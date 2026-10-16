-- Retained preview drag: real Bridge profile epoch, the real editor and the real preview kit.
local root, scenario = assert(arg[1]), arg[3] or arg[2] or 'profile'
local a = { headerOffsetX = 10, headerOffsetY = 20 }
local b = { headerOffsetX = 70, headerOffsetY = 80 }
local current, writes, cursorX, cursorY, combat, visible = a, 0, 100, 100, false, true
local rules = {
    headerOffsetX = { min = -1000, max = 1000 },
    headerOffsetY = { min = -1000, max = 1000 },
}
MSUF_NS = { Client = { Flavor = 'Mainline', IsForever = false } }
securecallfunction = function(fn, ...) return fn(...) end
InCombatLockdown = function() return combat end
IsShiftKeyDown, IsControlKeyDown = function() return false end, function() return false end
local S = { Config = function() return current end, OwnedElementLevel = function() return nil end }
local Suite = { Suite = S, DB = a, SuiteCatalog = { damageMeter = { rules = rules } }, SuiteOrder = {},
    HostBridge = { Menu2 = function() return {} end } }
assert(loadfile(root .. '/MSUF_Suite/Core/Platform.lua'))('MSUF_Suite', Suite)
Suite.InCombat = function() return combat end
assert(loadfile(root .. '/MSUF_Suite/Core/PreviewKit.lua'))('MSUF_Suite', Suite)
MSUFSuite, MSUF2 = Suite, { Widgets = {}, Theme = {} }
local P = {}
assert(loadfile(root .. '/MSUF_Suite_Options/Menu/Bridge.lua'))('MSUF_Suite_Options', P)
P.Get = function(_, key) return current[key] end
P.SetMany = function(_, values)
    writes = writes + 1
    for key, value in pairs(values) do current[key] = value end
    return true
end
P.HM.SkipHistoryCheckpoint = function() end
P.MeterPreviewProperties = { Build = function() end, Refresh = function() end }
P.PreviewInteraction = { Outline = function() end, Handles = function(host, opts) return Suite.PreviewKit.Handles(host, opts) end }
GetCursorPosition = function() return cursorX, cursorY end
assert(loadfile(root .. '/MSUF_Suite_Options/Pages/DamageMeterPreviewEditor.lua'))('MSUF_Suite_Options', P)
local E = P.MeterPreviewEditor
-- Selection only paints unrelated chrome. Build, Handle, Refresh and the kit's drag stay real,
-- with the actual Bridge/Registry owner guard.
E.Select = function() end
local function Frame()
    local frame = { scripts = {}, points = 0 }
    function frame:IsVisible() return visible end
    function frame:IsShown() return visible end
    function frame:GetFrameLevel() return 1 end
    function frame:GetEffectiveScale() return 1 end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:StartMoving() self.moving = true end
    function frame:StopMovingOrSizing() self.moving = false end
    return setmetatable(frame, { __index = function(_, key)
        if key:match('^Set') or key:match('^Enable') or key:match('^Register') or key:match('^Clear')
            or key:match('^Unregister') then return function() end end
    end })
end
local viewport, handle = Frame(), Frame()
local preview = { selected = function() return 1 end, viewport = viewport, stage = Frame() }
E.Build(preview)
E.Handle(preview, handle, Frame(), 'headerOffset', 'Header', 'header', 'section', 'headerHeight')
handle.scripts.OnMouseDown(handle, 'LeftButton')
assert(preview.kit.drag and handle.moving, 'drag did not start')
if scenario == 'profile' or scenario == 'profile_aba' then
    current, Suite.DB = b, b
    Suite.Registry.NotifyListeners('profile')
    if scenario == 'profile_aba' then current, Suite.DB = a, a; Suite.Registry.NotifyListeners('profile') end
elseif scenario == 'configswap' then
    current = b -- Replaced module configuration within the same profile.
elseif scenario == 'combat' then
    combat = true
elseif scenario == 'hidden' then
    visible = false
end
E.Refresh(preview)
cursorX, cursorY = 105, 103
handle.scripts.OnMouseUp(handle, 'LeftButton')
if scenario == 'original' then
    assert(writes == 1 and a.headerOffsetX == 15 and a.headerOffsetY == 23, 'original drag stopped working')
else
    assert(writes == 0 and b.headerOffsetX == 70 and b.headerOffsetY == 80,
        'old drag offsets were written into a different profile/configuration session')
end
print('Meter preview drag ' .. scenario .. ': PASS')
