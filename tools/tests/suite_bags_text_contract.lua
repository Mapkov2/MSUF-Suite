-- Text of the bag and bank views with the FULL Bags TOC loaded (client model
-- of suite_bags_harness.lua): translatable composed labels, player text left
-- alone, fonts that follow the global MSUF font, one copy of the helpers.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")

local function Labels(W)
    local texts = {}
    for _, label in ipairs(W.P.InventoryView.labels) do
        if label.shown then texts[#texts + 1] = label.text end
    end
    return texts
end

local function Has(list, text)
    for _, value in ipairs(list) do if value == text then return true end end
    return false
end

---------------------------------------------------------------- labels
do
    local W = H.New(root, { config = { inventoryView = 3, groupExpansions = true, hideEmptyCategories = true,
        customCategories = "1|Junk|12\n1|Raid %25 Mats|13" } })
    MSUF_NS.L["Consumables"] = "Verbrauchsgüter"
    MSUF_NS.L["%s - %s"] = "%s (%s)"
    MSUF_NS.L["Junk"] = "Plunder"
    MSUF_NS.L["%s (%d)"] = "%s [%d]"
    W.sizes[0] = 4
    W.Define(10, { name = "Potion", class = 0, maxStack = 20, expansion = 10 })
    W.Define(12, { name = "Stone", class = 15, expansion = 10 })
    W.Define(13, { name = "Ore", class = 7, expansion = 10 })
    W.Put(0, 1, 10, 3)
    W.Put(0, 2, 12, 1)
    W.Put(0, 3, 13, 1)
    W.Apply()
    W.OpenBags()
    W.Settle()
    local labels = Labels(W)
    assert(Has(labels, "Verbrauchsgüter (The War Within)"),
        "built-in labels and the expansion suffix must be translated as parts: " .. table.concat(labels, ", "))
    assert(Has(labels, "Junk (The War Within)") and not Has(labels, "Plunder (The War Within)"),
        "a category the player named must not be translated like Suite text")
    assert(Has(labels, "Raid % Mats (The War Within)"), "player text keeps its own characters")
    local sidebar = {}
    for _, button in ipairs(W.P.InventoryView.buttons) do
        if button.shown then sidebar[#sidebar + 1] = button.text end
    end
    assert(Has(sidebar, "Verbrauchsgüter (The War Within) [1]"),
        "sidebar counts must use the translatable count format: " .. table.concat(sidebar, ", "))
end

---------------------------------------------------------------- fonts
do
    local W = H.New(root, { config = { inventoryView = 1, font = "" } })
    W.globalFont = "Fonts\\First.ttf"
    MSUF_GetFontPath = function() return W.globalFont end
    W.sizes[0] = 2
    W.Define(10, { name = "Potion", class = 0, maxStack = 20 })
    W.Put(0, 1, 10, 3)
    W.Apply()
    W.OpenBags()
    W.Settle()
    local V = W.P.InventoryView
    assert(V.position.font[1] == "Fonts\\First.ttf", "view text did not start with the global MSUF font")
    W.globalFont = "Fonts\\Second.ttf"
    W.Apply()
    W.Settle()
    assert(V.position.font[1] == "Fonts\\Second.ttf" and V.labels[1].font[1] == "Fonts\\Second.ttf",
        "view text must follow a changed global MSUF font")
end

---------------------------------------------------------------- one copy of the view helpers
do
    local function Source(file)
        local handle = assert(io.open(root .. "/MSUF_Suite_Bags/" .. file, "rb"))
        local text = handle:read("*a")
        handle:close()
        return text
    end
    for _, file in ipairs({ "InventoryView.lua", "BankInventory.lua" }) do
        local text = Source(file)
        assert(not text:find("local function Font%(") and not text:find("Rows %%d%-%%d of %%d", 1)
            and not text:find("S%.Text%(cell%.group%.label%)") and not text:find("S%.Text%(group%.label%)"),
            file .. " keeps its own copy of a shared view helper")
    end
    assert(Source("GridView.lua"):find("Rows %d-%d of %d", 1, true), "GridView owns the row counter")
end

print("bag text: translatable labels, player text, global fonts and shared helpers passed")
