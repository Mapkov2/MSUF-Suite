local _, P = ...
local S = P.Suite
-- Pooled bar rows. Styling (fonts, anchors, textures) runs only when the
-- style generation changes; painting writes content, memoizes plain values
-- and hands secret values straight to C sinks (StatusBar, FontString,
-- AbbreviateNumbers). Secrets are never compared, stored as memo or used as keys.
local D = P.DamageMeter
local M = D.M
local Public, Finite, Num = S.Public, S.Finite, D.Num
-- The client's secret test (Platform.lua) for the row paint.
local IsSecret = P.NS.IsSecret
-- The one native formatter of every amount, plain or secret (Data.lua).
local Abbreviate = D.Abbreviate
local TYPE, ICON, ROW_BORDER, VALUE_FORMAT = D.TYPE, D.ICON, D.ROW_BORDER, D.VALUE_FORMAT
local floor, format = math.floor, string.format
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local gradientDirections = {
    { "gradientLeft", "HORIZONTAL", true },
    { "gradientRight", "HORIZONTAL", false },
    { "gradientUp", "VERTICAL", false },
    { "gradientDown", "VERTICAL", true },
}
local ranks = setmetatable({}, {
    __index = function(list, index)
        local text = index .. "."
        list[index] = text
        return text
    end
})
D.ranks = ranks
local separators = { [VALUE_FORMAT.PARENTHESES] = "%s (%s)", [VALUE_FORMAT.BAR] = "%s | %s" }
-- The values of the custom layout, in the valueOrder choices' order.
local TOTAL, RATE, PERCENT = 1, 2, 3
local customOrders = {
    { TOTAL, RATE, PERCENT }, { TOTAL, PERCENT, RATE }, { RATE, TOTAL, PERCENT },
    { RATE, PERCENT, TOTAL }, { PERCENT, TOTAL, RATE }, { PERCENT, RATE, TOTAL },
}
-- Select only the configured arguments, keeping their count exact for native text sinks.
local customArguments = {
    [1] = function(total) return total end,
    [12] = function(total, rate) return total, rate end,
    [13] = function(total, _, percent) return total, percent end,
    [21] = function(total, rate) return rate, total end,
    [31] = function(total, _, percent) return percent, total end,
    [123] = function(total, rate, percent) return total, rate, percent end,
    [132] = function(total, rate, percent) return total, percent, rate end,
    [213] = function(total, rate, percent) return rate, total, percent end,
    [231] = function(total, rate, percent) return rate, percent, total end,
    [312] = function(total, rate, percent) return percent, total, rate end,
    [321] = function(total, rate, percent) return percent, rate, total end,
}
local customPatterns = {
    { "%s", "%s %s", "%s %s %s" },
    { "%s", "%s (%s)", "%s (%s) (%s)" },
    { "%s", "%s [%s]", "%s [%s] [%s]" },
    { "%s", "%s | %s", "%s | %s | %s" },
    { "%s", "%s / %s", "%s / %s / %s" },
    { "%s", "%s - %s", "%s - %s - %s" },
}

local function NewValueColumn(parent)
    local text = S.CreateFontString(parent, nil, "OVERLAY")
    text:SetJustifyH("RIGHT")
    text:SetWordWrap(false)
    return text
end

local function PlaceValueColumn(text, reference, point, x, y, width, size)
    text:ClearAllPoints()
    text:SetWidth(width)
    text:SetPoint("RIGHT", reference, point, x, y)
    D.FontStyle(text, size, "values")
    text:Show()
end

