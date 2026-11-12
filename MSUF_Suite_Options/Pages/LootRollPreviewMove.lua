local _, P = ...
-- Moving loot row elements in the preview, as the damage meter does: drag,
-- arrow keys and the X/Y bar write one element's <id>OffsetX/Y, which moves
-- that element in every row. A drag only re-anchors the element's painted
-- regions while the pointer moves; the painter places everything from the
-- profile again after the single write on release.
-- Combat: EnableKeyboard and SetPropagateKeyboardInput are restricted
-- (SimpleFrameAPIDocumentation, wow-ui-source live). The controller is made
-- out of combat only, and PLAYER_REGEN_DISABLED, which fires before the
-- lockdown, drops the selection, the drag, the arrow bindings and the
-- keyboard; the editor shows no targets until combat ends.
local Move = {}
P.LootRollPreviewMove = Move
local S, M, Tr, Interaction = P.S, P.M, P.Tr, P.PreviewInteraction
local ID = "lootRolls"
local ELEMENTS = {}
for _, element in ipairs(P.Suite.LootRollElements) do ELEMENTS[element.id] = element end
Move.Elements = ELEMENTS
local REGIONS = { icon = "item", name = "name", details = "details", result = "status",
    remaining = "remaining", timer = "timer" }
local MOVE_HINT = "Drag or use arrows to move; click for settings."
local CLICK_HINT = "Click an element to open its settings."

local function Read(target)
    local config, element = S.Config(ID), target.element
    return config[element.xKey], config[element.yKey]
end

-- A drag may only commit into the profile, table and values it began under.
local function Current(editor)
    local claim, config = editor.claim, S.Config(ID)
    return claim ~= nil and claim.current() and claim.config == config
        and config[claim.element.xKey] == claim.x and config[claim.element.yKey] == claim.y
end

local function Write(editor, target, x, y, dragged)
    local element = target.element
    if not element or P.Combat() or not editor.ui.stage:IsVisible() or not target:IsShown() then return false end
    if editor.config ~= S.Config(ID) or (dragged and not Current(editor)) then return false end
    local rules = P.catalog[ID].rules
    local xRule, yRule = rules[element.xKey], rules[element.yKey]
    x = math.max(xRule.min, math.min(xRule.max, math.floor(x + .5)))
    y = math.max(yRule.min, math.min(yRule.max, math.floor(y + .5)))
    local oldX, oldY = Read(target)
    if x == oldX and y == oldY then return false end
    return P.SetMany(ID, { [element.xKey] = x, [element.yKey] = y }) ~= false
end

local function Reset(editor, target)
    local rules = target.element and P.catalog[ID].rules
    if not rules then return false end
    return Write(editor, target, rules[target.element.xKey].default, rules[target.element.yKey].default)
end

