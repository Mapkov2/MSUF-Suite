-- A loaded vendor addon does not own repair/sales while its automation is off.
local root = assert(arg[1], "repository root required")
SUITE_OPTIONS_FIXTURE = true
local F = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
SUITE_OPTIONS_FIXTURE = nil
local NS, P, M = F.Suite, F.optionsNS, F.M
local V = P.QoLView
local loaded = {}
local originalLoaded = NS.Client.IsAddOnLoaded
NS.Client.IsAddOnLoaded = function(name)
    if loaded[name] ~= nil then return loaded[name] end
    return originalLoaded(name)
end
local ctx = { key = "suite_qualityOfLife", width = 1200, refreshers = {}, widgets = {},
    sections = {}, pageItems = {}, entry = { sections = {} } }
F.SetCurrent(ctx)
M.RequestRefresh = function()
    for _, refresh in ipairs(ctx.refreshers) do refresh() end
end
M.pages.suite_qualityOfLife.build(ctx)
local ui = assert(ctx.entry.qualityOfLifeView)
assert(ui:SelectCategory("lootMerchants"))
local repair = assert(ui.rows[V.FeatureSectionId(V.FindFeature("qol", "repair"))])
local junk = assert(ui.rows[V.FeatureSectionId(V.FindFeature("qol", "autoJunk"))])
local checks = 0
local function Available(expected, reason)
    local ok, why = F.S.Availability("qol")
    assert(ok == expected and why == reason, tostring(ok) .. ": " .. tostring(why))
    P.ForgetAvailability()
    ui:SetFilter("all")
    assert(repair.row:IsShown() == expected and junk.row:IsShown() == expected,
        "merchant rows disagree with actual automation availability")
    checks = checks + 1
end

loaded.EnhanceQoLVendor = true
EnhanceQoL = { db = { autoRepair = false, sellAllJunk = false,
    vendorIncludeSellList = {}, vendorBulkBuy = true, vendorShowSellOverlay = true } }
Available(true)
for _, key in ipairs({ "autoRepair", "sellAllJunk", "vendorPoorEnable", "vendorCommonEnable",
    "vendorUncommonEnable", "vendorRareEnable", "vendorEpicEnable" }) do
    EnhanceQoL.db[key] = true
    Available(false, "Managed by EnhanceQoLVendor")
    EnhanceQoL.db[key] = false
    Available(true)
end
EnhanceQoL.db.vendorIncludeSellList[6948] = true
Available(false, "Managed by EnhanceQoLVendor")
EnhanceQoL.db.vendorIncludeSellList = {}
Available(true)

-- Missing or unreadable foreign state keeps the existing conflict refusal.
local db = EnhanceQoL.db
EnhanceQoL.db = nil
Available(false, "Managed by EnhanceQoLVendor")
EnhanceQoL = nil
Available(false, "Managed by EnhanceQoLVendor")
EnhanceQoL = { db = db }
local secret, originalSecret = {}, NS.IsSecret
NS.IsSecret = function(value) return value == secret or originalSecret(value) end
EnhanceQoL.db.autoRepair = secret
Available(false, "Managed by EnhanceQoLVendor")
EnhanceQoL.db.autoRepair = false
EnhanceQoL.db.vendorIncludeSellList = secret
Available(false, "Managed by EnhanceQoLVendor")
EnhanceQoL.db.vendorIncludeSellList = { [secret] = true }
Available(false, "Managed by EnhanceQoLVendor")
EnhanceQoL.db.vendorIncludeSellList = {}
NS.IsSecret = originalSecret

loaded.EnhanceQoLVendor = false
EnhanceQoL.db.autoRepair = true
loaded.EnhanceQoL = true
Available(false, "Managed by EnhanceQoL")
EnhanceQoL.db.autoRepair = false
EnhanceQoL.db.sellAllJunk = true
Available(true)
loaded.EnhanceQoL = false
EnhanceQoL.db.autoRepair = true
Available(true)
for _, name in ipairs({ "Scrap", "SellJunk" }) do
    loaded[name] = true
    Available(false, "Managed by " .. name)
    loaded[name] = false
    Available(true)
end

-- Use the real availability predicate at the runtime's visit boundary too.
loaded.EnhanceQoLVendor, loaded.EnhanceQoL = true, true
EnhanceQoL.db.autoRepair = false
EnhanceQoL.db.sellAllJunk = false
local repairs, sales, merchant = 0, 0
CanMerchantRepair = function() return true end
GetRepairAllCost = function() return 10000, true end
GetMoney = function() return 100000 end
RepairAllItems = function() repairs = repairs + 1 end
IsShiftKeyDown = function() return false end
C_MerchantFrame = {
    IsSellAllJunkEnabled = function() return true end,
    GetNumJunkItems = function() return 1 end,
    SellAllJunkItems = function() sales = sales + 1 end,
}
local runtime = { Public = NS.Public, Number = NS.Number, Finite = NS.Finite,
    Availability = F.S.Availability, Text = function(text) return text end,
    InventoryProtection = { HasProtectedJunk = function() return false end } }
runtime.Install = function(id, module) assert(id == "qol"); merchant = module end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/Merchant.lua"))("Test", {
    NS = { IsCombatLocked = function() return false end, Print = function() end }, Suite = runtime })
merchant.config = { repair = true, autoJunk = true, repairLimit = 100 }
merchant.context = { events = {} }
function merchant.context:Event(name, callback) self.events[name] = callback end
function merchant.context:RemoveEvent(name) self.events[name] = nil end
merchant:Enable()
local function Visit()
    merchant.context.events.MERCHANT_SHOW(merchant, "MERCHANT_SHOW")
    merchant.context.events.MERCHANT_CLOSED(merchant, "MERCHANT_CLOSED")
end
Visit()
assert(repairs == 1 and sales == 1, "inactive EQoL blocked a normal merchant visit")
EnhanceQoL.db.autoRepair = true
Visit()
assert(repairs == 1 and sales == 1, "enabling EQoL repeated spending/selling in an already active Suite module")
EnhanceQoL.db.autoRepair = false
Visit()
assert(repairs == 2 and sales == 2, "turning EQoL back off did not restore Suite's next merchant visit")
EnhanceQoL.db.sellAllJunk = true
Visit()
assert(repairs == 2 and sales == 2, "enabling EQoL selling did not stop the already active Suite module")
EnhanceQoL.db.sellAllJunk = false
Visit()
assert(repairs == 3 and sales == 3, "turning EQoL selling back off did not restore the next merchant visit")
checks = checks + 5
NS.Client.IsAddOnLoaded = originalLoaded
EnhanceQoL = nil
print("PASS merchant availability " .. (arg[2] or "Mainline") .. ": " .. checks .. " cases")
