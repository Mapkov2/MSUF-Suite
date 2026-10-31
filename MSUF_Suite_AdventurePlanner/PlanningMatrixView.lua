local _, P = ...
local S, Plan = P.Suite, P.PlanningTools
local B, Matrix = Plan.Board, Plan.Matrix
local Bridge = P.NS.HostBridge
-- The comparison viewport scrolls by pixels: one band more than the visible
-- rows slides under the clip edge, so the pool stays ROWS + 1 bands.
Matrix.ROW_HEIGHT = 44
local LABEL_WIDTH, COLUMN_STEP, VIEW_TOP = 200, 118, -56

-- Each slot with its progress; an unlocked slot names its reward level.
local function VaultTip(activity, character)
    local fresh = character.week == "fresh"
    for _, row in ipairs(character.snapshot.vault or {}) do
        if row.kind == activity.rewardType then
            local progress = fresh and row.progress or 0
            GameTooltip:AddDoubleLine(S.Text("%s slot %d: %d / %d"):format(Plan.Weekly.KindLabel(row.kind), row.index,
                progress, row.threshold), progress >= row.threshold and Matrix.SlotLabel(row) or "", .8, .8, .8, .3, .9, .5)
        end
    end
end

-- This week's runs, highest first; timed runs are green.
local function RunsTip(character)
    if character.week ~= "fresh" then return end
    for i, run in ipairs(character.snapshot.runs or {}) do
        if i > 12 then break end
        local r, g, b = 1, 1, 1
        if run.completed then r, g, b = .3, .9, .5 end
        GameTooltip:AddDoubleLine(Matrix.MapName(run.map), "+" .. run.level, .8, .8, .8, r, g, b)
    end
end

-- Every boss of the saved instance; defeated ones are green.
local function LockoutTip(activity, character)
    local lockout = Matrix.FindLockout(character, activity.lockKey)
    if not lockout then return end
    for _, boss in ipairs(lockout.encounters or {}) do
        if boss.killed then GameTooltip:AddLine(boss.name, .3, .9, .5) else GameTooltip:AddLine(boss.name, .55, .55, .55) end
    end
    GameTooltip:AddLine(Plan.Date(lockout.expires), .8, .8, .8)
end

local function DungeonTip(activity, character)
    for _, best in ipairs(character.snapshot.dungeons or {}) do
        if best.id == activity.map and S.Finite(best.score) and best.score > 0 then
            GameTooltip:AddDoubleLine(S.Text("Mythic+ rating"), tostring(math.floor(best.score + .5)), .8, .8, .8, 1, 1, 1)
        end
    end
end

local function Details(activity, character)
    local kind, entry = activity.kind, character.snapshot
    if kind == "vault" then return VaultTip(activity, character) end
    if kind == "runs" then return RunsTip(character) end
    if kind == "lockout" then return LockoutTip(activity, character) end
    if kind == "dungeon" then return DungeonTip(activity, character) end
    if activity.field == "key" and entry.key and not entry.keyPending then GameTooltip:AddLine(entry.key.name, .8, .8, .8, true) end
    if activity.field == "seen" and entry.zone then GameTooltip:AddLine(entry.zone, .8, .8, .8, true) end
end

local function Tooltip(cell)
    if cell.window.foldActive or not B.Valid(cell.window) or not cell.activity or not cell.character then return end
    local activity, character = cell.activity, cell.character
    local text = Matrix.Value(activity, character, cell.window.now)
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:SetText(activity.label)
    GameTooltip:AddLine(character.label, 1, 1, 1)
    GameTooltip:AddLine(text, 1, 1, 1)
    Details(activity, character)
    if text == "?" then
        GameTooltip:AddLine(S.Text(character.snapshot.lockoutsPending and activity.kind == "lockout"
            and "Lockout data is waiting for the server." or "Old or unknown reset; log in to refresh."), 1, .8, .4, true)
    end
    GameTooltip:AddLine(S.Text("Last seen: %s"):format(Plan.Date(character.snapshot.at)), .7, .7, .7)
    Matrix.tooltipOwner = cell
    GameTooltip:Show()
end

function Matrix.HideTooltip()
    if Matrix.tooltipOwner and GameTooltip:IsOwned(Matrix.tooltipOwner) then GameTooltip:Hide() end
    Matrix.tooltipOwner = nil
end

