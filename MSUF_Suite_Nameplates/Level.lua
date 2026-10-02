local _, private = ...
local NS, S = private.NS, private.Suite
local LOOK_BLIZZARD, LEVEL_BADGE = private.Mode.LOOK_BLIZZARD, private.Mode.LEVEL_BADGE
local Key = private.Key
local LevelBadgeShown = private.Geometry.LevelBadgeShown
-- The level number the Suite draws beside the health bar, and the alpha it
-- applies to Blizzard's own level frames while that number replaces them.
local Level = {}
private.Level = Level
local M

function Level.Bind(module) M = module end

local function Safe(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

function Level.Hide(uf)
    local label = M.levelLabels[uf]
    if Safe(label) then label:Hide() end
end

local function NativeAlpha(frame, hide)
    if not Safe(frame) then return end
    local previous = M.nativeLevelAlphas[frame]
    if hide then
        if previous ~= nil and frame:GetAlpha() == 0 then return end
        if previous == nil then
            previous = frame:GetAlpha()
            if not S.Finite(previous) then return end
            M.nativeLevelAlphas[frame] = previous
        end
        if NS.IsCombatLocked() then
            M.needsRefresh = true
            return
        end
        frame:SetAlpha(0)
    elseif previous ~= nil then
        if NS.IsCombatLocked() then
            M.needsRefresh = true
            return
        end
        frame:SetAlpha(previous)
        M.nativeLevelAlphas[frame] = nil
    end
end

function Level.PaintNative(uf, prefix)
    if not NS.Client.isForever then return end
    local hide = prefix and M.config.look ~= LOOK_BLIZZARD and M.config[prefix]
        and (M.config[Key[prefix].LevelEnabled] == false or M.config.levelAppearance ~= LEVEL_BADGE)
    NativeAlpha(uf.PlayerLevelDiffFrame, hide)
    -- Camelot already draws its own badge in Classic style. Keep its legacy
    -- LevelFrame out of the Suite look so the level is never duplicated.
    NativeAlpha(uf.LevelFrame, hide or prefix and M.config.look ~= LOOK_BLIZZARD and M.config[prefix])
end

function Level.RestoreNative()
    if not next(M.nativeLevelAlphas) then return end
    if NS.IsCombatLocked() then
        if not M.nativeLevelRestoreFrame then
            local frame = CreateFrame("Frame")
            frame:SetScript("OnEvent", function(self)
                if NS.IsCombatLocked() then return end
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if not M.active then Level.RestoreNative() end
            end)
            M.nativeLevelRestoreFrame = frame
        end
        M.nativeLevelRestoreFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    for frame, alpha in pairs(M.nativeLevelAlphas) do
        if Safe(frame) then frame:SetAlpha(alpha) end
        M.nativeLevelAlphas[frame] = nil
    end
end

-- Whether the plate shows Blizzard's level instead of the Suite number.
local function NativeShown(uf, prefix, unit)
    local setup = NamePlateSetupOptions
    local classic = S.Public(setup.useClassicHealthBar) and setup.useClassicHealthBar == true
    local namesOnly = S.Public(uf.showOnlyName) and uf.showOnlyName == true
    if not prefix or M.config.look == LOOK_BLIZZARD or not M.config[prefix]
        or not M.config[Key[prefix].LevelEnabled] or not unit then return true end
    if NS.Client.isForever then return M.config.levelAppearance == LEVEL_BADGE or namesOnly end
    -- Retail's own badge appears only for some players; it keeps its place.
    return classic or LevelBadgeShown(uf, unit) ~= false
end

local function Label(uf)
    local label = M.levelLabels[uf]
    if label then return label end
    if NS.IsCombatLocked() or not Safe(uf) then
        M.needsRefresh = true
        return
    end
    local container = uf.HealthBarsContainer
    if not Safe(container) then return end
    label = uf:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlateLevel")
    label:SetPoint("RIGHT", container, "LEFT", -4, 0)
    label:SetWidth(24)
    label:SetJustifyH("RIGHT")
    label:SetTextColor(1, 1, 1)
    M.levelLabels[uf] = label
    return label
end

function Level.Paint(uf, prefix, unit)
    if NativeShown(uf, prefix, unit) then
        Level.Hide(uf)
        return
    end
    local label = Label(uf)
    if not label then return end
    if not Safe(label) then
        M.needsRefresh = true
        return
    end
    local customHeight = M.config[Key[prefix].LevelSize]
    local height = S.Finite(customHeight) and customHeight > 0 and customHeight
        or NamePlateSetupOptions.levelFontHeight or 10
    if S.Finite(height) and label._suiteLevelHeight ~= height then
        label:SetTextHeight(height)
        local width = math.max(24, height * 2)
        label:SetWidth(width)
        label._suiteLevelWidth = width
        label._suiteLevelHeight = height
    end
    local value
    if NS.Client.isForever then value = UnitEffectiveLevel(unit) else value = UnitLevel(unit) end
    if S.Public(value) and type(value) == "number" and value <= 0 then value = "??" end
    -- SetText accepts secret text in the engine; never compare or format a
    -- secret level in addon Lua.
    label:SetText(value)
    label:Show()
end
