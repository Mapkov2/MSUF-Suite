local _, P = ...
local S = P.Suite
local NS = P.NS
-- Spell breakdowns: the in-window panel (click a row) and the hover tooltip.
-- Both fetch a source only with a plain identity (D.Identity); a row whose
-- identity is secret shows an explanation instead of querying the API.
local D = P.DamageMeter
local M = D.M
local Public, Finite = S.Public, S.Finite
local max, min = math.max, math.min
local TIP_WIDTH, TIP_PAD, TIP_ROW = 260, 6, 17

local function StyleTabs(panel, view)
    local selected = M.style
    panel.targetsTab.text:SetTextColor(view == "targets" and selected.leftR or .6,
        view == "targets" and selected.leftG or .6, view == "targets" and selected.leftB or .6)
    panel.spellsTab.text:SetTextColor(view == "spells" and selected.leftR or .6,
        view == "spells" and selected.leftG or .6, view == "spells" and selected.leftB or .6)
end

local function StylePanel(win)
    local panel, style = win.panel, M.style
    panel.styleGen = M.styleGen
    panel.styledType = win.meterType
    local height = style.barHeight
    panel.back:ClearAllPoints()
    panel.back:SetSize(height, height)
    panel.back:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    D.FontStyle(panel.title, style.leftSize)
    panel.title:SetTextColor(style.leftR, style.leftG, style.leftB)
    panel.title:ClearAllPoints()
    panel.title:SetPoint("LEFT", panel.back, "RIGHT", 3, style.baseline)
    panel.spellsTab:ClearAllPoints()
    panel.spellsTab:SetSize(58, height)
    panel.spellsTab:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, 0)
    panel.targetsTab:ClearAllPoints()
    panel.targetsTab:SetSize(58, height)
    panel.targetsTab:SetPoint("RIGHT", panel.spellsTab, "LEFT", -2, 0)
    D.FontStyle(panel.targetsTab.text, 10)
    D.FontStyle(panel.spellsTab.text, 10)
    if D.targetTypes[win.meterType] then
        panel.title:SetPoint("RIGHT", panel.targetsTab, "LEFT", -3, style.baseline)
    else
        panel.title:SetPoint("RIGHT", panel, "RIGHT", -3, style.baseline)
    end
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
    local function Tab(text, view)
        local button = S.CreateFrame("Button", nil, panel)
        button.win = win
        button:RegisterForClicks("LeftButtonUp")
        button.text = S.CreateFontString(button, nil, "OVERLAY")
        button.text:SetAllPoints(button)
        button.text:SetJustifyH("CENTER")
        D.FontStyle(button.text, 10)
        button.text:SetText(S.Text(text))
        button:SetScript("OnClick", function() D.SetBreakdownView(win, view) end)
        return button
    end
    panel.targetsTab, panel.spellsTab = Tab("Targets", "targets"), Tab("Spells", "spells")
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
    if panel.styleGen ~= M.styleGen or panel.styledType ~= win.meterType then StylePanel(win) end
    local bd = win.bd
    bd.open, bd.blocked, bd.offset = true, blocked, 0
    local tabs = not blocked and D.targetTypes[win.meterType] == true
    panel.targetsTab:SetShown(tabs)
    panel.spellsTab:SetShown(tabs)
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
    if win.meterType == D.TYPE.Deaths then
        D.OpenRecap(win, source)
        return
    end
    local bd = win.bd
    bd.guid, bd.creature = D.Identity(source)
    local class = source.classFilename
    bd.class = Public(class) and type(class) == "string" and class or ""
    bd.name, bd.duration, bd.listSource, bd.targetRevision = source.name, session.durationSeconds, source, nil
    bd.view = "spells"
    D.ShowPanel(win, not bd.guid and not bd.creature)
    D.RefreshBreakdown(win)
end

-- Blizzard's recap panel reads the recap in the calling (addon) context and
-- would receive secrets during combat; it opens once the row is readable.
function D.OpenRecap(win, source)
    local id = source.deathRecapID
    if not Finite(id) or id <= 0 then return end
    if Public(source.deathTimeSeconds) then
        OpenDeathRecapUI(id)
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
    bd.listSource, bd.view, bd.targetRevision = nil, nil, nil
    if win.bdRows then
        local owner = GameTooltip:GetOwner()
        for _, row in pairs(win.bdRows) do
            if owner == row then
                GameTooltip:Hide()
                break
            end
        end
    end
    if win.panel then win.panel:Hide() end
    win.dirty = true
    if not quiet and win.shown then D.Paint(win) end
