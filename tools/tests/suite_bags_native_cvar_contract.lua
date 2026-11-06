local root = assert(arg[1])
local client = arg[2] or "Mainline"
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local function World()
    local W = H.New(root, {client=client,config={windowPresentation=1}})
    W.writes, W.eventDepth, W.behavior = 0, 0, "normal"
    function W.ModeEvent(payload, committed)
        W.eventDepth = W.eventDepth + 1
        W.Fire("USE_COMBINED_BAGS_CHANGED", payload)
        W.eventDepth = W.eventDepth - 1
        if committed ~= nil then W.cvars.combinedBags = committed end
    end
    C_CVar.SetCVar = function(key, value)
        if key ~= "combinedBags" then W.cvars[key] = tostring(value); return end
        W.writes = W.writes + 1
        assert(W.writes < 6, "CVar write loop")
        assert(W.eventDepth == 0, "combinedBags write during its own native event")
        assert(not W.combat and not W.fighting, "CVar write during combat edge/lockdown")
        if W.behavior == "hostile" then W.ModeEvent(false)
        elseif W.behavior ~= "reject" then W.ModeEvent(tostring(value)=="1", tostring(value)) end
    end
    return W
end
local cases = {"startup", "true", "false", "burst", "flip", "reject", "hostile", "combat", "edge",
    "queuedCombat", "disable", "reenable", "restore"}
for _, case in ipairs(cases) do
    local W = World()
    if case == "startup" or case == "restore" then W.cvars.combinedBags = "0" end
    W.Apply()
    W.Settle()
    if case == "startup" then
        assert(W.writes==1 and W.cvars.combinedBags=="1", "initial native split bags did not enable once")
    elseif case == "restore" then
        W.S.Set("bags", "enabled", false)
        W.Settle()
        assert(W.cvars.combinedBags=="0" and W.writes==2, "disable did not restore original split mode")
    else
        assert(W.writes==0, "already combined bags were rewritten")
        if case == "true" then
            W.cvars.combinedBags="0"
            W.ModeEvent(true, "1")
        else
            if case == "combat" then W.EnterCombat() end
            if case == "edge" then W.fighting=true; W.Fire("PLAYER_REGEN_DISABLED") end
            W.ModeEvent(false, "0")
            assert(W.writes==0, "native false event was handled synchronously")
            if case == "burst" then for i=1,10 do W.ModeEvent(false, "0") end end
            if case == "flip" then W.ModeEvent(true, "1") end
            if case == "reject" or case == "hostile" then W.behavior=case end
            if case == "queuedCombat" then W.EnterCombat() end
            if case == "disable" or case == "reenable" then W.S.Set("bags", "enabled", false) end
            if case == "reenable" then W.S.Set("bags", "enabled", true) end
        end
        W.Settle()
        if case=="combat" or case=="edge" or case=="queuedCombat" then
            assert(W.writes==0, "pending CVar correction crossed combat")
            W.LeaveCombat()
            if W.queuedApply then W.queuedApply=nil; W.Apply() end
            W.Settle()
        end
        local noWrite = case=="true" or case=="flip" or case=="disable"
        assert(W.writes==(noWrite and 0 or 1), "mode enforcement must be one bounded deferred attempt: "..case)
        if case=="reject" or case=="hostile" or case=="disable" then
            assert(W.cvars.combinedBags=="0", "rejected/disabled native mode changed")
        else assert(W.cvars.combinedBags=="1", "committed native mode was not restored: "..case) end
    end
    local writes = W.writes
    for i=1,5 do W.Frame() end
    assert(W.writes==writes and #W.timers==0, "automatic CVar retry loop: "..case)
    assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0, "native callback error/ownership violation: "..case)
end
print("Native precommit CVar events, bounded writes, combat and lifecycle passed: "..client)
