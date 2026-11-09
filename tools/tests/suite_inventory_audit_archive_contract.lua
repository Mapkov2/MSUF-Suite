-- The inventory archive's Forget actions and the automatic junk sale, as a
-- player meets them (the options and profile half is suite_inventory_audit_contract.lua):
--  * Forget a character and Forget warband bank each ask first, remove exactly
--    that record, and the mail recipients derived from the archive follow;
--  * Forget current says it is recorded again while the archive is on, and it
--    is: one rule for every character, no hidden "stopped" state;
--  * an answer that arrives in combat, on another profile or after the archive
--    went off removes nothing;
--  * the automatic junk sale pauses only when a protected item would be sold
--    (a protected item that is junk, or anything unreadable), never merely
--    because a protected item sits in the bags.
-- Usage: lua suite_inventory_audit_archive_contract.lua <Suite root>
local root = assert(arg[1], "repository root required")
local F = dofile(root .. "/tools/tests/suite_inventory_tools_fixture.lua")
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local E = F.New(root)
local S, NS = E.S, E.NS
local profile = NS.DB

-- S.Confirm shows one question; the player's Yes runs its callback.
local asked
S.Confirm = function(key, data) asked = { key = key, data = data } end
local function Answer()
    local question = assert(asked, "no question was asked")
    asked = nil
    question.data.callback()
    return question
end

------------------------------------------------------------------ the archive
E:Item(0, 1, 12, 4)
local archive = E:Start("inventoryArchive", { characters = 5, tooltips = true })
E:Flush()
E.guid, E.name = "player-b", "Beta"
E:Item(0, 1, 12, 1); E:Item(6, 1, 12, 8); E:Item(13, 1, 12, 10)
BankFrame:Show(); E:Emit(archive, "BANKFRAME_OPENED"); E:Flush()
local store = NS.RootDB.suiteInventoryArchive
eq(store.characters["player-a"] ~= nil and store.characters["player-b"] ~= nil, true, "both characters recorded")
eq(store.account.EU ~= nil, true, "warband bank recorded")
eq(table.concat(archive:Recipients(), ","), "Alpha-Realm", "the other character is a mail recipient")

archive:Open()
local window
for _, frame in ipairs(E.frames) do if frame.owner == archive and frame.actions then window = frame end end
assert(window, "the archive window did not open")

