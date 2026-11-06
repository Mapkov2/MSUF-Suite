-- Real adapter and motion entrypoints. Rendering/texture streaming still needs
-- native acceptance; this contract pins who may animate the map's render tree.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message) assert(value, message) checks = checks + 1 end
local function Noop() end

local function Run(flavor)
    arg[2], arg[3] = flavor, "coverage"
    local H = assert(loadfile(root .. "/tools/tests/suite_skin_menu_transitions_contract.lua"))()
    arg[3] = nil
    local NS, Frame, Load = H.NS, H.Frame, H.Load
    local forever = flavor == "Forever"
    local jobs = {}
    NS.DB.skins = {}
    NS.Registry.QueueJob = function(callback) jobs[callback] = true end
    NS.Registry.NotifyListeners = Noop
    NS.WindowControls = { TrackFocus = Noop, Attach = Noop, DisableOwner = Noop, Refresh = Noop }
    NS.Checkmarks.TrackControlTree = Noop
    NS.QuestText = { Activate = Noop, Deactivate = Noop }
    NS.Cosmetics = { Fade = Noop, RestoreOwner = Noop }
    NS.ScrollMotion = { IsQuestScroll = function() return false end, Track = Noop, ReleaseOwner = Noop }
    NS.SocialUISkin = { SetMotionProvider = Noop }
    NS.GenericWindows.SetCollapseMotionProvider = Noop
    NS.GenericWindows.SetMenuMotionProvider = function(track, release)
        NS.GenericWindows.TrackMenuMotion = track
        NS.GenericWindows.Disable = function(owner) release(owner) return true end
    end
    local painted = {}
    NS.Surface = { Attach = function(target, spec)
        painted[target] = spec
        return { spec = spec }
    end, SetVisible = Noop }
    NS.ControlSkin = { ApplyButton = function() return {} end }
    EventRegistry = Frame()
    QuestLogQuests_Update = nil
    Load("Adapters/AdapterKit.lua")
    Load("Rendering/LegacyScrollMotion.lua")
    Load("Rendering/CollapseCollectionRows.lua")
    Load("Rendering/CollapseCollections.lua")
    Load("Rendering/MenuMotion.lua")
    Load("Adapters/WorldMap.lua")
    local Content, Menus, Legacy = NS.ContentMotion, NS.MenuMotion, NS.LegacyScrollMotion

    local function Flush()
        for _ = 1, 5 do
            if not next(jobs) then return end
            local pending = jobs
            jobs = {}
            for callback in pairs(pending) do callback() end
        end
        assert(not next(jobs), "map motion rediscovery did not settle")
    end
    local function Scroll(parent)
        local scroll, child = Frame(parent, true), Frame(nil, true)
        scroll.kind, scroll.scrollChild, scroll.Child = "ScrollFrame", child, child
        child.parent, scroll.children = scroll, { child }
        return scroll, child
    end
    local map = Frame(UIParent, true)
    local canvasScroll, canvas = Scroll(map)
    local quest = Frame(map, true)
    local questScroll = Scroll(quest)
    map.ScrollContainer, map.QuestLog = canvasScroll, quest
    map.children, quest.children = { canvasScroll, quest }, { questScroll }
    if forever then
        -- Native Forever XML adds these even in keyboard/mouse mode.
        canvas.smartNavigationIgnored = true
        map.OverscrollBG = Frame(map, true)
        map.children[#map.children + 1] = map.OverscrollBG
    end
    local exploration, details = Frame(canvas, true), Frame(canvas, true)
    canvas.children = { exploration, details }
    exploration.alpha, details.alpha = 0, 0
    local updates = 0
    local function Loaded(frame) updates = updates + 1 frame.alpha = 1 end
    exploration:SetScript("OnUpdate", Loaded)
    details:SetScript("OnUpdate", Loaded)
    _G.WorldMapFrame = map

    Check(NS.Adapters.Apply("worldMap"), flavor .. ": map skin failed to apply")
    Flush()
    Check(painted[map] and painted[quest], flavor .. ": map or quest chrome was removed")
    Check(Legacy.states[questScroll] ~= nil, flavor .. ": quest list lost its scroll motion")
    Check(Content.HasOpeningFade(quest) == forever, flavor .. ": quest opening scope changed")
    Check(Content.HasOpeningFade(map) == not forever, flavor .. ": map root has an unexpected opening fade")
    Check((Legacy.states[canvasScroll] ~= nil) == not forever,
        flavor .. ": native map canvas was adopted as a legacy list")
    Check(not painted[canvas] and not painted[exploration] and not painted[details],
        flavor .. ": semantic map content was skinned")

    map:Fire("OnShow")
    canvasScroll.scrollOffset = 64
    canvasScroll:Fire("OnVerticalScroll", 64)
    questScroll.scrollOffset = 32
    questScroll:Fire("OnVerticalScroll", 32)
    Flush()
    local travel = Legacy.states[canvasScroll] and Legacy.states[canvasScroll].current
    Check((travel ~= nil and travel.group:IsPlaying()) == not forever,
        flavor .. ": native map movement received an unexpected render translation")
    Check(Legacy.states[questScroll].current.group:IsPlaying(), flavor .. ": quest motion stopped working")
    if forever then
        Check(not Content.records[map] and not canvasScroll.hooks.OnVerticalScroll,
            flavor .. ": cold open installed a canvas animation hook")
        Check(not Menus.observers[canvas] and (not map.OverscrollBG or not Content.HasOpeningFade(map.OverscrollBG)),
            flavor .. ": motion discovery entered native map content")
    end
    Check(exploration.alpha == 0 and details.alpha == 0, "skin overrode native texture-loading alpha")
    exploration:Fire("OnUpdate")
    details:Fire("OnUpdate")
    Check(updates == 2 and exploration.alpha == 1 and details.alpha == 1,
        "skin replaced native texture-loading scripts")

    Check(NS.Adapters.SetEnabled("worldMap", false), "map skin failed to disable")
    Flush()
    Check(not Content.HasOpeningFade(map) and not Content.HasOpeningFade(quest),
        "disable retained map opening motion")
    Check(not next(Legacy.states[questScroll].owners), "disable retained quest scroll ownership")
    Check(not Legacy.states[canvasScroll] or not next(Legacy.states[canvasScroll].owners),
        "disable retained native canvas ownership")
    Check(NS.Adapters.SetEnabled("worldMap", true), "map skin failed to re-enable")
    Flush()
    Check(next(Legacy.states[questScroll].owners), "re-enable lost quest scroll ownership")
    Check(Content.HasOpeningFade(map) == not forever, "re-enable changed map motion scope")
    Check(NS.Adapters.SetEnabled("worldMap", false), "final map release failed")
    _G.WorldMapFrame = nil
    Check(H.ForeignWrites() == 0, "map motion wrote native geometry or alpha")
end

Run("Mainline")
Run("Forever")
print("Suite world map motion: " .. checks .. " checks passed (Mainline and Forever)")
