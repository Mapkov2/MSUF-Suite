local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }

local M = { rows = {}, page = 1 }
local Command
local COMMAND = "MSUFSUITEKEYS"
local PREFIX = "MSUFKEY1"

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

local function PaintWindow(self)
    if not self.host then return end
    local c = self.config or {}
    self.host:SetScale((c.windowScale or 100) / 100)
    local size = c.fontSize or 14
    local rows = {}
    for name, key in pairs(self.rows) do rows[#rows + 1] = { name, key } end
    table.sort(rows, function(a, b) return a[1] < b[1] end)
    local pages = math.max(1, math.ceil(#rows / 12))
    self.page = math.min(self.page or 1, pages)
    for i = 1, 12 do
        local row = rows[(self.page - 1) * 12 + i]
        local label = self.labels[i]
        S.SetStyledFont(label, S.GlobalFontPath(), size, "OUTLINE", 1, true, 70, 1)
        label:SetText(row and (row[1] .. "  ·  " .. row[2]) or "")
    end
    self.status:SetText(string.format(S.Text("Page %d/%d · Suite users who answered this request"), self.page, pages))
end

local function ShowWindow(self)
    if not self.host then
        local host = S.CreateFrame("Frame", "MSUFSuiteKeystones", UIParent)
        host:SetSize(480, 414)
        host:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        host:SetFrameStrata("DIALOG")
        host:SetClampedToScreen(true)
        host:SetMovable(true)
        host:EnableMouse(true)
        host:RegisterForDrag("LeftButton")
        host:SetScript("OnDragStart", function() host:StartMoving() end)
        host:SetScript("OnDragStop", function() host:StopMovingOrSizing() end)
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
        for i = 1, 12 do
            local label = S.CreateFontString(host, nil, "OVERLAY")
            label:SetPoint("TOPLEFT", 16, -48 - (i - 1) * 27)
            label:SetPoint("TOPRIGHT", -16, -48 - (i - 1) * 27)
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
    PaintWindow(self)
    self.host:Show()
end

local function AddOwn(self)
    local text = OwnKeystone()
    self.rows[S.Text("You")] = text or S.Text("No owned keystone found")
end

local function OnAddonMessage(self, _, prefix, payload, channel, sender)
    if not self.active or not S.PublicText(prefix) or prefix ~= PREFIX
        or not S.PublicText(payload) or not S.PublicText(channel)
        or not S.PublicText(sender) then return end
    if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" and channel ~= "GUILD" then return end
    local ownName, ownRealm = UnitFullName("player")
    if S.PublicText(ownName) and (sender == ownName
        or (S.PublicText(ownRealm) and sender == ownName .. "-" .. ownRealm)) then return end
    local current = channel == "GUILD" and GuildChannel() or GroupChannel()
    if not current or channel ~= current then return end
    local now = GetTime()
    if not S.Finite(now) then return end
    if payload == "Q" then
        if self.lastResponseAt and now - self.lastResponseAt < 5 then return end
        local _, mapID, level = OwnKeystone()
        if not mapID then return end
        self.lastResponseAt = now
        C_ChatInfo.SendAddonMessage(PREFIX, string.format("K:%d:%d", mapID, math.floor(level)), channel)
        return
    end
    if not self.requestExpiresAt or now > self.requestExpiresAt or channel ~= self.requestChannel then return end
    local mapText, levelText = payload:match("^K:(%d+):(%d+)$")
    local mapID, level = tonumber(mapText), tonumber(levelText)
    if not S.Finite(mapID) or mapID < 1 or mapID > 100000
        or not S.Finite(level) or level < 2 or level > 99
        or self.seen[sender] then return end
    local name = S.PublicText(C_ChallengeMode.GetMapUIInfo(mapID))
    if not name then return end
    if (self.rowCount or 0) >= 100 then return end
    self.seen[sender] = true
    self.rowCount = (self.rowCount or 0) + 1
    self.rows[sender] = name .. " +" .. level
    PaintWindow(self)
    S.Print(string.format(S.Text("%s: %s +%d"), sender, name, level))
end

Command = function(message)
    if not M.active then return end
    if not S.Public(message) or type(message) ~= "string" then return end
    local mode = message:lower():match("^%s*(.-)%s*$")
    if mode == "group" or mode == "guild" then
        local channel = mode == "guild" and GuildChannel() or GroupChannel()
        if not channel then
            S.Print(S.Text("Join a group to request Suite keystones"))
            return
        end
        local now = GetTime()
        if not S.Finite(now) or (M.lastRequestAt and now - M.lastRequestAt < 2) then return end
        M.lastRequestAt, M.requestExpiresAt, M.seen = now, now + 5, {}
        M.requestChannel, M.rows, M.rowCount, M.page = channel, {}, 0, 1
        AddOwn(M)
        ShowWindow(M)
        local own = OwnKeystone()
        if own then S.Print(own) end
        -- Addon messages report a lockdown or throttle as a result; nothing raises.
        local sent = C_ChatInfo.SendAddonMessage(PREFIX, "Q", channel)
        if not S.Public(sent) or sent ~= Enum.SendAddonMessageResult.Success then
            M.requestExpiresAt = nil
            S.Print(S.Text("Keystone requests cannot be sent right now; the window lists only your own key."))
        end
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
    if mode == "party" and S.Public(inParty) and inParty == true then channel = "PARTY"
    elseif mode == "raid" and S.Public(inRaid) and inRaid == true then channel = "RAID"
    elseif mode == "instance" and S.Public(inInstance) and inInstance == true then channel = "INSTANCE_CHAT" end
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
    if self.host then self.host:Hide() end
    self.rows, self.requestChannel = {}, nil
    self.context:RemoveEvent("CHAT_MSG_ADDON")
    self.context:RemoveEvent("ADDON_LOADED")
    self.requestExpiresAt, self.seen, self.lastResponseAt, self.lastRequestAt = nil, nil, nil, nil
    S.UnregisterSlash(COMMAND, Command)
end

S.Install("mythicKeyShare", M)
