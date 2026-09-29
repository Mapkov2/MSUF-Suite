local _, P = ...
local NS, S = P.NS, P.Suite

local M = { deleteHooks = {} }
local DELETE_DIALOGS = { "DELETE_GOOD_ITEM", "DELETE_GOOD_QUEST_ITEM" }
local CVAR_CHOICES = {
    { "chatWheel", "chatMouseScroll", "1" },
    { "chatClassColors", "chatClassColorOverride", "0" },
    { "keepMapVisible", "mapFade", "0" },
    { "playerMapCoords", "worldMapShowPlayerCoords", "1" },
    { "cursorMapCoords", "worldMapShowCursorCoords", "1" },
    { "hideLowHealthFlash", "doNotFlashLowHealthWarning", "1" },
    { "alternateScreenFlash", "overrideScreenFlash", "1", true },
    { "muteMusic", "Sound_EnableMusic", "0" },
    { "muteAmbience", "Sound_EnableAmbience", "0" },
    { "muteDialog", "Sound_EnableDialog", "0" },
    { "muteErrorSpeech", "Sound_EnableErrorSpeech", "0" },
}
local CHAT_LIMIT = 64

local function SafeFrame(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

local function InstallDeleteHooks(self)
    if not self.config.fillDelete then return true end
    if type(StaticPopupDialogs) ~= "table" or type(hooksecurefunc) ~= "function" then return false end
    local ready = true
    for _, key in ipairs(DELETE_DIALOGS) do
        local definition = StaticPopupDialogs[key]
        if type(definition) == "table" and type(definition.OnShow) == "function" then
            if not self.deleteHooks[key] then
                hooksecurefunc(definition, "OnShow", function(dialog)
                    if not M.active or not M.config.fillDelete or not SafeFrame(dialog) then return end
                    local editBox = dialog.GetEditBox and dialog:GetEditBox()
                    if SafeFrame(editBox) and type(DELETE_ITEM_CONFIRM_STRING) == "string" then
                        -- Blizzard still owns the button and its confirmation handler.
                        editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
                    end
                end)
                self.deleteHooks[key] = true
            end
        else
            ready = false
        end
    end
    return ready
end

local function SetScreenshotNotice(self)
    local frame = _G.ActionStatus
    if not SafeFrame(frame) then return not self.config.hideScreenshotSuccess end
    if self.config.hideScreenshotSuccess then
        if self.screenshotWasRegistered == nil then
            self.screenshotWasRegistered = frame:IsEventRegistered("SCREENSHOT_SUCCEEDED")
        end
        if self.screenshotWasRegistered then frame:UnregisterEvent("SCREENSHOT_SUCCEEDED") end
    elseif self.screenshotWasRegistered ~= nil then
        if self.screenshotWasRegistered then frame:RegisterEvent("SCREENSHOT_SUCCEEDED") end
        self.screenshotWasRegistered = nil
    end
    return true
end

local CloseMerchantCharacter
local function DeferCharacterClose(self)
    if not self.characterCloseFrame then
        local frame = S.CreateFrame("Frame")
        frame:SetScript("OnEvent", function()
            frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local merchant = _G.MerchantFrame
            if M.active and M.config.vendorCharacter and SafeFrame(merchant) and merchant:IsShown() then return end
            CloseMerchantCharacter(M)
        end)
        self.characterCloseFrame = frame
    end
    self.characterCloseFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

CloseMerchantCharacter = function(self)
    if not self.openedCharacter then return end
    local frame = _G.CharacterFrame
    if not SafeFrame(frame) or not frame:IsShown() then self.openedCharacter = nil return end
    if NS.IsCombatLocked() and frame:IsProtected() then DeferCharacterClose(self) return end
    self.openedCharacter = nil
    if type(HideUIPanel) == "function" then pcall(HideUIPanel, frame) end
end

local function OpenMerchantCharacter(self)
    if not self.active or not self.config.vendorCharacter or self.openedCharacter
        or type(ToggleCharacter) ~= "function" or NS.IsCombatLocked() then return end
    local frame = _G.CharacterFrame
    if not SafeFrame(frame) or frame:IsShown() then return end
    if not pcall(ToggleCharacter, "PaperDollFrame", true) then return end
    if frame:IsShown() then
        self.openedCharacter = true
        if not self.characterHooked then
            frame:HookScript("OnHide", function() M.openedCharacter = nil end)
            self.characterHooked = true
        end
    end
end

local function AuctionFilter(self, enabled)
    local filterID = Enum and Enum.AuctionHouseFilter and Enum.AuctionHouseFilter.CurrentExpansionOnly
    local saved = _G.g_auctionHouseFilters
    local filters = type(saved) == "table" and saved.filters
    if type(filters) ~= "table" or not S.Finite(filterID) then return not enabled end
    if enabled then
        if filters[filterID] ~= true then
            self.auctionFilters, self.auctionPrevious = filters, filters[filterID]
            self.auctionOwned = true
            filters[filterID] = true
            local bar = _G.AuctionHouseFrame and _G.AuctionHouseFrame.SearchBar
            if SafeFrame(bar) and type(bar.OnFilterToggled) == "function" then bar:OnFilterToggled() end
        end
    elseif self.auctionOwned then
        if filters == self.auctionFilters and filters[filterID] == true then
            filters[filterID] = self.auctionPrevious
            local bar = _G.AuctionHouseFrame and _G.AuctionHouseFrame.SearchBar
            if SafeFrame(bar) and type(bar.OnFilterToggled) == "function" then bar:OnFilterToggled() end
        end
        self.auctionFilters, self.auctionPrevious, self.auctionOwned = nil, nil, nil
    end
    return true
end

local function SyncAuction(self)
    if not self.config.auctionExpansion or NS.Client.isForever then
        AuctionFilter(self, false)
        return true
    end
    local frame = _G.AuctionHouseFrame
    if not SafeFrame(frame) then return false end
    if not self.auctionHooked then
        frame:HookScript("OnShow", function()
            if M.active and M.config.auctionExpansion then AuctionFilter(M, true) end
        end)
        self.auctionHooked = true
    end
    if frame:IsShown() then return AuctionFilter(self, true) end
    return true
end

local function SyncCVar(self, key, enabled, value)
    self.appliedCVars = self.appliedCVars or {}
    if enabled then
        if self.appliedCVars[key] ~= value and self.context:CVar(key, value) then
            self.appliedCVars[key] = value
        end
    else
        S.RestoreCVar(self.id, key)
        self.appliedCVars[key] = nil
    end
end

local function ReleaseChatFade(self)
    if not self.chatFadePrior then return end
    for frame, previous in pairs(self.chatFadePrior) do
        if SafeFrame(frame) then
            local current = frame:GetFading()
            if S.Public(current) and current == false and previous then
                frame:SetFading(true)
            end
        end
    end
    self.chatFadePrior = nil
end

local function SyncChatFade(self)
    if not self.config.noChatFade then
        ReleaseChatFade(self)
        self.context:RemoveEvent("UPDATE_CHAT_WINDOWS")
        self.context:RemoveEvent("UPDATE_FLOATING_CHAT_WINDOWS")
        return true
    end
    local names = _G.CHAT_FRAMES
    if type(names) ~= "table" then return false end
    self.chatFadePrior = self.chatFadePrior or setmetatable({}, { __mode = "k" })
    local count = 0
    for _, name in pairs(names) do
        if count >= CHAT_LIMIT then break end
        count = count + 1
        local frame = type(name) == "string" and _G[name]
        if SafeFrame(frame) then
            local current = frame:GetFading()
            if S.Public(current) and type(current) == "boolean" then
                if self.chatFadePrior[frame] == nil then self.chatFadePrior[frame] = current end
                if current then frame:SetFading(false) end
            end
        end
    end
    self.context:Event("UPDATE_CHAT_WINDOWS", function(module) SyncChatFade(module) end)
    self.context:Event("UPDATE_FLOATING_CHAT_WINDOWS", function(module) SyncChatFade(module) end)
    if not self.chatFadeHooked then
        local update = function()
            if M.active and M.config.noChatFade then SyncChatFade(M) end
        end
        if type(_G.FCF_OpenNewWindow) == "function"
            and type(_G.FCF_OpenTemporaryWindow) == "function" then
            hooksecurefunc("FCF_OpenNewWindow", update)
            hooksecurefunc("FCF_OpenTemporaryWindow", update)
            self.chatFadeHooked = true
        end
    end
    return true
end

local function Sync(self)
    SyncCVar(self, "showTutorials", self.config.hideTutorials, "0")
    for i = 1, #CVAR_CHOICES do
        local choice = CVAR_CHOICES[i]
        if not choice[4] or not NS.Client.isForever then
            SyncCVar(self, choice[2], self.config[choice[1]], choice[3])
        end
    end
    local whisperMode = self.config.whisperWindows
    SyncCVar(self, "whisperMode", whisperMode == 2 or whisperMode == 3,
        whisperMode == 3 and "popout_and_inline" or "popout")
    local deleteReady = InstallDeleteHooks(self)
    local screenshotReady = SetScreenshotNotice(self)
    local auctionReady = SyncAuction(self)
    local chatReady = SyncChatFade(self)
    if self.config.vendorCharacter then
        self.context:Event("MERCHANT_SHOW", OpenMerchantCharacter)
        self.context:Event("MERCHANT_CLOSED", CloseMerchantCharacter)
        local merchant = _G.MerchantFrame
        if SafeFrame(merchant) and merchant:IsShown() then OpenMerchantCharacter(self) end
    else
        self.context:RemoveEvent("MERCHANT_SHOW")
        self.context:RemoveEvent("MERCHANT_CLOSED")
        CloseMerchantCharacter(self)
    end
    local ready = deleteReady and screenshotReady and auctionReady and chatReady
    if ready then
        self.context:RemoveEvent("ADDON_LOADED")
    else
        self.context:Event("ADDON_LOADED", function(module) Sync(module) end)
    end
end

function M:Enable() Sync(self) end
function M:Refresh() Sync(self) end
function M:Disable()
    CloseMerchantCharacter(self)
    AuctionFilter(self, false)
    ReleaseChatFade(self)
    self.appliedCVars = nil
    if self.screenshotWasRegistered ~= nil then
        local frame = _G.ActionStatus
        if SafeFrame(frame) and self.screenshotWasRegistered then frame:RegisterEvent("SCREENSHOT_SUCCEEDED") end
        self.screenshotWasRegistered = nil
    end
end

S.Install("dailyComfort", M)
