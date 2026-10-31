local _, P = ...
local NS, S, Plan = P.NS, P.Suite, P.PlanningTools
local Loadouts = {}
Plan.Loadouts = Loadouts

local function Equipment()
    local ids = C_EquipmentSet.GetEquipmentSetIDs()
    if not S.Public(ids) or type(ids) ~= "table" then return nil end
    for i = 1, math.min(#ids, 30) do
        if S.Finite(ids[i]) then
            local name, _, id, equipped = C_EquipmentSet.GetEquipmentSetInfo(ids[i])
            if S.Public(equipped) and equipped == true and S.Finite(id) then return id, Plan.Text(name, 120) end
        end
    end
end

function Loadouts.Current()
    if NS.Client.isForever or NS.InCombat() then return nil end
    local config, build, loot, lootName = S.LoadoutSnapshot()
    if not S.Finite(config) or not S.Finite(loot) or not S.PublicText(build) or not S.PublicText(lootName) then return nil end
    local equipment, equipmentName = Equipment()
    return { config = config, build = build, loot = loot, lootName = lootName, equipment = equipment, equipmentName = equipmentName }
end

function Loadouts.Save()
    if not Plan.CanEdit() then return false end
    local instance, current, entries = Plan.Instance(), Loadouts.Current(), Plan.Bucket("loadouts")
    if not instance or not current or not entries then return false end
    if not entries[instance.key] and Plan.Count(entries) >= Plan.LIMIT.loadouts then return false end
    current.name, current.instanceID = instance.name, instance.id
    entries[instance.key] = current
    Plan.Changed()
    return true
end

function Loadouts.Mismatch(expected, current)
    if not expected or not current then return nil end
    local rows = {}
    if expected.config ~= current.config then rows[#rows + 1] = S.Text("Talents: %s"):format(expected.build) end
    if expected.loot ~= current.loot then rows[#rows + 1] = S.Text("Loot: %s"):format(expected.lootName) end
    if expected.equipment and expected.equipment ~= current.equipment then
        rows[#rows + 1] = S.Text("Equipment: %s"):format(expected.equipmentName or S.Text("Unknown"))
    end
    return #rows > 0 and table.concat(rows, "\n") or nil
end

function Loadouts.Check()
    if not Plan.CanEdit() or not Plan.owner.config.loadouts then return end
    local instance, entries = Plan.Instance(), Plan.Bucket("loadouts")
    local expected = instance and entries and entries[instance.key]
    local detail = Loadouts.Mismatch(expected, expected and Loadouts.Current())
    local signature = detail and instance.key .. detail or nil
    if signature and signature ~= Loadouts.last then Plan.Notify("loadout", S.Text("Check your loadout"), detail) end
    Loadouts.last = signature
end

function Loadouts.Rows()
    local rows = {}
    for key, entry in pairs(Plan.Bucket("loadouts") or {}) do
        if type(entry) == "table" and Plan.Text(entry.name, 120) then
            rows[#rows + 1] = { key = key, label = entry.name,
                detail = S.Text("Talents: %s\nLoot: %s\nEquipment: %s"):format(entry.build or "--", entry.lootName or "--",
                    entry.equipmentName or S.Text("Any equipment")) }
        end
    end
    table.sort(rows, Plan.SortNames)
    return rows
end
