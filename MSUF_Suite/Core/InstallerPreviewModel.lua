local _, Suite = ...
-- A read-only overview of the staged factory. Rectangles use the supplied
-- frame/module geometry; bars and icons contain illustrative sample values.
local Model = {}
Suite.InstallerPreviewModel = Model
local max, min = math.max, math.min
local POINTS = { { 0, 0 }, { .5, 0 }, { 1, 0 }, { 0, .5 }, { .5, .5 }, { 1, .5 },
    { 0, 1 }, { .5, 1 }, { 1, 1 } }
local WIDTH, HEIGHT = 2560, 1440
local POINT_INDEX = { TOPLEFT = 1, TOP = 2, TOPRIGHT = 3, LEFT = 4, CENTER = 5,
    RIGHT = 6, BOTTOMLEFT = 7, BOTTOM = 8, BOTTOMRIGHT = 9 }
local SLANT_ROOT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\slanted_bar_"
local SLANT_SUFFIX = { RIGHT_UP = "_right_up", LEFT_DOWN = "_left_down" }

local function Number(value, fallback)
    return Suite.Finite(value) and value or fallback
end

function Model.Viewport(options)
    local parent = _G.UIParent
    local current = max(.01, Number(parent:GetEffectiveScale(), 1))
    local scale = options and options.useScale and options.scale or current
    scale = max(.3, Number(scale, current))
    local width, height = GetPhysicalScreenSize()
    return { width = max(1, Number(parent:GetWidth(), WIDTH)) * current / scale,
        height = max(1, Number(parent:GetHeight(), HEIGHT)) * current / scale,
        physicalWidth = max(1, Number(width, WIDTH)), physicalHeight = max(1, Number(height, HEIGHT)),
        scale = scale, keepFrames = options and options.keepFrames }
end

