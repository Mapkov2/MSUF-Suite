local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local ID, SPELL_ID = "burningRushCue", 111400
local WIDTH, HEIGHT = 216, 46
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local COMBAT_VISIBILITY = "[combat] show; hide"

local function Decorate(frame, preview)
    frame:SetSize(WIDTH, HEIGHT)
    frame:EnableMouse(false)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.13, .06, .07, .94)
    local stripe = frame:CreateTexture(nil, "BORDER")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(3)
    stripe:SetColorTexture(1, .36, .29, 1)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("LEFT", 7, 0)
    if preview then icon:SetTexture(QUESTION) end

    local label = frame:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    S.SetFont(label, nil, 14, "OUTLINE")
    label:SetTextColor(1, .87, .82)
    label:SetText(S.Text("Burning Rush active"))
    return icon, background, label
end

local function Paint(background, label, config)
    if not background or not label then return end
    local style = S.QoLStyle(config)
    S.QoLColor(background, style.background, .94)
    label:SetTextColor(S.RGB(style.text))
end

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetSize(WIDTH, HEIGHT)
    host:SetFrameStrata("HIGH")
    host:EnableMouse(false)
    host:Hide()

    -- Blizzard owns all aura selection, UNIT_AURA dispatch and button
    -- visibility. The initializer runs before its aura button is sealed.
    local container = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
    container:SetAllPoints(host)
    container:SetUnit("player")
    container:AddAuraSlot("burningRush", "HELPFUL", {
        candidateFilters = { includeSpellIDs = { [SPELL_ID] = true } },
        initializeFrame = function(button)
            button:SetAllPoints(container)
            button:SetMouseClickEnabled(false)
            local icon, background, label = Decorate(button, false)
            self.auraBackground, self.auraLabel = background, label
            Paint(background, label, self.config)
            button:SetIcon(icon)
        end,
    })

    local preview = S.CreateFrame("Frame", nil, host)
    preview:SetAllPoints(host)
    local _, previewBackground, previewLabel = Decorate(preview, true)
    self.previewBackground, self.previewLabel = previewBackground, previewLabel
    Paint(previewBackground, previewLabel, self.config)
    preview:Hide()
    self.host, self.container, self.preview = host, container, preview
end

local function Place(self)
    S.PlaceHost(self.host, self.config)
end

local function Update(self)
    if not self.active or not self.host then return end
    if NS.IsCombatLocked() then
        -- The state driver owns native visibility in combat. Edit Mode may
        -- close at combat start; apply that cold transition after combat.
        self.preview:Hide()
        if self.previewMode ~= (S.editMode == true) then S.Queue(ID) end
        return
    end
    local editing = S.editMode == true
    if self.previewMode ~= editing then
        self.previewMode = editing
        self.container:SetEnabled(not editing)
    end
    self.preview:SetShown(editing)
end

function M:Enable()
    if NS.IsCombatLocked() then
        S.Queue(ID)
        return
    end
    if NS.Client.isForever or S.PublicText(UnitClassBase("player")) ~= "WARLOCK" then return end
    Create(self)
    Place(self)
    self.previewMode = nil
    -- The native container is the sole combat-visible surface. Blizzard's
    -- secure state driver changes its visibility without addon combat writes.
    RegisterStateDriver(self.container, "visibility", COMBAT_VISIBILITY)
    self.driverRegistered = true
    Update(self)
    self.host:Show()
    self.context:Event("PLAYER_ENTERING_WORLD", Update, true)
    self.context:Event("PLAYER_REGEN_DISABLED", Update, true)
    self.context:Event("PLAYER_REGEN_ENABLED", Update, true)
    self:RegisterMovers()
end

function M:Refresh()
    if NS.IsCombatLocked() then
        S.Queue(ID)
        return
    end
    if not self.host then return end
    Paint(self.auraBackground, self.auraLabel, self.config)
    Paint(self.previewBackground, self.previewLabel, self.config)
    Place(self)
    Update(self)
end

-- The controller stops a module only outside combat lockdown (S.Apply).
function M:Disable()
    self.context:RemoveEvent("PLAYER_ENTERING_WORLD")
    self.context:RemoveEvent("PLAYER_REGEN_DISABLED")
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    self.previewMode = nil
    if self.host then
        if self.driverRegistered then
            UnregisterStateDriver(self.container, "visibility")
            self.driverRegistered = false
        end
        self.container:SetEnabled(false)
        self.container:Hide()
        self.preview:Hide()
        self.host:Hide()
    end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "combat", {
        label = "Burning Rush cue", order = 648,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return NS.AnchorPoints[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "scale" },
        sizeKeys = { "scale" },
    })
end

S.Install(ID, M)
