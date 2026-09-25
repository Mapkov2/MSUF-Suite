local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "announcements"
local M = { queue = {}, generation = 0 }
local FALLBACK_FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"
local COLORS = {
    zone = { .96, .88, .67 }, quest = { .98, .79, .39 },
    achievement = { .88, .69, .41 }, level = { .47, .81, .98 },
    scenario = { .69, .58, .96 }, notice = { .66, .84, .98 },
}
local COLOR_KEYS = {
    zone = "zoneColor", quest = "questColor", achievement = "achievementColor",
    level = "levelColor", scenario = "scenarioColor", notice = "noticeColor",
}

local function Text(value)
    return S.Public(value) and type(value) == "string" and value ~= "" and value or nil
end
local function Number(value)
    return S.Public(value) and type(value) == "number" and value == value
end
local function SafeText(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    return ok and Text(value) or nil
end

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", "MSUFSuiteAnnouncements", UIParent)
    host:SetSize(660, 130)
    host:SetFrameStrata("HIGH")
    host:EnableMouse(false)
    local background = S.CreateTexture(host, nil, "BACKGROUND")
    background:SetPoint("TOPLEFT", 65, -8)
    background:SetPoint("BOTTOMRIGHT", -65, 11)
    local accent = S.CreateTexture(host, nil, "ARTWORK")
    accent:SetPoint("TOP", 0, -12)
    accent:SetSize(35, 2)
    local title = S.CreateFontString(host, nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 14, -23)
    title:SetPoint("TOPRIGHT", -14, -23)
    title:SetJustifyH("CENTER")
    title:SetWordWrap(false)
    local divider = S.CreateTexture(host, nil, "ARTWORK")
    divider:SetPoint("CENTER", 0, -10)
    divider:SetSize(260, 1)
    local subtitle = S.CreateFontString(host, nil, "OVERLAY")
    subtitle:SetPoint("TOPLEFT", 18, -84)
    subtitle:SetPoint("TOPRIGHT", -18, -84)
    subtitle:SetJustifyH("CENTER")
    subtitle:SetWordWrap(false)
    local enter = host:CreateAnimationGroup()
    local fadeIn = enter:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(.22)
    local leave = host:CreateAnimationGroup()
    local fadeOut = leave:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(.36)
    leave:SetScript("OnFinished", function()
        if not self.active or S.editMode then return end
        host:Hide()
        self.showing = false
        self:Next()
    end)
    self.host, self.background, self.accent = host, background, accent
    self.title, self.divider, self.subtitle = title, divider, subtitle
    self.enter, self.leave = enter, leave
    self.hiddenParent = S.CreateFrame("Frame", nil, UIParent)
    self.hiddenParent:Hide()
    host:Hide()
end

local function Theme(self)
    local c = self.config
    local skin = self.context and self.context:Skin()
    local font = S.ResolveFont(c.font) or (skin and skin:GetFont()) or FALLBACK_FONT
    S.SetStyledFont(self.title, font, c.titleSize or 31, "OUTLINE", 1, true, 80, 2)
    S.SetStyledFont(self.subtitle, font, c.subtitleSize or 16, "OUTLINE", 1, true, 75, 1)
    local dark = not skin or skin:GetLook() == "midnightDark"
    local custom = c.colorStyle == 2
    self.kindColors = {}
    for kind, key in pairs(COLOR_KEYS) do
        self.kindColors[kind] = custom and { S.RGB(c[key]) } or COLORS[kind]
    end
    local opacity = (c.backgroundOpacity or (dark and 57 or 50)) / 100
    if custom then
        local r, g, b = S.RGB(c.backgroundColor)
        self.background:SetColorTexture(r, g, b, opacity)
        self.subtitle:SetTextColor(S.RGB(c.subtitleColor))
    elseif skin then
        local r, g, b = skin:GetColor("surface")
        self.background:SetColorTexture(r, g, b, opacity)
        self.subtitle:SetTextColor(skin:GetColor("text"))
    else
        self.background:SetColorTexture(dark and .02 or .03, dark and .025 or .05,
            dark and .035 or .075, opacity)
        self.subtitle:SetTextColor(.91, .93, .96)
    end
    self.host:SetScale(self.config.scale / 100)
    self.host:ClearAllPoints()
    local point = c.anchor == 2 and "CENTER" or "TOP"
    self.host:SetPoint(point, UIParent, point, c.x, c.y)
end

local function Paint(self, item)
    local color = self.kindColors[item.kind] or self.kindColors.zone
    self.title:SetText(item.title)
    self.title:SetTextColor(color[1], color[2], color[3])
    self.subtitle:SetText(item.subtitle or "")
    self.accent:SetColorTexture(color[1], color[2], color[3], .95)
    self.divider:SetColorTexture(color[1], color[2], color[3], .62)
end

local function Display(self, item)
    self.current = item
    self.leave:Stop()
    self.enter:Stop()
    Paint(self, item)
    self.host:SetAlpha(1)
    self.host:Show()
    self.enter:Play()
    self.showing = true
    self.serial = (self.serial or 0) + 1
    local serial, generation = self.serial, self.generation
    C_Timer.After(self.config.duration, function()
        if self.active and not S.editMode and self.generation == generation
            and self.serial == serial then self.leave:Play() end
    end)
end

function M:Next()
    if not self.active or self.showing or S.editMode or #self.queue == 0 then return end
    Display(self, table.remove(self.queue, 1))
end

local function Enqueue(self, kind, title, subtitle, key)
    if not self.active or not Text(title) then return end
    local now = GetTime()
    if key and self.lastKey == key and now - (self.lastTime or 0) < 2 then return end
    self.lastKey, self.lastTime = key, now
    local item = { kind = kind, title = title, subtitle = subtitle }
    if #self.queue >= 4 then table.remove(self.queue, 1) end
    self.queue[#self.queue + 1] = item
    self:Next()
end

local function Direct(self, kind, title, subtitle, key)
    self.lastDirect = self.lastDirect or {}
    self.lastDirect[kind] = GetTime()
    Enqueue(self, kind, title, subtitle, key)
end

local function Zone(self)
    self.zoneScheduled = false
    if not self.active or not self.config.zone then return end
    local zone = SafeText(GetZoneText)
    local subzone = SafeText(GetSubZoneText)
    if not zone then return end
    local key = zone .. "/" .. (subzone or "")
    if self.lastZone == key then return end
    self.lastZone = key
    Enqueue(self, "zone", subzone or zone, subzone and zone or "NEW AREA", "zone:" .. key)
end

local function Event(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if self.ApplyNative then self:ApplyNative() end
        local initialLogin, reload = ...
        if initialLogin or reload then
            self.lastZone = (SafeText(GetZoneText) or "") .. "/" .. (SafeText(GetSubZoneText) or "")
        else
            self.lastZone = nil
            if self.config.zone and not self.zoneScheduled then
                self.zoneScheduled = true
                local generation = self.generation
                C_Timer.After(0, function() if self.generation == generation then Zone(self) end end)
            end
        end
        return
    end
    if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS"
        or event == "ZONE_CHANGED_NEW_AREA" then
        if self.zoneScheduled then return end
        self.zoneScheduled = true
        local generation = self.generation
        C_Timer.After(0, function() if self.generation == generation then Zone(self) end end)
    elseif event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" then
        if not self.config.quests then return end
        local arg1, arg2 = ...
        local id = Number(arg2) and arg2 or Number(arg1) and arg1
        if not id then return end
        local title = SafeText(C_QuestLog and C_QuestLog.GetTitleForQuestID, id)
        if title then Direct(self, "quest", title,
            event == "QUEST_ACCEPTED" and "QUEST ACCEPTED" or "QUEST COMPLETE",
            event .. ":" .. id) end
    elseif event == "ACHIEVEMENT_EARNED" and self.config.achievements then
        local id = ...
        if not Number(id) or type(GetAchievementInfo) ~= "function" then return end
        local ok, _, name = pcall(GetAchievementInfo, id)
        if ok and Text(name) then Direct(self, "achievement", name, "ACHIEVEMENT EARNED", "achievement:" .. id) end
    elseif event == "PLAYER_LEVEL_UP" and self.config.level then
        local level = ...
        if Number(level) then Direct(self, "level", "LEVEL " .. tostring(level), "LEVEL UP", "level:" .. level) end
    elseif event == "SCENARIO_COMPLETED" and self.config.scenario then
        Direct(self, "scenario", "SCENARIO COMPLETE", SafeText(C_Scenario and C_Scenario.GetInfo), "scenario")
    end
end

local function ToastKind(eventType)
    local types = Enum and Enum.EventToastEventType
    if not types or not Number(eventType) then return "notice" end
    if eventType == types.QuestTurnedIn then return "quest" end
    if eventType == types.Scenario then return "scenario" end
    if eventType == types.LevelUp or eventType == types.LevelUpSpell
        or eventType == types.LevelUpDungeon or eventType == types.LevelUpRaid
        or eventType == types.LevelUpPvP or eventType == types.LevelUpOther then return "level" end
    return "notice"
end

local function ToastData(frame)
    local ok, info = pcall(function()
        local toast = frame.currentDisplayingToast
        return toast and toast.toastInfo
    end)
    if not ok or not S.Public(info) or not info then return nil end
    local fields, eventType, title, subtitle, id = pcall(function()
        return info.eventType, info.title, info.subtitle, info.eventToastID
    end)
    if not fields then return nil end
    return ToastKind(eventType), Text(title), Text(subtitle), Number(id) and id or nil
end

local function NativeZone(self)
    if NS.IsCombatLocked() or not self.context then return end
    for _, spec in ipairs({
        { "ZoneTextFrame", "zone" }, { "SubZoneTextFrame", "zone" },
        { "LevelUpDisplay", "level" }, { "LevelUpDisplaySide", "level" },
        { "ObjectiveTrackerTopBannerFrame", "quests" },
        { "WorldQuestCompleteBannerFrame", "quests" },
    }) do
        local frame = _G[spec[1]]
        if frame and not NS.Safety.IsForbidden(frame) then
            if self.config[spec[2]] then
                self.context:Property(frame, "GetParent", "SetParent", self.hiddenParent)
                self.context:HideControl(frame, true)
            else
                self.context:RestoreProperty(frame, "SetParent")
                self.context:HideControl(frame, false)
            end
        end
    end
end

local function NativeToasts(self)
    local frame = _G.EventToastManagerFrame
    if not frame or NS.Safety.IsForbidden(frame) then return end
    if not NS.IsCombatLocked() then
        local kind = ToastData(frame)
        local enabled = self.config.eventToasts and (kind == nil
            or kind == "notice" or self.config[kind == "quest" and "quests" or kind])
        self.context:HideControl(frame, enabled == true)
    end
    self.toastHooks = self.toastHooks or setmetatable({}, { __mode = "k" })
    if self.toastHooks[frame] or type(hooksecurefunc) ~= "function"
        or type(frame.DisplayToast) ~= "function" then return end
    local hooked = pcall(hooksecurefunc, frame, "DisplayToast", function(manager)
        if not self.active or not self.context then return end
        local kind, title, subtitle, id = ToastData(manager)
        local allowed = self.config.eventToasts and (kind == nil
            or kind == "notice" or self.config[kind == "quest" and "quests" or kind])
        if not NS.IsCombatLocked() then self.context:HideControl(manager, allowed == true) end
        if not allowed or not title then return end
        local recent = self.lastDirect and self.lastDirect[kind]
        if recent and GetTime() - recent < 1.5 then return end
        Enqueue(self, kind, title, subtitle, "toast:" .. tostring(id or title))
    end)
    if hooked then self.toastHooks[frame] = true end
end

local function SuppressAlerts(self, system, kind)
    if not self.active or not self.config[kind] or NS.IsCombatLocked() then return end
    local pool = system and system.alertFramePool
    if not pool or type(pool.EnumerateActive) ~= "function" then return end
    local frames = {}
    for frame in pool:EnumerateActive() do frames[#frames + 1] = frame end
    for i = 1, #frames do
        local frame = frames[i]
        if frame and not NS.Safety.IsForbidden(frame) then
            self.context:Property(frame, "GetParent", "SetParent", self.hiddenParent)
            self.alertFrames[frame] = kind
        end
    end
end

local ALERT_SYSTEMS = {
    { "AchievementAlertSystem", "achievements" },
    { "ScenarioAlertSystem", "scenario" },
    { "WorldQuestCompleteAlertSystem", "quests" },
}
local function NativeAlerts(self)
    self.alertHooks = self.alertHooks or setmetatable({}, { __mode = "k" })
    self.alertFrames = self.alertFrames or setmetatable({}, { __mode = "k" })
    for frame, kind in pairs(self.alertFrames) do
        if not self.config[kind] then
            self.context:RestoreProperty(frame, "SetParent")
            self.alertFrames[frame] = nil
        end
    end
    for i = 1, #ALERT_SYSTEMS do
        local spec = ALERT_SYSTEMS[i]
        local system = _G[spec[1]]
        if system then
            if not self.alertHooks[system] and type(hooksecurefunc) == "function"
                and type(system.ShowAlert) == "function" then
                local kind = spec[2]
                local hooked = pcall(hooksecurefunc, system, "ShowAlert", function(target, data)
                    SuppressAlerts(self, target, kind)
                    if not self.active or not self.config[kind] or not S.Public(data)
                        or type(data) ~= "table" then return end
                    local title = kind == "quests" and Text(data.taskName)
                        or kind == "scenario" and Text(data.name)
                    local recent = self.lastDirect and self.lastDirect[kind]
                    if title and (not recent or GetTime() - recent >= 1.5) then
                        Enqueue(self, kind, title,
                            kind == "quests" and "QUEST COMPLETE" or "SCENARIO COMPLETE",
                            "alert:" .. kind .. ":" .. title)
                    end
                end)
                if hooked then self.alertHooks[system] = true end
            end
            SuppressAlerts(self, system, spec[2])
        end
    end
end

local function NativeAnnouncements(self)
    NativeZone(self)
    NativeToasts(self)
    NativeAlerts(self)
end
M.ApplyNative = NativeAnnouncements

function M:Enable()
    self.generation = self.generation + 1
    self.active = true
    Create(self)
    Theme(self)
    self.queue, self.showing = {}, false
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
        "ZONE_CHANGED_NEW_AREA", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "ACHIEVEMENT_EARNED",
        "PLAYER_LEVEL_UP", "SCENARIO_COMPLETED" }) do
        self.context:Event(event, Event, true)
    end
    self.context:Event("PLAYER_REGEN_ENABLED", NativeAnnouncements, true)
    self.lastZone = (SafeText(GetZoneText) or "") .. "/" .. (SafeText(GetSubZoneText) or "")
    NativeAnnouncements(self)
    local c = self.config
    self.nativeSignature = table.concat({ tostring(c.zone), tostring(c.eventToasts),
        tostring(c.quests), tostring(c.achievements), tostring(c.level), tostring(c.scenario) }, ":")
    self:RegisterMovers()
    if S.editMode then self:Refresh() end
end

function M:Refresh()
    Theme(self)
    local c = self.config
    local signature = table.concat({ tostring(c.zone), tostring(c.eventToasts),
        tostring(c.quests), tostring(c.achievements), tostring(c.level), tostring(c.scenario) }, ":")
    if self.nativeSignature ~= signature then
        NativeAnnouncements(self)
        self.nativeSignature = signature
    end
    if S.editMode then
        self.enter:Stop(); self.leave:Stop()
        self.serial = (self.serial or 0) + 1
        Paint(self, { kind = "zone", title = "ANNOUNCEMENTS", subtitle = "Zone and event preview" })
        self.host:SetAlpha(1); self.host:Show()
    elseif self.showing and self.current then
        Paint(self, self.current)
    else
        self.host:Hide()
        self:Next()
    end
end

function M:Disable()
    self.generation = self.generation + 1
    self.serial = (self.serial or 0) + 1
    self.enter:Stop(); self.leave:Stop()
    self.queue, self.showing, self.current = {}, false, nil
    if self.host then self.host:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "banner", {
        label = "Announcements", order = 626, getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "anchor",
        point = function() return self.config.anchor == 2 and "CENTER" or "TOP" end,
        historyKeys = { "scale" },
    })
end

S.Install(ID, M)
