-- Real source-details picker through Dialogs' Forever gamepad list, plus
-- the native menu-description response contract used outside that list.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_gamepad_openers_contract.lua", "rb"))
local fixture = file:read("*a"); file:close()
local stop = assert(fixture:find('Case("core", function()', 1, true))
local World = assert(loadstring(fixture:sub(1, stop - 1) .. "\nreturn World\n", "@currency_gamepad_fixture"))()

local function New(gamepad)
    local W = World(gamepad and "Forever" or "Mainline", gamepad)
    local config = { barIds = {1}, bar1Slot1 = 1, bar1Slot1Currency = 10 }
    W.Suite.DataTextSourceKeys = { "currency" }
    local state = { expanded = false, calls = 0, writes = 0, config = config, world = W }
    W.G.C_CurrencyInfo = {
        GetCurrencyListSize = function() return state.expanded and 2 or 1 end,
        GetCurrencyListInfo = function(index)
            if index == 1 then
                return { name = "Native season", isHeader = true, isHeaderExpanded = state.expanded }
            end
            return { name = "Discovered token", isHeader = false }
        end,
        GetCurrencyListLink = function(index) return index == 2 and "currency:20" end,
        GetCurrencyIDFromLink = function(link) return tonumber(link:match("%d+")) end,
        ExpandCurrencyList = function(index, expanded)
            assert(index == 1)
            state.expanded, state.calls = expanded, state.calls + 1
        end,
    }
    if not gamepad then
        W.G.MenuUtil.CreateContextMenu = function(owner, generator)
            local menu = { rows = {}, SetScrollMode = function() end, CreateTitle = function() end }
            function menu:CreateButton(text, callback)
                local row = { text = text, callback = callback }
                function row:SetResponse(response) self.response = response end
                self.rows[#self.rows + 1] = row
                return row
            end
            function menu:CreateRadio(text, selected, callback)
                local row = self:CreateButton(text, callback)
                row.selected = selected
                return row
            end
            generator(owner, menu)
            return menu
        end
    end
    local P = { Suite = W.Suite, S = { Config = function() return config end }, T = {}, HM = {},
        Tr = function(value) return value end, Combat = function() return W.combat end,
        M = { TrackRefresh = function(_, callback) callback() end }, Meta = function() return {} end,
        Get = function(_, key) return config[key] end,
        Set = function(_, key, value)
            config[key], state.writes = value, state.writes + 1
            return true
        end,
        SetButtonText = function(widget, value) widget.text = value end,
        ContextMenu = function(...)
            state.panel = W.S.ContextMenu(...)
            return state.panel
        end,
        Button = function(_, parent, _, _, _, _, callback)
            state.button = W.New("Button", nil, parent)
            state.button:SetScript("OnClick", callback)
            return state.button
        end,
    }
    setfenv(assert(loadfile(root .. "/MSUF_Suite_Options/Pages/DataTextsSourcePicker.lua")), W.G)("Options", P)
    P.DataTextsSourcePicker.BuildDetails({}, W.UIParent, 1, 1, "test", 0, 300)
    function state:Open() W.Click(self.button) end
    function state:Row(text)
        for _, row in ipairs(self.panel.rows) do
            local label = gamepad and row.label.text or row.text
            if (not gamepad or row.shown) and label and label:find(text, 1, true) then return row end
        end
    end
    function state:Pick(text)
        local row = assert(self:Row(text), "missing currency menu row: " .. text)
        if gamepad then W.Click(row) else row.callback() end
    end
    function state:Navigable()
        assert(self.panel:IsShown() and W.padNavigation.Top() == self.panel,
            "currency header closed the rebuilt picker or released gamepad navigation")
    end
    return state
end

local state = New(true)
state:Open()
state:Navigable()
state:Pick("Native season +")
assert(state.expanded and state.calls == 1 and state.writes == 0)
state:Navigable()
assert(state:Row("Discovered token"), "expanded currency must be selectable")
state:Pick("Native season -")
assert(not state.expanded and state.calls == 2 and state.writes == 0)
state:Navigable()
assert(not state:Row("Discovered token"), "collapse must remove the discovered currency row")
state:Pick("Native season +")
assert(state.calls == 3 and state.writes == 0)
state:Navigable()
state:Pick("Discovered token")
assert(state.config.bar1Slot1Currency == 20 and state.writes == 1, "currency must commit exactly once")
assert(not state.panel:IsShown() and state.world.padNavigation.Top() == nil, "selection must close and release navigation")

-- A stale header and a stale currency callback must never mutate a replacement profile.
state = New(true)
state:Open()
state.world.Suite.DB = {}
state:Pick("Native season +")
assert(not state.expanded and state.calls == 0 and state.writes == 0, "stale profile expanded native data")
state = New(true)
state:Open()
state:Pick("Native season +")
state.world.Suite.DB = {}
state:Pick("Discovered token")
assert(state.config.bar1Slot1Currency == 10 and state.writes == 0, "stale profile accepted currency selection")

-- Native MenuElementDescriptionProxyMixin:Pick consumes SetResponse; its
-- MenuResponse.Open preserves the menu after a header callback regenerates it.
state = New(false)
state:Open()
assert(state:Row("Native season +").response == state.world.G.MenuResponse.Open, "native header lacks Open response")
state:Pick("Native season +")
assert(state.expanded and state.calls == 1 and state.writes == 0)
assert(state:Row("Native season -").response == state.world.G.MenuResponse.Open, "native expanded header lacks Open response")
state:Pick("Native season -")
assert(not state.expanded and state.calls == 2 and state.writes == 0)
state:Pick("Native season +")
state:Pick("Discovered token")
assert(state.config.bar1Slot1Currency == 20 and state.writes == 1)
print("currency source picker: expand/collapse navigation, single selection, stale profile and native response passed")
