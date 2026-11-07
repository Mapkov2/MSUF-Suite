local _, P = ...
local NS, S = P.NS, P.Suite

local M = {}
local DELETE_DIALOGS = { "DELETE_GOOD_ITEM", "DELETE_GOOD_QUEST_ITEM" }
local CVAR_CHOICES = {
    { "keepMapVisible", "mapFade", "0" },
    { "playerMapCoords", "worldMapShowPlayerCoords", "1" },
    { "cursorMapCoords", "worldMapShowCursorCoords", "1" },
    { "hideLowHealthFlash", "doNotFlashLowHealthWarning", "1" },
    { "alternateScreenFlash", "overrideScreenFlash", "1" },
    { "muteMusic", "Sound_EnableMusic", "0" },
    { "muteAmbience", "Sound_EnableAmbience", "0" },
    { "muteDialog", "Sound_EnableDialog", "0" },
    { "muteErrorSpeech", "Sound_EnableErrorSpeech", "0" },
}

local function FillDelete(dialog)
    -- Blizzard still owns the button and its confirmation handler.
    if M.active and M.config.fillDelete then dialog:GetEditBox():SetText(DELETE_ITEM_CONFIRM_STRING) end
end

-- Blizzard_StaticPopup_Game defines both dialogs before any addon loads.
local function InstallDeleteHooks(self)
    if not self.config.fillDelete or self.deleteHooked then return end
    for _, key in ipairs(DELETE_DIALOGS) do hooksecurefunc(StaticPopupDialogs[key], "OnShow", FillDelete) end
    self.deleteHooked = true
end

local function SetScreenshotNotice(self)
    local frame = ActionStatus
    if self.config.hideScreenshotSuccess then
        if self.screenshotWasRegistered == nil then
            self.screenshotWasRegistered = frame:IsEventRegistered("SCREENSHOT_SUCCEEDED")
        end
        if self.screenshotWasRegistered then frame:UnregisterEvent("SCREENSHOT_SUCCEEDED") end
    elseif self.screenshotWasRegistered ~= nil then
        if self.screenshotWasRegistered then frame:RegisterEvent("SCREENSHOT_SUCCEEDED") end
        self.screenshotWasRegistered = nil
    end
end

-- The character window at merchants (CharacterPanel.lua owns the window).
local function MerchantShown(self)
    if self.config.vendorCharacter then S.OpenCharacterFor(self) end
end

local function MerchantClosed(self)
    S.CloseCharacterFor(self)
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

-- Escape shows CinematicFrame.closeDialog for a real cinematic, a scene the
-- player may cancel, or a vehicle sequence the player may leave. Blizzard's
-- confirm button runs CinematicFrame_CancelCinematic, which ends a vehicle
-- sequence through VehicleExit() (Blizzard_FrameXML/Shared/CinematicFrame.lua).
-- This helper ends only real cinematics and cancellable scenes; it never
-- leaves a vehicle sequence on the player's behalf.
local function EndCinematic(realCinematic)
    if NS.IsCombatLocked() then return end
    if realCinematic then
        StopCinematic()
    elseif IsInCinematicScene() and CanCancelScene() then
        CancelScene()
    end
end

local function ConfirmCinematic()
    if not M.active or not M.config.skipCinematicConfirm then return end
    local real = CinematicFrame.isRealCinematic
    EndCinematic(S.Public(real) and real == true)
end

-- CinematicFrame.xml binds <OnEvent function="CinematicFrame_OnEvent"/> while
-- it loads, so replacing that global never reaches the frame. A script hook
-- runs right after Blizzard's handler took the frame up for CINEMATIC_START;
-- canBeCancelled is false for vehicle sequences.
local function CinematicEvent(_, event, canBeCancelled)
    if event ~= "CINEMATIC_START" or not M.active or not M.config.autoSkipCinematic then return end
    EndCinematic(S.Public(canBeCancelled) and canBeCancelled == true)
end

local function ConfirmMovie()
    if M.active and M.config.skipCinematicConfirm and not NS.IsCombatLocked() then
        MovieFrame:FinishMovie()
    end
end

-- MovieFrameMixin:OnEvent calls self:PlayMovie, so the method hook runs.
local function AfterMovie(frame)
    if M.active and M.config.autoSkipCinematic and not NS.IsCombatLocked()
        and frame:IsShown() then
        frame:FinishMovie()
    end
end

------------------------------------------------------------------ auction house
-- Blizzard keeps the Current Expansion Only filter in its per-character
-- g_auctionHouseFilters. A value written there by addon code would be read
-- by every later search and toggle, so the purchase and posting calls would
-- run tainted (Blizzard_AuctionHouseSearchBar.lua). The helper only reads the
-- filter and, while it is off, marks Blizzard's filter button; ticking the
-- choice there is the player's own click, and Blizzard keeps it.
local HINT_R, HINT_G, HINT_B = 1, .74, .25

