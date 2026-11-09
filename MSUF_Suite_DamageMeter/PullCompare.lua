local _, private = ...
local D, S, NS = private.DamageMeter, private.Suite, private.NS
local M = D.M
local WIDTH, HEIGHT = 600, 534
local INSET, ROW_HEIGHT, PAGE_SIZE = 16, 23, 6
local CELL_WIDTH = 88
local EMPTY_VALUE = "—"
local panel

local function Button(parent, width, height, click)
    local button = NS.HostBridge.MenuButton(parent, width, height)
        or S.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetScript("OnClick", click)
    return button
end

local function Label(parent, text, size)
    local label = S.QoLLabel(parent, text, size)
    label:SetJustifyH("LEFT")
    label:SetMaxLines(1)
    return label
end

local function Columns(row, text, size)
    local name = Label(row, text, size)
    name:SetPoint("LEFT", 8, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -(3 * CELL_WIDTH + 18), 0)
    row.name = name
    row.values = {}
    for i = 1, 3 do
        local value = Label(row, "", size)
        value:SetJustifyH("RIGHT")
        value:SetWidth(CELL_WIDTH - 8)
        value:SetPoint("RIGHT", row, "RIGHT", -8 - (3 - i) * CELL_WIDTH, 0)
        row.values[i] = value
    end
end

local function FormatRate(value)
    return value == nil and EMPTY_VALUE or D.Abbreviate(value)
end

local function PaintDelta(label, a, b)
    if a == nil or b == nil then
        label:SetText(EMPTY_VALUE)
        label:SetTextColor(.65, .69, .74)
        return
    end
    local delta = b - a
    if delta > 0 then
        label:SetText("+" .. D.Abbreviate(delta))
        label:SetTextColor(.45, .85, .67)
    elseif delta < 0 then
        label:SetText("−" .. D.Abbreviate(-delta))
        label:SetTextColor(.96, .56, .56)
    else
        label:SetText("0")
        label:SetTextColor(.65, .69, .74)
    end
end

local function PaintList(list)
    local count = #list.items
    for i = 1, PAGE_SIZE do
        local row, item = list.rows[i], list.items[list.offset + i]
        row.item = item
        if item then
            if not item.label then
                local name = C_Spell.GetSpellName(item.spellID)
                item.label = S.PublicText(name) or tostring(item.spellID)
            end
            row.name:SetText(item.label)
            row.values[1]:SetText(FormatRate(item.rateA))
            row.values[2]:SetText(FormatRate(item.rateB))
            PaintDelta(row.values[3], item.rateA, item.rateB)
            local active = item == list.selected
            row.fill:SetColorTexture(.34, .48, .62, active and .35 or (i % 2 == 1 and .12 or .04))
        end
        row:SetShown(item ~= nil)
    end
    list.message:SetShown(count == 0)
    list.counter:SetText(S.Text("%d–%d of %d"):format(
        count > 0 and list.offset + 1 or 0, math.min(count, list.offset + PAGE_SIZE), count))
    local paged = count > PAGE_SIZE
    list.prev:SetShown(paged)
    list.next:SetShown(paged)
    list.counter:SetShown(paged)
    list.prev:SetEnabled(list.offset > 0)
    list.next:SetEnabled(list.offset + PAGE_SIZE < count)
end

local function Page(list, direction)
    local offset = list.offset + direction * PAGE_SIZE
    if list.items and offset >= 0 and offset < #list.items then
        list.offset = offset
        PaintList(list)
    end
end

local function SetItems(list, items, message, selected)
    list.items, list.selected, list.offset = items or {}, selected, 0
    if selected then
        for i = 1, #list.items do
            if list.items[i] == selected then
                list.offset = math.floor((i - 1) / PAGE_SIZE) * PAGE_SIZE
                break
            end
        end
    end
    list.message:SetText(message or "")
    PaintList(list)
end

