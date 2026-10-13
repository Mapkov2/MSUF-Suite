-- Real runtime, shared MSUF levels, sparse identities and hostile native sinks.
local root = assert(arg[1]):gsub("\\", "/")
local originalLoad, private, secretTest = loadfile
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    return function(addon, namespace)
        if path:find("MSUF_Suite_DamageMeter/Data.lua", 1, true) then private, secretTest = namespace, issecretvalue end
        return chunk(addon, namespace)
    end
end
local fixture = arg[2] == "Forever" and "suite_damage_meter_threat_contract.lua" or "suite_damage_meter_contract.lua"
assert(originalLoad(root .. "/tools/tests/" .. fixture))()
loadfile = originalLoad
local S, D, NS = private.Suite, private.DamageMeter, private.NS
local M = D.M
assert(originalLoad(root .. "/MSUF_Suite_DamageMeter/Preview.lua"))("MSUF_Suite_DamageMeter", private)
-- Execute the shared host implementation instead of reproducing its formula.
local hostLayers = {}
assert(originalLoad(root .. "/../MidnightSimpleUnitFrames/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Layers.lua"))("MSUF", hostLayers)
MSUF_NS.UF = hostLayers.UF
local Host = MSUF_NS.UF.Layers
M:Disable()
M.active = false
local c = S.Config("damageMeter")
c.iconStyle, c.iconBorder, c.rowBorderMode, c.rowBorderIcon = D.ICON.SPEC, true, D.ROW_BORDER.FULL, true
c.iconOffsetX, c.iconOffsetY, c.iconSize = 6, -4, 0
c.barsLayer, c.iconLayer, c.nameLayer, c.valueLayer = -1, -1, -1, -1

-- Native globals are read-only, and every tested frame write must target
-- a new Suite-owned nonsecure descendant. A protected/foreign sink fails.
for _, name in ipairs({ "C_DamageMeter", "C_Texture", "C_Spell", "RAID_CLASS_COLORS", "CLASS_ICON_TCOORDS" }) do
    local original = _G[name]
    _G[name] = setmetatable({}, { __index = original, __newindex = function() error("Blizzard table write: " .. name) end })
end
local nativeCreate, owned, writes = CreateFrame, {}, 0
CreateFrame = function(kind, name, parent, template)
    assert(not template or not template:find("Secure", 1, true), "preview created a protected template")
    local frame = nativeCreate(kind, name, parent, template)
    owned[frame] = true
    return frame
end
local stage = CreateFrame("Frame", nil, UIParent)
local Region = getmetatable(stage)
local function IsOwned(region)
    return owned[region] or region.parent and IsOwned(region.parent)
end
for _, method in ipairs({ "SetFrameLevel", "SetPoint", "SetAllPoints", "SetSize", "SetTexture" }) do
    local native = assert(Region[method])
    Region[method] = function(self, ...)
        assert(IsOwned(self) and not self.protected and not self.forbidden, "protected or foreign native write: " .. method)
        writes = writes + 1
        return native(self, ...)
    end
end
local win = S.DamageMeterDrawMenuPreview(stage, 1)
local row = win.rows[1]
assert(row.icon:GetParent() == row.iconHost and row.iconHost:GetParent() == row, "icon lacks an owned sibling plane")
assert(row.nameText:GetParent() == row.nameHost and row.valueText:GetParent() == row.valueHost)
assert(row.track:GetParent() == row.bar, "bar track did not follow its selected draw plane")
assert(row.iconHost:GetFrameLevel() > row.bar:GetFrameLevel(), "Auto icon remains behind the bar")
assert(row.iconBorder:GetParent() == row.iconHost and row.iconBorder:GetFrameLevel() == row.iconHost:GetFrameLevel() + 1)
assert(row.fillBorder.points[1][2] == row, "full border follows a displaced icon instead of the reserved column")
local function Draw() return S.DamageMeterDrawMenuPreview(stage, 1) end
local function Expected(slot, detail, target)
    return Host.ElementLevel(slot, 0, detail) - Host.ElementLevel(0, 0, 0) + target:GetFrameLevel()
