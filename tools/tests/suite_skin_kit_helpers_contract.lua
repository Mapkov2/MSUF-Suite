-- The skin's shared helpers that replaced copies in several adapters:
-- Safety.Isolated (hook bodies as their own error boundary),
-- AdapterKit.FontPath (the client's normal text font) and
-- AdapterKit.DeferForOwner (a combat-deferred pass for the owner's current
-- state). Real Safety.lua and AdapterKit.lua.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2, table.maxn(results))
end

local locked = false
local deferred, cancelled = {}, {}
local NS = {
    IsCombatLocked = function() return locked end,
    CombatGate = {
        RunOrDefer = function(key, callback)
            if locked then
                deferred[key] = callback
                return false, "combat"
            end
            callback()
            return true
        end,
        Cancel = function(key)
            cancelled[key] = true
            deferred[key] = nil
        end,
    },
    Registry = { AddListener = function() end },
}
for _, file in ipairs({ "Core/Safety.lua", "Adapters/AdapterKit.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
local Safety, Kit = NS.Safety, NS.AdapterKit

-- Isolated: one wrapper per callback; an error is reported and the caller goes on.
local calls = 0
local function Body(value)
    calls = calls + 1
    if value == "raise" then error("contract: hook raised") end
end
local hook = Safety.Isolated(Body)
Check(Safety.Isolated(Body) == hook, "hooking the same callback twice made two wrappers")
hook("fine")
local ok = pcall(hook, "raise")
Check(ok and calls == 2 and #reported == 1, "a raising hook body escaped into Blizzard's caller or was not reported")

-- FontPath: GameFontNormal's face, else the standard text font, else Friz.
GameFontNormal = { GetFont = function() return "Fonts\\Normal.ttf", 12, "" end }
Check(Kit.FontPath() == "Fonts\\Normal.ttf", "FontPath did not read GameFontNormal")
GameFontNormal = { GetFont = function() return nil end }
STANDARD_TEXT_FONT = "Fonts\\Standard.ttf"
Check(Kit.FontPath() == "Fonts\\Standard.ttf", "FontPath did not fall back to the standard text font")
STANDARD_TEXT_FONT = nil
Check(Kit.FontPath() == Kit.DEFAULT_FONT and Kit.DEFAULT_FONT == "Fonts\\FRIZQT__.TTF",
    "FontPath did not fall back to Friz Quadrata")

-- DeferForOwner: runs now out of combat, else once after combat for the
-- owner's state then, and not for a state that went inactive.
local owners = { main = { active = true, deferred = {} } }
local runs = {}
local function Run(state, arg) runs[#runs + 1] = { state = state, arg = arg } end
local ran = Kit.DeferForOwner(owners, "main", "contract:pass", Run, "now")
Check(ran == true and #runs == 1 and runs[1].arg == "now" and next(owners.main.deferred) == nil,
    "an out-of-combat pass did not run at once or stayed marked")
locked = true
ran = Kit.DeferForOwner(owners, "main", "contract:pass", Run, "later")
Check(ran == false and #runs == 1 and owners.main.deferred["contract:pass"], "a combat pass ran or was not marked")
locked = false
local applied = { active = true, deferred = {} }
owners.main = applied
deferred["contract:pass"]()
Check(#runs == 2 and runs[2].state == applied and runs[2].arg == "later",
    "the deferred pass did not run for the owner's current state")
locked = true
Kit.DeferForOwner(owners, "main", "contract:pass", Run)
locked = false
applied.active = false
deferred["contract:pass"]()
Check(#runs == 2 and applied.deferred["contract:pass"] == nil, "a deferred pass ran for an inactive owner")
locked = true
applied.active = true
Kit.DeferForOwner(owners, "main", "contract:pass", Run)
Kit.CancelDeferred(applied)
Check(cancelled["contract:pass"] and deferred["contract:pass"] == nil, "CancelDeferred kept the pending pass")
locked = false

print("Suite skin kit helpers: " .. checks .. " checks passed")
