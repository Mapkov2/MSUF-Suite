-- Native locale companions add installed-addon slots. Quantify their existing
-- memory-reader cost without changing the memory providers or cache cadence.
local root = assert(arg[1])
local function Run(extra, selected)
    local now, reads, updates, metadata, addonLoaded = 0, 0, 0, 0
    local addonSize = 2048
    local S = { Dispatch = function(fn) return fn() end, Text = function(text) return text end,
        Public = function() return true end, PublicText = function(text) return text end,
        Finite = function(value) return type(value) == "number" and value == value and value < math.huge end }
    local env = setmetatable({ GetTime = function() return now end,
        EventRegistry = { RegisterFrameEventAndCallback = function(_, event, callback, owner)
            assert(event == "ADDON_LOADED" and owner == S and not addonLoaded)
            addonLoaded = callback
        end },
        UpdateAddOnMemoryUsage = function() updates = updates + 1 end,
        GetAddOnMemoryUsage = function(index)
            reads = reads + 1
            if index == 1 then return 1024 end
            if index == 2 then return addonSize end
            return selected and index == 3 and 256 or 0
        end,
        C_AddOns = { GetNumAddOns = function() return 2 + extra end,
            GetAddOnInfo = function(index)
                metadata = metadata + 1
                return index <= 2 and ("Addon" .. index) or "MSUF_Suite_Locales"
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
    local tooltip = { AddLine = function() end,
        AddDoubleLine = function(_, name, amount) rows[#rows + 1] = name .. "=" .. amount end }
    P.MemoryTooltip(tooltip)
    assert(updates == 2 and reads == initialReads * 3, "details repeated the same frame's global RAM scan")
    assert(metadata == (selected and 3 or 2) and #rows == (selected and 4 or 3))
    local details = table.concat(rows, "\n")
    now = 60
    P.MemoryTooltip(tooltip)
    assert(updates == 3, "first hover in a new frame did not refresh the data")
    assert(S.ReadInfoSource("memory") == expected and updates == 3, "a due total repeated the tooltip's scan")
    addonSize = addonSize + 1024
    addonLoaded(S, "NewLoadOnDemandAddon")
    assert(S.ReadInfoSource("memory") == expected + 1 and updates == 4, "an addon load left a stale total")
    P.MemoryTooltip(tooltip)
    assert(updates == 4, "the tooltip repeated the new addon's measurement")
    S.InvalidateSharedData("memory")
    assert(S.ReadInfoSource("memory") == expected + 1 and updates == 5, "an explicitly invalidated profile reused a scan")
    now = 62
    addonSize = addonSize + 1024
    addonLoaded(S, "AnotherAddon")
    assert(S.ReadInfoSource("memory") == expected + 1 and updates == 5, "a later addon load expired a two-second-old total")
    P.MemoryTooltip(tooltip)
    assert(updates == 6 and rows[#rows] == ("Addon memory=%.2f MB"):format(expected + 2),
        "the first hover after the addon load missed the new memory usage")
    addonLoaded(S, "AnotherAddonInTheTooltipFrame")
    assert(S.ReadInfoSource("memory") == expected + 1 and updates == 6, "a tooltip invalidated a total from an older frame")
    P.MemoryTooltip(tooltip)
    assert(updates == 7, "a same-frame addon load kept stale tooltip details")
    now = 90
    assert(S.ReadInfoSource("memory") == expected + 2 and updates == 8, "the total lost its original 30s deadline")
    return details, initialReads
end
local before, oldReads = Run(0, false)
local after, newReads = Run(1, false)
assert(before == after and newReads == oldReads + 1, "unloaded locale slots changed memory totals/rows")
local selected = Run(1, true)
assert(selected:find("MSUF_Suite_Locales=256.00 KB", 1, true), "loaded companion was hidden from native memory ownership")
print("PASS 30s RAM refresh, same-frame total and details, loaded addon invalidation, locale totals and rows")
