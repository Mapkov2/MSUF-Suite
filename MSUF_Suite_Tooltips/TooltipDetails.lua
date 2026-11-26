local _, P = ...
local NS, S = P.NS, P.Suite

-- Extra lines on Blizzard's main tooltip (guild rank, target, item level and
-- specialization, Mythic+ forces, the hovered unit's mount, item and spell
-- details), names without titles, hidden faction, PvP, guild and realm texts,
-- a border color and a general anchor. Lines join Blizzard's own build
-- (TooltipLines.lua); nothing asks the tooltip to rebuild and Blizzard's line
-- data is never written.
local M = { health = {} }
local Lines, Border, HiddenLines = S.TooltipLines, S.TooltipBorder, S.TooltipHiddenLines
local Positions = NS.TooltipPositions
local UnitDetails, DetailText = P.TooltipUnitDetails, P.TooltipDetailText

local function Detail(t, label, value, selfTarget)
    if value == nil then return end
    if selfTarget then
        Lines.Line(t, label, tostring(value), 1, .8, .2)
    else
        Lines.Line(t, label, tostring(value), .9, .9, .9)
    end
end

local function PublicTable(value)
    return S.Public(value) and type(value) == "table" and canaccesstable(value)
end

-- True unless a documented secrecy predicate answers a public false.
local function Restricted(query, ...)
    local value = query(...)
    return not S.Public(value) or value ~= false
end

-- The unit's GUID, when its identity is public.
local function Identity(unit)
    if Restricted(C_Secrets.ShouldUnitIdentityBeSecret, unit) then return end
    return S.PublicText(UnitGUID(unit))
end

------------------------------------------------------------------ mounts
-- Read once per hovered identity, outside combat; a mount change shows on
-- the next hover. A raising aura read is reported and caches nothing found.
local function UnitMount(t, unit)
    local c = M.config
    if not c.unitMount and not c.unitMountOwned or NS.IsCombatLocked() then return end
    local guid = Identity(unit)
    if not guid then return end
    if M.mountGUID ~= guid then
        M.mountGUID = guid
        M.mountName, M.mountCollected = S.Dispatch(NS.UnitMount.Read, unit)
    end
    if c.unitMount then Detail(t, "Mount", M.mountName) end
    if c.unitMountOwned and M.mountName and M.mountCollected ~= nil then
        Detail(t, "Mount collection", M.mountCollected and S.Text("Collected") or S.Text("Not collected"))
    end
end

------------------------------------------------------------------ inspect
-- InspectFrame.unit is assigned before its server response. The shared
-- inspect buffer has no public owner, so hovered requests yield to all
-- observed inspect activity.
local inspectCache, inspectOrder = {}, {}
local INSPECT_QUIET, INSPECT_TIMEOUT, CACHE_SECONDS, CACHE_SIZE = 5, 10, 60, 16

local function DetailKeyMode()
    return S.Config("tooltipIDs").idModifier
end

local function Now()
    local value = GetTime()
    if S.Finite(value) then return value end
end

local function NativeInspectBusy()
    local spells = _G.PlayerSpellsFrame
    return _G.InspectFrame and (InspectFrame:IsShown() or S.PublicText(InspectFrame.unit))
        or spells and spells.IsInspecting and spells:IsInspecting()
end

-- The inspected unit's specialization name, from the call Blizzard's Inspect
-- window uses (InspectPaperDollFrame.lua).
local function InspectSpec(unit)
    local id = C_SpecializationInfo.GetInspectSpecialization(unit)
    if not S.Finite(id) or id <= 0 then return end
    local sex = UnitSex(unit)
    return S.PublicText(select(2, GetSpecializationInfoByID(id, S.Finite(sex) and sex or nil)))
end

-- Your own specialization needs no inspect request.
local function OwnSpec()
    if NS.Client.isForever then return UnitDetails.OwnTalents() end
    local index = C_SpecializationInfo.GetSpecialization()
    if not S.Finite(index) or index < 1 then return end
    return S.PublicText(select(2, C_SpecializationInfo.GetSpecializationInfo(index)))
end

-- The inspected unit's item level and, when asked for, its specialization.
local function ReadInspect(unit)
    local value = C_PaperDollInfo.GetInspectItemLevel(unit)
    value = S.Finite(value) and value > 0 and math.floor(value) or nil
    return value, M.config.spec and InspectSpec(unit) or nil
