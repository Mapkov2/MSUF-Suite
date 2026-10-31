-- Actual meter rows and previews; recording/real skin hosts share the same checks.
local root = assert(arg[1]):gsub("\\", "/")
local hostRoot = arg[3]
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
loadfile, issecretvalue = originalLoad, secretTest
local S, D, NS = private.Suite, private.DamageMeter, private.NS
local M = D.M
M:Disable()
M.active = false
assert(originalLoad(root .. "/MSUF_Suite_DamageMeter/Preview.lua"))("MSUF_Suite_DamageMeter", private)
local c = S.Config("damageMeter")
c.iconStyle, c.iconBorder, c.rowBorderMode, c.rowBorderIcon = D.ICON.SPEC, true, D.ROW_BORDER.FULL, true
c.iconSkin = "CUSTOM"
local stage = CreateFrame("Frame", nil, UIParent)
local Region, textures = getmetatable(stage), {}
local createTexture = Region.CreateTexture
Region.CreateTexture = function(self, ...)
    local texture = createTexture(self, ...)
    textures[#textures + 1] = texture
    return texture
end
-- Real material painters use these native texture contracts too.
Region.SetSnapToPixelGrid = Region.SetSnapToPixelGrid or function() end
Region.SetTexelSnappingBias = Region.SetTexelSnappingBias or function() end
local texture, vertex = Region.SetTexture, Region.SetVertexColor
Region.SetTexture = function(self, path, ...) self.texture = path; return texture(self, path, ...) end
Region.SetVertexColor = function(self, ...) self.vertex = { ... }; return vertex(self, ...) end
local function Bridge(api)
    MSUF_HostAPI = api
    assert(originalLoad(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", NS)
    return NS.HostBridge
end
local function Draw() return S.DamageMeterDrawMenuPreview(stage, 1) end
local rule = assert(S.catalog.damageMeter.rules.iconSkin, "meter skin setting missing")
assert(rule.hidden and rule.default == "CUSTOM", "legacy profiles must preserve their own borders")
for _, api in ipairs({ false, { version = 1 } }) do
    Bridge(api or nil)
    c.iconSkin = "SHADOW1"
    local win = Draw()
    assert(not win.rows[1].iconSkinHost and win.rows[1].iconBorder:IsShown(), "old host changed the existing row look")
end
local subscribed, compiles, paints = {}, 0, 0
local shared = { iconSkinDefault = { styleSkin = "SHADOW1" } }
local engine
if hostRoot then
    local A3 = { _runtimeConfigGen = 1 }
    function A3.EnsureDB() return {}, shared end
    local MSUF = { MSUF_Auras3 = A3, Util = { InCombat = function() return false end } }
    local providers = { MSUF_PixelLayoutRegion = function(region) return region end,
        MSUF_EventBus_Register = function() end, MSUF_EventBus_Unregister = function() end }
    dofile(root .. "/tools/tests/suite_test_support.lua").HostMediaProviders(providers)
    function MSUF.Require(name) return assert(providers[name], name) end
    function MSUF.RunHostAPIStep(_, step, ...) return true, step(...) end
    function MSUF.ExportPublic(name, value) MSUF[name] = value end
    for _, file in ipairs({ "Runtime/MSUF_BorderStyles.lua", "Auras3/MSUF_Auras3_IconShape.lua",
        "Auras3/MSUF_Auras3_IconSkins.lua", "Auras3/MSUF_Auras3_IconSkins_Catalog.lua",
        "Auras3/MSUF_Auras3_IconSkins_Host.lua", "Runtime/MSUF_HostAPI.lua" }) do
        assert(originalLoad(hostRoot .. "/MidnightSimpleUnitFrames/" .. file))("MSUF", MSUF)
    end
    engine = MSUF.MSUF_HostAPI.GetIconSkins()
else
    engine = { version = 1, DEFAULT = "DEFAULT" }
    function engine.Compile(choice, shape)
        if choice == "CUSTOM" or choice == "ROUND1" or shape ~= "RECTANGLE" then return nil end
        local id = choice == "DEFAULT" and shared.iconSkinDefault.styleSkin or choice
        return { signature = id }
    end
    function engine.Paint(_, look) return look ~= nil end
end
local proxy = { version = 1, DEFAULT = "DEFAULT" }
function proxy.Compile(...) compiles = compiles + 1; return engine.Compile(...) end
function proxy.Paint(...) paints = paints + 1; return engine.Paint(...) end
function proxy.Subscribe(key, fn) subscribed[key] = fn; return true end
Bridge({ version = 1, GetIconSkins = function() return proxy end })
c.iconSkin = "CUSTOM"
local win = Draw()
local row = win.rows[1]
assert(not row.iconSkinHost and row.iconBorder:IsShown() and paints == 0, "CUSTOM paints or allocates")
c.iconSkin = "DEFAULT"
Draw()
assert(row.iconSkinHost and row.iconSkinHost:IsShown() and not row.iconBorder:IsShown(), "full skin did not replace border")
assert(row.iconSkinLook == M.style.iconSkin and row.iconSkinApplied, "runtime skin differs from preview")
c.iconSize = 37
Draw()
assert(row.iconSkinW == 37 and row.iconSkinH == 37 and row.icon:GetWidth() == 37, "resized skin retained stale dimensions")
c.iconStyle = D.ICON.NONE
Draw()
assert(not row.icon:IsShown() and not row.iconSkinHost:IsShown(), "icon-off setting leaves a floating skin")
c.iconStyle = D.ICON.SPEC
Draw()
assert(row.icon:IsShown() and row.iconSkinHost:IsShown(), "icon re-enable lost skin")
local beforePaint, beforeCompile = paints, compiles
Draw(); Draw(); D.StyleRow(row)
assert(paints == beforePaint and compiles == beforeCompile, "unchanged style repaints or recompiles")
local source = { name = "Player", classFilename = "WARRIOR", specIconID = 132355, totalAmount = 50, amountPerSecond = 5 }
local session = { maxAmount = 100, totalAmount = 100 }
for i = 1, 1000 do
    source.totalAmount = i
    D.PaintSource(row, source, 1, session, win)
end
assert(paints == beforePaint and compiles == beforeCompile, "meter data updates touched skin materials")
D.UnitIcon(row, 0, "", D.ICON.CLASS)
assert(not row.icon:IsShown() and not row.iconSkinHost:IsShown(), "missing class leaves floating shadow/gloss")
D.UnitIcon(row, 132355, "WARRIOR", D.ICON.SPEC)
assert(row.icon:IsShown() and row.iconSkinHost:IsShown(), "recycled row lost its skin")
-- Rows.lua captured IsSecret at load, so use the fixture's sentinel metatable.
local capturedSecret
for i = 1, 30 do
    local name, value = debug.getupvalue(secretTest, i)
    if not name then break end
    if name == "SecretMT" then capturedSecret = setmetatable({}, value) end
end
assert(capturedSecret, "fixture must provide hostile secret values")
D.PaintSpell(row, { spellID = capturedSecret, totalAmount = 5, amountPerSecond = 1 }, session, win.meterType, "WARRIOR")
assert(not row.icon:IsShown() and not row.iconSkinHost:IsShown(), "secret spell ID leaves floating skin")
local skinVisibilityWrites, setShown = 0, row.iconSkinHost.SetShown
row.iconSkinHost.SetShown = function(self, ...)
    skinVisibilityWrites = skinVisibilityWrites + 1
    return setShown(self, ...)
end
local hiddenSpell = { spellID = capturedSecret, totalAmount = 5, amountPerSecond = 1 }
for i = 1, 1000 do D.PaintSpell(row, hiddenSpell, session, win.meterType, "WARRIOR") end
row.iconSkinHost.SetShown = setShown
assert(skinVisibilityWrites == 0, "unchanged secret spell updates rewrite skin visibility: " .. skinVisibilityWrites)
assert(paints == beforePaint and compiles == beforeCompile, "identity changes repainted the skin")
shared.iconSkinDefault.styleSkin = "SHADOW4"
assert(subscribed.MSUF_Suite, "bridge did not subscribe")("apply")
Draw()
assert(row.iconSkinHost:IsShown() and row.iconSkinLook == M.style.iconSkin, "default edit missed disabled preview")
assert(paints > beforePaint and compiles > beforeCompile, "default edit retained stale material")
c.iconSkin = "ROUND1"
Draw()
assert(not row.iconSkinHost:IsShown() and row.iconBorder:IsShown(), "incompatible skin did not restore border")
c.iconSkin = "CUSTOM"
Draw()
assert(not row.iconSkinHost:IsShown() and row.iconBorder:IsShown(), "reset did not restore existing border")
if hostRoot then
    local shadow, gloss = false, false
    for _, art in ipairs(textures) do
        if type(art.texture) == "string" then
            shadow = shadow or art.texture:find("msuf_skin_shadow_soft", 1, true) ~= nil
            gloss = gloss or art.texture:find("msuf_skin_gloss", 1, true) ~= nil
        end
    end
    assert(shadow and gloss, "real host did not paint complete shadow and gloss layers")
end
local bridge, watching = NS.HostBridge
local watch = bridge.WatchIconSkins
bridge.WatchIconSkins = function(id, on)
    assert(id == "damageMeter")
    watching = on
    return watch(id, on)
end
M.config = c
for _, choice in ipairs({ "CUSTOM", "DEFAULT", "SHADOW1", "CUSTOM" }) do
    c.iconSkin = choice
    M:Refresh()
    assert(watching == (choice ~= "CUSTOM"), "meter skin watcher mismatches " .. choice)
end
M:Disable()
assert(watching == false, "disabled meter watches global skins")
bridge.WatchIconSkins = watch
print("meter icon skins: old hosts, runtime/preview, defaults, secret identities, 1000 data updates with zero material work" ..
    (hostRoot and ", real MSUF engine" or ", recording host"))
