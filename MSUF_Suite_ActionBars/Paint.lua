local _, P = ...
local NS, S = P.NS, P.Suite
-- Central dispatcher. One event frame (the module context) marks work dirty;
-- a single next-frame flush paints it: same-frame dedupe for free, a 0.1 s
-- leading-edge cap with one trailing flush for cooldown and usable storms,
-- per-bar filled-button lists, a slot -> buttons map for targeted events,
-- and dormant (hidden) bars skipped entirely. No OnUpdate, no per-event
-- allocation. Secret values (12.x) only reach C sinks: cooldowns through
-- duration objects, counts and text through SetText, desaturation and alpha
-- through curve evaluations. Only NeverSecret fields are compared.
local AB = P.ActionBars
local M = AB.M
local Public = S.Public
local api = {}
local slotMap = {}
local dirty = { cooldown = false, usable = false, state = false, count = false, icon = false, full = false }
local dirtySlots, dirtyBars, refillBars, gridBars = {}, {}, {}, {}
local scheduled, routingDirty, gridDirty = false, false, false
local legacyCooldown, legacyCharges = {}, {}
local last = { cooldown = 0, usable = 0 }
local chargeEpoch = 0
local rangeRefs = {}
local CAP = 0.1
local RETAIL = NS.Client.isMainline and not NS.Client.isForever
local WalkNative
-- Blizzard keeps the vehicle/override page (133-144) alive separately.
local SPECIAL_FIRST, SPECIAL_LAST = 133, 144

-- C_ActionBar first; Classic globals as fallback. Resolved on enable so the
-- runtime follows whatever the client provides.
function AB.ResolveAPI()
    local bar = C_ActionBar or {}
    api.HasAction = bar.HasAction or _G.HasAction
    api.Texture = bar.GetActionTexture or _G.GetActionTexture
    api.DisplayCount = bar.GetActionDisplayCount
    api.UseCount = bar.GetActionUseCount or _G.GetActionCount
    api.Cooldown = bar.GetActionCooldown
    api.CooldownDuration = bar.GetActionCooldownDuration
    api.Charges = bar.GetActionCharges
    api.ChargeDuration = bar.GetActionChargeDuration
    api.LoC = bar.GetActionLossOfControlCooldownInfo
    api.LoCDuration = bar.GetActionLossOfControlCooldownDuration
    api.Usable = bar.IsUsableAction or _G.IsUsableAction
    api.Current = bar.IsCurrentAction or _G.IsCurrentAction
    api.AutoRepeat = bar.IsAutoRepeatAction or _G.IsAutoRepeatAction
    api.Equipped = bar.IsEquippedAction or _G.IsEquippedAction
    api.UsesText = bar.UsesActionText
    api.Text = bar.GetActionText or _G.GetActionText
    api.InRange = bar.IsActionInRange or _G.IsActionInRange
    api.EnableRange = bar.EnableActionRangeCheck
    api.Overlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
    -- Older Classic builds: numeric globals, copied into reused tables.
    if not api.Cooldown and type(_G.GetActionCooldown) == "function" then
        local get = _G.GetActionCooldown
        api.Cooldown = function(slot)
            local start, duration, enable, modRate = get(slot)
            legacyCooldown.startTime, legacyCooldown.duration, legacyCooldown.modRate = start, duration, modRate
            legacyCooldown.isEnabled, legacyCooldown.isActive = enable ~= 0 and enable ~= false, nil
            return legacyCooldown
        end
    end
    if not api.Charges and type(_G.GetActionCharges) == "function" then
        local get = _G.GetActionCharges
        api.Charges = function(slot)
            local current, maximum, start, duration, modRate = get(slot)
            legacyCharges.currentCharges, legacyCharges.maxCharges = current, maximum
            legacyCharges.cooldownStartTime, legacyCharges.cooldownDuration, legacyCharges.chargeModRate = start, duration, modRate
            legacyCharges.isActive = type(current) == "number" and type(maximum) == "number" and current < maximum
                and type(duration) == "number" and duration > 0
            return legacyCharges
        end
    end
    -- Secret clients must use duration objects; plain clients use numbers.
    api.durations = NS.Client.hasSecrets and api.CooldownDuration ~= nil
    local curves = C_CurveUtil and C_CurveUtil.CreateCurve
    if api.durations and curves and not AB.desatCurve then
        local step = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
        AB.desatCurve, AB.alphaCurve = curves(), curves()
        if step then
            AB.desatCurve:SetType(step)
            AB.alphaCurve:SetType(step)
        end
        AB.desatCurve:AddPoint(0, 0)
        AB.desatCurve:AddPoint(0.001, 1)
    end
