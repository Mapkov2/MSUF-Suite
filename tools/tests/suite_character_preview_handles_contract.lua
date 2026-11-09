local root = assert(arg[1])
local function Load(path, namespace)
    return assert(loadfile(root .. "/" .. path))("MSUF_Suite", namespace)
end

local Methods = {}
Methods.__index = Methods
local function Frame(kind, _, parent)
    local frame = setmetatable({ kind = kind, parent = parent, children = {}, scripts = {}, shown = true }, Methods)
    if parent then parent.children[#parent.children + 1] = frame end
    return frame
end
CreateFrame = Frame
function wipe(values) for key in pairs(values) do values[key] = nil end end
function SetPortraitTexture() end

function Methods:SetScript(event, callback) self.scripts[event] = callback end
function Methods:Fire(event, ...)
    if self.scripts[event] then return self.scripts[event](self, ...) end
end
function Methods:IsShown() return self.shown end
function Methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
local function Visibility(frame, shown)
    if frame.shown then
        frame:Fire(shown and "OnShow" or "OnHide")
        for _, child in ipairs(frame.children) do Visibility(child, shown) end
    end
end
function Methods:SetShown(shown)
    if self.shown == shown then return end
    if self:IsVisible() then Visibility(self, false) end
    self.shown = shown
    if self:IsVisible() then Visibility(self, true) end
end
function Methods:SetPoint(_, x, y) self.left, self.top = x, y end
function Methods:ClearAllPoints() self.left, self.top = nil, nil end
function Methods:SetAllPoints() end
function Methods:SetSize(width, height) self.width, self.height = width, height end
function Methods:SetHeight(height) self.height = height end
function Methods:SetWidth(width) self.width = width end
function Methods:GetEffectiveScale()
    return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1)
end
function Methods:SetFrameLevel(level) self.level = level end
function Methods:GetFrameLevel() return self.level or 1 end
function Methods:RegisterForClicks() assert(self.kind == "Button", "drag attached to a non-button frame") end
function Methods:EnableMouse() end
function Methods:EnableKeyboard() end
function Methods:SetMovable() end
function Methods:SetPropagateKeyboardInput() end
function Methods:SetTexture() end
function Methods:SetWordWrap() end
function Methods:SetJustifyH() end
function Methods:SetColorTexture() end
function Methods:SetTextColor() end
function Methods:SetText(value) self.value = value end
function Methods:GetUnboundedStringWidth() return #self.value * 6 end
function Methods:CreateTexture() return Frame("Texture", nil, self) end
function Methods:CreateFontString() return Frame("FontString", nil, self) end

local cursorX, cursorY, held
function GetCursorPosition() return cursorX, cursorY end
function IsMouseButtonDown() return held end

local function Press(button)
    cursorX, cursorY, held = 400, 300, true
    button:Fire("OnMouseDown", "LeftButton")
end

local function Move(button, x, y)
    local scale = button:GetEffectiveScale()
    cursorX, cursorY = 400 + x * scale, 300 + y * scale
    button:Fire("OnUpdate")
end

local function Release(button)
    held = false
    button:Fire("OnMouseUp", "LeftButton")
    button:Fire("OnClick", "LeftButton")
    assert(not button.scripts.OnUpdate, "idle button kept pointer updates")
end

local function Text(value) return value end
local function Noop() end

