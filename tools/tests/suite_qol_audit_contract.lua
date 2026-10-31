-- Contract of the Quality of Life completeness audit: Edit Mode movers and a
-- scale for the loot notice, the loadout reminder and the group death notice;
-- a text size for the secondary stats; help for every section of the page;
-- muted sound files that need no volume profile, and a battleground profile;
-- a duration and a warning sound for the cues and alerts; the text style of
-- the action tracker, the dungeon cast stack and the threat meter; one
-- "Spell icon ID" line; conflicts with the addons that own the same surface.
-- Live Edit Mode drags, sounds and the client's refusal of an addon-made
-- frame still need an in-game check.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return false end
local Suite = Support.Load(root, "MSUF_Suite", {}, "Core/Suite.lua")
local catalog = Suite.SuiteCatalog
local ANCHORS = Support.AnchorPoints(root)

local function Anchor(name)
    for index, point in ipairs(ANCHORS) do
        if point == name then return index end
    end
end

-- The config of a module whose profile changed nothing.
local function Defaults(id)
    local config = {}
    for key, rule in pairs(catalog[id].rules) do config[key] = rule.default end
    return config
end

------------------------------------------------------------------ catalog
-- Surfaces that stood at a fixed place now have a mover and a scale, and keep
-- the place they had: point, x and y are where the frame stood before.
local MOVERS = {
    lootToastFilter = { element = "notices", point = "TOPRIGHT", x = -24, y = -162 },
    loadoutReminder = { element = "reminder", point = "TOP", x = 0, y = -155 },
    groupDeathAlert = { element = "notice", point = "CENTER", x = 0, y = 55 },
}
local function MoverCatalog()
    for id, want in pairs(MOVERS) do
        local spec, rules = catalog[id], catalog[id].rules
        Check(spec.editElement == want.element, id .. " has no Edit Mode element")
        Check(rules.point.default == Anchor(want.point) and rules.x.default == want.x and rules.y.default == want.y,
            id .. " does not start where it always stood")
        Check(rules.scale.default == 100 and rules.scale.min == 50 and rules.scale.max == 200,
            id .. " has no scale in percent")
        Check(rules.point.hidden and rules.x.hidden and rules.y.hidden, id .. " shows a second position control")
    end
    Check(catalog.groupDeathAlert.rules.scale.enableKey == "screen", "the notice scale applies without a notice")
    local size = catalog.combatStatsHUD.rules.fontSize
    Check(size and size.default == 15 and size.min == 10 and size.max == 24, "the secondary stats have no text size")
    Check(catalog.combatMovementCue.rules.duration.default == 2.5, "the movement cue starts with another duration")
end

local function AlertCatalog()
    for _, id in ipairs({ "durabilityAlert", "combatPetStatus", "combatMovementCue", "loadoutReminder" }) do
        local rule = catalog[id].rules.sound
        Check(rule and rule.default == false, id .. " does not offer a warning sound that starts off")
    end
    local function Has(list, name)
        for _, entry in ipairs(list) do
            if entry == name then return true end
        end
    end
    for _, name in ipairs({ "MikScrollingBattleText", "Parrot", "xCT+" }) do
        Check(Has(catalog.selfCombatText.conflicts, name), "own combat text does not yield to " .. name)
    end
    Check(Has(catalog.threatMeter.conflicts, "Omen"), "the threat meter does not yield to Omen")
end

-- Today's text of each surface: outlined and smooth, with the shadow it drew.
local TEXT_STYLES = { actionTracker = false, enemyCastStack = 70, threatMeter = 80 }
local function TextStyleCatalog()
    for id, opacity in pairs(TEXT_STYLES) do
        local rules = catalog[id].rules
        Check(rules.fontOutline.choices[rules.fontOutline.default] == "Outline", id .. " starts without its outline")
        Check(rules.fontRendering.choices[rules.fontRendering.default] == "Smooth", id .. " starts with other rendering")
        Check(rules.fontShadow.default == (opacity ~= false), id .. " starts with another shadow")
        Check(rules.fontShadowOpacity.default == (opacity or 100) and rules.fontShadowDistance.default == 1,
            id .. " starts with another shadow strength")
        Check(rules.fontShadow.requiresChoice and rules.fontShadowOpacity.enableKey == "fontShadow",
            id .. " offers a shadow that rendering cannot draw")
        local source = Read("MSUF_Suite_QualityOfLife/" .. id:sub(1, 1):upper() .. id:sub(2) .. ".lua")
        Check(source:find("S.QoLStyleText", 1, true) and not source:find('"OUTLINE"', 1, true),
            id .. " still styles its text by hand")
    end
