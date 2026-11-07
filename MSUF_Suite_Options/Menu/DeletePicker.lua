local _, P = ...
local T, W, HM = P.T, P.W, P.HM
local Controller = P.Suite.Client
local WIDTH, ROW_HEIGHT, PAGE_SIZE = 320, 30, 8
local popup
local anchors = setmetatable({}, { __mode = "k" })

local function Confirm(self)
    if not self:IsVisible() or not self.ready or not self.ready() or self.count == 0 then return end
    local picks, names = {}, {}
    for index, item in ipairs(self.snapshot) do
        if self.selected[index] then
            picks[#picks + 1] = item
            if #names < 10 then names[#names + 1] = item.text end
        end
    end
    if #picks > #names then names[#names + 1] = "… +" .. (#picks - #names) end
    local spec, accept = self.spec, self.accept
    self:Hide()
    P.Confirm(spec.key, spec.question .. "\n" .. table.concat(names, "\n"), function()
        if not P.Combat() then accept(picks) end
    end)
end

local function MakeRow(self, index)
    local row = CreateFrame("Frame", nil, self)
    row:SetPoint("TOPLEFT", self, "TOPLEFT", 12, -38 - (index - 1) * ROW_HEIGHT)
    row:SetSize(WIDTH - 24, ROW_HEIGHT)
    row.toggle = W.ToggleAt(row, "", 0, 0, WIDTH - 62)
    HM.GetControlLabel(row.toggle):SetWordWrap(false)
    HM.SkipHistoryCheckpoint(row.toggle)
    row.toggle:SetScript("OnClick", function(toggle)
        local item = row.item
        if self.ready and self.ready() then
            local checked = not self.selected[item]
            self.selected[item] = checked or nil
            self.count = self.count + (checked and 1 or -1)
            self.apply:SetEnabled(self.count > 0)
        end
        toggle:SetChecked(self.selected and self.selected[item] == true)
    end)
    self.rows[index] = row
    return row
end

local function ShowPage(self, page)
    if not self.ready or not self.ready() then return end
    self.page = math.max(1, math.min(self.pages, page))
    local offset = (self.page - 1) * PAGE_SIZE
    for index = 1, math.min(PAGE_SIZE, #self.snapshot - offset) do
        local item = offset + index
        local row = self.rows[index] or MakeRow(self, index)
        -- The host computes its checkbox label hitbox on Show.
        row:Hide()
        row.item = item
        P.SetButtonText(row.toggle, self.snapshot[item].text)
        row.toggle:SetChecked(self.selected[item] == true)
        row:Show()
    end
    for index = #self.snapshot - offset + 1, #self.rows do self.rows[index]:Hide() end
    self.pager:SetShown(self.pages > 1)
    self.previous:SetEnabled(self.page > 1)
    self.next:SetEnabled(self.page < self.pages)
    self.pageNumber:SetText(self.page .. " / " .. self.pages)
end

local function Button(parent, text, width, click)
    local button = T.Button(parent, text, width, 23, { noSearch = true })
    button:SetScript("OnClick", click)
    HM.SkipHistoryCheckpoint(button)
    return button
end

local function Ensure()
    if popup then return popup end
    local self = P.MenuPopupPanel(WIDTH, 1)
    self:Hide()
    self.rows = {}
    self:EnableKeyboard(true)
    self:SetScript("OnKeyDown", function(frame, key)
        if P.Combat() then return end
        frame:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then frame:Hide() end
    end)
    self.title = P.Text(self, "", 14, -12, WIDTH - 52, T.colors.text)
    local close = Button(self, "x", 24, function() self:Hide() end)
    close:SetPoint("TOPRIGHT", self, "TOPRIGHT", -8, -8)
    self.apply = T.RoleButton(self, "", "destructive", WIDTH - 28, 26)
    self.apply:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 14, 12)
    self.apply:SetScript("OnClick", function() Confirm(self) end)
    HM.SkipHistoryCheckpoint(self.apply)
    self.pager = CreateFrame("Frame", nil, self)
    self.pager:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 14, 44)
    self.pager:SetSize(WIDTH - 28, 24)
    self.previous = Button(self.pager, "<", 40, function() ShowPage(self, self.page - 1) end)
    self.previous:SetPoint("LEFT")
    self.next = Button(self.pager, ">", 40, function() ShowPage(self, self.page + 1) end)
    self.next:SetPoint("RIGHT")
    self.pageNumber = T.Font(self.pager, "GameFontHighlightSmall", "", T.colors.text)
    self.pageNumber:SetPoint("CENTER")
    self:EnableMouseWheel(true)
    self:SetScript("OnMouseWheel", function(frame, delta)
        if delta ~= 0 then ShowPage(frame, frame.page + (delta > 0 and -1 or 1)) end
    end)
    self:HookScript("OnHide", function()
        self.anchor, self.snapshot, self.ready, self.selected, self.spec, self.accept = nil, nil, nil, nil, nil, nil
    end)
    P.Suite.Registry.AddListener(self, function(_, domain)
        if domain == "profile" then self:Hide() end
    end)
    self.SmartNavigationCloseHandler = function()
        self:Hide()
        return true
    end
    Controller.AttachControllerWindow(self)
    popup = self
    return self
end

-- Each row is a caller-owned snapshot with text and an optional initial check.
function P.OpenDeletePicker(anchor, rows, spec, accept)
    if P.Combat() then return end
    if popup and popup:IsShown() and popup.anchor == anchor then
        popup:Hide()
        return
    end
    if #rows == 0 then return end
    local self = Ensure()
    self:Hide()
    if not anchors[anchor] then
        anchors[anchor] = true
        anchor:HookScript("OnHide", function() if self.anchor == anchor then self:Hide() end end)
    end
    self.anchor, self.snapshot, self.ready = anchor, rows, P.ProfileGuard()
    self.spec, self.accept, self.selected, self.count = spec, accept, {}, 0
    self.pages = math.ceil(#rows / PAGE_SIZE)
    local page = 1
    for index, item in ipairs(rows) do
        if item.selected then
            if self.count == 0 then page = math.ceil(index / PAGE_SIZE) end
            self.selected[index], self.count = true, self.count + 1
        end
    end
    P.SetTranslatedText(self.title, spec.title)
    P.SetButtonText(self.apply, spec.action)
    self.apply:SetEnabled(self.count > 0)
    self:SetHeight(82 + math.min(PAGE_SIZE, #rows) * ROW_HEIGHT + (self.pages > 1 and 29 or 0))
    ShowPage(self, page)
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    self:SetPropagateKeyboardInput(true)
    self:Show()
    Controller.ResumeControllerWindow(self)
    Controller.RaiseControllerCursor()
    return self
end
