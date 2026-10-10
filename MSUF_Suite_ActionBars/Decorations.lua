local _, P = ...
local NS, S, AB = P.NS, P.Suite, P.ActionBars
local M = AB.M
local ENUM = AB.ENUM
local ENDCAP, SHAPE, BORDER_ART, ASSIST = ENUM.ENDCAP, ENUM.BUTTON_SHAPE, ENUM.BORDER_ART, ENUM.ASSIST_STYLE

-- Optional static ornaments use only small colored regions owned by Suite.
-- Nothing follows combat events, timers or the cursor. They take the
-- resolved border color of the button look (AB.style: the class color with
-- "Class-colored border"), which the style pass builds before this runs.
local ENDCAP_KEYS = {}
for _, side in ipairs({ "Left", "Right" }) do
    ENDCAP_KEYS[side] = { style = side .. "Endcap", size = side .. "EndcapSize", x = side .. "EndcapX", y = side .. "EndcapY" }
end
local function Endcap(bar, side)
    local c, keys, names = M.config, bar.key, ENDCAP_KEYS[side]
    local style = c[keys[names.style]]
    local cap = bar[names.style]
    if style == ENDCAP.NONE then
        if cap then cap:Hide() end
        return
    end
    if not cap then
        cap = S.CreateFrame("Frame", nil, bar.header)
        cap.pieces = {}
        for i = 1, 5 do cap.pieces[i] = S.CreateTexture(cap, nil, "ARTWORK") end
        bar[names.style] = cap
    end
    local size = c[keys[names.size]]
    local direction = side == "Left" and -1 or 1
    local anchor = side == "Left" and "LEFT" or "RIGHT"
    cap:SetSize(size, size)
    cap:ClearAllPoints()
    cap:SetPoint("CENTER", bar.header, anchor, direction * size * .6 + c[keys[names.x]], c[keys[names.y]])
    local r, g, b = AB.style.br, AB.style.bg, AB.style.bb
    for i = 1, 5 do
        local t = cap.pieces[i]
        t:ClearAllPoints()
        t:SetColorTexture(r, g, b, 1)
        t:SetShown(i <= (style == ENDCAP.DIAMOND and 2 or 4))
        if style == ENDCAP.DIAMOND then
            t:SetSize(size * .55, i == 1 and size * .55 or size * .3)
            t:SetPoint("CENTER", cap, "CENTER", 0, 0)
            t:SetRotation(math.pi / 4)
            if i == 2 then t:SetColorTexture(.08, .08, .08, 1) end
        else
            local pair = math.floor((i - 1) / 2)
            t:SetSize(size * .55, math.max(1, size / 10))
            t:SetPoint("CENTER", cap, "CENTER", direction * pair * size * .28, i % 2 == 0 and -size * .16 or size * .16)
            t:SetRotation(direction * (i % 2 == 0 and math.pi / 4 or -math.pi / 4))
        end
    end
    cap:Show()
end

-- Page arrows click Blizzard's own page buttons (MainActionBar.xml, Retail and
-- Forever: MainActionBar.ActionBarPageNumber.UpButton/DownButton) through a
-- secure "click" action, so the page change runs untainted. They wear the
-- atlases of those buttons. An addon's secure action button runs its action
-- on the press while ActionButtonUseKeyDown is on (SecureActionButton_OnClick);
-- useOnKeyDown false makes the registered release click it.
local ARROWS = {
    { "UpButton", "ui-hud-actionbar-pageuparrow" },
    { "DownButton", "ui-hud-actionbar-pagedownarrow" },
}
local function PageArrow(arrows, pager, index)
    local target, atlas = pager[ARROWS[index][1]], ARROWS[index][2]
    local button = S.CreateFrame("Button", nil, arrows, "SecureActionButtonTemplate")
    button:SetSize(17, 14)
    button:SetPoint(index == 1 and "TOP" or "BOTTOM", arrows, index == 1 and "TOP" or "BOTTOM", 0, 0)
    button:SetAttribute("type", "click")
    button:SetAttribute("clickbutton", target)
    button:SetAttribute("useOnKeyDown", false)
    button:RegisterForClicks("AnyUp")
    button:SetNormalAtlas(atlas .. "-up")
    button:SetPushedAtlas(atlas .. "-down")
    button:SetDisabledAtlas(atlas .. "-disabled")
    button:SetHighlightAtlas(atlas .. "-mouseover")
    return button
