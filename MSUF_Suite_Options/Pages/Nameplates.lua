local _, P = ...
local Tr, HM = P.Tr, P.HM
local PAGE, ID = "suite_nameplates", "nameplates"

local HELP = {
    neutralBasics = P.Help("Neutral creatures share Enemy styling. Use Enable to show or hide neutral nameplates.",
        "A neutral creature uses the Enemy rules once it enters combat."),
    friendlyNpcBasics = P.Help("Choose how friendly NPCs appear. Enable separate dimensions to give their health bars a different size.",
        "Friendly NPCs share the Friendly appearance. In instances the game may restrict styling."),
    general = P.Help("Pick a look: Mapko (recommended), Jundies, Blizzard (no skin) or Custom.",
        "Mapko uses Modern plates, Medium size and the same bar dimensions on Retail and Forever. Guild names and titles also affect names in the world. Bind Toggle friendly NPC nameplates under MSUF Suite in Blizzard Key Bindings. Import protection keeps your current nameplates when importing a full Suite profile; explicit nameplate imports still replace them."),
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
    native = P.Help("Set the shared nameplate style, size and player names."),
    visibility = P.Help("Which units get nameplates and how plates share space.",
        "Set visibility for each unit type and how plates share space."),
    distance = P.Help("How far plates show, how they fade and shrink, and how stacked plates sit.",
        "Set the maximum distance, spacing and screen margins here."),
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
          keys = { "nativeStyle", "nativeSize", "targetScaleEnabled", "targetScalePercent", "barGeometry",
                "classColors", "playerTitles" } },
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
        if rule and (not available or available(rule)) then rules[#rules + 1] = rule end
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
        if spec.key == "enemyBasics" then Place({ "look" }, PAGE .. "_enemyBasics", spec, "general") end
    end
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
        local side = spec and spec.statusItems and spec.positionSide
        local textIndicator = spec and spec.statusItems and rule.section == "plateExtraText"
        if textIndicator then side = spec.plateScope end
        local colorTarget = placement.tab == "colors" or textIndicator
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
    local bars = P.NameplateBarTextures.Target(key)
    if bars then
        return P.Suite.HostBridge.OpenExactMenuSetting(P.M, bars.page, bars.section, "msufsuite.nameplates." .. key)
    end
    local sectionId, _, exact = P.NameplateSearchTarget(rule)
    if not sectionId or exact == false then return false end
    local page = P.M.cache and P.M.cache[PAGE]
    RevealSection(page and page.sections and page.sections[sectionId])
    return P.Suite.HostBridge.OpenExactMenuSetting(P.M, PAGE, sectionId, "msufsuite.nameplates." .. key)
end

-- One panel per tab with its rules; a search hit on a rule selects the
-- rule's tab first (the preview's exact setting jump uses the same hook).
local function ColorTab(panel, width, spec, tab, sectionId, y)
    local card = P.W.ControlCard and P.W.ControlCard(panel, Tr("Colors"), nil, 16, y, width, 48)
        or P.T.Panel(panel, nil, P.T.colors.panel2, P.T.colors.borderSoft)
    if not P.W.ControlCard then
        card:SetPoint("TOPLEFT", 16, y)
        card:SetSize(width, 48)
        P.Text(card, "Colors", 16, -14, width - 60)
    end
    local dots = tab.id == "colors" and (spec.styleScope == "enemy" or spec.styleScope == "neutral")
    dots = dots and P.NameplatesAuraUI
    local shortcut = P.AttachRuleColors(card, Tr("Colors"), ID, tab.colorRules, nil, nil,
        dots and dots.ColorTargets, dots and P.Suite.NameplateAuraColors.LIMIT + 2)
    if shortcut and P.M.RegisterControlMetadata then
        local meta = P.Meta(PAGE, ID, spec.key .. ".colors", "action", sectionId)
        P.M.RegisterControlMetadata(shortcut, meta, "Colors", "button")
    end
    return y - 60
end

local TAB_BODY_TOP = 59

local function Panels(ctx, builder, body, width, spec, sectionId)
    local panels, heights, byTab = {}, {}, {}
    local selectItem
    for _, tab in ipairs(spec.tabs) do
        local panel = CreateFrame("Frame", nil, body)
        panel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -TAB_BODY_TOP)
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
                    P.FinishBody(builder, body, -TAB_BODY_TOP - height)
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
        if tab.colorRules then y = ColorTab(panel, width, spec, tab, sectionId, y) end
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
            y, entries = P.RuleGrid(ctx, panel, PAGE, ID, tab.rules, y, width, nil, sectionId)
        end
        for _, entry in ipairs(entries or {}) do
            if entry.widget then HM.SetSearchTargetPrepare(entry.widget, function() spec.select(tab.id) end) end
        end
        if tab.extra then y = tab.extra(ctx, panel, y, width, sectionId, spec) end
        heights[tabId] = -y + 14
        panel:SetHeight(heights[tabId])
    end
    return panels, heights, Ensure, function(key) if selectItem then selectItem(key) end end
end

