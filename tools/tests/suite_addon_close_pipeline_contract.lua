-- Real close renderer, control, Ace and bounded GenericWindows integration.
-- Artwork/state contracts; native rendering and taint are separate checks.
local root,style,route=assert(arg[1]),arg[2] or "native",arg[3] or "ace"
local flavor=arg[5] or "Mainline"
if style=="Mainline" or style=="Forever" then flavor,style=style,"all" end
local function Run(style,route)
local function Read(path) local f=assert(io.open(path,"rb")) local s=f:read("*a") f:close() return (s:gsub("\r\n","\n")) end
local source=Read(root.."/tools/tests/suite_skin_motion_contract.lua")
source=source:gsub('arg%[2%] == "Forever"',flavor=="Forever" and "true" or "false")
source=source:sub(1,assert(source:find('local parent = Target("Frame", UIParent)',1,true))-1)
local first=assert(source:find('NS.Checkmarks = {',1,true))
local last=assert(source:find('Load("Rendering/WindowActionSkin.lua")',first,true))
source=source:sub(1,first-1)..'Load("Core/Checkmarks.lua")\n'
    ..'NS.Checkmarks.TrackDropdown, NS.Checkmarks.UntrackDropdown = Noop, Noop\n'
    ..'NS.Checkmarks.RegisterLegacyDropdowns, NS.Checkmarks.ReleaseMenus = Noop, Noop\n'
    ..source:sub(last)
local H=assert(loadstring(source..[[
return {NS=NS,Target=Target,Texture=Texture}
]],"@integrated-close-host"))()
local NS=H.NS
NS.CombatGate.RunOrDefer=function(_,fn) return fn() end
NS.DB.enabled=true
NS.DB.icons.windowActions.style=style
NS.DB.icons.windowActions.closeStyle="global"
NS.LabelStyle={CanStyle=function() return false end,Apply=function() end}
NS.ScrollBarSkin={Apply=function() end}
assert(loadfile(root.."/MSUF_Suite_Skin/Adapters/AddonSkinVisuals.lua"))("MSUF_Suite_Skin",NS)
assert(loadfile(root.."/MSUF_Suite_Skin/Adapters/AceWidgets.lua"))("MSUF_Suite_Skin",NS)
local function Texture(path)
    local t=H.Texture()
    function t:GetObjectType() return "Texture" end
    function t:GetTexture() return path end
    function t:GetAtlas() return nil end
    return t
end
local parent=H.Target("Frame",UIParent)
local close=H.Target("Button",parent)
local native={}
for _,key in ipairs({"Normal","Pushed","Disabled","Highlight"}) do
    native[key]=Texture("Interface/AddOns/Test/CustomClose"..key..".tga") close.slots[key]=native[key]
end
close.NormalTexture,close.HoverTexture,close.Icon=Texture("native-normal"),Texture("native-hover"),Texture("native-icon")
close.Bg=Texture("native-close-background")
close.Text=Texture()
function close.Text:GetText() return "X" end
function close:GetText() return "" end
function parent:GetChildren() return close end
parent.CustomCloseButton=close
local originalClick=function() end close:SetScript("OnClick",originalClick)
local owner="integration-review"
NS.AddonSkinVisuals.Close(parent,owner)
assert(NS.WindowActionSkin.GetKind(close)=="close" and NS.WindowActionSkin.IsApplied(close),"explicit custom close did not initially register")
if route=="dynamic" then
    NS.WindowActionSkin.Disable(close,owner)
    local suffixes={Normal="",Pushed="-pressed",Disabled="-disabled",Highlight="-highlight"}
    for key,suffix in pairs(suffixes) do
        local t=Texture() t.atlas="redbutton-exit"..suffix function t:GetAtlas() return self.atlas end close.slots[key]=t
    end
    assert(NS.WindowActionSkin.Apply(close,owner,"close"))
    assert(not NS.WindowActionSkin.GetExplicitKind or NS.WindowActionSkin.GetExplicitKind(close)==nil,"inferred atlas action acquired an explicit lease")
    local latest={}
    for key in pairs(suffixes) do latest[key]=Texture("ordinary-button-"..key) close.slots[key]=latest[key] end
    NS.Checkmarks.TrackButton(close,owner)
    assert(not NS.WindowActionSkin.IsApplied(close),"inferred action survived a native non-action artkit")
    for key,t in pairs(latest) do assert(close.slots[key]==t,"automatic stale-action cleanup overwrote newer native art") end
    print("integrated inferred nonaction pipeline passed: "..style)
    return