end

-- The background border: LayoutBar creates the edges, this places them once
-- the look is built (also for a border color change, which lays out nothing).
function AB.LayoutDecorations(bar)
    if bar.backgroundEdges and M.config[bar.key.Background] then
        local style = AB.style
        S.PlaceEdges(bar.backgroundEdges, bar.background, M.config[bar.key.BackgroundBorder], style.br, style.bg, style.bb, 1)
    end
    Endcap(bar, "Left")
    Endcap(bar, "Right")
    if bar.index ~= ENUM.BAR.MAIN then return end
    local c, arrows = M.config, bar.pageArrows
    local main = AB.Frame("MainActionBar")
    if not c.pageArrows or not main then
        if arrows then arrows:Hide() end
        return
    end
    if not arrows then
        arrows = S.CreateFrame("Frame", nil, bar.header)
        arrows:SetSize(17, 34)
        arrows.buttons = {}
        for i = 1, 2 do arrows.buttons[i] = PageArrow(arrows, main.ActionBarPageNumber, i) end
        bar.pageArrows = arrows
    end
    arrows:ClearAllPoints()
    local left = c.pageArrowSide == ENUM.PAGE_ARROW_SIDE.LEFT
    arrows:SetPoint(left and "RIGHT" or "LEFT", bar.header, left and "LEFT" or "RIGHT", left and -4 or 4, 0)
    arrows:Show()
end

-- Geometry-only clipping and ornament layer. Blizzard remains the source of
-- cooldowns, pressed/current states and assisted-combat recommendations.
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RING = "Interface\\AddOns\\MSUF_Suite_Modules\\Media\\Minimap\\Halo"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ABOVE = { "cooldown", "chargeCooldown", "SpellActivationAlert", "AssistedCombatHighlightFrame", "AssistedCombatRotationFrame" }
function AB.RaiseDecoration(rec)
    local host, button = rec.edgeHost, rec.button
    if not host then return end
    local level = button:GetFrameLevel()
    for _, key in ipairs(ABOVE) do
        local child = button[key]
        if child then level = math.max(level, child:GetFrameLevel()) end
    end
    if rec.edgeLevel ~= level + 5 then
        rec.edgeLevel = level + 5
        host:SetFrameLevel(level + 5)
    end
end
function AB.DecorationHost(rec)
    if not rec.edgeHost then
        rec.edgeHost = S.CreateFrame("Frame", nil, rec.button)
        rec.edgeHost:SetAllPoints(rec.button)
        rec.edgeHost:EnableMouse(false)
    end
    AB.RaiseDecoration(rec)
    return rec.edgeHost
end
local function Art(texture, circle)
    if circle then
        texture:SetTexture(RING)
    else
        texture:SetAtlas("UI-HUD-ActionBar-IconFrame")
    end
end
-- Round buttons get round interaction art: the ring of their frame, in the
-- interaction color, for the mouseover border (HIGHLIGHT layer of the button)
-- and the pixel proc glow (on the decoration host).
local function Ring(rec, key, owner, layer, size)
    local ring = rec[key]
    if not ring then
        ring = S.CreateTexture(owner, nil, layer, nil, 7)
        ring:SetTexture(RING)
        rec[key] = ring
    end
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", rec.button, "CENTER", 0, 0)
    ring:SetSize(size, size)
    ring:SetVertexColor(AB.style.ir, AB.style.ig, AB.style.ib, 1)
    ring:Show()
end
function AB.HoverRing(rec, size, shown)
    if shown then
        Ring(rec, "hoverRing", rec.button, "HIGHLIGHT", size)
    elseif rec.hoverRing then
        rec.hoverRing:Hide()
    end
end
function AB.GlowRing(rec, shown)
    if shown then
        Ring(rec, "glowRing", AB.DecorationHost(rec), "OVERLAY", rec.bar.size or M.config[rec.bar.key.Size])
    elseif rec.glowRing then
        rec.glowRing:Hide()
    end
end
function AB.UpdateDecorState(rec)
    if rec.stateArt then rec.stateArt:SetShown(rec.decorFancy and (rec.decorPushed or rec.decorChecked) or false) end
end
-- Masks (or unmasks) one of the button's own textures for the round shape.
local function ShapeMask(texture, rec, circle)
    if not texture then return end
    if circle then
        texture:AddMaskTexture(rec.shapeMask)
    elseif rec.shapeMask then
        texture:RemoveMaskTexture(rec.shapeMask)
    end
