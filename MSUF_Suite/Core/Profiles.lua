local _, Suite = ...
local P = { prefix = "MSUFS2:", maxBytes = 3 * 1024 * 1024 }
Suite.SuiteProfiles = P
local DB, IO = Suite.Database, Suite.ProfileIO

-- Returns the Suite-owned skin engine once its database is ready. The second
-- result tells whether the engine is loaded at all.
local function LoadedSkin()
    local skin = _G.MapkoSkin
    if type(skin) ~= "table" or rawget(skin, "addonName") ~= "MSUF_Suite_Skin"
        or not skin.Database or not skin.ProfileIO then
        return nil, false
    end
    if type(skin.EnsureDatabaseReady) == "function" then skin.EnsureDatabaseReady() end
    if type(skin.Database.GetRoot) == "function" and not skin.Database.GetRoot() then return nil, true end
    return skin, true
end

local function SkinEngine()
    local skin, loaded = LoadedSkin()
    if loaded then return skin end
    local enabled = Suite.Client and Suite.Client.AddOnEnabled and Suite.Client.AddOnEnabled("MSUF_Suite_Skin")
    if enabled and Suite.Skin and Suite.Skin.EnsureEngine and Suite.Skin.EnsureEngine() then
        return (LoadedSkin())
    end
end

local function SkinSnapshot(skin)
    if not skin then return nil end
    local encoded, reason = skin.ProfileIO.ExportProfile()
    if not encoded then return nil, reason end
    return skin.ProfileIO.PrepareProfile(encoded)
end

-- Left edge of the Damage Meter windows, as an offset from the right screen
-- edge they are anchored to; nil without measurable windows.
local function MeterLeftEdge(modules)
    local meter = modules and modules.damageMeter
    if not meter or type(meter.windowCount) ~= "number" then return nil end
    local leftEdge
    for i = 1, math.min(meter.windowCount, 5) do
        local x, width = meter["w" .. i .. "X"], meter["w" .. i .. "Width"]
        if type(x) == "number" and type(width) == "number" then
            leftEdge = math.min(leftEdge or 0, x - width)
        end
    end
    return leftEdge
end

local function PlaceFactoryMenu(profile, modules)
    local menu = profile.icons and profile.icons.microMenu
    if menu then
        local leftEdge = MeterLeftEdge(modules)
        if leftEdge and leftEdge < 0 then
            -- Both the meter and menu follow UIParent's right edge. Use the
            -- meter's configured left edge with a two-pixel visual gap so the
            -- menu stays beside it at every resolution and UI scale.
            menu.layoutPoint, menu.layoutRelativePoint = "BOTTOMRIGHT", "BOTTOMRIGHT"
            menu.layoutX, menu.layoutY = leftEdge - 2, 0
        else
            menu.layoutPoint, menu.layoutRelativePoint = "BOTTOMLEFT", "BOTTOMLEFT"
            menu.layoutX, menu.layoutY = 18, 18
        end
        menu.positionPreset = "custom"
    end
end

local function AdaptFactorySkin(profile, modules)
    if profile.windowControls then profile.windowControls.positions = {} end
    -- A Forever factory carries the selected menu position in its Skin export.
    -- Modern supplies module geometry so its menu can follow the Damage Meter.
    if modules then PlaceFactoryMenu(profile, modules) end
end

