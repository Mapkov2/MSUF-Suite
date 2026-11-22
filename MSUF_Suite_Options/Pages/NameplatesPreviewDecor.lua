local _, P = ...
local AURA_SAMPLE_IDS = { debuff = { 1714, 34914, 589 }, buff = { 21562, 139 } }
local Style = P.Suite.NameplateStyle
local Draw = Style.Decor
local Preview = {}
P.NameplatesPreviewDecor = Preview
local ID = "nameplates"
local CONFIG = setmetatable({}, { __index = function(_, key) return P.Get(ID, key) end })
local X = P.Suite.NameplateExtensions
local TEXT_SAMPLES = { [6] = "85%", [7] = "+1500", [8] = "70 / 100", [9] = "2400", [10] = "+1.25%" }

function Preview.ExtraTextSample(source)
    return TEXT_SAMPLES[source] or P.Tr(X.TextIndicators[source].label)
end

local function ExtraTextFrame(editor, sample, scope, item, key)
    local frame = CreateFrame(sample.static and "Frame" or "Button", nil, sample.cell)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints(frame)
    if not sample.static then
        editor:Bind(frame, scope .. "." .. item.element, P.Tr(item.label),
            key .. "X", key .. "Y", scope .. "Markers")
        frame._npSettingKey = key
    end
    return { frame = frame, label = label }
end

function Preview.ExtraText(editor, sample, metrics)
    local scope = editor.scope or sample.prefix
    if sample.extraTextScope ~= scope then
        for _, visual in pairs(sample.extraText or {}) do visual.frame:Hide() end
        sample.extraTextScope = scope
        sample.extraTextByScope = sample.extraTextByScope or {}
        sample.extraText = sample.extraTextByScope[scope]
    end
    local labels = sample.extraText
    local shown = sample.prefix == editor.sampleKind and not (metrics.skinDisabled or metrics.npcWorldName or metrics.nameOnlyScope)
        and P.Get(ID, "look") ~= 2 and P.Get(ID, sample.prefix) and editor:LayerOn("status")
    for source = X.FirstTextSource, X.LastTextSource do
        local item = X.TextIndicators[source]
        local key = X.TextKey(scope, source)
        local selected = editor.statusSample == item.element
        local visual = labels and labels[source]
        if shown and (selected or not editor.statusSample and P.Get(ID, key)) then
            if not visual then
                labels = labels or {}
                visual = ExtraTextFrame(editor, sample, scope, item, key)
                labels[source], sample.extraText, sample.extraTextByScope[scope] = visual, labels, labels
            end
            local frame, label = visual.frame, visual.label
            local anchor = X.TextPoints[P.Get(ID, key .. "Anchor")] or X.TextPoints[1]
            local owner = anchor[2] == "name" and sample.name or sample.bar
            frame:ClearAllPoints()
            frame:SetPoint(anchor[1], owner, anchor[3], anchor[4] + P.Get(ID, key .. "X"), anchor[5] + P.Get(ID, key .. "Y"))
            local size = P.Get(ID, key .. "Size")
            P.StylePreviewFont(label, P.Suite.GlobalFontPath(), size, "OUTLINE")
            label:SetTextColor(P.RGB(P.Get(ID, key .. "Color")))
            P.SetTranslatedText(label, Preview.ExtraTextSample(source))
            frame:SetSize(math.max(size, label:GetStringWidth() + 4), size + 4)
            local level = item.layer and sample.bar:GetParent():GetFrameLevel() + P.Get(ID, key .. "Layer")
            frame:SetFrameLevel(level or owner:GetFrameLevel() + 1)
            frame:Show()
        elseif visual then
            visual.frame:Hide()
        end
    end
end

local function Styled(prefix)
    return P.Get(ID, "look") ~= 2 and P.Get(ID, prefix)
end

function Preview.LevelMode(editor, prefix, classic, namesOnly)
    local forever = P.Suite.Client.isForever
    local badge = forever == true
    local otherPlayer = prefix == "enemy" and editor.enemyPlayer
        or prefix == "friendly" and editor.friendlyOutsider and not editor.friendlyElite
    if not forever and not classic and otherPlayer then
        local active = C_GameRules.IsGameRuleActive(Enum.GameRule.PlayerNameplateDifficultyIcon)
        badge = P.Suite.Public(active) and active == true
    end
    local enabled = P.Get(ID, prefix .. "LevelEnabled") or editor.statusOffsetSample == "Level"
    return Style.LevelMode(forever, classic, Styled(prefix), enabled,
        forever and P.Get(ID, "levelAppearance"), badge, namesOnly)
end

local function OutlineOff(s, m, bars)
    local nativeOverride = not m.skinDisabled and bars.look == 2 and bars.barsOverride
    return bars.hideHealthBarBorders or (Styled(s.prefix) or nativeOverride) and Style.OutlineOff(bars, s.prefix)
end