local function StyleValueColumns(row, vx, vy, size)
    local style, c, win = M.style, M.config, row.win
    local meterType = win and win.meterType
    local enabled = row.kind == "list" and win and VALUE_FORMAT.COLUMNS and style.numberFormat == VALUE_FORMAT.COLUMNS
        and meterType ~= D.THREAT and meterType ~= TYPE.Deaths
    local total = row.valueText
    row.columns = enabled
    if not enabled then
        if row.rateText then
            total:SetWidth(0)
            row.rateText:Hide()
            row.percentText:Hide()
        end
        return
    end
    local parent = row.valueHost or row.bar
    if not row.rateText then
        row.rateText = NewValueColumn(parent)
        row.percentText = NewValueColumn(parent)
    end
    local rate, percent = row.rateText, row.percentText
    local totalWidth = c.totalColumnWidth or 48
    local rateWidth = not D.countOnly[meterType] and (c.rateColumnWidth or 44) or 0
    local percentWidth = style.percent and (c.percentColumnWidth or 34) or 0
    local width = win.frame:GetWidth()
    local scale = Finite(width) and math.min(1, math.max(1, width - 64) / (totalWidth + rateWidth + percentWidth)) or 1
    total:SetWidth(totalWidth * scale)
    local edge, point, x, y = row.bar, "RIGHT", -3 + vx, style.baseline + vy
    if percentWidth > 0 then
        PlaceValueColumn(percent, edge, point, x, y, percentWidth * scale, size)
        edge, point, x, y = percent, "LEFT", -4, 0
    else
        percent:Hide()
    end
    if rateWidth > 0 then
        PlaceValueColumn(rate, edge, point, x, y, rateWidth * scale, size)
        edge, point, x, y = rate, "LEFT", -4, 0
    else
        rate:Hide()
    end
    total:ClearAllPoints()
    total:SetPoint("RIGHT", edge, point, x, y)
end

function D.Atlas(texture, atlas)
    if C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas)
        return true
    end
    return false
end

function D.FontStyle(fontString, size, role)
    local style = role and M.style.fonts[role] or M.style
    S.SetStyledFont(fontString, style.font, size, style.outline, style.rendering,
        style.shadow, style.shadowOpacity, style.shadowDistance)
    fontString:SetAlpha(style.textAlpha)
end

-- kind: "list" (meter rows), "spell" (breakdown panel) or "tip" (hover breakdown).
function D.CreateRow(parent, win, kind)
    local row = S.CreateFrame("Button", nil, parent)
    row.win, row.kind = win, kind
    local bar = S.CreateFrame("StatusBar", nil, row)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    row.bar = bar
    D.CreateRowSurfaces(row)
    row.track = S.CreateTexture(bar, nil, "BACKGROUND")
    row.icon = S.CreateTexture(row.iconHost or row, nil, "ARTWORK")
    row.rankText = S.CreateFontString(row.nameHost or bar, nil, "OVERLAY")
    row.nameText = S.CreateFontString(row.nameHost or bar, nil, "OVERLAY")
    row.valueText = S.CreateFontString(row.valueHost or bar, nil, "OVERLAY")
    row.nameText:SetJustifyH("LEFT")
    row.valueText:SetJustifyH("RIGHT")
    row.rankText:SetWordWrap(false)
    row.nameText:SetWordWrap(false)
    row.valueText:SetWordWrap(false)
    -- A click-through window (Window.lua D.ApplyMouse) makes its new rows deaf too.
    if kind == "tip" or win.passive then row:EnableMouse(false) end
    if kind ~= "tip" then
        local highlight = S.CreateTexture(row, nil, "HIGHLIGHT")
        highlight:SetAllPoints(row)
        highlight:SetColorTexture(1, 1, 1, .08)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:EnableMouseWheel(true)
        for script, handler in pairs(kind == "list" and D.listScripts or D.spellScripts) do row:SetScript(script, handler) end
    end
    return row
end

function D.AnchorRow(row, parent, slot)
    local offset = -(slot - 1) * (M.style.barHeight + M.style.spacing)
    local x, y = 0, 0
    if row.kind == "list" then x, y = M.config.barsOffsetX, M.config.barsOffsetY end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, offset + y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x, offset + y)
end

function D.ClearMemo(row)
    row.rank, row.rawName, row.class, row.iconKey, row.spellID = nil, nil, nil, nil, nil
    row.mA, row.mB, row.mP, row.mF = nil, nil, nil, nil
    row.percentPainted = nil
    row.mMax, row.mVal, row.full, row.mDeath = nil, nil, nil, nil
end

