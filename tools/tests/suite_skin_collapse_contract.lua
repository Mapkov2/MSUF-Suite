-- Real providers, native layout callbacks and immediately recycled rows.
local root = assert(arg[1])
local mode = arg[3]
arg[3] = "coverage"
local H = assert(loadfile(root .. "/tools/tests/suite_skin_menu_transitions_contract.lua"))()
arg[3] = mode
local NS, Frame = H.NS, H.Frame
local checks = 0
local function Check(value, message) checks = checks + 1; assert(value, message) end
local function Node(data, parent, size)
    local node = { data = data, parent = parent, size = size or 0 }
    function node:GetData() return self.data end
    function node:GetParent() return self.parent end
    function node:GetSize() return self.size end
    function node:IsCollapsed() return self.collapsed end
    return node
end
local function List(parent, tree)
    local box = Frame(parent, true)
    box.provider, box.offset, box.rows = {}, 0, {}
    if tree then function box.provider:GetRootNode() return self end end
    function box:GetDataProvider() return self.provider end
    function box:GetDerivedScrollOffset() return self.offset end
    function box:ForEachFrame(callback) for _, row in ipairs(self.rows) do callback(row) end end
    return box
end
local function Row(box, node, top, label)
    local row = Frame(box, true)
    row.node, row.top, row.height = node, top, 20
    function row:GetElementData() return self.node end
    row.label = row:CreateFontString()
    row.label.kind, row.label.text = "FontString", label or "Native label"
    function row:GetRegions() return self.label end
    return row
end
local box = List(UIParent, true)
local a, b = Node({ isCategory = true }, nil, 2), Node({ isParent = true }, nil, 1)
local child, tail = Node({ entryID = 1 }, a), Node({ entryID = 2 }, b)
local header, entry, second, last = Row(box, a, 400), Row(box, child, 380), Row(box, b, 360), Row(box, tail, 340)
header.StateIcon, second.CollapseIcon = Frame(header), Frame(second)
box.rows = { header, entry, second, last }
NS.GenericWindows.trackContent(box, "generic-tree")
a.collapsed, b.collapsed = true, true
entry:Hide(); entry.top, entry.node = nil, nil
last:Hide(); last.top, last.node = nil, nil
box:TriggerEvent("released", entry, child)
box:TriggerEvent("released", last, tail)
second.top, box.rows = 380, { header, second }
box:TriggerEvent("layout")
local state = NS.AddonListMotion.scrollStates[box]
Check(state and state.records[second].group and state.records[second].group:IsPlaying(),
    "generic native tree categories did not collapse like AddOns")
Check(state.records[header].arrowGroup:IsPlaying(), "generic header glyph did not animate")
local firstGhost, lastGhost = state.records[entry].ghost, state.records[last].ghost
Check(firstGhost.group:IsPlaying() and lastGhost.group:IsPlaying(), "CollapseAll lost a closing branch")
Check(firstGhost.clip ~= lastGhost.clip, "different branches share a destructive clip")
Check(firstGhost.fonts[1].text == "Native label", "native recycled row lost its cached appearance")
Check(not NS.ContentMotion.records[box], "tree toggle also started a result fade")
-- Recycling, scrolling, filtering and geometry changes are not disclosures.
firstGhost.group:Finish(); lastGhost.group:Finish()
local plays = state.records[second].group.plays
box.offset = 20
second.top = 400
box:TriggerEvent("layout")
Check(state.records[second].group.plays == plays, "ordinary scrolling started collapse motion")
box.provider = { GetRootNode = function(self) return self end }
box:TriggerEvent("layout")
Check(state.records[second].group.plays == plays, "provider replacement invented a tree toggle")
NS.GenericWindows.releaseContent("generic-tree")
Check(not state.active and not state.registered, "generic owner release retained observers")
-- Settings replaces initializer tables and its provider on every disclosure.
local settings = Frame(UIParent, true)
function settings:CreateCategories() end
function settings:GetCategorySet() return 1 end
local flat = List(settings)
local category = { expanded = true }
function category:IsExpanded() return self.expanded end
function category:GetSubcategories() return { 1 } end
function category:GetParentCategory() end
local sibling = { expanded = true, IsExpanded = category.IsExpanded, GetSubcategories = category.GetSubcategories,
    GetParentCategory = category.GetParentCategory }
local parentRow = Row(flat, { data = { category = category } }, 400)
local childCategory = { IsExpanded = category.IsExpanded, expanded = true, GetSubcategories = function() return {} end,
    GetParentCategory = function() return category end }
