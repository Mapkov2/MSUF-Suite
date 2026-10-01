local _, P = ...
local S, Tr = P.S, P.Tr
local PAGE, ID = "suite_bags", "bags"

local function Build(ctx)
    local b = P.W.PageBuilder(ctx)
    P.ModuleCard(ctx, b, PAGE, ID, {
        { "Choose currencies", function(button)
            if S.BagCurrencyMenu then S.BagCurrencyMenu(button) end
          end, function() return P.Get(ID, "enabled") and S.Availability(ID) end, key = "currencies" },
        { "Open bags", function() OpenAllBags() end,
          function() return P.Get(ID, "enabled") and S.Availability(ID) end, key = "open" },
        { "Move bag windows", function()
            OpenAllBags()
            P.OpenEditMode(ID, "combined")
          end, function() return P.EditModeReady() and P.Get(ID, "enabled") and S.Availability(ID) end, key = "move" },
    })
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_look", Tr("Choose a look"),
        P.SectionRules(ID, "look"), {
            help = "Choose Clean Modern, Midnight Blue, Midnight Dark, MSUF Forever or Class Style. This changes only the bag window colors and opacity; item slots and Blizzard bag actions remain intact.",
            open = true,
        })
    -- Hidden rules are data (custom categories): never rendered, never reset.
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_organisation", Tr("Inventory organisation"),
        P.SectionRules(ID, "organisation", function(rule) return not rule.hidden end), {
            help = "Keep Blizzard grid, or choose one Suite grid, physical bag groups or categories. Use Edit categories in the bag window to create, rename, reorder or disable your categories; drop items onto a sidebar category to assign them. Scroll or use Previous and Next for larger inventories; in combat every slot is shown at once. Combined stack counts are visual only; physical stacks are always restored at the bank, guild bank, mail, trade, auction house and merchant.",
            open = true,
        })
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_categories", Tr("Built-in categories"),
        P.SectionRules(ID, "categories"), {
            help = "Disable a built-in category to keep those items in Other items. Items are never hidden or moved by disabling a category.",
        })
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_collections", Tr("Pinned and recent items"),
        P.SectionRules(ID, "collections"), {
            help = "Drop an item onto Pinned items in the category sidebar to keep it at the top of every view. Recent items lists up to 200 item types this character received, also across logins; each leaves the list once it is older than the hours set here, and Clear recent items empties it sooner. Neither action moves or deletes an item.",
        })
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_finance", Tr("Gold and currencies"),
        P.SectionRules(ID, "finance"), {
            help = "Selected currencies appear above the bag footer. Click Gold history for recorded character balances and 30 days of this character's income and spending, by local date. Other characters show their last recorded balance. The history starts when enabled and does not reconstruct earlier transactions; Clear saved character gold removes the history and the balances.",
            extra = function(body, y, width)
                P.Button(ctx, body, "Clear saved character gold", 16, y, width,
                    function() P.Suite.ClearCharacterGold() end,
                    function() return type(P.Suite.RootDB) == "table" end,
                    P.Meta(PAGE, ID, "action.clearGold", "action", PAGE .. "_finance"))
                return y - 40
            end,
        })
    local appearance = P.SectionRules(ID, "appearance")
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_appearance", Tr("Window appearance"), appearance, {
        help = "The combined bag and reagent bag use a Suite panel with a distinct header, border, and accent line. Set background opacity to 0 for a transparent window; item slots stay visible.",
        open = true,
    })
    local rules = P.SectionRules(ID, "itemLevels")
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_itemLevels", Tr("Item levels"), rules, {
        help = "Equipment item levels appear in the upper right of each slot. Choose a font, outline, shadow and Smooth, Sharp or Slug rendering. Slug has no shadow. Missing item data appears when the client provides it.",
        open = true,
    })
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_window", Tr("Combined bag window"),
        P.SectionRules(ID, "window"), {
            help = P.Help("Drag the bag title to move it; click for options.", "Drag the title of an open bag to move it. Click the title for bag options. Each bag keeps its own position. Blizzard shows your current gold on the right; the optional Session value on the left shows the change since login and survives /reload. Adjust the combined bag size here or in its MSUF Edit Mode popup. Reset position in Edit Mode returns the window to Blizzard's normal anchor."),
        })
    local bankRules = P.SectionRules(ID, "bank", function(rule) return not rule.hidden end)
    if #bankRules > 0 then
        P.RuleSection(ctx, b, PAGE, ID, "suite_bags_bank", Tr("Bank organisation"), bankRules, {
            help = "Switch between native tabs, combined bank, combined warbank and shared categories with the button below the bank window. Shared categories include accessible character and warbank tabs. Manage bank tabs returns to Blizzard purchases, deposits and tab settings. Every slot keeps its own item action and bank stacks are never merged; clicking a warband item selects Blizzard's Warband Bank tab first, and a refundable item asks before it enters the warband bank.",
        })
    end
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_reagentWindow", Tr("Reagent bag window"),
        P.SectionRules(ID, "reagentWindow"), {
            help = "Drag the reagent bag title while it is open to move it independently. Click the title for bag options. Reset its position in MSUF Edit Mode to follow Blizzard's normal bag layout again.",
        })
end

P.RegisterPage({ key = PAGE, label = "Bags", title = "Bags", build = Build, icon = { 3, 2 },
    nav = "interface", navOrder = 4,
    aliases = { "bags", "bag", "inventory", "itemlevel", "item_level" } })
