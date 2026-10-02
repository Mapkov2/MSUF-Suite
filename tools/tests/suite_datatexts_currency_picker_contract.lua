local root=assert(arg[1])
local config={crestCurrencyIDs='10',crestMode=1}
-- Two distinct tables, as in the client (Bridge.lua): P.Suite is the namespace
-- (_G.MSUFSuite, with Finite and Public), P.S is Suite.Suite, where the
-- DataTexts addon exports its sources. One shared table would hide a lookup
-- in the wrong one.
local NS={Finite=function(v) return type(v)=='number' and v==v end,Public=function(v) return v~='secret' end}
local S={}
NS.Suite=S
local page
local P={Suite=NS,S=S,Tr=function(v) return v end,RegisterPage=function(v) page=v end,
    Get=function(_,key) return config[key] end,SetMany=function(_,values) for key,value in pairs(values) do config[key]=value end end}
assert(loadfile(root..'/MSUF_Suite_Options/Pages/DataTexts.lua'))('Options',P)
local picker
for i=1,50 do local name,value=debug.getupvalue(page.build,i);if not name then break end;if name=='CrestCurrencyMenu' then picker=value end end
assert(picker,'real options picker closure must be reachable')
local expanded=false
C_CurrencyInfo={GetCurrencyInfo=function(id) return {name='Selected '..id,iconFileID=44} end,
 GetCurrencyListSize=function() return expanded and 3 or 1 end,
 GetCurrencyListInfo=function(index) if index==1 then return {name='Native season',isHeader=true,isHeaderExpanded=expanded} end
 return {name=index==2 and 'Crest tier' or 'secret',isHeader=false,iconFileID=45} end,
 GetCurrencyListLink=function(index) return 'currency:'..(index==2 and 20 or 30) end,
 GetCurrencyIDFromLink=function(link) return tonumber(link:match('%d+')) end,
 ExpandCurrencyList=function(index,state) assert(index==1);expanded=state end}
MenuResponse={Open=1}
local buttons,checks={},{}
local scans=0
MenuUtil={CreateContextMenu=function(_,build)
 scans=scans+1;buttons={};checks={}
 local menu={SetScrollMode=function() end,CreateTitle=function() end,CreateDivider=function() end}
 function menu:CreateButton(label,callback) buttons[label]=callback;return {SetResponse=function() end} end
 function menu:CreateCheckbox(label,selected,callback) checks[label]={selected=selected,callback=callback} end
 build(nil,menu)
end}
picker({})
assert(scans==1 and checks['|T44:16|t Selected 10 (10)'].selected())
buttons['Native season +']()
assert(expanded and scans==2,'native collapsed category expands only on deliberate click')
assert(checks['|T45:16|t Crest tier (20)'],'native discovered currency has named icon choice')
for label in pairs(checks) do assert(not label:find('secret'),'secret name rejected') end
checks['|T45:16|t Crest tier (20)'].callback()
assert(config.crestMode==2 and config.crestCurrencyIDs=='10,20','new selections append persistent display order')
checks['|T44:16|t Selected 10 (10)'].callback()
assert(config.crestCurrencyIDs=='20','toggle removes selection')
buttons['Clear selection']()
assert(config.crestMode==2 and config.crestCurrencyIDs=='','clear keeps manual empty mode')
-- The observed seasonal stages come from the load-on-demand DataTexts addon
-- (S.DataTextExtraSources, P.S); before it loads, only the reset is offered.
local stages
for i=1,50 do local name,value=debug.getupvalue(page.build,i);if not name then break end;if name=='SeasonStagesMenu' then stages=value end end
assert(stages,'season stage menu closure must be reachable')
S.DataTextExtraSources=nil
stages({})
assert(buttons['Show all observed stages'] and next(checks)==nil,'without DataTexts only the reset is offered')
S.DataTextExtraSources={CrestChoices=function() return {{order=1,currencyID=10},{order=2,itemID=99}} end}
C_Item={GetItemInfo=function(id) return id==99 and 'Upgrade item' or nil end}
config.crestCurrencies='2'
stages({})
assert(checks['1: Selected 10'] and checks['2: Upgrade item'] and checks['2: Upgrade item'].selected()
 and not checks['1: Selected 10'].selected(),'observed stages listed with their selection')
checks['1: Selected 10'].callback()
assert(config.crestMode==1 and config.crestCurrencies=='2,1','a stage selection appends in display order')
buttons['Show all observed stages']()
assert(config.crestMode==1 and config.crestCurrencies=='','the reset shows all observed stages')
print('native crest currency picker PASS')
