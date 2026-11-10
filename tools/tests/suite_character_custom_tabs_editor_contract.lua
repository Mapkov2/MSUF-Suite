local root = assert(arg[1])
local candidate = arg[2]
local function Load(path, namespace)
    local file = candidate and loadfile(candidate .. "/" .. path) or nil
    return assert(file or loadfile(root .. "/" .. path))("MSUF_Suite", namespace)
end

local Frame = {}
Frame.__index = Frame
local function NewFrame(parent)
    return setmetatable({ parent = parent, shown = true, scripts = {} }, Frame)
end

function Frame:SetScript(event, callback) self.scripts[event] = callback end
function Frame:Fire(event, ...)
    local callback = self.scripts[event]
    if callback then return callback(self, ...) end
end
function Frame:HookScript(event, callback)
    local earlier = self.scripts[event]
    self.scripts[event] = function(frame, ...)
        if earlier then earlier(frame, ...) end
        callback(frame, ...)
    end
end
function Frame:SetShown(shown)
    if self.shown == shown then return end
    self.shown = shown
    self:Fire(shown and "OnShow" or "OnHide")
end
function Frame:Show() self:SetShown(true) end
function Frame:Hide() self:SetShown(false) end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:IsMouseOver() return self:IsVisible() end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetHeight(height) self.height = height end
function Frame:SetWidth(width) self.width = width end
function Frame:SetPoint(...) self.anchor = { ... } end
function Frame:ClearAllPoints() self.anchor = nil end
function Frame:SetAllPoints() end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:GetParent() return self.parent end
function Frame:GetPoint() return unpack(self.anchor) end
function Frame:GetRect() return unpack(self.rect) end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:GetEffectiveScale() return self.scale or self.parent and self.parent:GetEffectiveScale() or .73 end
function Frame:SetEnabled(enabled) self.enabled = enabled end
function Frame:EnableKeyboard() end
function Frame:EnableMouse() end
function Frame:RegisterForClicks() end
function Frame:SetMovable() end
function Frame:SetColorTexture() end
function Frame:CreateTexture() return NewFrame(self) end
function Frame:SetJustifyH() end
function Frame:SetWordWrap() end
function Frame:GetStringHeight() return 14 end
function Frame:SetAutoFocus() end
function Frame:SetMaxLetters() end
function Frame:SetFocus() end
function Frame:SetVerticalScroll(value)
    if self:GetVerticalScroll() ~= value then
        self.offset = value
        self:Fire("OnVerticalScroll", value)
    end
end
function Frame:GetVerticalScroll() return self.offset or 0 end
function Frame:EnableMouseWheel(value) self.wheelEnabled = value end
function Frame:GetVerticalScrollRange() return self.range or 0 end
local function Wheel(frame, delta)
    frame:SetVerticalScroll(math.max(0, math.min(frame:GetVerticalScrollRange(), frame:GetVerticalScroll() - delta * 40)))
end
function Frame:SetHideIfUnscrollable(value) self.hideIfUnscrollable = value end
function Frame:SetScrollChild(child) self.child = child end
function Frame:SetText(value) self.text = value self:Fire("OnTextChanged") end
function Frame:GetText() return self.text or "" end
function Frame:HighlightText() end

function CreateFrame(_, _, parent, template)
    local frame = NewFrame(parent)
    frame.template = template
    if template == "ScrollFrameTemplate" then
        frame.ScrollBar = NewFrame(frame)
        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", Wheel)
    end
    return frame
end
local x, y, originX, originY, held = 0, 0, 0, 0, false
function GetCursorPosition() return x, y end
function IsMouseButtonDown() return held end
function wipe(values)
    for key in pairs(values) do values[key] = nil end
end

local function Press(button, cursorX, cursorY)
    originX, originY = cursorX or 450, cursorY or 450
    x, y, held = originX, originY, true
    button:Fire("OnMouseDown", "LeftButton")
end

local function Travel(button, dx, dy)
    local scale = button:GetEffectiveScale()
    x, y = originX + dx * scale, originY + dy * scale
    button:Fire("OnUpdate")
end

local function Release(button)
    held = false
    button:Fire("OnMouseUp", "LeftButton")
    button:Fire("OnClick", "LeftButton")
    assert(not button.scripts.OnUpdate, "completed gesture kept its OnUpdate")
end

