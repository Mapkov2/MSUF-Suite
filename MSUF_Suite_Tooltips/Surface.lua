local _, NS = ...
local Suite = NS.SuiteCore()
local Theme = {}
NS.Theme = Theme
local roles = { popup = "background", panel = "background", ink = "background", title = "text",
    text = "text", border = "border", accent = "accent" }
local looks = { cleanModern = 4, midnight = 1, foreverGlass = 3, midnightDark = 2,
    classColor = 5, gridClassic = 3, modern = 1 }
NS.LookOrder = { "cleanModern", "midnight", "foreverGlass", "midnightDark", "classColor" }
NS.LookPresets = {
    cleanModern = { label = "Clean Modern" }, midnight = { label = "Midnight Blue" },
    foreverGlass = { label = "MSUF Forever Glass" }, midnightDark = { label = "Midnight Dark" },
    classColor = { label = "Class Style" },
}

local function PaletteChannels(palette, role)
    local hex = tonumber(palette[roles[role]], 16)
    return math.floor(hex / 65536) / 255, math.floor(hex / 256) % 256 / 255, hex % 256 / 255, 1
end

local skin, currentPalette
function NS.RefreshPalette()
    skin = Suite.Skin.TooltipTheme()
    local active = Suite.DB and Suite.DB.suite
    local palette = Suite.QoLVisualStyles[active and looks[active.globalLook] or 4]
    currentPalette = currentPalette or {}
    for role in pairs(roles) do currentPalette[role] = { PaletteChannels(palette, role) } end
end

function Theme.GetColor(role)
    if skin then return skin.Theme.GetColor(role) end
    return unpack(currentPalette[role])
end

function Theme.StyleProfile(profile, look)
    if skin then return skin.Theme.StyleProfile(profile, look) end
    local palette = Suite.QoLVisualStyles[looks[look]]
    if not palette then return false end
    local colors = {}
    for role in pairs(roles) do colors[role] = { PaletteChannels(palette, role) } end
    profile.theme.colors, profile.theme.shellOpacity, profile.theme.borderOpacity = colors, .97, 1
    profile.theme.gradient, profile.theme.gradientDirection = false, "VERTICAL"
    return true
end

NS.LabelStyle = {
    Apply = function(...)
        if skin then skin.LabelStyle.Apply(...) end
    end,
}

function Theme.Border()
    local r, g, b, a = Theme.GetColor("border")
    if skin then
        local width = skin.DB.geometry.border
        a = width > 0 and a * skin.Theme.GetBorderOpacity() or 0
    end
    return r, g, b, a
end

local function ResolveFill(spec)
    if spec.resolveFill then
        local r, g, b, a, tr, tg, tb, ta, gradient, direction = spec.resolveFill(spec)
        if r ~= nil then return r, g, b, a, tr, tg, tb, ta, gradient, direction end
    end
    if skin then
        local style = skin.DB.theme
        local r, g, b, a = skin.Theme.GetColor(spec.role)
        local tr, tg, tb, ta = skin.Theme.GetColor("ink")
        local opacity = spec.role == "popup" and style.shellOpacity or style.panelOpacity
        local strength = style.gradientStrength or 1
        return r, g, b, spec.opaqueFill and 1 or a * opacity,
            r + (tr - r) * strength, g + (tg - g) * strength, b + (tb - b) * strength,
            spec.opaqueFill and 1 or (a + (ta - a) * strength) * opacity,
            style.gradient == true, style.gradientDirection or "VERTICAL"
    end
    local r, g, b = Theme.GetColor(spec.role)
    return r, g, b, spec.opaqueFill and 1 or .97, r, g, b, 1, false, "VERTICAL"
end

local Surface, fills = {}, setmetatable({}, { __mode = "k" })
NS.Surface = Surface
local media = {}

local function ResolveMedia(key, library)
    if key == "" then return end
    local builtins = _G.MSUF_BUILTIN_BAR_TEXTURES
    if (builtins and builtins[key]) or (library and library:Fetch("statusbar", key, true)) then
        return Suite.ResolveTexture(key)
    end
end

function Surface.RefreshMedia()
    local setting = NS.ItemTooltipCard.Setting
    local library = Suite.SharedMedia()
    media.background = ResolveMedia(setting("backgroundTexture"), library)
    media.header = ResolveMedia(setting("headerTexture"), library)
end

function Surface.MediaPath(role) return media[role] end

function Surface.SetMediaTexture(texture, state, role)
    local path = media[role]
    if state.mediaTexture == path then return end
    state.mediaTexture = path
    if path then texture:SetTexture(path)
    else texture:SetColorTexture(1, 1, 1, 1) end
end

local function ColorObject(existing, r, g, b, a)
    if existing and existing.r == r and existing.g == g and existing.b == b and existing.a == a then return existing end
    return CreateColor(r, g, b, a)
end

function Surface.PrepareFill(_, spec) return { ResolveFill(spec) } end

function Surface.PaintFill(texture, _, state, _, prepared)
    local r, g, b, a, tr, tg, tb, ta, gradient, direction = unpack(prepared)
    if gradient or state.gradientFrom then
        texture:SetVertexColor(1, 1, 1, 1)
        state.gradientFrom = ColorObject(state.gradientFrom, r, g, b, a)
        local finish = state.gradientFrom
        if gradient then
            state.gradientTo = ColorObject(state.gradientTo, tr, tg, tb, ta)
            finish = state.gradientTo
        end
        texture:SetGradient(direction, state.gradientFrom, finish)
    else
        texture:SetVertexColor(r, g, b, a)
    end
end

local function UpdateVisibility(state)
    local shown = state.visible or state.spec.media == "header" and media.header ~= nil
    if shown ~= state.shown then
        state.shown = shown
        state.texture:SetShown(shown)
    end
end

local function Paint(state)
    if not NS.Safety.CanDecorate(state.texture) then return end
    Surface.SetMediaTexture(state.texture, state, state.spec.media)
    UpdateVisibility(state)
    Surface.PaintFill(state.texture, nil, state, nil, Surface.PrepareFill(nil, state.spec))
end

function Surface.Attach(frame, spec)
    local state = fills[frame]
    if not state then
        if not NS.Safety.CanCreateRegions(frame) then return false end
        local texture = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        texture:SetAllPoints()
        texture:SetColorTexture(1, 1, 1, 1)
        state = { texture = texture, visible = true, shown = true }
        fills[frame] = state
    end
    if state.spec ~= spec then
        state.spec = spec
        Paint(state)
    end
    return true
end

function Surface.SetVisible(frame, visible)
    local state = fills[frame]
    if state then
        state.visible = visible
        UpdateVisibility(state)
    end
end

function Surface.RefreshAll()
    for _, state in pairs(fills) do Paint(state) end
end
