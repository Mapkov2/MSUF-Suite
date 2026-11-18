local root = assert(arg[1], "Suite checkout required")
local function Equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local function Widget()
    local w = { shown = true, writes = 0 }
    local function Noop() end
    w.SetFrameStrata, w.SetClampedToScreen, w.SetStatusBarTexture = Noop, Noop, Noop
    w.SetMinMaxValues, w.SetAllPoints, w.SetColorTexture = Noop, Noop, Noop
    w.SetJustifyH, w.SetWordWrap, w.SetMaxLines, w.EnableMouse = Noop, Noop, Noop, Noop
    w.ClearAllPoints = Noop
    function w:SetStatusBarColor(r, g, b)
        self.red, self.green, self.blue = r, g, b
        self.colorWrites = (self.colorWrites or 0) + 1
    end
    function w:EnableMouse(enabled) self.mouse = enabled end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:GetSize() return self.width, self.height end
    function w:GetWidth() return self.width end
    function w:SetWidth(width) self.width = width end
    function w:SetPoint(point, relative, _, x, y)
        if relative == UIParent then self.x, self.y = x, y end
    end
    function w:GetCenter() return UIParent:GetWidth() / 2 + self.x end
    function w:GetBottom() return self.y end
    function w:GetRect() return self.left, self.y, self.width, self.height end
    function w:GetEffectiveScale() return self.scale or 1 end
    function w:GetEffectiveAlpha() return self.alpha or 1 end
    function w:SetScript(event, callback) self[event] = callback end
    function w:IsShown() return self.shown end
    w.IsVisible = w.IsShown
    function w:SetShown(shown) self.shown = shown end
    function w:Hide() self.shown = false end
    function w:SetText(value) self.text, self.writes = value, self.writes + 1 end
    function w:SetValue(value) self.value, self.writes = value, self.writes + 1 end
    return w
end

UIParent = Widget()
UIParent:SetSize(1280, 720)
GameTooltip = { IsOwned = function() return false end }
local config = { enabled = false, factionID = 0, x = 0, y = 160 }
local module, mover, menu
local panelConfig, inCombat = {}, false
FACTION_BAR_COLORS = {
    [2] = { r = .8, g = .1, b = .1 },
    [4] = { r = .9, g = .8, b = .1 },
    [5] = { r = .1, g = .7, b = .2 },
}
local S = {
    Text = function(value) return value end,
    CreateFrame = Widget, CreateTexture = Widget, CreateFontString = Widget,
    ResolveTexture = function() return "texture" end,
    Config = function(id) return id == "characterPanel" and panelConfig or config end,
    RGB = function(hex) return tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 end,
    Install = function(_, value) module = value end,
    Set = function(_, key, value) config[key] = value end,
    SetMany = function(_, values) for key, value in pairs(values) do config[key] = value end end,
    RegisterOwnedMover = function(_, _, spec) mover = spec end,
}
local secret = newproxy()
local NS = { Suite = S, Text = S.Text, Public = function(value) return not rawequal(value, secret) end,
    String = function(value) if type(value) == "string" then return value end end }
NS.Host = { Finite = function(value) return type(value) == "number" end, MSUFMedia = {},
    Safety = { IsForbidden = function() return false end }, InCombat = function() return inCombat end }
function NS.Number(value) if NS.Host.Finite(value) then return value end end
S.ContextMenu = function(button, generator, ...)
    menu = {
        CreateTitle = function(self, title) self.title = title end,
        CreateCheckbox = function(self, label, checked, toggle, id)
            self[label] = { checked = function() return checked(id) end, toggle = function() return toggle(id) end }
        end,
    }
    generator(button, menu, ...)
end

