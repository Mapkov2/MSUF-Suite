local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Native aura slots own the match and its protected visibility.
local Display = {}
C.TotemCoverageDisplay = Display

local MAX_UNITS, COLUMNS = 40, 4
local CELL_WIDTH, CELL_HEIGHT, GUTTER, HEADER_HEIGHT = 83, 20, 10, 46
local SLOT, FILTER = "coverage", "HELPFUL|PLAYER"
local views = {}
local shownIcon, shownView

-- The roster and effect IDs come from the CDM's public totem data. Blizzard
-- owns the aura match and button visibility. This panel never reads them.
local function NewView()
    local frame = S.CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:SetBackdrop({
        bgFile = C.Const.WHITE,
        edgeFile = C.Const.WHITE,
        edgeSize = 1,
    })
    frame:SetBackdropColor(.045, .052, .068, .98)
    frame:SetBackdropBorderColor(.29, .34, .41, 1)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", GUTTER, -9)
    title:SetPoint("RIGHT", frame, "RIGHT", -GUTTER, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    hint:SetWordWrap(false)
    hint:SetTextColor(.72, .77, .83)
    hint:SetText(S.Text("Highlighted players have your totem buff."))
    return { frame = frame, title = title, hint = hint, cells = {}, count = 0 }
end

local function NewCell(parent, spellIDs)
    local frame = S.CreateFrame("Frame", nil, parent)
    frame:SetSize(CELL_WIDTH - 3, CELL_HEIGHT - 3)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(.13, .15, .19, 1)

    local marker = frame:CreateTexture(nil, "ARTWORK")
    marker:SetSize(7, 7)
    marker:SetPoint("LEFT", frame, "LEFT", 5, 0)
    marker:SetColorTexture(.32, .36, .42, 1)

    local name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", marker, "RIGHT", 5, 0)
    name:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)

    local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    if container.SetEditModePreviewEnabled then container:SetEditModePreviewEnabled(false) end
    container:SetAllPoints(frame)
    container:AddAuraSlot(SLOT, FILTER, {
        candidateFilters = { includeSpellIDs = spellIDs },
        initializeFrame = function(button)
            button:SetSize(7, 7)
            button:SetPoint("LEFT", frame, "LEFT", 5, 0)
            button:SetMouseClickEnabled(false)
            button:SetMouseMotionEnabled(false)
            local active = button:CreateTexture(nil, "OVERLAY")
            active:SetAllPoints(button)
            active:SetColorTexture(.35, .86, .53, 1)
        end,
    })
    return { frame = frame, container = container, name = name }
end

local function RosterMatches(view, units)
    if not view or view.count ~= #units then return false end
    for i = 1, #units do
        if view.cells[i].unit ~= units[i] then return false end
    end
    return true
end

function Display.Hide(icon)
    if not shownView or (icon and icon ~= shownIcon) then return end
    shownView.frame:Hide()
    shownIcon, shownView = nil, nil
end

Display.Retire = Display.Hide

-- Each supported effect family has a stable ID set. Reuse its native slots
-- across CDM bars and only change their unit bindings outside combat.
function Display.Prepare(_, _, spellIDs, units)
    if not spellIDs or not units or #units == 0 or #units > MAX_UNITS then return false end
    local view = views[spellIDs]
    if RosterMatches(view, units) then return true end
    if NS.InCombat() or NS.Client.AuraBuildBlocked() or not C.AuraButtons.Quiet() then return false end
    if not view then
        view = NewView()
        views[spellIDs] = view
    end
    if shownView == view then Display.Hide() end

    local columns = math.min(COLUMNS, #units)
    for i = 1, #units do
        local cell = view.cells[i]
        if not cell then
            cell = NewCell(view.frame, spellIDs)
            view.cells[i] = cell
        end
        local unit = units[i]
        if cell.unit ~= unit then
            cell.container:SetUnit(unit)
            cell.unit = unit
        end
        cell.frame:ClearAllPoints()
        cell.frame:SetPoint("TOPLEFT", view.frame, "TOPLEFT",
            GUTTER + ((i - 1) % columns) * CELL_WIDTH,
            -HEADER_HEIGHT - math.floor((i - 1) / columns) * CELL_HEIGHT)
        cell.frame:Show()
    end
    for i = #units + 1, view.count do view.cells[i].frame:Hide() end
    local width = math.max(310, GUTTER * 2 + columns * CELL_WIDTH)
    view.hint:SetWidth(width - GUTTER * 2)
    view.frame:SetSize(width, HEADER_HEIGHT + math.ceil(#units / columns) * CELL_HEIGHT + GUTTER)
    view.count = #units
    return true
end

function Display.Show(icon, label, spellIDs, units, haveTotem)
    label = S.PublicText(label)
    if not icon or not label or not Display.Prepare(icon, label, spellIDs, units) then
        Display.Hide(icon)
        return false
    end
    local view = views[spellIDs]
    if shownView == view and shownIcon == icon then return true end
    Display.Hide()
    local frame = view.frame
    -- Match the visible totem icon when the slot itself is secret.
    if S.Public(haveTotem) then frame:SetAlpha(1) else frame:SetAlphaFromBoolean(haveTotem, 1, 0) end
    -- Only our outer Frame is repositioned. All AuraContainer configuration
    -- was set in Prepare and is untouched while protected.
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOM", icon, "TOP", 0, 7)
    view.title:SetText(label)
    for i = 1, view.count do
        local unit = units[i]
        local name = S.PublicText(UnitName(unit))
        view.cells[i].name:SetText(name or "")
    end
    shownIcon, shownView = icon, view
    frame:Show()
    return true
end
