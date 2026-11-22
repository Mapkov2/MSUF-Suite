local _, P = ...
-- Cursor deltas follow Blizzard_SharedXML/InputUtil.lua on upstream/live
-- and upstream/forever: pixels divided by the preview's effective scale.
local E, ID = {}, "damageMeter"
P.MeterPreviewEditor = E
local M, HM, Tr = P.M, P.HM, P.Tr
local Properties = P.MeterPreviewProperties
local DRAG_THRESHOLD = 2
local TEXT_ANCHORS = { leftSize = "LEFT", rightSize = "RIGHT", rank = "LEFT", titleSize = "LEFT", headerTimerSize = "RIGHT" }
local HIT_ORDER = { window = 0, header = 1, bars = 2, name = 4, value = 4, title = 5, timer = 5, floatingTimer = 5, details = 7, buttons = 6, icon = 6 }

local function Anchor(handle, force)
    local region, anchor = handle.previewRegion, handle.textAnchor
    if not anchor then
        if force then
            handle:ClearAllPoints()
            handle:SetAllPoints(region)
        end
        return
    end
    local width = math.max(8, math.min(region:GetWidth(), region:GetStringWidth()))
    local height = math.max(8, region:GetHeight())
    if not force and handle.hitWidth == width and handle.hitHeight == height then return end
    handle.hitWidth, handle.hitHeight = width, height
    handle:ClearAllPoints()
    handle:SetPoint(anchor, region, anchor, 0, 0)
    handle:SetSize(width, height)
end

-- Resolve the same stable identity registered by the real, lazy rule row.
-- Window rows retain w1 template identities while their getters follow the picker.
function E.Open(preview, handle)
    if not handle then return false end
    local ui, key = preview.ui, handle.settingsKey or handle.controlKey
    if not ui:Focus(handle.previewSection) then return false end
    local bridge = M.SearchBridge
    if not bridge or not bridge.OpenSearchTarget then return false end
    local kind = key:match("^action%.") and "action" or "setting"
    local exact = P.Meta("suite_damageMeter", ID, key, kind, handle.previewSection)
    if kind == "setting" then exact.prepareKind, exact.prepareValue = "suiteWorkspace", key end
    local called, opened, focused = bridge.OpenSearchTarget("suite_damageMeter", "", nil, nil, {}, exact)
    return called == true and opened == true and focused == true
end

function E.Keys(preview, handle)
    local prefix = handle and handle.offsetPrefix
    if not prefix then return end
    if prefix == "screenWindow" then
        prefix = "w" .. preview.selected()
        if P.Get(ID, prefix .. "AnchorWindow") ~= 1 or preview.selected() > P.Get(ID, "windowCount") then return end
    elseif prefix == "screenTimer" then
        if P.Get(ID, "timerAnchor") ~= 1 then return end
        prefix = "timer"
    elseif prefix == "timerDock" and P.Get(ID, "timerAnchor") == 1 then
        return
    end
    return prefix .. "X", prefix .. "Y"
end
local Keys = E.Keys

local function Scale(preview, handle)
    if handle.positionScale then return handle.positionScale * preview.viewport:GetEffectiveScale() end
    return preview.stage:GetEffectiveScale()
end

local function DragCurrent(token, preview, handle)
    local x, y = Keys(preview, handle)
    return x and token.window == preview.selected() and token.current() and token.config == P.S.Config(ID)
        and token.key == x and token.scale == Scale(preview, handle) and token.x == P.Get(ID, x) and token.y == P.Get(ID, y)
end

local function UnclampDrag(value, original, correction, scale)
    if correction == 0 then return value end
    if math.abs(value - original) * scale < DRAG_THRESHOLD then return original end
    return value + correction
end

-- dragged: the commit of a drag, which must still belong to the window, profile
-- and settings it began under. Arrows and the X/Y fields carry no such claim.
local function Write(preview, handle, x, y, dragged)
    local token = handle.dragToken
    if dragged and not (token and DragCurrent(token, preview, handle)) then return false end
    if preview.inCombat or P.Combat() or not preview.viewport:IsVisible() or not handle:IsVisible() then return false end
    local xKey, yKey = Keys(preview, handle)
    if not xKey then return false end
    local rules = P.catalog[ID].rules
    local xr, yr = rules[xKey], rules[yKey]
    if dragged then
        x = UnclampDrag(x, token.x, token.clampedX, token.scale)
        y = UnclampDrag(y, token.y, token.clampedY, token.scale)
    end
    x = math.max(xr.min, math.min(xr.max, math.floor(x + .5)))
    y = math.max(yr.min, math.min(yr.max, math.floor(y + .5)))
    return P.SetMany(ID, { [xKey] = x, [yKey] = y }) ~= false
