local root = assert(arg[1], "repository root required")
-- MSUF's icon skins on Blizzard's own player buffs and debuffs (QoL Player
-- aura layout, MSUF_Suite_QualityOfLife/PlayerAuras.lua; Icon Skins page rows
-- "Buffs" and "Debuffs": buffSkin, debuffSkin). On a model of
-- Blizzard_BuffFrame (BuffFrameTemplates.xml: Icon and Duration on
-- BACKGROUND, DebuffBorder, TempEnchantBorder and Count on OVERLAY):
--   1. each frame paints its own row's look on its buttons, as textures of
--      the button around its Icon at the configured icon size; the module's
--      outline hides while a skin draws; the Duration moves above the skin;
--      a private aura anchor is left alone;
--   2. a button the pool hands out in combat gets the same look at once; an
--      adoption (also in combat) is Suite main's code: it asks MSUF nothing;
--   3. No skin: a skinned button is cleared once and its Duration goes back
--      to its own layer; a button that never showed a skin never calls MSUF;
--   4. the module watches MSUF's reports while enabled; disabling clears
--      every skin and lifted layer.

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local combat, parents = false, 0
local function Region(w, h)
    local r = { width = w or 30, height = h or 40, scale = 1, alpha = 1, points = {}, shown = true, layer = "BACKGROUND",
        sublayer = 0, font = { "native.ttf", 10, "" }, color = { 1, 1, 1, 1 }, shadow = { 0, 0, 0, 1 },
        shadowOffset = { 0, 0 }, coords = { 0, 0, 0, 1, 1, 0, 1, 1 } }
    function r:GetWidth() return self.width end
    function r:GetHeight() return self.height end
    function r:GetScale() return self.scale end
    function r:GetAlpha() return self.alpha end
    function r:SetAlpha(v) self.alpha = v end
    function r:GetNumPoints() return #self.points end
    function r:GetPoint(i) return unpack(self.points[i]) end
    function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function r:ClearAllPoints() self.points = {} end
    function r:SetSize(width, height) self.width, self.height = width, height end
    function r:SetScale(s) self.scale = s end
    function r:GetTexCoord() return unpack(self.coords) end
    function r:SetTexCoord(left, right, top, bottom, ...)
        if select("#", ...) == 0 then
            self.coords = { left, top, left, bottom, right, top, right, bottom }
        else
            self.coords = { left, right, top, bottom, ... }
        end
    end
    function r:GetFont() return unpack(self.font) end
    function r:SetFont(...) self.font = { ... } end
    function r:GetTextColor() return unpack(self.color) end
    function r:SetTextColor(...) self.color = { ... } end
    function r:GetShadowColor() return unpack(self.shadow) end
    function r:SetShadowColor(...) self.shadow = { ... } end
    function r:GetShadowOffset() return unpack(self.shadowOffset) end
    function r:SetShadowOffset(...) self.shadowOffset = { ... } end
    function r:GetDrawLayer() return self.layer, self.sublayer end
    function r:SetDrawLayer(layer, sublayer) self.layer, self.sublayer = layer, sublayer end
    function r:SetAllPoints(parent, doResize)
        if doResize ~= false then self:SetSize(parent:GetWidth(), parent:GetHeight()) end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        self:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    end
    function r:SetFrameLevel(n) self.level = n end
    function r:GetFrameLevel() return self.level or 1 end
    function r:IsProtected() return false end
    function r:IsShown() return self.shown end
    function r:SetShown(v) self.shown = v end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:EnableMouse() end
    function r:GetParent()
        parents = parents + 1
        return self.parent
    end
    return r
end
local function Button(shown, parent)
    local b = Region()
    b.parent = parent
    b.Icon, b.Count, b.Duration = Region(30, 30), Region(), Region()
    b.DebuffBorder, b.TempEnchantBorder = Region(40, 40), Region(32, 32)
    b.Count.layer = "OVERLAY"
    b.shown = shown
    return b
