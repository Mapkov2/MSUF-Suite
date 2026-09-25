local _, NS = ...

-- Read-only equipment dossier for Blizzard's PaperDoll and Inspect pages.
-- Source: wow-ui-source upstream/live 8ea15b61e45c0ed4eba01439c90757f86eb78d34,
-- InspectPaperDollFrame.lua, CharacterFrame.lua and Item/PaperDollInfo API docs.
-- Native item actions and inspection requests stay Blizzard-owned. The optional
-- wide Character layout is reversible and never applies to Inspect.
local Details = { views = setmetatable({}, { __mode = "k" }) }
NS.CharacterDetails = Details

local Public = NS.Safety.Public

local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local ROW_HEIGHT = 28
local hosts = setmetatable({}, { __mode = "k" })
local slots = {
    { 1, "HeadSlot" }, { 2, "NeckSlot" }, { 3, "ShoulderSlot" }, { 15, "BackSlot" },
    { 5, "ChestSlot" }, { 9, "WristSlot" }, { 10, "HandsSlot" }, { 6, "WaistSlot" },
    { 7, "LegsSlot" }, { 8, "FeetSlot" }, { 11, "Finger0Slot" }, { 12, "Finger1Slot" },
    { 13, "Trinket0Slot" }, { 14, "Trinket1Slot" }, { 16, "MainHandSlot" }, { 17, "SecondaryHandSlot" },
}
local events = {
    "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "UPDATE_INVENTORY_DURABILITY",
    "GET_ITEM_INFO_RECEIVED", "INSPECT_READY", "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_LEVEL_UP", "PLAYER_AVG_ITEM_LEVEL_UPDATE",
}
local OPTION_KEYS = {
    enabled = true, expanded = true, styleEQoL = true, inlineGear = true, wideLayout = true,
}
local VIEWS = { modern = true, list = true, classic = true }

function Details.IsHost(frame)
    return hosts[frame] == true
end

local function Accessible(value)
    if Public(value) then return value end
    return nil
end

-- Calls a Blizzard getter with valid arguments; secret results become nil.
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local a, b, c = fn(...)
    return Accessible(a), Accessible(b), Accessible(c)
end

local function Text(value)
    return type(value) == "string" and value or nil
end

local function Number(value)
    return type(value) == "number" and value == value and value >= 0 and value < 1e9 and value or nil
end

local function Config()
    return NS.DB and NS.DB.characterDetails or NS.Defaults.characterDetails
end

function Details.GetView()
    return Config().view
end

function Details.IsModern()
    return (not NS.Client or NS.Client.modernEquipment)
        and (Config().view == nil or Config().view == "modern")
end

-- Whether this view shows item data (and needs events and reads).
local function NeedsData(v)
    local config = Config()
    if v.kind == "character" and config.view then return config.view ~= "classic" end
    return config.expanded or (v.kind == "character" and config.inlineGear == true)
end

local function Enabled(v)
    if NS.Client and not NS.Client.modernEquipment then return false end
    local config = Config()
    return v.active and NS.DB and NS.DB.enabled and NS.DB.skins.blizzardWindows ~= false
        and NS.GenericWindows.IsCategoryEnabled("character")
        and ((v.kind == "character" and config.view and config.view ~= "classic")
            or (not (v.kind == "character" and config.view) and config.enabled))
end

local function Color(region, token)
    region:SetTextColor(NS.Theme.GetColor(token))
end

local function FontPath()
    return Read(GameFontNormal and GameFontNormal.GetFont, GameFontNormal)
        or STANDARD_TEXT_FONT or DEFAULT_FONT
end

local function Label(parent, size, token)
    local font = parent:CreateFontString(nil, "OVERLAY")
    font.dossierFontSize = size
    font:SetFont(FontPath(), size, "")
    font:SetJustifyH("LEFT")
    font:SetWordWrap(false)
    Color(font, token)
    return font
end

local function RefreshFonts(v)
    local path = FontPath()
    if path == v.fontPath then return end
    v.fontPath = path
    for _, font in ipairs(v.fonts) do font:SetFont(path, font.dossierFontSize, "") end
end