local function Run(forever, styled)
    local config, profile, combat, writes = { customTabs = "", tabOrder = "" }, 1, false, 0
    local secret = {}
    local factions = { { name = "Alliance frontiers", isHeader = true } }
    local byFaction, factionReads, currencyReads = {}, 0, 0
    for index = 1, 14 do
        local info = { name = ("Frontier %02d"):format(index), factionID = 100 + index }
        factions[#factions + 1], byFaction[info.factionID] = info, info
    end
    factions[#factions + 1] = { name = "Other factions", isHeader = true }
    for index = 1, 180 do
        local info = { name = ("Observer %03d"):format(index), factionID = 200 + index }
        factions[#factions + 1], byFaction[info.factionID] = info, info
    end
    factions[#factions + 1] = { name = "Protected ID", factionID = secret }
    factions[#factions + 1] = { name = secret, factionID = 999 }
    factions[#factions + 1] = secret
    local currencies = { { name = "Raid marks", isHeader = true },
        { name = "Veteran Medal", currencyID = 392, quantity = 12 } }
    C_Reputation = {
        GetNumFactions = function() return #factions end,
        GetFactionDataByIndex = function(index) factionReads = factionReads + 1 return factions[index] end,
        GetFactionDataByID = function(id) return byFaction[id] end,
    }
    C_CurrencyInfo = {
        GetCurrencyListSize = function() return #currencies end,
        GetCurrencyListInfo = function(index) currencyReads = currencyReads + 1 return currencies[index] end,
        GetCurrencyInfo = function(id) if id == 392 then return currencies[2] end end,
    }
    local menus, answer, confirm, selected, component = {}
    local positionMode, previewScale, attached = false, 1
    local feedbackX, feedbackY
    local function Feedback(x, y) feedbackX, feedbackY = x, y end
    local function Refresh(visible)
        if attached and visible then return component:AttachPreview(attached, selected, positionMode, Feedback) end
        return component:Refresh(440, 80, selected, visible, positionMode, previewScale)
    end
    local function Text(value) return value end
    local suite = { Text = Text, Client = { isForever = forever }, IsSecret = function(value) return value == secret end,
        Public = function(value) return value ~= secret end,
        PublicText = function(value) if type(value) == "string" then return value end end,
        Number = tonumber, Finite = function(value) return type(value) == "number" and value == value end,
        Suite = { Config = function() return config end, FontRevision = 1 } }
    Load("MSUF_Suite/Core/SuiteCatalog.lua", suite)
    Load("MSUF_Suite/Core/CharacterTabs.lua", suite)
    Load("MSUF_Suite/Core/CharacterBindings.lua", suite)
    Load("MSUF_Suite/Core/Catalog/CharacterPanel.lua", suite)
    Load("MSUF_Suite/Core/PreviewKit.lua", suite)
    suite.Suite.CharacterHeader = suite.CharacterHeader
    local bindingTab
    local P = { Suite = suite, S = suite.Suite, Tr = Text, M = {},
        CharacterPanelBindings = { Open = function(_, tab) bindingTab = tab end },
        HM = { SkipHistoryCheckpoint = function() end, GetControlLabel = function(button) return button.label end },
        T = { colors = { accent = { 1, .8, .4 }, panel = { .08, .08, .09 }, muted = { .6, .6, .6 } } },
        Combat = function() return combat end,
    }
    P.ProfileGuard = function()
        local owner = profile
        return function() return owner == profile and not combat end
    end
    P.SetMany = function(id, values)
        assert(id == "characterPanel")
        for key, value in pairs(values) do config[key] = value end
        writes = writes + 1
        Refresh(true)
        return true
    end
    P.Set = function(id, key, value) return P.SetMany(id, { [key] = value }) end
    P.T.Button = function(parent, text, width, height)
        local button = NewFrame(parent)
        button:SetSize(width, height)
        button.label = NewFrame(button)
        button.label:SetText(text)
        return button
    end
    local styleCalls = 0
    if styled then
        P.T.StyleScrollFrame = function(scroll, anchor)
            styleCalls = styleCalls + 1
            assert(scroll.child and scroll.child.parent == scroll, "styled before the picker had a scroll child")
            assert(scroll.parent == anchor, "styled track was not anchored inside the popup")
            scroll:EnableMouseWheel(true)
            scroll:SetScript("OnMouseWheel", Wheel)
        end
    end
    P.Text = function(parent, text)
        local font = NewFrame(parent)
        font:SetText(text)
        return font
    end
    P.SetTranslatedText = function(font, text) font:SetText(text) end
    P.SetButtonText = function(button, text) button.label:SetText(text) end
    P.MenuPopupPanel = function() return NewFrame() end
    P.ContextMenu = function(anchor, generate)
        local items = {}
        menus[#menus + 1] = items
        generate(anchor, { CreateTitle = function() end, CreateButton = function(_, label, click) items[label] = click end })
    end
    P.AskText = function(_, _, callback)
        answer = callback
        local edit = NewFrame()
        return { GetEditBox = function() return edit end }
    end
    P.Confirm = function(_, _, callback) confirm = callback end

    Load("MSUF_Suite_Options/Menu/PreviewInteraction.lua", P)
    Load("MSUF_Suite_Options/Pages/CharacterPreviewContent.lua", P)
    Load("MSUF_Suite_Options/Pages/CharacterSourcePicker.lua", P)
    Load("MSUF_Suite_Options/Pages/CharacterCustomTabs.lua", P)
    local host = NewFrame()
    component = P.CharacterCustomTabs.Create({ host = host }, function(id)
        selected = id
        Refresh(true)
    end)
    local plus = NewFrame(host)
    local model = suite.CharacterTabs
    local function Tab() return assert(model.Find(config, selected)) end
    local function Menu(label) return assert(menus[#menus][label], label)() end
    local function PickerRow(id)
        for _, row in ipairs(component.picker.rows) do
            if row:IsShown() and row.entry.id == id then return row end
        end
        error("Missing source: " .. id)
    end

    assert(component:Refresh(440, 80, nil, true) == 80 and not component.root:IsShown())
    local restored
    assert(component:Add(plus, { { id = "gear", label = "Equipment" } }, function(id) restored = id end))
    Menu("Equipment")
    assert(restored == "gear" and menus[#menus]["Raid check"], "stock restoration replaced custom templates")
    Menu("Raid check")
    answer("Raid desk")
    assert(Tab().name == "Raid desk" and #Tab().cards == 2 and component.root:IsShown())
    assert(component.cards[1].rows[1].value.text == "712", "preview did not use the source sample")

    component.add:Fire("OnClick")
    local pickerScroll = assert(component.picker.scroll)
    if styled then
        assert(styleCalls == 1 and not pickerScroll.template and not pickerScroll.ScrollBar,
            "picker did not install the MSUF scrollbar without native chrome")
    else
        assert(styleCalls == 0 and pickerScroll.template == "ScrollFrameTemplate"
            and pickerScroll.ScrollBar.hideIfUnscrollable, "older hosts did not get the native fallback scrollbar")
    end
    pickerScroll.range = 90
    assert(pickerScroll.wheelEnabled and pickerScroll.scripts.OnMouseWheel, "picker lost wheel input")
    pickerScroll:Fire("OnMouseWheel", -1)
    assert(pickerScroll:GetVerticalScroll() == 40)
    pickerScroll:Fire("OnMouseWheel", -5)
    assert(pickerScroll:GetVerticalScroll() == 90, "wheel missed the scroll-range clamp")
    component.picker.search:SetText("spi")
    assert(pickerScroll:GetVerticalScroll() == 0, "filtering kept the previous scroll offset")
    local spirit = PickerRow("spirit")
    local unavailable = spirit.label.text:find("Not available", 1, true) ~= nil
    assert(spirit.enabled == forever and unavailable == not forever)
    component.picker.search:SetText("experience")
    PickerRow("xp"):Fire("OnClick")
    assert(Tab().cards[2].rows[#Tab().cards[2].rows].source == "xp")

    local first, second = component.cards[1], component.cards[2]
    local before, menuCount, anchor = writes, #menus, first.anchor[5]
    Press(first.title)
    Travel(first.title, 3, -(second.top - first.top + 2))
    assert(writes == before and first.anchor[5] ~= anchor and component.marker:IsShown(),
        "card did not physically follow pointer before a commit")
    Release(first.title)
    assert(writes == before + 1 and #menus == menuCount and Tab().cards[1].title == "Enhancements",
        "card drag did not reorder or navigated on release")
    assert(not component.marker:IsShown())

    first, second = component.cards[1], component.cards[2]
    local from = first.rows[#Tab().cards[1].rows]
    local to = second.rows[1]
    before, menuCount, anchor = writes, #menus, from.anchor[5]
    Press(from)
    Travel(from, 3, -(second.top + to.top - first.top - from.top - 2))
    assert(writes == before and from.anchor[5] ~= anchor and component.marker:IsShown())
    Release(from)
    assert(writes == before + 1 and #menus == menuCount and Tab().cards[2].rows[1].source == "xp",
        "row drag did not move between cards or navigated on release")

    first, second = component.cards[1], component.cards[2]
    from, to = second.rows[1], second.rows[2]
    before = writes
    Press(from)
    Travel(from, 0, -(to.top - from.top + 2))
    Release(from)
    assert(writes == before + 1 and Tab().cards[2].rows[2].source == "xp",
        "row drag did not reorder within the card")
    before = writes
    Press(to)
    Travel(to, 0, second.rows[2].top - second.rows[1].top + 2)
    profile = profile + 1
    Release(to)
    assert(writes == before, "stale profile drag edited a different profile")

    Press(to)
    Release(to)
    Menu("Edit label")
    answer("XP target")
    assert(Tab().cards[2].rows[2].label == "XP target")
    Press(to)
    Release(to)
    Menu("Change data source")
    component.picker.search:SetText("stamina")
    PickerRow("stamina"):Fire("OnClick")
    assert(Tab().cards[2].rows[2].label == "XP target" and Tab().cards[2].rows[2].source == "stamina")

    component.actions:Fire("OnClick")
    Menu("Rename tab")
    answer("Setup")
    assert(Tab().name == "Setup")
    local original = selected
    component.actions:Fire("OnClick")
    Menu("Duplicate tab")
    assert(selected ~= original and #model.Get(config) == 2 and Tab().cards[2].rows[2].label == "XP target")
    local removed = selected
    config.tabOrder = "overview," .. removed .. "," .. original .. ",gear"
    component.actions:Fire("OnClick")
    Menu("Key bindings")
    assert(bindingTab == removed, "custom tab actions did not open its direct bindings")
    Menu("Use as character start tab")
    assert(config.homeTab == removed, "a custom tab could not be selected as C home")
    component.actions:Fire("OnClick")
    Menu("Delete tab")
    confirm()
    assert(not selected and #model.Get(config) == 1 and not config.tabOrder:find(removed, 1, true)
        and config.homeTab == "overview", "delete did not clear both home and order atomically")
    selected = original
    local hidden = {}
    for _, tab in ipairs(suite.CharacterHeader.Tabs) do hidden[#hidden + 1] = tab.id end
    config.hiddenTabs = table.concat(hidden, ",")
    Refresh(true)
    component.actions:Fire("OnClick")
    assert(not menus[#menus]["Delete tab"], "the final visible custom tab was offered for deletion")
    config.hiddenTabs = nil
    Refresh(true)

    assert(component:Add(plus))
    Menu("Empty tab")
    answer("Notes")
    assert(#Tab().cards == 0)
    component.add:Fire("OnClick")
    component.picker.search:SetText("empty card")
    PickerRow("empty"):Fire("OnClick")
    assert(#Tab().cards == 1 and #Tab().cards[1].rows == 0)
    local tabs = model.Copy(config)
    local dense = assert(model.Create(tabs, "empty", "Dense tab"))
    local tab
    for _, item in ipairs(tabs) do if item.id == dense then tab = item break end end
    for index = 1, model.CardLimit do tab.cards[index] = model.NewCard("attributes") end
    config.customTabs, selected = model.Encode(tabs), dense
    local bottom = component:Refresh(440, 80, selected, true)
    local scroll = component.scroll
    assert(bottom < 360 and scroll.ScrollBar.hideIfUnscrollable and component.scrollRange > 0,
        "card viewport did not cap the fixed preview height")
    scroll:Fire("OnMouseWheel", -100)
    assert(scroll:GetVerticalScroll() == component.scrollRange, "wheel did not reach the last card")
    first, second = component.cards[3], component.cards[4]
    from, to = first.rows[1], second.rows[2]
    local sourceY = first.top + from.top
    local targetY = second.top + to.top
    local startScroll = sourceY - 20
    scroll:SetVerticalScroll(startScroll)
    before = writes
    Press(from)
    Travel(from, 0, -8)
    scroll:SetVerticalScroll(startScroll + targetY - sourceY - 10)
    from:Fire("OnUpdate")
    assert(component.marker:IsShown() and writes == before)
    Release(from)
    assert(writes == before + 1 and #Tab().cards[3].rows == #Tab().cards[4].rows - 2
        and Tab().cards[4].rows[2].source == "health", "scroll-adjusted row drag missed the drop target")
    positionMode, previewScale = true, .61
    Refresh(true)
    local card = component.cards[4]
    local row = card.rows[2]
    local cardTitle = Tab().cards[4].title
    local rowSource = Tab().cards[4].rows[2].source
    local dx, dy = 20 * previewScale, -6 * previewScale
    local function Near(a, b) return math.abs(a - b) < 1e-6 end
    local xBefore, yBefore = row.anchor[4], row.anchor[5]
    before, menuCount = writes, #menus
    Press(row)
    Travel(row, dx, dy)
    local priorScroll = scroll:GetVerticalScroll()
    scroll:Fire("OnMouseWheel", -1)
    assert(scroll:GetVerticalScroll() == priorScroll, "scroll changed the local X/Y displacement mid-drag")
    assert(Near(row.anchor[4], xBefore + dx) and Near(row.anchor[5], yBefore + dy) and writes == before
        and component.hint.text == "Position: X 20, Y -6", "scaled row position did not follow the pointer")
    Release(row)
    local rowSpec = Tab().cards[4].rows[2]
    assert(rowSpec.x == 20 and rowSpec.y == -6 and rowSpec.source == rowSource
        and writes == before + 1 and #menus == menuCount, "row X/Y changed its order or opened its menu")
    before, menuCount = writes, #menus
    Press(card.title)
    Travel(card.title, -100 * previewScale, 100 * previewScale)
    assert(component.hint.text == "Position: X -48, Y 24" and writes == before)
    Release(card.title)
    local cardSpec = Tab().cards[4]
    assert(cardSpec.x == -48 and cardSpec.y == 24 and cardSpec.title == cardTitle
        and writes == before + 1 and #menus == menuCount, "card X/Y did not clamp independently from order")

    local raw = config.customTabs
    config = { customTabs = raw, tabOrder = config.tabOrder }
    positionMode = false
    Refresh(true)
    assert(Near(card.anchor[4], component.cardInset - 48 * previewScale)
        and Near(card.anchor[5], -card.top + 24 * previewScale)
        and Near(row.anchor[4], component.rowInset + 20 * previewScale)
        and Near(row.anchor[5], -row.top - 6 * previewScale), "reloaded offsets disappeared in reorder mode")
    Press(row)
    Release(row)
    Menu("Reset position")
    local resetX, resetY = model.Position(Tab().cards[4].rows[2])
    assert(resetX == 0 and resetY == 0, "position reset did not restore row origin")
    positionMode = true
    Refresh(true)
    before = writes
    Press(card.title)
    Travel(card.title, 10, -5)
    profile = profile + 1
    Release(card.title)
    assert(writes == before and Tab().cards[4].x == -48, "profile switch accepted a stale position drag")
    tabs = model.Copy(config)
    for _, item in ipairs(tabs) do if item.id == dense then tab = item break end end
    tab.cards[1].title, tab.cards[1].y = "Raised first", 24
    tab.cards[2].title = "Move around raised card"
    config.customTabs = model.Encode(tabs)
    positionMode, previewScale = false, 1
    Refresh(true)
    scroll:SetVerticalScroll(0)

    first, second = component.cards[1], component.cards[2]
    before = writes
    Press(second.title)
    Travel(second.title, 0, second.drawY - first.drawY + 2)
    assert(component.marker:IsShown(), "first visible title was outside the drop range")
    Release(second.title)
    assert(writes == before + 1 and Tab().cards[1].title == "Move around raised card"
        and Tab().cards[2].y == 24, "dropping above a raised card lost order or offset")

    before = writes
    Press(first.title)
    Travel(first.title, 0, first.drawY - second.drawY - 2)
    Release(first.title)
    assert(writes == before + 1 and Tab().cards[1].title == "Raised first"
        and Tab().cards[1].y == 24, "reorder used the card's unshifted title center")

    before = writes
    local heldRow = component.cards[2].rows[1]
    Press(heldRow)
    Travel(heldRow, 8, 0)
    assert(heldRow.scripts.OnUpdate, "hide test did not start a row drag")
    Refresh(false)
    held = false
    assert(not heldRow.scripts.OnUpdate and not component.marker:IsShown() and writes == before,
        "hiding a held drag failed to clear its scripts without a write")
    assert(not component:Add(plus) and not component.root:IsShown(), "Inspect exposed custom editing")

    local viewport = NewFrame(host)
    viewport.rect = { 0, 0, 800, 520 }
    local canvas = NewFrame(viewport)
    local native = {}
    for index = 1, 2 do
        local actor = NewFrame(canvas)
        local left = 20 + (index - 1) * 310
        actor.rect, actor.previewCardIndex = { left, 150, 280, 320 }, index
        actor:SetPoint("TOPLEFT", canvas, "TOPLEFT", left, -50)
        local title, value = NewFrame(actor), NewFrame(actor)
        title.rect, value.rect = { left, 445, 280, 25 }, { left + 20, 409, 230, 25 }
        value:SetPoint("TOPLEFT", actor, "TOPLEFT", 20, -36)
        value.previewRowIndex = 1
        native[index] = { actor = actor, title = title, value = value }
    end
    attached = { view = { report = { scroll = viewport, canvas = canvas } } }
    function attached:SetContentChanging(callback) self.before = callback end
    function attached:SetContentChanged(callback) self.after = callback end
    function attached:VisitContent(visitor)
        for index, card in ipairs(native) do
            visitor("card", card.title, index, nil, card.actor, canvas)
            visitor("row", card.value, index, card.value.previewRowIndex, card.value, canvas)
        end
    end
    positionMode, selected = false, nil
    Refresh(true)
    assert(component:Add(plus), "full Own preview could not add a first custom tab without a selection")
    Menu("Raid check")
    answer("Direct preview")
    assert(Tab().name == "Direct preview" and not component.root:IsShown())
    assert(attached.before and attached.after, "native paint lifecycle not connected")
    component:OpenContent(plus)
    assert(component.picker:IsShown())
    component.picker:Hide()
    component:OpenTabActions(plus)
    assert(menus[#menus]["Rename tab"], "direct toolbar could not open tab actions")

    local direct = component.direct
    local titleHandle = direct.byFrame[native[1].title]
    local nativeScale = titleHandle:GetEffectiveScale()
    before, menuCount = writes, #menus
    Press(titleHandle, 100 * nativeScale, 455 * nativeScale)
    Travel(titleHandle, 310, 0)
    assert(Near(native[1].actor.anchor[4], 330) and direct.marker:IsShown() and writes == before,
        "rendered native card did not move before release")
    Release(titleHandle)
    assert(writes == before + 1 and #menus == menuCount and Tab().cards[1].title == "Enhancements",
        "direct card drag did not reorder")

    local rowHandle = direct.byFrame[native[1].value]
    before = writes
    Press(rowHandle, 100 * nativeScale, 425 * nativeScale)
    Travel(rowHandle, 310, 0)
    Release(rowHandle)
    assert(writes == before + 1 and Tab().cards[2].rows[1].source == "crit",
        "direct row drag did not move between visible cards")

    positionMode = true
    Refresh(true)
    before, menuCount = writes, #menus
    Press(rowHandle, 100 * nativeScale, 425 * nativeScale)
    Travel(rowHandle, 20, -6)
    assert(native[1].value.anchor[4] == 40 and native[1].value.anchor[5] == -42 and writes == before
        and feedbackX == 20 and feedbackY == -6, "direct X/Y did not use actor scale")
    Release(rowHandle)
    local movedRow = Tab().cards[1].rows[1]
    assert(movedRow.x == 20 and movedRow.y == -6 and #menus == menuCount, "direct X/Y did not persist on release")

    before = writes
    Press(rowHandle, 100 * nativeScale, 425 * nativeScale)
    Travel(rowHandle, 12, 4)
    native[1].value.scale = .66
    Release(rowHandle)
    native[1].value.scale = nil
    assert(writes == before and native[1].value.anchor[4] == 20,
        "mid-drag scale change wrote a stale native position")

    config = { customTabs = config.customTabs, tabOrder = config.tabOrder }
    profile = profile + 1
    Press(rowHandle, 100 * nativeScale, 425 * nativeScale)
    Travel(rowHandle, 12, 4)
    Release(rowHandle)
    assert(writes == before, "an actor painted for a different profile acquired a new write claim")
    Refresh(true)

    before = writes
    Press(rowHandle, 100 * nativeScale, 425 * nativeScale)
    Travel(rowHandle, 12, 4)
    attached.before()
    attached.after()
    held = false
    assert(not rowHandle.scripts.OnUpdate and not direct.marker:IsShown() and writes == before
        and native[1].value.anchor[4] == 20, "pool repaint did not cancel and restore the native actor")
    Press(rowHandle)
    Release(rowHandle)
    Menu("Edit label")
    native[1].value.previewRowIndex = 2
    attached.before()
    attached.after()
    answer("stale binding")
    assert(writes == before and Tab().cards[1].rows[1].label ~= "stale binding",
        "a menu for a recycled row still wrote to the profile")
    component:DetachPreview()
    assert(not attached.before and not attached.after and not rowHandle:IsShown(),
        "direct preview teardown left handles or callbacks active")

    attached, positionMode = nil, false
    Refresh(true)
    local initialCards = #Tab().cards
    component.add:Fire("OnClick")
    local picker = component.picker
    local initialFactionReads, initialCurrencyReads = factionReads, currencyReads
    local last = #picker.results
    assert(last > 180 and #picker.rows <= 10, "the large source list did not use a bounded row pool")
    picker.scroll:SetVerticalScroll((last - 7) * 28)
    assert(PickerRow("currency:392"):IsShown() and #picker.rows <= 10, "scrolling missed the recycled end of the list")
    picker.search:SetText("observer 179")
    assert(PickerRow("faction:379").label.text == "Observer 179")
    picker.search:SetText("protected id")
    assert(picker.empty:IsShown(), "a protected ID became an available choice")
    picker.search:SetText("veteran")
    assert(PickerRow("currency:392").label.text == "Veteran Medal")
    assert(factionReads == initialFactionReads and currencyReads == initialCurrencyReads,
        "scroll or search reread a native list")
    PickerRow("currency:392"):Fire("OnClick")
    local card = Tab().cards[initialCards]
    assert(card.rows[#card.rows].source == "currency:392" and card.rows[#card.rows].label == "",
        "a currency choice saved a transient index or replaced the source label")

    component.add:Fire("OnClick")
    picker.search:SetText("frontier 03")
    PickerRow("faction:103"):Fire("OnClick")
    card = Tab().cards[initialCards]
    assert(card.rows[#card.rows].source == "faction:103" and card.rows[#card.rows].label == "")
    local editorRow = component.cards[initialCards].rows[#card.rows]
    assert(editorRow.label.text == "Frontier 03", "the editor lost the live faction name")
    component.add:Fire("OnClick")
    picker.search:SetText("add shown factions in alliance frontiers")
    before = writes
    picker.search:Fire("OnEnterPressed")
    assert(writes == before + 1 and #Tab().cards == initialCards + 2, "a group did not write once across two cards")
    local firstGroup, lastGroup = Tab().cards[initialCards + 1], Tab().cards[initialCards + 2]
    assert(firstGroup.title == "Alliance frontiers" and #firstGroup.rows == model.RowLimit and #lastGroup.rows == 2)
    assert(firstGroup.rows[1].source == "faction:101" and lastGroup.rows[2].source == "faction:114")

    component.add:Fire("OnClick")
    picker.search:SetText("add shown factions in other factions")
    before = writes
    assert(picker.results[2].noRoom and not picker.results[2].enabled)
    picker.search:Fire("OnEnterPressed")
    assert(writes == before and #Tab().cards == initialCards + 2, "an oversized group was saved partially")
    picker.search:SetText("all reputations")
    PickerRow("reputationReport"):Fire("OnClick")
    component.add:Fire("OnClick")
    picker.search:SetText("all reputations")
    assert(not PickerRow("reputationReport").enabled, "a second full report was offered")
    picker:Hide()
    local current = Tab().cards[initialCards + 2]
    local reportIndex = #current.rows
    local reportRow = component.cards[initialCards + 2].rows[reportIndex]
    Press(reportRow)
    Release(reportRow)
    Menu("Change data source")
    picker.search:SetText("all reputations")
    assert(PickerRow("reputationReport").enabled, "the current source became unavailable while replacing it")
    picker:Hide()
    component.add:Fire("OnClick")
    picker.search:SetText("frontier 03")
    local staleChoice = PickerRow("faction:103")
    before = writes
    profile = profile + 1
    staleChoice:Fire("OnClick")
    assert(writes == before, "a picker from the old profile wrote a faction into the new profile")
end

Run(false, true)
Run(true, false)
print("Character custom tabs composer: creation, picker scroll and search, profile guard, editing and scaled card/row drags passed")
