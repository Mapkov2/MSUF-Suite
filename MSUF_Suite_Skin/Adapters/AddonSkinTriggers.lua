local _, NS = ...

-- Narrow posthooks on supported addon launchers. A lazy anonymous window is
-- discovered after its opening callback, including keyboard/slash launches.
local Skins, Safety = NS.AddonSkins, NS.Safety
local hooked = setmetatable({}, { __mode = "k" })
local callbacks = {}
local secondaryRoots, secondaryButtons = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local brokerNames = {}
local designerOwners = setmetatable({}, { __mode = "k" })
for _, entry in ipairs(Skins.definitions) do
    local id = entry.id
    -- The profiler constructs both named windows in InitUI. Its launchers
    -- also control data collection, which never requires skin discovery.
    if id ~= "addonProfiler" then
        brokerNames[entry.label:lower():gsub("[^%w]", "")] = id
        for _, addon in ipairs(entry.addons) do brokerNames[addon:lower():gsub("[^%w]", "")] = id end
        callbacks[id] = function()
            if Skins.IsEnabled(id) then Skins.RefreshAddon(id) Skins.Discover(id) end
        end
    end
end

local function Hook(target, key, callback)
    if not Safety.HasMethod(target, key) then return end
    local methods = hooked[target]
    if not methods then methods = {} hooked[target] = methods end
    if methods[key] == target[key] then return end
    hooksecurefunc(target, key, callback)
    methods[key] = target[key]
end

local function DesignerOpened(library, app)
    if not Safety.Public(app) then return end
    local name = type(app) == "table" and Safety.Field(app, "id") or app
    if not Safety.Public(name) or type(name) ~= "string" then return end
    local id = Skins.ResolveApp(name) or designerOwners[library]
    if not id or not Skins.IsEnabled(id) or Skins.cooperative[id] then return end
    local frame = Safety.Field(_G, name .. "ConfigCenterFrame")
    if Safety.Public(frame) and frame then
        if Skins.Watch(frame, id) then Skins.RefreshFrame(frame) end
    end
end

local function ObserveDesigner(addon, id)
    local namespace = Safety.Field(_G, addon)
    local library = Safety.Field(Safety.Field(namespace, "LibSettingsDesigner"), "UI")
    if not Safety.HasMethod(library, "Open") then return end
    designerOwners[library] = id
    Hook(library, "Open", DesignerOpened)
    local internal = Safety.Field(library, "_Internal")
    for _, key in ipairs({ "applyFrameBackground", "applySidebarShellBackground", "applyContentShellBackground" }) do
        Hook(internal, key, NS.AddonSkinDesigner.NativeBackgroundChanged)
    end
end

local function SecondaryClick(button)
    local id = secondaryButtons[button]
    if id then Skins.CheckNamedRoots(id) end
end

local function ActionRows(frame, id, remaining, depth)
    if remaining <= 0 or depth > 6 or not NS.AddonSkinVisuals.Safe(frame) then return remaining end
    remaining = remaining - 1
    local button = Safety.Field(frame, "button")
    if NS.AddonSkinVisuals.Safe(button) and Safety.Read(button, "GetObjectType") == "Button" and not secondaryButtons[button] then
        secondaryButtons[button] = id
        button:HookScript("OnClick", SecondaryClick)
    end
    for _, child in ipairs({ Safety.Call(frame, "GetChildren") }) do
        if remaining <= 0 then break end
        remaining = ActionRows(child, id, remaining, depth + 1)
    end
    return remaining
end

function Skins.ObserveSecondaryWindows(frame, id)
    -- DoesItDie's local Advanced > View handler lazily creates LearnedTicks.
    -- Its actionRow.button controls are constructed synchronously in this area.
    if id ~= "doesItDie" then return end
    local area = Safety.Field(frame, "settingsArea")
    if not area or secondaryRoots[frame] == area then return end
    secondaryRoots[frame] = area
    ActionRows(area, id, 320, 0)
end

local function Broker(library, name)
    if not Safety.Public(name) or type(name) ~= "string" then return end
    local id = brokerNames[name:lower():gsub("[^%w]", "")]
    if not id or not Skins.IsEnabled(id) then return end
    local object = Safety.Call(library, "GetDataObjectByName", name)
    Hook(object, "OnClick", callbacks[id])
end

local function InstallBroker()
    local stub = rawget(_G, "LibStub")
    local library = Safety.Call(stub, "GetLibrary", "LibDataBroker-1.1", true)
    if not library then return end
    Hook(library, "NewDataObject", Broker)
    if not Safety.HasMethod(library, "DataObjectIterator") then return end
    local count = 0
    for name in library:DataObjectIterator() do
        count = count + 1
        if count > 256 then break end
        Broker(library, name)
    end
end

local function RestedChanged()
    if Skins.IsEnabled("restedXP") then Skins.RefreshAddon("restedXP") end
end

function Skins.ObserveRestedXP()
    if not Skins.IsEnabled("restedXP") then return end
    Hook(rawget(_G, "RXPFrame"), "UpdateVisuals", RestedChanged)
    local window = rawget(_G, "RXPV2GuideWindow")
    Hook(window, "UpdateTheme", RestedChanged)
    Hook(window, "UpdateSubTheme", RestedChanged)
end

local function ProfilerPinned()
    if not Skins.IsEnabled("addonProfiler") then return end
    local frame = Safety.Field(rawget(_G, "NumyAddonProfiler"), "PinContainer")
    if frame and Skins.Watch(frame, "addonProfiler") then Skins.RefreshFrame(frame) end
end

local function ProfilerBuilt()
    if not Skins.IsEnabled("addonProfiler") then return end
    if NS.IsCombatLocked() then NS.Registry.QueueJob(ProfilerBuilt) return end
    local addon = rawget(_G, "NumyAddonProfiler")
    Hook(Safety.Field(addon, "PinContainer"), "PinAddon", ProfilerPinned)
    Skins.CheckNamedRoots("addonProfiler")
end

local function ObserveProfiler()
    if not Skins.IsEnabled("addonProfiler") then return end
    local addon = rawget(_G, "NumyAddonProfiler")
    Hook(addon, "InitUI", ProfilerBuilt)
    -- Enabling the skin after InitUI adopts existing roots in the same refresh.
    Hook(Safety.Field(addon, "PinContainer"), "PinAddon", ProfilerPinned)
end

function Skins.InstallTriggers()
    for _, entry in ipairs(Skins.definitions) do
        if Skins.IsEnabled(entry.id) then
            local callback = callbacks[entry.id]
            if callback then
                for _, key in ipairs(entry.slash or {}) do Hook(SlashCmdList, key, callback) end
            end
            for _, addon in ipairs(entry.addons) do
                if NS.Client.HasAddOn(addon) then
                    local title = C_AddOns.GetAddOnMetadata(addon, "Title")
                    if Safety.Public(title) and type(title) == "string" then Skins.byTitle[title:lower()] = entry.id end
                    if callback then
                        ObserveDesigner(addon, entry.id)
                        local key = C_AddOns.GetAddOnMetadata(addon, "AddonCompartmentFunc")
                        if Safety.Public(key) and type(key) == "string" then Hook(_G, key, callback) end
                    end
                end
            end
        end
    end
    InstallBroker()
    Skins.ObserveRestedXP()
    ObserveProfiler()
end
