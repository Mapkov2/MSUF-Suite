-- Native stat appearance survives combat updates and a close/reopen.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_character_stats_dr_contract.lua", "rb"))
local source = file:read("*a"); file:close()
local stop = assert(source:find("-- PLAYER_REGEN_DISABLED fires",1,true))
local H = assert(loadstring(source:sub(1,stop-1) .. [[
return { NS=NS, Object=Object, SetCombat=function(value) combatLocked=value end }
]], "@character_stats_combat_fixture"))()
local NS, checks = H.NS, 0
NS.Safety.Dispatch=function(callback,...) return callback(...) end
local surface={}
NS.Surface.Attach=function() return surface end
NS.Surface.Ensure=NS.Surface.Attach
InCombatLockdown=function() return false end
local writes=0
local function Object(fields)
    local object=H.Object(fields)
    object.path,object.size,object.color="native",12,{1,.82,0,1}
    function object:IsProtected() return self.protected,self.explicit end
    function object:IsForbidden() return self.forbidden == true end
    local function Writable(self)
        assert(not self.forbidden and not self.explicit and not (self.protected and NS.IsCombatLocked()),"unsafe stat target write")
        writes=writes+1
    end
    function object:SetHeight(height) Writable(self); self.height=height end
    function object:SetShown(value) Writable(self); if value then self:Show() else self:Hide() end end
    function object:GetFont() return self.path,self.size,"" end
    function object:SetFont(path,size) Writable(self); self.path,self.size=path,size end
    function object:GetTextColor() return unpack(self.color) end
    function object:SetTextColor(r,g,b,a) Writable(self); self.color[1],self.color[2],self.color[3],self.color[4]=r,g,b,a end
    function object:GetNumPoints() return self.point and 1 or 0 end
    function object:GetPoint() return self.point,self.relative,self.relativePoint,self.x,self.y end
    function object:SetPoint(point,relative,relativePoint,x,y)
        Writable(self); self.point,self.relative,self.relativePoint,self.x,self.y=point,relative,relativePoint,x,y
    end
    function object:ClearAllPoints() Writable(self); self.point=nil end
    function object:SetJustifyH(value) Writable(self); self.justify=value end
    function object:GetJustifyH() return self.justify or "CENTER" end
    function object:CreateFontString() return Object() end
    function object:CreateTexture() return Object() end
    return object
end
CreateFrame=function() return Object() end
local row=Object({Label=Object({text="Haste:"}),Value=Object()})
local count=0
local function NextRow(_,previous) if not previous then return row end end
local pane=Object({height=400, ItemLevelCategory=Object({Title=Object()}),
    AttributesCategory=Object({Title=Object()}),EnhancementsCategory=Object({Title=Object()}),
    statsFramePool={EnumerateActive=function() count=count+1; return NextRow end}})
local function Check(value,message) assert(value,message); checks=checks+1 end
NS.CharacterStats.Apply(pane,"combat")
local view=assert(NS.CharacterStats.views[pane])
local height,path,size,color=row.height,row.Label.path,row.Label.size,row.Label.color[1]
H.SetCombat(true)
row.height,row.Label.path,row.Label.size,row.Label.color[1]=20,"native",12,1
NS.CharacterStats.Refresh(view)
Check(row.height==height and row.Label.path==path and row.Label.size==size and row.Label.color[1]==color,
    "native stats update lost configured geometry or font/color during combat")
H.SetCombat(false); view.host:Hide()
Check(row.height==20,"close failed to release native geometry")
H.SetCombat(true); view.host:Show()
NS.CharacterStats.Apply(pane,"combat")
Check(row.height==height and row.Label.path==path and row.Label.color[1]==color,
    "cold combat reopen failed to restore stat appearance")
row.Label.protected=true
row.Label.path,row.Label.size,row.Label.color[1]="native",12,1
NS.CharacterStats.Refresh(view)
Check(row.Label.path=="native" and row.Label.color[1]==1,"protected font was painted at event edge")
row.Label.protected=nil
row.protected=true; row.height=20
NS.CharacterStats.Refresh(view)
Check(row.height==20,"protected row was resized")
row.protected=nil
NS.CharacterStats.Refresh(view)
local growth=math.huge
for _=1,2 do
    collectgarbage("collect"); collectgarbage("stop")
    local memory=collectgarbage("count")
    for index=1,1000 do NS.CharacterStats.Refresh(view) end
    growth=math.min(growth,collectgarbage("count")-memory)
    collectgarbage("restart")
end
Check(growth<2,"warm combat stats allocated: " .. growth .. " KiB")
local before=count
pane:Hide()
local paintWrites=writes
for _=1,1000 do NS.CharacterStats.Refresh(view); NS.CharacterStats.SyncDetails(pane) end
Check(count==before and writes==paintWrites,"hidden pane enumerated or painted stat rows")
print("Character stat combat parity: " .. checks .. " checks; " .. growth .. " KiB/1000 warm refreshes")
