local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }
local M = { dialogs = {} }
local MODIFIERS = { IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown }
local MODIFIER_NAMES = { SHIFT_KEY_TEXT, CTRL_KEY_TEXT, ALT_KEY_TEXT }
-- The client's CVars naming the pad button that acts as each modifier.
local PAD_MODIFIER_CVARS = { "GamePadEmulateShift", "GamePadEmulateCtrl", "GamePadEmulateAlt" }
-- The pad's A (GAMEPAD_FACE_BOTTOM), which presses the dialog's first button.
local PAD_ACCEPT = "PAD1"
-- How long Release stays pressable after the pad's modifier was let go, and
-- how long the pad lock lasts on one dialog at most (both below).
local PAD_ARM_SECONDS, PAD_RESCUE_SECONDS = 3, 30
-- S.InstanceKind() -> the setting that switches protection on there.
local ZONE_KEYS = { world = "openWorld", party = "party", raid = "raid", pvp = "pvp" }

-- upstream/live and upstream/forever: Blizzard_StaticPopup_Game/Mainline/
-- GameDialogDefs.lua owns DEATH button 1, sets its enabled state every frame
-- and lays its buttons out. The lock only makes the button transparent and
-- click-through: no visibility, layout or Lua field of Blizzard's dialog is
-- written, so its layout and per-frame OnUpdate stay untainted, and falling,
-- encounter and aura locks, self-resurrection and the recap keep working.
-- The DEATH dialog has no Enter shortcut (StaticPopup_OnKeyDown).
local function Lock(record, locked)
    if record.locked == locked then return end
    local button = record.button
    if locked then
        local alpha, mouse = button:GetAlpha(), button:IsMouseEnabled()
        record.alpha = S.Public(alpha) and alpha or 1
        record.mouse = not S.Public(mouse) or mouse ~= false
        button:SetAlpha(0)
        button:EnableMouse(false)
    else
        button:SetAlpha(record.alpha)
        button:EnableMouse(record.mouse)
    end
    record.locked = locked
end

