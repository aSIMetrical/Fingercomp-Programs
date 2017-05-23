local component = require("component")
local fs = require("filesystem")
local shell = require("shell")
local term = require("term")
local unicode = require("unicode")

local complex = require("complex")

local gpu = component.gpu

local function reverseBits(num, len)
  local result = 0
  local n = 1 << len
  local nrev = num
  for i = 1, len - 1, 1 do
    num = num >> 1
    nrev = nrev << 1
    nrev = nrev | (num & 1)
  end
  nrev = nrev & (n - 1)
  return nrev
end

local function fft(x)
  local bitlen = math.ceil(math.log(#x, 2))
  local data = {}
  for i = 0, #x, 1 do
    data[reverseBits(i, bitlen)] = complex(x[i])
  end

  for s = 1, bitlen, 1 do
    local m = 2^s
    local hm = m * 0.5
    local omegaM = (complex{0, -2 * math.pi / m}):exp()
    for k = 0, #x, m do
      local omega = complex(1)
      for j = 0, hm - 1 do
        local t = omega * data[k + j + hm]
        local u = data[k + j]
        data[k + j] = u + t
        data[k + j + hm] = u - t
        omega = omega * omegaM
      end
    end
  end
  return data
end

path, depth, rate, sampleSize, step, len = ...
depth, rate = tonumber(depth), tonumber(rate)
sampleSize = tonumber(sampleSize) or 1024
step = tonumber(step)

local f = io.open(path, "rb")
local total = fs.size(shell.resolve(path))

depth = math.floor(depth / 8)
len = tonumber(len) or total / rate / depth

total = len * rate * depth

local chans = {}

sampleSize = 2^math.ceil(math.log(sampleSize, 2)) - 1
step = math.floor((sampleSize + 1) / step + .5)
local sleep = step / rate

print("Loading " .. ("%.2f"):format(len) .. "s of " .. path .. ": pcm_s" .. (depth * 8) .. (depth > 1 and "le" or "") .. " @ " .. rate .. " Hz [" .. math.floor(sampleSize + 1) .. " samples -> " .. math.floor(step) .. "]")

local iTime = os.clock()
local startTime = iTime

os.sleep(0)
local lastSleep = os.clock()

local shift = 0

while shift < total do
  local samples = {}
  for i = 1, math.min(sampleSize, total - shift) * depth, depth do
    local sample = f:read(depth)
    sample = ("<i" .. depth):unpack(sample)
    samples[i] = sample / (2^(depth * 8) / 2)
  end

  local requiredLen = 2^math.ceil(math.log(#samples, 2))
  for i = #samples, requiredLen - 1, 1 do
    table.insert(samples, 0)
  end

  for i = 1, #samples, 1 do
    samples[i - 1] = samples[i]
  end

  samples[#samples] = nil

  samples = fft(samples, true)
  result = samples

  --[[
  print("Removing noise")

  for i = 0, #result, 1 do
    local a = #result / 2
    local t = (i - a) / (0.5 * a)
    t = t^2
    t = math.exp(-t/2)
    result[i] = result[i] * t
  end]]

  for i = 1, #result, 1 do
    result[i] = {i * rate / (#result + 1), result[i]:abs() / (#result + 1), select(2, result[i]:polar())}
  end

  --[[
  print("Post-filtering")

  for i = 1, #result, 1 do
    local f = result[i][1]
    local m = 0
    local Q = 10
    local Tl = 150
    local E = 2/3
    if f > Tl then
      m = Q * (Tl / f)^E
    end
    result[i][2] = result[i][2] * m
  end
  ]]--

  for i = #result, 1, -1 do
    result[i + 1] = result[i]
  end

  for i = math.floor(#result / 2), #result, 1 do
    result[i] = nil
  end

  table.sort(result, function(lhs, rhs)
    return lhs[2] > rhs[2]
  end)

  for i = 1, 8, 1 do
    table.insert(chans, result[i][1])
    table.insert(chans, result[i][2])
  end

  if total - shift < sampleSize then
    break
  end
  shift = shift + step
  term.clearLine()
  local dig = math.ceil(math.log(total, 10))
  io.write(("%" .. dig .. ".0f B processed out of %" .. dig .. ".0f B (took %.3fs)"):format(shift, total, os.clock() - iTime))
  iTime = os.clock()
  if os.clock() - lastSleep > 2.5 then
    os.sleep(0)
    lastSleep = os.clock()
  end
end

f:close()

term.clearLine()
print(("%.0f B processed for %.3fs (%.2f B/s)"):format(total, os.clock() - startTime, total / (os.clock() - startTime)))

local brailleMap do
  brailleMap = {}
  brailleMap.__index = brailleMap

  local function unit(a, b, c, d, e, f, g, h)
    a = a and 1 or 0
    b = b and 1 or 0
    c = c and 1 or 0
    d = d and 1 or 0
    e = e and 1 or 0
    f = f and 1 or 0
    g = g and 1 or 0
    h = h and 1 or 0
    return unicode.char(
      10240 + 128 * h + 64 * d + 32 * g + 16 * f + 8 * e + 4 * c + 2 * b + a)
  end

  function brailleMap:set(x, y, v)
    v = v and v or 0xFFFFFF
    x = x - 1
    y = y - 1
    if x >= 0 and x < self.width and y >= 0 and y < self.height then
      self.data[self.width * y + x] = v
    end
  end

  function brailleMap:get(x, y)
    x = x - 1
    y = y - 1
    if x >= 0 and x < self.width and y >= 0 and y < self.height then
      return self.data[self.width * y + x] or nil
    else
      return nil
    end
  end

  local function rgb2hex(r, g, b)
    return bit32.rshift(r, 16) + bit32.rshift(g, 8) + b
  end

  local function hex2rgb(hex)
    return bit32.lshift(hex, 16),
      bit32.band(bit32.lshift(hex, 8), 0xFF),
      bit32.band(hex, 0xFF)
  end

  local function sum(a)
    local result = 0
    for _, v in pairs(a) do
      result = result + v
    end
    return result
  end

  local function color8interpolate(a, b, c, d, e, f, g, h)
    local count = 0
    local unique = {}
    local rarr, garr, barr = {}, {}, {}

    for _, v in ipairs({a or 0, b or 0, c or 0, d or 0, e or 0, f or 0, g or 0, h or 0}) do
      if v ~= 0 and not unique[v] then
        unique[v] = true
        rarr[count + 1], garr[count + 1], barr[count + 1] = hex2rgb(v)
        count = count + 1
      end
    end

    local r = sum(rarr) / count
    local g = sum(garr) / count
    local b = sum(barr) / count

    return rgb2hex(r, g, b)
  end

  function brailleMap:render(x, y)
    local sy = 0
    local fg = gpu.getForeground()
    for dy = 1, self.height, 4 do
      local sx = 0
      for dx = 1, self.width, 2 do
        local a, b, c, d, e, f, g, h =
          self:get(dx, dy), self:get(dx, dy + 1),
          self:get(dx, dy + 2), self:get(dx, dy + 3),
          self:get(dx + 1, dy), self:get(dx + 1, dy + 1),
          self:get(dx + 1, dy + 2), self:get(dx + 1, dy + 3)

        local nfg = a or b or c or d or e or f or g or h or fg

        if (a and a ~= nfg) or
           (b and b ~= nfg) or
           (c and c ~= nfg) or
           (d and d ~= nfg) or
           (e and e ~= nfg) or
           (f and f ~= nfg) or
           (g and g ~= nfg) or
           (h and h ~= nfg) then
          nfg = color8interpolate(a, b, c, d, e, f, g, h)
        end

        if fg ~= nfg then
          gpu.setForeground(nfg)
          fg = nfg
        end
        local c = unit(a, b, c, d, e, f, g, h)
        if c ~= "⠀" then
          gpu.set(x + sx, y + sy, c)
        end
        sx = sx + 1
      end
      sy = sy + 1
    end
  end

  setmetatable(brailleMap, {
    __call = function(_, w, h)
      local self = setmetatable({}, brailleMap)
      self.width = w
      self.height = h
      self.data = {}
      return self
    end
  })
end

local plot do
  plot = {}
  plot.__index = plot

  function plot:renderXAxis(vx, vy, vw, vh)
    local y = (vh * math.abs(self.ly)) / (math.abs(self.ly) + self.uy) + 1
    local x = vx
    y = vh - y + 1

    self.centerY = y

    gpu.fill(x, math.floor(y + 0.5), vw - 1, 1, "─")
    gpu.set(x + vw - 1, math.floor(y + 0.5), "→")
  end

  function plot:renderYAxis(vx, vy, vw, vh)
    local y = vy
    local x = vx + (vw * math.abs(self.lx)) / (math.abs(self.lx) + self.ux) - 1

    self.centerX = x

    gpu.fill(math.floor(x + 0.5), y + 1, 1, vh - 1, "│", true)
    gpu.set(math.floor(x + 0.5), y, "↑")
  end

  function plot:renderXYPoint(vx, vy, vw, vh)
    gpu.set(math.floor(self.centerX + 0.5), math.floor(self.centerY + 0.5), "┼")
  end

  function plot:render(vx, vy, vw, vh)
    gpu.fill(vx, vy, vw, vh, " ")

    vh = vh - self:renderLabels(vx, vy, vw, vh)
    self:renderXAxis(vx, vy, vw, vh)
    self:renderYAxis(vx, vy, vw, vh)
    self:renderXYPoint()

    self.braille = brailleMap(vw * 2, vh * 4)

    for _, fun in pairs(self.functions) do
      self:plotFunction(vx, vy, vw, vh, fun.fun, fun.color, fun.step)
    end

    self.braille:render(vx, vy)
  end

  function plot:fun(fun, color, step, label)
    table.insert(self.functions, {fun = fun, color = color, step = step, label = label})
    return self.functions[#self.functions]
  end

  function plot:renderLabels(vx, vy, vw, vh)
    local sx = 0

    for _, fun in ipairs(self.functions) do
      if fun.label then
        gpu.setForeground(fun.color)
        gpu.set(vx + sx, vy + vh - 1, fun.label)
        sx = sx + unicode.len(fun.label) + 2
      end
    end

    for _, label in ipairs(self.labels) do
      gpu.setForeground(label.color)
      gpu.set(vx + sx, vy + vh - 1, label.text)
      sx = sx + unicode.len(label.text) + 2
    end

    return 1
  end

  function plot:plotFunction(vx, vy, vw, vh, fun, color, step)
    local rw, rh = self.ux - self.lx,
      self.uy - self.ly

    for x = self.lx, self.ux, step or 0.001 do
      local y = fun(x)
      local px = self.centerX * 2 + x * vw * 2 / rw
      local py = self.centerY * 4 - y * vh * 4 / rh
      for ty = math.floor(py + 0.5), self.centerY * 4, 1 do
        self.braille:set(math.floor(px + 0.5), math.floor(ty + 0.5), color)
      end
    end
  end

  function plot:label(text, color)
    table.insert(self.labels, {text = text, color = color})
    return self.labels[#self.labels]
  end

  setmetatable(plot, {
    __call = function()
      local self = setmetatable({}, plot)

      self.functions = {}
      self.labels = {}

      self.lx = 1
      self.ux = rate / 2

      local max = 0
      for i = 2, #chans, 2 do
        max = math.max(max, chans[i])
      end
      self.ly = 0
      self.uy = max
      if self.ly == self.uy and self.uy == 0 then
        self.uy = 1
      end

      return self
    end
  })
end

os.sleep(0)

local s = component.sound

local maxAmplitude = 0
for i = 2, #chans, 2 do
  maxAmplitude = math.max(maxAmplitude, chans[i])
end

local iteration = 1

for sample = 1, #chans, 8 * 2 do
  term.clearLine()
  io.write(("Playing: %.2fs (%3.0f%%)"):format(iteration * sleep, iteration * sleep / len * 100))
  local i = 1
  for chan = sample, sample + 8 * 2 - 1, 2 do
    s.setWave(i, s.modes.sine)
    s.setFrequency(i, chans[chan])
    s.setVolume(i, chans[chan + 1] / maxAmplitude)
    s.resetEnvelope(i)
    s.resetFM(i)
    s.resetAM(i)
    s.open(i)
    i = i + 1
  end
  s.delay(sleep * 1000)
  while not s.process() do
    os.sleep(0.05)
  end
  os.sleep(sleep)
  iteration = iteration + 1
end

s.process()

print("\n\nExiting")
