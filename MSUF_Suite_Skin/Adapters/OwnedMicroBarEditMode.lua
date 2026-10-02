local _, NS = ...

-- MSUF Edit Mode for the owned Micro Bar (OwnedMicroBar.lua, which loads
-- after this file): the registered element with its captured state, drag
-- moves, position reset and extra controls. OwnedMicroBar hands over its
-- table, its bar frame and two placements once with Attach; until then
-- nothing registers.
local EditMode = {
    registered = false,
}
NS.OwnedMicroBarEditMode = EditMode

local Layout = NS.OwnedMicroBarLayout
local Settings = Layout.Settings
local ReadNumber = Layout.ReadNumber
local IsOwnedMode = Layout.IsOwnedMode
local MAX_BUTTONS_PER_LINE = Layout.MAX_BUTTONS_PER_LINE

local Visibility = NS.OwnedMicroBarVisibility
local ApplyVisibility = Visibility.Apply

local EDIT_OWNER, EDIT_ID = "MSUFSuite.Skin", "microBar"
local owner, bar, place, applyOwned
local editProfile, editEpoch = nil, 0

-- owner is the OwnedMicroBar table (active, suspended) and bar its frame,
-- created once. place(settings) puts the bar at its saved position;
-- applyOwned(settings) applies the settings to the menu the bar holds.
function EditMode.Attach(ownedBar, barFrame, applyPosition, applyToRoot)
    owner, bar, place, applyOwned = ownedBar, barFrame, applyPosition, applyToRoot
end

local function ProfileEpoch()
    if editProfile ~= NS.DB then
        editProfile, editEpoch = NS.DB, editEpoch + 1
    end
    return editEpoch
end

local function EditAPI()
    local api = _G.MSUF_EditModeAPI
    if type(api) == "table" and type(api.RegisterElement) == "function" then
        return api
    end
end

local function RoundTenth(value)
    if value >= 0 then return math.floor(value * 10 + 0.5) / 10 end
    return math.ceil(value * 10 - 0.5) / 10
end

local function PlaceEditPosition(state, x, y, commit)
    local settings = Settings()
    if not settings or not bar or NS.IsCombatLocked() then return false end
    if type(x) ~= "number" or type(y) ~= "number"
        or x ~= x or y ~= y or math.abs(x) > 4096 or math.abs(y) > 4096 then
        return false
    end
    if commit then
        settings.layoutPoint = state.point
        settings.layoutRelativePoint = state.relativePoint
        settings.layoutX = RoundTenth(x)
        settings.layoutY = RoundTenth(y)
        settings.positionPreset = "custom"
        return place(settings)
    end
    bar:ClearAllPoints()
    bar:SetPoint(state.point, UIParent, state.relativePoint, x, y)
    return true
end

local function EditState()
    local settings = Settings()
    if not settings then return nil end
    return {
        epoch = ProfileEpoch(),
        point = settings.layoutPoint,
        relativePoint = settings.layoutRelativePoint,
        x = settings.layoutX,
        y = settings.layoutY,
        positionPreset = settings.positionPreset,
        orientation = settings.orientation,
        buttonsPerLine = settings.buttonsPerLine,
        spacing = settings.spacing,
        scale = settings.scale,
        padding = settings.padding,
    }
end

local function ValidEditState(state)
    return type(state) == "table" and state.epoch == ProfileEpoch()
        and type(state.point) == "string" and type(state.relativePoint) == "string"
        and type(state.x) == "number" and type(state.y) == "number"
        and (state.orientation == "horizontal" or state.orientation == "vertical")
        and type(state.buttonsPerLine) == "number" and state.buttonsPerLine >= 1
        and state.buttonsPerLine <= MAX_BUTTONS_PER_LINE
        and type(state.spacing) == "number" and state.spacing >= -8 and state.spacing <= 16
        and type(state.scale) == "number" and state.scale >= 0.5 and state.scale <= 1.5
        and type(state.padding) == "number" and state.padding >= 0 and state.padding <= 16
end

-- Labels are locale keys: NS.L exists once the skin finished loading, so
-- they are resolved when the element registers (EditMode.Register).
local function EditOption(key, labelKey, minimum, maximum, step)
    return {
        id = key, labelKey = labelKey, kind = "number", min = minimum, max = maximum, step = step,
        get = function()
            local settings = Settings()
            return settings and settings[key]
        end,
        set = function(value) return NS.MicroMenuSkin.SetOption(key, value) end,
    }
