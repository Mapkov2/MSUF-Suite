local root = assert(arg[1], "repository root required")
local now, flying, capable, speed = 100, false, false, 0
local charges = {
    [372610] = { currentCharges = 6, maxCharges = 6, cooldownStartTime = 0, cooldownDuration = 0 },
    [425782] = { currentCharges = 3, maxCharges = 3, cooldownStartTime = 0, cooldownDuration = 0 },
}
local cooldown = { startTime = 0, duration = 0 }

local function Widget(parent)
    local w = { shown = true, parent = parent }
    function w:CreateTexture() return Widget(self) end
    function w:CreateFontString() return Widget(self) end
    function w:GetParent() return self.parent end
    function w:SetFrameStrata() end
    function w:SetStatusBarTexture(texture) self.texture = texture end
    function w:SetMinMaxValues(min, max) self.min, self.max = min, max end
    function w:SetStatusBarColor(...) self.barColor = { ... } end
    function w:SetValue(value) self.value = value end
    function w:SetColorTexture(...) self.color = { ... } end
    function w:SetAlpha(value) self.alpha = value end
    function w:SetTexture(value) self.texture = value end
    function w:SetAllPoints() end
    function w:SetPoint(...) self.point = { ... } end
    function w:ClearAllPoints() end
    function w:SetScale(value) self.scale = value end
    function w:GetEffectiveScale() return self.scale or 1 end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetWidth(width) self.width = width end
    function w:SetHeight(height) self.height = height end
    function w:SetShown(value) self.shown = value end
    function w:IsShown() return self.shown end
    function w:Hide() self.shown = false end
    function w:SetText(value) self.text = value; self.writes = (self.writes or 0) + 1 end
    function w:SetTextColor(...) self.textColor = { ... } end
    function w:SetJustifyH() end
    function w:SetScript(name, callback) self[name] = callback end
    function w:SetFont(path) self.font = path; return true end
    function w:SetShadowColor(...) self.shadowColor = { ... } end
    function w:SetShadowOffset(...) self.shadowOffset = { ... } end
    return w
end

UIParent = Widget()
CreateFrame = function(_, _, parent) return Widget(parent) end
GetTime = function() return now end
C_PlayerInfo = { GetGlidingInfo = function() return flying, capable, speed end }
local chargeReads, cooldownReads = 0, 0
C_Spell = {
    GetSpellCharges = function(id) chargeReads = chargeReads + 1; return charges[id] end,
    GetSpellCooldown = function() cooldownReads = cooldownReads + 1; return cooldown end,
    GetSpellTexture = function() return 12345 end,
}

local events, movers = {}, {}
local suite = { ChatLookPresets = {} }
suite.Suite = { instances = {}, editMode = false }
local S = suite.Suite
S.Public = function(value) return value ~= "secret" end
S.Install = function(id, module) assert(id == "skyriding"); S.instances[id] = module end
S.RegisterOwnedMover = function(id, element, spec)
    assert(id == "skyriding" and element == "flight" and spec.xKey == "x")
    movers[element] = spec
    return true
end
S.Config = function(id) return S.instances[id].config end
S.Set = function(id, key, value) S.Config(id)[key] = value; return true end
S.ResolveFont = function(key) return key == "Other font" and "Other.ttf" or nil end
S.ResolveTexture = function(key, fallback) return key == "Other bars" and "Other.tga" or fallback end
S.SetFont = function(label, path, size, flags)
    label:SetFont(path)
    label.fontSize, label.fontFlags = size, flags
end
S.SetStyledFont = function(label, path, size, flags, rendering, shadow, opacity, distance)
    local styled = rendering == 3 and (flags == "" and "SLUG" or "OUTLINE,SLUG")
        or rendering == 2 and (flags == "" and "MONOCHROME" or flags .. ",MONOCHROME") or flags
    S.SetFont(label, path, size, styled)
    local shown = shadow and rendering ~= 3
    label:SetShadowColor(0, 0, 0, shown and (opacity or 100) / 100 or 0)
    label:SetShadowOffset(shown and (distance or 1) or 0, shown and -(distance or 1) or 0)
end
S.Text = function(value) return value end
S.CreateFrame = CreateFrame
S.RGB = function(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
MSUFSuite = suite
local private = {}
for _, file in ipairs({ "Bootstrap", "Skyriding" }) do
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))("MSUF_Suite_QualityOfLife", private)
end
local module = S.instances.skyriding
module.active = true
module.config = { look = 1, width = 350, scale = 100, point = 5, x = 0, y = -145,
    airborneOnly = false, showSpeed = true, showVigor = true, showSecondWind = true,
    showWhirlingSurge = true, speedMax = 1200, thrillSpeed = 830,
    font = "", fontSize = 11, fontOutline = 1, fontRendering = 3,
    fontShadow = false, fontShadowOpacity = 100, fontShadowDistance = 1,
    barTexture = "", barHeight = 10, rowGap = 0,
    panelColor = "0a1220", panelOpacity = 94, borderColor = "41627a", borderSize = 1,
    trackColor = "102033", trackOpacity = 100, accentColor = "57c7df",
    windColor = "558bdd", thrillColor = "d8b66a", textColor = "f4f7fb", mutedColor = "aab5c2" }
