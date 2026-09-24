local _, P = ...
local S, M, T, Tr = P.S, P.M, P.T, P.Tr
local PAGE, ID = "suite_dataTexts", "dataTexts"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"
local OUTLINES = { "OUTLINE", "THICKOUTLINE", "", "MONOCHROME,OUTLINE" }
local ALIGN = { "LEFT", "CENTER", "RIGHT" }
local function ResolveMedia(kind, key)
    if type(key) ~= "string" or key == "" then return nil end
    local shared = kind == "font" and S.ResolveFont or S.ResolveTexture
    if shared then return shared(key) end
    if key:find("\\", 1, true) or key:find("/", 1, true) then return key end
    local resolve = kind == "font" and (_G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey)
        or _G.MSUF_ResolveStatusbarTextureKey
    local path = type(resolve) == "function" and resolve(key) or nil
    if type(path) == "string" and path ~= "" then return path end
    local stub = _G.LibStub
    local media = type(stub) == "table" and type(stub.GetLibrary) == "function"
        and stub:GetLibrary("LibSharedMedia-3.0", true)
    return media and media:Fetch(kind == "font" and "font" or "statusbar", key, true) or nil
end

local function Preview(ctx, body, y, width, bar)
    local sample = CreateFrame("Frame", nil, body)
    sample:SetPoint("TOPLEFT", body, "TOPLEFT", 16, y)
    sample:SetSize(math.min(width, 520), 32)
    local fill = sample:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(sample)
    local edges = {}
    for i = 1, 4 do edges[i] = sample:CreateTexture(nil, "BORDER"); edges[i]:SetTexture(WHITE) end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT")
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT")
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT")
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT")
    local accent = sample:CreateTexture(nil, "ARTWORK")
    accent:SetTexture(WHITE)
    accent:SetPoint("BOTTOMLEFT"); accent:SetPoint("BOTTOMRIGHT"); accent:SetHeight(1)
    local divider = sample:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(WHITE)
    divider:SetPoint("CENTER")
    local labels = {}
    for i = 1, 2 do
        local label = sample:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetWordWrap(false)
        labels[i] = label
    end
    M.TrackRefresh(ctx, function()
        local style = P.Suite.DataTextEffectiveStyle(S.Config(ID), bar or 1)
        local function Color(texture, hex, alpha)
            local r, g, b = P.RGB(hex)
            texture:SetVertexColor(r, g, b, alpha)
        end
        local texture = ResolveMedia("texture", style.backgroundTexture)
        fill:SetTexture(texture or WHITE)
        Color(fill, style.backgroundColor, style.backgroundOpacity / 100)
        fill:SetShown(style.backgroundEnabled)
        for i = 1, 4 do
            local edge = edges[i]
            Color(edge, style.borderColor, .85)
            edge:SetShown(style.borderEnabled)
            if i <= 2 then edge:SetHeight(style.borderSize) else edge:SetWidth(style.borderSize) end
        end
        Color(accent, style.accentColor, .9)
        accent:SetShown(style.accentEnabled)
        Color(divider, style.separatorColor, .8)
        divider:SetSize(style.separatorSize, math.max(6, 32 - 2 * style.padding))
        divider:SetShown(style.separatorEnabled)
        local font = ResolveMedia("font", style.font) or DEFAULT_FONT
        local flags = OUTLINES[style.textOutline] or "OUTLINE"
        local align = ALIGN[style.textAlign] or "CENTER"
        local half = math.floor(math.min(width, 520) / 2)
        for i, label in ipairs(labels) do
            label:ClearAllPoints()
            label:SetPoint("LEFT", sample, "LEFT", (i - 1) * half + style.padding + (i == 2 and style.gap / 2 or 0), 0)
            label:SetWidth(half - 2 * style.padding - style.gap / 2)
            label:SetJustifyH(align)
            P.StylePreviewFont(label, font, style.fontSize, flags, style.fontRendering,
                style.fontShadow, style.fontShadowOpacity, style.fontShadowDistance)
            local name, value = i == 1 and "Gold" or "FPS", i == 1 and "124g" or "75"
            label:SetText((style.showLabels and ("|cff" .. style.labelColor .. name .. ": |r") or "")
                .. "|cff" .. style.valueColor .. value .. "|r")
        end
    end)
    return y - 44
