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
local ENUM = AB.ENUM
local VIS, BAR = ENUM.VISIBILITY, ENUM.BAR
-- The state driver body of each visibility mode.
local MODES = {
    [VIS.ALWAYS] = "show", [VIS.COMBAT] = "[combat] show; hide", [VIS.OUT_OF_COMBAT] = "[combat] hide; show",
    [VIS.MOUSEOVER] = "fade", [VIS.MOUSEOVER_OR_COMBAT] = "[combat] show; fade", [VIS.NEVER] = "hide",
}
local PLACEABLE = { spell = true, item = true, macro = true, mount = true, companion = true, flyout = true, equipmentset = true,
    battlepet = true, petaction = true, outfit = true, toy = true }
-- Reveal bits: 2 = drag seen by Lua (out of combat), 4 = secure drag from a
-- suite button, 8 = placement preview, 16 = spellbook or macro panel open.
-- Bit 1 is never a reveal.
local REVEAL = {}
for _, bit in ipairs({ 2, 4, 8, 16 }) do
    REVEAL[bit] = {
        [true] = 'self:RunAttribute("msuf-reveal",' .. bit .. ',true)',
        [false] = 'self:RunAttribute("msuf-reveal",' .. bit .. ',false)',
    }
end

local function HasForms()
    local forms = GetNumShapeshiftForms()
    return S.Public(forms) and type(forms) == "number" and forms > 0
end
AB.HasForms = HasForms

-- Driver string for one bar and visibility mode (catalog choice index).
-- reveal: the spellbook/macro reveal shows the bar out of combat. It follows
-- the implicit pet battle and vehicle hides; a bar that is hidden outright
-- (Never, the gamepad rule, a stance bar without forms) stays hidden.
function AB.VisibilityDriver(index, mode, forms, gamepad, reveal)
    if gamepad and M.config[AB.KEYS[index].HideGamepad] then return "hide" end
    if mode == VIS.NEVER then return "hide" end
    local body = MODES[mode] or "show"
    if reveal then body = "[nocombat] show; " .. body end
    if index == BAR.STANCE then
        if not forms then return "hide" end
        return "[petbattle][vehicleui][possessbar] hide; " .. body
    elseif index == BAR.PET then
        return "[petbattle][nopet] hide; " .. body
    end
    return "[petbattle][vehicleui] hide; " .. body
end

function AB.AnyGamepadHidden()
    for index = 1, AB.BAR_COUNT do if M.config[AB.KEYS[index].HideGamepad] then return true end end
    return false
end
function AB.GamepadHideActive()
    if not NS.Client.isForever or not AB.AnyGamepadHidden() then return false end
    -- Forever's gamepad interface state (upstream/forever Blizzard_SharedXML/
    -- Mainline/InputUtil.lua); 12.1.0 and 12.1.5 have no IsGamepadUIEnabled.
    local enabled = InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
    if not S.Public(enabled) or enabled ~= true then return false end
    local devices = C_GamePad.GetAllDeviceIDs()
    return S.Public(devices) and type(devices) == "table" and next(devices) ~= nil
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
    local textAlpha = 1
    -- The panel reveal lives in the driver: out of combat it shows instead of
    -- fading, so a fade state never means an open spellbook.
    if bar.header:GetAttribute("state-vis") == "fade" and not (S.editMode or AB.dragging or bar.hover
        or (config.mouseoverShowAll and AnyHover())) then
        local fadeAlpha = config[keys.FadeAlpha] / 100
        textAlpha = fadeAlpha == 0 and 0 or 1
        -- Zero-alpha secure frames do not reliably take hover in Forever.
        -- Keep the hit target, but fully fade the template's separate text
        -- overlay so count updates cannot leave ghost stack/key text.
        alpha = math.max(0.01, fadeAlpha)
    end
    if bar.textAlpha ~= textAlpha then
        bar.textAlpha = textAlpha
        for i = 1, #bar.buttons do
            local overlay = bar.buttons[i].button.TextOverlayContainer
            if overlay then overlay:SetAlpha(textAlpha) end
        end
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
    local flyout = SpellFlyout
    if not flyout:IsShown() then return false end
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
    if rec and rec.owned and not rec.native and GameTooltip:GetOwner() == frame then GameTooltip:Hide() end
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
    if AB.panelPending and not NS.IsCombatLocked() then AB.SyncPanelReveal() end
    local kind = GetCursorInfo()
    local dragging = S.Public(kind) and PLACEABLE[kind] or false
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
    if AB.settling then return end
    AB.settling = true
    C_Timer.After(0.05, Settle)
