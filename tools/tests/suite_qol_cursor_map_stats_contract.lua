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
    function region:SetTextColor(r, g, b) self.textColor = { r, g, b } end
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
    function region:SetCooldown(start, duration) self.sampleDuration=duration end
    function region:Pause() self.paused=true end
    function region:Resume() self.paused=false end
    function region:Clear() self.sampleDuration=nil;self.duration=nil end
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
C_Spell = { GetSpellCooldown = function() return { isActive = gcdDuration ~= nil } end, GetSpellCooldownDuration = function(id)
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
local playerClass, knownSpells = "HUNTER", { [883] = true }
UnitClassBase = function() return playerClass end
C_SpellBook = { IsSpellKnown = function(spellID) return knownSpells[spellID] == true end }
UnitExists = function(unit) assert(unit == "pet"); return petExists end
UnitIsDeadOrGhost = function(unit) assert(unit == "pet"); return petDead end

local suite = {
    Install = function(id, value) installed[id] = value end,
    CreateFrame = function() return Region() end,
    CreateTexture = function() return Region() end,
    CreateFontString = function() return Region() end,
    SetFont = function() end,
    Text = function(value) return value end,
    -- Distinct colors per hex value, so a test can tell palettes apart.
    RGB = function(hex) return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255 end,
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value) return type(value) == "string" and value ~= "secret" and value or nil end,
    Finite = function(value) return type(value) == "number" and value == value end,
    RegisterOwnedMover = function(id) installed[id].moverRegistered = true end,
}
-- securecallfunction reports an error and returns nothing; this stand-in
-- lets errors raise so a failing Blizzard opener fails the test.
suite.Dispatch = function(callback, ...) return callback(...) end
local ns = { Finish = function(callback, ...) return true, callback(...) end,
    IsCombatLocked = function() return combat end,
    AnchorPoints = { [5] = "CENTER" }, Safety = { IsForbidden = function() return false end } }
ns.InCombat = assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().InCombat(root,
    function() return combat end)
local function Context()
    local context = { events = {} }
    function context:Event(event, callback) self.events[event] = callback end
    function context:RemoveEvent(event) self.events[event] = nil end
    return context
end

