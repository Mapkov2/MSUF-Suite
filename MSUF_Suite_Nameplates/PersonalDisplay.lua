local _, private = ...
local NS, S = private.NS, private.Suite
local Personal = {}
private.PersonalDisplay = Personal

local default, suiteTexture, compact = 1, 2, 3
local flat = "Interface\\Buttons\\WHITE8X8"
local ownEvents = { "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }
local owner, eventFrame, current
local active, waiting

local function Available(region)
    if not NS.Public(region) or not region or NS.Safety.IsForbidden(region) then return false end
    if not region.CanBeAccessedInContext then return true end
    local canAccess = region:CanBeAccessedInContext()
    return NS.Public(canAccess) and canAccess == true
end

local function RestoreBar(saved)
    if not saved or not Available(saved.bar) then return end
    if saved.atlas then
        local texture = saved.bar:GetStatusBarTexture()
        if Available(texture) then texture:SetAtlas(saved.atlas) end
    else
        saved.bar:SetStatusBarTexture(saved.texture)
    end
end

local function PaintBar(saved, bar, texture)
    if saved and (saved.bar ~= bar or not texture) then
        RestoreBar(saved)
        saved = nil
    end
    if not texture or not Available(bar) then return saved end
    local image = bar:GetStatusBarTexture()
    if not Available(image) then return saved end
    local file, atlas = image:GetTexture(), image:GetAtlas()
    if not NS.Public(file) or not NS.Public(atlas) then return saved end
    if not saved or saved.applied and (file ~= saved.applied or atlas) then
        if not file and not atlas then return saved end
        saved = { bar = bar, texture = file, atlas = atlas }
    end
    if file ~= texture or atlas then bar:SetStatusBarTexture(texture) end
    image = bar:GetStatusBarTexture()
    local applied = Available(image) and image:GetTexture()
    saved.applied = NS.Public(applied) and applied or nil
    return saved
end

local function Height(saved, region, height)
    if saved and (not height or saved.region ~= region) then
        if Available(saved.region) then saved.region:SetHeight(saved.height) end
        saved = nil
    end
    if not height or not Available(region) then return saved end
    local native = region:GetHeight()
    if not S.Finite(native) then return saved end
    if not saved or native ~= saved.applied then saved = { region = region, height = native } end
    if native ~= height then region:SetHeight(height) end
    saved.applied = height
    return saved
end

local function AuraButton(button)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(.07, .93, .07, .93)
    local clock = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    clock:SetAllPoints(button)
    clock:SetDrawBling(false)
    button:SetMouseClickEnabled(false)
    button:SetMouseMotionEnabled(false)
    button:SetIcon(icon)
    button:SetDurationCooldown(clock)
end

local function CreateAuras(parent)
    local frame = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    frame:SetEnabled(false)
    NS.Client.RealAurasOnly(frame)
    frame:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
    frame:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.LeftToRight, AnchorUtil.FlowDirection.BottomToTop)
    return { frame = frame, added = {} }
end

local function AuraGroup(auras, key, filter, count, size, index)
    local frame = auras.frame
    if not auras.added[key] then
        if count == 0 then return end
        frame:AddAuraGroup(key, filter, { maxFrameCount = count, initializeFrame = AuraButton })
        auras.added[key] = true
    else
        frame:SetAuraGroupMaxFrameCount(key, count)
    end
    frame:SetAuraGroupLayout(key, { elementWidth = size, elementHeight = size, elementSpacing = 3,
        lineSpacing = 3, groupSpacing = 3, groupLineSpacing = 3, layoutIndex = index })
end

local function Auras(record, config)
    local mode = config and config.nameplatePersonalAuras or 1
    if mode == 1 then
        if record.auras then record.auras.frame:SetEnabled(false) end
        return
    end
    if NS.Client.AuraBuildBlocked() then
        NS.Client.AfterAuraBuild(Personal, Personal.Refresh)
        return
    end
    local count, size = config.nameplatePersonalAuraCount or 6, config.nameplatePersonalAuraSize or 20
    local auras = record.auras or CreateAuras(record.frame)
    record.auras = auras
    if mode ~= auras.mode or count ~= auras.count or size ~= auras.size then
        local frame = auras.frame
        frame:SetEnabled(false)
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", record.frame, "TOPLEFT", 0, 5)
        frame:SetSize((size + 3) * count, (size + 3) * 2)
        frame:SetFlowLayoutMaximumLineSize((size + 3) * count)
        AuraGroup(auras, "buffs", "HELPFUL", mode ~= 3 and count or 0, size, 1)
        AuraGroup(auras, "debuffs", "HARMFUL", mode ~= 2 and count or 0, size, 2)
        frame:SetUnit("player")
        auras.mode, auras.count, auras.size = mode, count, size
    end
    auras.frame:SetEnabled(true)
end

local function Apply(record, config)
    local frame = record.frame
    local container = frame.HealthBarsContainer
    local health, power = Available(container) and container.healthBar or nil, frame.PowerBar
    local style = config and config.nameplatePersonalStyle or default
    local texture
    if style == suiteTexture then texture = S.ResolveTexture(config.nameplatePersonalTexture) end
    if style == compact then texture = flat end
    record.healthBar = PaintBar(record.healthBar, health, texture)
    record.powerBar = PaintBar(record.powerBar, power, texture)
    record.healthHeight = Height(record.healthHeight, container, style == compact and 10 or nil)
    record.powerHeight = Height(record.powerHeight, power, style == compact and 5 or nil)
    if Available(health) then
        local hide = config and config.nameplateHideIncomingHeals
        if hide or next(record.heals) then private.ExtensionLayout.IncomingHeals(record.heals, health, hide and 0 or 1) end
    end
    Auras(record, config)
end

function Personal.Refresh()
    local config = active and owner.config or nil
    if NS.InCombat() then
        waiting = true
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    waiting = nil
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local frame = config and PersonalResourceDisplayFrame or nil
    if current and current.frame ~= frame then
        if current.auras then current.auras.frame:SetEnabled(false) end
        if Available(current.frame) then Apply(current, nil) end
        current = nil
    end
    if not Available(frame) then return end
    if not current or current.frame ~= frame then current = { frame = frame, heals = {} } end
    Apply(current, config)
end

local function OnEvent(_, event, unit)
    if event == "ADDON_LOADED" and (not NS.Public(unit) or unit ~= "Blizzard_PersonalResourceDisplay") then return end
    if (event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and (not NS.Public(unit) or unit ~= "player") then return end
    Personal.Refresh()
end

function Personal.Configure(module)
    owner = module
    local config = module.config
    local enabled = module.active and config.look ~= private.Mode.LOOK_BLIZZARD
        and (config.nameplateHideIncomingHeals == true or (config.nameplatePersonalStyle or default) ~= default
            or (config.nameplatePersonalAuras or 1) ~= 1)
    if enabled and not active then
        if not eventFrame then
            eventFrame = CreateFrame("Frame")
            eventFrame:SetScript("OnEvent", OnEvent)
        end
        for _, event in ipairs(ownEvents) do eventFrame:RegisterEvent(event) end
    elseif not enabled and active then
        for _, event in ipairs(ownEvents) do eventFrame:UnregisterEvent(event) end
    end
    local wasActive = active
    active = enabled
    if active or wasActive or waiting then Personal.Refresh() end
end

function Personal.Disable()
    if not active then return end
    active = false
    for _, event in ipairs(ownEvents) do eventFrame:UnregisterEvent(event) end
    Personal.Refresh()
end