local childRow = Row(flat, { data = { category = childCategory } }, 380)
local tailRow = Row(flat, { data = { category = sibling } }, 360)
parentRow.Toggle = Frame(parentRow)
flat.rows = { parentRow, childRow, tailRow }
NS.GenericWindows.trackContent(flat, "settings-collapse")
category.expanded = false
flat:TriggerEvent("released", childRow, childRow.node)
flat.provider = {}
parentRow.node, tailRow.node = { data = { category = category } }, { data = { category = sibling } }
tailRow.top, flat.rows = 380, { parentRow, tailRow }
flat:TriggerEvent("layout")
local linear = NS.AddonListMotion.scrollStates[flat]
Check(linear and linear.records[tailRow].group and linear.records[tailRow].group:IsPlaying(),
    "Settings provider rebuild lost its accordion transition")
Check(linear.records[childRow].ghost.group:IsPlaying(), "Settings closed children disappeared without a transition")
Check(not NS.ContentMotion.records[flat], "Settings disclosure received a second full-list fade")
-- One native observer group survives independent adopters until the last lease.
NS.GenericWindows.trackContent(flat, "second-settings-owner")
NS.GenericWindows.releaseContent("settings-collapse")
Check(linear.active, "one owner disabled another owner's collapse animation")
NS.GenericWindows.releaseContent("second-settings-owner")
Check(not linear.active and not linear.registered, "last owner retained collapse callbacks")
Check(H.ForeignWrites() == 0, "collapse motion changed native alpha, anchors or ownership")
-- Each verified linear schema runs through the real result dispatcher.
for _, kind in ipairs({ "reputation", "skills", "currency", "achievement", "dungeon" }) do
    local panel = Frame(UIParent, true)
    local names = { reputation = "ReputationFrame", skills = "SkillsFrame", currency = "TokenFrame",
        achievement = "AchievementFrameCategories", dungeon = "LFDQueueFrame" }
    function panel:GetName() return names[kind] end
    local list = List(panel)
    local function Data(id, header, collapsed)
        if kind == "achievement" then return { id = id, parent = header and true or 100, collapsed = collapsed } end
        if kind == "dungeon" then return { dungeonID = id } end
        local data = { isHeader = header, name = "Entry" .. id, isCollapsed = collapsed, isHeaderExpanded = not collapsed,
            currencyListDepth = header and 0 or 1 }
        data[({ reputation = "factionID", skills = "skillID", currency = "currencyID" })[kind]] = id
        return data
    end
    local first, child, following = Row(list, Data(100, true, false), 400), Row(list, Data(101, false), 380),
        Row(list, Data(200, true, false), 360)
    first.ToggleCollapseButton = Frame(first)
    if kind == "dungeon" then
        first.expandOrCollapseButton, following.expandOrCollapseButton = Frame(first), Frame(following)
        child.expandOrCollapseButton = Frame(child); child.expandOrCollapseButton:Hide()
        first.isCollapsed, following.isCollapsed = false, false
    end
    list.rows = { first, child, following }
    NS.GenericWindows.trackContent(list, kind)
    list:TriggerEvent("released", child, child.node)
    first.node, first.isCollapsed = Data(100, true, true), true
    following.node, following.top, list.rows, list.provider = Data(200, true, false), 380, { first, following }, {}
    list:TriggerEvent("layout")
    local record = NS.AddonListMotion.scrollStates[list]
    Check(record and record.records[following].group and record.records[following].group:IsPlaying(), kind .. " list did not collapse")
    Check(record.records[child].ghost.group:IsPlaying(), kind .. " closing copy was lost")
    Check(not NS.ContentMotion.records[list], kind .. " collapse multiplied the full result fade")
    NS.GenericWindows.releaseContent(kind)
end

-- Legacy ScrollFrames rebuild complete pools before their post-layout hook.
NS.GenericWindows.SetCollapseMotionProvider = function(track) NS.GenericWindows.trackCollapse = track end
NS.AdapterKit = { Path = function(object, ...)
    for index = 1, select("#", ...) do object = NS.Safety.Field(object, select(index, ...)) end
    return object
end }
hooksecurefunc = function(target, key, callback)
    if type(target) == "string" then callback, key, target = key, target, _G end
    local native = assert(target[key])
    target[key] = function(...) native(...); callback(...) end
