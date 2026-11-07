local _, P = ...
local E, ID = {}, "chat"
P.ChatPreview = E
local R, K, M, HM = P.ChatPreviewPositions, P.PreviewCanvas, P.M, P.HM
local L, Windows = P.ChatPreviewLayers, P.ChatPreviewWindows
local GEOMETRY

local Open, Current, Write, Anchor, Scale, Refresh
local function InitializeActions()
    Refresh = function(ui)
        if not ui.header:IsVisible() or not ui.ctx.wrapper:IsVisible() then return end
        local drag = ui.kit.drag
        if drag and not Current(ui, drag.entry.region) then ui.kit:Cancel() end
        L.Restore(ui)
        P.ChatPreviewPaint.Refresh(ui)
        P.ChatPreviewLinks.Refresh(ui)
        Windows.Refresh(ui)
        L.Paint(ui)
        local selected = ui.viewport._selectedHandle
        for _, handle in ipairs(ui.handles) do
            if handle.spec.prefix == "tab" and handle.region ~= ui.parts.tabGroup then handle._label = handle.region.Text:GetText() end
            if not ui.kit.drag or ui.kit.drag.entry.region ~= handle then Anchor(handle) end
        end
        E.Select(ui, selected and selected:IsVisible() and selected or nil)
    end

    Scale = function(ui, handle)
        local spec = handle.spec
        local factor = spec.icon and 1 or spec.prefix == "tab" and (ui.parts.dockScale or 1) or ui.parts.nativeScale or 1
        return ui.stage:GetEffectiveScale() * factor
    end
    Open = function(ui, spec)
        if not spec or ui.inCombat or P.Combat() or not ui.header:IsVisible() or not ui.ctx.wrapper:IsVisible() then return false end
        if P.ChatPreviewLinks.Open(ui, spec) then return true end
        local section = "suite_chat" .. "_" .. spec.section
        local body = ui.ctx.chatSections and ui.ctx.chatSections[section]
        if body then
            P.EnsureSectionContent(body)
            -- Older hosts still expose local section navigation without exact search.
            if P.W.FocusCollapsibleSection and P.W.FocusCollapsibleSection(body, { persist = true, flash = true }) then return true end
        end
        local bridge = M.SearchBridge
        if not bridge or not bridge.OpenSearchTarget then return body ~= nil end
        local exact = P.Meta("suite_chat", ID, spec.control, "setting", section)
        local called, opened, focused = bridge.OpenSearchTarget("suite_chat", "", nil, nil, {}, exact)
        return called == true and opened == true and focused == true
    end

    Current = function(ui, handle)
        local token = handle.dragToken
        if not token or token.width ~= ui.width or token.scale ~= Scale(ui, handle) then return false end
        for _, key in ipairs(GEOMETRY) do
            if token.geometry[key] ~= P.Get(ID, key) then return false end
        end
        return token.nativeEpoch == ui.parts.nativeEpoch and token.current() and token.config == P.S.Config(ID)
            and token.x == P.Get(ID, handle.spec.prefix .. "X") and token.y == P.Get(ID, handle.spec.prefix .. "Y")
            and (not handle.spec.icon or token.moved == P.Get(ID, handle.spec.prefix .. "Moved"))
    end

    Write = function(ui, handle, x, y, dragged)
        if ui.inCombat or not ui.header:IsVisible() or not ui.ctx.wrapper:IsVisible() or not handle:IsVisible() then return false end
        if dragged and not Current(ui, handle) then return false end
        return R.Write(handle.spec, x, y)
    end

    Anchor = function(handle)
        if handle.spec.prefix == "messageText" then return P.ChatPreviewPaint.AnchorMessage(handle) end
        handle:ClearAllPoints()
        handle:SetAllPoints(handle.region)
    end
end

