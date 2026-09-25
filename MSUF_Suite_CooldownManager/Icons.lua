local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Cooldown icon frames: one pool per bar keyed by entry key. Styling runs
-- only when the bar's style generation moved; per-entry parts (swipe mode,
-- threshold formatter, bling, texture) are memoized on the icon, so a
-- repeated sync with unchanged inputs writes nothing. Icons are plain
-- frames under our own bar frames, never secure, so every setter used by
-- the time and effect layers stays legal in combat.
local K = C.Const
local I = {}
C.Icons = I
local floor, max = math.floor, math.max
local EMPTY = C.EMPTY
local pools = {}
local owner = {}
local formatters = {}
local syncGen = 0

------------------------------------------------------------------ scripts
-- Prebuilt handlers shared by every icon; the icon is looked up, never captured.
-- Time needs to know which swipe ran out (main swipe or recharge edge).
local function CooldownDone(cooldown)
    local icon = owner[cooldown]
    local time = C.Time
    if icon and time and time.Done then time.Done(icon, cooldown) end
end

local function OnEnter(icon)
    local entry = icon.entry
    if not entry then return end
    local view, bar = C.views[entry.slot], C.bars[entry.slot]
    if not view or not view.tooltips or (bar and bar.hidden) then return end
    local tip = _G.GameTooltip
    if not tip then return end
    if _G.GameTooltip_SetDefaultAnchor then
        _G.GameTooltip_SetDefaultAnchor(tip, icon)
    else
        tip:SetOwner(icon, "ANCHOR_RIGHT")
    end
    local slot = entry.equipSlot or (entry.src == "e" and entry.id)
    if slot then
        tip:SetInventoryItem("player", slot)
    elseif entry.src == "i" then
        tip:SetItemByID(entry.itemID or entry.id)
    else
        local spell = entry.tooltip or entry.spell or entry.base
        if not spell then
            tip:Hide()
            return
        end
        tip:SetSpellByID(spell)
    end
    tip:Show()
end

local function OnLeave(icon)
    local tip = _G.GameTooltip
    if tip and tip:IsOwned(icon) then tip:Hide() end
end

-- Match Blizzard's CooldownViewer ping target order: equipped/bag items,
-- consumable categories, then spells. IDs in the plan are plain values from
-- Catalog/Resolve; an empty equipment slot has no item to ping.
local function PingTarget(entry)
    if not entry then return end
    local item = entry.itemID
    if item then return "itemID", item end
    local category = entry.spellCategory
    if category then return "spellCategoryID", category end
    local spell = entry.spell or entry.base
    if spell then return "spellID", spell end
end

local function IsPingable(icon)
    return icon.entry ~= nil and icon.ping == true and PingTarget(icon.entry) ~= nil
end

local function NoRadialWheel() return false end

local function PingInfo(icon)
    local key, id = PingTarget(icon.entry)
    if key then return { [key] = id } end
    return {}
end

------------------------------------------------------------------ creation
local function NewCooldown(icon)
    local cooldown = S.CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cooldown:ClearAllPoints()
    cooldown:SetAllPoints(icon.tex)
    cooldown:SetScript("OnCooldownDone", CooldownDone)
    owner[cooldown] = icon
    return cooldown
end

local function CreateIcon(parent, pingable)
    local icon = S.CreateFrame("Frame", nil, parent, pingable and "PingReceiverAttributeTemplate" or nil)
    if pingable then
        icon.GetIsPingable = IsPingable
        icon.GetAllowRadialWheel = NoRadialWheel
        icon.GetTargetInfo = PingInfo
    end
    icon.tex = S.CreateTexture(icon, nil, "ARTWORK")
    icon.cd = NewCooldown(icon)
    icon.edges = K.NewEdges(icon, 7)
    -- Stacks and the keybind sit on their own frame above the swipe and the
    -- glows; the countdown is the swipe's own text (see Texts).
    local over = S.CreateFrame("Frame", nil, icon)
    over:SetAllPoints(icon)
    icon.over = over
    icon.count = S.CreateFontString(over, nil, "OVERLAY")
    icon:SetScript("OnEnter", OnEnter)
    icon:SetScript("OnLeave", OnLeave)
    icon:EnableMouse(false)
    icon.mouse = false
    return icon