end
H.Load("Rendering/CollapseCollectionRows.lua")
H.Load("Rendering/CollapseCollections.lua")
local quest = Frame(UIParent, true)
quest.kind = "ScrollFrame"
local h = Frame(quest, true)
h.sortKey, h.isCollapsed, h.top = "zone-a", false, 400
local title = Row(quest, {}, 380)
title.info = { questID = 21, header = { headerSortKey = "zone-a" } }
local following = Frame(quest, true)
following.sortKey, following.isCollapsed, following.top = "zone-b", false, 360
local function NativePool(rows)
    local pool = { rows = rows }
    function pool:EnumerateActive()
        local index = 0
        return function() index = index + 1; return self.rows[index] end
    end
    return pool
end
quest.headerFramePool, quest.titleFramePool = NativePool({ h, following }), NativePool({ title })
QuestLogQuests_Update = function()
    title:Hide(); title.top, title.info = nil, nil
    quest.titleFramePool.rows = {}
    h.isCollapsed, following.top = true, 380
end
NS.CollapseCollections.Track(quest, "quest-pool")
QuestLogQuests_Update()
local questState = NS.AddonListMotion.scrollStates[quest]
Check(questState and questState.records[following].group:IsPlaying(), "Quest pool completion did not animate")
Check(questState.records[title].ghost.group:IsPlaying(), "Quest pool reset erased its closing copy")
quest:Fire("OnVerticalScroll", 20)
Check(not questState.records[title].ghost.group:IsPlaying() and not questState.records[following].group:IsPlaying(),
    "legacy scrolling retained closing copies or row travel")
NS.AddonListMotion.DisableOwner("quest-pool")
local nativeSection = Frame(UIParent, true)
nativeSection.myID, nativeSection.parentID, nativeSection.expanded = 27123, 1409, true
Check(NS.CollapseCollectionRows.Encounter({}, nativeSection) == "header:27123",
    "native journal myID section was not recognized")
local alphaList = List(UIParent, true)
function alphaList:GetEffectiveAlpha() return 1 end
local alphaHeader, alphaChild = Node({}, nil, 1), Node({})
alphaChild.parent = alphaHeader
local ah, ac = Row(alphaList, alphaHeader, 400), Row(alphaList, alphaChild, 380)
ac.alpha = 0.5
function ac.label:GetEffectiveAlpha() return 0.5 end
alphaList.rows = { ah, ac }
NS.GenericWindows.trackContent(alphaList, "alpha-collapse")
alphaHeader.collapsed = true
alphaList:TriggerEvent("released", ac, alphaChild)
alphaList.rows = { ah }
alphaList:TriggerEvent("layout")
local alphaCopy = NS.AddonListMotion.scrollStates[alphaList].records[ac].ghost
Check(math.abs(alphaCopy.fonts[1].alpha * alphaCopy.alpha.FromAlpha - 0.5) < 0.001,
    "closing copy compounded native row opacity")
NS.GenericWindows.releaseContent("alpha-collapse")

local function CheckCompositor()
    local probes = 0
    local proxy = Frame(UIParent, true)
    proxy.AttachTexture, proxy.AttachFontString, proxy.AttachFrame, proxy.AttachTemplate = function() end, function() end, function() end, function() end
    proxy.CreateAnimationGroup = nil
    setmetatable(proxy, { __index = function(_, key) if key == "CreateAnimationGroup" then probes = probes + 1 end end })
    local list = List(UIParent, true)
    list.rows = { proxy }
    NS.GenericWindows.trackContent(list, "compositor-collapse")
    list:TriggerEvent("layout")
    Check(probes == 0, "compositor row indexed a disallowed animation method")
    Check(NS.CollapseRows.Arrow({ StateIcon = proxy }) == nil and probes == 0,
        "compositor glyph indexed a disallowed animation method")
    NS.GenericWindows.releaseContent("compositor-collapse")
end
CheckCompositor()

local function CheckRetargetAndCache()
    local list = List(UIParent, true)
    local parent, child, following = Node({}, nil, 1), Node({}), Node({})
    child.parent = parent
    local h, c, tail = Row(list, parent, 400), Row(list, child, 380, "old label"), Row(list, following, 360)
    list.rows = { h, c, tail }
    NS.GenericWindows.trackContent(list, "result-collapse")
    c.label.text = "new provider label"
    list.provider = { GetRootNode = function(self) return self end }
    list:TriggerEvent("layout")
    local record = NS.AddonListMotion.scrollStates[list].records[c]
    Check(record.ghost.fonts[1].text == "new provider label", "provider replacement retained stale closing text")
    c.label.text = "updated native label"
    list:TriggerEvent("initialized", c)
    list:TriggerEvent("layout")
    Check(record.ghost.fonts[1].text == "updated native label", "native row initialization retained stale closing text")
    Check(NS.ContentMotion.records[list].group:IsPlaying(), "provider replacement fixture did not start its result fade")
    parent.collapsed = true
    c:Hide(); c.top, c.node = nil, nil
    list:TriggerEvent("released", c, child)
    tail.top, list.rows = 380, { h, tail }
    list:TriggerEvent("layout")
    Check(not NS.ContentMotion.records[list].group:IsPlaying(), "same-provider collapse retained a previous full-list fade")
    Check(record.ghost.fonts[1].text == "updated native label" and record.ghost.group:IsPlaying(),
        "collapse lost the refreshed native row snapshot")
    NS.GenericWindows.releaseContent("result-collapse")
