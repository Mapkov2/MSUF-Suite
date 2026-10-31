local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end
local M = { rows = {}, entries = {} }
local LIMIT = 128
local function Records()
    local root = NS.RootDB
    if type(root) ~= "table" then return end
    if type(root.suiteMailRecipients) ~= "table" then root.suiteMailRecipients = {} end
    return root.suiteMailRecipients
end
local function Record()
    local records = Records()
    local guid = S.PublicText(UnitGUID("player"))
    local name, realm = UnitFullName("player")
    realm = S.PublicText(realm) or S.PublicText(GetNormalizedRealmName())
    local level, now = UnitLevel("player"), GetServerTime()
    local region = S.PublicText(GetCurrentRegionName())
    if not records or not guid or not region or not S.PublicText(name) or not realm or not S.Finite(level) or not S.Finite(now) then return end
    local row = records[guid]
    if type(row) ~= "table" then
        -- A full list gives up the character visited longest ago.
        local count, oldest, oldestAt = 0, nil, nil
        for key, record in pairs(records) do
            count = count + 1
            local at = type(record) == "table" and S.Finite(record.visited) and record.visited or -math.huge
            if not oldestAt or at < oldestAt then oldest, oldestAt = key, at end
        end
        if count >= LIMIT then records[oldest] = nil end
        row = {}
        records[guid] = row
    end
    row.name, row.realm, row.level, row.visited, row.region = name, realm, level, now, region
end
local function Less(a, b)
    local sort = M.config.sort
    if sort == 2 and a.record.level ~= b.record.level then return a.record.level > b.record.level end
    if sort == 3 and a.record.visited ~= b.record.visited then return a.record.visited > b.record.visited end
    return a.address < b.address
end
local Draw
local function Pick(row, button)
    if not M.active or NS.InCombat() or not M.frame:IsVisible() then return end
    local records, entry = Records(), row.entry
    if not entry or records[entry.guid] ~= entry.record then return end
    if button == "RightButton" then
        entry.record.hidden = not entry.record.hidden or nil
        Draw()
    elseif button == "LeftButton" then
        -- Address entry is the only native write, directly from this hardware click.
        SendMailNameEditBox:SetText(entry.address)
        SendMailNameEditBox:ClearFocus()
    end
end
local function Row(index)
    local row = M.rows[index]
    if row then return row end
    row = S.CreateFrame("Button", nil, M.frame)
    row:SetSize(214, 22)
    row:SetPoint("TOPLEFT", 8, -86 - (index - 1) * 24)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local text = S.CreateFontString(row, nil, "OVERLAY")
    text:SetAllPoints(row)
    S.SetFont(text, nil, 11, "")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    row.label = text
    row:SetScript("OnClick", Pick)
    row:SetScript("OnEnter", function(button)
        if not button.entry or NS.Safety.IsForbidden(GameTooltip) then return end
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(button.entry.address)
        GameTooltip:AddLine(S.Text("Right-click to hide or restore."), .8, .8, .8)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(button)
        if not NS.Safety.IsForbidden(GameTooltip) and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    end)
    M.rows[index] = row
    return row
end
local function Page(delta)
    if not M.active then return end
    M.offset = math.max(0, (M.offset or 0) + delta * M.config.rows)
    Draw()
end
local function Build()
    if M.frame or not _G.SendMailFrame then return end
    local frame = S.CreateFrame("Frame", nil, SendMailFrame)
    frame:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 8, -26)
    frame:SetWidth(230)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) Page(delta > 0 and -1 or 1) end)
    local back = S.CreateTexture(frame, nil, "BACKGROUND")
    back:SetAllPoints(frame)
    back:SetColorTexture(.04, .05, .07, .96)
    M.back = back
    local title = S.CreateFontString(frame, nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 8, -8)
    S.SetFont(title, nil, 12, "")
    title:SetText(S.Text("Mail recipients"))
    M.frame = frame
    local search = S.CreateFrame("EditBox", nil, frame, "InputBoxInstructionsTemplate")
    search.Instructions:SetText(S.Text("Search"))
    search:SetPoint("TOPLEFT", 14, -32)
    search:SetSize(202, 22)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    search:SetScript("OnEscapePressed", function(box)
        box:SetText("")
        box:ClearFocus()
    end)
    search:SetScript("OnTextChanged", function(box)
        M.query = (S.PublicText(box:GetText()) or ""):lower()
        M.offset = 0
        if M.active then M.job:Request() end
    end)
    local hidden = S.CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    hidden:SetSize(22, 22)
    hidden:SetPoint("TOPLEFT", 8, -59)
    local caption = S.CreateFontString(hidden, nil, "OVERLAY")
    caption:SetPoint("LEFT", hidden, "RIGHT", 2, 0)
    S.SetFont(caption, nil, 11, "")
    caption:SetText(S.Text("Show hidden recipients"))
    hidden:SetScript("OnClick", function(button)
        if not M.active then return end
        if NS.InCombat() then button:SetChecked(M.config.showHidden)
        else
            S.Set("mailRecipients", "showHidden", button:GetChecked() == true)
        end
    end)
    M.hidden = hidden
    local footer = S.CreateFontString(frame, nil, "OVERLAY")
    footer:SetPoint("BOTTOM", 0, 11)
    S.SetFont(footer, nil, 10, "")
    M.footer, M.search = footer, search
    for i = 1, 2 do
        local button = S.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(30, 22)
        button:SetPoint(i == 1 and "BOTTOMLEFT" or "BOTTOMRIGHT", i == 1 and 8 or -8, 6)
        button:SetText(i == 1 and "<" or ">")
        button:SetScript("OnClick", function() Page(i == 1 and -1 or 1) end)
        if i == 1 then M.previous = button
        else
            M.next = button
        end
    end
    SendMailFrame:HookScript("OnShow", function() if M.active then M.job:Request() end end)
