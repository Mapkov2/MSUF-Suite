local root = assert(arg[1])
local F = assert(loadfile(root .. "/tools/tests/comfort_fixture.lua"))()
local E = F.New(root, false)
local S, NS = E.S, E.NS
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
local now, messages, sounds = 1000, {}, 0
GetTime = function() return now end
GetServerTime = GetTime
date = os.date
SOUNDKIT = { RAID_WARNING = 1 }
PlaySound = function() sounds = sounds + 1 end
S.Print = function(text) messages[#messages + 1] = text end
S.CharacterData = NS.CharacterData
NS.SuiteCatalog = { keywordAlerts = {}, currencyGoals = {} }
local window = { SetStatus = function(self, text) self.status = text end }
S.ToolListWindow = {
    Open = function(owner, spec) window.owner, window.spec = owner, spec; return window end,
    Refresh = function() end, Close = function() end,
    Edit = function(owner, spec) window.editOwner, window.edit = owner, spec end,
}
S.Confirm = function(_, data) assert(type(data) == "table"); window.confirm = data.callback end
S.Open = function(id) window.opened = id end
E:Load("MSUF_Suite_Modules/SuiteNotices.lua")
local history = E:Start("notificationHistory", { limit = 10, mergeSeconds = 60 })
assert(S.Notifications.Push("a", "Title", "Detail", "currencyGoals"))
assert(S.Notifications.Push("a", "Title", "Detail", "currencyGoals"))
local saved = S.CharacterData("notificationHistory")
assert(#saved.entries == 1 and saved.entries[1].count == 2, "repeat merged")
assert(not S.Notifications.Push(E.secret, "Title", "Detail"), "secret key rejected")
for i = 1, 20 do S.Notifications.Push("n" .. i, "Title", "Detail") end
assert(#saved.entries == 10, "bounded history")
history:Open(); window.spec.actions[2].run(); window.confirm()
assert(#saved.entries == 0, "clear uses actual confirmation callback")
history.active = false
assert(not S.Notifications.Push("a", "Title", "Detail"), "disabled history does no work")
history.active = true

E:Load("MSUF_Suite_QualityOfLife/KeywordAlerts.lua")
local keywords = E:Start("keywordAlerts", { words = "Ready.\nKey", party = true, raid = false,
    guild = false, say = false, channels = false, cooldown = 30, sound = true })
assert(not keywords.context.events.CHAT_MSG_GUILD, "unselected scope not registered")
E:Emit(keywords, "CHAT_MSG_PARTY", "readyX", "Tank")
assert(#messages == 0, "phrases match literal text, not Lua patterns")
E:Emit(keywords, "CHAT_MSG_PARTY", "READY.", "Tank")
E:Emit(keywords, "CHAT_MSG_PARTY", "ready.", "Tank")
assert(#messages == 1 and sounds == 1, "case-insensitive and rate limited")
E:Emit(keywords, "CHAT_MSG_PARTY", E.secret, "Tank")
E:Emit(keywords, "CHAT_MSG_PARTY", "key", E.secret)
assert(#messages == 1, "restricted message or author excluded")
now = now + 31
E:Emit(keywords, "CHAT_MSG_PARTY", "ready.", "Tank")
assert(#messages == 2, "rate window expires")
keywords.config.words = ""; keywords:Refresh()
assert(not next(keywords.context.events), "empty phrase list removes listeners")
keywords:Open()
keywords.config.words = "newer settings"
assert(window.edit.onSave(keywords, "old edit") == false, "stale keyword editor cannot overwrite newer settings")
keywords:Open()
assert(window.edit.onSave(keywords, string.rep("目", 80)), "80 UTF-8 characters fit the phrase limit")
keywords:Open()
assert(window.edit.onSave(keywords, string.rep("目", 81)) == false, "81 UTF-8 characters exceed the phrase limit")

local quantity = 5
C_CurrencyInfo = {
    GetCurrencyInfo = function(id) if id == 42 then return { name = "Tokens", quantity = quantity,
        maxQuantity = 100, maxWeeklyQuantity = 100, quantityEarnedThisWeek = quantity } end end,
    GetCurrencyListSize = function() return 2 end,
    GetCurrencyListLink = function(i) return i == 1 and "|Hcurrency:42|hTokens|h" or E.secret end,
}
S.CharacterData("currencyGoals").goals = { [42] = 10 }
E:Load("MSUF_Suite_QualityOfLife/CurrencyGoals.lua")
local currency = E:Start("currencyGoals", { notifyGoal = true, notifyCap = true, capPercent = 90 })
assert(#messages == 2, "initial state never spams old goals")
quantity = 11; E:Emit(currency, "CURRENCY_DISPLAY_UPDATE"); E:Flush()
assert(#messages == 3, "goal crossing notifies")
E:Emit(currency, "CURRENCY_DISPLAY_UPDATE"); E:Flush()
assert(#messages == 3, "unchanged currency does not repeat")
quantity = 95; E:Emit(currency, "CURRENCY_DISPLAY_UPDATE"); E:Flush()
assert(#messages == 4, "cap crossing notifies once")
quantity = E.secret; E:Emit(currency, "CURRENCY_DISPLAY_UPDATE"); E:Flush()
assert(#messages == 4, "secret quantity cannot enter calculations")
quantity = 5
currency:Open(); window.spec.actions[1].run()
assert(#window.spec.rows() == 1, "currency picker ignores restricted link")
window.spec.actions[1].run(currency, window.spec.rows()[1])
assert(window.edit.onSave(currency, "-1") == false, "target validation")
assert(window.edit.onSave(currency, "20"))
assert(S.CharacterData("currencyGoals").goals[42] == 20)
quantity = 21
local beforeGoal = #messages
E:Emit(currency, "CURRENCY_DISPLAY_UPDATE"); E:Flush()
assert(#messages == beforeGoal + 1, "first earning after changing target must notify")
currency:Open()
window.spec.actions[2].run(currency, window.spec.rows()[1])
S.CharacterData("currencyGoals").goals[42] = nil
assert(window.edit.onSave(currency, "30") == false, "stale goal editor cannot recreate a removed goal")
S.CharacterData("currencyGoals").goals[42] = 500
local earned = 50
C_CurrencyInfo.GetCurrencyInfo = function()
    return { name = "Tokens", quantity = 5, maxQuantity = 100, useTotalEarnedForMaxQty = true, totalEarned = earned }
end
currency:Refresh()
local beforeCap = #messages
earned = 95; E:Emit(currency, "CURRENCY_DISPLAY_UPDATE"); E:Flush()
assert(#messages == beforeCap + 1, "earned-total currency cap follows totalEarned instead of spendable balance")
earned = E.secret; E:Emit(currency, "CURRENCY_DISPLAY_UPDATE"); E:Flush()
assert(#messages == beforeCap + 1, "secret lifetime earnings are never compared or formatted")

local setPoint, tracked = nil, false
local position = { GetXY = function() return .25, .75 end }
C_Map = { GetBestMapForUnit = function() return 84 end, GetPlayerMapPosition = function() return position end,
    GetMapInfo = function() return { name = "City" } end, GetUserWaypoint = function() return E.secret end,
    CanSetUserWaypointOnMap = function() return true end, SetUserWaypoint = function(point) setPoint = point; return true end }
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(value) tracked = value end }
E:Load("MSUF_Suite_QualityOfLife/WaypointLists.lua")
local waypoints = E:Start("waypointLists", { superTrack = true })
waypoints:Open(); window.spec.actions[1].run(waypoints, nil, window)
assert(window.edit.onSave(waypoints, "Bank"))
assert(window.edit.onSave(waypoints, "Weekly"))
local points = S.CharacterData("waypointLists").points
assert(#points == 1 and points[1].map == 84 and not setPoint, "saving never activates movement or a pin")
waypoints:Open(); local rows = window.spec.rows()
window.spec.actions[3].run(waypoints, rows[1], window)
assert(setPoint.map == 84 and setPoint.x == .25 and tracked, "explicit activation uses exact saved coordinates")
window.spec.actions[2].run(waypoints, nil, window)
assert(#points == 1, "restricted map pin ignored")
window.spec.actions[4].run(waypoints, rows[1]); local previous = NS.DB; NS.DB = {}
window.confirm(); assert(#points == 1, "stale remove confirmation rejected")
NS.DB = previous

local volumes, restoreCount, kind = {}, 0, "world"
S.RestoreCVar = function(_, key) volumes[key] = nil; restoreCount = restoreCount + 1 end
S.InstanceKind = function() return kind end
E:Load("MSUF_Suite_QualityOfLife/SharedItems.lua")
E:Load("MSUF_Suite_QualityOfLife/SoundProfiles.lua")
local sound = E.modules.soundProfiles
sound.active, sound.context = true, E:Context()
sound.context.CVar = function(_, key, value) volumes[key] = value end
sound.config = { worldMusic = 10, worldAmbience = 20, worldEffects = 30,
    partyMusic = 40, partyAmbience = 50, partyEffects = 60, raidMusic = 70, raidAmbience = 80, raidEffects = 90 }
sound:Enable(); assert(volumes.Sound_MusicVolume == .1)
kind = "party"; E:Emit(sound, "ZONE_CHANGED_NEW_AREA"); assert(volumes.Sound_MusicVolume == .4)
E:Combat(true); kind = "raid"; E:Emit(sound, "ZONE_CHANGED_NEW_AREA")
assert(volumes.Sound_MusicVolume == .4, "combat defers context writes")
E:Combat(false); E:Emit(sound, "PLAYER_REGEN_ENABLED"); assert(volumes.Sound_MusicVolume == .7)
S.SuspendSoundProfile(); S.instances.fishingComfort = { audio = true }; S.RefreshSoundProfile()
assert(not volumes.Sound_MusicVolume, "fishing owns sound until it ends")
S.instances.fishingComfort.audio = nil; S.RefreshSoundProfile(); assert(volumes.Sound_MusicVolume == .7)
sound:Disable(); assert(not next(volumes), "disable releases owned sound settings")
print("PASS everyday tools: bounded notices, literal scoped keywords, currency crossings, manual waypoints, sound lifecycle")
