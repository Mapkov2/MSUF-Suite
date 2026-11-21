local _, NS = ...

-- Cooperative AceGUI/AceConfig boundaries, including widgets already open
-- when the skin loads. No CreateFrame/global-frame enumeration or callback
-- replacement; pooled widgets release all skin and motion owner leases.
local Menus = { widgets = setmetatable({}, { __mode = "k" }), libraries = {} }
NS.AddonMenus = Menus
local Safety = NS.Safety
local roots = { Frame = true, Window = true }
local paintedRoots = setmetatable({}, { __mode = "k" })
local mode = { role = "shell", allowImplicitProtected = false, maxDepth = 0, maxNodes = 0, registerDynamicRows = false }

local function Enabled(state)
    return NS.AddonSkins and NS.AddonSkins.IsEnabled("aceGUI")
        and (not state or not state.addonID or NS.AddonSkins.IsEnabled(state.addonID))
        and (not state or not state.addonID or not NS.AddonSkins.cooperative[state.addonID])
end

local function ReleaseWidget(state)
    if not state.hasWidgetArt then return end
    NS.AceWidgets.Release(state.widget, state.owner)
    state.hasWidgetArt = nil
end

local function Release(state)
    if not paintedRoots[state] then return end
    NS.GenericWindows.Disable(state.owner)
    NS.MenuMotion.Release(state.owner)
    for widget in pairs(state.members or {}) do
        local member = Menus.widgets[widget]
        if member and member.rootState == state then
            ReleaseWidget(member)
            member.rootState = nil
        end
        state.members[widget] = nil
    end
    state.applied = false
    paintedRoots[state] = nil
end

local Registered, Schedule
local function PaintWidget(widget, root, budget, depth)
    if budget <= 0 or depth > 12 then return budget end
    local state = Menus.widgets[widget]
    if not state then Registered(nil, widget) state = Menus.widgets[widget] end
    if not state or state.released then return budget - 1 end
    if state.rootState and state.rootState ~= root then state.rootState.members[widget] = nil end
    state.rootState = root
    root.members[widget] = true
    state.hasWidgetArt = true
    NS.AceWidgets.Apply(widget, state.owner)
    local children = Safety.Field(widget, "children") or Safety.Field(widget, "items")
    if type(children) == "table" then
        for index = 1, #children do
            if budget <= 1 then break end
            budget = PaintWidget(children[index], root, budget - 1, depth + 1)
        end
    end
    local pullout = Safety.Field(widget, "pullout")
    if pullout and pullout ~= widget and budget > 1 then budget = PaintWidget(pullout, root, budget - 1, depth + 1) end
    return budget
end

local function Paint(state)
    state.queued = false
    if not state.root or state.released then return end
    if not Enabled() then Release(state) return end
    if state.pendingApp then
        state.addonID = NS.AddonSkins.ResolveApp(state.pendingApp)
        state.pendingApp = nil
    end
    local frame = Safety.Field(state.widget, "frame")
    state.addonID = state.addonID or NS.AddonSkins.Origin(frame)
    if not Enabled(state) then Release(state) return end
    if not Safety.CanCreateRegions(frame) or Safety.GetProtection(frame)
        or Safety.Read(frame, "IsVisible") ~= true or NS.Motion.combat or NS.IsCombatLocked() then return end
    -- An interrupted first paint may already have acquired a visual lease.
    paintedRoots[state] = true
    NS.GenericWindows.ApplyFrame(frame, state.owner, mode)
    state.members = state.members or setmetatable({}, { __mode = "k" })
    PaintWidget(state.widget, state, 512, 0)
    local content = Safety.Field(state.widget, "content")
    if content then NS.ContentMotion.Watch(content, state.owner) end
    state.applied, state.dirty = true, false
end

Schedule = function(state, invalidate)
    if state.released then return end
    if not paintedRoots[state] and NS.AddonSkins and NS.DB and not Enabled(state) then return end
    if invalidate ~= false then state.dirty = true end
    if state.queued or state.applied and not state.dirty then return end
    state.queued = true
    NS.Registry.QueueJob(state.paint)
end

local function Shown(frame)
    local state = Menus.frames[frame]
    if state and (state.root or state.rootState) then Schedule(state.rootState or state, false) end
end
Menus.frames = setmetatable({}, { __mode = "k" })

local function Selected(widget, token)
    local root = Menus.widgets[widget]
    if root and root.rootState then Schedule(root.rootState) end
    local content = Safety.Field(widget, "content")
    local owner = content and NS.MenuMotion.OwnerFor(content)
    if owner and NS.ContentMotion.Play(content, owner, token) then
        local state = Menus.widgets[widget]
        if state then state.contentOwner = owner end
    end
end

local function Acquired(widget)
    local state = Menus.widgets[widget]
    if state then
        -- Some widgets call OnAcquire again while live. A pool release or
        -- adoption by a different root owns the previous membership cleanup.
        state.released, state.addonID, state.pendingApp = false, nil, nil
    end
    if not NS.AddonSkins or not NS.AddonSkins.IsEnabled() then return end
    local kind = Safety.Field(widget, "type")
    if Safety.Public(kind) and type(kind) == "string" and kind:find("^RXPV2") then
        NS.RestedXPSkin.Acquired(widget)
        return
    end
    if state and state.root then Schedule(state) end
    if state and state.externalAddon then NS.AddonSkins.RefreshAddon(state.externalAddon) end
end

