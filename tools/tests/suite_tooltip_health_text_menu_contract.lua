local root = assert(arg[1], "Suite root required")
SUITE_OPTIONS_FIXTURE = true
local fixture = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
local options, suite = fixture.optionsNS, fixture.S

local ctx = { key = "suite_tooltips", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {},
    entry = { sections = {} } }
fixture.SetCurrent(ctx)
fixture.M.pages.suite_tooltips.build(ctx)
for _, refresh in ipairs(ctx.refreshers) do refresh() end
local key = "msufsuite.tooltipIDs.idModifier"
local setting = assert(options.ResolveTooltipMenuTarget("suite_tooltips", { settingKey = key }))
local control
for _, widget in ipairs(ctx.widgets) do
    if widget.meta and widget.meta.controlId == setting.controlId then control = widget end
end
assert(control and control.meta.sectionId == options.TooltipBasicsSection, "the shared detail key is missing from Basics")
assert(not suite.Config("tooltipIDs").enabled and control.enabled ~= false, "turning IDs off also locked the shared key")
control.set(2)
assert(suite.Config("tooltipIDs").idModifier == 2, "changing the detail key lost the saved setting identity")
assert(suite.Availability("tooltipIDs") and suite.Availability("itemCounts"), "the client's tooltip details are unavailable")
assert(options.catalog.tooltipVisibility.rules.inCombat.hidden and options.catalog.tooltipVisibility.rules.inInstances.hidden,
    "the Tooltip page offered a separate combat or instance switch")
local search = { searchRows = {} }
options.BuildTooltipSearchRows(search)
local result
for _, row in ipairs(search.searchRows) do
    if row.settingKey == key then result = row end
end
assert(result and result.suiteModuleId == "tooltipIDs" and result.sectionId == options.TooltipBasicsSection,
    "the cold search sent the detail key to Skinning")

local sourceRows = {}
for _, row in ipairs(search.searchRows) do
    if row.sectionId == options.TooltipSourcesSection then sourceRows[row.label] = row end
end
for _, label in ipairs({ "World units", "World objects", "Unit frames", "Other UI elements" }) do
    assert(sourceRows[options.Tr(label)].suiteModuleId == "tooltipDetails", "missing source position search entry")
end
local config = suite.Config("tooltipDetails")
config.enabled, config.anchor = true, 3
local Position = options.TooltipPositionPreview
local tip = { positionSource = "unitFrame" }
assert(Position.Mode(tip) == 3, "the position preview did not inherit the global corner")
config.unitFrameAnchor, config.unitFrameX, config.unitFrameY, config.unitFrameSide = 5, 21, 8, 1
tip.anchorMode, tip.anchorSource = Position.Mode(tip)
assert(tip.anchorMode == 4 and tip.anchorSource.id == "unitFrame", "the position preview used the contents instead of the source")
local function RegionWithPoints(w, h)
    return {
        SetShown = function(self, shown) self.shown = shown end,
        ClearAllPoints = function(self) self.point = nil end,
        SetPoint = function(self, ...) self.point = { ... } end,
        GetWidth = function() return w end,
        GetHeight = function() return h end,
    }
end
tip.stage, tip.frame, tip.positionReference = RegionWithPoints(580, 220), RegionWithPoints(300, 125), RegionWithPoints(24, 16)
Position.Place(tip)
assert(tip.positionReference.shown and tip.frame.point[2] == tip.positionReference and tip.frame.point[3] == "RIGHT",
    "the parent placement preview did not use the selected relative side")
assert(Position.Read(tip) == 21, "the preview read global offsets for a source override")
tip.positionSource = "uiElement"
assert(Position.Mode(tip) == 3, "source override leaked into the next selection")