end
if route=="style-cycle" then
    function close:GetBackdrop() return {bgFile="native-backdrop"} end
    for _,nextStyle in ipairs({"native","bare","soft","outline","native"}) do
        NS.DB.icons.windowActions.style=nextStyle
        assert(NS.WindowActionSkin.Refresh(close),"explicit style refresh failed: "..nextStyle)
        NS.ControlSkin.ApplyButton(close,owner)
        NS.AddonSkinVisuals.Tree(parent,owner)
        assert(NS.Checkmarks.GetWindowAction(close)=="close" and NS.WindowActionSkin.IsApplied(close),"explicit style cycle lost action identity: "..nextStyle)
    end
    assert(not NS.WindowActionSkin.Disable(close,"foreign-owner"),"foreign owner disabled the explicit close")
    assert(NS.WindowActionSkin.Disable(close,owner))
    assert(NS.WindowActionSkin.GetExplicitKind(close)==nil and not NS.WindowActionSkin.IsApplied(close),"disabled explicit close retained its role")
    for key,t in pairs(native) do assert(close.slots[key]==t,"style-cycle disable lost original native state") end
    print("integrated explicit style/disable pipeline passed: "..style)
    return
end
if route=="backdrop" or route=="panel" then
    function close:GetBackdrop() return {bgFile="native-backdrop"} end
    local before=NS.Registry.GetSurface(close)
    local beforeSpec=before and before.spec
    local beforeFill=beforeSpec and beforeSpec.fillVisible
    if route=="panel" then NS.AddonSkinVisuals.Panel(close,owner,"panel") else NS.AddonSkinVisuals.Tree(parent,owner) end
    local after=NS.Registry.GetSurface(close)
    if style=="bare" or style=="native" then
        assert(not after or not after.visible,"generic backdrop pass added a rectangle beneath an explicit close: "..style)
    else
        assert(after and after.spec==beforeSpec and after.spec.fillVisible==beforeFill,
            "generic backdrop pass replaced the explicit close surface style: "..style)
    end
    if style=="native" then assert(close.Bg.alpha==1,"generic panel pass faded native close artwork") end
    print("integrated close backdrop pipeline passed: "..style)
    return
end
if route=="border" then
    close.BorderParts={Top=Texture(),Bottom=Texture(),Left=Texture(),Right=Texture()}
    NS.AddonSkinVisuals.Close(parent,owner)
    for _,region in pairs(close.BorderParts) do assert(region.alpha==0,"native LibSettingsDesigner BorderParts remained beneath explicit X") end
    print("integrated explicit border pipeline passed: "..style)
    return
end
if route=="restyle" or route=="restyle-track" then
    for _,key in ipairs({"Normal","Pushed","Disabled","Highlight"}) do close.slots[key]=Texture("new-custom-"..key) end
    if route=="restyle-track" then NS.Checkmarks.TrackButton(close,owner) else NS.AddonSkinVisuals.Close(parent,owner) end
    assert(NS.WindowActionSkin.HasOwnedStates(close),"explicit close did not adopt reconstructed custom native states")
    print("integrated explicit restyle pipeline passed: "..style)
    return
end
local widget={type="Frame",frame=parent,closebutton=close}
if route~="generic" then NS.AceWidgets.Apply(widget,owner) end
if route=="generic" then
    NS.BlizzardYellow.TrackFrames=function() end
    NS.SuiteOwnership={IsBagShell=function() return false end}
    NS.CharacterDetails={IsHost=function() return false end}
    NS.CharacterStats=NS.CharacterDetails
    NS.EQoLCharacter=NS.CharacterDetails
    NS.WindowControls={Attach=function() end,TrackFocus=function() end,DisableOwner=function() end}
    assert(loadfile(root.."/MSUF_Suite_Skin/Core/Cosmetics.lua"))("MSUF_Suite_Skin",NS)
    for _,file in ipairs({"AdapterKit","GenericWindows","GenericWindowsNodes","GenericWindowsFrames"}) do
        assert(loadfile(root.."/MSUF_Suite_Skin/Adapters/"..file..".lua"))("MSUF_Suite_Skin",NS)
    end
    UIParent.width,UIParent.height=1920,1080
    function parent:GetRegions() return end
    function close:GetRegions() return self.Text end
    function close:GetChildren() return end
    parent.CloseButton=close
    assert(NS.GenericWindows.ApplyFrame(parent,owner,{allowImplicitProtected=false}))
    NS.AddonSkinVisuals.Tree(parent,owner)
end
assert(NS.Checkmarks.GetWindowAction(close)=="close","explicit custom close role was lost through Checkmarks/AceWidgets: "..style)
assert(NS.WindowActionSkin.IsApplied(close),"generic button processing disabled the explicit action: "..style)
assert(close.scripts.OnClick==originalClick,"integrated decoration replaced the native click handler")
if style=="native" then
    for key,texture in pairs(native) do assert(close.slots[key]==texture,"native close was replaced with a generic button state: "..key) end
else
    assert(NS.WindowActionSkin.HasOwnedStates(close),"modern explicit close lost glyph state ownership")
end
print("integrated real close pipeline passed: "..style)
end
if style=="all" then
    for _,mode in ipairs({"native","bare","soft","outline"}) do
        for _,path in ipairs({"ace","generic","backdrop","panel","dynamic","style-cycle"}) do Run(mode,path) end
        if mode~="native" then for _,path in ipairs({"border","restyle","restyle-track"}) do Run(mode,path) end end
    end
    print("integrated explicit close contract: 33 cases passed ("..flavor..")")
else Run(style,route) end
