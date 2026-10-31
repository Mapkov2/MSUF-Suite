local root = assert(arg[1], "repository root required")
-- Cooldown manager per-spell rules on the render plane (package cdm11-C):
-- "Show only when usable" and "Show only during a spell alert" hide an icon
-- through the layout's hidden state (Effects.lua, Time.lua, Index.lua),
-- "Sound when used" and "Sound when a charge returns" on the time layer's
-- edges (Alerts.lua), a timer bar's own color and name (TrackingBars.lua),
-- the active border, fill and name inside aura buttons (AuraLooks.lua), the
-- glow on a missing buff's stand-in (AuraPlaceholders.lua) and an item's use
-- buff (EntryFill.lua). Runs on the render contract's harness up to its glow
-- checks; every rule is off by default.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_render_contract.lua", [=[
do (function()
Record("SetColorTexture", function(self, r, g, b, a) self.color = { r, g, b, a } end)
Record("SetVertexColor", function(self, r, g, b, a) self.vc = { r, g, b, a } end)
Record("SetStatusBarColor", function(self, r, g, b, a) self.sbc = { r, g, b, a } end)
Record("SetText", function(self, text) self.text = text end)
local CDMNS = NS.CDM
local F = CDMNS.SPELL_FIELDS
local KIT = "kit:316406"
local function Rebind(e, ov, view)
    e.ov, view.behaviorGen = ov, view.behaviorGen + 1
    T.Refresh(e, "full")
    E.Update(e)
end
local function Source(file)
    local handle = assert(io.open(root .. "/MSUF_Suite_CooldownManager/" .. file, "rb"))
    local text = handle:read("*a"):gsub("\r", "")
    handle:close()
    return text
end
-- Each case runs alone with BH3_CASE (red proofs load one file from a baseline).

-- The catalog keeps the new choices; a specialization stores explicit
-- values (Off, the bar's color, the spell's name) apart from inheriting.
BH3("catalog", function()
    for _, key in ipairs({ "usableOnly", "procOnly", "missingGlow", "itemAura" }) do
        assert(F[key] and F[key](true) and F[key](false) and not F[key](1) and not F[key]("true"), key .. " is a switch")
    end
    for _, key in ipairs({ "activeBorder", "barColor" }) do
        assert(F[key]("ff0000") and F[key]("") and not F[key]("red") and not F[key](1), key .. " is a color or the bar's")
    end
    assert(F.barText("Big hit") and F.barText("") and not F.barText("|cffff0000x") and not F.barText(("x"):rep(41))
        and not F.barText("a\nb") and not F.barText(5), "a bar name: plain text up to 40 characters")
    assert(F.usedSound(KIT) and F.chargeSound("") and F.chargeSound("file:123") and not F.usedSound("bogus"), "sound values")
    do
        local clean = CDMNS.CleanSpells({ e = { b1 = { usableOnly = true, barColor = "ff0000", barText = "Kick", chargeSound = KIT } },
            s = { [62] = { b1 = { usableOnly = false, barColor = "", barText = "", chargeSound = "" } } } })
        local spec, shared = CDMNS.EffectiveSpells(clean, 62).b1, CDMNS.EffectiveSpells(clean, 63).b1
        assert(spec.usableOnly == false and spec.barColor == "" and spec.barText == "" and spec.chargeSound == "",
            "a specialization keeps its explicit values")
        assert(shared.usableOnly == true and shared.barColor == "ff0000" and shared.barText == "Kick", "the shared choices")
    end
end)

-- "Show only when usable": hidden while the spell is unusable, also from a
-- hidden icon; the bar relayouts on each flip.
BH3("usable", function()
    local entry, icon = b6, b6.icon
    Info(600, false, false)
    local asked = requests.uti or 0
    usable[600] = false
    Rebind(entry, { usableOnly = true }, uti)
    assert(icon.gate and entry.unusable == true and entry.gated == true and entry.hidden == true, "unusable: hidden")
    assert((requests.uti or 0) > asked, "the bar relayouts")
    T.Refresh(entry, "cooldown")
    assert(entry.hidden == true, "a cooldown refresh keeps the gate")
    -- The sweep's shared answers: a memoized answer is used, not asked again.
    local function Queries()
        return { spells = { seen = {}, usable = {}, noPower = {} }, items = { seen = {}, usable = {}, noPower = {} } }
    end
    usable[600] = nil
    local q = Queries()
    E.GateUsable(entry, q)
    assert(entry.hidden == false and entry.gated == false and q.spells.seen[600] and q.spells.usable[600] == true, "usable: shown")
    q = Queries()
    q.spells.seen[600], q.spells.usable[600] = true, false
    E.GateUsable(entry, q)
    assert(entry.hidden == true, "the flush's answer decides")
    -- A secret answer shows the icon; a hidden bar waits for its show edge.
    q.spells.usable[600] = Secret("boolean")
    E.GateUsable(entry, q)
    assert(entry.hidden == false and entry.unusable == nil, "a secret answer never hides")
    C.bars.uti.hidden = true
    usable[600] = false
    E.GateUsable(entry)
    assert(entry.hidden == true, "asked while its bar is hidden too")
    C.bars.uti.hidden = nil
    -- The preview shows every icon.
    C.state.preview = true
    T.Refresh(entry, "full")
    assert(entry.hidden == false, "the preview shows it")
    C.state.preview = false
    T.Refresh(entry, "full")
    assert(entry.hidden == true, "hidden again after the preview")
    -- Off (and every entry without it): nothing gates, nothing is asked.
    Rebind(entry, C.EMPTY, uti)
    assert(not icon.gate and entry.gated == false and entry.hidden == false, "off: the icon shows")
    usable[600] = nil
end)

-- "Show only during a spell alert": the proc state shows and hides it.
BH3("proc", function()
    overlayed[100] = nil
    Rebind(b1, { procOnly = true }, ess)
    assert(b1.hidden == true and b1.gated == true, "no spell alert: hidden")
    local asked = requests.ess or 0
    E.Proc(b1, true)
    assert(b1.hidden == false and (requests.ess or 0) > asked, "the alert shows it")
    E.Proc(b1, false)
    assert(b1.hidden == true, "the alert ended")
    overlayed[100] = true
    Rebind(b1, { procOnly = true }, ess)
    assert(b1.hidden == false, "a running alert at the bind shows it")
    overlayed[100] = nil
    E.Proc(b1, false)
    Rebind(b1, C.EMPTY, ess)
    assert(b1.hidden == false and b1.gated == false, "off: shown")
end)

-- "Sound when used": the start of a real cooldown after a known ready state.
BH3("sounds", function()
    local used, charged = 0, 0
    local alerts = C.Alerts
    C.Alerts = { Ready = alerts.Ready, Used = function() used = used + 1 end, Charge = function() charged = charged + 1 end }
    Rebind(b6, { usedSound = KIT }, uti)
    assert(b6.cooling == false, "ready")
    Info(600, true, false)
    T.Refresh(b6, "cooldown")
    assert(used == 1 and b6.cooling == true, "the cooldown started: one sound")
    T.Refresh(b6, "cooldown")
    assert(used == 1, "no edge, no sound")
    Info(600, true, true)
    Info(600, false, false)
    T.Refresh(b6, "cooldown")
    Info(600, true, true)
    T.Refresh(b6, "cooldown")
    assert(used == 1, "the global cooldown is no use")
    Info(600, false, false)
    T.Refresh(b6, "cooldown")
    b6.cooling = nil
    Info(600, true, false)
    T.Refresh(b6, "cooldown")
    assert(used == 1, "a cooldown seen first is not a use")
    Info(600, false, false)
    Rebind(b6, C.EMPTY, uti)
    Info(600, true, false)
    T.Refresh(b6, "cooldown")
    assert(used == 1, "off: silent")
    Info(600, false, false)
    T.Refresh(b6, "cooldown")
    -- "Sound when a charge returns": a running recharge swipe ran out.
    local cicon = b2.icon
    b2.ov = { chargeSound = KIT }
    cicon.chargeSet = true
    T.Done(cicon, cicon.chargeCd)
    assert(charged == 1, "a charge came back")
    cicon.chargeSet = false
    T.Done(cicon, cicon.chargeCd)
    assert(charged == 1, "no recharge ran")
    cicon.chargeSet = true
    T.Done(cicon, cicon.cd)
    assert(charged == 1, "the main swipe is no charge")
    b2.ov = C.EMPTY
    cicon.chargeSet = true
    T.Done(cicon, cicon.chargeCd)
    assert(charged == 1, "off: silent")
    C.Alerts = alerts
end)

-- The real alert layer: channel, mute, the quiet window and a gap per sound.
BH3("alerts", function()
    local alerts = C.Alerts
    Enum.UnitAuraSoundTrigger = { Added = 0, Removed = 1 }
    C.NewWake, C.Wake = function(fn) return fn end, Noop
    local played = {}
    PlaySoundFile = function(file, channel) played[#played + 1] = { file, channel }; return true end
    C_Sound = { PlaySoundWithOptions = function() return true end }
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/Alerts.lua"))("MSUF_Suite_CooldownManager", P)
    local A = C.Alerts
    C.state.soundChannel, C.state.muteSounds, C.state.soundQuietUntil = "SFX", false, 0
    local sounding = { family = 1, ov = { usedSound = KIT, chargeSound = "file:123" } }
    assert(A.Used(sounding) == true and played[1][1] == 7466004 and played[1][2] == "SFX", "a kit plays its file on the channel")
    assert(A.Used(sounding) == false and #played == 1, "a repeat within a second waits")
    assert(A.Charge(sounding) == true and played[2][1] == 123, "each sound keeps its own gap")
    now = now + 1.5
    assert(A.Used(sounding) == true, "after the gap")
    now = now + 2
    C.state.muteSounds = true
    assert(A.Charge(sounding) == false, "muted")
    C.state.muteSounds, C.state.soundQuietUntil = false, now + 5
    assert(A.Charge(sounding) == false, "the quiet window after a loading screen")
    C.state.soundQuietUntil = 0
    sounding.ov = { usedSound = "" }
    assert(A.Used(sounding) == false, "none chosen")
    assert(A.Used({ family = 2, ov = { usedSound = KIT } }) == false, "buffs sound through their aura registrations")
    C.Alerts = alerts
end)

-- A timer bar's own color and name; "" follows the bar and the spell.
BH3("bars", function()
    ess.cooldownDuration, ess.styleGen = true, ess.styleGen + 1
    b1.name, b2.name = "Fireball", "Blink"
    b1.ov = { barColor = "ff0000", barText = "Big hit" }
    I.Sync("ess")
    local bar, plain = b1.icon.timerBar, b2.icon.timerBar
    assert(bar.name.text == "Big hit" and plain.name.text == "Blink", "the entry's own name")
    assert(bar.sbc[1] == 1 and bar.sbc[2] == 0 and bar.sbc[3] == 0 and bar.r == 1 and bar.g == 0, "the entry's own color")
    assert(plain.r ~= 1 or plain.g ~= 0, "other bars keep the bar's color")
    b1.ov = { barColor = "", barText = "" }
    I.Sync("ess")
    assert(bar.name.text == "Fireball" and bar.r == plain.r and bar.g == plain.g and bar.b == plain.b,
        "a specialization's explicit values follow the bar and the spell")
    local painted = Calls(bar, "SetStatusBarColor")
    I.Sync("ess")
    assert(Calls(bar, "SetStatusBarColor") == painted, "an unchanged sync paints nothing")
    b1.ov = C.EMPTY
    ess.cooldownDuration, ess.styleGen = false, ess.styleGen + 1
    I.Sync("ess")
end)

-- Aura buttons: the border while active, a buff bar's fill and name, with
-- the dry/write contract of AuraButtons' ApplyEntry.
BH3("looks", function()
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/AuraLooks.lua"))("MSUF_Suite_CooldownManager", P)
    local Looks = C.AuraLooks
    local button = CreateFrame("Frame")
    local part = { button = button, edges = K.NewEdges(button), bar = CreateFrame("StatusBar"), bg = button:CreateTexture(),
        name = button:CreateFontString(), label = button:CreateFontString() }
    local lk = { er = 0, eg = 0, eb = 0, bw = 0, px = 1, shape = K.SQUARE, fr = .5, fg = .5, fb = .5, bgA = .5 }
    local rec = { role = "icon", lk = lk }
    local quiet = writes
    assert(Looks.Apply(rec, part, C.EMPTY, true) == false and Looks.Apply(rec, part, C.EMPTY, false) == false and writes == quiet,
        "nothing chosen: nothing written")
    local border = { activeBorder = "ff0000" }
    assert(Looks.Apply(rec, part, border, true) == true and writes == quiet, "dry: reports the write")
    Looks.Apply(rec, part, border, false)
    local edge = part.edges[1]
    assert(edge.shown and edge.last.SetHeight == 1 and edge.color[1] == 1 and edge.color[2] == 0, "a one pixel red border")
    assert(part.looked == true, "the part remembers it shows a look")
    assert(Looks.Apply(rec, part, border, true) == false, "painted: nothing more")
    Looks.Restyled(part)
    assert(Looks.Apply(rec, part, border, true) == true, "a restyle paints it again")
    Looks.Apply(rec, part, border, false)
    Looks.Apply(rec, part, { activeBorder = "" }, false)
    assert(not edge.shown and part.looked == false, "the bar's border again (none)")
    lk.bw = 2
    Looks.Restyled(part)
    Looks.Apply(rec, part, border, false)
    assert(edge.last.SetHeight == 2, "a wider bar border keeps its width")
    lk.shape, part.rings = "CIRCLE", { button:CreateTexture(), button:CreateTexture() }
    Looks.Restyled(part)
    Looks.Apply(rec, part, { activeBorder = "00ff00" }, false)
    assert(part.rings[2].vc[1] == 0 and part.rings[2].vc[2] == 1, "a shaped button tints its rings")
    lk.shape, part.rings, lk.bw = K.SQUARE, nil, 0
    assert(Looks.Apply(rec, part, { barColor = "00ff00", barText = "Kick" }, false) == false and not part.label.text,
        "icons have no fill or name")
    rec.role = "bar"
    Looks.Restyled(part)
    Looks.Apply(rec, part, { barColor = "00ff00", barText = "Kick" }, false)
    assert(part.bar.sbc[2] == 1 and part.bg.vc[2] == .25 and part.bg.vc[4] == .5, "the bar's own fill")
    assert(part.label.text == "Kick" and part.label.shown and part.name.last.SetAlpha == 0, "the bar's own name")
    Looks.Restyled(part)
    assert(Looks.Apply(rec, part, { barColor = "00ff00", barText = "Kick" }, true) == true, "a restyle repaints the fill")
    Looks.Apply(rec, part, { barColor = "00ff00", barText = "Kick" }, false)
    assert(Looks.Apply(rec, part, { barColor = "00ff00", barText = "Kick" }, true) == false, "the name survives a restyle")
    Looks.Apply(rec, part, C.EMPTY, false)
    assert(not part.label.shown and part.name.last.SetAlpha == 1 and part.bar.sbc[1] == .5, "back to the spell's name and bar color")
    -- Buttons ask only where the bar's entries choose a look or still show
    -- one, so a bar without these choices pays two reads per button.
    local function Text(file)
        local handle = assert(io.open(root .. "/MSUF_Suite_CooldownManager/" .. file, "rb"))
        local text = handle:read("*a"):gsub("\r", "")
        handle:close()
        return text
    end
    assert(Text("AuraButtons.lua"):find("if (rec.looks or part.looked) and Looks.Apply(rec, part, ov, dry) then return true end", 1, true),
        "ApplyEntry asks only where wanted")
    assert(Text("AuraContainers.lua"):find("rec.looks = need.looks\n", 1, true)
        and Text("Auras.lua"):find("if looks and (ov.activeBorder or ov.barColor or ov.barText) then\n                need.looks = true", 1, true),
        "a bar's entries decide, while a choice uses a look")
end)

-- "Glow while missing": the stand-in of a missing buff glows, under its slot.
BH3("missing", function()
    C.AuraButtons = C.AuraButtons or {}
    C.Layout.Cell = function(slot, i) return C.bars[slot].cells[i] end
    local cellA, cellB = CreateFrame("Frame"), CreateFrame("Frame")
    C.bars.buf = { cells = { cellA, cellB } }
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/AuraPlaceholders.lua"))("MSUF_Suite_CooldownManager", P)
    local B = C.AuraButtons
    local view = { showMissing = false, glowStyle = 1, glowTint = false, maxIcons = 0 }
    local meta = { fixed = true, role = "icon", look = "L", lk = { l = 0, r = 1, t = 0, b = 1, bw = 0, px = 1, w = 30, h = 30, shape = K.SQUARE } }
    local missing = { key = "a1", src = "a", ov = { missingGlow = true }, texture = 5, name = "Buff" }
    local other = { key = "a2", src = "a", ov = C.EMPTY, texture = 6, name = "Other" }
    local plan = { entries = { missing, other } }
    assert(B.Held(missing, view, false) and not B.Held(other, view, false), "a glow holds the stand-in")
    B.Placeholders("buf", view, plan, meta, false)
    local g = assert(C.Diagnostics.MissingGlow(cellA), "the missing buff glows")
    assert(not C.Diagnostics.MissingGlow(cellB), "another missing buff without it does not")
    assert(g.shown and g.parent == cellA and g.level == cellA.level, "a frame at its cell's level, under the slot button")
    assert(g.flip.shown and g.book.playing and g.flip.last.SetAtlas == K.GLOW[1].atlas, "the bar's alert style plays")
    missing.ov = { missingGlow = true, glowStyle = 4, glowColor = "00ff00" }
    B.Placeholders("buf", view, plan, meta, false)
    assert(not g.flip.shown and not g.book.playing and g.edges[1].shown and g.edges[1].color[2] == 1, "the spell's border style")
    missing.ov = { missingGlow = true, glowStyle = 3 }
    B.Placeholders("buf", view, plan, meta, false)
    assert(g.pulse.playing and g.edges[1].shown, "the pulse pulses")
    C.state.allGlowsCombat = true
    E.CombatChanged()
    assert(not g.shown, "only in combat: hidden outside")
    C.state.inCombat = true
    E.CombatChanged()
    assert(g.shown, "shown in combat")
    C.state.inCombat, C.state.allGlowsCombat = false, false
    E.CombatChanged()
    B.Placeholders("buf", view, plan, meta, true)
    assert(not g.shown and not C.Diagnostics.MissingGlow(cellA), "the preview shows samples, not the glow")
    missing.ov = { missingGlow = true }
    B.Placeholders("buf", view, plan, meta, false)
    assert(g.shown, "back after the preview")
    missing.ov = C.EMPTY
    B.Placeholders("buf", view, plan, meta, false)
    assert(not g.shown and not C.Diagnostics.MissingGlow(cellA), "off: the glow goes with the stand-in")
end)

-- An item's use buff: the entry looks for that spell's aura on the player.
BH3("item", function()
    C.Catalog = { Num = function(v) return type(v) == "number" and v or nil end, ItemIcon = function() return 1001 end,
        ItemSpell = function() return 5000 end, ItemName = function() return "Trinket" end, EquipItem = function() return 7000 end,
        EquipTexture = function() return 1002 end, SlotLabel = function() return "Trinket 1" end }
    local choices = { i7000 = { itemAura = true }, e13 = { itemAura = true }, i7001 = { stackText = 2 } }
    C.Choices = function() return choices end
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/EntryFill.lua"))("MSUF_Suite_CooldownManager", P)
    -- A fill reads the item's choice in effect.
    local filled = {}
    assert(C.EntryFill.Fill(filled, "i7000") and filled.hasAura and filled.auraIDs[5000] and filled.unit == "player",
        "an item with the choice looks for its use buff")
    assert(C.EntryFill.Fill(filled, "i7001") and not filled.hasAura and filled.auraIDs == nil and filled.unit == nil,
        "without it: no buff")
    local equipped = {}
    assert(C.EntryFill.Fill(equipped, "e13") and equipped.hasAura and equipped.auraIDs[5000], "an equipment slot's item too")
    assert(C.EntryFill.Fill(equipped, "e14") and not equipped.hasAura, "another slot without it")
    local item = { src = "i", spell = 5000 }
    C.EntryFill.ItemAura(item)
    assert(item.hasAura and item.selfAura and item.auraHelpful and item.unit == "player" and item.auraIDs[5000], "the use buff")
    local spellEntry, empty = { src = "s", spell = 5000 }, { src = "e" }
    C.EntryFill.ItemAura(spellEntry)
    C.EntryFill.ItemAura(empty)
    assert(not spellEntry.hasAura and not empty.hasAura, "items with a use spell only")
    assert(Source("Auras.lua"):find("ok = view.showAura == true or ov.itemAura == true", 1, true), "its overlay shows it")
end)

-- Routing (Index.lua): the usable sweep's gate list, the proc events and
-- the item's overlay join only for entries that ask.
BH3("index", function()
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/Index.lua"))("MSUF_Suite_CooldownManager", P)
    local X = C.Index
    local function Has(list, e)
        for i = 1, #list do if list[i] == e then return true end end
        return false
    end
    ess.procGlow, uti.procGlow, ess.showAura = false, false, false
    X.Rebuild()
    assert(#X.gated == 0 and not Has(X.proc, b1) and not Has(X.overlay, e13), "nothing asked: nothing joins")
    b6.ov, b1.ov = { usableOnly = true }, { procOnly = true }
    e13.ov, e13.hasAura, e13.auraIDs = { itemAura = true }, true, { [5000] = true }
    X.Rebuild()
    assert(#X.gated == 0 and not Has(X.proc, b1), "their own pass runs only while a choice uses one")
    C.routedChoices = true
    X.Rebuild()
    assert(#X.gated == 1 and X.gated[1] == b6, "the gate list")
    assert(Has(X.proc, b1) and Has(X.overlay, e13), "the alert events and the item's overlay")
    b6.ov, b1.ov, e13.ov, e13.hasAura, e13.auraIDs = C.EMPTY, C.EMPTY, C.EMPTY, nil, nil
    X.Rebuild()
    C.routedChoices = nil
    -- The gate list swaps in its own event handler and sweep; without it the
    -- plain ones run as before. Settings marks when a choice needs the pass.
    local events = Source("Events.lua")
    assert(events:find("    Flush.Gated(gated)\n    Want(\"SPELL_UPDATE_USABLE\", #Index.usable > 0 or gated, gated and OnUsableGated or OnUsable)",
        1, true), "the usable event serves the gate list")
    local flush = Source("Flush.lua")
    assert(flush:find("function Flush.Gated(on) usableUnit = on and GatedUsableUnit or UsableUnit end", 1, true)
        and flush:find('Run(dirty, "usable", true, usableUnit)', 1, true)
        and flush:find("for i = 1, #list do fx.GateUsable(list[i], usableQueries) end", 1, true), "the usable sweep asks the gate list")
    assert(Source("Settings.lua"):find("C.routedChoices, C.lookChoices = Chosen(C.spells, ROUTED), Chosen(C.spells, LOOKS)", 1, true),
        "decoded choices mark the pass and the looks")
end)
print("suite_cdm_perspell_contract: ok")
end)() end
]=], "------------------------------------------------------------------ Effects: glows")
