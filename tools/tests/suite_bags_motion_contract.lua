local root=assert(arg[1])
local fighting,reduced=false,false
local P={ NS={ BagsAnimation={OFF=1,SIMPLE=2,FULL=3},InCombat=function() return fighting end,
 HostBridge={MenuReducedMotion=function() return reduced end} } }
assert(loadfile(root.."/MSUF_Suite_Bags/Motion.lua"))("Bags",P)
local groups={}
local function Frame()
 return {CreateAnimationGroup=function()
 local g={plays=0,stops=0}
 function g:CreateAnimation(kind)
  assert(kind=="Alpha")
  local a={}
  for _,name in ipairs({"FromAlpha","ToAlpha","Duration","Smoothing","StartDelay"}) do
   a["Set"..name]=function(self,value) self[name]=value end
  end
  self.alpha=a
 return a
 end
 function g:Play() self.plays=self.plays+1 end
 function g:Stop() self.stops=self.stops+1 end
 groups[#groups+1]=g
 return g
 end}
end
local frame=Frame()
P.BagMotion.Play(frame,{animationMode=1})
 assert(#groups==0,"off allocated animation")
P.BagMotion.Play(frame,{animationMode=2})
 local g=groups[1]
assert(g.plays==1 and g.alpha.Duration==.12 and g.alpha.StartDelay==0)
P.BagMotion.Play(frame,{animationMode=3},99)
assert(#groups==1 and g.plays==2 and g.alpha.Duration==.18 and g.alpha.StartDelay==.09)
reduced=true
 P.BagMotion.Play(frame,{animationMode=3})
 assert(g.plays==2,"reduced motion played animation")
reduced=false
 fighting=true
 P.BagMotion.Play(frame,{animationMode=3})
 assert(g.plays==2,"combat edge played animation")
fighting=false
 P.BagMotion.Play(Frame(),{animationMode=2})
P.BagMotion.StopAll()
 assert(groups[1].stops>0 and groups[2].stops>0)
print("independent off/simple/full/reduced/combat motion checks passed")
