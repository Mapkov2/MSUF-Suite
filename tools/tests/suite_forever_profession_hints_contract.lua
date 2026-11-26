-- The Camelot UI shares one frame between the profession book and crafting.
local root = assert(arg[1], "Suite root required")
local function Load(path, ns)
    return assert(loadfile(root .. "/" .. path))("MSUF_Suite", ns)
end

local retail = { Client = { isForever = false } }
local function Catalog(ns)
    Load("MSUF_Suite/Core/SuiteCatalog.lua", ns)
    Load("MSUF_Suite/Core/Catalog/ForeverTools.lua", ns)
    return ns.SuiteCatalog.professionHints
end

local function LoadHints(ns, s)
    local state = { NS = ns, Suite = s }
    for _, file in ipairs({ "ProfessionHintRecipes", "ProfessionHintData", "ProfessionHintAdvice", "ProfessionHints" }) do
        Load("MSUF_Suite_QualityOfLife/" .. file .. ".lua", state)
    end
    return state
end

local spec = Catalog(retail)
assert(not spec.available() and spec.rules.enabled.default == false, "Retail must keep the feature unavailable")
assert(not LoadHints(retail).ProfessionHintData, "Retail allocated Forever's routes")

local function Identity(value) return value end
local combat, hiddenBar
local client = {
    isForever = true,
    IsAddOnLoaded = function(name) return name == "Blizzard_Professions" and ProfessionsFrame ~= nil end,
}
local ns = { Client = client, InCombat = function() return combat end }
spec = Catalog(ns)
assert(spec.available() and spec.rules.enabled.default == true, "Forever default")
assert(spec.addon == "MSUF_Suite_QualityOfLife" and spec.page == "suite_qualityOfLife")

local function ReadOnly(fields)
    return setmetatable({}, { __index = fields, __newindex = function() error("native object was written") end })
end
local secret = ReadOnly({})
local function Public(value) return value ~= secret end

local tooltip, module, nativeControls = nil, nil, {}
GameTooltip = setmetatable({}, {
    __index = function() error("the shared tooltip was accessed") end,
    __newindex = function() error("the shared tooltip was modified") end,
})
UIParent = ReadOnly({})

