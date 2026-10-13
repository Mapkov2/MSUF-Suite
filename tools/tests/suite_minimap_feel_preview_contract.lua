local root=assert(arg[1])
local original,ui,P=loadfile
loadfile=function(path)
    local chunk=assert(original(path))
    if path:match("/Pages/MinimapPreview%.lua$") then
        return function(addon,ns)
            P=ns
            local register=P.M.RegisterControlMetadata
            P.M.RegisterControlMetadata=function(widget,...)
                local value=rawget(widget,"previewUI")
                if type(value)=="table" and value.state then ui=value end
                return register(widget,...)
            end
            chunk(addon,ns)
        end
    end
    return chunk
end
assert(original(root.."/tools/tests/suite_options_menu_contract.lua"))()
loadfile=original
assert(ui and P,"minimap preview did not build")
GetMinimapZoneText=function() return "Native Subzone" end
GetZoneText=function() return "Dornogal" end
GetSubZoneText=function() return "Contender's Gate" end
C_Texture.GetAtlasInfo=function() return {leftTexCoord=.125,rightTexCoord=.375,topTexCoord=.5,bottomTexCoord=.75} end
local c=P.S.Config("minimap")
for k,v in pairs({shape=1,size=240,borderSize=2,outerBorderSize=2,outerBorderGap=4,styleBackdrop=true,
    styleBackdropPadding=6,styleBackdropAlpha=100,styleTexture=1,dungeonButton=true,dungeonStyle=2,
    dungeonWidth=48,dungeonHeight=26,dungeonAnchor=1,dungeonX=8,dungeonY=-16,infoLocation=true,
    infoLocationSource=4,infoLocationBelow=false}) do c[k]=v end
for k in pairs(ui.state.layers) do ui.state.layers[k]=true end
ui.state.layers.guides,ui.state.layers.hidden=false,false
local item,location
for _,v in ipairs(ui.textItems) do if v.spec[1]=="Location" then location=v end end
assert(location,"no location preview")
for _,v in ipairs(ui.iconItems) do if v.spec[1]=="dungeon" then item=v end end
assert(item,"no dungeon preview")
for _,width in ipairs({300,720}) do
    ui.body:SetWidth(width)
    ui.Paint()
    local art=ui.art
    assert(location.label.text=="Native Subzone","preview ignored the selected location source")
    assert(art.style.under:GetFrameLevel()<art.borderSurface:GetFrameLevel(),"opaque preview plate covers ring")
    local icon=item.button.previewIcon
    local l,r,t,b=unpack(icon.texCoords)
    assert(math.abs(l-.2)<1e-8 and math.abs(r-.3)<1e-8 and math.abs(t-.59)<1e-8 and math.abs(b-.66)<1e-8,
        "preview eye crop differs from runtime")
    assert(item.button:GetWidth()==48*art.scale and item.button:GetHeight()==26*art.scale,"preview tile geometry differs from runtime")
    assert(item.button.dungeonBand:IsShown() and item.button.dungeonInner:IsShown(),"preview double frame missing")
    local _,_,_,x,y=unpack(icon.points[1])
    assert(x==5*art.scale and y==-5*art.scale,"preview frame inset was not scaled")
end
c.dungeonStyle=1;ui.Paint()
assert(not item.button.dungeonBand:IsShown() and not item.button.dungeonInner:IsShown(),"preview Default retained modern frame")

c.infoLocationSource=3;ui.Paint()
assert(location.label.text=="Contender's Gate","preview location source retained stale text")
c.infoLocationSource=5;c.infoLocationBelow=true;ui.Paint()
assert(location.label.text=="Dornogal\nContender's Gate","preview did not show both place names")
print("Minimap options preview: scaled frame layering, queue eye and location source switching passed")
