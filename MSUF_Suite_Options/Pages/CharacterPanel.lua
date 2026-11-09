local _, P = ...
local PAGE, ID = "suite_hud", "characterPanel"
local Header = P.S.CharacterHeader
local Editor = P.CharacterPanelEditor

function P.BuildHUDCharacterPanel(ctx, builder)
    local actions = {
        { "Character Panel colors", function() P.HUDMenu.OpenColors(ID) end, key = "colors" },
        { "Reset preview order", Editor.ResetOrder, key = "resetOrder" },
    }
    P.ModuleCard(ctx, builder, PAGE, ID, actions, {
        title = "Character Panel", prepareControl = P.HUDMenu.PrepareControl,
    })
    P.RuleSection(ctx, builder, PAGE, ID, PAGE .. "_" .. ID .. "_appearance", P.Tr("Appearance"),
        P.SectionRules(ID, "appearance", function(rule) return not rule.hidden end),
        { open = true, help = P.catalog[ID].description, onBuilt = P.HUDMenu.Prepare })
    local controls = P.catalog[ID].rules
    local sections = {}
    ctx.characterHeaderSections = sections
    for _, field in ipairs(Header.Fields) do
        local rules = {}
        for _, suffix in ipairs({ "Visible", "Size", "X", "Y", "Font", "Color" }) do
            local rule = controls[field.prefix .. suffix]
            if rule then rules[#rules + 1] = rule end
        end
        local section = Editor.FieldSection(field.id)
        local body = P.RuleSection(ctx, builder, PAGE, ID, section, field.label, rules, {
            onBuilt = P.HUDMenu.Prepare,
        })
        sections[field.id] = body
    end
end
