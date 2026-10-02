local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "durabilityAlert"
local POINTS = NS.AnchorPoints
local IN_COMBAT = { inCombat = true }
local M = {}

local LABEL = S.Text("Low durability")
local PREVIEW = S.Text("Preview")

local CARD = { width = 250, height = 62, fill = { .06, .07, .09, .92 }, edge = 1, line = { .7, .25, .22, .9 } }

local function Create(self)
    if self.host then return end

    local host, panel, edges = S.QoLCard(CARD)

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
    self.host, self.panel, self.edges, self.title, self.value = host, panel, edges, title, value
end

local function Place(self)
    local c = self.config
    S.PaintQoLCard(ID, c, self.panel, self.edges)
    self.host:SetSize(c.width, c.height)
    S.PlaceHost(self.host, c)
end

-- The warning waits for combat to end. A refresh while MSUF Edit Mode
-- closes for combat runs before the lockdown starts (NS.InCombat).
local function Update(self)
    if not self.active then return end
    if NS.InCombat() then
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

-- Inventory and alert events can arrive together: one update per window.
-- Waiting past the shared reader's 0.05-second cache also ensures a repair
-- uses fresh values.
local SETTLE = .06
local function ScheduleUpdate(self)
    self.updateJob:Request()
end

local function OnEvent(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        self.host:Hide()
    elseif not NS.InCombat(event) then
        ScheduleUpdate(self)
    end
end

function M:Enable()
    self.updateJob = self.context:Coalesce(SETTLE, Update)
    Create(self)
    Place(self)
    local context = self.context
    context:Event("PLAYER_ENTERING_WORLD", OnEvent, IN_COMBAT)
    context:Event("UPDATE_INVENTORY_DURABILITY", OnEvent, IN_COMBAT)
    context:Event("UPDATE_INVENTORY_ALERTS", OnEvent, IN_COMBAT)
    context:Event("PLAYER_EQUIPMENT_CHANGED", OnEvent, IN_COMBAT)
    context:Event("PLAYER_REGEN_DISABLED", OnEvent, IN_COMBAT)
    context:Event("PLAYER_REGEN_ENABLED", OnEvent, IN_COMBAT)
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

-- The context's Release drops an update still due.
function M:Disable()
    if self.host then self.host:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "warning", {
        label = "Low durability warning", order = 635,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "height", "scale" },
        sizeKeys = { "width", "height", "scale" },
    })
end

S.Install(ID, M)
