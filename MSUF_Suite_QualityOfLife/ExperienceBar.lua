local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local ID = "xpBar"
local SEGMENT_COUNT = 20
local SESSION_MAX_AGE = 604800
local POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local MSUF_BAR, MSUF_FONT = P.MSUF_BAR_TEXTURE, P.MSUF_FONT
local DETAIL_SEPARATOR = "   •   "
local GetServerTime = type(GetServerTime) == "function" and GetServerTime or time
local GetXPExhaustion = GetXPExhaustion
local RGB = S.RGB
local floor, max, min = math.floor, math.max, math.min
-- Match the authored Blue, Dark and Forever palettes used by the Suite's MSUF chat
-- looks. The XP and rested fills stay visually distinct within each palette.
local LOOKS = {
    { panel = "0a1220", track = "102033", border = "41627a", accent = "57c7df",
        text = "f4f7fb", muted = "aab5c2", rested = "558bdd" },
    { panel = "151719", track = "202326", border = "575b58", accent = "b9ab86",
        text = "e9e9e4", muted = "b9bdb9", rested = "777d70" },
    { panel = "14181b", track = "20272a", border = "9f8960", accent = "d8b66a",
        text = "f4f3eb", muted = "d4dce2", rested = "668db8" },
}
local TEXT = {
    experience = S.Text("Experience"),
    level = S.Text("Level"),
    currentXP = S.Text("Current XP"),
    remaining = S.Text("Remaining"),
    restedXP = S.Text("Rested XP"),
    restedUntil = S.Text("Rested until"),
    nextLevel = S.Text("Next level or later"),
    sessionXP = S.Text("Session XP"),
    sessionTime = S.Text("Session time"),
    perHour = S.Text("XP per hour"),
    timeToLevel = S.Text("Time to level"),
    levelUps = S.Text("Levels this session"),
    noProgress = S.Text("No experience progress is available."),
    unavailable = S.Text("XP unavailable"),
    unavailableDetails = S.Text("Experience data is currently unavailable"),
    maxLevel = S.Text("Max level"),
    preview = S.Text("Experience bar preview"),
    short = S.Text("Lv"),
    session = S.Text("Session"),
    rate = S.Text("XP/h"),
    toLevel = S.Text("To level"),
}
-- Reused for the details line; table.concat reads only the filled prefix.
local detailParts = {}

local function Paint(texture, hex, alpha)
    local r, g, b = RGB(hex)
    texture:SetColorTexture(r, g, b, alpha)
end

local function Tint(texture, hex, alpha)
    local r, g, b = RGB(hex)
    texture:SetVertexColor(r, g, b, alpha)
end

local Finite = S.Finite

local function Clock()
    local value = GetServerTime()
    return Finite(value) and floor(value) or 0
end

local function XP()
    local level, current, maximum = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
    if not Finite(level) or not Finite(current) or not Finite(maximum)
        or level < 1 or current < 0 or maximum < 0 then
        return nil
    end
    return level, current, maximum
end

local function Rested()
    if type(GetXPExhaustion) ~= "function" then return 0 end
    local value = GetXPExhaustion()
    return Finite(value) and max(0, value) or 0
end

local function Exact(value)
    value = max(0, floor(value or 0))
    return type(BreakUpLargeNumbers) == "function" and BreakUpLargeNumbers(value) or tostring(value)
end

local function Compact(value)
    value = max(0, value or 0)
    if value >= 1000000 then return ("%.1fm"):format(value / 1000000) end
    if value >= 10000 then return ("%.0fk"):format(value / 1000) end
    if value >= 1000 then return ("%.1fk"):format(value / 1000) end
    return tostring(floor(value))
end

local function Duration(seconds)
    if not Finite(seconds) or seconds < 0 then return "--" end
    seconds = floor(seconds)
    if seconds >= 86400 then return ("%dd %dh"):format(floor(seconds / 86400), floor(seconds % 86400 / 3600)) end
    if seconds >= 3600 then return ("%dh %dm"):format(floor(seconds / 3600), floor(seconds % 3600 / 60)) end
    if seconds >= 60 then return ("%dm %ds"):format(floor(seconds / 60), seconds % 60) end
    return ("%ds"):format(seconds)
end

