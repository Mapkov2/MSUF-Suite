local root = assert(arg[1])
local F = dofile(root .. "/tools/tests/suite_inventory_tools_fixture.lua")
local E = F.New(root)
E.S.InventoryData = nil
local loaded = {}
for line in io.lines(root .. "/MSUF_Suite_QualityOfLife/MSUF_Suite_QualityOfLife_Mainline.toc") do
    line = line:gsub("\r$", "")
    if line == "InventoryProtection.lua" or line == "InventoryData.lua" then
        loaded[#loaded + 1] = line
        E:Load("MSUF_Suite_QualityOfLife/" .. line)
    end
end
assert(table.concat(loaded, ",") == "InventoryProtection.lua,InventoryData.lua", "probe lost native TOC ordering")
local protection = E:Start("inventoryProtection", { items = "500=1", sets = false })
E:Item(0, 1, 500, 1, 0)
assert(E.S.InventoryData and protection:IsProtected(500, 0, 1), "fixture lacks the real late provider or protection")
print("providers loaded in shipped TOC order: " .. table.concat(loaded, ", "))
assert(protection:HasProtectedJunk(), "protected junk should block the Suite's native bulk sale")

-- The own item-list rows also resolve the late provider when the user opens them.
local spec
E.S.ToolListWindow.Open = function(_, value) spec = value end
protection:Open()
local rows = spec.rows()
assert(#rows == 1 and rows[1].itemID == 500 and rows[1].label,
    "the protection list could not resolve its late data provider")
print("Suite inventory protection: shipped provider order, junk safety and list rows passed")
