local _,NS=...
NS.Defaults.skins.classicWindows=true
if NS.Client.isMainline or NS.Client.flavor=="Unknown" then return end

-- Exact additional roots from the Classic client's UIPanels_Game, TalentUI,
-- TradeSkillUI and CraftUI manifests. Forever uses Mainline's PlayerSpells.
local roots={"SpellBookFrame","QuestLogFrame","PlayerTalentFrame","TradeSkillFrame","CraftFrame"}
local addons={"Blizzard_UIPanels_Game","Blizzard_TalentUI","Blizzard_TradeSkillUI","Blizzard_CraftUI"}
local pending={}
local frame
local owner="classicWindows"
local function Loaded(self,event,name)
    if not pending[name] then return end
    pending[name]=nil
    if not next(pending) then self:UnregisterAllEvents() end
    NS.Adapters.Apply(owner)
end
local function Apply()
    for i=1,#roots do
        local target=_G[roots[i]]
        if target then NS.GenericWindows.ApplyFrame(target,owner,"shell") end
    end
    if NS.QuestText then NS.QuestText.Activate(_G.QuestLogFrame, owner) end
    for i=1,#addons do
        local addon=addons[i]
        if NS.Client.HasAddOn(addon)~=false and not NS.Client.IsAddOnLoaded(addon) then
            pending[addon]=true
        end
    end
    if next(pending) then
        if not frame then frame=CreateFrame("Frame");frame:SetScript("OnEvent",Loaded) end
        frame:RegisterEvent("ADDON_LOADED")
    end
    return true
end
local function Disable()
    if frame then frame:UnregisterAllEvents() end
    for key in pairs(pending) do pending[key]=nil end
    if NS.QuestText then NS.QuestText.Deactivate(_G.QuestLogFrame, owner) end
    NS.GenericWindows.Disable(owner)
    return true
end
local token={}
NS.Adapters.Register({id=owner,labelKey="SKIN_CLASSIC_WINDOWS",resolve=function() return token end,
    apply=Apply,disable=Disable,defaultEnabled=true})
