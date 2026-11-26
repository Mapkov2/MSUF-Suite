local root = assert(arg[1], "repository root required"):gsub("\\", "/")
-- Nameplate names in restricted combat (MSUF_Suite_Nameplates/NameText.lua).
-- 2026-11-11 raid trace (300 s, 24 players): the CompactUnitFrame_UpdateName
-- post-hook ran 54,237 times; 24,911 of them reached a mapped plate whose
-- name was secret, so nothing could be painted and the state was dropped to
-- its unit mapping (ForgetPlain) every time, a pairs() walk that removes
-- nothing new after the first one. This contract holds:
--   * budget: a secret native update of a plate that holds no captured name
--     stays under the VM instruction budgets in NameText.lua and the shared safety wrappers, walks no table
--     (no pairs()/next()) and keeps the same native safety and text queries;
--   * frames: that update runs the hook alone, no other Lua function of
--     NameText.lua (2026-11-15 raid trace: 10,213 of 24,848 hook runs each
--     entered ReadLabel, 10,169 Protected; 10,153 then read a secret name);
--   * premise: a state without the captured mark (a Capture that succeeded
--     since the last Clear; raw alone is not it, a shown label without text
--     captures nil) holds no field but unit, prefix, look and nativeDirty,
--     after every step of a random walk through native updates (secret, nil
--     and plain names), skin passes, releases and settings;
--   * equivalence: the same walk on a copy of NameText.lua whose ForgetPlain
--     always clears (the code before the trace) ends every step with the
--     same label text, colors, writes and state.
local SOURCE = root .. "/MSUF_Suite_Nameplates/NameText.lua"
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local IDLE_BUDGET, COMBAT_BUDGET = 63, 79
local idleSpent, combatSpent
local checks = 0
local function Check(value, message)
    checks = checks + 1
    if not value then error(message, 2) end
end

