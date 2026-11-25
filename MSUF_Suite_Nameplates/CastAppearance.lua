local _, private = ...
local NS = private.NS
local Public, Finite = NS.Public, NS.Finite
local CastAppearance = {}
private.CastAppearance = CastAppearance

local ART = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Castbars\\"
local SHAKE_TIMES = { .05, .10, .05 }
local SHAKE_OFFSETS = { .5, -1, .5 }
local states = setmetatable({}, { __mode = "k" })
-- Fit marker, never a client value, for a cast dimension the client withheld:
-- the paint that left it is complete while the dimension stays unreadable.
local UNREADABLE = {}

local function Writable(region)
    if not NS.Public(region) or not region or NS.Safety.IsForbidden(region) then return false end
    local canAccess = region.CanBeAccessedInContext
    if not canAccess then return true end
    local allowed = canAccess(region)
    return Public(allowed) and allowed == true
end

local function Mutable(cast)
    if not Writable(cast) then return false end
    if not NS.InCombat() then return true end
    local protected = cast:IsProtected()
    return NS.Public(protected) and protected == false
end
CastAppearance.Accessible, CastAppearance.Mutable = Writable, Mutable

-- Hiding by alpha leaves the native shown state under Blizzard's control.
local function SetHidden(state, key, region, hidden, reset)
    local alpha = state[key]
    if not hidden and alpha == nil then return true end
    if not Writable(region) then return false end
    if hidden then
        if alpha == nil then
            alpha = region:GetAlpha()
            if not NS.Finite(alpha) then return false end
            region:SetAlpha(0)
            state[key] = alpha
        elseif reset then
            region:SetAlpha(0)
        end
    else
        region:SetAlpha(alpha)
        state[key] = nil
    end
    return true
end

-- The cast width a name panel under the bar has to span. false: the style or
-- the native layout has none. nil: a restricted value leaves the answer open.
-- UNREADABLE: the cast width is the only input the client withheld.
local function NamePanelWidth(cast, settings, text)
    if settings.artworkNamePanel == false then return false end
    local inside = NamePlateSetupOptions.spellNameInsideCastBar
    if not NS.Public(inside) then return end
    if inside then return false end
    local classic = cast.classicStyleCastBar
    if not NS.Public(classic) then return end
    if classic == true then return false end
    if not Writable(text) then return end
    local shown = text:IsShown()
    if not NS.Public(shown) then return end
    if shown ~= true then return false end
    local width = cast:GetWidth()
    if NS.Finite(width) then return width end
    return UNREADABLE
end

local function PaintArtwork(cast, state, settings)
    local art, enabled = state.art, settings and settings.artwork == true
    -- The cast width this paint is complete for, false when it used none.
    -- The size observer repeats a paint that left it open.
    state.artFit = nil
    if not enabled then
        if art then
            art.border:Hide()
            art.name:Hide()
        end
        return
    end
    if not art then
        art = { border = cast:CreateTexture(nil, "ARTWORK", nil, 4), name = cast:CreateTexture(nil, "BACKGROUND", nil, 1) }
        art.border:SetTexture(ART .. "CastFrame.tga")
        art.border:SetAllPoints(cast)
        art.name:SetTexture(ART .. "CastName.tga")
        -- Without a width until the first visible paint.
        art.name:Hide()
        state.art = art
    end
    art.border:SetShown(settings.slanted ~= true)
    -- A border alone follows the cast by its anchors and uses no dimension.
    if settings.artworkNamePanel == false then
        art.name:Hide()
        state.artFit = false
        return
    end
    -- The panel's width is cast geometry. A cast that is not known to be
    -- visible has none read: the fit stays open for the sample of its OnShow.
    if state.seen ~= true and not state.prepaint then return end
    local text = cast.Text
    local width = NamePanelWidth(cast, settings, text)
    local showName = width ~= UNREADABLE and width and width > 0
    if showName then
        if art.text ~= text then
            art.name:ClearAllPoints()
            art.name:SetPoint("TOP", text, "TOP", 0, 2)
            art.name:SetPoint("BOTTOM", text, "BOTTOM", 0, -2)
            art.text = text
        end
        if art.width ~= width then
            art.name:SetWidth(width)
            art.width = width
        end
    end
    art.name:SetShown(showName == true)
    state.artFit = width
