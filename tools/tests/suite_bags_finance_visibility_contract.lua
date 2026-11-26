local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local function Check(client)
    local W = H.New(root, {client = client, config = {currencyIDs = "42", showSessionGold = true, goldPeriod = 3, showGoldHistory = true}})
    W.sizes[0] = 12
    local quantity, currencyReads = 100, 0
    C_CurrencyInfo.GetCurrencyInfo = function(id)
        if id == 42 then
            currencyReads = currencyReads + 1
            return {name = "Test currency", quantity = quantity}
        end
    end
    local activeTicks = {}
    function W.S.ScheduleDataTick(key, delay, callback)
        local tick = {}
        function tick:Cancel()
            if activeTicks[key] == self then activeTicks[key] = nil end
        end
        activeTicks[key] = tick
        C_Timer.After(math.max(.05, delay), function()
            if activeTicks[key] ~= tick then return end
            activeTicks[key] = nil
            callback()
        end)
        return tick
    end
    W.Apply()
    local finance = W.P.BagFinance
    local function CurrencyWatching() return finance.events:IsEventRegistered("CURRENCY_DISPLAY_UPDATE") end
    assert(not CurrencyWatching(), "currency event subscribed before first open")
    assert(not next(activeTicks), "hidden Today footer scheduled its own clock")
    W.OpenBags()
    W.Settle()
    assert(CurrencyWatching() and next(activeTicks), "open bag footer did not watch its values")
    currencyReads = 0
    W.Fire("PLAYER_MONEY")
    W.Settle()
    assert(currencyReads == 0, "a gold update reread the footer currencies")
    quantity = 120
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Settle()
    assert(finance.currencies[1].quantity == 120, "zoning missed a visible currency update")
    local style = W.M.windows[W.CF]
    local writes = 0
    for _, label in ipairs({style.goldLabel, style.dailyGoldLabel}) do
        local set = label.SetText
        label.SetText = function(widget, value)
            writes = writes + 1
            return set(widget, value)
        end
    end
    W.CloseBags()
    assert(not CurrencyWatching() and not next(activeTicks), "a hidden footer kept its listeners")
    local initial = W.money
    W.money = initial + 1000
    W.Fire("PLAYER_MONEY")
    W.money = initial + 300
    W.Fire("PLAYER_MONEY")
    W.Advance(.1)
    assert(writes == 0, "hidden gold labels written " .. writes .. " times")
    local guid = UnitGUID("player")
    local day = W.NS.RootDB.suiteBagGold.characters[guid].days[1]
    assert(day.earned == 1000 and day.spent == 700, "closed journal collapsed separate transactions")
    finance.Show()
    assert(CurrencyWatching(), "visible history window missed its currency event")
    quantity = 125
    W.Fire("CURRENCY_DISPLAY_UPDATE")
    W.Settle()
    assert(finance.labels[1].right:GetText() == "125", "standalone history did not refresh currency")
    W.EnterCombat()
    quantity = 173
    W.Fire("CURRENCY_DISPLAY_UPDATE")
    W.Settle()
    assert(CurrencyWatching() and finance.labels[1].right:GetText() == "173", "visible history froze in combat")
    finance.window:Hide()
    assert(not CurrencyWatching() and not finance.events:IsEventRegistered("PLAYER_MONEY"), "closed combat history kept events")
    W.money = initial + 500
    W.Fire("PLAYER_MONEY")
    finance.Show()
    assert(CurrencyWatching() and day.earned == 1200 and day.spent == 700, "opening standalone history in combat missed catchup")
    finance.window:Hide()
    W.LeaveCombat()
    W.Settle()
    assert(not CurrencyWatching() and writes == 0 and finance.events:IsEventRegistered("PLAYER_MONEY"), "closed wallets woke display work at combat end")
    W.OpenBags()
    W.Settle()
    assert(writes > 0 and style.goldLabel:GetText() == "Session +" .. W.S.MoneyText(500), "session footer did not catch up on show")
    assert(style.dailyGoldLabel:GetText() == "Today +" .. W.S.MoneyText(500), "Today footer did not catch up on show")
    writes = 0
    W.CloseBags()
    W.OpenBags()
    W.Settle()
    assert(writes == 0, "unchanged gold amounts were written on reopen")
    finance.Show()
    -- WoW sends effective visibility edges to children of a hidden ancestor.
    -- The harness fires only a frame's own scripts, so deliver these two edges.
    local function SetParentVisibility(shown)
        W.Native(function()
            W.UIParent:SetShown(shown)
            local edge = shown and "OnShow" or "OnHide"
            W.CF:GetScript(edge)(W.CF)
            finance.window:GetScript(edge)(finance.window)
        end)
    end
    SetParentVisibility(false)
    assert(W.CF:IsShown() and finance.window:IsShown() and not W.CF:IsVisible() and not finance.window:IsVisible())
    assert(not CurrencyWatching() and not next(activeTicks), "hidden UIParent kept finance views subscribed")
    W.S.Set("bags", "goldPeriod", 1)
    W.S.Set("bags", "goldPeriod", 3)
    assert(not W.M.context.callbacks.PLAYER_MONEY and not next(activeTicks), "hidden UIParent options woke the gold footer")
    quantity, currencyReads, writes = 218, 0, 0
    local previousMoney = W.money
    W.money = W.money + 100
    W.Fire("PLAYER_MONEY")
    W.Fire("CURRENCY_DISPLAY_UPDATE")
    finance.Show()
    finance.Refresh()
    W.Settle()
    assert(currencyReads == 0 and writes == 0 and day.earned == 1300, "invisible finance surfaces painted or lost a transaction")
    SetParentVisibility(true)
    W.Settle()
    assert(CurrencyWatching() and next(activeTicks) and finance.labels[1].right:GetText() == "218", "ancestor show failed to refresh the history")
    assert(style.goldLabel:GetText() == "Session +" .. W.S.MoneyText(previousMoney + 100 - initial), "ancestor show failed to refresh the footer")
    W.CloseBags()
    assert(CurrencyWatching(), "bag close lost the independently visible currency window")
    finance.window:Hide()
    assert(not CurrencyWatching(), "last currency window closed without removing the event")
    W.S.SetMany("bags", {currencyIDs = "", showGoldHistory = false, goldPeriod = 1})
    assert(not finance.events:IsEventRegistered("PLAYER_MONEY") and not CurrencyWatching(), "disabled history or empty currency list kept listening")
    W.OpenBags()
    W.Settle()
    assert(not CurrencyWatching(), "empty currency list kept the currency event")
    assert(#W.errors == 0 and #W.taint == 0 and #W.combatLayout == 0, table.concat(W.errors, ";"))
end
local function CheckUnreadableLogin()
    local W = H.New(root, {client = "Forever", config = {showGoldHistory = false, goldPeriod = 1}})
    W.money = "unreadable"
    W.NS.goldSessionCaptured = false
    W.Apply()
    assert(W.M.context.callbacks.PLAYER_MONEY, "closed bag abandoned an unreadable login baseline")
    W.money = 240
    W.Fire("PLAYER_MONEY")
    assert(W.NS.StoredSessionGold() == 240 and not W.M.context.callbacks.PLAYER_MONEY, "baseline recovery did not disarm")
    W.money = 480
    W.Fire("PLAYER_MONEY")
    W.OpenBags()
    W.Settle()
    assert(W.M.windows[W.CF].goldLabel:GetText() == "Session +" .. W.S.MoneyText(240), "first open lost recoverable session income")
end
CheckUnreadableLogin()
for _, client in ipairs({"Forever", "Mainline"}) do Check(client) end
print("closed-gold display, live history, independent currency window and combat transitions passed")
