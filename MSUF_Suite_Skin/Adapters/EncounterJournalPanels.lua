local _, NS = ...

-- Exact encounter-page templates. No tree walk on row reuse or navigation.
local Panels = {}
NS.EncounterJournalPanels = Panels
local Kit, Safety = NS.AdapterKit, NS.Safety
local Field, Path = Safety.Field, Kit.Path
local Fade, Text = Kit.Fade, Kit.SetTextColor
local PANEL = Kit.SurfaceSpec("panel", 8, 1)
local CARD = Kit.SurfaceSpec("card", 8, 2)
local BUTTON = {
    role = "button", activeRole = "buttonPrimary", useControlShape = true, inset = 1, regions = { "Background" },
}
local BOSS = { role = "card", activeRole = "navigationActive", radius = 6, inset = 1 }
local NAV = { role = "navigation", activeRole = "navigationActive", useControlShape = true, inset = 1, active = false }
local NAV_ACTIVE = { role = "navigation", activeRole = "navigationActive", useControlShape = true, inset = 1, active = true }
local SIDE_TABS = { "overviewTab", "lootTab", "bossTab", "modelTab" }
local NAV_ART = { "arrowUp", "arrowDown", "selected" }
local BORDER_ART = {
    "InsetBorderTop", "InsetBorderBottom", "InsetBorderLeft", "InsetBorderRight",
    "InsetBorderTopLeft", "InsetBorderTopRight", "InsetBorderBottomLeft", "InsetBorderBottomRight",
}
local NAV_JOB = "encounterJournal:navigation"
local TABS_JOB = "encounterJournal:side-tabs"
local navHooked, tabsHooked = false, false
local FlushNavigation
local FlushSideTabs

local function Control(state, button, spec)
    if not button or not Safety.CanCreateRegions(button, true) then return end
    if not state.journalControls then state.journalControls = Kit.WeakSet() end
    if state.journalControls[button] ~= spec and Kit.SkinControl(state, button, spec) then
        Fade(state, Safety.Read(button, "GetNormalTexture"))
        state.journalControls[button] = spec
    end
end

local function NavButton(state, button, active)
    if not button then return end
    Control(state, button, active and NAV_ACTIVE or NAV)
    Kit.FadeFields(state, button, NAV_ART)
    NS.Surface.SetActive(button, active)
    Text(state.textColors, Field(button, "text"), active and "title" or "text", true)
    Control(state, Field(button, "MenuArrowButton"), BUTTON)
end

