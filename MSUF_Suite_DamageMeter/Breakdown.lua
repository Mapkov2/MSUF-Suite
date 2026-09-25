local _, P = ...
local NS, S = P.NS, P.Suite
-- Spell breakdowns: the in-window panel (click a row) and the hover tooltip.
-- Both fetch a source only with a plain identity (D.Identity); a row whose
-- identity is secret shows an explanation instead of querying the API.
local D = P.DamageMeter
local M = D.M
local Public = S.Public
local max, min = math.max, math.min
local TIP_WIDTH, TIP_PAD, TIP_ROW = 260, 6, 17

local function StylePanel(win)
    local panel, style = win.panel, M.style
    panel.styleGen = M.styleGen
    local height = style.barHeight
    panel.back:ClearAllPoints()
    panel.back:SetSize(height, height)
    panel.back:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    D.FontStyle(panel.title, style.leftSize)
    panel.title:SetTextColor(style.leftR, style.leftG, style.leftB)
    panel.title:ClearAllPoints()
    panel.title:SetPoint("LEFT", panel.back, "RIGHT", 3, style.baseline)
    panel.title:SetPoint("RIGHT", panel, "RIGHT", -3, style.baseline)
    D.FontStyle(panel.message, style.leftSize)
    panel.message:SetTextColor(.8, .8, .8)
    local top = -(height + style.spacing + 6)
    panel.message:ClearAllPoints()
    panel.message:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, top + style.baseline)
    panel.message:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, top + style.baseline)
    for slot, row in pairs(win.bdRows) do D.AnchorRow(row, panel, slot + 1) end
end

function D.EnsurePanel(win)
    local panel = win.panel
    if panel then return panel end
    panel = S.CreateFrame("Button", nil, win.frame)
    panel.win, win.panel, win.bdRows = win, panel, {}
    panel:SetAllPoints(win.body)
    panel:SetFrameLevel(win.body:GetFrameLevel() + 4)
    panel:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    panel:EnableMouseWheel(true)
    for script, handler in pairs(D.panelScripts) do panel:SetScript(script, handler) end
    panel.back = S.CreateTexture(panel, nil, "ARTWORK")
    if not D.Atlas(panel.back, "common-icon-backarrow") then panel.back:Hide() end
    panel.title = S.CreateFontString(panel, nil, "OVERLAY")
    panel.title:SetJustifyH("LEFT")
    panel.title:SetWordWrap(false)
    panel.message = S.CreateFontString(panel, nil, "OVERLAY")
    panel.message:SetJustifyH("CENTER")
    panel:Hide()
    return panel
end

local function SetMessage(panel, text)
    if text ~= panel.messageText then
        panel.messageText = text
        panel.message:SetText(text)
    end
end

function D.ShowPanel(win, blocked)
    local panel = D.EnsurePanel(win)
    if panel.styleGen ~= M.styleGen then StylePanel(win) end
    local bd = win.bd
    bd.open, bd.blocked, bd.offset = true, blocked, 0
    local name = bd.name
    panel.title:SetText(D.Short(name))
    D.HideTip()
    for _, row in pairs(win.rows) do row:Hide() end
    win.statusText = ""
    win.status:SetText("")
    panel:Show()
end

function D.OpenBreakdown(win, index)
    local session = win.session
    if not session or D.IsSample(session) then return end
    local source = session.combatSources[index]
    if not source then return end
    if win.meterType == D.DEATHS then
        D.OpenRecap(win, source)
        return
    end
    local bd = win.bd
    bd.guid, bd.creature = D.Identity(source)
    local class = source.classFilename
    bd.class = Public(class) and type(class) == "string" and class or ""
    bd.name, bd.duration = source.name, session.durationSeconds
    D.ShowPanel(win, not bd.guid and not bd.creature)
    D.RefreshBreakdown(win)
end

-- Blizzard's recap panel reads the recap in the calling (addon) context and
-- would receive secrets during combat; it opens once the row is readable.
function D.OpenRecap(win, source)
    local id, open = source.deathRecapID, _G.OpenDeathRecapUI
    if not D.Plain(id) or id <= 0 or type(open) ~= "function" then return end
    if Public(source.deathTimeSeconds) then
        open(id)
        return
    end
    local bd = win.bd
    bd.name, bd.class, bd.guid, bd.creature = source.name, "", nil, nil
    D.ShowPanel(win, true)
    D.RefreshBreakdown(win)
end

