local _, NS = ...
local Currency = {}
NS.Currency = Currency

local API = C_CurrencyInfo
local Suite, Host = NS.Suite, NS.Host
local Number, String, Public, Text = NS.Number, NS.String, NS.Public, NS.Text
local ALL, WARBAND, CHARACTER = 1, 2, 3
local CATEGORY, NAME, QUANTITY = 1, 2, 3
local ACCOUNT_EVENT = "ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED"
local UPDATE_EVENT, RESTRICTION_EVENT = "CURRENCY_DISPLAY_UPDATE", "ADDON_RESTRICTION_STATE_CHANGED"
Currency.Events = { UPDATE_EVENT, ACCOUNT_EVENT, "CURRENCY_TRANSFER_SUCCESS", RESTRICTION_EVENT }

local function Data(value)
    if Public(value) and type(value) == "table" and canaccesstable(value) then return value end
end

local function Yes(value)
    return Public(value) and value == true
end

local function FormatAmount(value)
    return value and BreakUpLargeNumbers(value) or "—"
end

local function Walk(tx, snapshot)
    if tx.previous ~= tx.target then
        Suite.Dispatch(API.SetCurrencyFilter, tx.target)
        if Number(API.GetCurrencyFilter()) ~= tx.target then tx.refused = true return end
    end
    local index, count = 1, Number(API.GetCurrencyListSize()) or 0
    local parents, group = {}, nil
    while index <= count do
        local info = Data(API.GetCurrencyListInfo(index))
        local name = info and String(info.name)
        if name and Yes(info.isHeader) then
            local depth = math.max(0, Number(info.currencyListDepth) or 0)
            local parent = depth > 0 and parents[depth - 1]
            group = { title = name, parent = parent, depth = depth, key = parent and (parent.key .. "\031" .. name) or name }
            parents[depth] = group
            for childDepth = depth + 1, #parents do parents[childDepth] = nil end
            if Public(info.isHeaderExpanded) and info.isHeaderExpanded == false then
                tx[#tx + 1] = index
                API.ExpandCurrencyList(index, true)
                count = Number(API.GetCurrencyListSize()) or count
            end
        elseif name then
            local id = Number(info.currencyID)
            if id and id > 0 and not snapshot.ids[id] then
                snapshot.ids[id] = true
                snapshot.rows[#snapshot.rows + 1] = { id = id, name = name, group = group,
                    icon = Number(info.iconFileID), quantity = Number(info.quantity), inactive = Yes(info.isTypeUnused),
                    cap = Number(info.maxQuantity), earnedCap = Yes(info.useTotalEarnedForMaxQty),
                    transferable = Yes(info.isAccountTransferable) and not Yes(info.isAccountWide) }
            end
        end
        index = index + 1
    end
    return true
end

local function Read(state, target)
    local previous = Number(API.GetCurrencyFilter())
    if not previous or not target or state.scanning or Host.InCombat() then return end
    if previous ~= target and state.refused[target] then return end
    local snapshot = { rows = {}, ids = {} }
    local tx = { previous = previous, target = target }
    state.scanning = true
    local finished, read = Suite.Dispatch(Suite.Finish, Walk, tx, snapshot)
    for i = #tx, 1, -1 do Suite.Dispatch(API.ExpandCurrencyList, tx[i], false) end
    if Number(API.GetCurrencyFilter()) ~= previous then Suite.Dispatch(API.SetCurrencyFilter, previous) end
    state.scanning = nil
    if tx.refused then state.refused[target] = true end
    if finished and read then return snapshot end
end

local function RequestAccount(state)
    local request, module = {}, state.module
    state.requested, state.waiting = request, true
    Suite.Dispatch(API.RequestCurrencyDataForAccountCharacters)
    module.context:After(8, function()
        if state.requested ~= request or module.currencies ~= state or not state.waiting then return end
        state.waiting = nil
        if NS.CurrencyControls.Current(state) then Currency.Paint(module, false) end
    end)
end

local function RefreshQuantities(snapshot)
    if not snapshot then return end
    for _, entry in ipairs(snapshot.rows) do
        local info = Data(API.GetCurrencyInfo(entry.id))
        if info then entry.quantity = Number(info.quantity) end
        entry.other = nil
    end
end

local function Refresh(state, mode)
    local ready = Yes(API.IsAccountCharacterCurrencyDataReady())
    local wantsAccount = mode ~= CHARACTER
    if ready then state.waiting = nil
    elseif wantsAccount and not state.requested then RequestAccount(state) end
    local filters = Enum.CurrencyFilterType
    if mode == CHARACTER or not ready then
        if not state.character then state.character = Read(state, filters.DiscoveredOnly) end
    elseif not state.account then
        state.account = Read(state, filters.DiscoveredAndAllAccountTransferable)
    end
    if wantsAccount and not state.account and not state.character then state.character = Read(state, filters.DiscoveredOnly) end
    if state.quantitiesDirty then
        RefreshQuantities(state.account)
        RefreshQuantities(state.character)
        state.quantitiesDirty = nil
    end
    state.loading = wantsAccount and state.waiting == true
    state.unavailable = wantsAccount and not state.loading and not state.account
    if mode == CHARACTER then return state.character end
    return state.account or (mode == ALL and state.character or nil)
end

function Currency.Invalidate(state, event, id)
    if not state or state.scanning then return false end
    if event == UPDATE_EVENT and not Number(id) then
        -- An unqualified update can be a filter/expansion echo. Refresh the
        -- known balances without changing the native list a second time.
        state.quantitiesDirty = true
        return true
    end
    state.account = nil
    if event ~= ACCOUNT_EVENT then state.character = nil end
    if event == RESTRICTION_EVENT then wipe(state.refused) end
    if event == "CURRENCY_TRANSFER_SUCCESS" then state.requested = nil end
    return true
end

function Currency.Reload(state)
    state.account, state.character, state.requested, state.waiting = nil, nil, nil, nil
    wipe(state.refused)
    Currency.Paint(state.module, false, true)
end

local function Roster(id, visitor)
    local current = String(UnitGUID("player"))
    local data = current and Data(API.FetchCurrencyDataFromAccountCharacters(id))
    if not data then return 0 end
    local total = 0
    for i = 1, #data do
        local entry = Data(data[i])
        local guid = entry and String(entry.characterGUID)
        local amount = guid and guid ~= current and Number(entry.quantity)
        if amount and amount > 0 then
            total = total + amount
            if visitor then visitor(String(entry.fullCharacterName) or String(entry.characterName), amount) end
        end
    end
    return total
end

local function Tooltip(tip, row)
    tip:SetCurrencyByID(row.id)
    if row.warband then tip:AddDoubleLine(Text("Warband"), row.value) end
    if row.action.transferable and Yes(API.IsAccountCharacterCurrencyDataReady()) then
        Roster(row.id, function(name, amount)
            if name then tip:AddDoubleLine(name, FormatAmount(amount)) end
        end)
    end
end

local Fold = CaseAccentInsensitiveParse or strlower or string.lower

function Currency.Query(text)
    return Fold(text:match("^%s*(.-)%s*$"))
end

local function Less(a, b)
    if a.name == b.name then return a.id < b.id end
    return a.name < b.name
end

local function More(a, b)
    if a.amount == b.amount then return Less(a, b) end
    return a.amount > b.amount
end

local function AddGroup(groups, seen, state, group)
    local existing = seen[group]
    if existing then return existing end
    if group.parent then AddGroup(groups, seen, state, group.parent) end
    local parent = seen[group.parent]
    local hidden = parent and (parent.collapsed or parent.hidden)
    local collapsed = state.query == "" and state.closed[group.key]
    local target = {
        title = group.title, depth = group.depth, rows = {}, hidden = hidden, collapsed = collapsed,
        action = state.query == "" and { group = group.key } or nil,
    }
    seen[group] = target
    if not hidden then groups[#groups + 1] = target end
    return target
end

local function Matches(entry, name, query)
    while entry do
        if Fold(name):find(query, 1, true) then return true end
        entry = entry.group or entry.parent
        name = entry and entry.title
    end
    return false
end

local function Display(entry, mode, config, amount)
    local value = FormatAmount(amount)
    if config.currencyCaps and mode ~= WARBAND and amount and entry.cap and entry.cap > 0 and not entry.earnedCap then
        value = value .. " / " .. FormatAmount(entry.cap)
    end
    return value
end

local function Project(state, config, snapshot)
    local groups, seen = {}, {}
    local all = { title = Text("Currencies"), key = "currencies" }
    local pinned = { title = Text("Favorites"), key = "\031favorites" }
    local sort = config.currencySort or CATEGORY
    local favorites = "," .. (config.currencyFavorites or "") .. ","
    if snapshot then
        for _, entry in ipairs(snapshot.rows) do
            local name = entry.name
            if (config.currencyView ~= WARBAND or entry.transferable)
                and (config.currencyShowInactive or not entry.inactive) and Matches(entry, name, state.query) then
                local amount = entry.quantity
                if config.currencyView == WARBAND and state.account == snapshot then
                    entry.other = entry.other or Roster(entry.id)
                    if amount then amount = amount + entry.other end
                end
                if not config.currencyHideZero or amount ~= 0 then
                    local favorite = favorites:find("," .. entry.id .. ",", 1, true)
                    local group = favorite and pinned or sort == CATEGORY and entry.group or all
                    local target = AddGroup(groups, seen, state, group or all)
                    if not (target.collapsed or target.hidden) then
                        local icon = config.currencyIcons ~= false and entry.icon
                        if icon and icon > 0 then name = ("|T%d:13:13|t %s"):format(icon, name) end
                        local row = { label = name, value = Display(entry, config.currencyView, config, amount),
                            action = entry, tooltip = Tooltip, name = entry.name, amount = amount or -1, id = entry.id,
                            warband = config.currencyView == WARBAND }
                        row.tooltipArgument = row
                        target.rows[#target.rows + 1] = row
                    end
                end
            end
        end
    end
    local favoriteGroup = seen[pinned]
    if favoriteGroup then
        for i, group in ipairs(groups) do if group == favoriteGroup then table.remove(groups, i) break end end
        table.insert(groups, 1, favoriteGroup)
    end
    if sort ~= CATEGORY then
        for _, group in ipairs(groups) do table.sort(group.rows, sort == QUANTITY and More or Less) end
    end
    if state.loading then table.insert(groups, 1, { title = Text("Loading currency data"), rows = {} }) end
    if state.unavailable then table.insert(groups, 1, { title = Text("Warband currency data unavailable"), rows = {} }) end
    if #groups == 0 then groups[1] = { title = snapshot and Text("No results") or Text("No data available"), rows = {} } end
    return groups
end

function Currency.Paint(module, combat, reset)
    local state = module.currencies
    if not state then
        state = { query = "", closed = {}, refused = {}, module = module }
        module.currencies = state
    end
    if not combat then
        if module.config.currencySearch == false then state.query = "" end
        local mode = module.config.currencyView or ALL
        reset = reset or mode ~= state.mode or state.sort ~= module.config.currencySort
        state.mode, state.sort = mode, module.config.currencySort
        local snapshot = Refresh(state, mode)
        state.groups = Project(state, module.config, snapshot)
    elseif not state.groups then
        state.groups = { { title = Text("Available after combat"), rows = {} } }
    end
    module.view:ShowCurrency(state, combat, reset)
end

function Currency.Click(state, action, button)
    if not state or Host.InCombat() then return end
    if action.group then
        state.closed[action.group] = not state.closed[action.group] or nil
        Currency.Paint(state.module, false)
    else
        local link = IsModifiedClick("CHATLINK") and String(API.GetCurrencyLink(action.id))
        if link and HandleModifiedItemClick(link) then return end
        NS.CurrencyControls.RowMenu(state, action, button)
    end
end
