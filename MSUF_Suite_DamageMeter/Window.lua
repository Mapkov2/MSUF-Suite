local _,P=...;local NS,S=P.NS,P.Suite
-- Meter windows: plain (non-secure) UIParent children, so showing, hiding and
-- painting stay legal in combat. Geometry is written to settings out of
-- combat only. Positions are BOTTOMRIGHT offsets against UIParent's
-- BOTTOMRIGHT, the same format MSUF Edit Mode writes.
local D=P.DamageMeter
local M=D.M
local Public=S.Public
local floor,max,min,format=math.floor,math.max,math.min,string.format
local GRIP="Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
local ORDER={"settings","reset","session","type"}
local EDGE={TOP={"TOPLEFT","TOPRIGHT"},BOTTOM={"BOTTOMLEFT","BOTTOMRIGHT"}}

local function HeaderButton(win,kind)
    local button=S.CreateFrame("Button",nil,win.header)
    button.win,button.kind=win,kind
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick",D.HeaderButtonClick)
    button:SetScript("OnEnter",D.HeaderButtonEnter)
    button:SetScript("OnLeave",D.HeaderButtonLeave)
    local icon=S.CreateTexture(button,nil,"ARTWORK")
    button.icon=icon
    if kind=="settings" and D.Atlas(icon,"common-dropdown-a-button-settings-shadowless") then
        button.iconScale=1; icon:SetPoint("CENTER",button,"CENTER",0,0)
    elseif kind=="reset" and D.Atlas(icon,"common-icon-undo") then
        button.iconScale=.8; icon:SetPoint("CENTER",button,"CENTER",0,0)
    elseif kind=="type" then
        -- Three bars of falling length: a small meter glyph from plain textures.
        icon:Hide()
        button.bars={}
        for i=1,3 do button.bars[i]=S.CreateTexture(button,nil,"ARTWORK") end
    else
        icon:Hide()
        button.label=S.CreateFontString(button,nil,"OVERLAY")
        button.label:SetPoint("CENTER",button,"CENTER",0,0)
        if kind=="settings" then button.label:SetText("*") elseif kind=="reset" then button.label:SetText("R") end
    end
    return button
end

function D.EnsureWindow(index)
    local win=D.windows[index]
    if win then return win end
    win={index=index,rows={},maxRow=0,offset=0,count=0,capacity=0,bd={offset=0},dirty=true,buttons={},hover=false}
    D.windows[index]=win
    local frame=S.CreateFrame("Frame",nil,UIParent)
    frame.win,win.frame=win,frame
    frame:Hide()
    frame:SetClampedToScreen(true); frame:SetMovable(true); frame:SetResizable(true)
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    frame:EnableMouse(true)
    frame:SetScript("OnEnter",D.HoverEnter); frame:SetScript("OnLeave",D.HoverLeave)
    frame:SetScript("OnSizeChanged",D.WindowSized)
    win.bg=S.CreateTexture(frame,nil,"BACKGROUND")
    local header=S.CreateFrame("Button",nil,frame)
    header.win,win.header=win,header
    header:SetFrameLevel(frame:GetFrameLevel()+3)
    header:RegisterForDrag("LeftButton"); header:RegisterForClicks("RightButtonUp")
    for script,handler in pairs(D.headerScripts) do header:SetScript(script,handler) end
    win.headerBg=S.CreateTexture(header,nil,"BACKGROUND"); win.headerBg:SetAllPoints(header)
    win.title=S.CreateFontString(header,nil,"OVERLAY"); win.title:SetJustifyH("LEFT"); win.title:SetWordWrap(false)
    win.timer=S.CreateFontString(header,nil,"OVERLAY"); win.timer:SetJustifyH("RIGHT")
    for _,kind in ipairs(ORDER) do win.buttons[kind]=HeaderButton(win,kind) end
    local body=S.CreateFrame("Frame",nil,frame)
    body.win,win.body=win,body
    body:SetFrameLevel(frame:GetFrameLevel()+1)
    body:EnableMouse(true); body:EnableMouseWheel(true)
    for script,handler in pairs(D.bodyScripts) do body:SetScript(script,handler) end
    win.status=S.CreateFontString(body,nil,"OVERLAY")
    win.status:SetPoint("LEFT",body,"LEFT",8,0); win.status:SetPoint("RIGHT",body,"RIGHT",-8,0)
    win.status:SetJustifyH("CENTER")
    -- Border strips live on their own frame above the header and the rows.
    local border=S.CreateFrame("Frame",nil,frame)
    border:SetAllPoints(frame); border:SetFrameLevel(frame:GetFrameLevel()+10)
    win.border,win.edges=border,{}
    for i=1,4 do win.edges[i]=S.CreateTexture(border,nil,"OVERLAY") end
    local grip=S.CreateFrame("Button",nil,frame)
    grip.win,win.grip=win,grip
    grip:SetSize(16,16); grip:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-1,1)
    grip:SetFrameLevel(frame:GetFrameLevel()+12)
    grip:SetNormalTexture(GRIP.."Up"); grip:SetHighlightTexture(GRIP.."Highlight"); grip:SetPushedTexture(GRIP.."Down")
    for script,handler in pairs(D.gripScripts) do grip:SetScript(script,handler) end
    grip:Hide()
    return win
