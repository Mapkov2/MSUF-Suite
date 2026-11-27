local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "playerAuras"
local M = {}
local cleanup, trayHooked, debuffControls
local buffFrame, debuffFrame
-- All snapshots, style generations and placements live in Suite side tables.
local saved, borders, hooked, debuffs, laid, styled = {}, {}, {}, {}, {}, {}
local looks, skinned, shifted, handles = {}, {}, {}, {}
local generation, fontPath = 0, nil
local borderRed, borderGreen, borderBlue
local buffGeometry, debuffGeometry = {}, {}
local countPoint = { "BOTTOMRIGHT", -2, 1 }
local timerPoints = { { "BOTTOMLEFT", 2, 1 }, { "CENTER", 0, 0 } }
local timerPoint
local unpack, select, floor, ceil, max, min = unpack, select, math.floor, math.ceil, math.max, math.min
local IsSecret = NS.IsSecret
local Finite = S.Finite

-- Prepare the native pool before show: buff refills keep geometry and skin; debuffs reflow active and private anchors.
local function Readable(...)
    local values = { n = select("#", ...), ... }
    for index = 1, values.n do
        if IsSecret(values[index]) then return nil end
    end
    return values
end

local BUTTON = { points = true, size = true, scale = true }
-- SetAllPoints resizes textures by default. Save their intrinsic size independently of the resolved rectangle.
local ICON = { points = true, intrinsicSize = true }
local TEXT = { points = true, alpha = true, text = true }
local DURATION = { points = true, alpha = true, text = true }
local BORDER = { size = true }
local FRAME = { points = true }
local CONTAINER = { points = true, size = true }

local function Points(region)
    local count = region:GetNumPoints()
    if not Finite(count) or count < 0 or count ~= floor(count) then return end
    local points = {}
    for index = 1, count do
        local point = Readable(region:GetPoint(index))
        if not point or point.n ~= 5 or type(point[1]) ~= "string" or type(point[3]) ~= "string"
            or not Finite(point[4]) or not Finite(point[5]) then return end
        if point[2] and NS.Safety.IsForbidden(point[2]) then return end
        points[index] = point
    end
    return points
end

local function Numbers(count, ...)
    local values = { n = select("#", ...), ... }
    if values.n ~= count then return end
    for index = 1, count do
        if not Finite(values[index]) then return end
    end
    return values
end

-- Opposite corners fill the button without changing an unreadable intrinsic size.
local function FillIconCorners(icon, button)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT")
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT")
end

local function CapturePoints(region, state, button, container)
    state.points = Points(region)
    -- The native anchor can be writeable even when its resolved offsets are secret.
    -- Keep a per-button restore plan so one unavailable slot cannot strand another.
    if not state.points and container and NS.Safety.CanAnchor(region) then
        state.points = P.PlayerAuraSkins.NativePoints(button, region, container)
        if state.points then state.nativeButton, state.nativeContainer = button, container end
    end
end

local function Snapshot(region, aspects, button, container)
    if not region or NS.Safety.IsForbidden(region) then return end
    local state = {}
    if aspects.points then
        CapturePoints(region, state, button, container)
        if not (state.points or aspects.intrinsicSize) then return end
    end
    if aspects.size or aspects.intrinsicSize then
        local intrinsic = aspects.intrinsicSize == true
        state.size = Numbers(2, region:GetWidth(intrinsic), region:GetHeight(intrinsic))
        if intrinsic then state.fill = state.size and region.SetAllPoints or FillIconCorners
        elseif not state.size then
            return
        end
    end
    if aspects.scale then
        state.scale = Numbers(1, region:GetScale())
        if not state.scale then return end
    end
    if aspects.alpha then
        state.alpha = Numbers(1, region:GetAlpha())
        if not state.alpha then return end
    end
    if aspects.text then
        state.font = Readable(region:GetFont())
        state.color = Numbers(4, region:GetTextColor())
        state.shadow = Numbers(4, region:GetShadowColor())
        state.shadowOffset = Numbers(2, region:GetShadowOffset())
        if not state.font or type(state.font[1]) ~= "string" or not Finite(state.font[2])
            or not state.color or not state.shadow or not state.shadowOffset then return end
    end
    return state
