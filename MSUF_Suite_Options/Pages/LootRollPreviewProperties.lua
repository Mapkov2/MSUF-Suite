local _, P = ...
-- The selected loot row element's size, in the style of the XP bar and meter
-- previews: the element's real setting row (history, search, reset) under the
-- X/Y bar, one element at a time. 0 keeps the automatic size. Nothing here
-- runs per frame; a change repaints the preview once through the page refresh.
local Properties = {}
P.LootRollPreviewProperties = Properties
local ID = "lootRolls"

-- The feature's settings grid leaves the element sizes to the preview.
function Properties.GridRules(rules)
    local grid = {}
    for _, rule in ipairs(rules) do
        if not rule.lootElement then grid[#grid + 1] = rule end
    end
    return grid
end

function Properties.Show(editor, id)
    local views = editor.sizeViews
    if not views or not views[id] or editor.sizeShown == id then return end
    editor.sizeShown = id
    for key, body in pairs(views) do body:SetShown(key == id) end
end

-- Search finds an element's size: reveal the feature, then show that element.
local function Register(editor, element, entries, page, section)
    for _, entry in ipairs(entries) do
        local rule = entry.rule
        local meta = P.Meta(page, ID, rule.key, "setting", section)
        meta.pageKey, meta.label, meta.kind = page, P.Tr(rule.label), "slider"
        meta.keywords = { element.label, rule.label, "Loot roll window" }
        P.HM.SetSearchTargetPrepare(entry.widget, function()
            if P.Combat() then return false end
            local group = P.QoLView.FindFeature(ID)
            if group and group.reveal and group.reveal(true) == nil then return false end
            Properties.Show(editor, element.id)
            return true
        end)
        P.M.RegisterSearchWidget(entry.widget, meta)
    end
end

function Properties.Build(editor, parent, y, width)
    local group = P.QoLView.FindFeature(ID)
    local page, section = P.QoLView.GetFeaturePage(group), P.QoLView.FeatureSectionId(group)
    local rules = P.catalog[ID].rules
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    editor.sizeViews = {}
    local height = 0
    for _, element in ipairs(P.Suite.LootRollElements) do
        local body = CreateFrame("Frame", nil, panel)
        body:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        body:SetWidth(width + 32)
        local bottom, entries = P.RuleGrid(editor.ui.ctx, body, page, ID, { rules[element.sizeKey] }, 0, width,
            nil, section, nil, nil, true)
        body:SetHeight(-bottom)
        height = math.max(height, -bottom)
        Register(editor, element, entries, page, section)
        body:Hide()
        editor.sizeViews[element.id] = body
    end
    panel:SetSize(width + 32, height)
    Properties.Show(editor, "name")
    return y - height - 4
end
