local _, NS = ...

-- Foreign windows keep their input, layout and semantic artwork. Only exact
-- backdrop pieces and explicitly supplied labels/controls are decorated.
local Visuals = { owners = {} }
NS.AddonSkinVisuals = Visuals
local Safety = NS.Safety
local textBindings = setmetatable({}, { __mode = "k" })
local textHooks = setmetatable({}, { __mode = "k" })
local pieces = { "Center", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }
local specs = {
    shell = { role = "shell", allowImplicitProtected = false },
    panel = { role = "panel", allowImplicitProtected = false },
    input = { role = "input", radius = 4, allowImplicitProtected = false },
    button = { role = "button", radius = 4, interactive = true, allowImplicitProtected = false },
}
local implicitSpecs = {}
for role, spec in pairs(specs) do
    local copy = {}
    for key, value in pairs(spec) do copy[key] = value end
    copy.allowImplicitProtected = true
    implicitSpecs[role] = copy
end

local function Owned(owner)
    local state = Visuals.owners[owner]
    if not state then
        state = { surfaces = setmetatable({}, { __mode = "k" }), labels = setmetatable({}, { __mode = "k" }),
            tints = setmetatable({}, { __mode = "k" }), textColors = setmetatable({}, { __mode = "k" }) }
        Visuals.owners[owner] = state
    end
    return state
end

function Visuals.Safe(target, allowImplicitProtected)
    return Safety.Public(target) and Safety.CanCreateRegions(target, allowImplicitProtected)
end

function Visuals.Surface(target, owner, role, allowImplicitProtected)
    if not Visuals.Safe(target, allowImplicitProtected) then return false end
    local styles = allowImplicitProtected and implicitSpecs or specs
    if not NS.Surface.Attach(target, styles[role] or styles.panel) then return false end
    NS.Surface.SetVisible(target, true)
    Owned(owner).surfaces[target] = true
    return true
end

function Visuals.Label(label, owner)
    if not NS.LabelStyle.CanStyle(label) then return end
    NS.LabelStyle.Apply(label, owner)
    Owned(owner).labels[label] = true
end

local function FollowText(label)
    local record = textBindings[label]
    if not record or record.painting or not NS.LabelStyle.CanStyle(label) then return end
    local r, g, b, a = Safety.ReadColor(label, "GetTextColor")
    if not r or Safety.SameColor(r, g, b, a, unpack(record.applied)) then return end
    record.original = { r, g, b, a }
    record.painting = true
    label:SetTextColor(unpack(record.applied))
    record.painting = nil
end

function Visuals.Text(label, owner, token)
    if not NS.LabelStyle.CanStyle(label) then return end
    local binding = textBindings[label]
    if binding and binding.owner ~= owner then return end
    local r, g, b, a = Safety.ReadColor(label, "GetTextColor")
    if not r then return end
    local colors = Owned(owner).textColors
    local record = colors[label]
    if not record then record = { owner = owner, original = { r, g, b, a }, applied = {} } colors[label] = record end
    local previous = record.applied
    if previous[1] and not Safety.SameColor(r, g, b, a, unpack(previous)) then
        record.original = { r, g, b, a }
    end
    local red, green, blue = NS.Theme.GetColor(token or "text")
    previous[1], previous[2], previous[3], previous[4] = red, green, blue, a
    textBindings[label] = record
    if not textHooks[label] then
        textHooks[label] = true
        hooksecurefunc(label, "SetTextColor", FollowText)
    end
    record.painting = true
    if not Safety.SameColor(r, g, b, a, red, green, blue, a) then label:SetTextColor(red, green, blue, a) end
    record.painting = nil
    Visuals.Label(label, owner)
end

function Visuals.Fade(region, owner, allowImplicitProtected)
    if Safety.Read(region, "GetObjectType") == "Texture" and Safety.CanDecorate(region, allowImplicitProtected) then
        NS.Cosmetics.Fade(region, owner)
    end
end

function Visuals.Close(frame, owner, allowImplicitProtected)
    for _, key in ipairs({ "CloseButton", "CustomCloseButton", "closeButton", "closebutton" }) do
        local button = Safety.Field(frame, key)
        if Visuals.Safe(button, allowImplicitProtected) and Safety.Read(button, "GetObjectType") == "Button" then
            local text = Safety.Read(button, "GetText")
            if text == nil or text == "" or text == "X" or text == "x" or text == "×" or text == "✕" then
                NS.WindowActionSkin.Apply(button, owner, "close")
            end
        end
    end
end

