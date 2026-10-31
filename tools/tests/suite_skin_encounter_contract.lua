-- Native EncounterJournal template fields, lifecycle and repeat-work budgets.
local root = assert(arg[1])
local checks, locked, scans, attaches, controls, textWrites = 0, false, 0, 0, 0, 0
local function Check(ok, message) assert(ok, message); checks = checks + 1 end
local function Noop() end
securecallfunction = function(fn, ...) return fn(...) end
local hooks, jobs, surfaces = {}, {}, {}
function hooksecurefunc(name, callback) hooks[name] = callback end
NavBar_CheckLength = Noop
EncounterJournal_SetTab = Noop
ScrollBoxListMixin = { Event = { OnInitializedFrame = "row" } }
EventRegistry = { RegisterCallback = Noop, UnregisterCallback = Noop }
local color = { .85, .86, .87, 1 }
local NS = {
    IsCombatLocked = function() return locked end,
    Theme = { GetColor = function() return unpack(color) end },
    Registry = { AddListener = Noop, RemoveListener = Noop,
        QueueJob = function(fn) fn() end, GetSurface = function(target) return surfaces[target] end },
    CombatGate = {
        RunOrDefer = function(key, fn) jobs[key] = fn end,
        Cancel = function(key) jobs[key] = nil end,
    },
    GenericWindows = { ApplyFrame = function() return true end, Disable = Noop },
}
local methods = {}
function methods:GetObjectType() return self.kind or "Frame" end
function methods:IsForbidden() return self.forbidden == true end
function methods:IsProtected() return self.protected == true, self.protected == true end
function methods:CreateTexture() error("renderer fixture required") end
function methods:GetName() return self.name end
function methods:GetID() return self.id end
function methods:GetNormalTexture() return self.normal end
function methods:GetRegions() scans = scans + 1; return unpack(self.regions or {}) end
function methods:GetAlpha() return self.alpha or 1 end
function methods:SetAlpha(alpha) assert(not locked, "combat alpha write"); self.alpha = alpha end
function methods:GetTextColor() return self.r or 1, self.g or 1, self.b or 1, 1 end
function methods:SetTextColor(r, g, b)
    assert(not locked, "combat text write")
    self.r, self.g, self.b = r, g, b
    textWrites = textWrites + 1
end
function methods:IsShown() return self.shown ~= false end
function methods:IsVisible() return self.shown ~= false end
function methods:HookScript(script, callback) self.hooks[script] = callback end
function methods:RegisterCallback(event, callback, owner) self.callback, self.owner = callback, owner end
function methods:UnregisterCallback() self.callback, self.owner = nil, nil end
function methods:ForEachFrame(callback) for _, row in ipairs(self.rows or {}) do callback(row) end end
function methods:Initialize(row) self.callback(self.owner, row) end
local meta = { __index = methods }
local function Frame(name) return setmetatable({ name = name, hooks = {} }, meta) end
local function Texture(name) local t = Frame(name); t.kind = "Texture"; return t end
local function Text(r, g, b) local t = Frame(); t.kind, t.r, t.g, t.b = "FontString", r, g, b; return t end
NS.Surface = {
    Attach = function(target, spec)
        assert(not locked, "combat surface write")
        attaches = attaches + 1
        local surface = surfaces[target] or {}
        surface.spec, surface.visible = spec, true
        surfaces[target] = surface
        return surface
    end,
    SetActive = function(target, active) if surfaces[target] then surfaces[target].active = active end end,
    SetVisible = function(target, visible) if surfaces[target] then surfaces[target].visible = visible end end,
}
function NS.Surface.Ensure(target, spec)
    local surface = surfaces[target]
    if surface and surface.spec == spec and surface.visible then return surface end
    return NS.Surface.Attach(target, spec)
end
NS.ControlSkin = {
    ApplyButton = function(target, owner, spec)
        controls = controls + 1
        target.controlOwner = owner
        return NS.Surface.Attach(target, spec)
    end,
    ApplyTab = function(target, owner, spec) return NS.ControlSkin.ApplyButton(target, owner, spec) end,
    Refresh = Noop, DisableOwner = Noop,
    RefreshOwner = function(owner)
        for target, surface in pairs(surfaces) do
            if target.controlOwner == owner then surface.active = surface.spec.active == true end
        end
    end,
}
local function Load(path, override)
    assert(loadfile(override or root .. "/MSUF_Suite_Skin/" .. path))("MSUF_Suite_Skin", NS)
