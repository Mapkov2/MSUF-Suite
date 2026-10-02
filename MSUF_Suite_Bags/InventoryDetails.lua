local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Details = { dirty = true, sets = {}, overlays = setmetatable({}, { __mode = "k" }), maps = {} }
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

function Details.Index(index)
    local c = M.config
    if c.groupEquipmentSets or c.showEquipmentSetNames then ReadSets() end
    local keyLevel, keyMap
    if not NS.Client.isForever and c.showKeystoneDetails then
        keyLevel, keyMap = C_MythicPlus.GetOwnedKeystoneLevel(), C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    end
    for i = 1, #index.items do
        local item = index.items[i]
        item.setNames = (c.groupEquipmentSets or c.showEquipmentSetNames)
            and Details.sets[item.bag * KEY + item.slot] or nil
        item.setName = item.setNames and item.setNames[1] or nil
        item.setLabel = item.setNames and item.setNames.label or nil
        if c.showUpgradeTrack and item.equipLoc and item.equipLoc ~= "" then ReadUpgrade(item) end
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

function Details.Hide()
    for _, record in pairs(Details.overlays) do
        record.name:Hide()
        record.upgrade:Hide()
        record.keyLevel:Hide()
        record.keyMap:Hide()
        record.item = nil
    end
    Details.dirty = true
end
