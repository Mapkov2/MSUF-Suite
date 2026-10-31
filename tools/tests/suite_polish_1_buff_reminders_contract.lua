-- Buff reminders note placement: the notice lines hang below the row and the
-- ready check note above it, except with a bottom anchor, where the row is at
-- the lower edge of the screen and every note hangs above it (the ready check
-- note over the notice lines). Following the cursor moves the host, and the
-- notes with it.
-- arg 2 names a mutation: the test loads the module with one piece of the
-- change taken out and must then fail.
local root = assert(arg[1], "repository root required")
local mutation = arg[2]
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local function eq(a, b, label) assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local MODULE = "MSUF_Suite_BuffReminders/"
local MUTATIONS = {
    rule = { MODULE .. "Visuals.lua", "BOTTOM_POINTS = { BOTTOM = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }",
        "BOTTOM_POINTS = {}" },
    everywhere = { MODULE .. "Visuals.lua", "return below and not BOTTOM_POINTS[R.ScreenPoint(config)]",
        "return false" },
    noticePlaced = { MODULE .. "Special.lua", "R.PlaceNote(label, self.view.host, self.config, true, NOTICE_GAP)", "" },
    readyPlaced = { MODULE .. "Preparation.lua",
        "R.PlaceNote(text, ReadyNoteAnchor(self), self.config, false, READY_NOTE_GAP)", "" },
    stacked = { MODULE .. "Preparation.lua", "if notices.label and notices.text", "if false and notices.label and notices.text" },
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
    function w:RegisterForClicks() end
    function w:CreateTexture() return Widget() end
    function w:CreateFontString() return Widget() end
    function w:SetShown(value) self.shown = value end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetText(value) self.text = value end
    function w:SetTexture(value) self.texture = value end
    function w:SetFontObject(object) self.fontObject = object end
    function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function w:ClearAllPoints() self.points = {} end
    function w:GetEffectiveScale() return 1 end
    function w:GetFrameLevel() return 1 end
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
        "SetSize", "SetFrameLevel", "SetTextColor", "SetWidth", "SetHeight", "SetDesaturated", "SetAlpha" }) do
        w[name] = function() end
    end
    return w
end
UIParent = Widget()
CreateFrame = function() return Widget() end
RegisterStateDriver, UnregisterStateDriver = function() end, function() end
GameTooltip = Widget()
GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
GameFontNormalLarge = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 16, "" end }

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
    Install = function(_, module) _G.noteModule = module end,
    Text = function(value) return value end,
    CreateFrame = function(...) return CreateFrame(...) end,
    CreateTexture = function(parent, ...) return parent:CreateTexture(...) end,
    CreateFontString = function(parent, ...) return parent:CreateFontString(...) end,
    RGB = function() return 1, 1, 1 end,
    SetFont = function(label, path, size, flags) label.font = { path = path, size = size, flags = flags } end,
    ResolveFont = function(value) return value end,
    RegisterOwnedMover = function() end, editMode = false,
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
local module = assert(noteModule)
local choices = catalogNS.SuiteCatalog.buffReminders.rules.point.choices

local events, context = {}, {}
function context:Event(event, callback) events[event] = callback end
function context:RemoveEvent(event) events[event] = nil end
module.context = Support.ModuleTimers(root, S, NS)("buffReminders", module, context)
module.active = true

-- The Suite's point of each "Screen anchor" choice, from the Suite's own lists.
local POINT_OF_LABEL = {}
for index, label in ipairs(catalogNS.AnchorLabels) do POINT_OF_LABEL[label] = catalogNS.AnchorPoints[index] end
local function PointOf(index) return POINT_OF_LABEL[choices[index]] end
local function IsBottom(index) return PointOf(index):find("^BOTTOM") ~= nil end

local NOTICE_GAP, READY_GAP = 6, 8
local function Start(overrides)
    module.config = {}
    for key, value in pairs(config) do module.config[key] = value end
    module.config.classBuff, module.config.autoRoguePoisons = false, false
    module.config.autoFlask, module.config.autoFood, module.config.autoRune = false, false, false
    module.config.autoWeapon, module.config.readyCheckMana = false, true
    for key, value in pairs(overrides or {}) do module.config[key] = value end
    module.notices.label, module.notices.mask, module.readyCheck.label = nil, nil, nil
    module:Enable()
end

-- One notice line is showing (the pet is passive).
local function ShowNotice(on)
    module.notices.petPassive = on or nil
    R.SpecialText(module, true)
    return module.notices.label
