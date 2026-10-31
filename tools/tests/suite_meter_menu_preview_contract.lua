-- Reuse the real meter's established native-client fixture and runtime
-- budgets; then check the new isolated menu renderer, including Forever.
local root = assert(arg[1])
local originalLoad, private = loadfile
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    return function(addon, namespace)
        if path:find("MSUF_Suite_DamageMeter/Data.lua", 1, true) then private = namespace end
        return chunk(addon, namespace)
    end
end
local fixture = arg[2] == "Forever" and "suite_damage_meter_threat_contract.lua" or "suite_damage_meter_contract.lua"
assert(originalLoad(root .. "/tools/tests/" .. fixture))()
loadfile = originalLoad
local S, D = private.Suite, private.DamageMeter
local M = D.M
assert(originalLoad(root .. "/MSUF_Suite_DamageMeter/Preview.lua"))("MSUF_Suite_DamageMeter", private)
M:Disable()
M.active = false
local config, snapshot, windows = S.Config("damageMeter"), {}, {}
for key, value in pairs(config) do snapshot[key] = value end
for key, value in pairs(D.windows) do windows[key] = value end
config.w1Width, config.w1Height = 420, 240
config.w1Type, config.w1Session = D.TYPE.DamageDone + 1, D.SESSION.OVERALL
config.iconStyle = D.ICON.NONE
local stage = CreateFrame("Frame", nil, UIParent)
local preview = assert(S.DamageMeterDrawMenuPreview(stage, 1))
assert(preview.frame:GetWidth() == 420 and preview.frame:GetHeight() == 240, "menu did not draw the whole runtime window")
assert(preview.title.text:find("Overall", 1, true), "preview lost the Overall heading")
assert(not preview.rows[1].icon:IsShown(), "preview ignored Icons=None")
assert(preview.rows[1].valueText.text and preview.rows[1].nameText.text, "runtime row formatter did not paint samples")
local layouts, layout = 0, D.StyleWindowLayout
D.StyleWindowLayout = function(...) layouts = layouts + 1; return layout(...) end
local gen = M.styleGen
local sinks = { preview.frame, preview.header, preview.title, preview.timer, preview.rows[1], preview.rows[1].nameText, preview.rows[1].valueText }
local methods = { "SetSize", "SetPoint", "ClearAllPoints", "SetText", "SetFont", "SetShown" }
local savedSinks = {}
for i, region in ipairs(sinks) do
    savedSinks[i] = {}
    for _, key in ipairs(methods) do
        savedSinks[i][key] = rawget(region, key)
        region[key] = function() error("warm meter preview wrote a native sink") end
    end
end
local instructions = 0
debug.sethook(function() instructions = instructions + 1 end, "", 1)
for i = 1, 100 do assert(S.DamageMeterDrawMenuPreview(stage, 1) == preview) end
debug.sethook()
assert(instructions < 600000, "warm meter preview exceeded its bounded settings-scan budget")
for i, region in ipairs(sinks) do for _, key in ipairs(methods) do region[key] = savedSinks[i][key] end end
print("Warm meter source budget: " .. instructions .. " instructions / 100 draws, zero layout/text writes")
assert(layouts == 0 and M.styleGen == gen, "warm meter preview restyled or allocated a new window")
config.w1Width = 460
S.DamageMeterDrawMenuPreview(stage, 1)
assert(layouts == 1 and preview.frame:GetWidth() == 460, "settings did not reach the runtime preview")
if D.THREAT then
    config.w1Type = D.THREAT + 1
    S.DamageMeterDrawMenuPreview(stage, 1)
    assert(preview.rows[1].valueText.text:find("100%%"), "Threat sample did not use runtime threat formatting")
    assert(not preview.rows[1].icon:IsShown(), "Threat sample ignored Icons=None")
end
-- The menu and live meter use these exact same native layout functions.
config.barsOffsetX, config.barsOffsetY = 7, 9
config.iconOffsetX, config.iconOffsetY = 13, 14
config.nameOffsetX, config.nameOffsetY = 17, 18
config.valueOffsetX, config.valueOffsetY = 23, 24
config.titleOffsetX, config.titleOffsetY = 31, 32
config.buttonsOffsetX, config.buttonsOffsetY = 43, 44
config.headerTimerOffsetX, config.headerTimerOffsetY = 51, 52
config.baseline, config.rank, config.iconStyle = 1, true, D.ICON.SPEC
S.DamageMeterDrawMenuPreview(stage, 1)
local function Point(region, index, x, y, message)
    local point = assert(region.points[index])
    assert(point[4] == x and point[5] == y, message)
