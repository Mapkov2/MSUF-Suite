local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- An independent, pooled glow uses the same six-style painter as proc/ready
-- glows. Native alpha gates compose one interrupt's readiness with the
-- target's interruptibility; neither restricted result enters SetGlow's
-- Lua reason union. Only enabled bars with matching entries subscribe.
local Kick = {}
C.KickMark = Kick
local K, Public = C.Const, S.Public
local OWNER = "MSUF_Suite_CooldownManager"
local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }
local INTERRUPTIBLE = { UNIT_SPELLCAST_INTERRUPTIBLE = false, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true }
local marked, shown, seen, slotIDs, slotNames, alphas = {}, {}, {}, {}, {}, {}
local engine, listener, registered, active, listening
local castKind, rawNotInterruptible
local solid, clear

local function ReadCast()
    local duration = UnitCastingDuration("target")
    if not Public(duration) or duration ~= nil then
        castKind, rawNotInterruptible = "cast", select(8, UnitCastingInfo("target"))
        return
    end
    duration = UnitChannelDuration("target")
    if Public(duration) and duration == nil then
        castKind, rawNotInterruptible = nil, nil
    else
        castKind, rawNotInterruptible = "channel", select(7, UnitChannelInfo("target"))
    end
end

local function Hide(icon)
    local layer = icon.kickGlow
    if not layer then return end
    C.Effects.SetGlow(layer.proxy, "ready", false)
    layer.cast:Hide()
    layer.proxy:SetAlpha(0)
    layer.cast:SetAlpha(0)
    layer.shown, shown[icon] = false, nil
end

local function Park(icon)
    local layer = icon.kickGlow
    -- Routing may precede first icon attachment, or an icon already retired.
    if not layer or layer.entry == nil then return end
    Hide(icon)
    C.Effects.ParkOwnedGlow(layer.proxy)
    layer.entry, layer.proxy.entry = nil, nil
end
Kick.Recycled = Park

local function NewLayer(icon)
    local gate = S.CreateFrame("Frame", nil, icon)
    gate:SetAllPoints(icon)
    gate:Hide()
    local proxy = S.CreateFrame("Frame", nil, gate)
    proxy:SetAllPoints(icon)
    proxy:SetAlpha(0)
    local layer = { cast = gate, proxy = proxy }
    icon.kickGlow = layer
    return layer
end

-- Cold style/geometry work. A first preparation runs behind the hidden cast
-- gate and stops again, retaining the painter's normal size/shape memos.
function Kick.Style(entry, view)
    local icon = entry and entry.icon
    if not icon or not view or not view.kickMark then return end
    local layer = icon.kickGlow or NewLayer(icon)
    local proxy = layer.proxy
    C.Effects.ResumeOwnedGlow(proxy)
    local reshaped = proxy.shape ~= icon.shape
    layer.entry, proxy.entry = entry, entry
    proxy.w, proxy.h, proxy.shape, proxy.tex = icon.w, icon.h, icon.shape, icon.tex
    if not layer.prepared then
        C.Effects.SetGlow(proxy, "ready", true)
        C.Effects.Reshaped(proxy, view)
        C.Effects.SetGlow(proxy, "ready", false)
        layer.prepared = true
    elseif reshaped then
        C.Effects.Reshaped(proxy, view)
    else
        C.Effects.PrepareGlow(proxy)
        C.Effects.Refit(proxy)
    end
end

local function Slot(entry)
    for index = 1, #slotIDs do
        local spell = slotIDs[index]
        if entry.base == spell or entry.spell == spell or entry.override == spell
            or (slotNames[index] ~= nil and entry.name == slotNames[index]) then return index end
    end
end

local function SlotsChanged()
    if engine.SlotCount() ~= #slotIDs then return true end
    for index = 1, #slotIDs do
        if engine.Spell(index) ~= slotIDs[index] then return true end
    end
    return false
end