function Details.RefreshFonts()
    if NS.IsCombatLocked() then return end
    for _, v in pairs(Details.views) do
        if Enabled(v) and v.host:IsVisible() then
            RefreshFonts(v)
            for _, row in ipairs(v.rows) do NS.GearAnnotations.Paint(v, row) end
            NS.GearAnnotations.UpdateSummary(v)
        end
    end
end

function Details.StyleChrome(root, owner)
    if not root or NS.IsCombatLocked() then return end
    local close = root.CloseButton or _G[(root:GetName() or "") .. "CloseButton"]
    if close then NS.WindowActionSkin.Apply(close, owner, "close") end
end

local function Unit(v)
    return v.kind == "character" and "player" or Text(Accessible(v.root.unit))
end

local function GUID(unit)
    return unit and Text(Read(UnitGUID, unit))
end

local function Clear(v)
    v.unit, v.guid = nil, nil
    for id in pairs(v.pending) do v.pending[id] = nil end
    for _, row in ipairs(v.rows) do
        row.link, row.baseMeta, row.eqolMeta, row.eqolTrack = nil, nil, nil, nil
        row.icon:SetTexture(nil)
        row.name:SetText("")
        row.meta:SetText("")
        row.level:SetText("")
        row.track:SetText("")
    end
    v.identity:SetText(NS.L.DOSSIER_LOADING)
    v.subtitle:SetText("")
    v.specialization:SetText("")
    v.average:SetText("--")
    v.summary:SetText("")
    v.checkText:SetText("")
    v.footer:SetText(NS.L.DOSSIER_PENDING)
end

local function Unregister(v)
    if not v.registered then return end
    for _, event in ipairs(events) do v.host:UnregisterEvent(event) end
    v.registered = false
end

local function HideTooltip(v)
    if not GameTooltip or type(GameTooltip.IsOwned) ~= "function" then return end
    if GameTooltip:IsOwned(v.toggle) then
        GameTooltip:Hide()
        return
    end
    for _, row in ipairs(v.rows) do
        if GameTooltip:IsOwned(row.frame) then
            GameTooltip:Hide()
            return
        end
    end
end

-- One deferred refresh per view (the job is built once in Create).
local function Queue(v)
    v.dirty = true
    NS.CombatGate.RunOrDefer(v.deferKey, v.deferredRefresh)
end

local function SlotLabel(slot)
    return Text(_G[string.upper(slot[2])]) or slot[2]
end

-- Optional EnhanceQoL coexistence: prefer its enchant/track texts when present.
local function EQoLMetadata(v, row, element)
    local audit = row.audit
    local enchant = audit and audit.enchantLabel
    local track = audit and audit.upgradeText
    if Config().styleEQoL ~= false and element then
        if not enchant or enchant == "" then
            enchant = Text(Read(element.enchant and element.enchant.GetText, element.enchant))
        end
        if not track and Read(element.trackLabel and element.trackLabel.IsShown, element.trackLabel) then
            track = Text(Read(element.trackLabel.GetText, element.trackLabel))
        end
    end
    local metadata = enchant and enchant ~= "" and enchant or row.baseMeta or ""
    if audit and audit.sockets and audit.sockets > 0 then
        metadata = metadata .. "  |  " .. string.format(NS.L.GEAR_SOCKETS, audit.gems or 0, audit.sockets)
    end
    if row.eqolMeta ~= metadata then
        row.meta:SetText(metadata)
        row.eqolMeta = metadata
    end
    track = track or ""
    if row.eqolTrack ~= track then
        row.track:SetText(track)
        row.eqolTrack = track
    end
    local nameWidth = track ~= "" and 190 or 236
    if row.name:GetWidth() ~= nameWidth then row.name:SetWidth(nameWidth) end
    if track ~= "" and element and element.trackLabel then
        local r, g, b = Read(element.trackLabel.GetTextColor, element.trackLabel)
        if r and g and b then row.track:SetTextColor(r, g, b, 1) end
    else
        Color(row.track, "muted")
    end
    if audit then Color(row.meta, audit.enchantToken or "muted") end
end

function Details.RefreshEQoL(element, slotID)
    local v = Details.views[_G.CharacterFrame]
    if NS.IsCombatLocked() or not v or not Enabled(v) or not v.host:IsVisible()
        or not NeedsData(v) then
        return
    end
    local row = v.bySlot[slotID]
    if row then
        EQoLMetadata(v, row, element)
        NS.GearAnnotations.Update(v, row, row.slotName)
    end
