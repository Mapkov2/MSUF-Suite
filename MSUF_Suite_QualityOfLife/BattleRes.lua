local _, P = ...
local NS, S = P.NS, P.Suite
local ID, SPELL_ID = "battleRes", 20484 -- Rebirth exposes the shared combat-resurrection pool.
local POINTS = NS.AnchorPoints
local IN_COMBAT = { inCombat = true }
local M = {}
-- CHALLENGE_MODE_START may precede the API's active-state transition; the
-- key state is read again once, this long after it (self.startJob).
local START_RECHECK = .2

local function EncounterActive()
    local active = C_InstanceEncounter.IsEncounterInProgress()
    return S.Public(active) and active == true
end

local function ChallengeActive()
    local active = C_ChallengeMode.IsChallengeModeActive()
    return S.Public(active) and active == true
end

local CARD = { width = 146, height = 44, fill = { .06, .07, .09, .92 }, edge = 1, line = { .54, .72, .78, .95 } }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SAMPLE_ICON = "Interface\\Icons\\Spell_Nature_Reincarnation"

local function WatchGloss(self, on)
    if on or self.glossWatch then
        NS.HostBridge.WatchIconSkins(ID, on)
        self.glossWatch = on or nil
    end
end

local function Create(self)
    if self.host then return end

    local host, panel, edges = S.QoLCard(CARD)
    if self.previewParent then
        host:SetParent(self.previewParent)
        host:SetFrameStrata(self.previewParent:GetFrameStrata())
    end

    local icon = S.CreateTexture(host, nil, "ARTWORK")
    local cooldown = S.CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(self.previewParent ~= nil)
    cooldown:SetMinimumCountdownDuration(0)
    if self.previewParent then
        local sample = S.CreateFontString(cooldown, nil, "OVERLAY")
        sample:SetPoint("CENTER")
        S.SetFont(sample, nil, 12, "OUTLINE")
        sample:SetText("02:38")
    end

    local title = S.CreateFontString(host, nil, "OVERLAY")
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    S.SetFont(title, nil, 11, "OUTLINE")
    title:SetText(S.Text("Battle Rez"))

    local count = S.CreateFontString(host, nil, "OVERLAY")
    local maximum = S.CreateFontString(host, nil, "OVERLAY")

    host:Hide()
    self.host, self.panel, self.edges, self.cooldown, self.title, self.count, self.maximum, self.icon =
        host, panel, edges, cooldown, title, count, maximum, icon
    self.borderBounds = S.CreateTexture(host, nil, "BACKGROUND")
    self.spellIcon = self.previewParent and SAMPLE_ICON or C_Spell.GetSpellTexture(SPELL_ID)
end

local function ClearTimer(self)
    if self.cooldownActive then self.cooldown:Clear() end
    self.cooldownActive, self.cooldownSample = nil, nil
    if self.durationBinding then self.durationBinding:Disable() end
    if self.time then
        self.time:Hide()
        self.separator:Hide()
    end
end

local function CreateText(self)
    if self.time then return end
    self.time = S.CreateFontString(self.host, nil, "OVERLAY")
    self.separator = S.CreateFontString(self.host, nil, "OVERLAY")
    local c = self.config
    local font = S.ResolveFont(c.font) or (c.font ~= "" and c.font or nil)
    S.SetFont(self.time, font, c.fontSize, "OUTLINE")
    S.SetFont(self.separator, font, c.fontSize, "OUTLINE")
    self.separator:SetText("+")
    if self.previewParent then return end
    local down = Enum.NumericRuleFormatRounding.Down
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    formatter:SetBreakpoints({ { threshold = 0, format = "%02d:%02d", rounding = down,
        components = { { div = 60, rounding = down }, { mod = 60, rounding = down } } } })
    local binding = C_DurationUtil.CreateDurationTextBinding()
    binding:SetFontString(self.time)
    binding:SetFormatter(formatter)
    binding:SetUpdateInterval(1)
    binding:SetZeroDurationText("")
    binding:SetExpiredText("")
    binding:Disable()
    self.durationBinding = binding
end

local function Anchor(region, point, relative, otherPoint, x, y)
    region:ClearAllPoints()
    region:SetPoint(point, relative, otherPoint, x, y)
end

local function BindTime(self, duration)
    -- The duration's contents may be secret; the object itself must be public
    -- for DurationTextBinding:SetDuration (AllowedWhenUntainted).
    if not S.Public(duration) or duration == nil then return end
    self.durationBinding:SetDuration(duration)
    self.durationBinding:Enable()
    self.time:Show()
    self.separator:Show()
end

local function SampleTime(self, editMode)
    if not self.timerShown then return end
    if self.config.textOnly then
        if self.durationBinding then self.durationBinding:Disable() end
        self.time:SetText("02:38")
        self.time:Show()
        self.separator:Show()
    elseif not self.cooldownSample then
        self.cooldown:SetCooldown(GetTime(), editMode and 90 or 158)
        self.cooldownActive, self.cooldownSample = true, true
    end
