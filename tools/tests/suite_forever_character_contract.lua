local rootPath = assert(arg[1], "Suite root required")

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
    assert(target == character and (method == "SetSelectedModeTabByFrame"
        or method == "UpdateTabLayout"))
    hooks[method] = callback
end
local ns = {
    Client = { isForever = true },
    DB = { theme = { look = "foreverGlass" } },
    Theme = { GetColor = function() return 0.7, 0.5, 0.3, 1 end },
    Registry = { AddListener = function(_, callback) themeListener = callback end },
    IsCombatLocked = function() return false end,
    Safety = {
        CanCreateRegions = function() return true end,
        CanDecorate = function() return true end,
    },
    Cosmetics = {
        Fade = function(region) region.alpha = 0; return true end,
        Restore = function(region) region.alpha = 1; return true end,
        FadeNineSlice = function() return true end,
    },
    Surface = {
        Attach = function(target, spec) target.surface = spec; return spec end,
        SetActive = function(target, active) target.active = active; return true end,
        SetVisible = function(target, shown) target.surfaceVisible = shown; return true end,
    },
    CharacterStats = { Disable = function() end },
    GearAnnotations = { IsWide = function() return false end },
    CharacterDetails = { Apply = function() end, Disable = function() end, views = {} },
    EQoLCharacter = { Apply = function() end, Disable = function() end },
    GenericWindows = { IsCategoryEnabled = function() return true end },
    CombatGate = { RunOrDefer = function(_, callback) callback(); return true end,
        Cancel = function() end },
}
assert(loadfile(rootPath .. "/MSUF_Suite_Skin/Adapters/CharacterPanel.lua"))("MSUF_Suite_Skin", ns)
assert(ns.CharacterPanel.Apply("blizzardWindows"))
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
    and tabs[2]._msufForeverLabel.shown == true
    and tabs[2]._msufForeverLabel.text == "Reputation"
    and tabs[2].Icon.alpha == 0 and character.TitleText.alpha == 1
    and tabs[2]._msufForeverRule.shown
    and not tabs[1]._msufForeverRule.shown,
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
    and tabs[5].active and tabs[5]._msufForeverRule.shown,
    "lazy native Forever currency content did not receive its skin")
character.selectedTab = 3
hooks.SetSelectedModeTabByFrame()
assert(not tabs[2].active and tabs[3].active
    and tabs[3]._msufForeverRule.shown and not tabs[2]._msufForeverRule.shown,
    "native mode-tab change did not refresh the Forever selection")
assert(hooks.UpdateTabLayout, "native tab layout was not observed")
character:UpdateTabLayout()
hooks.UpdateTabLayout()
assert(tabs[3].points[1][4] > tabs[2].points[1][4],
    "native layout refresh undid the Forever icon rail")
assert(themeListener, "Forever tabs did not observe look changes")
ns.DB.theme.look = "midnight"
themeListener(nil, "theme", "look")
assert(character.ModeTabs.points[1][3] == "TOPRIGHT"
    and tabs[2]._msufForeverLabel.shown == false
    and tabs[2].Icon.alpha == 1
    and character.ModeTabs.frameStrata == "MEDIUM"
    and character.ModeTabs.frameLevel == 0
    and modelBackgrounds[1].vertex[1] == 1,
    "switching looks did not restore the native tabs")
ns.DB.theme.look = "foreverGlass"
themeListener(nil, "theme", "look")
assert(tabs[2]._msufForeverLabel.shown == true and tabs[3]._msufForeverRule.shown
    and modelBackgrounds[1].vertex[1] == 0.36,
    "reselecting Forever did not restore the tab row and backdrop")
character.width = 398
character:UpdateTabLayout()
hooks.UpdateTabLayout()
assert(character.ModeTabs.points[1][3] == "TOPRIGHT"
    and character.ModeTabs.frameStrata == "MEDIUM"
    and tabs[2]._msufForeverLabel.shown == false,
    "collapsed Forever panel did not fall back to accessible native side tabs")
character.width = 646
themeListener(nil, "profile", nil)
assert(character.ModeTabs.frameStrata == "HIGH"
    and tabs[2]._msufForeverLabel.shown == true,
    "expanded Forever panel did not restore visible top tabs")
assert(ns.CharacterPanel.Disable("blizzardWindows")
    and left.surfaceVisible == false and right.surfaceVisible == false
    and character.ModeTabs.points[1][3] == "TOPRIGHT"
    and tabs[2]._msufForeverLabel.shown == false
    and modelBackgrounds[1].vertex[1] == 1,
    "disabling the character skin left its materials visible")
print("Suite Forever character: Camelot panes, visible mode tabs and restore passed")
