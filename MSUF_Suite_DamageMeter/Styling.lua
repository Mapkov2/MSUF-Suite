local _, P = ...
local D, S = P.DamageMeter, P.Suite
local M = D.M
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FILES = {
    [2] = "Interface\\Tooltips\\UI-Tooltip-Border",
    [3] = "Interface\\DialogFrame\\UI-DialogBox-Border",
    [4] = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
}
local OUTLINE = { [2] = "OUTLINE", [3] = "THICKOUTLINE", [5] = "OUTLINE", [6] = "THICKOUTLINE" }
local SHADOW = { [1] = true, [5] = true, [6] = true }
local ROLES = { "names", "values", "header", "details", "timer" }
local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local ADJACENT = { { 1, 3 }, { 1, 4 }, { 2, 3 }, { 2, 4 } }
-- Blizzard's common edge-file layout. Fixed UVs and native anchors stretch
-- the strips: no OnSizeChanged handler or reads of a secret bar-fill width.
local UV = {
    { .2578125, .9375, .3671875, .9375, .2578125, .0625, .3671875, .0625 },
    { .3828125, .9375, .4921875, .9375, .3828125, .0625, .4921875, .0625 },
    { .0078125, .0625, .0078125, .9375, .1171875, .0625, .1171875, .9375 },
    { .1328125, .0625, .1328125, .9375, .2421875, .0625, .2421875, .9375 },
}

local function BorderSpec(c, prefix, size, color)
    local r, g, b = S.RGB(c[color])
    return { style = c[prefix .. "Style"] or 1, size = c[size], r = r, g = g, b = b,
        alpha = (c[prefix .. "Alpha"] or 100) / 100, gap = c[prefix .. "Gap"] or 0,
        c[prefix .. "Top"] ~= false, c[prefix .. "Bottom"] ~= false,
        c[prefix .. "Left"] ~= false, c[prefix .. "Right"] ~= false }
end

function D.BuildDecorationStyle(style, c)
    style.headerClock = c.combatTime and c.headerTimer and c.headerVisible ~= false
    style.headerSpace = c.headerVisible ~= false and not c.headerOutside and c.headerHeight or 0
    style.windowBorder = BorderSpec(c, "border", "borderSize", "borderColor")
    style.rowBorder = BorderSpec(c, "rowBorder", "rowBorderSize", "rowBorderColor")
    style.iconBorder = c.iconBorderCustom and BorderSpec(c, "iconBorder", "iconBorderSize", "iconBorderColor") or style.rowBorder
    style.bgTexture = c.bgTextured and S.ResolveTexture(c.bgTexture, WHITE) or nil
    style.headerTexture = c.headerTextured and S.ResolveTexture(c.headerTexture, WHITE) or nil
    style.fonts = style.fonts or {}
    for _, role in ipairs(ROLES) do
        local target = style.fonts[role] or {}
        style.fonts[role] = target
        local custom = c[role .. "FontCustom"]
        if custom then target.font = S.ResolveFont(c[role .. "Font"]) else target.font = style.font end
        target.outline = custom and (OUTLINE[c[role .. "Outline"]] or "") or style.outline
        target.rendering = custom and c[role .. "Rendering"] or style.rendering
        target.shadow = custom and SHADOW[c[role .. "Outline"]] == true or not custom and style.shadow
        target.shadow = target.shadow and target.rendering ~= P.NS.FontRendering.SLUG
        target.shadowOpacity, target.shadowDistance = style.shadowOpacity, style.shadowDistance
        target.textAlpha = style.textAlpha
    end
end

function D.PaintSurface(texture, path, color, alpha)
    local r, g, b = S.RGB(color)
    if path then
        texture:SetTexture(path)
        texture:SetVertexColor(r, g, b, alpha / 100)
    else
        texture:SetVertexColor(1, 1, 1, 1)
        texture:SetColorTexture(r, g, b, alpha / 100)
    end
end

local function MaterialPieces(owner)
    if owner.materialEdges then return owner.materialEdges end
    local pieces = {}
    for i = 1, 8 do pieces[i] = S.CreateTexture(owner, nil, "OVERLAY") end
    owner.materialEdges = pieces
    return pieces
