local _, P = ...
local NS, S = P.NS, P.Suite
local Style = NS.NameplateStyle
local Status = { inUse = false }
P.Status = Status

local plans, wanted = {}, {}
local plates = setmetatable({}, { __mode = "k" })
local pending = {}
local raidSizes, raidAlphas = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local raidTouched = setmetatable({}, { __mode = "k" })
local owner, events, raidEnabled

local function Flag(fn, unit)
    if not fn then return end
    local value = fn(unit)
    if S.Public(value) then return value end
end

local function IdentityAllowed(unit)
    if not C_Secrets or not C_Secrets.ShouldUnitIdentityBeSecret then return true end
    return Flag(C_Secrets.ShouldUnitIdentityBeSecret, unit) == false
end

local function Text(fn, unit)
    if not fn or not IdentityAllowed(unit) then return end
    local value = fn(unit)
    if S.Public(value) and type(value) == "string" and value ~= "" then return value end
end

local function RaidGroup(unit)
    if not IdentityAllowed(unit) then return end
    local index = UnitInRaid(unit)
    if not S.Finite(index) or index < 1 then return end
    local _, _, group = GetRaidRosterInfo(index)
    if S.Finite(group) and group >= 1 then return group end
end

local function Dead(unit)
    if Flag(UnitIsPlayer, unit) and Flag(UnitIsConnected, unit) == false then return NS.Text("Offline") end
    if Flag(UnitIsDead, unit) then return NS.Text("Dead") end
end

local function PvP(unit)
    if Flag(UnitIsPVPFreeForAll, unit) then return "Interface\\TargetingFrame\\UI-PVP-FFA" end
    if not Flag(UnitIsPVP, unit) or not IdentityAllowed(unit) then return end
    local faction = UnitFactionGroup(unit)
    if not S.Public(faction) then return end
    if faction == "Horde" then return "Interface\\TargetingFrame\\UI-PVP-Horde" end
    if faction == "Alliance" then return "Interface\\TargetingFrame\\UI-PVP-Alliance" end
end

local bossUnits = { "boss1", "boss2", "boss3", "boss4", "boss5", "boss6", "boss7", "boss8" }
local function BossNumber(unit)
    for i, boss in ipairs(bossUnits) do
        local same = UnitIsUnit(unit, boss)
        if S.Public(same) and same == true then return i end
    end
end

local function AFKTime(unit, item)
    local afk = Flag(UnitIsAFK, unit)
    if afk == false then item.since = nil end
    if afk ~= true then return end
    local now = GetTime()
    item.since = item.since or now
    local elapsed = math.floor(now - item.since)
    return ("%d:%02d"):format(math.floor(elapsed / 60), elapsed % 60)
end

local function ReadFlag(fn, text)
    return function(unit)
        if Flag(fn, unit) then return text and NS.Text(text) or true end
    end
end

local READ = {
    StatusLeader = ReadFlag(UnitIsGroupLeader), StatusAssist = ReadFlag(UnitIsGroupAssistant),
    StatusRace = function(unit) return Text(UnitRace, unit) end,
    StatusClass = function(unit) return Text(UnitClass, unit) end,
    StatusGroup = RaidGroup, StatusDead = Dead, StatusGhost = ReadFlag(UnitIsGhost, "Ghost"),
    StatusAFK = ReadFlag(UnitIsAFK, "AFK"), StatusAFKTimer = AFKTime, StatusDND = ReadFlag(UnitIsDND, "DND"),
    StatusCombat = ReadFlag(UnitAffectingCombat), StatusRez = ReadFlag(UnitHasIncomingResurrection),
    StatusPvP = PvP, StatusBossNumber = BossNumber,
}

