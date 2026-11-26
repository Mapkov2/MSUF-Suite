local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Readable snapshots for selected own totems. Native slots handle protected auras.
local Coverage = {}
C.TotemCoverage = Coverage

if not NS.Client.isForever then return end
local _, class = UnitClass("player")
if not S.Public(class) or class ~= "SHAMAN" or not S.Number(AIR_TOTEM_SLOT) or not S.Number(EARTH_TOTEM_SLOT) then return end

local GetTotemInfo, Public, InCombat = GetTotemInfo, S.Public, NS.InCombat
local GetAura = C_UnitAuras.GetAuraDataBySpellName
local ShouldHideAura = C_Secrets.ShouldSpellAuraBeSecret
local Display = C.TotemCoverageDisplay
local UNKNOWN, WITHOUT, WITH, EXCLUDED = 0, 1, 2, 3
local NONE, KNOWN, OPAQUE = 0, 1, 2

local function Family(cast, effects, base)
    return { cast = cast, effects = effects, base = base, matches = {}, state = NONE }
end

local families = {
    [AIR_TOTEM_SLOT] = Family(8512,
        { [8515] = true, [10609] = true, [10612] = true }, 8515),
    [EARTH_TOTEM_SLOT] = Family(8075,
        { [8076] = true, [8162] = true, [8163] = true, [10441] = true, [25362] = true }, 8076),
}

local grounding = Family(8177, { [8178] = true }, 8178)
local resolved, visible = {}, {}
local records, units, members, changed = {}, {}, {}, {}
local driver, listening, watchUnits, scheduled, full, rosterDirty, prepare, hovered

local function FamilyName(family)
    if not family.name then family.name = S.PublicText(C_Spell.GetSpellName(family.base)) end
    return family.name
end

local function CanRead(family)
    if not ShouldHideAura then return false end
    for id in pairs(family.effects) do
        local restricted = ShouldHideAura(id)
        if not Public(restricted) or restricted ~= false then return false end
    end
    return FamilyName(family) ~= nil
end

local function SlotState(slot)
    local have, _, start, duration, _, _, id = GetTotemInfo(slot)
    local family = families[slot]
    if not Public(have) then return resolved[slot] or family, OPAQUE, have end
    if have ~= true then return family, NONE end
    if not Public(id) then return resolved[slot] or family, OPAQUE end
    local cast = S.Number(id) and C.Ranks.Canon(id)
    if slot == AIR_TOTEM_SLOT and cast == grounding.cast then family = grounding end
    if cast ~= family.cast then return family, NONE end
    if S.Number(start) and S.Number(duration) and duration > 0 and start + duration <= GetTime() then return family, NONE end
    return family, KNOWN
end

local function Read(family, unit)
    local connected, dead = UnitIsConnected(unit), UnitIsDeadOrGhost(unit)
    if (Public(connected) and connected == false) or (Public(dead) and dead == true) then return EXCLUDED end
    if not Public(connected) or connected ~= true or not Public(dead) or dead ~= false then return UNKNOWN end
    local visible = UnitIsVisible(unit)
    if not Public(visible) or visible ~= true then return UNKNOWN end
    local aura = GetAura(unit, family.name, "HELPFUL|PLAYER")
    if not Public(aura) then return UNKNOWN end
    if aura == nil then return WITHOUT end
    if type(aura) ~= "table" then return UNKNOWN end
    local id = aura.spellId
    if not Public(id) or not family.effects[id] then return UNKNOWN end
    return WITH
end