-- Rows rest on the host surface with a hairline below each one, as Menu2
-- lists its rows; hover lifts the row under the cursor.
local function TintBand(band)
    B.Tint(band.fill, "pillHover", band.hover and .55 or 0, "pillBase")
end

local function Enter(cell)
    local band = cell:GetParent()
    band.hover = true
    if band.activity then TintBand(band) end
    Tooltip(cell)
end

local function Leave(cell)
    local band = cell:GetParent()
    band.hover = nil
    if band.activity then TintBand(band) end
    Matrix.HideTooltip()
end

local function ChooseCharacter(button)
    if button.window.foldActive or not B.Valid(button.window) or not button.character then return end
    button.window.selected = button.character.key
    button.window:Refresh()
end

local function Page(window, step)
    local view = window.matrix
    if not B.Valid(window) then return end
    view.characterOffset = math.max(0, view.characterOffset + step * Matrix.COLUMNS)
    window:Refresh()
end

local function CommitFold(window) window:Refresh() end
local function GatherMatrix(window, key)
    local view = window.matrix
    local start, last
    for i, row in ipairs(view.rows) do
        if start and row.kind == "section" then last = i - 1 break end
        if row.kind == "section" and row.key == key then start = i end
    end
    if not start then return end
    last = last or #view.rows
    Matrix.HideTooltip()
    for _, band in ipairs(view.bands) do
        if band:IsShown() and band.activity and band.index > start then
            local child = band.index <= last
            local distance = child and (band.index - start - 1) * Matrix.ROW_HEIGHT or (last - start) * Matrix.ROW_HEIGHT
            B.AddFoldRegion(window, band, distance, child)
        end
    end
end

-- A section folds like a Menu2 section header; the choice is saved.
local function ToggleSection(toggle)
    local window = toggle.window
    local band = toggle:GetParent()
    if not B.Valid(window) or not band.activity or not band.activity.key then return end
    window.matrix.scroller:Stop()
    local key = band.activity.key
    B.FinishAccordion(window, true)
    local folded = Matrix.Folded()
    folded[key] = not folded[key] or nil
    B.PlayAccordion(window, not folded[key], CommitFold, GatherMatrix, key)
end

local function SectionArt(band, window)
    band.arrow = S.CreateTexture(band, nil, "OVERLAY")
    band.arrow:SetSize(12, 12)
    band.arrow:SetPoint("LEFT", 4, 0)
    band.toggle = S.CreateFrame("Button", nil, band)
    band.toggle:SetAllPoints()
    band.toggle.window = window
    band.toggle:SetScript("OnClick", ToggleSection)
    band.toggle:SetScript("OnEnter", function(self) self:GetParent().hover = true TintBand(self:GetParent()) end)
    band.toggle:SetScript("OnLeave", function(self) self:GetParent().hover = nil TintBand(self:GetParent()) end)
end

local function Cell(band, window, col)
    local cell = S.CreateFrame("Button", nil, band)
    cell:SetPoint("LEFT", LABEL_WIDTH + (col - 1) * COLUMN_STEP, 0)
    cell:SetSize(COLUMN_STEP - 6, Matrix.ROW_HEIGHT - 1)
    cell.text = B.Label(cell, "", 11)
    cell.text:SetAllPoints()
    cell.text:SetJustifyH("CENTER")
    cell.text:SetJustifyV("MIDDLE")
    cell.text:SetWordWrap(true)
    cell.keyLevel = B.Label(cell, "", 12)
    cell.keyLevel:SetPoint("BOTTOMLEFT", 0, 1)
    cell.keyLevel:SetSize(COLUMN_STEP - 6, 14)
    cell.keyLevel:SetJustifyH("CENTER")
    cell.keyLevel:Hide()
    cell.window = window
    cell:SetScript("OnEnter", Enter)
    cell:SetScript("OnLeave", Leave)
    cell:SetScript("OnClick", ChooseCharacter)
    return cell
end

