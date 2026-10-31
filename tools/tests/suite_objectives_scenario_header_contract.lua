local root = assert(arg[1], "repository root required")
-- Regression for the actual native 12.1.5 unresolved-rect/OnShow lifecycle.
-- The previous fixed-size fixture did not exercise these native transitions.
function CreateFromMixins(...)
    local result = {}
    for i = 1, select('#', ...) do
        for key, value in pairs(select(i, ...) or {}) do result[key] = value end
    end
    return result
end
function CreateColor() return {} end
function RoundToNearestMultiple(value) return value end
function Clamp(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end
FunctionUtil = { SafeInvokeMethod = function(object, method, ...) if object[method] then return object[method](object, ...) end end }
Enum = { UIWidgetSetLayoutDirection = { Vertical = 1, Overlap = 2 }, UIWidgetLayoutDirection = { Default = 0, Vertical = 1, Overlap = 2, HorizontalForceNewRow = 3 } }


-- CI boundary for the one-card case, cross-checked with the actual native
-- functions from live18c6d677. Optional arg2 loads those functions directly.
-- GetScaledRect remains an explicit engine boundary in both runs.
if arg[2] then
    dofile(arg[2])
else
    BaseLayoutMixin = { OnShow = function(self) self:Layout() end }
    ResizeLayoutMixin = {}
    UIWidgetContainerMixin = {}
    UIWidgetContainerResizeMixin = {}
    function ResizeLayoutMixin:Layout()
        self:SetSize(1, 1)
        local width, height = 1, 1
        for _, widget in pairs(self.widgetFrames or {}) do
            local left, _, w, h = widget:GetScaledRect()
            if left then
                local scale = self:GetEffectiveScale()
                width, height = math.max(width, w / scale), math.max(height, h / scale)
            end
        end
        self:SetSize(width, height)
        self.dirty = false
        self:SetScript('OnUpdate', nil)
    end
    function UIWidgetContainerMixin:RegisterForWidgetSet(id)
        if self.widgetSetID == id then return end
        if self.widgetSetID then self:UnregisterForWidgetSet() end
        if not id then return end
        self.widgetSetID, self.widgetFrames = id, {}
        self:ProcessWidget(902, 29)
        self:Layout()
        self:Show()
    end
    function UIWidgetContainerMixin:UnregisterForWidgetSet()
        if not self.widgetSetID then return end
        self.widgetFrames = {}
        self:Layout()
        self.widgetSetID = nil
        self:Hide()
    end
    function UIWidgetContainerMixin:HasAnyWidgetsShowing() return next(self.widgetFrames or {}) ~= nil end
    function ResizeLayoutMixin:MarkDirty()
        self.dirty = true
        self:SetScript('OnUpdate', self.Layout)
    end
    function ResizeLayoutMixin:IsDirty() return self.dirty end
end
local row
local native = arg[2] ~= nil
local function DispatchShow(frame)
    if not frame.shown then return end
    local callback = frame.scripts.OnShow
    if callback then callback(frame) end
    for _, child in ipairs(frame.children) do DispatchShow(child) end
end
local function Frame(parent)
    local frame = { parent = parent, shown = true, width = 0, height = 0, scale = 1, children = {}, scripts = {} }
    if parent then parent.children[#parent.children + 1] = frame end
    function frame:GetParent() return self.parent end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetScale() return self.scale end
    function frame:GetSize() return self.width, self.height end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:GetAlpha() return self.alpha or 1 end
    function frame:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
    function frame:SetSize(width, height)
        if self.width == width and self.height == height then return end
        self.width, self.height = width, height
        if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self) end
    end
    function frame:SetWidth(width) self:SetSize(width, self.height) end
    function frame:SetHeight(height) self:SetSize(self.width, height) end
    function frame:GetScaledRect()
        -- Explicit engine boundary: the initial native rectangle is unresolved.
        -- Resolve it when the reused Suite row becomes visible.
        if not row.rectReady then return nil end
        local scale = self:GetEffectiveScale()
        return 0, 0, self.width * scale, self.height * scale
    end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:ClearAllPoints() self.point = nil end
    function frame:GetNumPoints() return self.point and 1 or 0 end
    function frame:GetFrameLevel() return 1 end
    function frame:SetFrameLevel() end
    function frame:SetParent(parent) self.parent = parent end
    function frame:SetScale(value) self.scale = value end
    function frame:GetChildren() return unpack(self.children) end
    function frame:GetRegions() end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function frame:GetScript(script) return self.scripts[script] end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:HookScript(script, callback)
        local previous = self.scripts[script]
        self.scripts[script] = function(...) if previous then previous(...) end; callback(...) end
    end
    function frame:Show()
        if self.shown then return end
        self.shown = true
        if self == row and self.resolveOnShow then self.rectReady = true end
        if self:IsVisible() then DispatchShow(self) end
    end
    function frame:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
    function frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:EnableMouse() end
    function frame:SetText(text) self.text = text end
    function frame:SetTextColor() end
    function frame:SetColorTexture() end
    function frame:GetStringHeight() return 20 end
    return frame
end
UIParent = Frame()
C_UIWidgetManager = {
    GetWidgetSetInfo = function() return { layoutDirection = Enum.UIWidgetSetLayoutDirection.Vertical, verticalPadding = 0 } end,
    GetAllWidgetsBySetID = function() return { { widgetID = 902, widgetType = 29 } } end,
}
UIWidgetManager = { OnWidgetContainerRegistered = function() end, OnWidgetContainerUnregistered = function() end }
local O = { M = {}, SOURCES = {} }
local requests = 0
function O.RequestScenarioLayout() requests = requests + 1; O.M.layoutDirty = true end
local Suite = {
    Text = function(text) return text end,
    Finite = function(value) return type(value) == 'number' end,
    SetStyledFont = function() end,
}
function Suite.CreateFrame(_, _, parent, template)
    assert(template == 'UIWidgetContainerTemplate')
    local frame = Frame(parent)
    for key, value in pairs(CreateFromMixins(ResizeLayoutMixin, UIWidgetContainerMixin, UIWidgetContainerResizeMixin)) do frame[key] = value end
    frame.showAndHideOnWidgetSetRegistration = true
    frame.verticalAnchorPoint, frame.verticalRelativePoint = 'TOP', 'BOTTOM'
    frame.horizontalAnchorPoint, frame.horizontalRelativePoint = 'LEFT', 'RIGHT'
    frame.horizontalAnchorXOffset = 2
    frame.horizontalRowContainerPool = { ReleaseAll = function() end }
    frame.widgetPools = { ReleaseAll = function() for _, child in ipairs(frame.children) do child.shown = false end end }
    frame:SetScript('OnShow', BaseLayoutMixin.OnShow)
    function frame:ProcessWidget(widgetID, widgetType)
        local widget = Frame(self)
        widget.width, widget.height = 318, 88
        widget.orderIndex, widget.widgetID, widget.layoutDirection = 1, widgetID, Enum.UIWidgetLayoutDirection.Default
        self.widgetFrames[widgetID] = widget
    end
    return frame
end
local P = { NS = { Client = { isForever = false }, HUDTextArgs = function() end }, Suite = Suite, Objectives = O }
assert(loadfile(root .. '/MSUF_Suite_Modules/ObjectivesDetails.lua'))('Suite', P)
assert(loadfile(root .. "/MSUF_Suite_Modules/ObjectivesRows.lua"))("Suite", P)
local file = assert(io.open(root .. '/MSUF_Suite_Modules/ObjectivesTracker.lua', 'rb'))
local tracker = file:read('*a'); file:close()
assert(loadstring(tracker .. '\nO.TestPaintRow, O.TestPaintRows = PaintRow, PaintRows'))('Suite', P)

local function Scenario(shown, resolveOnShow)
    requests = 0
    row = Frame(UIParent)
    row.shown, row.rectReady, row.resolveOnShow = shown, false, resolveOnShow
    row.text, row.stripe, row.collapse, row.progress = Frame(row), Frame(row), Frame(row), Frame(row)
    local state = O.M
    state.layoutDirty = nil
    state.content, state.groupRGB, state.font = UIParent, { scenario = {1,1,1} }, 'font'
    state.textRGB, state.mutedRGB, state.completeRGB = {1,1,1}, {1,1,1}, {1,1,1}
    state.rows, state.freeRows = { entry = row }, {}
    local item = { key = 'entry', group = 'scenario', kind = 'entry', text = 'Choose Your Path',
        height = 30, scenarioHeaderSetID = 888 }
    return state, item
end

-- Reused hidden rows: the native OnShow resolves its rect and invalidates the
-- Suite row while PaintRow is still on the stack. That invalidation must survive.
local state, item = Scenario(false, true)
local height = O.TestPaintRow(state, row, item, {}, 340, 0)
local header = row.scenarioHeader
assert(header:GetHeight() == 88, 'native OnShow must resolve its dimensions')
assert(height >= 88 * header:GetScale() + 6,
    'a reused row with resolvable geometry must reserve the native height on its first paint')
local followup = O.TestPaintRows(state, { width = 354 }, { item }, 1, { item }, false)
assert(followup >= 88 * header:GetScale() + 6,
    'Labyrinth header reached 88px, but the queued Suite repaint reused the 30px row cache')
assert(header:GetWidth() * header:GetScale() <= 340 - 42 + .001,
    'the resolved native header extends past the available tracker width')

-- A final size setter can itself release a pending native resize. Its
-- invalidation must survive the return from PaintRow as well as OnShow.
local setHeight = row.SetHeight
local changed = false
row.SetHeight = function(self, value)
    setHeight(self, value)
    if value > 40 and not changed then
        changed = true
        header.widgetFrames[902]:SetHeight(124)
        header:Layout()
    end
end
O.TestPaintRow(state, row, item, {}, 340, 0)
assert(changed and row.layoutHeight == nil,
    'PaintRow overwrote native invalidation raised by its final height setter')
followup = O.TestPaintRows(state, { width = 354 }, { item }, 1, { item }, false)
assert(followup >= 124 * header:GetScale() + 6,
    'the queued repaint ignored a native resize raised during PaintRow')

-- Cold rows are already shown. A native unresolved rect is 1x1, not zero.
-- The header stays transparent until a bounded native layout pass resolves it.
state, item = Scenario(true, false)
height = O.TestPaintRow(state, row, item, {}, 340, 0)
header = row.scenarioHeader
assert(header:GetWidth() == 1 and header:GetHeight() == 1, 'the native unresolved-rect condition was not exercised')
assert(header:GetAlpha() == 0 and row.text.shown,
    'an unresolved native card must not cover the ordinary scenario text')
local retry = header:GetScript('OnUpdate')
assert(retry, 'an unresolved native header needs one deferred native layout pass')
row.rectReady = true
retry(header, 0)
assert(not header:GetScript('OnUpdate'), 'native layout must stop after resolving the rect')
followup = O.TestPaintRows(state, { width = 354 }, { item }, 1, { item }, false)
assert(followup >= 88 * header:GetScale() + 6 and header:GetAlpha() == 1 and not row.text.shown,
    'the first valid native layout must restore the card and reserve its actual height')

-- The same content must become idle; no repeated native layout or registration.
local before = requests
followup = O.TestPaintRows(state, { width = 354 }, { item }, 1, { item }, false)
assert(requests == before and not header:GetScript('OnUpdate'),
    'an unchanged Delve header must not keep requesting layout')

-- If the engine rectangle is still invalid, the retry must become idle.
-- Later widget events or visibility changes remain native-owned triggers.
state, item = Scenario(true, false)
O.TestPaintRow(state, row, item, {}, 340, 0)
header = row.scenarioHeader
retry = assert(header:GetScript('OnUpdate'))
retry(header, 0)
assert(not header:GetScript('OnUpdate') and header:GetAlpha() == 0,
    'an unresolved native rectangle must not leave an update loop running')
before = requests
for i = 1, 10 do O.PaintScenarioHeader(row, item, 340) end
assert(requests == before and not header:GetScript('OnUpdate'),
    'repainting an unchanged unresolved header must not restart its retry')
header:Hide()
header:Show()
O.PaintScenarioHeader(row, item, 340)
assert(header:GetScript('OnUpdate'), 'reopening an unresolved header must permit one fresh native retry')
row.rectReady = true
header:GetScript('OnUpdate')(header, 0)
O.PaintScenarioHeader(row, item, 340)

-- Existing native geometry, width changes and hide/show retain the same set.
height = O.PaintScenarioHeader(row, item, 240)
assert(height >= 88 * header:GetScale() + 6 and header:GetWidth() * header:GetScale() <= 198 + .001,
    'narrow tracker geometry did not fit the native card')
height = O.PaintScenarioHeader(row, item, 500)
assert(header:GetScale() == 1 and height >= 94, 'widening the tracker lost native height')
header:Hide()
assert(header.widgetSetID == nil, 'hiding the card retained widget updates')
header:Show()
assert(header.widgetSetID == 888, 'reopening the card lost its active set')
item.scenarioHeaderSetID = nil
assert(O.PaintScenarioHeader(row, item, 340) == 0 and row.text.shown and not header.shown,
    'leaving the Delve must restore the ordinary title and release native widgets')
print('Suite Labyrinth native layout lifecycle contract passed (' .. (native and 'actual live functions' or 'engine boundary fixture') .. ')')
