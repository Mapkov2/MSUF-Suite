local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local function check(value, message) if not value then error(message, 2) end end
local function Anchor(frame) return frame:GetPoint(1) end

-- A minimap world in which exactly the addons in `loaded` are loaded (the
-- table may change while the world lives).
local function World(loaded, beforeModules)
    return H.New(root, "Mainline", { beforeModules = function(W)
        W.G.C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true end
        if beforeModules then beforeModules(W) end
    end })
end

local NS = World({}).Suite
local rules = NS.SuiteCatalog.minimap.rules

------------------------------------------------------------------ button collectors
-- Every collector keeps the map ours and blocks the Suite drawer, whether it
-- loaded before the module started or loads afterwards.
do
    local collectors, seen = NS.MinimapButtonCollectors, {}
    check(NS.MinimapButtonCollector() == nil and not NS.IsMinimapButtonCollector("SomeOtherAddon"),
        "an unrelated addon counts as a button collector")
    for _, name in ipairs(collectors) do
        check(not seen[name], "collector listed twice: " .. name)
        seen[name] = true
        check(NS.IsMinimapButtonCollector(name), "collector not recognised: " .. name)
    end
    check(seen.MinimapButtonButton and seen.HidingBar, "common collectors missing from the list")
    for _, name in ipairs(collectors) do
        local startup = World({ [name] = true })
        local icon = startup.Button("LibDBIcon10_Startup", startup.map, 31, 31)
        H.Enable(startup, { captured = true })
        startup.Step()
        check(startup.S.Availability("minimap") and startup.M.active and startup.M.mapOwned,
            name .. " blocked the Suite minimap")
        check(icon:GetParent() == startup.map and startup.MM.panel == nil and not startup.S.MinimapRescanButtons(),
            "Suite drawer claimed the buttons while " .. name .. " is loaded")
        check(startup.Suite.MinimapButtonCollector() == name, "the loaded collector is not found: " .. name)

        local loaded = {}
        local late = World(loaded)
        local button = late.Button("LibDBIcon10_Late", late.map, 31, 31)
        H.Enable(late, { captured = true })
        late.Step()
        check(button:GetParent() ~= late.map, "drawer did not collect before " .. name .. " loaded")
        loaded[name] = true
        late.Event("ADDON_LOADED", name)
        late.Step()
        check(late.S.Availability("minimap") and late.M.active and late.M.mapOwned,
            "late " .. name .. " disabled the Suite minimap")
        check(button:GetParent() == late.map and not late.S.MinimapRescanButtons(),
            "drawer did not yield its buttons to late " .. name)
    end
end

------------------------------------------------------------------ module conflicts
-- Replacement minimaps own the map itself; only they switch the module off.
do
    for _, name in ipairs({ "SexyMap", "Chinchilla", "BasicMinimap", "EllesmereUIMinimap", "ElvUI" }) do
        local ok, why = World({ [name] = true }).S.Availability("minimap")
        check(ok == false and why == "Managed by " .. name, name .. " does not switch the minimap module off")
    end
    check(World({}).S.Availability("minimap"), "the minimap module is unavailable without a conflict")
    for _, name in ipairs(NS.MinimapButtonCollectors) do
        check(World({ [name] = true }).S.Availability("minimap"), "collector " .. name .. " is a module conflict")
    end
end

------------------------------------------------------------------ group finder offsets
-- The preview moves the group finder button, so its offsets are not sliders.
do
    check(rules.dungeonX.previewOnly and rules.dungeonY.previewOnly, "dungeon offsets still show as numeric fields")
    for _, key in ipairs({ "dungeonWidth", "dungeonHeight", "dungeonAnchor", "dungeonStyle" }) do
        check(not rules[key].previewOnly, key .. " lost its control")
    end
end

------------------------------------------------------------------ difficulty text
local TIER_MYTHIC = 3
local function Near(color, hex)
    local r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    return color and math.abs(color[1] - r) < 1e-6 and math.abs(color[2] - g) < 1e-6 and math.abs(color[3] - b) < 1e-6
