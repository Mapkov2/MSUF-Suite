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
-- The name a bar row shows (timer bars, buff bars, their stand-ins and
-- timer rows): the entry's own (barText; "" the spell's), else the spell's.
function K.EntryLabel(entry)
    local text = entry and entry.ov and entry.ov.barText
    if text and text ~= "" then return text end
    return entry and entry.name or ""
end

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
-- One countdown formatter per (warning seconds, warning color) and the
-- Text section's tenths and urgent stage: whole seconds (below the warning
-- threshold in the warning color, below the urgent one in the urgent color,
-- below the tenths one with tenths), m:ss from a minute, hours from an hour.
-- Nothing set: plain seconds. Shared by the cooldown swipes
-- (SetCountdownFormatter) and the aura buttons' duration text bindings,
-- built on first use and kept (bounded). Only breakpoints: the remaining
-- time, secret in combat, stays in C.
local countdowns = K.NewCache()
local function Whole(value)
    if type(value) ~= "number" or value <= 0 then return 0 end
    return floor(value + .5)
end
local function Bytes(r, g, b) return floor((r or 1) * 255 + .5), floor((g or 1) * 255 + .5), floor((b or 1) * 255 + .5) end
-- Where the look below a minute changes, rising, each value once.
local function Cut(cuts, value)
    if value <= 0 then return end
    for i = 1, #cuts do
        if cuts[i] == value then return end
    end
    cuts[#cuts + 1] = value
end
-- The point from a cut up to the next: tenths (a 0.1 step, rounded up like
-- the whole seconds) and the stage's color.
local function Stage(from, seconds, tenths, urgent, warn, alarm, up)
    local format, step = "%.0f", nil
    if from < tenths then format, step = "%.1f", .1 end
    local hex = from < urgent and alarm or from < seconds and warn or nil
    if hex then format = "|cff" .. hex .. format .. "|r" end
    return { threshold = from, format = format, rounding = up, step = step }
end
function K.CountdownFormatter(seconds, r, g, b, tenths, urgent, ur, ug, ub)
    seconds, tenths, urgent = Whole(seconds), Whole(tenths), Whole(urgent)
    local R, G, B = 0, 0, 0
    if seconds > 0 then R, G, B = Bytes(r, g, b) end
    local key = seconds * 16777216 + R * 65536 + G * 256 + B
    local UR, UG, UB = 0, 0, 0
    if urgent > 0 then UR, UG, UB = Bytes(ur, ug, ub) end
    if tenths > 0 or urgent > 0 then key = ("%d:%d:%d:%d"):format(key, tenths, urgent, UR * 65536 + UG * 256 + UB) end
    local formatter = countdowns.young[key] or Recall(countdowns, key)
    if formatter then return formatter end
    local rounding = Enum.NumericRuleFormatRounding
    local up, down = rounding.Up, rounding.Down
    local cuts = { 0 }
    Cut(cuts, tenths)
    Cut(cuts, urgent)
    Cut(cuts, seconds)
    table.sort(cuts)
    local warn, alarm = ("%02x%02x%02x"):format(R, G, B), ("%02x%02x%02x"):format(UR, UG, UB)
    local points = {}
    for i = 1, #cuts do points[i] = Stage(cuts[i], seconds, tenths, urgent, warn, alarm, up) end
    points[#points + 1] = { threshold = 60, format = "%d:%02d", rounding = down,
        components = { { div = 60, rounding = down }, { mod = 60, rounding = down } } }
    points[#points + 1] = { threshold = 3600, format = "%dh", rounding = down, components = { { div = 3600, rounding = down } } }
    formatter = C_StringUtil.CreateNumericRuleFormatter()
    formatter:SetBreakpoints(points)
    return Remember(countdowns, key, formatter)
end

-- The Text section's countdown stages for a warning threshold (seconds: an
-- entry's own or the bar's): its formatter, nil while nothing asks for one
-- (the swipe keeps Blizzard's own countdown text). C.state.cdExtra: tenths
-- or an urgent stage set (Settings.ReadGlobals).
function K.Countdown(seconds)
    local state = C.state
    if not (state.cdExtra or type(seconds) == "number" and seconds > 0) then return nil end
    return K.CountdownFormatter(seconds, state.thR, state.thG, state.thB, state.tenths, state.urgent, state.urR, state.urG, state.urB)
end

-- Duration text options per countdown formatter: a binding template that
-- Blizzard copies into each aura button, around the shared formatter. The
-- fallbacks must ride on the binding, and without a formatter on it no text
-- renders at all. Every entry of a sync asks for the same few signatures,
-- so the last answer is kept: a repeat costs four compares. The Text
-- section's tenths and urgent stage drop it (K.ForgetDurationText, the
-- settings read).
local textOpts = K.NewCache()
local lastSeconds, lastR, lastG, lastB, lastOpts
function K.DurationText(seconds)
    local state = C.state
    local r, g, b = state.thR, state.thG, state.thB
    if lastOpts and seconds == lastSeconds and r == lastR and g == lastG and b == lastB then return lastOpts end
    local formatter = K.CountdownFormatter(seconds, r, g, b, state.tenths, state.urgent, state.urR, state.urG, state.urB)
    local opts = textOpts.young[formatter] or Recall(textOpts, formatter)
    if not opts then
        local binding = C_DurationUtil.CreateDurationTextBinding()
        binding:SetFormatter(formatter)
        binding:SetZeroDurationText("")
        binding:SetExpiredText("")
        binding:SetUpdateInterval(.1)
        binding:SetEnabled(true)
        opts = Remember(textOpts, formatter, { binding = binding })
    end
    lastSeconds, lastR, lastG, lastB, lastOpts = seconds, r, g, b, opts
    return opts
end
function K.ForgetDurationText() lastOpts = nil end

------------------------------------------------------------------ swipes and sparks
-- A bar's swipe color ("Swipe color", or "Class-colored swipe" while the
-- class color is readable); black where a view has none. Read where the
-- swipe is styled, never per update.
function K.SwipeRGB(view)
    if view.swipeClass then
        local r, g, b = K.ClassRGB()
        if r then return r, g, b end
    end
    return view.swipeR or 0, view.swipeG or 0, view.swipeB or 0
