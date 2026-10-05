-- The owned Micro Bar registers and unregisters only events the client knows.
-- INPUT_DEVICE_INTERFACE_TRANSITION exists on WoW Forever only (upstream/forever
-- Blizzard_APIDocumentationGenerated/InputDocumentation.lua; absent from live),
-- and the client raises for an unknown event on RegisterEvent and on
-- UnregisterEvent ("Attempt to unregister unknown event"). On Retail, handing
-- the menu back (skin off, master switch off, Blizzard layout) must neither
-- raise nor leave the bar half disabled; taking the menu again registers every
-- event again. Real Safety, AdapterKit and OwnedMicroBar* files.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

securecallfunction = function(callback, ...) return callback(...) end
function hooksecurefunc(target, method, callback)
    if type(target) == "string" then target, method, callback = _G, target, method end
    local original = target[method]
    assert(type(original) == "function", "hook target missing: " .. tostring(method))
    target[method] = function(...)
        original(...)
        callback(...)
    end
end

local known
local widgets = setmetatable({}, { __mode = "k" })
local function State(widget) return widgets[widget] end
local function Widget(name, parent, methods)
    methods = methods or {}
    local widget = methods
    widgets[widget] = { name = name, parent = parent, scale = 1, points = {}, shown = true,
        width = 10, height = 10, alpha = 1, events = {} }
    local function Own() return widgets[widget] end
    function methods:GetName() return Own().name end
    function methods:GetObjectType() return "Frame" end
    function methods:IsForbidden() return false end
    function methods:IsProtected() return false, false end
    function methods:GetParent() return Own().parent end
    function methods:SetParent(newParent) Own().parent = newParent end
    function methods:SetScale(scale) Own().scale = scale end
    function methods:GetScale() return Own().scale end
    function methods:GetEffectiveScale() return Own().scale end
    function methods:ClearAllPoints() Own().points = {} end
    function methods:SetPoint(...) local p = Own().points; p[#p + 1] = { ... } end
    function methods:GetNumPoints() return #Own().points end
    function methods:GetPoint(index) return unpack(Own().points[index or 1] or {}) end
    function methods:SetSize(width, height) Own().width, Own().height = width, height end
    function methods:GetWidth() return Own().width end
    function methods:GetHeight() return Own().height end
    function methods:GetCenter() return 500, 100 end
    function methods:IsShown() return Own().shown end
    function methods:Show() Own().shown = true end
    function methods:Hide() Own().shown = false end
    function methods:SetShown(shown) Own().shown = shown == true end
    function methods:SetAlpha(alpha) Own().alpha = alpha end
    function methods:GetAlpha() return Own().alpha end
    function methods:GetFrameLevel() return 1 end
    function methods:GetFrameStrata() return "MEDIUM" end
    function methods:GetWindow() return nil end
    function methods:CreateTexture() return Widget() end
    function methods:CreateMaskTexture() return Widget() end
    function methods:CreateFontString() return Widget() end
    function methods:SetScript(script, handler) Own()[script] = handler end
    function methods:HookScript() end
    function methods:GetScaledRect() return 0, 0, 10, 10 end
    -- The client's event registration: an unknown event raises either way.
    function methods:RegisterEvent(event)
        assert(known(event), 'Frame:RegisterEvent(): Attempt to register unknown event "' .. event .. '"')
        Own().events[event] = true
    end
    methods.RegisterUnitEvent = methods.RegisterEvent
    function methods:UnregisterEvent(event)
        assert(known(event), 'Frame:UnregisterEvent(): Attempt to unregister unknown event "' .. event .. '"')
        Own().events[event] = nil
    end
    return setmetatable(widget, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return Noop end
    end })
end

UIParent = Widget("UIParent")
local createdFrames = {}
CreateFrame = function(_, name, parent)
    local frame = Widget(name, parent)
    createdFrames[#createdFrames + 1] = frame
    return frame
end
FrameUtil = { SetParentMaintainRenderLayering = function(frame, parent) frame:SetParent(parent) end }
SetPortraitTexture, RegisterStateDriver, UnregisterStateDriver = Noop, Noop, Noop
IsInInstance = function() return false end
C_Housing = { IsInsideHouseOrPlot = function() return false end }
C_GameRules = { GetGameRuleAsFloat = function() return 0 end }
C_Timer = { After = Noop }
Enum = { GameRule = { MicrobarScale = 7 }, LuaCurveType = { Step = 1 } }
EditModeSystemMixin = { IsInDefaultPosition = function() return true end }
MicroMenuPositionEnum = { BottomLeft = 1, BottomRight = 2, TopLeft = 3, TopRight = 4 }
EditModeManagerFrame = { UpdateSystem = Noop }
GridLayoutUtil = {
    CreateStandardGridLayout = function() return {} end,
    CreateVerticalGridLayout = function() return {} end,
    ApplyGridLayout = function(children)
        for _, child in ipairs(children) do child:ClearAllPoints(); child:SetPoint("TOPLEFT") end
    end,
}
AnchorUtil = { CreateAnchor = function() return {} end }
HelpOpenWebTicketButton = Widget("HelpOpenWebTicketButton")

local BAR_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
    "PET_BATTLE_CLOSE", "UNIT_PORTRAIT_UPDATE" }