function D.CloseBreakdown(win, quiet)
    local bd = win.bd
    if not bd.open then return end
    bd.open, bd.source, bd.name, bd.guid, bd.creature, bd.duration = false, nil, nil, nil, nil, nil
    local tooltip = _G.GameTooltip
    if tooltip and win.bdRows then
        local owner = tooltip:GetOwner()
        for _, row in pairs(win.bdRows) do
            if owner == row then
                tooltip:Hide()
                break
            end
        end
    end
    if win.panel then win.panel:Hide() end
    win.dirty = true
    if not quiet and win.shown then D.Paint(win) end
end

-- Refetch with the stored plain identity (the window paint path while open).
function D.RefreshBreakdown(win)
    local bd = win.bd
    if bd.blocked then
        bd.source = nil
        for _, row in pairs(win.bdRows) do row:Hide() end
        SetMessage(win.panel, D.Blocked())
        return
    end
    bd.source = D.FetchSource(win, bd.guid, bd.creature)
    D.RenderBreakdown(win)
end

function D.RenderBreakdown(win)
    local bd, panel = win.bd, win.panel
    if bd.blocked then return end
    if panel.styleGen ~= M.styleGen then StylePanel(win) end
    local source = bd.source
    local capacity = max(0, win.capacity - 1)
    local groups, count, sum
    if win.meterType == D.ENEMY then groups, count, sum = D.GroupSpells(source) end
    local spells = not groups and source and source.combatSpells
    if not groups then count = D.Count(spells) end
    bd.offset = min(bd.offset, max(0, count - capacity))
    local duration = D.Plain(bd.duration) and bd.duration or 0
    local rows = win.bdRows
    for slot = 1, capacity do
        local index, row = bd.offset + slot, rows[slot]
        if index <= count then
            if not row then
                row = D.CreateRow(panel, win, "spell")
                rows[slot] = row
                D.AnchorRow(row, panel, slot + 1)
            end
            if groups then
                D.PaintGroup(row, groups[index], groups[1].amount, sum, duration, win.meterType)
            else
                D.PaintSpell(row, spells[index], source, win.meterType, bd.class)
            end
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    for slot, row in pairs(rows) do if slot > capacity then row:Hide() end end
    SetMessage(panel, count == 0 and S.Text("No details for this entry.") or "")
end

function D.ScrollBreakdown(win, delta)
    local bd = win.bd
    if not bd.open or bd.blocked or not Public(delta) or type(delta) ~= "number" or delta == 0 then return end
    local offset = max(0, bd.offset + (delta > 0 and -2 or 2))
    if offset ~= bd.offset then
        bd.offset = offset
        D.RenderBreakdown(win)
    end
end

local tip
local function EnsureTip()
    if tip then return tip end
    tip = S.CreateFrame("Frame", nil, UIParent)
    tip:SetFrameStrata("TOOLTIP")
    tip:SetClampedToScreen(true)
    tip:SetWidth(TIP_WIDTH)
    tip:Hide()
    local background = S.CreateTexture(tip, nil, "BACKGROUND")
    background:SetAllPoints(tip)
    background:SetColorTexture(.05, .05, .05, .92)
    tip.title = S.CreateFontString(tip, nil, "OVERLAY")
    tip.title:SetPoint("TOPLEFT", tip, "TOPLEFT", TIP_PAD, -TIP_PAD)
    tip.title:SetPoint("TOPRIGHT", tip, "TOPRIGHT", -TIP_PAD, -TIP_PAD)
    tip.title:SetJustifyH("LEFT")
    tip.title:SetWordWrap(false)
    tip.message = S.CreateFontString(tip, nil, "OVERLAY")
    tip.message:SetPoint("TOPLEFT", tip.title, "BOTTOMLEFT", 0, -4)
    tip.message:SetPoint("TOPRIGHT", tip.title, "BOTTOMRIGHT", 0, -4)
    tip.message:SetJustifyH("LEFT")
    tip.rows = {}
    M.tip = tip
    return tip
end