end

local function Remember(region, aspects, button, container)
    if not saved[region] then saved[region] = Snapshot(region, aspects, button, container) end
    return saved[region]
end

local function Put(region, setter, values)
    if values then region[setter](region, unpack(values, 1, values.n)) end
end

local function RestoreRegion(region, state)
    if not state then return end
    if NS.Safety.IsForbidden(region) then
        saved[region] = nil
        return
    end
    local points = state.points
    if state.nativeContainer then
        points = NS.Safety.CanAnchor(region)
            and (P.PlayerAuraSkins.NativePoints(state.nativeButton, region, state.nativeContainer) or points)
        if points and NS.Safety.IsForbidden(points[1][2]) then points = nil end
    end
    if points and not state.reanchored then
        local clear = region.ClearAllPointsBase or region.ClearAllPoints
        local set = region.SetPointBase or region.SetPoint
        clear(region)
        for _, point in ipairs(points) do set(region, unpack(point, 1, point.n)) end
    end
    Put(region, "SetSize", state.size)
    Put(region, "SetScale", state.scale)
    Put(region, "SetAlpha", state.alpha)
    Put(region, "SetTexCoord", state.coords)
    Put(region, "SetFont", state.font)
    Put(region, "SetTextColor", state.color)
    Put(region, "SetShadowColor", state.shadow)
    Put(region, "SetShadowOffset", state.shadowOffset)
    saved[region] = nil
end

local function Restore()
    for region, state in pairs(saved) do
        NS.Dispatch(RestoreRegion, region, state)
        saved[region] = nil
    end
    for _, border in pairs(borders) do NS.Dispatch(border.Hide, border) end
    for button in pairs(skinned) do
        NS.Dispatch(NS.HostBridge.PaintIconSkin, button, nil)
        NS.Dispatch(P.PlayerAuraSkins.SetLayers, button, false)
        skinned[button] = nil
    end
    for frame in pairs(shifted) do shifted[frame] = nil end
end

local function Invalidate()
    generation = generation + 1
    for _, list in pairs(laid) do
        list.n, list.anchored, list.framed, list.attempts = -1, false, false, nil
    end
end

-- Protected writes resume after combat.
local function Refused(region, list)
    local protected = region:IsProtected()
    if not (IsSecret(protected) or protected) then return false end
    S.Queue("playerAuras")
    list.n = -1
    return true
end

local function Border(button, icon, c)
    local border = borders[button]
    if not border then
        border = S.CreateFrame("Frame", nil, button)
        border:EnableMouse(false)
        border.edges = {}
        for index = 1, 4 do border.edges[index] = S.CreateTexture(border, nil, "OVERLAY") end
        borders[button] = border
    end
    border:SetAllPoints(icon)
    local level = button:GetFrameLevel()
    if Finite(level) then border:SetFrameLevel(level + 1) end
    S.PlaceEdges(border.edges, border, c.borderSize, borderRed, borderGreen, borderBlue, 1)
    border:SetShown(c.borderSize > 0)
end

local function Font(region, size)
    if not saved[region] then return end
    region:SetFont(fontPath, size, "OUTLINE")
    region:SetTextColor(1, 1, 1, 1)
    region:SetShadowColor(0, 0, 0, 1)
    region:SetShadowOffset(1, -1)
end

local function Pin(region, button, anchor, container)
    if not (region and region.SetFont) then return end
    if not saved[region] then
        if not Remember(region, container and DURATION or TEXT, button, container) then return end
        styled[button] = nil
    end
    region:ClearAllPoints()
    region:SetPoint(anchor[1], button, anchor[1], anchor[2], anchor[3])
end

local function NativeBorder(region, geometry)
    if not region then return end
    if not Remember(region, BORDER) then return end
    region:SetSize(geometry.width + 2, geometry.height + 2)
end