local function Roster(list, lookup)
    wipe(list)
    if lookup then wipe(lookup) end
    local raid = IsInRaid()
    if not Public(raid) then return end
    local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    if not S.Number(count) or count <= 0 then return end
    if not raid then list[1] = "player" end
    for i = 1, math.min(count, raid and 40 or 4) do
        list[#list + 1] = (raid and "raid" or "party") .. i
    end
    if lookup then
        for i = 1, #list do lookup[list[i]] = true end
    end
end

local function Totals(family)
    local with, without, unknown = 0, 0, 0
    for i = 1, #units do
        local result = family.matches[units[i]]
        if result == WITH then
            with = with + 1
        elseif result == WITHOUT then
            without = without + 1
        elseif result == UNKNOWN then
            unknown = unknown + 1
        end
    end
    family.with, family.without, family.unknown = with, without, unknown
end

local function SetBadge(icon, text)
    if icon.totemCoverageValue == text then return end
    icon.totemCoverageValue = text
    local badge = icon.totemCoverageBadge
    if not badge and text then
        badge = S.CreateFontString(icon.over, nil, "OVERLAY")
        badge:SetFontObject(GameFontHighlightSmall)
        badge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
        badge:SetShadowOffset(1, -1)
        icon.totemCoverageBadge = badge
    end
    if badge then badge:SetText(text or "") end
end

local function BadgeText(family)
    if #units == 0 or family.state == NONE then return end
    if not family.readable then return "?" end
    if family.unknown > 0 then
        return family.with > 0 and ("%d+"):format(family.with) or "?"
    end
    local total = family.with + family.without
    if total > 0 then return ("%d/%d"):format(family.with, total) end
end

local function UpdateFamily(family)
    if full then
        family.readable = family.state == KNOWN and #units > 0 and CanRead(family)
    end
    if not family.readable then return end
    if full then
        wipe(family.matches)
        for i = 1, #units do
            local unit = units[i]
            family.matches[unit] = Read(family, unit)
        end
    else
        for unit in pairs(changed) do family.matches[unit] = Read(family, unit) end
    end
    Totals(family)
end

local unitEvents = { "UNIT_AURA", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_PHASE" }
local function WatchUnits(enabled)
    if watchUnits == enabled then return end
    watchUnits = enabled
    for i = 1, #unitEvents do
        if enabled then driver:RegisterEvent(unitEvents[i]) else driver:UnregisterEvent(unitEvents[i]) end
    end
end

local function ShowDetails(icon, family)
    local name = family and FamilyName(family)
    if not name or family.state == NONE or #units == 0 then return false end
    return Display.Show(icon, name, family.effects, units, family.have)
end

local function Visible(icon)
    local entry = icon.entry
    local bar = entry and C.bars[entry.slot]
    return entry ~= nil and not C.state.preview and not (bar and bar.hidden)
end

local function Flush()
    scheduled = false
    if not next(records) then return end
    if rosterDirty then Roster(units, members) end
    wipe(visible)
    for icon, slot in pairs(records) do
        if Visible(icon) then visible[slot] = true end
    end
    local shouldWatch = false
    for slot, fallback in pairs(families) do
        local family = resolved[slot] or fallback
        if full and visible[slot] then
            local selected, state, have = SlotState(slot)
            if family ~= selected then
                family = selected
                resolved[slot], prepare = family, true
                if hovered and records[hovered] == slot then Display.Hide(hovered) end
            end
            family.state, family.have = state, have
        end
        if visible[slot] then
            UpdateFamily(family)
            shouldWatch = shouldWatch or family.readable
            family.badge = BadgeText(family)
        else
            family.readable, family.badge = false, nil
        end
    end
    local pendingPrepare = prepare and not InCombat() and not NS.Client.AuraBuildBlocked()
    local allPrepared = pendingPrepare or #units == 0
    for icon, slot in pairs(records) do
        local family = resolved[slot] or families[slot]
        if pendingPrepare and #units > 0 then
            local name = FamilyName(family)
            if not name or not Display.Prepare(icon, name, family.effects, units) then allPrepared = false end
        end
        SetBadge(icon, Visible(icon) and family.badge or nil)
    end
    if hovered and full then
        local slot = records[hovered]
        if not ShowDetails(hovered, resolved[slot] or families[slot]) then Display.Hide(hovered) end
    end
    WatchUnits(shouldWatch)
    wipe(changed)
    full, rosterDirty, prepare = false, false, prepare and not allPrepared
end

local function Queue()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, Flush)
end

local function ResumePreparation()
    if prepare and listening then Queue() end
end

local function ResumeWhenAllowed()
    if prepare and NS.Client.AuraBuildBlocked() then
        NS.Client.AfterAuraBuild(Coverage, ResumePreparation)
    end
end

local function OnEvent(_, event, unit)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        rosterDirty, prepare, full = true, true, true
        if hovered then Display.Hide(hovered) end
        for icon in pairs(records) do SetBadge(icon) end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        full, prepare = true, true
        if hovered then Display.Hide(hovered) end
        for icon in pairs(records) do SetBadge(icon) end
    elseif Public(unit) and members[unit] then
        changed[unit] = true
    else
        return
    end
    ResumeWhenAllowed()
    Queue()
end

local function Wake()
    if listening then return end
    listening = true
    if not driver then
        driver = S.CreateFrame("Frame")
        driver:SetScript("OnEvent", OnEvent)
    end
    driver:RegisterEvent("GROUP_ROSTER_UPDATE")
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    driver:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    driver:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Coverage.Leave(icon)
    if hovered ~= icon then return end
    hovered = nil
    Display.Hide(icon)
end

function Coverage.Retire(icon)
    local slot = records[icon]
    if not slot then return end
    Coverage.Leave(icon)
    Display.Retire(icon)
    SetBadge(icon)
    records[icon] = nil
    if not next(records) then
        driver:UnregisterAllEvents()
        listening, watchUnits = false, nil
        wipe(changed)
        wipe(resolved)
    end
end

function Coverage.Sync(icon, entry)
    local slot = entry.id
    if not (entry.ov and entry.ov.totemCoverage == true and families[slot]) then
        if records[icon] then Coverage.Retire(icon) end
        return
    end
    if records[icon] == slot then return end
    Coverage.Retire(icon)
    records[icon] = slot
    Wake()
    rosterDirty, prepare, full = true, true, true
    ResumeWhenAllowed()
    Queue()
end

function Coverage.Update(icon)
    if not records[icon] then return end
    SetBadge(icon)
    if hovered == icon then Display.Hide(icon) end
    full = true
    Queue()
end

function Coverage.WantsHover(icon)
    return records[icon] ~= nil
end

function Coverage.Hover(icon)
    if not records[icon] then return false end
    if hovered and hovered ~= icon then Coverage.Leave(hovered) end
    hovered = icon
    local slot = records[icon]
    local family = resolved[slot] or families[slot]
    -- When the active spell is opaque, the panel describes the named aura family.
    -- Keep the native tooltip available to identify the actual slot contents.
    return ShowDetails(icon, family) and family.state == KNOWN
end

local function Notice(text)
    DEFAULT_CHAT_FRAME:AddMessage(S.Text(text))
end

local lastReport
function NS.ReportTotemCoverage(slot)
    local raid = IsInRaid()
    if not Public(raid) or raid ~= true then return Notice("Join a raid to report totem coverage.") end
    local locked = NS.ChatLocked()
    if not S.Number(slot) then return Notice("Totem coverage is unavailable.") end
    local family, state
    if families[slot] then family, state = SlotState(slot) end
    if state ~= KNOWN or not CanRead(family) then
        if locked then return Notice("Totem coverage cannot be sent right now.") end
        return Notice("Totem coverage is unavailable.")
    end
    local now = GetTime()
    if not locked and lastReport and now - lastReport < 1 then return end
    local list = {}
    Roster(list)
    local with, without, unknown = 0, 0, 0
    for i = 1, #list do
        local result = Read(family, list[i])
        if result == WITH then
            with = with + 1
        elseif result == WITHOUT then
            without = without + 1
        elseif result == UNKNOWN then
            unknown = unknown + 1
        end
    end
    if with + without == 0 then return Notice("Totem coverage is unavailable.") end
    local message = S.Text("%s — %d with your buff, %d without, %d unknown."):format(family.name, with, without, unknown)
    if locked or NS.ChatLocked() then
        DEFAULT_CHAT_FRAME:AddMessage(S.Text("Totem coverage cannot be sent right now.") .. " " .. message)
        return
    end
    lastReport = now
    C_ChatInfo.SendChatMessage(message, "RAID")
end
