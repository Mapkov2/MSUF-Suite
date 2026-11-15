local _, Suite = ...
local Text = {}
Suite.DevBarAnimationText = Text

local copies, active, seen, resourceOwners
local floor, max = math.floor, math.max

local function StopCopy(record)
    record.mute:Stop()
    record.copy:Hide()
end

function Text.Clear()
    if not active then return end
    for original, record in pairs(active) do
        StopCopy(record)
        active[original] = nil
    end
    wipe(seen)
    wipe(resourceOwners)
end

function Text.BeginSample()
    if not copies then copies, active, seen, resourceOwners = {}, {}, {}, {} end
    wipe(seen)
    wipe(resourceOwners)
end

function Text.EndSample()
    for original, record in pairs(active) do
        if not seen[original] then
            StopCopy(record)
            active[original] = nil
        end
    end
end

local function Accessible(region)
    if not Suite.Public(region) or not region then return false end
    local forbidden = region:IsForbidden()
    return Suite.Public(forbidden) and not forbidden
end

local function CopyPoints(copy, original, horizontal)
    local count = original:GetNumPoints()
    copy:ClearAllPoints()
    if Suite.Finite(count) then
        for i = 1, count do
            local point, relative, relativePoint, x, y = original:GetPoint(i)
            point = Suite.PublicText(point)
            if point and Suite.Public(relative) then
                copy:SetPoint(point, relative, Suite.PublicText(relativePoint) or point,
                    Suite.Finite(x) and x or 0, Suite.Finite(y) and y or 0)
            end
        end
    end
    if copy:GetNumPoints() == 0 then
        copy:SetPoint(horizontal, original, horizontal)
    end
end

local function CopyFont(record, original)
    local font, size, flags = original:GetFont()
    if not Suite.Public(font) or not font or not Suite.Finite(size) then return end
    flags = Suite.PublicText(flags) or ""
    if record.font ~= font or record.size ~= size or record.flags ~= flags then
        record.copy:SetFont(font, size, flags)
        record.font, record.size, record.flags = font, size, flags
    end
end

local function CopyStyle(record, original, opacity)
    local copy = record.copy
    local horizontal = Suite.PublicText(original:GetJustifyH()) or "CENTER"
    local vertical = Suite.PublicText(original:GetJustifyV()) or "MIDDLE"
    local layer, sublayer = original:GetDrawLayer()
    local wrap = original:CanWordWrap()
    CopyFont(record, original)
    CopyPoints(copy, original, horizontal)
    copy:SetAlpha(opacity)
    copy:SetDrawLayer(Suite.PublicText(layer) or "OVERLAY", Suite.Finite(sublayer) and sublayer or 0)
    copy:SetJustifyH(horizontal)
    copy:SetJustifyV(vertical)
    copy:SetWordWrap(Suite.Public(wrap) and wrap == true)
    local r, g, b, a = original:GetTextColor()
    if Suite.Finite(r) and Suite.Finite(g) and Suite.Finite(b) and Suite.Finite(a) then
        copy:SetTextColor(r, g, b, a)
    else
        copy:SetTextColor(1, 1, 1, 1)
    end
    local sr, sg, sb, sa = original:GetShadowColor()
    local sx, sy = original:GetShadowOffset()
    if Suite.Finite(sr) and Suite.Finite(sg) and Suite.Finite(sb) and Suite.Finite(sa) then
        copy:SetShadowColor(sr, sg, sb, sa)
    end
    if Suite.Finite(sx) and Suite.Finite(sy) then copy:SetShadowOffset(sx, sy) end
end

local function WriteRecord(record, progress)
    local maximum = record.maximum
    if record.kind == "timer" then
        local value = record.countsDown and progress or 1 - progress
        local tenths = floor(value * maximum * 10 + 0.5)
        if record.last ~= tenths then
            record.copy:SetFormattedText("%.1f", tenths / 10)
            record.last = tenths
        end
        return
    end
    local current = floor(progress * maximum + 0.5)
    if record.writer then
        local state = record.state
        state.healthMissing = maximum - current
        record.writer(record.slot, current, maximum, progress * 100, true, state)
    elseif record.last ~= current then
        record.copy:SetFormattedText("%d", current)
        record.last = current
    end
end

