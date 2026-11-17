local _, NS = ...

-- AceGUI is a widget pool, not a Blizzard frame tree. Its dropdowns live
-- outside their window and its anonymous chrome needs explicit treatment.
local Widgets = {}
NS.AceWidgets = Widgets
local Safety, Visuals = NS.Safety, NS.AddonSkinVisuals
local labels = { "text", "label", "titletext", "statustext", "lowtext", "hightext" }
local panels = { "border", "treeframe", "scrollBG" }
local art = { "titlebg", "left", "middle", "right" }
local windowArt = { [251966] = true, [137056] = true, [251963] = true,
    ["interface\\paperdollinfoframe\\ui-gearmanager-title-background"] = true,
    ["interface\\paperdollinfoframe\\ui-gearmanager-border"] = true,
    ["interface\\tooltips\\ui-tooltip-background"] = true }
local buttonSpec = { role = "button", allowImplicitProtected = false }
local tabSpec = { role = "navigation", allowImplicitProtected = false }

local function Button(frame, owner, tab)
    if Visuals.Safe(frame) and Safety.HasMethod(frame, "SetHighlightTexture") then
        NS.ControlSkin.ApplyButton(frame, owner, tab and tabSpec or buttonSpec)
    end
end

local function WindowRegions(owner, ...)
    for index = 1, math.min(select("#", ...), 64) do
        local region = select(index, ...)
        if Safety.Read(region, "GetObjectType") == "Texture" then
            local texture = Safety.Read(region, "GetTexture")
            if type(texture) == "string" then texture = texture:lower() end
            if texture and windowArt[texture] then NS.Cosmetics.Fade(region, owner) end
        end
    end
end

local function CheckBox(widget, owner)
    Visuals.Tint(Safety.Field(widget, "checkbg"), owner, "buttonBorder")
    Visuals.Tint(Safety.Field(widget, "check"), owner, "checkmark")
    Visuals.Tint(Safety.Field(widget, "highlight"), owner, "accent")
end

local function RootButtons(widget, owner, ...)
    for index = 1, math.min(select("#", ...), 32) do
        local child = select(index, ...)
        if child ~= Safety.Field(widget, "title") and Safety.Read(child, "GetObjectType") == "Button"
            and (NS.Checkmarks.GetWindowAction(child) or type(Safety.Read(child, "GetText")) == "string") then
            Button(child, owner)
        end
    end
end

local function Scrollbar(scrollbar, owner)
    if not Visuals.Safe(scrollbar) then return end
    if Safety.Read(scrollbar, "GetObjectType") == "Slider" then
        -- Ace's legacy UIPanelScrollBarTemplate is deliberately outside the
        -- modern ScrollBarSkin contract. Keep its native range, thumb and
        -- stepper scripts; only style its exposed decorative parts.
        Visuals.Backdrop(scrollbar, owner, "input")
        Visuals.Tint(Safety.Read(scrollbar, "GetThumbTexture"), owner, "accent")
        Button(Safety.Field(scrollbar, "ScrollUpButton"), owner)
        Button(Safety.Field(scrollbar, "ScrollDownButton"), owner)
    else
        NS.ScrollBarSkin.Apply(scrollbar, owner)
    end
end

local function Collections(widget, owner)
    for _, key in ipairs({ "tabs", "buttons" }) do
        local list = Safety.Field(widget, key)
        if type(list) == "table" then
            for index = 1, math.min(#list, 128) do
                local item = list[index]
                local frame = Safety.Field(item, "frame") or item
                Button(frame, owner, true)
                Visuals.Label(Safety.Field(item, "text"), owner)
            end
        end
    end
end

function Widgets.Apply(widget, owner)
    Visuals.Close(widget, owner)
    local frame = Safety.Field(widget, "frame")
    if not Visuals.Safe(frame) then return false end
    local kind = Safety.Field(widget, "type")
    for index = 1, #labels do Visuals.Label(Safety.Field(widget, labels[index]), owner) end
    for index = 1, #panels do Visuals.Backdrop(Safety.Field(widget, panels[index]), owner, "panel") end
    if kind == "Frame" or kind == "Window" then
        Visuals.Backdrop(frame, owner, "shell")
        WindowRegions(owner, Safety.Call(frame, "GetRegions"))
        Visuals.Backdrop(Safety.Read(Safety.Field(widget, "statustext"), "GetParent"), owner, "panel")
        RootButtons(widget, owner, Safety.Call(frame, "GetChildren"))
    elseif kind == "Button" then Button(frame, owner)
    elseif kind == "CheckBox" then CheckBox(widget, owner)
    end
    if kind ~= "Frame" and kind ~= "Window" then Visuals.Backdrop(frame, owner, "panel") end
    for index = 1, #art do
        local region = Safety.Field(widget, art[index])
        if Safety.Read(region, "GetObjectType") == "Texture" then NS.Cosmetics.Fade(region, owner) end
    end
    Visuals.Backdrop(Safety.Field(widget, "slider"), owner, "input")
    Scrollbar(Safety.Field(widget, "scrollbar"), owner)
    local edit = Safety.Field(widget, "editbox")
    if Visuals.Safe(edit) then NS.ControlSkin.ApplySearchBox(edit, owner, { allowImplicitProtected = false }) end
    Visuals.Backdrop(edit, owner, "input")
    local dropdown = Safety.Field(widget, "dropdown")
    if Visuals.Safe(dropdown) then Visuals.Surface(dropdown, owner, "input") end
    Button(Safety.Field(widget, "button"), owner)
    Collections(widget, owner)
    return true
end

function Widgets.Release(_, owner)
    if owner then Visuals.Release(owner) end
end
