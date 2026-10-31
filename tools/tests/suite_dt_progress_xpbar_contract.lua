-- The experience bar's Track choice: experience (the bar as it always was),
-- reputation, honor, or Automatic. Each choice registers only the events it
-- needs, colors the fill by source, and shows reputation and honor at the
-- level cap where the experience bar hides.
-- The reputation resolver itself: suite_dt_progress_contract.lua.
local root = assert(arg[1], "repository root required")
local function eq(a, b, label) assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local EXPERIENCE, REPUTATION, HONOR, AUTOMATIC = 1, 2, 3, 4
local level, xp, maximum, capped = 10, 100, 1000, false
local watched, honor

local function Widget(parent)
    local w = { shown = true, parent = parent }
    function w:SetFrameStrata() end
    function w:EnableMouse() end
    function w:SetScript(key, callback) self[key] = callback end
    function w:CreateTexture() return Widget() end
    function w:CreateFontString() return Widget() end
    function w:SetPoint() end
    function w:ClearAllPoints() end
    function w:SetColorTexture(...) self.color = { ... } end
    function w:SetVertexColor(...) self.vertex = { ... } end
    function w:SetTexture(value) self.texture = value end
    function w:SetAllPoints() end
    function w:SetScale(value) self.scale = value end
    function w:GetEffectiveScale() return 1 end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetShown(value) self.shown = value end
    function w:IsShown() return self.shown end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetText(value) self.text = value end
    function w:SetWidth(value) self.width = value end
    function w:SetHeight(value) self.height = value end
    function w:SetJustifyH() end
    function w:SetTextColor() end
    function w:SetFont() return true end
    return w
end
UIParent = Widget()
CreateFrame = function(_, _, parent) return Widget(parent) end
GetServerTime = function() return 100000 end
UnitLevel = function() return level end
UnitXP = function() return xp end
UnitXPMax = function() return maximum end
GetXPExhaustion = function() return 0 end
UnitGUID = function() return "Player-test" end
BreakUpLargeNumbers = tostring
RENOWN_LEVEL_LABEL, HONOR_LEVEL_LABEL = "Renown %d", "Honor Level %d"
GameTooltip = { lines = {} }
function GameTooltip:SetOwner(owner) self.owner = owner end
function GameTooltip:IsOwned(owner) return self.shown and self.owner == owner end
function GameTooltip:ClearLines() self.lines = {} end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " | " .. right end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false end
GameRulesUtil = { IsPlayerAtEffectiveMaxLevel = function() return capped end }
C_Timer = { After = function() end }
Enum = { SecondsFormatterInterval = { Seconds = 1 }, SecondsFormatterAbbreviation = { OneLetter = 2 } }
C_StringUtil = { CreateSecondsFormatter = function()
    local formatter = {}
    function formatter:SetDesiredUnitCount() end
    function formatter:SetMinInterval() end
    function formatter:SetDefaultAbbreviation() end
    function formatter:Format(seconds) return seconds .. "s" end
    return formatter
end }
local MEDIA = { font = "font.ttf", barTexture = "bar.tga" }

local suite = { editMode = false, loginKind = "login", RootDB = {}, MSUFMedia = MEDIA,
    InCombat = function() return false end, IsCombatLocked = function() return false end,
    Dispatch = function(callback, ...) return callback(...) end,
    AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" } }
suite.Suite = { instances = {}, editMode = false }
local runtime = suite.Suite
runtime.ApplyOwnedLayer = function() return false end
runtime.ApplyOwnedChildLayer = function() return false end
runtime.GlobalFontPath = function() return MEDIA.font end
runtime.Public = function(value) return value ~= "secret" end
runtime.Number = function(value) return runtime.Public(value) and type(value) == "number" and value == value end
runtime.Finite = runtime.Number
runtime.Text = function(value) return value end
runtime.CreateFrame = CreateFrame
runtime.CreateTexture = function(parent, ...) return parent:CreateTexture(...) end
runtime.CreateFontString = function(parent, ...) return parent:CreateFontString(...) end
runtime.ResolveTexture = function(_, fallback) return fallback end
runtime.RGB = function(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
runtime.Install = function(id, module) runtime.instances[id] = module end
runtime.RegisterOwnedMover = function() return true end
runtime.Config = function() return runtime.instances.xpBar.config end
runtime.SetFont = function(fontString, path, size, flags) return fontString:SetFont(path, size, flags) end
-- MSUF_Suite_Modules/PlayerReaders.lua is the real reader; these are its results.
runtime.ReputationProgress = function() return watched end
runtime.HonorProgress = function() if honor then return honor.current, honor.maximum, honor.level end end
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", suite)
MSUFSuite = suite
local private = {}
for _, file in ipairs({ "Bootstrap", "NativeExperienceBar", "ExperienceTrack", "ExperienceBar" }) do
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))("MSUF_Suite_QualityOfLife", private)
end
local module = runtime.instances.xpBar
module.active = true
module.config = { enabled = true, look = 1, width = 400, height = 18, scale = 100, displayStyle = 1,
    showSegments = true, showRested = true, showSession = true, showRate = true, showETA = true,
    hideAtMax = true, point = 8, x = 0, y = 148, track = EXPERIENCE }
