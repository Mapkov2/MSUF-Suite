local _, P = ...
local D, S, NS = P.DamageMeter, P.Suite, P.NS
local M, Public, Finite = D.M, S.Public, S.Finite
local max = math.max
local fields = { "timestamp", "spellName", "spellId", "amount", "overkill", "currentHP", "event" }

function D.ReadRecap(id)
    if not Finite(id) or id <= 0 then return nil end
    local available = C_DeathRecap.HasRecapEvents(id)
    if not Public(available) or available ~= true then return nil end
    local events = C_DeathRecap.GetRecapEvents(id)
    if not Public(events) or type(events) ~= "table" or D.Count(events) == 0 then return nil end
    local restricted = M.inCombat or NS.IsCombatLocked()
    for i = 1, D.Count(events) do
        local event = events[i]
        if not Public(event) or type(event) ~= "table" then return nil end
        if not restricted then
            for j = 1, #fields do
                if NS.IsSecret(event[fields[j]]) then restricted = true break end
            end
        end
    end
    local stamp = events[1].timestamp
    local ending = Finite(stamp) and stamp or nil
    local health = C_DeathRecap.GetRecapMaxHealth(id)
    return { id = id, events = events, maxHealth = health, ending = ending,
        restricted = restricted or NS.IsSecret(health) }
end

-- Combat end can precede data declassification. Retry only on the existing
-- dirty/restriction/late-paint routes until a fresh readable snapshot arrives.
function D.RefreshRecap(win)
    local recap = win.bd.recap
    if recap.restricted and not M.inCombat and not NS.IsCombatLocked() then
        win.bd.recap = D.ReadRecap(recap.id) or recap
    end
    D.RenderRecap(win)
end

local function EventName(event)
    local name = event.spellName
    if not Public(name) then return name end
    if type(name) == "string" and name ~= "" then return name end
    local kind = event.event
    if Public(kind) and kind == "SWING_DAMAGE" then return S.Text("Melee") end
    return S.Text("Unknown")
end

local function EventIcon(row, event)
    local id = event.spellId
    row.spellID = Finite(id) and id > 0 and id or nil
    local texture = row.spellID and C_Spell.GetSpellTexture(row.spellID)
    if texture then
        row.icon:SetTexture(texture)
        row.icon:SetTexCoord(.08, .92, .08, .92)
    end
    D.SetIconShown(row, texture ~= nil)
end

local function EventTime(event, recap)
    if not Finite(event.timestamp) then return nil end
    return recap.ending and max(0, recap.ending - event.timestamp)
end

function D.PaintRecap(row, event, recap)
    if row.styleGen ~= M.styleGen then D.StyleRow(row) end
    D.ClearMemo(row)
    D.RowColors(row, "")
    local kind = event.event
    local heal = Public(kind) and (kind == "SPELL_HEAL" or kind == "SPELL_PERIODIC_HEAL")
    if not Public(kind) then row.bar:SetStatusBarColor(.33, .33, .33)
    elseif heal then row.bar:SetStatusBarColor(.1, .5, .1)
    else row.bar:SetStatusBarColor(.6, .08, .08) end
    EventIcon(row, event)
    local name, seconds = EventName(event), EventTime(event, recap)
    if seconds then row.nameText:SetFormattedText("-%.1fs %s", seconds, name) else row.nameText:SetText(name) end
    local hp, health = event.currentHP, recap.maxHealth
    D.SetBar(row, health, hp)
    local amount, overkill = event.amount, event.overkill
    local text = D.Abbreviate(D.Num(amount))
    if Finite(overkill) and overkill > 0 then
        row.valueText:SetFormattedText(S.Text("%s (%s overkill)"), text, D.Abbreviate(overkill))
    elseif Finite(hp) and Finite(health) and health > 0 then
        row.valueText:SetFormattedText("%s (%.0f%%)", text, hp / health * 100)
    else row.valueText:SetText(text) end
end

-- Own, unprotected rows consume the native recap fields directly. Blizzard's
-- panel remains the default out-of-combat click action when it can open.
function D.OpenInlineRecap(win, source)
    local recap = D.ReadRecap(source.deathRecapID)
    if not recap then return false end
    local bd = win.bd
    bd.name, bd.class, bd.guid, bd.creature = source.name, "", nil, nil
    bd.view, bd.recap = "recap", recap
    D.ShowPanel(win, false)
    win.panel.targetsTab:Hide()
    win.panel.spellsTab:Hide()
    D.RenderRecap(win)
    return true
end

function D.RenderRecap(win)
    local bd, panel = win.bd, win.panel
    local count, capacity = D.Count(bd.recap.events), max(0, win.capacity - 1)
    bd.offset = math.min(bd.offset, max(0, count - capacity))
    -- A readable recap is our retained snapshot. A new read, scrolling,
    -- resizing or styling invalidates this view; secrets always reach sinks.
    if not bd.recap.restricted and bd.paintedRecap == bd.recap and bd.recapStyle == M.styleGen
        and bd.recapOffset == bd.offset and bd.recapCapacity == capacity then return end
    if panel.styleGen ~= M.styleGen then D.StyleBreakdownPanel(win) end
    for slot = 1, capacity do
        local row = win.bdRows[slot]
        local index = bd.offset + slot
        if index <= count then
            if not row then
                row = D.CreateRow(panel, win, "spell")
                win.bdRows[slot] = row
                D.AnchorRow(row, panel, slot + 1)
            end
            D.PaintRecap(row, bd.recap.events[index], bd.recap)
            row:Show()
        elseif row then row:Hide() end
    end
    for slot, row in pairs(win.bdRows) do if slot > capacity then row:Hide() end end
    panel.message:SetText("")
    bd.paintedRecap = not bd.recap.restricted and bd.recap or nil
    bd.recapStyle, bd.recapOffset, bd.recapCapacity = M.styleGen, bd.offset, capacity
end

function D.RecapTip(frame, source, makeRow, pad, stride)
    local recap = D.ReadRecap(source.deathRecapID)
    if not recap then return 0, S.Text("No death recap available.") end
    local count = D.Count(recap.events)
    local shown = math.min(count, M.config.tooltipRows)
    for i = 1, shown do
        local row = makeRow(frame, i, -(pad + 18 + (i - 1) * stride))
        D.PaintRecap(row, recap.events[i], recap)
        row:Show()
    end
    return shown, S.Text("Click to open the death recap.")
end
