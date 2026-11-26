local _, P = ...
local PAGE = "auras3_styling"
local Bridge = P.Suite.HostBridge
local function Unsupported() return false end
if not Bridge.HasPlayerAuraMenu(P.M) then
    P.PlayerAurasPage = {
        registered = false, Open = Unsupported,
        FilterQualityOfLife = Unsupported, AppendSearchRows = Unsupported, Relocated = Unsupported,
    }
    return
end
local AuraMenu = {}
P.PlayerAurasPage = AuraMenu
local MODULES = { playerAuras = true, playerAuraSkins = true, playerBuffGroups = true }
local SECTIONS = {
    playerAuras = PAGE .. "_playerAuras_module",
    playerAuraSkins = PAGE .. "_playerAuraSkins_module",
    playerBuffGroups = PAGE .. "_playerBuffGroups_module",
}
local function SettingSection(id, rule)
    if id == "playerBuffGroups" and rule and rule.section and rule.section ~= "buff_group_layout" then
        return PAGE .. "_" .. rule.section
    end
    return SECTIONS[id]
end

function AuraMenu.Relocated(id)
    return AuraMenu.registered and MODULES[id] == true
end
local function RemoveAuraKeys(keys)
    for index = #keys, 1, -1 do
        if MODULES[keys[index]:match("^([^.]+)%.")] then table.remove(keys, index) end
    end
end
function AuraMenu.FilterQualityOfLife(groups, categories)
    if not AuraMenu.registered then return end
    for index = #groups, 1, -1 do
        if MODULES[groups[index].id] then table.remove(groups, index) end
    end
    for _, category in ipairs(categories) do
        for _, tab in ipairs(category.tabs or { category }) do RemoveAuraKeys(tab.keys) end
    end