end

local function SetDirection(cast, state, desired)
    local original = state.originalReverse
    if desired == nil and original == nil then return true end
    local current = cast:GetReverseFill()
    if not NS.Public(current) then return false end
    if desired == nil then
        desired, state.originalReverse = original, nil
    elseif original == nil then
        state.originalReverse = current
    end
    if desired ~= current then cast:SetReverseFill(desired) end
    return true
end

-- A substitute that could not be hidden leaves the spark paint open.
local function HideSpark(state)
    local spark = state.spark
    if not spark then return end
    if Writable(spark) then spark:Hide() else state.sparkDenied = true end
end

-- false with state.sparkOwed: Blizzard's spark is accessible and only its
-- current height is undisclosed, so the write waits for a readable height.
-- A plain false is an access denial. The original height stays recorded.
--
-- edge: the paint follows a layout edge (Apply, Restore, OnLayout). Blizzard
-- sizes its spark in its layout alone (ApplyFrameOptions and UpdateAnchors),
-- so only an edge reads the spark's height and binds it: nativeSparkHeight is
-- Blizzard's height, appliedSparkHeight the one of this file while it stands,
-- both public numbers. A height this file did not write is Blizzard's or
-- another owner's: it becomes the baseline and is never written over on the
-- way back. keep: the style sizes this spark although this paint does not
-- (Empower), so the baseline stays bound.
--
-- Between two edges a bound spark (state.sparkBound) switches between the two
-- recorded heights without a read, and an owed height stays owed to the next
-- edge. Only a paint whose edge was denied the spark, or never reached it,
-- reads once more: the verified sample that edge owed.
local function SetNativeSparkHeight(native, state, height, edge, keep)
    local base, applied = state.nativeSparkHeight, state.appliedSparkHeight
    if not (height or keep or base) then return true end
    if not edge then
        if state.sparkOwed then return false end
        if height == applied then return true end
    end
    if not Writable(native) then
        if edge then state.sparkBound = nil end
        return false
    end
    local current = applied or base
    if edge or not state.sparkBound then
        current = native:GetHeight()
        if not Finite(current) then
            state.sparkOwed, state.sparkBound = true, nil
            return false
        end
        if current ~= applied then base = current end
    end
    local target = height or base
    if target ~= current then native:SetHeight(target) end
    local bound = (height or keep) and true or nil
    state.nativeSparkHeight, state.appliedSparkHeight, state.sparkBound = bound and base, height, bound
    return true
end

-- Sample a visible cast's settled layout. A hidden bar marks the sample
-- stale and waits for its first show. A protected bar can prepare before
-- combat. Unreadable geometry keeps the native height until a writable edge.
local function Measure(cast, state)
    state.stale = nil
    if not state.sizing then
        state.castHeight, state.sparkSize, state.heightOwed = nil, nil, nil
        return
    end
    local height = cast:GetHeight()
    if Finite(height) and height > 0 then
        state.castHeight, state.heightOwed = height, nil
        state.sparkSize = state.settings.sparkOverflow ~= false and math.max(4, height * 2.1) or height
    else
        state.castHeight, state.sparkSize, state.heightOwed = nil, nil, true
    end
end

local function UseNativeSpark(state, native, hidden, height, reset, edge, keep)
    HideSpark(state)
    local sized = SetNativeSparkHeight(native, state, height, edge, keep)
    if SetHidden(state, "sparkAlpha", native, hidden, reset) then return sized end
    -- More than the height is open: the next cast event repeats the paint.
    state.sparkOwed = nil
    return false
end

-- SUBSTITUTE, STILL TO BE REPLACED: the only spark of this file that is not
-- Blizzard's region. It is drawn for a reversed fill alone. Blizzard's
-- OnUpdate re-anchors its own spark every frame at value / maxValue of the
-- width from the cast's LEFT, whatever the fill direction, so no event of
-- this file can hold it on the reversed edge. Normal direction and Empower
-- always draw Blizzard's spark. It is anchored to the fill's LEFT, so the
-- engine moves it, and its size is the one of the last layout edge: no cast
-- event and no frame polls for it.
local function PlaceSpark(cast, state, fill, size)
    local spark = state.spark
    if not spark then
        spark = cast:CreateTexture(nil, "OVERLAY", nil, 6)
        spark:Hide()
        spark:SetTexture(4417031)
        spark:SetTexCoord(0.222168, 0.232422, 0.294434, 0.317383)
        spark:SetDesaturated(true)
        spark:SetBlendMode("ADD")
        state.spark = spark
    end
    if state.sparkFill ~= fill then
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", fill, "LEFT", 0, 0)
        state.sparkFill = fill
    end
    if state.sparkHeight ~= size then
        spark:SetSize(16, size)
        state.sparkHeight = size
    end
