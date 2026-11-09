local _, NS = ...
local S = NS.Suite
local Controls = {}
NS.ModelControls = Controls

local BUTTON_SIZE, GAP, ICON_SIZE = 20, 3, 12
local FULL_TURN, BUTTON_TURN, DRAG_TURN = 2 * math.pi, math.pi / 12, .01
local ZOOM_STEP, MAX_ZOOM = .15, .8
local Number, min, max = NS.Number, math.min, math.max

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
        Rotate(model, (cursor - model.rotationCursor) * DRAG_TURN)
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
    if steps then Zoom(model, steps) end
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
    toolbar:SetPoint("TOP", 0, -5)
    toolbar:SetSize(#BUTTONS * (BUTTON_SIZE + GAP) - GAP, BUTTON_SIZE)
    for i, control in ipairs(BUTTONS) do
        local button = makeButton(view, toolbar, "", Click)
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

function Controls.Attach(view, makeButton)
    local model = view.model
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
