if jit then
  jit.on()
end

local identity = "EngineerSmith-Love-Jam-2025-B"
love.filesystem.setIdentity(identity, true)
love.setDeprecationOutput(true)

require("libs.mintmousse.prepare")()

love.conf = function(t)
  t.console = true
  t.version = "12.0"
  t.identity = identity
  t.title = identity
  t.appendidentity = true

  t.window = nil
  t.audio = nil
  t.graphics = nil

  t.modules.joystick = false
  t.modules.touch = false
  t.modules.image = false
  t.modules.graphics = false
  t.modules.audio = false
  t.modules.physics = false
  t.modules.sensor = false
  t.modules.sound = false
  t.modules.font = false
  t.modules.window = false
  t.modules.video = false

  t.modules.data = true
  t.modules.event = true
  t.modules.keyboard = true
  t.modules.mouse = true
  t.modules.timer = true
  t.modules.math = true
  t.modules.system = true
  t.modules.thread = true
end