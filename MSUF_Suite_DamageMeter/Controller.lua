local _, P = ...
local NS, S = P.NS, P.Suite
-- Damage meter controller: lifecycle, event-driven paints and visible clocks,
-- visibility rules and Edit Mode movers.
--
-- Refresh model: DAMAGE_METER_* events only mark windows dirty (Blizzard's
-- dedupe: Current/Overall windows react to sessionID 0, a pinned window to
-- its own ID). One cancellable timer coalesces dirty data at refreshRate in
-- combat, or after 0.1 s out of combat. A separate one-shot timer advances
-- only visible live clock text. Combat end paints once and again after 0.5 s
-- because declassification can lag the regen edge.
local D = P.DamageMeter
local M = D.M
local Public = S.Public
local max, format = math.max, string.format
local HOST_KEY = "external:msuf.blizzard:damagemeter"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ZONES = { party = "HideDungeon", scenario = "HideDungeon", raid = "HideRaid", pvp = "HidePvP", arena = "HidePvP" }
local PREVIEW_SECONDS = 95
local VISIBILITY, TEXT_STYLE, SESSION = D.VISIBILITY, D.TEXT_STYLE, D.SESSION
local OUTLINED = { [TEXT_STYLE.OUTLINE] = "OUTLINE", [TEXT_STYLE.OUTLINE_SHADOW] = "OUTLINE",
    [TEXT_STYLE.THICK] = "THICKOUTLINE", [TEXT_STYLE.THICK_SHADOW] = "THICKOUTLINE" }
local SHADOWED = { [TEXT_STYLE.SHADOW] = true, [TEXT_STYLE.OUTLINE_SHADOW] = true, [TEXT_STYLE.THICK_SHADOW] = true }
-- The fontRendering choice "Slug" draws no shadow (S.SetStyledFont).
local SLUG = NS.FontRendering.SLUG

function D.BuildStyle()
    D.ConfigureAbbreviation()
    local c = M.config
    local style = M.style or {}
    M.style = style
    style.font = S.ResolveFont(c.font)
    style.outline = OUTLINED[c.outline] or ""
    style.rendering = c.rendering
    style.shadow = SHADOWED[c.outline] == true and c.rendering ~= SLUG
    style.shadowOpacity, style.shadowDistance = c.shadowOpacity, c.shadowDistance
    style.textAlpha, style.baseline = c.textOpacity / 100, c.baseline
    style.leftSize, style.rightSize, style.barHeight, style.spacing = c.leftSize, c.rightSize, c.barHeight, c.barSpacing
    style.texture = S.ResolveTexture(c.barTexture, WHITE)
    style.barAlpha = c.barAlpha / 100
    style.barR, style.barG, style.barB = S.RGB(c.barColor)
    style.gradientLeft, style.gradientRight, style.gradientUp, style.gradientDown =
        c.gradientDirLeft, c.gradientDirRight, c.gradientDirUp, c.gradientDirDown
    style.gradientEnabled = c.gradientEnabled and c.gradientStrength > 0
        and (style.gradientLeft or style.gradientRight or style.gradientUp or style.gradientDown)
    style.gradientStrength = c.gradientStrength / 100
    style.gradientR, style.gradientG, style.gradientB = S.RGB(c.gradientColor)
    if style.gradientEnabled then
        style.gradientClear = CreateColor(style.gradientR, style.gradientG, style.gradientB, 0)
        style.gradientTint = CreateColor(style.gradientR, style.gradientG, style.gradientB, style.gradientStrength)
    else
        style.gradientClear, style.gradientTint = nil, nil
    end
    style.trackR, style.trackG, style.trackB = S.RGB(c.trackColor)
    style.trackA = c.trackAlpha / 100
    style.leftR, style.leftG, style.leftB = S.RGB(c.leftColor)
    style.rightR, style.rightG, style.rightB = S.RGB(c.rightColor)
    style.classColors, style.leftClass, style.rightClass = c.classColors, c.leftClassColor, c.rightClassColor
    style.iconStyle, style.zoom = c.iconStyle, c.iconZoom / 100
    style.rank, style.numberFormat, style.valueOrder, style.valueSeparator, style.percent, style.showPlayer =
        c.rank, c.numberFormat, c.valueOrder, c.valueSeparator, c.percent, c.showPlayer
