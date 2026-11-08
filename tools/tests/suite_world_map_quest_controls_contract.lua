local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message) assert(value, message) checks = checks + 1 end
local function Noop() end

local function CheckZoneFolds(NS, Frame, map, scroll, contents, row, active)
    local zone = { isHeader = true, isCollapsed = false, headerSortKey = "Redridge Mountains" }
    local otherZone = { isHeader = true, isCollapsed = false, headerSortKey = "Darkshore" }
    local header, other, objective, pin = Frame(contents), Frame(contents), Frame(contents), Frame(contents)
    local normal, highlight = header:CreateTexture(), header:CreateTexture()
    header.CollapseButton = Frame(header)
    header.CollapseButton.Icon = normal
    header.CollapseButton.GetHighlightTexture = function() return highlight end
    header.questLogIndex = 6
    row.info.header = zone
    other.info = { questID = 99, header = otherZone }
    objective.questID = row.info.questID
    local pinQuestID = objective.questID
    pin.GetQuestID = function() return pinQuestID end
    pin:SetAlpha(0.75)
    local nativeShow, nativeHide = pin.Show, pin.Hide
    function pin:Show() error("addon showed a native POI button") end
    function pin:Hide() error("addon hid a native POI button") end
    function pin:SetMouseClickEnabled(value) self.clicks = value end
    function pin:SetMouseMotionEnabled(value) self.motion = value end
    function pin:IsMouseClickEnabled() return self.clicks end
    function pin:IsMouseMotionEnabled() return self.motion end
    pin:SetMouseClickEnabled(true)
    pin:SetMouseMotionEnabled(false)
    local function PinVisible()
        return pin:IsShown() and pin:GetAlpha() == 0.75 and pin:IsMouseClickEnabled() and not pin:IsMouseMotionEnabled()
    end
    C_QuestLog.GetInfo = function(index) return index == 6 and zone or nil end
    C_QuestLog.GetHeaderIndexForQuest = function(id) return id == objective.questID and 6 or nil end
    local activeObjectives, activePins = {}, {}
    scroll.Contents = contents
    scroll.headerFramePool = { EnumerateActive = function() return pairs({ [header] = true }) end }
    scroll.objectiveFramePool = { EnumerateActive = function() return pairs(activeObjectives) end }
    contents.buttonPool = { EnumerateActive = function() return pairs(activePins) end }
    scroll.UpdateBackground = Noop
    scroll.ExpandHeaderForQuest = Noop
    local query = ""
    scroll.SearchBox.GetText = function() return query end
    function contents:SetSize(width, height)
        self.width, self.visibleQuests = width, height
    end
    function contents:GetLayoutChildren()
        return (row:IsShown() and 1 or 0) + (other:IsShown() and 1 or 0)
    end
    contents.rowWidth = 280
    function contents:LayoutChildren(children, expandToWidth)
        if not self.skipChildLayout then header.dirty = false end
        return expandToWidth or self.rowWidth, children, expandToWidth == nil
    end
    function contents:CalculateFrameSize(width, height) return math.max(width, 304), height end
    function contents:Layout()
        local children = self:GetLayoutChildren()
        local width, height = self:LayoutChildren(children, 304)
        self:SetSize(width, height)
        self.dirty = false
    end
    local plus, minus = "common-button-list-plus", "common-button-list-minus"
    local displayState = { questInfoContainer = { [6] = zone } }
    local function NativeRebuild()
        -- Native releases the pools, then shows only rows belonging to open headers.
        local shown = not zone.isCollapsed
        active[row], activeObjectives[objective], activePins[pin] = shown or nil, shown or nil, shown or nil
        if shown then row:Show() objective:Show() nativeShow(pin)
        else row:Hide() objective:Hide() nativeHide(pin) end
        header.CollapseButton.collapsed = zone.isCollapsed
        normal:SetAtlas(shown and minus or plus)
        highlight:SetAtlas(shown and minus or plus)
        scroll:UpdateBackground(displayState)
        contents:Layout()
    end
    local originalExpand = ExpandQuestHeader
    local explicitExpands, externalExpands, guideReads = 0, 0, 0
    local rebuildImmediately = true
    ExpandQuestHeader = function(index)
        if index == 0 then externalExpands = externalExpands + 1
        else explicitExpands = explicitExpands + 1 end
        zone.isCollapsed = false
        if rebuildImmediately then NativeRebuild() end
    end
    local function Click(button, guide)
        header:Fire("PreClick", button)
        if button == "LeftButton" then
            zone.isCollapsed = not zone.isCollapsed
            if rebuildImmediately then NativeRebuild() end
            if guide and zone.isCollapsed then
                ExpandQuestHeader(0)
                if not zone.isCollapsed then guideReads = guideReads + 1 end
            end
        end
        header:Fire("PostClick", button)
    end
    local function Folded(message)
        Check(not row:IsShown() and not objective:IsShown() and pin:IsShown()
            and pin:GetAlpha() == 0 and not pin:IsMouseClickEnabled() and not pin:IsMouseMotionEnabled()
            and other:IsShown() and contents.visibleQuests == 1 and normal:GetAtlas() == plus
            and highlight:GetAtlas() == plus, message)
    end
    active[other] = true
    NativeRebuild()
    Check(NS.WorldMapSkin.Apply(map, "map-quests"), "map fold adapter did not attach")
    Click("LeftButton", true)
    Folded("external expand-all reopened a manually folded zone or left a stray row")
    Check(guideReads == 1 and externalExpands == 1 and explicitExpands == 0 and not zone.isCollapsed,
        "fold masking changed the quest data used by a guide")
    ExpandQuestHeader(0)
    Folded("next native pool rebuild lost the fold")
    pinQuestID = other.info.questID
    NativeRebuild()
    Check(PinVisible(), "a pooled POI inherited another quest's suppression")
    pinQuestID = objective.questID
    NativeRebuild()
    Folded("reacquired POI escaped the fold")
    Click("RightButton", false)
    Folded("right click changed the fold")
    NS.WorldMapQuests.SetLayout("blizzard")
    Folded("switching quest layouts lost the fold")
    query = "Quest"
    NativeRebuild()
    Check(row:IsShown() and PinVisible() and normal:GetAtlas() == minus, "fold masked a native search result")
    query = ""
    NativeRebuild()
    Folded("clearing native search did not restore the fold")
    NS.WorldMapQuests.SetLayout("compact")
    Check(not row.labels[2]:IsShown(), "masked quest still retained shown compact columns")
    rebuildImmediately = false
    contents.dirty, header.dirty = true, true
    Click("LeftButton", false)
    Check(row:IsShown() and objective:IsShown() and PinVisible() and explicitExpands == 1
        and normal:GetAtlas() == minus, "second click did not expand the locally folded zone")
    Check(row.labels[2]:IsShown(), "local reopen left a blank compact quest until native rebuild")
    Check(contents.visibleQuests == 2 and contents.width == 304, "local reopen did not lay out the expanded rows")
    Check(contents.dirty == true, "local reopen cleared Blizzard's pending layout state")
    Check(header.dirty == true and contents.skipChildLayout == nil, "local reopen changed native child layout state")
    rebuildImmediately = true
    Click("LeftButton", true)
    scroll:ExpandHeaderForQuest(objective.questID)
    NativeRebuild()
    Check(row:IsShown() and contents.visibleQuests == 2, "native pin navigation could not reveal its quest")
    Click("LeftButton", true)
    Folded("zone could not be folded again after pin navigation")
    ExpandQuestHeader = originalExpand
    contents.dirty = true
    return function()
        Check(row:IsShown() and objective:IsShown() and PinVisible() and normal:GetAtlas() == minus
            and contents.visibleQuests == 2, "disabling skin left quest rows hidden or the disclosure changed")
        Check(contents.dirty == true, "disabling the skin cleared Blizzard's pending layout state")
    end
