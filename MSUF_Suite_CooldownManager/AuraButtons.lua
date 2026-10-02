local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- What the aura layer draws inside Blizzard's aura buttons, and the stand-in
-- icons it draws on cells. Auras.lua builds the containers and calls in
-- here: a container record (rec) carries the look (rec.lk) and the bar's
-- choices; each button's regions and state live in a part record, never on
-- the button.
--  * Look: every visual value of a container's buttons and the signature
--    that changes exactly when a button needs restyling;
--  * Init (initializeFrame) and the batch: a group's ten pre-built buttons
--    are collected and only the one Blizzard shows is built (Adopt: every
--    region, styled, bound last; bound regions are sealed);
--  * Style and ApplyEntry restyle a button and apply its per-spell choices
--    (swipe, glows, stack text, countdown, text on top); Mutable says
--    whether sealed buttons accept that now;
--  * kit sensors hear a button show or hide (unknown kit sounds only);
--  * the glows and their combat gates are AuraGlows.lua's;
--  * placeholders: a dimmed icon for missing buffs (showMissing) and the
--    sample icon in the preview, on the cell under the slot button.
local K = C.Const
local SWIPE = K.SWIPE
local NORMAL_SWIPE, REVERSED_SWIPE, HIDDEN_SWIPE = SWIPE.NORMAL, SWIPE.REVERSED, SWIPE.HIDDEN
local Choice = K.Choice
local AuraButtons = {}
C.AuraButtons = AuraButtons

-- Regions inside Blizzard's aura buttons are created with the client's
-- CreateFrame: the container lays those buttons out and seals their bound
-- regions, so MSUF's pixel-layout policy (S.CreateFrame) must not round what
-- Blizzard positions. Placeholders sit on our own cells (S.CreateTexture).
local CreateFrame = CreateFrame
local IsCombatLocked = NS.IsCombatLocked
local floor, max, min = math.floor, math.max, math.min
local type, tonumber = type, tonumber
local tconcat = table.concat
local Public = S.Public
local EMPTY = C.EMPTY

local BAR_TEXTURE = K.BAR_TEXTURE
local TEXT_DEFAULT = {}
-- Init of a button whose group has no entry yet: the bar's choices.
local NO_ENTRY = {}
local TIMER = Enum.StatusBarTimerDirection
local IMMEDIATE = Enum.StatusBarInterpolation.Immediate
-- barFill 1 drains, 2 fills.
local BAR_OPTS = { { direction = TIMER.RemainingTime, interpolation = IMMEDIATE },
    { direction = TIMER.ElapsedTime, interpolation = IMMEDIATE } }
local GOLD = K.GLOW_GOLD
local BAR_LEVEL, ICON_LEVEL = K.AURA_LEVEL, K.AURA_ICON_LEVEL
local PANDEMIC = { 1, .3, .15 }
local STACK_COLOR = NS.CDM.SPELL_DEFAULTS.stackColor
-- Every field Look writes: the signature changes exactly when a button needs restyling.
local LOOK = { "w", "h", "px", "bw", "er", "eg", "eb", "l", "r", "t", "b", "font", "flags", "rendering", "shadow", "shadowOpacity",
    "shadowDistance", "cs", "ss", "sp", "cr", "cg", "cb", "sr", "sg", "sb", "swipe", "edge", "tip", "tex", "fr", "fg", "fb", "bgA", "icon", "side",
    "smax", "marks" }
local NO_MARKS = {}

local sig = {}
local textOpts = K.NewCache()  -- duration text options per countdown formatter
local countOpts = K.NewCache() -- stack text options per (N, color)
local Recall, Remember = K.Recall, K.Remember
local barOpts = {}   -- SetApplicationBar options (Blizzard copies them)
local sensed = {}    -- kit sensor frame -> its button record
-- Batch button -> its sensor, made inside initializeFrame: the client seals
-- an aura button once initializeFrame returns, and SetScript on it or on a
-- child is refused from then on ("blocked by secret aspects").
local premade = setmetatable({}, { __mode = "k" })

