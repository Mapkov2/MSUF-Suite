local _,P=...;local NS,S=P.NS,P.Suite
-- Lifecycle, first-enable import, Edit Mode movers. The controller calls
-- Enable/Refresh/Disable out of combat only; runtime events do run in
-- combat and never touch protected state there.
local AB=P.ActionBars
local M=AB.M
local Public=S.Public
local floor,ceil,min,max=math.floor,math.ceil,math.min,math.max
AB.RELOAD_MESSAGE="Reload the UI to restore Blizzard's action bars"

local function Finite(value)
    return Public(value) and type(value)=="number" and value==value and value>-math.huge and value<math.huge
end

-- Position (as a CENTER offset) and grid of a shown Blizzard bar.
local function ImportGeometry(values,index,frame)
    local k=AB.KEYS[index]
    local x,y=frame:GetCenter()
    local scale,root=frame:GetEffectiveScale(),UIParent:GetEffectiveScale()
    local width,height=UIParent:GetWidth(),UIParent:GetHeight()
    if not (Finite(x) and Finite(y) and Finite(scale) and Finite(root) and root>0 and Finite(width) and Finite(height)) then return end
    values[k.Point]=5
    values[k.X]=floor((x*scale/root-width/2)*10+.5)/10
    values[k.Y]=floor((y*scale/root-height/2)*10+.5)/10
    if index>8 then return end
    local rows,shown,horizontal=frame.numRows,frame.numButtonsShowable,frame.isHorizontal
    if Finite(rows) and Finite(shown) and Public(horizontal) and type(horizontal)=="boolean" then
        shown,rows=min(max(floor(shown),1),12),min(max(floor(rows),1),12)
        values[k.Buttons]=shown
        values[k.Vertical]=not horizontal
        -- Blizzard counts columns for vertical bars; the suite counts rows.
        values[k.Rows]=horizontal and rows or ceil(shown/rows)
    end
    local padding=frame.buttonPadding
    if Finite(padding) then values[k.Spacing]=min(max(floor(padding+.5),-10),20) end
end

-- Import Blizzard positions and grids without copying visibility. The suite's
-- first-enable mouseover defaults must apply even to hidden Blizzard bars.
function AB.BuildImport(state)
    local values={imported=true}
    for index=1,12 do
        local entry,k=state[index],AB.KEYS[index]
        local frame=entry and entry.frame
        if entry and AB.Available(index) then
            local shown=frame~=nil and frame:IsShown()==true
            if index>=2 and index<=8 and entry.toggle~=nil then
                shown=entry.toggle==true
            end
            if frame and shown then ImportGeometry(values,index,frame) end
        end
    end
    return values
end

-- Settings are written after the current apply finished (S.SetMany re-runs
-- Refresh); a combat start in between retries on the next refresh.
local function QueueImport(values)
    AB.importQueued=true
    local function Write()
        if not M.active or M.config.imported then return end
        if not S.SetMany("actionbars",values) then AB.importQueued=nil end
    end
    if C_Timer then C_Timer.After(0,Write) else Write() end
end

local function LayoutAll()
    for index=1,AB.BAR_COUNT do
        local bar=AB.bars[index]
        if bar then
            if index>=11 then AB.Adopt(index) end
            AB.LayoutBar(bar)
            if index==11 then bar.forms=AB.HasForms() end
        end
    end
end

function M:Enable()
    AB.ResolveAPI()
    AB.Build()
    local state=not self.config.imported and AB.ReadBlizzard() or nil
    AB.Dispose()
    AB.HookNativePresses()
    S.states.actionbars.reloadRequired=nil
    if state and not AB.importQueued then QueueImport(AB.BuildImport(state)) end
    self:Refresh()
end

function M:Refresh()
    if NS.IsCombatLocked() then S.Queue("actionbars");return end
    if not self.config.imported and not AB.importQueued then QueueImport(AB.BuildImport(AB.ReadBlizzard())) end
    AB.ReparentLeaveButton()
    AB.UpdateCurves()
    LayoutAll()
    AB.StyleAll()
    AB.ApplyPaging()
    AB.ApplyVisibility()
    AB.UpdateClickAttributes()
    if AB.dispatching then AB.SyncOptionalEvents();AB.MarkAll()
    else AB.dispatching=true;AB.StartDispatcher() end
    AB.UpdateRouting()
    AB.ApplyDrag()