-- Gradient textures are allocated once per used direction, and only restyled
-- when the meter style changes. Anchoring to the fill clips them to its value.
local function StyleGradient(bar, style)
    local overlays = bar.gradientOverlays
    local fill = style.gradientEnabled and bar:GetStatusBarTexture()
    if not fill then
        if overlays then for _, texture in pairs(overlays) do texture:Hide() end end
        return
    end
    if not overlays then
        overlays = {}
        bar.gradientOverlays = overlays
    end
    for i = 1, #gradientDirections do
        local direction = gradientDirections[i]
        local key, orientation, reverse = direction[1], direction[2], direction[3]
        local texture = overlays[key]
        if style[key] then
            if not texture then
                texture = S.CreateTexture(bar, nil, "ARTWORK", nil, 1)
                texture:SetTexture(WHITE)
                texture:SetBlendMode("BLEND")
                overlays[key] = texture
            end
            texture:ClearAllPoints()
            texture:SetAllPoints(fill)
            texture:SetAlpha(style.barAlpha)
            local first, second = style.gradientClear, style.gradientTint
            if reverse then first, second = second, first end
            texture:SetGradient(orientation, first, second)
            texture:Show()
        elseif texture then
            texture:Hide()
        end
    end
end

local function RowEdges(row, key, parent)
    local holder = row[key]
    if not holder then
        holder = S.CreateFrame("Frame", nil, parent)
        holder:SetFrameLevel(parent:GetFrameLevel() + 2)
        holder:EnableMouse(false)
        holder.edges = {}
        for i = 1, 4 do holder.edges[i] = S.CreateTexture(holder, nil, "OVERLAY") end
        row[key] = holder
    end
    return holder
end
local function StyleRowBorder(row, hasIcon)
    local c, bar = M.config, row.bar
    local mode = c.rowBorderMode
    local spec = M.style.rowBorder
    if mode ~= ROW_BORDER.NONE then
        local holder = RowEdges(row, "fillBorder", bar)
        local level = bar:GetFrameLevel() + 2
        if holder:GetFrameLevel() ~= level then holder:SetFrameLevel(level) end
        local target = mode == ROW_BORDER.FILLED and bar:GetStatusBarTexture() or bar
        holder:ClearAllPoints()
        -- Include the reserved icon column; a displaced icon must not invert
        -- the full-row rectangle by crossing its opposite bar corner.
        holder:SetPoint("TOPLEFT", hasIcon and c.rowBorderIcon and row or target, "TOPLEFT", -spec.gap, spec.gap)
        holder:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", spec.gap, -spec.gap)
        D.PaintBorder(holder, holder.edges, holder, spec)
        holder:Show()
    elseif row.fillBorder then row.fillBorder:Hide() end
    if c.iconBorder and hasIcon then
        local holder = RowEdges(row, "iconBorder", row.iconHost or bar)
        if row.iconHost then holder:SetFrameLevel(row.iconHost:GetFrameLevel() + 1) end
        holder:ClearAllPoints()
        local iconSpec = M.style.iconBorder
        if iconSpec.gap == 0 then holder:SetAllPoints(row.icon) else
            holder:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -iconSpec.gap, iconSpec.gap)
            holder:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", iconSpec.gap, -iconSpec.gap)
        end
        D.PaintBorder(holder, holder.edges, holder, iconSpec)
        holder:Show()
    elseif row.iconBorder then row.iconBorder:Hide() end
end

local function StyleRowText(row, list, left, right)
    local style, c = M.style, M.config
    local nx, ny = list and c.nameOffsetX or 0, list and c.nameOffsetY or 0
    local vx, vy = list and c.valueOffsetX or 0, list and c.valueOffsetY or 0
    local rank, name, value, bar = row.rankText, row.nameText, row.valueText, row.bar
    local showValues = not list or c.showValues ~= false
    name:SetShown(not list or c.showNames ~= false)
    if list then row.valueHost:SetShown(showValues) end
    D.FontStyle(rank, left, list and "names" or "details")
    D.FontStyle(name, left, list and "names" or "details")
    D.FontStyle(value, right, list and "values" or "details")
    rank:ClearAllPoints()
    name:ClearAllPoints()
    value:ClearAllPoints()
    value:SetPoint("RIGHT", bar, "RIGHT", -3 + vx, style.baseline + vy)
    StyleValueColumns(row, vx, vy, right)
    if list and style.rank then
        rank:SetPoint("LEFT", bar, "LEFT", 3 + nx, style.baseline + ny)
        rank:Show()
        name:SetPoint("LEFT", rank, "RIGHT", 2, 0)
    else
        rank:Hide()
        name:SetPoint("LEFT", bar, "LEFT", 3 + nx, style.baseline + ny)
    end
    if showValues then
        name:SetPoint("RIGHT", value, "LEFT", -6 + nx - vx, ny - vy)
    else
        name:SetPoint("RIGHT", bar, "RIGHT", -3 + nx, style.baseline + ny)
    end
