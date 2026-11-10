local _, NS = ...
local S = NS.Suite
local Controls = {}
NS.ModelControls = Controls

local BUTTON_SIZE, GAP, ICON_SIZE = 20, 3, 12
local FULL_TURN, BUTTON_TURN, DRAG_TURN = 2 * math.pi, math.pi / 12, .01
local ZOOM_STEP, MAX_ZOOM = .15, .8
local Number, min, max = NS.Number, math.min, math.max

function Controls.CanBindUnit(unit)
    if not NS.Host.InCombat() then return true end
    if unit ~= "player" then return false end
    local restricted = C_Secrets.ShouldUnitIdentityBeSecret(unit)
    return NS.Public(restricted) and restricted == false
end

local function SetRotation(model, rotation)
    if model.controlRotation == rotation then return end
    model.controlRotation = rotation
    model:SetRotation(rotation)
end

local function SetZoom(model, zoom)
    if model.controlZoom == zoom then return end
    model.controlZoom = zoom
    model:SetPortraitZoom(zoom)
end

local function Rotate(model, amount)
    SetRotation(model, (model.controlRotation + amount) % FULL_TURN)
end

local function Zoom(model, steps)
    SetZoom(model, max(0, min(MAX_ZOOM, model.controlZoom + steps * ZOOM_STEP)))
end

local function Reset(model)
    SetZoom(model, 0)
    SetRotation(model, 0)
end

local function NativeCamera()
    local scene = CharacterModelScene
    if not NS.Public(scene) or not scene or not scene:IsVisible() then return end
    local camera = scene:GetActiveCamera()
    if NS.Public(camera) then return camera end
end

local function NativeRotate(amount)
    local camera = NativeCamera()
    if not camera or type(camera.GetYaw) ~= "function" or type(camera.SetYaw) ~= "function" then return end
    local yaw = Number(camera:GetYaw())
    if yaw then camera:SetYaw(yaw + amount) end
end

local function NativeZoom(amount)
    local camera = NativeCamera()
    if camera then camera:OnMouseWheel(amount) end
end

local function StopDrag(model)
    if model.rotationCursor == nil then return end
    model.rotationCursor = nil
    model:SetScript("OnUpdate", nil)
end

local function UpdateDrag(model)
    if not IsMouseButtonDown("LeftButton") then
        StopDrag(model)
        return
    end
    local cursor = Number((GetCursorPosition()))
    if cursor and cursor ~= model.rotationCursor then
        local amount = (cursor - model.rotationCursor) * DRAG_TURN
        if model.nativeScene then NativeRotate(amount) else Rotate(model, amount) end
        model.rotationCursor = cursor
    end
end

local function BeginDrag(model, button)
    if button ~= "LeftButton" or not model.ready or model.rotationCursor ~= nil then return end
    model.rotationCursor = Number((GetCursorPosition()))
    if model.rotationCursor then model:SetScript("OnUpdate", UpdateDrag) end
end

local function EndDrag(model, button)
    if button == "LeftButton" then StopDrag(model) end
end

local function Wheel(model, delta)
    if not model.ready then return end
    local steps = Number(delta)
    if not steps then return end
    if model.nativeScene then NativeZoom(steps) else Zoom(model, steps) end
end

local BUTTONS = {
    { atlas = "common-icon-rotateleft", tooltip = "ROTATE_LEFT", apply = Rotate, amount = -BUTTON_TURN },
    { atlas = "common-icon-rotateright", tooltip = "ROTATE_RIGHT", apply = Rotate, amount = BUTTON_TURN },
    { atlas = "common-icon-zoomout", tooltip = "ZOOM_OUT", apply = Zoom, amount = -1 },
    { atlas = "common-icon-zoomin", tooltip = "ZOOM_IN", apply = Zoom, amount = 1 },
    { atlas = "common-icon-undo", tooltip = "RESET_POSITION", apply = Reset },
}

local function Click(button)
    local model, control = button.model, button.control
    if model.ready then control.apply(model, control.amount) end
end

local function ClickNative(button)
    local scene, control = CharacterModelScene, button.control
    if control.apply == Zoom then NativeZoom(control.amount)
    elseif control.apply == Rotate then NativeRotate(control.amount)
    elseif NS.Public(scene) and scene and scene:IsVisible() and not NS.Host.InCombat() then scene:Reset() end
end

local function ShowTooltip(button)
    if not button.tooltipText then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(button.tooltipText)
    GameTooltip:Show()
end

local function HideTooltip(button)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function MakeToolbar(view, makeButton)
    local toolbar = S.CreateFrame("Frame", nil, view.modelHost)
    -- The native slot hit spans cross the model. Keep the toolbar above
    -- the same masks as the viewport input, below the report cover.
    if view.modelInput then toolbar:SetFrameLevel(view.modelInput:GetFrameLevel() + 1) end
    toolbar:SetPoint("TOP", 0, -5)
    toolbar:SetSize(#BUTTONS * (BUTTON_SIZE + GAP) - GAP, BUTTON_SIZE)
    local click = view.nativeLayout and ClickNative or Click
    for i, control in ipairs(BUTTONS) do
        local button = makeButton(view, toolbar, "", click)
        button.model, button.control, button.tooltipText = view.model, control, _G[control.tooltip]
        button:SetPoint("LEFT", (i - 1) * (BUTTON_SIZE + GAP), 0)
        button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        local icon = S.CreateTexture(button, nil, "ARTWORK")
        icon:SetAtlas(control.atlas)
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("CENTER")
        button:HookScript("OnEnter", ShowTooltip)
        button:HookScript("OnLeave", HideTooltip)
        button:HookScript("OnHide", HideTooltip)
    end
end

local function AttachNativeInput(view)
    local plan = view.nativeLayout
    local rect = plan.model
    local input = NS.Window.CreateChild(view, "Frame", view.modelHost)
    input:SetPoint("TOPLEFT", view.frame, "TOPLEFT", rect.x, -rect.y)
    input:SetSize(rect.width, rect.height)
    -- The inactive right-slot hit span crosses the model. Capture only the viewport.
    input:SetFrameLevel(NS.Window.NativeLevel(view, plan.slotLevel + 2))
    input.nativeScene, input.ready = true, true
    view.modelInput = input
    return input
end

function Controls.Attach(view, makeButton)
    local model = view.model or AttachNativeInput(view)
    model.controlRotation, model.controlZoom = 0, 0
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model:SetScript("OnMouseDown", BeginDrag)
    model:SetScript("OnMouseUp", EndDrag)
    model:SetScript("OnMouseWheel", Wheel)
    model:HookScript("OnHide", StopDrag)
    MakeToolbar(view, makeButton)
end

-- SetUnit and RefreshUnit can reinitialize the native camera.
function Controls.Apply(view)
    local model = view.model
    if model.controlUnit ~= view.unit or model.controlIdentity ~= view.identity then
        StopDrag(model)
        model.controlUnit, model.controlIdentity = view.unit, view.identity
        model.controlRotation, model.controlZoom = 0, 0
    end
    model:SetPortraitZoom(model.controlZoom)
    model:SetRotation(model.controlRotation)
end
