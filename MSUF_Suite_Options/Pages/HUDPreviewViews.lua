local _, P = ...
local V, Tr = P.HUDPreview, P.Tr
local DrawText, Fill, Color = V.Label, V.Fill, V.Color
local TEXT, MUTED = { .95, .96, .98 }, { .78, .81, .85 }
local COMPLETE, SCENARIO, FOCUSED, LATE = { .39, .86, .54 }, { .39, .64, .90 }, { .98, .84, .42 }, { .92, .36, .36 }

-- The Mythic+ and raid views of the objective tracker preview, drawn from the
-- same settings as MSUF_Suite_Modules/MythicPlus.lua and Raid.lua. They show
-- an example key and an example boss pull; each draw function takes the next
-- free row and returns the one below its last.
local SAMPLE_LIMIT, SAMPLE_ELAPSED, SAMPLE_LATE_ELAPSED = 1800, 1422, 1890
local FORCES_PERCENT = 61.4
local BOSS_TIMES = { 252, 665 }
-- The pace comparison of the first two bosses, in seconds against the reference.
local BOSS_PACE = { -8, 22 }

local function Clock(seconds)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function Right(label) return label:SetJustifyH("RIGHT") end

-- The timer bar, its fill in the bracket color (over time: the late color),
-- the upgrade thresholds and the time inside it.
local function TimerBar(ui, y, late)
    local c, width = ui.config, ui.config.width
    local elapsed = late and SAMPLE_LATE_ELAPSED or SAMPLE_ELAPSED
    local barWidth = width - 22
    local color = { Color(c, late and "lateColor" or "scenarioColor", late and LATE or SCENARIO) }
    Fill(ui, 11, y, barWidth, c.timerBarHeight, { .15, .17, .20 }, .55)
    Fill(ui, 11, y, barWidth * math.min(1, elapsed / SAMPLE_LIMIT), c.timerBarHeight, color)
    if c.timerThresholds then
        for _, share in ipairs({ .6, .8 }) do
            Fill(ui, 11 + barWidth * share, y + 2, 1, c.timerBarHeight + 4, { 1, 1, 1 }, .75)
        end
    end
    if c.timerBarText then
        DrawText(ui, Clock(elapsed) .. " / " .. Clock(SAMPLE_LIMIT), 11, y, barWidth, 11, { Color(c, "textColor", TEXT, "text") })
            :SetJustifyH("CENTER")
    end
    return y - c.timerBarHeight - 12
end

-- The clock, the time left and the three upgrade windows.
local function Timer(ui, y, late)
    local c, width = ui.config, ui.config.width
    local text, muted = { Color(c, "textColor", TEXT, "text") }, { Color(c, "mutedColor", MUTED, "muted") }
    local elapsed = late and SAMPLE_LATE_ELAPSED or SAMPLE_ELAPSED
    DrawText(ui, Tr("Example Dungeon") .. "  +15", 11, y, width - 22, c.entrySize, text)
    y = y - c.entrySize - 8
    local clockSize = math.max(23, c.titleSize + 6)
    DrawText(ui, Clock(elapsed) .. " / " .. Clock(SAMPLE_LIMIT), 11, y, width - 22, clockSize, text)
    local left = SAMPLE_LIMIT - elapsed
    Right(DrawText(ui, left >= 0 and Tr("%s LEFT"):format(Clock(left)) or Tr("%s OVER"):format(Clock(-left)),
        11, y - 6, width - 22, c.objectiveSize, muted))
    y = TimerBar(ui, y - clockSize - 10, late)
    local colors = { { Color(c, "completeGroupColor", COMPLETE) }, { Color(c, "scenarioColor", SCENARIO) },
        { Color(c, "focusedColor", FOCUSED) } }
    for window = 3, 1, -1 do
        local cutoff = SAMPLE_LIMIT * (1 - (window - 1) * .2)
        DrawText(ui, "+" .. window .. "  " .. Clock(cutoff), 11, y, width - 22, c.objectiveSize, colors[4 - window])
        Right(DrawText(ui, cutoff >= elapsed and Tr("%s left"):format(Clock(cutoff - elapsed)) or Tr("missed"),
            11, y, width - 22, c.objectiveSize, muted))
        y = y - c.chestSpacing
    end
    return y - 4
end

