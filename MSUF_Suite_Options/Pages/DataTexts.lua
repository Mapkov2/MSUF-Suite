local _, P = ...
local S, M, T, Tr = P.S, P.M, P.T, P.Tr
local PAGE, ID = "suite_dataTexts", "dataTexts"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BAG_BADGE = "Interface\\AddOns\\MSUF_Suite_DataTexts\\Media\\BagMedallion.tga"
local OUTLINES = { "OUTLINE", "THICKOUTLINE", "", "MONOCHROME,OUTLINE" }
local ALIGN = { "LEFT", "CENTER", "RIGHT" }
local PLACES = 6
local function CrestCurrencyMenu(anchor)
    local suite=P.Suite
    local selected,order,seen={},{},{}
    for value in (P.Get(ID,'crestCurrencyIDs') or ''):sub(1,4096):gmatch('%d+') do
        local id=tonumber(value)
        if suite.Finite(id) and id>0 and id<2147483647 and not selected[id] and #order<32 then
            selected[id]=true
            order[#order+1]=id
        end
    end
    local function Add(menu,id,info)
        if not suite.Finite(id) or id<=0 or seen[id] or not suite.Public(info) or type(info)~='table'
            or not suite.Public(info.name) or type(info.name)~='string' then return end
        seen[id]=true
        local label=info.name..' ('..id..')'
        if suite.Finite(info.iconFileID) then label='|T'..info.iconFileID..':16|t '..label end
        menu:CreateCheckbox(label,function() return selected[id]==true end,function()
            local values={}
            for _,value in ipairs(order) do if value~=id then values[#values+1]=value end end
            if not selected[id] and #values<32 then values[#values+1]=id end
            P.SetMany(ID,{crestMode=2,crestCurrencyIDs=table.concat(values,',')})
            CrestCurrencyMenu(anchor)
        end)
    end
    MenuUtil.CreateContextMenu(anchor,function(_,menu)
        menu:SetScrollMode(420)
        menu:CreateTitle(Tr('Select your current-season crests from the native currency list.'))
        menu:CreateTitle(Tr('Selection order is display order. Remove and select again to move a currency last.'))
        menu:CreateButton(Tr('Clear selection'),function() P.SetMany(ID,{crestMode=2,crestCurrencyIDs=''}) end)
        for _,id in ipairs(order) do Add(menu,id,C_CurrencyInfo.GetCurrencyInfo(id)) end
        menu:CreateDivider()
        for index=1,C_CurrencyInfo.GetCurrencyListSize() do
            local info=C_CurrencyInfo.GetCurrencyListInfo(index)
            if suite.Public(info) and type(info)=='table' and suite.Public(info.name) and type(info.name)=='string' then
                if suite.Public(info.isHeader) and info.isHeader then
                    local row=index
                    local expanded=suite.Public(info.isHeaderExpanded) and info.isHeaderExpanded==true
                    local header=menu:CreateButton(info.name..(expanded and ' -' or ' +'),function()
                        C_CurrencyInfo.ExpandCurrencyList(row,not expanded)
                        CrestCurrencyMenu(anchor)
                    end)
                    header:SetResponse(MenuResponse.Open)
                else
                    local link=C_CurrencyInfo.GetCurrencyListLink(index)
                    if suite.Public(link) and type(link)=='string' then Add(menu,C_CurrencyInfo.GetCurrencyIDFromLink(link),info) end
                end
            end
        end
    end)
end
-- The upgrade stages DataTexts observed this login. Sources.lua belongs to
-- the load-on-demand DataTexts addon and exports them on S (Suite.Suite), not
-- on the namespace: before it loads, the menu offers only the reset to all
-- observed stages.
local function SeasonStagesMenu(anchor)
    local sources = S.DataTextExtraSources
    local choices = sources and sources.CrestChoices() or {}
    MenuUtil.CreateContextMenu(anchor, function(_, menu)
        menu:CreateButton(Tr("Show all observed stages"), function() P.SetMany(ID, { crestMode = 1, crestCurrencies = "" }) end)
        for _, cost in ipairs(choices) do
            local order = cost.order
            local selected = false
            for value in (P.Get(ID, "crestCurrencies") or ""):gmatch("%d+") do
                if tonumber(value) == order then selected = true end
            end
            local info = cost.currencyID and C_CurrencyInfo.GetCurrencyInfo(cost.currencyID)
            local name = info and info.name or cost.itemID and C_Item.GetItemInfo(cost.itemID) or tostring(order)
            menu:CreateCheckbox(tostring(order) .. ": " .. name, function() return selected end, function()
                local values = {}
                for value in (P.Get(ID, "crestCurrencies") or ""):gmatch("%d+") do
                    if tonumber(value) ~= order then values[#values + 1] = value end
                end
                if not selected then values[#values + 1] = tostring(order) end
                P.SetMany(ID, { crestMode = 1, crestCurrencies = table.concat(values, ",") })
            end)
        end
    end)
end
-- Top, bottom, left and right preview edges, each spanning its whole side.
local EDGE_POINTS = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }

-- Font and texture keys through the core resolvers (MSUF_Suite/Core/Platform.lua).
local function ResolveMedia(kind, key)
    if kind == "font" then return P.Suite.ResolveFont(key) end
    return P.Suite.ResolveTexture(key)
end

local function Color(texture, hex, alpha)
    local r, g, b = P.RGB(hex)
    texture:SetVertexColor(r, g, b, alpha)
end

------------------------------------------------------------------ preview
local function PaintPreview(view, style)
    local fill, edges = view.fill, view.edges
    local fade = style.backgroundEnabled and style.backgroundGradient
    fill:SetTexture(ResolveMedia("texture", style.backgroundTexture) or WHITE)
    Color(fill, style.backgroundColor, style.backgroundOpacity / 100)
    fill:SetShown(style.backgroundEnabled and not fade)
    view.gradient:SetShown(fade == true)
    if fade then
        local r, g, b = P.RGB(style.backgroundColor)
        local fr, fg, fb = P.RGB(style.backgroundFadeColor)
        local alpha = style.backgroundOpacity / 100
        view.gradient:SetGradient("VERTICAL", CreateColor(fr, fg, fb, alpha), CreateColor(r, g, b, alpha))
    end
    for i = 1, 4 do
        local edge = edges[i]
        Color(edge, style.borderColor, .85)
        edge:SetShown(style.borderEnabled)
        if i <= 2 then edge:SetHeight(style.borderSize) else edge:SetWidth(style.borderSize) end
    end
    Color(view.accent, style.accentColor, .9)
    view.accent:SetShown(style.accentEnabled)
    view.accent:ClearAllPoints()
    local contentX = style.bagBadge and 64 or 0
    if style.accentPosition == 2 then
        view.accent:SetPoint("TOPLEFT", view.sample, "TOPLEFT", contentX, 0)
        view.accent:SetPoint("TOPRIGHT", view.sample, "TOPRIGHT", 0, 0)
    else
        view.accent:SetPoint("BOTTOMLEFT", view.sample, "BOTTOMLEFT")
        view.accent:SetPoint("BOTTOMRIGHT", view.sample, "BOTTOMRIGHT")
    end
    view.badge:SetShown(style.bagBadge == true)
    local font = ResolveMedia("font", style.font) or P.Suite.GlobalFontPath()
    local flags = OUTLINES[style.textOutline] or "OUTLINE"
    local align = ALIGN[style.textAlign] or "CENTER"
    local count = style.bagBadge and 3 or 2
    local slotWidth = (view.width - contentX) / count
    for i, divider in ipairs(view.dividers) do
        Color(divider, style.separatorColor, .8)
        divider:SetSize(style.separatorSize, math.max(6, 60 - 2 * style.padding))
        divider:ClearAllPoints()
        divider:SetPoint("CENTER", view.sample, "LEFT", contentX + slotWidth * i, 0)
        divider:SetShown(style.separatorEnabled and i < count)
    end
    for i, label in ipairs(view.labels) do
        label:SetShown(i <= count)
        label:ClearAllPoints()
        label:SetPoint("LEFT", view.sample, "LEFT", contentX + (i - 1) * slotWidth + style.padding, 0)
        label:SetWidth(slotWidth - 2 * style.padding)
        label:SetJustifyH(align)
        P.StylePreviewFont(label, font, style.fontSize, flags, style.fontRendering,
            style.fontShadow, style.fontShadowOpacity, style.fontShadowDistance)
        local name, value
        if style.bagBadge then
            name, value = ({ Tr("Bags"), Tr("Durability"), Tr("Time") })[i],
                ({ "48%", "100%", "11:39" })[i]
        else
            name, value = i == 1 and Tr("Gold") or "FPS", i == 1 and "124g" or "75"
        end
        local hasLabel = style.showLabels and not (style.bagBadge and i == 3 and not style.clockLabel)
        local separator = style.labelColon and ": " or " "
        label:SetText((hasLabel and ("|cff" .. style.labelColor .. name .. separator .. "|r") or "")
            .. "|cff" .. style.valueColor .. value .. "|r")
    end
end

-- A sample bar (shared style, or `bar`'s own) with two example texts.
local function Preview(ctx, body, y, width, bar)
    local view = { width = math.min(width, 520), edges = {}, labels = {}, dividers = {} }
    local sample = CreateFrame("Frame", nil, body)
    sample:SetPoint("TOPLEFT", body, "TOPLEFT", 16, y)
    sample:SetSize(view.width, 60)
    view.sample = sample
    view.fill = sample:CreateTexture(nil, "BACKGROUND")
    view.fill:SetAllPoints(sample)
    view.gradient = sample:CreateTexture(nil, "BACKGROUND")
    view.gradient:SetTexture(WHITE)
    view.gradient:SetAllPoints(sample)
    for i = 1, 4 do
        local edge = sample:CreateTexture(nil, "BORDER")
        edge:SetTexture(WHITE)
        edge:SetPoint(EDGE_POINTS[i][1])
        edge:SetPoint(EDGE_POINTS[i][2])
        view.edges[i] = edge
    end
    view.accent = sample:CreateTexture(nil, "ARTWORK")
    view.accent:SetTexture(WHITE)
    view.accent:SetPoint("BOTTOMLEFT")
    view.accent:SetPoint("BOTTOMRIGHT")
    view.accent:SetHeight(1)
    for i = 1, 2 do
        local divider = sample:CreateTexture(nil, "ARTWORK")
        divider:SetTexture(WHITE)
        view.dividers[i] = divider
    end
    view.badge = sample:CreateTexture(nil, "OVERLAY")
    view.badge:SetTexture(BAG_BADGE)
    view.badge:SetPoint("LEFT", sample, "LEFT", 3, 0)
    view.badge:SetSize(56, 56)
    for i = 1, 3 do
        local label = sample:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetWordWrap(false)
        view.labels[i] = label
    end
    M.TrackRefresh(ctx, function()
        PaintPreview(view, P.Suite.DataTextEffectiveStyle(S.Config(ID), bar or 1))
    end)
    return y - 72
end

------------------------------------------------------------------ bars
local function NextBar()
    return P.Suite.DataTextNextBarID(S.Config(ID))
end
local function RebuildBars()
    if M.activeKey==PAGE and M.RebuildPageKeepingScroll then M.RebuildPageKeepingScroll(PAGE) end
end

local function HasEmptyPlace(prefix)
    for slot = 1, PLACES do
        if P.Get(ID, prefix .. "Slot" .. slot) == 1 then return true end
    end
    return false
end

-- Fills the first empty place with a source the bar does not show yet.
local function AddPlace(bar)
    local prefix, used = "bar" .. bar, {}
    for slot = 1, PLACES do used[P.Get(ID, prefix .. "Slot" .. slot)] = true end
    for slot = 1, PLACES do
        local key = prefix .. "Slot" .. slot
        if P.Get(ID, key) == 1 then
            for choice = 2, #P.Suite.DataTextSources do
                if not used[choice] then return P.Set(ID, key, choice) end
            end
            return P.Set(ID, key, 2)
        end
    end
end

-- Blizzard_Menu's MenuUtil exists on every supported client.
local function OpenChoice(button, bar, slot)
    local key = "bar" .. bar .. "Slot" .. slot
    MenuUtil.CreateContextMenu(button, function(_, root)
        for index, name in ipairs(P.Suite.DataTextSources) do
            root:CreateRadio(Tr(name), function() return P.Get(ID, key) == index end,
                function() P.Set(ID, key, index) end)
        end
    end)
end

-- One tile per place; a click opens the source menu.
local function BuildPlaces(ctx, body, bar, sectionId, y, width)
    local prefix = "bar" .. bar
    local gap = 6
    local tileWidth = math.floor((width - (PLACES - 1) * gap) / PLACES)
    local buttons = {}
    for slot = 1, PLACES do
        local button = T.Button(body, "", tileWidth, 29)
        button:SetPoint("TOPLEFT", body, "TOPLEFT", 16 + (slot - 1) * (tileWidth + gap), y)
        button:SetScript("OnClick", function(self)
            if not P.Combat() then OpenChoice(self, bar, slot) end
        end)
        if M.RegisterControlMetadata then
            M.RegisterControlMetadata(button, P.Meta(PAGE, ID, prefix .. "Slot" .. slot .. ".preview", "action", sectionId),
                Tr("Choose data for place %d"):format(slot), "button")
        end
        buttons[slot] = button
    end
    M.TrackRefresh(ctx, function()
        local enabled = S.Availability(ID) and P.Get(ID, "enabled") and P.Get(ID, prefix .. "Enabled")
            and not P.Combat()
        for slot = 1, PLACES do
            local choice = P.Get(ID, prefix .. "Slot" .. slot)
            buttons[slot]:SetText(Tr(P.Suite.DataTextSources[choice] or "None"))
            buttons[slot]:SetEnabled(enabled)
        end
    end)
    return y - 43
end

local function BuildBarActions(ctx, body, bar, sectionId, y, width)
    local prefix = "bar" .. bar
    local buttonWidth = math.floor((width - 12) / 3)
    P.Button(ctx, body, "Add place", 16, y, buttonWidth,
        function() AddPlace(bar) end,
        function() return P.Get(ID, prefix .. "Enabled") and HasEmptyPlace(prefix) end,
        P.Meta(PAGE, ID, prefix .. ".addPlace", "action", sectionId))
    P.Button(ctx, body, "Move in Edit Mode", 22 + buttonWidth, y, buttonWidth,
        function() P.OpenEditMode(ID, prefix) end,
        function() return P.EditModeReady() and S.Status(ID) == "Active" and P.Get(ID, prefix .. "Enabled") end,
        P.Meta(PAGE, ID, prefix .. ".move", "action", sectionId))
    P.Button(ctx, body, "Hide bar", 28 + buttonWidth * 2, y, buttonWidth,
        function() P.Set(ID, prefix .. "Enabled", false) end,
        function() return P.Get(ID, prefix .. "Enabled") end,
        P.Meta(PAGE, ID, prefix .. ".hide", "action", sectionId))
    P.Button(ctx,body,"Remove bar",16,y-43,(width-6)/2,function()
        if P.SetMany(ID,P.Suite.DataTextBarRemovalValues(S.Config(ID),bar)) then RebuildBars() end
    end,function() return not P.Combat() end,P.Meta(PAGE,ID,prefix..".remove","action",sectionId))
    P.Button(ctx, body, "Antique Footer preset", 22+(width-6)/2, y - 43, (width-6)/2,
        function() P.SetMany(ID, P.Suite.DataTextAntiqueFooterValues(bar, S.Config(ID))) end,
        function() return S.Availability(ID) and not P.Combat() end,
        P.Meta(PAGE, ID, prefix .. ".antiqueFooter", "action", sectionId))
    return y - 86
end

-- Switching a bar to its own style starts from the current shared settings.
local function BuildBarStyle(ctx, body, bar, sectionId, y, width, rules)
    local prefix = "bar" .. bar
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
    local styleRules = rules.style
    y = P.RuleGrid(ctx, body, PAGE, ID, styleRules, y, width, nil, sectionId)
    y = Preview(ctx, body, y - 8, width, bar)
    return y
end

local function BuildBarContents(ctx, b, body, bar, sectionId, width, rules)
    local y = -18
    local help = P.Description(body, P.Help("Choose the information shown in each bar.", "Click a place to choose its text. Drag the bar in MSUF Edit Mode. Empty places disappear. The Antique Footer preset creates a bag, durability and clock strip on this bar only."),
        16, y, width)
    y = y - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 10
    y = BuildPlaces(ctx, body, bar, sectionId, y, width)
    y = BuildBarActions(ctx, body, bar, sectionId, y, width)
    y = P.RuleGrid(ctx, body, PAGE, ID, rules.layout, y, width, nil, sectionId)
    y = P.RuleGrid(ctx, body, PAGE, ID, rules.blocks, y - 8, width, nil, sectionId)
    local heading = P.Text(body, Tr("Visibility"), 16, y - 12, width, T.colors.text)
    y = y - 12 - math.max(14, math.ceil(heading:GetStringHeight() or 14)) - 6
    local loadHelp = P.Text(body,
        "Hide this bar when any selected condition is true. The health condition uses your character's health. At full health the bar is transparent but can still receive clicks. Edit Mode shows it for placement.",
        16, y, width)
    y = y - math.max(14, math.ceil(loadHelp:GetStringHeight() or 14)) - 8
    y = P.RuleGrid(ctx, body, PAGE, ID, rules.load, y, width, nil, sectionId)
    y = BuildBarStyle(ctx, body, bar, sectionId, y - 16, width, rules)
    P.FinishBody(b, body, y - 12)
end

-- Hundreds of bar controls include two skinned step buttons per slider.
-- Build only requested bodies, one per timer dispatch for restored open
-- accordions. The queue has no work/timer while idle; hidden pages are skipped.
local function BarBuildQueue(ctx)
    local jobs, first, last, scheduled = {}, 1, 0, false
    local function RunNext()
        if P.Combat() or ctx.wrapper and not ctx.wrapper:IsVisible() then
            for index = first, last do
                jobs[index].queued = nil
                jobs[index] = nil
            end
            first, last, scheduled = 1, 0, false
            return
        end
        local record = jobs[first]
        jobs[first], first = nil, first + 1
        record.queued = nil
        if record.body:IsVisible() then record.ensure() end
        if first <= last then
            C_Timer.After(0, RunNext)
        else
            first, last, scheduled = 1, 0, false
        end
    end
    return function(record)
        if record.built or record.building or record.queued or not record.body:IsVisible() or P.Combat() then return end
        record.queued = true
        last = last + 1
        jobs[last] = record
        if not scheduled then
            scheduled = true
            C_Timer.After(0, RunNext)
        end
    end
end

local function BarSection(ctx, b, bar, sections, queue)
    local prefix, sectionId = "bar" .. bar, PAGE .. "_bar" .. bar
    local body = b:CollapsibleSection(sectionId, P.Get(ID, prefix .. "Name") or Tr("Bar %d"):format(bar), 120, bar == 1)
    local width = math.max(240, (body._msuf2Width or b.width or 720) - 32)
    local toggle = P.W.SectionSwitch(body, Tr("Enable"), Tr("Enable"))
    M.BindBoolWidget(ctx, toggle,
        function() return P.Get(ID, prefix .. "Enabled") == true end,
        function(value) P.Set(ID, prefix .. "Enabled", value == true) end,
        P.Meta(PAGE, ID, prefix .. "Enabled", "setting", sectionId))
    M.TrackRefresh(ctx, function() P.W.SetControlEnabled(toggle, not P.Combat()) end)
    local rules = {
        layout = sections[prefix] or {}, blocks = sections[prefix .. "Blocks"] or {},
        load = sections[prefix .. "Load"] or {}, style = sections[prefix .. "Style"] or {},
    }
    local colors = {}
    for _, rule in ipairs(rules.style) do colors[#colors + 1] = rule end
    for _, rule in ipairs(rules.blocks) do colors[#colors + 1] = rule end
    P.AttachRuleColors(body, Tr("Bar %d"):format(bar), ID, colors)
    P.AttachSectionReset(ctx, body, Tr("Bar %d"):format(bar), function()
        return P.ResetPrefix(ID, prefix)
    end)
    P.FinishBody(b, body, -39)
    local record = { body = body }
    record.ensure = function()
        if record.built then return body end
        if record.building or P.Combat() then return nil end
        record.building = true
        local firstRefresher = #ctx.refreshers + 1
        BuildBarContents(ctx, b, body, bar, sectionId, width, rules)
        record.built, record.building = true, nil
        if ctx.entry then ctx.entry.sections[sectionId] = body end
        -- Initialize only the newly added bindings. Refreshing the entire
        -- page after every body would revisit all previously built bars.
        for index = firstRefresher, #ctx.refreshers do ctx.refreshers[index]() end
        return body
    end
    body._msuf2CollapsibleEntry._msuf2EnsureVisible = record.ensure
    -- Keep the body a virtual section until its controls exist. Menu2 invokes
    -- the exact resolver for missing sections before looking up the control,
    -- including a restored open body whose queued build has not run yet.
    if ctx.entry then ctx.entry.sections[sectionId] = nil end
    body:HookScript("OnShow", function() queue(record) end)
    M.TrackRefresh(ctx, function() queue(record) end)
    ctx.dataTextBarRows[sectionId] = record
end

local function BuildBars(ctx, b, sections)
    local queue = BarBuildQueue(ctx)
    local bars = {}
    ctx.dataTextBarRows = bars
    if ctx.entry then
        ctx.entry._msuf2ResolveMissingSection = function(sectionId)
            local record = bars[sectionId]
            return record and record.ensure() or nil
        end
    end
    for _, bar in ipairs(P.Suite.DataTextBarIDs(S.Config(ID))) do
        BarSection(ctx, b, bar, sections, queue)
    end
end

local function Build(ctx)
    local b = P.W.PageBuilder(ctx)
    local sections = {}
    for _,rule in ipairs(P.catalog[ID].getControls(S.Config(ID))) do
        if rule.section and rule.key~="enabled" and not rule.previewOnly then
            local group=sections[rule.section]
            if not group then
                group={}
                sections[rule.section]=group
            end
            group[#group+1]=rule
        end
    end
    P.ModuleCard(ctx, b, PAGE, ID, {
        { "Add bar", function()
            local index = NextBar()
            if index and P.SetMany(ID,P.Suite.DataTextBarCreationValues(S.Config(ID),index)) then RebuildBars() end
        end, function() return S.Availability(ID) and P.Get(ID, "enabled") and NextBar() ~= nil end, key = "addBar" },
        { "Move first bar", function() P.OpenEditMode(ID, "bar1") end,
          function() return P.EditModeReady() and S.Status(ID) == "Active" and P.Get(ID, "bar1Enabled") end,
          key = "move" },
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
    BuildBars(ctx, b, sections)
    P.RuleSection(ctx,b,PAGE,ID,PAGE..'_sources',Tr('Additional data sources'),P.SectionRules(ID,'sources'),{
        help='Choose broker names and discovered currency IDs per place. Select your current-season crest currencies from the native currency list; saved currency selections work after login without visiting an upgrade NPC. Selection order and separator control the crest block. Observed upgrade stages remain available as an alternative after selecting an upgrade item this login. Hearthstone actions require a deliberate click.',
        extra=function(body,y,width)
            local button
            local picker
            picker=P.Button(ctx,body,'Choose crest currencies',16,y,width,function() CrestCurrencyMenu(picker) end,
                function() return not P.Combat() end,P.Meta(PAGE,ID,'chooseCrestCurrencies','action',PAGE..'_sources'))
            button=P.Button(ctx,body,'Choose observed seasonal stages',16,y-40,width,function()
                SeasonStagesMenu(button)
            end,function() return not P.Combat() end,P.Meta(PAGE,ID,'chooseSeasonStages','action',PAGE..'_sources'))
            return y-80
        end,
    })
    P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_gold", Tr("Gold across characters"),
        P.SectionRules(ID, "gold"), {
            help = "While DataTexts and this choice are enabled, MSUF remembers this character's gold at login and after money changes. Hover a Gold or Session gold DataText to see the last known account total and up to eight other characters. No background scans are used.",
            extra = function(body, y, width)
                P.Button(ctx, body, "Clear saved character gold", 16, y, width,
                    function() P.Suite.ClearCharacterGold() end,
                    function() return type(P.Suite.RootDB) == "table" end,
                    P.Meta(PAGE, ID, "action.clearGold", "action", PAGE .. "_gold"))
                return y - 40
            end,
        })
end

P.RegisterPage({ key = PAGE, label = "DataTexts", title = "DataTexts", build = Build, icon = { 5, 2 },
    nav = "interface", navOrder = 6,
    aliases = { "datatext", "datatexts", "data bars", "info bar", "system info" } })
