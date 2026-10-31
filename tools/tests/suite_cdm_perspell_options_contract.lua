-- Per-spell rules in the popover (package cdm11-C): each new row shows
-- where the runtime reads it (cooldowns, spells only, items only, buffs,
-- bars), sits in its section, keeps a specialization's explicit values
-- apart from inheriting, and the bar name box stores plain text only. The
-- rows are made on the first open or search, not at load. Reuses the
-- options contract's Menu2 world up to its popover checks.
local root = assert(arg[1]):gsub("\\", "/")
local file = assert(io.open(root .. "/tools/tests/suite_cooldown_manager_options_contract.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local stop = assert(source:find("------------------------------------------------------------------ per-spell popover", 1, true))
source = source:sub(1, stop - 1) .. [[
return { Page = Page, P = P, CDM = CDM, Config = Config, Fire = Fire, Grid = grid, Dropdown = function() return lastDropdown end }
]]
local world = assert(loadstring(source, "@perspell-world"))()
local Page, CDM, Fire = world.Page, world.CDM, world.Fire
local config = world.Config()
local NEW = { "usableOnly", "procOnly", "missingGlow", "activeBorder", "itemAura", "barColor", "barText", "usedSound", "chargeSound" }

-- The rows of the popover file: the new ones only inside the function that
-- makes them on the first open or search.
local handle = assert(io.open(root .. "/MSUF_Suite_Options/Pages/CooldownManagerPopoverFields.lua", "rb"))
local text = handle:read("*a"):gsub("\r", "")
handle:close()
local lazy = assert(text:match("\nlocal function MoreFields%(%)\n(.-)\nend\n"), "the lazy rows")
for _, key in ipairs(NEW) do
    assert(lazy:find('key = "' .. key .. '"', 1, true) and select(2, text:gsub('key = "' .. key .. '"', "")) == 1,
        key .. ": made lazily, once")
end
Page.CompleteFields()
Page.CompleteFields()
local count = {}
for _, field in ipairs(Page.FIELDS) do count[field.key] = (count[field.key] or 0) + 1 end
for _, key in ipairs(NEW) do assert(count[key] == 1, key .. " has one row") end

local anchor = assert(world.Grid:Tile("b1"))
local tile = { key = "b1", family = CDM.FAMILY.COOLDOWN, aura = true, name = "Fireball", texture = 1001 }
local function Open(key, slot, family, aura)
    if Page.popover and Page.popover:IsShown() then Page.popover:Hide() end
    Page.selected, tile.key, tile.family, tile.aura = slot, key, family, aura
    assert(Page.TogglePopover(tile, anchor))
    return Page.popover
end
local function Shown(pop, key) return pop.rows[key] ~= nil and pop.rows[key]:IsShown() end
local function Expect(pop, label, want)
    for key, on in pairs(want) do
        assert(Shown(pop, key) == on, label .. ": " .. key .. (on and " must show" or " must not show"))
    end
end
config.spellsData = ""
-- A Blizzard cooldown with a buff on cooldown icons.
local pop = Open("b1", "ess", CDM.FAMILY.COOLDOWN, true)
Expect(pop, "cooldown icon", { usableOnly = true, procOnly = true, usedSound = true, chargeSound = true, activeBorder = true,
    missingGlow = false, itemAura = false, barColor = false, barText = false })
assert(not pop.rows.activeBorder.dimmed, "the bar shows the buff: the active border applies")
config.ess_showAura = false
Page.PaintPopover()
assert(pop.rows.activeBorder.dimmed, "the active border waits for \"Show active buff duration\"")
config.ess_showAura = true
assert(pop.rows.usableOnly.field.section.label == "Appearance" and pop.rows.procOnly.field.section.label == "Appearance"
    and pop.rows.activeBorder.field.section.label == "Buff and stacks" and pop.rows.usedSound.field.section.label == "Sounds"
    and pop.rows.chargeSound.field.section.label == "Sounds", "sections")
-- Timer bars draw bars: their color and name apply.
config.ess_cooldownDuration = true
Page.PaintPopover()
Expect(pop, "timer bars", { barColor = true, barText = true })
config.ess_cooldownDuration = false
-- An item: its use buff and its cooldown sound, no spell rules.
pop = Open("i5512", "ess", CDM.FAMILY.COOLDOWN, false)
Expect(pop, "item", { itemAura = true, usedSound = true, usableOnly = false, procOnly = false, chargeSound = false })
assert(pop.rows.itemAura.field.section.label == "Buff and stacks", "the item's buff row")
-- A buff on a buff bar.
pop = Open("a1126", "bar", CDM.FAMILY.AURA, true)
Expect(pop, "buff bar", { missingGlow = true, activeBorder = true, barColor = true, barText = true, usableOnly = false,
    usedSound = false, itemAura = false })
assert(not pop.rows.activeBorder.dimmed and pop.rows.missingGlow.field.section.label == "Glow", "buff rows")

-- Switches store On or nothing; a specialization stores Off over a shared On.
local function Effective(key) return CDM.EffectiveSpells(CDM.Codec.DecodeSpells(config.spellsData), Page.Spec())[key] or {} end
config.spellsData = ""
Page.spellSpecScope = false
pop = Open("b1", "ess", CDM.FAMILY.COOLDOWN, true)
local row = pop.rows.usableOnly
Fire(row.on, "OnClick")
assert(Page.SpellField("b1", "usableOnly") == true and row.reset:IsShown(), "On")
Fire(row.off, "OnClick")
assert(Page.SpellField("b1", "usableOnly") == nil, "Off clears a shared switch")
Fire(row.on, "OnClick")
Fire(pop.scopeButton, "OnClick")
assert(Page.spellSpecScope, "specialization scope")
Fire(row.off, "OnClick")
assert(Page.SpellField("b1", "usableOnly") == false and Effective("b1").usableOnly == false, "explicit Off over shared On")
Fire(row.reset, "OnClick")
assert(Page.SpellField("b1", "usableOnly") == true, "Reset inherits the shared On")
-- Colors: the chosen one clicked again follows the bar ("" in a specialization).
Page.spellSpecScope = false
config.ess_cooldownDuration = true
Page.PaintPopover()
row = pop.rows.barColor
Fire(row.swatches[3], "OnClick")
assert(Page.SpellField("b1", "barColor") == "ff4d4d", "a shared bar color")
Fire(pop.scopeButton, "OnClick")
Fire(row.swatches[3], "OnClick")
assert(Page.SpellField("b1", "barColor") == "" and Effective("b1").barColor == "", "the bar's color over the shared one")
Fire(row.reset, "OnClick")
assert(Page.SpellField("b1", "barColor") == "ff4d4d", "Reset inherits it")
Fire(pop.scopeButton, "OnClick")
-- The bar name box: plain text up to 40 characters, Enter stores it.
row = pop.rows.barText
local edit = assert(row.edit, "the name box")
local function Type(value)
    edit.focus = true
    edit:SetText(value)
    Fire(edit, "OnTextChanged", true)
    Fire(edit, "OnEnterPressed")
end
Type("Big hit")
assert(Page.SpellField("b1", "barText") == "Big hit", "a name is stored")
Type("a|cffff0000b")
assert(Page.SpellField("b1", "barText") == "Big hit" and edit.dirty, "an escape sequence is refused and stays for correction")
Type("")
assert(Page.SpellField("b1", "barText") == nil, "empty: the spell's name")
config.ess_cooldownDuration = false
config.spellsData = ""
pop:Hide()
print("suite_cdm_perspell_options_contract: ok")
