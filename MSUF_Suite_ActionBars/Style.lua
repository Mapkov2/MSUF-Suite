local _, P = ...
local NS, S = P.NS, P.Suite
-- Static button styling (configuration time, out of combat). Suite buttons
-- use the regions of ActionButtonTemplate; adopted stance/pet buttons are
-- Blizzard's, so only cosmetic regions are touched there and every suite
-- texture lives in the suite's own records, never on Blizzard tables.
-- Every button remembers the style generations it was styled with (the
-- global AB.styleGen and its bar's styleGen); a refresh restyles only the
-- buttons whose look changed.
local AB = P.ActionBars
local M = AB.M
local max, floor = math.max, math.floor
local OUTLINES = { "OUTLINE", "THICKOUTLINE", "" }
-- Highlight/pressed choices: 1 Border, 2 Soft fill, 3 Blizzard, 4 None.
local STYLE_BORDER, STYLE_FILL, STYLE_BLIZZARD = 1, 2, 3
-- Cooldown frames beside the main swipe that follow the icon.
local EXTRA_COOLDOWNS = { "chargeCooldown", "lossOfControlCooldown" }
AB.styleGen = 0

local function Class()
    if type(UnitClass) ~= "function" then return nil end
    local _, class = UnitClass("player")
    return S.Public(class) and class or nil
end

-- Resolved once per style change; buttons read plain values from here.
function AB.BuildStyle()
    local config = M.config
    local style = AB.style or {}
    AB.style = style
    style.font = S.ResolveFont(config.font)
    style.flags = OUTLINES[config.fontOutline] or ""
    style.rendering, style.shadow = config.fontRendering, config.fontShadow
    style.shadowOpacity, style.shadowDistance = config.fontShadowOpacity, config.fontShadowDistance
    style.zoom = config.iconZoom / 100
    style.border = config.borderSize
    local classR, classG, classB = S.ClassRGB(Class())
    if config.borderClassColor and classR then
        style.br, style.bg, style.bb = classR, classG, classB
    else
        style.br, style.bg, style.bb = S.RGB(config.borderColor)
    end
    if config.interactionClassColor and classR then
        style.ir, style.ig, style.ib = classR, classG, classB
    else
        style.ir, style.ig, style.ib = S.RGB(config.interactionColor)
    end
    style.sr, style.sg, style.sb = S.RGB(config.slotColor)
    style.slotAlpha = config.slotAlpha / 100
    style.kr, style.kg, style.kb = S.RGB(config.keybindColor)
    style.mr, style.mg, style.mb = S.RGB(config.macroColor)
    style.cr, style.cg, style.cb = S.RGB(config.countColor)
    style.dr, style.dg, style.db = S.RGB(config.cooldownColor)
    style.wr, style.wg, style.wb = S.RGB(config.swipeColor)
    style.swipeAlpha = config.swipeAlpha / 100
    style.highlight, style.pushed = config.highlightStyle, config.pushedStyle
    style.rr, style.rg, style.rb = S.RGB(config.rangeColor)
    AB.styleGen = AB.styleGen + 1
    return style
end

-- Four textures on the button, created once per record and key.
function AB.Edges(rec, key, layer, sublevel)
    local set = rec[key]
    if not set then
        set = {}
        for i = 1, 4 do set[i] = S.CreateTexture(rec.button, nil, layer, nil, sublevel) end
        rec[key] = set
    end
    return set
end

-- Four edges inside the button rect; the side edges stop short of the top
-- and bottom ones so translucent colors do not double at the corners.
function AB.PlaceEdges(set, button, width, r, g, b, a)
    local shown = width > 0
    for i = 1, 4 do
        local edge = set[i]
        edge:ClearAllPoints()
        edge:SetColorTexture(r, g, b, a)
        edge:SetShown(shown)
    end
    if not shown then return end
    set[1]:SetPoint("TOPLEFT", button, "TOPLEFT")
    set[1]:SetPoint("TOPRIGHT", button, "TOPRIGHT")
    set[1]:SetHeight(width)
    set[2]:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT")
    set[2]:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT")
    set[2]:SetHeight(width)
    set[3]:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -width)
    set[3]:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, width)
    set[3]:SetWidth(width)
    set[4]:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, -width)
    set[4]:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, width)
    set[4]:SetWidth(width)
end

function AB.ShowEdges(set, shown)
    if not set then return end
    for i = 1, 4 do set[i]:SetShown(shown) end
end

local Edges, PlaceEdges, ShowEdges = AB.Edges, AB.PlaceEdges, AB.ShowEdges

-- Remembers a template texture's own art once, so "Blizzard" can restore it.
local function Remember(rec, key, texture)
    rec.art = rec.art or {}
    if texture and rec.art[key] == nil then
        rec.art[key] = {
            atlas = texture.GetAtlas and texture:GetAtlas(),
            file = texture:GetTexture(),
            blend = texture:GetBlendMode(),
        }
    end
    return rec.art[key]