local function ValidSession(saved, level, now)
    return type(saved) == "table" and Finite(saved.started) and saved.started > 0
        and saved.started <= now and now - saved.started < SESSION_MAX_AGE
        and Finite(saved.gained) and saved.gained >= 0
        and Finite(saved.lastLevel) and saved.lastLevel >= 1 and saved.lastLevel <= level
        and Finite(saved.lastXP) and saved.lastXP >= 0
        and Finite(saved.lastMax) and saved.lastMax >= 0
        and (saved.lastMax == 0 or saved.lastXP <= saved.lastMax)
        and Finite(saved.levelUps) and saved.levelUps >= 0
end

local function CharacterKey()
    local guid = type(UnitGUID) == "function" and UnitGUID("player")
    return S.Public(guid) and type(guid) == "string" and guid ~= "" and guid or nil
end

-- The saved record is rewritten in place on every tracked XP event.
local function Save(self)
    local root, key, session = NS.RootDB, CharacterKey(), self.session
    if not root or not key or not session then return end
    if type(root.suiteXP) ~= "table" then root.suiteXP = {} end
    local saved = root.suiteXP[key]
    if type(saved) ~= "table" then
        saved = {}
        root.suiteXP[key] = saved
    end
    saved.started, saved.gained, saved.levelUps = session.started, session.gained, session.levelUps
    saved.lastLevel, saved.lastXP, saved.lastMax = session.lastLevel, session.lastXP, session.lastMax
end

local function NewSession(level, current, maximum)
    return { started = Clock(), gained = 0, levelUps = 0, lastLevel = level, lastXP = current, lastMax = maximum }
end

