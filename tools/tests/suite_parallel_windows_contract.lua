local root = assert(arg[1], "Suite root required")
local checks, combat, gamepad = 0, false, false
local events, deferred, occupied, callbacks = {}, {}, {}, {}
local module, watcher, escapeRegistered
local nativeEscape, stackReads = false, 0
local directCombatCloses, sourceReads, panelLookups = 0, 0, 0
local hiddenStack = {}
local bagsOpen = true
local nativeBagOwner
local config = {}
local nativeAreaHook, nativeShowHook, nativeHideHook, nativeSpellWrite
local addonSpellCloses, addonSpellAreaWrites = 0, 0
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
    if not events[event] then return end
    if event == "ADDON_LOADED" and select("#", ...) == 0 then
        watcher.OnEvent(watcher, event, "Blizzard_Test")
    else
        watcher.OnEvent(watcher, event, ...)
    end
end

UIParent, UIPanelWindows, UISpecialFrames = {}, {}, {}
local layout = "UIPanelLayout-area"
local defined = "UIPanelLayout-defined"
local function Panel(name, area, protected)
    local frame = { name = name, protected = protected, shown = false, attr = {}, scripts = {} }
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent or UIParent end
    function frame:GetSourceLocation() sourceReads = sourceReads + 1 return self.source end
    function frame:IsProtected() return self.protected, self.explicit end
    function frame:IsShown() return self.shown end
    function frame:IsToplevel() return true end
    function frame:Raise()
        assert(not combat, "addon raised a window in combat")
        self.raised = (self.raised or 0) + 1
    end
    function frame:Hide()
        assert(combat and not self.protected and not self.attr[layout],
            "direct addon hide touched a protected or managed panel")
        directCombatCloses = directCombatCloses + 1
        HideUIPanel(self)
    end
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

function SetUIPanelAttribute(frame, key, value)
    local native = nativeSpellWrite and frame == playerSpells and value ~= nil
    if not native then
        if frame == playerSpells then addonSpellAreaWrites = addonSpellAreaWrites + 1 end
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
function UIPanelUpdateScaleForFit()
    error("Suite replaced the native spell window's scale-to-fit call")
end
function hooksecurefunc(name, callback)
    if name == "ShowUIPanel" and not nativeShowHook then
        nativeShowHook = callback
    elseif name == "HideUIPanel" and not nativeHideHook then
        nativeHideHook = callback
    else
        assert(name == "SetUIPanelAttribute" and not nativeAreaHook, "unexpected native hook")
        nativeAreaHook = callback
    end
end
function GetUIPanel(slot)
    panelLookups = panelLookups + 1
    return occupied[slot]
end
local function NativeArea(frame)
    if frame.attr[defined] then return frame.attr[layout] end
    return UIPanelWindows[frame.name].area
end
function HideUIPanel(frame)
    if not frame.shown then return end
    local area = NativeArea(frame)
    if area and occupied[area] == frame then occupied[area] = nil end
    frame.shown, frame.closes = false, (frame.closes or 0) + 1
    if frame.nativeHide then frame:nativeHide() end
    if frame.scripts.OnHide and not frame.skipHideHook then frame.scripts.OnHide(frame) end
    if nativeHideHook then nativeHideHook(frame) end
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
    if frame.nativeShow then frame:nativeShow() end
    if frame.scripts.OnShow and not frame.skipShowHook then frame.scripts.OnShow(frame) end
    if nativeShowHook then nativeShowHook(frame) end
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
    local closed = playerSpells and occupied[NativeArea(playerSpells)] == playerSpells
    if closed then HideUIPanel(playerSpells) end
    closed = CloseSpecialWindows() or closed
    nativeEscape = false
    return closed and "window" or hadBags and "bags" or "default"
end
InputUtil = { IsGamepadUIEnabled = function() return gamepad end }