end

local function MaterialEdge(texture, box, index, size)
    texture:ClearAllPoints()
    if index <= 2 then
        local point = index == 1 and "TOP" or "BOTTOM"
        texture:SetPoint(point .. "LEFT", box, point .. "LEFT", size, 0)
        texture:SetPoint(point .. "RIGHT", box, point .. "RIGHT", -size, 0)
        texture:SetHeight(size)
    else
        local point = index == 3 and "LEFT" or "RIGHT"
        texture:SetPoint("TOP" .. point, box, "TOP" .. point, 0, -size)
        texture:SetPoint("BOTTOM" .. point, box, "BOTTOM" .. point, 0, size)
        texture:SetWidth(size)
    end
    texture:SetTexCoord(unpack(UV[index]))
end

function D.PaintBorder(owner, edges, box, spec)
    local path = FILES[spec.style]
    local pieces = owner.materialEdges
    if not path or spec.size <= 0 then
        if pieces then for _, texture in ipairs(pieces) do texture:Hide() end end
        S.PlaceEdges(edges, box, spec.size, spec.r, spec.g, spec.b, spec.alpha)
        for i = 1, 4 do if not spec[i] then edges[i]:Hide() end end
        return
    end
    for _, texture in ipairs(edges) do texture:Hide() end
    pieces = MaterialPieces(owner)
    for i, texture in ipairs(pieces) do
        texture:SetTexture(path)
        texture:SetVertexColor(spec.r, spec.g, spec.b, spec.alpha)
        local visible
        if i <= 4 then
            MaterialEdge(texture, box, i, spec.size)
            visible = spec[i]
        else
            local corner = i - 4
            texture:ClearAllPoints()
            texture:SetPoint(CORNERS[corner], box, CORNERS[corner], 0, 0)
            texture:SetSize(spec.size, spec.size)
            texture:SetTexCoord((corner + 3) / 8 + .0078125, (corner + 4) / 8 - .0078125, .0625, .9375)
            visible = spec[ADJACENT[corner][1]] and spec[ADJACENT[corner][2]]
        end
        texture:SetShown(visible)
    end
end

local function Separator(owner, key, enabled, parent)
    local texture = owner[key]
    if enabled and not texture then
        texture = S.CreateTexture(parent or owner, nil, "OVERLAY")
        owner[key] = texture
    end
    if texture then texture:SetShown(enabled) end
    return texture
end

local function LineColor(texture)
    local c = M.config
    local r, g, b = S.RGB(c.separatorColor)
    texture:SetColorTexture(r, g, b, c.separatorAlpha / 100)
    texture:ClearAllPoints()
end

function D.StyleRowSeparators(row, hasIcon)
    local c = M.config
    local texture = Separator(row, "rowSeparator", c.rowSeparators == true, row.bar)
    if texture then
        LineColor(texture)
        texture:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", c.separatorInset, -c.barSpacing / 2)
        texture:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -c.separatorInset, -c.barSpacing / 2)
        texture:SetHeight(c.separatorSize)
    end
    texture = Separator(row, "iconSeparator", c.iconSeparator == true and hasIcon, row.bar)
    if texture then
        LineColor(texture)
        local inset = math.min(c.separatorInset, (row:GetHeight() - 1) / 2)
        texture:SetPoint("TOPLEFT", row.bar, "TOPLEFT", -1, -inset)
        texture:SetPoint("BOTTOMLEFT", row.bar, "BOTTOMLEFT", -1, inset)
        texture:SetWidth(c.separatorSize)
    end
end

function D.StyleHeaderSeparator(win)
    local c = M.config
    local texture = Separator(win.header, "separator", c.headerSeparator == true and c.headerVisible ~= false)
    if not texture then return end
    LineColor(texture)
    texture:SetPoint("BOTTOMLEFT", win.header, "BOTTOMLEFT", c.separatorInset, 0)
    texture:SetPoint("BOTTOMRIGHT", win.header, "BOTTOMRIGHT", -c.separatorInset, 0)
    texture:SetHeight(c.separatorSize)
end
