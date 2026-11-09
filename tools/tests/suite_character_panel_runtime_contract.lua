local root = assert(arg[1], "Suite root required")
local path = root .. "/MSUF_Suite_CharacterPanel/"
local function Load(file, ns)
    assert(loadfile(path .. file .. ".lua"))("MSUF_Suite_CharacterPanel", ns)
end

local secret = newproxy()
local hooks, units = {}, { player = "P", target = "A" }
local locked, pad, disabled = false, false, false
local requests, nativeToggles, nativeHides, gearReads = 0, 0, 0, 0
local snapshotReads, missingLinks = 0, false
local appearancePaints = 0
local openSounds = 0
local screenFits, cancelledGestures = 0, 0
local lastSlot, lastTab, lastKind, lastUnit, lastGroup, actions
local usedSlot, pickedSlot, modifiedClick, linkedItem
local nativeHardware, nativeSlots, nativeModel, nativePanes, gearProxy
local groupReads = 0
local setReads, setUses = 0, 0
local inspectAllowed, currentSet, setMenu, equippedSet
local itemWorn = true
local frames = {}
UIParent, UISpecialFrames = { GetEffectiveScale = function() return 2 end }, {}
C_GameRules = { IsGameRuleActive = function() return disabled end }
Enum = { GameRule = { CharacterPanelDisabled = 1 }, AddOnRestrictionState = { Inactive = 0, Activating = 1 } }
SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 839 }
function PlaySound(kit)
    assert(kit == SOUNDKIT.IG_CHARACTER_INFO_OPEN, "incorrect window opening sound")
    openSounds = openSounds + 1
end
C_CurrencyInfo = { GetCurrencyListSize = function() return 2 end }
C_EquipmentSet = {
    GetEquipmentSetIDs = function()
        setReads = setReads + 1
        return { 0, secret, 1 }
    end,
    GetEquipmentSetInfo = function(id)
        assert(id == 0 or id == 1, "invalid equipment set ID reached the API")
        return id == 0 and "Dungeons" or "PvP", nil, id, id == currentSet
    end,
}
function EquipmentManager_EquipSet(id)
    assert(not locked, "equipment sets bypassed the combat gate")
    equippedSet, currentSet, setUses = id, id, setUses + 1
end
function CanInspect() return inspectAllowed end
function GetInventoryItemDurability(slot)
    if slot == 2 then return itemWorn and 1000 or 1001, 1001 end
end
function wipe(values) for key in pairs(values) do values[key] = nil end end
function UnitGUID(unit) return units[unit] end
function UnitClass() return "Priest" end
function UnitLevel() return 22 end
function UnitName(unit) return unit end
function GetBindingKey() error("Suite must leave the stock Character key in place") end
function GetBindingAction() error("Suite must leave the stock Character key in place") end
function RegisterStateDriver(frame, state, condition)
    assert(frame == gearProxy and state == "visibility" and condition == "[combat] hide",
        "native click proxy lost the combat visibility driver")
end
function IsModifiedClick(kind) return kind == modifiedClick end
function HandleModifiedItemClick(link) linkedItem = link end
function ToggleCharacter(pane, onlyShow)
    local subframe = nativePanes[pane]
    if disabled or not subframe then return end
    nativeToggles = nativeToggles + 1
    local visible = CharacterFrame:IsShown()
    if visible and subframe:IsShown() then
        if not onlyShow then CharacterFrame:Hide() end
        return
    end
    CharacterFrame:ShowSubFrame(pane)
    if not visible then
        CharacterFrame:Show()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    end
    CharacterFrame.stockWidth = 338 -- Blizzard RefreshDisplay runs after toggling.
end
function PickupInventoryItem(slot)
    assert(nativeHardware and PaperDollFrame:IsVisible(), "Suite attempted to pick up a native inventory slot")
    pickedSlot = slot
end
function UseInventoryItem(slot)
    assert(nativeHardware and PaperDollFrame:IsVisible(), "Suite attempted to use a native inventory slot")
    usedSlot = slot
end
function HideUIPanel(frame)
    assert(frame ~= CharacterFrame, "Suite attempted to hide the native player window")
    nativeHides = nativeHides + 1
    frame.shown, frame.unit = false, nil
end
function hooksecurefunc(target, method, callback)
    if target == "ToggleCharacter" then
        local original = ToggleCharacter
        ToggleCharacter = function(...)
            original(...)
            method(...)
        end
    elseif target == CharacterFrame then
        local original = assert(target[method])
        target[method] = function(...)
            original(...)
            callback(...)
        end
    else
        hooks[target] = method
    end
