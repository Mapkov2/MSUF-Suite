local _, P = ...
local ID = "nameplates"
local Style = P.Suite.NameplateStyle
local RuleRow = P.RuleRow
local GateControls = P.GateControls

-- Both the section switch and NPC display selector are deliberate visibility
-- actions. Keep their native write in the same history point as the settings.
function P.SetFriendlyNameplateVisibility(scope, on, values)
    local key = P.Suite.NameplateExtensions.SkinKeys[scope]
    local ok, reason
    P.WithHistory(P.catalog[ID].rules[key].label, "suite:nameplates." .. key, function()
        ok, reason = P.Suite.SetFriendlyNameplates(scope, on, values)
        return ok
    end)
    if ok == nil then ok, reason = false, "Finish combat before editing the suite" end
    P.feedback[ID] = not ok and reason or nil
    P.Refresh()
    return ok, reason
end

local function SyncSwitch(entry, read, keyFn, editWhileOff)
    local widget = entry.widget
    local function Sync()
        local checked = not not read()
        if (not not widget:GetChecked()) ~= checked then widget:SetChecked(checked) end
        P.W.SetControlEnabled(widget, P.RuleEnabled(ID, entry.rule, keyFn, false, editWhileOff))
    end
    Sync()
    widget:HookScript("OnShow", Sync)
end

function P.GateControls(ctx, id, entries, keyFn, editWhileOff)
    GateControls(ctx, id, entries, keyFn, editWhileOff)
    if id ~= ID then return end
    -- Nameplate controls can be built or shown between Menu2 refreshes.
    for _, entry in ipairs(entries) do
        local row = entry.row
        local read = entry.checked or row and row.kind == "toggle" and row.get
        if entry.widget and read then SyncSwitch(entry, read, keyFn, editWhileOff) end
    end
end

-- Stored choice 1 is the legacy inherited value. Display the live choice for
-- those profiles and write an explicit value only after the user edits it.
local switches = {
    plateShowAll = "nameplateShowAll", plateOffscreen = "nameplateShowOffscreen",
    plateEnemyMinions = "nameplateShowEnemyMinions", plateEnemyMinus = "nameplateShowEnemyMinus",
    plateEnemyPets = "nameplateShowEnemyPets", plateEnemyGuardians = "nameplateShowEnemyGuardians",
    plateEnemyTotems = "nameplateShowEnemyTotems", plateFriendlyMinions = "nameplateShowFriendlyPlayerMinions",
    plateFriendlyPets = "nameplateShowFriendlyPlayerPets", plateFriendlyGuardians = "nameplateShowFriendlyPlayerGuardians",
    plateFriendlyTotems = "nameplateShowFriendlyPlayerTotems", plateClampTarget = "clampTargetNameplateToScreen",
    enemyCastEnabled = "nameplateShowCastBars",
    friendlyNpcDebuffs = "nameplateShowDebuffsOnFriendly", friendlyNameClassColor = "nameplateUseClassColorForFriendlyPlayerUnitNames",
    friendlyRealm = "nameplateShowFriendlyRealmName", playerGuildNames = "UnitNamePlayerGuild", playerTitles = "UnitNamePlayerPVPTitle",
    classColors = "nameplateShowClassColor", softTargetEnemy = "SoftTargetIconEnemy",
    softTargetFriend = "SoftTargetIconFriend", softTargetInteract = "SoftTargetIconInteract", softTargetIconGate = "SoftTargetNameplateSize",
}
local dependent
local function PrepareDependent()
    if dependent then return end
    dependent = {
        threatFlash = { "threatSignalMode", "nameplateThreatDisplay", 2 },
        threatHighlight = { "threatSignalMode", "nameplateThreatDisplay", 1 },
    }
    for index, key in ipairs({ "enemyCastSpellName", "enemyCastSpellIcon", "enemyCastSpellTarget", "enemyCastImportant",
        "enemyCastTargetHighlight" }) do dependent[key] = { "enemyCastDisplay", "nameplateCastBarDisplay", index } end
    for _, group in ipairs(Style.AuraGroups) do
        for key, bit in pairs(Style.AuraBits) do
            dependent[group.key .. key] = { group.key .. "AuraMode", group.cvar, bit }
        end
    end
end

local modes = { enemyCastDisplay = true, threatSignalMode = true, auraScaleMode = true,
    plateMaxDistanceMode = true, plateOccludedMode = true, plateSpacingMode = true, plateInsetMode = true }
for _, group in ipairs(Style.AuraGroups) do modes[group.key .. "AuraMode"] = true end

local labels = { enemyCastDisplay = "Customize castbar details", threatSignalMode = "Customize aggro indicators",
    auraScaleMode = "Set aura icon size", plateMaxDistanceMode = "Set maximum distance", plateOccludedMode = "Dim plates behind walls",
    plateSpacingMode = "Set stacked plate spacing", plateInsetMode = "Set screen edge margins" }

local function NativeFlag(cvar, bit, fallback)
    if bit then return Style.NativeBit(cvar, bit, fallback) end
    return Style.NativeToggle(cvar, fallback)
end

local function Number(cvar)
    local value = C_CVar.GetCVar(cvar)
    if P.Suite.Public(value) and (type(value) == "string" or type(value) == "number") then return tonumber(value) end
end

