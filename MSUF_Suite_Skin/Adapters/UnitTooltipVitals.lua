local _, NS = ...
local Card, Safety = NS.ItemTooltipCard, NS.Safety
local Vitals = {}
NS.TooltipVitals = Vitals

local FILL = "Interface\\Buttons\\WHITE8X8"
local NATIVE_FILL = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
local UNIT = Enum.TooltipDataType.Unit
local UNIT_NAME = Enum.TooltipDataLineType.UnitName
local nativeView, panelView
local active, nativeHooks
local config = {}
local UnitHealthPercent = UnitHealthPercent
local scaleTo100 = CurveConstants and CurveConstants.ScaleTo100
if UnitHealthPercent and not scaleTo100 and C_CurveUtil and C_CurveUtil.CreateCurve then
    scaleTo100 = C_CurveUtil.CreateCurve()
    local curveType = Enum.LuaCurveType and Enum.LuaCurveType.Linear
    if curveType and scaleTo100.SetType then scaleTo100:SetType(curveType) end
    scaleTo100:AddPoint(0, 0)
    scaleTo100:AddPoint(1, 100)
end
local nativeStyle = { fill = NATIVE_FILL, background = FILL, color = { 0, 1, 0, 1 },
    tint = { .03, .04, .05, .95 }, width = 100, height = 8, x = 0, y = 0 }

local function Readable(value)
    return Safety.Public(value) and type(value) == "table" and canaccesstable(value)
end

local function PublicUnit(unit)
    return Safety.Public(unit) and type(unit) == "string" and unit ~= ""
end

local function UnitFromData(tooltip, data)
    local lines = data.lines
    local first = Readable(lines) and lines[1]
    if Readable(first) and Safety.Public(first.type) and first.type == UNIT_NAME and PublicUnit(first.unitToken) then
        return first.unitToken
    end
    -- The native frame already knows its unit. Its result can be secret.
    local _, unit = Safety.Call(tooltip, "GetUnit")
    if PublicUnit(unit) then return unit end
end

local function FillTexture(bar, path)
    bar:SetStatusBarTexture(path)
    local fill = bar:GetStatusBarTexture()
    if fill then
        if path == FILL then fill:SetColorTexture(1, 1, 1, 1) end
        fill:SetDrawLayer("ARTWORK")
    end
end

local function Bar(parent)
    local bar = Safety.CreateChildFrame("StatusBar", parent)
    FillTexture(bar, FILL)
    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetColorTexture(.03, .04, .05, .95)
    local text = bar:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    text:SetPoint("LEFT", 2, 0)
    text:SetPoint("RIGHT", -2, 0)
    text:SetWordWrap(false)
    bar:Hide()
    return bar, text, bg
end

local function Place(view, shape)
    local bar = shape.bar
    if not shape.shown then return end
    local width = view.width
    local inset = 2
    if width and width > 4 and shape.width ~= 100 then
        inset = (width - (width - 4) * shape.width / 100) / 2
    end
    local left, right, y = shape.x + inset, shape.x - inset, shape.y - shape.offset
    if shape.left ~= left or shape.right ~= right or shape.top ~= y then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", view.parent, "BOTTOMLEFT", left, y)
        bar:SetPoint("TOPRIGHT", view.parent, "BOTTOMRIGHT", right, y)
        shape.left, shape.right, shape.top = left, right, y
    end
    if shape.appliedHeight ~= shape.height then
        bar:SetHeight(shape.height)
        shape.appliedHeight = shape.height
    end
end

local function Create(parent)
    local health, healthText, healthBg = Bar(parent)
    local power, powerText, powerBg = Bar(parent)
    local view = { parent = parent, health = health, healthText = healthText, power = power, powerText = powerText,
        healthShape = { bar = health, bg = healthBg, text = healthText, fill = FILL },
        powerShape = { bar = power, bg = powerBg, text = powerText, fill = FILL } }
    view.width = Safety.Read(parent, "GetWidth")
    parent:HookScript("OnSizeChanged", function(_, width)
        if not Safety.Public(width) or width == view.width then return end
        view.width = width
        if view.healthShape.width ~= 100 then Place(view, view.healthShape) end
        if view.powerShape.width ~= 100 then Place(view, view.powerShape) end
    end)
    return view
end

