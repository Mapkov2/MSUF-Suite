local _, private = ...
local NS, S = private.NS, private.Suite
local Model = NS.NameplateAuraDisplay
-- The Suite creates containers only for explicitly tracked Custom and DoT
-- rows. Blizzard owns their aura evaluation and the standard nameplate rows.
local Display = {}
private.AuraDisplay = Display
local states = setmetatable({}, { __mode = "k" })
local pending = setmetatable({}, { __mode = "k" })
local owner, repaint, plan, revision, waitFrame, stackOptions, targetUF
local active, editMode = false, false
local EMPTY = { includeSpellIDs = {} }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SORT = { "Default", "ExpirationOnly", "NameOnly", "AuraInstanceIDOnly", "ImportantOnly" }
local function SameIDs(left, right)
    if left == right then return true end
    if not left or not right then return false end
    for id in pairs(left) do if not right[id] then return false end end
    for id in pairs(right) do if not left[id] then return false end end
    return true
end
local OUTLINE = { "", "OUTLINE", "THICKOUTLINE" }
local TEXT_SWITCH = { Time = "timeText", Stack = "stackText" }
-- Blizzard makes a group's buttons on demand, one per aura up to the group's
-- frame limit, and each new button costs about half a millisecond of
-- protected set-up (2026-11-11 combat trace: ten buttons, 7.4 ms in the frame
-- a plate got its unit). So a group's limit stays RAMP above the buttons it
-- has, and all plates together are granted FRAME_GRANT new buttons a frame.
-- The grant is counted in allowances, not in buttons made: Blizzard fills an
-- allowance later and the aura count cannot be read here. Plates that appear
-- together therefore do not wait one frame each.
local RAMP, FRAME_GRANT = 3, 6
local ramping = {}
local waiting, waitCount, snapshot = {}, 0, {}
local GROUP_NAMES = { "any", "auras" }
local rampJob, grantAt, granted = nil, 0, 0
local RampStep
local rampBlocked

-- How many of the wanted new allowances this frame's budget still allows.
-- GetTime does not change within a frame.
local function Grant(count)
    local now = GetTime()
    if now ~= grantAt then grantAt, granted = now, 0 end
    local n = math.min(count, FRAME_GRANT - granted)
    if n <= 0 then return 0 end
    granted = granted + n
    return n
end

local function QueueRamp()
    if rampBlocked then return end
    if not rampJob then rampJob = owner.context:Coalesce(0, RampStep) end
    rampJob:Request()
end

-- Native button creation queues the next grant once across all groups.
local function Ramp(record)
    if not active or ramping[record] then return end
    ramping[record] = true
    waitCount = waitCount + 1
    waiting[waitCount] = record
    QueueRamp()
end

local function ResumeRamp()
    rampBlocked = nil
    if active and waitCount > 0 then QueueRamp() end
end

-- Raises each waiting group's limit by what this frame's budget allows, up to
-- the buttons it has plus RAMP. A group still short of its want stays waiting.
-- The small groups go first, so the one-button "any" group is never starved.
RampStep = function()
    if NS.Client.AuraBuildBlocked() then
        rampBlocked = true
        NS.Client.AfterAuraBuild(ramping, ResumeRamp)
        return
    end
    -- Only groups that ran out of allowances queue another pass.
    local count = waitCount
    for index = 1, count do
        snapshot[index] = waiting[index]
        waiting[index] = nil
    end
    waitCount = 0
    for index = 1, count do
        local record = snapshot[index]
        snapshot[index] = nil
        ramping[record] = nil
        if record.shown then
            for slot = 1, #GROUP_NAMES do
                local name = GROUP_NAMES[slot]
                local want = record.want[name]
                if want then
                    local allowed = record.allowed[name]
                    local need = math.min(want, (record.made[name] or 0) + RAMP) - allowed
                    if need > 0 then
                        local n = Grant(need)
                        if n > 0 then
                            allowed = allowed + n
                            record.allowed[name] = allowed
                            record.frame:SetAuraGroupMaxFrameCount(name, allowed)
                        end
                        if n < need then Ramp(record) end
                    end
                end
            end
        end
    end
