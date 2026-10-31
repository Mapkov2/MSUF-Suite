-- Buff reminders audit: the note texts follow a size setting that defaults to
-- today's Blizzard font objects, the dependent settings are greyed through the
-- catalog's links, and the "Screen anchor" offers every Suite anchor while the
-- two numbers older profiles stored (1 Center, 2 Top) still mean the same.
-- arg 2 names a mutation: the test loads the module or the catalog with one
-- piece of the change taken out and must then fail.
local root = assert(arg[1], "repository root required")
local mutation = arg[2]
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local function eq(a, b, label) assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local MODULE = "MSUF_Suite_BuffReminders/"
local CATALOG = "MSUF_Suite/Core/Catalog/BuffReminders.lua"
local MUTATIONS = {
    anchors = { MODULE .. "Visuals.lua", [["CENTER", "TOP", "TOPLEFT", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }]],
        [["CENTER", "TOP" }]] },
    cursor = { MODULE .. "Cursor.lua", "R.ScreenPoint(self.config)", [[self.config.point == 2 and "TOP" or "CENTER"]] },
    mover = { MODULE .. "Controller.lua", "return R.ScreenPoint(self.config) end", [[return "CENTER" end]] },
    catalogAnchors = { CATALOG, [[Choice("point", "Screen anchor", 2, screenAnchors)]],
        [[Choice("point", "Screen anchor", 2, { "Center", "Top" })]] },
    legacyOrder = { CATALOG, [[local screenAnchors = { "Center", "Top" }]], "local screenAnchors = {}" },
    sizeNote = { MODULE .. "Visuals.lua", "if size > 0 then", "if false then" },
    defaultLook = { MODULE .. "Visuals.lua", "elseif label.sized then", "else" },
    readyCheck = { MODULE .. "Preparation.lua",
        [[R.StyleNote(text, GameFontNormalLarge, NumberSetting(self.config, "readyCheckSize"))]], "" },
    noticeCreate = { MODULE .. "Special.lua", "notices.label = label\n        R.StyleNotices(self)", "notices.label = label" },
    noticeRefresh = { MODULE .. "Controller.lua", "    R.StyleNotices(self)\n    self:Compile()", "    self:Compile()" },
    switches = { CATALOG, "    rules[key].enableKey = switch\n", "" },
    soundChannel = { CATALOG, [[rules.reminderSoundChannel.requiresChoice = { key = "reminderSound", values = sounds }]], "" },
    demons = { CATALOG, [[rules[demon.key].enableKey = "demonChoiceWarning"]], "" },
}
local originalLoad = loadfile
if mutation then
    local change = assert(MUTATIONS[mutation], "unknown mutation " .. mutation)
    loadfile = function(path)
        if not path:find(change[1], 1, true) then return originalLoad(path) end
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local first, last = source:find(change[2], 1, true)
        assert(first, "the mutation anchor moved")
        return assert(loadstring(source:sub(1, first - 1) .. change[3] .. source:sub(last + 1), "@" .. path))
    end
end

local function Widget()
    local w = { shown = false, attributes = {}, points = {} }
    function w:SetScript(name, callback) self[name] = callback end
    function w:SetAttribute(key, value) self.attributes[key] = value end
    function w:RegisterForClicks(...) self.clicks = { ... } end
    function w:CreateTexture() return Widget() end
    function w:CreateFontString(_, _, inherits)
        local text = Widget()
        text.inherits = inherits
        return text
    end
    function w:SetShown(value) self.shown = value end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetText(value) self.text = value end
    function w:SetTexture(value) self.texture = value end
    function w:SetFontObject(object) self.fontObject = object end
    function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function w:ClearAllPoints() self.points = {} end
    function w:GetEffectiveScale() return 1 end
    function w:SetDesaturated() end
    function w:SetAlpha() end
    function w:CreateAnimationGroup()
        local group = {}
        function group:SetLooping() end
        function group:Play() end
        function group:Stop() end
        function group:CreateAnimation()
            return { SetFromAlpha = function() end, SetToAlpha = function() end, SetDuration = function() end }
        end
        return group
    end
    for _, name in ipairs({ "SetTexCoord", "SetColorTexture", "SetVertexColor", "SetDrawLayer", "SetAllPoints",
        "SetSize", "SetFrameLevel", "SetTextColor", "SetWidth", "SetHeight" }) do
        w[name] = function() end
    end
    function w:GetFrameLevel() return 1 end
    return w
