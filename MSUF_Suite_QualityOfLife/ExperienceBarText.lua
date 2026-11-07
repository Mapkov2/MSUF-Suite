local _, P = ...
local NS, S = P.NS, P.Suite
local Shared = NS.ExperienceBarLayout
local Text = {}
P.ExperienceBarText = Text
local floor, max, min = math.floor, math.max, math.min
local OUTLINES, PERCENT = { false, "", "OUTLINE", "THICKOUTLINE" }, { "%.0f%%", "%.1f%%", "%.2f%%" }
local LABELS = { level = S.Text("Lv %d"), session = S.Text("Session +%s"), rate = S.Text("XP/h %s"),
    eta = S.Text("To level %s"), xp = S.Text("%s / %s"), combined = S.Text("Lv %d  %s / %s"),
    progress = S.Text("%s  %s / %s") }
local durations

function Text.Compact(value)
    value = max(0, value or 0)
    if value >= 1000000 then return ("%.1fm"):format(value / 1000000) end
    if value >= 10000 then return ("%.0fk"):format(value / 1000) end
    if value >= 1000 then return ("%.1fk"):format(value / 1000) end
    return tostring(floor(value))
end

function Text.Exact(value) return BreakUpLargeNumbers(max(0, floor(value or 0))) end

function Text.Duration(seconds)
    if not S.Finite(seconds) or seconds < 0 then return "--" end
    if not durations then
        durations = C_StringUtil.CreateSecondsFormatter()
        durations:SetDesiredUnitCount(2)
        durations:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
        durations:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
    end
    return durations:Format(floor(seconds))
end

function Text.Create(view)
    local states = {}
    view.xpTexts = states
    for _, spec in ipairs(Shared.Texts) do
        local region = S.CreateFontString(view.bar, nil, "OVERLAY", "GameFontHighlightSmall")
        states[spec.id] = { region = region, spec = spec }
        view[spec.region] = region
    end
    view.details = S.CreateFontString(view.host, nil, "OVERLAY", "GameFontHighlightSmall")
    view.details:SetPoint("TOP", view.bar, "BOTTOM", 0, -4)
    view.details:SetJustifyH("CENTER")
end

local function Placement(spec, config)
    local anchor = config[spec.prefix .. "Anchor"] or 1
    local point = anchor > 1 and NS.AnchorPoints[anchor - 1] or spec.point
    local relative, x, y = anchor > 1 and point or spec.relative, 0, 0
    if anchor == 1 then
        x, y = spec.x, spec.y
        if spec.id == "percent" and config.displayStyle == 2 then point, relative, x = "CENTER", "CENTER", 0 end
        if spec.id == "xp" and config.levelTextVisibility == 3 then x = 6 end
    end
    return point, relative, x + (config[spec.prefix .. "X"] or 0), y + (config[spec.prefix .. "Y"] or 0)
end

local function Enabled(spec, config)
    if spec.toggle then return config[spec.toggle] == true end
    local choice = config[spec.prefix .. "Visibility"] or 1
    if choice ~= 1 then return choice == 2 end
    if spec.id == "percent" then return true end
    return config.displayStyle ~= 2 and not (spec.id == "xp" and config.levelTextFormat == 4)
end

local function Show(state, shown)
    if state.shown ~= shown then
        state.region:SetShown(shown)
        state.shown = shown
    end
end

function Text.Source(view, xp)
    if view.textXPSource == xp then return end
    view.textXPSource = xp
    for _, spec in ipairs(Shared.Texts) do
        local state = view.xpTexts[spec.id]
        state.dirty = true
        Show(state, state.enabled and (xp or not spec.toggle))
    end
    view.details:SetShown(not xp)
end

local function Configure(view, state, path, epoch)
    local spec, config = state.spec, view.config
    local prefix = spec.prefix
    local font = S.ResolveFont(config[prefix .. "Font"]) or path
    local size = config[prefix .. "Size"] or 0
    if size == 0 then size = spec.id == "percent" and config.displayStyle == 2 and 20 or 11 end
    local outline = OUTLINES[config[prefix .. "Outline"] or 1]
    if not outline then outline = spec.toggle and "" or "OUTLINE" end
    if state.font ~= font or state.size ~= size or state.outline ~= outline or state.epoch ~= epoch then
        S.SetFont(state.region, font, size, outline)
        state.font, state.size, state.outline, state.epoch = font, size, outline, epoch
    end
    local format = config[prefix .. "Format"] or 1
    local number = config[prefix .. "Numbers"] == 3 and Text.Exact or Text.Compact
    local precision = format == 1 and (config.displayStyle == 2 and 0 or 1) or format - 2
    local percent = PERCENT[precision + 1] or PERCENT[2]
    state.dirty = state.dirty or state.format ~= format or state.number ~= number or state.percent ~= percent
    state.format, state.number, state.percent = format, number, percent
    state.enabled = Enabled(spec, config)
    local point, relative, x, y = Placement(spec, config)
    state.point, state.relative, state.x, state.y = point, relative, x, y
    state.region:ClearAllPoints()
    state.region:SetPoint(point, view.bar, relative, x, y)
    state.region:SetJustifyH(point:find("LEFT", 1, true) and "LEFT" or point:find("RIGHT", 1, true) and "RIGHT" or "CENTER")
    Show(state, state.enabled and (view.textXPSource ~= false or not spec.toggle))
