local _, P = ...
local S = P.Suite
local function Descending(a, b)
    if a.kb == b.kb then return a.name < b.name end
    return a.kb > b.kb
end

function P.MemoryTooltip(tooltip)
    tooltip:AddLine(S.Text("Left-click") .. " - " .. S.Text("Refresh"), .7, .7, .7)
    local rows, total = S.GetAddonMemoryReport()
    if not rows then return end
    if not rows.sorted then
        table.sort(rows, Descending)
        rows.sorted = true
    end
    for _, row in ipairs(rows) do
        local share = row.kb / math.max(1, total)
        local unit = row.kb < 1024 and "KB" or "MB"
        local amount = row.kb < 1024 and row.kb or row.kb / 1024
        local value = string.format("%.2f %s - %.1f%%", amount, unit, share * 100)
        tooltip:AddDoubleLine(row.name, value, 1, .82, 0, share > .25 and 1 or .3, 1, .2)
    end
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(S.Text("Addon memory"), string.format("%.2f MB", total / 1024), 1, .82, 0, 1, .65, 0)
end
