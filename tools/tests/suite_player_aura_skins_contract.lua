local root = assert(arg[1], "repository root required")
-- The skin-only player aura piece (MSUF_Suite_QualityOfLife/PlayerAuraSkins.lua,
-- QoL module "Player aura skins"): MSUF's icon skins of the Icon Skins page
-- rows "Buffs" and "Debuffs" on Blizzard's own player buffs and debuffs, at
-- Blizzard's size and layout, while Player aura layout is off. On a model of
-- Blizzard_BuffFrame 12.1.5 / Forever 1.60.1 (every aura button made once at
-- load; updates only show, hide and refill them; the grid layout scales them
-- and anchors their fixed 30x30 Icon again):
--   1. the piece paints every aura button of each frame once, shown or
--      hidden, around its Icon at the Icon's size, and the consolidated buffs
--      button; private aura anchors stay Blizzard's; the Duration moves above
--      a skin; it installs no hook;
--   2. one player UNIT_AURA (both frames' updates and the debuff grid layout)
--      costs the same instructions, widget calls and memory with the piece
--      running and a skin on both rows as before the piece existed;
--   3. No skin clears each skin once and puts the Duration back; a button that
--      never showed a skin never calls MSUF; a change in combat waits for its
--      end; the module watches MSUF's reports while enabled;
--   4. Player aura layout starting takes the buttons (the piece clears its
--      skins first) and its cleanup gives them back;
--   5. the catalog: the module follows playerAuras (its choices) in the QoL
--      addon, loads after Player aura layout, and the Suite applies a follower
--      right after the module it follows.

local function Check(condition, message)
    if not condition then error(message, 2) end
end

------------------------------------------------------------------ widgets
local calls = 0 -- every widget call
local function Count() calls = calls + 1 end
-- Unknown keys read nil (a field the client does not set, like isAuraAnchor
-- on an aura button); the widget calls the model and the piece make count.
local Widget = {}
Widget.__index = Widget
for _, name in ipairs({ "SetTexture", "SetText", "SetScale", "SetSize", "ClearAllPoints", "SetPoint" }) do
    Widget[name] = Count
end
local made = {} -- frames the piece makes (its combat-end waiter)
local function New(w, h)
    return setmetatable({ w = w or 0, h = h or 0, shown = true, layer = "BACKGROUND", sub = 0 }, Widget)
end
function Widget:GetWidth() calls = calls + 1 return self.w end
function Widget:GetHeight() calls = calls + 1 return self.h end
function Widget:SetShown(on) calls = calls + 1 self.shown = on and true or false end
function Widget:GetDrawLayer() calls = calls + 1 return self.layer, self.sub end
function Widget:SetDrawLayer(layer, sub) calls = calls + 1 self.layer, self.sub = layer, sub end
function Widget:SetScript(event, fn) calls = calls + 1 self.scripts = self.scripts or {}; self.scripts[event] = fn end
function Widget:RegisterEvent(event) calls = calls + 1 self.events = self.events or {}; self.events[event] = true end
function Widget:UnregisterEvent(event) calls = calls + 1 if self.events then self.events[event] = nil end end

-- An aura button as AuraButtonTemplate makes it: Icon 30x30 and Duration on
-- BACKGROUND, Count and the debuff border on OVERLAY; hidden until used.
local function Button()
    local b = New(30, 40)
    b.Icon, b.Duration, b.Count, b.DebuffBorder = New(30, 30), New(29, 11), New(0, 0), New(40, 40)
    b.Count.layer, b.DebuffBorder.layer = "OVERLAY", "OVERLAY"
    b.shown = false
    return b
end
-- An aura frame: maxAuras buttons made once, then its private aura anchor.
local function AuraFrame(max, info)
    local frame = New(0, 0)
    frame.auraFrames = {}
    for i = 1, max do frame.auraFrames[i] = Button() end
    local anchor = Button()
    anchor.isAuraAnchor = true
    frame.auraFrames[#frame.auraFrames + 1] = anchor
    frame.auraInfo = info
    -- AuraFrameMixin:UpdateAuraButtons (BuffFrame.lua:202-234).
    function frame:UpdateAuraButtons()
        local index = 1
        for _, button in ipairs(self.auraFrames) do
            if not button.isAuraAnchor then
                local aura = self.auraInfo[index]
                index = index + 1
                button:SetShown(aura ~= nil)
                if aura then
                    button.Icon:SetTexture(aura)
                    button.Count:SetText("")
                end
            end
        end
    end
    -- AuraContainerMixin:UpdateGridLayout (BuffFrame.lua:57-165).
    function frame:UpdateGridLayout()
        for _, button in ipairs(self.auraFrames) do
            button:SetScale(1)
            button:SetSize(30, 40)
            button.Icon:ClearAllPoints()
            button.Icon:SetPoint("TOP", button, "TOP")
            button.Duration:ClearAllPoints()
            button.Duration:SetPoint("TOP", button.Icon, "BOTTOM")
        end
    end
    return frame
end
BuffFrame, DebuffFrame = AuraFrame(32, { 1, 2, 3 }), AuraFrame(16, { 4 })
BuffFrame.ConsolidatedBuffs = Button()
local hooks = 0
hooksecurefunc = function() hooks = hooks + 1 end

-- One player UNIT_AURA (BuffFrame.lua cadence: both frames' UpdateAuraButtons,
-- DebuffFrame's ends in UpdateGridLayout): instructions, widget calls, bytes.
local function Update()
    BuffFrame:UpdateAuraButtons()
    DebuffFrame:UpdateAuraButtons()
    DebuffFrame:UpdateGridLayout()
end
local counted = 0 -- instructions; the hook is made once, outside the measured window
local function Hook() counted = counted + 1 end
local function Measure()
    Update()
    collectgarbage("collect")
    collectgarbage("stop")
    local before, kb = calls, collectgarbage("count")
    counted = 0
    debug.sethook(Hook, "", 1)
    Update()
    debug.sethook()
    local bytes = (collectgarbage("count") - kb) * 1024
    collectgarbage("restart")
    return counted, calls - before, bytes
end
Measure() -- warms the hook machinery
local mainInstr, mainCalls, mainBytes = Measure()

------------------------------------------------------------------ the piece
local LOOKS = { DEFAULT = { signature = "K:SHADOW1" }, DARK2 = { signature = "K:DARK2" } }
local paints, watched, combat = {}, {}, false
local bridge = {
    IconSkinLook = function(choice) return LOOKS[choice or "DEFAULT"] end,
    PaintIconSkin = function(owner, look, w, h, anchor)
        paints[#paints + 1] = { owner = owner, look = look, w = w, h = h, anchor = anchor }
        return look ~= nil
    end,
    WatchIconSkins = function(id, on) watched[id] = on end,
}
local config = { buffSkin = "DEFAULT", debuffSkin = "DARK2" }
local module
local S = {
    Config = function(id)
        Check(id == "playerAuras", "the piece reads only Player aura layout's choices")
        return config
    end,
    CreateFrame = function()
        local frame = New(0, 0)
        made[#made + 1] = frame
        return frame
    end,
    Install = function(id, instance)
        Check(id == "playerAuraSkins", "the piece installs its own module")
        module = instance
    end,
}
local NS = { IsCombatLocked = function() return combat end, IsSecret = function() return false end, HostBridge = bridge }
local P = { NS = NS, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/PlayerAuraSkins.lua"))("MSUF_Suite_QualityOfLife", P)
Check(module and P.PlayerAuraSkins and P.PlayerAuraSkins.Yield, "the piece installs its module and the yield call")

local function PaintsOf(button)
    local list = {}
    for _, call in ipairs(paints) do if call.owner == button then list[#list + 1] = call end end
    return list
end
local function Last(button) local list = PaintsOf(button) return list[#list] end
local function CombatEnd()
    for _, frame in ipairs(made) do
        if frame.events and frame.events.PLAYER_REGEN_ENABLED then frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED") end
    end
end

-- 1. Every button once -------------------------------------------------------
module.config = {}
module:Enable()
Check(watched.playerAuraSkins == true, "the module must watch MSUF's reports while enabled")
Check(hooks == 0, "the piece must install no hook")
for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
    local look = frame == BuffFrame and LOOKS.DEFAULT or LOOKS.DARK2
    for _, button in ipairs(frame.auraFrames) do
        if button.isAuraAnchor then
            Check(#PaintsOf(button) == 0, "a private aura anchor must stay Blizzard's")
        else
            local call = Last(button)
            Check(call and #PaintsOf(button) == 1 and call.look == look and call.anchor == button.Icon and call.w == 30
                and call.h == 30, "every aura button (shown or hidden) takes its row's look around its Icon at its size, once")
            Check(button.Duration.layer == "OVERLAY" and button.Count.layer == "OVERLAY", "the Duration must sit above the skin")
        end
    end
end
Check(Last(BuffFrame.ConsolidatedBuffs) and Last(BuffFrame.ConsolidatedBuffs).look == LOOKS.DEFAULT,
    "the consolidated buffs button takes the Buffs row's look")

-- 2. A UNIT_AURA costs what it costs without the piece ----------------------
local painted = #paints
combat = true
local instr, widgetCalls, bytes = Measure()
combat = false
Check(#paints == painted, "aura updates must not paint")
Check(instr == mainInstr and widgetCalls == mainCalls and bytes == mainBytes,
    ("a UNIT_AURA with the piece and both skins on must cost what it costs without it: %d/%d instructions, %d/%d widget calls, %d/%d bytes")
    :format(instr, mainInstr, widgetCalls, mainCalls, bytes, mainBytes))
module:Refresh()
Check(#paints == painted, "an unchanged refresh repaints nothing")

-- 3. No skin, combat ---------------------------------------------------------
local buff, debuff = BuffFrame.auraFrames[1], DebuffFrame.auraFrames[1]
config.buffSkin = "CUSTOM"
module:Refresh()
Check(Last(buff).look == nil and buff.Duration.layer == "BACKGROUND", "No skin clears the skin once and puts the Duration back")
local cleared = #paints
module:Refresh()
Check(#paints == cleared, "buttons without a skin must not call MSUF again")
combat = true
config.buffSkin = "DARK2"
module:Refresh()
Check(#paints == cleared, "a change in combat waits for the combat end")
combat = false
CombatEnd()
Check(Last(buff).look == LOOKS.DARK2 and buff.Duration.layer == "OVERLAY", "the combat end paints the waiting look")

-- 4. Player aura layout takes the buttons and gives them back ---------------
P.PlayerAuraSkins.Yield(true)
Check(Last(buff).look == nil and Last(debuff).look == nil and buff.Duration.layer == "BACKGROUND",
    "Player aura layout starting: the piece clears its skins first")
local yielded = #paints
module:Refresh()
Check(#paints == yielded, "while Player aura layout runs the piece paints nothing")
P.PlayerAuraSkins.Yield(false)
Check(Last(buff).look == LOOKS.DARK2 and Last(debuff).look == LOOKS.DARK2, "Player aura layout's cleanup: the piece paints again")
module:Disable()
Check(watched.playerAuraSkins == false and Last(buff).look == nil and buff.Duration.layer == "BACKGROUND",
    "a disabled piece leaves no skin and stops watching")

-- 5. The catalog and the follow link -----------------------------------------
local catalogNS = { Client = { isForever = false }, Text = function(text) return text end }
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", catalogNS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLife.lua"))("MSUF_Suite", catalogNS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLifeIndicators.lua"))("MSUF_Suite", catalogNS)
local spec = catalogNS.SuiteCatalog.playerAuraSkins
Check(spec and spec.follows == "playerAuras" and spec.addon == "MSUF_Suite_QualityOfLife",
    "the module follows Player aura layout (its choices) in the Quality of Life addon")
do
    local function Read(rel)
        local handle = assert(io.open(root .. "/" .. rel, "rb"))
        local text = handle:read("*a"):gsub("\r\n", "\n")
        handle:close()
        return text
    end
    Check(Read("MSUF_Suite_QualityOfLife/MSUF_Suite_QualityOfLife_Mainline.toc"):find("PlayerAuras.lua\nPlayerAuraSkins.lua", 1, true),
        "the piece loads right after Player aura layout")
end
print(("suite player aura skins contract passed (one UNIT_AURA: %d instructions, %d widget calls, %d bytes with and without the piece)")
    :format(instr, widgetCalls, bytes))
