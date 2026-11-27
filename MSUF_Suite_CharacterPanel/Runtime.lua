local _, NS = ...
local Suite, Host, Text = NS.Suite, NS.Host, NS.Text
local Gear, GearActions, Pages, Routing = NS.Gear, NS.GearActions, NS.Pages, NS.Routing
local Travel, Mode = NS.Travel, Host.CharacterPanelMode
local CharacterHeader, CharacterTabs = Suite.CharacterHeader, Host.CharacterTabs
local Module = { groups = {}, details = {}, subscriptions = {}, pageEvents = {}, inspectItems = {}, header = {} }
local FRAME_NAME = "MSUFSuiteCharacterPanel"
local PLAYER, INSPECT = "character", "inspect"
local TAB_KIND = { [PLAYER] = "tab", [INSPECT] = "inspectTab" }
local OVERVIEW, EQUIPMENT, COMPARE, ATTRIBUTES, REPUTATION = "overview", "gear", "compare", "attributes", "reputation"
local CURRENCY = "currency"
local IN_COMBAT = { inCombat = true }
local ITEM_EVENTS = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }
local SCREEN_EVENTS = { "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }
local INSPECT_IDENTITY_EVENTS = { "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE" }
local MODEL_EVENTS = { "UNIT_MODEL_CHANGED" }
local SET_EVENTS = { "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED" }
local GUILD_EVENTS = { "PLAYER_GUILD_UPDATE" }
local ZONE_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }

local function Identity(unit)
    if unit then return NS.String(UnitGUID(unit)) end
end

local function HideTooltip()
    local owner = Module.tooltipOwner
    if owner and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    Module.tooltipOwner = nil
end

local function OnLeave(button)
    if Module.tooltipOwner == button then HideTooltip() end
end

local function OnEnter(button, slot)
    local data = Module.gear and Module.gear.bySlot[slot]
    if not data or not data.link then return end
    Module.tooltipOwner = button
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if Module.kind == PLAYER then GameTooltip:SetInventoryItem("player", slot)
    else GameTooltip:SetHyperlink(data.link) end
    GameTooltip:Show()
end

local function Unsubscribe()
    for event in pairs(Module.subscriptions) do Module.context:RemoveEvent(event) end
    wipe(Module.subscriptions)
    wipe(Module.pageEvents)
end

local function ClearPendingPaint()
    Module.paintJob:Clear()
    Module.dirtyAll, Module.dirtySlot, Module.dirtyHeader = nil, nil, nil
    Module.dirtyDurability, Module.dirtyModel, Module.dirtyPage, Module.dirtySets = nil, nil, nil, nil
    wipe(Module.inspectItems)
end

local function SuspendPaint()
    Travel.Stop()
    Unsubscribe()
    HideTooltip()
    ClearPendingPaint()
end

local function OnClose()
    if not Module.kind then return end
    if Module.view.currencyControls then NS.CurrencyControls.Hide(Module.view) end
    Module.currencies = nil
    if Module.view.reputationSearch then NS.ReputationSearch.Hide(Module.view) end
    Module.view.tabSearch, Module.searchState = nil, nil
    if Module.reputations then Module.reputations.query = "" end
    if Module.view.nativeLayout then Module.layoutGeometry.Present(Module.layoutRoot, nil) end
    local restoreCharacter = Module.kind == INSPECT and Module.running and not Module.replacing and Routing.Shown()
    Routing.ReleaseGearClick()
    Module.view:CancelWindowGestures()
    SuspendPaint()
    GearActions.CloseManager(Module)
    Module.appearanceJob:Clear()
    if Module.gear and Module.reader then Gear.Close(Module.reader, Module.gear) end
    Module.unit, Module.guid, Module.kind, Module.gear, Module.slot = nil, nil, nil, nil, nil
    Module.inspectGuild, Module.custom, Module.customDefinition, Module.nativeTab = nil, nil, nil, nil
    Module.gearStale, Module.durabilityStale, Module.setName = nil, nil, nil
    if restoreCharacter then Module.nativeJob:Request() end
    Module.view.frame:Hide() -- A parent hide (CharacterFrame, UIParent) keeps the shown flag; a close drops it.
end

local function Close(replacing)
    if Module.view and Module.view.frame:IsShown() then
        Module.replacing = replacing == true
        Module.view.frame:Hide()
        OnClose()
        Module.replacing = nil
    end
end

local function CancelInspect()
    Module.context:RemoveEvent("INSPECT_READY")
    Module.inspectUnit, Module.inspectGUID = nil, nil
end

local function PaintHeader()
    local average = Module.average
    if not average and Module.kind == INSPECT then average = Module.gear.visibleAverage end
    local shownAverage = Pages.FormatItemLevel(average) or "—"
    Module.view:SetHeader(Module.name, nil, shownAverage, Module.unit, Module.guid, Module.header)
end