local function ApplyMaterial(shape, style)
    if shape.style == style then return end
    shape.style = style
    if shape.fill ~= style.fill then
        FillTexture(shape.bar, style.fill)
        shape.fill = style.fill
    end
    shape.bar:SetStatusBarColor(unpack(style.color))
    if style.background == FILL then shape.bg:SetColorTexture(1, 1, 1, 1)
    else shape.bg:SetTexture(style.background) end
    shape.bg:SetVertexColor(unpack(style.tint))
end

local function PaintBar(view, shape, style, offset, shown, showText, draft)
    shape.shown = shown
    shape.bar:SetShown(shown)
    if not shown then return 0 end
    shape.offset = offset
    shape.x = draft and draft.x or style.x
    shape.y = draft and draft.y or style.y
    shape.width = draft and draft.width or style.width
    shape.height = draft and draft.height or style.height
    ApplyMaterial(shape, style)
    Place(view, shape)
    shape.text:SetShown(showText)
    return offset - shape.y + shape.height
end

local function StyleHealthText(view, draft)
    local style, text = config.healthText, view.healthText
    if view.textStyle ~= style then
        if not view.nativeTextFont then view.nativeTextFont = { text:GetFont() } end
        local base, baseSize, flags = unpack(view.nativeTextFont)
        local size = style.size > 0 and math.max(6, style.size) or baseSize
        if base and size then
            if text:SetFont(style.font or base, size, flags) == false and style.font then
                text:SetFont(base, size, flags)
            end
        end
        text:SetTextColor(unpack(style.color))
        view.textStyle = style
    end
    local x, y = draft and draft.x or style.x, draft and draft.y or style.y
    if view.textX ~= x or view.textY ~= y then
        view.textX, view.textY = x, y
        text:ClearAllPoints()
        text:SetPoint("LEFT", view.health, "LEFT", 2 + x, y)
        text:SetPoint("RIGHT", view.health, "RIGHT", -2 + x, y)
    end
end

local function Paint(view, health, power, native, nativeHeight, draft)
    local style = native and nativeStyle or config.health
    local showHealthText = not native and config.healthText.mode ~= "off"
    local hpDepth = PaintBar(view, view.healthShape, style, 1, health, showHealthText,
        not native and draft and draft.unitHealth)
    if health and showHealthText then StyleHealthText(view, draft and draft.unitHealthText) end
    local offset = health and (view.healthShape.height + 3) or nativeHeight and (nativeHeight + 3) or 1
    local powerDepth = PaintBar(view, view.powerShape, config.resource, offset, power, config.text,
        draft and draft.unitPower)
    return math.max(hpDepth, powerDepth)
end

-- The bar and FontString are the only consumers of restricted numbers.
local function SetValues(bar, text, value, maximum, showText)
    bar:SetMinMaxValues(0, maximum)
    bar:SetValue(value)
    if showText then text:SetFormattedText("%d / %d", value, maximum) end
end

local function HealthValues(view, value, maximum)
    SetValues(view.health, view.healthText, value, maximum, config.healthText.mode == "value")
    if config.healthText.mode ~= "percent" then return end
    if Safety.Public(value) and Safety.Public(maximum) and type(value) == "number"
        and type(maximum) == "number" and maximum > 0 then
        view.healthText:SetFormattedText("%.0f%%", value / maximum * 100)
    else
        view.healthText:SetText("")
    end
end

local function ValidMaximum(value)
    if not Safety.Public(value) then return true end
    return type(value) == "number" and value > 0
end

local function NativeBar()
    local bar = Safety.Field(GameTooltip, "StatusBar")
    if not Safety.Public(bar) then return end
    return bar or GameTooltipStatusBar
end

local function NativeHeight()
    local bar = NativeBar()
    if Safety.Read(bar, "IsShown") == true then
        local alpha = Safety.Read(bar, "GetAlpha")
        if alpha == nil or alpha > 0 then return Safety.Read(bar, "GetHeight") or 8 end
    end
end

local function FadeNative(view, fade)
    local bar = NativeBar()
    if view.faded and (not fade or view.faded ~= bar) then
        NS.Cosmetics.Restore(view.faded, view)
        view.faded = nil
    end
    if not fade then return true end
    if not bar then return true end
    if Safety.Read(bar, "GetAlpha") == 0 then return true end
    if not NS.Cosmetics.Fade(bar, view) then return false end
    view.faded = bar
    return true
end

local function Stop(view)
    if not view then return end
    if view.native then FadeNative(view, false) end
    if view.unit then view.event:UnregisterAllEvents() end
    view.unit, view.pending, view.unitShown, view.healthOn, view.powerOn = nil, nil, nil, nil, nil
    view.healthShape.shown, view.powerShape.shown = nil, nil
    view.health:Hide()
    view.power:Hide()