end

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

function Display.Restore(uf)
    if targetUF == uf then targetUF = nil end
    local state = states[uf]
    if state and state.visible then
        if private.Auras and state.duplicateTracked then
            private.Auras.SetDuplicateState(uf, nil)
            state.duplicateTracked = nil
        end
        if Accessible(state.wrapper) then state.wrapper:Hide() end
        for _, side in pairs(state.sides) do
            for _, record in pairs(side.records) do
                if Accessible(record.frame) then record.frame:SetEnabled(false) end
                for _, slot in ipairs(record.slots) do slot.anchor:Hide() end
                record.unit, record.shown = nil, false
            end
        end
        state.visible = false
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

-- AddDispelTypeTexture copies and processes these options on every call,
-- four times a button (2026-11-10 combat trace: 0.83 ms a button). A colour
-- object carries all its methods; the map's documented element is colorRGB,
-- so it gets the three numbers only.
local function Plain(color)
    local r, g, b = color:GetRGB()
    return { r = r, g = g, b = b }
end

local function DispelOptions(values)
    local assets, colors = {}, {}
    if values.auraDispelHighlight then
        for _, key in ipairs({ "Magic", "Curse", "Disease", "Poison", "Bleed" }) do
            assets[key] = { asset = WHITE }
            colors[key] = Plain(AuraUtil.GetAuraBorderColor(key))
        end
    end
    if values.auraEnrageHighlight then
        -- Enrages use the empty dispel-name token on legacy clients. The
        -- named token is accepted too, without treating nil as an enrage.
        assets[""], assets.Enrage = { asset = WHITE }, { asset = WHITE }
        colors[""], colors.Enrage = { r = 1, g = .55, b = .1 }, { r = 1, g = .55, b = .1 }
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

-- Same highlights, assets and colours: the next plan keeps the options table,
-- which is what a button's binding is compared by. Style and the show flags
-- are constants; every colour key has its asset key.
local function SameDispel(left, right)
    local assets, colors = left.customDispelAssetMap, left.customDispelColorMap
    local otherAssets, otherColors = right.customDispelAssetMap, right.customDispelColorMap
    for key, color in pairs(colors) do
        local other, asset = otherColors[key], otherAssets[key]
        if not other or not asset or asset.asset ~= assets[key].asset
            or other.r ~= color.r or other.g ~= color.g or other.b ~= color.b then return false end
    end
    for key in pairs(otherColors) do if not colors[key] then return false end end
    return true
end

-- Blizzard keeps a button's dispel textures and their copied options until
-- ClearDispelTypeTextures (CustomAuraButton.lua: set in OnLoad_Intrinsic and
-- there only), through SetUnit and every aura update. part.dispelBound is the
-- options table the button holds, false for none, nil while unknown.
local function BindDispel(record, part)
    local want = record.c.dispel and plan.dispel or false
    part.dispelBound = nil
    if want then part.button:AddDispelTypeTexture(part.dispel, want) end
    part.dispelBound = want
end

-- A restyle that leaves the binding as it is costs no protected call
-- (2026-11 Forever traces: 0.148-0.871 ms a rebind).
local function RebindDispel(record, part)
    local bound = part.dispelBound
    if bound == (record.c.dispel and plan.dispel or false) then return end
    part.dispelBound = nil
    if bound ~= false then part.button:ClearDispelTypeTextures() end
    BindDispel(record, part)
end

-- One texture behind the icon, a highlight's width larger on every side: the
-- icon covers its middle, so it shows as a ring. Every bound dispel texture
-- costs a protected call with the full options (2026-11-10 combat trace:
-- four edges, 0.83 ms a button), so there is only this one.
local function Ring(texture, button, width)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", button, "TOPLEFT", -width, width)
    texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", width, -width)
end

