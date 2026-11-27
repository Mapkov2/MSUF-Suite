local function LoadNameplatePage(P, root, opened)
    P.Help = function() return "" end
    P.NameplatesAdvancedAuras = { Append = function(sections)
        sections[#sections + 1] = { key = "auraWorkspace", keys = { "enemyNpcDebuffs", "enemyNpcBuffs", "enemyNpcControl" } }
    end }
    P.RegisterPage = function() end
    P.Combat = function() return false end
    P.Suite.NameplateStyle.Roles, P.Suite.NameplateStyle.Elements, P.Suite.NameplateStyle.Status = {}, {}, {}
    P.Suite.AnchorPoints, P.Suite.AnchorLabels = {}, {}
    assert(loadfile(root .. "../../MSUF_Suite/Core/NameplateExtensions.lua"))("MSUF_Suite", P.Suite)
    P.NameplatesProfiles = { Basics = function() end }
    P.Gates = {}
    local rules = {}
    for _, key in ipairs({ "enemyNpcDebuffs", "enemyNpcBuffs", "enemyNpcControl",
        "softTargetEnemy", "friendlyCastTimeEnabled" }) do
        rules[key] = { key = key }
    end
    P.catalog = { nameplates = { rules = rules, controls = {}, controlAvailable = function() return true end } }
    P.Suite.HostBridge = { RegisterSearchTargetResolver = function() end, OpenExactMenuSetting = function(_, page, section, key)
        assert(page == "suite_nameplates" and section)
        return opened(key, section)
    end }
    for _, file in ipairs({ "NameplateBarTextures", "NameplatesWorkspace", "NameplatesExtensions", "NameplatesStatus", "NameplatesSectionsLayout", "Nameplates", "NameplateFonts" }) do
        assert(loadfile(root .. file .. ".lua"))("MSUF_Suite_Options", P)
    end
end

BH3("S04-A2",function()
-- Loads the shipped options editor and right-clicks preview handles to check
-- which accordion or exact setting they open.
local ROOT = arg[1] .. "/MSUF_Suite_Options/Pages/"
local focused, opened = {}, {}
local function noop() end
local P = {}
P.Tr = function(s) return s end
P.M = {
  RegisterControlMetadata = noop,
  OpenExactSettingControl = function(key, label, page) opened[#opened+1] = key; return true end,
}
P.W = { FocusCollapsibleSection = function(target) focused[#focused+1] = target end }
P.T = {}
P.HM = {}
P.Combat = function() return false end
P.Get = function() return nil end
P.Meta = function() return {} end
P.SetTranslatedText = noop
-- The preview kit, from the shipped file, on the namespace it needs.
local core = { IsSecret = function() return false end, Number = function(v) return type(v) == "number" end,
  InCombat = function() return false end }
assert(loadfile(arg[1] .. "/MSUF_Suite/Core/PreviewKit.lua"))("MSUF_Suite", core)
-- The editor asks the shipped aura display model which handles are aura
-- containers, so the model is loaded on a namespace of its own.
local auras = { Public = function() return true end, Client = { isForever = false } }
assert(loadfile(arg[1] .. "/MSUF_Suite/Core/NameplateAuraDisplay.lua"))("MSUF_Suite", auras)
P.Suite = { Client = { isForever = false }, Public = function() return true end,
  NameplateStyle = { NativeBit = function() return false end,
  CreateBorder = function() return {} end, PaintBorder = noop }, PreviewKit = core.PreviewKit,
  NameplateAuraDisplay = auras.NameplateAuraDisplay }
P.PreviewInteraction = { Outline = noop, Handles = function(host, opts) return core.PreviewKit.Handles(host, opts) end }
P.NameplatesEditorMarkers = {}
LoadNameplatePage(P, ROOT, function(key) opened[#opened+1] = key; return true end)
assert(loadfile(ROOT .. "NameplatesEditorLayers.lua"))("MSUF_Suite_Options", P)
assert(loadfile(ROOT .. "NameplatesElements.lua"))("MSUF_Suite_Options", P)
assert(loadfile(ROOT .. "NameplatesLayoutTemplates.lua"))("MSUF_Suite_Options", P)
assert(loadfile(ROOT .. "NameplatesInspector.lua"))("MSUF_Suite_Options", P)
assert(loadfile(ROOT .. "NameplatesPreviewLayout.lua"))("MSUF_Suite_Options", P)
assert(loadfile(ROOT .. "NameplatesEditorGhosts.lua"))("MSUF_Suite_Options", P)
assert(loadfile(ROOT .. "NameplatesEditorTools.lua"))("MSUF_Suite_Options", P)
assert(loadfile(ROOT .. "NameplatesEditor.lua"))("MSUF_Suite_Options", P)
local Editor = P.NameplatesEditor

local function Handle()
  local h = { scripts = {} }
  function h:SetScript(n, f) self.scripts[n] = f end
  function h:GetScript(n) return self.scripts[n] end
  for _, m in ipairs({ "EnableMouse", "SetMovable", "RegisterForClicks", "RegisterForDrag",
      "EnableMouseWheel", "EnableKeyboard" }) do h[m] = noop end
  function h:IsShown() return true end
  function h:IsVisible() return self:IsShown() end
  return h
end
local ui = setmetatable({ sampleKind = "enemy", LayoutElements = noop,
  body = { IsShown = function() return true end, IsVisible = function() return true end,
    EnableKeyboard = noop, SetPropagateKeyboardInput = noop,
    SetScript = noop },
  sections = { enemy = "SECTION:enemy", auras = "SECTION:auras", signals = "SECTION:signals" } },
  { __index = Editor })
Editor.BuildKit(ui)

for _, case in ipairs({
  { "enemy.Auras", "enemy", "enemyNpcDebuffs" },
  { "enemy.Buffs", "auras", "enemyNpcBuffs" },
  { "enemy.ControlAura", "auras", "enemyNpcControl" },
  { "enemy.SoftTarget", "signals", "softTargetEnemy" },
}) do
  focused, opened = {}, {}
  local h = Handle()
  Editor.Bind(ui, h, case[1], case[1], case[1] .. "X", case[1] .. "Y", case[2])
  h.scripts.OnClick(h, "RightButton")
  assert(opened[1] == "msufsuite.nameplates." .. case[3],
    "S04-A2: aura handle focused the wrong exact setting " .. tostring(opened[1]))
end

end)
BH3("S04-A3",function()
-- Real NameplatesEditorLayers.lua: the "Cast time" layer with the
-- friendly sample selected, while the friendly cast time is switched off.
local ROOT = arg[1] .. "/MSUF_Suite_Options/Pages/"
local focused, opened = {}, {}
local function noop() end
local DB = { look = 4, enemyCastTimeEnabled = true, friendlyCastTimeEnabled = false }
local P = {}
P.Tr = function(s) return s end
P.M = { RegisterControlMetadata = noop,
  OpenExactSettingControl = function(key) opened[#opened+1] = key; return true end }
P.W = { FocusCollapsibleSection = function(t) focused[#focused+1] = t end }
P.T, P.HM = {}, {}
P.Get = function(_, k) return DB[k] end
P.Meta = function() return {} end
P.Suite = { Client = { isForever = false }, NameplateStyle = { NativeBit = function() return false end } }
P.NameplatesEditorMarkers = {}
local reachedSection, canOpen = nil, true
LoadNameplatePage(P, ROOT, function(key, section)
  reachedSection = section
  opened[#opened+1] = key
  return canOpen
end)
assert(loadfile(ROOT .. "NameplatesEditorLayers.lua"))("MSUF_Suite_Options", P)
local L = P.NameplatesEditorLayers
local ui = { sampleKind = "friendly", layers = {},
  sections = { castbar = "SECTION:castbar", friendlyCast = "SECTION:friendlyCast" } }
function ui:LayerOn(k) return L.On(self, k) end
function ui:LayerAvailable(k) return L.Available(self, k) end
L.Focus(ui, "castbar", "castTime")
assert(reachedSection == "suite_nameplates_friendlyCast" and opened[1] == "msufsuite.nameplates.friendlyCastTimeEnabled"
    and not focused[1], "S04-A3: friendly cast-time layer opened enemy controls")
canOpen = false
L.Focus(ui, "castbar", "castTime")
assert(focused[1] == "SECTION:friendlyCast", "S04-A3: exact-open failure lost its local section fallback")

end)