local FLAGS = { "UNIT_FLAGS" }
local NAME = { "UNIT_NAME_UPDATE" }
local ROSTER = { "GROUP_ROSTER_UPDATE" }
local PLAYER_FLAGS = { "PLAYER_FLAGS_CHANGED", "UNIT_FLAGS" }
local SIGNALS = {
    StatusLeader = ROSTER, StatusAssist = ROSTER, StatusGroup = ROSTER,
    StatusRace = NAME, StatusClass = NAME,
    StatusDead = { "UNIT_HEALTH", "UNIT_CONNECTION", "UNIT_FLAGS" }, StatusGhost = FLAGS,
    StatusAFK = PLAYER_FLAGS, StatusDND = PLAYER_FLAGS,
    StatusAFKTimer = { "PLAYER_FLAGS_CHANGED", "UNIT_FLAGS", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED" },
    StatusCombat = FLAGS, StatusRez = { "INCOMING_RESURRECT_CHANGED" },
    StatusPvP = { "UNIT_FACTION", "UNIT_FLAGS" },
    StatusBossNumber = { "INSTANCE_ENCOUNTER_ENGAGE_UNIT" },
}

local Restore

local function Safe(region)
    return region and not NS.Safety.IsForbidden(region)
end

local function Mutable(uf, region)
    if not Safe(uf) or not Safe(region) then return false end
    if not NS.IsCombatLocked() then return true end
    local parent, target = uf:IsProtected(), region:IsProtected()
    if S.Public(parent) and S.Public(target) and parent == false and target == false then return true end
    pending[uf] = true
    return false
end

-- Blizzard continues to assign the marker and own its visibility. Size uses
-- the native container so its classification sibling keeps the right gap.
function Status.Raid(uf, prefix)
    local config = owner.config
    local keys = prefix and P.Key[prefix]
    local styled = keys and owner.active and config.look ~= P.Mode.LOOK_BLIZZARD and config[prefix]
    local hidden = styled and config[keys.RaidIcon] == false
    local size = styled and config[keys.RaidIconSize] or 22
    if not hidden and size == 22 and not raidTouched[uf] then return end
    local frame = uf.RaidTargetFrame
    if not Safe(frame) then return end
    local icon = frame.RaidTargetIcon
    if not Safe(icon) or not Mutable(uf, frame) then return end
    if hidden and not raidAlphas[icon] then
        local alpha = icon:GetAlpha()
        if S.Finite(alpha) then raidAlphas[icon] = alpha icon:SetAlpha(0) end
    elseif not hidden and raidAlphas[icon] then
        icon:SetAlpha(raidAlphas[icon])
        raidAlphas[icon] = nil
    end
    if size ~= 22 and raidSizes[frame] ~= size then
        frame:SetSize(size, size)
        raidSizes[frame] = size
    elseif size == 22 and raidSizes[frame] then
        frame:SetSize(22, 22)
        raidSizes[frame] = nil
    end
    raidTouched[uf] = (raidSizes[frame] or raidAlphas[icon]) and true or nil
    if raidTouched[uf] then Status.Restore = Restore end
end

local function PaintValue(item, unit)
    local value = READ[item.plan.spec.key](unit, item)
    if value ~= item.value then
        item.value = value
        if value ~= nil then
            if item.plan.spec.sample then
                item.content:SetText(value)
            elseif item.plan.spec.key == "StatusPvP" then
                item.content:SetTexture(value)
            end
        end
    end
    item.frame:SetShown(value ~= nil)
end

local function Hide(item)
    item.since = nil
    if Safe(item.frame) then item.frame:Hide() end
end

function Status.Release(uf)
    local plate = plates[uf]
    if not plate then return end
    for key, item in pairs(plate.active) do
        plate.active[key] = nil
        Hide(item)
    end
    plate.unit, plate.events = nil, nil
end

local function Region(uf, plate, spec)
    local frame = CreateFrame("Frame", nil, uf)
    local content
    if spec.sample then
        content = frame:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlateLevel")
    else
        content = frame:CreateTexture(nil, "ARTWORK")
        if spec.atlas then content:SetAtlas(spec.atlas) end
        if spec.texture then content:SetTexture(spec.texture) end
    end
    content:SetAllPoints(frame)
    local item = { frame = frame, content = content }
    plate.items[spec.key] = item
    return item
end

local function Place(item, uf, plan)
    local frame = item.frame
    local base = uf:GetFrameLevel()
    local level = S.Finite(base) and base + plan.layer
    if item.plan == plan and item.level == level then return end
    item.plan, item.level = plan, level
    frame:ClearAllPoints()
    local health = uf.HealthBarsContainer.healthBar
    frame:SetPoint("CENTER", health, plan.point, plan.x, plan.y)
    frame:SetSize(plan.spec.sample and plan.size * 10 or plan.size, plan.size)
    if level then frame:SetFrameLevel(level) end
    if plan.spec.sample then
        item.content:SetTextHeight(plan.size)
        item.content:SetTextColor(S.RGB(plan.color))
    end
end

function Status.Apply(uf, prefix, unit)
    local plan = prefix and plans[prefix]
    if not plan or not next(plan.items) or not unit or not Mutable(uf, uf) then
        Status.Release(uf)
        return
    end
    local widgets = uf.widgetsOnlyMode
    local bars = uf.HealthBarsContainer
    if not S.Public(widgets) or widgets == true or not Safe(bars) or not Mutable(uf, bars.healthBar) then
        Status.Release(uf)
        return
    end
    local plate = plates[uf]
    if not plate then
        plate = { items = {}, active = {} }
        plates[uf] = plate
    elseif plate.unit ~= unit then
        Status.Release(uf)
    end
    local items = plan.items
    plate.unit, plate.events = unit, plan.events
    local player = plan.player and Flag(UnitIsPlayer, unit)
    for key, item in pairs(plate.active) do
        local entry = items[key]
        if not entry or entry.spec.player and player ~= true then
            plate.active[key] = nil
            Hide(item)
        end
    end
    for key, value in pairs(items) do
        if not value.spec.player or player == true then
            local item = plate.items[key] or Region(uf, plate, value.spec)
            plate.active[key] = item
            Place(item, uf, value)
            PaintValue(item, unit)
        end
    end
end

local function UpdateEvent(uf, unit, event)
    local plate = plates[uf]
    local enabled = plate and plate.events and plate.events[event]
    if not enabled or plate.unit ~= unit or not Safe(uf) then return end
    local player
    for key in pairs(enabled) do
        local item = plate.active[key]
        if item and Safe(item.frame) then
            if item.plan.spec.player and player == nil then player = Flag(UnitIsPlayer, unit) == true end
            if not item.plan.spec.player or player then
                PaintValue(item, unit)
            else
                Hide(item)
            end
        end
    end
end

local function ByToken(event, unit)
    local uf = owner.activeUnits[unit]
    if uf then
        UpdateEvent(uf, unit, event)
        return
    end
    if event ~= "PLAYER_FLAGS_CHANGED" and event ~= "INCOMING_RESURRECT_CHANGED" and event ~= "UNIT_CONNECTION" then return end
    -- An alias only needs comparing with plates that consume this event.
    for frame, plate in pairs(plates) do
        local token = plate.unit
        if token and plate.events[event] then
            local same = UnitIsUnit(token, unit)
            if S.Public(same) and same == true then
                UpdateEvent(frame, token, event)
                return
            end
        end
    end
end

-- Sample elapsed AFK time on inspection, without reading unrelated badges or
-- looking for a unit token through every visible plate.
local function Inspect(unit)
    local base = C_NamePlate.GetNamePlateForUnit(unit)
    if not S.Public(base) or not Safe(base) then return end
    local uf = base.UnitFrame
    if not S.Public(uf) or not Safe(uf) then return end
    local plate = plates[uf]
    local item = plate and plate.active.StatusAFKTimer
    if item and plate.unit and Safe(item.frame) then PaintValue(item, plate.unit) end
end

local function OnEvent(_, event, unit)
    if event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_TARGET_CHANGED" then
        Inspect(event == "UPDATE_MOUSEOVER_UNIT" and "mouseover" or "target")
    elseif event == "PLAYER_REGEN_ENABLED" then
        if events then events:UnregisterEvent(event) end
        for uf in pairs(pending) do
            pending[uf] = nil
            if Safe(uf) then
                local token = uf.unit
                local active = owner.active and S.Public(token) and type(token) == "string" and owner.activeUnits[token] == uf
                local styled = active and (not P.IsSkinSuppressed or not P.IsSkinSuppressed(uf))
                local prefix = styled and P.PlatePrefix(uf)
                Status.Raid(uf, prefix)
                if active and Status.inUse then Status.Apply(uf, prefix, token) end
            end
        end
        Status.EndRefresh()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        for token, uf in pairs(owner.activeUnits) do UpdateEvent(uf, token, event) end
    elseif S.Public(unit) and type(unit) == "string" then
        ByToken(event, unit)
    end
end

local function Compile(config, prefix)
    local plan = { items = {}, events = {} }
    if config.look == P.Mode.LOOK_BLIZZARD or not config[prefix] then return plan end
    for _, spec in ipairs(Style.Status or {}) do
        local key = prefix .. spec.key
        if config[key] and Style.StatusSupported(spec, prefix) then
            local point, x, y = Style.StatusPoint(config, prefix, spec)
            plan.items[spec.key] = { spec = spec, point = point, x = x, y = y,
                size = config[key .. "Size"], layer = config[key .. "Layer"], color = config[key .. "Color"] }
            plan.player = plan.player or spec.player
            for _, event in ipairs(SIGNALS[spec.key] or FLAGS) do
                local entries = plan.events[event] or {}
                entries[spec.key] = true
                plan.events[event], wanted[event] = entries, true
            end
        end
    end
    return plan
end

local function Paint(uf, prefix, unit)
    if P.FriendlyNames and P.FriendlyNames.IsNameOnly(uf) then return Restore(uf) end
    if raidEnabled or raidTouched[uf] then Status.Raid(uf, prefix) end
    if Status.inUse then Status.Apply(uf, prefix, unit) end
end

Restore = function(uf)
    if raidTouched[uf] then Status.Raid(uf) end
    Status.Release(uf)
end

local function RaidEnabled(config, side)
    return config[side] and (config[side .. "RaidIcon"] == false
        or (config[side .. "RaidIconSize"] or 22) ~= 22)
end

function Status.Configure(module)
    owner = module
    raidEnabled = module.config.look ~= P.Mode.LOOK_BLIZZARD
        and (RaidEnabled(module.config, "enemy") or RaidEnabled(module.config, "friendly"))
    for event in pairs(wanted) do wanted[event] = nil end
    plans.enemy = Compile(module.config, "enemy")
    plans.friendly = Compile(module.config, "friendly")
    Status.inUse = next(plans.enemy.items) ~= nil or next(plans.friendly.items) ~= nil
    Status.EndRefresh()
    if Status.inUse and not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    if events then
        events:UnregisterAllEvents()
        for event in pairs(wanted) do
            if NS.Client.SupportsEvent(event) then events:RegisterEvent(event) end
        end
    end
    if not Status.inUse then
        for uf in pairs(plates) do Status.Release(uf) end
    end
end

function Status.EndRefresh()
    local restoring = Status.inUse or next(raidTouched) ~= nil
    Status.Paint = (restoring or raidEnabled) and Paint or nil
    Status.Restore = restoring and Restore or nil
end

function Status.Flush()
    if next(pending) then OnEvent(nil, "PLAYER_REGEN_ENABLED") end
end

function Status.Disable()
    if events then events:UnregisterAllEvents() end
    Status.inUse, Status.Paint, Status.Restore, raidEnabled = false, nil, nil, nil
    if next(pending) and NS.IsCombatLocked() then
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end
