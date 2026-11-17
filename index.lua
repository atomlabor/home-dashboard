-- Home Dashboard: Home Assistant on the X4.
-- Four areas in a bottom bar: Home (hero card, now playing, lights and switches
-- as tiles), Music (cover and controls), Sensors, Settings. First start opens the setup screen: sign in with the
-- Home Assistant user name, paste a token, or read homeassistant.txt.
-- While the app is open it polls every 30 s and redraws only on visible change.
local HA = require("app.ha")
local I18N = require("app.i18n")
local Icon = require("app.icons")

local S = { xs = 4, sm = 8, md = 16, lg = 24, xl = 40, margin = 20, radius = 12, radius_lg = 16,
  line = 2, line_bold = 3, hit = 44 }
local POLL_MS = 30000
local NAV_H = 80

local F, T
local lang = "en"
local tab = 1                      -- 1 home, 2 music, 3 sensors, 4 settings
local screen                       -- nil | "setup" | "pins" | "visible"
local page = {}
local npages = {}
local focus = 1
local keymode = false
local touch = false

local list, sensors, toggles, by_id = {}, {}, {}, {}
local pins = {}
local hidden = {}
local vis_sensors, vis_toggles = {}, {}
local media = {}
local cover = {}                   -- { pic = ..., big = image, small = image }
local at, err, note
local setup_msg, setup_bad
local sig = ""
local busy, alive, polling = false, true, false
local hits = {}
local files_path

local function view() return screen or ("tab" .. tab) end

-- data -----------------------------------------------------------------------

local function signature(l)
  local p = {}
  for i, e in ipairs(l) do p[i] = e.id .. "=" .. e.state .. (e.title and ("/" .. e.title) or "") end
  return table.concat(p, ";")
end