end

function D.MarkAll()
    for i = 1, D.MAX do
        local win = D.windows[i]
        if win then win.dirty = true end
    end
end

-- Header timers: live Current duration (memoized per displayed second), the
-- stored duration of a pinned fight, nothing for Overall.
function D.UpdateTimers()
    local c = M.config
    local current, currentResolved
    for i = 1, c.windowCount do
        local win = D.windows[i]
        if win and win.shown and not win.faded then
            local seconds
            if c.combatTime and c.headerTimer then
                if win.sessionID then
                    seconds = win.pinDuration
                elseif not win.overall then
                    if not currentResolved then
                        if M.preview then
                            current = PREVIEW_SECONDS
                        elseif M.inCombat then
                            current = D.LiveDuration()
                        else
                            current = D.Duration(D.CURRENT)
                        end
                        current = current or false
                        currentResolved = true
                    end
                    seconds = current or nil
                end
            end
            D.SetTimerText(win, seconds)
        end
    end
    D.UpdateTimer(current, currentResolved and M.inCombat and not M.forced)
end

-- DAMAGE_METER_COMBAT_SESSION_UPDATED fires twice per change, hundreds of
-- times per second in raid combat. While a paint is pending and every shown
-- window is already dirty, further updates cannot change what that paint
-- draws: it fetches the session when it runs. The event is unregistered for
-- that span and registered again, with the target cache invalidated, as
-- soon as the pending paint clears or any window paints, before anything is
-- drawn. So a muted meter always has every shown window dirty.
local SESSION_EVENT = "DAMAGE_METER_COMBAT_SESSION_UPDATED"
local SessionUpdated

local function MuteSessionUpdates()
    if M.sessionMuted or not M.events[SESSION_EVENT] then return end
    M.sessionMuted = true
    M.context:RemoveEvent(SESSION_EVENT)
end

function D.ResumeSessionUpdates()
    if not M.sessionMuted then return end
    M.sessionMuted = false
    D.InvalidateTargets()
    if M.events[SESSION_EVENT] then M.context:Event(SESSION_EVENT, SessionUpdated, true) end
end

-- Deferred paints and clock ticks use C_Timer.After with one shared callback
-- each and keep at most one call in flight: no timer object per paint or per
-- second. The pending flag is the request; cancelling clears it, so a call
-- still in flight finds nothing to do, and a newer request reuses that call
-- instead of scheduling another.
function D.CancelPaint()
    M.pendingPaint = false
    D.ResumeSessionUpdates()
end

function D.PaintDirty()
    D.CancelPaint()
    local c = M.config
    -- A batch may contain several windows showing the same meter/session.
    -- Reuse that one API snapshot only within this paint pass; session data
    -- can change before the next event, and breakdowns fetch their own source.
    local batch = (M.paintBatch or 0) + 1
    M.paintBatch = batch
    for i = 1, c.windowCount do
        local win = D.windows[i]
        if win and win.shown and win.dirty and not win.faded then
            local previous
            if not win.bd.open then
                for j = 1, i - 1 do
                    local candidate = D.windows[j]
                    if candidate and candidate.paintBatch == batch and candidate.meterType == win.meterType
                        and candidate.sessionType == win.sessionType and candidate.sessionID == win.sessionID then
                        previous = candidate
                        break
                    end
                end
            end
            if previous then D.Paint(win, previous.session, true) else D.Paint(win) end
            if not win.bd.open then win.paintBatch = batch end
        end
    end
    D.UpdateTimers()
    if M.inCombat then M.nextPaint = GetTime() + max(.2, c.refreshRate) end
end

