-- Chat audit: the keyword notices follow the instance group's chat, the other
-- chat addons count as conflicts, a setting is greyed while the switch it
-- depends on is off (the menu only, never the stored value), and the locked
-- main window has an Edit Mode mover.
local root = assert(arg[1])
SUITE_OPTIONS_FIXTURE = true
local F = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
local P, S, Suite = F.optionsNS, F.S, F.Suite
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local function eq(a, b, label) assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local CONFLICTS = { "EllesmereUIChat", "ElvUI", "Glass", "Glassy", "Prat-3.0", "Chattynator", "Chatter" }

------------------------------------------------------------------ conflicts
-- Any of these chat addons switches the module off; the module's own late
-- load handler (Controller.lua) is checked below against the same list.
do
    local original = Suite.Client.IsAddOnLoaded
    assert(S.Availability("chat"), "harness: the chat module is unavailable without a conflict")
    for _, name in ipairs(CONFLICTS) do
        Suite.Client.IsAddOnLoaded = function(addon) return addon == name or original(addon) end
        local ok, why = S.Availability("chat")
        eq(ok, false, name .. " does not switch the chat module off")
        eq(why, "Managed by " .. name, name .. " status")
    end
    Suite.Client.IsAddOnLoaded = original
end

------------------------------------------------------------------ dependent settings
-- A rule with a switch is greyed while the switch is off and says which one to
-- turn on; flipping the switch never rewrites the stored value of the rule.
local rules = P.catalog.chat.rules
local function Usable(key) return P.RuleEnabled("chat", rules[key]) end
local function Reason(key)
    local ok, why = P.RuleEnabled("chat", rules[key], nil, true)
    eq(ok, false, key .. " is not greyed")
    return why
end
local function Links(switch, dependents)
    local stored = {}
    for _, key in ipairs(dependents) do stored[key] = P.Get("chat", key) end
    assert(P.Set("chat", switch, false))
    assert(Usable(switch), switch .. " greys itself")
    for _, key in ipairs(dependents) do
        assert(not Usable(key), key .. " stays editable while " .. switch .. " is off")
        eq(Reason(key), ('Turn on "%s" to change this.'):format(P.Tr(rules[switch].label)), key .. " reason")
        eq(P.Get("chat", key), stored[key], key .. " lost its value while greyed")
    end
    assert(P.Set("chat", switch, true))
    for _, key in ipairs(dependents) do assert(Usable(key), key .. " stays greyed with " .. switch .. " on") end
end

Links("lockWindowSize", { "windowWidth", "windowHeight" })
Links("lockWindowPosition", { "windowX", "windowY" })
Links("saveHistory", { "historyLines" })
Links("allTimestamps", { "timestampFormat" })
Links("copyMessages", { "copyButtonX", "copyButtonY" })

-- The idle fade is a delay where 0 means off, not a switch.
do
    assert(P.Set("chat", "idleSeconds", 0))
    assert(Usable("idleSeconds"), "the fade delay greys itself")
    for _, key in ipairs({ "idleAlpha", "idleFadeDuration" }) do
        assert(not Usable(key), key .. " stays editable without a fade delay")
    end
    assert(P.Set("chat", "idleSeconds", 12))
    for _, key in ipairs({ "idleAlpha", "idleFadeDuration" }) do
        assert(Usable(key), key .. " stays greyed with a fade delay")
    end
end