local function Style(button, icon, geometry)
    local c = M.config
    if icon.SetTexCoord then
        -- ConsolidatedBuffs uses a sub-rectangle of an atlas, not an aura icon.
        if not (buffFrame and button == buffFrame.ConsolidatedBuffs) then
            local original = saved[icon]
            original.coords = original.coords or Numbers(8, icon:GetTexCoord())
            if original.coords then icon:SetTexCoord(geometry.left, geometry.right, geometry.top, geometry.bottom) end
        end
        Border(button, icon, c)
    end
    NativeBorder(button.DebuffBorder, geometry)
    NativeBorder(button.TempEnchantBorder, geometry)
    Pin(button.Count, button, countPoint)
    Font(button.Count, c.fontSize)
    Font(button.Duration, geometry.timerTextSize)
    if saved[button.Duration] then button.Duration:SetAlpha(c.showDuration and 1 or 0) end
    styled[button] = generation
end

local style = Style
local function StyleSkinned(button, icon, geometry)
    Style(button, icon, geometry)
    local border = borders[button]
    if border and P.PlayerAuraSkins.PaintLook(skinned, button, icon, looks[button:GetParent()], geometry.width, geometry.height) then
        border:Hide()
    end
end

local function Place(button, icon, slot, container, geometry, auraAnchor)
    if not saved[button] or (not auraAnchor and not saved[icon]) then
        if not icon then return end
        local original = saved[button] or Snapshot(button, BUTTON)
        if not original or (not auraAnchor and not Remember(icon, ICON, button, container)) then return end
        saved[button] = original
    end
    local col, row = (slot - 1) % geometry.perRow, floor((slot - 1) / geometry.perRow)
    button:SetScale(1)
    button:SetSize(geometry.width, geometry.height)
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", container, "TOPRIGHT", -col * geometry.stepX, -row * geometry.stepY)
    -- Keep the native IconInfo for private auras.
    if auraAnchor then return true end
    local artwork = saved[icon]
    if not artwork.points and artwork.checked ~= generation then
        CapturePoints(icon, artwork, button, container)
        artwork.checked = generation
        if not artwork.size then
            artwork.size = Numbers(2, icon:GetWidth(true), icon:GetHeight(true))
            artwork.fill = artwork.size and icon.SetAllPoints or FillIconCorners
        end
    end
    if artwork.points then
        icon:ClearAllPoints()
        artwork.fill(icon, button)
    elseif artwork.size then
        -- When we cannot restore the anchor, only override a size we can restore.
        icon:SetSize(geometry.width, geometry.height)
    end
    Pin(button.Duration, button, timerPoint, container)
    if styled[button] ~= generation then style(button, icon, geometry) end
    return true
end

-- Track actual point writes: a frame or grid callback can finish before Blizzard replaces the Suite position.
local function PointWritten(region)
    local original = saved[region]
    if original then original.reanchored = true end
    local list = laid[region]
    if list then list.framed, list.anchored = false, false end
end

local function SaveNativePoints(region)
    local original = saved[region]
    if not (original and original.reanchored) then return true end
    local points = Points(region)
    if points then original.points, original.reanchored = points, nil end
    return points
end
local function AnchorRegions(frame, x, y, moveArrow)
    local container, arrow = frame.AuraContainer, frame.CollapseAndExpandButton
    if arrow and moveArrow then
        if not Remember(arrow, FRAME) or not SaveNativePoints(arrow) then return end
        arrow:ClearAllPoints()
        arrow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, y)
        saved[arrow].reanchored = nil
    end
    container:ClearAllPoints()
    if arrow then
        container:SetPoint("TOPRIGHT", arrow, "TOPLEFT", 0, 0)
    else
        container:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, y)
    end
    saved[container].reanchored = nil
    return true
end

-- Own the public row position independently of individual aura geometry and skins.
local function SeatFrame(frame, list)
    if not Remember(frame, FRAME) or not SaveNativePoints(frame) then return end
    local debuff, c = debuffs[frame], M.config
    local clear = frame.ClearAllPointsBase or frame.ClearAllPoints
    local set = frame.SetPointBase or frame.SetPoint
    clear(frame)
    set(frame, "TOPRIGHT", Minimap, "TOPLEFT", debuff and c.x + c.debuffX or c.x, debuff and c.y - c.debuffOffset or c.y)
    saved[frame].reanchored, list.framed, list.captureContainer = nil, true, true
    return true
