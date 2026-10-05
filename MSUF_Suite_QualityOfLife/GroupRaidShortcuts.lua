local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local COMMANDS = { raid = "MSUFSUITERAID", pull = "MSUFSUITEPULL", mark = "MSUFSUITEMARK" }
local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local AUTO_ROLES = { { "autoMarkTank", "TANK", "tankMarker" },
    { "autoMarkHealer", "HEALER", "healerMarker" } }

local function Permitted()
    local grouped, leader, assistant = IsInGroup(), UnitIsGroupLeader("player"), UnitIsGroupAssistant("player")
    return S.Public(grouped) and grouped == true and S.Public(leader) and S.Public(assistant)
        and (leader == true or assistant == true)
end

-- The chat frame caches slash handlers, so a command typed after the module
-- was switched off still reaches its old handler: answer instead of nothing.
local function Available()
    if M.active then return true end
    S.Print(S.Text("Raid shortcuts are switched off in the MSUF Suite options."))
    return false
end

-- Countdowns, raid markers and ready checks are restricted actions; a
-- blocked call cannot be caught, so the shortcut refuses it beforehand.
local function Allowed()
    if not NS.GroupActionsRestricted() then return true end
    S.Print(NS.RestrictedNotice())
    return false
end

local function OpenRaidManager()
    if not Available() then return end
    local frame = _G.CompactRaidFrameManager
    local visible = frame and frame:IsShown()
    if not S.Public(visible) or visible ~= true then
        S.Print(S.Text("Enable Blizzard's Raid Manager in MSUF group settings"))
        return
    end
    -- Blizzard's own expand moves the manager; keep that out of combat.
    if NS.IsCombatLocked() then
        S.Print(NS.RestrictedNotice())
        return
    end
    if not S.Dispatch(NS.Finish, CompactRaidFrameManager_Expand) then
        S.Print(S.Text("Raid Manager could not be opened by the client."))
    end
end

local function StartPull(message)
    if not Available() or not S.Public(message) or type(message) ~= "string" then return end
    if not Permitted() then
        S.Print(S.Text("Group leader or assistant required"))
        return
    end
    local seconds = message:match("^%s*(%d*)%s*$")
    seconds = seconds == "" and 10 or tonumber(seconds)
    if not S.Finite(seconds) or seconds < 1 or seconds > 60 then
        S.Print(S.Text("Usage: /msufpull [1-60]"))
        return
    end
    if not Allowed() then return end
    local started = C_PartyInfo.DoCountdown(seconds)
    if not S.Public(started) or started ~= true then
        S.Print(S.Text("Countdown could not be started"))
    end
end

local function UniqueRole(role)
    local found
    for i = 1, #PARTY_UNITS do
        local unit = PARTY_UNITS[i]
        local exists = UnitExists(unit)
        if not S.Public(exists) then return nil end
        if exists == true then
            local assigned = S.PublicText(UnitGroupRolesAssigned(unit))
            if not assigned then return nil end
            if assigned == role then
                if found then return nil end
                found = unit
            end
        end
    end
    return found
end

-- GetRaidTargetIndex is secret on Retail (RaidMarkersDocumentation), so the
-- markers this module set are the only ones it can tell apart: marker -> GUID
-- and the role it was set for.
local ownMarks, ownRoles = {}, {}
local function Remember(unit, marker, role)
    local guid = S.PublicText(UnitGUID(unit))
    if not guid then return end
    for held, owner in pairs(ownMarks) do
        if owner == guid then ownMarks[held], ownRoles[held] = nil, nil end
    end
    ownMarks[marker], ownRoles[marker] = guid, role
end

