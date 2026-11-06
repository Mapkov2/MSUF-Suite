local root = assert(arg[1])
local W = dofile(root .. "/tools/tests/cdm_data_world.lua")(root)
local C, CDM = W.C, W.NS.CDM
W.NS.Client.isForever = arg[2] == "Forever"
W.Views()
W.sets[4] = { 198715, 198716 }
W.infos[198715] = { spellID = 33763, category = 4, isKnown = true, hasAura = true }
W.infos[198716] = { spellID = 774, category = 4, isKnown = true, hasAura = true, flags = 2 }
assert(C.Catalog.Ready(), "group buffs alone must establish native data readiness")
C.Catalog.Rebuild()
local rec = assert(C.Catalog.records[198715], "Lifebloom was dropped from the GroupBuff source")
assert(rec.groupAura and rec.family == 2 and rec.bar == "buf", "group buff must enter the buff catalog")
assert(C.Catalog.records[198716].groupAura and not C.Catalog.records[198716].bar,
    "hidden group buff lost its identity or became visible by default")
C.Resolve.Build()
assert(C.entries.b198715 and C.entries.b198715.unit == "group" and C.entries.b198715.auraHelpful,
    "automatic Lifebloom must follow group recipients")
assert(C.plans.buf.hasRecipients, "resolved group entries must enable the recipient consumer")
C.spells = CDM.CleanSpells({ e = { b198715 = { auraUnit = 5 } } })
C.Resolve.Build()
C.Index.Rebuild()
local harmful = C_Spell.IsSpellHarmful
C_Spell.IsSpellHarmful = function(id) return id == 900123 end
C.Catalog.OnOverride(33763, 900123)
assert(C.entries.b198715.unit == "target" and not C.plans.buf.hasRecipients,
    "direct harmful override retained the group consumer")
C.Catalog.OnOverride(33763, nil)
assert(C.entries.b198715.unit == "group" and C.plans.buf.hasRecipients,
    "direct override back to Lifebloom failed to restore group tracking")
C_Spell.IsSpellHarmful = harmful
for choice, unit in pairs({ [2] = "player", [3] = "target", [4] = "both", [5] = "group" }) do
    C.spells = CDM.CleanSpells({ e = { b198715 = { auraUnit = choice } } })
    C.Resolve.Build()
    assert(C.entries.b198715.unit == unit, "explicit tracking choice lost precedence")
end
C_Spell.IsSpellHarmful = function(id) return id == 589 end
C.spells = CDM.CleanSpells({ e = { a33763 = { auraUnit = 5 }, d589 = { auraUnit = 5 } } })
C.lists = CDM.CleanLists({ specs = { [63] = { buf = { "a33763", "b198716", "d589" } } } })
C.state.specID = 63
C.Resolve.Build()
assert(C.entries.a33763.unit == "group" and C.entries.b198716.unit == "group",
    "custom or manually selected hidden buffs cannot track the group")
assert(C.entries.d589.unit == "target", "the buff-only Group choice must preserve a harmful aura's target route")
local replacement = { family = 1, src = "s" }
assert(C.EntryFill.ApplyReplacement(replacement, { replaceAura = 589, auraUnit = 5 }) and replacement.unit == "target",
    "a harmful replacement aura disappeared through the Group buff choice")
C_Spell.IsSpellHarmful = harmful
W.combat = true
W.infos[198715].selfAura = true
W.sets[4][3] = 198719
W.infos[198719] = { spellID = 139, category = 4, isKnown = true, hasAura = true }
for _ = 1, 30 do if C.Catalog.Rebuild(true) then break end end
assert(C.Catalog.records[198715].groupAura, "combat catalog lost the source category")
assert(C.Catalog.records[198719].groupAura, "a new combat-sliced group record lost its source identity")

