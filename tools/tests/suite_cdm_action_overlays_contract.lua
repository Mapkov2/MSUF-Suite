local root = assert(arg[1], "repository root required"):gsub("\\", "/")
-- Action-bar aura display (ov.actionAuraDisplay, ov.actionAuraGlow,
-- MSUF_Suite_CooldownManager/ActionGlows.lua): the spell-mapped aura bridge
-- may also show the aura's icon, the full aura, its duration swipe,
-- duration text or stacks on its action buttons, with its glow or without.
-- Checked here: the default stays the glow-only bridge and costs no more
-- than 0.1.20's, each display binds exactly its regions to the record's own
-- native aura button (no Lua reads an aura value), a hidden glow stays dark
-- on the same record, the display takes the action icon's crop and its
-- owner's masks and follows them through the action bars' style event
-- (subscribed only while a display is wanted), secret values and sealed
-- buttons are never touched, disabled and hidden paths do no work, and
-- spell and page changes move the display with the glow.
-- Reuses the aura contract's world (sealed aura buttons that refuse Lua while
-- auras are secret, secret sentinels that raise on any use, strict globals)
-- up to its static rules, as the per-spell options contract reuses the
-- options world.
local handle = assert(io.open(root .. "/tools/tests/suite_cooldown_manager_auras_contract.lua", "rb"))
local source = handle:read("*a"):gsub("\r\n", "\n")
handle:close()
local stop = assert(source:find("\n-- Static rules on the source text.\n", 1, true), "the aura contract's world moved")
source = source:sub(1, stop) .. [[
return { R = R, New = New, Methods = Methods, containers = containers, C = C, S = S, NS = NS, CDM = CDM,
    Secret = Secret, IsSecret = IsSecret, RunTimers = RunTimers, LoadRuntime = LoadRuntime, Calls = Calls, Args = Args, tally = tally,
    State = function(combat, access, secret) COMBAT, ACCESS, AURAS_SECRET = combat, access, secret end,
    Armed = function() return timerCount end }
]]
local W = assert(loadstring(source, "@action-overlay-world"))()
local R, C, S, CDM, Methods = W.R, W.C, W.S, W.CDM, W.Methods
local Secret, Calls, Args, containers = W.Secret, W.Calls, W.Args, W.containers
local DISPLAY, GLOW = CDM.ACTION_AURA, CDM.ACTION_AURA_GLOW
local STYLE_EVENT = "MSUFSuite.ActionBars.StyleChanged"
local WHITE = "Interface\\Buttons\\WHITE8X8"

------------------------------------------------------------------ the saved fields
do
    local valid = assert(CDM.SPELL_FIELDS.actionAuraDisplay, "the per-spell display field")
    for value = 1, 6 do assert(valid(value), "display " .. value .. " is stored") end
    for _, bad in ipairs({ 0, 7, 2.5, "2", true, -1 }) do assert(not valid(bad), "a bad display is dropped: " .. tostring(bad)) end
    local glow = assert(CDM.SPELL_FIELDS.actionAuraGlow, "the per-spell glow field")
    assert(glow(1) and glow(2), "both glow choices are stored")
    for _, bad in ipairs({ 0, 3, 1.5, "2", true, false }) do assert(not glow(bad), "a bad glow choice is dropped: " .. tostring(bad)) end
    local clean = CDM.CleanSpells({ e = { a456 = { actionAuraDisplay = 3, actionAuraGlow = 2, actionGlowSpell = 123 },
        a457 = { actionAuraDisplay = 9, actionAuraGlow = 5 } } })
    assert(clean.e.a456.actionAuraDisplay == 3 and clean.e.a456.actionAuraGlow == 2 and clean.e.a457 == nil,
        "the codec keeps valid choices and drops bad ones")
    assert(DISPLAY.GLOW == 1 and DISPLAY.ICON == 2 and DISPLAY.FULL == 3 and DISPLAY.SWIPE == 4 and DISPLAY.TIME == 5
        and DISPLAY.STACKS == 6, "display values")
    assert(GLOW.SHOW == 1 and GLOW.HIDE == 2, "glow values: absent shows the glow")
end

------------------------------------------------------------------ static rules
-- Event-driven only: no polling, scripts, combat log, protected calls, aura
-- reads or event registration of its own; one callback, the action bars'
-- style event.
do
    local file = assert(io.open(root .. "/MSUF_Suite_CooldownManager/ActionGlows.lua", "rb"))
    local text = file:read("*a")
    file:close()
    for _, banned in ipairs({ "OnUpdate", "SetScript", "OnSizeChanged", "COMBAT_LOG", "pcall", "RegisterEvent",
        "RegisterUnitEvent", "C_UnitAuras", "GetAuraData", "UnitAura", "GameTooltip", "HookScript", "hooksecurefunc",
        "NewTicker" }) do
        assert(not text:find(banned, 1, true), "ActionGlows.lua uses " .. banned)
    end
    local _, callbacks = text:gsub("EventRegistry:RegisterCallback%(", "")
    assert(callbacks == 1 and text:find('"' .. STYLE_EVENT .. '"', 1, true), "one callback: the action bars' style event")
