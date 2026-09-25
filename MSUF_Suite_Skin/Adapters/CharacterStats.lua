local _, NS = ...

-- Native player stats: wow-ui-source upstream/live 8ea15b61e45c0ed4eba01439c90757f86eb78d34,
-- CharacterFrame.xml, PaperDollFrame.lua, PlayerScript/CurveUtilDocumentation.lua.
-- Curve identity/units checked against SimulationCraft midnight sc_enums.hpp and
-- player_t::apply_combat_rating_dr. No copied implementation or fixed rating tables.
local Stats = { views = setmetatable({}, { __mode = "k" }) }
NS.CharacterStats = Stats

local Public = NS.Safety.Public

local RATING_CURVE = 21024
local MAX_STAT_ROWS = 64
local categories = { "ItemLevelCategory", "AttributesCategory", "EnhancementsCategory" }
local fontFields = { "Label", "Value" }
local hosts = setmetatable({}, { __mode = "k" })
local firstDRPoint

local definitions = {
    { label = "STAT_CRITICAL_STRIKE", rating = "CR_CRIT_MELEE" },
    { label = "STAT_HASTE", rating = "CR_HASTE_MELEE" },
    { label = "STAT_MASTERY", rating = "CR_MASTERY" },
    { label = "STAT_VERSATILITY", rating = "CR_VERSATILITY_DAMAGE_DONE" },
}

function Stats.IsHost(frame)
    return hosts[frame] == true
end

local function Accessible(value)
    if Public(value) then return value end
    return nil
end

-- Calls a Blizzard getter with valid arguments; secret results become nil.
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local a, b, c, d = fn(...)
    return Accessible(a), Accessible(b), Accessible(c), Accessible(d)
end

local function Number(value)
    return type(value) == "number" and value == value and value >= 0 and value < 1e9 and value or nil
end

local function Config()
    return NS.DB.characterStats
end

local function Modern()
    return not NS.CharacterDetails or NS.CharacterDetails.IsModern()
end

local function Enabled(v)
    if NS.Client and not NS.Client.modernEquipment then return false end
    return v.active and NS.DB.enabled and NS.DB.skins.blizzardWindows ~= false
        and NS.GenericWindows.IsCategoryEnabled("character") and Config().enabled and Modern()
end

local function Visible(frame)
    return Read(frame and frame.IsVisible, frame) == true
end

function Stats.StylesRows(pane)
    return pane and Config().enabled and Modern() and pane.ItemLevelCategory
        and pane.ItemLevelCategory.Title and Visible(pane)
end

local function FontPath()
    return Read(GameFontNormal and GameFontNormal.GetFont, GameFontNormal)
        or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- Diminishing returns ---------------------------------------------------------------------

-- Reuse one result per rating. DR describes the marginal return of the NEXT
-- rating point, not a blanket penalty on all existing rating or the total stat.
-- The first reduced segment is discovered from the native curve once rather
-- than assuming a threshold or rating conversion for every client version.
local function FirstDRPoint(curve)
    if firstDRPoint then return firstDRPoint end
    local high = 200
    local value = Number(Read(curve, RATING_CURVE, high))
    if not value or high - value < .001 then return nil end
    local low = 0
    for _ = 1, 18 do
        local middle = (low + high) / 2
        value = Number(Read(curve, RATING_CURVE, middle))
        if not value then return nil end
        if middle - value > .00001 then high = middle else low = middle end
    end
    firstDRPoint = low
    return firstDRPoint
end

function Stats.ReadRating(index, result)
    result.rating, result.bonus, result.penalty, result.loss = nil, nil, nil, nil
    result.inDR, result.lostRating = nil, nil
    if NS.IsCombatLocked() or not index then return result end
    local rating = Number(Read(GetCombatRating, index))
    local bonus = Number(Read(GetCombatRatingBonus, index))
    result.rating, result.bonus = rating, bonus
    if not rating or not bonus or Read(PlayerIsTimerunning) == true then return result end
    local perPoint = Number(Read(GetCombatRatingBonusForCombatRatingValue, index, 1))
    local curve = C_CurveUtil and C_CurveUtil.EvaluateGameCurve
    if not perPoint or perPoint <= 0 or type(curve) ~= "function" then return result end
    local baseline = Number(Read(curve, RATING_CURVE, 1))
    if not baseline or math.abs(baseline - 1) > .001 then return result end
    local raw = rating * perPoint
    local effective = Number(Read(curve, RATING_CURVE, raw))
    local nextPoint = Number(Read(curve, RATING_CURVE, raw + perPoint))
    -- Fail closed on unavailable curves, different units, unusual scaling or
    -- stale client contracts. Mastery stays in rating-derived mastery POINTS.
    if not effective or not nextPoint or effective > raw + .001
        or math.abs(effective - bonus) > math.max(.02, bonus * .002)
        or nextPoint < effective or nextPoint - effective > perPoint * 1.002 then
        return result
    end
    result.penalty = math.max(0, math.min(100, 100 * (1 - (nextPoint - effective) / perPoint)))
    if result.penalty < .05 then result.penalty = 0 end
    result.loss = raw > 0 and math.max(0, 100 * (raw - effective) / raw) or 0
    result.lostRating = math.max(0, (raw - effective) / perPoint)
    if result.penalty == 0 then
        result.inDR = 0
    else
        local onset = FirstDRPoint(curve)
        if onset then result.inDR = math.max(0, rating - onset / perPoint) end
    end
    return result
