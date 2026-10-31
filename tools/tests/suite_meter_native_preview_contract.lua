-- Integration of the real meter renderer, Suite controls and host page lifecycle.
-- Geometry is a deterministic client stand-in; this does not prove native pixels.
local root = assert(arg[1]):gsub("\\", "/")
local flavor = arg[2] or "Mainline"
local host = arg[3] or root .. "/../MidnightSimpleUnitFrames"
local MenuWorld = assert(loadfile(host .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(host, flavor, { open = false, locale = "deDE", clientScriptBindings = true })
local env, M, world = mw.env, mw.M, mw.world
assert(not M.frame, "fixture warmed the host before its first open")
-- The shared widgets expose only their local shown flag by default.
world.widgets.Methods.IsVisible = function(self)
    local parent = self:GetParent()
    return self:IsShown() and (not parent or parent:IsVisible())
end
world.widgets.Methods.SetResizeBounds = function() end
local create = env.CreateFrame
env.CreateFrame = function(...)
    local frame = create(...)
    MenuWorld.FireVisibilityScripts(frame)
    return frame
end
env.InCombatLockdown, env.UnitAffectingCombat = function() return false end, function() return false end
env.GetCurrentKeyBoardFocus = function() return nil end
env.IsControlKeyDown, env.IsShiftKeyDown = function() return false end, function() return false end
env.C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
env.C_AddOns = {
    GetAddOnMetadata = function() end,
    IsAddOnLoaded = function(name)
        local loaded = name ~= "EllesmereUIDamageMeters"
        return loaded, loaded
    end,
    DoesAddOnExist = function(name) return name:find("^MSUF_Suite") ~= nil end,
    GetAddOnEnableState = function() return 2 end,
    LoadAddOn = function() return false, "MISSING" end,
    GetNumAddOns = function() return 0 end,
}
-- Public samples need native string sinks, not the generic API sentinel tables.
env.AbbreviateNumbers = function(value) return tostring(value) end
env.Ambiguate = function(value) return value end
env.Enum.DamageMeterType = {
    DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5,
    Dispels = 6, DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10,
}
env.Enum.DamageMeterSessionType = { Overall = 0, Current = 1, Expired = 2 }
env.C_DamageMeter = {
    GetSessionDurationSeconds = function() return 0 end,
    IsDamageMeterAvailable = function() return true end,
    GetCombatSessionFromType = function() return nil end,
    GetCombatSessionFromID = function() return nil end,
}
local function Load(addon, namespace)
    local file = assert(io.open(root .. "/" .. addon .. "/" .. addon .. "_Mainline.toc", "rb"))
    local source = file:read("*a")
    file:close()
    for line in source:gmatch("[^\r\n]+") do
        if line:sub(1, 1) ~= "#" then
            local ok, message = world:LoadFile(root .. "/" .. addon .. "/" .. line:gsub("\\", "/"), addon, namespace)
            assert(ok, tostring(message))
        end
    end
end
Load("MSUF_Suite", {})
local Suite, P, private = env.MSUFSuite, {}, {}
assert(Suite.Database.Initialize(nil))
local config = Suite.Suite.Config("damageMeter")
config.enabled, config.combatTime, config.timer = true, false, false
config.w1Width, config.w1Height, config.w1Type, config.w1Session = 260, 170, 10, 1
Load("MSUF_Suite_Options", P)
Load("MSUF_Suite_Modules", {})
Load("MSUF_Suite_DamageMeter", private)
local D = private.DamageMeter
D.M.config, D.M.context, D.M.active = config, P.S.NewContext("damageMeter"), true
D.M:Enable()
P.S.started, P.S.states.damageMeter.active = true, true
local ui, paints = nil, 0
local draw = P.S.DamageMeterDrawMenuPreview
P.S.DamageMeterDrawMenuPreview = function(...)
    paints = paints + 1
    assert(paints < 300, "preview entered an unbounded repaint loop")
    return draw(...)
end
local build = P.BuildMeterMenuPreview
P.BuildMeterMenuPreview = function(workspace, ...)
    ui = workspace
    -- Deliver actual size changes, including reentrant layout callbacks. The
    -- generic client widgets otherwise store dimensions without notifications.
    for _, name in ipairs({ "SetSize", "SetHeight", "SetWidth" }) do
        local original = ui.header[name]
        ui.header[name] = function(self, ...)
            local width, height = self:GetWidth(), self:GetHeight()
            original(self, ...)
            if self:GetWidth() ~= width or self:GetHeight() ~= height then
                MenuWorld.FireScript(self, "OnSizeChanged", self:GetWidth(), self:GetHeight())
            end
        end
    end
    return build(workspace, ...)
end
assert(M.Open("suite_damageMeter") ~= false)
mw:RunTimers()
local preview = assert(ui and ui.meterPreview, "first menu open did not build the preview")
local win = assert(preview.stage.damageMeterMenuPreview, "first menu open skipped the real renderer")
local function Positive(value)
    return type(value) == "number" and value == value and value > 0 and value < math.huge
end
local function Visible()
    assert(ui.ctx.wrapper:IsVisible() and ui.header:IsVisible(), "preview owner is hidden")
    assert(preview.stage:IsVisible() and win.frame:IsVisible(), "real meter sample disappeared")
    assert(preview.targets and #preview.handles > 0, "real sample lacks interactive handles")
    assert(Positive(preview.scale) and Positive(preview.height) and preview.height <= 250.001, "invalid fitted sample geometry")
    assert(preview.stage:GetWidth() >= win.frame:GetWidth(), "stage clips the meter width")
    assert(preview.stage:GetHeight() >= win.frame:GetHeight(), "stage clips the meter height")
    assert(preview.stage:GetWidth() * preview.scale <= preview.availableWidth + .001, "sample exceeds the available width")
    local name, value = win.rows[1].nameText:GetText(), win.rows[1].valueText:GetText()
    assert(win.rows[1]:IsVisible() and type(name) == "string" and #name > 0, "real sample has no visible name")
    assert(type(value) == "string" and #value > 0, "real sample has no value")
    local _, _, _, x, y = win.frame:GetPoint(1)
    assert(x >= 0 and -y >= 0, "meter begins outside its stage")
    assert(x + win.frame:GetWidth() <= win.previewWidth + .001, "meter extends beyond stage right")
    assert(-y + win.frame:GetHeight() <= win.previewHeight + .001, "meter extends beyond stage bottom")
end
Visible()
assert(paints > 0 and preview.selected() == 1, "first open needed a picker change")
assert(not win.timer:IsShown() and not win.sampleTimer, "disabled timer appeared in the initial sample")
local function Click(key)
    assert(ui:Focus("suite_damageMeter_timer"))
    local meta = P.Meta("suite_damageMeter", "damageMeter", key, "setting", "suite_damageMeter_timer")
    local _, control = M.RuntimeControlCatalog.ResolveExactTarget("suite_damageMeter", meta)
    assert(control and control:IsVisible(), "missing visible timer control: " .. key)
    control:GetScript("OnClick")(control)
    mw:RunTimers()
    Visible()
end
Click("combatTime")
assert(config.combatTime and win.timer:IsVisible() and win.timer:GetText() == "(1:35)", "master timer did not reach real preview")
Click("timer")
assert(config.timer and win.sampleTimer:IsVisible(), "floating timer did not reach real preview")
local sampleTimer = win.sampleTimer
local function Set(values)
    assert(P.SetMany("damageMeter", values) ~= false)
    mw:RunTimers()
    Visible()
end
local points = { "TOPLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT", "TOPRIGHT" }
for _, outside in ipairs({ false, true }) do
    for anchor = 1, 5 do
        Set({ timerAnchor = anchor, headerOutside = outside, timerDockX = 7, timerDockY = 9 })
        assert(win.sampleTimer == sampleTimer and sampleTimer:IsVisible(), "docking replaced or hid the timer")
        local point, relative = sampleTimer:GetPoint(1)
        assert(point == points[anchor], "wrong timer docking point")
        local expected = anchor >= 2 and anchor <= 3 and win.header or win.frame
        assert(relative == expected, "timer is attached to the wrong sample region")
        local x, y = sampleTimer.previewX, sampleTimer.previewY
        local _, _, _, fx, fy = win.frame:GetPoint(1)
        assert(x and y and fx + x >= -.001 and -fy + y >= -.001, "timer begins outside the stage")
        assert(fx + x + sampleTimer:GetWidth() <= win.previewWidth + .001, "timer exceeds stage right")
        assert(-fy + y + sampleTimer:GetHeight() <= win.previewHeight + .001, "timer exceeds stage bottom")
    end
end
Click("combatTime")
assert(not config.combatTime and not win.timer:IsShown() and not sampleTimer:IsShown(), "master timer off left a timer visible")
Click("combatTime")
assert(win.timer:IsVisible() and sampleTimer:IsVisible(), "master timer could not restore both samples")
local before = paints
M.HideSlashMenuAndMinibar(M.frame)
mw:RunTimers()
assert(not win.frame:IsVisible(), "closing the menu left the sample visible")
ui.refreshPreview()
assert(paints == before, "hidden preview kept painting")
assert(M.Open("suite_damageMeter") ~= false)
mw:RunTimers()
assert(ui.meterPreview == preview and preview.stage.damageMeterMenuPreview == win, "reopen replaced the sample")
Visible()
assert(win.timer:IsVisible() and sampleTimer:IsVisible(), "reopen lost the enabled timer samples")
assert(not preview.stage:GetScript("OnUpdate"), "preview introduced persistent polling")
print("Meter native preview " .. flavor .. ": first open, real timer controls, all anchors, hidden suspension and reopen passed")
