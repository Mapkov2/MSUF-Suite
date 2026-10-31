local _, P = ...
local NS, S = P.NS, P.Suite
local Sources, Teleport = P.KeystoneSources, P.KeystoneTeleport
local IN_COMBAT = { inCombat = true }

-- rows maps a player to the listed text, entries to the answer behind it
-- (rowCount counts the answering players); layout is the window's geometry,
-- shared with the teleport buttons over the rows.
local M = { rows = {}, entries = {}, rowMaps = {}, rowCount = 0, page = 1,
    layout = { rows = 12, top = 48, step = 27, inset = 16, iconRoom = 26 } }
local Command, RefreshGroup
local COMMAND = "MSUFSUITEKEYS"
local PREFIX = "MSUFKEY1"
-- Seconds, except MAX_ANSWERS.
local REQUEST_COOLDOWN = 2   -- between two requests
local RESPONSE_COOLDOWN = 5  -- between two answers to the Suite protocol's request
local ANSWER_WINDOW = 5      -- answers over the Suite protocol count this long after a request
local SOURCE_WINDOW = 12     -- other addons' libraries answer more slowly
local GROUP_SETTLE = 3       -- the roster stays quiet this long before the list is asked again
local MAX_ANSWERS = 100

-- Precedence of equal answers: the Suite protocol, LibKeystone, LibOpenRaid.
local RANK = {}
for rank, source in ipairs(Sources.order) do RANK[source] = rank end