end

function D.StyleRow(row)
    local style = M.style
    row.styleGen = M.styleGen
    local tip, list = row.kind == "tip", row.kind == "list"
    local height = tip and 16 or style.barHeight
    local left, right = tip and 11 or style.leftSize, tip and 11 or style.rightSize
    local hasIcon = not list or style.iconStyle ~= ICON.NONE
    local c = M.config
    row:SetHeight(height)
    local icon, bar = row.icon, row.bar
    icon:ClearAllPoints()
    bar:ClearAllPoints()
    if hasIcon then
        local size = list and c.iconSize > 0 and c.iconSize or height
        icon:SetSize(size, size)
        icon:SetPoint("LEFT", row, "LEFT", list and c.iconOffsetX or 0, list and c.iconOffsetY or 0)
        bar:SetPoint("TOPLEFT", row, "TOPLEFT", height + 1, 0)
    else
        D.SetIconShown(row, false)
        bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    end
    bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    local texture = not list and style.breakdownTexture or style.texture
    bar:SetStatusBarTexture(texture)
    D.StyleRowSurfaces(row)
    StyleGradient(bar, style)
    if style.glossEnabled or row.glossActive then
        row.glossActive = P.NS.GlossMaterial.Bar(bar, style.glossEnabled, style.glossStrength, style.barAlpha)
    end
    StyleRowBorder(row, hasIcon)
    D.StyleIconSkin(row, hasIcon)
    D.StyleRowSeparators(row, hasIcon)
    row.track:ClearAllPoints()
    row.track:SetAllPoints(bar)
    row.track:SetColorTexture(style.trackR, style.trackG, style.trackB, style.trackA)
    row.hasIcon = hasIcon
    StyleRowText(row, list, left, right)
    D.ClearMemo(row)
end

-- Bar and text colors follow the NeverSecret class token.
local function ValueColor(row, r, g, b)
    row.valueText:SetTextColor(r, g, b)
    if row.columns then
        row.rateText:SetTextColor(r, g, b)
        row.percentText:SetTextColor(r, g, b)
    end
end

function D.RowColors(row, class)
    local style = M.style
    local r, g, b
    if class ~= "" then r, g, b = S.ClassRGB(class) end
    if style.classColors and r then
        row.bar:SetStatusBarColor(r, g, b, style.barAlpha)
    else
        row.bar:SetStatusBarColor(style.barR, style.barG, style.barB, style.barAlpha)
    end
    if style.leftClass and r then
        row.nameText:SetTextColor(r, g, b)
        row.rankText:SetTextColor(r, g, b)
    else
        row.nameText:SetTextColor(style.leftR, style.leftG, style.leftB)
        row.rankText:SetTextColor(style.leftR, style.leftG, style.leftB)
    end
    if style.rightClass and r then
        ValueColor(row, r, g, b)
    else
        ValueColor(row, style.rightR, style.rightG, style.rightB)
    end
end

-- Specialization prefers the spec icon; Class (and a missing spec) uses the class sprite.
function D.UnitIcon(row, spec, class, iconStyle)
    local bySpec = iconStyle == ICON.SPEC and spec ~= 0
    local key = bySpec and spec or class
    if key == row.iconKey then return end
    row.iconKey = key
    local icon, zoom = row.icon, M.style.zoom
    if bySpec then
        icon:SetTexture(spec)
        icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        D.SetIconShown(row, true)
        return
    end
    local coords = class ~= "" and CLASS_ICON_TCOORDS[class]
    if type(coords) ~= "table" then
        D.SetIconShown(row, false)
        return
    end
    local l, r, t, b = coords[1], coords[2], coords[3], coords[4]
    local dx, dy = (r - l) * zoom, (b - t) * zoom
    icon:SetTexture(CLASS_SHEET)
    icon:SetTexCoord(l + dx, r - dx, t + dy, b - dy)
    D.SetIconShown(row, true)
