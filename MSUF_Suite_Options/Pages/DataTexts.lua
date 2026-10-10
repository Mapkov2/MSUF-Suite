local _, P = ...
local S, M, T, Tr = P.S, P.M, P.T, P.Tr
local PAGE, ID = "suite_dataTexts", "dataTexts"
-- The choice values of the crest and source settings (Core/Catalog/DataTexts.lua).
local CREST_MODE = P.Suite.DataTextCrestMode
local function CrestCurrencyMenu(anchor)
    local suite=P.Suite
    local selected,order,seen={},{},{}
    for value in (P.Get(ID,'crestCurrencyIDs') or ''):sub(1,4096):gmatch('%d+') do
        local id=tonumber(value)
        if suite.Finite(id) and id>0 and id<2147483647 and not selected[id] and #order<32 then
            selected[id]=true
            order[#order+1]=id
        end
    end
    local function Add(menu,id,info)
        if not suite.Finite(id) or id<=0 or seen[id] or not suite.Public(info) or type(info)~='table'
            or not suite.Public(info.name) or type(info.name)~='string' then return end
        seen[id]=true
        local label=info.name..' ('..id..')'
        if suite.Finite(info.iconFileID) then label='|T'..info.iconFileID..':16|t '..label end
        menu:CreateCheckbox(label,function() return selected[id]==true end,function()
            local values={}
            for _,value in ipairs(order) do if value~=id then values[#values+1]=value end end
            if not selected[id] and #values<32 then values[#values+1]=id end
            P.SetMany(ID,{crestMode=CREST_MODE.SELECTED,crestCurrencyIDs=table.concat(values,',')})
            CrestCurrencyMenu(anchor)
        end)
    end
    P.ContextMenu(anchor,function(_,menu)
        menu:SetScrollMode(420)
        menu:CreateTitle(Tr('Select your current-season crests from the native currency list.'))
        menu:CreateTitle(Tr('Selection order is display order. Remove and select again to move a currency last.'))
        menu:CreateButton(Tr('Clear selection'),function() P.SetMany(ID,{crestMode=CREST_MODE.SELECTED,crestCurrencyIDs=''}) end)
        for _,id in ipairs(order) do Add(menu,id,C_CurrencyInfo.GetCurrencyInfo(id)) end
        menu:CreateDivider()
        for index=1,C_CurrencyInfo.GetCurrencyListSize() do
            local info=C_CurrencyInfo.GetCurrencyListInfo(index)
            if suite.Public(info) and type(info)=='table' and suite.Public(info.name) and type(info.name)=='string' then
                if suite.Public(info.isHeader) and info.isHeader then
                    local row=index
                    local expanded=suite.Public(info.isHeaderExpanded) and info.isHeaderExpanded==true
                    local header=menu:CreateButton(info.name..(expanded and ' -' or ' +'),function()
                        C_CurrencyInfo.ExpandCurrencyList(row,not expanded)
                        CrestCurrencyMenu(anchor)
                    end)
                    header:SetResponse(MenuResponse.Open)
                else
                    local link=C_CurrencyInfo.GetCurrencyListLink(index)
                    if suite.Public(link) and type(link)=='string' then Add(menu,C_CurrencyInfo.GetCurrencyIDFromLink(link),info) end
                end
            end
        end
    end)
end
-- The upgrade stages DataTexts observed this login. Sources.lua belongs to
-- the load-on-demand DataTexts addon and exports them on S (Suite.Suite), not
-- on the namespace: before it loads, the menu offers only the reset to all
-- observed stages.
-- A checkbox click keeps Blizzard's menu open and redraws every tick, so
-- both read the saved stages, not the ones the menu opened with.
local function StageSelected(order)
    for value in (P.Get(ID, "crestCurrencies") or ""):gmatch("%d+") do
        if tonumber(value) == order then return true end
    end
    return false
end
local function SeasonStagesMenu(anchor)
    local sources = S.DataTextExtraSources
    local choices = sources and sources.CrestChoices() or {}
    P.ContextMenu(anchor, function(_, menu)
        menu:CreateButton(Tr("Show all observed stages"), function() P.SetMany(ID, { crestMode = CREST_MODE.OBSERVED, crestCurrencies = "" }) end)
        for _, cost in ipairs(choices) do
            local order = cost.order
            local info = cost.currencyID and C_CurrencyInfo.GetCurrencyInfo(cost.currencyID)
            local name = info and info.name or cost.itemID and C_Item.GetItemInfo(cost.itemID) or tostring(order)
            menu:CreateCheckbox(tostring(order) .. ": " .. name, function() return StageSelected(order) end, function()
                local values = {}
                for value in (P.Get(ID, "crestCurrencies") or ""):gmatch("%d+") do
                    if tonumber(value) ~= order then values[#values + 1] = value end
                end
                if not StageSelected(order) then values[#values + 1] = tostring(order) end
                P.SetMany(ID, { crestMode = CREST_MODE.OBSERVED, crestCurrencies = table.concat(values, ",") })
            end)
        end
    end)
end

local function SharedRules(ctx, b, reveal, section, title, rules, opts)
    opts.onEnsureVisible = reveal
    opts.onBuilt = function(_, entries) P.DataTextPage.Prepare(entries, section, reveal) end
    local body = P.RuleSection(ctx, b, PAGE, ID, section, title, rules, opts)
    return body
end

local function Shared(ctx, b, reveal)
    SharedRules(ctx, b, reveal, PAGE .. "_appearance", Tr("Shared bar style"),
        P.SectionRules(ID, "appearance"), {
            open = true,
            help = "These settings apply to all bars until a bar uses its own style.",
        })
    SharedRules(ctx, b, reveal, PAGE .. "_textStyle", Tr("Shared text style"),
        P.SectionRules(ID, "textStyle"), {
            help = "Choose an MSUF font, outline, shadow and Smooth, Sharp or Slug rendering. Slug has no shadow. Label, value and warning colors are separate.",
        })
    local bagRules = P.SectionRules(ID, "bags")
    if #bagRules > 0 then
        SharedRules(ctx, b, reveal, PAGE .. "_bags", Tr("Blizzard bag buttons"), bagRules, {
            help = "While DataTexts is active, hide Blizzard's backpack and bag slots. A Bag space DataText opens the native bags when clicked. Turn this off to restore the Blizzard buttons.",
        })
    end
    SharedRules(ctx,b,reveal,PAGE..'_sources',Tr('Additional data sources'),P.SectionRules(ID,'sources'),{
        help='Choose broker names and discovered currency IDs per place. Select your current-season crest currencies from the native currency list; saved currency selections work after login without visiting an upgrade NPC. Selection order and separator control the crest block. Observed upgrade stages remain available as an alternative after selecting an upgrade item this login. Hearthstone actions require a deliberate click.',
        extra=function(body,y,width)
            if not P.Suite.Client.modernEquipment then return y end
            local button
            local picker
            picker=P.Button(ctx,body,'Choose crest currencies',16,y,width,function() CrestCurrencyMenu(picker) end,
                function() return not P.Combat() end,P.Meta(PAGE,ID,'chooseCrestCurrencies','action',PAGE..'_sources'))
            button=P.Button(ctx,body,'Choose observed seasonal stages',16,y-40,width,function()
                SeasonStagesMenu(button)
            end,function() return not P.Combat() end,P.Meta(PAGE,ID,'chooseSeasonStages','action',PAGE..'_sources'))
            return y-80
        end,
    })
    SharedRules(ctx, b, reveal, PAGE .. "_gold", Tr("Gold across characters"),
        P.SectionRules(ID, "gold"), {
            help = "While DataTexts and this choice are enabled, MSUF remembers this character's gold at login and after money changes. Hover a Gold or Session gold DataText to see the last known account total and up to eight other characters. No background scans are used.",
            extra = function(body, y, width)
                P.Button(ctx, body, "Clear saved character gold", 16, y, width, P.ClearCharacterGold,
                    function() return type(P.Suite.RootDB) == "table" end,
                    P.Meta(PAGE, ID, "action.clearGold", "action", PAGE .. "_gold"))
                return y - 40
            end,
        })
end

local function Build(ctx)
    local b = P.W.PageBuilder(ctx)
    local navigation = P.DataTextPage.Navigation(ctx, b)
    P.ModuleCard(ctx, b, PAGE, ID, {}, { title = "DataTexts", open = false })
    P.DataTextPage.Build(ctx, b, Shared, navigation)
end

P.RegisterPage({ key = PAGE, label = "DataTexts", title = "DataTexts", build = Build, icon = { 5, 2 },
    nav = "interface", navOrder = 6,
    aliases = { "datatext", "datatexts", "data bars", "info bar", "system info" } })