end

local function Anchor(frame, list, rows, geometry)
    local container = frame.AuraContainer
    local original = saved[container] or Remember(container, CONTAINER)
    if not original then return end
    local cache = container.currentGridLayoutInfo
    if list.captureContainer or cache and (list.nativeLayout ~= cache.layout or list.nativeAnchor ~= cache.anchor) then
        if not SaveNativePoints(container) then return end
        if cache then list.nativeLayout, list.nativeAnchor = cache.layout, cache.anchor end
        list.captureContainer = nil
    end
    local shift = shifted[frame]
    local x, y = shift and shift[1] or 0, shift and shift[2] or 0
    if not AnchorRegions(frame, x, y, not list.anchored) then return end
    container:SetSize(geometry.fullWidth, geometry.height + (rows - 1) * geometry.stepY)
    list.anchored = true
    return true
end

local function RestoreButton(button)
    RestoreRegion(button, saved[button])
    RestoreRegion(button.Icon, saved[button.Icon])
    RestoreRegion(button.Count, saved[button.Count])
    RestoreRegion(button.Duration, saved[button.Duration])
    RestoreRegion(button.DebuffBorder, saved[button.DebuffBorder])
    RestoreRegion(button.TempEnchantBorder, saved[button.TempEnchantBorder])
    if borders[button] then borders[button]:Hide() end
    if skinned[button] then
        NS.HostBridge.PaintIconSkin(button, nil)
        P.PlayerAuraSkins.SetLayers(button, false)
    end
    skinned[button], styled[button] = nil, nil
end

-- Prepaint under Blizzard geometry ownership so ordinary native refills retain the Suite look.
local function PaintNativeSkins(frame)
    local look = looks[frame]
    if look then P.PlayerAuraSkins.PaintNativeRow(frame, look, skinned) end
end

local function RestoreNative(frame, list)
    RestoreRegion(frame.CollapseAndExpandButton, saved[frame.CollapseAndExpandButton])
    local container, collect = frame.AuraContainer, frame.ConsolidatedBuffs
    RestoreRegion(container, saved[container])
    if collect then RestoreButton(collect) end
    for _, button in ipairs(frame.auraFrames) do RestoreButton(button) end
    shifted[frame] = nil
    list.n, list.anchored = -1, false
end

local function RollBack(frame, list)
    if list.attempts == 2 then return end
    list.restoring, list.attempts = true, (list.attempts or 0) + 1
    local restored = list.rollback == "grid" or NS.Dispatch(NS.Finish, RestoreNative, frame, list)
    -- A skipped grid leaves the per-region restoration in place. Retry a grid that raised.
    local solved = restored and NS.Dispatch(NS.Finish, P.PlayerAuraSkins.RestoreGrid, frame)
    NS.Dispatch(PaintNativeSkins, frame)
    list.restoring, list.rollback = nil, nil
    if not solved then list.rollback = restored and "grid" or true end
    return solved
end

local function FallBack(frame, list, failed, locked)
    list.failed, list.attempts = failed, nil
    if locked then
        list.rollback = true
        S.Queue(ID)
        return
    end
    RollBack(frame, list)
end

-- Check unused slots only after geometry fails. Hidden malformed buttons stay native until a usable refill.
local function Unused(frame, button)
    if button == frame then return false end
    local private = button.isAuraAnchor
    if IsSecret(private) or private then return false end
    local valid, example = button.hasValidInfo, button.isExample
    if not IsSecret(valid) and valid ~= nil and not IsSecret(example) then return not (valid or example) end
    if NS.Safety.IsForbidden(button) then return false end
    local shown = button:IsShown()
    return not IsSecret(shown) and not shown
end

