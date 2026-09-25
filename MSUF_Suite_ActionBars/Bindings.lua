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

local function Keys(command, ...)
    if type(GetBindingKey) ~= "function" then return end
    return GetBindingKey(command, ...)
end

-- Short key text is shared with the cooldown icons (Surfaces.lua). No range dot.
AB.KeyText = S.KeyText

function AB.BindingText(rec)
    return AB.KeyText((Keys(rec.command)))
end

-- Key text of the suite button that presses a spell, for the cooldown
-- manager's icons (MSUF_Suite_CooldownManager/Keybinds.lua): the text that
-- button shows. Candidates in key preference: each bar's own page in bar
-- order (bar 1 page 1, bars 2-10 their fixed slots), then the form pages
-- 7-9 bar 1 switches to, pressed by bar 1's keys (page 10, slots 109-120,
-- is bar 10). "" when no candidate has a key; nil while the suite bars are
-- off (Blizzard's bars apply then).
local FORM_FIRST, FORM_LAST = 73, 108
local spellSlots = {}
function S.ActionBarsBindingForSpell(spell)
    if not M.active then return nil end
    local actionBar = _G.C_ActionBar
    local find = actionBar and actionBar.FindSpellActionButtons
    local slots = find and spell and find(spell)
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
                if spellSlots[rec.base] then
                    local text = AB.BindingText(rec)
                    if text ~= "" then return text end
                end
            end
        end
    end
    local main = AB.bars[1]
    if main and not M.config.disableFormPaging then
        for slot = FORM_FIRST, FORM_LAST do
            if spellSlots[slot] then
                local text = AB.BindingText(main.buttons[(slot - FORM_FIRST) % 12 + 1])
                if text ~= "" then return text end
            end
        end
    end
    return ""
end

local function IsFlyout(slot)
    if not slot or type(GetActionInfo) ~= "function" then return false end
    local kind = GetActionInfo(slot)
    return Public(kind) and kind == "flyout"
end
AB.IsFlyoutSlot = IsFlyout

-- Whether a suite button's keys must click it instead of the native command.
function AB.ClickRouted(rec)
    if rec.native then return false end
    local index = rec.bar.index
    if index >= 9 then return true end
    if index == 1 and AB.CustomPaging(M.config) then return true end
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
    if NS.IsCombatLocked() or type(SetOverrideBindingClick) ~= "function" then
        AB.routingPending = true
        return
    end
    AB.routingPending = nil
    local count = 0
    for i = 1, #AB.owned do
        local rec = AB.owned[i]
        if AB.ClickRouted(rec) then
            local first, second = Keys(rec.command)
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
    if AB.bindingOwner and type(ClearOverrideBindings) == "function" then ClearOverrideBindings(AB.bindingOwner) end
    routed, AB.routingPending = false, nil
end

-- Mirrors ActionButtonUseKeyDown and the action bar lock onto the secure
-- grid controller read by the click and drag wraps.
function AB.UpdateClickAttributes()
    local grid = AB.grid
    if not grid or NS.IsCombatLocked() then return end
    local keydown = type(GetCVarBool) == "function" and GetCVarBool("ActionButtonUseKeyDown") and true or false
    local unlocked = not (type(GetCVarBool) == "function" and GetCVarBool("lockActionBars"))
    if grid:GetAttribute("keydown") ~= keydown then grid:SetAttribute("keydown", keydown) end
    if grid:GetAttribute("unlocked") ~= unlocked then grid:SetAttribute("unlocked", unlocked) end
end

-- Native keys press the hidden Blizzard button, so the visible suite button
-- gets its pushed state from post-hooks on Blizzard's binding handlers. The
-- Up hooks restore it; no polling.
local NATIVE_BAR = {}
for index = 2, 8 do NATIVE_BAR[AB.NATIVE_BARS[index]] = index end
local function Native(index, id, down)
    if not M.active then return end
    local bar = AB.bars[index]
    local rec = bar and bar.buttons[tonumber(id) or 0]
    if not rec or AB.ClickRouted(rec) then return end
    AB.SetPushed(rec, down)
end
function AB.HookNativePresses()
    if AB.nativeHooked or type(hooksecurefunc) ~= "function" then return end
    AB.nativeHooked = true
    if type(ActionButtonDown) == "function" then
        hooksecurefunc("ActionButtonDown", function(id) Native(1, id, true) end)
    end
    if type(ActionButtonUp) == "function" then
        hooksecurefunc("ActionButtonUp", function(id) Native(1, id, false) end)
    end
    if type(MultiActionButtonDown) == "function" then
        hooksecurefunc("MultiActionButtonDown", function(bar, id)
            local index = NATIVE_BAR[bar]
            if index then
                Native(index, id, true)
            end
        end)
    end
    if type(MultiActionButtonUp) == "function" then
        hooksecurefunc("MultiActionButtonUp", function(bar, id)
            local index = NATIVE_BAR[bar]
            if index then
                Native(index, id, false)
            end
        end)
    end
end
