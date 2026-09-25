local _, NS = ...

-- Blizzard surfaces a running Suite module replaces or hides: Blizzard's
-- damage meter (the Suite meter turns it off), the shell of the combined and
-- reagent bag windows (the Bags module paints its own), the cooldown viewers
-- (the Suite cooldown manager turns them off or runs them invisibly) and the
-- bag bar (DataTexts hides it on request). While such a module runs the skin
-- leaves the surface to it; with the module off the skin styles Blizzard's
-- original again. The Suite controller answers (MSUFSuite.Suite.
-- OwnsBlizzardSurface) and reports starts and stops through Refresh.
local SuiteOwnership = { answers = {} }
NS.SuiteOwnership = SuiteOwnership

-- The adapter that rebuilds a surface when it changes hands.
local ADAPTERS = {
    damageMeter = "damageMeter",
    bagWindows = "blizzardWindows",
    cooldownViewers = "blizzardWindows",
    bagBar = "blizzardWindows",
}

-- Catalog entries whose frames are exactly one owned surface.
local ENTRIES = {
    ["hud-cooldown-viewers"] = "cooldownViewers",
    ["hud-bag-bar"] = "bagBar",
}

local function Ask(surface)
    local suite = _G.MSUFSuite
    local controller = type(suite) == "table" and suite.Suite
    local owns = type(controller) == "table" and controller.OwnsBlizzardSurface
    return type(owns) == "function" and owns(surface) == true
end

-- Asks the Suite and remembers the answer, so Refresh rebuilds only what
-- changed hands. Apply paths use this.
function SuiteOwnership.Owns(surface)
    local owned = Ask(surface)
    SuiteOwnership.answers[surface] = owned
    return owned
end

-- The answer of the last apply, without asking again. Hooks that fire often
-- (also in combat) use this.
function SuiteOwnership.Owned(surface)
    return SuiteOwnership.answers[surface] == true
end

function SuiteOwnership.EntrySurface(entryID)
    return ENTRIES[entryID]
end

-- The bag windows whose shell the Bags module paints.
function SuiteOwnership.IsBagShell(frame)
    return frame ~= nil and (frame == _G.ContainerFrameCombinedBags or frame == _G.ContainerFrame6)
end

-- "before" a module starts or stops, the skin lets go of surfaces that became
-- owned; "after", it takes back surfaces that were freed. A surface the skin
-- never asked about has nothing to undo.
function SuiteOwnership.Refresh(phase)
    local claiming = phase == "before"
    local rebuild
    for surface, owned in pairs(SuiteOwnership.answers) do
        local now = Ask(surface)
        if now ~= owned and now == claiming then
            SuiteOwnership.answers[surface] = now
            rebuild = rebuild or {}
            rebuild[ADAPTERS[surface]] = true
        end
    end
    if not rebuild then return end
    for id in pairs(rebuild) do NS.Adapters.Refresh(id) end
end

return SuiteOwnership
