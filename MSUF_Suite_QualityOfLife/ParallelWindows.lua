local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}

-- Reviewed windows that may float even when their registration lacks whileDead.
local reviewed = {
    AuctionHouseFrame = true, QuestLogPopupDetailFrame = true, QuestFrame = true, GossipFrame = true,
    CharacterFrame = true, DressUpFrame = true, CollectionsJournal = true, AchievementFrame = true,
    EncounterJournal = true, ProfessionsFrame = true, ProfessionsBookFrame = true, InspectFrame = true,
    MerchantFrame = true, MailFrame = true, GuildBankFrame = true, TradeFrame = true,
    WorldMapFrame = true, LFGParentFrame = true,
}
local sideAreas = { left = true, doublewide = true, centerOrLeft = true, right = true }
local childPanels = {
    LootFrame = true, PetitionFrame = true, PVPBannerFrame = true, ClubFinderGuildRecruitmentDialog = true,
    CommunitiesGuildLogFrame = true, CommunitiesGuildTextEditFrame = true, CommunitiesGuildNewsFiltersFrame = true,
}
-- These native OnHide scripts only clear the quest detail or play a sound.
local combatClose = { QuestLogPopupDetailFrame = true, ExpansionLandingPage = true }
local slots = { "left", "center", "right", "doublewide", "fullscreen" }
local records, shown, bagFrames, pendingLayout = {}, {}, {}, {}
local bagNames = {
    "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6", "ContainerFrame7",
}
local ESCAPE_FRAME = "MSUFSuiteParallelWindowsEscape"
local AREA = "UIPanelLayout-area"
local DEFINED = "UIPanelLayout-defined"
local watcher, prepare, release, flush, queued, map, playerSpells
local latest, pendingClose, pendingCap, capAfterCombat
local windowLimit = 0
local escapeArmed = false
local serial, ownedCount, shownBags, openedWindows = 0, 0, 0, 0
local placementIndex = 0
local bagOrder

local function Accessible(frame)
    return NS.Public(frame) and frame and not NS.Safety.IsForbidden(frame)
end

local function IsFree(frame)
    local defined = frame:GetAttribute(DEFINED)
    if not NS.Public(defined) or defined ~= true then return false end
    local area = frame:GetAttribute(AREA)
    return NS.Public(area) and area == nil
end

local function OccupiesSlot(frame)
    for _, slot in ipairs(slots) do
        if GetUIPanel(slot) == frame then return true end
    end
    return false
end

local function EscapeAllowed()
    return M.active and not (NS.Client.isForever and S.GamepadUI())
end

local function Visible(frame)
    return Accessible(frame) and frame:IsShown()
end

local function NativeOnly(record)
    return record.nativeOnly or record.foreverOnly and NS.Client.isForever
end

local function CanClose(frame, managed, combat)
    if not frame or not shown[frame] then return false end
    local record = records[frame]
    local canFloat = record.detachable and not NativeOnly(record)
    local canCloseManaged = managed and record.retailCap and not NS.Client.isForever and not combat
    if not (canFloat or canCloseManaged) or not Visible(frame) then return false end
    local protected, explicit = frame:IsProtected()
    if protected and (not canCloseManaged or frame ~= playerSpells or explicit ~= false) then return false end
    if frame == _G.CharacterFrame and NS.Client.isForever and S.GamepadUI() then return false end
    if combat then
        -- HideUIPanel is gated even for floating frames. Only use Hide for our own
        -- detached roots with reviewed native OnHide scripts.
        return record.combatClose and record.area and frame:GetParent() == UIParent and IsFree(frame)
    end
    return canCloseManaged or IsFree(frame)
end

local function CanCloseBags()
    if shownBags == 0 then return false end
    -- Forever's combined bag OnHide calls ToggleCharacter in Gamepad UI.
    if NS.Client.isForever and bagFrames[_G.ContainerFrameCombinedBags]
        and Visible(_G.CharacterFrame) and S.GamepadUI() then return false end
    for frame, open in pairs(bagFrames) do
        if open then
            if not Accessible(frame) then return false end
            local protected, explicit = frame:IsProtected()
            if protected and explicit ~= false then return false end
        end
    end
    return true
end

