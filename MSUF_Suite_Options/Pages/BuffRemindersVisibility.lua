local _, P = ...
local ID, PAGE = "buffReminders", "suite_buffReminders"
local Visibility = {}
P.ReminderVisibility = Visibility

local function Locations(section)
    local locations, appearance = {}, {}
    for _, rule in ipairs(P.SectionRules(ID, section)) do
        local list = rule.key:find("_show", 1, true) and locations or appearance
        list[#list + 1] = rule
    end
    return locations, appearance
end

function Visibility.UsesGlobal(section)
    for _, rule in ipairs(Locations(section)) do if P.Get(ID, rule.key) == false then return false end end
    return true
end

function Visibility.Inherit(section)
    local values = {}
    for _, rule in ipairs(Locations(section)) do values[rule.key] = true end
    return P.SetMany(ID, values)
end

function Visibility.Build(ctx, builder, section, title)
    local locations, appearance = Locations(section)
    local custom = not Visibility.UsesGlobal(section)
    local sectionId = PAGE .. "_" .. section
    return P.LazySection(builder, sectionId, P.Tr(title), false, {
        content = function(body)
            local width = math.max(240, (P.HM.GetSectionWidth(body) or builder.width) - 32)
            local picker = P.M.BindDropdownAt(ctx, body, P.Tr("When to show"), 16, -12, {
                { value = false, text = P.Tr("Use global locations") },
                { value = true, text = P.Tr("Custom locations") },
            }, width, function() return custom end, function(value)
                custom = value == true
                if not custom then Visibility.Inherit(section) end
                P.Refresh()
            end, P.Meta(PAGE, ID, section .. ".inherit", "ephemeral", sectionId))
            local y, styles = P.RuleGrid(ctx, body, PAGE, ID, appearance, -76, width, nil, sectionId)
            P.MenuWorkspace.Prepare(body, styles)
            local panel = CreateFrame("Frame", nil, body)
            panel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
            panel:SetSize(width + 32, 100)
            local bottom, entries = P.RuleGrid(ctx, panel, PAGE, ID, locations, -8, width, nil, sectionId)
            panel:SetHeight(-bottom + 8)
            for _, entry in ipairs(entries) do
                P.HM.SetSearchTargetPrepare(entry.widget, function()
                    custom = true
                    P.Refresh()
                    return true
                end)
            end
            P.MenuWorkspace.Prepare(body, entries)
            P.AttachRuleColors(body, title, ID, appearance)
            P.M.TrackRefresh(ctx, function()
                if not Visibility.UsesGlobal(section) then custom = true end
                panel:SetShown(custom)
                picker:SetValue(custom)
                P.FinishBody(builder, body, custom and y + bottom - 8 or y)
            end)
            return custom and y + bottom - 8 or y
        end,
        shell = function(body)
            P.AttachSectionReset(ctx, body, title, function() return P.ResetRules(ID, P.SectionRules(ID, section)) end)
        end,
        finish = function(body, y) P.FinishBody(builder, body, y) end,
    })
end