local function CanRetry(frame, failed)
    if failed == frame then
        local arrow = frame.CollapseAndExpandButton
        return Snapshot(frame, FRAME) and Snapshot(frame.AuraContainer, CONTAINER) and (not arrow or Snapshot(arrow, FRAME))
    end
    if failed ~= frame.ConsolidatedBuffs then
        local present = false
        for _, button in ipairs(frame.auraFrames) do
            if button == failed then present = true break end
        end
        if not present then return true end
    end
    return failed.Icon and Snapshot(failed, BUTTON) and (failed.isAuraAnchor or Snapshot(failed.Icon, ICON))
end

-- FrameXML fills buttons in order. For row extent, sample buff row starts and reserve room at unreadable boundaries.
local function Filled(buttons, ordinary, offset, step)
    for index = ordinary - (ordinary + offset - 1) % step, 1, -step do
        local button = buttons[index]
        local valid, example = button.hasValidInfo, button.isExample
        if IsSecret(valid) or valid or IsSecret(example) or example then return index end
    end
    return 0
end

local function Bounds(frame, list, ordinary, private, offset)
    if private > 0 then
        -- Before UpdateSize reports the exact native count including private anchors, use the pool.
        local enabled = list.enabled
        if enabled and enabled >= private and enabled <= ordinary + private then return enabled - private end
        return Filled(frame.auraFrames, ordinary, 0, 1)
    end
    return Filled(frame.auraFrames, ordinary, offset, M.config.perRow)
end

local function Offset(collect, list)
    if not collect then return 0 end
    if list.nativeOffset ~= nil then return list.nativeOffset end
    local shown = collect:IsShown()
    if not IsSecret(shown) then return shown and 1 or 0 end
    local enabled = collect:IsEnabled()
    return list.offset or ((IsSecret(enabled) or enabled) and 1 or 0)
end

local function SamePool(buttons, list)
    for index = 1, #buttons do
        if buttons[index] ~= list[index] then return false end
    end
    return true
end

local function Sync(frame)
    if not (M.active and frame and frame.AuraContainer and frame.auraFrames) then return end
    local list = laid[frame]
    if not list then
        list = { n = -1, geometry = debuffs[frame] and debuffGeometry or buffGeometry }
        laid[frame] = list
    end
    if list.restoring then return end
    if not list.framed then
        local locked = NS.IsCombatLocked()
        if locked and Refused(frame, list) then return end
        if not SeatFrame(frame, list) then
            if list.failed ~= frame then FallBack(frame, list, frame, locked) end
            return
        end
    end
    if list.failed then
        if Unused(frame, list.failed) then list.n, list.rollback = -1, nil
        else
            if NS.IsCombatLocked() or (list.rollback and not RollBack(frame, list)) then return end
            if not CanRetry(frame, list.failed) then return end
        end
        list.failed = nil
    end
    if list.restyle then
        generation, list.n, list.restyle = generation + 1, -1, false
        list.anchored, list.framed = false, false
    end
    local buttons, collect = frame.auraFrames, frame.ConsolidatedBuffs
    local offset = Offset(collect, list)
    local private = frame.PrivateAuraAnchors and #frame.PrivateAuraAnchors or 0
    local ordinary = #buttons - private
    local filled = Bounds(frame, list, ordinary, private, offset)
    local reset = list.reset and (frame.doNotAnchorDisabledFrames and private > 0 and filled or ordinary) or -1
    local valid, locked = list.n, nil
    if list.offset ~= offset then valid = -1 end
    if valid == #buttons and list.anchored and not list.reset and list.filled == filled
        and list[0] == collect and SamePool(buttons, list) then return end
    local geometry = list.geometry
    for index = collect and 0 or 1, #buttons do
        local button = index == 0 and collect or buttons[index]
        local anchor = index > ordinary
        if index > valid or index <= reset or list[index] ~= button or (anchor and (list.reset or list.filled ~= filled)) then
            if locked == nil then
                locked = NS.IsCombatLocked()
                if locked and Refused(frame, list) then return end
            end
            if locked and Refused(button, list) then return end
            local slot = index == 0 and 1 or index + offset
            if anchor then slot = filled + index - ordinary end
            if Place(button, button.Icon, slot, frame.AuraContainer, geometry, anchor) then list[index] = button
            elseif Unused(frame, button) then
                list[index] = nil
            else
                FallBack(frame, list, button, locked)
                return
            end
        end
    end
    list.n, list.reset, list.filled, list.offset = #buttons, false, filled, offset
    local rows = max(1, ceil((filled + offset + private) / geometry.perRow))
    if list.rows == rows and list.anchored then return end
    if locked == nil then
        locked = NS.IsCombatLocked()
        if locked and Refused(frame, list) then return end
    end
    if locked and not list.anchored and frame.CollapseAndExpandButton and Refused(frame.CollapseAndExpandButton, list) then return end
    if Anchor(frame, list, rows, geometry) then list.rows = rows
    else
        FallBack(frame, list, frame, locked)
    end
