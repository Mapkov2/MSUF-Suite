local _, P = ...
local S, MM = P.Suite, P.Minimap
local button
-- Blizzard LFDMicroButton uses PVEFrame_ToggleFrame (upstream/ptr).
-- This independent shortcut leaves the native queue eye and its animations owned by Blizzard.
local function Allowed()
    return not P.NS.InCombat() and not S.editMode and MM.M.active and MM.M.config.dungeonButton
        and not Kiosk.IsEnabled() and not KeybindFrames_InQuickKeybindMode()
end

local function PreClick(self)
    local target = Allowed() and S.GamepadUI() and S.PanelButton("groupFinder") or nil
    self:SetAttribute("type", target and "click" or nil)
    self:SetAttribute("clickbutton", target)
end

local function Click()
    if not Allowed() or not S.CanOpenNativeWindow() or Kiosk.IsEnabled() or KeybindFrames_InQuickKeybindMode() then return end
    if P.NS.Client.isForever and type(ToggleGroupFinderFrame) == "function" then
        ToggleGroupFinderFrame()
    else
        PVEFrame_ToggleFrame()
    end
end
local function Ensure()
    if button then return button end
    local template = P.NS.Client.isForever and "InsecureActionButtonTemplate" or nil
    button = S.CreateFrame("Button", nil, MM.host, template)
    button:RegisterForClicks("LeftButtonUp")
    button:SetFrameLevel(MM.mapLevel + 5)
    if template then
        button:SetAttribute("useOnKeyDown", false)
        button:SetScript("PreClick", PreClick)
        button:HookScript("OnClick", Click)
    else
        button:SetScript("OnClick", Click)
    end
    local icon = S.CreateTexture(button, nil, "ARTWORK")
    button.dungeonIcon = icon
    -- The queue eye's place on the button (Elements.lua parents the eye here),
    -- so the button's show rule covers the eye that stands in for it.
    local holder = S.CreateFrame("Frame", nil, MM.host)
    holder:SetFrameLevel(MM.mapLevel + 5)
    holder:EnableMouse(false)
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER", button, "CENTER")
    MM.dungeonButton, MM.dungeonEyeHolder = button, holder
    -- Pointing at the button keeps a mouseover button open.
    MM.HookHover(button)
    return button
end

-- Blizzard's queue eye stands in for this button while it shows (Elements.lua
-- LayoutQueue): one group finder on the map, with the queue's tooltip and menu.
local function EyeStandsIn(c)
    local Native = P.NS.MinimapElements
    if Native.QueuePlacement(c) ~= "finder" then return false end
    local eye = Native.QueueStatus()
    local shown = eye and eye:IsShown()
    return P.NS.Public(shown) and shown == true
end

-- When to show: always, on mouseover of the map, out of combat, or only as
-- the queue eye while queued. Combat is watched only for its own choice.
local SHOW = P.NS.MinimapGroupFinderShow
local REGEN = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local inCombat = false
local function Shows(c)
    local mode = c.dungeonShow
    if mode == SHOW.MOUSEOVER then return MM.Revealed() end
    if mode == SHOW.OUT_OF_COMBAT then return not inCombat end
    return true
end
local function ApplyShown(c)
    if not button or not c.dungeonButton then return end
    local shows = Shows(c)
    MM.dungeonEyeHolder:SetShown(shows)
    button:SetShown(shows and c.dungeonShow ~= SHOW.QUEUED and not EyeStandsIn(c))
end
local function CombatChanged(_, event)
    inCombat = P.NS.InCombat(event)
    if MM.M.active then ApplyShown(MM.M.config) end
end
local function WatchCombat(c)
    local watch = c.dungeonButton and c.dungeonShow == SHOW.OUT_OF_COMBAT
    if watch then inCombat = P.NS.InCombat() end
    for i = 1, #REGEN do
        if watch then MM.Listen(REGEN[i], "dungeonShow", CombatChanged) else MM.Unlisten(REGEN[i], "dungeonShow") end
    end
end
-- The symbol's colour (MinimapStyle.GroupFinderTint); nil keeps Blizzard's eye as drawn.
local function SymbolRGB(c)
    local tint = P.NS.MinimapStyle.GroupFinderTint(c)
    if tint == "class" then
        local _, token = UnitClass("player")
        local r, g, b
        if S.Public(token) then r, g, b = S.ClassRGB(token) end
        if r then return r, g, b end
        tint = "e6ecf2"
    end
    if tint then return S.RGB(tint) end
end

MM.OnHover(function()
    local c = MM.M.config
    if MM.M.active and c.dungeonShow == SHOW.MOUSEOVER then ApplyShown(c) end
end)

function MM.ApplyDungeonShortcut()
    local c = MM.M.config
    WatchCombat(c)
    if not c.dungeonButton then
        if button then
            button:Hide()
            MM.dungeonEyeHolder:Hide()
        end
        MM.SetExtent("dungeon", 0, 0, 0, 0)
        return
    end
    local frame = Ensure()
    local Style = P.NS.MinimapStyle
    local r, g, b = SymbolRGB(c)
    Style.PaintDungeonButton(frame, frame.dungeonIcon, Style.GroupFinderStyle(c), 1, c.dungeonIcon,
        c.dungeonWidth, c.dungeonHeight, r, g, b)
    -- Only the square symbol takes clicks, not the empty sides of a wide button.
    local side = math.min(c.dungeonWidth, c.dungeonHeight)
    local dx, dy = (c.dungeonWidth - side) / 2, (c.dungeonHeight - side) / 2
    frame:SetHitRectInsets(dx, dx, dy, dy)
    local anchor = P.NS.MinimapDungeonAnchors[c.dungeonAnchor]
    frame:SetSize(c.dungeonWidth, c.dungeonHeight)
    frame:ClearAllPoints()
    frame:SetPoint(anchor[1], MM.host, anchor[2], c.dungeonX, c.dungeonY)
    local width, height = MM.Dimensions()
    local left = anchor[2]:find("LEFT", 1, true) and c.dungeonX or width + c.dungeonX - c.dungeonWidth
    local bottom = anchor[2]:find("TOP", 1, true) and height + c.dungeonY or c.dungeonY - c.dungeonHeight
    MM.SetExtent("dungeon", math.max(0, -left), math.max(0, left + c.dungeonWidth - width),
        math.max(0, bottom + c.dungeonHeight - height), math.max(0, -bottom))
    ApplyShown(c)
end