end

------------------------------------------------------------------ world
-- EventRegistry as CallbackRegistryMixin keeps it: one callback per event
-- and owner, called with the owner first.
local callbacks, registrations = {}, 0
rawset(_G, "EventRegistry", {
    RegisterCallback = function(_, event, fn, owner)
        assert(type(fn) == "function" and owner ~= nil, "a callback with its owner")
        callbacks[event] = callbacks[event] or {}
        assert(not callbacks[event][owner], "registered twice")
        callbacks[event][owner] = fn
        registrations = registrations + 1
    end,
    UnregisterCallback = function(_, event, owner) if callbacks[event] then callbacks[event][owner] = nil end end,
    TriggerEvent = function(_, event, ...)
        for owner, fn in pairs(callbacks[event] or {}) do fn(owner, ...) end
    end,
})
local function Subscribed() return next(callbacks[STYLE_EVENT] or {}) ~= nil end
local function Restyled() EventRegistry:TriggerEvent(STYLE_EVENT) end
-- The client keeps a secret value's Lua type (a secret number is a
-- "number"); the world's sentinels are tables. ActionGlows.lua takes `type`
-- once at load, so it loads with the client's answer: only its Public
-- guards keep secrets out.
local rawType = type
rawset(_G, "type", function(value) if W.IsSecret(value) then return "number" end return rawType(value) end)
W.LoadRuntime("ActionGlows.lua")
rawset(_G, "type", rawType)
W.LoadRuntime("ActionUsableGlows.lua")
local bridge = C.ActionGlows
local combat = false
local function State(inCombat, access, secret)
    combat = inCombat
    W.State(inCombat, access, secret)
end
local function Write(obj, name, ...)
    W.tally.writes = W.tally.writes + 1
    local s = R[obj]
    s.args[name] = { ... }
    s.calls[name] = (s.calls[name] or 0) + 1
end
function Methods:GetSize() local s = R[self]; return s.w or 36, s.h or 36 end
function Methods:GetAttribute(key) local a = R[self].attrs; return a and a[key] end
function Methods:GetTexCoord() return unpack(R[self].coords or { 0, 0, 0, 1, 1, 0, 1, 1 }) end
-- Texture masks (SimpleTextureAPI): a secret hierarchy answers secret.
function Methods:GetNumMaskTextures()
    local s = R[self]
    if s.secretMasks then return Secret() end
    return s.masks and #s.masks or 0
end
function Methods:GetMaskTexture(i) return R[self].masks[i] end
function Methods:AddMaskTexture(mask)
    Write(self, "AddMaskTexture", mask)
    local s = R[self]
    s.masks = s.masks or {}
    for i = 1, #s.masks do assert(s.masks[i] ~= mask, "a mask added twice") end
    s.masks[#s.masks + 1] = mask
end
function Methods:RemoveMaskTexture(mask)
    Write(self, "RemoveMaskTexture", mask)
    local masks = R[self].masks
    for i = #masks, 1, -1 do
        if masks[i] == mask then table.remove(masks, i) end
    end
end
function Methods:GetAtlas() return R[self].atlas end
function Methods:GetTexture() return R[self].file end
function Methods:SetSwipeTexture(file) Write(self, "SetSwipeTexture", file) end
local function ActionButton(slot)
    local button = W.New("Button", UIParent)
    local icon = W.New("Texture", button)
    button.icon = icon
    R[button].attrs = { action = slot }
    R[icon].coords = { .1, .12, .1, .88, .9, .12, .9, .88 }
    return button, icon
end
-- A mask its owner made (CreateMaskTexture) from a file or an atlas.
local function OwnMask(owner, file, atlas)
    local mask = W.New("MaskTexture", owner)
    R[mask].file, R[mask].atlas = file, atlas
    return mask
end
local first, firstIcon = ActionButton(5)
local second = ActionButton(6)
local slots = { [5] = { "spell", 123, "spell" }, [6] = { "macro", 123, "spell" }, [77] = { "spell", 999, "spell" } }
rawset(_G, "GetActionInfo", function(slot) local a = slots[slot]; if a then return a[1], a[2], a[3] end end)
local onBar, visits = { [123] = { first, second } }, 0
local ownerSwipes = {}
S.ActionBarButtonSwipe = function(button) return ownerSwipes[button] end
S.ForEachActionBarButtonForSpell = function(spell, callback)
    assert(not combat, "the action bars are visited out of combat only")
    visits = visits + 1
    local list = onBar[spell] or {}
    for i = 1, #list do callback(list[i]) end
    return #list
end
S.states = { actionbars = { active = true } }
C.Flush, C.Schedule = { dirty = {} }, function() end
C.M.active = true
C.state.font = "Fonts\\FRIZQT__.TTF"
local view = { glowStyle = 4, glowTint = false, glowR = 1, glowG = 1, glowB = 1, styleGen = 1, stackPos = 3 }
C.views.bar = view
local entry = { key = "a456", slot = "bar", auraIDs = { [456] = true }, ov = { actionGlowSpell = 123 } }
C.entries.a456 = entry
local function Aura(container) return R[container].slots.glow.buttons[1] end
local function Bound(container) return R[Aura(container)].bind end
local function Made() return #containers end
local function Size(fs) return R[fs].font[2] end
-- The presence glow's frame (AuraGlows NewGlow: the combat gate holds only
-- it) and the stack glow's clipping gate (NewStack), by what they show.
local function GlowFrame(container)
    for _, kid in ipairs(R[Aura(container)].kids or {}) do
        local s = R[kid]
        if s.kind == "Frame" and not s.calls.SetClipsChildren and s.kids and #s.kids == 1 and R[s.kids[1]].kind == "Frame" then
            return s.kids[1]
        end
    end
