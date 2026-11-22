local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }

-- Conceals Blizzard's main tooltip by alpha. GameTooltip:Hide() from addon
-- code would run GameTooltip_OnHide in the addon's context and leave the
-- fields it writes (waitingForData, infoList and others, GameTooltip.lua)
-- tainted for later builds. A concealed tooltip keeps working natively at
-- alpha 0 and gets its alpha back when it hides, when a later Show() no longer
-- matches a rule, or when it is cleared for new content (a reused tooltip
-- need not hide in between). A held reveal key
-- shows a tooltip the rules would hide. The same OnShow hook sets the
-- tooltip's scale percent with NS.TooltipScale, which composes it with
-- Blizzard's own scale and any Minimap hover scale; OnHide gives it back.
local M = {}
local TYPE_CHOICES = {
    { "hideItems", "Item" },
    { "hideSpells", "Spell" },
    { "hideUnits", "Unit" },
}
local SCALE_SOURCE = "tooltipVisibility"
-- revealModifier choice -> the key that shows hidden tooltips (false: none).
local REVEAL_KEYS = { false, IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown }
local concealedAlpha
local watching, rulesEnabled = false, false
local buildHooked, itemIconHooked
local Apply

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

local function RulesHide(tooltip)
    if Exempt(tooltip) then return false end
    local c = M.config
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

-- The reveal key is watched only while the rules hide a tooltip.
local function WatchReveal(hidden)
    local wanted = hidden and REVEAL_KEYS[M.config.revealModifier] and true or false
    if wanted == watching then return end
    watching = wanted
    if wanted then
        M.context:Event("MODIFIER_STATE_CHANGED", Apply, IN_COMBAT)
    else
        M.context:RemoveEvent("MODIFIER_STATE_CHANGED")
    end
end

local function RevealHeld()
    local key = REVEAL_KEYS[M.config.revealModifier]
    local held = key and key()
    return S.Public(held) and held == true
end

Apply = function()
    local tooltip = GameTooltip
    if not M.active or not rulesEnabled or not tooltip:IsShown() then return end
    local hidden = RulesHide(tooltip)
    WatchReveal(hidden)
    if hidden and not RevealHeld() then
        if concealedAlpha == nil then concealedAlpha = tooltip:GetAlpha() end
        tooltip:SetAlpha(0)
    else
        Reveal(tooltip)
    end
end

-- The scale is relative to Blizzard's own, which comes back with ReleaseScale
-- (the default percent changes nothing).
local function ApplyScale()
    NS.TooltipScale.Set(SCALE_SOURCE, M.config.scale)
end

local function ReleaseScale()
    NS.TooltipScale.Set(SCALE_SOURCE, nil)
end

local function Shown()
    if M.active then ApplyScale() end
    Apply()
end
local function Built(tooltip)
    if rulesEnabled and tooltip == GameTooltip then Apply() end
end

-- Post-calls run after the native item name was written. AppendText adds to
-- line one through the native API, without replacing its color or comparing
-- the item name. Ignore appended item sections and inaccessible headers.
local function ItemIcon(tooltip, data)
    if not M.config.itemHeaderIcon or NS.InCombat() or not S.Finite(data.id) or data.id <= 0
        or not tooltip.AppendText or not tooltip.GetPrimaryTooltipData then return end
    local primary = tooltip:GetPrimaryTooltipData()
    if not S.Public(primary) or not rawequal(primary, data) then return end
    local lines = data.lines
    if not S.Public(lines) or type(lines) ~= "table" or not canaccesstable(lines) then return end
    local name = lines[1]
    if not S.Public(name) or type(name) ~= "table" or not canaccesstable(name)
        or not S.Public(name.type) or name.type ~= Enum.TooltipDataLineType.ItemName
        or not S.Finite(name.lineIndex) or name.lineIndex ~= 1 or not S.PublicText(name.leftText) then return end
    local icon = C_Item.GetItemIconByID(data.id)
    if S.Finite(icon) and icon > 0 then tooltip:AppendText(("  |T%d:15:15|t"):format(icon)) end
end
-- The tooltip is Blizzard's again: its alpha, its scale, no reveal key watch.
local function Released(tooltip)
    Reveal(tooltip)
    ReleaseScale()
    WatchReveal(false)
end

-- OnTooltipCleared (SetOwner, ClearLines) starts new content, possibly on a
-- tooltip that never hid. New native data is classified by its post-call.
-- Plain SetText/AddLine content is visible again after a clear.
local function Cleared(tooltip)
    if concealedAlpha == nil or tooltip ~= GameTooltip then return end
    Reveal(tooltip)
    WatchReveal(false)
end

-- OnShow handles first display; native data post-calls handle a rebuild of an
-- already visible tooltip; OnTooltipCleared releases a concealed tooltip that
-- is reused for plain content. All registrations are inert while disabled.
function M:Enable()
    if not self.hooked then
        GameTooltip:HookScript("OnShow", Shown)
        GameTooltip:HookScript("OnHide", Released)
        GameTooltip:HookScript("OnTooltipCleared", Cleared)
        self.hooked = true
    end
    self:Refresh()
end

function M:Refresh()
    local c = self.config
    rulesEnabled = c.hideItems or c.hideSpells or c.hideUnits
    -- A scale-only profile has no work on each Blizzard tooltip rebuild.
    if rulesEnabled and not buildHooked then
        S.TooltipLines.Add(self, "AllTypes", Built)
        buildHooked = true
    elseif not rulesEnabled then
        Reveal(GameTooltip)
        WatchReveal(false)
    end
    if c.itemHeaderIcon and not itemIconHooked and C_Item and C_Item.GetItemIconByID then
        S.TooltipLines.Add(self, "Item", ItemIcon, true)
        itemIconHooked = true
    end
    if GameTooltip:IsShown() then ApplyScale() end
    Apply()
end

function M:Disable() Released(GameTooltip) end

S.Install("tooltipVisibility", M)
