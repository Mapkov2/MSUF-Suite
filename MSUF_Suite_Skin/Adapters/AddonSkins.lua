local _, NS = ...

local Skins = { definitions = NS.AddonSkinDefinitions, byID = {}, byAddon = {}, byLabel = {}, byTitle = {}, cooperative = {},
    roots = setmetatable({}, { __mode = "k" }), byHost = {}, failures = {} }
NS.AddonSkins = Skins
local Safety, Visuals = NS.Safety, NS.AddonSkinVisuals
local mode = { role = "shell", allowImplicitProtected = false, maxDepth = 6, maxNodes = 480 }
local restedMode = { role = "shell", allowImplicitProtected = true, maxDepth = 6, maxNodes = 480 }
local profilerMode = { role = "shell", allowImplicitProtected = false, maxDepth = 6, maxNodes = 480,
    registerDynamicRows = false }
local embeddedMode = { rootSurface = false, preserveRootArt = true, maxDepth = 4, maxNodes = 180 }
local softerModes = setmetatable({}, { __mode = "k" })
local events = CreateFrame("Frame")
local active

for index = 1, #Skins.definitions do
    local entry = Skins.definitions[index]
    Skins.byID[entry.id] = entry
    Skins.byLabel[entry.label:lower():gsub("[^%w]", "")] = entry.id
    for _, alias in ipairs(entry.aliases or {}) do Skins.byLabel[alias:lower():gsub("[^%w]", "")] = entry.id end
    for _, addon in ipairs(entry.addons) do Skins.byAddon[addon:lower()] = entry.id end
    for _, host in ipairs(entry.hosts or {}) do
        local entries = Skins.byHost[host] or {}
        entries[#entries + 1] = entry
        Skins.byHost[host] = entries
    end
end

function Skins.IsEnabled(id)
    local settings = NS.DB and NS.DB.addonSkins
    return NS.DB and NS.DB.enabled == true and settings and settings.enabled == true
        and (id == nil or settings[id] ~= false and not Skins.failures[id])
end

function Skins.ResolveApp(name)
    if not Safety.Public(name) or type(name) ~= "string" then return nil end
    local lower = (name:match("^([^/]+)") or name):lower()
    return Skins.byAddon[lower] or Skins.byTitle[lower] or (Skins.byID[name] and name)
        or Skins.byLabel[lower:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[^%w]", "")]
end

local function Release(state)
    if state.id == "questie" and NS.AddonSkinQuestie then NS.AddonSkinQuestie.Release(state.frame) end
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

function Skins.GetLook(id)
    local opts = NS.DB and NS.DB.addonSkins
    return opts and opts.looks and opts.looks[id]
end

function Skins.WindowMode(id, original)
    local look = Skins.GetLook(id)
    if not look or not look.softerWindow then return original end
    local mode = softerModes[original]
    if not mode then
        mode = NS.CopyValue(original)
        mode.fillAlphaScale = 0.65
        softerModes[original] = mode
    end
    return mode
end

local function Paint(state)
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
    if Visuals.UseLook then Visuals.UseLook(state.owner, Skins.GetLook(state.id)) end
    if state.embedded or state.chrome then
        local applied = state.embedded and NS.GenericWindows.ApplyDescendant(state.frame, state.owner, embeddedMode)
        if state.chrome then applied = Visuals.ApplyDiscovered(state.frame, state.owner) end
        state.applied, state.dirty = applied == true, applied ~= true
        return
    end
    if state.id == "questie" and NS.AddonSkinQuestie then
        local painted = NS.AddonSkinQuestie.Paint(state.frame, state.owner)
        if painted ~= nil then
            state.applied, state.dirty = painted, not painted
            return
        end
    end
    if state.id == "spoken" and NS.SpokenSkin.Direct(state.frame) then
        state.applied = NS.SpokenSkin.PaintDirect(state.frame, state.owner)
        if state.applied then state.dirty = false end
        return
    end
    local appearance = state.id == "spoken" and NS.SpokenSkin.Mode(state.frame, mode)
        or state.id == "restedXP" and restedMode or state.id == "addonProfiler" and profilerMode or mode
    Visuals.Close(state.frame, state.owner, state.id == "restedXP")
    state.applied = NS.GenericWindows.ApplyFrame(state.frame, state.owner, Skins.WindowMode(state.id, appearance)) == true
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

local function Apply(state)
    Paint(state)
    return true
end

function Skins.RunTask(id, phase, callback, ...)
    if Skins.failures[id] then return false end
    if Safety.Dispatch(callback, ...) then return true end
    -- The client reports the original Lua error. Stop this adapter from
    -- retrying on every show or repaint; release all its owned visuals.
    Skins.failures[id] = phase
    for _, owned in pairs(Skins.roots) do
        if owned.id == id then Safety.Dispatch(Release, owned) end
    end
    if NS.AddonMenus.ReleaseAddon then Safety.Dispatch(NS.AddonMenus.ReleaseAddon, id) end
    Safety.Dispatch(NS.AddonSettings.ReleaseAddon, id)
    return false
end

local function RunPaint(state)
    state.queued = false
    if not state.applied or state.dirty then Skins.RunTask(state.id, "window", Apply, state) end
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

function Skins.Watch(frame, id, embedded, chrome)
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
        state = { frame = frame, id = id, dirty = true, embedded = embedded, chrome = chrome,
            owner = id == "restedXP" and "addon-skin:restedXP" or "addon-skin:" .. id .. ":" .. tostring(frame) }
        state.paint = function() RunPaint(state) end
        Skins.roots[frame] = state
        frame:HookScript("OnShow", Shown)
    end
    if embedded then state.embedded = true end
    if chrome then state.chrome = true end
    Queue(state)
    return true
end

function Skins.PaintOnOpen(frame, id)
    if NS.IsCombatLocked() or not Skins.IsEnabled(id) or not Skins.Watch(frame, id) then return end
    local state = Skins.roots[frame]
    if state then RunPaint(state) end
end

function Skins.RefreshFrame(frame)
    local state = Skins.roots[frame]
    if state then Queue(state, true) end
end

NS.PublicAPI.OnRegistrationChanged = function(name, registered)
    if Skins.TransferDiscovered then Skins.TransferDiscovered(name, registered) end
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
    local present, loaded, available, version = false, false, false, nil
    for _, addon in ipairs(entry.addons) do
        if NS.Client.HasAddOn(addon) then
            present = true
            loaded = NS.Client.IsAddOnLoaded(addon) or loaded
            available = not NS.Client.IsDisabledHere or not NS.Client.IsDisabledHere(addon) or available
            version = version or NS.Client.AddOnVersion and NS.Client.AddOnVersion(addon)
        end
    end
    if not present then return "missing" end
    if not loaded and not available then return "characterDisabled", version end
    local opts = NS.DB.addonSkins
    if not NS.DB.enabled or not opts.enabled or opts[id] == false then return "disabled", version end
    if Skins.cooperative[id] then return "registered", version end
    if Skins.failures[id] then return "error", version, Skins.failures[id] end
    if not loaded then return "waiting", version end
    local applied = NS.AddonSettings.IsApplied(id) or NS.AddonMenus.IsApplied and NS.AddonMenus.IsApplied(id)
    local pending = false
    for _, state in pairs(Skins.roots) do
        if state.id == id then
            applied = applied or state.applied
            pending = pending or state.blocked or not state.applied
        end
    end
    if applied then return pending and "partial" or "applied", version end
    return pending and "pending" or "ready", version
end

local function NamedRoots(entry)
    for index = 1, #entry.roots do
        local name = entry.roots[index]
        local frame = rawget(_G, name)
        if frame then Skins.Watch(frame, entry.id, nil, entry.chrome and entry.chrome[name]) end
    end
    for _, name in ipairs(entry.embedded or {}) do
        local frame = rawget(_G, name)
        if frame then Skins.Watch(frame, entry.id, true) end
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

local function RefreshTarget(entry)
    local id = entry.id
    if Skins.IsEnabled(id) and not Skins.cooperative[id] then
        Skins.InstallTriggers(id)
        if id == "spoken" then NS.SpokenSkin.Install() end
        NamedRoots(entry)
        Skins.Discover(id)
    else
        NS.AddonSettings.ReleaseAddon(id)
        if NS.AddonMenus.ReleaseAddon then NS.AddonMenus.ReleaseAddon(id) end
    end
    if id == "restedXP" then NS.RestedXPSkin.Invalidate() end
    for _, state in pairs(Skins.roots) do
        if state.id == id then Queue(state, true) end
    end
end

local function QueueTarget(entry)
    if not entry.targetJob then entry.targetJob = function() RefreshTarget(entry) end end
    NS.Registry.QueueJob(entry.targetJob)
end

function Skins.SetLook(id, key, enabled)
    if NS.IsCombatLocked() or not Skins.byID[id] then return false end
    if id == "restedXP" or id == "spoken" or (key ~= "nativeFont" and key ~= "softerWindow" and key ~= "reset") then
        return false
    end
    local looks = NS.DB.addonSkins.looks
    if key == "reset" then
        looks[id] = nil
    else
        local look = looks[id] or {}
        look[key] = enabled == true or nil
        looks[id] = next(look) and look or nil
    end
    for _, state in pairs(Skins.roots) do
        if state.id == id then Safety.Dispatch(Release, state) end
    end
    QueueTarget(Skins.byID[id])
    return true
end

function Skins.SetKnownAddons(enabled)
    if NS.IsCombatLocked() then return false end
    local opts = NS.DB.addonSkins
    for _, entry in ipairs(Skins.definitions) do opts[entry.id] = enabled == true end
    NS.Registry.NotifyListeners("addonSkins", "bulk")
    return true
end

function Skins.RetryAddon(id)
    if NS.IsCombatLocked() then return false, "combat" end
    local entry = Skins.byID[id]
    if not entry then return false, "invalid-addon" end
    Skins.failures[id] = nil
    QueueTarget(entry)
    return true
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
    if Skins.ReconcileDiscovered then Skins.ReconcileDiscovered() end
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
    if type(NS.Defaults.addonSkins[key]) ~= "boolean" then return false, "invalid-option" end
    value = value == true
    NS.DB.addonSkins[key] = value
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
    elseif domain == "addonSkins" and Skins.byID[key] then
        QueueTarget(Skins.byID[key])
    elseif domain == "addonSkins" and (key == "aceGUI" or key == "discovered") then
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
    elseif addon == NS.addonName then
        NS.Registry.QueueJob(Refresh)
    elseif active then
        local id = Skins.ResolveApp(addon)
        if id and Skins.IsEnabled(id) then QueueTarget(Skins.byID[id]) end
        local host = Safety.Public(addon) and Skins.byHost[addon]
        if host then
            for _, entry in ipairs(host) do
                if Skins.IsEnabled(entry.id) then QueueTarget(entry) end
            end
        end
    end
end)
