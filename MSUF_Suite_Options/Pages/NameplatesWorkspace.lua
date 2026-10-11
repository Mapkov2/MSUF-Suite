local _, P = ...
local Tr, HM, W = P.Tr, P.HM, P.W
local PAGE, ID = "suite_nameplates", "nameplates"
local LOOK_BLIZZARD, LOOK_RECOMMENDED = 2, 4
-- The Nameplates page in the Class Resources shape: a fixed header picks one
-- area (General, Enemies, Colors, Friendly, Auras) and only that area's
-- sections show; Quick Setup applies the recommended look in one step.
-- Search hits, preview clicks and section focus switch to the target's area
-- first (each section's ensure-visible hook).
local Workspace = {}
P.NameplatesWorkspace = Workspace

local ORDER = { "general", "enemies", "colors", "friendly", "auras" }
-- The preview sample each area shows (NameplatesEditor.lua ShowSample).
local SAMPLES = { enemies = "enemy", colors = "enemy", friendly = "friendly" }
local LABELS = { general = "General", enemies = "Enemies", colors = "Colors", friendly = "Friendly", auras = "Auras" }
-- The area last chosen this session; the page reopens on it.
local current = "general"

-- Skin settings act only through a nameplate look other than Blizzard, and
-- enemy and friendly ones only while that side is skinned. These keys are
-- Blizzard settings that apply under any look (CVars.lua Names) or only
-- change the preview.
local SKIN_SECTIONS = { enemy = "enemy", roleColors = "enemy", enemyColors = "enemy", friendly = "friendly",
    castbar = true, auras = true, signals = true, personal = true, auraColors = true }
local ANY_LOOK = { friendlyNamesOnly = true, friendlyNameClassColor = true, friendlyRealm = true, enemyPreviewRole = true }
local LOOK_REASON = "Choose a nameplate look other than Blizzard under Look."
local SIDE_REASONS = { enemy = "Skin enemy nameplates", friendly = "Skin friendly nameplates" }

P.Gates[ID] = function(rule, key)
    local skin = SKIN_SECTIONS[rule.section]
    if not skin or ANY_LOOK[key] then return true end
    if P.Get(ID, "look") == LOOK_BLIZZARD then return false, Tr(LOOK_REASON) end
    -- Target arrows can also show on friendly plates (enemyTargetHideFriendly).
    if skin ~= true and not P.Get(ID, skin) and not key:find("^enemyTarget") then
        return false, Tr("Turn on \"%s\" to change this."):format(Tr(SIDE_REASONS[skin]))
    end
    return true
end

-- Quick Setup: the recommended look, both sides skinned, module on.
local function QuickSetup()
    local values = { look = LOOK_RECOMMENDED, enabled = true, enemy = true, friendly = true }
    local look = P.catalog[ID].look
    for key, value in pairs(look and look.presets[LOOK_RECOMMENDED] or {}) do values[key] = value end
    P.SetMany(ID, values)
end

local function QuickSetupButton(ctx, head)
    -- Menu2's creators translate their own labels.
    local button = W.RoleButton and W.RoleButton(head, "Quick Setup", "success", 132, 24)
        or P.T.Button(head, "Quick Setup", 132, 24)
    button:SetPoint("TOPRIGHT", head, "TOPRIGHT", -16, -16)
    button:SetScript("OnClick", function()
        if P.Combat() then return end
        P.Confirm("nameplates.quickSetup",
            Tr("Apply the recommended nameplates? This picks the Mapko look and skins enemy and friendly plates. Undo brings your settings back."),
            QuickSetup)
    end)
    P.M.AddTooltip(button, Tr("Quick Setup"), Tr("Apply the recommended Mapko look to enemy and friendly nameplates in one step."),
        { hook = true })
    if P.M.RegisterControlMetadata then
        P.M.RegisterControlMetadata(button, P.Meta(PAGE, ID, "action.quickSetup", "action", PAGE .. "_header"),
            "Quick Setup", "button")
    end
    P.M.TrackRefresh(ctx, function() button:SetEnabled(not P.Combat()) end)
end

-- Shows the sections of one area and hides the rest (the host's Class
-- Resources workspace does the same: MSUF_Menu2_ClassPowerWorkspace.lua).
function Workspace.Select(ui, kind, fromFocus)
    if not LABELS[kind] or ui.selecting then return false end
    ui.selecting = true
    current = kind
    local visible = {}
    for _, key in ipairs(ORDER) do
        for _, entry in ipairs(ui.entries[key]) do
            entry.outer:SetShown(key == kind)
            if key == kind then visible[#visible + 1] = entry end
        end
    end
    if #visible > 0 then
        ui.builder.layoutEntries = visible
        ui.builder:RequestRelayoutCollapsibles()
    end
    if ui.selector then ui.selector:Refresh() end
    -- A preview click or search hit keeps the sample it came from.
    if not fromFocus and SAMPLES[kind] and P.ShowNameplatesSample then P.ShowNameplatesSample(SAMPLES[kind]) end
    if not fromFocus and not ui.building and visible[1] and not visible[1].open then
        W.FocusCollapsibleSection(visible[1].body, { scroll = false, flash = false })
    end
    ui.selecting = nil
    return true
end

-- Each section belongs to one area; focusing it from search or the preview
-- shows that area first.
function Workspace.Track(ui, body, kind)
    local entry = body and HM.GetSectionEntry(body)
    if not ui or not entry then return end
    local list = ui.entries[kind]
    list[#list + 1] = entry
    HM.SetSectionEnsureVisible(entry, function() Workspace.Select(ui, kind, true) end)
end

-- The fixed header with the area selector and Quick Setup. Returns nil on a
-- host without the selector or section filtering: the page then shows every
-- section as before.
function Workspace.Header(ctx, builder)
    if not (W.ScopeOverrideBar and W.MeasureScopeOverrideBar and builder.RequestRelayoutCollapsibles
        and builder.layoutEntries and HM.GetSectionEntry) then return nil end
    local ui = { builder = builder, entries = {}, building = true }
    for _, kind in ipairs(ORDER) do ui.entries[kind] = {} end
    local width = builder.width or ctx.width or 720
    local values = {}
    for _, kind in ipairs(ORDER) do values[#values + 1] = { value = kind, text = Tr(LABELS[kind]) } end
    local opts = { values = values, width = width, maxRight = width - 164, label = "", labelWidth = 0, startX = 16,
        getValue = function() return current end,
        setValue = function(kind) Workspace.Select(ui, kind) end }
    local metrics = W.MeasureScopeOverrideBar(values, opts)
    local head = builder:Section(Tr("Nameplates"), math.max(56, math.abs(metrics.bottomY) + 14))
    if head.title then head.title:Hide() end
    ui.selector = W.ScopeOverrideBar(ctx, head, opts)
    if P.M.BindSegment then
        P.M.BindSegment(ctx, ui.selector, opts.getValue, opts.setValue, P.Meta(PAGE, ID, "view.area", "ephemeral"))
    end
    QuickSetupButton(ctx, head)
    if W.AttachStickyPageHeader then W.AttachStickyPageHeader(head, { ctx = ctx, builder = builder, gap = 8 }) end
    return ui
end

-- After every section exists: show the area chosen last.
function Workspace.Finish(ui)
    if not ui then return end
    Workspace.Select(ui, current)
    ui.building = nil
end