end

-- Driver, preview forcing and header mouse motion of one bar. A driver is
-- re-registered only when its string changes (re-registering blinks the bar).
local function ApplyBarVisibility(bar, config, forms, gamepad)
    local keys = bar.key
    local mode = config[keys.Visibility]
    local driver = AB.VisibilityDriver(bar.index, mode, forms, gamepad, AB.panelsOpen)
    local forced = SetForced(bar, "forceshow", S.editMode and mode ~= VIS.NEVER)
    if bar.visDriver ~= driver then
        bar.visDriver = driver
        RegisterStateDriver(bar.header, "vis", driver)
    end
    -- The driver only re-runs the handler when its state changes.
    if forced then AB.Execute(bar.header, AB.SNIPPET.VIS) end
    local fade = mode == VIS.MOUSEOVER or mode == VIS.MOUSEOVER_OR_COMBAT
    -- EnableMouseMotion alone leaves the header non-interactive on
    -- Forever. Buttons continue to receive their own clicks.
    bar.header:EnableMouse(fade and not config[keys.ClickThrough])
    bar.header:EnableMouseMotion(fade)
    AB.HookHover(bar.header)
    for i = 1, #bar.buttons do AB.HookHover(bar.buttons[i].button) end
    if not fade then bar.hover = nil end
    AB.UpdateAlpha(bar)
end

-- Applies visibility to the bars in the set `only` (nil: every bar, plus
-- the placement preview reveal).
function AB.ApplyVisibility(only)
    if NS.IsCombatLocked() then return end
    local config, forms, gamepad = M.config, HasForms(), AB.GamepadHideActive()
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar and (not only or only[bar]) then ApplyBarVisibility(bar, config, forms, gamepad) end
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

-- The toggle bindings. Settings are locked in combat, so a toggle pressed
-- there switches the bar when combat ends (pressing it again cancels) and
-- says so in chat. A plain event frame carries the wait: it works whether
-- or not the bars run.
local queuedToggles, toggleFrame = {}, nil
local function SwitchBar(index)
    local values = NS.ActionBarSwitchValues(S.Config("actionbars"), index)
    return values ~= nil and S.SetMany("actionbars", values) == true
end
local function FlushToggles()
    toggleFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    for index in pairs(queuedToggles) do
        queuedToggles[index] = nil
        SwitchBar(index)
    end
end
local function QueueToggle(index)
    local title = S.Text(NS.ActionBarTitles[index])
    if queuedToggles[index] then
        queuedToggles[index] = nil
        S.Print(S.Text("%s stays as it is."):format(title))
        return
    end
    queuedToggles[index] = true
    if not toggleFrame then
        toggleFrame = S.CreateFrame("Frame")
        toggleFrame:SetScript("OnEvent", FlushToggles)
    end
    toggleFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    S.Print(S.Text("%s switches when combat ends."):format(title))
end
function S.ToggleActionBar(index)
    if not AB.Available(index) then return false end
    if NS.IsCombatLocked() then
        QueueToggle(index)
        return false
    end
    return SwitchBar(index)
end

local panelHooks = {}
local function PanelChanged()
    if M.active then AB.SyncPanelReveal() end
end
local function WatchPanel(panel)
    if not panel or NS.Safety.IsForbidden(panel) then return false end
    if not panelHooks[panel] then
        panelHooks[panel] = true
        panel:HookScript("OnShow", PanelChanged)
        panel:HookScript("OnHide", PanelChanged)
    end
    return panel:IsVisible()
end
-- In combat the reveal waits: PLAYER_REGEN_ENABLED flushes it (Events.lua).
function AB.SyncPanelReveal()
    if NS.IsCombatLocked() then
        AB.panelPending = true
        return
    end
    AB.panelPending = nil
    -- Retail and Forever keep the spellbook in Blizzard_PlayerSpells, which
    -- loads on demand.
    local spellbook = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
    local spellbookOpen, macroOpen = WatchPanel(spellbook), WatchPanel(MacroFrame)
    local open = spellbookOpen or macroOpen
    open = M.config.showOnPanels and open or false
    if open == AB.panelsOpen then return end
    AB.panelsOpen = open
    AB.Reveal(16, open)
    AB.ApplyVisibility()
end
