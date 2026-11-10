local _, private = ...
local NS, S = private.NS, private.Suite
local Model = NS.NameplateAuraDisplay
-- The aura containers of a nameplate: Buffs, Debuffs, Custom 1-3 and Dots
-- on target, one set for enemy and one for friendly plates. Buffs and
-- Debuffs are lanes: while one is Visible the Suite draws it and hides
-- Blizzard's list of that kind; otherwise Blizzard's list is not touched.
-- Crowd control always stays Blizzard's. Every container is a native
-- AuraContainer: Blizzard tracks, filters, sorts and times the auras, so
-- nothing in this file runs on an aura update. Work happens only when a
-- plate gets a unit or the settings change, and a settings change reaches
-- only the containers whose own signature changed.
local Display = {}
private.AuraDisplay = Display
local states = setmetatable({}, { __mode = "k" })
local pending = setmetatable({}, { __mode = "k" })
local owner, repaint, plan, revision, waitFrame, stackOptions
local active, editMode, listening = false, false, false
local EMPTY = { includeSpellIDs = {} }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SORT = { "Default", "ExpirationOnly", "NameOnly", "AuraInstanceIDOnly", "ImportantOnly" }
local OUTLINE = { "", "OUTLINE", "THICKOUTLINE" }
local TEXT_SWITCH = { Time = "timeText", Stack = "stackText" }
local LISTS = { "BuffListFrame", "DebuffListFrame" }
local NATIVE_CVARS = { nameplateenemynpcauradisplay = true, nameplateenemyplayerauradisplay = true,
    nameplatefriendlyplayerauradisplay = true, nameplateshowdebuffsonfriendly = true }
local IN_COMBAT = { inCombat = true }

local function Accessible(frame)
    if not frame or NS.Safety.IsForbidden(frame) then return false end
    local allowed = frame:CanBeAccessedInContext()
    return NS.Public(allowed) and allowed == true
end

local function Wait(uf)
    pending[uf] = true
    if not waitFrame then
        waitFrame = CreateFrame("Frame")
        waitFrame:SetScript("OnEvent", function() Display.Resume() end)
    end
    waitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    waitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    waitFrame:RegisterEvent("AURA_DATA_PROVIDER_SWITCH")
end

local function Unwait()
    if waitFrame and not next(pending) then waitFrame:UnregisterAllEvents() end
end

local function Writable(frame)
    if not Accessible(frame) then return false end
    if not NS.InCombat() then return true end
    local protected = frame:IsProtected()
    return NS.Public(protected) and protected == false
end

-- A Visible lane replaces one Blizzard list. A hidden list has no mouse
-- targets and skips its refresh. Every visibility request of Blizzard's is
-- observed, so handing the list back also restores what Blizzard asked for
-- meanwhile. All bookkeeping stays outside the Blizzard frames.
local function ListChanged(state, list, shown)
    if not list.owned or list.changing or not NS.Public(shown) then return end
    list.shown = shown == true
    if not list.shown then return end
    if not Writable(list.frame) then
        Display.Restore(state.uf)
        return
    end
    list.changing = true
    list.frame:Hide()
    list.changing = nil
end

local function List(state, name)
    local list = state.lists[name]
    if list ~= nil then return list end
    local frame = state.native and state.native[name]
    if not Accessible(frame) then
        state.lists[name] = false
        return false
    end
    list = { frame = frame, owned = false }
    state.lists[name] = list
    hooksecurefunc(frame, "SetShown", function(_, shown) ListChanged(state, list, shown) end)
    hooksecurefunc(frame, "Show", function() ListChanged(state, list, true) end)
    hooksecurefunc(frame, "Hide", function() ListChanged(state, list, false) end)
    return list
end

-- Hides (owned) or hands back one Blizzard list. False while Blizzard
-- refuses the change: a protected list in combat, or a secret state.
local function OwnList(state, name, owned)
    local list = List(state, name)
    if not list or list.owned == owned then return true end
    if not Writable(list.frame) then return false end
    if owned then
        local shown = list.frame:IsShown()
        if not NS.Public(shown) then return false end
        list.shown = shown
    end
    list.owned, list.changing = owned, true
    list.frame:SetShown(not owned and list.shown)
    list.changing = nil
    return true
end

-- False while a Blizzard list could not be handed back yet.
local function Hide(state)
    if state.visible then
        if Accessible(state.wrapper) then state.wrapper:Hide() end
        for _, side in pairs(state.sides) do
            for _, record in pairs(side.records) do
                if Accessible(record.frame) then record.frame:SetEnabled(false) end
            end
        end
        state.visible = false
    end
    state.unit, state.side, state.kind = nil, nil, nil
    local restored = true
    for name, list in pairs(state.lists) do
        if list and list.owned and not OwnList(state, name, false) then restored = false end
    end
    state.restoring = not restored or nil
    return restored