local function PaintSelection(s, m, texture, visible, badge)
    local mode = Styled(s.prefix) and P.Get(ID, "selectionBorder") or 1
    local target, focus = s.state.target, s.state.focus
    local off = OutlineOff(s, m, m.barSettings or CONFIG)
    texture:SetShown(visible and not s.customSelection and not off and mode ~= 3
        and (target or focus == true))
    if mode == 2 then
        texture:SetVertexColor(P.RGB(P.Get(ID, target and "selectionTargetColor" or "selectionFocusColor")))
    else
        local color
        if badge then
            color = NamePlateConstants[target and "TARGET_BORDER_COLOR" or "FOCUS_TARGET_BORDER_COLOR"]
        else
            color = target and NAMEPLATE_BORDER_TARGET_COLOR or NAMEPLATE_BORDER_FOCUS_TARGET_COLOR
        end
        if color then
            texture:SetVertexColor(color.r, color.g, color.b)
        else
            texture:SetVertexColor(1, 1, 1)
        end
    end
end

function Preview.ApplySampleOpacity(editor, s, m)
    local prefix, cell = s.prefix, s.cell
    local config, alpha = P.S.Config(ID), P.Get(ID, prefix) and 1 or 0.4
    local kind = editor.scope == "neutral" and "neutralNpc" or m.friendlyNPC and "friendlyNpc"
        or prefix == "enemy" and (editor.enemyPlayer and "enemyPlayer" or "enemyNpc") or "friendlyPlayer"
    local model = P.Suite.NameplateExtensions
    kind = model.ContextKind(config, kind)
    if not m.skinDisabled and model.ContextEnabled(config, kind) then
        alpha = alpha * (config[kind .. "Opacity"] or 100) / 100
    end
    local scope = editor.scope == "neutral" and "neutral" or m.friendlyNPC and "friendlyNpc" or prefix
    m.opacity = not m.skinDisabled and Styled(prefix) and model and model.ReadOpacity and model.ReadOpacity(config, scope) or nil
    if m.opacity and editor.opacitySample then alpha = alpha * m.opacity.ooc end
    cell:SetAlpha(alpha)
end

function Preview.PaintOpacity(editor, s, m)
    local fade = m.opacity
    if fade or s.opacityPainted then
        s.progress:SetAlpha(fade and fade.health or 1)
        if s.healthGradient then Style.Gradient.SetAlpha(s.healthGradient, fade and fade.health or 1) end
        s.back:SetAlpha(fade and fade.background or 1)
        s.healthText:SetAlpha(fade and fade.text or 1)
        local alpha = (s.castNameOpacity or 1) * (fade and fade.text or 1)
        if s.name:GetAlpha() ~= alpha then s.name:SetAlpha(alpha) end
    end
    s.opacityPainted = fade ~= nil
    if s.enemyPower and (fade or s.powerOpacityPainted) then
        s.enemyPower:GetStatusBarTexture():SetAlpha(fade and fade.power or 1)
        local gradient = s.enemyPower.powerGradient
        if gradient then Style.Gradient.SetAlpha(gradient, fade and fade.power or 1) end
        s.enemyPower.enemyPowerBackground:SetAlpha(fade and fade.powerBackground or 1)
        local trail = s.enemyPower.enemyPowerLoss
        if trail then trail.bar:SetAlpha(fade and fade.power or 1) end
        if s.enemyPower.enemyPowerText then s.enemyPower.enemyPowerText:SetAlpha(fade and fade.powerText or 1) end
        s.powerOpacityPainted = fade ~= nil
    end
    if editor.layerContext == "opacity" and not m.namesOnly and editor.sampleKind == s.prefix then
        if not s.absorbSample then
            s.absorbSample = s.bar:CreateTexture(nil, "OVERLAY")
            s.absorbSample:SetColorTexture(.5, .78, 1, .7)
        end
        local absorb = s.absorbSample
        absorb:ClearAllPoints()
        absorb:SetPoint("TOPLEFT", s.progress, "TOPRIGHT")
        absorb:SetPoint("BOTTOMLEFT", s.progress, "BOTTOMRIGHT")
        absorb:SetWidth(m.barWidth * .14)
        absorb:SetAlpha(fade and fade.prediction or 1)
        absorb:Show()
    elseif s.absorbSample then
        s.absorbSample:Hide()
    end
end

function Preview.PaintHealthGradient(s, m)
    local gradient = Style.Gradient
    if not gradient then return end
    local state = s.healthGradient
    local bars = m.barSettings or CONFIG
    local plan = not m.skinDisabled and not m.namesOnly and Styled(s.prefix)
        and gradient.Plan(bars, "health", state and state.plan) or nil
    s.healthGradient = gradient.Paint(s.bar, state, s.progress, plan)
end

function Preview.PaintHealthFill(sample, hex, key, tint)
    if sample.healthFillKey == key and sample.healthFillColor == hex then return end
    sample.healthFillKey, sample.healthFillColor = key, hex
    local texture = sample.progress
    local path = P.Suite.ResolveTexture(key)
    if path then
        texture:SetTexture(path)
        local r, g, b = P.RGB(hex)
        texture:SetVertexColor(r, g, b, 1)
    else
        tint(texture, hex)
    end
end

