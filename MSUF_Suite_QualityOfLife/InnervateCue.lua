local _, P = ...
local NS, S = P.NS, P.Suite
local ID, SPELL_ID = "innervateCue", 29166
local POINTS, GLOW_OWNER = NS.AnchorPoints, "MSUFSuiteInnervateCue"
local IN_COMBAT = { inCombat = true }
local M = {}
local Dispatch = S.Dispatch

-- Also the cue's own timeout (ctx:After in Show).
local function Hide(self)
    self.context:Cancel(Hide)
    if self.host then self.host:Hide() end
    if self.glow then self.glow:Hide() end
end

local CARD = { width = 280, height = 54, fill = { .04, .10, .17, .94 }, edge = 2, line = { .32, .72, 1, 1 } }

local function Create(self)
    if self.host then return end
    local host, panel, edges = S.QoLCard(CARD)
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
    self.host, self.panel, self.edges, self.title, self.subtitle = host, panel, edges, title, subtitle

    -- This inert Suite-owned overlay never changes the protected unit frame.
    local glow = S.CreateFrame("Frame", nil, UIParent)
    glow:SetFrameStrata("TOOLTIP")
    glow:EnableMouse(false)
    local glowEdges = {}
    for i = 1, 4 do glowEdges[i] = S.CreateTexture(glow, nil, "OVERLAY") end
    S.PlaceEdges(glowEdges, glow, 3, .24, .65, 1, 1)
    glow:Hide()
    self.glow, self.glowEdges = glow, glowEdges
end

local function Place(self)
    local c = self.config
    local style = S.PaintQoLCard(ID, c, self.panel)
    for _, edge in ipairs(self.edges) do S.QoLColor(edge, style.accent) end
    for _, edge in ipairs(self.glowEdges) do S.QoLColor(edge, style.accent) end
    self.title:SetTextColor(S.RGB(style.text))
    self.subtitle:SetTextColor(S.RGB(style.muted))
    self.host:SetSize(c.width, c.height)
    S.PlaceHost(self.host, c)
end

-- Dungeons, scenarios, battlegrounds and arenas share the group switch.
local ZONE_KEYS = { world = "openWorld", party = "party", pvp = "party", raid = "raid" }
local function ZoneAllowed(c)
    local key = ZONE_KEYS[S.InstanceKind() or ""]
    return key ~= nil and c[key] == true
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
    self.title:SetText(S.Text("Innervate whisper cue"))
    local readable = S.PublicText(sender)
    self.subtitle:SetText(readable and S.Text("%s whispered"):format(readable) or S.Text("Incoming whisper"))
    self.host:Show()
    local frame = self.glowAnchor
    if frame and self.config.highlightTarget and frame.IsVisible then
        local visible = frame:IsVisible()
        if S.Public(visible) and visible == true then self.glow:Show() end
    end
    if self.config.sound then
        PlaySound(SOUNDKIT.RAID_WARNING, "SFX")
    end
    self.context:After(self.config.duration, Hide)
end

-- A whisper while Innervate is about to come off cooldown waits for it.
local PendingReady
local function ClearPending(self)
    self.context:Cancel(PendingReady)
    self.pending = nil
end

PendingReady = function(self)
    if not self.pending then return end
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
            self.context:After(remaining, PendingReady)
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
        self.context:Cancel(Hide)
        self.title:SetText(S.Text("Innervate whisper cue"))
        self.subtitle:SetText(S.Text("Incoming whisper"))
        self.host:Show()
    else
        Hide(self)
    end
end

-- MSUF's group frames call their registry observers inside their own
-- update; the cue's work runs isolated so its error never stops theirs.
local function GroupFramesChanged()
    if M.active then Dispatch(CacheTarget, M) end
end

-- MSUF is another addon: registering and leaving its observer list run
-- through Dispatch, and an MSUF without the leave call is left alone.
local function ReleaseGroupFrames(self)
    local gf = self.observedGF
    if not gf then return end
    self.observedGF = nil
    if type(gf.UnregisterFrameRegistryObserver) == "function" then
        Dispatch(gf.UnregisterFrameRegistryObserver, GLOW_OWNER)
    end
end

function M:Enable()
    Create(self)
    Place(self)
    self.lastWhisper = nil
    self.context:Event("CHAT_MSG_WHISPER", Whisper, IN_COMBAT)
    self.context:Event("UNIT_SPELLCAST_SUCCEEDED", Cast, IN_COMBAT, "player")
    self.context:Event("GROUP_ROSTER_UPDATE", Roster, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_ENABLED", Roster, IN_COMBAT)
    local gf = GroupAPI()
    if gf and type(gf.RegisterFrameRegistryObserver) == "function"
        and Dispatch(gf.RegisterFrameRegistryObserver, GLOW_OWNER, GroupFramesChanged) then
        self.observedGF = gf
    end
    CacheTarget(self)
    Preview(self)
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
    ReleaseGroupFrames(self)
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "alert", {
        label = "Innervate whisper cue", order = 637,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "height", "scale" },
        sizeKeys = { "width", "height", "scale" },
    })
end

S.Install(ID, M)