end

local function Durability(v, row)
    local current, maximum
    if v.kind == "character" then current, maximum = Read(GetInventoryItemDurability, row.slot) end
    current, maximum = Number(current), Number(maximum)
    local durability = current and maximum and maximum > 0 and current / maximum or nil
    row.durability = durability
    local itemLevel = row.audit and row.audit.itemLevel
    local text = itemLevel and string.format("%d", itemLevel) or "--"
    if durability then text = text .. "\n" .. string.format("%d%%", durability * 100) end
    if row.level:GetText() ~= text then row.level:SetText(text) end
    Color(row.level, durability and (durability < .25 and "danger" or durability < .6 and "warning") or "text")
    return durability
end

local function ProviderElement(v, slot)
    local provider = v.kind == "character" and _G.EnhanceQoL
    local element = provider and provider.variables and provider.variables.itemSlots
        and provider.variables.itemSlots[slot[1]]
    if element ~= _G["Character" .. slot[2]] then return nil end
    return element
end

-- Reads one slot (or reuses its snapshot when another slot changed).
-- Returns itemLevel, enchanted, gems, durability, pending.
local function ReadRow(v, row, slot, onlySlot)
    local id = slot[1]
    if onlySlot and onlySlot ~= id and row.audit then
        return row.audit.itemLevel, row.audit.enchanted, row.audit.gems, row.durability, row.audit.pending
    end
    local link = Text(Read(GetInventoryItemLink, v.unit, id))
    local info = NS.EquipmentInfo.Read(link, v.unit, id, row.audit, v.guid)
    row.audit = info
    NS.EquipmentInfo.Check(info, v.level)
    local texture = info.texture or Read(GetInventoryItemTexture, v.unit, id)
    local quality = info.quality or Number(Read(GetInventoryItemQuality, v.unit, id))
    row.inventoryTexture, row.quality = texture, quality
    row.link = link
    row.icon:SetTexture(texture)
    local itemName, itemLevel, pending = info.name, info.itemLevel, info.pending
    row.name:SetText(itemName or ((link or texture) and NS.L.DOSSIER_LOADING or NS.L.DOSSIER_EMPTY))
    row.level:SetText(itemLevel and string.format("%d", itemLevel) or "--")
    local qualityColor = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if qualityColor then
        row.name:SetTextColor(qualityColor.r, qualityColor.g, qualityColor.b, 1)
    else
        Color(row.name, "muted")
    end
    local enchanted, gems = info.enchanted, info.gems
    local details = SlotLabel(slot)
    if link then
        if enchanted then details = details .. "  |  " .. NS.L.DOSSIER_ENCHANTED end
        if not info.sockets and gems and gems > 0 then
            details = details .. "  |  " .. string.format(NS.L.DOSSIER_GEMS, gems)
        end
    end
    row.baseMeta = details
    EQoLMetadata(v, row, ProviderElement(v, slot))
    local durability = Durability(v, row)
    NS.GearAnnotations.Update(v, row, slot[2])
    return itemLevel, enchanted, gems, durability, pending or (texture ~= nil and not link)
end

local function Paint(v)
    RefreshFonts(v)
    Color(v.heading, "accent")
    Color(v.identity, "title")
    Color(v.subtitle, "muted")
    Color(v.specialization, "muted")
    Color(v.average, "title")
    Color(v.averageLabel, "muted")
    Color(v.summary, "muted")
    Color(v.footer, "dim")
    for _, row in ipairs(v.rows) do
        Color(row.meta, row.audit and row.audit.enchantToken or "muted")
        NS.GearAnnotations.Paint(v, row)
    end
    v.accent:SetColorTexture(NS.Theme.GetColor("accent"))
    Color(v.toggleText, "text")
end

local function Disclosure(v)
    local config = Config()
    if v.kind == "character" and config.view then
        v.panel:SetShown(config.view == "list")
        v.toggle:Hide()
        return
    end
    v.panel:SetShown(config.expanded)
    v.toggle:Show()
    v.toggle:ClearAllPoints()
    if config.expanded then
        v.toggle:SetPoint("TOPRIGHT", v.panel, "TOPRIGHT", -8, -8)
    else
        v.toggle:SetPoint("TOPLEFT", v.root, "TOPRIGHT", 8, -34)
    end
    local action = NS.WindowActionSkin.Apply(v.toggle, v.actionOwner, config.expanded and "collapse" or "expand")
    v.toggleText:SetText(config.expanded and "-" or "+")
    v.toggleText:SetShown(not action or action.style == "native")
