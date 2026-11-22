local _, NS = ...

-- Shared tooltips are also native layout inputs. Keep their textures, anchors
-- and widget payload intact. The palette is applied only to existing chrome.
local Safety = NS.Safety
local TooltipChrome = {}
NS.TooltipChrome = TooltipChrome

local Palette = { choices = {}, fields = { fillColor = "popup", endColor = "ink", titleColor = "text", accentColor = "accent" } }
NS.TooltipPalette = Palette

local presets = {}
local function AddPreset(key, label, look, height, iconSize)
    Palette.choices[#Palette.choices + 1] = { key = key, label = label }
    presets[key] = { look = look, height = height, iconSize = iconSize }
end
AddPreset("forever", "WoW Forever", "gridClassic", 40, 24)
AddPreset("retail", "Retail", "modern", 48, 32)
for _, key in ipairs(NS.LookOrder or {}) do
    AddPreset(key, NS.LookPresets[key].label, key, key == "cleanModern" and 42 or 48, key == "cleanModern" and 26 or 30)
end

function Palette.HasPreset(key)
    return presets[key] ~= nil
end

local function WithOpacity(rgba, opacity)
    return { rgba[1], rgba[2], rgba[3], rgba[4] * opacity }
end

function Palette.BuildPreset(key)
    local spec = presets[key]
    if not spec then return end
    local profile = { theme = {}, geometry = {} }
    if not NS.Theme.StyleProfile(profile, spec.look) then return end
    local theme, layout = profile.theme, {
        palette = true, borderMode = "custom", height = spec.height, iconSize = spec.iconSize,
    }
    layout.paletteGradient, layout.paletteDirection = theme.gradient == true, theme.gradientDirection
    for field, role in pairs(Palette.fields) do
        local opacity = (role == "popup" or role == "ink") and theme.shellOpacity or 1
        layout[field] = WithOpacity(theme.colors[role], opacity)
    end
    layout.borderColor = WithOpacity(theme.colors.border, theme.borderOpacity)
    return layout
end

local function Layout()
    local layout = NS.DB and NS.DB.theme and NS.DB.theme.tooltipLayout
    if type(layout) == "table" then return layout end
end

local function Channel(value)
    return Safety.Public(value) and type(value) == "number" and value >= 0 and value <= 1
end

local function ReadColor(layout, field, role)
    local color = layout and layout[field]
    if Safety.Public(color) and type(color) == "table" and canaccesstable(color)
        and Channel(color[1]) and Channel(color[2]) and Channel(color[3]) and Channel(color[4]) then
        return unpack(color, 1, 4)
    end
    return NS.Theme.GetColor(role)
end

function Palette.IsActive()
    local layout = Layout()
    return layout and layout.palette == true or false
end

function Palette.Color(field)
    return ReadColor(Layout(), field, Palette.fields[field])
end

function Palette.Fill(spec, alphaScale)
    local layout = Layout()
    if not layout or layout.palette ~= true then return end
    local r, g, b, a = ReadColor(layout, "fillColor", "popup")
    local tr, tg, tb, ta = ReadColor(layout, "endColor", "ink")
    local scale = alphaScale or 1
    local direction = layout.paletteDirection == "HORIZONTAL" and "HORIZONTAL" or "VERTICAL"
    return r, g, b, spec.opaqueFill and 1 or a * scale,
        tr, tg, tb, spec.opaqueFill and 1 or ta * scale, layout.paletteGradient == true, direction
end

function Palette.Title()
    if Palette.IsActive() then return Palette.Color("titleColor") end
    return NS.Theme.GetColor("text")
end

function Palette.Accent(r, g, b)
    if Palette.IsActive() then return Palette.Color("accentColor") end
    return r, g, b, .74
end

local hostFill = { role = "popup", resolveFill = Palette.Fill }
function Palette.PaintHostBackdrop(frame, state, wanted, keepBorder)
    if not wanted or not Palette.IsActive() then
        if state.nativeBackdrop then
            frame:SetBackdropColor(unpack(state.nativeBackdrop))
            state.nativeBackdrop = nil
        end
        if state.nativeBorder then
            frame:SetBackdropBorderColor(unpack(state.nativeBorder))
            state.nativeBorder = nil
        end
        if state.paletteFill then state.paletteFill:Hide() end
        return false
    end
    if not state.nativeBackdrop then
        local r, g, b, a = Safety.ReadColor(frame, "GetBackdropColor")
        if not r or not Safety.HasMethod(frame, "SetBackdropColor") then return false end
        state.nativeBackdrop = { r, g, b, a }
        frame:SetBackdropColor(0, 0, 0, 0)
    end
    if keepBorder and state.nativeBorder then
        frame:SetBackdropBorderColor(unpack(state.nativeBorder))
        state.nativeBorder = nil
    elseif not keepBorder and not state.nativeBorder then
        local r, g, b, a = Safety.ReadColor(frame, "GetBackdropBorderColor")
        if r and Safety.HasMethod(frame, "SetBackdropBorderColor") then
            state.nativeBorder = { r, g, b, a }
            frame:SetBackdropBorderColor(0, 0, 0, 0)
        end
    end
    if not state.paletteFill then
        state.paletteFill = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        state.paletteFill:SetAllPoints(frame)
        state.paletteFill:SetColorTexture(1, 1, 1, 1)
    end
    local material = NS.Theme.GetMaterial("popup")
    NS.Surface.PaintFill(state.paletteFill, nil, state, nil, NS.Surface.PrepareFill(material, hostFill))
    state.paletteFill:Show()
    return true
end

NS.Registry.AddListener(Palette, function(_, domain)
    if domain == "tooltipStyle" then NS.Registry.QueueRefresh("tooltipPalette") end
end)

local Caption = { Height = 20 }
NS.TooltipComparisonCaption = Caption

function Caption.Read(tip)
    local badge = Safety.Field(tip, "CompareHeader")
    if not Safety.Public(badge) then return false end
    if not badge then return end
    local shown = Safety.Read(badge, "IsShown")
    if shown == nil then return false end
    if not shown then return end
    local label = Safety.Field(badge, "Label")
    if not Safety.Public(label) then return false end
    local text = Safety.Read(label, "GetText")
    if type(text) ~= "string" or text == "" then return false end
    return badge, text
end

function Caption.Release(view)
    if not view.nativeComparison then return end
    NS.Cosmetics.Restore(view.nativeComparison, view)
    view.nativeComparison, view.comparisonCaption = nil, nil
    view.comparisonText:Hide()
    view.comparisonFill:Hide()
end

function Caption.Paint(view, badge, text, changed)
    if view.nativeComparison and view.nativeComparison ~= badge then Caption.Release(view) end
    if not view.nativeComparison or Safety.Read(badge, "GetAlpha") ~= 0 then
        if not Safety.CanDecorate(badge) or not NS.Cosmetics.Fade(badge, view) then return false end
    end
    view.nativeComparison = badge
    local label, fill = view.comparisonText, view.comparisonFill
    if not label then
        local header = view.header.frame
        label = header:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
        label:SetPoint("BOTTOMLEFT", header, "TOPLEFT", 7, 4)
        label:SetPoint("BOTTOMRIGHT", header, "TOPRIGHT", -7, 4)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetMaxLines(1)
        fill = header:CreateTexture(nil, "BACKGROUND")
        fill:SetPoint("TOPLEFT", header, "TOPLEFT", 0, Caption.Height)
        fill:SetPoint("BOTTOMRIGHT", header, "TOPRIGHT")
        view.comparisonText, view.comparisonFill = label, fill
    end
    if view.comparisonCaption ~= text or changed then
        view.comparisonCaption = text
        label:SetText(text)
        label:SetTextColor(NS.Theme.GetColor("title"))
        if Palette.IsActive() then fill:SetColorTexture(Palette.Color("fillColor"))
        else fill:SetColorTexture(NS.Theme.GetColor("popup")) end
        label:Show()
        fill:Show()
    end
    return true
end

local tooltips = setmetatable({}, { __mode = "k" })
local pending = setmetatable({}, { __mode = "k" })
local scheduled = false
local styleHooked = false
local borderPieces = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
}
local fillSpec = { role = "popup", radius = 8, resolveFill = Palette.Fill }

