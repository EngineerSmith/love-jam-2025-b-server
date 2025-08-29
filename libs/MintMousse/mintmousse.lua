local love = love
local lfs = love.filesystem

if love.isThread == nil then
  love.isThread = arg == nil
end

if not jit then
  error("Library MintMousse requires lua jit; this is usually packaged with love.")
end
local success = pcall(require, "string.buffer")
if not success then
  error("Library MintMousse requires lua jit with string buffer; update your love version or supply your own lua.dll/lua.so that it includes it.")
end

-- Load love modules that may be disabled, because we need them.
require("love.thread")
require("love.event")
require("love.timer")
require("love.data")
require("love.math") -- todo check if can be removed

local createBuffer = function()
  local bufferMetatable = { }

  local channelDictionary = love.thread.getChannel(love.mintmousse.READONLY_BUFFER_DICTIONARY_ID)
  if not channelDictionary:peek() then
    local dictionary, lookup = {
      "id",
      "type",
      "func",
      "quit",
      "size",
      "text",
      "start",
      "style",
      "color",
      "update",
      "latest",
      "parent",
      "newTab",
      "creator",
      "setTitle",
      "children",
      "parentID",
      "setSVGIcon",
      "setIconRaw",
      "setIconRFG",
      "mintmousse",
      "addComponent",
      "componentAdded",
      "updateComponent",
      "removeComponent",
      "setIconFromFile",
      "componentRemoved",
      "updateSubscription",
    }, { }
    for index, word in ipairs(dictionary) do
      assert(not lookup[word], "You've duplicated a word in the list! " .. index .. " index was already added")
      lookup[word] = true
    end
    -- todo!! Add commonly found strings to push into dictionary
    --   This is unlikely to happen now components are loaded on a thread and checked at the end of this file

    channelDictionary:push(dictionary)
  end

  local buffer = require("string.buffer").new({
    dict = channelDictionary:peek(),
    metatable = bufferMetatable,
  })

  return buffer
end

