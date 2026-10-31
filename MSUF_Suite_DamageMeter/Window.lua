local _, P = ...
local NS, S = P.NS, P.Suite
-- Meter windows: plain (non-secure) UIParent children, so showing, hiding and
-- painting stay legal in combat. Geometry is written to settings out of
-- combat only. Positions are BOTTOMRIGHT offsets against UIParent's
-- BOTTOMRIGHT, the same format MSUF Edit Mode writes.
local D = P.DamageMeter
local M = D.M
local Public, Finite = S.Public, S.Finite
-- The client's secret test (Platform.lua) for the list paint.
local IsSecret = NS.IsSecret
local floor, max, min, format = math.floor, math.max, math.min, string.format
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
local ORDER = { "settings", "reset", "session", "type", "target" }
local EDGE = { TOP = { "TOPLEFT", "TOPRIGHT" }, BOTTOM = { "BOTTOMLEFT", "BOTTOMRIGHT" } }

local function HeaderButton(win, kind)
    local button = S.CreateFrame("Button", nil, win.header)
    button.win, button.kind = win, kind
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", D.HeaderButtonClick)
    button:SetScript("OnEnter", D.HeaderButtonEnter)
    button:SetScript("OnLeave", D.HeaderButtonLeave)
    local icon = S.CreateTexture(button, nil, "ARTWORK")
    button.icon = icon
    if kind == "settings" and D.Atlas(icon, "common-dropdown-a-button-settings-shadowless") then
        button.iconScale = 1
        icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    elseif kind == "reset" and D.Atlas(icon, "common-icon-undo") then
        button.iconScale = .8
        icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    elseif kind == "type" then
        -- Three bars of falling length: a small meter glyph from plain textures.
        icon:Hide()
        button.bars = {}
        for i = 1, 3 do button.bars[i] = S.CreateTexture(button, nil, "ARTWORK") end
    else
        icon:Hide()
        button.label = S.CreateFontString(button, nil, "OVERLAY")
        button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
        D.FontStyle(button.label, 11)
        if kind == "settings" then button.label:SetText("*")
        elseif kind == "reset" then button.label:SetText("R")
        elseif kind == "target" then button.label:SetText("T") end
    end
    return button
end

function D.NewWindow(parent, index)
    local win = { index = index, rows = {}, maxRow = 0, offset = 0, count = 0, capacity = 0, bd = { offset = 0 }, dirty = true, buttons = {}, hover = false }
    local frame = S.CreateFrame("Frame", nil, parent)
    frame.win, win.frame = win, frame
    frame:Hide()
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetDontSavePosition(true)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", D.HoverEnter)
    frame:SetScript("OnLeave", D.HoverLeave)
    frame:SetScript("OnSizeChanged", D.WindowSized)
    win.bg = S.CreateTexture(frame, nil, "BACKGROUND")
    local header = S.CreateFrame("Button", nil, frame)
    header.win, win.header = win, header
    header:SetFrameLevel(frame:GetFrameLevel() + 3)
    header:RegisterForDrag("LeftButton")
    header:RegisterForClicks("RightButtonUp")
    for script, handler in pairs(D.headerScripts) do header:SetScript(script, handler) end
    win.headerBg = S.CreateTexture(header, nil, "BACKGROUND")
    win.headerBg:SetAllPoints(header)
    win.title = S.CreateFontString(header, nil, "OVERLAY")
    win.title:SetJustifyH("LEFT")
    win.title:SetWordWrap(false)
    win.timer = S.CreateFontString(header, nil, "OVERLAY")
    win.timer:SetJustifyH("RIGHT")
    for _, kind in ipairs(ORDER) do win.buttons[kind] = HeaderButton(win, kind) end
    local body = S.CreateFrame("Frame", nil, frame)
    body.win, win.body = win, body
    body:SetFrameLevel(frame:GetFrameLevel() + 1)
    body:EnableMouse(true)
    body:EnableMouseWheel(true)
    for script, handler in pairs(D.bodyScripts) do body:SetScript(script, handler) end
    win.status = S.CreateFontString(body, nil, "OVERLAY")
    win.status:SetPoint("LEFT", body, "LEFT", 8, 0)
    win.status:SetPoint("RIGHT", body, "RIGHT", -8, 0)
    win.status:SetJustifyH("CENTER")
    -- Border strips live on their own frame above the header and the rows.
    -- They frame a box just outside the window (an anchor only, never drawn).
    local border = S.CreateFrame("Frame", nil, frame)
    border:SetAllPoints(frame)
    border:SetFrameLevel(frame:GetFrameLevel() + 10)
    win.border, win.edges = border, {}
    for i = 1, 4 do win.edges[i] = S.CreateTexture(border, nil, "OVERLAY") end
    win.borderBox = S.CreateTexture(border, nil, "OVERLAY")
    win.borderBox:Hide()
    local grip = S.CreateFrame("Button", nil, frame)
    grip.win, win.grip = win, grip
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(frame:GetFrameLevel() + 12)
    grip:SetNormalTexture(GRIP .. "Up")
    grip:SetHighlightTexture(GRIP .. "Highlight")
    grip:SetPushedTexture(GRIP .. "Down")
    for script, handler in pairs(D.gripScripts) do grip:SetScript(script, handler) end
    grip:Hide()
    return win