local plan
local geometry = {}

local function ResolveBorder(material)
    local layout = Layout()
    if layout and layout.palette == true and layout.borderMode == "custom" then
        return ReadColor(layout, "borderColor", material.border)
    end
    local r, g, b, a = NS.Theme.GetColor(material.border)
    local edge = NS.Geometry.Resolve(fillSpec, geometry).edge
    return r, g, b, edge and a * NS.Theme.GetBorderOpacity() or 0
end

function TooltipChrome.GetBorder()
    return ResolveBorder(NS.Theme.GetMaterial("popup"))
end

-- Reuse the tooltip's actual edge art on an addon-owned overlay. The center
-- belongs to the outlined window; only the eight edge pieces are installed.
local outlineLayout
function TooltipChrome.PaintOutline(frame, art, strata, level)
    local r, g, b, a = TooltipChrome.GetBorder()
    if a <= 0 then
        if art then art:Hide() end
        return art
    end
    if not art then
        if not outlineLayout then
            local native = NineSliceUtil and NineSliceUtil.GetLayout("TooltipDefaultLayout")
            if not native then return end
            outlineLayout = NS.CopyValue(native)
            outlineLayout.Center = nil
        end
        art = CreateFrame("Frame", nil, UIParent, "NineSlicePanelTemplate")
        art:EnableMouse(false)
        art:SetAllPoints(frame)
        NineSliceUtil.ApplyLayout(art, outlineLayout)
    end
    local tooltipScale = Safety.Read(GameTooltip, "GetEffectiveScale")
    local parentScale = Safety.Read(UIParent, "GetEffectiveScale")
    local scale = tooltipScale and parentScale and parentScale > 0 and tooltipScale / parentScale or 1
    if art:GetScale() ~= scale then art:SetScale(scale) end
    if art:GetFrameStrata() ~= strata then art:SetFrameStrata(strata) end
    if art:GetFrameLevel() ~= level then art:SetFrameLevel(level) end
    art:SetBorderColor(r, g, b, a)
    art:Show()
    return art
