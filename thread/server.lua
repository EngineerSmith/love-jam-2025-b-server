local enet = require("enet")

local serialize = require("util.serialize")

local ld, ltr = love.data, love.timer

local options = require("util.option")
local enum = require("util.enum")

local server = {
  maxPlayers = 100,
  clients = { },
}

local channelOut = love.thread.getChannel("channelOut")

server.start = function(port)
  channelOut:clear()

  if not port then port = 53135 end
  love.logging.info("Game server starting on port:", port)
  server.host = enet.host_create("*:"..tostring(port), server.maxPlayers, enum.channelCount, 0, 0)
  if not server.host then
    love.logging.warning("Game server could not start on port:", port)
    return false
  end

  return true
end

server.process = function(budgetEndTime)
  local event = server.host:service(20)
  while event and ltr.getTime() < budgetEndTime do
    local sessionID = ld.hash("string", "sha256", tostring(event.peer))
    local client = server.getClient(sessionID)

    if event.type == "receive" then
      local success, encoded = pcall(ld.decompress, "data", options.compressionFunction, event.data)
      if not success then
        if client.loggedIn then
          love.logging.info("Server Process: Could not decompress incoing data from", client.username)
        else
          removeClient(sessionID)
          client.peer:disconnect_now(enum.disconnect.badlogin)
        end
        goto continue
      end
      if client.loggedIn then
        POST(enum.packetType.receive, client, encoded)
      else
        local success = server.validLogin(client, encoded)
        if not success then
          server.removeClient(sessionID)
          client.peer:disconnect_now(enum.disconnect.badlogin)
          goto continue
        end
        POST(enum.packetType.login, client)
        channelOut:push({ -- tell client it is accepted, and their uid if they're a new user
          sessionID,
          serialize.encode(enum.packetType.login)
        })
      end
    elseif event.type == "disconnect" then
      server.removeClient(sessionID)
      if client.loggedIn then
        POST(enum.packetType.disconnect, client)
      end
    elseif event.type == "connect" then
      client.peer = event.peer
      client.sessionID = sessionID
      client.loggedIn = false
    end
    ::continue::
    event = server.host:check_events()
  end
end

server.processOutgoing = function()
  local command = channelOut:pop()
  while command do
    if type(command) ~= "table" then
      love.logging.warning("Server Outgoing: Tried to process command that isn't type table. Type:", type(command), (type(command) == "string") and ". Value:"..command or "")
    else
      local target = command[1]
      local data = command[2]
      local channel = enum.channel.default
      local flags = "reliable"
      if target == "channel" then
        channel = command[2]
        if channel == enum.channel.unreliable then
          flags = "unreliable"
        elseif channel == enum.channel.unsequenced then
          flags = "unsequenced"
        end
        target = command[3]
        data = command[4]
      end
      -- compress
      local compressData
      if data and data ~= enum.packetType.disconnect then
        local success
        success, compressData = pcall(ld.compress, "data", options.compressionFunction, data)
        if not success then
          if target == "all" then
            love.logging.warn("Server outgoing: Could not compress outgoing data to all!")
          else
            local client = getClient(target, false)
            love.logging.warn("Server outgoing: Could not compress outgoing data to", tostring(target)..(client and client.username and " known as "..client.username or ""))
          end
          goto continue
        end
      end
      -- send to target
      if target == "all" then
        for _, client in pairs(clients) do
          if client.loggedIn then
            client.peer:send(compressData:getPointer(), compressData:getSize(), channel, flags)
          end
        end
      else
        local client = server.getClient(target, false)
        if not client then
          love.logging.warn("Server outgoing: Network target is not valid:", tostring(target))
          goto continue
        end
        if command[2] == enum.packetType.disconnect then 
          local reason = tonumber(command[3]) or enum.disconnect.normal
          client.peer:disconnect(reason)
          goto continue
        end

        client.peer:send(compressData:getPointer(), compressData:getSize(), channel, flags)
      end
      ::continue::
    end
    command = channelOut:pop()
  end
end

server.stop = function()
  if type(cleanUp) == "function" then
    cleanUp()
  end

  for _, client in pairs(clients) do
    if client.loggedIn then
      client.peer:disconnect(enum.disconnect.shutdown)
    else
      client.peer:disconnect_now(enum.disconnect.shutdown)
    end
  end

  server.clients = { }
  server.host:destroy()
  server.host = nil
end

server.getClient = function(sessionID, makeNew)
  if makeNew == nil then
    makeNew = true
  end
  local client = server.clients[sessionID] or (makeNew and { } or nil)
  server.clients[sessionID] = client
  return client
end

server.removeClient = function(sessionID)
  server.clients[sessionID] = nil
end

server.validLogin = function(client, encoded)
  local decoded = serialize.decodeIndexed(encoded:getString())
  if type(decoded) ~= "table" then
    love.logging.info("LOGIN: Invalid decoded")
    return false
  end
  -- USERNAME
  client.username = decoded[1]
  if type(client.username) ~= "string" or #client.username == 0 or client.username == "server" or not options.validateUsername(client.username) then
    love.logging.info("LOGIN: Invalid username")
    return false
  end
  --
  client.loggedIn = true
  return true
end

server.getPlayerCount = function()
  local count = 0
  for _, client in pairs(server.clients) do
    if client.loggedIn then
      count = count + 1
    end
  end
  return count
end

return server