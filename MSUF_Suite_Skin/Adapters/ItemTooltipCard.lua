local _, NS = ...

-- The rich header covers the first native line. The game's detail
-- lines, embedded widgets, comparisons, owner and fade remain native.
local Card = {}
NS.ItemTooltipCard = Card
local Safety = NS.Safety
local SPEC = { role = "popup", radius = 0, border = 0, opaqueFill = true }
local WIDTH, HEIGHT = 238, 48
local dataTypes = Enum.TooltipDataType
local ITEM, SPELL, UNIT, AURA = dataTypes.Item, dataTypes.Spell, dataTypes.Unit, dataTypes.UnitAura
local spellLabels = {
    [SPELL] = "Spell", [AURA] = "Buffs and debuffs", [dataTypes.PetAction] = "Pet",
    [dataTypes.Totem] = "Totems", [dataTypes.Flyout] = "Spell", [dataTypes.Macro] = "Macros",
}
local defaults = NS.Defaults.theme.tooltipLayout
local limits = { iconSize = { 16, 38 }, x = { 4, 22 }, y = { -5, 5 }, height = { 36, HEIGHT }, borderWidth = { 1, 4 } }
local presets = {
    compact = {},
    detailed = { borderMode = "title" },
    minimal = { rule = false, icon = false, kind = false, height = 36 },
    dense = { iconSize = 24, x = 6, height = 40, headerColor = { .08, .10, .14, 1 } },
}
local types = { item = "itemStyle", spell = "spellStyle", unit = "unitStyle", loot = "lootStyle" }
local borderModes = { suite = true, title = true, custom = true, native = true }
local events, installed, active
local views = {}
local appliedStyle = {}
local corePanel, panelStyle
local panelLinked = false

local function Setting(field)
    local settings = NS.DB.theme.tooltipLayout
    local value
    if type(settings) == "table" then value = settings[field] end
    if type(value) == type(defaults[field]) then
        local limit = limits[field]
        if not limit or (value >= limit[1] and value <= limit[2]) then return value end
    end
    return defaults[field]
end
Card.Setting = Setting
function Card.HeaderHeight() return Setting("height") end

function Card.TypeStyle(kind)
    local saved = Setting(types[kind])
    if saved == "custom" or saved == "suite" then return saved end
    if kind == "loot" then return "suite" end
    local legacy = NS.DB.theme.itemTooltipStyle == "card" and (kind == "unit" or Setting(kind))
    return legacy and "custom" or "suite"
end

local function LayoutSettings()
    local theme = NS.DB.theme
    if type(theme.tooltipLayout) ~= "table" then theme.tooltipLayout = {} end
    return theme.tooltipLayout
end

function Card.SetTypeStyle(kind, value)
    if NS.IsCombatLocked() or not Safety.Public(kind) or not Safety.Public(value) or not types[kind]
        or (value ~= "custom" and value ~= "suite") then return false end
    LayoutSettings()[types[kind]] = value
    NS.Registry.NotifyListeners("tooltipStyle", kind)
    return true
end

function Card.Set(field, value)
    if NS.IsCombatLocked() or not Safety.Public(field) or not Safety.Public(value)
        or type(field) ~= "string" or field == "preset" or field == "headerColor" or defaults[field] == nil
        or field == "borderColor" or field == "itemStyle" or field == "spellStyle" or field == "unitStyle" or field == "lootStyle"
        or type(value) ~= type(defaults[field]) then return false end
    if field == "borderMode" and not borderModes[value] then return false end
    local limit = limits[field]
    if limit and (value ~= value or value < limit[1] or value > limit[2]) then return false end
    local settings = LayoutSettings()
    settings[field], settings.preset = value, "custom"
    NS.Registry.NotifyListeners("tooltipStyle", field)
    return true
end

function Card.SetOffsets(x, y)
    if NS.IsCombatLocked() or not Safety.Public(x) or not Safety.Public(y)
        or type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return false end
    x = math.max(limits.x[1], math.min(limits.x[2], math.floor(x + .5)))
    y = math.max(limits.y[1], math.min(limits.y[2], math.floor(y + .5)))
    if x == Setting("x") and y == Setting("y") then return false end
    local settings = LayoutSettings()
    settings.x, settings.y, settings.preset = x, y, "custom"
    NS.Registry.NotifyListeners("tooltipStyle", "position")
    return true
end

local function Channel(value)
    return Safety.Public(value) and type(value) == "number" and value >= 0 and value <= 1
