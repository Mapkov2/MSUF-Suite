local _, P = ...
local NS, S = P.NS, P.Suite
local M = { dialogs = {} }
local MODIFIERS = { IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown }
local MODIFIER_NAMES = { SHIFT_KEY_TEXT, CTRL_KEY_TEXT, ALT_KEY_TEXT }

-- upstream/live and upstream/forever: Blizzard_StaticPopup_Game/Mainline/
-- GameDialogDefs.lua owns DEATH button 1 and updates its enabled state every
-- frame. Gate visibility only; Blizzard retains falling/encounter/aura locks,
-- self-resurrection, recap and the release callback. No polling is needed.
local function SetShown(record, shown)
    record.writing = true
    record.button:SetShown(shown)
    record.writing = nil
end

local function Release(self)
    local record = self.current
    self.current = nil
    self.context:RemoveEvent("MODIFIER_STATE_CHANGED")
    if record then
        record.hint:Hide()
        SetShown(record, record.nativeShown)
    end
end

local function ZoneAllowed(config)
    local inInstance, kind = IsInInstance()
    if not S.Public(inInstance) or not S.Public(kind) then return false end
    if not inInstance then return config.openWorld end
    if kind == "raid" then return config.raid end
    if kind == "party" or kind == "scenario" then return config.party end
    if kind == "pvp" or kind == "arena" then return config.pvp end
    return false
end

local function UpdateGate(self)
    local record = self.current
    if not record then return end
    local held = MODIFIERS[self.config.modifier]()
    record.locked = not (S.Public(held) and held == true)
    SetShown(record, record.nativeShown and not record.locked)
    record.hint:SetShown(record.nativeShown)
end

-- Remember later native visibility requests while the Suite temporarily hides
-- the button. SetupButtons may run again on the same visible death dialog.
local function NativeVisibility(record, shown)
    if record.writing or M.current ~= record or not S.Public(shown) then return end
    record.nativeShown = shown == true
    record.hint:SetShown(record.nativeShown)
    if record.locked and record.nativeShown then SetShown(record, false) end
end

local function Dialog(self, popup)
    local record = self.dialogs[popup]
    if record then return record end
    local button = popup:GetButton1()
    if NS.Safety.IsForbidden(button) then return nil end
    local hint = S.CreateFontString(popup, nil, "OVERLAY")
    S.SetFont(hint, nil, 13, "OUTLINE")
    hint:SetPoint("BOTTOM", popup, "TOP", 0, 8)
    hint:SetJustifyH("CENTER")
    hint:SetTextColor(1, .82, 0)
    hint:SetWordWrap(true)
    hint:Hide()
    record = { button = button, hint = hint, popup = popup }
    self.dialogs[popup] = record
    hooksecurefunc(button, "Show", function() NativeVisibility(record, true) end)
    hooksecurefunc(button, "Hide", function() NativeVisibility(record, false) end)
    hooksecurefunc(button, "SetShown", function(_, shown) NativeVisibility(record, shown) end)
    popup:HookScript("OnHide", function()
        if self.current == record then Release(self) end
    end)
    return record
end

local function Sync(self)
    local popup = self.active and ZoneAllowed(self.config) and StaticPopup_FindVisible("DEATH")
    if not popup or NS.Safety.IsForbidden(popup) then Release(self); return end
    local record = Dialog(self, popup)
    if not record then Release(self); return end
    if self.current ~= record then
        Release(self)
        local shown = record.button:IsShown()
        if not S.Public(shown) then return end
        record.nativeShown = shown == true
        self.current = record
        self.context:Event("MODIFIER_STATE_CHANGED", UpdateGate, true)
    end
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
    self.context:Event("PLAYER_ENTERING_WORLD", Sync, true)
    self.context:Event("ZONE_CHANGED_NEW_AREA", Sync, true)
    Sync(self)
end

function M:Refresh() Sync(self) end
function M:Disable() Release(self) end

S.Install("releaseProtection", M)
