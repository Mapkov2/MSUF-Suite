local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
-- Lifecycle, secure buttons and evaluation. Secure action buttons change
-- only out of combat; in combat a state driver hides the reminders and every
-- listener except PLAYER_REGEN_ENABLED is released. An evaluation re-reads
-- only what its event can have changed and shows the missing entries as a
-- bit mask.
local M = {}
local Public = S.Public
local ANCHORS = { "CENTER", "TOP" }
-- Registered while out of combat. In combat the reminders are hidden by their
-- state driver, so only PLAYER_REGEN_ENABLED stays registered. Subzone steps
-- (SUBZONE_EVENTS) are listened to only for the map potion.
local EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED", "ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ALIVE", "PLAYER_DEAD", "PLAYER_UNGHOST",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
}
local COMPILE_EVENTS = {
    SPELLS_CHANGED = true, PLAYER_REGEN_ENABLED = true, PLAYER_SPECIALIZATION_CHANGED = true,
    PLAYER_EQUIPMENT_CHANGED = true, WEAPON_SLOT_CHANGED = true,
    PLAYER_ENTERING_WORLD = true, ZONE_CHANGED_NEW_AREA = true,
}
-- Subzone steps matter only to the map potion: listened to while it has maps,
-- and they compile only when the player crossed onto or off such a map.
local SUBZONE_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }
local SUBZONE_EVENT = { ZONE_CHANGED = true, ZONE_CHANGED_INDOORS = true }
local INSTANCE_EVENTS = { PLAYER_ENTERING_WORLD = true, ZONE_CHANGED_NEW_AREA = true, PLAYER_REGEN_ENABLED = true }
local EVENT_MODES = {
    UNIT_AURA = "aura",
    UNIT_INVENTORY_CHANGED = "weapon", WEAPON_ENCHANT_CHANGED = "weapon",
    WEAPON_SLOT_CHANGED = "weapon", PLAYER_EQUIPMENT_CHANGED = "weapon",
    PLAYER_ENTERING_WORLD = "all", ZONE_CHANGED_NEW_AREA = "all", PLAYER_REGEN_ENABLED = "all",
    SPELLS_CHANGED = "all", PLAYER_SPECIALIZATION_CHANGED = "all",
}
local UNIT_FILTERED = { UNIT_AURA = true, UNIT_INVENTORY_CHANGED = true, PLAYER_SPECIALIZATION_CHANGED = true }
local WEAPON_EVENTS = { "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED" }
-- With options that read member auras (R.WantsMemberAuras) these follow the
-- player and the roster units only (R.GroupRoster builds the unit list);
-- without them UNIT_AURA follows the player alone.
local MEMBER_EVENTS = { "UNIT_AURA", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_PHASE" }
local MEMBER_EVENT = { UNIT_AURA = true, UNIT_CONNECTION = true, UNIT_FLAGS = true, UNIT_PHASE = true }
local ItemCount, Texture, AuraPresent, AuraChangeAffects = R.ItemCount, R.Texture, R.AuraPresent, R.AuraChangeAffects
local FoodDelta, FoodPresent, EnchantPresent = R.FoodDelta, R.FoodPresent, R.EnchantPresent
local ReadPoisonState, BuildPoisonWarnings = R.ReadPoisonState, R.BuildPoisonWarnings
local BuildEntries, SameEntries, StockChanged = R.BuildEntries, R.SameEntries, R.StockChanged

local ReadInstance = R.ReadEnvironment

local function Allowed(self)
    local dead = UnitIsDeadOrGhost("player")
    if not Public(dead) or dead == true then return false end
    local vehicle = UnitInVehicle("player")
    if not Public(vehicle) or vehicle == true then return false end
    if self.config.hideMounted then
        local mounted = IsMounted()
        if not Public(mounted) or mounted == true then return false end
    end
    local instanceType = self.instanceType
    if instanceType == false or instanceType == "arena" or instanceType == "pvp" then return false end
    if self.config.instancesOnly and instanceType ~= "party" and instanceType ~= "raid" then return false end
    if self.config[self.environmentKey] == false then return false end
    return true
end

local function CancelThreshold(self)
    if self.thresholdTimer then self.thresholdTimer:Cancel() end
    self.thresholdTimer, self.thresholdAt = nil, nil
end

local function ScheduleThreshold(self, due, now)
    if self.thresholdAt == due then return end
    CancelThreshold(self)
    if not due then return end
    local timer
    timer = C_Timer.NewTimer(math.max(0.05, due - now), function()
        if self.thresholdTimer ~= timer or not self.active then return end
        self.thresholdTimer, self.thresholdAt = nil, nil
        if not NS.IsCombatLocked() then self:Update("visual") end
    end)
    self.thresholdTimer, self.thresholdAt = timer, due
end

-- A poison reminder shows the spell its button casts right now.
local function Tooltip(button)
    local entry = button.entry
    if not entry then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if entry.kind == "spell" or entry.notice == "food" then
        GameTooltip:SetSpellByID(entry.actionID or entry.id)
    else
        GameTooltip:SetItemByID(entry.id)
    end
    if entry.restock then GameTooltip:AddLine(S.Text("None left in your bags: restock it."), 1, .65, .2, true) end
    if entry.group then GameTooltip:AddLine(S.Text("Group members need your buff."), 1, .65, .2, true) end
    if entry.notice == true then GameTooltip:AddLine(S.Text("A class in your group can provide this buff."), 1, .65, .2, true) end
    if entry.notice == "food" and not entry.restock then
        GameTooltip:AddLine(S.Text("No food for this buff in your bags."), 1, .65, .2, true)
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

-- Secure action buttons stay raw CreateFrame: the template owns the click.
-- Their regions use the shared helpers like every other Suite region.
local function MakeButton(self, index)
    local button = CreateFrame("Button", nil, self.host, "SecureActionButtonTemplate")
    button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    button.icon = S.CreateTexture(button, nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(.08, .92, .08, .92)
    button.border = S.CreateTexture(button, nil, "BACKGROUND")
    button.border:SetAllPoints(button)
    button.border:SetColorTexture(1, .72, .34, 1)
    button.count = S.CreateFontString(button, nil, "OVERLAY", "GameFontHighlightSmall")
    button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", HideTooltip)
    button:Hide()
    self.buttons[index] = button
    return button
end

local OnEvent

-- Unit and weapon events are registered only while an entry needs them and
-- the player is out of combat. Options that read member auras register the
-- member events for the current unit list again whenever the roster
-- membership changed.
local function SyncUnitEvents(self)
    local context = self.context
    local group = not self.suspended and R.WantsMemberAuras(self) and self.groupUnitList ~= nil
    local mode = group and "group" or not self.suspended and (self.hasAura or self.hasFood) and "player" or false
    local wantWeapon = not self.suspended and self.hasWeapon or false
    if mode ~= self.auraListening or group and self.groupListChanged then
        self.auraListening = mode
        self.groupListChanged = false
        for i = 1, #MEMBER_EVENTS do context:RemoveEvent(MEMBER_EVENTS[i]) end
        if group then
            for i = 1, #MEMBER_EVENTS do context:Event(MEMBER_EVENTS[i], OnEvent, true, self.groupUnitList) end
        elseif mode then
            context:Event("UNIT_AURA", OnEvent, true, "player")
        end
    end
    if wantWeapon ~= self.weaponListening then
        self.weaponListening = wantWeapon
        if wantWeapon then
            context:Event("UNIT_INVENTORY_CHANGED", OnEvent, true, "player")
            for i = 1, #WEAPON_EVENTS do context:Event(WEAPON_EVENTS[i], OnEvent, true) end
        else
            context:RemoveEvent("UNIT_INVENTORY_CHANGED")
            for i = 1, #WEAPON_EVENTS do context:RemoveEvent(WEAPON_EVENTS[i]) end
        end
    end
end

local function NewPoisonState(entry)
    return {
        aliases = entry.aliases, candidates = entry.candidates,
        active = {}, instanceIDs = {}, warnings = {}, required = 0,
    }
end

-- Derives masks, poison groups and which event groups the new entry list needs.
local function IndexEntries(self, entries)
    local hasAura, hasWeapon, hasFood = false, false, false
    self.poisonStates = {}
    for index, entry in ipairs(entries) do
        entry.bit = 2 ^ (index - 1)
        if entry.slot then
            hasWeapon = true
        elseif entry.kind == "food" then
            hasFood = true
        else
            hasAura = true
            if entry.poison then
                local state = self.poisonStates[entry.poison]
                if not state then
                    state = NewPoisonState(entry)
                    self.poisonStates[entry.poison] = state
                end
                state.required = state.required + 1
            end
        end
    end
    self.hasAura, self.hasFood, self.hasWeapon = hasAura, hasFood, hasWeapon
    SyncUnitEvents(self)
end

-- A notice has no click action; the food notice shows the Well Fed spell.
local function BindButton(button, entry)
    local action = (entry.kind == "spell" or entry.notice == "food") and "spell" or "item"
    local click = not entry.restock and not entry.notice
    button:SetAttribute("type1", click and action or nil)
    button:SetAttribute("spell1", click and action == "spell" and (entry.spellName or entry.id) or nil)
    button:SetAttribute("item1", click and action == "item" and ("item:" .. entry.id) or nil)
    button:SetAttribute("target-slot", entry.slot)
    button:SetAttribute("unit", "player")
    button.icon:SetTexture(Texture(action, entry.id))
    button.icon:SetDesaturated(entry.restock)
    entry.actionID = entry.id
    button.count:SetText("")
end

local function LayoutButtons(self, entries, entriesChanged, geometryChanged, colorChanged, textChanged)
    local c = self.config
    local size, spacing, columns = c.size, c.spacing, c.columns
    if entriesChanged or geometryChanged then
        local displayColumns = math.min(columns, math.max(1, #entries))
        local rows = math.max(1, math.ceil(#entries / columns))
        self.host:SetSize(displayColumns * size + (displayColumns - 1) * spacing,
            rows * size + (rows - 1) * spacing)
    end
    if not (entriesChanged or geometryChanged or colorChanged or textChanged) then return end
    local r, g, b = S.RGB(c.borderColor)
    for index = 1, math.max(#entries, #self.buttons) do
        local button = self.buttons[index] or MakeButton(self, index)
        local entry = entries[index]
        if entriesChanged then
            button.entry = entry
            button:Hide()
        end
        if entry then
            if entriesChanged then BindButton(button, entry) end
            if entriesChanged or textChanged then R.StyleCount(button, c) end
            if entriesChanged or colorChanged then
                button.border:SetColorTexture(r, g, b, 1)
                button.alertColor = nil
            end
            if entriesChanged or geometryChanged then button:SetSize(size, size) end
        end
    end
end

function M:Compile()
    if NS.IsCombatLocked() then return end
    local c = self.config
    local entries = BuildEntries(self)
    R.ReadPet(self)
    R.ReadHealthstone(self)
    SyncUnitEvents(self)
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
    local textChanged = not layout or layout.countFont ~= c.countFont or layout.countSize ~= c.countSize
        or layout.countPosition ~= c.countPosition or layout.countX ~= c.countX or layout.countY ~= c.countY
    if not entriesChanged and not anchorChanged and not geometryChanged and not colorChanged and not textChanged then return false end
    if anchorChanged or geometryChanged or colorChanged or textChanged then
        layout = layout or {}
        layout.point, layout.x, layout.y = c.point, c.x, c.y
        layout.size, layout.spacing, layout.columns = c.size, c.spacing, c.columns
        layout.borderColor = c.borderColor
        layout.countFont, layout.countSize, layout.countPosition = c.countFont, c.countSize, c.countPosition
        layout.countX, layout.countY = c.countX, c.countY
        self.layout = layout
        if geometryChanged then self.mask = nil end
    end
    if entriesChanged then IndexEntries(self, entries) end
    if anchorChanged then
        self.host:ClearAllPoints()
        local point = ANCHORS[c.point] or "CENTER"
        self.host:SetPoint(point, UIParent, point, c.x, c.y)
    end
    LayoutButtons(self, entries, entriesChanged, geometryChanged, colorChanged, textChanged)
    return entriesChanged
end

local function RefreshPoisonEntry(self, index, entry)
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
end

local function RefreshAuraEntry(self, entry, fullRefresh, updateInfo, foodDirty)
    if entry.kind == "food" then
        if fullRefresh or foodDirty then
            entry.present, entry.expiresAt, entry.totalDuration = FoodPresent(self)
        end
    elseif fullRefresh or AuraChangeAffects(entry, updateInfo) then
        entry.present, entry.auraInstanceID, entry.expiresAt,
            entry.instanceIDs, entry.totalDuration = AuraPresent(entry)
    end
end

-- Returns the reminder bit mask and the next advance-warning deadline.
local function Evaluate(self, mode, updateInfo, foodDirty, now, threshold)
    local mask, nextDue = 0, nil
    local fullRefresh = self.needsFullRefresh or mode == "all"
    local auraDirty = fullRefresh or mode == "aura"
    if fullRefresh then R.RefreshGroup(self) end
    local weaponDirty = fullRefresh or mode == "weapon"
    for _, state in pairs(self.poisonStates) do
        if auraDirty and (fullRefresh or AuraChangeAffects(state, updateInfo)) then ReadPoisonState(state) end
        local due = BuildPoisonWarnings(state, now, threshold)
        if due and (not nextDue or due < nextDue) then nextDue = due end
    end
    for index, entry in ipairs(self.entries) do
        if entry.group then
            local before = entry.missingCount
            entry.present = R.GroupPresent(self, entry)
            if before ~= entry.missingCount then
                self.buttons[index].count:SetText(entry.missingCount > 0 and tostring(entry.missingCount) or "")
            end
            if auraDirty then R.OwnGroupBuffTiming(self, entry, fullRefresh, updateInfo) end
        elseif entry.poison then
            RefreshPoisonEntry(self, index, entry)
        elseif entry.slot then
            if weaponDirty then entry.present, entry.expiresAt = EnchantPresent(entry.slot) end
        elseif auraDirty then
            RefreshAuraEntry(self, entry, fullRefresh, updateInfo, foodDirty)
        end
        local categoryAllowed = self.config[(entry.category or "personal") .. "_" .. self.environmentKey] ~= false
        if not categoryAllowed then
            -- This category follows its own content choices within the
            -- module-wide visibility filter.
        elseif entry.restock or entry.present == false then
            mask = mask + entry.bit
        elseif entry.present == true and threshold > 0 and now and entry.expiresAt
            and (not entry.totalDuration or entry.totalDuration > threshold) then
            local due = entry.expiresAt - threshold
            if due <= now then
                mask = mask + entry.bit
            elseif not nextDue or due < nextDue then
                nextDue = due
            end
        end
    end
    self.needsFullRefresh = false
    return mask, nextDue
end

local function ShowMask(self, mask)
    local shown, columns, size, spacing = 0, self.config.columns, self.config.size, self.config.spacing
    for index, button in ipairs(self.buttons) do
        local bit = self.entries[index] and self.entries[index].bit or 2 ^ (index - 1)
        R.AlertTransition(self, button, self.entries[index], mask % (bit * 2) >= bit)
        if mask % (bit * 2) >= bit then
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", self.host, "TOPLEFT", (shown % columns) * (size + spacing),
                -math.floor(shown / columns) * (size + spacing))
            button:Show()
            shown = shown + 1
        else
            button:Hide()
        end
    end
    if self.previewing then self.newReminderAlert = nil else R.PlayReminderAlert(self) end
end

local function UpdateCounts(self, force)
    for index, entry in ipairs(self.entries) do
        if entry.group then
            self.buttons[index].count:SetText(entry.missingCount and entry.missingCount > 0 and tostring(entry.missingCount) or "")
        elseif entry.kind ~= "spell" and not entry.notice then
            local count = ItemCount(entry.id)
            if force or count ~= entry.count then
                entry.count = count
                self.buttons[index].count:SetText(count and tostring(count) or "")
            end
        end
    end
    self.countsDirty = false
end

-- Preview configured entries even when all buffs are currently present.
-- Only display state changes; live presence/count caches remain untouched.
local function Preview(self)
    CancelThreshold(self)
    R.SpecialText(self, false)
    local mask = 0
    for _, entry in ipairs(self.entries) do mask = mask + entry.bit end
    if self.mask ~= mask or not self.previewing then
        self.previewing, self.mask = true, mask
        ShowMask(self, mask)
        for i, entry in ipairs(self.entries) do
            self.buttons[i].count:SetText(entry.group and "2" or entry.kind ~= "spell" and not entry.notice and "5" or "")
        end
    end
    self.needsFullRefresh, self.countsDirty = true, true
    self.preview:SetShown(mask == 0)
    self.previewShown = mask == 0
    R.SyncCursor(self)
end

function M:Update(mode, updateCounts, updateInfo, foodDirty)
    if NS.IsCombatLocked() then return end
    if S.editMode then Preview(self); return end
    local wasPreview = self.previewing
    if wasPreview then self.mask = nil end
    local now = GetTime()
    -- The catalog keeps the advance warning between 0 and 60 minutes.
    local threshold = R.Threshold(self)
    local mask, nextDue = 0, nil
    local allowed = Allowed(self)
    if allowed then
        mask, nextDue = Evaluate(self, mode, updateInfo, foodDirty, now, threshold)
    else
        self.needsFullRefresh = true
    end
    R.SpecialText(self, allowed and self.config["class_" .. self.environmentKey] ~= false)
    ScheduleThreshold(self, nextDue, now)
    if self.mask ~= mask then
        self.mask = mask
        ShowMask(self, mask)
    end
    if self.countsDirty or updateCounts then UpdateCounts(self, wasPreview) end
    self.previewing = nil
    local previewShown = S.editMode == true and mask == 0
    if self.previewShown ~= previewShown then
        self.preview:SetShown(previewShown)
        self.previewShown = previewShown
    end
    R.SyncCursor(self)
end

local function SyncSubzoneEvents(self)
    local c = self.config
    local wanted = not self.suspended and c.mapPotion and c.mapPotionMaps:find("%d") ~= nil
    for i = 1, #SUBZONE_EVENTS do
        if wanted then self.context:Event(SUBZONE_EVENTS[i], OnEvent, true)
        else self.context:RemoveEvent(SUBZONE_EVENTS[i]) end
    end
end

local function RegisterEvents(self)
    for i = 1, #EVENTS do self.context:Event(EVENTS[i], OnEvent, true) end
    SyncSubzoneEvents(self)
    R.SyncPreparationEvents(self, OnEvent)
    R.SyncSpecialEvents(self, OnEvent)
    if R.WantsGroup(self) then self.context:Event("GROUP_ROSTER_UPDATE", OnEvent, true)
    else self.context:RemoveEvent("GROUP_ROSTER_UPDATE") end
end

-- Entering combat: every handler would return early, so stop listening.
local function Suspend(self)
    self.suspended = true
    R.StopCursor(self, false)
    CancelThreshold(self)
    R.StopReminderAlerts(self)
    self.mask = nil
    for i = 1, #EVENTS do
        if EVENTS[i] ~= "PLAYER_REGEN_ENABLED" then self.context:RemoveEvent(EVENTS[i]) end
    end
    SyncSubzoneEvents(self)
    SyncUnitEvents(self)
    R.SyncPreparationEvents(self, OnEvent)
    R.HideReadyCheck(self)
    R.SyncSpecialEvents(self, OnEvent)
    R.CancelGroupWork(self)
    self.context:RemoveEvent("GROUP_ROSTER_UPDATE")
end

-- Leaving combat: bag events were not followed, so the item counts are read
-- once more (consumables used in combat).
local function Resume(self)
    self.suspended = false
    self.countsDirty = true
    RegisterEvents(self)
    SyncUnitEvents(self)
end

OnEvent = function(self, event, unit, updateInfo)
    if not self.active then return end
    if MEMBER_EVENT[event] and self.auraListening == "group" then
        -- Member work waits for one coalesced pass. The player's own aura
        -- delta refreshes the player's group state at once and goes on to
        -- the personal update below, so no second pass follows.
        if event == "UNIT_AURA" and unit == "player" then
            if not self.suspended then R.RefreshGroup(self, "player") end
        else
            if not self.suspended then R.QueueGroupWork(self, unit) end
            return
        end
    end
    if UNIT_FILTERED[event] and unit ~= "player" then return end
    if event == "PLAYER_REGEN_DISABLED" then
        Suspend(self)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" and self.suspended then Resume(self) end
    if NS.IsCombatLocked() then return end
    if event == "PET_BAR_UPDATE" or event == "PET_UI_UPDATE" or event == "UNIT_PET" then
        if event ~= "UNIT_PET" or unit == "player" then R.ReadPet(self); self:Update("visual") end
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        R.QueueGroupWork(self, nil, true)
        return
    end
    if SUBZONE_EVENT[event] then
        if R.OnPotionMap(self) ~= self.onPotionMap then
            self:Compile()
            self:Update("visual")
        end
        return
    end
    if event == "READY_CHECK" then
        if Allowed(self) then R.ReadyCheck(self) end
        return
    end
    if event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_RESET" or event == "CHALLENGE_MODE_COMPLETED" then
        ReadInstance(self, event)
        self:Update("visual")
        return
    end
    local foodDirty = event == "UNIT_AURA" and FoodDelta(self, updateInfo)
    if INSTANCE_EVENTS[event] then
        ReadInstance(self, event)
        -- Re-check food, never forget it: no aura listener runs in combat,
        -- and the rescan keeps every known food aura that is still active.
        self.foodKnown = nil
    end
    local bagUpdate = event == "BAG_UPDATE_DELAYED"
    if bagUpdate then R.ReadHealthstone(self) end
    if COMPILE_EVENTS[event] or (bagUpdate and StockChanged(self)) then self:Compile() end
    self:Update(EVENT_MODES[event] or "visual", bagUpdate, updateInfo, foodDirty)
end

function M:Enable()
    if not self.host then
        self.host = CreateFrame("Frame", nil, UIParent, "SecureFrameTemplate")
        self.host:SetScript("OnHide", function() R.StopCursor(self, false) end)
        self.buttons, self.foodIDs = {}, {}
        self.preview = S.CreateFontString(self.host, nil, "OVERLAY", "GameFontHighlightSmall")
        self.preview:SetPoint("CENTER", self.host, "CENTER")
        self.preview:SetText(S.Text("Buff reminders"))
    end
    self.host:Show()
    self.foodKnown = nil
    self.suspended = false
    RegisterStateDriver(self.host, "visibility", "[combat] hide; show")
    ReadInstance(self)
    RegisterEvents(self)
    self:Refresh()
end

function M:Refresh()
    ReadInstance(self)
    R.SyncPreparationEvents(self, OnEvent)
    RegisterEvents(self)
    if not self.config.readyCheckMana then R.HideReadyCheck(self) end
    self:Compile()
    self.mask = nil
    self:Update("visual")
end

function M:Disable()
    R.StopCursor(self, false)
    CancelThreshold(self)
    R.StopReminderAlerts(self)
    self.suspended = true
    SyncUnitEvents(self)
    R.SyncPreparationEvents(self, OnEvent)
    R.HideReadyCheck(self)
    R.SyncSpecialEvents(self, OnEvent)
    R.SpecialText(self, false)
    R.CancelGroupWork(self)
    self.context:RemoveEvent("GROUP_ROSTER_UPDATE")
    for i = 1, #EVENTS do self.context:RemoveEvent(EVENTS[i]) end
    SyncSubzoneEvents(self)
    self.suspended = false
    UnregisterStateDriver(self.host, "visibility")
    self.host:Hide()
    self.entries, self.mask = nil, nil
    self.foodKnown = nil
    self.previewShown, self.previewing = nil, nil
end

function M:RegisterMovers()
    S.RegisterOwnedMover("buffReminders", "buffs", {
        label = "Buff reminders", order = 620, getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return ANCHORS[self.config.point] or "CENTER" end,
        historyKeys = { "size", "spacing", "columns" },
        extraControls = {
            { id = "size", label = "Icon size", kind = "number", min = 22, max = 72, step = 1,
                get = function() return S.Config("buffReminders").size end,
                set = function(value) return S.Set("buffReminders", "size", value) end },
            { id = "spacing", label = "Spacing", kind = "number", min = 0, max = 20, step = 1,
                get = function() return S.Config("buffReminders").spacing end,
                set = function(value) return S.Set("buffReminders", "spacing", value) end },
            { id = "columns", label = "Per row", kind = "number", min = 1, max = 12, step = 1,
                get = function() return S.Config("buffReminders").columns end,
                set = function(value) return S.Set("buffReminders", "columns", value) end },
        },
    })
end

S.Install("buffReminders", M)
