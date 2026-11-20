local root = assert(arg[1], "repository root required")
local secret = setmetatable({}, { __index = function() error("read a secret value") end })
local blocked = setmetatable({}, { __index = function() error("read an inaccessible table") end })
canaccesstable = function(value) return not rawequal(value, blocked) end
local errors, forbidden = 0, 0
local function Public(value) return not rawequal(value, secret) end
local S = {
    Public = Public,
    Finite = function(value) return Public(value) and type(value) == "number" and math.abs(value) < math.huge end,
    PublicText = function(value) return Public(value) and type(value) == "string" and value ~= "" and value or nil end,
    Dispatch = function(fn, ...)
        local ok, a, b, c = coroutine.resume(coroutine.create(fn), ...)
        if ok then return a, b, c end
        errors = errors + 1
    end,
}
local originalMethods, hooks = {}, 0
hooksecurefunc = function(owner, name, callback)
    hooks = hooks + 1
    local method = owner[name]
    assert(method == originalMethods[name], "installed a second hook on the same method")
    owner[name] = function(...)
        method(...)
        callback(...)
    end
end
C_AddOns = { LoadAddOn = function() forbidden = forbidden + 1; error("loaded an optional provider") end }
GameTooltip = setmetatable({}, { __index = function() forbidden = forbidden + 1; error("read the native tooltip") end })
local hbd = {
    GetPlayerZone = function() return 37 end,
    TranslateZoneCoordinates = function(_, x, y, from, to)
        assert(from == 40 and to == 37)
        return x + .1, y
    end,
}
local migrate = {
    GetLegacyMapInfo = function(_, map) assert(map == 37); return 30, 2, "Legacy" end,
    GetUIMapIDFromMapFile = function(_, source, level)
        assert(source == "Child" and level == 1)
        return 40
    end,
}
LibStub = { GetLibrary = function(_, name, optional)
    assert(optional, "required a supporting library")
    if name == "HereBeDragons-2.0" then return hbd end
    if name == "HereBeDragons-Migrate" then return migrate end
end }
local private = { Suite = S }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/NavigationHUDHandyNotes.lua"))("QoL", private)
local Provider = assert(private.NavigationHUDHandyNotes)
local function Add(output, x, y, label, atlas, source, texture, left, right, top, bottom, native)
    assert(not atlas and source == "handynotes")
    output[#output + 1] = { x = x, y = y, label = label, texture = texture, native = native, uv = { left, right, top, bottom } }
end
local function Read(native, map)
    local output = {}
    Provider.Read(output, map or 37, Add, native)
    return output
end
local function Iter(data, previous)
    local index = previous and data.indices[previous] + 1 or 1
    local row = data[index]
    if row then return unpack(row, 1, 6) end
end
local function Feed(rows)
    rows.indices = {}
    for i, row in ipairs(rows) do rows.indices[row[1]] = i end
    return Iter, rows, nil
end
local updates, nativeReads, worldReads = 0, 0, 0
local function OnUpdate() updates = updates + 1 end
Provider.Watch(OnUpdate)
assert(#Read() == 0 and hooks == 0, "an absent provider was loaded or hooked")
local descriptor = { icon = 128004, tCoordLeft = 0, tCoordRight = .25, tCoordTop = .5, tCoordBottom = .75 }
local owner = {
    IsEnabled = function(self) return self.active end,
    active = true,
    plugins = {},
    db = { profile = { enabled = true, enabledPlugins = { HandyNotes = true, Legacy = true, Hidden = false, Other = true } } },
    GetModule = function(_, name, optional)
        assert(name == "HandyNotes" and optional)
        return { db = { global = { [37] = { [25004000] = { title = "My mailbox" } } } } }
    end,
}
local function Method(name)
    local function Original() end
    owner[name], originalMethods[name] = Original, Original
end
HandyNotes = blocked
Provider.Watch(OnUpdate)
assert(#Read() == 0 and errors == 0 and hooks == 0, "read or hooked an inaccessible provider")
HandyNotes = owner
Method("RegisterPluginDB")
Provider.Watch(OnUpdate)
assert(hooks == 1, "did not hook the available method on an early addon shell")
for _, method in ipairs({ "UpdatePluginMap", "OnProfileChanged", "OnEnable", "OnDisable" }) do Method(method) end
Provider.Watch(OnUpdate)
Provider.Watch(OnUpdate)
assert(hooks == 5, "did not finish hooking a late provider or registered duplicate hooks")
owner:UpdatePluginMap(nil, "HandyNotes")
owner:OnProfileChanged()
owner:RegisterPluginDB()
assert(updates == 3)
owner.plugins.HandyNotes = {
    GetNodes2 = function(_, map, minimap)
        assert(map == 37)
        if minimap then
            nativeReads = nativeReads + 1
            return Feed({ { 25004000, nil, descriptor, 1, .5 } })
        end
        worldReads = worldReads + 1
        return Feed({ { 25004000, nil, descriptor, 1, .5 }, { 30005000, nil, "Interface\\Icons\\foo", 1, 1 },
            { 40006000, nil, 33, 1, 0 }, { 80001000, nil, secret, 1, 1 }, { 70007000, secret, 33, 1, 1 },
            { 99000000, nil, 777, 1, secret } })
    end,
    OnEnter = function() forbidden = forbidden + 1; error("opened a plugin tooltip") end,
}
owner.plugins.Legacy = {
    GetNodes = function(_, map, minimap, level)
        assert(map == "Legacy" and level == 2)
        local rows = { { 20005000, "Child", 456, 1, 1, 1 } }
        if minimap then rows[1][1], rows[1][2], rows[1][6] = 30005000, nil, nil end
        return Feed(rows)
    end,
}
owner.plugins.Hidden = { GetNodes2 = function() error("enumerated disabled plugin") end }
-- One reader may fail while the next plugin still contributes.
owner.plugins.Other = { GetNodes2 = function()
    return function() error("broken third-party iterator") end
end }
local plain = Read(false)
assert(#plain == 4 and nativeReads == 0 and worldReads == 1 and errors == 1 and forbidden == 0)
local both = Read(true)
assert(#both == 4 and nativeReads == 1 and worldReads == 2 and errors == 3 and forbidden == 0)
local found = {}
for _, point in ipairs(both) do found[point.texture or false] = point end
local mailbox = assert(found[128004])
assert(mailbox.label == "My mailbox" and mailbox.x == .25 and mailbox.y == .4 and mailbox.native == true)
assert(mailbox.uv[1] == 0 and mailbox.uv[2] == .25 and mailbox.uv[3] == .5 and mailbox.uv[4] == .75)
assert(found["Interface\\Icons\\foo"].native == false and found["Interface\\Icons\\foo"].label == "HandyNotes")
assert(found[456].label == "Legacy" and math.abs(found[456].x - .3) < 1e-6 and found[456].native == true)
assert(found[false].texture == nil and found[false].native == false and not found[777])
owner.db.profile.icon_alpha_minimap = 0
for _, point in ipairs(Read(true)) do assert(point.native == false, "globally hidden native minimap points still suppressed the Suite") end
assert(nativeReads == 1, "hid native pins, then read their provider anyway")
owner.db.profile.icon_alpha_minimap = 1
owner.db.profile.enabledPlugins.HandyNotes = false
assert(#Read() == 1 and worldReads == 3, "ignored a changed plugin visibility setting")
owner.db.profile.enabled = false
assert(#Read() == 0, "ignored the HandyNotes master toggle")
local profile = owner.db.profile
owner.db.profile = blocked
local errCount = errors
assert(#Read() == 0 and errors == errCount, "accessed a restricted HandyNotes profile")
owner.db.profile = profile
owner.db.profile.enabled, owner.active = true, false
assert(#Read() == 0, "ignored disabling the active addon")

owner.active = true
owner.db.profile.enabledPlugins = { Endless = true }
local visits = { world = 0, minimap = 0 }
owner.plugins = {
    Endless = { GetNodes2 = function(_, _, minimap)
        local key = minimap and "minimap" or "world"
        return function()
            visits[key] = visits[key] + 1
            return (minimap and 10000000 or 25000000) + visits[key], nil, 1
        end
    end },
}
local limited = Read(true)
assert(#limited == 128 and visits.world == 128 and visits.minimap == 128, "did not bound an endless reader")
assert(limited[1].native == nil, "an incomplete native pass claimed a pin was missing")
owner.db.profile.enabledPlugins.HandyNotes = true
owner.plugins.HandyNotes = {
    GetNodes2 = function() return Feed({ { 25004000, nil, blocked } }) end,
}
local priority = Read(false)
assert(priority[1].label == "My mailbox" and priority[1].texture == nil,
    "personal notes lost priority or leaked an inaccessible icon descriptor")
Provider.Watch(nil)
owner:OnDisable()
assert(updates == 3, "disabled watcher still woke a Suite owner")
Provider.Watch(OnUpdate)
owner:OnEnable()
assert(updates == 4 and hooks == 5, "watch re-enable failed to reuse hooks")
print("PASS HandyNotes registry, world-only/native pin filtering, legacy coordinates, public icons/titles and bounded watchers")