local function ReadSpells()
    local player = panel.players.selected
    if not player then
        panel.spellHeader.name:SetText(S.BlizzardText("SPELLS", "Spells"))
        SetItems(panel.spells, nil, S.Text("Select a player to compare spells."))
        return
    end
    panel.spellHeader.name:SetText(S.Text("Spells — %s"):format(player.label))
    local spells = D.CompareSpells(panel.pullA.id, panel.pullB.id, panel.meterType, player)
    local message = spells and S.Text("No spells recorded for this player.") or S.Text("Spell data is unavailable for this player.")
    SetItems(panel.spells, spells, message)
end

local function PickPlayer(row)
    local list = panel.players
    if not row.item or list.selected == row.item then return end
    list.selected = row.item
    PaintList(list)
    ReadSpells()
end

local function ReadPlayers()
    local hasPulls = panel.pullA and panel.pullB
    local players = hasPulls and D.ComparePlayers(panel.pullA.id, panel.pullB.id, panel.meterType)
    local selected
    if players then
        for i = 1, #players do
            local player = players[i]
            player.label = player.name
            if player.localPlayer then selected = player end
        end
        selected = selected or players[1]
    end
    local message = hasPulls and S.Text("Combat data is unavailable for these pulls.") or S.Text("Complete two fights to compare them.")
    SetItems(panel.players, players, message, selected)
    ReadSpells()
end

local function PaintMode(button)
    local label = D.TypeName(button.meterType)
    button:SetText(panel.meterType == button.meterType and ("|cffffd282" .. label .. "|r") or label)
end

local function SelectMode(button)
    if panel.meterType == button.meterType then return end
    panel.meterType = button.meterType
    PaintMode(panel.dps)
    PaintMode(panel.hps)
    ReadPlayers()
end

local function PullSelected(data)
    return panel[data.side] == data.segment
end

local function SetPullLabels()
    panel.aButton:SetText(panel.pullA and panel.pullA.label .. " ▾" or EMPTY_VALUE)
    panel.bButton:SetText(panel.pullB and panel.pullB.label .. " ▾" or EMPTY_VALUE)
end

local function PickPull(data)
    if panel.segments ~= data.segments or panel[data.side] == data.segment then return end
    local other = data.side == "pullA" and "pullB" or "pullA"
    if panel[other] == data.segment then panel[other] = panel[data.side] end
    panel[data.side] = data.segment
    SetPullLabels()
    ReadPlayers()
end

local function PullMenu(_, root, side)
    local segments = panel.segments
    if not segments then return end
    for i = 1, #segments do
        local segment = segments[i]
        root:CreateRadio(segment.label, PullSelected, PickPull, { segment = segment, side = side, segments = segments })
    end
end

local function OpenPullMenu(button)
    panel.menuOwner = button
    D.OpenDropdown(button, PullMenu, button.side)
end

local function NewRow(list, index, click)
    local row = S.CreateFrame(click and "Button" or "Frame", nil, list)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetHeight(ROW_HEIGHT)
    row.fill = S.CreateTexture(row, nil, "BACKGROUND")
    row.fill:SetAllPoints()
    Columns(row, "", 12)
    if click then
        local highlight = S.CreateTexture(row, nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(.43, .62, .80, .19)
        row:SetScript("OnClick", click)
    end
    return row
end

local function NewList(parent, top, title, click)
    local header = S.CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", INSET, -top)
    header:SetPoint("TOPRIGHT", -INSET, -top)
    header:SetHeight(24)
    local background = S.CreateTexture(header, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.13, .17, .22, .96)
    Columns(header, title, 12)
    header.values[1]:SetText(S.Text("Pull A"))
    header.values[2]:SetText(S.Text("Pull B"))
    header.values[3]:SetText("B − A")

    local list = S.CreateFrame("Frame", nil, parent)
    list:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    list:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
    list:SetHeight(ROW_HEIGHT * PAGE_SIZE)
    list.rows = {}
    for i = 1, PAGE_SIZE do list.rows[i] = NewRow(list, i, click) end
    list.message = Label(list, "", 12)
    list.message:SetPoint("TOPLEFT", 8, -12)
    list.message:SetPoint("RIGHT", -8, 0)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta) Page(self, delta > 0 and -1 or 1) end)
    list.prev = Button(parent, 27, 22, function() Page(list, -1) end)
    list.prev:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -2)
    list.prev:SetText("‹")
    list.next = Button(parent, 27, 22, function() Page(list, 1) end)
    list.next:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -2)
    list.next:SetText("›")
    list.counter = Label(parent, "", 11)
    list.counter:SetPoint("TOP", list, "BOTTOM", 0, -7)
    return list, header