end

local function Relayout(frame)
    local list = laid[frame]
    if not list then return Sync(frame) end
    -- Blizzard's completed grid settles a failed proxy without a retry per refill.
    if list.rollback == "grid" then list.rollback = nil end
    list.reset, list.anchored = true, false
    Sync(frame)
end

local function Restyle(frame)
    local list = laid[frame]
    if list then list.restyle = true end
end

local function Moved(frame)
    local list = laid[frame]
    if list then
        list.anchored, list.framed = false, false
    end
    Sync(frame)
end

local function Reanchor()
    if M.active and buffFrame and buffFrame:IsInDefaultPosition() then Moved(buffFrame) end
end

local function Hook(frame, debuff)
    if not frame or hooked[frame] or not frame.UpdateGridLayout then return end
    hooked[frame] = true
    debuffs[frame] = debuff
    for _, region in ipairs({ frame, frame.AuraContainer, frame.CollapseAndExpandButton }) do
        hooksecurefunc(region, "SetPoint", PointWritten)
    end
    hooksecurefunc(frame, "UpdateGridLayout", Relayout)
    if debuff and frame.UpdateSize then
        hooksecurefunc(frame, "UpdateSize", function(_, _, _, _, _, _, _, count)
            local list = laid[frame]
            if list then list.enabled = Finite(count) and count or nil end
        end)
    elseif frame.AuraContainer.UpdateGridLayout then
        hooksecurefunc(frame.AuraContainer, "UpdateGridLayout", function(_, icons)
            local list = laid[frame]
            if list then list.nativeOffset = icons[1] == frame.ConsolidatedBuffs and 1 or 0 end
        end)
    end
    local mixin = _G.DebuffFrameMixin
    if frame.UpdateAuraButtons and not (mixin and frame.UpdateAuraButtons == mixin.UpdateAuraButtons) then
        hooksecurefunc(frame, "UpdateAuraButtons", Sync)
    end
    if frame.SetIsEditing then hooksecurefunc(frame, "SetIsEditing", Restyle) end
    if frame.ApplySystemAnchor then hooksecurefunc(frame, "ApplySystemAnchor", Moved) end
end

local function SetLook(name, choice)
    local frame = _G[name]
    if not frame then return end
    local look = NS.HostBridge.PlayerAuraSkin(choice)
    looks[frame] = look
    local container = frame.AuraContainer
    if container then looks[container] = look end
end

local function ResolveLooks()
    local c = M.config
    SetLook("BuffFrame", c.buffSkin)
    SetLook("DebuffFrame", c.debuffSkin)
    -- Release even hidden skins as soon as their row selects No skin.
    for button in pairs(skinned) do
        if not looks[button:GetParent()] then
            NS.HostBridge.PaintIconSkin(button, nil)
            skinned[button] = nil
            P.PlayerAuraSkins.SetLayers(button, false)
        end
    end
    style = next(looks) and StyleSkinned or Style
end

local function UpdateGeometry(geometry, width, height, c)
    geometry.width, geometry.height, geometry.perRow = width, height, c.perRow
    geometry.stepX, geometry.stepY = width + c.spacing, height + c.rowSpacing
    geometry.fullWidth = geometry.perRow * geometry.stepX - c.spacing
    local half = .5 - c.iconZoom / 100
    local x, y = half * min(1, width / height), half * min(1, height / width)
    geometry.left, geometry.right, geometry.top, geometry.bottom = .5 - x, .5 + x, .5 - y, .5 + y
end

