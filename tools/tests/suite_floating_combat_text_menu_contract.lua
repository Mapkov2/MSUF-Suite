local root = assert(arg[1], "repository root required")
local ID = "floatingCombatText"
local function Load(path, ns)
    assert(loadfile(root .. "/" .. path))("MSUF_Suite", ns)
end

local Frame = {}
Frame.__index = Frame
local function New(parent) return setmetatable({ parent = parent, shown = true }, Frame) end
function Frame:SetWidth(width) self.width = width end
function Frame:SetHeight(height) self.height = height end
function Frame:GetHeight() return self.height or 26 end
function Frame:GetStringHeight() return 16 end
function Frame:SetShown(shown) self.shown = shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:ClearAllPoints() end
function Frame:SetPoint(...) self.anchor = { ... } end
function Frame:HookScript(script, callback) self[script] = callback end
CreateFrame = function(_, _, parent) return New(parent) end

local SECTION_NAMES = { "floating_combat_text", "floating_combat_text_hits", "floating_combat_text_gains" }
local GAIN_KEYS = { "showXP", "showLevelUp", "showReputation", "showHonor", "showPower" }

local function Run(forever)
    local ns = { Client = { isForever = forever }, Text = function(text) return text end }
    Load("MSUF_Suite/Core/SuiteCatalog.lua", ns)
    Load("MSUF_Suite/Core/Catalog/QualityOfLifeCombatText.lua", ns)
    local spec = ns.SuiteCatalog[ID]
    local sections, values = {}, {}
    for _, section in ipairs(SECTION_NAMES) do
        local rules = {}
        for _, rule in pairs(spec.rules) do
            if rule.section == section then
                rules[#rules + 1] = rule
                values[rule.key] = rule.default
            end
        end
        sections[#sections + 1] = { key = section, rules = rules }
    end

    local actions, batches, controls, sizes, sampleTabs = {}, {}, {}, {}, {}
    local combat, choose, picker, tabs = false
    local P = { catalog = ns.SuiteCatalog, Tr = ns.Text, M = {} }
    P.Combat = function() return combat end
    P.Get = function(_, key) return values[key] end
    P.RuleEnabled = function(_, _, _, _, editWhileOff) return not combat and editWhileOff end
    P.SetMany = function(id, batch)
        assert(id == ID and not combat)
        batches[#batches + 1] = batch
        for key, value in pairs(batch) do values[key] = value end
    end
    P.Button = function(_, panel, label, _, _, _, onClick, enabled)
        local button = New(panel)
        button.click, button.enabled = onClick, enabled
        actions[label] = button
        return button
    end
    P.M.AddTooltip = function(button, _, _, opts) button.tooltip = opts.enabled end
    P.Text = function() return New() end
    P.RuleGrid = function(_, panel, page, id, rules, y, _, _, section)
        assert(page == "gameplay" and id == ID and section == "fct")
        local entries = {}
        for _, rule in ipairs(rules) do entries[#entries + 1] = { widget = New(panel), rule = rule } end
        return y - #rules * 34, entries
    end
    Load("MSUF_Suite_Options/Menu/Workspace.lua", P)
    P.MenuWorkspace.WrappingTabs = function(state, items, select)
        picker, tabs, choose = state, items, select
        return New(state.header), select
    end
    Load("MSUF_Suite_Options/Pages/FloatingCombatTextSettings.lua", P)
    local preview = { BuildSamples = function(_, tab, y)
        sampleTabs[tab] = true
        return tab == "appearance" and y or y - 29
    end }
    local bottom = P.BuildFloatingCombatTextSettings({}, New(), -330, 540, "gameplay", "fct", sections, preview,
        function(entries, prepare)
            for _, entry in ipairs(entries) do
                local key = entry.rule.key
                assert(not controls[key], "duplicated " .. key)
                controls[key] = { widget = entry.widget, prepare = prepare }
            end
        end, function(height) sizes[#sizes + 1] = height end)
    for key in pairs(values) do assert(controls[key], "lost setting " .. key) end
    assert(#tabs == 4 and picker.selected == "appearance" and bottom < -330)
    assert(sampleTabs.appearance and sampleTabs.hits and sampleTabs.gains and sampleTabs.combat)
    assert(controls.font.widget:IsVisible() and not controls.showHits.widget:IsVisible())

    local enable, disable = actions["Enable all"], actions["Disable all"]
    assert(not enable:IsVisible() and not disable:IsVisible())
    controls.xpSide.prepare()
    assert(picker.selected == "gains" and enable:IsVisible() and disable:IsVisible())
    assert(enable.enabled() and disable.enabled())
    enable.click()
    assert(#batches == 1 and not enable.enabled() and disable.enabled())
    for _, key in ipairs(GAIN_KEYS) do assert(values[key] == true, key) end
    enable.click()
    assert(#batches == 1, "unchanged gains must not write")
    if forever then values.hideBlizzardWorldText = true end
    disable.click()
    assert(#batches == 2 and not disable.enabled())
    for _, key in ipairs(GAIN_KEYS) do assert(values[key] == false, key) end
    assert(values.showHits == true and values.showCombatState == false and values.hideBlizzard == forever)
    if forever then
        assert(values.hideBlizzardWorldText == true and disable.tooltip() == true,
            "bulk disable must preserve and explain the force-XP exception")
        controls.hideBlizzardWorldText.prepare()
        assert(picker.selected == "hits" and controls.hideBlizzardWorldText.widget:IsVisible())
    else
        assert(values.hideBlizzardWorldText == nil)
    end
    controls.combatSide.prepare()
    assert(picker.selected == "combat" and controls.showCombatState.widget:IsVisible() and not enable:IsVisible())
    assert(#sizes > 0 and sizes[#sizes] > bottom, "the shorter Combat tab should shrink its section")
    choose("gains")
    combat = true
    enable.click()
    assert(#batches == 2 and not enable.enabled(), "combat must block profile writes")
end

Run(false)
Run(true)
print("Floating combat text tabs, exact routes, preserved controls, and bulk gains passed on both clients")