end
local SWIPES = { "cooldown", "chargeCooldown", "lossOfControlCooldown" }
local function PlaceArt(texture, button, extent, circle)
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", button, "CENTER", 0, 0)
    texture:SetSize(extent, extent)
    Art(texture, circle)
end
function AB.StyleDecoration(rec, size)
    local c, button = M.config, rec.button
    local circle = c.buttonShape == SHAPE.CIRCLE
    if circle and not rec.shapeMask then
        rec.shapeMask = button:CreateMaskTexture()
        rec.shapeMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        rec.shapeMask:SetAllPoints(button.icon)
    end
    if circle ~= (rec.circleMasked == true) then
        ShapeMask(button.icon, rec, circle)
        ShapeMask(rec.slotTexture, rec, circle)
        ShapeMask(button:GetHighlightTexture(), rec, circle)
        ShapeMask(button:GetPushedTexture(), rec, circle)
        ShapeMask(button:GetCheckedTexture(), rec, circle)
        rec.circleMasked = circle
    end
    for i = 1, #SWIPES do
        local cooldown = button[SWIPES[i]]
        if cooldown then cooldown:SetSwipeTexture(circle and CIRCLE or WHITE) end
    end
    local fancy = circle or c.borderArt == BORDER_ART.BLIZZARD
    rec.decorFancy = fancy
    if fancy then
        local host = AB.DecorationHost(rec)
        if not rec.borderArt then
            rec.borderArt = S.CreateTexture(host, nil, "OVERLAY", nil, 5)
            rec.stateArt = S.CreateTexture(host, nil, "OVERLAY", nil, 6)
        end
        local extent = (size + c.borderExpansion * 2) * c.borderScale / 100
        PlaceArt(rec.borderArt, button, extent, circle)
        PlaceArt(rec.stateArt, button, extent, circle)
        rec.borderArt:SetVertexColor(AB.style.br, AB.style.bg, AB.style.bb, 1)
        rec.stateArt:SetVertexColor(AB.style.ir, AB.style.ig, AB.style.ib, 1)
        rec.stateArt:SetBlendMode("ADD")
        rec.borderArt:SetShown(c.borderSize > 0)
        AB.ShowEdges(rec.borderEdges, false)
        rec.pressBorder = false
        AB.ShowEdges(rec.pressEdges, false)
        AB.UpdateDecorState(rec)
    else
        if rec.borderArt then
            rec.borderArt:Hide()
            rec.stateArt:Hide()
        end
    end
    if rec.quality then rec.quality:SetSize(math.max(8, size * .4), math.max(8, size * .4)) end
end

-- Assisted combat recommendation, Retail only: Forever's Camelot UI offers no
-- assisted combat setting (InterfaceOverrides.HasAssistedCombat() is false
-- there), so its options are hidden and nothing is hooked on Forever.
-- AssistedCombatManager itself does load there (forever Blizzard_ActionBar
-- .toc lists it for mainline, which Forever loads unless a file excludes
-- camelot). Blizzard computes the
-- recommendation only while its Assisted Highlight option (the
-- assistedCombatHighlight CVar) is on, and highlights its own buttons: the
-- reused buttons of bars 2-8 and the adopted stance buttons. There the Suite
-- follows Blizzard's decision; a suite button matches the spell its paint
-- cached (a macro re-reads its spell). Blizzard creates a button's highlight
-- frame on its first recommendation, so its alpha is set after each
-- SetAssistedHighlightFrameShown.
local assistedSpell
local assistActive = false
local function NativeAlpha(button)
    local frame = button.AssistedCombatHighlightFrame
    if frame then frame:SetAlpha(M.config.assistStyle == ASSIST.BLIZZARD and 1 or 0) end
