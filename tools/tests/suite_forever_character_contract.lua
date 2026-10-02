local rootPath = assert(arg[1], "Suite root required")

-- Blizzard's callback isolation: an error is reported and the caller goes on.
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2, table.maxn(results))
end

local function Texture(atlas)
    return { atlas = atlas, vertex = { 1, 1, 1, 1 },
        GetAtlas = function(self) return self.atlas end,
        GetVertexColor = function(self) return unpack(self.vertex) end,
        SetVertexColor = function(self, ...) self.vertex = { ... } end,
        SetAlpha = function(self, alpha) self.alpha = alpha end,
        ClearAllPoints = function(self) self.points = {} end,
        SetPoint = function(self, ...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end,
        SetHeight = function() end,
        SetColorTexture = function() end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetShown = function(self, shown) self.shown = shown end }
end
local function Frame(regions)
    return { points = {}, width = 646, height = 540,
        frameStrata = "MEDIUM", frameLevel = 0,
        GetFrameStrata = function(self) return self.frameStrata end,
        SetFrameStrata = function(self, value) self.frameStrata = value end,
        GetFrameLevel = function(self) return self.frameLevel end,
        SetFrameLevel = function(self, value) self.frameLevel = value end,
        GetParent = function(self) return self.parent end,
        GetRegions = function() return unpack(regions or {}) end,
        GetNumPoints = function(self) return #self.points end,
        GetPoint = function(self, index) return unpack(self.points[index]) end,
        GetWidth = function(self) return self.width end,
        GetHeight = function(self) return self.height end,
        ClearAllPoints = function(self) self.points = {} end,
        SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
        SetSize = function(self, width, height) self.width, self.height = width, height end,
        CreateTexture = function() return Texture() end,
        CreateFontString = function()
            return { SetPoint = function() end, SetWidth = function() end,
                SetJustifyH = function() end,
                SetText = function(self, text) self.text = text end,
                SetTextColor = function() end,
                Show = function(self) self.shown = true end,
                Hide = function(self) self.shown = false end }
        end }
end

local leftArt = Texture("UI-Character-Info-General-BG")
local rightArt = Texture("UI-Character-Info-Stat-BG")
local left, right = Frame({ leftArt }), Frame({ rightArt })
right.StoneBg = Texture("UI-Character-Info-Stat-StoneBG")
local tabs = {}
for index = 1, 6 do
    tabs[index] = Frame()
    tabs[index].tooltipText = ({ "Character", "Reputation", "Skills",
        "PvP", "Currency", "Statistics" })[index]
    tabs[index].Icon = Texture()
    tabs[index].Background = Texture("common-sidetab")
    tabs[index].SelectedTexture = Texture("common-sidetab-selected")
    tabs[index].HighlightTexture = Texture("common-sidetab-hover")
end
local character = Frame()
character.LeftPaneHost, character.RightPaneHost = left, right
local reputation = Frame()
reputation.parent = character
reputation.ScrollBox = Frame()
reputation.ReputationDetailFrame = Frame()
ReputationFrame = reputation
character.ModeTabs = Frame()
character.ModeTabs.Tabs = tabs
character.ModeTabs:SetPoint("TOPLEFT", character, "TOPRIGHT", 0, -30)
function character:UpdateTabLayout()
    for index, tab in ipairs(tabs) do
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", self.ModeTabs, "TOPLEFT", 0, -(index - 1) * 55)
    end
end
character:UpdateTabLayout()
character.selectedTab = 2
function character:SetSelectedModeTabByFrame(index) self.selectedTab = index end
character.TitleText = Texture()
CharacterFrame = character
CharacterModelScene = Frame()
-- Blizzard_UIPanels_Game creates the stat pane with CharacterFrame.
CharacterStatsPane = Frame()
-- PaperDollFrame_SetItemLevel wrote Blizzard's own item-level text; the
-- skin shows its two-decimal text and gives Blizzard's back on disable.
local itemLevelValue = { text = "612",
    GetText = function(self) return self.text end,
    SetText = function(self, value) self.text = value end }
CharacterStatsPane.ItemLevelFrame = Frame()
CharacterStatsPane.ItemLevelFrame.Value = itemLevelValue
GetAverageItemLevel = function() return 615.5, 612.25 end
PaperDollFrame_SetItemLevel = function() error("contract: the skin ran PaperDoll item-level code") end
local modelBackgrounds = {}
for _, name in ipairs({ "CharacterModelFrameBackgroundTopLeft",
    "CharacterModelFrameBackgroundTopRight", "CharacterModelFrameBackgroundBotLeft",
    "CharacterModelFrameBackgroundBotRight" }) do
    modelBackgrounds[#modelBackgrounds + 1] = Texture()
    _G[name] = modelBackgrounds[#modelBackgrounds]
end

local hooks = {}
local themeListener
hooksecurefunc = function(target, method, callback)
    if type(target) == "string" then
        hooks[target] = method
        return
    end
    assert(target == character and (method == "SetSelectedModeTabByFrame"
        or method == "UpdateTabLayout"))
    hooks[method] = callback
end
-- PaperDoll slot updates arrive through this global.
PaperDollItemSlotButton_Update = function() end
-- So do native stats updates.
PaperDollFrame_UpdateStats = function() end
local headSlot = Frame()
headSlot.Icon, headSlot.IconBorder = Texture(), Texture()
CharacterHeadSlot = headSlot
PAPERDOLL_SIDEBARS = { "Stats", "Equipment", "Titles", "Pet" }
PaperDollSidebarTabs = Frame()
for index = 1, #PAPERDOLL_SIDEBARS do
    local tab = Frame()
    tab.TabBg, tab.Hider, tab.Highlight = Texture(), Texture(), Texture()
    _G["PaperDollSidebarTab" .. index] = tab
end
PaperDollFrame_UpdateSidebarTabs = function() end
local iconSpecs = {}
local combatLocked = false
-- Registry.QueueJob runs a job once on the next frame (Core/Registry.lua).
local queuedJobs = {}
local function QueueJob(job)
    for _, pending in ipairs(queuedJobs) do if pending == job then return end end
    queuedJobs[#queuedJobs + 1] = job
end
local function NextFrame()
    local jobs = queuedJobs
    queuedJobs = {}
    for _, job in ipairs(jobs) do job() end
end
local ns = {
    Client = { isForever = true },
    DB = { theme = { look = "foreverGlass" } },
    Theme = { GetColor = function() return 0.7, 0.5, 0.3, 1 end },
    Registry = { AddListener = function(_, callback) themeListener = callback end, QueueJob = QueueJob },
    IsCombatLocked = function() return combatLocked end,
    Safety = assert(loadfile(rootPath .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", {}),
    Cosmetics = {
        Fade = function(region) region.alpha = 0; return true end,
        Restore = function(region) region.alpha = 1; return true end,
        FadeNineSlice = function() return true end,
    },
    Surface = {
        Attach = function(target, spec) target.surface = spec; return spec end,
        -- The update-hook attach (Surface.Ensure) paints like Attach here.
        Ensure = function(target, spec) target.surface = spec; return spec end,
        SetActive = function(target, active) target.active = active; return true end,
        SetVisible = function(target, shown) target.surfaceVisible = shown; return true end,
    },
    ControlSkin = { ApplyButton = function(tab, _, spec)
        tab.surface = spec
        return true
    end },
    CharacterStats = { Apply = function() end, Disable = function() end },
    GearAnnotations = { IsWide = function() return false end },
    CharacterDetails = { Apply = function() end, Disable = function() end, views = {} },
    EQoLCharacter = { Apply = function() end, Disable = function() end },
    GenericWindows = { IsCategoryEnabled = function() return true end },
    CombatGate = { RunOrDefer = function(_, callback) callback(); return true end,
        Cancel = function() end },
    IconSkin = { Apply = function(_, _, spec)
        iconSpecs[#iconSpecs + 1] = spec
        return {}
    end },
}
for _, file in ipairs({ "AdapterKit", "SharedChrome", "PaperDollChrome", "CharacterPanel" }) do
    assert(loadfile(rootPath .. "/MSUF_Suite_Skin/Adapters/" .. file .. ".lua"))("MSUF_Suite_Skin", ns)
end
assert(ns.CharacterPanel.Apply("blizzardWindows"))
assert(PaperDollSidebarTab4.surface, "70170 pet sidebar tab was not skinned")
assert(hooks.PaperDollFrame_UpdateSidebarTabs, "native sidebar updates were not observed")
PaperDollSidebarTab4.surface = nil
hooks.PaperDollFrame_UpdateSidebarTabs()
assert(PaperDollSidebarTab4.surface, "native sidebar update lost the fourth tab")
-- A three-tab native layout leaves a stray fourth frame alone.
PAPERDOLL_SIDEBARS[4] = nil
PaperDollSidebarTab4.surface = nil
hooks.PaperDollFrame_UpdateSidebarTabs()
assert(not PaperDollSidebarTab4.surface and PaperDollSidebarTab3.surface,
    "three-tab native layouts did not retain their own sidebar count")
PAPERDOLL_SIDEBARS[4] = "Pet"
hooks.PaperDollFrame_UpdateSidebarTabs()
local function Parts(index) return ns.CharacterPanel.tabParts[tabs[index]] end
assert(itemLevelValue.text == "612.25 / 615.50", "the skin did not format the item level")
assert(left.surface.role == "panel" and right.surface.role == "panel"
    and leftArt.alpha == 0 and rightArt.alpha == 0 and right.StoneBg.alpha == 0,
    "Camelot panes did not receive the Forever material")
assert(reputation.ScrollBox.surface.role == "panel"
    and reputation.ReputationDetailFrame.surface.role == "card",
    "native Forever reputation content was not skinned")
assert(tabs[2].active and not tabs[1].active and not tabs[3].active
    and tabs[2].surface.activeRole == "navigationActive"
    and tabs[2].Background.alpha == 0,
    "Forever mode tabs lost their native selection state")
assert(character.ModeTabs.points[1][2] == character
    and character.ModeTabs.points[1][4] == 8
    and character.ModeTabs.points[1][5] == -26
    and character.ModeTabs.frameStrata == "HIGH"
    and character.ModeTabs.frameLevel >= 520
    and tabs[2].points[1][4] > 0
    and Parts(2).label.shown == true
    and Parts(2).label.text == "Reputation"
    and tabs[2].Icon.alpha == 0 and character.TitleText.alpha == 1
    and Parts(2).rule.shown
    and not Parts(1).rule.shown,
    "Forever tabs did not form a visible, labelled row above the content")
assert(modelBackgrounds[1].vertex[1] == 0.36
    and modelBackgrounds[1].vertex[3] == 0.54,
    "Forever character model lost its toned race backdrop")
assert(hooks.SetSelectedModeTabByFrame, "native mode-tab update was not observed")
local currency = Frame()
currency.parent = character
currency.ScrollBox = Frame()
currency.DetailFrame = Frame()
TokenFrame = currency
character.selectedTab = 5
hooks.SetSelectedModeTabByFrame()
assert(currency.ScrollBox.surface.role == "panel"
    and currency.DetailFrame.surface.role == "card"
    and tabs[5].active and Parts(5).rule.shown,
    "lazy native Forever currency content did not receive its skin")
character.selectedTab = 3
hooks.SetSelectedModeTabByFrame()
assert(not tabs[2].active and tabs[3].active
    and Parts(3).rule.shown and not Parts(2).rule.shown,
    "native mode-tab change did not refresh the Forever selection")
assert(hooks.UpdateTabLayout, "native tab layout was not observed")
character:UpdateTabLayout()
hooks.UpdateTabLayout()
assert(tabs[3].points[1][4] > tabs[2].points[1][4],
    "native layout refresh undid the Forever icon rail")
assert(themeListener, "Forever tabs did not observe look changes")
ns.DB.theme.look = "midnight"
themeListener(nil, "theme", "look")
NextFrame()
assert(character.ModeTabs.points[1][3] == "TOPRIGHT"
    and Parts(2).label.shown == false
    and tabs[2].Icon.alpha == 1
    and character.ModeTabs.frameStrata == "MEDIUM"
    and character.ModeTabs.frameLevel == 0
    and modelBackgrounds[1].vertex[1] == 1,
    "switching looks did not restore the native tabs")
ns.DB.theme.look = "foreverGlass"
themeListener(nil, "theme", "look")
NextFrame()
assert(Parts(2).label.shown == true and Parts(3).rule.shown
    and modelBackgrounds[1].vertex[1] == 0.36,
    "reselecting Forever did not restore the tab row and backdrop")
character.width = 398
character:UpdateTabLayout()
hooks.UpdateTabLayout()
assert(character.ModeTabs.points[1][3] == "TOPRIGHT"
    and character.ModeTabs.frameStrata == "MEDIUM"
    and Parts(2).label.shown == false,
    "collapsed Forever panel did not fall back to accessible native side tabs")
character.width = 646
themeListener(nil, "profile", nil)
NextFrame()
assert(character.ModeTabs.frameStrata == "HIGH"
    and Parts(2).label.shown == true,
    "expanded Forever panel did not restore visible top tabs")

-- Blizzard's PaperDoll post-hooks: a raising pass is reported and never
-- reaches Blizzard's caller.
local getColor = ns.Theme.GetColor
ns.Theme.GetColor = function() error("contract: theme raised") end
local before = #reported
local finished = pcall(hooks.UpdateTabLayout)
ns.Theme.GetColor = getColor
assert(finished and #reported == before + 1,
    "a raising PaperDoll pass escaped into Blizzard's tab layout caller")

-- Slot updates repeat for every equipment change; the icon skin reuses one spec.
local specCount = #iconSpecs
hooks.PaperDollItemSlotButton_Update(headSlot)
hooks.PaperDollItemSlotButton_Update(headSlot)
assert(#iconSpecs == specCount + 2 and iconSpecs[#iconSpecs] == iconSpecs[#iconSpecs - 1],
    "every PaperDoll slot update built a new icon spec")
-- A stats update during combat: the stats pass waits for combat to end, the
-- skin's stat details follow Blizzard's reassigned rows at once.
local synced, statsPasses = {}, 0
ns.CharacterStats.SyncDetails = function(pane) synced[#synced + 1] = pane end
ns.CharacterStats.Apply = function() statsPasses = statsPasses + 1 end
assert(hooks.PaperDollFrame_UpdateStats, "native stats updates were not observed")
combatLocked = true
hooks.PaperDollFrame_UpdateStats()
combatLocked = false
assert(#synced == 1 and synced[1] == CharacterStatsPane and statsPasses == 0,
    "a stats update during combat did not sync the stat details, or ran the stats pass")
hooks.PaperDollFrame_UpdateStats()
assert(#synced == 1 and statsPasses == 1, "an out-of-combat stats update did not run the stats pass")

assert(ns.CharacterPanel.Disable("blizzardWindows")
    and left.surfaceVisible == false and right.surfaceVisible == false
    and character.ModeTabs.points[1][3] == "TOPRIGHT"
    and Parts(2).label.shown == false
    and modelBackgrounds[1].vertex[1] == 1,
    "disabling the character skin left its materials visible")
assert(itemLevelValue.text == "612", "disabling the character skin did not give back Blizzard's item level")
-- Runtime state lives in side tables, not in fields on Blizzard's frames.
local blizzardFrames = { character, character.ModeTabs, CharacterModelScene, CharacterStatsPane }
for _, tab in ipairs(tabs) do blizzardFrames[#blizzardFrames + 1] = tab end
for _, frame in ipairs(blizzardFrames) do
    for key in pairs(frame) do
        assert(type(key) ~= "string" or not key:find("^_msuf"), "the skin wrote " .. key .. " onto a Blizzard frame")
    end
end
print("Suite Forever character: Camelot panes, visible mode tabs and restore passed")
