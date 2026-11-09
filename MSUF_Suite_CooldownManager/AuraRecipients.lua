local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Special own buffs can live on another group member. Keep one native aura
-- slot per entry and move only its unit binding when the recipient changes.
-- The native button still owns duration, stacks, glows and secret values.
-- Only readable identities may be queried by name. Explicit externals use
-- Blizzard's current spell secrecy predicate when available. Aura storms share one wake.
local Recipients = { slots = {} }
C.AuraRecipients = Recipients
local Public, type, pairs = S.Public, type, pairs
local Containers = C.AuraContainers
local records, dirty, units, known = {}, {}, { "player" }, {}
for i = 1, 4 do units[#units + 1] = "party" .. i end
for i = 1, 40 do units[#units + 1] = "raid" .. i end
units[#units + 1], units[#units + 2] = "target", "focus"
for i = 1, #units do known[units[i]], dirty[units[i]] = true, false end
local driver, listening, armed, all, generation = nil, false, false, false, 0
local FILTER = "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"

local function Visible(rec)
    if rec.shown ~= true or rec.enabled ~= true or C.state.preview then return false end
    if rec.fam ~= "over" then return true end
    for i = 1, #rec.keys do if rec.act[i] then return true end end
    return false
end

local function Eligible(state)
    local never = Enum.SecrecyLevel.NeverSecret
    local shouldBeSecret = state.external and C_Secrets.ShouldSpellAuraBeSecret
    for i = 1, #state.spells do
        local spell = state.spells[i]
        if shouldBeSecret then
            local secret = shouldBeSecret(spell)
            state.eligible[i] = Public(secret) and secret == false
        else
            local secrecy = C_Secrets.GetSpellAuraSecrecy(spell)
            state.eligible[i] = Public(secrecy) and secrecy == never
        end
    end
end

local function Read(state, unit)
    local exists = UnitExists(unit)
    if not Public(exists) or exists ~= true then return false end
    local uncertain, eligible = false, false
    for i = 1, #state.spells do
        if state.eligible[i] then
            eligible = true
            local aura = C_UnitAuras.GetAuraDataBySpellName(unit, state.names[i], FILTER)
            if not Public(aura) then
                uncertain = true
            elseif type(aura) == "table" then
                local id = aura.spellId
                if not Public(id) then
                    uncertain = true
                elseif state.ids[id] then
                    return true
                end
            end
        end
    end
    if eligible and not uncertain then return false end
end

local function Select(rec, state)
    local unit = rec.unit
    if state.matches[unit] ~= true then
        unit = "player"
        for i = 1, #units do
            if state.matches[units[i]] == true then unit = units[i] break end
        end
    end
    local active = state.matches[unit] == true
    if rec.unit ~= unit then
        if state.active and active then C.AuraButtons.Hush(rec) end
        rec.unit = unit
        rec.frame:SetUnit(unit)
    end
    state.active = active
    local displayUnit = active and unit or false
    if state.named and state.displayUnit ~= displayUnit then
        state.displayUnit = displayUnit
        local recipient = active and S.PublicText(UnitName(unit)) or nil
        local label = recipient and state.name and S.Text("%s on %s"):format(state.name, recipient) or nil
        if rec.recipientText ~= label then
            rec.recipientText = label
            C.AuraLooks.Recipient(rec)
        end
    end
end

local function Refresh(rec, state, full)
    Eligible(state)
    for i = 1, #units do
        local unit = units[i]
        if full or dirty[unit] then
            local match = Read(state, unit)
            -- Opaque externals have no verified recipient. Other group buffs
            -- keep their prior public binding and let the native slot update.
            if match ~= nil or state.external then state.matches[unit] = match == true end
        end
    end
    Select(rec, state)
end

local function Flush()
    armed = false
    for rec, state in pairs(records) do
        if Visible(rec) then Refresh(rec, state, all) end
    end
    for unit in pairs(dirty) do dirty[unit] = false end
    all = false
end
local WAKE = C.NewWake(Flush)
local function Event(event, unit)
    if not listening then return end
    if event == "UNIT_AURA" then
        if not Public(unit) or not known[unit] then return end
        dirty[unit] = true
    elseif event == "PLAYER_TARGET_CHANGED" then
        dirty.target = true
        for _, state in pairs(records) do
            state.matches.target = false
            if state.displayUnit == "target" then state.displayUnit = nil end
        end
    elseif event == "PLAYER_FOCUS_CHANGED" then
        dirty.focus = true
        for _, state in pairs(records) do
            state.matches.focus = false
            if state.displayUnit == "focus" then state.displayUnit = nil end
        end
    else
        all = true
        -- A token may now name a different person, or a previously readable
        -- identity may become restricted. Do not retain stale associations.
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            for _, state in pairs(records) do
                state.displayUnit = nil
                for token in pairs(state.matches) do state.matches[token] = false end
            end
        end
    end
    if armed then return end
    armed = true
    C.Wake(WAKE, 0)
end
local function OnEvent(_, event, unit) S.Dispatch(Event, event, unit) end

function Recipients.Watch(refreshed)
    local wanted, newlyVisible = false, false
    for rec, state in pairs(records) do
        local visible = Visible(rec)
        if visible and not state.visible then newlyVisible = true end
        state.visible = visible
        if visible then wanted = true end
    end
    if wanted == listening then
        if wanted and newlyVisible and not refreshed then Event("refresh") end
        return
    end
    listening = wanted
    if not driver and wanted then
        driver = S.CreateFrame("Frame")
        driver:SetScript("OnEvent", OnEvent)
    end
    if not driver then return end
    driver:UnregisterAllEvents()
    if wanted then
        driver:RegisterEvent("UNIT_AURA")
        driver:RegisterEvent("GROUP_ROSTER_UPDATE")
        driver:RegisterEvent("PLAYER_TARGET_CHANGED")
        driver:RegisterEvent("PLAYER_FOCUS_CHANGED")
        driver:RegisterEvent("PLAYER_ENTERING_WORLD")
        if NS.Client.SupportsEvent("ADDON_RESTRICTION_STATE_CHANGED") then
            driver:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        end
        if not refreshed then Event("refresh") end
    end
end

function Recipients.Retire(rec)
    records[rec] = nil
    Recipients.Watch()
end

function Recipients.Visibility(rec)
    if records[rec] then Recipients.Watch() end
end

local function State(rec, entry)
    local state = records[rec]
    if not state then
        state = { spells = {}, names = {}, eligible = {}, ids = {}, matches = {} }
        for i = 1, #units do state.matches[units[i]] = false end
        records[rec] = state
    end
    state.displayUnit = nil
    state.external = entry.src == "g"
    state.named, state.name = state.external and rec.role == "bar", entry.name
    C.wipe(state.spells)
    C.wipe(state.names)
    C.wipe(state.ids)
    for id in pairs(entry.auraIDs or C.EMPTY) do
        local name = C.Catalog.SpellName(id)
        if name then
            local i = #state.spells + 1
            state.spells[i], state.names[i], state.ids[id] = id, name, true
        end
    end
    for unit in pairs(state.matches) do state.matches[unit] = false end
    return state
end

local function Wanted(entry, over, view)
    if entry.unit ~= "group" or not entry.auraHelpful or entry.src == "p" then return false end
    if not over then return entry.family == C.Const.FAMILY.AURA end
    if not entry.icon or not entry.hasAura then return false end
    local show = (entry.ov or C.EMPTY).showAura
    if show == nil then show = view.showAura == true end
    return show == true and entry.family == C.Const.FAMILY.COOLDOWN
end

function Recipients.Sync(slot, fam, view, plan, force, run, needs)
    if not plan.hasRecipients and not Recipients.slots[slot] then return end
    Recipients.slots[slot] = nil
    generation = generation + 1
    local mark, over = generation, fam == "over"
    local entries, list, where = plan.entries, Containers.list, Containers.where
    local cap = #entries
    local steady, limit = 0, view.maxIcons
    if not over and type(view.maxIcons) == "number" and view.maxIcons > 0 then cap = math.min(cap, view.maxIcons) end
    for i = 1, cap do
        local entry = entries[i]
        if over and entry.icon then
            if type(limit) == "number" and limit > 0 and steady >= limit then break end
            local hide = (entry.ov or C.EMPTY).hideReady
            if hide == nil then hide = view.hideReady == true end
            if hide ~= true then steady = steady + 1 end
        end
        if Wanted(entry, over, view) then
            list[1], where[1] = entry, i
            for j = #list, 2, -1 do list[j], where[j] = nil, nil end
            needs(list, not over, view)
            if not over and C.Alerts.AuraSensor(entry) then Containers.need.kit = true end
            if entry.src == "g" and plan.kind == C.Const.KIND.AURA_BAR then
                Containers.need.label, Containers.need.looks = true, true
                Containers.need.timers = Containers.need.timers .. "R"
            end
            local key = "group:" .. entry.key
            local role = over and "over" or plan.kind == C.Const.KIND.AURA_BAR and "bar" or "icon"
            local fams = Containers.live[slot]
            local old = fams and fams[fam][key]
            local rec = run(slot, fam, old and old.unit or "player", role, true, view, 1, force, 0, nil, key)
            if rec then
                Recipients.slots[slot] = true
                local state = State(rec, entry)
                state.mark = mark
                if Visible(rec) then Refresh(rec, state, true) end
            end
        end
    end
    local fams = Containers.live[slot]
    for key, rec in pairs(fams and fams[fam] or C.EMPTY) do
        local state = records[rec]
        if state and state.mark ~= mark then Containers.Retire(slot, fam, key) end
    end
    Recipients.Watch(true)
end
