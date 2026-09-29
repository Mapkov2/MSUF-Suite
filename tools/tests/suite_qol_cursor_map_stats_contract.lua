local root = assert(arg[1], "repository root required")
local installed = {}
local combat = false
local timerQueue = {}
local pointX, pointY = 100, 120
local currentSpec, lootSpec = 1, 0
local castDuration, gcdDuration = nil, { token = "gcd" }
local hasteValue = 22.5
local petExists, petDead = false, false
local landingOpens, vaultOpens, journalOpens, mapOpens = 0, 0, 0, 0

local function Region()
    local region = { shown = true, scripts = {} }
    function region:SetSize(w, h) self.width, self.height = w, h end
    function region:SetWidth(w) self.width = w end
    function region:SetScale(v) self.scale = v end
    function region:SetAlpha(v) self.alpha = v end
    function region:SetColorTexture(...) self.color = { ... } end
    function region:SetVertexColor(...) self.vertex = { ... } end
    function region:SetTexture(v) self.texture = v end
    function region:SetText(v) self.text = v end
    function region:SetTextColor() end
    function region:SetJustifyH() end
    function region:SetRotation() end
    function region:SetPoint(...) self.point = { ... } end
    function region:ClearAllPoints() self.point = nil end
    function region:SetAllPoints() end
    function region:SetFrameStrata() end
    function region:RegisterForClicks() end
    function region:EnableMouse() end
    function region:SetDrawBling() end
    function region:SetDrawEdge() end
    function region:SetHideCountdownNumbers() end
    function region:SetSwipeColor() end
    function region:SetCooldownFromDurationObject(value) self.duration = value end
    function region:SetScript(name, value) self.scripts[name] = value end
    function region:HookScript(name, value) self.scripts["hook_" .. name] = value end
    function region:SetShown(value) self.shown = value end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:IsShown() return self.shown end
    function region:IsVisible() return self.shown end
    return region
end

UIParent = Region()
function UIParent:GetEffectiveScale() return 2 end
Minimap = Region()
ExpansionLandingPageMinimapButton = Region()
ExpansionLandingPageMinimapButton.scripts.OnClick = function() landingOpens = landingOpens + 1 end
function ExpansionLandingPageMinimapButton:ToggleLandingPage()
    landingOpens = landingOpens + 1
end
GameTooltip = { SetOwner = function() end, SetText = function() end,
    AddLine = function() end, Show = function() end, Hide = function() end }
