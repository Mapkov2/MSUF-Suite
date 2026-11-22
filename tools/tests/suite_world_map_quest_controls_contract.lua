local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message) assert(value, message) checks = checks + 1 end
local function Noop() end

local function MountSpoken(Frame, scroll, row, other)
    local overlay = { questPlayButtons = {}, questContributeButtons = {}, displayedButtons = {}, enabled = true }
    local function Button()
        local button = Frame(scroll)
        button.kind, button.clicks, button.motion = "Button", true, true
        function button:IsMouseClickEnabled() return self.clicks end
        function button:SetMouseClickEnabled(value) self.clicks = value end
        function button:IsMouseMotionEnabled() return self.motion end
        function button:SetMouseMotionEnabled(value) self.motion = value end
        button:Hide()
        return button
    end
    for _, title in ipairs({ row, other }) do
        title.Checkbox = title.Checkbox or Frame(title)
        local play = Button()
        play.questID = title.info.questID
        overlay.questPlayButtons[play.questID] = play
    end
    function overlay:GetPlayButtonParent() return scroll end
    function overlay:ShowsQuestLogButtons() return self.enabled end
    function overlay:UpdateQuestTitle(title, button)
        button:ClearAllPoints()
        button:SetPoint("RIGHT", title.Checkbox, "LEFT", -3, 0)
    end
    function overlay:Update()
        for _, button in ipairs(self.displayedButtons) do button:Hide() end
        wipe(self.displayedButtons)
        if not self:ShowsQuestLogButtons() then return end
        for title in scroll.titleFramePool:EnumerateActive() do
            local id = title.questID
            if self.questPlayButtons[id] then
                local button = self.questPlayButtons[id]
                if id == self.contribution then
                    self.questContributeButtons[id] = self.questContributeButtons[id] or Button()
                    button = self.questContributeButtons[id]
                end
                button:SetParent(title:GetParent())
                self:UpdateQuestTitle(title, button)
                button:Show()
                table.insert(self.displayedButtons, button)
            end
        end
    end
    _G.VoiceOver = { AddonFolder = "Spoken_Quests", QuestOverlayUI = overlay }
    return overlay
end

local function CheckSpokenButton(button, shown, message)
    local visible = button:IsVisible() and button:GetAlpha() > 0 or false
    local clickable = button:IsVisible() and button:IsMouseClickEnabled() or false
    local hoverable = button:IsVisible() and button:IsMouseMotionEnabled() or false
    Check(visible == shown and clickable == shown and hoverable == shown, message)
end

