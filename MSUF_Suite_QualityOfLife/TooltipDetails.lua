local _, P = ...
local NS, S = P.NS, P.Suite

-- Extra lines on Blizzard's main tooltip (guild rank, target, item level, the
-- hovered unit's mount, item and spell details), names without titles and a
-- general anchor. Lines join Blizzard's own build (TooltipLines.lua); nothing
-- asks the tooltip to rebuild and Blizzard's line data is never written.
local M = { health = {} }
local Lines = S.TooltipLines

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
local function AuraMount(aura)
    if not PublicTable(aura) then return end
    local spellID = aura.spellId
    if not S.Finite(spellID) or spellID <= 0 then return end
    local mountID = C_MountJournal.GetMountFromSpell(spellID)
    if not S.Finite(mountID) or mountID <= 0 then return end
    local name, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
    name = S.PublicText(name)
    if not name then return end
    if not S.Public(collected) or type(collected) ~= "boolean" then collected = nil end
    return name, collected
end

-- One page of helpful aura slots: "stop" on restricted data, "found" and the
-- mount, or the continuation token of the next page.
local function ScanSlots(unit, continuation, ...)
    if not S.Public(continuation) or continuation ~= nil and not S.Finite(continuation) then return "stop" end
    for index = 1, select("#", ...) do
        local slot = select(index, ...)
        if not S.Finite(slot) or Restricted(C_Secrets.ShouldUnitAuraSlotBeSecret, unit, slot) then return "stop" end
        local aura = C_UnitAuras.GetAuraDataBySlot(unit, slot)
        if not S.Public(aura) or aura ~= nil and not PublicTable(aura) then return "stop" end
        local name, collected = AuraMount(aura)
        if name then return "found", name, collected end
    end
    return continuation
end

local function ReadUnitMount(unit)
    if Restricted(C_Secrets.ShouldAurasBeSecret) then return end
    local continuation, seen = nil, {}
    repeat
        local result, name, collected = ScanSlots(unit, C_UnitAuras.GetAuraSlots(unit, "HELPFUL", 32, continuation))
        if result == "found" then return name, collected end
        -- A malformed page that does not progress ends the scan.
        if result == "stop" or result ~= nil and seen[result] then return end
        if result ~= nil then seen[result] = true end
        continuation = result
    until continuation == nil
end

-- Read once per hovered identity, outside combat; a mount change shows on
-- the next hover. A raising aura read is reported and caches nothing found.
local function UnitMount(t, unit)
    local c = M.config
    if not c.unitMount and not c.unitMountOwned or NS.IsCombatLocked() then return end
    local guid = Identity(unit)
    if not guid then return end
    if M.mountGUID ~= guid then
        M.mountGUID = guid
        M.mountName, M.mountCollected = S.Dispatch(ReadUnitMount, unit)
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

local function Now()
    local value = GetTime()
    if S.Finite(value) then return value end
end

local function NativeInspectBusy()
    local spells = _G.PlayerSpellsFrame
    return _G.InspectFrame and (InspectFrame:IsShown() or S.PublicText(InspectFrame.unit))
        or spells and spells:IsInspecting()
end

local function ReadInspect(unit)
    local value = C_PaperDollInfo.GetInspectItemLevel(unit)
    if S.Finite(value) and value > 0 then return math.floor(value) end
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
    if not M.issuingInspect or unit ~= M.issuingInspect then
        CancelInspectRetry()
        M.pendingInspect = nil
        if M.inspectHoverGUID then M.inspectAttempted = true end
    end
end

