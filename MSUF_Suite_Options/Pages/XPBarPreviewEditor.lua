local _, P = ...
local Editor = {}
P.XPBarPreviewEditor = Editor
local S, M, HM, Tr = P.S, P.M, P.HM, P.Tr
local ID, PAGE, SECTION = "xpBar", "suite_hud", "suite_qualityOfLife_xpBar_xp_bar"
local Shared = P.Suite.ExperienceBarLayout
local CLAIM_FIELDS = { "Anchor", "X", "Y", "Font", "Size", "Outline", "Visibility", "Format", "Numbers" }

local function SettleInput(editor)
    local focus = GetCurrentKeyBoardFocus() or editor.activeInput
    if not focus or not focus:IsObjectType("EditBox") then return end
    local ancestor = focus
    while ancestor and ancestor ~= editor.parent and ancestor ~= UIParent do ancestor = ancestor:GetParent() end
    if ancestor ~= editor.parent then return end
    if focus == editor.activeInput then
        local commit = focus:GetScript("OnEditFocusLost")
        if commit then commit(focus) end
    end
    focus:ClearFocus()
end

local function Current(editor, handle)
    local token = handle.claim
    if not token or not token.current() or token.config ~= S.Config(ID) or not editor.ui.stage:IsVisible() then return false end
    local config = S.Config(ID)
    if token.width ~= config.width or token.height ~= config.height or token.scale ~= config.scale
        or token.style ~= config.displayStyle or token.effectiveScale ~= editor.view.host:GetEffectiveScale()
        or token.revision ~= editor.view.textLayoutRevision then return false end
    for _, key in ipairs(handle.keys) do
        if token.values[key] ~= config[key] then return false end
    end
    return true
end

local function Open(editor, handle)
    if not handle or P.Combat() or not editor.ui.stage:IsVisible() then return false end
    editor.properties:Select(handle.spec.id)
    local exact = P.Meta(PAGE, ID, handle.spec.prefix .. "Size", "setting", SECTION)
    local called, opened, focused = M.SearchBridge.OpenSearchTarget(PAGE, "", nil, nil, {}, exact)
    return called and opened and focused
end

local function Read(handle)
    local config, prefix = S.Config(ID), handle.spec.prefix
    return config[prefix .. "X"] or 0, config[prefix .. "Y"] or 0
end

local function Write(editor, handle, x, y, dragged)
    if P.Combat() or not editor.ui.stage:IsVisible() or not handle:IsVisible()
        or editor.config ~= S.Config(ID) or dragged and not Current(editor, handle) then return false end
    local prefix, rules = handle.spec.prefix, P.catalog[ID].rules
    local xr, yr = rules[prefix .. "X"], rules[prefix .. "Y"]
    local values = { [prefix .. "X"] = math.max(xr.min, math.min(xr.max, math.floor(x + .5))),
        [prefix .. "Y"] = math.max(yr.min, math.min(yr.max, math.floor(y + .5))) }
    return P.SetMany(ID, values) ~= false
end

local function Selected(editor, handle)
    if editor.selected ~= handle then editor.inputEpoch = editor.inputEpoch + 1 end
    editor.selected = handle
    if handle then editor.properties:Select(handle.spec.id) end
    for _, target in ipairs(editor.kit.list) do P.PreviewInteraction.Outline(target, target == handle and target:IsVisible()) end
    if editor.selection then M.PreviewSelectionBar.Refresh(editor.ui.stage) end
end

local function Drag(editor, handle, phase)
    if phase == "press" then
        SettleInput(editor)
        editor.inputEpoch = editor.inputEpoch + 1
        local config = S.Config(ID)
        local token = { current = P.ProfileGuard(), config = config, values = {}, width = config.width,
            height = config.height, scale = config.scale, style = config.displayStyle,
            effectiveScale = editor.view.host:GetEffectiveScale(), revision = editor.view.textLayoutRevision,
            point = { handle.region:GetPoint(1) } }
        for _, key in ipairs(handle.keys) do token.values[key] = config[key] end
        handle.claim = token
        editor.ui.viewport.fixedScale = editor.view.host:GetScale()
    elseif phase == "done" or phase == "cancel" then
        handle.claim, editor.ui.viewport.fixedScale = nil, nil
        editor.ui.Paint()
    end
