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

local function ClassSample(state, sample)
    local entries = state.menuPreview.classEntries
    if not entries then entries = {}
    state.menuPreview.classEntries = entries end
    if state.menuPreview.classSample ~= sample then
        state.menuPreview.classSample = sample
        local buff = R.ClassBuff(sample[1])
        for i = 1, 3 do
            local entry = entries[i] or {}
            entries[i] = entry
            entry.kind, entry.category = "spell", i == 1 and "class" or "personal"
            entry.id = i == 1 and buff and buff.cast or sample[i + 2]
            entry.previewTexture = sample[6]
            entry.group = i == 1 and buff ~= nil
        end
    end
    return entries
end

function S.BuffRemindersDrawPreview(stage, config, dirty, open, classSample)
    local state = State(stage)
    state.config = config
    if state.menuPreview.activeClass ~= classSample then
        state.menuPreview.activeClass, dirty = classSample, true
    end
    local changed = SelectionChanged(state, config)
    if not classSample and (dirty or changed or not state.list.entries) then
        state.list.entries = R.BuildEntries(state, state.menuPreview.buffer)
    end
    local entries, view = classSample and ClassSample(state, classSample) or state.list.entries, state.view
    local width, height = R.IconGeometry(config, #entries)
    stage:SetSize(width, height)
    local shape, look = R.IconLook(config)
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
            if classSample and not C_Spell.GetSpellTexture(entry.id) then button.icon:SetTexture(entry.previewTexture) end
            R.StyleCount(button, config)
            button.count:SetText(R.PreviewCount(entry))
            button:SetSize(config.size, config.size)
            R.StyleIcon(button, config, look, shape)
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
