local _, NS = ...

-- Optional, exact-owner integration. EnhanceQoL Init.lua / Settings/ItemInventory.lua
-- owns itemSlots, enchant, trackLabel, gems and ItemEnchantDisplay.Apply/Clear.
-- We never change its settings, text, colors, item buttons, scripts or parents.
-- Only the presentation of these verified cosmetic annotations is adjusted.
local Compat = { records = {}, elements = {}, hooks = setmetatable({}, { __mode = "k" }) }
NS.EQoLCharacter = Compat

-- Getters called with valid arguments; secret results read as nil.
local Read = NS.AdapterKit.ReadValues
local Public = NS.Safety.Public
local Dispatch = NS.Safety.Dispatch

local KEY = "character-eqol"
local MAX_POINTS = 4
-- slot id, native slot suffix, annotations grow to the left (right-hand column)
local definitions = {
    { 1, "HeadSlot", false }, { 2, "NeckSlot", false }, { 3, "ShoulderSlot", false },
    { 15, "BackSlot", false }, { 5, "ChestSlot", false }, { 9, "WristSlot", false },
    { 10, "HandsSlot", true }, { 6, "WaistSlot", true }, { 7, "LegsSlot", true },
    { 8, "FeetSlot", true }, { 11, "Finger0Slot", true }, { 12, "Finger1Slot", true },
    { 13, "Trinket0Slot", true }, { 14, "Trinket1Slot", true },
    { 16, "MainHandSlot", true }, { 17, "SecondaryHandSlot", false },
}

local function Enabled()
    return Compat.active and NS.DB.enabled and NS.DB.skins.blizzardWindows ~= false
        and NS.DB.characterDetails.styleEQoL ~= false and NS.GenericWindows.IsCategoryEnabled("character")
end

local function Visible()
    return Read(Compat.host and Compat.host.IsVisible, Compat.host) == true
end

local FontPath = NS.AdapterKit.FontPath

local function SamePoint(region, point)
    if not point or Read(region.GetNumPoints, region) ~= 1 then return false end
    local a, b, c, d, e = Read(region.GetPoint, region, 1)
    return a == point[1] and b == point[2] and c == point[3] and d == point[4] and e == point[5]
end

-- The region's anchors and whether they were all readable. A point with a
-- secret value (its anchor region included) ends the snapshot: it cannot be
-- restored, and nil would silently mean "relative to the parent".
local function SavePoints(region)
    local points = {}
    local count = math.min(Read(region.GetNumPoints, region) or 0, MAX_POINTS)
    for index = 1, count do
        local point, relativeTo, relativePoint, x, y = NS.Safety.Call(region, "GetPoint", index)
        if point == nil or not Public(point) or not Public(relativeTo) or not Public(relativePoint)
            or not Public(x) or not Public(y) then
            return points, false
        end
        points[index] = { point, relativeTo, relativePoint, x, y }
    end
    return points, true
end

-- Restores only values we still own; a newer provider change is kept. An
-- incomplete anchor snapshot keeps our anchor rather than guessing one.
local function Restore(record)
    local region = record.region
    if not NS.Safety.CanDecorate(region, true) then return end
    if record.pointsComplete and SamePoint(region, record.appliedPoint) then
        region:ClearAllPoints()
        for _, point in ipairs(record.points) do region:SetPoint(unpack(point)) end
    end
    if Read(region.GetWidth, region) == record.appliedWidth then region:SetWidth(record.width) end
    if Read(region.GetHeight, region) == record.appliedHeight then region:SetHeight(record.height) end
    if not record.path then return end
    local path, size, flags = Read(region.GetFont, region)
    if path == record.appliedPath and size == record.appliedSize and flags == record.appliedFlags then
        region:SetFont(record.path, record.size, record.flags)
    end
    if record.justify and Read(region.GetJustifyH, region) == record.appliedJustify then
        region:SetJustifyH(record.justify)
    end
    if record.wrap ~= nil and Read(region.CanWordWrap, region) == false then
        region:SetWordWrap(record.wrap)
    end
end

