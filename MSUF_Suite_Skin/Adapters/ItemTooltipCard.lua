local _, NS = ...

-- Keep the native detail lines, widgets, comparison data, anchoring and fade.
local Card, Vitals = NS.ItemTooltipCard, NS.TooltipVitals
local Safety = NS.Safety
local Palette = NS.TooltipPalette
local SPEC = { role = "popup", radius = 0, border = 0, opaqueFill = true,
    resolveFill = Palette.Fill, appearanceToken = "tooltipPalette" }
local BACKING = { role = "popup", radius = 0, border = 0, motion = false, depth = false, ownedArt = true,
    resolveFill = Palette.Fill, appearanceToken = "tooltipPalette" }
local WIDTH, HEIGHT, MIN_CARD_WIDTH = 238, 48, 160
local Caption = NS.TooltipComparisonCaption
local dataTypes = Enum.TooltipDataType
local ITEM, SPELL, UNIT, AURA = dataTypes.Item, dataTypes.Spell, dataTypes.Unit, dataTypes.UnitAura
local OBJECT, QUEST = dataTypes.Object, dataTypes.Quest
local nativeNames = { [UNIT] = true }
if OBJECT then nativeNames[OBJECT] = true end
if QUEST then nativeNames[QUEST] = true end
local spellLabels = {
    [SPELL] = "Spell", [AURA] = "Buffs and debuffs", [dataTypes.PetAction] = "Pet",
    [dataTypes.Totem] = "Totems", [dataTypes.Flyout] = "Spell", [dataTypes.Macro] = "Macros",
}
local events, installed, active
local views = {}
local appliedStyle = {}
local corePanel, panelStyle, unifiedCard, cardBackingMode
local panelLinked = false

local Setting = Card.Setting

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

function Card.CreateBacking(parent, level)
    local frame = Safety.CreateChildFrame("Frame", parent)
    frame:EnableMouse(false)
    frame:SetFrameLevel(level)
    frame:Hide()
    if NS.Surface.Attach(frame, BACKING) then return frame end
end

function Card.SetUnifiedHeader(target, unified)
    if (target.unified == true) == unified then return end
    NS.Surface.SetVisible(target.frame, not unified)
    target.unified = unified
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

function Card.Draw(target, name, icon, kind, level, quality, maxHeight, previewSize)
    local height = math.min(previewSize and previewSize.height or Card.HeaderHeight(), maxHeight or HEIGHT)
    local size = math.min(height - 8, previewSize and previewSize.iconSize or Setting("iconSize"))
    local showIcon = icon ~= nil and Setting("icon")
    target.hasIcon, target.iconSize, target.height = showIcon, size, height
    target.frame:SetHeight(height)
    target.icon:SetShown(showIcon)
    target.icon:SetTexture(icon)
    target.icon:SetSize(size, size)
    Card.PlaceContent(target, Setting("x"), Setting("y"))
    target.title:SetText(name)
    local r, g, b = Palette.Title()
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
    target.rule:SetColorTexture(Palette.Accent(r, g, b))
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

local function ReleaseBacking(view)
    if not view.nativeTitle then return end
    view.backing:Hide()
    NS.Cosmetics.Restore(view.nativeTitle, view)
    NS.TooltipChrome.SetCardBacking(view.tip, nil)
    view.nativeTitle = nil
end

local function Hide(view)
    Caption.Release(view)
    if view.header.frame:IsShown() then view.header.frame:Hide() end
    if view.outline.frame:IsShown() then view.outline.frame:Hide() end
    ReleaseBacking(view)
end

local EMPTY = {}
local function OwnerItemLink(tip)
    local _, link = Safety.Call(tip, "GetItem")
    if Safety.Public(link) and type(link) == "string" and link ~= "" then return link end
end

local function PrimaryData(tip, allowHidden, info)
    if not tip or Safety.IsForbidden(tip) or (not allowHidden and Safety.Read(tip, "IsShown") ~= true) then return end
    if info == nil then info = Safety.Call(tip, "GetPrimaryTooltipData") end
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
    if nativeNames[kind] then return kind end
    -- An aura instance, action slot or macro ID is not a spell ID.
    if spellLabels[kind] then return Setting("icon") and OwnerIcon(tip) or false end
end

local sourceColor = {}
local function ReadData(kind, key, text)
    if kind == ITEM then
        local icon, itemType, level, quality = Card.ReadItem(key)
        return text, icon, itemType, level, quality
    elseif spellLabels[kind] then
        local icon = key or nil
        if kind == SPELL then
            icon = type(key) == "number" and Setting("icon") and PositiveNumber(C_Spell.GetSpellTexture(key)) or nil
        end
        return text, icon, NS.SuiteCore().Text(spellLabels[kind])
    elseif nativeNames[kind] then
        return text, nil, nil, nil, sourceColor.r and sourceColor or nil
    end