end

-- Blizzard's bars cannot be rebuilt at runtime: the suite bars hide, their
-- drivers and override bindings go, and a reload restores Blizzard's bars.
-- A later enable in the same session reuses every frame.
function M:Disable()
    AB.StopDispatcher()
    AB.dispatching=nil
    AB.StopPaging()
    AB.StopVisibility()
    AB.ClearRouting()
    AB.importQueued=nil
    if AB.disposed then S.states.actionbars.reloadRequired=AB.RELOAD_MESSAGE end
end

local function NumberControl(id,key)
    local rule=S.catalog.actionbars.rules[key]
    return {id=id,label=S.Text(rule.label),kind="number",min=rule.min,max=rule.max,step=1,
        get=function() return S.Config("actionbars")[key] end,
        set=function(value) return S.Set("actionbars",key,value) end}
end

-- A one-column bar stays one column when its button count changes here.
local function ButtonCountControl(index)
    local k=AB.KEYS[index]
    local control=NumberControl("buttons",k.Buttons)
    control.set=function(value)
        local c=S.Config("actionbars")
        if c[k.Rows]>=c[k.Buttons] then
            return S.SetMany("actionbars",{[k.Buttons]=value,[k.Rows]=value})
        end
        return S.Set("actionbars",k.Buttons,value)
    end
    return control
end

-- The popup exposes one-click row and column layouts. A custom Rows value
-- remains available for grids; neither orientation button is selected then.
local function OrientationControl(index,vertical)
    local k=AB.KEYS[index]
    return {id=vertical and "vertical" or "horizontal",label=S.Text(vertical and "Vertical" or "Horizontal"),kind="toggle",
        get=function()
            local c=S.Config("actionbars")
            if c[k.Buttons]==1 then return c[k.Vertical]==vertical end
            return vertical and c[k.Rows]>=c[k.Buttons] or not vertical and c[k.Rows]==1
        end,
        set=function(on)
            if not on then return false end
            local c=S.Config("actionbars")
            return S.SetMany("actionbars",{[k.Vertical]=vertical,[k.Rows]=vertical and c[k.Buttons] or 1})
        end}
end

-- Mouseover on/off keeps the combat part of the current mode.
local function MouseoverControl(key)
    return {id="mouseover",label=S.Text("Show on mouseover"),kind="toggle",
        get=function() local mode=S.Config("actionbars")[key];return mode==4 or mode==5 end,
        set=function(on)
            local mode=S.Config("actionbars")[key]
            local value
            if on then value=(mode==2 or mode==5) and 5 or 4 else value=mode==5 and 2 or mode==4 and 1 or mode end
            return S.Set("actionbars",key,value)
        end}
end

local function Controls(index)
    AB.controls=AB.controls or {}
    local list=AB.controls[index]
    if not list then
        local k=AB.KEYS[index]
        list={ButtonCountControl(index),NumberControl("rows",k.Rows),NumberControl("size",k.Size),
            NumberControl("spacing",k.Spacing),OrientationControl(index,false),OrientationControl(index,true),
            MouseoverControl(k.Visibility)}
        AB.controls[index]=list
    end
    return list
end

function M:RegisterMovers()
    for index=1,AB.BAR_COUNT do
        if AB.bars[index] then
            local k=AB.KEYS[index]
            S.RegisterOwnedMover("actionbars","bar"..index,{
                label=NS.ActionBarTitles[index],
                getFrame=function() local bar=AB.bars[index];return bar and bar.header end,
                xKey=k.X,yKey=k.Y,pointKey=k.Point,
                point=function() return NS.ActionBarAnchorPoints[S.Config("actionbars")[k.Point]] or "CENTER" end,
                isEnabled=function()
                    return AB.Available(index) and S.Config("actionbars")[k.Visibility]~=6 and (index~=11 or AB.HasForms())
                end,
                order=100+index,
                extraControls=Controls(index),
                historyKeys={k.Buttons,k.Rows,k.Size,k.Spacing,k.Vertical,k.Visibility},
            })
        end
    end
end