-- Mouseover-only windows retain dirty data while faded. There is no data
-- timer unless a dirty window can actually be painted.
function D.HasDirtyVisible()
    if not M.anyShown then return false end
    for i = 1, M.config.windowCount do
        local win = D.windows[i]
        if win and win.shown and win.dirty and not win.faded then return true end
    end
    return false
end

-- Only Current headers and the separate combat timer need changing seconds.
-- Pinned durations and Overall have no live clock work.
function D.NeedClock()
    local c = M.config
    if not M.active or not M.inCombat or not c.combatTime then return false end
    if c.timer and not (M.sessionHidden and c.toggleTimer) then return true end
    if not c.headerTimer or not M.anyShown then return false end
    for i = 1, c.windowCount do
        local win = D.windows[i]
        if win and win.shown and not win.faded and not win.sessionID and not win.overall then return true end
    end
    return false
end

function D.StopClock()
    M.clockRunning = false
end

function D.ClockTick()
    M.clockInFlight = false
    if not M.clockRunning then return end
    M.clockRunning = false
    if not D.NeedClock() then return end
    D.UpdateTimers()
    D.SyncClock()
end

function D.SyncClock()
    if not D.NeedClock() then
        D.StopClock()
        return
    end
    if M.clockRunning then return end
    M.clockRunning = true
    if M.clockInFlight then return end
    M.clockInFlight = true
    local origin = M.combatStart or 0
    C_Timer.After(1 - ((GetTime() - origin) % 1) + .02, D.ClockTick)
end

function D.DeferredPaint()
    M.paintInFlight = false
    if not M.pendingPaint then return end
    M.pendingPaint = false
    D.ResumeSessionUpdates()
    if M.active and D.HasDirtyVisible() then D.PaintDirty() end
end

function D.RequestPaint()
    if M.pendingPaint or not M.active or not D.HasDirtyVisible() then return end
    M.pendingPaint = true
    if M.paintInFlight then return end
    M.paintInFlight = true
    local delay = .1
    if M.inCombat then
        local now = GetTime()
        delay = max(.01, (M.nextPaint or now) - now)
    end
    C_Timer.After(delay, D.DeferredPaint)
end

-- A pinned historic fight returns to Current (autoCurrent, resets).
function D.ClearPins()
    for i = 1, M.config.windowCount do
        local win = D.windows[i]
        if win and win.sessionID then
            D.ApplySession(win, SESSION.CURRENT, nil, nil)
            D.CloseBreakdown(win, true)
            win.offset, win.timerSecond, win.dirty = 0, false, true
            D.UpdateTitle(win)
        end
    end
end

function D.ZoneKey()
    local inside, kind = IsInInstance()
    if not Public(inside) or not Public(kind) or not inside then return "HideWorld" end
    return ZONES[kind] or "HideWorld"
end

SessionUpdated = function(self, _, meterType, sessionID)
    if not Public(meterType) or not Public(sessionID) then return end
    D.InvalidateTargets()
    local dirty, clean = false, false
    for i = 1, self.config.windowCount do
        local win = D.windows[i]
        if win and win.shown then
            if win.meterType == meterType then
                local id = win.sessionID
                if (id and id == sessionID) or (not id and sessionID == 0) then win.dirty, dirty = true, true end
            end
            clean = clean or not win.dirty
        end
    end
    if dirty then D.RequestPaint() end
    if M.pendingPaint and not clean then MuteSessionUpdates() end
end
local function CurrentUpdated(self)
    D.InvalidateTargets()
    local dirty = false
    for i = 1, self.config.windowCount do
        local win = D.windows[i]
        if win and win.shown and not win.sessionID and not win.overall then win.dirty, dirty = true, true end
    end
    if dirty then D.RequestPaint() end