end

local function HeaderRoom(tip, title, reserve)
    local width = Safety.Read(tip, "GetWidth")
    local screen = Safety.Read(UIParent, "GetTop")
    local tipScale, screenScale = Safety.Read(tip, "GetEffectiveScale"), Safety.Read(UIParent, "GetEffectiveScale")
    if not (width and width > 0 and screen and tipScale and tipScale > 0 and screenScale and screenScale > 0) then return end
    local ratio = tipScale / screenScale
    local height = Card.HeaderHeight()
    local top, bottom = Safety.Read(title, "GetTop"), Safety.Read(title, "GetBottom")
    local tipTop = Safety.Read(tip, "GetTop")
    if not (top and bottom and tipTop) then return end
    if top - bottom < height - 4 and (bottom + height + reserve) * ratio <= screen then
        return width, bottom - tipTop - 1, ratio
    end
    return width
end

local function PaintBacking(view, title, level)
    local chrome, tip = NS.TooltipChrome, view.tip
    if not unifiedCard or not chrome or level < 1 or not chrome.IsActive(tip)
        or not Safety.CanDecorate(title) then
        ReleaseBacking(view)
        return false
    end
    if not view.backing then
        if not Safety.CanCreateRegions(tip) then return false end
        local backing = Card.CreateBacking(tip, level - 1)
        if not backing then return false end
        backing:SetPoint("TOPLEFT", view.header.frame, "TOPLEFT")
        backing:SetPoint("TOPRIGHT", view.header.frame, "TOPRIGHT")
        backing:SetPoint("BOTTOM", tip, "BOTTOM")
        view.backing = backing
    elseif view.backing:GetFrameLevel() ~= level - 1 then
        view.backing:SetFrameLevel(level - 1)
    end
    if view.nativeTitle and view.nativeTitle ~= title then ReleaseBacking(view) end
    if not chrome.SetCardBacking(tip, cardBackingMode) then
        ReleaseBacking(view)
        return false
    end
    if not view.nativeTitle or Safety.Read(title, "GetAlpha") ~= 0 then
        if not NS.Cosmetics.Fade(title, view) then
            ReleaseBacking(view)
            chrome.SetCardBacking(tip, nil)
            return false
        end
    end
    view.nativeTitle = title
    if not view.backing:IsShown() then view.backing:Show() end
    return true
end

local function ComparisonFrames(tip)
    local tips = Safety.Field(tip, "shoppingTooltips")
    if Safety.Public(tips) and type(tips) == "table" and canaccesstable(tips) then return tips[1], tips[2] end
end

local function HasComparison(tip)
    local primary, secondary = ComparisonFrames(tip)
    return Safety.Public(primary) and Safety.Read(primary, "IsShown") == true
        or Safety.Public(secondary) and Safety.Read(secondary, "IsShown") == true
end

local function HeaderInsets(tip, width, ratio)
    local extra = MIN_CARD_WIDTH - width
    local right, screenRight = Safety.Read(tip, "GetRight"), Safety.Read(UIParent, "GetRight")
    if not (right and screenRight) then return 0, 0 end
    local room = math.max(0, screenRight / ratio - right)
    if room >= extra then return 0, extra end
    local left, screenLeft = Safety.Read(tip, "GetLeft"), Safety.Read(UIParent, "GetLeft")
    return left and screenLeft and -math.min(extra - room, math.max(0, left - screenLeft / ratio)) or 0, room
end

local function Present(view, title, width, offset, changed, ratio)
    local tip, header, outline = view.tip, view.header, view.outline
    local frame = header.frame
    local level = Safety.Read(tip, "GetFrameLevel")
    if type(level) ~= "number" then Hide(view) return end
    local unified
    if offset ~= nil then
        unified = PaintBacking(view, title, level)
        local left, right = 0, 0
        if unified and cardBackingMode == "all" and width < MIN_CARD_WIDTH and not view.comparison and not HasComparison(tip) then
            left, right = HeaderInsets(tip, width, ratio)
        end
        if header.offset ~= offset or header.left ~= left or header.right ~= right then
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOMLEFT", tip, "TOPLEFT", left, offset)
            frame:SetPoint("BOTTOMRIGHT", tip, "TOPRIGHT", right, offset)
            header.left, header.right = left, right
        end
        if frame:GetFrameLevel() ~= level + 8 then frame:SetFrameLevel(level + 8) end
        Card.SetUnifiedHeader(header, unified)
        if not frame:IsShown() then frame:Show() end
    else
        if frame:IsShown() then frame:Hide() end
        Caption.Release(view)
        ReleaseBacking(view)
    end
    local bottom = unified and view.backing or tip
    local top = unified and bottom or offset ~= nil and frame or tip
    if outline.frame:GetFrameLevel() ~= level + 9 then outline.frame:SetFrameLevel(level + 9) end
    if changed or outline.top ~= top or outline.bottom ~= bottom or not outline.frame:IsShown() then
        local r, g, b = header.r, header.g, header.b
        if not width then r, g, b = nil, nil, nil end
        Card.PaintOutline(outline, top, bottom, r, g, b)
    end
    header.offset = offset