local function MarkRole(message)
    if not Available() or not S.Public(message) or type(message) ~= "string" then return end
    local role = message:lower():match("^%s*(%a+)%s*$")
    if role ~= "tank" and role ~= "healer" then
        S.Print(S.Text("Usage: /msufmark tank or /msufmark healer"))
        return
    end
    local raid = IsInRaid()
    if not S.Public(raid) or raid == true or not Permitted() then
        S.Print(S.Text("Party leader or assistant required"))
        return
    end
    local unit = UniqueRole(role == "tank" and "TANK" or "HEALER")
    if not unit then
        S.Print(S.Text("Exactly one party member with that role is required"))
        return
    end
    local marker = role == "tank" and M.config.tankMarker or M.config.healerMarker
    if not S.Finite(marker) or marker < 1 or marker > 8 then return end
    -- A secret index is set anyway: in a group the same marker set again stays.
    local existing = GetRaidTargetIndex(unit)
    if (S.Public(existing) and existing == marker) or not Allowed() then return end
    -- A refusal the restriction check could not foresee comes back as
    -- ADDON_ACTION_BLOCKED during the call (S.QoLRestrictedCall).
    if not S.QoLRestrictedCall(SetRaidTarget, unit, marker) then
        S.Print(S.Text("Raid marker could not be set by the client."))
    else
        Remember(unit, marker, role:upper())
    end
end

local function MarkerFree(marker, wantedUnit)
    for i = 1, #PARTY_UNITS do
        local unit = PARTY_UNITS[i]
        local exists = UnitExists(unit)
        if not S.Public(exists) then return false end
        if exists == true then
            local current = GetRaidTargetIndex(unit)
            if not S.Public(current) then
                -- Unreadable: taken only when this module put this marker on
                -- this member for the role it still holds. Anyone may have
                -- changed a former role holder's marker since.
                local owner = ownMarks[marker]
                if owner and unit ~= wantedUnit and owner == S.PublicText(UnitGUID(unit))
                    and ownRoles[marker] == S.PublicText(UnitGroupRolesAssigned(unit)) then return false end
            elseif current == marker and unit ~= wantedUnit then
                return false
            end
        end
    end
    return true
end

-- Automation stays silent while restrictions apply (for example a running
-- keystone) and tries again on the next roster, role or combat-end event.
local function AutoMark(self)
    if not self.active or self.autoBlocked then return end
    -- Raid roster storms stop at the cheap raid and permission checks.
    local raid = IsInRaid()
    if not S.Public(raid) or raid == true or not Permitted() or NS.GroupActionsRestricted() then return end
    self.autoAttempts = self.autoAttempts or {}
    for _, spec in ipairs(AUTO_ROLES) do
        if self.config[spec[1]] then
            local unit = UniqueRole(spec[2])
            local marker = self.config[spec[3]]
            if unit and S.Finite(marker) and marker >= 1 and marker <= 8 then
                local existing, guid = GetRaidTargetIndex(unit), UnitGUID(unit)
                if S.Public(existing) and S.PublicText(guid) and (not existing or existing == 0)
                    and MarkerFree(marker, unit) then
                    local key = guid .. ":" .. marker
                    if not self.autoAttempts[key] then
                        if (self.autoAttemptCount or 0) >= 128 then
                            self.autoAttempts, self.autoAttemptCount = {}, 0
                        end
                        self.autoAttempts[key] = true
                        self.autoAttemptCount = (self.autoAttemptCount or 0) + 1
                        -- A refused marker stops automation until the settings change.
                        if not S.QoLRestrictedCall(SetRaidTarget, unit, marker) then
                            self.autoBlocked = true
                            S.Print(S.Text("Automatic raid markers were blocked by the client."))
                            return
                        end
                        Remember(unit, marker, spec[2])
                    end
                end
            end
        end
    end
end

