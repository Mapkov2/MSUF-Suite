local root = assert(arg[1], "repository root required")
local actions, page, combat = {}, nil, false
local menu = { shown = true, hides = 0 }
function menu:Hide() self.shown = false; self.hides = self.hides + 1 end
local calls = {}
local summary = { active = true }
function summary:Preview(kind)
    calls[#calls + 1] = kind
    assert(menu.shown, "preview is dispatched before the normal menu dismissal")
end
function summary:ShowLast() calls[#calls + 1] = "last" end
function summary:ClearHistory() calls[#calls + 1] = "clear" end
local P = {
    S = { instances = { runSummary = summary }, catalog = {
        runSummary = { rules = { showMythicPlus = {} } } } },
    M = { frame = menu }, W = { PageBuilder = function() return {} end },
    Tr = function(text) return text end,
    Combat = function() return combat end,
    SectionRules = function() return {} end,
    RuleSection = function() end,
    Help = function(a) return a end,
    RegisterPage = function(spec) page = spec end,
    ModuleCard = function(_, _, _, id, entries)
        if id == "runSummary" then
            for _, action in ipairs(entries) do actions[action.key] = action[2] end
        end
    end,
}
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/HUD.lua"))("MSUF_Suite_Options", P)
page.build({})
actions.preview_raid()
assert(calls[1] == "raid" and not menu.shown and menu.hides == 1,
    "raid preview must dismiss the options window that otherwise obscures the result")
menu.shown = true
actions.preview_mythic()
assert(calls[2] == "mythic" and not menu.shown and menu.hides == 2,
    "the equivalent Mythic+ preview must present its on-screen result too")
menu.shown, combat = true, true
actions.preview_raid()
assert(menu.shown and #calls == 2 and menu.hides == 2,
    "a combat-blocked preview must not dismiss the menu")
combat, summary.active = false, false
actions.preview_raid()
assert(menu.shown and #calls == 2, "inactive module must leave the menu open")
summary.active = true
local preview = summary.Preview
summary.Preview = nil
actions.preview_raid()
assert(menu.shown and #calls == 2, "unavailable runtime preview must leave the menu open")
summary.Preview = preview
actions.last()
assert(menu.shown and calls[3] == "last", "non-preview menu actions retain their existing behavior")
-- Clearing the run history asks first through MSUF's popup helper.
local dialogs, shown = {}, nil
YES, NO = "Yes", "No"
P.M.InstallStaticPopup = function(name, spec) dialogs[name] = spec end
StaticPopup_Show = function(name, _, _, data) shown = { name = name, data = data } end
actions.clear_history()
assert(#calls == 3 and shown and dialogs[shown.name] and dialogs[shown.name].button1 == "Yes",
    "clearing the run history did not ask first")
-- The question is the Suite's own wording.
assert(dialogs[shown.name].text == "Erase this character's Mythic+ history? The removed runs cannot be restored.",
    "the run history question lost its own wording")
dialogs[shown.name].OnAccept(nil, shown.data)
assert(calls[4] == "clear", "confirming did not clear the run history")
P.M.InstallStaticPopup = nil
actions.clear_history()
assert(calls[5] == "clear", "a host without the popup helper must still clear the history")
calls[4], calls[5] = nil, nil
P.S.catalog.runSummary.rules.showMythicPlus = nil
actions = {}
page.build({})
assert(actions.preview_raid and not actions.preview_mythic, "Forever retains only its supported preview action")
actions.preview_raid()
assert(not menu.shown and calls[4] == "raid", "Forever raid preview dismisses the menu")
menu.shown, P.M.frame = true, nil
actions.preview_raid()
assert(calls[5] == "raid" and menu.hides == 3,
    "a host without an exported menu frame still dispatches the preview")
P.M.frame = {}
actions.preview_raid()
assert(calls[6] == "raid" and menu.hides == 3,
    "a host without the optional Hide method still dispatches the preview")
print("HUD explicit result preview menu dismissal and unavailable/combat guards passed")