end
local scenarios = 0
for barLayer = 0, 30 do
    for iconLayer = 0, 30 do
        c.barsLayer, c.iconLayer, c.nameLayer, c.valueLayer = barLayer, iconLayer, 30 - barLayer, iconLayer
        Draw()
        assert(row.bar:GetFrameLevel() == Expected(barLayer, 0, row), "bar ignored the shared layer slot")
        assert(row.iconHost:GetFrameLevel() == Expected(iconLayer, 0, row), "icon ignored the shared layer slot")
        assert(row.nameHost:GetFrameLevel() == Expected(30 - barLayer, 8, row), "name ignored its independent slot")
        assert(row.valueHost:GetFrameLevel() == Expected(iconLayer, 8, row), "value ignored its independent slot")
        assert(row.fillBorder:GetFrameLevel() == row.bar:GetFrameLevel() + 2, "row border did not follow its bar slot")
        scenarios = scenarios + 1
    end
end
-- The real live surface uses absolute MSUF slots; the preview changes only bias.
row.win.menuPreview = false
D.StyleRow(row)
D.UnitIcon(row, 132355, "WARRIOR", D.ICON.SPEC)
assert(row.iconHost:GetFrameLevel() == Host.ElementLevel(30, 0, 0), "live icon does not share MSUF's absolute slot")
row.win.menuPreview = true
c.barsLayer, c.iconLayer, c.nameLayer, c.valueLayer = 30, -1, -1, -1
Draw()
assert(row.iconHost:GetFrameLevel() == row.bar:GetFrameLevel() + 2, "returning to Auto did not follow the current bar")
c.barsLayer = 0
Draw()
assert(row.iconHost:GetFrameLevel() == row.bar:GetFrameLevel() + 2, "Auto retained a stale remembered frame level")

-- Old per-identity data must never override the shared icon layout.
c.iconOverrides = "S.WARRIOR.132355=200,-200,30,40;C.MAGE=-83,29,4,17;"
c.iconOffsetX, c.iconOffsetY, c.iconSize, c.iconLayer = 23, -17, 31, 12
for _, mode in ipairs({ D.ICON.CLASS, D.ICON.SPEC }) do
    c.iconStyle = mode
    Draw()
    for _, source in ipairs({ { "WARRIOR", 132355 }, { "MAGE", 135932 }, { "PRIEST", 135940 } }) do
        for _, target in ipairs({ row, win.rows[2] }) do
            D.UnitIcon(target, source[2], source[1], mode)
            assert(target.icon.points[1][4] == 23 and target.icon.points[1][5] == -17, "class/spec icons did not share their position")
            assert(target.icon:GetWidth() == 31, "class/spec icons did not share their size")
            assert(target.iconHost:GetFrameLevel() == Expected(12, 0, target), "class/spec icons did not share their layer")
        end
    end
end
local stage2 = CreateFrame("Frame", nil, UIParent)
local win2 = S.DamageMeterDrawMenuPreview(stage2, 2)
assert(win2.rows[1].icon.points[1][4] == 23, "another window lost shared icon position")
c.iconSize = 0
Draw()
assert(row.icon:GetWidth() == M.style.barHeight, "Auto size did not inherit bar height")
local coldWrites = writes
for i = 1, 100 do Draw() end
assert(writes == coldWrites, "warm sample preview performed native layout writes")
D.UnitIcon(row, 135932, "MAGE", D.ICON.SPEC)
local anchors = writes
for i = 1, 100 do D.UnitIcon(row, 135932, "MAGE", D.ICON.SPEC) end
assert(writes == anchors, "unchanged live icon restyled artwork")
local secret = setmetatable({}, select(2, debug.getupvalue(secretTest, 1)))
assert(secretTest(secret), "secret sentinel fixture drifted")
local source = { name = "Secret source", classFilename = secret, specIconID = secret, totalAmount = 42, amountPerSecond = 7 }
D.PaintSource(row, source, 1, { maxAmount = 42, totalAmount = 42 }, win)
assert(row.iconKey == "", "secret class became a persistent icon key")
-- Prove the native poison actually rejects a foreign/protected sink.
local poison = nativeCreate("Frame")
local ok, message = pcall(function() poison:SetFrameLevel(99) end)
assert(not ok and message:find("protected or foreign", 1, true))
for frame in pairs(owned) do assert(not frame:GetScript("OnUpdate"), "layer feature introduced polling") end
print("Meter icon simulation: " .. scenarios .. " layer combinations, shared class/spec/window layout, legacy data isolation, secrets, poisoned native sinks and warm cache passed")