end
local row = preview.rows[1]
Point(row, 1, 7, 9, "bar group offset did not reach native rows")
Point(row.icon, 1, 13, 14, "icon offset did not reach native rows")
Point(row.rankText, 1, 20, 19, "names and ranks no longer move together")
Point(row.nameText, 2, -12, -6, "value movement pulled or stretched the name field")
Point(row.valueText, 1, 20, 25, "value offset did not reach native rows")
Point(preview.buttons.settings, 1, 40, 44, "header buttons did not move together")
local targetSlot = preview.buttons.target.configuredShown and 20 or 0
-- A threat window has no Session button: the buttons after it and the timer take its slot.
local sessionSlot = preview.buttons.session.configuredShown and 0 or 20
Point(preview.timer, 1, -34 - targetSlot + sessionSlot, 53, "button movement pulled the header timer")
Point(preview.title, 1, 37, 33, "title offset did not reach native header")
Point(preview.title, 2, -91 - targetSlot + sessionSlot, 33, "timer movement pulled or stretched the title field")
-- Exercise the actual cold runtime layout after individual editor settings change.
local order = { "settings", "reset", "session", "type" }
if sessionSlot > 0 then table.remove(order, 3) end
if targetSlot > 0 then order[#order + 1] = "target" end
local priorHeight, priorIconSize = config.headerHeight, config.headerIconSize
config.headerHeight, config.headerIconSize = 14, 30
S.DamageMeterDrawMenuPreview(stage, 1)
assert(preview.buttons.session:GetWidth() == 14, "Auto header button size did not respect header height")
config.headerHeight, config.headerIconSize = priorHeight, priorIconSize
S.DamageMeterDrawMenuPreview(stage, 1)
local function CaptureHeader()
    local positions = {}
    for _, kind in ipairs(order) do
        local button, point = preview.buttons[kind], preview.buttons[kind].points[1]
        positions[kind] = { point[2], point[4], point[5], button:GetWidth() }
    end
    for _, kind in ipairs({ "title", "timer" }) do
        local region = preview[kind]
        positions[kind] = { region.points[1][2], region.points[1][4], region.points[1][5], region.font[2] }
    end
    return positions
end
local function Unchanged(before, selected)
    local after = CaptureHeader()
    for kind, values in pairs(before) do
        if kind ~= selected then
            for i, value in ipairs(values) do assert(after[kind][i] == value, "individual header edit pulled a sibling: " .. kind) end
        end
    end
end
for index, kind in ipairs(order) do
    local before = CaptureHeader()
    config[kind .. "OffsetX"], config[kind .. "OffsetY"], config[kind .. "Size"] = 19, -11, 29
    S.DamageMeterDrawMenuPreview(stage, 1)
    local button = preview.buttons[kind]
    assert(button.points[1][2] == preview.header, "header button retains a sibling anchor chain")
    Point(button, 1, 59 - (index - 1) * 20, 33, "individual header offsets did not reach runtime")
    assert(button:GetWidth() == 29 and button:GetHeight() == 29, "individual header size did not reach runtime")
    Unchanged(before, kind)
end
for _, spec in ipairs({ { "title", "titleOffset", "titleSize" }, { "timer", "headerTimerOffset", "headerTimerSize" } }) do
    local kind, prefix, size = unpack(spec)
    local before = CaptureHeader()
    config[prefix .. "X"], config[prefix .. "Y"], config[size] = 27, -13, 21
    S.DamageMeterDrawMenuPreview(stage, 1)
    assert(preview[kind].font[2] == 21, "individual header font size did not reach runtime: " .. kind)
    assert(preview[kind].points[1][2] == preview.header, "header text retains a sibling anchor chain")
    assert(preview[kind].points[1][5] == -12, "individual header text offsets did not reach runtime")
    if kind == "title" then assert(preview.title.points[2][5] == -12, "title anchors disagree on the baseline") end
    Unchanged(before, kind)
end
for _, kind in ipairs({ "spell", "tip" }) do
    local detail = D.CreateRow(preview.body, preview, kind)
    D.AnchorRow(detail, preview.body, 1)
    D.StyleRow(detail)
    Point(detail, 1, 0, 0, "meter offsets moved a breakdown row")
    Point(detail.icon, 1, 0, 0, "meter offsets moved a breakdown icon")
    Point(detail.valueText, 1, -3, 1, "meter offsets moved breakdown values")
end
for key, value in pairs(windows) do assert(D.windows[key] == value and value ~= preview, "menu borrowed a live meter window") end
assert(not M.active and not M.preview, "menu enabled the meter or its live preview mode")
for key, value in pairs(config) do config[key] = snapshot[key] end
D.StyleWindowLayout = layout
print("Meter menu preview: whole runtime window, formatters, Threat, isolation and warm cache passed")
