local _, NS = ...

-- Each window keeps its existing restore button and its own open/close path.
-- Docking only changes the button's placement; it never becomes a secure parent.
local Taskbar = {}
NS.MinimizedWindows = Taskbar

local visible, docked = {}, {}
local frame
local BUTTON_WIDTH, BUTTON_HEIGHT, GAP = 154, 26, 4
local SCREEN_PADDING, BOTTOM_OFFSET = 8, 64

local function Undock(button)
    local points = docked[button]
    if not points then return end
    docked[button] = nil
    button:SetWidth(BUTTON_WIDTH)
    button:ClearAllPoints()
    for _, point in ipairs(points) do button:SetPoint(unpack(point, 1, 5)) end
end

local function Dock(button, width, x, y)
    if not docked[button] then
        local points = {}
        for index = 1, button:GetNumPoints() do points[index] = { button:GetPoint(index) } end
        docked[button] = points
    end
    button:SetWidth(width)
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", frame, "BOTTOM", x, y)
end

local function Layout()
    local available = UIParent:GetWidth() - 2 * SCREEN_PADDING
    local width = math.min(BUTTON_WIDTH, math.max(1, available))
    local columns = math.max(1, math.floor((available + GAP) / (width + GAP)))
    for index, button in ipairs(visible) do
        local row, column = math.floor((index - 1) / columns), (index - 1) % columns
        local count = math.min(columns, #visible - row * columns)
        local left = -(count * (width + GAP) - GAP) / 2
        Dock(button, width, left + column * (width + GAP), row * (BUTTON_HEIGHT + GAP))
    end
end

function Taskbar.Refresh()
    local config = #visible > 0 and NS.Suite.Config("dataTexts")
    if not config or config.showMinimizedWindows ~= true then
        for _, button in ipairs(visible) do Undock(button) end
        if frame then frame:UnregisterAllEvents() end
        return
    end
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(1, 1)
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, BOTTOM_OFFSET)
        frame:SetScript("OnEvent", Layout)
    end
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    frame:RegisterEvent("UI_SCALE_CHANGED")
    Layout()
end

local function Shown(button)
    visible[#visible + 1] = button
    Taskbar.Refresh()
end

local function Hidden(button)
    for index, item in ipairs(visible) do
        if item == button then
            table.remove(visible, index)
            break
        end
    end
    Undock(button)
    Taskbar.Refresh()
end

function Taskbar.Track(button)
    button:HookScript("OnShow", Shown)
    button:HookScript("OnHide", Hidden)
end

function Taskbar.IsDocked(button)
    return docked[button] ~= nil
end