-- Every painted region of one element, in all rows.
local function Collect(view, element, out)
    for index = 1, view.viewCount or 0 do
        local row = view.rows[index]
        if row.frame:IsShown() and element.id == "buttons" then
            for _, action in ipairs(row.actions) do
                if action.button:IsShown() then out[#out + 1] = action.button end
            end
        elseif row.frame:IsShown() then
            out[#out + 1] = row[REGIONS[element.id]]
        end
    end
    return out
end

local function Claim(editor, target)
    local element, config = target.element, S.Config(ID)
    local claim = { target = target, element = element, current = P.ProfileGuard(), config = config,
        x = config[element.xKey], y = config[element.yKey], anchors = {} }
    for _, region in ipairs(Collect(editor.view, element, {})) do
        local points = { region = region }
        for index = 1, region:GetNumPoints() do points[index] = { region:GetPoint(index) } end
        claim.anchors[#claim.anchors + 1] = points
    end
    editor.claim = claim
end

local function Follow(editor, target, dx, dy)
    local claim = editor.claim
    if not claim or claim.target ~= target then return end
    if not Current(editor) then
        editor.kit:Cancel()
        return
    end
    if claim.drawX == dx and claim.drawY == dy then return end
    claim.drawX, claim.drawY = dx, dy
    for _, points in ipairs(claim.anchors) do
        local region = points.region
        region:ClearAllPoints()
        for _, point in ipairs(points) do region:SetPoint(point[1], point[2], point[3], point[4] + dx, point[5] + dy) end
    end
end

-- Outlines: the hovered target, the selected element in every row and a
-- layer whose chip is hovered. The rail names the hovered or selected layer.
function Move.Light(editor)
    local selected = editor.kit and editor.kit:Selected()
    local group = selected and selected.element
    for _, target in ipairs(editor.targets) do
        local lit = target == editor.hovered or (group ~= nil and target.element == group)
            or editor.spotlight == target.layer[1]
        Interaction.Outline(target, lit and target:IsShown())
    end
    local focus = editor.hovered or selected
    local key = focus and focus.layer[1] or nil
    if editor._msuf2SelectedPreviewLayerKey ~= key then
        editor._msuf2SelectedPreviewLayerKey = key
        Interaction.RefreshLayerRail(editor)
    end
end

local function Tip(editor, target, entering)
    if entering then editor.hovered = target elseif editor.hovered == target then editor.hovered = nil end
    Move.Light(editor)
end

-- Typed X/Y text belongs to the element it was typed for: commit it before
-- the selection moves (the bar commits to whatever is selected on blur).
local function Settle(editor)
    local bar, focus = editor.bar, GetCurrentKeyBoardFocus()
    if bar and focus and (focus == bar.editX or focus == bar.editY) then focus:ClearFocus() end
end

local Keyboard

-- The stage takes keys (Tab, Escape; arrows also come by binding) only while
-- an element is selected, so other key presses never pass through here.
local function Selected(editor)
    local selected = editor.kit and editor.kit:Selected()
    if selected and selected.element then P.LootRollPreviewProperties.Show(editor, selected.element.id) end
    Move.Light(editor)
    Keyboard(editor, editor.kit ~= nil and editor.kit:Selected() ~= nil and editor.ui.stage:IsVisible())
    if editor.bar then M.PreviewSelectionBar.Refresh(editor.ui.stage) end
end

local function Drag(editor, target, phase)
    if phase == "press" then
        Claim(editor, target)
    elseif phase == "done" or phase == "cancel" then
        editor.claim = nil
    end
end

local function Click(editor, target, moved)
    if moved or P.Combat() then return end
    P.LootRollPreviewEditor.Open(editor, target.layer)
end

local function Cycle(editor, backwards)
    if not editor.bar or editor.kit:Typing() then return false end
    return M.PreviewSelectionBar.CycleHandle(editor.ui.stage, backwards) == true
end

-- Arrows go to the host's handler; Tab and Escape stay with this preview.
local function KeyDown(editor, arrows, frame, key)
    if InCombatLockdown() then return false end
    if key ~= "TAB" and key ~= "ESCAPE" then return arrows(frame, key) end
    local consumed = false
    if key == "TAB" then
        consumed = Cycle(editor, IsShiftKeyDown())
    elseif editor.kit:Selected() then
        editor.kit:Release()
        consumed = true
    end
    frame:SetPropagateKeyboardInput(not consumed)
    return consumed
end

Keyboard = function(editor, enabled)
    local stage = editor.ui.stage
    enabled = enabled == true
    if not editor.kit or InCombatLockdown() or editor.keyboard == enabled then return end
    editor.keyboard = enabled
    stage:EnableKeyboard(enabled)
    stage:SetPropagateKeyboardInput(true)
end

local function Controller(editor)
    local ui = editor.ui
    local host = P.Suite.PreviewKit.NewHost(nil, { frame = ui.stage, paint = function() ui.Paint() end })
    local bindings = { ownerName = "MSUF_SuiteLootPreview_NudgeOwner", activeName = "MSUF_SuiteLootPreview_ActiveNudgeBox",
        buttonPrefix = "MSUF_SuiteLootPreview_Nudge", onClick = function(_, dx, dy) return editor.kit:Arrow(dx, dy) end }
    local kit = Interaction.Handles(host, {
        owner = ui.stage, threshold = 2, rekey = true, manualDrag = true, bindings = bindings,
        pointerHeld = function() return IsMouseButtonDown("LeftButton") end,
        combat = function() return P.Combat() or not ui.stage:IsVisible() end,
        tip = function(target, entering) Tip(editor, target, entering) end,
        select = function() Selected(editor) end,
        click = function(target, _, moved) Click(editor, target, moved) end,
        drag = function(target, phase) Drag(editor, target, phase) end,
        escape = function() editor.kit:Release() end,
        tab = function(backwards) return Cycle(editor, backwards) end,
    })
    local arrows = kit.opts.keydown
    if arrows then kit.opts.keydown = function(frame, key) return KeyDown(editor, arrows, frame, key) end end
    local baseSelect = kit.Select
    function kit:Select(target)
        if target ~= self:Selected() then Settle(editor) end
        return baseSelect(self, target)
    end
    editor.kit = kit
end

-- One kit entry per painted target. Rows open their look and never move.
local function Enroll(editor, target)
    local element = target.element
    editor.kit:Add(target, target, function() return Read(target) end,
        element and function(x, y, dragged) return Write(editor, target, x, y, dragged) end or nil, {
            select = element ~= nil, clicks = { "LeftButtonUp", "RightButtonUp" },
            follow = element and function(_, dx, dy) Follow(editor, target, dx, dy) end or nil,
        })
    target:HookScript("OnHide", function() Tip(editor, target, false) end)
    local rule = P.catalog[ID].rules[target.layer[3]]
    M.AddTooltip(target, Tr(rule.label), Tr(element and MOVE_HINT or CLICK_HINT), { hook = true })
    target.enrolled = true
end

function Move.Suspend(editor)
    if not editor.kit or InCombatLockdown() then return end
    Settle(editor)
    editor.kit:Release()
    editor.kit.opts.focus(editor.ui.stage, nil, false)
    editor.claim = nil
    Keyboard(editor, false)
end

-- Out of combat, after each paint: make the controller once, enroll new
-- targets, keep a stale drag from committing and list one target per element
-- for the X/Y bar's Tab cycle.
function Move.Bind(editor, view)
    editor.view = view
    if P.Combat() or InCombatLockdown() then return end
    if not editor.kit then
        Controller(editor)
        Keyboard(editor, false)
    end
    if editor.config ~= S.Config(ID) then
        Move.Suspend(editor)
        editor.config = S.Config(ID)
    end
    for _, target in ipairs(editor.targets) do
        if not target.enrolled then Enroll(editor, target) end
    end
    if editor.kit.drag and not Current(editor) then editor.kit:Cancel() end
    if editor.claim then editor.claim.drawX = nil end
    wipe(editor.movables)
    for _, element in ipairs(P.Suite.LootRollElements) do
        for _, target in ipairs(editor.byElement[element.id]) do
            if target:IsShown() then
                editor.movables[#editor.movables + 1] = target
                break
            end
        end
    end
    Selected(editor)
end

local function LayoutBar(bar, width)
    local compact = width < 600
    local function At(region, x, y, point)
        region:ClearAllPoints()
        region:SetPoint(point or "TOPLEFT", bar, point or "TOPLEFT", x, y)
    end
    bar:SetSize(width, compact and 60 or 28)
    At(bar.swatch, 10, -10)
    At(bar.label, 25, -5)
    bar.label:SetSize(compact and math.max(40, width - 230) or 132, 18)
    At(bar.axisX, compact and 10 or 163, compact and -34 or -3)
    At(bar.axisY, compact and 134 or 285, compact and -34 or -3)
    At(bar.openButton, -8, -5, "TOPRIGHT")
    bar.resetButton:ClearAllPoints()
    bar.resetButton:SetPoint("RIGHT", bar.openButton, "LEFT", -6, 0)
    return compact and 60 or 28
end

local function Bar(editor, parent, y, width)
    if not M.PreviewSelectionBar then return y end
    local stage = editor.ui.stage
    local bar = M.PreviewSelectionBar.Create(stage, {
        Tr = Tr, Theme = function() return P.T end,
        HandleList = function() return editor.movables end,
        HandleLabel = function(target) return target._label end,
        IsPlaced = function(target) return target:IsVisible() end,
        ReadOffsets = function(_, target) return Read(target) end,
        WriteOffsets = function(_, target, x, offsetY) return Write(editor, target, x, offsetY) end,
        NudgeDelta = function(_, dx, dy) return editor.kit ~= nil and editor.kit:Nudge(dx, dy) end,
        ResetOffsets = function(_, target) return Reset(editor, target) end,
        OpenSettings = function(_, target) return P.LootRollPreviewEditor.Open(editor, target.layer) end,
        SelectHandle = function(_, target)
            if not editor.kit or P.Combat() then return false end
            editor.kit:Select(target)
            return true
        end,
        UpdateHint = function() end,
    })
    bar:SetParent(parent)
    editor.bar = bar
    local height = LayoutBar(bar, width)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    return y - height - 8
end

function Move.Build(editor, parent, y, width)
    local stage = editor.ui.stage
    editor.movables, editor.config = {}, S.Config(ID)
    y = Bar(editor, parent, y, width)
    stage:HookScript("OnShow", function() stage:RegisterEvent("PLAYER_REGEN_DISABLED") end)
    stage:HookScript("OnHide", function() Move.Suspend(editor) end)
    stage:HookScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then Move.Suspend(editor) end
    end)
    if stage:IsVisible() then stage:RegisterEvent("PLAYER_REGEN_DISABLED") end
    return y
end
