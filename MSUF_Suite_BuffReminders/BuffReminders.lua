local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local MAX_ENTRIES = 12
local QUESTION_MARK = 134400
-- These spell IDs are already part of MSUF's long-term raid buff presets.
-- The cast spell and observed aura can differ (notably Blessing of the Bronze).
local CLASS_BUFF = {
    DRUID   = { cast=1126,   auras={1126, 432661} },
    MAGE    = { cast=1459,   auras={1459, 432778} },
    PRIEST  = { cast=21562,  auras={21562} },
    SHAMAN  = { cast=462854, auras={462854} },
    WARRIOR = { cast=6673,   auras={6673} },
    EVOKER  = { cast=364342, auras={381732, 381741, 381746, 381748, 381749,
        381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758} },
}
-- Spell IDs are game identifiers. Assassination favors Deadly Poison;
-- Outlaw and Subtlety favor Instant Poison. Any active poison of the same
-- category satisfies the reminder, including a player's talent choice.
local LETHAL_POISONS = { 2823, 315584, 381664, 8679 }
local ASSASSINATION_LETHAL_POISONS = { 2823, 381664, 315584, 8679 }
local OTHER_LETHAL_POISONS = { 315584, 8679, 2823, 381664 }
local NONLETHAL_POISONS = { 381637, 5761, 3408 }
-- Curated current-season item IDs. These are identifiers, not EUI source or logic.
-- Selection runs only on configuration/bag/equipment events, never on a timer.
local FLASKS = {
    241324, 241325, 245931, 245930, 241322, 241323, 245933, 245932,
    241326, 241327, 245929, 245928, 241320, 241321, 245926, 245927,
}
local FLASK_AURAS = { 1235110, 1235108, 1235111, 1235057 }
local FOODS = {
    242275, 255847, 255848, 242274, 242285, 242284,
    242272, 242273, 242744, 242745, 242746, 242747,
}
local RUNES = { 259085, 243191 }
local RUNE_AURAS = { 1264426, 453250, 1234969, 1242347, 393438, 347901 }
local OILS = { 243733, 243734, 243735, 243736, 243737, 243738 }
local OIL_WEAPON_LOCATIONS = {
    INVTYPE_WEAPON=true, INVTYPE_2HWEAPON=true,
    INVTYPE_WEAPONMAINHAND=true, INVTYPE_WEAPONOFFHAND=true,
}
local FOOD_ICONS = { [136000]=true, [133950]=true }
local ANCHORS = { "CENTER", "TOP" }
local itemCountAPI = (_G.C_Item and _G.C_Item.GetItemCount) or _G.GetItemCount

local function ID(value)
    local id = tonumber(value)
    if id and id > 0 and id < 10000000 and id == math.floor(id) then return id end
end

local function Known(spellID)
    local first = _G.IsPlayerSpell
    if type(first) == "function" then
        local result = first(spellID)
        if S.Public(result) and result == true then return true end
    end
    local second = _G.IsSpellKnown
    if type(second) == "function" then
        local result = second(spellID)
        if S.Public(result) and result == true then return true end
    end
    return false
end

local function ItemCount(itemID)
    if type(itemCountAPI) ~= "function" then return nil end
    local count = itemCountAPI(itemID)
    if S.Public(count) and type(count) == "number" then return count end
end

local function FirstStocked(items)
    for index = 1, #items do
        local itemID = items[index]
        local count = ItemCount(itemID)
        if count and count > 0 then return itemID end
    end
end

local function OilWeaponEquipped(slot)
    local getID = _G.GetInventoryItemID
    local getInfo = _G.C_Item and _G.C_Item.GetItemInfoInstant
    if type(getID) ~= "function" or type(getInfo) ~= "function" then return false end
    local ok, itemID = pcall(getID, "player", slot)
    if not ok or not S.Public(itemID) or type(itemID) ~= "number" then return false end
    local infoOK, _, _, _, location, _, classID = pcall(getInfo, itemID)
    if not infoOK or not S.Public(location) or not S.Public(classID) then return false end
    -- ItemClass.Weapon is 2; a shield, held item or ranged weapon is not an oil target.
    return classID == 2 and OIL_WEAPON_LOCATIONS[location] == true
end

local function OwnWeaponImbueKnown()
    if type(_G.UnitClass) ~= "function" then return true end
    local _, class = UnitClass("player")
    if not S.Public(class) or type(class) ~= "string" then return true end
    if class == "SHAMAN" then
        return Known(382021) or Known(318038) or Known(33757)
    end
    if class == "PALADIN" then return Known(433583) or Known(433568) end
    return false
end

