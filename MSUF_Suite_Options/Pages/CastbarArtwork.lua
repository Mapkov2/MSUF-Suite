local _, P = ...
local Bridge = P.Suite.HostBridge
local PAGE, MODULE = "opt_castbar", "castbarArt"
local SECTION = PAGE .. "_" .. MODULE .. "_module"
local OLD_SECTION = "suite_qualityOfLife_castbarArt_castbar_art"
local Art = { registered = false }
P.CastbarArtworkPage = Art

function Art.Relocated(id) return Art.registered and id == MODULE end

function Art.FilterQualityOfLife(groups)
    if not Art.registered then return end
    for index = #groups, 1, -1 do
        if groups[index].id == MODULE then table.remove(groups, index) end
    end
end

local function Build(ctx, builder)
    P.M.TrackRefresh(ctx, P.ForgetAvailability)
    P.ModuleCard(ctx, builder, PAGE, MODULE, nil, {
        title = "Castbar artwork", open = false,
        rules = P.SectionRules(MODULE, "castbar_art"),
    })
end

function Art.AppendSearchRows(rows, ruleRow)
    if not Art.registered then return end
    local page = { key = PAGE, title = P.M.pages[PAGE].title }
    for _, rule in ipairs(P.catalog[MODULE].controls) do
        if not rule.hidden then
            local row = ruleRow(page, P.catalog[MODULE], rule)
            if row then
                row.sectionId = SECTION
                row.controlId = P.Meta(PAGE, MODULE, rule.key, "setting", SECTION).controlId
                rows[#rows + 1] = row
            end
        end
    end
end

local oldControls = {}
for _, rule in ipairs(P.catalog[MODULE].controls) do
    local control = P.Meta("suite_qualityOfLife", MODULE, rule.key, "setting", OLD_SECTION).controlId
    if control then oldControls[control] = rule.key end
end

for _, action in ipairs({ "action.settings.enabled", "action.reset.enabled" }) do
    local control = P.Meta("suite_qualityOfLife", MODULE, action, "action", OLD_SECTION).controlId
    if control then oldControls[control] = "" end -- Old actions now reveal the section.
end

-- Preserve old favourites and control-only links without changing their records.
function Art.Resolve(page, target)
    if not Art.registered or not target then return end
    local key = (target.settingKey or ""):match("^msufsuite%.castbarArt%.(.+)$")
        or oldControls[target.controlId]
    if not key and target.sectionId ~= OLD_SECTION then return end
    local copy = {}
    for field, value in pairs(target) do copy[field] = value end
    copy.pageKey, copy.sectionId = PAGE, SECTION
    copy.controlId, copy.controlPath, copy.identityKey, copy.actionKey = nil, nil, nil, nil
    if key and key ~= "" then
        local meta = P.Meta(PAGE, MODULE, key, "setting", SECTION)
        copy.settingKey = "msufsuite." .. MODULE .. "." .. key
        copy.controlId, copy.controlPath, copy.identityKey = meta.controlId, meta.controlPath, meta.identityKey
    else
        copy.settingKey = nil
    end
    return PAGE, copy, {}
end

function Art.Open(id)
    if not Art.Relocated(id) or P.Combat() or not P.Suite.Menu.Open(PAGE) then return false end
    local called, opened, focused = P.M.SearchBridge.OpenSearchTarget(PAGE, "", nil, nil, {},
        { pageKey = PAGE, sectionId = SECTION })
    return called == true and opened == true and focused == true
end

local provider = {
    build = Build,
    canReset = function() return P.Available(MODULE) end,
    warning = function() return string.format(P.Tr("Reset the settings of %s."), P.Tr("Castbar artwork")) end,
    prepare = function() return not P.Combat() end,
    reset = function() return P.S.Reset(MODULE) end,
    finish = function() P.Refresh() end,
}
function Art.Register()
    Art.registered = Bridge.RegisterPageTail(P.M, PAGE, "MSUF_Suite.CastbarArtwork", provider)
    if Art.registered then
        Bridge.RegisterSearchTargetResolver(P.M, "MSUF_Suite.CastbarArtwork", Art.Resolve)
    end
end
Art.Register()
