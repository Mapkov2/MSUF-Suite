local root = assert(arg[1], "Suite root required")
local checks, combat, gamepad = 0, false, false
local events, deferred, occupied = {}, {}, {}
local module, watcher, escapeRegistered
local nativeEscape, stackReads = false, 0
local bagsOpen = true
local config = {}
local nativeAreaHook, nativeSpellWrite
local playerSpells
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

function CreateFrame(_, name)
    watcher = {
        shown = true,
        RegisterEvent = function(_, event) events[event] = true end,
        UnregisterEvent = function(_, event) events[event] = nil end,
        UnregisterAllEvents = function() events = {} end,
        SetScript = function(self, script, callback) self[script] = callback end,
        IsShown = function(self) return self.shown end,
        SetShown = function(self, shown)
            if self.shown == shown then return end
            self.shown = shown
            if not shown and self.OnHide then self:OnHide() end
        end,
    }
    function watcher:Hide() self:SetShown(false) end
    if name then _G[name] = watcher end
    return watcher
end
C_Timer = { After = function(_, callback) deferred[#deferred + 1] = callback end }
local function Flush()
    local jobs = deferred
    deferred = {}
    for _, job in ipairs(jobs) do job() end
end
local function Fire(event, ...)
    if events[event] then watcher.OnEvent(watcher, event, ...) end
end

UIParent, UIPanelWindows, UISpecialFrames = {}, {}, {}
local function Panel(name, area, protected)
    local frame = { name = name, protected = protected, shown = false, attr = {}, scripts = {} }
    function frame:GetParent() return UIParent end
    function frame:IsProtected() return self.protected, self.explicit end
    function frame:IsShown() return self.shown end
    function frame:IsToplevel() return true end
    function frame:Raise() self.raised = (self.raised or 0) + 1 end
    function frame:GetAttribute(key) return self.attr[key] end
    function frame:GetNumPoints() return self.point and 1 or 0 end
    function frame:GetPoint() if self.point then return unpack(self.point) end end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:HookScript(name, callback)
        assert(not self.scripts[name], "hooked twice")
        self.scripts[name] = callback
    end
    UIPanelWindows[name] = { area = area }
    _G[name] = frame
    return frame
end

local layout = "UIPanelLayout-area"
local defined = "UIPanelLayout-defined"
function SetUIPanelAttribute(frame, key, value)
    local native = nativeSpellWrite and frame == playerSpells and value ~= nil
    if not native then
        assert(not combat and not frame.explicit, "unsafe panel mutation")
        assert(not frame:IsShown() or frame == playerSpells and occupied.center ~= frame, "changed an occupied panel")
    end
    assert(key == "area" or native and key == "centerXOffset", "changed unrelated native metadata")
    if not frame.attr[defined] then
        for name, setting in pairs(UIPanelWindows[frame.name]) do
            frame.attr["UIPanelLayout-" .. name] = setting
        end
    end
    frame.attr[defined], frame.attr["UIPanelLayout-" .. key] = true, value
    if nativeAreaHook then nativeAreaHook(frame, key, value) end
end
-- Blizzard keeps this helper local to its panel manager.
GetUIPanelAttribute = nil
function UIPanelUpdateScaleForFit(frame, x, y)
    assert(frame == playerSpells and not combat and x == 200 and y == 140, "unexpected native scale-fit call")
    frame.fit = true
end
function hooksecurefunc(name, callback)
    assert(name == "SetUIPanelAttribute" and not nativeAreaHook, "unexpected native hook")
    nativeAreaHook = callback
end
function GetUIPanel(slot) return occupied[slot] end
local function NativeArea(frame)
    if frame.attr[defined] then return frame.attr[layout] end
    return UIPanelWindows[frame.name].area
end
function HideUIPanel(frame)
    if not frame.shown then return end
    local area = NativeArea(frame)
    if area and occupied[area] == frame then occupied[area] = nil end
    frame.shown, frame.closes = false, (frame.closes or 0) + 1
    if frame.scripts.OnHide then frame.scripts.OnHide(frame) end
end
local function NativeOpen(frame)
    local area = NativeArea(frame)
    if area then
        for _, slot in ipairs({ "doublewide", "left", "center" }) do
            if occupied[slot] and occupied[slot] ~= frame then HideUIPanel(occupied[slot]) end
        end
        occupied[area] = frame
    end
    frame.shown = true
    if frame.scripts.OnShow then frame.scripts.OnShow(frame) end
end
local function NativeSpellArea(area)
    nativeSpellWrite = true
    SetUIPanelAttribute(playerSpells, "area", area)
    nativeSpellWrite = false
end
GameMenuEscPriority = { AddOn = 8 }
function RegisterGameMenuEscHandler()
    escapeRegistered = true
end
function debugstack()
    stackReads = stackReads + 1
    return nativeEscape and "[Blizzard_GameMenuEsc/Blizzard_GameMenuEsc.lua]:101" or "[UIParentPanelManager.lua]:280"
end
local function CloseSpecialWindows()
    local found = false
    for _, name in ipairs(UISpecialFrames) do
        local window = _G[name]
        if window:IsShown() then
            window:Hide()
            found = true
        end
    end
    return found
end
local function Escape(casting)
    -- Registering the addon callback sorts and rewrites the shared native
    -- handler array before the protected Casting handler gets its turn.
    assert(not escapeRegistered, "Suite registered in the protected Escape dispatch")
    if casting then return "cast" end
    local hadBags = bagsOpen
    CloseAllBags()
    nativeEscape = true
    local closed = CloseSpecialWindows()
    nativeEscape = false
    return closed and "window" or hadBags and "bags" or "default"
end
InputUtil = { IsGamepadUIEnabled = function() return gamepad end }

local NS = {
    Client = { isForever = true },
    Safety = { IsForbidden = function(frame) return frame.forbidden end },
    InCombat = function(event) return event == "PLAYER_REGEN_DISABLED" or combat end,
    Public = function() return true end,
    Dispatch = function(callback, ...) return callback(...) end,
}
local S = {
    Install = function(id, instance) assert(id == "parallelWindows"); module = instance end,
    Config = function() return config end,
}
local auction = Panel("AuctionHouseFrame", "doublewide")
local quest = Panel("QuestLogPopupDetailFrame", "left")
local npcQuest = Panel("QuestFrame", "left")
local protected = Panel("ProfessionsFrame", "left", true)
local modal = Panel("CinematicFrame", "full")
local map = Panel("WorldMapFrame", "left")
map.preferCompact = true
function map:IsMaximized() return self.maximized == true end
function map:ShouldBeMinimized() return self.preferCompact end
local callbacks = {}
EventRegistry = {
    RegisterCallback = function(_, name, callback) callbacks[name] = callback end,
    UnregisterCallback = function(_, name) callbacks[name] = nil end,
}
local function ChangeMapSize(maximized)
    map.maximized = maximized
    local callback = callbacks[maximized and "WorldMapMaximized" or "WorldMapMinimized"]
    if callback then callback() end
    -- The native delegate leaves both slot moves alone for a nil map area.
    -- The maximize handler still applies the native full-size anchor.
    if maximized then map:SetPoint("TOP", UIParent, "TOP", 0, 0) end
end
local bag1, bag2 = Panel("ContainerFrame1"), Panel("ContainerFrame2")
function IsAnyBagOpen() return bagsOpen or bag1:IsShown() or bag2:IsShown() end
function CloseAllBags()
    bagsOpen = false
    HideUIPanel(bag1)
    HideUIPanel(bag2)
end
assert(loadfile(arg[2] or root .. "/MSUF_Suite_QualityOfLife/ParallelWindows.lua"))("MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })

NativeOpen(auction)
NativeOpen(quest)
Check(not auction:IsShown(), "fixture did not reproduce native eviction")
HideUIPanel(quest)
NativeOpen(auction)
module.active = true
module:Enable()
Check(auction:IsShown() and GetUIPanel("doublewide") == auction, "enabling broke the current auction session")
NativeOpen(map)
Check(map:IsShown() and auction:IsShown() and bagsOpen and GetUIPanel("left") == nil,
    "opening the small map with M evicted an existing panel")
map:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 180, -135)
ChangeMapSize(true)
Check(map:IsMaximized() and map.point[1] == "TOP" and auction:IsShown(), "maximizing a floating map changed native layout")
ChangeMapSize(false)
Check(map.point[1] == "TOPLEFT" and map.point[4] == 180 and map.point[5] == -135,
    "minimizing did not restore the compact map position")
HideUIPanel(map)
NativeOpen(quest)
Check(auction:IsShown() and quest:IsShown() and bagsOpen, "opening a quest detail closed the auction house or bags")
HideUIPanel(auction)
Flush()
Check(NativeArea(auction) == nil and GetUIPanel("doublewide") == nil, "auction did not float on its next open")
NativeOpen(auction)
NativeOpen(npcQuest)
Check(auction:IsShown() and quest:IsShown() and npcQuest:IsShown(), "independent panels evicted one another")
Check(quest.point[4] ~= auction.point[4] and auction.raised and npcQuest.raised, "floating windows lack independent placement")
Check(Escape(true) == "cast" and npcQuest:IsShown() and bagsOpen and stackReads == 0,
    "Escape interrupted native cast handling")
CloseSpecialWindows()
Flush()
Check(npcQuest:IsShown() and auction:IsShown() and quest:IsShown(), "native panel cleanup closed a floating window")
Check(Escape(false) == "window" and npcQuest:IsShown() and not bagsOpen,
    "Escape did not finish native cleanup before the floating window close")
Flush()
Check(not npcQuest:IsShown() and auction:IsShown() and quest:IsShown(), "Escape did not close only the newest floating window")
Check(watcher.OnUpdate == nil and watcher.OnKeyDown == nil, "Escape installed a polling or input handler")
NativeOpen(npcQuest)
Check(Escape(false) == "window", "reopening did not rearm Escape")
Fire("PLAYER_REGEN_DISABLED")
combat = true
Flush()
Check(npcQuest:IsShown() and not watcher:IsShown(), "a pending Escape close crossed into combat")
combat = false
Fire("PLAYER_REGEN_ENABLED")
HideUIPanel(npcQuest)
Flush()
Check(NativeArea(protected) == "left" and NativeArea(modal) == "full", "modified a protected or fullscreen window")
Check(UIPanelWindows.AuctionHouseFrame.area == "doublewide", "wrote to the native registration table")

Fire("PLAYER_REGEN_DISABLED")
Check(Escape(false) == "default", "the combat edge consumed Escape before lockdown")
combat = true
local journal = Panel("CollectionsJournal", "left")
Fire("ADDON_LOADED")
Check(NativeArea(journal) == "left" and Escape(false) == "default", "combat did not defer changes")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Check(NativeArea(journal) == nil, "did not apply to a late-loaded panel after combat")
gamepad = true
Fire("CVAR_UPDATE", "InputDeviceInterfaceStyle")
Check(Escape(false) == "default" and auction:IsShown(), "Escape intercepted Gamepad UI")
gamepad = false
Fire("GAME_PAD_ACTIVE_CHANGED")
Check(watcher:IsShown(), "returning to keyboard input did not rearm Escape")

module.active = false
module:Disable()
Check(auction:IsShown() and quest:IsShown() and NativeArea(journal) == "left",
    "disable closed live windows or failed to restore a hidden window")
HideUIPanel(auction)
HideUIPanel(quest)
Flush()
Check(NativeArea(auction) == "doublewide" and NativeArea(quest) == "left", "native layout was not restored after close")
Check(NativeArea(map) == "left" and next(callbacks) == nil, "disabling did not restore the native map")
Check(next(events) == nil and Escape(false) == "default", "disabled watchers still active")
NativeOpen(auction)
NativeOpen(quest)
Check(not auction:IsShown(), "disabling did not restore native eviction")

HideUIPanel(quest)
NativeOpen(auction)
map.preferCompact = false
ChangeMapSize(true)
module.active = true
module:Enable()
-- The native quest-log action opens the panel before changing its display
-- mode. It requests the compact map with the log regardless of the M preset.
NativeOpen(map)
ChangeMapSize(false)
map.questLogShown = true
Check(map:IsShown() and map.questLogShown and auction:IsShown() and GetUIPanel("left") == nil,
    "the quest-log action evicted an existing panel with the full-size preference")
Check(not map:IsMaximized() and map.point[1] == "TOPLEFT", "the quest-log action did not restore the compact anchor")
HideUIPanel(map)

-- Forever's group-finder key also opens a native left panel. On a narrow
-- screen it can replace the doublewide auction window if still managed.
local groupFinder = Panel("LFGParentFrame", "left")
Fire("ADDON_LOADED")
NativeOpen(groupFinder)
Check(groupFinder:IsShown() and auction:IsShown() and GetUIPanel("left") == nil,
    "opening the Forever group finder evicted an existing panel")
HideUIPanel(groupFinder)

-- M can still open the full-size map and run Blizzard's size transition.
NativeOpen(map)
ChangeMapSize(not map.preferCompact)
Check(map:IsMaximized() and map.point[1] == "TOP" and auction:IsShown(), "the full-size M action changed native geometry")
HideUIPanel(map)
module.active = false
module:Disable()
Check(NativeArea(map) == "left" and NativeArea(groupFinder) == "left" and next(callbacks) == nil,
    "disabling did not restore the native map and group finder")
-- N loads the native addon and selects its tab before calling ShowUIPanel.
HideUIPanel(auction)
module.active = true
module:Enable()
local retained = Panel("NativeCenterTest", "left")
NativeOpen(retained)
NativeOpen(auction)
playerSpells = Panel("PlayerSpellsFrame", "centerOrLeft", true)
playerSpells.explicit = false
UIPanelWindows.PlayerSpellsFrame.checkFit = 1
UIPanelWindows.PlayerSpellsFrame.checkFitExtraWidth = 200
UIPanelWindows.PlayerSpellsFrame.checkFitExtraHeight = 140
Fire("ADDON_LOADED")
bagsOpen = true
NativeSpellArea("center")
NativeOpen(playerSpells)
Check(playerSpells:IsShown() and playerSpells.fit and retained:IsShown() and auction:IsShown() and bagsOpen
    and GetUIPanel("center") == nil, "opening Talents with N closed another native window or skipped scale to fit")
NativeSpellArea("left")
HideUIPanel(playerSpells)
NativeSpellArea("centerOrLeft")
NativeOpen(playerSpells)
Check(NativeArea(playerSpells) == nil and playerSpells:IsShown() and retained:IsShown() and auction:IsShown(),
    "switching or resizing the spellbook returned it to native slots")
module.active = false
module:Disable()
Check(playerSpells:IsShown(), "disable closed an open spell window")
HideUIPanel(playerSpells)
HideUIPanel(retained)
HideUIPanel(auction)
Flush()
Check(NativeArea(playerSpells) == "centerOrLeft", "disable did not restore the latest native spell area")

module.active = true
module:Enable()
playerSpells.explicit = true
NativeSpellArea("center")
Check(NativeArea(playerSpells) == "center", "modified explicitly protected spell root")
playerSpells.explicit = false
gamepad = true
NativeSpellArea("center")
Check(NativeArea(playerSpells) == "center", "modified native Gamepad spell layout")
gamepad = false
combat = true
NativeSpellArea("center")
Check(NativeArea(playerSpells) == "center", "modified spell area in combat")
combat = false
NativeOpen(playerSpells)
NativeSpellArea("center")
Check(GetUIPanel("center") == playerSpells and NativeArea(playerSpells) == "center", "stranded a native spell slot")
HideUIPanel(playerSpells)
-- Native resizes hide first, update their fit offset, then show internally.
nativeSpellWrite = true
SetUIPanelAttribute(playerSpells, "centerXOffset", 0)
nativeSpellWrite = false
NativeOpen(retained)
NativeOpen(playerSpells)
Check(retained:IsShown() and NativeArea(playerSpells) == nil, "native resize reopened the spells frame in a managed slot")
HideUIPanel(retained)
HideUIPanel(playerSpells)
Flush()

-- Opening order includes bags and existing managed panels. Native same-tick
-- hide/show transitions retain their order; a completed close removes it.
local function ResetWindows()
    config.windowLimit = 0
    module:Refresh()
    for _, frame in ipairs({ auction, quest, npcQuest, protected, map, groupFinder, playerSpells, retained }) do
        HideUIPanel(frame)
    end
    CloseAllBags()
    Flush()
    Flush()
end
local function Limit(value)
    config.windowLimit = value
    module:Refresh()
    Flush()
end

ResetWindows()
Limit(2)
NativeOpen(bag1)
NativeOpen(bag2)
Flush()
NativeOpen(auction)
Flush()
Check(auction:IsShown() and bag1:IsShown() and bag2:IsShown(), "separate bags counted as multiple windows")
NativeOpen(quest)
Check(auction:IsShown() and quest:IsShown() and bag1:IsShown(), "cap ran inside the native show")
Flush()
Check(not bag1:IsShown() and not bag2:IsShown() and auction:IsShown() and quest:IsShown(),
    "the oldest bag group was counted but never closed")
NativeOpen(map)
Flush()
Check(not auction:IsShown() and quest:IsShown() and map:IsShown(), "cap did not keep closing in opening order")

ResetWindows()
NativeOpen(auction)
Flush()
NativeOpen(quest)
Flush()
NativeOpen(map)
Flush()
Limit(2)
Check(not auction:IsShown() and quest:IsShown() and map:IsShown(), "lowering the limit did not apply to open windows")

ResetWindows()
Limit(3)
NativeSpellArea("center")
NativeOpen(playerSpells)
Flush()
NativeOpen(auction)
Flush()
NativeOpen(quest)
Flush()
-- The native spellbook resize hides and reopens its root synchronously.
HideUIPanel(playerSpells)
nativeSpellWrite = true
SetUIPanelAttribute(playerSpells, "centerXOffset", 0)
nativeSpellWrite = false
NativeOpen(playerSpells)
Flush()
NativeOpen(map)
Flush()
Check(not playerSpells:IsShown() and auction:IsShown() and quest:IsShown() and map:IsShown(),
    "an internal spellbook resize moved the oldest window to the end")

ResetWindows()
Limit(2)
NativeOpen(auction)
Flush()
NativeOpen(quest)
Flush()
HideUIPanel(auction)
Flush()
NativeOpen(auction)
Flush()
NativeOpen(map)
Flush()
Check(not quest:IsShown() and auction:IsShown() and map:IsShown(),
    "a manually closed and reopened window retained its old opening order")

ResetWindows()
module.active = false
module:Disable()
Flush()
NativeOpen(auction)
NativeOpen(bag1)
module.active = true
module:Enable()
Limit(2)
NativeOpen(quest)
Flush()
Check(not auction:IsShown() and bag1:IsShown() and quest:IsShown(),
    "an existing managed window was counted but excluded from FIFO closure")

ResetWindows()
Limit(2)
NativeOpen(protected)
Flush()
NativeOpen(auction)
Flush()
NativeOpen(quest)
Flush()
Check(protected:IsShown() and quest:IsShown() and not auction:IsShown(), "cap closed a protected or newly opened window")
NativeOpen(auction)
HideUIPanel(auction)
Flush()
Check(protected:IsShown() and quest:IsShown(), "a window closed before the cap pass still evicted another window")
NativeOpen(auction)
Fire("PLAYER_REGEN_DISABLED")
combat = true
Flush()
Check(protected:IsShown() and quest:IsShown() and auction:IsShown(), "a queued cap crossed into combat")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Flush()
Check(protected:IsShown() and quest:IsShown() and auction:IsShown(), "combat end replayed a stale cap")
config.windowLimit = 0
module:Refresh()
NativeSpellArea("center")
NativeOpen(playerSpells)
Flush()
Check(protected:IsShown() and quest:IsShown() and auction:IsShown() and playerSpells:IsShown(),
    "unlimited mode closed a supported window")

ResetWindows()
Limit(2)
NativeOpen(auction)
NativeOpen(quest)
NativeOpen(map)
HideUIPanel(map)
Flush()
Check(auction:IsShown() and quest:IsShown(), "a closed last opener caused unnecessary eviction")
NativeOpen(map)
NativeOpen(npcQuest)
HideUIPanel(npcQuest)
Flush()
Check(not auction:IsShown() and quest:IsShown() and map:IsShown(),
    "a closed last opener cancelled a required earlier cap")

ResetWindows()
NativeOpen(bag1)
Flush()
NativeOpen(auction)
Flush()
Limit(2)
NativeOpen(bag2)
auction.scripts.OnHide(auction)
auction.scripts.OnShow(auction)
Flush()
Check(auction:IsShown() and bag1:IsShown(), "inherited visibility counted an additional window")
NativeOpen(quest)
Flush()
Check(not bag1:IsShown() and not bag2:IsShown() and auction:IsShown() and quest:IsShown(),
    "opening an extra bag reset the bag group's age")
Check(watcher.OnUpdate == nil and watcher.OnKeyDown == nil, "window limits installed polling or an input handler")
-- All opening orders and limits for the same four independent windows.
local sequence, used = {}, {}
local candidates = { auction, quest, map, bag1 }
local permutations = 0
local function VerifyOrder()
    for limit = 1, #candidates do
        ResetWindows()
        Limit(limit)
        for index, frame in ipairs(sequence) do
            NativeOpen(frame)
            Flush()
            for earlier = 1, index do
                Check(sequence[earlier]:IsShown() == (earlier > index - limit),
                    "FIFO differs from the last N open windows")
            end
        end
    end
    permutations = permutations + 1
end
local function Permute(depth)
    if depth > #candidates then VerifyOrder() return end
    for index, frame in ipairs(candidates) do
        if not used[index] then
            sequence[depth], used[index] = frame, true
            Permute(depth + 1)
            used[index] = nil
        end
    end
end
Permute(1)
Check(permutations == 24, "opening-order coverage is incomplete")

ResetWindows()
NativeOpen(auction)
Flush()
NativeOpen(quest)
Flush()
HideUIPanel(auction)
NativeOpen(auction)
Flush()
Escape(false)
Flush()
Check(auction:IsShown() and not quest:IsShown(), "a same-tick layout transition changed Escape order")
print("Suite parallel windows: " .. checks .. " checks passed")