end

function Display.Restore(uf)
    local state = states[uf]
    if state and not Hide(state) then
        Wait(uf)
        return
    end
    pending[uf] = nil
    Unwait()
end

local function Edges(parent)
    local edges = {}
    for i = 1, 4 do edges[i] = parent:CreateTexture(nil, "OVERLAY") end
    return edges
end

local function Border(edges, parent, width)
    for i = 1, 4 do edges[i]:ClearAllPoints() end
    edges[1]:SetPoint("TOPLEFT", parent, "TOPLEFT")
    edges[1]:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
    edges[1]:SetHeight(width)
    edges[2]:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT")
    edges[2]:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")
    edges[2]:SetHeight(width)
    edges[3]:SetPoint("TOPLEFT", parent, "TOPLEFT")
    edges[3]:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT")
    edges[3]:SetWidth(width)
    edges[4]:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
    edges[4]:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")
    edges[4]:SetWidth(width)
end

local function Child(parent, level)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:SetFrameLevel(level)
    return frame
end

local function Font(part, c, field)
    local values, text, label = plan.values, c.text[field], part[field]
    S.SetFont(label, plan.font, text.size, OUTLINE[values.auraTextOutline])
    label:ClearAllPoints()
    label:SetPoint(text.point, part.button, text.point, text.x, text.y)
    label:SetTextColor(NS.RGB(values["aura" .. field .. "Color"]))
    part[field .. "Host"]:SetAlpha(values["aura" .. field .. "Text"] and c[TEXT_SWITCH[field]] and 1 or 0)
end

local function DispelOptions(values)
    local assets, colors = {}, {}
    if values.auraDispelHighlight then
        for _, key in ipairs({ "Magic", "Curse", "Disease", "Poison", "Bleed" }) do
            assets[key] = { asset = WHITE }
            colors[key] = AuraUtil.GetAuraBorderColor(key)
        end
    end
    if values.auraEnrageHighlight then
        -- Enrages use the empty dispel-name token on legacy clients. The
        -- named token is accepted too, without treating nil as an enrage.
        assets[""], assets.Enrage = { asset = WHITE }, { asset = WHITE }
        colors[""], colors.Enrage = CreateColor(1, .55, .1), CreateColor(1, .55, .1)
    end
    return { style = Enum.CustomAuraButtonDispelTypeTextureStyle.CustomAsset,
        showWhenHelpful = true, showWhenHarmful = true, customDispelAssetMap = assets, customDispelColorMap = colors }
end

-- An aura from every player (Sunder Armor) shows its count from one: the
-- slot's current row, or the second flow group.
local function Any(part)
    if part.slot then return part.slot.any == true end
    return part.anyGroup
end

local function BindDispel(record, part)
    if not record.c.dispel then return end
    for _, texture in ipairs(part.dispel) do part.button:AddDispelTypeTexture(texture, plan.dispel) end
end

local function StylePart(record, part)
    local c, values, button = record.c, plan.values, part.button
    local mouse = c.tooltip and not values.auraClickthrough
    button:SetSize(c.width, c.height)
    button:SetAlpha(c.alpha)
    button:SetMouseClickEnabled(mouse)
    button:SetMouseMotionEnabled(mouse)
    part.icon:SetTexCoord(c.crop, 1 - c.crop, c.crop, 1 - c.crop)
    Font(part, c, "Time")
    Font(part, c, "Stack")
    part.cooldown:SetAlpha(values.auraSwipe and c.swipe and values.auraSwipeAlpha / 100 or 0)
    Border(part.dispel, part.dispelHost, values.auraHighlightSize)
    Border(part.pandemicEdges, part.pandemicStyle, values.auraHighlightSize)
    for _, texture in ipairs(part.pandemicEdges) do texture:SetColorTexture(NS.RGB(values.auraPandemicColor)) end
    part.pandemicStyle:SetShown(values.auraPandemicHighlight and c.pandemic)
    if part.bound then
        button:ClearDispelTypeTextures()
        BindDispel(record, part)
        button:SetApplicationCount(part.Stack, Any(part) and stackOptions or nil)
    end
end

