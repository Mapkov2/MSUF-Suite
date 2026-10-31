local _, NS = ...
local S = NS.Suite
-- Cold settings inspection. Never reads spell cooldowns, aura contents or secret state.
-- The hide conditions say whether they hide the bar right now: the macro
-- conditions through the same conditional the bar's driver uses, the
-- instance rule through IsInInstance; only for a condition that is on.
local HIDES = {
    { "hideResting", "Hidden while resting.", "Hidden while resting. You are resting now." },
    { "hideSolo", "Hidden when not in a group.", "Hidden when not in a group. You are not in a group now." },
    { "hideWorld", "Hidden outside instances.", "Hidden outside instances. You are outside an instance now." },
    { "hideFlying", "Hidden while flying.", "Hidden while flying. You are flying now." },
    { "hideDead", "Hidden while dead.", "Hidden while dead. You are dead now." },
}
local function HidesNow(catalog, suffix)
    if suffix == "hideWorld" then
        local _, kind = IsInInstance()
        return not (NS.Public(kind) and catalog.INSTANCES[kind] == true)
    end
    for _, rule in ipairs(catalog.HIDE_MACROS) do
        if rule.suffix == suffix then
            local answer = SecureCmdOptionParse(rule.macro .. " now")
            return NS.Public(answer) and answer == "now"
        end
    end
    return false
end
local function Conditions(catalog, keys, config, reasons)
    for _, hide in ipairs(HIDES) do
        if config[keys[hide[1]]] == true then
            reasons[#reasons + 1] = NS.Text(HidesNow(catalog, hide[1]) and hide[3] or hide[2])
        end
    end
    local faded = config[keys.hiddenAlpha]
    if type(faded) == "number" and faded > 0 then
        reasons[#reasons + 1] = NS.Text("Hidden, this bar fades to %d%% opacity instead of disappearing."):format(faded)
    end
    if config[keys.hoverShow] == true then
        reasons[#reasons + 1] = NS.Text("Pointing at this bar shows it while it is hidden or faded.")
    end
end
local function BuildRow(slot, config)
    local catalog = NS.CDM
    local keys = catalog.KEYS[slot.key]
    local reasons = {}
    local available, why = S.Availability("cooldownManager")
    local state = S.states.cooldownManager
    if not available then reasons[1] = NS.Text(why or "Unavailable on this client")
    elseif state.error then reasons[1] = NS.Text(state.error)
    elseif not config.enabled then reasons[1] = NS.Text("Cooldown manager is switched off.") end
    if #reasons == 0 then
        if not config[keys.on] then reasons[#reasons + 1] = NS.Text("This bar is switched off.") end
        if config[keys.vis] == catalog.VIS.HIDDEN then reasons[#reasons + 1] = NS.Text("Visibility is set to Hidden.")
        elseif config[keys.vis] == catalog.VIS.COMBAT then reasons[#reasons + 1] = NS.Text("This bar appears only in combat.")
        elseif config[keys.vis] == catalog.VIS.COMBAT_OR_TARGET then reasons[#reasons + 1] = NS.Text("This bar needs combat or a target.") end
        if config[keys.alpha] == 0 then reasons[#reasons + 1] = NS.Text("Bar opacity is zero.") end
        if config[keys.oocAlpha] == 0 then reasons[#reasons + 1] = NS.Text("Out-of-combat opacity is zero.") end
        if config[keys.hideMounted] then reasons[#reasons + 1] = NS.Text("Hidden while mounted.") end
        if config[keys.hideVehicle] then reasons[#reasons + 1] = NS.Text("Hidden in vehicles or override bars.") end
        Conditions(catalog, keys, config, reasons)
        if config[keys.hideReady] then reasons[#reasons + 1] = NS.Text("Ready abilities are hidden.") end
        if #reasons == 0 then
            reasons[1] = NS.Text("No visibility restriction found in these settings. Spell availability still depends on Blizzard's current data.")
        end
    end
    return { label = NS.Text(slot.title), reason = table.concat(reasons, "\n"), page = "suite_cooldownManager", slot = slot.key,
        target = { pageKey = "suite_cooldownManager", sectionId = "suite_cooldownManager_visibility",
            settingKey = "msufsuite.cooldownManager.c1_vis", prepareKind = "suiteCDMBar", prepareValue = slot.key } }
end
function S.CDMInspectionRow(slotKey)
    for _, slot in ipairs(NS.CDM.SLOTS) do
        if slot.key == slotKey then return BuildRow(slot, S.Config("cooldownManager")) end
    end
end
function S.CDMInspectionRows()
    local rows, config = {}, S.Config("cooldownManager")
    for _, slot in ipairs(NS.CDM.SLOTS) do rows[#rows + 1] = BuildRow(slot, config) end
    return rows
end
