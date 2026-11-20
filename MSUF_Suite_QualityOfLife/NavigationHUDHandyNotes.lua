local _, private = ...
local S = private.Suite
local HandyNotes = {}
private.NavigationHUDHandyNotes = HandyNotes

local PLUGIN_LIMIT, NODE_LIMIT, FEED_LIMIT, POINT_LIMIT = 32, 128, 384, 160
local floor = math.floor
local Public, Finite, Text = S.Public, S.Finite, S.PublicText
local listener
local hooked = setmetatable({}, { __mode = "k" })
local HOOKS = { "RegisterPluginDB", "UpdatePluginMap", "OnProfileChanged", "OnEnable", "OnDisable" }

local function Table(value)
    return Public(value) and type(value) == "table" and canaccesstable(value) and value or nil
end

local function Accessible(value)
    return Public(value) and (type(value) ~= "table" or canaccesstable(value))
end

local function Method(owner, name)
    local value = Table(owner) and owner[name]
    if Public(value) and type(value) == "function" then return value end
end

local function Library(name)
    local stub = _G.LibStub
    local get = Method(stub, "GetLibrary")
    if get then return Table(get(stub, name, true)) end
end

local function PositiveInteger(value)
    return Finite(value) and value >= 1 and value == floor(value)
end

local function Fraction(value)
    return Finite(value) and value >= 0 and value <= 1
end

local function PathOrFileID(value)
    if PositiveInteger(value) then return value end
    return Text(value)
end

local function Texture(value)
    local descriptor = Table(value)
    if not descriptor then return PathOrFileID(value) end
    local file = PathOrFileID(descriptor.icon)
    if not file then return end
    local left, right, top, bottom = descriptor.tCoordLeft, descriptor.tCoordRight,
        descriptor.tCoordTop, descriptor.tCoordBottom
    if Fraction(left) and Fraction(right) and Fraction(top) and Fraction(bottom) then
        return file, left, right, top, bottom
    end
    return file
end

local function OwnNotes(core)
    local getModule = Method(core, "GetModule")
    local notes = getModule and Table(getModule(core, "HandyNotes", true))
    local db = notes and Table(notes.db)
    return db and Table(db.global)
end

local function NoteTitle(notes, map, coord)
    local zone = notes and Table(notes[map])
    local note = zone and Table(zone[coord])
    return note and (Text(note.title) or Text(note.desc)) or nil
end

local function Open(plugin, map, minimap)
    local modern = Method(plugin, "GetNodes2")
    if modern then return modern(plugin, map, minimap) end
    local legacy = Method(plugin, "GetNodes")
    if not legacy then return end
    local migrate = Library("HereBeDragons-Migrate")
    local legacyInfo = Method(migrate, "GetLegacyMapInfo")
    if not legacyInfo then return end
    local _, level, mapFile = legacyInfo(migrate, map)
    mapFile = Text(mapFile)
    if not mapFile then return end
    if not Finite(level) then level = 0 end
    local nextNode, iteratorState, cursor = legacy(plugin, mapFile, minimap, level)
    return nextNode, iteratorState, cursor, migrate, mapFile, level
end

local function SourceMap(map, source, level, migrate, mapFile, originalLevel)
    if not Public(source) then return end
    if not migrate then
        if source == nil then return map end
        if PositiveInteger(source) then return source end
        return
    end
    if not Public(level) then return end
    if source == nil then source = mapFile else source = Text(source) end
    if not source then return end
    if level == nil then
        level = originalLevel
    elseif not Finite(level) then
        return
    end
    if source == mapFile and level == originalLevel then return map end
    local convert = Method(migrate, "GetUIMapIDFromMapFile")
    local translated = convert and convert(migrate, source, level)
    if PositiveInteger(translated) then return translated end
end

local function Position(state, source, coord)
    if not (source and Finite(coord) and coord >= 0 and coord == floor(coord)) then return end
    local x, y = floor(coord / 10000) / 10000, (coord % 10000) / 10000
    if source ~= state.map then
        if not state.translate then return end
        x, y = state.translate(state.hbd, x, y, source, state.map)
    end
    if Fraction(x) and Fraction(y) then return x, y end
end

local function PointKey(x, y)
    return floor(x * 10000 + .5) * 10001 + floor(y * 10000 + .5)
end

local function CollectNative(state, _, x, y)
    state.nativePoints[PointKey(x, y)] = true
end

local function CollectWorld(state, name, x, y, source, coord, icon)
    local label = (name == "HandyNotes" and NoteTitle(state.notes, source, coord)) or name
    local onNativeMinimap
    if state.nativePoints[PointKey(x, y)] then
        onNativeMinimap = true
    elseif state.nativeComplete then
        onNativeMinimap = false
    end
    local file, left, right, top, bottom = Texture(icon)
    state.add(state.output, x, y, label, nil, "handynotes", file, left, right, top, bottom, onNativeMinimap)
    state.points = state.points + 1
