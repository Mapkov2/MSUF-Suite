local _, P = ...
local S, Tr, HM = P.S, P.Tr, P.HM
local PAGE, MODULE, SECTION = "suite_actionbars", "actionbars", "suite_actionbars_flyouts"

local Page = {}
P.ActionBarFlyoutsPage = Page

local function PresetsEnabled()
    local api = S.ActionBarFlyouts
    return api and api.OpenPresets and api.Ready() == true
end

function Page.Build(ctx, builder)
    local title = Tr("Flyouts")
    local rules = P.SectionRules(MODULE, "flyouts")
    P.LazySection(builder, SECTION, title, true, {
        shell = function(body)
            P.AttachSectionReset(ctx, body, title, function() return P.ResetRules(MODULE, rules) end)
        end,
        content = function(body)
            local width = math.max(260, (HM.GetSectionWidth(body) or builder.width or 720) - 32)
            body._msufSuiteActionBarSectionId = SECTION
            local y, entries = P.RuleGrid(ctx, body, PAGE, MODULE, rules, -12, width, nil, SECTION)
            P.ActionBarMenu.Prepare(body, entries)
            local help = P.Text(body, "Group spells, items and macros on one action button. Click it to open the flyout, even in combat.",
                16, y - 12, width)
            y = y - math.max(18, math.ceil(help:GetStringHeight())) - 22
            local steps = P.Text(body, "Drag a spell, item or macro onto the + that appears on an action button.", 16, y, width)
            y = y - math.max(18, math.ceil(steps:GetStringHeight())) - 6
            local edit = P.Text(body, "Drag actions into or out of an open flyout, just like on an action bar.", 16, y, width, P.T.colors.muted)
            y = y - math.max(18, math.ceil(edit:GetStringHeight())) - 12
            local buttonWidth = math.min(180, (width - 12) / 2)
            local presets
            presets = P.Button(ctx, body, "Presets", 16, y, buttonWidth, function()
                S.ActionBarFlyouts.OpenPresets(presets)
            end, PresetsEnabled, P.Meta(PAGE, MODULE, "flyouts.presets", "ephemeral", SECTION))
            HM.SkipHistoryCheckpoint(presets)
            local saved
            saved = P.Button(ctx, body, "Saved flyouts", 28 + buttonWidth, y, buttonWidth, function()
                S.ActionBarFlyouts.OpenSaved(saved)
            end, PresetsEnabled, P.Meta(PAGE, MODULE, "flyouts.saved", "ephemeral", SECTION))
            HM.SkipHistoryCheckpoint(saved)
            return y - math.max(presets:GetHeight(), saved:GetHeight())
        end,
        finish = function(body, y) P.FinishBody(builder, body, y) end,
    })
end
