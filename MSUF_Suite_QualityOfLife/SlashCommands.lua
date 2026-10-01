local _, P = ...
local S = P.Suite

-- Slash commands as the client resolves them (Blizzard_ChatFrameBase/Shared/
-- ChatFrameUtil.lua, ImportListToHash). Before it parses chat input, the
-- client imports every SlashCmdList entry: each SLASH_<KEY><n> alias, upper
-- case, gets the handler in hash_SlashCmdList, the handler moves into the
-- proxy table behind SlashCmdList's metatable and the list is wiped. A typed
-- command runs whatever hash_SlashCmdList holds. An alias therefore belongs
-- to another addon while its hash entry runs another handler or another
-- command lists it, whether that command waits in the list or sits in the
-- proxy. Handlers must stay the same function between Register and
-- Unregister: ownership is decided by identity.

local function Proxy()
    return getmetatable(SlashCmdList).__index
end

-- The key of another command in list whose aliases include alias.
local function ClaimedIn(list, alias, ownKey)
    for key in pairs(list) do
        if key ~= ownKey and type(key) == "string" then
            local index = 1
            local value = _G["SLASH_" .. key .. index]
            while value do
                if type(value) == "string" and value:upper() == alias then return key end
                index = index + 1
                value = _G["SLASH_" .. key .. index]
            end
        end
    end
end

local function OtherOwner(alias, ownKey)
    return ClaimedIn(SlashCmdList, alias, ownKey) or ClaimedIn(Proxy(), alias, ownKey)
end

-- True while no other command owns alias (for example "/way").
function S.SlashAliasFree(alias, ownKey, handler)
    alias = alias:upper()
    local typed = hash_SlashCmdList[alias]
    if typed ~= nil and typed ~= handler then return false end
    return OtherOwner(alias, ownKey) == nil
end

-- True when another handler took alias in the hash or a command added since
-- the client's last import (still in SlashCmdList itself) lists it: all an
-- addon that just loaded can have claimed. The imported commands in the
-- proxy are not read again.
function S.SlashAliasNewlyClaimed(alias, ownKey, handler)
    alias = alias:upper()
    local typed = hash_SlashCmdList[alias]
    if typed ~= nil and typed ~= handler then return true end
    return ClaimedIn(SlashCmdList, alias, ownKey) ~= nil
end

-- Clears this command's SLASH_ aliases. A hash entry that still runs handler
-- goes back to another command listing the alias, as the client's import
-- would have left it, or away.
local function Release(key, handler)
    local proxy = Proxy()
    local index = 1
    local value = _G["SLASH_" .. key .. index]
    while value do
        if type(value) == "string" then
            local alias = value:upper()
            if hash_SlashCmdList[alias] == handler then
                local other = OtherOwner(alias, key)
                hash_SlashCmdList[alias] = other and (rawget(SlashCmdList, other) or proxy[other]) or nil
            end
        end
        _G["SLASH_" .. key .. index] = nil
        index = index + 1
        value = _G["SLASH_" .. key .. index]
    end
end

-- Registers handler under key for the given aliases. A previous registration
-- of the key is released first, so an alias left out of the list stops
-- running it; the client imports the new aliases before the next command.
function S.RegisterSlash(key, handler, ...)
    Release(key, handler)
    for index = 1, select("#", ...) do
        _G["SLASH_" .. key .. index] = (select(index, ...))
    end
    SlashCmdList[key] = handler
end

-- Removes the command wherever handler still owns it. An alias another
-- addon took over keeps that addon's handler.
function S.UnregisterSlash(key, handler)
    Release(key, handler)
    if rawget(SlashCmdList, key) == handler then SlashCmdList[key] = nil end
    local proxy = Proxy()
    if proxy[key] == handler then proxy[key] = nil end
end
