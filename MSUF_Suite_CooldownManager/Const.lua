local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Shared constants and cold-path helpers for the render plane: glow styles
-- and their flipbook animations, step curves for desaturation and cooldown
-- opacity (cached per value pair), pixel snapping, the 9-point anchor table,
-- tint colors, the hardcoded spell-category icons, the icon crop, the class
-- color, the per-spell choice rules, the growth-edge offset, automatic text
-- sizes, the countdown formatter and the fallbacks several layers share.
local K = {}
C.Const = K
local floor, max = math.floor, math.max
local type = type

-- The GCD's recovery category (133 on every client).
K.GCD_CATEGORY = Constants.SpellCooldownConsts.GLOBAL_RECOVERY_CATEGORY
K.QUESTION_ICON = 134400
-- The catalog's named choice values (Core/Catalog/CooldownManager.lua):
-- bar kinds, the "Show" rule, the bar's "Text on top" and the per-spell
-- choices.
local CDM = NS.CDM
K.KIND, K.VIS, K.TEXT_TOP = CDM.KIND, CDM.VIS, CDM.TEXT_TOP
K.CHOICE, K.DESAT, K.SWIPE, K.STACK_OP, K.ACTION_GLOW = CDM.CHOICE, CDM.DESAT, CDM.SWIPE, CDM.STACK_OP, CDM.ACTION_GLOW
-- The family of a Blizzard catalog entry and the bar's layout choices.
K.FAMILY, K.GROW, K.ALIGN, K.SIDE, K.ANCHOR, K.OVERFLOW = CDM.FAMILY, CDM.GROW, CDM.ALIGN, CDM.SIDE, CDM.ANCHOR, CDM.OVERFLOW
K.BAR_FILL, K.BAR_ICON_SIDE, K.BLIZZARD = CDM.BAR_FILL, CDM.BAR_ICON_SIDE, CDM.BLIZZARD
local KIND, CHOICE, TEXT_TOP = K.KIND, K.CHOICE, K.TEXT_TOP
local COOLDOWN, AURA_BAR, COUNTDOWN_ON_TOP = KIND.COOLDOWN, KIND.AURA_BAR, TEXT_TOP.COUNTDOWN
-- The kinds drawn by the aura layer (buff icons and buff bars).
K.AURA_KINDS = { [KIND.AURA_ICON] = true, [KIND.AURA_BAR] = true }
-- Catalog choice "Frame layer" and the default bar texture.
K.STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH" }
K.BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
K.WHITE = "Interface\\Buttons\\WHITE8X8"

------------------------------------------------------------------ fallbacks
-- A view read from the settings carries every value of its bar; these
-- apply only where one is absent (stand-in views such as the options
-- canvas). Each was copied in several layers before, and two drifted.
-- Swipe opacity in percent: the catalog default of every cooldown bar and
-- every custom bar, whatever its kind (the built-in Buffs and Buff bars
-- carry their own 60 in the catalog, which reaches their views). The aura
-- buttons fell back to 60, the cooldown icons to 70.
K.SWIPE_ALPHA = 70
-- Bar fill: the Retail catalog default ("e8b855"); the cooldown timer bars
-- fell back to a drifted 1, .72, .34. Background opacity in percent.
K.BAR_RGB = { .91, .72, .33 }
K.BAR_BG_ALPHA = 55

-- The spell categories (spellCategory of a Blizzard record) of the bag
-- consumables the viewer shows as one entry each.
K.SPELL_CATEGORY = { COMBAT_POTION = 4, HEALTH_POTION = 30, HEALTHSTONE = 1711, DEMONIC_HEALTHSTONE = 2566 }
local SPELL_CATEGORY = K.SPELL_CATEGORY
-- Blizzard's viewers use these file paths for bag-item categories (potions,
-- healthstones); the space in the Warlock paths is part of the file name.
K.CATEGORY_ICONS = {
    [SPELL_CATEGORY.COMBAT_POTION] = "Interface/ICONS/INV_POTION_114",
    [SPELL_CATEGORY.HEALTH_POTION] = "Interface/ICONS/INV_POTION_54",
    [SPELL_CATEGORY.HEALTHSTONE] = "Interface/ICONS/Warlock_ Healthstone",
    [SPELL_CATEGORY.DEMONIC_HEALTHSTONE] = "Interface/ICONS/Warlock_ Bloodstone",
}