end

local function StyleInteraction(rec, key, texture, mode, alpha)
    if not texture then return end
    local art = Remember(rec, key, texture)
    local style = AB.style
    texture:ClearAllPoints()
    texture:SetAllPoints(rec.button)
    if mode == STYLE_BLIZZARD and art then
        if art.atlas then
            texture:SetAtlas(art.atlas)
        elseif art.file then
            texture:SetTexture(art.file)
        end
        texture:SetBlendMode(art.blend or "ADD")
        texture:SetVertexColor(1, 1, 1, 1)
        texture:SetAlpha(1)
    elseif mode == STYLE_FILL then
        texture:SetColorTexture(style.ir, style.ig, style.ib, alpha)
        texture:SetBlendMode("ADD")
        texture:SetAlpha(1)
    else
        texture:SetAlpha(0)
    end
end

local function Text(fontString, size, r, g, b, shown)
    if not fontString then return end
    local style = AB.style
    S.SetStyledFont(fontString, style.font, size, style.flags, style.rendering,
        style.shadow, style.shadowOpacity, style.shadowDistance)
    fontString:SetTextColor(r, g, b)
    fontString:SetAlpha(shown and 1 or 0)
end

local function Hide(region)
    if region then region:SetAlpha(0) end
end

-- Icon crop, hidden template art and the empty-slot fill behind the icon
-- (filled slots cover it).
local function StyleIcon(rec, border)
    local button, style = rec.button, AB.style
    local icon = button.icon
    if icon then
        if button.IconMask and not rec.unmasked and icon.RemoveMaskTexture then
            icon:RemoveMaskTexture(button.IconMask)
            rec.unmasked = true
        end
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", border, -border)
        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -border, border)
        icon:SetTexCoord(style.zoom, 1 - style.zoom, style.zoom, 1 - style.zoom)
    end
    Hide(button:GetNormalTexture())
    Hide(button.SlotArt)
    Hide(button.SlotBackground)
    if rec.owned then
        Hide(button.Flash)
        Hide(button.NewActionTexture)
        Hide(button.SpellHighlightTexture)
    end
    local slot = rec.slotTexture
    if not slot then
        slot = S.CreateTexture(button, nil, "BACKGROUND", nil, -8)
        rec.slotTexture = slot
    end
    slot:ClearAllPoints()
    slot:SetPoint("TOPLEFT", button, "TOPLEFT", border, -border)
    slot:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -border, border)
    slot:SetColorTexture(style.sr, style.sg, style.sb, style.slotAlpha)
end

-- Border, mouseover and pressed looks. Mouseover uses HIGHLIGHT-layer edges
-- that show on hover without scripts. The pressed border needs press state
-- (owned buttons only); adopted buttons fall back to the fill.
local function StyleInteractions(rec, size, border)
    local button, style = rec.button, AB.style
    PlaceEdges(Edges(rec, "borderEdges", "OVERLAY", 6), button, border, style.br, style.bg, style.bb, 1)
    local hoverWidth = style.highlight == STYLE_BORDER and max(1, floor(size / 20 + .5)) or 0
    PlaceEdges(Edges(rec, "hoverEdges", "HIGHLIGHT", 7), button, hoverWidth, style.ir, style.ig, style.ib, 1)
    StyleInteraction(rec, "highlight", button:GetHighlightTexture(), style.highlight, .25)
    local pushed = style.pushed
    if pushed == STYLE_BORDER and not rec.owned then pushed = STYLE_FILL end
    local press = Edges(rec, "pressEdges", "OVERLAY", 7)
    PlaceEdges(press, button, pushed == STYLE_BORDER and max(1, floor(size / 15 + .5)) or 0, style.ir, style.ig, style.ib, 1)
    ShowEdges(press, false)
    rec.pressBorder = pushed == STYLE_BORDER
    StyleInteraction(rec, "pushed", button:GetPushedTexture(), pushed, .35)
    local checked = style.highlight == STYLE_BLIZZARD and STYLE_BLIZZARD or STYLE_FILL
    StyleInteraction(rec, "checked", button:GetCheckedTexture(), checked, .3)
end

-- Keybind top right, count bottom right, macro name at the bottom. Native
-- and adopted buttons show the key on a suite font string, because
-- Blizzard rewrites its own HotKey text.
local function StyleTexts(rec, size, border, fontScale)
    local button, style, config = rec.button, AB.style, M.config
    local keys = rec.bar.key
    local hotkey = rec.owned and not rec.native and button.HotKey or rec.keyText
    if not rec.owned or rec.native then
        Hide(button.HotKey)
        if not hotkey then
            hotkey = S.CreateFontString(button, nil, "OVERLAY")
            rec.keyText = hotkey
        end
    end
    if hotkey then
        hotkey:ClearAllPoints()
        hotkey:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1 - border, -2 - border)
        local keySize = max(6, config[keys.KeybindSize] - fontScale)
        hotkey:SetJustifyH("RIGHT")
        hotkey:SetWordWrap(false)
        hotkey:SetSize(max(1, size - 2), keySize + 2)
        Text(hotkey, keySize, style.kr, style.kg, style.kb, config[keys.Keybind])
    end
    local count = button.Count
    if count then
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1 - border, 2 + border)
        Text(count, config[keys.CountSize], style.cr, style.cg, style.cb, true)
    end
    local name = button.Name
    if name then
        name:ClearAllPoints()
        name:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 2 + border)
        name:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 2 + border)
        name:SetHeight(config[keys.MacroSize] + 2)
        name:SetWordWrap(false)
        Text(name, config[keys.MacroSize], style.mr, style.mg, style.mb, rec.owned and config[keys.Macro])
    end
