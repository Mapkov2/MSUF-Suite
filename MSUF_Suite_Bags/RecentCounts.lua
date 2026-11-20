local _, P = ...
local NS, S = P.NS, P.Suite
local Slots, Index = P.SlotCache, P.InventoryIndex
local Recent = {}
P.BagRecentCounts = Recent

-- Two carried-inventory totals. A slot move or a stack split keeps their sum
-- unchanged. This extra read path is only active for the opt-in Recent modes.
local current, scratch, seeded = {}, {}, false
local transferUntil

function Recent.Reset()
    seeded, transferUntil = false, nil
end

local function Totals(out)
    for id in pairs(out) do out[id] = nil end
    local last = NS.Client.isForever and Constants.InventoryConstants.NumBagSlots or Enum.BagIndex.ReagentBag
    for bag = 0, last do
        local count = Slots.Sync(bag)
        for slot = 1, count do
            local item = Slots.Get(bag, slot)
            if Slots.dirtySlots[bag * Slots.KEY + slot] then return false end
            if item then
                local id, amount = item.itemID, item.stackCount
                if not S.Finite(id) or not S.Finite(amount) then return false end
                out[id] = (out[id] or 0) + amount
            end
        end
    end
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if not S.Public(id) then return false end
        if id then out[id] = (out[id] or 0) + 1 end
    end
    return true
end

local function Active(config)
    return config.showRecent and (config.recentNewTypesOnly or config.showRecentGains)
end

function Recent.Wanted(config)
    return Active(config) == true
end

local function Shown(frame)
    if not frame then return false end
    local shown = frame:IsShown()
    return S.Public(shown) and shown == true
end

function Recent.Event(config, event, first, second)
    if not Active(config) or NS.InCombat(event) then return end
    if event == "MAIL_INBOX_UPDATE" then
        if Shown(MailFrame) then transferUntil = GetTime() + 1 end
        return
    elseif event == "TRADE_ACCEPT_UPDATE" then
        transferUntil = S.Public(first) and S.Public(second) and (first == 1 or first == true)
            and (second == 1 or second == true) and GetTime() + 1 or nil
        return
    end
    if not Totals(scratch) then
        Recent.Reset()
        return
    end
    local gainEvent = event == "BAG_UPDATE_DELAYED" or event == "PLAYER_REGEN_ENABLED"
    if seeded and gainEvent and not (Shown(BankFrame) or Shown(GuildBankFrame)) then
        local recent = Index.Recent()
        local transfer = Shown(MailFrame) or Shown(TradeFrame) or transferUntil and GetTime() <= transferUntil
        local now = GetServerTime()
        for id, count in pairs(scratch) do
            local before = current[id] or 0
            if count > before then Index.RememberRecentGain(recent, id, before, count, transfer, now) end
        end
    end
    current, scratch, seeded = scratch, current, true
end