end
local function CreateFrame(_, name, parent, template)
    local scripts = {}
    local frame = {
        scripts = scripts,
        GetName = function() return name end,
        SetScript = function(_, key, value) scripts[key] = value end,
        HookScript = function(_, key, value)
            local old = scripts[key]
            scripts[key] = function(...)
                if old then old(...) end
                value(...)
            end
        end,
        IsShown = function(self) return self.shown == true end,
        IsVisible = function(self) return self:IsShown() and (not parent or parent:IsVisible()) end,
        Show = function(self)
            if self.shown then return end
            self.shown = true
            if scripts.OnShow then scripts.OnShow(self) end
        end,
        Hide = function(self)
            if not self.shown then return end
            self.shown = false
            if scripts.OnHide and (not parent or parent:IsVisible()) then scripts.OnHide(self) end
        end,
    }
    if template == "SecureActionButtonTemplate" then
        assert(not locked and parent == UIParent, "click proxy was created under protected UI or in combat")
        gearProxy = frame
        local attributes = {}
        frame.SetAttribute = function(_, key, value) assert(not locked) attributes[key] = value end
        frame.GetAttribute = function(_, key) return attributes[key] end
        frame.ClearAllPoints = function() assert(not locked) end
        frame.SetPoint = function(self, ...) assert(not locked) self.point = { ... } end
        frame.SetSize = function(self, width, height) self.width, self.height = width, height end
        frame.SetFrameStrata = function() end
        frame.SetFrameLevel = function() end
        frame.RegisterForClicks = function(_, button) assert(button == "LeftButtonUp") end
    end
    frames[#frames + 1] = frame
    return frame
end
local callbacks, jobs, timers, tickers = {}, {}, {}, {}
local context = {}
local skinAcquires = 0
function context:Skin() skinAcquires = skinAcquires + 1 end
function context:Event(event, fn, _, unit)
    if event == "UNIT_AURA" then assert(unit == "target", "mount aura subscription was not unit-filtered") end
    callbacks[event] = fn
end
function context:RemoveEvent(event) callbacks[event] = nil end
function context:After(_, fn) timers[fn] = true end
function context:Ticker(interval, fn)
    assert(interval == 0.25 and not next(tickers), "mounted speed started a duplicate or hot ticker")
    tickers[fn] = true
end
function context:Cancel(fn) timers[fn], tickers[fn] = nil, nil end
local function Tick()
    local fn = assert(next(tickers), "mounted speed did not start a ticker")
    fn()
end
function context:Coalesce(_, fn)
    local job = {
        Request = function(self) self.pending = true end,
        Clear = function(self) self.pending = nil end,
    }
    jobs[fn] = job
    return job
end
local function Flush()
    for fn, job in pairs(jobs) do
        if job.pending then job.pending = nil fn() end
    end
end
local function Event(module, event, ...)
    if callbacks[event] then callbacks[event](module, event, ...) end
end
local function Press(key)
    local pane = key == "C" and "PaperDollFrame" or key == "U" and "ReputationFrame" or key
    ToggleCharacter(pane)
    Flush()
end

local function NativeSlot(slot, event)
    local frame = nativeSlots[slot]
    nativeHardware = true
    frame.scripts[event](frame)
    nativeHardware = nil
end
local function RequestInspect(unit)
    requests = requests + 1
    InspectFrame.unit, InspectFrame.shown = unit, false
    hooks.InspectFrame_Show(unit)
end
function InspectUnit(unit) InspectFrame_Show(unit) end
local function EmptyGear()
    local head = { slot = 1, label = "Head", link = "item:1", audit = { missingEnchant = true } }
    local chest = { slot = 2, label = "Chest", link = "item:2", audit = { emptySockets = 2 } }
    local rows = { head, chest }
    return { bySlot = rows, rows = rows, left = rows, right = {}, weapons = {}, pending = {} }
end

local function Run(forever)
    local runtime, controller
    local preferences, boundPreferences = {}, nil
    local lastContext, lastReport, lastGearSummary, lastHeader, lastTabs, lastRail
    local armor, armorReads, averageItemLevel = 42, 0, 19
    local statReads, critReads, lastCombatRail = 0, 0, nil
    local xp, xpReads = 25, 0
    function UnitXP(unit)
        assert(unit == "player", "custom XP used a foreign unit")
        xpReads = xpReads + 1
        return xp
    end
    function UnitXPMax(unit)
        assert(unit == "player", "custom XP limit used a foreign unit")
        return 100
    end
    LE_UNIT_STAT_STRENGTH, LE_UNIT_STAT_AGILITY, LE_UNIT_STAT_STAMINA, LE_UNIT_STAT_INTELLECT, LE_UNIT_STAT_SPIRIT = 1, 2, 3, 4, 5
    SPELL_STAT1_NAME, SPELL_STAT2_NAME, SPELL_STAT3_NAME, SPELL_STAT4_NAME, SPELL_STAT5_NAME =
        "Strength", "Agility", "Stamina", "Intellect", "Spirit"
    HEALTH, MANA, DEFENSE = "Health", "Mana", "Defense"
    STAT_CRITICAL_STRIKE, STAT_HASTE, STAT_MASTERY, STAT_VERSATILITY = "Crit", "Haste", "Mastery", "Versatility"
    STAT_ARMOR, STAT_DODGE, STAT_AVOIDANCE = "Armor", "Dodge", "Avoidance"
    C_SpecializationInfo = { GetSpecialization = function() return nil end }
    function UnitHealthMax() return 595 end
    function UnitPowerType() return 0, "MANA" end
    function UnitPowerMax() return 1264 end
    function UnitStat(_, id) statReads = statReads + 1 return id, id * 10 end
    function UnitArmor() armorReads = armorReads + 1 return 0, armor end
    function GetDodgeChance() return 2 end
    function GetAvoidance() return 3 end
    function UnitDefenseSkill() return 100, 5 end
    local zoneReads, guildReads = 0, 0
    local auraReads, speedReads, railPaints = 0, 0, 0
    local currentAura, currentSpeed, restricted
    local mountedAura = { auraInstanceID = 5, spellId = 111, isHelpful = true }
    local function TargetOnly(unit)
        assert(unit == "target", "Inspect travel read a different unit")
    end
    function GetUnitSpeed(unit)
        TargetOnly(unit)
        speedReads = speedReads + 1
        return currentSpeed, 77, 88, 99
    end
    function canaccesstable(value) return type(value) == "table" end
    C_Secrets = {
        ShouldAurasBeSecret = function() return restricted == true end,
        ShouldUnitAuraSlotBeSecret = function() return false end,
    }
    C_UnitAuras = {
        GetAuraSlots = function(unit, filter)
            TargetOnly(unit)
            assert(filter == "HELPFUL")
            auraReads = auraReads + 1
            if currentAura then return nil, 1 end
        end,
        GetAuraDataBySlot = function(unit)
            TargetOnly(unit)
            return currentAura
        end,
    }
    C_MountJournal = {
        GetMountFromSpell = function(id)
            assert(type(id) == "number")
            if id == 111 then return 1 end
        end,
        GetMountInfoByID = function() return "Mount" end,
    }
    function GetGuildInfo() guildReads = guildReads + 1 return secret end
    function GetMinimapZoneText() zoneReads = zoneReads + 1 return "Stormwind" end
    currentSet, inspectAllowed, itemWorn = 0, true, true
    controller = {
        CreateFrame = CreateFrame, GamepadUI = function() return pad end,
        ReadCrit = function() critReads = critReads + 1 return 1 end, ReadHaste = function() return 2 end,
        ReadMastery = function() return 3 end, ReadVersatility = function() return 4 end,
        Dispatch = function(callback, ...) return callback(...) end,
        Finish = function(callback, ...) return true, callback(...) end,
        ContextMenu = function(owner, generator, ...)
            setMenu = {}
            generator(owner, {
                CreateRadio = function(_, text, selected, pick, data)
                    setMenu[#setMenu + 1] = { text = text, selected = selected, pick = pick, data = data }
                end,
            }, ...)
        end,
        ModuleState = function(id)
            assert(id == "characterPanel")
            return preferences
        end,
        Install = function(id, module)
            assert(id == "characterPanel")
            runtime = module
        end,
    }
    local readerAvailable, readerChecks = false, 0
    local geometryApplied, geometryReleased = 0, 0
    local lastWindowAction, lastWithModel, presented
    local layout = { width = 940, height = 552 }
    local reader = {
        SpecializationName = function(kind) lastKind = kind end,
        AverageItemLevel = function() return averageItemLevel end,
        ClearPending = function(_, pending) wipe(pending) end,
    }
    MSUFSuite = {
        Suite = controller, Text = function(text) return text end, Client = { isForever = forever },
        InCombat = function(event) return locked or event == "PLAYER_REGEN_DISABLED" end, Public = function(value) return not rawequal(value, secret) end,
        Finite = function(value)
            return MSUFSuite.Public(value) and type(value) == "number" and value == value
                and value ~= math.huge and value ~= -math.huge
        end,
        PublicText = function(value) return type(value) == "string" and value or nil end,
        Skin = {
            Acquire = function(id) assert(id == "characterPanelInspect" or id == "characterPanelDock") end,
            CharacterGeometry = {
                Present = function(root, frame)
                    assert(root == CharacterFrame and (not frame or frame:IsVisible()), "focus footprint used an invalid host")
                    presented = frame
                end,
                WindowAction = function(root, action)
                    assert(root == CharacterFrame)
                    if locked and action ~= "release" and action ~= "moveStop" and action ~= "scaleStop" then
                        error("native window gesture started in combat")
                    end
                    lastWindowAction = action
                    return action == "maximize"
                end,
                Apply = function(root, plan)
                    assert(not locked and root == CharacterFrame and plan == layout, "native layout was written in combat or on the wrong root")
                    geometryApplied = geometryApplied + 1
                    return true
                end,
                Release = function(root)
                    assert(not locked and root == CharacterFrame, "native geometry was not released on its owner")
                    geometryReleased = geometryReleased + 1
                end,
            },
            GetEquipmentReader = function()
                assert(not locked, "character panel tried loading a cold provider in combat")
                readerChecks = readerChecks + 1
                return readerAvailable and reader or nil
            end,
        },
        CharacterPanelMode = { BASIC = 1, SUITE = 2 },
    }
    local build = setmetatable({}, { __index = function() return function() return {} end end })
    MSUFSuite.CatalogBuild = { ForAddon = function() return build end }
    assert(loadfile(root .. "/MSUF_Suite/Core/CharacterTabs.lua"))("MSUF_Suite", MSUFSuite)
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/CharacterPanel.lua"))("MSUF_Suite", MSUFSuite)
    controller.CharacterHeader = MSUFSuite.CharacterHeader
    assert(loadfile(root .. "/MSUF_Suite/Core/UnitMount.lua"))("MSUF_Suite", MSUFSuite)
    gearProxy = nil
    CharacterMicroButton = {
        IsForbidden = function() return false end, IsEnabled = function() return true end,
        Click = function() ToggleCharacter("PaperDollFrame") end,
    }
    CharacterFrame = CreateFrame("Frame")
    CharacterFrame.SetPoint, CharacterFrame.SetScale, CharacterFrame.StopMovingOrSizing =
        function() end, function() end, function() end
    PaperDollFrame = CreateFrame("Frame", nil, CharacterFrame)
    nativePanes = { PaperDollFrame = PaperDollFrame }
    for _, name in ipairs({ "ReputationFrame", "TokenFrame", "SkillsFrame", "PVPRankFrame", "StatisticsFrame", "UnmappedFrame" }) do
        _G[name] = CreateFrame("Frame", name, CharacterFrame)
        nativePanes[name] = _G[name]
    end
    function CharacterFrame:ShowSubFrame(name)
        if forever then self.activeSubframe = name end
        for id, subframe in pairs(nativePanes) do
            if id ~= name then subframe:Hide() end
        end
        nativePanes[name]:Show()
        if not forever then self.activeSubframe = name end
    end
    nativeModel = CreateFrame("ModelScene", nil, PaperDollFrame)
    nativeModel:Show()
    nativeSlots = { [13] = CreateFrame("ItemButton", nil, PaperDollFrame),
        [16] = CreateFrame("ItemButton", nil, PaperDollFrame) }
    nativeSlots[13]:SetScript("OnClick", function() UseInventoryItem(13) end)
    nativeSlots[16]:SetScript("OnDragStart", function() PickupInventoryItem(16) end)
    nativeSlots[16]:SetScript("OnReceiveDrag", function() PickupInventoryItem(16) end)
    InspectFrame = CreateFrame("Frame")
    InspectFrame_Show = RequestInspect
    local inspectGuildReads = 0
    C_PaperDollInfo = {
        GetInspectGuildInfo = function(unit)
            assert(InspectFrame.unit == unit, "guild was read after native Inspect cleared its cache")
            inspectGuildReads = inspectGuildReads + 1
            return nil, nil, "Inspect guild"
        end,
    }
    local gearFixture = {
        New = EmptyGear,
        Read = function(_, gear, unit, _, _, slot)
            gearReads, lastSlot = gearReads + 1, slot
            gear.missingLinks = unit == "target" and missingLinks
            if unit == "target" then gear.pending[123] = true end
            gear.rows[1].name, gear.rows[2].name = "Helm", "Robe"
            gear.rows[1].level = unit == "target" and 24 or 18
            gear.rows[2].level = unit == "player" and 20 or nil
            gear.missingEnchants, gear.emptySockets = 1, 2
        end,
        UpdateSnapshot = function(_, gear, ids)
            assert(InspectFrame.unit == nil and ids[123], "snapshot read requires cached links")
            snapshotReads = snapshotReads + 1
            gear.pending[123] = nil
        end,
    }
    local ns = {
        View = {
            NativeLayout = function(gear)
                assert(gear.rows[1].slot == 1)
                return layout
            end,
            New = function(buttons, parent, nativeRoot, nativeLayout)
                assert(parent == nil and (not nativeRoot or nativeRoot == CharacterFrame))
                assert(not nativeLayout or not locked, "the native child was built for the first time in combat")
                return {
                    nativeRoot = nativeRoot, nativeLayout = nativeLayout,
                    frame = CreateFrame("Frame", not nativeRoot and buttons.frameName or nil, nativeLayout and nativeRoot or nil),
                    SetTabs = function(_, tabs, tab)
                        actions = buttons
                        lastTab, lastTabs = tab, tabs
                        local visible = {}
                        for i = 1, #tabs do visible[tabs[i].id] = true end
                        assert(not visible.stats, "standalone character Stats tab remained")
                        if visible.compare then
                            assert(not visible.reputation and not visible.custom2, "own tabs leaked into Inspect")
                        else
                            assert(visible.reputation and visible.currency)
                            assert(visible.skills and visible.pvp and visible.statistics)
                        end
                    end,
                    SetHeader = function(_, _, _, _, unit, _, data) lastUnit, lastHeader = unit, data end,
                    SetContextAction = function(_, label) lastContext = label end,
                    ShowGear = function(_, _, _, _, groups, _, details, withModel, combat)
                        lastWithModel, lastCombatRail = withModel, combat
                        lastRail = #details > 0 and details or groups
                        lastGearSummary = lastRail[#lastRail] and lastRail[#lastRail].rows
                    end,
                    RefreshInspectSummary = function(_, groups)
                        railPaints = railPaints + 1
                        assert(lastGearSummary == groups[1].rows, "speed repaint used a different rail")
                    end,
                    ShowGroups = function(_, groups)
                        lastReport = groups
                        if nativeRoot and (lastTab == "overview" or lastTab == "gear") then
                            lastRail = groups
                            lastGearSummary = lastRail[#lastRail] and lastRail[#lastRail].rows
                        end
                    end,
                    ApplyWindowPreferences = function(_, state)
                        if not nativeRoot then boundPreferences = state end
                    end,
                    FitScreen = function() screenFits = screenFits + 1 end,
                    RefreshModel = function() assert(not nativeRoot, "hosted view allocated a duplicate model") end,
                    IsMinimized = function(self) return self.minimized end,
                    SetMinimized = function(self, minimized, tab, silent)
                        if self.minimized == minimized then return end
                        self.minimized = minimized
                        if not silent then buttons.minimized(minimized, tab) end
                    end,
                    CancelWindowGestures = function() cancelledGestures = cancelledGestures + 1 end,
                    RefreshAppearance = function() appearancePaints = appearancePaints + 1 end,
                }
            end,
        },
    }
    Load("Bootstrap", ns)
    Load("Equipment", ns)
    for key, fn in pairs(gearFixture) do ns.Gear[key] = fn end
    Load("GearActions", ns)
    Load("Pages", ns)
    ns.Pages.Read = function(tab) lastGroup, groupReads = tab, groupReads + 1 end
    ns.Pages.Toggle = function() return true end
    do
        local definition = { cards = { { title = "Combat stats", rows = {
            { source = "crit", label = "" }, { source = "health", label = "" },
        } } } }
        local groups, plan = {}, ns.Pages.CustomPlan(definition)
        local before = critReads
        ns.Pages.Custom(groups, plan, {}, false)
        assert(groups[1].rows[1].value == "1.00%" and critReads == before + 1)
        ns.Pages.Custom(groups, plan, {}, true)
        assert(groups[1].rows[1].value == "—" and groups[1].rows[2].value == 595 and critReads == before + 1,
            "custom tab carried a stale combat value or queried its provider")
        ns.Pages.Custom(groups, plan, {}, false)
        assert(groups[1].rows[1].value == "1.00%" and critReads == before + 2)
        critReads = before
    end
    Load("Routing", ns)
    Load("Travel", ns)
    Load("Runtime", ns)
    runtime.context, runtime.config, runtime.active = context, { mode = 1 }, true
    runtime:Enable()
    assert(not callbacks.INSPECT_READY and not runtime.view and readerChecks == 0, "Basic acquired ownership")
    Press("C")
    assert(CharacterFrame:IsVisible() and not runtime.view, "Basic changed native Character ownership")
    Press("C")
    Press("U")
    assert(CharacterFrame:IsVisible() and ReputationFrame:IsVisible() and not runtime.view,
        "Basic replaced a directly opened native report")
    Press("U")
    runtime.config.mode = 2
    runtime:Refresh()
    assert(not runtime.view and runtime.characterView and not runtime.characterView.frame:IsShown()
        and not callbacks.UPDATE_BINDINGS and geometryApplied == 1,
        "Suite failed to prepare the wide layout without opening or overriding C")
    local coldReaderChecks, coldReads, beforeCombatSkin = readerChecks, gearReads, skinAcquires
    locked = true
    local playerGUID = units.player
    units.player = secret
    Press("C")
    local hostedView = assert(runtime.characterView, "first combat open missed its host")
    assert(hostedView == runtime.view and hostedView.nativeRoot == CharacterFrame and hostedView.frame:IsShown()
        and hostedView.nativeLayout == layout and presented == hostedView.frame and CharacterFrame.stockWidth == 338 and geometryApplied == 1
        and nativeModel:IsVisible() and readerChecks == coldReaderChecks and gearReads == coldReads,
        "first combat open missed its host or attempted to load optional metadata")
    assert(skinAcquires == beforeCombatSkin + 1, "prepared wide panel lost its skin when first opened in combat")
    assert(lastCombatRail and #lastRail[1].rows == 2 and lastRail[1].rows[1].value == 595
        and lastRail[1].rows[2].value == 1264 and statReads == 0 and critReads == 0 and armorReads == 0,
        "first combat open used the native scroller or queried restricted stats")
    assert(lastRail[2].title == "Full stats after combat" and #lastRail[2].rows == 0,
        "combat stats did not show a compact notice below the vitals")
    if not forever then
        local audit = lastRail[#lastRail].rows
        assert(audit[#audit - 1].value == "—" and audit[#audit].value == "—", "cold gear audit displayed false zeroes")
    end
    units.player = playerGUID
    locked, readerAvailable = false, true
    Event(runtime, "PLAYER_REGEN_ENABLED")
    Flush()
    assert(runtime.reader == reader and gearReads == coldReads + 1 and hostedView.frame:IsShown(),
        "combat exit did not fill metadata in the same view")
    Press("C")
    assert(not hostedView.frame:IsShown() and not runtime.kind and not presented, "native close retained Suite events")
    armorReads = 0
    local beforeSounds, beforeOpenReads = openSounds, gearReads
    Press("C")
    assert(runtime.view == hostedView and runtime.view.frame:IsShown() and lastTab == "overview"
        and lastKind == "character" and lastWithModel)
    assert(actions.windowAction("maximize") and lastWindowAction == "maximize", "Suite caption lost its native window owner")
    assert(gearReads == beforeOpenReads + 1 and boundPreferences == nil, "native show painted twice or moved its hosted view")
    local function FindRow(label)
        for _, group in ipairs(lastRail) do
            for _, row in ipairs(group.rows) do
                if row.label == label then return row.value end
            end
        end
    end
    local statEvent = forever and "SKILL_LINES_CHANGED" or "AVOIDANCE_UPDATE"
    assert(lastRail[1].title == "Attributes" and lastRail[2].title == "Enhancements" and lastRail[3].title == "Defense",
        "default Overview did not move all three Stats groups to the rail")
    assert(FindRow("Health") == 595 and FindRow("Mana") == 1264 and FindRow("Armor") == 42 and FindRow("Durability"),
        "full stats displaced vitals or the equipment audit")
    assert((FindRow("Spirit") == 50) == forever and (FindRow("Avoidance") == "3.00%") ~= forever,
        "full stats used the wrong client capabilities")
    assert(callbacks[statEvent] and armorReads == 1, "default stats were not read once with their events")
    armor = 55
    Event(runtime, statEvent)
    Event(runtime, statEvent)
    Flush()
    assert(FindRow("Armor") == 55 and armorReads == 2, "full-stat events did not coalesce and refresh the rail")
    NativeSlot(13, "OnClick")
    assert(usedSlot == 13 and not runtime.slot, "original right-click did not reach equipped trinket")
    usedSlot = nil
    actions.tab("gear")
    actions.group(1)
    assert(runtime.slot == 1 and lastRail[1].title == "Helm" and not lastWithModel,
        "wide gear lost its read-only details or distinct renderer")
    assert(not callbacks[statEvent] and not callbacks.UNIT_STATS, "hidden stats kept event subscriptions")
    Event(runtime, statEvent)
    Flush()
    assert(armorReads == 2, "hidden Overview stats were read behind an equipment detail")
    actions.tab("overview")
    assert(callbacks[statEvent] and armorReads == 3 and FindRow("Armor") == 55,
        "returning from equipment details did not refresh stats")
    local beforeStatsToggle = gearReads
    runtime.config.showFullStats = false
    runtime:Refresh()
    Flush()
    assert(not callbacks[statEvent] and lastRail[1].title == "At a glance" and not FindRow("Armor") and FindRow("Durability"),
        "turning full stats off did not restore the compact rail")
    assert(armorReads == 3 and gearReads == beforeStatsToggle, "option toggle reread full stats or equipment")
    runtime.config.showFullStats = true
    runtime:Refresh()
    Flush()
    assert(callbacks[statEvent] and armorReads == 4 and FindRow("Armor") == 55 and gearReads == beforeStatsToggle,
        "turning full stats on did not restore the full rail in place")
    assert(openSounds == beforeSounds + 1, "new player window missed the native open sound")
    assert(zoneReads == 0 and guildReads == 0 and not callbacks.ZONE_CHANGED, "hidden header info performed work")
    runtime.config.headerGuildVisible, runtime.config.headerZoneVisible = true, true
    runtime.config.tabOrder = "pvp,gear,stats"
    runtime:Refresh()
    Flush()
    assert(lastTabs[1].id == "pvp" and lastTabs[2].id == "gear" and lastTabs[3].id == "overview"
        and lastHeader.zone == "Stormwind" and lastHeader.guild == nil,
        "live header settings, order or secret fallback not applied")
    Event(runtime, "ZONE_CHANGED")
    assert(zoneReads == 2 and guildReads == 1 and callbacks.PLAYER_GUILD_UPDATE)
    runtime.config.headerNameSize = 25
    runtime:Refresh()
    Flush()
    assert(zoneReads == 2 and guildReads == 1, "styling changes reread optional character data")
    runtime.config.headerGuildVisible, runtime.config.headerZoneVisible = false, false
    runtime:Refresh()
    Flush()
    assert(not callbacks.ZONE_CHANGED and not callbacks.PLAYER_GUILD_UPDATE and not lastHeader.zone)
    local auditRows = {}
    for _, row in ipairs(lastGearSummary) do auditRows[row.label] = row end
    assert(auditRows.Durability.action == "durability", "a slightly worn slot rounded to 100% and lost its action")
    actions.group(auditRows.Durability.action)
    assert(not runtime.gear.rows[1].marked and runtime.gear.rows[2].marked, "worn slot did not highlight")
    itemWorn = false
    Event(runtime, "UPDATE_INVENTORY_DURABILITY")
    Flush()
    assert(not runtime.gear.rows[2].marked and not runtime.gear.auditFocus, "repaired slot stayed highlighted")
    if forever then
        assert(not auditRows["Missing enchants"] and not auditRows["Empty sockets"], "Retail audit leaked into Forever")
    else
        actions.group(auditRows["Missing enchants"].action)
        assert(runtime.gear.rows[1].marked and not runtime.gear.rows[2].marked, "missing enchant marked the wrong slot")
        actions.group(auditRows["Empty sockets"].action)
        assert(not runtime.gear.rows[1].marked and runtime.gear.rows[2].marked, "empty socket marked the wrong slot")
        actions.group("sockets")
        assert(not runtime.gear.auditFocus and not runtime.gear.rows[2].marked, "second click did not clear the marks")
    end
    local baselineReads = gearReads
    local beforeAppearance = appearancePaints
    preferences = {}
    runtime:Refresh()
    runtime:Refresh()
    Flush()
    assert(appearancePaints == beforeAppearance + 1 and gearReads == baselineReads,
        "appearance change did not refresh the open view without rereading gear")
    assert(boundPreferences == nil, "profile refresh moved the native host from Suite")
    Event(runtime, "PLAYER_EQUIPMENT_CHANGED", secret)
    Event(runtime, "UNIT_STATS", "player")
    Flush()
    assert(gearReads == baselineReads, "stat event reread equipment")
    Event(runtime, "PLAYER_EQUIPMENT_CHANGED", 1)
    Event(runtime, "PLAYER_EQUIPMENT_CHANGED", 1)
    Flush()
    assert(gearReads == baselineReads + 1 and lastSlot == 1, "equipment event lost slot coalescing")

    do
        local model = MSUFSuite.CharacterTabs
        local progress = {
            id = "custom1", name = "Field notes", x = -11, y = 6,
            cards = { { title = "Current level", x = 21, y = -15, rows = {
                { source = "xp", label = "Training", x = 19, y = 7 }, { source = "xp" },
                { source = forever and "mastery" or "spirit" },
                { source = "level" },
            } } },
        }
        local audit = {
            id = "custom2", name = "Equipment notes",
            cards = { { title = "Readiness", rows = {
                { source = "itemLevel" }, { source = "durability" }, { source = "missingEnchants" },
            } } },
        }
        local function InstallCustom(...)
            runtime.config.customTabs = assert(model.Encode({ ... }))
            runtime:Refresh()
            Flush()
        end
        InstallCustom(progress, audit)
        assert(lastTabs[#lastTabs - 1].id == "custom1" and lastTabs[#lastTabs].id == "custom2",
            "new custom tabs did not join the open character panel")
        assert(lastTabs[#lastTabs - 1].x == -11 and lastTabs[#lastTabs - 1].y == 6,
            "saved custom tab placement did not reach the live tab bar")
        assert(xpReads == 0 and not callbacks.PLAYER_XP_UPDATE, "inactive custom tab sampled or subscribed to XP")
        local gearBeforeCustom = gearReads
        actions.tab("custom1")
        local rows = lastReport[1].rows
        assert(lastReport[1].title == "Current level" and rows[1].label == "Training" and rows[1].value == "25 / 100"
            and rows[2].label == "Experience" and rows[2].value == rows[1].value and rows[4].value == 22,
            "custom tab did not use shared report rows, the source label, and the value")
        local cardPosition, rowPosition = lastReport[1].layout, rows[1].layout
        assert(cardPosition.x == 21 and cardPosition.y == -15 and cardPosition.rowUp == 7
            and rowPosition.x == 19 and rowPosition.y == 7 and rows[2].layout.x == 0 and rows[2].layout.y == 0,
            "saved card and row placement did not reach pooled report data")
        assert(rows[3].value == "—" and not callbacks[forever and "MASTERY_UPDATE" or "UNIT_STATS"],
            "an unsupported imported source became an active reader")
        assert(xpReads == 1 and gearReads == gearBeforeCustom and callbacks.PLAYER_XP_UPDATE,
            "duplicate custom rows sampled more than once or touched equipment")
        assert(not callbacks.ITEM_DATA_LOAD_RESULT and not callbacks.PLAYER_EQUIPMENT_CHANGED
            and not callbacks.UNIT_MODEL_CHANGED and not callbacks.UPDATE_INVENTORY_DURABILITY,
            "custom XP tab retained inactive equipment listeners")
        Event(runtime, "PLAYER_XP_UPDATE", "target")
        Event(runtime, "PLAYER_XP_UPDATE", secret)
        Flush()
        assert(xpReads == 1, "an unrelated or restricted XP event repainted the tab")
        xp = 75
        Event(runtime, "PLAYER_XP_UPDATE", "player")
        Event(runtime, "PLAYER_XP_UPDATE", "player")
        Flush()
        assert(xpReads == 2 and lastReport[1].rows == rows and rows[1].value == "75 / 100",
            "active events did not coalesce into one pooled repaint")
        xp = secret
        Event(runtime, "PLAYER_XP_UPDATE", "player")
        Flush()
        assert(xpReads == 3 and rows[1].value == "—", "restricted XP did not render as unknown")

        progress.name = "New field notes"
        progress.cards[1].rows[1].label, progress.cards[1].rows[1].y = "New training", -9
        InstallCustom(progress, audit)
        assert(lastTab == "custom1" and lastTabs[#lastTabs - 1].label == progress.name
            and lastReport[1].rows[1].label == "New training" and lastReport[1].rows[1].layout.y == -9 and xpReads == 4,
            "active tab did not update on an in-place rename/content edit")
        xp = 80
        Event(runtime, "PLAYER_XP_UPDATE", "player")
        Flush()
        assert(lastTab == "custom1" and callbacks.PLAYER_XP_UPDATE and xpReads == 5
            and lastReport[1].rows[1].value == "80 / 100" and gearReads == gearBeforeCustom,
            "live hosted source reread hidden equipment or missed the selected data")
        averageItemLevel = 20
        Event(runtime, "PLAYER_AVG_ITEM_LEVEL_UPDATE")
        actions.tab("custom2")
        Flush()
        assert(not callbacks.PLAYER_XP_UPDATE and callbacks.UPDATE_INVENTORY_DURABILITY
            and (callbacks.ITEM_DATA_LOAD_RESULT ~= nil) == not forever,
            "source subscription did not switch to supported equipment data")
        assert(gearReads == gearBeforeCustom + (forever and 0 or 1) and lastReport[1].rows[1].value == "20"
            and lastReport[1].rows[2].value == "100%" and lastReport[1].rows[3].value == (forever and "—" or 1),
            "custom gear sources did not reuse a fresh audit and durability cache")
        InstallCustom(progress)
        assert(lastTab == "overview" and not callbacks.PLAYER_XP_UPDATE and lastRail[1].title == "Attributes",
            "deleting the live selected custom tab did not return to Overview")
        assert(not lastRail[1].layout and not lastRail[1].rows[1].layout,
            "stock report inherited positioned data from the custom pool")
        InstallCustom(audit)
    end

    actions.tab("gear")
    assert(lastContext == "Equipment set: Dungeons" and callbacks.EQUIPMENT_SETS_CHANGED)
    actions.contextAction({})
    assert(#setMenu == 2 and setMenu[1].selected(setMenu[1].data), "menu did not reflect the native active set")
    local beforeUses = setUses
    locked = true
    setMenu[2].pick(setMenu[2].data)
    assert(setUses == beforeUses, "a menu opened before combat equipped a set during combat")
    locked = false
    setMenu[2].pick(setMenu[2].data)
    assert(setUses == beforeUses + 1 and equippedSet == 1, "selector did not invoke Blizzard's set action")
    Event(runtime, "EQUIPMENT_SWAP_FINISHED")
    Flush()
    assert(lastContext == "Equipment set: PvP", "finished swap did not refresh the active set")
    actions.tab("reputation")
    assert(lastGroup == "reputation" and callbacks.UPDATE_FACTION and not callbacks.UNIT_STATS)
    local beforeSets = setReads
    Event(runtime, "EQUIPMENT_SETS_CHANGED")
    Flush()
    assert(setReads == beforeSets and not callbacks.EQUIPMENT_SETS_CHANGED, "inactive tab listened to set updates")
    local beforeGroups = groupReads
    actions.group(1)
    Flush()
    assert(groupReads == beforeGroups + 1, "group action waited for an unrelated native event")
    local beforeFits = screenFits
    CharacterFrame.scripts.OnSizeChanged()
    CharacterFrame:SetPoint("CENTER")
    CharacterFrame:SetScale(1)
    CharacterFrame:StopMovingOrSizing()
    Flush()
    assert(screenFits == beforeFits, "the inherited wide host rescheduled a detached layout on native movement")
    local beforeClose = gearReads
    Event(runtime, "PLAYER_EQUIPMENT_CHANGED", 1)
    Press("C")
    assert(not runtime.view.frame:IsShown() and not callbacks.UPDATE_FACTION and not callbacks.PLAYER_EQUIPMENT_CHANGED
        and gearReads == beforeClose, "native close retained Suite events or a queued equipment repaint")
    assert(openSounds == beforeSounds + 1, "changing tabs or closing replayed the opening sound")
    beforeAppearance = appearancePaints
    runtime:Refresh()
    Flush()
    assert(appearancePaints == beforeAppearance, "appearance update painted the closed window")
    local beforeRequests = requests
    missingLinks = true
    RequestInspect("target")
    InspectFrame:Show()
    Event(runtime, "INSPECT_READY", "A")
    Flush()
    assert(InspectFrame:IsShown() and not runtime.view.frame:IsShown(), "replaced Inspect before links were readable")
    missingLinks = false
    RequestInspect("target")
    InspectFrame:Show()
    Event(runtime, "INSPECT_READY", "B")
    Flush()
    assert(InspectFrame:IsShown() and not runtime.view.frame:IsShown(), "accepted mismatched Inspect data")
    Event(runtime, "INSPECT_READY", "A")
    Flush()
    assert(requests == beforeRequests + 2 and not callbacks.INSPECT_READY, "issued or retained an Inspect request")
    assert(not InspectFrame:IsShown() and runtime.view.frame:IsShown() and lastKind == "inspect" and lastUnit == "target")
    assert(lastTabs[1].id == "overview" and boundPreferences == preferences,
        "Inspect lost its independent tab order or free position")
    assert(callbacks.UNIT_AURA and callbacks.ADDON_RESTRICTION_STATE_CHANGED and not next(tickers)
        and auraReads == 1 and speedReads == 0 and not lastGearSummary[3], "unmounted Inspect polled speed")
    local readsBeforeSpeed = gearReads
    Event(runtime, "UNIT_AURA", "target", { addedAuras = {
        { spellId = secret, isHelpful = true }, { spellId = 111, isHelpful = false },
        { spellId = 112, isHelpful = true },
    }, updatedAuraInstanceIDs = { 77 } })
    assert(auraReads == 1 and speedReads == 0 and railPaints == 0, "unrelated auras refreshed travel")
    currentAura, currentSpeed = mountedAura, 14
    Event(runtime, "UNIT_AURA", "focus", { addedAuras = { mountedAura } })
    assert(not next(tickers), "a different unit started the ticker")
    Event(runtime, "UNIT_AURA", "target", { addedAuras = { mountedAura } })
    assert(lastGearSummary[3].label == "Speed" and lastGearSummary[3].value == "200%"
        and auraReads == 1 and speedReads == 1 and railPaints == 1, "mount addition did not show native current speed")
    Tick()
    assert(speedReads == 2 and railPaints == 1 and auraReads == 1, "unchanged speed repainted or scanned auras")
    currentSpeed = 16.1
    Tick()
    assert(lastGearSummary[3].value == "230%" and railPaints == 2 and gearReads == readsBeforeSpeed,
        "speed change did not stay within the summary rail")
    currentSpeed = secret
    Tick()
    assert(not lastGearSummary[3] and railPaints == 3, "secret speed leaked or kept a stale value")
    currentSpeed = 0
    Tick()
    assert(lastGearSummary[3].value == "0%" and railPaints == 4, "mounted standing speed was not shown")
    Event(runtime, "UNIT_AURA", "target", { removedAuraInstanceIDs = { 77 } })
    assert(auraReads == 1 and railPaints == 4, "unrelated aura removal rescanned travel")
    currentAura = nil
    Event(runtime, "UNIT_AURA", "target", { removedAuraInstanceIDs = { 5 } })
    assert(not lastGearSummary[3] and not next(tickers) and railPaints == 5 and auraReads == 2,
        "dismount left speed or a ticker active")
    currentAura, currentSpeed = mountedAura, 7
    Event(runtime, "UNIT_AURA", "target", { isFullUpdate = true })
    assert(lastGearSummary[3].value == "100%" and next(tickers), "full aura update did not recover mounting")
    Event(runtime, "ADDON_RESTRICTION_STATE_CHANGED", 0, Enum.AddOnRestrictionState.Activating)
    assert(not lastGearSummary[3] and not next(tickers), "activating restrictions retained speed")
    Event(runtime, "UNIT_AURA", "target", { addedAuras = { mountedAura } })
    assert(not next(tickers), "aura restored speed before restrictions took effect")
    restricted = true
    Flush()
    assert(not lastGearSummary[3] and not next(tickers), "restricted mount retained speed")
    restricted = false
    Event(runtime, "ADDON_RESTRICTION_STATE_CHANGED", 0, Enum.AddOnRestrictionState.Inactive)
    assert(lastGearSummary[3].value == "100%" and next(tickers), "public mount did not resume speed")
    actions.slot(1)
    assert(not callbacks.UNIT_AURA and not next(tickers), "item details retained travel work")
    actions.slot(1)
    assert(lastGearSummary[3].value == "100%" and next(tickers), "closing details did not resume travel")
    runtime.config.inspectTabOrder = "compare,gear,overview"
    runtime:Refresh()
    Flush()
    assert(lastTabs[1].id == "compare" and lastTabs[3].id == "overview", "Inspect tab order was not applied live")
    assert(not lastHeader.guild and inspectGuildReads == 1, "Inspect guild snapshot was not captured once")
    runtime.config.headerGuildVisible = true
    runtime:Refresh()
    Flush()
    assert(lastHeader.guild == "Inspect guild" and inspectGuildReads == 1, "Inspect preview settings reread native guild")
    runtime.config.headerGuildVisible = false
    assert(lastContext == "Blizzard Inspect")
    actions.tab("compare")
    assert(not callbacks.UNIT_AURA and not callbacks.ADDON_RESTRICTION_STATE_CHANGED and not next(tickers),
        "comparison retained travel work")
    assert(#lastReport == 1 and lastReport[1].rows[1].value == "18 → 24 · +6"
        and lastReport[1].rows[2].value == "20 → —", "comparison lost aligned slots or treated unknown as zero")
    assert(openSounds == beforeSounds + 1, "Inspect handoff replayed the native opening sound")
    actions.slot(1, nil, "RightButton")
    assert(not usedSlot, "right clicking an inspected item used the player's slot")
    local beforeSnapshot = snapshotReads
    Event(runtime, "ITEM_DATA_LOAD_RESULT", 456, true)
    Event(runtime, "ITEM_DATA_LOAD_RESULT", 123, true)
    Event(runtime, "GET_ITEM_INFO_RECEIVED", 123, true)
    runtime.view:SetMinimized(true)
    Flush()
    assert(snapshotReads == beforeSnapshot and callbacks.PLAYER_TARGET_CHANGED and not callbacks.ITEM_DATA_LOAD_RESULT,
        "minimized Inspect kept painting or lost identity tracking")
    runtime.view:SetMinimized(false)
    assert(snapshotReads == beforeSnapshot + 1 and not callbacks.ITEM_DATA_LOAD_RESULT,
        "Inspect restore did not resolve cached snapshot data")
    actions.tab("overview")
    assert(lastGearSummary[3].value == "100%" and next(tickers), "returning to Overview did not resume mounted speed")
    runtime.view:SetMinimized(true)
    assert(not callbacks.UNIT_AURA and not next(tickers), "minimized Inspect retained travel work")
    units.target = "B"
    Event(runtime, "PLAYER_TARGET_CHANGED")
    assert(not runtime.view.frame:IsShown(), "stale Inspect remained")
    units.target = "A"
    RequestInspect("target")
    InspectFrame:Show()
    Event(runtime, "INSPECT_READY", "A")
    Flush()
    assert(next(tickers), "reopening Inspect did not resume mounted speed")
    local nativeRequest = requests
    inspectAllowed = secret
    actions.contextAction({})
    assert(requests == nativeRequest and runtime.view.frame:IsShown(), "unknown Inspect eligibility triggered a request")
    inspectAllowed = true
    actions.contextAction({})
    assert(requests == nativeRequest + 1 and not runtime.view.frame:IsShown() and not callbacks.INSPECT_READY,
        "native Inspect action did not issue exactly one native request")
    assert(not callbacks.UNIT_AURA and not next(tickers), "closing Inspect retained travel work")
    InspectFrame:Show()
    Event(runtime, "INSPECT_READY", "A")
    Flush()
    assert(InspectFrame:IsShown() and not runtime.view.frame:IsShown(), "explicit native Inspect was reintercepted")
    InspectFrame:Hide()
    Press("C")
    assert(openSounds == beforeSounds + 2, "reopening the player window did not replay its sound")
    local beforeCancel = cancelledGestures
    local beforeCombatStats, beforeCombatCrit = statReads, critReads
    Event(runtime, "PLAYER_REGEN_DISABLED")
    assert(lastCombatRail and not FindRow("Crit") and FindRow("Health") == 595
        and statReads == beforeCombatStats and critReads == beforeCombatCrit,
        "stat restriction waited for lockdown or sampled combat stats")
    assert(runtime.view == hostedView and hostedView.frame:IsShown() and cancelledGestures == beforeCancel + 1
        and lastWindowAction == "scaleStop",
        "entering combat closed the hosted view or kept an old gesture")
    locked = true
    local nativeClick, nativeDrag = nativeSlots[13].scripts.OnClick, nativeSlots[16].scripts.OnDragStart
    NativeSlot(13, "OnClick")
    NativeSlot(16, "OnDragStart")
    assert(usedSlot == 13 and pickedSlot == 16 and nativeModel:IsVisible() and runtime.view.frame:IsShown(),
        "the same combat window lost native trinket, weapon or model behavior")
    usedSlot, pickedSlot = nil, nil
    NativeSlot(16, "OnReceiveDrag")
    assert(pickedSlot == 16 and nativeSlots[13].scripts.OnClick == nativeClick
        and nativeSlots[16].scripts.OnDragStart == nativeDrag, "Suite replaced a native slot script")
    actions.tab("gear")
    actions.group(1)
    assert(runtime.slot == 1 and lastRail[1].title == "Helm" and not usedSlot and not lastWithModel,
        "combat item details no longer belong to the same window")
    actions.tab("reputation")
    assert(lastTab == "reputation" and nativeModel:IsVisible(), "combat tab displaced the native viewport")
    local beforeNative = nativeToggles
    Press("C")
    assert(nativeToggles == beforeNative + 1 and not CharacterFrame:IsVisible() and not hostedView.frame:IsShown()
        and not runtime.kind and not presented, "native close left the hosted window or its footprint active")
    pad = true
    Press("C")
    assert(CharacterFrame:IsVisible() and hostedView.frame:IsShown() and runtime.view == hostedView
        and lastTab == "overview", "C did not reopen the same hosted panel in combat")
    pad = false
    Press("U")
    assert(CharacterFrame:IsVisible() and hostedView.frame:IsShown() and not nativeModel:IsVisible()
        and lastTab == "reputation" and lastGroup == "reputation", "Reputation routed to the native report in combat")
    actions.tab("gear")
    assert(not nativeModel:IsVisible() and lastTab == "gear" and lastReport,
        "a report backing pane did not keep the Suite equipment data available")
    Press("C")
    assert(CharacterFrame:IsVisible() and hostedView.frame:IsShown() and nativeModel:IsVisible() and lastTab == "overview",
        "returning to PaperDoll lost the hosted view or native equipment")
    locked = false
    Event(runtime, "PLAYER_REGEN_ENABLED")
    assert(hostedView.frame:IsShown() and CharacterFrame:IsVisible(), "combat exit changed the active window")
    assert(not lastCombatRail and FindRow("Crit") == "1.00%" and FindRow("Armor") == 55,
        "public stats did not return after combat")
    missingLinks = true
    RequestInspect("target")
    InspectFrame:Show()
    Event(runtime, "INSPECT_READY", "A")
    Flush()
    assert(hostedView.frame:IsShown() and InspectFrame:IsShown(), "failed Inspect handoff hid the character dock")
    missingLinks = false
    RequestInspect("target")
    InspectFrame:Show()
    Event(runtime, "INSPECT_READY", "A")
    Flush()
    assert(not hostedView.frame:IsShown() and runtime.view == runtime.inspectView, "Inspect did not claim its own view")
    actions.close()
    Flush()
    assert(hostedView.frame:IsShown() and CharacterFrame:IsVisible(), "closing Inspect did not resume the already visible character dock")
    runtime.config.mode = 1
    runtime:Refresh()
    assert(CharacterFrame:IsVisible() and not hostedView.frame:IsShown() and not callbacks.INSPECT_READY
        and geometryReleased == 1 and lastWindowAction == "release",
        "Basic stopped the native Character window or kept the custom geometry")
    Press("C")
    assert(not CharacterFrame:IsVisible() and not hostedView.frame:IsShown(), "Basic retained the Suite view")

    local beforeFallback = geometryApplied
    locked = true
    runtime.config.mode = 2
    runtime:Refresh()
    Press("C")
    assert(runtime.view == runtime.dockView and runtime.view.frame:IsShown() and geometryApplied == beforeFallback,
        "combat startup applied unprepared geometry or lost the native fallback")
    actions.tab("reputation")
    locked = false
    Event(runtime, "PLAYER_REGEN_ENABLED")
    assert(runtime.view == hostedView and runtime.view.frame:IsShown() and lastTab == "reputation"
        and geometryApplied == beforeFallback + 1 and not runtime.dockView.frame:IsShown(),
        "combat exit did not restore wide art and retain the selected tab")
    local beforeStock = geometryReleased
    Press("UnmappedFrame")
    assert(CharacterFrame:IsVisible() and not hostedView.frame:IsShown() and geometryReleased == beforeStock + 1
        and not runtime.layoutRoot, "an unmapped native subframe kept Suite anchors")
    Press("C")
    assert(runtime.view == hostedView and hostedView.frame:IsShown() and runtime.layoutRoot == CharacterFrame,
        "the Suite geometry did not return after visiting a stock subframe")
    Press("C")
    Press("TokenFrame")
    assert(runtime.view == hostedView and lastTab == "currency" and lastGroup == "currency" and not nativeModel:IsVisible(),
        "opening Currency directly did not start the Suite report")
    actions.tab("reputation")
    ToggleCharacter("TokenFrame", true)
    Flush()
    assert(runtime.view == hostedView and lastTab == "currency", "an explicit link to the already-open native pane was ignored")
    local function HoverGearTab(id)
        ns.Routing.HoverGearTab({
            id = id, view = hostedView,
            GetRect = function() return 10, 20, 50, 30 end,
            GetEffectiveScale = function() return 3 end,
            GetFrameStrata = function() return "HIGH" end,
            GetFrameLevel = function() return 551 end,
        })
    end
    local function NativeGearClick(id)
        HoverGearTab(id)
        assert(gearProxy:IsShown() and gearProxy:GetAttribute("type1") == "click"
            and gearProxy:GetAttribute("clickbutton1") == CharacterMicroButton
            and gearProxy:GetAttribute("useOnKeyDown") == false and gearProxy.point[2] == UIParent
            and gearProxy.point[4] == 15 and gearProxy.point[5] == 30 and gearProxy.width == 75 and gearProxy.height == 45,
            "gear route did not prepare a detached Blizzard click at the tab's scaled position")
        local before = nativeToggles
        gearProxy.scripts.PreClick(gearProxy)
        gearProxy:GetAttribute("clickbutton1"):Click()
        gearProxy.scripts.PostClick(gearProxy)
        Flush()
        assert(nativeToggles == before + 1 and not gearProxy:IsShown() and lastTab == id
            and runtime.view == hostedView and nativeModel:IsVisible(), "gear tab click did not restore the native model and slots")
    end
    NativeGearClick("overview")
    HoverGearTab("overview")
    assert(not gearProxy:IsShown(), "gear overlay could toggle an already-shown PaperDoll closed")
    Press("TokenFrame")
    HoverGearTab("gear")
    Event(runtime, "PLAYER_REGEN_DISABLED")
    assert(not gearProxy:IsShown(), "combat transition kept a prepared detached click")
    locked = true
    HoverGearTab("overview")
    assert(not gearProxy:IsShown(), "a detached gear click armed in combat")
    locked = false
    Event(runtime, "PLAYER_REGEN_ENABLED")
    Flush()
    NativeGearClick("gear")
    NativeSlot(13, "OnClick")
    assert(usedSlot == 13, "returning through Equipment lost the native trinket")
    Press("TokenFrame")
    local routeReads, routeOpens = gearReads, openSounds
    if forever then
        for _, route in ipairs({ { "SkillsFrame", "skills" }, { "PVPRankFrame", "pvp" }, { "StatisticsFrame", "statistics" } }) do
            Press(route[1])
            assert(runtime.view == hostedView and lastTab == route[2] and lastGroup == route[2],
                "Forever link routed to the wrong tab: " .. route[1])
        end
    end
    Press("U")
    assert(runtime.view == hostedView and lastTab == "reputation" and gearReads == routeReads and openSounds == routeOpens,
        "changing native reports reopened the Suite or reread equipment")
    Press("U")
    assert(not hostedView.frame:IsShown() and not CharacterFrame:IsShown(), "the same native report did not toggle closed")
    CharacterFrame:Show()
    Flush()
    assert(hostedView.frame:IsShown() and lastTab == "reputation", "reopening the last native report missed the Suite")
    ToggleCharacter("TokenFrame", true)
    CharacterFrame:Hide()
    Flush()
    assert(not hostedView.frame:IsShown(), "closing the native window replayed a queued link")
    runtime.config.mode = 1
    runtime:Refresh()
    Press("U")
    assert(ReputationFrame:IsVisible() and not hostedView.frame:IsShown(), "Basic retained the Suite native routes")
    Press("U")
    assert(#UISpecialFrames == (forever and 2 or 1))
end

Run(false)
Run(true)
assert(nativeHides == 6)
print("Character Panel: both clients, audit navigation, native sets, Inspect comparison and native-hosted combat model and equipment passed")
