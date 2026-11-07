local _, P = ...
local V, W, HM, Tr = P.QoLView, P.W, P.HM, P.Tr
local RESET_SEARCH = "qolSectionReset"

local function ResetMeta(group, sectionId)
    return P.Meta(V.GetFeaturePage(group), group.id, "action.reset." .. group.switch, "action", sectionId)
end

function V.FeatureTitle(group)
    local title = Tr(group.title)
    if group.title:match(" %(Retail.-%)$") or group.title:match(" %(Forever%)$") then
        title = title:gsub(" %b()$", "")
    end
    return title
end

local function RefreshTitle(ctx, group, label)
    P.M.TrackRefresh(ctx, function()
        local ok, why = P.Available(group.id)
        local title = V.FeatureTitle(group)
        if not ok and why then title = Tr("%s: %s"):format(title, P.Suite.StatusText(why, Tr)) end
        P.SetTranslatedText(label, title)
    end)
end

local function Reveal(ui, panel, record, force, expand)
    if P.Combat() or not ui:SelectCategory(panel.category.id) then return nil end
    ui.retained = record.group
    ui:Layout()
    if not record.hasDetails or expand == false then return record.row end
    local entry = HM.GetSectionEntry(record.body)
    if force == false then
        entry.SetOpenByUser(not entry.open)
    else
        W.FocusCollapsibleSection(record.body, { scroll = false, flash = false })
    end
    if entry.open then P.EnsureSectionContent(record.body) end
    return record.body
end

local function BuildSimple(ui, panel, record)
    local row = P.Suite.HostBridge.MenuFlowSection(panel.builder, 32, 8)
    local label = P.T.Font(row, "GameFontHighlightSmall", V.FeatureTitle(record.group), P.T.colors.text, "control")
    label:SetPoint("LEFT", row, "LEFT", 30, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -88, 0)
    label:SetJustifyH("LEFT")
    local toggle = W.SwitchAt(row, Tr(record.group.title), 0, 0, 0, "HIDDEN")
    toggle:ClearAllPoints()
    toggle:SetPoint("RIGHT", row, "RIGHT", -22, 0)
    record.row, record.toggle = row, toggle
    record.flow = panel.builder.layoutEntries[#panel.builder.layoutEntries]
    record.keywords = V.BindFeatureSwitch(ui.ctx, toggle, record.group, record.sectionId,
        function(group) ui.retained = group end)
    RefreshTitle(ui.ctx, record.group, label)
end

local function BuildAccordion(ui, panel, record)
    local group = record.group
    local function Content(body)
        record.details = body
        local width = HM.GetSectionWidth(body) or ui.width
        local y, height, colors = V.BuildFeatureDetails(ui.ctx, body, group, record.sectionId,
            width, record.sections, record.allRules, record.keywords)
        record.detailHeight, record.colorShortcut = height, colors
        return y
    end
    local function Shell(body)
        local entry = HM.GetSectionEntry(body)
        record.body, record.row, record.flow = body, entry.outer, entry
        local toggle = W.SectionSwitch(body, Tr(group.title), Tr("Enable"))
        record.toggle = toggle
        record.keywords = V.BindFeatureSwitch(ui.ctx, toggle, group, record.sectionId,
            function(feature) ui.retained = feature end)
        if #record.allRules > 0 then
            -- The detail rules leave the feature switch out of the reset.
            local more = P.AttachSectionReset(ui.ctx, body, V.FeatureTitle(group), function()
                return P.ResetRules(group.id, record.allRules)
            end)
            if more then
                local meta = ResetMeta(group, record.sectionId)
                meta.searchPrepareKind, meta.searchPrepareValue = RESET_SEARCH, record.sectionId
                meta.prepareExactSearchTarget = function()
                    if not group.reveal(true) then return false end
                    more._msufSuiteOpenSectionPopup()
                    return true
                end
                P.M.RegisterControlMetadata(more, meta, "Reset section", "button")
            end
        end
        HM.SetSectionEnsureVisible(entry, function()
            ui.retained = group
            ui:SelectCategory(panel.category.id)
        end)
        RefreshTitle(ui.ctx, group, entry.label)
    end
    -- Hidden category panels remain hidden until filtering and layout settle.
    record.body = P.LazySection(panel.builder, record.sectionId, V.FeatureTitle(group), false, {
        head = Shell, content = Content, deferWhileHidden = true,
        finish = function(body, y) P.FinishBody(panel.builder, body, y) end,
    })
end

function V.BuildAccordionRecord(ui, panel, group)
    local sections, rules = V.FeatureRules(group)
    local record = { group = group, sectionId = V.FeatureSectionId(group), sections = sections, allRules = rules,
        hasDetails = V.HasDetails(group, rules), category = panel.category.id, tab = group.tab, title = group.title }
    if record.hasDetails then BuildAccordion(ui, panel, record) else BuildSimple(ui, panel, record) end
    record.reveal = function(force, expand) return Reveal(ui, panel, record, force, expand) end
    panel.records[group], ui.rows[record.sectionId] = record, record
    return record
end

-- Old favourites can identify the removed Settings button without a section.
-- Preserve those identities as navigation, including reset-button bookmarks.
local oldActions
local function Actions()
    if oldActions then return oldActions end
    oldActions = {}
    for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
        for _, page in ipairs({ "suite_qualityOfLife", V.GetFeaturePage(feature) }) do
            for _, action in ipairs({ "settings", "reset" }) do
                local meta = P.Meta(page, feature.id, "action." .. action .. "." .. feature.switch,
                    "action", V.FeatureSectionId(feature))
                if meta.controlId then oldActions[meta.controlId] = feature end
            end
        end
    end
    return oldActions
end

function V.ResolveAccordionTarget(_, target)
    local control = target and target.controlId
    if not control or not control:find("action", 1, true) then return end
    local feature = Actions()[control]
    if not feature then return end
    local copy = {}
    for key, value in pairs(target) do copy[key] = value end
    copy.pageKey, copy.sectionId = V.GetFeaturePage(feature), V.FeatureSectionId(feature)
    if target.prepareKind ~= RESET_SEARCH or control ~= ResetMeta(feature, copy.sectionId).controlId then
        copy.controlId, copy.controlPath, copy.identityKey, copy.actionKey, copy.settingKey = nil, nil, nil, nil, nil
    end
    return copy.pageKey, copy, {}
end
P.Suite.HostBridge.RegisterSearchTargetResolver(P.M, "MSUF_Suite.QoLAccordions", V.ResolveAccordionTarget)