-- Fills the tooltip rows; returns the row count and an optional message.
local function TipContent(frame, win, source, session)
    if win.meterType == D.DEATHS then
        local id = source.deathRecapID
        if type(_G.OpenDeathRecapUI) ~= "function" or not D.Plain(id) or id <= 0 then return 0, nil end
        return 0, Public(source.deathTimeSeconds) and S.Text("Click to open the death recap.") or D.Blocked()
    end
    local guid, creature = D.Identity(source)
    if not guid and not creature then return 0, D.Blocked() end
    local detail = D.FetchSource(win, guid, creature)
    local class = source.classFilename
    class = Public(class) and type(class) == "string" and class or ""
    local groups, count, sum
    if win.meterType == D.ENEMY then groups, count, sum = D.GroupSpells(detail) end
    local spells = not groups and detail and detail.combatSpells
    if not groups then count = D.Count(spells) end
    local shown = min(count, M.config.tooltipRows)
    local duration = D.Plain(session.durationSeconds) and session.durationSeconds or 0
    for i = 1, shown do
        local row = frame.rows[i]
        if not row then
            row = D.CreateRow(frame, nil, "tip")
            frame.rows[i] = row
            local y = -(TIP_PAD + 18 + (i - 1) * TIP_ROW)
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", TIP_PAD, y)
            row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TIP_PAD, y)
        end
        if groups then
            D.PaintGroup(row, groups[i], groups[1].amount, sum, duration, win.meterType)
        else
            D.PaintSpell(row, spells[i], detail, win.meterType, class)
        end
        row:Show()
    end
    return shown, shown == 0 and S.Text("No details for this entry.") or nil
end

-- Built once per hover, never live-updated.
function D.ShowTip(win, row)
    local session = win.session
    if not session or D.IsSample(session) or not row.index then return end
    local source = session.combatSources[row.index]
    if not source then return end
    local frame = EnsureTip()
    if frame.styleGen ~= M.styleGen then
        frame.styleGen = M.styleGen
        D.FontStyle(frame.title, 12)
        D.FontStyle(frame.message, 11)
        frame.message:SetTextColor(.8, .8, .8)
        frame.title:ClearAllPoints()
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", TIP_PAD, -TIP_PAD + M.style.baseline)
        frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TIP_PAD, -TIP_PAD + M.style.baseline)
    end
    local name = source.name
    frame.title:SetFormattedText("%s - %s", D.Short(name), D.TypeName(win.meterType))
    local shown, message = TipContent(frame, win, source, session)
    for i = shown + 1, #frame.rows do frame.rows[i]:Hide() end
    frame.message:SetText(message or "")
    frame.message:SetShown(message ~= nil)
    frame:SetHeight(TIP_PAD * 2 + 16 + (message and 18 or 0) + shown * TIP_ROW)
    frame:SetScale(M.config.tooltipScale / 100)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, 4)
    frame:Show()
end

function D.HideTip() if tip then tip:Hide() end end

function D.RowClick(row, button)
    local win = row.win
    if button == "RightButton" then
        D.OpenTypeMenu(win, row)
        return
    end
    if row.index then
        D.HideTip()
        D.OpenBreakdown(win, row.index)
    end
end

function D.RowEnter(row)
    D.HoverEnter(row)
    if M.config.hoverTooltip and not row.win.bd.open then D.ShowTip(row.win, row) end
end

function D.RowLeave(row)
    D.HideTip()
    D.HoverLeave(row)
end

function D.RowWheel(row, delta) D.Scroll(row.win, delta) end

function D.SpellEnter(row)
    D.HoverEnter(row)
    local tooltip = _G.GameTooltip
    if not M.config.spellTooltips or not row.spellID or not tooltip then return end
    tooltip:SetOwner(row, "ANCHOR_LEFT")
    if type(tooltip.SetSpellByID) == "function" then tooltip:SetSpellByID(row.spellID) end
    tooltip:Show()
end

function D.SpellLeave(row)
    local tooltip = _G.GameTooltip
    if tooltip and tooltip:GetOwner() == row then tooltip:Hide() end
    D.HoverLeave(row)
end

function D.BreakdownBack(region) D.CloseBreakdown(region.win) end

function D.BreakdownWheel(region, delta) D.ScrollBreakdown(region.win, delta) end

D.listScripts = { OnClick = D.RowClick, OnEnter = D.RowEnter, OnLeave = D.RowLeave, OnMouseWheel = D.RowWheel }
D.spellScripts = {
    OnClick = D.BreakdownBack,
    OnEnter = D.SpellEnter,
    OnLeave = D.SpellLeave,
    OnMouseWheel = D
        .BreakdownWheel
}
D.panelScripts = {
    OnClick = D.BreakdownBack,
    OnMouseWheel = D.BreakdownWheel,
    OnEnter = D.HoverEnter,
    OnLeave = D
        .HoverLeave
}
