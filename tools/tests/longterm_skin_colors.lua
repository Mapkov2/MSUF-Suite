-- Actual Skin profile/theme setters and Suite/host contextual owner callbacks.
local root, variant = assert(arg[1]), assert(arg[3] or arg[2])
root = root:gsub('\\', '/')
local schema, scenario = variant:match('^(%w+)_(.+)$')
local function Profile(value) return {theme={look='custom',preset='custom',colors={text={value,.2,.3,1}}}} end
local a,b = Profile(.1),Profile(.7)
local changes, captured, owners = 0
local S = {}
local Suite = {Suite=S, SuiteCatalog={}, SuiteOrder={}, DB={},
    HostBridge={Menu2=function() return {} end},
    Database={IsProfileName=function(name) return type(name)=='string' and name~='' end}}
MSUF_NS={Client={Flavor='Mainline',IsForever=false}}
securecallfunction=function(fn,...) return fn(...) end
InCombatLockdown=function() return false end
assert(loadfile(root..'/MSUF_Suite/Core/Platform.lua'))('MSUF_Suite',Suite)
Suite.InCombat=function() return false end
MSUFSuite=Suite
local skin={addonName='MSUF_Suite_Skin',DB=a,RootDB={activeProfile='A',profiles={A=a,B=b}},Database={},
    Client={isForever=false},IsCombatLocked=function() return false end,
    Defaults=Profile(.4),MicroColorSources={},LookPresets={},AppearanceRanges={},
    ColorOrder={{'text','Text'}},SourceText=function(v) return v end,
    Registry={QueueRefresh=function() changes=changes+1 end,RefreshAll=function() end,NotifyListeners=function() end},
    Typography={Restore=function() end,ApplyConfigured=function() end},Adapters={ApplyAll=function() end},
    Safety={Dispatch=function(fn,...) return fn(...) end}}
MapkoSkin=skin
assert(loadfile(root..'/MSUF_Suite_Skin/Core/Theme.lua'))('MSUF_Suite_Skin',skin)
assert(loadfile(root..'/MSUF_Suite_Skin/Core/DatabaseProfiles.lua'))('MSUF_Suite_Skin',skin)
local W={_Shared={},OpenColorContextPicker=function(_,values) owners=values end}
local M={Widgets=W,Theme={},TranslateText=function(v) return v end}
MSUF2=M
local P={}
assert(loadfile(root..'/MSUF_Suite_Options/Menu/Bridge.lua'))('MSUF_Suite_Options',P)
P.HM={ReleaseColorShortcut=function() end,GetSectionWidth=function() return 520 end}
P.Meta=function() return {} end
P.RegisterSummary=function() end
P.SummaryPriority=function() end
P.Refresh=function() end
P.WithHistory=function(_,_,fn) return fn() end
assert(loadfile(root..'/MSUF_Suite_Options/Menu/Controls.lua'))('MSUF_Suite_Options',P)
assert(loadfile(root..'/MSUF_Suite_Options/Pages/AppearanceKit.lua'))('MSUF_Suite_Options',P)
local host=root:gsub('/MSUF%-Suite$','/MidnightSimpleUnitFrames')
assert(loadfile(host..'/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets_ContextColors.lua'))(
    'MidnightSimpleUnitFrames',{MSUF2=M})
W.AttachContextColorShortcut=function(_,opts) captured=opts;return {} end
local open
if schema=='inline' or schema=='shortcut' then
    local rows,sectionSpec,widgets
    P.LazySection=function(_,_,_,_,spec) sectionSpec=spec end
    W.SettingsRows=function(_,_,spec)
        rows,widgets=spec.rows,{}
        for _,row in ipairs(rows) do
            local scripts={OnClick=function() W.OpenContextColors({}, {}, {row}) end}
            widgets[row.id]={SetScript=function(_,key,fn) scripts[key]=fn end,
                GetScript=function(_,key) return scripts[key] end}
        end
        return {bottomY=-60,controls=widgets}
    end
    assert(loadfile(root..'/MSUF_Suite_Options/Menu/Colors.lua'))('MSUF_Suite_Options',P)
    P.BuildSkinColors({}, {width=520})
    assert(sectionSpec.content({}))
    assert(rows and rows[1], 'actual Skin Colors rows missing')
    if schema=='shortcut' then
        open=function()
            if captured then assert(W.OpenContextColors({},captured))
            else assert(W.OpenContextColors({}, {}, rows)) end
        end
    else
        open=function() widgets[rows[1].id]:GetScript('OnClick')(widgets[rows[1].id]) end
    end
else
    P.AttachSkinColors({},'Appearance',{P.SkinPageKit.SkinColorRow(skin,'text','Text')})
    open=function() assert(W.OpenContextColors({},captured)) end
end
local coreProfile=Suite.DB
open()
assert(owners and owners[1] and owners[1]._msuf2OnColorChanged, 'real host owner missing')
local old=owners[1]
if scenario~='original' then
    assert(skin.Database.SetActiveProfile('B'))
    if scenario=='profile_aba' then assert(skin.Database.SetActiveProfile('A')) end
end
assert(Suite.DB==coreProfile, 'Skin switch changed the core profile identity')
old._msuf2OnColorChanged(1,0,0,1)
if scenario=='original' then
    assert(changes==1 and a.theme.colors.text[1]==1 and b.theme.colors.text[1]==.7, 'original skin color stopped working')
else
    assert(changes==0 and b.theme.colors.text[1]==.7, 'old Suite picker wrote a different Skin profile session')
    if scenario=='reopen' then
        open()
        owners[1]._msuf2OnColorChanged(1,0,0,1)
        assert(changes==1 and a.theme.colors.text[1]==.1 and b.theme.colors.text[1]==1, 'fresh Skin B target failed after reopening')
    end
end
print('Skin color ' .. variant .. ': PASS')