end

function D.EnsureWindow(index)
    local win = D.windows[index]
    if not win then
        win = D.NewWindow(UIParent, index)
        D.windows[index] = win
    end
    return win
end

-- The session updates a shown window hears (Controller.lua SessionUpdated):
-- M.watchTypes[meter type][key] is true for every shown window, key being
-- its pinned fight's sessionID, else 0 (Current and Overall take the copy
-- with sessionID 0). The 2026-10-11 raid trace: 38,586 session events,
-- 4,092 (10.6 %) of them dirtied a window. Rebuilt wherever a window shows,
-- hides or changes its meter or fight. An entry left over only costs the
-- window walk; a missing one would lose an update.
function D.SyncWatch()
    local watch = M.watchTypes
    for _, sessions in pairs(watch) do
        for key in pairs(sessions) do sessions[key] = nil end
    end
    for i = 1, D.MAX do
        local win = D.windows[i]
        local kind = win and win.shown and not win.faded and win.meterType
        if kind then
            local sessions = watch[kind]
            if not sessions then
                sessions = {}
                watch[kind] = sessions
            end
            sessions[win.sessionID or 0] = true
            if win.damageTarget then
                local targets = watch[D.TYPE.EnemyDamageTaken]
                if not targets then targets = {} watch[D.TYPE.EnemyDamageTaken] = targets end
                targets[win.sessionID or 0] = true
            end
        end
    end
end

-- Runtime session state; historic session IDs are never saved.
function D.ApplySession(win, value, sessionID, duration)
    D.ClearTarget(win)
    win.cfgSession, win.sessionID = value, sessionID
    win.pinDuration = sessionID and duration or nil
    local overall = value == D.SESSION.OVERALL
    win.sessionType = overall and D.OVERALL or D.CURRENT
    win.overall = not sessionID and overall
    D.SyncWatch()
end

-- Settings are the authority; runtime picks survive a Refresh while the
-- saved value is unchanged.
function D.SyncWindow(win)
    local c, keys = M.config, D.KEYS[win.index]
    local meterType = c[keys.Type] - 1
    if meterType ~= win.cfgType then
        D.ClearTarget(win)
        win.cfgType, win.meterType = meterType, meterType
        D.SyncWatch()
        D.CloseBreakdown(win, true)
        win.offset, win.dirty = 0, true
    end
    local value = c[keys.Session]
    if value ~= win.cfgSession then
        D.ApplySession(win, value, nil, nil)
        D.CloseBreakdown(win, true)
        win.offset, win.dirty = 0, true
    end
    D.ApplyScale(win)
end

function D.PlaceWindow(win)
    local c, keys = M.config, D.KEYS[win.index]
    win.frame:ClearAllPoints()
    win.frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", c[keys.X], c[keys.Y])
    win.placedConfig, win.placedX, win.placedY = c, c[keys.X], c[keys.Y]
end

