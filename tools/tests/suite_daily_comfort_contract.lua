local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local module
local restored, reported = {}, {}
local deferredFrame
-- Suite-created regions remember their parent.
local function Widget(parent)
    local w = { parent = parent, shown = true, points = {} }
    function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function w:SetHeight() end
    function w:SetColorTexture() end
    function w:SetTextColor() end
    function w:SetText(value) self.text = value end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    return w
end
local suite = {
    Dispatch = Support.Dispatcher(reported),
    Install = function(_, value) module = value end,
    RestoreCVar = function(_, key) restored[key] = (restored[key] or 0) + 1 end,
    Finite = function(value) return type(value) == "number" and value == value end,
    Public = function() return true end,
    Text = function(value) return value end,
    SetFont = function() end,
    CreateTexture = function(parent) return Widget(parent) end,
    CreateFontString = function(parent) return Widget(parent) end,
    CreateFrame = function(_, _, parent)
        if parent then return Widget(parent) end
        deferredFrame = { events = {} }
        function deferredFrame:SetScript(_, callback) self.callback = callback end
        function deferredFrame:RegisterEvent(event) self.events[event] = true end
        function deferredFrame:UnregisterEvent(event) self.events[event] = nil end
        return deferredFrame
    end,
}
local combat = false
local ns = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
    Client = { isForever = false },
    Finish = function(callback, ...) return true, callback(...) end,
}
local panels = Support.UIPanels(function() return combat end)
local function Context()
    local context = { events = {}, applied = {} }
    function context:Event(name, callback) self.events[name] = callback end
    function context:RemoveEvent(name) self.events[name] = nil end
    function context:CVar(key, value)
        self.applied[key] = value
        self.calls = (self.calls or 0) + 1
        return true
    end
    return context
end
local function Frame()
    local frame = { shown = false, events = { SCREENSHOT_SUCCEEDED = true }, hooks = {} }
    function frame:IsShown() return self.shown end
    function frame:IsProtected() return true end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false; if self.hooks.OnHide then self.hooks.OnHide() end end
    function frame:HookScript(name, callback) self.hooks[name] = callback end
    function frame:IsEventRegistered(name) return self.events[name] == true end
    function frame:RegisterEvent(name) self.events[name] = true end
    function frame:UnregisterEvent(name) self.events[name] = nil end
    return frame
end

ActionStatus = Frame()
MerchantFrame = Frame()
CharacterFrame = Frame()
-- Blizzard saves the auction house filters per character (g_auctionHouseFilters,
-- Blizzard_AuctionHouseUI); the helper must never write them.
AuctionHouseFrame = Frame()
AuctionHouseFrame.SearchBar = { updates = 0, OnFilterToggled = function(self) self.updates = self.updates + 1 end,
    FilterButton = { resets = 0, Reset = function(self) self.resets = self.resets + 1 end } }
AUCTION_HOUSE_FILTER_CURRENTEXPANSION_ONLY = "Current Expansion Only"
Enum = { AuctionHouseFilter = { CurrentExpansionOnly = 7 } }
g_auctionHouseFilters = { filters = { [7] = false } }
DELETE_ITEM_CONFIRM_STRING = "DELETE"
StaticPopupDialogs = {
    DELETE_GOOD_ITEM = { OnShow = function() end },
    DELETE_GOOD_QUEST_ITEM = { OnShow = function() end },
}
-- hooksecurefunc as the client runs it: the global (or table field) is
-- replaced by a wrapper; anything holding the original keeps the original.
hooksecurefunc = function(owner, key, callback)
    if type(owner) == "string" then
        local original = _G[owner]
        _G[owner] = function(...) original(...); key(...) end
        return
    end
    local original = owner[key]
    owner[key] = function(...) original(...); callback(...) end
    owner.postHook = callback
end
-- Blizzard_ChatFrameBase creates its chat frames before any addon loads.
local function ChatFrame()
    local frame = { fading = true, calls = 0 }
    function frame:GetFading() return self.fading end
    function frame:SetFading(value) self.fading, self.calls = value, self.calls + 1 end
    return frame
end
CHAT_FRAMES = { "ChatFrame1" }
ChatFrame1 = ChatFrame()
FCF_OpenNewWindow = function()
    ChatFrame2 = ChatFrame()
    CHAT_FRAMES[2] = "ChatFrame2"