-- MSUF owns the selected profile in the unified UI. A Suite profile with the
-- same name is created from current settings on the first switch; older Suite
-- profiles are retained, never renamed or discarded.
function P.SyncActive(name)
    if Suite.suppressProfileSync or not Suite.RootDB or not DB.IsProfileName(name) then return false end
    local installation = Suite.RootDB.installation
    if installation and installation.status == "complete" and installation.profile == "suite"
        and not installation.frameProfileName then
        local previousName = DB.GetActiveProfileName()
        if DB.IsProfileName(previousName) then installation.frameProfileName = previousName end
    end
    if DB.GetActiveProfileName() ~= name then
        if not DB.GetProfile(name) then
            local ok = DB.Create(name, true)
            if not ok then return false end
        end
        if not DB.Activate(name) then return false end
    end
    local skin = SkinEngine()
    if skin then
        if not skin.Database.GetProfile(name) then
            local ok = skin.Database.CreateProfile(name, true)
            if not ok then return false end
        end
        local repaired = false
        if installation and installation.status == "complete" and installation.profile == "suite"
            and installation.frameProfileName == name and installation.modernMeterMenuRevision ~= 2 then
            local current = skin.Database.GetProfile(name)
            local menu = current and current.icons and current.icons.microMenu
            local modules = DB.GetProfile(name)
            modules = modules and modules.suite and modules.suite.modules
            local leftEdge = MeterLeftEdge(modules)
            local oldCorner = menu and menu.layoutPoint == "BOTTOMLEFT"
                and menu.layoutRelativePoint == "BOTTOMLEFT"
                and menu.layoutX == 18 and menu.layoutY == 18
            local oldMeterGap = menu and leftEdge and menu.layoutPoint == "BOTTOMRIGHT"
                and menu.layoutRelativePoint == "BOTTOMRIGHT"
                and menu.layoutX == leftEdge - 12 and menu.layoutY == 18
            if menu and menu.positionPreset == "custom" and (oldCorner or oldMeterGap) and modules then
                local updated = Suite.CopyValue(current)
                PlaceFactoryMenu(updated, modules)
                repaired = skin.Database.SetProfile(name, updated) == true
            end
            if not oldCorner and not oldMeterGap or repaired then
                installation.modernMeterMenuRevision = 2
            end
        end
        if skin.Database.GetActiveProfileName() == name and not repaired then return true end
        return skin.Database.SetActiveProfile(name)
    end
    return true
end
Suite.OnMSUFProfileChanged = P.SyncActive

-- MSUF resolves a new character's frame profile before Suite starts. Install
-- the chosen Suite profile as MSUF's new-character default once, and repair
-- this login if MSUF already assigned its historical "Default" fallback.
-- An existing MSUF preference (including one later cleared by the user) wins.
function P.EnsureNewCharacterProfile()
    local installation = Suite.RootDB and Suite.RootDB.installation
    if type(installation) ~= "table" or installation.status ~= "complete"
        or installation.newCharacterProfileRevision == 1 then return false end
    local name = installation.frameProfileName or DB.GetActiveProfileName()
    local profiles = _G.MSUF_GlobalDB and _G.MSUF_GlobalDB.profiles
    if not DB.IsProfileName(name) or type(profiles) ~= "table"
        or type(profiles[name]) ~= "table" then return false end
    if not installation.frameProfileName then installation.frameProfileName = name end
    local get = _G.MSUF_GetDefaultProfileForNewCharacters
    local set = _G.MSUF_SetDefaultProfileForNewCharacters
    if type(get) ~= "function" or type(set) ~= "function" then return false end
    local chosen = get()
    if chosen then
        installation.newCharacterProfileRevision = 1
        return false
    end
    if set(name) ~= true then return false end
    installation.newCharacterProfileRevision = 1
    installation.newCharacterProfileOwned = true
    if _G.MSUF_ProfileWasUnboundAtLogin == true and _G.MSUF_ActiveProfile ~= name
        and type(_G.MSUF_SwitchProfile) == "function" and not Suite.IsCombatLocked() then
        return _G.MSUF_SwitchProfile(name) == true
    end
    return true
end

