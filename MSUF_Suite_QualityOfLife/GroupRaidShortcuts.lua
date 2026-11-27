local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local COMMANDS = { raid = "MSUFSUITERAID", pull = "MSUFSUITEPULL", mark = "MSUFSUITEMARK" }
local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local AUTO_ROLES = { { "autoMarkTank", "TANK", "tankMarker" },
    { "autoMarkHealer", "HEALER", "healerMarker" } }
local MARKER_COUNT = 8
local PANEL_BUTTON_WIDTH, PANEL_BUTTON_HEIGHT, PANEL_COLUMN, PANEL_ROW = 106, 25, 110, 29
local COMPACT_HEIGHT, COMPACT_WIDTH = 18, 106
local MARKER_SIZE, MARKER_STEP, MARKER_ROW_HEIGHT = 22, 25, 26

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
    if not NS.InCombat() and not NS.GroupActionsRestricted() then return true end
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
    if NS.InCombat() then
        S.Print(NS.RestrictedNotice())
        return
    end
    -- Forever's Gamepad UI opens this manager through its own binding.
    if S.GamepadUI() then
        S.Print(S.Text("Raid Manager could not be opened by the client."))
        return
    end
    if not S.Dispatch(NS.Finish, CompactRaidFrameManager_Expand) then
        S.Print(S.Text("Raid Manager could not be opened by the client."))
    end
end

local function CanLead()
    if not Available() then return false end
    if not Permitted() then
        S.Print(S.Text("Group leader or assistant required"))
        return false
    end
    return true
end

local function RunPull(seconds)
    if not Allowed() then return end
    local started = C_PartyInfo.DoCountdown(seconds)
    if not S.Public(started) or started ~= true then
        S.Print(S.Text("Countdown could not be started"))
    end
end

local function StartPull(message)
    if not S.Public(message) or type(message) ~= "string" or not CanLead() then return end
    local seconds = message:match("^%s*(%d*)%s*$")
    seconds = seconds == "" and 10 or tonumber(seconds)
    if not S.Finite(seconds) or seconds < 1 or seconds > 60 then
        S.Print(S.Text("Usage: /msufpull [1-60]"))
        return
    end
    RunPull(seconds)
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

local function DarkButton(button)
    local back = S.CreateTexture(button, nil, "BACKGROUND")
    back:SetAllPoints(button)
    back:SetColorTexture(.12, .15, .2, .95)
    local hover = S.CreateTexture(button, nil, "HIGHLIGHT")
    hover:SetAllPoints(button)
    hover:SetColorTexture(1, 1, 1, .12)
    return back, hover
end

local function PanelLabel(parent, label, size, point, x, y)
    local text = S.CreateFontString(parent, nil, "OVERLAY")
    text:SetPoint(point, x, y)
    S.SetStyledFont(text, S.GlobalFontPath(), size, "OUTLINE", 1, true, 70, 1)
    text:SetText(S.Text(label))
    return text
end