end

function Stats.DRBadge(result)
    if not result or result.penalty == nil then return NS.L.STATS_DR_UNKNOWN_BADGE end
    if result.inDR and result.inDR >= .5 then
        if result.inDR >= 1000 then
            return string.format(NS.L.STATS_DR_BADGE_AMOUNT_K, result.penalty, result.inDR / 1000)
        end
        return string.format(NS.L.STATS_DR_BADGE_AMOUNT, result.penalty, result.inDR)
    end
    return string.format(NS.L.STATS_DR_BADGE, result.penalty)
end

-- Native font snapshots -----------------------------------------------------------------

local function CaptureFont(font)
    if not font or not NS.Safety.CanDecorate(font, true) then return nil end
    local path, size, flags = Read(font.GetFont, font)
    if type(path) ~= "string" or not Number(size) then return nil end
    local points = {}
    for index = 1, math.min(Number(Read(font.GetNumPoints, font)) or 0, 4) do
        points[index] = { font:GetPoint(index) }
    end
    local r, g, b, a = Read(font.GetTextColor, font)
    return {
        font = font,
        path = path,
        size = size,
        flags = flags or "",
        points = points,
        object = Read(font.GetFontObject, font),
        justify = Read(font.GetJustifyH, font),
        color = r and { r, g, b, a } or nil,
    }
end

local function RestorePoints(saved)
    if not saved or #saved.points == 0 then return end
    saved.font:ClearAllPoints()
    for _, point in ipairs(saved.points) do saved.font:SetPoint(unpack(point)) end
end

local function Font(v, font, size, token)
    if not font then return end
    local saved = v.fonts[font]
    if not saved then
        saved = CaptureFont(font)
        v.fonts[font] = saved
    end
    if not saved then return end
    size = math.max(saved.size, size)
    if saved.appliedPath ~= v.path or saved.appliedSize ~= size then
        font:SetFont(v.path, size, saved.flags)
        saved.appliedPath, saved.appliedSize = v.path, size
    end
    if token and saved.color then
        saved.tinted = true
        local r, g, b, a = NS.Theme.GetColor(token)
        if saved.r ~= r or saved.g ~= g or saved.b ~= b or saved.a ~= a then
            font:SetTextColor(r, g, b, a)
            saved.r, saved.g, saved.b, saved.a = r, g, b, a
        end
    end
    return saved
end

local function Height(v, frame, height)
    if not v.heights[frame] then v.heights[frame] = { original = frame:GetHeight() } end
    if frame:GetHeight() ~= height then frame:SetHeight(height) end
    v.heights[frame].applied = height
end

local function Token(result)
    if not result.penalty then return "muted" end
    return result.penalty >= 20 and "danger" or result.penalty > 0 and "warning" or "muted"
end

local function Paint(v)
    v.path = FontPath()
    local wide = NS.GearAnnotations.IsWide()
    for _, field in ipairs(categories) do
        local category = v.pane[field]
        if category then Font(v, category.Title, wide and 12 or 11, "title") end
    end
    if v.pane.ItemLevelFrame then Font(v, v.pane.ItemLevelFrame.Value, wide and 28 or 20) end
    for _, record in pairs(v.rows) do
        Font(v, record.frame.Label, wide and 12 or 11, "muted")
        Font(v, record.frame.Value, record.definition and (wide and 18 or 16) or (wide and 13 or 12))
        if record.fontPath ~= v.path then
            record.meta:SetFont(v.path, 10, "")
            record.dr:SetFont(v.path, 9, "")
            record.fontPath = v.path
        end
        local token = record.result and Config().diminishingReturns and Token(record.result)
            or "muted"
        record.meta:SetTextColor(NS.Theme.GetColor("muted"))
        record.dr:SetTextColor(NS.Theme.GetColor(token))
        record.accent:SetColorTexture(NS.Theme.GetColor(token))
    end
    if v.helpPath ~= v.path then
        v.helpText:SetFont(v.path, 9, "")
        v.helpPath = v.path
    end
    v.helpText:SetTextColor(NS.Theme.GetColor("muted"))
