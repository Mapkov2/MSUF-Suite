local _, private = ...
local NS = private.NS
local Resource = {}
private.TargetResource = Resource
local owner, watcher, current, currentUF, power, read, maximum, config, revision, powerToken
local rows = setmetatable({}, { __mode = "k" })
local events = { "PLAYER_SPECIALIZATION_CHANGED", "SPELLS_CHANGED", "UPDATE_SHAPESHIFT_FORM",
    "UNIT_DISPLAYPOWER", "UNIT_MAXPOWER", "PLAYER_ENTERING_WORLD" }

local function Accessible(region)
    if NS.Safety.IsForbidden(region) then return false end
    if not region.CanBeAccessedInContext then return true end
    local access = region:CanBeAccessedInContext()
    return NS.Public(access) and access == true
end

local function Mutable(uf, health)
    if not NS.Public(uf) or not uf or not NS.Public(health) or not health
        or NS.Safety.IsForbidden(uf) or NS.Safety.IsForbidden(health) then return false end
    if not Accessible(uf) or not Accessible(health) then return false end
    if NS.InCombat() then
        local protected = uf:IsProtected()
        if not NS.Public(protected) or protected ~= false then owner.pendingPlates[uf] = true return false end
    end
    return true
end

local function Hide()
    if current and Accessible(current) then current:SetAlpha(0) end
    current, currentUF = nil, nil
end

local function Resolve()
    local bridge = NS.HostBridge
    power, read, maximum, powerToken = nil, nil, nil, nil
    if bridge and bridge.NameplateResource then power, read, maximum, powerToken = bridge.NameplateResource() end
end

local function Update()
    if not current or not read or not owner.active or not Accessible(current) then return end
    local value = read("player", power)
    for index = 1, current.count do current.bars[index]:SetValue(value) end
end

local function Layout(row, health, count)
    if row.revision ~= revision or row.count ~= count or row.power ~= power then
        local width, height = config.targetClassResourceWidth, config.targetClassResourceHeight
        row:SetSize(width, height)
        row:ClearAllPoints()
        row:SetPoint("TOP", health, "BOTTOM", 0, config.targetClassResourceY)
        local size = (width - (count - 1) * 2) / count
        local colors = PowerBarColor[powerToken] or PowerBarColor.COMBO_POINTS or { r = 1, g = .8, b = 0 }
        for index = 1, math.max(count, #row.bars) do
            local bar = row.bars[index]
            if index <= count then
                if not bar then
                    bar = CreateFrame("StatusBar", nil, row)
                    bar:EnableMouse(false)
                    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                    local back = bar:CreateTexture(nil, "BACKGROUND")
                    back:SetAllPoints(bar)
                    back:SetColorTexture(.08, .08, .08, .9)
                    row.bars[index] = bar
                end
                bar:SetSize(size, height)
                bar:ClearAllPoints()
                bar:SetPoint("LEFT", row, "LEFT", (index - 1) * (size + 2), 0)
                bar:SetMinMaxValues(index - 1, index)
                bar:SetStatusBarColor(colors.r, colors.g, colors.b)
                bar:Show()
            else
                bar:Hide()
            end
        end
        row.revision, row.count, row.power = revision, count, power
    end
end

function Resource.Attach(uf, health, styled)
    if not Resource.enabled or not power or not styled then
        Resource.Restore(uf)
        return
    end
    if Resource.targetUF ~= uf then
        Resource.Restore(uf)
        return
    end
    if not Mutable(uf, health) then return end
    local count = maximum("player", power)
    if not NS.Finite(count) then return end
    if count <= 0 or count % 1 ~= 0 then Hide() return end
    local row = rows[uf]
    if not row then
        row = CreateFrame("Frame", nil, health)
        row:EnableMouse(false)
        row.bars = {}
        rows[uf] = row
    end
    if current ~= row then Hide() current, currentUF = row, uf end
    Layout(row, health, count)
    row:SetAlpha(1)
    row:Show()
    Update()
end

function Resource.Selection()
    Hide()
    Resource.targetUF = nil
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    if not NS.Public(plate) or not plate or NS.Safety.IsForbidden(plate) then return end
    local uf = plate.UnitFrame
    if not NS.Public(uf) or not uf or NS.Safety.IsForbidden(uf) then return end
    Resource.targetUF = uf
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not health or not private.SkinAllowed(uf) then return end
    Resource.Attach(uf, health, true)
end

local function OnEvent(_, event, unit, token)
    if event == "UNIT_POWER_UPDATE" and NS.Public(token) and token ~= powerToken then return end
    if event == "UNIT_POWER_UPDATE" or event == "RUNE_POWER_UPDATE" or event == "COMBO_TARGET_CHANGED" then
        Update()
    else
        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "UNIT_DISPLAYPOWER" or event == "UNIT_MAXPOWER" then
            if not NS.Public(unit) or unit ~= "player" then return end
        end
        Resolve()
        if power then watcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player") else watcher:UnregisterEvent("UNIT_POWER_UPDATE") end
        Resource.Selection()
    end
end

function Resource.Configure(module)
    owner, config, revision = module, module.config, (revision or 0) + 1
    local enabled = owner.active and config.look ~= 2 and config.targetClassResource == true
    if watcher then watcher:UnregisterAllEvents() end
    Resource.enabled = enabled
    Resource.targetUF = nil
    Hide()
    if not enabled then return end
    Resolve()
    if not watcher then watcher = CreateFrame("Frame") watcher:SetScript("OnEvent", OnEvent) end
    if power then watcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player") end
    watcher:RegisterEvent("RUNE_POWER_UPDATE")
    if NS.Client.isForever then watcher:RegisterEvent("COMBO_TARGET_CHANGED") end
    for _, event in ipairs(events) do watcher:RegisterEvent(event) end
end

function Resource.Restore(uf, removed)
    local row = rows[uf]
    if row and Accessible(row) then row:SetAlpha(0) end
    if currentUF == uf then current, currentUF = nil, nil end
    if removed and Resource.targetUF == uf then Resource.targetUF = nil end
end
