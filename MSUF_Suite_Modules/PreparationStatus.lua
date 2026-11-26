local _, Private = ...
local NS, S = Private.NS, Private.Suite
local function Entries()
    local owner = S.instances.buffReminders
    if owner and owner.active and not owner.list.needsFullRefresh and not owner.listen.suspended then
        return owner.list.entries
    end
end

local function PersonalState(entry)
    if entry.group then return entry.own and entry.own.present end
    return entry.present
end

local function ReminderName(entry)
    if entry.notice == "food" or entry.kind == "food" then return S.Text("Food") end
    if entry.kind == "spell" then
        return S.PublicText(entry.spellName) or S.PublicText(C_Spell.GetSpellName(entry.actionID or entry.id))
    end
    return S.PublicText(C_Item.GetItemInfo(entry.id))
end

-- The tools are checked on Ready Check only, using taught totems that
-- require each item. Low-level Shamans are not reminded about future tools.
local TOTEM_TOOLS = {
    { item = 5175, label = "Earth Totem", spells = { 8071, 2484, 8075, 8143 } },
    { item = 5176, label = "Fire Totem", spells = { 3599 } },
    { item = 5177, label = "Water Totem", spells = { 5394, 5675 } },
    { item = 5178, label = "Air Totem", spells = { 8177, 10595, 8512 } },
}

local function NeedsTool(spells)
    for _, spell in ipairs(spells) do
        local learned = C_SpellBook.IsSpellKnownOrInSpellBook(spell, Enum.SpellBookSpellBank.Player, false)
        if S.Public(learned) and learned == true then return true end
    end
    return false
end

local function MissingTotemTools(lines)
    if not (NS.Client and NS.Client.isForever) then return 0 end
    local _, class = UnitClass("player")
    if not S.Public(class) or class ~= "SHAMAN" then return 0 end
    local skipped = 0
    for _, tool in ipairs(TOTEM_TOOLS) do
        if NeedsTool(tool.spells) then
            local count = C_Item.GetItemCount(tool.item, false, false, false)
            if S.Finite(count) and count == 0 then
                if #lines < 6 then
                    local name = S.PublicText(C_Item.GetItemNameByID(tool.item)) or S.Text(tool.label)
                    lines[#lines + 1] = S.Text("Missing %s"):format(name)
                else
                    skipped = skipped + 1
                end
            end
        end
    end
    return skipped
end

-- Read the reminder owner's evaluated entries and public bag counts on Ready Check.
function S.ReadyCheckPreparation()
    if NS.InCombat() then return end
    local lines, unseen, route = {}, 0
    local loadout = S.PlanningLoadoutIssues and S.PlanningLoadoutIssues()
    if loadout and #loadout > 0 then
        route = "loadouts"
        for i = 1, #loadout do lines[#lines + 1] = loadout[i] end
    end
    local alert = S.instances.durabilityAlert
    local threshold = alert and alert.active and alert.config.threshold or 30
    local durability = S.ReadInfoSource("durability")
    if S.Finite(durability) and durability >= 0 and durability < threshold / 100 then
        lines[#lines + 1] = S.Text("Low durability (%d%%)"):format(math.floor(durability * 100))
        route = route or "gear"
    end
    local entries = Entries()
    for i = 1, entries and #entries or 0 do
        local entry = entries[i]
        if not entry.dismissed and (entry.restock or PersonalState(entry) == false) then
            local name = ReminderName(entry)
            if name then
                route = route or "buffs"
                if #lines < 6 then
                    local format = entry.restock and S.Text("Restock %s") or S.Text("Missing %s")
                    lines[#lines + 1] = format:format(name)
                else
                    unseen = unseen + 1
                end
            end
        end
    end
    local beforeTools = #lines
    unseen = unseen + MissingTotemTools(lines)
    if #lines > beforeTools then route = route or "buffs" end
    if unseen > 0 then lines[#lines + 1] = S.Text("%d more preparation issues"):format(unseen) end
    if #lines > 0 then return table.concat(lines, "\n"), route end
end

-- A view of the reminder owner's last public evaluation. Opening preparation
-- never installs an aura listener or forces a second aura scan.
function S.PlanningReadiness()
    local owner = S.instances.buffReminders
    local row = { label = S.Text("Buffs and consumables"), status = "unknown", module = "buffReminders" }
    if NS.InCombat() then
        row.detail = S.Text("Check preparation outside combat.")
    elseif not owner or not owner.active then
        row.detail = S.Text("Enable Buff reminders to include their checks.")
    elseif not Entries() then
        row.detail = S.Text("Waiting for the next reminder update.")
    else
        local missing, unknown, restock = 0, 0, 0
        for _, entry in ipairs(owner.list.entries) do
            local present = PersonalState(entry)
            if entry.restock then restock = restock + 1
            elseif present == false then
                missing = missing + 1
            elseif present ~= true then
                unknown = unknown + 1
            end
        end
        row.status = missing + restock > 0 and "missing" or (unknown > 0 or #owner.list.entries == 0) and "unknown" or "ready"
        row.detail = S.Text("%d missing buffs · %d empty supplies · %d unavailable checks", true):format(missing, restock, unknown)
    end
    return { row }
end