end

local function Shown(region, value)
    if value then region:Show() else region:Hide() end
end

local function CustomDimension(value, fallback)
    return value and value > 0 and value or fallback
end

local function PaintTexture(region, texture, color, alpha)
    local r, g, b = S.RGB(color)
    if texture and texture ~= "" then
        region:SetTexture(S.ResolveTexture(texture, WHITE))
        region:SetVertexColor(r, g, b, alpha)
    else
        region:SetColorTexture(r, g, b, alpha)
        region:SetVertexColor(1, 1, 1, 1)
    end
end

local function PlaceTimer(self, point, x, y)
    local host, c = self.host, self.config
    local scale = (c.timerSize or 100) / 100
    if c.textOnly then
        if point then
            Anchor(self.time, point, host, point, x, y)
            Anchor(self.separator, "RIGHT", self.time, "LEFT", -2, 0)
        else
            local separatorX = c.fontSize * 13 / 11 + x
            Anchor(self.separator, "LEFT", host, "LEFT", separatorX, y)
            Anchor(self.time, "LEFT", host, "LEFT", separatorX + c.fontSize * scale, y)
        end
    elseif point then
        Anchor(self.cooldown, point, self.icon, point, x / scale, y / scale)
    else
        Anchor(self.cooldown, "CENTER", host, "LEFT", (22 + x) / scale, y / scale)
    end
end

local function PlaceLayer(self, key, x, y)
    local host, c = self.host, self.config
    -- Choice 1 preserves the original placement. Explicit points follow the
    -- icon in card mode and the display itself in text-only mode.
    local point = POINTS[(c[key .. "Point"] or 1) - 1]
    if key == "background" or key == "border" then
        Anchor(key == "background" and self.panel or self.borderBounds, "CENTER", host, "CENTER", x, y)
    elseif key == "icon" then
        Anchor(self.icon, "LEFT", host, "LEFT", 3 + x, y)
    elseif key == "title" then
        Anchor(self.title, "TOPLEFT", host, "LEFT", 48 + x, 17 + y)
    elseif key == "timer" then
        PlaceTimer(self, point, x, y)
    elseif point then
        local relative = c.textOnly and host or self.icon
        Anchor(self[key], point, relative, point, x, y)
    elseif key == "count" then
        if c.textOnly then Anchor(self.count, "LEFT", host, "LEFT", x, y)
        else
            Anchor(self.count, "BOTTOMLEFT", host, "LEFT", 48 + x, -19 + y)
        end
    elseif key == "maximum" then
        Anchor(self.maximum, "BOTTOMLEFT", host, "LEFT", 64 + x, -17 + y)
    end
end

local LAYERS = { "background", "border", "icon", "title", "count", "maximum", "timer" }

local function PaintCard(self, width, height, style)
    local c, compact = self.config, self.config.textOnly == true
    local backgroundAlpha = (c.backgroundOpacity or 92) / 100
    local borderAlpha = (c.borderOpacity or 95) / 100
    local background = not compact and c.backgroundShown ~= false and backgroundAlpha > 0
    local border = not compact and c.borderShown ~= false and borderAlpha > 0
    if background then
        self.panel:SetSize(CustomDimension(c.backgroundWidth, width), CustomDimension(c.backgroundHeight, height))
        PaintTexture(self.panel, c.backgroundTexture, style.background, backgroundAlpha)
    end
    if border then
        local bw, bh = CustomDimension(c.borderWidth, width), CustomDimension(c.borderHeight, height)
        self.borderBounds:SetSize(bw, bh)
        local thickness = math.min(c.borderThickness or 1, bw / 2, bh / 2)
        local r, g, b = S.RGB(style.border)
        S.PlaceEdges(self.edges, self.borderBounds, thickness, r, g, b, borderAlpha)
        local texture = S.ResolveTexture(c.borderTexture)
        for _, edge in ipairs(self.edges) do
            if texture then
                edge:SetTexture(texture)
                edge:SetVertexColor(r, g, b, borderAlpha)
            elseif self.borderTextured then
                edge:SetVertexColor(1, 1, 1, 1)
            end
        end
        self.borderTextured = texture ~= nil
    end
    Shown(self.panel, background)
    Shown(self.borderBounds, border)
    for _, edge in ipairs(self.edges) do Shown(edge, border) end
end

