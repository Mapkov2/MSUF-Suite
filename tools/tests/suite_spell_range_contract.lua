local root = assert(arg[1])
local calls, nativeState, secrets = {}, {}, {}
local hookCount, scans = 0, 0
local function Public(value) return not secrets[value] end
C_Spell = { EnableSpellRangeCheck = function(id, enabled)
    calls[#calls + 1] = { id, enabled }
    if Public(id) and Public(enabled) then nativeState[id] = enabled end
    assert(#calls < 200, "range posthook never recursively loops")
end }
hooksecurefunc = function(object, key, callback)
    hookCount = hookCount + 1
    local original = object[key]
    object[key] = function(...) original(...); callback(...) end
end
local NS = { Suite = {}, Public = Public, Finite = function(value)
    return Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end }
assert(loadfile(root .. "/MSUF_Suite/Core/SpellRange.lua"))("MSUF_Suite", NS)
local S = NS.Suite
assert(hookCount == 0, "disabled Suite range consumers install no global hook")
S.SetNativeSpellRange("cooldownManager", 10, true)
S.SetNativeSpellRange("cooldownManager", 10, true)
S.SetNativeSpellRange("targetDistance", 10, true)
assert(#calls == 1 and calls[1][2], "one native enable for shared/idempotent requests")
S.ClearNativeSpellRanges("cooldownManager")
assert(#calls == 1, "releasing CDM never disables the distance owner's same spell")
S.SetNativeSpellRange("targetDistance", 20, true)
S.ClearNativeSpellRanges("targetDistance")
assert(#calls == 4, "last owner releases each native spell exactly once")
S.ClearNativeSpellRanges("targetDistance")
S.SetNativeSpellRange("targetDistance", 10, false)
S.SetNativeSpellRange("bad", "secret", true)
S.SetNativeSpellRange("bad", -2, true)
assert(#calls == 4, "redundant release and invalid input do no native work")
S.SetNativeSpellRange("targetDistance", 10, true)
assert(#calls == 5, "owner can re-enable after teardown")
assert(hookCount == 1, "one lazy hook survives consumer disable/re-enable")

-- Another addon's subscription survives the Suite letting go of the spell.
C_Spell.EnableSpellRangeCheck(90, true)
S.SetNativeSpellRange("targetDistance", 90, true)
local beforeForeign = #calls
S.SetNativeSpellRange("targetDistance", 90, false)
assert(#calls == beforeForeign and nativeState[90] == true,
    "releasing Suite interest switched off another addon's range check")
C_Spell.EnableSpellRangeCheck(90, false)
S.SetNativeSpellRange("targetDistance", 90, true)
S.SetNativeSpellRange("targetDistance", 90, false)
assert(nativeState[90] == false, "a spell the other owner released stayed enabled after the Suite let go")

-- Native false is issued before ResetCooldownData clears the item's fields.
local function Item(id)
    return { needsRangeCheck = true, rangeCheckSpellID = id, IsForbidden = function() return false end }
end
local function Viewer(items)
    return { IsForbidden = function() return false end,
        itemFramePool = { EnumerateActive = function()
            scans = scans + 1
            local i = 0
            return function() i = i + 1; return items[i] end
        end } }
end
local nativeItem = Item(10)
EssentialCooldownViewer = Viewer({nativeItem})
local before = #calls
C_Spell.EnableSpellRangeCheck(10, false)
assert(#calls == before + 2 and nativeState[10], "native reset cannot disable active Suite interest")
assert(scans == 0, "posthook never scans native frames, including their stale reset state")
nativeItem.needsRangeCheck, nativeItem.rangeCheckSpellID = nil, nil
S.ClearNativeSpellRanges("targetDistance")
assert(nativeState[10] == false, "final Suite release disables after the native item reset")

-- Pools created after Suite acquisition are discovered on the final release.
EssentialCooldownViewer = nil
S.SetNativeSpellRange("cooldownManager", 30, true)
local utilItem = Item(30)
UtilityCooldownViewer = Viewer({Item(31), utilItem, Item(30)})
UtilityCooldownViewer.IsShown = function() error("hidden native viewer still owns registration") end
before = #calls
S.ClearNativeSpellRanges("cooldownManager")
assert(#calls == before and nativeState[30], "late Utility pool and duplicate native owners survive Suite teardown")
C_Spell.EnableSpellRangeCheck(30, false)
assert(#calls == before + 1 and nativeState[30] == false, "idle Suite hook leaves native teardown alone")
UtilityCooldownViewer = nil

EssentialCooldownViewer = Viewer({Item(40)})
S.SetNativeSpellRange("enemyCastStack", 40, true)
S.SetNativeSpellRange("targetDistance", 40, true)
before, scans = #calls, 0
S.ClearNativeSpellRanges("enemyCastStack")
assert(#calls == before and scans == 0, "intermediate Suite releases do not scan native pools")
S.ClearNativeSpellRanges("targetDistance")
assert(#calls == before and nativeState[40], "Essential ownership survives final Suite release")

-- Ignore private hook arguments before comparisons/keying; never inspect
-- forbidden frames or secret ownership fields while releasing Suite interest.
local secret = setmetatable({}, { __index = function() error("secret object inspected") end })
secrets[secret] = true
S.SetNativeSpellRange("targetDistance", 50, true)
before = #calls
C_Spell.EnableSpellRangeCheck(secret, false)
C_Spell.EnableSpellRangeCheck(50, secret)
C_Spell.EnableSpellRangeCheck("50", false)
C_Spell.EnableSpellRangeCheck(51, false)
assert(#calls == before + 4, "secret, nonnumeric and unowned identifiers cause no reassertion")
before = #calls
S.SetNativeSpellRange(secret, 50, true)
S.SetNativeSpellRange("targetDistance", secret, true)
S.SetNativeSpellRange("targetDistance", 50, secret)
assert(#calls == before, "Suite also rejects secret request arguments")
EssentialCooldownViewer = Viewer({setmetatable({IsForbidden = function() return true end}, {
    __index = function() error("forbidden native item inspected") end })})
S.ClearNativeSpellRanges("targetDistance")
assert(#calls == before, "unknown forbidden native ownership is preserved")
EssentialCooldownViewer = Viewer({Item(61)})
S.SetNativeSpellRange("targetDistance", 60, true)
S.ClearNativeSpellRanges("targetDistance")
assert(nativeState[60] == false, "different native spell does not retain released registration")
for _, viewer in ipairs({secret, Viewer({secret}), Viewer({{IsForbidden = function() return false end,
    needsRangeCheck = secret}}), Viewer({{IsForbidden = function() return false end,
    needsRangeCheck = true, rangeCheckSpellID = secret}})}) do
    EssentialCooldownViewer = viewer
    S.SetNativeSpellRange("targetDistance", 70, true)
    before = #calls
    S.ClearNativeSpellRanges("targetDistance")
    assert(#calls == before, "unreadable native ownership never authorizes a destructive disable")
end
EssentialCooldownViewer = nil
S.SetNativeSpellRange("targetDistance", 80, true)
S.ClearNativeSpellRanges("targetDistance")
before, scans = #calls, 0
C_Spell.EnableSpellRangeCheck(80, false)
assert(#calls == before + 1 and scans == 0 and hookCount == 1, "final teardown leaves an inert, scan-free posthook")
print("native spell range Suite/Blizzard/addon coexistence, secret guards, lazy hooks and teardown passed")