local function PanelButton(self, label, secure, action)
    local button = S.CreateFrame("Button", nil, self.panelBody,
        secure and "SecureActionButtonTemplate" or "UIPanelButtonTemplate")
    button:SetSize(106, 25)
    if secure then
        -- The secure template has no artwork of its own.
        local back = S.CreateTexture(button, nil, "BACKGROUND")
        back:SetAllPoints(button)
        back:SetColorTexture(.12, .15, .2, .95)
        local hover = S.CreateTexture(button, nil, "HIGHLIGHT")
        hover:SetAllPoints(button)
        hover:SetColorTexture(1, 1, 1, .12)
    end
    local text = S.CreateFontString(button, nil, "OVERLAY")
    text:SetPoint("CENTER", 0, 0)
    S.SetStyledFont(text, S.GlobalFontPath(), 11, "OUTLINE", 1, true, 70, 1)
    text:SetText(S.Text(label))
    if secure then button:SetAttribute("useOnKeyDown", false) end
    if action then button:SetScript("OnClick", action) end
    self.panelButtons[#self.panelButtons + 1] = button
    return button
end

local MARK_HELP = "Canceled placement still advances the sequence. Right-click Next worldmark to rewind without clearing a marker. Clear previous mark removes the last requested marker, not a confirmed placement."
local function MarkerHelp(button)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(S.Text(MARK_HELP), 1, 1, 1, nil, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function CreatePanel(self)
    if self.panel then return end
    local host = S.CreateFrame("Frame", "MSUFSuiteRaidTools", UIParent, "SecureHandlerBaseTemplate")
    local body = S.CreateFrame("Frame", nil, host, "SecureHandlerBaseTemplate")
    body:SetPoint("TOPLEFT", 0, -28)
    local back = S.CreateTexture(body, nil, "BACKGROUND")
    back:SetAllPoints(body)
    back:SetColorTexture(.04, .05, .07, .95)
    self.panel, self.panelBody, self.panelButtons = host, body, {}
    local toggle = S.CreateFrame("Button", nil, host, "SecureHandlerClickTemplate")
    toggle:SetSize(106, 25)
    toggle:SetPoint("TOPLEFT", 0, 0)
    toggle:SetFrameRef("body", body)
    toggle:SetAttribute("_onclick", [[local body = self:GetFrameRef("body"); if body:IsShown() then body:Hide() else body:Show() end]])
    local title = S.CreateFontString(toggle, nil, "OVERLAY")
    title:SetPoint("CENTER", 0, 0)
    S.SetStyledFont(title, S.GlobalFontPath(), 12, "OUTLINE", 1, true, 70, 1)
    title:SetText(S.Text("Raid tools +/-"))
    PanelButton(self, "Raid Manager", false, OpenRaidManager)
    PanelButton(self, "Pull 10", false, function() StartPull("10") end)
    PanelButton(self, "Ready check", false, function()
        if Available() and Permitted() and Allowed() then C_PartyInfo.DoReadyCheck() end
    end)
    local nextMark = PanelButton(self, "Next worldmark", true)
    MarkerHelp(nextMark)
    nextMark:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    nextMark:SetAttribute("type", "worldmarker")
    nextMark:SetAttribute("action", "set")
    SecureHandlerWrapScript(nextMark, "PreClick", host, [[
        if down then return end
        if button == "RightButton" then
            self:SetAttribute("type", nil)
            local count = control:GetAttribute("count") or 0
            if count > 0 then
                control:SetAttribute("next", ((control:GetAttribute("next") or 1) + 6) % 8 + 1)
                control:SetAttribute("count", count - 1)
            end
            return
        end
        self:SetAttribute("type", "worldmarker")
        local marker = control:GetAttribute("next") or 1
        self:SetAttribute("marker", marker)
        control:SetAttribute("next", marker % 8 + 1)
        control:SetAttribute("count", math.min(8, (control:GetAttribute("count") or 0) + 1))
    ]])
    local undo = PanelButton(self, "Clear previous mark", true)
    MarkerHelp(undo)
    undo:RegisterForClicks("AnyUp")
    undo:SetAttribute("action", "clear")
    SecureHandlerWrapScript(undo, "PreClick", host, [[
        if down then return end
        local count = control:GetAttribute("count") or 0
        self:SetAttribute("type", count > 0 and "worldmarker" or nil)
        if count > 0 then
            local marker = ((control:GetAttribute("next") or 1) + 6) % 8 + 1
            self:SetAttribute("marker", marker)
            control:SetAttribute("next", marker)
            control:SetAttribute("count", count - 1)
        end
    ]])
    local clear = PanelButton(self, "Clear worldmarks", true)
    clear:RegisterForClicks("AnyUp")
    clear:SetAttribute("type", "worldmarker")
    clear:SetAttribute("action", "clear")
    SecureHandlerWrapScript(clear, "PreClick", host, [[control:SetAttribute("next", 1); control:SetAttribute("count", 0)]])
    host:Hide()
end

local function RefreshPanel(self)
    if NS.IsCombatLocked() then return end
    if not self.config.showPanel then
        if self.panel then
            UnregisterStateDriver(self.panel, "visibility")
            self.panel:Hide()
        end
        return
    end
    CreatePanel(self)
    local columns = self.config.panelColumns or 3
    local width, height = columns * 110, math.ceil(#self.panelButtons / columns) * 29
    self.panel:SetSize(width, height + 28)
    self.panelBody:SetSize(width, height)
    self.panel:ClearAllPoints()
    self.panel:SetPoint("CENTER", UIParent, "CENTER", self.config.panelX or 0, self.config.panelY or 160)
    self.panel:SetScale((self.config.panelScale or 100) / 100)
    for i, button in ipairs(self.panelButtons) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", (i - 1) % columns * 110 + 2, -math.floor((i - 1) / columns) * 29 - 2)
    end
    RegisterStateDriver(self.panel, "visibility", S.editMode and "show" or "[group] show; hide")
end

-- The controller registers the mover after Enable and Refresh
-- (S.RefreshEditMover). A registration stays, so the mover follows the
-- panel option: a hidden panel offers no mover.
function M:RegisterMovers()
    S.RegisterOwnedMover("groupRaidShortcuts", "tools", {
        label = "Raid tools", order = 650, getFrame = function() return self.panel end,
        xKey = "panelX", yKey = "panelY", point = function() return "CENTER" end, quickPosition = true,
        isEnabled = function() return self.config.showPanel == true end,
    })
end

function M:Refresh()
    RefreshPanel(self)
    local c = self.config
    local options = table.concat({ tostring(c.autoMarkTank), tostring(c.autoMarkHealer),
        tostring(c.tankMarker), tostring(c.healerMarker) }, ":")
    if self.autoOptions ~= options then
        self.autoOptions, self.autoBlocked = options, nil
        self.autoAttempts, self.autoAttemptCount = {}, 0
    end
    if self.config.autoMarkTank or self.config.autoMarkHealer then
        self.context:Event("GROUP_ROSTER_UPDATE", AutoMark)
        self.context:Event("PLAYER_ROLES_ASSIGNED", AutoMark)
        self.context:Event("ROLE_CHANGED_INFORM", AutoMark)
        self.context:Event("PLAYER_REGEN_ENABLED", AutoMark)
        AutoMark(self)
    else
        self.context:RemoveEvent("GROUP_ROSTER_UPDATE")
        self.context:RemoveEvent("PLAYER_ROLES_ASSIGNED")
        self.context:RemoveEvent("ROLE_CHANGED_INFORM")
        self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    end
end

function M:Enable()
    S.RegisterSlash(COMMANDS.raid, OpenRaidManager, "/msufraid")
    S.RegisterSlash(COMMANDS.pull, StartPull, "/msufpull")
    S.RegisterSlash(COMMANDS.mark, MarkRole, "/msufmark")
    self:Refresh()
end

-- The controller stops a module only outside combat lockdown (S.Apply).
function M:Disable()
    if self.panel then
        UnregisterStateDriver(self.panel, "visibility")
        self.panel:Hide()
    end
    self.context:RemoveEvent("GROUP_ROSTER_UPDATE")
    self.context:RemoveEvent("PLAYER_ROLES_ASSIGNED")
    self.context:RemoveEvent("ROLE_CHANGED_INFORM")
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    self.autoOptions, self.autoAttempts, self.autoAttemptCount, self.autoBlocked = nil, nil, nil, nil
    S.UnregisterSlash(COMMANDS.raid, OpenRaidManager)
    S.UnregisterSlash(COMMANDS.pull, StartPull)
    S.UnregisterSlash(COMMANDS.mark, MarkRole)
end

S.Install("groupRaidShortcuts", M)