local function Adopt()
    buffFrame, debuffFrame = _G.BuffFrame, _G.DebuffFrame
    local c = M.config
    fontPath = S.ResolveFont(c.font) or S.GlobalFontPath()
    timerPoint = timerPoints[c.timerAnchor] or timerPoints[1]
    borderRed, borderGreen, borderBlue = S.RGB(c.borderColor)
    UpdateGeometry(buffGeometry, c.iconWidth, c.iconHeight, c)
    UpdateGeometry(debuffGeometry, c.debuffIconWidth or c.iconWidth, c.debuffIconHeight or c.iconHeight, c)
    buffGeometry.timerTextSize = c.fontSize
    local debuffTimerSize = c.debuffTimerTextSize or 0
    debuffGeometry.timerTextSize = debuffTimerSize > 0 and debuffTimerSize or c.fontSize
    -- Any refresh, including drag commit or cancel, returns preview containers to their frames.
    for frame in pairs(shifted) do shifted[frame] = nil end
    Invalidate()
    Hook(buffFrame, false)
    Hook(debuffFrame, true)
    NS.Dispatch(Sync, buffFrame)
    NS.Dispatch(Sync, debuffFrame)
    if not trayHooked and StatusTrayManager then
        hooksecurefunc(StatusTrayManager, "UpdateTrayAndBuffFrameLayout", Reanchor)
        trayHooked = true
    end
end

local function FinishCleanup()
    if NS.IsCombatLocked() then return end
    if cleanup then cleanup:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    NS.Dispatch(Restore)
    for frame in pairs(laid) do
        laid[frame] = nil
        NS.Dispatch(P.PlayerAuraSkins.RestoreGrid, frame)
    end
    P.PlayerAuraSkins.Yield(false)
end

function M:Enable()
    if cleanup then cleanup:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    self.active = true
    -- The skin-only piece (PlayerAuraSkins.lua) lets go of the buttons first.
    P.PlayerAuraSkins.Yield(true)
    NS.HostBridge.WatchIconSkins("playerAuras", true)
    self.context:Event("PLAYER_ENTERING_WORLD", Adopt)
    self.context:Event("PLAYER_REGEN_ENABLED", Adopt)
    self.context:Event("ADDON_LOADED", function(_, _, addon)
        if addon == "Blizzard_BuffFrame" then S.Apply(ID) end
    end)
    ResolveLooks()
    Adopt()
end

function M:Refresh()
    if not self.active then return end
    ResolveLooks()
    Adopt()
    if NS.IsCombatLocked() then return end
    for frame, list in pairs(laid) do
        if list.failed and not list.rollback then PaintNativeSkins(frame) end
    end
end

function M:Disable()
    self.active = false
    NS.HostBridge.WatchIconSkins("playerAuras", false)
    if NS.IsCombatLocked() then
        if not cleanup then
            cleanup = S.CreateFrame("Frame")
            cleanup:SetScript("OnEvent", FinishCleanup)
        end
        cleanup:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        FinishCleanup()
    end
end

local BUFF_LAYOUT = { "iconWidth", "iconHeight", "iconZoom", "perRow", "spacing", "rowSpacing" }
local DEBUFF_LAYOUT = { "debuffIconWidth", "debuffIconHeight", "iconZoom", "perRow", "spacing", "rowSpacing", "debuffTimerTextSize" }
local DEBUFF_LABELS = { debuffX = "X", debuffOffset = "Y", debuffIconWidth = "Width",
    debuffIconHeight = "Height", debuffTimerTextSize = "Timer text size" }

local function Round(value) return floor(value + .5) end
local function Handle(frame)
    local container = frame and frame.AuraContainer
    if not (container and saved[container]) then return end
    local handle = handles[container]
    if not handle then
        handle = S.CreateFrame("Frame", nil, UIParent)
        handle:EnableMouse(false)
        handle:SetAllPoints(container)
        handles[container] = handle
    end
    return handle
end

local function Visible(frame)
    local visible = frame and frame:IsVisible()
    return not IsSecret(visible) and visible == true
end

