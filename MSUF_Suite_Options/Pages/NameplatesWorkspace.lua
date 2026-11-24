local _, P = ...
local Tr, HM, W = P.Tr, P.HM, P.W
local PAGE, ID = "suite_nameplates", "nameplates"
local LOOK_BLIZZARD = 2
-- The top-level type selector and the ordered sections shown for each type.
local Workspace = {}
P.NameplatesWorkspace = Workspace

local ORDER = { "enemy", "neutral", "friendly", "friendlyNpc" }
local LABELS = { enemy = "Enemy", neutral = "Neutral", friendly = "Friendly",
    friendlyNpc = "Friendly NPC" }
local SIDES = { enemy = "enemy", neutral = "enemy", friendly = "friendly", friendlyNpc = "friendly" }
local X = P.Suite.NameplateExtensions
local PRIMARY_KINDS = { enemy = "enemyNpc", neutral = "neutralNpc", friendly = "friendlyPlayer", friendlyNpc = "friendlyNpc" }
local COPY_CATEGORIES = {
    { key = "dimensions", label = "Health bar dimensions" }, { key = "style", label = "Style" },
    { key = "text", label = "Text" }, { key = "cast", label = "Castbar" },
    { key = "status", label = "Status icons" }, { key = "positions", label = "Position" },
    { key = "visibility", label = "Visibility" }, { key = "opacity", label = "Opacity" },
    { key = "range", label = "Range Check" }, { key = "clicks", label = "Click area" },
}
local current = "enemy"

local nameOptions = {
    enemy = { "enemyCenterName", "enemyPlateNameClassColor", "enemyPlateNameTypeColor", "enemyExtraTextTitle" },
    neutral = { "neutralCenterName", "neutralPlateNameTypeColor", "neutralExtraTextTitle" },
    friendly = { "friendlyCenterName", "friendlyNameClassColor" },
    friendlyNpc = { "friendlyNpcCenterName", "friendlyNpcPlateNameTypeColor", "friendlyNpcExtraTextTitle" },
}
local nameOptionScopes = {}
for scope, keys in pairs(nameOptions) do
    for _, key in ipairs(keys) do nameOptionScopes[key] = scope end
end

function Workspace.NameOptionScope(key) return nameOptionScopes[key] end

