love.logging = {
  timestampEnable = true, -- if timestamp should be appended to log messages
  timestampFormat = "%Y-%m-%d %H:%M:%S", -- os.date format
  enablePrint = true, -- if love.mintmousse logging functions call global 'print' function
  enableError = true, -- if love.mintmousse.error calls global 'error' function
    -- Note; turning this off could cause functions to try and continue into undefined behaviour
    -- Note; love.mintmousse's own thread ignore enableError, and will always call global 'error' function
  warningsCauseErrors = false, -- Should warnings be treated as errors, and call love.mintmousse.error instead
-- internal usage
  _sinks = { },
}

local prefix = "Game" .. (love.isThread and " Thread" or "") .. ": "
local logPrefix = {
  info  = prefix .. "info:",
  warn  = prefix .. "warn:",
  error = prefix .. "error:",
}
prefix = nil
local errorDepthOffset = 0

local getTimestamp = function()
  return os.date(love.logging.timestampFormat)
end

local createLogMessage = function(logLevel, ...)
  local message
  if love.logging.timestampEnable then
    message = { getTimestamp(), logPrefix[logLevel], ... }
  else
    message = { logPrefix[logLevel], ... }
  end
  return table.concat(message, " ")
end

local dispatchToSinks = function(logLevel, ...)
  for _, sink in ipairs(love.logging._sinks) do
    sink(logLevel, ...)
  end
end

-- Sink must be a function which 1st argument is the log level['info', 'warn', 'error'], and subsequent arguments are the message parts
--   Error may pass an addition argument which is debug info to identify the location of where the error took place.
love.logging.addLogSink = function(sink)
  assert(type(sink) == "function", "1st argument was not type function")
  table.insert(love.logging._sinks, sink)
end

love.logging.info = function(...)
  if #love.logging._sinks == 0 and not love.logging.enablePrint then
    return
  end

  if love.logging.enablePrint then
    print(createLogMessage("info", ...))
  end

  dispatchToSinks("info", ...)
end

love.logging.warning = function(...)
  if #love.logging._sinks == 0 and not love.logging.enablePrint then
    return
  end
  if love.logging.warningsCauseErrors then
    errorDepthOffset = errorDepthOffset + 1
    love.logging.error(...)
    errorDepthOffset = errorDepthOffset - 1
    return
  end

  if love.logging.enablePrint then
    print(createLogMessage("warn", ...))
  end

  dispatchToSinks("warn", ...)
end

love.logging.error = function(...)
  if #love.logging._sinks == 0 and not love.logging.enablePrint and not love.logging.enableError then
    return
  end

  local debugInfo
  if type(debug) == "table" and type(debug.getinfo) == "function" then
    local info = debug.getinfo(2 + errorDepthOffset, "fnS")
    if info then
      local name = info.name and info.name or info.func and tostring(info.func):gsub("function: ", "") or "UNKNOWN"
      if info.short_src then
        name = name .. "@" .. info.short_src .. (info.linedefined and "#" .. info.linedefined or "")
      end
      debugInfo = name .. ": "
    end
  end

  if debugInfo then
    dispatchToSinks("error", debugInfo, ...)
  else
    dispatchToSinks("error", ...)
  end

  local message = debugInfo and createLogMessage("error", debugInfo, ...) or createLogMessage("error", ...)
  if love.logging.enablePrint then
    print(message)
  end
  if love.logging.enableError or love.isMintMousseServerThread then
    error(message)
  end
end

love.logging.assert = function(condition, ...)
  if not condition then
    errorDepthOffset = errorDepthOffset + 1
    love.logging.error(...)
    errorDepthOffset = errorDepthOffset - 1
  end
end

love.logging._metafunctionDepth = function(state)
  if state == "entered" then
    errorDepthOffset = errorDepthOffset + 1
  elseif state == "exited" then
    errorDepthOffset = errorDepthOffset - 1
  else
    error("You spelt it wrong:", "'"..tostring(state).."'", "::: Tell EngineerSmith")
  end
end