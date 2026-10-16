local _, P = ...
-- Cursor deltas follow Blizzard_SharedXML/InputUtil.lua on upstream/live
-- and upstream/forever: pixels divided by the preview's effective scale.
local E, ID = {}, "damageMeter"
P.MeterPreviewEditor = E
local M, HM, Tr = P.M, P.HM, P.Tr
local Properties = P.MeterPreviewProperties
local TEXT_ANCHORS = { leftSize = "LEFT", rightSize = "RIGHT", rank = "LEFT", titleSize = "LEFT", headerTimerSize = "RIGHT" }
local HIT_ORDER = { window = 0, header = 1, bars = 2, name = 4, value = 4, title = 5, timer = 5, buttons = 6, icon = 6 }

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
    local ui, key = preview.ui, handle.controlKey
    if not ui:Focus(handle.previewSection) then return false end
    local bridge = M.SearchBridge
    if not bridge or not bridge.OpenSearchTarget then return false end
    local kind = key:match("^action%.") and "action" or "setting"
    local exact = P.Meta("suite_damageMeter", ID, key, kind, handle.previewSection)
    if kind == "setting" then exact.prepareKind, exact.prepareValue = "suiteWorkspace", key end
    local called, opened, focused = bridge.OpenSearchTarget("suite_damageMeter", "", nil, nil, {}, exact)
    return called == true and opened == true and focused == true
end

local function Keys(preview, handle)
    if not handle.canMove then return end
    local prefix = handle.offsetPrefix
    return prefix .. "X", prefix .. "Y"
end

local function DragCurrent(token, preview)
    return token.window == preview.selected() and token.current() and token.config == P.S.Config(ID)
end

local function Write(preview, handle, x, y)
    local token = handle.dragToken
    handle.dragToken = nil
    if token and not DragCurrent(token, preview) then return false end
    if preview.inCombat or P.Combat() or not preview.viewport:IsVisible() or not handle:IsVisible() then return false end
    local xKey, yKey = Keys(preview, handle)
    if not xKey then return false end
    local rules = P.catalog[ID].rules
    local xr, yr = rules[xKey], rules[yKey]
    x = math.max(xr.min, math.min(xr.max, math.floor(x + .5)))
    y = math.max(yr.min, math.min(yr.max, math.floor(y + .5)))
    return P.SetMany(ID, { [xKey] = x, [yKey] = y }) ~= false
end

local function Read(preview, handle)
    local xKey, yKey = Keys(preview, handle)
    if not xKey then return 0, 0 end
    return P.Get(ID, xKey), P.Get(ID, yKey)
end

local function SelectionLayout(preview)
    local bar, width = preview.selection, preview.availableWidth
    if not bar or bar.layoutWidth == width then return end
    bar.layoutWidth = width
    local compact, narrow = width < 600, width < 260
    local height = compact and (narrow and 112 or 84) or 24
    local function Place(region, x, y, point)
        region:ClearAllPoints()
        region:SetPoint(point or "TOPLEFT", bar, point or "TOPLEFT", x, y)
    end
    bar:SetSize(width, height)
    Place(bar.swatch, 10, -8)
    Place(bar.label, 25, -3)
    bar.label:SetWidth(compact and width - 35 or 132)
    bar.label:SetHeight(18)
    Place(bar.axisX, compact and 10 or 163, compact and -29 or -1)
    Place(bar.axisY, compact and (narrow and 10 or 132) or 285, compact and (narrow and -57 or -29) or -1)
    local actionsY = compact and (narrow and -85 or -57) or -3
    Place(bar.openButton, -8, actionsY, "TOPRIGHT")
    if compact then Place(bar.resetButton, 10, actionsY)
    else
        bar.resetButton:ClearAllPoints()
        bar.resetButton:SetPoint("RIGHT", bar.openButton, "LEFT", -6, 0)
    end
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
    if preview.selection then preview.selection:SetShown(not handle or handle.canMove) end
    SelectionLayout(preview)
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
    if phase == "start" then
        E.Select(preview, handle)
        handle.dragToken = { window = preview.selected(), config = P.S.Config(ID), current = P.ProfileGuard() }
        return
    end
    if phase == "cancel" then handle.dragToken = nil end
    Anchor(handle, true)
end

function E.Handle(preview, handle, region, prefix, label, layer, section, controlKey)
    handle.meterPreview, handle.previewRegion = preview, region
    handle.offsetPrefix, handle._label, handle._previewLayerKey = prefix, label, layer
    handle.canMove = prefix ~= "window"
    handle.previewSection = section
    handle.controlKey = controlKey
    handle.sizeSetting, handle.widthSetting, handle.heightSetting, handle.layerSetting, handle.defaultSizeSetting = false, false, false, false, false
    handle.textAnchor = TEXT_ANCHORS[controlKey]
    local priority = HIT_ORDER[layer]
    local top, base = P.S.OwnedElementLevel(30, 31) or 1120, P.S.OwnedElementLevel(0, 0) or 0
    handle:SetFrameLevel(preview.viewport:GetFrameLevel() + top - base + 32 + priority)
    Anchor(handle, true)
    preview.kit:Add(handle, handle, function() return Read(preview, handle) end,
        handle.canMove and function(x, y) return Write(preview, handle, x, y) end or nil,
        { select = false, scale = function() return preview.stage:GetEffectiveScale() end })
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
        owner = owner, threshold = 2, rekey = true, bindings = preview.arrowBindings,
        combat = function() return preview.inCombat or P.Combat() end,
        tip = function(handle, entering)
            P.PreviewInteraction.Outline(handle, entering or owner._selectedHandle == handle)
        end,
        click = function(handle, button)
            if button == "RightButton" then E.Open(preview, handle) else E.Select(preview, handle, true) end
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
    if active and not (active.dragToken and DragCurrent(active.dragToken, preview) and active:IsVisible()) then
        preview.kit:Cancel()
        active = nil
    end
    for _, handle in ipairs(preview.handles) do
        if handle ~= active then Anchor(handle) end
    end
    local selected = preview.viewport._selectedHandle
    E.Select(preview, selected and selected:IsVisible() and selected or nil)
end