local Px = K.Px
local function Snap(value, px) return floor(value / px + .5) * px end
local ClassRGB = K.ClassRGB
-- Glows and edges (AuraGlows.lua loads first).
local Glows = C.AuraGlows
local Edges, NewGlow, NewStack, BindStack = Glows.Edges, Glows.NewGlow, Glows.NewStack, Glows.BindStack
local ApplyGlow, ApplyStack, ApplyCombatGate = Glows.ApplyGlow, Glows.ApplyStack, Glows.ApplyCombatGate

-- Duration text options per (threshold, warning color): a binding template
-- that Blizzard copies into each button, around the shared countdown
-- formatter (Const). The fallbacks must ride on the binding, and without a
-- formatter on it no text renders at all.
-- Every entry of a sync asks for the same few signatures, so the last answer
-- is kept: a repeat costs four compares.
local lastSeconds, lastR, lastG, lastB, lastOpts
local function TextOpts(seconds)
    local state = C.state
    local r, g, b = state.thR, state.thG, state.thB
    if lastOpts and seconds == lastSeconds and r == lastR and g == lastG and b == lastB then return lastOpts end
    local formatter = K.CountdownFormatter(seconds, r, g, b)
    local opts = textOpts.young[formatter] or Recall(textOpts, formatter)
    if opts then
        lastSeconds, lastR, lastG, lastB, lastOpts = seconds, r, g, b, opts
        return opts
    end
    local binding = C_DurationUtil.CreateDurationTextBinding()
    binding:SetFormatter(formatter)
    binding:SetZeroDurationText("")
    binding:SetExpiredText("")
    binding:SetUpdateInterval(.1)
    binding:SetEnabled(true)
    opts = Remember(textOpts, formatter, { binding = binding })
    lastSeconds, lastR, lastG, lastB, lastOpts = seconds, r, g, b, opts
    return opts
end

