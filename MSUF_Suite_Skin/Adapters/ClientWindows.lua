local _, NS = ...

NS.Defaults.skins.classicWindows = true
if NS.Client.isMainline or NS.Client.flavor == "Unknown" then return end

-- Exact additional roots from the Classic client's UIPanels_Game, TalentUI,
-- TradeSkillUI and CraftUI manifests. Forever uses Mainline's PlayerSpells.
local OWNER = "classicWindows"

local roots = {
    "SpellBookFrame",
    "QuestLogFrame",
    "PlayerTalentFrame",
    "TradeSkillFrame",
    "CraftFrame",
}

local addons = {
    "Blizzard_UIPanels_Game",
    "Blizzard_TalentUI",
    "Blizzard_TradeSkillUI",
    "Blizzard_CraftUI",
}

-- Load-on-demand addons still to come; the listener stops with the last one.
local pending = {}
local eventFrame

local function OnAddonLoaded(self, _, name)
    if not pending[name] then return end
    pending[name] = nil
    if not next(pending) then self:UnregisterAllEvents() end
    NS.Adapters.Apply(OWNER)
end

local function Apply()
    for index = 1, #roots do
        local target = _G[roots[index]]
        if target then NS.GenericWindows.ApplyFrame(target, OWNER, "shell") end
    end
    if NS.QuestText then NS.QuestText.Activate(_G.QuestLogFrame, OWNER) end
    for index = 1, #addons do
        local addon = addons[index]
        if NS.Client.HasAddOn(addon) ~= false and not NS.Client.IsAddOnLoaded(addon) then
            pending[addon] = true
        end
    end
    if next(pending) then
        if not eventFrame then
            eventFrame = CreateFrame("Frame")
            eventFrame:SetScript("OnEvent", OnAddonLoaded)
        end
        eventFrame:RegisterEvent("ADDON_LOADED")
    end
    return true
end

local function Disable()
    if eventFrame then eventFrame:UnregisterAllEvents() end
    for key in pairs(pending) do
        pending[key] = nil
    end
    if NS.QuestText then NS.QuestText.Deactivate(_G.QuestLogFrame, OWNER) end
    NS.GenericWindows.Disable(OWNER)
    return true
end

-- The adapter has no single root frame; resolve returns a stable token.
local token = {}
NS.Adapters.Register({
    id = OWNER,
    labelKey = "SKIN_CLASSIC_WINDOWS",
    resolve = function() return token end,
    apply = Apply,
    disable = Disable,
    defaultEnabled = true,
})