local function PaintHealthBackground(s, classic, background)
    if s.healthBackground == background and s.healthBackgroundClassic == classic then return end
    s.healthBackground, s.healthBackgroundClassic = background, classic
    local art = s.nativeBorder
    if background then
        art:SetTexture(background)
        art:ClearTextureSlice()
        art:SetTexCoord(0, 1, 0, 1)
        art:SetDrawLayer("BACKGROUND")
        art:SetVertexColor(.16, .16, .16, 1)
    elseif classic then
        art:SetTexture("Interface\\Tooltips\\Nameplate-Border")
        art:SetTexCoord(0, 1, 0.5, 1)
        art:SetDrawLayer("ARTWORK", 1)
        art:SetVertexColor(1, 1, 1, 1)
    else
        art:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
        art:SetDrawLayer("BACKGROUND", 0)
        art:SetTexCoord(0, 1, 0, 1)
        art:SetVertexColor(1, 1, 1, 1)
    end
    local fit = background and not classic
    if fit or s.healthBackgroundFitted then Style.FitModernHealthBackground(art, fit) end
    s.healthBackgroundFitted = fit
end

function Preview.PaintHealthChrome(editor, s, m, key)
    local art, bar = s.nativeBorder, s.bar
    if key == nil then key = P.Get(ID, "nativeHealthBackgroundTexture") end
    local bars = m.barSettings or CONFIG
    if not m.skinDisabled and Styled(s.prefix) and Style.UsesNativeOutline(bars, s.prefix) then key = "" end
    if s.healthBackgroundKey ~= key then
        s.healthBackgroundKey = key
        s.healthBackgroundPath = key and key ~= "" and P.Suite.ResolveTexture(key)
    end
    local background = s.healthBackgroundPath
    PaintHealthBackground(s, m.classic, background)
    art:ClearAllPoints()
    if m.classic then
        -- The Classic art is centered on the container, not stretched over the fill.
        art:SetSize(128 * m.horizontal, 16 * m.vertical)
        art:SetPoint("CENTER", bar, "CENTER", 8.625 * m.horizontal, -0.5 * m.vertical)
    else
        art:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 3)
        art:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 6, -6)
    end
    local show = editor:LayerOn("health") and not m.namesOnly
    local showNative = m.skinDisabled or not Styled(s.prefix) or not Style.HideNativeOutline(bars, s.prefix)
    local nativeVisible = showNative and not OutlineOff(s, m, bars)
    art:SetShown(show and (background or nativeVisible) and true or false)
    local selected = s.selectedBar
    selected:SetAtlas(m.forever and "UI-HUD-CoolDownManager-Selected-yellow" or "UI-HUD-Nameplates-Selected")
    selected:ClearAllPoints()
    selected:SetPoint("TOPLEFT", art, "TOPLEFT", m.forever and -3 or -1, m.forever and 2 or 1)
    selected:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", m.forever and 0 or -3, m.forever and 2 or 3)
    PaintSelection(s, m, selected, show and not m.classic)
end

local function SampleLevel(m, prefix)
    local read = m.forever and UnitEffectiveLevel or UnitLevel
    local value = read and read("player")
    if not P.Suite.Public(value) or type(value) ~= "number" or value < 1 then
        value = m.forever and 60 or 90
    end
    if prefix == "enemy" then
        if m.role == 4 then return "??" end
        if m.role == 9 then return math.max(1, value - 15) end
    end
    return value
end

function Preview.PaintLevel(editor, s, m, setup, place)
    local mode, prefix, level, label = m.levelMode, s.prefix, s.level, s.levelText
    local shown = mode ~= nil and editor:LayerOn("level")
    level._npLevelMode = mode
    level:SetShown(shown)
    if not shown then return end
    local badge, classic, number = mode == "badge", mode == "classic", mode == "number"
    local nativeHeight = (m.style == 0 or m.style == 2) and 23 or 16
    local custom = number and P.Get(ID, prefix .. "LevelSize") or 0
    local size = custom > 0 and custom or setup("levelFontHeight", 10 * m.vertical)
    local offset = Styled(prefix) and "Level"
    local anchor = number and offset and Style.Anchors[P.Get(ID, prefix .. "LevelAnchor")]
    if anchor then
        place(s, level, "CENTER", s.bar, anchor, 0, 0, offset)
    elseif badge and m.forever then
        place(s, level, "LEFT", s.bar, "RIGHT", 5, 0.5, offset)
    elseif classic then
        place(s, level, "CENTER", s.bar, "RIGHT", 10 * m.horizontal, 0, offset)
    else
        place(s, level, "RIGHT", s.bar, "LEFT", -4, 0, offset)
    end
    level:SetSize(badge and setup("playerLevelDiffWidth", (m.forever and 28 or 16) * m.classificationScale)
            or classic and setup("levelIconWidth", 15 * m.horizontal) or math.max(24, size * 2),
        badge and setup("playerLevelDiffHeight", nativeHeight * m.classificationScale)
            or classic and setup("levelIconHeight", 15 * m.vertical) or math.max(16, size))
    s.levelBack:SetShown(badge)
    if badge then s.levelBack:SetAtlas("ui-hud-nameplates-levelindicator") end
    PaintSelection(s, m, s.levelSelected, badge and m.forever, badge and m.forever)
    local sample = SampleLevel(m, prefix)
    local skull = not number and sample == "??"
    s.levelSkull:SetShown(skull)
    if skull then
        if m.forever then
            s.levelSkull:SetAtlas("ui-hud-nameplates-levelindicator-skull")
        else
            s.levelSkull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
        end
        local height = level:GetHeight()
        s.levelSkull:SetSize(height, height)
    end
    label:SetShown(not skull)
    label:SetText(sample)
    label:SetTextHeight(size)
    label:SetJustifyH(number and not anchor and "RIGHT" or "CENTER")
    local color = prefix == "enemy" and (not number or P.Get(ID, "enemyLevelColor"))
        and (m.role == 9 and TRIVIAL_DIFFICULTY_COLOR or FAIR_DIFFICULTY_COLOR)
    if color then
        label:SetTextColor(color.r, color.g, color.b)
    else
        label:SetTextColor(1, 1, 1)
    end
