local root = assert(arg[1])
local function Run(extra, selected)
    local now, reads, updates, metadata = 0, 0, 0, 0
    local addonSize = 2048
    local S = { Dispatch = function(fn) return fn() end, Text = function(text) return text end,
        Public = function() return true end, PublicText = function(text) return text end,
        Finite = function(value) return type(value) == "number" and value == value and value < math.huge end }
    local env = setmetatable({ GetTime = function() return now end,
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
    local P = { Suite = S, NS = {}, DataTextActions = {}, DataTexts = {}, SLOT_COUNT = 6 }
    local function Load(relative)
        setfenv(assert(loadfile(root .. "/MSUF_Suite_DataTexts/" .. relative .. ".lua")), env)("MSUF_Suite_DataTexts", P)
    end
    Load("Memory")
    Load("Standard")
    assert(not P.DataTextStandard.SAMPLED.memory and not P.DataTextStandard.INTERVAL.memory)
    Load("Bars")
    local noop = function() end
    local methods = { SetScript = function(self, key, callback) self[key] = callback end,
        RegisterForClicks = noop, EnableMouseWheel = noop, SetPoint = noop, SetJustifyH = noop, SetWordWrap = noop }
    local function Widget() return setmetatable({}, { __index = methods }) end
    S.CreateFrame, S.CreateFontString = Widget, Widget
    local paints = 0
    P.DataTexts.UpdateSource = function(_, key) assert(key == "memory"); paints = paints + 1 end
    env.GameTooltip = { IsOwned = function() return false end }
    local bar = { slots = {}, prefix = "bar1" }
    P.DataTextBars.EnsureSlots(bar, {})
    local button = bar.slots[1]
    button.source = "memory"
    local rows = {}
    local tooltip = { AddLine = noop, AddDoubleLine = function(_, name, amount) rows[#rows + 1] = name .. "=" .. amount end }
    P.MemoryTooltip(tooltip)
    assert(S.ReadInfoSource("memory") == nil and reads == 0 and updates == 0 and #rows == 0)
    button:OnClick("RightButton")
    assert(updates == 0)
    button:OnClick("LeftButton")
    assert(paints == 1 and updates == 1 and S.ReadInfoSource("memory") == expected)
    local initialReads = reads
    P.MemoryTooltip(tooltip)
    assert(reads == initialReads and metadata == (selected and 3 or 2) and #rows == (selected and 4 or 3))
    local details = table.concat(rows, "\n")
    addonSize = addonSize + 1024
    for _, time in ipairs({29, 30, 60, 90}) do
        now = time
        S.InvalidateSharedData("memory")
        assert(S.ReadInfoSource("memory") == expected)
        P.MemoryTooltip(tooltip)
        assert(updates == 1 and reads == initialReads, "an idle tick, invalidation or hover ran a global RAM scan")
    end
    P.DataTexts.active = true
    P.NS.DataTextSources, button.sourceIndex = { "Addon memory" }, 1
    tooltip.IsOwned = function(_, owner) return owner == button end
    tooltip.SetOwner, tooltip.Show = noop, noop
    tooltip.ClearLines = function() rows = {} end
    env.GameTooltip = tooltip
    button:OnClick("LeftButton")
    assert(updates == 2 and reads == 2 * initialReads and S.ReadInfoSource("memory") == expected + 1)
    assert(rows[#rows] == ("Addon memory=%.2f MB"):format(expected + 1), "the open tooltip did not update on click")
    button:OnClick("LeftButton")
    assert(updates == 2, "a same-frame duplicate click remeasured")
    return details, initialReads
end
local before, oldReads = Run(0, false)
local after, newReads = Run(1, false)
assert(before == after and newReads == oldReads + 1, "unloaded locale slots changed memory totals/rows")
local selected = Run(1, true)
assert(selected:find("MSUF_Suite_Locales=256.00 KB", 1, true), "loaded companion was hidden from native memory ownership")
print("PASS manual RAM measurement through the slot, cached totals/details and locale slot ownership")
