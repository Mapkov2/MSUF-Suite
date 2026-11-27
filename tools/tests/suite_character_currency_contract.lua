local root = assert(arg[1], "Suite root required")
local accountEvent = "ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED"
local file = root .. "/MSUF_Suite_CharacterPanel/Currency.lua"
local secret = newproxy()
local function Public(value) return not rawequal(value, secret) end

local function Header(name, depth)
    return { name = name, currencyListDepth = depth, isHeader = true, isHeaderExpanded = false }
end

local function Row(id, name, quantity, transferable, inactive)
    return { currencyID = id, name = name, quantity = quantity, isAccountTransferable = transferable,
        isTypeUnused = inactive, iconFileID = 13 }
end

local function Client(forever)
    local ns, state, shown, noCombat, calls, failRead = {}, nil, nil, true, {}, false
    local filter, ready, open, requests, rosterReads, refuse = 0, false, {}, 0, 0, nil
    local outer, inner = Header("Expansion", 0), Header("Season", 1)
    local current = Row(1, "Crests", 4, true)
    local alt = Row(2, "Badges", 0, true)
    local bound = Row(3, "Überreste", 1, false)
    local inactive = Row(4, "Coins", 0, false, true)
    local restricted = Row(5, "Secret amount", secret, secret)
    local function Rows()
        local rows = { outer }
        if open[outer] then
            rows[#rows + 1] = inner
            if open[inner] then
                rows[#rows + 1] = current
                if filter == 2 then rows[#rows + 1] = alt end
                rows[#rows + 1] = bound
                rows[#rows + 1] = inactive
                rows[#rows + 1] = restricted
            end
        end
        return rows
    end
    local function Echo()
        if state then
            assert(not ns.Currency.Invalidate(state, "CURRENCY_DISPLAY_UPDATE"), "a list write recursively invalidated its scan")
        end
    end
    local api = {
        IsAccountCharacterCurrencyDataReady = function() return ready end,
        RequestCurrencyDataForAccountCharacters = function() assert(noCombat); requests = requests + 1 end,
        GetCurrencyFilter = function() return filter end,
        SetCurrencyFilter = function(new)
            assert(noCombat)
            calls[#calls + 1] = "filter " .. new
            if new ~= refuse then filter = new end
            Echo()
        end,
        GetCurrencyListSize = function() return #Rows() end,
        GetCurrencyInfo = function(id) return id == 1 and current or nil end,
        GetCurrencyListInfo = function(index)
            if failRead and index == 3 then error("currency list changed during the walk") end
            local item = assert(Rows()[index])
            if item.isHeader then item.isHeaderExpanded = open[item] == true end
            return item
        end,
        ExpandCurrencyList = function(index, expanded)
            assert(noCombat)
            local item = assert(Rows()[index])
            assert(item.isHeader)
            calls[#calls + 1] = item.name .. (expanded and "+" or "-")
            open[item] = expanded or nil
            Echo()
        end,
        FetchCurrencyDataFromAccountCharacters = function(id)
            rosterReads = rosterReads + 1
            return {
                { characterGUID = "player", quantity = 4 },
                { characterGUID = "alt", fullCharacterName = "Other-Realm", quantity = id == 1 and 6 or 9 },
                { characterGUID = secret, quantity = 99 },
            }
        end,
    }
    local module = {
        tab = "currency",
        config = { currencyView = 1, currencyIcons = false, currencyShowInactive = true },
        context = { After = function(self, _, callback) self.timeout = callback end },
        view = { ShowCurrency = function(_, data) state, shown = data, data.groups end,
            frame = { IsShown = function() return true end }, IsMinimized = function() return false end },
    }
    local function Value(name)
        for _, group in ipairs(shown) do
            for _, row in ipairs(group.rows) do if row.label == name then return row.value end end
        end
    end
    ns.Host = { Client = { isForever = forever }, InCombat = function() return not noCombat end }
    ns.Suite = { Finish = function(fn, ...) return true, fn(...) end, Dispatch = function(fn, ...)
        local ok, first, second = pcall(fn, ...)
        if ok then return first, second end
    end }
    ns.Number = function(value) if Public(value) and type(value) == "number" then return value end end
    ns.String = function(value) if Public(value) and type(value) == "string" then return value end end
    ns.Public, ns.Text = Public, tostring
    local env = setmetatable({
        C_CurrencyInfo = api, Enum = { CurrencyFilterType = { DiscoveredOnly = 1, DiscoveredAndAllAccountTransferable = 2 } },
        canaccesstable = function() return true end, BreakUpLargeNumbers = tostring,
        CaseAccentInsensitiveParse = function(text) return (text:gsub("Ü", "u"):lower()) end,
        wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end end,
        UnitGUID = function() return "player" end,
    }, { __index = _G })
    setfenv(assert(loadfile(file)), env)("MSUF_Suite_CharacterPanel", ns)
    setfenv(assert(loadfile(root .. "/MSUF_Suite_CharacterPanel/CurrencyControls.lua")), env)("MSUF_Suite_CharacterPanel", ns)
    local currency = ns.Currency
    currency.Paint(module, false)
    assert(requests == 1 and shown[1].title == "Loading currency data")
    assert(Value("Crests") == "4" and not Value("Badges"))
    assert(filter == 0 and next(open) == nil)
    assert(table.concat(calls, "|") == "filter 1|Expansion+|Season+|Season-|Expansion-|filter 0")
    currency.Paint(module, false)
    assert(requests == 1 and #calls == 6, "pending data ignored cached rows")
    module.context.timeout()
    assert(shown[1].title == "Warband currency data unavailable" and Value("Crests") == "4")
    module.config.currencyView = 2
    currency.Paint(module, false)
    assert(shown[1].title == "Warband currency data unavailable" and not Value("Crests"))
    module.config.currencyView = 1
    currency.Reload(state)
    assert(requests == 2 and shown[1].title == "Loading currency data")
    module.tab = "reputation"
    module.context.timeout()
    assert(shown[1].title == "Loading currency data", "a currency timer repainted an inactive tab")
    module.tab = "currency"

    ready = true
    assert(currency.Invalidate(state, accountEvent))
    currency.Paint(module, false)
    assert(Value("Badges") == "0" and Value("Überreste") == "1" and Value("Secret amount") == "—")
    state.query = currency.Query("  UBER  ")
    currency.Paint(module, false)
    assert(Value("Überreste") == "1" and not Value("Crests"), "localized search needs to use the client's case and accent handling")
    state.query = ""
    module.config.currencyView = 2
    currency.Paint(module, false)
    assert(Value("Crests") == "10" and Value("Badges") == "9" and not Value("Überreste"))
    assert(rosterReads == 2)
    module.config.currencySort = 3
    module.config.currencyFavorites = "2"
    currency.Paint(module, false)
    assert(rosterReads == 2 and shown[1].title == "Favorites" and shown[1].rows[1].id == 2)
    state.query = "crest"
    currency.Paint(module, false)
    assert(Value("Crests") == "10" and not Value("Badges"))
    state.query = ""

    module.config.currencyView = 3
    module.config.currencyShowInactive = false
    currency.Paint(module, false)
    assert(Value("Crests") == "4" and not Value("Coins") and not Value("Badges"))
    module.config.currencyHideZero, module.config.currencyShowInactive = true, true
    currency.Paint(module, false)
    assert(not Value("Coins"))

    current.quantity = 8
    assert(currency.Invalidate(state, "CURRENCY_DISPLAY_UPDATE"))
    noCombat = false
    local before = #calls
    currency.Paint(module, true)
    assert(#calls == before and Value("Crests") == "4")
    noCombat = true
    currency.Paint(module, false)
    assert(Value("Crests") == "8" and #calls == before, "an anonymous currency update rescanned the native list")

    assert(currency.Invalidate(state, "CURRENCY_DISPLAY_UPDATE", 1))
    open[outer], failRead = true, true
    currency.Paint(module, false)
    assert(filter == 0 and open[outer] and not open[inner], "failed scan left a native mutation behind")
    failRead = false
    currency.Paint(module, false)
    assert(Value("Crests") == "8" and filter == 0 and open[outer] and not open[inner])

    module.config.currencyView, refuse = 2, 2
    currency.Reload(state)
    assert(shown[1].title == "Warband currency data unavailable" and not Value("Crests") and filter == 0)
    before = #calls
    currency.Invalidate(state, "CURRENCY_DISPLAY_UPDATE")
    currency.Paint(module, false)
    assert(#calls == before, "a refused account filter was retried by its anonymous echo")
    refuse = nil
    currency.Invalidate(state, "ADDON_RESTRICTION_STATE_CHANGED")
    currency.Paint(module, false)
    assert(Value("Crests") == "14" and filter == 0, "an expired restriction kept the account list unavailable")
end

Client(false)
Client(true)
print("character currency contract passed on Retail and Forever")
