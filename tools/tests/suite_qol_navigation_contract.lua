-- Cold QoL navigation creates only the selected category, and exact routes
-- reveal filtered rows without changing any feature settings.
local root = assert(arg[1], "repository root required")
SUITE_OPTIONS_FIXTURE = true
local F = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
SUITE_OPTIONS_FIXTURE = nil
local P, M, V = F.optionsNS, F.M, F.optionsNS.QoLView
local reflowDropdown = {}
local bindDropdownAt = M.BindDropdownAt
M.BindDropdownAt = function(ctx, parent, label, x, y, values, width, get, set, meta)
    local control = bindDropdownAt(ctx, parent, label, x, y, values, width, get, set, meta)
    control:SetSize(width, 22)
    -- Menu2 restores each registered dropdown's original MoveWidget anchor.
    reflowDropdown[control] = function()
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 24)
    end
    return control
end
local active
M.RequestRefresh = function()
    if active then for _, refresh in ipairs(active.refreshers) do refresh() end end
end
local function Count(values)
    local count = 0
    for _ in pairs(values) do count = count + 1 end
    return count
end
local function Build(width, gameplay)
    local page = gameplay and "gameplay" or "suite_qualityOfLife"
    local ctx = { key = page, width = width, refreshers = {}, widgets = {}, sections = {}, pageItems = {},
        entry = { sections = {} } }
    F.SetCurrent(ctx)
    active = ctx
    if gameplay then V.BuildGameplay(ctx, F.W.PageBuilder(ctx)) else M.pages[page].build(ctx) end
    M.RequestRefresh()
    return ctx, assert(ctx.entry.qualityOfLifeView)
end
local function CheckFilterPlacement(ui)
    local control = ui.filterControl
    reflowDropdown[control]()
    local point = control.points[1]
    local left, top = point[4], point[5]
    local parent = point[2]
    if parent ~= ui.body then
        local anchor = parent.points[1]
        assert(anchor[1] == "TOPRIGHT" and anchor[2] == ui.body and anchor[3] == "TOPRIGHT")
        left = left + ui.width + anchor[4] - parent:GetWidth()
        top = top + anchor[5]
    end
    local metrics = ui.selector:GetLayoutMetrics()
    if ui.inlineFilter then
        assert(left >= (metrics.maxRight or ui.width - 190), "reflow put the filter over the category tabs")
    else
        assert(top <= metrics.bottomY - 8, "reflow put the filter over the category tabs")
    end
    assert(left + control:GetWidth() == ui.width - 8, "reflow moved the filter away from the right edge")
    assert(top - control:GetHeight() > -ui.top, "filter extends into the feature rows")
