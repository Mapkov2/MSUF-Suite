local root = assert(arg[1])
local flavor = arg[2] or "Mainline"
assert(flavor == "Mainline" or flavor == "Forever")
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
do
    Suite.Client.isForever = arg[2] == "Forever"
    assert(not module.active, "the cold editor must work while the module is off")
    local setReads, infoReads = 0, 0
    local nativeSet, nativeInfo = C_CooldownViewer.GetCooldownViewerCategorySet, C_CooldownViewer.GetCooldownViewerCooldownInfo
    C_CooldownViewer.GetCooldownViewerCategorySet = function(...)
        setReads = setReads + 1
        return nativeSet(...)
    end
    C_CooldownViewer.GetCooldownViewerCooldownInfo = function(...)
        infoReads = infoReads + 1
        return nativeInfo(...)
    end
    local function NativeEvent(event)
        for _, frame in ipairs(all) do
            if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event) end
        end
    end
    local function KnownRow()
        for _, row in ipairs(S.CooldownManagerCatalogEntries(1)) do
            if row.key == "b13" then return row.known end
        end
    end
    assert(KnownRow() == false)
    local generation = C.Catalog.generation
    local frames, pending, before = #all, PendingTimers(), infoReads
    infos[13].isKnown, known[103] = true, true
    NativeEvent("SPELLS_CHANGED")
    assert(infoReads == before and PendingTimers() == pending, "invalidation must not scan or schedule work")
    assert(KnownRow() == true, "same-spec talent change left the disabled editor's catalog stale")
    assert(C.Catalog.generation == generation + 1, "one change must require one rebuild")
    for _ = 1, 100 do C.Cold() end
    assert(infoReads > before and C.Catalog.generation == generation + 1 and #all == frames,
        "warm cold reads must reuse the catalog and observer")
    local warmSets, warmInfos = setReads, infoReads
    for _ = 1, 100 do C.Cold() end
    assert(setReads == warmSets and infoReads == warmInfos, "warm cold reads queried the native catalog")

    -- Every native invalidation route stays cheap even during event bursts.
    local changes = { "TRAIT_CONFIG_UPDATED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "COOLDOWN_VIEWER_DATA_LOADED",
        "COOLDOWN_VIEWER_TABLE_HOTFIXED", "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_ICON" }
    for _, event in ipairs(changes) do
        local prior = C.Catalog.generation
        infos[13].isKnown = not infos[13].isKnown
        local reads = infoReads
        for _ = 1, 20 do NativeEvent(event) end
        assert(infoReads == reads, event .. " scanned before an editor read")
        assert(KnownRow() == infos[13].isKnown and C.Catalog.generation == prior + 1,
            event .. " did not refresh the next editor read once")
    end
    for _, event in ipairs({ "CooldownViewerSettings.OnPendingChanges", "CooldownViewerSettings.OnHide" }) do
        local callback = assert(registry[event], "missing layout invalidation")
        local prior = C.Catalog.generation
        infos[13].isKnown = not infos[13].isKnown
        callback.fn(callback.owner)
        assert(KnownRow() == infos[13].isKnown and C.Catalog.generation == prior + 1,
            "Blizzard layout callback left the cold snapshot stale")
    end

    -- Combat only records the change. A later safe read consumes it.
    local prior, reads = C.Catalog.generation, infoReads
    combat = true
    infos[13].isKnown = not infos[13].isKnown
    NativeEvent("SPELLS_CHANGED")
    C.Cold()
    assert(C.Catalog.generation == prior and infoReads == reads, "cold editor scanned the catalog in combat")
    combat = false
    assert(KnownRow() == infos[13].isKnown and C.Catalog.generation == prior + 1,
        "combat-deferred invalidation was lost")

    -- Not-ready native data and a failed read remain dirty, without a poll.
    local ready = C.Catalog.Ready
    C.Catalog.Ready = function() return false end
    infos[13].isKnown = not infos[13].isKnown
    NativeEvent("SPELLS_CHANGED")
    prior, pending = C.Catalog.generation, PendingTimers()
    C.Cold()
    assert(C.Catalog.generation == prior and PendingTimers() == pending, "unready cold data scheduled a poll")
    C.Catalog.Ready = ready
    assert(KnownRow() == infos[13].isKnown and C.Catalog.generation == prior + 1, "not-ready data became a clean cache")
    local rebuild = C.Catalog.Rebuild
    C.Catalog.Rebuild = function() error("cold read probe") end
    NativeEvent("SPELLS_CHANGED")
    assert(not pcall(C.Cold), "probe must fail its native read")
    C.Catalog.Rebuild = rebuild
    prior = C.Catalog.generation
    C.Cold()
    assert(C.Catalog.generation == prior + 1, "failed cold read lost its retry")

    -- Activation hands invalidation to normal runtime events. A later
    -- disabled inspection starts fresh and reuses the same cold frame.
    local watcher = assert(registry["CooldownViewerSettings.OnHide"]).owner
    module.context, module.config, module.active = S.NewContext(ID), S.Config(ID), true
    module:Enable()
    Run()
    assert(next(watcher.events) == nil, "cold native listeners survived activation")
    assert(registry["CooldownViewerSettings.OnHide"].owner == module.context,
        "cold callbacks survived activation or replaced the runtime callback")
    module.active = false
    module:Disable()
    module.context:Release()
    Run(5)
    assert(registry["CooldownViewerSettings.OnHide"] == nil, "normal release kept a layout callback")
    infos[13].isKnown = not infos[13].isKnown
    assert(KnownRow() == infos[13].isKnown, "first read after release reused the pre-disable catalog")
    assert(registry["CooldownViewerSettings.OnHide"].owner == watcher, "cold observer was recreated")
    for _, frame in ipairs(all) do assert(not frame.scripts.OnUpdate, "cold snapshot installed a polling driver") end
    print("cold CDM catalog: same-spec/native/layout invalidation, warm reuse, combat/readiness retry and lifecycle passed")
end
]=], "-- Work counters: the controller reaches every layer")