local function Initialize(record, button, slot, anyGroup)
    local level = button:GetFrameLevel()
    local part = { button = button, slot = slot, anyGroup = anyGroup == true }
    part.icon = button:CreateTexture(nil, "ARTWORK")
    part.icon:SetAllPoints(button)
    part.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    part.cooldown:SetAllPoints(button)
    part.cooldown:SetDrawBling(false)
    part.cooldown:SetReverse(true)
    part.cooldown:SetHideCountdownNumbers(true)
    part.cooldown:SetFrameLevel(level + 1)
    part.dispelHost = Child(button, level + 2)
    part.dispel = Edges(part.dispelHost)
    part.pandemic = Child(button, level + 3)
    part.pandemicStyle = Child(part.pandemic, level + 3)
    part.pandemicEdges = Edges(part.pandemicStyle)
    part.TimeHost, part.StackHost = Child(button, level + 4), Child(button, level + 5)
    part.Time = part.TimeHost:CreateFontString(nil, "OVERLAY")
    part.Stack = part.StackHost:CreateFontString(nil, "OVERLAY")
    if slot then button:SetAllPoints(slot.anchor) end
    StylePart(record, part)
    button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT")
    -- Bind last. Blizzard seals bound regions and seals the button after
    -- initializeFrame returns. Future paints never inspect aura state.
    button:SetIcon(part.icon)
    button:SetDurationCooldown(part.cooldown)
    button:SetDurationText(part.Time)
    button:SetApplicationCount(part.Stack, Any(part) and stackOptions or nil)
    BindDispel(record, part)
    button:AddPandemicRegion(part.pandemic)
    part.bound = true
    record.parts[#record.parts + 1] = part
end

local function NewRecord(state, c)
    local frame = CreateFrame("AuraContainer", nil, state.wrapper, "CustomAuraContainerTemplate")
    frame:SetEnabled(false)
    NS.Client.RealAurasOnly(frame)
    return { frame = frame, parts = {}, slots = {}, groups = {}, key = c.key }
end

local function Place(state, record, c)
    local frame, direction = record.frame, AnchorUtil.FlowDirection
    record.level = state.wrapper:GetFrameLevel() + c.layer
    frame:ClearAllPoints()
    frame:SetPoint(c.point, state.health, c.relative, c.x, c.y)
    frame:SetSize(c.gridWidth, c.gridHeight)
    frame:SetFrameLevel(record.level)
    frame:SetFlowLayoutAnchorPoint(c.flowPoint)
    frame:SetFlowLayoutGrowthDirection(direction[c.horizontal], direction[c.vertical])
    frame:SetFlowLayoutMaximumLineSize(c.lineSize)
end

-- A slot or group that was added once stays; one without candidates is empty.
local function ClearSlots(record, first)
    for index = first, #record.slots do
        local slot = record.slots[index]
        slot.anchor:Hide()
        if slot.added then record.frame:SetAuraSlotCandidateFilters(slot.key, EMPTY) end
    end
end

local function ClearGroups(record)
    for name in pairs(record.groups) do record.frame:SetAuraGroupCandidateFilters(name, EMPTY) end
end

local function NewSlot(state, record, index)
    local slot = { key = "slot" .. index, anchor = CreateFrame("Frame", nil, state.wrapper) }
    slot.texture = slot.anchor:CreateTexture(nil, "BACKGROUND")
    slot.texture:SetAllPoints(slot.anchor)
    slot.texture:SetDesaturated(true)
    record.slots[index] = slot
    return slot
end

-- Fixed slots: one native aura slot per tracked aura, in list order, with an
-- optional faded icon while the aura is missing.
local function Slots(state, record, c)
    for index, row in ipairs(c.rows) do
        local slot = record.slots[index] or NewSlot(state, record, index)
        local x, y = Model.SlotOffset(c, index)
        slot.anchor:SetSize(c.width, c.height)
        slot.anchor:ClearAllPoints()
        slot.anchor:SetPoint(c.flowPoint, record.frame, c.flowPoint, x, y)
        slot.anchor:SetFrameLevel(record.level)
        local texture = C_Spell.GetSpellTexture(row.id)
        if NS.Public(texture) then slot.texture:SetTexture(texture) end
        slot.texture:SetTexCoord(c.crop, 1 - c.crop, c.crop, 1 - c.crop)
        slot.texture:SetAlpha(c.missingAlpha / 100)
        slot.texture:SetShown(c.missing)
        slot.anchor:Show()
        slot.any = row.any
        if not slot.added then
            record.frame:AddAuraSlot(slot.key, row.filter, { candidateFilters = row.candidate,
                sortMethod = AuraContainerSortMethod.ExpirationOnly,
                initializeFrame = function(button) Initialize(record, button, slot) end })
            slot.added = true
        else
            record.frame:SetAuraSlotCandidateFilters(slot.key, row.candidate)
            record.frame:SetAuraSlotFilterString(slot.key, row.filter)
        end
    end
    ClearSlots(record, #c.rows + 1)
end

-- Flow: one native aura group packs the active auras; auras from every
-- player (index 2) need their own filter and follow as a second group.
local function Group(record, c, name, index, filter, candidate, count)
    local frame = record.frame
    if not record.groups[name] then
        if count == 0 then return end
        frame:AddAuraGroup(name, filter, { maxFrameCount = count, candidateFilters = candidate,
            initializeFrame = function(button) Initialize(record, button, nil, index == 2) end })
        record.groups[name] = true
    else
        frame:SetAuraGroupFilterString(name, filter)
        frame:SetAuraGroupCandidateFilters(name, count > 0 and candidate or EMPTY)
        if count > 0 then frame:SetAuraGroupMaxFrameCount(name, count) end
    end
    local layout = { elementWidth = c.width, elementHeight = c.height, elementSpacing = c.gap, lineSpacing = c.gap }
    if c.anyCount > 0 or record.groups.any then
        layout.groupSpacing, layout.groupLineSpacing, layout.layoutIndex = c.gap, c.gap, index
    end
    frame:SetAuraGroupLayout(name, layout)
    frame:SetAuraGroupSortMethod(name, AuraContainerSortMethod[SORT[c.sort]],
        c.reverse and AuraContainerSortDirection.Reverse or AuraContainerSortDirection.Normal)
end

local function Configure(state, record, c)
    record.c = c
    if c.enabled then
        Place(state, record, c)
        if c.fixed then
            ClearGroups(record)
            Slots(state, record, c)
        else
            ClearSlots(record, 1)
            Group(record, c, "auras", 1, c.filter, c.candidate, c.groupCount)
            Group(record, c, "any", 2, c.anyFilter, c.anyCandidate, c.anyCount)
        end
        for _, part in ipairs(record.parts) do StylePart(record, part) end
    end
    record.sig, record.style = c.sig, plan.style
end

-- Sealed aura regions refuse edits in combat and while auras are secret.
local function Mutable(side)
    if NS.InCombat() then return false end
    local secret = C_Secrets.ShouldAurasBeSecret()
    if not NS.Public(secret) or secret then return false end
    for _, record in pairs(side.records) do
        for _, part in ipairs(record.parts) do
            if not Accessible(part.button) then return false end
        end
    end
    return true
end

-- Builds the containers this side uses and applies the plan to the ones it
-- changed. A container that never showed is built at once; one that already
-- holds buttons waits until its regions may be edited (false).
local function ConfigureSide(state, sideKey)
    local side, mutable = state.sides[sideKey], nil
    for _, c in ipairs(plan.scopes[sideKey]) do
        local record = side.records[c.key]
        if not record and c.enabled then
            record = NewRecord(state, c)
            side.records[c.key] = record
        end
        if record and (record.sig ~= c.sig or record.style ~= plan.style) then
            if record.sig then
                if mutable == nil then mutable = Mutable(side) end
                if not mutable then return false end
            end
            Configure(state, record, c)
        end
    end
    side.revision = revision
    return true
end

local function New(uf, health)
    -- A child of the plate's unit frame inherits its scale, fade and lifetime.
    -- Ignore its children for bounds so sealed aura slots cannot enlarge it.
    local wrapper = CreateFrame("Frame", nil, uf, "DisableUntrustedLayoutScriptsTemplate")
    wrapper:SetIgnoringChildrenForBounds(true)
    wrapper:SetAllPoints(uf)
    wrapper:SetFrameLevel(uf:GetFrameLevel() + 5)
    wrapper:Hide()
    local state = { uf = uf, wrapper = wrapper, health = health, visible = false, lists = {},
        sides = { enemy = { records = {} }, friendly = { records = {} } } }
    -- Blizzard hides its aura frame where a plate shows no auras (names
    -- only). Follow it; nothing is written to Blizzard's frame.
    local native = uf.AurasFrame
    if Accessible(native) then
        state.native = native
        native:HookScript("OnHide", function() wrapper:Hide() end)
        native:HookScript("OnShow", function() if state.visible then wrapper:Show() end end)
    end
    return state
end

-- kind: the plate kind (enemyNpc ...), nil while the side has no lane. A
-- lane shows on the plate kinds Blizzard's switches name and owns Blizzard's
-- list of its kind meanwhile; a lane whose list cannot be hidden yet leaves
-- the plate to Blizzard's list. False while a list change is still due.
local function Show(state, unit, sideKey, kind)
    local complete, blocked = true, nil
    for _, name in ipairs(LISTS) do
        local owned = false
        for _, record in pairs(state.sides[sideKey].records) do
            local c = record.c
            if c.frame == name and c.enabled and c.kinds[kind] == true then owned = true end
        end
        if (owned or state.lists[name]) and not OwnList(state, name, owned) then
            complete = false
            if owned then
                blocked = blocked or {}
                blocked[name] = true
            end
        end
    end
    for key, side in pairs(state.sides) do
        for _, record in pairs(side.records) do
            local c = record.c
            local shown = key == sideKey and c.enabled and (not c.kinds or c.kinds[kind] == true)
                and not (blocked and blocked[c.frame])
            if shown then record.frame:SetUnit(unit) end
            record.frame:SetEnabled(shown)
        end
    end
    local shown = true
    if state.native then
        shown = state.native:IsShown()
        shown = NS.Public(shown) and shown == true
    end
    state.wrapper:SetShown(shown)
    state.visible, state.unit, state.side, state.kind = true, unit, sideKey, kind
    return complete
end

local function Used(unit, sideKey)
    if not NS.Public(unit) or type(unit) ~= "string" or not active or editMode then return false end
    local values = plan.values
    return values.look ~= private.Mode.LOOK_BLIZZARD and values[sideKey] and plan.used[sideKey] == true
end

-- True while the plate shows the Suite's containers. A plate whose side has
-- no enabled container never gets a frame of ours.
function Display.Apply(uf, unit, enemy)
    local sideKey = enemy and "enemy" or "friendly"
    if not Used(unit, sideKey) then
        Display.Restore(uf)
        return false
    end
    local kind
    if plan.lanes[sideKey] then
        local player = UnitIsPlayer(unit)
        if not NS.Public(player) then
            Display.Restore(uf)
            return false
        end
        kind = sideKey .. (player == true and "Player" or "Npc")
    end
    local state = states[uf]
    if state and state.visible and state.unit == unit and state.side == sideKey and state.kind == kind
        and state.sides[sideKey].revision == revision and not pending[uf] then return true end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not Accessible(health) then
        Wait(uf)
        return false
    end
    if not state then
        state = New(uf, health)
        states[uf] = state
    end
    local side, current = state.sides[sideKey], true
    if side.revision ~= revision then
        if NS.Client.AuraBuildBlocked() then
            NS.Client.AfterAuraBuild(Display, Display.Resume)
            current = false
        else
            current = ConfigureSide(state, sideKey)
        end
    end
    if not current and not side.revision then
        -- Nothing of this side is complete yet: show it once it is.
        Hide(state)
        Wait(uf)
        return false
    end
    if Show(state, unit, sideKey, kind) and current then
        pending[uf] = nil
        Unwait()
    else
        Wait(uf)
    end
    return true
end

-- Blizzard's own aura switches decide the plate kinds of a lane.
local function NativeCVar(module, _, name)
    if not active or not NS.Public(name) or type(name) ~= "string" or not NATIVE_CVARS[name:lower()] then return end
    local before = revision
    Display.Configure(module.config)
    if revision ~= before then repaint(module) end
end

function Display.Configure(config)
    active = config and config.auraDisplayEnabled == true or false
    if not active then
        Display.Release()
        return
    end
    if not listening then
        owner.context:Event("CVAR_UPDATE", NativeCVar, IN_COMBAT)
        listening = true
    end
    local nextPlan = Model.Plan(config)
    if plan and nextPlan.signature == plan.signature then return end
    nextPlan.font = S.ResolveFont(nextPlan.values.auraFont) or S.GlobalFontPath()
    nextPlan.dispel = DispelOptions(nextPlan.values)
    if not stackOptions then
        local formatter = C_StringUtil.CreateNumericRuleFormatter()
        formatter:SetBreakpoints({ { threshold = 0, format = "" }, { threshold = 1, format = "%d" } })
        stackOptions = { formatter = formatter }
    end
    plan, revision = nextPlan, (revision or 0) + 1
end

function Display.Resume()
    if not next(pending) then return end
    for uf in pairs(pending) do
        local state = states[uf]
        if not active or state and state.restoring then Display.Restore(uf) end
    end
    if active and repaint then repaint(owner) end
    Unwait()
end

function Display.SetEditMode(enabled)
    editMode = enabled == true
end

function Display.Bind(module, refresh)
    owner, repaint = module, refresh
end

function Display.Release()
    active = false
    if listening then
        owner.context:RemoveEvent("CVAR_UPDATE")
        listening = false
    end
    for uf in pairs(states) do Display.Restore(uf) end
    for uf in pairs(pending) do
        if not states[uf] then pending[uf] = nil end
    end
    Unwait()
end
