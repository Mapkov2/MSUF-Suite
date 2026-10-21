local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
-- MSUF's icon skins (the Icon Skins page rows "Buffs" and "Debuffs": the
-- Player aura layout settings buffSkin and debuffSkin) on Blizzard's own
-- player buffs and debuffs, at Blizzard's size and layout, while Player aura
-- layout (PlayerAuras.lua, which paints them itself) is off.
--
-- Blizzard_BuffFrame (live 12.1.5 and Forever 1.60.1) makes every aura button
-- once, when it loads (AuraFrame_OnLoad: maxAuras buttons per frame); aura
-- updates only show, hide and refill them, and the grid layout (Edit Mode
-- too) scales a button and anchors its fixed 30x30 Icon again. A skin is
-- textures of the button around its Icon, so it follows all of that by
-- itself: every button is painted once, out of combat (enable, a choice on
-- the Icon Skins page, MSUF's report, Player aura layout going off), and no
-- aura update, layout or combat runs any code here. Private aura anchors
-- (isAuraAnchor), the deadly debuff and external defensives frames stay
-- Blizzard's. Side tables only; nothing is written onto Blizzard frames.
-- After a reload in combat the Suite starts its modules when combat ends (the
-- controller's rule, as for the action bars' skins), so the skins appear then:
-- painting in combat would make textures in combat.
--   painted  button -> { look, w, h } it shows
--   layers   Duration -> its draw layer before a skin lifted it
local painted, layers = {}, {}
local yielded = false -- Player aura layout paints the buttons now
local waiting -- a frame that paints at the combat end
local IsSecret = NS.IsSecret

-- The Duration sits on BACKGROUND, under a skin's layers: while a skin draws
-- it moves to OVERLAY (the Count's layer), and back when the skin goes.
local function Layer(text, skin)
    if not (text and text.SetDrawLayer) then return end
    local before = layers[text]
    if skin and not before then
        local layer, sublayer = text:GetDrawLayer()
        if IsSecret(layer) or IsSecret(sublayer) then return end
        layers[text] = { layer, sublayer or 0 }
        text:SetDrawLayer("OVERLAY", 0)
    elseif not skin and before then
        layers[text] = nil
        text:SetDrawLayer(before[1], before[2])
    end
end

-- One button at its Icon's size; a button that never showed a skin never
-- calls MSUF.
local function Paint(button, look)
    local icon = button and button.Icon
    if not icon or button.isAuraAnchor then return end
    local shown = painted[button]
    if not (look or shown) then return end
    local w, h = icon:GetWidth(), icon:GetHeight()
    if IsSecret(w) or IsSecret(h) then return end
    if shown and shown.look == look and shown.w == w and shown.h == h then return end
    local skin = NS.HostBridge.PaintIconSkin(button, look, w, h, icon)
    painted[button] = skin and { look = look, w = w, h = h } or nil
    Layer(button.Duration, skin)
end
local function PaintFrame(name, look)
    local frame = _G[name]
    if not frame then return end
    for _, button in ipairs(frame.auraFrames or {}) do Paint(button, look) end
    -- BuffFrame's consolidated buffs button (BuffFrame.xml) is its own child.
    Paint(frame.ConsolidatedBuffs, look)
end

-- The rows' looks while the piece runs and Player aura layout is off; else
-- none (every skin it painted goes). Out of combat only: a change in a fight
-- (a reload in combat) waits for its end.
local function Apply()
    if NS.IsCombatLocked() then
        if not waiting then
            waiting = S.CreateFrame("Frame")
            waiting:SetScript("OnEvent", function(frame)
                frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
                Apply()
            end)
        end
        waiting:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local on, c = M.active and not yielded, S.Config("playerAuras")
    local bridge = NS.HostBridge
    PaintFrame("BuffFrame", on and bridge.IconSkinLook(c.buffSkin) or nil)
    PaintFrame("DebuffFrame", on and bridge.IconSkinLook(c.debuffSkin) or nil)
end

function M:Enable()
    self.active = true
    -- MSUF's default icon skin changed: Refresh paints the new look.
    NS.HostBridge.WatchIconSkins("playerAuraSkins", true)
    Apply()
end

function M:Refresh()
    Apply()
end

function M:Disable()
    self.active = false
    NS.HostBridge.WatchIconSkins("playerAuraSkins", false)
    Apply()
end

-- Player aura layout starts (on) or has let go of the buttons (off): the
-- skins it would paint over go first, and come back after it.
P.PlayerAuraSkins = {
    Yield = function(on)
        yielded = on == true
        Apply()
    end,
}

S.Install("playerAuraSkins", M)