local function Shift(frame, dx, dy)
    local list, container = laid[frame], frame and frame.AuraContainer
    if not (list and list.anchored and container and saved[container] and SaveNativePoints(container)) then return false end
    local shift = shifted[frame]
    if not shift then
        shift = {}
        shifted[frame] = shift
    end
    shift[1], shift[2] = dx, dy
    return AnchorRegions(frame, dx, dy, true) == true
end

local function InRange(delta, rule, value)
    return max(rule.min - value, min(rule.max - value, delta))
end

local function OnScreen(frame, scale, dx, dy)
    if not frame then return dx, dy end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not (Finite(left) and Finite(right) and Finite(top) and Finite(bottom) and Finite(width)
        and Finite(height)) then return dx, dy end
    local insetLeft, insetRight, insetTop, insetBottom = frame:GetClampRectInsets()
    if Finite(insetLeft) and Finite(insetRight) and Finite(insetTop) and Finite(insetBottom) then
        left, right = left + insetLeft, right + insetRight
        top, bottom = top + insetTop, bottom + insetBottom
    end
    return max(-left, min(width / scale - right, dx)), max(-bottom, min(height / scale - top, dy))
end

-- Convert host deltas to the frame scale. Buff drags carry the relative debuff row.
local function Drag(debuffRow, request)
    local frame, state = debuffRow and debuffFrame or buffFrame, request.state
    local origin = state.origin or state.values
    if not frame then return false end
    local scale = frame:GetScale()
    if not (Finite(scale) and scale > 0) then scale = 1 end
    local dx, dy = (request.deltaX or 0) / scale, (request.deltaY or 0) / scale
    if not (Finite(dx) and Finite(dy)) then return false end
    local rules = S.catalog[ID].rules
    if debuffRow then
        dx, dy = InRange(dx, rules.debuffX, origin.debuffX), -InRange(-dy, rules.debuffOffset, origin.debuffOffset)
    else
        dx, dy = OnScreen(debuffFrame, scale, InRange(dx, rules.x, origin.x), InRange(dy, rules.y, origin.y))
    end
    dx, dy = OnScreen(frame, scale, dx, dy)
    if request.phase == "commit" then
        if debuffRow then
            return S.CommitEditPosition(ID, { debuffX = Round(origin.debuffX + dx),
                debuffOffset = Round(origin.debuffOffset - dy) })
        end
        return S.CommitEditPosition(ID, { x = Round(origin.x + dx), y = Round(origin.y + dy) })
    end
    local moved = Shift(frame, dx, dy)
    if moved and not debuffRow then Shift(debuffFrame, dx, dy) end
    return moved
end

local function Control(key, axis)
    local rule = S.catalog[ID].rules[key]
    return { id = key, label = S.Text(DEBUFF_LABELS[key] or rule.label), kind = "number",
        positionAxis = axis, min = rule.min, max = rule.max, step = rule.step or 1,
        get = function() return S.Config(ID)[key] end,
        set = function(value) return S.Set(ID, key, value) end }
end

local function DebuffControls()
    local controls = { Control("debuffX", "x"), Control("debuffOffset", "y") }
    for _, key in ipairs(DEBUFF_LAYOUT) do controls[#controls + 1] = Control(key) end
    return controls
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "buffs", {
        label = "Player buffs", order = 650, xKey = "x", yKey = "y",
        getFrame = function() return Handle(buffFrame) end,
        visible = function() return Visible(buffFrame) end,
        move = function(_, _, request) return Drag(false, request) end,
        sizeSummary = false, sizeKeys = BUFF_LAYOUT,
    })
    debuffControls = debuffControls or DebuffControls()
    S.RegisterOwnedMover(ID, "debuffs", {
        label = "Player debuffs", order = 651, xKey = "debuffX", yKey = "debuffOffset",
        getFrame = function() return Handle(debuffFrame) end,
        visible = function() return Visible(debuffFrame) end,
        move = function(_, _, request) return Drag(true, request) end,
        quickPosition = false, extraControls = debuffControls, historyKeys = DEBUFF_LAYOUT, sizeSummary = false,
    })
end

S.Install("playerAuras", M)
