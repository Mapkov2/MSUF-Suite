local root=assert(arg[1],"repository root required")
local Support=dofile(root.."/tools/tests/suite_test_support.lua")
local Suite,provider,overlay,recording,combat={},nil,false,false,false
local frame={general={}}
local core={UF={},ProfileRuntime={Apply=function() end}}
MSUF_NS=core
MSUF_GlobalDB,MSUF_DB,MSUF_ActiveProfile={profiles={Default=frame}},frame,"Default"
WOW_PROJECT_ID,WOW_PROJECT_MAINLINE=1,1
SlashCmdList={}
InCombatLockdown=function() return combat end
C_AddOns={DoesAddOnExist=function() return false end,IsAddOnLoaded=function() return false end}
Minimap={SetMaskTexture=function() end}
securecallfunction=function(fn,...) return fn(...) end
core.ProfileFields={RegisterExternal=function(rootName,value) assert(rootName=="suiteModules");provider=value end}
core.ProfileVariants={
    BaseSnapshot=function() return {suiteModules=provider.Snapshot(Suite.DB.suite.modules)} end,
    HasExternalOverlay=function() return overlay end,
    IsRecording=function() return recording end,
    IsMaterialized=function() return overlay end,
    Restore=function() overlay=false end,
    ResolveCurrent=function() return true end,
}
local registered={}
core.ProfileSync={RegisterModule=function(id,label) registered[id]=label or true end,RebaseExternal=function() end}
-- The profile sync list names Suite modules through one whole translated
-- format, so a language can place "Suite" where it belongs.
core.L={["Suite: %s"]="%s (Suite)"}
Support.Load(root,"MSUF_Suite",Suite,"Core/ProfileVariants.lua")
assert(Suite.Database.Initialize(nil))
Suite.Suite.Normalize(Suite.DB)
assert(Suite.ProfileVariants.Register())
assert(provider and registered["suite:actionbars"] and not registered["suite:nameplates"])
assert(registered["suite:actionbars"]==("%s (Suite)"):format(Suite.Text(Suite.SuiteCatalog.actionbars.title)),
    "the profile sync label is not one translated text: "..tostring(registered["suite:actionbars"]))
local config=Suite.DB.suite.modules.actionbars
config.transientCache={owner="runtime"}
local snapshot=provider.Snapshot(Suite.DB.suite.modules)
assert(snapshot.actionbars and not snapshot.actionbars.transientCache and not snapshot.nameplates,
    "only catalog rules enter the synthetic root; nameplates never enter it")
assert(not provider.Allows({"suiteModules","nameplates","enabled"}))
assert(not provider.Allows({"suiteModules","actionbars","transientCache"}))
local enabled=Suite.SuiteCatalog.actionbars.rules.enabled
assert(provider.Check({"suiteModules","actionbars","enabled"},false,false)==false,
    "false is a valid checked setting")
assert(provider.Check({"suiteModules","actionbars","enabled"},nil,true)==enabled.default,
    "deletion follows the module rule default")
local _,valid=provider.Check({"suiteModules","actionbars","enabled"},"bad",false)
assert(not valid)
local plates=Suite.DB.suite.modules.nameplates
snapshot.actionbars.enabled=not config.enabled
assert(provider.Restore(Suite.DB.suite.modules,snapshot))
assert(Suite.DB.suite.modules.nameplates==plates and config.transientCache.owner=="runtime",
    "restoration changes documented settings while preserving runtime caches and nameplates")
snapshot.actionbars.enabled="invalid"
local before=config.enabled
assert(not provider.Restore(Suite.DB.suite.modules,snapshot) and config.enabled==before,
    "invalid restoration is checked before any settings are mutated")
local calls=0
Suite.Suite.started=true
Suite.Suite.ApplyAll=function() calls=calls+1 end
provider.Apply("PROFILE_APPLY")
assert(calls==0,"ordinary profile apply without Suite variants adds no Suite pass")
overlay=true;provider.Apply("PROFILE_APPLY");assert(calls==1)
overlay=false;provider.Apply("PROFILE_APPLY");assert(calls==2,"removed Suite variants repaint the restored base once")
provider.Apply("PROFILE_APPLY");assert(calls==2)
overlay=true;provider.Apply("SUITE_PROFILE_VARIANT_ACTIVATE");assert(calls==2,"activation uses Suite's existing apply owner")
Suite.suppressProfileSync=true
assert(provider.Resolve("Pending",true)==nil)
assert(provider.Resolve("Default",false)==Suite.DB.suite.modules,
    "suppressed imports must still read the old profile while its overlay is peeled")
provider.Apply("PROFILE_APPLY");assert(calls==2)
Suite.suppressProfileSync=nil
recording=true
assert(not Suite.ProfileVariants.CanMutate() and not Suite.Database.Activate("Default"))
recording=false
local saved,snapshots=core.ProfileVariants.BaseSnapshot,0
core.ProfileVariants.BaseSnapshot=function() snapshots=snapshots+1;return nil,"forced snapshot failure" end
overlay=false
-- Without an overlay the stored profile is the base: no copy of the whole
-- MSUF frame profile is taken (only the active MSUF profile can carry one).
assert(Suite.SuiteProfiles.OnLifecycle("copy","Default","Plain") and Suite.Database.GetProfile("Plain")
    and snapshots==0,"a profile copy without an overlay took an MSUF profile snapshot")
