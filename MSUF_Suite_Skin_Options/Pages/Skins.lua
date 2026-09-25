local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

local LIST_WIDTH = 474

-- Adapter state to its status color.
local STATUS_ROLES = {
    applied = "success",
    disabled = "dim",
    waiting = "accentAlt",
    failed = "danger",
    protected = "danger",
}

local function AdapterLabel(definitions, id)
    local definition = definitions[id]
    return type(definition.labelKey) == "string" and NS.L[definition.labelKey] or id
end

local function BuildToggleList(page, order, definitions)
    local listHost = CreateFrame("Frame", nil, page)
    listHost:SetPoint("TOPLEFT", 4, -70)
    listHost:SetPoint("BOTTOMLEFT", 4, 4)
    listHost:SetWidth(500)
    local listScroll, list = O.CreateScrollContainer(listHost, (#order + 1) * 46 + 10, LIST_WIDTH)
    page._mskinSkinListScroll = listScroll
    page._mskinSkinListContent = list

    local master = O.CreateToggle(list, NS.L.MASTER_ENABLE, function()
        return NS.DB.enabled
    end, function(value)
        NS.Adapters.SetMasterEnabled(value)
    end, LIST_WIDTH)
    master:SetPoint("TOPLEFT", 0, -2)

    local previous = master
    for index = 1, #order do
        local id = order[index]
        local toggle = O.CreateToggle(list, AdapterLabel(definitions, id), function()
            return NS.DB.skins[id]
        end, function(value)
            NS.Adapters.SetEnabled(id, value)
        end, LIST_WIDTH)
        toggle:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
        previous = toggle
    end
end

local function BuildStatusLines(page, statusCard, order, definitions)
    local lines = {}
    page._mskinSkinStatusLines = lines
    for index = 1, #order do
        local id = order[index]
        local y = -42 - (index - 1) * 20
        local line = O.CreateText(statusCard, AdapterLabel(definitions, id), 10, "muted")
        line:SetPoint("TOPLEFT", 16, y)
        if line.SetWordWrap then line:SetWordWrap(false) end
        if line.SetMaxLines then line:SetMaxLines(1) end
        local value = O.CreateText(statusCard, "", 10, "muted", "RIGHT")
        value:SetPoint("TOPRIGHT", -14, y)
        value:SetWidth(72)
        line:SetPoint("TOPRIGHT", value, "TOPLEFT", -8, 0)
        lines[id] = { label = line, value = value }
    end
    O.TrackRefresh(function()
        for index = 1, #order do
            local id = order[index]
            local state = NS.Adapters.GetStatus(id)
            local value = lines[id].value
            value:SetText(string.upper(state))
            O.SetTextColor(value, STATUS_ROLES[state] or "warning")
        end
    end)
end

local function BuildStatusCard(page, order, definitions)
    local statusCard = O.CreatePanel(page, "card")
    statusCard:SetPoint("TOPLEFT", 524, -70)
    statusCard:SetPoint("BOTTOMRIGHT", -4, 4)
    local title = O.CreateText(statusCard, L["ADAPTER STATUS"], 11, "accent")
    title:SetPoint("TOPLEFT", 16, -16)
    BuildStatusLines(page, statusCard, order, definitions)

    local coverage = O.CreateText(statusCard, "", 11, "accent")
    coverage:SetPoint("TOPLEFT", 16, -54 - #order * 20)
    coverage:SetPoint("RIGHT", -16, 0)
    O.TrackRefresh(function()
        local counts = NS.GenericWindows and NS.GenericWindows.GetCounts()
        if counts then
            coverage:SetText(L["GENERIC  %d groups  |  %d roots applied  |  %d LoD pending"]:format(
                counts.total or 0, counts.frames or 0, counts.pendingAddons or 0))
        end
    end)

    -- What the adapters promise about Blizzard frames and background work.
    local boundary = O.CreateText(statusCard,
        L["Bounded named-root traversal\nDedicated visual-only Edit Mode coverage\nExplicit secure controls remain untouched\nBlizzard frames keep their parents and scripts; only Suite-made selection indicators move\nNo polling or tickers; OnUpdate runs only while a window corner is dragged"],
        12, "text")
    boundary:SetPoint("TOPLEFT", 16, -88 - #order * 20)
    boundary:SetPoint("RIGHT", -16, 0)
    boundary:SetJustifyV("TOP")
end

O.RegisterPage("skins", NS.L.BLIZZARD_SKINS, function(page)
    local catalogFrames = NS.BlizzardCatalog and #NS.BlizzardCatalog.GetFrames() or 0
    O.CreateSectionTitle(page, L["Blizzard UI coverage"],
        L["%d verified 12.1 window roots plus dedicated adapters for pooled and unique interfaces."]:format(catalogFrames))
    local order, definitions = NS.Adapters.GetDefinitions()
    BuildToggleList(page, order, definitions)
    BuildStatusCard(page, order, definitions)
end)
