return {
  validateUsername = function(username)
    -- Verifies that the username conforms to the length required
    if #username < 3 or #username > 24 then
      return false
    end

    -- Verifies that the username contains only alphanumeric characters, underscores, or hyphens.
    if not string.match(username, "^[a-zA-Z0-9_-]+$") then
      return false
    end

    -- Verifies that the username doesn't contain reserved keywords
    local reservedKeywords = { "server", "admin", "moderator" }
    for _, keyword in ipairs(reservedKeywords) do
      if username:find(keyword, 1, true) then
        return false
      end
    end

    return true
  end,

  compressionFunction = "lz4", -- https://love2d.org/wiki/CompressedDataFormat
  hashFunction = "sha512", -- https://love2d.org/wiki/HashFunction
  uidLength = 64,
  saltLength = 64,
}