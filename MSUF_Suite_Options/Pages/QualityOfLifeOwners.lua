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
    suite_skin = { title = "Tooltips", modules =
        "tooltipClassColors tooltipSpellCopy itemCounts tooltipIDs tooltipVisibility tooltipDetails tooltipMPlusScore auctionPriceTooltip gatheringTooltips bnetToast" },
}
for page, spec in pairs(PAGES) do
    for id in spec.modules:gmatch("%S+") do destinations[id] = page end
end

function Owners.PageFor(id)
    if id == "bnetToast" and not P.Suite.Client.AddOnEnabled("MSUF_Suite_Skin") then return end
    local page = destinations[id]
    return page and active[page] and page or nil
end

function Owners.Title(id)
    local page = Owners.PageFor(id)
    if id == "bnetToast" and page then return "Notifications" end
    return page and PAGES[page].title or nil
end

function Owners.HasFeatures(page)
    if not active[page] then return false end
    for id in PAGES[page].modules:gmatch("%S+") do
        if P.Available(id) then return true end
    end
    return false
end

function Owners.Build(ctx, builder, page, reveal, group)
    if not Owners.HasFeatures(page) then return end
    P.SortQualityOfLifeCategories()
    local spec, features = PAGES[page], {}
    local title = group == "notifications" and "Notifications" or spec.title
    for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
        local belongs = not group or (feature.id == "bnetToast") == (group == "notifications")
        if belongs and Owners.PageFor(feature.id) == page and P.Available(feature.id) then
            features[#features + 1] = feature
        end
    end
    if #features == 0 then return end
    local categoryID = group or page
    local category = { id = categoryID, title = title, features = features,
        subgroups = { { id = categoryID, title = title, features = features } } }
    return P.QoLView.BuildSelected(ctx, builder, { category }, categoryID, { compact = true, reveal = reveal })
end

function Owners.Reset(page, availableOnly)
    for id in PAGES[page].modules:gmatch("%S+") do
        if (not availableOnly or P.Available(id)) and not P.S.Reset(id) then return false end
    end
    return true
end

-- Old control-only favourites may point at settings or action buttons. Match
-- exact generated identities lazily; navigating to an action never runs it.
local legacyControls
local unitTooltipKeys = {
    ["general.unitTooltipProvider"] = "unitTooltipProvider",
    ["general.unitTooltipAnchor"] = "unitTooltipAnchor",
    ["general.unitTooltipMode"] = "unitTooltipMode",
    ["general.unitTooltipModifier"] = "unitTooltipModifier",
}
local function LegacyControls()
    if legacyControls then return legacyControls end
    legacyControls = {}
    for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
        if Owners.PageFor(feature.id) then
            local section = P.QoLView.FeatureSectionId(feature)
            local function Add(key, kind)
                local meta = P.Meta("suite_qualityOfLife", feature.id, key, kind, section)
                if meta.controlId then legacyControls[meta.controlId] = { feature = feature, key = key, kind = kind } end
                local misc = P.Meta("opt_misc", feature.id, key, kind, section)
                if misc.controlId then legacyControls[misc.controlId] = { feature = feature, key = key, kind = kind } end
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
    local unit = page == "opt_misc" and unitTooltipKeys[target.settingKey]
    if unit and P.Suite.HostBridge.UnitFrameTooltipAPI() then
        if unit == "unitTooltipAnchor" and P.UsesSharedTooltipAnchor and P.UsesSharedTooltipAnchor() then
            local feature = P.QoLView.FindFeature("tooltipDetails")
            if feature then
                return "suite_skin", P.Meta("suite_skin", "tooltipDetails", "anchor", "setting", P.QoLView.FeatureSectionId(feature)), {}
            end
        end
        local meta = P.SkinPageKit.Meta(unit, "unit_tooltips")
        return "suite_skin", meta, {}
    end
    local id, key = (target.settingKey or ""):match("^msufsuite%.([^.]+)%.(.+)$")
    id = id or (target.sectionId or ""):match("^suite_qualityOfLife_([^_]+)_")
    local old = not key and target.controlId and LegacyControls()[target.controlId]
    local feature = old and old.feature or id and P.QoLView.FindFeature(id)
    local tooltips = active.suite_skin and (target.sectionId == "suite_qualityOfLife_category_tooltips"
        or target.sectionId == "suite_qualityOfLife_category_opt_misc")
    local destination = tooltips and "suite_skin" or feature and Owners.PageFor(feature.id)
    if not destination or page == destination then return end
    local copy = {}
    for field, value in pairs(target) do copy[field] = value end
    copy.pageKey = destination
    copy.sectionId = tooltips and "suite_skin_tooltips" or P.QoLView.FeatureSectionId(feature)
    copy.controlId, copy.controlPath, copy.identityKey, copy.actionKey = nil, nil, nil, nil
    key = key or old and old.kind == "setting" and old.key
    if key then
        local meta = P.Meta(destination, feature.id, key, "setting", copy.sectionId)
        copy.settingKey = "msufsuite." .. feature.id .. "." .. key
        copy.controlId, copy.controlPath, copy.identityKey = meta.controlId, meta.controlPath, meta.identityKey
    else copy.settingKey = nil end
    return destination, copy, {}
end

function Owners.Register()
    for _, page in ipairs(P.pages) do
        local spec = PAGES[page.key]
        if spec and (not spec.addon or P.Suite.Client.AddOnEnabled(spec.addon)) then active[page.key] = true end
    end
    P.Suite.HostBridge.RegisterSearchTargetResolver(P.M, "MSUF_Suite.QoLOwners", Owners.Resolve)
end