end

local function Add(editor, spec)
    local view, ui = editor.view, editor.ui
    local region = view[spec.region]
    local handle = CreateFrame("Button", nil, view.host)
    handle.spec, handle.region, handle._label = spec, region, spec.label
    handle.keys = {}
    for _, suffix in ipairs(CLAIM_FIELDS) do handle.keys[#handle.keys + 1] = spec.prefix .. suffix end
    handle:SetFrameLevel(view.host:GetFrameLevel() + 30 + #editor.kit.list)
    handle:SetAllPoints(region)
    local function Follow(_, dx, dy)
        if not Current(editor, handle) then
            editor.kit:Cancel()
            return
        end
        local point = handle.claim.point
        region:ClearAllPoints()
        region:SetPoint(point[1], point[2], point[3], (point[4] or 0) + dx, (point[5] or 0) + dy)
    end
    editor.kit:Add(spec.id, handle, function() return Read(handle) end,
        function(x, y, dragged) return Write(editor, handle, x, y, dragged) end,
        { follow = Follow, scale = function() return view.host:GetEffectiveScale() end })
    HM.SkipHistoryCheckpoint(handle)
    M.AddTooltip(handle, Tr(spec.label), Tr("Drag or use arrows to move; click for settings."), { hook = true })
    ui.targets[spec.id] = handle
    return handle
end

local function GuardAxis(editor, input)
    if not input then return end
    local claim
    local focus = input:GetScript("OnEditFocusGained")
    input:SetScript("OnEditFocusGained", function(...)
        claim = { current = P.ProfileGuard(), config = S.Config(ID), handle = editor.selected, epoch = editor.inputEpoch }
        editor.activeInput = input
        if focus then focus(...) end
    end)
    input:HookScript("OnHide", function()
        claim = nil
        if editor.activeInput == input then editor.activeInput = nil end
    end)
    for _, script in ipairs({ "OnEnterPressed", "OnEditFocusLost" }) do
        local original = input:GetScript(script)
        if original then
            input:SetScript(script, function(...)
                local valid = claim and claim.current() and claim.config == S.Config(ID) and claim.handle == editor.selected
                    and claim.epoch == editor.inputEpoch and editor.ui.stage:IsVisible()
                claim = nil
                if editor.activeInput == input then editor.activeInput = nil end
                if valid then return original(...) end
                if script == "OnEnterPressed" then input:ClearFocus() end
                M.PreviewSelectionBar.Refresh(editor.ui.stage)
            end)
        end
    end
end

local function SelectionBar(editor, parent, y)
    local ui = editor.ui
    local bar = M.PreviewSelectionBar.Create(ui.stage, {
        Tr = Tr, Theme = function() return P.T end, HandleList = function() return editor.kit.list end,
        HandleLabel = function(handle) return handle._label end,
        IsPlaced = function(handle) return handle:IsVisible() end,
        ReadOffsets = function(_, handle) return Read(handle) end,
        WriteOffsets = function(_, handle, x, y) return Write(editor, handle, x, y) end,
        NudgeDelta = function(_, dx, dy) return editor.kit:Nudge(dx, dy) end,
        ResetOffsets = function(_, handle) return Write(editor, handle, 0, 0) end,
        OpenSettings = function(_, handle) return Open(editor, handle) end,
        SelectHandle = function(_, handle)
            editor.kit:Select(handle)
            return true
        end,
    })
    bar:SetParent(parent)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    bar:SetWidth(ui.width)
    local wide = ui.width >= 650
    local height = wide and 30 or 92
    bar:SetHeight(height)
    bar.axisX:ClearAllPoints()
    bar.axisY:ClearAllPoints()
    bar.axisX:SetPoint("TOPLEFT", bar, "TOPLEFT", wide and 170 or 8, wide and -1 or -29)
    bar.axisY:SetPoint("TOPLEFT", bar, "TOPLEFT", wide and 294 or 132, wide and -1 or -29)
    bar.resetButton:ClearAllPoints()
    bar.resetButton:SetPoint("TOPLEFT", bar, "TOPLEFT", wide and 422 or 8, wide and -3 or -59)
    bar.openButton:ClearAllPoints()
    bar.openButton:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -8, wide and -3 or -59)
    editor.selection = bar
    GuardAxis(editor, bar.axisX.edit)
    GuardAxis(editor, bar.axisY.edit)
    return y - height - 12
end

local function Suspend(editor)
    editor.inputEpoch = editor.inputEpoch + 1
    editor.kit:Release()
    editor.kit.opts.focus(editor.ui.stage, nil, false)
    editor.ui.viewport.fixedScale = nil
    if editor.selection then editor.selection:Hide() end
end

local function Controller(editor)
    local ui = editor.ui
    editor.host = P.Suite.PreviewKit.NewHost(nil, { frame = ui.stage,
        paint = function() ui.Paint() end })
    local bindings = { ownerName = "MSUF_SuiteXPPreview_NudgeOwner", activeName = "MSUF_SuiteXPPreview_ActiveNudgeBox",
        buttonPrefix = "MSUF_SuiteXPPreview_Nudge", onClick = function(_, dx, dy) return editor.kit:Arrow(dx, dy) end }
    editor.kit = P.PreviewInteraction.Handles(editor.host, {
        owner = ui.stage, threshold = 2, rekey = true, bindings = bindings,
        combat = function() return P.Combat() or not ui.stage:IsVisible() end,
        tip = function(handle, entering) P.PreviewInteraction.Outline(handle, entering or editor.selected == handle) end,
        select = function(handle) Selected(editor, handle) end,
        click = function(handle, _, moved) if not moved then Open(editor, handle) end end,
        drag = function(handle, phase) Drag(editor, handle, phase) end,
        escape = function() editor.kit:Release() end,
        tab = function(backwards)
            if editor.kit:Typing() or P.Combat() then return false end
            return M.PreviewSelectionBar.CycleHandle(ui.stage, backwards)
        end,
    })
    local select = editor.kit.Select
    function editor.kit:Select(target)
        if target then SettleInput(editor) end
        return select(self, target)
    end
    local keydown = editor.kit.opts.keydown
    if keydown then
        editor.kit.opts.keydown = function(frame, key)
            local consumed
            if key == "TAB" then consumed = editor.kit.opts.tab(IsShiftKeyDown())
            elseif key == "ESCAPE" and editor.selected then
                editor.kit:Release()
                consumed = true
            else return keydown(frame, key) end
            frame:SetPropagateKeyboardInput(not consumed)
            return consumed
        end
    end
end

function Editor.Build(ui, parent, y, width)
    local editor = { ui = ui, parent = parent, inputEpoch = 0, config = S.Config(ID) }
    ui.xpEditor = editor
    Controller(editor)
    y = SelectionBar(editor, parent, y)
    editor.properties, y = P.XPBarTextOptions.Build(ui.ctx, parent, y, width, function(id)
        local handle = ui.targets[id]
        if handle then editor.kit:Select(handle) else editor.properties:Select(id) end
    end)
    ui.stage:HookScript("OnHide", function() Suspend(editor) end)
    ui.stage:HookScript("OnShow", function()
        ui.stage:RegisterEvent("PLAYER_REGEN_DISABLED")
        if editor.selection then editor.selection:Show() end
    end)
    ui.stage:HookScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then Suspend(editor) end
        if event == "PLAYER_REGEN_ENABLED" and editor.selection then editor.selection:Show() end
    end)
    if ui.stage:IsVisible() then ui.stage:RegisterEvent("PLAYER_REGEN_DISABLED") end
    ui.Paint()
    return y
end

function Editor.Bind(ui, view)
    local editor = ui.xpEditor
    if not editor then return end
    editor.view = view
    if editor.config ~= S.Config(ID) then
        Suspend(editor)
        editor.config = S.Config(ID)
    end
    if editor.kit.drag and not Current(editor, editor.kit.drag.entry.region) then editor.kit:Cancel() end
    if #editor.kit.list == 0 then
        for _, spec in ipairs(Shared.Texts) do Add(editor, spec) end
        editor.kit:Select(ui.targets.percent)
    end
    for _, handle in ipairs(editor.kit.list) do handle:SetShown(handle.region:IsShown()) end
    Selected(editor, editor.kit:Selected())
end
