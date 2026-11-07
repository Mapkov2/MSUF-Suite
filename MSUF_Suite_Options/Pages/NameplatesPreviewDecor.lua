local _, P = ...
local Style = P.Suite.NameplateStyle
local Draw = Style.Decor
local Preview = {}
P.NameplatesPreviewDecor = Preview
local ID = "nameplates"
local CONFIG = setmetatable({}, { __index = function(_, key) return P.Get(ID, key) end })

local function Styled(prefix)
    return P.Get(ID, "look") ~= 2 and P.Get(ID, prefix)
end

function Preview.LevelMode(editor, prefix, classic, namesOnly)
    local forever = P.Suite.Client.isForever
    local badge = forever == true
    local otherPlayer = prefix == "enemy" and editor.enemyPlayer
        or prefix == "friendly" and editor.friendlyOutsider and not editor.friendlyElite
    if not forever and not classic and not editor.personal and otherPlayer then
        local active = C_GameRules.IsGameRuleActive(Enum.GameRule.PlayerNameplateDifficultyIcon)
        badge = P.Suite.Public(active) and active == true
    end
    return Style.LevelMode(forever, classic, Styled(prefix), P.Get(ID, prefix .. "LevelEnabled"),
        forever and P.Get(ID, "levelAppearance"), badge, namesOnly)
end

local function PaintSelection(editor, s, texture, visible, badge)
    local mode = Styled(s.prefix) and P.Get(ID, "selectionBorder") or 1
    local target, focus = s.state.target, editor.focusSample
    texture:SetShown(visible and mode ~= 3 and (target or focus == true))
    if mode == 2 then
        texture:SetVertexColor(P.RGB(P.Get(ID, target and "selectionTargetColor" or "selectionFocusColor")))
    else
        local color
        if badge then
            color = NamePlateConstants[target and "TARGET_BORDER_COLOR" or "FOCUS_TARGET_BORDER_COLOR"]
        else
            color = target and NAMEPLATE_BORDER_TARGET_COLOR or NAMEPLATE_BORDER_FOCUS_TARGET_COLOR
        end
        if color then
            texture:SetVertexColor(color.r, color.g, color.b)
        else
            texture:SetVertexColor(1, 1, 1)
        end
    end
end

function Preview.PaintHealthChrome(editor, s, m)
    local art, bar = s.nativeBorder, s.bar
    art:ClearAllPoints()
    if m.classic then
        art:SetTexture("Interface\\Tooltips\\Nameplate-Border")
        art:SetTexCoord(0, 1, 0.5, 1)
        art:SetPoint("TOPLEFT", bar, "TOPLEFT", -3.5 * m.horizontal, 2)
        art:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 20.75 * m.horizontal, -3)
    else
        art:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
        art:SetTexCoord(0, 1, 0, 1)
        art:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 3)
        art:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 6, -6)
    end
    local show = editor:LayerOn("health") and not m.namesOnly
    art:SetShown(m.forever and show and (not Styled(s.prefix) or P.Get(ID, s.prefix .. "NativeBorderEnabled")))
    s.selectedBar:SetAtlas(m.forever and "UI-HUD-CoolDownManager-Selected-yellow" or "UI-HUD-Nameplates-Selected")
    PaintSelection(editor, s, s.selectedBar, show and not m.classic)
end

local function SampleLevel(m, prefix)
    local read = m.forever and UnitEffectiveLevel or UnitLevel
    local value = read and read("player")
    if not P.Suite.Public(value) or type(value) ~= "number" or value < 1 then
        value = m.forever and 60 or 90
    end
    if prefix == "enemy" then
        if m.role == 4 then return "??" end
        if m.role == 9 then return math.max(1, value - 15) end
    end
    return value
end

function Preview.PaintLevel(editor, s, m, setup, place)
    local mode, prefix, level, label = m.levelMode, s.prefix, s.level, s.levelText
    local shown = mode ~= nil and editor:LayerOn("level")
    level._npLevelMode = mode
    level:SetShown(shown)
    if not shown then return end
    local badge, classic, number = mode == "badge", mode == "classic", mode == "number"
    local nativeHeight = (m.style == 0 or m.style == 2) and 23 or 16
    local custom = number and P.Get(ID, prefix .. "LevelSize") or 0
    local size = custom > 0 and custom or setup("levelFontHeight", 10 * m.vertical)
    local offset = Styled(prefix) and "Level"
    if badge and m.forever then
        place(s, level, "LEFT", s.bar, "RIGHT", 5, 0.5, offset)
    elseif classic then
        place(s, level, "CENTER", s.bar, "RIGHT", 10 * m.horizontal, 0, offset)
    else
        place(s, level, "RIGHT", s.bar, "LEFT", -4, 0, offset)
    end
    level:SetSize(badge and setup("playerLevelDiffWidth", (m.forever and 28 or 16) * m.classificationScale)
            or classic and setup("levelIconWidth", 15 * m.horizontal) or math.max(24, size * 2),
        badge and setup("playerLevelDiffHeight", nativeHeight * m.classificationScale)
            or classic and setup("levelIconHeight", 15 * m.vertical) or math.max(16, size))
    s.levelBack:SetShown(badge)
    if badge then s.levelBack:SetAtlas("ui-hud-nameplates-levelindicator") end
    PaintSelection(editor, s, s.levelSelected, badge and m.forever, badge and m.forever)
    local sample = SampleLevel(m, prefix)
    local skull = not number and sample == "??"
    s.levelSkull:SetShown(skull)
    if skull then
        if m.forever then
            s.levelSkull:SetAtlas("ui-hud-nameplates-levelindicator-skull")
        else
            s.levelSkull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
        end
        local height = level:GetHeight()
        s.levelSkull:SetSize(height, height)
    end
    label:SetShown(not skull)
    label:SetText(sample)
    label:SetTextHeight(size)
    label:SetJustifyH(number and "RIGHT" or "CENTER")
    local color = prefix == "enemy" and (not number or P.Get(ID, "enemyLevelColor"))
        and (m.role == 9 and TRIVIAL_DIFFICULTY_COLOR or FAIR_DIFFICULTY_COLOR)
    if color then
        label:SetTextColor(color.r, color.g, color.b)
    else
        label:SetTextColor(1, 1, 1)
    end
end

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
