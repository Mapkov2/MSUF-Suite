local _, NS = ...

-- Resolve parts of the submitted widget and known art on its standard steppers.
local Widgets = {}
NS.PublicWidgets = Widgets
local S = NS.Safety
local function Field(object, key)
    if not S.Public(object) or type(object) ~= "table" or S.IsForbidden(object) then return end
    local value = S.Field(object, key)
    if S.Public(value) and type(value) == "table" then return value end
end

function Widgets.Belongs(root, part)
    for _ = 1, 16 do
        if not S.Public(part) or not part then return false end
        if part == root then return true end
        part = S.Read(part, "GetParent")
    end
    return false
end

function Widgets.Safe(part)
    return S.Public(part) and S.CanDecorate(part) and not S.IsCompositorManaged(part)
end

local function Part(plan, part, role)
    if not S.Public(part) then plan.error = "protected-target" return end
    if part == nil then return end
    if not Widgets.Safe(part) then plan.error = "protected-target" return end
    if not Widgets.Belongs(plan.root, part) then plan.error = "foreign-region" return end
    if part ~= plan.root then plan.parts[part] = true end
    if not role then return part end
    local text = S.Read(part, "GetObjectType") == "FontString"
    local getter = text and "GetTextColor" or "GetVertexColor"
    local setter = text and "SetTextColor" or "SetVertexColor"
    if not S.HasMethod(part, setter) or not S.ReadColor(part, getter) then return end
    plan.colors[part] = { role = role, getter = getter, setter = setter }
    return part
end

local stateTextures = {
    GetNormalTexture = "borderSoft", GetHighlightTexture = "hover",
    GetPushedTexture = "accentBright", GetDisabledTexture = "disabled",
}
local function ButtonArt(plan, button, skipNamedArrow)
    if not Part(plan, button) then return end
    for getter, role in pairs(stateTextures) do Part(plan, S.Read(button, getter), role) end
    if not skipNamedArrow then Part(plan, Field(button, "Texture"), "blizzardArrow") end
    return true
end

local function Dropdown(plan, options)
    local root = plan.root
    local trigger = options.trigger or Field(root, "Button") or root
    if not Part(plan, trigger) or not S.HasMethod(trigger, "GetButtonState") then return false end
    plan.trigger = trigger
    local label = options.label or S.Read(root, "GetFontString") or Field(root, "Text") or Field(root, "Label")
    Part(plan, label, "label")
    local arrow = options.arrow or Field(root, "Arrow") or Field(trigger, "Arrow") or Field(trigger, "Icon")
    Part(plan, arrow, "arrow")
    ButtonArt(plan, trigger)
    for _, key in ipairs({ "Background", "Left", "Middle", "Right" }) do
        local decor = Field(root, key)
        if decor and S.Read(decor, "GetObjectType") == "Texture" and Part(plan, decor) then
            plan.fades = plan.fades or {}
            plan.fades[decor] = true
        end
    end
    local filter = WowStyle1FilterDropdownMixin
    local getBackgroundAtlas = S.ReadableMethod(root, "GetBackgroundAtlas")
    plan.filterArrow = not arrow and plan.fades and plan.fades[Field(root, "Background")]
        and S.HasMethod(filter, "GetBackgroundAtlas")
        and S.Public(getBackgroundAtlas) and getBackgroundAtlas == filter.GetBackgroundAtlas
    -- Some modern triggers supply the complete arrow art as state textures.
    for _, key in ipairs({ "NormalTexture", "PushedTexture", "HighlightTexture", "DisabledTexture" }) do
        Part(plan, Field(trigger, key), key == "DisabledTexture" and "disabled" or "arrow")
    end
    return S.HasMethod(root, "CreateTexture") and S.HasMethod(trigger, "HookScript")
end

local function StepperAtlasRegion(button, atlas, ...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if Widgets.Safe(region) and S.Read(region, "GetParent") == button and S.Read(region, "GetAtlas") == atlas then
            return region
        end
    end
end

local function Stepper(plan, button, explicitArt, atlas)
    if not ButtonArt(plan, button, true) then
        if explicitArt then plan.error = plan.error or "missing-stepper" end
        return
    end
    local art = explicitArt or Field(button, "Texture")
    if not art and atlas then art = StepperAtlasRegion(button, atlas, S.Call(button, "GetRegions")) end
    if not art then return end
    if not Widgets.Belongs(button, art) then
        plan.error = "foreign-region"
        return
    end
    local region = Part(plan, art, "blizzardArrow")
    if region and S.HasMethod(button, "IsEnabled") then
        plan.colors[region].input = button
        return button
    end
end

local function CheckButton(plan, options)
    local root = plan.root
    if S.Read(root, "GetObjectType") ~= "CheckButton" then return false end
    ButtonArt(plan, root)
    local checked = options.indicator or S.Read(root, "GetCheckedTexture") or Field(root, "CheckedTexture")
    local mark = Part(plan, checked, "checkmark")
    Part(plan, S.Read(root, "GetDisabledCheckedTexture") or Field(root, "DisabledCheckedTexture"), "disabled")
    Part(plan, options.label or S.Read(root, "GetFontString") or Field(root, "Text"), "text")
    return mark ~= nil
end

local function Slider(plan, options)
    local root = plan.root
    local slider = Field(root, "Slider")
    if not slider or S.Read(slider, "GetObjectType") ~= "Slider" then slider = root end
    if not Part(plan, slider) or S.Read(slider, "GetObjectType") ~= "Slider" then return false end
    local thumb = Part(plan, options.thumb or S.Read(slider, "GetThumbTexture") or Field(slider, "Thumb"), "accentBright")
    if not thumb then return false end
    plan.slider = slider
    local track = options.track or Field(slider, "Track") or Field(slider, "Background")
    if track and not Part(plan, track, "borderSoft") and Part(plan, track) then
        for _, key in ipairs({ "Begin", "Middle", "End" }) do Part(plan, Field(track, key), "borderSoft") end
    end
    for _, key in ipairs({ "Left", "Middle", "Right", "Top", "Bottom" }) do Part(plan, Field(slider, key), "borderSoft") end
    for _, spec in pairs(plan.colors) do
        if spec.role == "borderSoft" then plan.hasTrack = true break end
    end
    local nativeBack, nativeForward = Field(root, "Back"), Field(root, "Forward")
    local back = options.back or nativeBack or Field(root, "ScrollUpButton")
    local forward = options.forward or nativeForward or Field(root, "ScrollDownButton")
    plan.back = Stepper(plan, back, options.backArt, slider ~= root and back == nativeBack and "Minimal_SliderBar_Button_Left")
    plan.forward = Stepper(plan, forward, options.forwardArt,
        slider ~= root and forward == nativeForward and "Minimal_SliderBar_Button_Right")
    return true
end

local builders = { dropdown = Dropdown, checkButton = CheckButton, slider = Slider }
function Widgets.Describe(root, kind, options)
    local plan = { root = root, kind = kind, colors = {}, parts = {} }
    if kind == "scrollBar" and not S.HasMethod(root, "GetThumbTexture") and not Field(root, "Slider") then
        local pieces, contract = NS.ScrollBarSkin.PublicParts(root)
        if not pieces then return nil, "unsupported-scrollbar" end
        for _, piece in ipairs(pieces) do Part(plan, piece) end
        plan.nativeBar = contract
    else
        local builder = builders[kind] or (kind == "scrollBar" and Slider)
        if not builder or not builder(plan, options) then return nil, plan.error or "unsupported-control" end
    end
    if plan.error then return nil, plan.error end
    return plan
end