end
Load("Core/Safety.lua")
Load("Core/Cosmetics.lua")
Load("Adapters/AdapterKit.lua")
Load("Adapters/EncounterJournalPanels.lua", os.getenv("SUITE_EJ_PANELS_SOURCE"))
Load("Adapters/EncounterJournal.lua", os.getenv("SUITE_EJ_SOURCE"))
local journal, encounter, info, instance = Frame("EncounterJournal"), Frame(), Frame("EncounterJournalEncounterFrameInfo"), Frame()
journal.encounter, encounter.info, encounter.instance = encounter, info, instance
journal.PortraitContainer = Texture()
local parchment, semantic = Texture("EncounterJournalEncounterFrameInfoBG"), Texture("EncounterJournalEncounterFrameInfoDifficultyIcon")
info.regions, info.leftShadow, info.rightShadow = { parchment, semantic }, Texture(), Texture()
info.instanceTitle, info.encounterTitle, info.difficulty = Text(), Text(), Frame()
instance.loreBG, instance.titleBG, instance.title = Texture(), Texture(), Text()
local lore = Text(.13, .07, .01)
instance.LoreScrollingFont = { ScrollBox = { FontStringContainer = { FontString = lore } } }
info.detailsScroll = { child = { description = Text(0, 0, 0) } }
info.overviewScroll = { child = { description = Text(0, 0, 0) } }
local nav, home = Frame(), Frame()
home.text, home.normal, home.arrowUp = Text(), Texture(), Texture()
nav.navList, nav.home, nav.overlay, nav.overflow = { home }, home, Frame(), Frame()
nav.regions, nav.overlay.regions = { Texture() }, { Texture() }
journal.navBar = nav
local bosses, loot = Frame(), Frame()
info.BossesScrollBox, info.LootContainer = bosses, loot
loot.ScrollBox, loot.filter, loot.slotFilter = Frame(), Frame(), Frame()
loot.classClearFilter = Frame()
loot.classClearFilter.text, loot.classClearFilter.regions = Text(), { Texture() }
local boss = Frame()
boss.text, boss.creature, boss.DefeatedOverlay, boss.normal = Text(.827, .659, .463), Texture(), Texture(), Texture()
bosses.rows = { boss }
local item = Frame()
item.name, item.slot, item.armorType, item.boss = Text(.64, .21, .93), Text(.25, .1484375, .02), Text(.25, .1484375, .02), Text(.25, .1484375, .02)
item.icon, item.IconBorder, item.IconOverlay = Texture(), Texture(), Texture()
item.bossTexture, item.bosslessTexture = Texture(), Texture()
loot.ScrollBox.rows = { item }
local sideTabs = { "overviewTab", "lootTab", "bossTab", "modelTab" }
for id, key in ipairs(sideTabs) do
    local button = Frame()
    button.id, button.normal, button.selected, button.unselected = id, Texture(), Texture(), Texture()
    info[key] = button
end
info.tab = 2
Check(NS.EncounterJournalSkin.Apply(journal, "journal"), "journal did not apply")
Check(parchment.alpha == 0 and info.leftShadow.alpha == 0 and info.rightShadow.alpha == 0,
    "unkeyed journal parchment or header shadows remain visible")
Check(semantic.alpha == nil and boss.creature.alpha == nil and boss.DefeatedOverlay.alpha == nil,
    "semantic difficulty/portrait/defeated art was suppressed")
Check(lore.r == color[1] and info.detailsScroll.child.description.r == color[1], "dark lore/detail text stayed unreadable")
Check(boss.normal.alpha == 0 and boss.text.r == color[1] and surfaces[boss].spec.role == "card", "boss button kept native art/text")
Check(surfaces[boss].spec.listItem ~= true, "idle boss cards have no fill")
Check(item.bossTexture.alpha == 0 and item.bosslessTexture.alpha == 0, "loot parchment remains visible")
Check(item.slot.r == color[1] and item.armorType.r == color[1] and item.boss.r == color[1], "loot metadata stayed brown")
Check(item.name.r == .64 and item.icon.alpha == nil and item.IconBorder.alpha == nil and item.IconOverlay.alpha == nil,
    "loot rarity or semantic icon art changed")
Check(home.normal.alpha == 0 and home.arrowUp.alpha == 0 and surfaces[home].active, "native navigation remains visible")
Check(surfaces[info.difficulty] and surfaces[loot.filter] and surfaces[loot.slotFilter], "loot filters were not skinned")
for _, key in ipairs(sideTabs) do
    local button = info[key]
    Check(button.normal.alpha == 0 and button.selected.alpha == nil and button.unselected.alpha == nil,
        "side tab art/semantic icons incorrect: " .. key)
end
Check(surfaces[info.lootTab].active and not surfaces[info.overviewTab].active, "side tab initial selection missed")
local sideScans, sideAttaches, sideControls = scans, attaches, controls
local function RepeatSideTabs()
    for _ = 1, 1000 do hooks.EncounterJournal_SetTab() end
end
local function SideAllocation()
    collectgarbage("collect"); collectgarbage("stop")
    local before = collectgarbage("count")
    RepeatSideTabs()
    local growth = collectgarbage("count") - before
    collectgarbage("restart")
    return growth
end
local sideGrowth = math.min(SideAllocation(), SideAllocation())
Check(sideGrowth < 2, ("side tab updates allocated %.2f KB"):format(sideGrowth))
print(("Encounter side-tab budget: %.2f KB / 1000 unchanged updates; 0 scans, attaches, control rebuilds"):format(sideGrowth))
Check(scans == sideScans and attaches == sideAttaches and controls == sideControls, "unchanged side tab rescanned/rebuilt window")
info.tab = 3
hooks.EncounterJournal_SetTab()
Check(surfaces[info.bossTab].active and not surfaces[info.lootTab].active, "side tab transition missed")
Check(scans == sideScans and attaches == sideAttaches + 2 and controls == sideControls + 2,
    "side tab transition repainted unrelated surfaces")
