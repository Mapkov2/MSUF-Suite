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
function Widget:GetFrameStrata() return "MEDIUM" end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetRight() return 400 end
function Widget:GetLeft() return 50 end
function Widget:GetWidth() return 1000 end
function Widget:RegisterEvent(event) self.events[event] = true end
function Widget:UnregisterAllEvents() self.events = {} end

local combat, queries = false, 0
local known = { [120] = true }
local pending, preset = nil, .45
UIParent, CLOSE, GameTooltip = New(), "Close", New()
CreateFrame = function(_, _, parent, template)
    local frame = New(parent)
    if template == "SearchBoxTemplate" then frame.Instructions = New(frame) end
    return frame
end
UnitClass = function() return "Mage", "MAGE", 8 end
UnitRace = function() return "Human", "Human", 1 end
UnitLevel = function() return 20 end
bit = {
    lshift = function(number, shift) return number * 2 ^ shift end,
    band = function(mask, flag) return math.floor(mask / flag) % 2 end,
}
C_SpellBook = { IsSpellKnown = function(id) queries = queries + 1; return known[id] == true end }
C_Spell = { GetSpellName = function(id) return "Spell " .. id end, GetSpellTexture = function() return 1 end }
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
}
local book, paged = New(UIParent), New()
book.PagedSpellsFrame = paged
local state = { frame = { SpellBookFrame = book }, active = true }
ns.PlayerSpellsSkin = { activeState = state }

local prefix = "MSUF_Suite_Skin/Adapters/ForeverSpellLearning"
Load(prefix .. "Data.lua", ns)
assert(ns.ForeverSpellLearningData[4]:find("1329283:24:1:", 1, true), "Forever rogue Shank rank 1 is missing")
assert(ns.ForeverSpellLearningData[4]:find("1329549:44:2:", 1, true), "Forever rogue Shank rank 2 is missing")
assert(ns.ForeverSpellLearningData[2]:find("19742:", 1, true), "Paladin Holy spells were not indexed")
assert(not ns.ForeverSpellLearningData[3]:find("17253:", 1, true), "hunter pet ranks leaked into player preview")
ns.ForeverSpellLearningData[8] = "120:10:1:0 121:16:2:1 122:20:1:1:1 123:30:1:2:2 124:30:3:4 "
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
assert(panel:IsShown() and panel.events.SPELLS_CHANGED and not panel.scripts.OnUpdate)
assert(panel.skinRole == "shell" and not panel.bg and panel.search.skinRole == "input")
assert(panel.title:GetText() == launcher.label:GetText() and panel.caption:GetText() ~= "")
assert(panel.close.skinRole == "button" and panel.previous.skinRole == "button" and panel.next.skinRole == "button")
assert(panel.headerRule.textureColor[1] == preset and panel.rows[1].divider.textureColor[1] == preset)
assert(panel.search.Instructions.color[1] == preset)
local beforeTheme = queries
preset = .72
ns.SpellLearning.RefreshSetting()
assert(panel.title.color[1] == preset and panel.search.color[1] == preset and panel.rows[1].name.color[1] == preset)
assert(panel.headerRule.textureColor[1] == preset and panel.rows[1].divider.textureColor[1] == preset)
assert(panel.search.Instructions.color[1] == preset)
assert(queries == beforeTheme, "changing presets rescanned the player's spellbook")
assert(#panel.available == 3 and panel.available[1].id == 121 and panel.available[2].id == 122
    and panel.available[3].id == 124, "known spells or incompatible races were included")
assert(panel.rows[1].rank.text == "Rank 2" and panel.rows[3].level.text == "Level 30")
panel.search:SetText("Spell 124")
panel.search.scripts.OnTextChanged()
assert(#panel.filtered == 1 and panel.rows[1].spellID == 124)
known[124] = true
panel.scripts.OnEvent(panel, "SPELLS_CHANGED")
assert(pending and panel.rows[1].spellID == 124, "spellbook changes did not coalesce")
pending()
assert(#panel.filtered == 0, "newly learned rank remained in the preview")

panel.scripts.OnEvent(panel, "PLAYER_REGEN_DISABLED")
assert(not panel:IsShown() and next(panel.events) == nil, "combat left preview event work running")
combat = true
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
