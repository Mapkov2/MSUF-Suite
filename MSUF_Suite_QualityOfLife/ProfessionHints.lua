local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client.isForever then return end

local Data, Advice = P.ProfessionHintData, P.ProfessionHintAdvice
local Text = S.Text
local PROFESSIONS_ADDON = "Blizzard_Professions"
local M = { surfaces = {}, addons = { [PROFESSIONS_ADDON] = true } }
local BOOK_SLOTS = {
    PrimaryProfession1 = 1, PrimaryProfession2 = 2,
    SecondaryProfession1 = 5, SecondaryProfession2 = 4, SecondaryProfession3 = 3,
}
local NEXT_CAP = { [75] = 150, [150] = 225, [225] = 300 }
local HOVER_EVENTS = { "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }

-- Forever d9c22e32cb. Blizzard_Professions/Camelot/Blizzard_ProfessionsFrame.xml
-- loads BookPage and CraftingPage. The Camelot ProfessionsBook mixin maps the
-- five cards to GetProfessions(), and uses the unmodified rank for the bar.
local function ReadSkill(id, skill, cap, bonus, name)
    id, name = Advice.SkillLine(id), S.PublicText(name)
    if not id or not name or not S.Finite(skill) or not S.Finite(cap) or not S.Finite(bonus)
        or skill < 1 or cap < skill or cap > 300 then return end
    return id, skill, cap, bonus, name
end

local function ReadBookSlot(slot)
    local index = select(slot, GetProfessions())
    if not S.Finite(index) or index <= 0 then return end
    local name, _, skill, cap, _, _, id, bonus = GetProfessionInfo(index)
    return ReadSkill(id, skill, cap, bonus, name)
end

local function External(query)
    if type(query) ~= "function" then return true end
    local value = query()
    return not S.Public(value) or value == true
end

local function ReadCraftingSkill()
    local api = C_TradeSkillUI
    if External(api.IsNPCCrafting) or External(api.IsTradeSkillLinked) or External(api.IsTradeSkillGuild)
        or External(api.IsTradeSkillGuildMember) then return end
    local info = api.GetChildProfessionInfo()
    if not S.Public(info) or type(info) ~= "table" or not S.Finite(info.professionID) then return end
    if info.professionID == 0 then info = api.GetBaseProfessionInfo() end
    if not S.Public(info) or type(info) ~= "table" or not S.Public(info.parentProfessionID) then return end
    local parent = info.parentProfessionID
    local id = S.Finite(parent) and parent > 0 and parent or info.professionID
    return ReadSkill(id, info.skillLevel, info.maxSkillLevel,
        info.skillModifier, info.professionName)
end

local function UnknownRecipe() end

local function ReadRecipe(id)
    local info = C_TradeSkillUI.GetRecipeInfo(id)
    if not S.Public(info) or type(info) ~= "table" or not S.Finite(info.recipeID) or info.recipeID ~= id then return end
    local learned, canSkillUp = info.learned, info.canSkillUp
    if not S.Public(learned) or type(learned) ~= "boolean" then return end
    if S.Public(canSkillUp) and type(canSkillUp) == "boolean" then return learned, canSkillUp end
    return learned
end

local function ItemName(id, fallback)
    return S.PublicText(C_Item.GetItemNameByID(id)) or fallback
end

local function Line(tooltip, message, r, g, b)
    tooltip:AddLine(message, r or 1, g or .87, b or .62, true)
end

local function FindDestination(rows)
    if not rows then return end
    local choice = Advice.Trainer(rows, S.PublicText(UnitFactionGroup("player")))
    if not choice then return end
    local zone, district = Advice.MapName(choice[1]), choice[4]
    if district and zone then zone = ("%s, %s"):format(district, zone) end
    return choice[2], zone or district, choice[5]
end

local function AddRecipeSource(tooltip, recipe)
    local vendor, place = FindDestination(Data.recipeVendors[recipe[1]])
    if vendor and place then
        local item = ItemName(recipe[7], recipe[8])
        Line(tooltip, Text("Buy %s from %s in %s."):format(item, vendor, place), .86, .86, .86)
        return
    end
    local source = S.PublicText(C_TradeSkillUI.GetRecipeSourceText(recipe[1]))
    if not source and recipe[7] then
        source = Text("Recipe item: %s"):format(ItemName(recipe[7], recipe[8]))
    end
    Line(tooltip, source or Text("Learn this recipe from a profession trainer."), .86, .86, .86)
end

local function AddRecipe(tooltip, choice, label)
    local recipe = choice.recipe
    local name = S.PublicText(C_Spell.GetSpellName(recipe[1])) or recipe[6]
    Line(tooltip, label:format(name, choice.target))
    if choice.learned == false then
        Line(tooltip, Text("Recipe not learned"), 1, .5, .33)
        AddRecipeSource(tooltip, recipe)
    end
end

local function AddGathering(tooltip, id, skill, cap, bonus)
    local row, target = Advice.GatheringRow(Data.gathering[id], skill, bonus, cap)
    if not row then return end
    if id == 393 then
        local level = skill + bonus <= 100 and math.floor((skill + bonus) / 10) + 10
            or math.floor((skill + bonus) / 5)
        level = math.max(1, math.min(level, 60))
        Line(tooltip, Text("Skin beasts up to level %d until skill %d."):format(level, target))
    elseif id == 356 then
        Line(tooltip, Text("Fish in starter waters until skill %d."):format(target))
    elseif id == 186 and row[1] == 275 then
        Line(tooltip, Text("Mine rich thorium veins until skill %d."):format(target))
    else
        local name = ItemName(row[2], row[3])
        Line(tooltip, Text("Gather %s until skill %d."):format(name, target))
    end
    local zones = Advice.Zones(row[4])
    if zones ~= "" then Line(tooltip, Text("Zones: %s"):format(zones), .86, .86, .86) end
end

local function AddTraining(tooltip, id, cap)
    local nextCap = NEXT_CAP[cap]
    if not nextCap then return end
    Line(tooltip, Text("Next rank raises the cap to %d."):format(nextCap))
    local name, place, kind = FindDestination(Data.training[id][cap])
    if not place then return end
    if kind == "book" then
        Line(tooltip, Text("Buy the training book from %s in %s."):format(name, place))
    elseif kind == "quest" then
        Line(tooltip, Text("Visit %s in %s for the training quest."):format(name, place))
    else
        Line(tooltip, Text("Train with %s in %s."):format(name, place))
    end
end

local function AddAdvice(tooltip, id, skill, cap, bonus, readRecipe)
    if skill >= 300 then
        Line(tooltip, Text("Maximum profession skill reached."), .58, 1, .62)
        return
    end
    if skill >= cap then
        AddTraining(tooltip, id, cap)
        return
    end
    AddGathering(tooltip, id, skill, cap, bonus)
    local first, second = Advice.Recipes(Data.recipes[id], skill, cap, readRecipe)
    if not first then return end
    local label = id == 186 and Text("%s until skill %d.") or Text("Craft %s until skill %d.")
    AddRecipe(tooltip, first, label)
    if second then AddRecipe(tooltip, second, Text("Alternative: %s (until skill %d)")) end
end

local function Tooltip(self)
    if not self.tooltip then
        local tip = S.CreateFrame("GameTooltip", "MSUFSuiteProfessionHintTooltip", UIParent, "GameTooltipTemplate")
        tip:SetClampedToScreen(true)
        tip:EnableMouse(false)
        self.tooltip = tip
    end
    return self.tooltip
end

local function Clear(self)
    if self.tooltip then self.tooltip:Hide() end
end

local function Render(self)
    local hit = self.hover
    if not self.active or not hit or not hit:IsVisible() or NS.InCombat() then return Clear(self) end
    local id, skill, cap, bonus, name
    if hit.slot then
        id, skill, cap, bonus, name = ReadBookSlot(hit.slot)
    else
        id, skill, cap, bonus, name = ReadCraftingSkill()
    end
    if not id or not Data.training[id] then return Clear(self) end
    local tip = Tooltip(self)
    tip:SetOwner(hit, "ANCHOR_RIGHT")
    tip:ClearLines()
    tip:AddLine(Text("%s (%d/%d)"):format(name, skill, cap))
    AddAdvice(tip, id, skill, cap, bonus, hit.slot and UnknownRecipe or ReadRecipe)
    tip:Show()
end

local function EndHover(self)
    self.hover = nil
    for _, event in ipairs(HOVER_EVENTS) do self.context:RemoveEvent(event) end
    self.context:RemoveEvent("PLAYER_REGEN_DISABLED")
    Clear(self)
end

local function Enter(hit)
    if not M.active or NS.InCombat() then return end
    if M.hover and M.hover ~= hit then EndHover(M) end
    M.hover = hit
    M.context:Event("SKILL_LINES_CHANGED", Render)
    if not hit.slot then
        M.context:Event("TRADE_SKILL_LIST_UPDATE", Render)
        M.context:Event("TRADE_SKILL_DATA_SOURCE_CHANGED", Render)
    end
    M.context:Event("PLAYER_REGEN_DISABLED", EndHover)
    Render(M)
end

local function Leave(hit)
    if M.hover == hit then EndHover(M) end
end

local function AttachBar(self, bar, slot)
    if not bar then return false end
    local hit = self.surfaces[bar]
    if not hit then
        -- The rank template has no mouse-enabled bar. A Suite-owned child
        -- follows native visibility and leaves the rank dropdown's area free.
        hit = S.CreateFrame("Frame", nil, bar)
        hit.slot = slot
        hit:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -2)
        hit:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -24, -3)
        hit:SetMouseClickEnabled(false)
        hit:SetMouseMotionEnabled(true)
        hit:SetScript("OnEnter", Enter)
        hit:SetScript("OnLeave", Leave)
        hit:SetScript("OnHide", Leave)
        self.surfaces[bar] = hit
    end
    hit:Show()
    return true
end

local function Attach(self)
    if not self.active or NS.InCombat() then return end
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    if not NS.Client.IsAddOnLoaded(PROFESSIONS_ADDON) then return end
    local frame = ProfessionsFrame
    local book = frame.BookPage.ProfessionsContentFrame
    local complete = AttachBar(self, frame.CraftingPage.RankBar)
    for key, slot in pairs(BOOK_SLOTS) do
        if not AttachBar(self, book[key].StatusBar, slot) then complete = false end
    end
    if complete then self.context:RemoveEvent("ADDON_LOADED") end
end

local function TryAttach(self)
    if NS.InCombat() then
        self.context:Event("PLAYER_REGEN_ENABLED", Attach)
    else
        Attach(self)
    end
end

function M:Enable()
    self.context:Event("ADDON_LOADED", TryAttach)
    TryAttach(self)
end

function M:Disable()
    EndHover(self)
    for _, hit in pairs(self.surfaces) do hit:Hide() end
end

S.Install("professionHints", M)