end
CheckRetargetAndCache()

local function CheckJournal()
    local journal = Frame(UIParent, true)
    journal.encounterID = 91
    local scroll = Frame(journal, true)
    local encounter = { info = { detailsScroll = scroll }, usedHeaders = {} }
    journal.encounter = encounter
    local first, second = Frame(scroll, true), Frame(scroll, true)
    first.myID, first.parentID, first.expanded, first.top = 510, 0, true, 400
    second.myID, second.parentID, second.expanded, second.top = 520, 0, true, 340
    first.description, second.description = first:CreateFontString(), second:CreateFontString()
    first.description.kind, first.description.top, first.description.text = "FontString", 380, "first body"
    second.description.kind, second.description.top, second.description.text = "FontString", 320, "second body"
    function first:GetRegions() return self.description end
    function second:GetRegions() return self.description end
    encounter.usedHeaders = { first, second }
    EncounterJournal_ToggleHeaders = function(_, doNotShift)
        if doNotShift then first.expanded = false; first.description:Hide(); return end
        EncounterJournal_ToggleHeaders(first, true)
        second.top, second.description.top = 380, 360
    end
    EncounterJournal_DisplayEncounter = function() end
    NS.CollapseCollections.TrackRoot(journal, "native-journal")
    EncounterJournal_ToggleHeaders(first)
    local state = NS.AddonListMotion.scrollStates[scroll]
    Check(state.records[second].group and state.records[second].group:IsPlaying(),
        "recursive journal callback consumed collapse before final native layout")
    Check(not state.records[second.description].group or not state.records[second.description].group:IsPlaying(),
        "journal body inherited the header translation twice")
    Check(state.records[first.description].ghost.group:IsPlaying(), "journal closing body was not retained")
    local copy = state.records[second].ghost
    Check(not copy or copy.fontCount == 0, "journal header duplicated its separately tracked description")
    state.records[second].group.progress = 0.5
    local body = state.records[second.description]
    local expectedTop = body.ghost.top + state.records[second].offset * 0.5
    second.description:Hide()
    Check(body.ghost.displayTop == expectedTop, "closing journal body lost its moving parent's rendered offset")
    NS.AddonListMotion.DisableOwner("native-journal")
end
CheckJournal()

local function CheckChannels()
    local panel, list = Frame(UIParent, true), Frame(UIParent, true)
    panel.ChannelList = list
    list.headerButtonPool, list.communityChannelButtonPool = {}, {}
    list.collapsed = {}
    function list:IsCollapsed(category) return self.collapsed[category] end
    local first, child, following = Row(list, {}, 400), Row(list, {}, 380), Row(list, {}, 360)
    function first:GetCategory() return "public" end
    function first:IsHeader() return true end
    function child:GetCategory() return "public" end
    function child:GetChannelID() return 1 end
    function following:GetCategory() return "voice" end
    function following:IsHeader() return true end
    list.buttons = { first, child, following }
    function list:Update()
        self.collapsed.public = true
        child:Hide(); child.top = nil
        following.top, self.buttons = 380, { first, following }
    end
    NS.CollapseCollections.TrackRoot(panel, "native-channels")
    list:Update()
    local state = NS.AddonListMotion.scrollStates[list]
    Check(state and state.records[following].group:IsPlaying(), "native channel completion did not animate")
    Check(state.records[child].ghost.group:IsPlaying(), "native channel rebuild erased the closing row")
    NS.AddonListMotion.DisableOwner("native-channels")
end
CheckChannels()

