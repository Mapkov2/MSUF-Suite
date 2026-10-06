-- The skin's shared helpers that replaced copies in several adapters:
-- Safety.Isolated (hook bodies as their own error boundary) and
-- AdapterKit.FontPath (the client's normal text font). The owner registry
-- that replaced AdapterKit.DeferForOwner has its own contract
-- (suite_skin_owner_registry_contract.lua). Real Safety.lua and AdapterKit.lua.
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

local NS = {
    IsCombatLocked = function() return false end,
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

print("Suite skin kit helpers: " .. checks .. " checks passed")
