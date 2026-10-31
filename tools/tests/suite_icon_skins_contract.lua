local root = assert(arg[1], "repository root required")
-- MSUF's icon skins on the Suite's cooldown manager icons (HostBridge icon
-- skin section, CDM Settings/Icons/TrackingBars). Argument 2 (optional) is an
-- MSUF 7.0 checkout: its real skin engine, catalog, host interface and
-- MSUF_HostAPI then paint; without it a recording host stands in.
--   1. hosts: no MSUF_HostAPI, a host API without GetIconSkins (every MSUF
--      before 7.0) and an interface below version 1 leave every icon with the
--      Suite's own look and never call MSUF;
--   2. looks are compiled once per icon shape and choice and shared until
--      MSUF reports a change; a report recompiles and refreshes only the
--      modules that draw skins;
--   3. a bar's look (Settings.ReadViews): its choice and MSUF's default skin
--      reach view.skin, a new look bumps styleGen exactly once, an unchanged
--      look (also a recompiled one) never;
--   4. icons (Icons.StyleIcon): a skin draws the border (the texture fills the
--      frame, the edges hide) as textures of the icon around its texture, a
--      timer bar's square icon too; an unchanged restyle writes nothing to
--      the skin; an icon that never had a skin never calls MSUF;
--   5. combat parity: icons made in combat (pool growth, a reload in combat)
--      get exactly the look of the icons beside them; MSUF's reports arrive
--      out of combat only, and a report in combat leaves the bars alone until
--      the module refresh the Suite queues for combat end;
--   6. with the real host: the painter writes no field on a frame it paints;
--      a skin made for round icons never reaches the square cooldown icons;
--   7. shapes: a bar's icon shape (iconShape) reaches view.shape and restyles
--      it; the icon art, its swipes and its press flash take MSUF's shape over
--      the icon texture; rings of the shape replace the square edges (a skin
--      draws its own border instead); a host without shapes keeps every icon
--      square with its edges; with the real host the masks write no field.
local hostRoot = arg[2]
securecallfunction = function(fn, ...) return fn(...) end

local function Check(condition, message)
    if not condition then error(message, 2) end
end