end
local expected = { "character", "lootMerchants", "questsProfessions", "groups", "travel", "interface" }
V.GetCategories()
for index, id in ipairs(expected) do assert(P.QualityOfLifeCategories[index].id == id, "fixed category order drift") end
assert(#P.QualityOfLifeCategories == #expected)
assert(#V.GetCategories() == 7, "old hosts must keep all gameplay helpers reachable")
local ctx, ui = Build(1200)
assert(Count(ui.panels) == 1, "hidden QoL categories created widgets")
assert(ui.selector.kind == "ScopeOverrideBar", "QoL must use the Unitframes group selector")
CheckFilterPlacement(ui)
local initial = Count(ui.rows)
for _, record in pairs(ui.rows) do assert(not record.details, "feature details were built eagerly") end
local selector = ui.selector
M.RequestRefresh()
assert(Count(ui.rows) == initial and ui.selector == selector, "refresh rebuilt the navigation")
assert(ui:SelectCategory("lootMerchants"))
local loot = V.FindFeature("loot", "quickLoot")
local record = assert(ui.rows[V.FeatureSectionId(loot)])
local config = F.S.Config("loot")
config.enabled, config.quickLoot, config.manageHistory = true, true, true
ui:SetFilter("enabled")
record.toggle.set(false)
M.RequestRefresh()
assert(record.row:IsShown(), "changed row vanished underneath its toggle")
assert(config.enabled and not config.quickLoot and config.manageHistory, "one loot toggle changed the sibling feature")
ui:SetFilter("enabled")
assert(not record.row:IsShown(), "explicit filtering retained an unchanged disabled feature")
local resolve = P.HM.GetMissingSectionResolver(ctx.entry)
assert(resolve(V.FeatureSectionId(loot)) and record.row:IsShown(), "search did not reveal the filtered feature")
assert(not config.quickLoot and config.manageHistory, "navigation changed feature settings")
record.reveal(false)
assert(not record.details or not record.details:IsShown(), "settings button did not close inline details")
ui:SetFilter("disabled")
assert(record.row:IsShown(), "disabled filter hid a disabled feature")
assert(resolve("suite_qualityOfLife_category_tooltips") and ui.selected == "interface", "legacy category route failed")
local _, restored = Build(600)
assert(restored.selected == "interface", "last category was not remembered")
assert(restored.selector.kind == "ScopeOverrideBar", "narrow QoL hid groups in a dropdown")
assert(Count(restored.panels) == 1, "restoring a category eagerly built other categories")
assert(#restored.selector.buttons == 7, "not every group has a clickable button")
assert(restored.top > ui.top, "wrapped groups overlap the filter or feature rows")
CheckFilterPlacement(restored)
restored.selector.buttons[2]:GetScript("OnClick")()
assert(restored.selected == "lootMerchants", "group click did not show its own features")
local top = restored.top
restored.selector:GetLayoutMetrics().bottomY = restored.selector:GetLayoutMetrics().bottomY - 30
M.RequestRefresh()
assert(restored.top == top + 30, "refresh forgot the resized selector height")
CheckFilterPlacement(restored)

P.GameplayPage.registered = true
assert(#V.GetCategories() == 6, "new hosts duplicated Gameplay inside QoL")
local gameplayCtx, gameplay = Build(1000, true)
assert(Count(gameplay.rows) == #V.GameplayCategory.features and Count(gameplay.panels) == 1)
for _, group in ipairs(V.GameplayCategory.features) do
    assert(V.GetFeaturePage(group) == "gameplay")
    local row = gameplay.rows[V.FeatureSectionId(group)]
    assert(row and row.toggle.searchMeta.pageKey == "gameplay", "gameplay toggle retained the old page")
end
local tracker = V.FindFeature("actionTracker")
assert(V.RevealFeature(tracker, gameplayCtx.entry), "shared gameplay renderer lost exact search")
assert(gameplay.rows[V.FeatureSectionId(tracker)].details, "gameplay details were not built on demand")
local moves = 0
local function Watch(frame)
    local previous = frame.SetPoint
    frame.SetPoint = function(self, ...) moves = moves + 1; return previous(self, ...) end
end
for _, row in pairs(gameplay.rows) do Watch(row.row) end
for _, heading in pairs(gameplay.panels.gameplay.headings) do Watch(heading.frame) end
M.RequestRefresh()
assert(moves == 0, "unchanged refresh rewrote feature or heading positions")
-- A first Edit Mode/module link must build the destination, not assume it is cached.
local opened = false
local oldOpen, oldBridge, oldCache = F.Suite.Menu.Open, M.SearchBridge, M.cache
M.cache = {}
F.Suite.Menu.Open = function(page)
    assert(page == "gameplay")
    opened = true
    local destination = Build(1000, true)
    M.cache.gameplay = destination.entry
    return true
end
M.SearchBridge = { OpenSearchTarget = function(page, _, _, section)
    assert(page == "gameplay" and section)
    return true, true, true
end }
assert(F.Suite.Menu.FocusQualityOfLifeModule("actionTracker") and opened, "cold module link did not open Gameplay")
F.Suite.Menu.Open, M.SearchBridge, M.cache = oldOpen, oldBridge, oldCache

local _, travel = Build(1000)
assert(travel:SelectCategory("travel"))
local partyMap = V.FindFeature("foreverPartyMap")
local partyRow = travel.rows[V.FeatureSectionId(partyMap)]
if F.Suite.Client.isForever then
    assert(partyRow and partyRow.toggle.get(), "the Forever party map must appear enabled in Map & Travel")
    partyRow.toggle.set(false)
    assert(not F.S.Config("foreverPartyMap").enabled, "the party map must have an independent off switch")
else
    assert(not P.Available("foreverPartyMap") and not partyRow.row:IsShown(),
        "the Forever party map must stay unavailable on Retail")
end
print("PASS QoL fixed categories, lazy rows/details, wrapping clickable groups, filters, state, exact routes and Suite Gameplay")
