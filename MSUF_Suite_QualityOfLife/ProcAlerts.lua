local _, P = ...
local NS, S = P.NS, P.Suite
local HUD = NS.HUDVisibility
local ID, MAX_CUES = "procAlerts", 6
local GLOW_SHOW, GLOW_HIDE = "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE"
local IN_COMBAT = { inCombat = true }
local SHOW_EVENTS = { GLOW_SHOW, GLOW_HIDE, "PLAYER_ENTERING_WORLD", "PLAYER_DEAD" }
local SHOW_ALL, FILTER_LIST = 1, 2
local WHITE = "Interface\\Buttons\\WHITE8x8"
local CUE_WIDTH, CUE_HEIGHT, GAP = 128, 44, 6
local MAX_GLOWS = 40
local Module = { cues = {}, activeBySpell = {}, spellFilter = {}, auraIDs = {}, glows = {}, glowOrder = {}, shown = 0 }

local function SpellID(value)
    return S.Finite(value) and value > 0 and value <= 2147483647 and math.floor(value) == value
end

local function CreateCue(host)
    local frame = S.CreateFrame("Frame", nil, host)
    frame:SetSize(CUE_WIDTH, CUE_HEIGHT)
    frame:EnableMouse(false)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(.055, .075, .1, .93)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(2)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", 7, 1)
    icon:SetSize(27, 27)
    icon:SetTexCoord(.08, .92, .08, .92)
    local text = frame:CreateFontString(nil, "OVERLAY")
    S.SetFont(text, nil, 12, "OUTLINE")
    text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    text:SetPoint("RIGHT", -5, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    local cooldown = S.CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(false)
    cooldown:Hide()
    local stacks = cooldown:CreateFontString(nil, "OVERLAY")
    S.SetFont(stacks, nil, 11, "OUTLINE")
    stacks:SetPoint("BOTTOMRIGHT", cooldown, "BOTTOMRIGHT", 1, -1)
    local pulse = line:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(.35)
    fade:SetDuration(.44)
    fade:SetSmoothing("IN_OUT")
    frame:Hide()
    return { frame = frame, line = line, icon = icon, text = text, pulse = pulse, fade = fade,
        cooldown = cooldown, stacks = stacks }
end

local function Prepare(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetSize(CUE_WIDTH, CUE_HEIGHT)
    host:SetFrameStrata("HIGH")
    host:EnableMouse(false)
    host:Hide()
    self.host = host
    for index = 1, MAX_CUES do self.cues[index] = CreateCue(host) end
end

local function Paint(cue, config, texture, name)
    cue.icon:SetTexture(texture)
    cue.text:SetText(name)
    local r, g, b = S.RGB(config.color)
    cue.line:SetColorTexture(r, g, b, 1)
    cue.frame:Show()
    if config.pulse and not cue.pulse:IsPlaying() then
        cue.fade:SetDuration(config.pulseSpeed / 1000)
        cue.pulse:Play()
    end
end

local function WipeCue(cue)
    cue.pulse:Stop()
    cue.line:SetAlpha(1)
    cue.frame:Hide()
    cue.cooldown:Clear()
    cue.cooldown:Hide()
    cue.stacks:Hide()
    cue.spell, cue.start, cue.duration, cue.count, cue.hasAura = nil, nil, nil, nil, nil
end

local function Clear(self)
    for index = 1, self.shown do WipeCue(self.cues[index]) end
    wipe(self.activeBySpell)
    self.shown = 0
    self.host:Hide()
end

local function Arrange(self)
    local n = self.shown
    if n == 0 then
        self.host:Hide()
        return
    end
    local width = n * CUE_WIDTH + (n - 1) * GAP
    self.host:SetWidth(width)
    for index = 1, n do
        local frame = self.cues[index].frame
        frame:ClearAllPoints()
        frame:SetPoint("LEFT", self.host, "LEFT", (index - 1) * (CUE_WIDTH + GAP), 0)
    end
    self.host:SetAlpha(HUD and not self.preview and HUD.Factor(ID) or 1)
    self.host:Show()
end

local function Remove(self, spell)
    local position = self.activeBySpell[spell]
    if not position then return end
    self.activeBySpell[spell] = nil
    local cue = self.cues[position]
    WipeCue(cue)
    local count = self.shown
    for index = position, count - 1 do
        local nextCue = self.cues[index + 1]
        self.cues[index] = nextCue
        self.activeBySpell[nextCue.spell] = index
    end
    self.cues[count] = cue
    self.shown = count - 1
    return true
end

local function Add(self, spell, silent)
    local position = self.shown + 1
    if position > MAX_CUES then return end
    local name = S.PublicText(C_Spell.GetSpellName(spell))
    if not name or name == "" then return end
    local texture = C_Spell.GetSpellTexture(spell)
    if not S.Public(texture) or not texture then texture = WHITE end
    local cue = self.cues[position]
    cue.spell = spell
    self.activeBySpell[spell] = position
    self.shown = position
    Paint(cue, self.config, texture, name)
    if self.config.sound and not silent then
        local now = GetTime()
        if now >= (self.soundAt or 0) then
            self.soundAt = now + .35
            PlaySound(SOUNDKIT.RAID_WARNING, "Master")
        end
    end
    return cue
end

local function Aura(self, spell)
    if not self.config.auraDetails then return end
    local id = self.auraIDs[spell] or spell
    if not (C_Secrets and C_Secrets.ShouldSpellAuraBeSecret and C_UnitAuras
        and C_UnitAuras.GetPlayerAuraBySpellID and canaccesstable) then return end
    local restricted = C_Secrets.ShouldSpellAuraBeSecret(id)
    if not S.Public(restricted) or restricted ~= false then return end
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(id)
    if not S.Public(aura) or type(aura) ~= "table" or not canaccesstable(aura) then return end
    local applications, expiration, duration = aura.applications, aura.expirationTime, aura.duration
    local count = S.Finite(applications) and math.min(99, applications) or nil
    if S.Finite(expiration) and S.Finite(duration) and duration > 0 and expiration > duration then
        return count, expiration - duration, duration
    end
    return count
end

local function DisplayAura(cue, count, start, duration)
    local cd = cue.cooldown
    if cue.start ~= start or cue.duration ~= duration then
        cue.start, cue.duration = start, duration
        if duration then cd:SetCooldown(start, duration) else cd:Clear() end
    end
    if cue.count ~= count then
        cue.count = count
        cue.stacks:SetShown(count ~= nil and count > 1)
        if count and count > 1 then cue.stacks:SetText(count) end
    end
    local shown = duration ~= nil or count ~= nil and count > 1
    if cue.hasAura ~= shown then
        cue.hasAura = shown
        cd:SetShown(shown)
    end
end

local function RefreshCues(self, silent)
    if self.preview then return end
    local moved = false
    local threshold = self.config.auraDetails and self.config.minimumStacks or 0
    for index = 1, #self.glowOrder do
        local spell = self.glowOrder[index]
        local position = self.activeBySpell[spell]
        local matched = self.config.mode == SHOW_ALL or self.spellFilter[spell]
        if matched and (position or self.shown < MAX_CUES) then
            local count, start, duration = Aura(self, spell)
            if count and threshold > count then
                if position then moved = Remove(self, spell) or moved end
            else
                local cue = position and self.cues[position] or Add(self, spell, silent)
                if cue then
                    if not position then moved = true end
                    if self.config.auraDetails then DisplayAura(cue, count, start, duration) end
                end
            end
        end
    end
    if moved then Arrange(self) end
end

local function OnAura(self) RefreshCues(self, false) end

local function WatchAuras(self)
    local watch = self.config.auraDetails and #self.glowOrder > 0
    if watch == self.watching then return end
    self.watching = watch
    if watch then
        self.context:Event("UNIT_AURA", OnAura, IN_COMBAT, "player")
        self.context:Event("ADDON_RESTRICTION_STATE_CHANGED", OnAura, IN_COMBAT)
    else
        self.context:RemoveEvent("UNIT_AURA")
        self.context:RemoveEvent("ADDON_RESTRICTION_STATE_CHANGED")
    end
end

local function OnGlow(self, event, spell)
    if not SpellID(spell) then return end
    if event == GLOW_HIDE then
        if not self.glows[spell] then return end
        self.glows[spell] = nil
        for index = 1, #self.glowOrder do
            if self.glowOrder[index] == spell then table.remove(self.glowOrder, index) break end
        end
        if Remove(self, spell) then Arrange(self) end
    elseif not self.glows[spell] and #self.glowOrder < MAX_GLOWS then
        self.glows[spell] = true
        self.glowOrder[#self.glowOrder + 1] = spell
    else
        return
    end
    WatchAuras(self)
    RefreshCues(self, false)
end

local function ResetGlows(self)
    wipe(self.glows)
    wipe(self.glowOrder)
    WatchAuras(self)
    if not self.preview then Clear(self) end
end

local function RefreshFilter(self)
    wipe(self.spellFilter)
    wipe(self.auraIDs)
    for text in self.config.spells:gmatch("[^,%s]+") do
        local id = tonumber(text)
        if SpellID(id) then self.spellFilter[id] = true end
    end
    for spell, aura in self.config.auraOverrides:gmatch("(%d+):(%d+)") do
        local id, auraID = tonumber(spell), tonumber(aura)
        if SpellID(id) and SpellID(auraID) then self.auraIDs[id] = auraID end
    end
end

function Module:Refresh()
    Prepare(self)
    Clear(self)
    RefreshFilter(self)
    S.PlaceHost(self.host, self.config)
    self.preview = S.editMode == true
    if self.preview then
        self.shown = 1
        Paint(self.cues[1], self.config, "Interface\\Icons\\Spell_Nature_Lightning", S.Text("Proc alert"))
        Arrange(self)
    else
        RefreshCues(self, true)
    end
    WatchAuras(self)
end

function Module:Enable()
    self:Refresh()
    for index = 1, #SHOW_EVENTS do
        local event = SHOW_EVENTS[index]
        self.context:Event(event, index <= 2 and OnGlow or ResetGlows, IN_COMBAT)
    end
end

function Module:Disable()
    self.watching = false
    wipe(self.glows)
    wipe(self.glowOrder)
    if self.host then Clear(self) end
end

function Module:RegisterMovers()
    S.RegisterOwnedMover(ID, "alerts", {
        label = "Proc alerts",
        order = 610,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", point = function() return "CENTER" end,
        sizeKeys = { "scale" },
    })
end

if HUD then
    HUD.Register(ID, function()
        if Module.active and Module.host then Module.host:SetAlpha(Module.preview and 1 or HUD.Factor(ID)) end
    end)
end

S.Install(ID, Module)