end

local function GetColor(key)
    local rgba = Setting(key)
    if canaccesstable(rgba) and Channel(rgba[1]) and Channel(rgba[2]) and Channel(rgba[3]) and Channel(rgba[4]) then
        return unpack(rgba, 1, 4)
    end
    return unpack(defaults[key])
end

local function SetColor(key, r, g, b, a)
    if NS.IsCombatLocked() or not (Channel(r) and Channel(g) and Channel(b) and Channel(a)) then return false end
    local settings = LayoutSettings()
    settings[key], settings.preset = { r, g, b, a }, "custom"
    if key == "borderColor" then settings.borderMode = "custom" end
    NS.Registry.NotifyListeners("tooltipStyle", key)
    return true
end

function Card.HeaderColor() return GetColor("headerColor") end
function Card.BorderColor() return GetColor("borderColor") end
function Card.SetHeaderColor(...) return SetColor("headerColor", ...) end
function Card.SetBorderColor(...) return SetColor("borderColor", ...) end

function Card.SetPreset(key)
    if NS.IsCombatLocked() or not Safety.Public(key) or type(key) ~= "string" then return false end
    if key ~= "custom" and not presets[key] then return false end
    local theme, item, spell, unit = NS.DB.theme, Card.TypeStyle("item"), Card.TypeStyle("spell"), Card.TypeStyle("unit")
    local loot = Card.TypeStyle("loot")
    if key == "custom" then
        LayoutSettings().preset = "custom"
    else
        theme.tooltipLayout = NS.CopyValue(presets[key])
        theme.tooltipLayout.preset = key
    end
    local settings = theme.tooltipLayout
    settings.itemStyle, settings.spellStyle, settings.unitStyle, settings.lootStyle = item, spell, unit, loot
    NS.Registry.NotifyListeners("tooltipStyle", "preset")
    return true
end

function Card.Preset()
    local theme = NS.DB.theme
    local key = Setting("preset")
    if key == "custom" or presets[key] then return key end
    return theme.itemTooltipStyle == "card" and "custom" or "compact"
end

local function Label(frame, font, x, y)
    local text = frame:CreateFontString(nil, "OVERLAY", font)
    text:SetPoint("TOPLEFT", x, y)
    text:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -11, y)
    text:SetJustifyH("LEFT")
    text:SetMaxLines(1)
    text:SetWordWrap(false)
    return text
end

function Card.Create(parent, detached)
    local frame = detached and Safety.CreateChildFrame("Frame", parent) or CreateFrame("Frame", nil, parent)
    frame:EnableMouse(false)
    frame:SetSize(WIDTH, HEIGHT)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", 10, 0)
    icon:SetSize(30, 30)
    icon:SetTexCoord(.07, .93, .07, .93)
    local title = Label(frame, "GameFontNormal", 49, -7)
    local meta = Label(frame, "GameFontHighlightSmall", 49, -27)
    NS.Surface.Attach(frame, SPEC)
    local background = frame:CreateTexture(nil, "ARTWORK", nil, -7)
    background:SetAllPoints()
    local rule = frame:CreateTexture(nil, "OVERLAY")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    return { frame = frame, icon = icon, title = title, meta = meta, rule = rule, background = background }
end

function Card.PlaceContent(target, x, y)
    local inset = x + (target.hasIcon and target.iconSize + 9 or 0)
    local meta = (target.height < 42 and -22 or -27) + y
    target.icon:ClearAllPoints()
    target.icon:SetPoint("LEFT", x, y)
    target.title:SetPoint("TOPLEFT", inset, -7 + y)
    target.title:SetPoint("TOPRIGHT", -11, -7 + y)
    target.meta:SetPoint("TOPLEFT", inset, meta)
    target.meta:SetPoint("TOPRIGHT", -11, meta)
end