end
local function Reset()
    D.InvalidateTargets()
    for i = 1, D.MAX do
        local win = D.windows[i]
        if win then
            if win.sessionID then
                D.ApplySession(win, SESSION.CURRENT, nil, nil)
                D.UpdateTitle(win)
            end
            D.CloseBreakdown(win, true)
            win.offset, win.timerSecond, win.dirty = 0, false, true
        end
    end
    M.lastDuration = nil
    D.HideTip()
    D.PaintDirty()
end
local function CombatStart(self)
    D.InvalidateTargets()
    M.inCombat = true
    M.combatStart = GetTime()
    M.nextPaint = nil
    M.preview = false
    if self.config.autoCurrent then D.ClearPins() end
    D.HideTip()
    D.EvaluateVisibility()
    D.MarkAll()
    D.PaintDirty()
    D.SyncClock()
end
-- Panels that only said "after combat" return to their list once data is readable.
local function CloseBlocked()
    for i = 1, D.MAX do
        local win = D.windows[i]
        if win and win.bd.open and win.bd.blocked then D.CloseBreakdown(win, true) end
    end
end
local function LateRepaint()
    if not M.active or M.inCombat then return end
    CloseBlocked()
    D.MarkAll()
    D.PaintDirty()
end
local function CombatEnd()
    D.InvalidateTargets()
    M.inCombat = false
    -- Only the floating timer keeps this; it keeps what it showed: the combat
    -- clock while it shows tenths (Timer.lua), else the session duration.
    local clock = M.config.timerDecimals and M.combatStart and GetTime() - M.combatStart
    M.lastDuration = clock or D.Duration(D.CURRENT) or M.lastDuration
    D.StopClock()
    D.CancelPaint()
    M.nextPaint = nil
    CloseBlocked()
    -- Saved picks made in combat refresh the whole module; otherwise paint once.
    if not D.FlushWrites() then
        D.EvaluateVisibility()
        D.MarkAll()
        D.PaintDirty()
    end
    C_Timer.After(.5, LateRepaint)
end
local function Encounter(self, event)
    D.InvalidateTargets()
    if event == "ENCOUNTER_START" and self.config.autoCurrent then D.ClearPins() end
    D.MarkAll()
    D.RequestPaint()
end
local function World(self)
    D.InvalidateTargets()
    local combat = NS.IsCombatLocked()
    if combat and not M.inCombat then CombatStart(self) elseif not combat and M.inCombat then CombatEnd() end
    M.available, M.reason = S.DamageMeterAvailability()
    D.EvaluateVisibility()
    D.MarkAll()
    D.RequestPaint()
end
local function Roster()
    D.EvaluateVisibility()
    D.RequestPaint()
end
local function KeyStart(self)
    if self.config.mythicReset then C_DamageMeter.ResetAllCombatSessions() end
end
-- Fires after a restriction lifted: session data is readable again.
local function Restriction(_, _, _, state)
    if Public(state) and state == Enum.AddOnRestrictionState.Inactive then
        D.InvalidateTargets()
        if not M.inCombat then CloseBlocked() end
        D.MarkAll()
        D.RequestPaint()
    end
end

local function Want(event, on, handler)
    on = on and true or false
    if (M.events[event] == true) == on then return end
    M.events[event] = on or nil
    if on then M.context:Event(event, handler, true) else M.context:RemoveEvent(event) end
end
-- Data events only while a window is shown; combat and zone events while a
-- window could appear (or the standalone timer runs). A combat that started
-- keeps PLAYER_REGEN_ENABLED until it ends: Edit Mode or the preview can
-- force windows at combat start and stop forcing them inside it.
function D.UpdateEvents()
    local c = M.config
    local possible = M.forced or c.visibility ~= VISIBILITY.NEVER
    local clock = possible or (c.combatTime and c.timer)
    Want("PLAYER_REGEN_DISABLED", clock, CombatStart)
    Want("PLAYER_REGEN_ENABLED", clock or M.inCombat, CombatEnd)
    Want("PLAYER_ENTERING_WORLD", clock, World)
    Want("ZONE_CHANGED_NEW_AREA", possible, World)
    Want("GROUP_ROSTER_UPDATE", possible and c.visibility == VISIBILITY.GROUP, Roster)
    Want("CHALLENGE_MODE_START", c.mythicReset, KeyStart)
    local data = M.anyShown
    Want("DAMAGE_METER_COMBAT_SESSION_UPDATED", data, SessionUpdated)
    Want("DAMAGE_METER_CURRENT_SESSION_UPDATED", data, CurrentUpdated)
    Want("DAMAGE_METER_RESET", data, Reset)
    Want("ENCOUNTER_START", data, Encounter)
    Want("ENCOUNTER_END", data, Encounter)
    Want("ADDON_RESTRICTION_STATE_CHANGED", data, Restriction)