local function FindCloseTarget(except, oldest, combat)
    local target, order
    for frame, opened in pairs(shown) do
        local preferred = not order or (oldest and opened < order) or (not oldest and opened > order)
        if preferred and frame ~= except and CanClose(frame, oldest, combat) then target, order = frame, opened end
    end
    if oldest and not combat and except ~= bagFrames and bagOrder and (not order or bagOrder < order) and CanCloseBags() then
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
        if not Visible(frame) then
            local record = records[frame]
            if record.open then
                record.open = false
                openedWindows = openedWindows - 1
            end
            shown[frame] = nil
        end
    end
    if shownBags == 0 then bagOrder = nil end
end

local function SetEscapeArmed(armed)
    if escapeArmed == armed then return end
    escapeArmed = armed
    watcher:SetShown(armed)
end

local function SyncEscape(event)
    if not EscapeAllowed() or NS.Client.isForever and Visible(playerSpells) then
        SetEscapeArmed(false)
        return
    end
    local combat = NS.InCombat(event)
    if not CanClose(latest, false, combat) then latest = FindCloseTarget(nil, false, combat) end
    SetEscapeArmed(latest ~= nil)
end

local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0, flush)
end

local function WindowCount()
    return openedWindows + (shownBags > 0 and 1 or 0)
end

local function QueueCap()
    if windowLimit == 0 or WindowCount() <= windowLimit then return end
    pendingCap = true
    Queue()
end

local function CloseWindow(frame, combat)
    if frame == bagFrames then
        NS.Dispatch(CloseAllBags)
        return shownBags == 0
    end
    if combat then
        NS.Dispatch(frame.Hide, frame)
    else
        NS.Dispatch(HideUIPanel, frame)
    end
    if Visible(frame) then return false end
    local record = records[frame]
    if record.open then
        record.open = false
        openedWindows = openedWindows - 1
    end
    return true
end

local function ApplyWindowLimit(pending)
    if windowLimit == 0 or not pending then return end
    local opening = LastOpenWindow()
    local count = WindowCount()
    while count > windowLimit do
        local combat = NS.InCombat()
        local target = FindCloseTarget(opening, true, combat)
        if not target or not CloseWindow(target, combat) or WindowCount() >= count then
            capAfterCombat = combat
            return
        end
        count = WindowCount()
    end
    capAfterCombat = nil
end

local function ApplyPendingLayout()
    for panel in pairs(pendingLayout) do
        pendingLayout[panel] = nil
        if M.active then prepare(panel, records[panel]) else release(panel, records[panel]) end
    end
    if not M.active and ownedCount == 0 then watcher:UnregisterAllEvents() end
end

flush = function()
    local frame, cap = pendingClose, pendingCap
    pendingClose, pendingCap = nil, nil
    ForgetClosedWindows()
    local combat = NS.InCombat()
    if frame and EscapeAllowed() and CanClose(frame, false, combat) then CloseWindow(frame, combat) end
    ApplyWindowLimit(cap)
    if not NS.InCombat() then ApplyPendingLayout() end
    queued = false
    SyncEscape()
    if pendingCap and not cap and WindowCount() > windowLimit then Queue() end
end

local function OnEscapeFrameHidden()
    if not escapeArmed then return end
    escapeArmed = false
    -- CloseSpecialWindows also runs when opening some native panels. Only the
    -- Escape dispatcher should close a floating window. Defer the close so
    -- the native handler completes before Suite runs any panel code.
    local stack = EscapeAllowed() and CanClose(latest, false, NS.InCombat()) and NS.PublicText(debugstack(2, 12, 0))
    if stack and stack:find("Blizzard_GameMenuEsc.lua", 1, true) then
        pendingClose = latest
    end
    Queue()
end

local function OnHide(frame)
    local record = records[frame]
    if not record.open or Visible(frame) then return end
    record.open = false
    openedWindows = openedWindows - 1
    -- A native resize can hide and re-show in one stack. Defer ordering and
    -- only revisit the panel that lost its native slot.
    if record.detachable and (M.active and not NativeOnly(record) and not record.area
        or not M.active and record.area) then
        pendingLayout[frame] = true
    end
    if latest == frame then SyncEscape() end
    if M.active or record.area then Queue() end
end

