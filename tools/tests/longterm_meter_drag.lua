-- Retained preview drag: real Bridge profile epoch and real editor callbacks.
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
local S = { Config = function() return current end }
local Suite = { Suite = S, DB = a, SuiteCatalog = { damageMeter = { rules = rules } }, SuiteOrder = {},
    HostBridge = { Menu2 = function() return {} end } }
assert(loadfile(root .. '/MSUF_Suite/Core/Platform.lua'))('MSUF_Suite', Suite)
Suite.InCombat = function() return combat end
MSUFSuite, MSUF2 = Suite, { Widgets = {}, Theme = {} }
local P = {}
assert(loadfile(root .. '/MSUF_Suite_Options/Menu/Bridge.lua'))('MSUF_Suite_Options', P)
P.Get = function(_, key) return current[key] end
P.SetMany = function(_, values)
    writes = writes + 1
    for key, value in pairs(values) do current[key] = value end
    return true
end
P.MeterPreviewProperties = {}
GetCursorPosition = function() return cursorX, cursorY end
assert(loadfile(root .. '/MSUF_Suite_Options/Pages/DamageMeterPreviewEditor.lua'))('MSUF_Suite_Options', P)
local E = P.MeterPreviewEditor
-- Selection only paints unrelated chrome. Start/Stop/Read/Write/Cancel/Refresh
-- remain the actual functions, with the actual Bridge/Registry owner guard.
E.Select = function() end
local funcs = {}
for i = 1, 60 do
    local name, value = debug.getupvalue(E.Handle, i)
    if not name then break end
    funcs[name] = value
end
local owner = { IsVisible = function() return visible end }
local preview = { selected = function() return 1 end, viewport = owner,
    stage = { GetEffectiveScale = function() return 1 end }, handles = {} }
local handle = { canMove = true, meterPreview = preview, offsetPrefix = 'headerOffset',
    IsVisible = owner.IsVisible, StartMoving = function() end,
    StopMovingOrSizing = function() end, ClearAllPoints = function() end,
    SetAllPoints = function() end, previewRegion = {} }
preview.handles[1] = handle
assert(funcs.Start and funcs.Stop, 'actual drag callbacks not found')
funcs.Start(handle, 'LeftButton')
assert(handle.drag, 'drag did not start')
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
funcs.Stop(handle, 'LeftButton')
if scenario == 'original' then
    assert(writes == 1 and a.headerOffsetX == 15 and a.headerOffsetY == 23, 'original drag stopped working')
else
    assert(writes == 0 and b.headerOffsetX == 70 and b.headerOffsetY == 80,
        'old drag offsets were written into a different profile/configuration session')
end
print('Meter preview drag ' .. scenario .. ': PASS')