end

local function PrepareStyle()
    local material = NS.Theme.GetMaterial("popup")
    local r, g, b, a = ResolveBorder(material)
    plan = {
        fill = NS.Surface.PrepareFill(material, fillSpec),
        r = r, g = g, b = b, alpha = a,
    }
end

local function SaveColor(color, r, g, b, a)
    color[1], color[2], color[3], color[4] = r, g, b, a
end

local function Capture(state, region)
    if not Safety.Public(region) or not Safety.CanDecorate(region) then return end
    local r, g, b, a = Safety.ReadColor(region, "GetVertexColor")
    if r == nil then return end
    local paint = state.regions[region]
    if not paint then
        paint = { spec = fillSpec, original = {}, applied = {} }
        state.regions[region] = paint
    end
    if not Safety.ColorMatches(paint.applied, r, g, b, a, Safety.COLOR_OWN) then
        SaveColor(paint.original, r, g, b, a)
    end
    return paint
end

local function RevealSlice(state, keep)
    local slice = state.coveredSlice
    if slice and slice ~= keep then
        NS.Cosmetics.Restore(slice, state)
        state.coveredSlice = nil
    end
end

local function CoverSlice(state, slice)
    RevealSlice(state, slice)
    if state.coveredSlice ~= slice or Safety.Read(slice, "GetAlpha") ~= 0 then
        if not NS.Cosmetics.Fade(slice, state) then return false, "protected" end
        state.coveredSlice = slice
    end
    return true
end

local function RevealCenter(state, keep)
    local center = state.coveredCenter
    if not center or center == keep then return end
    state.coveredCenter = nil
    if state.centerWasShown and Safety.CanDecorate(center) and Safety.Read(center, "IsShown") == false then
        center:Show()
    end
end

local function CoverCenter(state, center)
    RevealCenter(state, center)
    local shown = Safety.Read(center, "IsShown")
    if shown == nil then return false end
    if not state.coveredCenter or shown then
        state.coveredCenter, state.centerWasShown = center, shown
    end
    if shown then center:Hide() end
    return true
end

local function Paint(frame, state)
    if not Safety.CanDecorate(frame) then return false, "protected" end
    local slice = Safety.Field(frame, "NineSlice")
    if not Safety.Public(slice) or not Safety.CanDecorate(slice) then return false, "missing" end
    -- Atlas colors can be restored independently of their parent opacity.
    -- Our backdrop and outline replace the entire native slice in this mode.
    if state.cardBacking == "all" then
        RevealCenter(state)
        return CoverSlice(state, slice)
    end
    RevealSlice(state)

    local center = Safety.Field(slice, "Center")
    local fill = Capture(state, center)
    if not fill then return false, "missing" end
    if state.cardBacking == "fill" then
        if not CoverCenter(state, center) then return false, "protected" end
    else
        RevealCenter(state)
    end

    if not plan then PrepareStyle() end
    -- While the card supplies the backdrop, only the native edges need paint.
    if not state.cardBacking then NS.Surface.PaintFill(center, nil, fill, nil, plan.fill) end
    SaveColor(fill.applied, Safety.ReadColor(center, "GetVertexColor"))

    local r, g, b, alpha = plan.r, plan.g, plan.b, plan.alpha
    if state.tint then r, g, b = unpack(state.tint) end
    -- Blizzard can install another region in the same slice. Resolve the
    -- live handle before using its retained original and applied colors.
    for index = 1, #borderPieces do
        local region = Safety.Field(slice, borderPieces[index])
        local paint = Capture(state, region)
        if paint then
            region:SetVertexColor(r, g, b, alpha)
            SaveColor(paint.applied, r, g, b, alpha)
        end
    end
    return true
