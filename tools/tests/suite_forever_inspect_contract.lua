local root = assert(arg[1])
local calls = {}
local function noop() end
local chrome = {
    Spec = function() return {} end,
    Fade = noop, Attach = function() return true end,
    FadeNineSlice = noop, FadePortraits = noop, SkinInset = noop,
}
chrome.New = function(options)
    local panel = { owners = {}, exactSlots = {}, SkinAllSlots = noop, ScheduleLoad = noop }
    panel.Activate = function()
        local state = { active = true, owner = "audit" }
        options.initState(state)
        return options.applyNow(state)
    end
    return panel
end
local ns = {
    PaperDollChrome = chrome,
    Safety = { Field = function(t, k) return type(t) == "table" and t[k] or nil end, Call = noop, Public = function() return true end },
    AdapterKit = { SkinControl = function(_, target) if target then calls[target] = true end return true end },
    Client = { isForever = true },
    IsCombatLocked = function() return false end,
    CharacterDetails = { Apply = noop }, WindowControls = { Attach = noop },
}
local character, pvp, guild = { checked = false }, { checked = true }, { checked = false }
InspectFrame = { ModeTabs = { CharacterTab = character, PvPTab = pvp, GuildTab = guild } }
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/InspectPanel.lua"))("MSUF_Suite_Skin", ns)
assert(ns.InspectPanel.Apply())
assert(calls[character] and calls[guild], "existing Inspect tab skin path did not run")
assert(calls[pvp], "Forever Inspect PvP tab stayed unskinned")
assert(pvp.checked and not character.checked and not guild.checked,
    "Inspect skin changed the native selected tab")
calls = {}
InspectFrame.ModeTabs.PvPTab = nil
assert(ns.InspectPanel.Apply() and calls[character] and calls[guild],
    "older Forever Inspect tabs did not skin without PvPTab")
print("Forever Inspect: all mode tabs, native selection and older builds passed")