end

-- Recharge edge (charge spells): swipe off, edge on, no numbers.
function I.ChargeCooldown(icon)
    local cooldown = icon.chargeCd
    if cooldown then return cooldown end
    cooldown = NewCooldown(icon)
    cooldown:SetDrawSwipe(false)
    cooldown:SetDrawEdge(true)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetFrameLevel(icon:GetFrameLevel() + K.LEVEL.charge)
    icon.chargeCd = cooldown
    return cooldown
end

------------------------------------------------------------------ styling
local function Font(fontString, size, r, g, b)
    local state = C.state
    S.SetStyledFont(fontString, state.font, size, state.fontFlags, state.fontRendering,
        state.fontShadow, state.fontShadowOpacity, state.fontShadowDistance)
    fontString:SetTextColor(r or 1, g or 1, b or 1)
end

local function PlaceText(fontString, icon, pos, inset)
    if not K.POINTS[pos] then pos = 9 end
    local point = K.POINTS[pos]
    fontString:ClearAllPoints()
    fontString:SetPoint(point, icon, point, K.POINT_X[pos] * inset, K.POINT_Y[pos] * inset)
    fontString:SetJustifyH(K.JUSTIFY[pos])
end

local function StyleKey(icon, view)
    local key = icon.keyText
    if not key then return end
    local state = C.state
    local size = view.keybindSize or 0
    if size <= 0 then size = max(8, floor((icon.h or 36) * .26)) end
    Font(key, size, state.keyR, state.keyG, state.keyB)
    PlaceText(key, icon, view.keybindPos or 3, K.Pixels(1) + (icon.border or 0))
    key:SetShown(view.keybind == true)
end

-- Countdown, charge/stack text and which of the two is on top, per entry
-- (per-spell choices over the bar's switches; the preview's sample icons
-- carry no choices). Memoized: a repeated pass writes nothing. A hidden
-- count is cleared here and never written while hidden (icon.stackOn,
-- read by Time). Countdown on top lifts the swipe, which draws the
-- countdown, above the text frame.
local function Texts(icon, view, ov)
    local time = K.Choice(ov.timeText, K.BarTime(view))
    if icon.lastTime ~= time then
        icon.lastTime = time
        icon.cd:SetHideCountdownNumbers(not time)
    end
    local stack = K.Choice(ov.stackText, K.BarStacks(view, true))
    icon.stackOn = stack
    if not stack and icon.countOff ~= true then
        icon.countOff, icon.lastCount = true, nil
        icon.count:SetText("")
    end
    local top = K.Choice(ov.textTop, K.BarStacksTop(view))
    if icon.lastTop ~= top then
        icon.lastTop = top
        icon.cd:SetFrameLevel(icon:GetFrameLevel() + (top and K.LEVEL.cd or K.LEVEL.top))
    end
end

-- Full style pass; callers gate it on view.styleGen (the preview calls it directly).
function I.StyleIcon(icon, view)
    local state = C.state
    local w, h = K.IconSize(view)
    icon.w, icon.h = w, h
    icon:SetSize(w, h)
    local level = icon:GetFrameLevel()
    if icon.chargeCd then icon.chargeCd:SetFrameLevel(level + K.LEVEL.charge) end
    if icon.glow then icon.glow:SetFrameLevel(level + K.LEVEL.glow) end
    if icon.ants then icon.ants:SetFrameLevel(level + K.LEVEL.assist) end
    icon.over:SetFrameLevel(level + K.LEVEL.text)
    local border = K.Pixels(view.border or 0)
    icon.border = border
    local r, g, b = view.borderR or 0, view.borderG or 0, view.borderB or 0
    if view.borderClass then
        local cr, cg, cb = K.ClassRGB()
        if cr then r, g, b = cr, cg, cb end
    end
    K.PlaceEdges(icon.edges, icon, border, r, g, b, 1)
    local tex = icon.tex
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", icon, "TOPLEFT", border, -border)
    tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -border, border)
    tex:SetTexCoord(K.Crop(view.zoom, w - 2 * border, h - 2 * border))
    local cooldown = icon.cd
    cooldown:SetSwipeColor(0, 0, 0, (view.swipeAlpha or 70) / 100)
    cooldown:SetDrawEdge(view.edge == true)
    local entry = icon.entry
    Texts(icon, view, entry and entry.ov or EMPTY)
    local size = view.cdSize or 0
    if size <= 0 then size = max(10, floor(h * .38)) end
    local text = cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
    if text then Font(text, size, state.cdR, state.cdG, state.cdB) end
    local stack = view.stackSize or 0
    if stack <= 0 then stack = max(9, floor(h * .3)) end
    Font(icon.count, stack, state.stackR, state.stackG, state.stackB)
    PlaceText(icon.count, icon, view.stackPos or 9, K.Pixels(1) + border)
    StyleKey(icon, view)
    icon.styleGen, icon.styleView = view.styleGen, view
    local fx = C.Effects
    if fx and fx.Refit and (icon.glow or icon.ants) then fx.Refit(icon) end
