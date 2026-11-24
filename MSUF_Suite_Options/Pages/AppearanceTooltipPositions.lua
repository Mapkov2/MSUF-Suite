local _, P = ...

local View, Positions = {}, P.Suite.TooltipPositions
P.TooltipPositionPreview = View
local Kit, Tr = P.SkinPageKit, P.Tr
local PAGE, ID, SECTION = "suite_tooltips", "tooltipDetails", "suite_skin_tooltip_source_positions"
P.TooltipSourcesSection = SECTION
local UNIT_SECTION = "suite_skin_unit_tooltips"

local function OpenExact(preview, section, setting)
    preview.ui:Focus(section)
    return P.Suite.HostBridge.OpenExactMenuSetting(P.M, PAGE, section, "msufsuite." .. setting)
end

local function OpenModule(preview, id, key)
    local feature = P.QoLView.FindFeature(id)
    if not feature then return false end
    preview.ui.select("details")
    if not P.Get(id, "enabled") then key = "enabled" end
    return OpenExact(preview, P.QoLView.FeatureSectionId(feature), id .. "." .. key)
end

function View.Open(preview, spec, sample, blockedSection)
    local part, field = spec[1], spec[3]
    if part == "anchor" then
        if not P.Get(ID, "enabled") then return OpenModule(preview, ID, "enabled") end
        local source = Positions.byID[preview.positionSource]
        return OpenExact(preview, source and SECTION or P.TooltipLayoutSection, ID .. "." .. (source and source.mode or "anchor"))
    end
    if part == "scale" then
        if not P.Get("tooltipVisibility", "enabled") then return OpenModule(preview, "tooltipVisibility", "enabled") end
        return OpenExact(preview, P.TooltipLayoutSection, "tooltipVisibility.scale")
    end
    if part == "detailRow" then return OpenModule(preview, ID, field) end
    if part == "data" then
        if sample == "loot" then blockedSection = P.TooltipTypesSection
        elseif sample ~= "item" then return OpenModule(preview, ID, "enabled") end
    end
    if field == "unitHealthTextFormat" and P.OpenTooltipHealthTextMenu(preview) then return true end
    if field and (field:match("^unitHealth") or field:match("^unitPower")) then
        return OpenExact(preview, UNIT_SECTION, "skin.theme.tooltipLayout." .. field)
    end
    if blockedSection == P.TooltipTypesSection then
        return OpenExact(preview, blockedSection, "skin.theme.tooltipLayout." .. sample .. "Style")
    end
    return OpenExact(preview, P.TooltipFieldSection(field), "skin.theme.tooltipLayout." .. field)
end

function View.BuildDetailHandles(preview, open)
    preview.detailHandles = {}
    for i = 4, #preview.rows do
        local row = preview.rows[i]
        local handle = CreateFrame("Button", nil, preview.body)
        handle:SetPoint("TOPLEFT", row[1], "TOPLEFT")
        handle:SetPoint("TOPRIGHT", row[2], "TOPRIGHT")
        handle:SetHeight(19)
        handle:SetFrameLevel(preview.stage:GetFrameLevel() + 36)
        handle.spec = { "detailRow", "Details" }
        handle.open = function() return open(preview, handle.spec) end
        handle:Hide()
        preview.detailHandles[i] = handle
        preview.kit:Add("detailRow" .. i, handle)
        P.HM.SkipHistoryCheckpoint(handle)
    end
end

function View.PaintDetailHandles(preview, visible)
    for i = 4, #preview.rows do
        local handle, key = preview.detailHandles[i], preview.rowSettings[i]
        local rule = key and P.catalog[ID].rules[key]
        if rule then handle.spec[2], handle.spec[3] = rule.label, key end
        handle:SetShown(visible and rule ~= nil)
    end
end

local anchorPrefixes = { [2] = "cursor", [3] = "fixed" }
local corners = {
    { "BOTTOMRIGHT", -1, 1 }, { "BOTTOMLEFT", 1, 1 },
    { "TOPRIGHT", -1, -1 }, { "TOPLEFT", 1, -1 },
}

