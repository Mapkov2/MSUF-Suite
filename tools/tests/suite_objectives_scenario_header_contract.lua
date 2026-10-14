local root = assert(arg[1], "repository root required")

-- Native layout contract: upstream/ptr2 12380f8c, 12.1.5.70340,
-- Blizzard_UIWidgets/Blizzard_UIWidgetManager.lua (DefaultWidgetLayout,
-- RegisterForWidgetSet) and Blizzard_SharedXML/LayoutFrame.lua (ResizeLayout).
-- Registration lays out immediately; further native changes lay out later.
-- A vertical child uses the container's relative point on its predecessor.
local sets = {
    [888] = {
        { width = 318, height = 88 },
        { width = 280, height = 24 },
        { width = 250, height = 32 },
    },
    [889] = { { width = 250, height = 80 } },
    [890] = {
        { width = 318, height = 88 },
        { width = 280, height = 24, overlap = true },
    },
}
local padding, requests = 4, 0
local function Frame(parent)
    local frame = { parent = parent, shown = true, width = 1, height = 1, scale = 1 }
    function frame:GetParent() return self.parent end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:SetSize(width, height)
        if self.width == width and self.height == height then return end
        self.width, self.height = width, height
        if self.OnSizeChanged then self.OnSizeChanged(self) end
    end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetScale(scale) self.scale = scale end
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function frame:HookScript(script, callback)
        local native = self[script]
        self[script] = function(...)
            if native then native(...) end
            callback(...)
        end
    end
    function frame:Show()
        if self.shown then return end
        self.shown = true
        if self.OnShow then self.OnShow(self) end
    end
    function frame:Hide()
        if not self.shown then return end
        self.shown = false
        if self.OnHide then self.OnHide(self) end
    end
    return frame
end

local function Container(parent)
    local frame = Frame(parent)
    frame.registrations = 0
    function frame:Layout()
        -- ResizeLayout resets its own size before measuring child extents.
        self:SetSize(1, 1)
        local width, height, previousTop, previousHeight = 1, 1, 0, 0
        for index, widget in ipairs(self.widgets or {}) do
            local top = 0
            if index > 1 then
                top = previousTop
                if not widget.overlap then
                    if self.verticalRelativePoint == "BOTTOMLEFT" then top = top + previousHeight end
                    top = top + padding
                end
            end
            width, height = math.max(width, widget.width), math.max(height, top + widget.height)
            previousTop, previousHeight = top, widget.height
        end
        self:SetSize(width, height)
    end
    function frame:RegisterForWidgetSet(id)
        if self.widgetSetID == id then return end
        self.registrations = self.registrations + 1
        self.widgetSetID, self.widgets = id, sets[id]
        self:Layout()
        if id then self:Show() else self:Hide() end
    end
    function frame:HasAnyWidgetsShowing() return self.widgets and #self.widgets > 0 or false end
    frame.OnShow = frame.Layout
    return frame
end

local O = { RequestScenarioLayout = function() requests = requests + 1 end }
local suite = { CreateFrame = function(kind, name, parent, template)
    assert(kind == "Frame" and name == nil and template == "UIWidgetContainerTemplate")
    return Container(parent)
end }
assert(loadfile(root .. "/MSUF_Suite_Modules/ObjectivesDetails.lua"))(
    "MSUF_Suite_Modules", { NS = {}, Suite = suite, Objectives = O })
local row = Frame()
row.text, row.collapse = Frame(row), Frame(row)
local item = { scenarioHeaderSetID = 888 }
local height = O.PaintScenarioHeader(row, item, 360)
local header = assert(row.scenarioHeader)
assert(header:GetHeight() == 152 and height == 158,
    "Labyrinth widgets overlap: reserve all three native widget heights and both gaps")
assert(not row.text.shown and header.shown and header.scale == 1,
    "a native Delve header must replace the ordinary scenario title")

-- The criteria start after the returned height, including the native bottom.
local function Fits(width, reserved)
    assert(header:GetWidth() * header.scale <= width - 42 + .001,
        "the native header exceeds the container width available beside the controls")
    assert(reserved >= header:GetHeight() * header.scale + 6 - .001,
        "the next objective row overlaps the native scenario header")
end
Fits(360, height)
local registrations = header.registrations
height = O.PaintScenarioHeader(row, item, 240)
Fits(240, height)
assert(header.registrations == registrations and header.scale < 1,
    "narrowing the tracker must reuse and scale the existing widget set")
height = O.PaintScenarioHeader(row, item, 500)
Fits(500, height)
assert(header.scale == 1, "widening the tracker must restore the native size")

-- A native update changes geometry before the coalesced Suite repaint.
row.layoutHeight = height
sets[888][2].height = 54
local before = requests
header:Layout()
assert(requests > before and row.layoutHeight == nil,
    "a native widget resize must invalidate the Suite row and request layout")
height = O.PaintScenarioHeader(row, item, 360)
assert(header:GetHeight() == 182 and height == 188,
    "a native update must reserve the new cumulative height")

-- Hide/show releases and restores the same active set, including its layout.
header:Hide()
assert(header.widgetSetID == nil, "hiding the native header retained widget updates")
header:Show()
assert(header.widgetSetID == 888 and header:GetHeight() == 182,
    "reopening the header lost its set or cumulative native layout")
height = O.PaintScenarioHeader(row, item, 360)
Fits(360, height)

-- Switching stages reuses the container; native intentional overlap stays so.
item.scenarioHeaderSetID = 890
height = O.PaintScenarioHeader(row, item, 360)
assert(header:GetHeight() == 88 and height == 94,
    "an intentionally overlapping native effect must not add a separate row")
item.scenarioHeaderSetID = 889
height = O.PaintScenarioHeader(row, item, 360)
assert(header == row.scenarioHeader and header:GetHeight() == 80 and height == 86,
    "ordinary single-widget Delves must retain their existing layout")
item.scenarioHeaderSetID = nil
assert(O.PaintScenarioHeader(row, item, 360) == 0 and row.text.shown
    and not header.shown and header.widgetSetID == nil,
    "leaving the Delve must restore the title and release native widgets")
print("Suite multi-widget Delve header layout contract passed")
