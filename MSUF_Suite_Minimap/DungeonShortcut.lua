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
    local background = S.CreateTexture(button, nil, "BACKGROUND")
    background:SetAllPoints(button)
    background:SetColorTexture(0, 0, 0, 1)
    local icon = S.CreateTexture(button, nil, "ARTWORK")
    button.dungeonIcon = icon
    MM.dungeonButton = button
    return button
end

function MM.ApplyDungeonShortcut()
    local c = MM.M.config
    if not c.dungeonButton then
        if button then button:Hide() end
        MM.SetExtent("dungeon", 0, 0, 0, 0)
        return
    end
    local frame = Ensure()
    P.NS.MinimapStyle.PaintDungeonButton(frame, frame.dungeonIcon, c.dungeonStyle, 1)
    local anchor = P.NS.MinimapDungeonAnchors[c.dungeonAnchor]
    frame:SetSize(c.dungeonWidth, c.dungeonHeight)
    frame:ClearAllPoints()
    frame:SetPoint(anchor[1], MM.host, anchor[2], c.dungeonX, c.dungeonY)
    local width, height = MM.Dimensions()
    local left = anchor[2]:find("LEFT", 1, true) and c.dungeonX or width + c.dungeonX - c.dungeonWidth
    local bottom = anchor[2]:find("TOP", 1, true) and height + c.dungeonY or c.dungeonY - c.dungeonHeight
    MM.SetExtent("dungeon", math.max(0, -left), math.max(0, left + c.dungeonWidth - width),
        math.max(0, bottom + c.dungeonHeight - height), math.max(0, -bottom))
    frame:Show()
end
