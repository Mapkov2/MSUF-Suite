local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
-- Selection is the runtime's entry compiler, using a separate buffer and
-- state. Appearance refreshes reuse the list: moving a size slider never
-- scans bags or changes live aura/count caches, secure buttons or sounds.
local ENTRY_KEYS = {
    "classBuff", "groupBuff", "otherClassBuffs", "autoRoguePoisons", "campfireBuff",
    "spellIDs", "items", "mainHandItem", "offHandItem", "autoFlask", "autoFood",
    "autoRune", "autoWeapon", "restockNotice", "flaskChoice", "foodChoice",
    "runeChoice", "oilChoice", "mapPotion", "mapPotionItem", "mapPotionMaps",
}

local function SelectionChanged(state, config)
    local settings, changed = state.menuPreview.settings, false
    for _, key in ipairs(ENTRY_KEYS) do
        if settings[key] ~= config[key] then
            settings[key], changed = config[key], true
        end
    end
    return changed
end

local function State(stage)
    local state = stage.buffReminderPreview
    if not state then
        state = R.NewState({})
        state.view.host, state.view.buttons = stage, {}
        state.menuPreview.buffer, state.menuPreview.settings = R.NewEntryBuffer(), {}
        stage.buffReminderPreview = state
    end
    return state
end

function S.BuffRemindersDrawPreview(stage, config, dirty, open)
    local state = State(stage)
    state.config = config
    local changed = SelectionChanged(state, config)
    if dirty or changed or not state.list.entries then
        state.list.entries = R.BuildEntries(state, state.menuPreview.buffer)
    end
    local entries, view = state.list.entries, state.view
    local width, height = R.IconGeometry(config, #entries)
    stage:SetSize(width, height)
    for index = 1, math.max(#entries, #view.buttons) do
        local button = view.buttons[index]
        local entry = entries[index]
        if not button then
            button = CreateFrame("Button", nil, stage)
            R.CreateIcon(button)
            button:SetScript("OnClick", open)
            view.buttons[index] = button
        end
        button.entry = entry
        if entry then
            R.PaintEntry(button, entry)
            R.StyleCount(button, config)
            button.count:SetText(R.PreviewCount(entry))
            button:SetSize(config.size, config.size)
            R.PositionIcon(button, stage, index - 1, config)
        end
        R.AlertTransition(state, button, entry, entry ~= nil)
        button:SetShown(entry ~= nil)
    end
    view.newAlert = nil
    return width, height, #entries
end

function S.BuffRemindersReleasePreview(stage)
    local state = stage.buffReminderPreview
    if state then R.StopReminderAlerts(state) end
end