-- /keys stays with another keystone addon whenever one owns it
-- (SlashCommands.lua follows the client's slash hash and proxy).
local function Register()
    if S.SlashAliasFree("/keys", COMMAND, Command) then
        S.RegisterSlash(COMMAND, Command, "/msufkeys", "/keys")
    else
        S.RegisterSlash(COMMAND, Command, "/msufkeys")
    end
end

local function OwnKeystone()
    local mythic, challenge = C_MythicPlus, C_ChallengeMode
    local mapID = mythic.GetOwnedKeystoneChallengeMapID()
    local level = mythic.GetOwnedKeystoneLevel()
    if not S.Finite(mapID) or mapID < 1 or not S.Finite(level) or level < 2 then return nil end
    local name = S.PublicText(challenge.GetMapUIInfo(mapID))
    if not name then return nil end
    return string.format(S.Text("Keystone: %s +%d"), name, math.floor(level)), mapID, level
end

local function GroupChannel()
    local inParty, inRaid, inInstance = IsInGroup(), IsInRaid(), IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    if not S.Public(inParty) or not S.Public(inRaid) or not S.Public(inInstance) then return nil end
    if inInstance == true then return "INSTANCE_CHAT" end
    if inRaid == true then return "RAID" end
    if inParty == true then return "PARTY" end
end

local function GuildChannel()
    local guild = IsInGuild()
    return S.Public(guild) and guild == true and "GUILD" or nil
end

-- The window is a plain frame and scales in combat too; the teleport layer
-- follows it (MPlusKeystoneTeleport.lua).
local function ApplyScale(self, scale)
    if self.appliedScale == scale then return end
    self.appliedScale = scale
    self.host:SetScale(scale)
    Teleport.Follow(self)
end

-- "Suite 2, LibKeystone 1": the answering players by the source they answered
-- through, in the order of precedence.
local function AnswerSources(self)
    local counts, parts = {}, {}
    for _, entry in pairs(self.entries) do
        if entry.source then counts[entry.source] = (counts[entry.source] or 0) + 1 end
    end
    for _, source in ipairs(Sources.order) do
        if counts[source] then parts[#parts + 1] = source .. " " .. counts[source] end
    end
    return table.concat(parts, ", ")
end

-- Before the first request the window shows its original line.
local function StatusText(self, pages)
    if not self.requestMode then
        return string.format(S.Text("Page %d/%d · Suite users who answered this request"), self.page, pages)
    end
    if self.rowCount == 0 then
        return string.format(S.Text("Page %d/%d · No answers yet"), self.page, pages)
    end
    return string.format(S.Text("Page %d/%d · Players who answered: %d (%s)"),
        self.page, pages, self.rowCount, AnswerSources(self))
end

local function PaintWindow(self)
    if not self.host then return end
    local c = self.config or {}
    ApplyScale(self, (c.windowScale or 100) / 100)
    local size = c.fontSize or 14
    local rows = {}
    for name, key in pairs(self.rows) do rows[#rows + 1] = { name, key } end
    table.sort(rows, function(a, b) return a[1] < b[1] end)
    local perPage = self.layout.rows
    local pages = math.max(1, math.ceil(#rows / perPage))
    self.page = math.min(self.page or 1, pages)
    for i = 1, perPage do
        local row = rows[(self.page - 1) * perPage + i]
        local label = self.labels[i]
        S.SetStyledFont(label, S.GlobalFontPath(), size, "OUTLINE", 1, true, 70, 1)
        label:SetText(row and (row[1] .. "  ·  " .. row[2]) or "")
        local entry = row and self.entries[row[1]]
        self.rowMaps[i] = entry and entry.mapID or nil
    end
    self.status:SetText(StatusText(self, pages))
    -- Combat locks the teleport buttons; PLAYER_REGEN_ENABLED paints again (AfterCombat).
    Teleport.Paint(self, self.rowMaps)
end

-- The end of combat paints a shown window again and lets the teleport layer
-- catch up with a window that moved, scaled, opened or closed in combat.
local function AfterCombat(self)
    if self.host:IsShown() then
        PaintWindow(self)
    else
        self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    end
    Teleport.CombatEnded(self)
end

local function CreateWindow(self)
    local host = S.CreateFrame("Frame", "MSUFSuiteKeystones", UIParent)
    host:SetSize(480, 414)
    host:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    host:SetFrameStrata("DIALOG")
    host:SetClampedToScreen(true)
    host:SetMovable(true)
    host:EnableMouse(true)
    host:RegisterForDrag("LeftButton")
    -- The teleport layer follows the window outside combat (MPlusKeystoneTeleport.lua).
    host:SetScript("OnDragStart", function()
        host:StartMoving()
        Teleport.Follow(self, true)
    end)
    host:SetScript("OnDragStop", function()
        host:StopMovingOrSizing()
        Teleport.Follow(self)
    end)
    host:SetScript("OnShow", function() Teleport.Follow(self) end)
    -- The window listens to the roster and to the end of combat only while it
    -- is shown; after a close in combat the end of combat still hides the
    -- teleport layer (AfterCombat).
    host:SetScript("OnHide", function()
        self.context:RemoveEvent("GROUP_ROSTER_UPDATE")
        if not Teleport.Follow(self) then self.context:RemoveEvent("PLAYER_REGEN_ENABLED") end
    end)
    local back = S.CreateTexture(host, nil, "BACKGROUND")
    back:SetAllPoints(host)
    back:SetColorTexture(.04, .05, .07, .97)
    self.host, self.labels = host, {}
    local function Button(label, x, action)
        local button = S.CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
        button:SetSize(83, 24)
        button:SetPoint("TOPLEFT", x, -12)
        button:SetText(S.Text(label))
        button:SetScript("OnClick", action)
    end
    Button("Party keys", 12, function() Command("group") end)
    Button("Guild keys", 104, function() Command("guild") end)
    Button("Previous", 196, function()
        self.page = math.max(1, self.page - 1)
        PaintWindow(self)
    end)
    Button("Next", 288, function()
        self.page = self.page + 1
        PaintWindow(self)
    end)
    Button("Close", 380, function() host:Hide() end)
    local layout = self.layout
    for i = 1, layout.rows do
        local y = -layout.top - (i - 1) * layout.step
        local label = S.CreateFontString(host, nil, "OVERLAY")
        label:SetPoint("TOPLEFT", layout.inset, y)
        label:SetPoint("TOPRIGHT", -layout.inset - layout.iconRoom, y)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        self.labels[i] = label
    end
    self.status = S.CreateFontString(host, nil, "OVERLAY")
    self.status:SetPoint("BOTTOMLEFT", 16, 15)
    S.SetStyledFont(self.status, S.GlobalFontPath(), 11, "OUTLINE", 1, true, 70, 1)
    -- Escape closes the window like Blizzard's own panels.
    table.insert(UISpecialFrames, "MSUFSuiteKeystones")
end

local function ShowWindow(self)
    if not self.host then CreateWindow(self) end
    Teleport.Reset(self)
    self.context:Event("PLAYER_REGEN_ENABLED", AfterCombat, IN_COMBAT)
    PaintWindow(self)
    self.host:Show()
end

local function AddOwn(self)
    local text, mapID, level = OwnKeystone()
    local you = S.Text("You")
    self.rows[you] = text or S.Text("No owned keystone found")
    self.entries[you] = mapID and { mapID = mapID, level = level } or nil
end

-- The "Name-Realm" of a sender (a bare name is a player of the own realm), or
-- nil for an unreadable sender and for the player itself.
local function PeerName(sender)
    if not S.PublicText(sender) then return nil end
    local ownName, ownRealm = UnitFullName("player")
    local realm = S.PublicText(ownRealm)
    if realm and not sender:find("-", 1, true) then sender = sender .. "-" .. realm end
    if S.PublicText(ownName) and (sender == ownName or (realm and sender == ownName .. "-" .. realm)) then
        return nil
    end
    return sender
end

local function ValidKey(mapID, level)
    return S.Finite(mapID) and mapID >= 1 and mapID <= 100000 and mapID == math.floor(mapID)
        and S.Finite(level) and level >= 2 and level <= 99 and level == math.floor(level)
end

-- A newer answer replaces an older one, and so does an equal moment's answer
-- of a source with precedence; the same key from a source with precedence
-- only changes the source credited with it.
local function Supersedes(old, mapID, level, rank, now)
    if old.mapID == mapID and old.level == level then return rank < old.rank end
    return now > old.at or now == old.at and rank < old.rank
end

-- The one way in of every source: one entry per player (peer is a PeerName).
-- Says in chat when a key is new or changed, if the request asked for that.
local function Take(self, peer, mapID, level, source, now)
    local dungeon
    if peer and ValidKey(mapID, level) then dungeon = S.PublicText(C_ChallengeMode.GetMapUIInfo(mapID)) end
    if not dungeon then return end
    local old, rank = self.entries[peer], RANK[source]
    if old then
        if not Supersedes(old, mapID, level, rank, now) then return end
    elseif self.rowCount >= MAX_ANSWERS then
        return
    else
        self.rowCount = self.rowCount + 1
    end
    local changed = not old or old.mapID ~= mapID or old.level ~= level
    self.entries[peer] = { mapID = mapID, level = level, source = source, rank = rank, at = now }
    self.rows[peer] = dungeon .. " +" .. level
    PaintWindow(self)
    if changed and self.announce then S.Print(string.format(S.Text("%s: %s +%d"), peer, dungeon, level)) end
end

local function OnAddonMessage(self, _, prefix, payload, channel, sender)
    if not self.active or not S.PublicText(prefix) or prefix ~= PREFIX
        or not S.PublicText(payload) or not S.PublicText(channel)
        or not S.PublicText(sender) then return end
    if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" and channel ~= "GUILD" then return end
    local peer = PeerName(sender)
    if not peer then return end
    local current
    if channel == "GUILD" then current = GuildChannel() else current = GroupChannel() end
    if not current or channel ~= current then return end
    local now = GetTime()
    if not S.Finite(now) then return end
    if payload == "Q" then
        if self.lastResponseAt and now - self.lastResponseAt < RESPONSE_COOLDOWN then return end
        local _, mapID, level = OwnKeystone()
        if not mapID then return end
        self.lastResponseAt = now
        C_ChatInfo.SendAddonMessage(PREFIX, string.format("K:%d:%d", mapID, math.floor(level)), channel)
        return
    end
    if not self.requestExpiresAt or now > self.requestExpiresAt or channel ~= self.requestChannel then return end
    local mapText, levelText = payload:match("^K:(%d+):(%d+)$")
    Take(self, peer, tonumber(mapText), tonumber(levelText), Sources.SUITE, now)
end

-- The libraries of other addons answer a request through P.KeystoneSources.
-- scope says whether an answer belongs to a group or to a guild request.
local function OnSourceAnswer(source, name, mapID, level, scope)
    local now = GetTime()
    if not M.active or not S.Finite(now) or not M.sourcesExpireAt or now > M.sourcesExpireAt
        or scope ~= M.requestMode then return end
    Take(M, PeerName(name), mapID, level, source, now)
end

-- A roster change asks again after it settled; the cooldown of RequestKeys
-- still holds.
local function OnRosterChanged(self)
    self.context:After(GROUP_SETTLE, RefreshGroup)
end

-- mode is "group" or "guild". quiet is a request of the window itself after
-- a roster change: it leaves the chat alone.
local function RequestKeys(mode, quiet)
    local channel
    if mode == "guild" then channel = GuildChannel() else channel = GroupChannel() end
    if not channel then
        if quiet then return end
        if mode == "guild" then
            S.Print(S.Text("Join a guild to request Suite keystones"))
        else
            S.Print(S.Text("Join a group to request Suite keystones"))
        end
        return
    end
    local now = GetTime()
    if not S.Finite(now) or (M.lastRequestAt and now - M.lastRequestAt < REQUEST_COOLDOWN) then return end
    M.lastRequestAt, M.requestExpiresAt, M.sourcesExpireAt = now, now + ANSWER_WINDOW, nil
    M.requestChannel, M.requestMode, M.announce = channel, mode, not quiet
    M.rows, M.entries, M.rowCount, M.page = {}, {}, 0, 1
    if mode == "group" then
        M.context:Event("GROUP_ROSTER_UPDATE", OnRosterChanged, IN_COMBAT)
    else
        M.context:RemoveEvent("GROUP_ROSTER_UPDATE")
    end
    AddOwn(M)
    ShowWindow(M)
    local own = OwnKeystone()
    if own and not quiet then S.Print(own) end
    -- Addon messages report a lockdown or throttle as a result; nothing raises.
    local sent = C_ChatInfo.SendAddonMessage(PREFIX, "Q", channel)
    if not S.Public(sent) or sent ~= Enum.SendAddonMessageResult.Success then
        M.requestExpiresAt = nil
        if not quiet then
            S.Print(S.Text("Keystone requests cannot be sent right now; the window lists only your own key."))
        end
        return
    end
    if M.config and M.config.otherAddons == false then return end
    if Sources.Request(mode, OnSourceAnswer) > 0 then M.sourcesExpireAt = now + SOURCE_WINDOW end
end

RefreshGroup = function(self)
    if self.requestMode == "group" and self.host and self.host:IsShown() then RequestKeys("group", true) end
end

Command = function(message)
    if not M.active then return end
    if not S.Public(message) or type(message) ~= "string" then return end
    local mode = message:lower():match("^%s*(.-)%s*$")
    if mode == "group" or mode == "guild" then
        RequestKeys(mode)
        return
    end
    if mode == "" or mode == "window" then
        AddOwn(M)
        ShowWindow(M)
    end
    local text = OwnKeystone()
    if not text then
        S.Print(S.Text("No owned keystone found"))
        return
    end
    if mode == "" or mode == "window" or mode == "self" then
        S.Print(text)
        return
    end
    local channel
    local inParty, inRaid, inInstance = IsInGroup(), IsInRaid(), IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    if mode == "party" and S.Public(inParty) and inParty == true then
        channel = "PARTY"
    elseif mode == "raid" and S.Public(inRaid) and inRaid == true then
        channel = "RAID"
    elseif mode == "instance" and S.Public(inInstance) and inInstance == true then
        channel = "INSTANCE_CHAT"
    end
    if not channel then
        S.Print(S.Text("Usage: /keys [self||party||raid||instance||group||guild]"))
        return
    end
    -- Chat lockdown also applies inside dungeons and raids; a blocked
    -- SendChatMessage cannot be caught, so the key stays local then.
    if NS.ChatLocked() then
        S.Print(text)
        S.Print(S.Text("Chat messages are blocked here right now; only you see your keystone."))
        return
    end
    C_ChatInfo.SendChatMessage(text, channel)
end

local function InsertKey(self)
    if not self.active or not self.config or not self.config.insertKey or NS.IsCombatLocked() then return end
    local cursor, shift, slotted = CursorHasItem(), IsShiftKeyDown(), C_ChallengeMode.HasSlottedKeystone()
    if not S.Public(cursor) or cursor or not S.Public(shift) or shift or not S.Public(slotted) or slotted then return end
    for bag = 0, 5 do
        local count = C_Container.GetContainerNumSlots(bag)
        if S.Finite(count) and count >= 0 and count <= 200 then
            for slot = 1, count do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if S.Public(info) and type(info) == "table" and S.PublicText(info.hyperlink)
                    and info.hyperlink:find("|Hkeystone:", 1, true) and S.Public(info.isLocked) and info.isLocked == false
                    and S.Finite(info.itemID) then
                    -- Neither call is restricted; the checks above rule out the
                    -- states in which they would do nothing (combat, a held item).
                    C_Container.PickupContainerItem(bag, slot)
                    local kind, itemID = GetCursorInfo()
                    if not S.PublicText(kind) or kind ~= "item" or not S.Finite(itemID) or itemID ~= info.itemID then return end
                    if not S.QoLRestrictedCall(C_ChallengeMode.SlotKeystone) then
                        S.Print(S.Text("Keystone insertion was blocked by the client."))
                    end
                    -- Restore only the exact cursor item we picked up; never clear a foreign cursor.
                    kind, itemID = GetCursorInfo()
                    if S.PublicText(kind) == "item" and S.Finite(itemID) and itemID == info.itemID then
                        ClearCursor()
                    end
                    return
                end
            end
        end
    end
end

local function HookKeystone(self)
    local frame = _G.ChallengesKeystoneFrame
    if self.keystoneHooked then
        self.context:RemoveEvent("ADDON_LOADED")
        return
    end
    if not frame then return end
    frame:HookScript("OnShow", function() InsertKey(self) end)
    self.keystoneHooked = true
    self.context:RemoveEvent("ADDON_LOADED")
end

function M:Enable()
    self.context:Event("ADDON_LOADED", HookKeystone)
    HookKeystone(self)
    Register()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    self.context:Event("CHAT_MSG_ADDON", OnAddonMessage, IN_COMBAT)
end

function M:Refresh()
    PaintWindow(self)
    Register()
end

function M:Disable()
    -- Hiding the window drops its roster and combat events.
    if self.host then self.host:Hide() end
    self.rows, self.entries, self.rowCount, self.requestChannel, self.requestMode = {}, {}, 0, nil, nil
    self.context:RemoveEvent("CHAT_MSG_ADDON")
    self.context:RemoveEvent("ADDON_LOADED")
    self.requestExpiresAt, self.sourcesExpireAt, self.lastResponseAt, self.lastRequestAt = nil, nil, nil, nil
    Sources.Detach()
    S.UnregisterSlash(COMMAND, Command)
end

S.Install("mythicKeyShare", M)