end
FCF_OpenTemporaryWindow = function() end

assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/CharacterPanel.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/DailyComfort.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
assert(module)
module.id, module.active, module.context = "dailyComfort", true, Context()
-- auctionExpansion: a key shipped profiles may still carry; it does nothing.
module.config = {
    hideTutorials = true, fillDelete = true,
    hideScreenshotSuccess = true, vendorCharacter = true, auctionExpansion = true,
    chatWheel = true, chatClassColors = true, playerMapCoords = true, muteMusic = true,
    hideLowHealthFlash = true, alternateScreenFlash = true,
    noChatFade = true, whisperWindows = 2,
}
module:Enable()
assert(module.context.applied.showTutorials == "0"
    and module.context.applied.chatMouseScroll == "1"
    and module.context.applied.chatClassColorOverride == "0"
    and module.context.applied.doNotFlashLowHealthWarning == "1"
    and module.context.applied.overrideScreenFlash == "1"
    and module.context.applied.worldMapShowPlayerCoords == "1"
    and module.context.applied.Sound_EnableMusic == "0"
    and module.context.applied.whisperMode == "popout",
    "selected native settings were not applied")
assert(ChatFrame1.fading == false and ChatFrame1.calls == 1
    and module.context.events.UPDATE_CHAT_WINDOWS,
    "chat fading was not changed through the native message frame")
local initialCVarCalls = module.context.calls
module:Refresh()
assert(module.context.calls == initialCVarCalls,
    "refresh reapplied CVars after the player could have changed them")
module.config.whisperWindows = 3
module:Refresh()
assert(module.context.applied.whisperMode == "popout_and_inline"
    and module.context.calls == initialCVarCalls + 1,
    "changing the whisper choice did not update its native CVar")
assert(not ActionStatus:IsEventRegistered("SCREENSHOT_SUCCEEDED"),
    "successful screenshot notice remained registered")
assert(module.context.events.MERCHANT_SHOW and module.context.events.MERCHANT_CLOSED,
    "merchant lifecycle was not registered")
AuctionHouseFrame:Show()
if AuctionHouseFrame.hooks.OnShow then AuctionHouseFrame.hooks.OnShow() end
assert(g_auctionHouseFilters.filters[7] == false and AuctionHouseFrame.SearchBar.updates == 0
    and not AuctionHouseFrame.hooks.OnShow,
    "a saved auction choice wrote Blizzard's auction house filters")
-- The safe form of the old auction choice: while the filter is off, the
-- helper marks Blizzard's filter button; the saved filters stay Blizzard's.
-- Blizzard_AuctionHouseUI loads on demand.
local auction = AuctionHouseFrame
AuctionHouseFrame = nil
module.config.auctionExpansionHint = true
module:Refresh()
assert(module.context.events.ADDON_LOADED and not auction.hooks.OnShow, "the auction house hint did not wait for its window")
AuctionHouseFrame = auction
module.context.events.ADDON_LOADED(module, "ADDON_LOADED", "Blizzard_AuctionHouseUI")
AuctionHouseFrame.hooks.OnShow()
local hint = module.auctionHint
local bar = AuctionHouseFrame.SearchBar
assert(hint and hint.shown and hint.parent == bar.FilterButton
    and hint.text.text == "Current Expansion Only is off" and not module.context.events.ADDON_LOADED,
    "the filter button was not marked while Current Expansion Only is off")
g_auctionHouseFilters.filters[7] = true
bar:OnFilterToggled()
assert(not hint.shown and bar.updates == 1, "ticking the filter in Blizzard's menu kept the mark")
g_auctionHouseFilters.filters[7] = false
bar.FilterButton:Reset()
assert(hint.shown and bar.FilterButton.resets == 1, "clearing the filters did not bring the mark back")
assert(g_auctionHouseFilters.filters[7] == false, "the hint wrote Blizzard's auction house filters")
module.config.auctionExpansionHint = false
module:Refresh()
assert(not hint.shown, "turning the hint off kept the mark")
FCF_OpenNewWindow()
assert(ChatFrame2.fading == false, "a new chat window kept fading")
local edit = { text = nil, SetText = function(self, text) self.text = text end }
local dialog = { GetEditBox = function() return edit end }
StaticPopupDialogs.DELETE_GOOD_ITEM.postHook(dialog)
assert(edit.text == "DELETE", "item confirmation was not prefilled")
module.context.events.MERCHANT_SHOW(module)
assert(panels.shown == 1 and CharacterFrame:IsShown() and #reported == 0,
    "merchant did not open the character window through the panel manager")
