local root = assert(arg[1])
local originalLoad = loadfile
loadfile = function(path)
    if path:find("MSUF_Suite_CooldownManager/Time.lua", 1, true) then
        GetInventoryItemCooldown = function() return 0, 0, 1 end
    end
    return originalLoad(path)
end
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
do (function()
local selected = os.getenv("TRINKET_CASE") or "all"
local config = S.Config(ID)
Info(72, nil, 7, { equipSlot = 14 })
sets[7][2] = 72
GetInventoryItemCooldown = function() return 0, 0, 1 end
module.config, module.context, module.active = config, S.NewContext(ID), true
module:Enable()
Run()
config.raidEssentials, config.ess_maxIcons = false, 1
local spec = C.state.specID
local options = { Suite = Suite, S = S, T = {}, M = {}, catalog = Suite.SuiteCatalog,
    Gates = {}, SearchPreparers = {}, Tr = function(text) return text end,
    Combat = function() return combat == true end, Refresh = function() end,
    WithHistory = function(_, _, callback) return callback() end,
    Get = function(id, key) return S.Config(id)[key] end, Set = S.Set, SetMany = S.SetMany }
for _, name in ipairs({ "CooldownManagerData", "CooldownManagerLists", "CooldownManagerBars" }) do
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/" .. name .. ".lua"))("MSUF_Suite_Options", options)
end
local Page = options.CDMPage
Page.CommitFocus, Page.ClosePopups = function() end, function() end
local function Settle() module:Refresh(); Run() end
local function Edit(list, strict, slot)
    config.listsData = assert(Codec.EncodeLists({ specs = { [spec] = { [slot or "ess"] = list } },
        replace = { [spec] = { ess = strict } } }))
    Settle()
end
local function Has(key)
    for _, value in ipairs(C.Resolve.Keys("ess")) do if value == key then return true end end
    return false
end
assert(S.CooldownManagerSetPreview(true, function() end))
local stage = CreateFrame("Frame")
if selected == "all" or selected == "preview" then
    Edit({ "b11", "b13", "e13", "e14" }, true)
    local holder = assert(S.CooldownManagerRenderPreview(stage, "ess", 600, 200))
    assert(holder.count == 4 and holder.keys[3] == "e13" and holder.keys[4] == "e14",
        "the menu preview must expose both trinkets beyond the live cap")
    for i = 1, holder.count do assert(holder.keys[i] ~= false, "sample icons must not replace tracked equipment") end
    local layout = holder.layoutView
    S.CooldownManagerRenderPreview(stage, "ess", 600, 200)
    assert(holder.layoutView == layout and C.views.ess.maxIcons == 1 and config.ess_maxIcons == 1,
        "full editor layout must preserve the live cap and reuse its view")
    local visible = 0
    for _, entry in ipairs(C.plans.ess.entries) do if entry.icon and entry.icon.shown then visible = visible + 1 end end
    assert(visible == 1, "the live preview bar must still respect its icon cap")
    Edit({}, true)
    holder = S.CooldownManagerRenderPreview(stage, "ess", 600, 200)
    assert(holder.count == 3 and holder.keys[1] == false, "a genuinely empty bar keeps layout samples")
    assert(Page.AddEntry("ess", "e13", 1))
    Settle()
    holder = S.CooldownManagerRenderPreview(stage, "ess", 600, 200)
    assert(holder.count == 1 and holder.keys[1] == "e13" and holder.keys[2] == nil,
        "adding a trinket must immediately replace every sample")
    for i = 2, #holder.icons do assert(not holder.icons[i].shown, "old sample icon remained over a trinket") end
end
if selected == "all" or selected == "aliases" then
    for _, item in ipairs({ { "e13", "b71" }, { "e14", "b72" } }) do
        local key, native = item[1], item[2]
        Edit(nil)
        assert(Page.AddEntry("ess", key, 1))
        Settle()
        assert(Has(key) and not Has(native), "adding an equipment slot must replace its duplicate Blizzard record")
        local before = config.listsData
        assert(Page.RemoveWithUndo("ess", key, key))
        Settle()
        assert(not Has(key) and not Has(native), "removing a trinket must remove both stored identities")
        Page.RunUndo()
        Settle()
        assert(config.listsData == before and Has(key), "Undo must restore the exact tracked trinket")
        assert(Page.RemoveEntry("ess", key))
        Settle()
        assert(not Has(key) and not Has(native), "removing again must not resurrect the native item")
        Fire("PLAYER_EQUIPMENT_CHANGED", tonumber(key:sub(2)))
        Run()
        assert(not Has(key) and not Has(native), "an equipment refresh must preserve removal")
        assert(Page.AddEntry("ess", key, 1))
        Settle()
        assert(Has(key) and not Has(native), "the removed trinket must remain available to add again")
        assert(Page.AddEntry("ess", native, 1))
        Settle()
        assert(Has(native) and not Has(key), "adding the native record must also replace an existing equipment slot")
        assert(Page.AddEntry("ess", key, 1))
        Settle()
        assert(Has(key) and not Has(native), "switching back to a slot must remain deduplicated")
        Edit({ native, key }, true)
        assert(Page.RemoveEntry("ess", native))
        Settle()
        assert(not Has(key) and not Has(native), "legacy duplicate lists must be removable from either icon")
    end
    config.c1_on = true
    Edit({ "e13" }, nil, "c1")
    assert(Page.RemoveEntry("c1", "e13"))
    Settle()
    local hidden = Page.ListsView().hidden[spec] or {}
    assert(not hidden.e13 and not hidden.b71 and Has("b71"), "custom-bar removal must retain the native fallback")
end
if selected == "all" or selected == "removal" then
    Edit({ "b71", "e13" }, false)
    assert(Page.RemoveEntry("ess", "e13"))
    Settle()
    assert(not Has("e13") and not Has("b71"), "removing a legacy slot must also remove its native trinket")
end
if selected == "all" or selected == "move" then
    config.c1_on = true
    Edit({ "b11", "b71", "e13", "b12" }, true)
    assert(Page.MoveEntry("e13", "ess", "b71", 1))
    Settle()
    assert(table.concat(C.Resolve.Keys("ess"), ",") == "b11,e13,b12",
        "reordering a legacy slot must preserve the alias's insertion point and deduplicate")
    assert(Page.MoveEntry("e13", "c1", nil, 1))
    Settle()
    assert(not Has("e13") and not Has("b71") and table.concat(C.Resolve.Keys("c1"), ",") == "e13",
        "moving the slot must not leave its native identity on the old bar")
end
if selected == "all" or selected == "future" then
    Edit(nil)
    assert(Page.AddEntry("ess", "e13", 1))
    Settle()
    assert(Page.RemoveEntry("ess", "e13"))
    Settle()
    Info(99, nil, 7, { equipSlot = 13 })
    sets[7] = { 99, 72 }
    Fire("PLAYER_EQUIPMENT_CHANGED", 13)
    Run()
    assert(C.Catalog.records[99] and not Has("b99"),
        "a new native cooldown ID must not revive a removed equipment slot")
end
if selected == "all" or selected == "foreign" then
    local profile = Suite.Database.GetActiveProfileName()
    local saved = {
        { key = "b99", name = "Later trinket", texture = 4444, family = 1, slot = "ess", known = true, equipSlot = 13 },
        { key = "b31", name = "Trinket buff", texture = 4444, family = 2, slot = "buf", known = true, equipSlot = 13 },
    }
    saved.defaults, saved.knownSpells = { ess = { "b99" }, buf = { "b31" } }, {}
    Suite.RootDB.cdmEditorCatalog = Suite.RootDB.cdmEditorCatalog or {}
    Suite.RootDB.cdmEditorCatalog[profile] = { [266] = saved }
    config.listsData = assert(Codec.EncodeLists({ hidden = { [266] = { e13 = true } } }))
    local context = S.CooldownManagerEditorContext(266, 9)
    for _, row in ipairs(context.bars.ess) do
        assert(row.key ~= "b99", "a foreign spec must honor a removed slot even when its native record is new")
    end
    local buff = false
    for _, row in ipairs(context.bars.buf) do if row.key == "b31" then buff = true end end
    assert(buff, "hiding a cooldown slot must preserve its separate buff entry")
end
S.CooldownManagerReleasePreview(stage)
S.CooldownManagerSetPreview(false)
Run()
module.active = false
module:Disable()
print("suite_cdm_trinket_contract: " .. selected .. " passed")
end)() end
]=], "------------------------------------------------------------------ enable: capture")
loadfile = originalLoad
