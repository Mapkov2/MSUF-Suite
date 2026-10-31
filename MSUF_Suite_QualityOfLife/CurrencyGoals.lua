local _, P = ...
local NS, S = P.NS, P.Suite
local M = { states = {} }
local function Store()
    local data = S.CharacterData("currencyGoals")
    if not data then return end
    if type(data.goals) ~= "table" then data.goals = {} end
    local count = 0
    for id, target in pairs(data.goals) do
        if not S.Finite(id) or id < 1 or id % 1 ~= 0 or not S.Finite(target) or target < 1
            or target > 100000000 or count >= 50 then data.goals[id] = nil else count = count + 1 end
    end
    return data.goals
end
local function Info(id)
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    if S.Public(info) and type(info) == "table" and S.PublicText(info.name) and S.Finite(info.quantity) then return info end
end
local function Notice(id, kind, name, detail)
    local title = S.Text("Currency: %s"):format(name)
    S.Print(S.Text("%s — %s"):format(title, detail))
    S.Notifications.Push("currency:" .. id .. ":" .. kind, title, detail, "currencyGoals")
end
local function CapState(info)
    if not S.Finite(info.maxQuantity) then return end
    if info.maxQuantity <= 0 then return false end
    local lifetime = info.useTotalEarnedForMaxQty
    if not S.Public(lifetime) then return end
    local amount = info.quantity
    if lifetime == true then amount = info.totalEarned end
    if S.Finite(amount) then return amount >= info.maxQuantity * M.config.capPercent / 100 end
end
local function Update()
    if not M.active or NS.InCombat() then return end
    for id, target in pairs(Store() or {}) do
        local info = Info(id)
        if info then
            local state = M.states[id] or {}
            local reached = info.quantity >= target
            if M.config.notifyGoal and reached and state.reached == false then
                Notice(id, "goal", info.name, S.Text("Goal reached: %d / %d"):format(info.quantity, target))
            end
            local capped, weekly = CapState(info), nil
            if S.Finite(info.maxWeeklyQuantity) and info.maxWeeklyQuantity > 0 and S.Finite(info.quantityEarnedThisWeek) then
                weekly = info.quantityEarnedThisWeek >= info.maxWeeklyQuantity * M.config.capPercent / 100
            elseif S.Finite(info.maxWeeklyQuantity) and info.maxWeeklyQuantity <= 0 then
                weekly = false
            end
            if M.config.notifyCap and ((capped and state.capped == false) or (weekly and state.weekly == false)) then
                Notice(id, "cap", info.name, S.Text("At least %d%% of a currency limit has been reached."):format(M.config.capPercent))
            end
            state.reached, state.capped, state.weekly = reached, capped, weekly
            M.states[id] = state
        end
    end
    S.ToolListWindow.Refresh(M)
end
local function Rows()
    local rows = {}
    for id, target in pairs(Store() or {}) do
        local info = Info(id)
        local name = info and info.name or S.Text("Currency %d"):format(id)
        local detail = info and S.Text("Current: %d · Goal: %d · Remaining: %d"):format(info.quantity, target, math.max(0, target - info.quantity))
            or S.Text("This currency is currently unavailable.")
        if info and S.Finite(info.maxQuantity) and info.maxQuantity > 0 then
            detail = detail .. "\n" .. S.Text("Total limit: %d"):format(info.maxQuantity)
            if S.Public(info.useTotalEarnedForMaxQty) and info.useTotalEarnedForMaxQty == true and S.Finite(info.totalEarned) then
                detail = detail .. "\n" .. S.Text("Total earned: %d / %d"):format(info.totalEarned, info.maxQuantity)
            end
        end
        if info and S.Finite(info.maxWeeklyQuantity) and info.maxWeeklyQuantity > 0 and S.Finite(info.quantityEarnedThisWeek) then
            detail = detail .. "\n" .. S.Text("This week: %d / %d"):format(info.quantityEarnedThisWeek, info.maxWeeklyQuantity)
        end
        rows[#rows + 1] = { key = id, label = name, detail = detail, target = target }
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    return rows
end
local function Target(_, row)
    if not row then return end
    local id = row.key
    local initial = (Store() or {})[id]
    S.ToolListWindow.Edit(M, { title = "Currency goal", label = row.label, text = tostring(row.target or 1), maxBytes = 9,
        onSave = function(_, text)
            local target = tonumber(text)
            if not S.Finite(target) or target < 1 or target > 100000000 or target % 1 ~= 0 then
                return false, "Enter a whole number between 1 and 100000000."
            end
            local goals = Store()
            if not goals then return false, "Character data is not available yet." end
            if goals[id] ~= initial then return false, S.Text("Settings changed. Review again before applying.") end
            local count = 0
            for _ in pairs(goals) do count = count + 1 end
            if not goals[id] and count >= 50 then return false, "Keep at most 50 currency goals." end
            goals[id] = target
            M.states[id] = nil
            Update()
            M:Open()
            return true
        end })
end
local function Available()
    local rows, seen = {}, {}
    local count = C_CurrencyInfo.GetCurrencyListSize()
    if not S.Finite(count) then return rows end
    for i = 1, math.min(2000, count) do
        local link = C_CurrencyInfo.GetCurrencyListLink(i)
        local id = S.PublicText(link) and tonumber(link:match("currency:(%d+)"))
        local info = id and Info(id)
        if info and not seen[id] then
            seen[id] = true
            rows[#rows + 1] = { key = id, label = info.name, detail = S.Text("Current: %d"):format(info.quantity) }
        end
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    return rows
end
local function Add()
    M.available = Available()
    S.ToolListWindow.Open(M, { title = "Choose a currency", help = "Expand categories in Blizzard's Currency tab to include more currencies.",
        rows = function() return M.available end, empty = "No currencies are visible in the Currency tab.",
        actions = { { label = "Set goal", enabled = function(_, row) return row ~= nil end, run = Target },
            { label = "Back to goals", run = function() M:Open() end } } })
end
function M:Open()
    return S.ToolListWindow.Open(self, { title = "Currency goals",
        help = "Goals belong to this character. Notifications trigger when a goal or limit is crossed.",
        rows = Rows, empty = "Add a currency and choose the amount you want to save.", actions = {
            { label = "Add currency", run = Add }, { label = "Change goal", enabled = function(_, row) return row ~= nil end, run = Target },
            { label = "Remove goal", enabled = function(_, row) return row ~= nil end,
                run = function(_, row)
                    Store()[row.key] = nil
                    M.states[row.key] = nil
                    S.ToolListWindow.Refresh(M)
                end },
        } })
end
local function Changed() M.refresh:Request() end
function M:Enable()
    self.refresh = self.context:Coalesce(.2, Update)
    for _, event in ipairs({ "CURRENCY_DISPLAY_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
        self.context:Event(event, Changed, { inCombat = true })
    end
    self:Refresh()
end
function M:Refresh() wipe(self.states) Update() end
function M:Disable() S.ToolListWindow.Close(self) wipe(self.states) end
S.Install("currencyGoals", M)