do
    tip.root = { IsVisible = function() return true end }
    tip.anchorMode, tip.anchorSource = Position.Mode(tip)
    assert(not Position.CanMove(tip) and not Position.Write(tip, 10, 10), "editing an inherited anchor overwrote the shared defaults")
    tip.positionSource = "unitFrame"
    tip.anchorMode, tip.anchorSource = Position.Mode(tip)
    local x, y = Position.Drag(tip, 18, 12)
    assert(x > 21 and y > 8 and Position.Write(tip, x, y), "dragging the relative anchor did not save the offsets")
    assert(config.unitFrameX == x and config.unitFrameY == y and Position.Write(tip, 42, -15), "exact offsets did not use the dragged source")
    assert(config.unitFrameX == 42 and config.unitFrameY == -15, "exact X/Y wrote to a different anchor")

    local host = options.Suite.HostBridge
    local openExact = host.OpenExactMenuSetting
    local section, setting, tab
    tip.ui = { Focus = function() end, select = function(key) tab = key end }
    host.OpenExactMenuSetting = function(_, page, targetSection, targetSetting)
        assert(page == "suite_tooltips")
        section, setting = targetSection, targetSetting
        return true
    end
    assert(Position.Open(tip, { "anchor" }, "unit") and section == options.TooltipSourcesSection
        and setting == "msufsuite.tooltipDetails.unitFrameAnchor", "the anchor opened a different source control")
    config.enabled = false
    assert(Position.Open(tip, { "anchor" }, "unit") and tab == "details"
        and setting == "msufsuite.tooltipDetails.enabled", "a disabled anchor did not open its enable switch")
    config.enabled = true
    assert(Position.Open(tip, { "detailRow", "Threat percentage", "unitThreatPercent" }, "unit")
        and setting == "msufsuite.tooltipDetails.unitThreatPercent", "a preview detail opened the wrong toggle")
    assert(Position.Open(tip, { "rule", "Accent line", "rule" }, "item")
        and setting == "msufsuite.skin.theme.tooltipLayout.rule", "the accent line opened header sizing instead of its switch")
    assert(Position.Open(tip, { "power", "Resource Bar", "unitPower" }, "unit")
        and setting == "msufsuite.skin.theme.tooltipLayout.unitPower", "the resource bar opened a generic section")
    local visibility = suite.Config("tooltipVisibility")
    visibility.enabled = true
    assert(Position.WriteScale(tip, 135) and Position.Scale(tip, true) == 135, "preview scaling did not save the live size")
    assert(Position.Open(tip, { "scale" }, "unit") and setting == "msufsuite.tooltipVisibility.scale", "scale opened the wrong slider")
    visibility.enabled = false
    assert(Position.Open(tip, { "scale" }, "unit") and setting == "msufsuite.tooltipVisibility.enabled", "scale skipped a disabled module switch")
    host.OpenExactMenuSetting = openExact
end

do
    config.target, config.selfTarget, config.unitCombatStatus = true, true, true
    config.unitClassification, config.unitThreatStatus, config.unitThreatPercent = true, true, true
    config.unitTargeters = 3
    local usePanel = options.TooltipPreviewUsesPanel
    options.TooltipPreviewUsesPanel = function() return false end
    local function PreviewText()
        return { SetText = function(self, text) self.text = text end,
            SetTextColor = function(self, r, g, b) self.color = { r, g, b } end }
    end
    local detailPreview = { rows = {}, rowSettings = {} }
    for i = 1, 12 do detailPreview.rows[i] = { PreviewText(), PreviewText() } end
    local enemy = { id = "unit", enemy = true, rows = { { "Level", "56" }, { "", "" }, { "", "" } } }
    local height = options.PaintTooltipPreviewBody(detailPreview, enemy)
    assert(height == 6 * 19 and detailPreview.rows[7][2].text == "!" and detailPreview.rows[7][2].color[1] == 1,
        "the enemy preview clipped or omitted the new status details")
    assert(detailPreview.rows[8][2].text == "100%" and detailPreview.rows[9][1].text == options.Tr("Targeted by"),
        "the enemy preview omitted threat percentage or targeters")
    assert(detailPreview.rowSettings[8] == "unitThreatPercent" and detailPreview.rowSettings[9] == "unitTargeters",
        "the enemy preview rows did not retain their actual setting keys")
    detailPreview.restricted = true
    height = options.PaintTooltipPreviewBody(detailPreview, enemy)
    assert(height == 5 * 19 and detailPreview.rows[8][2].text == "100%" and detailPreview.rows[9][1].text == "",
        "restricted preview lost displayable threat or retained an unavailable targeter count")
    assert(not detailPreview.rowSettings[9], "a hidden row kept the old navigation target")
    options.TooltipPreviewUsesPanel = usePanel