end
local function StackGate(container)
    for _, kid in ipairs(R[Aura(container)].kids or {}) do
        if R[kid].calls.SetClipsChildren then return kid end
    end
end
local function Lit(container) return R[GlowFrame(container)].shown == true end
local function MasksOf(region) return R[region].masks or {} end
-- Lua VM instructions of fn with the GC stopped (deterministic for one
-- interpreter build). A budget is a measured cost plus 2 % (the aura
-- contract's rule): a pass may get cheaper, never dearer.
local function Cost(fn, ...)
    local n = 0
    collectgarbage("stop")
    debug.sethook(function() n = n + 1 end, "", 1)
    fn(...)
    debug.sethook()
    collectgarbage("restart")
    return n
end
local function Budget(label, used, baseline)
    local cap = math.floor(baseline * 1.02)
    assert(used <= cap, ("%s: %d instructions, budget %d (+2%%)"):format(label, used, cap))
    if os.getenv("MSUF_TEST_COSTS") == "1" then print(label, used) end
end

------------------------------------------------------------------ default: the glow only
local made = Made()
bridge.Refresh()
assert(bridge.wanted and Made() == made + 2, "glow only: one container per action button")
local glowA, glowB = containers[made + 1], containers[made + 2]
do
    local b = Bound(glowA)
    assert(not (b.icon or b.cooldown or b.text or b.count or b.bar or b.name), "glow only binds no aura display")
    assert((b.shownAnims or 0) > 0 and R[glowA].enabled and R[glowB].enabled and Lit(glowA), "the presence glow is built as before")
    assert(not Subscribed() and registrations == 0, "the glow only listens to no style event")
    local writes = W.tally.writes
    bridge.Refresh()
    assert(W.tally.writes == writes and Made() == made + 2, "an unchanged glow-only pass writes nothing")
    -- 0.1.20's ActionGlows.lua runs this pass (the client-faithful `type`
    -- above, this world) in 1355 instructions: the default may cost 2 % more
    -- at most (it costs less: each pass gives an entry its kind once).
    Budget("glow-only pass, two buttons", Cost(bridge.Refresh), 1355)
end

