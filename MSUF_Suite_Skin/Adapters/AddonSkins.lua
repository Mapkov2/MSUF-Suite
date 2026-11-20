local _, NS = ...

local Skins = { definitions = NS.AddonSkinDefinitions, byID = {}, byAddon = {}, byLabel = {}, byTitle = {}, cooperative = {},
    roots = setmetatable({}, { __mode = "k" }) }
NS.AddonSkins = Skins
local Safety, Visuals = NS.Safety, NS.AddonSkinVisuals
local mode = { role = "shell", allowImplicitProtected = false, maxDepth = 6, maxNodes = 480 }
local restedMode = { role = "shell", allowImplicitProtected = true, maxDepth = 6, maxNodes = 480 }
local profilerMode = { role = "shell", allowImplicitProtected = false, maxDepth = 6, maxNodes = 480,
    registerDynamicRows = false }
local events = CreateFrame("Frame")
local active

for index = 1, #Skins.definitions do
    local entry = Skins.definitions[index]
    Skins.byID[entry.id] = entry
    Skins.byLabel[entry.label:lower():gsub("[^%w]", "")] = entry.id
    for _, alias in ipairs(entry.aliases or {}) do Skins.byLabel[alias:lower():gsub("[^%w]", "")] = entry.id end
    for _, addon in ipairs(entry.addons) do Skins.byAddon[addon:lower()] = entry.id end
end

function Skins.IsEnabled(id)
    local settings = NS.DB and NS.DB.addonSkins
    return NS.DB and NS.DB.enabled == true and settings and settings.enabled == true
        and (id == nil or settings[id] ~= false)
end

