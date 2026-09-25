local _,P=...
local NS,S=P.NS,P.Suite
local C=P.CDM
-- Blizzard's cooldown viewers. Mode 1 turns them off through the reversible
-- CVar. Mode 2 keeps them running at alpha 0, so frames anchored to them
-- (MSUF unit frames, class power, castbars) stay where they are. Nothing
-- here calls a viewer method or writes a viewer field: the only writes are
-- SetAlpha through the context and item mouse (off while mode 2 runs,
-- Blizzard's own state again when it ends).
local N={}
C.Native=N
local M=C.M
local CDM=NS.CDM
local K=C.Const
local Public=S.Public
local CVAR="cooldownViewerEnabled"
-- Lets S.RestoreSaved put the CVar back after a crash or a disable.
M.cvars=M.cvars or {}
M.cvars[CVAR]=true
local VIEWERS={"EssentialCooldownViewer","UtilityCooldownViewer","BuffIconCooldownViewer","BuffBarCooldownViewer"}
-- MSUF resolves only these three names.
local EXPORTED={EssentialCooldownViewer="ess",UtilityCooldownViewer="uti",BuffIconCooldownViewer="buf"}
local PROMOTED="MSUF frames are attached to Blizzard's cooldown bars, so they keep running invisibly."

local hooked={}
local active,guard,applied=false,false,nil

local function ID() return M.id or "cooldownManager" end

local function Viewer(name)
    local frame=_G[name]
    if type(frame)=="table" and not NS.Safety.IsForbidden(frame) then return frame end
end

-- MSUF's "follow Blizzard's cooldown bars" toggle; foreign saved data, so
-- every level is type-checked.
local function Anchored()
    local db=_G.MSUF_DB
    local general=type(db)=="table" and db.general or nil
    return type(general)=="table" and general.anchorToCooldown==true
end

-- An MSUF that knows these bars (MSUF_GetSuiteCooldownAnchor) follows our
-- Essential bar itself, so Blizzard's bars can stay off.
function N.Mode()
    local config=M.config
    local mode=type(config)=="table" and config.blizzard==2 and 2 or 1
    if mode==1 and Anchored() and type(_G.MSUF_GetSuiteCooldownAnchor)~="function" then return 2,S.Text(PROMOTED) end
    return mode
end

------------------------------------------------------------------ hooks (mode 2)
local function AlphaHook(viewer,alpha)
    if not active or guard then return end
    if Public(alpha) and alpha==0 then return end
    guard=true
    viewer:SetAlpha(0)
    guard=false
end
-- Items whose mouse is off, with their viewer (weak keys: released items
-- may go).
local silenced=setmetatable({},{__mode="k"})
local function Mute(viewer,item)
    item:EnableMouse(false)
    silenced[item]=viewer
end
local function AcquireHook(viewer,item)
    if active and type(item)=="table" and not NS.Safety.IsForbidden(item) then Mute(viewer,item) end
end
-- Installed once per viewer; inert whenever mode 2 is not applied.
local function Hook(viewer)
    if hooked[viewer] then return end
    hooked[viewer]=true
    hooksecurefunc(viewer,"SetAlpha",AlphaHook)
    if type(viewer.OnAcquireItemFrame)=="function" then hooksecurefunc(viewer,"OnAcquireItemFrame",AcquireHook) end
end
-- Items acquired before the hook existed: acquired items carry a layout
-- index, Edit Mode's selection frame does not.
local function Silence(viewer,...)
    for i=1,select("#",...) do
        local child=select(i,...)
        if type(child)=="table" and not NS.Safety.IsForbidden(child) then
            local index=child.layoutIndex
            if Public(index) and type(index)=="number" then Mute(viewer,child) end
        end
    end
end
-- Back to the state Blizzard gives its items (clicks off, motion for the
-- viewer's tooltip setting), so its tooltips work without a re-acquire.
local function Unmute()
    for item,viewer in pairs(silenced) do
        silenced[item]=nil
        if not NS.Safety.IsForbidden(item) then
            local tips=viewer.tooltipsShown
            item:SetMouseClickEnabled(false)
            item:SetMouseMotionEnabled(Public(tips) and tips==true)
        end
    end
end

local function RestoreAlpha(ctx)
    active=false
    for i=1,#VIEWERS do
        local viewer=Viewer(VIEWERS[i])
        if viewer then ctx:RestoreProperty(viewer,"SetAlpha") end
    end
    Unmute()
end

------------------------------------------------------------------ takeover
-- Out of combat (Enable/Refresh). Only mode transitions do work.
function N.Apply()
    if NS.IsCombatLocked() then S.Queue(ID()); return end
    local ctx=M.context
    if not ctx then return end
    local mode=N.Mode()
    if mode==applied then return end
    if mode==2 then
        active=true
        for i=1,#VIEWERS do
            local viewer=Viewer(VIEWERS[i])
            if viewer then Hook(viewer); ctx:Alpha(viewer,0) end
        end
        -- Back from mode 1: the viewers return and re-acquire under the hook.
        if applied==1 then S.RestoreCVar(ID(),CVAR) end
        for i=1,#VIEWERS do
            local viewer=Viewer(VIEWERS[i])
            if viewer then Silence(viewer,viewer:GetChildren()) end
        end
    else
        if applied==2 then RestoreAlpha(ctx) end
        ctx:CVar(CVAR,"0")
    end
    applied=mode
end

function N.Release()
    local ctx=M.context
    if applied==2 and ctx then RestoreAlpha(ctx) end
    active=false
    if applied==1 then S.RestoreCVar(ID(),CVAR) end
    applied=nil
end

function N.Applied() return applied end

-- MSUF (without the suite provider) is attached to Blizzard's Essential bar,
-- which runs invisibly: our Essential bar then sits on top of it.
function N.FollowViewer()
    return applied==2 and Anchored() and type(_G.MSUF_GetSuiteCooldownAnchor)~="function"
end

------------------------------------------------------------------ first-run capture
local function Number(value) return Public(value) and type(value)=="number" and value==value end
-- A stand-in view for Layout.Point.
local pointProbe={}

-- Writes the x/y settings that put the Essential bar's center at (cx, cy)
-- (UIParent units from its bottom left) for a w x h bar: x/y place the
-- bar's growth edge relative to the screen center.
local function CaptureOffsets(values,config,cx,cy,w,h,uiW,uiH)
    local keys=CDM.KEYS.ess
    pointProbe.kind=1
    pointProbe.vertical=keys.vertical and config[keys.vertical]==true or false
    pointProbe.grow=keys.grow and config[keys.grow] or nil
    local dx,dy=K.EdgeOffset(C.Layout.Point(pointProbe),w,h)
    values[keys.x]=K.Clamp(keys.x,cx-uiW/2+dx)
    values[keys.y]=K.Clamp(keys.y,cy-uiH/2+dy)
end

-- Center and size of Blizzard's shown Essential bar in UIParent units.
local function Read(viewer,ui)
    local shown=viewer:IsShown()
    if not Public(shown) or shown~=true then return nil end
    local cx,cy=viewer:GetCenter()
    local w,h,scale=viewer:GetWidth(),viewer:GetHeight(),viewer:GetEffectiveScale()
    if not (Number(cx) and Number(cy) and Number(w) and Number(h) and Number(scale)) or scale<=0 then return nil end
    local k=scale/ui
    return cx*k,cy*k,w*k,h*k
end

-- First activation, out of combat, before the CVar is touched: the Essential
-- bar goes where Blizzard's Essential bar was, or with its top edge 222 units
-- below the screen center (under MSUF's default unit frames and castbar).
-- Sizes stay ours. Returns settings plus captured=true for S.SetMany.
function N.Capture()
    if NS.IsCombatLocked() or not UIParent then return nil end
    local ui=UIParent:GetEffectiveScale()
    local uiW,uiH=UIParent:GetWidth(),UIParent:GetHeight()
    if not (Number(ui) and Number(uiW) and Number(uiH)) or ui<=0 then return nil end
    local config=type(M.config)=="table" and M.config or {}
    local values={}
    local viewer=Viewer("EssentialCooldownViewer")
    local cx,cy,w,h
    if viewer then cx,cy,w,h=Read(viewer,ui) end
    if not cx then w,h=1,36; cx,cy=uiW/2,uiH/2-222-h/2 end
    CaptureOffsets(values,config,cx,cy,w,h,uiW,uiH)
    values.captured=true
    return values
end

------------------------------------------------------------------ MSUF anchor export
-- Our bar for one of the three viewer names MSUF stores, while the module
-- is active and the bar is shown; nil otherwise.
function N.AnchorFrame(viewerName)
    local slot=type(viewerName)=="string" and EXPORTED[viewerName]
    if not slot or not M.active then return nil end
    local view,bar=C.views[slot],C.bars[slot]
    if not view or not view.on or not bar or not bar.shown then return nil end
    return bar.anchorFrame
end