local function Add(scene, key, label, x, y, width, height, kind, config)
    width, height = max(1, width), max(1, height)
    scene[#scene + 1] = { key = key, label = label, x = x, y = y,
        width = width, height = height, kind = kind or "bar", config = config }
    scene[key] = scene[#scene]
    local module = key:match("^bar%d") and "actionbars" or key:match("^data%d") and "dataTexts"
        or key:match("^w%d") and "damageMeter" or key == "quests" and "objectives"
        or (key == "cooldowns" or key == "utilityCooldowns" or key == "defensiveCooldowns"
            or key == "externalCooldowns") and "cooldownManager"
        or key == "minimap" and "minimap"
        or key == "compass" and "navigationHUD"
        or key == "actions" and "actionTracker" or key == "battleRes" and "battleRes"
        or key == "raidControl" and "groupRaidShortcuts"
        or key == "chat" and "chat" or key == "experience" and "xpBar" or "frames"
    scene[#scene].module = module
    return scene[#scene]
end

local function Place(scene, key, label, point, x, y, width, height, kind, config)
    local anchor = POINTS[point] or POINTS[5]
    return Add(scene, key, label, anchor[1] * (scene.width - width) + x,
        anchor[2] * (scene.height - height) - y, width, height, kind, config)
end

local FRAMES = { { "player", "Player" }, { "target", "Target" },
    { "pet", "Pet" }, { "focus", "Focus" }, { "boss", "Boss" } }
local function ScreenAnchor(config, general)
    -- UF_Config.ResolveAnchorSettings: a frame's explicit anchor wins over
    -- the inherited anchor. Only screen-relative positions are projected.
    local name = config.anchorFrameName
    if name and name ~= "" then return name == "UIParent" or name == "UI_Parent" end
    local unit = config.anchorToUnitframe
    if unit and unit ~= "" and unit ~= "FREE" and unit ~= "GLOBAL" and unit ~= "global" then return false end
    if general and general.anchorToCooldown == true then return false end
    name = general and general.anchorName
    return not name or name == "" or name == "UIParent" or name == "UI_Parent" or name == "WorldFrame"
end

local function Frames(scene, frames)
    if not frames then return end
    local general = frames.general
    local playerRect
    for _, entry in ipairs(FRAMES) do
        local config = frames[entry[1]]
        local cooldown = scene.cooldowns
        local mainFrame = entry[1] == "player" or entry[1] == "target"
        local sharedCooldownAnchor = config and mainFrame and not scene.keepFrames and general
            and general.anchorToCooldown == true and general.cooldownAnchorPosition == "CENTER"
            and (not config.anchorFrameName or config.anchorFrameName == "")
            and (not config.anchorToUnitframe or config.anchorToUnitframe == "GLOBAL")
        local cooldownAnchor = config and not scene.keepFrames and cooldown
            and config.anchorFrameName == "EssentialCooldownViewer" and mainFrame
        local owner = config and scene[config.anchorToUnitframe]
        local unitAnchor = type(owner) == "table" and not scene.keepFrames
            and (not config.anchorFrameName or config.anchorFrameName == "")
        if config and config.enabled ~= false and (sharedCooldownAnchor or cooldownAnchor or unitAnchor or ScreenAnchor(config, general)) then
            local reference = Number(config.screenPositionHeight, 0)
            local factor = config.screenPositionMode == "relativeHeight" and not config.anchorToUnitframe
                and reference >= 400 and reference <= 10000 and scene.height >= 400 and scene.height <= 10000
                and math.abs(scene.height - reference) > .01 and scene.height / reference or 1
            local width, height = Number(config.width or config.frameWidth, 275), Number(config.height or config.frameHeight, 40)
            local point, relative = POINT_INDEX[config.point] or 5, POINT_INDEX[config.relativePoint or config.point] or 5
            local originX, originY, originWidth, originHeight, dx, dy = 0, 0, scene.width, scene.height, 0, 0
            if cooldownAnchor then
                -- UF_Config.CooldownAnchorRule: an explicitly named Essential
                -- anchor uses the physical RIGHT/LEFT edge and 20-unit gap.
                point, relative = entry[1] == "player" and 6 or 4, entry[1] == "player" and 4 or 6
                if config.cooldownAnchorFrameTop then
                    point, relative = entry[1] == "player" and 3 or 1, entry[1] == "player" and 1 or 3
                end
                dx = entry[1] == "player" and -20 or 20
                originX, originY, originWidth, originHeight = cooldown.x, cooldown.y, cooldown.width, cooldown.height
            elseif sharedCooldownAnchor and cooldown then
                point, relative = 5, 5
                dy = -Number(general.cooldownAnchorLayoutY, -180)
                originX, originY, originWidth, originHeight = cooldown.x, cooldown.y, cooldown.width, cooldown.height
            elseif unitAnchor then
                originX, originY, originWidth, originHeight = owner.x, owner.y, owner.width, owner.height
            end
            local anchor, origin = POINTS[point], POINTS[relative]
            local rect = Add(scene, entry[1], entry[2], originX + origin[1] * originWidth - anchor[1] * width
                + (Number(config.offsetX or config.x, 0) + dx) * factor,
                originY + origin[2] * originHeight - anchor[2] * height - (Number(config.offsetY or config.y, 0) + dy) * factor,
                width, height, "bar", config)
            local reaction = scene.layout == "wayfarer" and not scene.keepFrames
                and (entry[1] == "target" or entry[1] == "boss") and "enemy"
            rect.fillColor = Suite.InstallerFrameColors.HealthFill(frames, "unit", config, reaction)
            if entry[1] == "player" then playerRect = rect end
        elseif config and config.enabled ~= false then
            scene.externalFrames = true
        end
    end
    local target, companion = scene.target, frames.targettarget
    if target and not scene.keepFrames and companion and companion.enabled ~= false and companion.anchorToUnitframe == "target" then
        local width = Number(companion.width, 138)
        local fraction = companion.point == "TOP" and .5 or 1
        local x = target.x + (target.width - width) * fraction + Number(companion.offsetX, 0)
        local rect = Add(scene, "targettarget", "Target of Target", x, target.y + target.height - Number(companion.offsetY, -68),
            width, Number(companion.height, 16), "bar", companion)
        rect.fillColor = Suite.InstallerFrameColors.HealthFill(frames, "unit", companion)
    end
    local bars = frames.bars
    -- Retained class resources may follow a live external CDM provider. The
    -- sample icon row cannot resolve its actual rect, so disclose the omission.
    if bars and playerRect and bars.showClassPower ~= false and scene.keepFrames and bars.classPowerAnchorToCooldown == true then
        scene.externalFrames = true
        return
    end
    if bars and playerRect and bars.showClassPower ~= false then
        local mode = bars.classPowerWidthMode or "player"
        local width = mode == "custom" and Number(bars.classPowerWidth, 0) or playerRect.width
        if width < 30 then width = playerRect.width - 4 end
        local inset = mode == "player" and 0 or 2
        -- MSUF_CP_Core.Layout.Position: fallback TOPLEFT on the player,
        -- including the two-unit vertical inset. These are relative offsets.
        Add(scene, "resource", "Resources", playerRect.x + inset + Number(bars.classPowerOffsetX, 0),
            playerRect.y + 2 - Number(bars.classPowerOffsetY, 0), width,
            Number(bars.classPowerHeight, 4), "resource", bars)
    end
end

local ACTION_BARS = { 1, 2, 3, 4, 5 }
local MODERN_ACTION_BARS = { 1, 2, 3, 4, 5, 12 }
local function ActionBars(scene, config)
    if not config or config.enabled == false then return end
    for _, index in ipairs(scene.layout == "modernDark" and MODERN_ACTION_BARS or ACTION_BARS) do
        local prefix = "bar" .. index
        if config[prefix .. "Visibility"] ~= Suite.ActionBarEnum.VISIBILITY.NEVER then
            local count = max(1, Number(config[prefix .. "Buttons"], 12))
            local columns, rows = Suite.ActionBarGrid(count, Number(config[prefix .. "Rows"], 1),
                config[prefix .. "Vertical"])
            local size, gap = Number(config[prefix .. "Size"], 40), Number(config[prefix .. "Spacing"], 2)
            local buttonHeight = config.buttonShape == Suite.ActionBarEnum.BUTTON_SHAPE.SQUARE
                and math.floor(size * Number(config[prefix .. "HeightPercent"], 100) / 100 + .5) or size
            local width, height = columns * size + (columns - 1) * gap, rows * buttonHeight + (rows - 1) * gap
            local item = Place(scene, prefix, index == 12 and "Pet bar" or "Action bars", config[prefix .. "Point"] or 8,
                Number(config[prefix .. "X"], 0), Number(config[prefix .. "Y"], 0), width, height, "icons", config)
            item.columns, item.rows, item.count = columns, rows, count
            item.iconWidth, item.iconHeight, item.gap = size, buttonHeight, gap
        end
    end
end

local function ColorHex(r, g, b)
    return string.format("%02x%02x%02x",
        math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5))
end

local function PresetBossStack(scene, general, color)
    local first = scene.boss
    if not first then return end
    local spacing = Number(first.config.spacing, -64)
    local castHeight = Number(general.bossCastbarHeight, 12)
    for index = 1, 5 do
        local key, y = "boss" .. index, first.y - (index - 1) * spacing
        if index > 1 then
            local boss = Add(scene, key, first.label, first.x, y, first.width, first.height, "bar", first.config)
            boss.fillColor = first.fillColor
        end
        if general.enableBossCastbar and not general.bossCastbarDetached then
            local width = general.bossCastbarMatchWidth == "unitframe" and first.width
                or Number(general.bossCastbarWidth, first.width)
            local cast = Add(scene, key .. "Cast", first.label, first.x + Number(general.bossCastbarOffsetX, 0),
                y + first.height + 3 - Number(general.bossCastbarOffsetY, 0), width, castHeight, "bar", general)
            cast.fillColor, cast.castOwner = color, first.config
        end
    end
end

local function PresetCastbars(scene, frames)
    local general = frames and frames.general
    if (scene.layout ~= "wayfarer" and scene.layout ~= "modernDark") or scene.keepFrames or not general then return end
    local color = ColorHex(Number(general.castbarInterruptibleR, .78),
        Number(general.castbarInterruptibleG, .53), Number(general.castbarInterruptibleB, .24))
    for _, unit in ipairs({ "player", "target" }) do
        local owner = scene[unit]
        local name = unit == "player" and "Player" or "Target"
        local prefix = "castbar" .. name
        if owner and general["enable" .. name .. "Castbar"] and not general[prefix .. "Detached"] then
            local height = Number(general[prefix .. "BarHeight"], 18)
            local width = general[prefix .. "MatchWidth"] == "unitframe" and owner.width
                or Number(general[prefix .. "BarWidth"], owner.width)
            local x = owner.x + (unit == "player" and (owner.width - width) / 2 or 0)
            local y = owner.y - Number(general[prefix .. "OffsetY"], 0) - height
            local rect = Add(scene, unit .. "Cast", owner.label, x + Number(general[prefix .. "OffsetX"], 0),
                y, width, height, "bar", general)
            rect.fillColor, rect.castOwner = color, owner.config
        end
    end
    PresetBossStack(scene, general, color)
end

local function ModernAuraRow(scene, unit, kind, rect, aura, shared)
    local count = Number(shared[kind == "buff" and "maxBuffs" or "maxDebuffs"], 0)
    if count < 1 then return end
    local columns = max(1, min(count, Number(shared[kind .. "PerRow"], count)))
    local rows = math.ceil(count / columns)
    local size, gap = Number(aura[kind .. "GroupIconSize"], 26), Number(aura[kind .. "Spacing"], 2)
    local iconHeight = math.floor(size * Number(aura[kind .. "IconHeightPercent"], 100) / 100 + .5)
    local width, height = columns * size + (columns - 1) * gap, rows * iconHeight + (rows - 1) * gap
    local anchor = POINTS[POINT_INDEX[aura[kind .. "Anchor"]] or 1]
    local item = Add(scene, unit .. kind, kind == "buff" and "Buffs" or "Debuffs",
        rect.x + anchor[1] * (rect.width - width) + Number(aura[kind .. "GroupOffsetX"], 0),
        rect.y + anchor[2] * (rect.height - height) - Number(aura[kind .. "GroupOffsetY"], 0),
        width, height, "icons", aura)
    item.columns, item.rows, item.count = columns, rows, count
    item.iconWidth, item.iconHeight, item.gap = size, iconHeight, gap
end

local MODERN_AURA_UNITS = { "player", "target", "boss", "boss2", "boss3", "boss4", "boss5" }
local function ModernAuraRows(scene, frames)
    if scene.layout ~= "modernDark" or scene.keepFrames or not frames or not frames.auras3 then return end
    local units = frames.auras3.perUnit
    if not units then return end
    for _, unit in ipairs(MODERN_AURA_UNITS) do
        local rect, owner = scene[unit], units[unit == "boss" and "boss1" or unit]
        if rect and owner and owner.layout and owner.layoutShared then
            ModernAuraRow(scene, unit, "buff", rect, owner.layout, owner.layoutShared)
            ModernAuraRow(scene, unit, "debuff", rect, owner.layout, owner.layoutShared)
        end
    end
end

local function WayfarerRaid(scene, frames)
    local raid = frames and frames.gf_raid
    if scene.layout ~= "wayfarer" or scene.keepFrames or not raid or raid.enabled ~= true then return end
    -- The preset uses one horizontal row per raid subgroup. Show the full
    -- footprint so it can be compared with the boss stack and the chat.
    local gap, groups = Number(raid.spacing, 3), Number(raid.maxColumns, 8)
    local columns = Number(raid.unitsPerColumn, 5)
    local cellWidth, cellHeight = Number(raid.width, 74), Number(raid.height, 30)
    local width, height = columns * (cellWidth + gap) - gap, groups * (cellHeight + gap) - gap
    local rect = Place(scene, "raid", "Raid", POINT_INDEX[raid.anchorPoint or raid.point],
        Number(raid.offsetX, 18), Number(raid.offsetY, -176), width, height, "grid", raid)
    rect.count, rect.columns, rect.gap = columns * groups, columns, gap
    rect.cellWidth, rect.cellHeight = cellWidth, cellHeight
    rect.fillColor = raid.gfBarMode == "dark" and ColorHex(Number(raid.gfDarkR, .18),
        Number(raid.gfDarkG, .145), Number(raid.gfDarkB, .105))
        or Suite.InstallerFrameColors.HealthFill(frames, "group", raid)
end

local function WayfarerShapes(scene, frames)
    local bars = frames and frames.bars
    if scene.layout ~= "wayfarer" or scene.keepFrames or not bars or bars.slantedBarsEnabled ~= true then return end
    for _, rect in ipairs(scene) do
        local config, cast = rect.castOwner or rect.config, rect.castOwner ~= nil
        local allowed = cast and bars.slantedCastbars or rect.kind == "grid" and bars.slantedGroupFrames
            or rect.kind == "bar" and not cast and bars.slantedUnitFrames
        if allowed and config and (cast or config.frameBarShape == "SLANTED") then
            local suffix = SLANT_SUFFIX[config.slantedBarDirection or bars.slantedBarDirection]
            if suffix then
                rect.barMask = SLANT_ROOT .. "mask" .. suffix .. ".png"
                rect.barEdge = SLANT_ROOT .. "edge" .. suffix .. ".png"
            end
        end
    end
end

local function DockBelow(scene, key, label, anchor, gap, width, height, kind, config)
    return Add(scene, key, label, anchor.x + anchor.width - width,
        anchor.y + anchor.height + gap, width, height, kind, config)
end

local function ChatTop(config)
    if config.tabPanel then
        return Number(config.tabHeight, 24) + Number(config.tabPanelGap, 0)
    end
    return config.hideTabArt and 0 or Number(config.padding, 0)
end

local function Panels(scene, modules)
    local tail
    local map, meter, texts, tracker = modules.minimap, modules.damageMeter, modules.dataTexts, modules.objectives
    local navigation = modules.navigationHUD
    if navigation and navigation.enabled == true and navigation.showCompass == true then
        local rect = Place(scene, "compass", "Compass", POINT_INDEX.TOP,
            Number(navigation.compassX, 0), Number(navigation.compassY, -62),
            Number(navigation.compassWidth, 280), 34, "bar", navigation)
        rect.fillColor = navigation.accentColor
    end
    local experience = modules.xpBar
    if experience and experience.enabled == true then
        local scale = Number(experience.scale, 100) / 100
        local rect = Place(scene, "experience", "Experience bar", experience.point,
            Number(experience.x, 0), Number(experience.y, 0), Number(experience.width, 400) * scale,
            Number(experience.height, 18) * scale, "bar", experience)
        if experience.look == 4 then rect.fillColor = experience.customFill end
    end
    local chat = modules.chat
    if chat and chat.enabled ~= false and chat.lockWindowPosition and chat.lockWindowSize then
        local padding = Number(chat.padding, 0)
        local top = ChatTop(chat)
        Place(scene, "chat", "Chat", 7, Number(chat.windowX, 12) - padding, Number(chat.windowY, 12) - padding,
            Number(chat.windowWidth, 420) + padding * 2, Number(chat.windowHeight, 180) + padding + top, "list", chat)
    end
    if map and map.enabled ~= false then
        tail = Place(scene, "minimap", "Minimap", map.point, Number(map.x, 0), Number(map.y, 0),
            Number(map.size, 198), Number(map.size, 198), "map", map)
        if scene.layout == "wayfarer" and map.styleTexture == Suite.MinimapStyleTexture.CUSTOM then
            tail.artwork = map.styleTexturePath
        end
    end
    if meter and meter.enabled ~= false then
        local limit = scene.layout == "preMidnight" and 3 or 2
        for index = 1, min(limit, Number(meter.windowCount, 2)) do
            local p = "w" .. index
            Place(scene, p, "Damage meters", 9, Number(meter[p .. "X"], 0), Number(meter[p .. "Y"], 0),
                Number(meter[p .. "Width"], 260), Number(meter[p .. "Height"], 170), "meter", meter)
        end
    end
    if texts and texts.enabled ~= false then
        for index = 1, 5 do
            local p = "bar" .. index
            if texts[p .. "Enabled"] == true then
                local width = Number(texts[p .. "Width"], 390)
                local height = Number(texts[p .. "Height"], 26)
                if tail and texts[p .. "MinimapDock"] then
                    tail = DockBelow(scene, "data" .. index, "Data texts", tail,
                        Number(texts[p .. "MinimapDockGap"], 0), width, height, "bar", texts)
                else
                    Place(scene, "data" .. index, "Data texts", texts[p .. "Point"],
                        Number(texts[p .. "X"], 0), Number(texts[p .. "Y"], 0), width, height, "bar", texts)
                end
            end
        end
    end
    if tracker and tracker.enabled ~= false then
        local width, height = Number(tracker.width, 310), Number(tracker.height, 559)
        if tail and tracker.dockBelowMinimap then
            DockBelow(scene, "quests", "Quest tracker", tail,
                Number(tracker.minimapDockGap, 13), width, height, "list", tracker)
        else
            Place(scene, "quests", "Quest tracker", 3, Number(tracker.x, 0), Number(tracker.y, -250),
                width, height, "list", tracker)
        end
    end
end

local function DefensiveRows(scene, frames, cooldowns)
    local player = scene.player
    if not player or scene.keepFrames then return end
    local auras = frames and frames.auras3
    local custom = auras and auras.customContainers
    local perUnit = custom and custom.perUnit
    local items = perUnit and perUnit.player and perUnit.player.items
    local defensive = items and items[4]
    local placed = defensive and defensive.placed
    if defensive and defensive.enabled and placed and not defensive.portraitIcon then
        local size, gap = Number(placed.size, 21), Number(placed.spacing, 1)
        local iconHeight = max(1, math.floor(size * Number(placed.iconHeightPercent, 100) / 100 + .5))
        local columns = max(1, min(Number(placed.perRow, 2), Number(placed.max, 2)))
        local hostWidth = columns * size + (columns - 1) * gap
        local anchor = POINTS[POINT_INDEX[placed.anchor] or 1]
        local count = min(2, columns)
        local width = count * size + (count - 1) * gap
        local x = player.x + anchor[1] * (player.width - hostWidth) + Number(placed.x, 0)
        if placed.growth == "LEFTDOWN" or placed.growth == "LEFTUP" then x = x + hostWidth - width end
        local y = player.y + anchor[2] * (player.height - iconHeight) - Number(placed.y, 0)
        local row = Add(scene, "playerDefensives", "Defensive Buffs", x, y, width, iconHeight, "icons", placed)
        row.count, row.columns, row.iconWidth, row.iconHeight, row.gap = count, count, size, iconHeight, gap
    end
    if cooldowns and cooldowns.enabled and cooldowns.def_on then
        local size, gap = Number(cooldowns.def_size, 24), Number(cooldowns.def_spacing, 1)
        local width = size * 3 + gap * 2
        local row = Add(scene, "defensiveCooldowns", "Defensives", player.x + player.width - width + Number(cooldowns.def_x, 0),
            player.y - size - Number(cooldowns.def_gap, 0) - Number(cooldowns.def_y, 0), width, size, "icons", cooldowns)
        row.count, row.columns, row.iconWidth, row.iconHeight, row.gap = 3, 3, size, size, gap
    end
    if cooldowns and cooldowns.enabled and cooldowns.ext_on then
        local size, gap = Number(cooldowns.ext_size, 25), Number(cooldowns.ext_spacing, 1)
        local height = math.floor(size * Number(cooldowns.ext_height, 100) / 100 + .5)
        local row = Add(scene, "externalCooldowns", "Potions and racials", player.x + Number(cooldowns.ext_x, 0),
            player.y + player.height + Number(cooldowns.ext_gap, 0) - Number(cooldowns.ext_y, 0),
            2 * size + gap, height, "icons", cooldowns)
        row.count, row.columns, row.iconWidth, row.iconHeight, row.gap = 2, 2, size, height, gap
    end
end

local function PreMidnightUtility(scene, frames, config)
    local essential = scene.cooldowns
    if not essential or not config.uti_on then return end
    local size, spacing = Number(config.uti_size, 28), Number(config.uti_spacing, 1)
    local count = max(1, min(Number(config.uti_perRow, 5), Number(config.uti_maxIcons, 5)))
    local width = count * size + (count - 1) * spacing
    local height = math.floor(size * Number(config.uti_height, 100) / 100 + .5)
    local x = essential.x + (essential.width - width) / 2 + Number(config.uti_x, 0)
    local y = essential.y + essential.height + Number(config.uti_gap, 1) - Number(config.uti_y, 0)
    local utility = Add(scene, "utilityCooldowns", "Utility cooldowns", x, y, width, height, "icons", config)
    utility.columns, utility.rows, utility.count = count, 1, count
    utility.iconWidth, utility.iconHeight, utility.gap = size, height, spacing

    local general = frames and frames.general
    if scene.keepFrames or not general or not general.enablePlayerCastbar or not general.castbarPlayerAnchorToUtility then return end
    local castWidth = general.castbarPlayerMatchWidth == "utility" and width or Number(general.castbarPlayerBarWidth, width)
    local cast = Add(scene, "playerCast", "Player", x + (width - castWidth) / 2 + Number(general.castbarPlayerOffsetX, 0),
        y + height - Number(general.castbarPlayerOffsetY, 0), castWidth, Number(general.castbarPlayerBarHeight, 18), "bar", general)
    cast.fillColor = ColorHex(Number(general.castbarInterruptibleR, .78),
        Number(general.castbarInterruptibleG, .53), Number(general.castbarInterruptibleB, .24))
end

local function PreMidnightExtras(scene, frames, modules)
    PreMidnightUtility(scene, frames, modules.cooldownManager)
    DefensiveRows(scene, frames, modules.cooldownManager)
    local party = frames and frames.gf_party
    if party and party.enabled ~= false and not scene.keepFrames then
        local anchor = party.anchorToFrame == "MSUF_player" and scene.player
        local x = party.offsetX + (anchor and anchor.x or 0)
        local y = (anchor and anchor.y or 0) - party.offsetY
        for index = 1, 4 do
            Add(scene, "party" .. index, "Party", x, y + (index - 1) * (party.height + party.spacing),
                party.width, party.height, "bar", party)
        end
    end
    local tracker = modules.actionTracker
    if tracker and tracker.enabled and tracker.displayPreset == 2 and tracker.growth == 3 then
        local size, count, gap = tracker.rowHeight, tracker.rows, tracker.rowGap
        local width = size * count + gap * (count - 1)
        local meter = tracker.anchorTarget == 2 and scene.w1
        local rect
        if meter then
            local header = meter.config.headerOutside and Number(meter.config.headerHeight, 15) or 0
            rect = Add(scene, "actions", "Action tracker", meter.x - 1, meter.y - header - size, width, size, "icons", tracker)
        else
            rect = Place(scene, "actions", "Action tracker", tracker.point, tracker.x, tracker.y, width, size, "icons", tracker)
        end
        rect.columns, rect.rows, rect.count = count, 1, count
        rect.iconWidth, rect.iconHeight, rect.gap = size - 2, size - 2, gap + 2
    end
    local chat, combatRes = scene.chat, modules.battleRes
    if combatRes and combatRes.enabled and not Suite.Client.isForever then
        if chat and combatRes.anchorTarget == 2 then
            local tabX = Number(chat.config.padding, 0) + Number(chat.config.tabX, 0)
            local tabY = chat.y - Number(chat.config.tabY, 0)
            Add(scene, "battleRes", "Battle resurrection", chat.x + tabX, tabY - 2 - combatRes.height,
                combatRes.width, combatRes.height, "bar", combatRes)
        else
            Place(scene, "battleRes", "Battle resurrection", combatRes.point, combatRes.x, combatRes.y,
                combatRes.width, combatRes.height, "bar", combatRes)
        end
    end
    local timer = frames and frames.gameplay
    if chat and timer and timer.enableCombatTimer and timer.combatTimerAnchor == "chat" then
        local padding = Number(chat.config.padding, 0)
        local top = ChatTop(chat.config)
        local height = Number(timer.combatFontSize, 11)
        local width = height * 4
        Add(scene, "combatTime", "Combat timer", chat.x + chat.width - padding - width + timer.combatOffsetX,
            chat.y + top - timer.combatOffsetY - height / 2, width, height, "bar", timer)
    end
    local panel = modules.groupRaidShortcuts
    if panel and panel.enabled and panel.showPanel then
        Place(scene, "raidControl", "Raid Control", panel.panelPoint or 2, panel.panelX, panel.panelY,
            106, 18, "bar", panel)
    end
end

-- Native cooldown layouts contain class/spec-dependent rows. The overview
-- deliberately uses sample icons, without loading or simulating the CDM.
local function Cooldowns(scene, modules)
    local config = modules.cooldownManager
    if not config or config.enabled == false then return end
    if config.ess_on == false then return end
    local size, gap = Number(config.ess_size, 40), Number(config.ess_spacing, 0)
    local compact = scene.layout == "modernDark" or scene.layout == "blizzard" or scene.layout == "darkRaid"
    local limit = scene.layout == "preMidnight" and 9 or compact and 8 or 6
    local count = min(limit, max(1, Number(config.ess_perRow, 6)))
    local width, height = count * size + (count - 1) * gap, size
    local x, y = scene.width / 2 - width / 2, scene.height / 2
    local attach = scene.bar3 and config.ess_anchor == Suite.CDM.OTHER_ANCHOR
        and config.ess_anchorFrame == "MSUFSuiteBar3" and config.ess_side == Suite.CDM.SIDE.ABOVE
    if attach then
        local row = scene.bar3
        x, y = row.x + (row.width - width) / 2, row.y - height - Number(config.ess_gap, 0)
    end
    -- Free Essential rows start at a TOP point relative to screen center.
    local item = Add(scene, "cooldowns", "Cooldowns", x + Number(config.ess_x, 0),
        y - Number(config.ess_y, -218), width, height, "icons", config)
    item.columns, item.rows, item.count = count, 1, count
    item.iconWidth, item.iconHeight, item.gap = size, size, gap
end

local function PreviewModules(profile, layout, overrides)
    local source = profile and profile.suite and profile.suite.modules
    if not source then return nil end
    local modules = {}
    for _, id in ipairs({ "minimap", "damageMeter", "dataTexts", "objectives", "actionbars", "cooldownManager",
        "chat", "xpBar", "navigationHUD", "actionTracker", "battleRes", "groupRaidShortcuts" }) do
        local config = source[id]
        if config then
            if id == "actionbars" or id == "dataTexts" or overrides and overrides[id] ~= nil then
                local view = {}
                for key, value in pairs(config) do view[key] = value end
                if overrides and overrides[id] ~= nil then view.enabled = overrides[id] == true end
                modules[id] = view
            else
                modules[id] = config
            end
        end
    end
    -- Reuse the installer's exact Modern edge anchoring, on private views of
    -- the two relevant modules; the cached factory always stays untouched.
    if layout == "classic" then Suite.InstallerLayout.Prepare(modules) end
    return modules
end

function Model.Build(profile, frames, layout, overrides, viewport)
    local scene = { width = viewport and viewport.width or WIDTH, height = viewport and viewport.height or HEIGHT, layout = layout,
        keepFrames = viewport and viewport.keepFrames }
    scene.frameSettingsAvailable = frames ~= nil and (frames.player ~= nil or frames.target ~= nil or frames.focus ~= nil)
    local modules = PreviewModules(profile, layout, overrides)
    if not modules then return scene end
    local cooldownFirst = layout == "modernDark" or layout == "blizzard" or layout == "darkRaid" or layout == "preMidnight"
    if cooldownFirst then Cooldowns(scene, modules) end
    Frames(scene, frames)
    PresetCastbars(scene, frames)
    ModernAuraRows(scene, frames)
    WayfarerRaid(scene, frames)
    WayfarerShapes(scene, frames)
    ActionBars(scene, modules.actionbars)
    Panels(scene, modules)
    if layout == "preMidnight" then PreMidnightExtras(scene, frames, modules) end
    if not cooldownFirst then Cooldowns(scene, modules) end
    local resource, cooldown = scene.resource, scene.cooldowns
    if resource and cooldown and layout == "blizzard" and not scene.keepFrames then
        local player = frames.player
        local powerHeight = Number(player.detachedPowerBarHeight, 6)
        resource.width = cooldown.width
        resource.x = cooldown.x + (cooldown.width - resource.width) / 2
        resource.y = cooldown.y - 4 - resource.height - Number(frames.bars.classPowerOffsetY, 0)
        -- The detached power bar follows the player, so classes without a
        -- class-resource container still keep their power below Essential.
        local rect = scene.player
        Add(scene, "playerPower", "Resources", rect.x + rect.width / 2
            + Number(player.detachedPowerBarOffsetX, 0) - cooldown.width / 2,
            rect.y + rect.height - Number(player.detachedPowerBarOffsetY, 0),
            cooldown.width, powerHeight, "resource", player)
    end
    local resourceLayout = layout == "modernDark" or layout == "darkRaid" or layout == "preMidnight"
        or layout == "forever" and not Suite.Client.isForever
    if resource and cooldown and resourceLayout then
        -- Profiles.EnsureRetailResourceStack(true) is the installer's final
        -- Retail step. CP_AboveCooldownGap reserves attached power + 4 and
        -- a four-unit gap above Essential. Resolve this on the sample only.
        local player = frames.player
        local powerHeight = Number(player.detachedPowerBarHeight, 6)
        resource.width = frames.bars.classPowerWidthMode == "custom" and layout ~= "forever"
            and Number(frames.bars.classPowerWidth, cooldown.width) or cooldown.width
        resource.x = cooldown.x + (cooldown.width - resource.width) / 2
        resource.y = cooldown.y - 8 - powerHeight - resource.height
        local powerGap = 4
        if layout == "preMidnight" then
            resource.y = resource.y - Number(frames.bars.classPowerOffsetY, 0)
            powerGap = -Number(player.detachedPowerBarOffsetY, -4)
        end
        Add(scene, "playerPower", "Resources", resource.x, resource.y + resource.height + powerGap,
            resource.width, powerHeight, "resource", player)
    end
    return scene
end
