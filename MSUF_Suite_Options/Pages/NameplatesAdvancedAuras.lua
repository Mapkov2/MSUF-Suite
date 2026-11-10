local _, P = ...
local UI = {}
P.NameplatesAdvancedAuras = UI
local Model, Style = P.Suite.NameplateAuraDisplay, P.Suite.NameplateStyle
local Tr = P.Tr
local PAGE, ID = "suite_nameplates", "nameplates"
local SECTION = PAGE .. "_auraWorkspace"
local previews = setmetatable({}, { __mode = "k" })
local OUTLINE = { "", "OUTLINE", "THICKOUTLINE" }
local SAMPLE_TEXTURES = {
    [1] = { "Interface\\Icons\\Spell_Holy_Renew", "Interface\\Icons\\Spell_Holy_WordFortitude", "Interface\\Icons\\Spell_Nature_Rejuvenation" },
    [2] = { "Interface\\Icons\\Spell_Shadow_ShadowWordPain", "Interface\\Icons\\Spell_Shadow_VampiricEmbrace",
        "Interface\\Icons\\Spell_Fire_Immolation" },
}
-- The preview's own Blizzard aura samples a Visible lane paints over.
local SAMPLE_HOST = { Buffs = "buffs", Auras = "auras" }
local LIST_LABELS = {
    lane = { add = "Add blocked aura", remove = "Remove blocked aura", empty = "No auras blocked." },
    custom = { add = "Add allowed aura", remove = "Remove allowed aura",
        empty = "No spells tracked. Add up to 40 exact SpellIDs." },
    dots = { add = "Add custom tracked aura", remove = "Remove custom tracked aura",
        empty = "No DoT selected. Choose one above or add a custom Spell ID." },
}
local LIST_TOOLS = { blacklist = true, whitelist = true, dots = true }
local WORKSPACE_HINT = "Aura Options, Ordering and Aura Style belong to these plates. Shared icon appearance: Style."
-- The workspace view: which plates, which container and, per container
-- kind, which tool. Menu state only; nothing here is saved.
local view = { scope = "enemy", container = "buff", tools = { lane = "layout", custom = "setup", dots = "setup" } }
local selectView, revealWorkspace, nativeHelp