-- Retail Modern and Retail Forever both need the same resource stack above
-- their Essential row. Apply once; rerunning the installer explicitly restores
-- these defaults on the newly selected frame profile.
function P.EnsureRetailResourceStack(force)
    local installation = Suite.RootDB and Suite.RootDB.installation
    local module = Suite.DB and Suite.DB.suite and Suite.DB.suite.modules
    module = module and module.cooldownManager
    if not (Suite.Client and Suite.Client.isMainline)
        or type(installation) ~= "table" or installation.status ~= "complete"
        or (installation.profile ~= "suite" and installation.profile ~= "forever")
        or (installation.profile == "forever" and Suite.Client.isForever == true)
        or type(module) ~= "table"
        or module.enabled == false then return false end
    if not force and installation.resourceStackRevision == 1 then return false end
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return false end
    local bars, player = db.bars, db.player
    if type(bars) ~= "table" or type(player) ~= "table" then return false end
    local migrate = force or (bars.classPowerAnchorToCooldown ~= true
        and (player.powerBarDetached == true
            and player.detachedPowerBarAnchorToClassPower == true
            or installation.profile == "forever" and bars.classPowerOffsetY == -41))
    installation.resourceStackRevision = 1
    if not migrate then return false end
    bars.showClassPower = true
    bars.classPowerAnchorToCooldown = true
    bars.classPowerCooldownTopAnchor = true
    bars.classPowerWidthMode = "cooldown"
    bars.detachedPowerBarWidthMode = "cooldown"
    bars.classPowerOffsetX, bars.classPowerOffsetY = 0, 0
    player.showPowerBar = true
    player.powerBarDetached = true
    player.detachedPowerBarAnchorToClassPower = true
    player.detachedPowerBarSyncClassPower = true
    player.detachedPowerBarAnchorMode = "CENTER"
    player.detachedPowerBarOffsetX, player.detachedPowerBarOffsetY = 0, -4
    if type(_G.MSUF_EnsureCooldownWidthObservers) == "function" then
        _G.MSUF_EnsureCooldownWidthObservers()
    end
    if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player", true)
    end
    if type(_G.MSUF_ClassPower_Apply) == "function" then
        _G.MSUF_ClassPower_Apply({ playerHP = true })
    end
    if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
        _G.MSUF_UFCore_NotifyConfigChanged("player", false, true, "SuiteResourceStack")
    end
    return true
end

-- Older Retail Forever imports had Potions attached to Utility at Y=-380.
-- Repair that exact factory layout before CDM starts, preserving personal
-- changes and the authored Forever icon sizes/positions.
function P.EnsureRetailForeverCooldownLayout()
    local installation = Suite.RootDB and Suite.RootDB.installation
    if not (Suite.Client and Suite.Client.isMainline and Suite.Client.isForever ~= true)
        or type(installation) ~= "table" or installation.status ~= "complete"
        or installation.profile ~= "forever" or installation.foreverAnchorRevision == 1 then
        return false
    end
    local config = Suite.DB and Suite.DB.suite and Suite.DB.suite.modules
    config = config and config.cooldownManager
    if type(config) ~= "table" or config.enabled == false then return false end
    local anchor
    for index, unit in pairs(Suite.CDM and Suite.CDM.FRAME_ANCHORS or {}) do
        if unit == "player" then anchor = index; break end
    end
    if not anchor then return false end
    installation.foreverAnchorRevision = 1
    if config.ext_anchor ~= 3 or config.ext_y ~= -380 then return false end
    config.def_anchor, config.def_side = anchor, 2
    config.def_gap, config.def_align = 44, 3
    config.def_x, config.def_y = 0, 0
    config.ext_anchor, config.ext_side = anchor, 1
    config.ext_gap, config.ext_align = 22, 2
    config.ext_x, config.ext_y = 0, 0
    config.captured = true
    config.defaultsVersion = Suite.CDM.DEFAULTS_VERSION
    if Suite.Suite and Suite.Suite.started and Suite.Suite.Apply then
        Suite.Suite.Apply("cooldownManager")
    end
    return true
end

