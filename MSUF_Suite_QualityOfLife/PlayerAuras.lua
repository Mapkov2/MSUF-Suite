local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local cleanup
local saved, borders, hooked = {}, {}, {}
local unpack, floor = unpack, math.floor

-- Blizzard_BuffFrame (upstream/ptr and Forever): retain native buttons,
-- aura updates, cancel clicks, private anchors and duration timers.
-- Only public, configured geometry and artwork are changed here.
local function Remember(region)
    if not region or saved[region] then return end
    local state = { points = {}, width = region:GetWidth(), height = region:GetHeight(), scale = region:GetScale(), alpha = region:GetAlpha() }
    for index = 1, region:GetNumPoints() do state.points[index] = { region:GetPoint(index) } end
    if region:IsObjectType("Texture") then state.coords = { region:GetTexCoord() } end
    if region.GetFont then
        state.font = { region:GetFont() }
        state.color = { region:GetTextColor() }
        state.shadow = { region:GetShadowColor() }
        state.shadowOffset = { region:GetShadowOffset() }
    end
    saved[region] = state
end

local function Restore()
    for region, state in pairs(saved) do
        region:ClearAllPoints()
        for _, point in ipairs(state.points) do region:SetPoint(unpack(point)) end
        region:SetSize(state.width, state.height)
        region:SetScale(state.scale)
        region:SetAlpha(state.alpha)
        if state.coords then region:SetTexCoord(unpack(state.coords)) end
        if state.font then
            region:SetFont(unpack(state.font))
            region:SetTextColor(unpack(state.color))
            region:SetShadowColor(unpack(state.shadow))
            region:SetShadowOffset(unpack(state.shadowOffset))
        end
        saved[region] = nil
    end
    for _, border in pairs(borders) do border:Hide() end
end

local function Border(button, icon, c)
    local border = borders[button]
    if not border then
        border = S.CreateFrame("Frame", nil, button)
        border:EnableMouse(false)
        border.edges = {}
        for index = 1, 4 do border.edges[index] = S.CreateTexture(border, nil, "OVERLAY") end
        borders[button] = border
    end
    border:SetAllPoints(icon)
    border:SetFrameLevel(button:GetFrameLevel() + 1)
    local r, g, b = S.RGB(c.borderColor)
    S.PlaceEdges(border.edges, border, c.borderSize, r, g, b, 1)
    border:SetShown(c.borderSize > 0)
end

local function Font(region, button, point, c)
    if not (region and region.SetFont) then return end
    Remember(region)
    region:SetFont(S.ResolveFont(c.font) or NS.MSUFMedia.font, c.fontSize, "OUTLINE")
    region:SetTextColor(1, 1, 1, 1)
    region:SetShadowColor(0, 0, 0, 1)
    region:SetShadowOffset(1, -1)
    region:ClearAllPoints()
    region:SetPoint(point, button, point, point == "BOTTOMRIGHT" and -2 or 2, 1)
end

local function NativeBorder(region, c)
    if not region then return end
    Remember(region)
    region:SetSize(c.iconWidth + 2, c.iconHeight + 2)
end

local function Button(button, index, container, c)
    local icon = button.Icon
    if not icon then return end
    if NS.IsCombatLocked() and button:IsProtected() then
        S.Queue("playerAuras")
        return
    end
    Remember(button)
    Remember(icon)
    local col, row = (index - 1) % c.perRow, floor((index - 1) / c.perRow)
    button:SetScale(1)
    button:SetSize(c.iconWidth, c.iconHeight)
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", container, "TOPRIGHT", -col * (c.iconWidth + c.spacing),
        -row * (c.iconHeight + c.rowSpacing))
    -- Private aura artwork is registered with fixed native dimensions.
    -- Keep its native IconInfo; only place its public anchor in the row.
    if button.isAuraAnchor then return end
    icon:ClearAllPoints()
    icon:SetAllPoints(button)
    if icon.SetTexCoord then
        local x, y = .43, .43
        if c.iconWidth > c.iconHeight then
            y = y * c.iconHeight / c.iconWidth
        else
            x = x * c.iconWidth / c.iconHeight
        end
        icon:SetTexCoord(.5 - x, .5 + x, .5 - y, .5 + y)
        Border(button, icon, c)
    end
    NativeBorder(button.DebuffBorder, c)
    NativeBorder(button.TempEnchantBorder, c)
    Font(button.Count, button, "BOTTOMRIGHT", c)
    Font(button.Duration, button, "BOTTOMLEFT", c)
    if button.Duration and button.Duration.SetFont then button.Duration:SetAlpha(c.showDuration and 1 or 0) end
end

local function Paint(frame, offset)
    local c = M.config
    if not (frame and frame.AuraContainer and frame.auraFrames) then return end
    if NS.IsCombatLocked() and frame:IsProtected() then
        S.Queue("playerAuras")
        return
    end
    local container = frame.AuraContainer
    Remember(frame)
    Remember(container)
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", c.x, c.y - offset)
    container:ClearAllPoints()
    container:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    local index = 0
    local collect = frame.ConsolidatedBuffs
    local collectShown = collect and collect:IsShown()
    if S.Public(collectShown) and collectShown then
        index = index + 1
        Button(collect, index, container, c)
    end
    for _, button in ipairs(frame.auraFrames) do
        local shown = button:IsShown()
        if S.Public(shown) and shown then
            index = index + 1
            Button(button, index, container, c)
        end
    end
    container:SetSize(c.perRow * (c.iconWidth + c.spacing) - c.spacing,
        math.max(1, math.ceil(index / c.perRow)) * (c.iconHeight + c.rowSpacing) - c.rowSpacing)
end

local function Apply()
    if not M.active then return end
    Paint(_G.BuffFrame, 0)
    Paint(_G.DebuffFrame, M.config.debuffOffset)
end

local function Adopt()
    for _, frame in ipairs({ _G.BuffFrame, _G.DebuffFrame }) do
        if frame and not hooked[frame] and frame.UpdateGridLayout then
            hooked[frame] = true
            hooksecurefunc(frame, "UpdateGridLayout", Apply)
            if frame.UpdateAuraButtons then hooksecurefunc(frame, "UpdateAuraButtons", Apply) end
        end
    end
    Apply()
end

local function FinishCleanup()
    if NS.IsCombatLocked() then return end
    if cleanup then cleanup:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    Restore()
    for frame in pairs(hooked) do frame:UpdateGridLayout() end
end

function M:Enable()
    if cleanup then cleanup:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    self.active = true
    self.context:Event("PLAYER_ENTERING_WORLD", Adopt)
    self.context:Event("PLAYER_REGEN_ENABLED", Adopt)
    self.context:Event("ADDON_LOADED", Adopt)
    Adopt()
end

function M:Refresh()
    Adopt()
end

function M:Disable()
    self.active = false
    if NS.IsCombatLocked() then
        if not cleanup then
            cleanup = S.CreateFrame("Frame")
            cleanup:SetScript("OnEvent", FinishCleanup)
        end
        cleanup:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        FinishCleanup()
    end
end

S.Install("playerAuras", M)
