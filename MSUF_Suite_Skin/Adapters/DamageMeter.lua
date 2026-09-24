local _, NS = ...

-- Clean-room adapter for Blizzard's native 12.1 Damage Meter.  Class-colored
-- StatusBar fills, text, icons, clicks, dropdowns, resize behavior, Edit Mode
-- ownership, and combat-session refreshes remain Blizzard-owned.
local DamageMeterSkin = {
    owners = {},
    hookedWindows = setmetatable({}, { __mode = "k" }),
}
NS.DamageMeterSkin = DamageMeterSkin

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function OwnerState(owner)
    local state = DamageMeterSkin.owners[owner]
    if not state then
        state = {
            active = false,
            surfaces = setmetatable({}, { __mode = "k" }),
            scrollBoxes = setmetatable({}, { __mode = "k" }),
            windows = setmetatable({}, { __mode = "k" }),
        }
        DamageMeterSkin.owners[owner] = state
    end
    return state
end

local function Track(owner, target)
    local state = DamageMeterSkin.owners[owner]
    if state and target then state.surfaces[target] = true end
end

local function Attach(target, owner, spec)
    if not target or not NS.Safety.CanDecorate(target, true) then return false end
    spec = spec or {}
    spec.allowImplicitProtected = true
    local surface = NS.Surface.Attach(target, spec)
    if surface then
        Track(owner, target)
        return true
    end
    return false
end

local function CallBoolean(object, method)
    local callback = SafeField(object, method)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, object)
    return ok and value == true or nil
end

local function SkinWindowAction(button, owner, kind)
    if not button then return false end
    if NS.WindowActionSkin then
        local action, reason = NS.WindowActionSkin.SyncNativeVisual(button, owner, kind)
        if action then return true end
        if reason == "owned by another adapter"
            or reason == "state texture ownership changed" then return false end
    end
    if NS.Checkmarks then return NS.Checkmarks.TrackButton(button, owner) end
    return false
end

local function SkinMinimizeButton(window, owner, minimized)
    if type(minimized) ~= "boolean" then minimized = CallBoolean(window, "IsMinimized") end
    return SkinWindowAction(SafeField(window, "MinimizeButton"), owner,
        minimized and "maximize" or "minimize")
end

local function OnWindowMinimized(window, minimized)
    for owner, state in pairs(DamageMeterSkin.owners) do
        if state.active and state.windows[window] then
            SkinMinimizeButton(window, owner, minimized)
        end
    end
end

local function HookWindow(window)
    if not window or DamageMeterSkin.hookedWindows[window]
        or type(hooksecurefunc) ~= "function"
        or type(SafeField(window, "SetMinimized")) ~= "function" then
        return false
    end
    local ok = pcall(function()
        hooksecurefunc(window, "SetMinimized", OnWindowMinimized)
    end)
    if ok then DamageMeterSkin.hookedWindows[window] = true end
    return ok == true
end

local function SkinRow(row, owner)
    local state = DamageMeterSkin.owners[owner]
    if not state or not state.active or NS.IsCombatLocked()
        or not NS.DB.hud.damageMeterRows then
        return false
    end
    local statusBar = SafeField(row, "StatusBar")
    if not statusBar then return false end

    NS.Cosmetics.SuppressVertexAlpha(SafeField(statusBar, "Background"), owner)
    NS.Cosmetics.SuppressVertexAlpha(SafeField(statusBar, "BackgroundEdge"), owner)
    for _, region in pairs(SafeField(statusBar, "BackgroundRegions") or {}) do
        NS.Cosmetics.SuppressVertexAlpha(region, owner)
    end
    -- This plate sits behind Blizzard's class-/source-colored StatusBar fill.
    Attach(statusBar, owner, {
        role = "card", shape = "continuous", radius = 4, inset = 0, listItem = true,
    })
    return true
end

local function InitializedFrameEvent()
    return ScrollBoxListMixin and ScrollBoxListMixin.Event
        and ScrollBoxListMixin.Event.OnInitializedFrame
end

