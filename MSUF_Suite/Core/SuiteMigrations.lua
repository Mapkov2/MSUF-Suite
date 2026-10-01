local _, NS = ...
-- The saved data upgrades of the Suite's module settings: one function per
-- migration step or repair. Their order and the revision bookkeeping live
-- in Suite.lua (MIGRATIONS, REPAIRS), which runs them from S.Normalize.
local Steps = {}
NS.SuiteMigrationSteps = Steps
local Catalog = NS.SuiteCatalog

local function Module(modules, id)
    local config = modules[id]
    return type(config) == "table" and config or nil
end

local function EnsureModule(modules, id)
    local config = Module(modules, id)
    if not config then
        config = {}
        modules[id] = config
    end
    return config
end

Steps.EnsureModule = EnsureModule

local function HasSettings(config)
    return config ~= nil and next(config) ~= nil
end

function Steps.ObjectivesTransparent(modules)
    -- The original tracker factory used an opaque card; its exact standard
    -- value moves to the transparent HUD look.
    local objectives = Module(modules, "objectives")
    if objectives and objectives.backgroundOpacity == 82
        and (objectives.colorStyle == nil or objectives.colorStyle == 1) then
        objectives.backgroundOpacity = 0
    end
end

function Steps.HudTypography(modules)
    -- Grow only the previous HUD factory text sizes. Different user choices stay.
    local objectives = Module(modules, "objectives")
    if objectives then
        local title, section = objectives.titleSize, objectives.sectionSize
        if title == nil or title == 16 or title == 17 then objectives.titleSize = 18 end
        if section == nil or section == 10 or section == 16 then objectives.sectionSize = 14 end
        if objectives.entrySize == nil or objectives.entrySize == 13 then objectives.entrySize = 15 end
        if objectives.objectiveSize == nil or objectives.objectiveSize == 11 then objectives.objectiveSize = 13 end
    end
    local announcements = Module(modules, "announcements")
    if announcements and (announcements.subtitleSize == nil or announcements.subtitleSize == 15) then
        announcements.subtitleSize = 16
    end
end

function Steps.ExperienceBarTop(modules)
    -- The former Suite and Forever XP factory positions were at the bottom of
    -- the screen. Move only those known positions to the top center.
    local xp = Module(modules, "xpBar")
    if xp and (xp.point == nil or xp.point == 8)
        and (xp.x == nil or xp.x == 0 or xp.x == 12)
        and (xp.y == nil or xp.y == 148 or xp.y == 1040) then
        xp.point, xp.x, xp.y = 2, 0, -24
    end
end

function Steps.AnnouncementsAnchor(modules)
    -- Older announcement positions were offsets from screen center. Keep them
    -- when new profiles start from the top-center anchor.
    local announcements = Module(modules, "announcements")
    if announcements and announcements.anchor == nil and type(announcements.y) == "number" then
        announcements.anchor = 2
    end
end

function Steps.AnnouncementsFactory(modules)
    -- The first announcements factory showed zones only. It now also replaces
    -- Blizzard's quest, achievement, level and scenario banners.
    local old = Module(modules, "announcements")
    if old and old.eventToasts == nil and old.zone == true
        and old.quests == false and old.achievements == false
        and old.level == false and old.scenario == false
        and old.duration == 4 and old.scale == 100 and old.x == 0 and old.y == -170 then
        old.quests, old.achievements, old.level, old.scenario = true, true, true, true
    end
end

function Steps.DataTextsBagButtons(modules)
    -- An older Retail profile may have DataTexts without a Bag space slot.
    -- Keep Blizzard's bag buttons until that player explicitly chooses this.
    local data = Module(modules, "dataTexts")
    if not data or data.hideBlizzardBagBar ~= nil then return end
    local anySlot = false
    for bar = 1, 3 do
        for slot = 1, 6 do
            local source = data["bar" .. bar .. "Slot" .. slot]
            if source == 3 then return end
            if source ~= nil then anySlot = true end
        end
    end
    if anySlot then data.hideBlizzardBagBar = false end
end

function Steps.ActionBarsCustomLook(modules)
    -- Action bar looks are newer than the bars. Existing profiles keep their
    -- exact button colors and spacing and show them as Custom.
    local bars = Module(modules, "actionbars")
    if HasSettings(bars) and bars.look == nil then bars.look = Catalog.actionbars.look.custom end
end