end

local function Read(preview, handle)
    local xKey, yKey = Keys(preview, handle)
    if not xKey then return 0, 0 end
    return P.Get(ID, xKey), P.Get(ID, yKey)
end

-- What a selection changes besides the keyboard, which the kit hands over.
local function Selected(preview, handle)
    local owner = preview.viewport
    local chrome = M.PreviewHelpers
    if chrome and chrome.RefreshSelectedLayerButtons then chrome.RefreshSelectedLayerButtons(preview, handle) end
    for _, target in ipairs(preview.handles) do
        P.PreviewInteraction.Outline(target, target == handle and target:IsVisible())
    end
    local previousSelectionHeight = preview.selectionHeight
    if M.PreviewSelectionBar then M.PreviewSelectionBar.Refresh(owner) end
    if preview.selection then preview.selection:SetShown(not handle or Keys(preview, handle) ~= nil) end
    P.PreviewInteraction.LayoutSelectionBar(preview.selection, preview.availableWidth)
    preview.selectionHeight = preview.selection and preview.selection:IsShown() and preview.selection:GetHeight() + 8 or 0
    local previousHeight = preview.propertiesHeight
    Properties.Refresh(preview)
    local selectionChanged = previousSelectionHeight ~= preview.selectionHeight
    if (previousHeight ~= preview.propertiesHeight or selectionChanged) and preview.ui.refreshPreview then preview.ui.refreshPreview() end
end

function E.Select(preview, handle, focus)
    preview.kit:Select(handle)
    if focus and handle then E.Open(preview, handle) end
end

-- A drag that starts selects its element and remembers which window and
-- profile it began under; when it ends the handle goes back on its region.
local function Dragged(preview, handle, phase)
    if phase == "press" then
        -- Before the drag exists, as the old code did; the claim first, so the
        -- repaint a selection asks for finds it.
        local x, y = Read(preview, handle)
        handle.dragToken = { window = preview.selected(), config = P.S.Config(ID), current = P.ProfileGuard(), x = x, y = y,
            key = Keys(preview, handle), scale = Scale(preview, handle),
            clampedX = handle.clampedX or 0, clampedY = handle.clampedY or 0 }
        E.Select(preview, handle)
        return
    end
    if phase == "done" or phase == "cancel" then handle.dragToken = nil end
    if phase == "stop" or phase == "cancel" then Anchor(handle, true) end
end

function E.Handle(preview, handle, region, prefix, label, layer, section, controlKey)
    handle.meterPreview, handle.previewRegion = preview, region
    handle.offsetPrefix, handle._label, handle._previewLayerKey = prefix ~= "window" and prefix or nil, label, layer
    handle.canMove = handle.offsetPrefix ~= nil
    handle.positionScale, handle.clampedX, handle.clampedY = false, 0, 0
    handle.previewSection = section
    handle.controlKey = controlKey
    handle.settingsKey = false
    handle.sizeSetting, handle.widthSetting, handle.heightSetting, handle.layerSetting, handle.defaultSizeSetting = false, false, false, false, false
    handle.textAnchor = TEXT_ANCHORS[controlKey]
    local priority = HIT_ORDER[layer]
    local top, base = P.S.OwnedElementLevel(30, 31) or 1120, P.S.OwnedElementLevel(0, 0) or 0
    handle:SetFrameLevel(preview.viewport:GetFrameLevel() + top - base + 32 + priority)
    Anchor(handle, true)
    preview.kit:Add(handle, handle, function() return Read(preview, handle) end,
        handle.canMove and function(x, y, dragged) return Write(preview, handle, x, y, dragged) end or nil,
        { select = false, scale = function() return Scale(preview, handle) end,
            can = function() return handle:IsVisible() and Keys(preview, handle) ~= nil end })
    HM.SkipHistoryCheckpoint(handle)
