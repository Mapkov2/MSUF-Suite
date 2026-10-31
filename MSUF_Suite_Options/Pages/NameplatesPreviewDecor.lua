local _, P = ...
local Style = P.Suite.NameplateStyle
local Draw = Style.Decor
local Preview = {}
P.NameplatesPreviewDecor = Preview
local ID = "nameplates"
local CONFIG = setmetatable({}, { __index = function(_, key) return P.Get(ID, key) end })

local function NativeScale()
    local value = C_CVar.GetCVar("nameplateSelectedScale")
    if not P.Suite.Public(value) then return 1 end
    return tonumber(value) or 1
end

-- The samples by their health bar: the editor's handle tip (NameplatesEditor.lua)
-- reports the mouse entering and leaving every handle.
local hovers = setmetatable({}, { __mode = "k" })

-- The mouseover highlight shows while the mouse is over the sample's health
-- bar, as over a live plate.
local function Hover(sample, on)
    local texture = sample.highlight
    if not (on and P.Get(ID, "mouseoverHighlight") and P.Get(ID, "look") ~= 2 and P.Get(ID, sample.prefix)) then
        if texture then texture:Hide() end
        return
    end
    if not texture then
        texture = Style.CreateHighlight(sample.bar)
        sample.highlight = texture
    end
    Style.PaintHighlight(texture, P.Get(ID, "mouseoverHighlightColor"))
    texture:Show()
end

function Preview.Build(editor, sample)
    sample.decor = { parent = sample.cell, health = sample.bar, cast = sample.cast, fillSource = sample.progress }
    hovers[sample.bar] = sample
    if editor.targetStateButton then return end
    local button = P.T.Button(editor.tools, "Target / non-target", 126, 20)
    button:SetPoint("RIGHT", editor.tools, "RIGHT", -114, 0)
    button:SetScript("OnClick", function()
        editor.targetSample = editor.targetSample == false
        editor:Paint()
    end)
    P.NameplatesEditorLayers.Register(button, "targetSample", "Target / non-target")
    editor.targetStateButton = button
    local focus = P.T.Button(editor.tools, "Focus sample", 96, 20)
    focus:SetPoint("RIGHT", editor.tools, "RIGHT", 0, 0)
    focus:SetScript("OnClick", function()
        editor.focusSample = not editor.focusSample
        editor:Paint()
    end)
    P.NameplatesEditorLayers.Register(focus, "focusSample", "Focus sample")
    editor.focusStateButton = focus
    local function LayoutTools()
        local width = editor.tools:GetWidth()
        editor.tools:SetHeight(46)
        editor.contextButton:ClearAllPoints()
        editor.contextButton:SetPoint("BOTTOMLEFT", editor.tools, "BOTTOMLEFT", 0, 0)
        editor.contextButton:SetWidth(width < 500 and 96 or 128)
        button:ClearAllPoints()
        focus:ClearAllPoints()
        button:SetPoint("BOTTOMRIGHT", editor.tools, "BOTTOMRIGHT", -102, 0)
        focus:SetPoint("BOTTOMRIGHT", editor.tools, "BOTTOMRIGHT", 0, 0)
    end
    editor.LayoutDecorTools = LayoutTools
    editor.tools:HookScript("OnSizeChanged", LayoutTools)
    LayoutTools()
end

function Preview.Hover(handle, on)
    local sample = hovers[handle]
    if sample then Hover(sample, on) end
end

function Preview.Paint(editor, s, m)
    if editor.targetStateButton then
        editor.targetStateButton:SetAlpha(editor.targetSample ~= false and 1 or 0.5)
        editor.focusStateButton:SetAlpha(editor.focusSample and 1 or 0.5)
    end
    local p = Draw.Plan(CONFIG, s.prefix)
    if not editor:LayerOn("outerFrame") then p.outer = false end
    if not editor:LayerOn("shadow") then p.shadow = false end
    if not editor:LayerOn("glow") then p.glow = 1 end
    if not editor:LayerOn("fillTexture") then p.texture = nil end
    if not editor:LayerOn("threshold") then p.threshold = false end
    if not editor:LayerOn("focusMarker") then p.focus = false end
    local scale = s.state.target and Draw.TargetScale(CONFIG, NativeScale()) or 1
    s.cell:SetScale(scale)
    if m.namesOnly or not editor:LayerOn("health") or P.Get(ID, "look") == 2 or not P.Get(ID, s.prefix) then
        Draw.Hide(s.decor)
        return
    end
    Draw.Paint(s.decor, p, s.state.target, editor.focusSample == true, m.showCast)
end
