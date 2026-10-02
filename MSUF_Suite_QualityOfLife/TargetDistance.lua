local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end
local ID, M = "targetDistance", { probes = {}, values = {}, layout = {}, nextLayout = {} }
local Public, Finite = S.Public, S.Finite
local EMPTY = {}
local MAX_LINES, MAX_ITEMS = 20, 500

local function Field(data, key)
    if Public(data) and type(data) == "table" and Public(data[key]) then return data[key] end
end

local function AddProbe(sets, item)
    local spell = Field(item, "spellID")
    if not Finite(spell) or Field(item, "isPassive") ~= false or Field(item, "isOffSpec") ~= false then return end
    local known = C_SpellBook.IsSpellKnown(spell)
    if not Public(known) or known ~= true then return end
    local info = C_Spell.GetSpellInfo(spell)
    local minimum, maximum = Field(info, "minRange"), Field(info, "maxRange")
    if minimum ~= 0 or not Finite(maximum) or maximum <= 0 or maximum > 100 then return end
    local harmful, helpful = C_Spell.IsSpellHarmful(spell), C_Spell.IsSpellHelpful(spell)
    if Public(harmful) and harmful == true and not sets.harmful[maximum] then sets.harmful[maximum] = spell end
    if Public(helpful) and helpful == true and not sets.helpful[maximum] then sets.helpful[maximum] = spell end
end

-- The spellbook layout: per skill line its first slot and its size (false
-- while unreadable), into a reused array.
local function ReadLayout(layout)
    local count = C_SpellBook.GetNumSpellBookSkillLines()
    count = Finite(count) and math.min(count, MAX_LINES) or 0
    for line = 1, count do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        local offset, items = Field(info, "itemIndexOffset"), Field(info, "numSpellBookItems")
        layout[line * 2 - 1] = Finite(offset) and offset or false
        layout[line * 2] = Finite(items) and items or false
    end
    for index = count * 2 + 1, #layout do layout[index] = nil end
end

