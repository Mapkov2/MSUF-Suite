local root = assert(arg[1])
local F = dofile(root .. "/tools/tests/comfort_fixture.lua")
local e = F.New(root, true)
UIParent = e.Frame()
local hooks, choices, quest = {}, {}, 10
local prices = { ["reward:1"] = 20, ["reward:2"] = 50 }
local cached = { ["reward:1"] = true, ["reward:2"] = true }
local itemLoads, missingLogLink = 0, false
local itemLoaded = "ITEM_DATA_LOAD_RESULT"
hooksecurefunc = function(name, fn) hooks[name] = fn end
GetQuestID = function() return quest end
C_QuestLog = { GetSelectedQuest = GetQuestID }
GetQuestItemInfo = function(_, index) local v = choices[index]; return "Reward", 1, v.count, 1, true, v.id end
GetQuestLogChoiceInfo = function(index) return GetQuestItemInfo("choice", index) end
GetQuestItemLink = function(_, index) return "reward:" .. index end
GetQuestLogItemLink = function(kind, index)
    if not missingLogLink or index ~= 2 then return GetQuestItemLink(kind, index) end
end
-- Model the selection loss if an extra item load causes a native reward refresh.
local function LoadItem()
    itemLoads = itemLoads + 1
    QuestInfoFrame.itemChoice = 0
end
C_Item = {
    IsItemDataCachedByID = function(link) return cached[link] == true end,
    GetItemInfo = function(link)
        if not cached[link] then
            LoadItem()
            return
        end
        return "Reward", nil, nil, nil, nil, nil, nil, nil, nil, nil, prices[link]
    end,
    RequestLoadItemDataByID = LoadItem,
}
local rewards = e.Frame()
rewards.RewardButtons = {}
for i = 1, 2 do local b = e.Frame(); b.id, b.type, b.objectType = i, "choice", "item"; rewards.RewardButtons[i] = b end
QuestInfoFrame = { questLog = false, rewardsFrame = rewards, itemChoice = 2 }
choices = { { id = 101, count = 4 }, { id = 102, count = 1 } }
e:Load("MSUF_Suite_QualityOfLife/QuestRewardValue.lua")
e.S.MoneyText = tostring
local m = e:Start("questRewardValue", {})
local function Winner()
    for button, marker in pairs(m.markers) do if marker.shown then return button.id end end
end
assert(Winner() == 1, "contextual reward price times stack size must choose first reward")
assert(m.values[rewards.RewardButtons[1]].text == "80", "reward value is for the full stack")
assert(m.values[rewards.RewardButtons[2]].text == "50", "each priced choice receives its own value")
assert(not _G.GetQuestReward, "the marker has no reward-selection dependency")
-- The price pass must not start item loads while a choice is selected.
quest = 11
cached["reward:2"] = false
hooks.QuestInfo_ShowRewards()
e:Flush()
assert(itemLoads == 0 and QuestInfoFrame.itemChoice == 2, "a cold price must not start a load and disturb the choice")
assert(not Winner() and not m.values[rewards.RewardButtons[2]].shown, "a cold price must not leave a stale winner or value")
for i = 1, 4 do
    hooks.QuestInfo_ShowRewards()
    e:Flush()
end
assert(m.context.events[itemLoaded] and itemLoads == 0, "reward redraws must only wait for the native load")
e:Emit(m, itemLoaded, 999, true)
assert(not m.job.pending, "unrelated item loads must not queue a redraw")
cached["reward:2"] = true
prices["reward:2"] = 100
e:Emit(m, itemLoaded, 102, true)
e:Flush()
assert(Winner() == 2 and not m.context.events[itemLoaded], "a native load must repaint the price and stop waiting")
assert(itemLoads == 0 and QuestInfoFrame.itemChoice == 2, "the passive repaint must leave the choice intact")

-- A missing link in the quest log can resolve after native item data arrives.
quest = 12
QuestInfoFrame.questLog = true
missingLogLink = true
hooks.QuestInfo_Display()
e:Flush()
assert(not Winner() and m.context.events[itemLoaded], "a known item ID must wait even when the log link is missing")
missingLogLink = false
prices["reward:2"] = 0
e:Emit(m, itemLoaded, 102, true)
e:Flush()
assert(Winner() == 1 and itemLoads == 0, "an unsellable item is a resolved price in the quest log")