local function InitializeSession(self, level, current, maximum)
    if self.session then return end
    local root, key, now = NS.RootDB, CharacterKey(), Clock()
    local saved = root and key and type(root.suiteXP) == "table" and root.suiteXP[key]
    if NS.loginKind == "reload" and ValidSession(saved, level, now) then
        self.session = {
            started = saved.started, gained = saved.gained, levelUps = saved.levelUps,
            lastLevel = saved.lastLevel, lastXP = saved.lastXP, lastMax = saved.lastMax,
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
        -- XP rolled over before PLAYER_LEVEL_UP: retain the old baseline.
        if current < session.lastXP then return end
        delta = current - session.lastXP
    elseif level > session.lastLevel then
        -- Multiple unseen level-ups cannot be reconstructed safely.
        if level == session.lastLevel + 1 then
            delta = max(0, session.lastMax - session.lastXP) + current
        end
        session.levelUps = session.levelUps + (level - session.lastLevel)
    end
    session.gained = session.gained + delta
    session.lastLevel, session.lastXP, session.lastMax = level, current, maximum
    Save(self)
end

local function Rate(self)
    local session = self.session
    local now = Clock()
    local elapsed = max(0, now - (session and session.started or now))
    if elapsed < 60 or not session or session.gained <= 0 then return nil, elapsed end
    return session.gained * 3600 / elapsed, elapsed
end

local function AddSessionLines(self, remaining)
    local rate, elapsed = Rate(self)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(TEXT.sessionXP, "+" .. Exact(self.session.gained), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine(TEXT.sessionTime, Duration(elapsed), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine(TEXT.perHour, rate and Exact(rate) or "--", 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine(TEXT.timeToLevel, rate and rate > 0 and Duration(remaining * 3600 / rate) or "--",
        1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine(TEXT.levelUps, tostring(self.session.levelUps), 1, 1, 1, 1, 1, 1)
end

local function Tooltip(self)
    if not self.host or not self.host:IsShown() or not GameTooltip then return end
    local level, current, maximum = XP()
    GameTooltip:SetOwner(self.host, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(TEXT.experience, 0.3, 0.85, 0.95)
    if level and maximum > 0 then
        local remaining = max(0, maximum - current)
        GameTooltip:AddDoubleLine(TEXT.level, tostring(level), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(TEXT.currentXP, Exact(current) .. " / " .. Exact(maximum), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(TEXT.remaining, Exact(remaining), 1, 1, 1, 1, 1, 1)
        local rested = Rested()
        GameTooltip:AddDoubleLine(TEXT.restedXP, Exact(rested), 1, 1, 1, 0.45, 0.7, 1)
        if rested > 0 then
            GameTooltip:AddDoubleLine(TEXT.restedUntil, current + rested < maximum
                and Exact(current + rested) .. " / " .. Exact(maximum) or TEXT.nextLevel,
                1, 1, 1, 0.65, 0.82, 1)
        end
        if self.session then AddSessionLines(self, remaining) end
    else
        GameTooltip:AddLine(TEXT.noProgress, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function HostEnter() Tooltip(M) end

local function HostLeave(host)
    if GameTooltip and GameTooltip:IsOwned(host) then GameTooltip:Hide() end
end

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("MEDIUM")
    host:EnableMouse(true)
    host:SetScript("OnEnter", HostEnter)
    host:SetScript("OnLeave", HostLeave)
    local panel = host:CreateTexture(nil, "BACKGROUND")
    panel:SetAllPoints(host)
    local bar = S.CreateFrame("Frame", nil, host)
    bar:SetPoint("TOPLEFT")
    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    local texture = S.ResolveTexture("MSUF Lucent", MSUF_BAR)
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
    self.host, self.bar, self.panel, self.background = host, bar, panel, background
    self.fill, self.rested, self.restedMarker, self.segments = fill, rested, restedMarker, segments
    self.levelText, self.percentText, self.details = levelText, percentText, details
    self.edges, self.detailRule = edges, detailRule
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
    for edge = 2, 4 do Paint(self.edges[edge], border, 0.86) end
    Paint(self.detailRule, border, 0.48)
    for _, divider in ipairs(self.segments) do Paint(divider, text, 0.34) end
    local textR, textG, textB = RGB(text)
    local mutedR, mutedG, mutedB = RGB(muted)
    self.levelText:SetTextColor(textR, textG, textB, 1)
    self.percentText:SetTextColor(textR, textG, textB, 1)
    self.details:SetTextColor(mutedR, mutedG, mutedB, 1)
    S.SetFont(self.levelText, MSUF_FONT, 11, "OUTLINE")
    S.SetFont(self.percentText, MSUF_FONT, 11, "OUTLINE")
    S.SetFont(self.details, MSUF_FONT, 11, "")
    self.appliedLook = index
end

-- Geometry and style: settings, scale and Edit Mode changes only.
local function Layout(self)
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
    local pixel = Finite(effectiveScale) and effectiveScale > 0 and 1 / effectiveScale or 1
    self.pixel = pixel
    self.edges[1]:SetHeight(pixel)
    self.edges[2]:SetHeight(pixel)
    self.edges[3]:SetWidth(pixel)
    self.edges[4]:SetWidth(pixel)
    self.detailRule:SetHeight(pixel)
    for index, divider in ipairs(self.segments) do
        divider:ClearAllPoints()
        local x = floor((c.width * index / SEGMENT_COUNT) / pixel + 0.5) * pixel
        divider:SetPoint("LEFT", bar, "LEFT", x, 0)
        divider:SetSize(pixel, c.height)
        divider:SetShown(c.showSegments == true)
    end
    self.details:SetWidth(c.width)
end

local function CancelRateTimer(self)
    if self.rateTimer then
        self.rateTimer:Cancel()
        self.rateTimer = nil
    end
end

local PaintValues
local function KeepRateCurrent(self)
    if self.rateTimer or not self.active or not self.host:IsShown()
        or not self.session or self.session.gained <= 0
        or not (self.config.showRate or self.config.showETA)
        or not C_Timer or type(C_Timer.NewTimer) ~= "function" then
        return
    end
    local timer
    timer = C_Timer.NewTimer(60, function()
        if self.rateTimer ~= timer then return end
        self.rateTimer = nil
        if self.active then PaintValues(self) end
    end)
    self.rateTimer = timer
end

local function HideProgress(self, levelText, percentText, detailsText)
    CancelRateTimer(self)
    self.fill:Hide()
    self.rested:Hide()
    self.restedMarker:Hide()
    self.levelText:SetText(levelText)
    self.percentText:SetText(percentText)
    self.details:SetText(detailsText)
end

-- The effective maximum level only changes with the level itself.
local function AtEffectiveMaxLevel(self, level)
    if self.cappedLevel ~= level then
        local rules = GameRulesUtil
        local result = type(rules) == "table" and type(rules.IsPlayerAtEffectiveMaxLevel) == "function"
            and rules.IsPlayerAtEffectiveMaxLevel()
        self.cappedLevel, self.capped = level, S.Public(result) and result == true
    end
    return self.capped
end

local function PaintRested(self, fraction, maximum, capped)
    local c, pixel = self.config, self.pixel
    local rested = c.showRested and Rested() or 0
    local restedFraction = max(0, min(1 - fraction, rested / maximum))
    self.rested:ClearAllPoints()
    self.rested:SetPoint("LEFT", self.bar, "LEFT", c.width * fraction, 0)
    self.rested:SetSize(max(0.01, c.width * restedFraction), c.height)
    self.rested:SetShown(restedFraction > 0)
    local restedEnd = fraction + restedFraction
    self.restedMarker:ClearAllPoints()
    self.restedMarker:SetPoint("CENTER", self.bar, "LEFT", c.width * restedEnd, 0)
    self.restedMarker:SetSize(pixel * 2, c.height + pixel * 4)
    self.restedMarker:SetShown(restedFraction > 0 and restedEnd > 0.01 and restedEnd < 0.99 and not capped)
end

local function DetailsText(self, current, maximum)
    local c = self.config
    local rate = Rate(self)
    local count = 0
    if c.showSession then
        count = count + 1
        detailParts[count] = TEXT.session .. " +" .. Compact(self.session and self.session.gained or 0)
    end
    if c.showRate then
        count = count + 1
        detailParts[count] = TEXT.rate .. " " .. (rate and Compact(rate) or "--")
    end
    if c.showETA then
        count = count + 1
        detailParts[count] = TEXT.toLevel .. " "
            .. (rate and rate > 0 and Duration((maximum - current) * 3600 / rate) or "--")
    end
    return table.concat(detailParts, DETAIL_SEPARATOR, 1, count)
end

-- Values only: XP, rested and rate changes never move the bar or its dividers.
PaintValues = function(self)
    local c, host = self.config, self.host
    local level, current, maximum = XP()
    if not level then
        HideProgress(self, TEXT.unavailable, "", TEXT.unavailableDetails)
        host:SetShown(S.editMode == true)
        return
    end
    local capped = maximum <= 0 or AtEffectiveMaxLevel(self, level)
    host:SetShown(S.editMode or not (c.hideAtMax and capped))
    if not host:IsShown() then CancelRateTimer(self) end
    if maximum <= 0 then
        HideProgress(self, TEXT.level .. " " .. level, TEXT.maxLevel, S.editMode and TEXT.preview or "")
        return
    end
    local fraction = max(0, min(1, current / maximum))
    self.fill:SetSize(max(0.01, c.width * fraction), c.height)
    self.fill:SetShown(fraction > 0)
    PaintRested(self, fraction, maximum, capped)
    self.levelText:SetText(TEXT.short .. " " .. level .. "  " .. Compact(current) .. " / " .. Compact(maximum))
    self.percentText:SetText(("%.1f%%"):format(fraction * 100))
    self.details:SetText(DetailsText(self, current, maximum))
    if GameTooltip and GameTooltip:IsOwned(host) then Tooltip(self) end
    KeepRateCurrent(self)
end

local function Render(self)
    Layout(self)
    PaintValues(self)
end

local function XPChanged(self, event, unit)
    if event == "PLAYER_XP_UPDATE" and unit and unit ~= "player" then return end
    local level, current, maximum = XP()
    if level then
        if not self.session and NS.loginKind then InitializeSession(self, level, current, maximum) end
        if self.session and (event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP") then
            Track(self, level, current, maximum)
        end
    end
    PaintValues(self)
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
    context:Event("PLAYER_XP_UPDATE", XPChanged, true)
    context:Event("PLAYER_LEVEL_UP", XPChanged, true)
    context:Event("UPDATE_EXHAUSTION", XPChanged, true)
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
    CancelRateTimer(self)
    if self.host then
        self.host:Hide()
        HostLeave(self.host)
    end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "experience", {
        label = "Experience bar", order = 630, getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "BOTTOM" end,
        historyKeys = { "width", "height", "scale" },
        extraControls = {
            { id = "width", label = "Width", kind = "number", min = 220, max = 800, step = 1,
                get = function() return S.Config(ID).width end,
                set = function(value) return S.Set(ID, "width", value) end },
            { id = "height", label = "Height", kind = "number", min = 8, max = 40, step = 1,
                get = function() return S.Config(ID).height end,
                set = function(value) return S.Set(ID, "height", value) end },
        },
    })
end

function S.ResetXPSession()
    if not M.active then return false end
    local level, current, maximum = XP()
    if not level then return false end
    M.session = NewSession(level, current, maximum)
    Save(M)
    PaintValues(M)
    return true
end

S.Install(ID, M)