local function Highlight(ui, selected)
    local hovered = ui.hoveredMessage
    if hovered and not (hovered.hitVisible and hovered:IsVisible()) then
        ui.hoveredMessage, hovered = nil, nil
    end
    local highlighted = hovered or selected
    for _, target in ipairs(ui.handles) do
        P.PreviewInteraction.Outline(target, target == highlighted and target:IsVisible() and target.hitVisible ~= false)
    end
end

local function InitializeSelection()
    local function BarLayout(ui)
        local bar, width = ui.selection, ui.width
        if not bar then return end
        local wide, narrow = width >= 650, width < 290
        local height = wide and 28 or narrow and 112 or 84
        bar:SetSize(width, height)
        local function Place(region, x, y)
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", bar, "TOPLEFT", x, y)
        end
        Place(bar.swatch, 8, -8)
        Place(bar.label, 24, -3)
        bar.label:SetSize(wide and 140 or width - 32, 18)
        Place(bar.axisX, wide and 170 or 8, wide and -1 or -29)
        Place(bar.axisY, wide and 294 or narrow and 8 or 132, wide and -1 or narrow and -57 or -29)
        Place(bar.resetButton, wide and 422 or 8, wide and -3 or narrow and -85 or -57)
        bar.openButton:ClearAllPoints()
        bar.openButton:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -8, wide and -3 or narrow and -85 or -57)
        bar:SetShown(ui.viewport._selectedHandle and ui.viewport._selectedHandle.canMove)
    end

    E.Selected = function(ui, handle)
        Highlight(ui, handle)
        if M.PreviewSelectionBar then M.PreviewSelectionBar.Refresh(ui.viewport) end
        BarLayout(ui)
        P.PreviewInteraction.SetHint(ui.hint, handle and handle._label, handle and handle.canMove and R.Allowed(handle.spec))
    end

    function E.Select(ui, key, open)
        local handle = type(key) == "string" and ui.targets[key] or key
        if type(key) == "string" and handle then
            local layer = handle.spec.section
            if ui.layers[layer] == false then
                L.Restore(ui)
                ui.layers[layer] = true
                L.Paint(ui)
            end
        end
        if key == "messageText" then
            for _, row in ipairs(ui.messageHandles) do
                if row.hitVisible then handle = row break end
            end
        end
        ui.kit:Select(handle)
        if open and handle then Open(ui, handle.spec) end
        E.Layout(ui)
    end

    function E.Layout(ui)
        local barHeight = ui.selection and ui.selection:IsShown() and ui.selection:GetHeight() + 8 or 0
        local layerHeight = L.Layout(ui, barHeight)
        local windowHeight = Windows.Layout(ui, barHeight + layerHeight)
        ui.hint:ClearAllPoints()
        ui.hint:SetPoint("TOPLEFT", ui.viewport, "BOTTOMLEFT", 0, -8 - barHeight - layerHeight - windowHeight)
        ui.hint:SetWidth(ui.width)
        local height = 60 + (ui.navigationHeight or 0) + (ui.canvasHeight or 216) + barHeight + layerHeight + windowHeight
        P.MenuWorkspace.FitHeader(ui, height + math.ceil(ui.hint:GetStringHeight() or 28))
    end
end