end

do
    local client = fixture.Suite.Client
    local oldTooltips = fixture.Suite.Tooltips
    local function Noop() end
    local layout = fixture.Suite.TooltipAppearance.defaults.tooltipLayout
    fixture.Suite.Tooltips = {
        TooltipPalette = { choices = {}, IsActive = function() return false end, Title = function() return 1, 1, 1 end },
        Surface = { Attach = Noop, SetVisible = Noop }, Registry = { AddListener = Noop },
        ItemTooltipCard = {
            Create = function(parent)
                local frame = CreateFrame("Frame", nil, parent)
                return { frame = frame, title = frame:CreateFontString(), meta = frame:CreateFontString(),
                    icon = frame:CreateTexture(), rule = frame:CreateTexture() }
            end,
            CreateOutline = function(parent)
                local frame = CreateFrame("Frame", nil, parent)
                return { frame = frame, edges = { frame:CreateTexture() } }
            end,
            Setting = function(field) return layout[field] end, Range = function() return 1, 100 end,
            TypeStyle = function() return "suite" end, TypeStyleChoice = function() return "inherit" end,
            PresetChoice = function() return "compact" end, MatchesLootSurface = function() return false end,
        },
    }
    local ctx = { key = "suite_tooltips", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {}, entry = { sections = {} } }
    fixture.SetCurrent(ctx)
    config.enabled, config.anchor, config.unitThreatPercent = true, 1, false
    fixture.M.pages.suite_tooltips.build(ctx)
    local ui = assert(ctx.suiteWorkspace)
    local section = assert(ctx.qualityOfLifeFeatureRows.suite_qualityOfLife_tooltipDetails_tooltip_details)
    ui.select("details")
    fixture.W.EnsureSectionContent(section.body)
    local controls = {}
    for _, widget in ipairs(ctx.widgets) do
        local key = widget.meta and (widget.meta.settingKey or ""):match("^msufsuite%.tooltipDetails%.(.+)$")
        if key then controls[key] = widget end
    end
    local preview = assert(ui.tooltipPreview)
    local function HasRow(key)
        for _, setting in pairs(preview.rowSettings) do
            if setting == key then return true end
        end
    end
    assert(preview.selected == 1, "opening Tooltip details silently changed the preview sample")
    controls.unitThreatPercent.set(true)
    assert(preview.selected == 6 and preview.sampleSelector.value == 6 and HasRow("unitThreatPercent"),
        "enabling threat percentage did not switch and repaint the enemy preview")
    preview.sampleSelector.set(2)
    controls.unitThreatPercent.set(false)
    assert(preview.selected == 6 and not HasRow("unitThreatPercent"), "disabling threat percentage did not show the change")
    preview.sampleSelector.set(2)
    for _, refresh in ipairs(ctx.refreshers) do refresh() end
    controls.unitThreatPercent.set(false)
    assert(preview.selected == 2, "refresh or an unchanged value switched the preview")
    local write = options.Set
    options.Set = function() return false end
    controls.unitThreatPercent.set(true)
    options.Set = write
    assert(preview.selected == 2, "a rejected write switched the preview")
    preview.stateSelector.set("restricted")
    controls.unitThreatPercent.set(true)
    assert(preview.restricted and HasRow("unitThreatPercent"), "an available combat detail reset the scenario")
    controls.unitTargeters.set(2)
    assert(not preview.restricted and HasRow("unitTargeters"), "a targeter count did not select a usable preview")
    local host = options.Suite.HostBridge
    local api = host.UnitFrameTooltipAPI
    host.UnitFrameTooltipAPI = function() return { GetUnitFrameTooltipSetting = function() return "MSUF" end } end
    config.unitCombatStatus = false
    preview.sampleSelector.set(3)
    assert(preview.usesPanel, "manual unit preview ignored the configured provider")
    controls.unitIdentityIcons.set(true)
    assert(not preview.usesPanel and HasRow("unitIdentityIcons"), "editing native details selected the custom unitframe panel")
    host.UnitFrameTooltipAPI = api
    if client.modernEquipment then
        controls.hideFaction.set(true)
        assert(preview.rows[2][1]:GetText() == "", "the preview did not hide the native faction line")
        controls.hideFaction.set(false)
        assert(preview.rows[2][1]:GetText() == options.Tr("Alliance"), "the native faction line did not return")
        controls.maxStack.set(false)
        assert(preview.selected == 7 and not HasRow("maxStack"), "disabling stack size did not select the stackable item")
        controls.maxStack.set(true)
        assert(HasRow("maxStack"), "the selected item cannot demonstrate stack size")
        controls.ownedMount.set(false)
        assert(preview.selected == 8 and not HasRow("ownedMount"), "mount collection switched to a non-mount sample")
        controls.ownedMount.set(true)
        assert(HasRow("ownedMount"), "the mount example did not show collection status")
        controls.unitMount.set(false)
        assert(preview.selected == 9 and not HasRow("unitMount"), "unit mount did not switch to the rider sample")
        controls.unitMount.set(true)
        assert(HasRow("unitMount"), "the rider example did not show the mount")
        preview.sampleSelector.set(2)
        controls.iconID.set(true)
        assert(preview.selected == 2 and HasRow("iconID"), "the spell preview was replaced by an item for a spell icon ID")
    end
    fixture.Suite.Tooltips = oldTooltips
