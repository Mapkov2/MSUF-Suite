BH3("S04-A2",function()
-- Loads the real NameplatesEditorLayers.lua + NameplatesEditor.lua and right-clicks
-- preview handles. Prints which accordion is focused and which exact setting opens.
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
P.Suite = { Client = { isForever = false }, NameplateStyle = { NativeBit = function() return false end,
  CreateBorder = function() return {} end, PaintBorder = noop } }
P.PreviewInteraction = { Outline = noop }
P.NameplatesEditorMarkers = {}
P.NameplatesPreviewLayout = { Apply = noop }
assert(loadfile(ROOT .. "NameplatesEditorLayers.lua"))("MSUF_Suite_Options", P)
assert(loadfile(ROOT .. "NameplatesEditor.lua"))("MSUF_Suite_Options", P)
local Editor = P.NameplatesEditor

local function Handle()
  local h = { scripts = {} }
  function h:SetScript(n, f) self.scripts[n] = f end
  for _, m in ipairs({ "EnableMouse", "SetMovable", "RegisterForClicks", "RegisterForDrag",
      "EnableMouseWheel", "EnableKeyboard" }) do h[m] = noop end
  function h:IsShown() return true end
  return h
end
local ui = setmetatable({ handles = {}, sampleKind = "enemy",
  body = { IsShown = function() return true end },
  sections = { enemy = "SECTION:enemy", auras = "SECTION:auras", signals = "SECTION:signals" } },
  { __index = Editor })

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
  assert(h._npSettingKey ~= nil and opened[1] == "msufsuite.nameplates." .. case[3],
    "S04-A2: aura handle focused the wrong exact setting " .. tostring(opened[1]))
end

end)
BH3("S04-A3",function()
-- Real NameplatesEditorLayers.lua: the "Cast time" layer chip with the
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
assert(loadfile(ROOT .. "NameplatesEditorLayers.lua"))("MSUF_Suite_Options", P)
local L = P.NameplatesEditorLayers
local ui = { sampleKind = "friendly", layers = {},
  sections = { castbar = "SECTION:castbar", friendly = "SECTION:friendly" } }
function ui:LayerOn(k) return L.On(self, k) end
function ui:LayerAvailable(k) return L.Available(self, k) end
L.Focus(ui, "castbar", "castTime")
assert(focused[1] == "SECTION:friendly" and opened[1] == "msufsuite.nameplates.friendlyCastTimeEnabled",
 "S04-A3: friendly cast-time chip opened enemy controls")

end)
