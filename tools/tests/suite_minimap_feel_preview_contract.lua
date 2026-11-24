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
SUITE_OPTIONS_FIXTURE = true
local fixture = assert(original(root .. "/tools/tests/suite_options_menu_contract.lua"))()
SUITE_OPTIONS_FIXTURE = nil
local ctx = { key = "suite_minimap", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
fixture.SetCurrent(ctx)
fixture.M.pages.suite_minimap.build(ctx)
loadfile = original
assert(ui and P,"minimap preview did not build")
GetMinimapZoneText=function() return "Native Subzone" end
GetZoneText=function() return "Dornogal" end
GetSubZoneText=function() return "Contender's Gate" end
C_Texture.GetAtlasInfo=function() return {file=777,leftTexCoord=.125,rightTexCoord=.375,topTexCoord=.5,bottomTexCoord=.75} end
local c=P.S.Config("minimap")
for k,v in pairs({shape=1,size=240,borderSize=2,outerBorderSize=2,outerBorderGap=4,styleBackdrop=true,
    styleBackdropPadding=6,styleBackdropAlpha=100,styleTexture=1,dungeonButton=true,dungeonStyle=2,dungeonIcon=1,
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
    local point,relative,relativePoint=unpack(icon.points[1])
    assert(#icon.points==1 and point=="CENTER" and relative==item.button and relativePoint=="CENTER"
        and icon.texture=="Interface\\AddOns\\MSUF_Suite\\Media\\GroupFinder\\Eye"
        and math.abs(icon.width-26*.62*art.scale)<1e-8 and icon.width==icon.height,
        "the preview eye glyph does not stand square on its badge like the runtime")
    assert(item.button:GetWidth()==48*art.scale and item.button:GetHeight()==26*art.scale,"preview tile geometry differs from runtime")
    assert(item.button.dungeonRing:IsShown() and item.button.dungeonDisc:IsShown()
        and math.abs(item.button.dungeonRing.width-26*art.scale)<1e-8,"preview round badge missing")
    assert(not item.backdrop:IsShown(),"the preview drew a box behind the symbol")
end
-- Default shows the symbol bare; Blizzard's eye is its flipbook's first frame.
local symbols,icon,scale=P.Suite.MinimapGroupFinderSymbol,item.button.previewIcon,ui.art.scale
c.dungeonStyle=1;ui.Paint()
assert(not item.button.dungeonRing:IsShown() and math.abs(icon.width-26*scale)<1e-8 and not item.backdrop:IsShown(),
    "preview Default kept a badge or a box")
c.dungeonIcon=symbols.BLIZZARD;ui.Paint()
local l,r,t,b=unpack(icon.texCoords)
assert(icon.texture==777 and math.abs(l-.125)<1e-8 and math.abs(r-(.125+.25/11))<1e-8
    and math.abs(t-.5)<1e-8 and math.abs(b-(.5+.25/8))<1e-8,"the preview Blizzard eye is not cut from its flipbook file")
c.dungeonIcon=symbols.GROUP;ui.Paint()
assert(icon.texture=="Interface\\AddOns\\MSUF_Suite\\Media\\GroupFinder\\Group","the group glyph is missing")

c.infoLocationSource=3;ui.Paint()
assert(location.label.text=="Contender's Gate","preview location source retained stale text")
c.infoLocationSource=5;c.infoLocationBelow=true;ui.Paint()
assert(location.label.text=="Dornogal\nContender's Gate","preview did not show both place names")
print("Minimap options preview: scaled frame layering, queue eye, group finder symbols and location source switching passed")