local function Texture(kind, id)
    local value
    if kind == "spell" then
        local fn = _G.C_Spell and _G.C_Spell.GetSpellTexture or _G.GetSpellTexture
        if type(fn) == "function" then value = fn(id) end
    else
        local fn = _G.C_Item and _G.C_Item.GetItemIconByID or _G.GetItemIcon
        if type(fn) == "function" then value = fn(id) end
    end
    return S.Public(value) and value or QUESTION_MARK
end

local function AuraExpiry(data)
    local expiration, duration = data.expirationTime, data.duration
    if S.Public(expiration) and S.Public(duration)
        and type(expiration) == "number" and type(duration) == "number"
        and expiration > 0 and duration > 0 and expiration < math.huge then return expiration end
end

local function PublicAuraSnapshot(data)
    local instanceID = data.auraInstanceID
    if not S.Public(instanceID) or type(instanceID) ~= "number" then instanceID = nil end
    local expiration = AuraExpiry(data)
    return { auraInstanceID=instanceID, expirationTime=expiration,
        duration=expiration and data.duration or nil }
end

local function AuraPresent(entry, scan)
    local ids = entry.aliases
    local count = ids and #ids or 1
    local unknown = false
    for index = 1, count do
        local id = ids and ids[index] or entry.aura
        local data
        if scan then
            data = scan[id]
        else
            local ok
            ok, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if not ok or not S.Public(data) then unknown = true
                data = nil
            end
        end
        if data then
            local instanceID = data.auraInstanceID
            if not S.Public(instanceID) or type(instanceID) ~= "number" then instanceID = nil end
            local expiration = scan and data.expirationTime or AuraExpiry(data)
            return true, instanceID, expiration, nil, expiration and data.duration or nil
        end
    end
    if unknown then return nil end
    return false
end

local function MatchesAuraID(entry, spellID)
    local aliases = entry.aliases
    if not aliases then return entry.aura == spellID end
    for index = 1, #aliases do
        if aliases[index] == spellID then return true end
    end
    return false
end

local function AuraChangeAffects(entry, info)
    if not S.Public(info) or type(info) ~= "table" then return true end
    local full = info.isFullUpdate
    if not S.Public(full) or full then return true end
    if entry.present == nil then return true end
    local added = info.addedAuras
    if not S.Public(added) or (added ~= nil and type(added) ~= "table") then return true end
    if added then
        for _, aura in ipairs(added) do
            if not S.Public(aura) then return true end
            local spellID = aura.spellId
            if not S.Public(spellID) or type(spellID) ~= "number"
                or MatchesAuraID(entry, spellID) then return true end
        end
    end
    if entry.present == false then return false end
    local instanceID = entry.auraInstanceID
    if not instanceID then return true end
    local removed = info.removedAuraInstanceIDs
    if not S.Public(removed) or (removed ~= nil and type(removed) ~= "table") then return true end
    if removed then
        for _, removedID in ipairs(removed) do
            if not S.Public(removedID) or type(removedID) ~= "number"
                or removedID == instanceID or (entry.instanceIDs and entry.instanceIDs[removedID]) then return true end
        end
    end
    local updated = info.updatedAuraInstanceIDs
    if not S.Public(updated) or (updated ~= nil and type(updated) ~= "table") then return true end
    if updated then
        for _, updatedID in ipairs(updated) do
            if not S.Public(updatedID) or type(updatedID) ~= "number"
                or updatedID == instanceID or (entry.instanceIDs and entry.instanceIDs[updatedID]) then return true end
        end
    end
    return false
end

local function ScanAuras(self)
    local get = C_UnitAuras.GetAuraDataByIndex
    if type(get) ~= "function" then return nil, false end
    local found = self.auraScratch
    local wanted = self.auraWanted
    for id in pairs(found) do found[id] = nil end
    for index = 1, 255 do
        local ok, data = pcall(get, "player", index, "HELPFUL")
        if not ok or not S.Public(data) then return nil, false end
        if data == nil then break end
        local spellID = data.spellId
        if not S.Public(spellID) then return nil, false end
        if type(spellID) == "number" and wanted[spellID] then
            found[spellID] = PublicAuraSnapshot(data)
        end
        if index == 255 then return nil, false end
    end
    return found, true
end