end

-- DR help tooltip and view ----------------------------------------------------------------

local function Help(v)
    if not GameTooltip then return end
    GameTooltip:SetOwner(v.help, "ANCHOR_RIGHT")
    GameTooltip:SetText(NS.L.STATS_DR_TITLE)
    GameTooltip:AddLine(NS.L.STATS_DR_EXPLAIN, .75, .8, .85, true)
    for index, definition in ipairs(definitions) do
        local result = v.results[index]
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(_G[definition.label] or definition.label, 1, 1, 1)
        if result and result.rating then
            GameTooltip:AddLine(string.format(NS.L.STATS_RATING, result.rating), .75, .8, .85)
        end
        if result and result.penalty then
            GameTooltip:AddLine(string.format(NS.L.STATS_DR_DETAIL, 100 - result.penalty, result.loss),
                .75, .8, .85, true)
            if result.inDR and result.lostRating then
                GameTooltip:AddLine(string.format(NS.L.STATS_DR_AMOUNT, result.inDR, result.lostRating),
                    .75, .8, .85, true)
            end
        else
            GameTooltip:AddLine(NS.L.STATS_DR_UNKNOWN, .75, .8, .85, true)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(NS.L.STATS_DR_MASTERY, .75, .8, .85, true)
    GameTooltip:Show()
end

local function HideMetadata(v)
    for _, record in pairs(v.rows) do
        record.meta:Hide()
        record.dr:Hide()
        record.accent:Hide()
    end
    v.help:Hide()
    if GameTooltip and GameTooltip:IsOwned(v.help) then GameTooltip:Hide() end
end

local function RefreshIfShown(v)
    if Enabled(v) and Visible(v.pane) then Stats.Refresh(v) end
end

local function Create(pane, owner)
    local v = {
        pane = pane, owner = owner, active = true,
        fonts = {}, heights = {}, rows = {}, ordered = {}, results = {},
        deferKey = "character-stats:" .. owner,
    }
    for index = 1, #definitions do v.results[index] = {} end
    -- The combat-deferred refresh is the same job every time.
    v.refresh = function() RefreshIfShown(v) end

    local host = CreateFrame("Frame", nil, pane)
    v.host = host
    hosts[host] = true
    host:SetSize(1, 1)
    host:SetPoint("TOPLEFT")
    host:EnableMouse(false)

    local help = CreateFrame("Button", nil, host)
    v.help = help
    help:SetSize(28, 18)
    help:SetPoint("RIGHT", pane.EnhancementsCategory, "RIGHT", -5, 0)
    help:SetFrameLevel(pane:GetFrameLevel() + 5)
    NS.Surface.SkinOwnedButton(help, { role = "navigation", radius = 3, inset = 0, allowImplicitProtected = true })
    v.helpText = help:CreateFontString(nil, "OVERLAY")
    v.helpPath = FontPath()
    v.helpText:SetFont(v.helpPath, 9, "")
    v.helpText:SetAllPoints()
    v.helpText:SetText("DR")
    help:SetScript("OnEnter", function() Help(v) end)
    help:SetScript("OnLeave", function()
        if GameTooltip and GameTooltip:IsOwned(help) then GameTooltip:Hide() end
    end)

    host:SetScript("OnShow", function()
        if Enabled(v) then
            host:RegisterEvent("PLAYER_REGEN_DISABLED")
            Stats.Refresh(v)
        end
    end)
    host:SetScript("OnHide", function()
        host:UnregisterEvent("PLAYER_REGEN_DISABLED")
        NS.CombatGate.Cancel(v.deferKey)
        HideMetadata(v)
    end)
    -- PLAYER_REGEN_DISABLED: hide the extra rows for combat, rebuild after.
    host:SetScript("OnEvent", function()
        HideMetadata(v)
        NS.CombatGate.RunOrDefer(v.deferKey, v.refresh)
    end)
    return v
end