-- The saved offsets are in the window's own scale (MSUF Edit Mode divides its
-- drag by the frame's scale). A new scale therefore rewrites them, and the
-- corner the window hangs from stays where the player put it. Only a scale
-- edit does that: a profile change, import or reset brings offsets of its own,
-- which PlaceWindow has not placed yet.
local function Rescaled(rule, offset, from, to)
    return max(rule.min, min(rule.max, floor(offset * from / to + .5)))
end

function D.ApplyScale(win)
    local c, keys = M.config, D.KEYS[win.index]
    local scale, previous = c[keys.Scale] / 100, win.cfgScale
    if scale == previous then return end
    win.cfgScale = scale
    win.frame:SetScale(scale)
    if previous and win.placedConfig == c and win.placedX == c[keys.X] and win.placedY == c[keys.Y] then
        local rules = S.catalog[M.id].rules
        c[keys.X] = Rescaled(rules[keys.X], c[keys.X], previous, scale)
        c[keys.Y] = Rescaled(rules[keys.Y], c[keys.Y], previous, scale)
    end
end

function D.Capacity(height)
    local style = M.style
    local capacity = floor((height - M.style.headerSpace - 2 + style.spacing) / (style.barHeight + style.spacing))
    return capacity < 0 and 0 or capacity > 40 and 40 or capacity
end

-- The header buttons shown, counted from the right: Target only for the damage
-- meters, and no Session button on a threat window, which has no fights.
local function HeaderSlots(c, meterType)
    if c.headerSelectors == false then return 2 end
    local slots = D.damageTypes[meterType] and c.targetSelector and #ORDER or #ORDER - 1
    return meterType == D.THREAT and slots - 1 or slots
end

function D.StyleHeader(win)
    local c = M.config
    local size = min(c.headerIconSize, c.headerHeight)
    local r, g, b = S.RGB(c.titleColor)
    local previous
    local slots, gap = HeaderSlots(c, win.meterType), 0
    for index, kind in ipairs(ORDER) do
        local button = win.buttons[kind]
        -- The buttons after the unused Session button close its slot.
        local unused = kind == "session" and win.meterType == D.THREAT
        if unused then gap = 1 end
        local slot = index - gap
        button.configuredShown = c.headerVisible ~= false and slot <= slots and not unused
        button:SetShown(button.configuredShown)
        button:ClearAllPoints()
        local elementSize = c[kind .. "Size"] > 0 and c[kind .. "Size"] or size
        button:SetSize(elementSize, elementSize)
        -- Every element has a stable slot; moving/resizing one never drags
        -- its siblings, the title or the combat timer through an anchor chain.
        button:SetPoint("RIGHT", win.header, "RIGHT", -3 - (slot - 1) * (size + 2)
            + c.buttonsOffsetX + c[kind .. "OffsetX"], c.buttonsOffsetY + c[kind .. "OffsetY"])
        previous = button
        if button.iconScale then button.icon:SetSize(elementSize * button.iconScale, elementSize * button.iconScale) end
        if button.label then
            D.FontStyle(button.label, c[kind .. "Size"] > 0 and max(8, floor(elementSize * .6)) or max(8, c.headerFontSize - 1), "header")
            button.label:SetTextColor(r, g, b)
            button.label:ClearAllPoints()
            button.label:SetPoint("CENTER", button, "CENTER", 0, M.style.baseline)
        end
        if button.bars then
            local width, thick = elementSize * .7, max(1, floor(elementSize / 9 + .5))
            for i, bar in ipairs(button.bars) do
                bar:ClearAllPoints()
                bar:SetSize(width * (1.3 - .3 * i), thick)
                bar:SetPoint("LEFT", button, "CENTER", -width / 2, (2 - i) * (thick + 2))
                bar:SetColorTexture(r, g, b, 1)
            end
        end
    end
    win.firstButton = previous
    D.FontStyle(win.title, c.titleSize > 0 and c.titleSize or c.headerFontSize, "header")
    win.title:SetTextColor(r, g, b)
    D.FontStyle(win.timer, c.headerTimerSize > 0 and c.headerTimerSize or c.headerFontSize, "header")
    win.timer:SetTextColor(r, g, b)
    win.title:ClearAllPoints()
    win.timer:ClearAllPoints()
    local timerRight = -3 - slots * (size + 2) - 2
    win.timer:SetPoint("RIGHT", win.header, "RIGHT", timerRight + c.headerTimerOffsetX, M.style.baseline + c.headerTimerOffsetY)
    win.title:SetPoint("LEFT", win.header, "LEFT", 6 + c.titleOffsetX, M.style.baseline + c.titleOffsetY)
    win.title:SetPoint("RIGHT", win.header, "RIGHT", timerRight - c.headerFontSize * 3 - 4 + c.titleOffsetX, M.style.baseline + c.titleOffsetY)
