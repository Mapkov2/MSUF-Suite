local _, NS = ...

-- MapkoSkin owns these files and registers them with the process-wide
-- LibSharedMedia catalog. Other loaded SharedMedia packs automatically share
-- the same catalog through LibStub; there is no runtime dependency on MSUF.
local SharedMedia = {}
NS.SharedMedia = SharedMedia

local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
SharedMedia.library = LSM

local fonts = {
    { "MapkoSkin - Expressway", "Expressway Regular.ttf" },
    { "MapkoSkin - Expressway Semibold", "Expressway SemiBold.ttf" },
    { "MapkoSkin - Expressway Bold", "Expressway Bold.ttf" },
    { "MapkoSkin - Expressway ExtraBold", "Expressway ExtraBold.ttf" },
    { "MapkoSkin - Expressway Condensed Light", "Expressway Condensed Light.otf" },
    { "MapkoSkin - Fritz Soundscape", "Fritz Soundscape.ttf" },
}

local bars = {
    "BetterBlizzard.blp", "Charcoal.tga", "Minimalist.tga",
    "MSUF_ArcanePulse.tga", "MSUF_AuroraSilk.tga", "MSUF_DeepCurrent.tga",
    "MSUF_DragonScale.tga", "MSUF_Dreamy.tga", "MSUF_DreamySoft.tga",
    "MSUF_DreamyUltraSoft.tga", "MSUF_EmberWeave.tga", "MSUF_Foggy.tga",
    "MSUF_ForgedSteel.tga", "MSUF_FrostedQuartz.tga", "MSUF_Glass.tga",
    "MSUF_Lucent_v2.tga", "MSUF_LunarMist.tga", "MSUF_MirroredGlass.tga",
    "MSUF_ObsidianGlass.tga", "MSUF_RunicCircuit.tga", "MSUF_Smooth.tga",
    "Slickrock.tga", "smoother.tga", "Smoothv2.tga",
}

if LSM then
    for index = 1, #fonts do
        LSM:Register("font", fonts[index][1], NS.path .. "Media\\Fonts\\" .. fonts[index][2])
    end
    for index = 1, #bars do
        local file = bars[index]
        local label = file:gsub("%.[^%.]+$", ""):gsub("^MSUF_", "")
        LSM:Register("statusbar", "MapkoSkin - " .. label, NS.path .. "Media\\Bars\\" .. file)
    end
end

-- If a selected font is registered after MapkoSkin initializes, reapply it
-- through the normal OOC typography path. The catalog itself is already shared
-- by LibSharedMedia, so unrelated registrations need no runtime work.
function SharedMedia:OnRegistered(_, mediaType, key)
    -- Older CallbackHandler embeds can dispatch without forwarding event
    -- arguments. In that case the selected key becoming available is still an
    -- exact, bounded signal and avoids rescanning or refreshing other fonts.
    if mediaType == nil and key == nil and LSM and NS.DB and NS.DB.typography
        and NS.DB.typography.face == "sharedMedia" then
        local selected = NS.DB.typography.sharedMediaFont
        if type(selected) == "string" and selected ~= ""
            and type(LSM.IsValid) == "function" and LSM:IsValid("font", selected) then
            mediaType, key = "font", selected
        end
    end
    if mediaType ~= "font" or not NS.DB or not NS.DB.enabled
        or not NS.DB.typography or not NS.DB.typography.enabled
        or NS.DB.typography.face ~= "sharedMedia"
        or NS.DB.typography.sharedMediaFont ~= key
        or not NS.Typography or type(NS.Typography.ApplyConfigured) ~= "function" then
        return
    end
    if NS.CombatGate and type(NS.CombatGate.RunOrDefer) == "function" then
        NS.CombatGate.RunOrDefer("typography:shared-media", function()
            if NS.DB and NS.DB.enabled and NS.DB.typography
                and NS.DB.typography.enabled and NS.DB.typography.face == "sharedMedia"
                and NS.DB.typography.sharedMediaFont == key then
                NS.Typography.ApplyConfigured()
            end
        end)
    end
end

if LSM and type(LSM.RegisterCallback) == "function" then
    -- Register an explicit function reference. This is compatible with both
    -- the bundled CallbackHandler and older process-wide LSM instances whose
    -- method-name dispatch contract may already have been embedded.
    local function OnRegistered(event, mediaType, key)
        SharedMedia:OnRegistered(event, mediaType, key)
    end
    local ok, message = pcall(LSM.RegisterCallback, SharedMedia,
        "LibSharedMedia_Registered", OnRegistered)
    SharedMedia.callbackRegistered = ok == true
    SharedMedia.callbackError = not ok and message or nil
end

function SharedMedia.GetLibrary()
    return LSM
end

function SharedMedia.GetFontNames()
    local result = {}
    if LSM and type(LSM.List) == "function" then
        local list = LSM:List("font")
        for index = 1, #(list or {}) do result[index] = list[index] end
    end
    if #result == 0 then result[1] = "Friz Quadrata TT" end
    return result
end

function SharedMedia.FetchFont(name)
    if not LSM or type(name) ~= "string" or name == "" then return nil end
    return LSM:Fetch("font", name, true)
end

function SharedMedia.GetStatusBarNames()
    local result = {}
    if LSM and type(LSM.List) == "function" then
        local list = LSM:List("statusbar")
        for index = 1, #(list or {}) do result[index] = list[index] end
    end
    return result
end

return SharedMedia
