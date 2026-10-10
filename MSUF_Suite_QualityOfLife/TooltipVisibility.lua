local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }

-- Conceals Blizzard's main tooltip by alpha. GameTooltip:Hide() from addon
-- code would run GameTooltip_OnHide in the addon's context and leave the
-- fields it writes (waitingForData, infoList and others, GameTooltip.lua)
-- tainted for later builds. A concealed tooltip keeps working natively at
-- alpha 0 and gets its alpha back when it hides, when a later Show() no longer
-- matches a rule, or when it is cleared for new content that no rule keeps
-- concealed (a reused tooltip need not hide in between).
local M = {}
local TYPE_CHOICES = {
    { "hideItems", "Item" },
    { "hideSpells", "Spell" },
    { "hideUnits", "Unit" },
}
local concealedAlpha

local function MatchesType(tooltip, kind)
    local matches = tooltip:IsTooltipType(Enum.TooltipDataType[kind])
    return S.Public(matches) and matches == true
end

local function Exempt(tooltip)
    -- GameTooltip is shared. MSUF's own unit/group visibility mode owns it
    -- until MSUF clears this marker on hide (also when another owner reuses it).
    if tooltip._msufUnitTooltipOwner ~= nil then return true end
    -- Clickable aura reminders show their item or spell here and have their
    -- own tooltip switch.
    local owner = tooltip:GetOwner()
    if owner and not NS.Safety.IsForbidden(owner) then
        local reminder = owner._msufA3CastTooltip
        return S.Public(reminder) and reminder == true
    end
    return false
end

-- PLAYER_REGEN_DISABLED arrives before InCombatLockdown() turns true. plain:
-- the tooltip holds no Blizzard data, so only the state rules can apply.
local function ShouldConceal(tooltip, event, plain)
    if Exempt(tooltip) then return false end
    local c = M.config
    if c.inCombat and NS.InCombat(event) then return true end
    if c.inInstances then
        local inInstance = IsInInstance()
        if S.Public(inInstance) and inInstance == true then return true end
    end
    if plain then return false end
    for i = 1, #TYPE_CHOICES do
        local choice = TYPE_CHOICES[i]
        if c[choice[1]] and MatchesType(tooltip, choice[2]) then return true end
    end
    return false
end

local function Reveal(tooltip)
    if concealedAlpha == nil then return end
    if tooltip:GetAlpha() == 0 then tooltip:SetAlpha(concealedAlpha) end
    concealedAlpha = nil
end

local function Apply(event, plain)
    local tooltip = GameTooltip
    if not M.active or not tooltip:IsShown() then return end
    if ShouldConceal(tooltip, event, plain) then
        if concealedAlpha == nil then concealedAlpha = tooltip:GetAlpha() end
        tooltip:SetAlpha(0)
    else
        Reveal(tooltip)
    end
end

local function Shown() Apply() end
local function Built(tooltip)
    if tooltip == GameTooltip then Apply() end
end
local function StateChanged(_, event) Apply(event) end

-- OnTooltipCleared (SetOwner, ClearLines) starts new content, possibly on a
-- tooltip that never hid. Blizzard data announces itself again through the
-- post-call; plain SetText/AddLine content does not, so a concealed tooltip is
-- judged by the state rules alone here. A tooltip that is not concealed needs
-- nothing: the state events conceal it when a rule begins.
local function Cleared(tooltip)
    if concealedAlpha ~= nil and tooltip == GameTooltip then Apply(nil, true) end
end

local function WantEvent(context, event, wanted)
    if wanted then context:Event(event, StateChanged, IN_COMBAT) else context:RemoveEvent(event) end
end

-- OnShow handles first display; native data post-calls handle a rebuild of an
-- already visible tooltip; OnTooltipCleared releases a concealed tooltip that
-- is reused for plain content. All registrations are inert while disabled.
function M:Enable()
    if not self.hooked then
        GameTooltip:HookScript("OnShow", Shown)
        S.TooltipLines.Add(self, "AllTypes", Built)
        GameTooltip:HookScript("OnHide", Reveal)
        GameTooltip:HookScript("OnTooltipCleared", Cleared)
        self.hooked = true
    end
    self:Refresh()
end

function M:Refresh()
    local c, context = self.config, self.context
    WantEvent(context, "PLAYER_REGEN_DISABLED", c.inCombat)
    WantEvent(context, "PLAYER_REGEN_ENABLED", c.inCombat)
    WantEvent(context, "PLAYER_ENTERING_WORLD", c.inInstances)
    WantEvent(context, "ZONE_CHANGED_NEW_AREA", c.inInstances)
    Apply()
end

function M:Disable() Reveal(GameTooltip) end

S.Install("tooltipVisibility", M)