assert(Suite.ProfileVariants.BaseSettings("Default").modules and snapshots==0,
    "history settings without an overlay took an MSUF profile snapshot")
overlay=true
assert(not Suite.SuiteProfiles.OnLifecycle("copy","Default","Rejected") and snapshots==1)
assert(not Suite.Database.GetProfile("Rejected"),"failed base snapshots must never fall back to baked overlays")
assert(Suite.ProfileVariants.BaseSettings("Default")==nil,"history fell back to baked overlay values")
MSUF_DB={}
assert(Suite.ProfileVariants.BaseProfile("Default") and snapshots==2,
    "an inactive MSUF profile cannot carry the overlay of the active one")
MSUF_DB=frame
overlay=false
core.ProfileVariants.BaseSnapshot=saved
for _,schema in ipairs({{entries=false},{entries={false}},{entries={{patch=false}}},{entries={{patch={{}}}}}}) do
    frame.profileVariants=schema
    Suite.ProfileVariants.OnActivated("Default")
end
frame.profileVariants=nil
-- Activation lifts the overlay before the stored profile is normalized, so a
-- migration rewrites the stored value and never the variant's, and the core
-- lays the overlay again afterwards.
local steps,normalize,restore,resolve={},Suite.Suite.Normalize,core.ProfileVariants.Restore,core.ProfileVariants.ResolveCurrent
local apply=core.ProfileRuntime.Apply
core.ProfileVariants.Restore=function(capture) steps[#steps+1]=capture==false and "lift" or "peel";overlay=false end
core.ProfileVariants.ResolveCurrent=function() steps[#steps+1]="resolve" end
core.ProfileRuntime.Apply=function(reason) steps[#steps+1]="apply:"..reason end
Suite.Suite.Normalize=function(profile)
    steps[#steps+1]=profile==Suite.Database.GetProfile("Default") and "normalize" or "normalize-other"
    return normalize(profile)
end
frame.profileVariants={version=1,entries={{name="Healer",patch={{path={"suiteModules","objectives","width"},value=420}}}}}
Suite.ProfileVariants.OnActivated("Default")
assert(table.concat(steps,",")=="peel,normalize,apply:SUITE_PROFILE_VARIANT_ACTIVATE",
    "activation normalized the overlaid values instead of the stored ones: "..table.concat(steps,","))
frame.profileVariants=nil
-- Undo lifts an overlay of the active profile without capturing edits and
-- lays it again; without an overlay it does neither.
steps={}
assert(not Suite.ProfileVariants.LiftOverlay("Default") and #steps==0,"undo lifted an overlay that does not exist")
overlay=true
assert(Suite.ProfileVariants.LiftOverlay("Default"))
Suite.ProfileVariants.LayOverlay()
assert(table.concat(steps,",")=="lift,resolve","undo did not lift and lay the overlay: "..table.concat(steps,","))
overlay=false
Suite.Suite.Normalize,core.ProfileVariants.Restore,core.ProfileVariants.ResolveCurrent=normalize,restore,resolve
core.ProfileRuntime.Apply=apply
local texts=Suite.DB.suite.modules.dataTexts
texts.barIds="99"
texts.bar99Enabled=true;texts.bar99Name="Custom";texts.bar99Width=240
local projected=provider.Snapshot(Suite.DB.suite.modules)
assert(projected.dataTexts.bar99Name=="Custom" and texts.bar99Height==nil,
    "dynamic bar rule defaults are projected on the snapshot, never added to the live source")
assert(provider.Allows({"suiteModules","dataTexts","bar99Width"}))
local _,dynamicValid=provider.Check({"suiteModules","dataTexts","bar99Width"},"bad",false)
assert(not dynamicValid)
local clean=assert(Suite.ProfileIO.PrepareTable(Suite.DB,false))
assert(clean.suite.modules.dataTexts.bar99Name=="Custom" and clean.suite.modules.dataTexts.bar99Width==240,
    "module IO retains actual dynamic rule keys")
assert(texts.bar99Height==nil,"import/export preparation cannot normalize or mutate its source")
local target=Suite.CopyValue(projected)
target.dataTexts.bar123Enabled=true;target.dataTexts.bar123Name="Added"
assert(provider.Restore(target,projected))
assert(target.dataTexts.bar123Name==nil and target.dataTexts.bar99Name=="Custom",
    "restoring a base removes documented dynamic settings created during recording")
-- On an older core the optional adapter stays inactive and existing APIs work.
MSUF_NS={}
local old={SuiteCatalog=Suite.SuiteCatalog,Suite=Suite.Suite,Database=Suite.Database,CopyValue=Suite.CopyValue}
assert(loadfile(root.."/MSUF_Suite/Core/ProfileVariants.lua"))("MSUF_Suite",old)
assert(not old.ProfileVariants.Register() and old.ProfileVariants.CanMutate())
print("suite_profile_variants_contract: OK")