module.context = { Event = function(_, name, callback, combat)
    assert(combat and not events[name])
    events[name] = callback
end, RemoveEvent = function(_, name) events[name] = nil end }
module:Enable()
assert(module.title.fontFlags == "SLUG", "default Skyriding HUD did not use Slug")
assert(movers.flight and events.PLAYER_CAN_GLIDE_CHANGED and events.PLAYER_IS_GLIDING_CHANGED
    and not events.SPELL_UPDATE_CHARGES and not events.SPELL_UPDATE_COOLDOWN,
    "Grounded Skyriding registered global spell events or lost its mover")
assert(not module.host:IsShown() and not module.host.OnUpdate, "Grounded HUD remained active")

capable = true
events.PLAYER_CAN_GLIDE_CHANGED()
assert(module.host:IsShown() and not module.host.OnUpdate,
    "Mounted HUD should be visible without a continuous tick when idle")
assert(events.SPELL_UPDATE_CHARGES and events.SPELL_UPDATE_COOLDOWN,
    "Visible Skyriding HUD did not subscribe to spell changes")
assert(module.vigor.label.text == "VIGOR" and module.vigor.count.text == "6/6"
    and module.wind.label.text == "WIND" and module.wind.count.text == "3/3")
module.config.airborneOnly = true
module:Refresh()
assert(not module.host:IsShown() and not events.SPELL_UPDATE_CHARGES and not events.SPELL_UPDATE_COOLDOWN,
    "Airborne-only HUD kept hot listeners while grounded")
module.config.airborneOnly = false
module:Refresh()

flying, speed = true, 70
charges[372610] = { currentCharges = 3, maxCharges = 6, cooldownStartTime = 95, cooldownDuration = 10 }
charges[425782] = { currentCharges = 1, maxCharges = 3, cooldownStartTime = 95, cooldownDuration = 10 }
cooldown = { startTime = 98, duration = 14 }
events.PLAYER_IS_GLIDING_CHANGED()
assert(module.speedText.text == "SPEED" and module.speedValue.text == "1000%" and module.speed.value > 0.8
    and module.state.text == "THRILL SPEED",
    "Flight speed was not read from GetGlidingInfo")
assert(module.vigor.pips[4].value == 0.5 and module.wind.pips[2].value == 0.5,
    "Charge recharge was not displayed")
assert(module.surgeText.text == "12" and module.host.OnUpdate,
    "Whirling Surge countdown or active flight tick missing")
now = 103
local tick, reads, speedWrites = module.host.OnUpdate, chargeReads + cooldownReads, module.speedValue.writes
module.host.OnUpdate(module.host, 0.1)
assert(module.vigor.pips[4].value > 0.5, "Active recharge did not advance")
assert(chargeReads + cooldownReads == reads and module.speedValue.writes == speedWrites,
    "An unchanged flight tick re-read spell data or rewrote unchanged text")
events.SPELL_UPDATE_COOLDOWN()
assert(cooldownReads == reads - chargeReads, "A spell event drew a full update while the tick was running")
module.host.OnUpdate(module.host, 0.1)
assert(cooldownReads == reads - chargeReads + 1, "The next tick did not pick up the invalidated cooldown")
capable = false
events.PLAYER_CAN_GLIDE_CHANGED()
assert(not module.host.OnUpdate, "A hidden HUD kept its flight tick")
capable = true
events.PLAYER_CAN_GLIDE_CHANGED()
assert(module.host.OnUpdate == tick, "Restarting the flight tick allocated a new handler")

-- The minimum HUD width must keep every caption, charge cell and Surge icon
-- inside its own lane, even with the largest supported charge counts.
module.config.width = 220
module:Refresh()
charges[372610] = { currentCharges = 8, maxCharges = 8 }
charges[425782] = { currentCharges = 4, maxCharges = 4 }
events.SPELL_UPDATE_CHARGES()
assert(module.vigor.count.text == "3/6", "A charge event redrew the HUD while the tick was running")
module.host.OnUpdate(module.host, 0.1)
assert(module.vigor.width == 148 and module.wind.width == 148 and module.speed.width == 148)
assert(module.vigor.label.width + module.vigor.count.width <= module.vigor.width
    and module.speedText.width + module.speedValue.width <= module.speed.width,
    "Skyriding captions overlap at minimum width")
