-- Home Assistant access shared by the app and the lock screen.
-- Everything is fetched through POST /api/template, so one request returns
-- exactly the few fields the e-ink screen needs instead of the whole state dump.
local CFG = require("app.config")

local M = {}

M.CACHE = "ha_cache.json"   -- last full list (app)
M.LOCK = "ha_lock.json"     -- last lock-screen snapshot
M.PINS = "ha_pins.json"     -- entity ids chosen for the lock screen
M.HIDDEN = "ha_hidden.json" -- entity ids hidden from the dashboard
M.MAX_PINS = 6
M.VERSION = "1.3.0"
M.COVER = "ha_cover.bin"     -- last album cover bytes, shared with the lock screen
M.TOGGLE = { light = true, switch = true, input_boolean = true, fan = true }
-- used until something is chosen on the "Lock screen" page
M.DEFAULT_PINS = { "sensor.atomlabor_current_outd_temp_bt1", "sensor.meter_5006_temperature",
  "sensor.meter_5006_humidity" }

function M.load_pins(ctx)
  local p = M.load(ctx, M.PINS)
  if type(p) == "table" then return p end
  local d = {}
  for i, id in ipairs(M.DEFAULT_PINS) do d[i] = id end
  return d
end

local PRIO = { temperature = 1, humidity = 2, carbon_dioxide = 3, pm25 = 4, power = 5, energy = 6,
  illuminance = 7, pressure = 8, battery = 9 }
local CLASSES = "['temperature','humidity','carbon_dioxide','pm25','power','energy','illuminance','pressure','battery']"
local SEP, NL = "\t", "\n"

local function set(v, mark)
  return type(v) == "string" and v:match("%S") ~= nil and v ~= mark
end

-- Credentials --------------------------------------------------------------
-- Four ways in, first match wins:
--   1. set up on the device (login with user name + password, or a pasted token),
--      kept in private storage
--   2. homeassistant.txt in the app's visible folder ("url = ..." / "token = ...")
--   3. the install-time configuration
-- A login keeps only the refresh token, never the password; short-lived access
-- tokens are fetched with it when needed.
M.CRED_FILE = "homeassistant.txt"
M.CRED_STORE = "ha_cred.json"
M.CLIENT = "https://homedash.atomlabor.de/"
local OV = {}

local function trim(x)
  x = x:gsub("^%s+", "")
  x = x:gsub("%s+$", "")
  return x
end

local function norm(u)
  u = tostring(u or ""):gsub("%s", "")
  u = u:gsub("/+$", "")
  if u ~= "" and not u:match("^https?://") then u = "https://" .. u end
  return u
end
M.norm = norm

local function parse_cred(s)
  local url, token
  for raw in s:gmatch("[^\r\n]+") do
    local line = trim(raw)
    local k, v = line:match("^(%a+)%s*[=:]%s*(.+)$")
    k = k and k:lower()
    if k == "url" then url = trim(v)
    elseif k == "token" then token = trim(v)
    elseif line:match("^https?://") then url = line
    elseif #line >= 40 and not line:find("%s") then token = line end
  end
  return url, token
end

local function persist(ctx)
  M.save(ctx, M.CRED_STORE, OV)
end

function M.read_file(ctx)
  if not (ctx.files and ctx.files.read) then return false end
  local ok, s = pcall(ctx.files.read, ctx.files, M.CRED_FILE)
  if not (ok and type(s) == "string") then return false end
  local u, t = parse_cred(s)
  if not t then return false end
  OV = { url = u and norm(u) or OV.url, token = t, src = "file" }
  persist(ctx)
  return true
end

function M.init(ctx)
  local c = M.load(ctx, M.CRED_STORE)
  if c and (c.token or c.refresh) then
    OV = c
    return
  end
  OV = (c and c.url) and { url = c.url } or {}
  M.read_file(ctx)
end

function M.files_path(ctx)
  if not ctx.files then return nil end
  local p = ctx.files.path
  if type(p) == "function" then
    local ok, v = pcall(p, ctx.files)
    p = ok and v or nil
  end
  if type(p) == "string" and p ~= "" then return p end
  return nil