end

------------------------------------------------------------------ threshold formatter
local function Rounding(name, fallback)
    local enum = _G.Enum and _G.Enum.NumericRuleFormatRounding
    return enum and enum[name] or fallback
end

-- One formatter per (seconds, color); nil when off or unsupported.
function I.Formatter(seconds, r, g, b)
    if type(seconds) ~= "number" or seconds <= 0 then return nil end
    seconds = floor(seconds + .5)
    local R, G, B = floor((r or 1) * 255 + .5), floor((g or 1) * 255 + .5), floor((b or 1) * 255 + .5)
    local key = seconds * 16777216 + R * 65536 + G * 256 + B
    local formatter = formatters[key]
    if formatter ~= nil then return formatter or nil end
    local util = _G.C_StringUtil
    if type(util) ~= "table" or type(util.CreateNumericRuleFormatter) ~= "function" then
        formatters[key] = false
        return nil
    end
    formatter = util.CreateNumericRuleFormatter()
    local up, down = Rounding("Up", 1), Rounding("Down", 2)
    local points = {
        { threshold = 0, format = ("|cff%02x%02x%02x%%.0f|r"):format(R, G, B), rounding = up },
        { threshold = seconds, format = "%.0f", rounding = up },
        { threshold = 60, format = "%d:%02d", rounding = down, components = { { div = 60, rounding = down }, { mod = 60, rounding = down } } },
        { threshold = 3600, format = "%dh", rounding = down, components = { { div = 3600, rounding = down } } },
    }
    if formatter.SetBreakpoints then
        formatter:SetBreakpoints(points)
    else
        for i = 1, #points do
            formatter:AddBreakpoint(points[i])
        end
    end
    formatters[key] = formatter
    return formatter
end

------------------------------------------------------------------ per-entry parts
function I.SetTexture(icon, texture)
    if icon.lastTex == texture then return end
    icon.lastTex = texture
    icon.tex:SetTexture(texture)
end

function I.Texture(entry)
    local icon = entry.icon
    if not icon then return end
    local ov = entry.ov or EMPTY
    I.SetTexture(icon, ov.icon or entry.texture or K.QUESTION_ICON)
end

-- Swipe mode, bling, threshold formatter and the texts depend on the
-- entry's spell choices; memoized per (entry, choices, generations).
function I.Apply(entry)
    local icon = entry.icon
    local view = icon and C.views[entry.slot]
    if not view then return end
    local ov = entry.ov or EMPTY
    if icon.esEntry == entry and icon.esOv == ov and icon.esStyle == view.styleGen and icon.esBehavior == view.behaviorGen then return end
    icon.esEntry, icon.esOv, icon.esStyle, icon.esBehavior = entry, ov, view.styleGen, view.behaviorGen
    Texts(icon, view, ov)
    local cooldown, state = icon.cd, C.state
    local swipe = ov.swipe or 1
    if icon.lastSwipe ~= swipe then
        icon.lastSwipe = swipe
        cooldown:SetReverse(swipe == 2)
        cooldown:SetDrawSwipe(swipe ~= 3)
    end
    local bling = view.bling == true
    if icon.lastBling ~= bling then
        icon.lastBling = bling
        cooldown:SetDrawBling(bling)
    end
    local seconds = ov.threshold
    if seconds == nil then seconds = state.threshold or 0 end
    local formatter = seconds > 0 and I.Formatter(seconds, state.thR, state.thG, state.thB) or nil
    if icon.lastFmt ~= formatter then
        icon.lastFmt = formatter
        if cooldown.SetCountdownFormatter then cooldown:SetCountdownFormatter(formatter) end
    end