local function ExpansionFilterOn()
    local saved = g_auctionHouseFilters
    local filters = saved and saved.filters
    return filters ~= nil and filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] == true
end

local function HintFrame(self)
    if self.auctionHint then return self.auctionHint end
    local button = AuctionHouseFrame.SearchBar.FilterButton
    local hint = S.CreateFrame("Frame", nil, button)
    hint:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
    hint:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
        local line = S.CreateTexture(hint, nil, "OVERLAY")
        line:SetPoint(edge[1])
        line:SetPoint(edge[2])
        line:SetHeight(2)
        line:SetColorTexture(HINT_R, HINT_G, HINT_B, 1)
    end
    hint.text = S.CreateFontString(hint, nil, "OVERLAY")
    S.SetFont(hint.text, nil, 11, "OUTLINE")
    hint.text:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
    hint.text:SetTextColor(HINT_R, HINT_G, HINT_B)
    hint.text:SetText(string.format(S.Text("%s is off"), AUCTION_HOUSE_FILTER_CURRENTEXPANSION_ONLY))
    self.auctionHint = hint
    return hint
end

local function AuctionHint()
    local wanted = M.active and M.config.auctionExpansionHint and AuctionHouseFrame:IsShown()
        and not ExpansionFilterOn()
    if wanted then
        HintFrame(M):Show()
    elseif M.auctionHint then
        M.auctionHint:Hide()
    end
end

-- Blizzard_AuctionHouseUI loads on demand. OnFilterToggled follows every
-- filter click and Reset follows Clear filters; hooks cannot be removed.
local function HookAuction(self)
    if self.auctionHooked or not _G.AuctionHouseFrame then return end
    AuctionHouseFrame:HookScript("OnShow", AuctionHint)
    hooksecurefunc(AuctionHouseFrame.SearchBar, "OnFilterToggled", AuctionHint)
    hooksecurefunc(AuctionHouseFrame.SearchBar.FilterButton, "Reset", AuctionHint)
    self.auctionHooked = true
    self.context:RemoveEvent("ADDON_LOADED")
end

local function AuctionLoaded(self, _, addon)
    if addon == "Blizzard_AuctionHouseUI" then HookAuction(self) end
end

local function SyncAuction(self)
    if self.config.auctionExpansionHint and not self.auctionHooked then
        if _G.AuctionHouseFrame then HookAuction(self) else self.context:Event("ADDON_LOADED", AuctionLoaded) end
    end
    if self.auctionHooked then AuctionHint() end
end

-- Script and method hooks cannot be removed; they do nothing while off.
local function SyncCinematics(self)
    if self.cinematicHooked or not self.config.skipCinematicConfirm and not self.config.autoSkipCinematic then
        return
    end
    CinematicFrame.closeDialog:HookScript("OnShow", ConfirmCinematic)
    CinematicFrame:HookScript("OnEvent", CinematicEvent)
    MovieFrame.CloseDialog:HookScript("OnShow", ConfirmMovie)
    hooksecurefunc(MovieFrame, "PlayMovie", AfterMovie)
    self.cinematicHooked = true
end

local function Sync(self)
    SyncCVar(self, "showTutorials", self.config.hideTutorials, "0")
    for i = 1, #CVAR_CHOICES do
        local choice = CVAR_CHOICES[i]
        SyncCVar(self, choice[2], self.config[choice[1]], choice[3])
    end
    InstallDeleteHooks(self)
    SetScreenshotNotice(self)
    SyncCinematics(self)
    SyncAuction(self)
    if self.config.vendorCharacter then
        self.context:Event("MERCHANT_SHOW", MerchantShown)
        self.context:Event("MERCHANT_CLOSED", MerchantClosed)
        if MerchantFrame:IsShown() then MerchantShown(self) end
    else
        self.context:RemoveEvent("MERCHANT_SHOW")
        self.context:RemoveEvent("MERCHANT_CLOSED")
        S.CloseCharacterFor(self)
    end
end

function M:Enable()
    -- The old owner may still hold records from before the Chat menu split.
    S.RestoreCVar(self.id, "chatMouseScroll")
    S.RestoreCVar(self.id, "chatClassColorOverride")
    S.RestoreCVar(self.id, "whisperMode")
    Sync(self)
end
function M:Refresh() Sync(self) end
function M:Disable()
    S.CloseCharacterFor(self)
    if self.auctionHint then self.auctionHint:Hide() end
    self.appliedCVars = nil
    if self.screenshotWasRegistered then ActionStatus:RegisterEvent("SCREENSHOT_SUCCEEDED") end
    self.screenshotWasRegistered = nil
end

S.Install("dailyComfort", M)