local function Run(isForever)
    local config = { customTabs = "", tabOrder = "", inspectTabOrder = "" }
    local profile, combat, writes = 1, false, 0
    local selected, opened, moreClicks, marked = nil, nil, 0, 0
    local ui, positionMode, promoted = { mode = "own" }, false, nil
    local S = { Config = function() return config end, SetFont = Noop, GlobalFontPath = Noop }
    local suite = { Suite = S, Text = Text, ResolveFont = Noop, Skin = { Acquire = Noop },
        IsSecret = function() return false end, Number = tonumber, Client = { isForever = isForever } }
    Load("MSUF_Suite/Core/SuiteCatalog.lua", suite)
    Load("MSUF_Suite/Core/CharacterTabs.lua", suite)
    Load("MSUF_Suite/Core/Catalog/CharacterPanel.lua", suite)
    Load("MSUF_Suite/Core/CharacterHeader.lua", suite)
    Load("MSUF_Suite/Core/PreviewKit.lua", suite)
    local P = { S = S, Suite = suite, Tr = Text, M = {}, HM = { SkipHistoryCheckpoint = Noop },
        Combat = function() return combat end, T = { colors = { accent = { 1, .8, .4 } } } }
    P.ProfileGuard = function()
        local generation = profile
        return function() return generation == profile and not combat end
    end
    P.SetMany = function(id, values)
        assert(id == "characterPanel")
        for key, value in pairs(values) do config[key] = value end
        writes = writes + 1
        return true
    end
    P.Set = function(id, key, value) return P.SetMany(id, { [key] = value }) end
    Load("MSUF_Suite_Options/Menu/PreviewInteraction.lua", P)
    Load("MSUF_Suite_Options/Pages/CharacterPreviewHandles.lua", P)

    local parent = Frame("Frame")
    local frame = Frame("Frame", nil, parent)
    parent.scale, frame.scale = .8, .625
    local header = S.CharacterHeader.Create(frame, { field = Noop })
    local tabBar = Frame("Frame", nil, frame)
    local more = Frame("Button", nil, tabBar)
    more:SetScript("OnClick", function() moreClicks = moreClicks + 1 end)
    local view = { frame = frame, header = header, tabBar = tabBar, tabButtons = {}, moreTab = more }
    local handles
    local function Paint()
        local order = S.CharacterHeader.Order(config, ui.mode == "own" and "tab" or "inspectTab")
        view.tabs, view.visibleTabs, view.fontRevision = order, math.min(#order, 3), 1
        view.promotedTab = promoted
        for index, spec in ipairs(order) do
            local button = view.tabButtons[index] or Frame("Button", nil, tabBar)
            view.tabButtons[index], button.id = button, spec.id
            local x, y = suite.CharacterTabs.Position(spec)
            local column = index == promoted and view.visibleTabs + 1 or index
            button.panelX, button.panelY = (column - 1) * 100 + 50 + x, 10 - y
            button.panelWidth, button.panelHeight = 100, 24
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", button.panelX, -button.panelY)
            button:SetShown(index <= view.visibleTabs or index == promoted)
        end
        for index = #order + 1, #view.tabButtons do view.tabButtons[index]:SetShown(false) end
        header:Render(config, { name = "Mapko", level = 23, class = "Priest", itemLevel = "12" },
            nil, S.CharacterHeader.PreviewWidth, 0)
        handles:Refresh(order, positionMode)
    end

    handles = P.CharacterPreviewHandles.Create(ui, { view = view }, function(id) selected = id end,
        function(field) opened = field.id end, Paint, function() marked = marked + 1 end)
    Paint()
    local name, first, second, third = header.buttons.name, unpack(view.tabButtons, 1, 3)
    local idle = first.scripts.OnMouseDown
    Paint()
    assert(first.scripts.OnMouseDown == idle and not first.scripts.OnUpdate, "warm preview rebound its buttons")
    more:Fire("OnClick", "LeftButton")
    assert(moreClicks == 1 and not more.scripts.OnMouseDown, "overflow click was intercepted")
    promoted = 5
    Paint()
    local promotedButton = view.tabButtons[promoted]
    Press(promotedButton)
    Release(promotedButton)
    assert(selected == view.tabs[promoted].id and handles:Selected() == promotedButton,
        "promoted overflow tab was not interactive")
    Press(third)
    Move(third, 100, 0)
    assert(promotedButton._suitePreviewSelectionEdges.selected, "promoted tab was unavailable as a drop target")
    handles:Cancel()
    Release(third)
    promoted = nil
    Paint()
    assert(writes == 0, "cancelled tab drag stored a new order")

    Press(name)
    Move(name, 2, 0)
    Release(name)
    assert(opened == "name" and writes == 0 and marked > 0, "ordinary header click did not open field settings")
    opened = nil
    local left, top = name.left, name.top
    Press(name)
    Move(name, 12, 3)
    assert(name.left == left + 12 and name.top == top + 3 and writes == 0,
        "scaled header drag did not follow positive-up pointer motion without writing")
    Release(name)
    assert(config.headerNameX == 12 and config.headerNameY == 3 and writes == 1 and not opened,
        "header drag did not commit once or opened the field settings")

    Press(first)
    Release(first)
    assert(selected == "overview" and writes == 1, "ordinary tab click did not select the tab")
    selected = nil
    Press(first)
    Move(first, 100, 0)
    assert(second._suitePreviewSelectionEdges.selected and writes == 1, "tab drop target was not highlighted")
    Release(first)
    assert(config.tabOrder:match("^gear,overview,") and writes == 2 and not selected,
        "own tab drag did not reorder or also selected a tab")
    assert(handles:Selected() == second and second.spec.id == "overview", "reorder lost the dragged tab selection")

    Press(name)
    Move(name, 20, -4)
    profile = 2
    Release(name)
    assert(writes == 2 and not opened and name.left == left + 12, "stale profile gesture committed or opened settings")

    Press(name)
    Move(name, 20, -4)
    combat = true
    name:Fire("OnUpdate")
    Release(name)
    combat = false
    assert(writes == 2 and name.left == left + 12, "combat cancelled neither the drag nor its visual offset")

    Press(name)
    Move(name, 20, -4)
    frame:SetShown(false)
    Release(name)
    frame:SetShown(true)
    assert(writes == 2 and name.left == left + 12 and not handles:Selected(), "hidden preview retained drag or selection")

    Press(name)
    Move(name, 20, -4)
    frame.scale = .5
    Paint()
    Release(name)
    frame.scale = .625
    assert(writes == 2 and name.left == left + 12, "changed preview geometry accepted stale drag coordinates")

    local ownOrder = config.tabOrder
    handles:Release()
    ui.mode = "inspect"
    Paint()
    Press(first)
    Move(first, 200, 0)
    held = false
    first:Fire("OnUpdate")
    assert(not first.scripts.OnUpdate and config.inspectTabOrder == "gear,compare,overview"
        and config.tabOrder == ownOrder and writes == 3 and handles:Selected() == third,
        "Inspect reorder or mouse-up outside did not finish independently")

    handles:Release()
    ui.mode, positionMode = "own", true
    local tabs = {}
    local customID = assert(suite.CharacterTabs.Create(tabs, "empty", "Custom"))
    config.customTabs = assert(suite.CharacterTabs.Encode(tabs))
    config.tabOrder = customID .. "," .. ownOrder
    Paint()
    local tabLeft, tabTop = first.left, first.top
    Press(first)
    Move(first, 85, -40)
    assert(first.left == tabLeft + 48 and first.top == tabTop - 8 and writes == 3,
        "position mode did not use live custom-tab bounds or wrote before release")
    Release(first)
    local x, y = suite.CharacterTabs.Position(suite.CharacterTabs.Find(config, customID))
    assert(x == 48 and y == -8 and writes == 4 and config.tabOrder == customID .. "," .. ownOrder,
        "custom tab drag did not save clamped offsets independently of order")
    handles:SelectTab(customID)
    assert(handles:Nudge(-1, 1))
    x, y = suite.CharacterTabs.Position(suite.CharacterTabs.Find(config, customID))
    assert(x == 47 and y == -7 and writes == 5, "selected custom tab did not nudge in logical panel units")
end

Run(false)
Run(true)
print("Character Panel direct preview: scaled drag, click, tab order, offsets and teardown passed for both clients")