------------------------------------------------------------------ anchors
-- Index = catalog 9-point choice. X/Y are inward signs for text insets.
K.POINTS = NS.CDM.POINTS
K.POINT_X = { 1, 0, -1, 1, 0, -1, 1, 0, -1 }
K.POINT_Y = { -1, -1, -1, 0, 0, 0, 1, 1, 1 }
K.JUSTIFY = { "LEFT", "CENTER", "RIGHT", "LEFT", "CENTER", "RIGHT", "LEFT", "CENTER", "RIGHT" }

-- Frame levels above the icon frame: a timer bar's charge segments, swipe
-- (with its countdown), recharge edge, glow, text. The swipe moves to top,
-- above the text, for entries that show the countdown on top.
K.LEVEL = { fill = 1, cd = 2, charge = 3, glow = 4, assist = 5, text = 6, top = 7 }
-- Frame levels above an aura button, bottom to top. Buff bars: the fill,
-- the stack threshold colour, the stack markers, glows and pandemic edges,
-- then the countdown and name, then the stacks (Text on top swaps the last
-- two). Buff icons and overlays have no colour or markers and keep four
-- levels: swipe, glows, countdown, stacks. An overlay's stacks then reach
-- no higher than its cooldown icon's countdown on top (K.LEVEL.top).
K.AURA_LEVEL = { fill = 1, color = 2, marks = 3, glow = 4, text = 5, stacks = 6 }
K.AURA_ICON_LEVEL = { fill = 1, glow = 2, text = 3, stacks = 4 }

------------------------------------------------------------------ choices
-- A per-spell yes/no choice (ov: the entry's choices), else the bar's.
function K.Pick(ov, view, field)
    local value = ov[field]
    if value == nil then value = view[field] end
    return value == true
end
-- Per-spell text choices (timeText, stackText, textTop): CHOICE.YES,
-- CHOICE.NO, anything else the bar's answer. Every aura sync asks once per
-- button and text, so it is one table lookup.
local CHOSEN = { [CHOICE.YES] = true, [CHOICE.NO] = false }
function K.Choice(value, bar)
    local chosen = CHOSEN[value]
    if chosen ~= nil then return chosen end
    return bar == true
end
-- The bar's countdown switch; timer bars also follow "Show time".
function K.BarTime(view)
    return view.cdText ~= false and (view.kind ~= AURA_BAR and not view.cooldownDuration or view.barTime ~= false)
end
-- The bar's charge and stack switch; counts on cooldown icons also follow
-- the cooldown bar's "Show charges".
function K.BarStacks(view, counts)
    return view.stackText ~= false and not (counts and view.charges == false)
end
-- Text on top: stacks (true) unless the bar chose the countdown.
function K.BarStacksTop(view) return view.textTop ~= COUNTDOWN_ON_TOP end

------------------------------------------------------------------ tints
-- The usable states and their colors are S.USABLE and S.USABLE_TINT (shared
-- with the action bars); out of range paints the bar's range color.
K.GLOW_GOLD = { 1, .82, 0 }

------------------------------------------------------------------ game constants
-- The global cooldown's spell and the trinket equipment slots (Blizzard's
-- INVSLOT_TRINKET1 and INVSLOT_TRINKET2): every layer that names them uses these.
K.GCD_SPELL = 61304
K.TRINKET1, K.TRINKET2 = INVSLOT_TRINKET1, INVSLOT_TRINKET2

------------------------------------------------------------------ text sizes
-- A size setting of 0 means automatic: this share of the icon or bar
-- height, never below the floor. Cooldown and buff icons share the icon
-- specs, buff bars and cooldown timer bars the bar one. The floors that
-- drifted take what the bars show by default: buff bar text 9 (cooldown
-- timer bars, off by default, used 8), keybinds 8 (the assisted icon used
-- 9, which its default size of 48 never reaches).
K.FONT = {
    countdown = { share = .38, floor = 10 },
    stacks = { share = .3, floor = 9 },
    keybind = { share = .26, floor = 8 },
    barText = { share = .55, floor = 9 },
    barStacks = { share = .45, floor = 8 },
}
function K.TextSize(setting, spec, height)
    if type(setting) == "number" and setting > 0 then return setting end
    return max(spec.floor, floor(height * spec.share))
end

