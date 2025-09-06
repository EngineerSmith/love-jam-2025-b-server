local projectileTypes =  {
  ["player"] = {
    movementSpeed = 500,
  }
}

local projectile = { }
projectile.__index = projectile

projectile.new = function(ownerUUID, type_, x, y, moveX, moveY, UUID)
  local type_ = projectileTypes[type_]
  return setmetatable({
    x = x,
    y = y,
    moveX = moveX,
    moveY = moveY,
    type_ = type_,
    movementSpeed = type_ and type_.movementSpeed or 500,
    ownerUUID = ownerUUID,
    UUID = UUID,
    isActive = true,
  }, projectile)
end

projectile.update = function(self, dt)
  self.x = self.x + self.moveX * self.movementSpeed * dt
  self.y = self.y + self.moveY * self.movementSpeed * dt
end

local projectileManager = { }
projectileManager.__index = projectileManager

projectileManager.new = function()
  return setmetatable({ 
    activeProjectiles = { },
  }, projectileManager)
end

projectileManager.createProjectile = function(self, ownerUUID, type_, localUUID, x, y, moveX, moveY, timestamp)
  local UUID = getUUID()
  local newProjectile = projectile.new(ownerUUID, type_, x, y, moveX, moveY, UUID)

  self.activeProjectiles[UUID] = newProjectile

  self.sendAll("projectileReplicated", newProjectile.ownerUUID, UUID, localUUID, type_, newProjectile.x, newProjectile.y, newProjectile.moveX, newProjectile.moveY)

  return newProjectile
end

local limit = 1000000
projectileManager.update = function(self, dt)
  local projectilesToRemove = { }
  for uuid, projectile in pairs(self.activeProjectiles) do
    projectile:update(dt)

    if projectile.x < -limit or projectile.x > limit or projectile.y < -limit or projectile.y > limit then
      projectile.isActive = false
    end
    if not projectile.isActive then
      table.insert(projectilesToRemove, uuid)
    end
  end

  for _, uuid in ipairs(projectilesToRemove) do
    self.activeProjectiles[uuid] = nil
    self.sendAll("projectileDestroyed", uuid)
  end
end

return projectileManager