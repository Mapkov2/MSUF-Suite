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
    "runeChoice", "oilChoice", "mapPotion", "mapPotionItem", "mapPotionMaps", "classReminders",
}

local function SelectionChanged(state, config)
    local settings, changed = state.menuPreview.settings, false
    for _, key in ipairs(ENTRY_KEYS) do
        if settings[key] ~= config[key] then
            settings[key], changed = config[key], true
        end
    end
    -- The class reminders' own switches matter while the master switch is on.
    if config.classReminders then
        for _, def in ipairs(NS.BuffReminderClassReminders) do
            if settings[def.key] ~= config[def.key] then
                settings[def.key], changed = config[def.key], true
            end
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

-- The first spell of a class reminder's plan: the icon its sample shows.
local function SampleSpell(plan)
    if plan.kind == "imbue" then return plan.imbues[1].spell end
    return plan.casts[1]
end

-- A sample class shows its class buff, two sample spells and, with the class
-- reminders on, one icon for each of that class's switched-on reminders.
local function ClassSample(state, sample, config)
    local entries = state.menuPreview.classEntries
    if not entries then entries = {}
    state.menuPreview.classEntries = entries end
    local count = 3
    if state.menuPreview.classSample ~= sample then
        state.menuPreview.classSample = sample
        local buff = R.ClassBuff(sample[1])
        for i = 1, count do
            local entry = entries[i] or {}
            entries[i] = entry
            entry.kind, entry.category = "spell", i == 1 and "class" or "personal"
            entry.id = i == 1 and buff and buff.cast or sample[i + 2]
            entry.previewTexture = sample[6]
            entry.group = i == 1 and buff ~= nil
        end
    end
    if config.classReminders then
        for _, def in ipairs(NS.BuffReminderClassReminders) do
            local plan = R.ClassPlan(def)
            if plan and def.class == sample[1] and config[def.key] ~= false then
                count = count + 1
                local entry = entries[count] or {}
                entries[count] = entry
                entry.kind, entry.category, entry.id = "spell", "class", SampleSpell(plan)
                entry.previewTexture, entry.group = sample[6], false
            end
        end
    end
    for i = #entries, count + 1, -1 do entries[i] = nil end
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
    local entries, view = classSample and ClassSample(state, classSample, config) or state.list.entries, state.view
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