end

local function FooterText(waiting, lowest)
    if waiting then return NS.L.DOSSIER_PENDING end
    if lowest then return string.format(NS.L.DOSSIER_DURABILITY, lowest * 100) end
    return NS.L.DOSSIER_INSPECT_NOTE
end

local function RefreshDurability(v)
    local lowest, waiting
    for _, row in ipairs(v.rows) do
        local value = Durability(v, row)
        if value then lowest = math.min(lowest or 1, value) end
        waiting = waiting or (row.audit and row.audit.pending)
    end
    v.footer:SetText(FooterText(waiting, lowest))
    NS.GearAnnotations.UpdateSummary(v)
end

local function SpecializationName(v, unit)
    if not C_SpecializationInfo then return nil end
    local sex = Number(Read(UnitSex, unit))
    if v.kind == "character" then
        local index = Number(Read(C_SpecializationInfo.GetSpecialization))
        if not index then return nil end
        local _, name = Read(C_SpecializationInfo.GetSpecializationInfo, index, false, false, nil, sex)
        return Text(name)
    end
    local id = Number(Read(C_SpecializationInfo.GetInspectSpecialization, unit))
    if not id or id <= 0 then return nil end
    local _, name = Read(GetSpecializationInfoByID, id, sex)
    return Text(name)
end

local function AverageItemLevel(v, unit)
    if v.kind == "character" then
        local _, equipped = Read(GetAverageItemLevel)
        return Number(equipped)
    end
    return Number(Read(C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel, unit))
end

local function UpdateCheckSummary(v)
    local missing, low, empty, unknown = 0, 0, 0, 0
    for _, row in ipairs(v.rows) do
        local info = row.audit
        if info and info.link then
            if info.pending and info.itemID then v.pending[info.itemID] = true end
            for _, gem in ipairs(info.gemInfo) do
                if gem.pending and gem.id then v.pending[gem.id] = true end
            end
            if info.missingEnchant then missing = missing + 1 end
            if info.lowEnchant then low = low + 1 end
            empty = empty + (info.emptySockets or 0)
            if info.unknown then unknown = unknown + 1 end
        end
    end
    v.checkText:SetText(string.format(NS.L.GEAR_CHECK_SUMMARY, missing, low, empty, unknown))
    Color(v.checkText, (missing + empty) > 0 and "danger" or low > 0 and "warning"
        or unknown > 0 and "muted" or "success")
end

function Details.Refresh(v, onlySlot, durabilityOnly)
    if NS.IsCombatLocked() then
        Queue(v)
        return
    end
    if not Enabled(v) then
        v.host:Hide()
        Unregister(v)
        Clear(v)
        return
    end
    Details.StyleChrome(v.root, v.owner)
    if not v.host:IsVisible() then
        v.dirty = true
        return
    end
    if durabilityOnly and v.unit and v.kind == "character" and NeedsData(v) then
        -- No item, tooltip, identity, annotation or summary refresh.
        RefreshDurability(v)
        return
    end
    NS.GearAnnotations.ApplyLayout(v)
    Paint(v)
    Disclosure(v)
    if not NeedsData(v) then
        Unregister(v)
        HideTooltip(v)
        NS.GearAnnotations.Hide(v)
        v.dirty = true
        return
    end
    if not v.registered then
        for _, event in ipairs(events) do v.host:RegisterEvent(event) end
        v.registered = true
    end
    v.dirty = false
    local unit = Unit(v)
    local guid = GUID(unit)
    if not unit or not guid then
        HideTooltip(v)
        Clear(v)
        v.panel:Hide()
        v.toggle:Hide()
        return
    end
    if guid ~= v.guid then
        HideTooltip(v)
        Clear(v)
        onlySlot = nil
    end
    v.unit, v.guid = unit, guid
    local name = Text(Read(UnitName, unit)) or NS.L.DOSSIER_LOADING
    local class = Text(Read(UnitClass, unit)) or ""
    local level = Number(Read(UnitLevel, unit))
    v.level = level
    v.identity:SetText(name)
    v.subtitle:SetText((level and string.format(NS.L.DOSSIER_LEVEL, level) .. " " or "") .. class)
    -- A target swap while an inspect window stays visible is not permission
    -- to reuse the prior inspect cache. Wait for Blizzard's matching ready GUID.
    if v.kind == "inspect" and v.readyGUID ~= guid then return end
    v.specialization:SetText(SpecializationName(v, unit) or "")
    local average = AverageItemLevel(v, unit)
    v.average:SetText(average and average > 0 and string.format("%.1f", average) or "--")
    local loaded, enchantCount, gemCount, lowest, waiting = 0, 0, 0, nil, false
    for id in pairs(v.pending) do v.pending[id] = nil end
    for index, slot in ipairs(slots) do
        local itemLevel, enchanted, gems, durability, pending = ReadRow(v, v.rows[index], slot, onlySlot)
        if itemLevel then loaded = loaded + 1 end
        if enchanted then enchantCount = enchantCount + 1 end
        gemCount = gemCount + (gems or 0)
        if durability then lowest = math.min(lowest or 1, durability) end
        waiting = waiting or pending
    end
    v.summary:SetText(string.format(NS.L.DOSSIER_SUMMARY, loaded, enchantCount, gemCount))
    v.footer:SetText(FooterText(waiting, lowest))
    UpdateCheckSummary(v)
    NS.GearAnnotations.UpdateSummary(v)
