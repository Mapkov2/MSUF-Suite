local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "groupBloodlust"
local M = {}
local POINTS = NS.AnchorPoints
-- All six player lockout auras are part of MSUF's existing SATED preset.
local SPELLS = { 57723, 57724, 80354, 95809, 160455, 264689 }
local SPELL_SET = {}
for i = 1, #SPELLS do SPELL_SET[SPELLS[i]] = true end

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetSize(172, 42)
    host:SetFrameStrata("HIGH")
    host:EnableMouse(false)
    local background = S.CreateTexture(host, nil, "BACKGROUND")
    background:SetAllPoints(host)
    background:SetColorTexture(.06, .07, .09, .92)
    local edges = {}
    for i = 1, 4 do edges[i] = S.CreateTexture(host, nil, "BORDER") end
    S.PlaceEdges(edges, host, 1, .54, .72, .78, .95)
    local icon = S.CreateTexture(host, nil, "ARTWORK")
    icon:SetPoint("LEFT", host, "LEFT", 4, 0)
    icon:SetSize(34, 34)
    icon:SetTexture(C_Spell.GetSpellTexture(57724))
    local cooldown = S.CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(false)
    cooldown:SetMinimumCountdownDuration(0)
    local title = S.CreateFontString(host, nil, "OVERLAY")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -3)
    S.SetFont(title, nil, 11, "OUTLINE")
    title:SetTextColor(.7, .84, .88)
    title:SetText(S.Text("Bloodlust lockout"))
    local status = S.CreateFontString(host, nil, "OVERLAY")
    status:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 2)
    S.SetFont(status, nil, 14, "OUTLINE")
    host:Hide()
    self.host, self.background, self.edges, self.cooldown, self.title, self.status =
        host, background, edges, cooldown, title, status
end

local function Place(self)
    local c = self.config
    local style = S.QoLStyle(c)
    S.QoLColor(self.background, style.background, .92)
    for _, edge in ipairs(self.edges) do S.QoLColor(edge, style.border, .95) end
    self.title:SetTextColor(S.RGB(style.muted))
    local point = POINTS[c.point] or "CENTER"
    self.host:SetSize(c.width, c.height)
    self.host:SetScale(c.scale / 100)
    self.host:ClearAllPoints()
    self.host:SetPoint(point, UIParent, point, c.x, c.y)
end

local function LockoutAura(self)
    if self.auraBlocked then return nil, false end
    for i = 1, #SPELLS do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SPELLS[i])
        if not ok or not S.Public(aura) then
            -- A restricted/secret player aura cannot be queried repeatedly
            -- during combat. Resume once the client clears that restriction.
            self.auraBlocked = true
            self.context:RemoveEvent("UNIT_AURA")
            return nil, false
        end
        if aura then return aura, true end
    end
    return nil, true
end

local function Paint(self)
    if not self.active then return end
    if S.editMode and not NS.IsCombatLocked() then
        self.status:SetText(S.Text("Locked"))
        self.status:SetTextColor(1, .65, .3)
        self.cooldown:Clear()
        self.host:Show()
        return
    end
    if not self.grouped then
        self.cooldown:Clear()
        self.host:Hide()
        return
    end
    local aura, readable = LockoutAura(self)
    if not readable then
        self.cooldown:Clear()
        self.host:Hide()
        return
    end
    self.auraInstanceID = aura and S.Finite(aura.auraInstanceID) and aura.auraInstanceID or nil
    self.unknownInstanceID = aura ~= nil and self.auraInstanceID == nil
    if aura then
        self.status:SetText(S.Text("Locked"))
        self.status:SetTextColor(1, .65, .3)
        local duration, expiration = aura.duration, aura.expirationTime
        if S.Finite(duration) and duration > 0 and S.Finite(expiration)
            and expiration > duration then
            self.cooldown:SetCooldown(expiration - duration, duration)
        else
            self.cooldown:Clear()
        end
        self.host:Show()
    else
        self.cooldown:Clear()
        if self.config.onlyWhenLocked then
            self.host:Hide()
        else
            self.status:SetText(S.Text("Ready"))
            self.status:SetTextColor(.38, .88, .55)
            self.host:Show()
        end
    end
