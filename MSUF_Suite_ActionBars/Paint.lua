local _, P = ...
local NS, S = P.NS, P.Suite
-- Paint passes of the suite's own buttons: range tint, usability, checked
-- state, counts, text, equipped border, cooldowns and proc glows, plus the
-- slot -> buttons map and the walks over visible filled buttons. The
-- dirty mask and the next-frame flush are in Flush.lua, the event map in
-- Events.lua, Blizzard's reused buttons in NativeButtons.lua; they resolve
-- what they use from here (AB.Painter) once at load. No per-event
-- allocation. Secret values (12.x) only reach C sinks: cooldowns through
-- duration objects, counts and text through SetText, desaturation and alpha
-- through curve evaluations. Only NeverSecret fields are compared.
local AB = P.ActionBars
local M = AB.M
local Public = S.Public
local UpdateAssist = AB.UpdateAssist
local api = {}
local slotMap = {}
local chargeEpoch = 0
local rangeRefs = {}
local WalkNative
-- Blizzard keeps the vehicle/override page (133-144) alive separately.
local SPECIAL_FIRST, SPECIAL_LAST = 133, 144

-- Retail and Forever share C_ActionBar with duration objects, so cooldowns
-- never pass through plain numbers. Resolved on enable.
function AB.ResolveAPI()
    local bar = C_ActionBar
    api.HasAction = bar.HasAction
    api.Texture = bar.GetActionTexture
    api.DisplayCount = bar.GetActionDisplayCount
    api.CooldownDuration = bar.GetActionCooldownDuration
    api.Charges = bar.GetActionCharges
    api.ChargeDuration = bar.GetActionChargeDuration
    api.LoC = bar.GetActionLossOfControlCooldownInfo
    api.LoCDuration = bar.GetActionLossOfControlCooldownDuration
    api.Usable = bar.IsUsableAction
    api.Current = bar.IsCurrentAction
    api.AutoRepeat = bar.IsAutoRepeatAction
    api.Equipped = bar.IsEquippedAction
    api.UsesText = bar.UsesActionText
    api.Text = bar.GetActionText
    api.InRange = bar.IsActionInRange
    api.EnableRange = bar.EnableActionRangeCheck
    api.Overlayed = C_SpellActivationOverlay.IsSpellOverlayed
    api.IsItem = bar.IsItemAction
    api.Quality = bar.GetProfessionQualityInfo
    if AB.desatCurve then return end
    local step = Enum.LuaCurveType.Step
    AB.desatCurve, AB.alphaCurve = C_CurveUtil.CreateCurve(), C_CurveUtil.CreateCurve()
    AB.desatCurve:SetType(step)
    AB.alphaCurve:SetType(step)
    AB.desatCurve:AddPoint(0, 0)
    AB.desatCurve:AddPoint(0.001, 1)
end

-- Cooldown opacity curve: full alpha when ready, the setting while the
-- remaining (GCD-free) duration is above zero. Rebuilt on refresh only.
function AB.UpdateCurves()
    -- With no cooldown feedback, the duration object paints and clears the
    -- swipe alone: no GetActionCooldown info table per visible button on
    -- each global cooldown event.
    AB.directDuration = not M.config.desaturateCooldown and M.config.cooldownAlpha >= 100
    local curve = AB.alphaCurve
    local alpha = M.config.cooldownAlpha / 100
    if AB.curveAlpha == alpha then return end
    AB.curveAlpha = alpha
    curve:ClearPoints()
    curve:AddPoint(0, 1)
    curve:AddPoint(0.001, alpha)
end

local function Visible(bar) return bar.header:IsVisible() end

------------------------------------------------------------------ range
local function Tint(rec)
    local icon = rec.button.icon
    if not icon then return end
    local style, code = AB.style, rec.usable or 1
    local key = rec.outOfRange and 4 or code
    if rec.tint == key then return end
    rec.tint = key
    if key == 4 then
        icon:SetVertexColor(style.rr, style.rg, style.rb)
    elseif key == 1 then
        icon:SetVertexColor(1, 1, 1)
    elseif key == 2 then
        icon:SetVertexColor(.5, .5, 1)
    else
        icon:SetVertexColor(.4, .4, .4)
    end