local function Record(v, row)
    local record = v.rows[row]
    if not record then
        record = { frame = row, spec = { radius = 4, border = 0, inset = 1, allowImplicitProtected = true } }
        v.rows[row] = record
        record.meta = row:CreateFontString(nil, "OVERLAY")
        record.meta:SetPoint("TOPLEFT", 11, -22)
        record.meta:SetWidth(80)
        record.meta:SetJustifyH("LEFT")
        record.dr = row:CreateFontString(nil, "OVERLAY")
        record.dr:SetPoint("TOPRIGHT", -8, -22)
        record.dr:SetWidth(80)
        record.dr:SetJustifyH("RIGHT")
        record.meta:Hide()
        record.dr:Hide()
        record.accent = row:CreateTexture(nil, "ARTWORK")
        record.accent:SetSize(1, 12)
        record.accent:SetPoint("LEFT", 3, 0)
    end
    record.definition, record.result = nil, nil
    local label = Read(row.Label.GetText, row.Label)
    for index, definition in ipairs(definitions) do
        local text = _G[definition.label]
        if type(text) == "string" and label == string.format(STAT_FORMAT or "%s:", text) then
            record.definition, record.result = definition, v.results[index]
            break
        end
    end
    return record
end

-- Collects the visible native stat rows in pool order; returns the row count
-- and how many of them are the four rated secondary stats.
local function CollectRows(v)
    local pool = v.pane.statsFramePool
    if not pool or type(pool.EnumerateActive) ~= "function" then return nil end
    local iterator, invariant, control = pool:EnumerateActive()
    local count, coreCount = 0, 0
    for _, record in pairs(v.rows) do
        record.meta:Hide()
        record.dr:Hide()
        record.accent:Hide()
    end
    for _ = 1, MAX_STAT_ROWS do
        local row = iterator(invariant, control)
        control = row
        if not row then break end
        if Visible(row) and row.Label and row.Value and NS.Safety.CanCreateRegions(row, true) then
            count = count + 1
            local record = Record(v, row)
            v.ordered[count] = record
            if record.definition then coreCount = coreCount + 1 end
        end
    end
    for index = #v.ordered, count + 1, -1 do v.ordered[index] = nil end
    return count, coreCount
end

local function StyleHeaders(v, itemLevel)
    -- Quiet section labels instead of another boxed card above every group.
    -- Native category/row anchors and value text still belong to PaperDoll.
    v.headerSpec = v.headerSpec or {
        role = "panel", listItem = true, border = 0, radius = 4, inset = 1, allowImplicitProtected = true,
    }
    v.ilvlSpec = v.ilvlSpec or {
        role = "card", border = 0, radius = 4, inset = 1, allowImplicitProtected = true,
    }
    for _, field in ipairs(categories) do
        local category = v.pane[field]
        if category and v.fonts[category.Title] then
            category.Title:ClearAllPoints()
            category.Title:SetPoint("LEFT", category, "LEFT", 11, 0)
            category.Title:SetJustifyH("LEFT")
            NS.Surface.Attach(category, v.headerSpec)
        end
    end
    if itemLevel then NS.Surface.Attach(itemLevel, v.ilvlSpec) end
end

local function StyleRow(v, record, detailed, wide, base, detailHeight)
    local row = record.frame
    Height(v, row, base + (detailed and detailHeight or 0))
    record.spec.inset = wide and 3 or 1
    record.spec.role = record.definition and "card" or "panel"
    record.spec.listItem = not record.definition
    NS.Surface.Attach(row, record.spec)
    for _, field in ipairs(fontFields) do
        local saved = v.fonts[row[field]]
        if saved then
            if detailed then
                local label = field == "Label"
                row[field]:ClearAllPoints()
                row[field]:SetPoint(label and "TOPLEFT" or "TOPRIGHT", row,
                    label and "TOPLEFT" or "TOPRIGHT", label and 11 or -8, wide and -7 or -4)
            else
                RestorePoints(saved)
            end
        end
    end
    if detailed then
        record.meta:ClearAllPoints()
        record.meta:SetPoint("TOPLEFT", 11, wide and -28 or -22)
        record.dr:ClearAllPoints()
        record.dr:SetPoint("TOPRIGHT", -8, wide and -28 or -22)
        local result = record.result
        local text = result.rating and string.format(NS.L.STATS_RATING, result.rating)
            or NS.L.STATS_RATING_UNKNOWN
        if record.metaText ~= text then
            record.meta:SetText(text)
            record.metaText = text
        end
        local badge = Stats.DRBadge(result)
        if record.drText ~= badge then
            record.dr:SetText(badge)
            record.drText = badge
        end
        record.dr:Show()
        record.meta:Show()
    end
    record.accent:SetShown(detailed and record.result.penalty ~= nil and record.result.penalty > 0)