end

-- The second result is the fit of a complete paint: true for a spark at the
-- height of the last layout edge, false for one that uses no dimension.
-- Nothing here reads the cast's geometry: the size is state.sparkSize (Measure).
local function DrawSpark(cast, state, reset, edge)
    local settings = state.settings
    local native = cast.Spark
    if not settings then return UseNativeSpark(state, native, false, nil, nil, edge) end
    local empowered = cast.reverseChanneling
    if not Public(empowered) then return false end
    local reversed
    if empowered ~= true then reversed = settings.reverseFill end
    if not SetDirection(cast, state, reversed) then return false end
    if state.sizing and state.seen ~= true and not state.prepaintSpark then
        HideSpark(state)
        return true, false
    end
    local size = state.sparkSize
    -- The height Blizzard's spark has in this style's regular casts. Empower
    -- returns it to Blizzard's and keeps the baseline for the cast after it.
    local sized = settings.showSpark == true
    local nativeSize = sized and settings.reverseFill ~= true and size or nil
    if empowered == true then return UseNativeSpark(state, native, false, nil, nil, edge, nativeSize), false end
    if settings.showSpark == false then return UseNativeSpark(state, native, true, nil, reset, edge), false end
    -- Blizzard already tracks the correct edge in normal fill direction. Its
    -- spark keeps Blizzard's height while the cast's is unknown.
    if reversed ~= true then return UseNativeSpark(state, native, false, nativeSize, nil, edge), sized end
    if not SetNativeSparkHeight(native, state, nil, edge) then return false end
    if not Writable(native) then return false end
    local shown = native:IsShown()
    if not Public(shown) then return false end
    if not shown then
        HideSpark(state)
        return true, false
    end
    local fill = cast:GetStatusBarTexture()
    if not size or not Writable(fill) then
        -- Neither spark is drawn at an unknown height or on the wrong edge.
        -- The unknown height is complete until the next layout edge.
        HideSpark(state)
        return SetHidden(state, "sparkAlpha", native, true, reset) and not size, true
    end
    PlaceSpark(cast, state, fill, size)
    -- The substitute is only visible after the native spark is suppressed.
    if SetHidden(state, "sparkAlpha", native, true, reset) then
        state.spark:Show()
        return true, true
    end
    HideSpark(state)
    return false
end

-- state.sparkFit: the fit of the last complete paint, nil while it is open.
-- A cast event repeats an open paint, without geometry.
--
-- state.sparkOwed: an edge paint stopped at the undisclosed height of
-- Blizzard's spark and at nothing else. Only an edge looks at it again.
local function PaintSpark(cast, state, reset, edge)
    state.sparkFit, state.sparkDenied = nil, nil
    if edge then state.sparkOwed = nil end
    local done, fit = DrawSpark(cast, state, reset, edge)
    if state.sparkDenied then
        state.sparkOwed = nil
    elseif done then
        state.sparkFit = fit
    end
    return done
end

-- A paint that has to wait for the end of combat: the texture owner applies
-- the plate again then (Textures.DeferCast). No timer and no polling.
local function Owe(cast)
    local textures = private.Textures
    if textures then textures.DeferCast(cast) end
end

-- Reuse the height until a new layout, the first show or a writable retry.
local function Repaint(cast, state)
    if state.sizing and not (state.seen or state.prepaintSpark) then return end
    if not Mutable(cast) then return Owe(cast) end
    local edge = state.stale and not state.sparkPending
    if edge then Measure(cast, state) end
    PaintSpark(cast, state, true, edge)
    if edge and state.heightOwed then Owe(cast) end
end

local Reobserve, PaintInterrupt

