local root=assert(arg[1],"repository root required")
local combat,registers,applies,hides=false,0,0,0
local frame={points={},scale=1}
function frame:GetScale() return self.scale end
function frame:ClearAllPoints() self.points={} end
function frame:SetPoint(...) self.points={...} end
UIParent={}
local configs={main={x=5,y=7,width=100,height=20,scale=100},secondary={x=0,y=0,width=100,height=20,scale=100}}
local NS={DB={},Safety={IsForbidden=function() return false end},IsCombatLocked=function() return combat end}
local rules={x={min=-500,max=500,default=0},y={min=-500,max=500,default=0},width={min=50,max=300,default=100},height={min=10,max=60,default=20},scale={min=50,max=200,default=100}}
local S={catalog={main={rules=rules},secondary={rules=rules}},states={main={active=true},secondary={active=true}},instances={}}
S.Finite=function(v) return type(v)=="number" and v==v end
S.Text=function(v) return "translated:"..v end
S.Config=function(id) return configs[id] end
S.SetMany=function(id,values) for k,v in pairs(values) do configs[id][k]=v end;return true end
S.Set=function(id,k,v) return S.SetMany(id,{[k]=v}) end
S.CommitEditPosition=function(id,values) if combat then return false end;return S.SetMany(id,values) end
S.Apply=function() applies=applies+1 end
S.Dispatch=function(fn,...) return pcall(fn,...) end
S.instances.main={HideEditPreview=function() hides=hides+1 end}
local records={}
MSUF_EditModeAPI={RegisterElement=function(owner,element) registers=registers+1;records[owner.."/"..element.id]=element;return true end,
    RegisterSessionListener=function(_,callback) S.session=callback end,IsActive=function() return false end,
    UnregisterOwner=function(owner) for key in pairs(records) do if key:find(owner,1,true)==1 then records[key]=nil end end end,
    UnregisterSessionListener=function() S.session=nil end}
assert(loadfile(root.."/MSUF_Suite_Modules/EditMode.lua"))("test",{NS=NS,Suite=S})
local visible=true
assert(S.RegisterOwnedMover("main","main",{label="Main",getFrame=function() return frame end,xKey="x",yKey="y",point="CENTER",
    visible=function() return visible end,sizeKeys={"width","height","scale"},historyKeys={"width"}}))
local element=records["MSUFSuite.main/main"]
assert(element.isEnabled());visible=false;assert(not element.isEnabled(),"inactive element visibility predicate ignored");visible=true
local controls={};for _,control in ipairs(element.extraControls) do controls[control.id]=control end
assert(controls.width.label=="translated:Width" and controls.height.label=="translated:Height","generic sizing labels not localized")
local before=element.captureState();assert(controls.width.set(140) and controls.height.set(30))
assert(element.restoreState(before) and configs.main.width==100 and configs.main.height==20,"dimension edits lost undo/discard baseline")
assert(element.movePosition({state=before,deltaX=10,deltaY=-2,phase="drag"}) and frame.points[4]==15 and configs.main.x==5,"drag preview wrote saved position")
assert(element.movePosition({state=before,deltaX=10,deltaY=-2,phase="commit"}) and configs.main.x==15,"drag commit failed")
combat=true;assert(not element.movePosition({state=before,deltaX=1,deltaY=1,phase="commit"}),"combat mutation accepted")
S.SetEditMode(true);S.SetEditMode(false);assert(hides==1,"combat exit deferred own-preview cleanup")
combat=false
NS.DB={};assert(not element.restoreState(before),"old profile drag state restored into new profile")
assert(S.RegisterOwnedMover("main","main",{getFrame=function() return frame end,xKey="x",yKey="y"}) and registers==1,"cached mover allocated again")
assert(S.RegisterOwnedMover("secondary","child",{label="Child",getFrame=function() return frame end,xKey="x",yKey="y"}))
local child=records["MSUFSuite.secondary/child"]
for _,control in ipairs(child.extraControls) do assert(control.id~="width" and control.id~="height" and control.id~="scale","child mover incorrectly edits parent module size") end
S.UnregisterEditElements("main");assert(not records["MSUFSuite.main/main"],"removed owner record survived")
-- Action bars and the Minimap can both be anchored to a screen edge with
-- local X = 0. Use the host's screen coordinate row when it supports one.
MSUF_EditModeAPI.GetCapabilities = function() return { positionFields = true } end
assert(S.RegisterOwnedMover("secondary", "oldEdge", {
    label = "Old host", getFrame = function() return frame end, xKey = "x", yKey = "y", point = "TOPRIGHT",
}))
local oldEdge = records["MSUFSuite.secondary/oldEdge"]
assert(#oldEdge.extraControls == 2 and oldEdge.extraControls[1].positionAxis == "x",
    "an older host lost its working owner offset controls")
MSUF_EditModeAPI.GetCapabilities = function() return { positionFields = true, relativePositionSteps = true } end
for _, edge in ipairs({ "LEFT", "TOPRIGHT" }) do
    local id = edge:lower()
    frame.scale = edge == "LEFT" and 0.8 or 2
    configs.secondary.x, configs.secondary.y = 0, -12
    assert(S.RegisterOwnedMover("secondary", id, {
        label = edge, getFrame = function() return frame end, xKey = "x", yKey = "y",
        point = edge, sizeKeys = { "width" },
    }))
    local registered = records["MSUFSuite.secondary/" .. id]
    assert(#registered.extraControls == 1 and registered.extraControls[1].id == "width",
        edge .. " mover still uses local X/Y and hides the host's screen position")
    assert(configs.secondary.x == 0 and configs.secondary.y == -12, "registration moved a saved edge layout")
    local state = registered.captureState()
    local dx = edge == "LEFT" and 1 or -1
    local delta = dx * math.max(1, frame.scale)
    local nextX = edge == "LEFT" and 1.3 or -1
    assert(registered.movePosition({ state = state, deltaX = delta, deltaY = 0, phase = "commit" }))
    assert(configs.secondary.x == nextX and configs.secondary.y == -12, "scaled screen step lost the original anchor offsets")
    assert(registered.restoreState(state) and configs.secondary.x == 0, "edge position undo failed")
end
frame.scale = 1

local relative = { { id = "relativeX", positionAxis = "x" }, { id = "relativeY", positionAxis = "y" } }
assert(S.RegisterOwnedMover("secondary", "relative", {
    label = "Relative", getFrame = function() return frame end, xKey = "x", yKey = "y",
    quickPosition = false, extraControls = relative,
}))
assert(records["MSUFSuite.secondary/relative"].extraControls == relative, "explicit relative controls were replaced")
print("PASS shared owned mover visibility, explicit sizing, localization, save/discard/profile/combat lifecycle")