local function PaintElements(self, style)
    local c, compact = self.config, self.config.textOnly == true
    local iconSize = c.iconSize or 38
    self.icon:SetSize(iconSize, iconSize)
    local customIcon = c.iconTexture
    local fileID = tonumber(customIcon)
    if fileID and (fileID < 1 or fileID > 2147483647 or fileID ~= math.floor(fileID)) then customIcon, fileID = nil, nil end
    if self.icon:SetTexture(fileID or (customIcon ~= "" and customIcon) or self.spellIcon) == false then
        self.icon:SetTexture(self.spellIcon)
    end
    self.cooldown:SetSize(38, 38)
    self.cooldown:SetScale((c.timerSize or 100) / 100)
    -- Off leaves only the countdown numbers: no swipe and no finish flash.
    local swipe = c.timerSwipe ~= false
    if self.drawSwipe ~= swipe then
        self.cooldown:SetDrawSwipe(swipe)
        self.cooldown:SetDrawBling(swipe)
        self.drawSwipe = swipe
    end
    if swipe and c.timerTexture and c.timerTexture ~= "" then
        self.cooldown:SetSwipeTexture(S.ResolveTexture(c.timerTexture, WHITE), 0.25, 0.25, 0.25, .8)
        self.customSwipe = true
    elseif self.customSwipe then
        self.cooldown:SetSwipeTexture(WHITE, 0, 0, 0, .8)
        self.customSwipe = nil
    end
    local compactFont = compact and (S.ResolveFont(c.font) or (c.font ~= "" and c.font or nil)) or nil
    S.SetFont(self.title, S.ResolveFont(c.titleFont), c.titleSize or 11, "OUTLINE")
    self.title:SetWidth(math.ceil(self.title:GetUnboundedStringWidth()) + 4)
    local countFont = S.ResolveFont(c.countFont) or compactFont
    local countSize = CustomDimension(c.countSize, compact and c.fontSize or 22)
    S.SetFont(self.count, countFont, countSize, "OUTLINE")
    S.SetFont(self.maximum, S.ResolveFont(c.maximumFont), c.maximumSize or 12, "OUTLINE")
    self.title:SetTextColor(S.RGB(style.muted))
    self.count:SetTextColor(S.RGB(style.text))
    self.maximum:SetTextColor(S.RGB(style.muted))
    self.countShown, self.maximumShown = c.countShown ~= false, not compact and c.maximumShown ~= false
    self.timerShown = c.timerShown ~= false
    Shown(self.icon, not compact and c.iconShown ~= false)
    Shown(self.title, not compact and c.titleShown ~= false)
    Shown(self.count, self.countShown)
    Shown(self.maximum, self.maximumShown)
    Shown(self.cooldown, not compact and self.timerShown)
    if compact then
        CreateText(self)
        local size = c.fontSize * (c.timerSize or 100) / 100
        S.SetFont(self.time, compactFont, size, "OUTLINE")
        S.SetFont(self.separator, compactFont, size, "OUTLINE")
        self.time:SetTextColor(1, 1, 1)
        self.separator:SetTextColor(1, 1, 1)
    end
    if self.compact ~= compact or not self.timerShown then ClearTimer(self) end
    self.compact = compact
end

local function Place(self)
    local c = self.config
    local style = S.QoLStyle(c)
    local width = math.max(c.width, c.textOnly and c.fontSize * 6 or 146)
    local height = math.max(c.height, c.textOnly and c.fontSize + 2 or 44)
    self.host:SetSize(width, height)
    if self.previewViewport then
        local viewport = self.previewViewport
        self.host:SetScale(math.min(viewport.scale, viewport.width / width, viewport.height / height))
    else
        S.PlaceHost(self.host, c)
    end
    PaintCard(self, width, height, style)
    PaintElements(self, style)
    self.hasLayers = self.countShown or self.maximumShown or self.timerShown or self.title:IsShown()
        or self.icon:IsShown() or self.panel:IsShown() or self.borderBounds:IsShown()
    for _, key in ipairs(LAYERS) do PlaceLayer(self, key, c[key .. "X"] or 0, c[key .. "Y"] or 0) end
    if c.glossEnabled or self.glossIconActive then
        self.glossIconActive = NS.GlossMaterial.Icon(self.host, self.icon,
            c.glossEnabled and self.icon:IsShown(), c.glossStrength, c.iconSize or 38) or nil
    end
end

local function ReadInstanceType(self)
    local _, instanceType = GetInstanceInfo()
    self.instanceType = S.Public(instanceType) and type(instanceType) == "string" and instanceType ~= "" and instanceType or nil
end

local function InstancePending(self)
    local kind = self.instanceType
    return not kind or (kind == "none" and (self.challengeActive or self.encounterActive))
end

local function InSharedPool(self)
    if self.instanceType == "party" then return self.challengeActive == true end
    if self.instanceType == "raid" then return self.encounterActive == true end
    return false
end

local Update
local function ChargesChanged(self)
    Update(self)
end

local function WatchCharges(self, watch)
    if self.watching == watch then return end
    self.watching = watch
    if watch then
        self.context:Event("SPELL_UPDATE_CHARGES", ChargesChanged, IN_COMBAT)
    else
        self.context:RemoveEvent("SPELL_UPDATE_CHARGES")
    end
