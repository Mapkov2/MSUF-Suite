-- Merchant and auction trading use every visible bag together.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_window_focus_contract.lua", "rb"))
local source = file:read("*a"); file:close()
local stop = assert(source:find('    local a = Native("CharacterFrame"', 1, true))
local body = [======[
    Load("Adapters/CatalogGlass.lua")
    UIPanelWindows[tradingWindowName] = { area = "left" }
    local merchant = Native(tradingWindowName, 100, 100, 338, 496)
    local bag = Native("ContainerFrameCombinedBags", 500, 100, 450, 500)
    merchant.protected, merchant.explicitProtected = true, true
    bag.protected, bag.explicitProtected = true, true
    local other = Native("ProfessionsFrame", 1100, 50, 400, 600)
    local bank = Native("BankFrame", 1600, 50, 300, 600)
    W.TrackFocus(merchant, "merchant")
    W.TrackFocus(other, "other")
    Check(Dimmed(merchant), "a merchant without bags became exempt")
    Check(W.TrackFocus(bag, "bags"), "combined backpack was not enrolled")
    Check(not Dimmed(merchant) and not Dimmed(bag), "opening bags dims the merchant")
    Click(merchant); Tick()
    Check(not Dimmed(merchant) and not Dimmed(bag) and Dimmed(other), "merchant input dims bags")
    Click(bag); Tick()
    Check(not Dimmed(merchant) and not Dimmed(bag), "bag input dims the merchant")
    Click(other); Tick()
    Check(not Dimmed(merchant) and not Dimmed(bag), "third-window input dims the shopping pair")
    W.TrackFocus(bank, "bank")
    Click(other); Tick()
    Check(Dimmed(bank), "shopping exempts the bank")
    other.left, other.width = 50, 1000
    Click(merchant); Tick()
    for _, veil in ipairs(F.records[other].veils) do
        if veil.dim then
            Check(not Intersects(veil.rect, F.records[merchant].rect)
                and not Intersects(veil.rect, F.records[bag].rect), "another window's veil covers shopping")
        end
    end
    other.left, other.width = 1100, 400
    local width = bag.GetWidth
    bag.GetWidth = function() return { secret = true } end
    listeners[F](F, "geometry")
    Check(not Dimmed(merchant) and not Dimmed(bag) and not Dimmed(bank), "unreadable bag leaves a stale veil")
    bag.GetWidth = width
    listeners[F](F, "geometry")
    Check(not Dimmed(merchant) and not Dimmed(bag) and Dimmed(bank), "readable bag did not restore shopping")
    bag:Hide(); Click(other); Tick()
    Check(Dimmed(merchant), "closing the last bag leaves the merchant exempt")
    merchant:Hide(); bag:Show(); Click(other); Tick()
    Check(Dimmed(bag), "bags without a merchant became exempt")
    merchant:Show(); Tick()
    Check(not Dimmed(merchant) and not Dimmed(bag), "reverse opening order breaks shopping")
    bag:Hide()
    local bags = {}
    for index = 1, 6 do
        local split = Native("ContainerFrame" .. index, 450 + index * 170, 150, 160, 300)
        bags[index] = split
        Check(W.TrackFocus(split, "bags"), "split bag was not enrolled")
        Click(other); Tick()
        Check(not Dimmed(merchant) and not Dimmed(split), "split bag does not stay clear with the merchant")
    end
    for _, split in ipairs(bags) do
        Check(not Dimmed(split), "opening another split bag dims an existing bag")
    end
    combat, combatEdge = true, true
    Click(merchant); Tick(); Click(bags[3]); Tick(); Click(other); Tick()
    Check(not Dimmed(merchant) and not Dimmed(bags[3]), "combat breaks shopping")
    Check((merchant.geometryWrites or 0) == 0 and (bags[3].geometryWrites or 0) == 0,
        "shopping changes native geometry in combat")
    combat, combatEdge = false, false
    for index = 1, 5 do bags[index]:Hide() end
    Check(not Dimmed(merchant) and not Dimmed(bags[6]), "closing some bags breaks the remaining pair")
    bags[6]:Hide(); Click(other); Tick()
    Check(Dimmed(merchant), "closing all split bags leaves the merchant exempt")
    bag:Show(); Click(other); Tick()
    F.ReleaseOwner("bags")
    Check(Dimmed(merchant) and not Dimmed(bag), "releasing bags leaves a stale shopping exception")
    W.TrackFocus(bag, "bags")
    Check(not Dimmed(merchant) and not Dimmed(bag), "retracking bags did not restore shopping")
    F.ReleaseOwner("merchant"); Click(other); Tick()
    Check(Dimmed(bag) and not Dimmed(merchant), "releasing merchant leaves a stale shopping exception")
    W.TrackFocus(merchant, "merchant")
    NS.DB.theme.windowFocusDimming = false; listeners[F](F, "theme")
    Check(not Dimmed(other) and not Dimmed(bag), "disabling dimming leaves a shopping veil")
    NS.DB.theme.windowFocusDimming = true; listeners[F](F, "theme")
    Check(not Dimmed(merchant) and not Dimmed(bag), "reenabling dimming loses shopping")
    local secondName = tradingWindowName == "MerchantFrame" and "AuctionHouseFrame" or "MerchantFrame"
    UIPanelWindows[secondName] = { area = "left" }
    local second = Native(secondName, 1500, 100, 338, 496)
    W.TrackFocus(second, "second-trader")
    Click(other); Tick()
    Check(not Dimmed(merchant) and not Dimmed(second) and not Dimmed(bag), "one trader dims another")
    merchant:Hide(); Tick()
    Check(not Dimmed(second) and not Dimmed(bag), "closing one trader breaks the other pair")
    second:Hide(); Click(other); Tick()
    Check(Dimmed(bag), "closing both traders leaves bags exempt")
    merchant:Show(); Tick()
    Check(not Dimmed(merchant) and not Dimmed(bag), "reopening a trader did not restore the pair")
    F.ReleaseOwner("second-trader")
    merchant:Hide(); bag:Hide(); bank:Hide(); other:Hide()
    local reads = 0
    merchant.GetWidth = function() reads = reads + 1; return 338 end
    bag.GetWidth = function() reads = reads + 1; return 450 end
    for _ = 1, 1000 do Tick() end
    Check(reads == 0 and not driver.scripts.OnUpdate, "closed shopping windows poll geometry")
end
]======]
for _, name in ipairs({ "AuctionHouseFrame", "MerchantFrame" }) do
    local prefix = ("local tradingWindowName = %q\n"):format(name)
    local report = ('\nprint("suite_window_focus_merchant_contract (%s): " .. checks .. " checks passed")'):format(name)
    assert(loadstring(prefix .. source:sub(1, stop - 1) .. body .. report, "@window_focus_merchant_contract:" .. name))()
end
