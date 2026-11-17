-- Exercise the real section header and its native visibility subscription.
local root = assert(arg[1])
local config = { enabled = true, friendlySkinEnabled = true, friendlyNpcSkinEnabled = true,
    enemySkinEnabled = true, neutralSkinEnabled = true }
local native = { friendly = false, friendlyNpc = true }
local frames, buttons, actions, histories, refreshes = {}, {}, {}, 0, 0
local allowed, rowWrites, batches = true, 0, 0
local secret = {}
local function Frame(parent)
    local frame = { parent = parent, scripts = {}, events = {}, shown = true }
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    function frame:HookScript(name, callback) self.scripts[name] = callback end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    return frame
end
CreateFrame = function(_, _, parent)
    local frame = Frame(parent)
    frames[#frames + 1] = frame
    return frame
end
local skinKeys = { enemy = "enemySkinEnabled", neutral = "neutralSkinEnabled",
    friendly = "friendlySkinEnabled", friendlyNpc = "friendlyNpcSkinEnabled" }
local rules = {}
for scope, key in pairs(skinKeys) do rules[key] = { key = key, label = scope } end
local P = {
    Tr = function(text) return text end,
    catalog = { nameplates = { rules = rules } }, feedback = {},
    Suite = { NameplateExtensions = { SkinKeys = skinKeys },
        Public = function(value) return value ~= secret end },
    W = { SectionSwitch = function() end, SetControlEnabled = function() end }, M = { TrackRefresh = function() end },
}
P.NameplatesStatus = { IsOffset = function() return false end }
P.Suite.NameplateStyle = { AuraGroups = {} }
P.Get = function(id, key) assert(id == "nameplates"); return config[key] end
P.RuleEnabled = function() return allowed end
P.RuleRow = function(_, _, rule)
    return { label = rule.label, get = function() return config[rule.key] end,
        set = function(on) rowWrites = rowWrites + 1; config[rule.key] = on; return true end }
end
P.WithHistory = function(_, _, callback) histories = histories + 1; return callback() end
P.Refresh = function() refreshes = refreshes + 1 end
P.SetMany = function(_, values)
    batches = batches + 1
    for key, value in pairs(values) do config[key] = value end
    return true
end
P.GateControls = function() end
P.W.SetCollapsibleSummary = function(body, text) body.summary = text end
P.BindSectionSwitch = function(_, body, spec)
    local button = Frame()
    function button:SetChecked(on) self.checked = on end
    function button:GetChecked() return self.checked end
    button.spec, button.checked = spec, spec.get()
    body.button = button
    buttons[#buttons + 1] = button
    return button
end
P.NameplatesPreview = { Metrics = function() return { barWidth = 100, nativeBarHeight = 10, heightDelta = 0 } end }
P.Suite.FriendlyNameplateShown = function(scope)
    return config.enabled and config[skinKeys[scope]] ~= false and native[scope]
end
P.Suite.SetFriendlyNameplates = function(scope, on, values)
    actions[#actions + 1] = { scope = scope, on = on, values = values }
    for key, value in pairs(values or {}) do config[key] = value end
    config[skinKeys[scope]], native[scope] = on, on
    return true
end
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesDirectSettings.lua"))("MSUF_Suite_Options", P)
assert(loadfile(arg[2] or root .. "/MSUF_Suite_Options/Pages/NameplatesSectionsLayout.lua"))("MSUF_Suite_Options", P)
local Layout = P.NameplatesSectionsLayout
local function Header(scope)
    local body = {}
    Layout.Header({}, { switch = skinKeys[scope], enableModule = true,
        summary = Layout.Dimensions(scope) }, "suite_nameplates_" .. scope .. "Basics")(body)
    return body, body.button
end
local function Event(frame, name)
    assert(frame.events.CVAR_UPDATE, "visible header does not watch native visibility")
    frame.scripts.OnEvent(frame, "CVAR_UPDATE", name)
end

local friendly, player = Header("friendly")
assert(not player.checked and friendly.summary == "Off", "native OFF still appears enabled in the Suite header")
assert(player.spec.set(true) and #actions == 1 and actions[1].scope == "friendly" and actions[1].on,
    "Friendly Enable did not use the intentional visibility action")
assert(histories == 1 and refreshes == 1 and rowWrites == 0 and player.spec.get(),
    "Friendly Enable bypassed history or wrote the old skin-only control")
local playerEvents = assert(frames[1])
Event(playerEvents, "nameplateShowFriendlyPlayers")
assert(player.checked and friendly.summary == "100 × 10 px")
native.friendly = false
Event(playerEvents, "nameplateshowfriendlyplayers")
assert(not player.checked and friendly.summary == "Off", "native OFF did not repaint the visible header and summary")
native.friendly = true
Event(playerEvents, "NAMEPLATESHOWFRIENDLYPLAYERS")
assert(player.checked, "uppercase native CVar event did not repaint the visible header")
native.friendly = false
Event(playerEvents, "nameplateshowfriendlyplayers")
local checkedBefore = player.checked
Event(playerEvents, secret)
Event(playerEvents, "unrelatedCVar")
assert(player.checked == checkedBefore and #actions == 1, "native event changed a profile or accepted an unrelated value")
playerEvents.scripts.OnHide(playerEvents)
assert(not next(playerEvents.events), "hidden header retained its native event listener")
native.friendly = true
playerEvents.scripts.OnShow(playerEvents)
assert(player.checked, "returning to the header did not read native visibility")
assert(player.spec.set(false) and actions[2].on == false and not player.spec.get())

local npc, npcButton = Header("friendlyNpc")
assert(npcButton.checked and not player.spec.get(), "NPC and player visibility were coupled")
native.friendlyNpc = false
Event(assert(frames[2]), "NAMEPLATESHOWFRIENDLYNPCS")
assert(not npcButton.checked and npc.summary == "Off")
assert(npcButton.spec.set(true) and actions[3].scope == "friendlyNpc" and npcButton.spec.get(),
    "NPC Enable needed a second click after native OFF")
config.enabled = false
assert(npcButton.spec.set(true))
local values = assert(actions[4].values)
assert(values.enabled and values.friendlyNpcSkinEnabled and not values.friendlySkinEnabled
    and not values.enemySkinEnabled and not values.neutralSkinEnabled,
    "enabling the module from NPC selected unrelated scopes")

local _, enemy = Header("enemy")
assert(enemy.spec.set(true) and rowWrites == 1 and #actions == 4 and #frames == 2,
    "Friendly compatibility changed the Enemy switch")
config.enabled = false
assert(enemy.spec.set(true) and batches == 1 and #actions == 4,
    "Enemy module enable no longer uses the existing batch setter")
allowed = false
assert(not player.spec.set(true) and #actions == 4, "gated header still performed a visibility action")
allowed = true
config.enabled, config.friendlyNpcSkinEnabled, config.friendlyNPCs = true, true, 4
local display = P.RuleRow("suite_nameplates", "nameplates", { key = "friendlyNPCs", label = "Display",
    choices = { "Keep Blizzard setting", "Show", "Hide", "Names only" } })
assert(display.get() == 4 and display.set(2))
assert(#actions == 5 and actions[5].scope == "friendlyNpc" and actions[5].on
    and actions[5].values.friendlyNPCs == 2,
    "switching Names only to Health bars did not deliberately show native NPC plates")
config.friendlyNpcSkinEnabled = false
assert(display.set(4) and rowWrites == 1 and #actions == 6 and not actions[6].on,
    "editing the display of disabled NPC plates enabled them")
for _, mode in ipairs({ 2, 4 }) do
    config.friendlyNpcSkinEnabled, native.friendlyNpc = true, false
    assert(not npcButton.spec.get(), "native NPC OFF does not appear OFF before editing Display")
    assert(display.set(mode) and not config.friendlyNpcSkinEnabled and not native.friendlyNpc,
        "editing Display enabled native-hidden NPC plates with the default active skin")
    assert(actions[#actions].values.friendlyNPCs == mode and not actions[#actions].on)
end
config.enabled, config.friendlyNpcSkinEnabled = false, true
assert(display.set(4) and not config.enabled and not config.friendlyNpcSkinEnabled,
    "editing Display while the module is off enabled its NPC scope")
print("Friendly header: native state, intentional actions, visible-only events, NPC display and separate scopes passed")
