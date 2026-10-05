local _, P = ...
local NS, S = P.NS, P.Suite
-- Key routing. Bars 2-8 keep Blizzard's native command on their adopted
-- buttons. Bar 1 keeps the native command while it follows Blizzard's page.
-- These are the queue-safe routes for empower and press-and-hold spells.
-- One owner frame routes keys to the suite buttons with override click
-- bindings where a native command cannot express the slot: bars 9/10 (their
-- own commands), bar 1 with custom paging or paging opt-outs (Blizzard's
-- page would differ from the icons), and flyout slots (the flyout must open
-- on a visible button). Routing changes only out of combat; unchanged
-- routes skip the rebuild.
local AB = P.ActionBars
local M = AB.M
local Public = S.Public

-- The base action template deliberately omits Blizzard's action-bar painter
-- and Quick Keybind scripts. A temporary input surface supplies only the
-- native binding template, so mouse bindings cannot also cast the action.
-- Blizzard's reused buttons already provide this behavior themselves.
local bindingOverlays = {}
local function BindingHidden(button)
    if button.changedUpdateScript then button:QuickKeybindButtonOnLeave() end
end
function AB.SyncQuickKeybind(open)
    if not open or not M.active or NS.IsCombatLocked() then
        for _, button in pairs(bindingOverlays) do button:Hide() end
        return
    end
    for i = 1, #AB.owned do
        local rec = AB.owned[i]
        if not rec.native then
            local button = bindingOverlays[rec.button]
            if not button then
                button = S.CreateFrame("Button", nil, rec.button, "QuickKeybindButtonTemplate")
                button.commandName = rec.command
                button:SetAllPoints(rec.button)
                button.QuickKeybindHighlightTexture:SetAllPoints(button)
                button:RegisterForClicks("AnyUp")
                button:HookScript("OnHide", BindingHidden)
                bindingOverlays[rec.button] = button
            end
            button:DoModeChange(true)
            button:Show()
        end
    end
end

-- Short key text, shared with the cooldown icons (S.KeyText). No range dot.
function AB.BindingText(rec)
    return S.KeyText((GetBindingKey(rec.command)))
end

