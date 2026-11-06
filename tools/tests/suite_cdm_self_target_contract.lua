local root = assert(arg[1])
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_auras_contract.lua", [=[
do (function()
    NS.Client.isForever = arg[2] == "Forever"
    local same = true
    local identity = UnitIsUnit
    UnitIsUnit = function(a, b)
        assert(a == "player" and b == "target")
        return same
    end
    FRIENDLY, COMBAT, ACCESS, AURAS_SECRET = true, false, true, false
    local ownFilter = "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
    local function Active(rec, key)
        local group = R[rec.frame].slots[key] or R[rec.frame].groups[key]
        return group.enabled ~= false and group.max ~= 0 and group.cand.maxDuration ~= 0
    end
    -- Model native identity/caster filtering: a different druid's earlier
    -- Lifebloom cannot take the player's slot, even for a custom buff entry.
    local function FirstCaster(rec, key, foreignOnly)
        local group = R[rec.frame].slots[key] or R[rec.frame].groups[key]
        assert(group.cand.includeSpellIDs[33763])
        local mine = group.filter:find("|PLAYER", 1, true) ~= nil
        if not mine then return "otherDruid" end
        return not foreignOnly and "player" or nil
    end
    for _, modern in ipairs({true, false}) do
        V125 = modern
        for _, fixed in ipairs({true, false}) do
            for _, src in ipairs({"b", "a"}) do
                local view = View("c6", 2)
                view.keepSlots, view.showMissing = fixed, false
                C.views.c6 = view
                local both = Aura("c6", src .. "33763", src, "both", Set(33763), { auraHelpful = true })
                local target = Aura("c6", "b774", "b", "target", Set(774), { auraHelpful = true })
                Plan("c6", 2, {both, target})
                same = true
                A.Sync("c6")
                local live = C.AuraContainers.live.c6.aura
                local playerRec, targetRec = live.player, live.target
                assert(Active(playerRec, fixed and "s1" or "g1"), "self target disabled the player half")
                assert(not Active(targetRec, fixed and "s1" or "g1"), "Both duplicated Lifebloom while self-targeted")
                assert(Active(targetRec, fixed and "s2" or "g2"), "self-target dedup hid an explicit Target entry")
                local key = fixed and "s1" or "g1"
                assert((R[playerRec.frame].slots[key] or R[playerRec.frame].groups[key]).filter == ownFilter,
                    "Lifebloom player binding lost own-caster filtering")
                assert(FirstCaster(playerRec, key, false) == "player" and FirstCaster(playerRec, key, true) == nil,
                    "a different druid's Lifebloom entered the player's slot")
                COMBAT, ACCESS, AURAS_SECRET = true, false, true
                same = false
                A.TargetChanged()
                assert(Active(targetRec, key), "another friendly target did not restore the Both target half")
                same = true
                A.TargetChanged()
                assert(not Active(targetRec, key) and Active(playerRec, key), "combat self-retarget duplicated Both")
                for _, unknown in ipairs({false, Secret()}) do
                    same = unknown
                    A.TargetChanged()
                    assert(Active(targetRec, key), "unknown or non-self identity suppressed the target half")
                end
                same = nil
                A.TargetChanged()
                assert(Active(targetRec, key), "nil identity suppressed the target half")
                COMBAT, ACCESS, AURAS_SECRET = false, true, false
                A.Release("c6")
            end
        end
    end
    V125 = true
    -- Custom Me remains own-only for Lifebloom and aliases containing it;
    -- unrelated custom buffs keep their existing any-caster behavior.
    local view = View("c6", 2)
    view.keepSlots, view.showMissing = true, false
    C.views.c6 = view
    local bloom = Aura("c6", "a33763", "a", "player", Set(33763), { auraHelpful = true })
    local alias = Aura("c6", "a9001", "a", "player", Set(9001,33763), { auraHelpful = true })
    local other = Aura("c6", "a9002", "a", "player", Set(9002), { auraHelpful = true })
    Plan("c6", 2, {bloom, alias, other})
    same = false
    A.Sync("c6")
    local playerRec = C.AuraContainers.live.c6.aura.player
    assert(R[playerRec.frame].slots.s1.filter == ownFilter and R[playerRec.frame].slots.s2.filter == ownFilter,
        "custom Me Lifebloom or an alias accepts other druids")
    assert(R[playerRec.frame].slots.s3.filter == "HELPFUL|INCLUDE_NAME_PLATE_ONLY",
        "own-Lifebloom correction changed unrelated custom buffs")
    A.Release("c6")
    -- Cooldown overlays use the same per-slot rule and retain a target-only
    -- overlay beside the deduplicated Both overlay.
    C.views.c6 = View("c6", 1)
    C.views.c6.showAura = true
    local host = L.EnsureBar("c6").frame
    bloom.family, bloom.unit = 1, "both"
    bloom.icon = CreateFrame("Frame", nil, host)
    bloom.icon.layShown = true
    Plan("c6", 1, {bloom})
    same = true
    A.Sync("c6")
    local overlays = C.AuraContainers.live.c6.over
    assert(Active(overlays.player, "s1") and not Active(overlays.target, "s1"), "self-target duplicated cooldown overlays")
    same = false
    A.TargetChanged()
    assert(Active(overlays.target, "s1"), "overlay did not resume for another target")
    A.Release("c6")
    UnitIsUnit = identity
end)()
end
]=])
print("suite_cdm_self_target_contract: ok " .. (arg[2] or "Mainline"))