end

local RAID_POINTS = { [2] = { "RIGHT", "LEFT", -3, 0 }, [3] = { "LEFT", "RIGHT", 3, 0 },
    [4] = { "BOTTOM", "TOP", 0, 3 }, [5] = { "CENTER", "CENTER", 0, 0 } }
function Preview.PlaceRaid(s, m, styled, get, place)
    local prefix, raid = s.prefix, s.raid
    local choice = styled and get(ID, prefix .. "RaidRelativeAnchor")
    local anchor = RAID_POINTS[choice]
    if anchor then
        place(s, raid, anchor[1], choice == 5 and s.bar or s.name, anchor[2], anchor[3], anchor[4], "RaidIcon")
    elseif m.namesOnly then
        -- Runtime subtracts the name displacement from this native link.
        raid:ClearAllPoints()
        raid:SetPoint("BOTTOM", s.name, "TOP",
            get(ID, prefix .. "RaidIconOffsetX") - get(ID, prefix .. "NameOffsetX"),
            10 + get(ID, prefix .. "RaidIconOffsetY") - get(ID, prefix .. "NameOffsetY"))
    else place(s, raid, "RIGHT", s.bar, "LEFT", m.classic and -3.5 * m.horizontal or 0, 0, "RaidIcon") end
end

local function StatusSample(editor, s, item)
    s.statusSamples = s.statusSamples or {}
    local visual = s.statusSamples[item.key]
    if visual then return visual end
    local frame = CreateFrame(s.static and "Frame" or "Button", nil, s.cell)
    local content
    if item.sample then
        content = frame:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlateLevel")
        content:SetText(P.Tr(item.sample))
    else
        content = frame:CreateTexture(nil, "ARTWORK")
        if item.atlas then
            content:SetAtlas(item.atlas)
        else
            content:SetTexture(item.texture)
        end
    end
    content:SetAllPoints(frame)
    if not s.static then
        local key = s.prefix .. item.key
        editor:Bind(frame, s.prefix .. "." .. item.key, P.Tr(item.label),
            key .. "OffsetX", key .. "OffsetY", s.prefix .. "Markers")
    end
    visual = { frame = frame, content = content }
    s.statusSamples[item.key] = visual
    return visual
end

local function PaintIdentity(editor, s, player, get)
    local key = s.prefix .. "IdentityIcon"
    local mode = get(ID, key .. "s") or 1
    if (editor.statusSample and editor.statusSample ~= "identity") or not player then
        mode = 1
    end
    if mode == 1 and editor.statusOffsetSample == "identity" and player then mode = 4 end
    if mode == 1 and not s.identitySamples then return end
    if not s.identitySamples then
        s.identitySamples = { s.cell:CreateTexture(nil, "OVERLAY"), s.cell:CreateTexture(nil, "OVERLAY") }
        s.identitySamples[1]:SetAtlas("classicon-warrior")
        s.identitySamples[2]:SetAtlas(P.Suite.Client.isForever and "UI-HUD-UnitFrame-SmallCircle-Horde"
            or "UI-HUD-UnitFrame-Player-PVP-HordeIcon")
    end
    local size = get(ID, key .. "Size")
    local x, y = get(ID, key .. "X"), get(ID, key .. "Y")
    local class, faction = s.identitySamples[1], s.identitySamples[2]
    for i, icon in ipairs(s.identitySamples) do
        icon:ClearAllPoints()
        icon:SetPoint("RIGHT", s.name, "LEFT", x - (i == 2 and mode == 4 and size + 2 or 0), y)
        icon:SetSize(size, size)
    end
    class:SetShown(mode == 2 or mode == 4)
    faction:SetShown(mode == 3 or mode == 4)
    if mode ~= 1 and not s.identityHandle and not s.static then
        s.identityHandle = CreateFrame("Button", nil, s.cell)
        editor:Bind(s.identityHandle, s.prefix .. ".identity", P.Tr("Player identity icons"), key .. "X", key .. "Y",
            s.prefix .. "Markers")
    end
    local handle = s.identityHandle
    if not handle then return end
    handle:SetShown(mode ~= 1)
    if mode ~= 1 then
        handle:ClearAllPoints()
        handle:SetPoint("RIGHT", mode == 3 and faction or class, "RIGHT")
        handle:SetSize(mode == 4 and size * 2 + 2 or size, size)
    end
end