GetCursorPosition = function() return pointX, pointY end
UnitCastingDuration = function() return castDuration end
UnitChannelDuration = function() return nil end
C_Spell = { GetSpellCooldownDuration = function(id)
    assert(id == 61304)
    return gcdDuration
end }
C_Timer = { After = function(_, fn) timerQueue[#timerQueue + 1] = fn end }
C_SpecializationInfo = {
    GetSpecialization = function() return currentSpec end,
    GetSpecializationInfo = function(index) return 70 + index, "Spec " .. index, nil, 100 + index end,
    SetSpecialization = function(index) currentSpec = index; return true end,
}
GetNumSpecializations = function() return 3 end
GetLootSpecialization = function() return lootSpec end
SetLootSpecialization = function(id) lootSpec = id end
WeeklyRewards_ShowUI = function() vaultOpens = vaultOpens + 1 end
CanShowEncounterJournal = function() return true end
ToggleEncounterJournal = function() journalOpens = journalOpens + 1 end
ToggleWorldMap = function() mapOpens = mapOpens + 1 end
GetSpecializationInfoByID = function(id) return id, "Loot " .. id end
CR_VERSATILITY_DAMAGE_DONE = 29
GetCritChance = function() return 11.1 end
GetRangedCritChance = function() return 9.5 end
GetSpellCritChance = function() return 10.5 end
GetHaste = function() return hasteValue end
GetMasteryEffect = function() return 33.3 end
GetCombatRatingBonus = function() return 40 end
GetVersatilityBonus = function() return 4.4 end
UnitClassBase = function() return "HUNTER" end
UnitExists = function(unit) assert(unit == "pet"); return petExists end
UnitIsDeadOrGhost = function(unit) assert(unit == "pet"); return petDead end

local suite = {
    Install = function(id, value) installed[id] = value end,
    CreateFrame = function() return Region() end,
    CreateTexture = function() return Region() end,
    CreateFontString = function() return Region() end,
    SetFont = function() end,
    Text = function(value) return value end,
    RGB = function() return 1, 1, 1 end,
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value) return type(value) == "string" and value ~= "secret" and value or nil end,
    Finite = function(value) return type(value) == "number" and value == value end,
    RegisterOwnedMover = function(id) installed[id].moverRegistered = true end,
}
local ns = { IsCombatLocked = function() return combat end,
    AnchorPoints = { [5] = "CENTER" }, Safety = { IsForbidden = function() return false end } }
local function Context()
    local context = { events = {} }
    function context:Event(event, callback) self.events[event] = callback end
    function context:RemoveEvent(event) self.events[event] = nil end
    return context
end

assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().QoLStyleFixture(root, suite)
for _, filename in ipairs({ "CursorEffects.lua", "MapQuickSwitch.lua",
    "CombatStatsHUD.lua", "CombatPetStatus.lua", "MapLandingShortcuts.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. filename))(
        "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
end

local cursor = assert(installed.cursorEffects)
cursor.active, cursor.context = true, Context()
cursor.config = { color = "ffffff", size = 36, opacity = 85,
    showTrail = true, showGCD = true, showCast = true, combatOnly = false }
cursor:Enable()
assert(cursor.host.scripts.OnUpdate and cursor.context.events.UNIT_SPELLCAST_SUCCEEDED,
    "enabled cursor did not listen only while active")
cursor.host.scripts.OnUpdate(cursor.host, .05)
assert(cursor.host.point[4] == 50 and cursor.host.point[5] == 60,
    "cursor position did not account for UI scale")
castDuration = { token = "cast" }
cursor.context.events.UNIT_SPELLCAST_START(cursor)
assert(cursor.cast.shown and cursor.cast.duration == castDuration and not cursor.gcd.shown,
    "cast duration did not take visual priority")
castDuration = nil
cursor.context.events.UNIT_SPELLCAST_STOP(cursor)
assert(not cursor.cast.shown and cursor.gcd.duration == gcdDuration,
    "GCD did not resume after cast")
cursor.config.combatOnly = true
cursor:Refresh()
assert(not cursor.host.shown and not cursor.host.scripts.OnUpdate,
    "combat-only cursor kept sampling outside combat")
combat = true
cursor.context.events.PLAYER_REGEN_DISABLED(cursor)
assert(cursor.host.shown and cursor.host.scripts.OnUpdate,
    "combat-only cursor did not resume on combat entry")
cursor:Disable()
assert(not cursor.host.shown and not cursor.host.scripts.OnUpdate,
    "disabled cursor left its per-frame position callback running")

local menuRoot
MenuUtil = { CreateContextMenu = function(_, builder)
    local function Node()
        local node = { children = {} }
        function node:CreateTitle() end
        function node:SetEnabled(enabled) self.enabled = enabled end
        function node:CreateButton(name, callback)
            local child = Node()
            child.name, child.callback = name, callback
            self.children[#self.children + 1] = child
            return child
        end
        function node:CreateRadio(name, selected, change, value)
            local child = { name = name, selected = selected, change = change, value = value }
            function child:SetEnabled(enabled) self.enabled = enabled end
            self.children[#self.children + 1] = child
            return child
        end
        return node
    end
    menuRoot = Node()
    builder(nil, menuRoot)
end }
local quick = assert(installed.mapQuickSwitch)
quick.active, quick.context = true, Context()
quick.config = { showSpec = true, showLoot = true, corner = 1, size = 24, x = 0, y = 0 }
combat = false
quick:Enable()
assert(quick.button.shown and quick.icon.texture == 101,
    "quick switch did not show current specialization")
quick.button.scripts.OnClick(quick.button)
local specChoice = menuRoot.children[1].children[2]
specChoice.change(specChoice.value)
assert(currentSpec == 2, "spec menu did not use Blizzard's specialization setter")
local lootChoice = menuRoot.children[2].children[3]
lootChoice.change(lootChoice.value)
assert(lootSpec == 72, "loot menu did not use Blizzard's loot setter")
combat = true
quick.button.scripts.OnClick(quick.button)
assert(menuRoot.children[1].children[1].enabled == false,
    "spec changes remained enabled during combat")
specChoice.change(3)
assert(currentSpec == 2, "combat guard did not protect spec setter")
quick:Disable()
assert(not quick.button.shown, "quick switch remained visible when disabled")

local landing = assert(installed.mapLandingShortcuts)
landing.active, landing.context = true, Context()
combat = false
landing.config = { showLandingPage = true, showVault = true,
    showJournal = true, showMap = true, size = 18, offsetX = 4, offsetY = 0 }
local native = ExpansionLandingPageMinimapButton
local nativeClick = native.scripts.OnClick
ExpansionLandingPageMinimapButton = nil
landing:Enable()
assert(not landing.button and landing.context.events.ADDON_LOADED,
    "landing shortcut must wait for Blizzard's lazy-loaded native button")
ExpansionLandingPageMinimapButton = native
landing.context.events.ADDON_LOADED(landing, "ADDON_LOADED", "Blizzard_MidnightLandingPage")
landing:Enable()
assert(landing.button.shown and ExpansionLandingPageMinimapButton.scripts.OnClick == nativeClick,
    "landing shortcuts replaced Blizzard's native click")
landing.button.scripts.OnClick(landing.button)
assert(#menuRoot.children == 4, "landing context did not expose four native destinations")
menuRoot.children[1].callback()
menuRoot.children[2].callback()
menuRoot.children[3].callback()
menuRoot.children[4].callback()
assert(landingOpens == 1 and vaultOpens == 1 and journalOpens == 1 and mapOpens == 1,
    "landing menu did not call native page openers")
combat = true
landing.button.scripts.OnClick(landing.button)
assert(menuRoot.children[1].enabled == false and menuRoot.children[4].enabled == false,
    "landing shortcuts stayed enabled during combat")
menuRoot.children[2].callback()
assert(vaultOpens == 1, "combat guard did not protect landing shortcut")
combat = false
ExpansionLandingPageMinimapButton:Hide()
ExpansionLandingPageMinimapButton.scripts.hook_OnHide()
assert(not landing.button.shown, "landing shortcut remained after native button hid")
landing:Disable()
ExpansionLandingPageMinimapButton:Show()
combat = true
landing:Enable()
assert(not landing.button.shown and landing.context.events.PLAYER_REGEN_ENABLED,
    "landing shortcuts changed native-adjacent layout during combat")
combat = false
landing.context.events.PLAYER_REGEN_ENABLED(landing)
assert(landing.button.shown, "deferred landing shortcut did not resume after combat")
landing:Disable()

local hud = assert(installed.combatStatsHUD)
hud.active, hud.context = true, Context()
hud.config = { point = 5, x = 0, y = 0, width = 300, scale = 100,
    backgroundColor = "000000", accentColor = "ffffff", opacity = 90,
    showCrit = true, showHaste = true, showMastery = true, showVersatility = true,
    combatOnly = false }
hud:Enable()
assert(hud.moverRegistered and hud.fields[1].value.text == "11.1%"
    and hud.fields[4].value.text == "44.4%", "stats HUD did not show native secondary stats")
hasteValue = "secret"
hud.context.events.UNIT_AURA(hud)
hud.context.events.COMBAT_RATING_UPDATE(hud)
assert(#timerQueue == 1, "stat events did not coalesce into one update")
timerQueue[1]()
assert(hud.fields[2].value.text == "--", "restricted stat was formatted in Lua")
hud.config.showCrit, hud.config.showMastery, hud.config.showVersatility = false, false, false
GetCritChance = function() error("disabled crit getter was called") end
hasteValue = 22.2
hud:Refresh()
assert(hud.fields[2].value.text == "22.2%" and hud.fields[1].value.text == "--",
    "disabled stat getters were queried or their labels stayed stale")
hud.config.combatOnly = true
combat = false
hud:Refresh()
assert(not hud.host.shown and not hud.context.events.UNIT_AURA,
    "combat-only stats HUD kept aura listeners while hidden")
combat = true
hud.context.events.PLAYER_REGEN_DISABLED(hud)
assert(hud.host.shown and hud.context.events.UNIT_AURA,
    "combat-only stats HUD did not restore listeners in combat")
combat = false
hud:Disable()
assert(not hud.host.shown, "stats HUD remained visible when disabled")

local pet = assert(installed.combatPetStatus)
pet.active, pet.context = true, Context()
pet.config = { point = 5, x = 0, y = 0, scale = 100,
    combatOnly = false, showMissing = true, showDead = true, anyClass = false }
pet:Enable()
assert(pet.host.shown and pet.label.text == "Pet missing",
    "missing pet status was not shown for a pet class")
petExists, petDead = true, false
pet.context.events.UNIT_PET(pet)
assert(not pet.host.shown, "healthy pet left warning visible")
petDead = true
pet.context.events.UNIT_HEALTH(pet)
assert(pet.host.shown and pet.label.text == "Pet dead",
    "pet death status did not follow a unit event")
pet:Disable()
assert(not pet.host.shown, "pet status remained visible when disabled")

print("Suite cursor, map shortcuts, stats HUD and pet status lifecycle passed")
