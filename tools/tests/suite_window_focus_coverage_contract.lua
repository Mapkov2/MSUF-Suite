-- Native companion windows and delayed-layout roots must join focus before painting.
local root = assert(arg[1])
local file = assert(io.open(root .. "/tools/tests/suite_window_focus_contract.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local stop = assert(source:find('    local a = Native("CharacterFrame"', 1, true))
local body = [======[
    Load("Adapters/CatalogGlass.lua")
    local character = Native("CharacterFrame", 100, 100, 400, 500)
    W.TrackFocus(character, "coverage")
    local professions = Native("ProfessionsFrame", 600, 200, 1, 658)
    professions:Hide()
    professions.protected, professions.explicitProtected = true, true
    _G.combat, _G.combatEdge = true, true
    Check(W.TrackFocus(professions, "coverage"), "native width-one Professions root was discarded before its first OnShow")
    professions.width = 700
    professions:Show()
    Check(F.active.frame == professions and Dimmed(character), "first protected combat layout failed to activate Professions")
    Check(not professions.geometryWrites, "focus enrollment changed protected root geometry")
    local companions = {
        "BattleNetInviteFrame",
        "AddFriendFrame",
        "AuctionHouseMultisellProgressFrame",
        "CatalogShopFrame",
        "CatalogShopRefundFrame",
        "CatalogShopTopUpFrame",
        "CreateChannelPopup",
        "CommunitiesAvatarPickerDialog",
        "CommunitiesSettingsDialog",
        "CommunitiesTicketManagerDialog",
        "CovenantPreviewFrame",
        "ExpansionTrialThanksForPlayingDialog",
        "ExpansionTrialCheckPointDialog",
        "GuildInviteFrame",
        "GroupLootHistoryFrame",
        "RolePollPopup",
        "WardrobeCustomSetEditFrame",
        "LFDRoleCheckPopup",
        "LFGDungeonReadyPopup",
        "LFGInvitePopup",
        "LFGListApplicationDialog",
        "LFGListInviteDialog",
        "PVPFramePopup",
        "PlunderstormFramePopup",
        "PVPRoleCheckPopup",
        "PVPReadyDialog",
        "PVPReadyPopup",
        "LFGReadyCheckPopup",
        "ReportCheatingDialog",
        "IslandsQueueFrame",
        "PhotoSharingFrame",
        "PhotoSharingBrowserFrame",
        "PhotoSharingBrowserPopup",
        "QuickJoinRoleSelectionFrame",
        "RecruitAFriendRewardsFrame",
        "RecruitAFriendRecruitmentFrame",
        "ReportFrame",
        "SecureTransferDialog",
        "SplashFrame",
        "PetBattleQueueReadyFrame",
        "BankCleanUpConfirmationPopup",
        "SideDressUpFrame",
        "MasterLooterFrame",
        "WowTokenRedemptionFrame",
        "WowTokenDialog",
        "NeighborhoodChangeNameDialog",
        "HousingCharterRequestSignatureDialog",
        "BuyHouseConfirmationDialog",
        "MoveHouseConfirmationDialog",
        "ImportHouseConfirmationDialog",
        "AbandonHouseConfirmationDialog",
    }
    for _, name in ipairs(companions) do
        local frame = Native(name, 1100, 100, 197, 100)
        Check(W.TrackFocus(frame, "coverage"), name .. " reviewed native dialog was excluded from focus")
        Click(character)
        Check(Dimmed(frame), name .. " native dialog was not dimmed")
        frame:Hide()
    end
    local nestedParents = {
        CalendarViewHolidayFrame = "CalendarFrame", CalendarViewRaidFrame = "CalendarFrame",
        CalendarViewEventFrame = "CalendarFrame", CalendarCreateEventFrame = "CalendarFrame",
        CalendarMassInviteFrame = "CalendarFrame", CalendarEventPickerFrame = "CalendarFrame",
        CalendarTexturePickerFrame = "CalendarFrame", CurrencyTransferLog = "TokenFrame",
        SideDressUpFrame = "RecruitAFriendRewardsFrame",
    }
    for name, parentName in pairs(nestedParents) do
        local nativeParent = Native(parentName, 900, 100, 600, 600)
        local frame = Native(name, 1200, 100, 350, 450)
        frame.parent = nativeParent
        Check(W.TrackFocus(frame, "coverage"), name .. " rejected its exact native parent")
        Click(character)
        Check(Dimmed(frame), name .. " nested companion did not dim independently")
        frame:Hide()
        local forged = Native(name, 1200, 100, 350, 450)
        forged.parent = character
        Check(not W.TrackFocus(forged, "coverage"), name .. " admitted an unrelated native parent")
        _G[name] = frame
        Check(not W.TrackFocus(forged, "coverage"), name .. " admitted a non-global lookalike")
    end
    -- Normal and cold discovery use the actual catalog, not only direct callers.
    local discovered = {}
    for _, name in ipairs(companions) do
        local frame = Native(name, 1100, 100, 350, 450)
        frame:Hide()
        discovered[#discovered + 1] = frame
    end
    NS.Client.HasAddOn = function() return true end
    NS.Client.IsAddOnLoaded = function() return true end
    NS.GenericWindows = { IsCategoryEnabled = function() return true end }
    NS.DB.skins, NS.DB.skinCategories = {}, {}
    NS.ForeverLegacyTree = { Apply = function() return true end }
    Load("Adapters/Blizzard.lua")
    Load("Rendering/WindowFocusDiscovery.lua")
    NS.Adapters.Apply("blizzardWindows")
    for _, frame in ipairs(discovered) do
        Check(F.records[frame] and F.records[frame].owners.blizzardWindows ~= nil,
            frame.name .. " absent from real cold catalog discovery")
        frame:Show()
        Check(F.active.frame == frame, frame.name .. " discovery did not observe the native first show")
        frame:Hide()
    end
    UIPanelWindows.InspectRecipeFrame = { area = "left" } -- native ProfessionsRegistration.lua
    for _, name in ipairs({ "OpenMailFrame", "InspectRecipeFrame" }) do
        local frame = Native(name, 1100, 100, 404, 658)
        Check(W.TrackFocus(frame, "coverage"), name .. " native standalone window was rejected")
        Click(character)
        Check(Dimmed(frame), name .. " did not dim after another native window was used")
        frame:Hide()
    end
    local fake = Native("InspectRecipeFrameFake", 1100, 100, 404, 658)
    Check(not W.TrackFocus(fake, "coverage"), "unreviewed lookalike was admitted")
    local nested = Native("InspectRecipeFrame", 1100, 100, 404, 658)
    nested.parent = character
    Check(not W.TrackFocus(nested, "coverage"), "native root name admitted an arbitrary nested pane")
    local scans = 0
    local function Children(parent, children)
        parent.GetChildren = function() scans = scans + 1; return unpack(children) end
    end
    local function Child(parent, kind, left, bottom, width, height)
        local child = Native("CoverageChild" .. tostring(scans), left, bottom, width, height)
        child.parent, child.kind = parent, kind
        return child
    end
    local page = Child(professions, "Frame", 600, 200, 700, 658)
    local card = Child(page, "Frame", 650, 400, 300, 100)
    local bar = Child(card, "StatusBar", 650, 400, 300, 20)
    bar.strata, bar.frameLevel = "HIGH", 100
    local tabs = Child(professions, "Frame", 620, 174, 400, 28)
    local tab = Child(tabs, "Button", 620, 174, 140, 28)
    local sideTab = Child(professions, "Frame", 1300, 600, 50, 46)
    sideTab.scripts.OnMouseDown = function() end
    Children(professions, { page, tabs, sideTab })
    Children(page, { card }); Children(card, { bar }); Children(tabs, { tab })
    professions:Hide(); professions:Show()
    Click(character)
    local state = F.records[professions]
    Check(state.strata == "HIGH", "native HIGH profession card remained above its dim veil")
    local covered = false
    for _, veil in ipairs(state.veils) do
        if veil.dim and Intersects(veil.rect, { left = 620, bottom = 174, width = 140, height = 24 }) then covered = true end
    end
    Check(covered, "Mainline native tabs below the root were omitted from dimming")
    covered = false
    for _, veil in ipairs(state.veils) do
        if veil.dim and Intersects(veil.rect, { left = 1300, bottom = 600, width = 50, height = 46 }) then covered = true end
    end
    Check(covered, "Forever native Frame side tab was omitted from dimming")
    character.left = 600
    Click(tab)
    Check(F.active.frame == professions and not Dimmed(professions), "outside native tab click did not focus its window")
    for _, veil in ipairs(F.records[character].veils) do
        Check(not veil.dim or not Intersects(veil.rect, { left = 620, bottom = 174, width = 140, height = 28 }),
            "inactive overlay shaded the active outside tab")
    end
    Tick() -- finish the finite post-input layout pass before measuring drag
    local scansBefore = scans
    held = true
    -- The engine moves the root without calling Lua setters on every frame.
    professions.protected, professions.explicitProtected = false, false
    _G.combat, _G.combatEdge = false, false
    professions:StartMoving()
    for index = 1, 100 do professions.left = 600 + index; Tick() end
    Check(scans == scansBefore, "drag rescanned the native descendants")
    held = false
    if driver.events.GLOBAL_MOUSE_UP then driver.scripts.OnEvent(driver, "GLOBAL_MOUSE_UP") end
    Tick()
    -- A click on an already-active root can create/reveal a deeper pane after
    -- GLOBAL_MOUSE_DOWN; one queued layout pass must see its new HIGH child.
    bar:Hide(); Tick()
    local hiddenPane = Child(page, "Frame", 620, 300, 300, 200)
    hiddenPane:Hide()
    Children(page, { card, hiddenPane })
    Click(tabs); Tick()
    Click(tabs)
    local lateHigh = Child(hiddenPane, "Frame", 620, 300, 300, 200)
    lateHigh.strata, lateHigh.frameLevel = "HIGH", 1800
    Children(hiddenPane, { lateHigh })
    hiddenPane:Show()
    Tick()
    Click(character)
    Check(state.strata == "HIGH" and state.level > lateHigh.frameLevel, "active native tab reveal left newly created HIGH content above dimming")
    lateHigh.frameLevel = 2500
    professions:Raise(); Tick()
    Check(state.level > lateHigh.frameLevel, "native Raise retained cached descendant levels")
    hiddenPane:Hide(); Tick()
    Check(F.records[professions].strata == "MEDIUM", "hidden raised child retained the old HIGH veil layer")
    bar:Show(); Tick()
    Check(F.records[professions].strata == "HIGH", "shown raised child failed to refresh the native veil layer")
    Click(tabs); Tick()
    held = true
    Click(tabs); Tick()
    Check(not driver.scripts.OnUpdate and driver.events.GLOBAL_MOUSE_UP,
        "held native click needs a one-shot release listener, not a polling driver")
    local releaseChild = Child(page, "Frame", 620, 300, 300, 200)
    releaseChild.strata, releaseChild.frameLevel = "HIGH", 3200
    Children(page, { card, hiddenPane, releaseChild })
    held = false
    if driver.events.GLOBAL_MOUSE_UP then driver.scripts.OnEvent(driver, "GLOBAL_MOUSE_UP") end
    Tick()
    Click(character)
    Check(state.level > releaseChild.frameLevel, "native OnClick release-created HIGH subtree escaped dimming")
    professions:Hide(); character:Hide()
    scansBefore = scans
    for index = 1, 100 do bar:Show(); bar:Hide(); Tick() end
    Check(scans == scansBefore and not driver.scripts.OnUpdate, "closed window child changes caused subtree scans or idle work")
    local scaled = Native("ProfessionsFrame", 400, 400 / 3, 700, 658)
    scaled.scale = 1.5
    local scaledTab = Child(scaled, "Frame", 1100, 400, 50, 46)
    scaledTab.scale = 1.5
    scaledTab.scripts.OnMouseDown = function() end
    Children(scaled, { scaledTab })
    W.TrackFocus(scaled, "scaled")
    character:Show(); Click(character); Tick()
    covered = false
    for _, veil in ipairs(F.records[scaled].veils) do
        if veil.dim and Intersects(veil.rect, { left = 1650, bottom = 600, width = 75, height = 69 }) then covered = true end
    end
    Check(covered, "150-percent native side tab was clipped by an unscaled gutter")
    W.DisableOwner("scaled")
    W.DisableOwner("coverage")
    W.DisableOwner("blizzardWindows")
    Check(not driver.events.GLOBAL_MOUSE_DOWN and not driver.scripts.OnUpdate, "coverage teardown retained idle work")
end
print("suite_window_focus_coverage_contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@window_focus_coverage_fixture"))()
