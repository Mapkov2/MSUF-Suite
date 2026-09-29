local _, NS = ...
local S = NS.Suite

-- MSUF's full font apply also covers cold-start font recovery. Active Suite
-- modules restyle their text while explicit module font choices stay intact.
local FONT_MODULES = {
    "actionbars", "bags", "cooldownManager", "damageMeter", "dataTexts",
    "minimap", "nameplates", "objectives", "announcements", "afkScreen",
    "xpBar", "skyriding", "durabilityAlert", "battleRes", "chat",
}
local lastPath, lastEpoch
local function ApplyBlizzardFont()
    local skin = NS.Skin
    if not skin or not skin.enabled then return end
    local engine = _G.MapkoSkin
    if type(engine) ~= "table" or engine.addonName ~= "MSUF_Suite_Skin"
        or not engine.DB or engine.DB.enabled ~= true or not engine.DB.typography
        or engine.DB.typography.enabled ~= true or engine.DB.typography.followMSUF == false then
        return
    end
    local typography = engine.Typography
    if typography and type(typography.ApplyConfigured) == "function" then
        typography.ApplyConfigured()
    end
end
function S.ApplyGlobalFont()
    if not S.started then return end
    local path, epoch = NS.GlobalFontPath(), _G.MSUF_FontApplyEpoch
    if path == lastPath and epoch == lastEpoch then return end
    lastPath, lastEpoch = path, epoch
    ApplyBlizzardFont()
    for i = 1, #FONT_MODULES do
        local id = FONT_MODULES[i]
        if S.states[id] and S.states[id].active then S.Apply(id) end
    end
end
_G.MSUFSuite_ApplyFontsFromMSUF = S.ApplyGlobalFont