function P.BuildTooltipSourcePositions(ctx, builder, ui)
    if not P.Available(ID) then return end
    local defaults, rows = {}, {}
    local rules = P.catalog[ID].rules
    for _, source in ipairs(Positions.sources) do
        for _, key in ipairs({ source.mode, source.x, source.y, source.direction, source.side }) do
            defaults[key] = rules[key].default
        end
        local rule = rules[source.mode]
        local row = P.RuleRow(PAGE, ID, rule, nil, SECTION)
        row.pageKey, row.suiteModuleId, row.searchLabel = PAGE, ID, rule.label
        row.unavailable = function()
            local enabled, reason = P.RuleEnabled(ID, rule, nil, true)
            if not enabled then return reason end
        end
        local set = row.set
        row.set = function(value)
            set(value)
            local preview = ui and ui.tooltipPreview
            if preview then View.SelectSource(preview, source.id) end
        end
        rows[#rows + 1] = row
    end
    Kit.Section(ctx, builder, "tooltip_source_positions", "Position by source", nil, rows, false, nil, nil, nil,
        function() return P.S.ResetKeys(ID, defaults) end)
end

function View.Mode(preview)
    local global = P.TooltipAnchorMode()
    if not P.Available(ID) or not P.Get(ID, "enabled") then return end
    local source = Positions.byID[preview.positionSource]
    local mode = source and P.Get(ID, source.mode)
    if not mode or mode <= 1 then return global end
    if mode > 2 then return mode - 1, source end
end

function View.Keys(preview)
    local source = preview.anchorSource
    if source then return source.x, source.y end
    local prefix = anchorPrefixes[preview.anchorMode]
    if prefix then return prefix .. "X", prefix .. "Y" end
end

function View.Read(preview)
    local x, y = View.Keys(preview)
    if x then return P.Get(ID, x), P.Get(ID, y) end
    return 0, 0
end

function View.IsAnchor(preview, handle)
    return handle ~= nil and (handle == preview.anchorButton or handle == preview.anchorSurface)
end

function View.CanMove(preview)
    return preview.anchorMode ~= nil and (preview.positionSource == "default" or preview.anchorSource ~= nil)
end

function View.Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, math.floor(value + .5)))
end
local Clamp = View.Clamp

function View.Write(preview, x, y)
    local mode, source = View.Mode(preview)
    if P.Combat() or not preview.root:IsVisible() or not View.CanMove(preview)
        or preview.anchorMode ~= mode or preview.anchorSource ~= source
        or not (P.Suite.Finite(x) and P.Suite.Finite(y)) then return false end
    local xKey, yKey = View.Keys(preview)
    if not xKey then return false end
    local rules = P.catalog[ID].rules
    return P.SetMany(ID, { [xKey] = Clamp(x, rules[xKey].min, rules[xKey].max),
        [yKey] = Clamp(y, rules[yKey].min, rules[yKey].max) })
end

local function Projection(preview)
    local x, y = View.Keys(preview)
    local rules = P.catalog[ID].rules
    local source = preview.anchorSource
    local corner = preview.anchorMode == 3 and (corners[P.Get(ID, source and source.direction or "growth")] or corners[1])
    local padding = preview.anchorMode == 4 and 44 or 24
    local scale = preview.displayScale or 1
    local roomX = math.max(1, preview.stage:GetWidth() - preview.frame:GetWidth() * scale - padding)
    local roomY = math.max(1, preview.stage:GetHeight() - (preview.frame:GetHeight() + (preview.footerHeight or 0)) * scale - padding)
    local divisor = corner and 1 or 2
    return roomX / (rules[x].max * divisor), roomY / (rules[y].max * divisor), corner
end

local function ParentSide(preview)
    return Positions.sides[P.Get(ID, preview.anchorSource.side)] or Positions.sides[1]
end

function View.Place(preview, x, y)
    local frame, marker = preview.frame, preview.positionReference
    frame:ClearAllPoints()
    local scale = preview.displayScale or 1
    local footer = (preview.footerHeight or 0) * scale
    marker:SetShown(preview.anchorMode == 4)
    if not preview.anchorMode then
        frame:SetPoint("CENTER", preview.stage, "CENTER", 0, footer / (2 * scale))
        return
    end
    local sx, sy, corner = Projection(preview)
    if x == nil then x, y = View.Read(preview) end
    if corner then
        frame:SetPoint(corner[1], preview.stage, corner[1], corner[2] * (12 + math.abs(x) * sx) / scale,
            (corner[3] * (12 + math.abs(y) * sy) + (corner[3] == 1 and footer or 0)) / scale)
    elseif preview.anchorMode == 4 then
        local side = ParentSide(preview)
        marker:ClearAllPoints()
        marker:SetPoint(side[1], preview.stage, side[1], side[1] == "LEFT" and 20 or side[1] == "RIGHT" and -20 or 0,
            side[1] == "BOTTOM" and 20 + footer or side[1] == "TOP" and -20 or footer / 2)
        local dx, dy = side[1] == "RIGHT" and -x or x, side[1] == "TOP" and -y or y
        frame:SetPoint(side[1], marker, side[2], dx * sx / scale, dy * sy / scale)
    else
        frame:SetPoint("CENTER", preview.stage, "CENTER", x * sx / scale, (y * sy + footer / 2) / scale)
    end
