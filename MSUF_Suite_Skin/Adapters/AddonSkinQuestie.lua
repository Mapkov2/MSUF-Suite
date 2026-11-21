local _, NS = ...

-- Questie v12.11.1 (Forever TOC): OptionsWindow makes the popup before its
-- first Show. OptionsControls.Refresh is also called for each lazily-built
-- control when the tab's coroutine constructs it.
local Questie = {}
NS.AddonSkinQuestie = Questie
local Skins, Safety, Visuals = NS.AddonSkins, NS.Safety, NS.AddonSkinVisuals
local rootName = "QuestieStandaloneSettings"
local ROOT_MODE = { role = "shell", maxDepth = 2, maxNodes = 40 }
local ROW_MODE = { rootSurface = false, maxDepth = 2, maxNodes = 16, registerDynamicRows = false }
local MAX_ROWS_PER_FRAME = 16
local roots = setmetatable({}, { __mode = "k" })
local hooks = setmetatable({}, { __mode = "k" })
local pending, queued = {}, false
local rowOwners = setmetatable({}, { __mode = "k" })

local function Enabled()
    return Skins.IsEnabled("questie") and not Skins.cooperative.questie
end

local function Root()
    local frame = rawget(_G, rootName)
    if Visuals.Safe(frame) then return frame end
end

local function Under(frame, root)
    for _ = 1, 9 do
        if frame == root then return true end
        frame = Safety.Read(frame, "GetParent")
        if not frame then return false end
    end
    return false
end

local function StyleControl(control, state)
    NS.GenericWindows.ApplyDescendant(control, state.owner, ROW_MODE)
    Visuals.Label(Safety.Field(control, "titleFrame"), state.owner, nil, true)
    Visuals.Label(Safety.Field(control, "descriptionFrame"), state.owner, nil, true)
    rowOwners[control] = state
    return true
end

local function Drain()
    queued = false
    if not Enabled() then pending = {} return end
    if NS.IsCombatLocked() then
        queued = true
        NS.Registry.QueueJob(Drain)
        return
    end
    for _ = 1, MAX_ROWS_PER_FRAME do
        local control, state = next(pending)
        if not control then return end
        pending[control] = nil
        if roots[state.frame] == state and Under(control, state.frame) and Visuals.Safe(control) then
            if not Skins.RunTask("questie", "settings", StyleControl, control, state) then
                pending = {}
                return
            end
        end
    end
    if next(pending) then
        queued = true
        C_Timer.After(0, Drain)
    end
end

local function Queue(control, state)
    if rowOwners[control] == state or pending[control] == state then return end
    pending[control] = state
    if not queued then
        queued = true
        NS.Registry.QueueJob(Drain)
    end
end

local function ControlRefreshed(control)
    if not Enabled() or not Safety.Public(control) or not control then return end
    local current = rowOwners[control] or pending[control]
    if current and roots[current.frame] == current then return end
    local root = Root()
    local state = root and roots[root]
    if not state then return end
    if Under(control, root) then Queue(control, state) end
end

local function TabSelected(tab, selected)
    if not Enabled() or NS.IsCombatLocked() or not Safety.Public(selected) or not selected then return end
    local root = Root()
    local state = root and roots[root]
    if not state or not Visuals.Safe(tab) or not Under(tab, root) then return end
    Visuals.Tint(Safety.Field(tab, "Selected"), state.owner, "accent")
end

local function Opened()
    if not Enabled() or NS.IsCombatLocked() then return end
    local root = Root()
    if root then Skins.PaintOnOpen(root, "questie") end
end

local function Hook(module, key, callback)
    local method = Safety.Field(module, key)
    if type(method) ~= "function" or hooks[module] == method then return end
    hooksecurefunc(module, key, Safety.Isolated(callback))
    hooks[module] = Safety.Field(module, key)
end

function Questie.Install()
    if not NS.Client.IsAddOnLoaded("Questie") then return end
    local loader = rawget(_G, "QuestieLoader")
    local version = NS.Client.AddOnVersion and NS.Client.AddOnVersion("Questie")
    if version and not version:match("^v?12%.11%.") then return end
    if not Safety.HasMethod(loader, "ImportModule") then return end
    Hook(Safety.Call(loader, "ImportModule", "QuestieOptionsEngine"), "ShowFrame", Opened)
    Hook(Safety.Call(loader, "ImportModule", "QuestieOptionsControls"), "Refresh", ControlRefreshed)
    Hook(Safety.Call(loader, "ImportModule", "QuestieOptionsWindow"), "SetSideTabSelected", TabSelected)
end

local function ActiveCanvases(state, ...)
    for index = 1, select("#", ...) do
        local canvas = select(index, ...)
        if Safety.Read(canvas, "IsVisible") == true then
            local controls = Safety.Field(canvas, "controls")
            if type(controls) == "table" then
                for i = 1, math.min(#controls, 256) do
                    local control = controls[i]
                    if Safety.Public(control) and control then Queue(control, state) end
                end
            end
        end
    end
end

function Questie.Paint(frame, owner)
    if frame ~= Root() then return nil end
    local state = roots[frame]
    local look = Skins.GetLook("questie")
    local font = NS.LabelStyle.GetConfiguredPath and NS.LabelStyle.GetConfiguredPath()
    if not state or state.look ~= look or state.font ~= font then
        state = { frame = frame, owner = owner, look = look, font = font }
        roots[frame] = state
    end
    Visuals.Close(frame, owner)
    if not NS.GenericWindows.ApplyFrame(frame, owner, Skins.WindowMode("questie", ROOT_MODE)) then return false end
    local container = Safety.Field(frame, "canvasContainer")
    ActiveCanvases(state, Safety.Call(container, "GetChildren"))
    return true
end

function Questie.Release(frame)
    roots[frame] = nil
end
