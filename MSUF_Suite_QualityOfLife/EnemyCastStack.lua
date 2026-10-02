local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }
if NS.Client.isForever then return end
local ID = "enemyCastStack"
local Public = S.Public
local GAP, ICON_GAP, STRIPE_WIDTH, TIME_WIDTH, FADE, FALLBACK_ICON = 3, 4, 3, 44, .4, 134400
local DIM, RANGE_TICK = .45, .25
-- Blizzard's raid marker sheet: 4 x 4 cells, markers 1-8 (TargetFrame.lua).
local MARKER_SHEET, MARKER_ROWS, MARKER_COLUMNS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons", 4, 4
local EMPTY = {}
-- Cast kinds, and the settings' choices (MSUF_Suite/Core/Catalog/
-- QualityOfLifeHUD.lua): castKinds lists casts and channels, casts or
-- channels; readyStyle marks with a stripe or the whole bar; growth adds new
-- casts below or above the last.
local CAST, CHANNEL = 1, 2
local ALL_KINDS, CASTS_ONLY, CHANNELS_ONLY = 1, 2, 3
local READY_WHOLE_BAR, GROW_UP = 2, 2
-- entries: one reused record per nameplate token; ordered: the live casts,
-- oldest first. A row belongs to an entry while that entry has a free slot.
local M = { entries = {}, ordered = {}, rows = {}, free = {}, previews = {}, wakes = {}, candidates = {},
    castRGB = {}, priorityRGB = {}, lockedRGB = {}, stripeRGB = {}, visible = 0 }

-- 12.1 nameplate tokens run from nameplate1 to nameplate150 (UnitSharedDocumentation).
local PLATES, PLATE_TOKENS = {}, {}
for i = 1, 150 do
    PLATE_TOKENS[i] = "nameplate" .. i
    PLATES[PLATE_TOKENS[i]] = true
end
local START = { UNIT_SPELLCAST_START = CAST, UNIT_SPELLCAST_CHANNEL_START = CHANNEL,
    UNIT_SPELLCAST_EMPOWER_START = CHANNEL }
local STOP = { NAME_PLATE_UNIT_REMOVED = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true }
local RETIME = { UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_UPDATE = true,
    UNIT_SPELLCAST_EMPOWER_UPDATE = true }