local function Tabs(ctx, builder, body, spec, sectionId)
    local width = math.max(240, (HM.GetSectionWidth(body) or builder.width or 720) - 32)
    local panels, heights, ensure, selectItem = Panels(ctx, builder, body, width, spec, sectionId)
    local values = {}
    for _, tab in ipairs(spec.tabs) do
        values[#values + 1] = { value = tab.id, text = Tr(tab.label) }
    end
    local defaultTab = spec.tabs[1].id
    local tabs, refresh, _, selectTab = P.W.SegmentTabs(ctx, body, {
        label = "", compact = true, x = 16, y = -12, values = values, frames = panels,
        width = math.min(width, math.max(360, (spec.tabWidth or 120) * #values)),
        defaultTab = defaultTab,
        get = function() return selectedTabs[spec.key] or defaultTab end,
        set = function(tab)
            selectedTabs[spec.key] = tab
            if spec.onTab then spec.onTab(tab) end
        end,
        afterRefresh = function(tab)
            ensure(tab)
            P.FinishBody(builder, body, -TAB_BODY_TOP - (heights[tab] or 100))
        end,
    })
    P.HideControlTitle(tabs)
    if P.M.RegisterControlMetadata then
        P.M.RegisterControlMetadata(tabs, P.Meta(PAGE, ID, spec.key .. ".tabs", "action", sectionId), spec.title, "segment")
    end
    return refresh, selectTab, selectItem
end

-- Fonts-owned settings route to the host. Suite settings select their tab
-- before the host looks up widgets that may not exist on a cold page.
local function PrepareSearch(page, target)
    if page ~= PAGE or not target then return end
    local fonts = P.NameplateFonts
    local destination, focus, route = fonts.TargetForSetting(target.settingKey)
    if destination then return destination, focus, route end
    local key = (target.settingKey or ""):match("^msufsuite%.nameplates%.(.+)$")
    local rule = key and P.catalog[ID].rules[key]
    if rule then
        local _, side = P.NameplateSearchTarget(rule)
        if side and P.NameplatesWorkspace.Side() ~= side then P.NameplatesWorkspace.Open(side) end
    end
    local placement = key and PlacedSections()[key]
    if not placement then return end
    local entry = P.M.cache and P.M.cache[PAGE]
    if entry and entry.sections then RevealSection(entry.sections[placement.section]) end
    local spec, tab = placement.spec, placement.tab
    if not spec or not (spec.prepare or tab) then return end
    if P.Combat() then return false end
    if spec.prepare then return spec.prepare(key) end
    selectedTabs[spec.key] = tab
    if spec.revealStatus then spec.revealStatus(key) end
    local item = spec.statusSettings and spec.statusSettings[key]
    local colorControl = tab == "colors" and spec.key .. ".colors"
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
            if not tab.shared and rule.key ~= spec.sharedGate and not (spec.sharedSettings and spec.sharedSettings[rule.key]) then
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
        if spec.textCards then y = P.NameplatesSectionsLayout.TextShortcuts(ctx, body, y, width, sectionId) end
        return y
    end
    local reset = PositionKeys(spec)
    if spec.switch and not spec.sharedSwitch then reset[#reset + 1] = spec.switch end
    local body = P.RuleSection(ctx, builder, PAGE, ID, sectionId, Tr(spec.title), displayRules,
        { help = HELP[spec.help or spec.tabs[1].help], open = spec.open, resetKeys = reset, resetRules = resetRules, extra = Extra,
          head = P.NameplatesSectionsLayout.Header(ctx, spec, sectionId) })
    spec.select = function() return body end
    return body
end

local function TabbedSection(ctx, builder, spec)
    local pageEntry = P.M.cache and P.M.cache[PAGE]
    local sectionId = PAGE .. "_" .. spec.key
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
            if not spec.castCards then
                P.AttachRuleColors(body, Tr(spec.title), ID, spec.statusItems and Rules(spec.colors) or all)
            end
        end,
        shell = function(body)
            spec.refreshStatusScope = nil
            spec.select = function(tab, item)
                if P.M.cache and P.M.cache[PAGE] ~= pageEntry then return end
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
                P.AttachSectionReset(ctx, body, Tr(spec.title), function() return P.ResetRules(ID, resetRules, nil, keys) end)
            end
        end,
        finish = function() refresh() end,
    })
end

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

function P.OpenNameplateStatusSection(side, item)
    if P.Combat() then return end
    for _, spec in ipairs(SECTIONS) do
        if spec.statusItems and spec.plateScope == P.NameplatesWorkspace.Kind() and spec.positionSide == side and spec.select then
            local body = spec.select("basic", item)
            if body and P.W.FocusCollapsibleSection then
                P.W.FocusCollapsibleSection(body, { persist = true, flash = true })
            end
            return body
        end
    end
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

function P.OpenNameplateStatusItem(side, key)
    if P.Combat() then return end
    local scope = P.NameplatesWorkspace.Kind()
    for _, spec in ipairs(SECTIONS) do
        local item = spec.plateScope == scope and spec.positionSide == side and spec.statusSettings and spec.statusSettings[key]
        if item then return P.OpenNameplateStatusSection(side, item) end
    end
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
