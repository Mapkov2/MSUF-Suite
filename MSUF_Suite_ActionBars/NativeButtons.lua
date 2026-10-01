local _, P = ...
local NS, S = P.NS, P.Suite
-- Blizzard's reused buttons (bars 2-8 on Retail). Blizzard paints them; the
-- suite only adds what its settings change: range tint, hidden empty
-- charge counts, cast highlight off, cooldown feedback, countdown numbers
-- and the pixel proc glow. Post-hooks on Blizzard's button code keep those
-- after Blizzard repaints; the walks (Flush.lua) call the Native* parts.
local AB = P.ActionBars
local M = AB.M
local Public = S.Public
local Dispatch = S.Dispatch
local Painter = AB.Painter
local api = Painter.api
local Tint, AcquireRange, Usable, CooldownFeedback = Painter.Tint, Painter.AcquireRange, Painter.Usable, Painter.CooldownFeedback
local GlowCheck, SetGlow = Painter.GlowCheck, Painter.SetGlow

local function NativeFeedback(rec)
    if AB.directDuration then
        if rec.feedback then CooldownFeedback(rec, false) end
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

local function NativeUsablePost(button)
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
    if rec and rec.native and M.active then
        if not M.config.castHighlight then NativeState(rec) end
        local checked = button:GetChecked()
        rec.decorChecked = Public(checked) and checked == true
        AB.UpdateDecorState(rec)
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
    if not rec or not rec.native or not M.active or M.config.procGlow == 1 then return end
    AB.SetNativeAlertAlpha(button, 0)
end

-- Blizzard runs these post-hooks inside its own call chains (button
-- updates, the alert manager): each runs isolated, so an error is reported
-- and never stops Blizzard's caller.
local function NativeUsableHook(button) Dispatch(NativeUsablePost, button) end
local function NativeStateHook(button) Dispatch(NativeStatePost, button) end
local function NativeCountdownHook(button) Dispatch(NativeCountdownPost, button) end
local function NativeAlertHook(manager, button) Dispatch(NativeAlertPost, manager, button) end

-- Post-hooks on Blizzard's shared button code (both clients define both),
-- installed with the first reused bar; both only touch reused buttons.
local function HookNativeShared()
    if AB.nativeSharedHooked then return end
    AB.nativeSharedHooked = true
    hooksecurefunc("ActionButton_UpdateCooldownNumberHidden", NativeCountdownHook)
    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", NativeAlertHook)
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
    if not rec.nativeHooks then
        rec.nativeHooks = true
        hooksecurefunc(rec.button, "UpdateUsable", NativeUsableHook)
        hooksecurefunc(rec.button, "UpdateState", NativeStateHook)
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
    HookNativeShared()
    for i = 1, #bar.buttons do RefreshNativeButton(bar.buttons[i]) end
end

function AB.RefreshNative()
    for index = 2, 8 do
        AB.RefreshNativeBar(AB.bars[index])
    end
end

-- A range color change: buttons tinted out of range take the new color.
local function Retint(rec)
    if rec.outOfRange then
        rec.tint = nil
        Tint(rec)
    end
end

AB.NativeButtons = {
    Feedback = NativeFeedback, Count = NativeCount, State = NativeState, Color = NativeColor, Retint = Retint,
}
