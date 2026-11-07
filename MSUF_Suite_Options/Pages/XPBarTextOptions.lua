local _, P = ...
local Options = {}
P.XPBarTextOptions = Options
local ID, PAGE, SECTION = "xpBar", "suite_hud", "suite_qualityOfLife_xpBar_xp_bar"
local Specs = P.Suite.ExperienceBarLayout.Texts

function Options.BarRules(rules)
    local visible = {}
    for _, rule in ipairs(rules) do
        if not rule.xpTextRole then visible[#visible + 1] = rule end
    end
    return visible
end

local function Register(editor, spec, entries)
    for _, entry in ipairs(entries) do
        local widget, rule = entry.widget, entry.rule
        local function Prepare()
            if P.Combat() or not editor.frame:IsVisible() then return false end
            editor.select(spec.id)
            return true
        end
        local meta = P.Meta(PAGE, ID, rule.key, "setting", SECTION)
        meta.pageKey, meta.label = PAGE, P.Tr(rule.label)
        meta.keywords = { spec.label, rule.label, "Experience bar" }
        meta.kind = (rule.font or rule.texture or rule.choices) and "dropdown" or "slider"
        P.HM.SetSearchTargetPrepare(widget, Prepare)
        P.M.RegisterSearchWidget(widget, meta)
    end
end

function Options.Build(ctx, parent, y, width, select)
    local editor = { views = {}, selected = "percent", select = select }
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    frame:SetWidth(width)
    editor.frame = frame
    local values = {}
    for _, spec in ipairs(Specs) do values[#values + 1] = { value = spec.id, text = P.Tr(spec.label), width = 130 } end
    editor.selector = P.W.ScopeOverrideBar(ctx, frame, {
        label = "", labelWidth = 0, startX = 0, width = width, maxRight = width,
        values = values, getValue = function() return editor.selected end, setValue = select,
    })
    editor.selector.label:Hide()
    for _, button in ipairs(editor.selector.buttons) do P.HM.SkipHistoryCheckpoint(button) end
    P.M.RegisterControlMetadata(editor.selector, P.Meta(PAGE, ID, "preview.textElement", "ephemeral", SECTION),
        "Text element", "segment")
    local top = editor.selector:GetLayoutMetrics().bottomY
    local height = 0
    for _, spec in ipairs(Specs) do
        local body, rules = CreateFrame("Frame", nil, frame), {}
        body:SetPoint("TOPLEFT", frame, "TOPLEFT", -16, top - 12)
        body:SetWidth(width + 32)
        for _, rule in ipairs(P.catalog[ID].controls) do
            if rule.xpTextRole == spec.id then rules[#rules + 1] = rule end
        end
        local bottom, entries = P.RuleGrid(ctx, body, PAGE, ID, rules, 0, width, nil, SECTION, nil, nil, true)
        body:SetHeight(-bottom + 12)
        editor.views[spec.id] = body
        height = math.max(height, -bottom + 12)
        Register(editor, spec, entries)
        body:SetShown(spec.id == editor.selected)
    end
    frame:SetHeight(math.abs(top) + height + 24)
    function editor:Select(id)
        if not self.views[id] then return end
        self.selected = id
        for key, body in pairs(self.views) do body:SetShown(key == id) end
        self.selector:Refresh()
    end
    return editor, y - frame:GetHeight() - 12
end
