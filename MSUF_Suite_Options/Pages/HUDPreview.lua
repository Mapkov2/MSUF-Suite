local _, P = ...
local Suite, S, M, Tr, HM = P.Suite, P.S, P.M, P.Tr, P.HM
local Art = Suite.AnnouncementArt
local Preview = {}
P.HUDPreview = Preview
local modes = { objectives = "quests", runSummary = "raid", announcements = "zone", afkScreen = "character" }
-- What a click on the banner sample selects: section names a settings
-- accordion of the HUD workspace (HUDWorkspace.lua).
local ARTWORK = { label = "Banner artwork", section = "artwork" }
local FRAME = { label = "Banner frame", section = "bannerFrame" }
local FRAME_EDGE, MIN_PICKER_WIDTH = 10, 120
-- Above the canvas, the banner's targets layer as the banner draws its parts:
-- text over artwork over frame.
local LEVEL = { frame = 2, artwork = 3, text = 4 }
local SyncBanner

function Preview.Stop(ui)
    if ui.dismissTimer then
        ui.dismissTimer:Cancel()
        ui.dismissTimer = nil
    end
    if ui.animation then
        ui.animation:Stop()
        ui.leave:Stop()
    end
    ui.playing, ui.finished = false, false
    ui.canvas:SetAlpha(1)
end

local function Animation(ui)
    local group = ui.canvas:CreateAnimationGroup()
    group:SetToFinalAlpha(true)
    local enter = group:CreateAnimation("Alpha")
    enter:SetOrder(1)
    enter:SetFromAlpha(0)
    enter:SetToAlpha(1)
    enter:SetDuration(.22)
    group:SetScript("OnFinished", function()
        -- Commit the visible hold after the native fade, instead of relying
        -- on its transient alpha until the independent display clock expires.
        if ui.playing and ui.dismissTimer then ui.canvas:SetAlpha(1) end
    end)
    local leave = ui.canvas:CreateAnimationGroup()
    leave:SetToFinalAlpha(true)
    local fadeOut = leave:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(.36)
    leave:SetScript("OnFinished", function()
        ui.playing, ui.finished = false, true
        ui.canvas:SetAlpha(0)
    end)
    ui.animation, ui.leave = group, leave
end

function Preview.Play(ui)
    if ui.id ~= "announcements" or not ui.host:IsVisible() then return end
    Preview.Stop(ui)
    if not ui.animation then Animation(ui) end
    local duration = S.Config("announcements").duration
    ui.lastDuration, ui.playing = duration, true
    ui.animation:Play()
    -- Match the actual banner: fade-in and the display clock start together;
    -- only the one-shot deadline starts the independent fade-out group.
    local timer
    timer = C_Timer.NewTimer(duration, function()
        if ui.dismissTimer ~= timer then return end
        ui.dismissTimer = nil
        if ui.playing and ui.id == "announcements" and ui.host:IsVisible() then ui.leave:Play() end
    end)
    ui.dismissTimer = timer
end

-- The already loaded public palette while the Suite skin is on, without
-- acquiring a runtime skin client or loading/enabling a feature just to
-- display its example.
function Preview.Skin()
    local provider = _G.MapkoSkin
    if not Suite.Skin.enabled or type(provider) ~= "table" or type(provider.GetAPI) ~= "function" then return nil end
    return provider.GetAPI(2, 0)
end

function Preview.Color(c, key, fallback, token)
    if c.colorStyle == 2 then return P.RGB(c[key]) end
    local api = token and Preview.Skin()
    if api then return api:GetColor(token) end
    return unpack(fallback)
end

