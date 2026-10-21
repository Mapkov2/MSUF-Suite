-- Native locale companions add installed-addon slots. Quantify their existing
-- memory-reader cost without changing the memory providers or cache cadence.
local root = assert(arg[1])
local function Run(extra, selected)
    local now, reads, updates, metadata = 0, 0, 0, 0
    local S = { Dispatch = function(fn) return fn() end, Text = function(text) return text end,
        Public = function() return true end, PublicText = function(text) return text end,
        Finite = function(value) return type(value) == "number" and value == value and value < math.huge end }
    local env = setmetatable({ GetTime = function() return now end,
        UpdateAddOnMemoryUsage = function() updates = updates + 1 end,
        GetAddOnMemoryUsage = function(index)
            reads = reads + 1
            if index == 1 then return 1024 end
            if index == 2 then return 2048 end
            return selected and index == 3 and 256 or 0
        end,
        C_AddOns = { GetNumAddOns = function() return 2 + extra end,
            GetAddOnInfo = function(index)
                metadata = metadata + 1
                return index <= 2 and ("Addon" .. index) or "MSUF_Suite_Locale_deDE"
            end },
    }, { __index = _G })
    setfenv(assert(loadfile(root .. "/MSUF_Suite_Modules/DataSources.lua")), env)("MSUF_Suite_Modules", { Suite = S })
    local expected = selected and 3.25 or 3
    assert(S.ReadInfoSource("memory") == expected)
    local initialReads = reads
    assert(S.ReadInfoSource("memory") == expected and reads == initialReads and updates == 1)
    now = 29
    assert(S.ReadInfoSource("memory") == expected and reads == initialReads and updates == 1)
    now = 30
    assert(S.ReadInfoSource("memory") == expected and reads == initialReads * 2 and updates == 2)
    local P = { Suite = S }
    setfenv(assert(loadfile(root .. "/MSUF_Suite_DataTexts/Memory.lua")), env)("MSUF_Suite_DataTexts", P)
    local rows = {}
    P.MemoryTooltip({ AddLine = function() end,
        AddDoubleLine = function(_, name, amount) rows[#rows + 1] = name .. "=" .. amount end })
    assert(updates == 3 and reads == initialReads * 3)
    assert(metadata == (selected and 3 or 2) and #rows == (selected and 4 or 3))
    return table.concat(rows, "\n"), initialReads
end
local before, oldReads = Run(0, false)
local after, newReads = Run(10, false)
assert(before == after and newReads == oldReads + 10, "unloaded locale slots changed memory totals/rows")
local selected = Run(10, true)
assert(selected:find("MSUF_Suite_Locale_deDE=256.00 KB", 1, true), "loaded companion was hidden from native memory ownership")
print("Suite locale memory footprint: 10 zero-usage slots preserve totals/rows and30s cache; +10 native reads per existing sample/tooltip, selected pack reported")
