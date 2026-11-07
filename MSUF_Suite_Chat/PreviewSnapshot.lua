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
    local context = C.M.context
    local tuples = context and context.tuples and context.tuples[region]
    local record = tuples and tuples.SetFont
    if record and path == record.applied[1] and flags == record.applied[3] then
        path, flags = record.before[1], record.before[3]
        if size == record.applied[2] then size = record.before[2] end
    end
    local fonts = parts.fonts or parts
    local changed = Store(fonts, prefix, path)
    changed = Store(fonts, prefix .. "Size", size) or changed
    return Store(fonts, prefix .. "Flags", flags) or changed
end

local function OwnedPoint(region)
    local context = C.M.context
    local record = context and context.points[region]
    if not record then return end
    local point, relative, relativePoint, x, y = region:GetPoint(1)
    if S.Public(point) and S.Public(relative) and S.Public(relativePoint) and S.Finite(x) and S.Finite(y)
        and region:GetNumPoints() == 1 and point == record.point and relative == record.relative
        and relativePoint == record.relativePoint and x == record.x and y == record.y then return record end
end

local function Dock(parts, dock, frame, rootScale)
    local left, bottom, scale = dock:GetLeft(), dock:GetBottom(), dock:GetEffectiveScale()
    local frameLeft, frameTop, frameScale = frame:GetLeft(), frame:GetTop(), frame:GetEffectiveScale()
    if not S.Finite(left) or not S.Finite(bottom) or not S.Finite(scale) or scale <= 0
        or not S.Finite(frameLeft) or not S.Finite(frameTop) or not S.Finite(frameScale)
        or not S.Finite(rootScale) or rootScale <= 0 then return false end
    local x, y = left - frameLeft * frameScale / scale, bottom - frameTop * frameScale / scale
    local record = OwnedPoint(dock)
    if record and record.before[1] then
        x, y = x + record.before[1][4] - record.x, y + record.before[1][5] - record.y
    end
    local changed = Store(parts, "dockX", x)
    local width, height = dock:GetWidth(), dock:GetHeight()
    if S.Finite(width) and width > 0 then changed = Store(parts, "dockWidth", width) or changed end
    if S.Finite(height) and height > 0 then changed = Store(parts, "dockHeight", height) or changed end
    changed = Store(parts, "dockY", y) or changed
    return Store(parts, "dockScale", scale / rootScale) or changed
end

local function TabMetrics(info, tab, dock)
    local changed = false
    local r, g, b, a = tab.Text:GetTextColor()
    if S.Finite(r) and S.Finite(g) and S.Finite(b) and S.Finite(a) then
        changed = Store(info, "r", r)
        changed = Store(info, "g", g) or changed
        changed = Store(info, "b", b) or changed
        changed = Store(info, "a", a) or changed
    end
    local x, y = tab.Text:GetCenter()
    local tx, ty = tab:GetCenter()
    if S.Finite(x) and S.Finite(y) and S.Finite(tx) and S.Finite(ty) then
        changed = Store(info, "textX", x - tx) or changed
        changed = Store(info, "textY", y - ty) or changed
    end
    local left, bottom, scale = tab:GetLeft(), tab:GetBottom(), tab:GetEffectiveScale()
    local dx, dy, ds = dock:GetLeft(), dock:GetBottom(), dock:GetEffectiveScale()
    if S.Finite(left) and S.Finite(bottom) and S.Finite(dx) and S.Finite(dy)
        and S.Finite(scale) and S.Finite(ds) and ds > 0 then
        changed = Store(info, "x", left * scale / ds - dx) or changed
        changed = Store(info, "y", bottom * scale / ds - dy) or changed
        changed = Store(info, "scale", scale / ds) or changed
    end
    return changed
end