-- Stack text options per (stackColorAt, stackColor): one formatter per
-- signature, shared by every button. Nothing below two applications (like
-- Blizzard's default), plain from two, colored from N (N = 1 colors a
-- single application too). nil: the plain binding (off).
local function CountOpts(ov)
    local n = ov.stackColorAt
    if type(n) ~= "number" or n < 1 then return nil end
    n = floor(n)
    local hex = ov.stackColor or STACK_COLOR
    local rgb = type(hex) == "string" and #hex == 6 and tonumber(hex, 16)
    if not rgb then return nil end
    local key = n * 16777216 + rgb
    local opts = countOpts.young[key] or Recall(countOpts, key)
    if opts then return opts end
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    local points = { { threshold = 0, format = "" } }
    if n > 2 then points[2] = { threshold = 2, format = "%d" } end
    points[#points + 1] = { threshold = n, format = "|cff" .. hex .. "%d|r" }
    formatter:SetBreakpoints(points)
    return Remember(countOpts, key, { formatter = formatter })
end

------------------------------------------------------------------ look
-- Every visual value of a container's buttons in rec.lk; the returned
-- string changes exactly when a button needs restyling.
local function Look(rec, view)
    local state, lk, bar = C.state, rec.lk, rec.role == "bar"
    local px = Px()
    local w, h
    if bar then
        w, h = max(px, Snap(view.barWidth or 200, px)), max(px, Snap(view.barHeight or 18, px))
    else
        local size = view.size or 36
        w, h = max(px, Snap(size, px)), max(px, Snap(size * (view.height or 100) / 100, px))
    end
    local bw = floor(view.border or (bar and 1 or 0)) * px
    lk.w, lk.h, lk.px, lk.bw = w, h, px, bw
    local r, g, b
    if view.borderClass then r, g, b = ClassRGB() end
    if not r then r, g, b = view.borderR or 0, view.borderG or 0, view.borderB or 0 end
    lk.er, lk.eg, lk.eb = r, g, b
    -- Same crop as the cooldown icons (a bar's icon is square).
    local iw, ih = w - 2 * bw, h - 2 * bw
    if bar then iw = ih end
    lk.l, lk.r, lk.t, lk.b = K.Crop(view.zoom, iw, ih)
    lk.font, lk.flags = state.font, state.fontFlags
    lk.rendering, lk.shadow, lk.shadowOpacity, lk.shadowDistance =
        state.fontRendering, state.fontShadow, state.fontShadowOpacity, state.fontShadowDistance
    local font = K.FONT
    lk.cs = K.TextSize(view.cdSize, bar and font.barText or font.countdown, h)
    lk.ss = K.TextSize(view.stackSize, bar and font.barStacks or font.stacks, h)
    local pos = view.stackPos
    lk.sp = (pos and K.POINTS[pos]) and pos or 9
    lk.cr, lk.cg, lk.cb = state.cdR or 1, state.cdG or 1, state.cdB or 1
    lk.sr, lk.sg, lk.sb = state.stackR or 1, state.stackG or 1, state.stackB or 1
    lk.swipe = (view.swipeAlpha or K.SWIPE_ALPHA) / 100
    lk.edge = view.edge == true
    lk.tip = view.tooltips == true
    if bar then
        lk.tex = S.ResolveTexture(view.barTexture, BAR_TEXTURE)
        r, g, b = nil, nil, nil
        if view.barClass ~= false then r, g, b = ClassRGB() end
        local fill = K.BAR_RGB
        if not r then r, g, b = view.barR or fill[1], view.barG or fill[2], view.barB or fill[3] end
        lk.fr, lk.fg, lk.fb = r, g, b
        lk.bgA = (view.barBgAlpha or K.BAR_BG_ALPHA) / 100
        lk.icon = view.barIcon ~= false
        lk.side = view.barIconSide == 2 and 2 or 1
        -- Stack fill maximum and markers are looks, not region sets: a new
        -- value restyles the buttons in place (application bar rebound,
        -- pooled markers placed), never builds another container.
        lk.smax = max(1, min(99, floor(view.barStackMax or 10)))
        lk.marks = view.barStackEach ~= false and "each" or (view.barStackMarks or "")
    end
    for i = 1, #LOOK do
        local v = lk[LOOK[i]]
        if v == true then
            v = 1
        elseif not v then
            v = 0
        end
        sig[i] = v
    end
    return tconcat(sig, "\031", 1, #LOOK)
end

-- Unknown kit sounds of aura entries (AddAuraSound takes files only): a
-- sensor in the button hears it show (aura gained) and hide (aura lost).
-- The sound, mute, quiet window, pairing and throttle are the alert
-- layer's; the container record is the hush gate of its sensors.
local function Heard(sensor, which)
    local part = sensed[sensor]
    local rec = part and part.rec
    if not rec then return end
    local k = part.pos
    local entry = rec.on[k] and rec.entry[k]
    -- Entries without a sound on the kit bar cost these reads only.
    local ov = entry and entry.ov
    if not ov or ov == EMPTY or not (ov.sound or ov.lossSound) then return end
    C.Alerts.PlayAura(entry.key, which, rec)
end
local function Gained(sensor) Heard(sensor, "gain") end
local function Lost(sensor) Heard(sensor, "loss") end

-- Container switches show or hide buttons without an aura changing:
-- that container's sensors stay silent for a moment.
local function Hush(rec)
    if rec.kit then C.Alerts.Hush(rec) end
end
-- Tainted code may touch sealed aura buttons only out of combat, while
-- auras are not secret and each button says so plainly.
local function Quiet()
    if IsCombatLocked() then return false end
    local secret = C_Secrets.ShouldAurasBeSecret()
    return Public(secret) and not secret
end
local function Open(button)
    local ok = button:CanBeAccessedInContext()
    return Public(ok) and ok == true
end
local function Mutable(rec)
    if not Quiet() then return false end
    local parts = rec.parts
    for i = 1, #parts do
        if not Open(parts[i].button) or not C.StackColors.Open(parts[i]) then
            return false
        end
    end
    return true
end

local function Text(fs, size, r, g, b, lk)
    S.SetStyledFont(fs, lk.font, size, lk.flags, lk.rendering, lk.shadow, lk.shadowOpacity, lk.shadowDistance)
    fs:SetTextColor(r, g, b)
end

-- The stacks a stack-filled bar marks: every stack below the maximum, or
-- the listed ones below it (each once, rising). One list per container,
-- refilled only when the look's markers or maximum changed.
local function MarkValues(rec, lk)
    local values = rec.markValues
    if not values then
        values = {}
        rec.markValues = values
    end
    if rec.mvMarks == lk.marks and rec.mvMax == lk.smax then return values end
    rec.mvMarks, rec.mvMax = lk.marks, lk.smax
    for i = #values, 1, -1 do values[i] = nil end
    local top = lk.smax - 1
    if lk.marks == "each" then
        for n = 1, top do values[n] = n end
        return values
    end
    local listed = {}
    for token in lk.marks:gmatch("%d+") do
        local n = tonumber(token)
        if n > 0 and n <= top then listed[n] = true end
    end
    for n = 1, top do
        if listed[n] then values[#values + 1] = n end
    end
    return values
end

-- Markers come from a per-button pool (made while the button accepts
-- writes, never freed): a new maximum or marker list places them again.
-- Sample rows are our own frames and take the pixel-layout policy.
local function PlaceMarkers(rec, part, lk, bar)
    local values = rec.stackFill and MarkValues(rec, lk) or NO_MARKS
    part.markerValues = values
    local markers = part.markers
    if not markers then
        markers = {}
        part.markers = markers
    end
    local host, px, bw = part.markerHost or bar, lk.px, lk.bw
    local width = lk.w - (lk.icon and lk.h or bw) - bw
    for i = 1, #values do
        local marker = markers[i]
        if not marker then
            marker = part.sample and S.CreateTexture(host, nil, "OVERLAY") or host:CreateTexture(nil, "OVERLAY")
            marker:SetColorTexture(0, 0, 0, .7)
            markers[i] = marker
        end
        marker:ClearAllPoints()
        marker:SetPoint("TOPLEFT", bar, "TOPLEFT", Snap(width * values[i] / lk.smax, px), 0)
        marker:SetSize(px, lk.h - 2 * bw)
        marker:Show()
    end
    for i = #values + 1, #markers do markers[i]:Hide() end
end

-- Every region of one button from rec.lk; idempotent (init and restyle).
local function Style(rec, part)
    local lk, b = rec.lk, part.button
    local bw, px = lk.bw, lk.px
    if not rec.fixed then b:SetSize(lk.w, lk.h) end
    K.PlaceEdges(part.edges, b, bw, lk.er, lk.eg, lk.eb, 1)
    local icon = part.icon
    icon:ClearAllPoints()
    if rec.role == "bar" then
        local left = lk.side == 1
        local inner = lk.h - 2 * bw
        local point = left and "TOPLEFT" or "TOPRIGHT"
        icon:SetPoint(point, b, point, left and bw or -bw, -bw)
        icon:SetSize(inner, inner)
        icon:SetShown(lk.icon)
        local lead = lk.icon and lk.h or bw
        local bg, bar = part.bg, part.bar
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", b, "TOPLEFT", bw, -bw)
        bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -bw, bw)
        bg:SetTexture(lk.tex)
        bg:SetVertexColor(lk.fr * .25, lk.fg * .25, lk.fb * .25, lk.bgA)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", b, "TOPLEFT", left and lead or bw, -bw)
        bar:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", left and -bw or -lead, bw)
        bar:SetStatusBarTexture(lk.tex)
        bar:SetStatusBarColor(lk.fr, lk.fg, lk.fb, 1)
        if rec.stackFill or part.markers then PlaceMarkers(rec, part, lk, bar) end
        -- The fill's range is its application bar's maximum: a bound button
        -- is rebound in place when the maximum changes.
        if rec.stackFill and part.bound and part.appMax ~= lk.smax then
            part.appMax = lk.smax
            barOpts.maxApplications = lk.smax
            b:SetApplicationBar(bar, barOpts)
        end
        local dur, name = part.dur, part.name
        if dur then
            Text(dur, lk.cs, lk.cr, lk.cg, lk.cb, lk)
            dur:ClearAllPoints()
            dur:SetPoint("RIGHT", bar, "RIGHT", -4 * px, 0)
            dur:SetJustifyH("RIGHT")
        end
        if name then
            Text(name, lk.cs, lk.cr, lk.cg, lk.cb, lk)
            name:ClearAllPoints()
            -- Room for the time text without anchoring to a sealed string.
            name:SetPoint("LEFT", bar, "LEFT", 4 * px, 0)
            name:SetPoint("RIGHT", bar, "RIGHT", dur and -floor(lk.cs * 2.6 + .5) or -4 * px, 0)
            name:SetJustifyH("LEFT")
            name:SetWordWrap(false)
        end
    else
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", bw, -bw)
        icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -bw, bw)
        local cd = part.cd
        if rec.role == "over" then
            cd:SetSwipeColor(GOLD[1], GOLD[2], GOLD[3], .55)
            cd:SetDrawEdge(false)
        else
            cd:SetSwipeColor(0, 0, 0, lk.swipe)
            cd:SetDrawEdge(lk.edge)
        end
        local dur = part.dur
        if dur then
            Text(dur, lk.cs, lk.cr, lk.cg, lk.cb, lk)
            dur:ClearAllPoints()
            dur:SetPoint("CENTER", icon, "CENTER", 0, 0)
        end
    end
    icon:SetTexCoord(lk.l, lk.r, lk.t, lk.b)
    local count, pos = part.count, lk.sp
    local point, inset = K.POINTS[pos], px + bw
    Text(count, lk.ss, lk.sr, lk.sg, lk.sb, lk)
    count:ClearAllPoints()
    count:SetPoint(point, icon, point, K.POINT_X[pos] * inset, K.POINT_Y[pos] * inset)
    count:SetJustifyH(K.JUSTIFY[pos])
    if part.pan then K.PlaceEdges(part.panEdges, part.pan, max(2 * px, bw), PANDEMIC[1], PANDEMIC[2], PANDEMIC[3], 1) end
    b:SetMouseMotionEnabled(lk.tip)
end

-- Text on top: the two text frames trade levels (both stay above the glows).
local function Layer(part, top)
    local stacks, texts = part.stackFrame, part.timeFrame
    local a, b = stacks:GetFrameLevel(), texts:GetFrameLevel()
    if a > b then a, b = b, a end
    if top then
        stacks:SetFrameLevel(b)
        texts:SetFrameLevel(a)
    else
        stacks:SetFrameLevel(a)
        texts:SetFrameLevel(b)
    end
end

-- Per-spell choices on one button: swipe mode, glows, stack text (shown,
-- color), countdown (shown, warning threshold) and which is on top. With
-- dry set it only reports whether a write is needed. Unbound
-- (initializeFrame) it prepares what the binding takes. Hidden text is
-- never bound: a bound one is cleared, then hidden by hand.
local function ApplyEntry(rec, part, entry, dry)
    if C.StackColors.Apply(rec, part, entry, dry) then return true end
    local ov = entry.ov or EMPTY
    local cd = part.cd
    if cd and rec.role == "icon" then
        local mode = ov.swipe or NORMAL_SWIPE
        if part.swipe ~= mode then
            if dry then return true end
            part.swipe = mode
            -- Normal aura swipes run reversed; REVERSED flips them.
            cd:SetReverse(mode ~= REVERSED_SWIPE)
            cd:SetDrawSwipe(mode ~= HIDDEN_SWIPE)
        end
    end
    if part.glow and ApplyGlow(rec, part, ov, dry) then return true end
    if part.glow and ApplyCombatGate(part.glow, part.gOn, dry) then return true end
    if part.stack and ApplyStack(rec, part, ov, dry) then return true end
    if part.stack and ApplyCombatGate(part.stack.glow, part.stack.on, dry) then return true end
    local b = part.button
    local stacks = Choice(ov.stackText, rec.stackBar)
    local count = stacks and CountOpts(ov) or nil
    if part.countOn ~= stacks or part.countOpts ~= count then
        if dry then return true end
        local was = part.countOn
        part.countOn, part.countOpts = stacks, count
        if not stacks then
            if part.bound and was then b:ClearApplicationCount() end
            part.count:Hide()
        else
            if was == false then part.count:Show() end
            if part.bound then b:SetApplicationCount(part.count, count) end
        end
    end
    local dur = part.dur
    if dur then
        local shown = Choice(ov.timeText, rec.timeBar)
        if part.durOn ~= shown then
            if dry then return true end
            local was = part.durOn
            part.durOn = shown
            if not shown then
                if part.bound and was then b:ClearDurationText() end
                part.textOpts = nil
                dur:Hide()
            elseif was == false then
                dur:Show()
            end
        end
        if shown and part.bound then
            local opts = TextOpts(ov.threshold or C.state.threshold)
            if part.textOpts ~= opts then
                if dry then return true end
                part.textOpts = opts
                b:SetDurationText(dur, opts)
            end
        end
    end
    local top = Choice(ov.textTop, rec.topBar)
    if part.top ~= top then
        if dry then return true end
        part.top = top
        Layer(part, top)
    end
    return false
end

-- Every region of a new button, as its descendants, in our own part record.
local function NewPart(rec, button, k)
    local part = { button = button, pos = k, rec = rec }
    part.edges = Edges(button)
    part.icon = button:CreateTexture(nil, "ARTWORK")
    -- Every layer at its own level above the button. Bars (K.AURA_LEVEL):
    -- fill, stack colour (StackColors), markers, glows, countdown and name,
    -- stacks. Icons and overlays (K.AURA_ICON_LEVEL): swipe, glows,
    -- countdown, stacks.
    local base = button:GetFrameLevel()
    local LEVEL = rec.role == "bar" and BAR_LEVEL or ICON_LEVEL
    local lower
    if rec.role == "bar" then
        part.bg = button:CreateTexture(nil, "BACKGROUND")
        lower = CreateFrame("StatusBar", nil, button)
        lower:SetMinMaxValues(0, 1)
        lower:SetValue(0)
        part.bar = lower
        -- Stack markers sit above the threshold colour (Style places them
        -- from a pool; the look says which).
        if rec.stackFill and rec.color then
            local markerHost = CreateFrame("Frame", nil, button)
            markerHost:SetFrameLevel(base + LEVEL.marks)
            part.markerHost = markerHost
        end
    else
        lower = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        lower:SetAllPoints(part.icon)
        lower:SetDrawBling(false)
        lower:SetHideCountdownNumbers(true)
        lower:SetReverse(true)
        part.cd = lower
    end
    lower:SetFrameLevel(base + LEVEL.fill)
    -- Glows over the icon, fill, colour and markers; text above the glows.
    local level = base + LEVEL.glow
    if rec.pandemic then
        local pan = CreateFrame("Frame", nil, button)
        pan:SetAllPoints(button)
        pan:SetFrameLevel(level)
        pan:Hide()
        part.pan, part.panEdges = pan, Edges(pan)
    end
    if rec.glow then part.glow = NewGlow(button, button, level) end
    if rec.stack then part.stack = NewStack(button, level) end
    -- Stacks and countdown (with the name) on two frames above the glows,
    -- stacks on top until the entry's Text on top says otherwise.
    local stacks = CreateFrame("Frame", nil, button)
    stacks:SetAllPoints(button)
    stacks:SetFrameLevel(base + LEVEL.stacks)
    local texts = CreateFrame("Frame", nil, button)
    texts:SetAllPoints(button)
    texts:SetFrameLevel(base + LEVEL.text)
    part.stackFrame, part.timeFrame, part.top = stacks, texts, true
    part.count = stacks:CreateFontString(nil, "OVERLAY")
    if rec.text then part.dur = texts:CreateFontString(nil, "OVERLAY") end
    if rec.name then part.name = texts:CreateFontString(nil, "OVERLAY") end
    if rec.kit then
        -- A new button hides once it is set up: not an aura leaving.
        Hush(rec)
        -- A batch button built after its batch is sealed: it reuses the
        -- sensor initializeFrame gave it; no script is set any more.
        local sensor = premade[button]
        if not sensor then
            sensor = CreateFrame("Frame", nil, button)
            sensor:SetAllPoints(button)
            sensor:SetScript("OnShow", Gained)
            sensor:SetScript("OnHide", Lost)
        end
        sensed[sensor] = part
    end
    return part
end

-- Hands the styled regions to the button; bound regions are sealed.
local function Bind(rec, part, k)
    local button = part.button
    button:SetIcon(part.icon)
    if part.cd then button:SetDurationCooldown(part.cd) end
    if part.bar then
        if rec.stackFill then
            part.appMax = rec.lk.smax
            barOpts.maxApplications = part.appMax
            button:SetApplicationBar(part.bar, barOpts)
        else
            button:SetDurationBar(part.bar, BAR_OPTS[rec.fill])
        end
    end
    if part.dur and part.durOn then
        local opts = rec.topts[k] or TEXT_DEFAULT
        button:SetDurationText(part.dur, opts)
        part.textOpts = opts
    end
    if part.name then button:SetSpellName(part.name) end
    -- Without a formatter Blizzard shows stacks above 1 only; the per-spell
    -- stack color passes a shared formatter (CountOpts).
    if part.countOn then button:SetApplicationCount(part.count, part.countOpts) end
    if part.stack then BindStack(button, part.stack) end
    -- 12.1.5 and Forever return nothing here; the result is never used.
    if part.pan then button:AddPandemicRegion(part.pan) end
    part.bound = true
end

-- Builds and styles every region of a button as its descendant, binds last
-- (bound regions are sealed) and keeps our state in our own table, never on
-- the button. Its part joins rec.parts, the buttons restyles reach.
local function Adopt(rec, button, k)
    local part = NewPart(rec, button, k)
    button:SetMouseClickEnabled(false)
    button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT")
    -- Slots are outside the flow layout: they follow their cell or icon.
    if rec.fixed then
        button:ClearAllPoints()
        button:SetAllPoints(rec.anchors[k])
    end
    Style(rec, part)
    ApplyEntry(rec, part, rec.entry[k] or NO_ENTRY, false)
    Bind(rec, part, k)
    local parts = rec.parts
    parts[#parts + 1] = part
end

------------------------------------------------------------------ batches
-- AddAuraGroup pre-builds a batch of buttons (FrameCreationBatchSize, ten,
-- Blizzard_CustomAuraContainer.lua) and runs initializeFrame for each
-- before it returns. The group's frame provider hands out the newest free
-- button (AcquireFrame takes the last of its available list; a released
-- one goes back on top), so a one-frame entry group only ever shows the
-- last button of its batch. While auras are plain (Quiet) the batch is
-- collected and only that button is built; the others stay bare, each
-- with one sensor. Should Blizzard show one of them after all, it is built
-- a frame later, or once auras are plain again (A.FlushPending). While
-- auras are secret the buttons seal on creation, so each is built in
-- initializeFrame, like a button made outside a batch, and so is every
-- batch of a container made because sealed buttons refused a restyle
-- (rec.eager). A shown button that refuses right after its batch waits in
-- rec.waiting; Finish reports the container unfinished meanwhile.
local batch = {}
local dormant = {} -- sensor of a bare button -> { rec, button, pos, sensor }
local woken = {}   -- bare buttons Blizzard showed, waiting to be built
local wakeArmed = false

local function AdoptWoken()
    wakeArmed = false
    for i = #woken, 1, -1 do
        local shell = woken[i]
        if not (Quiet() and Open(shell.button)) then
            -- Pending, so the end of combat or of a restriction comes back.
            C.Auras.pending[shell.rec.slot] = true
            return
        end
        woken[i] = nil
        Adopt(shell.rec, shell.button, shell.pos)
    end
end
AuraButtons.AdoptWoken = AdoptWoken

local function Woke(sensor)
    local shell = dormant[sensor]
    if not shell then return end
    dormant[sensor] = nil
    woken[#woken + 1] = shell
    if wakeArmed then return end
    wakeArmed = true
    C_Timer.After(0, AdoptWoken)
end

-- One sensor per batch button, made inside initializeFrame (the only time
-- the client accepts its scripts): a bare button wakes on show; once built,
-- a kit button's sensor hears gains and losses (sensed).
local function SensorShown(sensor)
    if dormant[sensor] then return Woke(sensor) end
    if sensed[sensor] then Gained(sensor) end
end
local function SensorHidden(sensor)
    if sensed[sensor] then Lost(sensor) end
end
local function Dormant(rec, button, k)
    local sensor = CreateFrame("Frame", nil, button)
    sensor:SetAllPoints(button)
    dormant[sensor] = { rec = rec, button = button, pos = k, sensor = sensor }
    premade[button] = sensor
    sensor:SetScript("OnShow", SensorShown)
    if rec.kit then sensor:SetScript("OnHide", SensorHidden) end
end

-- Around AddAuraGroup: true when the batch is collected (auras plain).
function AuraButtons.BeginBatch(rec)
    for i = #batch, 1, -1 do batch[i] = nil end
    if rec.eager or not Quiet() then return false end
    rec.batch = batch
    return true
end
function AuraButtons.EndBatch(rec, k)
    rec.batch = nil
    local n = #batch
    local shown = batch[n]
    -- The shown button is built now; its sensor no longer wakes it.
    local sensor = shown and premade[shown]
    if sensor then dormant[sensor] = nil end
    if shown and Open(shown) then
        Adopt(rec, shown, k)
    elseif shown then
        local waiting = rec.waiting or {}
        rec.waiting = waiting
        waiting[#waiting + 1] = { rec = rec, button = shown, pos = k }
    end
    for i = n, 1, -1 do batch[i] = nil end
end
-- Builds the shown buttons that refused right after their batch; false
-- while one still refuses (the container then counts as refusing a
-- restyle, Auras.Run).
function AuraButtons.Finish(rec)
    local waiting = rec.waiting
    if not waiting then return true end
    for i = #waiting, 1, -1 do
        local shell = waiting[i]
        if not (Quiet() and Open(shell.button)) then return false end
        waiting[i] = nil
        Adopt(rec, shell.button, shell.pos)
    end
    rec.waiting = nil
    return true
end

-- initializeFrame, from Blizzard's frame provider: inside a collected
-- batch the button waits for EndBatch; otherwise it is built at once (a
-- slot's one button, a batch made while auras are secret).
local function Init(rec, button, k)
    local list = rec.batch
    if list then
        list[#list + 1] = button
        Dormant(rec, button, k)
        return
    end
    Adopt(rec, button, k)
end

AuraButtons.TextOpts, AuraButtons.Look, AuraButtons.Hush, AuraButtons.Quiet, AuraButtons.Mutable = TextOpts, Look, Hush, Quiet, Mutable
AuraButtons.Style, AuraButtons.ApplyEntry, AuraButtons.Init = Style, ApplyEntry, Init