end

local function Relevant(updateInfo, tracked)
    if not S.Public(updateInfo) or type(updateInfo) ~= "table" then return true end
    if not S.Public(updateInfo.isFullUpdate) or updateInfo.isFullUpdate then return true end
    local added = updateInfo.addedAuras
    if not S.Public(added) or (added ~= nil and type(added) ~= "table") then return true end
    added = added or {}
    for i = 1, #added do
        local aura = added[i]
        if not S.Public(aura) or type(aura) ~= "table" then return true end
        local spellID = aura.spellId
        if S.Finite(spellID) and SPELL_SET[spellID] then return true end
    end
    for _, key in ipairs({ "updatedAuraInstanceIDs", "removedAuraInstanceIDs" }) do
        local ids = updateInfo[key]
        if not S.Public(ids) or (ids ~= nil and type(ids) ~= "table") then return true end
        ids = ids or {}
        if tracked then
            for i = 1, #ids do
                local instanceID = ids[i]
                if not S.Finite(instanceID) or instanceID == tracked then return true end
            end
        end
    end
    return false
end

local function OnAura(self, _, unit, updateInfo)
    if not S.PublicText(unit) or unit ~= "player"
        or (not self.unknownInstanceID and not Relevant(updateInfo, self.auraInstanceID)) then return end
    Paint(self)
end

local function OnGroup(self)
    if not NS.IsCombatLocked() then self.auraBlocked = nil end
    local grouped = IsInGroup()
    self.grouped = S.Public(grouped) and grouped == true
    if self.grouped then
        self.context:Event("PLAYER_REGEN_ENABLED", OnGroup, true)
        if not self.auraBlocked then self.context:Event("UNIT_AURA", OnAura, true, "player") end
    else
        self.context:RemoveEvent("UNIT_AURA")
        self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
        self.auraInstanceID, self.unknownInstanceID = nil, nil
    end
    Paint(self)
end

function M:Enable()
    Create(self)
    Place(self)
    self.context:Event("GROUP_ROSTER_UPDATE", OnGroup, true)
    self.context:Event("PLAYER_ENTERING_WORLD", OnGroup, true)
    OnGroup(self)
    self:RegisterMovers()
end

function M:Refresh()
    if not self.host then return end
    S.SetFont(self.title, nil, 11, "OUTLINE")
    S.SetFont(self.status, nil, 14, "OUTLINE")
    Place(self)
    OnGroup(self)
end

function M:Disable()
    self.context:RemoveEvent("UNIT_AURA")
    self.context:RemoveEvent("GROUP_ROSTER_UPDATE")
    self.context:RemoveEvent("PLAYER_ENTERING_WORLD")
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    self.grouped, self.auraInstanceID, self.unknownInstanceID, self.auraBlocked = nil, nil, nil, nil
    if self.host then self.cooldown:Clear(); self.host:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "lockout", {
        label = "Bloodlust lockout", order = 637,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "height", "scale" },
        extraControls = {
            { id = "width", label = "Width", kind = "number", min = 160, max = 350, step = 1,
                get = function() return S.Config(ID).width end,
                set = function(value) return S.Set(ID, "width", value) end },
            { id = "height", label = "Height", kind = "number", min = 42, max = 80, step = 1,
                get = function() return S.Config(ID).height end,
                set = function(value) return S.Set(ID, "height", value) end },
            { id = "scale", label = "Scale %", kind = "number", min = 50, max = 200, step = 1,
                get = function() return S.Config(ID).scale end,
                set = function(value) return S.Set(ID, "scale", value) end },
        },
    })
end

S.Install(ID, M)
