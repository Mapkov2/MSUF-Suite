local _, P = ...
local Content = P.Suite.TooltipContent
local PAGE, MODULE = "suite_tooltips", "tooltipDetails"
local SECTION = "suite_tooltip_content_order"

local function Shift(kind, row, direction)
    local id = Content.Fields[kind]
    local groups = Content.Order(kind, P.Get(MODULE, id))
    local nextRow = row + direction
    if nextRow < 1 or nextRow > #groups then return end
    groups[row], groups[nextRow] = groups[nextRow], groups[row]
    P.Set(MODULE, id, table.concat(groups, ","))
end

local function BuildRows(ctx, body, y, width, kind)
    local definitions = Content.Groups(kind)
    local labels = {}
    for _, def in ipairs(definitions) do labels[def[1]] = def[2] end
    local active, names = nil, {}
    local actionsWidth = math.min(110, math.floor(width / 4))
    for index = 1, #definitions do
        local row = index
        names[row] = P.Text(body, "", 16, y - 4, width - 2 * actionsWidth - 24, nil, "section")
        P.Button(ctx, body, "Move earlier", 16 + width - 2 * actionsWidth - 8, y, actionsWidth,
            function() Shift(kind, row, -1) end, function() return row > 1 end)
        P.Button(ctx, body, "Move later", 16 + width - actionsWidth, y, actionsWidth,
            function() Shift(kind, row, 1) end, function() return row < #definitions end)
        y = y - 30
    end
    local function Paint()
        local nextOrder = P.Get(MODULE, Content.Fields[kind])
        if active == nextOrder then return end
        active = nextOrder
        for index, key in ipairs(Content.Order(kind, active)) do names[index]:SetText(labels[key]) end
    end
    active = false
    P.M.TrackRefresh(ctx, Paint)
    Paint()
    return y
end

local function Body(ctx, body, width)
    local y = -14
    P.Text(body, "Unit tooltip", 16, y, width, nil, "section")
    y = BuildRows(ctx, body, y - 24, width, "unit")
    P.Text(body, "Creature tooltip", 16, y, width, nil, "section")
    y = BuildRows(ctx, body, y - 24, width, "creature")
    P.Text(body, "Item tooltip", 16, y, width, nil, "section")
    y = BuildRows(ctx, body, y - 24, width, "item")
    P.Button(ctx, body, "Reset content order", 16, y - 6, math.min(216, width), function()
        P.SetMany(MODULE, { unitContentOrder = "", creatureContentOrder = "", itemContentOrder = "" })
    end)
    return -y + 44
end

function P.BuildTooltipContentOrder(ctx, builder)
    local title = P.Tr("Tooltip content order")
    if ctx.searchRows then
        P.SkinSearchRow(ctx, { pageKey = PAGE, kind = "section", label = title }, SECTION, title)
        return
    end
    P.LazySection(builder, SECTION, title, false, {
        description = P.Tr("Choose the order of the details added by MSUF."),
        content = function(body)
            local width = math.max(250, (P.HM.GetSectionWidth(body) or builder.width or 720) - 32)
            return Body(ctx, body, width)
        end,
    })
end