end

local function ReadNodes(state, plugin, name, map, minimap, collect)
    local nextNode, iteratorState, cursor, migrate, mapFile, originalLevel = Open(plugin, map, minimap)
    if not Public(nextNode) or type(nextNode) ~= "function" or not Accessible(iteratorState) or not Accessible(cursor) then return end
    local budget = minimap and "nativeBudget" or "worldBudget"
    local complete = true
    for _ = 1, NODE_LIMIT do
        if state[budget] < 1 or state.points >= POINT_LIMIT then return end
        state[budget] = state[budget] - 1
        local coord, source, icon, _, alpha, level = nextNode(iteratorState, cursor)
        if not Accessible(coord) then return end
        if coord == nil then return complete end
        cursor = coord
        if not Public(alpha) or (alpha ~= nil and not Finite(alpha)) then
            complete = false
        elseif alpha == nil or alpha > 0 then
            source = SourceMap(map, source, level, migrate, mapFile, originalLevel)
            local x, y = Position(state, source, coord)
            if x then
                collect(state, name, x, y, source, coord, icon)
            else
                complete = false
            end
        end
    end
end

local function Core(core)
    local isEnabled = Method(core, "IsEnabled")
    local enabled = isEnabled and isEnabled(core)
    if not Public(enabled) or enabled ~= true then return end
    local db = Table(core.db)
    local profile = db and Table(db.profile)
    if not profile or not Public(profile.enabled) or profile.enabled ~= true then return end
    local plugins = Table(core.plugins)
    local selection = Table(profile.enabledPlugins)
    if plugins and selection then return profile, plugins, selection end
end

local function Setup(output, map, add)
    local hbd = S.Dispatch(Library, "HereBeDragons-2.0")
    return {
        output = output, map = map, add = add, hbd = hbd, translate = Method(hbd, "TranslateZoneCoordinates"),
        worldBudget = FEED_LIMIT, nativeBudget = FEED_LIMIT, nativePoints = {}, points = 0,
    }
end

local function NativeMap(state)
    local getZone = Method(state.hbd, "GetPlayerZone")
    local zone = getZone and getZone(state.hbd)
    if PositiveInteger(zone) then return zone end
end

local function ReadPlugin(state, core, selection, name, plugin)
    local enabled = selection[name]
    if not Public(enabled) or enabled ~= true or not Table(plugin) then return end
    if name == "HandyNotes" then state.notes = S.Dispatch(OwnNotes, core) end
    for point in pairs(state.nativePoints) do state.nativePoints[point] = nil end
    state.nativeComplete = state.nativeHidden
    if state.nativeMap then
        state.nativeComplete = S.Dispatch(ReadNodes, state, plugin, name, state.nativeMap, true, CollectNative)
    end
    S.Dispatch(ReadNodes, state, plugin, name, state.map, false, CollectWorld)
end

-- The world pass is the source for the overlay and compass. When the Suite
-- minimap is enabled, a second bounded pass lets it add only world-only pins.
-- A partial native read can still prove presence, but cannot prove absence.
function HandyNotes.Read(output, map, add, classifyNative)
    if not PositiveInteger(map) then return end
    local core = _G.HandyNotes
    local profile, plugins, selection = S.Dispatch(Core, core)
    if not profile then return end
    local state = Setup(output, map, add)
    state.nativeHidden = classifyNative and Finite(profile.icon_alpha_minimap) and profile.icon_alpha_minimap <= 0
    state.nativeMap = classifyNative and not state.nativeHidden and S.Dispatch(NativeMap, state)
    ReadPlugin(state, core, selection, "HandyNotes", plugins.HandyNotes)
    local count = 1
    for key, plugin in pairs(plugins) do
        local name = Text(key)
        if count >= PLUGIN_LIMIT or state.worldBudget < 1 or state.points >= POINT_LIMIT then break end
        if name ~= "HandyNotes" then
            count = count + 1
            if name then ReadPlugin(state, core, selection, name, plugin) end
        end
    end
end

local function Updated()
    if listener then S.Dispatch(listener) end
end

local function Hook(core)
    local installed = hooked[core]
    if not installed then
        installed = {}
        hooked[core] = installed
    end
    for _, name in ipairs(HOOKS) do
        if not installed[name] and Method(core, name) then
            hooksecurefunc(core, name, Updated)
            installed[name] = true
        end
    end
end

function HandyNotes.Watch(callback)
    listener = callback
    local core = _G.HandyNotes
    if callback and Table(core) then S.Dispatch(Hook, core) end
end
