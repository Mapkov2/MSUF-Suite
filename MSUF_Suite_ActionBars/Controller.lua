local _, P = ...
local NS, S = P.NS, P.Suite
-- Lifecycle, first-enable import, per-setting refresh work, Edit Mode
-- movers. The controller calls Enable/Refresh/Disable out of combat only;
-- runtime events do run in combat and never touch protected state there.
local AB = P.ActionBars
local M = AB.M
local Public = S.Public
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
AB.RELOAD_MESSAGE = "Reload the UI to restore Blizzard's action bars"

local Finite = S.Finite

-- Position (as a CENTER offset) and grid of a shown Blizzard bar.
local function ImportGeometry(values, index, frame)
    local keys = AB.KEYS[index]
    local x, y = frame:GetCenter()
    local scale, root = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not (Finite(x) and Finite(y) and Finite(scale) and Finite(root) and root > 0
        and Finite(width) and Finite(height)) then return end
    values[keys.Point] = 5
    values[keys.X] = floor((x * scale / root - width / 2) * 10 + .5) / 10
    values[keys.Y] = floor((y * scale / root - height / 2) * 10 + .5) / 10
    if index > 8 then return end
    local rows, shown, horizontal = frame.numRows, frame.numButtonsShowable, frame.isHorizontal
    if Finite(rows) and Finite(shown) and Public(horizontal) and type(horizontal) == "boolean" then
        shown, rows = min(max(floor(shown), 1), 12), min(max(floor(rows), 1), 12)
        values[keys.Buttons] = shown
        values[keys.Vertical] = not horizontal
        -- Blizzard counts columns for vertical bars; the suite counts rows.
        values[keys.Rows] = horizontal and rows or ceil(shown / rows)
    end
    local padding = frame.buttonPadding
    if Finite(padding) then values[keys.Spacing] = min(max(floor(padding + .5), -10), 20) end
end

-- Import Blizzard positions and grids without copying visibility. The suite's
-- first-enable mouseover defaults must apply even to hidden Blizzard bars.
function AB.BuildImport(state)
    local values = { imported = true }
    for index = 1, 12 do
        local entry = state[index]
        local frame = entry and entry.frame
        if entry and AB.Available(index) then
            local shown = frame ~= nil and frame:IsShown() == true
            if index >= 2 and index <= 8 and entry.toggle ~= nil then
                shown = entry.toggle == true
            end
            if frame and shown then ImportGeometry(values, index, frame) end
        end
    end
    return values
end

-- Settings are written after the current apply finished (S.SetMany re-runs
-- Refresh); a combat start in between retries on the next refresh.
local function QueueImport(values)
    AB.importQueued = true
    local function Write()
        if not M.active or M.config.imported then return end
        if not S.SetMany("actionbars", values) then AB.importQueued = nil end
    end
    if C_Timer then
        C_Timer.After(0, Write)
    else
        Write()
    end
end

