local _, P = ...
local S = P.Suite
-- The painter of the minimal loot window, its loot feed and the options
-- preview: one row per entry with an icon, a name, a quality or quest line and
-- an amount, without a frame (the background layer is optional). Entries are
-- plain records the controller reads; a secret name or icon only reaches
-- SetText and SetTexture. Nothing here reads loot state or calls loot actions.
local View = {}
P.LootWindowView = View

local MAX_ROWS, GROW_UP = 16, 2
local FALLBACK_ICON = 134400
local QUEST_BANG = "Interface\\ContainerFrame\\UI-Icon-QuestBang"
local QUEST_COLOR = { 1, .82, 0 }
local LAYERS = { "icon", "name", "subtitle", "count" }
View.MaxRows, View.Layers = MAX_ROWS, LAYERS
-- Blizzard's localized quality names (GlobalStrings), as its loot rows use them.
local QUALITY_NAMES = {
    [0] = ITEM_QUALITY0_DESC, ITEM_QUALITY1_DESC, ITEM_QUALITY2_DESC, ITEM_QUALITY3_DESC,
    ITEM_QUALITY4_DESC, ITEM_QUALITY5_DESC, ITEM_QUALITY6_DESC, ITEM_QUALITY7_DESC,
}

function View.QualityName(quality)
    return S.Finite(quality) and QUALITY_NAMES[quality] or nil
end

local function QualityColor(entry)
    local color = S.Finite(entry.quality) and ITEM_QUALITY_COLORS[entry.quality]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

local function NewText(parent, justify)
    local region = S.CreateFontString(parent, nil, "OVERLAY")
    region:SetJustifyH(justify)
    region:SetWordWrap(false)
    return region
end

-- A row is a button only in the live window; feed and preview rows let every
-- click through.
local function NewRow(owner)
    local handlers = owner.handlers
    local row = S.CreateFrame(handlers and "Button" or "Frame", nil, owner.host)
    row.owner = owner
    row:EnableMouse(handlers ~= nil)
    if handlers then
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", handlers.click)
        row:SetScript("OnEnter", handlers.enter)
        row:SetScript("OnLeave", handlers.leave)
        row:SetScript("OnHide", handlers.leave)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", handlers.wheel)
        local highlight = S.CreateTexture(row, nil, "HIGHLIGHT")
        highlight:SetAllPoints(row)
        highlight:SetColorTexture(1, 1, 1, .08)
    end
    row.icon = S.CreateTexture(row, nil, "ARTWORK")
    row.icon:SetTexCoord(.08, .92, .08, .92)
    row.quest = S.CreateTexture(row, nil, "OVERLAY")
    row.quest:SetAllPoints(row.icon)
    row.quest:SetTexture(QUEST_BANG)
    row.edges = {}
    for index = 1, 4 do row.edges[index] = S.CreateTexture(row, nil, "OVERLAY") end
    row.name, row.subtitle, row.count = NewText(row, "LEFT"), NewText(row, "LEFT"), NewText(row, "RIGHT")
    row:Hide()
    return row
end

local function Row(owner, index)
    local row = owner.rows[index]
    if not row then
        row = NewRow(owner)
        owner.rows[index] = row
        owner.styled = nil
    end
    return row
end

function View.Create(owner)
    if owner.host then return end
    local host = S.CreateFrame("Frame", nil, owner.previewParent or UIParent)
    host:EnableMouse(false)
    if not owner.previewParent then
        host:SetFrameStrata("HIGH")
        host:SetClampedToScreen(true)
    end
    owner.host, owner.rows, owner.metrics = host, {}, {}
    owner.panel = S.CreateTexture(host, nil, "BACKGROUND")
    owner.panel:SetAllPoints(host)
    owner.more = NewText(host, "CENTER")
    if owner.previewParent then
        owner.bounds = {}
        for _, key in ipairs(LAYERS) do
            owner.bounds[key] = S.CreateFrame("Frame", nil, host)
            owner.bounds[key]:EnableMouse(false)
        end
    end
    host:Hide()
end