end

-- The outline sits outside the window: S.PlaceEdges frames the box that
-- reaches size pixels past each side, so the strips cover the same pixels
-- as an outline drawn around the window itself.
function D.StyleBorder(win)
    local c, box, spec = M.config, win.borderBox, M.style.windowBorder
    local top = win.border
    if c.borderArea == 2 and c.headerVisible ~= false then top = win.header end
    if c.borderArea == 3 then top = win.body end
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", top, "TOPLEFT", -spec.size - spec.gap, spec.size + spec.gap)
    box:SetPoint("BOTTOMRIGHT", win.border, "BOTTOMRIGHT", spec.size + spec.gap, -spec.size - spec.gap)
    D.PaintBorder(win.border, win.edges, box, spec)
end

-- Layout pass: runs when the style generation changed (after Refresh).
function D.StyleWindowLayout(win)
    local c, keys = M.config, D.KEYS[win.index]
    local frame, header, body = win.frame, win.header, win.body
    win.styleGen = M.styleGen
    local height = c[keys.Height]
    frame:SetSize(c[keys.Width], height)
    header:ClearAllPoints()
    local headerPoint = c.headerVisible ~= false and c.headerOutside and "BOTTOM" or "TOP"
    header:SetPoint(headerPoint .. "LEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint(headerPoint .. "RIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(c.headerVisible ~= false and c.headerHeight or 0)
    header:SetShown(c.headerVisible ~= false)
    D.PaintSurface(win.headerBg, M.style.headerTexture, c.headerColor, c.headerAlpha)
    win.bg:ClearAllPoints()
    win.bg:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    win.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    D.PaintSurface(win.bg, M.style.bgTexture, c.bgColor, c.bgAlpha)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 1, -1)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    D.StyleHeader(win)
    D.StyleHeaderSeparator(win)
    D.StyleBorder(win)
    D.FontStyle(win.status, M.style.leftSize)
    win.status:SetTextColor(.8, .8, .8)
    win.status:ClearAllPoints()
    win.status:SetPoint("LEFT", body, "LEFT", 8, M.style.baseline)
    win.status:SetPoint("RIGHT", body, "RIGHT", -8, M.style.baseline)
    win.capacity = D.Capacity(height)
    for slot, row in pairs(win.rows) do D.AnchorRow(row, body, slot) end
    -- Keep the current fade state through a style refresh. Resetting it would
    -- make ApplyHover fetch and paint once before Refresh's batched paint.
    win.titleText, win.statusText, win.timerSecond, win.buttonAlpha = nil, nil, false, nil
end

function D.StyleWindow(win)
    D.StyleWindowLayout(win)
    D.PlaceWindow(win)
    local keys, rules = D.KEYS[win.index], S.catalog[M.id].rules
    win.frame:SetResizeBounds(rules[keys.Width].min, rules[keys.Height].min,
        rules[keys.Width].max, rules[keys.Height].max)
    D.UpdateTitle(win)
    D.ApplyHover(win)
end

function D.UpdateTitle(win)
    local text = D.TypeName(win.meterType)
    if win.damageTarget then text = format("%s: %s", text, win.damageTarget.name) end
    if win.meterType == D.THREAT then
        -- Threat reads the watched enemy, never a fight session.
        local enemy = D.ThreatEnemyName()
        if enemy then text = format("%s - %s", text, enemy) end
    elseif win.overall then
        text = format("%s (%s)", text, S.BlizzardText("DAMAGE_METER_OVERALL_SESSION", "Overall"))
    end
    if text ~= win.titleText then
        win.titleText = text
        win.title:SetText(text)
    end
    local label = win.buttons.session.label
    if win.sessionID then
        label:SetText("#")
    elseif win.overall then
        label:SetText(S.BlizzardText("DAMAGE_METER_OVERALL_SESSION_SHORT", "O"))
    else
        label:SetText(S.BlizzardText("DAMAGE_METER_CURRENT_SESSION_SHORT", "C"))
    end