local function OnShow(frame)
    local record = records[frame]
    if record.open or not Accessible(frame) then return end
    record.open = true
    openedWindows = openedWindows + 1
    if not M.active then return end
    ObserveOpen(frame)
    QueueCap()
    if frame == playerSpells and NS.Client.isForever then
        SetEscapeArmed(false)
        return
    end
    if not record.area or not IsFree(frame) then return end
    local combat = NS.InCombat()
    if CanClose(frame, false, combat)
        and (not CanClose(latest, false, combat) or shown[frame] > shown[latest]) then latest = frame end
    if not combat and not frame:IsProtected() and frame:IsToplevel() then frame:Raise() end
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

local function NativePanel(frame)
    local source = frame.GetSourceLocation and NS.PublicText(frame:GetSourceLocation())
    if source then
        local addon = source:match("[Aa]dd[Oo]ns[/\\](Blizzard_[%w_]+)")
        return addon ~= nil
    end
    return false
end

local function StandardLayout(info)
    local whileDead, allow, fit = info.whileDead, info.allowOtherPanels, info.checkFit
    local never, minimize, conditional, failed = info.neverAllowOtherPanels, info.autoMinimizeWithOtherPanels,
        info.autoMinimizeOnCondition, info.showFailedFunc
    local ignore = info.ignoreControlLost
    return NS.Public(whileDead) and whileDead == 1 and NS.Public(allow) and allow ~= 0
        and NS.Public(fit) and fit ~= 1 and NS.Public(never) and not never
        and NS.Public(minimize) and not minimize and NS.Public(conditional) and not conditional
        and NS.Public(failed) and not failed and NS.Public(ignore) and not ignore
end

prepare = function(frame, record)
    if not record.detachable or NativeOnly(record) or record.area or not Accessible(frame)
        or frame:IsShown() or frame:IsProtected() or frame:GetParent() ~= UIParent or OccupiesSlot(frame) then return end
    local area = record.layout
    local defined, current = frame:GetAttribute(DEFINED), frame:GetAttribute(AREA)
    if not NS.Public(defined) or not NS.Public(current) or defined and current ~= area then return end

    local points = frame:GetNumPoints()
    if NS.Public(points) and points == 0 then
        local offset = placementIndex % 7
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 28 + offset * 40, -100 - offset * 22)
        placementIndex = placementIndex + 1
    end
    SetUIPanelAttribute(frame, "area", nil)
    if not IsFree(frame) then return end
    record.area, ownedCount = area, ownedCount + 1
    if frame == _G.WorldMapFrame then
        map = frame
        record.maximized = frame:IsMaximized()
        EventRegistry:RegisterCallback("WorldMapMaximized", MapMaximized, M)
        EventRegistry:RegisterCallback("WorldMapMinimized", MapMinimized, M)
    end
end

local function TrackPanel(name, info, combat)
    if not NS.Public(name) or type(name) ~= "string" or childPanels[name]
        or not NS.Public(info) or type(info) ~= "table" then return end
    local frame = _G[name]
    if not Accessible(frame) or records[frame] or type(frame.HookScript) ~= "function"
        or frame:GetParent() ~= UIParent then return end
    local area = info.area
    if not NS.Public(area) then return end
    local known = reviewed[name] or name == "PlayerSpellsFrame" or name == "BankFrame"
    if not known and (not sideAreas[area] or not NativePanel(frame)) then return end
    local record = {
        layout = area,
        open = frame:IsShown(),
        combatClose = combatClose[name],
        detachable = sideAreas[area] and (reviewed[name] or StandardLayout(info)),
        nativeOnly = name == "PlayerSpellsFrame" or name == "BankFrame",
        -- The Forever map's quest pins and mailbox's emote need the native manager.
        foreverOnly = name == "MailFrame" or name == "WorldMapFrame",
        retailCap = reviewed[name] or name == "PlayerSpellsFrame",
    }
    records[frame] = record
    if name == "PlayerSpellsFrame" then playerSpells = frame end
    if record.open then
        openedWindows = openedWindows + 1
        ObserveOpen(frame)
    elseif combat then
        if record.detachable and not NativeOnly(record) then pendingLayout[frame] = true end
    else
        prepare(frame, record)
    end
    frame:HookScript("OnHide", OnHide)
    frame:HookScript("OnShow", OnShow)
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