locked = true
info.tab = 4
for _ = 1, 20 do hooks.EncounterJournal_SetTab() end
Check(not surfaces[info.modelTab].active and jobs["encounterJournal:side-tabs"], "combat side tab writes were not deferred")
locked = false
local pending = jobs["encounterJournal:side-tabs"]
jobs["encounterJournal:side-tabs"] = nil
pending()
Check(surfaces[info.modelTab].active and not surfaces[info.bossTab].active, "combat side tab did not replay")
-- Both navigation and tabs can change while the same journal is hidden.
journal.shown = false
info.tab = 1
hooks.NavBar_CheckLength(nav)
hooks.EncounterJournal_SetTab()
Check(surfaces[info.modelTab].active, "hidden side tabs were repainted")
journal.shown = true
journal.hooks.OnShow(journal)
Check(surfaces[info.overviewTab].active and not surfaces[info.modelTab].active, "hidden side tabs did not replay")

-- Same physical rows, different data: no tree/region scans, surface reattach,
-- control replacement, timer, or allocation after the initial claim.
bosses:Initialize(boss)
loot.ScrollBox:Initialize(item)
local oldScans, oldAttaches, oldControls = scans, attaches, controls
local function RepeatRows()
    for _ = 1, 500 do bosses:Initialize(boss); loot.ScrollBox:Initialize(item) end
end
local function Allocation()
    collectgarbage("collect"); collectgarbage("stop")
    local before = collectgarbage("count")
    RepeatRows()
    local growth = collectgarbage("count") - before
    collectgarbage("restart")
    return growth
end
local growth = math.min(Allocation(), Allocation())
Check(scans == oldScans and attaches == oldAttaches and controls == oldControls, "recycled rows repeated chrome/control/surface work")
Check(growth < 2, ("row recycling allocated %.2f KB"):format(growth))
local vm = 0
debug.sethook(function() vm = vm + 100 end, "", 100)
RepeatRows()
debug.sethook()
Check(vm < 6500000, "row instruction budget exceeded")
print(("Encounter row budget: %.2f KB / 1000 reuses; %d VM / reuse; 0 scans, attaches, control rebuilds"):format(growth, vm / 1000))

local nextButton = Frame()
nextButton.text, nextButton.normal, nextButton.arrowDown = Text(), Texture(), Texture()
nav.navList[2] = nextButton
hooks.NavBar_CheckLength(nav)
Check(surfaces[nextButton] and surfaces[nextButton].active and not surfaces[home].active, "new breadcrumb missed its skin/selection")
local beforeWrites = textWrites
hooks.NavBar_CheckLength(Frame())
Check(textWrites == beforeWrites, "unrelated navigation triggered journal work")
journal.shown = false
hooks.NavBar_CheckLength(nav)
Check(textWrites == beforeWrites, "hidden navigation was repainted")
locked, journal.shown = true, true
journal.hooks.OnShow(journal)
for _ = 1, 20 do hooks.NavBar_CheckLength(nav) end
Check(textWrites == beforeWrites and jobs["encounterJournal:navigation"], "combat navigation was not deferred")
local fresh = Frame()
fresh.text, fresh.creature, fresh.normal = Text(), Texture(), Texture()
bosses.rows[1] = fresh
bosses:Initialize(fresh)
Check(not surfaces[fresh] and jobs["encounterJournal:rows"], "combat row was painted or lost")
locked = false
for key, callback in pairs(jobs) do jobs[key] = nil; callback() end
Check(surfaces[fresh] and fresh.text.r == color[1], "combat row did not replay")
color[1] = .72
NS.EncounterJournalSkin:OnThemeChanged()
Check(lore.r == .72 and fresh.text.r == .72 and item.slot.r == .72, "theme changes missed encounter text")
Check(item.name.r == .64, "theme change overwrote item rarity")
Check(surfaces[nextButton].active and not surfaces[home].active, "theme refresh lost breadcrumb selection")
Check(surfaces[info.overviewTab].active, "theme refresh lost side tab selection")
NS.EncounterJournalSkin.Disable(journal, "journal")
Check(parchment.alpha == 1 and lore.r == .13 and item.bossTexture.alpha == 1, "disable did not restore native art/text")
Check(info.lootTab.normal.alpha == 1, "disable did not restore side tab art")
beforeWrites = textWrites
hooks.NavBar_CheckLength(nav)
Check(textWrites == beforeWrites and not next(jobs), "disabled adapter still did work")
Check(NS.EncounterJournalSkin.Apply(journal, "journal") and parchment.alpha == 0, "re-enable retained stale chrome cache")
Check(fresh.normal.alpha == 0, "re-enable retained stale control cache")
NS.EncounterJournalSkin.Disable(journal, "journal")
print(("EncounterJournal: %d checks passed"):format(checks))