end

-- Runtime session state; historic session IDs are never saved.
function D.ApplySession(win,value,sessionID,duration)
    win.cfgSession,win.sessionID=value,sessionID
    win.pinDuration=sessionID and duration or nil
    win.sessionType=value==2 and D.OVERALL or D.CURRENT
    win.overall=not sessionID and value==2
end
-- Settings are the authority; runtime picks survive a Refresh while the
-- saved value is unchanged.
function D.SyncWindow(win)
    local c,keys=M.config,D.KEYS[win.index]
    local meterType=c[keys.Type]-1
    if meterType~=win.cfgType then
        win.cfgType,win.meterType=meterType,meterType
        D.CloseBreakdown(win,true); win.offset,win.dirty=0,true
    end
    local value=c[keys.Session]
    if value~=win.cfgSession then
        D.ApplySession(win,value,nil,nil)
        D.CloseBreakdown(win,true); win.offset,win.dirty=0,true
    end
end

function D.PlaceWindow(win)
    local keys=D.KEYS[win.index]
    win.frame:ClearAllPoints()
    win.frame:SetPoint("BOTTOMRIGHT",UIParent,"BOTTOMRIGHT",M.config[keys.X],M.config[keys.Y])
end
function D.Capacity(height)
    local style=M.style
    local capacity=floor((height-M.config.headerHeight-2+style.spacing)/(style.barHeight+style.spacing))
    return capacity<0 and 0 or capacity>40 and 40 or capacity
end

function D.StyleHeader(win)
    local c=M.config
    local size=min(c.headerIconSize,c.headerHeight)
    local r,g,b=S.RGB(c.titleColor)
    local previous
    for _,kind in ipairs(ORDER) do
        local button=win.buttons[kind]
        button:ClearAllPoints(); button:SetSize(size,size)
        if previous then button:SetPoint("RIGHT",previous,"LEFT",-2,0) else button:SetPoint("RIGHT",win.header,"RIGHT",-3,0) end
        previous=button
        if button.iconScale then button.icon:SetSize(size*button.iconScale,size*button.iconScale) end
        if button.label then
            D.FontStyle(button.label,max(8,c.headerFontSize-1)); button.label:SetTextColor(r,g,b)
            button.label:ClearAllPoints(); button.label:SetPoint("CENTER",button,"CENTER",0,M.style.baseline)
        end
        if button.bars then
            local width,thick=size*.7,max(1,floor(size/9+.5))
            for i,bar in ipairs(button.bars) do
                bar:ClearAllPoints(); bar:SetSize(width*(1.3-.3*i),thick)
                bar:SetPoint("LEFT",button,"CENTER",-width/2,(2-i)*(thick+2))
                bar:SetColorTexture(r,g,b,1)
            end
        end
    end
    win.firstButton=previous
    D.FontStyle(win.title,c.headerFontSize); win.title:SetTextColor(r,g,b)
    D.FontStyle(win.timer,c.headerFontSize); win.timer:SetTextColor(r,g,b)
    win.title:ClearAllPoints(); win.timer:ClearAllPoints()
    win.timer:SetPoint("RIGHT",previous,"LEFT",-4,M.style.baseline)
    win.title:SetPoint("LEFT",win.header,"LEFT",6,M.style.baseline); win.title:SetPoint("RIGHT",win.timer,"LEFT",-4,0)