end

local function Run(flavor)
    arg[2], arg[3] = flavor, "coverage"
    local H = assert(loadfile(root .. "/tools/tests/suite_skin_menu_transitions_contract.lua"))()
    arg[3] = nil
    local NS, Frame, Load = H.NS, H.Frame, H.Load
    local combat, delayed, cvar, objectiveReads = false, {}, "1", 0
    NS.IsCombatLocked = function() return combat end
    InCombatLockdown = function() return combat end
    NS.DB.questLog = { layout = "blizzard" }
    NS.DB.skins = {}
    local opacity, color = 1, 0.4
    NS.Theme = { GetColor = function() return color, 0.6, 0.8, 1 end,
        GetMaterialOpacity = function() return opacity end }
    NS.L = setmetatable({}, { __index = function(_, key) return key end })
    NS.WindowControls = { Refresh = Noop }
    NS.QuestText = { Activate = Noop, Deactivate = Noop }
    NS.Registry.NotifyListeners = function(domain)
        for owner, callback in pairs(H.listeners) do callback(owner, domain) end
    end
    NS.Surface = { Attach = function(_, spec) return { spec = spec } end, SetVisible = Noop }
    local searchSkins, buttonSkins = {}, {}
    NS.ControlSkin = {
        ApplySearchBox = function(box, _, spec) searchSkins[box] = spec return {} end,
        ApplyButton = function(button) buttonSkins[button] = true return {} end,
    }
    NS.GenericWindows = { ApplyFrame = function() return true, "applied", { nodeLimited = false } end,
        ApplyDescendant = Noop, RefreshDescendant = Noop, TrackMenuMotion = Noop,
        Disable = function(owner) NS.Cosmetics.RestoreOwner(owner) end }
    NS.CombatGate = { RunOrDefer = function(key, callback)
        if combat then delayed[key] = callback else callback() end
    end }
    Load("Core/Cosmetics.lua")
    Load("Adapters/AdapterKit.lua")
    hooksecurefunc = function(target, name, callback)
        if type(target) == "string" then target, name, callback = _G, target, name end
        local original = target[name]
        target[name] = function(...)
            local first, second = original(...)
            callback(...)
            return first, second
        end
    end
    EventRegistry = Frame()
    local created = H.frames
    local oldCreateFrame = CreateFrame
    local cvarEvents
    CreateFrame = function(...)
        local frame = oldCreateFrame(...)
        cvarEvents = frame
        return frame
    end
    local asyncEvents, asynchronous = {}, false
    GetCVar = function(name) Check(name == "showQuestObjectivesInLog", "unexpected CVar read") return cvar end
    SetCVar = function(name, value)
        cvar = tostring(value)
        if asynchronous then asyncEvents[#asyncEvents + 1] = { name, cvar }
        else cvarEvents:Fire("OnEvent", "CVAR_UPDATE", name, cvar) end
    end
    local function External(value)
        cvar = tostring(value)
        cvarEvents:Fire("OnEvent", "CVAR_UPDATE", "showQuestObjectivesInLog", cvar)
    end
    local function FlushCVar()
        for _, event in ipairs(asyncEvents) do cvarEvents:Fire("OnEvent", "CVAR_UPDATE", unpack(event)) end
        asyncEvents = {}
    end
    C_QuestLog = { IsComplete = function(id) return id == 2 end }
    GetNumQuestLeaderBoards = function() return 2 end
    GetQuestObjectiveInfo = function(_, index)
        objectiveReads = objectiveReads + 1
        return "objective", "item", index == 1, index == 1 and 2 or 1, 2
    end
    local oldMenu, modifyQuestMenu = Menu
    Menu = { ModifyMenu = function(tag, callback)
        Check(tag == "MENU_QUEST_MAP_FRAME_SETTINGS", "quest layout hooked the wrong native menu")
        modifyQuestMenu = callback
    end }
    Load("Adapters/WorldMapQuests.lua")
    CreateFrame = oldCreateFrame
    Load("Adapters/WorldMap.lua")
    local map, log, quests, scroll, contents = Frame(UIParent), Frame(), Frame(), Frame(), Frame()
    map.QuestLog, log.QuestsFrame, quests.ScrollFrame = log, quests, scroll
    log.parent, quests.parent, scroll.parent, contents.parent = map, log, quests, scroll
    local search = Frame(scroll)
    scroll.SearchBox, scroll.SettingsDropdown = search, Frame(scroll)
    local searches = 0
    local nativeSearch = function() searches = searches + 1 end
    search:SetScript("OnTextChanged", nativeSearch)
    map.BorderFrame = Frame(map)
    local actions = Frame(map.BorderFrame)
    map.BorderFrame.MaximizeMinimizeFrame = actions
    actions.MaximizeButton, actions.MinimizeButton = Frame(actions), Frame(actions)
    local active = {}
    scroll.titleFramePool = { EnumerateActive = function() return pairs(active) end }
    local tooltip, clicked, framesBefore = nil, 0, #created
    local function Acquire(id)
        local row = Frame(contents)
        row.info, row.questLogIndex, row.mouseOver = { questID = id, title = "Quest " .. id, level = 17 }, id, false
        function row:IsMouseOver() return self.mouseOver end
        row.Text = row:CreateFontString()
        row.Text.font, row.Text.color = { "quest.ttf", 15, "OUTLINE" }, { 1, 0.8, 0, 1 }
        function row.Text:SetAlpha(alpha)
            self.alpha, self.color[4] = alpha, alpha
        end
        function row.Text:SetTextColor(r, g, b, a)
            self.color = { r, g, b, a or 1 }
            self.alpha = self.color[4]
        end
        row.HighlightTexture = row:CreateTexture()
        row.HighlightTexture:Hide()
        local nativeTexture = row.CreateTexture
        row.CreateTexture = function(self, ...)
            local texture = nativeTexture(self, ...)
            function texture:SetShown(value) self.shown = value end
            function texture:SetColorTexture(...) self.color = { ... } end
            row.plate = texture
            return texture
        end
        local nativeFont = row.CreateFontString
        row.labels = {}
        row.CreateFontString = function(self, ...)
            local label = nativeFont(self, ...)
            label.SetWordWrap, label.SetWidth, label.SetJustifyH = Noop, Noop, Noop
            function label:SetShown(value) self.shown = value end
            function label:SetFontObject(object) self.fontObject = object end
            local getFont = label.GetFont
            function label:GetFont()
                if self.fontObject then return unpack(self.fontObject) end
                return getFont(self)
            end
            local setFont = label.SetFont
            function label:SetFont(face, size, flags)
                Check(type(face) == "string" and type(size) == "number", "font size was lost")
                setFont(self, face, size, flags)
            end
            row.labels[#row.labels + 1] = label
            return label
        end
        row:SetScript("OnEnter", function(self) self.HighlightTexture:Show() tooltip = self.info.questID end)
        row:SetScript("OnLeave", function(self) self.HighlightTexture:Hide() tooltip = nil end)
        row:SetScript("OnClick", function() clicked = clicked + 1 end)
        active[row] = true
        return row
    end
    local row = Acquire(1)
    local nativeEnter, nativeLeave, nativeClick = row.scripts.OnEnter, row.scripts.OnLeave, row.scripts.OnClick
    local nativeRebuilds = 0
    QuestLogQuests_Update = function() nativeRebuilds = nativeRebuilds + 1 end
    Check(NS.WorldMapSkin.Apply(map, "map-quests"), "map skin did not apply")
    Check(searchSkins[search] and searchSkins[search].pillHeight == 28, "dedicated quest search skin missing")
    Check(buttonSkins[actions.MaximizeButton] and buttonSkins[actions.MinimizeButton], "native map size buttons omitted")
    Check(search.scripts.OnTextChanged == nativeSearch, "native search was replaced")
    search:Fire("OnTextChanged")
    Check(searches == 1 and cvar == "1" and #row.labels == 0, "Blizzard layout changed behavior")
    Check(row.plate and not row.plate.shown and row.HighlightTexture.alpha == 0, "hover plate not prepared")
    row.mouseOver = true
    row:Fire("OnEnter")
    Check(tooltip == 1 and row.plate.shown, "row hover lost native tooltip or full-row highlight")
    row.mouseOver = false
    row:Fire("OnLeave")
    Check(tooltip == nil and not row.plate.shown, "row leave retained tooltip/highlight")
    row.HighlightTexture:Show()
    QuestLogQuests_Update()
    Check(row.plate.shown, "map-pin hover lost native quest-row callout")
    row.HighlightTexture:Hide()
    QuestLogQuests_Update()
    Check(not row.plate.shown, "map-pin leave retained quest-row callout")
    NS.DB.theme.hoverStyle = "off"
    NS.Registry.NotifyListeners("appearance")
    Check(row.HighlightTexture.alpha == 1 and not row.plate.shown, "hover off removed native map-pin glow")
    NS.DB.theme.hoverStyle, opacity = "softFill", 0
    row.mouseOver = true
    row:Fire("OnEnter")
    Check(row.plate.color[4] == 0, "quest highlight ignored control opacity")
    opacity = 1
    External("0")
    External("1")
    Check(NS.WorldMapQuests.SetLayout("compact") and cvar == "0", "compact layout failed after native CVar edits")
    Check(#row.labels == 3, "compact quest columns missing")
    Check(nativeRebuilds == 2, "switching layouts invoked the native quest pool rebuild from addon code")
    row.Text:SetTextColor(1, 0.8, 0)
    Check(not row.Text:IsShown(), "native color repaint exposed a second quest title")
    row.Text:SetTextColor(0.8, 0.1, 0.1, 0)
    row:Fire("OnLeave")
    Check(row.labels[2].color[1] == 0.8 and row.labels[2].color[4] == 1,
        "native title alpha hid the compact title on hover leave")
    row.Text:SetTextColor(1, 0.8, 0)
    Check(row.labels[1].text == 17 and row.labels[2].text == "Quest 1" and row.labels[3].text == "3/4",
        "compact level, title or objective progress is wrong")
    row.info.difficultyLevel = 17
    QuestUtilsOverrides = { GetQuestTitlePrefix = function() return "[17+] " end }
    row.Text:SetText("|TReplay:16|t[2] [17+] Quest 1")
    row.Text.fontObject = { "shared.ttf", 18, "OUTLINE" }
    function row.Text:GetFontObject() return self.fontObject end
    QuestLogQuests_Update()
    Check(row.labels[2].text == "|TReplay:16|t[2] Quest 1", "compact title lost native replay/party decorations")
    row.Text.fontObject[2] = 22
    local _, inheritedSize = row.labels[2]:GetFont()
    Check(inheritedSize == 22, "compact text did not inherit live shared-font changes")
    color = 0.9
    NS.Registry.NotifyListeners("color")
    Check(row.labels[1].color[1] == 0.9 and row.labels[3].color[1] == 0.9,
        "compact level/progress retained old theme colors")
    local rebuildsBeforeTheme = nativeRebuilds
    color = 0.7
    NS.Registry.NotifyListeners("theme")
    Check(nativeRebuilds == rebuildsBeforeTheme and row.labels[1].color[1] == 0.7,
        "theme repaint rebuilt the native quest list")
    row.info = { questID = 2, title = "Ready quest", level = 20 }
    row.Text:SetText("Ready quest")
    QuestLogQuests_Update()
    Check(row.labels[2].text == "Ready quest" and row.labels[3].text == "Ready", "recycled row retained old quest data")
    row:Fire("OnClick")
    Check(clicked == 1 and row.scripts.OnEnter == nativeEnter and row.scripts.OnLeave == nativeLeave
        and row.scripts.OnClick == nativeClick, "compact presentation replaced native quest actions")
    local reads = objectiveReads
    map.shown = false
    QuestLogQuests_Update()
    Check(objectiveReads == reads, "hidden map queried compact objective progress")
    map.shown = true
    NS.WorldMapSkin:OnWorldMapShown()
    Check(NS.WorldMapQuests.SetLayout("blizzard") and cvar == "1" and row.Text:IsShown()
        and not row.labels[1].shown, "Blizzard switch did not restore preference/text")
    asynchronous = true
    NS.WorldMapQuests.SetLayout("compact")
    FlushCVar()
    NS.WorldMapQuests.SetLayout("blizzard")
    FlushCVar()
    Check(cvar == "1", "asynchronous own CVar event lost native preference")
    NS.WorldMapQuests.SetLayout("compact")
    NS.WorldMapQuests.SetLayout("blizzard")
    NS.WorldMapQuests.SetLayout("compact")
    FlushCVar()
    cvarEvents:Fire("OnEvent", "PLAYER_LOGOUT")
    FlushCVar()
    Check(cvar == "1", "batched asynchronous switches lost native preference")
    NS.WorldMapQuests.SetLayout("blizzard")
    FlushCVar()
    asynchronous = false
    NS.WorldMapQuests.SetLayout("compact")
    External("1")
    External("0")
    NS.WorldMapQuests.SetLayout("blizzard")
    Check(cvar == "0", "mode switch overwrote a later native preference")
    External("1")
    NS.WorldMapQuests.SetLayout("compact")
    cvarEvents:Fire("OnEvent", "PLAYER_LOGOUT")
    Check(cvar == "1", "logout/reload did not restore native objective preference")
    NS.WorldMapQuests.Refresh()
    Check(cvar == "0", "compact preference did not reacquire after reload boundary")
    NS.WorldMapQuests.SetLayout("blizzard")
    local historyKey, historyCount = nil, 0
    local P = { Suite = {}, M = {}, W = {}, HM = {}, Combat = function() return combat end,
        Tr = function(text) return text end, Meta = function() return {} end,
        RegisterSummary = Noop, SummaryPriority = Noop, Refresh = Noop,
        SkinSearchRow = function(ctx, item, section)
            item.testSection = section
            ctx.searchRows[#ctx.searchRows + 1] = item
        end,
        WithHistory = function(_, key, callback)
            historyKey, historyCount = key, historyCount + 1
            return callback()
        end }
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/AppearanceKit.lua"))("MSUF_Suite_Options", P)
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/AppearanceQuests.lua"))("MSUF_Suite_Options", P)
    local ctx = { searchRows = {} }
    P.BuildSkinQuestLogSection(ctx, {}, NS)
    local setting = ctx.searchRows[2]
    Check(setting.id == "questLog.layout" and setting.testSection == "suite_skin_quests"
        and #setting.values == 2 and setting.get() == "blizzard", "Skinning switch/search route missing")
    local radios, gearHistory = {}, 0
    NS.SuiteCore = function() return { HostBridge = { WithMenuHistory = function(label, key, callback)
        Check(label == "Quest list layout" and key == "suite:skin.questLog.layout", "gear used a different history setting")
        gearHistory = gearHistory + 1
        return callback()
    end } } end
    local rootMenu = { CreateDivider = Noop, CreateTitle = Noop,
        CreateRadio = function(_, label, selected, select, value)
            radios[value] = { label = label, selected = selected, select = select }
            return { SetEnabled = Noop }
        end }
    Check(modifyQuestMenu ~= nil, "quest layout missing from the map gear menu")
    modifyQuestMenu(scroll.SettingsDropdown, rootMenu)
    Check(radios.blizzard.label == "Blizzard" and radios.compact.label == "Compact"
        and radios.blizzard.selected("blizzard"), "map gear did not expose both layouts and current selection")
    radios.compact.select("compact")
    Check(gearHistory == 1 and setting.get() == "compact" and cvar == "0", "map gear did not switch to compact")
    radios.blizzard.select("blizzard")
    Check(gearHistory == 2 and setting.get() == "blizzard" and cvar == "1", "map gear did not restore Blizzard layout")
    setting.set("compact")
    Check(historyCount == 1 and historyKey == "suite:skin.questLog.layout" and cvar == "0",
        "Skinning switch did not record exactly one menu history change")
    NS.DB.questLog = { layout = "blizzard" }
    NS.Registry.NotifyListeners("profile")
    Check(cvar == "1" and row.Text:IsShown(), "Undo/profile restore retained compact quest presentation")
    NS.DB.questLog = { layout = "compact" }
    NS.Registry.NotifyListeners("profile")
    Check(cvar == "0" and not row.Text:IsShown(), "Redo/profile restore did not restore compact presentation")
    local originalSetText, dispatch, reported = row.labels[1].SetText, NS.Safety.Dispatch, 0
    NS.Safety.Dispatch = function(callback, ...)
        local ok, value = pcall(callback, ...)
        if not ok then reported = reported + 1 return end
        return value
    end
    row.labels[1].SetText = function() error("contract: compact quest paint failed") end
    NS.WorldMapQuests.Refresh()
    row.labels[1].SetText = originalSetText
    NS.WorldMapQuests.SetLayout("blizzard")
    Check(reported == 1 and cvar == "1" and row.Text:IsShown(), "paint error latched future layout restoration")
    NS.WorldMapQuests.SetLayout("compact")
    NS.Safety.Dispatch = dispatch
    combat = true
    Check(not NS.WorldMapQuests.SetLayout("blizzard"), "combat changed quest layout")
    row.protected = true
    function row:IsProtected() return self.protected, false end
    row.mouseOver = false
    row:Fire("OnLeave")
    Check(next(delayed) ~= nil, "protected hover did not defer combat paint")
    combat = false
    for key, callback in pairs(delayed) do delayed[key] = nil callback() end
    Check(not row.plate.shown, "deferred hover did not clear after combat")
    local checkReleasedFolds = CheckZoneFolds(NS, Frame, map, scroll, contents, row, active)
    NS.WorldMapSkin.Disable(map, "map-quests")
    checkReleasedFolds()
    Check(cvar == "1" and row.Text:IsShown() and row.HighlightTexture.alpha == 1,
        "disable did not restore native quest presentation")
    Check(not row.labels[1].shown and not row.plate.shown, "disable retained owned quest visuals")
    Check(#created > framesBefore, "contract did not exercise owned visual creation")
    _G.WorldMapFrame, _G.QuestLogQuests_Update, _G.QuestUtilsOverrides = nil, nil, nil
    Menu = oldMenu
end

Run("Mainline")
Run("Forever")
print("Suite map quest controls: " .. checks .. " checks passed")