local function ChildAdded(widget)
    if not NS.AddonSkins or not NS.AddonSkins.IsEnabled() then return end
    local kind = Safety.Field(widget, "type")
    if Safety.Public(kind) and type(kind) == "string" and kind:find("^RXPV2") then NS.RestedXPSkin.Acquired(widget) return end
    for _ = 1, 16 do
        local state = Menus.widgets[widget]
        if state and state.externalAddon then NS.AddonSkins.RefreshAddon(state.externalAddon) return end
        if state and state.root then Schedule(state) return end
        widget = Safety.Field(widget, "parent")
        if not widget then return end
    end
end

Registered = function(_, widget, force)
    local frame = Safety.Field(widget, "frame")
    local kind = Safety.Field(widget, "type")
    local rested = Safety.Public(kind) and type(kind) == "string" and kind:find("^RXPV2") ~= nil
    if rested then
        if not Safety.Public(frame) or not frame or Safety.IsForbidden(frame) or Safety.IsCompositorManaged(frame) then return end
        local _, explicit = Safety.GetProtection(frame)
        if explicit then return end
    elseif not Safety.CanCreateRegions(frame) or Safety.GetProtection(frame) then return end
    local state = Menus.widgets[widget]
    if not state then
        state = { widget = widget, owner = {} }
        state.paint = function() Paint(state) end
        Menus.widgets[widget], Menus.frames[frame] = state, state
        if Safety.HasMethod(widget, "OnAcquire") then hooksecurefunc(widget, "OnAcquire", Acquired) end
        if Safety.HasMethod(widget, "SelectTab") then hooksecurefunc(widget, "SelectTab", Selected) end
        if Safety.HasMethod(widget, "AddChild") then hooksecurefunc(widget, "AddChild", ChildAdded) end
        for _, key in ipairs({ "AddItem", "SetTabs", "RefreshTree" }) do
            if Safety.HasMethod(widget, key) then hooksecurefunc(widget, key, ChildAdded) end
        end
        if not rested then frame:HookScript("OnShow", Shown) end
    end
    state.root = state.root or force == true or roots[Safety.Field(widget, "type")] == true
    if state.root then Schedule(state) end
end

local function Released(_, widget)
    local state = Menus.widgets[widget]
    if state then
        state.released = true
        ReleaseWidget(state)
        if state.rootState and state.rootState ~= state then state.rootState.members[widget] = nil end
        state.rootState = nil
    end
    if state and state.contentOwner then
        NS.ContentMotion.Unwatch(state.contentOwner, Safety.Field(widget, "content"))
        state.contentOwner = nil
    end
    if state and state.root then Release(state) end
end

local function Opened(dialog, name, container)
    if not Safety.Public(name) or not Safety.Public(container) then return end
    local widget = type(container) == "table" and container or Safety.Field(Safety.Field(dialog, "OpenFrames"), name)
    if widget then
        Registered(dialog, widget, true)
        local state = Menus.widgets[widget]
        if state then
            state.pendingApp = not NS.AddonSkins and name or nil
            state.addonID = NS.AddonSkins and NS.AddonSkins.ResolveApp(name)
            Schedule(state)
        end
    end
end

function Menus.AssignAddon(frame, id)
    local state = Menus.frames[frame]
    if not state then return false end
    if not state.root then state.externalAddon = id return false end
    state.addonID = id
    Schedule(state)
    return true
end

function Menus.ReleaseAddon(id)
    for _, state in pairs(Menus.widgets) do
        if state.root and state.addonID == id then
            Release(state)
            if not NS.AddonSkins.cooperative[id] then Schedule(state) end
        end
    end
end

local function Library(stub, name)
    return Safety.Call(stub, "GetLibrary", name, true)
end

local function InstallHook(library, key, callback)
    if not Safety.HasMethod(library, key) then return end
    local hooks = Menus.libraries[library]
    if not hooks then hooks = {} Menus.libraries[library] = hooks end
    local method = Safety.Field(library, key)
    if hooks[key] == method then return end
    hooksecurefunc(library, key, callback)
    hooks[key] = Safety.Field(library, key)
    return true
end

local function Install()
    local stub = rawget(_G, "LibStub")
    local gui, dialog = Library(stub, "AceGUI-3.0"), Library(stub, "AceConfigDialog-3.0")
    if gui then
        InstallHook(gui, "RegisterAsWidget", Registered)
        InstallHook(gui, "RegisterAsContainer", Registered)
        InstallHook(gui, "Release", Released)
    end
    if dialog and InstallHook(dialog, "Open", Opened) then
        local open = Safety.Field(dialog, "OpenFrames")
        if type(open) == "table" then
            local count = 0
            for name in pairs(open) do
                if count >= 64 then break end
                count = count + 1
                Opened(dialog, name)
            end
        end
    end
end

local function Refresh(_, domain, key)
    if domain ~= "addonSkins" and domain ~= "profile" and domain ~= "adapter" and domain ~= "theme"
        and domain ~= "color" and domain ~= "appearance" and domain ~= "geometry" and domain ~= "typography" then return end
    if not Enabled() then
        for state in pairs(paintedRoots) do Schedule(state) end
        return
    end
    if domain == "addonSkins" and key == "discovered" then return end
    local id = domain == "addonSkins" and NS.AddonSkins.byID[key] and key
    for _, state in pairs(Menus.widgets) do
        if state.root and (not id or state.addonID == id) then Schedule(state) end
    end
end
function Menus.IsApplied(id)
    for state in pairs(paintedRoots) do
        if state.addonID == id and state.applied then return true end
    end
    return false
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", Install)
NS.Registry.AddListener(Menus, Refresh)
Install()
