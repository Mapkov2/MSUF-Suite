local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end
local Data, Lists, M = S.InventoryData, NS.InventoryLists, { tab = "shopping" }
local function Choices(text)
    local result, count = {}, 0
    for key, id in (text or ""):gmatch("([%d:]+)=(%d+)") do
        count = count + 1
        if count > 400 then break end
        id = tonumber(id)
        if id > 0 and id < 10000000 then result[key] = id end
    end
    return result
end

local function SaveChoice(key, id)
    local values, lines = Choices(M.config.choices), {}
    values[key] = id
    for entry, itemID in pairs(values) do lines[#lines + 1] = entry .. "=" .. itemID end
    table.sort(lines)
    local text = table.concat(lines, "\n")
    if #lines <= 400 and #text <= 12000 then S.Set(M.id, "choices", text) end
end

local function ReadSlot(slot)
    if not S.Public(slot) or type(slot) ~= "table" or not S.Public(slot.required) or slot.required ~= true then return nil end
    local reagents = slot.reagents
    if not S.Public(reagents) or type(reagents) ~= "table" or #reagents == 0 or #reagents > 50 then return {}, nil end
    local options = {}
    for i = 1, #reagents do
        local reagent = reagents[i]
        if not S.Public(reagent) or type(reagent) ~= "table" then return {}, nil end
        if S.Finite(reagent.itemID) and reagent.itemID > 0 then options[#options + 1] = reagent.itemID
        else
            return {}, nil
        end
    end
    local variable = slot.variableQuantities
    if not S.Public(variable) or type(variable) == "table" and #variable > 0 then return options, nil end
    local quantity = slot.quantityRequired
    return options, S.Finite(quantity) and quantity >= 0 and quantity or nil
end

local function SlotRow(recipe, slot, index, choices, totals)
    local options, quantity = ReadSlot(slot)
    if not options then return end
    local key = recipe.id .. ":" .. (recipe.recraft and "1" or "0") .. ":" .. index
    local chosen = #options == 1 and options[1] or choices[key]
    local valid = false
    for i = 1, #options do if options[i] == chosen then valid = true break end end
    local row = { key = key, recipeID = recipe.id, options = options, quantity = quantity, choice = valid and chosen or nil }
    if valid and quantity then
        totals[chosen] = (totals[chosen] or 0) + quantity * recipe.quantity
        row.label = S.Text("%s — %s × %d"):format(recipe.name, Data.Name(chosen), quantity * recipe.quantity)
        row.detail = S.Text("This material choice is used for the shopping total. Crafting quality and optional reagents stay in the profession window.")
    else
        row.label = S.Text("%s — material choice required"):format(recipe.name)
        row.detail = quantity and S.Text("Choose one material alternative before this slot can enter the total.")
            or S.Text(
                "This slot has a variable quantity, currency, or unavailable data. Review it in the profession window; it is excluded from the item total.")
    end
    return row
end

local function AddRecipes(self, recraft, quantities, choices, recipes, materials, totals)
    local ids = C_TradeSkillUI.GetRecipesTracked(recraft)
    if not S.Public(ids) or type(ids) ~= "table" then return end
    for i = 1, math.min(#ids, 100) do
        local id = ids[i]
        if S.Finite(id) and id > 0 then
            local schematic = C_TradeSkillUI.GetRecipeSchematic(id, recraft)
            if S.Public(schematic) and type(schematic) == "table" then
                local name, slots = S.PublicText(schematic.name), schematic.reagentSlotSchematics
                if name and S.Public(slots) and type(slots) == "table" then
                    local key = id * 2 + (recraft and 1 or 0)
                    local recipe = { key = key, id = id, recraft = recraft, name = name, quantity = quantities[key] or 1 }
                    recipe.label = S.Text("%s — %d crafts"):format(name, recipe.quantity)
                    if recraft then recipe.label = S.Text("Recraft: %s"):format(recipe.label) end
                    recipe.detail = S.Text("Choose Craft quantity to change how many times you plan to craft this tracked recipe.")
                    recipes[#recipes + 1] = recipe
                    for j = 1, math.min(#slots, 30) do
                        local row = SlotRow(recipe, slots[j], j, choices, totals)
                        if row then materials[#materials + 1] = row end
                    end
                end
            end
        end
    end
end

function M:Build()
    local recipes, materials, totals = {}, {}, {}
    local quantities, choices = Lists.Quantities(self.config.quantities) or {}, Choices(self.config.choices)
    AddRecipes(self, false, quantities, choices, recipes, materials, totals)
    AddRecipes(self, true, quantities, choices, recipes, materials, totals)
    return recipes, materials, totals
end

function M:Rows()
    local recipes, materials, totals = self:Build()
    if self.tab == "recipes" then return recipes end
    if self.tab == "materials" then return materials end
    local _, bags, complete = Data.Bags()
    local rows = Data.QuantityRows(totals, bags)
    for i = 1, #rows do
        local row = rows[i]
        row.label = S.Text("%s — need %d, missing %d"):format(Data.Name(row.itemID), row.quantity,
            math.max(0, row.quantity - (bags[row.itemID] or 0)))
        row.detail = S.Text("Totals include only resolved required item slots. Review Material choices for unresolved slots; optional reagents are excluded.")
        if not complete then
            row.label = S.Text("%s — need %d, bag quantity unavailable"):format(Data.Name(row.itemID), row.quantity)
            row.detail = S.Text("Some bag slots are unavailable. Refresh outside combat before using a missing amount.")
        end
    end
    return rows
end

local function ChooseMaterial(self, row, window)
    if not row or not row.options or not row.quantity then return end
    local profile, before = NS.DB, self.config.choices
    S.ContextMenu(window, function(_, menu)
        menu:CreateTitle(S.Text("Choose material"))
        for i = 1, #row.options do
            local id = row.options[i]
            menu:CreateButton(Data.Name(id), function()
                if self.active and not NS.InCombat() and NS.DB == profile and self.config.choices == before then SaveChoice(row.key, id) end
            end)
        end
    end)
end

function M:Open()
    S.ToolListWindow.Open(self, { title = "Crafting shopping list", rows = M.Rows,
        help = "Track recipes in the profession window. Set craft quantities and resolve material choices before using the total.",
        empty = "No items to show. Track a recipe, then review Recipes and Material choices.",
        tabs = { { key = "shopping", label = "Shopping" }, { key = "recipes", label = "Recipes" }, { key = "materials", label = "Materials" } },
        currentTab = function(self) return self.tab end, selectTab = function(self, key) self.tab = key end,
        actions = {
            { label = "Craft quantity", enabled = function(self, row) return self.tab == "recipes" and row ~= nil end,
                run = function(self, row)
                    S.InventoryToolsUI.Number(self, "Craft quantity", row.quantity, function(_, quantity)
                        local values = Lists.Quantities(M.config.quantities) or {}
                        values[row.key] = quantity
                        return S.Set(M.id, "quantities", Lists.EncodeQuantities(values))
                    end)
                end },
            { label = "Choose material", enabled = function(self, row)
                return self.tab == "materials" and row and row.quantity ~= nil and #row.options > 1
            end, run = ChooseMaterial },
            { label = "Refresh", run = function(self) S.ToolListWindow.Refresh(self) end },
        } })
end
function M:Refresh() S.ToolListWindow.Refresh(self) end
function M:Enable()
    self.context:Event("TRACKED_RECIPE_UPDATE", M.Refresh)
    self.context:Event("BAG_UPDATE_DELAYED", M.Refresh)
    self.context:Event("TRADE_SKILL_DATA_SOURCE_CHANGED", M.Refresh)
end
function M:Disable() S.ToolListWindow.Close(self) end
S.Install("craftShopping", M)