end
UIParent = Widget()
CreateFrame = function() return Widget() end
RegisterStateDriver, UnregisterStateDriver = function() end, function() end
GameTooltip = Widget()

-- Blizzard's font objects the notes inherit: face, size and flags.
local FACE = "Fonts\\FRIZQT__.TTF"
local function FontObject(size) return { GetFont = function() return FACE, size, "" end } end
GameFontNormal, GameFontNormalLarge = FontObject(12), FontObject(16)

-- The game state the module reads: a priest with nothing to remind of, a
-- healer whose mana is low, and the cursor.
local combat, mana, cursor = false, 20, { x = 500, y = 300 }
Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 }, PowerType = { Mana = 0 },
    ItemClass = { Consumable = 0 }, ItemConsumableSubclass = { Fooddrink = 5 } }
Constants = { InventoryConstants = { NumBagSlots = 4 } }
DifficultyUtil = { ID = { DungeonTimewalker = 24, RaidTimewalker = 33 } }
C_SpellBook = { IsSpellKnown = function() return false end, IsSpellInSpellBook = function() return false end }
C_Spell = { GetSpellName = function(id) return "Spell " .. id end, GetSpellTexture = function(id) return id end }
C_SpecializationInfo = { GetSpecialization = function() return 1 end, GetSpecializationInfo = function() return 258 end }
C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemID = function() end }
C_Item = { GetItemCount = function() return 0 end, GetItemIconByID = function(id) return id end }
C_PaperDollInfo = { GetTemporaryEnchantmentInfo = function() end }
C_Secrets = { ShouldAurasBeSecret = function() return false end }
C_UnitAuras = { GetPlayerAuraBySpellID = function() end }
C_Timer = { After = function() end }
GetTime = function() return 100 end
GetCursorPosition = function() return cursor.x, cursor.y end
UnitClass = function() return "PRIEST", "PRIEST" end
UnitIsUnit = function(unit, other) return unit == other end
UnitExists = function(unit) return unit == "player" end
UnitIsConnected, UnitIsVisible = function() return true end, function() return true end
UnitIsDeadOrGhost, UnitInVehicle, IsMounted = function() return false end, function() return false end, function() return false end
UnitGroupRolesAssigned = function() return "HEALER" end
UnitPower = function() return mana end
UnitPowerMax = function() return 100 end
IsResting = function() return false end
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 0 end
GetInventoryItemID = function() end
GetInstanceInfo = function() return "World", "none" end
GetDifficultyInfo = function() end

local S = {
    Public = function(value) return not (type(value) == "table" and value.secret) end,
    Install = function(_, module) _G.auditModule = module end,
    Text = function(value) return value end,
    CreateFrame = function(...) return CreateFrame(...) end,
    CreateTexture = function(parent, ...) return parent:CreateTexture(...) end,
    CreateFontString = function(parent, ...) return parent:CreateFontString(...) end,
    RGB = function() return 1, 1, 1 end,
    SetFont = function(label, path, size, flags) label.font = { path = path, size = size, flags = flags } end,
    ResolveFont = function(value) return value end,
    RegisterOwnedMover = function(_, _, spec) _G.auditMover = spec end, editMode = false,
}
local config, catalogNS = Support.CatalogDefaults(root, "buffReminders")
local NS = { IsCombatLocked = function() return combat end,
    Client = { isForever = false, modernEquipment = true, SupportsEvent = function() return true end },
    AnchorPoints = catalogNS.AnchorPoints, BuffReminderClassReminders = catalogNS.BuffReminderClassReminders,
    BuffReminderDemons = catalogNS.BuffReminderDemons }
catalogNS.Defaults = {}
catalogNS.FinalizeCatalog()
NS.Defaults, NS.IconShapeIds = catalogNS.Defaults, catalogNS.IconShapeIds
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", NS)
NS.Dispatch = function(callback, ...) return callback(...) end
local private = { NS = NS, Suite = S }
Support.Load(root, "MSUF_Suite_BuffReminders", private, nil, { ["Bootstrap.lua"] = true })
local R = private.BuffReminders
local module = assert(auditModule)
local rules = catalogNS.SuiteCatalog.buffReminders.rules