function Panels.Navigation(state)
    if not state.active then return end
    if NS.IsCombatLocked() then
        if not state.deferred[NAV_JOB] then
            state.deferred[NAV_JOB] = true
            NS.CombatGate.RunOrDefer(NAV_JOB, FlushNavigation)
        end
        return
    end
    if Kit.DeferHidden(state.frame, state, Panels.Controls, state) then return end
    local nav = Field(state.frame, "navBar")
    local list = Field(nav, "navList")
    if type(list) == "table" then
        for index = 1, math.min(#list, 12) do NavButton(state, list[index], index == #list) end
    end
    Control(state, Field(nav, "overflow"), BUTTON)
end

FlushNavigation = function()
    local state = NS.EncounterJournalSkin.activeState
    if not state then return end
    state.deferred[NAV_JOB] = nil
    if NS.IsCombatLocked() then return end
    Panels.Navigation(state)
end

local function OnNavigation(nav)
    local state = NS.EncounterJournalSkin.activeState
    if not state or not state.active or nav ~= Field(state.frame, "navBar") then return end
    Safety.Dispatch(Panels.Navigation, state)
end

function Panels.SideTabs(state)
    if not state.active then return end
    if NS.IsCombatLocked() then
        if not state.deferred[TABS_JOB] then
            state.deferred[TABS_JOB] = true
            NS.CombatGate.RunOrDefer(TABS_JOB, FlushSideTabs)
        end
        return
    end
    if Kit.DeferHidden(state.frame, state, Panels.Controls, state) then return end
    local info = Path(state.frame, "encounter", "info")
    local selected = Field(info, "tab")
    for index = 1, #SIDE_TABS do
        local button = Field(info, SIDE_TABS[index])
        local active = selected ~= nil and selected == Safety.Read(button, "GetID")
        -- EncounterTabTemplate uses info.tab and locked highlights, not
        -- PanelTemplates selection. Preserve both semantic icon textures.
        Control(state, button, active and NAV_ACTIVE or NAV)
        NS.Surface.SetActive(button, active)
    end
end

FlushSideTabs = function()
    local state = NS.EncounterJournalSkin.activeState
    if not state then return end
    state.deferred[TABS_JOB] = nil
    if NS.IsCombatLocked() then return end
    Panels.SideTabs(state)
end

local function OnSideTabChanged()
    local state = NS.EncounterJournalSkin.activeState
    if state and state.active then Safety.Dispatch(Panels.SideTabs, state) end
end

function Panels.Controls(state)
    Panels.Navigation(state)
    Panels.SideTabs(state)
end

local function JournalBackground(region, state, name)
    -- EncounterFrameInfoBG has a global name, but no parentKey in the XML.
    if name and Safety.Read(region, "GetName") == name then Fade(state, region) end
end

local function StaticChrome(state, info)
    if state.journalChrome then return end
    state.journalChrome = true
    local name = Safety.Read(info, "GetName")
    Kit.ForEachRegion(info, JournalBackground, state, type(name) == "string" and name .. "BG" or nil)
    Fade(state, Field(info, "leftShadow"))
    Fade(state, Field(info, "rightShadow"))
    Fade(state, Field(state.frame, "PortraitContainer"))
    local nav = Field(state.frame, "navBar")
    Kit.FadeNativeTextures(state, nav)
    Kit.FadeNativeTextures(state, Field(nav, "overlay"))
    Kit.FadeNativeTextures(state, Field(nav, "home"))
    Kit.FadeFields(state, nav, BORDER_ART)
    Kit.Ensure(state, nav, PANEL)
    if not navHooked then navHooked = Kit.HookGlobal("NavBar_CheckLength", OnNavigation) end
end

local function DetailText(state, info, instance)
    -- ScrollingFont:SetTextColor takes a ColorMixin; theme the actual text.
    Text(state.textColors, Path(instance, "LoreScrollingFont", "ScrollBox", "FontStringContainer", "FontString"), "text")
    Text(state.textColors, Path(info, "detailsScroll", "child", "description"), "text")
    Text(state.textColors, Path(info, "overviewScroll", "child", "description"), "text")
    Text(state.textColors, Path(info, "model", "imageTitle"), "title")
end

function Panels.Apply(state)
    local encounter = Field(state.frame, "encounter")
    if not encounter or not Safety.CanCreateRegions(encounter, true) then return end
    Kit.Ensure(state, encounter, PANEL)
    local instance, info = Field(encounter, "instance"), Field(encounter, "info")
    if instance and Safety.CanCreateRegions(instance, true) then
        Fade(state, Field(instance, "loreBG"))
        Fade(state, Field(instance, "titleBG"))
        Kit.Ensure(state, instance, CARD)
        Text(state.textColors, Field(instance, "title"), "title")
    end
    if not info or not Safety.CanCreateRegions(info, true) then return end
    StaticChrome(state, info)
    Kit.Ensure(state, info, PANEL)
    Text(state.textColors, Field(info, "instanceTitle"), "title")
    Text(state.textColors, Field(info, "encounterTitle"), "title")
    DetailText(state, info, instance)
    Control(state, Field(info, "difficulty"), BUTTON)
    local loot = Field(info, "LootContainer")
    Control(state, Field(loot, "filter"), BUTTON)
    Control(state, Field(loot, "slotFilter"), BUTTON)
    local filter = Field(loot, "classClearFilter")
    Kit.FadeNativeTextures(state, filter)
    Kit.Ensure(state, filter, PANEL)
    Text(state.textColors, Field(filter, "text"), "muted")
    Panels.Navigation(state)
    Panels.SideTabs(state)
    if not tabsHooked then tabsHooked = Kit.HookGlobal("EncounterJournal_SetTab", OnSideTabChanged) end
end

function Panels.Row(state, row)
    if Field(row, "creature") and Field(row, "text") then
        -- EncounterBossButtonTemplate: preserve portrait and defeated marker;
        -- replace native button states once, including its locked highlight.
        Control(state, row, BOSS)
        Text(state.textColors, Field(row, "text"), "text", true)
        return true
    end
    -- EncounterItemTemplate: these two are parchment, not the item icon.
    Fade(state, Field(row, "bossTexture"))
    Fade(state, Field(row, "bosslessTexture"))
    return false
end

function Panels.Reset(state)
    state.journalChrome, state.journalControls = nil, nil
end

return Panels
