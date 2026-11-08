local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}

-- Reviewed top-level windows. Modal dialogs and secure actions retain native handling.
local names = {
    "AuctionHouseFrame", "QuestLogPopupDetailFrame", "QuestFrame", "GossipFrame",
    "CharacterFrame", "DressUpFrame", "CollectionsJournal", "AchievementFrame",
    "EncounterJournal", "ProfessionsFrame", "ProfessionsBookFrame", "InspectFrame",
    "MerchantFrame", "MailFrame", "GuildBankFrame", "TradeFrame",
    "WorldMapFrame", "LFGParentFrame",
}
local slots = { "left", "center", "right", "doublewide", "fullscreen" }
local records, shown, bagFrames = {}, {}, {}
local bagNames = {
    "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6", "ContainerFrame7",
}
local ESCAPE_FRAME = "MSUFSuiteParallelWindowsEscape"
local AREA = "UIPanelLayout-area"
local DEFINED = "UIPanelLayout-defined"
local watcher, reconcile, flush, queued, layoutPending, map, playerSpells
local latest, pendingClose, pendingCap
local windowLimit = 0
local escapeArmed = false
local escapeSupported = GameMenuEscPriority ~= nil and debugstack ~= nil
local serial, ownedCount, shownBags = 0, 0, 0
local bagOrder

local function Accessible(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

local function IsFree(frame)
    local area = frame:GetAttribute(AREA)
    return NS.Public(area) and area == nil
end

local function OccupiesSlot(frame)
    for _, slot in ipairs(slots) do
        if GetUIPanel(slot) == frame then return true end
    end
    return false
end

local function EscapeAllowed(event)
    return escapeSupported and not NS.InCombat(event)
        and not (NS.Client.isForever and InputUtil.IsGamepadUIEnabled())
end

local function CanFloat(frame)
    local protected, explicit = frame:IsProtected()
    -- Spellbook buttons can implicitly protect their plain outer container.
    return not protected or (frame == playerSpells and explicit == false)
end

local function Visible(frame)
    return Accessible(frame) and frame:IsShown()
end

local function CanClose(frame, managed)
    return frame and shown[frame] and Visible(frame) and CanFloat(frame) and (managed or IsFree(frame))
end

local function CanCloseBags()
    if shownBags == 0 then return false end
    for frame, open in pairs(bagFrames) do
        if open then
            if not Accessible(frame) then return false end
            local protected, explicit = frame:IsProtected()
            if protected and explicit ~= false then return false end
        end
    end
    return true
end

local function FindCloseTarget(except, oldest)
    local target, order
    for frame, opened in pairs(shown) do
        local preferred = not order or (oldest and opened < order) or (not oldest and opened > order)
        if preferred and frame ~= except and CanClose(frame, oldest) then target, order = frame, opened end
    end
    if oldest and except ~= bagFrames and bagOrder and (not order or bagOrder < order) and CanCloseBags() then
        return bagFrames
    end
    return target
end

local function ObserveOpen(frame)
    if shown[frame] then return end
    serial = serial + 1
    shown[frame] = serial
end

local function LastOpenWindow()
    local newest, order
    if shownBags > 0 then newest, order = bagFrames, bagOrder end
    for frame, opened in pairs(shown) do
        if Visible(frame) and (not order or opened > order) then newest, order = frame, opened end
    end
    return newest
end

local function ForgetClosedWindows()
    for frame in pairs(shown) do
        if not Visible(frame) then shown[frame] = nil end
    end
    if shownBags == 0 then bagOrder = nil end
end

local function SetEscapeArmed(armed)
    if escapeArmed == armed then return end
    escapeArmed = armed
    watcher:SetShown(armed)
end

local function SyncEscape(event)
    if not EscapeAllowed(event) then
        SetEscapeArmed(false)
        return
    end
    if not CanClose(latest) then latest = FindCloseTarget() end
    SetEscapeArmed(latest ~= nil)
end

local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0, flush)
end

local function QueueCap()
    if windowLimit == 0 or NS.InCombat() then return end
    pendingCap = true
    Queue()
end

local function CountWindows()
    local count = shownBags > 0 and 1 or 0
    for frame in pairs(records) do
        if Visible(frame) then count = count + 1 end
    end
    return count
end

local function ApplyWindowLimit(pending)
    if windowLimit == 0 or not pending or NS.InCombat() then return end
    local opening = LastOpenWindow()
    while not NS.InCombat() and CountWindows() > windowLimit do
        local target = FindCloseTarget(opening, true)
        if not target then return end
        if target == bagFrames then
            NS.Dispatch(CloseAllBags)
            if shownBags > 0 then return end
        else
            NS.Dispatch(HideUIPanel, target)
            if Visible(target) then return end
        end
    end
end

flush = function()
    queued = false
    local frame, opening = pendingClose, pendingCap
    pendingClose, pendingCap = nil, nil
    ForgetClosedWindows()
    if frame and EscapeAllowed() and CanClose(frame) then NS.Dispatch(HideUIPanel, frame) end
    ApplyWindowLimit(opening)
    if layoutPending then
        layoutPending = false
        reconcile()
    else
        SyncEscape()
    end
    if pendingCap then Queue() end
