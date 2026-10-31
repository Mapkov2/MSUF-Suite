local root = assert(arg[1])
local F = dofile(root .. "/tools/tests/comfort_fixture.lua")
local e = F.New(root, false)
UIParent = e.Frame()
local results = { [1] = { partyGUID = "party1", activityIDs = { 20 } }, [2] = { partyGUID = "party2", activityIDs = { 21 } } }
local mythic = true
C_LFGList = { GetSearchResultInfo = function(id) return results[id] end,
    GetActivityInfoTable = function(id) return { isMythicPlusActivity = id == 20 and mythic } end,
    GetApplications = function() return {} end }
e:Load("MSUF_Suite_QualityOfLife/GroupFinderStatistics.lua")
local stats = e.P.GroupFinderStatistics
assert(stats.Changed(1, "applied", "none")); assert(not stats.Changed(1, "applied", "none"))
assert(stats.Changed(1, "invited", "applied")); assert(not stats.Changed(1, "invited", "applied"))
assert(stats.Changed(1, "invitedeclined", "invited"), "declining an invite must finish the application")
for scope = 1, 3 do
    local d = stats.Data(scope)
    assert(d.applied == 1 and d.invited == 1 and d.cancelled == 1, "all scopes must count each transition once")
end
assert(stats.applications[1].terminal, "invite decline is terminal")
assert(not stats.Changed(2, "applied", "none"), "non-Mythic+ must not affect statistics")
assert(not stats.Changed(e.secret, "applied", "none"), "restricted identifiers cannot index records")
results[1].partyGUID = "newparty"
assert(stats.Changed(1, "applied", "none"), "reused result IDs can start a different application")
stats.Reset(1); assert(not stats.Data(1).applied and stats.Data(2).applied == 2, "reset must stay scoped")
for i = 3, 260 do results[i] = { partyGUID = tostring(i), activityIDs = { 20 } }; stats.Changed(i, "applied", "none") end
local count = 0; for _ in pairs(stats.applications) do count = count + 1 end
assert(count <= 128, "application identities must remain bounded")
-- Native filters preserve fields outside Suite ownership and require the native eligible search view.
local saved, searches = nil, 0
local native = { needsMyClass = true, generalPlaystyle3 = true, futureField = 77 }
C_LFGList.GetAdvancedFilter = function() return native end
C_LFGList.SaveAdvancedFilter = function(data) saved = data end
LFGListSearchPanel_DoSearch = function() searches = searches + 1 end
GetLFGRoles = function() return false, true, false, true end
GROUP_FINDER_CATEGORY_ID_DUNGEONS = 2
GameRulesUtil = { IsPlayerAtEffectiveMaxLevel = function() return true end }
LFGListFrame = { SearchPanel = e.Frame(), CategorySelection = { selectedCategory = 2 } }
e.modules.groupFinderTools = { active = true, config = { filters = true, difficulty = 5, minimumRating = 1700,
    activities = "7,7,8", needsRole = true, hasTank = false, hasHealer = true } }
