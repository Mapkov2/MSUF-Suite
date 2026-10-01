local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Addon-owned stand-ins on aura bar cells: the sample rows the options
-- page and MSUF Edit Mode draw, and the dimmed icons of missing buffs.
local K, B = C.Const, C.AuraButtons
local floor, max = math.floor, math.max
local EMPTY, QUESTION = C.EMPTY, K.QUESTION_ICON
local STACK_COLOR = NS.CDM.SPELL_DEFAULTS.stackColor
local Px = K.Px
local holders = {} -- addon-owned samples and missing-aura placeholders per cell

-- A plain, reusable sample shares the live bar's style. It never binds a
-- unit, reads aura state, or writes an entry; menu and Edit Mode use it alike.
function B.Sample(parent, row, view, ov, texture, name)
    if not row then
        row = S.CreateFrame("Frame", nil, parent)
        row.rec = { role = "bar", lk = {} }
        local times = S.CreateFrame("Frame", nil, row)
        local stacks = S.CreateFrame("Frame", nil, row)
        times:SetAllPoints(row)
        stacks:SetAllPoints(row)
        local part = { button = row, edges = {}, sample = true,
            timeFrame = times, stackFrame = stacks,
            icon = S.CreateTexture(row, nil, "ARTWORK"), bg = S.CreateTexture(row, nil, "BACKGROUND"),
            bar = S.CreateFrame("StatusBar", nil, row),
            name = S.CreateFontString(times, nil, "OVERLAY"), dur = S.CreateFontString(times, nil, "OVERLAY"),
            count = S.CreateFontString(stacks, nil, "OVERLAY") }
        for i = 1, 4 do part.edges[i] = S.CreateTexture(row, nil, "OVERLAY") end
        part.bar:SetFrameLevel(row:GetFrameLevel())
        row.part = part
        row.name, row.icon, row.bg, row.fill = part.name, part.icon, part.bg, part.bar
    end
    ov = ov or EMPTY
    local px = Px()
    if row.sampleView == view and row.sampleStyle == view.styleGen and row.sampleBehavior == view.behaviorGen
        and row.sampleOv == ov and row.sampleTexture == texture and row.sampleName == name and row.samplePx == px then return row end
    row.sampleView, row.sampleStyle, row.sampleBehavior = view, view.styleGen, view.behaviorGen
    row.sampleOv, row.sampleTexture, row.sampleName = ov, texture, name
    row.samplePx = px
    local rec, part = row.rec, row.part
    rec.stackFill = view.barStacks == true
    -- The live buttons' look and markers (AuraButtons Look and Style).
    B.Look(rec, view)
    B.Style(rec, part)
    local stackMax = rec.lk.smax
    local amount = max(1, floor(stackMax * .6))
    part.bar:SetMinMaxValues(0, rec.stackFill and stackMax or 1)
    part.bar:SetValue(rec.stackFill and amount or (view.barFill == 2 and .4 or .6))
    if rec.stackFill and (view.barStackColorAt or 0) > 0 and amount >= view.barStackColorAt then
        part.bar:SetStatusBarColor(K.HexRGB(view.barStackColor or "ff6633"))
    end
    part.icon:SetTexture(texture or QUESTION)
    part.name:SetText(name or "")
    part.name:SetShown(view.barName ~= false)
    part.dur:SetText("8")
    part.dur:SetShown(K.Choice(ov.timeText, K.BarTime(view)))
    local threshold = ov.threshold
    if threshold == nil then threshold = C.state.threshold or 0 end
    if threshold > 8 then part.dur:SetTextColor(C.state.thR or 1, C.state.thG or 1, C.state.thB or 1) end
    part.count:SetText(amount > 1 and tostring(amount) or "")
    part.count:SetShown(K.Choice(ov.stackText, K.BarStacks(view, false)))
    if (ov.stackColorAt or 0) > 0 and amount >= ov.stackColorAt then
        part.count:SetTextColor(K.HexRGB(ov.stackColor or STACK_COLOR))
    end
    local level = row:GetFrameLevel()
    local top = K.Choice(ov.textTop, K.BarStacksTop(view))
    part.stackFrame:SetFrameLevel(level + (top and 3 or 2))
    part.timeFrame:SetFrameLevel(level + (top and 2 or 3))
    return row
end