end

local function ApplyKey(icon, text)
    text = text or ""
    if icon.lastKey == text then return end
    icon.lastKey = text
    local key = icon.keyText
    if not key then
        if text == "" then return end
        key = S.CreateFontString(icon.over, nil, "OVERLAY")
        key:SetWordWrap(false)
        icon.keyText = key
        -- A FontString needs a font before its first SetText.
        local entry = icon.entry
        StyleKey(icon, entry and C.views[entry.slot] or icon.styleView or EMPTY)
    end
    key:SetText(text)
end

function I.SetKeybind(entry, text)
    entry.keyText = text
    local icon = entry.icon
    if icon then ApplyKey(icon, text) end
end

-- Blizzard's ping hit test uses ping-receiver independently of mouse clicks.
-- Keep normal clicks passing through while tooltips use mouse motion only.
local function SetMouse(icon, on)
    if icon.mouse == on then return end
    icon.mouse = on
    if icon.EnableMouseMotion then
        icon:EnableMouseMotion(on)
    else
        icon:EnableMouse(on)
    end
end
local function SetPing(icon, on)
    on = on == true and PingTarget(icon.entry) ~= nil
    if icon.ping == on then return end
    icon.ping = on
    icon:SetAttribute("ping-receiver", on)
end
-- A bar hidden by its visibility rule is only transparent: its icons must
-- not keep catching the cursor over the frames and the world below.
local function MouseWanted(view, bar)
    return view.tooltips == true and not (bar and bar.hidden)
end

------------------------------------------------------------------ pools
local function Pool(slotKey)
    local pool = pools[slotKey]
    if not pool then
        pool = { byKey = {}, free = {} }
        pools[slotKey] = pool
    end
    return pool
end