local function SelectionBar(ui)
    local function GuardAxis(ui, input)
        if not input then return end -- Older hosts may only expose the axis buttons.
        local claim
        input:HookScript("OnEditFocusGained", function()
            claim = { current = P.ProfileGuard(), config = P.S.Config(ID),
                handle = ui.viewport._selectedHandle, epoch = ui.inputEpoch }
        end)
        input:HookScript("OnHide", function() claim = nil end)
        local function Valid()
            return claim and claim.current() and claim.config == P.S.Config(ID) and claim.epoch == ui.inputEpoch
                and claim.handle == ui.viewport._selectedHandle and ui.header:IsVisible() and ui.ctx.wrapper:IsVisible()
        end
        for _, script in ipairs({ "OnEnterPressed", "OnEditFocusLost" }) do
            local handler = input:GetScript(script)
            if handler then
                input:SetScript(script, function(...)
                    if Valid() then return handler(...) end
                    if script == "OnEnterPressed" then input:ClearFocus() end
                    M.PreviewSelectionBar.Refresh(ui.viewport)
                end)
            end
        end
    end

    if not M.PreviewSelectionBar then return end
    ui.selection = M.PreviewSelectionBar.Create(ui.viewport, {
        Tr = P.Tr, Theme = function() return P.T end,
        HandleList = function() return ui.handles end,
        HandleLabel = function(handle) return handle._label end,
        IsPlaced = function(handle)
            return handle.canMove and handle:IsVisible()
                and (handle.hitVisible ~= false or handle == ui.viewport._selectedHandle)
        end,
        ReadOffsets = function(_, handle) return R.Read(ui, handle.spec) end,
        WriteOffsets = function(_, handle, x, y) return Write(ui, handle, x, y) end,
        NudgeDelta = function(_, dx, dy) return ui.kit:Nudge(dx, dy) end,
        ResetOffsets = function(_, handle)
            if not ui.inCombat and ui.header:IsVisible() and handle:IsVisible() then return R.Reset(handle.spec) end
            return false
        end,
        OpenSettings = function(_, handle) return handle and Open(ui, handle.spec) end,
        SelectHandle = function(_, handle) E.Select(ui, handle, true) return true end,
        UpdateHint = function() end,
    })
    -- Navigation stays available while the selected element cannot be moved.
    local setEnabled = ui.selection.MSUF2SetEnabled
    function ui.selection:MSUF2SetEnabled(enabled)
        local handle = ui.viewport._selectedHandle
        setEnabled(self, enabled and handle and R.Allowed(handle.spec))
        self.openButton:SetEnabled(enabled)
        self.openButton:SetAlpha(enabled and 1 or .45)
    end
    ui.selection:SetPoint("TOPLEFT", ui.viewport, "BOTTOMLEFT", 0, -8)
    GuardAxis(ui, ui.selection.axisX.edit)
    GuardAxis(ui, ui.selection.axisY.edit)
end

local function Interactions(ui)
    local function Drag(ui, handle, phase)
        if phase == "press" then
            local spec = handle.spec
            handle.dragToken = { current = P.ProfileGuard(), config = P.S.Config(ID),
                x = P.Get(ID, spec.prefix .. "X"), y = P.Get(ID, spec.prefix .. "Y"),
                moved = spec.icon and P.Get(ID, spec.prefix .. "Moved"),
                width = ui.width, scale = Scale(ui, handle), nativeEpoch = ui.parts.nativeEpoch, geometry = {} }
            handle.dragToken.draw = { handle.followRegion:GetPoint(1) }
            for _, key in ipairs(GEOMETRY) do handle.dragToken.geometry[key] = P.Get(ID, key) end
        elseif (phase == "start" or phase == "stop") and handle.dragToken and ui.viewport._selectedHandle ~= handle then
            E.Select(ui, handle)
        elseif phase == "done" then
            handle.dragToken = nil
        end
        if phase == "stop" or phase == "cancel" then
            if handle.dragToken then handle.follow(handle, 0, 0) end
            Anchor(handle)
            if phase == "cancel" then handle.dragToken = nil end
        end
    end

    local function Add(ui, region, spec, priority)
        local parent = spec.prefix == "messageText" and ui.parts.sample
            or (region:IsObjectType("FontString") and region:GetParent() or region)
        local handle = CreateFrame("Button", nil, parent)
        handle.spec, handle.region, handle._label = spec, region, spec.label
        handle.canMove = spec.prefix ~= nil
        handle.followRegion = spec.followRegion and ui.parts[spec.followRegion] or spec.region and ui.parts[spec.region] or region
        handle.follow = function(_, dx, dy)
            local token = handle.dragToken
            if not token then return end
            local point = token.draw
            handle.followRegion:ClearAllPoints()
            handle.followRegion:SetPoint(point[1], point[2], point[3], (point[4] or 0) + dx, (point[5] or 0) + dy)
        end
        handle:SetFrameLevel(ui.stage:GetFrameLevel() + 12 + priority)
        local key = spec.prefix or spec.control
        ui.targets[key] = ui.targets[key] or handle
        if spec.prefix == "tab" and region ~= ui.parts.tabGroup then handle._label = region.Text:GetText() end
        ui.kit:Add(handle, handle, function() return R.Read(ui, spec) end,
            handle.canMove and function(x, y, dragged) return Write(ui, handle, x, y, dragged) end or nil,
            { select = false, follow = handle.follow, scale = function() return Scale(ui, handle) end,
                can = function() return handle.canMove and R.Allowed(spec) end })
        Anchor(handle)
        HM.SkipHistoryCheckpoint(handle)
        return handle
    end

    ui.addHandle, ui.dragHandle = Add, Drag