-- MSUF's native Profiles page owns names and copy operations. Keep the Suite
-- and optional skin profile stores aligned with those same actions.
function P.OnLifecycle(kind, source, target)
    if Suite.suppressProfileSync or not Suite.RootDB or Suite.IsCombatLocked() then return false end
    local skin = SkinEngine()
    if kind == "create" and DB.IsProfileName(source) then
        if not DB.GetProfile(source) then DB.Create(source, false) end
        if skin and not skin.Database.GetProfile(source) then skin.Database.CreateProfile(source, false) end
        return true
    end
    if kind == "reset" and DB.IsProfileName(source) then
        if DB.GetProfile(source) then
            local profile = DB.CreateFactoryProfile()
            Suite.Suite.Normalize(profile)
            Suite.RootDB.profiles[source] = profile
            if DB.GetActiveProfileName() == source then DB.Activate(source) end
        end
        if skin and skin.Defaults then
            local factory = skin.Database.CreateFactoryProfile and skin.Database.CreateFactoryProfile()
                or Suite.CopyValue(skin.Defaults)
            skin.Database.SetProfile(source, factory)
            if skin.Database.GetActiveProfileName() == source then skin.Database.SetActiveProfile(source) end
        end
        return true
    end
    if kind == "copy" and DB.IsProfileName(source) and DB.IsProfileName(target) then
        if not DB.GetProfile(target) then
            local original = DB.GetProfile(source)
            if original then DB.CreateFromProfile(target, original) else DB.Create(target, false) end
        end
        if skin and not skin.Database.GetProfile(target) then
            local original = skin.Database.GetProfile(source)
            if original then skin.Database.SetProfile(target, Suite.CopyValue(original))
            else skin.Database.CreateProfile(target, false) end
        end
        return true
    end
    if kind == "rename" and DB.IsProfileName(source) and DB.IsProfileName(target) then
        local original = DB.GetProfile(source)
        if original and not DB.GetProfile(target) then
            Suite.RootDB.profiles[target] = original
            Suite.RootDB.profiles[source] = nil
            if DB.GetActiveProfileName() == source then DB.Activate(target) end
        end
        if skin then
            local old = skin.Database.GetProfile(source)
            if old and not skin.Database.GetProfile(target) then
                skin.Database.SetProfile(target, Suite.CopyValue(old))
                if skin.Database.GetActiveProfileName() == source then skin.Database.SetActiveProfile(target) end
                skin.Database.DeleteProfile(source)
            end
        end
        return true
    end
    if kind == "delete" and DB.IsProfileName(source) then
        if DB.GetProfile(source) and DB.GetActiveProfileName() ~= source then DB.Delete(source) end
        if skin and skin.Database.GetProfile(source)
            and skin.Database.GetActiveProfileName() ~= source then skin.Database.DeleteProfile(source) end
        return true
    end
    return false
end
Suite.OnMSUFProfileLifecycle = P.OnLifecycle

-- Classic MSUF has a transactional import into a new profile. Main MSUF has
-- its external (Wago pack) import instead: it validates the string and stores
-- it under a new profile name without touching the active profile, so the
-- switch happens only after the import succeeded.
local function CanImportFrames()
    return type(_G.MSUF_Profiles_ImportIntoNewProfile) == "function"
        or type(_G.MSUF_Profiles_ImportExternal) == "function"
end

local function ImportFramesIntoNewProfile(name, frames)
    local native = _G.MSUF_Profiles_ImportIntoNewProfile
    if type(native) == "function" then return native(name, frames) end
    local profiles = _G.MSUF_GlobalDB.profiles
    local ok, why = _G.MSUF_Profiles_ImportExternal(frames, name)
    if ok ~= true or type(profiles[name]) ~= "table" then
        if profiles[name] ~= nil then _G.MSUF_DeleteProfile(name) end
        return false, why or "Frame profile import failed"
    end
    if _G.MSUF_SwitchProfile(name) == true and _G.MSUF_ActiveProfile == name then return true end
    if _G.MSUF_ActiveProfile ~= name then _G.MSUF_DeleteProfile(name) end
    return false, "Frame profile could not be activated"
end

function P.Available()
    return Suite.RootDB ~= nil and type(_G.MSUF_GlobalDB) == "table"
        and type(_G.MSUF_GlobalDB.profiles) == "table"
        and type(_G.MSUF_Profiles_ExportSelectionToString) == "function"
        and CanImportFrames()
        and type(_G.MSUF_SwitchProfile) == "function"
        and type(_G.MSUF_DeleteProfile) == "function"
end

function P.Active()
    local frames = _G.MSUF_ActiveProfile or "Default"
    local modules = DB.GetActiveProfileName()
    return frames == modules and frames or nil, frames, modules
end