local function Remember(guid, value, now)
    if not inspectCache[guid] then
        if #inspectOrder == CACHE_SIZE then inspectCache[table.remove(inspectOrder, 1)] = nil end
        inspectOrder[#inspectOrder + 1] = guid
    end
    inspectCache[guid] = { value = value, time = now }
end

-- The tooltip still shows the unit of guid: the last unit build was for it
-- and nothing else replaced it. GameTooltip:GetUnit() is not used; it tests
-- the tooltip data's GUID, which can be secret.
local function StillHovered(unit, guid)
    return GameTooltip:IsShown() and GameTooltip:IsTooltipType(Enum.TooltipDataType.Unit) == true
        and M.inspectHoverGUID == guid and Identity(unit) == guid
end

-- One delayed attempt per hover, after the quiet period (ctx:After);
-- a new request, a foreign inspect or the end of the hover cancels it.
local HoverLevel
RetryInspect = function(self)
    local unit, guid = self.retryUnit, self.retryGUID
    if not self.config.inspectHovered or NS.IsCombatLocked() or not StillHovered(unit, guid) then return end
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
-- while no native or foreign inspect is active. Returns a cached level.
HoverLevel = function(unit)
    if NS.IsCombatLocked() then
        M.pendingInspect = nil
        return
    end
    local guid, now = Identity(unit), Now()
    if not guid or not now then return end
    if M.inspectHoverGUID ~= guid then
        ClearHoverInspect()
        M.inspectHoverGUID = guid
    end
    local entry = inspectCache[guid]
    if entry and now - entry.time < CACHE_SECONDS then return entry.value end
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
    local value = ReadInspect(request.unit)
    if not value then return end
    -- Only completed requests for the still-hovered GUID enter the cache.
    Remember(guid, value, now)
    Detail(GameTooltip, "Item level", value)
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
    if not M.config.itemLevel then return end
    local value
    local own = UnitIsUnit(unit, "player")
    if S.Public(own) and own then
        value = select(2, GetAverageItemLevel())
    elseif _G.InspectFrame and S.PublicText(InspectFrame.unit) then
        value = InspectWindowLevel(unit)
    elseif M.config.inspectHovered then
        value = HoverLevel(unit)
    end
    if S.Finite(value) and value > 0 then Detail(t, "Item level", math.floor(value)) end
end

------------------------------------------------------------------ unit lines
-- Without titles the name line shows the plain name, and the realm of a
-- player from another realm.
local function PlainName(unit, nameText)
    if not nameText then return end
    local player = UnitIsPlayer(unit)
    if not S.Public(player) or player ~= true then return end
    local name, realm = UnitName(unit)
    name, realm = S.PublicText(name), S.PublicText(realm)
    if not name then return end
    nameText:SetText(realm and name .. "-" .. realm or name)
end

local function TargetLine(t, unit)
    local target = unit .. "target"
    local exists = UnitExists(target)
    if not S.Public(exists) or not exists then return end
    local own = UnitIsUnit(target, "player")
    Detail(t, "Target", S.PublicText(UnitName(target)), M.config.selfTarget and S.Public(own) and own)
end

local function HideHealth(t)
    local health = t.StatusBar or GameTooltipStatusBar
    if NS.Safety.IsForbidden(health) then return end
    if M.health[health] == nil then M.health[health] = health:GetAlpha() end
    health:SetAlpha(0)
end

local function Unit(t, data)
    local unit, nameText = Lines.UnitName(data)
    if not unit then return end
    local c = M.config
    if not c.titles then PlainName(unit, nameText) end
    UnitMount(t, unit)
    if c.guildRank then
        local _, rank = GetGuildInfo(unit)
        Detail(t, "Guild rank", S.PublicText(rank))
    end
    if c.target then TargetLine(t, unit) end
    UnitLevel(t, unit)
    if c.hideHealth then HideHealth(t) end
end

------------------------------------------------------------------ items, spells, mounts
local function Item(t, data)
    if not S.Finite(data.id) then return end
    local _, _, _, _, _, _, _, stack, _, icon = C_Item.GetItemInfo(data.id)
    if M.config.maxStack and S.Finite(stack) and stack > 1 then Detail(t, "Maximum stack", stack) end
    if M.config.iconID and S.Finite(icon) then Detail(t, "Item icon ID", icon) end
end

local function Spell(t, data)
    if not M.config.iconID or not S.Finite(data.id) then return end
    local icon = C_Spell.GetSpellTexture(data.id)
    if S.Finite(icon) then Detail(t, "Spell icon ID", icon) end
end

-- Mount journal entries call GameTooltip:SetMountBySpellID; the hook adds the
-- marker after Blizzard showed the tooltip, so it sizes the tooltip again.
local function Mount(t, spellID)
    if not M.active or not M.config.ownedMount or t ~= GameTooltip or not S.Finite(spellID) then return end
    local mountID = C_MountJournal.GetMountFromSpell(spellID)
    if not S.Finite(mountID) then return end
    local _, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
    if not S.Public(collected) then return end
    Detail(t, "Mount collection", collected and S.Text("Collected") or S.Text("Not collected"))
    t:Show()
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

local function Corner(config, x, y)
    local corner = CORNERS[config.growth] or CORNERS[1]
    return corner.point, corner.x * math.abs(x), corner.y * math.abs(y)
end

-- ANCHOR_CURSOR ignores offsets; ANCHOR_CURSOR_RIGHT applies them from the
-- cursor (Blizzard_AuraButton.lua lists both).
local function Anchor(t, owner)
    if not M.active or t ~= GameTooltip or t._msufUnitTooltipOwner ~= nil or M.config.anchor == 1 then return end
    if M.config.anchor == 2 then
        t:SetOwner(owner, "ANCHOR_CURSOR_RIGHT", M.config.cursorX, M.config.cursorY)
        return
    end
    local point, x, y = Corner(M.config, M.config.fixedX, M.config.fixedY)
    t:SetOwner(owner, "ANCHOR_NONE")
    t:ClearAllPoints()
    t:SetPoint(point, UIParent, point, x, y)
end

local function PlacePreview(x, y)
    local frame = M.preview
    if not frame then return false end
    local point, px, py = Corner(M.config, x, y)
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
    local _, x, y = Corner(M.config, origin.fixedX, origin.fixedY)
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

local function Hidden()
    ClearHoverInspect()
    M.mountGUID, M.mountName, M.mountCollected = nil, nil, nil
    Restore(M)
end

local function Reset(self)
    ClearHoverInspect()
    self.inspectGUID, self.pendingInspect = nil, nil
    self.mountGUID, self.mountName, self.mountCollected = nil, nil, nil
    inspectCache, inspectOrder = {}, {}
end

-- Hooks cannot be removed; they do nothing while the module is off.
local function Install(self)
    if self.hooked then return end
    Lines.Add(self, "Unit", Unit)
    Lines.Add(self, "Item", Item)
    Lines.Add(self, "Spell", Spell)
    hooksecurefunc(GameTooltip, "SetMountBySpellID", Mount)
    hooksecurefunc("GameTooltip_SetDefaultAnchor", Anchor)
    GameTooltip:HookScript("OnHide", Hidden)
    hooksecurefunc("NotifyInspect", ObserveInspect)
    hooksecurefunc("ClearInspectPlayer", function() ObserveInspect() end)
    self.hooked = true
end

function M:Enable()
    self.lastInspect = Now()
    self.context:Event("INSPECT_READY", InspectReady)
    Install(self)
    LayoutPreview(self)
end

function M:Refresh()
    LayoutPreview(self)
    Reset(self)
    if not self.config.hideHealth then Restore(self) end
end

function M:Disable()
    if self.preview then self.preview:Hide() end
    Reset(self)
    Restore(self)
end

S.Install("tooltipDetails", M)
