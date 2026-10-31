local _, P = ...
local NS, S = P.NS, P.Suite
-- Blizzard's reused buttons (bars 2-8 on Retail). Blizzard paints them; the
-- suite only adds what its settings change: range tint, hidden empty
-- charge counts, cast highlight off, cooldown feedback, countdown numbers
-- and the pixel proc glow. Post-hooks on Blizzard's button code keep those
-- after Blizzard repaints; the walks (Flush.lua) call the Native* parts.
local AB = P.ActionBars
local M = AB.M
local Public, IsSecret = S.Public, NS.IsSecret
local Dispatch = S.Dispatch
local Painter = AB.Painter
local api = Painter.api
local PROC_BLIZZARD, PROC_PIXEL = AB.ENUM.PROC_GLOW.BLIZZARD, AB.ENUM.PROC_GLOW.PIXEL
local OUT_OF_RANGE = S.USABLE.OUT_OF_RANGE
local Tint, AcquireRange, Usable, CooldownFeedback = Painter.Tint, Painter.AcquireRange, Painter.Usable, Painter.CooldownFeedback
local GlowCheck, SetGlow = Painter.GlowCheck, Painter.SetGlow
local cooldownOwners = {}

local function InvalidateFeedback(rec)
    rec.feedbackInactive, rec.feedbackNeutral, rec.feedbackSlot = nil, nil, nil
end

-- 2026-10-26 M+ trace: neutral native buttons paid five C calls per walk.
-- SpellSharedDocumentation marks all three isActive fields NeverSecret;
-- time fields may still be secret. GCD activity stays on the old path.
local function NativeCooldownPost(rec, info, chargeInfo, lossInfo)
    local active, chargeActive, lossActive
    if not IsSecret(info) and type(info) == "table" then active = info.isActive end
    local inactive = not IsSecret(active) and active == false
    if inactive then
        if not IsSecret(chargeInfo) and type(chargeInfo) == "table" then chargeActive = chargeInfo.isActive end
        inactive = not IsSecret(chargeActive) and chargeActive == false
    end
    if inactive then
        if not IsSecret(lossInfo) and type(lossInfo) == "table" then lossActive = lossInfo.isActive end
        inactive = not IsSecret(lossActive) and lossActive == false
    end
    if not inactive or rec.feedbackSlot ~= rec.slot then rec.feedbackNeutral = nil end
    rec.feedbackInactive, rec.feedbackSlot = inactive, rec.slot
end

local function NativeInvalidatePost(button)
    local rec = AB.records[button]
    if rec and rec.native then InvalidateFeedback(rec) end
end

local function NativeFeedback(rec)
    if AB.directDuration then
        if rec.feedback then CooldownFeedback(rec, false) end
        return
    end
    if rec.feedbackInactive and rec.feedbackSlot == rec.slot then
        if not rec.feedbackNeutral then
            CooldownFeedback(rec, false)
            rec.feedbackNeutral = true
        end
        return
    end
    -- A replacing loss-of-control effect shows instead of the cooldown.
    if AB.locActive then
        local loss = api.LoC(rec.slot)
        local shown = loss and loss.isActive
        if Public(shown) and shown and Public(loss.shouldReplaceNormalCooldown)
            and loss.shouldReplaceNormalCooldown then
            CooldownFeedback(rec, false)
            return
        end
    end
    CooldownFeedback(rec, true)
end

local function NativeCount(rec)
    local count = rec.button.Count
    if not count then return end
    if not M.config.hideEmptyCharges then
        count:SetAlpha(1)
        return
    end
    local charges = api.Charges(rec.slot)
    local readable = Public(charges) and type(charges) == "table"
    local maximum, current = readable and charges.maxCharges, readable and charges.currentCharges
    count:SetAlpha((Public(maximum) and type(maximum) == "number" and maximum > 1
        and Public(current) and current == 0) and 0 or 1)
end

local function NativeState(rec)
    if not M.config.castHighlight then rec.button:SetChecked(false) end
end

local function NativeUsablePost(button, usable, noMana)
    local rec = AB.records[button]
    if not rec or not rec.native or not M.active then return end
    -- Blizzard paints the state now: the cached one is old until the suite
    -- reads it again below (the preview asks, S.ActionBarPreviewTint).
    rec.usable = nil
    -- Level-link usability paint can desaturate an inactive icon again.
    rec.feedbackNeutral = nil
    -- Blizzard has already painted usable state. Only an active range
    -- override needs reapplying; another IsUsableAction call here would
    -- duplicate the native call on every usable update.
    if rec.bar.paintDormant then return end
    if rec.outOfRange then
        rec.tint = nil
        Tint(rec)
    elseif AB.style.customTints then
        -- Custom usability colors: Blizzard's payload says which one, so
        -- only an update without payload (it read the answer itself) asks again.
        rec.tint = nil
        if noMana == nil then usable = nil end
        Usable(rec, usable, noMana)
    end
end