end

function View.Scale(preview, stored)
    if not P.Available("tooltipVisibility") or not P.Get("tooltipVisibility", "enabled") then return 100 end
    return not stored and preview.scaleDraft or P.Get("tooltipVisibility", "scale")
end

function View.ClampScale(value)
    local rule = P.catalog.tooltipVisibility.rules.scale
    return Clamp(value, rule.min, rule.max)
end

function View.WriteScale(preview, value)
    if P.Combat() or not preview.root:IsVisible() or not P.Available("tooltipVisibility")
        or not P.Get("tooltipVisibility", "enabled") or not P.Suite.Finite(value) then return false end
    return P.Set("tooltipVisibility", "scale", View.ClampScale(value))
end

function View.Drag(preview, dx, dy)
    local x, y = View.Read(preview)
    local sx, sy, corner = Projection(preview)
    local xKey, yKey = View.Keys(preview)
    local rules = P.catalog[ID].rules
    if corner then
        local signX, signY = x == 0 and corner[2] or (x < 0 and -1 or 1), y == 0 and corner[3] or (y < 0 and -1 or 1)
        x = signX * Clamp(math.abs(x) + dx * corner[2] / sx, 0, rules[xKey].max)
        y = signY * Clamp(math.abs(y) + dy * corner[3] / sy, 0, rules[yKey].max)
    else
        if preview.anchorMode == 4 then
            local side = ParentSide(preview)
            if side[1] == "RIGHT" then dx = -dx end
            if side[1] == "TOP" then dy = -dy end
        end
        x = Clamp(x + dx / sx, rules[xKey].min, rules[xKey].max)
        y = Clamp(y + dy / sy, rules[yKey].min, rules[yKey].max)
    end
    return x, y
end

local function TrackInput(preview, input)
    if not input then return end
    input:HookScript("OnEditFocusGained", function()
        preview.axisProfile, preview.axisDatabase = P.ProfileGuard(), preview.skin.DB
        preview.axisMode = preview.anchorMode
    end)
    input:HookScript("OnHide", function() preview.axisProfile, preview.axisDatabase, preview.axisMode = nil, nil, nil end)
end

function View.BuildSelection(preview, movable, read, write, barPrefix, sizeField)
    local M = P.M
    if not M.PreviewSelectionBar then return end
    local selection = M.PreviewSelectionBar.Create(preview.stage, {
        Tr = Tr, Theme = function() return P.T end,
        HandleList = function() return preview.kit.list end,
        HandleLabel = function(handle)
            local size = sizeField(handle)
            return size == "height" and "Header height" or size == "iconSize" and "Icon size" or handle.spec[2]
        end,
        IsPlaced = function(handle) return movable(preview, handle) end,
        ReadOffsets = function(_, handle) return read(preview, handle) end,
        WriteOffsets = function(_, handle, x, y, reason)
            if reason == "PREVIEW_EXACT_OFFSET" and not (preview.axisProfile and preview.axisProfile()
                and preview.axisDatabase == preview.skin.DB
                and (not View.IsAnchor(preview, handle) or preview.axisMode == View.Mode(preview))) then return false end
            if movable(preview, handle) then return write(preview, x, y, handle) end
        end,
        NudgeDelta = function(_, dx, dy) return preview.kit:Nudge(dx, dy) end,
        ResetOffsets = function(_, handle)
            if not movable(preview, handle) then return false end
            if View.IsAnchor(preview, handle) then
                local x, y = View.Keys(preview)
                local rules = P.catalog[ID].rules
                return View.Write(preview, rules[x].default, rules[y].default)
            end
            if handle == preview.scaleButton then return write(preview, 100, 0, handle) end
            if handle.resize then
                local defaults = preview.skin.Defaults.theme.tooltipLayout
                local prefix = barPrefix(handle)
                return write(preview, defaults[prefix .. "Width"], defaults[prefix .. "Height"], handle)
            end
            local size = sizeField(handle)
            if size then return write(preview, preview.skin.Defaults.theme.tooltipLayout[size], 0, handle) end
            if barPrefix(handle) then return write(preview, 0, 0, handle) end
            return write(preview, 10, 0)
        end,
        OpenSettings = function(_, handle) return (handle.openSize or handle.open)() end,
        SelectHandle = function(_, handle) preview.kit:Select(handle) return true end,
    })
    preview.selection = selection
    selection:Hide()
    TrackInput(preview, selection.axisX.edit)
    TrackInput(preview, selection.axisY.edit)
end