function Steps.BagsCustomLook(modules)
    -- The previous bag appearance was the Forever palette on every client.
    -- Keep it, including missing visual fields in partial saved profiles.
    local bags = Module(modules, "bags")
    if not HasSettings(bags) or bags.look ~= nil then return end
    local look = Catalog.bags.look
    for key, value in pairs(look.presets[3]) do
        if bags[key] == nil then bags[key] = value end
    end
    bags.look = look.custom
end

function Steps.LookRenumbering(modules)
    -- Preset 2 used to mean Forever and preset 3 meant Custom. Translate the
    -- stored choices before catalog defaults can fill new fields.
    local legacyDefault = NS.Client.isForever and 3 or 1
    for _, id in ipairs({ "chat", "damageMeter" }) do
        local config = Module(modules, id)
        if HasSettings(config) then
            if config.look == nil then
                local custom = false
                for key, value in pairs(Catalog[id].look.presets[legacyDefault]) do
                    if config[key] == nil then
                        config[key] = value
                    elseif config[key] ~= value then
                        custom = true
                    end
                end
                config.look = custom and 4 or legacyDefault
            elseif config.look == 2 then
                config.look = 3
            elseif config.look == 3 then
                config.look = 4
            end
        end
    end
    local data = Module(modules, "dataTexts")
    if HasSettings(data) then
        if data.look == nil then
            data.look = legacyDefault
        elseif data.look == 2 then
            data.look = 3
        end
        for bar = 1, 3 do
            local key = "bar" .. bar .. "Look"
            if data[key] == 2 then
                data[key] = 3
            elseif data[key] == nil and data["bar" .. bar .. "StyleOverride"] then
                data[key] = legacyDefault
            end
        end
    end
    local xp = Module(modules, "xpBar")
    if HasSettings(xp) then
        if xp.look == nil then
            xp.look = legacyDefault
        elseif xp.look == 2 then
            xp.look = 3
        end
    end
end

function Steps.SkyridingColors(modules)
    -- Older Skyriding profiles have a selected look but no editable colors.
    -- Seed only missing fields from that look before defaults apply.
    local sky = Module(modules, "skyriding")
    if not sky then return end
    local presets = Catalog.skyriding.look.presets
    for key, value in pairs(presets[sky.look] or presets[1]) do
        if sky[key] == nil then sky[key] = value end
    end
end

function Steps.ForeverHud(modules)
    -- Forever previously exposed these HUD settings while marking both modules
    -- unavailable. Activate them once now that the runtime is supported.
    EnsureModule(modules, "objectives").enabled = true
    EnsureModule(modules, "announcements").enabled = true
end

function Steps.ForeverActionBars(modules)
    -- Forever profiles normalized with the old disabled default start the bars.
    EnsureModule(modules, "actionbars").enabled = true
end

local PREVIOUS_FOREVER_VISIBILITY = { 1, 1, 4, 1, 4, 6, 6, 6, 6, 6, 1, 1 }
function Steps.ForeverLayout(modules)
    -- Repair the original Forever factory stack without moving bars whose
    -- position or size was customized.
    local data = Module(modules, "dataTexts")
    if data and data.bar1Width == 270 and data.bar1Layout == 1
        and data.bar1Point == 9 and data.bar1X == -20 and data.bar1Y == 20
        and data.bar1Slot1 == 3 and data.bar1Slot2 == 4 and data.bar1Slot3 == 5 then
        data.bar1Width, data.bar1Layout = 340, 2
    end
    local meter = Module(modules, "damageMeter")
    if meter and meter.windowCount == 2
        and meter.w1Width == 260 and meter.w1Height == 170 and meter.w1X == -20 and meter.w1Y == 20
        and meter.w2Width == 260 and meter.w2Height == 170 and meter.w2X == -20 and meter.w2Y == 210 then
        meter.w1Width, meter.w1Y = 340, 60
        meter.w2Width, meter.w2Y = 340, 250
    end
    local bars = Module(modules, "actionbars")
    if not bars or bars.imported ~= false then return end
    for i, visibility in ipairs(PREVIOUS_FOREVER_VISIBILITY) do
        if bars["bar" .. i .. "Visibility"] ~= visibility
            or bars["bar" .. i .. "ResumeVisibility"] ~= (visibility == 6 and 1 or visibility) then
            return
        end
    end
    for i = 1, #PREVIOUS_FOREVER_VISIBILITY do
        bars["bar" .. i .. "Visibility"] = 4
        bars["bar" .. i .. "ResumeVisibility"] = 4
    end
end

