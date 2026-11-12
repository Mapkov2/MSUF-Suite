local root = assert(arg[1], "repository root required")
local writes, nativeReads, subscriptions = 0, 0, 0

local function Write()
    writes = writes + 1
end

local function Widget(parent, kind)
    local widget = { parent = parent, kind = kind, shown = true, scripts = {}, points = {} }
    function widget:SetScript(event, callback)
        assert(event ~= "OnEvent" and event ~= "OnUpdate", "renderer installed a runtime driver")
        self.scripts[event] = callback
        Write()
    end
    function widget:RegisterEvent()
        subscriptions = subscriptions + 1
        error("renderer subscribed to a native event")
    end
    function widget:ClearAllPoints() self.points = {} Write() end
    function widget:SetPoint(...) self.points[#self.points + 1] = { ... } Write() end
    function widget:SetAllPoints(relative) self.allPoints = relative Write() end
    function widget:SetSize(width, height) self.width, self.height = width, height Write() end
    function widget:SetWidth(width) self.width = width Write() end
    function widget:SetHeight(height) self.height = height Write() end
    function widget:SetScale(scale) self.scale = scale Write() end
    function widget:SetFrameStrata(strata) self.strata = strata Write() end
    function widget:EnableMouse(mouse) self.mouse = mouse Write() end
    function widget:SetShown(shown) self.shown = shown == true Write() end
    function widget:Show() self.shown = true Write() end
    function widget:Hide()
        local wasShown = self.shown
        self.shown = false
        Write()
        if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function widget:SetText(text)
        assert(self.kind ~= "FontString" or self.font, "text painted without the shared font style")
        self.text = text
        Write()
    end
    function widget:SetValue(value) self.value = value Write() end
    function widget:SetTexCoord(...) self.texCoord = { ... } Write() end
    function widget:SetColorTexture(...) self.color = { ... } Write() end
    function widget:SetTexture(texture) self.texture = texture Write() end
    function widget:SetAtlas(atlas) self.atlas = atlas Write() end
    function widget:SetAlpha(alpha) self.alpha = alpha Write() end
    function widget:SetJustifyH(justify) self.justify = justify Write() end
    function widget:SetWordWrap(wrap) self.wrap = wrap Write() end
    function widget:SetTextColor(...) self.textColor = { ... } Write() end
    function widget:SetStatusBarColor(...) self.barColor = { ... } Write() end
    function widget:SetStatusBarTexture(texture) self.barTexture = texture Write() end
    function widget:SetMinMaxValues(minimum, maximum)
        self.minimum, self.maximum = minimum, maximum
        Write()
    end
    return widget
end

local function NativeRead()
    nativeReads = nativeReads + 1
    error("the renderer read native loot or time")
end

GetTime, GetLootRollItemInfo, GetLootRollTimeLeft, GetLootRollItemLink = NativeRead, NativeRead, NativeRead, NativeRead
GetActiveLootRollIDs, RollOnLoot = NativeRead, NativeRead
C_LootHistory = setmetatable({}, { __index = function() return NativeRead end })
C_Item = setmetatable({}, { __index = function() return NativeRead end })
UIParent = Widget()
ITEM_QUALITY_COLORS = {
    [1] = { r = 1, g = 1, b = 1 },
    [3] = { r = 0, g = .44, b = .87 },
    [4] = { r = .64, g = .21, b = .93 },
}

GameTooltip = Widget()
function GameTooltip:SetOwner(owner) self.owner = owner end
function GameTooltip:IsOwned(owner) return self.owner == owner end
function GameTooltip:SetHyperlink(link) self.link = link end
function GameTooltip:AddLine(text) self.line = text end

local function RGB(hex)
    return tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255
end

local palettes = {
    { background = "101010", border = "333333", accent = "3399cc", text = "eeeeee", muted = "aaaaaa" },
    { background = "151719", border = "575b58", accent = "b9ab86", text = "e9e9e4", muted = "b9bdb9" },
}
local Suite = {
    Public = function() return true end,
    Finite = function(value) return type(value) == "number" and value == value end,
    Text = function(text) return text end,
    CreateFrame = function(_, _, parent) return Widget(parent, "Frame") end,
    CreateTexture = function(parent) return Widget(parent, "Texture") end,
    CreateFontString = function(parent) return Widget(parent, "FontString") end,
    ResolveFont = function() return "Fonts\\FRIZQT__.TTF" end,
    GlobalFontPath = function() return "Fonts\\FRIZQT__.TTF" end,
    RGB = RGB,
    QoLStyle = function(config) return palettes[config.look or 1] end,
    QoLStyleText = function(region, _, font, size)
        region.font, region.fontSize = font, size
    end,
    QoLColor = function(region, hex, alpha)
        local r, g, b = RGB(hex)
        region:SetColorTexture(r, g, b, alpha)
    end,
    PlaceEdges = function(edges, _, width, r, g, b, alpha)
        for _, edge in ipairs(edges) do
            edge.width = width
            edge:SetColorTexture(r, g, b, alpha)
        end
    end,
}
local namespace = { NS = { AnchorPoints = { "CENTER", "TOPLEFT" } }, Suite = Suite }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/LootRollView.lua"))("MSUF_Suite_QualityOfLife", namespace)
local View = assert(namespace.LootRollView)

local config = {
    width = 380, rowHeight = 58, rowGap = 4, maxRows = 6, scale = 100,
    growth = 1, font = "", fontSize = 12, point = 1, x = 20, y = 30, look = 1,
    showItemLevel = true, showBind = true, showCounts = true,
    urgentTimer = true, urgentSeconds = 10,
}
for _, element in ipairs({ "icon", "name", "details", "result", "remaining", "timer", "buttons" }) do
    config[element .. "OffsetX"], config[element .. "OffsetY"], config[element .. "Size"] = 0, 0, 0
end
local active = {
    rollID = 17, name = "Blue sword", link = "|Hitem:17|h[Blue sword]|h", icon = 1234, quality = 3,
    itemLevel = 100, count = 2, bindOnPickUp = true,
    canNeed = true, canGreed = true, canTransmog = true, canDisenchant = true,
    endsAt = 100, duration = 100, counts = { [0] = 1, [1] = 3, [2] = 2, [3] = 0, [4] = 0 },
    rollNames = { [1] = "Player A\nPlayer B\nPlayer C" },
}
local completed = {
    name = "White shield", icon = 5678, quality = 1, finished = true, status = "winner",
    statusText = "Winner: Player A",
}
local calls, lastEntry, lastChoice = 0
local module = {
    config = config, visibleEntries = { active, completed },
    Choose = function(_, entry, choice)
        calls, lastEntry, lastChoice = calls + 1, entry, choice
    end,
}

local function Action(row, id)
    for _, action in ipairs(row.actions) do
        if action.action.id == id then return action end
    end
    error("missing action")
end

local function Near(actual, expected)
    assert(math.abs(actual - expected) < .0001, tostring(actual) .. " ~= " .. tostring(expected))
end

View.Paint(module)
local row, done = module.rows[1], module.rows[2]
local need, transmog = Action(row, 1), Action(row, 4)
assert(module.viewCount == 2 and module.host.width == 380 and module.host.height == 120)
assert(module.host.shown and row.frame.shown and done.frame.shown and not module.rows[3].frame.shown)
assert(row.name.text == "Blue sword" and row.icon.texture == 1234)
Near(row.name.textColor[1], 0)
Near(row.name.textColor[2], .44)
Near(row.iconBorder[1].color[3], .87)
assert(row.name.wrap == false and row.details.text:find("100", 1, true))
assert(row.details.text:find("Bind on pickup", 1, true) and row.details.text:find("x2", 1, true))
assert(need.button.shown and transmog.button.shown and need.count.text == 3 and need.backdrop.shown)
assert(not transmog.count.shown and not transmog.backdrop.shown)
assert(done.status.text == "Winner: Player A" and not Action(done, 1).button.shown)

active.canNeed, active.counts[1] = false, 2
active.rollNames[1] = "Player A\nPlayer B"
View.Paint(module)
assert(need.button.shown and need.button.mouse and need.count.text == 2 and need.icon.alpha < 1,
    "other players' Need decisions disappeared when the player could not Need")
need.button.scripts.OnEnter(need.button)
assert(GameTooltip.line == active.rollNames[1], "ineligible Need lost its participant tooltip")
need.button.scripts.OnClick(need.button)
assert(calls == 0, "an observed but ineligible Need action submitted a roll")
active.canNeed, active.counts[1] = true, 3
active.rollNames[1] = "Player A\nPlayer B\nPlayer C"
View.Paint(module)
need.button.scripts.OnClick(need.button)
assert(calls == 1 and lastEntry == active and lastChoice == 1)
active.requestedChoice = 1
need.button.scripts.OnClick(need.button)
assert(calls == 2, "a canceled native confirmation could not be retried")
active.choice, active.statusText = 1, "Waiting for result"
View.Paint(module)
assert(need.button.shown and need.button.mouse and need.count.shown and row.status.shown,
    "waiting rows lost hoverable choices/counts")
assert(not row.details.shown and row.status.width < config.width - config.rowHeight)
need.button.scripts.OnEnter(need.button)
assert(GameTooltip.owner == need.button and GameTooltip.line == active.rollNames[1])
need.button.scripts.OnClick(need.button)
assert(calls == 2, "already-chosen row submitted another decision")
active.choice, active.cancelled = nil, true
need.button.scripts.OnClick(need.button)
assert(calls == 2, "cancelled row submitted another decision")
active.cancelled, active.requestedChoice = nil, nil

active.counts, active.rollNames = nil, nil
need.button.scripts.OnEnter(need.button)
assert(GameTooltip.line == "Roll details are unavailable.", "unknown counts were shown as known zero")
active.counts = { [1] = 0 }
need.button.scripts.OnEnter(need.button)
assert(GameTooltip.line == "No rolls yet.")
active.counts = { [1] = 3 }
need.button.scripts.OnEnter(need.button)
assert(GameTooltip.line == "Roll details are unavailable.", "missing names claimed nobody rolled")

row.item.scripts.OnEnter(row.item)
assert(GameTooltip.link == active.link and GameTooltip.owner == row.item)
local external = Widget()
GameTooltip:SetOwner(external)
GameTooltip:Show()
need.button.scripts.OnLeave(need.button)
assert(GameTooltip.shown, "leaving our button hid another owner's tooltip")
need.button.scripts.OnHide(need.button)
assert(GameTooltip.shown, "hiding our button hid another owner's tooltip")
GameTooltip:SetOwner(need.button)
need.button.scripts.OnLeave(need.button)
assert(not GameTooltip.shown, "our own tooltip was left open")

config.width, config.rowHeight, config.scale, config.growth = 300, 48, 125, 2
View.Paint(module)
assert(module.host.width == 300 and module.host.height == 114 and module.host.scale == 1.25)
assert(row.frame.points[1][1] == "BOTTOMLEFT" and done.frame.points[1][5] == 59)
assert(row.details.width > 0 and row.status.width > 0, "narrow rows give text non-positive width")
local lastOffset
for index = #row.actions, 1, -1 do
    local action = row.actions[index]
    if action.button.shown then
        local offset = action.button.points[1][4]
        if lastOffset then assert(lastOffset - offset >= action.button.width, "action hit areas overlap") end
        lastOffset = offset
    end
end
config.fontSize = 18
View.Paint(module)
assert(row.frame.height == 61 and module.host.height == 126,
    "minimum row height did not expand to fit the largest supported text")
local titleBottom = -row.name.points[1][5] + row.name.height
local buttonTop = row.frame.height - need.button.points[1][5] - need.button.height
assert(titleBottom <= buttonTop, "large title overlaps the roll buttons")
config.fontSize = 12
config.width, config.rowHeight, config.scale, config.growth, config.look = 600, 84, 80, 1, 2
View.Paint(module)
assert(module.host.width == 600 and module.host.height == 172 and module.host.scale == .8)
assert(row.frame.points[1][1] == "TOPLEFT" and done.frame.points[1][5] == -88)
assert(row.details.width > 300 and row.item.width == 72)
Near(row.background.color[1], 21 / 255)

config.width, config.rowHeight, config.scale, config.look = 380, 58, 100, 1
View.Paint(module)
assert(View.Tick(module, 89) and row.remaining.text == 11)
Near(row.border[1].color[1], 51 / 255)
assert(View.Tick(module, 90) and row.remaining.text == 10)
Near(row.border[1].color[1], 1)
Near(row.border[1].color[2], .16)
local unchanged = writes
View.Tick(module, 90)
assert(writes == unchanged, "unchanged countdown performed widget writes")
View.Tick(module, 99.99)
assert(row.remaining.text == 1, "subsecond deadline rounded down to zero early")
assert(not View.Tick(module, 101) and row.remaining.text == 0 and row.timer.value == 0)

active.finished, active.statusText = true, "Everyone passed"
View.Paint(module)
assert(not row.timer.shown and not row.remaining.shown and not need.button.shown)
assert(row.status.text == "Everyone passed")
Near(row.border[1].color[1], 51 / 255)
local replacement = {
    rollID = 18, name = "Replacement", icon = 2222, quality = 4,
    endsAt = 220, duration = 20, canNeed = true, counts = { [1] = 0 },
}
module.visibleEntries = { replacement }
View.Paint(module)
View.Tick(module, 200)
assert(row.entry == replacement and row.maximum == 20 and row.remaining.text == 20)
assert(row.timer.shown and need.button.shown and not need.count.shown and not done.frame.shown)
assert(row.name.text == "Replacement" and row.status.text == "" and not row.status.shown)
Near(row.name.textColor[1], .64)
Near(row.timer.value, 1000)
Near(row.border[1].color[1], 51 / 255)
config.urgentTimer = false
View.Tick(module, 219)
Near(row.border[1].color[1], 51 / 255)
config.showCounts = false
replacement.counts[1] = 5
View.Paint(module)
assert(not need.count.shown and not need.backdrop.shown)

-- Element offsets (the preview's X/Y editor) move only their own element.
local function Point(region, index)
    local point = region.points[index or 1]
    return point[4], point[5]
end
local nameX, nameY = Point(row.name)
local nameRightX = Point(row.name, 2)
local iconX, iconY = Point(row.item)
local needX, needY = Point(need.button)
local timerX, timerY = Point(row.timer)
local remainingX, remainingY = Point(row.remaining)
local detailsX, detailsY = Point(row.details)
local statusX, statusY = Point(row.status)
config.nameOffsetX, config.nameOffsetY, config.iconOffsetX, config.iconOffsetY = 7, -3, -2, 4
config.buttonsOffsetX, config.buttonsOffsetY, config.timerOffsetY = -11, 6, 5
config.remainingOffsetX, config.detailsOffsetY, config.resultOffsetX = 3, -1, 9
View.Paint(module)
local x, y = Point(row.name)
assert(x == nameX + 7 and y == nameY - 3 and Point(row.name, 2) == nameRightX + 7, "name offset")
x, y = Point(row.item)
assert(x == iconX - 2 and y == iconY + 4, "icon offset")
x, y = Point(need.button)
assert(x == needX - 11 and y == needY + 6, "roll buttons offset")
x, y = Point(row.timer)
assert(x == timerX and y == timerY + 5 and select(2, Point(row.timer, 2)) == timerY + 5, "timer bar offset")
x, y = Point(row.remaining)
assert(x == remainingX + 3 and y == remainingY, "remaining time offset")
x, y = Point(row.details)
assert(x == detailsX and y == detailsY - 1, "details offset")
x, y = Point(row.status)
assert(x == statusX + 9 and y == statusY, "result offset")
for _, element in ipairs({ "icon", "name", "details", "result", "remaining", "timer", "buttons" }) do
    config[element .. "OffsetX"], config[element .. "OffsetY"] = 0, 0
end
View.Paint(module)
assert(Point(row.name) == nameX and Point(need.button) == needX, "offsets did not return to the default place")

-- Element sizes (0 = automatic) resize only their element, on layout and paint.
local autoName, autoIcon, autoButton = row.name.fontSize, row.item.width, need.button.width
local autoStep = Point(Action(row, 0).button) - Point(Action(row, 1).button)
assert(autoName == 12 and autoIcon == 46 and autoButton == 23 and row.timer.height == 2, "automatic sizes drifted")
config.nameSize, config.iconSize, config.buttonsSize, config.timerSize = 16, 30, 28, 4
config.detailsSize, config.resultSize, config.remainingSize = 10, 14, 18
View.Paint(module)
assert(row.name.fontSize == 16 and row.name.height == 19, "name size")
assert(row.item.width == 30 and row.item.height == 30 and Point(row.name) == 30 + 14, "icon size or text start")
assert(need.button.width == 28 and Point(Action(row, 0).button) - Point(Action(row, 1).button) == autoStep + 5,
    "button size or spacing")
assert(row.timer.height == 4 and row.details.fontSize == 10 and row.status.fontSize == 14, "bar or text sizes")
assert(row.remaining.fontSize == 18 and row.remaining.width >= 43, "remaining time size")
assert(row.frame.height == 58, "an element size changed the row height")
for _, element in ipairs({ "icon", "name", "details", "result", "remaining", "timer", "buttons" }) do
    config[element .. "Size"] = 0
end
View.Paint(module)
assert(row.name.fontSize == autoName and row.item.width == autoIcon and need.button.width == autoButton)
local beforeTick = writes
View.Tick(module, 205)
View.Tick(module, 205)
assert(writes - beforeTick <= 2, "offsets or sizes added per-tick widget writes")

local sample = {
    name = "Sample item", quality = 3, remaining = 42, canNeed = true, canGreed = true,
    counts = { [1] = 2 }, rollNames = { [1] = "Sample player" },
}
local preview = {
    config = config, previewParent = Widget(), visibleEntries = { sample }, Choose = module.Choose,
    previewViewport = { scale = 2, width = 190, height = 100 },
}
View.Paint(preview)
local sampleRow, sampleNeed = preview.rows[1], Action(preview.rows[1], 1)
assert(preview.host.scale == .5 and sampleRow.remaining.text == 42 and sampleNeed.button.shown)
assert(not sampleNeed.button.mouse and not sampleRow.item.mouse)
local beforePreview = calls
sampleNeed.button.scripts.OnClick(sampleNeed.button)
sampleNeed.button.scripts.OnEnter(sampleNeed.button)
sampleRow.item.scripts.OnEnter(sampleRow.item)
assert(calls == beforePreview and GameTooltip.owner ~= sampleNeed.button and GameTooltip.owner ~= sampleRow.item)
assert(not View.Tick(preview, 900), "static preview requested a running countdown")

local editSample = { config = config, showingSamples = true, visibleEntries = { sample }, Choose = module.Choose }
View.Paint(editSample)
Action(editSample.rows[1], 1).button.scripts.OnClick(Action(editSample.rows[1], 1).button)
assert(calls == beforePreview and not Action(editSample.rows[1], 1).button.mouse,
    "Edit Mode samples were interactive")
assert(nativeReads == 0 and subscriptions == 0, "preview caused native reads or subscriptions")
print("loot roll view: action guards, counts, geometry, countdown, preview and tooltip contracts passed")
