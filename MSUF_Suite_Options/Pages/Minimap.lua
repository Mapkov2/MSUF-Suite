local _, P = ...
local Suite, S, W, M, T, Tr = P.Suite, P.S, P.W, P.M, P.T, P.Tr
local PAGE, ID = "suite_minimap", "minimap"

local HELP = {
    layout = "Select the map in the preview, then drag it or adjust X and Y in the preview's position bar.",
    hover_size = "The map grows or shrinks to the chosen width and height while the pointer is over it, then returns to its normal size. A circular map keeps its height equal to its width.",
    shape = "Choose the map shape, then adjust its border and outer shadow.",
    style_presets = "Start with a look, then tune its artwork, glow and plate. Changing a detail switches the preset label to Custom without losing the other settings.",
    style_art = "Layer original Suite border artwork above or behind the map. Choose Custom texture for a local texture path or file ID; negative rotation moves the other way.",
    style_glow = "A soft light behind the map, independent of the border and artwork.",
    style_backdrop = "A colored plate sits behind the map and its border. Padding extends it beyond the map edge.",
    behavior = "The mouse wheel zooms the map. Middle-click runs the chosen action; left and right clicks keep working as usual.",
    elements = "Blizzard's own buttons stay functional. The row is their starting position; drag each icon freely in the preview.",
    landing = "Omnium Folio is Midnight's expansion button. Choose Never to remove it, or Simple book for a smaller, quieter icon that still opens the feature.",
    addons = "Buttons that addons place on the minimap are collected into a drawer. Drag its button in the preview; click it to open the icons in a grid.",
    info_colors = "Shared colors for the FPS and latency texts.",
    info_tooltips = "Used when a clock, FPS or latency text shows instance lockouts or the Great Vault on mouseover.",
}
local ELEMENTS = { showTracking = "Tracking", showCalendar = "Calendar", showMail = "Mail", showCrafting = "Crafting",
    showDifficulty = "Difficulty", showLanding = "Landing", landingIcon = "Landing", showCompartment = "Compartment" }
-- Client capabilities come from the runtime once it is loaded; before that
-- every control stays editable and the runtime ignores what it cannot do.
P.Gates[ID] = function(rule, key)
    local prefix = key:match("^(info%a+)Shadow")
    if prefix then
        prefix = prefix:gsub("Shadow.*$", "")
        if P.Get(ID, prefix .. "Rendering") == 3 then return false end
        if key ~= prefix .. "Shadow" and not P.Get(ID, prefix .. "Shadow") then return false end
    end
    if rule.key == "shape" and S.CanShapeMinimap and not S.CanShapeMinimap() then return false end
    if rule.key == "hoverHeight" and P.Get(ID, "shape") == 2 then return false end
    if rule.infoField and S.CanShowMinimapInfo and not P.Get(ID, key) and not S.CanShowMinimapInfo(rule.infoField) then return false end
    local element = ELEMENTS[rule.key]
    -- Retail creates the expansion button lazily; its setting must be editable
    -- before the Blizzard_ExpansionLandingPage addon has loaded.
    if element == "Landing" and Suite.Client and Suite.Client.isMainline and not Suite.Client.isForever then return true end
    if element and S.MinimapElementAvailable and not S.MinimapElementAvailable(element) then return false end
    return true
end

-- Lockout and Great Vault tooltips depend on client APIs (no vault on Classic).
local function TooltipChoice(index)
    if index ~= 2 and index ~= 3 then return true end
    return not S.CanShowMinimapTooltip or S.CanShowMinimapTooltip(index) and true or false
end
P.ChoiceGates[ID] = { infoClockTooltip = TooltipChoice, infoFPSTooltip = TooltipChoice, infoLatencyTooltip = TooltipChoice }

