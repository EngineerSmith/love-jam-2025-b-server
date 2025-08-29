local args = ...

local port = tonumber(args["--port"])
if type(port) ~= "number" or 1023 > port or port > 65535 then
  port = 53135
  print("Game server using default port: 53135")
end

require("libs.mintmousse")

local ACTIVE_TICK_RATE = 20
local IDLE_TICK_RATE = 5
local ACTIVE_TICK_DURATION = 1 / ACTIVE_TICK_RATE
local IDLE_TICK_DURATION = 1 / IDLE_TICK_RATE

local ltr = require("love.timer")

local channel = love.thread.getChannel("channel")
ltr.step()
while true do
  while channel:getCount() > 0 do
    local message = channel:pop()
    if message == "quit" then
      return
    end
  end
  local start = ltr.getTime()
  -- ...
  local playerCount = 0
  local elapsed = ltr.getTime() - start
  local sleepTime = (playerCount == 0 and IDLE_TICK_DURATION or ACTIVE_TICK_DURATION) - elapsed
  if sleepTime > 0 then
    ltr.sleep(sleepTime)
  end
end