local function Frame(kind, name, parent, template)
    local frame = { parent = parent, scripts = {} }
    function frame:SetPoint() end
    function frame:Show() self.shown = true end
    function frame:IsVisible() return self.shown and parent ~= hiddenBar end
    function frame:Hide()
        if self.shown and self.scripts.OnHide then self.scripts.OnHide(self) end
        self.shown = false
    end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:SetMouseClickEnabled(value) self.click = value end
    function frame:SetMouseMotionEnabled(value) self.motion = value end
    if kind == "GameTooltip" then
        assert(name == "MSUFSuiteProfessionHintTooltip" and template == "GameTooltipTemplate" and not tooltip)
        tooltip = frame
        function frame:SetClampedToScreen() end
        function frame:EnableMouse(value) assert(value == false) end
        function frame:SetOwner(owner) self.owner = owner end
        function frame:ClearLines() self.lines = {} end
        function frame:AddLine(text) self.lines[#self.lines + 1] = text end
    else
        assert(kind == "Frame" and parent and not nativeControls[parent], "one overlay per native bar")
        nativeControls[parent] = frame
    end
    return frame
end

local suite = {
    Text = Identity, Public = Public, CreateFrame = Frame,
    Finite = function(value) return Public(value) and type(value) == "number" and math.abs(value) < math.huge end,
    PublicText = function(value) return Public(value) and type(value) == "string" and value ~= "" and value or nil end,
    Install = function(id, owner)
        assert(id == spec.id and not module)
        module = owner
    end,
}
local state = LoadHints(ns, suite)
local data, advice = state.ProfessionHintData, state.ProfessionHintAdvice
local faction, playerMap = "Alliance", 1417
local mapPositions = {
    [1417] = { continent = 0, x = 4 }, [1423] = { continent = 0, x = 10 },
    [1437] = { continent = 0, x = 6 }, [1452] = { continent = 1, x = 4 },
}
function UnitFactionGroup() return faction end
function CreateVector2D(x, y) return { x = x, y = y } end
C_Map = {
    GetBestMapForUnit = function() return playerMap end,
    GetMapInfo = function(id) return { name = data.mapNames[id] } end,
    GetPlayerMapPosition = function() return { x = .4, y = .4 } end,
    GetWorldPosFromMapPos = function(id)
        local map = mapPositions[id]
        if map then return map.continent, { x = map.x, y = 3 } end
    end,
}
assert(advice.Zones({ 1452, 1423, 1437, 1417 }) == "Arathi Highlands, Wetlands, Eastern Plaguelands")
assert(advice.Zones({ 1452, 1437 }) == "Wetlands, Winterspring (other continent)")
playerMap = nil
assert(advice.Zones({ 1452, 1437 }) == "Winterspring, Wetlands", "fallback must preserve the authored order")
playerMap = 1417

local unlocked = 0
for child, id in pairs(data.baseSkillLines) do
    assert(advice.SkillLine(child) == id and advice.SkillLine(id) == id)
    unlocked = unlocked + 1
    for _, cap in ipairs({ 75, 150, 225 }) do
        for _, side in ipairs({ "Alliance", "Horde" }) do
            local trainer = assert(advice.Trainer(data.training[id][cap], side))
            assert(data.mapNames[trainer[1]] and (not trainer[3] or trainer[3] == side))
        end
    end
    for skill = 1, 299 do
        local gathering = advice.GatheringRow(data.gathering[id], skill, 0, 300)
        local recipe, other = advice.Recipes(data.recipes[id], skill, 300, function() end)
        assert(gathering or recipe, "uncovered profession/skill " .. id .. "/" .. skill)
        assert(not recipe or recipe.target > skill and recipe.target <= 300)
        assert(not other or other.recipe ~= recipe.recipe and other.target > skill and other.target <= 300)
    end
end
assert(unlocked == 12 and not advice.SkillLine(secret))

local events = {}
module.context = {
    Event = function(_, event, callback) events[event] = callback end,
    RemoveEvent = function(_, event) events[event] = nil end,
}
local function Dispatch(event, ...)
    local callback = events[event]
    if callback then callback(module, event, ...) end
end

module.active = true
module:Enable()
assert(next(nativeControls) == nil and events.ADDON_LOADED, "the native UI must remain load-on-demand")
local book, bookTwo, crafting, cook, fish, aid = ReadOnly({}), ReadOnly({}), ReadOnly({}),
    ReadOnly({}), ReadOnly({}), ReadOnly({})
ProfessionsFrame = ReadOnly({
    CraftingPage = ReadOnly({ RankBar = crafting }),
    BookPage = ReadOnly({ ProfessionsContentFrame = ReadOnly({
        PrimaryProfession1 = ReadOnly({ StatusBar = book }),
        PrimaryProfession2 = ReadOnly({ StatusBar = bookTwo }),
        SecondaryProfession1 = ReadOnly({ StatusBar = cook }),
        SecondaryProfession2 = ReadOnly({ StatusBar = fish }),
        SecondaryProfession3 = ReadOnly({ StatusBar = aid }),
    }) }),
})
combat = true
Dispatch("ADDON_LOADED", "Blizzard_Professions")
assert(next(nativeControls) == nil and events.PLAYER_REGEN_ENABLED, "combat prevented overlay construction")
combat = false
Dispatch("PLAYER_REGEN_ENABLED")
assert(not events.ADDON_LOADED and not events.PLAYER_REGEN_ENABLED and not tooltip)
local count = 0
for _, control in pairs(nativeControls) do
    assert(control.motion == true and control.click == false)
    count = count + 1
end
assert(count == 6)

local skillLevel, cap, bonus, alchemy = 124, 150, 1, true
local external, source, recipeReads, recipeLearned = false, nil, 0, false
GetProfessions = function() return alchemy and 42 or 43, nil, 3, 4, 5 end
GetProfessionInfo = function(index)
    if index == 42 then return "Alchemy", nil, skillLevel, cap, nil, nil, 2937, bonus end
    if index == 43 then return "Mining", nil, 124, 150, nil, nil, 186, 1 end
    if index == 3 then return "First Aid", nil, skillLevel, cap, nil, nil, 129, 0 end
    if index == 4 then return "Fishing", nil, 50, 75, nil, nil, 356, 0 end
    if index == 5 then return "Cooking", nil, 61, 150, nil, nil, 185, 0 end
end
C_Item = { GetItemNameByID = function() end }
C_Spell = { GetSpellName = function() end }
local craftInfo = { professionID = 2942, parentProfessionID = 0, professionName = "First Aid",
    skillLevel = 200, maxSkillLevel = 225, skillModifier = 0 }
C_TradeSkillUI = {
    IsNPCCrafting = function() return false end,
    IsTradeSkillLinked = function() return external end,
    IsTradeSkillGuild = function() return false end,
    IsTradeSkillGuildMember = function() return false end,
    GetChildProfessionInfo = function() return craftInfo end,
    GetRecipeInfo = function(id)
        recipeReads = recipeReads + 1
        return { recipeID = id, learned = recipeLearned, canSkillUp = true }
    end,
    GetRecipeSourceText = function() return source end,
}

local function Hover(bar)
    local hit = assert(nativeControls[bar])
    assert(hit:IsVisible())
    hit.scripts.OnEnter(hit)
    return hit
end
local function Contains(value)
    assert(tooltip and tooltip.shown and table.concat(tooltip.lines, "\n"):find(value, 1, true),
        "missing tooltip line: " .. value)
end
local bookHit = Hover(book)
Contains("Alchemy (124/150)")
Contains("Craft ")
assert(recipeReads == 0, "the book should never read a foreign or stale recipe list")
alchemy = false
Dispatch("SKILL_LINES_CHANGED")
Contains("Mining (124/150)")
Contains("Iron Ore")
assert(recipeReads == 0)

Hover(cook)
Contains("Cooking (61/150)")
Hover(fish)
Contains("Fishing (50/75)")
assert(not events.TRADE_SKILL_LIST_UPDATE, "book subscribed to crafting updates")

local craftHit = Hover(crafting)
Contains("First Aid (200/225)")
Contains("Recipe not learned")
Contains("Deneb Walker")
faction = "Horde"
recipeLearned = false
source = "Client recipe source"
Dispatch("TRADE_SKILL_LIST_UPDATE")
Contains("Balai Lok'Wein")
Contains("Client recipe source")
bookHit.scripts.OnLeave(bookHit)
assert(tooltip.shown and tooltip.owner == craftHit, "an old leave event hid the new tooltip")
recipeLearned = true
Dispatch("TRADE_SKILL_LIST_UPDATE")
assert(tooltip.shown and not table.concat(tooltip.lines, "\n"):find("Recipe not learned", 1, true))
external = true
Dispatch("TRADE_SKILL_DATA_SOURCE_CHANGED")
assert(not tooltip.shown, "linked professions must not show personal guidance")
external = false
craftInfo.skillLevel = secret
Dispatch("SKILL_LINES_CHANGED")
assert(not tooltip.shown, "secret rank must suppress the tooltip")
craftInfo.skillLevel, craftInfo.maxSkillLevel = 300, 300
Dispatch("SKILL_LINES_CHANGED")
Contains("Maximum profession skill reached.")
hiddenBar = crafting
craftHit.scripts.OnHide(craftHit)
assert(not tooltip.shown and not events.SKILL_LINES_CHANGED)
hiddenBar = nil

skillLevel, cap = 150, 150
Hover(aid)
Contains("Buy the training book from Balai Lok'Wein")
skillLevel, cap = 225, 225
Dispatch("SKILL_LINES_CHANGED")
Contains("Doctor Gregory Victor")
combat = true
Dispatch("PLAYER_REGEN_DISABLED")
assert(not tooltip.shown and not events.SKILL_LINES_CHANGED)
combat = false

module.active = false
module:Disable()
for _, control in pairs(nativeControls) do assert(not control:IsVisible()) end
assert(not tooltip.shown and next(events) == nil)
module.active = true
module:Enable()
assert(nativeControls[book] == bookHit and nativeControls[crafting] == craftHit)
Hover(aid)
Contains("Doctor Gregory Victor")
print("Profession hints data, gates, ownership, skill updates and both Forever profession pages passed")
