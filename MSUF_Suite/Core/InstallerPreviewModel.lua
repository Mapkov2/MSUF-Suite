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
        or key == "cooldowns" and "cooldownManager" or key == "minimap" and "minimap" or "frames"
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
    local playerRect
    for _, entry in ipairs(FRAMES) do
        local config = frames[entry[1]]
        if config and config.enabled ~= false and ScreenAnchor(config, frames.general) then
            local reference = Number(config.screenPositionHeight, 0)
            local factor = config.screenPositionMode == "relativeHeight" and not config.anchorToUnitframe
                and reference >= 400 and reference <= 10000 and scene.height >= 400 and scene.height <= 10000
                and math.abs(scene.height - reference) > .01 and scene.height / reference or 1
            local width, height = Number(config.width or config.frameWidth, 275), Number(config.height or config.frameHeight, 40)
            local point, relative = POINT_INDEX[config.point] or 5, POINT_INDEX[config.relativePoint or config.point] or 5
            local anchor, origin = POINTS[point], POINTS[relative]
            local rect = Add(scene, entry[1], entry[2], origin[1] * scene.width - anchor[1] * width
                + Number(config.offsetX or config.x, 0) * factor,
                origin[2] * scene.height - anchor[2] * height - Number(config.offsetY or config.y, 0) * factor,
                width, height, "bar", config)
            if entry[1] == "player" then playerRect = rect end
        elseif config and config.enabled ~= false then
            scene.externalFrames = true
        end
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

local function ActionBars(scene, config)
    if not config or config.enabled == false then return end
    for _, index in ipairs({ 1, 2, 3, 5 }) do
        local prefix = "bar" .. index
        if config[prefix .. "Visibility"] ~= Suite.ActionBarEnum.VISIBILITY.NEVER then
            local count = max(1, Number(config[prefix .. "Buttons"], 12))
            local columns, rows = Suite.ActionBarGrid(count, Number(config[prefix .. "Rows"], 1),
                config[prefix .. "Vertical"])
            local size, gap = Number(config[prefix .. "Size"], 40), Number(config[prefix .. "Spacing"], 2)
            local width, height = columns * size + (columns - 1) * gap, rows * size + (rows - 1) * gap
            local item = Place(scene, prefix, "Action bars", config[prefix .. "Point"] or 8,
                Number(config[prefix .. "X"], 0), Number(config[prefix .. "Y"], 0), width, height, "icons", config)
            item.columns, item.rows, item.count = columns, rows, count
        end
    end
end

local function Panels(scene, modules)
    local map, meter, texts, tracker = modules.minimap, modules.damageMeter, modules.dataTexts, modules.objectives
    if map and map.enabled ~= false then
        Place(scene, "minimap", "Minimap", map.point, Number(map.x, 0), Number(map.y, 0),
            Number(map.size, 198), Number(map.size, 198), "map", map)
    end
    if meter and meter.enabled ~= false then
        for index = 1, min(2, Number(meter.windowCount, 2)) do
            local p = "w" .. index
            Place(scene, p, "Damage meters", 9, Number(meter[p .. "X"], 0), Number(meter[p .. "Y"], 0),
                Number(meter[p .. "Width"], 260), Number(meter[p .. "Height"], 170), "meter", meter)
        end
    end
    if texts and texts.enabled ~= false then
        for index = 1, 5 do
            local p = "bar" .. index
            if texts[p .. "Enabled"] == true then
                Place(scene, "data" .. index, "Data texts", texts[p .. "Point"],
                    Number(texts[p .. "X"], 0), Number(texts[p .. "Y"], 0),
                    Number(texts[p .. "Width"], 390), Number(texts[p .. "Height"], 26), "bar", texts)
            end
        end
    end
    if tracker and tracker.enabled ~= false then
        Place(scene, "quests", "Quest tracker", 3, Number(tracker.x, 0), Number(tracker.y, -250),
            Number(tracker.width, 310), Number(tracker.height, 559), "list", tracker)
    end
end

-- Native cooldown layouts contain class/spec-dependent rows. The overview
-- deliberately uses sample icons, without loading or simulating the CDM.
local function Cooldowns(scene, modules)
    local config = modules.cooldownManager
    if not config or config.enabled == false then return end
    if config.ess_on == false then return end
    local size, gap = Number(config.ess_size, 40), Number(config.ess_spacing, 0)
    local count = min(6, max(1, Number(config.ess_perRow, 6)))
    local width, height = count * size + (count - 1) * gap, size
    -- The supplied Essential rows grow down from a TOP point on screen
    -- CENTER (CDM Grid.Point/Layout). Icon count stays an explicit sample.
    local item = Add(scene, "cooldowns", "Cooldowns", scene.width / 2 + Number(config.ess_x, 0) - width / 2,
        scene.height / 2 - Number(config.ess_y, -218), width, height, "icons", config)
    item.columns, item.rows, item.count = count, 1, count
end

local function PreviewModules(profile, layout, overrides)
    local source = profile and profile.suite and profile.suite.modules
    if not source then return nil end
    local modules = {}
    for _, id in ipairs({ "minimap", "damageMeter", "dataTexts", "objectives", "actionbars", "cooldownManager" }) do
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
    local scene = { width = viewport and viewport.width or WIDTH, height = viewport and viewport.height or HEIGHT,
        keepFrames = viewport and viewport.keepFrames }
    scene.frameSettingsAvailable = frames ~= nil and (frames.player ~= nil or frames.target ~= nil or frames.focus ~= nil)
    local modules = PreviewModules(profile, layout, overrides)
    if not modules then return scene end
    Frames(scene, frames)
    ActionBars(scene, modules.actionbars)
    Panels(scene, modules)
    Cooldowns(scene, modules)
    local resource, cooldown = scene.resource, scene.cooldowns
    if resource and cooldown and layout == "forever" and not Suite.Client.isForever then
        -- Profiles.EnsureRetailResourceStack(true) is the installer's final
        -- Retail step. CP_AboveCooldownGap reserves attached power + 4 and
        -- a four-unit gap above Essential. Resolve this on the sample only.
        local player = frames.player
        local powerHeight = Number(player.detachedPowerBarHeight, 6)
        resource.width = cooldown.width
        resource.x = cooldown.x
        resource.y = cooldown.y - 8 - powerHeight - resource.height
        Add(scene, "playerPower", "Resources", resource.x, resource.y + resource.height + 4,
            resource.width, powerHeight, "resource", player)
    end
    return scene
end