end

local function BindInteractions(ui)
    ui.host = P.Suite.PreviewKit.NewHost(nil, { frame = ui.viewport })
    local bindings = { ownerName = "MSUF_SuiteChatPreview_NudgeOwner", activeName = "MSUF_SuiteChatPreview_ActiveNudgeBox",
        buttonPrefix = "MSUF_SuiteChatPreview_Nudge", onClick = function(_, dx, dy) return ui.kit:Arrow(dx, dy) end }
    ui.kit = P.PreviewInteraction.Handles(ui.host, {
        owner = ui.viewport, pixels = true, threshold = 4, manualDrag = true, rekey = true, bindings = bindings,
        combat = function() return ui.inCombat or P.Combat() end,
        tip = function(handle, entering)
            local selected = ui.viewport._selectedHandle
            if handle.spec.prefix == "messageText" then
                if entering and handle.hitVisible then ui.hoveredMessage = handle
                elseif ui.hoveredMessage == handle then ui.hoveredMessage = nil end
                Highlight(ui, selected)
            else
                P.PreviewInteraction.Outline(handle, not ui.hoveredMessage and (entering or selected == handle))
            end
            if handle.spec.icon and handle.region.entry then
                handle.region.hovered = entering == true
                P.S.ChatPaintPreviewSidebarHover(ui.parts, handle.region.entry)
            end
        end,
        click = function(handle, button, moved)
            if moved then return end
            local rename = button == "RightButton" and Windows.RenamePreviewTab(ui, handle.region)
            E.Select(ui, handle, not rename)
        end,
        drag = function(handle, phase) ui.dragHandle(ui, handle, phase) end,
        select = function(handle) E.Selected(ui, handle) end,
    })
    ui.handles, ui.messageHandles = ui.kit.list, {}
    for _, spec in ipairs(R.elements) do
        if spec.prefix == "messageText" then
            for index, line in ipairs(ui.parts.messageLines) do
                ui.messageHandles[index] = ui.addHandle(ui, line, spec, 2)
            end
        else
            local region = spec.region and ui.parts[spec.region] or spec.icon and ui.parts.icons[spec.icon]
                or spec.prefix == "window" and ui.parts.sample or ui.parts.copy
            ui.addHandle(ui, region, spec, spec.prefix == "window" and 0 or 4)
            if spec.prefix == "tab" then
                for _, tab in ipairs(ui.parts.tabs) do ui.addHandle(ui, tab, spec, 5) end
            end
        end
    end
    P.ChatPreviewLinks.Refresh(ui)
    SelectionBar(ui)
end

