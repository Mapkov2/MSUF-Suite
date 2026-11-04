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
local HEADER_ART = {
    "eLeftUp", "eMidUp", "eRightUp", "eLeftDown", "eMidDown", "eRightDown",
    "cLeftUp", "cMidUp", "cRightUp", "cLeftDown", "cMidDown", "cRightDown",
}
local HEADER = { role = "navigation", useControlShape = true, inset = 0, regions = HEADER_ART }
local bulletGlyphs = Kit.WeakSet()
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

-- SimpleHTML has a paragraph selector; the shared color ledger expects a
-- FontString-shaped interface. These owned proxies retain its restore/theme
-- handling without changing native text, hyperlinks or widget methods.
local Paragraph = {}
function Paragraph:IsForbidden() return Safety.IsForbidden(self.target) end
function Paragraph:IsProtected() return Safety.GetProtection(self.target) end
function Paragraph:GetTextColor() return Safety.Call(self.target, "GetTextColor", "p") end
function Paragraph:SetTextColor(r, g, b, a) self.target:SetTextColor("p", r, g, b, a) end
local paragraphMeta = { __index = Paragraph }

local function ParagraphText(state, target)
    if not Safety.HasMethod(target, "SetTextColor") then return end
    state.journalParagraphs = state.journalParagraphs or Kit.WeakSet()
    local paragraph = state.journalParagraphs[target]
    if not paragraph then
        paragraph = setmetatable({ target = target }, paragraphMeta)
        state.journalParagraphs[target] = paragraph
    end
    Text(state.textColors, paragraph, "text", true)
end

local function Bullet(state, bullet)
    local art = Field(bullet, "Bullet")
    if not art or not Safety.CanCreateRegions(bullet, not NS.IsCombatLocked())
        or not Safety.CanDecorate(art, not NS.IsCombatLocked()) then return end
    local glyph = bulletGlyphs[bullet]
    if not glyph then
        glyph = bullet:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        glyph:SetAllPoints(art)
        glyph:SetText("\226\128\162")
        bulletGlyphs[bullet] = glyph
    end
    if not Safety.CanDecorate(glyph, not NS.IsCombatLocked()) then return end
    state.journalGlyphs = state.journalGlyphs or Kit.WeakSet()
    state.journalGlyphs[glyph] = true
    Text(state.textColors, glyph, "text")
    Fade(state, art)
    glyph:Show()
end

local function OverviewHeader(state, overview)
    if not Field(overview, "header") then return end
    Fade(state, Field(overview, "header"))
    -- This title has a native global name but no parentKey in the template.
    local name = Safety.Read(overview, "GetName")
    if name then Text(state.textColors, Field(_G, name .. "Title"), "title") end
end