function Card.Draw(target, name, icon, kind, level, quality, maxHeight)
    local height = math.min(Card.HeaderHeight(), maxHeight or HEIGHT)
    local size = math.min(height - 8, Setting("iconSize"))
    local showIcon = icon ~= nil and Setting("icon")
    target.hasIcon, target.iconSize, target.height = showIcon, size, height
    target.frame:SetHeight(height)
    target.icon:SetShown(showIcon)
    target.icon:SetTexture(icon)
    target.icon:SetSize(size, size)
    Card.PlaceContent(target, Setting("x"), Setting("y"))
    target.title:SetText(name)
    local r, g, b = NS.Theme.GetColor("text")
    if Setting("tint") and type(quality) == "number" then
        local qr, qg, qb = C_Item.GetItemQualityColor(quality)
        if Safety.Public(qr) and Safety.Public(qg) and Safety.Public(qb)
            and type(qr) == "number" and type(qg) == "number" and type(qb) == "number" then r, g, b = qr, qg, qb end
    elseif type(quality) == "table" and Setting("tint") then
        r, g, b = quality.r, quality.g, quality.b
    end
    target.r, target.g, target.b = r, g, b
    target.title:SetTextColor(r, g, b)
    local br, bg, bb, ba = Card.HeaderColor()
    target.background:SetColorTexture(br, bg, bb, ba)
    target.background:SetShown(ba > 0)
    target.rule:SetColorTexture(r, g, b, .74)
    target.rule:SetShown(Setting("rule"))
    local meta = level and Setting("level") and level or nil
    if kind and Setting("kind") then meta = meta and meta .. "  ·  " .. kind or kind end
    target.meta:SetText(meta or "")
    NS.LabelStyle.Apply(target.title, target, false)
    NS.LabelStyle.Apply(target.meta, target, false)
end

function Card.CreateOutline(parent, detached)
    local frame = detached and Safety.CreateChildFrame("Frame", parent) or CreateFrame("Frame", nil, parent)
    frame:EnableMouse(false)
    local edges = {}
    for index, point in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = frame:CreateTexture(nil, "OVERLAY")
        if index <= 2 then
            edge:SetPoint(point .. "LEFT")
            edge:SetPoint(point .. "RIGHT")
        else
            edge:SetPoint("TOP" .. point)
            edge:SetPoint("BOTTOM" .. point)
        end
        edges[index] = edge
    end
    frame:Hide()
    return { frame = frame, edges = edges }
end

function Card.PaintOutline(target, top, bottom, r, g, b)
    local mode = Setting("borderMode")
    if mode == "native" then
        if target.frame:IsShown() then target.frame:Hide() end
        return
    end
    local a = 1
    if mode == "custom" then r, g, b, a = Card.BorderColor()
    elseif mode ~= "title" or not r then r, g, b, a = NS.Theme.GetColor("border") end
    local width = Setting("borderWidth")
    for index, edge in ipairs(target.edges) do
        if index <= 2 then edge:SetHeight(width) else edge:SetWidth(width) end
        edge:SetColorTexture(r, g, b, a)
    end
    local frame = target.frame
    if target.top ~= top or target.bottom ~= bottom then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", top, "TOPLEFT")
        frame:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT")
        target.top, target.bottom = top, bottom
    end
    frame:Show()
end

local function Hide(view)
    if view.header.frame:IsShown() then view.header.frame:Hide() end
    if view.outline.frame:IsShown() then view.outline.frame:Hide() end
end

local EMPTY = {}
local function OwnerItemLink(tip)
    local _, link = Safety.Call(tip, "GetItem")
    if Safety.Public(link) and type(link) == "string" and link ~= "" then return link end
end

local function PrimaryData(tip, allowHidden)
    if not tip or Safety.IsForbidden(tip) or (not allowHidden and Safety.Read(tip, "IsShown") ~= true) then return end
    local info = Safety.Call(tip, "GetPrimaryTooltipData")
    if not Safety.Public(info) then return end
    if info == nil then
        local link = OwnerItemLink(tip)
        if link then return EMPTY, ITEM, link end
        return
    end
    if type(info) ~= "table" or not canaccesstable(info) then return end
    local kind = info.type
    if Safety.Public(kind) then return info, kind end
end

local function PositiveNumber(value)
    return Safety.Public(value) and type(value) == "number" and value > 0 and value < math.huge and value or nil
end

local function ItemKey(tip, info)
    local link = info.hyperlink
    if not Safety.Public(link) then return end
    if type(link) == "string" and link ~= "" then return link end
    local _, itemLink = Safety.Call(tip, "GetItem")
    if not Safety.Public(itemLink) then return end
    if type(itemLink) == "string" and itemLink ~= "" then return itemLink end
    return PositiveNumber(info.id)
end

