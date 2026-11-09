-- Combat reload discovery uses actual adapters, catalog and focus controller.
local root = assert(arg[1])
local file = assert(io.open(root .. "/tools/tests/suite_window_focus_contract.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local stop = assert(source:find('    local a = Native("CharacterFrame"', 1, true))
local body = [======[
    Load("Adapters/CatalogGlass.lua")
    for _, entry in ipairs(NS.BlizzardCatalog.entries) do
        for _, name in ipairs(entry.frames or {}) do if type(name) == "string" then _G[name] = nil end end
    end
    NS.DB.skins, NS.DB.skinCategories = { playerSpells = false, communities = false }, { social = false }
    local loaded = { Blizzard_UIPanels_Game = true, Blizzard_FriendsFrame = true,
        Blizzard_SocialUI = true, Blizzard_ItemSocketingUI = true, Blizzard_Professions = false,
        Blizzard_Communities = true }
    NS.Client.HasAddOn = function(addon) return loaded[addon] ~= nil end
    NS.Client.IsAddOnLoaded = function(addon) return loaded[addon] == true end
    NS.GenericWindows = { IsCategoryEnabled = function(category) return NS.DB.skinCategories[category] ~= false end }
    NS.SuiteOwnership.Owns = function() error("focus discovery consulted Suite geometry ownership") end
    NS.SuiteOwnership.EntrySurface = function() error("focus discovery consulted skin shell ownership") end
    local heavy = 0
    NS.Surface = { Attach = function() heavy = heavy + 1; error("heavy traversal during discovery") end }
    NS.PlayerSpellsSkin = { AttachWindowControls = function() heavy = heavy + 1 end }
    local legacyApplies = 0
    NS.ForeverLegacyTree = { Apply = function() legacyApplies = legacyApplies + 1 return true end }
    Load("Adapters/Blizzard.lua")
    local helper = io.open(root .. "/MSUF_Suite_Skin/Rendering/WindowFocusDiscovery.lua", "rb")
    local loader
    if helper then helper:close(); Load("Rendering/WindowFocusDiscovery.lua"); loader = H.frames[#H.frames] end
    local character = Native("CharacterFrame", 100, 100, 400, 500)
    character.explicitProtected, character.protected = true, true
    local friend = Native("FriendsFrame", 550, 100, 400, 500)
    local social = Native("SocialUIFrame", 950, 100, 400, 500)
    local item = Native("ItemSocketingFrame", 1400, 100, 300, 500)
    UIPanelWindows.ItemSocketingFrame = { area = "left" }
    local spells = Native("PlayerSpellsFrame", 400, 300, 500, 500)
    local communities = Native("CommunitiesFrame", 700, 300, 500, 500)
    UIPanelWindows.CommunitiesFrame = { area = "left" }
    _G.combat, _G.combatEdge = true, true
    NS.Adapters.ApplyAll()
    Check(F.records[character] and F.records[character].owners.blizzardWindows ~= nil,
        "combat reload missed the protected Character root before generic skin initialization")
    Check(not F.records[friend] and not F.records[social], "disabled social category was discovered")
    Check(F.records[item] and not F.records[spells] and not F.records[communities], "skipGeneric item root or dedicated disabled setting was ignored")
    Check(heavy == 0 and not character.geometryWrites, "combat focus discovery wrote native geometry or traversed the skin")
    Check(legacyApplies == (NS.Client.isForever and 1 or 0), "Forever legacy adapter missed combat startup")
    Check(loader and loader.events.ADDON_LOADED and not loader.scripts.OnUpdate,
        "cold catalog lacks bounded LoD discovery or installed a ticker")
    local hooks = #character.hooks.OnShow
    NS.DB.skinCategories.social = true
    NS.Adapters.ApplyAll()
    Check(F.records[friend] and F.records[social] and #character.hooks.OnShow == hooks,
        "enabling social missed skipGeneric SocialUI or duplicated character hooks")
    Check(not F.records[communities], "enabled generic category bypassed the disabled dedicated adapter")
    Check(F.records[social].owners["blizzardWindows:social-ui"] ~= nil
        and F.records[social].owners.blizzardWindows == nil, "Social focus used the wrong owner key")
    W.DisableOwner("blizzardWindows:social-ui")
    social:Hide(); social:Show()
    Check(F.active.frame ~= social, "normal Social owner release retained cold discovery ownership")
    NS.Adapters.ApplyAll()
    local professions = Native("ProfessionsFrame", 350, 300, 450, 500)
    professions.protected, professions.explicitProtected = true, true
    loaded.Blizzard_Professions = true
    loader.scripts.OnEvent(loader, "ADDON_LOADED", "Blizzard_Professions")
    Check(F.records[professions] and F.records[professions].owners.blizzardWindows ~= nil,
        "first combat LoD opening missed Professions before normal catalog callbacks existed")
    Check(not loader.events.ADDON_LOADED and not professions.geometryWrites and heavy == 0,
        "completed discovery retained its loader or touched protected native geometry")
    local addonCallbacks = {}
    EventUtil = { ContinueOnAddOnLoaded = function(addon, callback) addonCallbacks[addon] = callback end }
    NS.DB.skins.playerSpells, loaded.Blizzard_PlayerSpells, _G.PlayerSpellsFrame = true, false, nil
    NS.Adapters.Apply("playerSpells")
    Check(addonCallbacks.Blizzard_PlayerSpells ~= nil, "cold dedicated window failed to register its existing LoD callback")
    _G.PlayerSpellsFrame = spells
    loaded.Blizzard_PlayerSpells = true
    spells.protected, spells.explicitProtected = true, true
    NS.PlayerSpellsSkin.AttachWindowControls = function(frame, owner) return W.Attach(frame, owner) end
    addonCallbacks.Blizzard_PlayerSpells()
    Check(F.records[spells] and F.records[spells].owners.playerSpells ~= nil
        and not F.records[spells].owners.blizzardWindows and not spells.geometryWrites,
        "dedicated LoD window lost focus ownership or modified protected geometry")
    NS.DB.skins.playerSpells = false
    W.DisableOwner("playerSpells")
    NS.DB.skinCategories.social = false
    NS.Adapters.Apply("blizzardWindows")
    friend:Hide(); friend:Show()
    Check(F.active.frame ~= friend, "category disable left ghost focus ownership")
    NS.DB.skins.blizzardWindows = false
    NS.Adapters.ApplyAll()
    character:Hide(); character:Show()
    Check(not F.active and not driver.events.GLOBAL_MOUSE_DOWN and not loader.events.ADDON_LOADED,
        "disable before combat end retained focus or pending discovery")
    -- A pending load after disable cannot resurrect the owner's focus.
    NS.DB.skins.blizzardWindows = true
    loaded.Blizzard_Professions = false
    _G.ProfessionsFrame = nil
    NS.Adapters.ApplyAll()
    Check(loader.events.ADDON_LOADED, "re-enable did not restore the bounded pending load")
    NS.DB.enabled = false
    NS.Adapters.ApplyAll()
    _G.ProfessionsFrame = professions
    loaded.Blizzard_Professions = true
    loader.scripts.OnEvent(loader, "ADDON_LOADED", "Blizzard_Professions")
    professions:Hide(); professions:Show()
    Check(not F.active and not loader.events.ADDON_LOADED, "late addon resurrected a disabled focus owner")
    -- The normal adapter's painting callbacks stand in for heavy skin work;
    -- actual ApplyAll retains focus discovery independently of skin ownership.
    NS.DB.enabled, NS.DB.skins.blizzardWindows = true, true
    loaded.Blizzard_Professions, _G.ProfessionsFrame = false, nil
    NS.Adapters.ApplyAll()
    Check(loader.events.ADDON_LOADED, "handoff fixture has no pending cold catalog load")
    NS.GenericWindows.ApplyAll = function(owner)
        Check(loader.events.ADDON_LOADED, "normal skin apply dropped pending focus discovery")
        W.TrackFocus(character, owner)
        W.TrackFocus(item, owner)
        return true
    end
    NS.MacroWindow = { Start = function() end }
    for _, name in ipairs({ "DeepWindows", "SemanticHUD", "SharedChrome", "UIPanelButtons", "CommonMenus",
        "Commerce", "CharacterPanel", "InspectPanel", "SocialUISkin", "MajorWindows", "LegacyWindows",
        "CommonArt", "ForeverGroupFinder", "ForeverLegacyTree" }) do
        NS[name] = { Apply = function() return true end }
    end
    NS.Adapters.order = { "blizzardWindows" }
    _G.combat, _G.combatEdge = false, false
    local bank = Native("BankFrame", 900, 200, 425, 600)
    Check(NS.Adapters.ApplyAll() and NS.Adapters.GetStatus("blizzardWindows") == "applied",
        "normal ApplyAll did not take over after the combat reload")
    Check(F.records[bank] and F.records[bank].owners.blizzardWindows ~= nil,
        "normal catalog missed an independently Suite-owned native bag root")
    bank:Hide()
    local later = Native("ProfessionsFrame", 350, 300, 1, 658)
    later:Hide()
    loaded.Blizzard_Professions = true
    loader.scripts.OnEvent(loader, "ADDON_LOADED", "Blizzard_Professions")
    Check(F.records[later] and not loader.events.ADDON_LOADED, "normal LoD lost focus-only discovery")
    later.width = 700
    later:Show()
    Check(F.active.frame == later, "delayed native layout did not join normal focus")
    later:Hide()
    Click(character)
    Check(F.active and F.active.frame == character and Dimmed(item),
        "cold-to-normal handoff released freshly attached focus ownership")
    Click(item)
    Check(F.active.frame == item and Dimmed(character), "normal handoff lost mouse focus/MRU promotion")
    NS.DB.enabled = false
    listeners[F](nil, "adapter")
    local created = #H.frames
    for _ = 1, 100 do
        loader.scripts.OnEvent(loader, "ADDON_LOADED", "UnrelatedAddon")
    end
    Check(#H.frames == created and not driver.scripts.OnUpdate and heavy == 0,
        "disabled discovery allocated work or restarted a hidden driver")
end
print("suite_window_focus_discovery_contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@combat_focus_discovery_fixture"))()