end

local function Paint(view, allowHidden, settled, data)
    local tip = view.tip
    local info, kind, link = PrimaryData(tip, allowHidden, data)
    if not kind or (view.aurasOnly and kind ~= AURA) or not appliedStyle[spellLabels[kind] and SPELL or kind] then
        Hide(view)
        return
    end
    local title = _G[view.titleName]
    local text = Safety.Call(title, "GetText")
    if not Safety.Public(text) then
        if kind == AURA or nativeNames[kind] then Present(view, title, nil, nil, false) else Hide(view) end
        return
    end
    if type(text) ~= "string" or text == "" then Hide(view) return end
    local key = DataKey(tip, info, kind, link)
    if key == nil then Hide(view) return end
    local same = view.kind == kind and view.key == key and view.text == text
    local badge, caption
    if view.comparison then badge, caption = Caption.Read(tip) end
    local width, offset, ratio = HeaderRoom(tip, title, badge and Caption.Height or 0)
    if not width or not offset and same and not settled and view.header.frame:IsShown() then
        if settled or not same then
            Hide(view)
        elseif view.nativeTitle and Safety.Read(view.nativeTitle, "GetAlpha") ~= 0
            and not NS.Cosmetics.Fade(view.nativeTitle, view) then
            Hide(view)
        end
        return false
    end
    local changed = not same
    if nativeNames[kind] then
        local r, g, b
        if Setting("tint") then r, g, b = Safety.ReadColor(title, "GetTextColor") end
        sourceColor.r, sourceColor.g, sourceColor.b = r, g, b
        changed = changed or view.titleR ~= r or view.titleG ~= g or view.titleB ~= b
        view.titleR, view.titleG, view.titleB = r, g, b
    end
    if changed then
        local name, icon, label, level, quality = ReadData(kind, key, text)
        view.kind, view.key, view.text = kind, key, text
        Card.Draw(view.header, name, icon, label, level, quality)
    end
    if badge == false or (offset and badge and not Caption.Paint(view, badge, caption, changed)) then offset = nil end
    if not badge then Caption.Release(view) end
    Present(view, title, width, offset, changed, ratio)
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

local function FinishComparison(tip)
    if not Safety.Public(tip) then return end
    local view = views[tip]
    if not view or not view.comparison or not view.ready or Safety.Read(tip, "IsShown") ~= true then return end
    if view.retryLayout then
        RetryIfLayoutMissing(view, Paint(view, false, true))
    elseif view.nativeTitle and not NS.Cosmetics.Fade(view.nativeTitle, view) then
        Hide(view)
    end
end

-- Native comparison rows and their anchors are finalized after the item
-- post-call. Restore the first-line alpha before presenting that rebuild.
local function OnComparisonsAnchored(manager)
    if not active or not appliedStyle[ITEM] then return end
    local owner = Safety.Field(manager, "tooltip")
    if not Safety.Public(owner) or Safety.IsForbidden(owner) then return end
    local primary, secondary = ComparisonFrames(owner)
    Safety.Dispatch(FinishComparison, primary)
    Safety.Dispatch(FinishComparison, secondary)
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

local function RefitOwner(tip)
    local owner = Safety.Read(tip, "GetOwner")
    local view = owner and views[owner]
    if not view or view.comparison or not view.header.frame:IsShown() then return end
    local width = Safety.Read(owner, "GetWidth")
    if width and width < MIN_CARD_WIDTH then PaintNow(view) end
end