------------------------------------------------------------------ placement
-- Each element's place in a row; x/y are its offsets (the profile's, or a
-- drag in the preview). The name rises when the row has a second line.
local PLACE = {}
function PLACE.icon(owner, row, x, y)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", 4 + x, y)
end
function PLACE.name(owner, row, x, y)
    local metrics = owner.metrics
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", metrics.textLeft + x, (row.twoLines and metrics.nameUp or 0) + y)
end
function PLACE.subtitle(owner, row, x, y)
    local metrics = owner.metrics
    row.subtitle:ClearAllPoints()
    row.subtitle:SetPoint("LEFT", row, "LEFT", metrics.textLeft + x, metrics.subtitleDown + y)
end
function PLACE.count(_, row, x, y)
    row.count:ClearAllPoints()
    row.count:SetPoint("RIGHT", row, "RIGHT", x - 6, y)
end

local function Offsets(config, key)
    return config[key .. "X"] or 0, config[key .. "Y"] or 0
end

-- The feed grows by its own setting, the window by the window's.
local function GrowsUp(owner)
    local config = owner.config
    return (owner.feed and config.feedGrowth or config.growth) == GROW_UP
end

-- The editor's outline of a layer covers that element in every shown row.
local function PlaceBounds(owner)
    local bounds, shown = owner.bounds, owner.shownCount or 0
    if not bounds then return end
    local up = GrowsUp(owner)
    local top, bottom = owner.rows[up and shown or 1], owner.rows[up and 1 or shown]
    for _, key in ipairs(LAYERS) do
        local frame, visible = bounds[key], shown > 0 and owner.config[key .. "Shown"] ~= false
        if visible then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", top[key], "TOPLEFT", -2, 2)
            frame:SetPoint("BOTTOMRIGHT", bottom[key], "BOTTOMRIGHT", 2, -2)
        end
        frame:SetShown(visible)
    end
end

-- A drag in the preview: one element moves in every row until the editor
-- writes the offsets and the next paint places everything from the profile.
function View.PlaceLayer(owner, key, x, y)
    local place = PLACE[key]
    if not place then return end
    for index = 1, owner.shownCount or 0 do place(owner, owner.rows[index], x, y) end
    PlaceBounds(owner)
end

------------------------------------------------------------------ layout
local function Measure(owner)
    local config, metrics = owner.config, owner.metrics
    local iconShown = config.iconShown ~= false
    metrics.height = math.max(config.rowHeight, iconShown and config.iconSize + 2 or 0)
    metrics.textLeft = iconShown and config.iconSize + 12 or 6
    metrics.nameUp = math.floor(config.subtitleSize / 2 + 1)
    metrics.subtitleDown = -math.floor(config.nameSize / 2 + 1)
    metrics.textWidth = math.max(20, config.width - metrics.textLeft - 8)
end

local function Style(owner)
    local config = owner.config
    local palette = S.QoLStyle(config)
    local font = S.ResolveFont(config.font) or S.GlobalFontPath()
    local text, muted = { S.RGB(palette.text) }, { S.RGB(palette.muted) }
    owner.textColor, owner.mutedColor = text, muted
    local red, green, blue = S.RGB(palette.background)
    owner.panel:SetColorTexture(red, green, blue, (config.backgroundOpacity or 0) / 100)
    for _, row in ipairs(owner.rows) do
        S.QoLStyleText(row.name, config, font, config.nameSize)
        S.QoLStyleText(row.subtitle, config, font, config.subtitleSize)
        S.QoLStyleText(row.count, config, font, config.countSize)
        row.icon:SetSize(config.iconSize, config.iconSize)
        row.subtitle:SetWidth(owner.metrics.textWidth)
    end
    S.QoLStyleText(owner.more, config, font, config.subtitleSize)
    owner.more:SetTextColor(muted[1], muted[2], muted[3])
    owner.styled = true
end

-- A settings change: sizes, fonts and colors, then a full repaint.
function View.Layout(owner)
    View.Create(owner)
    Measure(owner)
    owner.styled = nil
    View.Paint(owner)
