local _, P = ...
local Graphics, Tr = P.GraphicsPerformance, P.Tr
local PAGE, SECTION = "suite_qualityOfLife", "suite_qualityOfLife_graphics_performance"
local TITLE = "Graphics & performance"
local HELP = [[Apply a graphics preset once. Balanced changes your general settings and keeps your separate raid settings.
Raid / Dungeon changes only the separate instance settings and enables them.
Textures, particle density and outlines stay as you set them; projected textures stay on. Unsupported settings are skipped.
Sharpening, contrast and audio reverb are optional and apply globally.
Your originals are saved outside profiles. Restore keeps later manual changes. FPS gains depend on your hardware and the scene.]]
local ACTIONS = {
    { key = "apply", label = "Apply graphics preset" },
    { key = "restore", label = "Restore previous graphics settings" },
}

local function Keywords(label)
    return { TITLE, Tr(TITLE), label, Tr(label), "fps", "graphics", "performance",
        "optimize fps", "Grafik", "Leistung", "FPS verbessern" }
end

local function Meta(key, kind)
    local meta = P.Meta(PAGE, "graphicsPerformance", key, kind or "ephemeral", SECTION)
    if kind == "action" then
        meta.suiteAlways = true
        meta.keywords = Keywords(key == "apply" and ACTIONS[1].label or ACTIONS[2].label)
    end
    return meta
end

local function PlanText(rows)
    local lines = {}
    for _, row in ipairs(rows) do
        lines[#lines + 1] = Tr("%s: %s -> %s"):format(Tr(row.label), row.from, row.to)
    end
    if #lines == 0 then return Tr("No supported graphics settings are available.") end
    return table.concat(lines, "\n")
end

local function Feedback(result, reason)
    if reason == "combat" then return Tr("Graphics settings cannot be changed in combat.") end
    if reason == "stale" then return Tr("Settings changed since the preview. Review the updated values and apply again.") end
    if not result then return Tr("No supported graphics settings are available.") end
    if result.preserved then
        return Tr("Restored %d settings; kept %d manual changes; %d settings need another attempt.")
            :format(result.changed, result.preserved, result.failed)
    end
    return Tr("Applied %d settings; %d settings could not be changed."):format(result.changed, result.failed)
end

local function Choices(ctx, body, state, width, y, update)
    P.M.BindDropdownAt(ctx, body, Tr("Graphics preset"), 16, y, {
        { value = "balanced", text = Tr("Balanced") }, { value = "raid", text = Tr("Raid / Dungeon") },
    }, width, function() return state.mode end, function(value)
        state.mode = value
        update()
    end, Meta("preset"))
    y = y - 62
    for _, option in ipairs({
        { "sharpen", "Enable resample sharpening" },
        { "contrast", "Set contrast to 55" },
        { "reverb", "Disable audio reverb" },
    }) do
        local key = option[1]
        P.M.BindSwitchAt(ctx, body, Tr(option[2]), 16, y, width, function() return state[key] == true end,
            function(value)
                state[key] = value == true
                update()
            end, Meta(key))
        y = y - 36
    end
    return y
end

local function PositionButton(button, width, y)
    local label = P.HM.GetControlLabel(button)
    local height = 26
    if label then
        label:SetWidth(width - 24)
        label:SetWordWrap(true)
        height = math.max(height, math.ceil(label:GetStringHeight() or 14) + 12)
    end
    button:SetHeight(height)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", 16, y)
    return y - height - 12
end

local function Content(ctx, builder, body)
    local width = math.max(208, (P.HM.GetSectionWidth(body) or builder.width or 720) - 64)
    local state = ctx.suiteGraphicsChoices or { mode = "balanced" }
    ctx.suiteGraphicsChoices = state
    local description = P.Description(body, HELP, 16, -12, width, TITLE)
    local rows, preview, feedback, apply, restore, previewY, bottom
    local function Update()
        if not preview then return end
        rows = Graphics.Plan(state.mode, state)
        P.SetTranslatedText(preview, PlanText(rows))
        local height = math.max(14, math.ceil(preview:GetStringHeight() or 14))
        preview:SetHeight(height)
        if not apply then return end
        local y = PositionButton(apply, width, previewY - height - 18)
        y = PositionButton(restore, width, y)
        feedback:ClearAllPoints()
        feedback:SetPoint("TOPLEFT", 16, y)
        bottom = y - 16 - math.max(28, math.ceil(feedback:GetStringHeight() or 14))
        P.FinishBody(builder, body, bottom)
    end
    previewY = Choices(ctx, body, state, width, -28 - math.ceil(description:GetStringHeight() or 14), Update)
    preview = P.Text(body, "", 16, previewY, width, P.T.colors.text)
    Update()
    apply = P.Button(ctx, body, ACTIONS[1].label, 16, previewY, width, function()
        local result, reason = Graphics.Apply(rows)
        P.SetTranslatedText(feedback, Feedback(result, reason))
        Update()
    end, function() return #rows > 0 end, Meta("apply", "action"))
    restore = P.Button(ctx, body, ACTIONS[2].label, 16, previewY, width, function()
        P.Confirm("graphics-restore", Tr("Restore saved graphics settings? Later manual changes will be kept."), function()
            local result, reason = Graphics.Restore()
            P.SetTranslatedText(feedback, Feedback(result, reason))
            Update()
            P.Refresh()
        end)
    end, function() return Graphics.PendingCount() > 0 end, Meta("restore", "action"))
    feedback = P.Text(body, "", 16, previewY, width)
    P.M.TrackRefresh(ctx, function()
        if feedback:GetText() == "" then
            P.SetTranslatedText(feedback, Tr("Saved original settings: %d."):format(Graphics.PendingCount()))
        end
    end)
    Update()
    return bottom
end

function P.BuildGraphicsPerformance(ctx, builder)
    P.LazySection(builder, SECTION, Tr(TITLE), false, {
        content = function(body) return Content(ctx, builder, body) end,
        finish = function(body, y) P.FinishBody(builder, body, y) end,
    })
end

-- Recovery remains reachable when the QoL AddOn is disabled in Blizzard's list.
function P.BuildGraphicsNotice(ctx, y)
    local builder = P.W.PageBuilder(ctx, { topInset = -12 - y })
    P.BuildGraphicsPerformance(ctx, builder)
    return builder.y
end

function P.AppendGraphicsSearchRows(rows)
    for _, action in ipairs(ACTIONS) do
        rows[#rows + 1] = {
            pageKey = PAGE, sectionId = SECTION, controlId = Meta(action.key, "action").controlId,
            label = Tr(action.label), kind = "button", section = Tr(TITLE), suiteAlways = true,
            keywords = Keywords(action.label),
        }
    end
end