return function(path, directoryPath)
  if love.mintmousse then
    local err = type(love.mintmousse) == "table" and love.mintmousse.error or error
    return err("mintmousse/mintmousse.lua has already been ran, or there is a conflict in namespace with love.mintmousse")
  end

  love.mintmousse = {
    path = path,
    directoryPath = directoryPath,

    -- Internal use per thread
    _hinting = {
      -- Hinting data received from the main MintMousse thread
      typeMap = { },
      relationships = { },
      -- Hinting locally generated from components created by this thread
      localTypeMap = { },
      localRelationships = { },
    },
    _proxyComponents = { },
    _componentTypes = nil, -- given via blocking call at bottom of this file
  }

  love.mintmousse.require = function(file)
    return require(love.mintmousse.path .. file)
  end

  local conf = love.mintmousse.require("conf")(love.mintmousse.path, love.mintmousse.directoryPath)
  for k, v in pairs(conf) do
    love.mintmousse[k] = v
  end

  -- Start MintMousse's thread
  local startThread = love.mintmousse.require("prepare")
  startThread()

  love.mintmousse.read = function(file)
    return lfs.read(love.mintmousse.directoryPath .. file)
  end

  local buffer = createBuffer()
  love.mintmousse._encode = function(message)
    return buffer:reset():encode(message):get()
  end

  love.mintmousse._decode = function(encodedMessage)
    return buffer:set(encodedMessage):decode()
  end

  local COMMAND_QUEUE = love.thread.getChannel(love.mintmousse.THREAD_COMMAND_QUEUE_ID)
  love.mintmousse.push = function(message)
    COMMAND_QUEUE:push(love.mintmousse._encode(message))
  end

  if love.isMintMousseServerThread then
    -- only the mintmousse thread should pop the command queue!
    love.mintmousse.pop = function()
      local encodedMessage = COMMAND_QUEUE:pop()
      if not encodedMessage then
        return nil
      end
      return love.mintmousse._decode(encodedMessage)
    end

    love.mintmousse.popRaw = function()
      return COMMAND_QUEUE:pop()
    end

    love.mintmousse.threadID = "MintMousse"
  end

  local threadIDLength = 11
  if not love.isMintMousseServerThread then
    -- todo match AppleCake; recently checked AppleCake, it just numbers threads based on order of initialisation
    love.mintmousse.threadID = ("x"):rep(threadIDLength):gsub("[x]", function(_) return ("%x"):format(love.math.random(0, 15)) end)
  end

  if not love.isThread then -- main thread
    love.mintmousse.threadID = "main"

    love.handlers[love.mintmousse.THREAD_RESPONSE_QUEUE_ID] = function(enum, ...)
      -- todo; should all events go back to the main thread now that MM supports multithreaded calls?
        -- implementing event checking on each user thread would require a repeat call
      error("TODO")
    end

    love.mintmousse.start = function(config)
      local threadChannel = love.thread.getChannel(love.mintmousse.READONLY_THREAD_LOCATION)
      threadChannel:performAtomic(function()
        local thread = threadChannel:peek()
        if not thread:isRunning() then
          thread:start(love.mintmousse.path, love.mintmousse.directoryPath)
        end
      end)
      -- todo validate
      love.mintmousse.push({
        func = "start",
        config,
      })
    end

    love.mintmousse.stop = function(noWait)
      COMMAND_QUEUE:performAtomic(function()
        COMMAND_QUEUE:clear()
        love.mintmousse.push({
          func = "quit",
        })
      end)
      if not noWait then
        love.mintmousse.wait()
      end
    end

    love.mintmousse.wait = function()
      local threadChannel = love.thread.getChannel(love.mintmousse.READONLY_THREAD_LOCATION)
      threadChannel:performAtomic(function()
        local thread = threadChannel:peek()
        thread:wait()
      end)
    end

  else
    love.mintmousse.pushEvent = function(enum, ...)
      love.event.push(love.mintmousse.THREAD_RESPONSE_QUEUE_ID, enum, ...)
    end
  end

  love.mintmousse.require("logging")

  -- Only use this if necessary. All MintMousse components will handle sanitizing for you.
  --   If you have non-standard components, it may help to sanitize to avoid XSS attacks
  love.mintmousse.sanitizeText = function(text)
    local lustache = love.mintmousse.require("libs.lustache") -- only grab lustache on the thread if they need to use it
    return lustache:render("{{text}}", { text = text })
  end

  if love.isMintMousseServerThread then
    return
  end

  local _idCounter = 0
  love.mintmousse.generateID = function()
    local id = "MM_" .. love.mintmousse.threadID .. (_idCounter >= 100 and "_"..string.char(threadIDLength*7, threadIDLength*7, threadIDLength*6-1, 99, 101).."_%x" or "_%x"):format(_idCounter)
    _idCounter = _idCounter + 1
    return id
  end

  love.mintmousse.isValidID = function(id)
    if type(id) ~= "string" then
      return false, "ID isn't type string"
    end
    local failed = id:match("[^%w%._,:;@]")
    if failed then
      return false, "ID Can only contain alphanumeric or . _ , : ; @ characters. Failed character:'"..tostring(failed.."'")
    end
    if id:find("^%d") then
      return false, "ID cannot use a numeric as the first character of an id"
    end
    if id == "all" then
      return false, "ID cannot use the protected keyword 'all'"
    elseif id == "unknown" then
      return false, "ID cannot use the protected keyword 'unknown'"
    end
    return true, nil
  end

  local cleanUpLocalHinting = function()
    -- Remove acknowledged type hints
    for id in pairs(love.mintmousse._hinting.localTypeMap) do
      if love.mintmousse._hinting.typeMap[id] then
        love.mintmousse._hinting.localTypeMap[id] = nil
      end
    end

    -- Remove acknowledged relationships hints
    -- pairs are used as local relationships may not be an unbroken indexed table
    for id, relationships in pairs(love.mintmousse._hinting.localRelationships) do
      if love.mintmousse._hinting.relationships[id] then
        for index in pairs(relationships) do
          if love.mintmousse._hinting.relationships[id][index] then
            love.mintmousse._hinting.localRelationships[id][index] = nil
          end
        end
      end
      local hasIndex = false
      for _ in pairs(love.mintmousse._hinting.localRelationships[id]) do
        hasIndex = true
        break
      end
      if not hasIndex then
        love.mintmousse._hinting.localRelationships[id] = nil
      end
    end
  end

  local hintingComponentAdded 
  hintingComponentAdded = function(packagedComponent)
    love.mintmousse._hinting.typeMap[packagedComponent.id] = packagedComponent.type
    love.mintmousse._hinting.localTypeMap[packagedComponent.id] = nil
    local relationships = { }
    love.mintmousse._hinting.relationships[packagedComponent.id] = relationships
    if packagedComponent.children then

      local localRelationships = love.mintmousse._hinting.localRelationships[packagedComponent.id]
      for index, child in ipairs(packagedComponent.children) do
        relationships[index] = child.id
        if localRelationships then
          for localIndex, childID in pairs(localRelationships) do
            if childID == child.id then
              localRelationships[localIndex] = nil
              break
            end
          end
        end
        hintingComponentAdded(child)
      end
      local hasIndex = false
      for _ in pairs(localRelationships) do
        hasIndex = true
        break
      end
      if not hasIndex then
        love.mintmousse._hinting.localRelationships[packagedComponent.id] = nil
      end
    end
  end

  -- This function doesn't check locals as someone may remove a component, and then add a new component with the same id
  --     hintingComponentAdded should handle all cases; I don't foresee a race condition edge case where a component is removed without there being an added event
  local hintingComponentRemoved
  hintingComponentRemoved = function(packagedComponent)
    love.mintmousse._hinting.typeMap[packagedComponent.id] = nil
    if packagedComponent.children then
      for _, child in ipairs(packagedComponent.children) do
        hintingComponentRemoved(child)
      end
    end
    love.mintmousse._hinting.relationships[packagedComponent.id] = nil
  end

  local localHintingRemove
  localHintingRemove = function(id)
    if love.mintmousse._hinting.localTypeMap[id] then
      love.mintmousse._hinting.localTypeMap[id] = nil
    end
    local children = love.mintmousse._hinting.localRelationships[id]
    if children then
      for _, childID in ipairs(children) do
        localHintingRemove(childID)
      end
    end
    love.mintmousse._hinting.localRelationships[id] = nil
  end

  local COMPONENT_UPDATES_QUEUE = love.thread.getChannel(love.mintmousse.THREAD_COMPONENT_UPDATES_ID:format(love.mintmousse.threadID))
  love.mintmousse.processSubscription = function(max)
    love.mintmousse.assert(type(max) == "number" or type(max) == "nil", "Max must be type Number, or Nil")
    for _ = 1, max or love.mintmousse.SUBSCRIPTION_MAX_QUEUE_READ do
      local package = COMPONENT_UPDATES_QUEUE:pop()
      if not package then
        return
      end
      package = love.mintmousse._decode(package)
      if package.type == "latest" then
        love.mintmousse._hinting.typeMap = package.typeMap
        love.mintmousse._hinting.relationships = package.relationships
        cleanUpLocalHinting()
      elseif package.type == "componentAdded" then
        local packagedComponent, parentChildIndex = unpack(package)
        hintingComponentAdded(packagedComponent)
        if packagedComponent.parentID then
          table.insert(love.mintmousse._hinting.relationships[packagedComponent.parentID], parentChildIndex, packagedComponent.id)
        end
      elseif package.type == "componentRemoved" then
        local packagedComponent, parentChildIndex = unpack(package)
        hintingComponentRemoved(packagedComponent)
        table.remove(love.mintmousse._hinting.relationships[packagedComponent.parentID], parentChildIndex)
      else
        love.mintmousse.error("Package types hasn't been updated if new types have been added. Tell a programmer:", package.type)
        return
      end
    end
  end

  love.mintmousse.getType = function(id)
    love.mintmousse.processSubscription()
    local componentType = love.mintmousse._hinting.typeMap[id]
    if not componentType then
      componentType = love.mintmousse._hinting.localTypeMap[id]
    end
    return componentType or "unknown"
  end

  local childrenMetatable
  childrenMetatable = {
    __index = function(tbl, index)
      if index == "length" or index == "len" then
        return childrenMetatable.__len(tbl)
      end
      love.mintmousse._metafunctionDepth("entered")
      if type(index) ~= "number" then
        love.mintmousse._metafunctionDepth("exited")
        return nil
      end
      local relationships = love.mintmousse._hinting.relationships
      if (#relationships or 0) > index then
        relationships = love.mintmousse._hinting.relationships
      end
      if not relationships then
        love.mintmousse._metafunctionDepth("exited")
        return nil
      end
      local childID = relationships[index]
      local childProxyTable = love.mintmousse.get(childID)
      love.mintmousse._metafunctionDepth("exited")
      return childProxyTable
    end,
    __newindex = function(tbl, index, value)
      love.mintmousse._metafunctionDepth("entered")
      love.mintmousse.error("Proxy Table: You cannot change children, table values directly.")
      love.mintmousse._metafunctionDepth("exited")
      return
    end,
    __len = function(tbl)
      love.mintmousse._metafunctionDepth("entered")
      local id = rawget(tbl, "__id")
      local relationships = love.mintmousse._hinting.relationships[id]
      local count = relationships and #relationships or 0
      local localRelationships = love.mintmousse._hinting.localRelationships[id]
      if localRelationships then
        while true do
          if localRelationships[count+1] ~= nil then
            count = count + 1
          else
            break
          end
        end
      end
      love.mintmousse._metafunctionDepth("exited")
      return count
    end,
  }

  local proxyTableNew = function(tbl, component)
    local self = rawget(tbl, "__raw")
    local id = rawget(self, "id")
    return love.mintmousse.addComponent(component, id)
  end

  local proxyTableAdd = function(tbl, component)
    local self = rawget(tbl, "__raw")
    local id = rawget(self, "id")
    love.mintmousse.addComponent(component, id)
    return tbl
  end

  local proxyTableRemoveSelf = function(tbl)
    local self = rawget(tbl, "__raw")
    local id = rawget(self, "id")
    return love.mintmousse.removeComponent(id)
  end

  local proxyTableGetChildren = function(id)
    return setmetatable({
      __id = id,
    }, childrenMetatable)
  end

  local cachedCreationMethods = {
    new = { },
    add = { }
  }

  local getNewMethod = function(componentType)
    local cachedNewMethods = cachedCreationMethods["new"]
    if not cachedNewMethods[componentType] then
      cachedNewMethods[componentType] = function(tbl, component)
        component = component or { }
        component.type = componentType
        return proxyTableNew(tbl, component)
      end
    end
    return cachedNewMethods[componentType]
  end

  local getAddMethod = function(componentType)
    local cachedAddMethods = cachedCreationMethods["add"]
    if not cachedAddMethods[componentType] then
      cachedAddMethods[componentType] = function(tbl, component)
        component = component or { }
        component.type = componentType
        return proxyTableAdd(tbl, component)
      end
    end
    return cachedAddMethods[componentType]
  end

  local proxyTableMetatable
  proxyTableMetatable = {
    __newindex = function(tbl, index, value)
      if index == "__raw" then return nil end
      love.mintmousse._metafunctionDepth("entered")
      if index == "type" then
        love.mintmousse.error("Proxy Table: You cannot change that index:", "type")
        love.mintmousse._metafunctionDepth("exited")
        return
      end
      if index == "id" then
        love.mintmousse.error("Proxy Table: You cannot change that index:", "id")
        love.mintmousse._metafunctionDepth("exited")
        return
      end
      if index == "parentID" then
        love.mintmousse.error("Proxy Table: You cannot change that index:", "parentID")
        love.mintmousse._metafunctionDepth("exited")
        return
      end
      if index == "creator" then
        love.mintmousse.error("Proxy Table: You cannot change that index:", "creator")
        love.mintmousse._metafunctionDepth("exited")
        return
      end
      if type(index) == "number" then
        love.mintmousse.error("Proxy Table: You cannot change that index:", index, ". As it is related to the child table.")
        love.mintmousse._metafunctionDepth("exited")
        return
      end
      local self = rawget(tbl, "__raw")
      if rawget(self, index) == value then
        love.mintmousse._metafunctionDepth("exited")
        return
      end
      rawset(self, index, value)
      local id = rawget(self, "id")
      local componentType = love.mintmousse.getType(id)
      local notComplete = love.mintmousse._componentTypes["unknown"]
      if notComplete then
        local componentTypesChannel = love.thread.getChannel(love.mintmousse.READONLY_BASIC_TYPES_ID)
        love.mintmousse._componentTypes = componentTypesChannel:peek()
        notComplete = love.mintmousse._componentTypes["unknown"]
      end
      local sendUpdate = false
      if componentType == "unknown" or notComplete then
        sendUpdate = true
      else
        local updates = love.mintmousse._componentTypes[componentType].updates
        sendUpdate = updates and updates[index] ~= nil
      end
      if sendUpdate then
        love.mintmousse.push({
          func = "updateComponent",
          id, index, value
        })
      end
      -- check parent
      local parentID = rawget(self, "parentID")
      local parentComponentType = love.mintmousse.getType(parentID)
      local sendChildUpdate = false
      if parentComponentType == "unknown" or notComplete then
        sendChildUpdate = true
      else
        local childUpdates = love.mintmousse._componentTypes[parentComponentType].childUpdates
        sendChildUpdate = childUpdates and childUpdates[index] ~= nil
      end
      if sendChildUpdate then
        love.mintmousse.push({
          func = "updateParentComponent",
          parentID, id, index, value
        })
      end
      love.mintmousse._metafunctionDepth("exited")
    end,
    __index = function(tbl, index)
      if index == "__raw" then return nil end
      love.mintmousse._metafunctionDepth("entered")
      local self = rawget(tbl, "__raw")
      if index == "parent" or index == "back" then
        local parentID = rawget(self, "parentID")
        local v = parentID and love.mintmousse.get(parentID) or nil
        love.mintmousse._metafunctionDepth("exited")
        return v
      elseif index == "remove" then
        love.mintmousse._metafunctionDepth("exited")
        return proxyTableRemoveSelf
      elseif index == "type" then
        local id = rawget(self, "id")
        local componentType = love.mintmousse.getType(id)
        love.mintmousse._metafunctionDepth("exited")
        return componentType
      elseif index == "children" or type(index) == "number" then
        local children = rawget(tbl, "__proxyChildren")
        if type(index) == "number" then
          local child = children[index]
          love.mintmousse._metafunctionDepth("exited")
          return child
        end
        love.mintmousse._metafunctionDepth("exited")
        return children
      elseif index == "new" then
        love.mintmousse._metafunctionDepth("exited")
        return proxyTableNew
      elseif index == "add" then
        love.mintmousse._metafunctionDepth("exited")
        return proxyTableAdd
      elseif type(index) == "string" and #index > 3 then
        local sub = index:sub(1, 3)
        local componentType = index:sub(4)
        -- ComponentType name must be in camelCase
        componentType = componentType:gsub("^(.)", function(c) return c:lower() end, 1)
        if sub == "new" then
          local func = getNewMethod(componentType)
          love.mintmousse._metafunctionDepth("exited")
          return func
        elseif sub == "add" then
          local func = getAddMethod(componentType)
          love.mintmousse._metafunctionDepth("exited")
          return func
        end
      end
      local v = rawget(self, index)
      if not v and (index == "length" or index == "len") then
        v = proxyTableMetatable.__len(tbl)
      end
      love.mintmousse._metafunctionDepth("exited")
      return v
    end,
    __len = function(tbl)
      love.mintmousse._metafunctionDepth("entered")
      local children = rawget(tbl, "__proxyChildren")
      local count = children.length
      love.mintmousse._metafunctionDepth("exited")
      return count
    end,
  }

  love.mintmousse.addToLocalHinting = function(id, componentType)
    if not love.mintmousse._componentTypes[componentType] then
      love.mintmousse.error("Gave invalid componentType. This type does not exist:", componentType)
      return
    end
    love.mintmousse._hinting.localTypeMap[id] = componentType
  end

  love.mintmousse.addToLocalRelationships = function(parentID, childID)
    local relationships = love.mintmousse._hinting.relationships[parentID]
    local count = relationships and #relationships + 1 or 1
    local localRelationships = love.mintmousse._hinting.localRelationships[parentID]
    if localRelationships then
      while true do
        if localRelationships[count + 1] ~= nil then
          count = count + 1
        else
          break
        end
      end
      table.insert(localRelationships, count, childID)
    else
      love.mintmousse._hinting.localRelationships[parentID] = {
        [count] = childID,
      }
    end
  end

  love.mintmousse.createProxyTable = function(raw)
    local proxyTable = setmetatable({
      __raw = raw,
      __proxyChildren = proxyTableGetChildren(raw.id),
    }, proxyTableMetatable)
    love.mintmousse._proxyComponents[raw.id] = proxyTable
    return proxyTable
  end

-- Front facing functions

  love.mintmousse.updateSubscription = function(target)
    if target ~= "all" and target ~= "none" then
      local isValid, errorMessage = love.mintmousse.isValidID(target)
      if not isValid then
        love.mintmousse.warning("Could not update subscription for thread. Gave invalid target assumed to be an ID:", errorMessage)
        return
      end
    end
    love.mintmousse.push({
      func = "updateSubscription",
      love.mintmousse.threadID, target,
    })
  end
  if not love.isMintMousseServerThread then
    -- default subscription, required for subscription to component types
    love.mintmousse.updateSubscription("none")
  end

  local pngMagicNumber = string.char(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
  local jpegMagicNumber = string.char(0xff, 0xd8, 0xff)
  love.mintmousse.setIcon = function(icon)
    if type(icon) == "table" then
      icon = love.mintmousse.require("thread.icon.svg_icon")(icon)
      love.mintmousse.push({
        func = "setSVGIcon",
        icon,
      })
      return
    elseif type(icon) == "string" then
      if lfs.getInfo(icon, "file") then
        local temp = icon:lower()
        if temp:match(".png$") or temp:match(".jpeg$") or temp:match(".jpg$") or temp:match(".svg$") then
          love.mintmousse.push({
            func = "setIconFromFile",
            icon,
          })
          return
        end
        love.mintmousse.warning("Valid file provided, invalid file extension. Only .PNG, .JPEG, or .JPG are supported for icon.")
        return
      elseif icon:sub(#pngMagicNumber) == pngMagicNumber then
        love.mintmousse.setIconRaw(icon, "image/png")
        return
      elseif icon:sub(#jpegMagicNumber) == jpegMagicNumber then
        love.mintmousse.setIconRaw(icon, "image/jpeg")
        return
      end
    end
    love.mintmousse.warning("Invalid icon provided. Please supply either an SVG table, a file path to a .PNG, .JPEG, or .JPG image, or raw PNG or JPEG image data (identified by their magic numbers)")
  end

  love.mintmousse.setIconRaw = function(icon, iconType)
    love.mintmousse.push({
      func = "setIconRaw",
      icon, iconType,
    })
  end

  -- https://realfavicongenerator.net @ 2025 Q1
  love.mintmousse.setIconRFG = function(filepath)
    love.mintmousse.assert(type(filepath) == "string", "Filepath must be type String")
    local temp = filepath:lower()
    love.mintmousse.assert(temp:match("$.zip"), "Invalid file path, must end with .ZIP file extension. Gave:", filepath)
    love.mintmousse.assert(lfs.getInfo(filepath), "Invalid file path, couldn't reach file with given path. Gave:", filepath)
    love.mintmousse.push({
      func = "setIconRFG",
      filepath,
    })
  end

  love.mintmousse.setTitle = function(title)
    love.mintmousse.assert(type(title) == "string", "Title must be type String")
    love.mintmousse.push({
      func = "setTitle",
      title,
    })
  end

  love.mintmousse.get = function(id, componentTypeHint)
    if type(componentTypeHint) == "string" then
      love.mintmousse.addToLocalHinting(id, componentTypeHint)
    end
    local proxyTable = love.mintmousse._proxyComponents[id]
    return proxyTable or love.mintmousse.createProxyTable({ id = id })
  end

  love.mintmousse.newTab = function(title, id, index) -- todo index
    local success, errorMessage = love.mintmousse.isValidID(id)
    if not success then
      love.mintmousse.error("Couldn't create tab with given ID. Reason:", errorMessage)
      return
    end
    love.mintmousse.addToLocalHinting(id, "tab")
    love.mintmousse.push({
      func = "newTab",
      id, title, index, love.mintmousse.threadID,
    })
    return love.mintmousse.createProxyTable({
      id = id,
      title = title,
      parentID = nil,
      creator = love.mintmousse.threadID,
    })
  end

  local loadComponentLogic = function(componentTypeName, componentType)
    if not componentType.hasComponentLogic then
      return -- Nothing to load
    end

    if componentType.componentLogic then
      return -- Already loaded
    end

    local path
    for i = #componentType.directories, 1, -1 do
      path = componentType.directories[i] .. componentTypeName .. ".lua"
      if lfs.getInfo(path, "file") then
        break
      else
        path = nil
      end
    end
    if not path then
      love.mintmousse.warning("Failed to discover path for component logic( ", componentTypeName, ")which was previous found in one of these directories:", table.concat(componentType.directories, ", "))
      return nil
    end
    local success, chunk, errorMessage = pcall(lfs.load, path)
    if not success then
      love.mintmousse.error("Failed to load component logic! For:", componentTypeName, ". Reason:", chunk)
      return
    end
    if not chunk then
      love.mintmousse.error("Failed to load component logic! For:", componentTypeName, ". Reason:", errorMessage)
      return
    end

    local success, componentLogic = pcall(chunk)
    if not success then
      love.mintmousse.error("Failed to run componentLogic! For:", componentTypeName, ". Reason:", componentLogic)
      return
    end
    componentType.componentLogic = componentLogic

    if not type(componentType.componentLogic) == "table" then
      love.mintmousse.warning("Tried to load component logic for", componentTypeName, ", but it didn't return a table type as expected.")
      componentType.componentLogic = nil
      componentType.hasComponentLogic = false -- stop it from trying to reload
      return
    end

    if type(componentType.componentLogic.onCreate) ~= "function" then
      componentType.componentLogic.onCreate = nil
    end

    if componentType.componentLogic.onCreate == nil then
      love.mintmousse.warning("Failed to load component logic for", componentTypeName, ", as it didn't contain functions for 'onCreate'.")
      componentType.componentLogic = nil
      componentType.hasComponentLogic = false -- stop it from trying to reload
      return
    end
  end

  -- Should this be a public function?
  -- todo: This function allows for circular dependency 
  love.mintmousse.addComponent = function(component, parentID)
    if type(component) == "string" then
      component = {
        type = component,
      }
    elseif type(component) ~= "table" then
      love.mintmousse.error("Component must be componentType (string) or a component (table)")
      return
    end
    if type(parentID) ~= "string" then
      love.mintmousse.error("ParentID is required to create component")
      return
    end

    if not component.id then
      component.id = love.mintmousse.generateID()
    end

    component.creator = love.mintmousse.threadID

    local success, errorMessage = love.mintmousse.isValidID(component.id)
    if not success then
      love.mintmousse.error("Gave invalid ID to create component. Reason:", errorMessage)
      return
    end

    if type(component.type) ~= "string" then
      love.mintmousse.error("Gave invalid componentType to create component. Reason:", "Component.type isn't type string")
      return
    end

    if component.type == "unknown" then
      love.mintmousse.error("Gave invalid componentType. Reason:", "Cannot create a component with type: 'unknown'. This is a protected keyword")
      return
    elseif component.type == "tab" then
      love.mintmousse.error("Gave invalid componentType. Reason:", "Cannot create a component with type: 'tab'. Please use love.mintmousse.newTab")
      return
    end

    -- Get latest componentTyping information
    local notComplete = love.mintmousse._componentTypes["unknown"]
    if notComplete then
      local componentTypesChannel = love.thread.getChannel(love.mintmousse.READONLY_BASIC_TYPES_ID)
      love.mintmousse._componentTypes = componentTypesChannel:peek()
      notComplete = love.mintmousse._componentTypes["unknown"]
    end

    local componentType = love.mintmousse._componentTypes[component.type]
    if not componentType then
      love.mintmousse.error("Gave invalid componentType. Reason:", "This type does not exist:", component.type)
      return
    end

    -- if notComplete; thread will reject it anyway - this just makes the error message more clear
    if not notComplete and not componentType.hasMustacheFile and not componentType.hasNewFunction then
      love.mintmousse.error("Gave invalid componentType. Reason:", "Cannot create a component with type:", "'"..tostring(component.type).."'.", "As it does not have a construction method (JS or HTML)")
      return
    end

    loadComponentLogic(component.type, componentType)
    if componentType.componentLogic and componentType.componentLogic.onCreate then
      local componentID, componentTYPE, componentCREATOR = component.id, component.type, component.creator

      componentType.componentLogic.onCreate(component) -- not pcall as the function should handle the error methods

      if component.id ~= componentID then
        love.mintmousse.error("Tried to change component 'id' within 'onCreate' componentLogic, type:", componentType, ". This is a protected value at this stage of creation.")
      end
      if component.type ~= componentTYPE then
        love.mintmousse.error("Tried to change component 'type' within 'onCreate' componentLogic, type:", componentType, ". This is a protected value at this stage of creation.")
      end
      if component.creator ~= componentCREATOR then
        love.mintmousse.error("Tried to change component 'creator' within 'onCreate' componentLogic, type:", componentType, ". This is a protected value at this stage of creation.")
      end
    end

    love.mintmousse.addToLocalHinting(component.id, component.type)
    love.mintmousse.addToLocalRelationships(parentID, component.id)
    love.mintmousse.push({
      func = "addComponent",
      component, parentID,
    })

    component.parentID = parentID
    return love.mintmousse.createProxyTable(component)
  end

  love.mintmousse.removeComponent = function(id)
    localHintingRemove(id);
    love.mintmousse.push({
      func = "removeComponent",
      id,
    })
  end

  love.mintmousse.notify = function(message)
    love.mintmousse.assert(type(message) == "table", "Message must be type Table")
    if not message.title and not message.text then
      return -- If we have nothing to send; why send it?
    end
    love.mintmousse.push({
      func = "notify",
      message,
    })
  end


  if not love.isMintMousseServerThread then
    -- Wait for component types to be parsed: this is a quick operation, but it is blocking

    local componentTypesChannel = love.thread.getChannel(love.mintmousse.READONLY_BASIC_TYPES_ID)

    local start = love.timer.getTime()
    while love.mintmousse._componentTypes == nil do
      if love.timer.getTime() - start >= 3 then -- seconds timeout
        break
      end
      love.mintmousse._componentTypes = componentTypesChannel:peek()
      love.timer.sleep(0.0001) -- 0.1ms
    end

    if love.mintmousse._componentTypes == nil then
      local was = love.mintmousse.logging.enableError
      love.mintmousse.logging.enableError = false
      love.mintmousse.error("Timeout reached while waiting for MM thread. Possible error in thread code. Attempting to manually call love.threaderror")
      love.mintmousse.logging.enableError = was
      local channel = love.thread.getChannel(love.mintmousse.READONLY_THREAD_LOCATION)
      if not channel:peek() then
        return
      end
      local thread = channel:peek()
      local errorMessage = thread:getError()
      if errorMessage then
        -- Decided we want to know as soon as possible if there was a
        --   thread error than waiting for the event loop to pump.
        -- love.event.push("threaderror", thread, errorMessage)
        love.handlers["threaderror"](thread, errorMessage)
      else
        love.mintmousse.warning("There was no error waiting on the thread object. Possible that it is trying to load too many components and timeout needs to be increased. Tell a programmer.")
      end
      return
    end
  end
end