-- Speech bubbles: the shared look and each source's MSUF look need the
-- styling; a source's own look needs its MSUF look, and each part of it the
-- own look. A part follows the whole chain, not only its own switch.
do
    local shared = { "bubbleFont", "bubbleFontSize", "bubbleTextColor", "bubbleBackground", "bubbleAlpha",
        "bubbleBorder", "bubblePadding", "bubbleMaxWidth" }
    local parts = { "bubbleFont", "bubbleSize", "bubbleText", "bubbleFill", "bubbleOpacity", "bubbleEdge",
        "bubblePad", "bubbleWidth" }
    local sources = P.Suite.ChatBubbleSources
    assert(#sources > 0, "harness: no bubble source")
    local styles = {}
    for _, source in ipairs(sources) do styles[#styles + 1] = "bubbleStyle" .. source.key end
    for _, key in ipairs(shared) do styles[#styles + 1] = key end
    Links("styleBubbles", styles)
    assert(Usable("hideInstanceBubbles"), "turning bubbles off inside instances needs no bubble styling")
    for _, source in ipairs(sources) do
        local own, style, ownParts = "bubbleOwn" .. source.key, "bubbleStyle" .. source.key, {}
        for _, part in ipairs(parts) do ownParts[#ownParts + 1] = part .. source.key end
        Links(style, { own })
        Links(own, ownParts)
        -- With the styling off the own look is moot even while its switches are on.
        assert(P.Set("chat", "styleBubbles", false))
        for _, key in ipairs(ownParts) do
            assert(not Usable(key), key .. " stays editable without bubble styling")
            eq(Reason(key), ('Turn on "%s" to change this.'):format(P.Tr(rules.styleBubbles.label)), key .. " chain")
        end
        assert(P.Set("chat", "styleBubbles", true))
    end
end

------------------------------------------------------------------ chat module and mover
-- Controller.lua on its own, over the real catalog and the real Edit Mode
-- element registration (MSUF_Suite_Modules/EditMode.lua).
local config, catalogNS = Support.CatalogDefaults(root, "chat")
local registered, applied, events, combat = {}, {}, {}, false
local ns = { DB = {}, IsCombatLocked = function() return combat end,
    Safety = { IsForbidden = function() return false end } }
local suite = { catalog = catalogNS.SuiteCatalog, states = { chat = { active = true } }, instances = {},
    Text = function(text) return text end, Config = function() return config end,
    Finite = function(value) return type(value) == "number" and value == value end,
    Apply = function(id) applied[#applied + 1] = id end,
    Dispatch = function(callback, ...) return callback(...) end }
function suite.SetMany(_, values) for key, value in pairs(values) do config[key] = value end return true end
function suite.Set(id, key, value) return suite.SetMany(id, { [key] = value }) end
function suite.CommitEditPosition(id, values) return not combat and suite.SetMany(id, values) end
MSUF_EditModeAPI = {
    RegisterElement = function(owner, element) registered[owner .. "/" .. element.id] = element return true end,
    RegisterSessionListener = function() end, IsActive = function() return false end,
}
assert(loadfile(root .. "/MSUF_Suite_Modules/EditMode.lua"))("test", { NS = ns, Suite = suite })

-- Window handling is the Window.lua file's business; the controller only
-- needs these to start.
local chat = { M = {}, DockGeometry = function() end, DockSelection = function() end,
    MessagesRefresh = function() end, BubblesRefresh = function() end,
    ListenInCombat = function(context, event, callback) context:Event(event, callback) end }
function suite.Install(id, module) eq(id, "chat"); eq(module, chat.M, "installed module") end
hooksecurefunc = function() end
Constants = { ChatFrameConstants = { MaxChatWindows = 0 } }
CHAT_FRAMES = {}
assert(loadfile(root .. "/MSUF_Suite_Chat/Controller.lua"))("MSUF_Suite_Chat", { NS = ns, Suite = suite, Chat = chat })
local module = chat.M
module.config, module.active = config, true
module.context = {
    Event = function(_, event, callback) events[event] = callback end,
    RemoveEvent = function(_, event) events[event] = nil end,
}
module:Enable()

-- Every conflict of the catalog that loads after the module takes it out of
-- service; unrelated addons do not.
for _, name in ipairs(catalogNS.SuiteCatalog.chat.conflicts) do
    applied = {}
    events.ADDON_LOADED(module, "ADDON_LOADED", name)
    eq(#applied, 1, name .. " loading late did not re-evaluate the chat module")
    eq(applied[1], "chat", name .. " re-evaluated another module")
end
assert(#catalogNS.SuiteCatalog.chat.conflicts == #CONFLICTS, "the conflict list changed: update the contract")
applied = {}
events.ADDON_LOADED(module, "ADDON_LOADED", "Details")
eq(#applied, 0, "an unrelated addon re-evaluated the chat module")

-- The mover: the main window's position belongs to the Suite while it is
-- anchored, as offsets of its bottom left corner from the screen's.
local frame = { points = {} }
function frame:GetScale() return 1 end
function frame:ClearAllPoints() self.points = {} end
function frame:SetPoint(...) self.points = { ... } end
ChatFrame1 = frame
UIParent = UIParent or {}
module:RegisterMovers()
local element = registered["MSUFSuite.chat/window"]
assert(element, "the chat window has no Edit Mode mover")
eq(element.label, "Chat window", "mover label")
assert(not element.isEnabled(), "a mover for a window Blizzard's Edit Mode still owns")
config.lockWindowPosition, config.windowX, config.windowY = true, 12, 12
assert(element.isEnabled(), "no mover for the anchored window")
local controls = {}
for _, control in ipairs(element.extraControls) do controls[control.id] = control end
local ruleX, ruleY = catalogNS.SuiteCatalog.chat.rules.windowX, catalogNS.SuiteCatalog.chat.rules.windowY
eq(controls.windowX.max, ruleX.max, "X field range")
eq(controls.windowY.min, ruleY.min, "Y field range")
local state = element.captureState()
assert(element.movePosition({ state = state, deltaX = 30, deltaY = -10, phase = "drag" }), "drag refused")
eq(frame.points[1], "BOTTOMLEFT", "anchor point")
eq(frame.points[2], UIParent, "anchor frame")
eq(frame.points[3], "BOTTOMLEFT", "anchor frame point")
eq(frame.points[4], 42, "dragged X")
eq(frame.points[5], 2, "dragged Y")
eq(config.windowX, 12, "a drag preview wrote the saved position")
assert(element.movePosition({ state = state, deltaX = 30, deltaY = -10, phase = "commit" }), "commit refused")
eq(config.windowX, 42, "committed X")
eq(config.windowY, 2, "committed Y")
assert(element.restoreState(state), "undo refused")
eq(config.windowX, 12, "undone X")
config.lockWindowPosition = false
assert(not element.isEnabled(), "the mover stays after the anchor went off")
config.lockWindowPosition, suite.states.chat.active = true, false
assert(not element.isEnabled(), "the mover of a stopped module stays")

------------------------------------------------------------------ keyword notices
-- A random dungeon, raid finder or battleground group talks on the instance
-- chat events; they count as raid chat while that group is a raid and as party
-- chat otherwise. The group is asked only when a phrase matched.
local SECRET = setmetatable({}, { __tostring = function() error("secret formatted") end })
local clock, printed, asked = 1000, {}, {}
local homeRaid, instanceRaid = false, false
GetTime = function() return clock end
wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
IsInRaid = function(category)
    asked[#asked + 1] = category
    if category == LE_PARTY_CATEGORY_INSTANCE then return instanceRaid end
    return homeRaid
end
local alerts
local keywordSuite = {
    Text = function(text) return text end,
    PublicText = function(value) if value ~= SECRET and type(value) == "string" then return value end end,
    Finite = function(value) return value ~= SECRET and type(value) == "number" and value == value end,
    Print = function(text) printed[#printed + 1] = text end,
    Notifications = { Push = function() return true end },
    ToolListWindow = { Close = function() end, Edit = function() end },
    Install = function(_, module) alerts = module end,
}
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/KeywordAlerts.lua"))("MSUF_Suite_QualityOfLife",
    { NS = {}, Suite = keywordSuite })
local listening = {}
local function Start(settings)
    local base = { words = "ready", party = false, raid = false, guild = false, say = false, channels = false,
        cooldown = 30, sound = false }
    for key, value in pairs(settings) do base[key] = value end
    for event in pairs(listening) do listening[event] = nil end
    printed, asked = {}, {}
    alerts.config = base
    alerts.context = {
        Event = function(_, event, callback) listening[event] = callback end,
        RemoveEvent = function(_, event) listening[event] = nil end,
    }
    alerts:Enable()
    return base
end
local function Say(event, text)
    local callback = listening[event]
    assert(callback, event .. " is not watched")
    callback(alerts, event, text, "Tank")
end
local INSTANCE_EVENTS = { "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }

-- Party chat covers the instance group while it is a party.
Start({ party = true })
for _, event in ipairs(INSTANCE_EVENTS) do assert(listening[event], event .. " is not watched with party chat on") end
instanceRaid = false
Say("CHAT_MSG_INSTANCE_CHAT", "Ready check")
eq(#printed, 1, "a dungeon finder group's chat was not noticed")
eq(asked[1], LE_PARTY_CATEGORY_INSTANCE, "the group type asked about the home group")
clock = clock + 31
Say("CHAT_MSG_INSTANCE_CHAT_LEADER", "ready now")
eq(#printed, 2, "the instance leader's chat was not noticed")
-- A raid finder group is raid chat, which this setting leaves out.
clock = clock + 31
instanceRaid = true
Say("CHAT_MSG_INSTANCE_CHAT", "ready")
eq(#printed, 2, "a raid finder group counted as party chat")
-- The skipped message used no cooldown: the same phrase is noticed at once with raid chat on.
alerts.config.raid = true
Say("CHAT_MSG_INSTANCE_CHAT", "ready")
eq(#printed, 3, "a skipped message started the phrase's cooldown")

-- Raid chat alone covers the raid group but not the party.
Start({ raid = true })
for _, event in ipairs(INSTANCE_EVENTS) do assert(listening[event], event .. " is not watched with raid chat on") end
instanceRaid = true
Say("CHAT_MSG_INSTANCE_CHAT_LEADER", "ready")
eq(#printed, 1, "a raid finder group's chat was not noticed")
clock = clock + 31
instanceRaid = false
Say("CHAT_MSG_INSTANCE_CHAT", "ready")
eq(#printed, 1, "a dungeon finder group counted as raid chat")

-- Neither chat selected: no instance listener. Other scopes keep their events and never ask the group.
Start({ guild = true })
for _, event in ipairs(INSTANCE_EVENTS) do assert(not listening[event], event .. " is watched without party or raid chat") end
Start({ party = true, raid = true })
Say("CHAT_MSG_PARTY", "ready")
Say("CHAT_MSG_RAID", "ready again")
eq(#asked, 0, "the group type was asked for a home chat event")
clock = clock + 31
instanceRaid = false
Say("CHAT_MSG_INSTANCE_CHAT", "no phrase here")
eq(#asked, 0, "the group type was asked for a message no phrase matched")
Say("CHAT_MSG_INSTANCE_CHAT", SECRET)
eq(#asked, 0, "a restricted instance message was read")
Start({ party = true })
alerts.config.party = false
alerts:Refresh()
for _, event in ipairs(INSTANCE_EVENTS) do assert(not listening[event], event .. " stays watched after party chat went off") end
print("Chat audit: conflicts, greyed dependents, window mover and instance keyword notices passed")
