return function(world,scenario)
local Suite,S,AB,M=world.Suite,world.S,world.AB,world.M
local MainBar,RunTimers=world.MainBar,world.RunTimers

-- Only action bars are relevant. The real Suite Start, listener, Activate,
-- Apply, setters and ActionBars lifecycle remain unmodified. Variants are
-- disabled in this fixture, so their policy hooks have no side effects.
Suite.ProfileVariants={CanMutate=function() return true end,OnActivated=function() end}
for id in pairs(S.catalog) do S.Config(id).enabled=false end
local first=Suite.DB
local firstName=Suite.Database.GetActiveProfileName()
local a=first.suite.modules.actionbars
a.enabled=true;a.imported=false;a.bar1X=-101
local second=Suite.CopyValue(first)
local b=second.suite.modules.actionbars
b.bar1X=-202
Suite.RootDB.profiles.Second=second
local writes={}
local originalSetMany=S.SetMany
S.SetMany=function(id,values)
    if id=="actionbars" and values.imported then
        writes[#writes+1]={profile=Suite.DB,config=S.Config(id),x=values.bar1X,combat=world.GetCombat()}
    end
    return originalSetMany(id,values)
end
MainBar.cx=623 -- 111 pixels from UIParent's centre.
S.Start()
assert(M.active and S.states.actionbars.active,"real Start did not enable actionbars")
assert(a.imported==false and #writes==0,"capture persisted synchronously")
local function Activate(name,x)
    MainBar.cx=x
    assert(Suite.Database.Activate(name),"real profile activation refused")
    assert(M.config==S.Config("actionbars"),"profile listener did not apply new config")
end
if scenario=="a_to_b_false" then
    Activate("Second",734)
    RunTimers()
    assert(a.imported==false and a.bar1X==-101,"A changed while B active")
    assert(b.imported==true and b.bar1X==222,"B did not persist its own capture")
    assert(#writes==1 and writes[1].profile==second and writes[1].x==222,"stale A capture was dispatched")
elseif scenario=="a_to_b_true" then
    b.imported=true
    Activate("Second",734)
    RunTimers()
    assert(a.imported==false and a.bar1X==-101 and b.bar1X==-202 and #writes==0,
        "imported B accepted A's capture")
elseif scenario=="a_to_b_to_a" or scenario=="a_to_imported_b_to_a" then
    if scenario=="a_to_imported_b_to_a" then b.imported=true end
    Activate("Second",734)
    Activate(firstName,845)
    RunTimers()
    assert(a.imported==true and a.bar1X==333,"A returning before old timer retained stale capture")
    assert(b.bar1X==-202 and b.imported==(scenario=="a_to_imported_b_to_a"),"B changed while A active")
    assert(#writes==1 and writes[1].profile==first and writes[1].x==333,"obsolete generation persisted")
elseif scenario=="same_config_reenable" then
    assert(S.Set("actionbars","enabled",false))
    MainBar.cx=734
    assert(S.Set("actionbars","enabled",true))
    assert(M.config==a,"disable/enable replaced same config fixture")
    RunTimers()
    assert(a.imported==true and a.bar1X==222,"same-config reenable accepted previous generation")
    assert(#writes==1 and writes[1].x==222,"old same-config timer dispatched")
elseif scenario=="combat_retry" then
    world.SetCombat(true)
    RunTimers()
    assert(a.imported==false and a.bar1X==-101,"combat capture persisted")
    world.SetCombat(false)
    MainBar.cx=734
    S.Apply("actionbars")
    RunTimers()
    assert(a.imported==true and a.bar1X==111,"combat retry lost the capture from before native takeover")
    assert(writes[#writes].x==111,"retry recaptured already disposed native bars")
elseif scenario=="config_reset" then
    local replacement=Suite.CopyValue(a)
    replacement.bar1X=-303
    first.suite.modules.actionbars=replacement
    MainBar.cx=734
    S.Apply("actionbars")
    RunTimers()
    assert(a.imported==false and a.bar1X==-101,"reset persisted into old config")
    assert(replacement.imported==true and replacement.bar1X==222,"reset did not capture new config")
    assert(#writes==1 and writes[1].config==replacement and writes[1].x==222,"old reset capture dispatched")
elseif scenario=="refresh_dedup" then
    for i=1,20 do S.Apply("actionbars") end
    RunTimers()
    assert(a.imported==true and a.bar1X==111 and #writes==1,"normal repeated refresh duplicated first import")
else error("unknown scenario "..scenario) end
print("independent actionbars "..scenario.." "..tostring(world.mode).." passed")

end
