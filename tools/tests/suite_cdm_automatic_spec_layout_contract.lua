local root = assert(arg[1], "repository root required")
-- Real controller/event/persistence lifecycle: no menu refresh after a spec
-- switch, and no opt-in before arranging either specialization.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
assert(loadfile(root.."/MSUF_Suite/Core/ProfileVariants.lua"))("MSUF_Suite",Suite)
local config=S.Config(ID)
assert(config.specPositions==true,"spec layouts must save automatically without opting in")

-- The previous installed attempt stored false plus an empty layout in every
-- existing profile. Changing the catalog default alone cannot repair that.
do
    local old={suite={schema=1,revision=S.MigrationRevision-1,modules={cooldownManager={
        specPositions=false,positionsData="",ess_x=123,ess_y=-456,defaultsVersion=3,captured=true}}}}
    S.Normalize(old)
    local migrated=old.suite.modules.cooldownManager
    assert(migrated.specPositions==true,"the installed false/empty profile must start saving automatically")
    assert(migrated.ess_x==123 and migrated.ess_y==-456 and migrated.positionsData=="",
        "enabling automatic saving must keep the existing arrangement")
    migrated.specPositions=false
    S.Normalize(old)
    assert(migrated.specPositions==false,"a later explicit shared-layout choice survives normalization")
    local saved=assert(Codec.EncodePositions({specs={[62]={ess={x=8,y=9}}}}))
    old.suite.revision=S.MigrationRevision-1
    migrated.positionsData=saved
    S.Normalize(old)
    assert(migrated.specPositions==false and migrated.positionsData==saved,
        "an existing saved collection with an explicit shared-layout choice stays intact")
end

module.config=config
module.context=S.NewContext(ID)
-- Apply through the actual Suite owner, as normal settings writes do.
C_AddOns={DoesAddOnExist=function() return true end,GetAddOnEnableState=function() return 2 end,
    IsAddOnLoaded=function(name) return name=="MSUF_Suite" or name=="MSUF_Suite_Modules" or name==ADDON end}
UnitGUID=function() return "Player-1-1" end
S.started=true
assert(S.Set(ID,"enabled",true))
S.Apply(ID)
local function Settle() Run();Run() end
local function Data() return Codec.DecodePositions(config.positionsData) end
local function Spec(index)
    specIndex=index
    assert(Fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED"),"spec event must be registered")
    Settle()
end
local FREE=Suite.CDM.ANCHOR.FREE
Settle()
assert(Data().spec==63,"activation must claim the current specialization automatically")
assert(S.SetMany(ID,{ess_x=100,ess_y=-50,ess_perRow=7,ess_size=40,uti_anchor=FREE,uti_x=11,uti_y=22}))
Settle()
Spec(1)
assert(Data().spec==62 and Data().specs[63].ess.x==100,"the switch itself saves the outgoing layout")
assert(config.ess_x==100 and config.uti_x==11,"a first visit inherits the current arrangement")
assert(S.SetMany(ID,{ess_x=-300,ess_y=80,ess_perRow=12,ess_size=30,ess_grow=2,
    uti_anchor=2,uti_x=0,uti_y=0,uti_vertical=true,assistIconX=-15,assistIconY=-25}))
Settle()
Spec(2)
assert(config.ess_x==100 and config.ess_y==-50 and config.ess_perRow==7 and config.ess_size==40,
    "the first spec's position, rows and size return without any menu action")
assert(config.uti_anchor==FREE and config.uti_x==11 and config.uti_y==22 and config.uti_vertical==false,
    "attachment, zero offsets and orientation must travel with the layout")
assert(C.views.ess.x==100 and C.bars.ess.frame.point[4]==100,"the runtime takes the restored arrangement")
Spec(1)
assert(config.ess_x==-300 and config.ess_y==80 and config.ess_perRow==12 and config.ess_size==30
    and config.ess_grow==2 and config.uti_anchor==2 and config.uti_x==0 and config.uti_vertical==true,
    "the second spec keeps its distinct complete arrangement")
assert(C.state.assistIconX==-15 and C.state.assistIconY==-25,"the assisted icon follows its spec")

-- Edit Mode's real mover commit goes through CommitEditPosition/SetMany.
module:RegisterMovers()
local mover=assert(elements.ess)
assert(mover.movePosition({phase="commit",state=mover.captureState(),deltaX=522,deltaY=-191}))
Settle()
Spec(2)
Spec(1)
assert(config.ess_x==222 and config.ess_y==-111,"a real Edit Mode position commit survives the round trip")

-- With the menu open, the export can observe the new spec before the next
-- catalog flush. Its early read must not lose the old arrangement.
specIndex=2
S.CooldownManagerSpec()
assert(Fire("SPELLS_CHANGED"))
Settle()
assert(config.ess_x==100 and Data().spec==63,"early menu spec reads still restore the proper layout")

-- A catalog event with a temporarily missing specialization does not claim
-- or discard any layout, and learning/talent events on the same spec do not
-- serialize or rewrite the layout collection.
local text=config.positionsData
specIndex=nil
assert(Fire("SPELLS_CHANGED"))
Settle()
assert(config.positionsData==text and config.ess_x==100,"unknown specialization keeps the current layout intact")
Spec(2)
local decode,decodes=Codec.DecodePositions,0
Codec.DecodePositions=function(...) decodes=decodes+1;return decode(...) end
for i=1,5 do assert(Fire("SPELLS_CHANGED"));Settle() end
Codec.DecodePositions=decode
assert(config.positionsData==text and decodes==0,"same-spec events neither decode nor rewrite saved layouts")

-- A new activation in another spec restores the persisted state, including
-- a codec round trip as used by SavedVariables/profile export.
config.positionsData=assert(Codec.EncodePositions(Data()))
assert(S.Set(ID,"enabled",false))
Settle()
specIndex=1
assert(S.Set(ID,"enabled",true))
Settle()
assert(config.ess_x==222 and config.ess_y==-111 and Data().spec==62,
    "a fresh activation in another specialization restores its persisted layout")
assert(S.Set(ID,"enabled",false))
Settle()
print("suite_cdm_automatic_spec_layout_contract: ok")
]=], "------------------------------------------------------------------ enable: capture")
