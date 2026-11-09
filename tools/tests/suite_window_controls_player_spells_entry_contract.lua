-- Real registry and dedicated-adapter entry points must reach safe geometry
-- on a first combat opening, while the expensive spell/talent skin stays queued.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_window_controls_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))', 1, true))
local fixture = source:sub(1, stop - 1) .. [[
return { NS = NS, Frame = Frame, jobs = combatJobs, reported = reported }
]]
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    for _, route in ipairs({ "adapter", "all", "direct", "loadOnDemand" }) do
        _G.combat, _G.combatEdge, _G.PlayerSpellsFrame = false, false, nil
        local H = assert(loadstring(fixture, "@player_spells_entry_fixture"))()
        local NS, Frame = H.NS, H.Frame
        NS.Client.isForever = flavor == "Forever"
        NS.DB.theme = { look = "midnight" }
        NS.Client.HasAddOn = function() return true end
        NS.Client.IsAddOnLoaded = function() return false end
        NS.SuiteOwnership = { Owns = function() return false end }
        local continuation, traversals = nil, 0
        EventUtil = { ContinueOnAddOnLoaded = function(_, callback) continuation = callback end }
        local function Heavy() traversals = traversals + 1; error("heavy spell skin ran during combat") end
        NS.Surface.Attach, NS.Surface.Ensure = Heavy, Heavy
        NS.GenericWindows = { ApplyFrame = Heavy, Apply = Heavy, Disable = function() end }
        NS.Cosmetics = { Fade = Heavy }
        local function Load(path, override)
            assert(loadfile(override or root .. "/MSUF_Suite_Skin/" .. path))("MSUF_Suite_Skin", NS)
        end
        Load("Rendering/WindowControls.lua")
        Load("Adapters/AdapterKit.lua")
        Load("Adapters/PlayerSpells.lua", os.getenv("SUITE_PLAYER_SPELLS_ENTRY_SOURCE"))
        NS.ForeverLegacyTree = { Apply = function() return true end }
        Load("Adapters/Blizzard.lua", os.getenv("SUITE_BLIZZARD_ENTRY_SOURCE"))
        if route == "loadOnDemand" then
            Check(not NS.Adapters.Apply("playerSpells") and continuation, "missing spellbook did not schedule native loading")
        end
        local frame = Frame("PlayerSpellsFrame", UIParent)
        PlayerSpellsFrame = frame
        frame.NineSlice = Frame(nil, frame)
        frame.NineSlice:SetFrameLevel(5500)
        NS.DB.windowControls.scales.PlayerSpellsFrame = 0.8
        NS.DB.windowControls.positions.PlayerSpellsFrame = { x = 300, y = -90 }
        _G.combatEdge = true
        if route == "loadOnDemand" then
            frame:Hide()
            continuation()
            Check(not NS.WindowControls.states[frame], "hidden LoD root gained geometry before its first show")
            frame:Show()
        elseif route == "direct" then NS.PlayerSpellsSkin.Apply(frame, "playerSpells")
        elseif route == "all" then NS.Adapters.ApplyAll()
        else NS.Adapters.Apply("playerSpells") end
        local state = NS.WindowControls.states[frame]
        Check(state and frame.scale == 0.8 and state.grip.shown,
            flavor .. " " .. route .. " first combat opening missed window controls")
        Check(frame.point[4] == 300 / 0.8 and frame.point[5] == -90 / 0.8,
            "cold combat entry lost the chosen position")
        Check(traversals == 0 and next(H.jobs) ~= nil, "cold geometry ran heavy work or lost its deferred skin")
        Check(#H.reported == 0, "cold adapter reported an error")
        frame:Hide()
        local writes = frame.geometryWrites
        NS.WindowControls.Refresh()
        Check(frame.geometryWrites == writes and not state.grip.scripts.OnUpdate,
            "closed spellbook retained geometry work")

        -- Real runtime protection is re-read; a new secure descendant can make
        -- the same root implicit after its initial unprotected combat opening.
        frame.protected = true
        frame:Show()
        Check(frame.geometryWrites == writes, "a newly protected spellbook was changed in combat")
        frame:Hide()
        _G.combatEdge = false
        local pending = H.jobs[state.replayKey]
        if pending then pending() end
        Check(frame.geometryWrites == writes, "closed protected recovery changed geometry")

        local forbidden = Frame("PlayerSpellsFrame", UIParent)
        PlayerSpellsFrame = forbidden
        forbidden.protected, forbidden.explicitProtected = true, true
        _G.combatEdge = true
        NS.Adapters.Apply("playerSpells")
        Check(not NS.WindowControls.states[forbidden], "explicitly secure spellbook gained cold controls")
        _G.combatEdge = false
    end
end
print("PlayerSpells combat window entry: " .. checks .. " checks passed")
