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
local current = "enemy"

function Workspace.Side() return SIDES[current] end
function Workspace.Kind() return current end

local function CopyAppearance(source, target)
    if P.Combat() then return end
    local catalog, values = P.catalog[ID].rules, {}
    for key, rule in pairs(catalog) do
        if rule.section == source or rule.section == "plateStatus" or rule.section == "plateOpacity"
            or rule.section == "castbar" and source == "enemy" then
            local suffix = key:match("^" .. source .. "(%u.+)$")
            local destination = suffix and catalog[target .. suffix]
            if destination and (destination.section == target or destination.section == "plateStatus"
                or destination.section == "plateOpacity" or destination.section == "castbar") then
                values[destination.key] = P.Get(ID, key)
            end
        end
    end
    P.Confirm("nameplates.copyAppearance", Tr("Copy appearance and positions to %s?"):format(Tr(LABELS[target])), function()
        P.SetMany(ID, values)
    end)
end

local function CopyTo(anchor)
    local source = current
    if (source ~= "enemy" and source ~= "friendly") or P.Combat() then return end
    local target = source == "enemy" and "friendly" or "enemy"
    P.ContextMenu(anchor, function(_, menu)
        menu:CreateButton(Tr(LABELS[target]), function() CopyAppearance(source, target) end)
    end)
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
    castbar = true, auras = true, signals = true, auraColors = true, auraDisplay = true, barAbsorbs = true }
local ANY_LOOK = { friendlyNamesOnly = true, friendlyNameClassColor = true, friendlyRealm = true,
    enemyPreviewRole = true }
local LOOK_REASON = "Choose a nameplate look other than Blizzard under Look."
local SIDE_REASONS = { enemy = "Skin enemy nameplates", friendly = "Skin friendly nameplates" }

P.Gates[ID] = function(rule, key)
    local skin = SKIN_SECTIONS[rule.section]
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
    if ui.copy then ui.copy:SetShown(kind == "enemy" or kind == "friendly") end
    -- A preview click or search hit keeps the sample it came from.
    local side = SIDES[kind]
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

-- The fixed header with the type selector and Copy To. Returns nil on a
-- host without the selector or section filtering: the page then shows every
-- section as before.
function Workspace.Header(ctx, builder)
    if not (W.ScopeOverrideBar and W.MeasureScopeOverrideBar and builder.RequestRelayoutCollapsibles
        and builder.layoutEntries and HM.GetSectionEntry) then return nil end
    local ui = { builder = builder, sections = {}, building = true }
    Workspace.ui = ui
    local width = builder.width or ctx.width or 720
    local values = {}
    for _, kind in ipairs(ORDER) do values[#values + 1] = { value = kind, text = Tr(LABELS[kind]) } end
    local opts = { values = values, width = width, maxRight = width - 118, label = "", labelWidth = 0, startX = 16,
        getValue = function() return current end,
        setValue = function(kind) Workspace.Select(ui, kind) end }
    local metrics = W.MeasureScopeOverrideBar(values, opts)
    local head = builder:Section(Tr("Nameplates"), math.max(56, math.abs(metrics.bottomY) + 14))
    if head.title then head.title:Hide() end
    ui.selector = W.ScopeOverrideBar(ctx, head, opts)
    local theme = P.T
    if theme.Button then
        ui.copy = P.T.Button(head, "Copy To", 94, 24)
        ui.copy:SetPoint("TOPRIGHT", head, "TOPRIGHT", -12, -14)
        ui.copy:SetScript("OnClick", CopyTo)
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
