local _, P = ...
local NS, S = P.NS, P.Suite

local M = { serial = 0 }

local function Invalidate(self)
    self.serial = self.serial + 1
end

local function Trusted(self, guid, name)
    local ok, _, _, relation = pcall(SocialQueueUtil_GetRelationshipInfo, guid, name)
    if not ok then return false end
    relation = S.PublicText(relation)
    return relation == "bnfriend" and self.config.battleNet
        or relation == "wowfriend" and self.config.wowFriends
        or relation == "guild" and self.config.guild
end

local function SafeToJoin()
    if NS.IsCombatLocked() then return false end
    local grouped = IsInGroup()
    if not S.Public(grouped) or grouped ~= false then return false end
    -- Blizzard adds a queue-loss warning to this popup. Keep that decision
    -- manual, along with quest-session and role-selection invitations.
    local ok, removesQueue = pcall(WillAcceptInviteRemoveQueues)
    return ok and S.Public(removesQueue) and removesQueue == false
end

local function AcceptVisible(self, serial, inviterName)
    if not self.active or serial ~= self.serial or not SafeToJoin() then return end
    local dialog = StaticPopup_FindVisible("PARTY_INVITE")
    if not S.Public(dialog) or not dialog or NS.Safety.IsForbidden(dialog) then return end
    local shown = dialog:IsShown()
    if not S.Public(shown) or shown ~= true
        or S.PublicText(dialog.which) ~= "PARTY_INVITE" then return end
    -- A previous invite can still own this popup when Blizzard has not yet
    -- displayed the new one. Match its visible inviter before clicking it.
    local ok, displayedText = pcall(function()
        return dialog:GetTextFontString():GetText()
    end)
    if not ok or not S.PublicText(displayedText)
        or not displayedText:find(inviterName, 1, true) then return end
    -- Blizzard's own click handler accepts the group, sets inviteAccepted and
    -- hides the dialog. Calling AcceptGroup + Hide separately would run its
    -- OnHide decline path unless we modified Blizzard's popup state.
    if not pcall(StaticPopup_OnClick, dialog, 1) then
        S.Print(S.Text("Automatic party invite acceptance was blocked; use Blizzard's dialog."))
    end
end

local function OnInvite(self, _, name, tank, healer, damage, _, _, guid, questSession)
    Invalidate(self)
    if not self.active or not S.PublicText(name) or not S.PublicText(guid)
        or not S.Public(tank) or tank ~= false
        or not S.Public(healer) or healer ~= false
        or not S.Public(damage) or damage ~= false
        or not S.Public(questSession) or questSession ~= false
        or not SafeToJoin() or not Trusted(self, guid, name) then return end
    local serial = self.serial
    -- The event may reach addons before Blizzard creates its native popup.
    C_Timer.After(0, function() AcceptVisible(self, serial, name) end)
end

function M:Enable()
    Invalidate(self)
    self.context:Event("PARTY_INVITE_REQUEST", OnInvite)
    self.context:Event("PARTY_INVITE_CANCEL", Invalidate)
end

function M:Refresh() Invalidate(self) end

function M:Disable()
    Invalidate(self)
    self.context:RemoveEvent("PARTY_INVITE_REQUEST")
    self.context:RemoveEvent("PARTY_INVITE_CANCEL")
end

S.Install("trustedPartyInvites", M)