end

-- Memoized per displayed second; nil clears the timer.
function D.SetTimerText(win, seconds)
    if seconds then seconds = floor(seconds) end
    if seconds == win.timerSecond then return end
    win.timerSecond = seconds
    win.timer:SetText(seconds and seconds > 0 and format("(%s)", D.Clock(seconds)) or "")
end

function D.SetShown(win, show)
    if show then
        if win.styleGen ~= M.styleGen then D.StyleWindow(win) end
        if not win.shown then
            win.filteredCache, win.targetCache = nil, nil
            win.shown, win.dirty = true, true
            D.SyncWatch()
            win.frame:Show()
        end
        D.ApplyHover(win)
    elseif win.shown then
        win.shown, win.hover = false, false
        D.SyncWatch()
        if D.typePanel and D.typePanel.win == win then D.HideTypeMenu() end
        D.CloseBreakdown(win, true)
        D.HideTip()
        win.frame:Hide()
    end
end

function D.LocalIndex(sources, count)
    for i = 1, count do
        local flag = sources[i].isLocalPlayer
        if not IsSecret(flag) and flag == true then return i end
    end
    return 0
end

-- showPlayer can pin the own row into the first or last slot; one extra
-- scroll step keeps the list end reachable while that pin is active.
function D.MaxOffset(win, count)
    local extra = (M.style.showPlayer and count > win.capacity and win.capacity > 1) and 1 or 0
    return max(0, count - win.capacity + extra)
end

local function Separator(row, edge)
    local line = row.separator
    if not edge then
        if line then line:Hide() end
        return
    end
    if not line then
        line = S.CreateTexture(row, nil, "OVERLAY")
        line:SetColorTexture(1, 1, 1, .35)
        line:SetHeight(1)
        row.separator = line
    end
    if row.separatorEdge ~= edge then
        row.separatorEdge = edge
        line:ClearAllPoints()
        line:SetPoint(EDGE[edge][1], row, EDGE[edge][1], 0, 0)
        line:SetPoint(EDGE[edge][2], row, EDGE[edge][2], 0, 0)
    end
    line:Show()
end

function D.UpdateStatus(win, count)
    local text = ""
    if not M.available and not M.preview and win.meterType ~= D.THREAT then
        text = M.reason or ""
    elseif count == 0 then
        if win.damageTarget and not win.session then
            text = S.Text((M.inCombat or NS.IsCombatLocked()) and "Targets after combat" or "Target data unavailable")
        elseif win.meterType == D.TYPE.AvoidableDamageTaken then
            local notice = _G.DAMAGE_METER_AVOIDABLE_DAMAGE_NOT_ACTIVE
            text = type(notice) == "string" and notice or ""
        end
    end
    if text ~= win.statusText then
        win.statusText = text
        win.status:SetText(text)
    end
end

-- Content pass over the visible slots only; uses the cached session, so
-- scrolling and resizing never refetch.
function D.Render(win)
    local session = win.session
    local sources = session and session.combatSources
    local count = D.Count(sources)
    local capacity = win.capacity
    win.count = count
    local offset = min(win.offset, D.MaxOffset(win, count))
    win.offset = offset
    local pinSlot, pinIndex = 0, 0
    if M.style.showPlayer and count > capacity and capacity > 1 then
        local own = D.LocalIndex(sources, count)
        if own > 0 and own <= offset then
            pinSlot, pinIndex = 1, own
        elseif own > offset + capacity then
            pinSlot, pinIndex = capacity, own
        end
    end
    local rows = win.rows
    for slot = 1, capacity do
        local index = offset + slot
        if slot == pinSlot then index = pinIndex elseif pinSlot == 1 then index = offset + slot - 1 end
        local row = rows[slot]
        if index >= 1 and index <= count then
            if not row then
                row = D.CreateRow(win.body, win, "list")
                rows[slot] = row
                if slot > win.maxRow then win.maxRow = slot end
                D.AnchorRow(row, win.body, slot)
            end
            row.index = index
            D.PaintSource(row, sources[index], index, session, win)
            Separator(row, slot == pinSlot and (slot == 1 and "BOTTOM" or "TOP") or nil)
            row:Show()
        elseif row then
            row.index = nil
            row:Hide()
        end
    end
    for slot = capacity + 1, win.maxRow do
        local row = rows[slot]
        if row then
            row.index = nil
            row:Hide()
        end
    end
    D.UpdateStatus(win, count)