function P.Names()
    local result = {}
    if P.Available() then
        for name in pairs(_G.MSUF_GlobalDB.profiles) do
            if DB.GetProfile(name) then result[#result + 1] = name end
        end
        table.sort(result)
    end
    return result
end

local function Ready()
    if Suite.IsCombatLocked() then return false, "Finish combat before changing profiles" end
    if not P.Available() then return false, "MSUF profile system unavailable" end
    return true
end

local function NewName(name)
    local ready, reason = Ready()
    if not ready then return nil, reason end
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or nil
    if not DB.IsProfileName(name) then return nil, "Enter a new profile name" end
    if DB.GetProfile(name) or _G.MSUF_GlobalDB.profiles[name] then
        return nil, "Profile name already exists"
    end
    return name
end

local function Restore(frames, modules)
    if _G.MSUF_ActiveProfile ~= frames then _G.MSUF_SwitchProfile(frames) end
    if DB.GetActiveProfileName() ~= modules then DB.Activate(modules) end
    return _G.MSUF_ActiveProfile == frames and DB.GetActiveProfileName() == modules
end

function P.Activate(name)
    local ready, reason = Ready()
    if not ready then return false, reason end
    if not DB.IsProfileName(name) or not DB.GetProfile(name) or not _G.MSUF_GlobalDB.profiles[name] then
        return false, "Choose a profile that exists in both parts of the suite"
    end
    local _, frames, modules = P.Active()
    local ok, why = _G.MSUF_SwitchProfile(name)
    if ok and _G.MSUF_ActiveProfile == name and DB.GetActiveProfileName() ~= name then
        ok, why = DB.Activate(name)
    end
    if ok and _G.MSUF_ActiveProfile == name and DB.GetActiveProfileName() == name then return true, name end
    if not Restore(frames, modules) then return false, "Profile switch failed; restore the previous profiles manually" end
    return false, why or "Profile switch failed"
end

function P.Export()
    local ready, reason = Ready()
    if not ready then return nil, reason end
    local frames = _G.MSUF_Profiles_ExportSelectionToString("all")
    if type(frames) ~= "string" then return nil, "Frame profile export failed" end
    local modules, why = IO.ExportProfile()
    if not modules then return nil, why end
    local skin = SkinEngine()
    local skinText, skinReason
    if skin then
        skinText, skinReason = skin.ProfileIO.ExportProfile()
        if not skinText then return nil, skinReason end
    end
    local result = (skinText and "MSUFS3:" or P.prefix) .. frames .. "\n" .. modules
        .. (skinText and "\n" .. skinText or "")
    if #result > P.maxBytes then return nil, "Suite profile is too large" end
    return result
end

local function Create(name, frames, profile, skinProfile, screenHeight)
    local _, previousFrames, previousModules = P.Active()
    local skin = skinProfile and SkinEngine()
    if skinProfile and (not skin or skin.Database.GetProfile(name)) then
        return false, "Skin profile name already exists or skin engine is unavailable"
    end
    local previousSkin = skin and skin.Database.GetActiveProfileName()
    -- Module settings have already been validated. MSUF validates its own
    -- payload before creating a frame profile and reports a refusal as
    -- false, reason. Neither import overwrites data.
    Suite.suppressProfileSync = true
    local ok, reason = ImportFramesIntoNewProfile(name, frames)
    Suite.suppressProfileSync = nil
    if ok and screenHeight and type(_G.MSUF_SetCurrentProfileScreenReferenceHeight) == "function" then
        ok = _G.MSUF_SetCurrentProfileScreenReferenceHeight(screenHeight)
        if not ok then reason = "Frame positions could not be adapted" end
    end
    if ok then ok, reason = DB.CreateFromProfile(name, profile) end
    if ok then ok, reason = DB.Activate(name) end
    if ok and skinProfile then ok, reason = skin.Database.SetProfile(name, skinProfile) end
    if ok and skinProfile then ok, reason = skin.Database.SetActiveProfile(name) end
    if ok and _G.MSUF_ActiveProfile == name and DB.GetActiveProfileName() == name then return true, name end
    if skin and previousSkin and skin.Database.GetProfile(previousSkin) then
        skin.Database.SetActiveProfile(previousSkin)
    end
    if skin and skin.Database.GetProfile(name) then skin.Database.DeleteProfile(name) end
    if not Restore(previousFrames, previousModules) then
        return false, "Profile import failed; restore the previous profiles manually"
    end
    if _G.MSUF_GlobalDB.profiles[name] then _G.MSUF_DeleteProfile(name) end
    if DB.GetProfile(name) then DB.Delete(name) end
    if _G.MSUF_GlobalDB.profiles[name] or DB.GetProfile(name) then
        return false, "Profile import failed; the incomplete profile could not be removed"
    end
    return false, reason or "Profile import failed"
end

function P.SaveAs(name)
    local clean, reason = NewName(name)
    if not clean then return false, reason end
    local profile, why = IO.PrepareTable(Suite.DB, false)
    if not profile then return false, why end
    local frames = _G.MSUF_Profiles_ExportSelectionToString("all")
    if type(frames) ~= "string" then return false, "Frame profile export failed" end
    local skin = SkinEngine()
    local skinProfile = skin and Suite.CopyValue(skin.Database.GetProfile(skin.Database.GetActiveProfileName()))
    if skin and not skinProfile then return false, "Skin profile unavailable" end
    return Create(clean, frames, profile, skinProfile)
end

function P.Import(name, text)
    local clean, reason = NewName(name)
    if not clean then return false, reason end
    if type(text) ~= "string" or #text > P.maxBytes then return false, "Invalid suite profile" end
    text = text:match("^%s*(.-)%s*$"):gsub("\r\n", "\n")
    local version, frames, modules, skinText = text:match("^MSUFS(3):([^\n]+)\n([^\n]+)\n([^\n]+)$")
    if not version then version, frames, modules = text:match("^MSUFS([12]):([^\n]+)\n([^\n]+)$") end
    if not frames or not frames:match("^MSUF[234]:") then return false, "Invalid suite profile" end
    local decode = version == "1" and IO.PrepareLegacyProfile or IO.PrepareProfile
    local profile, why = decode(modules)
    if not profile then return false, why end
    local skin = SkinEngine()
    local skinProfile, skinReason
    if version == "3" or (version == "1" and skin) then
        if not skin then return false, "Skin engine unavailable" end
        skinProfile, skinReason = skin.ProfileIO.PrepareProfile(version == "3" and skinText or modules)
    else
        skinProfile, skinReason = SkinSnapshot(skin)
    end
    if skin and not skinProfile then return false, skinReason end
    return Create(clean, frames, profile, skinProfile)
end

-- Installer-owned factory data is already bundled and validated by the same
-- catalog as normal profiles. Keep its module values, including explicit
-- enabled choices, while MSUF's frame import remains transactional.
function P.InstallFactory(name, frames, modules, skinText)
    local clean, reason = NewName(name)
    if not clean then return false, reason end
    if type(frames) ~= "string" or not frames:match("^MSUF[234]:") then
        return false, "Forever frame profile unavailable"
    end
    local profile, why = IO.PrepareTable(modules, false)
    if not profile then return false, why end
    local skin = SkinEngine()
    local skinProfile
    if skin then
        if type(skinText) == "string" then
            skinProfile, why = skin.ProfileIO.PrepareProfile(skinText)
        else
            skinProfile, why = SkinSnapshot(skin)
        end
        if not skinProfile then return false, why or "Skin profile unavailable" end
        if type(skinText) == "string" then AdaptFactorySkin(skinProfile) end
    end
    return Create(clean, frames, profile, skinProfile,
        Suite.ForeverFactoryScreenHeight)
end

-- Modern replaces only the active Suite and optional Skin settings. Prepare
-- both payloads before changing either store; the MSUF frame profile is never
-- imported or switched here.
function P.InstallSuiteFactory(name, modules, skinText)
    if not DB.IsProfileName(name) then return false, "MSUF profile unavailable" end
    local profile, reason = IO.PrepareTable(modules, false)
    if not profile then return false, reason end
    local skinEnabled = Suite.Client and Suite.Client.AddOnEnabled
        and Suite.Client.AddOnEnabled("MSUF_Suite_Skin")
    local skin, skinProfile
    if skinEnabled then
        skin = SkinEngine()
        if not skin then return false, "Skin engine unavailable" end
        skinProfile, reason = skin.ProfileIO.PrepareProfile(skinText)
        if not skinProfile then return false, reason or "Modern Skin profile unavailable" end
        AdaptFactorySkin(skinProfile, profile.suite.modules)
    end
    local previousModules = DB.GetProfile(name)
    local previousActive = DB.GetActiveProfileName()
    local previousSkin = skin and skin.Database.GetProfile(name)
    previousSkin = previousSkin and Suite.CopyValue(previousSkin)
    local previousSkinActive = skin and skin.Database.GetActiveProfileName()
    Suite.RootDB.profiles[name] = profile
    -- Activation starts the profile's modules; their errors reach the client.
    local ok, why = DB.Activate(name)
    if ok and skin then ok, why = skin.Database.SetProfile(name, skinProfile) end
    if ok and skin then ok, why = skin.Database.SetActiveProfile(name) end
    if ok then return true, name end
    Suite.RootDB.profiles[name] = previousModules
    if previousActive and DB.GetProfile(previousActive) then DB.Activate(previousActive) end
    if skin then
        if previousSkin then skin.Database.SetProfile(name, previousSkin)
        elseif skin.Database.GetProfile(name) then skin.Database.DeleteProfile(name) end
        if previousSkinActive and skin.Database.GetProfile(previousSkinActive) then
            skin.Database.SetActiveProfile(previousSkinActive)
        end
    end
    return false, why or "Modern profile could not be activated"
end

function P.ExportModule(id)
    if Suite.IsCombatLocked() then return nil, "Finish combat before exporting" end
    if id == "skin" then
        local skin = SkinEngine()
        if not skin then return nil, "Skin engine unavailable" end
        return skin.ProfileIO.ExportProfile()
    end
    return IO.ExportModule(id)
end

function P.ImportModule(text)
    if Suite.IsCombatLocked() then return false, "Finish combat before importing" end
    if type(text) == "string" and text:match("^%s*MSKIN1:") then
        local skin = SkinEngine()
        if not skin then return false, "Skin engine unavailable" end
        local profile, reason = skin.ProfileIO.PrepareProfile(text)
        if not profile then return false, reason end
        local name = _G.MSUF_ActiveProfile or skin.Database.GetActiveProfileName()
        local ok
        ok, reason = skin.Database.SetProfile(name, profile)
        if not ok then return false, reason end
        return skin.Database.SetActiveProfile(name)
    end
    local id, settings, reason = IO.PrepareModuleProfile(text)
    if not id then return false, reason end
    return Suite.Suite.SetMany(id, settings)
end

function P.ImportModuleIntoNew(name, text)
    local clean, reason = NewName(name)
    if not clean then return false, reason end
    if type(text) == "string" and text:match("^%s*MSKIN1:") then
        local skin = SkinEngine()
        if not skin then return false, "Skin engine unavailable" end
        local skinProfile
        skinProfile, reason = skin.ProfileIO.PrepareProfile(text)
        if not skinProfile then return false, reason end
        local frames = _G.MSUF_Profiles_ExportSelectionToString("all")
        if type(frames) ~= "string" then return false, "Frame profile export failed" end
        local profile, why = IO.PrepareTable(Suite.DB, false)
        if not profile then return false, why end
        return Create(clean, frames, profile, skinProfile)
    end
    local id, settings, why = IO.PrepareModuleProfile(text)
    if not id then return false, why end
    local frames = _G.MSUF_Profiles_ExportSelectionToString("all")
    if type(frames) ~= "string" then return false, "Frame profile export failed" end
    local profile
    profile, why = IO.PrepareTable(Suite.DB, false)
    if not profile then return false, why end
    profile.suite.modules[id] = settings
    local skin = SkinEngine()
    local skinProfile = skin and Suite.CopyValue(skin.Database.GetProfile(skin.Database.GetActiveProfileName()))
    if skin and not skinProfile then return false, "Skin profile unavailable" end
    return Create(clean, frames, profile, skinProfile)
end