local function CatchUpState(rec)
    if not M.config.castHighlight then NativeState(rec) end
    local checked = rec.button:GetChecked()
    rec.decorChecked = Public(checked) and checked == true
    AB.UpdateDecorState(rec)
    rec.nativeStateDirty = nil
end

local function NativeStatePost(button)
    local rec = AB.records[button]
    if rec and rec.native and M.active then
        -- Native state keeps changing while a mouseover bar is faded. Its
        -- decoration catches up in the existing synchronous reveal pass.
        if rec.bar.paintDormant then
            rec.nativeStateDirty = true
            return
        end
        CatchUpState(rec)
    end
end

local function NativeCountdownPost(button)
    local rec = AB.records[button]
    if rec and rec.native and M.active then
        button.cooldown:SetHideCountdownNumbers(not M.config.cooldownNumbers)
    end
end

-- Blizzard creates a reused button's spell alert on its first proc, after
-- the style pass set the alert's opacity, and shows it on every proc. With
-- the Pixel border or None glow the alert stays invisible, the one on the
-- assisted-combat rotation frame included; the manager's own tables are
-- never written.
local function NativeAlertPost(_, button)
    local rec = AB.records[button]
    if rec and M.active then AB.RaiseDecoration(rec) end
    if not rec or not rec.native or not M.active or M.config.procGlow == PROC_BLIZZARD then return end
    AB.SetNativeAlertAlpha(button, 0)
end

-- Blizzard runs these post-hooks inside its own call chains (button
-- updates, the alert manager): each runs isolated, so an error is reported
-- and never stops Blizzard's caller.
local function NativeUsableHook(button, _, usable, noMana) Dispatch(NativeUsablePost, button, usable, noMana) end
local function NativeStateHook(button) Dispatch(NativeStatePost, button) end
local function NativeCountdownHook(button) Dispatch(NativeCountdownPost, button) end
local function NativeAlertHook(manager, button) Dispatch(NativeAlertPost, manager, button) end
local function NativeCooldownHook(normal, info, charge, chargeInfo, loss, lossInfo)
    if not M.active or AB.directDuration or AB.nativeFeedbackVisible == false or IsSecret(normal) then return end
    local rec = cooldownOwners[normal]
    if rec and not rec.bar.paintDormant then Dispatch(NativeCooldownPost, rec, info, chargeInfo, lossInfo) end
end
local function NativeInvalidateHook(button) Dispatch(NativeInvalidatePost, button) end

-- Shared button hooks, present on both clients and installed with the first
-- reused bar; foreign cooldowns never enter the isolated observer.
local function HookNativeShared()
    if AB.nativeSharedHooked then return end
    AB.nativeSharedHooked = true
    hooksecurefunc("ActionButton_UpdateCooldownNumberHidden", NativeCountdownHook)
    hooksecurefunc("ActionButton_ApplyCooldown", NativeCooldownHook)
    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", NativeAlertHook)
end

local function NativeColor(rec)
    local wasRangeTint = rec.tint == OUT_OF_RANGE
    AcquireRange(rec)
    if M.config.rangeColoring or wasRangeTint or AB.style.customTints then
        rec.tint = nil
        Usable(rec)
    end
end

local function RefreshNativeButton(rec)
    InvalidateFeedback(rec)
    cooldownOwners[rec.button.cooldown] = rec
    if not rec.nativeHooks then
        rec.nativeHooks = true
        hooksecurefunc(rec.button, "UpdateUsable", NativeUsableHook)
        hooksecurefunc(rec.button, "UpdateState", NativeStateHook)
        -- UpdateAction owns slot/page changes, including forced same-slot
        -- replacements. A post-hook discards any earlier paint in that call.
        hooksecurefunc(rec.button, "UpdateAction", NativeInvalidateHook)
        rec.button:HookScript("OnShow", NativeInvalidateHook)
    end
    NativeColor(rec)
    NativeCount(rec)
    if rec.nativeStateDirty and M.active and not rec.bar.paintDormant then
        Dispatch(CatchUpState, rec)
    else
        NativeState(rec)
    end
    NativeFeedback(rec)
    if M.config.procGlow == PROC_PIXEL then
        GlowCheck(rec)
    else
        SetGlow(rec, false)
    end
end

function AB.RefreshNativeBar(bar)
    if not bar or not bar.native then return end
    HookNativeShared()
    for i = 1, #bar.buttons do RefreshNativeButton(bar.buttons[i]) end
end

function AB.RefreshNative()
    for index = 2, 8 do
        AB.RefreshNativeBar(AB.bars[index])
    end
end

-- A color change (range or usability): a tinted button takes the new colors.
-- A suite button knows its usability (rec.usable); a reused Blizzard button
-- reads it once, and only when the suite tints it at all.
local function Retint(rec)
    if rec.native and rec.tint == nil and not AB.style.customTints then return end
    rec.tint = nil
    if rec.native then Usable(rec) else Tint(rec) end
end

AB.NativeButtons = {
    Feedback = NativeFeedback, Count = NativeCount, State = NativeState, Color = NativeColor, Retint = Retint,
}