local function DurationBar(part, c)
    local button, bar = part.button, part.durationBar
    if not c.durationBar then
        if bar then
            button:ClearDurationBar()
            bar:Hide()
        end
        return
    end
    if not bar then
        bar = CreateFrame("StatusBar", nil, button)
        bar:SetStatusBarTexture(WHITE)
        bar:SetFrameLevel(button:GetFrameLevel() + 2)
        bar:SetMinMaxValues(0, 1)
        part.durationBar = bar
    end
    local edge, y = c.durationBarTop and "TOP" or "BOTTOM", c.durationBarTop and -1 or 1
    bar:ClearAllPoints()
    bar:SetPoint(edge .. "LEFT", button, edge .. "LEFT", 1, y)
    bar:SetPoint(edge .. "RIGHT", button, edge .. "RIGHT", -1, y)
    bar:SetHeight(c.durationBarHeight)
    bar:SetStatusBarColor(NS.RGB(c.durationBarColor))
    bar:Show()
    local direction = Enum.StatusBarTimerDirection
    button:SetDurationBar(bar, { direction = c.durationBarElapsed and direction.ElapsedTime or direction.RemainingTime })
end

-- The native binding formats protected durations. One immutable formatter
-- per slider value; the default path never builds a formatter.
local durationTextOptions = {}
local function DurationText(part, decimals)
    if part.timeDecimals == decimals then return end
    local options = durationTextOptions[decimals]
    if not options and decimals > 0 then
        local up, down = Enum.NumericRuleFormatRounding.Up, Enum.NumericRuleFormatRounding.Down
        local formatter = C_StringUtil.CreateNumericRuleFormatter()
        formatter:SetBreakpoints({
            { threshold = 0, step = .1, rounding = up, min = .1, format = "%.1f" },
            { threshold = decimals, step = 1, rounding = up, format = "%.0f" },
            { threshold = 60, format = "%d:%02d", rounding = down,
                components = { { div = 60, rounding = down }, { mod = 60, rounding = down } } },
            { threshold = 3600, format = "%d:%02d", rounding = down,
                components = { { div = 3600, rounding = down }, { div = 60, mod = 60, rounding = down } } },
        })
        options = { textFormatter = formatter }
        durationTextOptions[decimals] = options
    end
    part.button:SetDurationText(part.Time, options)
    part.timeDecimals = decimals
end

local function StylePart(record, part)
    local c, values, button = record.c, plan.values, part.button
    local mouse = c.tooltip and not c.clickthrough
    button:SetSize(c.width, c.height)
    button:SetAlpha(c.alpha)
    button:SetMouseClickEnabled(mouse)
    button:SetMouseMotionEnabled(mouse)
    part.icon:SetTexCoord(c.crop, 1 - c.crop, c.crop, 1 - c.crop)
    local look = c.iconSkin and plan.iconLook
    if look or part.skinned then
        part.skinned = NS.HostBridge.PaintIconSkin(button, look or nil, c.width, c.height, part.icon, true)
    end
    Font(part, c, "Time")
    Font(part, c, "Stack")
    DurationBar(part, c)
    part.icon:SetAlpha(c.barOnly and 0 or 1)
    part.cooldown:SetReverse(c.swipeReverse)
    part.cooldown:SetAlpha(not c.barOnly and values.auraSwipe and c.swipe and values.auraSwipeAlpha / 100 or 0)
    Ring(part.dispel, button, values.auraHighlightSize)
    Border(part.pandemicEdges, part.pandemicStyle, values.auraHighlightSize)
    for _, texture in ipairs(part.pandemicEdges) do texture:SetColorTexture(NS.RGB(values.auraPandemicColor)) end
    part.pandemicStyle:SetShown(values.auraPandemicHighlight and c.pandemic)
    if part.bound then
        DurationText(part, c.timeDecimals)
        RebindDispel(record, part)
        button:SetApplicationCount(part.Stack, Any(part) and stackOptions or nil)
    end
end

