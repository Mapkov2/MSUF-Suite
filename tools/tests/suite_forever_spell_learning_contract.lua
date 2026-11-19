local root = assert(arg[1])
local function Load(path, ns)
    return assert(loadfile(root .. "/" .. path))("MSUF_Suite", ns)
end

local Widget = {}
local function Nothing() end
local function New(parent)
    return setmetatable({ shown = true, scripts = {}, events = {}, parent = parent }, {
        __index = function(_, key) return Widget[key] or (key:match("^[A-Z]") and Nothing or nil) end,
    })
end

function Widget:CreateFontString(_, drawLayer, font)
    local label = New(self)
    label.drawLayer, label.font = drawLayer, font
    return label
end
function Widget:SetPoint(...) self.anchor = { ... } end
function Widget:SetSize(width, height) self.width, self.height = width, height end
function Widget:GetStringWidth() return #self:GetText() * 7 end
function Widget:CreateTexture() return New(self) end
function Widget:SetScript(event, callback) self.scripts[event] = callback end
function Widget:GetScript(event) return self.scripts[event] end
function Widget:HookScript(event, callback) self.scripts[event] = callback end
function Widget:SetShown(shown)
    if self.shown == shown then return end
    self.shown = shown
    local script = self.scripts[shown and "OnShow" or "OnHide"]
    if script then script(self) end
end
function Widget:Show() self:SetShown(true) end
function Widget:Hide() self:SetShown(false) end
function Widget:IsShown() return self.shown end
function Widget:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Widget:IsMouseOver() return false end
function Widget:SetText(text) self.text = text end
function Widget:GetText() return rawget(self, "text") or "" end
function Widget:GetFrameLevel() return self.frameLevel or 4 end
function Widget:SetFrameLevel(level) self.frameLevel = level end
function Widget:SetTextColor(r, g, b, a) self.color = {r, g, b, a} end
function Widget:SetColorTexture(r, g, b, a) self.textureColor = {r, g, b, a} end
function Widget:AddLine(text)
    self.lines = self.lines or {}
    self.lines[#self.lines + 1] = text
end
function Widget:SetSpellByID(id)
    self.tooltipSpell = id
    self.lines, self.doubleLines = {}, {}
end
function Widget:AddDoubleLine(left, right)
    self.doubleLines[#self.doubleLines + 1] = { left, right }
end
function Widget:GetFrameStrata() return "MEDIUM" end
function Widget:GetEffectiveScale() return self.scale or 1 end
function Widget:GetScale() return self.scale or 1 end
function Widget:SetScale(scale) self.scale = scale end
function Widget:GetRight() return 400 end
function Widget:GetLeft() return 50 end
function Widget:GetWidth() return 1000 end
function Widget:RegisterEvent(event) self.events[event] = true end
function Widget:UnregisterAllEvents() self.events = {} end
function Widget:SetupMenu(generator) self.menuGenerator = generator end
function Widget:OpenMenu()
    local options = {}
    self.menuGenerator(self, {
        CreateRadio = function(_, label, selected, choose, value)
            options[label] = { selected = selected, choose = choose, value = value }
        end,
    })
    self.menu = options
    return options
end
function Widget:CloseMenu() self.menu = nil end

local combat, queries, playerLevel, playerRace = false, 0, 20, 1
local combatEdge, forbiddenErrors, clockTime = false, false, 0
local notices, errorNotices, frameCreations = {}, {}, 0
GetTime = function() return clockTime end
local known = { [120] = true }
local inBook, bookItems, spellNames = {}, {}, {}
local pending, preset = nil, .45
local moneyQueries = 0
C_CurrencyInfo = { GetCoinTextureString = function(copper)
    moneyQueries = moneyQueries + 1
    return "coins:" .. copper
end }
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2, Flyout = 3 } }
local function Color(red, green, blue)
    return { GetRGB = function() return red, green, blue end }