end

-- Cooldown opacity curve: full alpha when ready, the setting while the
-- remaining (GCD-free) duration is above zero. Rebuilt on refresh only.
function AB.UpdateCurves()
    -- With no cooldown feedback, the duration object can paint and clear the
    -- swipe directly. This avoids a fresh GetActionCooldown info table for
    -- every visible button on each global cooldown event.
    AB.directDuration = api.durations and api.CooldownDuration
        and not M.config.desaturateCooldown and M.config.cooldownAlpha >= 100
    local curve = AB.alphaCurve
    if not curve then return end
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
    if api.EnableRange and (slot < SPECIAL_FIRST or slot > SPECIAL_LAST) then api.EnableRange(slot, false) end
end

-- One reference per suite button. There is no initial range event, so an
-- acquire reads the current state once.
local function AcquireRange(rec)
    local slot = rec.slot
    if rec.native then
        rec.rangeSlot = M.config.rangeColoring and slot or nil
        local inRange = rec.rangeSlot and api.InRange and api.InRange(slot)
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
        if count == 0 and api.EnableRange and (slot < SPECIAL_FIRST or slot > SPECIAL_LAST) then api.EnableRange(slot, true) end
    end
    local inRange = api.InRange and api.InRange(slot)
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
        local repeating = api.AutoRepeat and api.AutoRepeat(slot)
        checked = (Public(current) and current) or (Public(repeating) and repeating) or false
    end
    rec.button:SetChecked(checked)
end

local function Count(rec)
    local slot, count = rec.slot, rec.button.Count
    if not count then return end
    if api.DisplayCount then
        count:SetText(api.DisplayCount(slot))
    elseif api.UseCount then
        local uses = api.UseCount(slot)
        count:SetText((Public(uses) and type(uses) == "number" and uses > 1) and uses or "")
    end
    local alpha = 1
    if M.config.hideEmptyCharges and api.Charges and rec.noChargeEpoch ~= chargeEpoch then
        local charges = api.Charges(slot)
        local readable = Public(charges) and type(charges) == "table"
        local maximum, current = readable and charges.maxCharges, readable and charges.currentCharges
        -- Secret while cooldowns are restricted: the count then stays shown.
        if Public(maximum) and type(maximum) == "number" and maximum > 1 and Public(current) and current == 0 then alpha = 0 end
    end
    count:SetAlpha(alpha)
end

local function Text(rec)
    local name = rec.button.Name
    if not name then return end
    local text = ""
    if not api.UsesText or api.UsesText(rec.slot) then text = api.Text and api.Text(rec.slot) or "" end
    name:SetText(text)
end

local function Equipped(rec)
    local border = rec.button.Border
    if not border then return end
    local equipped = api.Equipped and api.Equipped(rec.slot)
    if Public(equipped) and equipped then
        border:SetVertexColor(0, 1, 0, .5)
        border:Show()
    else
        border:Hide()
    end
end

-- Cooldown feedback (desaturation, alpha) excludes the global cooldown.
local function CooldownFeedback(rec, active, duration)
    local c, button = M.config, rec.button
    local desaturate, alpha = c.desaturateCooldown, c.cooldownAlpha < 100
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
    if api.durations then
        local object = AB.desatCurve and api.CooldownDuration(rec.slot, true)
        if not object or type(object.EvaluateRemainingDuration) ~= "function" then return end
        button.icon:SetDesaturation(desaturate and object:EvaluateRemainingDuration(AB.desatCurve) or 0)
        if alpha then
            button:SetAlpha(object:EvaluateRemainingDuration(AB.alphaCurve))
        else
            button:SetAlpha(1)
        end
    else
        -- Plain values: the GCD never lasts longer than 1.5 s.
        local long = Public(duration) and type(duration) == "number" and duration > 1.5
        button.icon:SetDesaturation((desaturate and long) and 1 or 0)
        button:SetAlpha((alpha and long) and c.cooldownAlpha / 100 or 1)
    end
end