local function BuildStylePresets(ctx, b)
    local rules = P.SectionRules(ID, "style_presets")
    return P.RuleSection(ctx, b, PAGE, ID, "suite_minimap_style_presets", Tr("Choose a look"), rules, {
        help = HELP.style_presets, open = true,
        extra = function(body, y, width)
            local presets = {
                { 8, "Midnight Blue", "57c7df" }, { 9, "Midnight Dark", "b9ab86" },
                { 7, "MSUF Forever", "d8b66a" }, { 2, "Clean", "aab5c2" },
                { 3, "Arcane", "b7a4ff" }, { 4, "Ember", "ffc078" },
                { 5, "Astral", "a7e8ff" }, { 6, "Steel", "c1d6df" },
            }
            local gap = 7
            local columns = 4
            local buttonWidth = math.max(40, math.floor((width - gap * (columns - 1)) / columns))
            for i, spec in ipairs(presets) do
                local button = T.Button(body, Tr(spec[2]), buttonWidth, 55)
                button:SetPoint("TOPLEFT", body, "TOPLEFT",
                    16 + ((i - 1) % columns) * (buttonWidth + gap),
                    y - math.floor((i - 1) / columns) * 62)
                local label = type(button) == "table" and rawget(button, "_msuf2Label")
                if label and type(label.ClearAllPoints) == "function" then
                    label:ClearAllPoints()
                    label:SetPoint("BOTTOM", button, "BOTTOM", 0, 5)
                    label:SetJustifyH("CENTER")
                end
                local path = Suite.MinimapStyle and Suite.MinimapStyle.paths[spec[1] - 1]
                local swatch = button:CreateTexture(nil, "ARTWORK")
                swatch:SetPoint("CENTER", button, "CENTER", 0, 10)
                swatch:SetSize(24, 24)
                swatch:SetTexture(path or "Interface\\Buttons\\WHITE8X8")
                local r, g, blue = P.RGB(spec[3])
                swatch:SetVertexColor(r, g, blue, 1)
                if i == 1 then swatch:SetSize(17, 17) end
                button:SetScript("OnClick", function()
                    if not P.Combat() then P.Set(ID, "stylePreset", spec[1]) end
                end)
                if M.RegisterControlMetadata then
                    M.RegisterControlMetadata(button, P.Meta(PAGE, ID, "style.preset." .. spec[1], "action", "suite_minimap_style_presets"),
                        spec[2] .. " minimap style", "button")
                end
                M.TrackRefresh(ctx, function() button:SetAlpha(P.Get(ID, "stylePreset") == spec[1] and 1 or 0.58) end)
            end
            return y - 130
        end,
    })
end

local function Build(ctx)
    local b = W.PageBuilder(ctx)
    local sections = {}
    -- FixedPreviewSection releases the first builder slot from scroll flow.
    -- Build it before any accordion so it stays docked above Frame Basics.
    P.BuildMinimapPreview(ctx, b, sections)
    P.ModuleCard(ctx, b, PAGE, ID, {
        { "Collect addon buttons again", function() if S.MinimapRescanButtons then S.MinimapRescanButtons() end end,
          function() return S.MinimapRescanButtons ~= nil and P.Get(ID, "enabled") and P.Get(ID, "collectButtons") end, key = "rescan" },
        { "Reload UI", function() if ReloadUI then ReloadUI() end end,
          function() return S.states[ID] and S.states[ID].reloadRequired ~= nil end, key = "reload" },
        { "Reset module", function()
            P.WithHistory("Reset minimap", "suite:minimap.reset", function() return S.Reset(ID) end)
        end, function() return S.Availability(ID) end, key = "reset" },
    })
    sections.style_presets = BuildStylePresets(ctx, b)
    for _, section in ipairs({ "layout", "hover_size", "landing", "shape", "behavior", "elements", "addons" }) do
        local rules = P.SectionRules(ID, section)
        sections[section] = P.RuleSection(ctx, b, PAGE, ID, "suite_minimap_" .. section, Tr(rules[1].sectionTitle), rules,
            { help = HELP[section], open = section == "layout" })
    end
    for _, section in ipairs({ "style_art", "style_glow", "style_backdrop" }) do
        local rules = P.SectionRules(ID, section)
        sections[section] = P.RuleSection(ctx, b, PAGE, ID, "suite_minimap_" .. section, Tr(rules[1].sectionTitle), rules,
            { help = HELP[section], open = false })
    end
    for _, field in ipairs(Suite.MinimapInfoFields or {}) do
        local section = "info_" .. field:lower()
        sections[section] = P.RuleSection(ctx, b, PAGE, ID, "suite_minimap_" .. section, Tr(field == "FPS" and "FPS" or field), P.SectionRules(ID, section),
            { open = false })
    end
    for _, section in ipairs({ "info_difficulty", "info_colors", "info_tooltips" }) do
        local rules = P.SectionRules(ID, section)
        if #rules > 0 then
            sections[section] = P.RuleSection(ctx, b, PAGE, ID, "suite_minimap_" .. section, Tr(rules[1].sectionTitle), rules,
                { help = HELP[section], open = false })
        end
    end
end

P.RegisterPage({ key = PAGE, label = "Minimap", title = "Minimap", build = Build, icon = { 2, 0 },
    aliases = { "minimap", "map" } })
