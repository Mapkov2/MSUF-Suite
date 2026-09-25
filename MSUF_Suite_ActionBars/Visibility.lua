local _, P = ...
local NS, S = P.NS, P.Suite
-- Bar visibility. Each header owns one "vis" state driver (show / hide /
-- fade); the restricted VIS snippet shows or hides the header, also in
-- combat. "fade" keeps the header shown and lets Lua pick the alpha from
-- hover state (alpha writes are allowed in combat, no cursor polling).
-- Implicit prefixes mirror Blizzard: pet battles hide every bar; vehicles
-- with a vehicle UI hide bars 1-11, where Blizzard's OverrideActionBar owns
-- the screen (ActionBarController hides the main bar, stance bar and all
-- multibars then). Override bars keep bar 1 visible on the override page,
-- because a macro condition cannot tell a skinned override bar from the
-- plain one Blizzard shows on the main bar.
local AB = P.ActionBars
local M = AB.M
local MODES = { "show", "[combat] show; hide", "[combat] hide; show", "fade", "[combat] show; fade", "hide" }
local PLACEABLE = { spell = true, item = true, macro = true, mount = true, companion = true, flyout = true, equipmentset = true,
    battlepet = true, petaction = true, outfit = true, toy = true }
-- Reveal bits: 2 = drag seen by Lua (out of combat), 4 = secure drag from a
-- suite button, 8 = placement preview. Bit 1 is never a reveal.
local REVEAL = {}
for _, bit in ipairs({ 2, 4, 8 }) do
    REVEAL[bit] = {
        [true] = 'self:RunAttribute("msuf-reveal",' .. bit .. ',true)',
        [false] = 'self:RunAttribute("msuf-reveal",' .. bit .. ',false)',
    }
end

local function HasForms()
    local forms = type(GetNumShapeshiftForms) == "function" and GetNumShapeshiftForms() or 0
    return S.Public(forms) and type(forms) == "number" and forms > 0
end
AB.HasForms = HasForms

-- Driver string for one bar and visibility mode (catalog choice index).
function AB.VisibilityDriver(index, mode, forms)
    if mode == 6 then return "hide" end
    local body = MODES[mode] or "show"
    if index == 11 then
        if not forms then return "hide" end
        return "[petbattle][vehicleui][possessbar] hide; " .. body
    elseif index == 12 then
        return "[petbattle][nopet] hide; " .. body
    end
    return "[petbattle][vehicleui] hide; " .. body
end

function AB.Reveal(bit, on)
    return AB.grid and AB.Execute(AB.grid, REVEAL[bit][on and true or false])
end

local function AnyHover()
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar and bar.hover and bar.header:GetAttribute("state-vis") == "fade" then return true end
    end
    return false
end

-- Alpha for one bar: bar opacity when shown; the fade opacity while a
-- mouseover bar is neither hovered nor revealed.
function AB.UpdateAlpha(bar)
    local config, keys = M.config, bar.key
    local alpha = config[keys.Alpha] / 100
    if bar.header:GetAttribute("state-vis") == "fade" and not (S.editMode or AB.dragging or bar.hover
        or (config.mouseoverShowAll and AnyHover())) then
        -- Zero-alpha secure frames do not reliably take hover in Forever.
        -- One percent stays visually hidden but leaves a hit target.
        alpha = math.max(0.01, config[keys.FadeAlpha] / 100)
    end
    if bar.alpha ~= alpha then
        bar.alpha = alpha
        bar.header:SetAlpha(alpha)
    end
end

function AB.UpdateAllAlpha()
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar then AB.UpdateAlpha(bar) end
    end
end

local function FlyoutOpen(bar)
    local flyout = _G.SpellFlyout
    if not flyout or not flyout:IsShown() then return false end
    local parent = flyout:GetParent()
    local rec = parent and AB.records[parent]
    return rec ~= nil and rec.bar == bar and flyout:IsMouseOver()
end

local function SetHover(bar, on)
    if bar.hover == on then return end
    bar.hover = on
    if M.config.mouseoverShowAll then
        AB.UpdateAllAlpha()
    else
        AB.UpdateAlpha(bar)
    end
end

-- Insecure post-hooks on suite headers and on every bar button (including
-- the adopted Blizzard ones); they only change alpha and tooltips.
local function Enter(frame)
    if not M.active then return end
    local rec = AB.records[frame]
    local bar = rec and rec.bar or AB.headers[frame]
    if not bar then return end
    SetHover(bar, true)
    if rec and rec.owned and not rec.native then AB.ShowTooltip(rec) end