e:Load("MSUF_Suite_QualityOfLife/GroupFinderFilters.lua")
local filters = e.P.GroupFinderFilters
assert(filters.Apply() and searches == 0, "saving the filter must leave the search to the player")
assert(saved.futureField == 77 and saved.generalPlaystyle3 and saved.needsMyClass, "native unrelated filters must survive")
assert(saved ~= native and not native.minimumRating, "must not mutate returned native data")
assert(saved.difficultyMythicPlus and not saved.difficultyNormal and saved.minimumRating == 1700)
assert(saved.needsTank and saved.needsDamage and not saved.needsHealer and #saved.activities == 2)
local savedBefore = saved
e:Combat(true); assert(not filters.Apply() and saved == savedBefore and searches == 0, "combat must not save a filter or issue a search")
e:Combat(false); LFGListFrame.CategorySelection.selectedCategory = 3
assert(not filters.Apply() and saved == savedBefore and searches == 0, "raid search cannot be overwritten by dungeon filters")
LFGListFrame.CategorySelection.selectedCategory = 2
Enum = { LFGListFilter = { PvE = 1 } }
C_LFGList.GetAvailableActivityGroups = function() return { 7, 8 } end
C_LFGList.GetActivityGroupInfo = function(id) return "Dungeon" .. id end
local menuActions = {}
e.S.ContextMenu = function(_, build)
    local menu = {}
    function menu:CreateTitle() end
    function menu:CreateButton(title, fn) menuActions[title] = fn; return self end
    function menu:CreateCheckbox(title, _, fn) menuActions[title] = fn; return self end
    build(nil, menu)
end
local m = e.modules.groupFinderTools
m.Refresh = function() end
filters.Menu({})
local original = m.config.activities
m.active = false; menuActions["All dungeons"]()
assert(m.config.activities == original, "a retained dungeon menu cannot write after disable")
m.active = true; filters.Menu({})
e.NS.DB = {}; menuActions.Dungeon7()
assert(m.config.activities == original, "a retained dungeon menu cannot write after profile switch")
print("comfort group finder: terminal transitions, scope, bounded identities, native preservation and search eligibility passed")
-- Every eligible mail recipient remains reachable; only a hardware click fills the address.
e = F.New(root, false); UIParent = e.Frame(); SendMailFrame = nil; MailFrame = e.Frame(); SendMailNameEditBox = e.Frame()
UnitGUID = function() return "self" end
UnitFullName = function() return "Own", "Realm" end
GetNormalizedRealmName = function() return "Realm" end
GetCurrentRegionName = function() return "US" end
UnitLevel = function() return 60 end
GetServerTime = function() return 10 end
local records = {}
for i = 1, 19 do records["char" .. i] = { name = string.format("Alt%02d", i), realm = "OtherRealm", level = 60, visited = i, region = "US" } end
records.foreign = { name = "Alt00", realm = "OtherRealm", level = 60, visited = 1, region = "EU" }
-- Mail only reaches the current realm and the realms connected to it.
records.far = { name = "Far00", realm = "FarRealm", level = 60, visited = 1, region = "US" }
records.home = { name = "Home00", realm = "Realm", level = 60, visited = 1, region = "US" }
C_AutoComplete = { GetAutoCompleteRealms = function() return { "OtherRealm" } end }
e.NS.RootDB.suiteMailRecipients = records
e:Load("MSUF_Suite_QualityOfLife/MailRecipients.lua")
local m = e:Start("mailRecipients", { rows = 8, sort = 1, minimumLevel = 1, showHidden = false })
assert(not m.frame, "native mail may load after Suite")
SendMailFrame = e.Frame(); e:Emit(m, "MAIL_SHOW"); e:Flush()
assert(m.frame:IsShown() and m.rows[1].entry.address == "Alt01-OtherRealm")
assert(not SendMailNameEditBox.text, "opening mail must not fill any address")
m.next.scripts.OnClick(); m.next.scripts.OnClick()
assert(m.rows[3].entry.address == "Alt19-OtherRealm", "last recipient must be reachable")
m.rows[3].scripts.OnClick(m.rows[3], "LeftButton")
assert(SendMailNameEditBox.text == "Alt19-OtherRealm", "selection must preserve realm")
m.search:SetText("Far00"); e:Flush()
assert(not m.rows[1].entry, "a realm that is not connected cannot be offered as a recipient")
m.search:SetText("Home00"); e:Flush()
assert(m.rows[1].entry and m.rows[1].entry.address == "Home00-Realm", "the current realm must stay offered")
m.search:SetText("Alt17"); e:Flush()
assert(m.rows[1].entry.address == "Alt17-OtherRealm" and not m.rows[2].shown)
m.rows[1].scripts.OnClick(m.rows[1], "RightButton")
assert(records.char17.hidden and not m.rows[1].entry, "hide removes matching recipient")
m.hidden:SetChecked(true); m.hidden.scripts.OnClick(m.hidden); e:Flush()
assert(m.rows[1].entry.record.hidden)
m.rows[1].scripts.OnClick(m.rows[1], "RightButton"); assert(not records.char17.hidden, "hidden recipient can be restored")
e:Combat(true); m.rows[1].scripts.OnClick(m.rows[1], "LeftButton")
assert(SendMailNameEditBox.text == "Alt19-OtherRealm", "combat click must leave recipient unchanged")
e:Combat(false); m.active = false; m:Disable(); assert(not m.frame.shown)
print("comfort mail: delayed native load, search, paging, exact recipient, hide/restore and combat guard passed")

-- A full record list drops its least recently visited character for a new one.
do
    e = F.New(root, false); UIParent = e.Frame(); SendMailFrame = nil; MailFrame = e.Frame()
    local full = {}
    for i = 1, 128 do full["g" .. i] = { name = "Old" .. i, realm = "Realm", level = 60, visited = i, region = "US" } end
    e.NS.RootDB.suiteMailRecipients = full
    e:Load("MSUF_Suite_QualityOfLife/MailRecipients.lua")
    e:Start("mailRecipients", { rows = 8, sort = 1, minimumLevel = 1, showHidden = false })
    local count = 0; for _ in pairs(full) do count = count + 1 end
    assert(full.self and full.self.name == "Own" and not full.g1 and full.g2 and count == 128,
        "a full list refused the current character or kept its oldest entry")
end
print("comfort mail: bounded recipient list keeps the newest characters")

-- Delayed Group Finder build, eligibility and reason use the same native contract.
e = F.New(root, false); UIParent = e.Frame(); LFGListFrame = nil
local categoryChanged
hooksecurefunc = function(name, fn) assert(name == "LFGListSearchPanel_SetCategory"); categoryChanged = fn end
e:Load("MSUF_Suite_QualityOfLife/GroupFinderStatistics.lua")
e:Load("MSUF_Suite_QualityOfLife/GroupFinderFilters.lua")
e:Load("MSUF_Suite_QualityOfLife/GroupFinderTools.lua")
m = e:Start("groupFinderTools", { filters = true, statistics = false, scope = 1 })
assert(not m.frame, "finder can load after Suite")
LFGListFrame = { SearchPanel = e.Frame(), CategorySelection = { selectedCategory = 3 } }
e:Emit(m, "ADDON_LOADED"); e:Flush()
assert(not m.filters.enabled and m.reason.shown, "unsupported category must show a disabled control and reason")
assert(m.frame.height == 110 and m.reason.point[1] == "TOPLEFT" and m.reason.point[3] == -62,
    "filters-only explanation must sit below the controls")
assert(not m.context.events.ADDON_LOADED, "completed build must stop observing unrelated addon loads")
LFGListFrame.CategorySelection.selectedCategory = 2; categoryChanged(); e:Flush()
assert(m.filters.enabled and not m.reason.shown, "eligible dungeon search must become usable")
GameRulesUtil.IsPlayerAtEffectiveMaxLevel = function() return false end
categoryChanged(); e:Flush(); assert(not m.filters.enabled and m.reason.shown, "low level must explain availability")
print("comfort finder UI: late build, category changes, level gate and listener cleanup passed")