local function PanelButton(self, label, secure, action)
    local button = S.CreateFrame("Button", nil, self.panelBody,
        secure and "SecureActionButtonTemplate" or "UIPanelButtonTemplate")
    button:SetSize(PANEL_BUTTON_WIDTH, PANEL_BUTTON_HEIGHT)
    if secure then
        DarkButton(button)
        button:SetAttribute("useOnKeyDown", false)
    end
    local text = PanelLabel(button, label, 11, "CENTER", 0, 0)
    if action then button:SetScript("OnClick", action) end
    self.panelButtons[#self.panelButtons + 1] = button
    return button, text
end

local MARK_HELP = "Canceled placement still advances the sequence. Right-click Next worldmark to rewind without clearing a marker. Clear previous mark removes the last requested marker, not a confirmed placement."
local function AttachHelp(button, label)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(S.Text(label), 1, 1, 1, nil, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(owner)
        if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    end)
end

local function AddWorldmarkSequence(self, host)
    local nextMark = PanelButton(self, "Next worldmark", true)
    AttachHelp(nextMark, MARK_HELP)
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
    AttachHelp(undo, MARK_HELP)
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
end

-- The two native marker types use different IDs. The world marker order and
-- atlases follow Blizzard's Mainline CompactRaidFrameManager on both clients.
local WORLD_MARKER_ORDER = { 8, 4, 1, 7, 2, 3, 6, 5 }

local function CreateMarkerRow(parent, world)
    local row = S.CreateFrame("Frame", nil, parent, "SecureHandlerBaseTemplate")
    PanelLabel(row, world and "World marker" or "Target marker", 10, "LEFT", 4, 0)
    local help = world and "Left-click to place this world marker. Right-click to clear it."
        or "Left-click to mark the target. Right-click to remove its marker."
    for index = 1, MARKER_COUNT do
        local button = S.CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
        button:SetSize(MARKER_SIZE, MARKER_SIZE)
        button:SetPoint("RIGHT", row, "RIGHT", -4 - (MARKER_COUNT - index) * MARKER_STEP, 0)
        DarkButton(button)
        local icon = S.CreateTexture(button, nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("CENTER", 0, 0)
        if world then
            icon:SetAtlas("GM-raidMarker" .. index)
        else
            icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index)
            button:SetAttribute("unit", "target")
        end
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetAttribute("useOnKeyDown", false)
        button:SetAttribute("type", world and "worldmarker" or "raidtarget")
        button:SetAttribute("marker", world and WORLD_MARKER_ORDER[index] or index)
        button:SetAttribute("action1", "set")
        button:SetAttribute("action2", "clear")
        AttachHelp(button, help)
    end
    return row
end

local function CreatePanel(self)
    if self.panel then return end
    local host = S.CreateFrame("Frame", "MSUFSuiteRaidTools", UIParent, "SecureHandlerBaseTemplate")
    local body = S.CreateFrame("Frame", nil, host, "SecureHandlerBaseTemplate")
    local back = S.CreateTexture(body, nil, "BACKGROUND")
    back:SetAllPoints(body)
    back:SetColorTexture(.04, .05, .07, .95)
    self.panel, self.panelBody, self.panelButtons = host, body, {}
    local toggle = S.CreateFrame("Button", nil, host, "SecureHandlerClickTemplate")
    toggle:RegisterForClicks("LeftButtonUp")
    toggle:SetFrameRef("body", body)
    toggle:SetAttribute("_onclick", [[
        local body = self:GetFrameRef("body")
        if body:IsShown() then body:Hide() else body:Show() end
    ]])
    self.panelToggle = toggle
    self.panelTabBack, self.panelTabHover = DarkButton(toggle)
    self.panelTitle = PanelLabel(toggle, "Raid tools +/-", 12, "CENTER", 0, 0)
    PanelButton(self, "Raid Manager", false, OpenRaidManager)
    local _, pullText = PanelButton(self, "Pull 10", false, function()
        if CanLead() then RunPull(self.config.panelPullSeconds or 10) end
    end)
    self.panelPullText = pullText
    PanelButton(self, "Ready check", false, function()
        if CanLead() and Allowed() then C_PartyInfo.DoReadyCheck() end
    end)
    AddWorldmarkSequence(self, host)
    host:Hide()
end

local function PanelPoint(self)
    return NS.AnchorPoints[self.config.panelPoint or 5] or "CENTER"
end

local function LayoutMarkerRows(self, width, controlsHeight, compact)
    if compact and not self.panelTargetMarkers then
        self.panelTargetMarkers = CreateMarkerRow(self.panelBody, false)
        self.panelWorldMarkers = CreateMarkerRow(self.panelBody, true)
    end
    if not self.panelTargetMarkers then return end
    local target, world = self.panelTargetMarkers, self.panelWorldMarkers
    target:SetShown(compact)
    world:SetShown(compact)
    if not compact then return end
    target:SetSize(width, MARKER_ROW_HEIGHT)
    target:ClearAllPoints()
    target:SetPoint("TOPLEFT", self.panelBody, "TOPLEFT", 0, -controlsHeight)
    world:SetSize(width, MARKER_ROW_HEIGHT)
    world:ClearAllPoints()
    world:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, 0)
