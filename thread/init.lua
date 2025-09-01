local args = ...

local ltr = require("love.timer")
require("love.data")
require("love.event")

require("libs.mintmousse")
require("util.logging")

require("love.math")
local uuidRNG = love.math.newRandomGenerator(os.time())
local uuidTemplate = "xxxxx-xxxxx-xxxxx-xxxxx-xxxxx-xxxxx"
getUUID = function()
  return uuidTemplate:gsub("[x]", function(_)
    return ("%x"):format(uuidRNG:random(0, 0xf))
  end)
end

local room = require("thread.room")

-- MM
love.mintmousse.updateSubscription("dashboard")
local tab = love.mintmousse.newTab("Dashboard", "dashboard")
local playerListCard = tab:newCard({ size = 1 })
  :addCardHeader({ text = "Players", id = "playerListTitle" })
  :newCardBody()
    :addCardText({
      id = "playerList",
      text = "",
    })
    .back
local playerListTitle = love.mintmousse.get("playerListTitle")
local playerListText = love.mintmousse.get("playerList")
--

local port = tonumber(args["--port"])
if type(port) ~= "number" or 1023 > port or port > 65535 then
  port = 53135
end

local server = require("thread.server")
local success = server.start(port)
if not success then
  love.logging.warning("Could not start server, quitting")
  love.event.quit()
  return
end

local ACTIVE_TICK_RATE = 30
local IDLE_TICK_RATE = 10
local ACTIVE_TICK_DURATION = 1 / ACTIVE_TICK_RATE
local IDLE_TICK_DURATION = 1 / IDLE_TICK_RATE
local PROCESS_BUDGET_RATIO = 0.40

local serialize = require("util.serialize")
local handlers = { }
addHandler = function(type_, cb)
  if not handlers[type_] then
    handlers[type_] = { cb }
  else
    table.insert(handlers[type_], cb)
  end
end

POST = function(packetType, client, encodedData)
  -- todo handle incoming
  if packetType == enum.packetType.receive then
    local decoded
    if encodedData then
      local success
      success, decoded = pcall(serialize.decodedIndexed, encodedData:getString())
      if not success then
        print("WARN< Could not decode incoming data")
        return
      end
    end
    local type_ = decoded[1]
    if not type_ or type(handlers[type_]) ~= "table" then
      print("WARN< There were no handlers for received type: ".. tostring(type_))
      return
    end
    for _, callback in ipairs(handlers[type_]) do
      callback(client, unpack(decoded, 2))
    end
  else
    print("> PacketType not handled:", packetType)
  end
end

local channel = love.thread.getChannel("channel")
local channelOut = love.thread.getChannel("outChannel")
ltr.step()
local step = 0
while true do
  step = step + 1
  while channel:getCount() > 0 do
    local message = channel:pop()
    if message == "quit" then
      love.logging.info("Server thread received quit command.")
      server.stop()
      ltr.sleep(0.050)
      return
    end
  end
  local tickDuration = (server.getPlayerCount() == 0 and IDLE_TICK_DURATION or ACTIVE_TICK_DURATION)
  local start = ltr.getTime()

  -- incoming
  local budgetEndTime = start + tickDuration * PROCESS_BUDGET_RATIO
  server.process(budgetEndTime)
  -- game logic
  -- todo
  -- outgoing
  server.processOutgoing()
  -- ...
  local elapsed = ltr.getTime() - start
  local sleepTime = tickDuration - elapsed
  if sleepTime > 0 then
    ltr.sleep(sleepTime)
  end
  -- MintMousse
  if step % 20 == 0 then
    playerListTitle.text = "Players - "..server.getPlayerCount()
    playerListText.text = server.getPlayerNameList()
  end
end