end
-- The active buff's swipe over a cooldown icon: its bar's color; the gold
-- it always had for the default value and where a view has none.
local AURA_SWIPE = CDM.AURA_SWIPE
function K.AuraSwipeRGB(view)
    local hex = view.auraSwipeColor
    if hex == nil or hex == AURA_SWIPE then return K.GLOW_GOLD[1], K.GLOW_GOLD[2], K.GLOW_GOLD[3] end
    return view.auraSwipeR or 0, view.auraSwipeG or 0, view.auraSwipeB or 0
end
-- "Show a spark": a thin bright line on a timer bar's fill edge, anchored to
-- the bar's fill texture, so the client moves it with the fill (draining or
-- filling, the fill grows from the left and its right edge moves). Made on
-- first use on owner (own: one of our frames, else a region inside an aura
-- button) and kept in holder.spark; holder.sparkOn says whether it shows.
function K.Spark(holder, on, owner, own, fill, height, px)
    local spark = holder.spark
    if on and not spark then
        spark = own and S.CreateTexture(owner, nil, "ARTWORK", nil, 7) or owner:CreateTexture(nil, "ARTWORK", nil, 7)
        spark:SetColorTexture(1, 1, 1, .9)
        spark:SetBlendMode("ADD")
        holder.spark = spark
    end
    holder.sparkOn = on
    if not spark then return end
    spark:SetShown(on)
    if not on then return end
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
    spark:SetSize(2 * px, height)
end

------------------------------------------------------------------ glows
-- 1 Blizzard alert and 2 marching ants are 6x5 flipbooks (30 frames, 1 s
-- loop) scaled around the icon; 3 pulses a border, 4 is a static border.
-- 5 Pixel and 6 Autocast: lines or sparks travelling around the border
-- (GlowLines.lua; lap: seconds per round at 100 percent speed), a still
-- border (edge) where they cannot run: a shaped icon, a glow built without
-- them.
K.GLOW = {
    { atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook", rows = 6, cols = 5, frames = 30, duration = 1, scale = 1.4 },
    { atlas = "rotationhelper_ants_flipbook", rows = 6, cols = 5, frames = 30, duration = 1, scale = 1.2 },
    { edge = 2, pulse = .6 },
    { edge = 2 },
    { edge = 2, lines = "pixel", lap = 4 },
    { edge = 2, lines = "spark", lap = 6 },
}
K.LINE_STYLES = CDM.LINE_STYLES
K.ASSIST_STYLE = 2

-- Style and color of an entry's glows: its per-spell choices (ov) first,
-- then the bar's style and tint (glowStyle 0 and glowColor "": the bar's,
-- chosen by a specialization over a shared choice). No color: the art's
-- own gold.
function K.GlowSpec(ov, style, tint, r, g, b)
    local own = ov.glowStyle
    if own ~= 0 then style = own or style end
    if not K.GLOW[style] then style = 1 end
    local hex = ov.glowColor
    if hex and hex ~= "" then return style, K.HexRGB(hex) end
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
        return K.Snap(view.barW or view.barWidth or 200), K.Snap(view.barHeight or 18)
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

