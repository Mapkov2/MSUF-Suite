-- The owned Micro Bar never runs Blizzard code that writes MicroMenu or Edit
-- Mode fields (SetOverrideScale, ResetMicroMenuPosition, Layout, Edit Mode's
-- UpdateSystem) and writes no MicroMenu field itself: Blizzard reads those
-- fields again in combat (vehicle exit), so a value written from addon code
-- would taint that secure pass. It scales the menu with the widget method,
-- keeps that scale through Blizzard's own UpdateScale, yields to Blizzard's
-- overrides, and hands the menu back to its container the way Blizzard's
-- layout places it. Real OwnedMicroBarLayout, OwnedMicroBarVisibility,
-- OwnedMicroBarEditMode, OwnedMicroBar, Safety and AdapterKit.
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

-- While `blizzard` is set, the test plays Blizzard's own code; everything
-- else that writes a MicroMenu field or calls a field-writing method is the
-- skin's and a violation.
local blizzard = false
local violations = {}
local function Violation(what)
    if not blizzard then violations[#violations + 1] = what end
end
local function Clean(step)
    Check(#violations == 0, step .. " ran Blizzard field writes from addon code: " .. table.concat(violations, ", "))
end

local widgets = setmetatable({}, { __mode = "k" })
local function State(widget) return widgets[widget] end
local function Widget(name, parent, methods)
    methods = methods or {}
    local widget = methods
    widgets[widget] = { name = name, parent = parent, scale = 1, points = {}, shown = true,
        width = 10, height = 10 }
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
    function methods:GetFrameLevel() return 1 end
    function methods:GetFrameStrata() return "MEDIUM" end
    function methods:GetWindow() return nil end
    function methods:CreateTexture() return Widget() end
    function methods:CreateMaskTexture() return Widget() end
    function methods:CreateFontString() return Widget() end
    function methods:SetScript() end
    function methods:HookScript() end
    function methods:GetScaledRect() return 0, 0, 10, 10 end
    return setmetatable(widget, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return Noop end
    end })
end

UIParent = Widget("UIParent")
CreateFrame = function(_, name, parent) return Widget(name, parent) end
FrameUtil = { SetParentMaintainRenderLayering = function(frame, parent) frame:SetParent(parent) end }
SetPortraitTexture, RegisterStateDriver, UnregisterStateDriver = Noop, Noop, Noop
IsInInstance = function() return false end
C_Housing = { IsInsideHouseOrPlot = function() return false end }
local ruleFactor = 0
C_GameRules = { GetGameRuleAsFloat = function() return ruleFactor end }
Enum = { GameRule = { MicrobarScale = 7 }, LuaCurveType = { Step = 1 } }
EditModeSystemMixin = { IsInDefaultPosition = function() return true end }
MicroMenuPositionEnum = { BottomLeft = 1, BottomRight = 2, TopLeft = 3, TopRight = 4 }
local systemUpdates = 0
EditModeManagerFrame = { UpdateSystem = function()
    Violation("EditModeManagerFrame:UpdateSystem")
    systemUpdates = systemUpdates + 1
end }
GridLayoutUtil = {
    CreateStandardGridLayout = function() return {} end,
    CreateVerticalGridLayout = function() return {} end,
    ApplyGridLayout = function(children)
        for _, child in ipairs(children) do child:ClearAllPoints(); child:SetPoint("TOPLEFT") end
    end,
}
AnchorUtil = { CreateAnchor = function() return {} end }
HelpOpenWebTicketButton = Widget("HelpOpenWebTicketButton")

------------------------------------------------------------------ Blizzard's menu
local container = Widget("MicroMenuContainer", UIParent)
function container:GetPosition() return MicroMenuPositionEnum.BottomRight end
function container:Layout() Violation("MicroMenuContainer:Layout") end
MicroMenuContainer = container
-- MicroMenu's Blizzard fields live behind the table, so every write of one
-- passes __newindex; methods hooked by hooksecurefunc are stored as usual.
local fields = {
    numButtons = 2, stride = 2, isHorizontal = true, layoutFramesGoingRight = true,
    layoutFramesGoingUp = false, childXPadding = 0, childYPadding = 0, normalScale = 1,
}
local menuMethods = {}
local menu = Widget("MicroMenu", container, menuMethods)
local buttons = { Widget("CharacterMicroButton", menu), Widget("QuestLogMicroButton", menu) }
buttons[1].layoutIndex, buttons[2].layoutIndex = 1, 2
function menuMethods:GetChildren() return buttons[1], buttons[2] end
function menuMethods:GetLayoutChildren() return buttons end
function menuMethods:UpdateScale()
    local useScale = fields.overrideScale or fields.normalScale
    local factor = C_GameRules.GetGameRuleAsFloat(Enum.GameRule.MicrobarScale)
    self:SetScale(factor ~= 0 and useScale * factor or useScale)
end
function menuMethods:SetOverrideScale(scale)
    Violation("SetOverrideScale")
    self.overrideScale = scale
    self:UpdateScale()
end
function menuMethods:ClearOverrideScale() Violation("ClearOverrideScale"); self:SetOverrideScale(nil) end
function menuMethods:SetNormalScale(scale)
    Violation("SetNormalScale")
    self.normalScale = scale
    self:UpdateScale()
end
function menuMethods:Layout()
    Violation("MicroMenu:Layout")
    self.oldGridSettings = {}
end
function menuMethods:MarkDirty() Violation("MarkDirty"); self.dirty = true end
function menuMethods:AnchorToMenuContainer(position)
    if self:GetParent() ~= MicroMenuContainer then return end
    local point = ({ "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT", "TOPRIGHT" })[position]
    self:ClearAllPoints()
    self:SetPoint(point, MicroMenuContainer, point, 0, 0)
end
function menuMethods:ResetMicroMenuPosition()
    Violation("ResetMicroMenuPosition")
    self:SetParent(MicroMenuContainer)
    self.stride = self.numButtons
    self:ClearOverrideScale()
    EditModeManagerFrame:UpdateSystem(MicroMenuContainer, true)
end
function menuMethods:OverrideMicroMenuPosition(parent, anchor, anchorTo, relAnchor, x, y)
    Violation("OverrideMicroMenuPosition")
    self:SetOverrideScale(0.85)
    self:SetParent(parent)
    self.isHorizontal = true
    self:ClearAllPoints()
    self:SetPoint(anchor, anchorTo, relAnchor, x, y)
end
setmetatable(menu, {
    __index = function(_, key)
        local value = fields[key]
        if value ~= nil then return value end
        if type(key) == "string" and key:match("^%u") then return Noop end
    end,
    __newindex = function(table, key, value)
        if type(value) == "function" then
            rawset(table, key, value)
            return
        end
        Violation("MicroMenu." .. tostring(key) .. " =")
        fields[key] = value
    end,
})
MicroMenu = menu
-- Blizzard's own calls into its menu (vehicle enter/exit, Edit Mode).
local function AsBlizzard(callback, ...)
    blizzard = true
    callback(...)
    blizzard = false
end

------------------------------------------------------------------ skin
local reapplies = 0
local settings = {
    layoutMode = "owned", scale = 0.8, buttonsPerLine = 13, spacing = 0, padding = 4,
    orientation = "horizontal", growth = "RIGHT_DOWN", barMaterial = "modern", iconStyle = "line",
    visibility = "always", locked = true, layoutPoint = "BOTTOM", layoutRelativePoint = "BOTTOM",
    layoutX = 0, layoutY = 0, buttonSize = 30,
}
local NS = {
    -- The skin's locale table (Locales/Localization.lua) is ready before
    -- any of this runs; here every key reads as itself.
    L = setmetatable({}, { __index = function(_, key) return key end }),
    Client = { isForever = false, SupportsEvent = function() return true end },
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
    RefreshActive = function()
        reapplies = reapplies + 1
        return NS.OwnedMicroBar.Apply(MicroMenu, settings)
    end,
}
for _, file in ipairs({ "Core/Safety.lua", "Adapters/AdapterKit.lua", "Adapters/OwnedMicroBarLayout.lua",
    "Adapters/OwnedMicroBarVisibility.lua", "Adapters/OwnedMicroBarEditMode.lua", "Adapters/OwnedMicroBar.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
local Owned = NS.OwnedMicroBar

local target, mode = Owned.Apply(menu, settings)
local bar = Owned.GetFrames()
Check(mode == "owned" and target == bar and State(menu).parent == bar, "the owned bar did not take the menu")
Check(math.abs(State(menu).scale - 0.8) < 1e-9, "the owned scale was not set on the menu")
Clean("taking the menu")
-- The game rule factor Blizzard's UpdateScale applies stays part of it.
ruleFactor = 1.25
Owned.Apply(menu, settings)
Check(math.abs(State(menu).scale - 1.0) < 1e-9, "the owned scale dropped the game rule factor")
ruleFactor = 0
Owned.Apply(menu, settings)
Clean("placing the bar again")

-- Edit Mode applies Blizzard's own Micro Menu size: the owned scale stays.
AsBlizzard(function() fields.normalScale = 1.3; menu:UpdateScale() end)
Check(math.abs(State(menu).scale - 0.8) < 1e-9, "a native UpdateScale replaced the owned scale")
Clean("keeping the owned scale")

-- A vehicle takes the menu with Blizzard's override scale: the bar yields.
local overrideBar = Widget("OverrideActionBar", UIParent)
AsBlizzard(menu.OverrideMicroMenuPosition, menu, overrideBar, "BOTTOM", overrideBar, "BOTTOM", 0, 0)
Check(State(menu).parent == overrideBar and math.abs(State(menu).scale - 0.85) < 1e-9,
    "the owned bar fought Blizzard's vehicle override")
Clean("yielding to a vehicle")
-- Leaving the vehicle runs Blizzard's reset; the bar takes the menu again.
AsBlizzard(menu.ResetMicroMenuPosition, menu)
Check(State(menu).parent == bar and math.abs(State(menu).scale - 0.8) < 1e-9,
    "the owned bar did not take the menu back after the vehicle")
Clean("taking the menu back")

-- Disable hands the menu back like Blizzard's reset would leave it, without
-- running that reset: container parent, container anchor, Blizzard's scale.
fields.normalScale = 1.1
local updates = systemUpdates
Owned.Disable(menu)
local point = State(menu).points[1]
Check(State(menu).parent == container, "disable did not hand the menu back to its container")
Check(point and point[1] == "BOTTOMRIGHT" and point[2] == container,
    "the handed-back menu was not anchored in its container")
Check(math.abs(State(menu).scale - 1.1) < 1e-9, "the handed-back menu kept the owned scale")
Check(systemUpdates == updates, "handing the menu back ran Edit Mode's UpdateSystem")
Clean("handing the menu back")

-- A full-screen flow leaves MicroMenu on UIParent: the bar takes it from
-- there without a reset, and hands it back to the container.
State(menu).parent = UIParent
Owned.Apply(menu, settings)
Check(State(menu).parent == bar, "the bar did not take a menu Blizzard left on UIParent")
Owned.Disable(menu)
Check(State(menu).parent == container, "a menu taken from UIParent was not handed back to its container")
Clean("taking the menu from UIParent")

-- No Blizzard field changed through the skin.
Check(fields.stride == 2 and fields.overrideScale == nil and fields.oldGridSettings == nil
    and fields.dirty == nil and fields.isHorizontal == true, "a MicroMenu field changed")
local source = assert(io.open(root .. "/MSUF_Suite_Skin/Adapters/OwnedMicroBar.lua", "rb")):read("*a")
Check(not source:find(":SetOverrideScale(", 1, true) and not source:find(":ResetMicroMenuPosition(", 1, true)
    and not source:find(":ClearOverrideScale(", 1, true), "the owned bar still calls Blizzard's field-writing methods")

print("Suite skin owned Micro Bar taint: " .. checks .. " checks passed")