end

-- Visibility: Edit Mode (out of combat) and the options preview force every
-- configured window; otherwise the global rule, then per-window zone hides.
-- Mouseover keeps windows shown and fades them (see D.ApplyHover).
function D.EvaluateVisibility()
    local c = M.config
    M.forced = M.preview == true or (S.editMode == true and not M.inCombat)
    local base
    if M.forced then
        base = true
    elseif M.sessionHidden or c.visibility == VISIBILITY.NEVER then
        base = false
    elseif c.visibility == VISIBILITY.COMBAT then
        base = M.inCombat == true
    elseif c.visibility == VISIBILITY.GROUP then
        local grouped = IsInGroup()
        base = Public(grouped) and grouped == true
    else
        base = true
    end
    local zone = base and not M.forced and D.ZoneKey()
    local any = false
    for i = 1, D.MAX do
        local win = D.windows[i]
        local show = base and i <= c.windowCount and not (zone and c[D.KEYS[i][zone]])
        if show and not win then
            win = D.EnsureWindow(i)
            D.SyncWindow(win)
        end
        if win then D.SetShown(win, show) end
        any = any or show
    end
    M.anyShown = any
    D.UpdateEvents()
    if not D.HasDirtyVisible() then D.CancelPaint() end
    D.SyncClock()
end

function M:Enable()
    M.inCombat = NS.IsCombatLocked()
    M.preview, M.pendingWrites, M.lastDuration, M.nextPaint = false, nil, nil, nil
    D.SessionTypes()
    self:Refresh()
end

-- The meter hotkey can also hide the QoL action tracker. Its export repaints
-- the tracker, so it is called only when the answer changes, not on every
-- refresh (each slider tick of a meter setting).
local historyPushed
local function SyncHistoryVisibility()
    local hidden = M.active and M.config.toggleHistory and M.sessionHidden or false
    if hidden == historyPushed or not S.SetActionTrackerSessionHidden then return end
    historyPushed = hidden
    S.SetActionTrackerSessionHidden(hidden)
end

function M:Refresh()
    local c = self.config
    SyncHistoryVisibility()
    D.InvalidateTargets()
    -- Blizzard's own meter UI stays hidden (reversible CVar; the data API keeps
    -- working) and MSUF's mover for it steps aside while this module is active.
    self.context:CVar("damageMeterEnabled", 0)
    S.SuppressHostElement(self.id, HOST_KEY, true)
    M.styleGen = M.styleGen + 1
    D.BuildStyle()
    M.available, M.reason = S.DamageMeterAvailability()
    for i = 1, c.windowCount do
        local win = D.EnsureWindow(i)
        local layer = c["w" .. i .. "Layer"]
        local restored = S.ApplyOwnedLayer(win.frame, layer)
        S.ApplyOwnedChildLayer(win.body, win.frame, layer, 1, restored)
        S.ApplyOwnedChildLayer(win.header, win.frame, layer, 3, restored)
        S.ApplyOwnedChildLayer(win.border, win.frame, layer, 10, restored)
        S.ApplyOwnedChildLayer(win.grip, win.frame, layer, 12, restored)
        if win.panel then S.ApplyOwnedChildLayer(win.panel, win.frame, layer, 5, restored) end
        D.SyncWindow(win)
    end
    D.HideTip()
    D.EvaluateVisibility()
    D.StyleTimer()
    D.MarkAll()
    D.PaintDirty()
