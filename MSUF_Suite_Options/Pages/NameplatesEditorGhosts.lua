local _, P = ...
local Elements, Layers = P.NameplatesElements, P.NameplatesEditorLayers
local Ghosts = {}
P.NameplatesEditorGhosts = Ghosts

local CONDITION = { cast = true, castText = true, castTime = true, castIcon = true, castTarget = true,
    castShield = true, raidIcon = true, classification = true, eliteMarker = true, questMarker = true,
    target = true, focusMarker = true }

local function Inactive(ui, handle, def, cell)
    if not def or not CONDITION[def.key] or handle:IsVisible() or not ui:LayerOn(def.key)
        or not Elements.Applies(ui, def) or Layers.Blocked(ui, def.key) then return false end
    local _, on = Elements.Presence(ui, def)
    if on == false or (def.group == "cast" and (not cell.previewCastAllowed or not ui:LayerOn("cast"))) then return false end
    -- Cast details can be disabled by the native defaults even when the
    -- profile delegates to Blizzard. Only show the regular cast geometry
    -- as a ghost for this sample; detail ghosts follow their own switches.
    if def.group == "cast" and def.key ~= "castShield" and def.key ~= "cast"
        and ui.castingSample ~= false then return false end
    if def.group == "cast" and def.presence and def.key ~= "cast" and on == nil then return false end
    return not ui:LayerActive(def.key) and handle:GetNumPoints() > 0
end

local function AddSegment(ghost, number, x, y, width, height)
    local dash = ghost.dashes[number]
    if not dash then
        dash = ghost:CreateTexture(nil, "OVERLAY")
        dash:SetColorTexture(.68, .76, .84, .75)
        ghost.dashes[number] = dash
    end
    dash:ClearAllPoints()
    dash:SetPoint("TOPLEFT", ghost, "TOPLEFT", x, -y)
    dash:SetSize(width, height)
    dash:Show()
end

local function Draw(ghost, width, height)
    if ghost.drawWidth == width and ghost.drawHeight == height then return end
    ghost.drawWidth, ghost.drawHeight = width, height
    local index = 0
    for x = 0, width - 1, 9 do
        local size = math.min(5, width - x)
        AddSegment(ghost, index + 1, x, 0, size, 1)
        AddSegment(ghost, index + 2, x, height - 1, size, 1)
        index = index + 2
    end
    for y = 3, height - 3, 9 do
        local size = math.min(5, height - y - 1)
        AddSegment(ghost, index + 1, 0, y, 1, size)
        AddSegment(ghost, index + 2, width - 1, y, 1, size)
        index = index + 2
    end
    for extra = index + 1, #ghost.dashes do ghost.dashes[extra]:Hide() end
end

local function Create(ui, handle, cell, def)
    -- A separate button remains visible when the real sample frame is hidden.
    -- Its anchor still follows the same settings and the stage's zoom/pan.
    local ghost = CreateFrame("Button", nil, cell)
    if not handle.previewGhostWidth then ghost:SetAllPoints(handle) end
    ghost:SetFrameLevel(cell:GetFrameLevel() + 1)
    ghost.dashes = {}
    ghost:SetScript("OnClick", function() Elements.Inspect(ui, def, true) end)
    if P.M.AddTooltip then P.M.AddTooltip(ghost, Elements.Label(def, handle), "Not shown in this sample.", { hook = true }) end
    return ghost
end

function Ghosts.Refresh(ui)
    if not ui.sampleCells then return end
    local cell = ui.sampleCells[ui.sampleKind]
    local show = cell and cell:IsVisible() and not ui.compact and not ui.groupPreviewEnabled and ui.showInactive ~= false
        and ui:CanPickElement()
    for _, handle in ipairs(ui.handles) do
        local ghost = handle.previewGhost
        local def = Elements.ForHandle(handle)
        local width, height = handle.previewGhostWidth or handle:GetWidth(), handle:GetHeight()
        if show and handle._key:match("^(%a+)%.") == ui.sampleKind and width > 1 and height > 1
            and Inactive(ui, handle, def, cell) then
            if not ghost then
                ghost = Create(ui, handle, cell, def)
                handle.previewGhost = ghost
            end
            if handle.previewGhostWidth then
                ghost:ClearAllPoints()
                ghost:SetPoint(handle:GetPoint())
                ghost:SetSize(width, height)
            end
            Draw(ghost, width, height)
            ghost:Show()
        elseif ghost then
            ghost:Hide()
        end
    end
end
