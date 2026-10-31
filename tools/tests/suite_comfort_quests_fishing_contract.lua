local root = assert(arg[1])
local F = dofile(root .. "/tools/tests/comfort_fixture.lua")
local e = F.New(root, true)
UIParent = e.Frame()
local hooks, requests, choices, prices, quest = {}, {}, {}, {}, 10
hooksecurefunc = function(name, fn) hooks[name] = fn end
GetQuestID = function() return quest end
C_QuestLog = { GetSelectedQuest = GetQuestID }
GetQuestItemInfo = function(_, index) local v = choices[index]; return "Reward", 1, v.count, 1, true, v.id end
GetQuestLogChoiceInfo = function(index) return GetQuestItemInfo("choice", index) end
GetQuestItemLink = function(_, index) return "reward:" .. index end
GetQuestLogItemLink = GetQuestItemLink
C_Item = { GetItemInfo = function(key) return "Reward", nil, nil, nil, nil, nil, nil, nil, nil, nil, prices[key] end,
    RequestLoadItemDataByID = function(id) requests[id] = (requests[id] or 0) + 1 end }
local rewards = e.Frame()
rewards.RewardButtons = {}
for i = 1, 2 do local b = e.Frame(); b.id, b.type, b.objectType = i, "choice", "item"; rewards.RewardButtons[i] = b end
QuestInfoFrame = { questLog = false, rewardsFrame = rewards }
choices = { { id = 101, count = 4 }, { id = 102, count = 1 } }
prices = { [101] = 5, [102] = 30, ["reward:1"] = 20, ["reward:2"] = 50 }
e:Load("MSUF_Suite_QualityOfLife/QuestRewardValue.lua")
local m = e:Start("questRewardValue", {})
local function Winner()
    for button, marker in pairs(m.markers) do if marker.shown then return button.id end end
end
assert(Winner() == 1, "contextual reward price times stack size must choose first reward")
assert(not _G.GetQuestReward, "the marker has no reward-selection dependency")
-- All choices must be priced before claiming a winner.
quest = 11; prices["reward:2"], prices[102] = nil, nil
hooks.QuestInfo_ShowRewards(); e:Flush()
assert(not Winner() and requests[102] == 1, "an unknown candidate must suppress a premature winner")
for i = 1, 4 do hooks.QuestInfo_ShowRewards(); e:Flush() end
assert(requests[102] == 1, "unknown item requests must be bounded")
prices["reward:2"] = 100
e:Emit(m, "GET_ITEM_INFO_RECEIVED", 102, true); e:Flush()
assert(Winner() == 2, "async price must repaint current quest")
quest = 12; choices[1].count = e.secret
hooks.QuestInfo_ShowRewards(); e:Flush()
assert(not Winner(), "secret quantity cannot produce a recommendation")
m.active = false; m:Disable(); assert(not Winner(), "disable removes owned markers")
-- Fishing never invokes protected casting from an event or performs a protected write in combat.
e = F.New(root, true); UIParent = e.Frame()
Enum = { SpellBookSpellBank = { Player = 1 }, ItemClass = { Weapon = 2 }, ItemWeaponSubclass = { Fishingpole = 20 } }
INVSLOT_MAINHAND = 16
GetProfessions = function() return nil, nil, nil, 7 end
GetProfessionInfo = function() return "Fishing", 1, 1, 300, 1, 40 end
C_SpellBook = { GetSpellBookItemInfo = function(slot, bank) assert(slot == 41 and bank == 1); return { spellID = 800 } end }
C_Spell = { IsSpellPassive = function() return false end, GetSpellInfo = function() return { name = "Fishing" } end }
C_Item = { GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, 2, 20 end }
RegisterStateDriver = function() error("fishing must not register a polling native state driver") end
local channel = 800
UnitChannelInfo = function() return "Fishing", nil, 1, 1, 2, false, false, channel end
local volumes, restored = {}, 0
e.S.RestoreCVar = function(_, key) volumes[key] = nil; restored = restored + 1 end
e:Load("MSUF_Suite_QualityOfLife/SoundProfiles.lua")
e:Load("MSUF_Suite_QualityOfLife/FishingComfort.lua")
local c = { rod = "1000", lure = "2000", audio = true, music = 10, ambience = 20, effects = 90 }
m = e:Start("fishingComfort", c)
function m.context:CVar(key, value) volumes[key] = value end
assert(m.button.attrs.macrotext1:find("/equip item:1000", 1, true), "selected verified rod is equipped by hardware macro")
assert(m.lure.attrs.macrotext1 == "/stopmacro [combat]\n/use item:2000\n/use 16", "lure remains a separate hardware action")
e:Emit(m, "UNIT_SPELLCAST_CHANNEL_START", "player")
assert(volumes.Sound_MusicVolume == .1 and volumes.Sound_SFXVolume == .9, "audio starts for fishing only")
e:Emit(m, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
assert(restored == 3 and not next(volumes), "channel end restores owned audio")
e:Combat(true); e:Emit(m, "SPELLS_CHANGED"); e:Emit(m, "PLAYER_REGEN_DISABLED")
e:Combat(false); e:Emit(m, "PLAYER_REGEN_ENABLED")
c.rod = "1000\n/cast Bad"; m:Refresh()
assert(m.button.attrs.macrotext1 == "/stopmacro [combat]\n/cast Fishing", "typed item values cannot inject macro commands")
m.active = false; m:Disable(); assert(not m.button.attrs.type1 and not m.lure.attrs.type1, "disable clears both secure actions")
print("comfort quests/fishing: contextual prices, unknown data, secrets, bounded requests, hardware actions and audio teardown passed")