end

local function Region(visible)
    return { visible = visible, shown = true, IsVisible = function(self) return self.visible end,
        IsShown = function(self) return self.shown end }
end

local text, chip, selector = Region(true), Region(true), Region(true)
chip.key = "healthText"
local preview = {
    handles = { healthText = text },
    layerButtons = { chip },
    sampleSelector = selector,
    card = { Setting = function() return "" end },
}

local opened, title, items, combat
options.Combat = function() return combat == true end
options.AnchoredContextMenu = function(owner, populate)
    opened, items = owner, {}
    populate(owner, {
        CreateTitle = function(_, label) title = label end,
        CreateButton = function(_, label)
            items[label] = true
            return { CreateRadio = function() end }
        end,
    })
end

local function CheckOwner(expected)
    opened = nil
    assert(options.OpenTooltipHealthTextMenu(preview), "Health text menu did not open")
    assert(opened == expected, "Health text menu chose a hidden or unrelated anchor")
    assert(title == options.Tr("Health text") and items[options.Tr("Format")]
        and items[options.Tr("Font")] and items[options.Tr("Font size")], "Health text options were lost")
end

CheckOwner(text)
text.shown, text.visible = false, false
CheckOwner(chip)
text.shown = true
text.visible = false
CheckOwner(chip)
chip.visible = false
CheckOwner(selector)
selector.visible = false
opened = nil
assert(not options.OpenTooltipHealthTextMenu(preview) and opened == nil, "Menu opened without a visible anchor")
selector.visible, combat = true, true
assert(not options.OpenTooltipHealthTextMenu(preview) and opened == nil, "Menu opened in combat")
print("suite tooltip health text menu contract passed")
