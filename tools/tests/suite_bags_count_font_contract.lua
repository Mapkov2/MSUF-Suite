local root=assert(arg[1])
local H=dofile(root.."/tools/tests/suite_bags_harness.lua")
local rendering=tonumber(arg[2]) or 3
local W=H.New(root,{config={inventoryView=1,fontRendering=rendering,font=arg[3] == "inherit" and "" or arg[3] or "",itemCountSize=13}})
-- The host's actual MSUF_SetFontChecked passes explicit flags to SetFont;
-- its other global font rendering settings are not consulted by that boundary.
local file=assert(io.open(root.."/../MidnightSimpleUnitFrames/MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua","rb"))
local source=file:read("*a"):gsub("\r\n","\n");file:close()
local checked=assert(source:match("(local function MSUF_SetFontChecked%b()%s+.-\nend)"))
MSUF_SetFontChecked=assert(loadstring("local SETFONT_RESULT_IS_READY=true\n"..checked.."\nreturn MSUF_SetFontChecked"))()
MSUF_GetFontPath=function() return "Interface/Fonts/Global.ttf" end
MSUF_ResolveFontKeyPath=function(key) return key=="Explicit" and "Interface/Fonts/Explicit.ttf" end
MSUF_DB={general={fontMonochrome=rendering~=2,fontSlug=rendering~=3}}
file=assert(io.open(root.."/../MidnightSimpleUnitFrames/MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_Core.lua","rb"))
source=file:read("*a"):gsub("\r\n","\n");file:close()
local flagsBody=assert(source:match("(GetGlobalFontFlags = function%b()%s+.-\nend)"))
MSUF_GetFontFlags=assert(loadstring("local EnsureDB=function() return MSUF_DB end\nlocal GetGlobalFontFlags\n"..flagsBody.."\nreturn GetGlobalFontFlags"))()
W.sizes[0]=2;W.Define(101,{name="Potion",class=0});W.Put(0,1,101,5)
W.Apply();W.OpenBags();W.Settle()
local actual
for _,item in ipairs(W.P.InventoryView.index.items) do
 if item.bag==0 and item.slot==1 then actual=item.button.Count end
end
local P={S=W.S,Suite=W.NS,Tr=function(s) return s end,catalog={bags=W.NS.SuiteCatalog.bags},
 T={colors={text={1,1,1}}},HM={SkipHistoryCheckpoint=function() end},PreviewInteraction={Outline=function() end},
 Combat=function() return false end,StylePreviewFont=W.S.SetStyledFont,
 SetTranslatedText=function(label,text) label:SetText(text) end}
P.Text=function(parent,text,x,y,width)
 local r=parent:CreateFontString(nil,"OVERLAY");r:SetText(text);r:SetHeight(12)
 r:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);r:SetWidth(width);return r
end
P.M={TrackRefresh=function(ctx,fn) ctx.refreshers[#ctx.refreshers+1]=fn end}
P.MenuWorkspace={FitHeader=function(ui,height) ui.header:SetHeight(height) end}
assert(loadfile(root.."/MSUF_Suite_Options/Menu/PreviewCanvas.lua"))("Options",P)
local ui={width=720,selected="bags",ctx={wrapper=CreateFrame("Frame",nil,UIParent),refreshers={}},
 header=CreateFrame("Frame",nil,UIParent),Focus=function() return true end}
ui.header:SetSize(720,220);ui.header:SetPoint("TOPLEFT",UIParent,"TOPLEFT",0,0)
assert(loadfile(root.."/MSUF_Suite_Options/Pages/BagsPreview.lua"))("Options",P)
P.BuildBagsMenuPreview(ui)
local path,size,flags=actual:GetFont()
local ppath,psize,pflags=ui.bagsPreview.slots[4].count:GetFont()
print("host global",MSUF_GetFontFlags(),"bag rendering",rendering,"runtime",path,size,flags,"preview",ppath,psize,pflags)
assert(path==ppath and size==psize and flags==pflags,"preview stack count font differs from actual inventory count")
print("actual runtime/provider count font parity passed")