local function filter_visible()
  vis_sensors, vis_toggles = {}, {}
  for _, e in ipairs(sensors) do if not hidden[e.id] then vis_sensors[#vis_sensors + 1] = e end end
  for _, e in ipairs(toggles) do if not hidden[e.id] then vis_toggles[#vis_toggles + 1] = e end end
end

local function set_list(l)
  list = l
  sensors, toggles = HA.split_list(l)
  by_id = {}
  for _, e in ipairs(l) do by_id[e.id] = e end
  media = HA.media(l)
  filter_visible()
end

local function save_hidden(ctx)
  local ids = {}
  for id, h in pairs(hidden) do if h then ids[#ids + 1] = id end end
  table.sort(ids)
  HA.save(ctx, HA.HIDDEN, ids)
  filter_visible()
end

local function toggle_visible(ctx, e)
  hidden[e.id] = not hidden[e.id] or nil
  save_hidden(ctx)
  ctx:invalidate()
end

local function set_all_visible(ctx, show)
  hidden = {}
  if not show then
    for _, e in ipairs(sensors) do hidden[e.id] = true end
    for _, e in ipairs(toggles) do hidden[e.id] = true end
  end
  save_hidden(ctx)
  ctx:invalidate()
end

local function save_lock(ctx)
  local s = HA.lock_snap(list, pins)
  s.at = at
  HA.save(ctx, HA.LOCK, s)
end

local function apply(ctx, l)
  sig = signature(l)
  set_list(l)
  err = nil
  at = HA.hhmm(ctx)
  if note == T.connected then note = nil end
  HA.save(ctx, HA.CACHE, { list = l, at = at })
  save_lock(ctx)
end

local function current_media()
  if tab == 2 and not screen then return media[page.tab2 or 1] or media[1] end
  return media[1]
end

local function set_cover(ctx, pic, bytes)
  cover = { pic = pic }
  if bytes then
    cover.big = HA.decode_cover(ctx, bytes, 280)
    cover.small = HA.decode_cover(ctx, bytes, 64)
  end
end

local function load_cover(ctx)
  local m = current_media()
  if not m or m.pic == "" or m.pic == cover.pic or busy or not ctx.net then return end
  busy = true
  local pic = m.pic
  HA.fetch_cover(ctx, pic, function(ctx, bytes)
    busy = false
    set_cover(ctx, pic, bytes)
    if bytes and #bytes <= 200000 then
      HA.save(ctx, "ha_cover.json", { pic = pic })
      if ctx.storage then pcall(ctx.storage.write, ctx.storage, HA.COVER, bytes) end
    end
    ctx:invalidate()
  end)
end

local function refresh(ctx, done)
  if busy or not ctx.net then
    if done then done(ctx, false, "busy") end
    return
  end
  if not HA.ready() then
    err = "config"
    if done then done(ctx, false, "config") end
    return
  end
  busy = true
  HA.template(ctx, HA.TPL_DISCOVER, function(ctx, l, e)
    busy = false
    local before = sig .. "|" .. tostring(err) .. "|" .. tostring(at)
    if l then apply(ctx, l) else err = e end
    local after = sig .. "|" .. tostring(err) .. "|" .. tostring(at)
    if done then done(ctx, l ~= nil, e) end
    if before ~= after then ctx:invalidate() end
    load_cover(ctx)
  end)
end

local function schedule(ctx)
  if polling then return end
  polling = true
  ctx:after(POLL_MS, function(c)
    c = c or ctx
    polling = false
    if alive then
      refresh(c)
      schedule(c)
    end
  end)
end

local function do_toggle(ctx, e)
  if busy or e.pending then return end
  if e.state ~= "on" and e.state ~= "off" then return end
  local prev = e.state
  e.state = (prev == "on") and "off" or "on"
  e.pending = true
  busy = true
  ctx:invalidate()
  HA.toggle(ctx, e, function(ctx, ok, why)
    busy = false
    e.pending = nil
    if not ok then
      e.state = prev
      err = why
    end
    sig = signature(list)
    save_lock(ctx)
    ctx:invalidate()
    ctx:after(1500, function(c) refresh(c or ctx) end)
  end)
end

local function media_cmd(ctx, m, service)
  if busy or not m then return end
  busy = true
  if service == "media_play_pause" then
    m.state = (m.state == "playing") and "paused" or "playing"
    ctx:invalidate()
  end
  HA.service(ctx, "media_player", service, m.id, function(ctx, ok, why)
    busy = false
    if not ok then err = why end
    ctx:invalidate()
    ctx:after(1500, function(c) refresh(c or ctx) end)
  end)
end

local function is_pinned(id)
  for i, p in ipairs(pins) do if p == id then return i end end
  return nil
end

local function toggle_pin(ctx, e)
  local i = is_pinned(e.id)
  if i then
    table.remove(pins, i)
  elseif #pins < HA.MAX_PINS then
    pins[#pins + 1] = e.id
  else
    note = string.format(T.max_pins, HA.MAX_PINS)
    ctx:invalidate()
    return
  end
  note = nil
  HA.save(ctx, HA.PINS, pins)
  save_lock(ctx)
  ctx:invalidate()
end

-- setup ----------------------------------------------------------------------

local function ask(ctx, title, text, secret, fn)
  if not (ctx.input and ctx.input.text) then return end
  ctx.input:text({ title = title, text = text or "", secret = secret or false, max_bytes = 256 }, function(c, t)
    c = c or ctx
    if type(t) == "string" then fn(c, t) end
    c:invalidate("full")
  end)
end

local function connected(ctx)
  screen = nil
  tab = 1
  setup_msg, setup_bad = nil, nil
  note = T.connected
  ctx:invalidate("full")
end

local function verify(ctx)
  setup_msg, setup_bad = T.connecting, false
  ctx:invalidate()
  refresh(ctx, function(ctx, ok, e)
    if ok then connected(ctx)
    else
      setup_msg, setup_bad = I18N.error(T, e), true
      ctx:invalidate()
    end
  end)
end

local function edit_url(ctx)
  ask(ctx, T.ask_url, HA.base(), false, function(ctx, t)
    if HA.set_url(ctx, t) and HA.ready() then verify(ctx) end
  end)
end

local function start_login(ctx)
  ask(ctx, T.ask_user, HA.user() or "", false, function(ctx, user)
    user = user:gsub("^%s+", ""):gsub("%s+$", "")
    if user == "" then return end
    ctx:after(60, function(c)
      c = c or ctx
      ask(c, T.ask_pass, "", true, function(ctx, pass)
        if pass == "" then return end
        if busy then
          setup_msg, setup_bad = T.err_busy, true
          return
        end
        busy = true
        setup_msg, setup_bad = T.connecting, false
        HA.login(ctx, "", user, pass, function(ctx, ok, e)
          busy = false
          if ok then
            refresh(ctx)
            connected(ctx)
          else
            setup_msg, setup_bad = I18N.error(T, e), true
          end
          ctx:invalidate()
        end)
      end)
    end)
  end)
end

local function paste_token(ctx)
  ask(ctx, T.ask_token, "", true, function(ctx, t)
    if HA.set_token(ctx, t) then verify(ctx)
    else
      setup_msg, setup_bad = T.err_auth, true
    end
  end)
end

local function read_file(ctx)
  if HA.read_file(ctx) then verify(ctx)
  else
    setup_msg, setup_bad = T.err_file, true
    ctx:invalidate()
  end
end

-- lifecycle ------------------------------------------------------------------

function on_load(ctx)
  if type(ctx.state) == "table" and (ctx.state.lang == "de" or ctx.state.lang == "en") then
    lang = ctx.state.lang
  end
  T = I18N.get(lang)
  F = {
    hero = HA.font(ctx, 64), big = HA.font(ctx, 40), title = HA.font(ctx, 30), body = HA.font(ctx, 24),
    small = HA.font(ctx, 20), tiny = HA.font(ctx, 16),
  }
  HA.init(ctx)
  files_path = HA.files_path(ctx)
  touch = (ctx.input and ctx.input.pointer) and true or false
  keymode = not touch
  local hl = HA.load(ctx, HA.HIDDEN)
  if type(hl) == "table" then
    for _, id in ipairs(hl) do hidden[id] = true end
  end
  local c = HA.load(ctx, HA.CACHE)
  if c and type(c.list) == "table" then
    set_list(c.list)
    sig = signature(c.list)
    at = c.at
  end
  pins = HA.load_pins(ctx)
  local cm = HA.load(ctx, "ha_cover.json")
  if cm and cm.pic and media[1] and media[1].pic == cm.pic and ctx.storage then
    local ok, bytes = pcall(ctx.storage.read, ctx.storage, HA.COVER)
    if ok and type(bytes) == "string" then set_cover(ctx, cm.pic, bytes) end
  end
  if not HA.ready() then screen = "setup" end
  refresh(ctx)
  schedule(ctx)
end

function on_pause(ctx)
  alive = false
end

function on_resume(ctx)
  alive = true
  schedule(ctx)
  ctx:invalidate()
end

function on_leave(ctx)
  alive = false
  if type(ctx.state) == "table" then ctx.state.lang = lang end
end

-- drawing helpers --------------------------------------------------------------

local lh = HA.lh
local tw = HA.tw
local fit = HA.fit

local function add_hit(kind, x, y, w, h, extra, content)
  local r = { kind = kind, x = x, y = y, w = w, h = h }
  if extra then for k, v in pairs(extra) do r[k] = v end end
  if content then
    local n = 0
    for _, o in ipairs(hits) do if o.order then n = n + 1 end end
    r.order = n + 1
  end
  hits[#hits + 1] = r
  return r
end

local function text(g, x, y, s, f, o)
  o = o or {}
  o.font = f
  o.valign = o.valign or "middle"
  g:text(x, y, s, o)
end

local function card(g, x, y, w, h, filled)
  if filled then
    g:rect(x, y, w, h, { radius = S.radius_lg, fill = true })
  else
    g:rect(x, y, w, h, { radius = S.radius_lg, line_width = S.line })
  end
end

local function value_unit(g, x, y, e, fv, fu, maxw, c)
  local v = HA.value(e, T)
  local unit = (tonumber(e.state) and e.unit) or ""
  local uw = unit ~= "" and (tw(fu, unit) + S.xs) or 0
  v = fit(fv, v, maxw - uw)
  text(g, x, y, v, fv, { bold = true, tabular = true, color = c })
  if unit ~= "" then
    text(g, x + tw(fv, v) + S.xs + 2, y + (lh(fv) - lh(fu)) // 3, unit, fu, { color = c })
  end
end

-- pager for a view; returns the y below the section header
local function section(g, x, y, w, label, right, v)
  text(g, x, y + 18, fit(F.small, label, w // 2), F.small, { bold = true })
  local n = npages[v] or 1
  if n > 1 then
    local bs = 36
    local nx = x + w - bs
    local px = nx - bs - S.sm
    g:circle(px + bs // 2, y + 18, bs // 2, { line_width = S.line })
    Icon.draw(g, "back", px + 8, y + 8, 20, 15)
    add_hit("prev", px - 4, y - 4, bs + 8, S.hit)
    g:circle(nx + bs // 2, y + 18, bs // 2, { line_width = S.line })
    Icon.draw(g, "chevron", nx + 8, y + 8, 20, 15)
    add_hit("next", nx - 4, y - 4, bs + 8, S.hit)
    text(g, px - S.md, y + 18, (page[v] or 1) .. " / " .. n, F.small, { align = "right", tabular = true })
  elseif right then
    text(g, x + w, y + 18, right, F.small, { align = "right" })
  end
  return y + 36 + S.md
end

local function paginate(v, count, per)
  npages[v] = math.max(1, (count + per - 1) // per)
  page[v] = math.max(1, math.min(page[v] or 1, npages[v]))
  return (page[v] - 1) * per
end

local function status(ctx)
  if busy and not at then return "busy", T.connecting end
  if err and err ~= "busy" then return "off", T.offline .. (at and (" \u{00B7} " .. at) or "") end
  if at then return "live", T.live .. " \u{00B7} " .. at end
  return "busy", T.loading
end

local function header(ctx, g, W)
  local M = S.margin
  local y = M
  local th = lh(F.title)
  text(g, M, y + th // 2, T.title, F.title, { bold = true })
  local kind, s = status(ctx)
  local pw = tw(F.small, s) + 44
  local ph = 36
  local px, py = W - M - pw, y + th // 2 - ph // 2
  if kind == "live" then
    g:rect(px, py, pw, ph, { radius = ph // 2, fill = true })
    g:circle(px + 18, py + ph // 2, 5, { fill = true, color = 0 })
    text(g, px + 30, py + ph // 2, s, F.small, { bold = true, color = 0 })
  else
    g:rect(px, py, pw, ph, { radius = ph // 2, line_width = S.line })
    g:circle(px + 18, py + ph // 2, 5, { line_width = 2 })
    text(g, px + 30, py + ph // 2, s, F.small, { bold = true })
  end
  add_hit("refresh", px, py - 4, pw, ph + 8)
  y = y + th + 2
  local sub = note or HA.date_label(ctx.clock:now(), T)
  text(g, M, y + lh(F.small) // 2, fit(F.small, sub, W - 2 * M), F.small)
  return y + lh(F.small) + S.lg
end

local NAV_ICON = { "home", "note", "grid", "gear" }

local function navbar(ctx, g, W, H)
  local y0 = H - NAV_H
  g:rect(0, y0, W, 1, { fill = true })
  local iw = W // 4
  for i = 1, 4 do
    local cx = (i - 1) * iw + iw // 2
    local sel = (i == tab)
    local pw, ph = 64, 34
    if sel then g:rect(cx - pw // 2, y0 + 10, pw, ph, { radius = ph // 2, fill = true }) end
    Icon.draw(g, NAV_ICON[i], cx - 13, y0 + 14, 26, sel and 0 or 15)
    text(g, cx, y0 + 10 + ph + 16, fit(F.tiny, T.nav[i], iw - S.sm), F.tiny, { align = "center", bold = sel })
    add_hit("tab", (i - 1) * iw, y0, iw, NAV_H, { i = i })
  end
  return y0
end

local function message(g, x, y, w, s)
  for i, l in ipairs(HA.wrap(F.body, s, w - 2 * S.md, 6)) do
    text(g, x + w // 2, y + lh(F.body) // 2 + (i - 1) * lh(F.body), l, F.body, { align = "center" })
  end
end

-- tiles ----------------------------------------------------------------------

local function toggle_tile(g, x, y, w, h, e)
  local on = e.state == "on"
  local can = e.state == "on" or e.state == "off"
  local c = (on and not e.pending) and 0 or 15
  if on and not e.pending then card(g, x, y, w, h, true)
  else g:rect(x, y, w, h, { radius = S.radius_lg, line_width = e.pending and S.line_bold or S.line }) end
  Icon.draw(g, Icon.for_entity(e), x + S.md, y + S.md, 30, c, on)
  local st = e.pending and "\u{2026}" or HA.value(e, T)
  text(g, x + w - S.md, y + S.md + 15, st, F.small, { align = "right", bold = true, color = c })
  text(g, x + S.md, y + h - S.md - lh(F.body) // 2 + 2, fit(F.body, e.name, w - 2 * S.md), F.body, { color = c })
  return can
end

local function sensor_tile(g, x, y, w, h, e)
  card(g, x, y, w, h, false)
  Icon.draw(g, Icon.for_entity(e), x + S.md, y + S.md, 26, 15)
  text(g, x + S.md + 34, y + S.md + 13, fit(F.small, e.name, w - 2 * S.md - 34), F.small)
  value_unit(g, x + S.md, y + h - S.md - lh(F.big) // 2, e, F.big, F.small, w - 2 * S.md, 15)
end

local function grid(ctx, g, v, items, x, y, w, h, tile_h, draw_one, kind)
  local gap = 12
  local cols = 2
  local tile_w = (w - gap) // cols
  local rows = math.max(1, (h + gap) // (tile_h + gap))
  local first = paginate(v, #items, rows * cols)
  for k = 1, rows * cols do
    local e = items[first + k]
    if not e then break end
    local cx = x + ((k - 1) % cols) * (tile_w + gap)
    local cy = y + ((k - 1) // cols) * (tile_h + gap)
    local tappable = draw_one(g, cx, cy, tile_w, tile_h, e)
    if tappable ~= false then add_hit(kind, cx, cy, tile_w, tile_h, { e = e }, true) end
  end
end

-- views ----------------------------------------------------------------------

local function hero_items()
  local out = {}
  for _, id in ipairs(pins) do
    local e = by_id[id]
    if e and e.dom == "sensor" and not hidden[e.id] and #out < 3 then out[#out + 1] = e end
  end
  for _, e in ipairs(vis_sensors) do
    if #out >= 3 then break end
    local dup = false
    for _, o in ipairs(out) do if o == e then dup = true end end
    if not dup then out[#out + 1] = e end
  end
  return out
end

local function draw_home(ctx, g, x, y, w, bottom)
  if #list == 0 then
    message(g, x, y + S.xl, w, err and I18N.error(T, err) or T.loading)
    return
  end
  local hero = hero_items()
  if #hero > 0 then
    local h = 160
    card(g, x, y, w, h, false)
    local lw = (#hero > 1) and (w * 56 // 100) or w
    local e = hero[1]
    Icon.draw(g, Icon.for_entity(e), x + S.lg, y + S.lg, 28, 15)
    text(g, x + S.lg + 38, y + S.lg + 14, fit(F.small, e.name, lw - 2 * S.lg - 38), F.small)
    value_unit(g, x + S.lg, y + h - S.lg - lh(F.hero) // 2 + 4, e, F.hero, F.title, lw - 2 * S.lg, 15)
    if #hero > 1 then
      local rx = x + lw
      g:rect(rx, y + S.lg, 2, h - 2 * S.lg, { fill = true })
      local bh = (h - 2 * S.md) // 2
      for i = 2, #hero do
        local s = hero[i]
        local by = y + S.md + (i - 2) * bh
        local bx = rx + S.lg
        local bw = x + w - bx - S.md
        Icon.draw(g, Icon.for_entity(s), bx, by + 10, 20, 15)
        text(g, bx + 28, by + 20, fit(F.tiny, s.name, bw - 28), F.tiny)
        value_unit(g, bx, by + 20 + lh(F.title) // 2 + 12, s, F.title, F.tiny, bw, 15)
      end
    end
    add_hit("hero", x, y, w, h, nil, false)
    y = y + h + S.lg
  end
  local m = media[1]
  if m then
    local h = 88
    card(g, x, y, w, h, false)
    local cs = 64
    local cx, cy = x + 12, y + 12
    if cover.small and cover.pic == m.pic then
      g:image(cover.small, cx, cy)
    else
      g:rect(cx, cy, cs, cs, { radius = 8, fill = true })
      Icon.draw(g, "note", cx + 16, cy + 16, 32, 0)
    end
    local bs = 48
    local bx = x + w - S.md - bs
    local by = y + (h - bs) // 2
    g:circle(bx + bs // 2, by + bs // 2, bs // 2, { fill = true })
    Icon.draw(g, m.state == "playing" and "pause" or "play", bx + 12, by + 12, 24, 0)
    local tx = cx + cs + S.md
    local tw_ = bx - S.md - tx
    text(g, tx, y + 30, fit(F.body, m.title, tw_), F.body, { bold = true })
    local sub = m.artist ~= "" and m.artist or m.player
    if m.state ~= "playing" then sub = T.paused .. " \u{00B7} " .. sub end
    text(g, tx, y + 60, fit(F.small, sub, tw_), F.small)
    add_hit("open_music", x, y, bx - x - 4, h, nil, true)
    add_hit("media_pp", bx - 6, by - 6, bs + 12, bs + 12, { m = m }, true)
    y = y + h + S.lg
  end
  if #vis_toggles == 0 then return end
  local n_on = 0
  for _, e in ipairs(vis_toggles) do if e.state == "on" then n_on = n_on + 1 end end
  local th = 104
  paginate("tab1", #vis_toggles, 2 * math.max(1, (bottom - y - 52 + 12) // (th + 12)))
  y = section(g, x, y, w, T.lights, string.format(T.lights_on, n_on), "tab1")
  grid(ctx, g, "tab1", vis_toggles, x, y, w, bottom - y, th, toggle_tile, "toggle")
end

local function round_button(g, cx, cy, d, icon, filled, kind, m)
  if filled then
    g:circle(cx, cy, d // 2, { fill = true })
  else
    g:circle(cx, cy, d // 2, { line_width = S.line })
  end
  local is = d * 2 // 5
  Icon.draw(g, icon, cx - is // 2, cy - is // 2, is, filled and 0 or 15)
  add_hit(kind, cx - d // 2, cy - d // 2, d, d, { m = m }, true)
end

local function draw_music(ctx, g, x, y, w, bottom)
  if #media == 0 then
    local s = 96
    g:rect(x + (w - s) // 2, y + S.xl, s, s, { radius = 24, fill = true })
    Icon.draw(g, "note", x + (w - s) // 2 + 24, y + S.xl + 24, 48, 0)
    message(g, x, y + S.xl + s + S.lg, w, err and I18N.error(T, err) or T.nothing_playing)
    return
  end
  paginate("tab2", #media, 1)
  local m = media[page.tab2]
  y = section(g, x, y, w, fit(F.small, m.player, w - 160), nil, "tab2")
  local cs = math.max(120, math.min(280, w, bottom - y - 236))
  local cx = x + (w - cs) // 2
  if cover.big and cover.pic == m.pic then
    local iw, ih = HA.image_size(cover.big, cs)
    g:image(cover.big, cx + (cs - iw) // 2, y + (cs - ih) // 2)
    g:rect(cx, y, cs, cs, { radius = 4, line_width = 1 })
  else
    g:rect(cx, y, cs, cs, { radius = S.radius_lg, fill = true })
    Icon.draw(g, "note", cx + cs // 4, y + cs // 4, cs // 2, 0)
  end
  y = y + cs + S.md
  for _, l in ipairs(HA.wrap(F.title, m.title, w, 2)) do
    text(g, x + w // 2, y + lh(F.title) // 2, l, F.title, { align = "center", bold = true })
    y = y + lh(F.title)
  end
  if m.artist ~= "" then
    text(g, x + w // 2, y + lh(F.body) // 2, fit(F.body, m.artist, w), F.body, { align = "center" })
    y = y + lh(F.body)
  end
  local sub = m.album
  if m.state ~= "playing" then sub = T.paused .. ((sub ~= "") and (" \u{00B7} " .. sub) or "") end
  if sub ~= "" then
    text(g, x + w // 2, y + lh(F.small) // 2, fit(F.small, sub, w), F.small, { align = "center" })
    y = y + lh(F.small)
  end
  local cyc = math.min(bottom - 40, y + S.md + 38)
  local mid = x + w // 2
  round_button(g, mid - 100, cyc, 56, "prev", false, "media_prev", m)
  round_button(g, mid, cyc, 76, m.state == "playing" and "pause" or "play", true, "media_pp", m)
  round_button(g, mid + 100, cyc, 56, "next", false, "media_next", m)
end

local function draw_sensors(ctx, g, x, y, w, bottom)
  if #vis_sensors == 0 then
    message(g, x, y + S.xl, w, err and I18N.error(T, err) or (at and T.empty or T.loading))
    return
  end
  paginate("tab3", #vis_sensors, 2 * math.max(1, (bottom - y - 52 + 12) // (116 + 12)))
  y = section(g, x, y, w, T.sensors, tostring(#vis_sensors), "tab3")
  grid(ctx, g, "tab3", vis_sensors, x, y, w, bottom - y, 116, sensor_tile, "sensor")
end

local function account_text()
  local src = HA.source()
  if src == "login" then
    local u = HA.user()
    return u and string.format(T.acc_login, u) or T.acc_login_anon
  end
  if src == "token" then return T.acc_token end
  if src == "file" then return T.acc_file end
  if src == "install" then return T.acc_install end
  return T.acc_none
end

local function draw_rows(ctx, g, x, y, w, rows)
  local row_h, head_h = 56, 44
  local gy
  local function close(cy)
    if gy then g:rect(x, gy, w, cy - gy, { radius = S.radius_lg, line_width = S.line }) end
    gy = nil
  end
  for i, r in ipairs(rows) do
    if r.head then
      close(y)
      text(g, x + S.xs, y + head_h - 14, r.head, F.tiny, { bold = true })
      y = y + head_h
      gy = y
    else
      local mid = y + row_h // 2
      local tx = x + S.md
      if r.icon then
        Icon.draw(g, r.icon, x + S.md, mid - 12, 24, 15)
        tx = x + S.md + 36
      end
      local right = x + w - S.md
      if r.switch ~= nil then
        local sw, sh = 60, 32
        local sx = right - sw
        if r.switch then
          g:rect(sx, mid - sh // 2, sw, sh, { radius = sh // 2, fill = true })
          g:circle(sx + sw - sh // 2, mid, sh // 2 - 5, { fill = true, color = 0 })
        else
          g:rect(sx, mid - sh // 2, sw, sh, { radius = sh // 2, line_width = S.line })
          g:circle(sx + sh // 2, mid, sh // 2 - 6, { fill = true })
        end
        right = sx - S.md
      elseif r.check ~= nil then
        local cs = 30
        local cx = right - cs
        if r.check then
          g:rect(cx, mid - cs // 2, cs, cs, { radius = 8, fill = true })
          Icon.draw(g, "check", cx + 3, mid - cs // 2 + 3, cs - 6, 0)
        else
          g:rect(cx, mid - cs // 2, cs, cs, { radius = 8, line_width = S.line })
        end
        right = cx - S.md
      elseif r.chev then
        Icon.draw(g, "chevron", right - 18, mid - 9, 18, 15)
        right = right - 26
      end
      local title_w = tw(F.body, r.title)
      local val = r.value
      local vmax = val and math.max(0, right - tx - math.min(title_w, (right - tx) // 2) - S.md) or 0
      if val and val ~= "" then
        val = fit(F.small, val, vmax)
        text(g, right, mid, val, F.small, { align = "right", bold = r.bold_value })
        right = right - tw(F.small, val) - S.md
      end
      text(g, tx, mid, fit(F.body, r.title, right - tx), F.body)
      if r.id then add_hit("row", x, y, w, row_h, { id = r.id, e = r.e }, true) end
      local nxt = rows[i + 1]
      if nxt and not nxt.head then g:rect(tx, y + row_h - 1, x + w - tx, 1, { fill = true }) end
      y = y + row_h
    end
  end
  close(y)
  return y
end

local function draw_settings(ctx, g, x, y, w, bottom)
  local n = #pins
  local total = #sensors + #toggles
  local shown = #vis_sensors + #vis_toggles
  local rows = {
    { head = T.g_conn },
    { id = "server", icon = "globe", title = T.s_server, value = HA.host(), chev = true },
    { id = "account", icon = "user", title = T.s_account, value = account_text(), chev = true },
    { id = "test", icon = "refresh", title = T.s_test,
      value = err and I18N.error(T, err) or (at and string.format(T.asof, at) or "") },
    { head = T.g_display },
    { id = "visible", icon = "grid", title = T.s_visible, value = string.format(T.pins_count, shown, total), chev = true },
    { id = "lang", icon = "globe", title = T.lang, value = T.lang_name, chev = true },
    { head = T.g_lock },
  }
  if ctx.lockscreen then
    rows[#rows + 1] = { id = "lock", icon = "lock", title = T.use_lock, switch = ctx.lockscreen:is_default() }
  end
  rows[#rows + 1] = { id = "pins", icon = "home", title = T.s_pins,
    value = string.format(T.pins_count, n, HA.MAX_PINS), chev = true }
  local yy = draw_rows(ctx, g, x, y, w, rows)
  if yy + S.md + lh(F.tiny) <= bottom then
    text(g, x + w // 2, yy + S.md + lh(F.tiny) // 2, "Home Dashboard " .. HA.VERSION, F.tiny, { align = "center" })
  end
end

local function top_bar(ctx, g, W, title, can_back)
  local M = S.margin
  local y = M
  local th = lh(F.title)
  local tx = M
  if can_back then
    g:circle(M + 22, y + th // 2, 22, { line_width = S.line })
    Icon.draw(g, "back", M + 10, y + th // 2 - 12, 24, 15)
    add_hit("back", M, y + th // 2 - 22, 44, 44)
    tx = M + 44 + S.md
  end
  text(g, tx, y + th // 2, fit(F.title, title, W - tx - M), F.title, { bold = true })
  return y + math.max(th, 44) + S.lg
end

local function draw_pins(ctx, g, W, H)
  local M = S.margin
  local y = top_bar(ctx, g, W, T.pins_title, true)
  local w = W - 2 * M
  local info = #pins > 0 and string.format(T.pins_count, #pins, HA.MAX_PINS) or T.pins_auto
  if note then info = note end
  local items = {}
  for _, e in ipairs(sensors) do items[#items + 1] = e end
  for _, e in ipairs(toggles) do items[#items + 1] = e end
  local row_h = 56
  local per = math.max(1, (H - M - y - 52) // row_h)
  local first = paginate("pins", #items, per)
  y = section(g, M, y, w, fit(F.small, info, w - 140), nil, "pins")
  local rows = {}
  for k = 1, per do
    local e = items[first + k]
    if not e then break end
    local v = HA.value(e, T) .. ((tonumber(e.state) and e.unit ~= "") and (" " .. e.unit) or "")
    rows[#rows + 1] = { id = "pin", e = e, icon = Icon.for_entity(e), title = e.name, value = v,
      check = is_pinned(e.id) ~= nil }
  end
  if #rows > 0 then draw_rows(ctx, g, M, y, w, rows) end
end

local function draw_visible(ctx, g, W, H)
  local M = S.margin
  local y = top_bar(ctx, g, W, T.vis_title, true)
  local w = W - 2 * M
  local items = { { all = true } }
  for _, e in ipairs(sensors) do items[#items + 1] = e end
  for _, e in ipairs(toggles) do items[#items + 1] = e end
  local total = #sensors + #toggles
  local shown = #vis_sensors + #vis_toggles
  local row_h = 56
  local per = math.max(1, (H - M - y - 52) // row_h)
  local first = paginate("visible", #items, per)
  y = section(g, M, y, w, string.format(T.vis_count, shown, total), nil, "visible")
  local rows = {}
  for k = 1, per do
    local e = items[first + k]
    if not e then break end
    if e.all then
      local all = shown < total
      rows[#rows + 1] = { id = all and "all_on" or "all_off", icon = all and "check" or "grid",
        title = all and T.all_on or T.all_off }
    else
      local v = HA.value(e, T) .. ((tonumber(e.state) and e.unit ~= "") and (" " .. e.unit) or "")
      rows[#rows + 1] = { id = "vis", e = e, icon = Icon.for_entity(e), title = e.name, value = v,
        check = not hidden[e.id] }
    end
  end
  if #rows > 0 then draw_rows(ctx, g, M, y, w, rows) end
end

local function button(g, x, y, w, h, label, icon, primary, kind)
  if primary then
    g:rect(x, y, w, h, { radius = S.radius, fill = true })
  else
    g:rect(x, y, w, h, { radius = S.radius, line_width = S.line })
  end
  local c = primary and 0 or 15
  local lw = tw(F.body, label)
  local total = lw + (icon and 34 or 0)
  local sx = x + math.max(S.md, (w - total) // 2)
  if icon then
    Icon.draw(g, icon, sx, y + h // 2 - 12, 24, c)
    sx = sx + 34
  end
  text(g, sx, y + h // 2, fit(F.body, label, x + w - S.md - sx), F.body, { bold = primary, color = c })
  add_hit(kind, x, y, w, h, nil, true)
end

local function draw_setup(ctx, g, W, H)
  local M = S.margin
  local w = W - 2 * M
  local y = M
  if HA.ready() then
    g:circle(M + 22, y + 22, 22, { line_width = S.line })
    Icon.draw(g, "back", M + 10, y + 10, 24, 15)
    add_hit("back", M, y, 44, 44)
  end
  -- app mark
  local ms = 76
  local mx = (W - ms) // 2
  g:rect(mx, y, ms, ms, { radius = 20, fill = true })
  Icon.draw(g, "home", mx + 14, y + 12, 48, 0)
  y = y + ms + S.md
  for _, l in ipairs(HA.wrap(F.title, T.setup_title, w, 2)) do
    text(g, W // 2, y + lh(F.title) // 2, l, F.title, { align = "center", bold = true })
    y = y + lh(F.title)
  end
  y = y + S.xs
  for _, l in ipairs(HA.wrap(F.small, T.setup_text, w - S.lg, 3)) do
    text(g, W // 2, y + lh(F.small) // 2, l, F.small, { align = "center" })
    y = y + lh(F.small)
  end
  y = y + S.lg

  -- server field
  local fh = 72
  g:rect(M, y, w, fh, { radius = S.radius, line_width = S.line })
  text(g, M + S.md, y + 20, T.f_server, F.tiny, { bold = true })
  text(g, M + S.md, y + fh - 22, fit(F.body, HA.base(), w - 2 * S.md - 30), F.body)
  Icon.draw(g, "chevron", M + w - S.md - 18, y + fh // 2 - 9, 18, 15)
  add_hit("url", M, y, w, fh, nil, true)
  y = y + fh + S.md

  local bh = 56
  button(g, M, y, w, bh, T.b_login, "user", true, "login")
  y = y + bh + S.sm + S.xs
  button(g, M, y, w, bh, T.b_token, "key", false, "token")
  y = y + bh + S.sm + S.xs
  button(g, M, y, w, bh, T.b_file, "file", false, "file")
  y = y + bh + S.md

  local hint = files_path and string.format(T.file_hint, files_path) or T.file_hint_nopath
  for _, l in ipairs(HA.wrap(F.tiny, hint, w, 2)) do
    text(g, W // 2, y + lh(F.tiny) // 2, l, F.tiny, { align = "center" })
    y = y + lh(F.tiny)
  end
  if setup_msg then
    y = y + S.sm
    local lines = HA.wrap(F.small, setup_msg, w - 2 * S.md, 2)
    local mh = #lines * lh(F.small) + 2 * S.sm
    if y + mh > H - S.sm then y = H - S.sm - mh end
    if setup_bad then g:rect(M, y, w, mh, { radius = S.radius, line_width = S.line }) end
    for i, l in ipairs(lines) do
      text(g, W // 2, y + S.sm + (i - 1) * lh(F.small) + lh(F.small) // 2, l, F.small, { align = "center", bold = true })
    end
  end
end

function on_draw(ctx, g)
  local W, H = ctx.screen.width, ctx.screen.height
  g:clear()
  hits = {}
  if screen == "setup" then
    draw_setup(ctx, g, W, H)
  elseif screen == "pins" then
    draw_pins(ctx, g, W, H)
  elseif screen == "visible" then
    draw_visible(ctx, g, W, H)
  else
    local y = header(ctx, g, W)
    local bottom = navbar(ctx, g, W, H) - S.md
    local x, w = S.margin, W - 2 * S.margin
    if tab == 1 then draw_home(ctx, g, x, y, w, bottom)
    elseif tab == 2 then draw_music(ctx, g, x, y, w, bottom)
    elseif tab == 3 then draw_sensors(ctx, g, x, y, w, bottom)
    else draw_settings(ctx, g, x, y, w, bottom) end
  end
  -- focus ring for key-only devices
  if keymode then
    local n = 0
    for _, r in ipairs(hits) do if r.order then n = n + 1 end end
    if n > 0 and focus > n then focus = n end
    for _, r in ipairs(hits) do
      if r.order == focus then
        g:rect(r.x - 5, r.y - 5, r.w + 10, r.h + 10, { radius = S.radius_lg + 4, line_width = S.line })
      end
    end
  end
end

-- input ----------------------------------------------------------------------

local function go_page(ctx, d)
  local v = view()
  local p = (page[v] or 1) + d
  if p < 1 or p > (npages[v] or 1) then return false end
  page[v] = p
  focus = 1
  ctx:invalidate("full")
  if v == "tab2" then load_cover(ctx) end
  return true
end

local function set_tab(ctx, i)
  if i < 1 then i = 4 elseif i > 4 then i = 1 end
  if i ~= tab or screen then
    tab = i
    screen = nil
    focus = 1
    note = nil
    ctx:invalidate("full")
  end
end

local function open(ctx, s)
  screen = s
  focus = 1
  note = nil
  setup_msg, setup_bad = nil, nil
  ctx:invalidate("full")
end

local function close_screen(ctx)
  screen = nil
  focus = 1
  note = nil
  ctx:invalidate("full")
end

local function row_action(ctx, r)
  local id = r.id
  if id == "server" then edit_url(ctx)
  elseif id == "account" then open(ctx, "setup")
  elseif id == "test" then
    note = nil
    refresh(ctx)
    ctx:invalidate()
  elseif id == "lock" then
    if ctx.lockscreen:is_default() then
      if ctx.lockscreen.clear_default then ctx.lockscreen:clear_default() end
    else
      save_lock(ctx)
      ctx.lockscreen:set_default()
    end
    ctx:invalidate()
  elseif id == "pins" then open(ctx, "pins")
  elseif id == "visible" then open(ctx, "visible")
  elseif id == "vis" then toggle_visible(ctx, r.e)
  elseif id == "all_on" then set_all_visible(ctx, true)
  elseif id == "all_off" then set_all_visible(ctx, false)
  elseif id == "pin" then toggle_pin(ctx, r.e)
  elseif id == "lang" then
    lang = (lang == "en") and "de" or "en"
    T = I18N.get(lang)
    if type(ctx.state) == "table" then ctx.state.lang = lang end
    save_lock(ctx)
    ctx:invalidate("full")
  end
end

local function activate(ctx, r)
  local k = r.kind
  if k == "refresh" then
    note = nil
    refresh(ctx)
    ctx:invalidate()
  elseif k == "tab" then set_tab(ctx, r.i)
  elseif k == "prev" then go_page(ctx, -1)
  elseif k == "next" then go_page(ctx, 1)
  elseif k == "toggle" then do_toggle(ctx, r.e)
  elseif k == "open_music" then set_tab(ctx, 2); load_cover(ctx)
  elseif k == "media_pp" then media_cmd(ctx, r.m, "media_play_pause")
  elseif k == "media_next" then media_cmd(ctx, r.m, "media_next_track")
  elseif k == "media_prev" then media_cmd(ctx, r.m, "media_previous_track")
  elseif k == "row" then row_action(ctx, r)
  elseif k == "back" then close_screen(ctx)
  elseif k == "url" then edit_url(ctx)
  elseif k == "login" then start_login(ctx)
  elseif k == "token" then paste_token(ctx)
  elseif k == "file" then read_file(ctx)
  end
end

local function hit_at(x, y)
  for i = #hits, 1, -1 do
    local r = hits[i]
    if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then return r end
  end
  return nil
end

function on_input(ctx, ev)
  if ev.type == "pointer" then
    if ev.phase ~= "up" then return true end
    local gst = ev.gesture
    if gst == "swipe_left" or gst == "swipe_up" then go_page(ctx, 1) return true end
    if gst == "swipe_right" or gst == "swipe_down" then go_page(ctx, -1) return true end
    if gst ~= "tap" and gst ~= "double_tap" and gst ~= nil then return true end
    if keymode then keymode = false; ctx:invalidate() end
    local r = hit_at(ev.x or -1, ev.y or -1)
    if r then activate(ctx, r) end
    return true
  end

  if ev.type ~= "key" then return false end
  local key = ev.key
  if key == "back" then
    if screen and (screen ~= "setup" or HA.ready()) then
      if ev.phase == "up" then close_screen(ctx) end
      return true
    end
    return false
  end
  if ev.phase ~= "up" then return true end

  if touch then
    -- X4 Pro: the side keys turn pages
    if key == "down" or key == "right" then go_page(ctx, 1) end
    if key == "up" or key == "left" then go_page(ctx, -1) end
    return true
  end

  -- keys only (X4 Classic): left/right = area, up/down = focus, ok = act
  keymode = true
  local n = 0
  for _, r in ipairs(hits) do if r.order then n = n + 1 end end
  if key == "left" and not screen then set_tab(ctx, tab - 1)
  elseif key == "right" and not screen then set_tab(ctx, tab + 1)
  elseif key == "down" then
    if focus < n then focus = focus + 1; ctx:invalidate()
    else go_page(ctx, 1) end
  elseif key == "up" then
    if focus > 1 then focus = focus - 1; ctx:invalidate()
    else go_page(ctx, -1) end
  elseif key == "ok" then
    for _, r in ipairs(hits) do
      if r.order == focus then activate(ctx, r) break end
    end
  end
  return true
end
