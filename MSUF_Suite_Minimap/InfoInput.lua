local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
local CLOCK_CLICK = NS.MinimapClockClick
-- Clicks and tooltips of the information texts (Info.lua builds them). A
-- text is an ordinary button on the minimap host, which moves, shows and
-- hides in combat. Coordinates, Location (with its click on) and Durability
-- open the world map and the character window: while the pointer rests on
-- one out of combat it borrows one secure overlay in UIParent that clicks
-- Blizzard's own opener button (S.PanelButton), so the window opens from
-- secure code. PLAYER_REGEN_DISABLED, before the lockdown, releases the
-- overlay and a "[combat] hide" state driver backs that up. Without a usable
-- Blizzard button the text's own click opens the window through Blizzard's
-- panel manager (S.TogglePanel).
-- ToggleCalendar and ToggleTimeManager are the bootstrap entry points of
-- Blizzard's load-on-demand calendar and clock (they load the addon first):
-- the calendar opens through ShowUIPanel (Calendar_Toggle), the clock window
-- is a plain frame outside the panel manager.
local PANELS = { Coordinates = "worldMap", Location = "worldMap", Durability = "character" }
-- Blizzard's localized names where one exists, else the suite's own text.
local TITLES = {
    Clock = { "TIMEMANAGER_TITLE", "Clock" },
    FPS = { false, "FPS" },
    Latency = { false, "Latency" },
    Coordinates = { false, "Coordinates" },
    Durability = { "DURABILITY", "Durability" },
    Location = { "ZONE", "Location" },
    Weather = { false, "Weather" },
}
local overlay

local function OpensWindow(button)
    local key = button.infoKey
    return key == "Coordinates" or key == "Durability" or key == "Location" and M.config.infoLocationClick == true
end

local function Click(button, mouseButton)
    if not M.active or NS.IsCombatLocked() then return end
    if button.infoKey == "Clock" then
        local calendar = M.config.infoClockClick == CLOCK_CLICK.CALENDAR
        if mouseButton == "RightButton" then calendar = not calendar end
        if calendar then ToggleCalendar() else ToggleTimeManager() end
    elseif OpensWindow(button) then
        S.TogglePanel(PANELS[button.infoKey])
    end
end

------------------------------------------------------------------ secure overlay
-- Lets go of the overlay; in combat only the bookkeeping changes (the state
-- driver hides it, and nothing moves a protected frame in lockdown).
local function Detach()
    if not overlay or not overlay.owner then return end
    overlay.owner = nil
    if M.context then MM.Unlisten("PLAYER_REGEN_DISABLED", "infoOverlay") end
    if NS.IsCombatLocked() then return end
    overlay:Hide()
    overlay:ClearAllPoints()
end
MM.DetachInfoOverlay = Detach

local function Covers(button)
    return overlay ~= nil and overlay.owner == button and overlay:IsShown() and overlay:IsMouseOver() == true
end

local function Leave(button)
    if Covers(button) then return end
    if overlay and overlay.owner == button then Detach() end
    MM.HideInfoTooltip(button)
end

local function Hidden(button)
    if overlay and overlay.owner == button then Detach() end
    MM.HideInfoTooltip(button)
end

local function OverlayLeave(self)
    local owner = self.owner
    Detach()
    if owner then MM.HideInfoTooltip(owner) end
end

local function Overlay()
    if overlay then return overlay end
    overlay = S.CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- SecureActionButton_OnClick acts on the press while ActionButtonUseKeyDown
    -- is on; the overlay registers the release, which must be the click.
    overlay:SetAttribute("useOnKeyDown", false)
    -- Every mouse button opens the window, as the text's click did.
    overlay:SetAttribute("type", "click")
    overlay:SetScript("OnLeave", OverlayLeave)
    overlay:Hide()
    RegisterStateDriver(overlay, "visibility", "[combat] hide")
    MM.infoOverlay = overlay
    return overlay
end

local function Attach(button)
    if S.editMode or NS.IsCombatLocked() or not OpensWindow(button) then return end
    local target = S.PanelButton(PANELS[button.infoKey])
    if not target then return end
    local frame = Overlay()
    frame.owner = button
    frame:SetAttribute("clickbutton", target)
    frame:SetFrameStrata(button:GetFrameStrata())
    frame:SetFrameLevel(button:GetFrameLevel() + 5)
    frame:ClearAllPoints()
    frame:SetAllPoints(button)
    frame:Show()
    MM.Listen("PLAYER_REGEN_DISABLED", "infoOverlay", Detach)
end

------------------------------------------------------------------ tooltip
local function Enter(button)
    if not M.active then return end
    Attach(button)
    if MM.ShowInfoTooltip(button) then return end
    local key = button.infoKey
    local entry, title = M.infoEntries[key], TITLES[key]
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    MM.ScaleTooltip(button)
    GameTooltip:SetText(S.BlizzardText(title[1], title[2]))
    GameTooltip:AddLine(entry.tooltipText or entry.text or "--", 1, 1, 1)
    if key == "Clock" then
        if entry.invite and entry.invite:IsShown() then
            GameTooltip:AddLine(S.Text("Calendar invitations are waiting."), 1, .82, 0)
        end
        local hint = M.config.infoClockClick == CLOCK_CLICK.CALENDAR and "Left: calendar. Right: clock."
            or "Left: clock. Right: calendar."
        GameTooltip:AddLine(S.Text(hint), .7, .8, .9)
    elseif key == "Coordinates" or key == "Location" and M.config.infoLocationClick then
        GameTooltip:AddLine(S.Text("Click to open the world map."), .7, .8, .9)
    elseif key == "Durability" then
        GameTooltip:AddLine(S.Text("Click to open your equipment."), .7, .8, .9)
    end
    GameTooltip:Show()
end

-- The scripts of every information text button.
MM.InfoScripts = { OnClick = Click, OnEnter = Enter, OnLeave = Leave, OnHide = Hidden }