end

-- A panel opened during combat holds a secret-bearing session snapshot. Once
-- the restriction lifts, get a fresh native session before aggregating targets.
local function RefreshTargetSession(win)
    local bd = win.bd
    if M.inCombat or NS.IsCombatLocked() or bd.targetRevision == M.targetRevision then return end
    bd.targetRevision = M.targetRevision
    local session = D.FetchSession(win)
    if not session or D.IsSample(session) then return end
    win.session, bd.listSource = session, nil
    local sources = session.combatSources
    for i = 1, D.Count(sources) do
        local source = sources[i]
        local guid, creature = D.Identity(source)
        local name = source.name
        if (bd.guid and guid == bd.guid) or (bd.creature and creature == bd.creature)
            or (Public(bd.name) and Public(name) and name == bd.name) then
            bd.listSource, bd.name, bd.duration = source, name, session.durationSeconds
            break
        end
    end
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
    if bd.view == "targets" then RefreshTargetSession(win) end
    bd.source = D.FetchSource(win, bd.guid, bd.creature)
    D.RenderBreakdown(win)
end

function D.RenderBreakdown(win)
    local bd, panel = win.bd, win.panel
    if bd.blocked then return end
    if panel.styleGen ~= M.styleGen or panel.styledType ~= win.meterType then StylePanel(win) end
    local source = bd.source
    local capacity = max(0, win.capacity - 1)
    local groups, count, sum, targets
    if bd.view == "targets" then
        groups, count, sum = D.TargetGroups(win, bd.listSource, source)
        targets = groups ~= nil
    end
    if bd.view == "spells" and win.meterType == D.TYPE.EnemyDamageTaken then
        groups, count, sum = D.GroupSpells(source)
    end
    local spells = bd.view == "spells" and not groups and source and source.combatSpells
    if not groups then count = D.Count(spells) end
    panel.title:SetText(D.Short(bd.name))
    StyleTabs(panel, bd.view)
    bd.offset = min(bd.offset, max(0, count - capacity))
    local duration = Finite(bd.duration) and bd.duration or 0
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
                D.PaintGroup(row, groups[index], groups[1].amount, sum, duration, win.meterType, targets)
            else
                D.PaintSpell(row, spells[index], source, win.meterType, bd.class)
            end
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    for slot, row in pairs(rows) do if slot > capacity then row:Hide() end end
    local message = count == 0 and S.Text(bd.view == "targets"
        and ((M.inCombat or NS.IsCombatLocked()) and "Targets after combat" or "Target data unavailable")
        or "No details for this entry.") or ""
    SetMessage(panel, message)
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
    tip.section = S.CreateFontString(tip, nil, "OVERLAY")
    D.FontStyle(tip.section, 11)
    tip.section:SetText(S.Text("Targets"))
    tip.section:Hide()
    tip.rows = {}
    M.tip = tip
    return tip
end

local function TipRow(frame, index, y)
    local row = frame.rows[index]
    if not row then
        row = D.CreateRow(frame, nil, "tip")
        frame.rows[index] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", TIP_PAD, y)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TIP_PAD, y)
    return row
end

