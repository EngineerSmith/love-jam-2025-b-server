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
  while event do
    local sessionID = ld.hash("string", "sha256", tostring(event.peer))
    local client = server.getClient(sessionID)
    if not client.peer then
      client.peer = event.peer
    end

    if event.type == "receive" then
      local success, encoded = pcall(ld.decompress, "data", options.compressionFunction, event.data)
      if not success then
        if client.loggedIn then
          love.logging.info("Server Process: Could not decompress incoing data from", client.username)
        else
          removeClient(sessionID)
          client.peer:disconnect(enum.disconnect.badlogin)
        end
        goto continue
      end
      if client.loggedIn then
        POST(enum.packetType.receive, client, encoded)
      else
        -- TODO receive uuid on login, and try to reroute them to their room
        local success = server.validLogin(client, encoded)
        if not success then
          server.removeClient(sessionID)
          client.peer:disconnect(enum.disconnect.badlogin)
          goto continue
        end
        POST(enum.packetType.login, client)
        channelOut:push({ -- tell client it is accepted, and their uuid.
          sessionID,
          serialize.encode(enum.packetType.login, client.uuid)
        })
      end
    elseif event.type == "disconnect" then
      server.removeClient(sessionID)
      if client.loggedIn then
        POST(enum.packetType.disconnect, client)
      end
    elseif event.type == "connect" then
      -- todo ? Anything we need to do here, not really.
    end
    ::continue::
    if ltr.getTime() >= budgetEndTime then
      break
    end
    event = server.host:check_events()
  end
end

server.sendTo = function(client, type_, ...)
  if not client.sessionID then
    error("Client doesn't have sess ID")
  end
  channelOut:push({ client.sessionID, serialize.encode(type_, ...) })
end

server.processOutgoing = function()
  local tempQueue = { }
  local command = channelOut:pop()
  while command do
    if type(command) ~= "table" then
      love.logging.warning("Server Outgoing: Tried to process command that isn't type table. Type:", type(command), (type(command) == "string") and ". Value:"..command or "")
    else
      local target = command[1]

      if target == "retry" then
        local target = command[2]

        local client = server.getClient(target, false)
        if not client then
          -- assume client disconnected, remove from queue
          goto continue
        end

        if client.peer and client.peer:state() == "connected" then
          local compressData = command[3]
          local channel = command[4]
          local flags = command[5]

          client.peer:send(compressData:getPointer(), compressData:getSize(), channel, flags)
        else
          command.retry = command.retry + 1
          if command.retry > 10 then
            love.logging.warn("Peer wasn't ready after 10 retries, disregarding packet.")
            goto continue
          end
          table.insert(tempQueue, command) 
        end
        goto continue
      end

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
      if not target then
        local n = 0
        for k, v in pairs(command) do
          n = n + 1
          print(k, v)
        end
        love.logging.warning("Processed outgoing, had no target.", n)
        goto continue
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
        if client.peer and client.peer:state() == "connected" then
          client.peer:send(compressData:getPointer(), compressData:getSize(), channel, flags)
        else
          command.retry = 1
          command[1] = "retry"
          command[2] = target
          command[3] = compressData
          command[4] = channel
          command[5] = flags
          table.insert(tempQueue, command) -- This does mean we waste resources compressing what isn't sent, and will continue to compress until it is sent
        end
      end
      ::continue::
    end
    command = channelOut:pop()
  end
  if #tempQueue ~= 0 then
    channelOut:performAtomic(function()
      for _, command in ipairs(tempQueue) do
        channelOut:push(command)
      end
    end)
  end
end

server.stop = function()
  if type(cleanUp) == "function" then
    cleanUp()
  end

  for _, client in pairs(clients) do
    if client.loggedIn then
      client.peer:disconnect(enum.disconnect.shutdown)
    end
  end

  server.clients = { }
  server.host:flush()
  server.host:destroy()
  server.host = nil
end

server.getClient = function(sessionID, makeNew)
  if makeNew == nil then
    makeNew = true
  end
  local client = server.clients[sessionID] or (makeNew and {
    sessionID = sessionID,
    uuid = getUUID(),
    loggedIn = false,
  } or nil)
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

server.getPlayerNameList = function()
  local playerNames = { }
  for index, client in pairs(server.clients) do
    if client.peer and client.peer:state() == "disconnected" then
      server.clients[index] = nil
      if client.loggedIn then
        POST(enum.packetType.disconnect, client)
      end
    elseif client.loggedIn then
      table.insert(playerNames, client.username)
    end
  end
  table.sort(playerNames)
  return table.concat(playerNames, "\n\n")
end

return server