-- WoW Forever's Gamepad UI presses the dialog's first button on the pad's
-- bare A only: GamepadPopupHandler binds PAD1 to it (TryClickOrHoldButton ->
-- ClickPopupButton, Blizzard_StaticPopup/StaticPopupGamepad.lua), which
-- checks only button:IsShown() and :IsEnabled() before button:Click(), so a
-- transparent, click-through button still releases; and its binding group's
-- BlockEverything (Blizzard_GamepadSharedUtility/InputBindingStack/
-- BindingSetFactory.lua) binds SHIFT-PAD1, CTRL-PAD1 and CTRL-SHIFT-PAD1 to
-- nothing, while the Gamepad UI's triggers are those modifiers (LT Shift, RT
-- Ctrl, Blizzard_SharedXML/Shared/GamepadConstants.lua). A held modifier and
-- an A that reaches Release can therefore never come together there. So the
-- pad lock hides Release, and a press of the chosen modifier arms it: Release
-- shows while the modifier is held and for PAD_ARM_SECONDS after it is let
-- go, and the bare A in that window releases.
-- Blizzard's own dialog code sets every button's visibility again whenever
-- it shows a dialog (GameDialogMixin:SetupButtons, Blizzard_StaticPopup_Game/
-- GameDialog.lua), and DEATH changes only texts and enabled states while it
-- shows (GameDialogDefs.lua), so the unlock shows Release again only while
-- this dialog still shows DEATH. The pad lock needs the chosen modifier on
-- the pad (the client's GamePadEmulate<Key> CVar names a pad button):
-- without one a pad-only player could never arm it, and Release keeps
-- Blizzard's A press there. The Gamepad UI comes and goes with the input
-- device (INPUT_DEVICE_INTERFACE_TRANSITION, Forever's InputUtil.lua): the
-- lock follows at once, so the mouse UI shows Release while dead and the
-- Gamepad UI hides it.
-- A rescue keeps a pad-only player from being stuck whatever the pad does
-- (a remapped pad, a modifier that never arrives): PAD_RESCUE_SECONDS after
-- the pad lock began on a dialog it ends for that dialog, and the A press
-- releases as on Blizzard's own dialog.
local function PadButton(config)
    if not S.GamepadUI() then return nil end
    local button = C_CVar.GetCVar(PAD_MODIFIER_CVARS[config.modifier])
    if type(button) == "string" and button ~= "" and button ~= "none" then return button end
    return nil
end

local function Hide(record, hidden)
    local button, popup = record.button, record.popup
    if hidden and not record.hidden then
        record.hidden = true
        button:Hide()
    elseif not hidden and record.hidden then
        record.hidden = nil
        local shown = popup:IsShown()
        if S.Public(shown) and shown == true and popup.which == "DEATH" then button:Show() end
    end
end

local function Release(self)
    local record = self.current
    self.current = nil
    self.context:RemoveEvent("MODIFIER_STATE_CHANGED")
    self.context:Cancel(self.PadDisarm)
    self.context:Cancel(self.PadRescue)
    if record then
        record.hint:Hide()
        record.held, record.armed, record.padRescued, record.rescueArmed = nil, nil, nil, nil
        Lock(record, false)
        Hide(record, false)
    end
end

local function ZoneAllowed(config)
    local key = ZONE_KEYS[S.InstanceKind() or ""]
    return key ~= nil and config[key] == true
end

local function HintText(config, pad)
    if pad then
        return S.Text("Press %s, then %s to release spirit"):format(GetBindingText(pad, true),
            GetBindingText(PAD_ACCEPT, true))
    end
    return S.Text("Hold %s to release spirit"):format(MODIFIER_NAMES[config.modifier])
end

local function UpdateGate(self)
    local record = self.current
    if not record then return end
    local held = MODIFIERS[self.config.modifier]()
    held = S.Public(held) and held == true
    local padButton = PadButton(self.config)
    local pad = padButton ~= nil and not record.padRescued and padButton or nil
    if pad and held then
        record.armed = true
    elseif pad and record.held and record.armed then
        -- Let go: the window for the bare A starts (a restart moves it).
        self.context:After(PAD_ARM_SECONDS, self.PadDisarm)
    end
    record.held = held
    -- Rescued on the pad, Release is Blizzard's own again.
    local open = held or pad ~= nil and record.armed == true or padButton ~= nil and record.padRescued == true
    Lock(record, not open)
    -- The hint follows Blizzard's own visibility of the release button.
    local shown = record.hidden or record.button:IsShown()
    shown = S.Public(shown) and shown == true
    Hide(record, not open and shown and pad ~= nil)
    record.hint:SetText(HintText(self.config, pad))
    record.hint:SetShown(shown and not (padButton ~= nil and record.padRescued))
    if pad and not record.rescueArmed then
        record.rescueArmed = true
        self.context:After(PAD_RESCUE_SECONDS, self.PadRescue)
    end
end

local function Dialog(self, popup)
    local record = self.dialogs[popup]
    if record then return record end
    local button = popup:GetButton1()
    if NS.Safety.IsForbidden(button) then return nil end
    -- Not a region of the dialog: StaticPopupTemplate is a ResizeLayoutFrame
    -- (GameDialog.xml) that DEATH lays out every frame of its countdown
    -- (StaticPopup_OnUpdate), and the hint above it would make it taller.
    local holder = S.CreateFrame("Frame", nil, UIParent)
    local hint = S.CreateFontString(holder, nil, "OVERLAY")
    S.SetFont(hint, nil, 13, "OUTLINE")
    hint:SetPoint("BOTTOM", popup, "TOP", 0, 8)
    hint:SetJustifyH("CENTER")
    hint:SetTextColor(1, .82, 0)
    hint:SetWordWrap(true)
    hint:Hide()
    record = { button = button, hint = hint, holder = holder, popup = popup, locked = false }
    self.dialogs[popup] = record
    popup:HookScript("OnHide", function()
        if self.current == record then Release(self) end
    end)
    return record
end

local function Sync(self)
    local popup = self.active and ZoneAllowed(self.config) and StaticPopup_FindVisible("DEATH")
    if not popup or NS.Safety.IsForbidden(popup) then
        Release(self)
        return
    end
    local record = Dialog(self, popup)
    if not record then
        Release(self)
        return
    end
    if self.current ~= record then
        Release(self)
        self.current = record
        self.context:Event("MODIFIER_STATE_CHANGED", UpdateGate, IN_COMBAT)
    end
    record.holder:SetFrameStrata(popup:GetFrameStrata())
    record.hint:SetWidth(popup:GetWidth())
    S.SetFont(record.hint, nil, 13, "OUTLINE")
    UpdateGate(self)
end

-- The window after the modifier was let go has passed.
function M.PadDisarm(self)
    local record = self.current
    if not record or record.held then return end
    record.armed = nil
    UpdateGate(self)
end

function M.PadRescue(self)
    local record = self.current
    if not record then return end
    record.padRescued = true
    UpdateGate(self)
end

function M:Enable()
    if not self.hooked then
        hooksecurefunc("StaticPopup_Show", function(which)
            if self.active and (which == "DEATH" or self.current) then Sync(self) end
        end)
        self.hooked = true
    end
    self.context:Event("PLAYER_ENTERING_WORLD", Sync, IN_COMBAT)
    self.context:Event("ZONE_CHANGED_NEW_AREA", Sync, IN_COMBAT)
    if NS.Client.isForever then self.context:Event("INPUT_DEVICE_INTERFACE_TRANSITION", Sync, IN_COMBAT) end
    Sync(self)
end

function M:Refresh() Sync(self) end
function M:Disable() Release(self) end

S.Install("releaseProtection", M)