local function ScanFood(self)
    local get = C_UnitAuras.GetAuraDataByIndex
    if type(get) ~= "function" then self.foodKnown = false; return end
    local ids = self.foodIDs
    for id in pairs(ids) do ids[id] = nil end
    for index = 1, 255 do
        local ok, data = pcall(get, "player", index, "HELPFUL")
        if not ok or not S.Public(data) then self.foodKnown = false; return end
        if data == nil then self.foodKnown = true; return end
        local icon, instanceID = data.icon, data.auraInstanceID
        if not S.Public(icon) or not S.Public(instanceID) then self.foodKnown = false; return end
        if type(icon) == "number" and FOOD_ICONS[icon]
            and (instanceID == nil or type(instanceID) == "number") then
            ids[instanceID or index] = PublicAuraSnapshot(data)
        end
    end
    self.foodKnown = false
end

local function FoodDelta(self, info)
    if not self.hasFood then return false end
    if not S.Public(info) then self.foodKnown = false; return true end
    if info == nil then self.foodKnown = nil; return true end
    if type(info) ~= "table" or not S.Public(info.isFullUpdate) then
        self.foodKnown = false
        return true
    end
    if info.isFullUpdate then
        self.foodKnown = nil
        return true
    end
    if self.foodKnown ~= true then return false end
    local ids = self.foodIDs
    local changed = false
    local removed = info.removedAuraInstanceIDs
    if not S.Public(removed) or (removed ~= nil and type(removed) ~= "table") then
        self.foodKnown = false; return true
    end
    if removed then
        for _, id in ipairs(removed) do
            if not S.Public(id) then self.foodKnown = false; return true end
            if ids[id] then changed = true end
            ids[id] = nil
        end
    end
    local added = info.addedAuras
    if not S.Public(added) or (added ~= nil and type(added) ~= "table") then
        self.foodKnown = false; return true
    end
    if added then
        for _, aura in ipairs(added) do
            if not S.Public(aura) or not S.Public(aura.icon) or not S.Public(aura.auraInstanceID) then
                self.foodKnown = false; return true
            end
            if type(aura.icon) == "number" and type(aura.auraInstanceID) == "number"
                and FOOD_ICONS[aura.icon] then
                ids[aura.auraInstanceID] = PublicAuraSnapshot(aura)
                changed = true
            end
        end
    end
    local updated = info.updatedAuraInstanceIDs
    if not S.Public(updated) or (updated ~= nil and type(updated) ~= "table") then
        self.foodKnown = false; return true
    end
    if updated then
        for _, id in ipairs(updated) do
            if not S.Public(id) then self.foodKnown = false; return true end
            if ids[id] then self.foodKnown = nil; return true end
        end
    end
    return changed
end

local function FoodPresent(self)
    if self.foodKnown == nil then ScanFood(self) end
    if not self.foodKnown then return nil end
    local present, expiresAt, totalDuration = false, nil, nil
    for _, aura in pairs(self.foodIDs) do
        present = true
        local expiration = aura.expirationTime
        if expiration and (not expiresAt or expiration > expiresAt) then
            expiresAt, totalDuration = expiration, aura.duration
        end
    end
    return present, expiresAt, totalDuration
end

local function EnchantPresent(slot)
    local paperDoll = _G.C_PaperDollInfo
    if paperDoll and type(paperDoll.GetTemporaryEnchantmentInfo) == "function" then
        local ok, data = pcall(paperDoll.GetTemporaryEnchantmentInfo, slot)
        if not ok or not S.Public(data) then return nil end
        if data == nil then return false end
        local remaining, timed = data.remainingTimeMs, data.hasExpirationTime
        if S.Public(remaining) and S.Public(timed) and timed == true
            and type(remaining) == "number" and remaining > 0 and remaining < math.huge
            and type(_G.GetTime) == "function" then return true, GetTime() + remaining / 1000 end
        return true
    end
    if type(_G.GetWeaponEnchantInfo) == "function" then
        local ok, main, mainRemaining, _, _, off, offRemaining = pcall(GetWeaponEnchantInfo)
        if not ok then return nil end
        local value, remaining
        if slot == 16 then value, remaining = main, mainRemaining else value, remaining = off, offRemaining end
        if not S.Public(value) then return nil end
        if value ~= true then return false end
        if S.Public(remaining) and type(remaining) == "number" and remaining > 0
            and remaining < math.huge and type(_G.GetTime) == "function" then
            return true, GetTime() + remaining / 1000
        end
        return true
    end
end

local function ReadInstance(self)
    if type(_G.GetInstanceInfo) ~= "function" then self.instanceType = nil; return end
    local _, instanceType = GetInstanceInfo()
    self.instanceType = S.Public(instanceType) and instanceType or false
end