-- role: the text style role of the screen's own text (Suite.HUDTextArgs), for
-- headline text that takes a stronger shadow.
function Preview.Label(ui, text, x, y, width, size, color, role)
    ui.used = ui.used + 1
    local label = ui.labels[ui.used]
    if not label then
        label = ui.canvas:CreateFontString(nil, "OVERLAY")
        ui.labels[ui.used] = label
    end
    P.StylePreviewFont(label, Suite.ResolveFont(ui.config.font), size, Suite.HUDTextArgs(ui.config, role))
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(text)
    label:SetTextColor(unpack(color))
    label:Show()
    return label
end

function Preview.Fill(ui, x, y, width, height, color, alpha)
    ui.fillsUsed = ui.fillsUsed + 1
    local fill = ui.fills[ui.fillsUsed]
    if not fill then
        fill = ui.canvas:CreateTexture(nil, "BACKGROUND")
        ui.fills[ui.fillsUsed] = fill
    end
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", x, y)
    fill:SetSize(width, height)
    fill:SetDrawLayer("BACKGROUND", 0)
    fill:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    fill:Show()
    return fill
end

local function Paint(ui)
    if not ui.id or not ui.host:IsVisible() then return end
    ui.config, ui.used, ui.fillsUsed = S.Config(ui.id), 0, 0
    if ui.afk then ui.afk.host:Hide() end
    local art = ui.bannerArt
    local previousArt = art and art.revision
    local previousOpacity = art and art.backgroundOpacity
    local width, height = Preview.Render[ui.id](ui, modes[ui.id])
    if ui.id == "announcements" then
        -- An artwork or frame edit after playback brings back the sample.
        art = ui.bannerArt
        if previousArt ~= art.revision or previousOpacity ~= art.backgroundOpacity then Preview.Stop(ui) end
    elseif art then
        Art.Clear(art)
    end
    for i = ui.used + 1, #ui.labels do ui.labels[i]:Hide() end
    for i = ui.fillsUsed + 1, #ui.fills do ui.fills[i]:Hide() end
    ui.canvas:SetSize(width, height)
    ui.canvas:SetScale(math.min((ui.config.scale or 100) / 100, ui.width / width, 182 / height))
    if not ui.playing then ui.canvas:SetAlpha(ui.finished and 0 or 1) end
    if ui.id == "announcements" then
        local duration = ui.config.duration
        if ui.lastDuration and ui.lastDuration ~= duration then Preview.Play(ui) end
        ui.lastDuration = duration
    end
    SyncBanner(ui)
end

local function Focus(ui, target)
    local workspace = ui.ctx._msufSuiteHUDWorkspace
    local group = workspace.groups[ui.id]
    local body = target and target.section and group[target.section] or group.artwork or group.appearance or group.body
    if P.W.FocusCollapsibleSection then P.W.FocusCollapsibleSection(body, { flash = true }) end
end

-- Outlines the banner part that is selected (every part of the artwork) or
-- hovered. The banner opens with nothing marked, exactly as the screen
-- shows it; a click marks what it selected.
local function MarkBanner(ui, hovered)
    local selected = ui.marked and ui.target or nil
    for _, region in ipairs(ui.marks) do
        local target = region.target
        P.PreviewInteraction.Outline(region, region:IsShown() and (target == selected or target == hovered), 1)
    end
end

-- The banner opens on its artwork; the other HUDs open as a whole. The
-- banner marks its own parts, so the bar only names the selection there.
local function SelectTarget(ui, target, marked)
    local banner = ui.id == "announcements"
    target = target or (banner and ARTWORK or { label = P.catalog[ui.id].title })
    ui.target, ui.marked = target, banner and marked == true
    P.PreviewInteraction.Select(ui.selection, ui.canvas, target.label, function() Focus(ui, target) end,
        banner and 0 or nil)
    if banner then MarkBanner(ui) end
end

