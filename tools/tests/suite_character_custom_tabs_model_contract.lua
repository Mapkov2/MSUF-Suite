local root = assert(arg[1], "Suite root required")
local function Load(path, ns)
    return assert(loadfile(root .. "/" .. path))("MSUF_Suite", ns)
end

local function Boot(forever)
    local ns = { Text = function(value) return value end, Client = { isForever = forever } }
    Load("MSUF_Suite/Core/SuiteCatalog.lua", ns)
    Load("MSUF_Suite/Core/CharacterTabs.lua", ns)
    Load("MSUF_Suite/Core/Catalog/CharacterPanel.lua", ns)
    return ns.CharacterTabs, ns.CharacterHeader, ns.SuiteCatalog.characterPanel
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
    assert(spec.prepareConfig == Model.Normalize)
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
                card.rows[k] = { source = "missingEnchants", label = longName, x = -32, y = -10 }
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

VerifyClient(false)
VerifyClient(true)
VerifyPositions(false)
VerifyPositions(true)
print("Character Panel: custom tab profile, source availability, ordering and positions passed for Retail and Forever")
