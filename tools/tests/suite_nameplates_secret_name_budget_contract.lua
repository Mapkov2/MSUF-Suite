local root = assert(arg[1], "repository root required"):gsub("\\", "/")
-- Nameplate names in restricted combat (MSUF_Suite_Nameplates/NameText.lua).
-- 2026-11-11 raid trace (300 s, 24 players): the CompactUnitFrame_UpdateName
-- post-hook ran 54,237 times; 24,911 of them reached a mapped plate whose
-- name was secret, so nothing could be painted and the state was dropped to
-- its unit mapping (ForgetPlain) every time, a pairs() walk that removes
-- nothing new after the first one. This contract holds:
--   * budget: a secret native update of a plate that holds no captured name
--     runs at most SECRET_BUDGET VM instructions in NameText.lua (101 before,
--     86 after; +2 %), walks no table (no pairs() and its next() C calls) and asks
--     the client exactly the seven questions it asked before (forbidden x2,
--     protected x2, combat, shown, text);
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
local SECRET_BUDGET = 88
local spent
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
    local S = {
        Public = function(v) return not rawequal(v, SECRET) end,
        Finite = function(v) return not rawequal(v, SECRET) and type(v) == "number" and v == v end,
    }
    -- Compiled looks carry an id so two instances compare by meaning; the
    -- formatter and the color painter write their own fields into the state,
    -- as the host's do (MSUF_Suite/Core/NameplateText.lua PaintColor).
    local Text = {}
    function Text.Compile(config, prefix)
        world.gen = world.gen + 1
        return { id = prefix .. world.gen, enabled = config.format == true, customColor = config.color == true,
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
        label:SetVertexColor(.1, .2, .3, 1)
        return true
    end
    local NS = {
        Suite = S, NameplateText = Text,
        Safety = { IsForbidden = function(frame) world.natives = world.natives + 1 return frame.forbidden == true end },
        IsCombatLocked = function() world.natives = world.natives + 1 return world.combat end,
    }
    local label = { value = "Ravenous Shadowcaster", r = .9, g = .7, b = .5, a = 1, shown = true }
    function label:GetText() world.natives = world.natives + 1 return self.value end
    function label:SetText(v) world.writes = world.writes + 1 self.value = v end
    function label:GetTextColor() world.natives = world.natives + 1 return self.r, self.g, self.b, self.a end
    function label:SetVertexColor(r, g, b, a) world.writes = world.writes + 1 self.r, self.g, self.b, self.a = r, g, b, a or 1 end
    function label:IsShown() world.natives = world.natives + 1 return self.shown end
    function label:IsProtected() world.natives = world.natives + 1 return self.protected == true end
    local uf = { name = label }
    function uf:IsProtected() world.natives = world.natives + 1 return self.protected == true end
    local callback
    hooksecurefunc = function(hooked, fn)
        assert(hooked == "CompactUnitFrame_UpdateName")
        callback = fn
    end
    local private = { NS = NS, Suite = S }
    local chunk = assert(loadstring(text, "@" .. name))
    chunk("MSUF_Suite_Nameplates", private)
    local Names = private.NameText
    local config = { enemy = true, friendly = true, format = true, color = true }
    local module = { active = true, config = config, pendingPlates = {}, activeUnits = { nameplate1 = uf } }
    Names.Bind(module)
    Names.Configure(config)
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
local text = ReadSource()
do
    local w = Instance(text, "NameText.lua")
    w.Names.Apply(w.uf, "enemy", "nameplate1")
    Check(w.label.value == "<Ravenous Shadowcaster>", "the public name was not formatted")
    -- In combat, as in the trace: neither frame is protected, so both are asked.
    w.combat, w.label.value = true, SECRET
    local writes = w.writes
    w.Native()
    local state = w.Names.states[w.uf]
    Check(state.raw == nil and state.unit == "nameplate1" and state.look ~= nil and Plain(state),
        "a secret name did not drop the state to its unit mapping")
    w.Native()
    local instructions, walks, source = 0, 0, w.source
    local natives = w.natives
    debug.sethook(function(event)
        if event == "call" then
            local fn = debug.getinfo(2, "f").func
            if fn == pairs or fn == next then walks = walks + 1 end
        elseif debug.getinfo(2, "S").source == source then
            instructions = instructions + 1
        end
    end, "c", 1)
    w.Native()
    debug.sethook()
    Check(walks == 0, "a secret native update of a plain plate walked its state (" .. walks .. " pairs/next calls)")
    Check(w.natives - natives == 7, "a secret native update asked the client " .. (w.natives - natives) .. " times, not 7")
    Check(instructions > 0, "the instruction filter counted nothing")
    Check(instructions <= SECRET_BUDGET, "a secret native update of a plain plate ran " .. instructions
        .. " VM instructions (budget " .. SECRET_BUDGET .. ")")
    Check(rawequal(w.label.value, SECRET) and w.writes == writes, "a secret name was written over")
    spent = instructions
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
print("Nameplates secret names: " .. checks .. " checks passed (secret update " .. spent .. "/" .. SECRET_BUDGET
    .. " VM instructions, premise, equivalence with the full clear)")