end

local function OnEscapeFrameHidden()
    if not escapeArmed then return end
    escapeArmed = false
    -- CloseSpecialWindows also runs when opening some native panels. Only the
    -- Escape dispatcher should close a floating window. Defer the close so
    -- the native handler completes before Suite runs any panel code.
    if EscapeAllowed() and CanClose(latest) and debugstack(2, 12, 0):find("Blizzard_GameMenuEsc.lua", 1, true) then
        pendingClose = latest
    end
    Queue()
end

local function OnHide(frame)
    if Visible(frame) then return end
    local record = records[frame]
    record.open = false
    -- Native tab and size transitions can hide and re-show within one call.
    -- Retain their opening order until the deferred pass sees a real close.
    if latest == frame then SyncEscape() end
    if M.active or record.area then
        layoutPending = true
        Queue()
    end
end

local function OnShow(frame)
    local record = records[frame]
    if record.open or not Accessible(frame) then return end
    record.open = true
    ObserveOpen(frame)
    QueueCap()
    if not record.area or not IsFree(frame) then return end
    if CanFloat(frame) then
        if not CanClose(latest) or shown[frame] > shown[latest] then latest = frame end
        if not NS.InCombat() then
            if frame == playerSpells then
                local fit = frame:GetAttribute("UIPanelLayout-checkFit")
                local width = frame:GetAttribute("UIPanelLayout-checkFitExtraWidth")
                local height = frame:GetAttribute("UIPanelLayout-checkFitExtraHeight")
                if NS.Public(fit) and fit == 1 and NS.Public(width) and NS.Public(height) then
                    UIPanelUpdateScaleForFit(frame, width or 20, height or 20)
                end
            end
            if frame:IsToplevel() then frame:Raise() end
        end
    end
    SyncEscape()
end

-- Maximizing still gives the map its native size and full-size anchor.
-- With no panel slot, the native minimize transition leaves that anchor
-- in place, so give the compact map back the point it had before maximizing.
local function RestoreCompactMap(event)
    if not Accessible(map) then return end
    local record = records[map]
    if not record.restoreCompact or NS.InCombat(event) or map:IsProtected() or not IsFree(map) then return end
    record.restoreCompact = nil
    map:ClearAllPoints()
    if record.compactPoint then
        map:SetPoint(unpack(record.compactPoint, 1, 5))
    else
        map:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 28, -100)
    end
end

local function MapMaximized()
    if not Accessible(map) or not IsFree(map) then return end
    local record = records[map]
    if record.maximized then return end
    record.maximized = true
    if record.restoreCompact then
        record.restoreCompact = nil
        return
    end
    local point, relative, relativePoint, x, y = map:GetPoint(1)
    if NS.Public(point) and NS.Public(relative) and NS.Public(relativePoint) and NS.Public(x) and NS.Public(y)
        and point then
        record.compactPoint = { point, relative, relativePoint, x, y }
    end
end

local function MapMinimized()
    local record = map and records[map]
    if not record or not record.maximized then return end
    record.maximized = nil
    record.restoreCompact = true
    RestoreCompactMap()
end

local function Track(frame)
    local record = records[frame]
    if not record then
        record = { open = frame:IsShown() }
        records[frame] = record
        if record.open then ObserveOpen(frame) end
        frame:HookScript("OnHide", OnHide)
        frame:HookScript("OnShow", OnShow)
    end
    return record
end

local function Attach(name, index)
    local frame = _G[name]
    local info = UIPanelWindows[name]
    if not Accessible(frame) or not info or frame:GetParent() ~= UIParent then return end
    local canDetach = (info.area == "left" or info.area == "doublewide") and not frame:IsProtected()
    local record = Track(frame)
    -- A nil map area bypasses Blizzard's panel delegate. On Forever, that
    -- direct show/hide path can rebuild quest pins with tainted layout state.
    if name == "WorldMapFrame" and NS.Client.isForever then return end
    if not canDetach then return end
    -- Changing a shown panel would strand its slot in the native manager.
    -- Let its current close run first, then apply the new layout policy.
    if record.area or frame:IsShown() or OccupiesSlot(frame) then return end
    local defined, area = frame:GetAttribute(DEFINED), frame:GetAttribute(AREA)
    if not NS.Public(defined) or not NS.Public(area) or defined and area ~= info.area then return end

    if frame:GetNumPoints() == 0 then
        local offset = (index - 1) % 7
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 28 + offset * 40, -100 - offset * 22)
    end
    -- The native API treats a panel with no area as a floating window and
    -- still runs the original Show/Hide scripts, close buttons and events.
    SetUIPanelAttribute(frame, "area", nil)
    if frame:GetAttribute(DEFINED) == true and IsFree(frame) then
        record.area, ownedCount = info.area, ownedCount + 1
        if name == "WorldMapFrame" then
            map = frame
            record.maximized = frame:IsMaximized()
            EventRegistry:RegisterCallback("WorldMapMaximized", MapMaximized, M)
            EventRegistry:RegisterCallback("WorldMapMinimized", MapMinimized, M)
        end
    end