end

local function ReleaseRange(rec)
    local slot = rec.rangeSlot
    if not slot then return end
    rec.rangeSlot, rec.outOfRange = nil, nil
    if rec.native then return end
    local count = (rangeRefs[slot] or 1) - 1
    if count > 0 then
        rangeRefs[slot] = count
        return
    end
    rangeRefs[slot] = nil
    -- Blizzard's still-visible buttons (vehicle, override, extra) own the
    -- special pages; the suite never switches those range checks off.
    if slot < SPECIAL_FIRST or slot > SPECIAL_LAST then api.EnableRange(slot, false) end
end

-- One reference per suite button. There is no initial range event, so an
-- acquire reads the current state once.
local function AcquireRange(rec)
    local slot = rec.slot
    if rec.native then
        rec.rangeSlot = M.config.rangeColoring and slot or nil
        local inRange = rec.rangeSlot and api.InRange(slot)
        rec.outOfRange = Public(inRange) and inRange == false or nil
        return
    end
    if not M.config.rangeColoring or not rec.filled or not slot then
        ReleaseRange(rec)
        return
    end
    if rec.rangeSlot ~= slot then
        ReleaseRange(rec)
        rec.rangeSlot = slot
        local count = rangeRefs[slot] or 0
        rangeRefs[slot] = count + 1
        if count == 0 and (slot < SPECIAL_FIRST or slot > SPECIAL_LAST) then api.EnableRange(slot, true) end
    end
    local inRange = api.InRange(slot)
    rec.outOfRange = Public(inRange) and inRange == false or nil
end

------------------------------------------------------------------ paint parts
local function Usable(rec, usable, noMana)
    -- The range color masks usability. A payload can still update the local
    -- state without a native read; an unknown state is read on the range edge.
    if usable == nil and rec.outOfRange then
        Tint(rec)
        return
    end
    if usable == nil then usable, noMana = api.Usable(rec.slot) end
    rec.usable = (Public(usable) and usable) and 1 or (Public(noMana) and noMana) and 2 or 3
    Tint(rec)
end

local function State(rec)
    local slot, checked = rec.slot, false
    if M.config.castHighlight then
        local current = api.Current(slot)
        local repeating = api.AutoRepeat(slot)
        checked = (Public(current) and current) or (Public(repeating) and repeating) or false
    end
    rec.button:SetChecked(checked)
    rec.decorChecked = checked
    AB.UpdateDecorState(rec)
end

local function Count(rec, charges, queried)
    local slot, count = rec.slot, rec.button.Count
    if not count then return end
    count:SetText(api.DisplayCount(slot))
    local alpha = 1
    if M.config.hideEmptyCharges and rec.noChargeEpoch ~= chargeEpoch then
        if not queried then charges, queried = api.Charges(slot), true end
        local readable = Public(charges) and type(charges) == "table"
        local maximum, current = readable and charges.maxCharges, readable and charges.currentCharges
        -- Secret while cooldowns are restricted: the count then stays shown.
        if Public(maximum) and type(maximum) == "number" and maximum > 1 and Public(current) and current == 0 then alpha = 0 end
    end
    count:SetAlpha(alpha)
    return charges, queried
end

local function Text(rec)
    local name = rec.button.Name
    if not name then return end
    local text = ""
    if api.UsesText(rec.slot) then text = api.Text(rec.slot) end
    name:SetText(text)
end

local function Equipped(rec)
    local border = rec.button.Border
    if not border then return end
    local equipped = api.Equipped(rec.slot)
    if Public(equipped) and equipped then
        border:SetVertexColor(0, 1, 0, .5)
        border:Show()
    else
        border:Hide()
    end
end

