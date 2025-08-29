local PATH, dirPATH = ...

love.isMintMousseServerThread = true
require(PATH .. "mintmousse")(PATH, dirPATH)

local json = love.mintmousse.require("libs.json")

local components = love.mintmousse.require("thread.components")
components.init()

local http = love.mintmousse.require("thread.http")
local server = nil -- deferred require until server needs to start
local controller = love.mintmousse.require("thread.controller")
local websocket13 = love.mintmousse.require("thread.websocket13")

-- Set defaults
controller.setTitle("MintMousse")
controller.setSVGIcon({
  emoji = "🍮",
  rect = true,
  rounded = true,
  insideColor = "#95d7ab",
  outsideColor = "#00FF07",
  easterEgg = true,
})

local callbacks = { }

callbacks.newTab = controller.newTab
callbacks.setTitle = controller.setTitle
callbacks.setSVGIcon = controller.setSVGIcon
callbacks.setIconRaw = controller.setIconRaw
callbacks.setIconRFG = controller.setIconRFG
callbacks.setIconFromFile = controller.setIconFromFile
callbacks.updateSubscription = controller.updateThreadSubscription

callbacks.addComponent = controller.addComponent
callbacks.updateComponent = controller.updateComponent
callbacks.updateParentComponent = controller.updateParentComponent
callbacks.removeComponent = controller.removeComponent

callbacks.notify = controller.notifyToast

callbacks.start = function(config)
  if not server then
    server = love.mintmousse.require("thread.server")
    server.handleIncomingEvent = function(request)
      if request.type == "text/utf8" or request.type == "application/json" then
        -- attempt json convert & handle
        local success, payload = pcall(json.decode, request.payload)
        if not success then
          love.mintmousse.warning("Couldn't decode incoming event request via json. Got error: ", payload)
          return
        end

        if payload.event then
          
          return
        end

        return
      end
      love.mintmousse.warning("Unhandled incoming server event! Type:", request.type)
    end
  end
  if config then
    if type(config.title) == "string" then
      callbacks.setTitle(config.title)
    end
    if type(config.whitelist) == "table" then
      for _, v in ipairs(config.whitelist) do
        server.addToWhitelist(v)
      end
    elseif type(config.whitelist) == "string" then
      server.addToWhitelist(config.whitelist)
    end
  end

  server.start(config and config.host, config and config.httpPort)
end

http.addMethod("GET", "/index", function(request)
  return 200, {
    ["cache-control"] = love.mintmousse.CACHE_CONTROL_HEADER,
    ["content-type"] = "text/html; charset=utf8",
  }, controller.getIndex()
end)

http.addMethod("GET", "/index.js", function(request)
  return 200, {
    ["cache-control"] = love.mintmousse.CACHE_CONTROL_HEADER,
    ["content-type"] = "text/javascript; charset=utf8",
  }, controller.javascript
end)

http.addMethod("GET", "/index.css", function(request)
  return 200, {
    ["cache-control"] = love.mintmousse.CACHE_CONTROL_HEADER,
    ["content-type"] = "text/css; charset=utf8",
  }, controller.css
end)

http.addMethod("GET", "/api/ping", function(request)
  return 204, {
    ["cache-control"] = "no-store",
  }, nil
end)

websocket13.newConnection = function(client)
  local array = controller.getInitialPayload()
  table.insert(client.queue, {
    type = "text/utf8",
    payload = array,
  })
end

controller.update = function(jsonPayload)
  if not server or not server.isRunning() then
    return
  end
  local payload = {
    type = "text/utf8",
    payload = "["..jsonPayload.."]",
  }
  for client in pairs(server.clients) do
    if client.connection.type == "WS/13" then
      table.insert(client.queue, payload)
    end
  end
end

while true do
  for _ = 1, 50 do
    local message = love.mintmousse.pop()
    if type(message) ~= "table" then
      break
    end
    if message.func == "quit" then
      if server then
        server.cleanUp()
      end
      return
    end
    if type(message.func) == "string" then
      local func = callbacks[message.func]
      if type(func) == "function" then
        local success, errorMessage = pcall(func, unpack(message))
        if not success then
          love.mintmousse.warning("Failed to process message:", message.func, ". Error:", errorMessage)
        end
      else
        love.mintmousse.warning("Could not find callback for:", message.func)
      end
    end
  end
  if server and server.isRunning() then
    server.newIncomingConnection()
    server.updateConnections()
  end
  love.timer.sleep(0.0001)
end