local LOCK = { UNIT_SPELLCAST_INTERRUPTIBLE = true, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true }
local CAST_EVENTS = { "NAME_PLATE_UNIT_ADDED" }
for _, set in ipairs({ START, STOP, RETIME, LOCK }) do
    for event in pairs(set) do CAST_EVENTS[#CAST_EVENTS + 1] = event end
end
-- Public spell records (nether.wowhead.com/tooltip/spell/<id>, 2026-09-30).
-- Spell-book membership selects the current talents/spec and active pet.
local INTERRUPTS = {
    DEATHKNIGHT = { 47528 }, DEMONHUNTER = { 183752 }, DRUID = { 106839, 78675 },
    EVOKER = { 351338 }, HUNTER = { 147362, 187707 }, MAGE = { 2139 }, MONK = { 116705 },
    PALADIN = { 96231, 31935 }, PRIEST = { 15487 }, ROGUE = { 1766 }, SHAMAN = { 57994 },
    WARLOCK = { 19647, 89766 }, WARRIOR = { 6552, 386071 },
}
-- Edit Mode samples: spells every client knows, named in the reader's language.
local SAMPLES = {
    { spell = 116, fraction = .58, left = 1.7, marker = 3 },
    { spell = 15407, fraction = .27, left = 3.4, important = true },
    { spell = 188196, fraction = .83, left = .5, locked = true, marker = 1, far = true },
    { spell = 348, fraction = .14, left = 2.9 },
}
local samplesReady
local OnWake

local function Samples()
    if samplesReady then return SAMPLES end
    samplesReady = true
    local targets = { S.PublicText(UnitName("player")), TANK, HEALER, DAMAGER }
    for index, sample in ipairs(SAMPLES) do
        local info = C_Spell.GetSpellInfo(sample.spell)
        if not Public(info) or type(info) ~= "table" then info = nil end
        sample.name = info and S.PublicText(info.name) or tostring(sample.spell)
        sample.icon = info and S.Finite(info.iconID) and info.iconID or FALLBACK_ICON
        sample.target = targets[index]
    end
    return SAMPLES
end

------------------------------------------------------------------ interrupt readiness
local function Candidates(self)
    local list, c = self.candidates, self.config
    for i = #list, 1, -1 do list[i] = nil end
    -- The ready mark and range dimming both ask the player's interrupt.
    if not (c.readyStripe or c.dimOutOfRange) then return end
    if c.interruptSpellID > 0 then
        list[1] = c.interruptSpellID
        return
    end
    local _, class = UnitClass("player")
    for _, spell in ipairs(INTERRUPTS[S.PublicText(class) or ""] or EMPTY) do
        local own = C_SpellBook.IsSpellKnown(spell, Enum.SpellBookSpellBank.Player)
        local pet = C_SpellBook.IsSpellKnown(spell, Enum.SpellBookSpellBank.Pet)
        if Public(own) and own == true or Public(pet) and pet == true then list[#list + 1] = spell end
    end
end

-- The client sends no event when a cooldown ends (CooldownViewer.lua,
-- TriggerAvailableAlert), so an invisible cooldown reports that moment.
local function Wake(self, index)
    local wake = self.wakes[index]
    if wake then return wake end
    wake = S.CreateFrame("Cooldown", nil, self.host)
    wake:SetPoint("TOPLEFT", self.host, "TOPLEFT")
    wake:SetSize(1, 1)
    wake:SetAlpha(0)
    wake:SetDrawSwipe(false)
    wake:SetDrawEdge(false)
    wake:SetDrawBling(false)
    wake:SetHideCountdownNumbers(true)
    wake:SetScript("OnCooldownDone", OnWake)
    self.wakes[index] = wake
    return wake
end

-- The cooldown without the global cooldown: none, or a readable inactive one.
local function OnlyGCD(duration)
    if not duration then return true end
    if duration:HasSecretValues() then return false end
    local running = duration:IsActive()
    return Public(running) and running == false
end

-- A spell that waits only for the global cooldown counts as ready. isActive
-- and isOnGCD are never secret (SpellSharedDocumentation), but isOnGCD can be
-- trusted only inside SPELL_UPDATE_COOLDOWN (cooldownEvent); elsewhere the
-- cooldown without the GCD answers, as in CombatMovementCue.
local function SampleReady(self, cooldownEvent)
    local ready, list = false, self.candidates
    for index = 1, #list do
        local spell = list[index]
        local info = C_Spell.GetSpellCooldown(spell)
        local active, gcd = info and info.isActive, cooldownEvent and info and info.isOnGCD
        local wake = Wake(self, index)
        if Public(active) and active == false or Public(gcd) and gcd == true then
            ready = true
            wake:Clear()
        else
            local duration = C_Spell.GetSpellCooldownDuration(spell, true)
            if not cooldownEvent and OnlyGCD(duration) then
                ready = true
                wake:Clear()
            elseif duration then
                wake:SetCooldownFromDurationObject(duration, true)
            else
                wake:Clear()
            end
        end
    end
    for index = #list + 1, #self.wakes do self.wakes[index]:Clear() end
    self.ready = ready
end

local function SetStripe(row, on)
    if row.stripeOn ~= on then
        row.stripe:SetShown(on)
        row.stripeOn = on
    end
end

local function PaintStripe(self, entry)
    local c, row = self.config, entry.row
    local on = self.ready == true and c.readyStripe == true and c.readyStyle ~= READY_WHOLE_BAR
    -- Secret or not, the interrupt state goes straight to the native alpha sink.
    if on then row.stripe:SetAlphaFromBoolean(entry.locked, 0, 1) end
    SetStripe(row, on)
end

local PaintColor

-- The ready mark is either the edge stripe or the bar color itself.
local function PaintReady(self, entry)
    PaintStripe(self, entry)
    local c = self.config
    if c.readyStripe and c.readyStyle == READY_WHOLE_BAR then PaintColor(self, entry) end
end

local function PaintStripes(self)
    for i = 1, self.visible do PaintReady(self, self.ordered[i]) end
end

------------------------------------------------------------------ rows
-- Cold style: sizes, fonts and text anchors change only in Refresh.
local function Style(self, row)
    local c, font = self.config, S.GlobalFontPath()
    local height = c.rowHeight
    row:SetSize(c.width - height - ICON_GAP, height)
    row.icon:SetSize(height, height)
    row.stripe:SetColorTexture(self.stripeRGB[1], self.stripeRGB[2], self.stripeRGB[3])
    row.marker:SetSize(math.floor(height * .55 + .5), math.floor(height * .55 + .5))
    S.SetStyledFont(row.name, font, c.fontSize, "OUTLINE", 1, true, 70, 1)
    S.SetStyledFont(row.target, font, math.max(8, c.fontSize - 2), "OUTLINE", 1, true, 70, 1)
    S.SetStyledFont(row.time, font, c.fontSize, "OUTLINE", 1, true, 70, 1)
    row.name:ClearAllPoints()
    if c.targetLine then
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -2)
        row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -TIME_WIDTH, -2)
    else
        row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -TIME_WIDTH, 0)
    end
    row.target:SetShown(c.targetLine == true)
    row.slot = nil