local function ReadHeaderExtras()
    local config, data = Module.config, Module.header
    local showGuild, showZone = config.headerGuildVisible == true, config.headerZoneVisible == true
    Module.showGuild, Module.showZone = showGuild, showZone
    data.guild, data.zone = nil, nil
    if Module.kind == INSPECT then
        if showGuild then data.guild = Module.inspectGuild end
        return
    end
    if showGuild then data.guild = NS.String((GetGuildInfo("player"))) end
    if showZone then data.zone = NS.String(GetMinimapZoneText()) end
end

local function Header()
    local unit, kind = Module.unit, Module.kind
    local level = NS.Number(UnitLevel(unit))
    local class = NS.String(UnitClass(unit))
    local name = NS.String(UnitName(unit)) or Text(kind == INSPECT and "Inspect" or "Character")
    local reader = Module.reader
    local spec = reader and NS.String(reader.SpecializationName(kind, unit))
    Module.name, Module.level, Module.class = name, level, class
    Module.header.level, Module.header.class = level and level > 0 and level or nil, class
    Module.header.specialization = spec ~= class and spec or nil
    Module.average = reader and reader.AverageItemLevel(kind, unit)
    PaintHeader()
end

local function InspectSpeedChanged(relayout)
    if relayout then Travel.Summary(Module.class, Module.level) end
    Module.view:RefreshInspectSummary(Module.groups, relayout)
end

local Dirty

local function Subscribe(events, isPage)
    if not events then return end
    for i = 1, #events do
        local event = events[i]
        if isPage then Module.pageEvents[event] = true end
        if not Module.subscriptions[event] then
            local unit = event:sub(1, 5) == "UNIT_" and Module.unit or nil
            Module.context:Event(event, Dirty, IN_COMBAT, unit)
            Module.subscriptions[event] = true
        end
    end
end

local function SetEvents(events, enabled, isPage)
    if enabled then
        Subscribe(events, isPage)
        return
    end
    for i = 1, #events do
        local event = events[i]
        if Module.subscriptions[event] then
            Module.context:RemoveEvent(event)
            Module.subscriptions[event] = nil
            Module.pageEvents[event] = nil
        end
    end
end

local function SyncStatsEvents(visible, combat)
    local quick, extra = Pages.Events.overview, Pages.ExtraStatEvents
    if visible ~= (Module.subscriptions[quick[1]] == true) then SetEvents(quick, visible, true) end
    local full = visible and Module.fullStats and not combat
    if full ~= (Module.subscriptions[extra[1]] == true) then SetEvents(extra, full, true) end
end

local function PaintContextAction(event)
    local view = Module.view
    if Module.kind == INSPECT then
        view:SetContextAction(Text("Blizzard Inspect"))
    elseif Module.setManager and not Host.InCombat(event) then
        view:SetContextAction(Module.tab == EQUIPMENT and Text("Equipment check") or Text("Close"))
    elseif Module.tab == EQUIPMENT and not Host.InCombat(event) then
        view:SetContextAction(GearActions.SetLabel(Module.setName))
    else
        view:SetContextAction(Module.kind == PLAYER and Module.tab == OVERVIEW and not Host.InCombat(event) and Text("Loot goals") or nil)
    end
end

