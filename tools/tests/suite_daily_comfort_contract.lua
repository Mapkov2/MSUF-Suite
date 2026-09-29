local root = assert(arg[1], "repository root required")
local module
local restored = {}
local deferredFrame
local suite = {
    Install = function(_, value) module = value end,
    RestoreCVar = function(_, key) restored[key] = (restored[key] or 0) + 1 end,
    Finite = function(value) return type(value) == "number" and value == value end,
    Public = function() return true end,
    CreateFrame = function()
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
}
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
AuctionHouseFrame = Frame()
AuctionHouseFrame.SearchBar = { updates = 0, OnFilterToggled = function(self) self.updates = self.updates + 1 end }
Enum = { AuctionHouseFilter = { CurrentExpansionOnly = 7 } }
g_auctionHouseFilters = { filters = { [7] = false } }
local opened, closed = 0, 0
ToggleCharacter = function(_, onlyShow)
    assert(onlyShow == true)
    opened = opened + 1
    CharacterFrame:Show()
end
HideUIPanel = function(frame)
    assert(frame == CharacterFrame)
    closed = closed + 1
    frame:Hide()
end
DELETE_ITEM_CONFIRM_STRING = "DELETE"
StaticPopupDialogs = {
    DELETE_GOOD_ITEM = { OnShow = function() end },
    DELETE_GOOD_QUEST_ITEM = { OnShow = function() end },
}
hooksecurefunc = function(owner, key, callback)
    if type(owner) == "string" then return end
    owner.postHook = callback
end
CHAT_FRAMES = { "ChatFrame1" }
ChatFrame1 = { fading = true, calls = 0 }
function ChatFrame1:GetFading() return self.fading end
function ChatFrame1:SetFading(value) self.fading, self.calls = value, self.calls + 1 end

assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/DailyComfort.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
assert(module)
module.id, module.active, module.context = "dailyComfort", true, Context()
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
AuctionHouseFrame.hooks.OnShow()
assert(g_auctionHouseFilters.filters[7] == true and AuctionHouseFrame.SearchBar.updates == 1,
    "native current expansion filter was not applied when the auction house opened")
local edit = { text = nil, SetText = function(self, text) self.text = text end }
local dialog = { GetEditBox = function() return edit end }
StaticPopupDialogs.DELETE_GOOD_ITEM.postHook(dialog)
assert(edit.text == "DELETE", "item confirmation was not prefilled")
module.context.events.MERCHANT_SHOW(module)
assert(opened == 1 and module.openedCharacter, "merchant did not open equipment window")
module.context.events.MERCHANT_CLOSED(module)
assert(closed == 1 and not module.openedCharacter, "merchant did not close its owned window")
module.context.events.MERCHANT_SHOW(module)
combat = true
module.context.events.MERCHANT_CLOSED(module)
assert(opened == 2 and closed == 1 and module.openedCharacter
    and deferredFrame.events.PLAYER_REGEN_ENABLED,
    "protected merchant equipment window lost its deferred close")
combat = false
deferredFrame.callback(deferredFrame, "PLAYER_REGEN_ENABLED")
assert(closed == 2 and not module.openedCharacter and not deferredFrame.events.PLAYER_REGEN_ENABLED,
    "merchant equipment window was not closed after combat")
local nativeToggle = ToggleCharacter
ToggleCharacter = function() error("client refused character panel") end
module.context.events.MERCHANT_SHOW(module)
assert(not module.openedCharacter and not CharacterFrame:IsShown(),
    "restricted merchant panel open raised an error or claimed ownership")
ToggleCharacter = nativeToggle
CharacterFrame:Show()
module.context.events.MERCHANT_SHOW(module)
module.context.events.MERCHANT_CLOSED(module)
assert(opened == 2 and closed == 2 and CharacterFrame:IsShown(),
    "merchant helper closed a character window it did not open")

module.config.hideTutorials, module.config.fillDelete = false, false
module.config.hideScreenshotSuccess = false
module.config.vendorCharacter, module.config.muteMusic, module.config.chatClassColors = false, false, false
module.config.hideLowHealthFlash, module.config.alternateScreenFlash = false, false
module.config.auctionExpansion = false
module.config.noChatFade, module.config.whisperWindows = false, 1
module:Refresh()
assert(restored.showTutorials and restored.Sound_EnableMusic and restored.chatClassColorOverride
    and restored.doNotFlashLowHealthWarning and restored.overrideScreenFlash
    and restored.whisperMode and ChatFrame1.fading == true
    and ActionStatus:IsEventRegistered("SCREENSHOT_SUCCEEDED")
    and not module.context.events.MERCHANT_SHOW and g_auctionHouseFilters.filters[7] == false,
    "disabled choices did not release their Blizzard state")
edit.text = nil
StaticPopupDialogs.DELETE_GOOD_ITEM.postHook(dialog)
assert(edit.text == nil,
    "permanent post-hooks ran after their choice was disabled")
local chatFrames = CHAT_FRAMES
CHAT_FRAMES = nil
module.config.noChatFade = true
module:Refresh()
assert(module.context.events.ADDON_LOADED,
    "chat fade did not defer until chat frames became available")
CHAT_FRAMES = chatFrames
module.context.events.ADDON_LOADED(module)
assert(ChatFrame1.fading == false,
    "deferred chat fade did not apply when chat frames became available")
module.active = false
module:Disable()
assert(ActionStatus:IsEventRegistered("SCREENSHOT_SUCCEEDED"),
    "disabling the module did not preserve the screenshot event")
print("Suite daily comfort lifecycle passed")