function Preview.PaintPattern(editor, s, m)
    local config, scopes = P.S.Config(ID), P.Suite.NameplateExtensions
    if not m.skinDisabled and not m.namesOnly and config.look ~= 2 and config[s.prefix]
        and editor:LayerOn("health") and editor:LayerOn("highlightBorders") then
        for _, signal in ipairs(Style.HighlightOrder(config.highlightPriority and config.highlightOrder or nil)) do
            local active = signal == "target" and s.state.target or signal == "focus" and s.state.focus
                or signal == "mouseover" and editor.highlightSample == "mouseover"
            if active and editor:LayerOn(signal .. "Border") then
                local kind = signal == "mouseover" and "hover" or signal
                for _, pattern in ipairs(scopes.Patterns) do
                    if pattern.kind == kind then
                        local key, alpha = scopes.PatternSettings(config, m.scope, pattern)
                        local texture = P.Suite.ResolveTexture(key)
                        if texture then
                            s.pattern:SetTexture(texture)
                            s.pattern:SetAlpha(alpha / 100)
                            s.pattern:Show()
                            return
                        end
                    end
                end
            end
        end
    end
    s.pattern:Hide()
end

function Preview.PaintStatus(editor, s, m, get)
    if m.skinDisabled or not editor:LayerOn("status") or s.prefix ~= editor.sampleKind or not Styled(s.prefix)
        or m.npcWorldName or m.nameOnlyScope then
        for _, visual in pairs(s.statusSamples or {}) do visual.frame:Hide() end
        for _, icon in ipairs(s.identitySamples or {}) do icon:Hide() end
        if s.identityHandle then s.identityHandle:Hide() end
        return
    end
    local player = s.prefix == "friendly" and not m.friendlyNPC or s.prefix == "enemy" and editor.enemyPlayer == true
    local forcePlayers = editor.allStatusSamples and editor.scope ~= "neutral" and editor.scope ~= "friendlyNpc"
    local playerScope = editor.scope ~= "neutral" and editor.scope ~= "friendlyNpc"
    PaintIdentity(editor, s, player or forcePlayers or playerScope and editor.statusSample == "identity", get)
    for _, item in ipairs(Style.Status) do
        local key = s.prefix .. item.key
        local available = Style.StatusSupported(item, s.prefix)
        local selected = editor.statusSample == item.key
        local visible = available and (not editor.statusSample or selected)
            and (get(ID, key) or editor.statusOffsetSample == item.key)
            and (not item.player or player or forcePlayers or playerScope and selected)
        if visible then
            local size = get(ID, key .. "Size")
            local visual = StatusSample(editor, s, item)
            local point = Style.StatusAnchor(get(ID, key .. "Anchor")) or "TOP"
            visual.frame:ClearAllPoints()
            visual.frame:SetPoint("CENTER", s.bar, point, get(ID, key .. "OffsetX"), get(ID, key .. "OffsetY"))
            visual.frame:SetFrameLevel(s.bar:GetFrameLevel() + get(ID, key .. "Layer"))
            local width = size
            if item.sample then
                visual.content:SetTextHeight(size)
                visual.content:SetTextColor(P.RGB(get(ID, key .. "Color")))
                width = math.max(size, visual.content:GetUnboundedStringWidth() + 4)
            end
            visual.frame:SetSize(width, size)
            visual.frame:Show()
        elseif s.statusSamples and s.statusSamples[item.key] then
            s.statusSamples[item.key].frame:Hide()
        end
    end
end

local function NativeScale()
    local value = C_CVar.GetCVar("nameplateSelectedScale")
    if not P.Suite.Public(value) then return 1 end
    return tonumber(value) or 1
end

-- The samples by their health bar: the editor's handle tip (NameplatesEditor.lua)
-- reports the mouse entering and leaving every handle.
local hovers = setmetatable({}, { __mode = "k" })

-- The mouseover highlight shows while the mouse is over the sample's health
-- bar, as over a live plate.
local function Hover(sample, on)
    local texture = sample.highlight
    if not (on and P.Get(ID, "mouseoverHighlight") and P.Get(ID, "look") ~= 2 and P.Get(ID, sample.prefix)) then
        if texture then texture:Hide() end
        return
    end
    if not texture then
        texture = Style.CreateHighlight(sample.bar)
        sample.highlight = texture
    end
    Style.PaintHighlight(texture, P.Get(ID, "mouseoverHighlightColor"))
    texture:Show()
end

local function FilterAuraRow(group, spells, excluded, reverse)
    if not excluded and not group.exclusions then return end
    group.exclusions = excluded
    local count, point = 0, reverse and "RIGHT" or "LEFT"
    for index, slot in ipairs(group.icons) do
        local show = not excluded or not excluded[spells[index]]
        slot.edge:SetShown(show)
        slot.icon:SetShown(show)
        if slot.stack then slot.stack:SetShown(show) end
        if show then
            slot.edge:ClearAllPoints()
            slot.edge:SetPoint(point, group, point, (reverse and -24 or 24) * count, 0)
            count = count + 1
        end
    end
    group:SetWidth(math.max(1, count * 24 - 2))
end

function Preview.FilterAuras(sample)
    local state = sample.auraPreviewState
    local excluded = state and state.exclusions
    FilterAuraRow(sample.auras, AURA_SAMPLE_IDS.debuff, excluded and excluded.debuff)
    FilterAuraRow(sample.buffs, AURA_SAMPLE_IDS.buff, excluded and excluded.buff, true)