module.context.events.MERCHANT_CLOSED(module)
assert(panels.hidden == 1 and not CharacterFrame:IsShown(), "merchant did not close its owned window")
module.context.events.MERCHANT_SHOW(module)
combat = true
module.context.events.MERCHANT_CLOSED(module)
assert(panels.shown == 2 and panels.hidden == 1 and CharacterFrame:IsShown() and panels.blocked == 0
    and deferredFrame.events.PLAYER_REGEN_ENABLED,
    "the merchant character window was not kept for a close after combat")
combat = false
deferredFrame.callback(deferredFrame, "PLAYER_REGEN_ENABLED")
assert(panels.hidden == 2 and not CharacterFrame:IsShown() and not deferredFrame.events.PLAYER_REGEN_ENABLED,
    "merchant character window was not closed after combat")
-- The player closes and reopens the window while a close waits: it stays.
module.context.events.MERCHANT_SHOW(module)
combat = true
module.context.events.MERCHANT_CLOSED(module)
CharacterFrame:Hide()
CharacterFrame:Show()
combat = false
assert(not deferredFrame.events.PLAYER_REGEN_ENABLED and CharacterFrame:IsShown(),
    "a pending close survived the player's own window")
module.context.events.MERCHANT_SHOW(module)
module.context.events.MERCHANT_CLOSED(module)
assert(panels.shown == 3 and panels.hidden == 2 and CharacterFrame:IsShown() and panels.blocked == 0,
    "merchant helper closed a character window it did not open")

module.config.hideTutorials, module.config.fillDelete = false, false
module.config.hideScreenshotSuccess = false
module.config.vendorCharacter, module.config.muteMusic, module.config.chatClassColors = false, false, false
module.config.hideLowHealthFlash, module.config.alternateScreenFlash = false, false
module.config.noChatFade, module.config.whisperWindows = false, 1
module:Refresh()
assert(restored.showTutorials and restored.Sound_EnableMusic and restored.chatClassColorOverride
    and restored.doNotFlashLowHealthWarning and restored.overrideScreenFlash
    and restored.whisperMode and ChatFrame1.fading == true and ChatFrame2.fading == true
    and ActionStatus:IsEventRegistered("SCREENSHOT_SUCCEEDED")
    and not module.context.events.MERCHANT_SHOW,
    "disabled choices did not release their Blizzard state")
edit.text = nil
StaticPopupDialogs.DELETE_GOOD_ITEM.postHook(dialog)
assert(edit.text == nil,
    "permanent post-hooks ran after their choice was disabled")
module.config.noChatFade = true
module:Refresh()
assert(ChatFrame1.fading == false and ChatFrame2.fading == false and not module.context.events.ADDON_LOADED,
    "chat fade did not apply to the existing chat frames at once")
-- Cinematics as the client builds them (Blizzard_FrameXML/Shared/CinematicFrame
-- .lua/.xml): the frame's OnEvent script is the function CinematicFrame.xml
-- bound at load, the confirm dialog's Yes runs CinematicFrame_CancelCinematic,
-- and that leaves a vehicle sequence through VehicleExit().
local stops, sceneCancels, vehicleExits, movieCancels = 0, 0, 0, 0
local inScene, sceneCancellable = false, false
local function ScriptFrame()
    local frame = Frame()
    function frame:HookScript(name, callback)
        local old = self.hooks[name]
        self.hooks[name] = function(...) if old then old(...) end; callback(...) end
    end
    function frame:Show()
        local was = self.shown
        self.shown = true
        if not was and self.hooks.OnShow then self.hooks.OnShow(self) end
    end
    return frame
end
CinematicFrame, MovieFrame = ScriptFrame(), ScriptFrame()
CinematicFrame.closeDialog, MovieFrame.CloseDialog = ScriptFrame(), ScriptFrame()
CinematicFrame_OnEvent = function(self, event, canBeCancelled)
    if event == "CINEMATIC_START" then
        self.isRealCinematic = canBeCancelled
        self.closeDialog:Hide()
        self:Show()
    elseif event == "CINEMATIC_STOP" then
        self:Hide()
    end