end
do
    -- Siblings carry the same options, and every key joins the texts category.
    for _, suffix in ipairs({ "Color", "Width", "Box", "BoxColor" }) do
        local rule = rules["infoDifficulty" .. suffix]
        check(rule and rules["infoClock" .. suffix], "difficulty lacks the sibling option " .. suffix)
        check(rule.section == "info_difficulty" and rule.enableKey == "infoDifficulty", suffix .. " is outside the section")
    end
    check(rules.infoDifficultyColor.disabledBy == "infoDifficultyColors", "the colour ignores 'Color by difficulty'")
    check(rules.infoDifficultyBoxColor.requiresChoice.key == "infoDifficultyBox", "the box colour has no box")
    local texts
    for _, category in ipairs(World({}).MM.applyCategories) do if category.name == "texts" then texts = category end end
    local joined = {}
    for _, key in ipairs(texts.keys) do joined[key] = true end
    for _, suffix in ipairs({ "Color", "Width", "Box", "BoxColor" }) do
        check(joined["infoDifficulty" .. suffix], "infoDifficulty" .. suffix .. " does not re-apply the texts")
    end

    local instance = { "Test", "none", 0, "", 0, 0, false, 0, 0 }
    local W = World({}, function(W)
        W.G.GetInstanceInfo = function() return unpack(instance) end
    end)
    W.editModeReady = true
    local S, M = W.S, W.M
    H.Enable(W, { captured = true, infoClock = false, infoLocation = false })
    W.Step()
    assert(S.Set("minimap", "infoDifficulty", true))
    local label = M.difficultyLabel
    -- Defaults are today's look: tier colour, plain white without it, no box.
    check(W.config.infoDifficultyColor == "ffffff" and W.config.infoDifficultyBox == 1
        and M.difficultyBox == nil, "difficulty defaults changed the look")
    instance = { "Raid", "raid", 16, "Mythic", 20, 0, false, 0, 20 }
    W.Event("PLAYER_DIFFICULTY_CHANGED")
    check(label.text == "20M" and Near(label.textColor, NS.MinimapDifficultyColors[TIER_MYTHIC]), "tier colour")
    assert(S.Set("minimap", "infoDifficultyColors", false))
    check(Near(label.textColor, "ffffff"), "plain colour is not white by default")
    assert(S.Set("minimap", "infoDifficultyColor", "336699"))
    check(Near(label.textColor, "336699"), "the chosen colour did not apply")
    assert(S.Set("minimap", "infoDifficultyColors", true))
    check(Near(label.textColor, NS.MinimapDifficultyColors[TIER_MYTHIC]), "tier colour ignored once switched back on")

    -- The width is the text's field: every anchor keeps the text on its side.
    check(label.width == W.config.infoDifficultyWidth, "difficulty text has no width")
    assert(S.Set("minimap", "infoDifficultyWidth", 200))
    check(label.width == 200, "the width did not apply")
    for anchor = 1, #NS.MinimapTextAnchorLabels do
        assert(S.Set("minimap", "infoDifficultyAnchor", anchor))
        local point, side = label.points[1][1], label.justify
        check(side == (point:find("LEFT", 1, true) and "LEFT" or point:find("RIGHT", 1, true) and "RIGHT" or "CENTER"),
            "a fixed width moved the text away from its anchor " .. anchor)
    end
    assert(S.Set("minimap", "infoDifficultyAnchor", 1))

    -- The box hugs the text, takes the border colour or its own, and rests
    -- while there is no text.
    assert(S.Set("minimap", "infoDifficultyBox", 2))
    local box = M.difficultyBox
    local r, g, b = W.MM.BorderRGB()
    check(box and box.shown and box.width == 26 and box.height == W.config.infoDifficultySize + 4
        and box.color[1] == r and box.color[2] == g and box.color[3] == b, "border-colour box")
    assert(S.SetMany("minimap", { infoDifficultyBox = 3, infoDifficultyBoxColor = "123456" }))
    check(Near(box.color, "123456"), "custom box colour")
    instance = { "Dungeon", "party", 8, "Mythic Keystone", 5, 0, false, 0, 5 }
    W.Event("PLAYER_DIFFICULTY_CHANGED")
    check(label.text == "M+" and box.shown and box.width == 20, "the box did not follow the text")
    instance = { "Test", "none", 0, "", 0, 0, false, 0, 0 }
    W.Event("PLAYER_DIFFICULTY_CHANGED")
    check(label.text == "" and not box.shown, "an empty text kept its box")
    assert(S.Set("minimap", "infoDifficultyBox", 1))
    instance = { "Raid", "raid", 16, "Mythic", 20, 0, false, 0, 20 }
    W.Event("PLAYER_DIFFICULTY_CHANGED")
    check(label.text == "20M" and not box.shown, "the box stayed with the setting off")
