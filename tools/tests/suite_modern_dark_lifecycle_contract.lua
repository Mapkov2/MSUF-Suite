local root = assert(arg[1])
local function Load(path, private) return assert(loadfile(root .. "/" .. path))("test", private) end
local S = {
    Public = function(v) return v ~= "secret" end,
    Finite = function(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end,
    Text = function(v) return v end,
}
local C = { M = { active = true, config = { completeMessages = true } } }
Load("MSUF_Suite_Chat/Positions.lua", { Chat = C, Suite = S })
Load("MSUF_Suite_Chat/CompleteMessages.lua", { Chat = C, Suite = S })
local function Line(top, bottom)
    return { top = top, bottom = bottom, color = { .2, .4, .6, 1 },
        GetTop = function(self) return self.top end,
        GetBottom = function(self) return self.bottom end,
        GetTextColor = function(self) return unpack(self.color) end,
        SetTextColor = function(self, ...) self.color = { ... } end }
end
local full, partial = Line(95, 75), Line(110, 98)
local frame = { visibleLines = { full, partial }, callbacks = {},
    GetTop = function() return 100 end, GetBottom = function() return 0 end,
    AddOnDisplayRefreshedCallback = function(self, fn) self.callbacks[#self.callbacks + 1] = fn end,
    MarkDisplayDirty = function(self) self.dirty = true end }
local function Refresh()
    for _, line in ipairs(frame.visibleLines) do line:SetTextColor(.2, .4, .6, 1) end
    for _, fn in ipairs(frame.callbacks) do fn(frame) end
    -- Blizzard's subsequent UpdateFading changes region alpha and visibility.
    for _, line in ipairs(frame.visibleLines) do line.alpha, line.shown = .7, true end
end
C.ApplyCompleteMessages(C.M, frame)
C.ApplyCompleteMessages(C.M, frame)
assert(#frame.callbacks == 1 and frame.dirty, "display callback duplicated or refresh missing")
Refresh()
assert(full.color[4] == 1 and partial.color[4] == 0, "partial message survived native fading")
partial.top, partial.bottom = 75, 55
Refresh()
assert(partial.color[4] == 1, "reused line stayed transparent inside viewport")
partial.top, partial.bottom = 110, 98
C.M.config.completeMessages = false
C.ApplyCompleteMessages(C.M, frame)
Refresh()
assert(partial.color[4] == 1, "disabled option retained hidden native text")

local reads, private = 0, { Suite = S }
UpdateAddOnMemoryUsage = function() reads = reads + 1 end
local names, amounts = { "Small", "Beta", "Alpha", "Zero", "Invalid", "secret" }, { 512, 2048, 2048, 0, 0/0, 200 }
C_AddOns = { GetNumAddOns = function() return #names end, GetAddOnInfo = function(i) return names[i] end }
GetAddOnMemoryUsage = function(i) return amounts[i] end
Load("MSUF_Suite_DataTexts/Memory.lua", private)
assert(reads == 0, "loading memory tooltip sampled APIs")
local rows = {}
local tooltip = { AddLine = function() end, AddDoubleLine = function(_, ...) rows[#rows + 1] = { ... } end }
private.MemoryTooltip(tooltip)
assert(reads == 1 and #rows == 4, "memory refresh or invalid addon filtering failed")
assert(rows[1][1] == "Alpha" and rows[2][1] == "Beta" and rows[3][1] == "Small", "usage sort/tie order failed")
assert(rows[1][2] == "2.00 MB - 44.4%" and rows[3][2] == "512.00 KB - 11.1%", "KB/MB or percentage incorrect")
assert(rows[4][1] == "Addon memory" and rows[4][2] == "4.50 MB", "memory total incorrect")

local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local calls, W = {}, nil
    W = H.New(root, flavor, { beforeModules = function(world)
        world.G.Kiosk = { IsEnabled = function() return false end }
        world.G.KeybindFrames_InQuickKeybindMode = function() return false end
        world.G.PVEFrame_ToggleFrame = function() calls.retail = (calls.retail or 0) + 1 end
        world.G.ToggleGroupFinderFrame = function() calls.forever = (calls.forever or 0) + 1 end
        world.G.date = function(format) if format == "%d" then return "12" end return os.date(format) end
    end })
    H.Enable(W, { captured = true, outerBorderSize = 2, outerBorderGap = 4, dungeonButton = true,
        infoCalendarDay = true, infoCalendarDayClassColor = true })
    W.Step()
    local MM, button = W.MM, W.MM.dungeonButton
    assert(button and button.width == 52 and button.height == 26, "minimap shortcut missing")
    local point, relative, relativePoint, x, y = button:GetPoint(1)
    assert(point == "TOPRIGHT" and relative == MM.host and relativePoint == "BOTTOMRIGHT" and x == 0 and y == -12,
        "minimap shortcut missed the reference corner")
    W.Click(button)
    assert(calls[flavor == "Forever" and "forever" or "retail"] == 1, "wrong client group finder opener")
    W.SetCombat(true)
    W.Click(button)
    assert(calls[flavor == "Forever" and "forever" or "retail"] == 1, "group finder opened in combat")
    W.SetCombat(false)
    assert(W.M.infoEntries.CalendarDay.label.text == "12", "calendar day did not reach runtime")
    assert(MM.outerEdges[1].shown, "outer minimap border missing")
    assert(W.S.SetMany("minimap", { dungeonButton = false, outerBorderSize = 0, infoCalendarDay = false }))
    assert(not button.shown and not MM.outerEdges[1].shown, "disabled minimap decorations retained")
end
print("Modern Dark clipping, memory tooltip and minimap lifecycle passed")