function Card.ReadItem(key)
    local link = type(key) == "string" and key
    local _, _, quality, base, _, kind, subclass, _, _, icon = C_Item.GetItemInfo(key)
    if not PositiveNumber(icon) then
        local _, itemType, itemSubclass, _, file = C_Item.GetItemInfoInstant(key)
        kind, subclass, icon = itemType, itemSubclass, file
    end
    local level = link and (PositiveNumber(C_Item.GetDetailedItemLevelInfo(link)) or PositiveNumber(base))
    if not Safety.Public(quality) or type(quality) ~= "number" then quality = nil end
    if not Safety.Public(subclass) or type(subclass) ~= "string" or subclass == "" then subclass = kind end
    if not Safety.Public(subclass) or type(subclass) ~= "string" then subclass = nil end
    return PositiveNumber(icon), subclass, level and NS.SuiteCore().Text("Item level %d"):format(level), quality
end

local function TextureKey(region)
    if not Safety.Public(region) then return end
    local texture = Safety.Read(region, "GetTexture")
    if type(texture) == "string" and texture ~= "" then return texture end
    return PositiveNumber(texture)
end

local function OwnerIcon(tip)
    local owner = Safety.Read(tip, "GetOwner")
    if not owner or Safety.IsForbidden(owner) then return end
    return TextureKey(Safety.Field(owner, "Icon")) or TextureKey(Safety.Field(owner, "icon"))
end

local function DataKey(tip, info, kind, link)
    if kind == ITEM then return link or ItemKey(tip, info) end
    if kind == SPELL then return PositiveNumber(info.id) or "spell" end
    if kind == UNIT then return "unit" end
    -- An aura instance, action slot or macro ID is not a spell ID.
    if spellLabels[kind] then return Setting("icon") and OwnerIcon(tip) or false end
end

local sourceColor = {}
local function ReadData(kind, key, text, title)
    if kind == ITEM then
        local icon, itemType, level, quality = Card.ReadItem(key)
        return text, icon, itemType, level, quality
    elseif spellLabels[kind] then
        local icon = key or nil
        if kind == SPELL then
            icon = type(key) == "number" and Setting("icon") and PositiveNumber(C_Spell.GetSpellTexture(key)) or nil
        end
        return text, icon, NS.SuiteCore().Text(spellLabels[kind])
    elseif kind == UNIT then
        sourceColor.r, sourceColor.g, sourceColor.b = Safety.ReadColor(title, "GetTextColor")
        return text, nil, nil, nil, sourceColor.r and sourceColor or nil
    end
end

local function HeaderRoom(tip, title)
    local width = Safety.Read(tip, "GetWidth")
    local screen = Safety.Read(UIParent, "GetTop")
    local tipScale, screenScale = Safety.Read(tip, "GetEffectiveScale"), Safety.Read(UIParent, "GetEffectiveScale")
    if not (width and width > 0 and screen and tipScale and tipScale > 0 and screenScale and screenScale > 0) then return end
    local ratio = tipScale / screenScale
    local height = Card.HeaderHeight()
    local top, bottom = Safety.Read(title, "GetTop"), Safety.Read(title, "GetBottom")
    local left, titleLeft = Safety.Read(tip, "GetLeft"), Safety.Read(title, "GetLeft")
    if not (top and bottom and left and titleLeft) then return end
    if top - bottom < height - 4 and (bottom + height) * ratio <= screen then
        return width, left - titleLeft
    end
    return width
end

local function Present(view, title, width, offset, changed)
    local tip, header, outline = view.tip, view.header, view.outline
    local frame = header.frame
    local level = Safety.Read(tip, "GetFrameLevel")
    if type(level) ~= "number" then Hide(view) return end
    if offset ~= nil then
        if header.width ~= width or header.offset ~= offset then
            frame:ClearAllPoints()
            frame:SetWidth(width)
            frame:SetPoint("BOTTOMLEFT", title, "BOTTOMLEFT", offset, -1)
        end
        if frame:GetFrameLevel() ~= level + 8 then frame:SetFrameLevel(level + 8) end
        if not frame:IsShown() then frame:Show() end
    elseif frame:IsShown() then frame:Hide() end
    local top = offset ~= nil and frame or tip
    if outline.frame:GetFrameLevel() ~= level + 9 then outline.frame:SetFrameLevel(level + 9) end
    if changed or outline.top ~= top or not outline.frame:IsShown() then
        local r, g, b = header.r, header.g, header.b
        if not width then r, g, b = Safety.ReadColor(title, "GetTextColor") end
        Card.PaintOutline(outline, top, tip, r, g, b)
    end
    header.width, header.offset = width, offset
end

