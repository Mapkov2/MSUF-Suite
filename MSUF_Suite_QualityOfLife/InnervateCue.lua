local _, P = ...
local NS, S = P.NS, P.Suite
local ID, SPELL_ID = "innervateCue", 29166
local POINTS, GLOW_OWNER = NS.AnchorPoints, "MSUFSuiteInnervateCue"
local M = {}

local function Cancel(self, key)
    local timer = self[key]
    if timer then timer:Cancel(); self[key] = nil end
end

local function Hide(self)
    Cancel(self, "hideTimer")
    if self.host then self.host:Hide() end
    if self.glow then self.glow:Hide() end
end

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetSize(280, 54)
    host:SetFrameStrata("HIGH")
    host:EnableMouse(false)
    local panel = S.CreateTexture(host, nil, "BACKGROUND")
    panel:SetAllPoints(host)
    panel:SetColorTexture(.04, .10, .17, .94)
    local edges = {}
    for i = 1, 4 do edges[i] = S.CreateTexture(host, nil, "BORDER") end
    S.PlaceEdges(edges, host, 2, .32, .72, 1, 1)
    local icon = S.CreateTexture(host, nil, "ARTWORK")
    icon:SetPoint("LEFT", host, "LEFT", 9, 0)
    icon:SetSize(34, 34)
    icon:SetTexture(C_Spell.GetSpellTexture(SPELL_ID))
    local title = S.CreateFontString(host, nil, "OVERLAY")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 9, -2)
    title:SetPoint("TOPRIGHT", host, "TOPRIGHT", -8, -2)
    title:SetJustifyH("LEFT")
    S.SetFont(title, nil, 15, "OUTLINE")
    title:SetTextColor(1, 1, 1)
    local subtitle = S.CreateFontString(host, nil, "OVERLAY")
    subtitle:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 9, 2)
    subtitle:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -8, 2)
    subtitle:SetJustifyH("LEFT")
    S.SetFont(subtitle, nil, 11, "OUTLINE")
    subtitle:SetTextColor(.68, .82, .92)
    host:Hide()
    self.host, self.title, self.subtitle = host, title, subtitle

    -- This inert Suite-owned overlay never changes the protected unit frame.
    local glow = S.CreateFrame("Frame", nil, UIParent)
    glow:SetFrameStrata("TOOLTIP")
    glow:EnableMouse(false)
    local glowEdges = {}
    for i = 1, 4 do glowEdges[i] = S.CreateTexture(glow, nil, "OVERLAY") end
    S.PlaceEdges(glowEdges, glow, 3, .24, .65, 1, 1)
    glow:Hide()
    self.glow = glow
end

local function Place(self)
    local c = self.config
    local point = POINTS[c.point] or "CENTER"
    self.host:SetSize(c.width, c.height)
    self.host:SetScale(c.scale / 100)
    self.host:ClearAllPoints()
    self.host:SetPoint(point, UIParent, point, c.x, c.y)
end

local function ZoneAllowed(c)
    local inInstance, kind = IsInInstance()
    if not S.Public(inInstance) or not S.Public(kind) then return false end
    if not inInstance then return c.openWorld end
    if kind == "raid" then return c.raid end
    if kind == "party" or kind == "scenario" or kind == "pvp" or kind == "arena" then return c.party end
    return false
end

-- A secret cooldown is unknown. The observed-cast window suppresses only
-- cues that we can establish are too early; it never invents readiness.
local function Ready(self)
    local info = C_Spell.GetSpellCooldown(SPELL_ID)
    if S.Public(info) and type(info) == "table" then
        local start, duration, enabled = info.startTime, info.duration, info.isEnabled
        if S.Finite(start) and S.Finite(duration) and S.Public(enabled) then
            if enabled == false then return false, nil end
            local remaining = start + duration - GetTime()
            if duration <= 1.5 or remaining <= 0 then return true end
            return false, remaining
        end
    end
    local remaining = (self.fallbackReady or 0) - GetTime()
    if remaining > 0 then return false, remaining end
    return nil
end

local function GroupAPI()
    return _G.MSUF_NS.GF
end

local function MatchUnit(wanted)
    if wanted == "" then return nil end
    local withRealm = wanted:find("-", 1, true) ~= nil
    local found, ambiguous
    local function Consider(unit)
        if not UnitExists(unit) then return end
        local name, realm = UnitFullName(unit)
        if not S.PublicText(name) or not S.Public(realm) then return end
        local candidate = realm and realm ~= "" and (name .. "-" .. realm) or name
        if (withRealm and candidate:lower() == wanted) or (not withRealm and name:lower() == wanted) then
            if found then ambiguous = true else found = unit end
        end
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do Consider("raid" .. i) end
    else
        Consider("player")
        for i = 1, math.max(0, GetNumGroupMembers() - 1) do Consider("party" .. i) end
    end
    return not ambiguous and found or nil
end

local function ResolveFrame(unit)
    local gf = GroupAPI()
    if not (unit and gf and type(gf.FrameForUnit) == "function") then return nil end
    local frame = gf.FrameForUnit(unit)
    if not frame or frame.MSUFUnitKey ~= unit then return nil end
    if frame:IsForbidden() then return nil end
    return frame
