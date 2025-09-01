local room = { }
room.__index = room

local server = require("thread.server")

local keys = { }
local getNewKey = function()
  for attempt = 1, 10 do
    local key = ""
    for __ = 1, 4 do
      key = key .. tostring(love.math.random(0, 9))
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

room.new = function(owner)
  local key = getNewKey()
  if not key then
    return
  end
  local self = setmetatable({
    state = "waiting",
    key = key,
    owner = owner,
    players = { },
    maxPlayers = 4,
    uuid = getUUID(),
  }, room)
  love.logging.info("Room: Created new room:", self.uuid)
  if not self:addPlayer(owner) then
    error("You messed up, this should never fail")
  end
  return self
end

room.addPlayer = function(self, client)
  if #self.players >= self.maxPlayers then
    return false
  end
  if self.state ~= "waiting" then
    return false
  end

  love.logging.info("Room: Added client["..client.uuid.."]to room: ", self.uuid)

  table.insert(self.players, {
    client = client,
  })
  return true
end

room.removePlayer = function(self, client)
   for i, player in ipairs(self.players) do
    if player.client.sessionID == client.sessionID then
      table.remove(self.players, i)
      if self.owner == client then
        if #self.players >= 1 then
          self.owner = self.players[1]
        else
          self.owner = nil
        end
      end
      return true
    end
  end
  return false
end

room.getInfo = function(self)
  local info = {
    key = self.key,
    owner = self.owner.uuid,
    players = { },
    maxPlayers = self.maxPlayers,
    state = self.state,
  }
  for _, player in ipairs(self.players) do
    table.insert(info.players, {
      username = player.client.username,
      uuid = player.client.uuid
    })
  end
  return info
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

-- network handlers
local rooms = { }

local findClientRoom = function(client)
  for _, room in ipairs(rooms) do
    if #room.players > 0 then
      for _, player in ipairs(room.players) do
        if player.client.sessionID == client.sessionID then
          return room
        end
      end
    end
  end
  return nil
end

addHandler("createRoom", function(client)
  do
    local room = findClientRoom(client)
    if room then
      server.sendTo(client, "createRoom", false)
      return
    end
  end

  local newRoom = room.new(client)
  if not newRoom then
    server.sendTo(client, "createRoom", false)
  else
    table.insert(rooms, newRoom)
    server.sendTo(client, "createRoom", true, newRoom:getInfo())
  end
end)

addHandler("joinRoom", function(client, roomKey)
  do
    local room = findClientRoom(client)
    if room then
      server.sendTo(client, "joinRoom", false)
      return
    end
  end

  for _, room in ipairs(rooms) do
    if room.state == "waiting" and room.key == roomKey then
      if room:addPlayer(client) then
        server.sendTo(client, "joinRoom", true, room:getInfo())
        -- todo tell new player about who is in the room
      else
        server.sendTo(client, "joinRoom", false)
      end
      return
    end
  end
end)

addHandler("disconnect", function(client)
  local room = findClientRoom(client)
  if room then
    if not room:removePlayer(client) then
      print("WARNING: Tried to remove player from room, but was unable to.")
    else
      if #room.players == 0 then
        for index, r in ipairs(rooms) do
          if r == room then
            love.logging.info("Room: Removed room:", room.uuid)
            room:remove()
            table.remove(rooms, index)
            break
          end
        end
      end
    end
  end
end)
--

return room