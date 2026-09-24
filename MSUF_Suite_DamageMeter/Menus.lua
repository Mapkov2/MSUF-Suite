local _,P=...;local NS,S=P.NS,P.Suite
-- Fight and settings menus use Blizzard's MenuUtil. The meter type picker is
-- one reusable Suite frame with direct choices below three category headings.
-- Meter and fight picks apply at once, also in combat; the
-- matching settings are written out of combat. Window-level settings (lock,
-- hides, new/close window) are writes only and stay disabled in combat.
local D=P.DamageMeter
local M=D.M
local Public=S.Public
local format,max,min=string.format,math.max,math.min
local HIDES={"HideDungeon","HideRaid","HidePvP","HideWorld"}
-- Blizzard's grouping of meter types; Absorbs joins the healing group.
local GROUPS={
    {"DAMAGE_METER_CATEGORY_DAMAGE","Damage",{0,1,7,8,10}},
    {"DAMAGE_METER_CATEGORY_HEALING","Healing",{2,3,4}},
    {"DAMAGE_METER_CATEGORY_ACTIONS","Actions",{5,6,9}},
}
local function MenuAPI()
    local util=_G.MenuUtil
    if type(util)=="table" and type(util.CreateContextMenu)=="function" then return util end
end
-- Menu entry data per window, created once.
local function Choices(win)
    local data=win.menuData
    if data then return data end
    data={current={win=win,value=1},overall={win=win,value=2},keys={}}
    data.keys.Locked={win=win,suffix="Locked"}
    for _,suffix in ipairs(HIDES) do data.keys[suffix]={win=win,suffix=suffix} end
    win.menuData=data
    return data
end

function D.Persist(key,value)
    if M.inCombat or NS.IsCombatLocked() then
        M.pendingWrites=M.pendingWrites or {}
        M.pendingWrites[key]=value
        return
    end
    S.Set(M.id,key,value)
end
-- Returns true when saved picks were applied (the controller then refreshed).
function D.FlushWrites()
    local writes=M.pendingWrites
    if not writes or NS.IsCombatLocked() then return false end
    M.pendingWrites=nil
    return S.SetMany(M.id,writes)==true
end

local function Changed(win)
    D.CloseBreakdown(win,true)
    win.offset,win.timerSecond,win.dirty=0,false,true
    D.UpdateTitle(win)
    if win.shown then D.Paint(win); D.UpdateTimers() end
end
function D.SetWindowType(win,meterType)
    if win.meterType==meterType then return end
    win.meterType,win.cfgType=meterType,meterType
    Changed(win)
    D.Persist(D.KEYS[win.index].Type,meterType+1)
end
-- value 1 Current, 2 Overall; a historic sessionID pins the window and keeps
-- Current as the saved fallback.
function D.SetWindowSession(win,value,sessionID,duration)
    D.ApplySession(win,value,sessionID,duration)
    Changed(win)
    D.Persist(D.KEYS[win.index].Session,value)
end

local TYPE_WIDTH,TYPE_PAD,TYPE_GAP,TYPE_ROW,TYPE_HEADING=376,10,6,24,20
local TYPE_TILE=(TYPE_WIDTH-TYPE_PAD*2-TYPE_GAP)/2
local function MixColor(first,second,amount)
    return {first[1]+(second[1]-first[1])*amount,
        first[2]+(second[2]-first[2])*amount,
        first[3]+(second[3]-first[3])*amount,1}