cached["reward:2"] = false
hooks.QuestInfo_Display()
e:Flush()
e:Emit(m, itemLoaded, 102, false)
assert(not m.context.events[itemLoaded] and not m.job.pending, "a failed load must stop waiting without a retry")
hooks.QuestInfo_Display()
e:Flush()
e:Combat(true)
e:Emit(m, "PLAYER_REGEN_DISABLED")
assert(not m.context.events[itemLoaded] and not Winner(), "combat must release the pending price listener and labels")
cached["reward:2"] = true
e:Combat(false)
e:Emit(m, "PLAYER_REGEN_ENABLED")
e:Flush()
assert(Winner() == 1 and itemLoads == 0, "combat exit must read the cache even if the load event was missed")

QuestInfoFrame.questLog = false
cached["reward:2"] = false
hooks.QuestInfo_Display()
e:Flush()
assert(m.context.events[itemLoaded], "open dialogue must be waiting for the missing price")
rewards:Hide()
e:Emit(m, "QUEST_FINISHED")
e:Flush()
assert(not m.context.events[itemLoaded] and not Winner(), "closing the dialogue must stop waiting")
rewards:Show()
cached["reward:2"] = true
quest = 13
choices[1].count = e.secret
hooks.QuestInfo_ShowRewards()
e:Flush()
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
local messages, instance = 0, 42
GetInstanceInfo = function() return nil, instance and "party" or "none", nil, nil, nil, nil, nil, instance end
GetInventoryItemLink = function() return "item:1000" end
e.NS.Print = function() messages = messages + 1 end
e:Emit(m, "PLAYER_ENTERING_WORLD")
e:Emit(m, "PLAYER_ENTERING_WORLD")
assert(messages == 1, "the same instance entry warns once")
instance = 43
e:Combat(true); e:Emit(m, "PLAYER_ENTERING_WORLD"); e:Combat(false)
assert(messages == 1, "entering during combat never checks the rod")
e:Emit(m, "PLAYER_ENTERING_WORLD")
assert(messages == 2, "entering another instance can show the warning")
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
local routed, handle, onCombat
local enabledInteract = "0"
Enum.SoftTargetEnableFlags = { Any = 3 }
C_CVar = { GetCVar = function(key) assert(key == "softTargetInteract"); return enabledInteract end }
GetBindingKey = function(binding) assert(binding == "CLICK MSUFSuiteFishing:LeftButton"); return "F", "SHIFT-F" end
ClearOverrideBindings = function() routed = {} end
handle = {
    ClearBindings = ClearOverrideBindings,
    SetBinding = function(_, priority, key, action)
        assert(priority == false and action == "INTERACTTARGET", "must delegate only to native Interact")
        routed[key] = action
    end,
}
RegisterStateDriver = function(owner, state)
    assert(state == "fishcombat")
    function handle:GetAttribute(key) return owner.attrs[key] end
    onCombat = setfenv(assert(loadstring(owner.attrs["_onstate-fishcombat"])), { self = handle, newstate = "blocked" })
end
UnregisterStateDriver = function(_, state)
    assert(state == "fishcombat")
    onCombat = nil
end
SecureHandlerExecute = function(_, snippet) setfenv(assert(loadstring(snippet)), { self = handle })() end
c.audio, c.sameKeyInteract = false, true
m:Refresh()
e:Emit(m, "UNIT_SPELLCAST_CHANNEL_START", "player")
assert(not m.routing and not m.bindingOwner, "disabled native Interact must leave the cast binding alone")
e:Emit(m, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
enabledInteract = "3"
channel = e.secret
e:Emit(m, "UNIT_SPELLCAST_CHANNEL_START", "player")
assert(not m.routing, "an unreadable cast must not take ownership of the binding")
channel = 800
e:Emit(m, "UNIT_SPELLCAST_CHANNEL_START", "player")
assert(routed.F and routed["SHIFT-F"] and m.routing, "the selected Fishing bindings must reach Blizzard Interact")
e:Emit(m, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
assert(not next(routed) and not m.routing and not onCombat, "channel stop must release keys and stop watching combat")
e:Emit(m, "UNIT_SPELLCAST_CHANNEL_START", "player")
e:Combat(true); onCombat()
assert(not next(routed), "combat must release the override through the secure state driver")
e:Emit(m, "PLAYER_REGEN_DISABLED")
e:Combat(false); e:Emit(m, "PLAYER_REGEN_ENABLED")
m.active = false; m:Disable(); assert(not m.button.attrs.type1 and not m.lure.attrs.type1, "disable clears both secure actions")
print("comfort quests/fishing: passive reward prices, unknown data, secrets, hardware actions and audio teardown passed")
