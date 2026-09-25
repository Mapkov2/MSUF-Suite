local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local ID = "xpBar"
local SEGMENT_COUNT = 20
local POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local MSUF_BAR = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Bars\\MSUF_Lucent_v2.tga"
local MSUF_FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"
-- Match the authored Blue, Dark and Forever palettes used by the Suite's MSUF chat
-- looks. The XP and rested fills stay visually distinct within each palette.
local LOOKS = {
    {
        panel = "0a1220",
        track = "102033",
        border = "41627a",
        accent = "57c7df",
        text = "f4f7fb",
        muted = "aab5c2",
        rested = "558bdd"
    },
    {
        panel = "151719",
        track = "202326",
        border = "575b58",
        accent = "b9ab86",
        text = "e9e9e4",
        muted = "b9bdb9",
        rested = "777d70"
    },
    {
        panel = "14181b",
        track = "20272a",
        border = "9f8960",
        accent = "d8b66a",
        text = "f4f3eb",
        muted = "d4dce2",
        rested = "668db8"
    },
}

local function RGB(hex)
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
        (tonumber(hex:sub(3, 4), 16) or 255) / 255,
        (tonumber(hex:sub(5, 6), 16) or 255) / 255
end

local function Paint(texture, hex, alpha)
    local r, g, b = RGB(hex)
    texture:SetColorTexture(r, g, b, alpha)
end

local function Tint(texture, hex, alpha)
    local r, g, b = RGB(hex)
    texture:SetVertexColor(r, g, b, alpha)
end

local function Number(value)
    return S.Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function Clock()
    local readers = { type(GetServerTime) == "function" and GetServerTime or false,
        type(time) == "function" and time or false }
    for _, read in ipairs(readers) do
        if type(read) == "function" then
            local ok, value = pcall(read)
            if ok and Number(value) then return math.floor(value) end
        end
    end
    return 0
end

local function XP()
    local ok, level, current, maximum = pcall(function()
        return UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
    end)
    if not ok or not Number(level) or not Number(current) or not Number(maximum)
        or level < 1 or current < 0 or maximum < 0 then
        return nil
    end
    return level, current, maximum
end

local function Rested()
    if type(GetXPExhaustion) ~= "function" then return 0 end
    local ok, value = pcall(GetXPExhaustion)
    return ok and Number(value) and math.max(0, value) or 0
end

local function Exact(value)
    value = math.max(0, math.floor(value or 0))
    return type(BreakUpLargeNumbers) == "function" and BreakUpLargeNumbers(value) or tostring(value)
end

local function Compact(value)
    value = math.max(0, value or 0)
    if value >= 1000000 then return ("%.1fm"):format(value / 1000000) end
    if value >= 10000 then return ("%.0fk"):format(value / 1000) end
    if value >= 1000 then return ("%.1fk"):format(value / 1000) end
    return tostring(math.floor(value))
end

