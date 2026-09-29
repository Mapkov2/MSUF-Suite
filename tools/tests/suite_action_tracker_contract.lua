local root = assert(arg[1], "repository root required")
local secret, events, timers = {}, {}, {}
local now, reads = 100, 0

local function Widget(parent, fontString)
    local w = { shown = true, parent = parent, fontString = fontString }
    function w:CreateTexture() return Widget(self) end
    function w:CreateFontString() return Widget(self, true) end
    function w:GetParent() return self.parent end
    function w:SetFrameStrata() end
    function w:EnableMouse(value) self.mouse = value end
    function w:SetAllPoints() end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetWidth(width) self.width = width end
    function w:SetHeight(height) self.height = height end
    function w:SetScale(scale) self.scale = scale end
    function w:SetPoint(...) self.point = { ... } end
    function w:ClearAllPoints() end
    function w:SetTexCoord() end
    function w:SetColorTexture(...) self.color = { ... } end
    function w:SetTexture(value) self.texture = value end
    function w:SetJustifyH() end
    function w:SetWordWrap() end
    function w:SetTextColor(...) self.textColor = { ... } end
    function w:SetText(value)
        assert(not self.fontString or self.font, "Action tracker text has no font")
        self.text = value
    end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetShown(value) self.shown = value end
    return w
end

UIParent = Widget()
GetTime = function() return now end
C_Spell = { GetSpellInfo = function(id)
    reads = reads + 1
    if id == 66 then return { name = secret, iconID = 66 } end
    if id == 67 then return { name = "Hidden icon", iconID = secret } end
    return { name = "Spell " .. id, iconID = id + 1000 }
end }
C_Timer = { NewTimer = function(delay, callback)
    assert(delay > 0)
    local timer = { delay = delay, callback = callback }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end }
local function Fire(timer)
    assert(not timer.cancelled)
    now = now + timer.delay
    timer.callback()
end

local S = { editMode = false }
S.Public = function(value) return value ~= secret end
S.PublicText = function(value)
    return S.Public(value) and type(value) == "string" and value ~= "" and value or nil
end
S.Finite = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.Text = function(value) return value end
S.CreateFrame = function(_, _, parent) return Widget(parent) end
S.CreateTexture = function(parent) return parent:CreateTexture() end
S.CreateFontString = function(parent) return parent:CreateFontString() end
S.RGB = function() return .5, .6, .7 end
S.ResolveFont = function() return nil end
S.GlobalFontPath = function() return "Fonts\\FRIZQT__.TTF" end
S.SetFont = function(fontString) fontString.font = true end
local module, mover
S.Install = function(id, value) assert(id == "actionTracker"); module = value end
S.RegisterOwnedMover = function(id, element, spec)
    assert(id == "actionTracker" and element == "actions")
    mover = spec
end
S.Config = function() return module.config end
S.Set = function(_, key, value)
    module.config[key] = value
    module:Refresh()
    return true
end

local NS = { AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER" } }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/ActionTracker.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
local M = assert(module)
M.active = true
M.config = { rows = 5, width = 210, rowHeight = 31, rowGap = 2, scale = 100,
    displayPreset = 1,
    hideAfter = 15, showNames = true, showChevron = true, font = "", fontSize = 12,
    point = 5, x = 0, y = -40, panelColor = "171316", panelOpacity = 88,
    borderColor = "563938", accentColor = "d4a64c", textColor = "f2eeea" }
M.context = { Event = function(_, event, callback, allowCombat, unit)
    assert(event == "UNIT_SPELLCAST_SUCCEEDED" and allowCombat and unit == "player")
    events.cast = callback
end }
M:Enable()
assert(reads == 0 and not M.host.shown and M.host.mouse == false,
    "disabled history did startup spell work or intercepted input")
assert(mover and mover.getFrame() == M.host and #mover.extraControls == 3,
    "Edit Mode position and size controls are missing")
assert(M.host.width == 210 and M.host.height == 163 and M.host.scale == 1,
    "default stack geometry is wrong")

local function Cast(id)
    events.cast(M, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", id)
end
Cast(secret)
Cast(66)
Cast(67)
assert(reads == 2 and not M.host.shown and #M.history == 0,
    "private cast details entered the history")
for id = 1, 9 do Cast(id) end
assert(#M.history == 8 and M.history[1].name == "Spell 9"
    and M.history[8].name == "Spell 2" and M.rows[1].name.text == "Spell 9"
    and M.rows[5].name.text == "Spell 5" and not M.rows[6].frame.shown,
    "recent spells did not remain bounded and newest-first")
assert(M.host.shown and M.rows[1].icon.texture == 1009,
    "latest spell was not rendered")
assert(timers[1].cancelled and not timers[#timers].cancelled,
    "new casts left earlier inactivity timers active")
Fire(timers[#timers])
assert(not M.host.shown and #M.history == 0, "inactivity did not clear the stack")

S.editMode = true
M:Refresh()
assert(M.host.shown and M.rows[5].frame.shown,
    "Edit Mode did not show five sample actions")
M.config.width, M.config.rowHeight, M.config.scale = 280, 40, 125
M.config.panelOpacity, M.config.showChevron = 50, false
M:Refresh()
assert(M.host.width == 280 and M.host.height == 208 and M.host.scale == 1.25
    and M.rows[1].panel.color[4] == .5 and not M.rows[1].marker.shown,
    "style or size changes did not reach the preview")
M.config.displayPreset = 2
M:Refresh()
assert(M.host.width == 40 and M.host.height == 208 and M.rows[1].icon.point[1] == "CENTER"
    and M.rows[1].icon.width == 38 and not M.rows[1].panel.shown
    and not M.rows[1].stripe.shown and not M.rows[1].rule.shown
    and not M.rows[1].name.shown and not M.rows[1].marker.shown,
    "icon-only preset retained the text row or its decoration")
M.config.displayPreset, M.config.showChevron = 1, true
M:Refresh()
assert(M.host.width == 280 and M.rows[1].panel.shown and M.rows[1].name.shown
    and M.rows[1].marker.shown and M.rows[1].icon.point[1] == "LEFT",
    "switching back did not restore the standard row")
S.editMode = false
M:Refresh()
assert(not M.host.shown, "Edit Mode preview survived its session")
M.config.hideAfter = 0
M:Refresh()
local timerCount = #timers
Cast(10)
now = now + 120
M:Refresh()
assert(M.host.shown and M.rows[1].name.text == "Spell 10" and #timers == timerCount,
    "persistent history scheduled a timer or disappeared")
M:Disable()
M.active = false
assert(not M.host.shown and #M.history == 0, "disable retained visible or recorded actions")
print("Action tracker: cast bounds, private values, inactivity, styles and preview passed")
