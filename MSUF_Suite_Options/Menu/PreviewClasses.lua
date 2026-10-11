local _, P = ...
local Classes = {}
P.PreviewClasses = Classes
-- IDs are examples only. No player spellbook, saved list or specialization
-- is changed when another class is selected in the menu.
local DATA = {
    { "WARRIOR", 1, 6673, 1719, 871, 132333 },
    { "PALADIN", 2, 465, 31884, 642, 135920 },
    { "HUNTER", 3, 13165, 19574, 5384, 132164 },
    { "ROGUE", 4, 2823, 13750, 5277, 132273 },
    { "PRIEST", 5, 21562, 10060, 17, 135940 },
    { "DEATHKNIGHT", 6, 57330, 48792, 49028, 135771 },
    { "SHAMAN", 7, 462854, 2825, 108271, 136052 },
    { "MAGE", 8, 1459, 12472, 45438, 135932 },
    { "WARLOCK", 9, 20707, 104773, 1122, 136145 },
    { "MONK", 10, 115921, 137639, 115203, 608951 },
    { "DRUID", 11, 1126, 22812, 106951, 136096 },
    { "DEMONHUNTER", 12, 195072, 198589, 191427, 1247262 },
    { "EVOKER", 13, 364342, 357208, 363916, 4622458 },
}
function Classes.Choices()
    local choices = { { value = "", text = P.Tr("Your character") } }
    for _, row in ipairs(DATA) do
        local info = C_CreatureInfo.GetClassInfo(row[2])
        local name = info and info.className or LOCALIZED_CLASS_NAMES_MALE[row[1]]
        if type(name) == "string" then choices[#choices + 1] = { value = row[1], text = name } end
    end
    return choices
end
function Classes.Sample(token)
    if token == "" then return nil end
    for _, row in ipairs(DATA) do
        if row[1] == token then return row end
    end
end
function Classes.Bind(ui, parent, x, y, width, page, module, section, refresh)
    local selected = ""
    return P.M.BindDropdownAt(ui.ctx, parent, P.Tr("Preview class"), x, y, Classes.Choices(), width,
        function() return selected end, function(value)
            selected = value
            ui.previewClass = Classes.Sample(value)
            refresh()
        end, P.Meta(page, module, "preview.class", "ephemeral", section))
end