end

function Preview.Build(_, sample)
    sample.decor = { parent = sample.cell, health = sample.bar, cast = sample.cast }
    hovers[sample.bar] = sample
end

function Preview.Hover(handle, on)
    local sample = hovers[handle]
    if sample then Hover(sample, on) end
end

local function HeaderPoint(region, ...)
    region:SetPoint(...)
end

local function PaintCastTextures(editor, sample, metrics, get, style)
    local fillKey = not metrics.skinDisabled and get(ID, "nativeCastFillTexture") or ""
    local backKey = not metrics.skinDisabled and get(ID, "nativeCastBackgroundTexture") or ""
    local locked = editor.uninterruptible
    local fill = P.Suite.ResolveTexture(fillKey) or style and style.fill
    local resetFill = not sample.castFillReady or sample.castFillPath ~= fill or sample.castLocked ~= locked
    if resetFill then
        sample.castFillReady = true
        sample.castFillPath, sample.castLocked = fill, locked
        local atlas = locked and "ui-castingbar-uninterruptable" or "ui-castingbar-filling-standard"
        sample.castProgress:SetStatusBarTexture(sample.castFillPath or atlas)
    end
    local r, g, b = 1, 1, 1
    if fill then
        local nr, ng, nb
        r, g, b, nr, ng, nb = Style.CastFillColors(get(ID, "nativeCastFillColor"), get(ID, "nativeCastLockedColor"))
        if locked then r, g, b = nr, ng, nb end
        if style and editor.interruptedSample and style.interruptR then r, g, b = style.interruptR, style.interruptG, style.interruptB end
    end
    if resetFill or sample.castR ~= r or sample.castG ~= g or sample.castB ~= b then
        sample.castR, sample.castG, sample.castB = r, g, b
        sample.castProgress:SetStatusBarColor(r, g, b, 1)
        sample.castProgress:GetStatusBarTexture():SetVertexColor(r, g, b, 1)
    end
    local dark = get(ID, "look") == 1 and backKey == "Solid"
    local back = P.Suite.ResolveTexture(backKey) or style and style.background
    local texture = sample.castBack
    local flat = not back and (style or metrics.classicCast) and true or false
    local resetBack = not sample.castBackReady or sample.castBackgroundPath ~= back
        or sample.castBackgroundFlat ~= flat
    if resetBack then
        sample.castBackReady = true
        sample.castBackgroundPath, sample.castBackgroundFlat = back, flat
        if back then
            texture:SetTexture(back)
            texture:ClearTextureSlice()
            texture:SetTexCoord(0, 1, 0, 1)
        elseif not flat then
            texture:SetAtlas("ui-castingbar-background")
        end
    end
    local br, bg, bb, ba = 1, 1, 1, 1
    if style then br, bg, bb, ba = style.backgroundR, style.backgroundG, style.backgroundB, style.backgroundA
    elseif back and not dark then br, bg, bb = .16, .16, .16
    elseif dark or metrics.classicCast then br, bg, bb, ba = 0, 0, 0, .5 end
    if resetBack or sample.castBackR ~= br or sample.castBackG ~= bg or sample.castBackB ~= bb or sample.castBackA ~= ba then
        sample.castBackR, sample.castBackG, sample.castBackB, sample.castBackA = br, bg, bb, ba
        if flat then
            texture:SetVertexColor(1, 1, 1, 1)
            texture:SetColorTexture(br, bg, bb, ba)
        else
            texture:SetVertexColor(br, bg, bb, ba)
        end
    end
end

local function PaintCastOutline(sample, style)
    local size = style and style.outlineSize or 0
    if size > 0 and not sample.castOutline then sample.castOutline = Style.CreateBorder(sample.castProgress) end
    local outline = sample.castOutline
    if outline then Style.PaintCastOutline(outline, sample.castProgress, size, style) end
end

function Preview.CastPresentation(editor, sample, metrics, get)
    local style = not metrics.skinDisabled and Style.SharedCastbar(get(ID, "look"))
    if sample.castBack then PaintCastTextures(editor, sample, metrics, get, style) end
    PaintCastOutline(sample, style)
    if sample.castProgress and sample.castProgress.SetReverseFill then
        local reverse = style and style.reverseFill == true or false
        if sample.castReverse ~= reverse then
            sample.castProgress:SetReverseFill(reverse)
            sample.castReverse = reverse
        end
    end
    local side = sample.prefix
    if sample.castText and style and style.textR and style.textG and style.textB
        and (get(ID, side .. "CastTextEnabled") ~= false or P.Suite.NameplateText.Shared(CONFIG)) then
        sample.castText:SetTextColor(style.textR, style.textG, style.textB, style.textA)
    end
    local enabled = not metrics.skinDisabled and get(ID, "look") ~= 2 and get(ID, side)
    sample.castBaseLevel = sample.castBaseLevel or sample.cast:GetFrameLevel()
    local level = sample.castBaseLevel
    if enabled and get(ID, side .. "CastForeground") then level = math.max(level, sample.cell:GetFrameLevel() + 10) end
    if level ~= sample.cast:GetFrameLevel() then sample.cast:SetFrameLevel(level) end
    local alpha, mode = 1, get(ID, side .. "NameDuringCast")
    if enabled and metrics.showCast and not editor.interruptedSample then
        if mode == 2 then alpha = (get(ID, side .. "NameCastAlpha") or 35) / 100 end
        if mode == 3 then alpha = 0 end
    end
    sample.castNameOpacity = alpha
    if not metrics.opacity and sample.name:GetAlpha() ~= alpha then sample.name:SetAlpha(alpha) end
