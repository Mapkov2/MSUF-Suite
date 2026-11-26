local _, Suite = ...
local Conflicts = {}
Suite.AddonConflicts = Conflicts
local Controller = Suite.Suite
local noticed

function Conflicts.List()
    local available = {}
    if Suite.InCombat() or not Controller.started then return available end
    local loaded = {}
    for _, id in ipairs(Controller.order) do
        local spec = Controller.catalog[id]
        if #spec.conflicts > 0 and Suite.Client.flavor ~= "Unknown" and Suite.Client.AddOnEnabled(spec.addon)
            and (not spec.available or spec.available()) then
            local config = Controller.Config(id)
            if config and config.enabled then
                local addons = {}
                for _, name in ipairs(spec.conflicts) do
                    if loaded[name] == nil then
                        loaded[name] = Suite.Client.IsAddOnLoaded(name) and Suite.Client.AddOnEnabled(name) or false
                    end
                    if loaded[name] then addons[#addons + 1] = name end
                end
                if #addons > 0 then
                    available[#available + 1] = { id = id, title = spec.title, addons = addons }
                end
            end
        end
    end
    return available
end

function Conflicts.Notice()
    if noticed or not Controller.started or Suite.InCombat() then return end
    noticed = true
    if #Conflicts.List() > 0 then Suite.Print(Suite.Text("Review overlapping addons in the Addon conflicts page.")) end
end

-- Requested by a confirmed Settings action. Resolve the current list again
-- so an earlier dialog cannot disable addons after the profile has changed.
function Conflicts.UseSuite(id, expected)
    if Suite.InCombat() or not (C_AddOns and C_AddOns.DisableAddOn) then return false end
    local guid = Suite.PublicText(UnitGUID("player"))
    if not guid or guid == "" then return false end
    local mine
    for _, row in ipairs(Conflicts.List()) do
        if row.id == id then mine = row break end
    end
    if not mine or #mine.addons ~= #expected then return false end
    for index = 1, #expected do
        if mine.addons[index] ~= expected[index] then return false end
    end
    local disabled = 0
    for index = 1, #mine.addons do
        local name = mine.addons[index]
        C_AddOns.DisableAddOn(name, guid)
        if not Suite.Client.AddOnEnabled(name) then disabled = disabled + 1 end
    end
    if disabled > 0 and C_AddOns.SaveAddOns then C_AddOns.SaveAddOns() end
    return disabled == #mine.addons, disabled > 0
end
