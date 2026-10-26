-- Combat end and native state storms on the owned Micro Bar (raid trace
-- 2026-10-11). Every in-combat change that moves, scales, hides or hands over
-- the menu defers the bar's Reapply through CombatGate; combat end with
-- nothing deferred brings back only what combat held back (the mover, the
-- portrait, the buttons whose state hooks fired, a changed button set) and
-- neither re-skins nor places the bar again; a layout check queued before
-- combat keeps its obligation. A deferred Reapply runs once, from the
-- CombatGate drain within its frame budget; a menu Blizzard holds still
-- takes the full pass. A native state hook repaints a
-- clean button without repeating the CanControl check per faded region, and
-- keeps the overlay paint while its inputs are unchanged; the native state
-- masks and the borrowed performance bar are checked on every repaint.
-- Real Safety, CombatGate, Registry, AdapterKit, OwnedMicroBar*, MicroMenuStates,
-- MicroMenu, MicroMenuPerformance and MicroMenuVisual.
local root = assert(arg[1], "Suite root required")
local portraitOnly = os.getenv("SUITE_MICRO_PORTRAIT_ONLY") == "1"
local baseline = os.getenv("SUITE_MICRO_BASELINE")
local forever = os.getenv("SUITE_MICRO_FOREVER") == "1"
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

local locked = false
InCombatLockdown = function() return locked end