-- Cooldown feedback (desaturation, alpha) excludes the global cooldown: the
-- step curves evaluate the GCD-free remaining time straight into the sinks.
local function CooldownFeedback(rec, active)
    local config, button = M.config, rec.button
    local desaturate, alpha = config.desaturateCooldown, config.cooldownAlpha < 100
    if not desaturate and not alpha then
        if rec.feedback then
            rec.feedback = nil
            button.icon:SetDesaturation(0)
            button:SetAlpha(1)
        end
        return
    end
    rec.feedback = true
    if not active then
        button.icon:SetDesaturation(0)
        button:SetAlpha(1)
        return
    end
    local object = api.CooldownDuration(rec.slot, true)
    if not object then
        button.icon:SetDesaturation(0)
        button:SetAlpha(1)
        return
    end
    button.icon:SetDesaturation(desaturate and object:EvaluateRemainingDuration(AB.desatCurve) or 0)
    if alpha then
        button:SetAlpha(object:EvaluateRemainingDuration(AB.alphaCurve))
    else
        button:SetAlpha(1)
    end
end

-- The duration getters are documented as never nil, but the 12.1 client
-- returns nothing for some action slots (BugSack: GetActionChargeDuration on a
-- proven charge action). Without an object the swipe clears instead of
-- erroring. Returns the new shown flag.
local function Swipe(frame, duration)
    if duration then
        frame:SetCooldownFromDurationObject(duration)
        return true
    end
    frame:Clear()
    return nil
end

-- Duration objects paint every swipe and drive the optional feedback; an
-- inactive cooldown needs no info table, and secret remaining times stay
-- inside Blizzard's C sinks.
local function Cooldown(rec, charges, chargesQueried)
    local slot, button = rec.slot, rec.button
    local cooldown, charge, loc = button.cooldown, button.chargeCooldown, button.lossOfControlCooldown
    local replace = false
    if loc and AB.locActive then
        local lossInfo = api.LoC(slot)
        local shown = lossInfo and lossInfo.isActive
        if Public(shown) and shown then
            replace = lossInfo.shouldReplaceNormalCooldown == true
            rec.locCooldownShown = Swipe(loc, api.LoCDuration(slot))
        elseif rec.locCooldownShown then
            loc:Clear()
            rec.locCooldownShown = nil
        end
    elseif loc and rec.locCooldownShown then
        loc:Clear()
        rec.locCooldownShown = nil
    end
    if charge and rec.noChargeEpoch ~= chargeEpoch then
        -- Once this action's public maximum proves it has charges, the native
        -- duration can paint and clear the recharge without another info table.
        -- Charge, spell and action changes invalidate that proof; counts still
        -- read their current answer when their own work is marked.
        if not chargesQueried and rec.chargeTypeEpoch == chargeEpoch then
            if not replace then
                rec.chargeCooldownShown = Swipe(charge, api.ChargeDuration(slot))
            elseif rec.chargeCooldownShown then
                charge:Clear()
                rec.chargeCooldownShown = nil
            end
        else
            -- A full paint already read the same native table for the count.
            -- Share it only within this synchronous paint, including a nil result.
            if not chargesQueried then charges, chargesQueried = api.Charges(slot), true end
            local readable = Public(charges) and type(charges) == "table"
            local recharging = readable and charges.isActive
            if Public(recharging) and recharging and not replace then
                rec.chargeCooldownShown = Swipe(charge, api.ChargeDuration(slot))
            elseif readable and Public(recharging) and rec.chargeCooldownShown then
                charge:Clear()
                rec.chargeCooldownShown = nil
            end
            -- Blizzard returns a public maxCharges=0 for actions without charges.
            -- Recheck on a charge event or when the action itself is repainted.
            local maximum = readable and charges.maxCharges
            if Public(maximum) and type(maximum) == "number" and maximum > 0 then
                rec.chargeTypeEpoch = chargeEpoch
            end
            if Public(maximum) and maximum == 0 and Public(recharging) and recharging == false then
                rec.noChargeEpoch = chargeEpoch
                rec.chargeTypeEpoch = nil
            end
        end
    end
    if not replace then
        -- clearIfZero defaults to true: a ready action clears its swipe.
        rec.cooldownShown = Swipe(cooldown, api.CooldownDuration(slot))
    elseif rec.cooldownShown then
        cooldown:Clear()
        rec.cooldownShown = nil
    end
    if not AB.directDuration or rec.feedback then CooldownFeedback(rec, not replace) end
    return charges, chargesQueried