end

local RetryInspect
local function CancelInspectRetry()
    M.context:Cancel(RetryInspect)
end

local function ClearHoverInspect()
    CancelInspectRetry()
    M.pendingInspect, M.inspectHoverGUID, M.inspectRetryAttempted, M.inspectAttempted = nil, nil, nil, nil
end

-- Every NotifyInspect, ours included, starts a quiet period; a foreign one
-- also takes over the shared buffer.
local function ObserveInspect(unit)
    M.inspectGUID = nil
    M.lastInspect = Now()
    if not M.issuingInspect or not S.Public(unit) or unit ~= M.issuingInspect then
        CancelInspectRetry()
        M.pendingInspect = nil
        if M.inspectHoverGUID then M.inspectAttempted = true end
    end
end

local function Remember(guid, value, spec, now)
    if not inspectCache[guid] then
        if #inspectOrder == CACHE_SIZE then inspectCache[table.remove(inspectOrder, 1)] = nil end
        inspectOrder[#inspectOrder + 1] = guid
    end
    inspectCache[guid] = { value = value, spec = spec, time = now }
end

-- The tooltip still shows the unit of guid: the last unit build was for it
-- and nothing else replaced it. GameTooltip:GetUnit() is not used; it tests
-- the tooltip data's GUID, which can be secret.
local function StillHovered(unit, guid)
    if M.inspectTooltipUnit ~= unit or M.inspectHoverGUID ~= guid or not GameTooltip:IsShown() then return false end
    local matches = GameTooltip:IsTooltipType(Enum.TooltipDataType.Unit)
    return S.Public(matches) and matches == true and Identity(unit) == guid
end

-- One delayed attempt per hover, after the quiet period (ctx:After);
-- a new request, a foreign inspect or the end of the hover cancels it.
local HoverLevel
RetryInspect = function(self)
    local unit, guid = self.retryUnit, self.retryGUID
    if not self.config.inspectHovered or NS.IsCombatLocked() or not StillHovered(unit, guid) then return end
    if not P.TooltipDetailKeyHeld(DetailKeyMode()) then
        self.inspectRetryAttempted = nil
        return
    end
    HoverLevel(unit)
end

local function ScheduleRetry(unit, guid, remaining)
    if M.inspectRetryAttempted then return end
    M.inspectRetryAttempted = true
    M.retryUnit, M.retryGUID = unit, guid
    M.context:After(remaining, RetryInspect)
end

-- Native InspectFrame_Show on Retail and Forever uses CanInspect(unit, true)
-- and then NotifyInspect; there is no separate range check.
local function Inspectable(unit)
    local inspectable = CanInspect(unit, true)
    if not S.Public(inspectable) or inspectable ~= true then return false end
    local dead = UnitIsDeadOrGhost("player")
    return S.Public(dead) and dead == false
end

-- One request per continuous hover, never inside the quiet periods, and only
-- while no native or foreign inspect is active. Returns a cached level and
-- specialization.
HoverLevel = function(unit)
    local locked = NS.IsCombatLocked()
    if locked then
        M.pendingInspect = nil
        if #inspectOrder == 0 then return end
    end
    local guid = Identity(unit)
    if not guid then return end
    local now = Now()
    if not now then return end
    if M.inspectHoverGUID ~= guid then
        ClearHoverInspect()
        M.inspectHoverGUID = guid
    end
    local entry = inspectCache[guid]
    if entry and now - entry.time < CACHE_SECONDS then return entry.value, entry.spec end
    if locked then return end
    local pending = M.pendingInspect
    if pending and now - pending.time >= INSPECT_TIMEOUT then M.pendingInspect = nil end
    if M.inspectAttempted or NativeInspectBusy() or not Inspectable(unit) then return end
    local remaining = math.max(0, INSPECT_QUIET - (now - (M.lastInspect or now)))
    if M.pendingInspect then remaining = math.max(remaining, INSPECT_TIMEOUT - (now - M.pendingInspect.time)) end
    if remaining > 0 then return ScheduleRetry(unit, guid, remaining) end
    CancelInspectRetry()
    M.inspectGeneration = (M.inspectGeneration or 0) + 1
    M.pendingInspect = { unit = unit, guid = guid, time = now, generation = M.inspectGeneration }
    M.issuingInspect, M.inspectAttempted = unit, true
    -- A raising request is reported (Dispatch) and leaves neither itself nor
    -- the own-request mark behind; a later foreign request still takes over.
    local sent = S.Dispatch(NS.Finish, NotifyInspect, unit)
    M.issuingInspect = nil
    if not sent then M.pendingInspect = nil end
end

-- The item level and specialization lines of one unit.
local function LevelLines(t, value, spec)
    local hasLevel = S.Finite(value) and value > 0
    if not hasLevel and not spec then return end
    if hasLevel then Detail(t, "Item level", math.floor(value)) end
    if spec then Detail(t, "Specialization", spec) end
    M.inspectLinesAdded = true
    return true
end

local function InspectReady(_, _, guid)
    M.inspectGUID = nil
    if not M.config.itemLevel or NS.IsCombatLocked() or not S.PublicText(guid) then
        M.pendingInspect = nil
        return
    end
    local native = _G.InspectFrame and S.PublicText(InspectFrame.unit)
    if native and Identity(native) == guid then M.inspectGUID = guid end
    local request = M.pendingInspect
    if not request or request.guid ~= guid then return end
    M.pendingInspect = nil
    local now = Now()
    if not now or now - request.time >= INSPECT_TIMEOUT or request.generation ~= M.inspectGeneration
        or NativeInspectBusy() or not StillHovered(request.unit, guid) then return end
    local value, spec = ReadInspect(request.unit)
    if not value and not spec then return end
    -- Only completed requests for the still-hovered GUID enter the cache.
    Remember(guid, value, spec, now)
    LevelLines(GameTooltip, value, spec)
    GameTooltip:Show()
end

-- The open Inspect window's unit after its INSPECT_READY.
local function InspectWindowLevel(unit)
    local window = _G.InspectFrame and S.PublicText(InspectFrame.unit)
    if not window or not M.inspectGUID or NS.IsCombatLocked() then return end
    local matches = UnitIsUnit(unit, window)
    if S.Public(matches) and matches and Identity(unit) == M.inspectGUID then return ReadInspect(unit) end
end

local function UnitLevel(t, unit)
    M.inspectTooltipUnit = nil
    if not M.config.itemLevel then return end
    local value, spec
    local own = UnitIsUnit(unit, "player")
    if S.Public(own) and own then
        value, spec = select(2, GetAverageItemLevel()), M.config.spec and OwnSpec() or nil
    elseif _G.InspectFrame and S.PublicText(InspectFrame.unit) then
        value, spec = InspectWindowLevel(unit)
    elseif M.config.inspectHovered then
        M.inspectTooltipUnit = unit
        if P.TooltipDetailKeyHeld(DetailKeyMode()) then value, spec = HoverLevel(unit) end
    end
    LevelLines(t, value, spec)
end

local function InspectModifier(_, _, key, down)
    local unit = M.inspectTooltipUnit
    if not unit or M.inspectLinesAdded or not P.TooltipDetailKeyPressed(DetailKeyMode(), key, down) then return end
    local tooltip, data = Lines.Open()
    if not data or not S.Public(data.type) or data.type ~= Enum.TooltipDataType.Unit
        or (Lines.UnitName(data) or UnitDetails.Token(tooltip, data)) ~= unit then return end
    local value, spec = HoverLevel(unit)
    if LevelLines(tooltip, value, spec) then Lines.Grow(tooltip) end
end

local function ListenForInspectKey(self)
    if self.config.itemLevel and self.config.inspectHovered then
        self.context:Event("MODIFIER_STATE_CHANGED", InspectModifier)
    else
        self.context:RemoveEvent("MODIFIER_STATE_CHANGED")
    end
end

------------------------------------------------------------------ unit lines
-- Without titles the name line shows the plain name, and the realm of a
-- player from another realm unless the realm is hidden.
local function PlainName(unit, nameText, hideRealm)
    if not nameText then return end
    local player = UnitIsPlayer(unit)
    if not S.Public(player) or player ~= true then return end
    local name, realm = UnitName(unit)
    name, realm = S.PublicText(name), S.PublicText(realm)
    if not name then return end
    nameText:SetText(realm and not hideRealm and name .. "-" .. realm or name)
end

-- Mythic+ forces: the unit's share of the keystone's enemy forces, the value
-- MSUF_Suite_Modules/MythicPlusPull.lua adds up. Lines examined for a
-- criteria line of Blizzard's own, which makes ours a second one.
local FORCES_SCAN = 20

local function KeystoneActive()
    local active = C_ChallengeMode.IsChallengeModeActive()
    return S.Public(active) and active == true
end

local function HasCriteriaLine(rows)
    if not PublicTable(rows) then return false end
    local kind = Enum.TooltipDataLineType.UnitCriteriaProgress
    for i = 2, math.min(#rows, FORCES_SCAN) do
        local row = rows[i]
        if PublicTable(row) and S.Public(row.type) and row.type == kind then return true end
    end
    return false
end

-- The percent a unit adds, nil when it adds nothing. A public identity keeps
-- the answer for the hover; a restricted one reads it again on every build.
local function ForcesPercent(unit)
    local guid = Identity(unit)
    if guid and M.forcesGUID == guid then return M.forcesPercent end
    local actual, percent = C_ScenarioInfo.GetUnitCriteriaProgressValues(unit)
    if not (S.Finite(actual) and S.Finite(percent) and percent > 0 and percent <= 100) then percent = nil end
    if guid then M.forcesGUID, M.forcesPercent = guid, percent end
    return percent
end

local function Forces(t, unit, rows)
    if not KeystoneActive() or HasCriteriaLine(rows) then return end
    local attackable, player = UnitCanAttack("player", unit), UnitIsPlayer(unit)
    if not S.Public(attackable) or attackable ~= true or not S.Public(player) or player ~= false then return end
    local percent = ForcesPercent(unit)
    if percent then Detail(t, "Forces", ("+%.2f%%"):format(percent)) end
end

local function HideHealth(t)
    if NS.HostBridge and NS.HostBridge.TooltipOwnsHealth then return end
    local health = t.StatusBar
    if not S.Public(health) then return end
    health = health or GameTooltipStatusBar
    if not S.Public(health) or not health or NS.Safety.IsForbidden(health) then return end
    if M.health[health] == nil then
        local alpha = health:GetAlpha()
        if not S.Finite(alpha) then return end
        M.health[health] = alpha
    end
    health:SetAlpha(0)
end

local function Unit(t, data)
    DetailText.Clear()
    local unit, nameText, nameRow = Lines.UnitName(data)
    unit = unit or UnitDetails.Token(t, data)
    if not unit then return end
    local c = M.config
    if NS.Client.modernEquipment then
        Border.Unit(t, unit, c.borderColor)
        if not c.titles then
            PlainName(unit, nameText, c.hideRealm)
        elseif c.hideRealm and nameRow then
            HiddenLines.Realm(unit, nameText, nameRow)
        end
        HiddenLines.Lines(data, unit, c)
        UnitMount(t, unit)
        if c.mythicForces then Forces(t, unit, data.lines) end
        if c.hideHealth then HideHealth(t) end
    end
    local order = M.unitOrder
    if M.creatureOrder then
        local player = UnitIsPlayer(unit)
        if S.Public(player) and player == false then order = M.creatureOrder end
    end
    UnitDetails.Paint(t, data, unit, c, order)
    UnitLevel(t, unit)
    if NS.Extensions then NS.Extensions.TooltipLines("Unit", unit, t, Lines.Line) end
end

------------------------------------------------------------------ items, spells, mounts
local function Item(t, data)
    Border.Item(t, data, M.config.borderColor)
    if not S.Finite(data.id) then return end
    local _, _, _, _, _, _, _, stack, _, icon = C_Item.GetItemInfo(data.id)
    local showStack = M.config.maxStack and S.Finite(stack) and stack > 1
    local showIcon = M.config.iconID and S.Finite(icon)
    if M.iconFirst and showIcon then Detail(t, "Item icon ID", icon) end
    if showStack then Detail(t, "Maximum stack", stack) end
    if not M.iconFirst and showIcon then Detail(t, "Item icon ID", icon) end
    if NS.Extensions then NS.Extensions.TooltipLines("Item", data.id, t, Lines.Line) end
end

local function Spell(t, data)
    if M.config.iconID then Lines.SpellIcon(t, data, .9, .9, .9) end
    if NS.Extensions then NS.Extensions.TooltipLines("Spell", data.id, t, Lines.Line) end
end

-- The mount data post-call runs before native sizing. Read the documented
-- getter arguments instead of assuming TooltipData.id is a spell identity.
local function Mount(t)
    if not M.config.ownedMount then return end
    local info = t:GetProcessingTooltipInfo()
    if not S.Public(info) or type(info) ~= "table" or not canaccesstable(info) then return end
    local args = info.getterArgs
    if not S.Public(info.getterName) or info.getterName ~= "GetMountBySpellID"
        or not S.Public(args) or type(args) ~= "table" or not canaccesstable(args) then return end
    local spellID = args[1]
    if not S.Finite(spellID) then return end
    local mountID = C_MountJournal.GetMountFromSpell(spellID)
    if not S.Finite(mountID) then return end
    local _, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
    if not S.Public(collected) then return end
    Detail(t, "Mount collection", collected and S.Text("Collected") or S.Text("Not collected"))
end

------------------------------------------------------------------ anchor
-- Offsets point inward from the chosen corner whatever their stored sign, so
-- a corner change keeps the tooltip on screen.
local CORNERS = {
    { point = "BOTTOMRIGHT", x = -1, y = 1 },
    { point = "BOTTOMLEFT", x = 1, y = 1 },
    { point = "TOPRIGHT", x = -1, y = -1 },
    { point = "TOPLEFT", x = 1, y = -1 },
}

local function Corner(direction, x, y)
    local corner = CORNERS[direction] or CORNERS[1]
    return corner.point, corner.x * math.abs(x), corner.y * math.abs(y)
end

local function CanAnchor(frame)
    if NS.Safety.IsForbidden(frame) then return false end
    if not NS.IsCombatLocked() then return true end
    local protected = frame:IsProtected()
    return S.Public(protected) and protected == false
end

local function FixedPoint(frame, point, relativePoint, x, y, nativeAnchor, relativeTo)
    relativeTo = relativeTo or UIParent
    local old, parent, relative, ox, oy = frame:GetPoint(1)
    if not (S.Public(old) and S.Public(parent) and S.Public(relative) and S.Public(ox) and S.Public(oy)) then return end
    local reset = nativeAnchor ~= nil and nativeAnchor ~= "ANCHOR_NONE"
    if not reset and old == point and parent == relativeTo and relative == relativePoint and S.Finite(ox) and S.Finite(oy)
        and math.abs(ox - x) < .01 and math.abs(oy - y) < .01 then
        local count = frame:GetNumPoints()
        if S.Public(count) and count == 1 then return true end
    end
    if reset then frame:SetAnchorType("ANCHOR_NONE") end
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
    return true
end

-- Use the native container's corner without calling SetDefaultAnchor, which
-- would clear a GameTooltip whose unit data is already being processed.
local function AnchorBlizzard(frame, nativeAnchor)
    local container = GameTooltipDefaultContainer or SharedTooltipDefaultContainer
    if not container or NS.Safety.IsForbidden(container) then return end
    local point, _, _, x, y = container:GetPoint(1)
    if not S.PublicText(point) then return end
    if point == "TOP" or point == "BOTTOM" or point == "LEFT" or point == "RIGHT" or point == "CENTER" then
        if not S.Finite(x) or not S.Finite(y) then return end
        local upper = point == "TOP" or point ~= "BOTTOM" and y > 0
        local right = point == "RIGHT" or point ~= "LEFT" and x > 0
        point = (upper and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT")
    end
    FixedPoint(frame, point, point, 0, 0, nativeAnchor, container)
end

local function AnchorScales(frame)
    local root, scale = UIParent:GetEffectiveScale(), frame:GetEffectiveScale()
    if S.Finite(root) and root > 0 and S.Finite(scale) and scale > 0 then return root, scale end
end

local function AnchorCorner(frame, nativeAnchor, source)
    local root, scale = AnchorScales(frame)
    if not root then return end
    local config = M.config
    local point, x, y
    if source then
        point, x, y = Corner(config[source.direction], config[source.x], config[source.y])
    else
        point, x, y = Corner(config.growth, config.fixedX, config.fixedY)
    end
    local ratio = root / scale
    FixedPoint(frame, point, point, x * ratio, y * ratio, nativeAnchor)
end

local function SharedAnchor()
    return M.active and (M.config.anchor == 2 or M.config.anchor == 3)
end

local function SharedTooltip(t)
    return M.active and S.Public(t) and t and (t == GameTooltip or t == BuffFrameTooltip) and CanAnchor(t)
end

local function AnchorAtOwner(t, owner, anchor, source)
    if not S.Public(owner) or not owner or owner == WorldFrame or owner == UIParent or owner == t or not CanAnchor(owner) then return end
    local secret = owner:IsAnchoringSecret()
    local restricted = owner:IsAnchoringRestricted()
    if not S.Public(secret) or secret ~= false or not S.Public(restricted) or restricted ~= false then return end
    local config = M.config
    local side = Positions.sides[config[source.side]] or Positions.sides[1]
    local x, y = config[source.x], config[source.y]
    if side[1] == "RIGHT" then x = -x end
    if side[1] == "TOP" then y = -y end
    return FixedPoint(t, side[1], side[2], x, y, anchor, owner)
end

-- ANCHOR_CURSOR ignores offsets; ANCHOR_CURSOR_RIGHT applies them from the
-- cursor (Blizzard_AuraButton.lua lists both). GameTooltip_SetDefaultAnchor
-- has just called SetOwner(parent, "ANCHOR_NONE") and set its own point
-- (SharedTooltipTemplates.lua). A second SetOwner from this post-hook would
-- clear the tooltip again (OnTooltipCleared) inside the addon's call, in the
-- middle of the caller's build. So the cursor mode changes only the anchor
-- type (SetAnchorType with offsets, as ContainerFrame.lua does).
local relativeOwners = setmetatable({}, { __mode = "v" })

local function RestoreDefaultAfterRelativeAnchor(t, anchor)
    local owner = relativeOwners[t]
    relativeOwners[t] = nil
    if not owner then return end
    local _, relative = t:GetPoint(1)
    if S.Public(relative) and relative == owner then AnchorBlizzard(t, anchor) end
end

local function ApplyAnchor(t, source, owner, hostUnit)
    local config = M.config
    local override = source and config[source.mode]
    if not override or override <= 1 then source = nil end
    local mode = source and override - 1 or config.anchor
    if mode == 1 and not hostUnit and not relativeOwners[t] then return end
    local anchor, anchorX, anchorY = t:GetAnchorType()
    if not S.Public(anchor) then return end
    if mode == 4 then
        if AnchorAtOwner(t, owner, anchor, source) then
            relativeOwners[t] = owner
            return
        end
        mode, source = config.anchor, nil
    end
    if mode == 2 then
        relativeOwners[t] = nil
        local x, y = config[source and source.x or "cursorX"], config[source and source.y or "cursorY"]
        if anchor == "ANCHOR_CURSOR_RIGHT" and S.Public(anchorX) and S.Public(anchorY)
            and anchorX == x and anchorY == y then return end
        if anchor ~= "ANCHOR_CURSOR_RIGHT" then t:ClearAllPoints() end
        t:SetAnchorType("ANCHOR_CURSOR_RIGHT", x, y)
    elseif mode == 3 then
        relativeOwners[t] = nil
        AnchorCorner(t, anchor, source)
    elseif hostUnit then
        relativeOwners[t] = nil
        AnchorBlizzard(t, anchor)
    else
        RestoreDefaultAfterRelativeAnchor(t, anchor)
    end
end

local scopedAnchors, hookedScopedShow
local function Anchor(t)
    if not scopedAnchors and SharedAnchor() and SharedTooltip(t) then ApplyAnchor(t) end
end

local function AnchorSource(t, data)
    if not canaccesstable(data) or not S.Public(data.type) or data.type == nil then return end
    local isUnit = data.type == Enum.TooltipDataType.Unit
    local owner = t:GetOwner()
    if not S.Public(owner) or not owner then return nil, nil, isUnit end
    local id
    local world = owner == WorldFrame
    if owner == UIParent then
        local info = t:GetPrimaryTooltipInfo()
        if PublicTable(info) and S.PublicText(info.getterName) == "GetWorldCursor" then
            world = true
        elseif WorldFrame and WorldFrame.IsMouseMotionFocus and not NS.Safety.IsForbidden(WorldFrame) then
            local focus = WorldFrame:IsMouseMotionFocus()
            world = S.Public(focus) and focus == true
        end
    end
    if world then
        id = isUnit and "worldUnit" or "worldObject"
    elseif owner ~= UIParent then
        id = isUnit and "unitFrame" or "uiElement"
    end
    return Positions.byID[id], owner, isUnit
end

-- Explicit SetOwner callers (bags, spells, auras and unit frames) bypass
-- GameTooltip_SetDefaultAnchor. Only the primary build can move its tooltip.
local function AnchorData(t, data)
    if not SharedTooltip(t) or not S.Public(data) or type(data) ~= "table" then return end
    local primary = t:GetPrimaryTooltipData()
    if not S.Public(primary) or not rawequal(primary, data) then return end
    if not scopedAnchors then return ApplyAnchor(t) end
    local source, owner, isUnit = AnchorSource(t, data)
    local host = NS.HostBridge
    local hostUnit = isUnit and host and host.OwnsUnitFrameTooltip and host.OwnsUnitFrameTooltip(t)
    ApplyAnchor(t, source, owner, hostUnit)
end

-- Plain SetText tooltips have no data post-call. Give them the shared anchor
-- without guessing their source or reading the text that Blizzard rendered.
local function AnchorPlain(t)
    if not scopedAnchors or not SharedAnchor() or not SharedTooltip(t) then return end
    local data = t:GetPrimaryTooltipData()
    if S.Public(data) and data == nil then ApplyAnchor(t) end
end

local function AnchorBlizzardUnit(t, data)
    local host = NS.HostBridge
    if t ~= GameTooltip or not host or not host.OwnsUnitFrameTooltip or not host.OwnsUnitFrameTooltip(t)
        or not S.Public(data) or type(data) ~= "table" or not CanAnchor(t) then return end
    local primary = t:GetPrimaryTooltipData()
    if not S.Public(primary) or not rawequal(primary, data) then return end
    local anchor = t:GetAnchorType()
    if S.Public(anchor) then AnchorBlizzard(t, anchor) end
end

local function AnchorUnitPanel(panel, owner)
    if not M.active or not CanAnchor(panel) then return end
    local source = scopedAnchors and Positions.byID.unitFrame or nil
    local override = source and M.config[source.mode]
    if override == 5 and AnchorAtOwner(panel, owner, nil, source) then return end
    if not override or override <= 1 or override == 5 then source = nil end
    local mode = source and override - 1 or M.config.anchor
    if mode == 1 then return AnchorBlizzard(panel) end
    if mode == 2 then
        local x, y = GetCursorPosition()
        local root, scale = AnchorScales(panel)
        local ox, oy = M.config[source and source.x or "cursorX"], M.config[source and source.y or "cursorY"]
        if root and S.Finite(x) and S.Finite(y) then
            FixedPoint(panel, "LEFT", "BOTTOMLEFT", (x + ox * root) / scale, (y + oy * root) / scale)
        end
        return
    end
    AnchorCorner(panel, nil, source)
end

local function RefreshAnchor()
    scopedAnchors = false
    for _, source in ipairs(Positions.sources) do
        if (M.config[source.mode] or 1) > 1 then
            scopedAnchors = true
            break
        end
    end
    if scopedAnchors and not hookedScopedShow then
        GameTooltip:HookScript("OnShow", AnchorPlain)
        if BuffFrameTooltip then BuffFrameTooltip:HookScript("OnShow", AnchorPlain) end
        hookedScopedShow = true
    end
    if SharedAnchor() or scopedAnchors then
        Lines.SetPositioner(AnchorData)
    elseif M.active then
        Lines.SetPositioner(AnchorBlizzardUnit, "Unit")
    else
        Lines.SetPositioner(nil)
    end
    if NS.HostBridge then NS.HostBridge.SetUnitFrameTooltipPanelPositioner(M.active and AnchorUnitPanel or nil) end
end

local function PlacePreview(x, y)
    local frame = M.preview
    if not frame then return false end
    local point, px, py = Corner(M.config.growth, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, px, py)
    return true
end

local function LayoutPreview(self)
    local frame = self.preview
    if not frame then
        frame = S.CreateFrame("Frame", nil, UIParent)
        frame:SetSize(260, 54)
        frame:EnableMouse(false)
        local bg = S.CreateTexture(frame, nil, "BACKGROUND")
        bg:SetAllPoints(frame)
        bg:SetColorTexture(.04, .07, .1, .96)
        local text = S.CreateFontString(frame, nil, "OVERLAY")
        text:SetPoint("CENTER", frame, "CENTER")
        S.SetFont(text, nil, 14, "OUTLINE")
        text:SetText(S.Text("Tooltip details"))
        self.preview = frame
    end
    PlacePreview(self.config.fixedX, self.config.fixedY)
    frame:SetShown(S.editMode == true and self.config.anchor == 3)
end

-- Drags start from the shown, inward offsets.
local function CaptureOffsets(origin)
    local _, x, y = Corner(M.config.growth, origin.fixedX, origin.fixedY)
    origin.fixedX, origin.fixedY = x, y
end

function M:HideEditPreview()
    if self.preview then self.preview:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover("tooltipDetails", "tooltip", { label = "Tooltip details", order = 657,
        getFrame = function() return self.preview end, xKey = "fixedX", yKey = "fixedY",
        point = function() return (CORNERS[self.config.growth] or CORNERS[1]).point end,
        place = PlacePreview, capture = CaptureOffsets,
        isEnabled = function() return self.config.anchor == 3 end, historyKeys = { "growth" } })
end

------------------------------------------------------------------ lifecycle
local function Restore(self)
    for bar, alpha in pairs(self.health) do
        bar:SetAlpha(alpha)
        self.health[bar] = nil
    end
end

local function ReleaseLegacyHealth() Restore(M) end

local function Hidden()
    DetailText.Clear()
    ClearHoverInspect()
    M.inspectTooltipUnit, M.inspectLinesAdded = nil, nil
    M.mountGUID, M.mountName, M.mountCollected = nil, nil, nil
    M.forcesGUID, M.forcesPercent = nil, nil
    Border.Restore(GameTooltip)
    Restore(M)
end

local function Reset(self)
    DetailText.Clear()
    ClearHoverInspect()
    self.inspectTooltipUnit, self.inspectLinesAdded = nil, nil
    self.inspectGUID, self.pendingInspect = nil, nil
    self.mountGUID, self.mountName, self.mountCollected = nil, nil, nil
    self.forcesGUID, self.forcesPercent = nil, nil
    Border.Restore(GameTooltip)
    inspectCache, inspectOrder = {}, {}
end

-- Hooks cannot be removed; they do nothing while the module is off.
local function InstallDetails(self)
    Lines.Add(self, "Unit", Unit)
    if NS.Client.modernEquipment then
        Lines.Add(self, "Item", Item)
        Lines.Add(self, "Spell", Spell)
        Lines.Add(self, "Mount", Mount)
    end
    GameTooltip:HookScript("OnHide", Hidden)
    GameTooltip:HookScript("OnTooltipCleared", function(t)
        DetailText.Clear()
        self.inspectTooltipUnit, self.inspectLinesAdded = nil, nil
        Border.Restore(t)
        Restore(self)
    end)
    hooksecurefunc("NotifyInspect", ObserveInspect)
    hooksecurefunc("ClearInspectPlayer", function() ObserveInspect() end)
end

local function Install(self)
    if self.hooked then return end
    hooksecurefunc("GameTooltip_SetDefaultAnchor", Anchor)
    InstallDetails(self)
    self.hooked = true
end

local function ReadOrder(self)
    local content = NS.TooltipContent
    if not content then return end
    self.unitOrder = content.Order("unit", self.config.unitContentOrder)
    self.creatureOrder = self.config.creatureContentOrder ~= "" and self.config.creatureContentOrder ~= nil
        and content.Order("creature", self.config.creatureContentOrder) or nil
    self.iconFirst = content.Order("item", self.config.itemContentOrder)[1] == "icon"
end

function M:Enable()
    ReadOrder(self)
    if NS.Client.modernEquipment and NS.HostBridge then NS.HostBridge.ReleaseLegacyTooltipHealth = ReleaseLegacyHealth end
    self.lastInspect = Now()
    self.context:Event("INSPECT_READY", InspectReady)
    ListenForInspectKey(self)
    Install(self)
    RefreshAnchor()
    LayoutPreview(self)
end

function M:Refresh()
    ReadOrder(self)
    ListenForInspectKey(self)
    RefreshAnchor()
    LayoutPreview(self)
    Reset(self)
    if not self.config.hideHealth then Restore(self) end
end

function M:Disable()
    if NS.HostBridge then NS.HostBridge.ReleaseLegacyTooltipHealth = nil end
    Lines.SetPositioner(nil)
    if NS.HostBridge then NS.HostBridge.SetUnitFrameTooltipPanelPositioner(nil) end
    if self.preview then self.preview:Hide() end
    Reset(self)
    Restore(self)
end

S.Install("tooltipDetails", M)
