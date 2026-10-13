local _, P = ...
local S = P.Suite
local function Descending(a, b)
    if a.kb == b.kb then return a.name < b.name end
    return a.kb > b.kb
end

-- upstream/ptr PerformanceDocumentation and AddOnsDocumentation:
-- memory usage is KB; the refresh is a global API, addon metadata uses C_AddOns.
function P.MemoryTooltip(tooltip)
    if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then return end
    UpdateAddOnMemoryUsage()
    local rows, total = {}, 0
    for index = 1, C_AddOns.GetNumAddOns() do
        local kb = GetAddOnMemoryUsage(index)
        if S.Finite(kb) and kb > 0 then
            local name = C_AddOns.GetAddOnInfo(index)
            if S.Public(name) and type(name) == "string" then
                rows[#rows + 1] = { name = name, kb = kb }
                total = total + kb
            end
        end
    end
    table.sort(rows, Descending)
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