-- Deaths, affixes, the enemy forces text and bar and the observed pull.
local function Forces(ui, y)
    local c, width = ui.config, ui.config.width
    local text, muted = { Color(c, "textColor", TEXT, "text") }, { Color(c, "mutedColor", MUTED, "muted") }
    DrawText(ui, Tr("DEATHS  %s     TIME PENALTY  +%s"):format(2, "0:10"), 11, y, width - 22, c.objectiveSize, text)
    y = y - c.objectiveSize - 9
    DrawText(ui, Tr("AFFIXES  %s"):format(Tr("Example affix")), 11, y, width - 22, c.objectiveSize - 1, muted)
    y = y - c.objectiveSize - 9
    if c.showForcesText then
        DrawText(ui, Tr("ENEMY FORCES  %s"):format(string.format("%.1f%%", FORCES_PERCENT)), 11, y, width - 22,
            c.forcesTextSize, text)
        y = y - c.forcesTextSize - 8
    end
    if c.showForcesBar then
        local barWidth = (width - 22) * c.forcesBarWidth / 100
        local x = 11 + (width - 22 - barWidth) / 2
        Fill(ui, x, y, barWidth, c.forcesBarHeight, { .15, .17, .20 }, .55)
        Fill(ui, x, y, barWidth * FORCES_PERCENT / 100, c.forcesBarHeight, { Color(c, "scenarioColor", SCENARIO) })
        y = y - c.forcesBarHeight - 8
    end
    if c.showObservedPull then
        DrawText(ui, Tr("Observed enemies  +%.1f%%  (total %.1f%%)"):format(8.2, FORCES_PERCENT + 8.2), 11, y, width - 22,
            c.objectiveSize - 1, muted)
        y = y - c.objectiveSize - 8
    end
    return y
end

-- The boss rows: two defeated with their split (and, with a pace reference,
-- how far ahead or behind), the third alive (with its target time on request).
local function Bosses(ui, y)
    local c, width = ui.config, ui.config.width
    local text, muted = { Color(c, "textColor", TEXT, "text") }, { Color(c, "mutedColor", MUTED, "muted") }
    local size = math.max(10, c.objectiveSize - 1)
    local paced = c.bossPace > 1
    DrawText(ui, Tr("BOSSES / OBJECTIVES"), 11, y, width - 22, size, { Color(c, "scenarioColor", SCENARIO) })
    y = y - size - 9
    for index = 1, 3 do
        local done = index <= #BOSS_TIMES
        DrawText(ui, (done and "|A:common-icon-checkmark:12:12|a  " or "\194\183  ") .. Tr("Boss %d"):format(index),
            11, y, width - 22, size, text)
        local split = done and Clock(BOSS_TIMES[index]) or ""
        if done and paced then split = split .. "  " .. (BOSS_PACE[index] >= 0 and "+" or "-") .. Clock(math.abs(BOSS_PACE[index])) end
        if not done and paced and c.bossTargets then split = Clock(960) end
        Right(DrawText(ui, split, 11, y, width - 22, size, muted))
        y = y - size - 8
    end
    return y
end

-- Forever has no Mythic+.
if not P.Suite.Client.isForever then
    local function Mythic(late)
        return function(ui, y) return Bosses(ui, Forces(ui, Timer(ui, y, late))) end
    end
    V.Views.mythic = { title = "MYTHIC+", count = "+15", draw = Mythic(false) }
    V.Views.mythicLate = { title = "MYTHIC+", count = "+15", draw = Mythic(true) }
end

-- The raid encounter view: boss, pull clock, phase and the records.
V.Views.raid = { title = "RAID", count = "Mythic", draw = function(ui, y)
    local c, width = ui.config, ui.config.width
    local text, muted = { Color(c, "textColor", TEXT, "text") }, { Color(c, "mutedColor", MUTED, "muted") }
    local rows = {
        { Tr("Example Boss"), c.entrySize, text },
        { "4:34", math.max(23, c.titleSize + 5), text },
        { Tr("PHASE  %s"):format("2  \194\183  BigWigs"), c.objectiveSize, muted },
        { Tr("ACTIVE BOSSES  %s"):format(Tr("Example Boss") .. " 41.0%"), c.objectiveSize, muted },
        { Tr("BEST PULL  %s"):format(Tr("%d defeated"):format(1) .. "  \194\183  12.3%"), c.objectiveSize, text },
        { Tr("FASTEST KILL  %s"):format("4:12"), c.objectiveSize, muted },
    }
    for _, row in ipairs(rows) do
        DrawText(ui, row[1], 11, y, width - 22, row[2], row[3])
        y = y - row[2] - 9
    end
    return y
end }