end
local function AuraFrame(count)
    local frame = Region()
    frame.AuraContainer = Region()
    frame.auraFrames = {}
    for i = 1, count do frame.auraFrames[i] = Button(i <= 2, frame.AuraContainer) end
    function frame:UpdateAuraButtons() end
    function frame:UpdateGridLayout() end
    return frame
end
_G.UIParent, _G.Minimap = Region(), Region()
StatusTrayManager = { UpdateTrayAndBuffFrameLayout = function() end }
BuffFrame, DebuffFrame = AuraFrame(3), AuraFrame(2)
-- BuffFrame.xml: the consolidated buffs button is BuffFrame's own child.
BuffFrame.ConsolidatedBuffs = Button(true, BuffFrame)
hooksecurefunc = function(obj, key, callback)
    local old = obj[key]
    obj[key] = function(self, ...)
        local out = { old(self, ...) }
        callback(self, ...)
        return unpack(out)
    end
end

-- MSUF's skins through HostBridge: one table per look; every paint recorded.
local LOOKS = { DEFAULT = { signature = "K:SHADOW1" }, DARK2 = { signature = "K:DARK2" } }
local paints, watched, asked = {}, {}, 0
local bridge = {
    IconSkinLook = function(choice)
        asked = asked + 1
        return LOOKS[choice or "DEFAULT"]
    end,
    PaintIconSkin = function(owner, look, width, height, anchor)
        paints[#paints + 1] = { owner = owner, look = look, w = width, h = height, anchor = anchor }
        return look ~= nil
    end,
    WatchIconSkins = function(id, on) watched[id] = on end,
}
local outline = {} -- button -> the module's outline frame
local module
local S = {
    Finite = function(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end,
    CreateFrame = function(_, _, parent)
        local frame = Region()
        if parent then outline[parent] = frame end
        return frame
    end,
    CreateTexture = function() return Region() end,
    RGB = function() return 0, 0, 0 end,
    PlaceEdges = function() end,
    ResolveFont = function() return "modern.ttf" end,
    Queue = function() end,
    Install = function(_, instance) module = instance end,
}
local NS = { IsCombatLocked = function() return combat end, IsSecret = function() return false end,
    Dispatch = function(fn, ...) return fn(...) end, Finish = function(fn, ...) return true, fn(...) end,
    Safety = { IsForbidden = function() return false end },
    MSUFMedia = { font = "msuf.ttf" } }
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", NS)
for key, callback in pairs(bridge) do NS.HostBridge[key] = callback end
-- The skin-only piece (PlayerAuraSkins.lua) lets go of the buttons while this
-- module runs: yields records its calls.
local yields = {}
local private = { NS = NS, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/PlayerAuraSkins.lua"))("MSUF_Suite_QualityOfLife", private)
private.PlayerAuraSkins.Yield = function(on) yields[#yields + 1] = { on = on, paints = #paints } end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/PlayerAuras.lua"))("MSUF_Suite_QualityOfLife", private)

local catalogNS = { Client = { isForever = false }, Text = function(text) return text end }
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", catalogNS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLife.lua"))("MSUF_Suite", catalogNS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLifeIndicators.lua"))("MSUF_Suite", catalogNS)
local rules = catalogNS.SuiteCatalog.playerAuras.rules
Check(rules.buffSkin and rules.buffSkin.hidden and rules.buffSkin.default == "DEFAULT"
    and rules.debuffSkin and rules.debuffSkin.hidden and rules.debuffSkin.default == "DEFAULT",
    "the rows' choices must be hidden rules that follow the default")
local config = {}
for key, rule in pairs(rules) do config[key] = rule.default end
config.debuffSkin = "DARK2"
config.debuffIconWidth, config.debuffIconHeight = 39, 32
local handlers = {} -- the module's events (context:Event)
module.config, module.context = config, { Event = function(_, event, handler) handlers[event] = handler end }

local function PaintsOf(button)
    local list = {}
    for _, call in ipairs(paints) do
        if call.owner == button then list[#list + 1] = call end
    end
    return list
end

-- 1. Each frame's row ----------------------------------------------------------
-- The native getter returns four corner pairs. Preserve the exact original
-- mapping, even when it is not a simple left/right/top/bottom crop.
local buffIcon = BuffFrame.auraFrames[1].Icon
buffIcon:SetTexCoord(.1, .2, .2, .8, .9, .1, .8, .9)
local originalCrop = table.concat(buffIcon.coords, ",")
local intrinsic = BuffFrame.auraFrames[3].Icon
intrinsic:SetSize(31, 27)
local pendingRect = intrinsic.GetWidth
function intrinsic:GetWidth(ignoreRect)
    if not ignoreRect then return 45 end
    return pendingRect(self)
end
local unavailable = DebuffFrame.auraFrames[1].Icon
local getHeight = unavailable.GetHeight
function unavailable:GetHeight(ignoreRect)
    if ignoreRect then return nil end
    return getHeight(self)
end
local unreadable = BuffFrame.auraFrames[2]
local readCoords = unreadable.Icon.GetTexCoord
local unreadableCrop = table.concat(unreadable.Icon.coords, ",")
unreadable.Icon.GetTexCoord = function() return nil end
module:Enable()
Check(unreadable.width == config.iconWidth and BuffFrame.points[1][2] == Minimap,
    "an unreadable crop disabled the entire aura layout")
Check(PaintsOf(unreadable)[1] and PaintsOf(unreadable)[1].look == LOOKS.DEFAULT,
    "an unreadable crop suppressed the applied skin")
Check(table.concat(unreadable.Icon.coords, ",") == unreadableCrop, "an unreadable crop was overwritten")
unreadable.Icon.GetTexCoord = readCoords
Check(table.concat(buffIcon.coords, ",") ~= originalCrop, "the layout must crop the native icon")
Check(watched.playerAuras == true, "the module must watch MSUF's reports while enabled")
Check(#yields == 1 and yields[1].on == true and yields[1].paints == 0,
    "enabling must make the skin-only piece let go of the buttons before this module paints")
local buff, debuff = BuffFrame.auraFrames[1], DebuffFrame.auraFrames[1]
local call = PaintsOf(buff)[1]
Check(call and call.look == LOOKS.DEFAULT and call.anchor == buff.Icon and call.w == config.iconWidth
    and call.h == config.iconHeight, "a buff takes the Buffs row's look around its Icon at the icon size")
call = PaintsOf(debuff)[1]
Check(call and call.look == LOOKS.DARK2 and call.w == config.debuffIconWidth and call.h == config.debuffIconHeight,
    "a debuff takes the Debuffs row's look and dimensions")
Check(PaintsOf(BuffFrame.ConsolidatedBuffs)[1] and PaintsOf(BuffFrame.ConsolidatedBuffs)[1].look == LOOKS.DEFAULT,
    "the consolidated buffs button (on BuffFrame itself) takes the Buffs row's look")
Check(outline[buff] and not outline[buff].shown, "the skin replaces the module's outline")
Check(buff.Duration.layer == "OVERLAY" and buff.Count.layer == "OVERLAY", "the duration text must sit above the skin")
Check(#PaintsOf(BuffFrame.auraFrames[3]) == 1 and PaintsOf(BuffFrame.auraFrames[3])[1].look == LOOKS.DEFAULT,
    "a hidden ordinary button must already carry its row's skin before combat")
for _, button in ipairs(BuffFrame.auraFrames) do
    button.IsShown = function() error("custom layout read an ordinary button's visibility") end
end
-- A private aura anchor keeps Blizzard's art.
local anchor = Button(true, DebuffFrame.AuraContainer)
anchor.isAuraAnchor = true
DebuffFrame.auraFrames[3] = anchor
DebuffFrame.PrivateAuraAnchors = { anchor }
DebuffFrame:UpdateGridLayout()
Check(#PaintsOf(anchor) == 0, "a private aura anchor must not be skinned")

-- An adoption (a zone, the combat end, an addon loading in combat) is Suite
-- main's code: it asks MSUF for no look and repaints nothing; the buttons
-- keep the look they show at their size.
combat = true
local adopted, asks = #paints, asked
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do handlers[event]() end
Check(asked == asks, "an adoption must not ask MSUF for a look")
Check(#paints == adopted and outline[buff] and not outline[buff].shown, "an unchanged adoption must not repaint skins")
combat = false

-- 2. Combat: a button the pool hands out gets the look at once -----------------
combat = true
local gained, beforeGain = BuffFrame.auraFrames[3], #paints
gained.shown = true
BuffFrame:UpdateAuraButtons()
Check(PaintsOf(gained)[1] and PaintsOf(gained)[1].look == PaintsOf(buff)[1].look,
    "a buff shown in combat must take the look of the buffs beside it")
Check(#paints == beforeGain, "revealing the prepainted button in combat must not repaint it")
combat = false
local quiet = #paints
BuffFrame:UpdateAuraButtons()
Check(#paints == quiet, "an aura update over styled buttons must not paint")

-- 3. No skin ------------------------------------------------------------------
config.buffSkin = "CUSTOM"
module:Refresh()
local last = PaintsOf(buff)
Check(last[#last].look == nil and outline[buff].shown and buff.Duration.layer == "BACKGROUND",
    "No skin clears the skin once, shows the outline and puts the duration back")
local cleared = #paints
module:Refresh()
local never = Button(true, BuffFrame.AuraContainer)
BuffFrame.auraFrames[4] = never
BuffFrame:UpdateAuraButtons()
local onBuffs = 0
for i = cleared + 1, #paints do
    if paints[i].owner ~= debuff and paints[i].owner ~= DebuffFrame.auraFrames[2] then onBuffs = onBuffs + 1 end
end
Check(onBuffs == 0, "buttons without a skin must never call MSUF")
-- No skin on either row: every skinned button is cleared at once, a hidden
-- one too (an adoption restyles only shown buttons), so adoptions and aura
-- updates run the plain style (main's code) right away: a button looks up no
-- row and calls no MSUF, also in combat.
local hidden = DebuffFrame.auraFrames[2]
hidden.shown = false
config.debuffSkin = "CUSTOM"
module:Refresh()
Check(PaintsOf(debuff)[#PaintsOf(debuff)].look == nil, "the debuffs' skin is cleared once")
Check(PaintsOf(hidden)[#PaintsOf(hidden)].look == nil and hidden.Duration.layer == "BACKGROUND",
    "a hidden skinned button must be cleared at once when its row has no skin")
local plain, lookups = #paints, parents
combat = true
handlers.ADDON_LOADED()
Check(#paints == plain and parents == lookups, "an adoption in combat without any skin must run the plain style only")
combat = false
hidden.shown = true
DebuffFrame:UpdateGridLayout()
Check(#paints == plain and outline[hidden] and outline[hidden].shown and hidden.Duration.layer == "BACKGROUND",
    "a cleared button shown again runs the plain style")
local fresh = Button(true, BuffFrame.AuraContainer)
BuffFrame.auraFrames[5] = fresh
BuffFrame:UpdateAuraButtons()
Check(#paints == plain and parents == lookups and outline[fresh] and outline[fresh].shown,
    "without any skin a new button must run the plain style only")

-- 4. Disable ------------------------------------------------------------------
config.debuffSkin = "DARK2"
module:Refresh()
Check(PaintsOf(debuff)[#PaintsOf(debuff)].look == LOOKS.DARK2, "the debuffs' skin is on again")
module:Disable()
Check(table.concat(buffIcon.coords, ",") == originalCrop, "disabling restores all eight native texture coordinates")
Check(buffIcon.width == 30 and buffIcon.height == 30, "layout release kept the resized native buff icon")
Check(intrinsic.width == 31 and intrinsic.height == 27, "release restored the current rectangle over the intrinsic size")
Check(unavailable.width == 30 and unavailable.height == 30, "layout overwrote an unreadable intrinsic texture size")
Check(yields[#yields].on == false, "the cleanup gives the buttons back to the skin-only piece")
Check(watched.playerAuras == false, "a disabled module stops watching")
Check(PaintsOf(debuff)[#PaintsOf(debuff)].look == nil and debuff.Duration.layer == "BACKGROUND",
    "disabling leaves no skin and puts every duration back")

-- A native fallback changes the geometry but still uses the layout module's
-- chosen look, even if the separate skin-only module has yielded.
local function LastPaint(button)
    local list = PaintsOf(button)
    return list[#list]
end
config.buffSkin = "DEFAULT"
local blocked = Button(true, BuffFrame.AuraContainer)
local getScale = blocked.GetScale
blocked.GetScale = function() return nil end
BuffFrame.auraFrames[6] = blocked
local pooled = Button(false, BuffFrame.AuraContainer)
BuffFrame.auraFrames[7] = pooled
module:Enable()
local native = LastPaint(buff)
Check(native and native.look == LOOKS.DEFAULT and native.w == 30 and native.h == 30
    and native.anchor == buff.Icon and buff.Duration.layer == "OVERLAY",
    "a failed layout must keep the Buffs skin at native icon size")
Check(LastPaint(blocked).look == LOOKS.DEFAULT and LastPaint(pooled).look == LOOKS.DEFAULT,
    "native skin must cover the failed button and the hidden pool")
Check(LastPaint(BuffFrame.ConsolidatedBuffs).look == LOOKS.DEFAULT,
    "native skin must cover the consolidation button")
local fallbackPaints = #paints
BuffFrame:UpdateAuraButtons()
Check(#paints == fallbackPaints, "a native refill during fallback must not repaint")
config.buffSkin = "DARK2"
module:Refresh()
Check(LastPaint(buff).look == LOOKS.DARK2 and LastPaint(buff).w == 30,
    "the native fallback must update when the Buffs look changes")
config.buffSkin = "CUSTOM"
module:Refresh()
Check(LastPaint(buff).look == nil and buff.Duration.layer == "BACKGROUND",
    "No skin must clear the native fallback look")
config.buffSkin = "DEFAULT"
module:Refresh()
blocked.GetScale = getScale
BuffFrame:UpdateAuraButtons()
Check(LastPaint(buff).look == LOOKS.DEFAULT and LastPaint(buff).w == config.iconWidth
    and buff.Duration.layer == "OVERLAY", "layout recovery must resize the skin without losing it")
LOOKS.DEFAULT, LOOKS.FRAME_BEVEL = nil, { signature = "K:FRAME_BEVEL" }
module:Refresh()
Check(LastPaint(buff).look == LOOKS.FRAME_BEVEL and LastPaint(buff).w == config.iconWidth,
    "an inherited skin missing its global default must draw the square fallback in the custom layout")
Check(LastPaint(debuff).look == LOOKS.DARK2, "the inherited fallback must preserve a specific Debuffs skin")
module:Disable()
Check(LastPaint(pooled).look == nil and pooled.Duration.layer == "BACKGROUND",
    "disabling must release a skin on a button prepainted during fallback")

-- The aura update path stays Suite main's code (owner, 2026-10-17): Sync,
-- Place, Style, Border and the adoption never look at a skin; StyleSkinned
-- runs in Style's stead only while a skin is set or still drawn.
do
    local handle = assert(io.open(root .. "/MSUF_Suite_QualityOfLife/PlayerAuras.lua", "rb"))
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    local function Body(head)
        local start = assert(text:find(head, 1, true), head)
        return text:sub(start, assert(text:find("\nend\n", start, true), head))
    end
    for _, head in ipairs({ "local function Style(", "local function Border(", "local function Place(", "local function Sync(",
        "local function Adopt(" }) do
        local body = Body(head):lower()
        Check(not body:find("skin", 1, true) and not body:find("look", 1, true), head .. " must run Suite main's code")
    end
    Check(Body("local function Sync("):find("Place(button, button.Icon, slot, frame.AuraContainer, geometry, anchor)", 1, true),
        "Sync must use the shared placement path")
end
print("suite player auras skin contract passed")
