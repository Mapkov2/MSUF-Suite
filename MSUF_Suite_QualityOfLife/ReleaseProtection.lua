local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }
local M = { dialogs = {} }
local MODIFIERS = { IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown }
local MODIFIER_NAMES = { SHIFT_KEY_TEXT, CTRL_KEY_TEXT, ALT_KEY_TEXT }
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

local function Release(self)
    local record = self.current
    self.current = nil
    self.context:RemoveEvent("MODIFIER_STATE_CHANGED")
    if record then
        record.hint:Hide()
        Lock(record, false)
    end
end

local function ZoneAllowed(config)
    local key = ZONE_KEYS[S.InstanceKind() or ""]
    return key ~= nil and config[key] == true
end

local function UpdateGate(self)
    local record = self.current
    if not record then return end
    local held = MODIFIERS[self.config.modifier]()
    Lock(record, not (S.Public(held) and held == true))
    -- The hint follows Blizzard's own visibility of the release button.
    local shown = record.button:IsShown()
    record.hint:SetShown(S.Public(shown) and shown == true)
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
    record.hint:SetText(S.Text("Hold %s to release spirit"):format(MODIFIER_NAMES[self.config.modifier]))
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
    Sync(self)
end

function M:Refresh() Sync(self) end
function M:Disable() Release(self) end

S.Install("releaseProtection", M)