local function Tabs(parts, dock, frame)
    local changed = false
    parts.nativeTabs = parts.nativeTabs or {}
    local count = #dock.DOCKED_CHAT_FRAMES
    count = math.min(64, math.max(1, count))
    changed = Store(parts, "nativeTabCount", count) or changed
    for index = 1, count do
        local nativeFrame = dock.DOCKED_CHAT_FRAMES[index]
        nativeFrame = nativeFrame or index == 1 and frame
        local name = nativeFrame and nativeFrame:GetName()
        local tab = S.PublicText(name) and _G[name .. "Tab"]
        local info = parts.nativeTabs[index]
        local tabID
        if tab then
            local width, height = tab:GetWidth(), tab:GetHeight()
            if S.Finite(width) and width > 0 and S.Finite(height) and height > 0 then
                info = info or {}
                parts.nativeTabs[index] = info
                local id = nativeFrame:GetID()
                if S.Finite(id) then tabID = id end
                changed = Store(info, "width", width) or changed
                changed = Store(info, "height", height) or changed
                changed = Store(info, "selected", nativeFrame == frame) or changed
                changed = Font(info, tab.Text, "font") or changed
                changed = TabMetrics(info, tab, dock) or changed
                local label = tab.Text:GetText()
                if S.PublicText(label) then changed = Store(info, "label", label) or changed end
            end
        end
        if info then
            changed = Store(info, "tabID", tabID) or changed
            changed = Store(info, "generation", tabID and C.TabGeneration(tabID)) or changed
        end
    end
    for index = count + 1, #parts.nativeTabs do parts.nativeTabs[index] = nil end
    return changed
end

local function Input(parts, frame)
    local input = frame.editBox
    if not input then return false end
    local changed, height = false, input:GetHeight()
    local context = C.M.context
    local properties = context and context.properties[input]
    local record = properties and properties.SetHeight
    if S.Finite(height) and height > 0 then
        if record and height == record.applied then height = record.before end
        changed = Store(parts, "nativeInputHeight", height) or changed
    end
    if input.header then changed = Font(parts, input.header, "input") or changed end
    return changed
end

-- The native windows own their unlocked dimensions and default font metrics.
-- Read those values; the menu never moves or restyles a native frame here.
function S.ChatPreviewSnapshot(parts)
    local dock = _G.GENERAL_CHAT_DOCK
    local frame = dock.selected or _G.ChatFrame1
    if not frame then return false end
    local changed = Store(parts, "source", frame)
    local width, height = frame:GetWidth(), frame:GetHeight()
    local scale, parentScale = frame:GetEffectiveScale(), _G.UIParent:GetEffectiveScale()
    if S.Finite(scale) and scale > 0 and S.Finite(parentScale) and parentScale > 0 then
        changed = Store(parts, "nativeScale", scale / parentScale) or changed
    end
    if S.Finite(width) and width > 0 then changed = Store(parts, "nativeWidth", width) or changed end
    if S.Finite(height) and height > 0 then changed = Store(parts, "nativeHeight", height) or changed end
    changed = Font(parts, frame, "message") or changed
    local mode, spacing = frame:GetInsertMode(), frame:GetSpacing()
    if S.Public(mode) then changed = Store(parts, "insertTop", mode == _G.SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP) or changed end
    if S.Finite(spacing) then changed = Store(parts, "messageSpacing", spacing) or changed end
    changed = Dock(parts, dock, frame, parentScale) or changed
    changed = Tabs(parts, dock, frame) or changed
    changed = Input(parts, frame) or changed
    local quick = C.CombatLogBar(frame)
    local quickHeight = quick and quick:GetHeight() or 0
    if S.Finite(quickHeight) then changed = Store(parts, "quickHeight", quickHeight) or changed end
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
        C.WatchFloatingClosures()
        hooked = true
        hooksecurefunc("FCF_SetChatWindowFontSize", NativeChanged)
        hooksecurefunc("FCFDock_SelectWindow", NativeChanged)
        hooksecurefunc("FCFDock_UpdateTabs", NativeChanged)
        hooksecurefunc("FCF_StopDragging", NativeChanged)
        hooksecurefunc("FCF_SetWindowName", NativeChanged)
        hooksecurefunc("FCF_Close", NativeChanged)
    end
    if callback and frame and not watched[frame] then
        watched[frame] = true
        frame:HookScript("OnSizeChanged", NativeChanged)
    end
end
