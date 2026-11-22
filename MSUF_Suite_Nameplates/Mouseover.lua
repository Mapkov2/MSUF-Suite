local _, private = ...
local NS = private.NS
local Style = NS.NameplateStyle
local LOOK_BLIZZARD = private.Mode.LOOK_BLIZZARD
local Prefix = private.PlatePrefix
-- A highlight on the skinned nameplate under the mouse (Blizzard indicators >
-- Target and focus). UPDATE_MOUSEOVER_UNIT reports a change of the mouseover
-- unit; Blizzard's compact frames set and clear their mouseover highlight on
-- this event alone (CompactUnitFrame_UpdateSelectionHighlight, upstream/live
-- and forever). Only the plate that lost the mouse and the one that gained it
-- repaint, as on a target change (Skin.lua OnTargetChanged). The event is
-- registered only while the setting is on; the highlight is the Suite's own
-- texture on the health bar (NameplateStyle.lua CreateHighlight), made on a
-- plate's first highlight.
local Hover = {}
private.Mouseover = Hover
local M
local IN_COMBAT = { inCombat = true }
local highlights = setmetatable({}, { __mode = "k" })
-- The unit frame highlighted now, and the color of the current settings.
local hovered, color
local listening, highlight, outline = false, false, false
local plans, plates = {}, setmetatable({}, { __mode = "k" })
local animations = setmetatable({}, { __mode = "k" })
local visibilityActive = false
local opacity = setmetatable({}, { __mode = "k" })
local ALWAYS = {}
local pointerNames = setmetatable({}, { __mode = "k" })
local textHovered, pointerTicker
local POINTER_INTERVAL = 0.05

function Hover.Bind(module) M = module end
function Hover.IsHovered(uf) return hovered == uf end