end
GREEN_FONT_COLOR, YELLOW_FONT_COLOR, RED_FONT_COLOR = Color(.1, 1, .1), Color(1, .82, 0), Color(1, .1, .1)
UIParent, GameTooltip = New(), New()
UIErrorsFrame = New()
UIErrorsFrame.AddMessage = function(_, message, red, green, blue)
    assert(not forbiddenErrors and red == 1 and green == .82 and blue == .1, "combat feedback lost the standard error style")
    errorNotices[#errorNotices + 1] = message
end
CreateFrame = function(kind, name, parent, template)
    frameCreations = frameCreations + 1
    local frame = New(parent)
    frame.frameName, frame.frameType, frame.template = name, kind, template
    if template == "SearchBoxTemplate" then frame.Instructions = New(frame) end
    return frame
end
UnitClass = function() return "Mage", "MAGE", 8 end
UnitRace = function() return "Race", "Race", playerRace end
UnitLevel = function() return playerLevel end
bit = {
    lshift = function(number, shift) return number * 2 ^ shift end,
    band = function(mask, flag) return math.floor(mask / flag) % 2 end,
}
C_SpellBook = {
    IsSpellKnown = function(id) queries = queries + 1; return known[id] == true end,
    IsSpellKnownOrInSpellBook = function(id, bank, overrides)
        assert(bank == Enum.SpellBookSpellBank.Player and overrides == false,
            "training checked another spell bank or included unlearned talent overrides")
        queries = queries + 1
        if known[id] == "secret" then return "secret" end
        return known[id] == true or inBook[id] == true
    end,
    GetNumSpellBookSkillLines = function() queries = queries + 1; return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #bookItems } end,
    GetSpellBookItemInfo = function(slot, bank)
        assert(bank == Enum.SpellBookSpellBank.Player, "pet abilities hid player spells")
        return bookItems[slot]
    end,
}
C_Spell = { GetSpellName = function(id) return spellNames[id] or "Spell " .. id end, GetSpellTexture = function() return 1 end }
local ns = {
    Client = { isForever = true, IsGamepadUI = function() return false end },
    DB = { skins = { playerSpells = true } },
    Safety = {
        Public = function(value) return value ~= "secret" end,
        IsForbidden = function(frame) return frame == UIErrorsFrame and forbiddenErrors end,
        Isolated = function(callback) return callback end,
        CreateChildFrame = function(kind, parent)
            assert(kind == "Button" and parent ~= UIParent, "the launcher became a separate root")
            return New(parent)
        end,
        Read = function(obj, method, ...) return obj[method](obj, ...) end,
        Field = function(obj, key) return obj[key] end,
    },
    IsCombatLocked = function() return combat end,
    SuiteCore = function() return { InCombat = function() return combat or combatEdge end } end,
    Print = function(message) notices[#notices + 1] = message end,
    Surface = { Ensure = function(frame, spec) frame.skinRole = spec.role end },
    ControlSkin = {
        ApplyButton = function(button, owner, spec)
            assert(button:IsShown() and owner == "spellLearning")
            button.skinRole = spec.role
        end,
        ApplySearchBox = function(box, owner, spec)
            assert(owner == "spellLearning")
            box.skinRole = spec.role
        end,
    },
    WindowActionSkin = { Apply = function(button, owner, kind)
        assert(owner == "spellLearning" and kind == "close")
        button.actionKind = kind
    end },
    Theme = { GetColor = function(role)
        assert(role ~= "shell", "the surface role was used as a palette color")
        if role == "accentBright" then return 1, .8, .4, .3 end
        return preset, 1, 1, 1
    end },
    Registry = { QueueJob = function(fn) pending = fn end },
    WindowControls = { states = {}, Attach = function(panel, owner)
        assert(owner == "spellLearning" and panel.frameName == "MSUFSuiteSpellLearningFrame",
            "the learning panel did not use the shared window scaling controls")
        panel.controlsAttached = true
    end },
}
local book, paged = New(UIParent), New()
book.PagedSpellsFrame = paged
local state = { frame = { SpellBookFrame = book }, active = true }
ns.PlayerSpellsSkin = { activeState = state }

local prefix = "MSUF_Suite_Skin/Adapters/ForeverSpellLearning"
local skinStrings
Load("MSUF_Suite_Skin/Locales/enUS.lua", { RegisterLocale = function(locale, strings)
    assert(locale == "enUS")
    skinStrings = strings
end })
assert(skinStrings["Training cost (before discounts)"] == "Training cost (before discounts)"
    and skinStrings["Training cost not recorded"] == "Training cost not recorded",
    "the cost labels are absent from the canonical skin locale catalog")
assert(skinStrings["Finish combat first."] == "Finish combat first.", "combat refusal is absent from the skin locale catalog")
for _, key in ipairs({"All", "Unknown", "Portal trainer", "Tome or item", "Learning source not confirmed",
    "Learned automatically", "Requires a class quest", "Class quest #%d (availability unconfirmed)"}) do
    assert(skinStrings[key] == key, "an acquisition label is absent from the canonical skin catalog")
end
Load(prefix .. "Data.lua", ns)
assert(ns.ForeverSpellLearningCosts[5]:find("14914:2100 ", 1, true), "Holy Fire's recorded base price is missing")
assert(not ns.ForeverSpellLearningCosts[5]:find("15237:", 1, true), "an unrecorded trainer price became an invented cost")
local function Entry(class, id)
    for token in ns.ForeverSpellLearningData[class]:gmatch("%S+") do
        local fields = {}
        for value in token:gmatch("%d+") do fields[#fields + 1] = tonumber(value) end
        if fields[1] == id then return fields end
    end
    error("spell missing: " .. id)
end
for _, spell in ipairs({15237, 15407}) do assert(Entry(5, spell)[4] == 4, "first talent rank became ordinary training") end
assert(Entry(5, 15430)[4] == 1 and Entry(5, 15430)[7] == 15237, "Holy Nova's trainer rank lost its talent prerequisite")
assert(Entry(5, 17311)[4] == 1 and Entry(5, 17311)[7] == 15407, "Mind Flay's trainer rank lost its talent prerequisite")
for class, spells in pairs({[1] = {355, 7386, 20252}, [2] = {7328}, [3] = {1515, 883, 2641},
    [4] = {2842}, [5] = {10797}, [7] = {8071, 3599, 5394}, [8] = {10140, 28272, 1297659},
    [9] = {688, 697, 713, 23161}, [11] = {5487, 768, 8946, 1066}}) do
    for _, id in ipairs(spells) do assert(Entry(class, id)[4] == 2, "class quest was misclassified: " .. id) end
end
for _, spell in ipairs({5504, 5505, 5506, 6127, 10138, 10139, 118, 12824, 12825, 12826}) do
    assert((Entry(8, spell)[8] or 0) == 0, "ordinary Mage training requires a late or alternate quest reward")
end
assert((Entry(11, 1082)[7] or 0) == 0 and (Entry(11, 3029)[7] or 0) == 0, "Claw acquired a passive talent prerequisite")
assert(Entry(4, 1804)[2] == 16 and Entry(8, 1296017)[2] == 6, "class skills outside the main spell lines are missing")
assert(Entry(8, 1297659)[2] == 50 and ns.ForeverSpellLearningPendingQuests[8]:find("1297659:96828 ", 1, true),
    "Teleport: Dalaran lost its quest evidence or unconfirmed availability")
assert(not ns.ForeverSpellLearningCosts[8]:find("1297659:", 1, true), "Teleport: Dalaran acquired an invented trainer price")
assert(ns.ForeverSpellLearningData[5]:find("10060:40:0:4", 1, true), "a genuine talent was reclassified as a trainer spell")
assert(ns.ForeverSpellLearningData[4]:find("1329283:24:1:", 1, true), "Forever rogue Shank rank 1 is missing")
assert(ns.ForeverSpellLearningData[4]:find("1329549:44:2:", 1, true), "Forever rogue Shank rank 2 is missing")
assert(ns.ForeverSpellLearningData[2]:find("19742:", 1, true), "Paladin Holy spells were not indexed")
assert(not ns.ForeverSpellLearningData[3]:find("17253:", 1, true), "hunter pet ranks leaked into player preview")
ns.ForeverSpellLearningData[8] = "120:10:1:0 121:16:2:1 122:20:1:1:1 123:30:1:2:2 124:30:3:1 "
ns.ForeverSpellLearningCosts[8] = "121:12345 122:0 124:32100 213:99999 "
Load(prefix .. ".lua", ns)
ns.L = setmetatable({}, { __index = function(_, key) return key end })
ns.L["Finish combat first."] = "Beende zuerst den Kampf."
ns.SpellLearning.Attach(state, book, paged)
assert(state.learningButton:IsShown() and not state.learningPanel and queries == 0, "opening the book scanned spells")
local launcher = state.learningButton
assert(launcher.skinRole == "buttonPrimary" and launcher.height >= 28 and launcher.label.drawLayer == "OVERLAY",
    "the training action uses a muted footer control or draws below its surface")
assert(launcher.label:GetText() == "Spells to Learn" and launcher.label.font == "GameFontHighlight")
assert(launcher.parent == book and launcher:GetFrameLevel() == paged:GetFrameLevel() + 10,
    "the launcher does not follow the visible spellbook controls")
assert(launcher.label.color[1] == 1 and launcher.label.color[2] == .8 and launcher.label.color[4] == 1,
    "the launcher label lost the full-opacity accent of the spellbook controls")
assert(launcher.anchor[1] == "TOPRIGHT" and launcher.anchor[2] == paged and launcher.anchor[3] == "TOPRIGHT",
    "the training action overlaps the native footer")
-- A cold combat-edge click must explain the refusal before creating a panel
-- or reading spells, even while the protected-write guard still says false.
local coldFrames, coldQueries = frameCreations, queries
combatEdge = true
launcher.scripts.OnClick()
assert(#notices == 1 and notices[1] == "Beende zuerst den Kampf." and errorNotices[1] == notices[1],
    "a cold combat click was silently ignored or not localized")
assert(not state.learningPanel and frameCreations == coldFrames and queries == coldQueries,
    "a refused cold click built or scanned the dialog")
launcher.scripts.OnClick()
assert(#notices == 1 and #errorNotices == 1, "repeated combat clicks spammed feedback")
combatEdge = false
launcher.scripts.OnClick()
local panel = assert(state.learningPanel)
assert(panel:IsShown() and panel.events.SPELLS_CHANGED and panel.events.SPELL_TEXT_UPDATE and not panel.scripts.OnUpdate)
assert(panel.controlsAttached and panel:GetTitleText() == panel.title, "the window scaling controls were not attached")
assert(panel.next.anchor[2] == -36, "the scale grip overlaps the next-page button")
assert(panel.skinRole == "shell" and not panel.bg and panel.search.skinRole == "input")
assert(panel.title:GetText() == launcher.label:GetText() and panel.caption:GetText() ~= "")
assert(panel.close.template == "UIPanelCloseButtonNoScripts" and panel.close.anchor[1] == "TOPRIGHT"
    and panel.close.actionKind == "close", "the panel did not replace its text button with the themed close X")
assert(panel.previous.skinRole == "button" and panel.next.skinRole == "button")
assert(panel.category.frameType == "DropdownButton" and panel.category.skinRole == "input"
    and panel.search.anchor[2] == panel.category, "the source selector did not leave room for the search field")
local initialMenu = panel.category:OpenMenu()
assert(initialMenu.All.selected(initialMenu.All.value), "the panel did not start with all sources")
panel.close.scripts.OnClick(panel.close)
assert(not panel:IsShown() and not panel.category.menu and book:IsShown(), "the X did not close just the preview and its menu")
launcher.scripts.OnClick()
assert(panel:IsShown(), "the launcher could not reopen the preview after closing it with X")
assert(panel.headerRule.textureColor[1] == preset and panel.rows[1].divider.textureColor[1] == preset)
assert(panel.search.Instructions.color[1] == preset)
local beforeTheme = queries
preset = .72
ns.SpellLearning.RefreshSetting()
assert(panel.title.color[1] == preset and panel.search.color[1] == preset and panel.rows[1].name.color[1] == .1,
    "changing presets replaced the learnable color")
assert(panel.headerRule.textureColor[1] == preset and panel.rows[1].divider.textureColor[1] == preset)
assert(panel.search.Instructions.color[1] == preset)
assert(queries == beforeTheme, "changing presets rescanned the player's spellbook")
assert(#panel.available == 3 and panel.available[1].id == 121 and panel.available[2].id == 122
    and panel.available[3].id == 124, "known spells or incompatible races were included")
assert(panel.rows[1].rank.text == "Rank 2" and panel.rows[3].level.text == "Level 30")
assert(moneyQueries == 0, "opening or repainting the panel formatted money")
local beforeHover = queries
panel.rows[1].scripts.OnEnter(panel.rows[1])
assert(GameTooltip.doubleLines[1][1] == "Training cost (before discounts)"
    and GameTooltip.doubleLines[1][2] == "coins:12345", "hover lost the recorded training cost or discount label")
panel.rows[2].scripts.OnEnter(panel.rows[2])
assert(GameTooltip.doubleLines[1][2] == "coins:0", "a recorded free service was treated as missing data")
assert(queries == beforeHover and moneyQueries == 2, "hover scanned the spellbook or formatted extra prices")
panel.search:SetText("Spell 124")
panel.search.scripts.OnTextChanged()
assert(#panel.filtered == 1 and panel.rows[1].spellID == 124)
known[124] = true
panel.scripts.OnEvent(panel, "SPELLS_CHANGED")
assert(pending and panel.rows[1].spellID == 124, "spellbook changes did not coalesce")
pending()
assert(#panel.filtered == 0, "newly learned rank remained in the preview")

local function UpdateSpells()
    panel.scripts.OnEvent(panel, "SPELLS_CHANGED")
    assert(pending, "learning did not request a refresh")
    local refresh = pending
    pending = nil
    refresh()
end

local function AssertColor(row, color)
    local red, green, blue = color:GetRGB()
    for _, label in ipairs({ row.name, row.rank, row.level }) do
        assert(label.color[1] == red and label.color[2] == green and label.color[3] == blue and label.color[4] == 1,
            "the spell name, rank and level do not show their training availability")
    end
end

-- Learned book ranks can have a different ID from the acquisition index.
-- Future entries and flyouts in the same native book must not count as learned.
spellNames = {
    [201] = "Arc Bolt I", [202] = "Arc Bolt II", [203] = "Arc Bolt III", [204] = "Arc Bolt IV",
    [205] = "Arc Bolt V", [206] = "Arc Bolt VI", [207] = "Future Spell", [208] = "Flyout Spell",
    [209] = "In Book", [210] = "Known Spell", [211] = "Unreadable Spell", [212] = "Talent Spark II",
    [213] = "Plan IV", [214] = "Starter", [215] = "Chain I", [216] = "Chain III", [217] = "Chain IV",
}
bookItems = {
    { name = "Arc Bolt III", subName = "Rang 3", itemType = Enum.SpellBookItemType.Spell, spellID = 999 },
    { name = "Future Spell", subName = "", itemType = Enum.SpellBookItemType.FutureSpell },
    { name = "Flyout Spell", subName = "", itemType = Enum.SpellBookItemType.Flyout },
    { name = "Plan III", subName = "Rank 1", itemType = Enum.SpellBookItemType.Spell },
    { name = "Unreadable", subName = "secret", itemType = Enum.SpellBookItemType.Spell },
}
inBook[209], known[210], known[211], known[216] = true, true, "secret", true
ns.ForeverSpellLearningData[8] = "201:10:1:1 202:14:2:1 203:18:3:1 204:21:4:1 205:22:5:1 206:23:6:1 "
    .. "207:24:0:1 208:25:0:1 209:10:1:1 210:10:1:1 211:10:1:1 212:20:2:1:0:0:218 213:10:1:2 "
    .. "214:1:0:1 215:10:1:1 216:18:3:1 217:22:4:1 "
panel.entries = nil
panel.search:SetText("")
UpdateSpells()
local expected = { 204, 205, 206, 207, 208, 213, 214, 217 }
assert(#panel.available == #expected, "learned, replaced, talent or unreadable spells remained, or future spells disappeared")
for index, id in ipairs(expected) do assert(panel.available[index].id == id, "the wrong spell rank was filtered") end
bookItems[1].subName = ""
panel.scripts.OnEvent(panel, "SPELL_TEXT_UPDATE")
pending()
assert(#panel.available == #expected, "cold spell text brought back learned ranks with an alternate ID")
bookItems[1].actionID, bookItems[1].spellID = 201, 203
UpdateSpells()
assert(#panel.available == #expected, "a cold override used the base spell's lower rank")
AssertColor(panel.rows[1], YELLOW_FONT_COLOR)
AssertColor(panel.rows[2], YELLOW_FONT_COLOR)
AssertColor(panel.rows[3], RED_FONT_COLOR)
local beforeUnknown = moneyQueries
panel.rows[4].scripts.OnEnter(panel.rows[4])
assert(GameTooltip.lines[#GameTooltip.lines] == "Training cost not recorded" and #GameTooltip.doubleLines == 0,
    "an unknown training cost was shown as free")
assert(moneyQueries == beforeUnknown, "an unknown price reached the money formatter")
AssertColor(panel.rows[6], GREEN_FONT_COLOR)
local beforeQuest = moneyQueries
panel.rows[6].scripts.OnEnter(panel.rows[6])
assert(GameTooltip.lines[1] == "Class quest" and #GameTooltip.lines == 1 and #GameTooltip.doubleLines == 0,
    "a quest spell acquired an unrelated training price")
assert(moneyQueries == beforeQuest, "a quest spell formatted a training price")
AssertColor(panel.rows[7], GREEN_FONT_COLOR)
AssertColor(panel.rows[8], YELLOW_FONT_COLOR)

-- The newly learned rank disappears, and the next two levels move with the player.
known[204] = true
playerLevel = 21
panel.scripts.OnEvent(panel, "PLAYER_LEVEL_UP")
pending()
assert(panel.available[1].id == 205, "a newly learned rank stayed visible")
AssertColor(panel.rows[1], YELLOW_FONT_COLOR)
AssertColor(panel.rows[2], YELLOW_FONT_COLOR)
AssertColor(panel.rows[3], RED_FONT_COLOR)
playerLevel = 22
panel.scripts.OnEvent(panel, "PLAYER_LEVEL_UP")
pending()
AssertColor(panel.rows[1], GREEN_FONT_COLOR)
AssertColor(panel.rows[2], YELLOW_FONT_COLOR)
AssertColor(panel.rows[3], YELLOW_FONT_COLOR)

local beforeSearch = queries
panel.search:SetText("Arc Bolt")
panel.search.scripts.OnTextChanged()
assert(#panel.filtered == 2 and queries == beforeSearch, "searching rescanned the spellbook")
panel:SetScale(2)
panel.scripts.OnEvent(panel, "DISPLAY_SIZE_CHANGED")
assert(panel.anchor[1] == "TOP" and queries == beforeSearch, "positioning ignored the scaled panel width or rescanned spells")
ns.WindowControls.states[panel] = { customPosition = true }
panel:SetPoint("CENTER", UIParent, "CENTER", 30, 20)
panel.scripts.OnEvent(panel, "UI_SCALE_CHANGED")
assert(panel.anchor[1] == "CENTER", "automatic docking overwrote the user's saved window position")

-- Acquisition and prerequisites are independent, including native alias
-- ranks, unranked appearances and the nonsequential Skyborne race IDs.
spellNames = {
    [301] = "Talent Echo I", [302] = "Talent Echo II", [303] = "Quest Stance", [304] = "Quest Strike",
    [305] = "Portal", [306] = "Polymorph", [307] = "Polymorph", [308] = "Polymorph",
    [309] = "Automatic", [310] = "Unconfirmed", [311] = "High Order", [312] = "Starting Spell", [313] = "Windshaper",
}
bookItems, inBook, known = {}, {}, { [308] = true }
ns.ForeverSpellLearningData[8] = "301:20:1:4 302:20:2:1:0:0:301 303:10:0:2 304:20:0:1:0:0:0:303 "
    .. "305:20:0:6 306:20:0:5 307:20:0:2 308:8:1:1 309:1:0:0 310:1:0:3 "
    .. "311:20:0:1:0:1 312:1:0:0 313:20:0:1:0:2 "
ns.ForeverSpellLearningCosts[8] = "304:200 305:10000 306:99999 "
ns.ForeverSpellLearningQuestSources[8] = "312:5:2 "
ns.ForeverSpellLearningPendingQuests[8] = "307:96828 "
local function Reindex()
    panel.entries = nil
    panel.search:SetText("")
    UpdateSpells()
end
local function Row(id)
    for _, row in ipairs(panel.rows) do if row:IsShown() and row.spellID == id then return row end end
    error("visible spell missing: " .. id)
end
local function Available(id)
    for _, entry in ipairs(panel.available) do if entry.id == id then return entry end end
end
local function CheckCategory(label, ...)
    local options = panel.category:OpenMenu()
    local option = assert(options[label], "missing category " .. label)
    option.choose(option.value)
    assert(option.selected(option.value) and panel.page == 1, "a category did not select and return to page one")
    assert(#panel.filtered == select("#", ...), "wrong number of results for " .. label)
    for index, id in ipairs({ ... }) do
        assert(panel.filtered[index].id == id, "wrong spell in " .. label)
    end
    panel.category:CloseMenu()
end
Reindex()
assert(not Available(301) and not Available(302), "the talent or its trainer rank survived the permanent filter")
AssertColor(Row(304), RED_FONT_COLOR)
Row(304).scripts.OnEnter(Row(304))
assert(GameTooltip.lines[1] == "Class trainer" and GameTooltip.lines[2] == "Requires a class quest",
    "a missing class quest was reported as a talent")
Row(305).scripts.OnEnter(Row(305))
assert(GameTooltip.lines[1] == "Portal trainer" and GameTooltip.doubleLines[1][2] == "coins:10000")
Row(306).scripts.OnEnter(Row(306))
assert(GameTooltip.lines[1] == "Tome or item" and #GameTooltip.doubleLines == 0)
assert(Available(306) and Available(307), "a learned basic Polymorph hid unlearned alternate appearances")
AssertColor(Row(307), RED_FONT_COLOR)
Row(307).scripts.OnEnter(Row(307))
assert(GameTooltip.lines[1] == "Class quest #96828 (availability unconfirmed)" and #GameTooltip.doubleLines == 0,
    "an unconfirmed quest appeared trainable now or lost its quest identity")
AssertColor(Row(310), RED_FONT_COLOR)
assert(Available(312).source == 0 and Available(312).level == 1, "a racial quest leaked onto another race")
local beforeCategories = queries
panel.page = 3
CheckCategory("Class trainer", 304)
CheckCategory("Class quest", 303, 307)
CheckCategory("Portal trainer", 305)
CheckCategory("Tome or item", 306)
CheckCategory("Learned automatically", 309, 312)
CheckCategory("Unknown", 310)
panel.search:SetText("polymorph")
panel.search.scripts.OnTextChanged()
CheckCategory("Class quest", 307)
CheckCategory("Tome or item", 306)
CheckCategory("All", 306, 307)
panel.search:SetText("talent echo")
panel.search.scripts.OnTextChanged()
assert(#panel.filtered == 0, "search exposed hidden talent spells")
panel.search:SetText("")
panel.search.scripts.OnTextChanged()
assert(queries == beforeCategories, "changing a category rescanned the spellbook")

bookItems[1] = { name = "Talent Echo I", subName = "Rank 1", spellID = 999, itemType = Enum.SpellBookItemType.Spell }
known[301] = true
UpdateSpells()
assert(not Available(301) and not Available(302), "learning a talent made a trainer rank visible")
bookItems[2] = { name = "Polymorph", subName = "", spellID = 306, itemType = Enum.SpellBookItemType.Spell }
UpdateSpells()
assert(not Available(306) and Available(307), "native spell identity hid the wrong unranked appearance")
known[303] = true
UpdateSpells()
assert(not Available(303), "a known class-quest spell remained visible")
AssertColor(Row(304), GREEN_FONT_COLOR)
known[303] = "secret"
UpdateSpells()
AssertColor(Row(304), RED_FONT_COLOR)
playerRace = 95
Reindex()
assert(Available(311) and not Available(313), "High Order Skyborne used race ID instead of PlayableRaceBit")
playerRace = 96
Reindex()
assert(Available(313) and not Available(311), "Windshaper Skyborne used the wrong race mask")
playerRace = 5
Reindex()
assert(Available(312).source == 2 and Available(312).level == 2, "the racial quest source or minimum level was lost")
known[307] = true
UpdateSpells()
assert(not Available(307), "an already learned reward remained visible because its quest availability is unconfirmed")

panel.category:OpenMenu()
panel.scripts.OnEvent(panel, "PLAYER_REGEN_DISABLED")
assert(not panel:IsShown() and next(panel.events) == nil, "combat left preview event work running")
assert(not panel.category.menu, "combat left the category menu visible")
combat = true
clockTime = 2
local beforeCombatMoney = moneyQueries
panel.rows[1].scripts.OnEnter(panel.rows[1])
assert(moneyQueries == beforeCombatMoney, "hover formatted costs in combat")
local warmQueries, warmFrames = queries, frameCreations
state.learningButton.scripts.OnClick()
assert(not panel:IsShown(), "combat opened the preview")
assert(#notices == 2 and #errorNotices == 2, "a warm combat click did not explain the refusal")
assert(queries == warmQueries and frameCreations == warmFrames, "a warm combat refusal did work on the dialog")
forbiddenErrors, clockTime = true, 4
state.learningButton.scripts.OnClick()
assert(#notices == 3 and #errorNotices == 2 and not panel:IsShown(), "a forbidden error frame lost the chat fallback")
forbiddenErrors, combat = false, false
combatEdge, clockTime = true, 6
state.learningButton.scripts.OnClick()
assert(#notices == 4 and not panel:IsShown() and queries == warmQueries,
    "the combat edge bypassed the warm-dialog refusal")
combatEdge = false
state.learningButton.scripts.OnClick()
assert(panel:IsShown() and #notices == 4, "the existing dialog did not reopen after combat")
combat = false
book:Hide()
assert(not state.learningButton:IsShown())
book:Show()
assert(state.learningButton:IsShown())
ns.SpellLearning.SetEnabled(false)
assert(not state.learningButton:IsShown() and ns.DB.foreverSpellLearning == false)
ns.SpellLearning.SetEnabled(true)
assert(state.learningButton:IsShown() and not panel:IsShown())
print("suite_forever_spell_learning_contract: ok")
