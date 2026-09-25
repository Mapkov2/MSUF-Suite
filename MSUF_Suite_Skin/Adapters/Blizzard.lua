local _, NS = ...

local Adapters = {
    definitions = {},
    order = {},
    status = {},
    waiting = {},
}
NS.Adapters = Adapters

local function IsUnsafeRoot(frame, definition)
    return not NS.Safety or not NS.Safety.CanDecorate(frame, definition.allowImplicitProtected)
end

function Adapters.Register(definition)
    if type(definition) ~= "table" or type(definition.id) ~= "string"
        or type(definition.resolve) ~= "function" then
        return false
    end
    if Adapters.definitions[definition.id] then
        return false
    end
    Adapters.definitions[definition.id] = definition
    Adapters.order[#Adapters.order + 1] = definition.id
    return true
end

function Adapters.Replace(definition)
    if type(definition) ~= "table" or type(definition.id) ~= "string"
        or type(definition.resolve) ~= "function" then
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
    if not definition.loadAddon then
        return false
    end
    if NS.Client and NS.Client.HasAddOn(definition.loadAddon)==false then return false end
    if Adapters.waiting[id] then
        return true
    end
    if not EventUtil or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then
        return false
    end

    -- EventUtil invokes its callback synchronously when the addon is already
    -- loaded.  If a Blizzard build has loaded the addon but omitted/renamed the
    -- expected root, rescheduling from that callback would recurse forever.
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loadedOrLoading, loaded = pcall(C_AddOns.IsAddOnLoaded, definition.loadAddon)
        if ok and (loaded == true or (loaded == nil and loadedOrLoading == true)) then
            return false
        end
    end

    Adapters.waiting[id] = true
    local ok, message = pcall(EventUtil.ContinueOnAddOnLoaded, definition.loadAddon, function()
        Adapters.waiting[id] = nil
        Adapters.Apply(id)
    end)
    if not ok then
        Adapters.waiting[id] = nil
        NS.ReportError("adapter load " .. id, message)
        return false
    end
    return true
end

local function DisableDefinition(definition, frame)
    local id = definition.id
    if NS.WindowControls then NS.WindowControls.DisableOwner(id) end
    if type(definition.disable) == "function" then
        local ok, disabled, reason = pcall(definition.disable, frame, id)
        if not ok then
            NS.ReportError("adapter disable " .. id, disabled)
            return false, "disable-failed"
        end
        if disabled == false then
            return false, reason or "disable-failed"
        end
    else
        NS.Cosmetics.RestoreOwner(id)
        if frame then
            NS.Surface.SetVisible(frame, false)
        end
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

local function ApplyDefinition(definition)
    local id = definition.id
    if not NS.DB.enabled or not DefinitionEnabled(definition) then
        local previous = Adapters.status[id]
        local disabled, reason = DisableDefinition(definition, previous and previous.frame)
        Adapters.status[id] = {
            state = disabled and "disabled" or (reason or "disable-failed"),
            frame = previous and previous.frame,
        }
        return false
    end

    local resolved, frame = pcall(definition.resolve)
    if not resolved then
        NS.ReportError("adapter resolve " .. id, frame)
        Adapters.status[id] = { state = "failed" }
        return false
    end
    if not frame then
        local waiting = ScheduleLoadOnDemand(definition)
        Adapters.status[id] = { state = waiting and "waiting" or "missing" }
        return false
    end
    if IsUnsafeRoot(frame, definition) then
        Adapters.status[id] = { state = "protected", frame = frame }
        return false
    end

    local appliedState
    if type(definition.apply) == "function" then
        local ok, applied, reason = pcall(definition.apply, frame, id)
        if not ok then
            NS.ReportError("adapter apply " .. id, applied)
            Adapters.status[id] = { state = "failed", frame = frame }
            return false
        end
        if applied == false then
            Adapters.status[id] = { state = reason or "failed", frame = frame }
            return false
        end
        if reason == "partial" then
            appliedState = "partial"
        end
    else
        local surface, reason = NS.Surface.Attach(frame, { role = "shell", inset = definition.inset or 0 })
        if not surface then
            Adapters.status[id] = { state = reason or "failed", frame = frame }
            return false
        end
        if type(definition.fade) == "function" then
            definition.fade(frame, id)
        end
        NS.Surface.SetVisible(frame, true)
    end
    if definition.trackIconTree == true and NS.Checkmarks
        and type(NS.Checkmarks.TrackControlTree) == "function" then
        local ok, message = pcall(NS.Checkmarks.TrackControlTree, frame, id,
            definition.iconTreeOptions)
        if not ok then NS.ReportError("adapter icon controls " .. id, message) end
    end
    Adapters.status[id] = { state = appliedState or "applied", frame = frame }
    if NS.WindowControls then NS.WindowControls.Attach(frame, id) end
    return true
end

function Adapters.Apply(id)
    local definition = Adapters.definitions[id]
    if not definition then
        return false
    end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("adapter:" .. id, function() ApplyDefinition(definition) end)
        return false
    end
    return ApplyDefinition(definition)
end

function Adapters.ApplyAll()
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("adapters:all", Adapters.ApplyAll)
        return false
    end
    for index = 1, #Adapters.order do
        ApplyDefinition(Adapters.definitions[Adapters.order[index]])
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
    local previous = Adapters.status[id]
    local disabled, reason = DisableDefinition(definition, previous and previous.frame)
    if not disabled then
        Adapters.status[id] = { state = reason or "disable-failed", frame = previous and previous.frame }
        return false
    end
    return ApplyDefinition(definition)
end

function Adapters.SetEnabled(id, enabled)
    local definition = Adapters.definitions[id]
    if NS.IsCombatLocked() or not definition then
        return false
    end
    NS.DB.skins[id] = enabled == true
    ApplyDefinition(definition)
    NS.Registry.NotifyListeners("adapter", id)
    return true
end

function Adapters.SetMasterEnabled(enabled)
    if NS.IsCombatLocked() then
        return false
    end
    NS.DB.enabled = enabled == true
    NS.BlizzardYellow.Apply()
    NS.Checkmarks.Apply()
    NS.Typography.ApplyConfigured()
    Adapters.ApplyAll()
    NS.Registry.RefreshAll()
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

function Adapters.GetStatusTable()
    local copy = {}
    for id, status in pairs(Adapters.status) do
        copy[id] = status and status.state or "pending"
    end
    return copy
end

Adapters.Register({
    id = "blizzardWindows",
    labelKey = "SKIN_BLIZZARD_WINDOWS",
    resolve = function() return NS.BlizzardCatalog end,
    apply = function(_, owner)
        local genericApplied, genericReason = NS.GenericWindows.ApplyAll(owner)
        if NS.GenericWindows.IsCategoryEnabled("character") then
            NS.MacroWindow.Start(owner)
        end
        if not genericApplied then
            return false, genericReason
        end
        local deepApplied, deepReason = NS.DeepWindows.Apply(owner)
        local semanticApplied, semanticReason = NS.SemanticHUD.Apply(owner)
        local sharedApplied, sharedReason = NS.SharedChrome.Apply(owner)
        local panelButtonsApplied, panelButtonsReason = NS.UIPanelButtons.Apply(owner)
        local commonApplied, commonReason = NS.CommonMenus.Apply(owner)
        local commerceApplied, commerceReason = NS.Commerce.Apply(owner)
        local characterApplied, characterReason = true, "disabled"
        local inspectApplied, inspectReason = true, "disabled"
        if NS.GenericWindows.IsCategoryEnabled("character") then
            characterApplied, characterReason = NS.CharacterPanel.Apply(owner)
            inspectApplied, inspectReason = NS.InspectPanel.Apply(owner)
        end
        local socialApplied, socialReason = true, "disabled"
        if NS.GenericWindows.IsCategoryEnabled("social") then
            socialApplied, socialReason = NS.SocialUISkin.Apply(owner)
        end
        local majorApplied, majorReason = NS.MajorWindows.Apply(owner)
        local legacyApplied, legacyReason = NS.LegacyWindows.Apply(owner)
        local artApplied, artReason = true, "disabled"
        if NS.GenericWindows.IsCategoryEnabled("group")
            and not (NS.Client and NS.Client.isForever) then
            artApplied, artReason = NS.CommonArt.Apply(owner)
        end
        local foreverGroupApplied, foreverGroupReason = NS.ForeverGroupFinder.Apply(owner)
        if not commonApplied and commonReason ~= "combat" then
            return true, "partial"
        end
        if not deepApplied and deepReason ~= "combat" and deepReason ~= "waiting" then
            return true, "partial"
        end
        if not semanticApplied and semanticReason ~= "combat" and semanticReason ~= "waiting" then
            return true, "partial"
        end
        if not sharedApplied and sharedReason ~= "combat" and sharedReason ~= "waiting" then
            return true, "partial"
        end
        if not panelButtonsApplied and panelButtonsReason ~= "combat" then
            return true, "partial"
        end
        if not commerceApplied and commerceReason ~= "combat" and commerceReason ~= "waiting" then
            return true, "partial"
        end
        if not characterApplied and characterReason ~= "combat" and characterReason ~= "waiting" then
            return true, "partial"
        end
        if not inspectApplied and inspectReason ~= "combat" and inspectReason ~= "waiting" then
            return true, "partial"
        end
        if not socialApplied and socialReason ~= "combat" and socialReason ~= "waiting" then
            return true, "partial"
        end
        if not majorApplied and majorReason ~= "combat" and majorReason ~= "waiting" then
            return true, "partial"
        end
        if not legacyApplied and legacyReason ~= "combat" and legacyReason ~= "waiting" then
            return true, "partial"
        end
        if not artApplied and artReason ~= "combat" then
            return true, "partial"
        end
        if not foreverGroupApplied and foreverGroupReason ~= "combat" then
            return true, "partial"
        end
        return true, genericReason
    end,
    disable = function(_, owner)
        NS.UIPanelButtons.Disable()
        NS.SharedChrome.Disable(owner)
        NS.Commerce.Disable(owner)
        NS.CommonArt.Disable(owner)
        NS.ForeverGroupFinder.Disable(owner)
        NS.CommonMenus.Disable(owner)
        NS.SocialUISkin.Disable(owner)
        NS.CharacterPanel.Disable(owner)
        NS.InspectPanel.Disable(owner)
        NS.LegacyWindows.Disable(owner)
        NS.MajorWindows.Disable(owner)
        NS.SemanticHUD.Disable(owner)
        NS.DeepWindows.Disable(owner)
        return NS.GenericWindows.Disable(owner)
    end,
})

Adapters.Register({
    id = "colorPicker",
    labelKey = "SKIN_COLOR_PICKER",
    resolve = function() return _G.ColorPickerFrame end,
    apply = function(frame, owner)
        local applied, reason = NS.GenericWindows.ApplyFrame(frame, owner, "dialog")
        if _G.OpacityFrame then
            NS.GenericWindows.ApplyFrame(_G.OpacityFrame, owner, "dialog")
        end
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
        if applied and NS.Checkmarks then
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
    apply = function(frame, owner)
        local applied, reason = NS.GenericWindows.ApplyFrame(frame, owner, "window")
        if _G.AddonDialog then
            NS.GenericWindows.ApplyFrame(_G.AddonDialog, owner, "dialog")
        end
        return applied, reason
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