-- Browsing starts from cached snapshots, including while the live bank is open.
local scans = E.calls.scan
archive:Browse("bank")
eq(#window.filtered, 1, "bank launcher scopes to recorded character banks")
eq(window.filtered[1].label, "Item 12 × 8 — Beta-Realm (Bank)", "character bank quantity is dated and read-only")
window.tabs[2]:Click()
eq(#window.filtered, 2, "bags tab shows both recorded characters")
window.actions[5]:Click()
eq(E.menu[1][1], "All characters", "character menu can restore the combined view")
eq(E.menu[2][1], "Alpha-Realm", "character menu includes an alt")
eq(E.menu[3][1], "Beta-Realm", "character menu includes the current character")
E.menu[2][2]()
eq(#window.filtered, 1, "choosing an alt scopes the rows")
eq(window.filtered[1].label, "Item 12 × 4 — Alpha-Realm (Bags)", "alt shows its own recorded quantity")
eq(window.status.text:find("Recorded ", 1, true) ~= nil, true, "selected snapshot shows when it was recorded")
window.search:SetText("not in archive")
eq(#window.filtered, 0, "search filters inside the selected snapshot")
window.search:SetText("ITEM 12")
eq(#window.filtered, 1, "recorded item search is case insensitive")
window.tabs[4]:Click()
eq(#window.filtered, 1, "warband is a separate recorded location")
eq(window.filtered[1].label, "Item 12 × 10 — Warband (Warband bank)", "warband count is independent of selected character")
window.tabs[2]:Click()
eq(#window.filtered, 1, "returning from warband preserves the character selection")
eq(E.calls.scan, scans, "archive launch, search and navigation do not scan live containers")
eq(#E.writes, 0, "archive browsing never moves items")
archive:Open()
eq(#window.filtered, 4, "the options launcher still opens the complete archive")

eq(window.actions[3].text, "Forget a character", "forget-a-character action")
eq(window.actions[4].text, "Forget warband bank", "forget-warband action")
eq(window.actions[3].enabled, true, "another character can be forgotten")
eq(window.actions[4].enabled, true, "a recorded warband bank can be forgotten")

-- Forget a character: pick, confirm, and only then is it gone.
window.actions[3]:Click()
eq(#E.menu, 1, "the picker lists the other recorded character only")
eq(E.menu[1][1], "Alpha-Realm", "the picker names the character")
E.menu[1][2]()
eq(asked.key, "suite-archive-forget", "the Suite's confirmation is used")
eq(asked.data.text_arg1, "Alpha-Realm", "the question names the character")
eq(store.characters["player-a"] ~= nil, true, "nothing is removed before the answer")
Answer()
eq(store.characters["player-a"], nil, "the confirmed character is gone")
eq(store.characters["player-b"] ~= nil, true, "the current character is untouched")
eq(#archive:Recipients(), 0, "mail recipients follow the forgotten character")
eq(window.actions[3].enabled, false, "no other character left to forget")
local rows = archive:Rows("")
for i = 1, #rows do assert(not rows[i].label:find("Alpha", 1, true), "forgotten items still listed") end

-- Forget warband bank: removes the region's snapshot, nothing else.
BankFrame:Hide(); E:Emit(archive, "BANKFRAME_CLOSED")
window.actions[4]:Click()
eq(asked.data.text_arg1, nil, "the warband question names no character")
Answer()
eq(store.account.EU, nil, "the warband snapshot is gone")
eq(select(3, archive:Supply(12)), 0, "no warband supply is reported")
eq(store.characters["player-b"].bank ~= nil, true, "the character bank is untouched")
eq(window.actions[4].enabled, false, "nothing left to forget")

-- Forget current: the question promises the re-recording, and it happens.
window.actions[2]:Click()
eq(asked.data.text_arg1, "Beta-Realm", "the question names the current character")
eq(asked.data.text:find("recorded again", 1, true) ~= nil, true, "the question says it is recorded again")
Answer()
eq(store.characters["player-b"], nil, "the current character is forgotten")
E:Emit(archive, "BAG_UPDATE_DELAYED"); E:Flush()
eq(store.characters["player-b"].bags.counts[12], 1, "recorded again while the archive is on")

-- An answer that no longer fits removes nothing.
local function Refused(label, setup, restore)
    window.actions[2]:Click()
    setup()
    Answer()
    restore()
    eq(store.characters["player-b"] ~= nil, true, label)
end
Refused("an answer in combat removed data", function() E.combat = true end, function() E.combat = false end)
Refused("an answer on another profile removed data", function() NS.DB = {} end, function() NS.DB = profile end)
Refused("an answer after the archive went off removed data",
    function() archive.active = false end, function() archive.active = true end)

------------------------------------------------------------------ the junk sale
local junkCalls = 0
IsShiftKeyDown = function() return false end
C_MerchantFrame = { IsSellAllJunkEnabled = function() return true end, GetNumJunkItems = function() return 1 end,
    SellAllJunkItems = function() junkCalls = junkCalls + 1 end }
E:Load("MSUF_Suite_QualityOfLife/Merchant.lua")
local protection = E:Start("inventoryProtection", { items = "12=1", sets = true })
local merchant = E:Start("qol", { autoJunk = true, repair = false })
-- One visit at the vendor: how many native sales it requested, and the notice.
local function Visit()
    local before = junkCalls
    E.message = nil
    E:Emit(merchant, "MERCHANT_SHOW"); E:Emit(merchant, "MERCHANT_CLOSED")
    return junkCalls - before, E.message
end
local function Bags(...)
    E.bags = {}
    for slot, item in ipairs({ ... }) do E:Item(0, slot, item[1], 1, item[2]) end
end
local COMMON, POOR, EPIC = 1, 0, 4

E.sets = {}
Bags({ 12, COMMON }, { 13, POOR })
local sold, notice = Visit()
eq(sold, 1, "a protected item that is not junk no longer stops the sale")
eq(notice, nil, "no pause notice without protected junk")

Bags({ 12, POOR }, { 13, POOR })
sold, notice = Visit()
eq(sold, 0, "a protected junk item pauses the sale")
eq(notice:find("protected item is among your junk", 1, true) ~= nil, true, "the notice says why")

Bags({ 12, COMMON })
E.bags[0][1].quality = E.secret
eq(Visit(), 0, "an unreadable quality may be junk: paused")

E.sets = { 1 }
Bags({ 99, EPIC }, { 13, POOR })
eq(Visit(), 1, "protected gear that is not junk does not pause the sale")
Bags({ 99, POOR }, { 13, POOR })
eq(Visit(), 0, "protected gear that is junk pauses the sale")

E.sets = E.secret
Bags({ 13, POOR })
eq(Visit(), 0, "unreadable equipment sets pause the sale")

E.sets = {}
Bags({ 12, POOR })
E.bags[0][2] = E.secret
eq(Visit(), 0, "an unreadable bag slot pauses the sale")

Bags({ 12, POOR })
protection.active = false
eq(Visit(), 1, "protection off: the native sale is untouched")

local function CheckNativeSources(forever)
    local env = F.New(root, forever)
    local module = env:Start("inventoryArchive", { characters = 5, tooltips = true })
    env:Flush()
    local row = env.NS.RootDB.suiteInventoryArchive.characters[env.guid]
    local function Event(event)
        env:Emit(module, event)
        env:Flush()
    end

    local mailReads, mailboxComplete = 0, true
    GetInboxNumItems = function() return 2, mailboxComplete and 2 or 3 end
    GetInboxHeaderInfo = function(message) return nil, nil, nil, nil, nil, message == 2 and 10 or 0, 2, 1 end
    GetInboxItem = function(message, slot)
        mailReads = mailReads + 1
        assert(message == 1, "cash-on-delivery message read as owned inventory")
        if slot == 4 then return "Ore", 12, 1, 5 end
    end
    CheckInbox = function() error("archive must not query the inbox") end
    Event("MAIL_INBOX_UPDATE")
    eq(mailReads, 0, "hidden mailbox never read")
    MailFrame:Show()
    env:Emit(module, "MAIL_INBOX_UPDATE"); env:Emit(module, "MAIL_INBOX_UPDATE"); env:Flush()
    eq(mailReads, 4, "mail snapshots coalesce and follow sparse attachment slots")
    eq(row.mail.counts[12], 5, "mail attachment count")
    local savedMail = row.mail
    mailboxComplete = false
    env.now = env.now + 1
    Event("MAIL_INBOX_UPDATE")
    eq(row.mail, savedMail, "partial inbox preserves the previous complete snapshot")
    MailFrame:Hide()

    AuctionHouseFrame = env.S.CreateFrame("Frame")
    Enum.AuctionStatus = { Active = 0, Sold = 1 }
    local auctionFull, auctionReads = false, 0
    C_AuctionHouse = {
        HasFullOwnedAuctionResults = function() return auctionFull end,
        GetNumOwnedAuctions = function() return 2 end,
        GetOwnedAuctionInfo = function(index)
            auctionReads = auctionReads + 1
            return { status = index - 1, itemKey = { itemID = 12 }, quantity = index * 10 }
        end,
        QueryOwnedAuctions = function() error("archive must not query auctions") end,
    }
    Event("OWNED_AUCTIONS_UPDATED")
    eq(auctionReads, 0, "incomplete auction listing not read")
    auctionFull = true
    Event("OWNED_AUCTIONS_UPDATED")
    eq(row.auctions.counts[12], 10, "only active owned auctions contribute")
    eq(auctionReads, 2, "owned auction entries read exactly once")
    AuctionHouseFrame:Hide()

    GuildBankFrame = env.S.CreateFrame("Frame")
    local club, activeTab, guildReads, canView = 1234, 1, 0, true
    C_Club = { GetGuildClubId = function() return club end }
    GetGuildInfo = function() return "Guild" end
    GetCurrentGuildBankTab = function() return activeTab end
    GetGuildBankTabInfo = function(tab) return "Tab " .. tab, 1, canView end
    GetGuildBankItemInfo = function(_, slot)
        guildReads = guildReads + 1
        if slot == 1 then return 1, 3 end
    end
    GetGuildBankItemLink = function() return "|Hitem:12:0|h[Ore]|h" end
    QueryGuildBankTab = function() error("archive must not query guild tabs") end
    env:Emit(module, "GUILDBANKBAGSLOTS_CHANGED")
    activeTab = 2
    env:Flush()
    eq(guildReads, 0, "switching tabs before capture does not record an unloaded tab")
    Event("GUILDBANKBAGSLOTS_CHANGED")
    eq(guildReads, 98, "only the loaded guild tab is read")
    module:Browse("guild")
    local items = module:Rows("")
    eq(#items, 1, "guild observation displayed in its separate scope")
    eq(items[1].label, "Item 12 × 3 — Guild (Tab 2) (Guild bank)", "guild result identifies its observed tab")
    club = 1235
    eq(#module:Rows(""), 0, "another guild cannot browse the previous guild observation")
    club = 1234
    env.guid, env.name = "other-guild-member", "Other"
    eq(#module:Rows(""), 0, "another alt must observe authorized tabs itself")
    env.guid, env.name = "player-a", "Alpha"
    canView = false
    Event("GUILDBANK_UPDATE_TABS")
    eq(#module:Rows(""), 0, "explicitly revoked tab access removes the stored observation")
    Event("GUILDBANKBAGSLOTS_CHANGED")
    eq(guildReads, 98, "a forbidden tab is never read")
    GuildBankFrame:Hide()

    local tooltip = {}
    env.tooltip(tooltip, { id = 12 })
    eq(tooltip[1][1], "Alpha-Realm (Mail)", "mail counts identify the recorded character in the tooltip")
    eq(tooltip[2][1], "Alpha-Realm (Auction House)", "auction counts identify the recorded character in the tooltip")
end

CheckNativeSources(false)
CheckNativeSources(true)

print("inventory audit archive: " .. checks .. " behavior checks")
