local _, P = ...
local S = P.Suite

-- Blizzard's tagged UnitPopup context menu supplies the character identity.
-- We only construct a URL after the player clicks one of the added entries;
-- neither the chat message nor whisper sender is read or cached.
local M = {}
local MENU_TAGS = {
    "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_GUILD", "MENU_UNIT_FRIEND", "MENU_UNIT_CHAT_ROSTER",
    "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_ENEMY_PLAYER",
}

local function Encode(segment)
    return (segment:gsub("[^%w%-%._~]", function(char)
        return string.format("%%%02X", char:byte())
    end))
end

-- The typographic apostrophe is three UTF-8 bytes; it is removed as a whole
-- sequence, never byte by byte (a class would cut other characters too).
local TYPOGRAPHIC_APOSTROPHE = "\226\128\153"

local function RealmSlug(realm)
    -- Blizzard may provide "Tarren Mill" or its normalized "TarrenMill". The
    -- player's own realm has its display name, spaces included; for another
    -- normalized realm, word breaks are guessed from capitals and digits.
    if not realm:find(" ", 1, true) then
        local own = S.PublicText(GetNormalizedRealmName())
        if own == realm then realm = S.PublicText(GetRealmName()) or realm end
    end
    if not realm:find(" ", 1, true) then
        realm = realm:gsub("(%l)(%u)", "%1-%2"):gsub("(%a)(%d)", "%1-%2")
    end
    realm = realm:gsub("[%s_]+", "-")
        :gsub("'", "")
        :gsub(TYPOGRAPHIC_APOSTROPHE, "")
        :lower()
    return Encode(realm)
end

-- TARGET is also the menu of a non-player target and FOCUS covers every
-- focus unit: a menu about a unit offers profiles only for a player, by a
-- public answer. Chat, guild and friend menus name no unit.
local function NotAPlayer(unit)
    if unit == nil then return false end
    if not S.Public(unit) then return true end
    local player = UnitIsPlayer(unit)
    return not S.Public(player) or player ~= true
end

local function Character(contextData)
    if not S.Public(contextData) or type(contextData) ~= "table" or NotAPlayer(contextData.unit) then return end
    local name = S.PublicText(contextData.name)
    local realm = S.PublicText(contextData.server)
    if not name then return end
    local splitName, splitRealm = name:match("^([^-]+)%-(.+)$")
    if splitName and splitRealm then name, realm = splitName, splitRealm end
    if not realm then realm = S.PublicText(GetRealmName()) end
    local region = S.PublicText(GetCurrentRegionName())
    if not realm or not region or not region:match("^[A-Z][A-Z]$")
        or name:find("[%c/\\]") or realm:find("[%c/\\]") then return end
    return region:lower(), RealmSlug(realm), Encode(name)
end

local function URL(service, contextData)
    local region, realm, name = Character(contextData)
    if not region then return end
    if service == "raiderIO" then
        return "https://raider.io/characters/" .. region .. "/" .. realm .. "/" .. name
    end
    return "https://www.warcraftlogs.com/character/" .. region .. "/" .. realm .. "/" .. name
end

local function Copy(service, contextData)
    if not M.active or not M.config[service] then return end
    local url = URL(service, contextData)
    if not url then return end
    M.dialog = M.dialog or S.QoLCopyDialog("Copy profile URL", "Press Ctrl+C to copy the URL", 500)
    S.QoLShowCopy(M.dialog, url)
end

local function Populate(_, rootDescription, contextData)
    if not M.active or not (M.config.raiderIO or M.config.warcraftLogs)
        or not Character(contextData) then return end
    rootDescription:CreateDivider()
    rootDescription:CreateTitle(S.Text("Character profiles"))
    if M.config.raiderIO then
        rootDescription:CreateButton(S.Text("Copy Raider.IO URL"), function()
            Copy("raiderIO", contextData)
        end)
    end
    if M.config.warcraftLogs then
        rootDescription:CreateButton(S.Text("Copy Warcraft Logs URL"), function()
            Copy("warcraftLogs", contextData)
        end)
    end
end

-- Blizzard_Menu loads first (LoadFirst); its tags exist before any addon.
-- Menu modifications cannot be removed, so they act only while active.
function M:Enable()
    if self.hooked then return end
    for i = 1, #MENU_TAGS do Menu.ModifyMenu(MENU_TAGS[i], Populate) end
    self.hooked = true
end

function M:Refresh() end

function M:Disable()
    if self.dialog then S.QoLClearCopy(self.dialog) end
end

S.Install("chatProfileLinks", M)