-- Widgets keep what is written; unknown widget methods are no-ops (the
-- compositor's Attach* members stay absent).
local counts = {}
local function Count(key) counts[key] = (counts[key] or 0) + 1 end
local function ResetCounts() for key in pairs(counts) do counts[key] = nil end end
local widgetMeta = { __index = function(_, key)
    if type(key) == "string" and key:match("^%u") and not key:match("^Attach") then return Noop end
end }
local function Widget(name, parent)
    local widget = { name = name, parent = parent, scale = 1, shown = true, alpha = 1,
        width = 10, height = 10, points = 0, events = {}, scripts = {} }
    function widget:GetName() return self.name end
    function widget:GetObjectType() return "Frame" end
    function widget:IsForbidden() return false end
    function widget:IsProtected() return false, false end
    function widget:GetParent() return self.parent end
    function widget:SetParent(newParent) self.parent = newParent end
    function widget:SetScale(scale) self.scale = scale end
    function widget:GetScale() return self.scale end
    function widget:GetEffectiveScale() return self.scale end
    function widget:SetPoint() self.points = self.points + 1 end
    function widget:SetSize(width, height) self.width, self.height = width, height end
    function widget:GetWidth() return self.width end
    function widget:GetHeight() return self.height end
    function widget:GetCenter() return 500, 100 end
    function widget:GetScaledRect() return 0, 0, 10, 10 end
    function widget:IsShown() return self.shown end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:SetShown(shown) self.shown = shown == true end
    function widget:SetAlpha(alpha) self.alpha = alpha end
    function widget:GetAlpha() return self.alpha end
    function widget:GetFrameLevel() return 1 end
    function widget:CreateTexture() return Widget() end
    function widget:CreateMaskTexture() return Widget() end
    function widget:CreateFontString() return Widget() end
    function widget:SetScript(script, handler) self.scripts[script] = handler end
    function widget:HookScript(script, handler) self.scripts[script] = handler end
    function widget:RegisterEvent(event) self.events[event] = true end
    widget.RegisterUnitEvent = widget.RegisterEvent
    function widget:UnregisterEvent(event) self.events[event] = nil end
    return setmetatable(widget, widgetMeta)
end

UIParent = Widget("UIParent")
local createdFrames = {}
CreateFrame = function(_, name, parent)
    local frame = Widget(name, parent)
    createdFrames[#createdFrames + 1] = frame
    return frame
end
FrameUtil = { SetParentMaintainRenderLayering = function(frame, parent) frame:SetParent(parent) end }
SetPortraitTexture = function() Count("portrait") end
RegisterStateDriver, UnregisterStateDriver = Noop, Noop
IsInInstance = function() return false end
C_Housing = { IsInsideHouseOrPlot = function() return false end }
C_GameRules = { GetGameRuleAsFloat = function() return 0 end }
-- CombatGate's drain budget reads this clock (milliseconds).
local clock = 0
debugprofilestop = function() return clock end
local nextFrame = {}
C_Timer = { After = function(_, callback) nextFrame[#nextFrame + 1] = callback end }
local function RunNextFrame()
    local jobs = nextFrame
    nextFrame = {}
    for index = 1, #jobs do jobs[index]() end
end
Enum = { GameRule = { MicrobarScale = 7 }, LuaCurveType = { Step = 1 } }
EditModeSystemMixin = { IsInDefaultPosition = function() return true end }
MicroMenuPositionEnum = { BottomLeft = 1, BottomRight = 2, TopLeft = 3, TopRight = 4 }
GridLayoutUtil = {
    CreateStandardGridLayout = function() return {} end,
    CreateVerticalGridLayout = function() return {} end,
    ApplyGridLayout = function() Count("grid") end,
}
AnchorUtil = { CreateAnchor = function() return {} end }
HelpOpenWebTicketButton = Widget("HelpOpenWebTicketButton")

------------------------------------------------------------------ Blizzard's menu
local container = Widget("MicroMenuContainer", UIParent)
function container:GetPosition() return MicroMenuPositionEnum.BottomRight end
-- MicroMenuContainerMixin:Layout returns at once while the bar holds the menu.
function container:Layout() end
MicroMenuContainer = container
local menu = Widget("MicroMenu", container)
menu.numButtons, menu.stride, menu.isHorizontal, menu.normalScale = 2, 2, true, 1
menu.layoutFramesGoingRight, menu.layoutFramesGoingUp, menu.childXPadding, menu.childYPadding = true, false, 0, 0
local CLEAN_REGIONS = { "Background", "PushedBackground", "Portrait", "Shadow", "PushedShadow", "Emblem",
    "HighlightEmblem" }
local buttons = {}
for index, name in ipairs({ "CharacterMicroButton", "QuestLogMicroButton" }) do
    local button = Widget(name, menu)
    button.layoutIndex = index
    function button:GetObjectType() return "Button" end
    function button:IsProtected() Count("protection"); return false, false end
    for _, region in ipairs(CLEAN_REGIONS) do button[region] = Widget() end
    local textures = { Normal = Widget(), Highlight = Widget(), Pushed = Widget(), Disabled = Widget() }
    button.textures = textures
    for state, texture in pairs(textures) do
        button["Get" .. state .. "Texture"] = function() return texture end
    end
    -- MainMenuBarMicroButtonMixin's state methods (hooked by the skin).
    button.buttonState, button.enabled, button.mouseOver = "NORMAL", true, false
    function button:GetButtonState() return self.buttonState end
    function button:IsEnabled() return self.enabled end
    function button:IsMouseOver() return self.mouseOver end
    function button:SetNormal() self.buttonState = "NORMAL"; textures.Highlight:SetAlpha(1) end
    function button:SetPushed() self.buttonState = "PUSHED"; textures.Highlight:SetAlpha(0.5) end
    button.OnEnable, button.OnDisable = Noop, Noop
    _G[name], buttons[index] = button, button
end
function menu:GetChildren() return buttons[1], buttons[2] end
function menu:GetLayoutChildren()
    local shown = {}
    for _, button in ipairs(buttons) do
        if button.shown then shown[#shown + 1] = button end
    end
    return shown
end
function menu:UpdateScale() self:SetScale(self.normalScale) end
function menu:AnchorToMenuContainer() end
function menu:Layout() end
function menu:ResetMicroMenuPosition() self:SetParent(MicroMenuContainer) end
function menu:OverrideMicroMenuPosition(parent) self:SetParent(parent) end
MicroMenu = menu

------------------------------------------------------------------ skin
local settings = {
    layoutMode = "owned", scale = 1, buttonsPerLine = 13, spacing = 0, padding = 4,
    orientation = "horizontal", growth = "RIGHT_DOWN", barMaterial = "modern", iconStyle = "bold",
    visibility = "always", locked = false, layoutPoint = "BOTTOM", layoutRelativePoint = "BOTTOM",
    layoutX = 0, layoutY = 0, buttonSize = 30, tint = "native",
    buttonBackground = false, buttonBorder = 0, barBackground = false, barBorder = 0,
}
-- button -> state-only repaints, full repaints
local stateApplies, fullApplies, paintedStates = {}, {}, {}
local NS = {
    L = setmetatable({}, { __index = function(_, key) return key end }),
    Client = { isForever = forever, SupportsEvent = function() return true end },
    IsCombatLocked = function() return locked end,
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
    MicroMenuVisual = {
        Prepare = function() Count("prepare"); return true end,
        Apply = function(button, _, _, state, stateOnly)
            local applies = stateOnly and stateApplies or fullApplies
            applies[button] = (applies[button] or 0) + 1
            paintedStates[button] = state
            return true
        end,
        Restore = function() Count("restore"); return true end,
    },
}
local function Load(file)
    local source = root .. "/MSUF_Suite_Skin/" .. file
    if baseline then
        local override = baseline .. "/MSUF_Suite_Skin/" .. file
        local found = io.open(override, "rb")
        if found then found:close(); source = override end
    end
    assert(loadfile(source))("MSUF_Suite_Skin", NS)
end
for _, file in ipairs({ "Core/Safety.lua", "Core/CombatGate.lua", "Core/Registry.lua", "Adapters/AdapterKit.lua",
    "Adapters/OwnedMicroBarLayout.lua", "Adapters/OwnedMicroBarVisibility.lua",
    "Adapters/OwnedMicroBarEditMode.lua" }) do
    Load(file)
end
local gateFrame = createdFrames[1]
local firstBarFrame = #createdFrames + 1
Load("Adapters/OwnedMicroBar.lua")
local barEvents = createdFrames[firstBarFrame]
Load("Adapters/MicroMenuStates.lua")
Load("Adapters/MicroMenu.lua")
local Owned, Skin, Gate = NS.OwnedMicroBar, NS.MicroMenuSkin, NS.CombatGate
local REAPPLY_KEY = "micro-menu:owned-reapply"

local function Total(applies)
    local total = 0
    for _, count in pairs(applies) do total = total + count end
    return total
end
local bar, mover
local function Reset()
    ResetCounts()
    menu.points = 0
    if bar then bar.points = 0 end
    for button in pairs(stateApplies) do stateApplies[button] = nil end
    for button in pairs(fullApplies) do fullApplies[button] = nil end
end
local function Fire(frame, event)
    if frame.events[event] then frame.scripts.OnEvent(frame, event) end
end
-- PLAYER_REGEN_ENABLED reaches both frames; gateFirst picks the order.
local function EndCombat(gateFirst)
    locked = false
    if gateFirst then Fire(gateFrame, "PLAYER_REGEN_ENABLED") end
    Fire(barEvents, "PLAYER_REGEN_ENABLED")
    if not gateFirst then Fire(gateFrame, "PLAYER_REGEN_ENABLED") end
end
local function StartCombat()
    Fire(barEvents, "PLAYER_REGEN_DISABLED")
    locked = true
end

Skin.Apply(menu, "combat-end-contract")
bar, mover = Owned.GetFrames()
Check(menu.parent == bar and Owned.active and mover.shown, "the owned bar did not take the menu with its mover")
Check(NS.OwnedMicroBar.GetRoot() == menu, "the owned bar does not hold the menu")
Check(counts.portrait == 1, "the initial owned shell did not seed its portrait")

-- Lifecycle storms wait for one flush; input feedback stays synchronous.
-- 2026-10-25 raid trace: three full walks must become one paint per button.
if not portraitOnly then
    Reset()
    for _ = 1, 3 do
        for _, button in ipairs(buttons) do button:SetNormal() end
    end
    Check(Total(stateApplies) == 0, "lifecycle burst painted before its flush")
    Check(#nextFrame == 1, "lifecycle burst scheduled more than one flush")
    -- SetNormal showed the highlight again; the clean style hides it at once.
    Check(buttons[1].textures.Highlight.alpha == 0 and buttons[2].textures.Highlight.alpha == 0,
        "a lifecycle call left the clean highlight visible until its flush")
    Reset()
    RunNextFrame()
    Check(stateApplies[buttons[1]] == 1 and stateApplies[buttons[2]] == 1,
        "lifecycle burst did not paint each button exactly once")
    Check(counts.protection == #buttons, "a lifecycle flush repeated native protection checks")

    -- Blizzard icon styles keep Blizzard's own highlight.
    settings.iconStyle = "blizzard"
    Skin.RefreshActive()
    buttons[1]:SetNormal()
    Check(buttons[1].textures.Highlight.alpha == 1, "a lifecycle call faded a Blizzard-style highlight")
    RunNextFrame()
    settings.iconStyle = "bold"
    Skin.RefreshActive()

    -- Repeated requests reuse the pending set and the single scheduled callback.
    Reset()
    buttons[1]:SetNormal()
    collectgarbage("collect")
    collectgarbage("stop")
    local memoryBefore = collectgarbage("count")
    for _ = 1, 50 do buttons[1]:SetNormal() end
    local allocated = collectgarbage("count") - memoryBefore
    collectgarbage("restart")
    Check(allocated < 1 and #nextFrame == 1,
        ("repeated lifecycle requests allocated %.1f KB or scheduled extra callbacks"):format(allocated))
    RunNextFrame()
    Check(stateApplies[buttons[1]] == 1, "repeated lifecycle requests escaped their single flush")

    for _, script in ipairs({ "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnClick" }) do
        Reset()
        buttons[1]:SetPushed()
        if script == "OnMouseUp" or script == "OnLeave" or script == "OnEnter" then buttons[1]:SetNormal() end
        buttons[1].mouseOver = script == "OnEnter"
        buttons[1].scripts[script](buttons[1])
        Check(stateApplies[buttons[1]] == 1, script .. " delayed input feedback")
        local state = buttons[1].buttonState == "PUSHED" and "pressed"
            or (buttons[1].mouseOver and "hover" or "normal")
        Check(paintedStates[buttons[1]] == state, script .. " painted stale input state")
        RunNextFrame()
        Check(stateApplies[buttons[1]] == 1, script .. " left a duplicate lifecycle repaint")
    end
    buttons[1].mouseOver = false

    -- The last lifecycle state wins, including disabled feedback.
    Reset()
    buttons[1]:SetPushed()
    buttons[1]:SetNormal()
    buttons[1].enabled = false
    buttons[1]:OnDisable()
    RunNextFrame()
    Check(stateApplies[buttons[1]] == 1 and paintedStates[buttons[1]] == "disabled",
        "lifecycle flush did not use the final disabled state")
    buttons[1].enabled = true
    buttons[1]:OnEnable()
    RunNextFrame()

    -- A full pass consumes pending work; disable cannot resurrect its old skin.
    buttons[1]:SetNormal()
    Skin.RefreshActive()
    Reset()
    RunNextFrame()
    Check(Total(stateApplies) == 0, "a full pass left a duplicate lifecycle repaint")
    buttons[1]:SetNormal()
    Skin.Disable()
    Reset()
    RunNextFrame()
    Check(Total(stateApplies) == 0 and Total(fullApplies) == 0,
        "a queued lifecycle flush repainted after disable")
    Skin.Apply(menu, "combat-end-contract")

    -- A queued lifecycle burst meeting combat retains its repaint obligation.
    buttons[1]:SetNormal()
    StartCombat()
    Reset()
    RunNextFrame()
    Check(Total(stateApplies) == 0, "a queued lifecycle flush repainted in combat")
    EndCombat()
    Check(stateApplies[buttons[1]] == 1 and not stateApplies[buttons[2]],
        "a lifecycle burst meeting combat lost its stale button")

    -- Combat replay can consume the button before its older timer gets to run.
    buttons[1]:SetNormal()
    StartCombat()
    buttons[1]:SetPushed()
    Reset()
    EndCombat()
    RunNextFrame()
    Check(stateApplies[buttons[1]] == 1, "combat replay left a duplicate pending lifecycle repaint")
end

-- CanControl is checked once for a whole button, not per faded region.
buttons[1].Background:SetAlpha(1)
buttons[1]:SetNormal()
Reset()
RunNextFrame()
Check(stateApplies[buttons[1]] == 1 and buttons[1].Background.alpha == 0,
    "a state hook did not repaint its button")
Check(counts.protection == 1, "a state hook checked CanControl " .. tostring(counts.protection)
    .. " times for one button (once per faded region)")

------------------------------------------------------------------ nothing deferred
StartCombat()
Check(not mover.shown, "combat start left the mover on screen")
Reset()
buttons[1]:SetPushed()
Fire(barEvents, "UNIT_PORTRAIT_UPDATE")
Fire(barEvents, "UNIT_PORTRAIT_UPDATE")
Check(Total(stateApplies) == 0 and Total(fullApplies) == 0, "a state hook repainted in combat")
Check(not Gate.IsPending(REAPPLY_KEY), "a state hook in combat deferred the bar's full pass")
EndCombat()
Check(not counts.grid and bar.points == 0 and menu.points == 0,
    "combat end with nothing deferred placed the owned bar again")
Check(not counts.prepare and Total(fullApplies) == 0, "combat end with nothing deferred re-skinned the bar")
Check(stateApplies[buttons[1]] == 1 and not stateApplies[buttons[2]],
    "combat end did not repaint exactly the button whose state hook fired in combat")
Check(mover.shown, "combat end did not bring the unlocked mover back")
Check(counts.portrait == 1, "combat end did not refresh the portrait an in-combat update skipped")

-- A quiet fight repaints nothing; a second combat end has no stale buttons.
StartCombat()
Reset()
EndCombat()
Check(Total(stateApplies) == 0 and not counts.grid, "a quiet fight repainted or placed the bar")
Check(not counts.portrait, "quiet combat end resolved an unchanged portrait")
Fire(barEvents, "PLAYER_REGEN_ENABLED")
Check(not counts.portrait, "a repeated combat end resolved an unchanged portrait")
Fire(barEvents, "UNIT_PORTRAIT_UPDATE")
Check(counts.portrait == 1, "an out-of-combat portrait update was delayed")
Reset()
Fire(barEvents, "PLAYER_REGEN_ENABLED")
Check(not counts.portrait, "an immediate portrait update stayed dirty")
-- PORTRAITS_UPDATED (every portrait invalidated, no unit) follows the same rule.
StartCombat()
Fire(barEvents, "PORTRAITS_UPDATED")
Check(not Gate.IsPending(REAPPLY_KEY), "a PORTRAITS_UPDATED in combat deferred the bar's full pass")
Reset()
EndCombat()
Check(counts.portrait == 1, "combat end did not refresh the portrait a PORTRAITS_UPDATED in combat invalidated")
Reset()
Fire(barEvents, "PORTRAITS_UPDATED")
Check(counts.portrait == 1, "an out-of-combat PORTRAITS_UPDATED was delayed")

-- A button Blizzard hid in combat: the owned grid is placed again once.
StartCombat()
buttons[2].shown = false
container:Layout()
Reset()
EndCombat()
Check(counts.grid == 1 and Total(stateApplies) == 0 and bar.points == 0,
    "a button hidden in combat did not get exactly the owned grid placed again")
buttons[2].shown = true
container:Layout()
RunNextFrame()
Check(counts.grid == 2, "showing the button again did not place the owned grid")

-- A button hidden just before combat: its check, queued for the next frame,
-- meets combat and keeps its obligation; combat end places the grid once.
buttons[2].shown = false
container:Layout()
StartCombat()
Reset()
RunNextFrame()
Check(not counts.grid, "a queued layout check placed the owned grid in combat")
EndCombat()
Check(counts.grid == 1, "a layout check that met combat placed the owned grid "
    .. tostring(counts.grid or 0) .. " times at combat end, not once")
buttons[2].shown = true
container:Layout()
RunNextFrame()

------------------------------------------------------------------ Reapply deferred
-- MicroMenu:Layout in combat defers the full pass: combat end keeps it, in
-- either order of the two PLAYER_REGEN_ENABLED handlers.
for _, gateFirst in ipairs({ false, true }) do
    local order = gateFirst and "drain first" or "bar first"
    StartCombat()
    menu:Layout()
    buttons[2]:SetPushed()
    Check(Gate.IsPending(REAPPLY_KEY), "a native layout pass in combat did not defer the bar's full pass")
    Reset()
    EndCombat(gateFirst)
    Check(not Gate.IsPending(REAPPLY_KEY), order .. ": the deferred full pass is still pending")
    Check((counts.grid or 0) >= 1 and bar.points >= 1 and menu.points >= 1,
        order .. ": a deferred full pass did not place the owned bar again")
    Check((stateApplies[buttons[1]] or 0) >= 1 and (stateApplies[buttons[2]] or 0) >= 1,
        order .. ": a deferred full pass did not repaint every button")
    Check(mover.shown, order .. ": a deferred full pass did not bring the mover back")
end
-- The deferred full pass runs once, from the drain; the bar's handler does
-- not ask for it again.
for _, gateFirst in ipairs({ false, true }) do
    StartCombat()
    menu:Layout()
    Reset()
    EndCombat(gateFirst)
    Check(counts.grid == 1, "combat end placed the owned grid " .. tostring(counts.grid)
        .. " times, not once" .. (gateFirst and " (drain first)" or " (bar first)"))
end

-- The drain keeps its frame budget (4 ms) around the deferred full pass: an
-- expensive job asked for before it uses up the frame, and the full pass
-- and a trailing job run once each on the next frame, with everything the
-- light path would restore (stale button, portrait, mover).
for _, gateFirst in ipairs({ false, true }) do
    local order = gateFirst and "drain first" or "bar first"
    local expensive, trailing = 0, 0
    StartCombat()
    Gate.RunOrDefer("contract:expensive", function() expensive = expensive + 1; clock = clock + 5 end)
    Fire(barEvents, "UNIT_PORTRAIT_UPDATE")
    menu:Layout()
    buttons[1]:SetPushed()
    Gate.RunOrDefer("contract:trailing", function() trailing = trailing + 1 end)
    Reset()
    EndCombat(gateFirst)
    Check(expensive == 1 and not counts.grid and trailing == 0 and Gate.IsPending(REAPPLY_KEY),
        order .. ": combat end ran the deferred full pass past the drain budget")
    RunNextFrame()
    Check(counts.grid == 1 and trailing == 1 and expensive == 1 and Gate.GetPendingCount() == 0,
        order .. ": the drain did not run the full pass and the trailing job exactly once")
    Check(mover.shown and counts.portrait == 1 and (stateApplies[buttons[1]] or 0) >= 1,
        order .. ": the drained full pass lost the mover, the portrait or a stale button")
    RunNextFrame()
    Check(counts.grid == 1, order .. ": the deferred full pass ran again")
end

------------------------------------------------------------------ menu held by Blizzard
-- A vehicle took the menu before combat: combat end runs the full skin pass
-- as before (it keeps the native art while Blizzard holds the menu).
local vehicle = Widget("OverrideActionBar", UIParent)
menu:OverrideMicroMenuPosition(vehicle)
Check(Owned.suspended and menu.parent == vehicle, "the owned bar did not yield to a vehicle")
StartCombat()
Reset()
EndCombat()
Check(counts.prepare == #buttons and counts.restore == #buttons,
    "combat end in a vehicle did not run the full skin pass")
menu:ResetMicroMenuPosition()
Check(menu.parent == bar and not Owned.suspended, "the owned bar did not take the menu back after the vehicle")
-- A menu the bar no longer holds, whoever moved it, takes the full pass too.
menu.parent = UIParent
StartCombat()
Reset()
EndCombat()
Check(menu.parent == bar and counts.prepare == #buttons,
    "combat end left a menu the bar no longer holds where it was")

Skin.Disable()
Check(not Owned.active and menu.parent == container, "disable did not hand the menu back")

------------------------------------------------------------------ overlay paint memo
-- Real MicroMenuPerformance and MicroMenuVisual: a state-only repaint with
-- the same inputs keeps the overlay paint and re-checks only the native
-- state masks and the performance bar.
local overlayWrites = 0
local function Quiet()
    local region = Widget()
    for _, method in ipairs({ "ClearAllPoints", "SetPoint", "SetSize", "SetVertexColor", "SetGradient",
        "SetDesaturated", "SetShown", "SetTexture", "ClearTextureSlice", "SetTextureSliceMargins",
        "SetTextureSliceMode" }) do
        region[method] = function() overlayWrites = overlayWrites + 1 end
    end
    region.SetShown = function(self, shown) overlayWrites = overlayWrites + 1; self.shown = shown == true end
    region.Hide = function(self) self.shown = false end
    return region
end
local iconColors, shapes = 0, 0
local VNS = {
    path = "Interface\\AddOns\\MSUF_Suite_Skin\\",
    IsCombatLocked = function() return false end,
    Clamp = NS.Clamp,
    DB = { theme = { gradient = false } },
    Geometry = {
        ConfigureShape = function() shapes = shapes + 1 end,
        Resolve = function(_, result)
            result = result or {}
            result.fill, result.edge, result.hoverEdge = "fill", "edge", "hoverEdge"
            return result
        end,
    },
    Theme = {
        GetColor = function() return 1, 1, 1, 1 end,
        ReuseColor = function(color) return color or {} end,
        GetColorTable = function() return { 1, 1, 1, 1 } end,
        GetMaterialOpacity = function() return 1 end,
        GetMaterial = function() return { from = "a", to = "b", border = "c" } end,
        GetBorderOpacity = function() return 1 end,
    },
    MicroMenuSkin = { GetIconColor = function()
        iconColors = iconColors + 1
        return 1, 1, 1, 1
    end },
}
for _, file in ipairs({ "Core/Safety.lua", "Core/Registry.lua", "Rendering/MicroMenuPerformance.lua",
    "Rendering/MicroMenuVisual.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", VNS)
end
local Visual = VNS.MicroMenuVisual

local button = Widget("MainMenuMicroButton")
function button:CreateTexture() return Quiet() end
local masks = {}
function button:CreateMaskTexture()
    local mask = Widget()
    masks[#masks + 1] = mask
    return mask
end
local function StateTexture()
    local texture = Widget()
    texture.masks = {}
    function texture:AddMaskTexture(mask) self.masks[mask] = true end
    function texture:RemoveMaskTexture(mask) self.masks[mask] = nil end
    return texture
end
local native = { Normal = StateTexture(), Highlight = StateTexture(), Pushed = StateTexture(),
    Disabled = StateTexture() }
for state in pairs(native) do
    button["Get" .. state .. "Texture"] = function() return native[state] end
end
-- Blizzard's latency bar on the game menu button, borrowed by the overlay.
local perfBar = Widget()
local perfReads = 0
function perfBar:GetNumPoints() perfReads = perfReads + 1; return 1 end
function perfBar:GetPoint() return "CENTER", button, "CENTER", 0, 0 end
function perfBar:GetVertexColor() return 0.2, 0.9, 0.2, 1 end
function perfBar:GetTexCoord() return 0, 1, 0, 1 end
function perfBar:GetDrawLayer() return "ARTWORK", 0 end
function perfBar:GetTexture() return "bar" end
button.MainMenuBarPerformanceBar = perfBar

local look = { iconStyle = "bold", hoverStyle = "outline", buttonBackground = true, buttonBorder = 1,
    buttonSize = 28, iconSize = 18, radius = 6, barMaterial = "modern", tint = "native" }
local function Paint(stateName, stateOnly, values)
    overlayWrites, iconColors, shapes, perfReads = 0, 0, 0, 0
    return Visual.Apply(button, "MainMenuMicroButton", values or look, stateName, stateOnly)
end
local function Repainted() return overlayWrites > 0 and iconColors == 1 and shapes > 0 end
local function Kept() return overlayWrites == 0 and iconColors == 0 and shapes == 0 end

Check(Paint("normal") and Repainted(), "the first overlay paint did not paint")
Check(Paint("normal", true) and Kept(), "a state hook with unchanged inputs repainted the overlay")
Check(perfReads > 0, "a kept overlay paint stopped re-checking the borrowed performance bar")
-- SetHighlightAtlas may hand the button a new highlight texture: its mask follows.
local oldHighlight = native.Highlight
native.Highlight = StateTexture()
Paint("normal", true)
Check(Kept() and next(native.Highlight.masks) ~= nil and next(oldHighlight.masks) == nil,
    "a kept overlay paint did not move the native state mask to the new highlight texture")
Check(Paint("pushed", true) and Repainted(), "a changed button state kept the old overlay paint")
Check(Paint("pressed", true) and Kept(), "pushed and pressed are one visual state")
Check(Paint("pressed") and Repainted(), "a full pass kept the overlay paint")
look.buttonSize = 24
Check(Paint("pressed", true) and Repainted(), "a changed button size kept the old overlay paint")
look.tint = "monochrome"
Check(Paint("pressed", true) and Repainted(), "a changed icon tint kept the old overlay paint")
VNS.Registry.NotifyListeners("color", "microIcon")
Check(Paint("pressed", true) and Repainted(), "a theme colour change kept the old overlay paint")
local profile = {}
for key, value in pairs(look) do profile[key] = value end
Check(Paint("pressed", true, profile) and Repainted(), "another profile's settings kept the old overlay paint")
Check(Paint("pressed", true, profile) and Kept(), "an unchanged profile repainted the overlay")
local icon = Visual.GetState(button).icon
Visual.Restore(button)
Check(not icon.shown, "restore left the overlay icon on screen")
Check(Paint("pressed", true, profile) and Repainted() and icon.shown,
    "a state hook after a restore kept the hidden overlay")
-- (false: these stand-ins answer every other capitalised key with a method)
button.MainMenuBarPerformanceBar = false
Check(Paint("pressed", true, profile) and Repainted(), "losing the performance bar kept the old glyph layout")

-- State hooks with a kept paint allocate nothing.
button.MainMenuBarPerformanceBar = perfBar
Paint("normal", true, profile)
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 50 do Paint("normal", true, profile) end
local grown = collectgarbage("count") - before
collectgarbage("restart")
Check(grown < 1, ("kept overlay paints allocated %.1f KB"):format(grown))

print("Suite skin Micro Bar combat end: " .. checks .. " checks passed")