-- Reuse the hostile native-container fixture, including its sealed buttons.
-- These cases exercise the actual Auras/Containers/Recipients integration.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_auras_contract.lua", [=[
do (function()
    NS.Client.isForever = arg[2] == "Forever"
    local recipients, driver, reads = {}, nil, 0
    local function SensorFire(sensor, event)
        local callback = R[sensor].scripts[event]
        if callback then callback(sensor) end
    end
    local present = { player = true, party1 = true, party2 = true, target = true }
    local restricted, opaque = false, false
    Enum.SecrecyLevel = { NeverSecret = 0 }
    C_Secrets.GetSpellAuraSecrecy = function() return restricted and 1 or 0 end
    rawset(_G, "UnitExists", function(unit) return present[unit] == true end)
    C.Catalog = C.Catalog or {}
    C.Catalog.SpellName = function(id) return tostring(id) end
    C_UnitAuras.GetAuraDataBySpellName = function(unit, name, filter)
        assert(not restricted, "restricted identity reached a RequiresNonSecretAura query")
        assert(filter:find("HELPFUL|PLAYER", 1, true), "recipient search must exclude another druid's buff")
        -- Model the live report: this hidden tracking aura is absent from
        -- ordinary player/group scans, but native Target already included it.
        if not filter:find("INCLUDE_NAME_PLATE_ONLY", 1, true) then return nil end
        reads = reads + 1
        if opaque then return Secret() end
        if recipients[unit] then return { spellId = tonumber(name) } end
    end
    local create = S.CreateFrame
    S.CreateFrame = function(kind, name, parent, template)
        if kind ~= "Frame" or parent or template then return create(kind, name, parent, template) end
        driver = { events = {} }
        function driver:SetScript(_, callback) self.callback = callback end
        function driver:RegisterEvent(event) self.events[event] = true end
        function driver:UnregisterAllEvents() for event in pairs(self.events) do self.events[event] = nil end end
        return driver
    end
    S.Dispatch = function(callback, ...) return callback(...) end
    LoadRuntime("AuraRecipients.lua")
    local function Fire(event, unit)
        if driver and driver.events[event] then driver.callback(driver, event, unit) end
    end
    local function Current()
        return assert(C.AuraContainers.live.c6.aura["group:b198715"], "no group aura container")
    end
    local view = View("c6", 2)
    view.keepSlots, view.showMissing = true, true
    C.views.c6 = view
    local entry = Aura("c6", "b198715", "b", "group", Set(33763),
        { auraHelpful = true, ov = { sound = "file:54321", lossSound = "file:54322" } })
    C.entries[entry.key] = entry
    Plan("c6", 2, { entry })
    recipients.party1 = true
    A.Sync("c6")
    RunTimers()
    local rec = Current()
    assert(rec.unit == "party1" and R[rec.frame].unit == "party1", "off-target Lifebloom was not bound")
    assert(R[rec.frame].slots.s1.filter == "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY",
        "group native slot omitted hidden tracking auras")
    local container = rec.frame
    -- Group sounds use the actual caster-filtered button, never unit='group'
    -- in a native sound registration. Model native hide/show after SetUnit;
    -- the production selection and hush decision remain under test.
    C.state.soundQuietUntil, C.state.muteSounds = 0, false
    C.Alerts.SyncAuraSounds()
    local button = Acquired(container, "s1")
    local sensors = {}
    for region, state in pairs(R) do
        if state.parent == button and state.scripts then sensors[#sensors + 1] = region end
    end
    assert(#sensors == 1, "file sounds on a group buff need one native-button sensor")
    local sensor, nativeActive = sensors[1], true
    local setUnit = ContainerMethods.SetUnit
    ContainerMethods.SetUnit = function(frame, unit)
        setUnit(frame, unit)
        if frame == container then
            if nativeActive then SensorFire(sensor, "OnHide") end
            nativeActive = recipients[unit] == true
            if nativeActive then SensorFire(sensor, "OnShow") end
        end
    end
    NOW = NOW + 5
    local sounds = played.files
    recipients.party1 = nil
    Fire("UNIT_AURA", "party1")
    RunTimers()
    assert(played.files == sounds + 1 and played.file == 54322, "last group buff loss was muted by a recipient transfer")
    NOW = NOW + 5
    recipients.party1 = true
    Fire("UNIT_AURA", "party1")
    RunTimers()
    assert(played.files == sounds + 2 and played.file == 54321, "first group buff gain was muted by a recipient transfer")
    ContainerMethods.SetUnit = setUnit
    local before = reads
    COMBAT, ACCESS, AURAS_SECRET = true, false, true
    for _ = 1, 100 do Fire("UNIT_AURA", "party1") end
    Fire("UNIT_AURA", Secret())
    Fire("UNIT_AURA", "nameplate1")
    RunTimers()
    assert(reads == before + 1 and Current().frame == container, "burst must read one changed unit and reuse its sealed slot")
    Fire("PLAYER_TARGET_CHANGED")
    RunTimers()
    assert(Current().unit == "party1", "retargeting discarded the group recipient")
    recipients.party1, recipients.party2 = nil, true
    Fire("UNIT_AURA", "party1")
    Fire("UNIT_AURA", "party2")
    RunTimers()
    assert(Current().unit == "party2" and Current().frame == container, "combat recipient transfer rebuilt the container")
    opaque = true
    Fire("UNIT_AURA", "party2")
    RunTimers()
    assert(Current().unit == "party2", "opaque aura result selected another recipient")
    opaque, restricted = false, true
    before = reads
    Fire("ADDON_RESTRICTION_STATE_CHANGED")
    RunTimers()
    assert(reads == before, "restricted spells must never be queried")
    restricted = false
    recipients.party2, recipients.raid7, present.raid7 = nil, true, true
    Fire("GROUP_ROSTER_UPDATE")
    RunTimers()
    assert(Current().unit == "raid7", "raid roster did not transfer the recipient")
    recipients.raid7 = nil
    Fire("GROUP_ROSTER_UPDATE")
    RunTimers()
    assert(Current().unit == "player", "reassigned roster token retained a stale recipient")
    -- One visible consumer must not prevent another one from reseeding when
    -- it returns after missing aura changes while hidden.
    local second = Aura("c5", "a33763", "a", "group", Set(33763), { auraHelpful = true })
    C.views.c5 = View("c5", 2)
    C.views.c5.keepSlots = true
    Plan("c5", 2, { second })
    COMBAT, ACCESS, AURAS_SECRET = false, true, false
    A.Sync("c5")
    local customRec = C.AuraContainers.live.c5.aura["group:a33763"]
    assert(R[customRec.frame].slots.s1.filter == "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY",
        "a custom Group slot must keep the player's caster filter and hidden tracking auras")
    A.SetBarMouse("c6", false)
    recipients.party1 = true
    Fire("UNIT_AURA", "party1")
    RunTimers()
    A.SetBarMouse("c6", true)
    RunTimers()
    assert(Current().unit == "party1", "a returning consumer was not refreshed while another kept the driver running")
    A.Release("c5")
    A.SetBarMouse("c6", false)
    assert(next(driver.events) == nil, "hidden group bar retained its aura listener")
    A.SetBarMouse("c6", true)
    RunTimers()
    assert(driver.events.UNIT_AURA, "shown group bar failed to resume")
    C.state.preview = true
    A.SetPreview(true)
    assert(next(driver.events) == nil, "a preview retained recipient event work")
    recipients.party1, recipients.party2 = nil, true
    C.state.preview = false
    A.SetPreview(false)
    RunTimers()
    assert(Current().unit == "party2", "leaving preview did not refresh the current recipient")
    COMBAT, ACCESS, AURAS_SECRET = false, true, false
    entry.unit = "player"
    A.Sync("c6")
    assert(not C.AuraContainers.live.c6.aura["group:b198715"] and next(driver.events) == nil,
        "switching back to Me retained the group slot or event driver")
    local own = Live("c6", "player")
    assert(R[own].slots.s1.filter == "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY",
        "Me cannot track the hidden player proxy without self-targeting")
    entry.unit = "both"
    Plan("c6", 2, { entry })
    A.Sync("c6")
    own = Live("c6", "player")
    local target = Live("c6", "target")
    assert(R[own].slots.s1.filter == R[target].slots.s1.filter
        and R[own].slots.s1.filter == "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY",
        "Both must include the same hidden tracking auras on player and target")
    A.Release("c6")
    RunTimers()
    before = reads
    RunTimers()
    assert(reads == before, "recipient tracking scheduled recurring polling")

    -- Cooldown overlays consume the same recipient route only while their
    -- slot can show. Permanently covered icons beyond maxIcons get no slot.
    local overView = View("c5", 1)
    overView.showAura, overView.maxIcons = true, 1
    C.views.c5 = overView
    local host = L.EnsureBar("c5").frame
    local overlay = Aura("c5", "b198717", "b", "group", Set(33763), { family = 1, auraHelpful = true })
    overlay.icon = CreateFrame("Frame", nil, host)
    overlay.icon.layShown = false
    local covered = Aura("c5", "b198718", "b", "group", Set(33763), { family = 1, auraHelpful = true })
    covered.icon = CreateFrame("Frame", nil, host)
    covered.icon.layShown = false
    recipients.party1, recipients.party2 = true, nil
    Plan("c5", 1, { overlay, covered })
    A.Sync("c5")
    local over = C.AuraContainers.live.c5.over
    assert(over["group:b198717"] and not over["group:b198718"], "maxIcons failed to bound group overlay construction")
    assert(next(driver.events) == nil, "an inactive overlay retained the recipient driver")
    before = reads
    Fire("UNIT_AURA", "party1")
    RunTimers()
    assert(reads == before, "an inactive overlay still read recipient auras")
    overlay.icon.layShown = true
    A.OverlayShown(overlay, true)
    RunTimers()
    assert(over["group:b198717"].unit == "party1" and driver.events.UNIT_AURA,
        "shown overlay did not seed its current recipient")
    A.OverlayShown(overlay, false)
    assert(next(driver.events) == nil, "hidden overlay retained its recipient work")
    A.Release("c5")
    S.CreateFrame = create
end)()
end
]=])
print("suite_cdm_group_buffs_contract: ok " .. (arg[2] or "Mainline"))