local INPUT_EVENT = "INPUT_DEVICE_INTERFACE_TRANSITION"

local function Session(forever)
    known = function(event) return forever or event ~= INPUT_EVENT end
    createdFrames = {}
    local container = Widget("MicroMenuContainer", UIParent)
    function container:GetPosition() return MicroMenuPositionEnum.BottomRight end
    MicroMenuContainer = container
    local menuMethods = { numButtons = 2, stride = 2, isHorizontal = true, layoutFramesGoingRight = true,
        layoutFramesGoingUp = false, childXPadding = 0, childYPadding = 0, normalScale = 1 }
    local menu = Widget("MicroMenu", container, menuMethods)
    local buttons = { Widget("CharacterMicroButton", menu), Widget("QuestLogMicroButton", menu) }
    buttons[1].layoutIndex, buttons[2].layoutIndex = 1, 2
    function menuMethods:GetChildren() return buttons[1], buttons[2] end
    function menuMethods:GetLayoutChildren() return buttons end
    function menuMethods:UpdateScale() self:SetScale(self.normalScale) end
    MicroMenu = menu
    local settings = {
        layoutMode = "owned", scale = 0.8, buttonsPerLine = 13, spacing = 0, padding = 4,
        orientation = "horizontal", growth = "RIGHT_DOWN", barMaterial = "modern", iconStyle = "line",
        visibility = "always", locked = true, layoutPoint = "BOTTOM", layoutRelativePoint = "BOTTOM",
        layoutX = 0, layoutY = 0, buttonSize = 30,
    }
    local NS = {
        L = setmetatable({}, { __index = function(_, key) return key end }),
        -- Core/Client.lua: C_EventUtils.IsEventValid(event) == true.
        Client = { isForever = forever, SupportsEvent = function(event) return known(event) end },
        IsCombatLocked = function() return false end,
        DB = { icons = { microMenu = settings }, skins = {} },
        Defaults = { icons = { microMenu = settings } },
        MicroMenuMaxButtonsPerLine = 13,
        MicroMenuLoadConditions = {},
        Clamp = function(value, minimum, maximum)
            value = tonumber(value) or minimum
            return math.max(minimum, math.min(maximum, value))
        end,
        Surface = { Attach = function() return {} end, SetVisible = Noop },
        Theme = { GetColor = function() return 1, 1, 1, 1 end },
        CombatGate = { RunOrDefer = function(_, callback) callback(); return true end },
    }
    NS.MicroMenuSkin = {
        RefreshButtonStates = function() return true end,
        RefreshActive = function() return NS.OwnedMicroBar.Apply(MicroMenu, settings) end,
    }
    for _, file in ipairs({ "Core/Safety.lua", "Adapters/AdapterKit.lua", "Adapters/OwnedMicroBarLayout.lua",
        "Adapters/OwnedMicroBarVisibility.lua", "Adapters/OwnedMicroBarEditMode.lua", "Adapters/OwnedMicroBar.lua" }) do
        assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
    end
    -- OwnedMicroBar.lua creates its event frame first, at load.
    return NS.OwnedMicroBar, menu, container, State(createdFrames[1]).events
end

for _, forever in ipairs({ false, true }) do
    local client = forever and "Forever" or "Retail"
    local Owned, menu, container, events = Session(forever)
    local target, mode = Owned.Apply(menu)
    Check(mode == "owned" and target == Owned.GetFrames() and Owned.active, client .. ": the bar did not take the menu")
    for _, event in ipairs(BAR_EVENTS) do
        Check(events[event], client .. ": the owned bar did not register " .. event)
    end
    Check((events[INPUT_EVENT] == true) == forever,
        client .. ": the Gamepad UI event registration does not follow the client")
    -- Skin off, master switch off or the Blizzard layout all hand the menu back.
    local disabled, reason = Owned.Disable(menu)
    Check(disabled and reason == "disabled" and not Owned.active and State(menu).parent == container,
        client .. ": handing the menu back failed")
    for _, event in ipairs(BAR_EVENTS) do
        Check(not events[event], client .. ": " .. event .. " stayed registered after the hand-back")
    end
    Check(not events[INPUT_EVENT], client .. ": the Gamepad UI event stayed registered after the hand-back")
    -- Taking the menu again registers every event again.
    Owned.Apply(menu)
    for _, event in ipairs(BAR_EVENTS) do
        Check(events[event], client .. ": taking the menu again did not register " .. event)
    end
    Check(Owned.Disable(menu) and not Owned.active, client .. ": the second hand-back failed")
end

print("Suite skin owned Micro Bar events: " .. checks .. " checks passed")
