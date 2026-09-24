local _, Private = ...
local NS, O = Private.NS, Private.Options

O.RegisterPage("skins", NS.L.BLIZZARD_SKINS, function(page)
    local catalogFrames = NS.BlizzardCatalog and #NS.BlizzardCatalog.GetFrames() or 0
    O.CreateSectionTitle(page, "Blizzard UI coverage", tostring(catalogFrames) .. " verified 12.1 window roots plus dedicated adapters for pooled and unique interfaces.")

    local order, definitions = NS.Adapters.GetDefinitions()
    local listHost = CreateFrame("Frame", nil, page)
    listHost:SetPoint("TOPLEFT", 4, -70)
    listHost:SetPoint("BOTTOMLEFT", 4, 4)
    listHost:SetWidth(500)
    local listScroll, list = O.CreateScrollContainer(listHost, (#order + 1) * 46 + 10, 474)
    page._mskinSkinListScroll = listScroll
    page._mskinSkinListContent = list

    local master = O.CreateToggle(list, NS.L.MASTER_ENABLE, function()
        return NS.DB.enabled
    end, function(value)
        NS.Adapters.SetMasterEnabled(value)
    end, 474)
    master:SetPoint("TOPLEFT", 0, -2)

    local previous = master
    for index = 1, #order do
        local id = order[index]
        local definition = definitions[id]
        local label = type(definition.labelKey) == "string" and NS.L[definition.labelKey] or id
        local toggle = O.CreateToggle(list, label, function()
            return NS.DB.skins[id]
        end, function(value)
            NS.Adapters.SetEnabled(id, value)
        end, 474)
        toggle:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
        previous = toggle
    end

    local statusCard = O.CreatePanel(page, "card")
    statusCard:SetPoint("TOPLEFT", 524, -70)
    statusCard:SetPoint("BOTTOMRIGHT", -4, 4)
    local title = O.CreateText(statusCard, "ADAPTER STATUS", 11, "accent")
    title:SetPoint("TOPLEFT", 16, -16)

    local statusLines = {}
    page._mskinSkinStatusLines = statusLines
    for index = 1, #order do
        local id = order[index]
        local definition = definitions[id]
        local label = type(definition.labelKey) == "string" and NS.L[definition.labelKey] or id
        local y = -42 - (index - 1) * 20
        local line = O.CreateText(statusCard, label, 10, "muted")
        line:SetPoint("TOPLEFT", 16, y)
        if line.SetWordWrap then line:SetWordWrap(false) end
        if line.SetMaxLines then line:SetMaxLines(1) end
        local value = O.CreateText(statusCard, "", 10, "muted", "RIGHT")
        value:SetPoint("TOPRIGHT", -14, y)
        value:SetWidth(72)
        line:SetPoint("TOPRIGHT", value, "TOPLEFT", -8, 0)
        statusLines[id] = { label = line, value = value }
        O.TrackRefresh(function()
            local state = NS.Adapters.GetStatus(id)
            value:SetText(string.upper(state))
            local role = state == "applied" and "success"
                or state == "disabled" and "dim"
                or state == "waiting" and "accentAlt"
                or (state == "failed" or state == "protected") and "danger"
                or "warning"
            O.SetTextColor(value, role)
        end)
    end

    local coverage = O.CreateText(statusCard, "", 11, "accent")
    coverage:SetPoint("TOPLEFT", 16, -54 - #order * 20)
    coverage:SetPoint("RIGHT", -16, 0)
    O.TrackRefresh(function()
        local counts = NS.GenericWindows and NS.GenericWindows.GetCounts()
        if counts then
            coverage:SetText(("GENERIC  %d groups  |  %d roots applied  |  %d LoD pending"):format(
                counts.total or 0, counts.frames or 0, counts.pendingAddons or 0))
        end
    end)

    local boundary = O.CreateText(statusCard,
        "Bounded named-root traversal\nDedicated visual-only Edit Mode coverage\nExplicit secure controls remain untouched\nNo frame reparenting or script replacement\nNo polling, ticker or idle OnUpdate",
        12, "text")
    boundary:SetPoint("TOPLEFT", 16, -88 - #order * 20)
    boundary:SetPoint("RIGHT", -16, 0)
    boundary:SetJustifyV("TOP")
end)
