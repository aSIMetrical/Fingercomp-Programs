-- Beep card module

local com = require("component")

NAME = "beep"

function new(addr)
  if not com.isAvailable("beep") then
    return false, "no device connected"
  end
  addr = addr or com.getPrimary("beep").address
  if not com.proxy(addr) then
    return false, "no device with such address"
  end
  local beep = com.proxy(addr)
  if not beep.type == "beep" then
    return false, "wrong device"
  end
  return audio.Device(function(dev, chords)
    local freqPairs = {}
    local l = 1
    for _, chord in pairs(chords) do
      for freq, len, instr in pairs(chord) do
        if l > 8 then
          goto outer
        end
        while freq < 20 do freq = freq * 2 end
        while freq > 2000 do freq = freq / 2 end
        freqPairs[freq] = len
      end
    end
    ::outer::
    if not com.proxy(addr) then
      return false, "device is unavailable"
    end
    beep.beep(freqPairs)
  end)
end

-- vim: expandtab tabstop=2 shiftwidth=2 :