------------------------------------------------------------------ each display
local EXPECT = {
    [DISPLAY.ICON] = { icon = true },
    [DISPLAY.FULL] = { icon = true, cooldown = true, text = true, count = true },
    [DISPLAY.SWIPE] = { cooldown = true },
    [DISPLAY.TIME] = { text = true },
    [DISPLAY.STACKS] = { count = true },
}
local byDisplay = {}
local function CheckRegions(display, c)
    local want, b, aura = EXPECT[display], Bound(c), Aura(c)
    for _, key in ipairs({ "icon", "cooldown", "text", "count" }) do
        assert((b[key] ~= nil) == (want[key] == true), "display " .. display .. ": binding " .. key)
    end
    assert(not (b.bar or b.name), "no bar or name on an action button")
    assert((b.shownAnims or 0) > 0 and Lit(c), "display " .. display .. ": the glow stays")
    local base = R[aura].level
    if b.icon then
        local crop = Args(b.icon, "SetTexCoord")
        assert(R[b.icon].allPoints == firstIcon and crop[1] == .1 and crop[2] == .9 and crop[3] == .12 and crop[4] == .88,
            "the aura icon covers the action icon with its crop")
        assert(#MasksOf(b.icon) == 0 and Calls(b.icon, "AddMaskTexture") == 0, "a square action icon: no mask")
    end
    if b.cooldown then
        local cd, swipe = b.cooldown, Args(b.cooldown, "SetSwipeColor")
        assert(R[cd].allPoints == firstIcon and swipe[4] == .55 and Args(cd, "SetReverse")[1] == true
            and Args(cd, "SetDrawEdge")[1] == false and Args(cd, "SetHideCountdownNumbers")[1] == true
            and Args(cd, "SetDrawBling")[1] == false, "the duration swipe: the aura swipe over the action icon")
        assert(Calls(cd, "SetSwipeTexture") == 0, "a square swipe keeps its template's texture")
        assert(R[cd].level == base + 1, "the swipe sits under the glow")
    end
    local top = b.cooldown and base + 3 or base + 2
    if b.text then
        assert(b.textOpts and b.textOpts.binding and Size(b.text) == 13 and R[R[b.text].parent].level == top,
            "duration text: a binding, the automatic countdown size, above the glow")
        local point = R[b.text].points[1]
        assert(point[1] == "CENTER" and point[2] == firstIcon, "duration text centered on the action icon")
    end
    if b.count then
        local point = R[b.count].points[1]
        assert(b.countFormatter == nil and Size(b.count) == 10 and point[1] == "TOPRIGHT" and point[2] == firstIcon
            and point[4] == -2 and point[5] == -2 and R[R[b.count].parent].level == top,
            "stack count: Blizzard's own rule at the bar's stack position, above the glow")
    end
end
for _, display in ipairs({ DISPLAY.ICON, DISPLAY.FULL, DISPLAY.SWIPE, DISPLAY.TIME, DISPLAY.STACKS }) do
    entry.ov.actionAuraDisplay = display
    local before = Made()
    bridge.Refresh()
    assert(Made() == before + 2, "display " .. display .. ": its own record per button")
    local a, b = containers[before + 1], containers[before + 2]
    assert(R[a].parent == first and R[b].parent == second and R[a].enabled and R[b].enabled, "display on both buttons")
    assert(not R[glowA].enabled and not R[glowB].enabled, "the glow-only records are free")
    assert(R[Aura(a)].allPoints == first, "the display's aura button covers the action button")
    CheckRegions(display, a)
    byDisplay[display] = { a, b }
end
assert(Subscribed() and registrations == 1, "a display listens to the action bars' style event, subscribed once")
local fullA, fullB = byDisplay[DISPLAY.FULL][1], byDisplay[DISPLAY.FULL][2]
local full, fullSecond = Bound(fullA), Bound(fullB)

-- Back to the glow only: the glow-only records come back, nothing is built,
-- and the style event is let go.
entry.ov.actionAuraDisplay = nil
made = Made()
bridge.Refresh()
assert(Made() == made and R[glowA].enabled and R[glowB].enabled, "clearing the display reuses the glow-only records")
for _, pair in pairs(byDisplay) do assert(not R[pair[1]].enabled and not R[pair[2]].enabled, "display records are free") end
assert(not Subscribed(), "no display: no style subscription")
-- A specialization's explicit first choices mean the same as absent ones.
entry.ov.actionAuraDisplay, entry.ov.actionAuraGlow = DISPLAY.GLOW, GLOW.SHOW
bridge.Refresh()
assert(Made() == made and R[glowA].enabled and Lit(glowA) and not Subscribed(), "explicit Glow only and Show: the default")
-- Unheard while no display listened: a new zoom. Subscribing again reads
-- the action icon again.
R[firstIcon].coords = { .2, .2, .2, .8, .8, .2, .8, .8 }
entry.ov.actionAuraGlow = nil
entry.ov.actionAuraDisplay = DISPLAY.FULL
bridge.Refresh()
assert(Made() == made and R[fullA].enabled and R[fullB].enabled and not R[glowA].enabled, "a freed display record is taken again")
assert(Subscribed() and registrations == 2, "and the style event with it")
assert(Args(full.icon, "SetTexCoord")[1] == .2, "a new subscription reads the look it did not hear change")
R[firstIcon].coords = { .1, .12, .1, .88, .9, .12, .9, .88 }
Restyled()
W.RunTimers()
assert(Args(full.icon, "SetTexCoord")[1] == .1, "the old crop back")
do
    local writes = W.tally.writes
    bridge.Refresh()
    assert(W.tally.writes == writes, "an unchanged display pass writes nothing")
    -- 2121 for this pass before the action icon's masks were read (round 1):
    -- the masks add their reads, the kinds take more away.
    Budget("full display pass, two buttons", Cost(bridge.Refresh), 2121)
end

------------------------------------------------------------------ looks
do
    local binds, opts = full.textBinds, full.textOpts
    entry.ov.threshold = 5
    bridge.Refresh()
    assert(full.textBinds == binds + 1 and full.textOpts ~= opts, "a warning threshold rebinds the countdown")
    bridge.Refresh()
    assert(full.textBinds == binds + 1, "the same threshold binds nothing")
    local colors = Calls(full.text, "SetTextColor")
    C.state.cdR = .5
    view.styleGen = 2
    bridge.Refresh()
    assert(Calls(full.text, "SetTextColor") == colors + 1 and Args(full.text, "SetTextColor")[1] == .5,
        "a new style generation restyles the display")
    -- An unreadable action icon crop (after the action bars' style event)
    -- falls back to Blizzard's border crop.
    R[firstIcon].coords = { Secret(), Secret(), Secret(), Secret(), Secret(), Secret(), Secret(), Secret() }
    Restyled()
    W.RunTimers()
    local crop = Args(full.icon, "SetTexCoord")
    assert(crop[1] == .08 and crop[2] == .92 and crop[3] == .08 and crop[4] == .92, "a secret crop is never used")
    R[firstIcon].coords = { .1, .12, .1, .88, .9, .12, .9, .88 }
    Restyled()
    W.RunTimers()
    assert(Args(full.icon, "SetTexCoord")[1] == .1, "a readable crop again")
end

------------------------------------------------------------------ the action bars' style: zoom and shape
-- The action bars restyle a button (zoom, shape): nothing polls; their
-- style event arms one trailing pass, which takes the new crop and the
-- owner's own masks. A shaped swipe takes the first mask's file.
do
    local circle = OwnMask(first, "Interface\\AddOns\\Host\\circle_mask.tga")
    R[firstIcon].masks = { circle }
    R[firstIcon].coords = { .15, .15, .15, .85, .85, .15, .85, .85 }
    local armed, passes = W.Armed(), visits
    assert(#MasksOf(full.icon) == 0 and Args(full.icon, "SetTexCoord")[1] == .1, "nothing reads the button before its event")
    for _ = 1, 5 do Restyled() end
    assert(W.Armed() == armed + 1 and visits == passes, "a burst of style events arms one trailing pass")
    W.RunTimers()
    local crop = Args(full.icon, "SetTexCoord")
    assert(crop[1] == .15 and crop[2] == .85 and visits == passes + 1, "the new zoom: the action icon's new crop")
    assert(MasksOf(full.icon)[1] == circle and #MasksOf(full.icon) == 1, "the shape: the owner's mask on the aura icon")
    assert(Args(full.cooldown, "SetSwipeTexture")[1] == "Interface\\AddOns\\Host\\circle_mask.tga",
        "the swipe takes the mask's file as its silhouette")
    assert(#MasksOf(fullSecond.icon) == 0 and Calls(fullSecond.cooldown, "SetSwipeTexture") == 0,
        "the other button keeps its own (square) look")
    -- New paths, first measured on 2026-11-17 (this world's method calls
    -- run through Lua): the event only arms the pass; the pass after it reads
    -- each display's action icon once (crop, masks) and writes nothing.
    local writes = W.tally.writes
    Budget("style event", Cost(Restyled), 71)
    Budget("unchanged style pass", Cost(W.RunTimers), 2615)
    assert(W.tally.writes == writes, "an unchanged style writes nothing")
    -- Another shape: the old mask goes, the new comes.
    local diamond = OwnMask(first, "Interface\\AddOns\\Host\\diamond_mask.tga")
    R[firstIcon].masks = { diamond }
    Restyled()
    W.RunTimers()
    assert(MasksOf(full.icon)[1] == diamond and #MasksOf(full.icon) == 1 and Args(full.icon, "RemoveMaskTexture")[1] == circle
        and Args(full.cooldown, "SetSwipeTexture")[1] == "Interface\\AddOns\\Host\\diamond_mask.tga", "a new shape swaps the mask")
    -- A second mask of the owner (the silhouette stays the first's): the
    -- icon takes both.
    local edge = OwnMask(first, "Interface\\AddOns\\Skin\\edge_mask.tga")
    R[firstIcon].masks = { diamond, edge }
    Restyled()
    W.RunTimers()
    assert(MasksOf(full.icon)[1] == diamond and MasksOf(full.icon)[2] == edge and #MasksOf(full.icon) == 2
        and Calls(full.cooldown, "SetSwipeTexture") == 2, "another mask joins; the silhouette stays")
    -- An atlas mask (MSUF's Blizzard portrait) shapes the icon; the swipe
    -- never takes its file (the atlas's whole sheet) and is square again.
    local portrait = OwnMask(first, "Interface\\UnitFrame\\UIUnitFramePlayerPortrait", "UI-HUD-UnitFrame-Player-Portrait-Mask")
    R[firstIcon].masks = { portrait }
    Restyled()
    W.RunTimers()
    assert(MasksOf(full.icon)[1] == portrait and Args(full.cooldown, "SetSwipeTexture")[1] == WHITE,
        "an atlas mask: the icon shaped, the swipe square")
    ownerSwipes[first] = "Interface\\AddOns\\Host\\portrait_fill.tga"
    Restyled()
    W.RunTimers()
    assert(Args(full.cooldown, "SetSwipeTexture")[1] == ownerSwipes[first]
        and MasksOf(full.icon)[1] == portrait, "owner metadata must supply the exact atlas swipe")
    ownerSwipes[first] = nil
    -- Only the action button's own masks: a foreign one is never borrowed.
    local foreign = OwnMask(second, "Interface\\AddOns\\Other\\star.tga")
    R[firstIcon].masks = { foreign, circle }
    Restyled()
    W.RunTimers()
    assert(MasksOf(full.icon)[1] == circle and #MasksOf(full.icon) == 1
        and Args(full.cooldown, "SetSwipeTexture")[1] == "Interface\\AddOns\\Host\\circle_mask.tga", "a foreign mask is skipped")
    -- Secret answers are never used: an unreadable hierarchy leaves the
    -- display square, an unreadable mask or file is skipped.
    R[firstIcon].secretMasks = true
    Restyled()
    W.RunTimers()
    assert(#MasksOf(full.icon) == 0 and Args(full.cooldown, "SetSwipeTexture")[1] == WHITE, "a secret mask count: square")
    R[firstIcon].secretMasks = nil
    R[firstIcon].masks = { Secret(), circle }
    Restyled()
    W.RunTimers()
    assert(MasksOf(full.icon)[1] == circle and #MasksOf(full.icon) == 1, "a secret mask is skipped")
    local hidden = OwnMask(first, Secret())
    R[firstIcon].masks = { hidden }
    Restyled()
    W.RunTimers()
    assert(MasksOf(full.icon)[1] == hidden and Args(full.cooldown, "SetSwipeTexture")[1] == WHITE,
        "a mask with a secret file shapes the icon; the swipe stays square")
    -- In combat the sealed display waits; the end of combat applies the shape.
    State(true, false, true)
    R[firstIcon].masks = { circle }
    Restyled()
    W.RunTimers()
    assert(bridge.pending and MasksOf(full.icon)[1] == hidden, "combat keeps the sealed display's shape until it ends")
    State(false, true, false)
    bridge.Refresh()
    assert(not bridge.pending and MasksOf(full.icon)[1] == circle and #MasksOf(full.icon) == 1,
        "the end of combat applies the new shape")
    -- Square again.
    R[firstIcon].masks = {}
    R[firstIcon].coords = { .1, .12, .1, .88, .9, .12, .9, .88 }
    Restyled()
    W.RunTimers()
    assert(#MasksOf(full.icon) == 0 and Args(full.cooldown, "SetSwipeTexture")[1] == WHITE
        and Args(full.icon, "SetTexCoord")[1] == .1, "square again: no mask, the square swipe, the old crop")
end

------------------------------------------------------------------ the action bars' style: size
do
    R[first].w, R[first].h = 48, 48
    Restyled()
    W.RunTimers()
    assert(Size(full.text) == 18 and Size(full.count) == 14 and Made() == made, "text sizes follow the height; nothing built")
    -- In combat the sealed texts wait; the end of combat restyles them.
    State(true, false, true)
    R[first].w, R[first].h = 40, 40
    Restyled()
    W.RunTimers()
    assert(bridge.pending and Size(full.text) == 18, "combat keeps the sealed display until it ends")
    State(false, true, false)
    bridge.Refresh()
    assert(not bridge.pending and Size(full.text) == 15, "the end of combat restyles the display")
    R[first].w, R[first].h = nil, nil
    Restyled()
    W.RunTimers()
    assert(Size(full.text) == 13, "back to its size")
end

------------------------------------------------------------------ the display without its glow
local stacked -- the stack glow and stack count record of the first button
do
    made = Made()
    entry.ov.actionAuraGlow = GLOW.HIDE
    bridge.Refresh()
    assert(Made() == made and R[fullA].enabled and R[fullB].enabled and not Lit(fullA) and not Lit(fullB),
        "a hidden glow: the same records, their glows dark")
    assert(full.icon and full.cooldown and full.text and full.count and Subscribed(), "the display stays bound")
    local writes = W.tally.writes
    bridge.Refresh()
    assert(W.tally.writes == writes, "an unchanged hidden glow writes nothing")
    entry.ov.actionAuraGlow = nil
    bridge.Refresh()
    assert(Made() == made and Lit(fullA) and Lit(fullB), "the glow back on the same records")
    -- Nothing to show (Glow only and a hidden glow): nothing wanted.
    entry.ov.actionAuraDisplay, entry.ov.actionAuraGlow = nil, GLOW.HIDE
    C.Flush.dirty.events = nil
    bridge.Refresh()
    assert(not bridge.wanted and C.Flush.dirty.events and not R[fullA].enabled and not R[glowA].enabled
        and not R[glowB].enabled and not Subscribed() and Made() == made, "nothing to show: no record, no event, no callback")
    local armed = W.Armed()
    bridge.RouteChanged()
    assert(W.Armed() == armed, "nothing wanted: a route arms nothing")
    -- The stack glow hides as well: its gate stays shut, the stacks show.
    entry.ov.actionGlowMode, entry.ov.stackGlow, entry.ov.actionAuraDisplay = CDM.ACTION_GLOW.STACKS, 3, DISPLAY.STACKS
    bridge.Refresh()
    stacked = containers[made + 1]
    local b = Bound(stacked)
    assert(Made() == made + 2 and b.appBar and b.count and not R[StackGate(stacked)].shown, "a hidden stack glow keeps its gate shut")
    entry.ov.actionAuraGlow = nil
    bridge.Refresh()
    assert(Made() == made + 2 and R[StackGate(stacked)].shown and b.appOpts.maxApplications == 3,
        "shown again: the gate opens at its threshold on the same record")
    entry.ov.actionGlowMode, entry.ov.stackGlow, entry.ov.actionAuraDisplay = nil, nil, DISPLAY.FULL
    bridge.Refresh()
    assert(R[fullA].enabled and R[fullB].enabled and Lit(fullA) and not R[stacked].enabled, "back to the full display")
    made = Made()
end

------------------------------------------------------------------ secret aura values
-- Blizzard writes secret values into the bound regions; no Lua path of the
-- bridge reads, compares or forwards them (the sentinels raise on any use).
do
    R[full.text].text, R[full.count].text, R[full.cooldown].value = Secret(), Secret(), Secret()
    State(true, false, true)
    bridge.RouteChanged()
    W.RunTimers()
    bridge.Refresh()
    bridge.TargetChanged()
    Restyled()
    W.RunTimers()
    entry.ov.actionAuraDisplay = DISPLAY.ICON
    made = Made()
    bridge.Refresh()
    assert(bridge.pending and Made() == made and R[fullA].enabled, "a secret or combat edit builds nothing and keeps the display")
    State(false, true, false)
    bridge.Refresh()
    assert(not R[fullA].enabled and R[byDisplay[DISPLAY.ICON][1]].enabled and Made() == made, "the edit applies once auras open")
    entry.ov.actionAuraDisplay = DISPLAY.FULL
    bridge.Refresh()
    -- An unreadable button size: that button is not decorated this pass.
    R[second].w = Secret()
    bridge.Refresh()
    assert(R[fullA].enabled and not R[fullB].enabled, "an unreadable size never reaches the display")
    R[second].w = nil
    bridge.Refresh()
    assert(R[fullB].enabled, "a readable size decorates again")
end

------------------------------------------------------------------ spell and page changes
do
    -- In combat a page or form change moves the second button to another
    -- spell: its display goes with the glow, by plain slot reads only.
    State(true, false, true)
    local before = visits
    R[second].attrs.action = 77
    bridge.RouteChanged()
    W.RunTimers()
    assert(R[fullA].enabled and not R[fullB].enabled and visits == before, "a paged button's display goes off in combat")
    R[second].attrs.action = 6
    bridge.RouteChanged()
    W.RunTimers()
    assert(R[fullB].enabled, "paged back: the display comes back")
    State(false, true, false)
    bridge.Refresh()
    -- Out of combat the spell leaves a button: its record is free and taken again.
    onBar[123] = { first }
    bridge.Refresh()
    assert(R[fullA].enabled and not R[fullB].enabled, "a button without the spell keeps no display")
    onBar[123] = { first, second }
    made = Made()
    bridge.Refresh()
    assert(R[fullB].enabled and Made() == made, "back on the bar: the freed record is taken again")
    -- Another action-bar spell moves the display to that spell's buttons.
    local third = ActionButton(77)
    onBar[999] = { third }
    entry.ov.actionGlowSpell = 999
    bridge.Refresh()
    local moved = containers[made + 1]
    assert(Made() == made + 1 and R[moved].parent == third and Bound(moved).text and not R[fullA].enabled
        and not R[fullB].enabled, "the display follows the spell to its buttons")
    entry.ov.actionGlowSpell = 123
    bridge.Refresh()
    assert(R[fullA].enabled and R[fullB].enabled and not R[moved].enabled, "and back")
end

------------------------------------------------------------------ with the other bridge choices
do
    -- Stack glow and stack count share one aura button.
    entry.ov.actionGlowMode, entry.ov.stackGlow, entry.ov.actionAuraDisplay = CDM.ACTION_GLOW.STACKS, 3, DISPLAY.STACKS
    made = Made()
    bridge.Refresh()
    local b = Bound(stacked)
    assert(Made() == made and R[stacked].enabled and b.appBar and b.appOpts.maxApplications == 3 and b.count and not b.text
        and R[StackGate(stacked)].shown, "stack glow and stack count together (the record of the hidden-glow check)")
    entry.ov.actionGlowMode, entry.ov.stackGlow, entry.ov.actionAuraDisplay = nil, nil, DISPLAY.FULL
    -- A required buff: the display is the inner (primary) aura's, inside the gate.
    entry.ov.actionGlowRequireSpell = 321
    made = Made()
    bridge.Refresh()
    assert(Made() == made + 4, "two native levels per button")
    local outer, inner = containers[made + 1], containers[made + 2]
    local gate, main = Bound(outer), Bound(inner)
    assert(R[inner].parent == Aura(outer) and not (gate.icon or gate.text or gate.count or gate.cooldown)
        and main.icon and main.text and main.count and main.cooldown, "the display shows only with both auras")
    entry.ov.actionGlowRequireSpell = nil
    bridge.Refresh()
    assert(not R[outer].enabled and R[fullA].enabled, "clearing the required buff restores the display record")
end

------------------------------------------------------------------ same-pass reuse
-- Before a pass, a record whose entry no longer wants its display is free,
-- so another entry with that display on the button takes it in that pass.
do
    local other = { key = "a789", slot = "bar", auraIDs = { [789] = true },
        ov = { actionGlowSpell = 123, actionAuraDisplay = DISPLAY.FULL } }
    entry.ov.actionAuraDisplay = nil
    C.entries.a789 = other
    made = Made()
    bridge.Refresh()
    assert(Made() == made and R[fullA].enabled and R[fullB].enabled and R[glowA].enabled and R[glowB].enabled
        and R[fullA].slots.glow.cand.includeSpellIDs[789] and not R[fullA].slots.glow.cand.includeSpellIDs[456],
        "the other entry takes the display records its owner let go, in the same pass")
    C.entries.a789 = nil
    entry.ov.actionAuraDisplay = DISPLAY.FULL
    bridge.Refresh()
    assert(Made() == made and R[fullA].enabled and not R[glowA].enabled and R[fullA].slots.glow.cand.includeSpellIDs[456],
        "and hands them back")
end

------------------------------------------------------------------ disabled and hidden
do
    S.states.actionbars.active = false
    bridge.Refresh()
    assert(not bridge.wanted and not R[fullA].enabled and not R[fullB].enabled and not Subscribed(),
        "action bars off: every display off, no style callback")
    local armed = W.Armed()
    Restyled()
    bridge.RouteChanged()
    assert(W.Armed() == armed, "nothing wanted: neither a style event nor a route arms a pass")
    S.states.actionbars.active = true
    bridge.Refresh()
    assert(R[fullA].enabled and R[fullB].enabled and Subscribed(), "the action bars back: the display comes back")
    C.entries.a456 = nil
    made = Made()
    bridge.Refresh()
    assert(not bridge.wanted and not R[fullA].enabled and Made() == made and not Subscribed(), "a removed entry frees its display")
    C.entries.a456 = entry
    bridge.Refresh()
    assert(Subscribed(), "the entry back: subscribed again")
    bridge.Release()
    assert(not bridge.wanted and not R[fullA].enabled and not R[fullB].enabled and not Subscribed(),
        "release turns every display off and lets the style event go")
    Restyled()
    assert(W.Armed() == armed, "a released bridge arms nothing on a style event")
    -- Glow-only entries never subscribe, whatever passes run.
    local count = registrations
    entry.ov.actionAuraDisplay = nil
    bridge.Refresh()
    bridge.Refresh()
    assert(registrations == count and not Subscribed(), "the glow only listens to nothing")
end
print("suite_cdm_action_overlays_contract: ok")