local function RegisterScrollBox(scrollBox, owner)
    local state = DamageMeterSkin.owners[owner]
    local event = InitializedFrameEvent()
    if not state or not scrollBox or not event or state.scrollBoxes[scrollBox]
        or type(SafeField(scrollBox, "RegisterCallback")) ~= "function" then
        return false
    end
    local token = {}
    local function OnInitialized(_, row)
        -- Damage rows can be recycled during combat.  Cosmetic work is
        -- optional, so do not mutate or queue from that hot path.
        SkinRow(row, owner)
    end
    local ok = pcall(scrollBox.RegisterCallback, scrollBox, event, OnInitialized, token)
    if not ok then return false end
    state.scrollBoxes[scrollBox] = token
    if type(SafeField(scrollBox, "ForEachFrame")) == "function" and not NS.IsCombatLocked() then
        pcall(scrollBox.ForEachFrame, scrollBox, function(row) SkinRow(row, owner) end)
    end
    return true
end

local function SkinSourceWindow(sourceWindow, owner)
    if not sourceWindow or not NS.DB.hud.damageMeterDetails then return end
    NS.Cosmetics.SuppressVertexAlpha(SafeField(sourceWindow, "Background"), owner)
    Attach(sourceWindow, owner, { role = "popup", radius = 8, inset = 0 })
    SkinWindowAction(SafeField(sourceWindow, "CloseButton"), owner, "close")
    RegisterScrollBox(SafeField(sourceWindow, "ScrollBox"), owner)
end

local function SkinSessionWindow(window, owner)
    if not window then return end
    local state = DamageMeterSkin.owners[owner]
    if state then state.windows[window] = true end
    HookWindow(window)
    SkinMinimizeButton(window, owner)
    local minimize = SafeField(window, "MinimizeContainer")
    if NS.DB.hud.damageMeterWindows then
        NS.Cosmetics.SuppressVertexAlpha(SafeField(window, "Header"), owner)
        NS.Cosmetics.SuppressVertexAlpha(SafeField(minimize, "Background"), owner)
        Attach(window, owner, { role = "shell", radius = 8, inset = 0 })
    end

    RegisterScrollBox(SafeField(minimize, "ScrollBox"), owner)
    SkinRow(SafeField(minimize, "LocalPlayerEntry"), owner)
    SkinSourceWindow(SafeField(minimize, "SourceWindow"), owner)
end

local function EnumerateWindows(frame, callback)
    if type(SafeField(frame, "ForEachSessionWindow")) == "function" then
        local ok = pcall(frame.ForEachSessionWindow, frame, callback)
        if ok then return end
    end
    local list = SafeField(frame, "windowDataList")
    if type(list) == "table" then
        for _, data in pairs(list) do
            callback(SafeField(data, "sessionWindow"))
        end
    end
end

function DamageMeterSkin.Apply(frame, owner)
    if not frame then return false, "missing" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not NS.Safety.CanDecorate(frame, true) then return false, "protected" end
    local state = OwnerState(owner)
    state.active = true
    EnumerateWindows(frame, function(window) SkinSessionWindow(window, owner) end)
    return true
end

function DamageMeterSkin.Disable(_, owner)
    if NS.IsCombatLocked() then return false, "combat" end
    local state = DamageMeterSkin.owners[owner]
    if not state then return true end
    state.active = false
    local event = InitializedFrameEvent()
    if event then
        for scrollBox, token in pairs(state.scrollBoxes) do
            local unregister = SafeField(scrollBox, "UnregisterCallback")
            if type(unregister) == "function" then
                pcall(unregister, scrollBox, event, token)
            end
        end
    end
    for target in pairs(state.surfaces) do
        pcall(NS.Surface.SetVisible, target, false)
    end
    if NS.WindowActionSkin then NS.WindowActionSkin.DisableOwner(owner) end
    if NS.Checkmarks then NS.Checkmarks.UntrackOwner(owner) end
    NS.Cosmetics.RestoreOwner(owner)
    DamageMeterSkin.owners[owner] = nil
    return true
end

return DamageMeterSkin
