local root = assert(arg[1], "repository root required")
local module, combat, inside, grouped = nil, false, false, true
local secret, cooldown = {}, nil
local known = { [354464] = true, [777777] = true }
local scans, requests, mapTable = 0, 0, {}
local function Widget(_, _, parent)
    local w = { shown = true, attributes = {}, scripts = {}, points = {}, parent = parent }
    for _, key in ipairs({ "SetSize", "SetAllPoints", "SetWidth", "SetColorTexture",
        "RegisterForClicks", "SetDrawEdge", "SetClampedToScreen" }) do w[key] = function() end end
    function w:SetPoint(point, relative, relativePoint, x, y)
        self.points[#self.points + 1] = { point, relative, relativePoint, x, y }
    end
    function w:ClearAllPoints() self.points = {} end
    function w:IsVisible()
        return self.shown and (not self.parent or not self.parent.IsVisible or self.parent:IsVisible())
    end
    function w:GetEffectiveScale()
        return self.effectiveScale or self.parent and self.parent:GetEffectiveScale() or 1
    end
    function w:SetAttribute(key, value) self.attributes[key] = value end
    function w:SetFrameRef(key, value) self[key] = value end
    function w:SetScript(key, value) self.scripts[key] = value end
    function w:SetScale(value) self.scale = value end
    function w:SetTexture(value) self.texture = value end
    function w:SetText(value) self.text = value end
    function w:SetShown(value) if value then self:Show() else self:Hide() end end
    function w:Show()
        local was = self.shown; self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function w:Hide()
        local was = self.shown; self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function w:IsShown() return self.shown end
    function w:SetCooldownFromDurationObject(value) assert(value ~= nil); self.duration = value end
    function w:Clear() self.duration = nil end
    return w
end
UIParent, Minimap = Widget(), Widget()
UIParent.effectiveScale, Minimap.effectiveScale = .8, 1.2
Minimap.GetRight = function() return 1500 end
Minimap.GetBottom = function() return 600 end
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Flyout = 3 } }
RegisterStateDriver = function(frame, state, rule) frame.driver = rule end
UnregisterStateDriver = function(frame) frame.driver = nil end
IsInInstance = function() return inside, inside and "party" or "none" end
IsInGroup = function() return grouped end
C_SpellBook = { IsSpellKnown = function(id) return known[id] == true end,
    GetNumSpellBookSkillLines = function() scans = scans + 1; return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 2 } end,
    GetSpellBookItemInfo = function(slot) return { itemType = 3, actionID = slot } end }
GetFlyoutInfo = function() return "Flyout", nil, 2, true end
GetFlyoutSlotInfo = function(id, slot)
    if id == 1 then return slot == 1 and 354464 or 777777, nil, true end
    return 999999, nil, true
end
C_Spell = { GetSpellInfo = function(id) return { name = "Portal " .. id, iconID = 42 } end,
    GetSpellSubtext = function(id) return id == 354464 and "Test Dungeon" or "Second Dungeon" end,
    GetSpellCooldownDuration = function() return cooldown end }
C_ChallengeMode = { GetMapUIInfo = function() return nil end, GetMapTable = function() return mapTable end }
C_MythicPlus = { RequestMapInfo = function() requests = requests + 1 end }
C_LFGList = { GetSearchResultInfo = function() return { activityIDs = { 123 } } end,
    GetActivityInfoTable = function() return { categoryID = 2, shortName = "Test Dungeon" } end }
local S = { Install = function(_, m) module = m end, Public = function(v) return v ~= secret end,
    Finite = function(v) return type(v) == "number" end,
    PublicText = function(v) return type(v) == "string" and v ~= "" and v or nil end,
    Text = function(v) return v end, CreateFrame = Widget,
    CreateTexture = function(parent) return Widget(nil, nil, parent) end,
    CreateFontString = function(parent) return Widget(nil, nil, parent) end,
    SetStyledFont = function() end, GlobalFontPath = function() return "font" end,
    Config = function() return module.config end }