local function ReadSource()
    local file = assert(io.open(SOURCE, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

-- One NameText instance with its own frames, counters and settings.
local function Instance(text, name)
    local world = { combat = false, natives = 0, writes = 0, gen = 0 }
    local isSecret = function(v) return rawequal(v, SECRET) end
    local function Public(value) return not isSecret(value) end
    local function IsForbidden(frame)
        return frame and type(frame.IsForbidden) == "function" and frame:IsForbidden() == true
    end
    -- Count the Lua wrappers that the old path called. The client mock
    -- methods and its secret predicate stand in for C functions.
    local wrappers = { [Public] = true, [IsForbidden] = true }
    local S = {
        Public = Public,
        Finite = function(v) return not rawequal(v, SECRET) and type(v) == "number" and v == v end,
    }
    -- Compiled looks carry an id so two instances compare by meaning; the
    -- formatter and the color painter write their own fields into the state,
    -- as the host's do (MSUF_Suite/Core/NameplateText.lua PaintColor).
    local Text = {}
    function Text.Compile(config, prefix)
        world.gen = world.gen + 1
        return { id = prefix .. world.gen, enabled = config.format == true,
            customColor = config.color == true or config[prefix .. "Color"] == true,
            shared = config.shared and { id = "shared" .. world.gen } or nil }
    end
    -- A label without text formats to nil, as the host's (Portable.Format).
    function Text.Format(state, value, look)
        state.formatMemo = look.id
        if not look.enabled then return value end
        if type(value) ~= "string" then return nil end
        return "<" .. value .. ">"
    end
    function Text.PaintColor(label, state, look, unit)
        state.MSUFSpec, state.MSUFUnitKey = look.shared, unit
        if world.refuseColor then return false end
        label:SetTextColor(.1, .2, .3, 1)
        return true
    end
    local NS = {
        Suite = S, NameplateText = Text, Finite = S.Finite,
        IsSecret = function(v) return rawequal(v, SECRET) end, IsSecret = isSecret,
        Safety = { IsForbidden = IsForbidden },
        IsCombatLocked = function() world.natives = world.natives + 1 return world.combat end,
    }
    local label = { value = "Ravenous Shadowcaster", r = .9, g = .7, b = .5, a = 1, shown = true }
    function label:GetText()
        world.natives = world.natives + 1
        world.textReads = (world.textReads or 0) + 1
        return self.value
    end
    function label:SetText(v) world.writes = world.writes + 1 self.value = v end
    function label:GetTextColor() world.natives = world.natives + 1 return self.r, self.g, self.b, self.a end
    function label:SetTextColor(r, g, b, a) world.writes = world.writes + 1 self.r, self.g, self.b, self.a = r, g, b, a or 1 end
    function label:IsShown() world.natives = world.natives + 1 return self.shown end
    function label:IsForbidden() world.natives = world.natives + 1 return self.forbidden or false end
    function label:IsProtected() world.natives = world.natives + 1 return self.protected or false end
    local uf = { name = label }
    uf.IsForbidden = label.IsForbidden
    function uf:IsProtected() world.natives = world.natives + 1 return self.protected or false end
    local callback
    hooksecurefunc = function(hooked, fn)
        assert(hooked == "CompactUnitFrame_UpdateName")
        callback = fn
    end
    local private = { NS = NS, Suite = S, Mode = { LOOK_BLIZZARD = 2 } }
    local chunk = assert(loadstring(text, "@" .. name))
    chunk("MSUF_Suite_Nameplates", private)
    local Names = private.NameText
    local config = { enemy = true, friendly = true, format = true, color = true }
    local module = { active = true, config = config, pendingPlates = {}, activeUnits = { nameplate1 = uf } }
    Names.Bind(module)
    Names.Configure(config)
    world.wrappers = wrappers
    world.Names, world.config, world.module, world.label, world.uf, world.source = Names, config, module, label, uf, "@" .. name
    function world.Native() callback(uf) end
    return world
end

local function Plain(state)
    for key in pairs(state) do
        if key ~= "unit" and key ~= "prefix" and key ~= "look" and key ~= "nativeDirty" then return false, key end
    end
    return true
end

------------------------------------------------------------------ budget
local function Measure(w, budget, nativeBudget)
    local instructions, walks, frames, source = 0, 0, 0, w.source
    local natives, writes = w.natives, w.writes
    debug.sethook(function(event)
        if event == "call" then
            local info = debug.getinfo(2, "Sf")
            local fn = info.func
            if fn == pairs or fn == next then walks = walks + 1 end
            if info.source == source then frames = frames + 1 end
        else
            local info = debug.getinfo(2, "Sf")
            if info.source == source or w.wrappers[info.func] then instructions = instructions + 1 end
        end
    end, "c", 1)
    w.Native()
    debug.sethook()
    Check(walks == 0, "repeated secret updates must not walk the state table")
    Check(frames == 1, "secret update entered " .. frames .. " Lua functions of NameText.lua (the hook alone is 1)")
    Check(w.natives - natives == nativeBudget, "repeated secret update made an unexpected number of native calls")
    Check(instructions > 0 and instructions <= budget, "secret update ran " .. instructions
        .. " VM instructions (budget " .. budget .. ")")
    Check(rawequal(w.label.value, SECRET) and w.writes == writes, "a secret name was written over")
    return instructions
end

local text = ReadSource()
do
    local w = Instance(text, "NameText.lua")
    w.Names.Apply(w.uf, "enemy", "nameplate1")
    Check(w.label.value == "<Ravenous Shadowcaster>", "the public name was not formatted")
    Check(w.textReads == 1, "initial application reread a public native name")
    w.label.value = SECRET
    w.Native()
    local state = w.Names.states[w.uf]
    Check(state.raw == nil and state.unit == "nameplate1" and state.look ~= nil and Plain(state),
        "a secret name did not drop the state to its unit mapping")
    idleSpent = Measure(w, IDLE_BUDGET, 5)
    -- Neither widget is protected in this case, so both checks run.
    w.combat = true
    combatSpent = Measure(w, COMBAT_BUDGET, 7)
end

do
    local w = Instance(text, "NameText.lua")
    w.Names.Apply(w.uf, "enemy", "nameplate1")
    w.combat, w.label.protected = true, true
    -- Blizzard writes the same raw name but a new color during lockdown.
    -- The public name comparison alone cannot detect that native change.
    w.label.value, w.label.r, w.label.g, w.label.b, w.label.a = "Ravenous Shadowcaster", .5, .5, .5, .8
    local writes = w.writes
    w.Native()
    Check(w.module.pendingPlates[w.uf] and w.writes == writes, "protected native update was not deferred")
    w.combat, w.label.protected = false, false
    w.Names.Apply(w.uf, "enemy", "nameplate1")
    w.config.format, w.config.color = false, false
    w.Names.Configure(w.config)
    Check(w.label.value == "Ravenous Shadowcaster" and w.label.r == .5 and w.label.g == .5
        and w.label.b == .5 and w.label.a == .8, "protected replay lost the new native color for the same name")
end

do
    local w = Instance(text, "NameText.lua")
    w.Names.Apply(w.uf, "enemy", "nameplate1")
    w.combat, w.uf.protected, w.label.value = true, true, SECRET
    local writes, reads = w.writes, w.textReads
    w.Native()
    Check(w.module.pendingPlates[w.uf] and w.writes == writes and w.textReads == reads,
        "protected secret update was not deferred without reading or writing the label")
    w.combat, w.uf.protected = false, false
    -- The client exposes the name before a new native update is observed.
    w.label.value, w.label.r = "Ravenous Shadowcaster", .6
    w.Names.Apply(w.uf, "enemy", "nameplate1")
    Check(w.label.value == "<Ravenous Shadowcaster>", "combat replay skipped a newly readable name")
    w.config.format, w.config.color = false, false
    w.Names.Configure(w.config)
    Check(w.label.r == .6, "combat replay retained the previous native color")
end

do
    local w = Instance(text, "NameText.lua")
    w.Names.Apply(w.uf, "enemy", "nameplate1")
    local writes, reads = w.writes, w.textReads
    for _, object in ipairs({ w.uf, w.label }) do
        object.forbidden = true
        w.Native()
        object.forbidden = SECRET
        w.Native()
        w.Names.Apply(w.uf, "enemy", "nameplate1")
        object.forbidden = nil
    end
    w.label.shown = SECRET
    w.Names.Invalidate(w.uf)
    w.Native()
    w.Names.Apply(w.uf, "enemy", "nameplate1")
    w.label.shown, w.combat = true, true
    for _, object in ipairs({ w.uf, w.label }) do
        object.protected = SECRET
        w.Native()
        Check(w.module.pendingPlates[w.uf], "secret protection did not defer the update")
        w.module.pendingPlates[w.uf], object.protected = nil, nil
    end
    Check(w.writes == writes and w.textReads == reads, "an inaccessible label's text was read or written")
end

do
    local w = Instance(text, "NameText.lua")
    w.label.shown = false
    w.Names.Apply(w.uf, "friendly", "nameplate1")
    w.label.shown = true
    w.Native()
    Check(w.label.r == .1, "the first visible native refresh missed a name bound while hidden")
end

------------------------------------------------------------------ mixed sides
-- Only one side colors its names: the other side stays native and must not
-- touch the plate at all, from the skin pass or from the native hook.
do
    local w = Instance(text, "NameText.lua")
    local cfg, l, uf = w.config, w.label, w.uf
    cfg.format, cfg.color, cfg.enemyColor = false, false, true
    w.Names.Configure(cfg)
    local natives, writes = w.natives, w.writes
    for _ = 1, 100 do
        w.Names.Apply(uf, "friendly", "nameplate1")
        w.Native()
    end
    Check(w.natives == natives and w.writes == writes and w.Names.states[uf] == nil,
        "a native-only side read, wrote or mapped the plate")
    w.Names.Apply(uf, "enemy", "nameplate1")
    Check(l.r == .1 and l.value == "Ravenous Shadowcaster", "the owning side did not color the name")
    l.r, l.g, l.b = .9, .7, .5
    natives = w.natives
    w.Native()
    Check(w.natives > natives and l.r == .1, "the owning side's native update was not repainted")
    -- Ownership moves to the other side: exact restore, mapping gone.
    cfg.enemyColor, cfg.friendlyColor = false, true
    w.Names.Configure(cfg)
    local state = w.Names.states[uf]
    Check(l.r == .9 and l.g == .7 and l.b == .5 and state.unit == nil and not state.tinted,
        "a side that stopped owning was not restored and unmapped")
    natives, writes = w.natives, w.writes
    for _ = 1, 100 do
        w.Names.Apply(uf, "enemy", "nameplate1")
        w.Native()
    end
    Check(w.natives == natives and w.writes == writes, "the released side still touched the plate")
    w.Names.Apply(uf, "friendly", "nameplate1")
    Check(l.r == .1, "the newly owning side did not color the name")
    -- Protection blocks the restore: owned values wait for the replay.
    w.combat, l.protected = true, true
    cfg.enemyColor, cfg.friendlyColor = true, false
    writes = w.writes
    w.Names.Configure(cfg)
    Check(state.tinted and l.r == .1 and w.writes == writes and w.module.pendingPlates[uf],
        "a blocked release dropped its owned values or wrote a protected label")
    natives = w.natives
    w.Native()
    Check(w.natives == natives and state.tinted, "the native hook touched a side waiting for its restore")
    w.combat, l.protected = false, false
    w.Names.Apply(uf, "friendly", "nameplate1")
    Check(l.r == .9 and not state.tinted and state.unit == nil, "the replay did not restore and unmap the released side")
end

------------------------------------------------------------------ premise and equivalence
-- The reference is this file with ForgetPlain's early return taken out.
local head = "local function ForgetPlain(state)\n"
local first = text:find(head .. "    if ", 1, true)
local last = first and select(2, text:find("\n        return\n    end\n", first, true))
Check(first and last and not text:find(head, first + 1, true), "ForgetPlain's plain-state return was not found once")
local reference = text:sub(1, first + #head - 1) .. text:sub(last + 1)

local function Describe(value)
    if rawequal(value, SECRET) then return "<secret>" end
    if type(value) == "table" then return value.id and ("look:" .. value.id) or "table" end
    return tostring(value)
end
local function Snapshot(w)
    local parts, keys = {}, {}
    local state = w.Names.states[w.uf]
    if state then
        for key in pairs(state) do keys[#keys + 1] = key end
        table.sort(keys)
        for i = 1, #keys do parts[#parts + 1] = keys[i] .. "=" .. Describe(state[keys[i]]) end
    else
        parts[1] = "no state"
    end
    local l = w.label
    parts[#parts + 1] = "| text=" .. Describe(l.value) .. " rgba=" .. Describe(l.r) .. "," .. Describe(l.g) .. ","
        .. Describe(l.b) .. "," .. Describe(l.a) .. " writes=" .. w.writes .. " natives=" .. w.natives
        .. " pending=" .. tostring(w.module.pendingPlates[w.uf] == true) .. " restore=" .. tostring(w.Names.pendingRestore)
    return table.concat(parts, " ")
end

local NAMES = { "Ancient Twilight Archmage", "Old Native Name" }
local function Step(w, op, a, b)
    local l, uf, cfg = w.label, w.uf, w.config
    if op == 1 then
        if a <= 2 then l.value = SECRET elseif a == 3 then l.value = nil else l.value = NAMES[a - 3] end
        if b == 1 then l.r = SECRET elseif b == 2 then l.r, l.g, l.b, l.a = .9, .7, .5, 1 end
        w.Native()
    elseif op == 2 then
        w.combat = a == 1
    elseif op == 3 then
        uf.protected = a == 1
        l.protected = b == 1
    elseif op == 4 then
        l.shown = a ~= 1
    elseif op == 5 then
        w.Names.Apply(uf, b == 1 and "friendly" or "enemy", a == 1 and "nameplate2" or "nameplate1")
    elseif op == 6 then
        w.Names.Release(uf)
    elseif op == 7 then
        w.Names.Begin(uf)
    elseif op == 8 then
        w.Names.Invalidate(uf)
    elseif op == 9 then
        cfg.format, cfg.color, cfg.shared = a ~= 1, b ~= 1, a == 3
        w.Names.Configure(cfg)
    elseif op == 10 then
        cfg.enemy = a ~= 1
        w.module.activeUnits.nameplate1 = b == 1 and {} or uf
    elseif op == 11 then
        uf.UpdateNameOverride = a == 1 or nil
        w.refuseColor = b == 1
    elseif op == 12 then
        w.Names.FlushRestores()
        for key in pairs(w.module.pendingPlates) do w.module.pendingPlates[key] = nil end
    end
end

-- A protected update in combat marks nativeDirty; the scripted run reaches
-- a secret update of a plain state that still carries that mark (rare in
-- the random walk): map the plate, read a secret name, mark it protected,
-- then read a secret name again unprotected.
local SCRIPT = { { 10, 2, 2 }, { 11, 2, 2 }, { 4, 2, 1 }, { 5, 2, 2 }, { 2, 2, 1 }, { 3, 2, 3 }, { 1, 1, 3 },
    { 2, 1, 1 }, { 3, 1, 3 }, { 1, 1, 3 }, { 3, 2, 3 }, { 1, 1, 3 }, { 9, 2, 2 }, { 1, 3, 2 }, { 1, 1, 3 } }
do
    local new, old = Instance(text, "NameText.lua"), Instance(reference, "NameText-reference.lua")
    math.randomseed(20261111)
    -- Secret updates of a state without a captured name, and of those the
    -- ones that also drop a protected update's nativeDirty mark.
    -- Secret updates after a name-less capture must clear in full (nilSecret,
    -- tintedSecret with a colour painted on it).
    local plainSecret, dirtySecret, nilSecret, tintedSecret, steps = 0, 0, 0, 0, 0
    local function Run(op, a, b)
        steps = steps + 1
        local state = new.Names.states[new.uf]
        if op == 1 and a <= 2 and state and state.captured and state.raw == nil then
            nilSecret = nilSecret + 1
            if state.tinted then tintedSecret = tintedSecret + 1 end
        end
        if op == 1 and a <= 2 and state and not state.captured and state.unit then
            plainSecret = plainSecret + 1
            local blocked = new.combat and (new.uf.protected or new.label.protected)
            if state.nativeDirty and not blocked then dirtySecret = dirtySecret + 1 end
        end
        Step(new, op, a, b)
        Step(old, op, a, b)
        state = new.Names.states[new.uf]
        if state and not state.captured then
            local plain, key = Plain(state)
            Check(plain, "step " .. steps .. ": a state without a captured name holds " .. tostring(key))
        end
        local got, want = Snapshot(new), Snapshot(old)
        Check(got == want, "step " .. steps .. " (op " .. op .. "," .. a .. "," .. b .. ") differs from the full clear:\n  new "
            .. got .. "\n  old " .. want)
    end
    for step = 1, 40000 do
        local op, a, b = math.random(1, 12), math.random(1, 5), math.random(1, 3)
        if op ~= 1 and math.random() < .6 then op = 1 end
        Run(op, a, b)
        if step % 250 == 0 then
            for i = 1, #SCRIPT do Run(SCRIPT[i][1], SCRIPT[i][2], SCRIPT[i][3]) end
        end
    end
    Check(plainSecret > 1000 and dirtySecret > 50 and nilSecret > 100 and tintedSecret > 50,
        "the walk reached the secret plain-state path only " .. plainSecret .. " times (" .. dirtySecret
        .. " with a nativeDirty mark), a name-less capture " .. nilSecret .. " (" .. tintedSecret .. " tinted)")
end
print("Nameplates secret names: " .. checks .. " checks passed (secret update " .. idleSpent .. "/" .. IDLE_BUDGET
    .. " VM instructions idle, " .. combatSpent .. "/" .. COMBAT_BUDGET .. " in combat)")
