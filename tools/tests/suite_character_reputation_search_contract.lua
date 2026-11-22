local addons = assert(arg[1])
local root = addons .. "/MSUF_Suite_CharacterPanel/"
function canaccesstable(value) return type(value) == "table" end
function wipe(value) for k in pairs(value) do value[k] = nil end return value end
Enum = { ReputationSortType = { None = 0 } }
function UnitSex() return 2 end

local function Check(forever)
    local locked, writes, reads, selected, sort, legacy = false, 0, 0, 1, 2, false
    local prefs, state = {}, { groups = {}, closed = {} }
    local faults, echo, failOnce, discovered, allowVisibleReads = 0
    local now = 4
    GetTime = function() return now end
    MSUF_NS = { Client = { Flavor = "Mainline", IsForever = forever } }
    local secretText = "restricted test value"
    issecretvalue = function(value) return value == secretText end
    InCombatLockdown = function() return locked end
    UnitAffectingCombat = InCombatLockdown
    securecallfunction = function(fn, ...)
        assert(type(fn) == "function", "securecallfunction requires a function")
        local ok, a, b = pcall(fn, ...)
        if ok then return a, b end
        faults = faults + 1
    end
    local config = {}
    MSUFSuite = { Suite = { ModuleState = function() return prefs end, Config = function() return config end } }
    assert(loadfile(addons .. "/MSUF_Suite/Core/Platform.lua"))("MSUF_Suite", MSUFSuite)
    assert(loadfile(addons .. "/MSUF_Suite/Core/CharacterTabs.lua"))("MSUF_Suite", MSUFSuite)
    assert(loadfile(addons .. "/MSUF_Suite_Modules/Runtime.lua"))("MSUF_Suite_Modules", {})
    local ns = { Stats = {}, Reputation = {
            OptionsKey = function() return 0 end, Options = function() end,
            Populate = function(row, data) row.value = data.currentStanding end,
        } }
    assert(loadfile(root .. "Bootstrap.lua"))("MSUF_Suite_CharacterPanel", ns)
    local function header(name, id, nested)
        return { name = name, factionID = id, isHeader = true, isChild = nested, isCollapsed = true }
    end
    local function faction(name, id, nested)
        return { name = name, factionID = id, isChild = nested, currentStanding = 25, canToggleAtWar = true, atWarWith = false }
    end
    local home, clan, inactive = header("Alliance", -1, false), header("Guild", 25, true), header("Inactive", -1, false)
    clan.isHeaderWithRep, clan.currentStanding = true, 100
    local sun, moon, rare = faction("Sun [A]", 12, true), faction("Moon", 13, false), faction("Archive", 14, false)
    local function visible()
        local a = { home }
        if not home.isCollapsed then
            a[#a + 1] = clan
            if not clan.isCollapsed then a[#a + 1] = sun end
            a[#a + 1] = moon
        end
        if sort == 0 and (forever or legacy) then
            a[#a + 1] = inactive
            if not inactive.isCollapsed then
                a[#a + 1] = rare
                if discovered then a[#a + 1] = discovered end
            end
        end
        return a
    end
    local function change()
        assert(not locked, "native write in combat")
        writes = writes + 1
        if echo then assert(not ns.ReputationList.Update(state, "UPDATE_FACTION"), "synchronous self-refresh") end
    end
    C_Reputation = {
        GetReputationSortType = function() return sort end, SetReputationSortType = function(v) change(); sort = v end,
        AreLegacyReputationsShown = function() return legacy end,
        SetLegacyReputationsShown = function(v) assert(not forever); change(); legacy = v end,
        GetSelectedFaction = function() return selected end, SetSelectedFaction = function(v) change(); selected = v end,
        GetNumFactions = function() assert(not locked or allowVisibleReads); reads = reads + 1; return #visible() end,
        GetFactionDataByIndex = function(i)
            assert(not locked or allowVisibleReads); reads = reads + 1
            local copy = {}
            for k, v in pairs(assert(visible()[i])) do copy[k] = v end
            return copy
        end,
        GetFactionDataByID = function(id)
            assert(not locked); reads = reads + 1
            for _, data in ipairs({ clan, sun, moon, rare, discovered }) do if data.factionID == id then return data end end
        end,
        ExpandFactionHeader = function(i)
            change()
            visible()[i].isCollapsed = false
            selected = 0
            if failOnce then failOnce = false; error("injected after expansion") end
        end,
        CollapseFactionHeader = function(i) change(); visible()[i].isCollapsed = true end,
        ToggleFactionAtWar = function(i) change(); assert(visible()[i] == sun); sun.atWarWith = true end,
    }
    for _, file in ipairs({ "ReputationList", "ReputationSearch", "Pages" }) do
        assert(loadfile(root .. file .. ".lua"))("MSUF_Suite_CharacterPanel", ns)
    end
    echo = true
    ns.ReputationList.Paint({ config = {}, reputations = state, view = { ShowGroups = function(_, groups, combat, catalog)
        assert(groups == state.groups and not combat and catalog == state)
    end } }, false)
    local parent, child, archived = unpack(state.groups)
    assert(#state.groups == 3 and #parent.rows == 1 and parent.rows[1].label == "Moon")
    assert(#child.rows == 2 and child.rows[1].factionName == "Guild" and child.rows[2].factionID == 12)
    assert(archived.rows[1].label == "Archive" and home.isCollapsed and clan.isCollapsed and inactive.isCollapsed)
    assert(selected == 1 and sort == 2 and legacy == false)
    local priorWrites = writes
    now = now + 3
    assert(ns.ReputationList.Update(state, "UPDATE_FACTION"))
    assert(ns.ReputationList.Update(state, "UPDATE_FACTION"))
    sun.currentStanding, clan.currentStanding = 79, 175
    ns.Pages.Read("reputation", state.groups, {}, state)
    assert(writes == priorWrites and child.rows[2].value == 79 and child.rows[1].value == 175, "echo rescanned or lost new standings")
    local oldRows = state.rows
    failOnce = true
    ns.Pages.Read("reputation", state.groups, {}, state)
    assert(faults == 1 and state.rows == oldRows and sort == 2 and selected == 1 and home.isCollapsed and not legacy,
        "partial scan replaced the snapshot or left native filters changed")
    discovered = faction("Newcomers", 222, false)
    assert(ns.ReputationList.Update(state, "FACTION_STANDING_CHANGED", 222))
    ns.Pages.Read("reputation", state.groups, {}, state)
    assert(state.ids[222] and archived.rows[2].label == "Newcomers" and inactive.isCollapsed)
    ns.ReputationList.ToggleHiddenWar(12)
    assert(sun.atWarWith and selected == 1 and home.isCollapsed and clan.isCollapsed)
    locked = true
    priorWrites = writes
    ns.ReputationList.ToggleHiddenWar(12)
    assert(writes == priorWrites)
    locked = false
    local beforeReads = reads
    local list = ns.ReputationList
    state.closed.Alliance = true
    local projected = list.Project(state, state.groups)
    assert(#projected == 2 and #projected[1].rows == 0)
    state.query = list.Query("  [a] ")
    projected = list.Project(state, state.groups)
    assert(#projected == 2 and projected[1].title == "Alliance" and projected[2].rows[1].factionID == 12)
    state.query = list.Query("Alliance")
    assert(#list.Project(state, state.groups) == 2)
    state.query = "no such faction"
    assert(list.Project(state, state.groups)[1].title == "No results")
    state.query = ""
    assert(#list.Project(state, state.groups) == 2 and #child.rows == 2 and reads == beforeReads)

    -- Drive the edit box and drag handlers, including a combat edge before a drop.
    local widget = {}
    widget.__index = widget
    local function new() return setmetatable({ scripts = {} }, widget) end
    for _, key in ipairs({ "SetSize", "SetMovable", "SetClampedToScreen", "SetFrameLevel", "SetAutoFocus",
        "SetMaxLetters", "SetFontObject", "RegisterForClicks", "RegisterForDrag", "ClearAllPoints", "StartMoving", "StopMovingOrSizing" }) do
        widget[key] = function() end
    end
    function widget:SetScript(key, fn) self.scripts[key] = fn end
    function widget:SetPoint(...) self.point = {...} end
    function widget:SetShown(v) self.shown = v end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
    function widget:SetFocus() self.focus = true end
    function widget:ClearFocus() self.focus = false end
    function widget:SetText(v) self.text = v; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
    function widget:GetText() return self.text end
    function widget:GetWidth() return 600 end
    function widget:GetHeight() return 400 end
    function widget:GetLeft() return self.left or 100 end
    function widget:GetBottom() return self.bottom or 50 end
    function widget:GetEffectiveScale() return .8 end
    function widget:GetFrameLevel() return 10 end
    local grip
    ns.Window = { CreateChild = function(_, kind)
        local frame = new()
        if kind == "Button" then grip = frame end
        return frame
    end }
    local style = { Panel = new, Font = new, Texture = new, Tint = function() end,
        Button = function(_, _, _, fn) local frame = new(); frame:SetScript("OnClick", fn); return frame end }
    local paints = 0
    local view = { frame = new(), footer = new(), report = { scroll = new() }, ShowGroups = function(v, groups, combat, s, reset)
        assert(not locked and not combat and groups == state.groups and s == state and reset)
        ns.ReputationSearch.Show(v, s, style)
        paints = paints + 1
    end }
    ns.ReputationSearch.Show(view, state, style)
    local control = view.reputationSearch
    control.edit:SetText("[A]")
    assert(paints == 1 and state.query == "[a]" and control.clear.shown and not control.hint.shown and control.count.text == "1 / 5")
    control.clear.scripts.OnClick()
    assert(paints == 2 and state.query == "" and control.edit.focus and control.hint.shown)
    grip.scripts.OnDragStart()
    control.left, control.bottom = 2000, -100
    grip.scripts.OnDragStop()
    assert(prefs.reputationSearchX == 1 and prefs.reputationSearchY == 0)
    grip.scripts.OnDragStart()
    locked = true
    ns.ReputationSearch.Hide(view)
    control.edit:SetText("stop")
    assert(not control.dragging and not control.edit.focus and not control.shown and paints == 2 and reads == beforeReads)
    locked = false
    ns.ReputationSearch.Show(view, state, style)
    grip.scripts.OnClick()
    assert(prefs.reputationSearchX == nil and prefs.reputationSearchY == nil and control.edit.text == "")

    local definition = { cards = { { title = "My factions", rows = { { source = "reputationReport", label = "" } } } } }
    definition.id, definition.name = "custom1", "My report"
    config.customTabs = assert(MSUFSuite.CharacterTabs.Encode({ definition }))
    local plan, report = ns.Pages.CustomPlan(definition), {}
    local custom = { config = {}, searchState = { tab = "custom1", query = "newcomers", groups = report } }
    ns.Pages.Custom(report, plan, custom, false)
    local afterRead = reads
    local result = ns.ReputationSearch.Show(view, custom.searchState, style)
    assert(#result == 1 and #result[1].rows == 1 and result[1].rows[1].label == "Newcomers"
        and reads == afterRead and inactive.isCollapsed and home.isCollapsed and sort == 2)
    grip.scripts.OnDragStart()
    grip.scripts.OnDragStop()
    assert(prefs.tabSearchPositions.custom1.reputationSearchX == 1 and not prefs.reputationSearchX)
    ns.ReputationSearch.Show(view, { tab = "skills", groups = {} }, style)
    grip.scripts.OnClick()
    assert(prefs.tabSearchPositions.custom1.reputationSearchX == 1, "another tab reset the custom position")
    result = ns.ReputationSearch.Show(view, { tab = "custom2", query = "restricted",
        groups = { { title = "Stats", rows = { { label = "Health", value = secretText } } } } }, style)
    assert(result[1].title == "No results", "search matched a secret string")
    local afterWrites = writes
    ns.Pages.InvalidateCustom(plan, "UPDATE_FACTION", custom.searchState)
    ns.Pages.Custom(report, plan, custom, false)
    assert(writes == afterWrites, "custom tab expanded factions again on its own update")
    locked = true
    ns.Pages.InvalidateCustom(plan, "UPDATE_FACTION")
    afterRead = reads
    ns.Pages.Custom(report, plan, custom, true)
    assert(reads == afterRead and writes == afterWrites, "custom search scanned factions in combat")
    allowVisibleReads = true
    local plain = ns.Pages.CustomPlan({ cards = definition.cards })
    ns.Pages.Custom({}, plain, { config = {} }, true)
    local plainReads = reads - afterRead
    local cold = ns.Pages.CustomPlan({ cards = definition.cards })
    local coldState = { config = {}, searchState = { tab = "custom1" } }
    ns.Pages.Custom({}, cold, coldState, true)
    assert(plainReads > 0 and reads - afterRead == 2 * plainReads and writes == afterWrites and not coldState.searchState.catalog,
        "first combat open did not use just the ordinary visible faction rows")
end
Check(true)
Check(false)
print("Complete faction tree, search, native restore, drag and combat input passed on Forever and Retail")