end

local function NewRow(self, list)
    local row = S.CreateFrame("StatusBar", nil, self.host)
    row:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.back = S.CreateTexture(row, nil, "BACKGROUND")
    row.back:SetAllPoints(row)
    row.back:SetColorTexture(.04, .05, .07, .88)
    row.icon = S.CreateTexture(row, nil, "ARTWORK")
    row.icon:SetPoint("RIGHT", row, "LEFT", -ICON_GAP, 0)
    row.stripe = S.CreateTexture(row, nil, "OVERLAY")
    row.stripe:SetPoint("TOPLEFT", row, "TOPLEFT")
    row.stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
    row.stripe:SetWidth(STRIPE_WIDTH)
    row.stripe:Hide()
    row.stripeOn = false
    -- A raid marker badge on the spell icon's corner.
    row.marker = S.CreateTexture(row, nil, "OVERLAY")
    row.marker:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -2, 2)
    row.marker:SetTexture(MARKER_SHEET)
    row.marker:Hide()
    row.name = S.CreateFontString(row, nil, "OVERLAY")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.target = S.CreateFontString(row, nil, "OVERLAY")
    row.target:SetJustifyH("LEFT")
    row.target:SetWordWrap(false)
    row.target:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 2)
    row.target:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -TIME_WIDTH, 2)
    row.time = S.CreateFontString(row, nil, "OVERLAY")
    row.time:SetJustifyH("RIGHT")
    row.time:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.time:SetWidth(TIME_WIDTH - 6)
    row.binding = C_DurationUtil.CreateDurationTextBinding()
    row.binding:SetFontString(row.time)
    row.binding:SetFormatter(self.formatter)
    row.binding:SetUpdateInterval(.1)
    row:Hide()
    Style(self, row)
    list[#list + 1] = row
    return row
end

-- Anchor only; used when a row changes slot.
local function Place(self, row, slot)
    local c = self.config
    local offset, x = (slot - 1) * (c.rowHeight + GAP), c.rowHeight + ICON_GAP
    row:ClearAllPoints()
    if c.growth == GROW_UP then
        row:SetPoint("BOTTOMLEFT", self.host, "BOTTOMLEFT", x, offset)
    else
        row:SetPoint("TOPLEFT", self.host, "TOPLEFT", x, -offset)
    end
    row.slot = slot
end

PaintColor = function(self, entry)
    local c, locked, isLocked = self.config, self.lockedRGB, entry.locked
    local Evaluate = C_CurveUtil.EvaluateColorValueFromBoolean
    local r, g, b
    if self.ready == true and c.readyStripe and c.readyStyle == READY_WHOLE_BAR then
        -- Whole-bar ready mark: every interruptible cast takes the ready color.
        local ready = self.stripeRGB
        r, g, b = ready[1], ready[2], ready[3]
    else
        local cast, priority, important = self.castRGB, self.priorityRGB, entry.important
        r = Evaluate(important, priority[1], cast[1])
        g = Evaluate(important, priority[2], cast[2])
        b = Evaluate(important, priority[3], cast[3])
    end
    entry.row:SetStatusBarColor(Evaluate(isLocked, locked[1], r), Evaluate(isLocked, locked[2], g),
        Evaluate(isLocked, locked[3], b))
end

-- One alpha writer per row: range dimming scales the importance fade or hide.
local function PaintAlpha(self, entry)
    local c, row = self.config, entry.row
    local base = entry.dim and DIM or 1
    if c.onlyImportant then
        row:SetAlphaFromBoolean(entry.important, base, 0)
    elseif c.fadeMinor then
        row:SetAlphaFromBoolean(entry.important, base, base * FADE)
    else
        row:SetAlpha(base)
    end
end

-- Public answers only: a cast dims when every interrupt reports false; a
-- secret or missing answer (no range check possible) leaves it undimmed.
local function OutOfRange(self, unit)
    local list = self.candidates
    if #list == 0 then return false end
    for i = 1, #list do
        local value = C_Spell.IsSpellInRange(list[i], unit)
        if not Public(value) or value ~= false then return false end
    end
    return true
end

-- GetRaidTargetIndex is secret (RaidMarkersDocumentation); the sprite-sheet
-- cell takes it as it is, the way Blizzard's SetRaidTargetIconTexture does.
local function PaintMarker(self, entry)
    local marker = entry.row.marker
    if not self.config.showMarkers then
        marker:Hide()
        return
    end
    local index = GetRaidTargetIndex(entry.unit)
    if Public(index) and index == nil then
        marker:Hide()
        return
    end
    marker:SetSpriteSheetCell(index, MARKER_ROWS, MARKER_COLUMNS)
    marker:Show()
end

-- The cast duration rule (shared with Nameplates/CastTime.lua): the duration
-- object may itself be secret (UnitCastingDuration: SecretReturns,
-- UnitDocumentation), and both duration sinks take secret arguments only
-- from untainted code (SecretArguments = "AllowedWhenUntainted":
-- StatusBar:SetTimerDuration, DurationTextBinding:SetDuration). A public
-- duration drives the bar and the time text; a secret one keeps the cast
-- listed as a full bar without a timer. A public nil means no such cast.
local function PaintTimer(entry)
    local row, duration = entry.row, entry.duration
    local timed = Public(duration)
    if timed then
        local direction = Enum.StatusBarTimerDirection
        row:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
            entry.kind == CHANNEL and direction.RemainingTime or direction.ElapsedTime)
        row.binding:SetDuration(duration)
    else
        row:SetMinMaxValues(0, 1)
        row:SetValue(1)
        row.time:SetText("")
    end
    row.binding:SetEnabled(timed)