-- Font, justification and word wrap of a provider FontString.
local function LayoutFont(region, record, size, justify)
    local path, oldSize, flags = Read(region.GetFont, region)
    if not path or not oldSize then return end
    if path ~= record.appliedPath or oldSize ~= record.appliedSize or flags ~= record.appliedFlags then
        record.path, record.size, record.flags = path, oldSize, flags or ""
    end
    local desired = FontPath()
    if path ~= desired or oldSize ~= size or flags ~= "" then region:SetFont(desired, size, "") end
    record.appliedPath, record.appliedSize, record.appliedFlags = desired, size, ""
    local current = Read(region.GetJustifyH, region)
    if current ~= record.appliedJustify then record.justify = current end
    if current ~= justify then region:SetJustifyH(justify) end
    record.appliedJustify = justify
    local wrap = Read(region.CanWordWrap, region)
    if record.wrap == nil or wrap == true then record.wrap = wrap end
    if wrap == true then region:SetWordWrap(false) end
end

local function Layout(region, anchor, parent, relative, x, y, width, height, size, justify)
    if not region or not NS.Safety.CanDecorate(region, true) then return end
    local record = Compat.records[region]
    if not record then
        record = { region = region }
        Compat.records[region] = record
    end
    -- An EQoL settings/update pass may have changed its native geometry/font.
    -- Save the incoming provider value, never our own previously applied one.
    if not SamePoint(region, record.appliedPoint) then
        record.points, record.pointsComplete = SavePoints(region)
    end
    local currentWidth, currentHeight = Read(region.GetWidth, region), Read(region.GetHeight, region)
    if currentWidth ~= record.appliedWidth then record.width = currentWidth end
    if currentHeight ~= record.appliedHeight then record.height = currentHeight end
    if not record.appliedPoint then record.appliedPoint = {} end
    local point = record.appliedPoint
    point[1], point[2], point[3], point[4], point[5] = anchor, parent, relative, x, y
    if not SamePoint(region, point) then
        region:ClearAllPoints()
        region:SetPoint(anchor, parent, relative, x, y)
    end
    if width and currentWidth ~= width then region:SetWidth(width) end
    if height and currentHeight ~= height then region:SetHeight(height) end
    record.appliedWidth, record.appliedHeight = width, height
    if size then LayoutFont(region, record, size, justify) end
end

local function ProviderSlot(definition)
    local provider = _G.EnhanceQoL
    local element = provider and provider.variables and provider.variables.itemSlots
        and provider.variables.itemSlots[definition[1]]
    if element and element == _G["Character" .. definition[2]] then return element end
end