end

local function ClearList(list)
    list.items, list.selected = nil, nil
    for i = 1, PAGE_SIZE do list.rows[i].item = nil end
end

function D.ClosePullCompare()
    if not M.compareOpen then return end
    M.compareOpen = nil
    if panel.menuOwner then
        S.CloseOwnedContextMenu(panel.menuOwner)
        panel.menuOwner = nil
    end
    panel:Hide()
    panel.segments, panel.pullA, panel.pullB = nil, nil, nil
    ClearList(panel.players)
    ClearList(panel.spells)
    if M.active then D.UpdateEvents() end
end

local function MakePanel()
    local frame = S.QoLWindow(WIDTH, HEIGHT, "Compare pulls", 16, true)
    frame:Hide()
    frame.close:SetScript("OnClick", D.ClosePullCompare)
    local left = Label(frame, "Pull A", 11)
    left:SetPoint("TOPLEFT", INSET, -48)
    frame.aButton = Button(frame, 211, 28, OpenPullMenu)
    frame.aButton.side = "pullA"
    frame.aButton:SetPoint("TOPLEFT", left, "BOTTOMLEFT", 0, -5)
    local right = Label(frame, "Pull B", 11)
    right:SetPoint("LEFT", left, "LEFT", 219, 0)
    frame.bButton = Button(frame, 211, 28, OpenPullMenu)
    frame.bButton.side = "pullB"
    frame.bButton:SetPoint("TOPLEFT", right, "BOTTOMLEFT", 0, -5)
    frame.hps = Button(frame, 60, 28, SelectMode)
    frame.hps:SetPoint("TOPRIGHT", -INSET, -66)
    frame.hps.meterType = D.TYPE.Hps
    frame.dps = Button(frame, 60, 28, SelectMode)
    frame.dps:SetPoint("RIGHT", frame.hps, "LEFT", -5, 0)
    frame.dps.meterType = D.TYPE.Dps
    frame.players = NewList(frame, 110, S.BlizzardText("PLAYER", "Player"), PickPlayer)
    frame.spells, frame.spellHeader = NewList(frame, 314, S.BlizzardText("SPELLS", "Spells"))
    return frame
end

function D.OpenPullCompare(win)
    if not M.active or M.inCombat or NS.IsCombatLocked() then return end
    if not panel then panel = MakePanel() end
    panel.segments = D.CompareSegments() or {}
    local latest, previous = panel.segments[1], panel.segments[2]
    panel.pullA, panel.pullB = previous, latest
    if previous and win.sessionID then
        for i = 2, #panel.segments do
            local segment = panel.segments[i]
            if segment.id == win.sessionID then
                panel.pullA, panel.pullB = latest, segment
                break
            end
        end
    end
    panel.meterType = D.healingTypes[win.meterType] and D.TYPE.Hps or D.TYPE.Dps
    PaintMode(panel.dps)
    PaintMode(panel.hps)
    panel.aButton:SetEnabled(previous ~= nil)
    panel.bButton:SetEnabled(previous ~= nil)
    SetPullLabels()
    ReadPlayers()
    M.compareOpen = true
    panel:Show()
    D.UpdateEvents()
end
