local args = ...

local ltr = require("love.timer")
require("love.data")
require("love.event")

require("libs.mintmousse")
require("util.logging")

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

local ACTIVE_TICK_RATE = 20
local IDLE_TICK_RATE = 5
local ACTIVE_TICK_DURATION = 1 / ACTIVE_TICK_RATE
local IDLE_TICK_DURATION = 1 / IDLE_TICK_RATE
local PROCESS_BUDGET_RATIO = 0.40

POST = function(packetType, client, encodedData)
  -- todo handle incoming 
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