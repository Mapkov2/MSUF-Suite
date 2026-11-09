local _, P = ...
local NS, S, Plan = P.NS, P.Suite, P.PlanningTools
local Loadouts = {}
Plan.Loadouts = Loadouts

local function Equipment()
    local ids = C_EquipmentSet.GetEquipmentSetIDs()
    if not S.Public(ids) or type(ids) ~= "table" then return nil end
    local known = #ids <= 30
    for i = 1, math.min(#ids, 30) do
        if S.Finite(ids[i]) then
            local name, _, id, equipped = C_EquipmentSet.GetEquipmentSetInfo(ids[i])
            local public = S.Public(equipped)
            if public and equipped == true and S.Finite(id) then return id, Plan.Text(name, 120), true end
            if not public or equipped ~= false then known = false end
        else
            known = false
        end
    end
    return nil, nil, known
end

function Loadouts.Current()
    if NS.Client.isForever or NS.InCombat() then return nil end
    local config, build, loot, lootName, spec, specName, lootPreference = S.LoadoutSnapshot()
    if not S.Finite(config) or not S.Finite(loot) or not S.PublicText(build) or not S.PublicText(lootName) then return nil end
    local equipment, equipmentName, equipmentKnown = Equipment()
    return { config = config, build = build, loot = loot, lootName = lootName, equipment = equipment, equipmentName = equipmentName,
        equipmentKnown = equipmentKnown == true, spec = spec, specName = specName, lootPreference = lootPreference }
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

local function Build(entry)
    local name = Plan.Text(entry.build, 120) or S.Text("Unknown")
    local spec = Plan.Text(entry.specName, 120)
    return spec and S.Text("%s — %s"):format(spec, name) or name
end

local function Delta(rows, fields, field, label, current, saved)
    fields[field] = true
    rows[#rows + 1] = S.Text(label):format(S.Text("%s → %s"):format(current, saved))
end

local function Differences(expected, current)
    if type(expected) ~= "table" or not current then return nil end
    local talents = expected.config ~= current.config or expected.spec and current.spec and expected.spec ~= current.spec
    local loot = expected.loot ~= current.loot or expected.lootPreference and current.lootPreference
        and expected.lootPreference ~= current.lootPreference
    local gear = current.equipmentKnown ~= false and expected.equipment and expected.equipment ~= current.equipment
    if not talents and not loot and not gear then return nil end
    local rows, fields = {}, {}
    if talents then
        Delta(rows, fields, "talents", "Talents: %s", Build(current), Build(expected))
    end
    if loot then
        Delta(rows, fields, "loot", "Loot: %s", current.lootName, Plan.Text(expected.lootName, 120) or S.Text("Unknown"))
    end
    if gear then
        Delta(rows, fields, "gear", "Equipment: %s", current.equipmentName or S.Text("No equipment set active"),
            Plan.Text(expected.equipmentName, 120) or S.Text("Unknown"))
    end
    return rows, fields
end

function Loadouts.Mismatch(expected, current)
    local rows = Differences(expected, current)
    return rows and table.concat(rows, "\n") or nil
end

local function InstanceDifferences()
    if not Plan.CanEdit() or NS.Client.isForever or not Plan.owner.config.loadouts then return end
    local instance, entries = Plan.Instance(), Plan.Bucket("loadouts")
    local expected = instance and entries and entries[instance.key]
    return Differences(expected, expected and Loadouts.Current()), instance and instance.key
end

function S.PlanningLoadoutIssues()
    local issues = InstanceDifferences()
    return issues
end

function Loadouts.Check()
    local issues, key = InstanceDifferences()
    local detail = issues and table.concat(issues, "\n")
    local signature = detail and key .. detail or nil
    if signature and signature ~= Loadouts.last then Plan.Notify("loadout", S.Text("Check your loadout"), detail) end
    Loadouts.last = signature
end

function Loadouts.Rows()
    local rows, entries = {}, Plan.Bucket("loadouts")
    if not entries or not next(entries) then return rows end
    local current = Loadouts.Current()
    for key, entry in pairs(entries) do
        if type(entry) == "table" and Plan.Text(entry.name, 120) then
            local differences, fields = Differences(entry, current)
            local summary = S.Text("Talents: %s\nLoot: %s\nEquipment: %s"):format(Build(entry), entry.lootName or "--",
                entry.equipmentName or S.Text("Any equipment"))
            if differences then
                summary = summary .. "\n\n" .. S.Text("Current → saved") .. "\n" .. table.concat(differences, "\n")
            elseif current and (current.equipmentKnown or not entry.equipment) then
                summary = summary .. "\n\n" .. S.Text("Current loadout matches.")
            end
            rows[#rows + 1] = { key = key, label = entry.name,
                detail = summary, differences = fields }
        end
    end
    table.sort(rows, Plan.SortNames)
    return rows
end

local function OpenGear()
    if S.OpenCharacterPanelTab and S.OpenCharacterPanelTab("gear") then return true end
    ToggleCharacter("PaperDollFrame", true)
    local visible = PaperDollFrame and PaperDollFrame:IsVisible()
    if S.Public(visible) and visible == true then
        PaperDollFrame_SetSidebar(nil, 3)
        return true
    end
    return false
end

function Loadouts.CanOpen(field)
    if not Plan.CanEdit() or NS.Client.isForever or not S.CanOpenNativeWindow() then return false end
    if field == "talents" then return PlayerSpellsUtil and PlayerSpellsUtil.OpenToClassTalentsTab ~= nil end
    if field == "loot" then return UnitPopup_OpenMenu ~= nil end
    if field == "gear" then return ToggleCharacter ~= nil and PaperDollFrame_SetSidebar ~= nil end
    return false
end

function Loadouts.Open(field)
    if not Loadouts.CanOpen(field) then return false end
    if field == "gear" then
        local called, opened = S.Dispatch(S.Finish, OpenGear)
        return called == true and opened == true
    end
    if field == "talents" then return S.Dispatch(S.Finish, PlayerSpellsUtil.OpenToClassTalentsTab) end
    return S.Dispatch(S.Finish, UnitPopup_OpenMenu, "SELF", { unit = "player", which = "SELF" })
end