end

local function token()
  if OV.token then return OV.token end
  if OV.refresh then return OV.access end
  if set(CFG.token, CFG.marks.token) then return CFG.token end
  return nil
end

function M.ready()
  return OV.token ~= nil or OV.refresh ~= nil or set(CFG.token, CFG.marks.token)
end

-- "login" | "token" | "file" | "install" | nil
function M.source()
  if OV.refresh then return "login" end
  if OV.token then return OV.src == "file" and "file" or "token" end
  if set(CFG.token, CFG.marks.token) then return "install" end
  return nil
end

function M.user() return OV.user end

function M.base()
  local u = OV.url
  if not set(u, "") then u = CFG.url end
  if not set(u, CFG.marks.url) then u = "" end
  return norm(u)
end

function M.host()
  return (M.base():gsub("^https?://", ""))
end

function M.set_url(ctx, u)
  u = norm(u)
  if u == "" then return false end
  OV.url = u
  persist(ctx)
  return true
end

function M.set_token(ctx, t)
  t = trim(tostring(t or ""))
  if #t < 20 then return false end
  OV = { url = OV.url, token = t, src = "token" }
  persist(ctx)
  return true
end

function M.logout(ctx)
  OV = { url = OV.url }
  persist(ctx)
end

local function now_s(ctx)
  local t = ctx.clock:now()
  if not (t and t.valid) then return 0 end
  local y, m, d = t.year, t.month, t.day
  if m <= 2 then y = y - 1 end
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local doy = (153 * ((m + 9) % 12) + 2) // 5 + d - 1
  local days = era * 146097 + yoe * 365 + yoe // 4 - yoe // 100 + doy - 719468
  return days * 86400 + t.hour * 3600 + t.minute * 60 + (t.second or 0)
end

local function enc(v)
  return (tostring(v):gsub("[^%w%-%._~]", function(ch) return string.format("%%%02X", ch:byte()) end))
end

