local _, NS = ...

-- Blizzard surfaces a running Suite module replaces or hides: Blizzard's
-- damage meter (the Suite meter turns it off), the native bag shells
-- the Bags module paints, the cooldown viewers
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
    staticPopups = "blizzardWindows",
    -- The Battle.net toast with a Suite look (Adapters/SharedChrome.lua).
    battleNetToast = "blizzardWindows",
}

-- Catalog entries whose frames are exactly one owned surface.
local ENTRIES = {
    ["hud-cooldown-viewers"] = "cooldownViewers",
    ["hud-bag-bar"] = "bagBar",
    ["static-popups"] = "staticPopups",
}

local function LoadedSuite()
    local suite = _G.MSUFSuite
    return type(suite) == "table" and suite or nil
end

local function Ask(surface)
    local suite = LoadedSuite()
    local controller = suite and suite.Suite
    local owns = type(controller) == "table" and controller.OwnsBlizzardSurface
    return type(owns) == "function" and owns(surface) == true
end

-- The host bridge alone knows the menu hierarchy and its combat-open policy.
-- Older Suite cores keep eager skinning when that capability is absent.
function SuiteOwnership.IsOptionsSurface(frame)
    local suite = LoadedSuite()
    local bridge = suite and suite.HostBridge
    return type(bridge) == "table" and bridge.IsOptionsSurface and bridge.IsOptionsSurface(frame) == true
end

-- Asks the Suite and remembers the answer, so Refresh rebuilds only what
-- changed hands. Apply paths use this.
function SuiteOwnership.Owns(surface)
    -- The character mode can be edited while its controller apply is queued.
    -- Keep the applied presentation until the ownership handoff runs.
    if surface == "characterDossier" and NS.IsCombatLocked() then
        local applied = SuiteOwnership.answers[surface]
        if applied ~= nil then return applied end
    end
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
    local safety = NS.Safety
    if not safety.Public(frame) or not frame then return false end
    if frame == ContainerFrameCombinedBags or frame == ContainerFrame6 then return true end
    if not NS.Client.isForever or frame == ContainerFrame1 then return false end
    -- Reserve the same Forever native pool that Bags uses for the keyring.
    -- A frame's current bag ID may change when Blizzard reuses the window.
    local frames = safety.Field(ContainerFrameContainer, "ContainerFrames")
    if type(frames) ~= "table" then return false end
    for index = 1, #frames do
        if frame == frames[index] then return true end
    end
    return false
end

-- Bags owns its window chrome and is the only mover for the combined and
-- reagent bag positions. Standalone Forever bags keep Blizzard placement.
function SuiteOwnership.OwnsWindowGeometry(frame)
    if SuiteOwnership.IsBagShell(frame) or (frame ~= nil and frame == BankFrame and not NS.Client.isForever) then
        return SuiteOwnership.Owns("bagWindows")
    end
    return false
end

local function RefreshCharacterDossier(claiming)
    local panel = NS.CharacterPanel
    local state = panel.owners.blizzardWindows
    if not state or not state.active then return end
    if claiming then
        -- The normal panel apply waits for a visible window. Release the
        -- dossier now so its native geometry cannot survive a hidden handoff.
        NS.Safety.Dispatch(NS.CharacterDetails.Apply, CharacterFrame, "character", state.owner)
    else
        NS.Safety.Dispatch(panel.Apply, state.owner)
    end
end

-- "before" a module starts or stops, the skin lets go of surfaces that became
-- owned; "after", it takes back surfaces that were freed. A surface the skin
-- never asked about has nothing to undo.
local function Collect(surface, claiming, rebuild)
    local owned = SuiteOwnership.answers[surface]
    if owned == nil then return rebuild end
    local now = Ask(surface)
    if now == owned or now ~= claiming then return rebuild end
    SuiteOwnership.answers[surface] = now
    rebuild = rebuild or {}
    rebuild[surface == "characterDossier" and surface or ADAPTERS[surface]] = true
    return rebuild
end

function SuiteOwnership.Refresh(phase, surface, dependent)
    local claiming = phase == "before"
    local rebuild
    if surface then
        rebuild = Collect(surface, claiming)
        if dependent then rebuild = Collect(dependent, claiming, rebuild) end
    else
        for observed in pairs(SuiteOwnership.answers) do rebuild = Collect(observed, claiming, rebuild) end
    end
    if not rebuild then return end
    if rebuild.characterDossier then
        rebuild.characterDossier = nil
        RefreshCharacterDossier(claiming)
    end
    for id in pairs(rebuild) do NS.Adapters.Refresh(id) end
end

return SuiteOwnership