end

------------------------------------------------------------------ paint
local function PaintIcon(owner, row, entry, red, green, blue)
    local config = owner.config
    local shown = config.iconShown ~= false
    row.icon:SetTexture(entry.icon)
    if entry.locked then
        row.icon:SetVertexColor(.9, .1, .1)
    else
        row.icon:SetVertexColor(1, 1, 1)
    end
    row.icon:SetShown(shown)
    row.quest:SetShown(shown and entry.questBang == true)
    local border = shown and config.iconBorder ~= false and S.Finite(entry.quality)
    S.PlaceEdges(row.edges, row.icon, border and 1 or 0, red, green, blue, 1)
end

local function PaintText(owner, row, entry, red, green, blue)
    local config, text, muted = owner.config, owner.textColor, owner.mutedColor
    row.name:SetText(entry.name)
    if config.nameQuality ~= false and S.Finite(entry.quality) then
        row.name:SetTextColor(red, green, blue)
    else
        row.name:SetTextColor(text[1], text[2], text[3])
    end
    local subtitle = config.subtitleShown ~= false and entry.subtitle or ""
    row.twoLines = subtitle ~= ""
    row.subtitle:SetText(subtitle)
    local color = entry.quest and QUEST_COLOR or muted
    row.subtitle:SetTextColor(color[1], color[2], color[3])
    row.count:SetText(entry.amount or "")
    row.count:SetTextColor(text[1], text[2], text[3])
    row.name:SetShown(config.nameShown ~= false)
    row.subtitle:SetShown(row.twoLines)
    row.count:SetShown(config.countShown ~= false)
    local room = config.countShown ~= false and (row.count:GetStringWidth() or 0) + 8 or 0
    row.name:SetWidth(math.max(20, owner.metrics.textWidth - room))
end

local function PaintRow(owner, row, entry)
    row.entry = entry
    local red, green, blue = QualityColor(entry)
    PaintIcon(owner, row, entry, red, green, blue)
    PaintText(owner, row, entry, red, green, blue)
    for _, key in ipairs(LAYERS) do PLACE[key](owner, row, Offsets(owner.config, key)) end
    row:Show()
end

local function PlaceRows(owner, shown)
    local config, height = owner.config, owner.metrics.height
    local up, gap = GrowsUp(owner), config.rowGap
    for index = 1, shown do
        local row = owner.rows[index]
        local offset = (index - 1) * (height + gap)
        row:ClearAllPoints()
        if up then
            row:SetPoint("BOTTOMLEFT", owner.host, "BOTTOMLEFT", 0, offset)
        else
            row:SetPoint("TOPLEFT", owner.host, "TOPLEFT", 0, -offset)
        end
        row:SetSize(config.width, height)
    end
    owner.more:ClearAllPoints()
    owner.more:SetPoint(up and "TOP" or "BOTTOM", owner.host, up and "TOP" or "BOTTOM", 0, up and -1 or 1)
end

local function SizeHost(owner, shown, hidden)
    local config, metrics = owner.config, owner.metrics
    local height = shown * metrics.height + math.max(0, shown - 1) * config.rowGap
    if hidden > 0 then height = height + config.subtitleSize + 6 end
    height = math.max(1, height)
    owner.host:SetSize(config.width, height)
    local viewport = owner.previewViewport
    if viewport then
        owner.host:SetScale(math.min(viewport.scale, viewport.width / config.width, viewport.height / height))
    end
end

local function SetWindowInput(owner, enabled)
    owner.inputSuspended = not enabled
    owner.host:EnableMouseWheel(enabled)
    for _, row in ipairs(owner.rows) do
        row:EnableMouse(enabled)
        row:EnableMouseWheel(enabled)
        if not enabled then owner.handlers.leave(row) end
    end
end

