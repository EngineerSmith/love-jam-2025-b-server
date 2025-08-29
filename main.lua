local love = love
local le, ltr = love.event, love.timer

local args = require("util.args")
require("util.logging")

local mintMoussePort = tonumber(args["--mmport"]) or 80
local mintMousseWhitelist = { "127.0.0.1", "192.168.0.0/16" }
if type(args["--mmwhitelist"]) == "table" and #args["--mmwhitelist"] >= 1 then
  mintMousseWhitelist = args["--mmwhitelist"]
end

require("libs.mintmousse")
love.logging.info("Starting MintMousse on port", mintMoussePort)
love.logging.info("MintMousse whitelist set to:", table.concat(mintMousseWhitelist, " & "))
love.mintmousse.start({
  title = "Love Jam 2025 B side",
  httpPort = mintMoussePort,
  whitelist = mintMousseWhitelist,
})

local processEvents = function()
  le.pump()
  for name, a, b, c, d, e, f in le.poll() do
    if name == "quit" then
      if not love.quit or not love.quit() then
        return a or 0
      end
    end
    love.handlers[name](a, b, c, d, e, f)
  end
  return nil
end

-- https://gist.github.com/1bardesign/3ed0fabfdcd2661d3308b4da7fa3076d
local manualGC = function(timeBudget, safetyNetMB)
  local limit, steps = 1000, 0
  local start = ltr.getTime()
  while ltr.getTime() - start < timeBudget and steps < limit do
    collectgarbage("step", 1)
    steps = steps + 1
  end
  if collectgarbage("count") / 1024 > safetyNetMB then
    collectgarbage("collect")
  end
end

love.logging.info("Creating server thread")
local channel = love.thread.getChannel("channel")
local thread = love.thread.newThread("thread/init.lua")

love.run = function()
  local loop = function()
    local quit = processEvents()
    if quit then
      love.logging.info("Exiting...")
      return quit
    end

    manualGC(0.005, 128) -- 5ms
    ltr.sleep(0.050) -- 50ms, server main thread can mostly sleep and process SDL events
  end

  love.logging.info("Starting server thread")
  thread:start(args)

  return loop
end

love.quit = function()
  if thread:isRunning() then
    channel:push("quit")
    love.logging.info("Waiting for server thread to rejoin main thread")
    thread:wait()
    love.logging.info("Server thread has rejoined")
  end
  love.logging.info("Telling MintMousse to stop")
  love.mintmousse.stop()
  love.logging.info("MintMousse has stopped.")
  return false -- exit love
end