end

------------------------------------------------------------------ glows
-- What a proc glow event is matched against, per button: a spell action
-- keeps its spell ID until the button is repainted; a macro (modifiers can
-- change its spell without a slot event) or an unreadable action is read
-- per event; a flyout rescans its slots; anything else never glows.
local GLOW_NONE, GLOW_SPELL, GLOW_DYNAMIC, GLOW_FLYOUT = 0, 1, 2, 3

-- The action's kind, ID and subtype; nothing while any of them is secret.
local function ReadAction(slot)
    local kind, id, sub = GetActionInfo(slot)
    if not Public(kind) or not Public(id) or not Public(sub) then return end
    return kind, id, sub
end

-- The spell a proc glow matches on this action, else its flyout.
local function ActionSpell(slot)
    local kind, id, sub = ReadAction(slot)
    if kind == "spell" or (kind == "macro" and sub == "spell") then return id end
    if kind == "flyout" then return nil, id end
end

-- Caches what GlowMatch compares; returns ActionSpell's answer.
local function CacheAction(rec)
    local kind, id, sub = ReadAction(rec.slot)
    if kind == "spell" then
        rec.glowKind, rec.glowID = GLOW_SPELL, id
        return id
    elseif kind == "flyout" then
        rec.glowKind, rec.glowID = GLOW_FLYOUT, id
        return nil, id
    elseif kind == "macro" or kind == nil then
        rec.glowKind, rec.glowID = GLOW_DYNAMIC, nil
        if sub == "spell" then return id end
        return
    end
    rec.glowKind, rec.glowID = GLOW_NONE, nil
end

-- Blizzard's proc alert on a suite button, played exactly as
-- ActionButtonSpellAlertManager plays a default alert on a button without
-- a bar or action field (template, 1.4x size, start animation, then loop).
-- The manager is not called: it records every alert in its shared
-- activeAlerts table, which Blizzard walks for its own buttons, and a
-- suite entry there would taint that walk. The frame is created raw, as
-- the manager creates it, so the flipbook looks the same. Both clients ship
-- the template (Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.xml).
local ALERT_TEMPLATE = "ActionButtonSpellAlertTemplate"

local function ShowAlert(button)
    local alert = button.SpellActivationAlert
    if not alert then
        alert = CreateFrame("Frame", nil, button, ALERT_TEMPLATE)
        button.SpellActivationAlert = alert
        alert:SetPoint("CENTER", button, "CENTER", 0, 0)
    end
    local size = button:GetWidth()
    alert:SetSize(size * 1.4, size * 1.4)
    alert:Show()
    alert.ProcStartAnim:Play()
end

local function HideAlert(button)
    local alert = button.SpellActivationAlert
    if not alert then return end
    alert:Hide()
    alert.ProcStartAnim:Stop()
end

-- The pixel border glow in the current interaction color; a round button
-- glows with a ring.
local function PixelGlow(rec)
    if M.config.buttonShape == 2 then
        AB.ShowEdges(rec.glowEdges, false)
        AB.GlowRing(rec, true)
        return
    end
    AB.GlowRing(rec, false)
    local style = AB.style
    AB.PlaceEdges(AB.Edges(rec, "glowEdges", "OVERLAY", 7), rec.button, 2, style.ir, style.ig, style.ib, 1)
end

-- SetGlow skips unchanged glows, so the style pass redraws a showing pixel
-- glow when the interaction color changes.
function AB.RecolorGlow(rec)
    if rec.glow and rec.glowMode == 2 then PixelGlow(rec) end
end

local function SetGlow(rec, show)
    local mode = M.config.procGlow
    if rec.glow == show and rec.glowMode == mode then return end
    local button = rec.button
    -- Hide whatever the previous mode drew before switching.
    if rec.glow then
        if rec.glowMode == 1 then HideAlert(button) end
        AB.ShowEdges(rec.glowEdges, false)
        AB.GlowRing(rec, false)
    end
    rec.glow, rec.glowMode = show, mode
    if not show then return end
    if mode == 1 then
        ShowAlert(button)
    elseif mode == 2 then
        PixelGlow(rec)
    end