------------------------------------------------------------------ placeholders
-- Addon-owned regions on the cell, under the slot button: a dimmed icon
-- for missing buffs (showMissing) and the sample icon in the preview.
local function Unhold(cell)
    local h = cell and holders[cell]
    if h and h.shown then
        h.shown = false
        h.icon:Hide()
        h.bg:Hide()
        h.name:Hide()
        if h.sample then h.sample:Hide() end
    end
end
local function Unholds(slot)
    local bar = C.bars[slot]
    if not bar or not bar.cells then return end
    local cells = bar.cells
    for i = 1, #cells do Unhold(cells[i]) end
end

local function Hold(cell, entry, barMeta, dim, view)
    local h = holders[cell]
    if not h then
        h = { bg = S.CreateTexture(cell, nil, "BACKGROUND", nil, 0), icon = S.CreateTexture(cell, nil, "BACKGROUND", nil, 1),
            name = S.CreateFontString(cell, nil, "ARTWORK") }
        h.name:SetWordWrap(false)
        h.name:SetJustifyH("LEFT")
        holders[cell] = h
    end
    local tex = (entry.ov or EMPTY).icon or entry.texture or QUESTION
    if not dim and barMeta.role == "bar" then
        h.shown, h.e, h.look, h.dim = true, nil, nil, nil
        h.icon:Hide()
        h.bg:Hide()
        h.name:Hide()
        h.sample = B.Sample(cell, h.sample, view, entry.ov, tex, entry.name)
        h.sample:SetAllPoints(cell)
        h.sample:Show()
        return
    end
    if h.sample then h.sample:Hide() end
    if h.shown and h.e == entry and h.tex == tex and h.look == barMeta.look and h.dim == dim then return end
    h.shown, h.e, h.tex, h.look, h.dim = true, entry, tex, barMeta.look, dim
    local lk, icon = barMeta.lk, h.icon
    local bw = lk.bw
    icon:SetTexture(tex)
    icon:SetTexCoord(lk.l, lk.r, lk.t, lk.b)
    icon:SetDesaturated(dim)
    icon:SetAlpha(dim and .5 or 1)
    icon:ClearAllPoints()
    if barMeta.role == "bar" then
        local left = lk.side == 1
        local point = left and "TOPLEFT" or "TOPRIGHT"
        icon:SetPoint(point, cell, point, left and bw or -bw, -bw)
        icon:SetSize(lk.h - 2 * bw, lk.h - 2 * bw)
        icon:SetShown(lk.icon)
        local bg, name = h.bg, h.name
        bg:ClearAllPoints()
        bg:SetAllPoints(cell)
        bg:SetTexture(lk.tex)
        bg:SetVertexColor(lk.fr * .25, lk.fg * .25, lk.fb * .25, dim and lk.bgA * .6 or lk.bgA)
        bg:Show()
        S.SetStyledFont(name, lk.font, lk.cs, lk.flags, lk.rendering, lk.shadow, lk.shadowOpacity, lk.shadowDistance)
        name:SetTextColor(lk.cr, lk.cg, lk.cb, dim and .6 or 1)
        name:ClearAllPoints()
        local lead = lk.icon and lk.h or 0
        name:SetPoint("LEFT", cell, "LEFT", (left and lead or 0) + 4 * lk.px, 0)
        name:SetPoint("RIGHT", cell, "RIGHT", -(left and 0 or lead) - 4 * lk.px, 0)
        name:SetText(entry.name or "")
        name:Show()
    else
        icon:SetPoint("TOPLEFT", cell, "TOPLEFT", bw, -bw)
        icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -bw, bw)
        icon:Show()
        h.bg:Hide()
        h.name:Hide()
    end
end

-- preview: the aura layer's preview state (every entry shows its sample).
local function Placeholders(slot, view, plan, barMeta, preview)
    -- The bar and its cells exist once the layout built them.
    local bar = C.bars[slot]
    if not (bar and bar.cells) then return end
    local Cell = C.Layout.Cell
    local entries = plan.entries
    local cap = #entries
    local limit = view.maxIcons
    if type(limit) == "number" and limit > 0 and limit < cap then cap = limit end
    for i = 1, cap do
        local entry = entries[i]
        local show = preview
        if not show and barMeta.fixed and entry.src ~= "p" then
            show = (entry.ov or EMPTY).showMissing
            if show == nil then show = view.showMissing == true end
        end
        if show then
            Hold(Cell(slot, i), entry, barMeta, not preview, view)
        else
            Unhold(bar.cells[i])
        end
    end
    local cells = bar.cells
    for i = cap + 1, #cells do Unhold(cells[i]) end
end

B.Unholds, B.Placeholders = Unholds, Placeholders