local function Bind(original, kind, maximum, countsDown, slot, progress, mute)
    if not Accessible(original) or seen[original] then return end
    local visible = original:IsVisible()
    if not Suite.Public(visible) or not visible then return end
    local opacity = active[original] and active[original].opacity or original:GetAlpha()
    if not Suite.Finite(opacity) or opacity <= 0 then return end
    local parent = original:GetParent()
    if not Accessible(parent) then return end
    local record = copies[original]
    if not record then
        local copy = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        copy:Hide()
        record = { copy = copy, parent = parent, mute = mute(original), slot = {}, state = { healthAbsorb = 0 } }
        copies[original], copies[copy] = record, false
    elseif record.parent ~= parent then
        record.copy:SetParent(parent)
        record.parent = parent
    end
    CopyStyle(record, original, opacity)
    record.kind, record.maximum, record.countsDown, record.opacity = kind, maximum, countsDown, opacity
    record.writer, record.last = nil, nil
    if slot then
        for key, value in pairs(slot) do record.slot[key] = value end
        record.slot.fs = record.copy
        record.writer = slot.plainWriter
    end
    WriteRecord(record, progress)
    seen[original] = true
    if not active[original] then
        active[original] = record
        record.copy:Show()
        record.mute:Play()
    elseif not record.mute:IsPlaying() then
        record.mute:Play()
    end
end

local function Range(source, fallback)
    local low, high = source:GetMinMaxValues()
    if Suite.Finite(low) and Suite.Finite(high) and high > low then
        return high - low
    end
    return fallback
end

local function HealthMaximum(owner)
    local unit = owner.MSUFUnitKey
    if Suite.PublicText(unit) then
        local maximum = UnitHealthMax(unit)
        if Suite.Finite(maximum) and maximum > 0 then return maximum end
    end
    return 100000
end

local function BindUnitTexts(owner, source, kind, progress, mute)
    local layout = owner._msufTextRuntime
    if not layout then return end
    local slots, count, maximum
    if kind == "health" then
        slots, count = layout.healthSlots, layout.healthValueSlotCount or layout.healthSlotCount
    else
        slots, count = layout.powerSlots, layout.powerSlotCount
    end
    if not slots then return end
    maximum = kind == "health" and HealthMaximum(owner) or Range(source, 100)
    for i = 1, count or 0 do
        local slot = slots[i]
        if slot and slot.plainWriter then
            Bind(slot.fs, kind, maximum, nil, slot, progress, mute)
        end
    end
end

local function IsKind(region, kind)
    if not Accessible(region) then return false end
    local matches = region:IsObjectType(kind)
    return Suite.Public(matches) and matches
end

local function ResourceTextRegions(frame, kind, maximum, progress, mute, ...)
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if IsKind(region, "FontString") and copies[region] ~= false then
            local _, relative = region:GetPoint(1)
            if Suite.Public(relative) and relative == frame then
                Bind(region, kind, maximum, nil, nil, progress, mute)
            end
        end
    end
end

local function CountResourceBars(...)
    local count = 0
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        if IsKind(child, "StatusBar") then
            local visible = child:IsVisible()
            if Suite.Public(visible) and visible then count = count + 1 end
        end
    end
    return count
end

local function BindResourceText(owner, source, kind, progress, sequential, mute, ...)
    local maximum = Range(source, kind == "class" and 1 or 100)
    if kind == "class" then
        local bars = CountResourceBars(...)
        if bars > 1 then maximum = sequential and 1 or bars end
    end
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        if IsKind(child, "Frame") and not IsKind(child, "StatusBar") then
            ResourceTextRegions(kind == "class" and child or owner, kind, maximum, progress, mute, child:GetRegions())
        end
    end
end

function Text.Bind(owner, source, kind, progress, sequential, duration, mute)
    if not Accessible(owner) then return end
    if kind == "health" or kind == "power" then
        BindUnitTexts(owner, source, kind, progress, mute)
    elseif kind == "cast" then
        local countsDown = owner._msufCountsDown
        Bind(owner.timeText, "timer", duration, Suite.Public(countsDown) and countsDown == true, nil, progress, mute)
    elseif kind == "swing" then
        local config = owner.config
        Bind(owner.Time, "timer", duration, config and config.fill == "remaining", nil, progress, mute)
    else
        if kind == "class" then Bind(source._runeText, "timer", duration, true, nil, progress, mute) end
        if not resourceOwners[owner] then
            resourceOwners[owner] = true
            BindResourceText(owner, source, kind, progress, sequential, mute, owner:GetChildren())
        end
    end
end

function Text.Write(progress)
    for _, record in pairs(active) do WriteRecord(record, progress) end
end