local function Allowed(self)
    if type(_G.UnitIsDeadOrGhost) == "function" then
        local dead = UnitIsDeadOrGhost("player")
        if not S.Public(dead) or dead == true then return false end
    end
    if type(_G.UnitInVehicle) == "function" then
        local vehicle = UnitInVehicle("player")
        if not S.Public(vehicle) or vehicle == true then return false end
    end
    if self.config.hideMounted and type(_G.IsMounted) == "function" then
        local mounted = IsMounted()
        if not S.Public(mounted) or mounted == true then return false end
    end
    local instanceType = self.instanceType
    if instanceType == false or instanceType == "arena" or instanceType == "pvp" then return false end
    if self.config.instancesOnly and instanceType ~= "party" and instanceType ~= "raid" then return false end
    return true
end

local function CancelThreshold(self)
    if self.thresholdTimer and type(self.thresholdTimer.Cancel) == "function" then
        self.thresholdTimer:Cancel()
    end
    self.thresholdTimer, self.thresholdAt = nil, nil
end

local function ScheduleThreshold(self, due, now)
    if self.thresholdAt == due then return end
    CancelThreshold(self)
    if not due or not _G.C_Timer or type(C_Timer.NewTimer) ~= "function" then return end
    local timer
    timer = C_Timer.NewTimer(math.max(0.05, due - now), function()
        if self.thresholdTimer ~= timer or not self.active then return end
        self.thresholdTimer, self.thresholdAt = nil, nil
        if not NS.IsCombatLocked() then self:Update("visual") end
    end)
    self.thresholdTimer, self.thresholdAt = timer, due
end

local function Tooltip(button)
    local entry = button.entry
    if not entry or not _G.GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if entry.kind == "spell" and type(GameTooltip.SetSpellByID) == "function" then
        GameTooltip:SetSpellByID(entry.actionID or entry.id)
    elseif entry.kind ~= "spell" and type(GameTooltip.SetItemByID) == "function" then
        GameTooltip:SetItemByID(entry.id)
    end
    GameTooltip:Show()
end

local function MakeButton(self, index)
    local button = CreateFrame("Button", nil, self.host, "SecureActionButtonTemplate")
    button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(.08, .92, .08, .92)
    button.border = button:CreateTexture(nil, "BACKGROUND")
    button.border:SetAllPoints(button)
    button.border:SetColorTexture(1, .72, .34, 1)
    button.count = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    button:Hide()
    self.buttons[index] = button
    return button
end

local function Add(entries, seen, kind, itemID, auraID, slot, aliases, poison, poisonRank, candidates)
    if #entries >= MAX_ENTRIES or not itemID then return end
    local key
    if poison then key = "poison:" .. poison .. ":" .. poisonRank
    elseif slot then key = "weapon:" .. slot
    elseif kind == "food" then key = "food"
    else key = "aura:" .. auraID end
    if seen[key] then return end
    if aliases and not (poison and poisonRank > 1) then
        for _, id in ipairs(aliases) do if seen["aura:" .. id] then return end end
    end
    seen[key] = true
    if aliases and not (poison and poisonRank > 1) then
        for _, id in ipairs(aliases) do seen["aura:" .. id] = true end
    end
    entries[#entries + 1] = { kind=kind, id=itemID, aura=auraID, slot=slot,
        aliases=aliases, poison=poison, poisonRank=poisonRank, candidates=candidates }
end

local function SameEntries(left, right)
    if not left or #left ~= #right then return false end
    for index = 1, #right do
        local a, b = left[index], right[index]
        if a.kind ~= b.kind or a.id ~= b.id or a.aura ~= b.aura
            or a.slot ~= b.slot or a.aliases ~= b.aliases or a.poison ~= b.poison
            or a.poisonRank ~= b.poisonRank then return false end
        if a.candidates or b.candidates then
            if not a.candidates or not b.candidates or #a.candidates ~= #b.candidates then return false end
            for offset = 1, #a.candidates do
                if a.candidates[offset] ~= b.candidates[offset] then return false end
            end
        end
    end
    return true
end