local function ModeChoice(key)
    if key == "friendlyNamesOnly" then return Style.NativeToggle("nameplateShowOnlyNameForFriendlyPlayerUnits", false) and 2 or 4 end
    if key == "enemyTextMode" then
        local flags = Style.CVarFlags(C_CVar.GetCVar("nameplateInfoDisplay"))
        local mode = flags and flags % 4 or 0
        return mode == 0 and 5 or mode + 1
    end
    if key == "nativeStyle" then return math.max(2, math.min(8, (Number("nameplateStyle") or 0) + 2)) end
    if key == "nativeSize" then return math.max(2, math.min(6, (Number("nameplateSize") or 2) + 1)) end
    if key == "selectionBorder" or key == "selectionDim" then return 4 end
    if key == "plateFadeDistance" then
        local opacity = Number("nameplateMinAlpha") or 0.6
        return opacity >= 1 and 2 or opacity < 0.6 and 4 or opacity > 0.6 and 3 or 5
    end
    if key == "plateShrinkDistance" then
        local scale = Number("nameplateMinScale") or 0.8
        return scale >= 1 and 2 or scale < 0.8 and 4 or scale > 0.8 and 3 or 5
    end
    if key == "plateMotionSpeed" then
        local speed = Number("nameplateMotionSpeed") or 0.025
        return speed >= 1 and 4 or speed >= 0.1 and 3 or speed <= 0.01 and 2 or 5
    end
    if key == "personalAuras" then return Style.NativeToggle("nameplateShowAllPersonalAuras", false) and 2 or 3 end
    local bit = ({ plateStackEnemy = 1, plateStackFriendly = 2 })[key]
    if bit then return NativeFlag("nameplateStackingTypes", bit, false) and 2 or 3 end
    bit = ({ plateSimpleMinion = 1, plateSimpleMinus = 2, plateSimpleFriendlyPlayer = 3, plateSimpleFriendlyNpc = 4 })[key]
    if bit then return NativeFlag("nameplateSimplifiedTypes", bit, false) and 2 or 3 end
    return 2
end

local function ToggleRow(row, key, get, set)
    row.kind, row.values = "toggle", nil
    row.get, row.set = get, set
    row.label = P.Tr(labels[key] or row.label)
end

local function EditFlag(key, group, on)
    if P.Get(ID, group[1]) == 2 then return P.Set(ID, key, on) end
    local values = { [group[1]] = 2 }
    for sibling, source in pairs(dependent) do
        if source[1] == group[1] then values[sibling] = NativeFlag(source[2], source[3], P.Get(ID, sibling)) end
    end
    values[key] = on
    return P.SetMany(ID, values)
end

function P.RuleRow(page, id, rule, keyFn, ...)
    if page == "suite_nameplates" and P.NameplatesStatus.IsOffset(rule.key) then return end
    local row = RuleRow(page, id, rule, keyFn, ...)
    if id ~= ID or not row then return row end
    PrepareDependent()
    local key = keyFn and keyFn(rule.key) or rule.key
    if key == "friendlyNPCs" then
        local get = row.get
        row.label = P.Tr("Display")
        row.values = function()
            return { { value = 2, text = P.Tr("Health bars") }, { value = 4, text = P.Tr(rule.choices[4]) } }
        end
        row.get = function() return get() == 4 and 4 or 2 end
        row.set = function(value)
            if P.Get(ID, "enabled") then
                return P.SetFriendlyNameplateVisibility("friendlyNpc", P.Suite.FriendlyNameplateShown("friendlyNpc"),
                    { friendlyNPCs = value })
            end
            return P.SetMany(ID, { friendlyNPCs = value, friendlyNpcSkinEnabled = false })
        end
        return row
    end
    local peer = key == "enemyPowerSmooth" and "enemyPowerChunked" or key == "enemyPowerChunked" and "enemyPowerSmooth"
    if peer then
        local set = row.set
        if key == "enemyPowerSmooth" then
            local get = row.get
            row.get = function() return not P.Get(ID, peer) and get() end
        end
        row.set = function(on)
            if on then return P.SetMany(ID, { [key] = true, [peer] = false }) end
            return set(false)
        end
    end
    local group = dependent[key]
    if group then
        row.get = function()
            local stored = P.Get(ID, key)
            if P.Get(ID, group[1]) == 2 then return stored end
            return NativeFlag(group[2], group[3], stored)
        end
        row.set = function(on)
            local ok, reason = EditFlag(key, group, on == true)
            if ok then P.ShowNameplatesAuraSample(key) end
            return ok, reason
        end
        return row
    end
    local inherited = rule.choices and rule.choices[1]
    if inherited ~= "Keep Blizzard setting" and inherited ~= "Keep Blizzard settings" then return row end
    local get, set = row.get, row.set
    local cvar = switches[key]
    if cvar or key == "enemyRarityIcon" then
        ToggleRow(row, key, function()
            local mode = get()
            return mode == 2 or mode == 1 and NativeFlag(cvar or "nameplateInfoDisplay", not cvar and 3, false)
        end, function(on) return set(on and 2 or 3) end)
    elseif modes[key] then
        ToggleRow(row, key, function() return get() == 2 end, function(on) return set(on and 2 or 1) end)
    else
        local choices = {}
        for i = 2, #rule.choices do choices[#choices + 1] = { value = i, text = P.Tr(rule.choices[i]) } end
        row.values = function() return choices end
        row.get = function()
            local value = get()
            return value == 1 and ModeChoice(key) or value
        end
    end
    return row
end