------------------------------------------------------------------ settings work
-- Refresh runs on every setting change, slider ticks included. It compares
-- each setting with the value the bars were last built with and runs only
-- the work that setting needs.
-- Global work:
--  style    rebuild the look, restyle every button     curves  cooldown curves
--  events   optional listeners (range, proc glows)     native  Blizzard's reused buttons
--  repaint  every suite button (range checks, glows)   paging  bar 1 driver and key routing
--  state, count, cooldown, tint   one paint walk       alpha   mouseover opacity
--  drag     drag reveal                                visible every bar's visibility
-- Bar work: layout (geometry, grid, background), style (that bar's buttons),
-- visible (driver, opacity, header mouse), paint (its filled buttons).
local GLOBAL_WORK = {}
local function Global(keys, work)
    for i = 1, #keys do GLOBAL_WORK[keys[i]] = work end
end
Global({ "iconZoom", "borderSize", "borderColor", "borderClassColor", "slotColor", "slotAlpha", "highlightStyle",
    "pushedStyle", "interactionColor", "interactionClassColor", "swipeColor", "swipeAlpha", "cooldownNumbers",
    "rechargeNumbers", "font", "fontOutline", "fontRendering", "fontShadow", "fontShadowOpacity",
    "fontShadowDistance", "keybindColor", "macroColor", "countColor", "cooldownColor" }, { style = true })
Global({ "rangeColor" }, { style = true, tint = true })
Global({ "castHighlight" }, { state = true, native = true })
Global({ "hideEmptyCharges" }, { count = true, native = true })
Global({ "desaturateCooldown", "cooldownAlpha" }, { curves = true, cooldown = true, native = true })
Global({ "rangeColoring" }, { events = true, repaint = true, native = true })
Global({ "procGlow" }, { style = true, events = true, repaint = true, native = true })
Global({ "mouseoverShowAll" }, { alpha = true })
Global({ "showOnDrag" }, { drag = true })
Global({ "disableFormPaging", "disableSkyridingPaging", "pagingModifiers", "pageShift", "pageCtrl", "pageAlt" },
    { paging = true })

local BAR_WORK = {
    Buttons = { layout = true, paint = true },
    Size = { layout = true, style = true },
    ClickThrough = { layout = true, visible = true },
    Visibility = { visible = true },
    Alpha = { visible = true },
    FadeAlpha = { visible = true },
}
for _, suffix in ipairs({ "Rows", "Spacing", "Vertical", "Start", "ShowEmpty", "Point", "X", "Y", "Background",
    "BackgroundColor", "BackgroundAlpha", "BackgroundPadding" }) do
    BAR_WORK[suffix] = { layout = true }
end
for _, suffix in ipairs({ "Keybind", "KeybindSize", "Macro", "MacroSize", "CountSize", "CooldownSize" }) do
    BAR_WORK[suffix] = { style = true }
end

-- Settings without runtime work; any other setting nobody listed above
-- rebuilds everything, so a new setting is never silently ignored.
local NO_WORK = { enabled = true, imported = true, look = true }
local FULL = {
    style = true, curves = true, events = true, native = true, repaint = true, paging = true, alpha = true,
    drag = true, visible = true,
}
local FULL_BAR = { layout = true, style = true, visible = true, paint = true }

-- Every watched setting as parallel arrays: key, work, bar index (0: global).
local WATCH_KEYS, WATCH_WORK, WATCH_BAR = {}, {}, {}
local function Watch(key, work, index)
    local n = #WATCH_KEYS + 1
    WATCH_KEYS[n], WATCH_WORK[n], WATCH_BAR[n] = key, work, index
end
local barKeys = {}
for index = 1, AB.BAR_COUNT do
    for suffix, work in pairs(BAR_WORK) do
        local key = AB.KEYS[index][suffix]
        Watch(key, work, index)
        barKeys[key] = true
    end
    barKeys["bar" .. index .. "ResumeVisibility"] = true
end
for key in pairs(S.catalog.actionbars.rules) do
    if not barKeys[key] and not NO_WORK[key] then Watch(key, GLOBAL_WORK[key] or FULL, 0) end
end

local applied = {}       -- setting -> value the bars were last built with
local work = {}          -- global work of the running refresh
local barWork = {}       -- bar index -> work of the running refresh
for index = 1, AB.BAR_COUNT do barWork[index] = {} end
local rebuild = true     -- the next refresh builds everything (activation)
local appliedUnit, appliedEditMode

local function Merge(into, from)
    for flag in pairs(from) do into[flag] = true end
end

local function Collect(config)
    local all = rebuild
    for i = 1, #WATCH_KEYS do
        local key = WATCH_KEYS[i]
        local value = config[key]
        if all or applied[key] ~= value then
            applied[key] = value
            local index = WATCH_BAR[i]
            Merge(index == 0 and work or barWork[index], WATCH_WORK[i])
        end
    end
    if all then
        Merge(work, FULL)
        for index = 1, AB.BAR_COUNT do Merge(barWork[index], FULL_BAR) end
    end
    -- A new pixel grid moves and restyles every bar.
    local unit = AB.PixelUnit()
    if unit ~= appliedUnit then
        appliedUnit = unit
        for index = 1, AB.BAR_COUNT do
            barWork[index].layout, barWork[index].style = true, true
        end
    end
    -- MSUF Edit Mode forces every bar (except Never) visible at full alpha.
    local editMode = S.editMode == true
    if editMode ~= appliedEditMode then
        appliedEditMode = editMode
        work.visible = true
    end
    -- The stance bar follows the class's forms (FormsChanged in Paint.lua).
    local stance = AB.bars[11]
    if stance and (stance.forms ~= AB.HasForms() or stance.count ~= AB.Count(stance, config)) then
        barWork[11].layout, barWork[11].visible = true, true
    end
end

local function ApplyLayout()
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar and barWork[index].layout then
            if index >= 11 then AB.Adopt(index) end
            AB.LayoutBar(bar)
            if index == 11 then bar.forms = AB.HasForms() end
        end
    end
end

local function ApplyStyle()
    local any = work.style
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar and barWork[index].style then
            bar.styleGen = bar.styleGen + 1
            any = true
        end
    end
    if any then AB.StyleAll(work.style) end
end

-- Paint walks a setting can ask for (Paint.lua dirty kinds).
local PAINT_WALKS = { "state", "count", "cooldown", "tint" }
local visibleBars = {}
local function ApplyVisibilityWork()
    if work.visible then
        AB.ApplyVisibility()
        return
    end
    local any = false
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar and barWork[index].visible then
            visibleBars[bar] = true
            any = true
        end
    end
    if any then AB.ApplyVisibility(visibleBars) end
    for bar in pairs(visibleBars) do visibleBars[bar] = nil end
    if work.alpha then AB.UpdateAllAlpha() end
end

local function ApplyPaint()
    if not AB.dispatching then
        AB.dispatching = true
        AB.StartDispatcher()
        return
    end
    if work.events then AB.SyncOptionalEvents() end
    if work.repaint then
        AB.MarkAll()
        return
    end
    for i = 1, #PAINT_WALKS do
        local kind = PAINT_WALKS[i]
        if work[kind] then AB.Mark(kind) end
    end
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar and barWork[index].paint then AB.MarkBar(bar) end
    end
end

local function ClearWork()
    for flag in pairs(work) do work[flag] = nil end
    for index = 1, AB.BAR_COUNT do
        local set = barWork[index]
        for flag in pairs(set) do set[flag] = nil end
    end
end

function M:Enable()
    AB.ResolveAPI()
    AB.Build()
    local state = not self.config.imported and AB.ReadBlizzard() or nil
    local import = state and AB.BuildImport(state)
    AB.Dispose()
    AB.HookNativePresses()
    S.states.actionbars.reloadRequired = nil
    if import and not AB.importQueued then QueueImport(import) end
    rebuild = true
    self:Refresh()
end

function M:Refresh()
    if NS.IsCombatLocked() then
        S.Queue("actionbars")
        return
    end
    local config = self.config
    if not config.imported and not AB.importQueued then QueueImport(AB.BuildImport(AB.ReadBlizzard())) end
    AB.ReparentLeaveButton()
    Collect(config)
    if work.curves then AB.UpdateCurves() end
    ApplyLayout()
    ApplyStyle()
    if work.native then AB.RefreshNative() end
    if work.paging then AB.ApplyPaging() end
    ApplyVisibilityWork()
    AB.UpdateClickAttributes()
    ApplyPaint()
    if work.paging then AB.UpdateRouting() end
    if work.drag or AB.dragPending then AB.ApplyDrag() end
    ClearWork()
    rebuild = false
end

-- Blizzard's bars cannot be rebuilt at runtime: the suite bars hide, their
-- drivers and override bindings go, and a reload restores Blizzard's bars.
-- A later enable in the same session reuses every frame.
function M:Disable()
    AB.StopDispatcher()
    AB.dispatching = nil
    AB.StopPaging()
    AB.StopVisibility()
    AB.ClearRouting()
    AB.importQueued = nil
    for key in pairs(applied) do applied[key] = nil end
    rebuild, appliedUnit, appliedEditMode = true, nil, nil
    if AB.disposed then S.states.actionbars.reloadRequired = AB.RELOAD_MESSAGE end
end

------------------------------------------------------------------ movers
local function NumberControl(id, key)
    local rule = S.catalog.actionbars.rules[key]
    return {
        id = id, label = S.Text(rule.label), kind = "number", min = rule.min, max = rule.max, step = 1,
        get = function() return S.Config("actionbars")[key] end,
        set = function(value) return S.Set("actionbars", key, value) end,
    }
end

-- A one-column bar stays one column when its button count changes here.
local function ButtonCountControl(keys)
    local control = NumberControl("buttons", keys.Buttons)
    control.set = function(value)
        local config = S.Config("actionbars")
        if config[keys.Rows] >= config[keys.Buttons] then
            return S.SetMany("actionbars", { [keys.Buttons] = value, [keys.Rows] = value })
        end
        return S.Set("actionbars", keys.Buttons, value)
    end
    return control
end

-- The popup exposes one-click row and column layouts. A custom Rows value
-- remains available for grids; neither orientation button is selected then.
local function OrientationControl(keys, vertical)
    return {
        id = vertical and "vertical" or "horizontal",
        label = S.Text(vertical and "Vertical" or "Horizontal"),
        kind = "toggle",
        get = function()
            local config = S.Config("actionbars")
            if config[keys.Buttons] == 1 then return config[keys.Vertical] == vertical end
            return vertical and config[keys.Rows] >= config[keys.Buttons] or not vertical and config[keys.Rows] == 1
        end,
        set = function(on)
            if not on then return false end
            local config = S.Config("actionbars")
            return S.SetMany("actionbars", { [keys.Vertical] = vertical, [keys.Rows] = vertical and config[keys.Buttons] or 1 })
        end,
    }
end

-- Mouseover on/off keeps the combat part of the current mode.
local function MouseoverControl(key)
    return {
        id = "mouseover", label = S.Text("Show on mouseover"), kind = "toggle",
        get = function()
            local mode = S.Config("actionbars")[key]
            return mode == 4 or mode == 5
        end,
        set = function(on)
            local mode = S.Config("actionbars")[key]
            local value
            if on then
                value = (mode == 2 or mode == 5) and 5 or 4
            else
                value = mode == 5 and 2 or mode == 4 and 1 or mode
            end
            return S.Set("actionbars", key, value)
        end,
    }
end

-- One mover spec per bar, built on first use and kept: the controller asks
-- for movers after every refresh.
local movers = {}
local function Mover(index)
    local keys = AB.KEYS[index]
    return {
        label = NS.ActionBarTitles[index],
        getFrame = function()
            local bar = AB.bars[index]
            return bar and bar.header
        end,
        xKey = keys.X, yKey = keys.Y, pointKey = keys.Point,
        point = function() return NS.ActionBarAnchorPoints[S.Config("actionbars")[keys.Point]] or "CENTER" end,
        isEnabled = function()
            return AB.Available(index) and S.Config("actionbars")[keys.Visibility] ~= 6 and (index ~= 11 or AB.HasForms())
        end,
        order = 100 + index,
        extraControls = {
            ButtonCountControl(keys), NumberControl("rows", keys.Rows), NumberControl("size", keys.Size),
            NumberControl("spacing", keys.Spacing), OrientationControl(keys, false), OrientationControl(keys, true),
            MouseoverControl(keys.Visibility),
        },
        historyKeys = { keys.Buttons, keys.Rows, keys.Size, keys.Spacing, keys.Vertical, keys.Visibility },
    }
end

function M:RegisterMovers()
    for index = 1, AB.BAR_COUNT do
        if AB.bars[index] then
            movers[index] = movers[index] or Mover(index)
            S.RegisterOwnedMover("actionbars", "bar" .. index, movers[index])
        end
    end
end