end

local function SelectionBar(preview)
    if not M.PreviewSelectionBar then return end
    local owner = preview.viewport
    owner._selectedHandle = false
    preview.selection = M.PreviewSelectionBar.Create(owner, {
        Tr = Tr, Theme = function() return P.T end,
        HandleList = function() return preview.handles end,
        HandleLabel = function(handle) return handle._label end,
        IsPlaced = function(handle) return handle:IsVisible() end,
        ReadOffsets = function(_, handle)
            return Read(preview, handle)
        end,
        WriteOffsets = function(_, handle, x, y) return Write(preview, handle, x, y) end,
        NudgeDelta = function(_, dx, dy) return preview.kit:Nudge(dx, dy) end,
        ResetOffsets = function(_, handle)
            local xKey, yKey = Keys(preview, handle)
            if not xKey then return false end
            local rules = P.catalog[ID].rules
            return Write(preview, handle, rules[xKey].default, rules[yKey].default)
        end,
        OpenSettings = function(_, handle) return E.Open(preview, handle) end,
        SelectHandle = function(_, handle)
            E.Select(preview, handle, true)
            return true
        end,
        UpdateHint = function() end,
    })
    preview.selection:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -8)
end

function E.Build(preview)
    local owner = preview.viewport
    owner.meterPreview = preview
    preview.host = P.Suite.PreviewKit.NewHost(nil, { frame = owner })
    preview.arrowBindings = { ownerName = "MSUF_SuiteMeterPreview_NudgeOwner", activeName = "MSUF_SuiteMeterPreview_ActiveNudgeBox",
        buttonPrefix = "MSUF_SuiteMeterPreview_Nudge", onClick = function(_, dx, dy) return preview.kit:Arrow(dx, dy) end }
    preview.kit = P.PreviewInteraction.Handles(preview.host, {
        owner = owner, threshold = DRAG_THRESHOLD, pixels = true, rekey = true, bindings = preview.arrowBindings,
        combat = function() return preview.inCombat or P.Combat() end,
        tip = function(handle, entering)
            P.PreviewInteraction.Outline(handle, entering or owner._selectedHandle == handle)
        end,
        click = function(handle, button, moved)
            if handle.openSample and button == "LeftButton" then
                if not moved and not preview.inCombat and not P.Combat() then handle.openSample(handle) end
            elseif button == "RightButton" then
                E.Open(preview, handle)
            else
                E.Select(preview, handle, true)
            end
        end,
        drag = function(handle, phase) Dragged(preview, handle, phase) end,
        select = function(handle) Selected(preview, handle) end,
    })
    preview.handles = preview.kit.list
    owner:SetScript("OnHide", function()
        owner:UnregisterAllEvents()
        E.Suspend(preview)
    end)
    owner:SetScript("OnShow", function()
        preview.inCombat = P.Combat()
        owner:RegisterEvent("PLAYER_REGEN_DISABLED")
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
        E.Select(preview, owner._selectedHandle)
    end)
    owner:RegisterEvent("PLAYER_REGEN_DISABLED")
    owner:RegisterEvent("PLAYER_REGEN_ENABLED")
    owner:SetScript("OnEvent", function(_, event)
        preview.inCombat = event == "PLAYER_REGEN_DISABLED"
        if preview.inCombat then E.Suspend(preview) else E.Refresh(preview) end
    end)
    SelectionBar(preview)
    Properties.Build(preview)
end

function E.Suspend(preview)
    preview.kit:Cancel()
    for _, handle in ipairs(preview.handles) do handle:EnableKeyboard(false) end
    preview.kit.opts.focus(preview.viewport, nil, false)
    Properties.Refresh(preview)
end

function E.Refresh(preview)
    local drag = preview.kit.drag
    local active = drag and drag.entry.region
    if active and not (active.dragToken and DragCurrent(active.dragToken, preview, active) and active:IsVisible()) then
        preview.kit:Cancel()
        active = nil
    end
    for _, handle in ipairs(preview.handles) do
        if handle ~= active then Anchor(handle) end
    end
    local selected = preview.viewport._selectedHandle
    E.Select(preview, selected and selected:IsVisible() and selected or nil)
end