local function Safe(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

local function HealthBar(uf)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if Safe(health) then return health end
end

local function Hide(uf)
    local health = HealthBar(uf)
    local texture = health and highlights[health]
    if texture then texture:Hide() end
end

local function Show(uf)
    local health = HealthBar(uf)
    if not health then return end
    local texture = highlights[health]
    if not texture then
        texture = Style.CreateHighlight(health)
        highlights[health] = texture
    end
    if texture._npColor ~= color then
        Style.PaintHighlight(texture, color)
        texture._npColor = color
    end
    texture:Show()
end

-- Whether the skin styles this plate's side.
local function Styled(uf)
    local prefix = Safe(uf) and Prefix(uf)
    return prefix and M.config[prefix] and (not private.IsSkinSuppressed or not private.IsSkinSuppressed(uf))
end

local function Writable(region)
    if not Safe(region) then return false end
    local allowed = region:CanBeAccessedInContext()
    return NS.Public(allowed) and allowed == true
end

local function Alpha(region, record, target, duration)
    if not Writable(region) then return false end
    local current = record.alpha
    if record.running then
        if duration > 0 and target == record.target then return true end
        current = record.from + (record.target - record.from) * record.animation:GetProgress()
        record.group:Stop()
        record.running = nil
        region:SetAlpha(current)
        record.alpha = current
    end
    if current == target then return true end
    if duration == 0 then
        region:SetAlpha(target)
        record.alpha = target
        return true
    end
    if not record.group then
        if NS.InCombat() then return Alpha(region, record, target, 0) end
        local cached = animations[region]
        if not cached then
            local group = region:CreateAnimationGroup()
            group:SetToFinalAlpha(true)
            cached = { group = group, animation = group:CreateAnimation("Alpha") }
            group:SetScript("OnFinished", function()
                local live = cached.record
                if live then live.alpha, live.running = live.target, nil end
            end)
            animations[region] = cached
        end
        cached.record = record
        record.group, record.animation = cached.group, cached.animation
    end
    record.from, record.target, record.running = current, target, true
    record.animation:SetFromAlpha(current)
    record.animation:SetToAlpha(target)
    record.animation:SetDuration(duration)
    record.group:Play()
    return true
end

local function ReleaseText(records, region)
    records[region] = nil
    local cached = animations[region]
    if cached then cached.record = nil end
end

local function Reveal(uf, over, instant)
    local records = plates[uf]
    if not records then return end
    for region, record in pairs(records) do
        local rule = record.rule
        local target = rule and (rule.hidden or rule.mouse and not over) and 0 or record.original * (record.multiplier or 1)
        local duration = not instant and rule and rule.mouse and (over and rule.fadeIn or rule.fadeOut) or 0
        record.retry = not Alpha(region, record, target, duration)
        if not record.retry and not rule then ReleaseText(records, region) end
    end
    if not next(records) then plates[uf] = nil end
end

local function SetTextHovered(uf)
    if textHovered == uf then return end
    if textHovered then Reveal(textHovered, false) end
    textHovered = uf
    if uf then Reveal(uf, true) end
end

local function StopTrackingName(uf)
    pointerNames[uf] = nil
    if textHovered == uf and hovered ~= uf then SetTextHovered(nil) end
    if pointerTicker and not next(pointerNames) then
        pointerTicker:Cancel()
        pointerTicker = nil
    end
end

-- The group-only filter takes ownership of the name's native alpha first.
function Hover.ReleaseName(uf, label)
    local records = plates[uf]
    local record = records and records[label]
    if not record then return true end
    if not Alpha(label, record, record.original, 0) then return false end
    ReleaseText(records, label)
    if pointerNames[uf] then StopTrackingName(uf) end
    return true
end

local function NameUnderPointer(uf, label)
    if not Safe(uf) or not Writable(label) then return false end
    -- Access to alpha does not grant frame measurement on native nameplates.
    local restricted = label:IsAnchoringRestricted()
    if not NS.Public(restricted) or restricted ~= false then return false end
    local visible = label:IsVisible()
    if not NS.Public(visible) or visible ~= true then return false end
    local over = label:IsMouseOver()
    return NS.Public(over) and over == true
end

-- Blizzard removes the hit-test area of name-only plates. Check only the
-- managed friendly name labels, without taking mouse focus or clicks.
local function PointerTick()
    if hovered then return end
    if IsMouselooking() then return SetTextHovered(nil) end
    local focus = GetMouseFoci()[1]
    if NS.Public(focus) and (not focus or focus == WorldFrame) then
        local current = textHovered and pointerNames[textHovered]
        if current and NameUnderPointer(textHovered, current) then return end
        for uf, label in pairs(pointerNames) do
            if uf ~= textHovered and NameUnderPointer(uf, label) then return SetTextHovered(uf) end
        end
    end
    SetTextHovered(nil)
end

local function Claim(records, region, rule, multiplier)
    if not rule and (not multiplier or multiplier == 1) or not Writable(region) then return end
    local record = records[region]
    if not record then
        local alpha = region:GetAlpha()
        if not NS.Finite(alpha) then return end
        record = { original = alpha, alpha = alpha }
        records[region] = record
    end
    record.rule, record.multiplier = rule or ALWAYS, multiplier
end

function Hover.Apply(uf, health, prefix, styled)
    local records, fade = plates[uf], styled and opacity[uf]
    if not visibilityActive and not records and not fade then return end
    local plan = styled and plans[prefix]
    if not plan and not fade and not records then return end
    if records then
        for _, record in pairs(records) do
            record.previousRule, record.rule = record.rule, nil
            record.previousMultiplier, record.multiplier = record.multiplier, nil
        end
    end
    local label
    if plan or fade then
        plan = plan or ALWAYS
        records = records or {}
        plates[uf] = records
        local text = fade and fade.text
        if not M.friendlyNames[uf.name] and (plan.name or fade and fade.name ~= 1) then
            label = uf.name
            Claim(records, label, plan.name, fade and fade.name)
        end
        Claim(records, health.Text, plan.hp, text)
        Claim(records, health.LeftText, plan.hp, text)
        Claim(records, health.RightText, plan.hp, text)
        if plan.power or fade and fade.power then
            Claim(records, private.Power.TextRegion(uf), plan.power, fade and fade.power)
        end
    end
    local changed = false
    for _, record in pairs(records) do
        changed = changed or record.previousRule ~= record.rule or record.previousMultiplier ~= record.multiplier or record.retry
        record.previousRule, record.previousMultiplier = nil, nil
    end
    if changed then Reveal(uf, textHovered == uf, true) end
    if prefix == "friendly" and plan and plan.name and plan.name.mouse then
        local record = label and records[label]
        if record and record.rule == plan.name then
            pointerNames[uf] = label
            if not pointerTicker then pointerTicker = M.context:Ticker(POINTER_INTERVAL, PointerTick) end
        elseif pointerNames[uf] then
            StopTrackingName(uf)
        end
    elseif pointerNames[uf] then
        StopTrackingName(uf)
    end
    if not next(records) then plates[uf] = nil end
    if not visibilityActive and not next(plates) then Hover.textInUse = false end
end

function Hover.SetOpacity(uf, health, prefix, text, power, cast)
    if not Safe(uf) or not Safe(health) then return end
    local current = opacity[uf]
    local name = text and text * cast
    if not text or text == 1 and power == 1 and name == 1 then
        if not current then return end
        opacity[uf] = nil
    elseif not current or current.text ~= text or current.power ~= power or current.name ~= name then
        opacity[uf] = { text = text, power = power, name = name }
    end
    Hover.Apply(uf, health, prefix, true)
    if opacity[uf] then Hover.textInUse = true end
end

local function OnMouseover()
    local plate = C_NamePlate.GetNamePlateForUnit("mouseover")
    local current = Safe(plate) and plate.UnitFrame or nil
    if current and not Styled(current) then current = nil end
    if current == hovered then return end
    if hovered then
        if highlight then Hide(hovered) end
        if outline then private.Selection.HighlightMouseover(hovered, false) end
    end
    local previous = hovered
    hovered = current
    if private.EasyFeatures then
        if previous then private.EasyFeatures.Hover(previous) end
        if current then private.EasyFeatures.Hover(current) end
    end
    if current then
        if highlight then Show(current) end
        if outline then private.Selection.HighlightMouseover(current, true) end
    end
    SetTextHovered(current)
end

local function Clear()
    if hovered then
        Hide(hovered)
        if outline then private.Selection.HighlightMouseover(hovered, false) end
    end
    hovered = nil
end

local function VisibilityRule(config, key)
    local hidden = config[key .. "Visible"] == false
    if key == "enemyPowerText" and config.enemyPowerTextVisible ~= true then return end
    local mouse = config[key .. "Mouseover"] == true and not hidden
    if not hidden and not mouse then return end
    return { hidden = hidden, mouse = mouse, fadeIn = config[key .. "FadeIn"] or 0, fadeOut = config[key .. "FadeOut"] or 0 }
end

local function TextPlans(config)
    visibilityActive = false
    for _, side in ipairs({ "enemy", "friendly" }) do
        local name, hp, power
        if config.look ~= LOOK_BLIZZARD and config[side] then
            name, hp = VisibilityRule(config, side .. "Name"), VisibilityRule(config, side .. "HealthText")
            if side == "enemy" then power = VisibilityRule(config, "enemyPowerText") end
        end
        plans[side] = (name or hp or power) and { name = name, hp = hp, power = power } or nil
        visibilityActive = visibilityActive or plans[side] ~= nil
    end
end

-- Settings changed (Skin.lua Refresh): the event follows the setting, and
-- the plate under the mouse takes the new color or loses its highlight.
function Hover.Configure(hasPatterns)
    local c = M.config
    TextPlans(c)
    Hover.textInUse = visibilityActive or next(plates) ~= nil
    local enemy, friendly = plans.enemy, plans.friendly
    local function Mouse(plan)
        return plan and (plan.name and plan.name.mouse or plan.hp and plan.hp.mouse or plan.power and plan.power.mouse)
    end
    highlight = c.mouseoverHighlight == true and c.look ~= LOOK_BLIZZARD
    outline = c.highlightMouseover == true and c.look ~= LOOK_BLIZZARD
    local on = highlight or outline or hasPatterns or Mouse(enemy) or Mouse(friendly)
    color = c.mouseoverHighlightColor or "ffffff"
    if on and not listening then
        M.context:Event("UPDATE_MOUSEOVER_UNIT", OnMouseover, IN_COMBAT)
        listening = true
    elseif not on and listening then
        M.context:RemoveEvent("UPDATE_MOUSEOVER_UNIT")
        listening = false
    end
    Clear()
    if on then OnMouseover() end
    if not hovered and textHovered and not pointerNames[textHovered] then SetTextHovered(nil) end
end

-- A plate that leaves (Skin.lua RestorePlate) takes its highlight along.
function Hover.Restore(uf)
    opacity[uf] = nil
    if textHovered == uf then textHovered = nil end
    if pointerNames[uf] then StopTrackingName(uf) end
    if Safe(uf) and highlight then Hide(uf) end
    local records = plates[uf]
    if records then
        for _, record in pairs(records) do record.rule, record.multiplier = nil, nil end
        Reveal(uf, false, true)
    end
    if hovered == uf then hovered = nil end
end

function Hover.Disable()
    Clear()
    textHovered = nil
    for uf in pairs(plates) do Hover.Restore(uf) end
    listening, highlight, outline, visibilityActive = false, false, false, false
    Hover.textInUse = next(plates) ~= nil
end