local function Cooldown(rec)
    local slot, button = rec.slot, rec.button
    local cooldown, charge, loc = button.cooldown, button.chargeCooldown, button.lossOfControlCooldown
    -- Duration objects also drive optional cooldown feedback. Their curve
    -- evaluates an inactive cooldown to the ready color without a fresh info
    -- table, while secret remaining times stay inside Blizzard's C sinks.
    local direct = api.durations and api.CooldownDuration and cooldown and cooldown.SetCooldownFromDurationObject
    local info = not direct and api.Cooldown and api.Cooldown(slot)
    local active = info and info.isActive
    if active == nil and info and not api.durations then
        -- Plain clients whose info lacks isActive: derive it from numbers.
        local duration = info.duration
        active = info.isEnabled ~= false and Public(duration) and type(duration) == "number" and duration > 0
    end
    if info and not Public(active) then active = false end
    local replace = false
    if loc and api.LoC and AB.locActive then
        local lossInfo = api.LoC(slot)
        local shown = lossInfo and lossInfo.isActive
        if Public(shown) and shown then
            replace = lossInfo.shouldReplaceNormalCooldown == true
            if api.durations and api.LoCDuration then
                loc:SetCooldownFromDurationObject(api.LoCDuration(slot))
            elseif Public(lossInfo.startTime) then
                loc:SetCooldown(lossInfo.startTime, lossInfo.duration, lossInfo.modRate)
            end
            rec.locCooldownShown = true
        else
            if rec.locCooldownShown then
                loc:Clear()
                rec.locCooldownShown = nil
            end
        end
    elseif loc and rec.locCooldownShown then
        loc:Clear()
        rec.locCooldownShown = nil
    end
    if charge and rec.noChargeEpoch ~= chargeEpoch then
        local charges = api.Charges and api.Charges(slot)
        local readable = Public(charges) and type(charges) == "table"
        local recharging = readable and charges.isActive
        if Public(recharging) and recharging and not replace then
            if api.durations and api.ChargeDuration then
                charge:SetCooldownFromDurationObject(api.ChargeDuration(slot))
            else
                charge:SetCooldown(charges.cooldownStartTime, charges.cooldownDuration, charges.chargeModRate)
            end
            rec.chargeCooldownShown = true
        elseif readable and Public(recharging) then
            if rec.chargeCooldownShown then
                charge:Clear()
                rec.chargeCooldownShown = nil
            end
        end
        -- Blizzard returns a public maxCharges=0 for actions without charges.
        -- Recheck on a charge event or when the action itself is repainted.
        local maximum = readable and charges.maxCharges
        if Public(maximum) and maximum == 0 and Public(recharging) and recharging == false then
            rec.noChargeEpoch = chargeEpoch
        end
    end
    if direct and not replace then
        -- clearIfZero defaults to true in Retail's CooldownFrame API.
        cooldown:SetCooldownFromDurationObject(api.CooldownDuration(slot))
        rec.cooldownShown = true
    elseif active and not replace then
        if api.durations then
            cooldown:SetCooldownFromDurationObject(api.CooldownDuration(slot))
        else
            cooldown:SetCooldown(info.startTime, info.duration, info.modRate)
        end
        rec.cooldownShown = true
    else
        if rec.cooldownShown then
            cooldown:Clear()
            rec.cooldownShown = nil
        end
    end
    if not AB.directDuration or rec.feedback then
        CooldownFeedback(rec, (direct or active) and not replace, info and info.duration)
    end
end

------------------------------------------------------------------ glows
local function ActionSpell(slot)
    if type(GetActionInfo) ~= "function" then return end
    local kind, id, sub = GetActionInfo(slot)
    if not Public(kind) or not Public(id) or not Public(sub) then return end
    if kind == "spell" or (kind == "macro" and sub == "spell") then return id end
    if kind == "flyout" then return nil, id end
end

local function SetGlow(rec, show)
    local mode = M.config.procGlow
    if rec.glow == show and rec.glowMode == mode then return end
    local button = rec.button
    -- Hide whatever the previous mode drew before switching.
    if rec.glow then
        if rec.glowMode == 1 and ActionButtonSpellAlertManager then ActionButtonSpellAlertManager:HideAlert(button) end
        if rec.glowEdges then
            for i = 1, 4 do
                rec.glowEdges[i]:Hide()
            end
        end
    end
    rec.glow, rec.glowMode = show, mode
    if not show then return end
    if mode == 1 and ActionButtonSpellAlertManager then
        ActionButtonSpellAlertManager:ShowAlert(button)
        local alert = button.SpellActivationAlert
        if alert then
            local size = button:GetWidth()
            alert:SetSize(size * 1.4, size * 1.4)
        end
    elseif mode == 2 then
        if not rec.glowEdges then
            rec.glowEdges = {}
            for i = 1, 4 do rec.glowEdges[i] = S.CreateTexture(button, nil, "OVERLAY", nil, 7) end
        end
        local style = AB.style
        AB.PlaceEdges(rec.glowEdges, button, 2, style.ir, style.ig, style.ib, 1)
    end
