local _, NS = ...

-- Cooperative AceGUI/AceConfig boundaries, including widgets already open
-- when the skin loads. No CreateFrame/global-frame enumeration or callback
-- replacement; pooled widgets release all skin and motion owner leases.
local Menus = { widgets = setmetatable({}, { __mode = "k" }), libraries = {} }
NS.AddonMenus = Menus
local Safety = NS.Safety
local roots = { Frame = true, Window = true }
local mode = { role = "shell", allowImplicitProtected = false }

local function Enabled()
    return NS.DB and NS.DB.enabled and NS.DB.skins.blizzardWindows ~= false
end

local function Release(state)
    NS.GenericWindows.Disable(state.owner)
    NS.MenuMotion.Release(state.owner)
end

local function Paint(state)
    state.queued = false
    local frame = Safety.Field(state.widget, "frame")
    if not state.root then return end
    if not Enabled() then Release(state) return end
    if not Safety.CanCreateRegions(frame) or Safety.GetProtection(frame)
        or Safety.Read(frame, "IsVisible") ~= true or NS.Motion.combat or NS.IsCombatLocked() then return end
    NS.GenericWindows.ApplyFrame(frame, state.owner, mode)
    local content = Safety.Field(state.widget, "content")
    if content then NS.ContentMotion.Watch(content, state.owner) end
end

local function Schedule(state)
    if state.queued then return end
    state.queued = true
    NS.Registry.QueueJob(state.paint)
end

local function Shown(frame)
    local state = Menus.frames[frame]
    if state and state.root then Schedule(state) end
end
Menus.frames = setmetatable({}, { __mode = "k" })

local function Selected(widget, token)
    local content = Safety.Field(widget, "content")
    local owner = content and NS.MenuMotion.OwnerFor(content)
    if owner and NS.ContentMotion.Play(content, owner, token) then
        local state = Menus.widgets[widget]
        if state then state.contentOwner = owner end
    end
end

local function Acquired(widget)
    local state = Menus.widgets[widget]
    if state and state.root then Schedule(state) end
end

local function ChildAdded(widget)
    for _ = 1, 16 do
        local state = Menus.widgets[widget]
        if state and state.root then Schedule(state) return end
        widget = Safety.Field(widget, "parent")
        if not widget then return end
    end
end

local function Registered(_, widget, force)
    local frame = Safety.Field(widget, "frame")
    if not Safety.CanCreateRegions(frame) or Safety.GetProtection(frame) then return end
    local state = Menus.widgets[widget]
    if not state then
        state = { widget = widget, owner = {} }
        state.paint = function() Paint(state) end
        Menus.widgets[widget], Menus.frames[frame] = state, state
        if Safety.HasMethod(widget, "OnAcquire") then hooksecurefunc(widget, "OnAcquire", Acquired) end
        if Safety.HasMethod(widget, "SelectTab") then hooksecurefunc(widget, "SelectTab", Selected) end
        if Safety.HasMethod(widget, "AddChild") then hooksecurefunc(widget, "AddChild", ChildAdded) end
        frame:HookScript("OnShow", Shown)
    end
    state.root = state.root or force == true or roots[Safety.Field(widget, "type")] == true
    if state.root then Schedule(state) end
end

local function Released(_, widget)
    local state = Menus.widgets[widget]
    if state and state.contentOwner then
        NS.ContentMotion.Unwatch(state.contentOwner, Safety.Field(widget, "content"))
        state.contentOwner = nil
    end
    if state and state.root then Release(state) end
end

local function Opened(dialog, name, container)
    local widget = container or Safety.Field(Safety.Field(dialog, "OpenFrames"), name)
    if widget then Registered(dialog, widget, true) end
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

local function Refresh()
    for _, state in pairs(Menus.widgets) do
        if state.root then Schedule(state) end
    end
end
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", Install)
NS.Registry.AddListener(Menus, Refresh)
Install()