-- Key text of the suite button that presses a spell, for the cooldown
-- manager's icons (MSUF_Suite_CooldownManager/Keybinds.lua): the text that
-- button shows. Candidates in key preference: each bar's own page in bar
-- order (bar 1 page 1, bars 2-10 their fixed slots), then bar 1's custom
-- pages (Paging.lua), then the form pages 7-9 bar 1 switches to, pressed by
-- bar 1's keys (page 10, slots 109-120, is bar 10). "" when no candidate has
-- a key; nil while the suite bars are off (Blizzard's bars apply then).
-- current (the cooldown manager's labels follow the page): each button
-- answers for the slot it presses now, and bar 1's target and form pages,
-- which its keys press only at other times, do not count.
local FORM_FIRST, FORM_LAST = 73, 108
local spellSlots = {}

-- Bar 1's custom pages are pressed by bar 1's keys as well: the friendly and
-- hostile target pages with the plain key, a modifier page with the modifier
-- held. A modified key reaches bar 1 only while that combination has no
-- binding of its own, and a key that carries a modifier already is skipped.
local MODIFIER_PAGES = { { "pageShift", "SHIFT-" }, { "pageCtrl", "CTRL-" }, { "pageAlt", "ALT-" } }
local function Modified(key)
    return key:find("^ALT%-.") or key:find("^CTRL%-.") or key:find("^SHIFT%-.") or key:find("^META%-.")
end
local function PageKey(main, page, modifier)
    if page == 1 then return "" end
    local first = (page - 1) * 12
    for i = 1, #main.buttons do
        if spellSlots[first + i] then
            local key = GetBindingKey(main.buttons[i].command)
            if Public(key) and type(key) == "string" and key ~= "" then
                if not modifier then return S.KeyText(key) end
                if not Modified(key) then
                    local action = GetBindingAction(modifier .. key, true)
                    if Public(action) and action == "" then return S.KeyText(modifier .. key) end
                end
            end
        end
    end
    return ""
end
local function CustomPagesKey(main, config, current)
    local text = ""
    if config.pagingTarget and not current then
        text = PageKey(main, config.pageFriendly)
        if text == "" then text = PageKey(main, config.pageHostile) end
    end
    if text == "" and config.pagingModifiers then
        for i = 1, #MODIFIER_PAGES do
            text = PageKey(main, config[MODIFIER_PAGES[i][1]], MODIFIER_PAGES[i][2])
            if text ~= "" then break end
        end
    end
    return text
end
function S.ActionBarsBindingForSpell(spell, current)
    if not M.active then return nil end
    local slots = spell and C_ActionBar.FindSpellActionButtons(spell)
    if not (Public(slots) and type(slots) == "table") then return "" end
    for slot in pairs(spellSlots) do spellSlots[slot] = nil end
    for i = 1, #slots do
        local slot = slots[i]
        if Public(slot) and type(slot) == "number" then spellSlots[slot] = true end
    end
    for index = 1, 10 do
        local bar = AB.bars[index]
        if bar then
            for i = 1, #bar.buttons do
                local rec = bar.buttons[i]
                if spellSlots[current and rec.slot or rec.base] then
                    local text = AB.BindingText(rec)
                    if text ~= "" then return text end
                end
            end
        end
    end
    local main = AB.bars[1]
    if main then
        local text = CustomPagesKey(main, M.config, current)
        if text ~= "" then return text end
    end
    if main and not current and not M.config.disableFormPaging then
        for slot = FORM_FIRST, FORM_LAST do
            if spellSlots[slot] then
                local text = AB.BindingText(main.buttons[(slot - FORM_FIRST) % 12 + 1])
                if text ~= "" then return text end
            end
        end
    end
    return ""
end

-- Cold integration seam for separately owned native aura decorations. Callers
-- own their overlays; button identity stays owned by ActionBars. No state from
-- an aura or restricted spell is exposed through this visitor.
function S.ForEachActionBarButtonForSpell(spellID, callback, context)
    if not M.active or NS.IsCombatLocked() or not S.Finite(spellID) or spellID <= 0
        or type(callback) ~= "function" then return 0 end
    local count = 0
    for _, rec in pairs(AB.records) do
        if rec.slot and AB.Painter.ActionSpell(rec.slot) == spellID then
            callback(rec.button, context)
            count = count + 1
        end
    end
    return count
end

local function IsFlyout(slot)
    if not slot then return false end
    local kind = GetActionInfo(slot)
    return Public(kind) and kind == "flyout"
end
AB.IsFlyoutSlot = IsFlyout

-- Whether a suite button's keys must click it instead of the native command.
function AB.ClickRouted(rec)
    if rec.native then return false end
    local index = rec.bar.index
    local BAR = AB.ENUM.BAR
    if index >= BAR.FIRST_EXTRA then return true end
    if index == BAR.MAIN and AB.CustomPaging(M.config) then return true end
    return IsFlyout(rec.slot) or IsFlyout(rec.base)
end

-- The routes last written (key -> button name pairs) and the routes wanted
-- now; unchanged routes skip the rebuild.
local routedKeys, routedNames, wantedKeys, wantedNames = {}, {}, {}, {}
local routed = false

local function Want(count, key, name)
    count = count + 1
    wantedKeys[count], wantedNames[count] = key, name
    return count
end

local function SameRoutes(count)
    if not routed or #routedKeys ~= count then return false end
    for i = 1, count do
        if routedKeys[i] ~= wantedKeys[i] or routedNames[i] ~= wantedNames[i] then return false end
    end
    return true
end

-- Rebuilds the override click bindings. Out of combat only: in combat the
-- rebuild waits for PLAYER_REGEN_ENABLED.
function AB.UpdateRouting(force)
    if not M.active then return end
    if NS.IsCombatLocked() then
        AB.routingPending = true
        return
    end
    AB.routingPending = nil
    local count = 0
    for i = 1, #AB.owned do
        local rec = AB.owned[i]
        if AB.ClickRouted(rec) then
            local first, second = GetBindingKey(rec.command)
            if first then count = Want(count, first, rec.name) end
            if second then count = Want(count, second, rec.name) end
        end
    end
    for i = count + 1, #wantedKeys do wantedKeys[i], wantedNames[i] = nil, nil end
    if not force and SameRoutes(count) then return end
    routed = true
    for i = 1, count do routedKeys[i], routedNames[i] = wantedKeys[i], wantedNames[i] end
    for i = count + 1, #routedKeys do routedKeys[i], routedNames[i] = nil, nil end
    local owner = AB.bindingOwner
    if not owner then
        owner = S.CreateFrame("Frame")
        AB.bindingOwner = owner
    end
    ClearOverrideBindings(owner)
    for i = 1, count do SetOverrideBindingClick(owner, false, routedKeys[i], routedNames[i], "Keybind") end
end

function AB.ClearRouting()
    if AB.bindingOwner then ClearOverrideBindings(AB.bindingOwner) end
    routed, AB.routingPending = false, nil
end

-- Mirrors ActionButtonUseKeyDown and the action bar lock onto the secure
-- grid controller read by the click and drag wraps.
function AB.UpdateClickAttributes()
    local grid = AB.grid
    if not grid or NS.IsCombatLocked() then return end
    local keydown = GetCVarBool("ActionButtonUseKeyDown") and true or false
    local unlocked = not GetCVarBool("lockActionBars")
    if grid:GetAttribute("keydown") ~= keydown then grid:SetAttribute("keydown", keydown) end
    if grid:GetAttribute("unlocked") ~= unlocked then grid:SetAttribute("unlocked", unlocked) end
end

-- Native keys press the hidden Blizzard button, so the visible suite button
-- gets its pushed state from post-hooks on Blizzard's binding handlers. The
-- Up hooks restore it; no polling. Each hook runs isolated (Dispatch): an
-- error is reported and never stops Blizzard's handler.
local Dispatch = S.Dispatch
local NATIVE_BAR = {}
for index = 2, 8 do NATIVE_BAR[AB.NATIVE_BARS[index]] = index end
local function Native(index, id, down)
    if not M.active then return end
    local bar = AB.bars[index]
    local rec = bar and bar.buttons[tonumber(id) or 0]
    if not rec or AB.ClickRouted(rec) then return end
    AB.SetPushed(rec, down)
end
local function MainDown(id) Dispatch(Native, 1, id, true) end
local function MainUp(id) Dispatch(Native, 1, id, false) end
local function MultiDown(bar, id)
    local index = NATIVE_BAR[bar]
    if index then Dispatch(Native, index, id, true) end
end
local function MultiUp(bar, id)
    local index = NATIVE_BAR[bar]
    if index then Dispatch(Native, index, id, false) end
end
-- Blizzard_ActionBar's binding handlers (Shared/ActionButton.lua and
-- MultiActionBars.lua) exist on Retail and Forever before this loads.
function AB.HookNativePresses()
    if AB.nativeHooked then return end
    AB.nativeHooked = true
    hooksecurefunc("ActionButtonDown", MainDown)
    hooksecurefunc("ActionButtonUp", MainUp)
    hooksecurefunc("MultiActionButtonDown", MultiDown)
    hooksecurefunc("MultiActionButtonUp", MultiUp)
end
