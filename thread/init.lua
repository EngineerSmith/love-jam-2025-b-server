local args = ...

local ltr = require("love.timer")

require("libs.mintmousse")
require("util.logging")

local port = tonumber(args["--port"])
if type(port) ~= "number" or 1023 > port or port > 65535 then
  port = 53135
end
love.logging.info("Game server starting on port:", port)

local ACTIVE_TICK_RATE = 20
local IDLE_TICK_RATE = 5
local ACTIVE_TICK_DURATION = 1 / ACTIVE_TICK_RATE
local IDLE_TICK_DURATION = 1 / IDLE_TICK_RATE

local channel = love.thread.getChannel("channel")
ltr.step()
while true do
  while channel:getCount() > 0 do
    local message = channel:pop()
    if message == "quit" then
      love.logging.info("Server thread received quit command.")
      -- todo disconnect clients
      ltr.sleep(0.001) -- 1ms
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