end

function Text.Layout(view)
    local path, epoch = S.GlobalFontPath(), _G.MSUF_FontApplyEpoch
    for _, spec in ipairs(Shared.Texts) do Configure(view, view.xpTexts[spec.id], path, epoch) end
    if view.detailFont ~= path or view.detailFontEpoch ~= epoch then
        S.SetFont(view.details, path, 11, "")
        view.detailFont, view.detailFontEpoch = path, epoch
    end
    view.details:SetWidth(view.config.width)
    view.textLayoutRevision = (view.textLayoutRevision or 0) + 1
end

function Text.Color(view, r, g, b, mr, mg, mb)
    for _, spec in ipairs(Shared.Texts) do
        local region = view[spec.region]
        if spec.toggle then
            region:SetTextColor(mr, mg, mb, 1)
        else
            region:SetTextColor(r, g, b, 1)
        end
    end
    view.details:SetTextColor(mr, mg, mb, 1)
end

local function Write(state, value)
    if state.value ~= value then
        state.region:SetText(value)
        state.value = value
    end
    state.dirty = false
end

local function NumberText(state, current, maximum)
    if state.format == 3 then return state.number(current) end
    if state.format == 4 then return state.number(max(0, maximum - current)) end
    if state.maximumValue ~= maximum or state.maximumFormatter ~= state.number then
        state.maximumText = state.number(maximum)
        state.maximumValue, state.maximumFormatter = maximum, state.number
    end
    return LABELS.xp:format(state.number(current), state.maximumText)
end

function Text.PaintXP(view, level, current, maximum, gained, rate, fraction)
    if view.textXPSource ~= true then Text.Source(view, true) end
    local states, state = view.xpTexts, view.xpTexts.level
    if state.enabled and (state.dirty or state.currentInput ~= level or state.format == 4
        and (state.xpInput ~= current or state.maximumInput ~= maximum)) then
        local value = state.format == 3 and tostring(level) or LABELS.level:format(level)
        if state.format == 4 then value = LABELS.combined:format(level, state.number(current), state.number(maximum)) end
        Write(state, value)
        state.currentInput, state.xpInput, state.maximumInput = level, current, maximum
    end
    state = states.xp
    if state.enabled and (state.dirty or state.currentInput ~= current or state.maximumInput ~= maximum) then
        Write(state, NumberText(state, current, maximum))
        state.currentInput, state.maximumInput = current, maximum
    end
    state = states.percent
    if state.enabled and (state.dirty or state.currentInput ~= current or state.maximumInput ~= maximum) then
        Write(state, state.percent:format(fraction * 100))
        state.currentInput, state.maximumInput = current, maximum
    end
    state = states.session
    if state.enabled and (state.dirty or state.currentInput ~= gained) then
        local value = state.number(gained)
        Write(state, state.format == 3 and ("+" .. value) or LABELS.session:format(value))
        state.currentInput = gained
    end
    state = states.rate
    if state.enabled and (state.dirty or state.currentInput ~= rate) then
        local value = rate and state.number(rate) or "--"
        Write(state, state.format == 3 and value or LABELS.rate:format(value))
        state.currentInput = rate
    end
    state = states.eta
    if state.enabled and (state.dirty or state.rateInput ~= rate or rate and rate > 0
        and (state.currentInput ~= current or state.maximumInput ~= maximum)) then
        local value = rate and rate > 0 and Text.Duration((maximum - current) * 3600 / rate) or "--"
        Write(state, state.format == 3 and value or LABELS.eta:format(value))
        state.rateInput, state.currentInput, state.maximumInput = rate, current, maximum
    end
end

function Text.PaintProgress(view, label, current, maximum, name, capped, fraction)
    Text.Source(view, false)
    local states = view.xpTexts
    local level = states.level
    Write(level, not capped and level.format == 4 and LABELS.progress:format(label, level.number(current), level.number(maximum)) or label)
    Write(states.xp, capped and "" or NumberText(states.xp, current, maximum))
    states.xp.currentInput, states.xp.maximumInput = current, maximum
    Write(states.percent, states.percent.percent:format(fraction * 100))
    view.details:SetText(name)
end

function Text.Message(view, level, percent, details)
    Text.Source(view, false)
    for _, spec in ipairs(Shared.Texts) do Write(view.xpTexts[spec.id], "") end
    Write(view.xpTexts.level, level)
    Write(view.xpTexts.percent, percent)
    view.details:SetText(details)
end

-- Only menu samples measure text. Live XP events never measure or move it.
function Text.PreviewBounds(view)
    local width, height = view.config.width, view.config.height
    local left, right, bottom, top = 0, width, -23, height
    for _, spec in ipairs(Shared.Texts) do
        local state = view.xpTexts[spec.id]
        if state.shown then
            local w, h = state.region:GetStringWidth(), state.region:GetStringHeight()
            local own, reference = Shared.Points[state.point], Shared.Points[state.relative]
            local x = reference[1] * width + state.x - own[1] * w
            local y = reference[2] * height + state.y - own[2] * h
            left, right, bottom, top = min(left, x), max(right, x + w), min(bottom, y), max(top, y + h)
        end
    end
    return right - left, top - bottom, width / 2 - (left + right) / 2, (height - 23) / 2 - (bottom + top) / 2
end