end
-- The ring's look: laid out again only when one of its inputs changed, so a
-- new recommendation (every few hundred milliseconds in combat) only moves
-- which rings show.
local function LayoutAssist(rec, holder)
    local c = M.config
    local size = (rec.bar.size or c[rec.bar.key.Size]) + c.assistExpansion * 2
    local circle = c.buttonShape == SHAPE.CIRCLE
    if holder.size == size and holder.x == c.assistX and holder.y == c.assistY and holder.circle == circle
        and holder.color == c.assistColor and holder.alpha == c.assistAlpha and holder.style == c.assistStyle then return end
    holder.size, holder.x, holder.y, holder.circle = size, c.assistX, c.assistY, circle
    holder.color, holder.alpha, holder.style = c.assistColor, c.assistAlpha, c.assistStyle
    holder:ClearAllPoints()
    holder:SetSize(size, size)
    holder:SetPoint("CENTER", rec.button, "CENTER", c.assistX, c.assistY)
    holder.ring:SetAllPoints(holder)
    Art(holder.ring, circle)
    holder.fill:SetAllPoints(rec.button.icon)
    holder.fill:SetTexture(circle and CIRCLE or WHITE)
    local r, g, b = S.RGB(c.assistColor)
    holder.ring:SetVertexColor(r, g, b, c.assistAlpha / 100)
    holder.fill:SetVertexColor(r, g, b, c.assistAlpha / 100 * .35)
    holder.ring:SetShown(c.assistStyle == ASSIST.RING or c.assistStyle == ASSIST.RING_AND_FILL)
    holder.fill:SetShown(c.assistStyle == ASSIST.FILL or c.assistStyle == ASSIST.RING_AND_FILL)
end
local function ShowAssist(rec, show)
    local holder = rec.assist
    if not show then
        if holder and holder.on then
            holder.on = false
            holder:Hide()
        end
        return
    end
    if not holder then
        holder = S.CreateFrame("Frame", nil, rec.button)
        holder.ring = S.CreateTexture(holder, nil, "OVERLAY")
        holder.fill = S.CreateTexture(holder, nil, "ARTWORK")
        rec.assist = holder
    end
    LayoutAssist(rec, holder)
    if not holder.on then
        holder.on = true
        holder:Show()
    end
    AB.RaiseDecoration(rec)
end
-- Whether a button carries the current recommendation.
local function Recommended(rec)
    local spell = assistedSpell
    if not spell then return false end
    if rec.native or not rec.owned then
        local frame = rec.button.AssistedCombatHighlightFrame
        local shown = frame and frame:IsShown()
        return S.Public(shown) and shown == true
    end
    if not rec.filled then return false end
    local Pa = AB.Painter
    if rec.glowKind == Pa.GLOW_SPELL then return rec.glowID == spell end
    if rec.glowKind == Pa.GLOW_DYNAMIC then return Pa.ActionSpell(rec.slot) == spell end
    return false
end
-- After a suite button's paint (its action or page changed).
function AB.UpdateAssist(rec)
    if assistActive then ShowAssist(rec, Recommended(rec)) end
end
local function AssistAll()
    for _, rec in pairs(AB.records) do ShowAssist(rec, assistActive and Recommended(rec)) end
end
local function RecommendationChanged(_, spellID)
    if not M.active then return end
    assistedSpell = S.Finite(spellID) and spellID or nil
    if assistActive then AssistAll() end
end
local function NativeHighlight(_, button)
    local rec = M.active and AB.records[button]
    if not rec then return end
    NativeAlpha(button)
    if assistActive then ShowAssist(rec, Recommended(rec)) end
end
-- Both run inside the manager's OnUpdate: isolated, so an error is reported
-- and never stops Blizzard's update.
local Dispatch = S.Dispatch
local function RecommendationHook(manager, spellID) Dispatch(RecommendationChanged, manager, spellID) end
local function NativeHighlightHook(manager, button) Dispatch(NativeHighlight, manager, button) end
-- Settings work for the assist keys (Controller.lua): style, look and size.
function AB.SyncAssistedDecoration()
    if NS.Client.isForever then return end
    local style = M.config.assistStyle
    if style ~= ASSIST.BLIZZARD and not AB.assistHooked then
        AB.assistHooked = true
        hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedHighlightFramesForSpell", RecommendationHook)
        hooksecurefunc(AssistedCombatManager, "SetAssistedHighlightFrameShown", NativeHighlightHook)
    end
    if not AB.assistHooked then return end
    assistActive = style ~= ASSIST.BLIZZARD
    local spell = AssistedCombatManager.lastNextCastSpellID
    assistedSpell = S.Finite(spell) and spell or nil
    for _, rec in pairs(AB.records) do NativeAlpha(rec.button) end
    AssistAll()
end
function AB.StopAssist()
    assistActive, assistedSpell = false, nil
    for _, rec in pairs(AB.records) do
        ShowAssist(rec, false)
        local frame = rec.button.AssistedCombatHighlightFrame
        if frame then frame:SetAlpha(1) end
    end
end