end

local function SetPlainBar(row, maxValue, value)
    local bar = row.bar
    row.full = nil
    maxValue, value = Num(maxValue), Num(value)
    if not IsSecret(maxValue) then
        if maxValue ~= row.mMax then
            row.mMax = maxValue
            bar:SetMinMaxValues(0, maxValue)
        end
    else
        row.mMax = nil
        bar:SetMinMaxValues(0, maxValue)
    end
    if not IsSecret(value) then
        if value ~= row.mVal then
            row.mVal = value
            bar:SetValue(value)
        end
    else
        row.mVal = nil
        bar:SetValue(value)
    end
end

-- Smooth fill: the client eases the bar toward its new range and value in C,
-- secret values included, so no timer or OnUpdate is needed. Every declared
-- client has Enum.StatusBarInterpolation (tools/tests/client_api_snapshot.json:
-- 12.1.0, 12.1.5, Forever). The plain writes' memo stays empty here.
local fillInterpolation
local function SetSmoothBar(row, maxValue, value)
    local bar = row.bar
    row.full, row.mMax, row.mVal = nil, nil, nil
    bar:SetMinMaxValues(0, Num(maxValue), fillInterpolation)
    bar:SetValue(Num(value), fillInterpolation)
end

-- D.SetBar is picked when the style is built (Controller.lua BuildStyle), so
-- the paint path takes no per-row branch.
function D.UseBarFill(smooth)
    fillInterpolation = smooth and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
    D.SetBar = smooth and SetSmoothBar or SetPlainBar
end
D.SetBar = SetPlainBar

-- The rounded share of denominator while percent is shown; nil unless both
-- values are plain (a secret is never used in arithmetic). Callers pass the
-- style they already hold, so a row update reads M.style once.
local function Percent(total, denominator, shown)
    if not shown then return nil end
    denominator = Num(denominator)
    if not IsSecret(total) and not IsSecret(denominator) and denominator > 0 then
        return floor(total / denominator * 100 + .5)
    end
end

local function PaintValueColumns(row, meterType, total, rate, denominator)
    local showRate = not D.countOnly[meterType]
    local percent = Percent(total, denominator, M.style.percent)
    local plainTotal, plainRate = not IsSecret(total), not IsSecret(rate)
    if not plainTotal or row.mA ~= total then
        row.valueText:SetText(Abbreviate(total))
        row.mA = plainTotal and total or nil
    end
    if showRate and (not plainRate or row.mB ~= rate) then
        row.rateText:SetText(Abbreviate(rate))
        row.mB = plainRate and rate or nil
    end
    if not row.percentPainted or row.mP ~= percent then
        row.percentText:SetText(percent and format("%d%%", percent) or "")
        row.mP, row.percentPainted = percent, true
    end
end

-- Compile the four rate/percent availability combinations for this style.
function D.BuildValuePlan(style)
    style.customValues = nil
    if style.numberFormat ~= VALUE_FORMAT.CUSTOM then return end
    local order = customOrders[style.valueOrder] or customOrders[1]
    local patterns = customPatterns[style.valueSeparator] or customPatterns[2]
    local plans = {}
    for variant = 1, 4 do
        local showRate, showPercent = variant > 2, variant % 2 == 0
        local count, key = 0, 0
        for _, field in ipairs(order) do
            if field == TOTAL or (field == RATE and showRate) or (field == PERCENT and showPercent) then
                count, key = count + 1, key * 10 + field
            end
        end
        plans[variant] = { args = customArguments[key], pattern = patterns[count] }
    end
    style.customValues = plans
end

-- A secret value is only passed through AbbreviateNumbers and SetFormattedText.
local function SetCustomValueText(row, meterType, total, perSecond, denominator, alwaysPercent)
    local style = M.style
    local countOnly = D.countOnly[meterType]
    local rate
    if not countOnly then rate = perSecond end
    local percent = Percent(total, denominator, alwaysPercent or style.percent)
    local plan = style.customValues[(countOnly and 1 or 3) + (percent and 1 or 0)]
    local allPlain = not IsSecret(total) and (countOnly or not IsSecret(rate))
    if allPlain and total == row.mA and rate == row.mB and percent == row.mP and row.mF == plan then return end
    if allPlain then
        row.mA, row.mB, row.mP, row.mF = total, rate, percent, plan
    else
        row.mA, row.mB, row.mP, row.mF = nil, nil, nil, nil
    end
    local totalText = Abbreviate(total)
    local rateText
    if not countOnly then rateText = Abbreviate(rate) end
    local percentText = percent and format("%d%%", percent)
    if allPlain then
        row.valueText:SetText(format(plan.pattern, plan.args(totalText, rateText, percentText)))
    else
        row.valueText:SetFormattedText(plan.pattern, plan.args(totalText, rateText, percentText))
    end
