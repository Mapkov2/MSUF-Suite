local root = assert(arg[1], "repository root required")
local F = dofile(root .. "/tools/tests/suite_inventory_tools_fixture.lua")
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local E = F.New(root)
local S, NS = E.S, E.NS
local Rules, Lists = NS.InventoryRules, NS.InventoryLists
local item = { itemID = 12, name = "Moon Cloth", search = "moon cloth", quality = 4, count = 12, bound = false,
    itemLevel = 620, setNames = { "Raid gear" }, equipLoc = "INVTYPE_CHEST", className = "Armor" }
for _, query in ipairs({ '"moon cloth"', 'quality>=3 !is:bound', 'name:"Moon Cloth"', 'id=12 | id=99', 'set:raid', 'level>=600 is:equipment' }) do
    eq(Rules.Matches(assert(Rules.Compile(query)), item), true, "query " .. query)
end
for _, query in ipairs({ 'quality<3', 'is:bound', 'id=99', 'type:weapon', '!set:raid' }) do
    eq(Rules.Matches(assert(Rules.Compile(query)), item), false, "exclude " .. query)
end
eq(Rules.Compile('"unclosed'), nil, "unclosed quote rejected")
eq(Rules.Compile('id>=x'), nil, "invalid numeric filter rejected")
eq(Rules.Compile('a |'), nil, "empty OR rejected")
eq(Rules.Compile(string.rep("x", 513)), nil, "query bounded")
eq(Lists.Quantities("12=4\n13=8")[13], 8, "quantities parse")
eq(Lists.Quantities("12=0"), nil, "zero rejected")
eq(Lists.Quantities("12=1.5"), nil, "fraction rejected")
eq(Lists.EncodeQuantities({ [12] = math.huge }), nil, "infinite rejected")
local template = { name = "Mats|Raid", recipient = "Beta-Realm", subject = "50%", items = "12=4\n13=8" }
local encoded = assert(Lists.EncodeTemplates({ template }))
local decoded = Lists.Templates(encoded)[1]
eq(decoded.name, template.name, "template escaped name")
eq(decoded.items, template.items, "template quantities round trip")

-- Real shared UI: bounded rows, no hidden provider work, fresh selection, profiles and editor lifecycle.
local owner, rows, calls, runs = { active = true }, {}, 0, 0
for i = 1, 30 do rows[i] = { key = i, label = "Row " .. i, detail = string.rep("note ", 900) } end
local spec = { title = "Tools", rows = function() calls = calls + 1; return rows end,
    actions = { { label = "Run", enabled = function(_, row) return row ~= nil end, run = function() runs = runs + 1 end } } }