local function Duration(seconds)
    if not Number(seconds) or seconds < 0 then return "--" end
    seconds = math.floor(seconds)
    if seconds >= 86400 then return ("%dd %dh"):format(math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)) end
    if seconds >= 3600 then return ("%dh %dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
    if seconds >= 60 then return ("%dm %ds"):format(math.floor(seconds / 60), seconds % 60) end
    return ("%ds"):format(seconds)
end

local function ValidSession(saved, level, now)
    return type(saved) == "table" and Number(saved.started) and saved.started > 0
        and saved.started <= now and now - saved.started < 604800
        and Number(saved.gained) and saved.gained >= 0
        and Number(saved.lastLevel) and saved.lastLevel >= 1 and saved.lastLevel <= level
        and Number(saved.lastXP) and saved.lastXP >= 0
        and Number(saved.lastMax) and saved.lastMax >= 0
        and (saved.lastMax == 0 or saved.lastXP <= saved.lastMax)
        and Number(saved.levelUps) and saved.levelUps >= 0
end

local function CharacterKey()
    local guid = type(UnitGUID) == "function" and UnitGUID("player")
    return S.Public(guid) and type(guid) == "string" and guid ~= "" and guid or nil
end

local function Save(self)
    local root, key = NS.RootDB, CharacterKey()
    if not root or not key or not self.session then return end
    if type(root.suiteXP) ~= "table" then root.suiteXP = {} end
    root.suiteXP[key] = {
        started = self.session.started,
        gained = self.session.gained,
        lastLevel = self.session.lastLevel,
        lastXP = self.session.lastXP,
        lastMax = self.session.lastMax,
        levelUps = self.session.levelUps,
    }
end

local function NewSession(level, current, maximum)
    return {
        started = Clock(),
        gained = 0,
        levelUps = 0,
        lastLevel = level,
        lastXP = current,
        lastMax = maximum
    }
end

local function InitializeSession(self, level, current, maximum)
    if self.session then return end
    local root, key, now = NS.RootDB, CharacterKey(), Clock()
    local saved = root and key and type(root.suiteXP) == "table" and root.suiteXP[key]
    if NS.loginKind == "reload" and ValidSession(saved, level, now) then
        self.session = {
            started = saved.started,
            gained = saved.gained,
            levelUps = saved.levelUps,
            lastLevel = saved.lastLevel,
            lastXP = saved.lastXP,
            lastMax = saved.lastMax,
        }
    else
        self.session = NewSession(level, current, maximum)
    end
    Save(self)
end

local function Track(self, level, current, maximum)
    local session = self.session
    if not session then return end
    local delta = 0
    if level == session.lastLevel then
        if current >= session.lastXP then
            delta = current - session.lastXP
        else
            return
        end -- XP rolled over before PLAYER_LEVEL_UP; retain the old baseline.
    elseif level > session.lastLevel then
        if level == session.lastLevel + 1 then
            delta = math.max(0, session.lastMax - session.lastXP) + current
        end -- Multiple unseen level-ups cannot be reconstructed safely.
        session.levelUps = session.levelUps + (level - session.lastLevel)
    end
    session.gained = session.gained + delta
    session.lastLevel, session.lastXP, session.lastMax = level, current, maximum
    Save(self)
end

local function Rate(self)
    local elapsed = math.max(0, Clock() - (self.session and self.session.started or Clock()))
    if elapsed < 60 or not self.session or self.session.gained <= 0 then return nil, elapsed end
    return self.session.gained * 3600 / elapsed, elapsed
end

local function Tooltip(self)
    if not self.host or not self.host:IsShown() or not GameTooltip then return end
    local level, current, maximum = XP()
    GameTooltip:SetOwner(self.host, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Experience", 0.3, 0.85, 0.95)
    if level and maximum > 0 then
        local remaining = math.max(0, maximum - current)
        GameTooltip:AddDoubleLine("Level", tostring(level), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Current XP", Exact(current) .. " / " .. Exact(maximum), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Remaining", Exact(remaining), 1, 1, 1, 1, 1, 1)
        local rested = Rested()
        GameTooltip:AddDoubleLine("Rested XP", Exact(rested), 1, 1, 1, 0.45, 0.7, 1)
        if rested > 0 then
            GameTooltip:AddDoubleLine("Rested until", current + rested < maximum
                and Exact(current + rested) .. " / " .. Exact(maximum) or "Next level or later",
                1, 1, 1, 0.65, 0.82, 1)
        end
        if self.session then
            local rate, elapsed = Rate(self)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Session XP", "+" .. Exact(self.session.gained), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Session time", Duration(elapsed), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("XP per hour", rate and Exact(rate) or "--", 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Time to level", rate and rate > 0 and Duration(remaining * 3600 / rate) or "--", 1,
                1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Levels this session", tostring(self.session.levelUps), 1, 1, 1, 1, 1, 1)
        end
    else
        GameTooltip:AddLine("No experience progress is available.", 1, 1, 1)
    end
    GameTooltip:Show()
end

local function Create(self)
    if self.host then return end
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("MEDIUM")
    host:EnableMouse(true)
    host:SetScript("OnEnter", function() Tooltip(self) end)
    host:SetScript("OnLeave", function() if GameTooltip and GameTooltip:IsOwned(host) then GameTooltip:Hide() end end)
    local panel = host:CreateTexture(nil, "BACKGROUND")
    panel:SetAllPoints(host)
    local bar = CreateFrame("Frame", nil, host)
    bar:SetPoint("TOPLEFT")
    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    local texture = type(S.ResolveTexture) == "function" and S.ResolveTexture("MSUF Lucent", MSUF_BAR) or MSUF_BAR
    local rested = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    rested:SetPoint("LEFT")
    rested:SetTexture(texture)
    local fill = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    fill:SetPoint("LEFT")
    fill:SetTexture(texture)
    local restedMarker = bar:CreateTexture(nil, "OVERLAY", nil, 3)
    -- Blizzard's XP frame uses a decorated atlas. Separate divider textures
    -- keep the familiar 20-part rhythm crisp at every user-selected width.
    local segments = {}
    for index = 1, SEGMENT_COUNT - 1 do
        local divider = bar:CreateTexture(nil, "OVERLAY", nil, 1)
        divider:SetColorTexture(1, 1, 1, 0.28)
        segments[index] = divider
    end
    local levelText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    levelText:SetPoint("LEFT", bar, "LEFT", 6, 0)
    local percentText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    percentText:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    local details = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    details:SetPoint("TOP", bar, "BOTTOM", 0, -4)
    details:SetJustifyH("CENTER")
    local edges = {}
    for index = 1, 4 do edges[index] = host:CreateTexture(nil, "OVERLAY", nil, 2) end
    edges[1]:SetPoint("TOPLEFT", host, "TOPLEFT")
    edges[1]:SetPoint("TOPRIGHT", host, "TOPRIGHT")
    edges[2]:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT")
    edges[2]:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT")
    edges[3]:SetPoint("TOPLEFT", host, "TOPLEFT")
    edges[3]:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT")
    edges[4]:SetPoint("TOPRIGHT", host, "TOPRIGHT")
    edges[4]:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT")
    local detailRule = host:CreateTexture(nil, "OVERLAY", nil, 1)
    detailRule:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
    detailRule:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -2)
    self.host, self.bar, self.fill, self.rested, self.restedMarker, self.segments = host, bar, fill, rested, restedMarker,
        segments
    self.levelText, self.percentText, self.details = levelText, percentText, details
    self.panel, self.background, self.edges, self.detailRule = panel, background, edges, detailRule
end

local function ApplyLook(self)
    local index = LOOKS[self.config.look] and self.config.look or (NS.Client.isForever and 3 or 2)
    if self.appliedLook == index then return end
    local look = LOOKS[index]
    local shared = NS.ChatLookPresets and NS.ChatLookPresets[index]
    local panel = shared and shared.panelColor or look.panel
    local border = shared and shared.borderColor or look.border
    local accent = shared and shared.accentColor or look.accent
    local text = shared and shared.tabActiveColor or look.text
    local muted = shared and shared.tabInactiveColor or look.muted
    Paint(self.panel, panel, 0.94)
    Paint(self.background, look.track, 0.98)
    Tint(self.fill, accent, 0.98)
    Tint(self.rested, look.rested, 0.78)
    Paint(self.restedMarker, look.rested, 1)
    Paint(self.edges[1], accent, 0.88)
    for index = 2, 4 do Paint(self.edges[index], border, 0.86) end
    Paint(self.detailRule, border, 0.48)
    for _, divider in ipairs(self.segments) do Paint(divider, text, 0.34) end
    local lr, lg, lb = RGB(text)
    local mr, mg, mb = RGB(muted)
    self.levelText:SetTextColor(lr, lg, lb, 1)
    self.percentText:SetTextColor(lr, lg, lb, 1)
    self.details:SetTextColor(mr, mg, mb, 1)
    if type(S.SetFont) == "function" then
        S.SetFont(self.levelText, MSUF_FONT, 11, "OUTLINE")
        S.SetFont(self.percentText, MSUF_FONT, 11, "OUTLINE")
        S.SetFont(self.details, MSUF_FONT, 11, "")
    end
    self.appliedLook = index
end

local Render
local function KeepRateCurrent(self)
    if self.rateTimer or not self.active or not self.host or not self.host:IsShown()
        or not self.session or self.session.gained <= 0
        or not (self.config.showRate or self.config.showETA)
        or not C_Timer or type(C_Timer.NewTimer) ~= "function" then
        return
    end
    local timer
    timer = C_Timer.NewTimer(60, function()
        if self.rateTimer ~= timer then return end
        self.rateTimer = nil
        if self.active then Render(self) end
    end)
    self.rateTimer = timer
end

Render = function(self)
    Create(self)
    ApplyLook(self)
    local c, host, bar = self.config, self.host, self.bar
    local point = POINTS[c.point] or "BOTTOM"
    host:SetScale(c.scale / 100)
    host:SetSize(c.width, c.height + 23)
    host:ClearAllPoints()
    host:SetPoint(point, UIParent, point, c.x, c.y)
    bar:SetSize(c.width, c.height)
    local effectiveScale = type(bar.GetEffectiveScale) == "function" and bar:GetEffectiveScale() or 1
    local pixel = Number(effectiveScale) and effectiveScale > 0 and 1 / effectiveScale or 1
    self.edges[1]:SetHeight(pixel)
    self.edges[2]:SetHeight(pixel)
    self.edges[3]:SetWidth(pixel)
    self.edges[4]:SetWidth(pixel)
    self.detailRule:SetHeight(pixel)
    for index, divider in ipairs(self.segments) do
        divider:ClearAllPoints()
        local x = math.floor((c.width * index / SEGMENT_COUNT) / pixel + 0.5) * pixel
        divider:SetPoint("LEFT", bar, "LEFT", x, 0)
        divider:SetSize(pixel, c.height)
        divider:SetShown(c.showSegments == true)
    end
    self.details:SetWidth(c.width)
    local level, current, maximum = XP()
    if not level then
        if self.rateTimer then
            self.rateTimer:Cancel()
            self.rateTimer = nil
        end
        self.fill:Hide()
        self.rested:Hide()
        self.restedMarker:Hide()
        self.levelText:SetText("XP unavailable")
        self.percentText:SetText("")
        self.details:SetText("Experience data is currently unavailable")
        host:SetShown(S.editMode == true)
        return
    end
    local capped = maximum <= 0
    if not capped and type(GameRulesUtil) == "table" and type(GameRulesUtil.IsPlayerAtEffectiveMaxLevel) == "function" then
        local ok, result = pcall(GameRulesUtil.IsPlayerAtEffectiveMaxLevel)
        capped = ok and S.Public(result) and result == true or false
    end
    host:SetShown(S.editMode or not (c.hideAtMax and capped))
    if not host:IsShown() and self.rateTimer then
        self.rateTimer:Cancel()
        self.rateTimer = nil
    end
    if maximum <= 0 then
        if self.rateTimer then
            self.rateTimer:Cancel()
            self.rateTimer = nil
        end
        self.fill:Hide()
        self.rested:Hide()
        self.restedMarker:Hide()
        self.levelText:SetText("Level " .. level)
        self.percentText:SetText("Max level")
        self.details:SetText(S.editMode and "Experience bar preview" or "")
        return
    end
    local fraction = math.max(0, math.min(1, current / maximum))
    self.fill:SetSize(math.max(0.01, c.width * fraction), c.height)
    self.fill:SetShown(fraction > 0)
    local rested = c.showRested and Rested() or 0
    local restedFraction = math.max(0, math.min(1 - fraction, rested / maximum))
    self.rested:ClearAllPoints()
    self.rested:SetPoint("LEFT", bar, "LEFT", c.width * fraction, 0)
    self.rested:SetSize(math.max(0.01, c.width * restedFraction), c.height)
    self.rested:SetShown(restedFraction > 0)
    local restedEnd = fraction + restedFraction
    self.restedMarker:ClearAllPoints()
    self.restedMarker:SetPoint("CENTER", bar, "LEFT", c.width * restedEnd, 0)
    self.restedMarker:SetSize(pixel * 2, c.height + pixel * 4)
    self.restedMarker:SetShown(restedFraction > 0 and restedEnd > 0.01 and restedEnd < 0.99 and not capped)
    self.levelText:SetText("Lv " .. level .. "  " .. Compact(current) .. " / " .. Compact(maximum))
    self.percentText:SetText(("%.1f%%"):format(fraction * 100))
    local pieces = {}
    local rate = Rate(self)
    if c.showSession then pieces[#pieces + 1] = "Session +" .. Compact(self.session and self.session.gained or 0) end
    if c.showRate then pieces[#pieces + 1] = "XP/h " .. (rate and Compact(rate) or "--") end
    if c.showETA then
        pieces[#pieces + 1] = "To level " .. (rate and rate > 0 and Duration((maximum - current) * 3600 / rate) or "--")
    end
    self.details:SetText(table.concat(pieces, "   •   "))
    if GameTooltip and GameTooltip:IsOwned(host) then Tooltip(self) end
    KeepRateCurrent(self)
end

local function Update(self, event, unit)
    if event == "PLAYER_XP_UPDATE" and unit and unit ~= "player" then return end
    local level, current, maximum = XP()
    if level then
        if not self.session and NS.loginKind then InitializeSession(self, level, current, maximum) end
        if self.session and (event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP") then
            Track(self, level, current, maximum)
        end
    end
    Render(self)
end

local function EnterWorld(self)
    local level, current, maximum = XP()
    if level then InitializeSession(self, level, current, maximum) end
    Render(self)
end

function M:Enable()
    Create(self)
    local context = self.context
    context:Event("PLAYER_ENTERING_WORLD", EnterWorld, true)
    context:Event("PLAYER_XP_UPDATE", Update, true)
    context:Event("PLAYER_LEVEL_UP", Update, true)
    context:Event("UPDATE_EXHAUSTION", Update, true)
    if NS.loginKind then
        local level, current, maximum = XP()
        if level then
            if self.session then
                Track(self, level, current, maximum)
            else
                InitializeSession(self, level, current, maximum)
            end
        end
    end
    Render(self)
    self:RegisterMovers()
end

function M:Refresh() Render(self) end

function M:Disable()
    if self.rateTimer then
        self.rateTimer:Cancel()
        self.rateTimer = nil
    end
    if self.host then self.host:Hide() end
    if GameTooltip and self.host and GameTooltip:IsOwned(self.host) then GameTooltip:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "experience", {
        label = "Experience bar",
        order = 630,
        getFrame = function() return self.host end,
        xKey = "x",
        yKey = "y",
        pointKey = "point",
        point = function() return POINTS[self.config.point] or "BOTTOM" end,
        historyKeys = { "width", "height", "scale" },
        extraControls = {
            {
                id = "width",
                label = "Width",
                kind = "number",
                min = 220,
                max = 800,
                step = 1,
                get = function() return S.Config(ID).width end,
                set = function(value) return S.Set(ID, "width", value) end
            },
            {
                id = "height",
                label = "Height",
                kind = "number",
                min = 8,
                max = 40,
                step = 1,
                get = function() return S.Config(ID).height end,
                set = function(value) return S.Set(ID, "height", value) end
            },
        },
    })
end

function S.ResetXPSession()
    if not M.active then return false end
    local level, current, maximum = XP()
    if not level then return false end
    M.session = NewSession(level, current, maximum)
    Save(M)
    Render(M)
    return true
end

S.Install(ID, M)
