local root = assert(arg[1], "Suite root required")
local function Load(path, ns)
    return assert(loadfile(root .. "/" .. path))("MSUF_Suite", ns)
end

local secret = newproxy()
local function Boot(forever)
    local ns = {
        Text = function(value) return value end,
        IsSecret = function(value) return rawequal(value, secret) end,
        Client = { isForever = forever, isMainline = not forever },
    }
    Load("MSUF_Suite/Core/SuiteCatalog.lua", ns)
    Load("MSUF_Suite/Core/CharacterTabs.lua", ns)
    Load("MSUF_Suite/Core/CharacterBindings.lua", ns)
    Load("MSUF_Suite/Core/Catalog/CharacterPanel.lua", ns)
    return ns.CharacterTabs, ns.CharacterHeader, ns.SuiteCatalog.characterPanel, ns.CharacterBindings
end

local function Sources(card)
    local ids = {}
    for i = 1, #card.rows do ids[card.rows[i].source] = true end
    return ids
end

local function VerifyClient(forever)
    local Model, Header, spec = Boot(forever)
    assert(spec.rules.customTabs.hidden and spec.rules.customTabs.default == "")
    assert(spec.rules.customTabs.maxLength == Model.MaxBytes and spec.rules.tabOrder.maxLength == 256)
    assert(Header.Order({}, "tab") == Header.Tabs and Header.Order({}, "inspectTab") == Header.InspectTabs)
    local attrs = { tabOrder = "reputation,overview", showAttributesTab = true }
    local shown = Header.Order(attrs, "tab")
    assert(shown[2].id == "attributes" and #shown == #Header.Tabs + 1)
    assert(Header.Order(attrs, "tab") == shown and #Header.Order(attrs, "inspectTab") == 3)
    attrs.tabOrder = Header.Move(attrs, "tab", "attributes", "overview")
    assert(Header.Order(attrs, "tab")[3].id == "attributes")
    attrs.showAttributesTab = false
    assert(Header.Order(attrs, "tab")[3].id ~= "attributes")
    attrs.tabOrder = Header.Move(attrs, "tab", "currency", "reputation")
    attrs.showAttributesTab = true
    assert(Header.Order(attrs, "tab")[4].id == "attributes", "moving tabs lost the hidden position")
    assert(#Header.Tabs == 7 and #Header.InspectTabs == 3)
    assert(Model.Source("health").sample and Model.Source("resource").label == "Resource")
    assert(Model.SourceAvailable("spirit") == forever and Model.SourceAvailable("avoidance") ~= forever)
    assert(Model.SourceAvailable("mastery") ~= forever and not Model.SourceAvailable("unknown"))
    assert(Sources(Model.NewCard("attributes")).spirit == (forever and true or nil))

    local config = { tabOrder = "stats,overview,custom2,custom1,gear,custom1", inspectTabOrder = "custom1,compare" }
    local tabs = Model.Copy(config)
    assert(Model.Create(tabs, "raid", "  Raid 100%  ") == "custom1")
    assert(Model.Create(tabs, "progress", "Fortschritt ä") == "custom2")
    assert(tabs[1].name == "Raid 100%" and #tabs[1].cards == 2 and #tabs[2].cards == 1)
    assert((Sources(tabs[1].cards[1]).missingEnchants == true) ~= forever)
    assert((Sources(tabs[1].cards[1]).emptySockets == true) ~= forever)
    assert(Sources(tabs[2].cards[1]).xp)
    tabs[1].cards[1].rows[1].label = "iLvl, % ready"
    config.customTabs = assert(Model.Encode(tabs))

    local record = Model.Get(config)
    assert(record == Model.Get(config) and record == Model.Get(config), "cache reparsed unchanged layout")
    assert(Model.Find(config, "custom2").name == "Fortschritt ä")
    assert(Model.Find(config, "custom1").cards[1].rows[1].label == "iLvl, % ready")
    assert(Model.Encode(record) == config.customTabs, "round trip changed a valid layout")
    spec.prepareConfig(config)
    assert(Model.Get(config) == record and Model.Encode(Model.Copy(config)) == config.customTabs)

    local ordered = Header.Order(config, "tab")
    assert(ordered[1].id == "overview" and ordered[2].id == "custom2" and ordered[2].custom,
        "stored order dropped numeric custom IDs")
    assert(ordered[3].id == "custom1" and ordered[4].id == "gear" and #ordered == 9)
    assert(Header.Order(config, "tab") == ordered, "unchanged order rebuilt descriptors")
    assert(Header.Order(config, "inspectTab")[1].id == "compare" and #Header.Order(config, "inspectTab") == 3)
    config.tabOrder = assert(Header.Move(config, "tab", "custom1", "custom2"))
    assert(Header.Order(config, "tab")[2].id == "custom1", "custom ID could not be moved among stock IDs")

    local copy = Model.Copy(config)
    copy[1].name = "Raid: updated"
    copy[1].cards[1].rows[1].label = "Gear"
    assert(record[1].name == "Raid 100%" and record[1].cards[1].rows[1].label == "iLvl, % ready")
    local priorOrder = Header.Order(config, "tab")
    config.customTabs = assert(Model.Encode(copy))
    assert(Header.Order(config, "tab") ~= priorOrder and Header.Order(config, "tab")[2].label == "Raid: updated")
    assert(Model.Duplicate(copy, "custom1", "Copy") == "custom3" and copy[3].name == "Copy")
    assert(copy[3].cards[1].rows[1] ~= copy[1].cards[1].rows[1])
    table.remove(copy, 3)
    config.customTabs = assert(Model.Encode(copy))
    copy = Model.Copy(config)
    assert(Model.Create(copy, "empty") == "custom4", "deleted identity was reused")
    assert(#copy[3].cards == 0)
    for i = #copy, 1, -1 do table.remove(copy, i) end
    config.customTabs = assert(Model.Encode(copy))
    assert(#Model.Get(config) == 0 and #Header.Order(config, "tab") == 7)
    assert(Model.Create(Model.Copy(config), "empty") == "custom5", "empty layout lost its identity sequence")

    local exhausted = { customTabs = "1|1000000\nT|custom999999|Imported\nT|custom1|First" }
    local recovered = Model.Copy(exhausted)
    assert(Model.Create(recovered, "empty") == "custom2", "imported high-water mark stranded tab creation")
    exhausted.customTabs = assert(Model.Encode(recovered))
    assert(Model.Find(exhausted, "custom999999").name == "Imported")
    assert(Model.Find(exhausted, "custom1").name == "First" and Model.Find(exhausted, "custom2"))

    local sanitized = Model.Copy({})
    Model.Create(sanitized, "empty", string.rep("é", 41))
    sanitized[1].cards[1] = Model.NewCard()
    sanitized[1].cards[1].title = "  Stats|: O\nK  "
    sanitized[1].cards[1].rows[1] = { source = forever and "mastery" or "spirit", label = "A\rB" }
    local normalized = Model.Get({ customTabs = assert(Model.Encode(sanitized)) })
    assert(normalized[1].name == string.rep("é", 40), "truncated a UTF-8 code point")
    assert(normalized[1].cards[1].title == "Stats: OK" and normalized[1].cards[1].rows[1].label == "AB")
    assert(not Model.SourceAvailable(normalized[1].cards[1].rows[1].source), "lost cross-client source identity")

    for _, corrupt in ipairs({
        "unknown", "3|2\nT|custom1|Raid", "1|1\nT|custom1|Raid", "1|2\nT|custom01|Raid",
        "1|2\nT|custom1|Raid|5050", "2|2\nT|custom1|Raid|5050|60", "2|2\nT|custom1|Raid|50XX",
        "1|2\nT|custom1|Raid\nT|custom1|Duplicate", "1|2\nR|health|Unattached",
        "1|2\nT|custom1|Raid\nC||Card\nR|injected|Row", string.rep("x", Model.MaxBytes + 1),
    }) do
        local profile = { customTabs = corrupt }
        assert(#Model.Get(profile) == 0, "accepted corrupt or out-of-bound layout")
        Model.Normalize(profile)
        assert(profile.customTabs == "", "did not repair invalid profile input")
    end

    local full = Model.Copy({ customTabs = "1|999990\n" })
    local longName = string.rep("é", Model.NameLimit / 2)
    for i = 1, Model.TabLimit do
        assert(Model.Create(full, "empty", longName))
        full[i].x, full[i].y = -48, -8
        for j = 1, Model.CardLimit do
            local card = Model.NewCard()
            card.title, card.x, card.y = longName, -48, -24
            for k = 1, Model.RowLimit do
                card.rows[k] = { source = "currency:2147483647", label = longName, x = -32, y = -10 }
            end
            full[i].cards[j] = card
        end
    end
    local encoded = assert(Model.Encode(full), "maximum-size moved layout did not fit")
    assert(Model.Encode(Model.Get({ customTabs = encoded })) == encoded, "largest moved layout did not round trip")
    assert(not Model.Create(full, "empty"), "tab count exceeded its cap")
    full[1].cards[1].rows[Model.RowLimit + 1] = { source = "health", label = "" }
    assert(not Model.Encode(full), "row count exceeded its cap")
end

local function ExpectPosition(Model, entry, expectedX, expectedY, message)
    local x, y = Model.Position(entry)
    assert(x == expectedX and y == expectedY, message)
end

local function VerifyBuilderSources(forever)
    local Model = Boot(forever)
    local reports = {
        reputationReport = "reputation", currencyReport = "currency", skillsReport = "skills",
        pvpReport = "pvp", statisticsReport = "statistics", attributesReport = "attributes", equipmentReport = "gear",
    }
    local visible = {}
    for _, source in ipairs(Model.Sources) do visible[source.id] = true end
    for id, tab in pairs(reports) do
        assert(visible[id] and Model.SourceAvailable(id) and Model.Source(id).report == tab, id)
    end
    local watched = Model.Source("watchedReputation")
    assert(visible[watched.id] and watched.kind == "faction" and watched.target == nil)

    local faction = assert(Model.DynamicSourceID("faction", 76))
    local currency = assert(Model.DynamicSourceID("currency", 2147483647))
    assert(faction == "faction:76" and currency == "currency:2147483647")
    assert(Model.SourceAvailable(faction) and Model.SourceAvailable(currency))
    assert(Model.Source(faction).kind == "faction" and Model.Source(faction).target == 76)
    assert(Model.Source(currency).kind == "currency" and Model.Source(currency).target == 2147483647)
    assert(not Model.DynamicSourceID(secret, 42) and not Model.DynamicSourceID("currency", secret))
    assert(not Model.DynamicSourceID("currency", 1.5) and not Model.DynamicSourceID("currency", math.huge))
    assert(not Model.DynamicSourceID("currency", "42") and not Model.DynamicSourceID("skill", 42))
    for _, key in ipairs({ "faction:0", "faction:-1", "faction:076", "faction:7e1", "currency:2147483648", "skill:95" }) do
        assert(not Model.Source(key) and not Model.SourceAvailable(key), key)
        local imported = "1|2\nT|custom1|Test\nC||Values\nR|" .. key .. "|Label"
        assert(#Model.Get({ customTabs = imported }) == 0, "accepted an invalid dynamic source")
    end

    local tabs = Model.Copy({})
    assert(Model.Create(tabs, "reputation") == "custom1" and Sources(tabs[1].cards[1]).reputationReport)
    local rows = tabs[1].cards[1].rows
    rows[2], rows[3] = { source = faction, label = "My faction", x = 4, y = -2 }, { source = currency, label = "" }
    rows[4] = { source = watched.id, label = "" }
    local encoded = assert(Model.Encode(tabs))
    local config = { customTabs = encoded }
    local copy = Model.Copy(config)
    assert(Model.Duplicate(copy, "custom1", "Copy") == "custom2")
    config.customTabs = assert(Model.Encode(copy))
    local duplicate = Model.Find(config, "custom2").cards[1].rows
    assert(duplicate[2].source == faction and duplicate[2].label == "My faction")
    assert(duplicate[3].source == currency and duplicate[4].source == watched.id)
    ExpectPosition(Model, duplicate[2], 4, -2, "dynamic source position did not survive duplication and encoding")
    config.customTabs = encoded
    Model.Normalize(config)
    assert(config.customTabs == encoded, "profile normalization altered supported dynamic sources")
end

local function VerifyPositions(forever)
    local Model, Header = Boot(forever)
    local legacy = "1|2\nT|custom1|Überblick\nC||Werte\nR|health|Ausdauer"
    local config = { customTabs = legacy, tabOrder = "overview,custom1,gear", inspectTabOrder = "compare,overview" }
    local old = assert(Model.Find(config, "custom1"))
    ExpectPosition(Model, old, 0, 0, "v1 tab did not default to its base slot")
    ExpectPosition(Model, old.cards[1], 0, 0, "v1 card did not default to its base slot")
    ExpectPosition(Model, old.cards[1].rows[1], 0, 0, "v1 row did not default to its base slot")
    ExpectPosition(Model, nil, 0, 0, "missing entries need zero offsets")
    assert(Model.Encode(Model.Copy(config)) == legacy, "unmoved v1 layout changed format")
    assert(Model.PositionBounds.tab.x == 48 and Model.PositionBounds.tab.y == 8)
    assert(Model.PositionBounds.card.x == 48 and Model.PositionBounds.card.y == 24)
    assert(Model.PositionBounds.row.x == 32 and Model.PositionBounds.row.y == 10)

    local before, inspect = Header.Order(config, "tab"), Header.Order(config, "inspectTab")
    local tabs = Model.Copy(config)
    local tab, card, row = tabs[1], tabs[1].cards[1], tabs[1].cards[1].rows[1]
    tab.x, tab.y = -12, 4
    config.customTabs = assert(Model.Encode(tabs))
    local after = Header.Order(config, "tab")
    assert(after ~= before and after[2].id == "custom1", "tab-only offsets did not invalidate cached order")
    ExpectPosition(Model, after[2], -12, 4, "tab order did not expose position")
    assert(Header.Order(config, "inspectTab") == inspect, "own tab offsets invalidated the Inspect order")
    assert(after[1] == Header.Tabs[1] and after[1].x == nil, "native tab gained custom position fields")

    card.x, card.y = 91, -82
    row.x, row.y = -8.2, 3.3
    config.customTabs = assert(Model.Encode(tabs))
    assert(config.customTabs:sub(1, 2) == "2|", "moved layout did not use the new format")
    local moved = assert(Model.Find(config, "custom1"))
    ExpectPosition(Model, moved, -12, 4, "tab offsets did not round trip")
    ExpectPosition(Model, moved.cards[1], 48, -24, "card offsets escaped their bounds")
    ExpectPosition(Model, moved.cards[1].rows[1], -8, 3, "row offsets were not rounded in logical units")
    assert(moved.name == old.name and moved.cards[1].rows[1].label == old.cards[1].rows[1].label)

    local encoded = config.customTabs
    Model.Normalize(config)
    assert(config.customTabs == encoded, "profile normalization changed a valid positioned layout")
    local copied = Model.Copy(config)
    assert(Model.Encode(copied) == encoded, "copy lost a position")
    assert(Model.Duplicate(copied, "custom1", "Kopie") == "custom2")
    local copyConfig = { customTabs = assert(Model.Encode(copied)) }
    local duplicate = assert(Model.Find(copyConfig, "custom2"))
    ExpectPosition(Model, duplicate, -12, 4, "duplicate lost tab position")
    ExpectPosition(Model, duplicate.cards[1], 48, -24, "duplicate lost card position")
    ExpectPosition(Model, duplicate.cards[1].rows[1], -8, 3, "duplicate lost row position")

    local untrusted = { customTabs = "2|2\nT|custom1|Imported|9999\nC||Card|0000\nR|health||9999" }
    local imported = assert(Model.Find(untrusted, "custom1"))
    ExpectPosition(Model, imported, 48, 8, "imported tab offset escaped its bounds")
    ExpectPosition(Model, imported.cards[1], -48, -24, "imported card offset escaped its bounds")
    ExpectPosition(Model, imported.cards[1].rows[1], 32, 10, "imported row offset escaped its bounds")
    local raw = untrusted.customTabs
    Model.Normalize(untrusted)
    assert(untrusted.customTabs ~= raw and untrusted.customTabs == Model.Encode(Model.Get(untrusted)),
        "import normalization did not canonicalize out-of-range positions")

    local x, y = Model.ClampPosition("row", -1000, 1000)
    assert(x == -32 and y == 10, "position helper bypassed per-kind limits")
    x, y = Model.ClampPosition("tab", 0 / 0, "6")
    assert(x == 0 and y == 0, "malformed axis leaked into the offset")
    local reset = Model.Copy(config)
    reset[1].x, reset[1].y = 0, 0
    reset[1].cards[1].x, reset[1].cards[1].y = 0, 0
    reset[1].cards[1].rows[1].x, reset[1].cards[1].rows[1].y = 0, 0
    assert(Model.Encode(reset) == legacy, "resetting all offsets did not restore v1 encoding")
end

local function BindingLabel(command)
    return _G["BINDING_NAME_" .. command]
end

local function Apply(config, patch)
    for key, value in pairs(assert(patch)) do config[key] = value end
end

local function VerifyVisibility(forever)
    local Model, Header, spec = Boot(forever)
    assert(spec.rules.hiddenTabs.hidden and spec.rules.hiddenInspectTabs.hidden and spec.rules.homeTab.hidden)
    assert(spec.rules.homeTab.default == "overview" and spec.rules.hiddenTabs.default == "")
    local config = { tabOrder = "overview,reputation,gear,pvp", showAttributesTab = true }
    assert(Header.HomeTab(config, "tab") == "overview")
    Apply(config, Header.SetHomeTab(config, "pvp"))
    assert(Header.HomeTab(config, "tab") == "pvp")
    local patch = Header.SetTabVisible(config, "tab", "pvp", false)
    assert(patch.hiddenTabs == "pvp" and patch.homeTab == "overview")
    assert(Header.HomeTab(config, "tab") == "pvp", "model edited the live profile before commit")
    Apply(config, patch)
    assert(not Header.TabVisible(config, "tab", "pvp") and Header.HomeTab(config, "tab") == "overview")
    local visible, hidden = Header.Order(config, "tab"), Header.HiddenTabs(config, "tab")
    assert(hidden[1].id == "pvp" and #hidden == 1)
    assert(visible == Header.Order(config, "tab") and hidden == Header.HiddenTabs(config, "tab"))
    Apply(config, Header.SetTabVisible(config, "tab", "attributes", false))
    assert(config.hiddenTabs == "pvp" and not config.showAttributesTab)
    assert(not Header.SetHomeTab(config, "pvp") and not Header.Move(config, "tab", "overview", "pvp"))
    config.tabOrder = assert(Header.Move(config, "tab", "gear", "overview"))
    Apply(config, Header.SetTabVisible(config, "tab", "pvp", true))
    Apply(config, Header.SetTabVisible(config, "tab", "attributes", true))
    visible = Header.Order(config, "tab")
    assert(visible[1].id == "gear" and visible[3].id == "reputation" and visible[4].id == "attributes" and visible[5].id == "pvp")
    assert(#Header.HiddenTabs(config, "tab") == 0)

    Apply(config, Header.SetTabVisible(config, "inspectTab", "overview", false))
    assert(Header.HomeTab(config, "inspectTab") == "gear" and Header.TabVisible(config, "tab", "overview"))
    Apply(config, Header.SetTabVisible(config, "inspectTab", "gear", false))
    assert(not Header.SetTabVisible(config, "inspectTab", "compare", false))
    assert(Header.HomeTab(config, "inspectTab") == "compare")
    Apply(config, Header.SetTabVisible(config, "inspectTab", "overview", true))
    assert(Header.HomeTab(config, "inspectTab") == "overview")

    local tabs = Model.Copy(config)
    assert(Model.Create(tabs, "empty", "My home") == "custom1")
    config.customTabs = assert(Model.Encode(tabs))
    config.tabOrder = "gear,overview,custom1,pvp,reputation,attributes"
    Apply(config, Header.SetTabVisible(config, "tab", "pvp", false))
    Apply(config, Header.SetHomeTab(config, "custom1"))
    table.remove(tabs, 1)
    Apply(config, Header.WithoutCustomTab(config, "custom1", assert(Model.Encode(tabs))))
    assert(Header.HomeTab(config, "tab") == "overview" and not Model.Find(config, "custom1"))
    assert(config.tabOrder:find("overview,pvp,reputation,attributes", 1, true), "deletion lost hidden placement")
    assert(Model.Create(Model.Copy(config), "empty", "Later") == "custom2")

    local all = "overview,gear,reputation,skills,pvp,currency,statistics"
    local corrupt = { hiddenTabs = all .. ",attributes,injected", homeTab = "missing", hiddenInspectTabs = "gear,overview,compare" }
    assert(#Header.Order(corrupt, "tab") == 1 and Header.HomeTab(corrupt, "tab") == "overview")
    assert(not Header.SetTabVisible(corrupt, "tab", "overview", false))
    spec.prepareConfig(corrupt)
    assert(corrupt.hiddenTabs == "gear,reputation,skills,pvp,currency,statistics" and corrupt.homeTab == "overview")
    assert(corrupt.hiddenInspectTabs == "gear,compare")
    local onlyCustom = { hiddenTabs = all, customTabs = "1|2\nT|custom1|Only", homeTab = "custom1" }
    assert(#Header.Order(onlyCustom, "tab") == 1 and Header.HomeTab(onlyCustom, "tab") == "custom1")
    assert(not Header.WithoutCustomTab(onlyCustom, "custom1", "1|2\n"))
end

local function VerifyBindings(forever)
    local Model, Header, spec, Bindings = Boot(forever)
    local config = { homeTab = "skills" }
    local overview, gear, custom1, custom2 = Bindings.Direct[1], Bindings.Direct[2], Bindings.Slots[1], Bindings.Slots[2]
    assert(#Bindings.Native == (forever and 5 or 6) and #Bindings.Direct == 8 and #Bindings.Slots == 8)
    assert(Bindings.Native[1].command == "TOGGLECHARACTER0" and Bindings.Native[1].key == "homeTab")
    assert(Bindings.Native[2].command == "TOGGLECHARACTER2" and Bindings.Native[3].command == "TOGGLECURRENCY")
    assert(Bindings.NativeTab(config, "pvp") == (forever and "pvp" or nil))
    assert(Bindings.NativeTab(config, "skills") == nil, "an unsupported native binding was fabricated")
    assert(Bindings.Native[5].command == "TOGGLEPROFESSIONBOOK" and Bindings.Native[5].defaultLabel == "Blizzard window")
    assert(not Bindings.NativeTab(config, "professions") and not Bindings.NativeTab(config, "statistics"))
    assert(not Bindings.Native[6] or Bindings.Native[6].command == "TOGGLESTATISTICS")
    assert(not forever or not Bindings.SetNativeTab(config, "statistics", "overview"))
    assert(spec.rules.statisticsBindingTab.hidden, "cross-client profile lost the dormant Retail route")
    assert(Bindings.NativeTab(config, "character") == "skills")
    assert(Bindings.NativeTab(config, "reputation") == "reputation")
    assert(Bindings.NativeTab(config, "currency") == "currency")
    assert(spec.rules.pvpBindingTab.hidden, "cross-client profile lost the dormant Forever route")
    assert(spec.rules[custom1.key].hidden and spec.rules[custom1.key].default == "")
    assert(BindingLabel(overview.command) == "Open Overview" and BindingLabel(custom1.command) == "Custom tab shortcut 1")
    assert(BINDING_HEADER_MSUFSUITE_CHARACTER == "Character Panel")

    local tabs = Model.Copy(config)
    local first = assert(Model.Create(tabs, "empty", "Raid"))
    local second = assert(Model.Create(tabs, "empty", "Daily"))
    config.customTabs = assert(Model.Encode(tabs))
    Apply(config, Bindings.SetNativeTab(config, "reputation", first))
    Apply(config, Bindings.SetNativeTab(config, "currency", "gear"))
    Apply(config, Bindings.SetNativeTab(config, "professions", first))
    assert(Bindings.DirectTab(config, Bindings.Native[5].override) == first)
    assert(Bindings.NativeTab(config, "reputation") == first and Bindings.NativeTab(config, "currency") == "gear")
    assert(not Bindings.SetSlot(config, 1, "gear") and not Bindings.SetSlot(config, 0, first))
    Apply(config, Bindings.SetSlot(config, 1, first))
    assert(not Bindings.SetSlot(config, 1, second), "assigning an occupied slot displaced the other tab")
    assert(Bindings.DirectTab(config, custom1.command) == first)
    assert(Bindings.CommandForTab(config, first) == custom1.command)
    assert(Bindings.CommandForTab(config, second) == nil)
    Bindings.RefreshLabels(config)
    assert(BindingLabel(custom1.command) == "Custom tab shortcut 1 (Raid)")

    Apply(config, Header.SetTabVisible(config, "tab", "gear", false))
    assert(Bindings.NativeTab(config, "currency") == "skills" and config.currencyBindingTab == "gear")
    assert(not Bindings.DirectTab(config, gear.command), "a hidden tab became a direct destination")
    Apply(config, Header.SetTabVisible(config, "tab", "gear", true))
    assert(Bindings.NativeTab(config, "currency") == "gear" and Bindings.DirectTab(config, gear.command) == "gear")

    tabs[1].name = "New Raid"
    config.customTabs = assert(Model.Encode(tabs))
    config.tabOrder = assert(Header.Move(config, "tab", second, first))
    assert(Bindings.DirectTab(config, custom1.command) == first, "tab reorder changed shortcut identity")
    Bindings.RefreshLabels(config)
    assert(BindingLabel(custom1.command) == "Custom tab shortcut 1 (New Raid)")
    Apply(config, Bindings.SetSlot(config, 2, first))
    assert(Bindings.DirectTab(config, custom1.command) == nil and Bindings.DirectTab(config, custom2.command) == first)

    config.pvpBindingTab = first
    table.remove(tabs, 1)
    Apply(config, Header.WithoutCustomTab(config, first, assert(Model.Encode(tabs))))
    assert(config.reputationBindingTab == "" and config.pvpBindingTab == "" and config.professionsBindingTab == ""
        and config[custom2.key] == "")
    assert(Bindings.NativeTab(config, "reputation") == "reputation")
    assert(Bindings.DirectTab(config, custom2.command) == nil, "a deleted tab left a live shortcut")
    Bindings.RefreshLabels(config)
    assert(BindingLabel(custom1.command) == "Custom tab shortcut 1" and BindingLabel(custom2.command) == "Custom tab shortcut 2")

    config[custom1.key], config[custom2.key] = second, second
    config.currencyBindingTab, config.pvpBindingTab = "bogus", "attributes"
    spec.prepareConfig(config)
    assert(config[custom1.key] == second and config[custom2.key] == "")
    assert(config.currencyBindingTab == "" and config.pvpBindingTab == "attributes")
    Bindings.RefreshLabels(nil)
end

local function VerifyBindingXml()
    local _, _, _, bindings = Boot(false)
    local file = assert(io.open(root .. "/MSUF_Suite/Bindings.xml", "rb"))
    local xml = file:read("*a")
    file:close()
    local scripts = {}
    for name, flags, script in xml:gmatch('<Binding name="(MSUFSUITE_CHARACTER_[A-Z0-9]+)"([^>]*)>([^<]+)</Binding>') do
        assert(flags:find('category="BINDING_HEADER_MSUFSUITE_CHARACTER"', 1, true) and not scripts[name])
        scripts[name] = script
    end
    assert(xml:find('header="MSUFSUITE_CHARACTER"', 1, true))
    for _, group in ipairs({ bindings.Direct, bindings.Slots }) do
        for _, entry in ipairs(group) do
            local called
            local handler = assert(loadstring(assert(scripts[entry.command])))
            setfenv(handler, { MSUFSuite = { Suite = { OpenBoundCharacterTab = function(command) called = command end } } })
            handler()
            assert(called == entry.command, "Blizzard binding opens the wrong destination")
            scripts[entry.command] = nil
        end
    end
    assert(not next(scripts), "unknown direct character binding")
end

VerifyBindingXml()
VerifyBindings(false)
VerifyBindings(true)
VerifyVisibility(false)
VerifyVisibility(true)
VerifyBuilderSources(false)
VerifyBuilderSources(true)
VerifyClient(false)
VerifyClient(true)
VerifyPositions(false)
VerifyPositions(true)
print("Character Panel: custom tab profile, source availability, ordering and positions passed for Retail and Forever")
