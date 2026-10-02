local _, NS = ...

local Adapters = {
    definitions = {},
    order = {},
    status = {},
    waiting = {},
}
NS.Adapters = Adapters

local function IsValidDefinition(definition)
    return type(definition) == "table" and type(definition.id) == "string"
        and type(definition.resolve) == "function"
end

function Adapters.Register(definition)
    if not IsValidDefinition(definition) or Adapters.definitions[definition.id] then
        return false
    end
    Adapters.definitions[definition.id] = definition
    Adapters.order[#Adapters.order + 1] = definition.id
    return true
end

function Adapters.Replace(definition)
    if not IsValidDefinition(definition) then
        return false
    end
    if not Adapters.definitions[definition.id] then
        return Adapters.Register(definition)
    end
    Adapters.definitions[definition.id] = definition
    return true
end

local function ScheduleLoadOnDemand(definition)
    local id = definition.id
    local addon = definition.loadAddon
    if not addon or NS.Client.HasAddOn(addon) == false then
        return false
    end
    if Adapters.waiting[id] then
        return true
    end
    -- EventUtil invokes its callback synchronously when the addon is already
    -- loaded. If a Blizzard build has loaded the addon but omitted/renamed the
    -- expected root, rescheduling from that callback would recurse forever.
    if NS.Client.IsAddOnLoaded(addon) then
        return false
    end

    Adapters.waiting[id] = true
    EventUtil.ContinueOnAddOnLoaded(addon, function()
        Adapters.waiting[id] = nil
        Adapters.Apply(id)
    end)
    return true
end

-- Definitions can come from other addons (API v1 RegisterAdapter), so their
-- callbacks run through Safety.Dispatch: a failing adapter is reported and the
-- other adapters still apply. The leading true tells a finished call from an
-- error, which returns nothing.
local function Finish(callback, ...)
    return true, callback(...)
end

local function RunCallback(callback, frame, id)
    local finished, first, second = NS.Safety.Dispatch(Finish, callback, frame, id)
    if not finished then return false, "error" end
    return first, second
end

local function DisableDefinition(definition, frame)
    local id = definition.id
    NS.WindowControls.DisableOwner(id)
    if type(definition.disable) == "function" then
        local disabled, reason = RunCallback(definition.disable, frame, id)
        if disabled == false then
            return false, reason or "disable-failed"
        end
        return true
    end
    NS.Cosmetics.RestoreOwner(id)
    if frame then
        NS.Surface.SetVisible(frame, false)
    end
    return true
end

local function DefinitionEnabled(definition)
    local configured = NS.DB.skins[definition.id]
    if configured == nil then
        return definition.defaultEnabled ~= false
    end
    return configured == true
end

-- A Suite module that replaces this adapter's surface keeps it while it runs
-- (Core/SuiteOwnership.lua).
local function SuiteOwned(definition)
    return definition.suiteSurface ~= nil and NS.SuiteOwnership.Owns(definition.suiteSurface)
end

-- Returns false with a status when the definition could not be applied.
local function RunDefinition(definition, frame)
    local id = definition.id
    if type(definition.apply) == "function" then
        local applied, reason = RunCallback(definition.apply, frame, id)
        if applied == false then
            return false, reason or "failed"
        end
        return true, reason == "partial" and "partial" or "applied"
    end

    local surface, reason = NS.Surface.Attach(frame, { role = "shell", inset = definition.inset or 0 })
    if not surface then
        return false, reason or "failed"
    end
    if type(definition.fade) == "function" then
        RunCallback(definition.fade, frame, id)
    end
    NS.Surface.SetVisible(frame, true)
    return true, "applied"
end

local function ApplyDefinition(definition)
    local id = definition.id
    if not NS.DB.enabled or not DefinitionEnabled(definition) or SuiteOwned(definition) then
        local previous = Adapters.status[id]
        local frame = previous and previous.frame
        local disabled, reason = DisableDefinition(definition, frame)
        Adapters.status[id] = {
            state = disabled and "disabled" or (reason or "disable-failed"),
            frame = frame,
        }
        return false
    end

    local frame = RunCallback(definition.resolve)
    if not frame then
        local waiting = ScheduleLoadOnDemand(definition)
        Adapters.status[id] = { state = waiting and "waiting" or "missing" }
        return false
    end
    if not NS.Safety.CanDecorate(frame, definition.allowImplicitProtected) then
        Adapters.status[id] = { state = "protected", frame = frame }
        return false
    end

    local applied, state = RunDefinition(definition, frame)
    Adapters.status[id] = { state = state, frame = frame }
    if not applied then
        return false
    end
    if definition.trackIconTree == true then
        NS.Checkmarks.TrackControlTree(frame, id, definition.iconTreeOptions)
    end
    NS.WindowControls.Attach(frame, id)
    return true
end

local function RefreshDefinition(definition)
    local id = definition.id
    local previous = Adapters.status[id]
    local frame = previous and previous.frame
    local disabled, reason = DisableDefinition(definition, frame)
    if not disabled then
        Adapters.status[id] = { state = reason or "disable-failed", frame = frame }
        return false
    end
    return ApplyDefinition(definition)
end

-- The whole apply of one adapter, including the icon tree and window
-- controls after its own callbacks, is one boundary: an error is reported,
-- the adapter reads "error" and the next adapter still applies.
local function RunIsolated(operation, definition)
    local finished, result = NS.Safety.Dispatch(Finish, operation, definition)
    if finished then return result end
    local previous = Adapters.status[definition.id]
    Adapters.status[definition.id] = { state = "error", frame = previous and previous.frame }
    return false
end

function Adapters.Apply(id)
    local definition = Adapters.definitions[id]
    if not definition then
        return false
    end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("adapter:" .. id, function() RunIsolated(ApplyDefinition, definition) end)
        return false
    end
    return RunIsolated(ApplyDefinition, definition)
end

function Adapters.ApplyAll()
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("adapters:all", Adapters.ApplyAll)
        return false
    end
    for index = 1, #Adapters.order do
        RunIsolated(ApplyDefinition, Adapters.definitions[Adapters.order[index]])
    end
    return true
end

function Adapters.Refresh(id)
    local definition = Adapters.definitions[id]
    if not definition then return false end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("adapter-refresh:" .. id, function() Adapters.Refresh(id) end)
        return false
    end
    return RunIsolated(RefreshDefinition, definition)
end

function Adapters.SetEnabled(id, enabled)
    local definition = Adapters.definitions[id]
    if NS.IsCombatLocked() or not definition then
        return false
    end
    NS.DB.skins[id] = enabled == true
    RunIsolated(ApplyDefinition, definition)
    NS.Registry.NotifyListeners("adapter", id)
    return true
end

-- Each stage is its own boundary: a stage that raises is reported and the
-- later stages still apply (or release) the skin and notify the listeners.
function Adapters.SetMasterEnabled(enabled)
    if NS.IsCombatLocked() then
        return false
    end
    NS.DB.enabled = enabled == true
    local dispatch = NS.Safety.Dispatch
    dispatch(NS.BlizzardYellow.Apply)
    dispatch(NS.Checkmarks.Apply)
    dispatch(NS.Typography.ApplyConfigured)
    dispatch(Adapters.ApplyAll)
    dispatch(NS.Registry.RefreshAll)
    NS.Registry.NotifyListeners("adapter", "master")
    return true
end

function Adapters.GetDefinitions()
    return Adapters.order, Adapters.definitions
end

function Adapters.GetStatus(id)
    local status = Adapters.status[id]
    return status and status.state or "pending"
end

-- Sub-skins of the Blizzard window adapter, applied in this order after the
-- generic catalog. A failure whose reason is `tolerated` (combat deferral, a
-- pending load-on-demand addon) still counts as applied; any other failure,
-- including a part that raised, reports the adapter as "partial". `category`
-- gates a part on its catalog category; skipped parts count as applied.
local COMBAT_OR_WAITING = { combat = true, waiting = true }
local COMBAT_ONLY = { combat = true }
local windowParts = {
    { module = "DeepWindows", tolerated = COMBAT_OR_WAITING },
    { module = "SemanticHUD", tolerated = COMBAT_OR_WAITING },
    { module = "SharedChrome", tolerated = COMBAT_OR_WAITING },
    { module = "UIPanelButtons", tolerated = COMBAT_ONLY },
    { module = "CommonMenus", tolerated = COMBAT_ONLY },
    { module = "Commerce", tolerated = COMBAT_OR_WAITING },
    { module = "CharacterPanel", tolerated = COMBAT_OR_WAITING, category = "character" },
    { module = "InspectPanel", tolerated = COMBAT_OR_WAITING, category = "character" },
    { module = "SocialUISkin", tolerated = COMBAT_OR_WAITING, category = "social" },
    { module = "MajorWindows", tolerated = COMBAT_OR_WAITING },
    { module = "LegacyWindows", tolerated = COMBAT_OR_WAITING },
    -- Forever's group finder has its own adapter below.
    { module = "CommonArt", tolerated = COMBAT_ONLY, category = "group", excludeForever = true },
    { module = "ForeverGroupFinder", tolerated = COMBAT_ONLY },
}

-- The same parts in their release order; the generic catalog goes last.
local windowPartsDisableOrder = {
    "UIPanelButtons", "SharedChrome", "Commerce", "CommonArt", "ForeverGroupFinder",
    "CommonMenus", "SocialUISkin", "CharacterPanel", "InspectPanel", "LegacyWindows",
    "MajorWindows", "SemanticHUD", "DeepWindows",
}

local function PartEnabled(part)
    if part.excludeForever and NS.Client.isForever then
        return false
    end
    return not part.category or NS.GenericWindows.IsCategoryEnabled(part.category)
end

-- Calls NS[moduleName][method](owner). Every part module loads before this
-- file (TOC order).
local function CallPart(moduleName, method, owner)
    return NS[moduleName][method](owner)
end

-- Each part, including the lookup of its module, is its own boundary: a
-- part that raises is reported (nil, "error") and the other parts still
-- apply or release.
local function RunPart(moduleName, method, owner)
    local finished, first, second = NS.Safety.Dispatch(Finish, CallPart, moduleName, method, owner)
    if not finished then return nil, "error" end
    return first, second
end

-- Like RunPart, for a release: true when the part finished it. A part that
-- refuses in combat still holds its skin, so it is not counted as released
-- (false, "combat") and its release runs again once combat ends.
local function ReleasePart(moduleName, owner)
    local finished, released, reason = NS.Safety.Dispatch(Finish, CallPart, moduleName, "Disable", owner)
    if finished and released == false and reason == "combat" and NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("window-part-release:" .. moduleName .. ":" .. tostring(owner), function()
            ReleasePart(moduleName, owner)
        end)
        return false, "combat"
    end
    return finished == true
end

-- True when a part failed for a reason its entry does not tolerate.
local function ApplyWindowParts(owner)
    local partial = false
    for index = 1, #windowParts do
        local part = windowParts[index]
        if PartEnabled(part) then
            local applied, reason = RunPart(part.module, "Apply", owner)
            if not applied and not part.tolerated[reason] then
                partial = true
            end
        end
    end
    return partial
end

-- failed: a part raised while it released its skin; combat: a part refused
-- in combat and releases once combat ends.
local function DisableWindowParts(owner)
    local failed, combat = false, false
    for index = 1, #windowPartsDisableOrder do
        local released, reason = ReleasePart(windowPartsDisableOrder[index], owner)
        if not released and reason == "combat" then
            combat = true
        elseif not released then
            failed = true
        end
    end
    return failed, combat
end

Adapters.Register({
    id = "blizzardWindows",
    labelKey = "SKIN_BLIZZARD_WINDOWS",
    resolve = function() return NS.BlizzardCatalog end,
    apply = function(_, owner)
        local genericApplied, genericReason = RunPart("GenericWindows", "ApplyAll", owner)
        if NS.GenericWindows.IsCategoryEnabled("character") then
            RunPart("MacroWindow", "Start", owner)
        end
        if not genericApplied then
            return false, genericReason
        end
        if ApplyWindowParts(owner) then
            return true, "partial"
        end
        return true, genericReason
    end,
    disable = function(_, owner)
        local failed, combat = DisableWindowParts(owner)
        local finished, disabled, reason = NS.Safety.Dispatch(Finish, CallPart, "GenericWindows", "Disable", owner)
        if failed or not finished then
            return false, "error"
        end
        if combat then return false, "combat" end
        return disabled, reason
    end,
})

Adapters.Register({
    id = "colorPicker",
    labelKey = "SKIN_COLOR_PICKER",
    resolve = function() return _G.ColorPickerFrame end,
    apply = function(frame, owner)
        -- OpacityFrame ships in the same addon (ColorPickerFrame.xml).
        local applied, reason = NS.GenericWindows.ApplyFrame(frame, owner, "dialog")
        NS.GenericWindows.ApplyFrame(_G.OpacityFrame, owner, "dialog")
        return applied, reason
    end,
    disable = function(_, owner)
        return NS.GenericWindows.Disable(owner)
    end,
})

Adapters.Register({
    id = "settings",
    labelKey = "SKIN_SETTINGS",
    resolve = function() return _G.SettingsPanel end,
    apply = function(frame, owner)
        local applied, reason = NS.GenericWindows.ApplyFrame(frame, owner, "window")
        if applied then
            NS.Checkmarks.TrackSettingsCategories(frame.CategoryList, owner, frame)
        end
        return applied, reason
    end,
    disable = function(_, owner)
        return NS.GenericWindows.Disable(owner)
    end,
})

Adapters.Register({
    id = "addonList",
    labelKey = "SKIN_ADDON_LIST",
    resolve = function() return _G.AddonList end,
    -- AddonDialog is glue-only: AddonList's OnLoad clears it in game.
    apply = function(frame, owner)
        return NS.GenericWindows.ApplyFrame(frame, owner, "window")
    end,
    disable = function(_, owner)
        return NS.GenericWindows.Disable(owner)
    end,
})

Adapters.Register({
    id = "gameMenu",
    labelKey = "SKIN_GAME_MENU",
    resolve = function() return _G.GameMenuFrame end,
    apply = function(frame, owner)
        return NS.GameMenuSkin.Apply(frame, owner)
    end,
    disable = function(frame, owner)
        return NS.GameMenuSkin.Disable(frame, owner)
    end,
})

Adapters.Register({
    id = "worldMap",
    labelKey = "SKIN_WORLD_MAP",
    allowImplicitProtected = true,
    trackIconTree = true,
    resolve = function() return _G.WorldMapFrame end,
    apply = function(frame, owner)
        return NS.WorldMapSkin.Apply(frame, owner)
    end,
    disable = function(frame, owner)
        return NS.WorldMapSkin.Disable(frame, owner)
    end,
})

Adapters.Register({
    id = "playerSpells",
    labelKey = "SKIN_PLAYER_SPELLS",
    loadAddon = "Blizzard_PlayerSpells",
    allowImplicitProtected = true,
    trackIconTree = true,
    resolve = function() return _G.PlayerSpellsFrame end,
    apply = function(frame, owner)
        return NS.PlayerSpellsSkin.Apply(frame, owner)
    end,
    disable = function(frame, owner)
        return NS.PlayerSpellsSkin.Disable(frame, owner)
    end,
})

Adapters.Register({
    id = "encounterJournal",
    labelKey = "SKIN_ENCOUNTER_JOURNAL",
    loadAddon = "Blizzard_EncounterJournal",
    allowImplicitProtected = true,
    trackIconTree = true,
    resolve = function() return _G.EncounterJournal end,
    apply = function(frame, owner)
        return NS.EncounterJournalSkin.Apply(frame, owner)
    end,
    disable = function(frame, owner)
        return NS.EncounterJournalSkin.Disable(frame, owner)
    end,
})

Adapters.Register({
    id = "chatFrames",
    labelKey = "SKIN_CHAT_FRAMES",
    allowImplicitProtected = true,
    resolve = function() return _G.ChatFrame1 end,
    apply = function(frame, owner)
        return NS.ChatFramesSkin.Apply(frame, owner)
    end,
    disable = function(frame, owner)
        return NS.ChatFramesSkin.Disable(frame, owner)
    end,
})

Adapters.Register({
    id = "damageMeter",
    labelKey = "SKIN_DAMAGE_METER",
    -- The Suite damage meter turns Blizzard's meter off while it runs.
    suiteSurface = "damageMeter",
    allowImplicitProtected = true,
    trackIconTree = true,
    resolve = function() return _G.DamageMeter end,
    apply = function(frame, owner)
        return NS.DamageMeterSkin.Apply(frame, owner)
    end,
    disable = function(frame, owner)
        return NS.DamageMeterSkin.Disable(frame, owner)
    end,
})

Adapters.Register({
    id = "editMode",
    labelKey = "SKIN_EDIT_MODE",
    allowImplicitProtected = true,
    trackIconTree = true,
    resolve = function() return _G.EditModeManagerFrame end,
    apply = function(frame, owner)
        return NS.EditModeSkin.Apply(frame, owner)
    end,
    disable = function(frame, owner)
        return NS.EditModeSkin.Disable(frame, owner)
    end,
})

Adapters.Register({
    id = "communities",
    labelKey = "SKIN_COMMUNITIES",
    loadAddon = "Blizzard_Communities",
    allowImplicitProtected = true,
    trackIconTree = true,
    resolve = function() return _G.CommunitiesFrame end,
    apply = function(frame, owner)
        return NS.CommunitiesSkin.Apply(frame, owner)
    end,
    disable = function(frame, owner)
        return NS.CommunitiesSkin.Disable(frame, owner)
    end,
})

Adapters.Register({
    id = "microMenu",
    labelKey = "SKIN_MICRO_MENU",
    loadAddon = "Blizzard_MicroMenu",
    allowImplicitProtected = true,
    resolve = function() return _G.MicroMenu end,
    apply = function(frame, owner)
        return NS.MicroMenuSkin.Apply(frame, owner)
    end,
    disable = function(frame, owner)
        return NS.MicroMenuSkin.Disable(frame, owner)
    end,
})