local function Select(ui, id)
    local same = ui.id == id
    if not same then Preview.Stop(ui) end
    local wasAdditional = ui.additional == true
    ui.id, ui.additional = id, id == nil
    local announcements = id == "announcements"
    for _, target in ipairs(ui.bannerTargets) do target:SetShown(announcements) end
    if not id then
        ui.host:Hide()
        ui.selection:Hide()
        ui.playButton:Hide()
        P.W.SetControlShown(ui.artPicker, false)
        if ui.framePicker then P.W.SetControlShown(ui.framePicker, false) end
        for _, picker in pairs(ui.pickers) do P.W.SetControlShown(picker, false) end
        return
    end
    if wasAdditional then
        ui.host:Show()
        ui.selection:Show()
    end
    SelectTarget(ui, same and ui.target or nil, same and ui.marked)
    ui.playButton:SetShown(announcements)
    P.W.SetControlShown(ui.artPicker, announcements)
    if ui.framePicker then P.W.SetControlShown(ui.framePicker, announcements) end
    for key, picker in pairs(ui.pickers) do P.W.SetControlShown(picker, key == id) end
    -- Only the AFK example reads character events, and only while visible.
    ui.host:UnregisterAllEvents()
    if id == "afkScreen" and ui.host:IsVisible() then
        for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "UNIT_MODEL_CHANGED", "ZONE_CHANGED_NEW_AREA" }) do
            ui.host:RegisterEvent(event)
        end
    end
    Paint(ui)
end

------------------------------------------------------------------ banner editor
-- The banner sample's parts are handles of the preview kit. Headline and
-- subtitle move by drag or arrow keys and save their offsets; the artwork's
-- parts and the frame's edges select (the frame also while it is off). The
-- empty canvas selects the artwork as well.
local function Part(ui, region, target, level)
    HM.SkipHistoryCheckpoint(region)
    HM.AllowCombatClick(region)
    region:SetFrameLevel(ui.canvas:GetFrameLevel() + level)
    region.target = target
    region:Hide()
    return region
end