-- Only call for a reviewed decorative panel; semantic pictures are excluded.
function Visuals.Panel(frame, owner, role, allowImplicitProtected)
    if not Visuals.Safe(frame, allowImplicitProtected) then return end
    Visuals.Backdrop(frame, owner, role, allowImplicitProtected)
    for _, key in ipairs({ "Bg", "Background", "background", "backgroundTexture",
        "SidebarBackgroundTexture", "ContentBackgroundTexture" }) do
        Visuals.Fade(Safety.Field(frame, key), owner)
    end
    local slice = Safety.Field(frame, "NineSlice")
    for index = 1, #pieces do Visuals.Fade(Safety.Field(slice, pieces[index]), owner) end
    Visuals.Surface(frame, owner, role or "panel", allowImplicitProtected)
end

function Visuals.Tint(region, owner, token)
    if not Safety.CanDecorate(region) or not Safety.HasMethod(region, "SetVertexColor") then return end
    local tints = Owned(owner).tints
    local state = tints[region]
    if not state then
        local r, g, b, a = Safety.ReadColor(region, "GetVertexColor")
        if not r then return end
        state = { original = { r, g, b, a }, applied = {} }
        tints[region] = state
    end
    local r, g, b = NS.Theme.GetColor(token)
    local color = state.applied
    color[1], color[2], color[3], color[4] = r, g, b, state.original[4]
    region:SetVertexColor(r, g, b, color[4])
end

function Visuals.Backdrop(frame, owner, role, allowImplicitProtected)
    if not Visuals.Safe(frame, allowImplicitProtected) or not Safety.Read(frame, "GetBackdrop") then return false end
    -- BackdropTemplate owns these nine texture members. Never hide the frame:
    -- its text, icons and mouse targets must remain visible and functional.
    for index = 1, #pieces do
        local region = Safety.Field(frame, pieces[index])
        if Safety.Read(region, "GetObjectType") == "Texture" then NS.Cosmetics.Fade(region, owner) end
    end
    return Visuals.Surface(frame, owner, role, allowImplicitProtected)
end

local function Regions(frame, owner, ...)
    for index = 1, select("#", ...) do
        if index > 64 then break end
        Visuals.Label(select(index, ...), owner)
    end
end

local Visit
local function Children(owner, depth, budget, allowImplicitProtected, ...)
    for index = 1, select("#", ...) do
        if budget <= 0 then break end
        budget = Visit(select(index, ...), owner, depth, budget, allowImplicitProtected)
    end
    return budget
end

Visit = function(frame, owner, depth, budget, allowImplicitProtected)
    if budget <= 0 then return budget end
    budget = budget - 1
    if not Visuals.Safe(frame, allowImplicitProtected) then return budget end
    Visuals.Backdrop(frame, owner, depth == 0 and "shell" or "panel", allowImplicitProtected)
    for _, key in ipairs({ "backdrop", "backgroundTexture" }) do
        local region = Safety.Field(frame, key)
        if Safety.Read(region, "GetObjectType") == "Texture" then NS.Cosmetics.Fade(region, owner) end
    end
    Regions(frame, owner, Safety.Call(frame, "GetRegions"))
    if depth < 6 then budget = Children(owner, depth + 1, budget, allowImplicitProtected, Safety.Call(frame, "GetChildren")) end
    return budget
end

function Visuals.Tree(frame, owner, maxNodes, allowImplicitProtected)
    return Visit(frame, owner, 0, maxNodes or 480, allowImplicitProtected)
end

function Visuals.Release(owner)
    local state = Visuals.owners[owner]
    if state then
        for frame in pairs(state.surfaces) do NS.Surface.SetVisible(frame, false) end
        for label in pairs(state.labels) do NS.LabelStyle.Release(label, owner) end
        for label, record in pairs(state.textColors) do
            if textBindings[label] == record then textBindings[label] = nil end
            local r, g, b, a = Safety.ReadColor(label, "GetTextColor")
            if Safety.SameColor(r, g, b, a, unpack(record.applied)) then label:SetTextColor(unpack(record.original)) end
        end
        for region, tint in pairs(state.tints) do
            local r, g, b, a = Safety.ReadColor(region, "GetVertexColor")
            local color = tint.applied
            if Safety.SameColor(r, g, b, a, color[1], color[2], color[3], color[4]) then
                region:SetVertexColor(unpack(tint.original))
            end
        end
    end
    NS.Cosmetics.RestoreOwner(owner)
    NS.ControlSkin.DisableOwner(owner)
    NS.ScrollBarSkin.DisableOwner(owner)
    NS.WindowActionSkin.DisableOwner(owner)
    Visuals.owners[owner] = nil
end