local NS = { Client = {}, IsCombatLocked = function() return combat end,
    DungeonPortalSet = { ALL = 1, SEASON = 2, CUSTOM = 3 },
    Dispatch = function(callback, ...) return callback(...) end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/DungeonPortals.lua"))("test", { NS = NS, Suite = S })
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local clock = Support.Clock()
module.active, module.config = true, { showMinimap = true, joinPopup = true, flyoutScale = 125 }
module.context = Support.ModuleTimers(root, S, NS)("dungeonPortals", module, { events = {},
    Event = function(self, event, fn) self.events[event] = fn end,
    RemoveEvent = function(self, event) self.events[event] = nil end })
local function Fire(event, ...) assert(module.context.events[event], event)(module, event, ...) end
module:Enable()
assert(#module.spells == 2 and #module.buttons == 2, "recognized native flyout must add new learned slots only")
assert(module.buttons[1].attributes.type == "spell" and module.buttons[1].attributes.spell == 354464)
assert(module.flyout.scale == 1.25 and module.toggle.shown and module.host.driver == "[combat] hide; show")
assert(module.toggle.attributes._onclick and module.toggle.flyout == module.flyout)
-- The protected toggle anchors to the Suite proxy, never to Minimap; the
-- proxy copies the minimap's bottom-right corner in UIParent units.
local anchor = module.toggle.points[1]
assert(anchor[1] == "BOTTOMRIGHT" and anchor[2] == module.proxy, "the toggle must anchor to the proxy")
local proxyPoint = module.proxy.points[1]
assert(proxyPoint[2] == UIParent and proxyPoint[4] == 1500 * 1.2 / .8 and proxyPoint[5] == 600 * 1.2 / .8,
    "the proxy did not copy the minimap corner")
for _, frame in ipairs({ module.toggle, module.flyout, module.proxy, module.host }) do
    for _, point in ipairs(frame.points) do assert(point[2] ~= Minimap, "a secure-family frame anchors to Minimap") end
end
-- Cooldowns are read only while the flyout or the suggestion is on screen.
assert(not module.context.events.SPELL_UPDATE_COOLDOWN, "cooldown events registered with the flyout closed")
cooldown = secret
module.flyout:Show()
assert(module.context.events.SPELL_UPDATE_COOLDOWN and module.buttons[1].cooldown.duration == secret,
    "opening the flyout did not read the cooldowns")
module.buttons[1].cooldown.duration = nil; Fire("SPELL_UPDATE_COOLDOWN")
assert(module.buttons[1].cooldown.duration == secret)
module.flyout:Hide()
assert(not module.context.events.SPELL_UPDATE_COOLDOWN, "closing the flyout kept the cooldown events")
Fire("LFG_LIST_JOINED_GROUP", 1)
assert(module.popup.shown and module.popup.cast.attributes.spell == 354464)
assert(module.context.events.SPELL_UPDATE_COOLDOWN and module.popup.cast.cooldown.duration == secret,
    "the suggestion did not read its cooldown")
-- The DataTexts portal menu reuses the kept list instead of a new scan.
local before = scans
assert(S.LearnedDungeonPortals() == module.spells and scans == before, "the export rescanned the spell book")
combat = true; Fire("PLAYER_REGEN_DISABLED")
Fire("LFG_LIST_JOINED_GROUP", 1)
assert(module.clearPopup, "combat must defer insecure changes behind secure hidden owner")
before = scans
combat = false; Fire("PLAYER_REGEN_ENABLED")
assert(not module.popup.shown and not module.context.events.SPELL_UPDATE_COOLDOWN)
assert(scans == before, "leaving combat rescanned an unchanged spell book")
-- A spell-book change in combat is read once after combat; a minimap move
-- in combat waits too.
combat = true; Fire("PLAYER_REGEN_DISABLED"); Fire("SPELLS_CHANGED")
Minimap.GetRight = function() return 1400 end
module.proxy.points = {}
assert(scans == before and module.dirty, "a spell-book change in combat was not deferred")
assert(S.LearnedDungeonPortals() ~= module.spells and scans == before + 1, "a stale list was exported")
combat = false; Fire("PLAYER_REGEN_ENABLED")
assert(scans == before + 2 and not module.dirty and module.proxy.points[1][4] == 1400 * 1.2 / .8,
    "the deferred rescan or minimap copy did not run after combat")
Minimap.GetRight = function() return 1300 end
module.watcher.scripts.OnSizeChanged()
assert(module.proxy.points[1][4] == 1300 * 1.2 / .8, "a minimap move did not move the proxy")
combat = true; Fire("PLAYER_REGEN_DISABLED")
Minimap.GetRight = function() return 1200 end
module.watcher.scripts.OnSizeChanged()
assert(module.proxy.points[1][4] == 1300 * 1.2 / .8 and module.placePending, "the proxy moved in combat")
before = scans
combat = false; Fire("PLAYER_REGEN_ENABLED")
assert(module.proxy.points[1][4] == 1200 * 1.2 / .8 and scans == before, "the deferred minimap copy did not run")
module.spells[2].destination = "Test Dungeon"
Fire("LFG_LIST_JOINED_GROUP", 1)
assert(not module.popup.shown, "ambiguous destinations must not suggest a spell")
C_ChallengeMode.GetMapUIInfo = function(id)
    assert(id == 375); return "Localized dungeon name", id, 1800, nil, nil, 2290
end
C_LFGList.GetActivityInfoTable = function() return { categoryID = 2, shortName = "Different localized label", mapID = 2290 } end
module:Refresh(); Fire("LFG_LIST_JOINED_GROUP", 1)
assert(module.popup.shown and module.popup.cast.attributes.spell == 354464,
    "verified native map IDs must work independently of localized text")
module.popup:Hide()
C_LFGList.GetActivityInfoTable = function() return { categoryID = 2, shortName = "Unknown", mapID = secret } end
Fire("LFG_LIST_JOINED_GROUP", 1)
assert(not module.popup.shown, "secret map IDs cannot drive portal selection")
C_ChallengeMode.GetMapUIInfo = function() return nil end
C_LFGList.GetActivityInfoTable = function() return { categoryID = 2, shortName = "Test Dungeon" } end
module:Refresh(); Fire("LFG_LIST_JOINED_GROUP", 1)
grouped = false; Fire("GROUP_ROSTER_UPDATE")
assert(not module.popup.shown)
grouped = true; inside = true; Fire("LFG_LIST_JOINED_GROUP", 1)
assert(not module.popup.shown, "joining inside a dungeon must not suggest a teleport")
inside = false; Fire("LFG_LIST_JOINED_GROUP", 1); Fire("PLAYER_ENTERING_WORLD")
assert(not module.popup.shown)
-- A burst of spell-book events reads the spell book once, on the next frame.
local burst = scans
for _ = 1, 5 do Fire("SPELLS_CHANGED") end
assert(scans == burst and module.dirty, "a spell-book burst was read inside the events")
clock.Frame()
assert(scans == burst + 1 and not module.dirty, "a spell-book burst was not read exactly once")
known = {}; Fire("SPELLS_CHANGED"); clock.Frame()
assert(not module.toggle.shown and not module.flyout.shown and not module.buttons[1].shown)
-- Every current season destination must resolve by the native map, without
-- English dungeon text or a spellbook flyout discovering an unrelated seed.
local season = { [1286801] = 584, [1286804] = 585, [1286807] = 586, [1286809] = 587,
    [1286812] = 588, [1286828] = 250, [1286831] = 249, [393256] = 399 }
for spell, challenge in pairs(season) do
    known = { [spell] = true }
    C_ChallengeMode.GetMapUIInfo = function(id)
        assert(id == challenge); return "Native dungeon", id, 1800, nil, nil, 9000 + id
    end
    C_LFGList.GetActivityInfoTable = function()
        return { categoryID = 2, shortName = "Different listing name", mapID = 9000 + challenge }
    end
    Fire("SPELLS_CHANGED"); clock.Frame(); Fire("LFG_LIST_JOINED_GROUP", 1)
    assert(#module.spells == 1 and module.popup.shown and module.popup.cast.attributes.spell == spell,
        "every learned Season 2 portal must use its verified destination")
end
-- Portal sets. The current season is the client's Mythic+ list, so it needs
-- no Suite data each season: a portal without a verified destination joins
-- it by the season dungeon's native name in its native description, and a
-- new expansion's flyout counts once it holds such a portal. Names compare
-- in lower case without a leading article; the longest name wins.
local SET = NS.DungeonPortalSet
assert(requests == 1, "an unknown season must be requested exactly once per session")
local names = { [557] = "Windrunner Spire", [161] = "Skyreach", [501] = "The Stonevault",
    [9001] = "Nexus Prime", [9002] = "The Voidspire Depths", [9003] = "Nexus" }
C_ChallengeMode.GetMapUIInfo = function(id) return names[id] or "Dungeon " .. id, id, 1800, nil, nil, 7000 + id end
local descriptions = { [888888] = "Teleport to the entrance of Nexus Prime.",
    [900001] = "Teleport to the entrance of Voidspire Depths.", [900002] = "Summons a loyal demon." }
local described = 0
C_Spell.GetSpellDescription = function(id)
    described = described + 1
    return descriptions[id] or ""
end
-- The older Skyreach portal sorts first, so the season replaces it by the newer spell.
C_Spell.GetSpellInfo = function(id) return { name = id == 159898 and "A Skyreach path" or "Portal " .. id, iconID = 42 } end
GetFlyoutSlotInfo = function(id, slot)
    if id == 1 then return slot == 1 and 1254400 or 888888, nil, true end
    return slot == 1 and 900001 or 900002, nil, true
end
known = { [1254400] = true, [1254557] = true, [159898] = true, [445269] = true, [888888] = true, [900001] = true }
mapTable = {}
module.config.portalSet = SET.ALL
Fire("SPELLS_CHANGED"); clock.Frame()
assert(#module.spells == 5 and module.shown == module.spells and #module.buttons >= 5 and module.buttons[5].shown,
    "all learned portals must be listed; an unseeded flyout waits for the season")
module.config.portalSet = SET.SEASON
module:Refresh()
assert(module.shown == module.spells and S.LearnedDungeonPortals() == module.shown,
    "a season the client has not sent must list every learned portal")
before = scans
mapTable = { 557, 161, 9001, 9002, 9003 }
Fire("CHALLENGE_MODE_MAPS_UPDATE")
assert(scans == before, "the season arrival was read inside the event")
clock.Frame()
assert(scans == before + 1 and #module.spells == 6, "a new season must be read once and find the new expansion flyout")
local listed = {}
for _, spell in ipairs(module.shown) do listed[spell.id] = true end
assert(#module.shown == 4 and listed[1254400] and listed[1254557] and listed[888888] and listed[900001]
    and not listed[159898], "the season must list its dungeons once each, newer spell first, matched by native names")
assert(module.buttons[4].shown and not module.buttons[5].shown and module.buttons[1].attributes.spell == module.shown[1].id)
assert(S.LearnedDungeonPortals() == module.shown and scans == before + 1, "the DataText menu must reuse the season list")
Fire("CHALLENGE_MODE_MAPS_UPDATE"); clock.Frame()
assert(scans == before + 1, "an unchanged season was read again")
-- Descriptions are read once per season, not on every spell-book read.
local reads = described
Fire("SPELLS_CHANGED"); clock.Frame()
assert(scans == before + 2 and described == reads and #module.shown == 4, "a rescan read the descriptions again")
-- A season change in combat waits for the combat end.
combat = true; Fire("PLAYER_REGEN_DISABLED")
mapTable = { 557, 161, 9001 }
Fire("CHALLENGE_MODE_MAPS_UPDATE"); clock.Frame()
assert(scans == before + 2 and module.dirty and #module.shown == 4, "a season change was read in combat")
combat = false; Fire("PLAYER_REGEN_ENABLED")
assert(scans == before + 3 and not module.dirty and #module.spells == 5 and #module.shown == 3,
    "the season change was not read after combat")
mapTable = { 557, 161, 9001, 9002, 9003 }
Fire("CHALLENGE_MODE_MAPS_UPDATE"); clock.Frame()
assert(#module.spells == 6 and #module.shown == 4)
-- Group suggestions keep every learned portal, also outside the shown set.
module.popup:Hide()
C_LFGList.GetActivityInfoTable = function() return { categoryID = 2, shortName = "Unlisted", mapID = 7501 } end
Fire("LFG_LIST_JOINED_GROUP", 1)
assert(module.popup.shown and module.popup.cast.attributes.spell == 445269, "the suggestion must use every learned portal")
module.popup:Hide()
module.config.portalSet, module.config.customPortals = SET.CUSTOM, "445269,900002,1254400"
module:Refresh()
assert(#module.shown == 2 and module.shown[1].id == 1254400 and module.shown[2].id == 445269,
    "the custom set must list its learned portals by name")
module.config.customPortals = ""
module:Refresh()
assert(module.shown == module.spells, "an empty custom set must list every learned portal")
-- The options picker: learned and not-learned portals with their season.
local groups, seasonKnown = S.DungeonPortalChoices()
local byId = {}
for name, group in pairs(groups) do
    for index, choice in ipairs(group) do
        byId[choice.id] = choice
        choice.group = name
        assert(index == 1 or group[index - 1].label <= choice.label, "picker groups must be sorted by label")
    end
end
assert(byId[888888].group == "season" and byId[445269].group == "learned" and byId[900002].group == "later")
assert(byId[1254557].label == "Skyreach (Portal 1254557)" and byId[159898].label == "Skyreach (A Skyreach path)",
    "two portals to one dungeon must keep their spell names")
assert(byId[888888].map == 9001 and byId[900001].map == 9002, "the longest quoted dungeon name must win")
assert(byId[1254557].seasonStart and not byId[159898].seasonStart and byId[888888].seasonStart
    and not byId[445269].seasonStart, "the season start must pick one portal per dungeon, the newer learned spell")
assert(seasonKnown and byId[888888].season and byId[888888].learned and byId[159898].season,
    "the picker must mark learned season portals")
assert(byId[900002] and not byId[900002].learned and not byId[900002].season, "unlearned flyout portals must be offered")
assert(byId[1286801] and not byId[1286801].learned and not byId[1286801].season
    and byId[1286801].destination == "Dungeon 584" and not byId[445269].season)
-- A secret season list counts as unknown and is not requested again.
mapTable = secret
module.config.portalSet = SET.SEASON
module:Refresh()
assert(module.shown == module.spells and requests == 1, "a secret season must list every learned portal")
module:Disable(); assert(not module.host.shown and not module.host.driver)
print("Dungeon portals: learned native flyouts, secure attributes, cooldown sink, exact destination, portal sets and lifecycle passed")