end

local function Flush()
    scheduled = false
    for frame in pairs(pending) do
        pending[frame] = nil
        local state = tooltips[frame]
        if state then Safety.Dispatch(Paint, frame, state) end
    end
end

local function RequestPaint(frame)
    pending[frame] = true
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, Flush)
end

function TooltipChrome.SettleBackdrop(frame)
    if not pending[frame] then return end
    pending[frame] = nil
    local state = tooltips[frame]
    if state then Safety.Dispatch(Paint, frame, state) end
end

-- Both clients reset the Center color in SharedTooltip_SetBackdropStyle.
-- Keep a visible card and the native body on the same palette even when an
-- item hover rebuilds the tooltip. Other chrome can settle once per frame.
local function OnStyleChanged(frame)
    if not Safety.Public(frame) or type(frame) ~= "table" or not tooltips[frame] then return end
    if NS.ItemTooltipCard and NS.ItemTooltipCard.HasVisibleHeader(frame) then
        pending[frame] = true
        TooltipChrome.SettleBackdrop(frame)
    else RequestPaint(frame) end
end

local function OnThemeChanged(_, domain)
    if domain ~= "theme" and domain ~= "color" and domain ~= "appearance"
        and domain ~= "geometry" and domain ~= "profile" and domain ~= "tooltipStyle" then return end
    plan = nil
    if next(tooltips) then PrepareStyle() end
    for frame in pairs(tooltips) do RequestPaint(frame) end
end

-- The card draws its own fill around the native content. Leave the nine-slice
-- layout intact, with only its paint suppressed for the life of that card.
function TooltipChrome.SetCardBacking(frame, mode)
    local state = tooltips[frame]
    if not state then return false end
    if state.cardBacking == mode then return true end
    state.cardBacking = mode
    local ok = Paint(frame, state)
    if not ok then
        state.cardBacking = nil
        RequestPaint(frame)
    end
    return ok
end

function TooltipChrome.IsActive(frame)
    return tooltips[frame] ~= nil
end

function TooltipChrome.Apply(frame, owner)
    if not Safety.Public(frame) or not Safety.CanDecorate(frame) then return false, "protected" end
    local state = tooltips[frame]
    if not state then
        state = { owners = {}, regions = setmetatable({}, { __mode = "k" }) }
        tooltips[frame] = state
    end
    state.owners[owner] = true
    if not styleHooked and type(SharedTooltip_SetBackdropStyle) == "function" then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", OnStyleChanged)
        NS.Registry.AddListener(TooltipChrome, OnThemeChanged)
        styleHooked = true
    end
    return Paint(frame, state)
end

-- QoL supplies its item/class color through Surface.TintEdge. Keep the
-- request with this tooltip so Blizzard style resets cannot overwrite it.
function TooltipChrome.TintEdge(frame, r, g, b)
    if not Safety.Public(frame) or not Safety.CanDecorate(frame) then return false end
    local state = tooltips[frame]
    if not state then return false end
    if Safety.Public(r) and r == nil then
        state.tint = nil
    elseif Safety.Public(r) and Safety.Public(g) and Safety.Public(b)
        and type(r) == "number" and type(g) == "number" and type(b) == "number" then
        state.tint = state.tint or {}
        state.tint[1], state.tint[2], state.tint[3] = r, g, b
    else
        return false
    end
    RequestPaint(frame)
    return true
end

local function Restore(region, paint)
    if not Safety.CanDecorate(region) then return end
    local r, g, b, a = Safety.ReadColor(region, "GetVertexColor")
    local owned = Safety.ColorMatches(paint.applied, r, g, b, a, Safety.COLOR_OWN)
    if paint.gradientFrom then
        -- Blizzard's tooltip atlases use a flat tint. Remove our gradient
        -- independently of a native style reset that changed the vertex color.
        local white = CreateColor(1, 1, 1, 1)
        region:SetGradient("VERTICAL", white, white)
    end
    if owned then
        region:SetVertexColor(unpack(paint.original))
    elseif paint.gradientFrom and r ~= nil then
        region:SetVertexColor(r, g, b, a)
    end
end

function TooltipChrome.DisableOwner(owner)
    for frame, state in pairs(tooltips) do
        state.owners[owner] = nil
        if not next(state.owners) then
            tooltips[frame], pending[frame] = nil, nil
            for region, paint in pairs(state.regions) do Restore(region, paint) end
            RevealCenter(state)
            NS.Cosmetics.RestoreOwner(state)
        end
    end
end
