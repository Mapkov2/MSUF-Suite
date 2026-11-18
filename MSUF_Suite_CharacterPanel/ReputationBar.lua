local _, NS = ...
local S, Text = NS.Suite, NS.Text
local Header, Reaction = NS.Host.CharacterHeader, NS.Reputation.Reaction
local Finite, Number = NS.Host.Finite, NS.Number
local ID = "reputationBar"
local M = { palette = {} }
local IN_COMBAT = { inCombat = true }
local TITLE = Text("Reputation bar")
local PROGRESS, REWARD = Text("Progress"), Text("Reward available")
local WIDTH, HEIGHT, GAP = 320, 20, 10
local min, max = math.min, math.max

local function HideTooltip(frame)
    if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
end

local function Tooltip(frame)
    if not M.name or NS.Host.InCombat() then return end
    GameTooltip:SetOwner(frame, "ANCHOR_TOP")
    GameTooltip:SetText(M.name)
    if M.standing then GameTooltip:AddLine(M.standing, 1, 1, 1) end
    if M.pending then
        GameTooltip:AddLine(REWARD)
    elseif M.maximum and not M.capped then
        GameTooltip:AddDoubleLine(PROGRESS,
            REPUTATION_PROGRESS_FORMAT:format(BreakUpLargeNumbers(M.current), BreakUpLargeNumbers(M.maximum)))
    end
    GameTooltip:Show()
end

