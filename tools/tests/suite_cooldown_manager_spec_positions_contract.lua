local root=assert(arg[1],"repository root required")
-- "Save bar layout per specialization" (Settings.SpecPositions, catalog
-- CDM.CleanPositions): the flat bar settings follow the specialization and
-- positionsData keeps the other ones. A bar's whole layout travels together:
-- x/y with its attachment, growth, rows, spacing and sizes. Runs on the
-- main cooldown manager contract's harness up to its first activation.
dofile(root.."/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua",[=[
local CDM=Suite.CDM
local FREE=CDM.ANCHOR.FREE
-- The core loads ProfileVariants.lua after Suite.lua, where this harness's
-- core boot stops.
assert(loadfile(root.."/MSUF_Suite/Core/ProfileVariants.lua"))("MSUF_Suite",Suite)
local config=S.Config(ID)
-- Exercise the explicit shared-layout option before enabling it below.
config.specPositions=false
module.config=config
module.context=S.NewContext(ID)
module.active=true
module:Enable()
-- Settings are written a frame later through SetMany; in the client its
-- S.Apply then refreshes the module.
local function Settle() Run();module:Refresh();Run() end
local function Data() return Codec.DecodePositions(config.positionsData) end
-- The spec change alone writes the layout (no settings write refreshes the
-- module then); the result is the specialization the data claims before
-- that refresh.
local function Spec(index)
    specIndex=index
    assert(Fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED"),"the module listens for specialization changes")
    Run()
    local claimed=Data().spec
    module:Refresh();Run()
    return claimed
end
local function Edit(values)
    for key,value in pairs(values) do config[key]=value end
    module:Refresh();Run()
end
local function Riding(on)
    local rides=C.Layout.RidesViewer
    C.Layout.RidesViewer=function(slot) return slot=="ess" and on end
    return function() C.Layout.RidesViewer=rides end
end
Settle()
assert(config.specPositions==false,"first-run capture must preserve an explicit shared-layout choice")
local ATTACHED=config.uti_anchor
assert(ATTACHED~=FREE,"Utility starts attached")

------------------------------------------------------------------ codec
assert(Codec.EncodePositions({})=="" and Codec.EncodePositions({specs={[62]={}}})=="","nothing to store is the empty string")
assert(Data().spec==nil and next(Data().specs)==nil,"the empty string decodes to nothing")
do
    local clean=CDM.CleanPositions({spec=62.5,specs={
        [62]={ess={x=1.5,y=0,grow=2,vertical="yes",anchor=99},uti={nope=1},assist={x=5000,y=7},
            c1={x=-3,y=4,anchor=FREE,r=true,perRow=5,centerFirst=true},nope={x=1,y=2}},
        [0]={ess={x=1,y=2}},
        -- The first format: x, y and the attach target as a.
        [63]={bar={x=1,y=2,a=2,p="TOP"},ess={x=1,y=2,r=1}}}})
    local s62,s63=clean.specs[62],clean.specs[63]
    assert(clean.v==2 and clean.spec==nil and clean.specs[0]==nil,"a broken specialization is dropped")
    assert(s62.ess.x==nil and s62.ess.y==0 and s62.ess.grow==2 and s62.ess.vertical==nil and s62.ess.anchor==nil,
        "each broken setting is dropped on its own")
    assert(s62.uti==nil and s62.nope==nil and s62.assist.x==nil and s62.assist.y==7,"unknown settings and bars are dropped")
    assert(s62.c1.r==true and s62.c1.perRow==5 and s62.c1.centerFirst==true and s62.assist.r==nil,"layout and ride mark kept")
    assert(s63.bar.anchor==2 and s63.bar.a==nil and s63.bar.p==nil and s63.ess.r==nil,"the first format reads as a layout")
    local copy=Codec.DecodePositions(assert(Codec.EncodePositions(clean)))
    assert(copy.specs[62].c1.x==-3 and copy.specs[63].bar.y==2,"layouts survive the codec")
end

------------------------------------------------------------------ shared layout
assert(C.state.specID==63 and config.specPositions==false and config.positionsData=="","explicitly off, nothing stored")
Edit({ess_x=100,ess_y=-50})
assert(Spec(1)==nil,"off: nothing is claimed")
assert(C.state.specID==62 and config.ess_x==100 and config.ess_y==-50 and config.positionsData=="",
    "off: every specialization shares one layout and nothing is written")

------------------------------------------------------------------ on
-- Switching on claims the current layout; nothing moves.
Edit({specPositions=true})
local data=Data()
assert(data.spec==62 and next(data.specs)==nil and config.ess_x==100,"switching on claims the current layout")
Edit({uti_x=6,uti_y=-4,assistIconX=40,assistIconY=-150,ess_perRow=7})
-- A specialization without a saved layout starts from the current one; the
-- outgoing specialization's layout is stored.
assert(Spec(3)==64,"the spec change itself stores the layout")
data=Data()
assert(config.ess_x==100 and config.ess_perRow==7 and config.uti_x==6 and config.assistIconX==40,
    "a specialization without a saved layout keeps the current one")
local saved=data.specs[62]
assert(saved and saved.ess.x==100 and saved.ess.y==-50 and saved.ess.anchor==FREE and saved.ess.grow==1
    and saved.ess.perRow==7 and saved.ess.r==nil,"the outgoing Essential layout")
assert(saved.uti.x==6 and saved.uti.y==-4 and saved.uti.anchor==ATTACHED,"an attached bar keeps its offset and target")
assert(saved.assist.x==40 and saved.assist.y==-150 and saved.assist.perRow==nil,"the assisted icon's place")
assert(saved.c6 and saved.c6.x==config.c6_x and saved.c6.size==config.c6_size,"bars that are off keep their layout too")
-- 64 gets another arrangement: attachments, growth, rows and size differ.
Edit({ess_x=-300,ess_y=20,ess_grow=2,ess_perRow=12,ess_size=30,uti_anchor=FREE,uti_x=200,uti_y=300,assistIconX=-10})
assert(Spec(1)==62)
assert(config.ess_x==100 and config.ess_y==-50 and config.ess_grow==1 and config.ess_perRow==7
    and config.ess_size==S.catalog[ID].rules.ess_size.default,"62's Essential layout comes back whole")
assert(config.uti_anchor==ATTACHED and config.uti_x==6 and config.uti_y==-4,"62's attachment comes back with its offset")
assert(config.assistIconX==40 and config.assistIconY==-150,"62's assisted icon place")
assert(C.views.ess.perRow==7 and C.views.uti.anchor==ATTACHED and C.state.assistIconX==40,"the views follow")
assert(C.bars.ess.frame.point[1]=="TOP" and C.bars.ess.frame.point[4]==100 and C.bars.ess.frame.point[5]==-50,
    "the Essential bar sits at 62's place with 62's growth edge")
data=Data()
assert(data.spec==62 and data.specs[62]==nil and data.specs[64].ess.x==-300 and data.specs[64].ess.grow==2
    and data.specs[64].ess.size==30 and data.specs[64].uti.anchor==FREE and data.specs[64].assist.x==-10,
    "the settings hold the current specialization, the data the other one")
assert(Spec(3)==64)
assert(config.ess_x==-300 and config.ess_grow==2 and config.ess_perRow==12 and config.ess_size==30
    and config.uti_anchor==FREE and config.uti_x==200 and config.uti_y==300 and config.assistIconX==-10,
    "64 gets its whole arrangement back")
assert(C.bars.ess.frame.point[1]=="BOTTOM" and C.bars.ess.frame.point[4]==-300,"64's Essential grows up from its place")
-- Other catalog passes of the same specialization write nothing.
do
    local text=config.positionsData
    assert(Fire("SPELLS_CHANGED"))
    Settle()
    assert(config.positionsData==text and config.ess_x==-300,"a catalog pass without a spec change keeps everything")
end
-- MSUF Edit Mode's captured states hold one specialization's layout: an undo
-- or discard across a spec change writes nothing.
do
    module:RegisterMovers()
    local element=assert(elements.ess,"the Essential mover")
    local before=element.captureState()
    assert(Spec(1)==62 and config.ess_x==100)
    assert(element.restoreState(before)==false and config.ess_x==100,"an undo across a spec change writes nothing")
    assert(element.restoreState(element.captureState())==true and config.ess_x==100,"a state of this layout restores")
    assert(Spec(3)==64 and config.ess_x==-300)
end

------------------------------------------------------------------ combat
-- In combat the bars take the layout at once and the settings follow
-- combat's end.
do
    -- The standalone assisted icon shows (as in the main contract).
    cvars.assistedCombatHighlight="1"
    Edit({assistIcon=true})
    AssistedCombatManager.lastNextCastSpellID=101
    assert(registry["AssistedCombatManager.OnAssistedHighlightSpellChange"]).fn()
    local icon=assert(C.Effects.RecommendationFrame(),"the assisted icon")
    assert(icon.shown and icon.point[4]==-10,"the assisted icon sits at 64's place")
    combat=true
    specIndex=1
    assert(Fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED"))
    Run()
    assert(config.ess_x==-300 and config.ess_perRow==12,"under lockdown the settings wait")
    assert(C.views.ess.x==100 and C.views.ess.perRow==7 and C.views.uti.anchor==ATTACHED and C.state.assistIconX==40
        and icon.point[4]==40 and icon.point[5]==-150,"under lockdown the bars and the assisted icon take 62's layout at once")
    -- A refresh while the write waits (a module re-applied at Edit Mode's
    -- close) keeps the waiting layout on screen.
    module:Refresh();Run()
    assert(config.ess_x==-300 and C.views.ess.x==100 and C.views.ess.perRow==7 and C.views.uti.anchor==ATTACHED
        and C.state.assistIconX==40 and icon.point[4]==40,"a refresh before the write keeps 62's layout")
    combat=false
    assert(Fire("PLAYER_REGEN_ENABLED"))
    Settle()
    assert(config.ess_x==100 and config.ess_perRow==7 and config.uti_anchor==ATTACHED and Data().spec==62,
        "combat's end writes the layout")
    cvars.assistedCombatHighlight="0"
    Edit({assistIcon=false})
end

------------------------------------------------------------------ MSUF profile variants
-- A bar an MSUF profile variant positions belongs to the variant layer: it
-- is neither stored nor brought back. The other bars still follow.
do
    local name=Suite.Database.GetActiveProfileName()
    MSUF_ActiveProfile=name
    MSUF_GlobalDB={profiles={[name]={profileVariants={version=1,entries={{name="Tank",
        patch={{path={"suiteModules",ID,"ess_x"},value=0}}}}}}}}
    Edit({ess_x=500,ess_perRow=4,ext_x=9})
    local before=Data().specs[64]
    assert(before.ess and before.ext,"64 has saved layouts")
    assert(Spec(3)==64)
    assert(config.ess_x==500 and config.ess_perRow==4,"a variant's bar keeps its whole layout")
    assert(config.ext_x==before.ext.x and Data().specs[62].ext.x==9 and Data().specs[62].ess==nil,
        "the other bars still follow")
    assert(Data().specs[64] and Data().specs[64].ess.x==before.ess.x and Data().specs[64].ext==nil,
        "the variant bar's saved layout waits in the data")
    -- Another profile's variants do not count.
    MSUF_ActiveProfile=name.."-other"
    Edit({ess_x=501})
    assert(Spec(1)==62 and (Data().specs[64].ess or {}).x==501,"only the active profile's variants hold settings")
    MSUF_GlobalDB,MSUF_ActiveProfile=nil,nil
end

------------------------------------------------------------------ Essential and Blizzard's bar
-- The Essential bar's ride flag comes back with its x/y: x/y saved as an
-- offset from Blizzard's bar return as one.
do
    local stored=Data()
    stored.specs[64].ess={x=55,y=66,anchor=FREE,grow=1,r=true}
    Edit({positionsData=assert(Codec.EncodePositions(stored)),essOnViewer=false})
    local restore=Riding(true)
    assert(Spec(3)==64)
    restore()
    assert(config.ess_x==55 and config.ess_y==66 and config.essOnViewer==true,"the offset comes back with its flag")
    assert(Data().specs[62].ess.r==nil,"62's screen position was stored as one")
    Edit({essOnViewer=false,ess_x=-300,ess_y=20})
end
-- While a conversion of the Essential x/y is still to be written (riding
-- Blizzard's bar starts), the swap waits for it and follows on the Refresh
-- that write brings; nothing of 62 is lost.
do
    local incoming=Data().specs[62]
    assert(incoming and incoming.ess and incoming.ess.r==nil,"62 has a saved Essential layout")
    local restore=Riding(true)
    specIndex=1
    assert(Fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED"))
    C.Settings.SyncViewerOffset()
    Run()
    assert(Data().spec==64 and config.essOnViewer==true and config.ess_x==0 and config.ess_y==0,
        "the swap waits for the pending ride conversion")
    module:Refresh();Run()
    restore()
    assert(Data().spec==62 and config.ess_x==incoming.ess.x and config.ess_y==incoming.ess.y and config.essOnViewer==false,
        "62's Essential layout comes back whole after the conversion")
    assert(config.ext_x==9 and Data().specs[64].ess.x==0 and Data().specs[64].ess.r==true,
        "the other bars follow; 64's Essential offset is stored with its flag")
    Edit({essOnViewer=false,ess_x=100,ess_y=-50})
end

------------------------------------------------------------------ off again
-- Switched off, the data forgets whose layout the settings hold and keeps
-- the others; spec changes then write nothing.
Edit({specPositions=false})
data=Data()
assert(data.spec==nil and data.specs[64] and data.specs[64].ess.x==0,"switching off keeps the saved layouts")
-- Off costs nothing per settings change (Refresh runs on every slider tick).
do
    local decode,decodes,size=Codec.DecodePositions,0,config.ess_size
    Codec.DecodePositions=function(...) decodes=decodes+1;return decode(...) end
    for _=1,5 do config.ess_size=config.ess_size+1;module:Refresh() end
    assert(Fire("SPELLS_CHANGED"))
    Run()
    Codec.DecodePositions=decode
    Edit({ess_size=size})
    assert(decodes==0,"while off neither a settings change nor a catalog pass decodes the data")
end
local text=config.positionsData
Edit({ess_x=1,ess_y=2})
assert(Spec(3)==nil)
assert(config.ess_x==1 and config.positionsData==text,"off: nothing moves and nothing is written")
-- Switching on again claims the layout as it is, even where the data has a
-- saved one for this specialization.
Edit({specPositions=true})
data=Data()
assert(data.spec==64 and data.specs[64]==nil and config.ess_x==1 and config.ess_y==2,
    "switching on again claims the current layout")
-- 62 held the settings when the switch went off, so it has no saved layout.
assert(Spec(1)==62)
assert(Data().specs[64].ess.x==1 and config.ess_x==1,"the claimed layout is 64's")

------------------------------------------------------------------ activation
-- Logging in, or enabling the module, in another specialization than the
-- data claims (a profile shared across characters, too): the first catalog
-- pass places the bars for it, without any settings write.
Edit({ess_x=777})
module.active=false;module:Disable();module.context:Release();Run(5)
specIndex=3
module.active=true;module:Enable();Run()
data=Data()
assert(data.spec==64 and data.specs[62].ess.x==777 and config.ess_x==1,"an activation in another specialization swaps")
module:Refresh();Run()
assert(C.bars.ess.frame.point[4]==1 and C.bars.ess.frame.point[5]==2,"the bar sits at 64's place")

------------------------------------------------------------------ profiles
-- The data belongs to the profile: a shared profile across characters
-- simply holds every specialization; a fresh profile starts empty.
assert(Suite.CDM.DEFAULTS_KEEP.positionsData==nil and S.catalog[ID].rules.positionsData.hidden,
    "the data is hidden and resets with the bar settings")
module.active=false;module:Disable();module.context:Release();Run(5)
print("suite_cooldown_manager_spec_positions_contract: ok")
]=],"------------------------------------------------------------------ enable: capture")
