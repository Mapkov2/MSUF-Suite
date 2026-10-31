-- The keystone window (/keys) merges the Suite's own answers (MSUFKEY1) with the
-- keystone libraries other addons loaded (LibKeystone, LibOpenRaid), one row per
-- player, and a row teleports to its dungeon when the portal is learned. The
-- teleport buttons never make the window protected: it closes (Escape),
-- moves and scales in combat without ADDON_ACTION_BLOCKED.
local root = assert(arg[1], "repository root required")
local support = assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))()

local function Check(condition, message)
    if not condition then error("suite_keys_interop_contract: " .. message, 2) end
    return condition
end

------------------------------------------------------------------ fixture
local now, combat, grouped, raided = 100, false, true, false
local installed, notices, messages, reported, log = nil, {}, {}, {}, {}
local blocked, secureCreated, slashHandler = {}, 0, nil
local names = { [161] = "Skyreach", [375] = "Mists of Tirna Scithe", [501] = "The Stonevault", [999] = "Nowhere" }
local own = { map = 161, level = 12 }

-- Frames, protected the way the client protects them: a frame made from a
-- secure template, and implicitly every frame with a protected child or with
-- a protected frame anchored to it. A protected frame may not change in
-- combat (ADDON_ACTION_BLOCKED); blocked lists every such attempt.
local SECURE = { SecureActionButtonTemplate = true, SecureHandlerStateTemplate = true }
local function IsProtected(frame)
    if frame.secure then return true end
    for other in pairs(frame.children) do if IsProtected(other) then return true end end
    for other in pairs(frame.anchoredBy) do if IsProtected(other) then return true end end
    return false
end
local function Guard(frame, what)
    if combat and IsProtected(frame) then blocked[#blocked + 1] = what .. " on " .. frame.kind end
end
local function Anchor(frame, point, relative, ...)
    local old = frame.points[point]
    if old then old[1].anchoredBy[frame] = nil end
    frame.points[point] = { relative, ... }
    relative.anchoredBy[frame] = true
end
local function Widget(kind, parent, template)
    -- Every field read is set here: a missing one would read a no-op method (__index below).
    local w = { kind = kind, parent = parent or false, secure = SECURE[template] or false, attrs = {}, scripts = {},
        children = {}, anchoredBy = {}, points = {}, shown = false, moving = false, scale = false,
        left = false, bottom = false, width = false, height = false,
        strata = parent and parent.strata or "MEDIUM", level = parent and parent.level + 1 or 0 }
    if parent then parent.children[w] = true end
    function w:SetAttribute(key, value) Guard(self, "SetAttribute"); self.attrs[key] = value end
    function w:SetPoint(point, relative, relativePoint, x, y)
        Guard(self, "SetPoint")
        if type(relative) ~= "table" then relative, relativePoint, x, y = self.parent, point, relative, relativePoint end
        Anchor(self, point, relative, relativePoint, x, y)
    end
    function w:SetAllPoints(relative) Guard(self, "SetAllPoints"); Anchor(self, "ALL", relative or self.parent) end
    function w:SetSize(width, height) Guard(self, "SetSize"); self.width, self.height = width, height end
    function w:SetHeight(value) Guard(self, "SetHeight"); self.height = value end
    function w:SetScale(value) Guard(self, "SetScale"); self.scale = value end
    function w:SetFrameStrata(value) Guard(self, "SetFrameStrata"); self.strata = value end
    function w:SetFrameLevel(value) Guard(self, "SetFrameLevel"); self.level = value end
    function w:StartMoving() Guard(self, "StartMoving"); self.moving = true end
    function w:StopMovingOrSizing() Guard(self, "StopMovingOrSizing"); self.moving = false end
    function w:GetRect() return self.left, self.bottom, self.width, self.height end
    function w:GetEffectiveScale() return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1) end
    function w:GetFrameStrata() return self.strata end
    function w:GetFrameLevel() return self.level end
    function w:SetScript(name, fn) self.scripts[name] = fn end
    function w:SetText(text) self.text = text end
    function w:SetTexture(value) self.texture = value end
    function w:IsShown() return self.shown end
    function w:Show()
        Guard(self, "Show")
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function w:Hide()
        Guard(self, "Hide")
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    return setmetatable(w, { __index = function() return function() end end })
end