end

local function GlowCheck(rec)
    local spell, flyout = CacheAction(rec)
    local show = false
    if spell then
        local overlayed = api.Overlayed(spell)
        show = Public(overlayed) and overlayed or false
    elseif flyout then
        local _, _, slots = GetFlyoutInfo(flyout)
        for i = 1, Public(slots) and type(slots) == "number" and slots or 0 do
            local id = GetFlyoutSlotInfo(flyout, i)
            local overlayed = Public(id) and id and api.Overlayed(id)
            if Public(overlayed) and overlayed then
                show = true
                break
            end
        end
    end
    SetGlow(rec, show and M.config.procGlow ~= 3)
end

------------------------------------------------------------------ buttons
local function Clear(rec)
    if rec.quality then rec.quality:Hide() end
    local button = rec.button
    rec.filled = false
    if button.icon then
        button.icon:SetTexture(nil)
        button.icon:Hide()
    end
    button.cooldown:Clear()
    if button.chargeCooldown then button.chargeCooldown:Clear() end
    if button.lossOfControlCooldown then button.lossOfControlCooldown:Clear() end
    rec.cooldownShown, rec.chargeCooldownShown, rec.locCooldownShown, rec.noChargeEpoch = nil, nil, nil, nil
    rec.chargeTypeEpoch = nil
    if button.Count then button.Count:SetText("") end
    if button.Name then button.Name:SetText("") end
    if button.Border then button.Border:Hide() end
    button:SetChecked(false)
    if rec.feedback then
        rec.feedback = nil
        if button.icon then
            button.icon:SetDesaturation(0)
        end
        button:SetAlpha(1)
    end
    rec.glowKind, rec.glowID = GLOW_NONE, nil
    SetGlow(rec, false)
    ReleaseRange(rec)
end

-- A crafted item's quality badge, as ActionBarActionButtonMixin:
-- UpdateProfessionQuality shows it on Retail and Forever: item actions only.
-- Native reused buttons own this overlay themselves.
local function ProfessionQuality(rec)
    if rec.native then return end
    local item = api.IsItem(rec.slot)
    local info = Public(item) and item and api.Quality(rec.slot)
    local atlas = Public(info) and type(info) == "table" and info.iconInventory
    if not Public(atlas) or type(atlas) ~= "string" or atlas == "" then
        if rec.quality then rec.quality:Hide() end
        return
    end
    if not rec.quality then rec.quality = S.CreateTexture(rec.button, nil, "OVERLAY", nil, 7) end
    rec.quality:SetAtlas(atlas)
    rec.quality:SetSize(math.max(8, rec.bar.size * .4), math.max(8, rec.bar.size * .4))
    rec.quality:ClearAllPoints()
    rec.quality:SetPoint("TOPLEFT", rec.button.icon, "TOPLEFT", 0, 0)
    rec.quality:Show()
end

local function Paint(rec)
    local slot = rec.slot
    local has = slot and api.HasAction(slot)
    if not (Public(has) and has) then
        Clear(rec)
        UpdateAssist(rec)
        return
    end
    rec.noChargeEpoch = nil
    rec.chargeTypeEpoch = nil
    rec.filled = true
    local icon = rec.button.icon
    local texture = api.Texture(slot)
    icon:SetTexture(texture)
    icon:Show()
    rec.tex = Public(texture) and texture or nil
    rec.tint = nil
    AcquireRange(rec)
    Usable(rec)
    State(rec)
    local charges, chargesQueried = Count(rec)
    Text(rec)
    Equipped(rec)
    ProfessionQuality(rec)
    Cooldown(rec, charges, chargesQueried)
    GlowCheck(rec)
    -- The recommendation ring follows the action the paint just cached.
    UpdateAssist(rec)
end