end
local function ReadyNote()
    events.READY_CHECK(module, "READY_CHECK")
    return module.readyCheck.label
end
local function Expect(label, side, anchor, gap, what)
    eq(#label.points, 1, what .. " is anchored " .. #label.points .. " times")
    local point, relative, relativePoint, x, y = unpack(label.points[1])
    if side == "below" then
        eq(point .. " " .. relativePoint, "TOP BOTTOM", what .. " is not below")
        eq(y, -gap, what .. " gap")
    else
        eq(point .. " " .. relativePoint, "BOTTOM TOP", what .. " is not above")
        eq(y, gap, what .. " gap")
    end
    eq(relative, anchor, what .. " hangs on another region")
    eq(x, 0, what .. " is off the row's middle")
end

-- Each of the nine anchors: below the row keeps today's look; a bottom anchor
-- puts the notice lines above the row and the ready check note above them.
for index in ipairs(choices) do
    local name = "anchor " .. index .. " (" .. PointOf(index) .. ")"
    Start({ point = index })
    local host = module.view.host
    local lines = ShowNotice(true)
    Expect(lines, IsBottom(index) and "above" or "below", host, NOTICE_GAP, name .. ": the notice lines")
    local note = ReadyNote()
    Expect(note, "above", IsBottom(index) and lines or host, READY_GAP, name .. ": the ready check note")
    -- With no notice showing, the ready check note hangs on the row itself.
    ShowNotice(false)
    note = ReadyNote()
    Expect(note, "above", host, READY_GAP, name .. ": the ready check note without notices")
    module:Disable()
end
eq(R.NoteBelow({ point = 2 }, true), true, "a top anchor lost the notice lines below the row")
eq(R.NoteBelow({ point = 2 }, false), false, "a note that belongs above hangs below")
eq(R.NoteBelow({}, true), true, "a profile without the setting lost the notice lines below the row")

-- A settings change moves the notes that exist: Top to Bottom and back.
do
    local top, bottom
    for index in ipairs(choices) do
        if PointOf(index) == "TOP" then top = index elseif PointOf(index) == "BOTTOM" then bottom = index end
    end
    Start({ point = top })
    local host = module.view.host
    local lines = ShowNotice(true)
    Expect(lines, "below", host, NOTICE_GAP, "top anchor: the notice lines")
    module.config.point = bottom
    module:Refresh()
    Expect(lines, "above", host, NOTICE_GAP, "after the change to a bottom anchor: the notice lines")
    ShowNotice(true)
    Expect(ReadyNote(), "above", lines, READY_GAP, "after the change to a bottom anchor: the ready check note")
    module.config.point = top
    module:Refresh()
    Expect(lines, "below", host, NOTICE_GAP, "after the change back to a top anchor: the notice lines")
    ShowNotice(true)
    Expect(ReadyNote(), "above", host, READY_GAP, "after the change back to a top anchor: the ready check note")
    module:Disable()
end

-- Following the cursor places the host, and the notes hang on the host, so
-- they follow it and stay where the anchor put them.
for index in ipairs(choices) do
    local name = "anchor " .. index .. ": "
    Start({ point = index, followCursor = true, cursorOffsetX = 24, cursorOffsetY = 24 })
    local host = module.view.host
    local lines = ShowNotice(true)
    local note = ReadyNote()
    R.SyncCursor(module)
    local driver = assert(module.cursor.driver, name .. "the cursor driver did not start")
    eq(host.points[1][1], "BOTTOMLEFT", name .. "the host does not follow by its corner")
    eq(host.points[1][4], 524, name .. "the host is not beside the cursor")
    cursor.x = 700
    driver.OnUpdate(driver)
    eq(host.points[1][4], 724, name .. "the host stopped following")
    Expect(lines, IsBottom(index) and "above" or "below", host, NOTICE_GAP, name .. "the notice lines while following")
    Expect(note, "above", IsBottom(index) and lines or host, READY_GAP, name .. "the ready check note while following")
    module.config.followCursor = false
    R.SyncCursor(module)
    eq(host.points[1][1], PointOf(index), name .. "the host did not return to its anchor")
    Expect(lines, IsBottom(index) and "above" or "below", host, NOTICE_GAP, name .. "the notice lines after following")
    cursor.x = 500
    module:Disable()
end

print("Suite buff reminders note placement: " .. (mutation and ("mutation " .. mutation .. " survived") or
    "nine anchors, settings change and cursor following passed"))