end

-- Value formats: per second only, primary only, "a (b)", "a | b", or the
-- custom layout. The primary value is the rate for Dps/Hps; interrupts and
-- dispels show counts.
function D.SetValueText(row, meterType, total, perSecond, denominator, alwaysPercent)
    local style = M.style
    local fmt = style.numberFormat
    total, perSecond = Num(total), Num(perSecond)
    if fmt == VALUE_FORMAT.COLUMNS then
        if row.columns then return PaintValueColumns(row, meterType, total, perSecond, denominator) end
        fmt = VALUE_FORMAT.PARENTHESES
    end
    if fmt == VALUE_FORMAT.CUSTOM then
        return SetCustomValueText(row, meterType, total, perSecond, denominator, alwaysPercent)
    end
    local a, b, two
    if D.countOnly[meterType] then
        a = total
    else
        local main, second = total, perSecond
        if D.perSecond[meterType] then main, second = perSecond, total end
        if fmt == VALUE_FORMAT.RATE then a = perSecond
        elseif fmt == VALUE_FORMAT.PRIMARY then a = main
        else a, b, two = main, second, true end
    end
    local text = row.valueText
    if not IsSecret(a) and (not two or not IsSecret(b)) then
        local percent = Percent(total, denominator, alwaysPercent or style.percent)
        if a == row.mA and b == row.mB and percent == row.mP and fmt == row.mF then return end
        row.mA, row.mB, row.mP, row.mF = a, b, percent, fmt
        local value = Abbreviate(a)
        if two then value = format(separators[fmt], value, Abbreviate(b)) end
        if percent then value = format("%s %d%%", value, percent) end
        text:SetText(value)
        return
    end
    row.mA, row.mB, row.mP, row.mF = nil, nil, nil, nil
    local first = Abbreviate(a)
    if two then
        text:SetFormattedText(separators[fmt], first, Abbreviate(b))
    else
        text:SetText(first)
    end
end

function D.PaintSource(row, source, index, session, win)
    if row.styleGen ~= M.styleGen then D.StyleRow(row) end
    local style, meterType = M.style, win.meterType
    local name = source.name
    if not IsSecret(name) then
        if name ~= row.rawName then
            row.rawName = name
            row.nameText:SetText(D.Short(name))
        end
    else
        row.rawName = nil
        row.nameText:SetText(D.Short(name))
    end
    local class = source.classFilename
    if IsSecret(class) or type(class) ~= "string" then class = "" end
    if class ~= row.class then
        row.class = class
        D.RowColors(row, class)
    end
    if row.hasIcon then
        local spec = source.specIconID
        local liveSpecs = M.remoteSpecs
        if liveSpecs and style.iconStyle == ICON.SPEC and not win.sessionID and meterType ~= D.THREAT then
            local guid = source.sourceGUID
            if not IsSecret(guid) then spec = liveSpecs[guid] or spec end
        end
        D.UnitIcon(row, Finite(spec) and spec or 0, class, style.iconStyle)
    end
    -- Threat rows number the members themselves (Threat.lua).
    if meterType == D.THREAT then
        row.mDeath = nil
        D.PaintThreatValue(row, source, session.maxAmount)
        return
    end
    if style.rank and row.rank ~= index then
        row.rank = index
        row.rankText:SetText(ranks[index])
    end
    if meterType == TYPE.Deaths then
        if not row.full then
            row.full, row.mMax, row.mVal = true, nil, nil
            row.bar:SetMinMaxValues(0, 1)
            row.bar:SetValue(1)
        end
        row.mA = nil
        local seconds = source.deathTimeSeconds
        seconds = (Finite(seconds) and seconds >= 0 and not win.overall) and floor(seconds) or -1
        if seconds ~= row.mDeath then
            row.mDeath = seconds
            row.valueText:SetText(seconds >= 0 and D.Clock(seconds) or "")
        end
        return
    end
    row.mDeath = nil
    D.SetBar(row, session.maxAmount, source.totalAmount)
    D.SetValueText(row, meterType, source.totalAmount, source.amountPerSecond, session.totalAmount, false)