end
CinematicFrame.hooks.OnEvent = CinematicFrame_OnEvent
local function Fire(event, ...) CinematicFrame.hooks.OnEvent(CinematicFrame, event, ...) end
StopCinematic = function() stops = stops + 1; Fire("CINEMATIC_STOP") end
IsInCinematicScene = function() return inScene end
CanCancelScene = function() return sceneCancellable end
CancelScene = function() sceneCancels = sceneCancels + 1; Fire("CINEMATIC_STOP") end
VehicleExit = function() vehicleExits = vehicleExits + 1 end
CinematicFrame_CancelCinematic = function()
    if CinematicFrame.isRealCinematic then StopCinematic()
    elseif CanCancelScene() then CancelScene()
    else VehicleExit() end
end
MovieFrame.PlayMovie = function(self) self:Show() end
MovieFrame.FinishMovie = function(self) movieCancels = movieCancels + 1; self:Hide() end
-- Escape shows the confirmation for whatever runs (CinematicFrame_OnKeyDown).
local function PressEscape()
    CinematicFrame.closeDialog:Hide()
    CinematicFrame.closeDialog:Show()
end

module.config.skipCinematicConfirm = true
module:Refresh()
Fire("CINEMATIC_START", true, 0)
PressEscape()
MovieFrame:PlayMovie(); MovieFrame.CloseDialog:Show()
assert(stops == 1 and movieCancels == 1 and not CinematicFrame:IsShown(), "native confirmation skip missing")
-- A vehicle sequence: the confirmation leaves the vehicle, so it stays manual.
Fire("CINEMATIC_START", false, 0)
PressEscape()
assert(vehicleExits == 0 and stops == 1 and CinematicFrame.closeDialog:IsShown(),
    "skipping the confirmation ejected the player from a vehicle sequence")
Fire("CINEMATIC_STOP")
inScene, sceneCancellable = true, true
Fire("CINEMATIC_START", false, 0)
PressEscape()
assert(sceneCancels == 1 and vehicleExits == 0, "a cancellable scene kept its confirmation")
inScene, sceneCancellable = false, false
Fire("CINEMATIC_START", true, 0)
MovieFrame:PlayMovie()
assert(stops == 1 and movieCancels == 1, "confirmation option silently enabled automatic skip")
Fire("CINEMATIC_STOP"); MovieFrame:Hide()

module.config.autoSkipCinematic = true
Fire("CINEMATIC_START", true, 0)
MovieFrame:PlayMovie()
assert(stops == 2 and movieCancels == 2 and not CinematicFrame:IsShown() and not MovieFrame:IsShown(),
    "full cinematic/movie skip missing")
Fire("CINEMATIC_START", false, 0)
assert(stops == 2 and vehicleExits == 0 and CinematicFrame:IsShown(),
    "automatic skip ended a vehicle sequence")
Fire("CINEMATIC_STOP")
inScene, sceneCancellable = true, true
Fire("CINEMATIC_START", false, 0)
assert(sceneCancels == 2, "automatic skip left a cancellable scene running")
sceneCancellable = false
Fire("CINEMATIC_START", false, 0)
assert(sceneCancels == 2 and vehicleExits == 0, "automatic skip cancelled a scene that cannot be cancelled")
Fire("CINEMATIC_STOP")
inScene = false
combat = true
Fire("CINEMATIC_START", true, 0)
PressEscape()
MovieFrame:PlayMovie()
assert(stops == 2 and movieCancels == 2, "cinematic helper ran in combat")
combat = false
Fire("CINEMATIC_STOP"); MovieFrame:Hide()
module.active = false
module:Disable()
Fire("CINEMATIC_START", true, 0)
PressEscape()
MovieFrame:PlayMovie()
assert(stops == 2 and movieCancels == 2, "disabled cinematic hooks kept running")
assert(ActionStatus:IsEventRegistered("SCREENSHOT_SUCCEEDED"),
    "disabling the module did not preserve the screenshot event")
print("Suite daily comfort lifecycle passed")