end

------------------------------------------------------------------ keep buttons on the map
local lib = { names = { "Alpha", "Beta" }, refreshed = {} }
function lib:GetButtonList() return self.names end
function lib:Refresh(name) self.refreshed[#self.refreshed + 1] = name end
function lib.RegisterCallback() end
function lib.UnregisterCallback() end
local function Refreshed(name)
    local count = 0
    for _, refreshed in ipairs(lib.refreshed) do if refreshed == name then count = count + 1 end end
    return count
end

local loaded = {}
local W = World(loaded, function(W)
    W.G.LibStub = { GetLibrary = function(_, name) if name == "LibDBIcon-1.0" then return lib end end }
end)
W.editModeReady = true
local map, S, MM = W.map, W.S, W.MM
local function Icon(name)
    local button = W.Button(name, map, 31, 31)
    button.strata, button.fixedStrata, button.level, button.fixedLevel = "MEDIUM", true, 8, true
    button.points = {}
    button:SetPoint("CENTER", map, "CENTER", 80, 10)
    return button
end
local alpha, beta, own = Icon("LibDBIcon10_Alpha"), Icon("LibDBIcon10_Beta"), Icon("MyAddonMinimapButton")
H.Enable(W, { captured = true })
W.Step()
local panel = MM.panel
check(alpha:GetParent() == panel and beta:GetParent() == panel and own:GetParent() == panel, "drawer did not collect")
check(#W.config.drawerKeep == 0, "the keep list is not empty by default")
local names = S.MinimapButtonNames()
check(#names == 3 and names[1] == "LibDBIcon10_Alpha" and names[3] == "MyAddonMinimapButton",
    "the picker is not fed the drawer's buttons")

-- A listed button leaves the drawer for the place its addon gave it.
local Kept = NS.MinimapKeptButtons
assert(S.Set("minimap", "drawerKeep", Kept.With("", "LibDBIcon10_Alpha")))
local point, relative, relativePoint, x, y = Anchor(alpha)
check(alpha:GetParent() == map and point == "CENTER" and relative == map and relativePoint == "CENTER"
    and x == 80 and y == 10 and alpha.scale == 1 and alpha.strata == "MEDIUM", "a kept button did not return to the map")
check(beta:GetParent() == panel and panel.width == 68, "the other buttons left the drawer")
names = S.MinimapButtonNames()
check(#names == 2 and names[1] == "LibDBIcon10_Beta", "the picker offers a kept button")
check(Refreshed("Alpha") == 1 and Refreshed("Beta") == 0, "a kept icon was not laid out around the map")
-- It follows the map's size, and a collected icon is not touched.
assert(S.Set("minimap", "size", 220))
check(Refreshed("Alpha") == 2 and Refreshed("Beta") == 0, "a kept icon did not follow the map's size")

-- Later rescans keep it out; a new icon is still collected.
local gamma = Icon("LibDBIcon10_Gamma")
W.Event("ADDON_LOADED", "Gamma")
W.Advance(0.1)
check(gamma:GetParent() == panel and alpha:GetParent() == map, "a rescan collected the kept button again")
check(S.MinimapRescanButtons() and alpha:GetParent() == map, "the manual rescan collected the kept button")

-- Removing it brings it back on the next scan; nothing else changes.
assert(S.Set("minimap", "drawerKeep", Kept.Without(W.config.drawerKeep, "LibDBIcon10_Alpha")))
W.Step()
check(alpha:GetParent() == panel and W.config.drawerKeep == "", "a removed button did not return to the drawer")
assert(S.Set("minimap", "drawerKeep", Kept.With(Kept.With("", "MyAddonMinimapButton"), "LibDBIcon10_Beta")))
check(own:GetParent() == map and beta:GetParent() == map, "a kept named button stayed in the drawer")
assert(S.Set("minimap", "collectButtons", false))
check(alpha:GetParent() == map and gamma:GetParent() == map, "turning collection off left buttons in the drawer")
assert(S.Set("minimap", "collectButtons", true))
check(alpha:GetParent() == panel and beta:GetParent() == map, "the keep list did not survive a collection switch")

-- The stored text: order, duplicates, limits and names that cannot be stored.
do
    local text = Kept.With(Kept.With("", "A"), "B")
    check(text == "A\nB" and Kept.With(text, "A") == text, "the list keeps duplicates")
    check(Kept.Without(text, "A") == "B" and Kept.Without("B", "B") == "", "removal")
    check(Kept.With(text, "bad\nname") == nil and Kept.With(text, "bad\tname") == nil, "a control character got in")
    local full = ""
    for i = 1, 24 do full = Kept.With(full, "Button" .. i) end
    check(full and Kept.With(full, "OneMore") == nil, "the list has no size limit")
    check(Kept.With("", ("x"):rep(rules.drawerKeep.maxLength + 1)) == nil, "a name beyond the setting's limit was stored")
    check(Kept.Label("LibDBIcon10_Alpha") == "Alpha" and Kept.Label("MyAddonMinimapButton") == "MyAddonMinimapButton"
        and Kept.IconFrame("Alpha") == "LibDBIcon10_Alpha", "button labels")
end

------------------------------------------------------------------ the page's list
-- MinimapButtonList.lua against stand-ins for the menu helpers it uses.
do
    assert(S.Set("minimap", "drawerKeep", ""))
    local refreshers, rows, menu, finished, picker = {}, {}, nil, nil, nil
    local function Control()
        local control = { enabled = true, shown = true, scripts = {} }
        function control:SetPoint() end
        function control:SetShown(value) self.shown = value end
        function control:SetEnabled(value) self.enabled = value end
        function control:SetScript(script, handler) self.scripts[script] = handler end
        function control:Click() self.scripts.OnClick(self) end
        return control
    end
    local function Refresh() for _, fn in ipairs(refreshers) do fn() end end
    local P = { Suite = W.Suite, S = S, Tr = function(text) return text end, catalog = NS.SuiteCatalog,
        T = { colors = { text = {} }, Button = function() local row = Control(); rows[#rows + 1] = row; return row end },
        M = { TrackRefresh = function(_, fn) refreshers[#refreshers + 1] = fn end } }
    function P.Get(id, key) return S.Config(id)[key] end
    function P.Set(id, key, value) local ok = S.Set(id, key, value); Refresh(); return ok end
    function P.Combat() return false end
    function P.ProfileGuard() return function() return true end end
    function P.ContextMenu(_, generator)
        menu = { titles = {}, choose = {}, order = {} }
        generator(nil, { CreateTitle = function(_, text) menu.titles[#menu.titles + 1] = text end,
            CreateButton = function(_, label, callback)
                menu.choose[label] = callback
                menu.order[#menu.order + 1] = label
            end })
    end
    function P.Text() return { GetStringHeight = function() return 14 end } end
    function P.Button(_, _, _, _, _, _, onClick, enabled)
        picker = Control()
        picker.scripts.OnClick = function() onClick(); Refresh() end
        picker.isEnabled = enabled
        return picker
    end
    function P.Meta() return {} end
    function P.SetTranslatedText(target, text) target.text = text end
    function P.SetButtonText(target, text) target.text = text end
    function P.FinishBody(_, _, bottom) finished = bottom end
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/MinimapButtonList.lua"))("MSUF_Suite_Options", P)

    local bottom = P.MinimapKeptButtons({}, "builder")({}, -18, 600)
    Refresh()
    check(picker.isEnabled() and P.MinimapDrawerOpen(), "the picker is not available with the drawer on")
    check(#rows == 0 and finished == nil, "rows exist without kept buttons")
    picker:Click()
    check(menu.titles[1] == "Keep a button on the minimap" and #menu.order == 4 and menu.order[1] == "Alpha"
        and menu.order[4] == "MyAddonMinimapButton", "the picker does not list the drawer's buttons by name")
    menu.choose.Alpha()
    check(S.Config("minimap").drawerKeep == "LibDBIcon10_Alpha" and alpha:GetParent() == map,
        "choosing a button did not keep it on the map")
    check(#rows == 1 and rows[1].shown and rows[1].text == "Put back in the drawer: Alpha",
        "the list shows no row for the kept button")
    check(finished == bottom - 30, "the section was not sized for its row")
    picker:Click()
    check(#menu.order == 3 and menu.order[1] == "Beta", "the picker still offers the kept button")
    menu.choose.Beta()
    check(#rows == 2 and finished == bottom - 2 * 30, "a second kept button has no row")
    -- Clicking a listed button removes it.
    rows[1]:Click()
    check(S.Config("minimap").drawerKeep == "LibDBIcon10_Beta" and rows[1].text == "Put back in the drawer: Beta"
        and not rows[2].shown, "clicking a listed button did not remove it")
    check(alpha:GetParent() == panel and beta:GetParent() == map, "the removed button did not return to the drawer")
    check(finished == bottom - 30, "the section kept the removed row's room")
    -- A dedicated collector pauses the drawer, and with it the picker.
    loaded.HidingBar = true
    check(not picker.isEnabled() and not P.MinimapDrawerOpen(), "the picker stays on while HidingBar collects")
end

------------------------------------------------------------------ preview
-- The movable preview shows the difficulty text with its colour, width and box.
-- The options contract's fixture builds the page; the run stops once the
-- Minimap page exists (the contract's later pins are other packages' concern).
do
    local SENTINEL = {}
    local original, ui, P = loadfile
    loadfile = function(path)
        local chunk = assert(original(path))
        if path:match("/Pages/MinimapPreview%.lua$") then
            return function(addon, ns)
                P = ns
                local register = P.M.RegisterControlMetadata
                P.M.RegisterControlMetadata = function(widget, ...)
                    local value = rawget(widget, "previewUI")
                    if type(value) == "table" and value.state then ui = value end
                    return register(widget, ...)
                end
                chunk(addon, ns)
            end
        end
        if path:match("/Pages/Minimap%.lua$") then
            return function(addon, ns)
                chunk(addon, ns)
                for _, spec in ipairs(ns.pages) do
                    if spec.key == "suite_minimap" then
                        local build = spec.build
                        spec.build = function(ctx)
                            build(ctx)
                            error(SENTINEL)
                        end
                    end
                end
            end
        end
        return chunk
    end
    local ok, err = pcall(function() assert(original(root .. "/tools/tests/suite_options_menu_contract.lua"))() end)
    loadfile = original
    check(not ok and err == SENTINEL, "the options fixture did not reach the Minimap page: " .. tostring(err))
    check(ui and P, "minimap preview did not build")
    local c = P.S.Config("minimap")
    c.infoDifficulty = true
    for key in pairs(ui.state.layers) do ui.state.layers[key] = true end
    ui.state.layers.guides, ui.state.layers.hidden = false, false
    local item
    for _, entry in ipairs(ui.textItems) do if entry.spec[1] == "Difficulty" then item = entry end end
    check(item, "no difficulty text in the preview")
    local function Is(color, hex)
        local r, g, b = P.RGB(hex)
        return color and math.abs(color[1] - r) < 1e-6 and math.abs(color[2] - g) < 1e-6 and math.abs(color[3] - b) < 1e-6
    end
    ui.body:SetWidth(720)
    ui.Paint()
    check(Is(item.label.textColor, P.Suite.MinimapDifficultyColors[2]) and not item.box.shown,
        "preview does not show the live colours or shows a box by default")
    c.infoDifficultyColors, c.infoDifficultyColor = false, "336699"
    ui.Paint()
    check(Is(item.label.textColor, "336699"), "preview ignores the difficulty text colour")
    c.infoDifficultyBox = 2
    ui.Paint()
    local r, g, b = P.RGB(c.borderColor)
    check(item.box.shown and item.box.color[1] == r and item.box.color[2] == g and item.box.color[3] == b,
        "preview shows no box in the border colour")
    c.infoDifficultyBox, c.infoDifficultyBoxColor = 3, "123456"
    ui.Paint()
    check(item.box.shown and Is(item.box.color, "123456"), "preview ignores the box colour")
    c.infoDifficultyBox = 1
    ui.Paint()
    check(not item.box.shown, "preview kept the box with the setting off")
end

print("Minimap pack: collectors, conflicts, group finder offsets, difficulty colour/width/box, kept buttons and preview passed")