end

function D.Paint(win, session, reuseSession)
    -- A clean window must hear session updates again (see Controller.lua);
    -- a threat window never hears them.
    if M.sessionMuted and win.meterType ~= D.THREAT then D.ResumeSessionUpdates() end
    win.dirty = false
    if win.bd.open then
        D.RefreshBreakdown(win)
        return
    end
    if reuseSession then win.session = session else win.session = D.FetchSession(win) end
    D.Render(win)
end

function D.Scroll(win, delta)
    if not Public(delta) or type(delta) ~= "number" or delta == 0 then return end
    local offset = min(D.MaxOffset(win, win.count), max(0, win.offset + (delta > 0 and -2 or 2)))
    if offset ~= win.offset then
        win.offset = offset
        D.HideTip()
        D.Render(win)
    end
end

-- Hover state drives Mouseover visibility, header buttons on mouseover and
-- the resize grip. OnEnter/OnLeave plus IsMouseOver on leave; no polling.
function D.HoverEnter(region)
    local win = region.win
    if win.hover then return end
    win.hover = true
    D.ApplyHover(win)
end

function D.HoverLeave(region)
    local win = region.win
    if not win.hover or win.frame:IsMouseOver() then return end
    win.hover = false
    D.ApplyHover(win)
end

function D.ApplyHover(win, deferred)
    local c = M.config
    local fade = M.uiHidden or (c.visibility == D.VISIBILITY.MOUSEOVER and not M.forced and not win.hover)
    if fade ~= win.faded then
        win.faded, win.dirty = fade, true
        win.frame:SetAlpha(fade and 0 or 1)
        if not fade then
            win.filteredCache, win.targetCache = nil, nil
            D.InvalidateTargets()
        end
        if not deferred then
            local resumeIdentities = not fade and not M.dataVisible
            D.SyncWatch()
            D.UpdateEvents()
            if resumeIdentities then D.SnapshotIdentities() end
        end
        -- Faded windows skip painting; catch up once they are revealed.
        if not deferred and not fade and win.shown and win.dirty then D.Paint(win) end
        if not deferred and not fade and win.shown then D.UpdateTimers() end
        if not deferred and fade and not D.HasDirtyVisible() then D.CancelPaint() end
        if not deferred then
            if fade then D.UpdateTimer() end
            D.SyncClock()
        end
    end
    local alpha = (c.headerMouseover and not win.hover and not M.forced) and 0 or 1
    if alpha ~= win.buttonAlpha then
        win.buttonAlpha = alpha
        for _, button in pairs(win.buttons) do button:SetAlpha(alpha) end
    end
    win.grip:SetShown(win.hover and D.CanMove(win))
end

-- Edit Mode and the preview unlock every window for placement.
function D.CanMove(win)
    return not M.inCombat and not NS.IsCombatLocked() and (M.forced or not M.config[D.KEYS[win.index].Locked])
end