end

-- The help text of each settings section, read from the page's own file.
local function HelpTexts()
    local help = {}
    for key, text in Read("MSUF_Suite_Options/Pages/QualityOfLifeHelp.lua"):gmatch('\n    ([%w_]+) = "([^\n]*)",') do
        help[key] = text
    end
    return help
end

-- The sections the page groups of Quality of Life modules list: each is a
-- heading with a help button, whether or not it holds settings.
local function PageSections()
    local listed = {}
    for _, page in ipairs({ "QualityOfLife", "QualityOfLifeComfort", "EverydayTools", "InventoryTools" }) do
        local source = Read("MSUF_Suite_Options/Pages/" .. page .. ".lua")
        for id, _, list in source:gmatch('{ id = "(%w+)"([^{}]*)sections = (%b{})') do
            if catalog[id] and catalog[id].page == "suite_qualityOfLife" then
                for section in list:gmatch('"([%w_]+)"') do listed[section] = id end
            end
        end
    end
    return listed
end

local function HelpCatalog()
    local help, listed = HelpTexts(), PageSections()
    local at = {}
    for index, file in ipairs(Support.TocFiles(root, "MSUF_Suite_Options")) do at[file] = index end
    Check(at["Pages/QualityOfLifeHelp.lua"] and at["Pages/QualityOfLifeHelp.lua"] < at["Pages/QualityOfLife.lua"],
        "the help loads after the page that asks for it")
    local sections = 0
    for section, id in pairs(listed) do
        Check(#(help[section] or "") > 30, id .. " section " .. section .. " has no help text")
        sections = sections + 1
    end
    Check(sections > 80, "the scan found only " .. sections .. " sections")
    for _, id in ipairs(Suite.SuiteOrder) do
        local spec = catalog[id]
        for _, rule in ipairs(spec.controls) do
            local section = spec.page == "suite_qualityOfLife" and rule.section
            Check(not section or listed[section], id .. " section " .. tostring(section) .. " is on no page")
        end
    end
end

local function SoundCatalog()
    local rules = catalog.soundProfiles.rules
    Check(rules.applyVolumes.default == true and rules.pvpProfile.default == false, "sound profile defaults changed")
    Check(rules.pvpMusic.default == 30 and rules.pvpAmbience.default == 50 and rules.pvpEffects.default == 100,
        "the battleground profile starts with other volumes")
    Check(rules.worldMusic.enableKey == "applyVolumes" and rules.raidEffects.enableKey == "applyVolumes"
        and rules.pvpMusic.enableKey == "pvpProfile" and rules.pvpProfile.enableKey == "applyVolumes",
        "the volume switches do not follow one another")
    Check(rules.mutedFileIDs.enableKey == nil, "muting sound files waits for the volume profiles")
end

------------------------------------------------------------------ harness
local clock = Support.Clock(100)
local function Widget()
    local widget = { shown = false, messages = {} }
    local methods = {}
    function methods:Show() self.shown = true end
    function methods:Hide() self.shown = false end
    function methods:IsShown() return self.shown end
    function methods:SetShown(value) self.shown = value == true end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:SetScale(value) self.scale = value end
    function methods:SetSize(width, height) self.width, self.height = width, height end
    function methods:SetText(text) self.text = text end
    function methods:CreateTexture() return Widget() end
    function methods:CreateFontString() return Widget() end
    function methods:AddMessage(...) self.messages[#self.messages + 1] = { ... } end
    function methods:Clear() self.messages = {} end
    function methods:SetFading(value) self.fading = value end
    return setmetatable(widget, { __index = function(_, key)
        if methods[key] then return methods[key] end
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
end
UIParent = Widget()
CreateFrame = function() return Widget() end
GameFontHighlightSmall, GameFontNormalSmall = {}, {}
SOUNDKIT = { RAID_WARNING = 1 }
IsInInstance = function() return false, "none" end
local sounds = 0
PlaySound = function() sounds = sounds + 1 end
-- What a module raised inside Dispatch (the Suite reports it and goes on).
local reported = {}

-- A Suite with the shared QoL bootstrap (cards, placement, the sound and text
-- helpers) and a module context that records its events.
local function World()
    local w = { movers = {}, modules = {}, combat = false }
    local S = {
        Public = function(value) return value ~= "secret" end,
        PublicText = function(value) return type(value) == "string" and value ~= "secret" and value ~= "" and value or nil end,
        Finite = function(value) return type(value) == "number" and value == value end,
        Text = function(value) return value end,
        RGB = function() return 1, 1, 1 end,
        Install = function(id, module) w.modules[id] = module end,
        CreateFrame = function() return Widget() end,
        CreateTexture = function() return Widget() end,
        CreateFontString = function() return Widget() end,
        PlaceEdges = function() end,
        SetFont = function(fontString, _, size) fontString.fontSize = size end,
        SetStyledFont = function(fontString, _, size, outline, rendering, shadow, opacity, distance)
            fontString.fontSize, fontString.style = size, { outline, rendering, shadow, opacity, distance }
        end,
        GlobalFontPath = function() return "font" end,
        Print = function() end,
        RegisterOwnedMover = function(id, element, spec) w.movers[id] = { element = element, spec = spec } end,
    }
    local NS = { AnchorPoints = ANCHORS, Client = { isForever = false }, IsSecret = function(value) return value == "secret" end,
        Safety = { IsForbidden = function() return false end },
        IsCombatLocked = function() return w.combat end, InCombat = function() return w.combat end }
    S.Dispatch = Support.Dispatcher(reported)
    NS.Dispatch = S.Dispatch
    Support.QoLStyleFixture(root, S)
    local contextOf = Support.ModuleTimers(root, S, NS)
    w.S, w.NS = S, NS
    function w:Load(file)
        if file == "LoadoutReminder" then
            assert(loadfile(root .. "/MSUF_Suite_Modules/LoadoutSnapshot.lua"))("MSUF_Suite_Modules", { Suite = S })
        end
        assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))(
            "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
    end
    function w:Start(id, file, config)
        self:Load(file)
        local module, events = self.modules[id], {}
        local context = contextOf(id, module, { events = events })
        function context:Event(name, callback) events[name] = callback end
        function context:RemoveEvent(name) events[name] = nil end
        module.context, module.config, module.active, module.events = context, config, true, events
        return module
    end
    return w
end

local function CountOf(map)
    local count = 0
    for _ in pairs(map) do count = count + 1 end
    return count
end

------------------------------------------------------------------ movers
local function Stands(frame, want)
    local point = frame.point
    return point and point[1] == want.point and point[2] == UIParent and point[3] == want.point
        and point[4] == want.x and point[5] == want.y
end

local function LootNotice()
    local w = World()
    w:Load("SharedItems")
    local module = w:Start("lootToastFilter", "LootToastFilter", Defaults("lootToastFilter"))
    module:Enable()
    module:RegisterMovers()
    local mover = w.movers.lootToastFilter
    Check(mover and mover.element == "notices" and mover.spec.getFrame() == module.host, "no mover for the loot notice")
    Check(mover.spec.sizeKeys[1] == "scale", "the loot notice mover has no scale")
    Check(Stands(module.host, MOVERS.lootToastFilter) and module.host.scale == 1, "the loot notice moved from its place")
    w.S.editMode = true
    module:Refresh()
    Check(#module.toasts == 3 and module.toasts[1].shown and module.toasts[3].shown,
        "Edit Mode shows no sample of the loot notice stack")
    Check(module.toasts[1].point[2] == module.host and module.toasts[2].point[5] == -53, "the toasts do not hang on the host")
    w.S.editMode = false
    module:HideEditPreview()
    Check(not module.toasts[1].shown and not module.toasts[3].shown, "the loot notice sample stayed")
    module.config.scale = 150
    module:Refresh()
    Check(module.host.scale == 1.5, "the loot notice ignores its scale")
end

local function LoadoutReminder()
    local w = World()
    C_SpecializationInfo = { GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 256, "Discipline" end }
    C_ClassTalents = { GetStarterBuildActive = function() return false end,
        GetLastSelectedSavedConfigID = function() return 100 end, GetActiveConfigID = function() return 7 end }
    C_Traits = { GetConfigInfo = function() return { name = "Raid" } end }
    GetLootSpecialization = function() return 0 end
    UnitGUID = function() return "Player-1" end
    local config = Defaults("loadoutReminder")
    config.onlyMismatch = true
    local module = w:Start("loadoutReminder", "LoadoutReminder", config)
    module:Enable()
    module:RegisterMovers()
    Check(module.host == nil, "the reminder made its frame before it had to")
    local mover = w.movers.loadoutReminder
    Check(mover and mover.element == "reminder" and mover.spec.getFrame() == module.host and module.host,
        "no mover for the loadout reminder")
    Check(Stands(module.host, MOVERS.loadoutReminder) and module.host.scale == 1, "the reminder moved from its place")
    w.S.editMode = true
    module:Refresh()
    Check(module.host.shown and module.title.text == "Current loadout" and module.detail.text:find("Sample", 1, true),
        "Edit Mode shows no sample of the reminder")
    w.S.editMode = false
    module:HideEditPreview()
    Check(not module.host.shown, "the reminder sample stayed")
    module:Test()
    Check(module.host.shown and module.detail.text == "Raid  |  Loot: Discipline (current)",
        "the test button shows nothing while only a mismatch would")
    module.config.scale = 200
    module:Refresh()
    Check(module.host.scale == 2, "the reminder ignores its scale")
end

local function DeathNotice()
    local w = World()
    IsInGroup, IsInRaid = function() return false end, function() return false end
    local config = Defaults("groupDeathAlert")
    config.screen = true
    local module = w:Start("groupDeathAlert", "GroupDeathAlert", config)
    module:Enable()
    module:RegisterMovers()
    local mover, screen = w.movers.groupDeathAlert, module.screen
    Check(mover and mover.element == "notice" and mover.spec.getFrame() == screen, "no mover for the death notice")
    Check(Stands(screen, MOVERS.groupDeathAlert) and screen.point[5] + screen.height / 2 == 160,
        "the death notice moved from its place near the screen center")
    Check(mover.spec.visible(), "the death notice mover waits for the notice")
    w.S.editMode = true
    module:Refresh()
    Check(#screen.messages == 1 and screen.messages[1][1]:find("A group member died", 1, true) and screen.fading == false,
        "Edit Mode shows no steady sample of the death notice")
    w.S.editMode = false
    module:HideEditPreview()
    Check(#screen.messages == 0 and screen.fading == true, "the death notice sample stayed")
    module.config.scale = 200
    module:Refresh()
    Check(screen.scale == 2, "the death notice ignores its scale")
    module.config.screen = false
    Check(not mover.spec.visible(), "the death notice mover stays without a notice")
end

------------------------------------------------------------------ text size and style
local function Sizes(module)
    local label, value = module.fields[1].label.fontSize, module.fields[1].value.fontSize
    return label, value, module.fpsText.fontSize
end

local function StatsText()
    local w = World()
    w:Load("SharedItems")
    GetFramerate = function() return 60 end
    w.S.ReadPercent = function() return 1 end
    w.S.ReadCrit = function() return 10, 100 end
    w.S.ReadHaste, w.S.ReadMastery, w.S.ReadVersatility = w.S.ReadCrit, w.S.ReadCrit, w.S.ReadCrit
    local config = Defaults("combatStatsHUD")
    config.fps = 3
    local module = w:Start("combatStatsHUD", "CombatStatsHUD", config)
    module:Enable()
    local label, value, fps = Sizes(module)
    Check(label == 10 and value == 15 and fps == 14, "the secondary stats start with other text sizes")
    config.fontSize = 20
    module:Refresh()
    label, value, fps = Sizes(module)
    Check(label == 15 and value == 20 and fps == 19, "the text size does not reach the strip")
    config.fontSize = 10
    module:Refresh()
    label, value, fps = Sizes(module)
    Check(label == 8 and value == 10 and fps == 9, "the stat names grew unreadable")
end

local function TextStyleHelper()
    local w = World()
    local text = Widget()
    local config = { fontOutline = 3, fontRendering = 2, fontShadow = true, fontShadowOpacity = 60, fontShadowDistance = 2 }
    w.S.QoLStyleText(text, config, "font", 14)
    Check(text.fontSize == 14 and text.style[1] == "THICKOUTLINE" and text.style[2] == 2 and text.style[3] == true
        and text.style[4] == 60 and text.style[5] == 2, "the text style choices do not reach the font")
    config.fontOutline = 1
    w.S.QoLStyleText(text, config, "font", 14)
    Check(text.style[1] == "", "no outline still draws one")
    local defaults = Defaults("enemyCastStack")
    w.S.QoLStyleText(text, defaults, "font", 12)
    Check(text.style[1] == "OUTLINE" and text.style[2] == 1 and text.style[3] == true and text.style[4] == 70
        and text.style[5] == 1, "the dungeon cast stack starts with another text look")
end

------------------------------------------------------------------ warning sounds and the cue duration
local function Heard(action)
    local before = sounds
    action()
    return sounds - before
end

local function DurabilitySound()
    local w = World()
    w.S.ReadInfoSource = function() return .2 end
    local config = Defaults("durabilityAlert")
    local module = w:Start("durabilityAlert", "DurabilityAlert", config)
    Check(Heard(function() module:Enable() end) == 0 and module.host.shown, "a silent warning played a sound")
    config.sound = true
    module.host:Hide()
    Check(Heard(function() module:Refresh() end) == 1, "the durability warning is not heard")
    Check(Heard(function() module:Refresh() end) == 0, "a repaint of the shown warning played again")
end

local function PetSound()
    local w = World()
    UnitClassBase = function() return "HUNTER" end
    UnitExists = function() return false end
    C_SpellBook = { IsSpellKnown = function(id) return id == 883 end }
    local config = Defaults("combatPetStatus")
    config.sound = true
    local module = w:Start("combatPetStatus", "CombatPetStatus", config)
    Check(Heard(function() module:Enable() end) == 1 and module.host.shown, "the pet warning is not heard")
    Check(Heard(function() module.events.PLAYER_ENTERING_WORLD(module) end) == 0, "the shown pet warning played again")
    config.sound = false
    module.host:Hide()
    Check(Heard(function() module:Refresh() end) == 0, "a silent pet warning played a sound")
end

local function Cue(duration, sound)
    local w = World()
    C_SpellBook = { IsSpellKnown = function() return true end }
    C_Spell = { GetSpellCooldown = function() return { isActive = false, isEnabled = true } end,
        IsSpellUsable = function() return true end, GetSpellName = function() return "Leap" end,
        GetSpellTexture = function() return 1 end }
    local config = Defaults("combatMovementCue")
    config.spellIDs, config.combatOnly, config.duration, config.sound = "101", false, duration, sound
    local module = w:Start("combatMovementCue", "CombatMovementCue", config)
    module:Enable()
    return module
end

local function MovementCue()
    local cue = Cue(2.5, true)
    Check(Heard(function() cue.events.PLAYER_STARTED_MOVING(cue) end) == 1 and cue.host.shown, "the movement cue is not heard")
    clock.Advance(2.4)
    Check(cue.host.shown, "the cue left before its default duration")
    clock.Advance(.2)
    Check(not cue.host.shown, "the cue outstayed its default duration")
    local long = Cue(6, false)
    Check(Heard(function() long.events.PLAYER_STARTED_MOVING(long) end) == 0 and long.host.shown,
        "a silent movement cue played a sound")
    clock.Advance(5.9)
    Check(long.host.shown, "the cue ignored its longer duration")
    clock.Advance(.2)
    Check(not long.host.shown, "the cue outstayed its chosen duration")
end

local function ReminderSound()
    local w = World()
    local config = Defaults("loadoutReminder")
    config.sound = true
    local module = w:Start("loadoutReminder", "LoadoutReminder", config)
    module:Enable()
    Check(Heard(function() module:Test() end) == 1, "the loadout reminder is not heard")
    config.sound = false
    Check(Heard(function() module:Test() end) == 0, "a silent loadout reminder played a sound")
end

------------------------------------------------------------------ sound profiles
local function SoundProfiles()
    local w = World()
    local volumes, muted, kind = {}, {}, "world"
    w.S.RestoreCVar = function(_, key) volumes[key] = nil end
    w.S.InstanceKind = function() return kind end
    MuteSoundFile = function(id) muted[id] = true end
    UnmuteSoundFile = function(id) muted[id] = nil end
    w:Load("SharedItems")
    -- A profile saved before the new switches knew neither of them.
    local config = Defaults("soundProfiles")
    config.applyVolumes, config.pvpProfile, config.mutedFileIDs = nil, nil, "111 222"
    config.worldMusic, config.partyMusic, config.pvpMusic = 10, 40, 15
    local module = w:Start("soundProfiles", "SoundProfiles", config)
    module.context.CVar = function(_, key, value) volumes[key] = value end
    module:Enable()
    Check(volumes.Sound_MusicVolume == .1 and CountOf(module.events) == 3 and muted[111] and muted[222],
        "an existing profile no longer gets its volume profile")
    kind = "party"
    module.events.ZONE_CHANGED_NEW_AREA(module)
    Check(volumes.Sound_MusicVolume == .4, "the dungeon profile stopped following the activity")
    config.applyVolumes = false
    module:Refresh()
    Check(next(volumes) == nil and next(module.events) == nil and muted[111] and muted[222],
        "muting sound files still needs the volume profiles")
    config.mutedFileIDs = "222 333"
    module:Refresh()
    Check(not muted[111] and muted[222] and muted[333] and next(volumes) == nil, "a list edit touched the volumes")
    config.applyVolumes = true
    module:Refresh()
    Check(volumes.Sound_MusicVolume == .4 and CountOf(module.events) == 3, "the volume profiles did not come back")
    kind = "pvp"
    module.events.ZONE_CHANGED_NEW_AREA(module)
    Check(next(volumes) == nil, "battlegrounds got a profile nobody asked for")
    config.pvpProfile = true
    module:Refresh()
    Check(volumes.Sound_MusicVolume == .15, "the battleground profile did not apply")
    module.active = false
    module:Disable()
    Check(next(volumes) == nil and next(muted) == nil, "disable left volumes or sound files changed")
end

------------------------------------------------------------------ one spell icon line
local function IconLines(first, alt, ids, details)
    local w = World()
    local lines = {}
    local tooltip = Widget()
    tooltip.AddDoubleLine = function(_, left, right) lines[#lines + 1] = { left, right } end
    GameTooltip = tooltip
    Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2, Quest = 3, Currency = 4, Mount = 10 } }
    canaccesstable = function() return true end
    IsAltKeyDown = function() return alt end
    hooksecurefunc = function() end
    C_Spell = { GetSpellTexture = function() return 135810 end }
    local fixture = Support.TooltipFixture(root, w.S, w.NS)
    w.S.TooltipBorder = { Restore = function() end }
    local function Start(id, file, on)
        local config = Defaults(id)
        config.showSpellIcon, config.iconID = on, on
        local module = w:Start(id, file, config)
        module:Enable()
    end
    local order = { { "tooltipIDs", "TooltipIDs", ids }, { "tooltipDetails", "TooltipDetails", details } }
    if not first then order[1], order[2] = order[2], order[1] end
    for _, entry in ipairs(order) do Start(entry[1], entry[2], entry[3]) end
    fixture.Run(Enum.TooltipDataType.Spell, tooltip, { id = 133 })
    local count = 0
    for _, line in ipairs(lines) do
        if line[1] == "Spell icon ID" then count = count + 1 end
    end
    return count
end

local function SpellIconLine()
    for _, idsFirst in ipairs({ true, false }) do
        Check(IconLines(idsFirst, true, true, true) == 1, "two options printed the spell icon ID twice")
    end
    Check(IconLines(true, true, true, false) == 1, "Tooltip IDs lost its spell icon ID")
    Check(IconLines(true, true, false, true) == 1, "Tooltip details lost its spell icon ID")
    Check(IconLines(true, false, true, true) == 1, "Tooltip details lost its line while Alt is up")
    Check(IconLines(true, false, true, false) == 0, "Tooltip IDs printed without Alt")
end

MoverCatalog()
AlertCatalog()
TextStyleCatalog()
HelpCatalog()
SoundCatalog()
LootNotice()
LoadoutReminder()
DeathNotice()
StatsText()
TextStyleHelper()
DurabilitySound()
PetSound()
MovementCue()
ReminderSound()
SoundProfiles()
SpellIconLine()
Check(#reported == 0, "a module raised: " .. tostring(reported[1]))
print("PASS Quality of Life audit: movers, text size, help, mute independence, cues, text style, one icon line ("
    .. checks .. " checks)")