local window = S.ToolListWindow.Open(owner, spec)
eq(#window.buttons, 12, "pooled rows")
window.buttons[1]:Click()
eq(window:Selected().key, 1, "row selection")
eq(window.detailsChild:GetHeight() > 67, true, "long notes scroll")
window.actions[1]:Click()
eq(runs, 1, "explicit selected action")
table.remove(rows, 1)
window.actions[1]:Click()
eq(runs, 1, "removed selection cannot run")
window:Hide()
local hiddenCalls = calls
S.ToolListWindow.Refresh(owner)
eq(calls, hiddenCalls, "hidden list never queries provider")
window = S.ToolListWindow.Open(owner, spec)
window.buttons[1]:Click()
NS.DB = {}
window.actions[1]:Click()
eq(runs, 1, "stale profile action refused")
S.ToolListWindow.Refresh(owner)
eq(window:IsShown(), false, "stale profile closes")
-- A search that hides the selected row also takes it out of the selection: the details and the actions never act on a row nobody sees.
window = S.ToolListWindow.Open(owner, spec)
window.buttons[1]:Click()
eq(window:Selected().key, 2, "first visible row selected")
window.search:SetText("Row 30")
eq(window:Selected(), nil, "a row hidden by the search stayed selected")
eq(window.details.text, "Select an entry to see its details.", "details of a row hidden by the search")
window.actions[1]:Click()
eq(runs, 1, "an action ran on a row hidden by the search")
window.search:SetText("")
window:Hide()
local saved = 0
S.ToolListWindow.Edit(owner, { title = "Edit", text = "old", onSave = function(_, value) saved = saved + 1; eq(value, "new", "edited value") end })
local save, cancel, input
for _, frame in ipairs(E.frames) do
    if frame.text == "Save" then save = frame end
    if frame.text == "Cancel" then cancel = frame end
    if frame.kind == "EditBox" and frame.text == "old" then input = frame end
end
input:SetText("new"); cancel:Click(); eq(saved, 0, "cancel never saves")
S.ToolListWindow.Edit(owner, { title = "Edit", text = "new", onSave = function() saved = saved + 1 end })
save:Click(); eq(saved, 1, "explicit save")
S.ToolListWindow.Edit(owner, { title = "Edit", onSave = function() saved = saved + 1 end })
E.combat = true; save:Click(); eq(saved, 1, "combat editor refused"); E.combat = false

-- Snapshot ownership and timestamps never follow another character's current inventory.
E:Item(0, 1, 12, 4); E:Item(6, 1, 12, 8); E:Item(13, 1, 12, 10)
local archive = E:Start("inventoryArchive", { characters = 5, tooltips = true })
E:Flush()
eq(NS.RootDB.suiteInventoryArchive.characters["player-a"].bags.counts[12], 4, "current bags captured")
eq(NS.RootDB.suiteInventoryArchive.characters["player-a"].bank, nil, "closed bank never invented")
BankFrame:Show(); E:Emit(archive, "BANKFRAME_OPENED"); E:Flush()
local bankCount, bankAt, warCount = archive:Supply(12)
eq(bankCount, 8, "bank captured"); eq(bankAt, 1000, "real timestamp"); eq(warCount, 10, "warbank once")
BankFrame:Hide(); E:Emit(archive, "BANKFRAME_CLOSED")
E.now = 2000; E.bags[0][1] = E.secret; E:Emit(archive, "BAG_UPDATE_DELAYED"); E:Flush()
eq(NS.RootDB.suiteInventoryArchive.characters["player-a"].bags.at, 1000, "unreadable scan preserves complete snapshot")
E.guid, E.name = "player-b", "Beta"; E:Item(0, 1, 12, 1); E:Emit(archive, "BAG_UPDATE_DELAYED"); E:Flush()
eq(NS.RootDB.suiteInventoryArchive.characters["player-a"].bags.counts[12], 4, "offline alt not overwritten")
eq(NS.RootDB.suiteInventoryArchive.characters["player-b"].bags.counts[12], 1, "second character separately captured")
local tooltip = {}; E.tooltip(tooltip, { id = 12 }); eq(#tooltip >= 2, true, "recorded owners tooltip")
local untouched = {}; E.tooltip(untouched, { id = E.secret }); eq(#untouched, 0, "secret tooltip ignored")
local restock = E:Start("restockPlanner", { targets = "12=6" })
eq(restock:Rows()[1].label:find("missing 5", 1, true) ~= nil, true, "stock deficit uses own bags")
eq(restock:Rows()[1].detail:find("Not recorded", 1, true) ~= nil, true, "unknown bank explicit")
E.bags[0][2] = E.secret
eq(restock:Rows()[1].label:find("unavailable", 1, true) ~= nil, true, "incomplete bags have no invented deficit")
E.bags[0][2] = nil

-- Protection includes bag locations belonging to an equipment set and fails closed on unreadable sets.
local protection = E:Start("inventoryProtection", { items = "12=1", sets = true })
eq(protection:IsProtected(12, 0, 1), true, "explicit never-sell item")
E.sets = { 2 }; protection:Prepare(); eq(protection:IsProtected(99, 0, 2), true, "equipment-set conservative gear protection")
eq(protection:IsProtected(99, 0, 3), true, "all equippable items protected without unproven membership")
E.sets = E.secret; protection:Prepare(); eq(protection:IsProtected(99, 0, 3), true, "unreadable set prevents unsafe sales")
E.sets = {}; protection:Prepare(); E.bags[0][1].quality = 0
eq(protection:HasProtectedJunk(), true, "bulk native guard sees protected junk item")
local junkCalls = 0
IsShiftKeyDown = function() return false end
C_MerchantFrame = { IsSellAllJunkEnabled = function() return true end, GetNumJunkItems = function() return 1 end,
    SellAllJunkItems = function() junkCalls = junkCalls + 1 end }
E:Load("MSUF_Suite_QualityOfLife/Merchant.lua")
local merchant = E:Start("qol", { autoJunk = true, repair = false })
E:Emit(merchant, "MERCHANT_SHOW")
eq(junkCalls, 0, "native bulk sale cannot bypass protection")
E:Emit(merchant, "MERCHANT_CLOSED"); protection.active = false; E:Emit(merchant, "MERCHANT_SHOW")
eq(junkCalls, 1, "native bulk behavior retained when protection off")
protection.active = true

-- Recipe quantities aggregate shared reagents; unresolved alternatives and variable requirements stay explicit.
E.recipes = { 101, 102 }; E.recrafts = {}
E.schematics[101] = { name = "Potion", reagentSlotSchematics = {
    { required = true, quantityRequired = 3, reagents = { { itemID = 12 } } },
    { required = true, quantityRequired = 2, reagents = { { itemID = 13 }, { itemID = 14 } } },
    { required = false, quantityRequired = 1, reagents = { { itemID = 99 } } },
} }
E.schematics[102] = { name = "Flask", reagentSlotSchematics = {
    { required = true, quantityRequired = 2, reagents = { { itemID = 12 } } },
    { required = true, quantityRequired = 1, variableQuantities = { { quantity = 1 } }, reagents = { { itemID = 90 } } },
} }
local craft = E:Start("craftShopping", { quantities = "202=4\n204=2", choices = "" })
local recipes, materials, totals = craft:Build()
eq(#recipes, 2, "tracked recipes"); eq(totals[12], 16, "shared reagent sum times crafts")
eq(totals[13], nil, "alternative not invented"); eq(totals[90], nil, "variable not invented"); eq(totals[99], nil, "optional excluded")
craft.config.choices = "101:0:2=14"
_, _, totals = craft:Build(); eq(totals[14], 8, "explicit quality choice counted")
local archiveStore = NS.RootDB.suiteInventoryArchive
archiveStore.characters["player-b"].bank = { counts = { [12] = 3 }, at = 3000 }
archiveStore.characters["other-region"] = { address = "Other-Realm", region = "US",
    bags = { counts = { [12] = 100 }, at = 3000 } }
archiveStore.characters["player-a"].mail = { counts = { [12] = 8 }, at = 3000 }
local shopping, indexCalls = {}, 0
local materialSources = archive.MaterialSources
function archive:MaterialSources(wanted)
    indexCalls = indexCalls + 1
    return materialSources(self, wanted)
end
for _, row in ipairs(craft:Rows()) do shopping[row.itemID] = row end
eq(indexCalls, 1, "shopping render indexes archived sources once for all items")
eq(shopping[12].label:find("missing 15", 1, true) ~= nil, true, "archive stock never changes the live bag deficit")
local materialDetail = shopping[12].detail
eq(materialDetail:find("Bank: 3 · " .. date("%Y-%m-%d %H:%M", 3000), 1, true) ~= nil, true, "own bank with its time")
eq(materialDetail:find("Warband bank: 10 · ", 1, true) ~= nil, true, "one shared warband source")
eq(materialDetail:find("Alpha-Realm (Bags): 4 · ", 1, true) ~= nil, true, "alt bags are separate from bank")
eq(materialDetail:find("Alpha-Realm (Bank): 8 · ", 1, true) ~= nil, true, "alt bank stays its own source")
eq(materialDetail:find("Beta-Realm (Bags)", 1, true), nil, "archived own bags never double count the live bags")
eq(materialDetail:find("Other-Realm", 1, true), nil, "another region is excluded")
eq(materialDetail:find("(Mail)", 1, true), nil, "mail is not a bank or bag source")
eq(shopping[14].detail:find("Last recorded material locations", 1, true), nil, "no inventory availability is invented")
archive.active = false
eq(craft:Rows()[1].detail:find("Last recorded material locations", 1, true), nil, "disabled archive contributes no sources")
archive.active = true
archive.MaterialSources = materialSources
E.bags[0][2] = E.secret
eq(craft:Rows()[1].label:find("unavailable", 1, true) ~= nil, true, "craft missing amount waits for complete bags")
E.bags[0][2] = nil

-- Bank calls are user-click-only; events confirm/stop but never issue another move.
E:Item(0, 1, 12, 8); BankFrame:Show()
local transfer = E:Start("bankTransfer", {})
local row = transfer:Rows()[1]
E:Click(transfer, transfer.Move, row); eq(#E.writes, 1, "clicked bank move")
E:Emit(transfer, "BAG_UPDATE_DELAYED"); eq(#E.writes, 1, "event never chains moves")
E:Click(transfer, transfer.Move, row); eq(#E.writes, 1, "pending cannot move again")
E:Flush(); eq(transfer.pending, nil, "bounded timeout")
E.free = 0; E:Click(transfer, transfer.Move, row); eq(#E.writes, 1, "full bank refusal"); E.free = 8
E.cursor = { kind = "item", id = 99 }; E:Click(transfer, transfer.Move, row); eq(#E.writes, 1, "cursor refusal"); E.cursor = nil
E.bankType = 2; E:Click(transfer, transfer.Move, row); eq(#E.writes, 1, "changed bank type refusal")
row = transfer:Rows()[1]; E.refundable = true; E:Click(transfer, transfer.Move, row)
eq(#E.writes, 1, "refund confirmation stays native"); E.refundable = false
E.combat = true; E:Click(transfer, transfer.Move, row); eq(#E.writes, 1, "combat transfer refused"); E.combat = false
E:Click(transfer, transfer.Move, row); E:Emit(transfer, "BANKFRAME_CLOSED")
eq(transfer.pending, nil, "close cancels pending")
eq(transfer.context.events.BAG_UPDATE_DELAYED, nil, "closed bank stops inventory event work")
eq(transfer.context.events.CURSOR_CHANGED, nil, "closed bank stops cursor event work")
BankFrame:Hide()

-- Grouped bank transfers use the displayed physical candidates, not a fresh inventory scan.
local question
S.Confirm = function(_, data) question = data end
S.HideQuestion = function() question = nil end
local function Stack(bag, slot, id, count)
    E:Item(bag, slot, id, count)
    return { bag = bag, slot = slot, itemID = id, count = count, link = "item:" .. id }
end
local function ConfirmBatch(items, direction, expected)
    question = nil
    E:Click(transfer, transfer.Batch, items, direction)
    eq(question and question.text_arg1 or 0, expected, "approved physical stack count")
    return question
end
local function Accept()
    local approved = question
    question = nil
    E:Click(transfer, function() approved.callback() end)
end
local function WriteCount(expected, label) eq(#E.writes, expected, label) end

E.bankType = 1
BankFrame:Show()
E:Emit(transfer, "BANKFRAME_OPENED")
eq(type(transfer.context.events.BAG_UPDATE_DELAYED), "function", "reopening resumes inventory acknowledgement")
local first, second, unmatched = Stack(0, 1, 12, 8), Stack(0, 2, 13, 4), Stack(0, 3, 14, 2)
local prior, scanned = #E.writes, E.calls.scan
local canBatch, activeBank = transfer:CanBatch()
eq(canBatch, true, "active bank can transfer")
eq(activeBank, 1, "menu can scope matches to the native bank")
StackSplitFrame:Show()
ConfirmBatch({ first }, "deposit", 0)
StackSplitFrame:Hide()
E.targeting = true
ConfirmBatch({ first }, "deposit", 0)
E.targeting = E.secret
ConfirmBatch({ first }, "deposit", 0)
E.targeting = nil
E.bags[0][unmatched.slot].isFiltered = true
ConfirmBatch({ unmatched }, "deposit", 0)
E.bags[0][unmatched.slot].isFiltered = false
local approval = ConfirmBatch({ first, first, second }, "deposit", 2)
WriteCount(prior, "preview never moves items")
Accept()
WriteCount(prior + 2, "same click issues both unique approved stacks")
eq(E.calls.scan, scanned, "batch uses exact candidates without rescanning containers")
eq(E.writes[prior + 1][5], 1, "native deposit uses confirmed bank type")
E:Click(transfer, function() approval.callback() end)
WriteCount(prior + 2, "duplicate confirmation cannot issue the batch again")
E.bags[0][1] = nil
E:Emit(transfer, "BAG_UPDATE_DELAYED")
eq(transfer.pending.updated, 1, "first accepted stack acknowledged")
WriteCount(prior + 2, "acknowledgement events never issue writes")
E.bags[0][2] = E.secret
E:Emit(transfer, "BAG_UPDATE_DELAYED")
eq(transfer.pending.updated, 1, "unknown slot is not an acknowledgement")
E:Flush()
eq(E.message:find("1 of 2", 1, true) ~= nil, true, "timeout reports the observed partial transfer")
eq(E.bags[0][unmatched.slot].itemID, 14, "nonmatching item remains untouched")

first, second = Stack(0, 1, 12, 8), Stack(0, 2, 13, 4)
ConfirmBatch({ first, second }, "deposit", 2)
E.bags[0][first.slot].guid = "different item instance"
Accept()
WriteCount(prior + 3, "same-ID replacement is skipped at confirmation")
eq(E.writes[prior + 3][3], second.slot, "the unchanged stack can still move")
E:Flush()

ConfirmBatch({ first, second }, "deposit", 2)
E.bankType = 2
Accept()
WriteCount(prior + 3, "changed destination never moves approved stacks")
ConfirmBatch({ first, second }, "deposit", 2)
E.refundable = true
Accept()
WriteCount(prior + 3, "newly refundable account deposit stays native")
E.refundable = false

E.free = 1
ConfirmBatch({ first, second }, "deposit", 1)
question.cancelCallback()
eq(transfer:CanBatch(), true, "cancel leaves the next explicit batch available")
E.free = 8
local stale = ConfirmBatch({ first }, "deposit", 1)
E:Emit(transfer, "BANKFRAME_CLOSED")
E:Emit(transfer, "BANKFRAME_OPENED")
E:Click(transfer, function() stale.callback() end)
WriteCount(prior + 3, "bank reopen invalidates earlier confirmation")
ConfirmBatch({ first, second }, "deposit", 2)
E.combat = true
Accept()
WriteCount(prior + 3, "combat invalidates an open confirmation")
E.combat = false
ConfirmBatch({ first, second }, "deposit", 2)
E.conflict = "MerchantFrame"
Accept()
WriteCount(prior + 3, "competing item windows cannot repurpose a transfer")
E.conflict = nil
ConfirmBatch({ first, second, unmatched }, "deposit", 3)
local native = S.QoLRestrictedCall
local attempted = 0
S.QoLRestrictedCall = function(...)
    attempted = attempted + 1
    if attempted == 2 then return false end
    return native(...)
end
Accept()
S.QoLRestrictedCall = native
WriteCount(prior + 4, "first refused native action stops the batch")
E.bags[0][1] = nil
E:Emit(transfer, "BAG_UPDATE_DELAYED")
eq(E.message:find("1 of 3", 1, true) ~= nil, true, "refusal is reflected in the confirmed count")

local bankItem = Stack(13, 1, 15, 3)
ConfirmBatch({ second, bankItem }, "withdraw", 1)
Accept()
WriteCount(prior + 5, "only physical items in the selected bank are withdrawn")
eq(E.writes[prior + 5][2], 13, "withdrawal uses the selected bank source")
E:Emit(transfer, "BANKFRAME_CLOSED")
E:Emit(transfer, "BANKFRAME_OPENED")
first, second = Stack(0, 1, 12, 8), Stack(0, 2, 13, 4)
ConfirmBatch({ first, second }, "deposit", 2)
local use = C_Container.UseContainerItem
C_Container.UseContainerItem = function(bag, slot, ...)
    use(bag, slot, ...)
    E.bags[bag][slot] = nil
    E:Emit(transfer, "BAG_UPDATE_DELAYED")
end
Accept()
C_Container.UseContainerItem = use
WriteCount(prior + 7, "synchronous updates still allow all approved writes")
eq(transfer.pending, nil, "updates during issuance are reconciled before returning")
eq(E.message:find("2 of 2", 1, true) ~= nil, true, "synchronous updates are acknowledged")
eq(next(E.timers), nil, "a fully acknowledged synchronous batch needs no timeout")
E:Emit(transfer, "BANKFRAME_CLOSED")
BankFrame:Hide()

-- Exact mail quantities, known own recipient, native fields only on click, no SendMail path.
local mail = E:Start("mailTemplates", { templates = assert(Lists.EncodeTemplates({ template })) })
mail.selected = 1; E.guid, E.name = "player-a", "Alpha"
MailFrame:Show(); SendMailFrame:Show(); E:Emit(mail, "MAIL_SHOW")
E:Click(mail, mail.Fill); eq(SendMailNameEditBox:GetText(), "Beta-Realm", "own-alt recipient filled")
eq(SendMailSubjectEditBox:GetText(), "50%", "subject filled")
E:Item(0, 1, 12, 20)
E:Click(mail, mail.Attach, { itemID = 12 }); eq(E.attachments[1].count, 4, "exact material quantity split")
eq(E.bags[0][1].stackCount, 16, "remainder stays in bags")
local writes = #E.writes
E:Click(mail, mail.Attach, { itemID = 12 }); eq(#E.writes, writes, "no overattachment")
E:Item(0, 2, 13, 20)
SendMailNameEditBox:SetText("Stranger-Realm"); E:Click(mail, mail.Attach, { itemID = 13 })
eq(#E.writes, writes, "edited recipient blocks attachment")
E:Emit(mail, "MAIL_CLOSED"); E:Click(mail, mail.Attach, { itemID = 13 })
eq(#E.writes, writes, "closed mail refuses")
mail.preview = false; mail:Open()
for _, frame in ipairs(E.frames) do if frame.owner == mail and frame.actions then window = frame end end
window.buttons[1]:Click(); window.actions[4]:Click(); window.buttons[1]:Click(); window.actions[2]:Click()
local mailEditor
for _, frame in ipairs(E.frames) do if frame.owner == mail and frame.input then mailEditor = frame end end
mailEditor.input:SetText("9")
local replacement = { name = "Other", recipient = "Gamma-Realm", subject = "Other", items = "12=2" }
mail.config.templates = Lists.EncodeTemplates({ replacement })
save:Click()
eq(Lists.Templates(mail.config.templates)[1].items, "12=2", "stale template quantity never changes another template")
local forever = F.New(root, true)
local foreverTransfer = forever:Start("bankTransfer", {})
BankFrame:Show()
forever:Emit(foreverTransfer, "BANKFRAME_OPENED")
forever:Item(0, 1, 12)
forever:Item(5, 1, 13)
eq(#foreverTransfer:Rows(), 1, "Forever's first bank bag is excluded from carried rows")
eq(foreverTransfer:CanBatch(), true, "Forever supports grouped bank transfers")
local foreverQuestion
forever.S.Confirm = function(_, data) foreverQuestion = data end
forever:Click(foreverTransfer, foreverTransfer.Batch, {
    { bag = 0, slot = 1, itemID = 12, count = 1 },
    { bag = 5, slot = 1, itemID = 13, count = 1 },
}, "deposit")
eq(foreverQuestion.text_arg1, 1, "Forever never deposits a slot of its own bank")
forever:Click(foreverTransfer, function() foreverQuestion.callback() end)
eq(#forever.writes, 1, "Forever confirm issues one native deposit")
eq(forever.writes[1][2], 0, "Forever deposit uses the actual carried slot")
BankFrame:Hide()
eq(forever.S.instances.mailTemplates, nil, "mail templates Retail-only")
eq(forever.S.instances.craftShopping, nil, "recipe shopping Retail-only")
print("inventory tools: " .. checks .. " behavior checks")