local function CheckZoneFolds(NS, Frame, map, scroll, contents, row, active, HoldSkinJobs, FlushSkinJobs, External, CombatRebuild, events)
    local forever = NS.Client.isForever
    row.protected = false
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
    local textHeight, nativeTitleHeight = 16, 63
    local compactTitleHeight = textHeight + 18
    other.height = 54
    function row.Text:GetHeight() return textHeight end
    function row:SetHeight(height) self.height = height end
    local pinQuestID = objective.questID
    pin.GetQuestID = function() return pinQuestID end
    -- The C frame parent is Contents; Blizzard's separate Lua .parent points at the title.
    function pin:GetParent() return contents end
    function pin:IsVisible() return self.shown and contents:IsVisible() end
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
        self.width, self.height = width, height
        self.visibleQuests = (row:IsShown() and 1 or 0) + (other:IsShown() and 1 or 0)
        self.visibleObjectives = objective:IsShown() and 1 or 0
    end
    function contents:GetLayoutChildren()
        -- The native title contains the objective space even after objective rows hide.
        return (row:IsShown() and row:GetHeight() or 0) + (other:IsShown() and other:GetHeight() or 0)
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
    local spoken
    if forever then _G.QuestScrollFrame = scroll end
    local function NativeRebuild(hideActiveTitle)
        -- Native releases the pools, then shows only rows belonging to open headers.
        local shown = not zone.isCollapsed
        local showObjective = shown and (not forever or GetCVar("showQuestObjectivesInLog") == "1")
        active[row], activeObjectives[objective], activePins[pin] = shown or nil, showObjective or nil, shown or nil
        row.questID, other.questID = row.info.questID, other.info.questID
        pin.parent = pinQuestID == row.questID and row or other
        pin:ClearAllPoints()
        pin:SetPoint("TOPLEFT", pin.parent, 6, -4)
        row.height = showObjective and nativeTitleHeight or compactTitleHeight
        if shown then row:Show() nativeShow(pin)
        else row:Hide() nativeHide(pin) end
        if hideActiveTitle then row:Hide() end
        if showObjective then objective:Show() else objective:Hide() end
        header.CollapseButton.collapsed = zone.isCollapsed
        normal:SetAtlas(shown and minus or plus)
        highlight:SetAtlas(shown and minus or plus)
        scroll:UpdateBackground(displayState)
        contents:Layout()
        if spoken then spoken:Update() end
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
    if forever then
        Check(row:IsShown() and not objective:IsShown() and contents.visibleObjectives == 0 and PinVisible(),
            "Compact did not locally mask and reflow only the objective rows")
        Check(row:GetHeight() == compactTitleHeight and contents.height == compactTitleHeight + other:GetHeight(),
            "Compact left blank objective space inside the native quest title")
        -- A new native opening has not reached its protected reading emote.
        map:Hide()
        map:Show()
        HoldSkinJobs()
        nativeTitleHeight = 78
        NativeRebuild()
        Check(objective:IsShown() and row:GetHeight() == nativeTitleHeight and contents.visibleObjectives == 1,
            "Compact changed the native opening before WorldMapOnShow")
        NS.WorldMapSkin:OnWorldMapShown()
        FlushSkinJobs()
        Check(not objective:IsShown() and contents.visibleObjectives == 0 and row:GetHeight() == compactTitleHeight
            and contents.height == compactTitleHeight + other:GetHeight(), "Compact did not reflow rebuilt objectives")
        -- Quest consumers rebuild the completed map repeatedly. Native Layout
        -- must never see an objective-bearing intermediate frame in this phase.
        HoldSkinJobs()
        for _ = 1, 25 do
            NativeRebuild()
            Check(not objective:IsShown() and contents.visibleObjectives == 0 and row:GetHeight() == compactTitleHeight,
                "an open-map quest scan flashed the native objective layout")
        end
        FlushSkinJobs()
        CombatRebuild(NativeRebuild, function()
            Check(not objective:IsShown() and row:GetHeight() == compactTitleHeight,
                "Compact lost its objective mask or title height during combat")
        end)
        Check(not objective:IsShown() and row:GetHeight() == compactTitleHeight,
            "Compact did not reapply objective masking after lockdown")
        NS.WorldMapQuests.SetLayout("blizzard")
        Check(objective:IsShown() and contents.visibleObjectives == 1 and row:GetHeight() == nativeTitleHeight
            and contents.height == nativeTitleHeight + other:GetHeight(), "Blizzard layout did not restore native objectives")
        NS.WorldMapQuests.SetLayout("compact")
        row:SetHeight(nativeTitleHeight + 7)
        NS.WorldMapQuests.SetLayout("blizzard")
        Check(row:GetHeight() == nativeTitleHeight + 7, "releasing Compact overwrote a later native title height")
        NS.WorldMapQuests.SetLayout("compact")
        External("0")
        NativeRebuild()
        NS.WorldMapQuests.SetLayout("blizzard")
        Check(not objective:IsShown() and row:GetHeight() == compactTitleHeight
            and GetCVar("showQuestObjectivesInLog") == "0", "Blizzard layout ignored the user's disabled objectives")
        External("1")
        NativeRebuild()
        Check(objective:IsShown() and row:GetHeight() == nativeTitleHeight,
            "native objectives did not return after the user enabled them")
        NS.WorldMapQuests.SetLayout("compact")
        Check(not objective:IsShown() and contents.visibleObjectives == 0, "returning to Compact lost the objective mask")
    end
    Click("LeftButton", true)
    Folded("external expand-all reopened a manually folded zone or left a stray row")
    if forever then
        NativeRebuild(true)
        Folded("a second filter hiding the folded title revealed its native POI before Spoken loaded")
        NativeRebuild()
        -- Spoken may build its buttons during initialization, before its ADDON_LOADED event.
        spoken = MountSpoken(Frame, scroll, row, other)
        spoken:Update()
        events:Fire("OnEvent", "ADDON_LOADED", "Spoken_Quests")
        local id = row.questID
        CheckSpokenButton(spoken.questPlayButtons[id], false, "Spoken Play overlays the header of a folded quest")
        CheckSpokenButton(spoken.questPlayButtons[other.questID], true, "folding a zone took Play from its visible neighbor")
        Check(spoken.questContributeButtons[id] == nil, "expected a quest without a cached Contribute button")
        spoken.contribution = id
        spoken:Update()
        CheckSpokenButton(spoken.questContributeButtons[id], false, "Spoken refreshed Contribute over a folded quest")
        spoken.enabled = false
        spoken:Update()
        query = "Quest"
        NativeRebuild()
        CheckSpokenButton(spoken.questContributeButtons[id], false, "search resurrected a button disabled in Spoken")
        spoken.enabled = true
        spoken:Update()
        CheckSpokenButton(spoken.questContributeButtons[id], true, "the visible search result lost Spoken Contribute")
        query = ""
        NativeRebuild()
        CheckSpokenButton(spoken.questContributeButtons[id], false, "clearing search left a floating Contribute button")
        -- A native pool rebuild can exchange the two row objects between quests.
        -- The original quest's button follows it to the visible row.
        row.questID, other.questID = other.questID, row.questID
        row.info.questID, other.info.questID = row.questID, other.questID
        NativeRebuild()
        CheckSpokenButton(spoken.questContributeButtons[id], true, "Contribute kept the old row's suppression after reuse")
        CheckSpokenButton(spoken.questPlayButtons[row.questID], false, "Play escaped its new folded row after reuse")
        row.questID, other.questID = other.questID, row.questID
        row.info.questID, other.info.questID = row.questID, other.questID
        NativeRebuild()
    end
    -- A protected pin restore must replay after combat on either client.
    function pin:IsProtected() return self.protected == true, false end
    pin.protected, query = true, "Quest"
    CombatRebuild(NativeRebuild, function()
        Check(pin:GetAlpha() == 0, "combat changed a protected pin")
    end)
    Check(PinVisible(), "protected pin restore was lost after combat")
    pin.protected, query = false, ""
    NativeRebuild()
    Folded("pin restore lost the player's folded header")
    -- Folds also work when Compact is off and a map opening has not settled.
    NS.WorldMapQuests.SetLayout("blizzard")
    map:Hide()
    map:Show()
    local oldAfter, pending = C_Timer.After, {}
    C_Timer.After = function(_, callback) pending[#pending + 1] = callback end
    CombatRebuild(function()
        NativeRebuild()
        QuestLogQuests_Update()
        local batch = pending
        pending = {}
        for _, callback in ipairs(batch) do callback() end
        Folded("Blizzard-layout folds were lost during an unready combat open")
    end, Noop)
    C_Timer.After = oldAfter
    NS.WorldMapSkin:OnWorldMapShown()
    NS.WorldMapQuests.SetLayout("compact")
    Check(guideReads == 1 and externalExpands == 1 and explicitExpands == 0 and not zone.isCollapsed,
        "fold masking changed the quest data used by a guide")
    if forever then
        HoldSkinJobs()
        ExpandQuestHeader(0)
        Folded("an open-map quest scan flashed an externally reopened group")
        FlushSkinJobs()
        Folded("queued row styling changed the completed compact layout")
    end
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
    Check(row:IsShown() and objective:IsShown() == (not forever) and PinVisible() and explicitExpands == 1
        and normal:GetAtlas() == minus, "second click did not expand the locally folded zone")
    Check(row.labels[2]:IsShown(), "local reopen left a blank compact quest until native rebuild")
    if spoken then
        CheckSpokenButton(spoken.questContributeButtons[row.questID], true, "local reopen left Spoken Contribute missing")
    end
    Check(contents.visibleQuests == 2 and contents.width == 304, "local reopen did not lay out the expanded rows")
    Check(contents.dirty == true, "local reopen cleared Blizzard's pending layout state")
    Check(header.dirty == true and contents.skipChildLayout == nil, "local reopen changed native child layout state")
    if spoken then
        spoken.contribution = nil
        NativeRebuild(true)
        Check(active[row] and not row:IsShown() and normal:GetAtlas() == minus, "expected an active hidden quest under an open header")
        Check(pin:IsVisible() and pin:GetAlpha() == 0 and not pin:IsMouseClickEnabled() and not pin:IsMouseMotionEnabled(),
            "the native POI of an active hidden quest overlaps the header")
        CheckSpokenButton(spoken.questPlayButtons[row.questID], false, "Spoken Play outlived its externally hidden title")
        CheckSpokenButton(spoken.questPlayButtons[other.questID], true, "an externally hidden title masked its visible neighbor")
        row:Show()
        spoken:Update()
        CheckSpokenButton(spoken.questPlayButtons[row.questID], true, "Spoken's own refresh left a newly visible title muted")
        NativeRebuild()
        Check(PinVisible(), "the POI of a newly visible title did not recover its mouse and alpha values")
        spoken.contribution = row.questID
        spoken:Update()
    end
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
        if forever then
            Check(row:GetHeight() == nativeTitleHeight and contents.height == nativeTitleHeight + other:GetHeight(),
                "disabling skin did not restore the latest native quest height")
        end
        Check(contents.dirty == true, "disabling the skin cleared Blizzard's pending layout state")
        if spoken then
            CheckSpokenButton(spoken.questContributeButtons[row.questID], true, "disabling the skin kept Contribute suppressed")
        end
    end
end

local function Run(flavor)
    arg[2], arg[3] = flavor, "coverage"
    local H = assert(loadfile(root .. "/tools/tests/suite_skin_menu_transitions_contract.lua"))()
    arg[3] = nil
    local NS, Frame, Load = H.NS, H.Frame, H.Load
    local forever = NS.Client.isForever
    local compactCVar = forever and "1" or "0"
    local combat, lockdown, delayed, cvar, objectiveReads = false, false, {}, "1", 0
    NS.IsCombatLocked = function() return combat end
    InCombatLockdown = function() return lockdown end
    NS.DB.questLog = { layout = "blizzard" }
    NS.DB.skins = {}
    local opacity, color = 1, 0.4
    NS.Theme = { GetColor = function() return color, 0.6, 0.8, 1 end,
        GetMaterialOpacity = function() return opacity end }
    NS.L = setmetatable({}, { __index = function(_, key) return key end })
    local captionRefreshes = 0
    NS.WindowControls = { TrackFocus = Noop, Attach = Noop, DisableOwner = Noop,
        Refresh = function() captionRefreshes = captionRefreshes + 1 end }
    NS.Checkmarks.TrackControlTree = Noop
    NS.QuestText = { Activate = Noop, Deactivate = Noop }
    NS.Registry.NotifyListeners = function(domain)
        for owner, callback in pairs(H.listeners) do callback(owner, domain) end
    end
    local holdSkinJobs, skinJobs
    NS.Registry.QueueJob = function(job)
        if holdSkinJobs then skinJobs[job] = true else job() end
    end
    local function HoldSkinJobs()
        holdSkinJobs, skinJobs = true, {}
    end
    local function FlushSkinJobs()
        holdSkinJobs = false
        for job in pairs(skinJobs) do job() end
        skinJobs = nil
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
    Load("../MSUF_Suite/Appearance/Cosmetics.lua")
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
    local detailsOpen, objectiveCVarWrites = false, 0
    GetCVar = function(name) Check(name == "showQuestObjectivesInLog", "unexpected CVar read") return cvar end
    SetCVar = function(name, value)
        objectiveCVarWrites = objectiveCVarWrites + 1
        Check(not forever, detailsOpen and "Forever's Compact refreshed native quest details by writing the CVar"
            or "Forever's Compact wrote the native quest objectives CVar")
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
    local active, enumerations = {}, 0
    scroll.titleFramePool = { EnumerateActive = function()
        enumerations = enumerations + 1
        return pairs(active)
    end }
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
    local nativeRebuilds, nativePoolUpdate = 0, nil
    QuestLogQuests_Update = function()
        nativeRebuilds = nativeRebuilds + 1
        if nativePoolUpdate then nativePoolUpdate() end
    end
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
    -- OnLeave is authoritative even if the geometric mouse query still
    -- reports the row (for example when motion transfers to a child).
    row:Fire("OnLeave")
    Check(tooltip == nil and not row.plate.shown, "row leave retained tooltip/highlight while IsMouseOver stayed true")
    NS.Registry.NotifyListeners("theme")
    Check(not row.plate.shown, "theme repaint revived a departed row's highlight")
    row.mouseOver = false
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
    detailsOpen = true
    Check(NS.WorldMapQuests.SetLayout("compact") and cvar == compactCVar, "compact layout failed after native CVar edits")
    detailsOpen = false
    Check(#row.labels == 3, "compact quest columns missing")
    Check(nativeRebuilds == 2, "switching layouts invoked the native quest pool rebuild from addon code")
    -- A map change rebuilds the quest log inside WorldMapMixin:OnShow before
    -- Blizzard calls the protected reading emote on both clients.
    EventRegistry:TriggerEvent("WorldMapOnShow")
    holdSkinJobs, skinJobs = true, {}
    row.Text:SetText("New map quest")
    local beforeOpen = enumerations
    QuestLogQuests_Update()
    QuestLogQuests_Update()
    Check(enumerations == beforeOpen and row.labels[2]:GetText() == "Quest 1",
        flavor .. ": skin touched native quest rows while the map was still opening")
    EventRegistry:TriggerEvent("WorldMapOnShow")
    FlushSkinJobs()
    Check(enumerations == beforeOpen + 1 and row.labels[2]:GetText() == "New map quest",
        flavor .. ": deferred skin did not paint the latest quest list once")
    if NS.Client.isForever then
        HoldSkinJobs()
        local beforeSizeChange = captionRefreshes
        EventRegistry:TriggerEvent("WorldMapMaximized")
        EventRegistry:TriggerEvent("WorldMapMinimized")
        Check(captionRefreshes == beforeSizeChange, "native map size change refreshed window controls inline")
        searchSkins[search] = nil
        EventRegistry:TriggerEvent("QuestLog.SetDisplayMode")
        Check(searchSkins[search] == nil, "mode change painted before the native map finished opening")
        row.mouseOver = false
        row:Fire("OnLeave")
        row.mouseOver = true
        row:Fire("OnShow")
        Check(not row.plate.shown, "pooled quest row repainted inline during native OnShow")
        FlushSkinJobs()
        Check(captionRefreshes == beforeSizeChange + 1, "map size changes did not settle window controls once")
        Check(searchSkins[search] and not row.plate.shown, "deferred mode paint revived a departed row's highlight")
        row:Fire("OnEnter")
        Check(row.plate.shown, "native hover did not highlight the shown row")
    end
    row.Text:SetText("Quest 1")
    QuestLogQuests_Update()
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
    local visits = enumerations
    map.shown = false
    local hiddenRow = Acquire(3)
    for _ = 1, 25 do QuestLogQuests_Update() end
    Check(objectiveReads == reads, "hidden map queried compact objective progress")
    Check(enumerations == visits, "hidden map still enumerated native quest rows")
    Check(not hiddenRow.plate, "closed map still skinned a freshly acquired quest row")
    map.shown = true
    NS.WorldMapSkin:OnWorldMapShown()
    Check(enumerations == visits + 1, "reopened map did not catch up on quest-row styling")
    Check(hiddenRow.plate ~= nil, "reopened map did not skin a row acquired while hidden")
    active[hiddenRow] = nil
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
    Check(cvar == compactCVar, "unexpected native preference after Compact refreshed at the reload boundary")
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
    local menuCore = { HostBridge = { WithMenuHistory = function(label, key, callback)
        Check(label == "Quest list layout" and key == "suite:skin.questLog.layout", "gear used a different history setting")
        gearHistory = gearHistory + 1
        return callback()
    end } }
    NS.SuiteCore = function() return menuCore end
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
    Check(gearHistory == 1 and setting.get() == "compact" and cvar == compactCVar, "map gear did not switch to compact")
    radios.blizzard.select("blizzard")
    Check(gearHistory == 2 and setting.get() == "blizzard" and cvar == "1", "map gear did not restore Blizzard layout")
    setting.set("compact")
    Check(historyCount == 1 and historyKey == "suite:skin.questLog.layout" and cvar == compactCVar,
        "Skinning switch did not record exactly one menu history change")
    NS.DB.questLog = { layout = "blizzard" }
    NS.Registry.NotifyListeners("profile")
    Check(cvar == "1" and row.Text:IsShown(), "Undo/profile restore retained compact quest presentation")
    NS.DB.questLog = { layout = "compact" }
    NS.Registry.NotifyListeners("profile")
    Check(cvar == compactCVar and not row.Text:IsShown(), "Redo/profile restore did not restore compact presentation")
    local originalSetText, dispatch, reported = row.labels[1].SetText, NS.Safety.Dispatch, 0
    NS.Safety.Dispatch = function(callback, ...)
        local ok, value = pcall(callback, ...)
        if not ok then reported = reported + 1 return end
        return value
    end
    row.labels[1].SetText = function() error("contract: compact quest paint failed") end
    local oldLevel = row.info.level
    row.info.level = oldLevel + 1
    NS.WorldMapQuests.Refresh()
    row.info.level = oldLevel
    row.labels[1].SetText = originalSetText
    NS.WorldMapQuests.SetLayout("blizzard")
    Check(reported == 1 and cvar == "1" and row.Text:IsShown(), "paint error latched future layout restoration")
    NS.WorldMapQuests.SetLayout("compact")
    NS.Safety.Dispatch = dispatch
    -- Plain pooled rows keep Compact at the combat edge and after native
    -- progress updates, releases and fresh acquisitions. No full skin pass.
    local nativeAfter, combatTimers = C_Timer.After, {}
    C_Timer.After = function(delay, callback)
        Check(delay == 0, "combat quest paint scheduled a recurring timer")
        combatTimers[#combatTimers + 1] = callback
    end
    local function FlushCombatTimers()
        local batch = combatTimers
        combatTimers = {}
        for _, callback in ipairs(batch) do callback() end
    end
    local savedInfo, savedIndex, savedText = row.info, row.questLogIndex, row.Text:GetText()
    local writesBeforeCombat = objectiveCVarWrites
    combat, lockdown = true, false
    cvarEvents:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
    Check(not row.Text:IsShown() and row.labels[2]:IsShown(), "combat edge disabled Compact on an unprotected row")
    Check(not NS.WorldMapSkin.AttachCombatQuestLog(map, "worldMap"), "combat attach took over a different active owner")
    lockdown = true
    local combatRow
    nativePoolUpdate = function()
        row:Hide()
        row.info, row.questLogIndex = { questID = 4, title = "Combat quest", level = 21 }, 4
        row.Text:SetText("Combat quest")
        row:Show()
        combatRow = Acquire(17)
    end
    visits = enumerations
    QuestLogQuests_Update()
    nativePoolUpdate = nil
    for _ = 1, 25 do QuestLogQuests_Update() end
    Check(enumerations == visits and #combatTimers == 1 and #combatRow.labels == 0,
        "combat rebuilds painted inline or failed to coalesce")
    FlushCombatTimers()
    Check(enumerations == visits + 1 and not row.Text:IsShown() and row.labels[2]:GetText() == "Combat quest",
        "combat recycle retained an old quest or exposed the native title")
    Check(#combatRow.labels == 3 and not combatRow.Text:IsShown() and combatRow.labels[2]:GetText() == "Quest 17",
        "fresh combat row did not receive Compact columns")
    Check(next(delayed) == nil, "ordinary combat paint queued a redundant combat-exit refresh")
    local complete = C_QuestLog.IsComplete
    C_QuestLog.IsComplete = function(id) return id == 4 or complete(id) end
    QuestLogQuests_Update()
    FlushCombatTimers()
    Check(row.labels[3]:GetText() == "Ready", "combat quest progress did not refresh")
    C_QuestLog.IsComplete = complete
    Check(objectiveCVarWrites == writesBeforeCombat, "combat Compact wrote the native objective CVar")
    row:Fire("OnClick")
    row:Fire("OnEnter")
    row:Fire("OnLeave")
    Check(clicked == 2 and tooltip == nil and not row.plate.shown, "combat Compact broke native actions or hover leave")
    map.shown = false
    visits = enumerations
    QuestLogQuests_Update()
    Check(#combatTimers == 0 and enumerations == visits, "closed combat map queued or walked quest rows")
    map.shown = true
    NS.WorldMapSkin:OnWorldMapShown()
    Check(#combatTimers == 1, "combat map opening did not queue a Compact refresh")
    FlushCombatTimers()
    Check(row.labels[2]:IsShown() and not row.Text:IsShown(), "combat map opening lost Compact")
    combat, lockdown = false, false
    cvarEvents:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
    for key, callback in pairs(delayed) do delayed[key] = nil callback() end
    row.info, row.questLogIndex = savedInfo, savedIndex
    row.Text:SetText(savedText)
    active[combatRow] = nil
    combatRow:Hide()
    NS.WorldMapQuests.Refresh()
    local showTitle = row.Text.Show
    function row.Text:Show()
        Check(not lockdown or not row.protected, "compact restored a protected title during lockdown")
        showTitle(self)
    end
    row.protected = true
    function row:IsProtected() return self.protected, false end
    hiddenRow.protected, hiddenRow.IsProtected = true, row.IsProtected
    hiddenRow:Hide()
    combat, lockdown = true, true
    if cvarEvents.events.PLAYER_REGEN_DISABLED then cvarEvents:Fire("OnEvent", "PLAYER_REGEN_DISABLED") end
    Check(not row.Text:IsShown() and row.labels[2]:IsShown(), "late edge changed a protected row during lockdown")
    lockdown = false
    visits = enumerations
    if cvarEvents.events.PLAYER_REGEN_DISABLED then cvarEvents:Fire("OnEvent", "PLAYER_REGEN_DISABLED") end
    Check(row.Text:IsShown() and not row.labels[2]:IsShown(), "combat edge left native quest title hidden")
    Check(hiddenRow.Text:IsShown() and not hiddenRow.labels[2]:IsShown(), "combat edge left an inactive pool title hidden")
    Check(enumerations == visits, "combat edge enumerated the native quest pool")

    -- A Forever reload can prepare the skin before lockdown even when the player is in combat.
    local core = NS.SuiteCore()
    core.startingBeforeLockdown, combat = true, false
    local edgeWrites = objectiveCVarWrites
    Check(not NS.WorldMapQuests.SetLayout("blizzard"), "pre-lockdown startup changed the layout")
    NS.WorldMapQuests.Refresh()
    Check(objectiveCVarWrites == edgeWrites, "pre-lockdown startup wrote the native objective CVar")
    Check(row.Text:IsShown() and not row.labels[2]:IsShown(), "pre-lockdown startup hid the native quest title")
    core.startingBeforeLockdown, combat, lockdown = nil, true, true
    visits = enumerations
    nativePoolUpdate = function()
        row:Hide()
        row.info, row.questLogIndex = { questID = 4, title = "Combat pool quest", level = 21 }, 4
        row.Text:SetText("Combat pool quest")
        row:Show()
    end
    QuestLogQuests_Update()
    nativePoolUpdate = nil
    Check(row.Text:IsShown() and row.Text:GetText() == "Combat pool quest" and not row.labels[2]:IsShown(),
        "native combat recycle kept a stale or hidden title")
    row.protected = false
    NS.Registry.NotifyListeners("theme")
    Check(not row.Text:IsShown() and row.labels[2]:IsShown(), "unprotected combat refresh did not restore Compact")

    for _ = 1, 25 do QuestLogQuests_Update() end
    Check(enumerations == visits, "combat quest log update walked native rows inline")
    Check(not NS.WorldMapQuests.SetLayout("blizzard"), "combat changed quest layout")
    row.protected = true
    row.mouseOver = false
    row:Fire("OnLeave")
    Check(next(delayed) ~= nil, "protected hover did not defer combat paint")
    combat, lockdown = false, false
    if cvarEvents.events.PLAYER_REGEN_ENABLED then cvarEvents:Fire("OnEvent", "PLAYER_REGEN_ENABLED") end
    Check(not row.Text:IsShown() and row.labels[2]:IsShown() and row.labels[2]:GetText() == "Combat pool quest",
        "combat end did not reapply Compact to the current quest")
    for key, callback in pairs(delayed) do delayed[key] = nil callback() end
    Check(not row.plate.shown, "deferred hover did not clear after combat")
    map.shown, combat = false, true
    cvarEvents:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
    visits = enumerations
    combat = false
    cvarEvents:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
    Check(enumerations == visits and row.Text:IsShown(), "combat end repainted a closed quest log")
    map.shown = true
    NS.WorldMapSkin:OnWorldMapShown()
    Check(not row.Text:IsShown() and row.labels[2]:IsShown(), "reopened quest log did not restore Compact")
    local function CombatRebuild(rebuild, verify)
        combat, lockdown = true, true
        rebuild()
        verify()
        combat, lockdown = false, false
        for key, callback in pairs(delayed) do delayed[key] = nil callback() end
    end
    FlushCombatTimers()
    local checkReleasedFolds = CheckZoneFolds(NS, Frame, map, scroll, contents, row, active,
        HoldSkinJobs, FlushSkinJobs, External, CombatRebuild, cvarEvents)
    holdSkinJobs, skinJobs = true, {}
    QuestLogQuests_Update()
    NS.WorldMapSkin.Disable(map, "map-quests")
    visits = enumerations
    FlushSkinJobs()
    Check(enumerations == visits, "queued quest paint walked the released adapter")
    Check(not cvarEvents.events.PLAYER_REGEN_DISABLED and not cvarEvents.events.PLAYER_REGEN_ENABLED,
        "released quest log retained its combat events")
    checkReleasedFolds()
    Check(cvar == "1" and row.Text:IsShown() and row.HighlightTexture.alpha == 1,
        "disable did not restore native quest presentation")
    Check(not row.labels[1].shown and not row.plate.shown, "disable retained owned quest visuals")
    if forever then
        detailsOpen = true
        Check(NS.WorldMapSkin.Apply(map, "map-quests"), "Compact did not activate with native quest details open")
        Check(not row.Text:IsShown() and cvar == "1", "activating Compact disturbed native details or lost its columns")
        cvarEvents:Fire("OnEvent", "PLAYER_LOGOUT")
        Check(NS.WorldMapSkin.Disable(map, "map-quests"), "Compact did not release with native quest details open")
        Check(objectiveCVarWrites == 0 and cvar == "1", "Compact layout lifecycle wrote the native objective preference")
        checkReleasedFolds()
    end
    -- Cold load while the root map is implicitly protected: prepare only
    -- plain quest rows through the real adapter combat route.
    FlushCombatTimers()
    C_Timer.After = nativeAfter
    local coldMap, coldLog, coldQuests, coldScroll = Frame(UIParent), Frame(), Frame(), Frame()
    coldMap.QuestLog, coldLog.QuestsFrame, coldQuests.ScrollFrame = coldLog, coldQuests, coldScroll
    coldLog.parent, coldQuests.parent, coldScroll.parent = coldMap, coldLog, coldQuests
    function coldMap:IsProtected() return true, false end
    local coldContents = Frame(coldScroll)
    coldScroll.Contents, coldScroll.SearchBox = coldContents, Frame(coldScroll)
    coldScroll.UpdateBackground = Noop
    function coldContents:GetLayoutChildren() return 80 end
    function coldContents:LayoutChildren(height) return 304, height, false end
    function coldContents:CalculateFrameSize(width, height) return width, height end
    local coldObjective = Frame(coldContents)
    coldScroll.objectiveFramePool = { EnumerateActive = function() return pairs({ [coldObjective] = true }) end }
    local coldRow = Acquire(27)
    active[coldRow], coldRow.parent = nil, coldContents
    coldRow.height = 80
    function coldRow:SetHeight(height) self.height = height end
    function coldRow.Text:GetHeight() return 16 end
    local coldVisits = 0
    coldScroll.titleFramePool = { EnumerateActive = function()
        coldVisits = coldVisits + 1
        return pairs({ [coldRow] = true })
    end }
    local oldAfter, coldTimers = C_Timer.After, {}
    C_Timer.After = function(_, callback) coldTimers[#coldTimers + 1] = callback end
    local function FlushColdTimers()
        local batch = coldTimers
        coldTimers = {}
        for _, callback in ipairs(batch) do callback() end
    end
    _G.WorldMapFrame = coldMap
    NS.DB.skins.worldMap = true
    NS.DB.skins.blizzardWindows = false
    combat, lockdown = true, true
    local coldCVarWrites = objectiveCVarWrites
    local oldOrder = NS.Adapters.order
    NS.Adapters.order = { "worldMap" }
    NS.ForeverLegacyTree = { Apply = Noop }
    NS.Client.HasAddOn = function() return false end
    Check(not NS.Adapters.ApplyAll(), "combat startup applied the full map skin")
    Check(coldObjective:IsShown() and coldRow:GetHeight() == 80, "cold combat changed native layout inline")
    FlushColdTimers()
    Check(#coldRow.labels == 3 and coldRow.labels[2]:GetText() == "Quest 27" and not coldRow.Text:IsShown(),
        "first combat opening did not prepare Compact quest rows: " .. #coldRow.labels .. "/" .. NS.WorldMapQuests.GetLayout())
    Check(not coldObjective:IsShown() and coldRow:GetHeight() == 34,
        "cold combat Compact retained native objectives or blank objective space")
    Check(searchSkins[coldScroll.SearchBox] == nil and objectiveCVarWrites == coldCVarWrites,
        "cold combat applied map chrome or wrote the native objective CVar")
    combat, lockdown = false, false
    for key, callback in pairs(delayed) do delayed[key] = nil callback() end
    Check(searchSkins[coldScroll.SearchBox] ~= nil, "cold combat did not complete the full skin after combat")
    local afterApplyVisits = coldVisits
    QuestLogQuests_Update()
    Check(coldVisits > afterApplyVisits, "cold combat view did not adopt normal quest updates after combat")
    Check(NS.WorldMapSkin.Disable(coldMap, "worldMap"), "cold combat view did not release after combat")
    Check(coldRow.Text:IsShown() and not coldRow.labels[2]:IsShown(), "cold combat release retained Compact text")
    NS.DB.skins.worldMap = false
    combat, lockdown = true, true
    NS.Adapters.Apply("worldMap")
    Check(#coldTimers == 0 and coldRow.Text:IsShown(), "disabled map skin prepared a combat quest view")
    combat, lockdown = false, false
    for key, callback in pairs(delayed) do delayed[key] = nil callback() end
    FlushColdTimers()
    Check(coldRow.Text:IsShown() and not coldRow.labels[2]:IsShown(), "stale combat job revived a released view")
    C_Timer.After, NS.Adapters.order = oldAfter, oldOrder
    Check(#created > framesBefore, "contract did not exercise owned visual creation")
    _G.WorldMapFrame, _G.QuestLogQuests_Update, _G.QuestUtilsOverrides = nil, nil, nil
    _G.VoiceOver, _G.QuestScrollFrame = nil, nil
    Menu = oldMenu
end

Run("Mainline")
Run("Forever")
print("Suite map quest controls: " .. checks .. " checks passed")