end

function Preview.InterruptedCast(editor, sample, metrics, get)
    local enabled = not metrics.skinDisabled and editor.interruptedSample and metrics.showCast and get(ID, "look") ~= 2
        and get(ID, "interruptFeedbackEnabled")
    local preview = sample.interruptPreview
    if enabled and not preview then
        local frame = CreateFrame("Frame", nil, sample.cast)
        frame:SetAllPoints(sample.cast)
        frame:SetFrameLevel(sample.castProgress:GetFrameLevel() + 4)
        local fill = frame:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints(frame)
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", frame, "CENTER")
        preview = { frame = frame, fill = fill, text = text }
        sample.interruptPreview = preview
    end
    if not preview then return end
    preview.frame:SetShown(enabled == true)
    if enabled then
        preview.fill:SetColorTexture(P.RGB(get(ID, "interruptFeedbackColor")))
        if get(ID, "interruptFeedbackWho") then
            P.SetTranslatedText(preview.text, P.Tr("Interrupted by %s"):format(P.Suite.NameplateText.Sample("friendly")))
        else
            P.SetTranslatedText(preview.text, P.Tr("Interrupted"))
        end
    end
end

function Preview.CastIcon(sample, place, get)
    local prefix = sample.prefix
    local zoom, choice = 100, 1
    local styled = not sample.metrics.skinDisabled and get(ID, "look") ~= 2 and get(ID, prefix)
    if styled then
        zoom = get(ID, prefix .. "CastIconZoom") or 100
        choice = get(ID, prefix .. "CastIconRelativeAnchor") or 1
    end
    local inset = (1 - 100 / zoom) / 2
    if sample.castIconFill then sample.castIconFill:SetTexCoord(inset, 1 - inset, inset, 1 - inset) end
    local border = styled and get(ID, prefix .. "CastIconBorder")
    if border and not sample.castIconBorder then sample.castIconBorder = Style.CreateBorder(sample.castIcon) end
    if sample.castIconBorder then
        Style.PaintBorder(sample.castIconBorder, sample.castIcon, border and get(ID, prefix .. "CastIconBorderSize") or 0,
            get(ID, prefix .. "CastIconBorderColor"))
    end
    if choice > 1 then
        local right = choice == 3 or choice == 5
        place(sample, sample.castIcon, right and "LEFT" or "RIGHT", choice > 3 and sample.bar or sample.cast,
            right and "RIGHT" or "LEFT", right and 3 or -3, 0, "CastIcon")
    end
end

function Preview.CastTimeSize(sample, inherited)
    local key = sample.prefix .. "CastTimeSize"
    local size = not sample.metrics.skinDisabled and Styled(sample.prefix) and P.Get(ID, key) or 0
    if size == 0 then return inherited end
    local text = sample.castTimeText
    local font, _, flags = text:GetFont()
    text:SetFont(font, size, flags)
    return size
end

function Preview.PaintMirroredHeader(s, m, get, config)
    if m.centerName or m.skinDisabled or s.prefix ~= "enemy" or not Style.MirrorHeader(get(ID, "enemyMirrorHeader"),
        get(ID, "enemyTextMode"), m.nameAnchor, m.namesOnly) or get(ID, "look") == 2 then return end
    if P.Suite.NameplateText.NameAnchor(config, s.prefix) then return end
    s.healthText:SetWidth(math.max(1, s.value:GetStringWidth()))
    Style.PlaceMirroredHeader(s.name, s.healthText, s.bar, s.bar, m.nameSpacing,
        get(ID, "enemyNameOffsetX"), get(ID, "enemyNameOffsetY"),
        get(ID, "enemyHealthTextOffsetX"), get(ID, "enemyHealthTextOffsetY"),
        HeaderPoint)
    s.nameText:SetWidth(math.max(1, s.name:GetWidth()))
    s.nameText:SetJustifyH("RIGHT")
    s.value:SetJustifyH("LEFT")
end

local function PaintPowerText(editor, s, power, config)
    local painter = Style.EnemyPower
    local label = painter.PaintText(s.enemyPower, config, P.Suite.GlobalFontPath())
    local textHandle = s.enemyPowerTextHandle
    if label then
        local _, _, format = painter.TextValue(P.Get(ID, "enemyPowerTextMode"))
        label:SetFormattedText(format, power, 100)
        if not textHandle then
            textHandle = CreateFrame("Button", nil, s.enemyPowerHandle)
            s.enemyPowerTextHandle = textHandle
            editor:Bind(textHandle, "enemy.PowerText", "Power Text", "enemyPowerTextOffsetX", "enemyPowerTextOffsetY", "enemyPower")
        end
        textHandle:SetPoint("CENTER", label, "CENTER")
        textHandle:SetSize(math.max(22, label:GetStringWidth()), P.Get(ID, "enemyPowerTextSize") + 4)
    end
    if textHandle then textHandle:SetShown(label ~= nil) end