end

function D.StyleBorder(win)
    local c,edges,frame=M.config,win.edges,win.border
    local size=c.borderSize
    if size<=0 then for i=1,4 do edges[i]:Hide() end; return end
    local r,g,b=S.RGB(c.borderColor)
    for i=1,4 do edges[i]:ClearAllPoints(); edges[i]:SetColorTexture(r,g,b,1); edges[i]:Show() end
    edges[1]:SetPoint("TOPLEFT",frame,"TOPLEFT",-size,size); edges[1]:SetPoint("TOPRIGHT",frame,"TOPRIGHT",size,size); edges[1]:SetHeight(size)
    edges[2]:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",-size,-size); edges[2]:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",size,-size); edges[2]:SetHeight(size)
    edges[3]:SetPoint("TOPLEFT",frame,"TOPLEFT",-size,0); edges[3]:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",-size,0); edges[3]:SetWidth(size)
    edges[4]:SetPoint("TOPRIGHT",frame,"TOPRIGHT",size,0); edges[4]:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",size,0); edges[4]:SetWidth(size)
end

-- Layout pass: runs when the style generation changed (after Refresh).
function D.StyleWindow(win)
    local c,keys=M.config,D.KEYS[win.index]
    local frame,header,body=win.frame,win.header,win.body
    win.styleGen=M.styleGen
    local height=c[keys.Height]
    frame:SetSize(c[keys.Width],height)
    D.PlaceWindow(win)
    local rules=S.catalog[M.id].rules
    if frame.SetResizeBounds then
        frame:SetResizeBounds(rules[keys.Width].min,rules[keys.Height].min,rules[keys.Width].max,rules[keys.Height].max)
    end
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0); header:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,0)
    header:SetHeight(c.headerHeight)
    local r,g,b=S.RGB(c.headerColor)
    win.headerBg:SetColorTexture(r,g,b,c.headerAlpha/100)
    r,g,b=S.RGB(c.bgColor)
    win.bg:ClearAllPoints(); win.bg:SetPoint("TOPLEFT",header,"BOTTOMLEFT",0,0); win.bg:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",0,0)
    win.bg:SetColorTexture(r,g,b,c.bgAlpha/100)
    body:ClearAllPoints(); body:SetPoint("TOPLEFT",header,"BOTTOMLEFT",1,-1); body:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-1,1)
    D.StyleHeader(win)
    D.StyleBorder(win)
    D.FontStyle(win.status,M.style.leftSize); win.status:SetTextColor(.8,.8,.8)
    win.status:ClearAllPoints()
    win.status:SetPoint("LEFT",body,"LEFT",8,M.style.baseline)
    win.status:SetPoint("RIGHT",body,"RIGHT",-8,M.style.baseline)
    win.capacity=D.Capacity(height)
    for slot,row in pairs(win.rows) do D.AnchorRow(row,body,slot) end
    -- Keep the current fade state through a style refresh. Resetting it would
    -- make ApplyHover fetch and paint once before Refresh's batched paint.
    win.titleText,win.statusText,win.timerSecond,win.buttonAlpha=nil,nil,false,nil
    D.UpdateTitle(win)
    D.ApplyHover(win)
end

function D.UpdateTitle(win)
    local text=D.TypeName(win.meterType)
    if win.overall then text=format("%s (%s)",text,D.Text("DAMAGE_METER_OVERALL_SESSION","Overall")) end
    if text~=win.titleText then win.titleText=text; win.title:SetText(text) end
    local label=win.buttons.session.label
    if win.sessionID then label:SetText("#")
    elseif win.overall then label:SetText(D.Text("DAMAGE_METER_OVERALL_SESSION_SHORT","O"))
    else label:SetText(D.Text("DAMAGE_METER_CURRENT_SESSION_SHORT","C")) end
end
-- Memoized per displayed second; nil clears the timer.
function D.SetTimerText(win,seconds)
    if seconds then seconds=floor(seconds) end
    if seconds==win.timerSecond then return end
    win.timerSecond=seconds
    win.timer:SetText(seconds and seconds>0 and format("(%s)",D.Clock(seconds)) or "")
end