-- Click-through (the window's Click through choice): the window's own frames
-- stop taking the mouse, so clicks reach the game under it. D.EvaluateVisibility
-- asks at every combat edge. Edit Mode and the options preview keep the window
-- usable, and so does a Mouseover window, which needs the mouse to appear.
local CLICK_THROUGH = NS.DamageMeterClickThrough
local function WantsPassive(win)
    local mode = M.config[D.KEYS[win.index].ClickThrough]
    if mode == CLICK_THROUGH.NEVER or M.forced or M.config.visibility == D.VISIBILITY.MOUSEOVER then return false end
    return mode == CLICK_THROUGH.ALWAYS or M.inCombat == true
end

local function SetMouse(win, enabled)
    win.frame:EnableMouse(enabled)
    win.header:EnableMouse(enabled)
    win.body:EnableMouse(enabled)
    win.grip:EnableMouse(enabled)
    for _, button in pairs(win.buttons) do button:EnableMouse(enabled) end
    for _, row in pairs(win.rows) do row:EnableMouse(enabled) end
    local panel = win.panel
    if not panel then return end
    panel:EnableMouse(enabled)
    panel.targetsTab:EnableMouse(enabled)
    panel.spellsTab:EnableMouse(enabled)
    for _, row in pairs(win.bdRows) do row:EnableMouse(enabled) end
end

function D.ApplyMouse(win)
    local passive = WantsPassive(win)
    if passive == (win.passive == true) then return end
    win.passive = passive
    SetMouse(win, not passive)
    -- A frame that stops taking the mouse may never report the pointer leaving.
    if passive and win.hover then
        win.hover = false
        D.ApplyHover(win)
    end
end

local function Round(value) return floor(value + .5) end
function D.SaveGeometry(win, sized)
    local frame, keys = win.frame, D.KEYS[win.index]
    local right, bottom = frame:GetRight(), frame:GetBottom()
    local parentRight, parentBottom = UIParent:GetRight(), UIParent:GetBottom()
    -- The frame's edges are in its own scale, UIParent's in the screen's: the
    -- offsets are saved in the window's scale (see D.ApplyScale).
    local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    if not (Finite(right) and Finite(bottom) and Finite(parentRight) and Finite(parentBottom) and Finite(ratio)) then
        D.PlaceWindow(win)
        return
    end
    local values = { [keys.X] = Round(right - parentRight * ratio), [keys.Y] = Round(bottom - parentBottom * ratio) }
    if sized then
        local width, height = frame:GetWidth(), frame:GetHeight()
        if Finite(width) and Finite(height) then values[keys.Width], values[keys.Height] = Round(width), Round(height) end
    end
    if not S.SetMany(M.id, values) then D.PlaceWindow(win) end
end

function D.DragStart(header)
    local win = header.win
    if not D.CanMove(win) then return end
    win.moving = true
    D.HideTip()
    win.frame:StartMoving()
end

function D.DragStop(header)
    local win = header.win
    if not win.moving then return end
    win.moving = false
    win.frame:StopMovingOrSizing()
    D.SaveGeometry(win, false)
end

function D.GripDown(grip, button)
    local win = grip.win
    if button ~= "LeftButton" or not D.CanMove(win) then return end
    win.sizing = true
    D.HideTip()
    win.frame:StartSizing("BOTTOMRIGHT")
end

function D.GripUp(grip)
    local win = grip.win
    if not win.sizing then return end
    win.sizing = false
    win.frame:StopMovingOrSizing()
    D.SaveGeometry(win, true)
end

-- Live resizing: recompute how many rows fit and repaint from the cache.
function D.WindowSized(frame, _, height)
    local win = frame.win
    if win.styleGen ~= M.styleGen or not Finite(height) then return end
    local capacity = D.Capacity(height)
    if capacity == win.capacity then return end
    win.capacity = capacity
    if not win.shown then return end
    if win.bd.open then D.RenderBreakdown(win) else D.Render(win) end
end

function D.HeaderClick(header, button) if button == "RightButton" then D.OpenTypeMenu(header.win, header) end end

function D.BodyWheel(body, delta) D.Scroll(body.win, delta) end

function D.BodyMouseUp(body, button) if button == "RightButton" then D.OpenTypeMenu(body.win, body) end end

D.headerScripts = {
    OnDragStart = D.DragStart,
    OnDragStop = D.DragStop,
    OnClick = D.HeaderClick,
    OnEnter = D.HoverEnter,
    OnLeave =
        D.HoverLeave
}
D.bodyScripts = { OnMouseWheel = D.BodyWheel, OnMouseUp = D.BodyMouseUp, OnEnter = D.HoverEnter, OnLeave = D.HoverLeave }
D.gripScripts = { OnMouseDown = D.GripDown, OnMouseUp = D.GripUp, OnEnter = D.HoverEnter, OnLeave = D.HoverLeave }