end

local function OnShow(v)
    if not Enabled(v) or not v.host:IsVisible() then return end
    if not v.observedVisible then
        v.observedVisible = true
        if v.kind == "inspect" then v.readyGUID = GUID(Unit(v)) end
    end
    if NS.IsCombatLocked() then
        v.panel:Hide()
        v.toggle:Hide()
        Queue(v)
        return
    end
    Details.Refresh(v)
end

local function OnHide(v)
    Unregister(v)
    HideTooltip(v)
    NS.GearAnnotations.Hide(v)
    NS.GearAnnotations.RestoreLayout(v)
    v.observedVisible = false
    v.readyGUID = nil
    v.panel:Hide()
    v.toggle:Hide()
    Clear(v)
end

local function OnEvent(v, event, arg1)
    if not Enabled(v) or not v.host:IsVisible() then return end
    if event == "GET_ITEM_INFO_RECEIVED" and not v.pending[Accessible(arg1)] then return end
    if event == "INSPECT_READY" then
        local guid = GUID(Unit(v))
        if v.kind ~= "inspect" or not guid or Text(Accessible(arg1)) ~= guid then return end
        v.readyGUID = guid
    elseif event == "UNIT_INVENTORY_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        if Text(Accessible(arg1)) ~= Unit(v) then return end
    elseif (event == "PLAYER_EQUIPMENT_CHANGED" or event == "UPDATE_INVENTORY_DURABILITY")
        and v.kind ~= "character" then
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_LEVEL_UP" then
        for _, row in ipairs(v.rows) do NS.EquipmentInfo.Invalidate(row.audit) end
    end
    Details.Refresh(v, event == "PLAYER_EQUIPMENT_CHANGED" and Number(Accessible(arg1)) or nil,
        event == "UPDATE_INVENTORY_DURABILITY")
end

-- Row tooltips: each row button knows its row (frame.dossierRow).
local function OnRowEnter(frame)
    local row = frame.dossierRow
    local v = row.view
    if row.link and v.unit and GameTooltip and GUID(v.unit) == v.guid then
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetInventoryItem(v.unit, row.slot)
        NS.EquipmentInfo.AddTooltip(row.audit)
        GameTooltip:Show()
    end
end

local function OnOwnedLeave(frame)
    if GameTooltip and GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
end

local function OnToggleClick()
    Details.SetOption("expanded", not Config().expanded)
end

local function OnToggleEnter(toggle)
    if not GameTooltip then return end
    GameTooltip:SetOwner(toggle, "ANCHOR_RIGHT")
    GameTooltip:SetText(Config().expanded and NS.L.DOSSIER_COLLAPSE or NS.L.DOSSIER_EXPAND)
    GameTooltip:Show()
end