local function AddView(tip, titleName, aurasOnly, comparison)
    if not tip or Safety.IsForbidden(tip) then return end
    local header = Card.Create(tip)
    local view = { tip = tip, titleName = titleName, aurasOnly = aurasOnly, comparison = comparison,
        header = header, outline = Card.CreateOutline(tip) }
    views[tip] = view
    header.frame:Hide()
    view.flush = function() Flush(view) end
    tip:HookScript("OnHide", function()
        Cleared(view)
        if comparison then RefitOwner(tip) end
    end)
    tip:HookScript("OnShow", function()
        PaintNow(view)
        if comparison then RefitOwner(tip) end
    end)
    tip:HookScript("OnSizeChanged", function() if view.ready then PaintNow(view) end end)
    tip:HookScript("OnTooltipCleared", function() NativeCleared(view) end)
    return view
end

local function ComparisonView(tip, data)
    if tip ~= ShoppingTooltip1 and tip ~= ShoppingTooltip2
        and tip ~= ItemRefShoppingTooltip1 and tip ~= ItemRefShoppingTooltip2 then return end
    if not appliedStyle[ITEM] or type(data) ~= "table" or not canaccesstable(data)
        or not Safety.Public(data.type) or data.type ~= ITEM or NS.IsCombatLocked()
        or not Safety.CanCreateRegions(tip) or not rawequal(Safety.Read(tip, "GetPrimaryTooltipData"), data) then return end
    local name = Safety.Read(tip, "GetName")
    if type(name) == "string" then return AddView(tip, name .. "TextLeft1", nil, true) end
end

local function NativePostCall(tooltip, data)
    if not active or not Safety.Public(tooltip) then return end
    local view = views[tooltip]
    if not Safety.Public(data) then
        if view and not Safety.Read(tooltip, "GetPrimaryTooltipData") then Cleared(view) end
        return
    end
    if not view then
        view = ComparisonView(tooltip, data)
        if not view then return end
    elseif not rawequal(Safety.Read(tooltip, "GetPrimaryTooltipData"), data) then return end
    view.ready = true
    RetryIfLayoutMissing(view, Paint(view, true, nil, data))
    if NS.TooltipChrome and view.header.frame:IsShown() then NS.TooltipChrome.SettleBackdrop(tooltip) end
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
    for kind in pairs(nativeNames) do
        if kind == UNIT and Vitals then
            TooltipDataProcessor.AddTooltipPostCall(kind, function(tooltip, data)
                if Vitals.Enabled then Safety.Dispatch(Vitals.Native, tooltip, data) end
                NativePostCall(tooltip, data)
            end)
        else TooltipDataProcessor.AddTooltipPostCall(kind, NativePostCall) end
    end
    for kind in pairs(spellLabels) do TooltipDataProcessor.AddTooltipPostCall(kind, NativePostCall) end
    if Safety.HasMethod(TooltipComparisonManager, "AnchorShoppingTooltips") then
        hooksecurefunc(TooltipComparisonManager, "AnchorShoppingTooltips", OnComparisonsAnchored)
    end
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
        Palette.PaintHostBackdrop(corePanel, style, false)
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
    local hasPalette = Palette.PaintHostBackdrop(corePanel, style, true, Setting("borderMode") == "native")
    local r, g, b, a = Card.HeaderColor()
    if hasPalette and unifiedCard then
        style.fill:SetColorTexture(r, g, b, a)
        style.fill:SetShown(a > 0)
    else
        local fr, fg, fb
        if hasPalette then fr, fg, fb = Palette.Color("fillColor")
        else fr, fg, fb = NS.Theme.GetColor("popup") end
        style.fill:SetColorTexture(fr + (r - fr) * a, fg + (g - fg) * a, fb + (b - fb) * a, 1)
        style.fill:Show()
    end
    if Setting("tint") then r, g, b = unpack(style.titleColor)
    else r, g, b = Palette.Title() end
    style.name:SetTextColor(r, g, b, 1)
    style.rule:SetColorTexture(Palette.Accent(r, g, b))
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
    unifiedCard = Setting("cardSurface") == "unified"
    cardBackingMode = Setting("borderMode") == "native" and "fill" or "all"
    appliedStyle[ITEM] = Card.TypeStyle("item") == "custom"
    appliedStyle[SPELL] = Card.TypeStyle("spell") == "custom"
    appliedStyle[UNIT] = Card.TypeStyle("unit") == "custom"
    local quest = Card.TypeStyle("quest") == "custom"
    if OBJECT then appliedStyle[OBJECT] = quest end
    if QUEST then appliedStyle[QUEST] = quest end
    local wanted = db.enabled and (appliedStyle[ITEM] or appliedStyle[SPELL] or appliedStyle[UNIT] or quest)
    local vitalsWanted = Vitals and Vitals.Refresh()
    if (wanted or vitalsWanted) and not installed and NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(Card, Card.Refresh)
        return
    end
    if (wanted or vitalsWanted) and not installed then Install() end
    local previous = active
    active = wanted and installed == true
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
