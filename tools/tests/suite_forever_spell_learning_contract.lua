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

local combat, queries, playerLevel = false, 0, 20
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
UIParent, CLOSE, GameTooltip = New(), "Close", New()
CreateFrame = function(_, name, parent, template)
    local frame = New(parent)
    frame.frameName = name
    if template == "SearchBoxTemplate" then frame.Instructions = New(frame) end
    return frame
end
UnitClass = function() return "Mage", "MAGE", 8 end
UnitRace = function() return "Human", "Human", 1 end
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
        IsForbidden = function() return false end,
        Isolated = function(callback) return callback end,
        CreateChildFrame = function(kind, parent)
            assert(kind == "Button" and parent ~= UIParent, "the launcher became a separate root")
            return New(parent)
        end,
        Read = function(obj, method, ...) return obj[method](obj, ...) end,
        Field = function(obj, key) return obj[key] end,
    },
    IsCombatLocked = function() return combat end,
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
Load(prefix .. "Data.lua", ns)
assert(ns.ForeverSpellLearningCosts[5]:find("14914:2100 ", 1, true), "Holy Fire's recorded base price is missing")
assert(not ns.ForeverSpellLearningCosts[5]:find("15237:", 1, true), "an unrecorded trainer price became an invented cost")
for _, spell in ipairs({ 15237, 15430, 15431, 27799, 27800, 27801, 15407, 17311, 17312, 17313, 17314, 18807 }) do
    local found
    for id, source in ns.ForeverSpellLearningData[5]:gmatch("(%d+):%d+:%d+:(%d+)") do
        if tonumber(id) == spell then found = tonumber(source) break end
    end
    assert(found == 1, "a Holy Nova or Mind Flay rank still requires a talent instead of class training")
end
assert(ns.ForeverSpellLearningData[5]:find("10060:40:0:4", 1, true), "a genuine talent was reclassified as a trainer spell")
assert(ns.ForeverSpellLearningData[4]:find("1329283:24:1:", 1, true), "Forever rogue Shank rank 1 is missing")
assert(ns.ForeverSpellLearningData[4]:find("1329549:44:2:", 1, true), "Forever rogue Shank rank 2 is missing")
assert(ns.ForeverSpellLearningData[2]:find("19742:", 1, true), "Paladin Holy spells were not indexed")
assert(not ns.ForeverSpellLearningData[3]:find("17253:", 1, true), "hunter pet ranks leaked into player preview")
ns.ForeverSpellLearningData[8] = "120:10:1:0 121:16:2:1 122:20:1:1:1 123:30:1:2:2 124:30:3:4 "
ns.ForeverSpellLearningCosts[8] = "121:12345 122:0 124:32100 213:99999 "
Load(prefix .. ".lua", ns)
ns.L = setmetatable({}, { __index = function(_, key) return key end })
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
launcher.scripts.OnClick()
local panel = assert(state.learningPanel)
assert(panel:IsShown() and panel.events.SPELLS_CHANGED and panel.events.SPELL_TEXT_UPDATE and not panel.scripts.OnUpdate)
assert(panel.controlsAttached and panel:GetTitleText() == panel.title, "the window scaling controls were not attached")
assert(panel.next.anchor[2] == -36, "the scale grip overlaps the next-page button")
assert(panel.skinRole == "shell" and not panel.bg and panel.search.skinRole == "input")
assert(panel.title:GetText() == launcher.label:GetText() and panel.caption:GetText() ~= "")
assert(panel.close.skinRole == "button" and panel.previous.skinRole == "button" and panel.next.skinRole == "button")
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
    .. "207:24:0:1 208:25:0:1 209:10:1:1 210:10:1:1 211:10:1:1 212:20:2:4 213:10:1:2 "
    .. "214:1:0:1 215:10:1:1 216:18:3:1 217:22:4:1 "
panel.entries = nil
panel.search:SetText("")
UpdateSpells()
local expected = { 204, 205, 206, 207, 208, 212, 213, 214, 217 }
assert(#panel.available == #expected, "learned, replaced or unreadable spells remained, or future spells disappeared")
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
AssertColor(panel.rows[6], RED_FONT_COLOR)
GameTooltip.lines = {}
panel.rows[6].scripts.OnEnter(panel.rows[6])
assert(GameTooltip.lines[1] == "Requires a talent", "a missing genuine talent lost its requirement hint")
AssertColor(panel.rows[7], GREEN_FONT_COLOR)
local beforeQuest = moneyQueries
panel.rows[7].scripts.OnEnter(panel.rows[7])
assert(GameTooltip.lines[1] == "Class quest" and #GameTooltip.lines == 1 and #GameTooltip.doubleLines == 0,
    "a quest spell acquired an unrelated training price")
assert(moneyQueries == beforeQuest, "a quest spell formatted a training price")
AssertColor(panel.rows[8], GREEN_FONT_COLOR)
AssertColor(panel.rows[9], YELLOW_FONT_COLOR)

-- The newly learned rank disappears, and the next two levels move with the player.
known[204] = true
playerLevel = 21
panel.scripts.OnEvent(panel, "PLAYER_LEVEL_UP")
pending()
assert(panel.available[1].id == 205, "a newly learned rank stayed visible")
AssertColor(panel.rows[1], YELLOW_FONT_COLOR)
AssertColor(panel.rows[2], YELLOW_FONT_COLOR)
AssertColor(panel.rows[3], RED_FONT_COLOR)
bookItems[#bookItems + 1] = { name = "Talent Spark I", subName = "Rang 1", itemType = Enum.SpellBookItemType.Spell }
UpdateSpells()
AssertColor(panel.rows[5], GREEN_FONT_COLOR)
GameTooltip.lines = {}
panel.rows[5].scripts.OnEnter(panel.rows[5])
for _, line in ipairs(GameTooltip.lines) do
    assert(line ~= "Requires a talent", "an already learned talent was still described as a missing requirement")
end
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

panel.scripts.OnEvent(panel, "PLAYER_REGEN_DISABLED")
assert(not panel:IsShown() and next(panel.events) == nil, "combat left preview event work running")
combat = true
local beforeCombatMoney = moneyQueries
panel.rows[1].scripts.OnEnter(panel.rows[1])
assert(moneyQueries == beforeCombatMoney, "hover formatted costs in combat")
state.learningButton.scripts.OnClick()
assert(not panel:IsShown(), "combat opened the preview")
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