local NS
NS = {
    Client = { isForever = true },
    Safety = { IsForbidden = function(frame) return frame.forbidden end },
    InCombat = function(event) return event == "PLAYER_REGEN_DISABLED" or combat end,
    Public = function(value) return value ~= hiddenStack end,
    PublicText = function(value) return type(value) == "string" and value end,
    Dispatch = function(callback, ...)
        if callback == HideUIPanel or callback == CloseAllBags then
            assert(not combat, "addon called a native managed close during combat")
        end
        if NS.Client.isForever and callback == HideUIPanel then
            Check(not NativeArea((...)), "a Forever addon close called the native panel delegate")
        end
        if callback == HideUIPanel and playerSpells and select(1, ...) == playerSpells then
            addonSpellCloses = addonSpellCloses + 1
        end
        return callback(...)
    end,
}
local S = {
    Install = function(id, instance) assert(id == "parallelWindows"); module = instance end,
    Config = function() return config end,
    GamepadUI = function() return InputUtil.IsGamepadUIEnabled() end,
}
local auction = Panel("AuctionHouseFrame", "doublewide")
local encounter = Panel("EncounterJournal", "left")
local guild = Panel("GuildBankFrame", "left")
local quest = Panel("QuestLogPopupDetailFrame", "left")
local npcQuest = Panel("QuestFrame", "left")
local protected = Panel("ProfessionsFrame", "left", true)
local modal = Panel("CinematicFrame", "full")
local mail = Panel("MailFrame", "left")
local map = Panel("WorldMapFrame", "left")
map.preferCompact = true
function map:IsMaximized() return self.maximized == true end
function map:ShouldBeMinimized() return self.preferCompact end
EventRegistry = {
    RegisterCallback = function(_, name, callback) callbacks[name] = callback end,
    UnregisterCallback = function(_, name) callbacks[name] = nil end,
}
local function ChangeMapSize(maximized)
    map.maximized = maximized
    local callback = callbacks[maximized and "WorldMapMaximized" or "WorldMapMinimized"]
    if callback then callback() end
    -- With a panel slot Blizzard also reapplies the compact anchor.
    if maximized then map:SetPoint("TOP", UIParent, "TOP", 0, 0)
    elseif NativeArea(map) then map:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 28, -100) end
end
local bag1, bag2 = Panel("ContainerFrame1"), Panel("ContainerFrame2")
function IsAnyBagOpen() return bagsOpen or bag1:IsShown() or bag2:IsShown() end
function CloseAllBags(frame)
    if frame and frame ~= nativeBagOwner then return end
    nativeBagOwner = nil
    bagsOpen = false
    HideUIPanel(bag1)
    HideUIPanel(bag2)