local function Paint(view, allowHidden, settled)
    local tip = view.tip
    local info, kind, link = PrimaryData(tip, allowHidden)
    if not kind or (view.aurasOnly and kind ~= AURA) or not appliedStyle[spellLabels[kind] and SPELL or kind] then
        Hide(view)
        return
    end
    local title = _G[view.titleName]
    local text = Safety.Call(title, "GetText")
    if not Safety.Public(text) then
        if kind == AURA or kind == UNIT then Present(view, title, nil, nil, true) else Hide(view) end
        return
    end
    if type(text) ~= "string" or text == "" then Hide(view) return end
    local key = DataKey(tip, info, kind, link)
    if key == nil then Hide(view) return end
    local same = view.kind == kind and view.key == key and view.text == text
    local width, offset = HeaderRoom(tip, title)
    if not width then
        if settled or not same then Hide(view) end
        return false
    end
    if not offset and same and not settled and view.header.frame:IsShown() then return false end
    local changed = not same or kind == UNIT
    if changed then
        local name, icon, label, level, quality = ReadData(kind, key, text, title)
        view.kind, view.key, view.text = kind, key, text
        Card.Draw(view.header, name, icon, label, level, quality)
    end
    Present(view, title, width, offset, changed)
end

local function Flush(view)
    view.queued = false
    if not active then return end
    if not view.ready then Hide(view)
    elseif view.retryLayout then Paint(view, false, true) end
end

local function QueueSettlement(view)
    if view.queued then return end
    view.queued = true
    C_Timer.After(0, view.flush)
end

local function RetryIfLayoutMissing(view, result)
    view.retryLayout = result == false
    if view.retryLayout then QueueSettlement(view) end
end

local function PaintNow(view)
    if not active then return end
    view.ready = true
    RetryIfLayoutMissing(view, Paint(view))
end

local function NativePostCall(tooltip, data)
    if not active or not Safety.Public(tooltip) or not Safety.Public(data) then return end
    local view = views[tooltip]
    if not view then return end
    if not rawequal(Safety.Read(tooltip, "GetPrimaryTooltipData"), data) then return end
    view.ready = true
    RetryIfLayoutMissing(view, Paint(view, true))
    if NS.TooltipChrome and view.header.frame:IsShown() then NS.TooltipChrome.SettleBackdrop(tooltip) end
end

function Card.HasVisibleHeader(tooltip)
    local view = views[tooltip or GameTooltip]
    return active and view and view.header.frame:IsShown()
end

local function Cleared(view)
    view.ready, view.retryLayout = false, false
    Hide(view)
end

local function NativeCleared(view)
    view.ready, view.retryLayout = false, false
    -- ClearLines also runs during in-place rebuilds. A replacement title can
    -- take over in the same native call without dropping the visible art.
    if active and Safety.Read(view.tip, "IsShown") == true
        and (view.header.frame:IsShown() or view.outline.frame:IsShown()) then
        QueueSettlement(view)
    else
        Hide(view)
    end
end

local function AddView(tip, titleName, aurasOnly)
    if not tip or Safety.IsForbidden(tip) then return end
    local header = Card.Create(tip)
    local view = { tip = tip, titleName = titleName, aurasOnly = aurasOnly,
        header = header, outline = Card.CreateOutline(tip) }
    views[tip] = view
    header.frame:Hide()
    view.flush = function() Flush(view) end
    tip:HookScript("OnHide", function() Cleared(view) end)
    tip:HookScript("OnShow", function() PaintNow(view) end)
    tip:HookScript("OnSizeChanged", function() if view.ready then PaintNow(view) end end)
    tip:HookScript("OnTooltipCleared", function() NativeCleared(view) end)
end

local function PaintAll()
    for _, view in pairs(views) do PaintNow(view) end
end

local function Install()
    if installed then return true end
    if not GameTooltip then return false end
    AddView(GameTooltip, "GameTooltipTextLeft1")
    AddView(BuffFrameTooltip, "BuffFrameTooltipTextLeft1", true)
    TooltipDataProcessor.AddTooltipPostCall(ITEM, NativePostCall)
    TooltipDataProcessor.AddTooltipPostCall(UNIT, NativePostCall)
    for kind in pairs(spellLabels) do TooltipDataProcessor.AddTooltipPostCall(kind, NativePostCall) end
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", PaintAll)
    installed = true
    return true
end

local function RestoreTextAnchor(text, point)
    text:ClearAllPoints()
    text:SetPoint(unpack(point))
end

