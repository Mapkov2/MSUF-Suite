local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
-- Addon buttons on the map (LibDBIcon icons and named buttons) collected into
-- one drawer. Owners keep controlling whether their button is shown; the
-- drawer only moves and scales buttons, and every button returns to its
-- recorded place when collection ends.
local weak = { __mode = "k" }
local collected, hooked, labels = setmetatable({}, weak), setmetatable({}, weak), setmetatable({}, weak)
local list, visible, rowItem = {}, {}, {}
local toggle, panel, single, rescanTimer, library
local libraryToken = {}
local GAP, MARGIN, RESCAN_DELAY = 4, 8, 0.1
-- MBB takes permanent ownership of the buttons it collects. Keep the map
-- active, but never compete with its button container.
function MM.CollectsButtons()
    return M.config and M.config.collectButtons and not NS.Client.IsAddOnLoaded("MinimapButtonButton") or false
end

-- Blizzard frames, the suite's own and known replacements are never collected.
local BLOCKED = {
    MinimapBackdrop = true,
    MinimapZoomIn = true,
    MinimapZoomOut = true,
    GameTimeFrame = true,
    TimeManagerClockButton = true,
    ExpansionLandingPageMinimapButton = true,
    AddonCompartmentFrame = true,
    MiniMapMailFrame = true,
    MiniMapBattlefieldFrame = true,
    MiniMapTracking = true,
    MiniMapTrackingButton = true,
    LFGMinimapFrame = true,
    MiniMapWorldMapButton = true,
    MinimapZoneTextButton = true,
    MinimapToggleButton = true,
    HybridMinimap = true,
    QueueStatusButton = true,
    MiniMapInstanceDifficulty = true,
    GuildInstanceDifficulty = true,
    MiniMapChallengeMode = true,
    PlumberLandingPageMinimapButton = true,
}
-- Map pins (HereBeDragons users and friends) are children of the map too.
local PINS = { "^HandyNotes", "^TomTom", "^HereBeDragons", "^HBD", "^Questie", "^GatherMate", "^Gatherer", "^[Pp]in" }
-- Opens away from the map, aligned with the toggle's corner.
local PANEL_ANCHORS = {
    { "TOPRIGHT", "TOPLEFT", -GAP, 0 }, { "BOTTOMLEFT", "TOPLEFT", 0, GAP }, { "TOPLEFT", "TOPRIGHT", GAP, 0 },
    { "BOTTOMRIGHT", "TOPRIGHT", 0, GAP }, { "BOTTOMRIGHT", "BOTTOMLEFT", -GAP, 0 }, { "TOPLEFT", "BOTTOMLEFT", 0, -GAP },
    { "BOTTOMLEFT", "BOTTOMRIGHT", GAP, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 0, -GAP },
}

local function Candidate(frame)
    if not MM.Usable(frame) or collected[frame] or type(frame.GetName) ~= "function" then return false end
    local name = frame:GetName()
    if not S.Public(name) or type(name) ~= "string" or name == "" or frame:IsProtected() then return false end
    if name:find("^LibDBIcon10_") then return true end
    if BLOCKED[name] or name:find("^MSUFSuite") or name:find("%d$") then return false end
    for i = 1, #PINS do if name:find(PINS[i]) then return false end end
    return type(frame.GetObjectType) == "function" and frame:GetObjectType() == "Button"
end
local function ByLabel(a, b) return labels[a] < labels[b] end
local function OwnerChanged(frame)
    if M.active and collected[frame] then MM.Queue("drawer") end
