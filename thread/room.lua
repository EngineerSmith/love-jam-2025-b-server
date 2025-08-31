local room = { }
room.__index = room

local keys = { }
local getNewKey = function()
  for attempt = 1, 10 do
    local key = ""
    for __ = 1, 4 do
      key = key .. love.math.random(0, 9).tostring()
    end
    if not keys[key] then
      keys[key] = true
      return key
    end
  end
  return nil
end

local removeKey = function(key)
  keys[key] = nil
end

room.new = function()
  local key = getNewKey()
  if not key then return end
  local self = setmetatable({
    state = "waiting",
    key = key
  }, room)
  return self
end

room.remove = function(self)
  if self.key then
    removeKey(self.key)
    self.key = nil
  end
end

room.begin = function(self)
  self.state = "playing"
end

return room