local function Create(self)
    local bar = S.CreateFrame("StatusBar", nil, UIParent)
    bar:Hide()
    bar:SetSize(WIDTH, HEIGHT)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:SetStatusBarTexture(S.ResolveTexture("MSUF Lucent", NS.Host.MSUFMedia.barTexture))
    bar:SetMinMaxValues(0, 1)
    local background = S.CreateTexture(bar, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.06, .08, .10, .94)
    local name = S.CreateFontString(bar, nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", 7, 0)
    name:SetPoint("RIGHT", -57, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetMaxLines(1)
    name:SetText(TITLE)
    local percent = S.CreateFontString(bar, nil, "OVERLAY", "GameFontHighlightSmall")
    percent:SetPoint("RIGHT", -7, 0)
    percent:SetWidth(44)
    percent:SetJustifyH("RIGHT")
    bar:SetScript("OnEnter", Tooltip)
    bar:SetScript("OnLeave", HideTooltip)
    bar:SetScript("OnHide", HideTooltip)
    self.host, self.nameText, self.percentText = bar, name, percent
end

local function FrameBounds(frame, below, above)
    if not frame or NS.Host.Safety.IsForbidden(frame) or not frame:IsVisible() then return end
    local left, bottom, width, height = frame:GetRect()
    if not (Finite(left) and Finite(bottom) and Finite(width) and Finite(height) and height > 0) then return end
    local scale = frame:GetEffectiveScale()
    if not Finite(scale) or scale <= 0 then return end
    scale = scale / UIParent:GetEffectiveScale()
    return left * scale, (bottom - below) * scale, (left + width) * scale, (bottom + height + above) * scale
end

-- Native tracking containers may be moved independently. Use the visible XP
-- container's bounds, including its chrome, without changing Blizzard's frames.
local function NativeXPBounds()
    local manager, info = _G.StatusTrackingBarManager, _G.StatusTrackingBarInfo
    local containers = manager and manager.barContainers
    local index = info and info.BarsEnum and info.BarsEnum.Experience
    if not containers or not index then return end
    for _, container in ipairs(containers) do
        local xp = container.bars and container.bars[index]
        if xp and not NS.Host.Safety.IsForbidden(xp) and xp:IsVisible() then
            local alpha = xp:GetEffectiveAlpha()
            if Finite(alpha) and alpha > 0 then return FrameBounds(container, 4, 4) end
        end
    end
end

local function XPBounds()
    if S.ExperienceBarPlacement then
        local bar, below, above = S.ExperienceBarPlacement()
        local left, bottom, right, top = FrameBounds(bar, below, above)
        if left then return left, bottom, right, top end
    end
    return NativeXPBounds()
end

local function AutoPosition(width, screenWidth, screenHeight, defaultY)
    local left, bottom, right, top = XPBounds()
    if not left then return 0, defaultY, width end
    local x = (left + right) / 2
    if bottom - HEIGHT >= 2 * GAP then
        return x - screenWidth / 2, bottom - HEIGHT - GAP, width
    end
    if top + HEIGHT <= screenHeight - 2 * GAP then
        return x - screenWidth / 2, max(GAP, top + GAP), width
    end

    -- A tall centered XP layout can leave more space to one side.
    local leftRoom, rightRoom = left - 2 * GAP, screenWidth - right - 2 * GAP
    if max(leftRoom, rightRoom) >= 120 then
        width = min(width, max(leftRoom, rightRoom))
        x = leftRoom >= rightRoom and (left - GAP - width / 2) or (right + GAP + width / 2)
        return x - screenWidth / 2, (bottom + top - HEIGHT) / 2, width
    end
    return x - screenWidth / 2, bottom - HEIGHT - GAP, width
end

local function Layout(self)
    local screenWidth, screenHeight = UIParent:GetSize()
    local width = max(1, min(WIDTH, screenWidth - 2 * GAP))
    local x, y = self.config.x, self.config.y
    if not self.config.manualPosition then x, y, width = AutoPosition(width, screenWidth, screenHeight, y) end
    local xLimit = max(0, (screenWidth - width) / 2 - GAP)
    local host = self.host
    host:SetWidth(width)
    host:ClearAllPoints()
    host:SetPoint("BOTTOM", UIParent, "BOTTOM", max(-xLimit, min(xLimit, x)),
        max(GAP, min(screenHeight - HEIGHT - GAP, y)))
end

function S.SyncReputationBarPlacement()
    if M.active and M.host and not M.paused and not M.config.manualPosition then Layout(M) end
end

local function Read(id)
    local data = C_Reputation.GetFactionDataByID(id)
    if not (NS.Public(data) and type(data) == "table") then return end
    local name = NS.String(data.name)
    if not name then return end
    local kind, standing, current, maximum, capped, _, pending = S.ReadFactionReputation(data, nil, true)
    local reaction = Reaction(kind, kind == "standing" and Number(data.reaction))
    if current and maximum and maximum > 0 then
        return name, reaction, standing, max(0, min(maximum, current)), maximum, capped, pending
    end
    return name, reaction, standing
end

local function PaintColor(self)
    local r, g, b = unpack(self.palette[self.reaction or 0])
    if self.red == r and self.green == g and self.blue == b then return end
    self.host:SetStatusBarColor(r, g, b)
    self.red, self.green, self.blue = r, g, b
end

local function Paint(self)
    local id = self.config.factionID
    local name, reaction, standing, current, maximum, capped, pending
    if id > 0 then name, reaction, standing, current, maximum, capped, pending = Read(id) end
    local host = self.host
    local shown = id > 0 and (name ~= nil or S.editMode == true)
    if host:IsShown() ~= shown then host:SetShown(shown) end
    if self.name ~= name then self.nameText:SetText(name or TITLE) end
    if self.reaction ~= reaction or self.colorDirty then
        self.reaction = reaction
        self.colorDirty = nil
        PaintColor(self)
    end
    if self.current ~= current or self.maximum ~= maximum or self.capped ~= capped then
        local fraction = maximum and current / maximum or 0
        host:SetValue(fraction)
        self.percentText:SetText(maximum and ("%.0f%%"):format(fraction * 100) or "")
    end
    local changed = self.name ~= name or self.standing ~= standing or self.current ~= current
        or self.maximum ~= maximum or self.capped ~= capped or self.pending ~= pending
    self.name, self.standing = name, standing
    self.current, self.maximum, self.capped, self.pending = current, maximum, capped, pending
    if changed and GameTooltip:IsOwned(host) then Tooltip(host) end
end

local function Refresh(self)
    self.colorDirty = Header.UpdateReputationColors(self.palette, S.Config("characterPanel"), Header.PickerColor("accentBright"))
    Layout(self)
    Paint(self)
end

local function OnRenown(self, _, factionID)
    if not Finite(factionID) or factionID == self.config.factionID then Paint(self) end
end

local UPDATE_EVENTS = {
    PLAYER_ENTERING_WORLD = Refresh,
    DISPLAY_SIZE_CHANGED = Layout,
    UI_SCALE_CHANGED = Layout,
    UPDATE_FACTION = Paint,
    MAJOR_FACTION_UNLOCKED = OnRenown,
    MAJOR_FACTION_RENOWN_LEVEL_CHANGED = OnRenown,
}

local function Pause(self)
    if self.paused then return end
    self.paused = true
    for event in pairs(UPDATE_EVENTS) do self.context:RemoveEvent(event) end
    HideTooltip(self.host)
    self.host:EnableMouse(false)
end

local function Resume(self)
    self.paused = nil
    for event, callback in pairs(UPDATE_EVENTS) do self.context:Event(event, callback) end
    self.host:EnableMouse(true)
    Refresh(self)
end

function M:Enable()
    if not self.host then Create(self) end
    self.context:Event("PLAYER_REGEN_DISABLED", Pause, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_ENABLED", Resume, IN_COMBAT)
    self.paused = nil
    if NS.Host.InCombat() then Pause(self) else Resume(self) end
end

function M:Refresh()
    if not self.paused and not NS.Host.InCombat() then Refresh(self) end
end

function M:Disable()
    if self.host then self.host:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, ID, {
        label = "Reputation bar", order = 631, getFrame = function() return self.host end,
        visible = function() return self.config.factionID > 0 end,
        xKey = "x", yKey = "y", point = "BOTTOM",
        historyKeys = { "manualPosition" }, resetKeys = { "manualPosition" },
        moveValues = { manualPosition = true },
        capture = function(values)
            local center, bottom = self.host:GetCenter(), self.host:GetBottom()
            if Finite(center) and Finite(bottom) then values.x, values.y = center - UIParent:GetWidth() / 2, bottom end
        end,
    })
end

local function IsSelected(id)
    local config = S.Config(ID)
    return config.enabled and config.factionID == id
end

local function Toggle(id)
    if IsSelected(id) then return S.Set(ID, "enabled", false) end
    return S.SetMany(ID, { enabled = true, factionID = id })
end

local function Menu(_, root, id, name)
    root:CreateTitle(name)
    root:CreateCheckbox(Text("Show as reputation bar"), IsSelected, Toggle, id)
    NS.Reputation.AddWarOption(root, id)
end

function NS.OpenReputationMenu(button)
    if not NS.Host.InCombat() then S.ContextMenu(button, Menu, button.factionID, button.factionName) end
end

S.Install(ID, M)