local function AbilityText(state, header)
    if not header then return end
    Text(state.textColors, Field(header, "loreDescription"), "text", true)
    Text(state.textColors, Field(header, "description"), "text", true)
    ParagraphText(state, Path(header, "overviewDescription", "Text"))
    local bullets = Field(header, "Bullets")
    if type(bullets) == "table" then
        for index = 1, math.min(#bullets, 128) do
            ParagraphText(state, Field(bullets[index], "Text"))
            Bullet(state, bullets[index])
        end
    end
    local button = Field(header, "button")
    Control(state, button, HEADER)
    Text(state.textColors, Field(button, "title"), "title", true)
    Text(state.textColors, Field(button, "expandedIcon"), "text", true)
    Fade(state, Field(header, "descriptionBG"))
    Fade(state, Field(header, "descriptionBGBottom"))
end

local function AbilityHeaders(state, headers)
    if type(headers) ~= "table" then return end
    local count = 0
    for _, header in pairs(headers) do
        AbilityText(state, header)
        count = count + 1
        if count == 128 then return end
    end
end

local function DeferAbilityText(state)
    state.journalAbilityJob = state.journalAbilityJob or {}
    return Kit.DeferHidden(state.frame, state.journalAbilityJob, Panels.Abilities, state)
end

function Panels.Abilities(state)
    if not state.active or DeferAbilityText(state) then return end
    local encounter = Field(state.frame, "encounter")
    local overview = Path(encounter, "info", "overviewScroll", "child")
    OverviewHeader(state, overview)
    AbilityText(state, overview)
    AbilityText(state, Path(encounter, "info", "detailsScroll", "child"))
    AbilityHeaders(state, Field(overview, "overviews"))
    AbilityHeaders(state, Field(encounter, "usedHeaders"))
end

local function OnAbilityTextChanged(object)
    local state = NS.EncounterJournalSkin.activeState
    if not state or not state.active then return end
    local header = Safety.Read(object, "GetParent")
    local parent = header
    for _ = 1, 12 do
        if parent == state.frame then
            if not DeferAbilityText(state) then AbilityText(state, header) end
            return
        end
        parent = Safety.Read(parent, "GetParent")
        if not parent then return end
    end
end

local function OnEncounterSelected()
    local state = NS.EncounterJournalSkin.activeState
    if state and state.active then Panels.Abilities(state) end
end

local tipContexts = Kit.WeakSet()
local TIP = Kit.SurfaceSpec("tooltip", 6, 1)
local Vertex = setmetatable({}, paragraphMeta)
function Vertex:GetTextColor() return Safety.Call(self.target, "GetVertexColor") end
function Vertex:SetTextColor(r, g, b, a) self.target:SetVertexColor(r, g, b, a) end
local vertexMeta = { __index = Vertex }

local function TipTint(context, texture, role)
    if not Safety.HasMethod(texture, "SetDesaturated")
        or not Safety.CanDecorate(texture, not NS.IsCombatLocked()) then return end
    local desaturated = Safety.Read(texture, "IsDesaturated")
    if type(desaturated) ~= "boolean" then return end
    local tint = context.tints[texture]
    if not tint then
        tint = setmetatable({ target = texture }, vertexMeta)
        context.tints[texture] = tint
    end
    if tint.originalDesaturated == nil then tint.originalDesaturated = desaturated end
    texture:SetDesaturated(true)
    Text(context.textColors, tint, role, true)
end

local function CanRestoreTip(tip, context)
    local allowImplicit = not NS.IsCombatLocked()
    if not Safety.CanDecorate(tip, allowImplicit) then return false end
    for target in pairs(context.textColors.roles) do
        if not Safety.CanDecorate(target, allowImplicit) then return false end
    end
    local regions = NS.Cosmetics.owners[context.owner]
    if regions then
        for region in pairs(regions) do
            if not Safety.CanDecorate(region, allowImplicit) then return false end
        end
    end
    return true
end

local function RestoreTip(tip)
    local context = tipContexts[tip]
    if not context or not context.active then return end
    if not CanRestoreTip(tip, context) then
        if NS.IsCombatLocked() then NS.CombatGate.RunOrDefer(context, context.restore) end
        return
    end
    NS.CombatGate.Cancel(context)
    context.active = false
    Kit.HideSurfaces(context)
    Kit.RestoreTextColors(context.textColors)
    for texture, tint in pairs(context.tints) do
        if Safety.CanDecorate(texture, not NS.IsCombatLocked()) and Safety.Read(texture, "IsDesaturated") == true then
            texture:SetDesaturated(tint.originalDesaturated)
            tint.originalDesaturated = nil
        end
    end
    local regions = NS.Cosmetics.owners[context.owner]
    if regions then
        for region in pairs(regions) do
            if Safety.CanDecorate(region, not NS.IsCombatLocked()) then NS.Cosmetics.Restore(region, context.owner) end
        end
    end
end

local function StyleTip(state, tip)
    if not Safety.CanCreateRegions(tip, not NS.IsCombatLocked()) then return end
    local context = tipContexts[tip]
    if not context then
        context = { surfaces = Kit.WeakSet(), textColors = Kit.NewTextColors(), tints = Kit.WeakSet() }
        context.owner = context
        context.restore = function() RestoreTip(tip) end
        tipContexts[tip] = context
        tip:HookScript("OnHide", Safety.Isolated(RestoreTip))
        tip:HookScript("OnShow", function()
            if Safety.Read(tip, "GetParent") ~= Field(_G, "EncounterJournalJourneysTab") then
                Safety.Dispatch(RestoreTip, tip)
            end
        end)
    end
    NS.CombatGate.Cancel(context)
    if not context.active then
        Kit.FadeNativeTextures(context, tip)
        Fade(context, Path(tip, "Arrow", "Glow"))
    end
    context.active = true
    state.journalTips = state.journalTips or Kit.WeakSet()
    state.journalTips[tip] = true
    Kit.Ensure(context, tip, TIP)
    Text(context.textColors, Field(tip, "Text"), "text")
    TipTint(context, Path(tip, "Arrow", "Arrow"), "muted")
    TipTint(context, Path(tip, "CloseButton", "Texture"), "text")
end

local function OnHelpTipShown(provider, parent)
    local state = NS.EncounterJournalSkin.activeState
    if not state or not state.active or Kit.IsHidden(state.frame) or not parent
        or parent ~= Field(_G, "EncounterJournalJourneysTab")
        or Safety.Read(parent, "GetParent") ~= state.frame then return end
    local pool = Field(provider, "framePool")
    if not Safety.HasMethod(pool, "GetNextActive") then return end
    local tip
    for _ = 1, 8 do
        tip = pool:GetNextActive(tip)
        if not tip then return end
        if Safety.Read(tip, "GetParent") == parent then StyleTip(state, tip) end
    end
end

function Panels.RefreshTips(state)
    if not state.journalTips or Kit.IsHidden(state.frame) then return end
    for tip in pairs(state.journalTips) do
        if tipContexts[tip].active then
            local parent = Safety.Read(tip, "GetParent")
            if parent == Field(_G, "EncounterJournalJourneysTab") and Safety.Read(parent, "GetParent") == state.frame
                and not Kit.IsHidden(tip) then
                StyleTip(state, tip)
            else
                RestoreTip(tip)
            end
        end
    end
end

local tipHooked = false
local function HelpTips(state)
    local provider = Field(_G, "HelpTip")
    if not tipHooked then tipHooked = Kit.HookFunction(provider, "Show", Safety.Isolated(OnHelpTipShown)) end
    if provider then OnHelpTipShown(provider, Field(_G, "EncounterJournalJourneysTab")) end
end

local bulletsHooked, headerHooked, encounterHooked = false, false, false
local function HookAbilities()
    if not bulletsHooked then bulletsHooked = Kit.HookGlobal("EncounterJournal_SetBullets", OnAbilityTextChanged) end
    if not headerHooked then headerHooked = Kit.HookGlobal("EncounterJournal_UpdateButtonState", OnAbilityTextChanged) end
    if not encounterHooked then encounterHooked = Kit.HookGlobal("EncounterJournal_DisplayEncounter", OnEncounterSelected) end
end

local function DetailText(state, info, instance)
    -- ScrollingFont:SetTextColor takes a ColorMixin; theme the actual text.
    Text(state.textColors, Path(instance, "LoreScrollingFont", "ScrollBox", "FontStringContainer", "FontString"), "text")
    Text(state.textColors, Path(info, "detailsScroll", "child", "description"), "text")
    Text(state.textColors, Path(info, "overviewScroll", "child", "description"), "text")
    Text(state.textColors, Path(info, "model", "imageTitle"), "title")
end

local function ScrollBar(state, bar)
    if bar then NS.ScrollBarSkin.Apply(bar, state.owner) end
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
    HookAbilities()
    Panels.Abilities(state)
    ScrollBar(state, Field(info, "BossesScrollBar"))
    ScrollBar(state, Path(info, "overviewScroll", "ScrollBar"))
    ScrollBar(state, Path(info, "detailsScroll", "ScrollBar"))
    ScrollBar(state, Field(instance, "LoreScrollBar"))
    Control(state, Field(info, "difficulty"), BUTTON)
    local loot = Field(info, "LootContainer")
    ScrollBar(state, Field(loot, "ScrollBar"))
    Control(state, Field(loot, "filter"), BUTTON)
    Control(state, Field(loot, "slotFilter"), BUTTON)
    local filter = Field(loot, "classClearFilter")
    Kit.FadeNativeTextures(state, filter)
    Kit.Ensure(state, filter, PANEL)
    Text(state.textColors, Field(filter, "text"), "muted")
    Panels.Navigation(state)
    Panels.SideTabs(state)
    HelpTips(state)
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
    state.journalParagraphs = nil
    if state.journalGlyphs then
        for glyph in pairs(state.journalGlyphs) do
            if Safety.CanDecorate(glyph, not NS.IsCombatLocked()) then glyph:Hide() end
        end
    end
    state.journalGlyphs = nil
    if state.journalTips then
        for tip in pairs(state.journalTips) do RestoreTip(tip) end
    end
    state.journalTips = nil
    if state.journalAbilityJob then Kit.CancelHidden(state.journalAbilityJob) end
    state.journalAbilityJob = nil
end

return Panels