-- SecureStateDriver.lua: registering applies the rule at once, the manager
-- applies it again on every update (a "show" rule shows its frame each time)
-- as secure code, and registering or unregistering is blocked in combat.
local VISIBILITY = "[combat] hide; show"
local drivers = {}
local function DriverUpdate() for frame in pairs(drivers) do frame.shown = not combat end end

local function Context()
    local ctx = { events = {} }
    function ctx:Event(event, callback) self.events[event] = callback end
    function ctx:RemoveEvent(event) self.events[event] = nil end
    function ctx:After(delay, callback) self.afterDelay, self.afterCallback = delay, callback end
    return ctx
end

local function IsSecret(value) return value == "secret" end
local S = {
    Install = function(id, module) installed = { id = id, module = module } end,
    Public = function(value) return not IsSecret(value) end,
    PublicText = function(value) return not IsSecret(value) and type(value) == "string" and value ~= "" and value or nil end,
    Finite = function(value) return not IsSecret(value) and type(value) == "number" and value == value end,
    Text = function(text) return text end,
    Print = function(text) notices[#notices + 1] = text end,
    CreateFrame = function(kind, _, parent, template)
        if combat and SECURE[template] then secureCreated = secureCreated + 1 end
        return Widget(kind, parent, template)
    end,
    CreateTexture = function(parent) return Widget("Texture", parent) end,
    CreateFontString = function(parent) return Widget("FontString", parent) end,
    SetStyledFont = function() end,
    GlobalFontPath = function() return "font" end,
    SlashAliasFree = function() return true end,
    RegisterSlash = function(_, handler) slashHandler = handler end,
    UnregisterSlash = function() slashHandler = nil end,
    Dispatch = support.Dispatcher(reported),
}
local NS = { IsCombatLocked = function() return combat end, ChatLocked = function() return false end,
    Finish = function(callback, ...) return true, callback(...) end }

GetTime = function() return now end
-- A UI scale with an exact binary value keeps the proxy arithmetic exact.
UIParent, UISpecialFrames = Widget("UIParent"), {}
UIParent.scale = .75
GameTooltip = setmetatable({}, { __index = function() return function() end end })
RegisterStateDriver = function(frame, state, rule)
    if combat then blocked[#blocked + 1] = "RegisterStateDriver" end
    Check(state == "visibility" and rule == VISIBILITY, "the teleport layer's state driver changed")
    drivers[frame] = rule
    frame.shown = not combat
end
UnregisterStateDriver = function(frame, state)
    if combat then blocked[#blocked + 1] = "UnregisterStateDriver" end
    Check(state == "visibility", "the teleport layer lost another state driver")
    drivers[frame] = nil
end
LE_PARTY_CATEGORY_INSTANCE = 2
IsInGroup = function(category) return category == nil and grouped end
IsInRaid = function() return raided end
IsInGuild = function() return true end
UnitFullName = function() return "Player", "Realm" end
local outsiders = { Dave = true, Vic = true }
UnitInParty = function(name) return outsiders[name] == nil end
UnitInRaid = function() return nil end
Enum = { SendAddonMessageResult = { Success = 0, AddOnMessageLockdown = 11 } }
local sendResult = 0
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) Check(prefix == "MSUFKEY1", "the Suite prefix changed") return true end,
    SendAddonMessage = function(prefix, payload, channel)
        if sendResult ~= 0 then return sendResult end
        messages[#messages + 1] = { prefix, payload, channel }
        return 0
    end,
    SendChatMessage = function() end,
}
C_MythicPlus = {
    GetOwnedKeystoneChallengeMapID = function() return own.map end,
    GetOwnedKeystoneLevel = function() return own.level end,
}
C_ChallengeMode = { GetMapUIInfo = function(id) return names[id] end, HasSlottedKeystone = function() return false end }

------------------------------------------------------------------ libraries
-- Stand-ins with the public API only: another addon owns the real ones.
local libs, libraryErrors = {}, {}
LibStub = { GetLibrary = function(_, name) return libs[name] end }

local function FakeKeystone()
    local lib = { callbacks = {} }
    function lib.Register(addon, callback)
        if libraryErrors.register then error("LibKeystone register failed") end
        log[#log + 1] = "ks.register"
        lib.callbacks[addon] = callback
    end
    function lib.Unregister(addon)
        log[#log + 1] = "ks.unregister"
        lib.callbacks[addon] = nil
    end
    function lib.Request(channel)
        log[#log + 1] = "ks.request:" .. channel
        if libraryErrors.request then error("LibKeystone request failed") end
    end
    function lib.Answer(level, mapID, name, channel)
        for _, callback in pairs(lib.callbacks) do callback(level, mapID, 2500, name, channel or "PARTY") end
    end
    return lib
end

local function FakeOpenRaid()
    local lib = { callbacks = {} }
    function lib.RegisterCallback(object, event, member)
        Check(event == "KeystoneUpdate", "LibOpenRaid callback name")
        log[#log + 1] = "or.register:" .. member
        lib.callbacks[#lib.callbacks + 1] = { object = object, member = member }
    end
    function lib.UnregisterCallback()
        log[#log + 1] = "or.unregister"
        lib.callbacks = {}
    end
    for _, kind in ipairs({ "Party", "Raid", "Guild" }) do
        lib["RequestKeystoneDataFrom" .. kind] = function()
            log[#log + 1] = "or.request:" .. kind
            return true
        end
    end
    function lib.Answer(name, level, mapID)
        for _, callback in ipairs(lib.callbacks) do
            callback.object[callback.member](name, { level = level, mythicPlusMapID = mapID }, {})
        end
    end
    return lib
end

------------------------------------------------------------------ load the module as the TOC does
local addon = { NS = NS, Suite = S }
for _, file in ipairs({ "MPlusKeystoneSources", "MPlusKeystoneTeleport", "MPlusKeystoneShare" }) do
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))("MSUF_Suite_QualityOfLife", addon)
end
local keys = Check(installed and installed.id == "mythicKeyShare" and installed.module, "the module did not install")
keys.active, keys.config, keys.context = true, {}, Context()
keys:Enable()
local command = Check(slashHandler, "/keys was not registered")

local function Reset()
    for i = #log, 1, -1 do log[i] = nil end
    for i = #messages, 1, -1 do messages[i] = nil end
end
local function Answer(sender, payload, channel)
    keys.context.events.CHAT_MSG_ADDON(keys, "CHAT_MSG_ADDON", "MSUFKEY1", payload, channel or "PARTY", sender)
end
local function Row(name) return keys.rows[name] end
local function RowIndex(name)
    local list = {}
    for rowName in pairs(keys.rows) do list[#list + 1] = rowName end
    table.sort(list)
    for i, rowName in ipairs(list) do if rowName == name then return i end end
end

------------------------------------------------------------------ no request without an action
Check(#messages == 0 and #log == 0, "enabling the module sent a request")
Answer("Alice-Realm", "K:161:12")
Check(not Row("Alice-Realm") and not keys.context.events.GROUP_ROSTER_UPDATE,
    "an unrequested answer was taken, or the roster was watched without a request")
command("")
Check(#messages == 0 and #log == 0 and keys.host.shown, "opening the window sent a request")
Check(keys.status.text == "Page 1/1 · Suite users who answered this request", "the idle status line changed")
Check(not keys.teleportLayer, "teleport buttons were built without a portal list")

------------------------------------------------------------------ the Suite protocol alone: wire format unchanged
now = 100
command("group")
Check(#messages == 1 and messages[1][1] == "MSUFKEY1" and messages[1][2] == "Q" and messages[1][3] == "PARTY",
    "the MSUFKEY1 request changed")
Check(keys.status.text == "Page 1/1 · No answers yet", keys.status.text)
Answer("Alice-Realm", "K:161:12")
Check(Row("Alice-Realm") == "Skyreach +12" and notices[#notices] == "Alice-Realm: Skyreach +12", "the Suite answer was not listed")
Check(keys.status.text == "Page 1/1 · Players who answered: 1 (Suite 1)", keys.status.text)
Answer("Bob-Realm", "Q")
Check(#messages == 2 and messages[2][2] == "K:161:12" and messages[2][3] == "PARTY", "the MSUFKEY1 answer changed")
local shareSource = assert(io.open(root .. "/MSUF_Suite_QualityOfLife/MPlusKeystoneShare.lua", "rb")):read("*a")
for _, literal in ipairs({ 'PREFIX = "MSUFKEY1"', 'string.format("K:%d:%d"', '"^K:(%d+):(%d+)$"',
    'SendAddonMessage(PREFIX, "Q", channel)' }) do
    Check(shareSource:find(literal, 1, true), "the wire format literal is gone: " .. literal)
end

------------------------------------------------------------------ each library alone: absent, present, erroring
now = 110
libs.LibKeystone, libs["LibOpenRaid-1.0"] = FakeKeystone(), nil
Reset()
command("group")
Check(table.concat(log, ",") == "ks.register,ks.request:PARTY", "LibKeystone was not asked once: " .. table.concat(log, ","))
libs.LibKeystone.Answer(15, 375, "Bob", "PARTY")
Check(Row("Bob-Realm") == "Mists of Tirna Scithe +15", "a bare LibKeystone name did not join the realm")
libs.LibKeystone.Answer(15, 375, "Player", "PARTY")
Check(not Row("Player") and not Row("Player-Realm"), "the player's own LibKeystone answer was listed")
libs.LibKeystone.Answer(7, 501, "Erin", "GUILD")
Check(not Row("Erin-Realm"), "a guild answer entered a group request")

now = 113
libs.LibKeystone, libs["LibOpenRaid-1.0"] = nil, FakeOpenRaid()
Reset()
command("group")
Check(table.concat(log, ",") == "or.register:OnUpdate,or.request:Party", "LibOpenRaid was not asked once: " .. table.concat(log, ","))
libs["LibOpenRaid-1.0"].Answer("Carol", 10, 501)
Check(Row("Carol-Realm") == "The Stonevault +10", "a LibOpenRaid answer was not listed")
libs["LibOpenRaid-1.0"].Answer("Dave", 10, 501)
Check(not Row("Dave-Realm"), "an answer of a player outside the group entered a group request")
raided, now = true, 116
Reset()
command("group")
Check(table.concat(log, ",") == "or.request:Raid", "a raid asked LibOpenRaid for the party")
raided, now = false, 119
-- A library that raises is reported and skipped; the others and the Suite still run.
libs.LibKeystone = FakeKeystone()
libraryErrors.request = true
Reset(); for i = #reported, 1, -1 do reported[i] = nil end
command("group")
Check(#reported == 1 and reported[1]:find("LibKeystone request failed", 1, true), "an erroring library was not reported")
Check(messages[1] and messages[1][2] == "Q" and table.concat(log, ","):find("or.request:Party", 1, true),
    "an erroring library stopped the Suite request or the other library")
libraryErrors.request = nil
-- A library that fails to register stays unattached and is not asked.
libs.LibKeystone, libraryErrors.register = FakeKeystone(), true
now = 122
Reset(); for i = #reported, 1, -1 do reported[i] = nil end
command("group")
Check(#reported == 1 and not table.concat(log, ","):find("ks.request", 1, true), "an unattached library was asked")
libraryErrors.register = nil

------------------------------------------------------------------ the merge: order, newest, one row per player
libs.LibKeystone, libs["LibOpenRaid-1.0"] = FakeKeystone(), FakeOpenRaid()
keys:Disable()
keys:Enable()
now = 130
command("group")
Check(keys.host.shown, "the window is not shown")
Answer("Alice-Realm", "K:161:12")
Check(keys.entries["Alice-Realm"].source == "Suite", "the Suite answer is not credited first")
now = 130.5
libs.LibKeystone.Answer(12, 161, "Alice", "PARTY")
Check(keys.entries["Alice-Realm"].source == "Suite" and keys.rowCount == 1,
    "the same key from a later source took the credit or made a second row")
libs.LibKeystone.Answer(15, 375, "Bob", "PARTY")
libs["LibOpenRaid-1.0"].Answer("Bob-Realm", 15, 375)
Check(keys.entries["Bob-Realm"].source == "LibKeystone" and keys.rowCount == 2,
    "LibKeystone does not rank before LibOpenRaid")
now = 131
libs["LibOpenRaid-1.0"].Answer("Alice-Realm", 14, 501)
Check(Row("Alice-Realm") == "The Stonevault +14" and keys.entries["Alice-Realm"].source == "LibOpenRaid",
    "a newer different key did not win")
now = 132
libs.LibKeystone.Answer(9, 375, "Alice", "PARTY")
Check(Row("Alice-Realm") == "Mists of Tirna Scithe +9" and keys.entries["Alice-Realm"].source == "LibKeystone",
    "the newest answer did not win")
Answer("Alice-Realm", "K:501:3")
libs["LibOpenRaid-1.0"].Answer("Alice-Realm", 20, 161)
Check(Row("Alice-Realm") == "The Stonevault +3" and keys.entries["Alice-Realm"].source == "Suite",
    "an answer of the same moment from a later source replaced the earlier one")
local count = 0
for name in pairs(keys.rows) do if name:find("^Alice") then count = count + 1 end end
Check(count == 1, "a player has more than one row")
libs["LibOpenRaid-1.0"].Answer("Carol", 10, 161)
Check(keys.status.text == "Page 1/1 · Players who answered: 3 (Suite 1, LibKeystone 1, LibOpenRaid 1)", keys.status.text)
-- Windows: the Suite protocol closes after 5 seconds, the libraries after 12.
now = 136
Answer("Zed-Realm", "K:161:12")
libs.LibKeystone.Answer(11, 161, "Yan", "PARTY")
Check(not Row("Zed-Realm") and Row("Yan-Realm") == "Skyreach +11", "the answer windows are wrong")
libs.LibKeystone.Answer(11, 99999, "Wil", "PARTY")
libs.LibKeystone.Answer(1, 161, "Vic", "PARTY")
libs["LibOpenRaid-1.0"].Answer("Uma", 12, 0)
libs["LibOpenRaid-1.0"].Answer("Tim", nil, 161)
Check(not Row("Wil-Realm") and not Row("Vic-Realm") and not Row("Uma-Realm") and not Row("Tim-Realm"),
    "an invalid key was listed")
now = 143
libs.LibKeystone.Answer(11, 161, "Xia", "PARTY")
Check(not Row("Xia-Realm"), "a library answer was taken after its window")

------------------------------------------------------------------ throttle
now = 200
Reset()
command("group")
local sent = #messages
now = 201
command("group")
Check(#messages == sent and #log == 2, "a second request inside the cooldown went out")
now = 202
command("group")
Check(#messages == sent + 1, "the cooldown never ends")

------------------------------------------------------------------ option off: no library is touched
keys.config = { otherAddons = false }
now = 210
Reset()
command("group")
Check(#messages == 1 and #log == 0, "the option did not keep the libraries out")
keys.config = {}

------------------------------------------------------------------ group changes
Check(keys.context.events.GROUP_ROSTER_UPDATE and keys.context.events.PLAYER_REGEN_ENABLED,
    "a shown group window listens to nothing")
keys.context.afterDelay, keys.context.afterCallback = nil, nil
keys.context.events.GROUP_ROSTER_UPDATE(keys, "GROUP_ROSTER_UPDATE")
Check(keys.context.afterDelay == 3, "a roster change is not settled before asking")
local before, noticed = #messages, #notices
now = 215
keys.context.afterCallback(keys)
Check(#messages == before + 1 and #notices == noticed, "the roster refresh did not ask quietly")
now = 216
keys.context.afterCallback(keys)
Check(#messages == before + 1, "the roster refresh ignored the cooldown")
now = 220
command("guild")
Check(not keys.context.events.GROUP_ROSTER_UPDATE, "a guild request keeps the roster watch")
now = 225
command("group")
keys.host:Hide()
Check(not keys.context.events.GROUP_ROSTER_UPDATE and not keys.context.events.PLAYER_REGEN_ENABLED,
    "a hidden window keeps listening")
before, now = #messages, 230
keys.context.afterCallback(keys)
Check(#messages == before, "a hidden window asked again")

------------------------------------------------------------------ teleports
local groups = {
    season = {
        { id = 159898, map = 161, learned = true, icon = 11 },
        { id = 1254557, map = 161, learned = true, icon = 12 },
        { id = 354464, map = 375, learned = false, icon = 13 },
    },
    learned = { { id = 445269, map = 501, learned = true, icon = 14 } },
    later = {},
}
local scans = 0
S.DungeonPortalChoices = function() scans = scans + 1 return groups, true end
local dungeonPortals = assert(io.open(root .. "/MSUF_Suite_QualityOfLife/DungeonPortals.lua", "rb")):read("*a")
Check(dungeonPortals:find("function S.DungeonPortalChoices()", 1, true), "the portal list the teleports read is gone")
-- The window stands away from the screen origin, at a scale of its own.
keys.config = { windowScale = 125 }
keys.host.left, keys.host.bottom = 300, 120
now = 240
command("group")
Answer("Alice-Realm", "K:501:14")
Answer("Bob-Realm", "K:375:15")
Answer("Carol-Realm", "K:999:10")
local layer = Check(keys.teleportLayer, "no teleport layer")
Check(scans == 1, "the portal list was read more than once for one request: " .. scans)
local buttons = keys.teleportButtons
local you, alice, bob, carol = RowIndex("You"), RowIndex("Alice-Realm"), RowIndex("Bob-Realm"), RowIndex("Carol-Realm")
Check(buttons[you].shown and buttons[you].attrs.spell == 1254557 and buttons[you].attrs.type == "spell",
    "the own row does not cast the newer learned portal")
Check(buttons[alice].shown and buttons[alice].attrs.spell == 445269, "a learned portal row does not teleport")
Check(not buttons[bob].shown, "an unlearned portal got a teleport")
Check(not buttons[carol].shown, "a dungeon without any portal got a teleport")
local listed = 0
for _, button in ipairs(buttons) do if button.shown then listed = listed + 1 end end
Check(listed == 2, "a row without a key got a teleport")
Check(buttons[you].attrs.useOnKeyDown == false and buttons[you].secure, "the teleport button is not a secure spell button")

------------------------------------------------------------------ teleports: the window stays a plain frame
-- DungeonPortals.lua's pattern: a secure owner on UIParent holds the buttons,
-- and they anchor to a plain proxy, never to the window.
local host, proxy = keys.host, keys.teleportProxy
Check(layer.parent == UIParent and layer.secure and drivers[layer] == VISIBILITY and layer.shown,
    "the teleport layer is not a shown secure owner on UIParent that its driver hides in combat")
Check(proxy and proxy.parent == UIParent and not proxy.secure, "the teleport proxy is not a plain frame on UIParent")
for i, button in ipairs(buttons) do
    Check(button.parent == layer and button.points.TOPLEFT[1] == proxy and button.points.TOPRIGHT[1] == proxy,
        "teleport button " .. i .. " does not anchor to the proxy")
end
Check(not IsProtected(host), "the keystone window is protected: a protected frame is its child or anchors to it")
Check(layer.strata == host.strata and buttons[you].level > host.level + 1, "the teleports do not draw over the window")
-- The proxy covers the window on screen in UIParent units, and the layer has
-- the window's effective scale: the rows' offsets and heights are window units.
local function Mirrors(left, bottom, scale)
    local point = proxy.points.BOTTOMLEFT
    return layer.scale == scale and point[1] == UIParent and point[2] == "BOTTOMLEFT"
        and point[3] == left * scale and point[4] == bottom * scale
        and proxy.width == 480 * scale and proxy.height == 414 * scale
end
Check(Mirrors(300, 120, 1.25) and layer:GetEffectiveScale() == host:GetEffectiveScale(),
    "the proxy does not mirror the window")

-- Out of combat the layer follows the window: it waits out a drag, comes
-- back at the drop, and hides and shows with the window.
host.scripts.OnDragStart(host)
Check(host.moving and not layer.shown and not drivers[layer], "the teleports stayed behind during a drag")
host.left, host.bottom = 340, 100
host.scripts.OnDragStop(host)
Check(not host.moving and layer.shown and drivers[layer] and Mirrors(340, 100, 1.25),
    "the teleports did not follow the dropped window")
host:Hide()
DriverUpdate()
Check(not layer.shown and not drivers[layer], "the teleports stayed on screen without the window")
command("")
Check(host.shown and layer.shown and drivers[layer] and Mirrors(340, 100, 1.25),
    "the teleports did not come back with the window")

------------------------------------------------------------------ teleports: combat
local function EnterCombat()
    combat = true
    DriverUpdate()
end
local function LeaveCombat()
    combat = false
    local after = keys.context.events.PLAYER_REGEN_ENABLED
    if after then after(keys, "PLAYER_REGEN_ENABLED") end
    DriverUpdate()
end
local function Blocked() return "a protected frame changed in combat: " .. table.concat(blocked, ", ") end

-- The window still moves and scales in combat; the protected layer, proxy
-- and buttons stay as they are until the end of combat catches them up.
blocked, secureCreated = {}, 0
EnterCombat()
Check(not layer.shown, "the state driver did not hide the teleports in combat")
now = 245
Answer("Alice-Realm", "K:375:15")
Answer("Bob-Realm", "K:501:20")
keys.config = { windowScale = 150 }
keys:Refresh()
host.scripts.OnDragStart(host)
Check(host.moving, "the window cannot be dragged in combat")
host.left, host.bottom = 200, 60
host.scripts.OnDragStop(host)
Check(#blocked == 0 and secureCreated == 0, Blocked())
Check(host.scale == 1.5 and not IsProtected(host), "the window did not scale in combat")
Check(Mirrors(340, 100, 1.25), "the proxy moved in combat")
Check(Row("Alice-Realm") == "Mists of Tirna Scithe +15", "the list stopped updating in combat")
Check(buttons[alice].attrs.spell == 445269, "a button was re-aimed in combat")
LeaveCombat()
Check(#blocked == 0 and layer.shown and Mirrors(200, 60, 1.5) and layer:GetEffectiveScale() == host:GetEffectiveScale(),
    "the teleports did not catch up with the window after combat")
Check(not buttons[alice].shown and buttons[bob].shown and buttons[bob].attrs.spell == 445269,
    "the buttons were not re-aimed after combat")

-- Escape or Close in combat closes the plain window; the layer, which its
-- driver hides meanwhile, stays hidden after combat.
EnterCombat()
host:Hide()
Check(#blocked == 0 and not host.shown, Blocked())
Check(keys.context.events.PLAYER_REGEN_ENABLED, "a window closed in combat does not wait for the end of combat")
LeaveCombat()
Check(#blocked == 0 and not layer.shown and not drivers[layer], "the teleports came back after combat without the window")
Check(not keys.context.events.PLAYER_REGEN_ENABLED, "a window closed in combat keeps listening after combat")
-- A window opened in combat gets its teleports at the end of combat.
EnterCombat()
command("")
Check(#blocked == 0 and host.shown and not layer.shown, Blocked())
LeaveCombat()
Check(#blocked == 0 and layer.shown and drivers[layer] and Mirrors(200, 60, 1.5),
    "a window opened in combat did not get its teleports after combat")

------------------------------------------------------------------ disable and catalog
keys:Disable()
Check(table.concat(log, ","):find("ks.unregister", 1, true) and table.concat(log, ","):find("or.unregister", 1, true)
    and not next(libs.LibKeystone.callbacks) and #libs["LibOpenRaid-1.0"].callbacks == 0,
    "disabling left a library callback behind")
local function Catalog(client)
    local ns = { Client = client, Text = function(text) return text end, AddQoLVisualStyle = function() end }
    assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", ns)
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLifeGroup.lua"))("MSUF_Suite", ns)
    return ns.SuiteCatalog.mythicKeyShare
end
local module = Catalog({ isForever = false })
local rule = Check(module.rules.otherAddons, "the other-addons option is missing")
Check(rule.default == true and rule.tooltip and module.rules.insertKey.default == false,
    "the other-addons option does not default on, has no tooltip, or insertKey changed")
Check(module.available() == true and Catalog({ isForever = true }).available() == false,
    "the keystone window is offered on WoW Forever")

print("Keys interop: Suite protocol unchanged, LibKeystone and LibOpenRaid merged by player, " ..
    "throttled and optional, teleports for learned portals over a plain window that closes, moves and scales in combat passed")
