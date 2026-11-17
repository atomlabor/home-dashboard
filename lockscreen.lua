-- Lock screen: date, large clock, up to six Home Assistant values as tiles and
-- the lights that are on. The clock redraws every minute (interval_sec); every
-- net_interval_sec the session goes online and fetches fresh values with a
-- single template request (after renewing the sign-in if needed). On failure
-- the stored values stay on screen with an "offline" marker top right and the
-- time of the last success.
local HA = require("app.ha")
local I18N = require("app.i18n")
local Icon = require("app.icons")

local S = { xs = 4, sm = 8, md = 16, lg = 24, margin = 24, radius_lg = 16, line = 2 }
local F, T, snap

function on_load(ctx)
  local lang = (type(ctx.state) == "table" and ctx.state.lang) or "en"
  T = I18N.get(lang)
  F = {
    clock = HA.font(ctx, 96), date = HA.font(ctx, 24), label = HA.font(ctx, 20),
    big = HA.font(ctx, 40), body = HA.font(ctx, 24), tiny = HA.font(ctx, 16), name = HA.font(ctx, 16),
  }
  snap = HA.load(ctx, HA.LOCK) or { tiles = {}, on = {} }
  HA.init(ctx)

  if not (ctx.lock and ctx.lock.net and ctx.net) then return end
  if not HA.ready() then
    snap.err = "config"
    return
  end
  local pins = HA.load_pins(ctx)
  local tpl = (#pins > 0) and HA.tpl_lock(pins) or HA.TPL_DISCOVER
  HA.template(ctx, tpl, function(ctx, list, e)
    if list then
      snap = HA.lock_snap(list, pins)
      snap.at = HA.hhmm(ctx)
      local m = snap.media
      local meta = HA.load(ctx, "ha_cover.json")
      if m and m.pic ~= "" and not (meta and meta.pic == m.pic) then
        HA.save(ctx, HA.LOCK, snap)
        HA.fetch_cover(ctx, m.pic, function(ctx, bytes)
          if bytes and #bytes <= 200000 and ctx.storage then
            pcall(ctx.storage.write, ctx.storage, HA.COVER, bytes)
            HA.save(ctx, "ha_cover.json", { pic = m.pic })
          end
          ctx.lock:done()
        end)
        return
      end
    else
      snap.failed = true
      snap.err = e
    end
    HA.save(ctx, HA.LOCK, snap)
    ctx.lock:done()
  end)
end

local lh, tw, fit = HA.lh, HA.tw, HA.fit

local function text(g, x, y, s, f, o)
  o = o or {}
  o.font = f
  o.valign = o.valign or "middle"
  g:text(x, y, s, o)
end

local function offline_mark(g, W, y)
  local s = T.offline
  local w = tw(F.tiny, s) + 34
  local h = 28
  g:rect(W - S.margin - w, y, w, h, { radius = h // 2, line_width = S.line })
  g:circle(W - S.margin - w + 14, y + h // 2, 4, { line_width = 2 })
  text(g, W - S.margin - w + 24, y + h // 2, s, F.tiny, { bold = true })
end

function on_draw(ctx, g)
  local W, H = ctx.screen.width, ctx.screen.height
  local M = S.margin
  local cw = W - 2 * M
  g:clear()

  local t = ctx.clock:now()
  local y = M

  -- date and offline marker
  text(g, M, y + lh(F.date) // 2, fit(F.date, HA.date_label(t, T), cw - 130), F.date, { bold = true })
  if snap.failed then offline_mark(g, W, y + (lh(F.date) - 28) // 2) end
  y = y + lh(F.date)

  -- clock
  local hm = (t and t.valid) and string.format("%02d:%02d", t.hour, t.minute) or "--:--"
  text(g, W // 2, y + lh(F.clock) // 2, hm, F.clock, { align = "center", bold = true, tabular = true })
  y = y + lh(F.clock) + S.sm

  -- section head
  local l = lh(F.label)
  Icon.draw(g, "home", M, y + l // 2 - 11, 22, 15)
  text(g, M + 30, y + l // 2, T.lock_home, F.label, { bold = true })
  if snap.at then
    text(g, W - M, y + l // 2, string.format(T.asof, snap.at), F.label, { align = "right" })
  end
  y = y + l + S.md

  -- tiles
  local tiles = snap.tiles or {}
  if #tiles == 0 then
    local msg = (snap.err == "config") and T.err_short or (snap.err == "auth" and T.err_auth or T.loading)
    for _, s in ipairs(HA.wrap(F.body, msg, cw, 4)) do
      text(g, M, y + lh(F.body) // 2, s, F.body)
      y = y + lh(F.body)
    end
    y = y + S.lg
  else
    local gap = 12
    local cols = 2
    local tile_w = (cw - gap) // cols
    local name_w = tile_w - 2 * S.md - 26
    local nlines = 1
    for _, e in ipairs(tiles) do
      if #HA.wrap(F.name, e.name, name_w, 2) > 1 then nlines = 2 end
    end
    local name_h = math.max(20, nlines * lh(F.name))
    local tile_h = S.md - 4 + name_h + S.xs + lh(F.big) + S.xs
    for i, e in ipairs(tiles) do
      local cx = M + ((i - 1) % cols) * (tile_w + gap)
      local cy = y + ((i - 1) // cols) * (tile_h + gap)
      g:rect(cx, cy, tile_w, tile_h, { radius = S.radius_lg, line_width = S.line })
      local kind = Icon.CLASS[e.cls] or (e.dom == "sensor" and "gauge" or Icon.DOMAIN[e.dom] or "gauge")
      local ny = cy + S.md - 4
      Icon.draw(g, kind, cx + S.md, ny + (lh(F.name) - 18) // 2, 18, 15, e.state == "on")
      for j, nl in ipairs(HA.wrap(F.name, e.name, name_w, 2)) do
        text(g, cx + S.md + 26, ny + (j - 1) * lh(F.name) + lh(F.name) // 2, nl, F.name)
      end
      local v = HA.value(e, T)
      local unit = (tonumber(e.state) and e.unit) or ""
      local uw = unit ~= "" and (tw(F.label, unit) + S.xs) or 0
      v = fit(F.big, v, tile_w - 2 * S.md - uw)
      local vy = cy + tile_h - S.xs - lh(F.big) // 2
      text(g, cx + S.md, vy, v, F.big, { bold = true, tabular = true })
      if unit ~= "" then
        text(g, cx + S.md + tw(F.big, v) + S.xs + 2, vy + (lh(F.big) - lh(F.label)) // 3, unit, F.label)
      end
    end
    local rows = (#tiles + cols - 1) // cols
    y = y + rows * tile_h + (rows - 1) * gap + S.lg
  end

  -- now playing
  local m = snap.media
  if m and m.title and m.title ~= "" then
    Icon.draw(g, "note", M, y + l // 2 - 11, 22, 15)
    text(g, M + 30, y + l // 2, T.now_playing, F.label, { bold = true })
    y = y + l + S.sm
    local cs = 80
    local img
    local meta = HA.load(ctx, "ha_cover.json")
    if meta and meta.pic == m.pic and ctx.storage then
      local ok, bytes = pcall(ctx.storage.read, ctx.storage, HA.COVER)
      if ok and type(bytes) == "string" then img = HA.decode_cover(ctx, bytes, cs) end
    end
    if img then
      local iw, ih = HA.image_size(img, cs)
      g:image(img, M + (cs - iw) // 2, y + (cs - ih) // 2)
      g:rect(M, y, cs, cs, { radius = 4, line_width = 1 })
    else
      g:rect(M, y, cs, cs, { radius = 12, fill = true })
      Icon.draw(g, "note", M + 20, y + 20, 40, 0)
    end
    local tx = M + cs + S.md
    local tw_ = cw - cs - S.md
    local lines = HA.wrap(F.body, m.title, tw_, 2)
    local ty = y + 4
    for _, t2 in ipairs(lines) do
      text(g, tx, ty + lh(F.body) // 2, t2, F.body, { bold = true })
      ty = ty + lh(F.body)
    end
    local sub = m.artist or ""
    if m.state ~= "playing" then sub = T.paused .. ((sub ~= "") and (" \u{00B7} " .. sub) or "") end
    if sub ~= "" then text(g, tx, ty + lh(F.label) // 2, fit(F.label, sub, tw_), F.label) end
    y = y + cs + S.lg
  end

  -- lights that are on
  local on = snap.on or {}
  Icon.draw(g, "bulb", M, y + l // 2 - 11, 22, 15, #on > 0)
  text(g, M + 30, y + l // 2, T.lock_on, F.label, { bold = true })
  if #on > 0 then
    local s = tostring(#on)
    local pw = math.max(28, tw(F.label, s) + 18)
    g:rect(W - M - pw, y + l // 2 - 14, pw, 28, { radius = 14, fill = true })
    text(g, W - M - pw // 2, y + l // 2, s, F.label, { align = "center", bold = true, color = 0, tabular = true })
  end
  y = y + l + S.md

  local bl = lh(F.body) + S.xs
  if #on == 0 then
    text(g, M, y + bl // 2, T.lock_none, F.body)
    return
  end
  local room = math.max(1, (H - M - y) // bl)
  local show = #on
  if show > room then show = room - 1 end
  for i = 1, show do
    local cy = y + (i - 1) * bl + bl // 2
    g:circle(M + 6, cy, 5, { fill = true })
    text(g, M + 22, cy, fit(F.body, on[i], cw - 22), F.body)
  end
  if show < #on then
    local cy = y + show * bl + bl // 2
    text(g, M + 22, cy, string.format(T.lock_more, #on - show), F.body)
  end
end