-- Blizzard's HandleCastStart: every styled spark returns Blizzard's cursor to
-- an empowered cast, and the style to the cast after it.
local function SyncSpark(cast)
    local state = Public(cast) and states[cast]
    if not state then return end
    if state.motion then
        state.sparkFit = nil
        Repaint(cast, state)
    end
    if state.observeOwed then Reobserve(cast, state) end
end

-- Blizzard's ShowSpark and SetStatusBarTexture. A completed paint of a spark
-- without a dimension (fit of false) has no use for either and stops here.
-- An open, owed or denied one has no such fit and keeps every repeat.
local function OnNativeSparkChanged(cast)
    local state = Public(cast) and states[cast]
    if not state or not state.motion then return end
    if state.sparkFit == false and not state.sizing then return end
    state.sparkFit = nil
    Repaint(cast, state)
    if state.observeOwed then Reobserve(cast, state) end
end

local function OnNativeSparkHidden(cast)
    local state = Public(cast) and states[cast]
    if not state or not state.motion then return end
    if state.sparkFit == false and not state.sizing then return end
    HideSpark(state)
    if state.sparkDenied then
        state.sparkFit = nil
        Owe(cast)
    end
end

-- Whether the style draws the optional name panel under the bar: the one
-- piece of artwork with a dimension, and so the only one with a visibility
-- state and a width observer. The border alone has neither.
local function HasNamePanel(settings)
    return settings and settings.artwork and settings.artworkNamePanel ~= false
end

local function SyncArtwork(cast)
    local state = NS.Public(cast) and states[cast]
    local settings = state and state.settings
    if not HasNamePanel(settings) then return end
    state.artFit = nil
    if state.seen ~= true then return end
    if Mutable(cast) then PaintArtwork(cast, state, settings) end
    if state.observeOwed then Reobserve(cast, state) end
end

-- The width observer of the artwork. The native castbar never carries a size
-- script of this file: a child of this file covers the cast, so its size is
-- the cast's, and its OnSizeChanged is set only while the cast is effectively
-- visible. A cast without a live cast, or on a hidden plate, runs no Lua on a
-- resize and has no width read. The child is created with the first visible
-- frame of a style with the name panel, or by the Apply of a protected cast.
local owners = setmetatable({}, { __mode = "k" })

-- The size callback serves the artwork's name panel alone: its width is the
-- cast's, which is anchor-derived and moves with the plate. The spark has no
-- part in it: a style without that panel has no observer, and with one the
-- callback reads, compares and writes nothing of the spark or the cast height.
--
-- A fit of false is complete without a width, and a callback whose public
-- width equals the fit needs no write, and so no access check. The callback's
-- dimensions only decide whether to look, and only as a public pair: every
-- write follows the cast's current width, read once. A width the client
-- withholds gets one complete paint, which leaves UNREADABLE, and then only
-- that read until it is public again. A denied callback without two public
-- dimensions opens the fit for the next one.
local function OnObservedSize(child, width, height)
    local cast = owners[child]
    local state = cast and states[cast]
    -- An already queued callback must also respect a release or detach.
    if not state or not state.observing then return end
    local artFit = state.artFit
    if artFit == false then return end
    local hinted = Finite(width) and Finite(height)
    if hinted and artFit == width then return end
    if not Mutable(cast) then
        -- A public width that differs keeps its stale fit for the next callback.
        if not hinted then state.artFit = nil end
        return
    end
    -- An open fit, and a panel that was collapsed, take a complete paint.
    if artFit == nil or hinted and artFit ~= UNREADABLE and artFit <= 0 then
        return PaintArtwork(cast, state, state.settings)
    end
    width = cast:GetWidth()
    local current = Finite(width)
    if current ~= (artFit ~= UNREADABLE) then
        return PaintArtwork(cast, state, state.settings)
    end
    if not current or width == artFit and not hinted then return end
    if artFit <= 0 or width <= 0 then
        if width ~= artFit then return PaintArtwork(cast, state, state.settings) end
        return
    end
    -- Resolving the width can deliver another size callback first.
    local art = state.art
    if art.width ~= width then
        art.name:SetWidth(width)
        art.width = width
    end
    state.artFit = width
end

