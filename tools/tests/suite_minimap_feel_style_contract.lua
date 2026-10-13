local root=assert(arg[1])
local H=dofile(root.."/tools/tests/suite_minimap_harness.lua")
local function Near(a,b) return H.Near(a,b,1e-8) end
for _,flavor in ipairs({"Mainline","Forever"}) do
    local zone,subzone,minimap="Dornogal","Contender's Gate","Native Subzone"
    local W=H.New(root,flavor,{beforeModules=function(W)
        W.G.C_Texture={GetAtlasInfo=function() return {leftTexCoord=.125,rightTexCoord=.375,topTexCoord=.5,bottomTexCoord=.75} end}
        W.G.GetZoneText=function() return zone end
        W.G.GetSubZoneText=function() return subzone end
        W.G.GetMinimapZoneText=function() return minimap end
    end})
    H.Enable(W,{captured=true,size=240,point=3,x=-16,y=-16,borderSize=2,borderColor="000000",borderAlpha=100,
        outerBorderSize=2,outerBorderGap=4,outerBorderColor="000000",styleBackdrop=true,styleBackdropColor="16191b",
        styleBackdropAlpha=100,styleBackdropPadding=6,styleTexture=1,styleGlow=false,shadowSize=0,
        infoLocation=true,infoLocationSource=4,infoLocationZone=true,infoLocationSubzone=false,
        infoLocationBelow=false,dungeonButton=true,dungeonStyle=2,dungeonWidth=48,dungeonHeight=26,
        dungeonAnchor=1,dungeonX=8,dungeonY=-16})
    W.Step()
    local MM=W.MM
    assert(MM.style.under:GetFrameLevel()<MM.borderFrame:GetFrameLevel(),"opaque plate covers minimap ring")
    assert(MM.style.backdrop:GetWidth()==252,"charcoal band misses outer inner-ring reach")
    assert(MM.host:GetWidth()==240 and MM.host:GetPoint(1)=="TOPRIGHT","map geometry mismatch")
    local _,_,_,x,y=MM.host:GetPoint(1)
    assert(x==-16 and y==-16,"map outer margin not 8px")
    local b=assert(MM.dungeonButton)
    local icon=assert(b.dungeonIcon)
    assert(b:GetWidth()==48 and b:GetHeight()==26 and b.dungeonBand:IsShown() and b.dungeonInner:IsShown(),"modern tile missing double frame")
    assert(Near(icon.coords[1],.2) and Near(icon.coords[2],.3) and Near(icon.coords[3],.59) and Near(icon.coords[4],.66),"modern eye crop escaped native atlas")
    local _,_,_,ix,iy=icon:GetPoint(1)
    assert(ix==5 and iy==-5,"modern tile frame inset mismatch")
    assert(W.M.infoEntries.Location.label.text==minimap,"native minimap title was lost")
    assert(W.S.Set("minimap","dungeonStyle",1))
    assert(not b.dungeonBand:IsShown() and not b.dungeonInner:IsShown(),"modern tile frame leaked into Default style")
    assert(Near(icon.coords[1],.165) and Near(icon.coords[2],.335) and Near(icon.coords[3],.575) and Near(icon.coords[4],.675),"Default eye crop escaped native atlas")
    assert(W.S.Set("minimap","dungeonStyle",2) and b.dungeonBand:IsShown(),"style re-enable did not restore frame")
    for _,row in ipairs({{3,"Contender's Gate"},{2,"Dornogal"},{4,"Native Subzone"},{1,"Dornogal"}}) do
        assert(W.S.Set("minimap","infoLocationSource",row[1]))
        assert(W.M.infoEntries.Location.label.text==row[2],"same-zone source switch retained stale text")
    end
    assert(W.S.Set("minimap","infoLocationSource",4))
    minimap=""; W.Event("ZONE_CHANGED")
    assert(W.M.infoEntries.Location.label.text==subzone,"native title did not fall back to subzone")
    subzone=""; W.Event("ZONE_CHANGED")
    assert(W.M.infoEntries.Location.label.text==zone,"empty subzone did not fall back to zone")
    assert(W.S.SetMany("minimap",{infoLocationSource=5,infoLocationBelow=true}))
    assert(W.M.infoEntries.Location.button.height==W.config.infoLocationSize*2+8,"combined title did not reserve two lines")
    assert(W.S.SetMany("minimap",{infoLocationSource=3,infoLocationBelow=true}))
    assert(W.M.infoEntries.Location.button.height==W.config.infoLocationSize+8,"subzone-only retained two-line height")
    assert(W.S.Set("minimap","dungeonButton",false) and not b:IsShown(),"disabled tile stayed visible")
    assert(W.S.Set("minimap","dungeonButton",true) and b:IsShown(),"tile did not reappear")
end

local W=H.New(root,"Mainline")
local Style=W.Suite.MinimapStyle
local c={infoLocationSource=5,infoLocationBelow=false}
assert(Style.LocationContent(c,"Zone","Subzone","Native")=="Zone - Subzone")
c.infoLocationBelow=true
assert(Style.LocationContent(c,"Zone","Subzone","Native")=="Zone\nSubzone")
assert(Style.LocationContent(c,"Zone","Zone","")=="Zone","duplicate place name")
assert(Style.LocationContent(c,"","","")=="--","missing place label")
assert(Style.LocationContent(c,W.secret,"Subzone",W.secret)=="Subzone","secret name escaped")
c.infoLocationSource=4
assert(Style.LocationContent(c,W.secret,W.secret,W.secret)=="--","secret native location escaped")
assert(Style.LocationLines(c)==1,"native title reserved two lines")
print("Minimap frame layering, atlas crop, style lifecycle and location sources on both clients passed")