end

local function UpdateHealth(view, unit)
    local scaled = config.healthText.mode == "percent" and UnitHealthPercent and scaleTo100
    local maximum = scaled and 100
    if not scaled then maximum = UnitHealthMax(unit) end
    if not ValidMaximum(maximum) then return false end
    if view.native and view.faded == nil and not FadeNative(view, true) then return false end
    if scaled then
        -- One display value feeds both sinks without stepping through Lua arithmetic.
        local percent = UnitHealthPercent(unit, true, scaleTo100)
        SetValues(view.health, view.healthText, percent, 100, false)
        view.healthText:SetFormattedText("%.0f%%", percent)
    else HealthValues(view, UnitHealth(unit), maximum) end
    return true
end

local function Update(view, event)
    local unit = view.unit
    if not unit then return end
    local health, power = config.mode == "show", config.power
    if health and (not event or event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") then
        health = UpdateHealth(view, unit)
    elseif event then health = view.healthOn end
    if power and (not event or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER") then
        local maximum = UnitPowerMax(unit)
        power = ValidMaximum(maximum)
        if power then SetValues(view.power, view.powerText, UnitPower(unit), maximum, config.text) end
    elseif event then power = view.powerOn end
    if view.native and not health then FadeNative(view, config.mode == "hide") end
    if not event or health ~= view.healthOn or power ~= view.powerOn then
        view.healthOn, view.powerOn = health, power
        Paint(view, health, power, false, view.native and not health and NativeHeight())
    end
end

local function Watch(view, unit)
    if not PublicUnit(unit) or not (config.mode == "show" or config.power) then
        Stop(view)
        return
    end
    if view.unit ~= unit or view.watchHealth ~= config.mode or view.watchPower ~= config.power then
        local frame = view.event
        frame:UnregisterAllEvents()
        if config.mode == "show" then
            frame:RegisterUnitEvent("UNIT_HEALTH", unit)
            frame:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
            frame:RegisterEvent("PLAYER_REGEN_DISABLED")
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        if config.power then
            frame:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
            frame:RegisterUnitEvent("UNIT_MAXPOWER", unit)
            frame:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit)
        end
        view.unit, view.watchHealth, view.watchPower = unit, config.mode, config.power
    end
    Update(view)
end

local function Bind(parent, native)
    if not Safety.CanCreateRegions(parent) then return end
    local view = Create(parent)
    view.native = native
    view.event = CreateFrame("Frame")
    view.event:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            event = "UNIT_HEALTH"
        end
        Update(view, event)
    end)
    parent:HookScript("OnHide", function() Stop(view) end)
    return view
end

local function ShowNative()
    local view = nativeView
    if not view or not active then return end
    local pending = view.pending
    view.pending = nil
    if pending then Watch(view, pending) end
    if config.mode == "hide" and view.unitShown then FadeNative(view, true) end
end

local function ClearNative()
    Stop(nativeView)
end

function Vitals.Native(tooltip, data)
    if not active or not nativeView or not Safety.Public(tooltip) or tooltip ~= GameTooltip
        or Safety.IsForbidden(tooltip) or not Readable(data) then return end
    if not rawequal(Safety.Read(tooltip, "GetPrimaryTooltipData"), data) then return end
    if not Safety.Public(data.type) or data.type ~= UNIT then return end
    if config.mode == "hide" and not config.power and (nativeView.unit or nativeView.pending) then
        Stop(nativeView)
    end
    nativeView.unitShown = true
    if config.mode == "hide" then FadeNative(nativeView, true) end
    if config.mode == "show" or config.power then
        local unit = UnitFromData(tooltip, data)
        if PublicUnit(unit) and Safety.Read(tooltip, "IsShown") ~= true then
            nativeView.pending = unit
        else
            Watch(nativeView, unit)
            if config.mode == "hide" then FadeNative(nativeView, true) end
        end
    end
end

local function ObservePanel(panel, unit)
    if not active then return end
    if panelView and panelView.parent ~= panel then
        Stop(panelView)
        panelView = nil
    end
    panelView = panelView or Bind(panel, false)
    if panelView then Watch(panelView, unit) end
end