end

local function UpdateRecharge(self, active)
    if not self.timerShown or not S.Public(active) or active ~= true then return ClearTimer(self) end
    local duration = C_Spell.GetSpellChargeDuration(SPELL_ID)
    if S.Public(duration) and duration == nil then return ClearTimer(self) end
    if self.compact then
        ClearTimer(self)
        BindTime(self, duration)
    else
        self.cooldown:SetCooldownFromDurationObject(duration, true)
        self.cooldownActive, self.cooldownSample = true, nil
    end
end

Update = function(self)
    if not self.active then return end
    if not self.hasLayers then
        WatchCharges(self, false)
        self.host:Hide()
        return
    end

    if S.editMode and not NS.IsCombatLocked() then
        WatchCharges(self, false)
        self.count:SetText("2")
        self.maximum:SetText("/3")
        SampleTime(self, true)
        self.host:Show()
        return
    end

    local inPool = InSharedPool(self)
    WatchCharges(self, inPool)
    if not inPool then
        ClearTimer(self)
        self.host:Hide()
        return
    end

    -- The table and its current charge can be secret in combat. Only public
    -- fields guide Lua branches; Blizzard's display string goes to SetText.
    local info = C_Spell.GetSpellCharges(SPELL_ID)
    if not S.Public(info) or type(info) ~= "table" then
        ClearTimer(self)
        self.host:Hide()
        return
    end
    local maximum = info.maxCharges
    if not S.Finite(maximum) or maximum < 1 then
        ClearTimer(self)
        self.host:Hide()
        return
    end

    if self.countShown then
        local display = C_Spell.GetSpellDisplayCount(SPELL_ID)
        if S.Public(display) and (type(display) ~= "string" or display == "") then display = "--" end
        self.count:SetText(display)
    end
    if self.maximumShown then self.maximum:SetFormattedText("/%d", math.floor(maximum)) end
    UpdateRecharge(self, info.isActive)
    self.host:Show()
end

local function ContextChanged(self, event)
    ReadInstanceType(self)
    if event == "ENCOUNTER_START" then
        self.encounterActive = true
    elseif event == "ENCOUNTER_END" then
        self.encounterActive = false
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET"
        or event == "WORLD_STATE_TIMER_STOP" then
        self.challengeActive = false
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        self.encounterActive = EncounterActive()
        self.challengeActive = ChallengeActive()
    else
        self.challengeActive = ChallengeActive()
    end
    Update(self)
    if InstancePending(self) or (event == "CHALLENGE_MODE_START" and (not self.challengeActive or self.instanceType ~= "party")) then
        self.startJob:Request()
    end
end

local function RecheckStart(self)
    ReadInstanceType(self)
    self.challengeActive = ChallengeActive()
    Update(self)
end

function M:Enable()
    WatchGloss(self, self.config.glossEnabled == true)
    self.startJob = self.context:Coalesce(START_RECHECK, RecheckStart)
    Create(self)
    Place(self)
    ReadInstanceType(self)
    self.encounterActive = EncounterActive()
    self.challengeActive = ChallengeActive()
    local context = self.context
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
        "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
        "WORLD_STATE_TIMER_START", "WORLD_STATE_TIMER_STOP", "ENCOUNTER_START", "ENCOUNTER_END" }) do
        context:Event(event, ContextChanged, IN_COMBAT)
    end
    Update(self)
    if InstancePending(self) then self.startJob:Request() end
end

function M:Refresh()
    WatchGloss(self, self.config.glossEnabled == true)
    Place(self)
    ReadInstanceType(self)
    Update(self)
    if InstancePending(self) then self.startJob:Request() end
end

-- The context's Release drops a pending key recheck.
function M:Disable()
    WatchGloss(self, false)
    if self.watching then WatchCharges(self, false) end
    if self.host then
        ClearTimer(self)
        self.host:Hide()
    end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "charges", {
        label = "Battle resurrection", order = 636,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "height", "scale" },
        sizeKeys = { "width", "height", "scale" },
    })
end

function S.DrawBattleResPreview(parent, config, _, viewport)
    local view = parent.suiteBattleResPreview
    if not view then
        view = { previewParent = parent }
        parent.suiteBattleResPreview = view
    end
    view.config, view.previewViewport = config, viewport
    Create(view)
    Place(view)
    view.count:SetText("2")
    view.maximum:SetText("/3")
    SampleTime(view)
    view.host:Show()
    return view.host
end

function S.MoveBattleResPreviewLayer(view, key, x, y)
    PlaceLayer(view, key, x, y)
end

function S.HideBattleResPreview(parent)
    local view = parent.suiteBattleResPreview
    if view then ClearTimer(view) end
end

S.Install(ID, M)