end

local function StyleCooldowns(rec, fontScale)
    local button, style, config = rec.button, AB.style, M.config
    local target = button.icon or button
    local cooldown = button.cooldown
    if cooldown then
        cooldown:ClearAllPoints()
        cooldown:SetAllPoints(target)
        cooldown:SetSwipeColor(style.wr, style.wg, style.wb, style.swipeAlpha)
        cooldown:SetDrawEdge(false)
        cooldown:SetDrawBling(false)
        cooldown:SetHideCountdownNumbers(not config.cooldownNumbers)
        local text = cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
        if text then
            Text(text, max(6, config[rec.bar.key.CooldownSize] - fontScale), style.dr, style.dg, style.db, true)
        end
    end
    local rechargeNumbers = config.cooldownNumbers and config.rechargeNumbers
    for i = 1, #EXTRA_COOLDOWNS do
        local key = EXTRA_COOLDOWNS[i]
        local extra = button[key]
        if extra then
            extra:ClearAllPoints()
            extra:SetAllPoints(target)
            extra:SetHideCountdownNumbers(key == "lossOfControlCooldown" or not rechargeNumbers)
        end
    end
end

-- Applies the static look to one button; all writes are idempotent and
-- nothing here runs from events.
function AB.StyleButton(rec)
    local button, bar = rec.button, rec.bar
    local size = bar.size or M.config[bar.key.Size]
    local border = AB.style.border
    local fontScale = rec.owned and 0 or 2
    StyleIcon(rec, border)
    StyleInteractions(rec, size, border)
    StyleTexts(rec, size, border, fontScale)
    StyleCooldowns(rec, fontScale)
    if rec.owned and button.Border then
        button.Border:ClearAllPoints()
        button.Border:SetAllPoints(button)
    end
    local alert = button.SpellActivationAlert
    if alert and rec.owned then
        alert:SetSize(size * 1.4, size * 1.4)
        if rec.native then alert:SetAlpha(M.config.procGlow == 1 and 1 or 0) end
    end
    rec.styleGen, rec.barStyleGen = AB.styleGen, bar.styleGen
end

-- Press state for native and routed keys; also drives the "Border" pressed
-- style. WoW manages the button state for physical mouse presses.
function AB.SetPushed(rec, down)
    if rec.owned then rec.button:SetButtonState(down and "PUSHED" or "NORMAL") end
    if rec.pressBorder then ShowEdges(rec.pressEdges, down) end
end

-- WoW owns the pressed state during a physical mouse click. Forcing it back
-- to NORMAL in OnMouseUp can cancel the release click before OnClick fires.
-- Only the suite's custom border needs a mouse hook; keyboard presses still
-- use SetPushed above because they do not generate mouse events.
local function MouseDown(button)
    local rec = AB.records[button]
    if rec and M.active and rec.pressBorder then ShowEdges(rec.pressEdges, true) end
end
local function MouseUp(button)
    local rec = AB.records[button]
    if rec and M.active and rec.pressBorder then ShowEdges(rec.pressEdges, false) end
end
-- Routed keys arrive as "Keybind" clicks, which do not change the button
-- state themselves.
local function PreClick(button, mouse, down)
    local rec = AB.records[button]
    if rec and M.active and mouse == "Keybind" then AB.SetPushed(rec, down) end
end
function AB.HookPress(rec)
    if rec.pressHooked or not rec.owned then return end
    rec.pressHooked = true
    local button = rec.button
    button:HookScript("OnMouseDown", MouseDown)
    button:HookScript("OnMouseUp", MouseUp)
    button:HookScript("PreClick", PreClick)
end

-- Restyles the buttons whose look changed: every button after a global
-- style change (rebuild set), else only those of bars whose styleGen moved.
function AB.StyleAll(rebuild)
    if rebuild or not AB.style then AB.BuildStyle() end
    local gen = AB.styleGen
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar then
            local barGen = bar.styleGen
            for i = 1, #bar.buttons do
                local rec = bar.buttons[i]
                if rec.styleGen ~= gen or rec.barStyleGen ~= barGen then AB.StyleButton(rec) end
                AB.HookPress(rec)
            end
        end
    end
end
