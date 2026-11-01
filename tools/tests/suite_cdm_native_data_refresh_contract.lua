local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
assert(flavor == "Mainline" or flavor == "Forever")
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
do
    Suite.Client.isForever = arg[2] == "Forever"
    local checks = 0
    local function Check(value, message)
        checks = checks + 1
        assert(value, message)
    end
    local function Notify()
        local callback = registry["CooldownViewerSettings.OnDataChanged"]
        if callback then callback.fn(callback.owner) end
    end
    local function KnownRow()
        for _, row in ipairs(S.CooldownManagerCatalogEntries(1)) do
            if row.key == "b71" then return row.known end
        end
    end
    -- The native slot record exists before its equipped item's known state
    -- settles. There is no layout edit and no second equipment event.
    local config = S.Config(ID)
    module.config, module.context, module.active = config, S.NewContext(ID), true
    infos[71].isKnown = false
    module:Enable()
    Run()
    Check(not C.entries.b71, "cold native trinket must initially be unavailable")
    infos[71].isKnown = true
    ResetCalls()
    for _ = 1, 20 do Notify() end
    Run()
    Check(C.entries.b71 and C.entries.b71.icon and C.entries.b71.slot == "ess",
        "late native item data left the trinket missing until the menu was opened")
    Check(Calls("catalog") == 1 and Calls("resolve") == 1, "native burst must share one catalog/resolve pass")
    Check(C.entries.b71.itemID == 7777 and C.entries.b71.equipSlot == 13, "the recovered icon must track the equipped item")
    Check(not C.Preview.mode, "recovery must not enter a menu preview")
    Check(Registered("BAG_UPDATE_COOLDOWN"), "recovered trinket must receive cooldown events")

    -- Unchanged native data may be reread, but never rebuilds the bars.
    ResetCalls()
    Notify()
    Run()
    Check(Calls("catalog") == 1 and Calls("resolve") == 0 and Calls("iconSync") == 0,
        "unchanged native data must keep the existing plans and frames")
    Check(PendingTimers() == 0, "native refresh must not start a poll")

    -- Entering another world can repeat the same late-readiness sequence.
    infos[71].isKnown = false
    Fire("PLAYER_ENTERING_WORLD")
    Run()
    Check(not C.entries.b71, "world-entry fixture must remove the unready trinket")
    infos[71].isKnown = true
    Notify()
    Run()
    Check(C.entries.b71 and C.entries.b71.icon, "world-entry data notification must restore the trinket")

    -- Native data updates also use the existing combat staging path.
    combat = true
    Fire("PLAYER_REGEN_DISABLED")
    infos[71].isKnown = false
    Notify()
    Run()
    Check(not C.entries.b71, "combat fixture must consume the unready native record")
    infos[71].isKnown = true
    Notify()
    Run()
    Check(C.entries.b71 and C.entries.b71.icon, "combat data update must complete through the existing staged resolver")
    combat = false
    Fire("PLAYER_REGEN_ENABLED")
    Run()
    Check(#dispatch.errors == 0, "native refresh must not raise through the runtime boundary")

    -- Sometimes the native slot record itself is absent from the first set.
    sets[7] = {}
    Fire("PLAYER_ENTERING_WORLD")
    Run()
    Check(not C.entries.b71, "missing native record must be absent initially")
    sets[7] = { 71 }
    Notify()
    Run()
    Check(C.entries.b71 and C.entries.b71.icon, "late native slot record must join the live bar")

    -- Refreshing source data must not bypass a deliberate user removal.
    config.listsData = assert(Codec.EncodeLists({ v = 1, hidden = { [C.state.specID] = { b71 = true } } }))
    module:Refresh()
    Run()
    Check(not C.entries.b71, "fixture must hide the trinket through its saved selection")
    Notify()
    Run()
    Check(not C.entries.b71, "native notification must preserve the user's hidden selection")

    -- With the module disabled, native notifications only invalidate the
    -- editor's snapshot; reading it later performs the single cold rebuild.
    module.active = false
    module:Disable()
    module.context:Release()
    module.context = nil
    Run(5)
    Check(not registry["CooldownViewerSettings.OnDataChanged"], "disable must release the active callback")
    infos[71].isKnown = false
    Check(KnownRow() == false, "cold snapshot must initially contain the unready slot")
    local generation, pending = C.Catalog.generation, PendingTimers()
    infos[71].isKnown = true
    for _ = 1, 20 do Notify() end
    Check(C.Catalog.generation == generation and PendingTimers() == pending, "disabled notifications must not scan or schedule")
    Check(KnownRow() == true and C.Catalog.generation == generation + 1, "native data update must invalidate the cold snapshot")
    C.Cold()
    Check(C.Catalog.generation == generation + 1, "unchanged cold reads must reuse their snapshot")
    print("native CDM data refresh: " .. checks .. " checks passed (" .. (arg[2] or "Mainline") .. ")")
end
]=], "------------------------------------------------------------------ enable: capture, takeover, first build")