local function Load(file, private) return assert(loadfile(root .. "/" .. file))("MSUF_Suite", private) end
local core = { Text = S.Text, Client = {}, Suite = S, Skin = { Acquire = function() end } }
Load("MSUF_Suite/Core/SuiteCatalog.lua", core)
Load("MSUF_Suite/Core/CharacterTabs.lua", core)
Load("MSUF_Suite/Core/CharacterBindings.lua", core)
Load("MSUF_Suite/Core/Catalog/CharacterPanel.lua", core)
Load("MSUF_Suite/Core/CharacterHeader.lua", core)
NS.Host.CharacterHeader = core.CharacterHeader
assert(core.SuiteCatalog.reputationBar.follows == "characterPanel", "color changes cannot refresh the HUD")
local hostileRule = core.SuiteCatalog.characterPanel.rules.reputationColorHostile
assert(hostileRule.color and not hostileRule.hidden and hostileRule.default == "", "missing Colors menu rule")
Equal(hostileRule.resolveColor(), .8, "inherited hostile color")
Load("MSUF_Suite_CharacterPanel/Reputation.lua", NS)
Load("MSUF_Suite_CharacterPanel/ReputationBar.lua", NS)
AT_WAR = "At War"
local city = { factionID = 72, canToggleAtWar = false, atWarWith = false }
local clan = { factionID = 47, canToggleAtWar = true, atWarWith = false }
local factions, indexReads, toggles = { city, clan }, 0, 0
C_Reputation = {
    GetFactionDataByID = function(id) return id == clan.factionID and clan or city end,
    GetNumFactions = function() return #factions end,
    GetFactionDataByIndex = function(index)
        indexReads = indexReads + 1
        return factions[index]
    end,
    ToggleFactionAtWar = function(index)
        assert(factions[index] == clan, "toggled a different faction after the list changed")
        clan.atWarWith = not clan.atWarWith
        toggles = toggles + 1
    end,
}
local row = { factionID = 72, factionName = "Stormwind" }
NS.OpenReputationMenu(row)
Equal(menu.title, "Stormwind", "row menu title")
assert(not menu[AT_WAR], "unavailable war control was offered")
local track = menu["Show as reputation bar"]
assert(not track.checked())
row.factionID, row.factionName = 47, "Gelkis Clan Centaur"
track.toggle()
assert(track.checked() and config.factionID == 72, "recycled row changed the faction behind the open menu")
track.toggle()
assert(not config.enabled, "the selected row could not remove its bar")
NS.OpenReputationMenu(row)
menu["Show as reputation bar"].toggle()
assert(config.enabled and config.factionID == 47, "the second faction did not replace the selection")
local war = assert(menu[AT_WAR], "toggleable faction has no war control")
assert(war.checked() == false)
Equal(indexReads, 0, "building or reading the menu scanned the faction list")

row.factionID, row.factionName = city.factionID, "Stormwind"
factions = { clan, city }
war.toggle()
assert(war.checked() == true and toggles == 1, "could not mark the original faction at war")
war.toggle()
assert(war.checked() == false and toggles == 2, "could not clear the war flag")

local beforeCombat = indexReads
inCombat = true
war.toggle()
Equal(indexReads, beforeCombat, "combat scanned the faction list")
Equal(toggles, 2, "combat toggled the faction")
inCombat = false

factions = { city }
war.toggle()
Equal(toggles, 2, "a stale menu toggled a faction missing from the list")
factions = { clan, city }
clan.canToggleAtWar = secret
war.toggle()
Equal(toggles, 2, "a restricted faction flag allowed the toggle")
row.factionID = clan.factionID
NS.OpenReputationMenu(row)
assert(not menu[AT_WAR], "secret permission exposed a war control")
clan.canToggleAtWar, clan.atWarWith = true, secret
NS.OpenReputationMenu(row)
assert(not menu[AT_WAR], "secret war state exposed a war control")

local reads, standing, reaction = 0, 650, 2
C_Reputation = {
    GetFactionDataByID = function(id)
        reads = reads + 1
        assert(id == 47, "did not read by the chosen faction ID")
        if standing then return { name = "Ironforge", reaction = reaction } end
    end,
    GetWatchedFactionData = function() error("bar queried the watched faction") end,
}
S.ReadFactionReputation = function(_, _, detailed)
    assert(detailed, "bar did not request progress")
    return "standing", "Friendly", standing, 1000, false
end

local xp = Widget()
xp.left, xp.y, xp.scale = 100, 150, 1.25
xp:SetSize(400, 48)
S.ExperienceBarPlacement = function() if xp:IsShown() then return xp, 12, 3 end end
local events = {}
module.config, module.active = config, true
module.context = {
    Event = function(_, event, callback, options)
        local transition = event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED"
        assert(transition == (options and options.inCombat == true or false))
        events[event] = callback
    end,
    RemoveEvent = function(_, event) events[event] = nil end,
}
module:Enable()
Equal(module.host.y, 142.5, "below the scaled XP text")
Equal(module.nameText.text, "Ironforge", "selected faction label")
Equal(module.percentText.text, "65%", "selected faction progress")
Equal(module.host.red, .8, "native hostile color")
Equal(module.host.green, .1, "native hostile color")