------------------------------------------------------------------ widgets
local writes = 0
local Widget = {}
Widget.__index = Widget
-- FontStrings take no masks (Blizzard's API: only textures have AddMaskTexture).
local TextWidget = { __index = function(_, key)
    if key == "AddMaskTexture" or key == "RemoveMaskTexture" then return nil end
    return Widget[key]
end }
local function New(kind, parent)
    local widget = setmetatable({ kind = kind, parent = parent, calls = {}, children = {}, shown = true,
        level = parent and (parent.level or 0) + 1 or 1, w = 0, h = 0 }, kind == "FontString" and TextWidget or Widget)
    if parent and parent.children then parent.children[#parent.children + 1] = widget end
    return widget
end
local function Record(name, apply)
    Widget[name] = function(self, a, b, c, d, e)
        self.calls[name] = (self.calls[name] or 0) + 1
        writes = writes + 1
        if apply then return apply(self, a, b, c, d, e) end
    end
end
for _, name in ipairs({ "SetTexCoord", "SetTexture", "SetAtlas", "SetColorTexture", "SetVertexColor", "SetBlendMode",
    "SetAlpha", "SetDesaturated", "SetDesaturation", "SetScript", "EnableMouse", "EnableMouseMotion", "SetAttribute",
    "SetSwipeColor", "SetSwipeTexture", "SetDrawEdge", "SetDrawSwipe", "SetDrawBling", "SetReverse",
    "SetHideCountdownNumbers", "SetCountdownFormatter", "Clear", "SetTextColor", "SetText", "SetJustifyH", "SetJustifyV",
    "SetWordWrap", "SetShadowColor", "SetShadowOffset", "SetStatusBarTexture", "SetStatusBarColor", "SetMinMaxValues",
    "SetValue", "SetFontObject", "SetSnapToPixelGrid", "SetTexelSnappingBias", "SetIgnoreParentScale", "SetDesaturated" }) do
    Record(name)
end
Record("SetFont", function(self, path) self.font = path end)
Record("SetDrawLayer", function(self, layer, sublevel) self.layer, self.sublevel = layer, sublevel end)
Record("SetSize", function(self, w, h) self.w, self.h = w, h end)
Record("SetWidth", function(self, w) self.w = w end)
Record("SetHeight", function(self, h) self.h = h end)
Record("SetFrameLevel", function(self, level) self.level = level end)
Record("ClearAllPoints", function(self) self.points = {} end)
Record("SetPoint", function(self, point, rel, relPoint, x, y)
    self.points = self.points or {}
    self.points[#self.points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
end)
Record("SetAllPoints", function(self, rel)
    self.points = { { point = "ALL", rel = rel } }
end)
Record("SetShown", function(self, shown) self.shown = shown == true end)
Record("Show", function(self) self.shown = true end)
Record("Hide", function(self) self.shown = false end)
function Widget:IsShown() return self.shown end
function Widget:GetFrameLevel() return self.level end
function Widget:GetWidth() return self.w end
function Widget:GetHeight() return self.h end
function Widget:GetFont() return self.font, 12, "" end
function Widget:GetCountdownFontString()
    self.countdown = self.countdown or New("FontString", self)
    return self.countdown
end
function Widget:CreateTexture(_, layer, _, sublevel)
    writes = writes + 1
    local texture = New("Texture", self)
    texture.layer, texture.sublevel = layer, sublevel
    return texture
end
function Widget:CreateFontString(_, layer)
    writes = writes + 1
    local text = New("FontString", self)
    text.layer = layer
    return text
end
function Widget:CreateMaskTexture() return New("MaskTexture", self) end
local maskOf = setmetatable({}, { __mode = "k" })
function Widget:AddMaskTexture(mask) writes = writes + 1; maskOf[self] = mask end
function Widget:RemoveMaskTexture(mask)
    writes = writes + 1
    if maskOf[self] == mask then maskOf[self] = nil end
end
-- A cooldown's regions: its countdown FontString once it was asked for.
function Widget:GetNumRegions() return self.countdown and 1 or 0 end
function Widget:GetRegions() return self.countdown end
local framesMade = 0
CreateFrame = function(kind, _, parent)
    framesMade = framesMade + 1
    return New(kind or "Frame", parent)
end
UIParent = New("Frame")

------------------------------------------------------------------ suite core (catalog, surfaces, fonts)
MSUF_NS = { Client = { Family = "Mainline", Flavor = "Mainline", IsRetail = true, SupportsEvent = function() return true end } }
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
C_CooldownViewer = { GetCooldownViewerCategorySet = function() return {} end, GetCooldownViewerCooldownInfo = function() end }
MSUF_EncodeCompactTable = function() return "" end
MSUF_TryDecodeCompactString = function() return nil end
RAID_CLASS_COLORS = { MAGE = { r = .25, g = .78, b = .92 } }
UnitClass = function() return "Mage", "MAGE" end
local inCombat = false
InCombatLockdown = function() return inCombat end
Enum = { StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 } }
Constants = { SpellCooldownConsts = { GLOBAL_RECOVERY_CATEGORY = 133 } }
GameFontHighlightSmall = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
local NS = {}
for _, file in ipairs({ "Core/Platform.lua", "Core/Database.lua", "Core/SuiteCatalog.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite/" .. file))("MSUF_Suite", NS)
end
do
    local B = NS.CatalogBuild
    local original = B.Module
    B.Module = function(id, spec)
        if id ~= "cooldownManager" then return original(id, spec) end
        spec.id, spec.addon, spec.controls, spec.rules, spec.conflicts = id, "MSUF_Suite_CooldownManager", {}, {}, spec.conflicts or {}
        NS.SuiteCatalog[id], NS.SuiteOrder[#NS.SuiteOrder + 1] = spec, id
        B.Add(id, B.Bool("enabled", "Enable module", false))
        return spec
    end
end
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/CooldownManager.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/CooldownManagerData.lua"))("MSUF_Suite", NS)
local S = {}
NS.Suite = S
MSUFSuite = NS
assert(loadfile(root .. "/MSUF_Suite/Core/FontBridge.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite_Modules/Surfaces.lua"))("MSUF_Suite_Modules", {})
S.Text = function(text) return text end
S.Public = function() return true end
local applied = {}
S.Apply = function(id) applied[#applied + 1] = id end

------------------------------------------------------------------ hosts
-- A recording host that keeps the interface contract (version 1).
local function RecordingHost()
    local host = { version = 1, DEFAULT = "DEFAULT", CUSTOM = "CUSTOM", compiles = 0, paints = {}, default = "SHADOW1",
        subscribed = {} }
    function host.Compile(choice, shape)
        host.compiles = host.compiles + 1
        if choice == "CUSTOM" then return nil end
        local id = (choice == nil or choice == "DEFAULT") and host.default or choice
        if id == "CUSTOM" or (shape or "RECTANGLE") ~= "RECTANGLE" then return nil end
        return { signature = "K:" .. id .. ":" .. tostring(host.look) }
    end
    function host.Paint(owner, look, width, height, anchor, clip)
        host.paints[#host.paints + 1] = { owner = owner, look = look, w = width, h = height, anchor = anchor, clip = clip }
        return look ~= nil
    end
    function host.ShapeOf(choice) return choice == "ROUND1" and "CIRCLE" or choice ~= "CUSTOM" and "RECTANGLE" or nil end
    function host.Subscribe(key, fn) host.subscribed[key] = fn return true end
    function host.Unsubscribe(key) host.subscribed[key] = nil return true end
    host.shapes = {}
    function host.ApplyShape(owner, shape, anchor, cooldowns, ...)
        host.shapes[#host.shapes + 1] = { owner = owner, shape = shape, anchor = anchor, cooldowns = cooldowns,
            textures = { ... } }
        return shape
    end
    function host.ShapeArt(shape)
        if shape == "RECTANGLE" then return nil end
        return "ring:" .. shape, "fill:" .. shape, shape == "STAR", shape == "STAR"
    end
    return host
end

-- MSUF 7.0's real skin files and MSUF_HostAPI in a minimal namespace.
local realBus = {}
local function RealHost()
    local A3 = { _runtimeConfigGen = 1 }
    local shared = { iconSkinDefault = { styleSkin = "SHADOW1" } }
    function A3.EnsureDB() return {}, shared end
    local MSUF = { MSUF_Auras3 = A3, Util = { InCombat = function() return inCombat end } }
    local providers = {
        MSUF_PixelLayoutRegion = function(region) return region end,
        MSUF_EventBus_Register = function(event, key, fn) realBus[event] = fn end,
        MSUF_EventBus_Unregister = function(event) realBus[event] = nil end,
    }
    dofile(root .. "/tools/tests/suite_test_support.lua").HostMediaProviders(providers)
    function MSUF.Require(name) return assert(providers[name], "unexpected dependency " .. tostring(name)) end
    function MSUF.RunHostAPIStep(_, step, ...) return true, step(...) end
    function MSUF.ExportPublic(name, value) MSUF[name] = value end
    UnitAffectingCombat = function() return inCombat end
    local addon = hostRoot .. "/MidnightSimpleUnitFrames/"
    for _, file in ipairs({ "Runtime/MSUF_BorderStyles.lua", "Auras3/MSUF_Auras3_IconShape.lua",
        "Auras3/MSUF_Auras3_IconSkins.lua", "Auras3/MSUF_Auras3_IconSkins_Catalog.lua",
        "Auras3/MSUF_Auras3_IconSkins_Host.lua", "Runtime/MSUF_HostAPI.lua" }) do
        assert(loadfile(addon .. file))("MidnightSimpleUnitFrames", MSUF)
    end
    return MSUF.MSUF_HostAPI, A3, shared
end

-- A fresh HostBridge (it resolves the host once) on the given host table.
local function Bridge(hostAPI)
    MSUF_HostAPI = hostAPI
    assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", NS)
    assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua"))("MSUF_Suite", NS)
    return NS.HostBridge
end

-- 1. Hosts without icon skins ---------------------------------------------------
do
    local legacy = { version = 1, ApplyUIScaleProfile = function() end, SetResourceStack = function() end }
    for name, api in pairs({ none = false, v1 = legacy, below = { version = 1, GetIconSkins = function()
        return { version = 0, Compile = error, Paint = error, Subscribe = error } end } }) do
        local bridge = Bridge(api or nil)
        Check(bridge.IconSkins() == nil, name .. ": a host without icon skins must answer nil")
        Check(bridge.IconSkinLook("DEFAULT") == nil and bridge.IconSkinLook("SHADOW1", "CIRCLE") == nil, name .. ": no look")
        Check(bridge.PaintIconSkin(New("Frame"), nil, 36, 36) == false, name .. ": nothing paints")
        -- MSUF's Icon Skins page can come without the painter (an MSUF build
        -- with the page but before GetIconSkins): no area, no status row.
        local registered = 0
        local page = { IconSkinsPage = { STATUS_ROW_KEY_FUNCTION = true, StatusRow = function() return 48 end,
            RegisterArea = function() registered = registered + 1 return true end } }
        Check(bridge.RegisterIconSkinAreas(page, { { key = "a" } }) == 0 and registered == 0,
            name .. ": a page without MSUF's painter must get no Suite areas")
        Check(bridge.IconSkinStatusRow(page, {}, nil, 0, 0, 100, "a") == 0, name .. ": and no status row")
        Check(bridge.IconSkinShape("SHADOW1") == nil, name .. ": no shape to match")
        bridge.WatchIconSkins("cooldownManager", true)
    end
end

-- 2. Looks and reports ----------------------------------------------------------
local host = RecordingHost()
local bridge = Bridge({ version = 1, GetIconSkins = function() return host end })
Check(bridge.IconSkins() == host and host.subscribed.MSUF_Suite, "the Suite must subscribe once under its own key")
local look = bridge.IconSkinLook("DEFAULT")
Check(look and bridge.IconSkinLook(nil) == look and bridge.IconSkinLook("DEFAULT") == look, "one table per look")
Check(host.compiles == 1, "a choice must compile once until MSUF reports a change")
Check(bridge.IconSkinLook("DEFAULT", "CIRCLE") == nil and host.compiles == 2, "each icon shape compiles on its own")
Check(bridge.IconSkinLook("CUSTOM") == nil and bridge.IconSkinLook("CUSTOM") == nil and host.compiles == 3, "no skin is kept too")
bridge.WatchIconSkins("cooldownManager", true)
bridge.WatchIconSkins("actionbars", true)
bridge.WatchIconSkins("actionbars", false)
local hookAt
bridge.OnIconSkinsChanged("contract", function() hookAt = #applied end)
host.default = "DARK2"
host.subscribed.MSUF_Suite("apply")
Check(#applied == 1 and applied[1] == "cooldownManager", "a report must refresh exactly the modules that draw skins")
Check(hookAt == 0, "settings that wait for MSUF's default are written before the modules refresh")
bridge.OnIconSkinsChanged("contract", nil)
-- The modules that draw skins watch MSUF's reports while they are enabled.
for id, file in pairs({ cooldownManager = "MSUF_Suite_CooldownManager/Controller.lua",
    actionbars = "MSUF_Suite_ActionBars/Controller.lua" }) do
    local handle = assert(io.open(root .. "/" .. file, "rb"))
    local text = handle:read("*a")
    handle:close()
    Check(text:find('WatchIconSkins("' .. id .. '", true)', 1, true) and text:find('WatchIconSkins("' .. id .. '", false)', 1, true),
        file .. " must watch MSUF's reports while enabled")
end
local after = bridge.IconSkinLook("DEFAULT")
Check(after and after ~= look and after.signature:find("DARK2", 1, true), "a report must recompile")
-- A module whose settings a hook just wrote (and so refreshed) is not
-- refreshed a second time by the report.
bridge.OnIconSkinsChanged("contract", function(refreshed) refreshed.cooldownManager = true end)
applied = {}
host.subscribed.MSUF_Suite("apply")
Check(#applied == 0, "a module a hook refreshed must not refresh twice")
bridge.OnIconSkinsChanged("contract", nil)
host.subscribed.MSUF_Suite("apply")
Check(#applied == 1, "without the hook the report refreshes it")
applied = {}

-- The frame reach of a look (MSUF's Outset) for the CDM's anchor footprint
-- (Layout.FitAnchor: settled by the settings read, a scale change and a new
-- bar, never by the flush's units; suite_cooldown_manager_contract counts it
-- through the real controller and flush).
do
    host.Outset = function(look, w, h) return look and 2 or 0, look and 1 or 0 end
    local x, y = bridge.IconSkinOutset({ skin = {} }, 36, 36)
    Check(x == 2 and y == 1, "the outset comes from MSUF")
    x, y = bridge.IconSkinOutset(nil, 36, 36)
    Check(x == 0 and y == 0, "no look reaches nowhere")
    local handle = assert(io.open(root .. "/MSUF_Suite_CooldownManager/Flush.lua", "rb"))
    local flush = handle:read("*a")
    handle:close()
    Check(not flush:find("FitAnchor", 1, true), "the flush's units must run the plain code (no anchor footprint)")
end

-- The in-combat event paths stay Suite main's code with or without a skin
-- (owner, 2026-10-17: no extra CPU in combat): the glow show, the cooldown
-- events' glow restyle and both glow paint memos never look at a shape (a
-- shape change drops the memos in the style pass: Icons.lua's Shape,
-- AuraGlows.Reshape).
do
    local function Source(rel)
        local handle = assert(io.open(root .. "/" .. rel, "rb"))
        local text = handle:read("*a"):gsub("\r\n", "\n")
        handle:close()
        return text
    end
    local function Body(text, head)
        local start = assert(text:find(head, 1, true), head)
        return text:sub(start, assert(text:find("\nend\n", start, true), head))
    end
    local effects = Source("MSUF_Suite_CooldownManager/Effects.lua")
    local glows = Source("MSUF_Suite_CooldownManager/AuraGlows.lua")
    for _, head in ipairs({ "local function ShowGlow(", "local function Restyle(", "function Effects.Refit(" }) do
        local body = Body(effects, head)
        Check(not body:find("shape", 1, true) and not body:find("Stale", 1, true), head .. " must run Suite main's code")
    end
    -- The icon style without a skin or shape anywhere (also a relayout's row
    -- size in combat) is Suite main's StyleIcon: StylePlain.
    local plain = Body(Source("MSUF_Suite_CooldownManager/Icons.lua"), "local function StylePlain(")
    Check(not plain:find("decor", 1, true) and not plain:find("skin", 1, true) and not plain:find("shape", 1, true),
        "the plain icon style must be Suite main's")
    Check(effects:find("glow.pH == h and glow.pPx == px then return end", 1, true), "the glow paint memo must be Suite main's")
    -- A first press makes its flash inline, as Suite main does (no helper call).
    Check(not Body(effects, "function Effects.Press("):find("Pulse(", 1, true), "the first press must run Suite main's code")
    Check(not Body(glows, "local function Painted("):find("shape", 1, true), "the aura glow paint memo must be Suite main's")
end

-- The menu half: the area rows and the module pages' status row both live on
-- MSUF's Icon Skins page (M.IconSkinsPage); a key function needs the page's
-- marker (a page with a bar selector); older hosts get no rows and no row.
do
    Check(bridge.IconSkinStatusRow(nil, {}, nil, 0, 0, 100, "suite_actionbars") == 0, "no menu, no status row")
    local rows = {}
    local page = { StatusRow = function(_, _, _, _, _, key) rows[#rows + 1] = key return 48 end }
    local menu = { IconSkinsPage = page }
    Check(bridge.IconSkinStatusRow(menu, {}, nil, 0, 0, 100, "suite_actionbars") == 48 and rows[1] == "suite_actionbars",
        "a fixed key reaches the page")
    local keyFn = function() return "suite_cdm_ess" end
    Check(bridge.IconSkinStatusRowFor(menu, {}, nil, 0, 0, 100, keyFn) == 0 and #rows == 1, "a key function needs the marker")
    page.STATUS_ROW_KEY_FUNCTION = true
    Check(bridge.IconSkinStatusRowFor(menu, {}, nil, 0, 0, 100, keyFn) == 48 and rows[2] == keyFn, "a key function with the marker")
    local added = {}
    page.RegisterArea = function(spec) added[#added + 1] = spec return spec.key ~= "dup" end
    Check(bridge.RegisterIconSkinAreas(menu, { { key = "a" }, { key = "dup" }, { key = "b" } }) == 2 and #added == 3,
        "every area is offered and the page's answer counted")
    Check(bridge.RegisterIconSkinAreas({}, { { key = "a" } }) == 0, "an older host has no Icon Skins page")
end

------------------------------------------------------------------ CDM render files
local C = { M = {}, EMPTY = {}, views = {}, plans = {}, bars = {}, entries = {}, Diagnostics = {},
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    state = { px = 1, font = "Fonts\\TEST.TTF", fontFlags = "OUTLINE", cdR = 1, cdG = 1, cdB = 1, stackR = 1, stackG = 1,
        stackB = 1, keyR = 1, keyG = 1, keyB = 1, threshold = 0 } }
C.Flush = { dirty = {}, sync = {}, style = {}, behavior = {}, visible = {} }
local fitted = {} -- slot -> FitAnchor calls (the MSUF anchor footprint)
C.Layout = { PixelScale = function() return 1 end, Forget = function() end,
    FitAnchor = function(slot) fitted[slot] = (fitted[slot] or 0) + 1 end }
-- Effects: the glow side is the render contract's; the decoration makes a
-- shaped icon's press flash here (Effects.PreparePulse).
local standIns -- the stand-ins' code the settings read picked (AuraPlaceholders.lua)
C.AuraButtons = { StandIns = function(any) standIns = any end }
C.Effects = { Refit = function() end, Shapes = function() end, Reshaped = function() end, ParkPulse = function() end,
    PreparePulse = function(icon)
        if icon.pressPulse then return end
        local overlay = New("Texture")
        icon.pressPulse = { GetParent = function() return overlay end }
    end }
local P = { NS = NS, Suite = S, CDM = C }
for _, file in ipairs({ "Const.lua", "Icons.lua", "TrackingBars.lua", "Settings.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/" .. file))("MSUF_Suite_CooldownManager", P)
end
local K, Icons, Settings = C.Const, C.Icons, C.Settings
local rules = NS.SuiteCatalog.cooldownManager.rules
local function Config()
    local config = {}
    for key, rule in pairs(rules) do config[key] = rule.default end
    return config
end
Check(rules.ess_iconSkin and rules.ess_iconSkin.default == "DEFAULT" and rules.ess_iconSkin.hidden,
    "every bar needs a hidden iconSkin rule that follows the default")
for _, slot in ipairs(NS.CDM.SLOTS) do
    Check(NS.CDM.KEYS[slot.key].iconSkin, slot.key .. ": no icon skin rule")
end

-- 3. A bar's look ---------------------------------------------------------------
local config = Config()
Settings.ReadViews(config, true, false)
local ess, uti = C.views.ess, C.views.uti
Check(standIns == true, "a bar with a skin must switch the stand-ins to their skinned code")
Check(ess.skin == bridge.IconSkinLook("DEFAULT") and ess.skin ~= nil, "Like default must reach the bar's look")
local gen = ess.styleGen
C.wipe(C.Flush.style)
Settings.ReadViews(config, false, false)
Check(ess.styleGen == gen and not C.Flush.style.ess, "an unchanged look must not restyle")
config.uti_iconSkin = "CUSTOM"
local utiGen = uti.styleGen
Settings.ReadViews(config, false, false)
Check(uti.skin == nil and uti.styleGen == utiGen + 1 and C.Flush.style.uti, "No skin must restyle that bar once")
Check(ess.styleGen == gen, "another bar's choice must not restyle this one")
-- A report recompiles: an equal look keeps the generation, a new one bumps it.
host.subscribed.MSUF_Suite("apply")
Settings.ReadViews(config, false, false)
Check(ess.styleGen == gen and ess.skin == bridge.IconSkinLook("DEFAULT"), "a recompiled equal look must not restyle")
host.default = "SHADOW4"
host.subscribed.MSUF_Suite("apply")
Settings.ReadViews(config, false, false)
Check(ess.styleGen == gen + 1, "MSUF's new default must restyle every bar that follows it once")
Check(uti.styleGen == utiGen + 1, "a bar with No skin must not follow MSUF's default")

-- 4. Icons ----------------------------------------------------------------------
local parent = New("Frame")
local function Styled(view)
    local icon = Icons.CreateStandalone(parent)
    Icons.StyleIcon(icon, view)
    return icon
end
-- The icon's own edges (a shaped icon's plain style places a hidden set).
local function EdgesShown(icon)
    local edges = icon.ownEdges or icon.edges
    for i = 1, 4 do if edges[i].shown then return true end end
    return false
end
host.paints = {}
local plain = Styled(uti)
Check(#host.paints == 0, "an icon that never had a skin must never call MSUF")
Check(EdgesShown(plain) and plain.border > 0, "No skin keeps the bar's own border")
local icon = Styled(ess)
local paint = host.paints[#host.paints]
Check(paint and paint.owner == icon and paint.look == ess.skin and paint.anchor == icon.tex, "the skin goes around the icon texture")
Check(paint.w == icon.w and paint.h == icon.h, "the skin takes the icon's size")
Check(not paint.clip, "a cooldown icon draws its whole skin")
Check(bridge.IconSkinShape("ROUND1") == "CIRCLE" and bridge.IconSkinShape("CUSTOM") == nil, "the shape a pick matches")
Check(icon.border == 0 and not EdgesShown(icon), "a skin draws the border: the Suite's edges hide")
local texPoint = icon.tex.points[1]
Check(texPoint.x == 0 and texPoint.y == 0, "the texture fills the icon under a skin")
-- A later row's own size (the layout's footprint, also in combat) keeps the
-- bar's skin size: the aura overlay above it is styled for the bar.
do
    local small = Icons.CreateStandalone(parent)
    Icons.StyleIcon(small, ess, 24, 24)
    local call = host.paints[#host.paints]
    Check(small.w == 24 and call.owner == small and call.w == icon.w and call.h == icon.h,
        "a later row must draw the skin at the bar's size")
    -- A relayout that only gives it another row's size (the layout, also in
    -- combat: hide ready in mixed rows) asks MSUF nothing: the skin follows
    -- the icon texture natively.
    local paints = #host.paints
    Icons.StyleIcon(small, ess, 30, 30)
    Check(small.w == 30 and #host.paints == paints, "a row size change must not repaint the skin")
end
-- Timer bars: the skin goes around the square icon only.
local barView = setmetatable({ cooldownDuration = true, barWidth = 160, barHeight = 20, styleGen = 1 }, { __index = ess })
C.Const.Decor(barView)
local bar = Styled(barView)
paint = host.paints[#host.paints]
Check(paint.owner == bar and paint.anchor == bar.tex and paint.w == bar.h and paint.h == bar.h, "a timer bar skins its square icon")
barView.barIcon, barView.styleGen = false, 2
C.Const.Decor(barView)
Icons.StyleIcon(bar, barView)
paint = host.paints[#host.paints]
Check(paint.look == nil, "a timer bar without its icon shows no skin")
-- Back to No skin: hidden once, then MSUF is never asked again.
local count = #host.paints
Icons.StyleIcon(icon, uti)
Check(#host.paints == count + 1 and host.paints[#host.paints].look == nil and EdgesShown(icon), "No skin hides the skin once")
Icons.StyleIcon(icon, uti)
Check(#host.paints == count + 1, "an icon whose skin is hidden must not call MSUF again")

-- 7. Shapes ----------------------------------------------------------------------
do
    -- No STAR here, as on the action bars: its ring only works behind the
    -- icon, and glows and the press flash draw above it.
    Check(not table.concat(NS.IconShapeIds, " "):find("STAR", 1, true) and #NS.IconShapeIds == #NS.IconShapeLabels,
        "the cooldown manager must offer no star shape")
    config.uti_iconShape = 2
    local gen = uti.styleGen
    Settings.ReadViews(config, false, false)
    Check(uti.shape == "CIRCLE" and uti.styleGen == gen + 1, "a bar's shape must reach its view and restyle it once")
    host.shapes = {}
    Styled(ess)
    Check(#host.shapes == 0, "a skinned square icon must not ask MSUF for a shape")
    local round = Styled(uti)
    local call = host.shapes[#host.shapes]
    Check(call and call.owner == round and call.shape == "CIRCLE" and call.anchor == round.tex
        and call.cooldowns[1] == round.cd and call.textures[1] == round.tex, "the icon art and its swipe take the shape")
    Check(not EdgesShown(round), "rings of the shape replace the square edges")
    local rings = 0
    for _, child in ipairs(round.children) do
        if child.layer == "BORDER" and child.shown then rings = rings + 1 end
    end
    Check(rings == math.floor(uti.border), "one ring per border pixel under the icon art")
    for _, paint in ipairs(host.paints) do
        Check(paint.owner ~= round, "a shaped icon without a skin must never call MSUF's painter")
    end
    local shapes = #host.shapes
    Icons.StyleIcon(round, uti, 20, 20)
    Check(#host.shapes == shapes, "a row size change must not reshape the icon")
    -- A timer bar takes the shape on its square icon; without its icon it has
    -- nothing to shape and keeps its square border, with no ring left behind.
    local rowView = setmetatable({ cooldownDuration = true, barWidth = 160, barHeight = 20, styleGen = 1 }, { __index = uti })
    C.Const.Decor(rowView)
    local row = Styled(rowView)
    Check(row.shape == "CIRCLE" and not EdgesShown(row), "a timer bar's icon takes the shape")
    rowView.barIcon, rowView.styleGen = false, 2
    C.Const.Decor(rowView)
    Icons.StyleIcon(row, rowView)
    Check(not row.shape and EdgesShown(row) and host.shapes[#host.shapes].shape == "RECTANGLE",
        "a timer bar without its icon keeps its square border")
    for _, ring in ipairs(row.rings or {}) do Check(not ring.shown, "a ring stayed around a hidden timer bar icon") end
    -- The decoration of a shaped icon makes its press flash and charge swipe
    -- first, so the shape masks them then: a first press or charge later (also
    -- in combat) makes and shapes nothing through MSUF.
    Check(round.pressPulse and round.chargeCd and round.chargeSet == false
        and call.textures[2] == round.pressPulse:GetParent() and call.cooldowns[2] == round.chargeCd,
        "a shaped icon's flash and charge swipe are made and masked by its decoration")
    local asked = #host.shapes
    Icons.ChargeCooldown(round)
    C.Effects.PreparePulse(round)
    Check(#host.shapes == asked, "a later swipe or flash asks MSUF nothing")
    -- A look change in combat (a pixel grid change: a new style generation)
    -- asks MSUF nothing then; the decoration follows at the combat end.
    inCombat = true
    uti.styleGen = uti.styleGen + 1
    local paintsBefore, shapesBefore = #host.paints, #host.shapes
    Icons.StyleIcon(round, uti)
    Check(#host.paints == paintsBefore and #host.shapes == shapesBefore, "a look change in combat must not call MSUF")
    -- A new icon in combat (a new button) and a pooled one another bar takes
    -- (decorated for the skinned bar before) take their bar's look at once.
    local newcomer = Styled(uti)
    local call = host.shapes[#host.shapes]
    Check(newcomer.shape == "CIRCLE" and call and call.owner == newcomer and #host.shapes == shapesBefore + 1,
        "an icon made in combat must take its bar's shape at once")
    local moved = Styled(ess)
    local paints = #host.paints
    Icons.StyleIcon(moved, uti)
    Check(moved.shape == "CIRCLE" and not moved.skinned and #host.paints == paints + 1 and host.paints[#host.paints].owner == moved
        and host.paints[#host.paints].look == nil, "a pooled icon another bar takes in combat must take that bar's look at once")
    -- An icon its own bar took back (a free pooled icon, not restyled while
    -- the bar's look changed out of combat: a new settings read) takes the
    -- bar's current look at once, also in combat.
    inCombat = false
    local pooled = Styled(uti)
    config.uti_iconShape = 4
    Settings.ReadViews(config, false, false)
    inCombat = true
    local wanted = uti.shape
    Icons.StyleIcon(pooled, uti)
    Check(wanted ~= "CIRCLE" and pooled.shape == wanted and host.shapes[#host.shapes].owner == pooled,
        "an icon its bar takes back in combat must take the bar's current look at once")
    config.uti_iconShape = 2
    inCombat = false
    Settings.ReadViews(config, false, false)
    Icons.StyleIcon(round, uti)
    inCombat = true
    uti.styleGen = uti.styleGen + 1
    Icons.StyleIcon(round, uti)
    shapesBefore = #host.shapes
    inCombat = false
    Icons.CombatEnded()
    Check(#host.shapes == shapesBefore + 1 and host.shapes[#host.shapes].owner == round, "the decoration follows at the combat end")
    -- An icon its bar takes back in combat after a settings change that keeps
    -- the decoration (here: the border color) takes the new look at once.
    inCombat = false
    local stale = Styled(uti)
    config.uti_borderColor = "ff0000"
    Settings.ReadViews(config, false, false)
    inCombat = true
    local staleShapes = #host.shapes
    Icons.StyleIcon(stale, uti)
    Check(#host.shapes == staleShapes + 1 and host.shapes[#host.shapes].owner == stale,
        "an icon taken back in combat after a border change must take the new look at once")
    inCombat = false
    Icons.StyleIcon(round, uti) -- the style pass after that settings change
    -- A settings read that changes something else (here: nothing) keeps the
    -- bar's decoration, so a later scale change in combat still waits for
    -- the combat end and asks MSUF nothing.
    local decor = uti.decor
    Settings.ReadViews(config, false, false)
    Check(uti.decor == decor, "a settings read that keeps the look must keep the bar's decoration")
    inCombat = true
    uti.styleGen = uti.styleGen + 1
    shapesBefore = #host.shapes
    Icons.StyleIcon(round, uti)
    Check(#host.shapes == shapesBefore, "a scale change in combat after an unrelated settings read must not call MSUF")
    inCombat = false
    Icons.CombatEnded()
    -- Back to square, by a settings change in combat: like any settings
    -- change then, it takes the decoration off at once (the bar's decoration
    -- went: decorRef), once; then MSUF is not asked.
    config.uti_iconShape = 1
    inCombat = true
    Settings.ReadViews(config, false, false)
    local before = #host.shapes
    Icons.StyleIcon(round, uti)
    Check(#host.shapes == before + 1 and host.shapes[#host.shapes].shape == "RECTANGLE" and EdgesShown(round),
        "square again, also in combat")
    inCombat = false
    Icons.StyleIcon(round, uti)
    Check(#host.shapes == before + 1, "a square icon must not ask MSUF again")
    -- A host without shapes (an icon skin interface without ApplyShape).
    local plainHost = RecordingHost()
    plainHost.ApplyShape, plainHost.ShapeArt = nil, nil
    local saved = NS.HostBridge
    local noShapes = Bridge({ version = 1, GetIconSkins = function() return plainHost end })
    config.uti_iconShape = 2
    Settings.ReadViews(config, false, false)
    Check(uti.shape == "RECTANGLE", "without MSUF's shapes a bar stays square")
    Check(EdgesShown(Styled(uti)), "and keeps its edges")
    config.uti_iconShape = 1
    NS.HostBridge = saved
    Check(noShapes ~= saved, "a separate bridge")
    Settings.ReadViews(config, false, false)
end

-- 5. Combat parity ---------------------------------------------------------------
inCombat = true
local early = Styled(ess)
local made = Styled(ess)
Check(host.paints[#host.paints].look == ess.skin and host.paints[#host.paints - 1].look == ess.skin,
    "icons made in combat must get the look of the icons beside them")
Check(early ~= made, "two icons")
inCombat = false

-- 6. The real host ---------------------------------------------------------------
if hostRoot then
    local api, A3, shared = RealHost()
    Check(api and api.version == 1 and api.GetIconSkins, "MSUF 7.0 must hand out GetIconSkins")
    applied = {}
    local real = Bridge(api)
    real.WatchIconSkins("cooldownManager", true)
    local realLook = real.IconSkinLook("DEFAULT")
    Check(realLook and realLook.signature, "the real default must compile")
    -- Every square skin of the catalog paints around the anchor on a frame
    -- that refuses field writes, and round skins never reach square icons.
    local Guarded = { __index = Widget, __newindex = function(_, key) error("field written on a painted frame: " .. key, 2) end }
    local skins = api.GetIconSkins()
    for _, item in ipairs(A3.IconSkins.List()) do
        local id = item.value
        local square = real.IconSkinLook(id)
        local shape = A3.IconSkins.ShapeOf(id)
        if id ~= "CUSTOM" then
            Check((square ~= nil) == (shape == "RECTANGLE"), id .. ": only square skins reach square icons")
        end
        if square then
            local owner = setmetatable({ kind = "Frame", calls = {}, children = {}, shown = true, level = 1 }, Guarded)
            local anchor = New("Texture", owner)
            Check(skins.Paint(owner, square, 40, 36, anchor) == true, id .. ": the skin must draw")
            for _, child in ipairs(rawget(owner, "children")) do
                for _, p in ipairs(child.points or {}) do
                    Check(p.rel ~= owner, id .. ": a layer is laid out around the frame instead of the icon")
                end
            end
        end
    end
    -- A real CDM icon: the layers are textures of the icon on ARTWORK 5-7 and
    -- the gloss on OVERLAY -1, under the swipe and text frames.
    C.views.ess = ess
    Settings.ReadViews(config, true, false)
    local realIcon = Styled(C.views.ess)
    local layers = 0
    for _, child in ipairs(realIcon.children) do
        if child.kind == "Texture" and ((child.layer == "ARTWORK" and (child.sublevel or 0) >= 5)
            or (child.layer == "OVERLAY" and child.sublevel == -1)) then
            layers = layers + 1
            for _, p in ipairs(child.points or {}) do
                Check(p.rel ~= realIcon, "a skin layer is laid out around the icon frame instead of its texture")
            end
        end
    end
    Check(layers > 0, "the real painter drew no layer on the icon")
    local function SkinWrites()
        local n = 0
        for _, child in ipairs(realIcon.children) do
            if (child.layer == "ARTWORK" and (child.sublevel or 0) >= 5) or (child.layer == "OVERLAY" and child.sublevel == -1) then
                for _, calls in pairs(child.calls) do n = n + calls end
            end
        end
        return n
    end
    local skinBefore = SkinWrites()
    Icons.StyleIcon(realIcon, C.views.ess)
    Check(SkinWrites() == skinBefore, "an unchanged restyle must not write to the skin")
    -- MSUF's real Outset for the footprint: the engine's reach of the skin.
    local fx, fy = real.IconSkinOutset(C.views.ess.skin, 36, 36)
    local ex, ey = A3.IconSkins.Outset(C.views.ess.skin.skin, 36, 36)
    Check(fx == ex and fy == ey, "the footprint uses MSUF's own outset")
    -- MSUF's real shapes: one mask over the icon art and the swipe's regions,
    -- the countdown text (a FontString, no AddMaskTexture) left alone.
    config.ess_iconShape = 2
    Settings.ReadViews(config, false, false)
    local round = Icons.CreateStandalone(parent)
    round.cd:GetCountdownFontString() -- the client makes it with the cooldown
    Icons.StyleIcon(round, C.views.ess)
    local roundMask = maskOf[round.tex]
    Check(round.shape == "CIRCLE" and roundMask and roundMask.kind == "MaskTexture" and round.cd.calls.SetSwipeTexture,
        "the real shape masks the icon and its swipe")
    Check(round.cd.countdown and round.cd.countdown.AddMaskTexture == nil and maskOf[round.cd.countdown] == nil,
        "the countdown text takes no mask")
    config.ess_iconShape = 1
    Settings.ReadViews(config, false, false)
    Icons.StyleIcon(round, C.views.ess)
    Check(round.shape == nil and maskOf[round.tex] == nil, "square again takes the real mask off")
    -- A default edited in combat stays frozen for the fight (the engine's
    -- snapshot), also for a Suite that compiles for the first time then (a
    -- reload in combat); MSUF reports it at combat end, out of combat.
    inCombat = true
    A3.IconSkins.WriteDefault("styleSkin", "DARK2")
    local fresh = Bridge(api)
    fresh.WatchIconSkins("cooldownManager", true)
    applied = {}
    Check(fresh.IconSkinLook("DEFAULT").signature == realLook.signature, "combat: a first compile keeps the applied look")
    Check(#applied == 0, "combat: no report")
    inCombat = false
    realBus.PLAYER_REGEN_ENABLED("PLAYER_REGEN_ENABLED")
    Check(#applied == 1 and applied[1] == "cooldownManager", "combat end: one report refreshes the module")
    Check(fresh.IconSkinLook("DEFAULT").signature:find("DARK2", 1, true), "combat end: the new default compiles")
    Check(shared.iconSkinDefault.styleSkin == "DARK2", "the page wrote the live default")
end

print("suite icon skins contract passed" .. (hostRoot and " (MSUF 7.0 host)" or " (recording host)"))
