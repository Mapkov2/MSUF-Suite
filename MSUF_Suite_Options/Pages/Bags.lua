local _, P = ...
local S, Tr = P.S, P.Tr
local PAGE, ID = "suite_bags", "bags"

local function Build(ctx)
    local b = P.W.PageBuilder(ctx)
    P.ModuleCard(ctx, b, PAGE, ID, {
        { "Open bags", function() if type(_G.OpenAllBags) == "function" then OpenAllBags() end end,
          function() return P.Get(ID, "enabled") and S.Availability(ID) end, key = "open" },
        { "Move bag windows", function()
            if type(_G.OpenAllBags) == "function" then OpenAllBags() end
            S.OpenEditMode(ID, "combined")
          end, function() return P.Get(ID, "enabled") and S.Availability(ID) end, key = "move" },
        { "Reset module", function()
            P.WithHistory("Reset bags", "suite:bags.reset", function() return S.Reset(ID) end)
        end, function() return S.Availability(ID) end, key = "reset" },
    })
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_look", Tr("Choose a look"),
        P.SectionRules(ID, "look"), {
            help = "Choose Midnight Blue, Midnight Dark or MSUF Forever. This changes only the bag window colors and opacity; item slots and Blizzard bag actions remain intact.",
            open = true,
        })
    local appearance = P.SectionRules(ID, "appearance")
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_appearance", Tr("Window appearance"), appearance, {
        help = "The combined bag and reagent bag use a Suite panel with a distinct header, border, and accent line. Set background opacity to 0 for a transparent window; item slots stay visible.",
        open = true,
    })
    local rules = P.SectionRules(ID, "itemLevels")
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_itemLevels", Tr("Item levels"), rules, {
        help = "Equipment item levels appear in the upper right of each slot. Item data that has not loaded yet appears as soon as the client provides it.",
        open = true,
    })
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_window", Tr("Combined bag window"),
        P.SectionRules(ID, "window"), {
            help = "Drag the title of an open bag to move it. Click the title for bag options. Each bag keeps its own position. Blizzard shows your current gold on the right; the optional Session value on the left shows the change since login and survives /reload. Adjust the combined bag size here or in its MSUF Edit Mode popup. Reset position in Edit Mode returns the window to Blizzard's normal anchor.",
        })
    P.RuleSection(ctx, b, PAGE, ID, "suite_bags_reagentWindow", Tr("Reagent bag window"),
        P.SectionRules(ID, "reagentWindow"), {
            help = "Drag the reagent bag title while it is open to move it independently. Click the title for bag options. Reset its position in MSUF Edit Mode to follow Blizzard's normal bag layout again.",
        })
end

P.RegisterPage({ key = PAGE, label = "Bags", title = "Bags", build = Build, icon = { 3, 2 },
    aliases = { "bags", "bag", "inventory", "itemlevel", "item_level" } })