end

-- Frames are kept and reused by the next Enable.
function M:Disable()
    M.sessionHidden = nil
    SyncHistoryVisibility()
    D.StopClock()
    D.CancelPaint()
    D.HideTypeMenu()
    M.preview, M.pendingWrites, M.forced, M.anyShown, M.inCombat, M.nextPaint = false, nil, false, false, false, nil
    for i = 1, D.MAX do
        local win = D.windows[i]
        if win then
            D.CloseBreakdown(win, true)
            win.targetCache = nil
            win.shown, win.hover = false, false
            win.frame:Hide()
        end
    end
    D.HideTip()
    if M.timerFrame then M.timerFrame:Hide() end
    S.SuppressHostElement(self.id, HOST_KEY, false)
    for event in pairs(M.events) do
        M.events[event] = nil
        self.context:RemoveEvent(event)
    end
end

local movers
local function Movers()
    if movers then return movers end
    movers = {}
    local label = S.BlizzardText("DAMAGE_METER_LABEL", "Damage meter")
    for i = 1, D.MAX do
        local index = i
        local keys = D.KEYS[i]
        movers[i] = {
            elementID = "window" .. i, label = format("%s %d", label, i), point = "BOTTOMRIGHT", order = 900 + i,
            xKey = keys.X, yKey = keys.Y,
            getFrame = function()
                local win = D.windows[index]
                return win and win.frame
            end,
            isEnabled = function() return index <= M.config.windowCount end,
            historyKeys = { keys.Width, keys.Height },
            extraControls = {
                { id = "width", label = "Width", kind = "number", min = 150, max = 900, step = 1,
                    get = function() return S.Config("damageMeter")[keys.Width] end,
                    set = function(value) return S.Set("damageMeter", keys.Width, value) end },
                { id = "height", label = "Height", kind = "number", min = 50, max = 900, step = 1,
                    get = function() return S.Config("damageMeter")[keys.Height] end,
                    set = function(value) return S.Set("damageMeter", keys.Height, value) end },
            },
        }
    end
    movers.timer = {
        label = "Combat timer", point = "CENTER", order = 906, xKey = "timerX", yKey = "timerY",
        getFrame = function() return M.timerFrame end,
        isEnabled = function() return M.config.combatTime and M.config.timer == true end,
        historyKeys = { "timerSize" },
        extraControls = {
            { id = "size", label = "Text size", kind = "number", min = 10, max = 40, step = 1,
                get = function() return S.Config("damageMeter").timerSize end,
                set = function(value) return S.Set("damageMeter", "timerSize", value) end },
        },
    }
    return movers
end
function M:RegisterMovers()
    local list = Movers()
    for i = 1, D.MAX do S.RegisterOwnedMover(self.id, list[i].elementID, list[i]) end
    S.RegisterOwnedMover(self.id, "timer", list.timer)
end

-- Sample data while the options page is open (out of combat only); combat
-- start or on=false restores live data.
function S.DamageMeterPreview(on)
    on = on == true
    if on and (not M.active or M.inCombat or NS.IsCombatLocked()) then return false end
    if (M.preview == true) == on then return true end
    M.preview = on
    D.InvalidateTargets()
    if not M.active then return true end
    for i = 1, D.MAX do
        local win = D.windows[i]
        if win then
            D.CloseBreakdown(win, true)
            win.offset, win.timerSecond = 0, false
        end
    end
    D.HideTip()
    D.EvaluateVisibility()
    D.MarkAll()
    D.PaintDirty()
    return true
end

function S.ToggleDamageMeterViews()
    if not M.active then return false end
    M.sessionHidden = not M.sessionHidden
    D.EvaluateVisibility()
    D.UpdateTimer()
    D.MarkAll()
    D.RequestPaint()
    SyncHistoryVisibility()
    return true
end

S.Install("damageMeter", M)