local function Band(view, window, row)
    local band = S.CreateFrame("Frame", nil, view.slider)
    band:SetPoint("TOPLEFT", 0, -(row - 1) * Matrix.ROW_HEIGHT)
    band:SetSize(view.viewWidth, Matrix.ROW_HEIGHT)
    band.fill = B.Fill(band, "pillHover", 0, "pillBase")
    local divider = B.Texture(band, "BORDER", "borderSoft", .55, "border")
    divider:SetPoint("BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", 0, 0)
    divider:SetHeight(1)
    band.index = row
    local label = B.Label(band, "", 13)
    label:SetPoint("LEFT", 22, 0)
    label:SetSize(LABEL_WIDTH - 30, Matrix.ROW_HEIGHT - 1)
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    band.difficulty = B.Label(band, "", 11, "muted")
    band.difficulty:SetPoint("TOPLEFT", 22, -23)
    band.difficulty:SetSize(LABEL_WIDTH - 30, 18)
    band.difficulty:SetWordWrap(false)
    band.title = B.Label(band, "", 14, "title")
    band.title:SetPoint("LEFT", 22, 0)
    band.title:SetSize(view.viewWidth - 30, Matrix.ROW_HEIGHT - 1)
    band.title:SetJustifyV("MIDDLE")
    band.title:SetWordWrap(false)
    view.rowLabels[row], view.bands[row], view.cells[row] = label, band, {}
    SectionArt(band, window)
    for col = 1, Matrix.COLUMNS do view.cells[row][col] = Cell(band, window, col) end
end

-- Characters are Menu2 pills, the realm sits under each in class colour.
local function Headers(view, window)
    view.counter = B.Label(view, "", 11, "muted")
    view.counter:SetPoint("TOPLEFT", 4, -10)
    view.counter:SetSize(118, 20)
    view.counter:SetJustifyV("MIDDLE")
    view.previous = B.Button(view, "<", 24, 24, function() Page(window, -1) end)
    view.previous:SetPoint("TOPLEFT", 126, -8)
    view.next = B.Button(view, ">", 24, 24, function() Page(window, 1) end)
    view.next:SetPoint("TOPLEFT", 154, -8)
    view.realms = {}
    for col = 1, Matrix.COLUMNS do
        local header = B.Button(view, "", COLUMN_STEP - 6, 24, ChooseCharacter)
        header:SetPoint("TOPLEFT", LABEL_WIDTH + (col - 1) * COLUMN_STEP, -8)
        header.text:SetJustifyH("CENTER")
        header.text:SetWordWrap(false)
        header.window = window
        view.headers[col] = header
        local realm = B.Label(view, "", 11, "muted")
        realm:SetPoint("TOPLEFT", LABEL_WIDTH + (col - 1) * COLUMN_STEP, -34)
        realm:SetSize(COLUMN_STEP - 6, 14)
        realm:SetJustifyH("CENTER")
        realm:SetWordWrap(false)
        view.realms[col] = realm
    end
end

function Matrix.Create(window)
    local view = S.CreateFrame("Frame", nil, window.body)
    view:SetPoint("TOPLEFT")
    view:SetSize(B.BODY_WIDTH, B.BODY_HEIGHT)
    window.matrix = view
    view.characterOffset, view.rowOffset = 0, 0
    view.headers, view.cells, view.rowLabels, view.bands = {}, {}, {}, {}
    view.viewWidth = LABEL_WIDTH + Matrix.COLUMNS * COLUMN_STEP
    view.empty = B.Label(view, "", 14, "muted")
    view.empty:SetPoint("CENTER")
    view.empty:SetSize(680, 80)
    view.empty:SetJustifyH("CENTER")
    view.empty:SetJustifyV("MIDDLE")
    view.empty:SetWordWrap(true)
    Headers(view, window)
    B.Rule(view, 0, VIEW_TOP + 2, view.viewWidth)
    view.hint = B.Label(view, "Green: done or timed. —: nothing yet. ?: log in to refresh. Shift + mouse wheel: more characters.", 11, "muted")
    view.hint:SetPoint("BOTTOMLEFT", 4, 6)
    view.hint:SetSize(B.BODY_WIDTH - 8, 16)
    view.hint:SetWordWrap(false)
    view.viewport = S.CreateFrame("Frame", nil, view)
    view.viewport:SetPoint("TOPLEFT", 0, VIEW_TOP)
    view.viewport:SetSize(view.viewWidth, Matrix.ROWS * Matrix.ROW_HEIGHT)
    view.viewport:SetClipsChildren(true)
    view.slider = S.CreateFrame("Frame", nil, view.viewport)
    view.slider:SetPoint("TOPLEFT")
    view.slider:SetSize(view.viewWidth, (Matrix.ROWS + 1) * Matrix.ROW_HEIGHT)
    for row = 1, Matrix.ROWS + 1 do Band(view, window, row) end
    Matrix.CreateScroll(window)
end

