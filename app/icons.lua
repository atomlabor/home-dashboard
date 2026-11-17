-- Small vector icons drawn with plain shapes, so they stay sharp at any size
-- and can be drawn black on white or white on black.
local M = {}

local function P(x, y, s, pts)
  local out = {}
  for i = 1, #pts, 2 do
    out[#out + 1] = x + math.floor(pts[i] * s + 0.5)
    out[#out + 1] = y + math.floor(pts[i + 1] * s + 0.5)
  end
  return out
end

local function R(v, s) return math.floor(v * s + 0.5) end

local draw = {}

function draw.thermo(g, x, y, s, c, bg, lw)
  g:rect(x + R(0.38, s), y + R(0.06, s), R(0.24, s), R(0.62, s), { radius = R(0.12, s), line_width = lw, color = c })
  g:circle(x + R(0.5, s), y + R(0.76, s), R(0.18, s), { fill = true, color = c })
  g:rect(x + R(0.46, s), y + R(0.34, s), math.max(2, R(0.08, s)), R(0.4, s), { fill = true, color = c })
end

function draw.drop(g, x, y, s, c)
  g:polygon(P(x, y, s, { 0.5, 0.06, 0.2, 0.56, 0.8, 0.56 }), { fill = true, color = c })
  g:circle(x + R(0.5, s), y + R(0.62, s), R(0.3, s), { fill = true, color = c })
end

function draw.bolt(g, x, y, s, c)
  g:polygon(P(x, y, s, { 0.6, 0.04, 0.18, 0.56, 0.46, 0.56, 0.36, 0.96, 0.82, 0.4, 0.54, 0.4 }), { fill = true, color = c })
end

function draw.battery(g, x, y, s, c, bg, lw)
  g:rect(x + R(0.06, s), y + R(0.28, s), R(0.76, s), R(0.44, s), { radius = R(0.08, s), line_width = lw, color = c })
  g:rect(x + R(0.84, s), y + R(0.4, s), R(0.1, s), R(0.2, s), { fill = true, color = c })
  g:rect(x + R(0.16, s), y + R(0.38, s), R(0.42, s), R(0.24, s), { fill = true, color = c })
end

function draw.air(g, x, y, s, c)
  g:circle(x + R(0.34, s), y + R(0.58, s), R(0.18, s), { fill = true, color = c })
  g:circle(x + R(0.56, s), y + R(0.46, s), R(0.24, s), { fill = true, color = c })
  g:circle(x + R(0.78, s), y + R(0.62, s), R(0.15, s), { fill = true, color = c })
  g:rect(x + R(0.2, s), y + R(0.6, s), R(0.62, s), R(0.17, s), { fill = true, color = c })
end

function draw.sun(g, x, y, s, c, bg, lw)
  local cx, cy = x + R(0.5, s), y + R(0.5, s)
  g:circle(cx, cy, R(0.2, s), { fill = true, color = c })
  for i = 0, 7 do
    local a = i * math.pi / 4
    g:line(cx + R(math.cos(a) * 0.32, s), cy + R(math.sin(a) * 0.32, s),
      cx + R(math.cos(a) * 0.46, s), cy + R(math.sin(a) * 0.46, s), { line_width = lw, color = c })
  end
end

function draw.gauge(g, x, y, s, c, bg, lw)
  local cx, cy = x + R(0.5, s), y + R(0.55, s)
  g:circle(cx, cy, R(0.42, s), { line_width = lw, color = c })
  g:line(cx, cy, x + R(0.74, s), y + R(0.3, s), { line_width = lw + 1, color = c })
  g:circle(cx, cy, R(0.08, s), { fill = true, color = c })
end

function draw.bulb(g, x, y, s, c, bg, lw, on)
  if on then
    g:circle(x + R(0.5, s), y + R(0.4, s), R(0.3, s), { fill = true, color = c })
  else
    g:circle(x + R(0.5, s), y + R(0.4, s), R(0.3, s), { line_width = lw, color = c })
  end
  g:rect(x + R(0.37, s), y + R(0.72, s), R(0.26, s), R(0.08, s), { fill = true, color = c })
  g:rect(x + R(0.41, s), y + R(0.84, s), R(0.18, s), R(0.08, s), { fill = true, color = c })
end

function draw.plug(g, x, y, s, c)
  g:rect(x + R(0.33, s), y + R(0.06, s), R(0.09, s), R(0.24, s), { fill = true, color = c })
  g:rect(x + R(0.58, s), y + R(0.06, s), R(0.09, s), R(0.24, s), { fill = true, color = c })
  g:rect(x + R(0.2, s), y + R(0.28, s), R(0.6, s), R(0.38, s), { radius = R(0.12, s), fill = true, color = c })
  g:rect(x + R(0.45, s), y + R(0.64, s), R(0.1, s), R(0.3, s), { fill = true, color = c })
end

function draw.fan(g, x, y, s, c)
  local cx, cy = x + R(0.5, s), y + R(0.5, s)
  for i = 0, 2 do
    local a = i * 2 * math.pi / 3 - math.pi / 2
    g:circle(cx + R(math.cos(a) * 0.26, s), cy + R(math.sin(a) * 0.26, s), R(0.18, s), { fill = true, color = c })
  end
  g:circle(cx, cy, R(0.1, s), { fill = true, color = c })
end

function draw.toggle(g, x, y, s, c, bg, lw, on)
  g:rect(x + R(0.06, s), y + R(0.28, s), R(0.88, s), R(0.44, s), { radius = R(0.22, s), line_width = lw, color = c })
  local kx = on and R(0.72, s) or R(0.28, s)
  g:circle(x + kx, y + R(0.5, s), R(0.14, s), { fill = true, color = c })
end

function draw.home(g, x, y, s, c, bg, lw)
  g:polyline(P(x, y, s, { 0.1, 0.5, 0.5, 0.12, 0.9, 0.5 }), { line_width = lw + 1, color = c })
  g:rect(x + R(0.22, s), y + R(0.44, s), R(0.56, s), R(0.46, s), { line_width = lw, color = c })
  g:rect(x + R(0.43, s), y + R(0.64, s), R(0.14, s), R(0.26, s), { fill = true, color = c })
end

function draw.grid(g, x, y, s, c, bg, lw)
  for i = 0, 1 do
    for j = 0, 1 do
      g:rect(x + R(0.1 + i * 0.44, s), y + R(0.1 + j * 0.44, s), R(0.36, s), R(0.36, s),
        { radius = R(0.08, s), line_width = lw, color = c })
    end
  end
end

function draw.gear(g, x, y, s, c, bg)
  local cx, cy = x + R(0.5, s), y + R(0.5, s)
  for i = 0, 7 do
    local a = i * math.pi / 4
    g:circle(cx + R(math.cos(a) * 0.36, s), cy + R(math.sin(a) * 0.36, s), R(0.1, s), { fill = true, color = c })
  end
  g:circle(cx, cy, R(0.33, s), { fill = true, color = c })
  g:circle(cx, cy, R(0.13, s), { fill = true, color = bg })
end

function draw.chevron(g, x, y, s, c, bg, lw)
  g:polyline(P(x, y, s, { 0.36, 0.18, 0.68, 0.5, 0.36, 0.82 }), { line_width = lw + 1, color = c })
end

function draw.back(g, x, y, s, c, bg, lw)
  g:polyline(P(x, y, s, { 0.64, 0.18, 0.32, 0.5, 0.64, 0.82 }), { line_width = lw + 1, color = c })
end

function draw.check(g, x, y, s, c, bg, lw)
  g:polyline(P(x, y, s, { 0.18, 0.52, 0.4, 0.74, 0.82, 0.28 }), { line_width = lw + 1, color = c })
end

function draw.user(g, x, y, s, c)
  g:circle(x + R(0.5, s), y + R(0.32, s), R(0.2, s), { fill = true, color = c })
  g:rect(x + R(0.16, s), y + R(0.6, s), R(0.68, s), R(0.34, s), { radius = R(0.16, s), fill = true, color = c })
end

function draw.key(g, x, y, s, c, bg)
  g:circle(x + R(0.3, s), y + R(0.5, s), R(0.22, s), { fill = true, color = c })
  g:circle(x + R(0.3, s), y + R(0.5, s), R(0.08, s), { fill = true, color = bg })
  g:rect(x + R(0.44, s), y + R(0.44, s), R(0.5, s), R(0.12, s), { fill = true, color = c })
  g:rect(x + R(0.72, s), y + R(0.54, s), R(0.1, s), R(0.16, s), { fill = true, color = c })
end

function draw.file(g, x, y, s, c, bg, lw)
  g:polygon(P(x, y, s, { 0.2, 0.06, 0.62, 0.06, 0.82, 0.26, 0.82, 0.94, 0.2, 0.94 }), { fill = true, color = c })
  for i = 0, 2 do
    g:rect(x + R(0.32, s), y + R(0.42 + i * 0.16, s), R(0.38, s), math.max(2, R(0.06, s)), { fill = true, color = bg })
  end
end

function draw.globe(g, x, y, s, c, bg, lw)
  local cx, cy, r = x + R(0.5, s), y + R(0.5, s), R(0.42, s)
  g:circle(cx, cy, r, { line_width = lw, color = c })
  g:line(cx - r, cy, cx + r, cy, { line_width = lw, color = c })
  g:rect(cx - R(0.16, s), cy - r, R(0.32, s), 2 * r, { radius = R(0.16, s), line_width = lw, color = c })
end

function draw.lock(g, x, y, s, c, bg, lw)
  g:rect(x + R(0.3, s), y + R(0.1, s), R(0.4, s), R(0.5, s), { radius = R(0.2, s), line_width = lw + 1, color = c })
  g:rect(x + R(0.16, s), y + R(0.42, s), R(0.68, s), R(0.5, s), { radius = R(0.08, s), fill = true, color = c })
  g:circle(x + R(0.5, s), y + R(0.64, s), R(0.07, s), { fill = true, color = bg })
end

function draw.refresh(g, x, y, s, c, bg, lw)
  local cx, cy, r = x + R(0.5, s), y + R(0.52, s), R(0.32, s)
  g:circle(cx, cy, r, { line_width = lw, color = c })
  g:rect(cx, cy - r - lw, R(0.4, s), R(0.3, s), { fill = true, color = bg })
  g:polygon(P(x, y, s, { 0.52, 0.04, 0.78, 0.2, 0.52, 0.36 }), { fill = true, color = c })
end

function draw.note(g, x, y, s, c)
  g:circle(x + R(0.32, s), y + R(0.74, s), R(0.17, s), { fill = true, color = c })
  g:rect(x + R(0.42, s), y + R(0.1, s), R(0.08, s), R(0.66, s), { fill = true, color = c })
  g:polygon(P(x, y, s, { 0.46, 0.1, 0.84, 0.22, 0.84, 0.4, 0.46, 0.3 }), { fill = true, color = c })
end

function draw.play(g, x, y, s, c)
  g:polygon(P(x, y, s, { 0.3, 0.16, 0.84, 0.5, 0.3, 0.84 }), { fill = true, color = c })
end

function draw.pause(g, x, y, s, c)
  g:rect(x + R(0.24, s), y + R(0.18, s), R(0.18, s), R(0.64, s), { radius = 2, fill = true, color = c })
  g:rect(x + R(0.58, s), y + R(0.18, s), R(0.18, s), R(0.64, s), { radius = 2, fill = true, color = c })
end

function draw.next(g, x, y, s, c)
  g:polygon(P(x, y, s, { 0.16, 0.2, 0.6, 0.5, 0.16, 0.8 }), { fill = true, color = c })
  g:rect(x + R(0.64, s), y + R(0.2, s), R(0.14, s), R(0.6, s), { fill = true, color = c })
end

function draw.prev(g, x, y, s, c)
  g:polygon(P(x, y, s, { 0.84, 0.2, 0.4, 0.5, 0.84, 0.8 }), { fill = true, color = c })
  g:rect(x + R(0.22, s), y + R(0.2, s), R(0.14, s), R(0.6, s), { fill = true, color = c })
end

M.CLASS = {
  temperature = "thermo", humidity = "drop", power = "bolt", energy = "bolt", battery = "battery",
  carbon_dioxide = "air", pm25 = "air", illuminance = "sun", pressure = "gauge",
}
M.DOMAIN = { light = "bulb", switch = "plug", input_boolean = "toggle", fan = "fan" }

function M.for_entity(e)
  if e.dom == "sensor" then return M.CLASS[e.cls] or "gauge" end
  return M.DOMAIN[e.dom] or "toggle"
end

-- color: 15 = ink on paper, 0 = paper on ink
function M.draw(g, kind, x, y, s, color, on)
  local f = draw[kind] or draw.gauge
  local c = color or 15
  local bg = (c >= 8) and 0 or 15
  local lw = math.max(2, s // 12)
  f(g, x, y, s, c, bg, lw, on)
end

return M
