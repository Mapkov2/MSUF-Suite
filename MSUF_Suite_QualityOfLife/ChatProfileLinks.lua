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

local function RealmSlug(realm)
    -- Blizzard may provide "Tarren Mill" or its normalized "TarrenMill".
    realm = realm:gsub("(%l)(%u)", "%1-%2")
        :gsub("(%a)(%d)", "%1-%2")
        :gsub("[%s_]+", "-")
        :gsub("['’]", "")
        :lower()
    return Encode(realm)
end

local function Character(contextData)
    if not S.Public(contextData) or type(contextData) ~= "table" then return end
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

local function Label(parent, text, size)
    local label = S.CreateFontString(parent, nil, "ARTWORK")
    S.SetFont(label, nil, size, "")
    label:SetText(S.Text(text))
    return label
end

local function CreateDialog()
    local panel = S.CreateFrame("Frame", nil, UIParent)
    panel:SetSize(500, 108)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    local background = S.CreateTexture(panel, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.065, .075, .085, .97)
    local stripe = S.CreateTexture(panel, nil, "BORDER")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("TOPRIGHT")
    stripe:SetHeight(2)
    stripe:SetColorTexture(.8, .68, .42, 1)
    local title = Label(panel, "Copy profile URL", 14)
    title:SetPoint("TOPLEFT", 14, -11)
    local drag = S.CreateFrame("Button", nil, panel)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", -33, 0)
    drag:SetHeight(37)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    local close = S.CreateFrame("Button", nil, panel)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -7, -7)
    local cross = Label(close, "X", 13)
    cross:SetPoint("CENTER")
    close:SetScript("OnClick", function() panel:Hide() end)
    local edit = S.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    edit:SetSize(447, 25)
    edit:SetPoint("TOP", 0, -45)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() panel:Hide() end)
    panel.edit = edit
    local hint = Label(panel, "Press Ctrl+C to copy the URL", 11)
    hint:SetPoint("BOTTOM", 0, 9)
    panel:Hide()
    return panel
end

local function Copy(service, contextData)
    if not M.active or not M.config[service] then return end
    local url = URL(service, contextData)
    if not url then return end
    local panel = M.dialog or CreateDialog()
    M.dialog = panel
    panel.edit:SetText(url)
    panel:Show()
    panel.edit:SetFocus()
    panel.edit:HighlightText()
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

local function Install()
    if M.hooked then return true end
    if not _G.Menu or type(Menu.ModifyMenu) ~= "function" then return false end
    for i = 1, #MENU_TAGS do Menu.ModifyMenu(MENU_TAGS[i], Populate) end
    M.hooked = true
    return true
end

local function OnAddon()
    if Install() then M.context:RemoveEvent("ADDON_LOADED") end
end

function M:Enable()
    if not Install() then self.context:Event("ADDON_LOADED", OnAddon) end
end

function M:Refresh() end

function M:Disable()
    if self.dialog then
        self.dialog:Hide()
        self.dialog.edit:ClearFocus()
        self.dialog.edit:SetText("")
    end
end

S.Install("chatProfileLinks", M)