end
function AuraMenu.AppendSearchRows(rows, ruleRow, checkpoint)
    if not AuraMenu.registered then return end
    local page = { key = PAGE, title = P.Tr("Blizzard player auras") }
    rows[#rows + 1] = {
        pageKey = PAGE, kind = "section", label = page.title,
        sectionId = "aura_style_blizzardPlayer_blizzard_aura_frames",
        keywords = { "player buffs", "minimap auras", "Blizzard player auras", page.title },
    }
    for _, id in ipairs({ "playerAuras", "playerAuraSkins", "playerBuffGroups" }) do
        for _, rule in ipairs(P.catalog[id].controls) do
            if checkpoint then checkpoint() end
            if not rule.hidden then
                local row = ruleRow(page, P.catalog[id], rule)
                if row then
                    row.sectionId = SettingSection(id, rule)
                    row.controlId = row.settingKey and P.Meta(PAGE, id, rule.key, "setting", row.sectionId).controlId or nil
                    row.keywords[#row.keywords + 1] = page.title
                    rows[#rows + 1] = row
                end
            end
        end
    end
end
local function SkinRows(ctx, body, y, width)
    for _, key in ipairs({ "suite_playerauras_buffs", "suite_playerauras_debuffs" }) do
        local height = Bridge.IconSkinStatusRow(P.M, ctx, body, 16, y, width, key)
        y = y - height - 8
    end
    return y
end
local function BuildBuffGroups(ctx, builder)
    local id = "playerBuffGroups"
    local function Visible(rule) return not rule.hidden end
    local actions = { { "Move in Edit Mode", function() P.MoveOnScreen(id, "groups") end, key = "move" } }
    P.ModuleCard(ctx, builder, PAGE, id, actions, {
        title = "Player buff groups", open = false, rules = P.SectionRules(id, "buff_group_layout", Visible),
    })
    local seen = {}
    for _, rule in ipairs(P.catalog[id].controls) do
        local section = SettingSection(id, rule)
        if section ~= SECTIONS[id] and not seen[section] then
            seen[section] = true
            P.RuleSection(ctx, builder, PAGE, id, section, P.Tr(rule.sectionTitle),
                P.SectionRules(id, rule.section, Visible), { open = false })
        end
    end
end

local function Build(ctx, builder)
    P.M.TrackRefresh(ctx, P.ForgetAvailability)
    local rules = P.SectionRules("playerAuras", "player_auras", function(rule) return not rule.hidden end)
    local layout = P.ModuleCard(ctx, builder, PAGE, "playerAuras", nil, {
        title = "Player aura layout", rules = rules, open = true,
    })
    P.AttachSectionReset(ctx, layout, "Player aura layout", function() return P.ResetRules("playerAuras", rules) end)
    BuildBuffGroups(ctx, builder)
    local skins = P.ModuleCard(ctx, builder, PAGE, "playerAuraSkins", nil, {
        title = "Player aura skins", open = false,
        help = "Keep Blizzard's layout and apply the selected icon skins. Player aura layout also uses these skins.",
        buildBody = function(body, y, width) return SkinRows(ctx, body, y, width) end,
    })
    P.AttachSectionReset(ctx, skins, "Player aura skins", function()
        return P.ResetRules("playerAuras", { P.catalog.playerAuras.rules.buffSkin, P.catalog.playerAuras.rules.debuffSkin })
    end)
end
function AuraMenu.Open(id)
    if not MODULES[id] or not AuraMenu.registered or P.Combat() then return false end
    if not Bridge.SelectPlayerAuraMenu(P.M) then return false end
    return P.Suite.Menu.Open(PAGE)
end
-- Resolve cold provider rows, visited QoL rows and saved search links through
-- the same Aura view. Targets are copied so saved bookmarks remain unchanged.
function AuraMenu.Resolve(page, target)
    if not AuraMenu.registered or not target then return end
    local id, key = (target.settingKey or ""):match("^msufsuite%.([^.]+)%.(.+)$")
    if not MODULES[id] then
        id = (target.sectionId or ""):match("^suite_qualityOfLife_([^_]+)_")
            or (target.sectionId or ""):match("^auras3_styling_([^_]+)_module$")
    end
    local visibility = (target.settingKey or ""):match("^auras3%.shared%.hideBlizzard")
        or (target.sectionId or ""):match("_blizzard_aura_frames$")
        or (target.controlId or ""):find(".blizzard-aura-frames.hide-", 1, true)
    if not MODULES[id] and not visibility then return end
    local selected, control = Bridge.SelectPlayerAuraMenu(P.M, visibility and target.settingKey, visibility and target.controlId)
    if not selected then return false end
    local copy = {}
    for field, value in pairs(target) do copy[field] = value end
    copy.pageKey, copy.prepareKind, copy.prepareValue = PAGE, nil, nil
    if MODULES[id] then
        copy.sectionId = SettingSection(id, key and P.catalog[id].rules[key])
        copy.controlId = key and P.Meta(PAGE, id, key, "setting", copy.sectionId).controlId or nil
    else
        copy.sectionId, copy.controlId = "aura_style_blizzardPlayer_blizzard_aura_frames", control
    end
    return PAGE, copy, {}
end
AuraMenu.registered = Bridge.RegisterPlayerAuraMenu(P.M, {
    text = P.Tr("Blizzard player auras"),
    description = P.Tr("Show, hide and customize Blizzard's player buff and debuff bars."), build = Build,
    canReset = function() return P.Available("playerAuras") end,
    warning = function()
        return P.Tr("Reset Blizzard player auras?\n\nThis resets Blizzard bar visibility and the Suite player aura layout and skins for the active profile.")
    end,
    historyLabel = function() return P.Tr("Reset Blizzard player auras") end,
    prepare = function() return true end,
    reset = function() return P.S.Reset("playerAuras") and P.S.Reset("playerAuraSkins") end,
    finish = function() P.Refresh() end,
})
if AuraMenu.registered then
    Bridge.RegisterSearchTargetResolver(P.M, "MSUF_Suite.PlayerAuras", AuraMenu.Resolve)
end