-- MSUF's ring art per shape ({ ring, desaturate } or false), read once out
-- of combat (the settings read's K.ShapeOf and a shape's decoration ask
-- first; a new bridge reads again): placing rings later, a glow's repaint in
-- combat too, asks MSUF nothing.
local ringArt, ringAsk = {}, nil
function K.RingArt(shape)
    local ask = NS.HostBridge.IconShapeArt
    if ask ~= ringAsk then ringArt, ringAsk = {}, ask end
    local art = ringArt[shape]
    if art == nil then
        local ring, _, _, desaturate = ask(shape)
        art = ring and { ring, desaturate == true } or false
        ringArt[shape] = art
    end
    return art
end

-- MSUF's icon shape of a bar (the iconShape choice): MSUF's id, RECTANGLE
-- when square or on a host without shapes (the bar keeps its square border).
K.SQUARE = "RECTANGLE"
function K.ShapeOf(view)
    local shape = NS.IconShapeIds[view.iconShape or 1] or K.SQUARE
    if shape ~= K.SQUARE and not K.RingArt(shape) then shape = K.SQUARE end
    return shape
end

-- A timer bar without its icon ("Display cooldowns as timer bars", icon off)
-- has nothing to skin or shape: it keeps its square border.
function K.Iconless(view)
    return view.cooldownDuration and view.kind == COOLDOWN and view.barIcon == false
end

-- What MSUF draws on a cooldown bar's icons (view.decor), made by the
-- settings read: { skin, shape (nil when square), view: with a skin, the view
-- for the plain icon style with no border (the skin draws it), base: the view
-- it was made for }, or false for nothing, so the icon style of a bar without
-- a skin or shape is the plain one. The table stays while the look does (a
-- settings read that changes something else keeps it): an icon decorated
-- with it is up to date (Icons.lua's StyleDecorated).
function K.Decor(view)
    local skin, shape = view.skin, view.shape
    if shape == K.SQUARE then shape = nil end
    if K.Iconless(view) or not (skin or shape) then
        view.decor = false
        return
    end
    local decor = rawget(view, "decor")
    if decor and decor.base == view and decor.shape == shape
        and (decor.skin and decor.skin.signature) == (skin and skin.signature) then return end
    view.decor = { skin = skin, shape = shape, base = view,
        view = skin and setmetatable({ border = 0 }, { __index = view }) or nil }
end

-- A set's ring textures up to `count`, hidden: made out of combat (a shaped
-- icon's decoration), so placing them later makes none.
function K.EnsureRings(set, owner, count)
    for i = #set + 1, count do
        local texture = S.CreateTexture(owner, nil, "BORDER", nil, -1)
        texture:Hide()
        set[i] = texture
    end
end

-- The border of a shaped icon: `count` rings of the shape's art one pixel
-- apart around `anchor`, on owner's BORDER layer under the icon art (STAR's
-- filled silhouette then shows as an outline). A square shape, no host art or
-- count 0 hides them; `set` is the owner's own list.
function K.PlaceRings(set, owner, anchor, shape, count, r, g, b)
    local art = shape and shape ~= K.SQUARE and K.RingArt(shape)
    if not art then count = 0 end
    K.EnsureRings(set, owner, count)
    local px = K.Px()
    for i = 1, count do
        local texture = set[i]
        texture:SetTexture(art[1])
        texture:SetDesaturated(art[2])
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", anchor, "TOPLEFT", -i * px, i * px)
        texture:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", i * px, -i * px)
        texture:SetVertexColor(r, g, b, 1)
        texture:Show()
    end
    for i = count + 1, #set do set[i]:Hide() end
end