end

-- Warm paint: text, texture, color, timer and alpha of one cast.
local function Paint(self, entry)
    local row, c = entry.row, self.config
    row.name:SetText(entry.name)
    row.icon:SetTexture(entry.icon)
    if c.targetLine then row.target:SetText(UnitSpellTargetName(entry.unit)) end
    PaintColor(self, entry)
    PaintTimer(entry)
    entry.dim = c.dimOutOfRange and OutOfRange(self, entry.unit) or false
    PaintAlpha(self, entry)
    PaintStripe(self, entry)
    PaintMarker(self, entry)
    row:Show()
end

local function Release(self, entry)
    local row = entry.row
    if not row then return end
    entry.row = nil
    row.binding:SetEnabled(false)
    row:Hide()
    self.free[#self.free + 1] = row
end

local function ShowHost(self)
    local shown = S.editMode == true or self.visible > 0
    if self.hostShown ~= shown then
        self.host:SetShown(shown)
        self.hostShown = shown
    end
end

-- Nameplates send no range events (SPELL_RANGE_CHECK_UPDATE covers only the
-- target), so a ticker samples the listed casts four times a second while
-- dimming is on and casts are listed; it stops with the last one.
local function RangeTick(self)
    for i = 1, self.visible do
        local entry = self.ordered[i]
        local dim = OutOfRange(self, entry.unit)
        if entry.dim ~= dim then
            entry.dim = dim
            PaintAlpha(self, entry)
        end
    end
end

local function SyncRangeTicker(self)
    local needed = self.listening and self.config.dimOutOfRange and #self.candidates > 0
        and self.visible > 0 and not S.editMode
    local ticker = self.rangeTicker
    local running = ticker ~= nil and ticker:Running()
    if needed and not running then
        self.rangeTicker = self.context:Ticker(RANGE_TICK, RangeTick)
    elseif running and not needed then
        ticker:Cancel()
    end
end

-- Rows follow their casts: a stop re-anchors the rows after it and paints
-- only the cast that moves into the freed slot. In Edit Mode the samples
-- stand in and casts are listed without rows; in combat Edit Mode closes
-- before the module's Refresh may run, so the first Sync after it gives
-- every listed cast its row (self.rowless).
local function Sync(self, from)
    if S.editMode then
        self.rowless = true
        return
    end
    if self.rowless then from, self.rowless = 1, nil end
    local ordered = self.ordered
    local count = math.min(#ordered, self.config.listSize)
    if self.visible == 0 and count > 0 then SampleReady(self) end
    for i = from, count do
        local entry = ordered[i]
        if not entry.row then
            entry.row = table.remove(self.free) or NewRow(self, self.rows)
            Paint(self, entry)
        end
        if entry.row.slot ~= i then Place(self, entry.row, i) end
    end
    self.visible = count
    ShowHost(self)
    SyncRangeTicker(self)
end

------------------------------------------------------------------ casts
local function Duration(unit, kind)
    if kind == CHANNEL then return UnitChannelDuration(unit) end
    return UnitCastingDuration(unit)
end

-- Enemy cast details are secret (SecretWhenUnitSpellCastRestricted) and only
-- reach native sinks; a public nil name means the unit is not casting.
local function Read(entry, unit, kind)
    local name, icon, locked, spell, _
    if kind == CHANNEL then
        name, _, icon, _, _, _, locked, spell = UnitChannelInfo(unit)
    else
        name, _, icon, _, _, _, _, locked, spell = UnitCastingInfo(unit)
    end
    if Public(name) and name == nil then return false end
    local duration = Duration(unit, kind)
    if Public(duration) and duration == nil then return false end
    if Public(locked) and locked == nil then locked = false end
    local important = false
    if not (Public(spell) and spell == nil) then important = C_Spell.IsSpellImportant(spell) end
    entry.kind, entry.name, entry.icon, entry.locked = kind, name, icon, locked
    entry.important, entry.duration = important, duration
    return true
end

local function Forget(entry)
    entry.live = false
    entry.name, entry.icon, entry.locked, entry.important, entry.duration = nil, nil, nil, nil, nil
end

local function Wanted(self, kind)
    local kinds = self.config.castKinds
    return kinds == ALL_KINDS or kinds == CASTS_ONLY and kind == CAST or kinds == CHANNELS_ONLY and kind == CHANNEL
end

local function Attackable(unit)
    local attack = UnitCanAttack("player", unit)
    return Public(attack) and attack == true
end

local function Add(self, unit, kind)
    local entry = self.entries[unit]
    if not entry then
        entry = { unit = unit }
        self.entries[unit] = entry
    end
    if kind then
        if not Read(entry, unit, kind) then return end
    elseif not Read(entry, unit, CAST) and not Read(entry, unit, CHANNEL) then
        return
    end
    if not Wanted(self, entry.kind) then
        Forget(entry)
        return
    end
    entry.live = true
    local ordered = self.ordered
    ordered[#ordered + 1] = entry
    Sync(self, #ordered)
end

local function Remove(self, entry)
    local ordered = self.ordered
    for i = 1, #ordered do
        if ordered[i] == entry then
            table.remove(ordered, i)
            Release(self, entry)
            Forget(entry)
            Sync(self, i)
            return
        end
    end
end

local function OnCast(self, event, unit)
    if not PLATES[unit] then return end
    local entry = self.entries[unit]
    local live = entry and entry.live
    local kind = START[event]
    if kind or event == "NAME_PLATE_UNIT_ADDED" then
        if live then Remove(self, entry) end
        if Attackable(unit) then Add(self, unit, kind) end
    elseif not live then
        -- Stops and updates of casts that are not listed cost nothing.
        return
    elseif STOP[event] then
        -- A failed or late stop can arrive while the unit casts on.
        if event ~= "NAME_PLATE_UNIT_REMOVED" and Read(entry, unit, entry.kind) then
            if entry.row then Paint(self, entry) end
            return
        end
        Remove(self, entry)
    elseif RETIME[event] then
        local duration = Duration(unit, entry.kind)
        if Public(duration) and duration == nil then return end
        entry.duration = duration
        if entry.row then PaintTimer(entry) end
    elseif LOCK[event] then
        entry.locked = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
        if entry.row then
            PaintColor(self, entry)
            PaintStripe(self, entry)
        end
    end
end

------------------------------------------------------------------ gating
local function Relevant(self, spellID, baseSpellID)
    -- No spell ID: every cooldown changed.
    if not Public(spellID) or spellID == nil then return true end
    local list = self.candidates
    for i = 1, #list do
        if list[i] == spellID or Public(baseSpellID) and list[i] == baseSpellID then return true end
    end
    return false
end

local function OnCooldown(self, _, spellID, baseSpellID)
    if self.visible == 0 or not Relevant(self, spellID, baseSpellID) then return end
    SampleReady(self, true)
    PaintStripes(self)
end

OnWake = function()
    if M.active and M.listening and M.visible > 0 then
        SampleReady(M)
        PaintStripes(M)
    end
end

local function ListenCooldowns(self)
    if self.listening and self.config.readyStripe and #self.candidates > 0 then
        self.context:Event("SPELL_UPDATE_COOLDOWN", OnCooldown, IN_COMBAT)
    else
        self.context:RemoveEvent("SPELL_UPDATE_COOLDOWN")
    end
end

local function OnSpells(self)
    Candidates(self)
    ListenCooldowns(self)
    if self.visible > 0 then
        SampleReady(self)
        PaintStripes(self)
    end
    SyncRangeTicker(self)
end

local function OnMarkers(self)
    for i = 1, self.visible do PaintMarker(self, self.ordered[i]) end
end

local function ListenSpells(self)
    local c = self.config
    local ctx, on = self.context, self.listening and (c.readyStripe or c.dimOutOfRange)
    if self.listening and c.showMarkers then
        ctx:Event("RAID_TARGET_UPDATE", OnMarkers, IN_COMBAT)
    else
        ctx:RemoveEvent("RAID_TARGET_UPDATE")
    end
    for _, event in ipairs({ "SPELLS_CHANGED", "PET_BAR_UPDATE" }) do
        if on then ctx:Event(event, OnSpells, IN_COMBAT) else ctx:RemoveEvent(event) end
    end
    for _, event in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "UNIT_PET" }) do
        if on then ctx:Event(event, OnSpells, IN_COMBAT, "player") else ctx:RemoveEvent(event) end
    end
    ListenCooldowns(self)
end

local function Clear(self)
    local ordered = self.ordered
    for i = #ordered, 1, -1 do
        local entry = ordered[i]
        ordered[i] = nil
        Release(self, entry)
        Forget(entry)
    end
    self.visible = 0
    for _, wake in ipairs(self.wakes) do wake:Clear() end
    SyncRangeTicker(self)
end

local function Gate(self)
    local inside, kind = IsInInstance()
    local want = self.active == true and Public(inside) and inside == true and S.PublicText(kind) == "party"
    if want ~= self.listening then
        self.listening = want
        for _, event in ipairs(CAST_EVENTS) do
            if want then self.context:Event(event, OnCast, IN_COMBAT) else self.context:RemoveEvent(event) end
        end
        Clear(self)
        if want then
            -- One bounded snapshot covers entering or enabling inside a dungeon.
            for i = 1, #PLATE_TOKENS do
                local unit = PLATE_TOKENS[i]
                local exists = UnitExists(unit)
                if Public(exists) and exists == true and Attackable(unit) then Add(self, unit) end
            end
        end
        ShowHost(self)
    end
    ListenSpells(self)
end

------------------------------------------------------------------ Edit Mode samples
local function PaintSample(self, row, index)
    local samples = Samples()
    local sample, c = samples[(index - 1) % #samples + 1], self.config
    local color = sample.locked and self.lockedRGB or sample.important and self.priorityRGB or self.castRGB
    row.name:SetText(sample.name)
    row.icon:SetTexture(sample.icon)
    row.target:SetText(sample.target)
    row:SetStatusBarColor(color[1], color[2], color[3])
    row:SetMinMaxValues(0, 1)
    row:SetValue(sample.fraction)
    row.time:SetText(string.format("%.1f", sample.left))
    local base = c.dimOutOfRange and sample.far and DIM or 1
    local minor = c.onlyImportant and 0 or c.fadeMinor and FADE or 1
    row:SetAlpha(sample.important and base or base * minor)
    if c.readyStripe and c.readyStyle == READY_WHOLE_BAR and not sample.locked then
        row:SetStatusBarColor(self.stripeRGB[1], self.stripeRGB[2], self.stripeRGB[3])
    end
    row.stripe:SetAlpha(1)
    SetStripe(row, c.readyStripe == true and c.readyStyle ~= READY_WHOLE_BAR and not sample.locked)
    if c.showMarkers and sample.marker then
        row.marker:SetSpriteSheetCell(sample.marker, MARKER_ROWS, MARKER_COLUMNS)
        row.marker:Show()
    else
        row.marker:Hide()
    end
    if row.slot ~= index then Place(self, row, index) end
    row:Show()
end

local function ShowSamples(self)
    local count = self.config.listSize
    for i = 1, count do
        PaintSample(self, self.previews[i] or NewRow(self, self.previews), i)
    end
    for i = count + 1, #self.previews do self.previews[i]:Hide() end
end

function M:HideEditPreview()
    for _, row in ipairs(self.previews) do row:Hide() end
end

------------------------------------------------------------------ lifecycle
local function SetRGB(into, hex)
    into[1], into[2], into[3] = S.RGB(hex)
end

local function OnZone(self) Gate(self) end

function M:Enable()
    if not self.host then
        self.host = S.CreateFrame("Frame", "MSUFSuiteEnemyCastStack", UIParent)
        self.host:Hide()
        self.hostShown = false
        self.formatter = C_StringUtil.CreateSecondsFormatter()
        self.formatter:SetDesiredUnitCount(1)
        self.formatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
    end
    self.context:Event("PLAYER_ENTERING_WORLD", OnZone, IN_COMBAT)
    self.context:Event("ZONE_CHANGED_NEW_AREA", OnZone, IN_COMBAT)
    self:Refresh()
    self:RegisterMovers()
end

function M:Refresh()
    local c, host = self.config, self.host
    SetRGB(self.castRGB, c.castColor)
    SetRGB(self.priorityRGB, c.priorityColor)
    SetRGB(self.lockedRGB, c.lockedColor)
    SetRGB(self.stripeRGB, c.stripeColor)
    host:ClearAllPoints()
    host:SetPoint("CENTER", UIParent, "CENTER", c.x, c.y)
    host:SetSize(c.width, c.listSize * c.rowHeight + (c.listSize - 1) * GAP)
    host:SetScale(c.scale / 100)
    for _, row in ipairs(self.rows) do Style(self, row) end
    for _, row in ipairs(self.previews) do Style(self, row) end
    Candidates(self)
    Gate(self)
    -- A settings change repaints every listed cast once.
    local ordered = self.ordered
    for i = #ordered, 1, -1 do
        local entry = ordered[i]
        Release(self, entry)
        if not Wanted(self, entry.kind) then
            table.remove(ordered, i)
            Forget(entry)
        end
    end
    self.visible = 0
    if S.editMode then
        ShowSamples(self)
    else
        self:HideEditPreview()
        Sync(self, 1)
    end
    ShowHost(self)
    SyncRangeTicker(self)
end

function M:Disable()
    Clear(self)
    self.listening = nil
    self:HideEditPreview()
    if self.host then
        self.host:Hide()
        self.hostShown = false
    end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "casts", { label = "Dungeon casts", order = 647,
        getFrame = function() return self.host end, xKey = "x", yKey = "y",
        sizeKeys = { "width", "rowHeight", "scale" },
        point = function() return "CENTER" end, quickPosition = true })
end

S.Install(ID, M)