end

-- Breakdown spell row; percent of the source total whenever values are plain.
function D.PaintSpell(row, spell, source, meterType, class)
    if row.styleGen ~= M.styleGen then D.StyleRow(row) end
    if class ~= row.class then
        row.class = class
        D.RowColors(row, class)
    end
    row.rawName, row.iconKey = nil, nil
    -- Native spell details may identify the recipient, or the attacker for
    -- EnemyDamageTaken. Names may be secret in combat; keep them in a C sink.
    local details = spell.combatSpellDetails
    local unitName = details and details.unitName
    local unitLabel = (D.targetTypes[meterType] or meterType == TYPE.EnemyDamageTaken) and
        (not Public(unitName) or (type(unitName) == "string" and unitName ~= ""))
    -- Recycled rows must repaint their plain spell name when that suffix ends.
    if row.unitSpellLabel and not unitLabel then row.spellID = nil end
    row.unitSpellLabel = unitLabel
    local id = spell.spellID
    if Finite(id) then
        local changed = id ~= row.spellID
        if changed then
            row.spellID = id
            local texture, zoom = C_Spell.GetSpellTexture(id), M.style.zoom
            if texture then
                row.icon:SetTexture(texture)
                row.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
                D.SetIconShown(row, true)
            else
                D.SetIconShown(row, false)
            end
        end
        -- A pooled row can keep its spell while its pet or owner changes.
        -- Cache only readable names; a secret pet drops the previous suffix.
        local pet = spell.creatureName
        if not Public(pet) or type(pet) ~= "string" then pet = "" end
        if changed or pet ~= row.spellPet then
            row.spellPet = pet
            local name = C_Spell.GetSpellName(id)
            if not Public(name) or type(name) ~= "string" then name = "" end
            if name ~= "" and pet ~= "" then name = format("%s (%s)", name, pet) end
            row.spellName = name
            row.nameText:SetText(name)
        end
    else
        -- Secret spell IDs never reach texture lookups (reported to raise on
        -- some clients); C_Spell.GetSpellName accepts them and returns a secret.
        row.spellID = nil
        D.SetIconShown(row, false)
        if Public(id) then
            row.spellName = ""
            row.nameText:SetText("")
        else
            row.spellName = C_Spell.GetSpellName(id)
            row.nameText:SetText(row.spellName)
        end
    end
    if unitLabel and (not Public(id) or id ~= nil) then
        row.nameText:SetFormattedText("%s - %s", row.spellName, D.Short(unitName))
    end
    D.SetBar(row, source.maxAmount, spell.totalAmount)
    D.SetValueText(row, meterType, spell.totalAmount, spell.amountPerSecond, source.totalAmount, true)
end

-- EnemyDamageTaken breakdown row: one attacking unit (plain data only).
function D.PaintGroup(row, entry, maxAmount, total, duration, meterType, targetAmount)
    if row.styleGen ~= M.styleGen then D.StyleRow(row) end
    if entry.class ~= row.class then
        row.class = entry.class
        D.RowColors(row, entry.class)
    end
    row.spellID = nil
    D.UnitIcon(row, entry.spec, entry.class, ICON.SPEC)
    if entry.name ~= row.rawName then
        row.rawName = entry.name
        row.nameText:SetText(D.Short(entry.name))
    end
    D.SetBar(row, maxAmount, entry.amount)
    if targetAmount then
        -- Target hover always shows damage, even when the meter displays only DPS.
        local percent = Percent(entry.amount, total, true)
        local amount = Abbreviate(entry.amount)
        row.valueText:SetText(percent and format("%s %d%%", amount, percent) or amount)
        row.mA, row.mB, row.mP, row.mF = nil, nil, nil, nil
        return
    end
    D.SetValueText(row, meterType, entry.amount, duration > 0 and entry.amount / duration or 0, total, true)
end