local function Advance(record, name)
    local made = (record.made[name] or 0) + 1
    record.made[name] = made
    if made >= record.allowed[name] and record.allowed[name] < record.want[name] then Ramp(record) end
end

local function Initialize(record, button, slot, anyGroup)
    local level = button:GetFrameLevel()
    local part = { button = button, slot = slot, anyGroup = anyGroup == true }
    part.icon = button:CreateTexture(nil, "ARTWORK")
    part.icon:SetAllPoints(button)
    part.dispel = button:CreateTexture(nil, "BACKGROUND")
    part.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    part.cooldown:SetAllPoints(button)
    part.cooldown:SetDrawBling(false)
    part.cooldown:SetHideCountdownNumbers(true)
    part.cooldown:SetFrameLevel(level + 1)
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
    DurationText(part, record.c.timeDecimals)
    button:SetApplicationCount(part.Stack, Any(part) and stackOptions or nil)
    BindDispel(record, part)
    button:AddPandemicRegion(part.pandemic)
    part.bound = true
    record.parts[#record.parts + 1] = part
    if not slot then
        -- A group's button filled its allowance: the group may take more.
        Advance(record, anyGroup == true and "any" or "auras")
    end
end

local function NewRecord(state, c)
    local frame = CreateFrame("AuraContainer", nil, state.wrapper, "CustomAuraContainerTemplate")
    frame:SetEnabled(false)
    NS.Client.RealAurasOnly(frame)
    return { frame = frame, parts = {}, slots = {}, groups = {}, key = c.key, made = {}, want = {}, allowed = {} }
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
    frame:SetFlowLayoutPadding(c.padding, c.padding, c.padding, c.padding)
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
local function Slots(state, record, c, excluded)
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
        slot.texture:SetShown(c.missing and not (excluded and excluded[row.id]))
        slot.anchor:SetShown(record.shown == true)
        slot.any = row.any
        local candidate = Model.Excluding(row.candidate, excluded)
        if not slot.added then
            record.frame:AddAuraSlot(slot.key, row.filter, { candidateFilters = candidate,
                sortMethod = AuraContainerSortMethod.ExpirationOnly,
                initializeFrame = function(button) Initialize(record, button, slot) end })
            slot.added = true
        else
            record.frame:SetAuraSlotCandidateFilters(slot.key, candidate)
            record.frame:SetAuraSlotFilterString(slot.key, row.filter)
        end
    end
    ClearSlots(record, #c.rows + 1)
end

-- Flow: one native aura group packs the active auras; auras from every
-- player (index 2) need their own filter and follow as a second group.
local function Group(record, c, name, index, filter, candidate, count)
    local frame = record.frame
    -- The limit is set before the group exists: Blizzard may make buttons at once.
    -- A group that is still short after its buttons fill is ramped by Initialize.
    if not record.groups[name] then
        if count == 0 then return end
        record.want[name], record.made[name] = count, record.made[name] or 0
        local allowed = Grant(math.min(count, RAMP))
        record.allowed[name] = allowed
        frame:AddAuraGroup(name, filter, { maxFrameCount = allowed, candidateFilters = candidate,
            initializeFrame = function(button) Initialize(record, button, nil, index == 2) end })
        record.groups[name] = true
        if record.made[name] >= allowed and allowed < count then Ramp(record) end
    else
        record.want[name] = count
        frame:SetAuraGroupFilterString(name, filter)
        frame:SetAuraGroupCandidateFilters(name, count > 0 and candidate or EMPTY)
        if count > 0 then
            -- A settings change takes no grant from the frame budget.
            local allowed = math.min(count, record.made[name] + RAMP)
            record.allowed[name] = allowed
            frame:SetAuraGroupMaxFrameCount(name, allowed)
            if record.made[name] >= allowed and allowed < count then Ramp(record) end
        end
    end
    local layout = { elementWidth = c.width, elementHeight = c.height, elementSpacing = c.gap, lineSpacing = c.gap }
    if c.anyCount > 0 or record.groups.any then
        layout.groupSpacing, layout.groupLineSpacing, layout.layoutIndex = c.gap, c.gap, index
    end
    frame:SetAuraGroupLayout(name, layout)
    frame:SetAuraGroupSortMethod(name, AuraContainerSortMethod[SORT[c.sort]],
        c.reverse and AuraContainerSortDirection.Reverse or AuraContainerSortDirection.Normal)
end

-- A button this pass makes is styled by Initialize and sealed by Blizzard as
-- soon as that returns, so only the buttons from before take the new style.
local function Configure(state, record, c, excluded)
    local styled = #record.parts
    record.c = c
    if c.hideDuplicates and not record.dedup then record.dedup, record.auras = {}, {} end
    if c.enabled then
        Place(state, record, c)
        if c.fixed then
            ClearGroups(record)
            Slots(state, record, c, excluded)
        else
            ClearSlots(record, 1)
            Group(record, c, "auras", 1, c.filter, Model.Excluding(c.candidate, excluded), c.groupCount)
            Group(record, c, "any", 2, c.anyFilter, Model.Excluding(c.anyCandidate, excluded), c.anyCount)
        end
        for index = 1, styled do StylePart(record, record.parts[index]) end
    end
    record.sig, record.style, record.iconLook = c.sig, plan.style, plan.iconLook
    record.excluded = excluded
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
local function ConfigureSide(state, sideKey, target)
    local side, mutable = state.sides[sideKey], nil
    local exclusions = plan.exclusions[sideKey]
    for _, c in ipairs(plan.scopes[sideKey]) do
        local record = side.records[c.key]
        if not record and c.enabled and (c.kind ~= "dots" or target) then
            record = NewRecord(state, c)
            side.records[c.key] = record
        end
        local skinChanged = record and c.iconSkin and record.iconLook ~= plan.iconLook
        local excluded = exclusions and exclusions[c.key]
        if record and (record.sig ~= c.sig or record.style ~= plan.style or skinChanged
            or not SameIDs(record.excluded, excluded)) then
            if record.sig or record.parts[1] then
                if mutable == nil then mutable = Mutable(side) end
                if not mutable then return false end
            end
            Configure(state, record, c, excluded)
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
    local state = { uf = uf, wrapper = wrapper, health = health, visible = false,
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

local function Show(state, unit, sideKey, target)
    for key, side in pairs(state.sides) do
        for _, record in pairs(side.records) do
            local c = record.c
            local shown = key == sideKey and c.enabled and (c.kind ~= "dots" or target)
            if shown and (record.unit ~= unit or not record.shown) then record.frame:SetUnit(unit) end
            if record.shown ~= shown then
                record.frame:SetEnabled(shown)
                if shown then
                    for _, name in ipairs(GROUP_NAMES) do
                        local allowed = record.allowed[name]
                        if allowed and allowed < record.want[name] and (record.made[name] or 0) >= allowed then Ramp(record) end
                    end
                end
                for index, slot in ipairs(record.slots) do slot.anchor:SetShown(shown and c.fixed and index <= #c.rows) end
            end
            record.unit, record.shown = shown and unit or nil, shown
        end
    end
    local shown = true
    if state.native then
        shown = Accessible(state.native) and state.native:IsShown()
        shown = NS.Public(shown) and shown == true
    end
    state.wrapper:SetShown(shown)
    state.visible, state.unit, state.side, state.target = true, unit, sideKey, target
end

local function Used(unit, sideKey)
    -- Side-effect-free tests, cheapest first: a plate add with the display off
    -- reads two upvalues (suite_nameplates_contract plate-add budget).
    if not active or editMode or not NS.Public(unit) or type(unit) ~= "string" then return false end
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
    local target = false
    if plan.targetOnly[sideKey] then
        local selected = UnitIsUnit(unit, "target")
        target = NS.Public(selected) and selected == true
        if target then targetUF = uf end
    end
    if not target and not plan.always[sideKey] then
        Display.Restore(uf)
        return false
    end
    local state = states[uf]
    if state and state.visible and state.unit == unit and state.side == sideKey and state.target == target
        and state.sides[sideKey].revision == revision and not pending[uf] then
        return true
    end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not Accessible(health) then
        Wait(uf)
        return false
    end
    if not state then
        local native = uf.AurasFrame
        if native and not Accessible(native) then
            Wait(uf)
            return false
        end
        state = New(uf, health)
        states[uf] = state
    end
    local side, current = state.sides[sideKey], true
    if side.revision ~= revision or (target and not side.records.dots and plan.targetOnly[sideKey]) then
        if NS.Client.AuraBuildBlocked() then
            NS.Client.AfterAuraBuild(Display, Display.Resume)
            current = false
        else
            current = ConfigureSide(state, sideKey, target)
        end
    end
    if not current and not side.revision then
        -- Nothing of this side is complete yet: show it once it is.
        Display.Restore(uf)
        Wait(uf)
        return false
    end
    Show(state, unit, sideKey, target)
    if current then
        pending[uf] = nil
        Unwait()
    else
        Wait(uf)
    end
    local exclusions = current and plan.exclusions[sideKey]
    if private.Auras and (exclusions or state.duplicateTracked) then
        state.duplicateTracked = exclusions and (exclusions.buff or exclusions.debuff)
        private.Auras.SetDuplicateState(uf, state.duplicateTracked and state, exclusions)
    end
    return true
end

-- Target changes repaint just the previously selected and the new plate.
local function RefreshTarget(uf)
    if private.IsSkinSuppressed and private.IsSkinSuppressed(uf) then return end
    if not Accessible(uf) then return end
    local unit, friendly = uf.unit, uf.isFriend
    if NS.Public(unit) and NS.Public(friendly) then Display.Apply(uf, unit, friendly == false) end
end

function Display.TargetChanged(current)
    if not active or not next(plan.targetOnly) then return end
    local previous = targetUF
    targetUF = nil
    if previous ~= current then RefreshTarget(previous) end
    RefreshTarget(current)
end

function Display.Configure(config)
    active = config and Model.Active(config) or false
    if not active then
        Display.Release()
        return
    end
    local nextPlan = Model.Plan(config)
    local bridge = NS.HostBridge
    if bridge and nextPlan.iconSkin then
        nextPlan.iconLook = bridge.IconSkinLook(nil, "RECTANGLE", nil, true)
        bridge.WatchIconSkins("nameplates", true)
    elseif bridge and plan and plan.iconSkin then
        bridge.WatchIconSkins("nameplates", false)
    end
    if plan and nextPlan.signature == plan.signature and nextPlan.iconLook == plan.iconLook then return end
    nextPlan.font = S.ResolveFont(nextPlan.values.auraFont) or S.GlobalFontPath()
    local dispel, held = DispelOptions(nextPlan.values), plan and plan.dispel
    nextPlan.dispel = held and SameDispel(held, dispel) and held or dispel
    if not stackOptions then
        local formatter = C_StringUtil.CreateNumericRuleFormatter()
        formatter:SetBreakpoints({ { threshold = 0, format = "" }, { threshold = 1, format = "%d" } })
        stackOptions = { formatter = formatter }
    end
    plan, revision = nextPlan, (revision or 0) + 1
end

function Display.Resume()
    if not next(pending) then return end
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
    active, targetUF = false, nil
    if NS.HostBridge and plan and plan.iconSkin then NS.HostBridge.WatchIconSkins("nameplates", false) end
    plan = nil
    if rampJob then rampJob:Cancel() end
    if rampBlocked then
        NS.Client.CancelAuraBuild(ramping)
        rampBlocked = nil
    end
    for index = 1, waitCount do
        ramping[waiting[index]], waiting[index] = nil, nil
    end
    waitCount = 0
    for uf in pairs(states) do Display.Restore(uf) end
    for uf in pairs(pending) do
        if not states[uf] then pending[uf] = nil end
    end
    Unwait()
end
