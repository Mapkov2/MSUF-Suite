local _, P = ...
local Owners, active, destinations = {}, {}, {}
P.QoLOwners = Owners
-- UI ownership only: catalog identities, saved values and runtimes stay in Suite.
local PAGES = {
    suite_bags = { title = "Inventory organisation", modules = "inventoryProtection lootVendorRules" },
    suite_chat = { title = "Chat tools", modules = "guildChatPrivacy" },
    suite_minimap = { title = "Minimap", modules = "mapLandingShortcuts" },
    suite_actionbars = { title = "Action bars", modules = "autoUprank" },
    suite_hud = { title = "Additional displays", modules = "xpBar skyriding flightTimer lootToastFilter" },
    opt_misc = { title = "Tooltips", modules =
        "tooltipClassColors tooltipSpellCopy itemCounts tooltipIDs tooltipVisibility tooltipDetails tooltipMPlusScore" },
}
for page, spec in pairs(PAGES) do
    for id in spec.modules:gmatch("%S+") do destinations[id] = page end
end

function Owners.PageFor(id)
    local page = destinations[id]
    return page and active[page] and page or nil
end

function Owners.Title(id)
    local page = Owners.PageFor(id)
    return page and PAGES[page].title or nil
end

function Owners.HasFeatures(page)
    if not active[page] then return false end
    for id in PAGES[page].modules:gmatch("%S+") do
        if P.Available(id) then return true end
    end
    return false
end

function Owners.Build(ctx, builder, page, reveal)
    if not Owners.HasFeatures(page) then return end
    P.SortQualityOfLifeCategories()
    local spec, features = PAGES[page], {}
    for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
        if Owners.PageFor(feature.id) == page and P.Available(feature.id) then features[#features + 1] = feature end
    end
    local category = { id = page, title = spec.title, features = features,
        subgroups = { { id = page, title = spec.title, features = features } } }
    return P.QoLView.BuildSelected(ctx, builder, { category }, page,
        { heading = page == "opt_misc" and spec.title or nil, compact = true, reveal = reveal })
end

function Owners.Reset(page)
    for id in PAGES[page].modules:gmatch("%S+") do
        if not P.S.Reset(id) then return false end
    end
    return true
end

-- Old control-only favourites may point at settings or action buttons. Match
-- exact generated identities lazily; navigating to an action never runs it.
local legacyControls
local function LegacyControls()
    if legacyControls then return legacyControls end
    legacyControls = {}
    for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
        if Owners.PageFor(feature.id) then
            local section = P.QoLView.FeatureSectionId(feature)
            local function Add(key, kind)
                local meta = P.Meta("suite_qualityOfLife", feature.id, key, kind, section)
                if meta.controlId then legacyControls[meta.controlId] = { feature = feature, key = key, kind = kind } end
            end
            for _, rule in ipairs(P.catalog[feature.id].controls) do Add(rule.key, "setting") end
            for _, key in ipairs({ "settings", "reset", "colors" }) do Add("action." .. key .. "." .. feature.switch, "action") end
            for _, key in ipairs({ "edit", "open", "resetSession" }) do Add("action." .. key, "action") end
        end
    end
    return legacyControls
end

function Owners.Resolve(page, target)
    if not target then return end
    local id, key = (target.settingKey or ""):match("^msufsuite%.([^.]+)%.(.+)$")
    id = id or (target.sectionId or ""):match("^suite_qualityOfLife_([^_]+)_")
    local old = not key and target.controlId and LegacyControls()[target.controlId]
    local feature = old and old.feature or id and P.QoLView.FindFeature(id)
    local tooltips = target.sectionId == "suite_qualityOfLife_category_tooltips" and active.opt_misc
    local destination = tooltips and "opt_misc" or feature and Owners.PageFor(feature.id)
    if not destination or page == destination then return end
    local copy = {}
    for field, value in pairs(target) do copy[field] = value end
    copy.pageKey = destination
    copy.sectionId = tooltips and "suite_qualityOfLife_category_opt_misc" or P.QoLView.FeatureSectionId(feature)
    copy.controlId, copy.controlPath, copy.identityKey, copy.actionKey = nil, nil, nil, nil
    key = key or old and old.kind == "setting" and old.key
    if key then
        local meta = P.Meta(destination, feature.id, key, "setting", copy.sectionId)
        copy.settingKey = "msufsuite." .. feature.id .. "." .. key
        copy.controlId, copy.controlPath, copy.identityKey = meta.controlId, meta.controlPath, meta.identityKey
    else copy.settingKey = nil end
    return destination, copy, {}
end

local tooltipProvider = {
    build = function(ctx, builder)
        P.M.TrackRefresh(ctx, P.ForgetAvailability)
        Owners.Build(ctx, builder, "opt_misc")
    end,
    canReset = function() return Owners.HasFeatures("opt_misc") end,
    warning = function() return string.format(P.Tr("Reset the settings of %s."), P.Tr("Tooltips")) end,
    prepare = function() return not P.Combat() end,
    reset = function() return Owners.Reset("opt_misc") end,
    finish = function() P.Refresh() end,
}
function Owners.Register()
    for _, page in ipairs(P.pages) do if PAGES[page.key] then active[page.key] = true end end
    -- Registration can rebuild an already visible host page immediately.
    active.opt_misc = true
    active.opt_misc = P.Suite.HostBridge.RegisterPageTail(P.M, "opt_misc", "MSUF_Suite.Tooltips", tooltipProvider)
    P.Suite.HostBridge.RegisterSearchTargetResolver(P.M, "MSUF_Suite.QoLOwners", Owners.Resolve)
end