end
local function Scan()
    local map = _G.Minimap
    if not MM.Usable(map) then return end
    local children, added = { map:GetChildren() }, false
    for i = 1, #children do
        local frame = children[i]
        if Candidate(frame) then
            collected[frame], added = true, true
            labels[frame] = (frame:GetName():gsub("^LibDBIcon10_", "")):lower()
            list[#list + 1] = frame
            if not hooked[frame] then
                hooked[frame] = true
                hooksecurefunc(frame, "Show", OwnerChanged)
                hooksecurefunc(frame, "Hide", OwnerChanged)
                if type(frame.SetShown) == "function" then hooksecurefunc(frame, "SetShown", OwnerChanged) end
            end
        end
    end
    if added then table.sort(list, ByLabel) end
end

local function ClosePanel()
    if panel then panel:Hide() end
end
local function ClickAway()
    local overPanel, overToggle = panel:IsMouseOver(), toggle:IsMouseOver()
    if S.Public(overPanel) and overPanel or S.Public(overToggle) and overToggle then return end
    -- An addon button may be the mouse target instead of its parent panel.
    -- Keep the panel alive through the mouse-down so the button gets OnClick.
    for i = 1, #visible do
        local button = visible[i]
        local overButton = MM.Usable(button) and button:IsMouseOver()
        if S.Public(overButton) and overButton then return end
    end
    ClosePanel()
end
local function TogglePanel()
    if not M.active then return end
    if panel:IsShown() then
        ClosePanel()
        return
    end
    panel:Show()
    -- Registered only while the panel is open.
    MM.Listen("GLOBAL_MOUSE_DOWN", "drawer", ClickAway)
end
local function ShowTip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(MM.Label("ADDONS", "Addon buttons"))
    GameTooltip:AddLine(S.Text("Click to show or hide the collected buttons."), 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end
local function HideTip(self)
    if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
end
local function Outline(frame, layer)
    local edges = {}
    for i = 1, 4 do edges[i] = S.CreateTexture(frame, nil, layer) end
    edges[1]:SetPoint("TOPLEFT")
    edges[1]:SetPoint("TOPRIGHT")
    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT")
    edges[2]:SetPoint("BOTTOMRIGHT")
    edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT")
    edges[3]:SetPoint("BOTTOMLEFT")
    edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT")
    edges[4]:SetPoint("BOTTOMRIGHT")
    edges[4]:SetWidth(1)
    return edges
end
local function EnsureDrawer()
    if toggle then return end
    local host = MM.host
    toggle = S.CreateFrame("Button", nil, host)
    toggle.minimapOffsetKey = "drawer"
    toggle:SetFrameStrata("MEDIUM")
    toggle:SetFrameLevel(MM.mapLevel + 14)
    toggle:RegisterForClicks("LeftButtonUp")
    toggle.back = S.CreateTexture(toggle, nil, "BACKGROUND")
    toggle.back:SetAllPoints(toggle)
    -- A 2x2 grid glyph drawn from plain textures (no client-specific art).
    toggle.dots = {}
    for i = 1, 4 do
        toggle.dots[i] = S.CreateTexture(toggle, nil, "ARTWORK")
        toggle.dots[i]:SetColorTexture(0.9, 0.9, 0.9, 1)
    end
    local highlight = S.CreateTexture(toggle, nil, "HIGHLIGHT")
    highlight:SetAllPoints(toggle)
    highlight:SetColorTexture(1, 1, 1, 0.15)
    toggle:SetScript("OnClick", TogglePanel)
    toggle:SetScript("OnEnter", ShowTip)
    toggle:SetScript("OnLeave", HideTip)
    toggle:Hide()
    panel = S.CreateFrame("Frame", nil, host)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel.back = S.CreateTexture(panel, nil, "BACKGROUND")
    panel.back:SetAllPoints(panel)
    panel.back:SetColorTexture(0.05, 0.05, 0.05, 0.92)
    panel.edges = Outline(panel, "BORDER")
    panel:SetScript("OnEnter", MM.HoverEnter)
    panel:SetScript("OnLeave", MM.HoverLeave)
    panel:SetScript("OnHide", function()
        if M.context then MM.Unlisten("GLOBAL_MOUSE_DOWN", "drawer") end
        if M.active then MM.NotifyHover() end
    end)
    panel:Hide()
    single = S.CreateFrame("Frame", nil, host)
    single.minimapOffsetKey = "drawer"
    single:SetFrameStrata("MEDIUM")
    single:SetFrameLevel(MM.mapLevel + 14)
    single:Hide()
    MM.panel = panel
end

local function StyleToggle(c)
    local size = c.elementSize
    local dot = math.max(2, math.floor(size * 0.2 + 0.5))
    local offset = (dot + math.max(1, math.floor(size * 0.12 + 0.5))) / 2
    toggle:SetSize(size, size)
    for i = 1, 4 do
        local texture = toggle.dots[i]
        texture:SetSize(dot, dot)
        texture:ClearAllPoints()
        texture:SetPoint("CENTER", toggle, "CENTER", i % 2 == 1 and -offset or offset, i <= 2 and offset or -offset)
    end
    local r, g, b = MM.BorderRGB()
    toggle.back:SetColorTexture(r, g, b, 0.8)
    for i = 1, 4 do panel.edges[i]:SetColorTexture(r, g, b, 1) end
end
local function ToggleShown(c)
    return not c.drawerMouseover or MM.Revealed() or panel:IsShown()
end

function MM.LayoutDrawer()
    local c = M.config
    if not MM.CollectsButtons() or not toggle then return end
    local count, level = 0, panel:GetFrameLevel() + 2
    for i = 1, #list do
        local button = list[i]
        if collected[button] and MM.Usable(button) then
            local shown = button:IsShown()
            if not S.Public(shown) or shown then
                count = count + 1
                visible[count] = button
            else
                -- Hidden by its owner: waits in the (closed) panel until shown.
                MM.Place(button, panel, "CENTER", panel, "CENTER", 0, 0, nil, "DIALOG", level)
            end
        end
    end
    for i = count + 1, #visible do visible[i] = nil end
    local start = c.drawerRow == c.elementRow and (MM.rowCount or 0) or 0
    StyleToggle(c)
    if count == 1 then
        -- A single button goes straight onto the row; no toggle.
        toggle:Hide()
        ClosePanel()
        single:SetSize(c.elementSize, c.elementSize)
        single:Show()
        MM.Place(visible[1], single, "CENTER", single, "CENTER", 0, 0, MM.Fit(visible[1], c.elementSize), nil,
            single:GetFrameLevel() + 1)
        rowItem[1] = single
        MM.LayoutRow(c.drawerRow, rowItem, 1, c.elementSize, c.elementSpacing, c.elementDistance, start, "drawer")
        return
    end
    single:Hide()
    if count == 0 then
        toggle:Hide()
        ClosePanel()
        MM.SetExtent("drawer", 0, 0, 0, 0)
        return
    end
    toggle:SetShown(ToggleShown(c))
    rowItem[1] = toggle
    MM.LayoutRow(c.drawerRow, rowItem, 1, c.elementSize, c.elementSpacing, c.elementDistance, start, "drawer")
    local cell, columns = c.drawerButtonSize, math.min(c.drawerColumns, count)
    local rows = math.ceil(count / columns)
    panel:SetSize(MARGIN * 2 + columns * cell + (columns - 1) * GAP, MARGIN * 2 + rows * cell + (rows - 1) * GAP)
    local anchor = PANEL_ANCHORS[c.drawerRow] or PANEL_ANCHORS[1]
    panel:ClearAllPoints()
    panel:SetPoint(anchor[1], toggle, anchor[2], anchor[3], anchor[4])
    for i = 1, count do
        local button = visible[i]
        local column, row = (i - 1) % columns, math.floor((i - 1) / columns)
        local x = MARGIN + column * (cell + GAP) + cell / 2
        local y = -(MARGIN + row * (cell + GAP) + cell / 2)
        MM.Place(button, panel, "CENTER", panel, "TOPLEFT", x, y, MM.Fit(button, cell), "DIALOG", level)
    end
end

MM.flushers.drawer = MM.LayoutDrawer

MM.OnHover(function()
    if toggle and M.active and MM.CollectsButtons() and M.config.drawerMouseover and #visible > 1 then
        toggle:SetShown(ToggleShown(M.config))
    end
end)

local function Rescan()
    rescanTimer = nil
    if not M.active or not MM.CollectsButtons() then return end
    -- Late ADDON_LOADED icons are placed right away: rescan, then relayout.
    Scan()
    MM.Queue("drawer")
end
local function ScheduleRescan()
    if rescanTimer then rescanTimer:Cancel() end
    local timer = _G.C_Timer
    if timer and type(timer.NewTimer) == "function" then
        rescanTimer = timer.NewTimer(RESCAN_DELAY, Rescan)
    else
        Rescan()
    end
end
local function Library()
    local stub = _G.LibStub
    return type(stub) == "table" and type(stub.GetLibrary) == "function" and stub:GetLibrary("LibDBIcon-1.0", true) or
        nil
end
-- Without collection LibDBIcon lays its icons around the current shape and size.
function MM.RefreshIcons()
    if NS.Client.IsAddOnLoaded("MinimapButtonButton") then return end
    local lib = Library()
    if not lib or type(lib.GetButtonList) ~= "function" or type(lib.Refresh) ~= "function" then return end
    local names = lib:GetButtonList()
    if type(names) ~= "table" then return end
    for i = 1, #names do lib:Refresh(names[i]) end
end

function MM.ApplyDrawer()
    if not MM.CollectsButtons() then
        MM.ReleaseDrawer()
        MM.RefreshIcons()
        return
    end
    EnsureDrawer()
    MM.Listen("ADDON_LOADED", "drawer", ScheduleRescan)
    MM.Listen("PLAYER_ENTERING_WORLD", "drawer", ScheduleRescan)
    local lib = Library()
    if lib and not library and type(lib.RegisterCallback) == "function" then
        library = lib
        lib.RegisterCallback(libraryToken, "LibDBIcon_IconCreated", ScheduleRescan)
    end
    Scan()
    MM.LayoutDrawer()
end

function S.MinimapRescanButtons()
    if not M.active or not MM.CollectsButtons() or not toggle or NS.IsCombatLocked() then return false end
    Scan()
    MM.LayoutDrawer()
    return true
end

function MM.ReleaseDrawer()
    if rescanTimer then
        rescanTimer:Cancel()
        rescanTimer = nil
    end
    if library and type(library.UnregisterCallback) == "function" then
        library.UnregisterCallback(libraryToken,
            "LibDBIcon_IconCreated")
    end
    library = nil
    ClosePanel()
    for i = #list, 1, -1 do
        local button = list[i]
        MM.Release(button)
        collected[button], list[i] = nil, nil
    end
    for i = #visible, 1, -1 do visible[i] = nil end
    if toggle then
        toggle:Hide()
        single:Hide()
    end
    if M.context then
        MM.Unlisten("ADDON_LOADED", "drawer")
        MM.Unlisten("PLAYER_ENTERING_WORLD", "drawer")
    end
    MM.SetExtent("drawer", 0, 0, 0, 0)
end