end
assert(loadfile(arg[2] or root .. "/MSUF_Suite_QualityOfLife/ParallelWindows.lua"))("MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })

NativeOpen(auction)
NativeOpen(encounter)
Check(not auction:IsShown(), "fixture did not reproduce native eviction")
HideUIPanel(encounter)
NativeOpen(auction)
module.active = true
module:Enable()
Check(auction:IsShown() and GetUIPanel("doublewide") == auction, "enabling broke the current auction session")
Check(NativeArea(map) == "left" and map.attr[defined] == nil,
    "Forever map lost its native panel dispatch before combat")
Check(NativeArea(mail) == "left" and mail.attr[defined] == nil and mail.point == nil,
    "Forever mailbox layout was written by the addon before the first native open")
HideUIPanel(auction)
Flush()
NativeOpen(auction)

-- These three native panels all have left/pushable=0. The outgoing frame's
-- OnHide runs before the next view's OnShow can reuse QuestInfo.
local questInfoView, dialogueCloses
npcQuest.nativeShow = function()
    Check(not quest:IsShown() and not map:IsShown(), "NPC built QuestInfo over another quest view")
    questInfoView = "offer"
end
npcQuest.nativeHide = function()
    dialogueCloses = (dialogueCloses or 0) + 1
end
local function RenderLog()
    Check(not npcQuest:IsShown(), "quest log replaced the active NPC reward state")
    questInfoView = "log"
end
quest.nativeShow, map.nativeShow = RenderLog, RenderLog
NativeOpen(npcQuest)
Check(questInfoView == "offer" and auction:IsShown(), "opening an NPC quest closed an unrelated floating panel")
questInfoView = "reward"
Flush()
Check(npcQuest:IsShown() and questInfoView == "reward" and not dialogueCloses,
    "standalone hand-in lost access to its native reward choice")
NativeOpen(encounter)
Check(npcQuest:IsShown() and questInfoView == "reward" and encounter:IsShown(),
    "an unrelated floating window disrupted hand-in")
HideUIPanel(encounter)
NativeOpen(map)
Check(not npcQuest:IsShown() and GetUIPanel("left") == map and dialogueCloses == 1 and questInfoView == "log",
    "native map did not replace the NPC dialogue before reusing QuestInfo")
NativeOpen(npcQuest)
Check(not map:IsShown() and GetUIPanel("left") == npcQuest and questInfoView == "offer",
    "NPC quest dialogue did not replace the native map")
NativeOpen(quest)
Check(not npcQuest:IsShown() and quest:IsShown() and GetUIPanel("left") == quest and dialogueCloses == 2,
    "quest detail popup did not replace the NPC quest dialogue")
NativeOpen(npcQuest)
Check(not quest:IsShown() and npcQuest:IsShown(),
    "NPC quest dialogue did not replace the quest detail popup")
HideUIPanel(npcQuest)
npcQuest.nativeShow, npcQuest.nativeHide, quest.nativeShow, map.nativeShow = nil, nil, nil, nil
Flush()

Fire("PLAYER_REGEN_DISABLED")
combat = true
NativeOpen(map)
Check(map:IsShown() and auction:IsShown() and bagsOpen and GetUIPanel("left") == map,
    "Forever combat map did not use its native slot alongside the floating auction house")
HideUIPanel(map)
Check(not map:IsShown() and GetUIPanel("left") == nil and NativeArea(map) == "left",
    "Forever combat map did not close through the native panel manager")
combat = false
Fire("PLAYER_REGEN_ENABLED")
NativeOpen(map)
ChangeMapSize(true)
Check(map:IsMaximized() and map.point[1] == "TOP" and auction:IsShown(), "maximizing the map changed native layout")
ChangeMapSize(false)
Check(map.point[1] == "TOPLEFT" and map.point[4] == 28 and map.point[5] == -100,
    "Blizzard did not restore the compact map position")
HideUIPanel(map)
NativeOpen(encounter)
Check(auction:IsShown() and encounter:IsShown() and bagsOpen, "opening the encounter journal closed the auction house or bags")
HideUIPanel(auction)
Flush()
Check(NativeArea(auction) == nil and GetUIPanel("doublewide") == nil, "auction did not float on its next open")
NativeOpen(auction)
NativeOpen(guild)
Check(auction:IsShown() and encounter:IsShown() and guild:IsShown(), "independent panels evicted one another")
Check(encounter.point[4] ~= auction.point[4] and auction.raised and guild.raised, "floating windows lack independent placement")
Check(Escape(true) == "cast" and guild:IsShown() and bagsOpen and stackReads == 0,
    "Escape interrupted native cast handling")
local readStack = debugstack
for _, read in ipairs({ function() return hiddenStack end, function() return nil end }) do
    debugstack = read
    CloseSpecialWindows()
    Flush()
    Check(guild:IsShown() and auction:IsShown(), "unreadable stack closed a floating window")
end
debugstack = readStack
CloseSpecialWindows()
Flush()
Check(guild:IsShown() and auction:IsShown() and encounter:IsShown(), "native panel cleanup closed a floating window")
Check(Escape(false) == "window" and guild:IsShown() and not bagsOpen,
    "Escape did not finish native cleanup before the floating window close")
Flush()
Check(not guild:IsShown() and auction:IsShown() and encounter:IsShown(), "Escape did not close only the newest floating window")
Check(watcher.OnUpdate == nil and watcher.OnKeyDown == nil, "Escape installed a polling or input handler")
NativeOpen(guild)
Check(Escape(false) == "window", "reopening did not rearm Escape")
Fire("PLAYER_REGEN_DISABLED")
combat = true
Flush()
Check(guild:IsShown() and encounter:IsShown(), "a pending Escape close crossed into combat")
combat = false
Fire("PLAYER_REGEN_ENABLED")
HideUIPanel(guild)
Flush()
Check(NativeArea(protected) == "left" and NativeArea(modal) == "full", "modified a protected or fullscreen window")
Check(UIPanelWindows.AuctionHouseFrame.area == "doublewide", "wrote to the native registration table")

HideUIPanel(encounter)
Flush()
Fire("PLAYER_REGEN_DISABLED")
Check(Escape(false) == "default", "a native-only combat window consumed Escape")
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
NativeOpen(encounter)

module.active = false
module:Disable()
Check(auction:IsShown() and encounter:IsShown() and NativeArea(journal) == "left",
    "disable closed live windows or failed to restore a hidden window")
HideUIPanel(auction)
HideUIPanel(encounter)
Flush()
Check(NativeArea(auction) == "doublewide" and NativeArea(encounter) == "left", "native layout was not restored after close")
Check(NativeArea(map) == "left" and next(callbacks) == nil, "disabling did not restore the native map")
Check(next(events) == nil and Escape(false) == "default", "disabled watchers still active")
NativeOpen(auction)
NativeOpen(encounter)
Check(not auction:IsShown(), "disabling did not restore native eviction")

HideUIPanel(encounter)
map.preferCompact = false
ChangeMapSize(true)
module.active = true
module:Enable()
NativeOpen(auction)
-- The native quest-log action opens the panel before changing its display
-- mode. It requests the compact map with the log regardless of the M preset.
NativeOpen(map)
ChangeMapSize(false)
map.questLogShown = true
Check(map:IsShown() and map.questLogShown and auction:IsShown() and GetUIPanel("left") == map,
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
-- Forever's shared spells root uses Blizzard's panel manager for all tabs.
HideUIPanel(auction)
module.active = true
module:Enable()
local retained = Panel("NativeCenterTest", "left")
NativeOpen(auction)
playerSpells = Panel("PlayerSpellsFrame", "centerOrLeft", true)
playerSpells.explicit = false
UIPanelWindows.PlayerSpellsFrame.checkFit = 1
UIPanelWindows.PlayerSpellsFrame.checkFitExtraWidth = 200
UIPanelWindows.PlayerSpellsFrame.checkFitExtraHeight = 140
Fire("ADDON_LOADED")
Check(playerSpells.attr[defined] == nil, "loading PlayerSpells wrote its panel metadata")
bagsOpen = true
for _, area in ipairs({ "center", "left", "centerOrLeft" }) do
    NativeSpellArea(area)
    Check(NativeArea(playerSpells) == area, "Suite rewrote a native spell tab's area")
    NativeOpen(playerSpells)
    Check(playerSpells:IsShown() and auction:IsShown() and bagsOpen and GetUIPanel(area) == playerSpells,
        "spell tab opening bypassed the native panel slot or closed a floating panel")
    HideUIPanel(playerSpells)
    Check(not playerSpells:IsShown() and GetUIPanel(area) == nil, "native spell tab close missed its panel slot")
end
nativeSpellWrite = true
SetUIPanelAttribute(playerSpells, "centerXOffset", 0)
nativeSpellWrite = false
Check(NativeArea(playerSpells) == "centerOrLeft" and addonSpellAreaWrites == 0 and nativeAreaHook == nil,
    "Suite attached a hook or rewrote the native spell panel area during resize")
HideUIPanel(auction)
CloseAllBags()
Flush()
NativeOpen(auction)
NativeOpen(playerSpells)
Check(Escape(false) == "window" and not playerSpells:IsShown() and auction:IsShown(),
    "native Escape did not close only the managed spells window immediately")
Flush()
Check(auction:IsShown() and addonSpellCloses == 0, "one Escape also closed a floating window")
Check(Escape(false) == "window" and auction:IsShown(), "native spells close did not rearm floating-window Escape")
Flush()
Check(not auction:IsShown(), "next Escape did not close the floating window")

module.active = false
module:Disable()
Check(NativeArea(playerSpells) == "centerOrLeft", "disable changed the native spell window layout")
module.active = true
module:Enable()

-- Opening order includes bags and existing managed panels. Native same-tick
-- hide/show transitions retain their order; a completed close removes it.
local function ResetWindows()
    config.windowLimit = 0
    module:Refresh()
    for _, frame in ipairs({ auction, encounter, guild, quest, npcQuest, protected, map, groupFinder, playerSpells, retained, mail }) do
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
NativeOpen(encounter)
Check(auction:IsShown() and encounter:IsShown() and bag1:IsShown(), "cap ran inside the native show")
Flush()
Check(not bag1:IsShown() and not bag2:IsShown() and auction:IsShown() and encounter:IsShown(),
    "the oldest bag group was counted but never closed")
NativeOpen(map)
Flush()
Check(not auction:IsShown() and encounter:IsShown() and map:IsShown(), "cap did not keep closing in opening order")

ResetWindows()
Limit(2)
NativeOpen(map)
Flush()
NativeOpen(auction)
Flush()
NativeOpen(encounter)
Flush()
Check(map:IsShown() and not auction:IsShown() and encounter:IsShown(),
    "the Forever cap did not preserve the native map and close the oldest floating window")

ResetWindows()
Limit(2)
-- MailFrame_Show first reads the native layout area in ShowUIPanel, then
-- opens bags and updates the inbox before its protected reading emote.
NativeOpen(mail)
Check(GetUIPanel("left") == mail, "Forever mailbox bypassed the native panel dispatcher")
Flush()
NativeOpen(auction)
Flush()
NativeOpen(encounter)
Flush()
Check(mail:IsShown() and not auction:IsShown() and encounter:IsShown(),
    "the cap did not count the native mailbox or close the oldest eligible window")
HideUIPanel(mail)
Flush()
Check(NativeArea(mail) == "left" and mail.attr[defined] == nil,
    "Forever mailbox layout was rewritten after native close")

ResetWindows()
Limit(1)
-- Another addon can detach the mailbox. Neither Suite close path should own it.
mail.attr[defined] = true
NativeOpen(mail)
Flush()
NativeOpen(auction)
Flush()
Check(mail:IsShown() and auction:IsShown(), "the cap addon-closed a floating Forever mailbox")
Escape(false)
Flush()
Escape(false)
Flush()
Check(mail:IsShown() and not auction:IsShown(), "Escape did not leave the floating Forever mailbox to Blizzard")
HideUIPanel(mail)
Flush()
mail.attr[defined] = nil

ResetWindows()
local character = Panel("CharacterFrame", "left")
local combined = Panel("ContainerFrameCombinedBags")
local closeBags = CloseAllBags
function CloseAllBags()
    Check(not (gamepad and combined:IsShown() and character:IsShown()),
        "the Forever cap would run native ToggleCharacter from the combined bags' OnHide")
    closeBags()
    HideUIPanel(combined)
end
Fire("ADDON_LOADED")
Limit(3)
gamepad = true
NativeOpen(combined)
Flush()
NativeOpen(character)
Flush()
NativeOpen(encounter)
Flush()
NativeOpen(auction)
Flush()
Check(combined:IsShown() and character:IsShown() and not encounter:IsShown() and auction:IsShown(),
    "the cap did not leave the combined bags and character window to the Gamepad UI")
gamepad = false
HideUIPanel(character)
ResetWindows()
CloseAllBags = closeBags

ResetWindows()
NativeOpen(auction)
Flush()
NativeOpen(encounter)
Flush()
NativeOpen(map)
Flush()
Limit(2)
Check(not auction:IsShown() and encounter:IsShown() and map:IsShown(), "lowering the limit did not apply to open windows")

ResetWindows()
Limit(3)
NativeSpellArea("center")
NativeOpen(playerSpells)
Flush()
NativeOpen(auction)
Flush()
NativeOpen(encounter)
Flush()
-- A same-tick native resize does not detach the spell panel or give it a Suite close path.
HideUIPanel(playerSpells)
nativeSpellWrite = true
SetUIPanelAttribute(playerSpells, "centerXOffset", 0)
nativeSpellWrite = false
NativeOpen(playerSpells)
Flush()
NativeOpen(groupFinder)
Flush()
Check(playerSpells:IsShown() and not auction:IsShown() and encounter:IsShown() and groupFinder:IsShown(),
    "cap did not count the spell window or skipped the oldest eligible floating window")
Check(addonSpellCloses == 0, "the cap closed the native spells window")

ResetWindows()
Limit(1)
NativeOpen(playerSpells)
Flush()
NativeOpen(auction)
Flush()
Check(playerSpells:IsShown() and auction:IsShown() and addonSpellCloses == 0,
    "cap closed the native spells window or the newest opener when neither was eligible")
HideUIPanel(playerSpells)
Flush()
Check(auction:IsShown(), "a native spells close evicted the remaining window")

ResetWindows()
Limit(2)
NativeOpen(auction)
Flush()
NativeOpen(encounter)
Flush()
HideUIPanel(auction)
Flush()
NativeOpen(auction)
Flush()
NativeOpen(map)
Flush()
Check(not encounter:IsShown() and auction:IsShown() and map:IsShown(),
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
NativeOpen(encounter)
Flush()
Check(auction:IsShown() and not bag1:IsShown() and encounter:IsShown(),
    "the Forever cap did not count the existing managed window and close the oldest eligible group")

ResetWindows()
Limit(2)
NativeOpen(protected)
Flush()
NativeOpen(auction)
Flush()
NativeOpen(encounter)
Flush()
Check(protected:IsShown() and encounter:IsShown() and not auction:IsShown(), "cap closed a protected or newly opened window")
NativeOpen(auction)
HideUIPanel(auction)
Flush()
Check(protected:IsShown() and encounter:IsShown(), "a window closed before the cap pass still evicted another window")
NativeOpen(auction)
Fire("PLAYER_REGEN_DISABLED")
combat = true
Flush()
Check(protected:IsShown() and encounter:IsShown() and auction:IsShown() and directCombatCloses == 0,
    "combat cap closed a window without a reviewed combat close path")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Flush()
Check(protected:IsShown() and not encounter:IsShown() and auction:IsShown(),
    "pending cap skipped the oldest eligible window after combat")
ResetWindows()
Limit(2)
NativeOpen(auction)
NativeOpen(guild)
Fire("PLAYER_REGEN_DISABLED")
combat = true
NativeOpen(map)
Flush()
Check(auction:IsShown() and guild:IsShown() and map:IsShown(), "combat cap closed a native interaction")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Flush()
Check(not auction:IsShown() and guild:IsShown() and map:IsShown(), "pending cap did not settle after combat")
HideUIPanel(map)
HideUIPanel(guild)
NativeOpen(encounter)
NativeOpen(auction)
Flush()
config.windowLimit = 0
module:Refresh()
NativeSpellArea("center")
NativeOpen(playerSpells)
Flush()
Check(encounter:IsShown() and auction:IsShown() and playerSpells:IsShown() and addonSpellCloses == 0,
    "unlimited mode closed a supported floating window or the native spells window")

ResetWindows()
Limit(2)
NativeOpen(auction)
NativeOpen(encounter)
NativeOpen(map)
HideUIPanel(map)
Flush()
Check(auction:IsShown() and encounter:IsShown(), "a closed last opener caused unnecessary eviction")
NativeOpen(map)
NativeOpen(guild)
HideUIPanel(guild)
Flush()
Check(not auction:IsShown() and encounter:IsShown() and map:IsShown(),
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
NativeOpen(encounter)
Flush()
Check(not bag1:IsShown() and not bag2:IsShown() and auction:IsShown() and encounter:IsShown(),
    "opening an extra bag reset the bag group's age")
Check(watcher.OnUpdate == nil and watcher.OnKeyDown == nil, "window limits installed polling or an input handler")
-- All opening orders and limits for the same four independent windows.
local sequence, used = {}, {}
local candidates = { auction, encounter, guild, bag1 }
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
NativeOpen(encounter)
Flush()
HideUIPanel(auction)
NativeOpen(auction)
Flush()
Escape(false)
Flush()
Check(auction:IsShown() and not encounter:IsShown(), "a same-tick layout transition changed Escape order")

ResetWindows()
module.active = false
module:Disable()
NS.Client.isForever = false
ChangeMapSize(false)
module.active = true
module:Enable()
NativeOpen(auction)
NativeOpen(map)
Check(NativeArea(map) == nil and map:IsShown() and auction:IsShown(), "Retail map lost floating-window support")
NativeOpen(mail)
Check(NativeArea(mail) == nil and mail:IsShown() and auction:IsShown(), "Retail mailbox lost floating-window support")
NativeOpen(quest)
NativeOpen(npcQuest)
Check(NativeArea(quest) == nil and NativeArea(npcQuest) == nil and quest:IsShown() and npcQuest:IsShown(),
    "Retail quest windows lost floating-window support")

map:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 180, -135)
ChangeMapSize(true)
ChangeMapSize(false)
Check(map.point[1] == "TOPLEFT" and map.point[4] == 180 and map.point[5] == -135,
    "Retail map lost its floating compact position")
ResetWindows()
Limit(1)
NativeOpen(playerSpells)
Flush()
NativeOpen(auction)
Flush()
Check(not playerSpells:IsShown() and auction:IsShown() and addonSpellCloses == 1,
    "Retail spells lost the existing managed-window cap handling")
ResetWindows()
local calendar = Panel("CalendarFrame", "doublewide")
calendar.skipShowHook, calendar.skipHideHook = true, true
local social = Panel("SocialUIFrame", "left")
local macro = Panel("MacroFrame", "left")
local newWindow = Panel("NativeFutureWindow", "centerOrLeft")
local nativeInteraction = Panel("UnreviewedInteractionFrame", "left")
local foreign = Panel("ForeignAddonWindow", "left")
for _, frame in ipairs({calendar, social, macro, newWindow, nativeInteraction, foreign}) do
    frame.source = "Interface/AddOns/Blizzard_Future"
end
macro.source = "Interface\\AddOns\\Blizzard_MacroUI\\Blizzard_MacroUI.xml"
foreign.source = "Interface/AddOns/ThirdParty/CustomPanel.xml"
for _, frame in ipairs({calendar, social, macro, newWindow, foreign}) do
    UIPanelWindows[frame.name].whileDead = 1
end
Fire("ADDON_LOADED", "ThirdParty")
Check(calendar.attr[defined] == nil, "third-party load triggered native discovery")
Fire("ADDON_LOADED", "Blizzard_Calendar")
Check(NativeArea(calendar) == nil and NativeArea(social) == nil and NativeArea(macro) == nil
    and NativeArea(newWindow) == nil, "new native windows never entered the parallel layout")
Check(NativeArea(foreign) == "left" and NativeArea(nativeInteraction) == "left",
    "detached an unowned window or one with native interaction restrictions")

Limit(6)
local firstSix = {calendar, auction, macro, newWindow, encounter, social}
local lookups, reads = panelLookups, sourceReads
for _, frame in ipairs(firstSix) do NativeOpen(frame) end
Check(#deferred == 0, "opens below the cap scheduled a timer")
NativeOpen(map)
Check(#deferred == 1, "opening the seventh window did not schedule exactly one cap pass")
Flush()
Check(not calendar:IsShown() and auction:IsShown() and macro:IsShown() and map:IsShown(),
    "limit six ignored dynamic native windows or closed the wrong frame")
Check(panelLookups == lookups and sourceReads == reads, "a normal open or close rescanned native panel layout")
for _, frame in ipairs(firstSix) do HideUIPanel(frame) end
HideUIPanel(map)
Flush()
Limit(1)
NativeOpen(quest)
Fire("PLAYER_REGEN_DISABLED")
combat = true
NativeOpen(calendar)
Flush()
Check(not quest:IsShown() and calendar:IsShown() and directCombatCloses == 1,
    "a native opener did not enforce the safe combat cap")
HideUIPanel(calendar)
NativeOpen(quest)
Check(Escape(false) == "window", "combat Escape did not observe a safe floating quest")
Flush()
Check(not quest:IsShown() and directCombatCloses == 2, "combat Escape failed to close the safe quest")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Flush()
Check(not watcher.OnUpdate and #deferred == 0, "settled windows left polling or pending work")

local merchant = Panel("MerchantFrame", "left")
Fire("ADDON_LOADED", "Blizzard_UIPanels_Game")
local function OpenTradingBags(trader)
    if IsAnyBagOpen() then return end
    nativeBagOwner = trader
    NativeOpen(bag1)
    NativeOpen(bag2)
end

local function CheckTradingWindows(trader)
    trader.nativeShow, trader.nativeHide = OpenTradingBags, CloseAllBags
    NativeOpen(encounter)
    NativeOpen(trader)
    Flush()
    Check(encounter:IsShown() and trader:IsShown() and bag1:IsShown() and bag2:IsShown(),
        trader.name .. " opening with its bags evicted an existing window at limit two")
    NativeOpen(guild)
    Flush()
    Check(not encounter:IsShown() and trader:IsShown() and guild:IsShown() and bag1:IsShown(),
        trader.name .. " companion bags took the place of a window in FIFO")
    HideUIPanel(trader)
    HideUIPanel(guild)
    Flush()
    Check(not IsAnyBagOpen(), "native trader close left its bags open")

    NativeOpen(trader)
    NativeOpen(encounter)
    Flush()
    Check(trader:IsShown() and encounter:IsShown() and bag2:IsShown(), "opening a second window closed the trading bags")
    CloseAllBags()
    NativeOpen(bag1)
    Flush()
    Check(not trader:IsShown() and encounter:IsShown() and bag1:IsShown(),
        "manually reopening bags counted them as part of the visible trader")
    ResetWindows()
    Limit(2)

    NativeOpen(bag1)
    NativeOpen(trader)
    NativeOpen(encounter)
    Flush()
    Check(not IsAnyBagOpen() and trader:IsShown() and encounter:IsShown(), "bags opened before the trader were not independent")
    HideUIPanel(trader)
    ResetWindows()
end

local function CheckReopenAfterLimit(frame)
    Limit(2)
    NativeOpen(frame)
    NativeOpen(encounter)
    Flush()
    NativeOpen(guild)
    Flush()
    Check(not frame:IsShown() and encounter:IsShown() and guild:IsShown(),
        frame.name .. " was not evicted as the oldest window")

    Flush()
    NativeOpen(frame)
    Flush()
    Check(frame:IsShown() and not encounter:IsShown() and guild:IsShown(),
        frame.name .. " kept its old position after a cap close and reopened as the oldest")
    ResetWindows()
end

for _, isForever in ipairs({ false, true }) do
    module.active = false
    module:Disable()
    NS.Client.isForever = isForever
    module.active = true
    module:Enable()
    for _, trader in ipairs({ merchant, auction }) do
        Limit(2)
        CheckTradingWindows(trader)
    end
    CheckReopenAfterLimit(auction)
    CheckReopenAfterLimit(bag1)
end

-- The native combined bag OnHide toggles a visible character window in Gamepad UI.
auction.nativeShow = function(trader)
    nativeBagOwner = trader
    NativeOpen(combined)
end
auction.nativeHide = function(trader)
    if nativeBagOwner ~= trader then return end
    CloseAllBags(trader)
    HideUIPanel(combined)
end
combined.nativeHide = function()
    if gamepad and character:IsShown() then HideUIPanel(character) end
end
Limit(2)
gamepad = true
NativeOpen(auction)
NativeOpen(encounter)
Flush()
NativeOpen(character)
Flush()
Check(auction:IsShown() and combined:IsShown() and character:IsShown() and not encounter:IsShown(),
    "closing the oldest auction at the cap also closed the Gamepad character window")
HideUIPanel(auction)
Check(not character:IsShown() and not combined:IsShown(), "the native attached-bag close did not run")
Flush()

NativeOpen(auction)
NativeOpen(character)
Flush()
NativeOpen(encounter)
Flush()
Check(auction:IsShown() and combined:IsShown() and character:IsShown() and encounter:IsShown(),
    "the cap closed an unsafe window when no older window could safely close")
HideUIPanel(auction)
ResetWindows()

gamepad = false
NativeOpen(auction)
-- CloseBackpack does not clear Blizzard's private record of which frame opened the bags.
HideUIPanel(combined)
NativeOpen(combined)
NativeOpen(character)
Flush()
gamepad = true
Limit(3)
NativeOpen(encounter)
Flush()
Check(auction:IsShown() and combined:IsShown() and character:IsShown() and encounter:IsShown(),
    "the cap closed Gamepad Character through a trader with unobserved native bag ownership")
HideUIPanel(auction)
gamepad = false
ResetWindows()
print("Suite parallel windows: " .. checks .. " checks passed")