local function Scrolled(window, offset)
    if B.Valid(window) then Matrix.Place(window, offset) end
end

function Matrix.CreateScroll(window)
    local view = window.matrix
    view.scroller = B.Scroller(window, view, Scrolled, Matrix.ROW_HEIGHT * 3)
    view.scroller.bar:SetPoint("TOPRIGHT", 0, VIEW_TOP - 2)
    view.scroller.bar:SetHeight(Matrix.ROWS * Matrix.ROW_HEIGHT - 4)
    view:EnableMouseWheel(true)
    -- Shift and the wheel turn character pages; the wheel alone scrolls rows.
    view:SetScript("OnMouseWheel", function(_, delta)
        if not B.Valid(window) then return end
        B.FinishAccordion(window, true)
        if IsShiftKeyDown() then return Page(window, delta > 0 and -1 or 1) end
        view.scroller:Wheel(delta)
    end)
end

-- Folded section keys, saved account-wide.
function Matrix.Folded()
    local account = Plan.Account()
    return account and Plan.Table(account, "overviewFolded") or {}
end

local function Filter(view, query)
    if view.query == query then return end
    view.query = query
    local columns = {}
    for _, character in ipairs(view.model.columns) do
        if query == "" or character.label:lower():find(query, 1, true) then columns[#columns + 1] = character end
    end
    view.columns = #columns > 0 and columns or view.model.columns
    if query == "" or #columns > 0 then
        view.matched = view.model.rows
        return
    end
    local rows, section = {}
    for _, row in ipairs(view.model.rows) do
        if row.kind == "section" then
            section = row
        elseif row.label:lower():find(query, 1, true) then
            if section then rows[#rows + 1] = section section = nil end
            rows[#rows + 1] = row
        end
    end
    view.matched = rows
    if #rows == 0 then view.columns = {} end
end

-- A folded section keeps its header and hides its rows.
local function Fold(view)
    local folded, rows, skip = Matrix.Folded(), {}, false
    for _, row in ipairs(view.matched) do
        if row.kind == "section" then skip = folded[row.key] == true end
        if row.kind == "section" or not skip then rows[#rows + 1] = row end
    end
    view.rows = rows
end

local function SelectVisible(window)
    local view = window.matrix
    if #view.columns == 0 or #view.rows == 0 then
        window.selected = nil
        return
    end
    for col = 1, Matrix.COLUMNS do
        local character = view.columns[view.characterOffset + col]
        if character and character.key == window.selected then return end
    end
    window.selected = view.columns[view.characterOffset + 1].key
end

local function DrawHeaders(window)
    local view = window.matrix
    for col, header in ipairs(view.headers) do
        local character = view.columns[view.characterOffset + col]
        local realm = view.realms[col]
        header.character = character
        header:SetShown(character ~= nil)
        realm:SetShown(character ~= nil)
        if character then
            header.text:SetText(Plan.Overview.Name(character))
            realm:SetText(character.snapshot.realm or "")
            realm.plannerClassFile = character.snapshot.classFile
            B.TintLabel(realm, "muted")
            B.StyleButton(header, character.key == window.selected)
        end
    end
    local count = #view.columns
    view.counter:SetText(S.Text("%d–%d of %d"):format(count == 0 and 0 or view.characterOffset + 1,
        math.min(count, view.characterOffset + Matrix.COLUMNS), count))
    view.previous:SetEnabled(view.characterOffset > 0)
    view.next:SetEnabled(view.characterOffset + Matrix.COLUMNS < count)
    B.StyleButton(view.previous, false)
    B.StyleButton(view.next, false)
end

local function PaintCells(view, row, activity, now)
    for col, cell in ipairs(view.cells[row]) do
        local character = activity and view.columns[view.characterOffset + col]
        cell.activity, cell.character = activity, character
        cell:SetShown(character ~= nil and activity.kind ~= "section")
        if character then
            local text, tone = Matrix.Value(activity, character, now)
            local key = activity.field == "key" and character.week == "fresh" and not character.snapshot.keyPending and character.snapshot.key
            cell.keyLevel:SetShown(key ~= nil and key ~= false)
            cell.text:ClearAllPoints()
            if key then
                cell.text:SetPoint("TOPLEFT", 0, 0)
                cell.text:SetSize(COLUMN_STEP - 6, Matrix.ROW_HEIGHT - 16)
                cell.text:SetText(key.name)
                cell.keyLevel:SetText(S.Text("+%d"):format(key.level))
            else
                cell.text:SetAllPoints()
                cell.text:SetText(text)
            end
            B.TintLabel(cell.text, tone)
        end
    end
end

local function PaintSection(band, label, activity)
    local section = activity.kind == "section"
    band.arrow:SetShown(section)
    band.toggle:SetShown(section)
    band.title:SetShown(section)
    label:SetShown(not section)
    band.difficulty:SetShown(not section and activity.difficulty ~= nil)
    if not section then
        label:ClearAllPoints()
        label:SetPoint("LEFT", 22, activity.difficulty and 10 or 0)
        label:SetHeight(activity.difficulty and 20 or Matrix.ROW_HEIGHT - 1)
        label:SetText(activity.name or activity.label)
        band.difficulty:SetText(activity.difficulty or "")
        return
    end
    band.title:SetText(activity.label)
    local open = not Matrix.Folded()[activity.key]
    if not Bridge.MenuArrow(band.arrow, open) then
        band.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        band.arrow:SetRotation(open and math.pi * .5 or 0)
        local c = B.Color(open and "accent" or "accent2", "accent")
        band.arrow:SetVertexColor(c[1], c[2], c[3], .95)
    end
end

function Matrix.Paint(window)
    local view = window.matrix
    local available = #view.columns > 0 and #view.rows > 0
    view.empty:SetShown(not available)
    view.hint:SetShown(available)
    local searching = view.query and view.query ~= ""
    view.empty:SetText(searching and S.Text("No results")
        or S.Text("No saved entries") .. "\n\n" .. Plan.Overview.Hint("characters"))
    DrawHeaders(window)
    for row, band in ipairs(view.bands) do
        local index = view.rowOffset + row
        local activity = available and view.rows[index] or nil
        band.activity, band.index = activity, index
        band:SetShown(activity ~= nil)
        if activity then
            PaintSection(band, view.rowLabels[row], activity)
            TintBand(band)
        end
        PaintCells(view, row, activity, window.now)
    end
    -- A repaint under a resting cursor changes what the hovered cell shows.
    local hovered = Matrix.tooltipOwner
    if hovered then
        if hovered:IsShown() and hovered.activity and hovered.character then Tooltip(hovered) else Matrix.HideTooltip() end
    end
end

-- offset is in pixels. A new first row repaints the pool; a fraction only
-- slides it. The extra band shows while a fraction leaves room below.
function Matrix.Place(window, offset, force)
    local view = window.matrix
    local first = math.floor(offset / Matrix.ROW_HEIGHT)
    local fraction = offset - first * Matrix.ROW_HEIGHT
    view.slider:ClearAllPoints()
    view.slider:SetPoint("TOPLEFT", 0, fraction)
    if force or first ~= view.rowOffset then
        view.rowOffset = first
        Matrix.Paint(window)
    end
    local last = view.bands[#view.bands]
    last:SetShown(last.activity ~= nil and fraction > 0)
end

function Matrix.Draw(window, query)
    local view, reset = window.matrix, Plan.Weekly.Reset()
    if not view.model or view.generation ~= Plan.generation or view.reset ~= reset
        or view.model.nextExpiry and window.now >= view.model.nextExpiry then
        view.model = Matrix.Build(window.items, window.now)
        view.generation, view.reset, view.query = Plan.generation, reset, nil
    end
    Filter(view, query)
    Fold(view)
    view.characterOffset = math.min(view.characterOffset, math.max(0, math.floor((#view.columns - 1) / Matrix.COLUMNS) * Matrix.COLUMNS))
    SelectVisible(window)
    view.scroller:SetRange(#view.rows * Matrix.ROW_HEIGHT, Matrix.ROWS * Matrix.ROW_HEIGHT)
    Matrix.Place(window, view.scroller.offset, true)
    if view.model.truncated then window.status:SetText(S.Text("Too many results. Narrow your search.")) end
end

function Matrix.Clear(window)
    Matrix.HideTooltip()
    local view = window.matrix
    if not view then return end
    view.scroller:Stop()
    view.model, view.columns, view.rows, view.matched, view.query = nil, nil, nil, nil, nil
    for _, header in ipairs(view.headers) do header.character = nil end
    for row, cells in ipairs(view.cells) do
        view.bands[row].activity, view.bands[row].hover = nil, nil
        for _, cell in ipairs(cells) do cell.activity, cell.character = nil, nil end
    end
end