end

local function NextBar()
    for i = 1, 3 do if not P.Get(ID, "bar" .. i .. "Enabled") then return i end end
end
local function AddPlace(bar)
    local prefix, used = "bar" .. bar, {}
    for slot = 1, 6 do used[P.Get(ID, prefix .. "Slot" .. slot)] = true end
    for slot = 1, 6 do
        local key = prefix .. "Slot" .. slot
        if P.Get(ID, key) == 1 then
            for choice = 2, #P.Suite.DataTextSources do
                if not used[choice] then return P.Set(ID, key, choice) end
            end
            return P.Set(ID, key, 2)
        end
    end
end
local function OpenChoice(button, bar, slot)
    local key = "bar" .. bar .. "Slot" .. slot
    if MenuUtil and type(MenuUtil.CreateContextMenu) == "function" then
        MenuUtil.CreateContextMenu(button, function(_, root)
            for index, name in ipairs(P.Suite.DataTextSources) do
                root:CreateRadio(Tr(name), function() return P.Get(ID, key) == index end,
                    function() P.Set(ID, key, index) end)
            end
        end)
        return
    end
    -- The dropdown rows below remain the primary picker on older clients.
    P.Set(ID, key, P.Get(ID, key) % #P.Suite.DataTextSources + 1)
end
local function BarSection(ctx, b, bar)
    local prefix, sectionId = "bar" .. bar, PAGE .. "_bar" .. bar
    local body = b:CollapsibleSection(sectionId, Tr("Bar " .. bar), 120, bar == 1)
    local width = math.max(240, (body._msuf2Width or b.width or 720) - 32)
    local toggle = P.W.SectionSwitch(body, Tr("Enable"), Tr("Enable"))
    M.BindBoolWidget(ctx, toggle,
        function() return P.Get(ID, prefix .. "Enabled") == true end,
        function(value) P.Set(ID, prefix .. "Enabled", value == true) end,
        P.Meta(PAGE, ID, prefix .. "Enabled", "setting", sectionId))
    M.TrackRefresh(ctx, function()
        P.W.SetControlEnabled(toggle, not P.Combat())
    end)
    local y = -18
    local help = P.Text(body, "Click a place to choose its text. Drag the bar in MSUF Edit Mode. Empty places disappear.", 16, y, width)
    y = y - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 10
    local gap = 6
    local tileWidth = math.floor((width - 5 * gap) / 6)
    for slot = 1, 6 do
        local index = slot
        local button = T.Button(body, "", tileWidth, 29)
        button:SetPoint("TOPLEFT", body, "TOPLEFT", 16 + (slot - 1) * (tileWidth + gap), y)
        button:SetScript("OnClick", function(self)
            if not P.Combat() then OpenChoice(self, bar, index) end
        end)
        if M.RegisterControlMetadata then
            M.RegisterControlMetadata(button, P.Meta(PAGE, ID, prefix .. "Slot" .. slot .. ".preview", "action", sectionId),
                "Choose data for place " .. slot, "button")
        end
        M.TrackRefresh(ctx, function()
            local choice = P.Get(ID, prefix .. "Slot" .. index)
            button:SetText(Tr(P.Suite.DataTextSources[choice] or "None"))
            button:SetEnabled(S.Availability(ID) and P.Get(ID, "enabled")
                and P.Get(ID, prefix .. "Enabled") and not P.Combat())
        end)
    end
    y = y - 43
    local buttonWidth = math.floor((width - 12) / 3)
    P.Button(ctx, body, "Add place", 16, y, buttonWidth,
        function() AddPlace(bar) end,
        function()
            if not P.Get(ID, prefix .. "Enabled") then return false end
            for slot = 1, 6 do if P.Get(ID, prefix .. "Slot" .. slot) == 1 then return true end end
            return false
        end, P.Meta(PAGE, ID, prefix .. ".addPlace", "action", sectionId))
    P.Button(ctx, body, "Move in Edit Mode", 22 + buttonWidth, y, buttonWidth,
        function() S.OpenEditMode(ID, prefix) end,
        function() return S.Status(ID) == "Active" and P.Get(ID, prefix .. "Enabled") end,
        P.Meta(PAGE, ID, prefix .. ".move", "action", sectionId))
    P.Button(ctx, body, "Hide bar", 28 + buttonWidth * 2, y, buttonWidth,
        function() P.Set(ID, prefix .. "Enabled", false) end,
        function() return P.Get(ID, prefix .. "Enabled") end,
        P.Meta(PAGE, ID, prefix .. ".hide", "action", sectionId))
    y = y - 43
    y = P.RuleGrid(ctx, body, PAGE, ID, P.SectionRules(ID, prefix), y, width, nil, sectionId)
    y = y - 16
    local heading = P.Text(body, Tr("Bar styling"), 16, y, width, T.colors.text)
    y = y - math.max(14, math.ceil(heading:GetStringHeight() or 14)) - 6
    local helpStyle = P.Text(body,
        "Use the shared style or customize this bar. Switching on copies the current shared settings.", 16, y, width)
    y = y - math.max(14, math.ceil(helpStyle:GetStringHeight() or 14)) - 10
    local ownRule = P.catalog[ID].rules[prefix .. "StyleOverride"]
    local ownRow = P.RuleRow(PAGE, ID, ownRule, nil, sectionId)
    ownRow.set = function(value)
        if value == true and not P.Get(ID, ownRule.key) then
            local values = { [ownRule.key] = true }
            for _, key in ipairs(P.Suite.DataTextStyleKeys) do
                values[P.Suite.DataTextBarStyleKey(bar, key)] = P.Get(ID, key)
            end
            P.SetMany(ID, values)
        else
            P.Set(ID, ownRule.key, value == true)
        end
    end
    local ownGrid = P.W.SettingsRows(ctx, body, { x = 16, y = y, width = width, columns = 2, rows = { ownRow } })
    P.GateControls(ctx, ID, { { rule = ownRule, widget = ownGrid.controls[ownRule.key] } })
    y = ownGrid.bottomY - 8
    local styleRules = P.SectionRules(ID, prefix .. "Style")
    y = P.RuleGrid(ctx, body, PAGE, ID, styleRules, y, width, nil, sectionId)
    y = Preview(ctx, body, y - 8, width, bar)
    P.AttachRuleColors(body, "Bar " .. bar, ID, styleRules)
    P.FinishBody(b, body, y - 12)
end
local function Build(ctx)
    local b = P.W.PageBuilder(ctx)
    P.ModuleCard(ctx, b, PAGE, ID, {
        { "Add bar", function()
            local index = NextBar()
            if index then P.Set(ID, "bar" .. index .. "Enabled", true) end
        end, function() return S.Availability(ID) and P.Get(ID, "enabled") and NextBar() ~= nil end, key = "addBar" },
        { "Move first bar", function() S.OpenEditMode(ID, "bar1") end,
          function() return S.Status(ID) == "Active" and P.Get(ID, "bar1Enabled") end, key = "move" },
        { "Reset module", function()
            P.WithHistory("Reset DataTexts", "suite:dataTexts.reset", function() return S.Reset(ID) end)
        end, function() return S.Availability(ID) end, key = "reset" },
    })
    P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_appearance", Tr("Shared bar style"),
        P.SectionRules(ID, "appearance"), {
            open = true,
            help = "These settings apply to all bars until a bar uses its own style.",
            extra = function(body, y, width) return Preview(ctx, body, y - 8, width) end,
        })
    P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_textStyle", Tr("Shared text style"),
        P.SectionRules(ID, "textStyle"), {
            help = "Choose an MSUF font, outline, shadow and Smooth, Sharp or Slug rendering. Slug has no shadow. Label, value and warning colors are separate.",
        })
    local bagRules = P.SectionRules(ID, "bags")
    if #bagRules > 0 then
        P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_bags", Tr("Blizzard bag buttons"), bagRules, {
            help = "While DataTexts is active, hide Blizzard's backpack and bag slots. A Bag space DataText opens the native bags when clicked. Turn this off to restore the Blizzard buttons.",
        })
    end
    for bar = 1, 3 do BarSection(ctx, b, bar) end
end
P.RegisterPage({ key = PAGE, label = "DataTexts", title = "DataTexts", build = Build, icon = { 5, 2 },
    aliases = { "datatext", "datatexts", "data bars", "info bar", "system info" } })