-- Shown and hidden with the banner's HUD tab.
local function Target(ui, region, target, level)
    ui.bannerTargets[#ui.bannerTargets + 1] = Part(ui, region, target, level)
    return region
end

-- Rounded and clamped to the settings' ranges, in one undo step.
local function WriteOffset(key, x, y)
    local keys, rules = Art.OFFSET_KEYS[key], P.catalog.announcements.rules
    local xRule, yRule = rules[keys[1]], rules[keys[2]]
    return P.SetMany("announcements", {
        [keys[1]] = math.max(xRule.min, math.min(xRule.max, math.floor(x + .5))),
        [keys[2]] = math.max(yRule.min, math.min(yRule.max, math.floor(y + .5))),
    }) ~= false
end

-- Sized to the drawn text (SyncBanner): the rest of its row belongs to the
-- artwork and frame below it.
local function TextHandle(ui, key, label)
    local art, region = ui.bannerArt, CreateFrame("Button", nil, ui.canvas)
    region:SetPoint("CENTER", art[key], "CENTER")
    Target(ui, region, { label = label, section = "appearance" }, LEVEL.text)
    ui.texts[key], ui.marks[#ui.marks + 1] = region, region
    local function Read() return Art.TextOffset(S.Config("announcements"), key) end
    ui.handles:Add(key, region, Read, function(x, y) return WriteOffset(key, x, y) end, {
        scale = function() return ui.canvas:GetEffectiveScale() end,
        -- The dragged row is drawn where it goes; the repaint after the
        -- write (or a cancel) places it from the settings again.
        follow = function(_, dx, dy)
            local x, y = Read()
            art.placed = nil
            Art.PlaceText(art, key, x + dx, y + dy)
        end,
    })
end

local function FrameHandles(ui)
    local panel, edge, half = Art.PANEL, FRAME_EDGE, FRAME_EDGE / 2
    local x, y, width, height = panel.x, panel.y, panel.width, panel.height
    -- The frame's mark: the panel the frame draws, whatever its shape.
    local outline = CreateFrame("Frame", nil, ui.canvas)
    outline:SetPoint("TOPLEFT", x, y)
    outline:SetSize(width, height)
    Target(ui, outline, FRAME, LEVEL.frame)
    ui.frameOutline, ui.marks[#ui.marks + 1] = outline, outline
    for index, rect in ipairs({ { x - half, y + half, width + edge, edge }, { x - half, y - height + half, width + edge, edge },
        { x - half, y + half, edge, height + edge }, { x + width - half, y + half, edge, height + edge } }) do
        local region = CreateFrame("Button", nil, ui.canvas)
        region:SetPoint("TOPLEFT", rect[1], rect[2])
        region:SetSize(rect[3], rect[4])
        ui.handles:Add("frame" .. index, Target(ui, region, FRAME, LEVEL.frame))
    end
end

-- One target per drawn part of the artwork, a little larger than the part so
-- a thin line can be hit. The parts are made on the first paint of a style.
local function ArtworkHandle(ui, accent, index)
    local region = CreateFrame("Button", nil, ui.canvas)
    region:SetPoint("TOPLEFT", accent, "TOPLEFT", -4, 4)
    region:SetPoint("BOTTOMRIGHT", accent, "BOTTOMRIGHT", 4, -4)
    Part(ui, region, ARTWORK, LEVEL.artwork)
    ui.artwork[index], ui.marks[#ui.marks + 1] = region, region
    ui.handles:Add("artwork" .. index, region)
    return region
end

-- After each paint: the text targets fit the drawn text, the artwork targets
-- follow the parts the style shows, and the marks follow both.
SyncBanner = function(ui)
    local art, banner = ui.bannerArt, ui.id == "announcements"
    for key, region in pairs(ui.texts) do
        local text = art[key]
        region:SetSize(math.max(24, text:GetStringWidth() + 12), math.max(12, text:GetStringHeight() + 6))
    end
    for index, accent in ipairs(art.accents) do
        local region = ui.artwork[index] or ArtworkHandle(ui, accent, index)
        region:SetShown(banner and accent:IsShown())
    end
    if banner then MarkBanner(ui) end
end

local function BannerEditor(ui)
    ui.bannerArt, ui.bannerTargets, ui.texts, ui.artwork, ui.marks = Art.Create(ui.canvas), {}, {}, {}, {}
    ui.handles = P.PreviewInteraction.Handles(ui.kit, {
        owner = ui.host, threshold = 2,
        tip = function(region, entering) MarkBanner(ui, entering and region.target or nil) end,
        select = function(region) if region then SelectTarget(ui, region.target, true) end end,
        click = function(region, _, moved) if not moved then Focus(ui, region.target) end end,
        drag = function(region, phase) if phase == "done" then Focus(ui, region.target) end end,
        escape = function() ui.handles:Release() end,
    })
    TextHandle(ui, "title", "Headline")
    TextHandle(ui, "subtitle", "Subtitle")
    FrameHandles(ui)
end

-- Preview shortcuts for the banner's two decorations: None turns one off,
-- a style turns it on. They write the same settings as the accordions.
local function DecorationPicker(ui, parent, x, width, spec)
    local id = "announcements"
    local row = P.RuleRow("suite_hud", id, P.catalog[id].rules[spec.key], nil, spec.section)
    local values = { { value = 0, text = Tr("None") } }
    for _, choice in ipairs(row.values) do values[#values + 1] = choice end
    local function Get() return P.Get(id, spec.switch) and row.get() or 0 end
    local function Set(value)
        if value == 0 then
            P.Set(id, spec.switch, false)
        elseif P.Get(id, spec.switch) then
            row.set(value)
        else
            P.SetMany(id, { [spec.key] = value, [spec.switch] = true })
        end
    end
    local picker = M.BindDropdownAt(ui.ctx, parent, row.label, x, -42, values, width, Get, Set,
        P.Meta("suite_hud", id, spec.view, "ephemeral"))
    P.W.SetControlShown(picker, false)
    return picker
end

-- The banner's pickers share the row left of Play preview. Where three do
-- not fit, the frame shape stays in its accordion.
local function Pickers(ui, parent)
    local third = math.floor((ui.width - 186) / 3)
    local withFrame = third >= MIN_PICKER_WIDTH
    local announcementWidth = withFrame and math.min(240, third) or math.min(300, math.floor((ui.width - 174) / 2))
    for id, choices in pairs(Preview.Choices) do
        local feature, values = id, {}
        for _, choice in ipairs(choices) do
            values[#values + 1] = { value = choice[1], text = Tr(choice[2]) }
        end
        local width = id == "announcements" and announcementWidth or math.min(300, ui.width)
        local picker = M.BindDropdownAt(ui.ctx, parent, "Preview", 16, -42, values, width,
            function() return modes[feature] end, function(value)
                modes[feature] = value
                Preview.Stop(ui)
                Paint(ui)
            end, P.Meta("suite_hud", feature, "view.preview", "ephemeral"))
        ui.pickers[id] = picker
    end
    ui.artPicker = DecorationPicker(ui, parent, 28 + announcementWidth, announcementWidth,
        { key = "artStyle", switch = "showBoxArt", section = "suite_hud_announcements_artwork", view = "view.artwork" })
    if not withFrame then return end
    ui.framePicker = DecorationPicker(ui, parent, 40 + 2 * announcementWidth, announcementWidth,
        { key = "frameStyle", switch = "showFrame", section = "suite_hud_announcements_frame", view = "view.frame" })
end

function Preview.Build(ctx, parent, width)
    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", 16, -99)
    host:SetSize(width, 186)
    host:SetClipsChildren(true)
    local canvas = CreateFrame("Button", nil, host)
    canvas:SetPoint("CENTER")
    HM.SkipHistoryCheckpoint(canvas)
    HM.AllowCombatClick(canvas)
    local ui = { ctx = ctx, host = host, canvas = canvas, width = width, labels = {}, fills = {}, pickers = {} }
    canvas:SetScript("OnClick", function()
        if not ui.id then return end
        -- The empty canvas selects the artwork: drop a text selection and
        -- its arrow keys.
        ui.handles:Select(nil)
        SelectTarget(ui, nil, true)
        Focus(ui, ui.target)
    end)
    ui.Select, ui.Paint = Select, Paint
    -- The kit host opens with the preview; the AFK events repaint once a frame.
    ui.kit = Suite.PreviewKit.NewHost(nil, { frame = host, paint = function() Paint(ui) end,
        activate = function() if ui.id then Select(ui, ui.id) end end,
        deactivate = function()
            host:UnregisterAllEvents()
            ui.handles:Release()
            Preview.Stop(ui)
        end })
    BannerEditor(ui)
    Pickers(ui, parent)
    ui.playButton = P.T.Button(parent, "Play preview", 146, 26)
    ui.playButton:SetPoint("TOPLEFT", width - 130, -66)
    HM.SkipHistoryCheckpoint(ui.playButton)
    HM.AllowCombatClick(ui.playButton)
    ui.playButton:SetScript("OnClick", function() Preview.Play(ui) end)
    ui.selection = P.PreviewInteraction.Bar(ctx, parent, width, "Sample preview. Changes update here even when the feature is off.")
    ui.selection:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -291)
    local height = 326
    HM.SetFixedPreviewHeight(parent, height)
    parent:SetHeight(height)
    host:SetScript("OnShow", function() ui.kit:Activate() end)
    host:SetScript("OnHide", function() ui.kit:Deactivate() end)
    host:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_MODEL_CHANGED" and (Suite.IsSecret(unit) or unit ~= "player") then return end
        ui.kit:Request("event")
    end)
    if host:IsVisible() then ui.kit:Activate() end
    M.TrackRefresh(ctx, function() Paint(ui) end)
    return ui
end