function Steps.ForeverPalette(modules)
    local chat = Module(modules, "chat")
    if chat and chat.look == 3 and chat.inputColor == "1a1a1b" then chat.inputColor = "111517" end
    local reminders = Module(modules, "buffReminders")
    if reminders and reminders.borderColor == "e8b855" then reminders.borderColor = "d8b66a" end
    local cooldowns = Module(modules, "cooldownManager")
    if cooldowns then
        for key, color in pairs(cooldowns) do
            if type(key) == "string" and key:sub(-8) == "barColor" and color == "e8b855" then
                cooldowns[key] = "d8b66a"
            end
        end
    end
end

function Steps.ObjectivesCollapseState(modules, db)
    -- Collapsed tracker groups used to live inside the settings. They are
    -- runtime state the tracker owns (see S.ModuleState).
    local objectives = Module(modules, "objectives")
    if not objectives then return end
    local groups, entries = objectives.collapsedGroups, objectives.collapsedEntries
    if groups == nil and entries == nil then return end
    objectives.collapsedGroups, objectives.collapsedEntries = nil, nil
    if type(groups) ~= "table" and type(entries) ~= "table" then return end
    db.moduleState = type(db.moduleState) == "table" and db.moduleState or {}
    local state = type(db.moduleState.objectives) == "table" and db.moduleState.objectives or {}
    db.moduleState.objectives = state
    if type(groups) == "table" then state.collapsedGroups = groups end
    if type(entries) == "table" then state.collapsedEntries = entries end
end

function Steps.JundiesNameplateSize(modules)
    -- The first Jundies preset selected Small, shrinking Blizzard's Modern
    -- plate to 75% width. Update only that preset's former size. Editing a
    -- visual setting in the Suite UI switches the look to Custom.
    local plates = Module(modules, "nameplates")
    if plates and plates.look == 1 and plates.nativeStyle == 2 and plates.nativeSize == 2 then
        plates.nativeSize = 3
    end
end

function Steps.JundiesNameplateMarkers(modules)
    -- Early Jundies builds enabled a text star in the middle of the bar.
    -- Custom profiles keep their choice; the preset uses Blizzard's marker.
    local plates = Module(modules, "nameplates")
    if plates and plates.look == 1 then
        plates.enemyEliteMarker, plates.enemyQuestMarker = false, false
    end
end

function Steps.NameplateCastVisibility(modules)
    local plates = Module(modules, "nameplates")
    -- Early profiles styled castbars before the visibility setting existed.
    -- Repair that combination once; explicit Hide and Blizzard look survive.
    if plates and plates.look ~= 2 and plates.enemyCastSkin == true
        and plates.enemyCastDisplay == 2 and plates.enemyCastEnabled == 1 then
        plates.enemyCastEnabled = 2
    end
end

function Steps.JundiesNameplatePalette(modules)
    local plates = Module(modules, "nameplates")
    if not plates or plates.look ~= 1 then return end
    local corrections = {
        enemyTextOutline = { 1, 4 }, friendlyTextOutline = { 1, 4 }, enemyCastOutline = { 1, 4 },
        enemyNeutralColor = { "e5bd45", "e5db00" }, enemyTrivialColor = { "777777", "be301d" },
        enemyThreatLostColor = { "ff4d32", "dd6f00" }, enemyThreatWarningColor = { "ffbd38", "ffe93a" },
        enemyNeutralEnabled = { false, true }, enemyTrivialEnabled = { false, true },
        enemyQuestMarker = { false, true }, enemyQuestOffsetX = { 0, -14 }, enemyQuestOffsetY = { 17, 0 },
        enemyQuestMarkerAnchor = { 1, 5 },
    }
    for key, values in pairs(corrections) do
        if plates[key] == values[1] then plates[key] = values[2] end
    end
end

function Steps.NameplateNativeCastOpacity(modules)
    local plates = Module(modules, "nameplates")
    -- The old preset used a translucent overlay above an opaque native fill.
    -- A replacement fill must be opaque by default. Preserve custom choices.
    if plates and plates.look == 1 and plates.enemyCastFillAlpha == 35 then plates.enemyCastFillAlpha = 100 end
end

function Steps.FriendlyPlayerDisplay(modules)
    local plates = Module(modules, "nameplates")
    if not plates then return end
    -- The former group-only switch overrode the friendly plate dropdown.
    -- Preserve that visible result before removing the second control.
    if plates.friendlyGroupOnly == true then
        plates.friendlyNamesOnly = 3
    elseif plates.friendlyNamesOnly == 3 then
        plates.friendlyNamesOnly = 4
    end
    plates.friendlyGroupOnly = nil
end