end

local function GlowCheck(rec)
    local spell, flyout = ActionSpell(rec.slot)
    local show = false
    if spell and api.Overlayed then
        local overlayed = api.Overlayed(spell)
        show = Public(overlayed) and overlayed or false
    elseif flyout and api.Overlayed and type(GetFlyoutInfo) == "function" and type(GetFlyoutSlotInfo) == "function" then
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
    SetGlow(rec, false)
    ReleaseRange(rec)
end

local function Paint(rec)
    local slot = rec.slot
    local has = slot and api.HasAction(slot)
    if not (Public(has) and has) then
        Clear(rec)
        return
    end
    rec.noChargeEpoch = nil
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
    Count(rec)
    Text(rec)
    Equipped(rec)
    Cooldown(rec)
    GlowCheck(rec)
end
AB.PaintButton = Paint

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

function AB.Remap()
    for _, list in pairs(slotMap) do
        for i = #list, 1, -1 do
            list[i] = nil
        end
    end
    for i = 1, #AB.owned do
        local rec = AB.owned[i]
        rec.noChargeEpoch = nil
        local slot = rec.slot
        if slot then
            local list = slotMap[slot]
            if not list then
                list = {}
                slotMap[slot] = list
            end
            list[#list + 1] = rec
        end
    end
end

local function KeyTexts(bar)
    for i = 1, #bar.buttons do
        local rec = bar.buttons[i]
        local text = rec.keyText or (rec.owned and rec.button.HotKey)
        if text then text:SetText(AB.BindingText(rec)) end
    end
end

function AB.PaintBar(bar)
    if bar.owned and not bar.native then
        for i = 1, #bar.buttons do Paint(bar.buttons[i]) end
        Refill(bar)
    end
    KeyTexts(bar)
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

local function NativeFeedback(rec)
    if AB.directDuration then
        if rec.feedback then CooldownFeedback(rec, false) end
        return
    end
    local c = M.config
    if api.durations and AB.desatCurve and api.CooldownDuration then
        -- The duration object can evaluate a secret remaining time directly
        -- into visual C sinks. Avoid GetActionCooldown's fresh info table on
        -- every cooldown broadcast for each native button.
        if AB.locActive and api.LoC then
            local loss = api.LoC(rec.slot)
            local shown = loss and loss.isActive
            if Public(shown) and shown and Public(loss.shouldReplaceNormalCooldown)
                and loss.shouldReplaceNormalCooldown then
                CooldownFeedback(rec, false)
                return
            end
        end
        local object = api.CooldownDuration(rec.slot, true)
        if object and type(object.EvaluateRemainingDuration) == "function" then
            rec.feedback = true
            rec.button.icon:SetDesaturation(c.desaturateCooldown and object:EvaluateRemainingDuration(AB.desatCurve) or 0)
            rec.button:SetAlpha(c.cooldownAlpha < 100 and object:EvaluateRemainingDuration(AB.alphaCurve) or 1)
            return
        end
    end
    local info = api.Cooldown and api.Cooldown(rec.slot)
    local active = info and info.isActive
    if not Public(active) then active = false end
    if active and AB.locActive and api.LoC then
        local loss = api.LoC(rec.slot)
        local shown = loss and loss.isActive
        if Public(shown) and shown and Public(loss.shouldReplaceNormalCooldown)
            and loss.shouldReplaceNormalCooldown then active = false end
    end
    CooldownFeedback(rec, active, info and info.duration)
end

local function NativeCount(rec)
    local count = rec.button.Count
    if not count then return end
    if not M.config.hideEmptyCharges then
        count:SetAlpha(1)
        return
    end
    local charges = api.Charges and api.Charges(rec.slot)
    local readable = Public(charges) and type(charges) == "table"
    local maximum, current = readable and charges.maxCharges, readable and charges.currentCharges
    count:SetAlpha((Public(maximum) and type(maximum) == "number" and maximum > 1
        and Public(current) and current == 0) and 0 or 1)
end

local function NativeState(rec)
    if not M.config.castHighlight then rec.button:SetChecked(false) end
end

local function NativeUsablePost(button, slot, usable, noMana)
    local rec = AB.records[button]
    if not rec or not rec.native or not M.active then return end
    -- Blizzard has already painted usable state. Only an active range
    -- override needs reapplying; another IsUsableAction call here would
    -- duplicate the native call on every usable update.
    if rec.outOfRange then
        rec.tint = nil
        Tint(rec)
    end
end

local function NativeStatePost(button)
    local rec = AB.records[button]
    if rec and rec.native and M.active and not M.config.castHighlight then NativeState(rec) end
end

local function NativeCountdownPost(button)
    local rec = AB.records[button]
    if rec and rec.native and M.active then
        button.cooldown:SetHideCountdownNumbers(not M.config.cooldownNumbers)
    end
end

local function NativeColor(rec)
    local wasRangeTint = rec.tint == 4
    AcquireRange(rec)
    if M.config.rangeColoring or wasRangeTint then
        rec.tint = nil
        Usable(rec)
    end
end

local function RefreshNativeButton(rec)
    if not rec.nativeHooks and type(hooksecurefunc) == "function" then
        rec.nativeHooks = true
        if type(rec.button.UpdateUsable) == "function" then
            hooksecurefunc(rec.button, "UpdateUsable", NativeUsablePost)
        end
        if type(rec.button.UpdateState) == "function" then
            hooksecurefunc(rec.button, "UpdateState", NativeStatePost)
        end
    end
    NativeColor(rec)
    NativeCount(rec)
    NativeState(rec)
    NativeFeedback(rec)
    if M.config.procGlow == 2 then
        GlowCheck(rec)
    else
        SetGlow(rec, false)
    end
end

function AB.RefreshNativeBar(bar)
    if not bar or not bar.native then return end
    for i = 1, #bar.buttons do RefreshNativeButton(bar.buttons[i]) end
end

function AB.RefreshNative()
    if not AB.nativeCountdownHooked and type(hooksecurefunc) == "function"
        and type(ActionButton_UpdateCooldownNumberHidden) == "function" then
        hooksecurefunc("ActionButton_UpdateCooldownNumberHidden", NativeCountdownPost)
        AB.nativeCountdownHooked = true
    end
    for index = 2, 8 do
        AB.RefreshNativeBar(AB.bars[index])
    end
end

------------------------------------------------------------------ flush
local Flush
local function Schedule(delay)
    if scheduled or not C_Timer then return end
    scheduled = true
    C_Timer.After(delay or 0, Flush)
end

-- Leading edge next frame, then at most one walk per CAP seconds.
local function Capped(kind, now, fn)
    if not dirty[kind] then return end
    local wait = last[kind] + CAP - now
    if wait > 0 then
        Schedule(wait)
        return
    end
    dirty[kind] = false
    last[kind] = now
    Walk(fn)
    if kind == "cooldown" and not AB.directDuration then WalkNative(NativeFeedback) end
end

Flush = function()
    scheduled = false
    if not M.active then return end
    local now = type(GetTime) == "function" and GetTime() or 0
    local nativeFull = false
    if dirty.full then
        dirty.full = false
        for kind in pairs(dirty) do dirty[kind] = false end
        for slot in pairs(dirtySlots) do dirtySlots[slot] = nil end
        for index = 1, AB.BAR_COUNT do
            local bar = AB.bars[index]
            if bar then
                dirtyBars[bar] = true
            end
        end
        -- Suite paint skips native buttons, so their optional effects still
        -- need one pass when a global refresh absorbs same-frame events.
        nativeFull = true
        if M.config.hideEmptyCharges then dirty.count = true end
        if not M.config.castHighlight then dirty.state = true end
        if not AB.directDuration then dirty.cooldown = true end
    end
    for bar in pairs(dirtyBars) do
        dirtyBars[bar] = nil
        if Visible(bar) then
            AB.PaintBar(bar)
        else
            KeyTexts(bar)
        end
    end
    for slot in pairs(dirtySlots) do
        dirtySlots[slot] = nil
        local list = slotMap[slot]
        if list then
            for i = 1, #list do
                local rec = list[i]
                if not rec.native and Visible(rec.bar) then
                    Paint(rec)
                    refillBars[rec.bar] = true
                end
            end
        end
    end
    for bar in pairs(refillBars) do
        refillBars[bar] = nil
        Refill(bar)
    end
    Capped("cooldown", now, Cooldown)
    Capped("usable", now, Usable)
    if dirty.state then
        dirty.state = false
        Walk(State)
        if not M.config.castHighlight then
            WalkNative(NativeState)
        end
    end
    if dirty.count then
        dirty.count = false
        Walk(Count)
        if M.config.hideEmptyCharges then
            WalkNative(NativeCount)
        end
    end
    if dirty.icon then
        dirty.icon = false
        Walk(Icon)
        for index = 1, 10 do
            local bar = AB.bars[index]
            if bar and not bar.native and Visible(bar) then
                Refill(bar)
            end
        end
    end
    if nativeFull then
        WalkNative(NativeColor)
        if M.config.procGlow == 2 then WalkNative(GlowCheck) end
    end
    -- Shown/empty state and key routing are protected: out of combat only.
    if not NS.IsCombatLocked() then
        for index = 1, 10 do
            local bar = AB.bars[index]
            if bar and (gridDirty or gridBars[bar]) then
                gridBars[bar] = nil
                AB.Execute(bar.header, [[self:ChildUpdate("grid")]])
            end
        end
        gridDirty = false
        if routingDirty then
            routingDirty = false
            AB.UpdateRouting()
        end
    end
end

local function Mark(kind)
    dirty[kind] = true
    Schedule(0)
end
function AB.MarkAll()
    dirty.full = true
    routingDirty = true
    gridDirty = true
    Schedule(0)
end
function AB.MarkBar(bar)
    dirtyBars[bar] = true
    Schedule(0)
end

------------------------------------------------------------------ events
local function SlotChanged(_, _, slot)
    if not Public(slot) or type(slot) ~= "number" or slot == 0 then
        AB.MarkAll()
        return
    end
    dirtySlots[slot] = true
    -- A filled or emptied slot changes which buttons show; a slot becoming or
    -- ceasing to be a flyout changes key routing.
    local list = slotMap[slot]
    if list then
        local flyout = AB.IsFlyoutSlot(slot)
        for i = 1, #list do
            local rec = list[i]
            gridBars[rec.bar] = true
            if not rec.native and rec.flyout ~= flyout then
                rec.flyout = flyout
                routingDirty = true
            end
        end
    end
    Schedule(0)
end

local function UsableChanged(_, _, changes)
    if type(changes) ~= "table" then
        Mark("usable")
        return
    end
    for i = 1, #changes do
        local change = changes[i]
        local slot = type(change) == "table" and change.slot
        local list = Public(slot) and slotMap[slot]
        if list then
            for n = 1, #list do
                local rec = list[n]
                if not rec.native and rec.filled and Visible(rec.bar) then Usable(rec, change.usable, change.noMana) end
            end
        end
    end
end

local function RangeChanged(_, _, slot, inRange, checksRange)
    if not M.config.rangeColoring then return end
    local list = Public(slot) and slotMap[slot]
    if not list then return end
    local out = Public(inRange) and Public(checksRange) and checksRange and not inRange or nil
    for i = 1, #list do
        local rec = list[i]
        if rec.rangeSlot == slot and rec.outOfRange ~= out then
            rec.outOfRange = out
            if not out then
                Usable(rec)
            else
                Tint(rec)
            end
        end
    end
end

-- Clients without range events: re-read range on target changes only.
local function ReadRange(rec)
    local inRange = api.InRange and api.InRange(rec.slot)
    rec.outOfRange = Public(inRange) and inRange == false or nil
    Tint(rec)
end
local function TargetChanged()
    Mark("usable")
    if api.EnableRange or not M.config.rangeColoring then return end
    Walk(ReadRange)
end

-- Proc glows match the event's spell against spell and macro actions;
-- flyouts rescan their slots.
local glowSpell, glowShow
local function GlowMatch(rec)
    local id, flyout = ActionSpell(rec.slot)
    if id == glowSpell then
        SetGlow(rec, glowShow and M.config.procGlow ~= 3)
    elseif flyout then
        GlowCheck(rec)
    end
end
local function Glow(_, event, spell)
    if M.config.procGlow == 3 then return end
    if not Public(spell) or type(spell) ~= "number" then
        AB.MarkAll()
        return
    end
    glowSpell, glowShow = spell, event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
    Walk(GlowMatch)
    if M.config.procGlow == 2 then WalkNative(GlowMatch) end
end

local function ActiveLossOfControl()
    local source = _G.C_LossOfControl
    local get = source and source.GetActiveLossOfControlDataCountByUnit
    if not get then return nil end
    local count = get("player")
    if Public(count) and type(count) == "number" then return count > 0 end
end

local function LossOfControl(_, _, unit)
    if Public(unit) and unit and unit ~= "player" then return end
    -- The event marks both the start and the end of an effect. Keep checking
    -- individual action slots only while the player has an active effect.
    local active = ActiveLossOfControl()
    AB.locActive = active == nil and true or active
    Mark("cooldown")
end

local function Bindings()
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar then
            KeyTexts(bar)
        end
    end
    AB.UpdateRouting()
end

local function CVarChanged(_, _, name)
    if name == "ActionButtonUseKeyDown" or name == "lockActionBars" or name == "LOCK_ACTIONBAR" then
        if NS.IsCombatLocked() then
            AB.attributesPending = true
        else
            AB.UpdateClickAttributes()
        end
    end
end

local function FormsChanged()
    local bar = AB.bars[11]
    if not bar then return end
    local forms = AB.HasForms()
    local count = AB.Count(bar, M.config)
    if bar.count == count and bar.forms == forms then return end
    -- Layout, adoption and the driver are protected: re-apply after combat.
    if NS.IsCombatLocked() then
        S.Queue("actionbars")
    else
        M:Refresh()
    end
end

local function RegenEnabled()
    if AB.routingPending then AB.UpdateRouting() end
    if AB.attributesPending then
        AB.attributesPending = nil
        AB.UpdateClickAttributes()
    end
    if AB.dragPending or AB.dragging then AB.ApplyDrag() end
    if gridDirty or routingDirty or next(gridBars) then Schedule(0) end
end

local EVENTS = {
    ACTIONBAR_SLOT_CHANGED = SlotChanged,
    ACTIONBAR_UPDATE_COOLDOWN = function() Mark("cooldown") end,
    -- Retail action buttons follow ACTIONBAR_UPDATE_COOLDOWN (Blizzard ActionButton.lua).
    -- Keep the spell event only on older clients that may lack that guarantee.
    SPELL_UPDATE_COOLDOWN = (not RETAIL
        and function() Mark("cooldown") end) or nil,
    -- Retail's Blizzard buttons only refresh counts here; cooldown swipes
    -- follow ACTIONBAR_UPDATE_COOLDOWN. Keep the extra walk on older clients.
    SPELL_UPDATE_CHARGES = function()
        chargeEpoch = chargeEpoch + 1
        if not RETAIL then Mark("cooldown") end
        Mark("count")
    end,
    LOSS_OF_CONTROL_ADDED = LossOfControl,
    LOSS_OF_CONTROL_UPDATE = LossOfControl,
    ACTIONBAR_UPDATE_USABLE = function() Mark("usable") end,
    -- Retail's ACTION_USABLE_CHANGED carries the affected action slots.
    SPELL_UPDATE_USABLE = (not RETAIL
        and function() Mark("usable") end) or nil,
    ACTION_USABLE_CHANGED = UsableChanged,
    PLAYER_TARGET_CHANGED = TargetChanged,
    ACTIONBAR_UPDATE_STATE = function() Mark("state") end,
    CURRENT_SPELL_CAST_CHANGED = function() Mark("state") end,
    START_AUTOREPEAT_SPELL = function() Mark("state") end,
    STOP_AUTOREPEAT_SPELL = function() Mark("state") end,
    TRADE_SKILL_SHOW = function() Mark("state") end,
    TRADE_SKILL_CLOSE = function() Mark("state") end,
    UPDATE_SHAPESHIFT_FORM = function()
        chargeEpoch = chargeEpoch + 1
        Mark("icon")
    end,
    SPELL_UPDATE_ICON = function()
        chargeEpoch = chargeEpoch + 1
        Mark("icon")
    end,
    SPELLS_CHANGED = function()
        chargeEpoch = chargeEpoch + 1
        Mark("icon")
    end,
    UPDATE_SUMMONPETS_ACTION = function()
        chargeEpoch = chargeEpoch + 1
        Mark("icon")
    end,
    BAG_UPDATE_DELAYED = function() Mark("count") end,
    PLAYER_EQUIPMENT_CHANGED = function()
        chargeEpoch = chargeEpoch + 1
        AB.MarkAll()
    end,
    PLAYER_ENTERING_WORLD = function()
        chargeEpoch = chargeEpoch + 1
        AB.MarkAll()
    end,
    PET_STABLE_UPDATE = function() AB.MarkAll() end,
    SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = Glow,
    SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = Glow,
    ACTION_RANGE_CHECK_UPDATE = RangeChanged,
    UPDATE_BINDINGS = Bindings,
    CVAR_UPDATE = CVarChanged,
    ACTIONBAR_SHOWGRID = function() AB.CursorChanged() end,
    ACTIONBAR_HIDEGRID = function() AB.CursorChanged() end,
    CURSOR_CHANGED = function() AB.CursorChanged() end,
    UPDATE_SHAPESHIFT_FORMS = function(...)
        chargeEpoch = chargeEpoch + 1
        FormsChanged(...)
    end,
    PLAYER_REGEN_ENABLED = RegenEnabled,
}
AB.EVENTS = EVENTS

-- Range checks and spell overlays can fire frequently in combat. Keep their
-- listeners absent when the matching paint feature is off; Refresh re-syncs
-- them after settings change without touching the stable event dispatcher.
local optionalEvents = {
    ACTION_RANGE_CHECK_UPDATE = true,
    SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = true,
    SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = true,
}
function AB.SyncOptionalEvents()
    local context = M.context
    for event in pairs(optionalEvents) do
        local wanted = event == "ACTION_RANGE_CHECK_UPDATE" and M.config.rangeColoring
            or event ~= "ACTION_RANGE_CHECK_UPDATE" and M.config.procGlow ~= 3
        if wanted then
            context:Event(event, EVENTS[event], true)
        else
            context:RemoveEvent(event)
        end
    end
end

-- Visibility edges: a shown bar repaints from live state; a hidden bar
-- releases its range checks and is skipped by every walk.
local function Shown(header)
    local bar = M.active and AB.headers[header]
    if bar then
        AB.MarkBar(bar)
        if bar.native then AB.RefreshNativeBar(bar) end
    end
end
local function Hidden(header)
    local bar = AB.headers[header]
    if not bar or not bar.owned then return end
    for i = 1, #bar.buttons do ReleaseRange(bar.buttons[i]) end
end

-- Page changes arrive from the restricted page handler, also in combat.
function AB.OnHeaderAttribute(bar, name, value)
    if not M.active then return end
    if name == "actionpage" and bar.index == 1 then
        AB.PageSlots(bar, value)
        AB.Remap()
        routingDirty = true
        AB.MarkBar(bar)
    elseif name == "state-vis" then
        AB.UpdateAlpha(bar)
    end
end

function AB.ShowTooltip(rec)
    local tip = GameTooltip
    if not tip or not rec.slot or not rec.filled then return end
    if GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(tip, rec.button)
    else
        tip:SetOwner(rec.button, "ANCHOR_RIGHT")
    end
    tip:SetAction(rec.slot)
end

local function CooldownDone(frame)
    local rec = AB.cooldownOwner and AB.cooldownOwner[frame]
    if rec and M.active and rec.filled then Cooldown(rec) end
end

function AB.StartDispatcher()
    local context = M.context
    AB.locActive = ActiveLossOfControl()
    for event, handler in pairs(EVENTS) do
        if not optionalEvents[event] then context:Event(event, handler, true) end
    end
    AB.SyncOptionalEvents()
    AB.cooldownOwner = AB.cooldownOwner or {}
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar and not bar.visHooked then
            bar.visHooked = true
            bar.header:HookScript("OnShow", Shown)
            bar.header:HookScript("OnHide", Hidden)
        end
    end
    for i = 1, #AB.owned do
        local rec = AB.owned[i]
        local cooldown = rec.button.cooldown
        if not rec.native and cooldown and not AB.cooldownOwner[cooldown] then
            AB.cooldownOwner[cooldown] = rec
            cooldown:HookScript("OnCooldownDone", CooldownDone)
        end
    end
    local bar = AB.bars[1]
    if bar then AB.PageSlots(bar, bar.header:GetAttribute("actionpage")) end
    AB.Remap()
    AB.MarkAll()
end

function AB.StopDispatcher()
    for event in pairs(EVENTS) do M.context:RemoveEvent(event) end
    for i = 1, #AB.owned do
        local rec = AB.owned[i]
        if not rec.native then
            ReleaseRange(rec)
            SetGlow(rec, false)
        end
    end
    for kind in pairs(dirty) do dirty[kind] = false end
    for slot in pairs(dirtySlots) do dirtySlots[slot] = nil end
    for bar in pairs(dirtyBars) do dirtyBars[bar] = nil end
    for bar in pairs(gridBars) do gridBars[bar] = nil end
    routingDirty, gridDirty = false, false
    AB.locActive = nil
end

-- Test and diagnostics hook: the number of suite range references held.
function AB.RangeReferences()
    local total = 0
    for _, count in pairs(rangeRefs) do total = total + count end
    return total
end