-- Fixed, non-overlapping info columns; full item/enchant details stay in the
-- original inventory and EQoL warning/socket tooltips.
local function LayoutElement(element, definition)
    local right = definition[3]
    local wide = NS.GearAnnotations.IsWide()
    if wide and definition[1] == 16 then right = false end
    local anchor, relative = right and "TOPRIGHT" or "TOPLEFT", right and "TOPLEFT" or "TOPRIGHT"
    local direction = right and -1 or 1
    if wide then
        local x = right and -172 or 45
        Layout(element.enchant, "TOPLEFT", element, "TOPLEFT", x + 14, -17, 150, 12, 10, "LEFT")
        Layout(element.trackLabel, "TOPLEFT", element, "TOPLEFT", x + 14, -28, 84, 10, 9, "LEFT")
    else
        local justify = right and "RIGHT" or "LEFT"
        Layout(element.enchant, anchor, element, relative, 6 * direction, -18, 96, 14, 10, justify)
        Layout(element.trackLabel, anchor, element, relative, 48 * direction, -1, 54, 14, 9, justify)
    end
    local gems = element.gems
    if type(gems) == "table" then
        for index = 1, math.min(#gems, wide and 4 or 3) do
            if wide then
                Layout(gems[index], "TOPLEFT", element, "TOPLEFT", (right and -63 or 154) + (index - 1) * 14,
                    -29, 12, 12)
            else
                Layout(gems[index], anchor, element, relative, (6 + (index - 1) * 13) * direction, -1, 12, 12)
            end
        end
    end
    local warning = element.enchantWarningTooltip
    if warning and element.enchant then
        Layout(warning, "CENTER", element.enchant, "CENTER", 0, 0, 100, 16)
    end
end

function Compat.RefreshElement(element)
    if not Enabled() or not Visible() then return end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(KEY, Compat.Refresh)
        return
    end
    local definition = Compat.elements[element]
    if NS.CharacterDetails.GetView() == "list" then
        -- The dossier list shows these annotations; the provider's own copy is hidden.
        if definition then
            NS.CharacterDetails.RefreshEQoL(element, definition[1])
            NS.GearAnnotations.SuppressListProvider(element, definition[1])
        end
        return
    end
    if not definition or ProviderSlot(definition) ~= element then return end
    LayoutElement(element, definition)
    NS.CharacterDetails.RefreshEQoL(element, definition[1])
end

function Compat.Refresh()
    if not Enabled() or not Visible() then return end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(KEY, Compat.Refresh)
        return
    end
    for _, definition in ipairs(definitions) do
        local element = ProviderSlot(definition)
        if element then
            Compat.elements[element] = definition
            Compat.RefreshElement(element)
        end
    end
end

-- Post-hooks on EnhanceQoL's functions: each pass is its own error boundary,
-- so a raising layout never reaches EnhanceQoL's caller.
local function OnDisplayChanged(element)
    Dispatch(Compat.RefreshElement, element)
end

local function OnCharacterFrameSet()
    Dispatch(Compat.Refresh)
end

local function Install()
    local provider = _G.EnhanceQoL
    if not provider then return end
    local display = provider.ItemEnchantDisplay
    if display and not Compat.hooks[display] and type(display.Apply) == "function"
        and type(display.Clear) == "function" then
        -- Apply also calls Clear. Both are bounded to this one equipment slot;
        -- no frame scan, tooltip query, global SetText hook, timer or polling.
        hooksecurefunc(display, "Apply", OnDisplayChanged)
        hooksecurefunc(display, "Clear", OnDisplayChanged)
        Compat.hooks[display] = true
    end
    local funcs = provider.functions
    if funcs and not Compat.hooks[funcs] and type(funcs.setCharFrame) == "function" then
        hooksecurefunc(funcs, "setCharFrame", OnCharacterFrameSet)
        Compat.hooks[funcs] = true
    end
end

local function InstallAndRefresh()
    Install()
    Compat.Refresh()
end

function Compat.IsHost(frame)
    return frame == Compat.host
end

function Compat.Apply(owner)
    local paperDoll = PaperDollFrame
    if NS.IsCombatLocked() or not NS.Safety.CanCreateRegions(paperDoll, true) then return end
    Compat.owner = owner
    if NS.DB.characterDetails.styleEQoL == false or NS.CharacterDetails.GetView() == "classic" then
        Compat.Disable(owner)
        return
    end
    Compat.active = true
    if not Compat.host then
        local host = CreateFrame("Frame", nil, paperDoll)
        Compat.host = host
        host:SetSize(1, 1)
        host:SetPoint("TOPLEFT")
        host:EnableMouse(false)
        host:SetScript("OnShow", InstallAndRefresh)
        host:SetScript("OnHide", function() NS.CombatGate.Cancel(KEY) end)
    end
    if not Compat.waiting then
        Compat.waiting = true
        EventUtil.ContinueOnAddOnLoaded("EnhanceQoL", InstallAndRefresh)
    end
    Install()
    Compat.host:Show()
    Compat.Refresh()
end

function Compat.Disable(owner)
    if Compat.owner ~= owner or NS.IsCombatLocked() then return end
    Compat.active = false
    NS.CombatGate.Cancel(KEY)
    if Compat.host then Compat.host:Hide() end
    for region, record in pairs(Compat.records) do
        Restore(record)
        Compat.records[region] = nil
    end
    for element in pairs(Compat.elements) do Compat.elements[element] = nil end
end

-- Every settings write refreshes the annotations, once per frame.
local function RefreshQueued() Compat.Refresh() end
NS.Registry.AddListener(Compat, function() NS.Registry.QueueJob(RefreshQueued) end)

return Compat