function D.SetShown(win,show)
    if show then
        if win.styleGen~=M.styleGen then D.StyleWindow(win) end
        if not win.shown then win.shown,win.dirty=true,true; win.frame:Show() end
        D.ApplyHover(win)
    elseif win.shown then
        win.shown,win.hover=false,false
        if D.typePanel and D.typePanel.win==win then D.HideTypeMenu() end
        D.CloseBreakdown(win,true)
        D.HideTip()
        win.frame:Hide()
    end
end

function D.LocalIndex(sources,count)
    for i=1,count do
        local flag=sources[i].isLocalPlayer
        if Public(flag) and flag==true then return i end
    end
    return 0
end
-- showPlayer can pin the own row into the first or last slot; one extra
-- scroll step keeps the list end reachable while that pin is active.
function D.MaxOffset(win,count)
    local extra=(M.style.showPlayer and count>win.capacity and win.capacity>1) and 1 or 0
    return max(0,count-win.capacity+extra)
end
local function Separator(row,edge)
    local line=row.separator
    if not edge then if line then line:Hide() end; return end
    if not line then line=S.CreateTexture(row,nil,"OVERLAY"); line:SetColorTexture(1,1,1,.35); line:SetHeight(1); row.separator=line end
    if row.separatorEdge~=edge then
        row.separatorEdge=edge
        line:ClearAllPoints()
        line:SetPoint(EDGE[edge][1],row,EDGE[edge][1],0,0); line:SetPoint(EDGE[edge][2],row,EDGE[edge][2],0,0)
    end
    line:Show()
end

function D.UpdateStatus(win,count)
    local text=""
    if not M.available and not M.preview then text=M.reason or ""
    elseif count==0 and win.meterType==D.AVOIDABLE then
        local notice=_G.DAMAGE_METER_AVOIDABLE_DAMAGE_NOT_ACTIVE
        text=type(notice)=="string" and notice or ""
    end
    if text~=win.statusText then win.statusText=text; win.status:SetText(text) end
end

-- Content pass over the visible slots only; uses the cached session, so
-- scrolling and resizing never refetch.
function D.Render(win)
    local session=win.session
    local sources=session and session.combatSources
    local count=D.Count(sources)
    local capacity=win.capacity
    win.count=count
    local offset=min(win.offset,D.MaxOffset(win,count))
    win.offset=offset
    local pinSlot,pinIndex=0,0
    if M.style.showPlayer and count>capacity and capacity>1 then
        local own=D.LocalIndex(sources,count)
        if own>0 and own<=offset then pinSlot,pinIndex=1,own
        elseif own>offset+capacity then pinSlot,pinIndex=capacity,own end
    end
    local rows=win.rows
    for slot=1,capacity do
        local index=offset+slot
        if slot==pinSlot then index=pinIndex elseif pinSlot==1 then index=offset+slot-1 end
        local row=rows[slot]
        if index>=1 and index<=count then
            if not row then
                row=D.CreateRow(win.body,win,"list")
                rows[slot]=row
                if slot>win.maxRow then win.maxRow=slot end
                D.AnchorRow(row,win.body,slot)
            end
            row.index=index
            D.PaintSource(row,sources[index],index,session,win)
            Separator(row,slot==pinSlot and (slot==1 and "BOTTOM" or "TOP") or nil)
            row:Show()
        elseif row then
            row.index=nil; row:Hide()
        end
    end
    for slot=capacity+1,win.maxRow do
        local row=rows[slot]
        if row then row.index=nil; row:Hide() end
    end
    D.UpdateStatus(win,count)
end

function D.Paint(win,session,reuseSession)
    win.dirty=false
    if win.bd.open then D.RefreshBreakdown(win); return end
    if reuseSession then win.session=session else win.session=D.FetchSession(win) end
    D.Render(win)
end

function D.Scroll(win,delta)
    if not Public(delta) or type(delta)~="number" or delta==0 then return end
    local offset=min(D.MaxOffset(win,win.count),max(0,win.offset+(delta>0 and -2 or 2)))
    if offset~=win.offset then
        win.offset=offset
        D.HideTip()
        D.Render(win)
    end
end

-- Hover state drives Mouseover visibility, header buttons on mouseover and
-- the resize grip. OnEnter/OnLeave plus IsMouseOver on leave; no polling.
function D.HoverEnter(region)
    local win=region.win
    if win.hover then return end
    win.hover=true
    D.ApplyHover(win)
