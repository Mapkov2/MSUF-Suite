-- Bags audit: the other bag replacements count as conflicts, the bank follows
-- the appearance settings (its panel color) and has a size and an Edit Mode
-- position, and the Categories-only settings are greyed in the other views
-- (the menu only, never the stored value). The bank runs against the client
-- model of suite_bags_harness.lua with the FULL Bags TOC loaded; the greying
-- and the conflicts run on the options page the player clicks.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")

local function equal(actual, expected, why)
    assert(actual == expected, (why or "value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function Near(value, expected) return math.abs(value - expected) < 0.001 end
-- The 8-bit channels a color texture shows.
local function Bytes(r, g, b) return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5) end

---------------------------------------------------------------- the catalog
local _, catalog = Support.CatalogDefaults(root, "bags")
local rules = catalog.SuiteCatalog.bags.rules
local BACKGROUND = catalog.BagsBankBackground
do
    -- The earlier replacements stay; the three missing ones join them.
    local listed = {}
    for _, name in ipairs(catalog.SuiteCatalog.bags.conflicts) do listed[name] = true end
    for _, name in ipairs({ "EllesmereUIBags", "ElvUI", "Bagnon", "BetterBags", "AdiBags", "ArkInventory",
        "Inventorian", "Baganator", "Combuctor", "LiteBag" }) do
        assert(listed[name], name .. " is not a Bags conflict")
    end
    -- Defaults keep today's bank: the dark panel, Blizzard's size and place.
    equal(rules.bankBackground.default, BACKGROUND.DARK, "bankBackground default")
    equal(rules.bankWindowScale.default, 1, "bankWindowScale default")
    equal(rules.bankWindowMoved.default, false, "bankWindowMoved default")
    equal(rules.bankWindowX.default, 0, "bankWindowX default")
    equal(rules.bankWindowY.default, 0, "bankWindowY default")
    local r, g, b = Bytes(0.06, 0.07, 0.08)
    local hex = catalog.BagsBankColor({ bankBackground = BACKGROUND.DARK, backgroundColor = "336699" })
    equal(tonumber(hex:sub(1, 2), 16), r, "dark panel red")
    equal(tonumber(hex:sub(3, 4), 16), g, "dark panel green")
    equal(tonumber(hex:sub(5, 6), 16), b, "dark panel blue")
    equal(catalog.BagsBankColor({ bankBackground = BACKGROUND.MATCH_BAGS, backgroundColor = "336699" }), "336699",
        "Match the bag window follows the bag background color")
    -- The bank window exists on Retail only.
    local _, forever = Support.CatalogDefaults(root, "bags", nil, { isForever = true })
    for _, key in ipairs({ "bankBackground", "bankWindowScale", "bankWindowMoved", "bankWindowX", "bankWindowY" }) do
        assert(not rules[key].hidden, key .. " is hidden on Retail")
        assert(forever.SuiteCatalog.bags.rules[key].hidden, key .. " shows on WoW Forever")
    end
end

---------------------------------------------------------------- the bank panel
-- The color texture the bank panel paints, as 8-bit channels and alpha.
local function PanelColor(W)
    local color = assert(W.P.BankInventory.background.color, "the bank panel has no color")
    local r, g, b = Bytes(color[1], color[2], color[3])
    return r, g, b, color[4]
end
local function OpenBank(config)
    local W = H.New(root, { config = config })
    W.sizes[0], W.sizes[6] = 4, 6
    W.bankTabs[Enum.BankType.Character] = { { ID = 6, name = "Bank tab" } }
    W.Define(10, { name = "Bread", class = 0, maxStack = 20, quality = 1 })
    W.Put(6, 1, 10, 4)
    W.Apply()
    W.OpenBank(Enum.BankType.Character)
    W.Settle()
    return W
end
do
    local W = OpenBank({ bankView = 2 })
    assert(W.P.BankInventory.active, "the organised bank did not open")
    local r, g, b, a = Bytes(0.06, 0.07, 0.08)
    local red, green, blue, alpha = PanelColor(W)
    assert(red == r and green == g and blue == b and alpha == 1, "the default bank panel is not today's dark panel")
    -- Match the bag window: the bag background color, the panel stays opaque
    -- (Blizzard's slots are shown underneath), whatever the bags' opacity.
    W.S.SetMany("bags", { bankBackground = BACKGROUND.MATCH_BAGS, backgroundColor = "336699", backgroundOpacity = 40 })
    W.Settle()
    red, green, blue, alpha = PanelColor(W)
    assert(red == 0x33 and green == 0x66 and blue == 0x99 and alpha == 1,
        "the bank panel does not follow the bag background color")
    -- A look preset changes the bag color: the bank follows it.
    W.S.Set("bags", "backgroundColor", "aa5500")
    W.Settle()
    red, green, blue = PanelColor(W)
    assert(red == 0xaa and green == 0x55 and blue == 0, "the bank panel does not follow a color change")
    W.S.Set("bags", "bankBackground", BACKGROUND.DARK)
    W.Settle()
    red, green, blue, alpha = PanelColor(W)
    assert(red == r and green == g and blue == b and alpha == 1, "the dark panel did not come back")
    -- A panel made after the setting changed paints that setting.
    local fresh = OpenBank({ bankView = 2, bankBackground = BACKGROUND.MATCH_BAGS, backgroundColor = "112233" })
    red, green, blue = PanelColor(fresh)
    assert(red == 0x11 and green == 0x22 and blue == 0x33, "a new bank panel ignores the setting")
end

---------------------------------------------------------------- the bank window
local function Anchor(W)
    local point, relative, relativePoint, x, y = W.BankFrame:GetPoint(1)
    return point, relative, relativePoint, x, y
end
do
    local W = OpenBank({})
    local bank = W.BankFrame
    equal(bank.scale, 1, "the default bank scale")
    local point, relative, _, x, y = Anchor(W)
    assert(point == "TOPLEFT" and relative == W.UIParent and x == 20 and y == -100,
        "the default bank is not where Blizzard puts it")
    W.M:RegisterMovers()
    local mover = assert(W.movers.bank, "the bank has no Edit Mode element")
    assert(mover.xKey == "bankWindowX" and mover.yKey == "bankWindowY" and mover.point == "TOPLEFT"
        and mover.moveValues.bankWindowMoved == true and mover.resetKeys[1] == "bankWindowMoved",
        "the bank element does not write the bank position settings")
    assert(mover.getFrame() == bank and mover.isEnabled(), "the open bank is not an enabled Edit Mode element")
    -- A drag of the unmoved bank starts where Blizzard put it, in the bank's scale.
    local origin = { bankWindowX = 0, bankWindowY = 0 }
    mover.capture(origin)
    assert(Near(origin.bankWindowX, 20) and Near(origin.bankWindowY, -100), "the drag starts away from the bank")

    -- The size: set before the panel pass reads it, so the corner stays put.
    local passes = W.panelPasses
    W.S.Set("bags", "bankWindowScale", 1.25)
    equal(bank.scale, 1.25, "bankWindowScale did not scale the bank")
    assert(W.panelPasses == passes + 1, "an open bank was not anchored again in its new scale")
    point, relative, _, x, y = Anchor(W)
    assert(point == "TOPLEFT" and Near(x, 20 / 1.25) and Near(y, -100 / 1.25), "the scaled bank left its corner")
    origin = {}
    mover.capture(origin)
    assert(Near(origin.bankWindowX, 16) and Near(origin.bankWindowY, -80), "the drag start ignores the bank's scale")
    -- The Edit Mode popup resizes it too.
    local size = assert(mover.extraControls[1], "the bank element has no size control")
    equal(size.get(), 125, "the size control reads the bank scale")
    assert(size.set(110) and Near(bank.scale, 1.1), "the size control did not scale the bank")
    W.S.Set("bags", "bankWindowScale", 1)

    -- The custom position: kept through every later panel pass and every show.
    W.S.SetMany("bags", { bankWindowMoved = true, bankWindowX = 300, bankWindowY = -50 })
    point, relative, _, x, y = Anchor(W)
    assert(point == "TOPLEFT" and relative == W.UIParent and x == 300 and y == -50, "the bank did not move")
    W.Native(function() UpdateUIPanelPositions() end)
    _, _, _, x, y = Anchor(W)
    assert(x == 300 and y == -50, "another panel's pass moved the bank back")
    W.CloseBank()
    W.OpenBank(Enum.BankType.Character)
    W.Settle()
    _, _, _, x, y = Anchor(W)
    assert(x == 300 and y == -50, "the bank opened away from its position")
    -- A pass for another panel leaves a closed bank alone.
    W.CloseBank()
    bank:ClearAllPoints()
    W.Native(function() UpdateUIPanelPositions() end)
    equal(bank:GetNumPoints(), 0, "a pass for another panel anchored the closed bank")
    W.OpenBank(Enum.BankType.Character)
    W.Settle()
    -- Edit Mode lists the bank while it is open.
    local refreshes = 0
    W.S.RefreshOwnedMovers = function(id) if id == "bags" then refreshes = refreshes + 1 end end
    W.CloseBank()
    assert(refreshes > 0 and not mover.isEnabled(), "Edit Mode still lists the closed bank")
    W.OpenBank(Enum.BankType.Character)
    W.Settle()
    assert(mover.isEnabled(), "Edit Mode does not list the open bank")

    -- Reset position: the panel manager's place again.
    W.S.Set("bags", "bankWindowMoved", false)
    _, _, _, x, y = Anchor(W)
    assert(x == 20 and y == -100, "Reset position did not hand the bank back to Blizzard")
    -- Turning the module off hands the size back too.
    W.S.SetMany("bags", { bankWindowScale = 1.4, bankWindowMoved = true, bankWindowX = 5, bankWindowY = -5 })
    equal(bank.scale, 1.4, "the bank scale before the module stops")
    W.OpenBags()
    W.Settle()
    W.config.enabled = false
    W.Apply()
    equal(bank.scale, 1, "disabling Bags kept the bank scale")
    _, _, _, x, y = Anchor(W)
    assert(Near(x, 20) and Near(y, -100), "disabling Bags kept the bank position")
end

---------------------------------------------------------------- WoW Forever
do
    local W = H.New(root, { client = "Forever" })
    W.Apply()
    W.M:RegisterMovers()
    assert(W.NS.Client.isForever and W.P.BankWindow == nil and not (W.movers and W.movers.bank),
        "the Retail bank window must not load on WoW Forever")
end

---------------------------------------------------------------- the preview
-- The bank tab previews the bank panel: its color, always opaque.
do
    local config = { font = "", itemCountSize = 12, inventoryView = 1, bankView = 1, showItemLevel = true,
        showBankItemLevel = true, bankBackground = BACKGROUND.DARK, backgroundColor = "336699",
        backgroundOpacity = 50, accentColor = "ff8800" }
    local painted
    local S = { Config = function() return config end,
        BagsPaintPreviewWindow = function(_, look) painted = { look.backgroundColor, look.backgroundOpacity,
            look.accentColor } end,
        BagsStylePreviewLabel = function() end }
    local methods = {}
    local function Noop() end
    local function Region() return setmetatable({}, { __index = function(_, key) return methods[key] or Noop end }) end
    function methods:CreateTexture() return Region() end
    function methods:GetStringHeight() return 14 end
    local paint
    local P = { S = S, Suite = setmetatable({ ResolveFont = function() end }, { __index = catalog }), Tr = function(text) return text end, SetTranslatedText = Noop,
        StylePreviewFont = Noop, MenuWorkspace = { FitHeader = Noop },
        PreviewCanvas = { Button = function() return Region() end, Text = function() return Region() end, Jump = Noop,
            Runtime = function() return true end, Changed = function() return true end,
            Watch = function(_, fn) paint = fn end },
        catalog = { bags = { rules = rules } } }
    C_Item = { GetItemQualityColor = function() return 1, 1, 1 end }
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/BagsPreview.lua"))("MSUF_Suite_Options", P)
    local ui = { header = Region(), width = 600, selected = "bank", Focus = Noop }
    P.BuildBagsMenuPreview(ui)
    paint()
    assert(painted[1] == "0f1214" and painted[2] == 100 and painted[3] == "ff8800",
        "the bank preview does not show the dark panel")
    config.bankBackground = BACKGROUND.MATCH_BAGS
    paint()
    assert(painted[1] == "336699" and painted[2] == 100, "the bank preview does not follow the bag background color")
    ui.selected = "appearance"
    paint()
    assert(painted[1] == "336699" and painted[2] == 50, "the bag preview must keep the bag opacity")
end

---------------------------------------------------------------- the options page
SUITE_OPTIONS_FIXTURE = true
local F = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
local P, S, Suite = F.optionsNS, F.S, F.Suite
local pageRules = P.catalog.bags.rules
-- The fixture has no combinedBags setting, which keeps Bags unavailable.
C_CVar = { GetCVar = function() return "1" end }
P.ForgetAvailability()

do
    local original = Suite.Client.IsAddOnLoaded
    assert(S.Availability("bags"), "harness: Bags is unavailable without a conflict")
    for _, name in ipairs({ "Baganator", "Combuctor", "LiteBag" }) do
        Suite.Client.IsAddOnLoaded = function(addon) return addon == name or original(addon) end
        local ok, why = S.Availability("bags")
        equal(ok, false, name .. " does not switch Bags off")
        equal(why, "Managed by " .. name, name .. " status")
    end
    Suite.Client.IsAddOnLoaded = original
end

-- The bank window rules are on the page's Bank organisation tab on Retail.
do
    local ctx = { key = "suite_bags", width = 720, refreshers = {}, widgets = {}, sections = {},
        pageItems = {}, entry = { sections = {} } }
    F.SetCurrent(ctx)
    F.M.pages.suite_bags.build(ctx)
    local found = false
    for _, section in ipairs(ctx.sections) do
        if section.sectionId == "suite_bags_bankWindow" then found = true end
    end
    equal(found, not Suite.Client.isForever, "the Bank window section follows the client")
end

------------------------------------------------ greyed outside the Categories view
do
    local VIEW, BANK_VIEW = Suite.BagsView, Suite.BagsBankView
    local config = S.Config("bags")
    config.enabled = true
    local function Usable(key) return P.RuleEnabled("bags", pageRules[key]) end
    local function Reason(key)
        local ok, why = P.RuleEnabled("bags", pageRules[key], nil, true)
        equal(ok, false, key .. " is not greyed")
        return why
    end
    -- Every Categories-only setting: the built-in categories (the optional ones
    -- too, whatever a later package adds to that section) and the grouping.
    local shared, bagsOnly = { "groupEquipmentSets", "hideEmptyCategories" },
        { "groupEquipmentSlots", "groupExpansions", "groupReagentTypes" }
    for _, rule in ipairs(P.SectionRules("bags", "categories")) do shared[#shared + 1] = rule.key end
    for _, key in ipairs({ "category_professionGear", "category_collectibles", "category_containers" }) do
        local listed = false
        for _, name in ipairs(shared) do listed = listed or name == key end
        assert(listed, key .. " is not in the categories section")
    end
    local always = { "sortMode", "compactGroups", "hideEmptySlots", "mergeStacks", "showFreeSlots",
        "showUpgradeMarker", "inventoryColumns", "showEquipmentSetNames", "bankBackground", "bankWindowScale" }

    local function Check(view, bankView, expectShared, expectBagsOnly, label)
        config.inventoryView, config.bankView = view, bankView
        local stored = {}
        for _, key in ipairs(shared) do stored[key] = P.Get("bags", key) end
        for _, key in ipairs(shared) do
            equal(Usable(key), expectShared, label .. ": " .. key)
            equal(P.Get("bags", key), stored[key], key .. " lost its value")
        end
        for _, key in ipairs(bagsOnly) do equal(Usable(key), expectBagsOnly, label .. ": " .. key) end
        for _, key in ipairs(always) do assert(Usable(key), label .. ": " .. key .. " is greyed") end
        for _, key in ipairs({ "bankGroupExpansions", "bankGroupEquipmentSlots", "bankGroupReagentTypes" }) do
            equal(Usable(key), bankView == BANK_VIEW.CATEGORIES, label .. ": " .. key)
        end
    end
    -- The bags' Categories view turns everything on.
    Check(VIEW.CATEGORIES, BANK_VIEW.TABS, true, true, "Categories")
    Check(VIEW.CATEGORIES, BANK_VIEW.CATEGORIES, true, true, "Categories and bank categories")
    -- Any other view greys them (the bank's tabs and combined views do not read them).
    for _, view in ipairs({ VIEW.ALL, VIEW.BY_BAG, VIEW.BLIZZARD_GRID }) do
        for _, bankView in ipairs({ BANK_VIEW.TABS, BANK_VIEW.CHARACTER, BANK_VIEW.WARBANK }) do
            Check(view, bankView, false, false, "view " .. view .. ", bank view " .. bankView)
        end
    end
    -- The bank's category view reads the category switches, the set grouping
    -- and the empty-category hiding too; it has its own twins of the other
    -- grouping options.
    for _, view in ipairs({ VIEW.ALL, VIEW.BY_BAG, VIEW.BLIZZARD_GRID }) do
        Check(view, BANK_VIEW.CATEGORIES, not Suite.Client.isForever, false, "bank categories with view " .. view)
    end
    -- The reasons name the setting to change.
    config.inventoryView, config.bankView = VIEW.ALL, BANK_VIEW.TABS
    equal(Reason("category_junk"),
        'Choose Categories for "Default inventory view" or Bank categories for "Default bank view".',
        "category reason")
    equal(Reason("groupExpansions"), 'Choose Categories for "Default inventory view".', "grouping reason")
    -- WoW Forever has no organised bank, so only the bags' view counts.
    local isForever = Suite.Client.isForever
    Suite.Client.isForever = true
    config.bankView = BANK_VIEW.CATEGORIES
    equal(Usable("category_junk"), false, "Forever: category_junk follows the bank view")
    equal(Reason("category_junk"), 'Choose Categories for "Default inventory view".', "Forever category reason")
    Suite.Client.isForever = isForever
    config.inventoryView, config.bankView = rules.inventoryView.default, rules.bankView.default
end
print("bags audit: conflicts, bank panel color, bank size and position, Categories-only greying passed")