local function CreateCoreStyle(frame)
    local name, body = frame.name, frame.line2
    if not name or not body then return end
    local r, g, b, a = Safety.ReadColor(name, "GetTextColor")
    if not r then r, g, b, a = NS.Theme.GetColor("text") end
    local fill = frame:CreateTexture(nil, "ARTWORK", nil, -7)
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("TOPRIGHT", -3, -3)
    fill:SetHeight(HEIGHT - 3)
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    rule:SetHeight(1)
    local border = Card.CreateOutline(frame)
    border.frame:SetFrameLevel(frame:GetFrameLevel() + 1)
    return { fill = fill, rule = rule, outline = border, name = name, body = body, height = frame:GetHeight(),
        titleAnchor = { name:GetPoint(1) }, bodyAnchor = { body:GetPoint(1) }, titleColor = { r, g, b, a } }
end

-- The custom panel already receives the title and details from Core, including
-- values sent directly to a native FontString. Style those regions in place.
local function PaintCorePanel()
    if not corePanel then return end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(PaintCorePanel, PaintCorePanel)
        return
    end
    if not active or not appliedStyle[UNIT] then
        local style = panelStyle
        if not style or not style.applied then return end
        style.applied = false
        style.fill:Hide()
        style.rule:Hide()
        style.outline.frame:Hide()
        RestoreTextAnchor(style.name, style.titleAnchor)
        RestoreTextAnchor(style.body, style.bodyAnchor)
        style.name:SetTextColor(unpack(style.titleColor))
        corePanel:SetHeight(style.height)
        return
    end
    panelStyle = panelStyle or CreateCoreStyle(corePanel)
    local style = panelStyle
    if not style then return end
    style.applied = true
    local x, y = Setting("x"), Setting("y")
    local height = Card.HeaderHeight()
    style.name:ClearAllPoints()
    style.name:SetPoint("TOPLEFT", corePanel, "TOPLEFT", x, -7 + y)
    style.body:ClearAllPoints()
    style.body:SetPoint("TOPLEFT", corePanel, "TOPLEFT", 8, -height - 5)
    style.fill:SetHeight(height - 3)
    corePanel:SetHeight(style.height + height - 25)
    local fr, fg, fb = NS.Theme.GetColor("popup")
    local r, g, b, a = Card.HeaderColor()
    style.fill:SetColorTexture(fr + (r - fr) * a, fg + (g - fg) * a, fb + (b - fb) * a, 1)
    style.fill:Show()
    if Setting("tint") then r, g, b = unpack(style.titleColor)
    else r, g, b = NS.Theme.GetColor("text") end
    style.name:SetTextColor(r, g, b, 1)
    style.rule:SetColorTexture(r, g, b, .74)
    style.rule:SetShown(Setting("rule"))
    Card.PaintOutline(style.outline, corePanel, corePanel, r, g, b)
end

local function ReceiveCorePanel(frame)
    corePanel = frame
    PaintCorePanel()
end

local function RefreshCorePanel()
    local wanted = active == true and appliedStyle[UNIT]
    if wanted ~= panelLinked then
        local host = NS.SuiteCore().HostBridge
        panelLinked = host.SetUnitFrameTooltipPanelStyler(wanted and ReceiveCorePanel or nil) == true and wanted
    end
    PaintCorePanel()
end

function Card.Refresh()
    local db = NS.DB
    if not db then return end
    appliedStyle[ITEM] = Card.TypeStyle("item") == "custom"
    appliedStyle[SPELL] = Card.TypeStyle("spell") == "custom"
    appliedStyle[UNIT] = Card.TypeStyle("unit") == "custom"
    local wanted = db.enabled and (appliedStyle[ITEM] or appliedStyle[SPELL] or appliedStyle[UNIT])
    if wanted and not installed and NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(Card, Card.Refresh)
        return
    end
    local previous = active
    active = wanted and (installed or Install()) == true
    if active then
        if not previous then
            events:RegisterEvent("PLAYER_REGEN_DISABLED")
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        PaintAll()
    else
        if previous then events:UnregisterAllEvents() end
        for _, view in pairs(views) do Cleared(view) end
    end
    RefreshCorePanel()
end

NS.Registry.AddListener(Card, function(_, domain)
    if domain == "typography" or domain == "color" or domain == "theme" or domain == "profile"
        or domain == "adapter" or domain == "tooltipStyle" then
        for _, view in pairs(views) do view.kind, view.key, view.text = nil, nil, nil end
        Card.Refresh()
    end
end)
