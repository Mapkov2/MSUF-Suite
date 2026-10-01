local _, P = ...
local NS, S = P.NS, P.Suite

local M = { hooked = {}, original = {} }
local frames = {
    talkingHead = "TalkingHeadFrame",
    bossBanner = "BossBanner",
    quickJoin = "QuickJoinToastButton",
}

local function Suppress(frame, key)
    if NS.Safety.IsForbidden(frame) then return end
    local combat = NS.IsCombatLocked()
    if combat and frame:IsProtected() then return end
    if key == "quickJoin" then
        local toast, alternate = frame.Toast, frame.Toast2
        if not toast or not alternate or NS.Safety.IsForbidden(toast)
            or NS.Safety.IsForbidden(alternate) then return end
        if combat and (toast:IsProtected() or alternate:IsProtected()) then return end
        if M.active and M.config.quickJoin then
            if not M.original.quickJoin then
                M.original.quickJoin = { first = toast:GetAlpha(), second = alternate:GetAlpha() }
            end
            toast:SetAlpha(0)
            alternate:SetAlpha(0)
        elseif M.original.quickJoin then
            toast:SetAlpha(M.original.quickJoin.first)
            alternate:SetAlpha(M.original.quickJoin.second)
            M.original.quickJoin = nil
        end
        return
    end
    if M.active and M.config[key] then
        if not M.original[key] then
            M.original[key] = { alpha = frame:GetAlpha(), mouse = frame:IsMouseEnabled() }
        end
        -- Keep Blizzard's OnUpdate and animation lifecycle running so queued
        -- boss banners and Talking Head lines still complete normally.
        frame:SetAlpha(0)
        frame:EnableMouse(false)
    elseif M.original[key] then
        frame:SetAlpha(M.original[key].alpha)
        frame:EnableMouse(M.original[key].mouse)
        M.original[key] = nil
    end
end

-- A hidden Talking Head is also silent. Blizzard's PlayCurrent starts the
-- voice-over (PlaySound, TalkingHeadUI.lua) after the frame showed, so the
-- line stops right after that call; SOUNDKIT_FINISHED and Close stay
-- Blizzard's own.
local function StopVoice(frame)
    if not M.active or not M.config.talkingHead then return end
    local handle = frame.voHandle
    if S.Finite(handle) then StopSound(handle) end
end

local function Install(self)
    for key, name in pairs(frames) do
        local frame = _G[name]
        if self.config[key] and frame and not self.hooked[key] and not NS.Safety.IsForbidden(frame) then
            frame:HookScript("OnShow", function(shown) Suppress(shown, key) end)
            if key == "talkingHead" then hooksecurefunc(frame, "PlayCurrent", StopVoice) end
            self.hooked[key] = true
        end
        if frame and (frame:IsShown() or (not self.config[key] and self.original[key])) then
            Suppress(frame, key)
        end
    end
end

local function OnAddon(self, _, addon)
    if addon == "Blizzard_QuickJoin" then
        Install(self)
        if self.hooked.quickJoin then self.context:RemoveEvent("ADDON_LOADED") end
    end
end

local function SyncAddonEvent(self)
    if self.config.quickJoin and not self.hooked.quickJoin then
        self.context:Event("ADDON_LOADED", OnAddon)
    else
        self.context:RemoveEvent("ADDON_LOADED")
    end
end

function M:Enable()
    Install(self)
    SyncAddonEvent(self)
end

function M:Refresh()
    Install(self)
    SyncAddonEvent(self)
end
function M:Disable()
    for key, name in pairs(frames) do
        local frame = _G[name]
        if frame then Suppress(frame, key) end
    end
end

S.Install("quietPopups", M)