end

local function OnSpellAreaChanged(frame, key)
    -- Native tab selection sets the area before ShowUIPanel. A resize can
    -- set it while still occupying a slot, then write the offset after HideUIPanel.
    if frame ~= playerSpells or not M.active or (key ~= "area" and key ~= "centerXOffset")
        or NS.InCombat() or not Accessible(frame) or frame:GetParent() ~= UIParent or not CanFloat(frame)
        or InputUtil.IsGamepadUIEnabled() then return end
    local area = frame:GetAttribute(AREA)
    if not NS.Public(area) or (area ~= "center" and area ~= "centerOrLeft" and area ~= "left") then return end
    local record = records[frame]
    if (not record.area and frame:IsShown()) or OccupiesSlot(frame) then return end
    SetUIPanelAttribute(frame, "area", nil)
    if IsFree(frame) then
        if not record.area then ownedCount = ownedCount + 1 end
        record.area = area
    end
end

local function AttachPlayerSpells()
    if playerSpells then return end
    local frame = _G.PlayerSpellsFrame
    if not Accessible(frame) or not UIPanelWindows.PlayerSpellsFrame or frame:GetParent() ~= UIParent then return end
    playerSpells = frame
    Track(frame)
    if NS.Client.isForever then hooksecurefunc("SetUIPanelAttribute", OnSpellAreaChanged) end
end

local function OnBagShow(frame)
    if bagFrames[frame] then return end
    bagFrames[frame] = true
    shownBags = shownBags + 1
    if shownBags == 1 then
        if not bagOrder then
            serial = serial + 1
            bagOrder = serial
        end
        QueueCap()
    end
end

local function OnBagHide(frame)
    if not bagFrames[frame] or Visible(frame) then return end
    bagFrames[frame] = false
    shownBags = shownBags - 1
    if shownBags == 0 then Queue() end
end

local function AttachBagFrames()
    for _, name in ipairs(bagNames) do
        local frame = _G[name]
        if Accessible(frame) and bagFrames[frame] == nil then
            bagFrames[frame] = false
            if frame:IsShown() then OnBagShow(frame) end
            frame:HookScript("OnShow", OnBagShow)
            frame:HookScript("OnHide", OnBagHide)
        end
    end
end

local function Release(frame, record)
    if not record.area or not Accessible(frame) or frame:IsShown() or not CanFloat(frame) then return end
    local current = frame:GetAttribute(AREA)
    if not NS.Public(current) then return end
    if current == nil then SetUIPanelAttribute(frame, "area", record.area) end
    record.area, ownedCount = nil, ownedCount - 1
    if frame == map then
        EventRegistry:UnregisterCallback("WorldMapMaximized", M)
        EventRegistry:UnregisterCallback("WorldMapMinimized", M)
        record.restoreCompact, map = nil, nil
    end
end

reconcile = function(event)
    if NS.InCombat(event) then
        SetEscapeArmed(false)
        return
    end
    RestoreCompactMap(event)
    if M.active then
        -- The quest log uses WorldMapFrame even when M is set to open the large map.
        for index, name in ipairs(names) do Attach(name, index) end
        AttachPlayerSpells()
        AttachBagFrames()
    else
        for frame, record in pairs(records) do Release(frame, record) end
        if ownedCount == 0 then watcher:UnregisterAllEvents() end
    end
    SyncEscape(event)
end

local function OnEvent(_, event, key)
    if event == "CVAR_UPDATE" then
        if NS.Public(key) and key == "InputDeviceInterfaceStyle" then SyncEscape(event) end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "GAME_PAD_ACTIVE_CHANGED" then
        if event == "PLAYER_REGEN_DISABLED" then pendingCap = nil end
        SyncEscape(event)
    else
        reconcile(event)
    end
end

function M:Enable()
    if not watcher then
        watcher = CreateFrame("Frame", ESCAPE_FRAME)
        watcher:Hide()
        watcher:SetScript("OnEvent", OnEvent)
        if escapeSupported then
            watcher:SetScript("OnHide", OnEscapeFrameHidden)
            -- The native close pass already supports addon-owned windows.
            -- Registering an Escape callback would re-sort the shared protected dispatch.
            UISpecialFrames[#UISpecialFrames + 1] = ESCAPE_FRAME
        end
    end
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    if NS.Client.isForever then
        watcher:RegisterEvent("CVAR_UPDATE")
        watcher:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
    end
    self:Refresh()
end

function M:Refresh()
    local previous = windowLimit
    windowLimit = S.Config("parallelWindows").windowLimit or 0
    reconcile()
    if windowLimit ~= previous then QueueCap() end
end

function M:Disable()
    windowLimit, pendingCap = 0, nil
    if not watcher then return end
    watcher:UnregisterEvent("ADDON_LOADED")
    reconcile()
end

S.Install("parallelWindows", M)
