local _, NS = ...

-- Popups are occluders, never independent focus targets. Their own native
-- show/hide signals keep this set small without polling cached menu history.
local Popups = {}
NS.WindowFocusPopups = Popups
local Safety, Geometry = NS.Safety, NS.WindowFocusGeometry
local records, visible = setmetatable({}, { __mode = "k" }), {}
local openMenus, shown = {}, {}
local ranks = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local Changed = function() end
local active = false
local descriptions = setmetatable({}, { __mode = "k" })
local menuManager
local EnsureMenuHooks
local names = { "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
    "StackSplitFrame", "DropDownList1", "DropDownList2", "DropDownList3" }

local function ReadBounds(frame, record)
    local valid = Geometry.Read(frame, record)
    visible[frame] = valid and record or nil
    if valid then record.empty = nil return end
    local width, height = Safety.Read(frame, "GetWidth"), Safety.Read(frame, "GetHeight")
    record.empty = type(width) == "number" and width <= 0 or type(height) == "number" and height <= 0
end

local function Shown(frame)
    local record = records[frame]
    if active and record and Safety.Read(frame, "IsVisible") == true then
        shown[frame] = record
        ReadBounds(frame, record)
        Changed()
    end
end

local function Hidden(frame)
    openMenus[frame] = nil
    if records[frame] then records[frame].observing = nil end
    if shown[frame] then
        shown[frame], visible[frame] = nil, nil
        Changed()
    end
end

local function Moved(frame)
    if shown[frame] then Changed() end
end

local function Acquired(menu)
    if not Safety.Public(menu) or not menu or Safety.IsForbidden(menu) then return end
    local record = records[menu]
    if not record then
        record = {}
        records[menu] = record
    end
    record.modern, record.lease = true, nil
    if not record.observing then
        -- Acquired precedes native positioning and Show. Pool reset removes
        -- scripts, so every lease renews these shared callbacks.
        menu:HookScript("OnShow", Shown)
        menu:HookScript("OnSizeChanged", Moved)
        menu:HookScript("OnHide", Hidden)
        record.observing = true
    end
    openMenus[menu] = record
    Shown(menu)
end

local function Opened(manager, _, description)
    if not Safety.Public(description) then return end
    if description and not descriptions[description] then
        descriptions[description] = true
        description:AddMenuAcquiredCallback(Acquired)
        description:AddMenuReleasedCallback(Hidden)
    end
    Acquired(manager:GetOpenMenu())
end

EnsureMenuHooks = function()
    if menuManager then return end
    local menu = Safety.Field(_G, "Menu")
    if not Safety.HasMethod(menu, "GetManager") then return end
    local manager = menu.GetManager()
    if not Safety.HasMethod(manager, "OpenMenu") or not Safety.HasMethod(manager, "OpenContextMenu") then return end
    menuManager = manager
    hooksecurefunc(manager, "OpenMenu", Opened)
    hooksecurefunc(manager, "OpenContextMenu", Opened)
end

function Popups.Track(frame)
    if not active or not frame or Safety.IsForbidden(frame) or not Safety.HasMethod(frame, "HookScript") then return end
    if records[frame] and records[frame].modern then Acquired(frame) return end
    if not records[frame] then
        records[frame] = {}
        frame:HookScript("OnShow", Shown)
        frame:HookScript("OnHide", Hidden)
        frame:HookScript("OnSizeChanged", Moved)
        if Safety.HasMethod(frame, "SetPoint") then hooksecurefunc(frame, "SetPoint", Moved) end
        if Safety.HasMethod(frame, "SetScale") then hooksecurefunc(frame, "SetScale", Moved) end
    end
    Shown(frame)
end

function Popups.Discover()
    if not active then return end
    EnsureMenuHooks()
    if menuManager then Acquired(menuManager:GetOpenMenu()) end
    for frame in pairs(openMenus) do Shown(frame) end
    for index = 1, #names do Popups.Track(Safety.Field(_G, names[index])) end
    Popups.Track(NS.FocusVeil.menu)
end

local function CouldCover(state, frame)
    local rank = ranks[Safety.Read(frame, "GetFrameStrata")]
    local level = Safety.Read(frame, "GetFrameLevel")
    return not rank or type(level) ~= "number" or state.paintRank > rank
        or state.paintRank == rank and state.paintLevel >= level
end

function Popups.Subtract(state)
    for frame, rect in pairs(shown) do
        local visibility = Safety.Read(frame, "IsVisible")
        if visibility == false then
            Hidden(frame)
        elseif visibility ~= true then
            if CouldCover(state, frame) then return false end
        else
            ReadBounds(frame, rect)
            if visible[frame] then
                if not Geometry.Subtract(state, rect) then return false end
            elseif not rect.empty and CouldCover(state, frame) then
                -- Unknown shown bounds must still protect a popup from a higher
                -- veil. Lower windows remain safe beneath the native popup strata.
                return false
            end
        end
    end
    return true
end

local function MenuOpened(lease, _, menu)
    if Safety.IsCompositorManaged(menu) then Acquired(menu) else Popups.Track(menu) end
    if records[menu] then records[menu].lease = lease end
end

local function MenuClosed(lease, menu)
    if menu and records[menu] and records[menu].lease == lease then Hidden(menu) end
end

function Popups.SetActive(value)
    active = value == true
    if not active then
        for frame in pairs(shown) do shown[frame], visible[frame] = nil, nil end
    end
end

function Popups.Initialize(changed)
    Changed = changed
    EnsureMenuHooks()
    if Safety.HasMethod(_G, "StaticPopup_Show") then hooksecurefunc("StaticPopup_Show", Popups.Discover) end
    NS.FocusVeil.SetWindowFocusProvider(MenuOpened, MenuClosed)
end