------------------------------------------------------------------ bounded caches
-- Native objects built per setting value (formatters, bindings, curves) are
-- shared by every user of that value. A color picker drag or a slider makes
-- a new value on every tick, so a cache keeps two generations of CACHE_LIMIT
-- entries: a full young generation becomes the old one and the previous old
-- one is dropped, so an object nothing uses any more is collected. A lookup
-- is one table read.
local CACHE_LIMIT = 256
K.CACHE_LIMIT = CACHE_LIMIT
function K.NewCache() return { young = {}, old = {}, n = 0 } end
local function Remember(cache, key, value)
    local n = cache.n + 1
    if n > CACHE_LIMIT then
        local recycled = cache.old
        for stale in pairs(recycled) do recycled[stale] = nil end
        cache.old, cache.young, n = cache.young, recycled, 1
    end
    cache.n = n
    cache.young[key] = value
    return value
end
K.Remember = Remember
function K.Recall(cache, key)
    local value = cache.young[key]
    if value ~= nil then return value end
    value = cache.old[key]
    if value ~= nil then Remember(cache, key, value) end
    return value
end
local Recall = K.Recall

------------------------------------------------------------------ countdown
-- One countdown formatter per (warning seconds, warning color): whole
-- seconds (below the threshold in the warning color), m:ss from a minute,
-- hours from an hour. No threshold: plain seconds. Shared by the cooldown
-- swipes (SetCountdownFormatter) and the aura buttons' duration text
-- bindings, built on first use and kept (bounded).
local countdowns = K.NewCache()
function K.CountdownFormatter(seconds, r, g, b)
    if type(seconds) ~= "number" or seconds <= 0 then
        seconds = 0
    else
        seconds = floor(seconds + .5)
    end
    local R, G, B = 0, 0, 0
    if seconds > 0 then R, G, B = floor((r or 1) * 255 + .5), floor((g or 1) * 255 + .5), floor((b or 1) * 255 + .5) end
    local key = seconds * 16777216 + R * 65536 + G * 256 + B
    local formatter = countdowns.young[key] or Recall(countdowns, key)
    if formatter then return formatter end
    local rounding = Enum.NumericRuleFormatRounding
    local up, down = rounding.Up, rounding.Down
    local points = { { threshold = 0, format = "%.0f", rounding = up } }
    if seconds > 0 then
        points[1].format = ("|cff%02x%02x%02x%%.0f|r"):format(R, G, B)
        points[2] = { threshold = seconds, format = "%.0f", rounding = up }
    end
    points[#points + 1] = { threshold = 60, format = "%d:%02d", rounding = down,
        components = { { div = 60, rounding = down }, { mod = 60, rounding = down } } }
    points[#points + 1] = { threshold = 3600, format = "%dh", rounding = down, components = { { div = 3600, rounding = down } } }
    formatter = C_StringUtil.CreateNumericRuleFormatter()
    formatter:SetBreakpoints(points)
    return Remember(countdowns, key, formatter)
end

------------------------------------------------------------------ glows
-- 1 Blizzard alert and 2 marching ants are 6x5 flipbooks (30 frames, 1 s
-- loop) scaled around the icon; 3 pulses a border, 4 is a static border.
K.GLOW = {
    { atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook", rows = 6, cols = 5, frames = 30, duration = 1, scale = 1.4 },
    { atlas = "rotationhelper_ants_flipbook", rows = 6, cols = 5, frames = 30, duration = 1, scale = 1.2 },
    { edge = 2, pulse = .6 },
    { edge = 2 },
}
K.ASSIST_STYLE = 2

-- Style and color of an entry's glows: its per-spell choices (ov) first,
-- then the bar's style and tint. No color: the art's own gold.
function K.GlowSpec(ov, style, tint, r, g, b)
    style = ov.glowStyle or style
    if not K.GLOW[style] then style = 1 end
    local hex = ov.glowColor
    if hex then return style, K.HexRGB(hex) end
    if tint then return style, r or 1, g or 1, b or 1 end
    return style
end

-- One looping FlipBook group per texture; the group only runs while played.
function K.FlipBook(texture, style)
    local group = texture:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local flip = group:CreateAnimation("FlipBook")
    group.flip = flip
    K.SetFlipBook(group, style)
    return group
end

function K.SetFlipBook(group, style)
    local flip = group.flip
    if group.style == style then return end
    group.style = style
    flip:SetFlipBookRows(style.rows)
    flip:SetFlipBookColumns(style.cols)
    flip:SetFlipBookFrames(style.frames)
    flip:SetFlipBookFrameWidth(0)
    flip:SetFlipBookFrameHeight(0)
    flip:SetDuration(style.duration)
end

-- Alpha bounce for the pulse style; animates the region it is created on.
function K.Pulse(region, duration)
    local group = region:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(.25)
    fade:SetDuration(duration)
    group.fade = fade
    return group
end

------------------------------------------------------------------ curves
-- Step curves from plain setting percentages: y0 while nothing remains,
-- y1 from 1 ms remaining on. Numeric cache key (bounded), built only on refresh.
local curves = K.NewCache()
function K.StepCurve(from, to)
    from, to = floor(from + .5), floor(to + .5)
    local key = from * 1000 + to
    local curve = curves.young[key] or Recall(curves, key)
    if curve then return curve end
    curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, from / 100)
    curve:AddPoint(.001, to / 100)
    return Remember(curves, key, curve)
end
function K.DesatCurve() return K.StepCurve(0, 100) end

------------------------------------------------------------------ pixels
-- C.state.px = UI units per physical pixel (Layout keeps it current).
function K.Px()
    local px = C.state.px
    if type(px) ~= "number" or px <= 0 then
        px = C.Layout.PixelScale()
        if type(px) ~= "number" or px <= 0 then px = 1 end
    end
    return px
end
function K.Snap(value)
    local px = K.Px()
    return floor(value / px + .5) * px
end
function K.Pixels(count) return count * K.Px() end

-- Icon footprint in UI units, snapped to whole physical pixels.
function K.IconSize(view)
    if view.kind == COOLDOWN and view.cooldownDuration then
        return K.Snap(view.barWidth or 200), K.Snap(view.barHeight or 18)
    end
    local px = K.Px()
    local size = view.size or 36
    local w = max(px, K.Snap(size))
    local h = max(px, K.Snap(size * (view.height or 100) / 100))
    return w, h
end

-- Texture crop for an iw x ih art area: zoom percent is the total crop,
-- split over both sides; the shorter axis is cropped further so non-square
-- icons keep the art's aspect. Returns left, right, top, bottom.
function K.Crop(zoom, iw, ih)
    local crop = (zoom or 0) / 200
    local span = 1 - 2 * crop
    local left, right, top, bottom = crop, 1 - crop, crop, 1 - crop
    if iw > 0 and ih > 0 then
        if ih < iw then
            local v = span * ih / iw
            top, bottom = .5 - v / 2, .5 + v / 2
        elseif iw < ih then
            local u = span * iw / ih
            left, right = .5 - u / 2, .5 + u / 2
        end
    end
    return left, right, top, bottom
end

-- The player's class color; nil while the class token is unreadable. The
-- token is read once, the color on every call (a class color addon may
-- change it).
local classToken
function K.ClassRGB()
    if classToken == nil then
        local token = false
        local _, file = UnitClass("player")
        if S.Public(file) and type(file) == "string" then token = file end
        classToken = token
    end
    if classToken then return S.ClassRGB(classToken) end
end

-- From a bar's center to its growth-edge point (Layout.Point) for a w x h bar.
function K.EdgeOffset(point, w, h)
    if point == "TOP" then
        return 0, h / 2
    elseif point == "BOTTOM" then
        return 0, -h / 2
    elseif point == "LEFT" then
        return -w / 2, 0
    end
    return w / 2, 0
end

-- A position setting rounded and clamped to its catalog rule.
function K.Clamp(key, value)
    local rule = NS.SuiteCatalog.cooldownManager.rules[key]
    value = floor(value + .5)
    if rule and type(rule.min) == "number" and value < rule.min then value = rule.min end
    if rule and type(rule.max) == "number" and value > rule.max then value = rule.max end
    return value
end

-- Four OVERLAY textures on owner for K.PlaceEdges.
function K.NewEdges(owner, sublevel)
    local set = {}
    for i = 1, 4 do set[i] = S.CreateTexture(owner, nil, "OVERLAY", nil, sublevel) end
    return set
end

-- Four edges inside owner's rect (shared with the action bars).
K.PlaceEdges = S.PlaceEdges

-- Spell ID sets (id -> true): equal members, and a copy into a kept table.
function K.SameSet(a, b)
    for id in pairs(a) do
        if not b[id] then return false end
    end
    for id in pairs(b) do
        if not a[id] then return false end
    end
    return true
end
function K.CopySet(into, from)
    C.wipe(into)
    for id in pairs(from) do into[id] = true end
    return into
end

-- Hex -> rgb for per-spell glow, keybind and stack colors; a hex in use is
-- decoded once, and a color picker drag keeps only two generations.
local hexCache = K.NewCache()
function K.HexRGB(hex)
    local rgb = hexCache.young[hex] or Recall(hexCache, hex)
    if not rgb then
        local r, g, b = S.RGB(hex)
        rgb = Remember(hexCache, hex, { r, g, b })
    end
    return rgb[1], rgb[2], rgb[3]
end
