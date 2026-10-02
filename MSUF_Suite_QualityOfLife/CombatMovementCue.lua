local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local ID = "combatMovementCue"
local MAX_IDS, THROTTLE, CHECK_INTERVAL, SHOW_SECONDS = 8, 20, 1, 2.5
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function ParseIDs(raw)
    local ids, seen = {}, {}
    if type(raw) ~= "string" then return ids end
    for token in raw:gmatch("[^,%s;]+") do
        local id = tonumber(token)
        if S.Finite(id) and id > 0 and id < 10000000 and id == math.floor(id)
            and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
            if #ids == MAX_IDS then break end
        end
    end
    return ids
end

local CARD = { width = 230, height = 38, fill = { .07, .09, .12, .92 }, stripe = 3, line = { .86, .7, .38 } }

local function Create(self)
    if self.host then return end
    local host, bg, stripe = S.QoLCard(CARD)
    local icon = S.CreateTexture(host, nil, "ARTWORK")
    icon:SetSize(27, 27)
    icon:SetPoint("LEFT", 8, 0)
    local label = S.CreateFontString(host, nil, "OVERLAY")
    label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", host, "RIGHT", -8, 0)
    label:SetJustifyH("LEFT")
    S.SetFont(label, nil, 13, "OUTLINE")
    host:Hide()
    self.host, self.bg, self.stripe, self.icon, self.label = host, bg, stripe, icon, label
end

local function Place(self)
    local c = self.config
    local style = S.PaintQoLCard(ID, c, self.bg)
    S.QoLColor(self.stripe, style.accent)
    self.label:SetTextColor(S.RGB(style.text))
    S.PlaceHost(self.host, c)
end

-- A spell that waits only for the global cooldown counts as ready. isActive
-- and isEnabled are NeverSecret in SpellCooldownInfo; isOnGCD can be trusted
-- only inside SPELL_UPDATE_COOLDOWN (SpellSharedDocumentation), so on a
-- movement start the cooldown without the GCD answers: none, or a readable
-- inactive one.
local function OffCooldown(id)
    local info = C_Spell.GetSpellCooldown(id)
    if not S.Public(info) or type(info) ~= "table" then return false end
    local active, enabled = info.isActive, info.isEnabled
    if not S.Public(active) or not S.Public(enabled) or enabled ~= true then return false end
    if active == false then return true end
    local real = C_Spell.GetSpellCooldownDuration(id, true)
    if not real then return true end
    if real:HasSecretValues() then return false end
    local running = real:IsActive()
    return S.Public(running) and running == false
end

-- IsSpellUsable and spell text may still be restricted, so silence is the
-- only safe answer when any part cannot be read publicly.
local function Ready(id)
    local known = C_SpellBook.IsSpellKnown(id)
    if not S.Public(known) or known ~= true then return nil end
    if not OffCooldown(id) then return nil end
    local usable = C_Spell.IsSpellUsable(id)
    if not S.Public(usable) or usable ~= true then return nil end
    local name = S.PublicText(C_Spell.GetSpellName(id))
    if not name then return nil end
    local icon = C_Spell.GetSpellTexture(id)
    if not S.Public(icon) then icon = nil end
    return name, icon
end

local function HideCue(self)
    if not S.editMode then self.host:Hide() end
end

-- A newer cue restarts the timeout of the one on screen.
local function Show(self, name, icon, now)
    self.lastShown = now
    self.icon:SetTexture(icon or QUESTION)
    self.label:SetText(string.format(S.Text("%s ready for movement"), name))
    self.host:Show()
    self.context:After(SHOW_SECONDS, HideCue)
end

local function StartedMoving(self)
    if not self.active or S.editMode then return end
    if self.config.combatOnly and not NS.IsCombatLocked() then return end
    local now = GetTime()
    if not S.Finite(now) then return end
    if self.lastShown and now - self.lastShown < THROTTLE then return end
    if self.lastChecked and now - self.lastChecked < CHECK_INTERVAL then return end
    self.lastChecked = now
    for i = 1, #self.ids do
        local name, icon = Ready(self.ids[i])
        if name then Show(self, name, icon, now) return end
    end
end

local function SyncEvent(self)
    if #self.ids > 0 then
        self.context:Event("PLAYER_STARTED_MOVING", StartedMoving, true)
    else
        self.context:RemoveEvent("PLAYER_STARTED_MOVING")
    end
end

function M:Enable()
    Create(self)
    self.ids = ParseIDs(self.config.spellIDs)
    Place(self)
    SyncEvent(self)
    self:RegisterMovers()
    self:Refresh()
end

function M:Refresh()
    self.ids = ParseIDs(self.config.spellIDs)
    self.lastChecked = nil
    SyncEvent(self)
    Place(self)
    S.SetFont(self.label, nil, 13, "OUTLINE")
    self.context:Cancel(HideCue)
    if S.editMode then
        self.icon:SetTexture(QUESTION)
        self.label:SetText(S.Text("Movement ability ready"))
        self.host:Show()
    else
        self.host:Hide()
    end
end

-- The context's Release drops a cue timeout still due.
function M:Disable()
    self.lastChecked = nil
    if self.host then self.host:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "combat", {
        label = "Movement cue", order = 647,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return NS.AnchorPoints[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "scale" },
        sizeKeys = { "scale" },
    })
end

S.Install(ID, M)