end

function Preview.Power(editor, s, m)
    if s.prefix ~= "enemy" then return end
    local handle, bar = s.enemyPowerHandle, s.enemyPower
    local config = m.barSettings or P.S.Config(ID)
    local edit = editor.textSample == "PowerText" or editor.layerContext == "power"
    if m.skinDisabled or editor.sampleKind ~= "enemy"
        or not (editor:LayerOn("enemyPower") and (edit or editor:LayerActive("enemyPower"))) then
        if handle then handle:Hide() end
        return
    end
    local painter = Style.EnemyPower
    if edit and config.look ~= 2 and (not config.enemyPowerEnabled or editor.textSample == "PowerText" and not config.enemyPowerTextVisible) then
        config = setmetatable({ enemyPowerEnabled = true, enemyPowerTextVisible = editor.textSample == "PowerText"
            or config.enemyPowerTextVisible }, { __index = config })
    end
    local plan = painter.Plan(config, bar and bar.enemyPowerPlan)
    if not plan.enabled then
        if handle then handle:Hide() end
        return
    end
    if not bar then
        handle = CreateFrame("Button", nil, s.cell)
        bar = painter.Create(handle)
        bar:SetAllPoints(handle)
        bar:SetMinMaxValues(0, 100)
        bar:Show()
        s.enemyPowerHandle, s.enemyPower = handle, bar
        s.enemyPowerBottom = CreateFrame("Frame", nil, s.cell)
        s.enemyPowerBottom:SetSize(1, 1)
        editor:Bind(handle, "enemy.Power", "Enemy power bar", "enemyPowerOffsetX", "enemyPowerOffsetY", "enemyPower")
    end
    -- Follow the native cast container even while its sample is hidden.
    local castContainerHeight = m.castHeight + (m.castInside and 0 or m.iconHeight)
    s.enemyPowerBottom:SetPoint("BOTTOM", s.cell, "CENTER", 0, -4 - m.nativeBarHeight / 2 - m.castSpacing - castContainerHeight)
    handle._npNativeWidth = m.barWidth
    handle:SetHeight(painter.Height(plan))
    painter.Place(handle, s.bar, s.enemyPowerBottom, plan)
    local _, token = painter.Resource(plan.source)
    local resourceColor = plan.byType and PowerBarColor[token or "MANA"]
    if resourceColor then painter.Paint(bar, plan, resourceColor.r, resourceColor.g, resourceColor.b)
    else painter.Paint(bar, plan) end
    local power = editor.enemyPlayer and 38 or 66
    painter.SetValue(bar, power, plan.interpolation)
    painter.PreviewLoss(bar, plan, power)
    PaintPowerText(editor, s, power, config)
    handle:Show()
end

local function PaintFocusHandle(editor, sample)
    if sample.static or sample.prefix ~= "enemy" then return end
    local marker = sample.decor.focusMarker
    local visible = marker and marker:IsShown()
    local handle = sample.focusHandle
    if visible and not handle then
        handle = CreateFrame("Button", nil, sample.cell)
        sample.focusHandle = handle
        editor:Bind(handle, "enemy.focusMarker", P.Tr("Focus diamond"), "enemyFocusMarkerX", "enemyFocusMarkerY", "enemyMarkers")
        handle:SetAllPoints(marker)
    end
    if handle then handle:SetShown(visible == true) end
end

function Preview.Paint(editor, s, m)
    Preview.PaintOpacity(editor, s, m)
    if editor.targetStateButton then
        editor.targetStateButton:SetAlpha(editor.targetSample ~= false and 1 or 0.5)
        editor.focusStateButton:SetAlpha(editor.focusSample and 1 or 0.5)
    end
    local p = Draw.Plan(m.barSettings or CONFIG, s.prefix)
    if not editor:LayerOn("outerFrame") then p.outer = false end
    if not editor:LayerOn("shadow") then p.shadow = false end
    if not editor:LayerOn("glow") then p.glow = 1 end
    if not editor:LayerOn("threshold") or editor.statusSample and editor.statusSample ~= "Threshold" then
        p.threshold = false
    end
    if editor.statusOffsetSample == "focusMarker" then p.focus = true end
    local focusSample = s.state.focus == true
    if not editor:LayerOn("focusMarker") or editor.statusSample and editor.statusSample ~= "focusMarker" then
        p.focus = false
    elseif editor.statusSample == "focusMarker" or editor.allStatusSamples then
        focusSample = true
    end
    local scale = s.state.target and Draw.TargetScale(CONFIG, NativeScale()) or 1
    s.cell:SetScale(scale)
    if m.skinDisabled or m.namesOnly or not editor:LayerOn("health") or P.Get(ID, "look") == 2 or not P.Get(ID, s.prefix) then
        Draw.Hide(s.decor)
        if s.focusHandle then s.focusHandle:Hide() end
        return
    end
    Draw.Paint(s.decor, p, s.state.target, focusSample, m.showCast)
    PaintFocusHandle(editor, s)
end
