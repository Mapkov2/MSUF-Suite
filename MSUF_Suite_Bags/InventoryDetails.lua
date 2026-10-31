local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Marker, SORT = P.UpgradeMarker, NS.BagsSort
local Details = { dirty = true, sets = {}, overlays = setmetatable({}, { __mode = "k" }),
    markers = setmetatable({}, { __mode = "k" }), maps = {} }
P.InventoryDetails = Details
-- Slot keys of SlotCache.lua: bag * KEY + slot, no string per item.
local KEY = P.SlotCache.KEY

function Details.Invalidate() Details.dirty = true end

local function ReadSets()
    if not Details.dirty then return end
    Details.dirty = false
    for key in pairs(Details.sets) do Details.sets[key] = nil end
    local ids = C_EquipmentSet.GetEquipmentSetIDs()
    table.sort(ids)
    for i = 1, #ids do
        local name = C_EquipmentSet.GetEquipmentSetInfo(ids[i])
        local locations = C_EquipmentSet.GetItemLocations(ids[i])
        if S.Public(name) and type(name) == "string" and S.Public(locations) and type(locations) == "table" then
            for _, location in pairs(locations) do
                if S.Finite(location) and location >= 0 then
                    local data = EquipmentManager_GetLocationData(location)
                    if data.isBags and S.Finite(data.bag) and S.Finite(data.slot) then
                        local key = data.bag * KEY + data.slot
                        local names = Details.sets[key]
                        if not names then
                            names = {}
                            Details.sets[key] = names
                        end
                        local found = false
                        for j = 1, #names do
                            if names[j] == name then
                                found = true
                                break
                            end
                        end
                        if not found then names[#names + 1] = name end
                    end
                end
            end
        end
    end
    for _, names in pairs(Details.sets) do names.label = table.concat(names, " / ") end
end

local function ReadUpgrade(item)
    if item.upgradeRead or not item.link then return end
    local data = C_Item.GetItemUpgradeInfo(item.link)
    if S.Public(data) and type(data) == "table" and S.Finite(data.currentLevel) and S.Finite(data.maxLevel) then
        item.upgrade = tostring(data.currentLevel) .. "/" .. tostring(data.maxLevel)
        item.upgradeTrack = S.Public(data.trackString) and data.trackString or nil
        item.upgradeRead = true
    end
end

local CHARACTER = "[%z\1-\127\194-\244][\128-\191]*"

local function Characters(text, count)
    local out = {}
    for char in text:gmatch(CHARACTER) do
        if #out == count then break end
        out[#out + 1] = char
    end
    return table.concat(out), #out
end

-- A short tag for the owned keystone's dungeon, derived from Blizzard's
-- localized map name: the first three letters of its first word longer than
-- three letters (short articles and particles are passed over); a one-word
-- name in a script without spaces (Chinese, Korean) gives its first two
-- characters. Punctuation is ignored; UTF-8 characters stay whole.
local function MapTag(mapID)
    if Details.maps[mapID] then return Details.maps[mapID] end
    local name = C_ChallengeMode.GetMapUIInfo(mapID)
    if not S.Public(name) or type(name) ~= "string" then return nil end
    local words, chosen, longest, longestLength = 0, nil, nil, 0
    for word in name:gmatch("%S+") do
        word = word:gsub("%p", "")
        local _, length = Characters(word, 64)
        words = words + 1
        if not chosen and length > 3 then chosen = word end
        if length > longestLength then longest, longestLength = word, length end
    end
    local tag
    if words < 2 and name:find("[\128-\255]") then
        tag = Characters((name:gsub("%p", "")), 2)
    else
        tag = Characters(chosen or longest or name, 3)
    end
    Details.maps[mapID] = tag:upper()
    return Details.maps[mapID]
end

-- The effective item level (upgrades and scaling included) replaces the
-- item's base level: a level rule asks for it of every item, sorting and the
-- upgrade marker of equipment only. Asked once per item link.
local function ReadLevel(item)
    local level = C_Item.GetDetailedItemLevelInfo(item.link)
    item.ruleLevel = S.Finite(level) and level or nil
    item.ruleLevelLink = item.ruleLevel and item.link or nil
    item.itemLevel = item.ruleLevel
end

-- Toys are told apart by the toy box, asked once per item link and only while
-- the Collectibles category is on.
local function ReadToys(items)
    for i = 1, #items do
        local item = items[i]
        if item.itemID and item.toyLink ~= item.link then
            item.toy = C_ToyBox.GetToyInfo(item.itemID) ~= nil
            item.toyLink = item.link
        end
    end
end

function Details.Index(index, query)
    local c = M.config
    if Details.ruleText ~= c.customCategories or Details.ruleQuery ~= query then
        local rules = (c.customCategories or ""):lower() .. " " .. (query or ""):lower()
        Details.ruleSets = rules:find("set[:=]") or rules:find("is:set", 1, true)
        Details.ruleLevel = rules:find("level", 1, true)
        Details.ruleText, Details.ruleQuery = c.customCategories, query
    end
    local needsSets = c.groupEquipmentSets or c.showEquipmentSetNames
        or Details.ruleSets
    if needsSets then ReadSets() end
    local ruleLevel, marker, track = Details.ruleLevel, c.showUpgradeMarker, c.showUpgradeTrack
    local gearLevel = ruleLevel or marker or c.sortMode == SORT.ITEM_LEVEL
    if c.category_collectibles then ReadToys(index.items) end
    local keyLevel, keyMap
    if not NS.Client.isForever and c.showKeystoneDetails then
        keyLevel, keyMap = C_MythicPlus.GetOwnedKeystoneLevel(), C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    end
    for i = 1, #index.items do
        local item = index.items[i]
        item.setNames = needsSets
            and Details.sets[item.bag * KEY + item.slot] or nil
        item.setName = item.setNames and item.setNames[1] or nil
        item.setLabel = item.setNames and item.setNames.label or nil
        local equipLoc = item.equipLoc
        if equipLoc and equipLoc ~= "" then
            if gearLevel and item.ruleLevelLink ~= item.link then ReadLevel(item) end
            if marker then Marker.Read(item) end
            if track then ReadUpgrade(item) end
        elseif ruleLevel and item.link and item.ruleLevelLink ~= item.link then
            ReadLevel(item)
        end
        item.keyLevel, item.keyMap = nil, nil
        if not item.bankType and item.itemID and S.Finite(keyLevel) and keyLevel > 0 and S.Finite(keyMap)
            and C_Item.IsItemKeystoneByID(item.itemID) then
            item.keyLevel, item.keyMap = keyLevel, MapTag(keyMap)
        end
    end
end

local function Label(button, point, x, y)
    local label = S.CreateFontString(button, nil, "OVERLAY")
    label:SetPoint(point, x, y)
    label:SetWidth(36)
    label:SetWordWrap(false)
    return label
end

-- Blizzard rebuilds a bag or bank item tooltip every 0.2 s (GameTooltip_OnUpdate
-- calls the button's UpdateTooltip, which runs SetBagItem again), so lines
-- added once on enter vanish. Item tooltip post-calls run on every rebuild.
local function Tooltip(tooltip)
    if not M.active or tooltip ~= GameTooltip then return end
    local record = Details.overlays[tooltip:GetOwner()]
    local item = record and record.item
    if not item then return end
    if item.setName and M.config.showEquipmentSetNames then
        tooltip:AddLine(item.setLabel or item.setName, 0.5, 0.85, 1, true)
    end
    if item.upgrade and M.config.showUpgradeTrack then
        tooltip:AddLine((item.upgradeTrack and item.upgradeTrack .. " " or "") .. item.upgrade, 0.8, 0.8, 0.8)
    end
end
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Tooltip)

-- The arrow Blizzard's bags once drew on equipment that beats what is worn
-- (ContainerFrame.xml UpgradeIcon, atlas bags-greenarrow).
local function PaintMarker(button, shown)
    local marker = Details.markers[button]
    if not marker then
        if not shown then return end
        marker = S.CreateTexture(button, nil, "OVERLAY", nil, 6)
        marker:SetAtlas("bags-greenarrow", true)
        marker:SetPoint("TOPLEFT", 0, 0)
        Details.markers[button] = marker
    end
    if marker.shownNow ~= shown then
        marker.shownNow = shown
        marker:SetShown(shown)
    end
end

local function PaintText(label, value, font, size)
    if not value then
        label:Hide()
        return
    end
    if label.font ~= font or label.size ~= size then
        S.SetFont(label, font, size, "OUTLINE")
        label.font, label.size = font, size
    end
    label:SetText(value)
    label:Show()
end

-- font: the bag font, read once per render (GridView.FontPath).
function Details.Paint(button, item, font)
    local c = M.config
    local name = c.showEquipmentSetNames and (item.setLabel or item.setName)
    local upgrade = c.showUpgradeTrack and item.upgrade
    local keyLevel = c.showKeystoneDetails and item.keyLevel
    if c.showUpgradeMarker then
        local better = item.beatsEquipped == true
        if better or Details.markers[button] then PaintMarker(button, better) end
    end
    local record = Details.overlays[button]
    if not record and not name and not upgrade and not keyLevel then return end
    if not record then
        record = { name = Label(button, "BOTTOM", 0, 1), upgrade = Label(button, "TOPLEFT", 0, -13),
            keyLevel = Label(button, "CENTER", 0, 2), keyMap = Label(button, "BOTTOM", 0, 1) }
        Details.overlays[button] = record
    end
    record.item = item
    PaintText(record.name, name, font, c.equipmentSetNameSize)
    PaintText(record.upgrade, upgrade, font, c.upgradeTextSize)
    PaintText(record.keyLevel, keyLevel and tostring(keyLevel), font, c.keystoneLevelSize)
    PaintText(record.keyMap, keyLevel and item.keyMap, font, c.keystoneDungeonSize)
end

function Details.HideMarkers()
    for _, marker in pairs(Details.markers) do
        marker:Hide()
        marker.shownNow = false
    end
end

function Details.Hide()
    for _, record in pairs(Details.overlays) do
        record.name:Hide()
        record.upgrade:Hide()
        record.keyLevel:Hide()
        record.keyMap:Hide()
        record.item = nil
    end
    Details.HideMarkers()
    Details.dirty = true
end