local function Lifecycle(ui)
    local function Suspend(ui)
        ui.inputEpoch = (ui.inputEpoch or 0) + 1
        ui.kit:Release()
        if ui.parts.fontReady then P.S.ChatWatchPreview(ui.viewport) end
        for _, handle in ipairs(ui.handles) do handle:EnableKeyboard(false) end
        ui.kit.opts.focus(ui.viewport, nil, false)
    end

    local owner = ui.viewport
    local function Activate()
        ui.inCombat = P.Combat()
        owner:RegisterEvent("PLAYER_REGEN_DISABLED")
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
        for _, event in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
            "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED", "BN_DISCONNECTED", "ADDON_LOADED",
            "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
            owner:RegisterEvent(event)
        end
    end
    owner:SetScript("OnShow", Activate)
    owner:SetScript("OnHide", function() owner:UnregisterAllEvents() Suspend(ui) end)
    ui.ctx.wrapper:HookScript("OnHide", function() Suspend(ui) end)
    ui.header:HookScript("OnHide", function() Suspend(ui) end)
    owner:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            ui.inCombat = true
            Windows.Refresh(ui)
            Suspend(ui)
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then ui.inCombat = false end
        if event ~= "ADDON_LOADED" or ui.parts.fontReady then
            ui.parts.painter = nil
            Refresh(ui)
        end
    end)
    if owner:IsVisible() then Activate() end
    ui.header:HookScript("OnSizeChanged", function(_, width)
        if not width or width <= 32 then return end
        ui.width = math.max(200, width - 32)
        ui.viewport:SetWidth(ui.width)
        Refresh(ui)
    end)
    ui.runtimeRefresh = function()
        if ui.kit.drag then ui.kit:Cancel() end
        ui.parts.painter = nil
        Refresh(ui)
    end
    K.Watch({ header = ui.parts.sample, ctx = ui.ctx }, function() Refresh(ui) end)
end

function E.Build(ctx, builder)
    R.Initialize()
    if not Open then
        InitializeActions()
        InitializeSelection()
    end
    if not GEOMETRY then
        GEOMETRY = { "lockWindowSize", "windowWidth", "windowHeight", "padding", "sidebarSide", "sidebarWidth",
            "sidebarGap", "scrollButtonPlace", "tabHeight", "tabPanelGap", "inputTop", "inputHeight",
            "inputWidth", "sidebarPanel", "panelAlpha" }
    end
    local header, toolbar = P.W.FixedPreviewSection(ctx, builder, { title = P.Tr("Preview"), height = 310, gap = 8 })
    if not header then return end
    local ui = { ctx = ctx, header = header, toolbar = toolbar, spec = { height = 176 }, targets = {},
        width = math.max(240, (HM.GetSectionWidth(header) or builder.width or 720) - 32) }
    ctx.chatPreviewUI = ui
    ui.viewport = CreateFrame("Frame", nil, header)
    ui.viewport:SetPoint("TOPLEFT", header, "TOPLEFT", 16, -42)
    ui.viewport:SetSize(ui.width, 216)
    ui.canvas = CreateFrame("Frame", nil, ui.viewport)
    ui.canvas:SetAllPoints(ui.viewport)
    ui.canvas:SetClipsChildren(true)
    ui.stage = CreateFrame("Frame", nil, ui.canvas)
    ui.stage:SetPoint("TOP", ui.viewport, "TOP", 0, 0)
    ui.stage:SetSize(ui.width, 216)
    ui.hint = K.Text(header, "Click to select; drag or use arrow keys; edit exact X/Y below.", 16, -270, ui.width)
    P.ChatPreviewPaint.Build(ui)
    Interactions(ui)
    BindInteractions(ui)
    L.Build(ui, function(key, enabled)
        if ui.inCombat or P.Combat() or not ui.header:IsVisible() or not ui.ctx.wrapper:IsVisible() then return false end
        ui.kit:Cancel()
        L.Restore(ui)
        ui.layers[key] = enabled
        L.Paint(ui)
        local selected = ui.viewport._selectedHandle
        E.Select(ui, selected and selected:IsVisible() and selected or nil)
        return true
    end, function(spec) return Open(ui, spec) end)
    Windows.Build(ui)
    E.Layout(ui)
    R.BindSearch(ui)
    Lifecycle(ui)
    return ui
end