for _, row in ipairs({ module.vigor, module.wind }) do
    local last = row == module.vigor and row.pips[8] or row.pips[4]
    assert(last.shown and last.point[4] + last.width <= row.width + 0.001,
        "Skyriding charge cells extend outside their row")
end
assert(module.surge.width == 40 and module.surgeIcon.width == 28 and module.host.height >= 123,
    "Skyriding surge lane or panel height clipped")
module.config.font, module.config.fontSize, module.config.fontOutline = "Other font", 18, 3
module.config.fontRendering = 1
module.config.barTexture, module.config.barHeight, module.config.rowGap = "Other bars", 18, 12
module.config.panelColor, module.config.panelOpacity = "112233", 35
module.config.trackColor, module.config.trackOpacity = "445566", 45
module.config.borderColor, module.config.borderSize = "778899", 2
module.config.accentColor, module.config.windColor = "ff2200", "22ff00"
module.config.thrillColor, module.config.textColor, module.config.mutedColor = "ffff00", "ffffff", "aaaaaa"
module:Refresh()
assert(module.title.font == "Other.ttf" and module.title.fontSize == 18
    and module.title.fontFlags == "THICKOUTLINE" and module.surgeLabel.fontSize == 18
    and module.state.text == "THRILL",
    "Selected font, size and outline were not applied to every HUD label")
assert(module.vigor.pips[1].texture == "Other.tga" and module.speed.texture == "Other.tga"
    and module.vigor.pips[1].height == 18 and module.speed.height == 18
    and module.wind.point[5] == -35 and module.vigor.point[5] == -90,
    "Selected texture, bar height or row spacing did not affect the HUD")
assert(module.panel.alpha == 0.35 and module.speed.track.alpha == 0.45
    and module.edges[1].height == 2 and module.panel.color[1] == 0x11 / 255
    and module.vigor.pips[1].barColor[1] == 1 and module.wind.pips[1].barColor[2] == 1,
    "Panel, track, border or bar colors were not applied independently")
assert(module.vigor.pips[8].point[4] + module.vigor.pips[8].width <= module.vigor.width + 0.001
    and module.host.height >= 210, "Large text and spacing clipped the compact HUD")
module.config.fontRendering, module.config.fontShadow = 2, true
module.config.fontShadowOpacity, module.config.fontShadowDistance = 55, 2
module:Refresh()
assert(module.title.fontFlags == "THICKOUTLINE,MONOCHROME"
    and module.title.shadowColor[4] == 0.55 and module.title.shadowOffset[1] == 2,
    "Skyriding Sharp text or shadow did not reach the HUD")
module.config.fontRendering = 3
module:Refresh()
assert(module.title.fontFlags == "OUTLINE,SLUG" and module.title.shadowColor[4] == 0
    and module.title.shadowOffset[1] == 0, "Skyriding Slug retained a shadow")
module.config.fontSize, module.config.barHeight, module.config.rowGap = 11, 10, 0
module:Refresh()
module.config.showSecondWind, module.config.showVigor, module.config.showSpeed = false, false, false
module:Refresh()
assert(module.host.height == 88 and module.surge.shown
    and not module.speedText.shown and not module.speedValue.shown,
    "Surge-only layout clips the icon or leaves speed text visible")
assert(not events.SPELL_UPDATE_CHARGES and events.SPELL_UPDATE_COOLDOWN,
    "Surge-only HUD listened for unused charge events")
module.config.showSecondWind, module.config.showVigor, module.config.showSpeed = true, true, true
module:Refresh()

charges[372610] = { currentCharges = "secret", maxCharges = 6 }
events.SPELL_UPDATE_CHARGES()
module.host.OnUpdate(module.host, 0.1)
assert(module.vigor.count.text == "--" and module.vigor.pips[1].alpha == 0.35,
    "Unknown charges must not be displayed as zero")

flying, capable = false, false
events.PLAYER_CAN_GLIDE_CHANGED()
assert(not module.host:IsShown() and not module.host.OnUpdate,
    "Dismount did not hide the HUD and release its tick")
assert(not events.SPELL_UPDATE_CHARGES and not events.SPELL_UPDATE_COOLDOWN,
    "Dismount retained global spell listeners")
S.editMode = true
module:Refresh()
assert(module.host:IsShown() and module.vigor.count.text == "5/6"
    and not module.host.OnUpdate, "Edit Mode preview did not render safely")
assert(not events.SPELL_UPDATE_CHARGES and not events.SPELL_UPDATE_COOLDOWN,
    "Edit Mode preview retained global spell listeners")
S.editMode = false
module:Disable()
assert(not module.host:IsShown() and not module.host.OnUpdate,
    "Disabling the module left its frame or tick active")
print("suite_skyriding_contract: OK")
