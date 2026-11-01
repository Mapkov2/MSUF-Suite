local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
-- Both shipped meter bootstraps, with the native recap panel still unloaded.
-- Mapping: Blizzard_DeathRecap on live d07eb002 and forever ca8368f2.
-- Forever's native renderer is mainline-only in its TOC; the Suite consumes
-- C_DeathRecap directly and must not need that renderer or its globals.
ACTION_ENVIRONMENTAL_DAMAGE_DROWNING = "Native drowning"
ACTION_ENVIRONMENTAL_DAMAGE_FALLING = "Native falling"
ACTION_ENVIRONMENTAL_DAMAGE_FIRE = "Native fire"
ACTION_ENVIRONMENTAL_DAMAGE_LAVA = "Native lava"
ACTION_ENVIRONMENTAL_DAMAGE_SLIME = "Native slime"
ACTION_ENVIRONMENTAL_DAMAGE_FATIGUE = "Native fatigue"
local secrets = setmetatable({}, { __mode = "k" })
local secretMeta = {}
for _, key in ipairs({ "__add", "__sub", "__mul", "__div", "__concat", "__lt", "__le", "__eq",
    "__index", "__newindex", "__tostring" }) do
    secretMeta[key] = function() error("secret reached a Lua operation") end
end
local function Secret()
    local value = setmetatable({}, secretMeta)
    secrets[value] = true
    return value
end
local originalLoad, private = loadfile
loadfile = function(path)
    local source = path
    if arg[3] and path:find("MSUF_Suite_DamageMeter/Recap.lua", 1, true) then source = arg[3] end
    local chunk = assert(originalLoad(source))
    return function(addon, namespace)
        if path:find("MSUF_Suite/Core/Platform.lua", 1, true) then
            local previous = issecretvalue
            issecretvalue = function(value) return secrets[value] == true or previous(value) end
        end
        if path:find("MSUF_Suite_DamageMeter/Data.lua", 1, true) then private = namespace end
        return chunk(addon, namespace)
    end
end
MSUF_DM_FEATURE_TESTS = true
dofile(root .. "/tools/tests/" .. (flavor == "Forever" and "suite_damage_meter_threat_contract.lua"
    or "suite_damage_meter_contract.lua"))
loadfile = originalLoad
assert(private and (MSUF_NS.Client.IsForever == true) == (flavor == "Forever"), "wrong client bootstrap")
assert(DeathRecapFrame == nil and DeathRecapFrameMixin == nil, "native recap renderer was loaded")
local D, M = private.DamageMeter, private.DamageMeter.M
local IsSecret = private.NS.IsSecret
local win = D.windows[1]
D.EnsurePanel(win)
local row = D.CreateRow(win.panel, win, "spell")
row.icon.SetTexture = function(self, texture) self.texture = texture end
row.nameText.SetText = function(self, text) self.text = text end
row.nameText.SetFormattedText = function(self, format, seconds, text)
    self.text = IsSecret(text) and text or string.format(format, seconds, text)
end
local lookups = {}
C_Spell.GetSpellTexture = function(id)
    assert(not IsSecret(id), "secret ID reached C_Spell.GetSpellTexture")
    lookups[#lookups + 1] = id
    return id ~= 999 and "spell:" .. id or nil
end
local event = { amount = 200, currentHP = 0, timestamp = 100 }
local events = { event }
C_DeathRecap = { HasRecapEvents = function() return true end, GetRecapEvents = function() return events end,
    GetRecapMaxHealth = function() return 1000 end }
local function Paint(kind, subtype, id, name)
    event.event, event.environmentalType, event.spellId, event.spellName = kind, subtype, id, name
    local recap = assert(D.ReadRecap(77))
    D.PaintRecap(row, event, recap)
    return recap
end
Paint("SWING_DAMAGE")
assert(row.icon:IsShown() and row.icon.texture == "spell:88163" and row.spellID == 88163,
    "melee recap without spellId lost its native icon/tooltip ID")
Paint("SWING_DAMAGE", nil, 0, "")
assert(row.icon.texture == "spell:88163" and row.nameText.text == "-0.0s Melee", "zero melee ID lost its fallback")
local cases = {
    { "DROWNING", "Native drowning", "spell_shadow_demonbreath" },
    { "FALLING", "Native falling", "ability_rogue_quickrecovery" },
    { "FIRE", "Native fire", "spell_fire_fire" },
    { "LAVA", "Native lava", "spell_fire_fire" },
    { "SLIME", "Native slime", "inv_misc_slime_01" },
    { "FATIGUE", "Native fatigue", "ability_creature_cursed_05" },
}
for _, case in ipairs(cases) do
    for _, subtype in ipairs({ case[1], case[1]:lower() }) do
        local before = #lookups
        Paint("ENVIRONMENTAL_DAMAGE", subtype)
        assert(row.icon:IsShown() and row.icon.texture == "Interface\\Icons\\" .. case[3], subtype .. " lost native icon")
        assert(row.nameText.text == "-0.0s " .. case[2], subtype .. " lost native localized label")
        assert(row.spellID == nil and #lookups == before, "environmental row kept a stale spell tooltip/lookup")
    end
end
Paint("ENVIRONMENTAL_DAMAGE", "falling", 133)
assert(row.spellID == nil and row.icon.texture == "Interface\\Icons\\ability_rogue_quickrecovery",
    "environmental event used a spell tooltip ID instead of its native icon")
Paint("ENVIRONMENTAL_DAMAGE", "UNRECOGNIZED")
assert(row.icon:IsShown() and row.icon.texture == "Interface\\Icons\\ability_creature_cursed_05"
    and row.nameText.text == "-0.0s Unknown", "unknown environmental type lost native default icon")
Paint("SPELL_DAMAGE", nil, 133, "Fireball")
assert(row.spellID == 133 and row.icon.texture == "spell:133" and row.nameText.text == "-0.0s Fireball",
    "ordinary spell rendering changed")
Paint("SPELL_DAMAGE", nil, 999, "Missing texture")
assert(not row.icon:IsShown(), "a failed texture lookup left the previous icon visible")
Paint("OTHER")
assert(row.spellID == nil and not row.icon:IsShown(), "a reused row kept an old spell/icon")
-- Native type(secret) can still be string; type checking alone is insufficient.
local rawType = type
type = function(value) return secrets[value] and "string" or rawType(value) end
local secret = Secret()
local recap = Paint("ENVIRONMENTAL_DAMAGE", secret)
assert(recap.restricted and row.spellID == nil and not row.icon:IsShown(),
    "secret environmentalType was cached as readable or sent through the icon lookup")
Paint(secret, nil, secret)
assert(not row.icon:IsShown() and row.spellID == nil, "secret event/ID retained a visible icon")
Paint("SPELL_DAMAGE", nil, secret, secret)
assert(row.nameText.text == secret and not row.icon:IsShown(), "secret name failed to reach its sink unchanged")
recap = Paint("ENVIRONMENTAL_DAMAGE", secret, nil, "")
win.bd.recap, win.bd.offset, win.bdRows[1] = recap, 0, row
D.RefreshRecap(win)
assert(win.bd.recap.restricted and win.bd.paintedRecap == nil, "restricted environment snapshot was memoized")
event.environmentalType = "falling"
D.RefreshRecap(win)
assert(not win.bd.recap.restricted and win.bd.paintedRecap == win.bd.recap
    and row.icon.texture == "Interface\\Icons\\ability_rogue_quickrecovery",
    "declassified environment failed to refresh and settle")
type = rawType
print("Death recap visuals (" .. flavor .. "): native melee/environment icons, localized names, row reuse and secret declassification passed")
