local _, NS = ...

-- Shared LibSettingsDesigner chrome, including Enhance QoL's Config Center.
-- The library and the addons keep their data, layout and input handlers.
local Skin = {}
NS.EnhanceQoLSkin = Skin
NS.AddonSkinDesigner = Skin
local Safety, Visuals = NS.Safety, NS.AddonSkinVisuals
local hooked = setmetatable({}, { __mode = "k" })

local function Capture(region)
    if Safety.Read(region, "IsShown") ~= true then return end
    local owner = NS.Cosmetics.GetOwner(region)
    if owner ~= nil then NS.Cosmetics.CaptureNativeAlpha(region, owner) end
end

function Skin.NativeBackgroundChanged(frame)
    -- These callbacks follow the library's actual background-alpha writes.
    -- Other decoration such as MaterialOverlay only changes vertex color.
    for _, key in ipairs({ "bg", "SidebarBackgroundTexture", "ContentBackgroundTexture" }) do
        Capture(Safety.Field(frame, key))
    end
end

local function Changed(state)
    local record = hooked[state]
    if record and NS.AddonSkins.IsEnabled(record.id) and not NS.AddonSkins.cooperative[record.id] then
        NS.AddonSkins.RefreshFrame(record.frame)
    end
end

local function Observe(state, frame, id)
    if type(state) ~= "table" then return end
    local record = hooked[state]
    if not record then record = { methods = {} } hooked[state] = record end
    record.frame, record.id = frame, id
    for _, key in ipairs({ "RenderContent", "RenderSidebar", "SetPage", "SetCategory" }) do
        if Safety.HasMethod(state, key) and record.methods[key] ~= Safety.Field(state, key) then
            hooksecurefunc(state, key, Changed)
            record.methods[key] = Safety.Field(state, key)
        end
    end
end

local function Visit(frame, owner, budget, depth)
    if budget <= 0 then return 0 end
    budget = budget - 1
    if depth > 12 or not Visuals.Safe(frame) then return budget end
    local kind = Safety.Read(frame, "GetObjectType")
    if kind == "Frame" or kind == "Button" then
        local parts = Safety.Field(frame, "_LibSettingsDesignerTextureStyleParts")
        if type(parts) == "table" then
            for _, groupName in ipairs({ "Fill", "Border" }) do
                local group = Safety.Field(parts, groupName)
                for _, key in ipairs({ "L", "M", "R" }) do Visuals.Fade(Safety.Field(group, key), owner) end
            end
        end
        if type(parts) == "table" or Safety.Field(frame, "_LibSettingsDesignerBackdropDefinition")
            or Safety.Field(frame, "SidebarBackgroundTexture") or Safety.Field(frame, "ContentBackgroundTexture") then
            Visuals.Panel(frame, owner, kind == "Button" and "button" or "panel")
        end
    end
    for _, child in ipairs({ Safety.Call(frame, "GetChildren") }) do
        if budget <= 0 then break end
        budget = Visit(child, owner, budget, depth + 1)
    end
    return budget
end

function Skin.Paint(frame, owner, id)
    Observe(Safety.Field(frame, "_LibSettingsDesignerState"), frame, id or "enhanceQoL")
    Visuals.Fade(Safety.Field(frame, "bg"), owner)
    Visuals.Fade(Safety.Field(frame, "MaterialOverlay"), owner)
    local border = Safety.Field(frame, "WindowBorder")
    if type(border) == "table" then for _, region in pairs(border) do Visuals.Fade(region, owner) end end
    Visit(frame, owner, 640, 0)
end
