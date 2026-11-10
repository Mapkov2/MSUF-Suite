local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
local Public = S.Public
local ORDER = { "PRIEST", "MAGE", "WARRIOR", "DRUID", "SHAMAN", "EVOKER" }
local SAMPLES = { 18, 20, 17, 20, 16, 19 }

-- A separate row leaves all twelve personal reminder slots available. Its
-- records survive roster changes; only member events invalidate aura reads.
function R.BuildRaidOverview(self, sample)
    local raid = self.raid
    local rows, pool = raid.rows or {}, raid.pool or {}
    raid.rows, raid.pool = rows, pool
    local count, changed = 0, raid.sample ~= sample
    raid.sample = sample
    if self.config.raidBuffOverview then
        for _, class in ipairs(ORDER) do
            local buff = R.ClassBuff(class)
            if buff and (sample or #self.group.unitList > 1 and self.group.classes[class]) then
                count = count + 1
                local row = pool[class]
                if not row then
                    row = { id = buff.cast, aliases = buff.auras, members = {}, presence = {},
                        ranked = NS.Client.isForever == true }
                    pool[class] = row
                end
                if rows[count] ~= row then changed = true end
                rows[count] = row
            end
        end
    end
    if count ~= #rows then changed = true end
    for i = #rows, count + 1, -1 do rows[i] = nil end
    if changed then self.list.needsFullRefresh = true end
    return changed
end

-- The existing coalesced group pass consumes these flags. Even a burst of
-- aura events reads each affected buff/member pair at most once per pass.
function R.MarkRaidOverview(self, unit, event, info)
    if not Public(unit) or not self.group.units[unit] then return false end
    local changed = false
    for _, row in ipairs(self.raid.rows or {}) do
        local member = row.members[unit]
        if not member then
            member = { aliases = row.aliases, ranked = row.ranked }
            row.members[unit] = member
        end
        if event ~= "UNIT_AURA" or R.AuraChangeAffects(member, info) then
            member.dirty, changed = true, true
        end
    end
    return changed
end

local function ReadMember(row, unit)
    local member = row.members[unit]
    if not member then
        member = { aliases = row.aliases, ranked = row.ranked }
        row.members[unit] = member
    end
    local present, data = R.GroupBuffOn(unit, row.aliases, row.ranked)
    member.present, member.dirty, member.auraInstanceID = present, nil, nil
    if data then
        local id = data.auraInstanceID
        if Public(id) and type(id) == "number" then member.auraInstanceID = id end
    end
    row.presence[unit] = present
    if present == true then
        row.covered = row.covered + 1
    elseif present == nil then
        row.unknown = row.unknown + 1
    end
end

function R.RefreshRaidOverview(self, unit)
    -- Hidden/first-show state owes a full snapshot. Do not apply a delta to
    -- uninitialized counts or spend native reads while that snapshot waits.
    if unit and self.list.needsFullRefresh then return end
    for _, row in ipairs(self.raid.rows or {}) do
        if not unit then
            row.covered, row.unknown, row.total = 0, 0, #self.group.unitList
            R.Clear(row.presence)
            for _, member in ipairs(self.group.unitList) do ReadMember(row, member) end
        else
            local member = row.members[unit]
            if member and member.dirty then
                if member.present == true then
                    row.covered = row.covered - 1
                elseif member.present == nil then
                    row.unknown = row.unknown - 1
                end
                ReadMember(row, unit)
            end
        end
    end
end

-- The old own-class reminder shares the overview's result when both are on.
function R.RaidBuffPresence(self, buff)
    for _, row in ipairs(self.raid.rows or {}) do
        if row.aliases == buff.auras then return row.presence end
    end
end

function R.OverviewGeometry(self, reminderCount)
    local width, height = R.IconGeometry(self.config, reminderCount)
    local count = #(self.raid.rows or {})
    self.raid.offset = nil
    if count == 0 then return width, height end
    local raidWidth, raidHeight = R.IconGeometry(self.config, count)
    self.raid.offset = raidHeight + (reminderCount > 0 and self.config.spacing or 0)
    if reminderCount == 0 then return raidWidth, raidHeight end
    return math.max(width, raidWidth), height + self.raid.offset
end

local function Tooltip(button)
    if NS.IsCombatLocked() then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(button.buffID)
    GameTooltip:AddLine(S.Text("Buffed: %d/%d"):format(button.covered or 0, button.total or 0), 1, 1, 1)
    if button.unknown and button.unknown > 0 then
        GameTooltip:AddLine(S.Text("Unable to check: %d"):format(button.unknown), .7, .7, .7)
    end
    GameTooltip:Show()
end

local function Leave(button)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

function R.LayoutRaidOverview(self, open)
    local raid, c = self.raid, self.config
    local buttons, rows = raid.buttons or {}, raid.rows or {}
    raid.buttons = buttons
    local shape, look = R.IconLook(c)
    for index = 1, math.max(#buttons, #rows) do
        local button, row = buttons[index], rows[index]
        if row then
            if not button then
                button = CreateFrame("Button", nil, self.view.host)
                R.CreateIcon(button)
                button:SetScript("OnEnter", Tooltip)
                button:SetScript("OnLeave", Leave)
                buttons[index] = button
            end
            button:SetScript("OnClick", open)
            if button.buffID ~= row.id then
                button.buffID = row.id
                button.icon:SetTexture(R.Texture("spell", row.id))
            end
            button:SetSize(c.size, c.size)
            R.StyleCount(button, c)
            R.StyleIcon(button, c, look, shape)
            if button.reminderBorderArt then
                button.border:SetVertexColor(S.RGB(c.borderColor))
            else
                button.border:SetColorTexture(S.RGB(c.borderColor))
            end
            R.PositionIcon(button, self.view.host, index - 1, c)
        else
            button:Hide()
            button.overviewShown = false
            Leave(button)
        end
    end
end

-- Counts repaint only on change. Unknown members remain in the denominator
-- and carry a question mark; they are never treated as confirmed missing.
function R.DrawRaidOverview(self, allowed, sample)
    local raid = self.raid
    if not sample then allowed = allowed and self.config["class_" .. self.environment.key] ~= false end
    for index, button in ipairs(raid.buttons or {}) do
        local row = raid.rows[index]
        local shown = allowed and row ~= nil and (sample or #self.group.unitList > 1)
        if shown then
            local covered = sample and SAMPLES[index] or row.covered or 0
            local total, unknown = sample and 20 or row.total or 0, sample and 0 or row.unknown or 0
            if button.covered ~= covered or button.total ~= total or button.unknown ~= unknown then
                button.covered, button.total, button.unknown = covered, total, unknown
                button.count:SetText(covered .. "/" .. total .. (unknown > 0 and " ?" or ""))
                if unknown > 0 then
                    button.count:SetTextColor(.75, .75, .75)
                elseif covered == total then
                    button.count:SetTextColor(.35, 1, .4)
                else
                    button.count:SetTextColor(1, .55, .25)
                end
            end
        end
        if button.overviewShown ~= shown then
            button.overviewShown = shown
            button:SetShown(shown)
            if not shown then Leave(button) end
        end
    end
end

-- Install the extra display work only while opted in. The normal controller
-- keeps its original event path when the overview is disabled.
local function UpdateWithOverview(self, ...)
    if NS.IsCombatLocked() then return end
    local sample = S.editMode == true
    if self.raid.sample ~= sample then
        R.BuildRaidOverview(self, sample)
        self.view.host:SetSize(R.OverviewGeometry(self, #self.list.entries))
        R.LayoutRaidOverview(self)
        self.view.mask = nil
    end
    self.raid.update(self, ...)
    R.DrawRaidOverview(self, sample or self.view.allowed, sample)
    if sample and #self.raid.rows > 0 then
        self.view.preview:Hide()
        self.view.previewShown = false
    end
end

function R.BindRaidOverview(self)
    local raid = self.raid
    if not raid.update then raid.update = self.Update end
    self.Update = self.config.raidBuffOverview and UpdateWithOverview or raid.update
end