end

local function LayoutPanelTab(self, compact, point, width, height)
    local panel, body, toggle = self.panel, self.panelBody, self.panelToggle
    local tabHeight = compact and COMPACT_HEIGHT or PANEL_BUTTON_HEIGHT
    toggle:SetSize(compact and COMPACT_WIDTH or PANEL_BUTTON_WIDTH, tabHeight)
    toggle:ClearAllPoints()
    toggle:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    self.panelTabBack:SetShown(compact)
    self.panelTabHover:SetShown(compact)
    self.panelTitle:SetText(compact and S.Text("Raid Control") or S.Text("Raid tools +/-"))
    body:SetSize(width, height)
    body:ClearAllPoints()
    if compact then
        local side = point:find("LEFT", 1, true) and "LEFT" or point:find("RIGHT", 1, true) and "RIGHT" or ""
        if point:find("BOTTOM", 1, true) then
            body:SetPoint("BOTTOM" .. side, toggle, "TOP" .. side, 0, 3)
        else
            body:SetPoint("TOP" .. side, toggle, "BOTTOM" .. side, 0, -3)
        end
    else
        body:SetPoint("TOPLEFT", toggle, "BOTTOMLEFT", 0, -3)
    end
    if self.panelCompact ~= compact then
        body:SetShown(not compact)
        self.panelCompact = compact
    end
    panel:SetSize(compact and COMPACT_WIDTH or width, compact and tabHeight or height + tabHeight + 3)
end

local function RefreshPanel(self)
    if NS.InCombat() then
        if self.config.showPanel or self.panel then S.Queue("groupRaidShortcuts") end
        return
    end
    if not self.config.showPanel then
        if self.panel then
            UnregisterStateDriver(self.panel, "visibility")
            self.panel:Hide()
        end
        return
    end
    CreatePanel(self)
    local config = self.config
    local columns, compact = config.panelColumns or 3, config.panelCompact == true
    local point = PanelPoint(self)
    local controlsHeight = math.ceil(#self.panelButtons / columns) * PANEL_ROW
    local width = columns * PANEL_COLUMN
    if compact then width = math.max(width, 300) end
    LayoutMarkerRows(self, width, controlsHeight, compact)
    LayoutPanelTab(self, compact, point, width, controlsHeight + (compact and MARKER_ROW_HEIGHT * 2 or 0))
    self.panel:ClearAllPoints()
    self.panel:SetPoint(point, UIParent, point, config.panelX or 0, config.panelY or 160)
    self.panel:SetScale((config.panelScale or 100) / 100)
    local pullSeconds = config.panelPullSeconds or 10
    self.panelPullText:SetText(pullSeconds == 10 and S.Text("Pull 10") or S.Text("Pull %d"):format(pullSeconds))
    for i, button in ipairs(self.panelButtons) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", (i - 1) % columns * PANEL_COLUMN + 2, -math.floor((i - 1) / columns) * PANEL_ROW - 2)
    end
    RegisterStateDriver(self.panel, "visibility", S.editMode and "show" or "[group] show; hide")
end

-- The controller registers the mover after Enable and Refresh
-- (S.RefreshEditMover). A registration stays, so the mover follows the
-- panel option: a hidden panel offers no mover.
function M:RegisterMovers()
    S.RegisterOwnedMover("groupRaidShortcuts", "tools", {
        label = "Raid tools", order = 650, getFrame = function() return self.panel end,
        xKey = "panelX", yKey = "panelY", pointKey = "panelPoint", point = function() return PanelPoint(self) end,
        quickPosition = true,
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
