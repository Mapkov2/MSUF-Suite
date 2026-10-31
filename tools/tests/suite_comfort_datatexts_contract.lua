local root = assert(arg[1])
local F = dofile(root .. "/tools/tests/comfort_fixture.lua")
local e = F.New(root, true)
local providers, reads, meta, counts, requests = {}, 0, {}, {}, {}
local Sources = { Register = function(kind, provider) providers[kind] = provider end }
e.P.DataTextSources, e.P.NO_VALUE = Sources, "-"
local owner = { context = e:Context(), config = { suppliesLearn = true, suppliesItems = "99999999999999999999,999" } }
local formats = 0
function Sources.Refresh(kind) formats = formats + 1; providers[kind].Format({ icons = {} }) end
Enum = { ItemClass = { Reagent = 5, Miscellaneous = 15 }, ItemReagentSubclass = { Reagent = 0 },
    ItemMiscellaneousSubclass = { Reagent = 1 } }
NUM_BAG_SLOTS = 4
C_Container = { GetContainerNumSlots = function() reads = reads + 1; return 1 end,
    GetContainerItemID = function() return 100 end }
C_PaperDollInfo = { GetInventorySlotInfo = function(name) assert(name == "AmmoSlot"); return 0 end }
GetInventoryItemID = function() return nil end
GetInventoryItemCount = function() return 99 end
C_Item = { GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, 5, 0 end,
    GetItemInfo = function(id) assert(id > 0 and id < 2147483647, "item ID out of native range"); if meta[id] == false then return nil end; return "Supply" .. id, nil, nil, nil, nil, nil, nil, nil, nil, 134400 end,
    GetItemCount = function(id, bank, uses, reagent, account)
        assert(not bank and not uses and not reagent and not account)
        return counts[id] or 0
    end, RequestLoadItemDataByID = function(id) requests[id] = (requests[id] or 0) + 1 end }
local saved = e.NS.CharacterData("supplies"); saved.items = {}
for i = 1, 32 do saved.items[i] = 100 + i end
counts[999] = 17
e:Load("MSUF_Suite_DataTexts/Supplies.lua")
local supplies = providers.supplies
supplies.Rebind(owner, true)
local binding = { icons = {} }
local _, value = supplies.Format(binding)
assert(value:match("^17 / "), "explicit item cannot be crowded out by 32 remembered reagents")
assert(#binding.icons == 32, "supplies remain bounded")
local originalReads = reads
for i = 1, 50 do supplies.Format({ icons = {} }) end
assert(reads == originalReads, "unchanged places must reuse the same snapshot")
for i = 1, 100 do e:NativeEvent("BAG_UPDATE_DELAYED") end
e:Flush()
assert(formats == 1 and reads == originalReads, "a full learned list must not scan bags while refreshing counts")
counts[999] = 0; e:NativeEvent("BAG_UPDATE_DELAYED"); e:Flush()
_, value = supplies.Format({ icons = {} }); assert(value:match("^0 / "), "zero stock stays visible")
supplies.Rebind(owner, false); originalReads = reads
for i = 1, 100 do e:NativeEvent("BAG_UPDATE_DELAYED") end
e:Flush(); assert(reads == originalReads, "hidden supplies must do no bag work")
-- Removing a custom entry updates the same profile table, without requiring reload.
owner.config.suppliesItems = "1000"; supplies.Rebind(owner, true)
_, value = supplies.Format({ icons = {} }); assert(not value:find("17", 1, true))
saved.items = {}
supplies.Rebind(owner, true)
local readsBefore = reads
supplies.Format({ icons = {} })
assert(reads == readsBefore + 5 and #saved.items == 1, "reset must forget obsolete entries and learn only current bags")
assert(owner.config.suppliesItems == "1000", "forgetting remembered reagents must preserve explicit items")
owner.config.suppliesItems = string.rep("1000,", 32) .. "999"
counts[999] = 17
supplies.Rebind(owner, true)
_, value = supplies.Format({ icons = {} })
assert(value:find("17", 1, true), "repeated custom tokens cannot crowd out later unique supplies")
owner.config.suppliesLearn, owner.config.suppliesItems = false, "1001"
meta[1001] = false
supplies.Rebind(owner, true); supplies.Format({ icons = {} })
supplies.Disable(); supplies.Rebind(owner, true); supplies.Format({ icons = {} })
local previousFormats = formats
meta[1001] = true; e:NativeEvent("GET_ITEM_INFO_RECEIVED", 1001, true); e:Flush()
assert(formats == previousFormats + 1, "reopening while item data is pending must restore the completion listener")
supplies.Disable()
for _, frame in ipairs(e.frames) do assert(not next(frame.events), "disable leaves no supplies listener") end
print("comfort supplies: explicit priority, zero stock, bounded data, burst coalescing and hidden zero work passed")
-- The shared Vault provider caches native reads for all placements, then
-- invalidates on native weekly change. Restricted activity fields are omitted.
e = F.New(root, false)
local data = { { id = 1, type = 1, index = 1, progress = 1, threshold = 1, level = 2 },
    { id = 2, type = 2, index = 1, progress = 2, threshold = 4, level = 0 },
    { type = 2, index = 2, progress = e.secret, threshold = 8 } }
Enum = { WeeklyRewardChestThresholdType = { Raid = 1, Activities = 2, RankedPvP = 3, World = 4 } }
local nativeReads, ready, capabilityReads = 0, false, 0
e.NS.Client.HasAddOn = function() capabilityReads = capabilityReads + 1; return true end
C_WeeklyRewards = { HasAvailableRewards = function() return ready end, GetActivities = function() nativeReads = nativeReads + 1; return data end,
    GetExampleRewardItemHyperlinks = function() return "reward:item" end }
C_Item.GetDetailedItemLevelInfo = function() return 275 end
GetDifficultyInfo = function() return "Normal" end
e.S.BlizzardText = function(_, fallback) return fallback end
assert(loadfile(root .. "/MSUF_Suite/Core/WeeklyRewards.lua"))("test", e.NS)
local vault = e.NS.WeeklyRewards
assert(vault.Summary() == "1 / 2 slots")
for i = 1, 100 do assert(vault.Summary() == "1 / 2 slots") end
assert(nativeReads == 1, "many vault placements must share one native fetch")
assert(capabilityReads == 1, "cached placements must not repeat native addon-existence probes")
ready = true; vault.Invalidate(); assert(vault.Summary() == "Reward available" and nativeReads == 2)
local tooltip = { lines = {} }
function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function tooltip:AddDoubleLine(a,b) self.lines[#self.lines + 1] = a .. ":" .. b end
vault.AppendTooltip(tooltip, true)
assert(nativeReads == 2 and #tooltip.lines == 3, "tooltip shares snapshot and skips secret row")
e.NS.Client.isForever = true; vault.Invalidate(); assert(not vault.Summary() and nativeReads == 2, "Forever never reads Vault API")
print("comfort vault: shared summary/tooltip, invalidation, restricted data and client gate passed")