-- The module's context: the events it holds now.
local registered, registrations = {}, 0
module.context = dofile(root .. "/tools/tests/suite_test_support.lua").ModuleTimers(root, runtime, suite)(
    "xpBar", module, {
        Event = function(_, name, callback, allowCombat)
            assert(allowCombat and not registered[name], name .. " registered twice or outside combat")
            registered[name], registrations = callback, registrations + 1
        end,
        RemoveEvent = function(_, name) assert(registered[name], name .. " was never registered"); registered[name] = nil end,
    })

local function Events()
    local names = {}
    for name in pairs(registered) do
        if name ~= "PLAYER_ENTERING_WORLD" and name ~= "ADDON_LOADED" then names[#names + 1] = name end
    end
    table.sort(names)
    return table.concat(names, " ")
end
local XP_EVENTS = "PLAYER_LEVEL_UP PLAYER_XP_UPDATE UPDATE_EXHAUSTION"
local REPUTATION_EVENTS = "MAJOR_FACTION_RENOWN_LEVEL_CHANGED UPDATE_FACTION"
local function Choose(track)
    module.config.track = track
    module:Refresh()
end

-- Experience is the bar as it always was.
module:Enable()
eq(Events(), XP_EVENTS, "experience events")
assert(module.host:IsShown() and module.levelText.text:find("100 / 1.0k", 1, true), "the experience bar changed")
level, xp, maximum, capped = 80, 0, 0, true
registered.PLAYER_LEVEL_UP(module, "PLAYER_LEVEL_UP")
assert(not module.host:IsShown(), "the experience track hides at the level cap, as it always did")
eq(Events(), XP_EVENTS, "experience events at the cap")

-- Reputation: its own events only, and the bar shows at the level cap.
watched = { name = "Dragonscale", label = "Renown 12", current = 1200, maximum = 2500, kind = "renown", capped = false }
Choose(REPUTATION)
eq(Events(), REPUTATION_EVENTS, "reputation events")
assert(module.host:IsShown(), "the reputation track hides at the level cap")
eq(module.levelText.text, "Renown 12  1.2k / 2.5k", "reputation step")
eq(module.percentText.text, "48.0%", "reputation percent")
eq(module.details.text, "Dragonscale", "the faction's name")
assert(not module.rested:IsShown() and not module.restedMarker:IsShown(), "rested XP showed on a reputation bar")
local renownBlue = module.fill.vertex
assert(renownBlue[3] > renownBlue[1], "renown paints blue")
watched.kind, watched.label = "standing", "Friendly"
registered.UPDATE_FACTION(module, "UPDATE_FACTION")
assert(module.fill.vertex[2] > module.fill.vertex[1] and module.fill.vertex[2] > module.fill.vertex[3],
    "a standing paints green")
watched.current, watched.maximum, watched.capped = 1, 1, true
registered.UPDATE_FACTION(module, "UPDATE_FACTION")
eq(module.levelText.text, "Friendly", "a capped faction shows its standing alone")
eq(module.percentText.text, "100.0%", "a capped faction is full")
module.host.OnEnter(module.host)
eq(GameTooltip.lines[1], "Dragonscale", "tooltip title")
eq(GameTooltip.lines[2], "Friendly", "tooltip standing")
module.host.OnLeave(module.host)
watched = nil
registered.UPDATE_FACTION(module, "UPDATE_FACTION")
eq(module.levelText.text, "Nothing to track", "no watched faction")
module.config.displayStyle = 1
-- Honor.
honor = { current = 500, maximum = 2000, level = 25 }
Choose(HONOR)
eq(Events(), "HONOR_XP_UPDATE", "honor events")
eq(module.levelText.text, "Honor Level 25  500 / 2.0k", "honor step")
assert(module.fill.vertex[1] > module.fill.vertex[3], "honor paints orange")
honor.current = 1000
registered.HONOR_XP_UPDATE(module, "HONOR_XP_UPDATE")
eq(module.percentText.text, "50.0%", "honor follows its event")

-- Automatic: experience while leveling, then the watched reputation, then honor.
level, xp, maximum, capped = 20, 100, 1000, false
watched = { name = "Dragonscale", label = "Renown 12", current = 1200, maximum = 2500, kind = "renown", capped = false }
Choose(AUTOMATIC)
eq(Events(), XP_EVENTS, "Automatic follows experience while leveling")
assert(module.levelText.text:find("100 / 1.0k", 1, true), "Automatic shows experience while leveling")
local accent = { module.fill.vertex[1], module.fill.vertex[2], module.fill.vertex[3] }
level, xp, maximum, capped = 80, 0, 0, true
registered.PLAYER_LEVEL_UP(module, "PLAYER_LEVEL_UP")
eq(Events(), REPUTATION_EVENTS, "Automatic follows the watched reputation at the cap")
eq(module.levelText.text, "Renown 12  1.2k / 2.5k", "Automatic shows the watched reputation")
assert(module.host:IsShown(), "Automatic hid the bar at the level cap")
watched = nil
registered.UPDATE_FACTION(module, "UPDATE_FACTION")
eq(Events(), "HONOR_XP_UPDATE MAJOR_FACTION_RENOWN_LEVEL_CHANGED UPDATE_FACTION",
    "Automatic without a reputation follows honor and a newly watched reputation")
eq(module.levelText.text, "Honor Level 25  1.0k / 2.0k", "Automatic falls back to honor")
watched = { name = "Dragonscale", label = "Renown 13", current = 5, maximum = 2500, kind = "renown", capped = false }
registered.UPDATE_FACTION(module, "UPDATE_FACTION")
eq(Events(), REPUTATION_EVENTS, "a newly watched reputation takes over from honor")
honor = nil
watched = nil
registered.UPDATE_FACTION(module, "UPDATE_FACTION")
eq(module.levelText.text, "Nothing to track", "Automatic with nothing to show")
assert(not module.host:IsShown(), "Automatic with nothing to show stayed on screen")

-- Back to experience: the events and the look return as they were.
level, xp, maximum, capped = 10, 100, 1000, false
Choose(EXPERIENCE)
eq(Events(), XP_EVENTS, "experience events return")
assert(module.levelText.text:find("100 / 1.0k", 1, true) and module.host:IsShown(), "the experience bar came back")
eq(module.fill.vertex[1], accent[1], "the look's accent returns to the fill")
eq(module.fill.vertex[3], accent[3], "the look's accent returns to the fill")
local before = registrations
module:Refresh()
module:Refresh()
eq(registrations, before, "refreshing registered events again")
-- The same events survive a disable and enable of the module.
module:Disable()
registered = {}
module:Enable()
eq(Events(), XP_EVENTS, "events after enabling again")

-- The menu preview shows the choice with sample values and never reads the game.
local function Preview(track)
    local config = {}
    for key, value in pairs(module.config) do config[key] = value end
    config.track = track
    local parent = Widget()
    runtime.DrawExperienceBarPreview(parent, config, { xp = 50, rested = 0 })
    return parent.suiteXPPreview
end
watched, honor = nil, nil
local view = Preview(REPUTATION)
eq(view.levelText.text, "Renown 12  1.3k / 2.5k", "reputation preview")
view = Preview(HONOR)
eq(view.levelText.text, "Honor Level 25  1.3k / 2.5k", "honor preview")
view = Preview(AUTOMATIC)
assert(view.levelText.text:find("Lv 42", 1, true), "Automatic previews a leveling character")
view = Preview(EXPERIENCE)
assert(view.levelText.text:find("Lv 42", 1, true), "experience preview")

print("xp bar track PASS")