local function WorkspaceKeys()
    local keys, seen = { "auraDisplayEnabled" }, { auraDisplayEnabled = true }
    for _, scope in ipairs(Model.Scopes) do
        for _, container in ipairs(Model.Containers) do
            for _, tool in ipairs(Model.Tools[container.kind]) do
                for _, key in ipairs(Model.ToolKeys(scope, container, tool)) do
                    if not seen[key] then keys[#keys + 1], seen[key] = key, true end
                end
            end
        end
    end
    return keys
end

-- Every aura setting of the nameplates lives in one workspace, built like
-- MSUF's unit frame Auras: Container, Edit, one tool. Buffs and Debuffs are
-- Blizzard's own lists until they are made Visible; Custom 1-3 and Dots on
-- target are the Suite's containers. help: the page's help texts
-- (help.auras explains Blizzard's settings).
function UI.Append(sections, help)
    nativeHelp = help and help.auras
    sections[#sections + 1] = { key = "auraWorkspace", area = "auras", title = "Auras", keys = WorkspaceKeys(),
        colors = Model.ColorKeys, build = UI.Build, prepare = UI.PrepareSearch }
end

function UI.Lookup(query)
    if type(query) ~= "string" or query == "" or #query > 128 then return end
    local id = tonumber(query) or C_Spell.GetSpellIDForSpellIdentifier(query)
    if not P.Suite.Public(id) or type(id) ~= "number" or id < 1 or id >= 2147483648 or id ~= math.floor(id) then return end
    local name, icon = C_Spell.GetSpellName(id), C_Spell.GetSpellTexture(id)
    if not P.Suite.Public(name) or type(name) ~= "string" then return end
    return { value = id, text = string.format(Tr("%s (Aura %d)"), name, id), icon = P.Suite.Public(icon) and icon or 134400 }
end

local function SpellValues(ids)
    local values = {}
    for _, id in ipairs(ids) do
        values[#values + 1] = UI.Lookup(tostring(id)) or {
            value = id, text = string.format(Tr("Check the ID for unknown aura %d"), id), icon = 134400 }
    end
    return values
end

local function Suggestions(lookup)
    local values, seen = {}, {}
    if lookup and lookup.value then values[1], seen[lookup.value] = lookup, true end
    -- The same curated/native DoT suggestions as the aura-color picker.
    for _, row in ipairs(P.Suite.NameplateAuraColors.Suggestions()) do
        if not seen[row.id] then
            local value = UI.Lookup(tostring(row.id))
            if value then values[#values + 1], seen[row.id] = value, true end
        end
    end
    return values
end

-- A list edit writes this client's list only (Model.ListKey). Adding a custom
-- DoT also selects the custom list as the container's source.
local function ChangeList(scope, container, id, remove)
    if P.Combat() or not P.Get(ID, "auraDisplayEnabled") then return end
    local key = Model.ListKey(scope, container)
    local ids, set = Model.IDs(P.Get(ID, key))
    if remove then
        for index = #ids, 1, -1 do if ids[index] == id then table.remove(ids, index) end end
    elseif not set[id] and #ids < Model.MAX_ICONS then
        ids[#ids + 1] = id
    end
    local value = table.concat(ids, ",")
    local source = Model.Prefix(scope, container) .. "Source"
    if not remove and P.catalog[ID].rules[source] then return P.SetMany(ID, { [key] = value, [source] = 2 }) end
    return P.Set(ID, key, value)
end

local function ListRow(scope, container, label, remove, lookup)
    local key = Model.ListKey(scope, container)
    local row = P.Meta(PAGE, ID, "action." .. key .. (remove and "Remove" or "Add"), "action", SECTION)
    row.id, row.label, row.kind = key .. (remove and "Remove" or "Add"), Tr(label), "dropdown"
    row.get = function() return nil end
    row.values = function()
        if remove then return SpellValues(Model.IDs(P.Get(ID, key))) end
        return Suggestions(lookup.match)
    end
    row.set = function(id)
        if P.Suite.Public(id) and type(id) == "number" and #Model.IDs(tostring(id), 1) == 1 then
            ChangeList(scope, container, id, remove)
        end
    end
    return row
end

local function ListSummary(scope, container)
    local ids = Model.IDs(P.Get(ID, Model.ListKey(scope, container)))
    if #ids == 0 then return Tr(LIST_LABELS[container.kind].empty) end
    local names = {}
    for index, value in ipairs(SpellValues(ids)) do names[index] = value.text end
    return table.concat(names, ", ")
end

-- The aura list of one container on this client: find by name or ID, add and
-- remove through the host's dropdown rows, and the list in stored order.
local function SpellList(ctx, panel, y, width, scope, container)
    local key, labels, lookup, query = Model.ListKey(scope, container), LIST_LABELS[container.kind], {}, ""
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y - 60)
    icon:SetTexture(134400)
    local found = P.Text(panel, "", 42, y - 63, width - 28)
    local function Lookup(value)
        query = value or ""
        lookup.match = UI.Lookup(query)
        icon:SetTexture(lookup.match and lookup.match.icon or 134400)
        P.SetTranslatedText(found, lookup.match and lookup.match.text or Tr("Enter a spell name or valid aura ID."))
        P.Refresh()
    end
    local input = P.M.BindTextInputAt(ctx, panel, Tr("Find aura by name or ID"), 16, y, width,
        function() return query end, Lookup, true, P.Meta(PAGE, ID, "action." .. key .. "Lookup", "action", SECTION))
    input:SetOnValueCommitted(Lookup)
    input:SetMaxLetters(128)
    P.SetTranslatedText(found, Tr("Enter a spell name or valid aura ID."))
    local rows = { ListRow(scope, container, labels.add, false, lookup), ListRow(scope, container, labels.remove, true, lookup) }
    local grid = P.W.SettingsRows(ctx, panel, { x = 16, y = y - 92, width = width, columns = 2, rows = rows })
    local summary = P.Text(panel, "", 16, grid.bottomY - 8, width)
    local shown
    P.M.TrackRefresh(ctx, function()
        local enabled = P.Get(ID, "auraDisplayEnabled") and not P.Combat()
        for _, row in ipairs(rows) do grid.controls[row.id]:SetEnabled(enabled) end
        local stored = P.Get(ID, key)
        if stored ~= shown then
            shown = stored
            P.SetTranslatedText(summary, ListSummary(scope, container))
        end
    end)
    return grid.bottomY - 64
end

-- The rule with its short label: inside the workspace the bars already name
-- the plates and the container. Identity, gates and values stay the rule's.
local function Short(rule)
    if not rule.short then return rule end
    return setmetatable({ label = rule.short }, { __index = rule })
end

local function Grid(ctx, panel, keys, y, width, columns)
    local rules, catalog = {}, P.catalog[ID].rules
    for _, key in ipairs(keys) do
        local rule = catalog[key]
        if rule and P.catalog[ID].controlAvailable(rule) then rules[#rules + 1] = Short(rule) end
    end
    if #rules == 0 then return y end
    return (P.RuleGrid(ctx, panel, PAGE, ID, rules, y, width, nil, SECTION, columns))
end

local function Heading(panel, text, y, width)
    local heading = P.Text(panel, text, 16, y, width, nil, "section")
    heading:SetJustifyH("CENTER")
    return y - 28
end

-- One tool of one container, in MSUF's control order and with its titles
-- ("Buff Layout", "Custom 1 Setup").
local function BuildTool(ctx, panel, width, scope, container, tool)
    local title = Tr(container.title or container.label) .. " " .. Tr(Model.ToolLabels[tool])
    local keys, y = Model.ToolKeys(scope, container, tool, true), Heading(panel, title, -12, width)
    if tool == "layout" then
        -- Visible (a lane), Anchor and Growth in one row, the numbers below.
        local head, numbers = {}, {}
        for _, key in ipairs(keys) do
            local field = key:sub(#Model.Prefix(scope, container) + 1)
            local list = (field == "Visible" or field == "Anchor" or field == "Growth") and head or numbers
            list[#list + 1] = key
        end
        y = Grid(ctx, panel, head, y, width, width >= 620 and #head or 2)
        y = Grid(ctx, panel, numbers, y, width, width >= 620 and 4 or 2)
        local note = P.Text(panel, "Position is controlled by the colored aura handle in the preview.", 16, y - 4, width)
        return y - 8 - math.max(14, math.ceil(note:GetStringHeight() or 14))
    end
    y = Grid(ctx, panel, keys, y, width)
    if LIST_TOOLS[tool] then y = SpellList(ctx, panel, y - 6, width, scope, container) end
    return y
end

local function Rules(keys)
    return function(ctx, panel, width) return Grid(ctx, panel, keys, -4, width) end
end

-- Blizzard's own settings under a lane's Layout: which plate kinds show the
-- lane, and the size of the icons while Blizzard draws them.
local function NativeParts(parts, scope, lane)
    local modes, switches, shared = Model.NativeKeys(scope, lane)
    parts[#parts + 1] = { key = "blizzard", build = function(_, panel, width)
        local y = Heading(panel, "Blizzard auras", -12, width)
        if not nativeHelp then return y end
        local text = P.Description(panel, nativeHelp, 16, y, width, Tr("Blizzard auras"))
        return y - math.max(14, math.ceil(text:GetStringHeight() or 14)) - 8
    end }
    parts[#parts + 1] = { key = "modes:" .. scope.key, build = Rules(modes) }
    parts[#parts + 1] = { key = "switches:" .. scope.key .. ":" .. lane.key, build = Rules(switches) }
    parts[#parts + 1] = { key = "shared", build = Rules(shared) }
end

-- The stacked parts of a view: the master switch, the tool, and what the
-- tool shares with other views. A shared part is built once and shown under
-- every view that has it, so each setting keeps exactly one control:
-- Blizzard's settings under a lane's Layout, the shared look under Style.
local function Parts(scope, container, tool)
    local parts = {
        { key = "master", build = Rules({ "auraDisplayEnabled" }) },
        { key = scope.key .. ":" .. container.key .. ":" .. tool,
            build = function(ctx, panel, width) return BuildTool(ctx, panel, width, scope, container, tool) end },
    }
    if container.kind == "lane" and tool == "layout" then
        NativeParts(parts, scope, container)
    elseif tool == "style" then
        parts[#parts + 1] = { key = "appearance", build = function(ctx, panel, width)
            return Grid(ctx, panel, Model.AppearanceKeys, Heading(panel, "Shared aura appearance", -12, width), width)
        end }
    end
    return parts
end

local function Values(list, key, label)
    local values = {}
    for _, item in ipairs(list) do values[#values + 1] = { value = key and item[key] or item, text = label and label(item) or item.label } end
    return values
end

local function Kind()
    return Model.Container(view.container).kind
end

local function ToolValues(kind)
    return Values(Model.Tools[kind], nil, function(tool) return Model.ToolLabels[tool] end)
end

local function SetBarShown(bar, shown)
    bar:SetShown(shown)
    bar.label:SetShown(shown)
    for _, button in ipairs(bar.buttons) do button:SetShown(shown) end
end

-- MSUF's Container and Edit bars (7.0 hosts). select: shows the view.
local function Bars(ctx, body, width, select)
    local W, top = P.W, -28
    local function Bar(label, values, centerY, get, set)
        local bar = W.ScopeOverrideBar(ctx, body, { values = values, width = width + 32, label = label, labelWidth = 72,
            centerY = centerY, getValue = get, setValue = function(value)
                set(value)
                select()
            end })
        local metrics = bar:GetLayoutMetrics()
        return bar, metrics and metrics.bottomY or centerY - 14
    end
    local _, bottom = Bar("Plates:", Values(Model.Scopes, "key"), top, function() return view.scope end,
        function(value) view.scope = value end)
    top = math.min(top - 34, bottom - 22)
    _, bottom = Bar("Container:", Values(Model.Containers, "key"), top, function() return view.container end,
        function(value) view.container = value end)
    top = math.min(top - 34, bottom - 22)
    local tools, lowest = {}, top
    for kind in pairs(Model.Tools) do
        tools[kind], bottom = Bar("Edit:", ToolValues(kind), top, function() return view.tools[kind] end,
            function(value) view.tools[kind] = value end)
        lowest = math.min(lowest, bottom)
    end
    return lowest - 2, function()
        for kind, bar in pairs(tools) do SetBarShown(bar, kind == Kind()) end
    end
end

-- Hosts without that bar get the same three choices as dropdown rows.
local function Dropdowns(ctx, body, width, select)
    local function Row(key, label, values, get, set)
        local row = P.Meta(PAGE, ID, "action.auraWorkspace." .. key, "action", SECTION)
        row.id, row.label, row.kind, row.values, row.get = "auraWorkspace" .. key, Tr(label), "dropdown", values, get
        row.set = function(value)
            set(value)
            select()
        end
        return row
    end
    local rows = {
        Row("Scope", "Plates", function() return Values(Model.Scopes, "key") end, function() return view.scope end,
            function(value) view.scope = value end),
        Row("Container", "Container", function() return Values(Model.Containers, "key") end,
            function() return view.container end, function(value) view.container = value end),
        Row("Tool", "Edit", function() return ToolValues(Kind()) end, function() return view.tools[Kind()] end,
            function(value) view.tools[Kind()] = value end),
    }
    local grid = P.W.SettingsRows(ctx, body, { x = 16, y = -18, width = width, columns = width >= 560 and 3 or 1, rows = rows })
    return grid.bottomY, function() end
end

-- MSUF's footer: the hint and the way to the shared icon appearance, which
-- here is the lower half of the Style tool.
local function Footer(ctx, body, width, y, select)
    P.Button(ctx, body, "Global Aura Appearance", width - 154, y, 170, function()
        view.tools[Kind()] = "style"
        select()
    end, nil, P.Meta(PAGE, ID, "action.auraWorkspace.appearance", "action", SECTION))
    local hint = P.Text(body, WORKSPACE_HINT, 16, y - 4, width - 190)
    return y - math.max(34, math.ceil(hint:GetStringHeight() or 14) + 10) - 8
end

local function ContainerOf()
    return Model.Scope(view.scope), Model.Container(view.container)
end

local function Content(ctx, builder, body)
    local width = math.max(240, (P.HM.GetSectionWidth(body) or builder.width or 720) - 32)
    local built, top, showTools = {}, nil, nil
    local function Part(part)
        if not built[part.key] and not P.Combat() then
            local frame = CreateFrame("Frame", nil, body)
            frame:SetSize(width + 32, 100)
            local height = -part.build(ctx, frame, width)
            frame:SetHeight(height)
            built[part.key] = { frame = frame, height = height }
        end
        return built[part.key]
    end
    local function Select(first)
        local scope, container = ContainerOf()
        local y, shown = top, {}
        for _, part in ipairs(Parts(scope, container, view.tools[container.kind])) do
            local entry = Part(part)
            if entry then
                entry.frame:ClearAllPoints()
                entry.frame:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
                shown[entry], y = true, y - entry.height
            end
        end
        for _, entry in pairs(built) do entry.frame:SetShown(shown[entry] == true) end
        showTools()
        if not first then
            P.FinishBody(builder, body, y - 14)
            P.Refresh()
        end
        return y - 14
    end
    selectView = function() Select() end
    if P.W.ScopeOverrideBar then
        top, showTools = Bars(ctx, body, width, selectView)
    else
        top, showTools = Dropdowns(ctx, body, width, selectView)
    end
    top = Footer(ctx, body, width, top - 8, selectView)
    local colors, catalog = {}, P.catalog[ID].rules
    for _, key in ipairs(Model.ColorKeys) do colors[#colors + 1] = catalog[key] end
    P.AttachRuleColors(body, Tr("Auras"), ID, colors)
    return Select(true)
end

-- Resets what the shown container owns. A lane also resets its Blizzard
-- switches and the dragged position it shares with Blizzard's list; the mode
-- of a plate kind stays, the other lane shares it.
local function ResetView()
    local scope, container = ContainerOf()
    local rules = P.SectionRules(ID, Model.Prefix(scope, container))
    if container.kind ~= "lane" then return P.ResetRules(ID, rules) end
    local _, switches = Model.NativeKeys(scope, container)
    for _, key in ipairs(switches) do
        local rule = P.catalog[ID].rules[key]
        if rule then rules[#rules + 1] = rule end
    end
    return P.ResetRules(ID, rules, nil, P.NameplateAuraPositionKeys(scope.key, container.elements))
end

-- A search hit or a preview click on an aura setting opens its view.
local index
function UI.PrepareSearch(key)
    if not index then
        index = { auraDisplayEnabled = { view.scope, view.container, view.tools[Kind()] } }
        for _, scope in ipairs(Model.Scopes) do
            for _, container in ipairs(Model.Containers) do
                for _, tool in ipairs(Model.Tools[container.kind]) do
                    for _, name in ipairs(Model.ToolKeys(scope, container, tool)) do
                        index[name] = index[name] or { scope.key, container.key, tool }
                    end
                end
            end
        end
        for _, name in ipairs(Model.ColorKeys) do index[name] = { "enemy", "buff", "style" } end
    end
    local target = index[key]
    if not target then return end
    view.scope, view.container = target[1], target[2]
    view.tools[Kind()] = target[3]
    if revealWorkspace then revealWorkspace() end
end

function UI.Build(ctx, builder, spec)
    local pageEntry = P.M.cache and P.M.cache[PAGE]
    selectView, revealWorkspace = nil, nil
    return P.LazySection(builder, SECTION, Tr(spec.title), true, {
        content = function(body) return Content(ctx, builder, body) end,
        shell = function(body)
            revealWorkspace = function()
                if P.M.cache and P.M.cache[PAGE] ~= pageEntry or P.Combat() then return end
                local entry = P.HM.GetSectionEntry(body)
                local reveal = entry and P.HM.GetSectionEnsureVisible(entry)
                if reveal then reveal() end
                if not selectView then P.EnsureSectionContent(body) end
                if selectView then selectView() end
            end
            P.AttachSectionReset(ctx, body, Tr(spec.title), ResetView)
        end,
        finish = function(body, y) P.FinishBody(builder, body, y) end,
    })
end

local function SampleIcon(parent)
    local frame = CreateFrame("Frame", nil, parent)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(frame)
    local swipe = frame:CreateTexture(nil, "OVERLAY")
    swipe:SetColorTexture(0, 0, 0, .4)
    swipe:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
    swipe:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    local textHost = CreateFrame("Frame", nil, frame)
    textHost:SetAllPoints(frame)
    textHost:SetFrameLevel(frame:GetFrameLevel() + 1)
    return { frame = frame, icon = icon, swipe = swipe, border = Style.CreateBorder(frame),
        Time = textHost:CreateFontString(nil, "OVERLAY"), Stack = textHost:CreateFontString(nil, "OVERLAY") }
end

local function SampleText(part, plan, c, field, sample)
    local values, label, text = plan.values, part[field], c.text[field]
    P.StylePreviewFont(label, plan.font, text.size, OUTLINE[values.auraTextOutline])
    label:ClearAllPoints()
    label:SetPoint(text.point, part.frame, text.point, text.x, text.y)
    label:SetTextColor(P.RGB(values["aura" .. field .. "Color"]))
    label:SetText(sample)
    label:SetShown(values["aura" .. field .. "Text"] and c[field == "Time" and "timeText" or "stackText"])
end

local function PaintIcon(part, plan, c, index, missing)
    local values = plan.values
    local helpful = c.kind == "lane" and c.key == "buff" or values[c.prefix .. "Type"] == 1
    local textures = SAMPLE_TEXTURES[helpful and 1 or 2]
    part.frame:SetSize(c.width, c.height)
    part.icon:SetTexture(textures[(index - 1) % #textures + 1])
    part.icon:SetTexCoord(c.crop, 1 - c.crop, c.crop, 1 - c.crop)
    part.icon:SetDesaturated(missing)
    part.frame:SetAlpha(missing and c.missingAlpha / 100 or c.alpha)
    part.swipe:SetHeight(c.height * .35)
    part.swipe:SetAlpha(values.auraSwipeAlpha / 100)
    part.swipe:SetShown(values.auraSwipe and c.swipe and not missing)
    SampleText(part, plan, c, "Time", index == 1 and "7" or "12")
    SampleText(part, plan, c, "Stack", index == 1 and "3" or "2")
    if missing then
        part.Time:Hide()
        part.Stack:Hide()
    end
    local color
    if index == 1 and values.auraPandemicHighlight and c.pandemic then color = values.auraPandemicColor
    elseif index == 2 and values.auraDispelHighlight and c.dispel then color = "66aaff" end
    Style.PaintBorder(part.border, part.frame, color and not missing and values.auraHighlightSize or 0, color)
    part.frame:Show()
end

-- A fixed container shows every slot, the last one missing; a packed one
-- shows up to three active sample auras.
local function PaintIcons(record, parent, plan, c)
    local count = c.fixed and c.count or math.min(c.max, 3)
    for index = 1, count do
        local part = record.icons[index] or SampleIcon(parent)
        record.icons[index] = part
        local missing = c.fixed and index == count and count > 1
        PaintIcon(part, plan, c, index, missing)
        local x, y = Model.SlotOffset(c, index)
        part.frame:ClearAllPoints()
        part.frame:SetPoint(c.flowPoint, parent, c.flowPoint, x, y)
        part.frame:SetShown(not missing or c.missing)
    end
    for index = count + 1, #record.icons do record.icons[index].frame:Hide() end
end

local function PaintContainer(record, sample, plan, c, facts)
    record.frame:SetShown(c.enabled and facts.show ~= false)
    record.frame:ClearAllPoints()
    record.frame:SetPoint(c.point, sample.bar, c.relative, c.x, c.y)
    record.frame:SetSize(c.gridWidth, c.gridHeight)
    PaintIcons(record, record.frame, plan, c)
end

-- A Visible lane paints over the preview's own Blizzard sample of its kind:
-- the same host, handle and position. Switched off, the sample returns.
local function PaintLane(state, sample, plan, c)
    local host = sample[SAMPLE_HOST[c.element]]
    local record = state.lanes[c.key]
    if not c.enabled then
        if record and record.painted then
            record.overlay:Hide()
            host:SetSize(record.width, record.height)
            for _, original in ipairs(record.originals) do original.region:SetAlpha(original.alpha) end
            record.painted = false
        end
        return
    end
    if not record then
        record = { icons = {}, originals = {}, width = host:GetWidth(), height = host:GetHeight() }
        for _, region in ipairs({ host:GetRegions() }) do
            record.originals[#record.originals + 1] = { region = region, alpha = region:GetAlpha() }
        end
        record.overlay = CreateFrame("Frame", nil, host)
        record.overlay:SetAllPoints(host)
        state.lanes[c.key] = record
    end
    for _, original in ipairs(record.originals) do original.region:SetAlpha(0) end
    host:SetSize(c.gridWidth, c.gridHeight)
    host:SetScale(1)
    host:ClearAllPoints()
    host:SetPoint(c.point, sample.bar, c.relative, c.x, c.y)
    record.overlay:Show()
    record.painted = true
    PaintIcons(record, record.overlay, plan, c)
end

local function HidePreview(state)
    for _, record in pairs(state.containers) do record.frame:Hide() end
end

-- Call after the ordinary sample renderer. facts.show hides the Suite-only
-- containers; an optional facts.specID chooses a saved DoT selection, else
-- the first saved specialization illustrates it. No live aura,
-- specialization or CVar API is read. Every returned container frame can be
-- bound to the editor's XY handles; a lane keeps Blizzard's handle.
function UI.Preview(sample, config, facts)
    local state = previews[sample]
    local on = config.auraDisplayEnabled and config.look ~= 2 and config[sample.prefix]
    if not on and not state then return end
    facts = facts or {}
    local plan = Model.Plan(on and config or {}, facts)
    plan.font = P.Suite.ResolveFont(plan.values.auraFont) or P.Suite.GlobalFontPath()
    if not state then
        state = { containers = {}, lanes = {} }
        previews[sample] = state
    end
    for _, c in ipairs(plan.scopes[sample.prefix]) do
        if c.kind == "lane" then
            PaintLane(state, sample, plan, c)
        elseif on then
            local record = state.containers[c.key]
            if not record then
                record = { frame = CreateFrame(sample.static and "Frame" or "Button", nil, sample.cell), icons = {} }
                state.containers[c.key] = record
            end
            PaintContainer(record, sample, plan, c, facts)
        end
    end
    if not on then HidePreview(state) end
    return on and state or nil
end

-- The Dots handle keeps the editor's Tracked element (size and settings
-- shortcuts, NameplatesSize.lua and NameplatesEditor.lua).
function UI.Render(editor, sample, metrics)
    local facts = sample.auraPreviewFacts or {}
    sample.auraPreviewFacts = facts
    facts.show = not metrics.namesOnly and editor:LayerOn("auras")
    local state = UI.Preview(sample, P.S.Config(ID), facts)
    sample.auraPreviewState = state
    if not state or state.bound or sample.static then return end
    local scope = Model.Scope(sample.prefix)
    for _, container in ipairs(Model.Containers) do
        local record = state.containers[container.key]
        if record then
            local prefix = Model.Prefix(scope, container)
            editor:Bind(record.frame, sample.prefix .. "." .. container.element,
                Tr("%s: %s"):format(Tr(scope.label), Tr(container.label)), prefix .. "OffsetX", prefix .. "OffsetY", prefix)
        end
    end
    state.bound = true
end