local function form(t)
  local p = {}
  for k, v in pairs(t) do p[#p + 1] = enc(k) .. "=" .. enc(v) end
  return table.concat(p, "&")
end

local function decode(ctx, res)
  if not (res and type(res.body) == "string" and res.body ~= "") then return nil end
  local ok, d = pcall(ctx.json.decode, ctx.json, res.body)
  if ok and type(d) == "table" then return d end
  return nil
end

-- make sure a usable access token exists; cb(ctx, ok, err)
local function authorize(ctx, cb, force)
  if not OV.refresh then
    if token() then cb(ctx, true) else cb(ctx, false, "config") end
    return
  end
  if not force and OV.access and OV.exp and now_s(ctx) < OV.exp - 60 then
    cb(ctx, true)
    return
  end
  local started = ctx.net:request({
    url = M.base() .. "/auth/token", method = "POST", timeout_ms = 12000,
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
    body = form({ grant_type = "refresh_token", refresh_token = OV.refresh, client_id = M.CLIENT }),
  }, function(ctx, res)
    local d = decode(ctx, res)
    if res.ok and res.status == 200 and d and d.access_token then
      OV.access = d.access_token
      OV.exp = now_s(ctx) + (tonumber(d.expires_in) or 1800)
      persist(ctx)
      cb(ctx, true)
    elseif res.status == 400 or res.status == 401 or res.status == 403 then
      cb(ctx, false, "auth")
    else
      cb(ctx, false, M.err(res))
    end
  end)
  if not started then cb(ctx, false, "busy") end
end

local function headers()
  return { Authorization = "Bearer " .. (token() or ""):gsub("%s", ""), ["Content-Type"] = "application/json" }
end

-- authorized request; cb(ctx, res) is always called exactly once
function M.call(ctx, req, cb, retried)
  authorize(ctx, function(ctx, ok, e)
    if not ok then
      cb(ctx, { ok = false, err = e })
      return
    end
    req.headers = headers()
    local started = ctx.net:request(req, function(ctx, res)
      if res.status == 401 and OV.refresh and not retried then
        OV.access = nil
        M.call(ctx, req, cb, true)
      else
        cb(ctx, res)
      end
    end)
    if not started then cb(ctx, { ok = false, err = "busy" }) end
  end)
end

-- Home Assistant login flow, the same one the companion apps use.
-- cb(ctx, ok, err) with err "invalid_auth" | "mfa" | "busy" | network errors
function M.login(ctx, url, user, pass, cb)
  local base = norm(url ~= "" and url or M.base())
  local function fail(e) cb(ctx, false, e) end
  local body1 = '{"client_id":"' .. M.CLIENT .. '","handler":["homeassistant",null],' ..
    '"redirect_uri":"' .. M.CLIENT .. '","type":"authorize"}'
  local s1 = ctx.net:request({ url = base .. "/auth/login_flow", method = "POST", timeout_ms = 15000,
    headers = { ["Content-Type"] = "application/json" }, body = body1 }, function(ctx, r1)
    local d1 = decode(ctx, r1)
    if not (r1.ok and r1.status == 200 and d1 and d1.flow_id) then return fail(M.err(r1)) end
    local s2 = ctx.net:request({ url = base .. "/auth/login_flow/" .. d1.flow_id, method = "POST", timeout_ms = 15000,
      headers = { ["Content-Type"] = "application/json" },
      body = ctx.json:encode({ client_id = M.CLIENT, username = user, password = pass }) }, function(ctx, r2)
      local d2 = decode(ctx, r2)
      if not (r2.ok and d2) then return fail(M.err(r2)) end
      if d2.type == "form" then
        if d2.step_id == "mfa" then return fail("mfa") end
        return fail("invalid_auth")
      end
      if d2.type ~= "create_entry" or type(d2.result) ~= "string" then
        return fail(type(d2.reason) == "string" and d2.reason or "invalid_auth")
      end
      local s3 = ctx.net:request({ url = base .. "/auth/token", method = "POST", timeout_ms = 15000,
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        body = form({ grant_type = "authorization_code", code = d2.result, client_id = M.CLIENT }) }, function(ctx, r3)
        local d3 = decode(ctx, r3)
        if not (r3.ok and r3.status == 200 and d3 and d3.refresh_token) then return fail(M.err(r3)) end
        OV = { url = base, refresh = d3.refresh_token, access = d3.access_token,
          exp = now_s(ctx) + (tonumber(d3.expires_in) or 1800), user = user, src = "login" }
        persist(ctx)
        cb(ctx, true)
      end)
      if not s3 then fail("busy") end
    end)
    if not s2 then fail("busy") end
  end)
  if not s1 then fail("busy") end
end

-- one output line per entity: id, state, unit, name, device class
local function row(id, state, unit, name, cls)
  return "{{ " .. id .. " }}" .. SEP .. "{{ " .. state .. " }}" .. SEP .. "{{ " .. unit .. " }}" .. SEP ..
    "{{ " .. name .. " }}" .. SEP .. "{{ " .. cls .. " }}" .. NL
end

local S_ROW = row("s.entity_id", "s.state", "s.attributes.get('unit_of_measurement','')", "s.name",
  "s.attributes.get('device_class','')")
local ON_ROW = row("s.entity_id", "s.state", "''", "s.name", "'__on'")
-- media players: id, state, artist, title, "__media", picture, album, player name
local MEDIA_ROW = "{{ s.entity_id }}" .. SEP .. "{{ s.state }}" .. SEP .. "{{ s.attributes.get('media_artist','') }}" ..
  SEP .. "{{ s.attributes.get('media_title','') }}" .. SEP .. "__media" .. SEP ..
  "{{ s.attributes.get('entity_picture','') }}" .. SEP .. "{{ s.attributes.get('media_album_name','') }}" .. SEP ..
  "{{ s.name }}" .. NL
local TPL_MEDIA = "{% for s in states.media_player if s.state in ['playing','paused'] and s.attributes.get('media_title') %}" ..
  "{% if loop.index <= 4 %}" .. MEDIA_ROW .. "{% endif %}{% endfor %}"

M.TPL_DISCOVER =
  "{% for s in (states.light|list + states.switch|list + states.input_boolean|list + states.fan|list) %}" ..
  "{% if loop.index <= 40 %}" .. S_ROW .. "{% endif %}{% endfor %}" ..
  "{% for s in states.sensor if s.attributes.get('device_class') in " .. CLASSES ..
  " and s.state not in ['unknown','unavailable'] %}" ..
  "{% if loop.index <= 48 %}" .. S_ROW .. "{% endif %}{% endfor %}" .. TPL_MEDIA

local function clean_id(id)
  return type(id) == "string" and id:match("^[%w_]+%.[%w_]+$") and id or nil
end

-- pinned entities, plus every light that is on
function M.tpl_lock(pins)
  local ids = {}
  for _, raw in ipairs(pins) do
    local id = clean_id(raw)
    if id then ids[#ids + 1] = "'" .. id .. "'" end
  end
  return "{% for e in [" .. table.concat(ids, ",") .. "] %}" ..
    row("e", "states(e)", "state_attr(e,'unit_of_measurement') or ''", "state_attr(e,'friendly_name') or e",
      "state_attr(e,'device_class') or ''") ..
    "{% endfor %}" ..
    "{% for s in states.light if s.state == 'on' %}{% if loop.index <= 12 %}" .. ON_ROW .. "{% endif %}{% endfor %}" ..
    TPL_MEDIA
end

local function split(line)
  local out, i = {}, 1
  while true do
    local j = line:find(SEP, i, true)
    if not j then
      out[#out + 1] = line:sub(i)
      return out
    end
    out[#out + 1] = line:sub(i, j - 1)
    i = j + 1
  end
end

function M.parse(body)
  local list = {}
  for line in body:gmatch("[^\n]+") do
    local f = split(line)
    local id = clean_id(f[1])
    if id then
      local name = f[4] or ""
      if name == "" or name == "None" then name = id end
      local unit = f[3] or ""
      if unit == "None" then unit = "" end
      local e = { id = id, dom = id:match("^([%w_]+)%."), state = f[2] or "", unit = unit,
        name = name, cls = f[5] or "" }
      if e.cls == "__media" then
        e.artist = unit
        e.title = (f[4] ~= "None" and f[4]) or ""
        e.pic = (f[6] ~= "None" and f[6]) or ""
        e.album = (f[7] ~= "None" and f[7]) or ""
        e.player = (f[8] and f[8] ~= "None" and f[8]) or id
      end
      list[#list + 1] = e
    end
  end
  return list
end

function M.err(res)
  if type(res) ~= "table" then return "error" end
  if res.status == 401 or res.status == 403 then return "auth" end
  if res.status == 429 then return "banned" end
  if res.err then return res.err end
  if res.status then return "http_" .. tostring(res.status) end
  return "error"
end

-- cb(ctx, list) on success, cb(ctx, nil, err) on failure; always called once
function M.template(ctx, tpl, cb)
  if not M.ready() then
    cb(ctx, nil, "config")
    return
  end
  M.call(ctx, { url = M.base() .. "/api/template", method = "POST", timeout_ms = 12000,
    body = ctx.json:encode({ template = tpl }) }, function(ctx, res)
    if res.ok and res.status == 200 and type(res.body) == "string" then
      cb(ctx, M.parse(res.body))
    else
      cb(ctx, nil, M.err(res))
    end
  end)
end

-- call a Home Assistant service for one entity; cb(ctx, ok, err), always called once
function M.service(ctx, domain, service, id, cb)
  M.call(ctx, { url = M.base() .. "/api/services/" .. domain .. "/" .. service, method = "POST", timeout_ms = 10000,
    body = ctx.json:encode({ entity_id = id }) }, function(ctx, res)
    cb(ctx, res.ok and res.status == 200, M.err(res))
  end)
end

function M.toggle(ctx, e, cb)
  M.service(ctx, e.dom, "toggle", e.id, cb)
end

-- media players in the list, playing first, Spotify before others
function M.media(list)
  local out = {}
  for _, e in ipairs(list) do if e.cls == "__media" then out[#out + 1] = e end end
  table.sort(out, function(a, b)
    local pa = (a.state == "playing" and 0 or 2) + (a.id:find("spotify", 1, true) and 0 or 1)
    local pb = (b.state == "playing" and 0 or 2) + (b.id:find("spotify", 1, true) and 0 or 1)
    if pa ~= pb then return pa < pb end
    return a.id < b.id
  end)
  return out
end

-- where to load a cover from: Spotify CDN pictures in 300 px instead of 640 px,
-- Home Assistant proxy paths relative to the server
function M.cover_url(pic)
  if type(pic) ~= "string" or pic == "" then return nil end
  if pic:match("^https?://") then
    return (pic:gsub("ab67616d0000b273", "ab67616d00001e02")), false
  end
  return M.base() .. pic, true
end

-- cb(ctx, body) or cb(ctx, nil, err); the HA token is sent only to Home Assistant
function M.fetch_cover(ctx, pic, cb)
  local url, own = M.cover_url(pic)
  if not url then cb(ctx, nil, "none") return end
  local req = { url = url, method = "GET", timeout_ms = 15000 }
  local function done(ctx, res)
    if res.ok and res.status == 200 and type(res.body) == "string" and #res.body > 0 then cb(ctx, res.body)
    else cb(ctx, nil, M.err(res)) end
  end
  if own then
    M.call(ctx, req, done)
  else
    local started = ctx.net:request(req, done)
    if not started then cb(ctx, nil, "busy") end
  end
end

-- decode cover bytes to a runtime image of at most size x size; nil if not possible
function M.decode_cover(ctx, bytes, size)
  if not (bytes and ctx.image and ctx.image.decode) then return nil end
  local ok, img = pcall(ctx.image.decode, ctx.image, bytes, { max_w = size, max_h = size })
  if ok and img then return img end
  return nil
end

function M.image_size(img, fallback)
  if type(img) == "table" or type(img) == "userdata" then
    local ok, w, h = pcall(function()
      if img.width then return img.width, img.height end
      if img.w then return img.w, img.h end
      if img.size then return img:size() end
    end)
    if ok and w then return w, h or w end
  end
  return fallback, fallback
end

-- storage --------------------------------------------------------------------

function M.load(ctx, name)
  if not ctx.storage then return nil end
  local ok, s = pcall(ctx.storage.read, ctx.storage, name)
  if not ok or type(s) ~= "string" or s == "" then return nil end
  local ok2, v = pcall(ctx.json.decode, ctx.json, s)
  if ok2 and type(v) == "table" then return v end
  return nil
end

function M.save(ctx, name, v)
  if ctx.storage and v then pcall(ctx.storage.write, ctx.storage, name, ctx.json:encode(v)) end
end

-- sorting and formatting -----------------------------------------------------

function M.split_list(list)
  local sensors, toggles = {}, {}
  for _, e in ipairs(list) do
    if e.dom == "sensor" then sensors[#sensors + 1] = e
    elseif M.TOGGLE[e.dom] then toggles[#toggles + 1] = e end
  end
  table.sort(sensors, function(a, b)
    local pa, pb = PRIO[a.cls] or 20, PRIO[b.cls] or 20
    if pa ~= pb then return pa < pb end
    return a.name:lower() < b.name:lower()
  end)
  local DOM = { light = 1, switch = 2, fan = 3, input_boolean = 4 }
  table.sort(toggles, function(a, b)
    if a.dom ~= b.dom then return (DOM[a.dom] or 9) < (DOM[b.dom] or 9) end
    return a.name:lower() < b.name:lower()
  end)
  return sensors, toggles
end

-- snapshot for the lock screen: up to MAX_PINS tiles and the lights that are on
function M.lock_snap(list, pins)
  local by, tiles, on, seen = {}, {}, {}, {}
  for _, e in ipairs(list) do
    if e.cls ~= "__on" and e.cls ~= "__media" then by[e.id] = e end
    if (e.cls == "__on" or (e.dom == "light" and e.state == "on")) and not seen[e.id] then
      seen[e.id] = true
      on[#on + 1] = e.name
    end
  end
  if pins and #pins > 0 then
    for _, id in ipairs(pins) do
      local e = by[id]
      if e and #tiles < M.MAX_PINS then
        tiles[#tiles + 1] = { name = e.name, state = e.state, unit = e.unit, dom = e.dom, cls = e.cls }
      end
    end
  end
  if #tiles == 0 then
    local sensors = M.split_list(list)
    for i = 1, math.min(M.MAX_PINS, #sensors) do
      local e = sensors[i]
      tiles[#tiles + 1] = { name = e.name, state = e.state, unit = e.unit, dom = e.dom, cls = e.cls }
    end
  end
  table.sort(on, function(a, b) return a:lower() < b:lower() end)
  local m = M.media(list)[1]
  local media = m and { title = m.title, artist = m.artist, state = m.state, pic = m.pic } or nil
  return { tiles = tiles, on = on, media = media }
end

function M.value(e, T)
  local s = tostring(e.state or "")
  if s == "on" then return T.on end
  if s == "off" then return T.off end
  if s == "" or s == "unknown" or s == "unavailable" then return T.na end
  local n = tonumber(s)
  if n then
    if math.abs(n) >= 100 or n == math.floor(n) then
      s = string.format("%.0f", n)
    else
      s = string.format("%.1f", n)
    end
    if s == "-0" then s = "0" end
    if T.comma then s = s:gsub("%.", ",") end
  end
  return s
end

function M.hhmm(ctx)
  local t = ctx.clock:now()
  if t and t.valid then return string.format("%02d:%02d", t.hour, t.minute) end
  return nil
end

local function days_from_civil(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = (153 * mp + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end

function M.date_label(t, T)
  if not (t and t.valid) then return "" end
  local wd = (days_from_civil(t.year, t.month, t.day) + 4) % 7 -- 1970-01-01 was a Thursday
  return T.date(T.wd[wd + 1], t.day, T.mon[t.month])
end

-- text helpers ---------------------------------------------------------------

function M.lh(f) return (f and f.line_height) or 24 end

function M.tw(f, s)
  local w = f:measure(s)
  if type(w) == "table" then w = w.w or w.width end
  return tonumber(w) or 0
end

local function chars(s)
  local out = {}
  if utf8 then
    local ok = pcall(function()
      for _, c in utf8.codes(s) do out[#out + 1] = utf8.char(c) end
    end)
    if ok then return out end
    out = {}
  end
  for i = 1, #s do out[#out + 1] = s:sub(i, i) end
  return out
end

function M.fit(f, s, maxw)
  s = tostring(s or "")
  if maxw <= 0 then return "" end
  if M.tw(f, s) <= maxw then return s end
  local ell = "\u{2026}"
  local cs = chars(s)
  local lo, hi = 0, #cs
  while lo < hi do
    local mid = (lo + hi + 1) // 2
    if M.tw(f, table.concat(cs, "", 1, mid) .. ell) <= maxw then lo = mid else hi = mid - 1 end
  end
  return table.concat(cs, "", 1, lo) .. ell
end

-- word wrap into at most max_lines lines
function M.wrap(f, s, maxw, max_lines)
  local lines, cur = {}, ""
  for word in tostring(s):gmatch("%S+") do
    local cand = cur == "" and word or (cur .. " " .. word)
    if M.tw(f, cand) <= maxw or cur == "" then
      cur = cand
    else
      lines[#lines + 1] = cur
      cur = word
    end
  end
  if cur ~= "" then lines[#lines + 1] = cur end
  if max_lines and #lines > max_lines then
    local keep = {}
    for i = 1, max_lines do keep[i] = lines[i] end
    keep[max_lines] = M.fit(f, keep[max_lines] .. " \u{2026}", maxw)
    lines = keep
  end
  for i, l in ipairs(lines) do lines[i] = M.fit(f, l, maxw) end
  return lines
end

function M.font(ctx, px)
  local f = ctx.fonts.size and ctx.fonts:size(px)
  if f then return f end
  if px >= 30 then return ctx.fonts.large end
  if px >= 24 then return ctx.fonts.medium end
  return ctx.fonts.small
end

return M
