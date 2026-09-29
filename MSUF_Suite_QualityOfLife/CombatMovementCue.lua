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

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetSize(230, 38)
    host:SetFrameStrata("HIGH")
    host:EnableMouse(false)
    local bg = S.CreateTexture(host, nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(.07, .09, .12, .92)
    local stripe = S.CreateTexture(host, nil, "BORDER")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(3)
    stripe:SetColorTexture(.86, .7, .38)
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
    local style = S.QoLStyle(c)
    S.QoLColor(self.bg, style.background, .92)
    S.QoLColor(self.stripe, style.accent)
    self.label:SetTextColor(S.RGB(style.text))
    local point = NS.AnchorPoints[c.point] or "CENTER"
    self.host:ClearAllPoints()
    self.host:SetPoint(point, UIParent, point, c.x, c.y)
    self.host:SetScale(c.scale / 100)
end

-- isActive/isEnabled are NeverSecret in upstream/live SpellCooldownInfo.
-- IsSpellUsable and spell text may still be restricted, so silence is the
-- only safe answer when any part cannot be read publicly.
local function Ready(id)
    local known = C_SpellBook.IsSpellKnown(id)
    if not S.Public(known) or known ~= true then return nil end
    local info = C_Spell.GetSpellCooldown(id)
    if not S.Public(info) or type(info) ~= "table" then return nil end
    local active, enabled = info.isActive, info.isEnabled
    if not S.Public(active) or active ~= false
        or not S.Public(enabled) or enabled ~= true then return nil end
    local usable = C_Spell.IsSpellUsable(id)
    if not S.Public(usable) or usable ~= true then return nil end
    local name = S.PublicText(C_Spell.GetSpellName(id))
    if not name then return nil end
    local icon = C_Spell.GetSpellTexture(id)
    if not S.Public(icon) then icon = nil end
    return name, icon
end

local function Show(self, name, icon, now)
    self.lastShown = now
    self.token = (self.token or 0) + 1
    local token = self.token
    self.icon:SetTexture(icon or QUESTION)
    self.label:SetText(string.format(S.Text("%s ready for movement"), name))
    self.host:Show()
    C_Timer.After(SHOW_SECONDS, function()
        if self.active and self.token == token and not S.editMode then self.host:Hide() end
    end)
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
        local id = self.ids[i]
        local ok, name, icon = pcall(Ready, id)
        if ok and name then Show(self, name, icon, now) return end
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
    self.token = (self.token or 0) + 1
    if S.editMode then
        self.icon:SetTexture(QUESTION)
        self.label:SetText(S.Text("Movement ability ready"))
        self.host:Show()
    else
        self.host:Hide()
    end
end

function M:Disable()
    self.token = (self.token or 0) + 1
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
        extraControls = {
            { id = "scale", label = "Scale %", kind = "number", min = 50, max = 200, step = 1,
                get = function() return S.Config(ID).scale end,
                set = function(value) return S.Set(ID, "scale", value) end },
        },
    })
end

S.Install(ID, M)
