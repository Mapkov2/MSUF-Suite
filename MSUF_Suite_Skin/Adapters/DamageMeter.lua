local _, NS = ...

-- Clean-room adapter for Blizzard's native 12.1 Damage Meter. Class-colored
-- StatusBar fills, text, icons, clicks, dropdowns, resize behavior, Edit Mode
-- ownership, and combat-session refreshes remain Blizzard-owned.
local DamageMeterSkin = {
    owners = {},
    hookedWindows = setmetatable({}, { __mode = "k" }),
}
NS.DamageMeterSkin = DamageMeterSkin

local Field = NS.Safety.Field
local HasMethod = NS.Safety.HasMethod
local Dispatch = NS.Safety.Dispatch
local Kit = NS.AdapterKit

local ROW_SPEC = {
    role = "card", shape = "continuous", radius = 4, inset = 0, listItem = true,
    allowImplicitProtected = true,
}
local SOURCE_WINDOW_SPEC = { role = "popup", radius = 8, inset = 0, allowImplicitProtected = true }
local SESSION_WINDOW_SPEC = { role = "shell", radius = 8, inset = 0, allowImplicitProtected = true }

local function Attach(state, target, spec)
    if not target or not NS.Safety.CanDecorate(target, true) then return false end
    if not NS.Surface.Attach(target, spec) then return false end
    state.surfaces[target] = true
    return true
end

local function SkinRow(row, owner)
    local state = DamageMeterSkin.owners[owner]
    if not state or not state.active or NS.IsCombatLocked()
        or not NS.DB.hud.damageMeterRows then
        return false
    end
    local statusBar = Field(row, "StatusBar")
    if not statusBar then return false end

    NS.Cosmetics.SuppressVertexAlpha(Field(statusBar, "Background"), owner)
    NS.Cosmetics.SuppressVertexAlpha(Field(statusBar, "BackgroundEdge"), owner)
    local regions = Field(statusBar, "BackgroundRegions")
    if type(regions) == "table" then
        for _, region in pairs(regions) do
            NS.Cosmetics.SuppressVertexAlpha(region, owner)
        end
    end
    -- This plate sits behind Blizzard's class-/source-colored StatusBar fill.
    Attach(state, statusBar, ROW_SPEC)
    return true
end

local function OwnerState(owner)
    local state = DamageMeterSkin.owners[owner]
    if not state then
        state = {
            owner = owner,
            active = false,
            surfaces = setmetatable({}, { __mode = "k" }),
            scrollBoxes = setmetatable({}, { __mode = "k" }),
            windows = setmetatable({}, { __mode = "k" }),
        }
        state.skinRow = function(row) SkinRow(row, owner) end
        DamageMeterSkin.owners[owner] = state
    end
    return state
end

local function SkinWindowAction(button, owner, kind)
    if not button then return false end
    local action, reason = NS.WindowActionSkin.SyncNativeVisual(button, owner, kind)
    if action then return true end
    if reason == "owned by another adapter"
        or reason == "state texture ownership changed" then
        return false
    end
    return NS.Checkmarks.TrackButton(button, owner)
end

local function SkinMinimizeButton(window, owner, minimized)
    if type(minimized) ~= "boolean" then
        minimized = NS.Safety.Call(window, "IsMinimized") == true
    end
    return SkinWindowAction(Field(window, "MinimizeButton"), owner,
        minimized and "maximize" or "minimize")
end

local function OnWindowMinimized(window, minimized)
    for owner, state in pairs(DamageMeterSkin.owners) do
        if state.active and state.windows[window] then
            SkinMinimizeButton(window, owner, minimized)
        end
    end
end

-- Runs inside Blizzard's SetMinimized, so the repaint is its own error boundary.
local function OnWindowMinimizedHook(window, minimized)
    Dispatch(OnWindowMinimized, window, minimized)
end

-- SetMinimized is an instance method of each exact session window.
local function HookWindow(window)
    if DamageMeterSkin.hookedWindows[window]
        or not HasMethod(window, "SetMinimized") then
        return
    end
    hooksecurefunc(window, "SetMinimized", OnWindowMinimizedHook)
    DamageMeterSkin.hookedWindows[window] = true
end

-- CallbackRegistry passes the registration owner first: the owner state.
local function OnRowInitialized(state, row)
    -- Damage rows can be recycled during combat. Cosmetic work is optional,
    -- so SkinRow neither mutates nor queues from that hot path.
    SkinRow(row, state.owner)
end

local function RegisterScrollBox(state, scrollBox)
    if not scrollBox or state.scrollBoxes[scrollBox] then return false end
    local event = Kit.RegisterRowCallback(scrollBox, OnRowInitialized, state)
    if not event then return false end
    state.scrollBoxes[scrollBox] = event
    -- ForEachRow waits for the list view Blizzard builds on initialization.
    if not NS.IsCombatLocked() then Kit.ForEachRow(scrollBox, state.skinRow) end
    return true
end

local function SkinSourceWindow(state, sourceWindow)
    if not sourceWindow or not NS.DB.hud.damageMeterDetails then return end
    local owner = state.owner
    NS.Cosmetics.SuppressVertexAlpha(Field(sourceWindow, "Background"), owner)
    Attach(state, sourceWindow, SOURCE_WINDOW_SPEC)
    SkinWindowAction(Field(sourceWindow, "CloseButton"), owner, "close")
    RegisterScrollBox(state, Field(sourceWindow, "ScrollBox"))
end

local function SkinSessionWindow(state, window)
    if not window then return end
    local owner = state.owner
    state.windows[window] = true
    HookWindow(window)
    SkinMinimizeButton(window, owner)
    local minimize = Field(window, "MinimizeContainer")
    if NS.DB.hud.damageMeterWindows then
        NS.Cosmetics.SuppressVertexAlpha(Field(window, "Header"), owner)
        NS.Cosmetics.SuppressVertexAlpha(Field(minimize, "Background"), owner)
        Attach(state, window, SESSION_WINDOW_SPEC)
    end

    RegisterScrollBox(state, Field(minimize, "ScrollBox"))
    SkinRow(Field(minimize, "LocalPlayerEntry"), owner)
    SkinSourceWindow(state, Field(minimize, "SourceWindow"))
end

local function SkinAllWindows(frame, state)
    if HasMethod(frame, "ForEachSessionWindow") then
        frame:ForEachSessionWindow(function(window) SkinSessionWindow(state, window) end)
        return
    end
    local list = Field(frame, "windowDataList")
    if type(list) == "table" then
        for _, data in pairs(list) do
            SkinSessionWindow(state, Field(data, "sessionWindow"))
        end
    end
end

function DamageMeterSkin.Apply(frame, owner)
    if not frame then return false, "missing" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not NS.Safety.CanDecorate(frame, true) then return false, "protected" end
    local state = OwnerState(owner)
    state.active = true
    SkinAllWindows(frame, state)
    return true
end

function DamageMeterSkin.Disable(_, owner)
    if NS.IsCombatLocked() then return false, "combat" end
    local state = DamageMeterSkin.owners[owner]
    if not state then return true end
    state.active = false
    for scrollBox, event in pairs(state.scrollBoxes) do
        Kit.UnregisterRowCallback(scrollBox, event, state)
    end
    for target in pairs(state.surfaces) do
        NS.Surface.SetVisible(target, false)
    end
    NS.WindowActionSkin.DisableOwner(owner)
    NS.Checkmarks.UntrackOwner(owner)
    NS.Cosmetics.RestoreOwner(owner)
    DamageMeterSkin.owners[owner] = nil
    return true
end

return DamageMeterSkin
