-- Read-only audit contract. Run with Lua5.1 and the frozen Suite root.
local root=assert(arg[1]):gsub('\\','/')
arg[2]='--fixture'
local Fixture=assert(loadfile(root..'/tools/tests/suite_planning_tools_contract.lua'))()
local passed,failures=0,{}
local function Check(ok,why) assert(ok,why) end
local function Equal(actual,wanted,why) assert(actual==wanted,why..': expected '..tostring(wanted)..', got '..tostring(actual)) end
local function Case(name,run)
 local ok,err=pcall(run)
 if ok then passed=passed+1; print('PASS '..name) else failures[#failures+1]=name..': '..tostring(err); print('FAIL '..failures[#failures]) end
end
local function New()
 local st,NS,S,Plan,owner,P=Fixture()
 owner:Enable();st.Flush()
 return st,NS,S,Plan,owner,P
end
Case('logout preserves live vitals and GUID ownership; real zero and late item level remain valid',function()
 local st,NS,S,Plan,owner=New()
 local account,guid=Plan.Account(),st.guid
 local old=account.characters[guid]
 local money,ilvl=old.money,old.ilvl
 st.time=st.time+20
 st.Event('PLAYER_MONEY')
 local late=assert(st.pending)
 st.money=0;GetAverageItemLevel=function() return 0,0 end
 Check(st.Event('PLAYER_LEAVING_WORLD'),'missing world-leave listener')
 Equal(st.pending,nil,'leave must cancel queued data read')
 Equal(old.at,st.time,'leave stamps last seen')
 Equal(old.money,money,'leave must preserve money')
 Equal(old.ilvl,ilvl,'leave must preserve item level')
 local scheduled=st.scheduled
 st.Event('PLAYER_MONEY');st.Event('PLAYER_EQUIPMENT_CHANGED');st.Event('PLAYER_AVG_ITEM_LEVEL_UPDATE')
 Equal(st.scheduled,scheduled,'late events must not queue teardown reads')
 late(owner)
 Equal(old.money,money,'stale queued callback must not overwrite money')
 Equal(old.ilvl,ilvl,'stale queued callback must not overwrite item level')
 Check(not Plan.CanEdit(),'leaving disallows manual edits')
 Check(not Plan.Weekly.Capture() and not Plan.Weekly.Vitals(),'leaving disallows direct snapshot reads')
 st.Event('PLAYER_LOGOUT')
 Equal(old.money,money,'logout must preserve money')
 Equal(old.ilvl,ilvl,'logout must preserve item level')
 st.guid,st.name,st.money='player-b','Bob',99999
 GetAverageItemLevel=function() return 700,690 end
 Check(st.Event('PLAYER_ENTERING_WORLD'),'missing world-enter listener')
 st.Flush()
 Equal(account.characters[guid].money,money,'switch must preserve old GUID money')
 Equal(account.characters[guid].ilvl,ilvl,'switch must preserve old GUID item level')
 Equal(account.characters[st.guid].money,99999,'new GUID owns its own money')
 Equal(account.characters[st.guid].ilvl,690,'new GUID owns its own item level')
 st.money=0;st.Event('PLAYER_MONEY');st.Flush()
 Equal(account.characters[st.guid].money,0,'live spending to zero must be stored')
 GetAverageItemLevel=function() return 710,705.2 end
 Check(st.Event('PLAYER_AVG_ITEM_LEVEL_UPDATE'),'missing item-level readiness event')
 st.Flush();Equal(account.characters[st.guid].ilvl,705.2,'late item-level readiness refreshes value')
end)
Case('leave then combat then enter during combat resumes after combat',function()
 local st,NS,S,Plan,owner=New()
 st.Event('PLAYER_LEAVING_WORLD');st.Event('PLAYER_REGEN_DISABLED')
 Check(st.Event('PLAYER_ENTERING_WORLD'),'combat must keep entering-world listener')
 Check(not owner.leaving,'enter during combat must clear leaving')
 st.Event('PLAYER_REGEN_ENABLED');Check(st.Flush(),'combat end must resume capture')
 Check(Plan.CanEdit(),'planner remains stuck leaving after combat/world transition')
end)
Case('combat then leave then combat end waits for actual world enter',function()
 local st,NS,S,Plan,owner=New()
 st.Event('PLAYER_REGEN_DISABLED')
 Check(st.Event('PLAYER_LEAVING_WORLD'),'combat must keep leaving-world listener')
 Check(owner.leaving,'combat leave must set transition gate')
 st.Event('PLAYER_REGEN_ENABLED')
 Equal(st.pending,nil,'combat end during loading must not read teardown APIs')
 Check(not Plan.CanEdit(),'loading after combat must stay gated')
 st.Event('PLAYER_ENTERING_WORLD');Check(st.Flush(),'actual enter must restore capture')
 Check(Plan.CanEdit(),'enter failed to restore editability')
end)
Case('run minimum filter redraws actual Planner Board',function()
 arg[2],arg[3],arg[4]='--fixture','-','Mainline'
 local F=assert(loadfile(root..'/tools/tests/suite_planner_board_contract.lua'))()
 local st,Plan,owner,S=F.st,F.Plan,F.owner,F.S
 owner:Enable();st.Flush()
 S.CharacterData('runSummary').history={
  {historyID=1,level=5,recordedAt=1000,time=120,subtitle='Dungeon +5'},
  {historyID=2,level=15,recordedAt=1001,time=120,subtitle='Dungeon +15'} }
 Plan.Window.Open('runs')
 local w=Plan.Board.window
 Equal(#w.items,2,'fixture must initially show both runs')
 Plan.Window.RunActions()[3].run(owner,nil,w)
 Check(st.editor.onSave(owner,'10'),'minimum level save rejected valid input')
 Equal(#w.items,1,'minimum level save must redraw visible list immediately')
 Equal(w.items[1].run.level,15,'minimum level save kept wrong row')
end)
Case('checklist state refreshes live and rejects replaced entry',function()
 local st,NS,S,Plan=New()
 Plan.Notes.Save('100','Dungeon','[ ] First\n[x] Second',100)
 Plan.Window.tab='notes'
 local boxes={}
 S.ContextMenu=function(_,build)
  build(nil,{CreateTitle=function()end,CreateCheckbox=function(_,_,get,select) boxes[#boxes+1]={get=get,select=select} end})
 end
 Plan.Window.Menu(nil,Plan.Notes.Rows(false)[1],{})
 Equal(#boxes,2,'all checklist lines must be menu items')
 Equal(boxes[1].get(),false,'first starts unchecked');Equal(boxes[2].get(),true,'second starts checked')
 boxes[1].select();Equal(boxes[1].get(),true,'first check must repaint live')
 boxes[2].select();Equal(boxes[2].get(),false,'second uncheck must repaint live')
 boxes[1].select();Equal(boxes[1].get(),false,'second first-item click must repaint unchecked')
 Plan.Notes.Save('100','Dungeon','[x] Replacement',100)
 boxes[1].select();Equal(Plan.Notes.Rows(false)[1].detail,'[x] Replacement','stale checkbox must not edit replaced note')
 Equal(boxes[1].get(),false,'stale checkbox selected state must fail closed')
end)
Case('41 weekly runs keep exact count and true highest in bounded details',function()
 local st,NS,S,Plan=New()
 st.runs={}
 for i=1,41 do st.runs[i]={mapChallengeModeID=1,level=i==41 and 22 or 10,completed=true} end
 Plan.Weekly.seasonReady=true;Plan.Weekly.Capture()
 local entry=Plan.Account().characters[st.guid]
 Equal(entry.runCount,41,'weekly total must include valid runs past cap')
 Equal(entry.runHighest,22,'weekly highest must inspect runs past cap')
 Equal(#entry.runs,40,'weekly details must remain bounded')
 Equal(entry.runs[1].level,22,'top-details/tooltip must include true highest beyond input cap')
 assert(loadfile(root..'/MSUF_Suite_AdventurePlanner/PlanningOverview.lua'))('Audit',{NS=NS,Suite=S,PlanningTools=Plan})
 assert(loadfile(root..'/MSUF_Suite_AdventurePlanner/PlanningMatrix.lua'))('Audit',{NS=NS,Suite=S,PlanningTools=Plan})
 local rows=Plan.Weekly.Rows(false);Plan.Matrix.Build(rows,st.time)
 Equal(Plan.Matrix.Value({kind='runs'},rows[1],st.time),'41 (+22)','matrix must show full total and highest')
end)
Case('weekly rollover never relabels old runs as fresh while map data is pending',function()
 local st,NS,S,Plan=New()
 st.runs={{mapChallengeModeID=1,level=17,completed=true}}
 Plan.Weekly.seasonReady=true;Plan.Weekly.Capture()
 local old=Plan.Account().characters[st.guid]
 local dungeons,rating=old.dungeons,old.rating
 Plan.Weekly.Request();Plan.Weekly.Capture()
 local same=Plan.Account().characters[st.guid]
 Equal(same.runs,old.runs,'same-reset pending request must retain known run details')
 Equal(same.runCount,1,'same-reset pending request must retain known total')
 Equal(same.runHighest,17,'same-reset pending request must retain known highest')
 st.reset,st.time=st.reset+604800,st.time+604800
 Plan.Weekly.Request();Plan.Weekly.Capture()
 local entry=Plan.Account().characters[st.guid]
 Equal(entry.reset,st.reset,'new snapshot must use current reset')
 Equal(entry.runs,nil,'prior-reset run details must not become fresh')
 Equal(entry.runCount,nil,'prior-reset run count must not become fresh')
 Equal(entry.runHighest,nil,'prior-reset highest must not become fresh')
 Equal(entry.dungeons,dungeons,'pending weekly refresh must retain season-long dungeon data')
 Equal(entry.rating,rating,'pending weekly refresh must retain season-long rating')
 assert(loadfile(root..'/MSUF_Suite_AdventurePlanner/PlanningOverview.lua'))('Audit',{NS=NS,Suite=S,PlanningTools=Plan})
 assert(loadfile(root..'/MSUF_Suite_AdventurePlanner/PlanningMatrix.lua'))('Audit',{NS=NS,Suite=S,PlanningTools=Plan})
 local rows=Plan.Weekly.Rows(false);Plan.Matrix.Build(rows,st.time)
 Equal(Plan.Matrix.Value({kind='runs'},rows[1],st.time),'?','new week pending server data must stay unknown')
end)
print('Planner audit: '..passed..' cases passed; '..#failures..' failed')
if #failures>0 then error(table.concat(failures,'\n')) end