-- Settles state.seen: the client's public answer, else the event delivered
-- (Blizzard's SetShown can carry a secret, and a denied cast is not asked).
-- Without an event an unanswered cast counts as hidden until its OnShow.
local function Settle(cast, state, event)
    if Writable(cast) then
        local visible = cast:IsVisible()
        if Public(visible) then event = visible == true end
    end
    state.seen = event
end

-- Writes to the child only, and only while the client lets this file write
-- it: a script that has to stay is inert through state.observing. Also drops
-- an observer that was still owed.
local function Unobserve(state)
    state.observeOwed, state.observing = nil, nil
    local child = state.scripted and state.observer
    if child and Writable(child) then
        state.scripted = nil
        child:SetScript("OnSizeChanged", nil)
    end
end

-- The child of a mutable cast, without a script. Recorded before the anchor.
local function Prepare(cast, state)
    local child = CreateFrame("Frame", nil, cast)
    owners[child], state.observer = cast, child
    child:SetAllPoints(cast)
    return child
end

-- Brings the size script in line with the style and the cast's visibility.
-- true: this call attached it, and sizes that moved unobserved need a sample.
-- A new child needs a mutable castbar, its script a writable child. A denial
-- leaves state.observeOwed for the next visible cast start, native change, OnShow or Apply.
local function Observe(cast, state)
    if not HasNamePanel(state.settings) or state.seen ~= true then
        return Unobserve(state)
    end
    if state.observing then return end
    local child = state.observer
    if not child then
        if not Mutable(cast) then
            state.observeOwed = true
            return
        end
        child = Prepare(cast, state)
    end
    if state.scripted then
        state.observing, state.observeOwed = true, nil
        return true
    end
    if not Writable(child) then
        state.observeOwed = true
        return
    end
    state.scripted, state.observing, state.observeOwed = true, true, nil
    child:SetScript("OnSizeChanged", OnObservedSize)
    return true
end

Reobserve = function(cast, state)
    if Observe(cast, state) then OnObservedSize(state.observer) end
end

local function OnCastShown(cast)
    local state = Public(cast) and states[cast]
    if not state or not state.settings then return end
    local panel = HasNamePanel(state.settings)
    if not (panel or state.sizing or state.interrupt) then return end
    Settle(cast, state, true)
    if not state.seen then return end
    if state.interruptPending and (not Mutable(cast) or not PaintInterrupt(cast, state)) then Owe(cast) end
    if panel then Reobserve(cast, state) end
    if state.sizing and (state.stale or state.sparkFit ~= true) then Repaint(cast, state) end
end

local function OnCastHidden(cast)
    local state = Public(cast) and states[cast]
    if not state or not (state.sizing or state.interrupt or HasNamePanel(state.settings)) then return end
    Settle(cast, state, false)
    if state.observing or state.observeOwed then Observe(cast, state) end
end

local function HookVisibility(cast, state)
    if not state.visibilityHooked then
        state.visibilityHooked = true
        cast:HookScript("OnShow", OnCastShown)
        cast:HookScript("OnHide", OnCastHidden)
    end
    if state.seen == nil then Settle(cast, state, false) end
end

-- The repeats of a spark paint: the native changes of Blizzard's spark and
-- the fill region, and the cast start. None of them reads geometry. Every
-- styled spark keeps them for the cast's lifetime, so a paint denied at one
-- is repaired by the next, or by the end of combat (Owe). A completed spark
-- without a dimension leaves all but the cast start at their state gate. The
-- cast is accessible.
local function HookSpark(cast, state)
    if not state.motionHooked then
        state.motionHooked = true
        hooksecurefunc(cast, "ShowSpark", OnNativeSparkChanged)
        hooksecurefunc(cast, "HideSpark", OnNativeSparkHidden)
        hooksecurefunc(cast, "SetStatusBarTexture", OnNativeSparkChanged)
        -- Every styled spark returns Blizzard's cursor to an empowered cast.
        hooksecurefunc(cast, "HandleCastStart", SyncSpark)
    end
end

local function SetInterruptHold(cast, state)
    local setting = state.settings and state.settings.interruptDuration
    if not setting and not state.originalHold then return true end
    local empowered = cast.reverseChanneling
    if not NS.Public(empowered) then return false end
    -- An early empower release uses the same HoldFadeOutAnim. Keep its native timing.
    local holdDuration = empowered ~= true and setting or nil
    if not holdDuration and not state.originalHold then return true end
    if holdDuration and state.appliedHold == holdDuration then return true end
    local group = cast.HoldFadeOutAnim
    if not Writable(group) then return false end
    local playing = group:IsPlaying()
    if not NS.Public(playing) then return false end
    if playing then return true end
    local hold, fade = group:GetAnimations()
    if not Writable(hold) or not Writable(fade) then return false end
    local order = hold:GetOrder()
    if NS.Public(order) and order == 2 then hold = fade end
    order = hold:GetOrder()
    local current = hold:GetDuration()
    if not NS.Public(order) or order ~= 1 or not NS.Finite(current) then return false end
    if holdDuration then
        if not state.originalHold then state.originalHold = current end
        state.appliedHold = holdDuration
    else
        holdDuration = state.originalHold
        state.originalHold, state.appliedHold = nil, nil
    end
    if current ~= holdDuration then hold:SetDuration(holdDuration) end
    return true
end

local function StopShake(state)
    if state.shaking then
        state.shaking = nil
        state.shake.group:Stop()
    end
end

local function RunShake(cast, target, feedback)
    local state = NS.Public(cast) and states[cast]
    local settings = state and state.settings
    if not settings or settings.interruptShake ~= true or not feedback and state.feedbackActive then return end
    if not Mutable(cast) or not Mutable(target) then return end
    local shown = target:IsShown()
    if not NS.Public(shown) or shown ~= true then return end
    local strength = settings.shakeStrength or 8
    if strength <= 0 then return end
    local key = feedback and "feedbackShake" or "nativeShake"
    local shake = state[key]
    if not shake or shake.target ~= target then
        StopShake(state)
        local group = target:CreateAnimationGroup()
        shake = { group = group, target = target }
        for i = 1, #SHAKE_TIMES do
            local move = group:CreateAnimation("Translation")
            move:SetOrder(i)
            move:SetDuration(SHAKE_TIMES[i])
            shake[i] = move
        end
        state[key] = shake
    end
    StopShake(state)
    state.shake = shake
    if shake.strength ~= strength then
        for i = 1, #SHAKE_OFFSETS do shake[i]:SetOffset(strength * SHAKE_OFFSETS[i], 0) end
        shake.strength = strength
    end
    state.shaking = true
    shake.group:Play()
end

local function PlayShake(cast) RunShake(cast, cast, false) end
function CastAppearance.ShakeFeedback(cast, target)
    local state = Public(cast) and states[cast]
    if state then state.feedbackActive = true RunShake(cast, target, true) end
end
function CastAppearance.StopFeedback(cast)
    local state = Public(cast) and states[cast]
    if state then
        state.feedbackActive = nil
        if state.shake == state.feedbackShake then StopShake(state) end
    end
end

local function InterruptStopped(cast)
    local state = NS.Public(cast) and states[cast]
    if not state or not (state.originalHold or state.shaking or state.interrupt and (state.seen or not state.interruptPending)) then return end
    if not Mutable(cast) then return end
    if not state.feedbackActive then StopShake(state) end
    SetInterruptHold(cast, state)
end

local function HoldFinished(group)
    if Writable(group) then InterruptStopped(group:GetParent()) end
end

PaintInterrupt = function(cast, state)
    local settings = state.settings
    if settings and settings.interruptDuration ~= nil and not state.holdHooked then
        local group = cast.HoldFadeOutAnim
        if not Writable(group) then return false end
        group:HookScript("OnFinished", HoldFinished)
        state.holdHooked = true
    end
    if settings and (state.interrupt or settings.interruptShake == true) and not state.interruptHooked then
        hooksecurefunc(cast, "PlayInterruptAnims", PlayShake)
        hooksecurefunc(cast, "StopInterruptAnims", InterruptStopped)
        state.interruptHooked = true
    end
    if not settings or settings.interruptShake ~= true or settings.shakeStrength == 0 then StopShake(state) end
    if not SetInterruptHold(cast, state) then return false end
    state.interruptPending = nil
    return true
end

function CastAppearance.Apply(cast, settings, reset, deferSpark)
    if not settings then return CastAppearance.Restore(cast) end
    local state = NS.Public(cast) and states[cast]
    if not Mutable(cast) then
        -- The layout or profile change this Apply answers still happened: the
        -- next paint that may write takes the sample this edge owed.
        if state then state.sparkFit, state.artFit, state.stale = nil, nil, true end
        return false
    end
    if not state then
        state = {}
        states[cast] = state
    end
    state.settings, state.prepaint = settings, nil
    local show = settings.showSpark
    state.motion = show ~= nil or settings.reverseFill ~= nil
    state.sizing = show ~= false and (show == true or settings.reverseFill == true)
    local panel = HasNamePanel(settings)
    state.interrupt = settings.interruptDuration ~= nil
    state.interruptPending = state.interrupt or nil
    if panel or state.sizing or state.interrupt then HookVisibility(cast, state) else state.seen = nil end
    -- A protected cast can first show during combat. Prepare while writable.
    local preparePanel = panel and not state.observer
    local protected
    if preparePanel or state.sizing or state.interrupt then
        local value = cast:IsProtected()
        protected = not Public(value) or value ~= false
        if protected and preparePanel then state.prepaint = Prepare(cast, state) end
    end
    state.prepaintSpark = protected and state.sizing or nil
    -- Before the paints, which then use the width a first callback would bring.
    Observe(cast, state)
    if state.motion then HookSpark(cast, state) end
    if panel and not state.artHooked then
        state.artHooked = true
        hooksecurefunc(cast, "SetNameTextShown", SyncArtwork)
    end
    local outline = private.CastOutline.Paint(cast, settings, reset)
    PaintArtwork(cast, state, settings)
    local paintInterrupt = state.originalHold or state.shaking or state.interrupt and (state.seen or protected)
        or not state.interrupt and settings.interruptShake == true
    local interrupt = not paintInterrupt or PaintInterrupt(cast, state)
    -- Direction is needed immediately by the cast's other decorations. A
    -- new plate can leave sizing until Textures.Paint finishes its layout.
    state.sparkPending = (deferSpark or state.sparkPending) and state.sizing
        and not state.castHeight and not state.nativeSparkHeight or nil
    if state.sizing and not (state.seen or state.prepaintSpark) then
        state.stale = true
    elseif not state.sparkPending then
        Measure(cast, state)
    end
    if state.motion then
        local spark = PaintSpark(cast, state, reset, true)
        if state.heightOwed then Owe(cast) end
        return spark and outline and interrupt
    end
    local direction = SetDirection(cast, state, nil)
    return UseNativeSpark(state, cast.Spark, false, nil, nil, true) and direction and outline and interrupt
end

-- Layout reports a settled pass. On the first lease Textures.Paint reports
-- the end of the whole paint, including when no Suite layout writes occur.
function CastAppearance.OnLayout(cast, finishSpark)
    local state = Public(cast) and states[cast]
    if not state or not state.sizing then return end
    if (state.sparkPending == true) ~= (finishSpark == true) then return end
    state.sparkPending = nil
    if not (state.seen or state.prepaintSpark) then
        state.stale = true
        return
    end
    if not Mutable(cast) then
        state.stale = true
        Owe(cast)
        return false
    end
    local known, stale = state.castHeight, state.stale
    Measure(cast, state)
    if finishSpark or stale or state.castHeight ~= known or state.sparkFit == nil or state.sparkOwed then
        PaintSpark(cast, state, stale, true)
    end
    if state.heightOwed or state.sparkOwed or state.sparkFit == nil then
        Owe(cast)
        return false
    end
end

function CastAppearance.Restore(cast)
    if not Public(cast) then return false end
    local state = states[cast]
    if not state then return true end
    state.settings, state.motion, state.sizing, state.seen = nil, nil, nil, nil
    state.feedbackActive = nil
    state.interrupt, state.interruptPending = nil, nil
    state.sparkPending, state.prepaintSpark = nil, nil
    state.castHeight, state.sparkSize, state.heightOwed, state.stale = nil, nil, nil, nil
    -- Also when the restore itself is blocked: a released cast has no observer.
    Unobserve(state)
    if not Mutable(cast) then return false end
    local outline = private.CastOutline.Paint(cast)
    PaintArtwork(cast, state)
    local direction = SetDirection(cast, state, nil)
    local interrupt = not (state.originalHold or state.shaking) or PaintInterrupt(cast, state)
    return PaintSpark(cast, state, nil, true) and direction and outline and interrupt
end