function M:Compile()
    if NS.IsCombatLocked() then return end
    local entries, seen = {}, {}
    local c = self.config
    local class
    if type(_G.UnitClass) == "function" then
        local _, value = UnitClass("player")
        if S.Public(value) then class = value end
    end
    if c.classBuff then
        local buff = CLASS_BUFF[class]
        if buff and Known(buff.cast) then Add(entries, seen, "spell", buff.cast, buff.auras[1], nil, buff.auras) end
    end
    if NS.Client.modernEquipment and c.autoRoguePoisons and class == "ROGUE"
        and type(_G.GetSpecialization) == "function" and type(_G.GetSpecializationInfo) == "function" then
        local specIndex = GetSpecialization()
        if S.Public(specIndex) and type(specIndex) == "number" and specIndex > 0 then
            local specID = GetSpecializationInfo(specIndex)
            if S.Public(specID) and (specID == 259 or specID == 260 or specID == 261) then
                local twoPerCategory = specID == 259 and Known(381801)
                local groups = {
                    { name="lethal", aliases=LETHAL_POISONS,
                        priority=specID == 259 and ASSASSINATION_LETHAL_POISONS or OTHER_LETHAL_POISONS },
                    { name="nonlethal", aliases=NONLETHAL_POISONS, priority=NONLETHAL_POISONS },
                }
                for _, group in ipairs(groups) do
                    local candidates = {}
                    for _, spellID in ipairs(group.priority) do
                        if Known(spellID) then candidates[#candidates + 1] = spellID end
                    end
                    local required = twoPerCategory and math.min(2, #candidates) or math.min(1, #candidates)
                    for rank = 1, required do
                        Add(entries, seen, "spell", candidates[rank], candidates[rank], nil,
                            group.aliases, group.name, rank, candidates)
                    end
                end
            end
        end
    end
    for token in c.spellIDs:gmatch("%d+") do
        if #entries >= MAX_ENTRIES then break end
        local spellID = ID(token)
        if spellID then Add(entries, seen, "spell", spellID, spellID) end
    end
    for token in c.items:gmatch("[^,%s]+") do
        if #entries >= MAX_ENTRIES then break end
        local item, aura = token:match("^(%d+):(%d+)$")
        local itemID, auraID = ID(item), ID(aura)
        if itemID and auraID then Add(entries, seen, "item", itemID, auraID) end
    end
    local mainID, offID = ID(c.mainHandItem), ID(c.offHandItem)
    if mainID then Add(entries, seen, "weapon", mainID, nil, 16) end
    if offID then Add(entries, seen, "weapon", offID, nil, 17) end
    if NS.Client.modernEquipment then
        if c.autoFlask and #entries < MAX_ENTRIES then
            local itemID = FirstStocked(FLASKS)
            if itemID then Add(entries, seen, "item", itemID, FLASK_AURAS[1], nil, FLASK_AURAS) end
        end
        if c.autoFood and #entries < MAX_ENTRIES then
            local itemID = FirstStocked(FOODS)
            if itemID then Add(entries, seen, "food", itemID) end
        end
        if c.autoRune and #entries < MAX_ENTRIES then
            local itemID = FirstStocked(RUNES)
            if itemID then Add(entries, seen, "item", itemID, RUNE_AURAS[1], nil, RUNE_AURAS) end
        end
        if c.autoWeapon and #entries < MAX_ENTRIES and (not mainID or not offID) then
            local itemID = FirstStocked(OILS)
            if itemID and not OwnWeaponImbueKnown() then
                if not mainID and OilWeaponEquipped(16) then
                    Add(entries, seen, "weapon", itemID, nil, 16)
                end
                if #entries < MAX_ENTRIES and not offID and OilWeaponEquipped(17) then
                    Add(entries, seen, "weapon", itemID, nil, 17)
                end
            end
        end
    end
    local entriesChanged = not SameEntries(self.entries, entries)
    if entriesChanged then
        self.entries, self.mask = entries, nil
        self.needsFullRefresh, self.countsDirty = true, true
    else
        entries = self.entries
    end
    local layout = self.layout
    local anchorChanged = not layout or layout.point ~= c.point or layout.x ~= c.x or layout.y ~= c.y
    local geometryChanged = not layout or layout.size ~= c.size or layout.spacing ~= c.spacing
        or layout.columns ~= c.columns
    local colorChanged = not layout or layout.borderColor ~= c.borderColor
    local layoutChanged = anchorChanged or geometryChanged or colorChanged
    if not entriesChanged and not layoutChanged then return false end
    if layoutChanged then
        layout = layout or {}
        layout.point, layout.x, layout.y = c.point, c.x, c.y
        layout.size, layout.spacing, layout.columns = c.size, c.spacing, c.columns
        layout.borderColor = c.borderColor
        self.layout = layout
        if geometryChanged then self.mask = nil end
    end
    if entriesChanged then
        local hasAura, hasWeapon, hasFood = false, false, false
        local wanted = self.auraWanted
        self.poisonStates = {}
        for id in pairs(wanted) do wanted[id] = nil end
        for index, entry in ipairs(entries) do
            entry.bit = 2 ^ (index - 1)
            if entry.slot then hasWeapon = true
            elseif entry.kind == "food" then hasFood = true
            else
                hasAura = true
                if entry.poison then
                    local state = self.poisonStates[entry.poison]
                    if not state then
                        state = { aliases=entry.aliases, candidates=entry.candidates,
                            active={}, instanceIDs={}, warnings={}, required=0 }
                        self.poisonStates[entry.poison] = state
                    end
                    state.required = state.required + 1
                end
                if entry.aliases then
                    for _, id in ipairs(entry.aliases) do wanted[id] = true end
                else wanted[entry.aura] = true end
            end
        end
        self.hasAura, self.hasFood = hasAura, hasFood
        if (hasAura or hasFood) and not self.auraListening then
            self.frame:RegisterUnitEvent("UNIT_AURA", "player")
            self.auraListening = true
        elseif not hasAura and not hasFood and self.auraListening then
            self.frame:UnregisterEvent("UNIT_AURA")
            self.auraListening = false
        end
        if hasWeapon and not self.weaponListening then
            self.frame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
            if NS.Client.SupportsEvent("WEAPON_ENCHANT_CHANGED") then
                self.frame:RegisterEvent("WEAPON_ENCHANT_CHANGED")
            end
            if NS.Client.SupportsEvent("WEAPON_SLOT_CHANGED") then
                self.frame:RegisterEvent("WEAPON_SLOT_CHANGED")
            end
            self.weaponListening = true
        elseif not hasWeapon and self.weaponListening then
            self.frame:UnregisterEvent("UNIT_INVENTORY_CHANGED")
            self.frame:UnregisterEvent("WEAPON_ENCHANT_CHANGED")
            self.frame:UnregisterEvent("WEAPON_SLOT_CHANGED")
            self.weaponListening = false
        end
    end
    local size, spacing, columns = c.size, c.spacing, c.columns
    if anchorChanged then
        self.host:ClearAllPoints()
        local point = ANCHORS[c.point] or "CENTER"
        self.host:SetPoint(point, UIParent, point, c.x, c.y)
    end
    if entriesChanged or geometryChanged then
        local displayColumns = math.min(columns, math.max(1, #entries))
        local rows = math.max(1, math.ceil(#entries / columns))
        self.host:SetSize(displayColumns * size + (displayColumns - 1) * spacing,
            rows * size + (rows - 1) * spacing)
    end
    if entriesChanged or geometryChanged or colorChanged then
        local r = tonumber(c.borderColor:sub(1, 2), 16) / 255
        local g = tonumber(c.borderColor:sub(3, 4), 16) / 255
        local b = tonumber(c.borderColor:sub(5, 6), 16) / 255
        for index = 1, math.max(#entries, #self.buttons) do
            local button = self.buttons[index] or MakeButton(self, index)
            local entry = entries[index]
            if entriesChanged then
                button.entry = entry
                button:Hide()
            end
            if entry then
                if entriesChanged then
                    local action = entry.kind == "spell" and "spell" or "item"
                    button:SetAttribute("type1", action)
                    button:SetAttribute("spell1", action == "spell" and entry.id or nil)
                    button:SetAttribute("item1", action == "item" and ("item:" .. entry.id) or nil)
                    button:SetAttribute("target-slot", entry.slot)
                    button:SetAttribute("unit", "player")
                    button.icon:SetTexture(Texture(action, entry.id))
                    entry.actionID = entry.id
                    button.count:SetText("")
                end
                if entriesChanged or colorChanged then button.border:SetColorTexture(r, g, b, 1) end
                if entriesChanged or geometryChanged then button:SetSize(size, size) end
            end
        end
    end
    return entriesChanged
end

local function PoisonLatestFirst(left, right)
    return (left.expiresAt or math.huge) > (right.expiresAt or math.huge)
end

local function ReadPoisonState(state, scan, directAura)
    local active, instanceIDs = state.active, state.instanceIDs
    for id in pairs(instanceIDs) do instanceIDs[id] = nil end
    local count, unknown = 0, false
    state.auraInstanceID = nil
    for _, spellID in ipairs(state.aliases) do
        local data
        if directAura then
            local ok
            ok, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
            if not ok or not S.Public(data) then unknown = true; data = nil end
        elseif scan then
            data = scan[spellID]
        else
            unknown = true
        end
        if data then
            count = count + 1
            local record = active[count] or {}
            active[count] = record
            record.spellID = spellID
            if directAura then
                record.expiresAt = AuraExpiry(data)
                record.duration = record.expiresAt and data.duration or nil
            else
                record.expiresAt, record.duration = data.expirationTime, data.duration
            end
            local instanceID = data.auraInstanceID
            if S.Public(instanceID) and type(instanceID) == "number" then
                instanceIDs[instanceID] = true
                state.auraInstanceID = instanceID
            end
        end
    end
    for index = count + 1, #active do active[index] = nil end
    if count > 1 then table.sort(active, PoisonLatestFirst) end
    if unknown then state.present = nil else state.present = count > 0 end
    state.unknown = unknown
end

local function BuildPoisonWarnings(state, now, threshold)
    local active, warnings = state.active, state.warnings
    for index = #warnings, 1, -1 do warnings[index] = nil end
    if state.unknown then return end
    local missing = math.max(0, state.required - #active)
    for _, candidate in ipairs(state.candidates) do
        if #warnings >= missing then break end
        local inUse = false
        for _, aura in ipairs(active) do
            if aura.spellID == candidate then inUse = true; break end
        end
        if not inUse then warnings[#warnings + 1] = candidate end
    end
    local nextDue
    if now and threshold > 0 then
        for index = 1, math.min(state.required, #active) do
            local aura = active[index]
            if aura.expiresAt and aura.duration and aura.duration > threshold then
                local due = aura.expiresAt - threshold
                if due <= now then warnings[#warnings + 1] = aura.spellID
                elseif not nextDue or due < nextDue then nextDue = due end
            end
        end
    end
    return nextDue
end

function M:Update(mode, updateCounts, updateInfo, foodDirty)
    if NS.IsCombatLocked() then return end
    local mask = 0
    local now = type(_G.GetTime) == "function" and GetTime() or nil
    if not S.Public(now) or type(now) ~= "number" then now = nil end
    local minutes = tonumber(self.config.remindBeforeMinutes) or 0
    local threshold = math.max(0, minutes) * 60
    local nextDue
    if Allowed(self) then
        local fullRefresh = self.needsFullRefresh or mode == "all"
        local auraDirty = fullRefresh or mode == "aura"
        local weaponDirty = fullRefresh or mode == "weapon"
        local directAura = type(C_UnitAuras.GetPlayerAuraBySpellID) == "function"
        local scan, usable
        if auraDirty and self.hasAura then
            if directAura then usable = true else scan, usable = ScanAuras(self) end
        end
        for _, state in pairs(self.poisonStates) do
            if auraDirty and (fullRefresh or not directAura or AuraChangeAffects(state, updateInfo)) then
                ReadPoisonState(state, usable and scan or nil, directAura and usable)
            end
            local due = BuildPoisonWarnings(state, now, threshold)
            if due and (not nextDue or due < nextDue) then nextDue = due end
        end
        for index, entry in ipairs(self.entries) do
            if entry.poison then
                local state = self.poisonStates[entry.poison]
                local spellID = state.warnings[entry.poisonRank]
                entry.present, entry.expiresAt = spellID == nil, nil
                if state.unknown then entry.present = nil end
                local actionID = spellID or entry.id
                if entry.actionID ~= actionID then
                    entry.actionID = actionID
                    self.buttons[index]:SetAttribute("spell1", actionID)
                    self.buttons[index].icon:SetTexture(Texture("spell", actionID))
                end
            elseif entry.slot then
                if weaponDirty then entry.present, entry.expiresAt = EnchantPresent(entry.slot) end
            elseif auraDirty then
                if entry.kind == "food" then
                    if fullRefresh or foodDirty then
                        entry.present, entry.expiresAt, entry.totalDuration = FoodPresent(self)
                    end
                elseif not usable then
                    entry.present, entry.auraInstanceID, entry.expiresAt,
                        entry.instanceIDs, entry.totalDuration = nil, nil, nil, nil, nil
                elseif fullRefresh or not directAura or AuraChangeAffects(entry, updateInfo) then
                    entry.present, entry.auraInstanceID, entry.expiresAt,
                        entry.instanceIDs, entry.totalDuration = AuraPresent(entry, scan)
                end
            end
            if entry.present == false then
                mask = mask + entry.bit
            elseif entry.present == true and threshold > 0 and now and entry.expiresAt
                and (not entry.totalDuration or entry.totalDuration > threshold) then
                local due = entry.expiresAt - threshold
                if due <= now then mask = mask + entry.bit
                elseif not nextDue or due < nextDue then nextDue = due end
            end
        end
        self.needsFullRefresh = false
    else
        self.needsFullRefresh = true
    end
    ScheduleThreshold(self, nextDue, now)
    local changed = self.mask ~= mask
    if changed then
        self.mask = mask
        local shown, columns, size, spacing = 0, self.config.columns, self.config.size, self.config.spacing
        for index, button in ipairs(self.buttons) do
            local bit = self.entries[index] and self.entries[index].bit or 2 ^ (index - 1)
            local visible = mask % (bit * 2) >= bit
            if visible then
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", self.host, "TOPLEFT", (shown % columns) * (size + spacing),
                    -math.floor(shown / columns) * (size + spacing))
                button:Show()
                shown = shown + 1
            else
                button:Hide()
            end
        end
    end
    if self.countsDirty or updateCounts then
        for index, entry in ipairs(self.entries) do
            if entry.kind ~= "spell" then
                local count = ItemCount(entry.id)
                if count ~= entry.count then
                    entry.count = count
                    self.buttons[index].count:SetText(count and tostring(count) or "")
                end
            end
        end
        self.countsDirty = false
    end
    local previewShown = S.editMode == true and mask == 0
    if self.previewShown ~= previewShown then
        self.preview:SetShown(previewShown)
        self.previewShown = previewShown
    end
end

local function OnEvent(frame, event, unit, updateInfo)
    local self = frame.owner
    if not self.active then return end
    if (event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED"
        or event == "PLAYER_SPECIALIZATION_CHANGED") and unit ~= "player" then return end
    if NS.IsCombatLocked() then return end
    local foodDirty = event == "UNIT_AURA" and FoodDelta(self, updateInfo)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA"
        or event == "PLAYER_REGEN_ENABLED" then
        ReadInstance(self)
        self.foodKnown = nil
    end
    if event == "SPELLS_CHANGED" or event == "PLAYER_REGEN_ENABLED"
        or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "BAG_UPDATE_DELAYED"
        or event == "PLAYER_EQUIPMENT_CHANGED" or event == "WEAPON_SLOT_CHANGED" then self:Compile() end
    local mode = "visual"
    if event == "UNIT_AURA" then mode = "aura"
    elseif event == "UNIT_INVENTORY_CHANGED" or event == "WEAPON_ENCHANT_CHANGED"
        or event == "WEAPON_SLOT_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then mode = "weapon"
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA"
        or event == "PLAYER_REGEN_ENABLED" or event == "SPELLS_CHANGED"
        or event == "PLAYER_SPECIALIZATION_CHANGED" then mode = "all" end
    self:Update(mode, event == "BAG_UPDATE_DELAYED", updateInfo, foodDirty)
end

function M:Enable()
    if not self.host then
        self.host = CreateFrame("Frame", nil, UIParent, "SecureFrameTemplate")
        self.buttons, self.auraScratch, self.auraWanted, self.foodIDs = {}, {}, {}, {}
        self.preview = self.host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        self.preview:SetPoint("CENTER", self.host, "CENTER")
        self.preview:SetText("Buff reminders")
        self.frame = CreateFrame("Frame")
        self.frame.owner = self
        self.frame:SetScript("OnEvent", OnEvent)
    end
    self.host:Show()
    self.foodKnown = nil
    RegisterStateDriver(self.host, "visibility", "[combat] hide; show")
    ReadInstance(self)
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
        "PLAYER_SPECIALIZATION_CHANGED", "ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED",
        "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ALIVE", "PLAYER_DEAD", "PLAYER_UNGHOST",
        "PLAYER_MOUNT_DISPLAY_CHANGED" }) do
        if NS.Client.SupportsEvent(event) then self.frame:RegisterEvent(event) end
    end
    self:Refresh()
end

function M:Refresh()
    self:Compile()
    self:Update("visual")
end

function M:Disable()
    CancelThreshold(self)
    self.frame:UnregisterAllEvents()
    self.auraListening, self.weaponListening = false, false
    if type(_G.UnregisterStateDriver) == "function" then UnregisterStateDriver(self.host, "visibility") end
    self.host:Hide()
    self.entries, self.mask = nil, nil
    self.foodKnown = nil
    self.previewShown = nil
end

function M:RegisterMovers()
    S.RegisterOwnedMover("buffReminders", "buffs", {
        label="Buff reminders", order=620, getFrame=function() return self.host end,
        xKey="x", yKey="y", pointKey="point",
        point=function() return ANCHORS[self.config.point] or "CENTER" end,
        historyKeys={"size","spacing","columns"},
        extraControls={
            {id="size",label="Icon size",kind="number",min=22,max=72,step=1,
                get=function() return S.Config("buffReminders").size end,
                set=function(value) return S.Set("buffReminders","size",value) end},
            {id="spacing",label="Spacing",kind="number",min=0,max=20,step=1,
                get=function() return S.Config("buffReminders").spacing end,
                set=function(value) return S.Set("buffReminders","spacing",value) end},
            {id="columns",label="Per row",kind="number",min=1,max=12,step=1,
                get=function() return S.Config("buffReminders").columns end,
                set=function(value) return S.Set("buffReminders","columns",value) end},
        },
    })
end

S.Install("buffReminders", M)