local _, foreverNS = Support.CatalogDefaults(root, "buffReminders", nil, { isForever = true })
local foreverRules = foreverNS.SuiteCatalog.buffReminders.rules

-- Pairs of an anchor label and its point, from the Suite's own lists.
local POINT_OF_LABEL, LABEL_COUNT = {}, #catalogNS.AnchorLabels
for index, label in ipairs(catalogNS.AnchorLabels) do POINT_OF_LABEL[label] = catalogNS.AnchorPoints[index] end

-- The screen anchor offers all nine Suite anchors once; Center and Top keep
-- the numbers older profiles stored.
do
    local labels = rules.point.choices
    eq(#labels, LABEL_COUNT, "the screen anchor does not offer every Suite anchor")
    eq(rules.point.max, LABEL_COUNT, "the screen anchor range")
    eq(rules.point.default, 2, "the default anchor moved")
    eq(labels[1], "Center", "a stored 1 no longer means Center")
    eq(labels[2], "Top", "a stored 2 no longer means Top")
    local seen = {}
    for _, label in ipairs(labels) do
        assert(POINT_OF_LABEL[label], label .. " is not a Suite anchor label")
        assert(not seen[label], label .. " is offered twice")
        seen[label] = true
    end
    eq(#foreverRules.point.choices, LABEL_COUNT, "Forever offers other anchors")
end

-- The host sits on the chosen anchor of the screen with its offsets; the
-- Edit Mode mover and the cursor's return use the same anchor.
local events = {}
local context = {}
function context:Event(event, callback) events[event] = callback end
function context:RemoveEvent(event) events[event] = nil end
module.context = Support.ModuleTimers(root, S, NS)("buffReminders", module, context)
module.active = true
local function Start(overrides)
    module.config = {}
    for key, value in pairs(config) do module.config[key] = value end
    module.config.classBuff, module.config.autoRoguePoisons = false, false
    module.config.autoFlask, module.config.autoFood, module.config.autoRune = false, false, false
    module.config.autoWeapon = false
    for key, value in pairs(overrides or {}) do module.config[key] = value end
    module:Enable()
end
local function ExpectedPoint(index) return POINT_OF_LABEL[rules.point.choices[index]] end

do
    for index in ipairs(rules.point.choices) do
        Start({ point = index, x = 7, y = -9 })
        local placed = module.view.host.points
        eq(#placed, 1, "anchor " .. index .. " placed the host " .. #placed .. " times")
        local point, relative, relativePoint, x, y = unpack(placed[1])
        eq(point, ExpectedPoint(index), "anchor " .. index .. " point")
        eq(relativePoint, point, "anchor " .. index .. " uses another point of the screen")
        assert(relative == UIParent and x == 7 and y == -9, "anchor " .. index .. " lost its offsets")
        module:RegisterMovers()
        eq(auditMover.point(), point, "the Edit Mode mover places anchor " .. index .. " elsewhere")
        module:Disable()
    end
    eq(R.ScreenPoint({ point = 1 }), "CENTER", "an old Center profile")
    eq(R.ScreenPoint({ point = 2 }), "TOP", "an old Top profile")
    eq(R.ScreenPoint({}), "CENTER", "a profile without the setting")
    eq(R.ScreenPoint({ point = LABEL_COUNT + 1 }), "CENTER", "an unknown anchor")
end

-- Following the cursor places the host by its bottom left corner, whatever
-- the anchor; leaving it returns the host to the chosen anchor.
do
    for index in ipairs(rules.point.choices) do
        local owner = R.NewState({ config = { followCursor = true, cursorOffsetX = 24, cursorOffsetY = 24,
            point = index, x = 3, y = 4 }, active = true })
        owner.view.host, owner.view.mask = Widget(), 1
        R.SyncCursor(owner)
        local follow = owner.view.host.points[1]
        eq(follow[1], "BOTTOMLEFT", "anchor " .. index .. ": the host does not follow by its corner")
        eq(follow[4], 524, "anchor " .. index .. ": the host is not beside the cursor")
        owner.config.followCursor = false
        R.SyncCursor(owner)
        local back = owner.view.host.points[1]
        eq(back[1], ExpectedPoint(index), "anchor " .. index .. ": the host returned to another anchor")
        assert(back[4] == 3 and back[5] == 4, "anchor " .. index .. ": the return lost the offsets")
    end
end

-- The ready check note and the notice lines keep their Blizzard font objects
-- at size 0; any other size draws the object's face at that size.
do
    mana = 20
    local function Check()
        events.READY_CHECK(module, "READY_CHECK")
        return module.readyCheck.label
    end
    Start({ readyCheckMana = true })
    local note = Check()
    eq(note.inherits, "GameFontNormalLarge", "the mana note lost its font object")
    eq(note.font, nil, "the default size changed the mana note font")
    eq(note.fontObject, nil, "the default size set another font object on the mana note")
    module.config.readyCheckSize = 24
    Check()
    assert(note.font and note.font.size == 24 and note.font.path == FACE and note.font.flags == "",
        "the mana note ignored its size")
    module.config.readyCheckSize = 0
    Check()
    eq(note.fontObject, GameFontNormalLarge, "size 0 did not give the mana note its font object back")
    eq(note.sized, nil, "the mana note stayed marked as sized")
    module:Disable()

    -- The notice lines: made at their size, restyled by a settings refresh.
    Start({})
    module.notices.petPassive = true
    R.SpecialText(module, true)
    local lines = module.notices.label
    eq(lines.inherits, "GameFontNormal", "the notice lines lost their font object")
    eq(lines.font, nil, "the default size changed the notice font")
    eq(lines.fontObject, nil, "the default size set another font object on the notices")
    module.config.noticeSize = 15
    module:Refresh()
    assert(lines.font and lines.font.size == 15 and lines.font.path == FACE, "a settings refresh left the notices at their old size")
    module.config.noticeSize = 0
    module:Refresh()
    eq(lines.fontObject, GameFontNormal, "size 0 did not give the notice lines their font object back")
    module:Disable()
    -- A label made while the size is set starts at that size.
    Start({ noticeSize = 18 })
    module.notices.mask, module.notices.label = nil, nil
    module.notices.petPassive = true
    R.SpecialText(module, true)
    eq(module.notices.label.font and module.notices.label.font.size, 18, "a new notice label ignored the size")
    module:Disable()
end

-- Settings that only matter with a switch (or a sound) are greyed through the
-- catalog; the links never touch a value, and every key resolves.
local function CheckLinks(rulesOf, label)
    local switches = {
        mapPotionItem = "mapPotion", mapPotionMaps = "mapPotion",
        flaskChoice = "autoFlask", foodChoice = "autoFood", runeChoice = "autoRune", oilChoice = "autoWeapon",
        readyCheckManaPercent = "readyCheckMana", readyCheckDuration = "readyCheckMana",
        readyCheckSize = "readyCheckMana", cursorOffsetX = "followCursor", cursorOffsetY = "followCursor",
    }
    for _, demon in ipairs(catalogNS.BuffReminderDemons) do switches[demon.key] = "demonChoiceWarning" end
    for key, switch in pairs(switches) do
        local rule = assert(rulesOf[key], label .. ": " .. key .. " has no rule")
        eq(rule.enableKey, switch, label .. ": " .. key .. " is not greyed with " .. switch)
        eq(type(rulesOf[switch].default), "boolean", label .. ": " .. switch .. " is not a switch")
        assert(rule.hidden == nil and rule.requiresChoice == nil, label .. ": " .. key .. " got more than a link")
    end
    local channel = rulesOf.reminderSoundChannel.requiresChoice
    eq(channel and channel.key, "reminderSound", label .. ": the sound channel follows another setting")
    assert(not channel.values[1], label .. ": the sound channel is open with no sound")
    for choice = 2, #rulesOf.reminderSound.choices do
        assert(channel.values[choice], label .. ": the sound channel is greyed for sound " .. choice)
    end
    eq(rulesOf.keystoneMinutes.requiresChoice.key, "keystoneCover", label .. ": the keystone link was lost")
end
CheckLinks(rules, "Retail")
CheckLinks(foreverRules, "Forever")

-- Defaults: the new settings change nothing, the old ones keep their values.
eq(rules.readyCheckSize.default, 0, "the mana note size default")
eq(rules.noticeSize.default, 0, "the notice size default")
eq(rules.mapPotionItem.default, "124640", "a dependent setting lost its default")
eq(rules.cursorOffsetX.default, 24, "a dependent setting lost its default")

print("Suite buff reminders audit: " .. (mutation and ("mutation " .. mutation .. " survived") or
    "anchors, cursor return, mover, note sizes and dependency links passed"))