local function Paint()
    if SlotsChanged() then return Kick.Rebuild() end
    local showing = castKind ~= nil
    if showing then
        for index = 1, #slotIDs do
            local color = engine.SelectSlotColor(index, solid, clear, rawNotInterruptible)
            local _, _, _, alpha = color:GetRGBA()
            alphas[index] = alpha
        end
    end
    C.wipe(seen)
    for index = 1, #marked do
        local entry = marked[index]
        local icon = entry.icon
        local layer = icon and icon.kickGlow
        if layer and layer.entry == entry and icon.entry == entry then
            seen[icon] = true
            if showing then
                layer.cast:SetAlpha(1)
                layer.proxy:SetAlpha(alphas[entry.kickSlot])
                C.Effects.SetGlow(layer.proxy, "ready", true)
                if not layer.shown then
                    layer.shown = true
                    layer.cast:Show()
                end
                shown[icon] = true
            else
                Hide(icon)
            end
        end
    end
    for icon in pairs(shown) do if not seen[icon] then Hide(icon) end end
    if active ~= showing then
        active = showing
        engine.SetActive(OWNER, showing)
    end
end

local function OnEvent(_, event)
    if not registered then return end
    ReadCast()
    local value = INTERRUPTIBLE[event]
    if value ~= nil and castKind then rawNotInterruptible = value end
    Paint()
end
local function OnEngine()
    if not registered then return end
    -- "projection" can mean a secondary slot changed while the aggregate
    -- stayed ready. Both callback reasons must repaint per-slot readiness.
    Paint()
end
local function Listen(on)
    if (listening == true) == on then return end
    listening = on
    if on and not listener then
        listener = S.CreateFrame("Frame")
        listener:SetScript("OnEvent", OnEvent)
    end
    if not listener then return end
    for index = 1, #CAST_EVENTS do
        if on then listener:RegisterUnitEvent(CAST_EVENTS[index], "target") else listener:UnregisterEvent(CAST_EVENTS[index]) end
    end
    if on then listener:RegisterEvent("PLAYER_TARGET_CHANGED") else listener:UnregisterEvent("PLAYER_TARGET_CHANGED") end
end

function Kick.Release()
    for index = 1, #marked do
        local entry = marked[index]
        if entry.icon then Park(entry.icon) end
        entry.kickSlot = nil
    end
    C.wipe(marked)
    for icon in pairs(shown) do Park(icon) end
    if registered then
        if active then engine.SetActive(OWNER, false) end
        engine.Unregister(OWNER)
        Listen(false)
    end
    engine, registered, active, castKind, rawNotInterruptible = nil, nil, nil, nil, nil
    C.wipe(alphas)
end

-- Settings and the completed routing index own membership. No cooldown or
-- usable hot path visits this module while the option is off.
function Kick.Rebuild()
    local any = false
    for index = 1, #NS.CDM.SLOTS do
        local view = C.views[NS.CDM.SLOTS[index].key]
        if view and view.on and view.kickMark == true then any = true end
    end
    local host = any and C.M.active and NS.HostBridge.KickReady() or nil
    if not host or host.version < 2 then return Kick.Release() end
    if engine ~= host then
        Kick.Release()
        engine = host
    end
    local fresh = not registered
    if fresh then
        -- Registration resolves the provider's current spell set. Do this
        -- before querying slots: its disabled cache may predate a learned spell.
        registered = engine.Register(OWNER, OnEngine, true)
        if not registered then return Kick.Release() end
    end
    C.wipe(slotIDs)
    C.wipe(slotNames)
    for index = 1, engine.SlotCount() do
        slotIDs[index] = engine.Spell(index)
        slotNames[index] = C.Catalog.SpellName(slotIDs[index])
    end
    C.wipe(seen)
    for index = 1, #marked do
        local entry = marked[index]
        entry.kickSlot = nil
        if entry.icon then seen[entry.icon] = true end
    end
    C.wipe(marked)
    for slot, plan in pairs(C.plans) do
        local view = C.views[slot]
        if view and view.on and view.kickMark and plan.kind == K.KIND.COOLDOWN then
            for index = 1, #plan.entries do
                local entry = plan.entries[index]
                local interrupt = entry.src ~= "p" and Slot(entry) or nil
                if interrupt then
                    entry.kickSlot = interrupt
                    marked[#marked + 1] = entry
                    Kick.Style(entry, view)
                    if entry.icon then seen[entry.icon] = nil end
                end
            end
        end
    end
    for icon in pairs(seen) do Park(icon) end
    if marked[1] == nil then return Kick.Release() end
    if not solid then solid, clear = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0) end
    if fresh then Listen(true) end
    ReadCast()
    Paint()
end