local function Acquire(pool, parent)
    local free = pool.free
    local icon = free[#free]
    if icon then
        free[#free] = nil
    else
        icon = CreateIcon(parent, true)
    end
    icon:Show()
    return icon
end

-- Returns an icon to its bar's pool. Points stay with the layout layer.
local function Recycle(pool, icon)
    local entry = icon.entry
    -- Its aura overlay goes off with it at once (combat too), so a rebound
    -- icon never shows the old aura; the layout memo goes as well, so an
    -- icon rebound within the same flush is placed and reported again.
    local auras, layout = C.Auras, C.Layout
    if auras and auras.OverlayShown then auras.OverlayShown(entry, false, icon) end
    if layout and layout.Forget then layout.Forget(icon) end
    local fx = C.Effects
    if fx and fx.ResetIcon then fx.ResetIcon(icon) end
    if entry and entry.icon == icon then
        entry.icon = nil
        if fx and fx.Detach then fx.Detach(entry) end
    end
    icon.entry, icon.sim = nil, nil
    -- Time memos (item cooldown, real-swipe flag) belong to the old entry.
    icon.itemStart, icon.itemLock, icon.cdReal = nil, nil, nil
    if icon.cdSet ~= false then
        icon.cdSet = false
        icon.cd:Clear()
    end
    if icon.chargeCd and icon.chargeSet ~= false then
        icon.chargeSet = false
        icon.chargeCd:Clear()
    end
    if icon.countOff ~= true then
        icon.countOff = true
        icon.count:SetText("")
    end
    ApplyKey(icon, nil)
    SetMouse(icon, false)
    SetPing(icon, false)
    icon:Hide()
    pool.free[#pool.free + 1] = icon
end

local function Bind(icon, entry)
    icon.entry = entry
    entry.icon = icon
    ApplyKey(icon, entry.keyText)
end

-- Ensures one icon per entry of a cooldown plan, releases icons of entries
-- that left, restyles on generation change. Newly bound icons get their
-- live state at once so a sync never shows a stale icon.
function I.Sync(slotKey)
    local plan, view = C.plans[slotKey], C.views[slotKey]
    if not plan or plan.kind ~= 1 or not view then
        I.Release(slotKey)
        return
    end
    local bar = C.bars[slotKey]
    if not (bar and bar.frame) and C.Layout and C.Layout.EnsureBar then bar = C.Layout.EnsureBar(slotKey) end
    if not (bar and bar.frame) then return end
    local pool = Pool(slotKey)
    syncGen = syncGen + 1
    local byKey, entries = pool.byKey, plan.entries
    local time, fx = C.Time, C.Effects
    local mouse = MouseWanted(view, bar)
    local ping = not bar.hidden
    local recount = false
    for i = 1, #entries do
        local entry = entries[i]
        local icon = byKey[entry.key]
        if not icon then
            icon = Acquire(pool, bar.frame)
            byKey[entry.key] = icon
        end
        icon.mark = syncGen
        local fresh = icon.entry ~= entry or entry.icon ~= icon
        if fresh then Bind(icon, entry) end
        if entry.charges and not icon.chargeCd then I.ChargeCooldown(icon) end
        if icon.styleGen ~= view.styleGen or icon.styleView ~= view then I.StyleIcon(icon, view) end
        I.Texture(entry)
        I.Apply(entry)
        SetMouse(icon, mouse)
        SetPing(icon, ping)
        if fresh then
            -- Bag counts were not followed while nothing showed one: read
            -- them again, once per pass.
            if not recount and time and time.BagsChanged and (entry.src == "i" or (entry.spellCategory or 0) ~= 0) then
                recount = true
                time.BagsChanged()
            end
            if time and time.Refresh then time.Refresh(entry, "full") end
            if fx and fx.Update then fx.Update(entry) end
        end
    end
    for key, icon in pairs(byKey) do
        if icon.mark ~= syncGen then
            byKey[key] = nil
            Recycle(pool, icon)
        end
    end
end

-- Restyles a bar's icons after a style or tooltip change (memoized).
function I.Style(slotKey)
    local pool, view = pools[slotKey], C.views[slotKey]
    if not pool or not view then return end
    local mouse = MouseWanted(view, C.bars[slotKey])
    local bar = C.bars[slotKey]
    local ping = not (bar and bar.hidden)
    for _, icon in pairs(pool.byKey) do
        if icon.styleGen ~= view.styleGen or icon.styleView ~= view then I.StyleIcon(icon, view) end
        if icon.entry then I.Apply(icon.entry) end
        SetMouse(icon, mouse)
        SetPing(icon, ping)
    end
end

-- Visibility: a transparent bar must give up tooltips and ping targets.
-- Plain icon frames remain safe to update in combat; unchanged state writes
-- nothing.
function I.SetBarMouse(slotKey, on)
    local pool, view = pools[slotKey], C.views[slotKey]
    if not pool then return end
    local visible = on == true and view ~= nil
    for _, icon in pairs(pool.byKey) do
        SetMouse(icon, visible and view.tooltips == true)
        SetPing(icon, visible)
    end
end

function I.Release(slotKey)
    local pool = pools[slotKey]
    if not pool then return end
    for key, icon in pairs(pool.byKey) do
        pool.byKey[key] = nil
        Recycle(pool, icon)
    end
end

function I.ReleaseAll()
    for slotKey in pairs(pools) do I.Release(slotKey) end
    -- Bag events stop with the module: counts are read again next time.
    local time = C.Time
    if time and time.BagsChanged then time.BagsChanged() end
end

-- Test and diagnostics hook: live icons of a bar.
function I.Count(slotKey)
    local pool, count = pools[slotKey], 0
    if pool then
        for _ in pairs(pool.byKey) do
            count = count + 1
        end
    end
    return count
end

------------------------------------------------------------------ options preview
-- Standalone icons live outside the pools; the preview styles and fills them.
function I.CreateStandalone(parent) return CreateIcon(parent) end
