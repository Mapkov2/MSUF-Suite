-- Exercise the NPC owner's normal path with no catalog entry or recursive paint.
local root = assert(arg[1], "Suite root required")
local sourceFile = assert(io.open(root .. "/tools/tests/suite_skin_generic_windows_contract.lua", "rb"))
local source = sourceFile:read("*a")
sourceFile:close()
local stop = assert(source:find("local rowChild = Frame(nil)", 1, true))
local body = [======[
local function LoadAdapter(name, optional)
    local path = skin .. "Adapters/" .. name .. ".lua"
    local function Exists(p)
        local f = io.open(p, "rb")
        if f then f:close(); return true end
    end
    if arg[2] then
        local staged = arg[2] .. "/" .. name .. ".lua"
        if Exists(staged) then path = staged end
    end
    if not optional or Exists(path) then assert(loadfile(path))("MSUF_Suite_Skin", NS) end
end

local jobs, hookCounts = {}, {}
local function Drain()
    for _ = 1, 5 do
        if #jobs == 0 then break end
        local batch = jobs
        jobs = {}
        for _, action in ipairs(batch) do action() end
    end
    assert(#jobs == 0, "quest presentation kept scheduling work without input")
    assert(#reported == 0, table.concat(reported, "\n"))
end
NS.Registry.QueueJob = function(cb) jobs[#jobs+1] = cb end
C_Timer = { After = function(delay, cb)
    assert(delay == 0, "unexpected polling timer")
    jobs[#jobs+1] = cb
end, NewTimer = function(delay, cb)
    -- QuestText has one existing post-fade check on Forever.
    assert(delay == 0.70)
    local timer = { Cancel = function(self) self.cancelled = true end }
    jobs[#jobs+1] = function() if not timer.cancelled then cb() end end
    return timer
end }
local methodsHook = hooksecurefunc
function hooksecurefunc(target, method, callback)
    if type(target) == "table" then
        hookCounts[target] = hookCounts[target] or {}
        local counts = hookCounts[target]
        counts[method] = (counts[method] or 0) + 1
    end
    return methodsHook(target, method, callback)
end
local function Node(name, parent, kind)
    local n = { name=name, parent=parent, shown=true, alpha=1, kind=kind or "Frame",
        hooks={}, scripts={}, created={}, points={}, changes=0, textures=0 }
    function n:GetName() return self.name end
    function n:GetParent() return self.parent end
    function n:GetObjectType() return self.kind end
    function n:IsObjectType(t) return self.kind == t end
    function n:IsShown() return self.shown end
    function n:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function n:GetAlpha() return self.alpha end
    function n:SetAlpha(a) self.alpha = a; self.changes = self.changes + 1 end
    function n:IsProtected() return false, false end
    function n:IsForbidden() return false end
    function n:GetWidth() return self.width or 338 end
    function n:GetHeight() return self.height or 496 end
    function n:HookScript(key, cb)
        assert(key ~= "OnUpdate", "per-frame quest skin installed")
        self.hooks[key] = self.hooks[key] or {}
        self.hooks[key][#self.hooks[key]+1] = cb
    end
    function n:SetScript(key, cb)
        assert(key ~= "OnUpdate", "per-frame quest skin installed")
        self.scripts[key] = cb
    end
    function n:GetScript(key) return self.scripts[key] end
    function n:Fire(key, ...)
        if self.scripts[key] then self.scripts[key](self, ...) end
        for _, cb in ipairs(self.hooks[key] or {}) do cb(self, ...) end
    end
    function n:Show() if not self.shown then self.shown=true; self:Fire("OnShow") end end
    function n:Hide() if self.shown then self.shown=false; self:Fire("OnHide") end end
    function n:SetShown(v) if v then self:Show() else self:Hide() end end
    function n:GetPoint(i) return unpack(self.points[i] or {}) end
    function n:SetPoint(...) self.points[#self.points+1] = {...} end
    function n:ClearAllPoints() self.points={} end
    function n:SetAllPoints(target) self.allPoints=target or self.parent end
    function n:SetDrawLayer(layer, level) self.layer, self.level=layer,level end
    function n:GetDrawLayer() return self.layer,self.level end
    function n:SetHeight(h) self.height=h end
    function n:SetWidth(w) self.width=w end
    function n:SetSize(w,h) self.width,self.height=w,h end
    function n:SetColorTexture(...) self.rgba={...} end
    function n:SetVertexColor(...) self.tint={...} end
    function n:GetVertexColor() return unpack(self.tint or {1,1,1,1}) end
    function n:CreateTexture(_, layer, _, level)
        local region = Node(nil, self, "Texture")
        region.layer, region.level = layer, level
        self.created[#self.created+1] = region
        return region
    end
    return n
end
local function Art(n, field)
    n[field] = Node(nil,n,"Texture")
    return n[field]
end
local function Global(name, parent, kind)
    local n = Node(name, parent, kind)
    _G[name] = n
    return n
end
local function Label(parent, text)
    local n = Node(nil,parent,"FontString")
    n.text, n.rgba = text, {0.3,0.2,0.1,1}
    function n:GetText() return self.text end
    function n:GetTextColor() return unpack(self.rgba) end
    function n:SetTextColor(...) self.rgba={...} end
    return n
end
local function HasPaint(target, layer)
    for _, region in ipairs(target.created) do
        if region:IsVisible() and region.layer == layer and region.rgba and region.rgba[4] > 0
            and (region.allPoints or next(region.points)) then return true end
    end
end
local surfaces, controls = {}, {}
NS.Registry.GetSurface = function(target) return surfaces[target] end
NS.Surface.Attach = function(target, spec)
    local s = surfaces[target] or { fill=Node(nil,target,"Texture"), edge=Node(nil,target,"Texture") }
    surfaces[target], s.spec, s.target = s, spec, target
    s.fill:Show(); s.edge:Show()
    return s
end
NS.Surface.Ensure = NS.Surface.Attach
NS.Surface.SetVisible = function(target, visible)
    local s = surfaces[target]
    if s then s.visible=visible; s.fill:SetShown(visible); s.edge:SetShown(visible) end
end
local function Control(control, owner)
    controls[control] = owner
    return {}
end
NS.ControlSkin.ApplyThreeSliceButton, NS.ControlSkin.ApplyButton = Control, Control
NS.ScrollBarSkin.Apply = Control
NS.ControlSkin.GetOwner = function(target) return controls[target] end
NS.ControlSkin.Refresh = function(target) return controls[target] ~= nil end
NS.ScrollBarSkin.GetState = function(target)
    return controls[target] and { owner=controls[target] }
end
NS.ScrollBarSkin.Refresh = NS.ControlSkin.Refresh
NS.IconSkin.Apply = function(button, owner, spec)
    assert(spec.icon == button.Icon and spec.nativeBorder == button.IconBorder)
    controls[button] = owner
    return {}
end
local function ReleaseControls(owner)
    for target, who in pairs(controls) do if who==owner then controls[target]=nil end end
end
NS.ControlSkin.DisableOwner, NS.ScrollBarSkin.DisableOwner, NS.IconSkin.DisableOwner = ReleaseControls, ReleaseControls, ReleaseControls
NS.QuestRewardSelection = { Enable=function() end, Disable=function() end }
NS.Theme.GetMaterial = function(role) return {opacity=role} end
NS.Theme.GetMaterialOpacity = function(mat) return mat.opacity=="panel" and 0.88 or 1 end
NS.DB = { enabled=true, blizzardWindowsEnabled=true, skins={blizzardWindows=true}, skinCategories={quest=true} }
NS.GenericWindows.ApplyFrame, NS.GenericWindows.ApplyEntry = function() error("used generic traversal") end, function() error("used generic catalog") end
NS.BlizzardCatalog.FindByFrame = function() return nil end
local stagedCosmetics = arg[2] and io.open(arg[2] .. "/Cosmetics.lua","rb")
if stagedCosmetics then stagedCosmetics:close() end
assert(loadfile(stagedCosmetics and (arg[2] .. "/Cosmetics.lua") or skin .. "../MSUF_Suite/Appearance/Cosmetics.lua"))("MSUF_Suite_Skin", NS)
QuestTextContrast = { UseLightText=function() return false end }
QuestFrame_SetMaterial, QuestInfo_ShowRewards, QuestInfo_Display = function() end, function() end, function() end
function GetQuestID() return 331 end
function GetNumQuestChoices() return 2 end
function GetNumQuestRewards() return 0 end
function QuestInfoItem_OnClick(row)
    if row.type == "choice" then
        QuestInfoItemHighlight:SetPoint("TOPLEFT",row,"TOPLEFT",-8,7)
        QuestInfoItemHighlight:Show()
        QuestInfoFrame.itemChoice=row:GetID()
    end
end
local grant, hovered
local function Row(parent,i,name)
    local row=Node("QuestInfoRewardsFrameQuestInfoItem"..i,parent,"Button")
    row.id,row.type,row.objectType,row.questID,row.largeItemButton = i,"choice","item",331,true
    row.Name=Label(row,name)
    function row:GetID() return self.id end
    for _,field in ipairs({"Icon","IconBorder","NameFrame"}) do Art(row,field) end
    row:SetScript("OnClick", function(self) QuestInfoItem_OnClick(self) end)
    row:SetScript("OnEnter", function(self) hovered=self end)
    return row
end
NS.Client.isForever = arg[3] ~= "retail"
UIParent = Node("UIParent")
local q=Global("QuestFrame",UIParent)
local alreadySkinned = arg[4] == "partial"
if alreadySkinned then
    NS.Surface.Attach(q,{role="shell"})
end
if arg[5] == "hidden" then q:Hide() end
q.GetChildren=function() error("walked the entire QuestFrame") end
Art(q,"Bg"); q.NineSlice=Node(nil,q); Art(q.NineSlice,"TopEdge")
q.Inset=Node("QuestFrameInset",q); Art(q.Inset,"Bg")
if alreadySkinned then NS.Cosmetics.Fade(q.Inset.Bg,"blizzardWindows") end
QuestFramePortrait=Node("QuestFramePortrait",q,"Texture")
local reward
for _, suffix in ipairs({"GreetingPanel","ProgressPanel","DetailPanel","RewardPanel"}) do
    local page=Global("QuestFrame"..suffix,q)
    page.width,page.height=384,512
    page.shown = suffix=="RewardPanel"
    Art(page,"Bg"); Art(page,"MaterialTopLeft"); Art(page,"MaterialTopRight")
    if page.shown then reward=page end
end
QuestFrameGreetingPanel.titleButtonPool={EnumerateActive=function() return function() end end}
local scroll=Global("QuestRewardScrollFrame",reward,"ScrollFrame")
reward.ScrollFrame=scroll
scroll.ScrollBar=Node(nil,scroll,"EventFrame")
local child=Global("QuestRewardScrollChildFrame",scroll)
Global("QuestDetailScrollChildFrame",QuestFrameDetailPanel)
local close=Global("QuestFrameCompleteQuestButton",reward,"Button")
for _,field in ipairs({"Left","Middle","Right"}) do Art(close,field) end
close:SetScript("OnClick",function() grant=QuestInfoFrame.itemChoice end)
local rewards=Global("QuestInfoRewardsFrame",child)
QuestInfoTitleHeader,QuestInfoRewardText=Label(child,"Report to Doren"),Label(child,"Quest story")
QuestInfoObjectivesFrame, QuestInfoSealFrame = { Objectives={} }, {}
rewards.XPFrame=Node(nil,rewards,"Button")
rewards.Header=Label(rewards,"Rewards")
rewards.ItemChooseText=Label(rewards,"Choose your reward")
local hi=Global("QuestInfoItemHighlight",rewards)
hi:Hide()
rewards.ItemHighlight=hi
QuestInfoFrame={rewardsFrame=rewards,acceptButton=close,chooseItems=true,questLog=false,mapView=false,itemChoice=0}
local a,b=Row(rewards,1,"Junglewalker Sandals"),Row(rewards,2,"Frost Metal Pauldrons")
local map=Global("WorldMapFrame",UIParent)
map:Hide()
local alien=Row(map,3,"Map-only quest")
rewards.RewardButtons, rewards.activeRewardElements={a,b,alien},{a,b}
local aClick,bClick,bEnter,foreignEnter=a:GetScript("OnClick"),b:GetScript("OnClick"),b:GetScript("OnEnter"),alien:GetScript("OnEnter")
LoadAdapter("QuestRewardCards",true)
LoadAdapter("QuestWindow",true)
LoadAdapter("QuestText")
-- No GenericWindows.ApplyEntry has been called. The NPC has already been
-- fully shown when the normal adapter is activated.
local first,second="blizzardWindows:deep-windows","another NPC owner"
assert(NS.QuestText.Activate(q,first))
Drain()
if arg[5] == "hidden" then q:Show(); reward:Fire("OnShow"); Drain() end
Expect(surfaces[q] and surfaces[q].fill:IsVisible(), "visible NPC lacks a physical Suite shell")
Expect(q.Bg.alpha==0 and reward.Bg.alpha==0 and reward.MaterialTopLeft.alpha==0,
    "physical root and active reward parchment remain unskinned")
Expect(q.NineSlice.TopEdge.alpha==0 and QuestFramePortrait.alpha==1, "frame border or portrait incorrect")
Expect(controls[close] and controls[scroll.ScrollBar], "completion footer or scrollbar lacks skin")
Expect(not surfaces[reward], "oversized native reward page grew a second shell")
local boundedBacking
for _,part in ipairs(reward.created) do
    if part.layer=="ARTWORK" and part.rgba and part.rgba[4]==0.88 and part:IsVisible()
        and part.points[1] and part.points[1][2]==q and part.points[2] and part.points[2][2]==q then boundedBacking=part end
end
Expect(boundedBacking,"native reward page has no backing bounded to quest root and profile opacity")
Expect(HasPaint(q,"ARTWORK") or HasPaint(q,"BACKGROUND") or HasPaint(q,"BORDER"),
    "normal NPC owner produced no visible header, body or footer decoration")
Expect(a.NameFrame.alpha==0 and b.NameFrame.alpha==0 and HasPaint(a,"BACKGROUND") and HasPaint(b,"BACKGROUND"),
    "the original two Blizzard buttons lack visible styled cards")
Expect(a.Icon.alpha==1 and b.Name.alpha==1 and hi:IsShown()==false and QuestInfoFrame.itemChoice==0,
    "skinning touched icon, label or selected a reward automatically")
assert(NS.QuestText.Activate(q,second)); Drain()
local progress=QuestFrameProgressPanel
reward:Hide(); progress:Show(); QuestFrame_SetMaterial(progress); Drain()
Expect(progress.Bg.alpha==0 and progress.MaterialTopLeft.alpha==0,"switching the existing NPC root to progress exposed parchment")
progress:Hide(); reward:Show(); QuestInfo_ShowRewards(); Drain()
Expect(reward.Bg.alpha==0 and HasPaint(b,"BACKGROUND"),"reopening the hand-in missed the active reward page or card")
local beforeAlphaWrites=q.Bg.changes+reward.Bg.changes
-- The reported live state was reached AFTER all page, display and material
-- events. There is no later OnShow, SetMaterial or whole-window traversal.
q.Bg:Show(); reward.Bg:Show()
q.Bg:SetAlpha(1); reward.Bg:SetAlpha(1)
Drain()
Expect(q.Bg.alpha==0 and reward.Bg.alpha==0,"native SetAlpha(1) re-exposed a settled NPC parchment")
Expect(not q.Bg:IsShown() and not reward.Bg:IsShown(),"native Show() re-exposed a settled NPC background")
Expect(not hookCounts[QuestFramePortrait] and not hookCounts[b.Icon] and not hookCounts[hi],
    "native portrait, choice icon or selection highlight acquired a cosmetic visibility hook")
Expect(q.Bg.changes+reward.Bg.changes-beforeAlphaWrites<=6,"recursive SetAlpha repair cycle")
local stableCount=q.Bg.changes+reward.Bg.changes
for i=1,4 do Drain() end
Expect(q.Bg.changes+reward.Bg.changes==stableCount,"idle parchment repair kept rewriting textures")
-- Blizzard can pool a new choice and change the selected row during combat.
-- The global settings queue is suspended until regen.
local hold, regularQueue, regularGate = {}, NS.Registry.QueueJob, NS.CombatGate.RunOrDefer
NS.Registry.QueueJob = function(job) hold[job] = job end
NS.CombatGate.RunOrDefer = function(key, job) hold[key] = job end
locked = true
local late = Row(rewards, 3, "A late choice")
local protected = Row(rewards, 4, "Protected choice")
protected.IsProtected = function() return true, false end
rewards.RewardButtons[3], rewards.RewardButtons[4] = late, protected
QuestInfo_ShowRewards()
Drain()
Expect(HasPaint(late,"BACKGROUND") and not late.NameFrame:IsShown(), "late combat reward has no styled card")
Expect(not HasPaint(protected,"BACKGROUND") and protected.NameFrame:IsShown(), "painted a protected reward in combat")
b:Fire("OnEnter"); b:Fire("OnClick"); Drain()
local _,anchor=hi:GetPoint(1)
Expect(hovered==b and QuestInfoFrame.itemChoice==2 and hi:IsVisible() and anchor==b,
    "the second original button lost native hover or its selected highlight")
Expect(HasPaint(b,"ARTWORK") and not HasPaint(a,"ARTWORK"),
    "the Suite selection indicator did not follow the second native click")
rewards.RewardButtons[3], rewards.RewardButtons[4] = alien, nil
QuestInfo_ShowRewards()
Drain()
Expect(not HasPaint(late,"BACKGROUND") and late.NameFrame:IsShown(), "a recycled combat reward retained the NPC card")
locked = false
NS.Registry.QueueJob, NS.CombatGate.RunOrDefer = regularQueue, regularGate
for _, job in pairs(hold) do job() end
Drain()
Expect(a:GetScript("OnClick")==aClick and b:GetScript("OnClick")==bClick and b:GetScript("OnEnter")==bEnter
    and next(alien.created)==nil and alien:GetScript("OnEnter")==foreignEnter,"presentation replaced native scripts or painted a foreign row")
close:Fire("OnClick")
Expect(grant==2,"completion did not use the player's actual second choice")
NS.QuestText.Deactivate(q,first); q.Bg:SetAlpha(1); Drain()
Expect(q.Bg.alpha==0,"one departing owner tore down the other owner's quest chrome")
reward.Bg:Hide()
reward.Bg:SetAlpha(0.47)
reward.MaterialTopRight:SetAlpha(0)
if alreadySkinned then q.Inset.Bg:SetAlpha(0.58) end
Drain()
NS.QuestText.Deactivate(q,second); Drain()
Expect(q.Bg.alpha==1 and q.Bg:IsShown() and reward.Bg.alpha==0.47 and not reward.Bg:IsShown()
    and reward.MaterialTopLeft.alpha==1 and reward.MaterialTopRight.alpha==0 and q.NineSlice.TopEdge.alpha==1,
    "last disable failed to restore the current native alpha and shown intent")
if alreadySkinned then
    Expect(NS.Cosmetics.GetOwner(q.Inset.Bg)=="blizzardWindows" and q.Inset.Bg.alpha==0,
        "dedicated disable tore down generic inset ownership")
    NS.Cosmetics.RestoreOwner("blizzardWindows")
    Expect(q.Inset.Bg.alpha==0.58,"the remaining generic owner restored a stale native alpha")
end
Expect(alreadySkinned and surfaces[q] and surfaces[q].fill:IsVisible() or
    not alreadySkinned and (not surfaces[q] or not surfaces[q].fill:IsVisible()),
    "last disable mis-restored the dedicated or pre-existing shell")
Expect(not HasPaint(q,"ARTWORK") and not HasPaint(q,"BACKGROUND") and not HasPaint(q,"BORDER"),
    "last disable retained an owned header, body or footer layer")
Expect(not boundedBacking or not boundedBacking:IsShown(),"last disable retained the reward page backing")
Expect(a.NameFrame.alpha==1 and b.NameFrame.alpha==1 and not HasPaint(b,"BACKGROUND"),
    "last disable failed to restore the original quest buttons")
q.Bg:SetAlpha(0.62); reward.Bg:SetAlpha(0.36); Drain()
Expect(q.Bg.alpha==0.62 and reward.Bg.alpha==0.36,"an inactive presentation reclaimed a native write")
assert(#failures==0,table.concat(failures,"\n"))
print("suite_quest_presentation_contract: " .. checks .. " checks passed")
]======]
local contract=source:sub(1,stop-1)..body
local stages=arg[2]
for _, scenario in ipairs({{"retail","cold","hidden"},{"forever","partial","visible"}}) do
    arg={root,stages,unpack(scenario)}
    issecretvalue=nil
    assert(loadstring(contract,"@suite_quest_presentation_contract"))()
end