function Workspace.ActiveNameRules(rules)
    if not Workspace.ui then return rules end
    local active = {}
    for _, rule in ipairs(rules) do
        local scope = nameOptionScopes[rule.key]
        if not scope or scope == current then active[#active + 1] = rule end
    end
    return active
end

function Workspace.AddNameOptions(keys, scopes)
    for _, scope in ipairs(ORDER) do
        if scopes[scope] then
            for _, key in ipairs(nameOptions[scope]) do keys[#keys + 1] = key end
        end
    end
end

function Workspace.NameOptionRows(ctx, card, top, width, sectionId, byKey, entries)
    local ui = Workspace.ui
    local bottom = top
    for _, scope in ipairs(ORDER) do
        local rules = {}
        for _, key in ipairs(nameOptions[scope]) do
            if byKey[key] then rules[#rules + 1] = byKey[key] end
        end
        if #rules > 0 then
            local rowTop = ui and top or bottom
            local rows = CreateFrame("Frame", nil, card)
            rows:SetPoint("TOPLEFT", card, "TOPLEFT", 0, rowTop)
            local offset, controls = P.RuleGrid(ctx, rows, PAGE, ID, rules, 0, width, nil, sectionId, 1)
            rows:SetSize(width + 32, -offset)
            for _, entry in ipairs(controls) do entries[#entries + 1] = entry end
            if ui then
                ui.nameOptionRows[rows] = scope
                rows:SetShown(current == scope)
            end
            bottom = math.min(bottom, rowTop + offset)
        end
    end
    return bottom
end

function Workspace.Side() return SIDES[current] end
function Workspace.Kind() return current end

local function CopyCategory(rule, field, scope)
    local section = rule.section or ""
    if section == "plateNameOnly" or section == "plateHighlightPatterns" then return "style" end
    local appearance = section:match("StyleOutline$") and "outline" or section:match("StyleTextures$") and "textures"
    if appearance then
        if P.Get(ID, P.Suite.NameplateStyle.AppearanceSwitch(scope, appearance)) then return "style" end
        return
    end
    if section == "plateOpacity" then return "opacity" end
    if section == "plateInteraction" or section == "plateExtras" then
        if field:match("^Range") then return "range" end
        if field:match("^Clickbox") or field == "PlateClickThrough" then return "clicks" end
        return
    end
    if section == "plateExtraText" then return field:match("[XY]$") and "positions" or "status" end
    if scope ~= SIDES[scope] then return end
    if section == "plateStatus" or section == "castbar" or section == "castPresentation" or section == "castExtensions"
        or section == "plateTextDisplay" or section == "nameText" or section == "frameOutline" or section == scope then
        if field:match("Offset[XY]$") then return "positions" end
        if field:match("^Cast") then return "cast" end
        if field:match("^Health[WH].*Delta$") then return end
        if section == "plateStatus" or field:match("^Raid") then return "status" end
        if section == "plateTextDisplay" or section == "nameText" or field:match("^Name") or field:match("^HealthText") then
            return "text"
        end
        return "style"
    end
end

local function CopyRule(values, from, to)
    local spec = P.catalog[ID]
    local source, target = spec.rules[from], spec.rules[to]
    if not (source and target) or source.cvar or target.cvar or source.previewOnly or target.previewOnly
        or not spec.controlAvailable(source) or not spec.controlAvailable(target) then return end
    local value = P.Get(ID, from)
    if type(value) ~= type(target.default) then return end
    if type(value) ~= "boolean" and (source.choices or target.choices) then
        local choice = source.choices and source.choices[value]
        if not choice or not target.choices then return end
        for index, label in ipairs(target.choices) do
            if choice == label then values[to] = index return true end
        end
    elseif type(value) ~= "number" or (not target.min or value >= target.min) and (not target.max or value <= target.max) then
        values[to] = value
        return true
    end
end

local function CopyContext(values, source, target, selected)
    local function CopyKind(from, to)
        for _, field in ipairs(X.ContextFields) do
            if selected[field == "Opacity" and "opacity" or "visibility"] then CopyRule(values, from .. field, to .. field) end
        end
    end
    CopyKind(source == "enemy" and target == "friendly" and "enemyPlayer" or PRIMARY_KINDS[source], PRIMARY_KINDS[target])
    if target == "enemy" then CopyKind(PRIMARY_KINDS[source], "enemyPlayer") end
    if selected.visibility then CopyRule(values, X.ContextKeys[source], X.ContextKeys[target]) end
end

function Workspace.CopyValues(source, target, selected)
    local values, available = {}, {}
    if not SIDES[source] or not SIDES[target] or source == target then return values, available end
    for key, rule in pairs(P.catalog[ID].rules) do
        local field = key:match("^" .. source .. "(%u.+)$")
        local category = field and CopyCategory(rule, field, source)
        local candidate = category and P.catalog[ID].rules[target .. field]
        local section = candidate and candidate.section
        local appearance = section and (section:match("StyleOutline$") or section:match("StyleTextures$"))
        if selected[category] and candidate and (appearance or CopyCategory(candidate, field, target) == category)
            and CopyRule(values, key, candidate.key) then
            available[category] = true
        end
    end
    if target == "neutral" and values.neutralPlateNameOnly ~= nil then values.neutralNameOnlyMode = 1 end
    if source == "neutral" and X.NeutralNameSplit(P.S.Config(ID)) then values[target .. "PlateNameOnly"] = nil end
    CopyContext(values, source, target, selected)
    available.visibility, available.opacity = selected.visibility, selected.opacity
    if selected.dimensions then
        local width, height = X.HealthDimensions(P.S.Config(ID), SIDES[source], PRIMARY_KINDS[source])
        local kind = PRIMARY_KINDS[target]
        local override = target ~= SIDES[target]
        local prefix = override and kind or target
        values[prefix .. "HealthWidthDelta"], values[prefix .. "HealthHeightDelta"] = width, height
        if override then values[kind .. "SizeOverride"] = true end
        available.dimensions = true
    end
    return values, available
end

local function ApplyCopy(source, target, selected)
    if source ~= current or P.Combat() then return false end
    local values = Workspace.CopyValues(source, target, selected)
    for key, value in pairs(values) do
        if P.Get(ID, key) == value then values[key] = nil end
    end
    if not next(values) then
        if P.M.ShowStatusFeedback then P.M.ShowStatusFeedback(Tr("Nothing was copied."), "warning", 2) end
        return false
    end
    return P.SetMany(ID, values)
end

local function AttachCopy(ctx, head, button)
    HM.SkipHistoryCheckpoint(button)
    local selected, all, available, source, target = {}, {}, {}, nil, nil
    for _, category in ipairs(COPY_CATEGORIES) do selected[category.key], all[category.key] = true, true end
    local function SetTarget(key)
        target = key
        local _, supported = Workspace.CopyValues(source, target, all)
        available = supported
    end
    local shared = P.M.UnitSectionsShared
    if not (shared and shared.MakeScopeCopyPopup) then
        button:SetScript("OnClick", function(anchor)
            local from = current
            if P.Combat() then return end
            P.ContextMenu(anchor, function(_, menu)
                for _, scope in ipairs(ORDER) do
                    if scope ~= from then
                        menu:CreateButton(Tr(LABELS[scope]), function()
                            P.Confirm("nameplates.copyAppearance", Tr("Copy appearance and positions to %s?"):format(Tr(LABELS[scope])),
                                function() ApplyCopy(from, scope, selected) end)
                        end)
                    end
                end
            end)
        end)
        return
    end
    local popup = shared.MakeScopeCopyPopup(button, {
        controlDomain = "suite", controlPageKey = ctx.key, controlPath = "nameplates.copy", width = 460,
        targetWidth = 132, categoryWidth = 184, categoryColumnWidth = 215,
        categories = COPY_CATEGORIES, scopes = selected, targets = ORDER,
        sourceKey = function() return source end, sourceLabel = function(key) return Tr(LABELS[key]) end,
        targetLabelText = function(key) return LABELS[key] end, selectedTarget = function() return target end,
        isTargetVisible = function(key, from) return key ~= from end, onTargetClick = SetTarget,
        isCategoryAvailable = function(key) return available[key] == true end,
        runLabel = "Copy Selected", runWidth = 128,
        onRun = function(_, panel)
            if ApplyCopy(source, target, selected) then
                if P.M.ShowStatusFeedback then P.M.ShowStatusFeedback(Tr("Copied to %s"):format(Tr(LABELS[target])), "ok", 1.8) end
                panel:Hide()
            end
        end,
    })
    button:SetScript("OnClick", function(anchor)
        if P.Combat() then return end
        source = current
        if not target or target == source then
            for _, scope in ipairs(ORDER) do if scope ~= source then target = scope break end end
        end
        SetTarget(target)
        popup.Show(anchor)
    end)
    head:HookScript("OnHide", popup.Hide)
    return popup
end

function Workspace.Open(kind)
    if Workspace.ui then return Workspace.Select(Workspace.ui, kind) end
    if LABELS[kind] then current = kind return true end
end

-- Skin settings act only through a nameplate look other than Blizzard, and
-- enemy and friendly ones only while that side is skinned. These keys are
-- Blizzard settings that apply under any look (CVars.lua Names) or only
-- change the preview.
local SKIN_SECTIONS = { enemy = "enemy", roleColors = "enemy", enemyColors = "enemy", friendly = "friendly",
    castbar = true, auras = true, signals = true, auraColors = true, auraDisplay = true, barAbsorbs = true, plateExtras = true,
    plateHighlightPatterns = true }
local ANY_LOOK = { friendlyNamesOnly = true, friendlyNameClassColor = true, friendlyRealm = true,
    enemyPreviewRole = true }
local LOOK_REASON = "Choose a nameplate look other than Blizzard under Look."
local SIDE_REASONS = { enemy = "Skin enemy nameplates", friendly = "Skin friendly nameplates" }

P.Gates[ID] = function(rule, key)
    local skin = SKIN_SECTIONS[rule.section]
    if rule.section == "plateNameOnly" then skin = SIDES[key:match("^(%l%a*)CenterName$")] end
    if rule.section == "highlightBorders" then skin = true end
    if rule.section == "frameOutline" then skin = key:match("^(%l+)") end
    local side, outlineField = key:match("^(%l+)Border([A-Z]%a*)$")
    if (side == "enemy" or side == "friendly") and (outlineField == "Size" or outlineField == "Style" or outlineField == "Color")
        and not P.Suite.NameplateStyle.CustomOutlineEnabled(P.S.Config(ID), side) then
        return false, Tr("Choose %s for \"%s\"."):format(Tr("Custom"), Tr("Frame Outline"))
    end
    if key == "selectionTargetColor" and not P.Get(ID, "highlightTarget")
        or key == "selectionFocusColor" and not P.Get(ID, "highlightFocus") then
        if P.Get(ID, "selectionBorder") ~= 2 then return false, Tr("Unavailable with the current settings.") end
    end
    if key == "highlightAggroColor" and not P.Suite.NameplateStyle.AggroHighlightEnabled(P.S.Config(ID)) then
        return false, Tr("Turn on \"%s\" to change this."):format(Tr("Aggro"))
    end
    if rule.section and rule.section:match("^auraEnemy") then skin = "enemy" end
    if rule.section and rule.section:match("^auraFriendly") then skin = "friendly" end
    if rule.section == "plateTextDisplay" or rule.section == "castPresentation" or rule.section == "plateStatus" then
        skin = key:match("^(enemy)") or "friendly"
    end
    if rule.castWidthMode then
        local side = key:match("^(enemy)") or "friendly"
        if P.Get(ID, side .. "CastWidthMode") ~= rule.castWidthMode then return false, Tr("Select the matching Width mode.") end
    end
    if (key:match("LevelSize$") or key:match("LevelAnchor$")) and not P.Suite.Client.isForever
        and P.Suite.NameplateStyle.ClassicNativePlate(P.Get(ID, "nativeStyle")) then
        return false, Tr("Use a modern nameplate style to change the level number.")
    end
    if key:match("^aura.+IconSkin$") and not P.Suite.HostBridge.IconSkins() then
        return false, Tr("Requires MSUF Icon Skins.")
    end
    if not skin or ANY_LOOK[key] then return true end
    if P.Get(ID, "look") == LOOK_BLIZZARD then return false, Tr(LOOK_REASON) end
    -- Target arrows can also show on friendly plates (enemyTargetHideFriendly).
    if skin ~= true and not P.Get(ID, skin) and not key:find("^enemyTarget") then
        return false, Tr("Turn on \"%s\" to change this."):format(Tr(SIDE_REASONS[skin]))
    end
    return true
end

-- Shows the sections of one area and hides the rest (the host's Class
-- Resources workspace does the same: MSUF_Menu2_ClassPowerWorkspace.lua).
function Workspace.Select(ui, kind, fromFocus)
    if not LABELS[kind] or ui.selecting then return false end
    ui.selecting = true
    local changed = current ~= kind
    current = kind
    for rows, scope in pairs(ui.nameOptionRows) do rows:SetShown(kind == scope) end
    local visible = {}
    for _, record in ipairs(ui.sections) do
        local rank = record.scopes[kind]
        record.entry.outer:SetShown(rank ~= nil)
        if rank then visible[#visible + 1] = record end
    end
    table.sort(visible, function(a, b)
        local ar, br = a.scopes[kind], b.scopes[kind]
        if ar == br then return a.index < b.index end
        return ar < br
    end)
    for i, record in ipairs(visible) do visible[i] = record.entry end
    ui.builder.layoutEntries = visible
    ui.builder:RequestRelayoutCollapsibles()
    if ui.selector then ui.selector:Refresh() end
    if changed and ui.copyPopup then ui.copyPopup.Hide() end
    -- A preview click or search hit keeps the sample it came from.
    local side = SIDES[kind]
    if ui.copy then ui.copy:SetShown(side ~= nil) end
    if side then
        local status = ui.statusSections and ui.statusSections[kind]
        if changed and status and status.refreshStatusScope then status.refreshStatusScope() end
        P.NameplatesAdvancedAuras.SelectSide(side, kind)
        P.ShowNameplatesSample(side, kind)
    end
    if changed and not fromFocus and not ui.building then
        local scroll = P.M.scrollFrame
        if scroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
    end
    ui.selecting = nil
    return true
end

-- Each section belongs to one area; focusing it from search or the preview
-- shows that area first.
function Workspace.Track(ui, body, scopes)
    local entry = body and HM.GetSectionEntry(body)
    if not ui or not entry then return end
    local index = #ui.sections + 1
    ui.sections[index] = { entry = entry, scopes = scopes, index = index }
    HM.SetSectionEnsureVisible(entry, function()
        if scopes[current] then return end
        for _, kind in ipairs(ORDER) do
            if scopes[kind] then Workspace.Select(ui, kind, true) return end
        end
    end)
end

-- Copy To keeps its translated caption whole (German "Kopieren nach" is wider
-- than the English button); the type selector wraps left of it.
local COPY_MIN_WIDTH, COPY_PADDING = 94, 26
local function CopyButtonWidth()
    local probe = Workspace.copyMeasure
    if not probe then
        probe = UIParent:CreateFontString(nil, "OVERLAY")
        probe:Hide()
        Workspace.copyMeasure = probe
    end
    if not (P.T.ApplyMenuFont and P.T.ApplyMenuFont(probe, nil, "card") ~= false and probe:GetFont()) then
        probe:SetFontObject("GameFontHighlightSmall")
    end
    probe:SetText(Tr("Copy To"))
    local measure = probe.GetUnboundedStringWidth or probe.GetStringWidth
    return math.max(COPY_MIN_WIDTH, math.ceil(measure(probe) or 0) + COPY_PADDING)
end

-- The fixed header with the type selector and Copy To. Returns nil on a
-- host without the selector or section filtering: the page then shows every
-- section as before.
function Workspace.Header(ctx, builder)
    if not (W.ScopeOverrideBar and W.MeasureScopeOverrideBar and builder.RequestRelayoutCollapsibles
        and builder.layoutEntries and HM.GetSectionEntry) then return nil end
    local ui = { builder = builder, sections = {}, nameOptionRows = {}, building = true }
    Workspace.ui = ui
    local width = builder.width or ctx.width or 720
    local values = {}
    for _, kind in ipairs(ORDER) do values[#values + 1] = { value = kind, text = Tr(LABELS[kind]) } end
    local copyWidth = CopyButtonWidth()
    local opts = { values = values, width = width, maxRight = width - copyWidth - 24, label = "", labelWidth = 0, startX = 16,
        getValue = function() return current end,
        setValue = function(kind) Workspace.Select(ui, kind) end }
    local metrics = W.MeasureScopeOverrideBar(values, opts)
    local head = builder:Section(Tr("Nameplates"), math.max(56, math.abs(metrics.bottomY) + 14))
    if head.title then head.title:Hide() end
    ui.selector = W.ScopeOverrideBar(ctx, head, opts)
    local theme = P.T
    if theme.Button then
        ui.copy = P.T.Button(head, "Copy To", copyWidth, 24)
        local label = HM.GetControlLabel(ui.copy)
        if label then label:SetWordWrap(false) end
        local measure = label and (label.GetUnboundedStringWidth or label.GetStringWidth)
        if measure and math.ceil(measure(label) or 0) + COPY_PADDING > copyWidth then
            ui.copy:SetWidth(math.ceil(measure(label)) + COPY_PADDING)
        end
        ui.copy:SetPoint("TOPRIGHT", head, "TOPRIGHT", -12, -14)
        ui.copyPopup = AttachCopy(ctx, head, ui.copy)
    end
    if P.M.BindSegment then
        P.M.BindSegment(ctx, ui.selector, opts.getValue, opts.setValue, P.Meta(PAGE, ID, "view.area", "ephemeral"))
    end
    if W.AttachStickyPageHeader then W.AttachStickyPageHeader(head, { ctx = ctx, builder = builder, gap = 8 }) end
    return ui
end

-- After every section exists: show the area chosen last.
function Workspace.Finish(ui)
    if not ui then return end
    Workspace.Select(ui, current)
    ui.building = nil
end