local function Discover(self)
    local sets, visited = { harmful = {}, helpful = {} }, 0
    local layout = self.layout
    ReadLayout(layout)
    for line = 1, #layout / 2 do
        local offset, items = layout[line * 2 - 1], layout[line * 2]
        if offset and items then
            for slot = offset + 1, offset + math.min(items, MAX_ITEMS - visited) do
                AddProbe(sets, C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player))
                visited = visited + 1
            end
        end
        if visited >= MAX_ITEMS then break end
    end
    self.sets = {}
    for kind, spells in pairs(sets) do
        local ordered = {}
        for distance, spell in pairs(spells) do ordered[#ordered + 1] = { spell = spell, distance = distance } end
        table.sort(ordered, function(a, b) return a.distance < b.distance end)
        self.sets[kind] = {}
        for i = 1, math.min(#ordered, 8) do self.sets[kind][i] = ordered[i] end
    end
end

local function RangeText(self)
    local lower, upper
    for spell, distance in pairs(self.probes) do
        local value = self.values[spell]
        if value == true then upper = math.min(upper or distance, distance)
        elseif value == false then lower = math.max(lower or distance, distance) end
    end
    if lower and upper and lower >= upper then return "--" end
    if lower and upper then return string.format("%g-%g", lower, upper) end
    if upper then return string.format("<=%g", upper) end
    if lower then return string.format(">%g", lower) end
    return "--"
end

local function Paint(self)
    local range = S.editMode and "10-30" or RangeText(self)
    local format = self.config.format or "{range} {unit}"
    local text = format:gsub("{range}", function() return range end)
        :gsub("{unit}", function() return S.Text("yd") end)
    if self.lastText ~= text then
        self.label:SetText(text)
        self.lastText = text
    end
    self.host:SetShown(self.active and (self.hasTarget or S.editMode) == true)
end

-- Below the target frame, the display copies that frame's position instead
-- of anchoring to it: MSUF's target frame is a secure unit button, and a
-- Suite frame anchored to it joins its protected layout. The copy is cold
-- work (Refresh and Edit Mode); a target change copies only while no rect
-- was available yet (a target frame that was never shown).
local function TargetOrigin(self)
    local frame = _G.MSUF_target or TargetFrame
    local x = frame:GetCenter()
    local bottom, scale, own = frame:GetBottom(), frame:GetEffectiveScale(), self.host:GetEffectiveScale()
    if not (Finite(x) and Finite(bottom) and Finite(scale) and Finite(own) and own > 0) then return nil end
    return x * scale / own, bottom * scale / own
end

local Place

-- The display follows the target frame when that frame moves (MSUF Edit
-- Mode, a profile switch): a probe from UIParent's corner to the frame's
-- bottom changes size with it, the way the CooldownManager watches MSUF's
-- frames. Only the probe anchors to the frame; the display stays anchored to
-- UIParent and is re-placed from the copied rect. The probe is attached
-- outside combat only.
local function Watch(self, frame)
    if self.watched == frame or NS.IsCombatLocked() then return end
    local probe = self.probe
    if not probe then
        probe = S.CreateFrame("Frame", nil, UIParent)
        probe:SetScript("OnSizeChanged", function()
            if M.active and M.config.attachTarget then Place(M) end
        end)
        self.probe = probe
    end
    probe:ClearAllPoints()
    if frame then
        probe:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT")
        probe:SetPoint("TOPRIGHT", frame, "BOTTOM")
    end
    self.watched = frame
end

Place = function(self, x, y)
    local c = self.config
    self.host:ClearAllPoints()
    self.placePending = nil
    Watch(self, c.attachTarget and (_G.MSUF_target or TargetFrame) or nil)
    if c.attachTarget then
        local originX, originY = TargetOrigin(self)
        if originX then
            self.host:SetPoint("TOP", UIParent, "BOTTOMLEFT", originX + (x or c.attachX), originY + (y or c.attachY))
            return
        end
        self.placePending = true
    end
    self.host:SetPoint("CENTER", UIParent, "CENTER", x or c.x, y or c.y)
end

local RangeEvent

-- Native range subscriptions follow the target's kind (harmful or helpful
-- probes); a new target of the same kind only reads the ranges again.
local function Subscribe(self, kind)
    if self.kind == kind then return end
    for spell in pairs(self.probes) do S.SetNativeSpellRange(ID, spell, false) end
    wipe(self.probes)
    wipe(self.values)
    self.kind = kind
    for _, probe in ipairs(kind and self.sets[kind] or EMPTY) do
        self.probes[probe.spell] = probe.distance
        S.SetNativeSpellRange(ID, probe.spell, true)
    end
    if next(self.probes) then self.context:Event("SPELL_RANGE_CHECK_UPDATE", RangeEvent, true)
    else self.context:RemoveEvent("SPELL_RANGE_CHECK_UPDATE") end
end

local function Release(self)
    Subscribe(self, nil)
end

RangeEvent = function(self, _, spell, inRange, checksRange)
    if not Finite(spell) or not self.probes[spell] then return end
    if Public(checksRange) and checksRange == true and Public(inRange) and type(inRange) == "boolean" then
        self.values[spell] = inRange
    else self.values[spell] = nil end
    Paint(self)
end

local function TargetKind()
    local enemy, friend = UnitCanAttack("player", "target"), UnitCanAssist("player", "target")
    if Public(enemy) and enemy == true then return "harmful" end
    if Public(friend) and friend == true then return "helpful" end
end

local function Sync(self)
    local exists = UnitExists("target")
    self.hasTarget = Public(exists) and exists == true
    Subscribe(self, self.hasTarget and self.active and not S.editMode and TargetKind() or nil)
    wipe(self.values)
    for spell in pairs(self.probes) do
        local value = C_Spell.IsSpellInRange(spell, "target")
        if Public(value) and type(value) == "boolean" then self.values[spell] = value end
    end
    if self.placePending then Place(self) end
    Paint(self)
end

local function DiscoverAgain(self)
    -- New probe sets replace the old subscriptions even for the same kind.
    Release(self)
    Discover(self)
    Sync(self)
end

-- A burst of spellbook events finds the probes once, on the next frame.
local function QueueDiscovery(self)
    self.discoveryJob:Request()
end

-- SPELLS_CHANGED also fires for spell overrides and procs, which leave the
-- spellbook layout as it is: the probes are found again only when the layout
-- changed. A new spec, a talent commit, a learned spell or a new world always
-- finds them again.
local function LayoutChanged(self)
    local layout, now = self.layout, self.nextLayout
    ReadLayout(now)
    if #now ~= #layout then return true end
    for index = 1, #now do
        if now[index] ~= layout[index] then return true end
    end
    return false
end

local function SpellsChanged(self)
    if LayoutChanged(self) then QueueDiscovery(self) end
end

local function SpecChanged(self, _, unit)
    if not Public(unit) or unit ~= nil and unit ~= "player" then return end
    QueueDiscovery(self)
end

local function Rediscover(self)
    QueueDiscovery(self)
end

function M:Enable()
    self.discoveryJob = self.context:Coalesce(0, DiscoverAgain)
    if not self.host then
        self.host = S.CreateFrame("Frame", "MSUFSuiteTargetDistance", UIParent)
        self.host:EnableMouse(false)
        self.label = S.CreateFontString(self.host, nil, "OVERLAY")
        self.label:SetAllPoints()
        self.label:SetWordWrap(false)
    end
    self.context:Event("SPELLS_CHANGED", SpellsChanged, true)
    self.context:Event("PLAYER_SPECIALIZATION_CHANGED", SpecChanged, true)
    self.context:Event("TRAIT_CONFIG_UPDATED", Rediscover, true)
    self.context:Event("LEARNED_SPELL_IN_SKILL_LINE", Rediscover, true)
    self.context:Event("PLAYER_ENTERING_WORLD", Rediscover, true)
    self.context:Event("PLAYER_TARGET_CHANGED", Sync, true)
    self.context:Event("UNIT_FACTION", Sync, false, "target")
    Discover(self)
    self:Refresh()
    -- One mover per placement: the free position, or offsets below the target frame.
    S.RegisterOwnedMover(ID, "distance", { label = "Target spell-range estimate", order = 648,
        getFrame = function() return self.host end, xKey = "x", yKey = "y", sizeKeys = { "width" },
        point = function() return "CENTER" end, quickPosition = true,
        visible = function() return not self.config.attachTarget end })
    S.RegisterOwnedMover(ID, "attached", { label = "Target spell-range estimate", order = 649,
        getFrame = function() return self.host end, xKey = "attachX", yKey = "attachY", sizeKeys = { "width" },
        point = function() return "TOP" end, quickPosition = true,
        place = function(x, y)
            Place(self, x, y)
            return true
        end,
        visible = function() return self.config.attachTarget end })
end

function M:Refresh()
    local c = self.config
    self.host:SetSize(c.width or 180, (c.fontSize or 16) + 8)
    self.host:SetScale((c.scale or 100) / 100)
    self.label:SetJustifyH(({ "LEFT", "CENTER", "RIGHT" })[c.align or 2])
    S.SetStyledFont(self.label, S.GlobalFontPath(), c.fontSize or 16, "OUTLINE", 1, true, 70, 1)
    self.label:SetTextColor(S.RGB(c.color))
    Place(self)
    Sync(self)
end

-- The context's Release drops a discovery still due.
function M:Disable()
    Release(self)
    if self.host then self.host:Hide() end
end

S.Install(ID, M)