local function ReadStyle(prefix, resolve)
    return { fill = resolve(Card.Setting(prefix .. "Texture"), FILL),
        background = resolve(Card.Setting(prefix .. "Background"), FILL),
        color = { Card.UnitBarColor(prefix .. "Color") }, tint = { Card.UnitBarColor(prefix .. "BackgroundColor") },
        height = Card.Setting(prefix .. "Height"), width = Card.Setting(prefix .. "Width"),
        x = Card.Setting(prefix .. "X"), y = Card.Setting(prefix .. "Y") }
end

local function ReadHealthText(suite, showValues)
    local mode = Card.Setting("unitHealthTextFormat")
    if mode == "" then mode = showValues and "value" or "off" end
    local key = Card.Setting("unitHealthTextFont")
    return { mode = mode, font = suite and suite.ResolveFont and suite.ResolveFont(key),
        size = Card.Setting("unitHealthTextSize"), color = { Card.UnitBarColor("unitHealthTextColor") },
        x = Card.Setting("unitHealthTextX"), y = Card.Setting("unitHealthTextY") }
end

local function DefaultTexture(_, fallback) return fallback end

function Vitals.Refresh()
    local suite = NS.SuiteCore()
    local resolve = suite and suite.ResolveTexture or DefaultTexture
    local mode, power = Card.Setting("unitHealth"), Card.Setting("unitPower")
    local wanted = NS.DB.enabled and (mode ~= "native" or power)
    config.mode, config.power, config.text = mode, power, Card.Setting("unitValueText")
    config.health = ReadStyle("unitHealth", resolve)
    config.resource = ReadStyle("unitPower", resolve)
    config.healthText = ReadHealthText(suite, config.text)
    if wanted and not nativeView and NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(Vitals, Vitals.Refresh)
    elseif wanted and GameTooltip and not nativeView then
        nativeView = Bind(GameTooltip, true)
        if nativeView and not nativeHooks then
            GameTooltip:HookScript("OnShow", ShowNative)
            GameTooltip:HookScript("OnTooltipCleared", ClearNative)
            nativeHooks = true
        end
    end
    active = wanted == true
    Vitals.Enabled = active
    local host = suite and suite.HostBridge
    local watchPanel = active and (mode == "show" or power)
    if host then
        local ownsHealth = active and nativeView ~= nil and mode ~= "native"
        if ownsHealth and not host.TooltipOwnsHealth and host.ReleaseLegacyTooltipHealth then
            host.ReleaseLegacyTooltipHealth()
        end
        host.TooltipOwnsHealth = ownsHealth
        if host.SetUnitFrameTooltipPanelObserver then
            host.SetUnitFrameTooltipPanelObserver(watchPanel and ObservePanel or nil)
        end
    end
    if not watchPanel then Stop(panelView)
    elseif panelView and panelView.unit then Watch(panelView, panelView.unit) end
    if not active then ClearNative()
    elseif nativeView then
        local data = Safety.Read(GameTooltip, "GetPrimaryTooltipData")
        if Readable(data) and Safety.Public(data.type) and data.type == UNIT then Vitals.Native(GameTooltip, data)
        else ClearNative() end
    end
    return active
end

local function RefreshMedia()
    Vitals.Refresh()
    NS.Registry.NotifyListeners("tooltipMedia")
end

function Vitals.MediaRegistered(key)
    if not NS.DB or key == nil or key == "" then return end
    if key == Card.Setting("unitHealthTexture") or key == Card.Setting("unitHealthBackground")
        or key == Card.Setting("unitPowerTexture") or key == Card.Setting("unitPowerBackground") then
        NS.CombatGate.RunOrDefer(RefreshMedia, RefreshMedia)
    end
end

function Vitals.FontRegistered(key)
    if NS.DB and key and key ~= "" and key == Card.Setting("unitHealthTextFont") then
        NS.CombatGate.RunOrDefer(RefreshMedia, RefreshMedia)
    end
end

function Vitals.CreatePreview(parent) return Create(parent) end

function Vitals.PaintPreview(view, visible, panel, legacyHidden, healthLayer, powerLayer, previewSize, restricted)
    local native = not panel and (config.mode == "native" and not legacyHidden
        or config.mode == "show" and restricted)
    local health = visible and healthLayer and (native or config.mode == "show" and not restricted)
    local power = visible and powerLayer and config.power == true and not restricted
    if health then
        if native then SetValues(view.health, view.healthText, 7601, 10000, false)
        else HealthValues(view, 7601, 10000) end
    end
    if power then SetValues(view.power, view.powerText, 63, 100, config.text) end
    return Paint(view, health, power, native, nil, previewSize)
end