end

local function OrientationToggle(orientation, labelKey)
    return {
        id = orientation, labelKey = labelKey, kind = "toggle",
        get = function()
            local settings = Settings()
            return settings and settings.orientation == orientation
        end,
        set = function(on)
            return on and NS.MicroMenuSkin.SetOption("orientation", orientation) or false
        end,
    }
end

local editControls = {
    EditOption("buttonsPerLine", "Per line", 1, MAX_BUTTONS_PER_LINE, 1),
    EditOption("spacing", "Spacing", -8, 16, 1),
    {
        id = "size", labelKey = "Size %", kind = "number", min = 50, max = 150, step = 1,
        get = function()
            local settings = Settings()
            return settings and math.floor((settings.scale or 1) * 100 + 0.5)
        end,
        set = function(value) return NS.MicroMenuSkin.SetOption("scale", value / 100) end,
    },
    EditOption("padding", "Padding", 0, 16, 1),
    OrientationToggle("vertical", "Vertical"),
    OrientationToggle("horizontal", "Horizontal"),
}

local editElement = {
    id = EDIT_ID, labelKey = "Micro Bar", groupKey = "MSUF Suite", order = 450,
    getFrame = function() return bar end,
    isEnabled = function()
        return owner.active and not owner.suspended
            and IsOwnedMode(Settings()) and NS.DB.skins.microMenu ~= false
    end,
    captureState = EditState,
    restoreState = function(state)
        if not ValidEditState(state) or not PlaceEditPosition(state, state.x, state.y, true) then
            return false
        end
        local settings = Settings()
        settings.positionPreset = state.positionPreset
        settings.orientation = state.orientation
        settings.buttonsPerLine = state.buttonsPerLine
        settings.spacing = state.spacing
        settings.scale = state.scale
        settings.padding = state.padding
        local refreshed
        if NS.MicroMenuSkin.active then
            refreshed = NS.MicroMenuSkin.RefreshActive()
        else
            refreshed = applyOwned(settings)
        end
        return refreshed ~= false and refreshed ~= nil
    end,
    movePosition = function(request)
        local state = request and request.state
        if not ValidEditState(state) then return false end
        local scale = ReadNumber(bar, "GetScale", 1)
        if scale <= 0 then scale = 1 end
        local x = state.x + (tonumber(request.deltaX) or 0) / scale
        local y = state.y + (tonumber(request.deltaY) or 0) / scale
        return PlaceEditPosition(state, x, y, request.phase == "commit")
    end,
    resetPosition = function()
        local defaults = NS.Defaults.icons.microMenu
        local settings = Settings()
        if not settings or NS.IsCombatLocked() then return false end
        settings.layoutPoint = defaults.layoutPoint
        settings.layoutRelativePoint = defaults.layoutRelativePoint
        settings.layoutX, settings.layoutY = defaults.layoutX, defaults.layoutY
        settings.positionPreset = defaults.positionPreset
        return place(settings)
    end,
    onSessionChanged = function(enabled)
        Visibility.SetEditSession(enabled)
        if owner.active and not owner.suspended then
            ApplyVisibility(Settings())
        end
    end,
    extraControls = editControls,
    openSettings = function()
        local open = _G.MSUF2_Open
        if type(open) ~= "function" then return false end
        open("suite_skin")
        return true
    end,
}

local function LocalizeEditElement()
    local L = NS.L
    editElement.label, editElement.group = L[editElement.labelKey], L[editElement.groupKey]
    for index = 1, #editControls do
        local control = editControls[index]
        control.label = L[control.labelKey]
    end
end

-- Registers the element once the bar exists and MSUF Edit Mode is loaded.
function EditMode.Register()
    if EditMode.registered or not bar then return EditMode.registered end
    local api = EditAPI()
    if not api then return false end
    LocalizeEditElement()
    EditMode.registered = api.RegisterElement(EDIT_OWNER, editElement) == true
    return EditMode.registered
end

function EditMode.RefreshOwner()
    local api = EditAPI()
    if EditMode.registered and api and api.RefreshOwner then api.RefreshOwner(EDIT_OWNER) end
end

function EditMode.Enter()
    local api = EditAPI()
    return api and api.EnterEditMode and api.EnterEditMode(EDIT_OWNER, EDIT_ID) == true
end