end
-- Mail reaches the current realm and the realms connected to it.
local function MailRealms()
    local realms = {}
    local own = S.PublicText(GetNormalizedRealmName())
    if own then realms[own] = true end
    local connected = C_AutoComplete.GetAutoCompleteRealms()
    if S.Public(connected) and type(connected) == "table" then
        for i = 1, #connected do
            local realm = S.PublicText(connected[i])
            if realm then realms[realm] = true end
        end
    end
    return realms
end
local function Collect()
    local entries, records, realms = M.entries, Records(), MailRealms()
    for i = #entries, 1, -1 do entries[i] = nil end
    local current = S.PublicText(UnitGUID("player"))
    local region = S.PublicText(GetCurrentRegionName())
    for guid, record in pairs(records or {}) do
        if #entries < LIMIT and type(record) == "table" and region and record.region == region
            and guid ~= current and type(guid) == "string"
            and S.PublicText(record.name) and S.PublicText(record.realm) and realms[record.realm] and S.Finite(record.level)
            and S.Finite(record.visited) and record.level >= M.config.minimumLevel
            and (M.config.showHidden or not record.hidden) then
            local address = record.name .. "-" .. record.realm
            if not M.query or address:lower():find(M.query, 1, true) then
                entries[#entries + 1] = { guid = guid, record = record, address = address }
            end
        end
    end
    table.sort(entries, Less)
    return entries
end
Draw = function()
    Build()
    if not M.frame then return end
    S.QoLColor(M.back, S.QoLStyle(M.config).background, .96)
    for i = 1, #M.rows do
        M.rows[i]:Hide()
        M.rows[i].entry = nil
    end
    if not M.active or not SendMailFrame:IsVisible() then
        M.frame:Hide()
        return
    end
    local entries, count = Collect(), M.config.rows
    local lastPage = math.floor(math.max(0, #entries - 1) / count) * count
    M.offset = math.min(M.offset or 0, lastPage)
    for i = 1, math.min(#entries - M.offset, count) do
        local row, entry = Row(i), entries[M.offset + i]
        row.entry = entry
        row.label:SetText(entry.address)
        row:SetAlpha(entry.record.hidden and .4 or 1)
        row:Show()
    end
    if #entries == 0 then
        local row = Row(1)
        row.label:SetText(S.Text("No matching recipients. Visit your other characters with this helper enabled."))
        row:Show()
    end
    M.hidden:SetChecked(M.config.showHidden)
    M.hidden:SetEnabled(not NS.InCombat())
    M.footer:SetText(S.Text("%d-%d / %d"):format(#entries > 0 and M.offset + 1 or 0,
        math.min(M.offset + count, #entries), #entries))
    M.previous:SetEnabled(M.offset > 0)
    M.next:SetEnabled(M.offset < lastPage)
    M.frame:SetHeight(114 + math.max(1, math.min(#entries, count)) * 24)
    M.frame:Show()
end
local function Changed(_, event)
    if event == "MAIL_CLOSED" then if M.frame then M.frame:Hide() end
    return end
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LEVEL_UP" then Record() end
    M.job:Request()
end
function M:Enable()
    self.job = self.context:Coalesce(0, Draw)
    self.context:Event("MAIL_SHOW", Changed)
    self.context:Event("MAIL_CLOSED", Changed)
    self.context:Event("PLAYER_ENTERING_WORLD", Changed)
    self.context:Event("PLAYER_LEVEL_UP", Changed)
    Record()
    self:Refresh()
end
function M:Refresh()
    self.offset = 0
    self.job:Request()
end
function M:Disable()
    if self.frame then self.frame:Hide() end
end
S.Install("mailRecipients", M)