end
function D.HoverLeave(region)
    local win=region.win
    if not win.hover or win.frame:IsMouseOver() then return end
    win.hover=false
    D.ApplyHover(win)
end
function D.ApplyHover(win)
    local c=M.config
    local fade=c.visibility==4 and not M.forced and not win.hover
    if fade~=win.faded then
        win.faded=fade
        win.frame:SetAlpha(fade and 0 or 1)
        -- Faded windows skip painting; catch up once they are revealed.
        if not fade and win.shown and win.dirty then D.Paint(win) end
        if not fade and win.shown then D.UpdateTimers() end
        if fade and not D.HasDirtyVisible() then D.CancelPaint() end
        D.SyncClock()
    end
    local alpha=(c.headerMouseover and not win.hover and not M.forced) and 0 or 1
    if alpha~=win.buttonAlpha then
        win.buttonAlpha=alpha
        for _,button in pairs(win.buttons) do button:SetAlpha(alpha) end
    end
    win.grip:SetShown(win.hover and D.CanMove(win))
end

-- Edit Mode and the preview unlock every window for placement.
function D.CanMove(win)
    return not M.inCombat and not NS.IsCombatLocked() and (M.forced or not M.config[D.KEYS[win.index].Locked])
end
local function Round(value) return floor(value+.5) end
function D.SaveGeometry(win,sized)
    local frame,keys=win.frame,D.KEYS[win.index]
    local right,bottom,parentRight,parentBottom=frame:GetRight(),frame:GetBottom(),UIParent:GetRight(),UIParent:GetBottom()
    if not (D.Plain(right) and D.Plain(bottom) and D.Plain(parentRight) and D.Plain(parentBottom)) then D.PlaceWindow(win); return end
    local values={[keys.X]=Round(right-parentRight),[keys.Y]=Round(bottom-parentBottom)}
    if sized then
        local width,height=frame:GetWidth(),frame:GetHeight()
        if D.Plain(width) and D.Plain(height) then values[keys.Width],values[keys.Height]=Round(width),Round(height) end
    end
    if not S.SetMany(M.id,values) then D.PlaceWindow(win) end
end
function D.DragStart(header)
    local win=header.win
    if not D.CanMove(win) then return end
    win.moving=true
    D.HideTip()
    win.frame:StartMoving()
end
function D.DragStop(header)
    local win=header.win
    if not win.moving then return end
    win.moving=false
    win.frame:StopMovingOrSizing()
    D.SaveGeometry(win,false)
end
function D.GripDown(grip,button)
    local win=grip.win
    if button~="LeftButton" or not D.CanMove(win) then return end
    win.sizing=true
    D.HideTip()
    win.frame:StartSizing("BOTTOMRIGHT")
end
function D.GripUp(grip)
    local win=grip.win
    if not win.sizing then return end
    win.sizing=false
    win.frame:StopMovingOrSizing()
    D.SaveGeometry(win,true)
end
-- Live resizing: recompute how many rows fit and repaint from the cache.
function D.WindowSized(frame,_,height)
    local win=frame.win
    if win.styleGen~=M.styleGen or not D.Plain(height) then return end
    local capacity=D.Capacity(height)
    if capacity==win.capacity then return end
    win.capacity=capacity
    if not win.shown then return end
    if win.bd.open then D.RenderBreakdown(win) else D.Render(win) end
end

function D.HeaderClick(header,button) if button=="RightButton" then D.OpenTypeMenu(header.win,header) end end
function D.BodyWheel(body,delta) D.Scroll(body.win,delta) end
function D.BodyMouseUp(body,button) if button=="RightButton" then D.OpenTypeMenu(body.win,body) end end
D.headerScripts={OnDragStart=D.DragStart,OnDragStop=D.DragStop,OnClick=D.HeaderClick,OnEnter=D.HoverEnter,OnLeave=D.HoverLeave}
D.bodyScripts={OnMouseWheel=D.BodyWheel,OnMouseUp=D.BodyMouseUp,OnEnter=D.HoverEnter,OnLeave=D.HoverLeave}
D.gripScripts={OnMouseDown=D.GripDown,OnMouseUp=D.GripUp,OnEnter=D.HoverEnter,OnLeave=D.HoverLeave}