end

function Stats.Refresh(v)
    if not Enabled(v) or not Visible(v.pane) then return end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(v.deferKey, v.refresh)
        return
    end
    v.host:RegisterEvent("PLAYER_REGEN_DISABLED")
    local count, coreCount = CollectRows(v)
    if not count then return end
    if count == 0 then
        v.help:Hide()
        return
    end
    local wide = NS.GearAnnotations.IsWide()
    local categoryHeight, levelHeight, detailHeight = wide and 30 or 22, wide and 48 or 34, wide and 18 or 12
    local used = 8
    for _, field in ipairs(categories) do
        local category = v.pane[field]
        if category then
            Height(v, category, categoryHeight)
            if Visible(category) then used = used + categoryHeight end
        end
    end
    local itemLevel = v.pane.ItemLevelFrame
    if itemLevel then
        Height(v, itemLevel, levelHeight)
        if Visible(itemLevel) then used = used + levelHeight end
    end
    local room = math.max(0, v.pane:GetHeight() - used)
    local diminishingReturns = Config().diminishingReturns
    local extra = diminishingReturns and coreCount * detailHeight or 0
    local base = math.min(wide and 28 or 24, math.max(15, math.floor((room - extra) / count)))
    local detailsFit = base >= 18 and room >= count * base + coreCount * detailHeight
    local showDR = diminishingReturns and detailsFit
    if not showDR then base = math.min(24, math.max(15, math.floor(room / count))) end
    if diminishingReturns then
        for index, definition in ipairs(definitions) do
            Stats.ReadRating(_G[definition.rating], v.results[index])
        end
    end
    Paint(v)
    StyleHeaders(v, itemLevel)
    for index = 1, count do
        local record = v.ordered[index]
        StyleRow(v, record, showDR and record.definition ~= nil, wide, base, detailHeight)
    end
    v.help:SetShown(diminishingReturns and Visible(v.pane.EnhancementsCategory))
end

function Stats.Apply(pane, owner)
    if NS.IsCombatLocked() or not pane or not pane.ItemLevelCategory or not pane.ItemLevelCategory.Title
        or not NS.Safety.CanCreateRegions(pane, true) then
        return
    end
    local v = Stats.views[pane]
    if not Config().enabled or not Modern() then
        if v then Stats.Disable(pane, owner) end
        return
    end
    if not v then
        v = Create(pane, owner)
        Stats.views[pane] = v
    end
    if v.owner ~= owner then return end
    v.active = true
    v.host:Show()
    Stats.Refresh(v)
end

function Stats.Disable(pane, owner)
    local v = pane and Stats.views[pane]
    if not v or v.owner ~= owner or NS.IsCombatLocked() then return end
    v.active = false
    NS.CombatGate.Cancel(v.deferKey)
    v.host:Hide()
    HideMetadata(v)
    v.host:UnregisterEvent("PLAYER_REGEN_DISABLED")
    for font, saved in pairs(v.fonts) do
        local r, g, b, a = Read(font.GetTextColor, font)
        if saved.object and font.SetFontObject then
            font:SetFontObject(saved.object)
        else
            font:SetFont(saved.path, saved.size, saved.flags)
        end
        if saved.tinted and saved.color then
            font:SetTextColor(unpack(saved.color))
        elseif r and g and b and a then
            font:SetTextColor(r, g, b, a)
        end
        RestorePoints(saved)
        if saved.justify then font:SetJustifyH(saved.justify) end
        v.fonts[font] = nil
    end
    for frame, saved in pairs(v.heights) do
        if frame:GetHeight() == saved.applied then frame:SetHeight(saved.original) end
        v.heights[frame] = nil
    end
end

function Stats.RefreshFonts()
    if NS.IsCombatLocked() then return end
    for _, v in pairs(Stats.views) do
        if Enabled(v) and Visible(v.pane) then Paint(v) end
    end
end

function Stats.SetOption(key, value)
    if NS.IsCombatLocked() or (key ~= "enabled" and key ~= "diminishingReturns")
        or type(value) ~= "boolean" then
        return false
    end
    Config()[key] = value
    if NS.DB.enabled and NS.DB.skins.blizzardWindows ~= false
        and NS.GenericWindows.IsCategoryEnabled("character") then
        NS.CharacterPanel.Apply("blizzardWindows")
    end
    return true
end

NS.Registry.AddListener(Stats, function() Stats.RefreshFonts() end)

return Stats
