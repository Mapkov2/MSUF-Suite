-- Server replies during combat are remembered without running planner work.
local root = assert(arg[1], "repository root required")
local selected, saved = arg[2], arg
arg = { root, "--fixture" }
local Fixture = assert(loadfile(root .. "/tools/tests/suite_planning_tools_contract.lua"))()
arg = saved
local function Scenario(forever)
    local st, NS, S, Plan, owner = Fixture()
    NS.Client.isForever = forever
    st.runs = { { mapChallengeModeID = 1, level = 12, completed = true } }
    owner:Enable()
    assert(st.requests == 1 and (forever or st.mapRequests == 1), "initial server request missing")
    local scheduled, rootBefore = st.scheduled, NS.RootDB.suitePlanning
    st.Event("PLAYER_REGEN_DISABLED")
    assert(st.pending == nil, "combat did not cancel pending capture")
    for _ = 1, 5 do
        st.Event("UPDATE_INSTANCE_INFO")
        if not forever then st.Event("CHALLENGE_MODE_MAPS_UPDATE") end
    end
    assert(st.pending == nil and st.scheduled == scheduled and NS.RootDB.suitePlanning == rootBefore,
        "readiness reply scheduled combat work or wrote a saved snapshot")
    assert(Plan.Weekly.lockoutsReady == true and (forever or Plan.Weekly.seasonReady == true),
        "combat-time reply was lost instead of retaining only readiness")
    st.Event("PLAYER_REGEN_ENABLED")
    assert(st.scheduled == scheduled + 1 and st.Flush(), "one post-combat refresh required")
    local entry = assert(Plan.Account().characters[st.guid])
    assert(entry.lockoutsPending == false and entry.lockouts[1].name == "Raid",
        "available lockouts remained pending after the combat-time reply")
    if not forever then
        assert(entry.rating == 2450 and entry.runCount == 1 and entry.runHighest == 12,
            "combat-time map reply did not populate season/runs on catch-up")
    end
    assert(st.requests == 1 and (forever or st.mapRequests == 1), "reply recovery re-requested server data")
    for _ = 1, 3 do
        st.Event("PLAYER_REGEN_DISABLED")
        st.Event("PLAYER_REGEN_ENABLED")
        st.Flush()
    end
    assert(st.requests == 1 and (forever or st.mapRequests == 1), "ordinary pulls re-requested server data")
    Plan.Weekly.lockoutsReady, Plan.Weekly.seasonReady = nil, nil
    st.Event("PLAYER_LEAVING_WORLD")
    st.Event("UPDATE_INSTANCE_INFO")
    st.Event("CHALLENGE_MODE_MAPS_UPDATE")
    assert(not Plan.Weekly.lockoutsReady and not Plan.Weekly.seasonReady and st.pending == nil,
        "leaving-world callback resurrected readiness or refresh")
    owner:Disable()
    owner.active = false
    st.Event("UPDATE_INSTANCE_INFO")
    st.Event("CHALLENGE_MODE_MAPS_UPDATE")
    assert(not Plan.Weekly.lockoutsReady and not Plan.Weekly.seasonReady and st.pending == nil,
        "stale disabled callback resumed the planner")
    print((forever and "Forever" or "Mainline") .. ": readiness-only combat replies and one catch-up passed")
end
if not selected or selected == "Mainline" then Scenario(false) end
if not selected or selected == "Forever" then Scenario(true) end
