local _, P = ...
local Tr, HM = P.Tr, P.HM
local PAGE, ID = "suite_nameplates", "nameplates"

local RuleRow = P.RuleRow
function P.RuleRow(page, id, rule, ...)
    local row = RuleRow(page, id, rule, ...)
    if not row or id ~= ID then return row end
    if page == PAGE and rule.section and rule.section:match("StyleOutline$") and not rule.key:match("StyleBorderSize$") then
        row.outlineFocus = false
    end
    if rule.appearanceScope then
        row.set = function(on)
            local values = { [rule.key] = on == true }
            if on and not P.Get(ID, rule.key .. "Saved") then
                local style = P.Suite.NameplateStyle
                local config = P.S.Config(ID)
                local bars = style.BarSettings(config, style.SharedBars())
                for key, parent in pairs(style.AppearanceFields(rule.appearanceScope, rule.appearanceGroup)) do
                    local value = bars[parent]
                    if bars.hideHealthBarBorders and parent:match("OutlineMode$") then value = 4 end
                    values[key] = value
                end
                values[rule.key .. "Saved"] = true
            end
            return P.SetMany(ID, values)
        end
    end
    return row
end

local HELP = {
    neutralBasics = P.Help("Show neutral nameplates",
        "A neutral creature uses the Enemy rules once it enters combat."),
    friendlyNpcBasics = P.Help("Choose how friendly NPCs appear. Enable separate dimensions to give their health bars a different size.",
        "In instances the game may restrict styling."),
    enemy = P.Help("Set enemy nameplate size, text and appearance.", "Blizzard supplies the name and health values. Mapko requests full enemy plates and both health values so normal enemies show text too. Width and height change only the enemy health bar in pixels; 0 keeps the selected bar dimensions. Backdrop, border and role fill are separate live skin layers in the preview; right-click a layer for its setting. Role colors use the saved palette; mana is only a caster hint. Open the three-dot menu here or Nameplates in MSUF Colors to change the palette."),
    friendly = P.Help("Names, health bars and text on friendly plates.",
        "Show names for all friendly players, names for party and raid members, or health bars. Names only hides Blizzard bars, casts and auras for friendly players; it does not change NPC or enemy plates. Group / outsider in the preview only changes the sample. Blizzard can forbid changes to friendly plates in instances; those frames stay under Blizzard's control."),
    enemyPower = P.Help("Show mana, energy or the current resource under Enemy and Neutral nameplates. Drag the bar in the preview to position it."),
    roleColors = P.Help("Color enemy health by type, threat and focus.",
        "Priority: focus, safe tank aggro, threat, tapped, quest, neutral, then NPC type. Turning focus off allows the next rule. Disabled threat overrides preserve Blizzard's active threat color. Tank mode uses your effective role; warnings also work for damage/healers. Secret values stay with Blizzard."),
    signals = P.Help("Blizzard's aggro, target, focus and soft target signals.",
        "Blizzard owns aggro flashes, progressive highlights and soft target icons. Optional colors tint Blizzard's existing threat textures; its health bar threat color stays under the role-color overlay. Soft target icons also need the nameplate icon switch enabled and a matching soft target in game."),
    decor = P.Help("Frame styling and clear target highlights.",
        "Frames join aligned bars; detached bars keep separate frames. Effects are static. Threshold marks a fixed percentage. Preview switches apply live."),
    native = P.Help("Presets and the Blizzard nameplate style and size apply to every type."),
    visibility = P.Help("Which units get nameplates and how plates share space.",
        "Set visibility for each unit type and how plates share space."),
    stacking = P.Help("Blizzard shares stacking spacing and motion speed across all nameplate types."),
    distance = P.Help("Blizzard shares distance, fading and screen margins across all nameplate types."),
}