local function Fire(event, ...) events[event](module, event, ...) end
Equal(reads, 1, "initial faction reads")
Fire("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 81)
Equal(reads, 1, "unrelated renown read")
local writes, colorWrites = module.host.writes, module.host.colorWrites
Fire("UPDATE_FACTION")
Equal(module.host.writes, writes, "unchanged value repainted")
Equal(module.host.colorWrites, colorWrites, "unchanged rank repainted the color")
standing = 700
Fire("UPDATE_FACTION")
Equal(module.host.value, .7, "event-driven value")
Equal(module.host.y, 142.5, "reputation update moved the bar")
assert(not events.PLAYER_XP_UPDATE and not module.host.OnUpdate)

reaction = 4
Fire("UPDATE_FACTION")
Equal(module.host.red, .9, "neutral rank update")
Equal(module.host.green, .8, "neutral rank update")
panelConfig.reputationColorNeutral = "ff00ff"
module:Refresh()
Equal(module.host.blue, 1, "applied custom neutral color")
Equal(module.host.green, 0, "applied custom neutral color")

Fire("PLAYER_REGEN_DISABLED")
inCombat = true
assert(not events.UPDATE_FACTION and not events.MAJOR_FACTION_UNLOCKED
    and not events.MAJOR_FACTION_RENOWN_LEVEL_CHANGED and not events.UI_SCALE_CHANGED and not module.host.mouse)
reaction, standing = 5, 800
local combatReads, combatColorWrites = reads, module.host.colorWrites
module:Refresh()
Equal(reads, combatReads, "combat faction query")
Equal(module.host.colorWrites, combatColorWrites, "combat color write")
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
Equal(reads, combatReads + 1, "one catch-up read after combat")
Equal(module.host.green, .7, "catch-up rank color")
Equal(module.host.value, .8, "catch-up progress")
assert(events.UPDATE_FACTION and module.host.mouse)

xp.y = 5
S.SyncReputationBarPlacement()
Equal(module.host.y, 80, "above an XP bar near the bottom edge")
xp.y, xp.height = 0, 600
S.SyncReputationBarPlacement()
assert(module.host.x > 0 and module.host.y > 20, "tall centered XP layout did not use side space")

module:RegisterMovers()
assert(mover.visible() and mover.getFrame() == module.host and mover.moveValues.manualPosition)
local origin = {}
mover.capture(origin)
Equal(origin.x, module.host.x, "drag origin uses the live automatic anchor")
config.manualPosition, config.x, config.y = true, -80, 210
module:Refresh()
xp.y = 200
S.SyncReputationBarPlacement()
Equal(module.host.x, -80, "saved edit position x")
Equal(module.host.y, 210, "saved edit position y")

config.manualPosition, config.x, config.y = false, 0, 160
xp:Hide()
local native = Widget()
native.left, native.y = 400, 8
native:SetSize(400, 20)
native.bars = { [1] = Widget() }
StatusTrackingBarManager = { barContainers = { native } }
StatusTrackingBarInfo = { BarsEnum = { Experience = 1 } }
S.SyncReputationBarPlacement()
Equal(module.host.y, 42, "above the native XP container")
native.bars[1].alpha = 0
S.SyncReputationBarPlacement()
Equal(module.host.y, 160, "normal position when XP is hidden")
standing = nil
Fire("UPDATE_FACTION")
assert(not module.host:IsShown(), "missing faction was still visible")
S.editMode = true
module:Refresh()
assert(module.host:IsShown(), "missing faction could not be moved in Edit Mode")
module:Disable()
assert(not module.host:IsShown())

local shared = {}
Load("MSUF_Suite/Core/ExperienceBarLayout.lua", shared)
local qol = { NS = shared, Suite = S }
Load("MSUF_Suite_QualityOfLife/ExperienceBarText.lua", qol)
local textStates = {}
for _, spec in ipairs(shared.ExperienceBarLayout.Texts) do textStates[spec.id] = {} end
textStates.eta = { enabled = true, point = "TOPRIGHT", relative = "BOTTOMRIGHT", y = -60, size = 18 }
textStates.level = { enabled = true, point = "BOTTOM", relative = "TOP", y = 9, size = 16 }
local below, above = qol.ExperienceBarText.VerticalOverflow({ config = { height = 18 }, xpTexts = textStates })
Equal(below, 59, "XP text below the normal host padding")
Equal(above, 29, "XP text above the normal host padding")