local function Paint(event)
    local view, model, tab = Module.view, Module.gear, Module.tab
    if not model then return end
    local groups, details, combat = Module.groups, Module.details, Module.kind == PLAYER and Host.InCombat(event)
    local gearTab = tab == OVERVIEW or tab == EQUIPMENT
    local listView = Module.kind == PLAYER and gearTab and view.characterView == "list"
    local showSets = GearActions.Present(Module, combat)
    if gearTab then
        wipe(details)
        Gear.Details(details, model, Module.slot, Module.kind == INSPECT)
    end
    if Module.kind == INSPECT and tab == OVERVIEW and #details == 0 then
        Travel.Start(Module.context, Module.unit, Module.guid, InspectSpeedChanged, Close)
    else
        Travel.Stop()
    end
    if Module.kind == PLAYER and (tab == OVERVIEW or tab == ATTRIBUTES) then
        SyncStatsEvents(tab == ATTRIBUTES or not listView and #details == 0, combat)
    end
    Pages.SyncCustomEvents(Module.custom, combat, SetEvents)
    if listView then
        local report = Gear.ListReport(groups, details, model, Module.reader)
        if showSets and report == groups then Pages.EquipmentSets(report, Module.setName, 1) end
        view:ShowGroups(report, combat)
    elseif gearTab then
        if #details == 0 then
            if tab == OVERVIEW and Module.kind == PLAYER then Pages.Overview(groups, Module.fullStats, combat) else wipe(groups) end
            if Module.kind == INSPECT then
                groups[#groups + 1] = Travel.Summary(Module.class, Module.level)
            else
                Pages.EquipmentSummary(groups, model)
                if showSets then Pages.EquipmentSets(groups, Module.setName, math.min(2, #groups + 1)) end
            end
        end
        if Module.kind == INSPECT or view.nativeLayout and Routing.PaperDollShown() then
            view:ShowGear(model.left, model.right, model.weapons, groups, Module.slot, details, tab == OVERVIEW, combat)
        else
            local report = #details > 0 and details or groups
            if #details == 0 and tab == EQUIPMENT and Module.reader then Gear.EquipmentList(report, model) end
            view:ShowGroups(report, combat)
        end
    elseif tab == REPUTATION then
        NS.ReputationList.Paint(Module, combat)
    elseif tab == CURRENCY then
        NS.Currency.Paint(Module, combat)
    elseif tab == ATTRIBUTES then
        view:ShowGroups(Pages.Overview(groups, true, combat), combat)
    elseif tab == COMPARE then
        wipe(groups)
        Gear.Compare(groups, Module.ownGear, model)
        view:ShowGroups(groups)
    else
        if Module.custom then Pages.Custom(groups, Module.custom, Module, combat) else Pages.Read(tab, groups, Module.config) end
        view:ShowGroups(groups, combat and Module.custom and Module.custom.hasReports)
    end
end

local function ReleaseResolvedItems()
    if Module.kind ~= INSPECT or next(Module.gear.pending) then return end
    for i = 1, #ITEM_EVENTS do
        local event = ITEM_EVENTS[i]
        Module.context:RemoveEvent(event)
        Module.subscriptions[event] = nil
    end
end

local function Flush()
    if not Module.kind then return end
    if Module.kind == INSPECT and Identity(Module.unit) ~= Module.guid then Close() return end
    local dirtySlot, dirtyAll = Module.dirtySlot, Module.dirtyAll
    Module.dirtySlot, Module.dirtyAll = nil, nil
    local custom = Module.custom
    local wantsGear, wantsDurability = Gear.Demand(Module.tab, custom)
    local readGear = wantsGear and (dirtyAll or dirtySlot)
    local readDurability = wantsDurability and Module.dirtyDurability
    local repaint = Module.dirtyPage or Module.tab == OVERVIEW or Module.tab == EQUIPMENT
        or custom and (readGear or readDurability)
    if Module.kind == PLAYER and Module.reader and readGear then
        local level = NS.Number(UnitLevel("player"))
        Gear.Read(Module.reader, Module.gear, "player", Module.guid, level, not dirtyAll and dirtySlot or nil)
    elseif next(Module.inspectItems) then
        Gear.UpdateSnapshot(Module.reader, Module.gear, Module.inspectItems, Module.level)
        wipe(Module.inspectItems)
        ReleaseResolvedItems()
        PaintHeader()
        repaint = true
    end
    if readDurability then Gear.Durability(Module.gear) end
    if Module.gear.auditFocus and (readGear or readDurability) then
        Gear.Mark(Module.gear, Module.gear.auditFocus)
    end
    if Module.dirtySets and GearActions.Refresh(Module) then repaint = true end
    Module.dirtySets = nil
    if Module.dirtyModel and not custom then Module.view:RefreshModel() end
    if Module.dirtyHeader then
        local average, level = Module.average, Module.header.level
        Header()
        if custom then
            repaint = repaint or (custom.average and average ~= Module.average) or (custom.level and level ~= Module.header.level)
        end
    end
    Module.dirtyDurability, Module.dirtyModel, Module.dirtyHeader = nil, nil, nil
    Module.dirtyPage = nil
    if repaint then Paint() end
end

function Dirty(_, event, first, success)
    if not Module.kind then return end
    if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        Module.view:CancelWindowGestures()
        if Module.view.nativeLayout and not Host.InCombat() then
            Module.layoutGeometry.WindowAction(Module.layoutRoot, "prepare")
        end
        Module.view:FitScreen()
        return
    end
    if event == "PLAYER_TARGET_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
        if Identity(Module.unit) ~= Module.guid then Close() end
        return
    end
    if event == "PLAYER_GUILD_UPDATE" then
        Module.header.guild = NS.String((GetGuildInfo(Module.unit)))
        PaintHeader()
        return
    end
    if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
        Module.header.zone = NS.String(GetMinimapZoneText())
        PaintHeader()
        return
    end
    if event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
        local id = NS.Number(first)
        if not id or not Module.gear.pending[id] then return end
        if NS.Public(success) and success == false then
            Module.gear.pending[id] = nil
            ReleaseResolvedItems()
            return
        end
        if Module.kind == INSPECT then Module.inspectItems[id] = true
        else Module.dirtyAll, Module.dirtyHeader = true, true end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        local slot = NS.Number(first)
        if not slot or not Module.gear.bySlot[slot] then return end
        if Module.setName ~= nil then Module.dirtySets = true end
        local custom = Module.custom
        if not custom or custom.audit then
            if Module.dirtySlot and Module.dirtySlot ~= slot then Module.dirtyAll = true end
            Module.dirtySlot = slot
        end
        if not custom or custom.durability then Module.dirtyDurability = true end
        Module.dirtyHeader = Module.dirtyHeader or not custom or Module.pageEvents[event]
    elseif event == "UNIT_INVENTORY_CHANGED" or event == "SOCKET_INFO_SUCCESS" then
        if event == "UNIT_INVENTORY_CHANGED" and NS.String(first) ~= "player" then return end
        Module.dirtyAll = true
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_LEVEL_UP" then
        if event == "PLAYER_SPECIALIZATION_CHANGED" and NS.String(first) ~= "player" then return end
        if not Module.custom or Module.custom.audit then Module.dirtyAll = true end
        Module.dirtyHeader = true
    elseif event == "PLAYER_XP_UPDATE" then
        if NS.String(first) ~= "player" then return end
    elseif event == "PLAYER_AVG_ITEM_LEVEL_UPDATE" then
        Module.dirtyHeader = true
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        Module.dirtyDurability = true
    elseif event == "UNIT_MODEL_CHANGED" then
        Module.dirtyModel = true
    elseif event == "EQUIPMENT_SETS_CHANGED" or event == "EQUIPMENT_SWAP_FINISHED" or event == "BAG_UPDATE_DELAYED" then
        Module.dirtySets = true
    end
    if Module.pageEvents[event] then
        if Module.tab == REPUTATION and Module.reputations and not NS.ReputationList.Update(Module.reputations, event, first) then return end
        if Module.tab == CURRENCY and not NS.Currency.Invalidate(Module.currencies, event, first) then return end
        Module.dirtyPage = true
    end
    Pages.InvalidateCustom(Module.custom, event, Module.view.tabSearch, first)
    Module.paintJob:Request()
end

local HEADER_EVENTS = { "PLAYER_AVG_ITEM_LEVEL_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED" }
local ATTRIBUTE_EVENTS = { "PLAYER_EQUIPMENT_CHANGED" }

local function SyncHeaderEvents()
    SetEvents(GUILD_EVENTS, Module.config.headerGuildVisible == true)
    SetEvents(ZONE_EVENTS, Module.config.headerZoneVisible == true)
end

local function PaintTabs()
    local tabs = CharacterHeader.Order(Module.config, TAB_KIND[Module.kind])
    Module.view:SetTabs(tabs, Module.tab)
end

local function SyncSets()
    if not GearActions.Sync(Module) then return end
    Subscribe(SET_EVENTS)
    Subscribe(ATTRIBUTE_EVENTS)
    if Module.setManager then Subscribe(GearActions.BagEvents) end
end

local function SelectTab(tab, preserveSlot, showAudit)
    if not Module.kind then return end
    HideTooltip()
    local kind, config = TAB_KIND[Module.kind], Module.config
    if not CharacterHeader.TabVisible(config, kind, tab) then tab = CharacterHeader.HomeTab(config, kind) end
    if tab ~= CURRENCY then Module.currencies = nil end
    local search = Module.searchState
    if Module.kind == PLAYER and tab ~= CURRENCY and CharacterHeader.TabSearchEnabled(config, tab) then
        if not search or search.tab ~= tab or search.config ~= config then search = { tab = tab, config = config, query = "" } end
    else search = nil end
    if Module.view.reputationSearch and (tab ~= Module.tab or search ~= Module.searchState) then NS.ReputationSearch.Hide(Module.view) end
    Module.searchState, Module.view.tabSearch = search, not Host.InCombat() and search or nil
    if Module.reputations then Module.reputations.updateOnly = false end
    local definition = Module.kind == PLAYER and tab:match("^custom%d+$") and CharacterTabs.Find(config, tab)
    Module.customDefinition, Module.custom = definition, definition and Pages.CustomPlan(definition, true) or nil
    if not preserveSlot or tab ~= Module.tab then
        Module.slot, Module.wantsSetManager = nil, tab == EQUIPMENT and not showAudit
        GearActions.CloseManager(Module)
    end
    Module.tab, Module.dirtyPage, Module.reputationKey = tab, nil, Pages.ReputationKey(tab, config, Module.custom)
    Unsubscribe()
    Subscribe(SCREEN_EVENTS)
    if Module.kind == PLAYER then
        local custom = Module.custom
        if custom then
            Subscribe(HEADER_EVENTS)
            Subscribe(Pages.CustomEvents(custom, Module.reputationKey), true)
        elseif tab == OVERVIEW or tab == EQUIPMENT then
            Subscribe(Gear.Events)
        else
            local attributes = tab == ATTRIBUTES
            Subscribe(HEADER_EVENTS, attributes)
            if tab ~= REPUTATION or not Host.InCombat() then
                Subscribe(attributes and ATTRIBUTE_EVENTS or tab == CURRENCY and NS.Currency.Events or Pages.ReportEvents(tab, config), true)
            end
        end
        Module.fullStats = tab == ATTRIBUTES or Module.config.showFullStats ~= false
        SyncHeaderEvents()
        Gear.SyncPlayer(Module)
        Module.showSets = config.showEquipmentSetsInOverview ~= false
        SyncSets()
    else
        Subscribe(INSPECT_IDENTITY_EVENTS)
        Subscribe(MODEL_EVENTS)
        if next(Module.gear.pending) then Subscribe(ITEM_EVENTS) end
        if tab == COMPARE then
            local own = Module.ownGear
            Gear.Read(Module.reader, own, "player", Identity("player"), NS.Number(UnitLevel("player")))
        end
    end
    PaintTabs()
    PaintContextAction()
    Paint()
end

local function OnMinimized(minimized, tab)
    if Module.kind ~= INSPECT then return end
    if minimized then
        SuspendPaint()
        Subscribe(SCREEN_EVENTS)
        Subscribe(INSPECT_IDENTITY_EVENTS)
        return
    end

    local model = Module.gear
    if Identity(Module.unit) ~= Module.guid then Close() return end
    if next(model.pending) then Gear.UpdateSnapshot(Module.reader, model, model.pending, Module.level) end
    PaintHeader()
    SelectTab(tab or Module.tab, true)
end

local function ClickSlot(slot, _, mouse)
    if not Module.kind then return end
    local combat = Host.InCombat()
    if Module.kind == INSPECT and combat or Module.kind == PLAYER and mouse == "RightButton" then return end
    local row = Module.gear.bySlot[slot]
    if not combat and row and row.link and (IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP")) then
        HandleModifiedItemClick(row.link)
        return
    end
    if Module.slot == slot then slot = nil end
    Module.slot = slot
    Paint()
end

local function ToggleSetManager()
    if Module.setManager then
        GearActions.CloseManager(Module)
    elseif not GearActions.OpenManager(Module) then return end
    Module.wantsSetManager = Module.setManager ~= nil
    SetEvents(GearActions.BagEvents, Module.wantsSetManager)
    PaintContextAction()
    Paint()
end

local function GroupClick(index, button)
    if Module.kind ~= PLAYER then return end
    if Module.tab == REPUTATION then return NS.ReputationList.Toggle(Module, index) end
    if Module.tab == CURRENCY then return NS.Currency.Click(Module.currencies, index, button) end
    if index == "equipmentSets" then
        if Host.InCombat() or Module.setManager then return end
        if Module.tab ~= EQUIPMENT and CharacterHeader.TabVisible(Module.config, "tab", EQUIPMENT) then return SelectTab(EQUIPMENT) end
        return ToggleSetManager()
    end
    if Module.tab == OVERVIEW or Module.tab == EQUIPMENT then
        local model = Module.gear
        if type(index) == "string" then
            if model.auditFocus == index then index = nil end
            Gear.Mark(model, index)
            if Module.tab == OVERVIEW and not Module.view.nativeLayout and CharacterHeader.TabVisible(Module.config, "tab", EQUIPMENT) then
                return SelectTab(EQUIPMENT, nil, true)
            end
        elseif model.bySlot[index] then
            if Module.slot == index then index = nil end
            Module.slot = index
        end
        Paint()
    elseif not Host.InCombat() and Pages.Toggle(Module.tab, index) then
        Module.dirtyPage = true
        Module.paintJob:Request()
    end
end

local function ContextAction(button)
    if Module.kind == PLAYER and (Module.tab == EQUIPMENT or Module.setManager) then return ToggleSetManager() end
    if Module.kind == PLAYER and Module.tab == OVERVIEW then return GearActions.OpenLootGoals() end
    if Module.kind ~= INSPECT or not NS.CanReplace() or Module.view:IsMinimized() then return end
    local unit = Module.unit
    if Identity(unit) ~= Module.guid then return end
    local allowed = CanInspect(unit, true)
    if not NS.Public(allowed) or allowed ~= true then return end
    CancelInspect()
    Module.context:Cancel(CancelInspect)
    Module.inspectJob:Clear()
    Module.openingNativeInspect = true
    local opened = Suite.Dispatch(Suite.Finish, InspectUnit, unit)
    Module.openingNativeInspect = nil
    if opened and NS.String(InspectFrame.unit) == unit then Close() end
end

local function WindowAction(action, control)
    local geometry, root = Module.layoutGeometry, Module.layoutRoot
    if not geometry then return end
    if action == "moveStop" or action == "scaleStop" or Module.kind == PLAYER and not Host.InCombat() then
        return geometry.WindowAction(root, action, control)
    end
end

local CALLBACKS = {
    frameName = FRAME_NAME, tab = SelectTab, slot = ClickSlot, close = Close, group = GroupClick,
    enter = OnEnter, leave = OnLeave,
    minimized = OnMinimized,
    contextAction = ContextAction, windowAction = WindowAction,
}

function NS.UpdateTrackedReputation(factionID)
    if Module.trackedReputation == factionID then return end
    Module.trackedReputation = factionID
    if Module.kind == PLAYER and Module.view then Module.view:SetTrackedReputation(factionID) end
end

local function AvailableSkin()
    if Module.kind == INSPECT then return Host.Skin.Acquire("characterPanelInspect") end
    if Module.view.nativeLayout then return Module.context:Skin() end
    if Module.reader or not Host.InCombat() then return Host.Skin.Acquire("characterPanelDock") end
end

local function RefreshVisibleAppearance()
    local view = Module.view
    if Module.running and view and view.frame:IsShown() then
        view:ApplyWindowPreferences(Suite.ModuleState("characterPanel"))
        view:RefreshAppearance(AvailableSkin(), Module.config)
        if view.nativeLayout and not Host.InCombat() then Module.layoutGeometry.Apply(Module.layoutRoot, Module.layoutPlan) end
        local previousView = view.characterView
        view.characterView = Routing.CharacterView(Module.kind)
        if not view:IsMinimized() then
            if Module.showGuild ~= (Module.config.headerGuildVisible == true)
                or Module.showZone ~= (Module.config.headerZoneVisible == true) then
                ReadHeaderExtras()
                PaintHeader()
            end
            local tab, config = Module.tab, Module.config
            if previousView ~= view.characterView or not CharacterHeader.TabVisible(config, TAB_KIND[Module.kind], tab)
                or Module.customDefinition and CharacterTabs.Find(config, tab) ~= Module.customDefinition
                or Module.kind == PLAYER and tab ~= CURRENCY and (Module.searchState ~= nil) ~= CharacterHeader.TabSearchEnabled(config, tab)
                or Module.searchState and Module.searchState.config ~= config
                or Module.kind == PLAYER and tab == OVERVIEW and (Module.fullStats ~= (config.showFullStats ~= false)
                    or Module.showSets ~= (config.showEquipmentSetsInOverview ~= false))
                or Module.reputationKey ~= Pages.ReputationKey(tab, config, Module.custom) then
                return SelectTab(tab, true)
            end
            if Module.kind == PLAYER then SyncHeaderEvents() end
            PaintTabs()
            PaintContextAction()
            if tab == CURRENCY then Paint() end
        end
    end
end

local function PrimeEquipmentReader()
    if not Module.reader then
        Module.reader = Host.Skin.EquipmentReader or not Host.InCombat() and Host.Skin.GetEquipmentReader() or nil
    end
    return Module.reader
end

local function ReleaseNativeLayout()
    local geometry, root = Module.layoutGeometry, Module.layoutRoot
    if not geometry then return end
    geometry.WindowAction(root, "release")
    geometry.Release(root)
    Module.layoutGeometry, Module.layoutRoot = nil, nil
end

local function AcquireView(nativeRoot)
    local plan = nativeRoot and nativeRoot == Module.layoutRoot and Module.layoutPlan or nil
    local key = plan and "characterView" or nativeRoot and "dockView" or "inspectView"
    local view = Module[key]
    if not view then
        view = NS.View.New(CALLBACKS, nil, nativeRoot, plan)
        view.frame:HookScript("OnHide", function() if Module.view == view then OnClose() end end)
        if not nativeRoot then UISpecialFrames[#UISpecialFrames + 1] = FRAME_NAME end
        Module[key] = view
    end
    return view
end

local function PrepareNativeLayout(root)
    if not root or Module.layoutRoot == root or Host.InCombat() then return end
    if root:IsVisible() and Routing.Shown() ~= root then return end
    local geometry = Host.Skin.CharacterGeometry
    if not geometry then return end
    if not Module.ownGear then Module.ownGear = Gear.New() end
    local plan = Module.layoutPlan or NS.View.NativeLayout(Module.ownGear)
    Module.layoutPlan = plan
    if not geometry.Apply(root, plan) then return end
    Module.layoutRoot, Module.layoutGeometry = root, geometry
    AcquireView(root):RefreshAppearance(Module.context:Skin(), Module.config)
end

local function Open(kind, unit, guid, tab, nativeRoot, nativeTab)
    local reader = PrimeEquipmentReader()
    if kind == INSPECT and not reader then return false end
    local playerVisible = kind == INSPECT and Module.kind == PLAYER
    if not playerVisible and (Module.kind ~= kind or Module.guid ~= guid) then Close(true) end
    if not Module.ownGear then Module.ownGear = Gear.New() end
    if kind == INSPECT and not Module.inspectGear then Module.inspectGear = Gear.New() end
    local model = kind == PLAYER and Module.ownGear or Module.inspectGear
    if kind == INSPECT then
        Gear.Read(reader, model, unit, guid, NS.Number(UnitLevel(unit)))
        if model.missingLinks then return false end
    elseif not reader then model.missingLinks = true end
    if playerVisible then Close(true) end
    local view = AcquireView(nativeRoot)
    Module.view, Module.nativeTab = view, nativeTab
    Module.kind, Module.unit, Module.guid, Module.gear = kind, unit, guid, model
    view.characterView = Routing.CharacterView(kind)
    view:SetTrackedReputation(kind == PLAYER and Module.trackedReputation or nil)
    if kind == PLAYER then
        WindowAction("prepare")
        Module.gearStale, Module.durabilityStale = true, true
    else
        Module.inspectGuild = NS.String(select(3, C_PaperDollInfo.GetInspectGuildInfo(unit)))
    end
    view:SetMinimized(false, nil, true)
    view:RefreshAppearance(AvailableSkin(), Module.config)
    view:ApplyWindowPreferences(Suite.ModuleState("characterPanel"))
    view:FitScreen()
    ReadHeaderExtras()
    Header()
    SelectTab(tab)
    view.frame:Show()
    if view.nativeLayout then Module.layoutGeometry.Present(nativeRoot, view.frame) end
    if kind == INSPECT then view:RefreshModel() end
    return true
end
local function OpenNativeCharacter()
    local root, tab, requested = Routing.TakeTabRequest()
    if not Module.running or not root or not NS.CanOpenCharacter() then return end
    if Module.kind == PLAYER and Module.nativeTab == tab and (not requested or Module.tab == requested) then return end
    local destination = requested or (tab == OVERVIEW and CharacterHeader.HomeTab(Module.config, "tab") or tab)
    if Module.kind == PLAYER then
        Module.nativeTab = tab
        return SelectTab(destination)
    end
    PrepareNativeLayout(root)
    Open(PLAYER, "player", Identity("player") or "player", destination, root, tab)
end
local function NativeVisibilityChanged(root, requestedTab)
    if requestedTab and Module.tab ~= requestedTab then Module.nativeTab = nil end
    if root and NS.CanOpenCharacter() then return Module.nativeJob:Request() end
    Module.nativeJob:Clear()
    Module.nativeFitJob:Clear()
    if Module.kind == PLAYER then Close() end
    if not Host.InCombat() then
        local native = Routing.Root()
        if native and native:IsVisible() then ReleaseNativeLayout() else PrepareNativeLayout(native) end
    end
end

local function FitNative()
    if Module.kind ~= PLAYER then return end
    if Module.view.nativeLayout then
        return Module.layoutGeometry.RefreshChrome(Module.layoutRoot)
    end
    Module.view:FitScreen()
end
local function NativeSizeChanged()
    if Module.kind == PLAYER then Module.nativeFitJob:Request() end
end
local function InspectInputMode(_, event, cvar)
    if event == "CVAR_UPDATE" and (NS.String(cvar) or ""):lower() ~= "gamepadenable" then return end
    if Module.kind == PLAYER and Module.view.glassLook then Module.appearanceJob:Request() end
    if Module.kind ~= INSPECT and not Routing.HasBindingRoutes() then return end
    Routing.UpdateBindings()
    if Module.kind == INSPECT and Suite.GamepadUI() then Close() end
end

local function HandoffInspect()
    local unit, guid = Module.inspectUnit, Module.inspectGUID
    CancelInspect()
    Module.context:Cancel(CancelInspect)
    local frame = InspectFrame
    if not Module.running or not guid or not NS.CanReplace() or not frame:IsShown() then return end
    if NS.String(frame.unit) ~= unit or Identity(unit) ~= guid then return end
    if Open(INSPECT, unit, guid, OVERVIEW) then
        if Host.InCombat() then Close() return end
        HideUIPanel(frame)
        if frame:IsShown() then Close() end
    end
end

local function InspectReady(_, _, guid)
    if not Module.inspectGUID or NS.String(guid) ~= Module.inspectGUID then return end
    Module.inspectJob:Request()
end

local inspectHooked
local function InspectRequested(unit)
    if not Module.running or Module.openingNativeInspect then return end
    CancelInspect()
    Module.inspectJob:Clear()
    if not NS.CanReplace() then return end
    unit = NS.String(unit)
    local guid = Identity(unit)
    if not guid or NS.String(InspectFrame.unit) ~= unit then return end
    if Module.kind == INSPECT and Module.guid ~= guid then Close() end
    Module.inspectUnit, Module.inspectGUID = unit, guid
    Module.context:Event("INSPECT_READY", InspectReady, IN_COMBAT)
    Module.context:After(10, CancelInspect)
end

local function HookInspect()
    if inspectHooked or type(InspectFrame_Show) ~= "function" then return end
    hooksecurefunc("InspectFrame_Show", InspectRequested)
    inspectHooked = true
    Module.context:RemoveEvent("ADDON_LOADED")
end

local function AddOnLoaded(_, _, addon)
    if addon == "Blizzard_InspectUI" then HookInspect() end
end

local function RepaintAfterCombat()
    ClearPendingPaint()
    if Module.guid == "player" then Module.guid = Identity("player") or Module.guid end
    Module.gearStale, Module.durabilityStale = true, true
    local tab = Module.tab
    Module.view.tabSearch = Module.searchState
    if Module.searchState and Module.searchState.catalog then Module.searchState.catalog.updateOnly = false end
    if tab == REPUTATION then
        Subscribe(Pages.ReportEvents(tab, Module.config), true)
        if Module.reputations then Module.reputations.updateOnly = false end
    end
    if tab == OVERVIEW or tab == EQUIPMENT or Module.custom then Gear.SyncPlayer(Module) end
    ReadHeaderExtras()
    Header()
    SyncSets()
    Paint()
end

local function LeaveCombat(_, event)
    Routing.UpdateBindings()
    local root = Routing.Shown()
    NativeVisibilityChanged(root)
    local hadReader, view = Module.reader, Module.view
    PrimeEquipmentReader()
    PrepareNativeLayout(Routing.Root())
    if Module.kind ~= PLAYER then return end
    if root and Module.layoutRoot == root and not Module.view.nativeLayout then
        local tab, nativeTab = Module.tab, Module.nativeTab
        Close(true)
        Open(PLAYER, "player", Identity("player") or "player", tab, root, nativeTab)
        return
    end
    if not hadReader and Module.reader or view.glassLook or view.glassApplied or view.roundedPending then
        view:RefreshAppearance(AvailableSkin(), Module.config)
    end
    RepaintAfterCombat()
    PaintContextAction(event)
end

local function EnterCombat(_, event)
    Routing.ReleaseGearClick()
    CancelInspect()
    if Module.kind == INSPECT then
        Close()
    elseif Module.kind == PLAYER then
        Module.view.tabSearch = nil
        if Module.view.reputationSearch then NS.ReputationSearch.Hide(Module.view) end
        if Module.tab == REPUTATION then
            SetEvents(Pages.ReportEvents(REPUTATION, Module.config), false)
            NS.ReputationList.Paint(Module, true)
        elseif Module.tab == CURRENCY then
            NS.Currency.Paint(Module, true)
        elseif Module.searchState and Module.searchState.groups and Module.searchState.query ~= ""
            and not Module.custom and Module.tab ~= ATTRIBUTES
            and Module.tab ~= OVERVIEW and Module.tab ~= EQUIPMENT then
            Module.view:ShowGroups(Module.searchState.groups)
        end
        Module.view:CancelWindowGestures()
        WindowAction("moveStop")
        WindowAction("scaleStop")
        HideTooltip()
        GearActions.CloseManager(Module)
        SetEvents(SET_EVENTS, false)
        SetEvents(GearActions.BagEvents, false)
        if Module.custom and Module.custom.sets and not Module.pageEvents.PLAYER_EQUIPMENT_CHANGED then
            SetEvents(ATTRIBUTE_EVENTS, false)
        end
        Module.dirtySets = nil
        PaintContextAction(event)
        if Module.tab == OVERVIEW or Module.tab == EQUIPMENT or Module.tab == ATTRIBUTES or Module.custom then Paint(event) end
    end
end
function Module:Refresh()
    if self.config.mode ~= Mode.SUITE then
        if self.running then self:Disable() end
        return
    end
    Routing.RefreshBindings(self.config, self.context)
    if self.running then
        if self.view and self.view.frame:IsShown() then self.appearanceJob:Request() end
        return
    end
    self.running = true
    self.paintJob = self.context:Coalesce(0, Flush)
    self.inspectJob = self.context:Coalesce(0, HandoffInspect)
    self.appearanceJob = self.context:Coalesce(0, RefreshVisibleAppearance)
    self.nativeJob = self.context:Coalesce(0, OpenNativeCharacter)
    self.nativeFitJob = self.context:Coalesce(0, FitNative)
    self.context:Event("CVAR_UPDATE", InspectInputMode, IN_COMBAT)
    self.context:Event("GAME_PAD_ACTIVE_CHANGED", InspectInputMode, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_ENABLED", LeaveCombat)
    self.context:Event("PLAYER_REGEN_DISABLED", EnterCombat, IN_COMBAT)
    if not inspectHooked then
        self.context:Event("ADDON_LOADED", AddOnLoaded)
        HookInspect()
    end
    PrimeEquipmentReader()
    Routing.Sync(NativeVisibilityChanged, NativeSizeChanged)
    PrepareNativeLayout(Routing.Root())
end

Module.Enable = Module.Refresh
function Module:Disable()
    Routing.RefreshBindings(nil, self.context)
    self.running = nil
    Routing.Sync(nil)
    Close()
    if self.nativeJob then self.nativeJob:Clear() self.nativeFitJob:Clear() end
    NS.Statistics.Drop()
    ReleaseNativeLayout()
    if self.characterView then self.characterView:RefreshAppearance(nil) end
    if self.dockView then self.dockView:RefreshAppearance(nil) end
    if self.inspectView then self.inspectView:RefreshAppearance(nil) end
    CancelInspect()
    self.context:Cancel(CancelInspect)
    if self.inspectJob then self.inspectJob:Clear() end
    self.context:RemoveEvent("CVAR_UPDATE")
    self.context:RemoveEvent("GAME_PAD_ACTIVE_CHANGED")
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    self.context:RemoveEvent("PLAYER_REGEN_DISABLED")
    self.context:RemoveEvent("ADDON_LOADED")
end

Suite.Install("characterPanel", Module)