-- Where every nameplate setting shows, in page order: one accordion per
-- entry and, in a tabbed one, one tab (Portrait and Class Resources style).
-- Keys missing on this client are skipped. Colors open from the section's
-- ::: menu; positions stay with the preview and reset with the section whose
-- catalog section `positions` names, or whose `positionElements` names the
-- element (both sides). A setting placed nowhere still shows, under More
-- settings.
local ROLE_SWITCHES, ROLE_COLORS = {}, {}
for _, role in ipairs(P.Suite.NameplateStyle.Roles) do
    if role.key ~= "TankMode" then ROLE_SWITCHES[#ROLE_SWITCHES + 1] = "enemy" .. role.key .. "Enabled" end
    ROLE_COLORS[#ROLE_COLORS + 1] = "enemy" .. role.key .. "Color"
end
local ENEMY = { key = "enemy", area = "enemies", title = "Enemy appearance", open = true, positions = "enemy",
  colors = {}, tabs = {
    { id = "bar", label = "Bar", help = "enemy", keys = { "enemyHealthWidthDelta", "enemyHealthHeightDelta",
        "enemyBackdropEnabled", "enemyBackdropAlpha", "enemyBorderEnabled", "enemyBorderSize", "enemyBorderStyle",
        "enemyNativeBorderEnabled" } },
    { id = "frame", label = "Frame and highlights", help = "decor", keys = {
        "enemyOuterFrame", "enemyOuterFrameSize", "enemyShadowEnabled", "enemyGlowEnabled", "enemyGlowMode", "enemyEffectSize" } },
    { id = "target", label = "Target arrows", keys = { "enemyTargetMarker", "enemyTargetStyle", "enemyTargetLayout",
        "enemyTargetAnchor", "enemyTargetDirection", "enemyTargetMarkerSize", "enemyTargetHideFriendly" } },
} }

local function BaseSections()
    return {
        { key = "native", area = "general", title = "Nameplate styling",
          keys = { "look", "nativeStyle", "nativeSize", "targetScaleEnabled", "targetScalePercent", "barGeometry",
                "classColors", "playerTitles", "levelAppearance" } },
        { key = "distance", area = "general", catalog = "distance" },
        ENEMY,
        { key = "castbar", area = "casts", catalog = "castbar", positions = "castbar" },
        { key = "enemyPower", area = "enemies", catalog = "enemyPower", positions = "enemyPower" },
        { key = "roleColors", area = "colors", title = "Enemy color rules", open = true, colors = ROLE_COLORS, tabs = {
            { id = "rules", label = "Rules", help = "roleColors", keys = { "enemyRoleColors", "enemyColorsInDungeons",
                "enemyColorsOutside", "enemyQuestColors", "enemyTankMode", "enemyPreviewRole" } },
            { id = "types", label = "Types", keys = ROLE_SWITCHES },
        } },
        { key = "signals", area = "colors", title = "Blizzard indicators", positionElements = { "SoftTarget" },
          colors = { "threatFlashColor", "threatHighlightColor" }, tabs = {
            { id = "aggro", label = "Aggro", help = "signals", keys = { "threatSignalMode", "threatFlash", "threatHighlight",
                "threatFlashColorEnabled", "threatHighlightColorEnabled" } },
            { id = "soft", label = "Soft target", keys = { "softTargetEnemy", "softTargetFriend", "softTargetInteract",
                "softTargetIconGate" } },
        } },
        { key = "friendly", area = "friendly", title = "Friendly appearance", open = true, positions = "friendly",
          tabs = {
            { id = "display", label = "Display", help = "friendly", keys = { "friendlyNamesOnly", "friendlyNameClassColor",
                "friendlyRealm", "friendlyNPCs" } },
            { id = "bar", label = "Bar", keys = { "friendlyHealthWidthDelta", "friendlyHealthHeightDelta",
                "friendlyBackdropEnabled", "friendlyBackdropAlpha", "friendlyBorderEnabled", "friendlyBorderSize",
                "friendlyBorderStyle", "friendlyNativeBorderEnabled" } },
            { id = "frame", label = "Frame and highlights", help = "decor", keys = {
                "friendlyOuterFrame", "friendlyOuterFrameSize", "friendlyShadowEnabled", "friendlyGlowEnabled", "friendlyGlowMode", "friendlyEffectSize" } },
        } },
        -- Blizzard's aura settings are the Buffs and Debuffs tabs of the Auras
        -- workspace (NameplatesAdvancedAuras.lua).
    }
end

local SECTIONS = {}
P.NameplateSections = SECTIONS
local sectionsReady
local function EnsureSections()
    if sectionsReady then return end
    for _, section in ipairs(BaseSections()) do SECTIONS[#SECTIONS + 1] = section end
    P.NameplatesAdvancedAuras.Append(SECTIONS, HELP)
    P.NameplatesExtensions.Append(SECTIONS, HELP)
    P.NameplatesSectionsLayout.Arrange(SECTIONS)
    sectionsReady = true
end

local function IsPositionRule(rule)
    return P.NameplatesStatus.IsOffset(rule.key)
end

-- The catalog rules of a key list that exist on this client.
local function Rules(keys)
    local rules, catalog = {}, P.catalog[ID].rules
    local available = P.catalog[ID].controlAvailable
    for _, key in ipairs(keys or {}) do
        local rule = catalog[key]
        if rule and (not available or available(rule)) and not P.NameplateFonts.OwnsColor(rule) then
            rules[#rules + 1] = rule
        end
    end
    return rules
end

local function VisibleRules(rules)
    local visible = {}
    for _, rule in ipairs(rules) do
        if not IsPositionRule(rule) then visible[#visible + 1] = rule end
    end
    return visible
end

-- The offsets a section's reset restores (SECTIONS: positions, positionElements).
local function PositionKeys(spec)
    local keys = {}
    for _, rule in ipairs(spec.positions and P.SectionRules(ID, spec.positions) or {}) do
        if IsPositionRule(rule) then keys[#keys + 1] = rule.key end
        local override = rule.previewFontSizeOverride
        if override then keys[#keys + 1] = override end
    end
    for _, side in ipairs(spec.positionSide and { spec.positionSide } or { "enemy", "friendly" }) do
        for _, element in ipairs(spec.positionElements or {}) do
            keys[#keys + 1] = side .. element .. "OffsetX"
            keys[#keys + 1] = side .. element .. "OffsetY"
        end
    end
    for key in pairs(spec.statusOffsets or {}) do keys[#keys + 1] = key end
    for _, tab in ipairs(spec.tabs or {}) do
        for _, key in ipairs(tab.keys) do
            local rule = P.catalog[ID].rules[key]
            if rule and rule.appearanceScope then keys[#keys + 1] = rule.key .. "Saved" end
            if rule and rule.previewFontSizeOverride then keys[#keys + 1] = rule.previewFontSizeOverride end
        end
    end
    return keys
end

-- The offsets of Blizzard's aura handles on one side. They sit in the enemy
-- and friendly catalog sections (Catalog/Nameplates.lua AddOffsets); the
-- Buffs and Debuffs tabs of the Auras workspace reset them.
function P.NameplateAuraPositionKeys(side, elements)
    local keys = {}
    for _, element in ipairs(elements) do
        keys[#keys + 1] = side .. element .. "OffsetX"
        keys[#keys + 1] = side .. element .. "OffsetY"
    end
    return keys
end

-- The same section and tab descriptors drive placement and exact navigation.
local placed
local selectedTabs = {}
local function HasColorAction(spec)
    return P.W.OpenContextColors and (spec.styleScope or spec.textCards)
end

local function HasStyleColorsLink(spec)
    return spec.styleScope and (not spec.page or spec.page == PAGE) and HasColorAction(spec)
end

local function Place(keys, sectionId, spec, tab)
    for _, key in ipairs(keys or {}) do
        if not placed[key] and not (tab and spec.sharedSettings and spec.sharedSettings[key]) then
            placed[key] = { section = sectionId, spec = spec, tab = tab }
        end
    end
end
-- Only a Nameplates page or search request needs the placement index.
local function PlacedSections()
    if placed then return placed end
    EnsureSections()
    placed = {}
    for _, spec in ipairs(SECTIONS) do
        local sectionId = PAGE .. "_" .. spec.key
        if spec.switch then Place({ spec.switch }, sectionId, spec) end
        Place(spec.keys, sectionId, spec)
        Place(spec.colors, sectionId, spec)
        for key, offset in pairs(spec.statusOffsets or {}) do
            if not placed[key] then placed[key] = { section = sectionId, spec = spec, offset = offset } end
        end
        for _, tab in ipairs(spec.tabs or {}) do
            Place(tab.keys, sectionId, spec, tab.id)
            Place(tab.colors, sectionId, spec, tab.id)
        end
        if spec.catalog then
            for _, rule in pairs(P.catalog[ID].rules) do
                if rule.section == spec.catalog and rule.key ~= "enabled" and not rule.previewOnly then
                    if not placed[rule.key] then placed[rule.key] = { section = sectionId, spec = spec } end
                end
            end
        end
    end
    for _, spec in ipairs(SECTIONS) do
        if spec.styleScope == "enemy" or spec.styleScope == "friendly" then
            for _, tab in ipairs(spec.tabs) do
                if tab.id == "colors" then
                    for _, key in ipairs(tab.colors) do
                        if not placed[key] or placed[key].tab ~= "colors" then
                            placed[key] = { section = PAGE .. "_" .. spec.key, spec = spec, tab = "colors" }
                        end
                    end
                end
            end
        end
    end
    return placed
end

-- Visible settings the placement does not name (a newer catalog rule). A
-- setting this client lacks (spec.controlAvailable) has no control at all.
local function Unplaced()
    local positions, rules = PlacedSections(), {}
    local textures = P.NameplateBarTextures
    for _, rule in ipairs(P.catalog[ID].getControls()) do
        if not positions[rule.key] and rule.key ~= "enabled" and not rule.hidden and not rule.previewOnly
            and not IsPositionRule(rule) and rule.section ~= "auraColors"
            and not textures.LegacyRule(rule.key) and not textures.Target(rule.key)
            and not P.NameplateFonts.TargetForSetting("msufsuite.nameplates." .. rule.key)
            and rule.section ~= "nativeTextures" and rule.section ~= "barGradients" then rules[#rules + 1] = rule end
    end
    return rules
end

-- Search follows the same placement as the page and preview.
function P.NameplateSearchTarget(rule)
    local placement = PlacedSections()[rule.key]
    local section = placement and placement.section
    local spec = placement and placement.spec
    if placement and placement.offset then
        return PAGE .. "_status_offset_" .. rule.key, spec.plateScope, false
    end
    if IsPositionRule(rule) then
        local side = rule.key:match("^(enemy)") or rule.key:match("^(friendly)")
            or rule.key:match("^aura(Enemy)") or rule.key:match("^aura(Friendly)")
        side = side and side:lower()
        return PAGE .. "_preview_" .. (side or "current"), side, false
    end
    if section then
        local side = P.NameplatesWorkspace.NameOptionScope(rule.key)
            or spec and (spec.searchScope or spec.statusItems and spec.positionSide)
        if rule.section == "plateHighlightPatterns" then side = spec.styleScope end
        local textIndicator = spec and spec.statusItems and rule.section == "plateExtraText"
        if textIndicator then side = spec.plateScope end
        if spec.styleScope and rule.section and rule.section:match("Style%u") then side = spec.styleScope end
        local colorTarget = textIndicator or HasColorAction(spec)
        return section, side, colorTarget and rule.color and true or nil
    end
    if rule.key == "enabled" then return PAGE .. "_enemyBasics", "enemy", false end
    if rule.section ~= "auraColors" then return PAGE .. "_more" end
end

local function RevealSection(body)
    local entry = body and HM.GetSectionEntry(body)
    local reveal = entry and HM.GetSectionEnsureVisible(entry)
    if reveal then reveal() end
end

-- A preview click already has a setting key. Use the live catalog directly,
-- even before the host has finished building its global search index.
function P.OpenNameplateSetting(key)
    local rule = key and P.catalog[ID].rules[key]
    if not rule or P.Combat() or not P.catalog[ID].controlAvailable(rule) then return false end
    local fonts = P.NameplateFonts
    if fonts.OwnsColor(rule) then return fonts.OpenColors("msufsuite.nameplates." .. key) end
    local bars = P.NameplateBarTextures.Target(key)
    if bars then
        return P.Suite.HostBridge.OpenExactMenuSetting(P.M, bars.page, bars.section, "msufsuite.nameplates." .. key)
    end
    local sectionId, _, exact = P.NameplateSearchTarget(rule)
    if not sectionId or exact == false then return false end
    local scope = P.NameplatesWorkspace.NameOptionScope(key)
    if scope and P.NameplatesWorkspace.Kind() ~= scope then P.NameplatesWorkspace.Open(scope) end
    local page = P.M.cache and P.M.cache[PAGE]
    RevealSection(page and page.sections and page.sections[sectionId])
    return P.Suite.HostBridge.OpenExactMenuSetting(P.M, PAGE, sectionId, "msufsuite.nameplates." .. key)
end

local function NamePalette()
    local scope = P.NameplatesWorkspace.Kind()
    if scope == "friendlyNpc" then
        local fonts = P.NameplateFonts
        local color = fonts and fonts.FriendlyNPCColorTarget()
        if color then return {}, nil, function() return { color } end end
    elseif scope == "neutral" then
        return Rules({ "enemyNeutralColor" })
    elseif scope == "enemy" then
        local keys = {}
        for _, role in ipairs(P.Suite.NameplateStyle.Roles) do keys[#keys + 1] = "enemy" .. role.key .. "Color" end
        return Rules(keys)
    end
end

local function RelevantColor(rule) return P.RuleEnabled(ID, rule) end

local function ColorSettings(spec)
    local selected = selectedTabs[spec.key] or spec.tabs[1].id
    if spec.textCards and selected == "name" then return NamePalette() end
    local palette
    for _, tab in ipairs(spec.tabs) do
        if tab.id == "colors" then palette = tab.colorRules end
        if tab.id == selected and tab.colorRules then
            if tab.id == "outline" or tab.id == "textures" then return tab.colorRules, RelevantColor end
            palette = tab.colorRules
            break
        end
    end
    if spec.colors then return Rules(spec.colors) end
    local auraTargets = (spec.styleScope == "enemy" or spec.styleScope == "neutral") and P.NameplatesAuraUI.ColorTargets
    return palette, nil, auraTargets
end

local function ColorsAvailable(rules, enabled)
    if not rules then return false end
    if not enabled then return true end
    for _, rule in ipairs(rules) do
        if enabled(rule) then return true end
    end
    return false
end

local function SectionColors(spec)
    return function(popup)
        local button = P.W.TopButton(popup, "Colors", 250, 24)
        button:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -76)
        HM.SkipHistoryCheckpoint(button)
        popup:SetHeight(116)
        popup:HookScript("OnShow", function()
            local rules, enabled = ColorSettings(spec)
            button:SetShown(rules ~= nil)
            popup:SetHeight(rules and 116 or 82)
            P.W.SetControlEnabled(button, ColorsAvailable(rules, enabled))
        end)
        button:SetScript("OnClick", function()
            if P.Combat() then return end
            local rules, enabled, extra = ColorSettings(spec)
            if not rules then return end
            popup:Hide()
            P.OpenRuleColors(popup, "Colors", ID, rules, enabled, extra)
        end)
    end
end

local STYLE_COLORS_WIDTH = 118

local function AttachStyleColorsLink(body, spec, sectionId)
    local button = (P.W.TopButton or P.T.Button)(body, "Open Colors", STYLE_COLORS_WIDTH, 24)
    button:SetPoint("TOPRIGHT", body, "TOPRIGHT", -16, -12)
    HM.SkipHistoryCheckpoint(button)
    button:SetScript("OnClick", function()
        if P.Combat() then return end
        local rules, enabled, extra = ColorSettings(spec)
        if ColorsAvailable(rules, enabled) then P.OpenRuleColors(button, "Colors", ID, rules, enabled, extra) end
    end)
    local meta = P.Meta(PAGE, ID, spec.key .. ".colors", "action", sectionId)
    if P.M.RegisterControlMetadata then P.M.RegisterControlMetadata(button, meta, "Colors", "button") end
    return function()
        P.W.SetControlEnabled(button, not P.Combat() and ColorsAvailable(ColorSettings(spec)))
    end
end

-- A search hit selects the rule's lazy tab before the host looks up its control.
local TAB_BODY_TOP = 59

local function Panels(ctx, builder, body, width, spec, sectionId, tabBodyTop)
    local panels, heights, byTab = {}, {}, {}
    local selectItem
    for _, tab in ipairs(spec.tabs) do
        local panel = CreateFrame("Frame", nil, body)
        panel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -tabBodyTop())
        panel:SetSize(width + 32, 100)
        panels[tab.id], byTab[tab.id] = panel, tab
    end
    local function Ensure(tabId)
        if heights[tabId] then return end
        local tab, panel = byTab[tabId], panels[tabId]
        if not tab or P.Combat() then return end
        if spec.statusItems and tab.id == "basic" then
            selectItem = P.NameplatesStatus.Basic(ctx, panel, width, spec, tab, sectionId, function(height)
                heights[tabId] = height
                panel:SetHeight(height)
                if (selectedTabs[spec.key] or spec.tabs[1].id) == tabId then
                    P.FinishBody(builder, body, -tabBodyTop() - height)
                end
            end)
            return
        end
        local y = -18
        if tab.help then
            local help = P.Description(panel, HELP[tab.help], 16, y, width, Tr(spec.title))
            y = y - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 12
        end
        if tab.before then y = tab.before(ctx, panel, y, width, sectionId, spec) end
        local entries
        if spec.textCards then
            y, entries = P.NameplatesSectionsLayout.TextCards(ctx, panel, y, width, spec, tab, sectionId)
        elseif spec.castCards then
            y, entries = P.NameplatesSectionsLayout.CastCards(ctx, panel, y, width, tab, sectionId, spec.opacityCards,
                spec.kick and spec.kick(ctx))
        elseif spec.spellPicker and tab.id == "spell" then
            local rules, spellRule = {}, nil
            for _, rule in ipairs(tab.rules) do
                if rule.key == spec.spellPicker then spellRule = rule else rules[#rules + 1] = rule end
            end
            if spellRule then y, entries = P.NameplatesExtensions.RangeSpell(ctx, panel, y, width, sectionId, spellRule) end
            entries = entries or {}
            local rest
            y, rest = P.RuleGrid(ctx, panel, PAGE, ID, rules, y, width, nil, sectionId)
            for _, entry in ipairs(rest) do entries[#entries + 1] = entry end
        else
            y, entries = P.RuleGrid(ctx, panel, spec.page or PAGE, ID, tab.rules, y, width, nil, sectionId)
        end
        for _, entry in ipairs(entries or {}) do
            if entry.widget then
                local scope = P.NameplatesWorkspace.NameOptionScope(entry.rule.key)
                HM.SetSearchTargetPrepare(entry.widget, function()
                    if scope and P.NameplatesWorkspace.Kind() ~= scope then P.NameplatesWorkspace.Open(scope) end
                    spec.select(tab.id)
                end)
            end
        end
        if tab.extra then y = tab.extra(ctx, panel, y, width, sectionId, spec) end
        heights[tabId] = -y + 14
        panel:SetHeight(heights[tabId])
    end
    return panels, heights, Ensure, function(key) if selectItem then selectItem(key) end end
end

local function Tabs(ctx, builder, body, spec, sectionId)
    local width = math.max(240, (HM.GetSectionWidth(body) or builder.width or 720) - 32)
    local tabs
    local function TabBodyTop()
        return TAB_BODY_TOP + (tabs and tabs:GetHeight() - 26 or 0)
    end
    local panels, heights, ensure, selectItem = Panels(ctx, builder, body, width, spec, sectionId, TabBodyTop)
    local values = {}
    for _, tab in ipairs(spec.tabs) do
        values[#values + 1] = { value = tab.id, text = Tr(tab.label) }
    end
    local defaultTab = spec.tabs[1].id
    local function GetTab() return selectedTabs[spec.key] or defaultTab end
    local colorLink = spec.textCards and P.NameplateFonts.AttachColorLink(body, sectionId, spec.key, GetTab)
    local refreshStyleColors = HasStyleColorsLink(spec) and AttachStyleColorsLink(body, spec, sectionId)
    local reservedWidth = refreshStyleColors and STYLE_COLORS_WIDTH + 8 or colorLink and 44 or 0
    local refresh, _, selectTab
    tabs, refresh, _, selectTab = P.W.SegmentTabs(ctx, body, {
        label = "", compact = true, wrap = true, x = 16, y = -12, values = values, frames = panels,
        width = width - reservedWidth,
        defaultTab = defaultTab,
        get = GetTab,
        set = function(tab)
            selectedTabs[spec.key] = tab
            if spec.onTab then spec.onTab(tab) end
        end,
        afterRefresh = function(tab)
            ensure(tab)
            if refreshStyleColors then refreshStyleColors() end
            P.FinishBody(builder, body, -TabBodyTop() - (heights[tab] or 100))
        end,
    })
    local function LayoutPanels()
        local top = TabBodyTop()
        for _, panel in pairs(panels) do
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -top)
        end
        P.FinishBody(builder, body, -top - (heights[selectedTabs[spec.key] or defaultTab] or 100))
    end
    tabs:HookScript("OnSizeChanged", LayoutPanels)
    LayoutPanels()
    P.HideControlTitle(tabs)
    if P.M.RegisterControlMetadata then
        P.M.RegisterControlMetadata(tabs, P.Meta(spec.page or PAGE, ID, spec.key .. ".tabs", "action", sectionId), spec.title, "segment")
    end
    return refresh, selectTab, selectItem
end

-- The four DoT actions have control IDs and share a lazily built editor with the color switch.
local dotActionIds
local function IsDotEditorAction(target)
    if target.sectionId ~= PAGE .. "_auraWorkspace" or not target.controlId then return false end
    if not dotActionIds then
        dotActionIds = {}
        for _, action in ipairs({ "action.auraSpec", "action.auraSuggestion", "action.auraCustom", "action.auraSample", "action.flameShock" }) do
            local id = P.Meta(PAGE, ID, action, "action", target.sectionId).controlId
            if id then dotActionIds[id] = true end
        end
    end
    return dotActionIds[target.controlId]
end

-- Fonts-owned settings route to the host. Suite settings select their tab
-- before the host looks up widgets that may not exist on a cold page.
local function PrepareSearch(page, target)
    if page ~= PAGE or not target then return end
    local fonts = P.NameplateFonts
    local destination, focus, route = fonts.TargetForSetting(target.settingKey)
    if destination then return destination, focus, route end
    local key = (target.settingKey or ""):match("^msufsuite%.nameplates%.(.+)$")
    if not key and IsDotEditorAction(target) then key = "auraColorsEnabled" end
    local rule = key and P.catalog[ID].rules[key]
    if rule then
        local _, side = P.NameplateSearchTarget(rule)
        if side and P.NameplatesWorkspace.Kind() ~= side
            and (rule.section == "plateHighlightPatterns" or P.NameplatesWorkspace.NameOptionScope(key)
                or P.NameplatesWorkspace.Side() ~= side) then
            P.NameplatesWorkspace.Open(side)
        end
    end
    local placement = key and PlacedSections()[key]
    if not placement then return end
    local entry = P.M.cache and P.M.cache[PAGE]
    if entry and entry.sections then RevealSection(entry.sections[placement.section]) end
    local spec, tab = placement.spec, placement.tab
    if not spec or not (spec.prepare or tab or rule and rule.color and HasColorAction(spec)) then return end
    if P.Combat() then return false end
    if spec.prepare then return spec.prepare(key) end
    tab = tab or spec.tabs[1].id
    selectedTabs[spec.key] = tab
    if spec.revealStatus then spec.revealStatus(key) end
    local item = spec.statusSettings and spec.statusSettings[key]
    local colorControl = HasColorAction(spec) and spec.key .. ".colors"
        or item and rule and rule.section == "plateExtraText" and item .. ".colors"
    if rule and rule.color and colorControl and P.W.SegmentTabs then
        local scope = next(spec.scopes)
        if not spec.scopes[P.NameplatesWorkspace.Kind()] then P.NameplatesWorkspace.Open(scope) end
        if spec.select then spec.select(tab, item) end
        local focus = {}
        for field, value in pairs(target) do focus[field] = value end
        focus.controlId = P.Meta(PAGE, ID, colorControl, "action", placement.section).controlId
        return page, focus, { accordion = { [page .. ":" .. placement.section] = true } }
    end
    if spec.select then spec.select(tab, item) end
end
P.Suite.HostBridge.RegisterSearchTargetResolver(P.M, "MSUF_Suite.NameplatesTabs", PrepareSearch)

-- Tabs build on first open, including when selected by search or preview.
local function TabRules(spec)
    local all = Rules(spec.colors)
    local reset = spec.sharedColors and {} or Rules(spec.colors)
    for _, tab in ipairs(spec.tabs) do
        tab.rules = Rules(tab.keys)
        if tab.colors then
            tab.colorRules = Rules(tab.colors)
            for _, rule in ipairs(tab.colorRules) do
                if not tab.shared then reset[#reset + 1] = rule end
            end
        end
        for _, rule in ipairs(tab.rules) do
            all[#all + 1] = rule
            if (not tab.shared or rule.section == "plateHighlightPatterns") and rule.key ~= "look"
                and rule.key ~= spec.sharedGate and not (spec.sharedSettings and spec.sharedSettings[rule.key]) then
                reset[#reset + 1] = rule
            end
        end
    end
    return all, reset
end

local function FlatTabbedSection(ctx, builder, spec, sectionId, all, resetRules, headerSwitch)
    local displayRules = all
    for _, tab in ipairs(spec.tabs) do
        for _, rule in ipairs(tab.colorRules or {}) do displayRules[#displayRules + 1] = rule end
    end
    if spec.sharedSwitch and not headerSwitch then
        displayRules = { P.catalog[ID].rules[spec.switch], unpack(all) }
    end
    local spellRule
    if spec.spellPicker then
        displayRules = { unpack(displayRules) }
        for i, rule in ipairs(displayRules) do
            if rule.key == spec.spellPicker then spellRule = table.remove(displayRules, i) break end
        end
    end
    local function Extra(body, y, width)
        if spellRule then y = P.NameplatesExtensions.RangeSpell(ctx, body, y, width, sectionId, spellRule) end
        if spec.kick then y = spec.kick(ctx)(body, y, width, sectionId) end
        for _, tab in ipairs(spec.tabs) do
            if tab.before then y = tab.before(ctx, body, y, width, sectionId) end
            if tab.extra then y = tab.extra(ctx, body, y, width, sectionId) end
        end
        if spec.textCards then
            local colorLink = P.NameplateFonts.AttachColorLink(body, sectionId, spec.key, nil, y)
            local availableWidth = width - (colorLink and 44 or 0)
            local bottom = P.NameplatesSectionsLayout.TextShortcuts(ctx, body, y, availableWidth, sectionId)
            y = colorLink and math.min(bottom, y - 26) or bottom
        end
        return y
    end
    local reset = PositionKeys(spec)
    if spec.switch and not spec.sharedSwitch then reset[#reset + 1] = spec.switch end
    local body = P.RuleSection(ctx, builder, spec.page or PAGE, ID, sectionId, Tr(spec.title), displayRules,
        { help = HELP[spec.help or spec.tabs[1].help], open = spec.open, resetKeys = reset, resetRules = resetRules, extra = Extra,
          head = P.NameplatesSectionsLayout.Header(ctx, spec, sectionId) })
    spec.select = function() return body end
    return body
end

local function TabbedSection(ctx, builder, spec)
    local page = spec.page or PAGE
    local pageEntry = P.M.cache and P.M.cache[page]
    local sectionId = page .. "_" .. spec.key
    local all, resetRules = TabRules(spec)
    local headerSwitch = P.W.SectionSwitch
    if spec.switch and not headerSwitch then
        local rule = P.catalog[ID].rules[spec.switch]
        if rule then
            if not spec.sharedSwitch then all[#all + 1] = rule end
            table.insert(spec.tabs[1].rules, 1, rule)
        end
    end
    if type(P.W.SegmentTabs) ~= "function" then
        return FlatTabbedSection(ctx, builder, spec, sectionId, all, resetRules, headerSwitch)
    end
    local refresh, selectTab, selectItem
    return P.LazySection(builder, sectionId, Tr(spec.title), spec.open, {
        head = P.NameplatesSectionsLayout.Header(ctx, spec, sectionId),
        content = function(body)
            refresh, selectTab, selectItem = Tabs(ctx, builder, body, spec, sectionId)
            if spec.statusItems then spec.refreshStatusScope = selectItem end
            if not spec.castCards and not HasColorAction(spec) then
                P.AttachRuleColors(body, Tr(spec.title), ID, spec.statusItems and Rules(spec.colors) or all)
            end
        end,
        shell = function(body)
            spec.refreshStatusScope = nil
            spec.select = function(tab, item)
                if P.M.cache and P.M.cache[page] ~= pageEntry then return end
                if P.Combat() then return body end
                if tab then selectedTabs[spec.key] = tab end
                local entry = HM.GetSectionEntry(body)
                local reveal = entry and HM.GetSectionEnsureVisible(entry)
                if reveal then reveal() end
                if entry and entry.SetOpenImmediate and not entry.open then entry.SetOpenImmediate(true) end
                if not selectTab then P.EnsureSectionContent(body) end
                if selectTab and tab then selectTab(tab) end
                if selectItem and (item or tab == "basic") then selectItem(item) end
                return body
            end
            local keys = PositionKeys(spec)
            if spec.switch and not spec.sharedSwitch then keys[#keys + 1] = spec.switch end
            if #resetRules > 0 or #keys > 0 then
                local fontsOwnColors = spec.textCards and P.NameplatesHostOptions.registered
                local colors = not fontsOwnColors and not HasStyleColorsLink(spec)
                    and HasColorAction(spec) and SectionColors(spec)
                local more = P.AttachSectionReset(ctx, body, Tr(spec.title), function()
                    local rules = spec.textCards and P.NameplatesWorkspace.ActiveNameRules(resetRules) or resetRules
                    return P.ResetRules(ID, rules, nil, keys)
                end, nil, colors)
                if colors and more and P.M.RegisterControlMetadata then
                    local meta = P.Meta(page, ID, spec.key .. ".colors", "action", sectionId)
                    P.M.RegisterControlMetadata(more, meta, "Colors", "button")
                end
            end
        end,
        finish = function() refresh() end,
    })
end

P.NameplateStyleSections = {
    sections = SECTIONS, ensure = EnsureSections, build = TabbedSection, rules = TabRules, positionKeys = PositionKeys,
}

-- MSUF owns the interrupt-ready indicator on these castbars: its switch and
-- its look are MSUF's (Castbars > Interrupt Ready Indicator), drawn here by
-- MSUF_Suite_Nameplates/KickReady.lua. Shown where the host has the engine.
-- Every host with the engine has Menu2's exact setting jump.
local KICK_SWITCH = "general.kickReadyShowNameplates"
local KICK_HELP =
    "Customize nameplate interrupt readiness in this area. MSUF castbar settings provide the inherited appearance."
local function KickReadyLink(ctx)
    return function(body, y, width, section)
        local textures = P.NameplateBarTextures
        if textures then y = textures.Link(ctx, body, y, width, section, true) end
        P.Button(ctx, body, "Open shared castbar settings", 16, y, math.min(width, 360), function()
            P.Suite.HostBridge.OpenExactMenuSetting(P.M, "opt_castbar", "castbar_behavior", "general.castbarInterruptShake")
        end, nil, P.Meta(PAGE, ID, "action.sharedCastbars", "action", section))
        y = y - 40
        if section ~= PAGE .. "_castbar" or not P.Suite.HostBridge.KickReady() then return y end
        local button = P.Button(ctx, body, "Open interrupt settings", 16, y, math.min(width, 220), function()
            P.Suite.HostBridge.OpenExactMenuSetting(P.M, "opt_castbar", "castbar_interrupt_ready", KICK_SWITCH)
        end, nil, P.Meta(PAGE, ID, "action.kickReady", "action", PAGE .. "_castbar"))
        if P.M.AddTooltip then P.M.AddTooltip(button, Tr("Open interrupt settings"), Tr(KICK_HELP), { hook = true }) end
        return y - 40
    end
end

-- An accordion of one key list or one catalog section.
local function PlainSection(ctx, builder, spec, rules)
    if not rules then
        rules = spec.keys and Rules(spec.keys) or spec.catalog and VisibleRules(P.SectionRules(ID, spec.catalog)) or {}
        for i = #rules, 1, -1 do
            if rules[i].key == spec.switch and spec.switch ~= "friendlyNPCs" then table.remove(rules, i) end
        end
        if spec.switch and not P.W.SectionSwitch and spec.switch ~= "friendlyNPCs" then
            table.insert(rules, 1, P.catalog[ID].rules[spec.switch])
        end
    end
    local colorRules, fonts = Rules(spec.colors), P.NameplateFonts
    if fonts then
        for index = #colorRules, 1, -1 do
            if fonts.TargetForSetting("msufsuite.nameplates." .. colorRules[index].key) then table.remove(colorRules, index) end
        end
    end
    if #rules == 0 and #colorRules == 0 and not spec.extra then return nil end
    local sectionId, reset = PAGE .. "_" .. spec.key, PositionKeys(spec)
    if spec.switch then reset[#reset + 1] = spec.switch end
    if not spec.sharedColors then
        for _, rule in ipairs(colorRules) do reset[#reset + 1] = rule.key end
    end
    local title = spec.title or (rules[1] or colorRules[1]).sectionTitle
    return P.RuleSection(ctx, builder, PAGE, ID, sectionId, Tr(title), rules,
        { help = not spec.grid and HELP[spec.help or spec.key], open = spec.open, resetKeys = reset, colors = spec.colors and colorRules,
          columns = spec.columns and (builder.width or 720) >= 882 and spec.columns or nil,
          grid = spec.grid and function(body, y, width) return spec.grid(ctx, body, y, width, sectionId, rules) end,
          head = P.NameplatesSectionsLayout.Header(ctx, spec, sectionId),
          extra = function(body, y, width)
              if spec.extra then y = spec.extra(ctx, body, y, width, PAGE .. "_" .. spec.key) end
              return y
          end })
end

-- Older preview entry points use the same sections as the new workspace.
function P.SelectNameplatesEnemyTab(tab)
    if tab == "text" then
        local page = P.M.cache and P.M.cache[PAGE]
        local body = page and page.sections and page.sections[PAGE .. "_enemyText"]
        RevealSection(body)
        return body
    end
    local markers = tab == "elements" or tab == "markers" or tab == "target"
    local scope = P.NameplatesWorkspace.Kind() == "neutral" and "neutral" or "enemy"
    local section = scope .. (markers and "Markers" or "Style")
    for _, spec in ipairs(SECTIONS) do
        if spec.key == section and spec.select then
            return spec.select(markers and "basic" or "frame", markers and (tab == "target" and "target" or "raid") or nil)
        end
    end
end

local function StatusSection(scope)
    for _, spec in ipairs(SECTIONS) do
        if spec.statusItems and spec.plateScope == scope and spec.select then return spec end
    end
end

local function FocusStatus(spec, item)
    local body = spec.select("basic", item)
    if body and P.W.FocusCollapsibleSection then
        P.W.FocusCollapsibleSection(body, { persist = true, flash = true })
    end
    return body
end

function P.OpenNameplateStatusSection(side, item, scope)
    if P.Combat() then return end
    local spec = StatusSection(scope or P.NameplatesWorkspace.Kind())
    if spec and spec.positionSide == side then return FocusStatus(spec, item) end
end

function P.OpenNameplateCastDetail(side, tab)
    local section = side == "friendly" and "friendlyCast" or "castbar"
    for _, spec in ipairs(SECTIONS) do
        if spec.key == section and spec.select then
            local body = spec.select(tab)
            if body and P.W.FocusCollapsibleSection then
                P.W.FocusCollapsibleSection(body, { persist = true, flash = true })
            end
            return body
        end
    end
end

function P.NameplateStatusTarget(side, key, scope)
    local spec = StatusSection(scope or P.NameplatesWorkspace.Kind())
    if not spec or spec.positionSide ~= side then return end
    local item = spec.statusSettings[key]
    if item then return spec, item end
    -- Friendly target arrows use the same settings as enemy target arrows.
    if side == "friendly" and key and key:match("^enemyTarget") then
        spec = StatusSection("enemy")
        if spec and spec.statusSettings[key] == "target" then return spec, "target" end
    end
end

function P.OpenNameplateStatusItem(side, key, scope)
    if P.Combat() then return end
    local spec, item = P.NameplateStatusTarget(side, key, scope)
    if spec then return FocusStatus(spec, item) end
end

local function Build(ctx)
    EnsureSections()
    local builder = P.W.PageBuilder(ctx)
    local sections = {}
    local Workspace = P.NameplatesWorkspace
    local ui = Workspace.Header(ctx, builder)
    local preview = P.BuildNameplatesPreview(ctx, builder, sections)
    if preview and ctx.entry then
        HM.SetMissingSectionResolver(ctx.entry, function(sectionId)
            if P.Combat() then return end
            local scope = sectionId:match("^suite_nameplates_preview_(%a+)$")
            if scope then
                if scope ~= "current" and Workspace.Side() ~= scope then Workspace.Open(scope) end
                preview:Edit("anchor")
                return preview.body
            end
            local key = sectionId:match("^suite_nameplates_status_offset_(.+)$")
            local placement = key and PlacedSections()[key]
            if not placement or not placement.offset then return end
            Workspace.Open(placement.spec.plateScope)
            local offset = placement.offset
            return preview:FocusStatusOffset(key, offset.element, offset.sample)
        end)
    end
    for _, spec in ipairs(SECTIONS) do
        if spec.key == "castbar" or spec.key == "friendlyCast" then spec.kick = KickReadyLink end
        if spec.build then
            sections[spec.key] = spec.build(ctx, builder, spec)
        elseif spec.tabs then
            sections[spec.key] = TabbedSection(ctx, builder, spec)
        else
            sections[spec.key] = PlainSection(ctx, builder, spec)
        end
        Workspace.Track(ui, sections[spec.key], spec.scopes)
        if ui and spec.statusItems then
            ui.statusSections = ui.statusSections or {}
            ui.statusSections[spec.plateScope] = spec
        end
    end
    local more = PlainSection(ctx, builder, { key = "more", title = "More settings" }, Unplaced())
    if more then Workspace.Track(ui, more, { enemy = 200 }) end
    Workspace.Finish(ui)
end

P.RegisterPage({ key = PAGE, label = "Nameplates", title = "Nameplates", build = Build, icon = { 7, 0 },
    nav = "combat", navOrder = 1,
    aliases = { "nameplate", "plates", "enemynameplates", "friendlynameplates" } })
