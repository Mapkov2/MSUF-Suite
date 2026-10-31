-- Chat greying remainder: a rule whose effect needs another switch is greyed
-- while that switch is off and says which one to turn on (the menu only; the
-- stored value never changes). Covers the channel shortcuts, the sidebar, the
-- input colors and the tab strip. Rules that work on their own stay open.
-- arg 2 names a mutation: the catalog loads with one link taken out and the
-- test must then fail.
local root = assert(arg[1], "repository root required")
local mutation = arg[2]
local CATALOG = "MSUF_Suite/Core/Catalog/Chat.lua"
local MUTATIONS = {
    shortcuts = { CATALOG, [[textRules.channelShortcuts.enableKey = "shortenChannels"]], "" },
    sidebar = { CATALOG, [[textRules[key].enableKey = "sidebarPanel"]], "local _ = key" },
    iconSwitch = { CATALOG, [[moved.enableKey = "sidebarPanel"]], "" },
    iconPosition = { CATALOG, [[.enableKey = moved.key]], "" },
    input = { CATALOG, [[textRules.inputColor.enableKey = "inputPanel"]], "" },
    stripGap = { CATALOG, [[textRules.tabPanelGap.enableKey = "tabPanel"]], "" },
    individual = { CATALOG, [[textRules.tabIndividualPanels.enableKey = "tabPanel"]], "" },
    individualParts = { CATALOG, [[textRules[key].enableKey = "tabIndividualPanels"]], "local _ = key" },
}
local originalLoad = loadfile
if mutation then
    local change = assert(MUTATIONS[mutation], "unknown mutation " .. mutation)
    loadfile = function(path)
        if not path:gsub("\\", "/"):find(change[1], 1, true) then return originalLoad(path) end
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local first, last = source:find(change[2], 1, true)
        assert(first, "the mutation anchor moved")
        return assert(loadstring(source:sub(1, first - 1) .. change[3] .. source:sub(last + 1), "@" .. path))
    end
end

SUITE_OPTIONS_FIXTURE = true
local F = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
local P = F.optionsNS
local function eq(a, b, label) assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local rules = P.catalog.chat.rules
local function Usable(key) return P.RuleEnabled("chat", rules[key]) end
local function Reason(key)
    local ok, why = P.RuleEnabled("chat", rules[key], nil, true)
    eq(ok, false, key .. " is not greyed")
    return why
end
local function TurnOn(switch) return ('Turn on "%s" to change this.'):format(P.Tr(rules[switch].label)) end

-- Each dependent is greyed while its switch is off, names the switch, keeps its
-- value, and opens again with the switch on; the switch itself is never greyed.
local function Links(switch, dependents)
    local stored = {}
    for _, key in ipairs(dependents) do stored[key] = P.Get("chat", key) end
    assert(P.Set("chat", switch, false))
    assert(Usable(switch), switch .. " greys itself")
    for _, key in ipairs(dependents) do
        assert(not Usable(key), key .. " stays editable while " .. switch .. " is off")
        eq(Reason(key), TurnOn(switch), key .. " reason")
        eq(P.Get("chat", key), stored[key], key .. " lost its value while greyed")
    end
    assert(P.Set("chat", switch, true))
    for _, key in ipairs(dependents) do assert(Usable(key), key .. " stays greyed with " .. switch .. " on") end
end

Links("shortenChannels", { "channelShortcuts" })

-- The sidebar: its look and its icons need the MSUF sidebar. An icon's own
-- position needs the icon moved first, and the sidebar behind that.
local SIDEBAR = { "sidebarSide", "sidebarColor", "sidebarAlpha", "sidebarGap", "scrollButtonPlace",
    "sidebarWidth", "sidebarClassColor" }
do
    local dependents = {}
    for _, key in ipairs(SIDEBAR) do dependents[#dependents + 1] = key end
    for index = 1, 5 do dependents[#dependents + 1] = "sidebarButton" .. index .. "Moved" end
    Links("sidebarPanel", dependents)
    for index = 1, 5 do
        local moved, position = "sidebarButton" .. index .. "Moved", { "sidebarButton" .. index .. "X", "sidebarButton" .. index .. "Y" }
        Links(moved, position)
        -- With the sidebar off the position is moot even while the icon is moved.
        assert(P.Set("chat", moved, true))
        assert(P.Set("chat", "sidebarPanel", false))
        for _, key in ipairs(position) do
            assert(not Usable(key), key .. " stays editable without the sidebar")
            eq(Reason(key), TurnOn("sidebarPanel"), key .. " chain")
        end
        assert(P.Set("chat", "sidebarPanel", true))
    end
    -- Blizzard's buttons are hidden with or without the MSUF sidebar.
    assert(P.Set("chat", "sidebarPanel", false))
    assert(Usable("hideNativeButtons"), "hiding Blizzard's chat buttons needs the MSUF sidebar")
    assert(P.Set("chat", "sidebarPanel", true))
end

Links("inputPanel", { "inputColor", "inputAlpha" })
do
    assert(P.Set("chat", "inputPanel", false))
    for _, key in ipairs({ "inputTop", "inputHeight", "saveInputHistory" }) do
        assert(Usable(key), key .. " needs the input background")
    end
    assert(P.Set("chat", "inputPanel", true))
end

-- The dark tab strip: the gap behind it and the individual tab backgrounds
-- need it; the individual parts need the backgrounds too, and so the strip.
do
    local parts = { "tabActiveBackground", "tabInactiveBackground", "tabActiveAlpha", "tabInactiveAlpha",
        "tabBorderSize", "tabActiveBorder", "tabInactiveBorder" }
    Links("tabPanel", { "tabPanelGap", "tabIndividualPanels" })
    assert(P.Set("chat", "tabIndividualPanels", true))
    Links("tabIndividualPanels", parts)
    assert(P.Set("chat", "tabPanel", false))
    for _, key in ipairs(parts) do
        assert(not Usable(key), key .. " stays editable without the tab strip")
        eq(Reason(key), TurnOn("tabPanel"), key .. " chain")
    end
    assert(P.Set("chat", "tabPanel", true))
    -- The tab height works with or without the strip.
    assert(P.Set("chat", "tabPanel", false))
    assert(Usable("tabHeight"), "the tab height needs the tab strip")
    assert(P.Set("chat", "tabPanel", true))
end

print("Suite chat greying remainder: " .. (mutation and ("mutation " .. mutation .. " survived") or
    "shortcuts, sidebar, input and tab strip links passed"))