end
local function TypePalette()
    local c=M.config
    local br,bg,bb=S.RGB(c.bgColor)
    local hr,hg,hb=S.RGB(c.headerColor)
    local rr,rg,rb=S.RGB(c.borderColor)
    local tr,tg,tb=S.RGB(c.titleColor)
    local ar,ag,ab=S.RGB(c.barColor)
    local background,header,text={br,bg,bb},{hr,hg,hb},{tr,tg,tb}
    local border={rr,rg,rb}
    local accent
    if c.borderColor=="9f8960" and c.barColor=="d8b66a" then
        accent=border
    elseif NS.Client and NS.Client.isForever and c.barColor=="598ccc" then
        accent={.95,.74,.36}
    else
        accent={ar,ag,ab}
    end
    if rr+rg+rb<.24 then border=MixColor(background,text,.28) end
    local idle=MixColor(background,header,.8)
    return {accent=accent,text=text,border=border,
        panel={br,bg,bb,max(.94,c.bgAlpha/100)},
        idle=idle,hover=MixColor(idle,accent,.14),selected=MixColor(idle,accent,.30)}
end
local function TypeTileStyle(button,palette,selected,hovered)
    local color=selected and palette.selected or hovered and palette.hover or palette.idle
    button.bg:SetColorTexture(unpack(color))
    button.accent:SetColorTexture(palette.accent[1],palette.accent[2],palette.accent[3],selected and 1 or hovered and .85 or .48)
    local text=palette.text
    local opacity=selected and 1 or .9
    button.label:SetTextColor(text[1]*opacity,text[2]*opacity,text[3]*opacity)
end
function D.HideTypeMenu()
    local panel=D.typePanel
    if not panel then return end
    panel:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    panel:Hide()
    panel.win,panel.owner=nil,nil
end
local function TypePicked(button)
    local panel=button:GetParent()
    local win=panel.win
    D.HideTypeMenu()
    if win then D.SetWindowType(win,button.meterType) end
end
local function TypeEntered(button)
    local panel=button:GetParent()
    if not panel.win then return end
    TypeTileStyle(button,panel.palette,panel.win.meterType==button.meterType,true)
end
local function TypeLeft(button)
    local panel=button:GetParent()
    if not panel.win then return end
    TypeTileStyle(button,panel.palette,panel.win.meterType==button.meterType,false)
end
local function TypeOutside(panel,event)
    if event=="GLOBAL_MOUSE_DOWN" and not panel:IsMouseOver() then
        D.HideTypeMenu()
    end
end
local function TypeFontString(parent)
    local fontString=S.CreateFontString(parent,nil,"OVERLAY")
    -- A new FontString has no font: SetText before SetFont raises in WoW.
    -- OpenTypeMenu applies the configured meter font after panel creation.
    S.SetFont(fontString,nil,11,"")
    return fontString
