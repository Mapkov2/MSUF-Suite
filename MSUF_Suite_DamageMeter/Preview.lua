local _, P = ...
local S, D = P.Suite, P.DamageMeter
local M = D.M
local CLASS = { "WARRIOR", "MAGE", "PALADIN", "PRIEST", "DRUID" }
local SPEC = { 132355, 135932, 135920, 135940, 136096 }
local sample = { maxAmount = 125000, totalAmount = 440000 }
local sources = {}
for i = 1, #CLASS do
    sources[i] = { name = S.Text("Player %d"):format(i), classFilename = CLASS[i],
        specIconID = SPEC[i], totalAmount = 125000 - (i - 1) * 18000,
        amountPerSecond = 12500 - (i - 1) * 1800, deathTimeSeconds = 95 - i,
        percent = 100 - (i - 1) * 16, points = 125000 - (i - 1) * 18000, rank = i }
end
local settings = {}
-- When disabled, compile the same authoritative configuration into the
-- ordinary style cache. This never enables the module or swaps its state.
local function Style()
    if M.active then return end
    local c, changed = S.Config("damageMeter"), M.style == nil
    for key in pairs(S.catalog.damageMeter.rules) do
        if settings[key] ~= c[key] then settings[key], changed = c[key], true end
    end
    if M.style and c.iconSkin ~= "CUSTOM" then
        changed = changed or M.style.iconSkin ~= P.NS.HostBridge.IconSkinLook(c.iconSkin)
    end
    if changed then
        M.config = c
        M.styleGen = M.styleGen + 1
        D.BuildStyle()
    end
end

local function Passive(frame, scripts)
    for script in pairs(scripts) do frame:SetScript(script, nil) end
end
local function Create(parent, index)
    local win = D.NewWindow(parent, index)
    win.menuPreview = true
    Passive(win.header, D.headerScripts)
    Passive(win.body, D.bodyScripts)
    Passive(win.grip, D.gripScripts)
    win.frame:SetScript("OnEnter", nil)
    win.frame:SetScript("OnLeave", nil)
    win.frame:SetScript("OnSizeChanged", nil)
    win.frame:SetClampedToScreen(false)
    win.frame:SetMovable(false)
    win.frame:SetResizable(false)
    for _, button in pairs(win.buttons) do
        button:SetScript("OnClick", nil)
        button:SetScript("OnEnter", nil)
        button:SetScript("OnLeave", nil)
    end
    for i = 1, #CLASS do
        local row = D.CreateRow(win.body, win, "list")
        Passive(row, D.listScripts)
        win.rows[i] = row
    end
    parent.damageMeterMenuPreview = win
    return win
end

function S.DamageMeterDrawMenuPreview(parent, index)
    Style()
    local win = parent.damageMeterMenuPreview or Create(parent, index)
    if win.index ~= index or win.styleGen ~= M.styleGen then
        win.index = index
        local c, keys = M.config, D.KEYS[index]
        win.meterType = c[keys.Type] - 1
        -- Sample headings never resolve live sessions, threat targets or APIs.
        win.overall = c[keys.Session] == D.SESSION.OVERALL
        D.StyleWindowLayout(win)
        win.frame:ClearAllPoints()
        win.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, c.headerOutside and -c.headerHeight or 0)
        if win.meterType == D.THREAT then
            win.title:SetText(D.TypeName(win.meterType))
            win.buttons.session.label:SetText(S.BlizzardText("DAMAGE_METER_CURRENT_SESSION_SHORT", "C"))
        else D.UpdateTitle(win) end
        D.SetTimerText(win, c.combatTime and c.headerTimer and not win.overall and 95 or nil)
        for i, row in ipairs(win.rows) do
            D.AnchorRow(row, win.body, i)
            D.StyleRow(row)
            D.PaintSource(row, sources[i], i, sample, win)
            row:SetShown(i <= win.capacity)
        end
        win.status:Hide()
        win.frame:Show()
    end
    return win
end
