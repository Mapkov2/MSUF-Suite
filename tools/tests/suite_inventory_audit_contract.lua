-- The inventory and everyday tools' catalog, profile and menu contracts, on the
-- real Suite core and options pages (the runtime half is
-- suite_inventory_audit_archive_contract.lua):
--  * mail template data names the player's characters, so a profile export and
--    a shared import blank it, and the player's own copy keeps it;
--  * every inventory and everyday tool is declared in the addon that installs
--    it, and enabling the notice history loads no Quality of Life addon;
--  * "Reset section" on a tool restores its settings and keeps whether it runs:
--    the never-sell list stays protecting.
-- Usage: lua suite_inventory_audit_contract.lua <Suite root>
local root = assert(arg[1], "repository root required")
arg[3] = "ownership"
local E = assert(loadfile(root .. "/tools/tests/suite_options_menu_contract.lua"))()
local P, S, Suite = E.P, E.S, E.Suite
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checks = 0
local function Check(value, label)
    assert(value, label)
    checks = checks + 1
end

------------------------------------------------------------------ personal data
-- The codec is MSUF's; a table stands in for its string.
local encoded = {}
MSUF_EncodeCompactTable = function(value) encoded[#encoded + 1] = value; return "MSUF3:" .. #encoded end
MSUF_TryDecodeCompactString = function(text) return encoded[tonumber(text:match("^MSUF3:(%d+)$"))] end
local IO = Suite.ProfileIO
local templates = assert(Suite.InventoryLists.EncodeTemplates({
    { name = "Mats", recipient = "Beta-Realm", subject = "Weekly", items = "12=4" } }))
local rule = S.catalog.mailTemplates.rules.templates
Check(rule.personal == true and rule.hidden == true, "template data is not marked personal")
S.Config("mailTemplates").templates = templates

local profile = MSUF_TryDecodeCompactString(assert(IO.ExportProfile()):sub(#IO.prefix + 1)).profile
Check(profile.suite.modules.mailTemplates.templates == "", "a profile export carried recipient names")
local module = assert(IO.ExportModule("mailTemplates"))
Check(MSUF_TryDecodeCompactString(module:sub(8)).settings.templates == "", "a module export carried recipient names")
Check(S.Config("mailTemplates").templates == templates, "the export cleared the live templates")

local function Modules(text) return { suite = { schema = 1, modules = { mailTemplates = { templates = text } } } } end
Check(IO.PrepareTable(Modules(templates), true).suite.modules.mailTemplates.templates == "",
    "a shared import took someone else's recipient names")
Check(IO.PrepareTable(Modules(templates), false).suite.modules.mailTemplates.templates == templates,
    "the player's own copy lost the templates")
local _, settings = IO.PrepareModuleProfile("MSUFM2:" .. MSUF_EncodeCompactTable({ addon = "MSUF_Suite", format = 2,
    module = "mailTemplates", settings = { templates = templates } }), true)
Check(settings.templates == nil, "a shared module import took recipient names")

------------------------------------------------------------------ module ownership
-- The addon a module's catalog entry names is the addon whose TOC loads the
-- file that installs it.
local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end
local function Installer(addon, id)
    for _, file in ipairs(Support.TocFiles(root, addon)) do
        if file:match("%.lua$") and Read(addon .. "/" .. file):find('S.Install("' .. id .. '"', 1, true) then
            return file
        end
    end
end
for _, source in ipairs({ P.InventoryToolGroups, P.EverydayToolGroups }) do
    for _, group in ipairs(source) do
        local addon = S.catalog[group.id].addon
        Check(Installer(addon, group.id), group.id .. " is declared in " .. addon .. ", which does not install it")
    end
end
Check(S.catalog.notificationHistory.addon == "MSUF_Suite_Modules", "the notice history names the wrong addon")

-- Enabling a module loads the shared runtime and the addon its entry names.
local loads, previousLoad, previousContext = {}, C_AddOns.LoadAddOn, S.NewContext
C_AddOns.LoadAddOn = function(name)
    loads[#loads + 1] = name
    if name == "MSUF_Suite_Modules" then S.NewContext = S.NewContext or function() return {} end end
    return true
end
local function Loaded(addon)
    for i = 1, #loads do if loads[i] == addon then return true end end
    return false
end
Check(S.Set("notificationHistory", "enabled", true), "the notice history could not be switched on")
Check(Loaded("MSUF_Suite_Modules") and not Loaded("MSUF_Suite_QualityOfLife"),
    "the notice history loaded the Quality of Life addon: " .. table.concat(loads, ", "))
Check(S.Set("inventoryProtection", "enabled", true), "never-sell could not be switched on")
Check(Loaded("MSUF_Suite_QualityOfLife"), "never-sell no longer loads its own addon")
for _, id in ipairs({ "notificationHistory", "inventoryProtection" }) do S.Set(id, "enabled", false) end
C_AddOns.LoadAddOn, S.NewContext = previousLoad, previousContext

------------------------------------------------------------------ section resets
-- Never-sell, on the Quality of Life page: the reset restores "Protect items in
-- equipment sets" and leaves protection on, with its list.
local qol = E.build("suite_qualityOfLife")
local record = assert(qol.qualityOfLifeFeatureRows.suite_qualityOfLife_inventoryProtection_inventoryProtection)
E.inContext(qol, function() record.reveal(true) end)
local protection = S.Config("inventoryProtection")
protection.enabled, protection.sets, protection.items = true, false, "12=1"
E.inContext(qol, function()
    Check(record.details._msufSuiteSectionReset(), "the never-sell section reset failed")
end)
Check(protection.sets == S.catalog.inventoryProtection.rules.sets.default, "the section reset missed a setting")
Check(protection.enabled == true, "the section reset switched never-sell off")
Check(protection.items == "12=1", "the section reset cleared the protected items")
protection.enabled = false

-- The tools the Bags page owns reset the same way.
local bags = E.build("suite_bags")
local function Section(ctx, id)
    for _, section in ipairs(ctx.sections) do
        if section.sectionId == id then return section end
    end
    error("no section " .. id)
end
local archive, transfer = S.Config("inventoryArchive"), S.Config("bankTransfer")
archive.enabled, archive.characters, transfer.enabled = true, 50, true
E.inContext(bags, function()
    Check(Section(bags, "suite_bags_inventoryArchive_module")._msufSuiteSectionReset(), "the archive reset failed")
    Check(Section(bags, "suite_bags_bankTransfer_module")._msufSuiteSectionReset(), "a tool without settings failed to reset")
end)
Check(archive.characters == S.catalog.inventoryArchive.rules.characters.default, "the archive reset missed a setting")
Check(archive.enabled == true and transfer.enabled == true, "a tool reset switched the tool off")
archive.enabled, transfer.enabled = false, false

print("inventory audit: " .. checks .. " contract checks")