local function CheckLifecycleAndBudget()
    local list = List(UIParent, true)
    local hiddenHeader = Node({}, nil, 2)
    local child, following = Node({}, hiddenHeader), Node({})
    local c, tail = Row(list, child, 400), Row(list, following, 380)
    list.rows = { c, tail }
    NS.GenericWindows.trackContent(list, "offscreen-collapse")
    local state = NS.AddonListMotion.scrollStates[list]
    hiddenHeader.collapsed = true
    c:Hide(); c.top, c.node = nil, nil
    list:TriggerEvent("released", c, child)
    list.rows, tail.top = { tail }, 400
    list:TriggerEvent("layout")
    Check(state.records[tail].group and state.records[tail].group:IsPlaying() and state.records[c].ghost.group:IsPlaying(),
        "offscreen expanded ancestor was missing from the collapse snapshot")
    list:Hide()
    Check(not state.records[tail].group:IsPlaying() and not state.records[c].ghost.group:IsPlaying(),
        "hidden collection retained finite motion")
    list:Show(); list:Fire("OnShow")
    Check(state.hadSnapshot, "reopened collection did not rebuild its first snapshot")
    local frames, groups = #H.frames, #H.groups
    for _ = 1, 50 do list:TriggerEvent("layout") end
    Check(#H.frames == frames and #H.groups == groups, "warm native layouts allocate new render objects")
    function list:GetView() return nil end
    function list:GetDataProvider() error("uninitialized native view was read") end
    list:TriggerEvent("layout")
    Check(not state.hadSnapshot, "view teardown retained an initialized collapse snapshot")
    NS.GenericWindows.releaseContent("offscreen-collapse")
    for _, option in ipairs({ "menuAnimations", "reduceMotion", "combat" }) do
        local other = List(UIParent, true)
        local parent, child = Node({}, nil, 1), Node({})
        child.parent = parent
        other.rows = { Row(other, parent, 400), Row(other, child, 380) }
        if option == "combat" then NS.Motion.combat = true else NS.DB.theme[option] = option == "reduceMotion" end
        frames, groups = #H.frames, #H.groups
        NS.GenericWindows.trackContent(other, option)
        Check(#H.frames == frames and #H.groups == groups, option .. " created collapse render objects while disabled")
        NS.GenericWindows.releaseContent(option)
        NS.Motion.combat, NS.DB.theme.menuAnimations, NS.DB.theme.reduceMotion = false, nil, nil
    end
end
CheckLifecycleAndBudget()

local function CheckOpeningAndTextures()
    local list = List(UIParent, true)
    local parent, child, nextNode = Node({}, nil, 1), Node({}), Node({})
    child.parent, parent.collapsed = parent, true
    local h, c, tail = Row(list, parent, 400), Row(list, child, 380), Row(list, nextNode, 380)
    local texture = c:CreateTexture()
    texture.kind, texture.texture = "Texture", 123
    function texture:GetTexCoord() return 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8 end
    function c:GetRegions() return self.label, texture end
    local nativeCreate = Frame
    local oldCreate = CreateFrame
    CreateFrame = function()
        local frame = nativeCreate()
        local createTexture = frame.CreateTexture
        function frame:CreateTexture()
            local result = createTexture(self)
            function result:SetTexCoord(...) self.coords = { ... } end
            return result
        end
        return frame
    end
    list.rows = { h, tail }
    NS.GenericWindows.trackContent(list, "opening-tree")
    parent.collapsed, tail.top, list.rows = false, 360, { h, c, tail }
    list:TriggerEvent("layout")
    local state = NS.AddonListMotion.scrollStates[list]
    local record = state.records[c]
    Check(record.group and record.group:IsPlaying() and record.alpha.ToAlpha == 0 and record.group.reverse,
        "native tree opening did not reveal children from the header")
    Check(state.records[tail].group:IsPlaying(), "opening did not move following native rows")
    local coords = record.ghost.textures[1].coords
    Check(coords and #coords == 8 and coords[3] == 0.3 and coords[8] == 0.8, "native rotated texture coordinates were not preserved")
    record.group:Finish(); state.records[tail].group:Finish()
    local frames, groups = #H.frames, #H.groups
    for _ = 1, 5 do
        parent.collapsed = true
        list:TriggerEvent("released", c, child)
        list.rows, tail.top = { h, tail }, 380
        list:TriggerEvent("layout")
        record.ghost.group:Finish(); state.records[tail].group:Finish()
        parent.collapsed, list.rows, tail.top = false, { h, c, tail }, 360
        list:TriggerEvent("layout")
        record.group:Finish(); state.records[tail].group:Finish()
    end
    Check(#H.frames == frames and #H.groups == groups, "warm repeated disclosures allocate new render objects")
    NS.GenericWindows.releaseContent("opening-tree")
    CreateFrame = oldCreate
end
CheckOpeningAndTextures()

Check(H.ForeignWrites() == 0, "extended collapse paths changed native anchors or alpha")

print("Suite Blizzard collapse (" .. (arg[2] or "Mainline") .. "): " .. checks .. " checks passed")
