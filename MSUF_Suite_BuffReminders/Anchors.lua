local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
local KEY, OWNER = "external:msufsuite.buffreminders:buffs", "MSUFSuite.BuffAnchor"
local EMPTY = {}
local POINT_X = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = .5, CENTER = .5, BOTTOM = .5,
    TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
local POINT_Y = { BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0, LEFT = .5, CENTER = .5, RIGHT = .5,
    TOPLEFT = 1, TOP = 1, TOPRIGHT = 1 }

-- A descendant or an anchor depending on the reminders would chase itself.
local function DependsOn(frame, host, seen, depth)
    if not S.Public(frame) then return true end
    if frame == host then return true end
    if not frame or seen[frame] then return false end
    if depth <= 0 or NS.Safety.IsForbidden(frame) then return true end
    seen[frame] = true
    if frame.GetParent and DependsOn(frame:GetParent(), host, seen, depth - 1) then return true end
    local count = 0
    if frame.GetNumPoints then count = frame:GetNumPoints() end
    if not S.Finite(count) then return true end
    for i = 1, count do
        local _, relative = frame:GetPoint(i)
        if DependsOn(relative, host, seen, depth - 1) then return true end
    end
    return false
end

local function Target(self)
    local key = self.config.anchorTarget
    if not key or key == "" or key == KEY then return nil end
    local element = NS.HostBridge.EditAnchorElements()[key]
    local frame = element and element.getFrame and element.getFrame()
    if not S.Public(frame) or type(frame) ~= "table" or not frame.GetRect
        or NS.Safety.IsForbidden(frame) then return nil end
    if DependsOn(frame, self.view.host, {}, 32) then return nil end
    return frame
end

local function Probe(self, point)
    local probe = S.CreateFrame("Frame", nil, UIParent)
    probe:SetScript("OnSizeChanged", function() R.PlaceAnchor(self) end)
    probe.point = point
    return probe
end

local function WatchTarget(self, target)
    local state = self.anchor
    if state.target == target then return end
    state.target = target
    if target and not state.probes then
        state.probes = { Probe(self, "BOTTOMLEFT"), Probe(self, "TOPRIGHT") }
    end
    for _, probe in ipairs(state.probes or EMPTY) do
        probe:ClearAllPoints()
        if target then
            probe:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
            probe:SetPoint("TOPRIGHT", target, probe.point, 0, 0)
        end
    end
end

local function TargetPosition(target, point, x, y)
    local left, bottom, width, height = target:GetRect()
    local scale, uiScale = target:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (S.Finite(left) and S.Finite(bottom) and S.Finite(width) and S.Finite(height)
        and S.Finite(scale) and S.Finite(uiScale)) or uiScale <= 0 then return nil end
    local ratio = scale / uiScale
    return (left + width * POINT_X[point]) * ratio + x, (bottom + height * POINT_Y[point]) * ratio + y
end

-- The secure reminder host stays attached to UIParent. Empty probes observe
-- moves and resizes without bringing a CDM bar into its protected anchor family.
function R.PlaceAnchor(self, x, y)
    local host, c = self.view.host, self.config
    if not host or NS.IsCombatLocked() then return false end
    local state = self.anchor
    if not state then state = {} self.anchor = state end
    if state.placing then return false end
    if c.followCursor and self.cursor.displaced and not S.editMode then return false end
    state.placing = true
    local target = Target(self)
    WatchTarget(self, target)
    local point, relative, relativePoint = R.ScreenPoint(c), UIParent, R.ScreenPoint(c)
    x, y = x or c.x, y or c.y
    if target then
        local scale, uiScale = host:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if S.Finite(scale) and S.Finite(uiScale) and scale > 0 and uiScale > 0 then
            scale = scale / uiScale
            local tx, ty = TargetPosition(target, NS.AnchorPoints[c.relativePoint or 5] or "CENTER", x * scale, y * scale)
            if tx then x, y, relativePoint = tx / scale, ty / scale, "BOTTOMLEFT" end
        end
    end
    host:ClearAllPoints()
    host:SetPoint(point, relative, relativePoint, x, y)
    state.placing = nil
    return true
end

function R.WatchAnchor(self, enabled)
    enabled = enabled and self.config.anchorTarget ~= nil and self.config.anchorTarget ~= ""
    local state = self.anchor
    if not state and not enabled then return end
    if state and not state.driver and not enabled then return end
    if not state then state = {} self.anchor = state end
    if not state.driver and enabled then
        state.driver = S.CreateFrame("Frame")
        state.driver:SetScript("OnEvent", function() R.PlaceAnchor(self) end)
        state.changed = function() R.PlaceAnchor(self) end
    end
    NS.HostBridge.WatchEditAnchors(OWNER, enabled and state.changed or nil)
    if enabled then
        for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
            "PLAYER_REGEN_ENABLED" }) do
            state.driver:RegisterEvent(event)
        end
        R.PlaceAnchor(self)
    else
        if state.driver then state.driver:UnregisterAllEvents() end
        state.placing = true
        WatchTarget(self, nil)
        state.placing = nil
    end
end

local function Choices()
    local values, current = NS.HostBridge.EditAnchorChoices(KEY), S.Config("buffReminders").anchorTarget
    for _, row in ipairs(values) do if row.value == current then return values end end
    values[#values + 1] = { value = current, text = S.Text("Unavailable") }
    return values
end

local function PointChoices(screen)
    local values = {}
    local rule = S.catalog.buffReminders.rules[screen and "point" or "relativePoint"]
    for i, label in ipairs(rule.choices) do values[i] = { value = i, text = S.Text(label) } end
    return values
end

function R.AnchorControls()
    local controls = {}
    if NS.HostBridge.EditChoiceControls and NS.HostBridge.EditChoiceControls() then
        for _, def in ipairs({ { "anchorTarget", "Attach to", Choices },
            { "point", "Reminder point", function() return PointChoices(true) end },
            { "relativePoint", "Anchor point", function() return PointChoices(false) end } }) do
            local key = def[1]
            controls[#controls + 1] = { id = key, label = S.Text(def[2]), kind = "choice", values = def[3],
                get = function() return S.Config("buffReminders")[key] end,
                set = function(value) return S.Set("buffReminders", key, value) end }
        end
    end
    for _, def in ipairs({ { "size", "Icon size", 22, 72 }, { "spacing", "Spacing", 0, 20 },
        { "columns", "Per row", 1, 12 } }) do
        local key = def[1]
        controls[#controls + 1] = { id = key, label = S.Text(def[2]), kind = "number", min = def[3], max = def[4], step = 1,
            get = function() return S.Config("buffReminders")[key] end,
            set = function(value) return S.Set("buffReminders", key, value) end }
    end
    return controls
end

