-- PIN lock: keeps the dashboard from being used by whoever picks up the reader.
-- Only a salted hash of the PIN is stored, never the digits.
local M = {}

M.FILE = "ha_sec.json"
M.MIN_LEN = 4
M.MAX_LEN = 8
M.MAX_TRIES = 5          -- wrong attempts before a pause
M.WAIT_S = 30            -- length of that pause
M.DELAYS = { 0, 60, 300, 900 }  -- "lock after" choices in seconds (0 = every time)

-- two small polynomial hashes; every step stays far below 2^31, because the
-- device runs Lua with 32-bit integers
local P1, P2 = 1000003, 999983
local function mix(s, a, b)
  for i = 1, #s do
    local c = s:byte(i)
    a = (a * 31 + c) % P1
    b = (b * 37 + c + 7) % P2
  end
  return a, b
end

function M.hash(salt, pin)
  local a, b = mix(salt .. ":" .. pin, 17, 23)
  for i = 1, 400 do
    a, b = mix(pin .. salt .. i, a, b)
  end
  return string.format("%06x%06x", a, b)
end

function M.new_salt(ctx)
  local ms = 0
  if ctx.clock and ctx.clock.millis then
    local ok, v = pcall(ctx.clock.millis, ctx.clock)
    if ok and type(v) == "number" then ms = v end
  end
  local r = math.random(0, 999999)
  return string.format("%x%x", math.floor(ms % 1048576), r)
end

-- s = { pin = hash, salt = ..., len = n, delay = seconds } or empty table
function M.load(HA, ctx)
  local s = HA.load(ctx, M.FILE)
  if type(s) ~= "table" then s = {} end
  if type(s.pin) ~= "string" or type(s.salt) ~= "string" then s.pin, s.salt, s.len = nil, nil, nil end
  if type(s.delay) ~= "number" then s.delay = 0 end
  return s
end

function M.save(HA, ctx, s)
  HA.save(ctx, M.FILE, { pin = s.pin, salt = s.salt, len = s.len, delay = s.delay })
end

function M.enabled(s) return s and s.pin ~= nil end

function M.set_pin(ctx, s, pin)
  s.salt = M.new_salt(ctx)
  s.pin = M.hash(s.salt, pin)
  s.len = #pin
end

function M.clear(s)
  s.pin, s.salt, s.len = nil, nil, nil
end

function M.check(s, pin)
  return s.pin ~= nil and M.hash(s.salt, pin) == s.pin
end

function M.next_delay(d)
  for i, v in ipairs(M.DELAYS) do
    if v == d then return M.DELAYS[i % #M.DELAYS + 1] end
  end
  return M.DELAYS[1]
end

return M