function Skins.ResolveApp(name)
    if not Safety.Public(name) or type(name) ~= "string" then return nil end
    local lower = (name:match("^([^/]+)") or name):lower()
    return Skins.byAddon[lower] or Skins.byTitle[lower] or (Skins.byID[name] and name)
        or Skins.byLabel[lower:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[^%w]", "")]
end

local function Release(state)
    if state.id == "addonProfiler" then NS.AddonProfilerSkin.Release(state.owner) end
    if state.id == "spoken" and not NS.SpokenSkin.CanTouch(state.frame) then
        state.releasePending = true
        NS.SpokenSkin.Defer(state.frame, state.paint)
        return
    end
    if state.id == "restedXP" then NS.RestedXPSkin.Invalidate() end
    NS.GenericWindows.Disable(state.owner)
    Visuals.Release(state.owner)
    state.applied, state.releasePending = false, nil
end

local function Paint(state)
    state.queued = false
    if state.id == "spoken" and not NS.SpokenSkin.CanTouch(state.frame) then
        NS.SpokenSkin.Defer(state.frame, state.paint)
        return
    end
    if Skins.cooperative[state.id] then
        if state.releasePending then Release(state) end
        return
    end
    if not Skins.IsEnabled(state.id) then Release(state) return end
    if NS.IsCombatLocked() then return end
    if not Visuals.Safe(state.frame, state.id == "restedXP") then state.blocked = true return end
    if Safety.Read(state.frame, "IsVisible") ~= true then return end
    state.blocked = false
    state.releasePending = nil
    if state.id == "spoken" and NS.SpokenSkin.Direct(state.frame) then
        state.applied = NS.SpokenSkin.PaintDirect(state.frame, state.owner)
        if state.applied then state.dirty = false end
        return
    end
    local appearance = state.id == "spoken" and NS.SpokenSkin.Mode(state.frame, mode)
        or state.id == "restedXP" and restedMode or state.id == "addonProfiler" and profilerMode or mode
    Visuals.Close(state.frame, state.owner, state.id == "restedXP")
    state.applied = NS.GenericWindows.ApplyFrame(state.frame, state.owner, appearance) == true
    if state.applied then
        Skins.ObserveSecondaryWindows(state.frame, state.id)
        if state.id == "spoken" then NS.SpokenSkin.Paint(state.frame, state.owner)
        else
            Visuals.Tree(state.frame, state.owner, nil, state.id == "restedXP")
            if state.id == "restedXP" then NS.RestedXPSkin.Paint(state.frame, state.owner) end
            if state.id == "addonProfiler" then NS.AddonProfilerSkin.Paint(state.frame, state.owner) end
            if state.id == "enhanceQoL" or type(Safety.Field(state.frame, "_LibSettingsDesignerState")) == "table" then
                NS.AddonSkinDesigner.Paint(state.frame, state.owner, state.id)
            end
        end
    end
    if state.applied then state.dirty = false end
end

local function Queue(state, invalidate)
    if invalidate then state.dirty = true end
    if state.queued or state.applied and not state.dirty then return end
    state.queued = true
    NS.Registry.QueueJob(state.paint)
end

local function Shown(frame)
    local state = Skins.roots[frame]
    if state and (not state.applied or state.dirty) and Skins.IsEnabled(state.id) and not Skins.cooperative[state.id] then
        Queue(state)
    end
end

function Skins.Watch(frame, id)
    if not Skins.byID[id] or not Visuals.Safe(frame, id == "restedXP" and not NS.IsCombatLocked()) then return false end
    if Skins.cooperative[id] then return false end
    if id == "restedXP" then Skins.ObserveRestedXP() end
    if NS.AddonMenus.AssignAddon(frame, id) then return true end
    local state = Skins.roots[frame]
    if state and state.id ~= id then return false end
    if not state then
        if id == "spoken" and not NS.SpokenSkin.CanTouch(frame) then
            NS.SpokenSkin.Defer(frame, function() Skins.Watch(frame, id) end)
            return false
        end
        state = { frame = frame, id = id, dirty = true,
            owner = id == "restedXP" and "addon-skin:restedXP" or "addon-skin:" .. id .. ":" .. tostring(frame) }
        state.paint = function() Paint(state) end
        Skins.roots[frame] = state
        frame:HookScript("OnShow", Shown)
    end
    Queue(state)
    return true
end

function Skins.RefreshFrame(frame)
    local state = Skins.roots[frame]
    if state then Queue(state, true) end
end

NS.PublicAPI.OnRegistrationChanged = function(name, registered)
    local id = Skins.ResolveApp(name)
    if not id then return end
    Skins.cooperative[id] = registered == true or nil
    local function Transfer()
        for _, state in pairs(Skins.roots) do
            if state.id == id then
                if Skins.cooperative[id] then Release(state) else Queue(state) end
            end
        end
        NS.AddonMenus.ReleaseAddon(id)
        NS.AddonSettings.ReleaseAddon(id)
    end
    if NS.IsCombatLocked() then NS.CombatGate.RunOrDefer("addon-skin-transfer:" .. id, Transfer)
    else Transfer() end
end

function Skins.GetStatus(id)
    local entry = Skins.byID[id]
    if not entry then return "waiting" end
    local present, loaded = false, false
    for _, addon in ipairs(entry.addons) do
        present = NS.Client.HasAddOn(addon) or present
        loaded = NS.Client.IsAddOnLoaded(addon) or loaded
    end
    if not present then return "missing" end
    if not Skins.IsEnabled(id) then return "disabled" end
    if not loaded then return "waiting" end
    if NS.AddonSettings.IsApplied(id) then return "applied" end
    for _, state in pairs(Skins.roots) do
        if state.id == id and state.applied then return "applied" end
    end
    return "ready"
end

local function NamedRoots(entry)
    for index = 1, #entry.roots do
        local frame = rawget(_G, entry.roots[index])
        if frame then Skins.Watch(frame, entry.id) end
    end
    for _, path in ipairs(entry.paths or {}) do
        local value = rawget(_G, path[1])
        for index = 2, #path do value = Safety.Field(value, path[index]) end
        if value then Skins.Watch(value, entry.id) end
    end
end

function Skins.CheckNamedRoots(id)
    local entry = Skins.byID[id]
    if not entry or not Skins.IsEnabled(id) or Skins.cooperative[id] then return end
    if not entry.namedJob then entry.namedJob = function()
        if Skins.IsEnabled(id) and not Skins.cooperative[id] then NamedRoots(entry) end
    end end
    NS.Registry.QueueJob(entry.namedJob)
end

function Skins.RefreshAddon(id)
    local entry = Skins.byID[id]
    if entry and Skins.IsEnabled(id) then
        if not entry.refreshJob then entry.refreshJob = function()
            if id == "restedXP" then NS.RestedXPSkin.Invalidate() end
            NamedRoots(entry)
            for _, state in pairs(Skins.roots) do if state.id == id then Queue(state, true) end end
        end end
        NS.Registry.QueueJob(entry.refreshJob)
    end
end

local function Repaint()
    if Skins.IsEnabled("restedXP") then NS.RestedXPSkin.Invalidate() end
    for _, state in pairs(Skins.roots) do Queue(state, true) end
end

local function Refresh()
    if not NS.DB then return end
    local enabled = Skins.IsEnabled() == true
    if active ~= enabled then
        if enabled then events:RegisterEvent("ADDON_LOADED") else events:UnregisterEvent("ADDON_LOADED") end
    end
    local release = active
    active = enabled
    if not enabled then
        if release then Repaint() end
        return
    end
    Repaint()
    for index = 1, #Skins.definitions do
        local entry = Skins.definitions[index]
        if Skins.IsEnabled(entry.id) then NamedRoots(entry) end
    end
    Skins.InstallTriggers()
    if Skins.IsEnabled("spoken") then NS.SpokenSkin.Install() end
    Skins.Discover()
end

function Skins.SetOption(key, value)
    if NS.IsCombatLocked() then return false, "combat" end
    if NS.Defaults.addonSkins[key] == nil then return false, "invalid-option" end
    NS.DB.addonSkins[key] = value == true
    NS.Registry.NotifyListeners("addonSkins", key)
    return true
end

local function NotifyStartup()
    if Skins.IsEnabled() then NS.Registry.NotifyListeners("addonSkins", "enabled") end
end

NS.Registry.AddListener(Skins, function(_, domain, key)
    if domain == "addonSkins" and key == "registered" then return end
    local enabled = Skins.IsEnabled() == true
    if enabled ~= active then
        NS.Registry.QueueJob(Refresh)
    elseif not enabled then
        return
    elseif domain == "addonSkins" or domain == "profile" or domain == "adapter" then
        NS.Registry.QueueJob(Refresh)
    elseif domain == "theme" or domain == "color" or domain == "appearance"
        or domain == "geometry" or domain == "typography" then
        NS.Registry.QueueJob(Repaint)
    end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, addon)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent(event)
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        if active ~= false or Skins.IsEnabled() then NS.Registry.QueueJob(Refresh) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent(event)
        if Skins.IsEnabled() then
            -- Let world-entry callbacks finish before notifying every addon skin owner.
            -- The startup layout can flush registry jobs during the dispatch.
            C_Timer.After(0, function()
                if Skins.IsEnabled() then NS.Registry.QueueJob(NotifyStartup) end
            end)
        end
    elseif addon == NS.addonName or (active and Skins.ResolveApp(addon)) then
        NS.Registry.QueueJob(Refresh)
    end
end)
