local _, Private = ...
local NS, S = Private.NS, Private.Suite
-- A view of the reminder owner's last public evaluation. Opening preparation
-- never installs an aura listener or forces a second aura scan.
function S.PlanningReadiness()
    local owner = S.instances.buffReminders
    local row = { label = S.Text("Buffs and consumables"), status = "unknown", module = "buffReminders" }
    if NS.InCombat() then
        row.detail = S.Text("Check preparation outside combat.")
    elseif not owner or not owner.active then
        row.detail = S.Text("Enable Buff reminders to include their checks.")
    elseif not owner.list.entries or owner.list.needsFullRefresh or owner.listen.suspended then
        row.detail = S.Text("Waiting for the next reminder update.")
    else
        local missing, unknown, restock = 0, 0, 0
        for _, entry in ipairs(owner.list.entries) do
            local present = entry.present
            if entry.group then present = entry.own and entry.own.present end
            if entry.restock then restock = restock + 1
            elseif present == false then
                missing = missing + 1
            elseif present ~= true then
                unknown = unknown + 1
            end
        end
        row.status = missing + restock > 0 and "missing" or (unknown > 0 or #owner.list.entries == 0) and "unknown" or "ready"
        row.detail = S.Text("%d missing buffs · %d empty supplies · %d unavailable checks"):format(missing, restock, unknown)
    end
    return { row }
end