-- A frame inside an aura button, or inside one of ours there, made with its
-- parent in the one CreateFrame call. The client refuses to SetParent a
-- frame into an aura button later ("Reparenting disallowed as child object
-- would inherit forbidden aspects": the button's ForbiddenAspects,
-- Blizzard_AuraButton.xml:16-24, would pass to it). Forever's SmartNavigation
-- walks the parent chain of every frame made with a parent while a gamepad
-- panel is open (SmartNavigation.lua:203-209, :921-934) and throws inside an
-- aura button (:929), so each build that makes one waits for the panel
-- (AuraButtons.Blocked). Blizzard never runs initializeFrame on its own
-- later: a group shows one frame (maxFrameCount 1) of the ten AddAuraGroup
-- pre-builds and releases before it acquires (AuraContainerGroups.lua
-- :241-305), so its pool never grows (AuraContainerFrameProviders.lua
-- :102-105). The client's CreateFrame: Blizzard lays these out.
function K.Child(kind, parent, template)
    return CreateFrame(kind, nil, parent, template)
end

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

-- BEGIN NATIVE PLAYER AURA IDENTITIES
-- Blizzard DB2 12.1.5.70391; all 40 Retail specs audited.
-- Complete base/linked identity sets with caster-only aura effects.
-- Regenerate: python tools/generate_cdm_aura_units.py
K.PLAYER_AURA_IDS = {
    [208] = { [88747] = true },
    [875] = { [363916] = true },
    [882] = { [406732] = true },
    [1341] = { [274837] = true },
    [1721] = { [357210] = true },
    [1737] = { [363916] = true },
    [1756] = { [363916] = true },
    [1762] = { [406732] = true },
    [1769] = { [357210] = true },
    [2058] = { [120517] = true },
    [2230] = { [421453] = true },
    [2234] = { [472433] = true },
    [2268] = { [260243] = true },
    [2699] = { [204066] = true },
    [2742] = { [265187] = true },
    [3229] = { [204066] = true },
    [4333] = { [1953] = true },
    [4402] = { [342245] = true, [342246] = true },
    [4931] = { [1953] = true },
    [4937] = { [342245] = true, [342246] = true },
    [5684] = { [1953] = true },
    [5690] = { [342245] = true, [342246] = true },
    [6624] = { [365350] = true, [365362] = true },
    [7517] = { [1250646] = true },
    [8191] = { [120644] = true },
    [9056] = { [145205] = true },
    [9125] = { [49998] = true, [463730] = true },
    [9944] = { [205180] = true },
    [10234] = { [101643] = true },
    [10240] = { [132578] = true },
    [10486] = { [132578] = true },
    [10489] = { [132578] = true },
    [11353] = { [198793] = true },
    [11853] = { [315341] = true },
    [11873] = { [13877] = true, [22482] = true },
    [11923] = { [322118] = true },
    [11926] = { [119996] = true },
    [12368] = { [325197] = true },
    [12424] = { [26573] = true },
    [12425] = { [53600] = true, [132403] = true },
    [12650] = { [443294] = true, [443421] = true, [443616] = true, [1238904] = true },
    [12821] = { [384352] = true, [466772] = true },
    [13370] = { [462620] = true },
    [13371] = { [61882] = true },
    [13374] = { [114050] = true, [1219480] = true },
    [13388] = { [198103] = true },
    [15295] = { [228920] = true },
    [18448] = { [228920] = true },
    [18459] = { [23922] = true },
    [18794] = { [1122] = true, [111685] = true },
    [19397] = { [20271] = true },
    [22788] = { [43265] = true },
    [23563] = { [157299] = true, [157319] = true, [191717] = true },
    [24093] = { [118291] = true, [188592] = true, [378255] = true },
    [25015] = { [34433] = true, [1280172] = true },
    [26429] = { [352278] = true },
    [26650] = { [352278] = true },
    [27906] = { [43265] = true },
    [27922] = { [49206] = true, [207349] = true, [1242147] = true },
    [29346] = { [26573] = true },
    [29970] = { [73920] = true },
    [29974] = { [108280] = true },
    [29993] = { [198103] = true },
    [29997] = { [73685] = true },
    [30357] = { [113656] = true },
    [30362] = { [152175] = true },
    [30363] = { [123904] = true },
    [30456] = { [119996] = true },
    [30502] = { [443294] = true, [443421] = true, [443616] = true, [1238904] = true },
    [30853] = { [32645] = true },
    [30875] = { [36554] = true },
    [31507] = { [36554] = true },
    [33121] = { [108280] = true },
    [33227] = { [73920] = true, [1307888] = true },
    [40444] = { [198793] = true },
    [40452] = { [196718] = true },
    [40607] = { [370965] = true },
    [40638] = { [188499] = true },
    [42285] = { [269513] = true },
    [42394] = { [269513] = true },
    [49408] = { [1226019] = true },
    [50002] = { [43265] = true, [188290] = true },
    [53326] = { [365350] = true, [365362] = true },
    [54939] = { [359816] = true },
    [55006] = { [377509] = true },
    [57950] = { [352278] = true },
    [58119] = { [119996] = true },
    [61614] = { [325197] = true },
    [61652] = { [322118] = true },
    [62774] = { [269513] = true },
    [65812] = { [357210] = true },
    [74402] = { [1246167] = true },
    [77097] = { [421453] = true },
    [77103] = { [197871] = true, [1218211] = true },
    [77363] = { [188616] = true, [198103] = true },
    [77971] = { [204330] = true, [460697] = true },
    [78235] = { [23922] = true },
    [78276] = { [23922] = true },
    [79875] = { [118323] = true, [188616] = true, [198103] = true },
    [82369] = { [188616] = true, [198103] = true },
    [82621] = { [384352] = true, [466772] = true },
    [82624] = { [187874] = true, [187878] = true, [1252415] = true },
    [84224] = { [265187] = true },
    [90199] = { [203964] = true, [213708] = true, [1253600] = true },
    [90224] = { [196718] = true },
    [90226] = { [198793] = true },
    [90490] = { [452402] = true, [452416] = true },
    [90567] = { [145205] = true },
    [92072] = { [363916] = true },
    [92075] = { [406732] = true },
    [92251] = { [363916] = true },
    [92254] = { [406732] = true },
    [92278] = { [363916] = true },
    [92281] = { [406732] = true },
    [92515] = { [73685] = true },
    [92923] = { [288853] = true, [1242608] = true },
    [93054] = { [271877] = true, [271896] = true },
    [93076] = { [315341] = true },
    [93217] = { [1261867] = true },
    [93222] = { [1263657] = true, [1263890] = true },
    [93355] = { [1261867] = true },
    [93848] = { [1261193] = true },
    [94196] = { [1259171] = true, [1259174] = true },
    [94264] = { [406732] = true },
    [100280] = { [1250378] = true, [1250385] = true },
    [100331] = { [1250378] = true, [1250385] = true },
    [105002] = { [36554] = true },
    [105493] = { [32645] = true },
    [108049] = { [373277] = true },
    [113211] = { [73685] = true },
    [117418] = { [371806] = true, [371807] = true },
    [126656] = { [1261992] = true, [1262094] = true },
    [132299] = { [434587] = true, [1245089] = true },
    [135605] = { [1276672] = true },
    [135606] = { [1276672] = true },
    [145680] = { [472433] = true },
    [146798] = { [200174] = true, [1230339] = true },
    [146799] = { [451234] = true, [451235] = true },
    [146866] = { [34433] = true, [1280172] = true },
    [146867] = { [123040] = true, [1280137] = true },
    [146868] = { [451234] = true, [451235] = true },
    [149195] = { [1253799] = true },
    [149268] = { [1253799] = true },
    [151835] = { [1261867] = true },
    [152137] = { [191034] = true, [1261867] = true, [1261872] = true },
    [152377] = { [1261867] = true },
    [154204] = { [49206] = true, [1242147] = true },
    [156301] = { [1250646] = true },
    [158083] = { [198103] = true },
    [160573] = { [389714] = true, [1270829] = true },
    [160638] = { [389714] = true, [1270829] = true },
    [160699] = { [389714] = true, [1270829] = true },
    [164535] = { [1264614] = true, [1264618] = true },
    [174832] = { [137041] = true, [444995] = true },
    [179821] = { [26573] = true },
    [179878] = { [205180] = true },
    [181089] = { [1276452] = true, [1276623] = true },
    [181090] = { [1276467] = true, [1276610] = true },
    [182891] = { [1276452] = true, [1288945] = true },
    [182955] = { [1276467] = true, [1288950] = true },
    [188095] = { [20271] = true, [24275] = true, [403495] = true },
    [191830] = { [101643] = true },
    [191882] = { [101643] = true },
    [198708] = { [43265] = true },
    [198783] = { [1264289] = true, [1264345] = true },
}
-- END NATIVE PLAYER AURA IDENTITIES