-- Observe native calls after their frame scripts, including client builds
-- without panel events and shows where a frame's OnShow aborted.
local function OnNativeShow(frame)
    if not M.active or not NS.Public(frame) or not frame then return end
    local record = records[frame]
    if record and record.open or not Visible(frame) then return end
    if record then
        OnShow(frame)
        return
    end
    local name = NS.PublicText(frame:GetName())
    if not name or _G[name] ~= frame then return end
    TrackPanel(name, UIPanelWindows[name], true)
    if records[frame] then
        QueueCap()
        SyncEscape()
    end
end

local function OnNativeHide(frame)
    if M.active and NS.Public(frame) and frame and records[frame] then OnHide(frame) end
end

local function OnForceHide(_, frame)
    OnNativeHide(frame)
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

release = function(frame, record)
    if not record.area or not Accessible(frame) or frame:IsShown() or frame:IsProtected() then return end
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

local function DiscoverPanels(combat)
    for name, info in pairs(UIPanelWindows) do TrackPanel(name, info, combat) end
    AttachBagFrames()
end

local function OnEvent(_, event, key)
    if event == "ADDON_LOADED" then
        local addon = NS.PublicText(key)
        if addon and addon:find("Blizzard_", 1, true) == 1 then
            DiscoverPanels(NS.InCombat())
            QueueCap()
            SyncEscape()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        RestoreCompactMap(event)
        ApplyPendingLayout()
        if capAfterCombat then QueueCap() end
        capAfterCombat, latest = nil, nil
        SyncEscape(event)
    elseif event == "PLAYER_REGEN_DISABLED" then
        pendingClose, latest = nil, nil
        SyncEscape(event)
    elseif event == "GAME_PAD_ACTIVE_CHANGED" or NS.Public(key) and key == "InputDeviceInterfaceStyle" then
        SyncEscape(event)
    end
end

function M:Enable()
    if not watcher then
        watcher = CreateFrame("Frame", ESCAPE_FRAME)
        watcher:Hide()
        watcher:SetScript("OnEvent", OnEvent)
        watcher:SetScript("OnHide", OnEscapeFrameHidden)
        -- The native close pass already supports addon-owned windows.
        -- Registering an Escape callback would re-sort the shared protected dispatch.
        UISpecialFrames[#UISpecialFrames + 1] = ESCAPE_FRAME
        hooksecurefunc("ShowUIPanel", OnNativeShow)
        hooksecurefunc("HideUIPanel", OnNativeHide)
    end
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    if NS.Client.isForever then
        watcher:RegisterEvent("CVAR_UPDATE")
        watcher:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
    end
    EventRegistry:RegisterCallback("UIParentPanelManager.ForcePanelHide", OnForceHide, M)
    local combat = NS.InCombat()
    openedWindows = 0
    -- Windows the player opened while this option was disabled have no known order.
    for frame, record in pairs(records) do
        record.open = Visible(frame)
        if record.open then
            openedWindows = openedWindows + 1
            ObserveOpen(frame)
        elseif record.detachable and not NativeOnly(record) and not record.area then
            if combat then pendingLayout[frame] = true else prepare(frame, record) end
        end
    end
    DiscoverPanels(combat)
    SyncEscape()
    self:Refresh()
end

function M:Refresh()
    local previous = windowLimit
    windowLimit = S.Config("parallelWindows").windowLimit or 0
    if windowLimit ~= previous then QueueCap() end
end

function M:Disable()
    windowLimit, pendingCap, pendingClose, capAfterCombat = 0, nil, nil, nil
    if not watcher then return end
    SetEscapeArmed(false)
    latest = nil
    for frame in pairs(shown) do shown[frame] = nil end
    watcher:UnregisterEvent("ADDON_LOADED")
    EventRegistry:UnregisterCallback("UIParentPanelManager.ForcePanelHide", M)
    local combat = NS.InCombat()
    for frame, record in pairs(records) do
        if combat and record.area then pendingLayout[frame] = true else release(frame, record) end
    end
    if ownedCount == 0 then watcher:UnregisterAllEvents() end
end

S.Install("parallelWindows", M)
