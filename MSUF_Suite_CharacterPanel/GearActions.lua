local _, NS = ...
local Suite, Text = NS.Suite, NS.Text
local Number, String = NS.Number, NS.String
local Actions = {}
NS.GearActions = Actions

-- Both native Paper Doll panes use the same Blizzard equipment manager.
local function EquipmentSetIDs()
    local ids = C_EquipmentSet.GetEquipmentSetIDs()
    if NS.Public(ids) and type(ids) == "table" then return ids end
end

local function SetInfo(id)
    id = Number(id)
    if not id then return end
    local name, _, setID, equipped = C_EquipmentSet.GetEquipmentSetInfo(id)
    if Number(setID) == id and NS.Public(equipped) then return String(name), equipped, id end
end

function Actions.SetLabel()
    local ids = EquipmentSetIDs()
    if ids then
        for i = 1, #ids do
            local name, equipped = SetInfo(ids[i])
            if name and equipped == true then return string.format(Text("Equipment set: %s"), name) end
        end
    end
    return Text("Equipment sets")
end

local function Equip(entry)
    if not entry.canUse() then return end
    local name, equipped = SetInfo(entry.id)
    if name and equipped == false then EquipmentManager_EquipSet(entry.id) end
end

local function IsEquipped(entry)
    return entry.equipped == true
end

local function SetMenu(_, root, canUse)
    local ids = EquipmentSetIDs()
    local hasSets = false
    if ids then
        for i = 1, #ids do
            local name, equipped, id = SetInfo(ids[i])
            if name then
                root:CreateRadio(name, IsEquipped, Equip, { id = id, equipped = equipped, canUse = canUse })
                hasSets = true
            end
        end
    end
    if not hasSets then root:CreateTitle(Text("No saved equipment sets")) end
end

function Actions.OpenSets(owner, canUse)
    Suite.ContextMenu(owner, SetMenu, canUse)
end

function Actions.OpenLootGoals()
    if NS.Host.InCombat() then return false end
    local planner = Suite.PlanningTools
    if planner and planner.Active() then return planner.Window.Open("loot") end
    return Suite.Open("planningTools")
end
