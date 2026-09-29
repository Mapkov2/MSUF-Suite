local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "durabilityAlert"
local POINTS = NS.AnchorPoints
local M = { generation = 0 }

local LABEL = S.Text("Low durability")
local PREVIEW = S.Text("Preview")

local function Create(self)
    if self.host then return end

    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetSize(250, 62)
    host:SetFrameStrata("HIGH")
    host:EnableMouse(false)

    local panel = S.CreateTexture(host, nil, "BACKGROUND")
    panel:SetAllPoints(host)
    panel:SetColorTexture(.06, .07, .09, .92)

    local edges = {}
    for i = 1, 4 do edges[i] = S.CreateTexture(host, nil, "BORDER") end
    S.PlaceEdges(edges, host, 1, .7, .25, .22, .9)

    local title = S.CreateFontString(host, nil, "OVERLAY")
    title:SetPoint("TOPLEFT", host, "TOPLEFT", 8, -8)
    title:SetPoint("TOPRIGHT", host, "TOPRIGHT", -8, -8)
    title:SetJustifyH("CENTER")
    title:SetWordWrap(false)
    S.SetFont(title, nil, 14, "OUTLINE")
    title:SetTextColor(1, .7, .58)
    title:SetText(LABEL)

    local value = S.CreateFontString(host, nil, "OVERLAY")
    value:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 8, 7)
    value:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -8, 7)
    value:SetJustifyH("CENTER")
    S.SetFont(value, nil, 22, "OUTLINE")
    value:SetTextColor(1, .36, .33)

    host:Hide()
    self.host, self.title, self.value = host, title, value
end

local function Place(self)
    local c = self.config
    local point = POINTS[c.point] or "CENTER"
    self.host:SetSize(c.width, c.height)
    self.host:SetScale(c.scale / 100)
    self.host:ClearAllPoints()
    self.host:SetPoint(point, UIParent, point, c.x, c.y)
end

local function Update(self)
    if not self.active then return end
    if NS.IsCombatLocked() then
        self.host:Hide()
        return
    end
    if S.editMode then
        self.value:SetText(PREVIEW .. " 25%")
        self.host:Show()
        return
    end

    -- The shared reader ignores unreadable/secret durability values and is
    -- already used by the Suite's minimap and DataTexts modules.
    local lowest = S.ReadInfoSource("durability")
    if not S.Finite(lowest) or lowest < 0 or lowest >= self.config.threshold / 100 then
        self.host:Hide()
        return
    end
    self.value:SetText(math.floor(lowest * 100) .. "%")
    self.host:Show()
end

local function ScheduleUpdate(self)
    if self.pending then return end
    self.pending = true
    local generation = self.generation
    -- Inventory and alert events can arrive together. Waiting past the shared
    -- reader's 0.05-second cache also ensures a repair uses fresh values.
    C_Timer.After(.06, function()
        if self.generation ~= generation then return end
        self.pending = false
        Update(self)
    end)
end

local function OnEvent(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        self.host:Hide()
    elseif not NS.IsCombatLocked() then
        ScheduleUpdate(self)
    end
end

function M:Enable()
    self.generation = self.generation + 1
    self.pending = false
    Create(self)
    Place(self)
    local context = self.context
    context:Event("PLAYER_ENTERING_WORLD", OnEvent, true)
    context:Event("UPDATE_INVENTORY_DURABILITY", OnEvent, true)
    context:Event("UPDATE_INVENTORY_ALERTS", OnEvent, true)
    context:Event("PLAYER_EQUIPMENT_CHANGED", OnEvent, true)
    context:Event("PLAYER_REGEN_DISABLED", OnEvent, true)
    context:Event("PLAYER_REGEN_ENABLED", OnEvent, true)
    Update(self)
    ScheduleUpdate(self)
    self:RegisterMovers()
end

function M:Refresh()
    S.SetFont(self.title, nil, 14, "OUTLINE")
    S.SetFont(self.value, nil, 22, "OUTLINE")
    Place(self)
    Update(self)
end

function M:Disable()
    self.generation = self.generation + 1
    self.pending = false
    if self.host then self.host:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "warning", {
        label = "Low durability warning", order = 635,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "height", "scale" },
        extraControls = {
            { id = "width", label = "Width", kind = "number", min = 180, max = 500, step = 1,
                get = function() return S.Config(ID).width end,
                set = function(value) return S.Set(ID, "width", value) end },
            { id = "height", label = "Height", kind = "number", min = 56, max = 90, step = 1,
                get = function() return S.Config(ID).height end,
                set = function(value) return S.Set(ID, "height", value) end },
            { id = "scale", label = "Scale %", kind = "number", min = 50, max = 200, step = 1,
                get = function() return S.Config(ID).scale end,
                set = function(value) return S.Set(ID, "scale", value) end },
        },
    })
end

S.Install(ID, M)