-- Keep abilities visible and append the native target breakdown when readable.
local function TipContent(frame, win, source, session)
    frame.section:Hide()
    if win.meterType == D.TYPE.Deaths then
        local id = source.deathRecapID
        if not Finite(id) or id <= 0 then return 0, nil end
        return 0, Public(source.deathTimeSeconds) and S.Text("Click to open the death recap.") or D.Blocked()
    end
    local guid, creature = D.Identity(source)
    if not guid and not creature then return 0, D.Blocked() end
    local class = source.classFilename
    class = Public(class) and type(class) == "string" and class or ""
    local detail = D.FetchSource(win, guid, creature)
    local targetGroups, targetCount, targetSum = D.TargetGroups(win, source, detail)
    local spellGroups, spellCount, spellSum
    if win.meterType == D.TYPE.EnemyDamageTaken then spellGroups, spellCount, spellSum = D.GroupSpells(detail) end
    local spells = not spellGroups and detail and detail.combatSpells
    if not spellGroups then spellCount = D.Count(spells) end
    local spellShown = min(spellCount, M.config.tooltipRows)
    local duration = Finite(session.durationSeconds) and session.durationSeconds or 0
    for i = 1, spellShown do
        local row = TipRow(frame, i, -(TIP_PAD + 18 + (i - 1) * TIP_ROW))
        if spellGroups then
            D.PaintGroup(row, spellGroups[i], spellGroups[1].amount, spellSum, duration, win.meterType)
        else
            D.PaintSpell(row, spells[i], detail, win.meterType, class)
        end
        row:Show()
    end
    local targetShown = targetGroups and min(targetCount, M.config.tooltipRows) or 0
    local sectionHeight = targetShown > 0 and TIP_ROW or 0
    frame.section:SetShown(targetShown > 0)
    if targetShown > 0 then
        frame.section:ClearAllPoints()
        frame.section:SetPoint("TOPLEFT", frame, "TOPLEFT", TIP_PAD, -(TIP_PAD + 18 + spellShown * TIP_ROW))
        frame.section:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TIP_PAD, -(TIP_PAD + 18 + spellShown * TIP_ROW))
        for i = 1, targetShown do
            local row = TipRow(frame, spellShown + i,
                -(TIP_PAD + 18 + (spellShown + i - 1) * TIP_ROW + sectionHeight))
            D.PaintGroup(row, targetGroups[i], targetGroups[1].amount, targetSum, duration, win.meterType, true)
            row:Show()
        end
    end
    local shown = spellShown + targetShown
    local note
    if not targetGroups and D.targetTypes[win.meterType] then
        note = S.Text((M.inCombat or NS.IsCombatLocked()) and "Targets after combat" or "Target data unavailable")
    end
    return shown, note or (shown == 0 and S.Text("No details for this entry.") or nil), sectionHeight
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
        D.FontStyle(frame.section, 11)
        frame.section:SetTextColor(M.style.leftR, M.style.leftG, M.style.leftB)
        frame.message:SetTextColor(.8, .8, .8)
        frame.title:ClearAllPoints()
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", TIP_PAD, -TIP_PAD + M.style.baseline)
        frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TIP_PAD, -TIP_PAD + M.style.baseline)
    end
    local name = source.name
    local shown, message, sectionHeight = TipContent(frame, win, source, session)
    sectionHeight = sectionHeight or 0
    frame.title:SetFormattedText("%s - %s", D.Short(name), D.TypeName(win.meterType))
    for i = shown + 1, #frame.rows do frame.rows[i]:Hide() end
    frame.message:SetText(message or "")
    frame.message:SetShown(message ~= nil)
    frame.message:ClearAllPoints()
    local messageY = -(TIP_PAD + 18 + shown * TIP_ROW + sectionHeight)
    frame.message:SetPoint("TOPLEFT", frame, "TOPLEFT", TIP_PAD, messageY)
    frame.message:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TIP_PAD, messageY)
    frame:SetHeight(TIP_PAD * 2 + 16 + (message and 18 or 0) + shown * TIP_ROW + sectionHeight)
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
    if not M.config.spellTooltips or not row.spellID then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetSpellByID(row.spellID)
    GameTooltip:Show()
end

function D.SpellLeave(row)
    if GameTooltip:GetOwner() == row then GameTooltip:Hide() end
    D.HoverLeave(row)
end

function D.SetBreakdownView(win, view)
    if not win.bd.open or win.bd.blocked or not D.targetTypes[win.meterType] then return end
    if win.bd.view == view and view ~= "targets" then return end
    win.bd.view, win.bd.offset = view, 0
    if view == "targets" then
        win.bd.targetRevision = nil
        D.RefreshBreakdown(win)
    else
        D.RenderBreakdown(win)
    end
end

function D.BreakdownBack(region, button)
    local win = region.win
    if button == "RightButton" and win.bd.open and not win.bd.blocked and D.targetTypes[win.meterType] then
        D.SetBreakdownView(win, win.bd.view == "targets" and "spells" or "targets")
    else
        D.CloseBreakdown(win)
    end
end

function D.BreakdownWheel(region, delta) D.ScrollBreakdown(region.win, delta) end

D.listScripts = { OnClick = D.RowClick, OnEnter = D.RowEnter, OnLeave = D.RowLeave, OnMouseWheel = D.RowWheel }
D.spellScripts = {
    OnClick = D.BreakdownBack, OnEnter = D.SpellEnter, OnLeave = D.SpellLeave, OnMouseWheel = D.BreakdownWheel,
}
D.panelScripts = {
    OnClick = D.BreakdownBack, OnMouseWheel = D.BreakdownWheel, OnEnter = D.HoverEnter, OnLeave = D.HoverLeave,
}
