local _, P = ...
local NS, S, AB = P.NS, P.Suite, P.ActionBars
local M = AB.M
local records, art, hooked = {}, {}, setmetatable({}, { __mode = "k" })
local shownRecords = setmetatable({}, { __mode = "k" })
local job, jobContext, zoneHooked, active
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Wanted()
    return M.active and (M.config.styleSpecialButtons or M.config.hideSpecialArtwork)
end

local function Queue()
    if not M.active or not M.config.styleSpecialButtons then return end
    if NS.InCombat() then
        AB.specialPending = true
        S.Queue("actionbars")
    elseif job then
        job:Request()
    end
end

local function RememberText(rec, region)
    if not region or rec.texts[region] then return end
    local font, size, flags = region:GetFont()
    local r, g, b, a = region:GetTextColor()
    local sx, sy = region:GetShadowOffset()
    local sr, sg, sb, sa = region:GetShadowColor()
    rec.texts[region] = { font, size, flags, r, g, b, a, sx, sy, sr, sg, sb, sa }
end

local function RestoreText(rec)
    for region, saved in pairs(rec.texts) do
        if type(saved[1]) == "string" and S.Finite(saved[2]) then region:SetFont(saved[1], saved[2], saved[3] or "") end
        region:SetTextColor(saved[4], saved[5], saved[6], saved[7])
        region:SetShadowOffset(saved[8], saved[9])
        region:SetShadowColor(saved[10], saved[11], saved[12], saved[13])
        rec.texts[region] = nil
    end
    if rec.hotkey and rec.keyAlpha ~= nil then rec.hotkey:SetAlpha(rec.keyAlpha) end
    rec.keyAlpha = nil
    rec.styleEpoch = nil
    if rec.border then rec.border:Hide() end
end

local function Font(rec, region, kind, size, r, g, b)
    if not region then return end
    RememberText(rec, region)
    local style, text = AB.style, AB.style.texts[kind]
    S.SetStyledFont(region, text.font, size, text.flags, style.rendering,
        style.shadow, style.shadowOpacity, style.shadowDistance)
    region:SetTextColor(r, g, b, 1)
end

local function Border(rec, button)
    local style, config = AB.style, M.config
    if not style.mediaBorder and config.borderSize <= 0 then
        if rec.border then rec.border:Hide() end
        return
    end
    local frame = rec.border
    if not frame then
        frame = S.CreateFrame("Frame", nil, button, "BackdropTemplate")
        frame:EnableMouse(false)
        rec.border = frame
    end
    local level = button:GetFrameLevel()
    if S.Finite(level) then frame:SetFrameLevel(level + 8) end
    local pad = style.mediaBorder and config.mediaBorderPadding or 0
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", button, "TOPLEFT", -pad, pad)
    frame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", pad, -pad)
    rec.backdrop = rec.backdrop or {}
    rec.backdrop.edgeFile = style.mediaBorder or WHITE
    rec.backdrop.edgeSize = style.mediaBorder and config.mediaBorderSize or config.borderSize
    frame:SetBackdrop(rec.backdrop)
    frame:SetBackdropBorderColor(style.br, style.bg, style.bb, 1)
    frame:Show()
end

local function Shown(frame)
    local rec = shownRecords[frame]
    if rec then rec.styleEpoch = nil end
    Queue()
end

local function HookShown(frame, rec)
    if not frame or hooked[frame] then return end
    hooked[frame] = true
    shownRecords[frame] = rec
    frame:HookScript("OnShow", Shown)
end

local function StyleButton(button, isExtra)
    local rec = records[button]
    local c, style = M.config, AB.style
    if not c.styleSpecialButtons then
        if rec and rec.styleEpoch ~= nil then RestoreText(rec) end
        return
    end
    if not rec then
        rec = { texts = {} }
        records[button] = rec
        HookShown(button, rec)
    end
    local epoch = AB.specialEpoch or 0
    if rec.styleEpoch == epoch and not rec.waitingCooldown then return end
    if isExtra and button.HotKey then
        local text = button.HotKey
        rec.hotkey = text
        if rec.keyAlpha == nil then rec.keyAlpha = text:GetAlpha() end
        Font(rec, text, "keybind", c.specialKeybindSize, style.kr, style.kg, style.kb)
        text:SetAlpha(c.specialKeybind and 1 or 0)
    end
    local cooldown = button.cooldown or button.Cooldown
    rec.waitingCooldown = nil
    if cooldown then
        HookShown(cooldown, rec)
        local text = cooldown:GetCountdownFontString()
        Font(rec, text, "cooldown", c.specialCooldownSize, style.dr, style.dg, style.db)
        rec.waitingCooldown = text == nil
    end
    Border(rec, button)
    rec.styleEpoch = epoch
end

local function Artwork(texture)
    if not texture then return end
    if M.config.hideSpecialArtwork then
        if art[texture] == nil then
            art[texture] = texture:GetAlpha()
            texture:SetAlpha(0)
        end
    elseif art[texture] ~= nil then
        texture:SetAlpha(art[texture])
        art[texture] = nil
    end
end

function AB.SyncSpecialButtons()
    if not Wanted() and not active then
        AB.specialPending = nil
        return
    end
    if NS.InCombat() then
        AB.specialPending = true
        S.Queue("actionbars")
        return
    end
    if not Wanted() then
        AB.StopSpecialButtons()
        return
    end
    AB.specialPending = nil
    active = true
    if jobContext ~= M.context then
        jobContext = M.context
        job = M.context:Coalesce(0, AB.SyncSpecialButtons)
    end
    local extra, zone = rawget(_G, "ExtraActionButton1"), rawget(_G, "ZoneAbilityFrame")
    if extra then
        StyleButton(extra, true)
        Artwork(extra.style)
    end
    if zone then
        Artwork(zone.Style)
        if M.config.styleSpecialButtons and not zoneHooked then
            hooksecurefunc(zone, "UpdateDisplayedZoneAbilities", Queue)
            zoneHooked = true
        end
        for button in zone.SpellButtonContainer:EnumerateActive() do StyleButton(button, false) end
    end
end

function AB.StopSpecialButtons()
    for _, rec in pairs(records) do RestoreText(rec) end
    for texture, alpha in pairs(art) do
        texture:SetAlpha(alpha)
        art[texture] = nil
    end
    if job then job:Cancel() end
    active = false
    AB.specialPending = nil
end