local function CreateRow(v, panel, index, slot)
    local row = { slot = slot[1], slotName = slot[2], view = v }
    v.rows[index] = row
    v.bySlot[slot[1]] = row
    local frame = CreateFrame("Button", nil, panel)
    row.frame = frame
    frame.dossierRow = row
    frame:SetSize(324, ROW_HEIGHT)
    frame:SetPoint("TOPLEFT", 14, -112 - (index - 1) * ROW_HEIGHT)
    frame:EnableMouse(true)
    NS.Surface.SkinOwnedButton(frame, {
        role = index % 2 == 1 and "card" or "panel", radius = 3, inset = 1, allowImplicitProtected = true,
    })
    row.icon = frame:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(.08, .92, .08, .92)
    row.name = Label(frame, 12, "text")
    row.name:SetPoint("TOPLEFT", 32, -1)
    row.name:SetWidth(236)
    row.meta = Label(frame, 10, "muted")
    row.meta:SetPoint("TOPLEFT", 32, -16)
    row.meta:SetWidth(232)
    row.level = Label(frame, 11, "text")
    row.level:SetPoint("TOPRIGHT", -4, -1)
    row.level:SetJustifyH("RIGHT")
    row.track = Label(frame, 9, "muted")
    row.track:SetPoint("TOPRIGHT", -52, -1)
    row.track:SetJustifyH("RIGHT")
    row.track:SetWidth(46)
    local fonts = v.fonts
    fonts[#fonts + 1] = row.name
    fonts[#fonts + 1] = row.meta
    fonts[#fonts + 1] = row.level
    fonts[#fonts + 1] = row.track
    frame:SetScript("OnEnter", OnRowEnter)
    frame:SetScript("OnLeave", OnOwnedLeave)
end

local function CreateHeader(v, panel)
    v.accent = panel:CreateTexture(nil, "ARTWORK")
    v.accent:SetSize(2, 48)
    v.accent:SetPoint("TOPLEFT", 12, -14)
    v.heading = Label(panel, 10, "accent")
    v.heading:SetPoint("TOPLEFT", 22, -14)
    v.heading:SetText(NS.L.DOSSIER_TITLE)
    v.identity = Label(panel, 16, "title")
    v.identity:SetPoint("TOPLEFT", 22, -32)
    v.identity:SetWidth(210)
    v.subtitle = Label(panel, 11, "muted")
    v.subtitle:SetPoint("TOPLEFT", 22, -54)
    v.subtitle:SetWidth(210)
    v.specialization = Label(panel, 11, "muted")
    v.specialization:SetPoint("TOPLEFT", 22, -70)
    v.specialization:SetWidth(210)
    v.average = Label(panel, 25, "title")
    v.average:SetPoint("TOPRIGHT", -18, -34)
    v.average:SetJustifyH("RIGHT")
    v.averageLabel = Label(panel, 9, "muted")
    v.averageLabel:SetPoint("TOPRIGHT", -18, -63)
    v.averageLabel:SetText(NS.L.DOSSIER_ILVL)
    v.summary = Label(panel, 11, "muted")
    v.summary:SetPoint("TOPLEFT", 14, -88)
    v.summary:SetWidth(324)
    v.footer = Label(panel, 10, "dim")
    v.footer:SetPoint("BOTTOMLEFT", 14, 12)
    v.footer:SetWidth(324)
    v.checkText = Label(panel, 9, "muted")
    v.checkText:SetPoint("BOTTOMLEFT", 14, 28)
    v.checkText:SetWidth(324)
    v.fonts = {
        v.heading, v.identity, v.subtitle, v.specialization, v.average,
        v.averageLabel, v.summary, v.footer, v.checkText,
    }
end

local function CreateToggle(v, host, panel)
    local toggle = CreateFrame("Button", nil, host)
    v.toggle = toggle
    toggle:SetSize(26, 26)
    toggle:SetFrameLevel(panel:GetFrameLevel() + 3)
    v.toggleText = Label(toggle, 18, "text")
    v.toggleText:SetAllPoints()
    v.toggleText:SetJustifyH("CENTER")
    v.fonts[#v.fonts + 1] = v.toggleText
    toggle:SetScript("OnClick", OnToggleClick)
    toggle:SetScript("OnEnter", OnToggleEnter)
    toggle:SetScript("OnLeave", OnOwnedLeave)
end

local function Create(root, parent, kind, owner)
    local v = {
        root = root, kind = kind, owner = owner, rows = {}, bySlot = {}, pending = {}, active = true,
        deferKey = "character-details:" .. kind, actionOwner = "character-details:" .. kind,
    }
    v.deferredRefresh = function()
        if v.active and v.host:IsVisible() then Details.Refresh(v) end
    end
    local host = CreateFrame("Frame", nil, parent)
    v.host = host
    hosts[host] = true
    host:SetSize(1, 1)
    host:SetPoint("TOPLEFT")
    host:EnableMouse(false)
    local panel = CreateFrame("Frame", nil, host)
    v.panel = panel
    panel:SetSize(352, 610)
    panel:SetPoint("TOPLEFT", root, "TOPRIGHT", 8, 0)
    panel:SetClampedToScreen(true)
    panel:SetFrameLevel(root:GetFrameLevel() + 5)
    NS.Surface.Attach(panel, { role = "shell", radius = 8, inset = 0, allowImplicitProtected = true })
    CreateHeader(v, panel)
    for index, slot in ipairs(slots) do CreateRow(v, panel, index, slot) end
    CreateToggle(v, host, panel)
    host:SetScript("OnShow", function() OnShow(v) end)
    host:SetScript("OnHide", function() OnHide(v) end)
    host:SetScript("OnEvent", function(_, event, arg1) OnEvent(v, event, arg1) end)
    return v
end

function Details.Apply(root, kind, owner)
    Details.StyleChrome(root, owner)
    if NS.Client and not NS.Client.modernEquipment then return end
    if NS.IsCombatLocked() or type(GetInventoryItemLink) ~= "function" then return end
    local parent = kind == "character" and _G.PaperDollFrame or _G.InspectPaperDollFrame
    if not root or not parent or not NS.Safety.CanCreateRegions(parent, true) then return end
    local v = Details.views[root]
    if v and v.owner ~= owner and v.active then return end
    if not v then
        local config = Config()
        if kind == "character" and config.view == "classic" then return end
        if not config.enabled and not (kind == "character" and config.view) then return end
        v = Create(root, parent, kind, owner)
        Details.views[root] = v
    end
    v.owner, v.active = owner, true
    if Enabled(v) then
        v.host:Show()
        OnShow(v)
    else
        v.host:Hide()
        Unregister(v)
        NS.GearAnnotations.RestoreLayout(v)
        Clear(v)
    end
end

function Details.Disable(root, owner)
    local v = root and Details.views[root]
    if v and v.owner == owner then
        v.active = false
        NS.CombatGate.Cancel(v.deferKey)
        Unregister(v)
        HideTooltip(v)
        NS.GearAnnotations.Hide(v)
        v.host:Hide()
        Clear(v)
        NS.GearAnnotations.RestoreLayout(v)
        NS.WindowActionSkin.DisableOwner(v.actionOwner)
    end
    if root and root.CloseButton then NS.WindowActionSkin.Disable(root.CloseButton, owner) end
end

function Details.SetOption(key, value)
    if NS.IsCombatLocked() or not OPTION_KEYS[key] or type(value) ~= "boolean" then return false end
    NS.DB.characterDetails[key] = value
    if NS.DB.enabled and NS.DB.skins.blizzardWindows ~= false
        and NS.GenericWindows.IsCategoryEnabled("character") then
        NS.CharacterPanel.Apply("blizzardWindows")
        NS.InspectPanel.Apply("blizzardWindows")
    end
    NS.Registry.NotifyListeners("characterDetails", key)
    return true
end

function Details.SetView(value)
    if NS.IsCombatLocked() or not VIEWS[value] then return false end
    if Config().view == value then return true end
    if type(ReloadUI) ~= "function" then return false end
    Config().view = value
    -- This selector is reload-only: persist first, then let Blizzard rebuild
    -- every native frame before applying the new layout. Do not hot-swap or
    -- notify appearance listeners in the old UI session. Native entry point:
    -- upstream/live, Blizzard_SharedXML/InterfaceUtil.lua (ReloadUI).
    ReloadUI()
    return true
end

NS.Registry.AddListener(Details, function()
    for _, v in pairs(Details.views) do
        if v.active then Details.Refresh(v) end
    end
end)

return Details