-- Palette 5 is the shared Class Style palette.
assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().QoLStyleFixture(root, suite, {
    [1] = { background = "0a1220", border = "41627a", accent = "57c7df", text = "f4f7fb", muted = "aab5c2" },
    [5] = { background = "101010", border = "c41e3a", accent = "c41e3a", text = "f5f5f5", muted = "806060" },
})
for _, filename in ipairs({ "CursorEffects.lua",
    "CombatStatsHUD.lua", "CombatPetStatus.lua", "MapLandingShortcuts.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. filename))(
        "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
end

local cursor = assert(installed.cursorEffects)
cursor.active, cursor.context = true, Context()
cursor.config = { color = "ffffff", ringShape = 1, size = 36, opacity = 85,
    showTrail = true, showGCD = true, showCast = true, combatOnly = false, zone = 1,
    showDot = false, dotSize = 4, cameraHoldOnly = false, castSpark = false, gcdDetached = false, gcdSize = 40,
    gcdOpacity = 80, gcdPoint = 5, gcdX = 0, gcdY = -140, ringWhen = 1, gcdWhen = 1, castWhen = 1 }
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
-- A cast-time spell starts the global cooldown long before its SUCCEEDED;
-- without the cast display its start must still draw the GCD.
cursor.config.showCast = false
cursor:Refresh()
local startGCD = cursor.context.events.UNIT_SPELLCAST_START
cursor.gcd.duration, gcdDuration = nil, { token = "cast-time gcd" }
assert(startGCD and cursor.context.events.UNIT_SPELLCAST_CHANNEL_START, "cast starts no longer read the GCD")
startGCD(cursor)
assert(cursor.gcd.shown and cursor.gcd.duration == gcdDuration, "a cast-time spell's GCD was missed")
cursor.config.showCast = true
cursor:Refresh()
assert(cursor.context.events.UNIT_SPELLCAST_START ~= startGCD and cursor.context.events.UNIT_SPELLCAST_STOP,
    "the cast display lost its own cast events")
cursor.config.combatOnly = true
cursor:Refresh()
assert(not cursor.host.shown and not cursor.host.scripts.OnUpdate,
    "combat-only cursor kept sampling outside combat")
-- PLAYER_REGEN_DISABLED arrives before InCombatLockdown() turns true.
cursor.context.events.PLAYER_REGEN_DISABLED(cursor, "PLAYER_REGEN_DISABLED")
combat = true
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
    backgroundColor = "000000", accentColor = "ffffff", opacity = 90, look = 5,
    showCrit = true, showHaste = true, showMastery = true, showVersatility = true,
    showLeech = false, showAvoidance = false, showSpeed = false, leechColor = "9cd7c9",
    avoidanceColor = "c9b3f2", speedColor = "8cc4e8", valueFormat = 1, labelStyle = 1,
    fps = 1, fpsX = 0, fpsY = -55, combatOnly = false }
hud:Enable()
assert(hud.moverRegistered and hud.fields[1].value.text == "11.1%"
    and hud.fields[4].value.text == "44.4%", "stats HUD did not show native secondary stats")
hasteValue = "secret"
hud.context.events.UNIT_AURA(hud)
hud.context.events.COMBAT_RATING_UPDATE(hud)
assert(#timerQueue == 1, "stat events did not coalesce into one update")
timerQueue[1]()
assert(hud.fields[2].value.text == "--", "restricted stat was formatted in Lua")
-- Class Style (look 6) paints with the shared class palette (index 5), not
-- the first palette; Custom (look 5) keeps the strip's own colors.
hud.config.look = 6
hud:Refresh()
local labelColor, valueColor = hud.fields[1].label.textColor, hud.fields[1].value.textColor
assert(math.abs(labelColor[1] - 0x80 / 255) < 1e-6 and math.abs(valueColor[1] - 0xc4 / 255) < 1e-6,
    "Class Style painted the stat names and values with another palette")
hud.config.look = 5
hud:Refresh()
hud.config.showCrit, hud.config.showMastery, hud.config.showVersatility = false, false, false
GetCritChance = function() error("disabled crit getter was called") end
hasteValue = 22.2
hud:Refresh()
assert(hud.fields[2].value.text == "22.2%" and hud.fields[1].value.text == "--",
    "disabled stat getters were queried or their labels stayed stale")
-- Rating follows the same native crit type that supplied the percentage;
-- disabled columns do not query rating readers. Extra stats are opt-in, one
-- switch and one color each; a switched-off one is not read.
CR_HASTE_MELEE, CR_MASTERY, CR_SPEED, CR_LIFESTEAL, CR_AVOIDANCE = 18, 26, 14, 17, 28
local ratingReads = {}
GetCombatRating = function(id) ratingReads[#ratingReads + 1] = id; return id * 100 end
GetSpeed = function() error("a switched-off speed stat was read") end
GetLifesteal, GetAvoidance = function() return 4.5 end, function() return "secret" end
hud.config.valueFormat, hud.config.showLeech = 3, true
hud:Refresh()
assert(hud.fields[5].value.shown and not hud.fields[6].value.shown and not hud.fields[7].value.shown
    and hud.fields[5].value.text == "4.5%\n1700", "one extra stat did not show on its own")
GetSpeed = function() return 3.2 end
ratingReads = {}
hud.config.showAvoidance, hud.config.showSpeed = true, true
hud:Refresh()
assert(hud.host.height == 58 and hud.fields[2].value.text == "22.2%\n1800"
    and hud.fields[5].value.text == "4.5%\n1700"
    and hud.fields[6].value.text == "--\n2800"
    and hud.fields[7].value.text == "3.2%\n1400" and #ratingReads == 4,
    "combined stat values or restricted tertiary handling failed")
assert(math.abs(hud.fields[5].value.textColor[1] - 0x9c / 255) < 1e-6
    and math.abs(hud.fields[6].value.textColor[1] - 0xc9 / 255) < 1e-6
    and math.abs(hud.fields[7].value.textColor[1] - 0x8c / 255) < 1e-6, "an extra stat ignored its own color")
hud.config.valueFormat = 2
hud:Refresh()
assert(hud.fields[2].value.text == "1800" and hud.host.height == 42, "rating-only layout failed")
hud.config.valueFormat, hud.config.labelStyle = 1, 2
hud:Refresh()
assert(hud.fields[6].label.text == "Avoidance", "long stat names unavailable")
hud.config.combatOnly = true
combat = false
hud:Refresh()
assert(not hud.host.shown and not hud.context.events.UNIT_AURA,
    "combat-only stats HUD kept aura listeners while hidden")
-- PLAYER_REGEN_DISABLED arrives before InCombatLockdown() turns true.
hud.context.events.PLAYER_REGEN_DISABLED(hud, "PLAYER_REGEN_DISABLED")
combat = true
assert(hud.host.shown and hud.context.events.UNIT_AURA,
    "combat-only stats HUD did not restore listeners in combat")
combat = false
hud.context.events.PLAYER_REGEN_ENABLED(hud, "PLAYER_REGEN_ENABLED")
assert(not hud.host.shown and not hud.context.events.UNIT_AURA, "combat-only stats HUD stayed after combat")
local fpsTicks, fps = {}, 144
GetFramerate = function() return fps end
suite.GlobalFontPath, suite.SetStyledFont = function() return "font" end, function() end
suite.Set = function() error("the FPS key binding wrote a profile setting") end
C_Timer.NewTicker = function(interval, callback)
    assert(interval == 1)
    local ticker = { callback = callback, Cancel = function(self) self.cancelled = true end }
    fpsTicks[#fpsTicks + 1] = ticker
    return ticker
end
hud.config.fps = 3
hud:Refresh()
assert(not hud.host.shown and hud.fpsHost.shown and hud.fpsText.text == "144 FPS" and #fpsTicks == 1,
    "a separate FPS readout should remain visible while combat-only stats are hidden")
fps = "secret"
fpsTicks[1].callback()
assert(hud.fpsText.text == "-- FPS")
hud:Refresh()
assert(#fpsTicks == 1, "refresh duplicated FPS ticker")
-- The key binding is a session toggle that also works in combat.
combat = true
suite.ToggleCombatStatsFPS()
assert(not hud.fpsHost.shown and fpsTicks[1].cancelled, "FPS hotkey did not hide and stop sampling in combat")
suite.ToggleCombatStatsFPS()
assert(hud.fpsHost.shown and #fpsTicks == 2, "FPS hotkey did not show the readout again in combat")
combat = false
hud.config.fps = 1
hud:Refresh()
assert(not hud.fpsHost.shown, "a new FPS choice did not replace the session override")
hud:Disable()
hud.active = false
local printed
suite.Print = function(text) printed = text end
suite.ToggleCombatStatsFPS()
assert(printed and not hud.fpsHost.shown, "FPS hotkey of a switched-off module gave no feedback")
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
-- Combat-only: no pet event fires without a pet, so the warning must come
-- from PLAYER_REGEN_DISABLED, which arrives before the lockdown starts.
petExists, petDead, combat = false, false, false
pet.config.combatOnly = true
pet:Refresh()
assert(not pet.host.shown, "combat-only pet warning showed outside combat")
pet.context.events.PLAYER_REGEN_DISABLED(pet, "PLAYER_REGEN_DISABLED")
assert(pet.host.shown and pet.label.text == "Pet missing",
    "combat-only missing-pet warning did not appear on combat entry")
combat = true
pet.context.events.UNIT_PET(pet, "UNIT_PET", "player")
assert(pet.host.shown, "combat-only warning dropped while in combat")
combat = false
pet.context.events.PLAYER_REGEN_ENABLED(pet, "PLAYER_REGEN_ENABLED")
assert(not pet.host.shown, "combat-only pet warning stayed after combat")
-- The spellbook decides whether a pet belongs to this character: a
-- Marksmanship hunter without Call Pet, or a warlock with Grimoire of
-- Sacrifice, plays without one.
pet.config.combatOnly = false
pet:Refresh()
assert(pet.host.shown and pet.context.events.SPELLS_CHANGED, "a hunter with Call Pet lost the missing-pet warning")
knownSpells[883] = nil
pet.context.events.SPELLS_CHANGED(pet, "SPELLS_CHANGED")
assert(not pet.host.shown, "a petless hunter specialization was told its pet is missing")
pet:Disable()
playerClass, knownSpells = "WARLOCK", { [688] = true, [108503] = true }
pet:Enable()
assert(not pet.host.shown, "a warlock with Grimoire of Sacrifice was told its demon is missing")
knownSpells[108503] = nil
pet.context.events.SPELLS_CHANGED(pet, "SPELLS_CHANGED")
assert(pet.host.shown and pet.label.text == "Pet missing", "a warlock without its demon lost the warning")
pet:Disable()
assert(not pet.host.shown, "pet status remained visible when disabled")

print("Suite cursor, map shortcuts, stats HUD and pet status lifecycle passed")
