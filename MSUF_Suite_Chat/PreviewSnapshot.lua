local _, P = ...
local S = P.Suite
local C = P.Chat

local function Store(parts, key, value)
    if parts[key] == value then return false end
    parts[key] = value
    return true
end

local function Font(parts, region, prefix)
    local path, size, flags = region:GetFont()
    if not S.PublicText(path) or not S.Finite(size) or not S.Public(flags) or type(flags) ~= "string" then return false end
    local fonts = parts.fonts
    local changed = Store(fonts, prefix, path)
    changed = Store(fonts, prefix .. "Size", size) or changed
    return Store(fonts, prefix .. "Flags", flags) or changed
end

local function Tabs(parts, dock, frame)
    local changed = false
    parts.nativeTabs = parts.nativeTabs or {}
    for index = 1, 2 do
        local nativeFrame = dock and dock.DOCKED_CHAT_FRAMES and dock.DOCKED_CHAT_FRAMES[index]
        nativeFrame = nativeFrame or index == 1 and frame
        local name = nativeFrame and nativeFrame:GetName()
        local tab = S.PublicText(name) and _G[name .. "Tab"]
        if tab then
            local width, height = tab:GetWidth(), tab:GetHeight()
            if S.Finite(width) and width > 0 and S.Finite(height) and height > 0 then
                local info = parts.nativeTabs[index] or {}
                parts.nativeTabs[index] = info
                changed = Store(info, "width", width) or changed
                changed = Store(info, "height", height) or changed
            end
        end
    end
    return changed
end

local function Input(parts, frame)
    local input = frame.editBox
    if not input then return false end
    local changed, width, height = false, input:GetWidth(), input:GetHeight()
    if S.Finite(width) and width > 0 then changed = Store(parts, "nativeInputWidth", width) or changed end
    if S.Finite(height) and height > 0 then changed = Store(parts, "nativeInputHeight", height) or changed end
    local point, relative, relativePoint, x, y = input:GetPoint(1)
    local context = C.M.context
    local record = context and context.points[input]
    if record and record.before[1] then point, relative, relativePoint, x, y = unpack(record.before[1]) end
    if S.PublicText(point) and S.Public(relative) and S.PublicText(relativePoint)
        and relative == frame and S.Finite(x) and S.Finite(y) then
        changed = Store(parts, "nativeInputPoint", point) or changed
        changed = Store(parts, "nativeInputRelativePoint", relativePoint) or changed
        changed = Store(parts, "nativeInputX", x) or changed
        changed = Store(parts, "nativeInputY", y) or changed
    end
    if input.header then changed = Font(parts, input.header, "input") or changed end
    return changed
end

-- The native windows own their unlocked dimensions and default font metrics.
-- Read those values; the menu never moves or restyles a native frame here.
function S.ChatPreviewSnapshot(parts)
    local dock = _G.GENERAL_CHAT_DOCK
    local frame = dock and dock.selected or _G.SELECTED_DOCK_FRAME or _G.ChatFrame1
    if not frame then return false end
    local changed = Store(parts, "source", frame)
    local width, height = frame:GetWidth(), frame:GetHeight()
    if S.Finite(width) and width > 0 then changed = Store(parts, "nativeWidth", width) or changed end
    if S.Finite(height) and height > 0 then changed = Store(parts, "nativeHeight", height) or changed end
    changed = Font(parts, frame, "message") or changed
    local mode, spacing = frame:GetInsertMode(), frame:GetSpacing()
    if S.Public(mode) then changed = Store(parts, "insertTop", mode == _G.SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP) or changed end
    if S.Finite(spacing) then changed = Store(parts, "messageSpacing", spacing) or changed end
    changed = Tabs(parts, dock, frame) or changed
    changed = Input(parts, frame) or changed
    local r, g, b, a = frame:GetShadowColor()
    local x, y = frame:GetShadowOffset()
    if S.Finite(r) and S.Finite(g) and S.Finite(b) and S.Finite(a) and S.Finite(x) and S.Finite(y) then
        local fonts = parts.fonts
        changed = Store(fonts, "shadowR", r) or changed
        changed = Store(fonts, "shadowG", g) or changed
        changed = Store(fonts, "shadowB", b) or changed
        changed = Store(fonts, "shadowAlpha", a) or changed
        changed = Store(fonts, "shadowX", x) or changed
        changed = Store(fonts, "shadowY", y) or changed
    end
    local name = frame:GetName()
    if S.PublicText(name) then
        local tab = _G[name .. "Tab"]
        if tab then changed = Font(parts, tab.Text, "tab") or changed end
    end
    if changed then parts.nativeEpoch = (parts.nativeEpoch or 0) + 1 end
    return changed
end

local listeners = setmetatable({}, { __mode = "k" })
local watched = setmetatable({}, { __mode = "k" })
local hooked
local function NativeChanged()
    for owner, callback in pairs(listeners) do
        if owner:IsVisible() then callback() end
    end
end

-- Only visible previews subscribe; native scripts remain Blizzard-owned.
function S.ChatWatchPreview(owner, callback, frame)
    listeners[owner] = callback
    if callback and not hooked then
        hooked = true
        hooksecurefunc("FCF_SetChatWindowFontSize", NativeChanged)
        hooksecurefunc("FCFDock_SelectWindow", NativeChanged)
        hooksecurefunc("FCFDock_UpdateTabs", NativeChanged)
    end
    if callback and frame and not watched[frame] then
        watched[frame] = true
        frame:HookScript("OnSizeChanged", NativeChanged)
    end
end