end

local function CacheTarget(self)
    -- Anchoring to a protected group frame and reading roster names are cold
    -- operations. A roster change in combat drops the outline until safe.
    self.glow:Hide()
    self.glowAnchor = nil
    if NS.IsCombatLocked() or not self.config.highlightTarget then return end
    local name = self.config.targetName
    if type(name) ~= "string" or name == "" then return end
    local unit = MatchUnit(name:lower())
    local frame = ResolveFrame(unit)
    if not frame then return end
    self.glow:ClearAllPoints()
    self.glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
    self.glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)
    self.glowAnchor = frame
end

local function Show(self, sender)
    Cancel(self, "hideTimer")
    self.title:SetText("Innervate whisper cue")
    local readable = S.PublicText(sender)
    self.subtitle:SetText(readable and (readable .. " whispered") or "Incoming whisper")
    self.host:Show()
    local frame = self.glowAnchor
    if frame and self.config.highlightTarget and frame.IsVisible then
        local visible = frame:IsVisible()
        if S.Public(visible) and visible == true then self.glow:Show() end
    end
    if self.config.sound then
        PlaySound(SOUNDKIT.RAID_WARNING, "SFX")
    end
    local timer
    timer = C_Timer.NewTimer(self.config.duration, function()
        if self.active and self.hideTimer == timer then Hide(self) end
    end)
    self.hideTimer = timer
end

local function ClearPending(self)
    Cancel(self, "readyTimer")
    self.pending = nil
end

local function PendingReady(self)
    self.readyTimer = nil
    if not self.active or not self.pending then return end
    local pending = self.pending
    self.pending = nil
    local ready = Ready(self)
    if ready == true and GetTime() - pending.at <= 5 then Show(self, pending.sender) end
end

local function Whisper(self, _, _, sender)
    local combat = UnitAffectingCombat("player")
    if not S.Public(combat) or combat ~= true or not ZoneAllowed(self.config) then return end
    local known = C_SpellBook.IsSpellKnown(SPELL_ID)
    if S.Public(known) and known == false then return end
    local now = GetTime()
    if self.lastWhisper and now - self.lastWhisper < 5 then return end
    self.lastWhisper = now
    ClearPending(self)
    local readable = S.PublicText(sender)
    local ready, remaining = Ready(self)
    if ready == false then
        if S.Finite(remaining) and remaining > 0 and remaining <= 5 then
            self.pending = { at = now, sender = readable }
            self.readyTimer = C_Timer.NewTimer(remaining, function() PendingReady(self) end)
        end
        return
    end
    Show(self, readable)
end

local function Cast(self, _, _, _, spellID)
    if not S.Public(spellID) or spellID ~= SPELL_ID then return end
    self.fallbackReady = GetTime() + 180
    ClearPending(self)
    Hide(self)
end

local function Roster(self)
    CacheTarget(self)
end

local function Preview(self)
    if S.editMode and not NS.IsCombatLocked() then
        Cancel(self, "hideTimer")
        self.title:SetText("Innervate whisper cue")
        self.subtitle:SetText("Incoming whisper")
        self.host:Show()
    else
        Hide(self)
    end
end

function M:Enable()
    Create(self)
    Place(self)
    self.lastWhisper = nil
    self.context:Event("CHAT_MSG_WHISPER", Whisper, true)
    self.context:Event("UNIT_SPELLCAST_SUCCEEDED", Cast, true, "player")
    self.context:Event("GROUP_ROSTER_UPDATE", Roster, true)
    self.context:Event("PLAYER_REGEN_ENABLED", Roster, true)
    local gf = GroupAPI()
    if gf and type(gf.RegisterFrameRegistryObserver) == "function" then
        gf.RegisterFrameRegistryObserver(GLOW_OWNER, function() if self.active then CacheTarget(self) end end)
        self.observedGF = gf
    end
    CacheTarget(self)
    Preview(self)
    self:RegisterMovers()
end

function M:Refresh()
    S.SetFont(self.title, nil, 15, "OUTLINE")
    S.SetFont(self.subtitle, nil, 11, "OUTLINE")
    Place(self)
    CacheTarget(self)
    Preview(self)
end

function M:Disable()
    ClearPending(self)
    Hide(self)
    self.glowAnchor = nil
    if self.observedGF then
        self.observedGF.UnregisterFrameRegistryObserver(GLOW_OWNER)
        self.observedGF = nil
    end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "alert", {
        label = "Innervate whisper cue", order = 637,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "height", "scale" },
        extraControls = {
            { id = "width", label = "Width", kind = "number", min = 180, max = 500, step = 1,
                get = function() return S.Config(ID).width end,
                set = function(value) return S.Set(ID, "width", value) end },
            { id = "height", label = "Height", kind = "number", min = 44, max = 90, step = 1,
                get = function() return S.Config(ID).height end,
                set = function(value) return S.Set(ID, "height", value) end },
            { id = "scale", label = "Scale %", kind = "number", min = 50, max = 200, step = 1,
                get = function() return S.Config(ID).scale end,
                set = function(value) return S.Set(ID, "scale", value) end },
        },
    })
end

S.Install(ID, M)