-- Icon storms (forms, spell overrides): only buttons whose texture changed
-- get the full repaint.
local function Icon(rec)
    local texture = api.Texture(rec.slot)
    if rec.tex ~= nil and Public(texture) and texture == rec.tex then return end
    Paint(rec)
end

local function Refill(bar)
    local filled, count = bar.filled, 0
    for i = 1, #bar.buttons do
        local rec = bar.buttons[i]
        if rec.filled and i <= (bar.count or 12) then
            count = count + 1
            filled[count] = rec
        end
    end
    for i = count + 1, #filled do filled[i] = nil end
end

-- slotMap: slot -> the owned buttons showing it. A slot's list is created
-- the first time a button shows that slot and reused afterwards.
local function MapButton(rec)
    local slot = rec.slot
    if not slot then return end
    local list = slotMap[slot]
    if not list then
        list = {}
        slotMap[slot] = list
    end
    list[#list + 1] = rec
end

local function UnmapButton(rec)
    local list = rec.slot and slotMap[rec.slot]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == rec then
            table.remove(list, i)
            return
        end
    end
end

local function Remap()
    for _, list in pairs(slotMap) do
        for i = #list, 1, -1 do
            list[i] = nil
        end
    end
    for i = 1, #AB.owned do
        local rec = AB.owned[i]
        rec.noChargeEpoch = nil
        rec.chargeTypeEpoch = nil
        MapButton(rec)
    end
end

-- Key texts depend on bindings only (each button keeps its command), so
-- page flips and repaints never read them.
local function KeyTexts(bar)
    for i = 1, #bar.buttons do
        local rec = bar.buttons[i]
        local text = rec.keyText or (rec.owned and rec.button.HotKey)
        if text then text:SetText(AB.BindingText(rec)) end
    end
end

local function AllKeyTexts()
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar then KeyTexts(bar) end
    end
end

local function PaintBar(bar)
    if not bar.owned or bar.native then return end
    for i = 1, #bar.buttons do Paint(bar.buttons[i]) end
    Refill(bar)
end

local function Walk(fn)
    for index = 1, 10 do
        local bar = AB.bars[index]
        if bar and not bar.native and Visible(bar) then
            local filled = bar.filled
            for i = 1, #filled do fn(filled[i]) end
        end
    end
end

WalkNative = function(fn)
    for index = 2, 8 do
        local bar = AB.bars[index]
        if bar and bar.native and Visible(bar) then
            for i = 1, #bar.buttons do
                local rec = bar.buttons[i]
                if rec.button:IsVisible() then fn(rec) end
            end
        end
    end
end

function AB.ShowTooltip(rec)
    if not rec.slot or not rec.filled then return end
    GameTooltip_SetDefaultAnchor(GameTooltip, rec.button)
    GameTooltip:SetAction(rec.slot)
end

-- Charge reads are skipped for actions known to have no charges until the
-- next charge-related event starts a new epoch.
local function NewChargeEpoch() chargeEpoch = chargeEpoch + 1 end

-- Test and diagnostics hook: the number of suite range references held.
function AB.RangeReferences()
    local total = 0
    for _, count in pairs(rangeRefs) do total = total + count end
    return total
end

AB.Painter = {
    api = api, slotMap = slotMap, Visible = Visible, NewChargeEpoch = NewChargeEpoch,
    Tint = Tint, ReleaseRange = ReleaseRange, AcquireRange = AcquireRange,
    Usable = Usable, State = State, Count = Count, Cooldown = Cooldown, CooldownFeedback = CooldownFeedback,
    CacheAction = CacheAction, ActionSpell = ActionSpell, SetGlow = SetGlow, GlowCheck = GlowCheck,
    GLOW_SPELL = GLOW_SPELL, GLOW_DYNAMIC = GLOW_DYNAMIC, GLOW_FLYOUT = GLOW_FLYOUT,
    Paint = Paint, Icon = Icon, Refill = Refill, MapButton = MapButton, UnmapButton = UnmapButton, Remap = Remap,
    AllKeyTexts = AllKeyTexts, PaintBar = PaintBar, Walk = Walk, WalkNative = WalkNative,
}