-- One native animation per live surface, allocated on the first transition.
-- Reverse an in-progress fade at its current opacity.
local function Fade(owner, target, seconds)
    if not owner.fade then
        owner.fade = owner.host:CreateAnimationGroup()
        owner.alpha = owner.fade:CreateAnimation("Alpha")
        owner.fade:SetScript("OnFinished", function()
            if owner.fadingOut then
                owner.fadingOut = nil
                owner.host:Hide()
            end
        end)
    end
    local fade, alpha = owner.fade, owner.alpha
    local from = 1 - target
    if fade:IsPlaying() then
        from = owner.fadeFrom + (owner.fadeTo - owner.fadeFrom) * alpha:GetProgress()
        fade:Stop()
    end
    owner.fadeFrom, owner.fadeTo = from, target
    alpha:SetFromAlpha(from)
    alpha:SetToAlpha(target)
    alpha:SetDuration(seconds)
    fade:Play()
end

function View.Hide(owner, seconds)
    if not owner.host then return end
    if seconds and seconds > 0 then
        if owner.fadingOut or not owner.host:IsShown() then return end
        owner.fadingOut = true
        if owner.handlers then SetWindowInput(owner, false) end
        Fade(owner, 0, seconds)
    else
        if owner.fade and owner.fade:IsPlaying() then owner.fade:Stop() end
        owner.fadingOut = nil
        owner.host:Hide()
    end
end

-- The rows of owner.entries from owner.first; a limit (maxRows, or feedRows
-- for the feed) keeps the rest a scroll away, counted at the list's end.
function View.Paint(owner, fadeIn)
    local config, entries = owner.config, owner.entries or {}
    local limit = math.min(owner.feed and config.feedRows or config.maxRows, MAX_ROWS)
    local shown = math.min(#entries, limit)
    if not owner.metrics.height then Measure(owner) end
    owner.first = math.max(0, math.min(owner.first or 0, #entries - shown))
    for index = 1, shown do Row(owner, index) end
    if not owner.styled then Style(owner) end
    PlaceRows(owner, shown)
    for index = 1, shown do PaintRow(owner, owner.rows[index], entries[owner.first + index]) end
    for index = shown + 1, #owner.rows do
        owner.rows[index].entry = nil
        owner.rows[index]:Hide()
    end
    local hidden = #entries - shown
    owner.more:SetText(hidden > 0 and ("+%d"):format(hidden) or "")
    owner.more:SetShown(hidden > 0)
    owner.panel:SetShown(shown > 0 and config.backgroundShown == true)
    owner.shownCount = shown
    SizeHost(owner, shown, hidden)
    PlaceBounds(owner)
    if shown == 0 then
        View.Hide(owner)
    else
        local appearing = owner.fadingOut or not owner.host:IsShown()
        owner.fadingOut = nil
        if owner.inputSuspended then SetWindowInput(owner, true) end
        owner.host:Show()
        if appearing then
            if fadeIn and fadeIn > 0 then Fade(owner, 1, fadeIn)
            elseif owner.fade and owner.fade:IsPlaying() then owner.fade:Stop() end
        end
    end
    return shown
end

-- The mouse wheel over the live window shows further slots.
function View.Scroll(owner, delta)
    if not S.Finite(delta) then return end
    owner.first = (owner.first or 0) - delta
    View.Paint(owner)
end

------------------------------------------------------------------ samples
-- Preview and Edit Mode rows, in Blizzard's own words for quality, quests
-- and money.
function View.Samples()
    return {
        { name = S.Text("Example quest item"), icon = "Interface\\Icons\\INV_Misc_Fish_09", quality = 1,
            subtitle = ITEM_BIND_QUEST, quest = true, questBang = true },
        { name = S.Text("Example equipment"), icon = "Interface\\Icons\\INV_Sword_04", quality = 3,
            subtitle = QUALITY_NAMES[3] },
        { name = S.Text("Example cloth"), icon = "Interface\\Icons\\INV_Fabric_Linen_01", quality = 1,
            subtitle = QUALITY_NAMES[1], amount = "5" },
        { name = MONEY, icon = "Interface\\Icons\\INV_Misc_Coin_02", amount = C_CurrencyInfo.GetCoinTextureString(12361) },
    }
end

View.FallbackIcon = FALLBACK_ICON