end
local function Leave(frame)
    if not M.active then return end
    local rec = AB.records[frame]
    local bar = rec and rec.bar or AB.headers[frame]
    if not bar then return end
    if rec and rec.owned and not rec.native and GameTooltip and GameTooltip:GetOwner() == frame then GameTooltip:Hide() end
    SetHover(bar, bar.header:IsMouseOver() or FlyoutOpen(bar))
end
function AB.HookHover(frame)
    AB.hovered = AB.hovered or {}
    if AB.hovered[frame] then return end
    AB.hovered[frame] = true
    frame:HookScript("OnEnter", Enter)
    frame:HookScript("OnLeave", Leave)
end

local function SetForced(bar, name, value)
    value = value or nil
    if bar.header:GetAttribute(name) == value then return false end
    bar.header:SetAttribute(name, value)
    return true
end

-- Drag reveal: empty slots appear (bit 2) and, with showOnDrag, hidden bars
-- show while something placeable is on the cursor. Out of combat only;
-- combat drags from suite buttons use the secure bit 4 instead.
function AB.ApplyDrag()
    local dragging = false
    if type(GetCursorInfo) == "function" then
        local kind = GetCursorInfo()
        dragging = S.Public(kind) and PLACEABLE[kind] or false
    end
    AB.dragging = dragging
    AB.UpdateAllAlpha()
    if NS.IsCombatLocked() then
        AB.dragPending = true
        return
    end
    AB.dragPending = nil
    AB.Reveal(2, dragging)
    if not dragging then AB.Reveal(4, false) end
    local show = dragging and M.config.showOnDrag
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar and SetForced(bar, "dragshow", show and AB.Available(index)) then AB.Execute(bar.header, AB.SNIPPET.VIS) end
    end
end

-- Bag sorting storms showgrid/hidegrid; a 50 ms settle absorbs them.
local function Settle()
    AB.settling = nil
    if M.active then AB.ApplyDrag() end
end
function AB.CursorChanged()
    if AB.settling or not C_Timer then return end
    AB.settling = true
    C_Timer.After(0.05, Settle)
end

-- Driver, preview forcing and header mouse motion of one bar. A driver is
-- re-registered only when its string changes (re-registering blinks the bar).
local function ApplyBarVisibility(bar, config, forms)
    local keys = bar.key
    local mode = config[keys.Visibility]
    local driver = AB.VisibilityDriver(bar.index, mode, forms)
    local forced = SetForced(bar, "forceshow", S.editMode and mode ~= 6)
    if bar.visDriver ~= driver then
        bar.visDriver = driver
        RegisterStateDriver(bar.header, "vis", driver)
    end
    -- The driver only re-runs the handler when its state changes.
    if forced then AB.Execute(bar.header, AB.SNIPPET.VIS) end
    local fade = mode == 4 or mode == 5
    -- EnableMouseMotion alone leaves the header non-interactive on
    -- Forever. Buttons continue to receive their own clicks.
    bar.header:EnableMouse(fade and not config[keys.ClickThrough])
    if bar.header.EnableMouseMotion then bar.header:EnableMouseMotion(fade) end
    AB.HookHover(bar.header)
    for i = 1, #bar.buttons do AB.HookHover(bar.buttons[i].button) end
    if not fade then bar.hover = nil end
    AB.UpdateAlpha(bar)
end

-- Applies visibility to the bars in the set `only` (nil: every bar, plus
-- the placement preview reveal).
function AB.ApplyVisibility(only)
    if NS.IsCombatLocked() then return end
    local config, forms = M.config, HasForms()
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar and (not only or only[bar]) then ApplyBarVisibility(bar, config, forms) end
    end
    if not only then AB.Reveal(8, S.editMode == true) end
end

function AB.StopVisibility()
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar then
            if bar.visDriver then
                UnregisterStateDriver(bar.header, "vis")
                bar.visDriver = nil
            end
            SetForced(bar, "forceshow", nil)
            SetForced(bar, "dragshow", nil)
            bar.header:SetAttribute("state-vis", "hide")
            AB.Execute(bar.header, AB.SNIPPET.VIS)
            bar.hover = nil
        end
    end
    AB.dragging, AB.dragPending = nil, nil
end