end
local function EnsureTypePanel()
    local panel=D.typePanel
    if panel then return panel end
    panel=S.CreateFrame("Frame",nil,UIParent)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetScript("OnEvent",TypeOutside)
    panel:SetScript("OnHide",function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    panel.buttons,panel.headings={},{}
    panel.bg=S.CreateTexture(panel,nil,"BACKGROUND")
    panel.bg:SetAllPoints(panel)
    panel.bg:SetColorTexture(.055,.062,.067,.97)
    local top=S.CreateTexture(panel,nil,"BORDER")
    top:SetPoint("TOPLEFT",panel,"TOPLEFT",0,0)
    top:SetPoint("TOPRIGHT",panel,"TOPRIGHT",0,0)
    top:SetHeight(1); top:SetColorTexture(.34,.36,.37,1)
    local bottom=S.CreateTexture(panel,nil,"BORDER")
    bottom:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",0,0)
    bottom:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",0,0)
    bottom:SetHeight(1); bottom:SetColorTexture(.25,.28,.29,1)
    local left=S.CreateTexture(panel,nil,"BORDER")
    left:SetPoint("TOPLEFT",panel,"TOPLEFT",0,0)
    left:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",0,0)
    left:SetWidth(1); left:SetColorTexture(.25,.28,.29,1)
    local right=S.CreateTexture(panel,nil,"BORDER")
    right:SetPoint("TOPRIGHT",panel,"TOPRIGHT",0,0)
    right:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",0,0)
    right:SetWidth(1); right:SetColorTexture(.25,.28,.29,1)
    panel.edges={top,bottom,left,right}
    local y=-TYPE_PAD
    for groupIndex,group in ipairs(GROUPS) do
        local heading=TypeFontString(panel)
        heading:SetPoint("TOPLEFT",panel,"TOPLEFT",TYPE_PAD,y)
        heading:SetText(D.Text(group[1],group[2]))
        heading:SetJustifyH("LEFT")
        panel.headings[groupIndex]=heading
        y=y-TYPE_HEADING
        for index,meterType in ipairs(group[3]) do
            local button=S.CreateFrame("Button",nil,panel)
            button.meterType=meterType
            button:RegisterForClicks("LeftButtonUp")
            button:SetSize(TYPE_TILE,TYPE_ROW)
            button:SetPoint("TOPLEFT",panel,"TOPLEFT",TYPE_PAD+((index-1)%2)*(TYPE_TILE+TYPE_GAP),y-math.floor((index-1)/2)*(TYPE_ROW+TYPE_GAP))
            button.bg=S.CreateTexture(button,nil,"BACKGROUND");button.bg:SetAllPoints(button)
            button.accent=S.CreateTexture(button,nil,"ARTWORK")
            button.accent:SetPoint("TOPLEFT",button,"TOPLEFT",0,0)
            button.accent:SetPoint("BOTTOMLEFT",button,"BOTTOMLEFT",0,0)
            button.accent:SetWidth(2)
            button.label=TypeFontString(button)
            button.label:SetPoint("LEFT",button,"LEFT",9,0)
            button.label:SetPoint("RIGHT",button,"RIGHT",-14,0)
            button.label:SetJustifyH("LEFT")
            button.label:SetWordWrap(false)
            button.label:SetText(D.TypeName(meterType))
            button.arrow=TypeFontString(button)
            button.arrow:SetPoint("RIGHT",button,"RIGHT",-5,0)
            button.arrow:SetText(">")
            button:SetScript("OnClick",TypePicked)
            button:SetScript("OnEnter",TypeEntered)
            button:SetScript("OnLeave",TypeLeft)
            panel.buttons[meterType]=button
        end
        y=y-math.ceil(#group[3]/2)*(TYPE_ROW+TYPE_GAP)-5
    end
    panel:SetSize(TYPE_WIDTH,-y+TYPE_PAD-5)
    panel:Hide()
    D.typePanel=panel
    return panel
end
function D.OpenTypeMenu(win,owner)
    local panel=EnsureTypePanel()
    if panel:IsShown() and panel.win==win and panel.owner==owner then D.HideTypeMenu(); return end
    panel.win,panel.owner=win,owner
    panel.palette=TypePalette()
    panel.bg:SetColorTexture(unpack(panel.palette.panel))
    for _,edge in ipairs(panel.edges) do edge:SetColorTexture(unpack(panel.palette.border)) end
    if panel.styleGen~=M.styleGen then
        panel.styleGen=M.styleGen
        for _,heading in ipairs(panel.headings) do D.FontStyle(heading,11) end
        for _,button in pairs(panel.buttons) do D.FontStyle(button.label,11); D.FontStyle(button.arrow,11) end
    end
    for _,heading in ipairs(panel.headings) do heading:SetTextColor(unpack(panel.palette.accent)) end
    for meterType,button in pairs(panel.buttons) do
        TypeTileStyle(button,panel.palette,win.meterType==meterType,false)
        button.arrow:SetTextColor(unpack(panel.palette.accent))
    end
    panel:ClearAllPoints()
    local cursor=_G.GetCursorPosition
    if type(cursor)=="function" then
        local x,y=cursor()
        local scale=panel:GetEffectiveScale()
        local width,height=UIParent:GetWidth(),UIParent:GetHeight()
        panel:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",max(8,min(x/scale,width-panel:GetWidth()-8)),max(8,min(y/scale,height-panel:GetHeight()-8)))
    else
        panel:SetPoint("BOTTOMLEFT",owner or UIParent,"TOPLEFT",0,4)
    end
    panel:RegisterEvent("GLOBAL_MOUSE_DOWN")
    panel:Show()
end

local function SessionSelected(data) return not data.win.sessionID and data.win.cfgSession==data.value end
local function SessionChosen(data) D.SetWindowSession(data.win,data.value,nil,nil) end
local function PinSelected(data) return data.win.sessionID==data.id end
local function PinChosen(data) D.SetWindowSession(data.win,1,data.id,data.duration) end
-- The 20 most recent tracked fights (the list is oldest first), then Current and Overall.
local function SessionMenu(_,root,win)
    local api=D.API()
    local list=api and type(api.GetAvailableCombatSessions)=="function" and api.GetAvailableCombatSessions()
    local count=D.Count(list)
    if count>0 then
        for i=max(1,count-19),count do
            local entry=list[i]
            local id=type(entry)=="table" and entry.sessionID
            if D.Plain(id) then
                local name,duration=entry.name,entry.durationSeconds
                if not Public(name) or type(name)~="string" or name=="" then name=format(D.Text("DAMAGE_METER_COMBAT_NUMBER","Fight %d"),id) end
                if D.Plain(duration) and duration>0 then name=format("%s [%s]",name,D.Clock(duration)) else duration=nil end
                root:CreateRadio(name,PinSelected,PinChosen,{win=win,id=id,duration=duration})
            end
        end
        root:CreateDivider()
    end
    local data=Choices(win)
    root:CreateRadio(D.Text("DAMAGE_METER_CURRENT_SESSION","Current fight"),SessionSelected,SessionChosen,data.current)
    root:CreateRadio(D.Text("DAMAGE_METER_OVERALL_SESSION","Overall"),SessionSelected,SessionChosen,data.overall)
end

-- Every per-window key of the catalog (window 1 section) moves on close.
function D.WindowSuffixes()
    local list=D.suffixes
    if list then return list end
    list={}
    for _,rule in ipairs(S.catalog[M.id].controls) do
        if rule.window==1 then list[#list+1]=rule.key:sub(3) end
    end
    D.suffixes=list
    return list
end
-- Closing window N shifts the settings of windows N+1.. down one slot, resets
-- the freed last slot to defaults and moves the runtime objects with them.
function D.CloseWindow(win)
    local c=M.config
    local count,index=c.windowCount,win.index
    if index<2 or index>count or M.inCombat or NS.IsCombatLocked() then return false end
    local rules,values=S.catalog[M.id].rules,{windowCount=count-1}
    for slot=index,count do
        local to,from=D.KEYS[slot],"w"..(slot+1)
        for _,suffix in ipairs(D.WindowSuffixes()) do
            local key=to[suffix] or "w"..slot..suffix
            if slot<count then values[key]=c[from..suffix] else values[key]=rules[key].default end
        end
    end
    local list=D.windows
    if D.typePanel and D.typePanel.win==win then D.HideTypeMenu() end
    D.CloseBreakdown(win,true)
    D.HideTip()
    for slot=index,count-1 do
        local moved=list[slot+1]
        list[slot]=moved
        if moved then moved.index=slot end
    end
    list[count],win.index=win,count
    win.cfgType,win.cfgSession,win.sessionID,win.shown,win.hover=nil,nil,nil,false,false
    win.frame:Hide()
    return S.SetMany(M.id,values)
end

local function KeyChecked(data) return M.config[D.KEYS[data.win.index][data.suffix]]==true end
local function KeyToggled(data)
    local key=D.KEYS[data.win.index][data.suffix]
    if not NS.IsCombatLocked() then S.Set(M.id,key,not M.config[key]) end
end
local function NewWindow()
    local count=M.config.windowCount
    if count<D.MAX and not NS.IsCombatLocked() then S.Set(M.id,"windowCount",count+1) end
end
local function CloseChosen(win) D.CloseWindow(win) end
local function OpenOptions() S.Open(M.id) end
local function SettingsMenu(_,root,win)
    local c,data,rules,keys=M.config,Choices(win),S.catalog[M.id].rules,D.KEYS[win.index]
    local locked=M.inCombat or NS.IsCombatLocked()
    local item=root:CreateCheckbox(D.Text("DAMAGE_METER_LOCK_WINDOW",rules[keys.Locked].label),KeyChecked,KeyToggled,data.keys.Locked)
    if locked then item:SetEnabled(false) end
    root:CreateDivider()
    for _,suffix in ipairs(HIDES) do
        item=root:CreateCheckbox(S.Text(rules[keys[suffix]].label),KeyChecked,KeyToggled,data.keys[suffix])
        if locked then item:SetEnabled(false) end
    end
    root:CreateDivider()
    if win.index==1 then
        item=root:CreateButton(D.Text("DAMAGE_METER_SHOW_NEW_WINDOW","New window"),NewWindow)
        if locked or c.windowCount>=D.MAX then item:SetEnabled(false) end
    else
        item=root:CreateButton(D.Text("DAMAGE_METER_HIDE_WINDOW","Close window"),CloseChosen,win)
        if locked or c[keys.Locked] then item:SetEnabled(false) end
    end
    item=root:CreateButton(S.Text("Open settings"),OpenOptions)
    if locked then item:SetEnabled(false) end
end

local function ResetNow()
    local api=D.API()
    if api and type(api.ResetAllCombatSessions)=="function" then api.ResetAllCombatSessions() end
end
-- Resets every tracked fight. Confirms first unless skipConfirm or the
-- confirmReset setting is off. The popup is added as one new field of
-- StaticPopupDialogs; the table itself is never replaced.
function S.DamageMeterReset(skipConfirm)
    local api=D.API()
    if not api or type(api.ResetAllCombatSessions)~="function" then return false end
    local config=M.config or S.Config("damageMeter")
    local dialogs,show=_G.StaticPopupDialogs,_G.StaticPopup_Show
    if skipConfirm or not config.confirmReset or type(dialogs)~="table" or type(show)~="function" then
        ResetNow()
        return true
    end
    if not dialogs.MSUF_SUITE_DAMAGE_METER_RESET then
        dialogs.MSUF_SUITE_DAMAGE_METER_RESET={
            text=format("%s?",D.Text("DAMAGE_METER_RESET_ALL_SESSIONS","Reset all sessions")),
            button1=type(_G.YES)=="string" and _G.YES or S.Text("Yes"),
            button2=type(_G.NO)=="string" and _G.NO or S.Text("No"),
            OnAccept=ResetNow,timeout=0,whileDead=1,hideOnEscape=1,preferredIndex=3,
        }
    end
    show("MSUF_SUITE_DAMAGE_METER_RESET")
    return true
end

local menus={session=SessionMenu,settings=SettingsMenu}
function D.HeaderButtonClick(button)
    local win,kind=button.win,button.kind
    if kind=="reset" then S.DamageMeterReset(false); return end
    if kind=="type" then D.OpenTypeMenu(win,button); return end
    local util=MenuAPI()
    if util then util.CreateContextMenu(button,menus[kind],win) end
end
local function ButtonLabel(kind)
    local rules=S.catalog[M.id].rules
    if kind=="type" then return S.Text(rules.w1Type.label) end
    if kind=="session" then return S.Text(rules.w1Session.label) end
    if kind=="reset" then return D.Text("DAMAGE_METER_RESET_ALL_SESSIONS","Reset all sessions") end
    return S.Text("Window settings")
end
function D.HeaderButtonEnter(button)
    D.HoverEnter(button)
    local tooltip=_G.GameTooltip
    if not tooltip then return end
    tooltip:SetOwner(button,"ANCHOR_TOP")
    tooltip:SetText(ButtonLabel(button.kind))
    tooltip:Show()
end
function D.HeaderButtonLeave(button)
    local tooltip=_G.GameTooltip
    if tooltip and tooltip:GetOwner()==button then tooltip:Hide() end
    D.HoverLeave(button)
end
