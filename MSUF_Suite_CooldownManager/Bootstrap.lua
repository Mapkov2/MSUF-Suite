local _, P = ...
P.NS = assert(_G.MSUFSuite, "MSUF_Suite is required")
P.Suite = P.NS.Suite
local NS = P.NS
-- Private state shared by every runtime file. The module object exists from
-- the first file on so each file can attach to it; Controller.lua installs
-- it last. EMPTY is the shared read-only sentinel: writes to it are dropped,
-- so it can never fill up. wipe is the client's table.wipe. Diagnostics:
-- read-only views of module state for the contract tests; nothing in the
-- addon calls them, and they sit in this one table so the modules' own API
-- stays free of test hooks.
local CDM = assert(NS.CDM, "MSUF_Suite is missing its cooldown manager catalog")
P.CDM = {
    M = {},
    EMPTY = setmetatable({}, { __newindex = function() end }),
    wipe = table.wipe,
    Diagnostics = {},
    state = { inCombat = false, preview = false, soundQuietUntil = 0 },
    views = {}, plans = {}, bars = {}, entries = {},
    lists = CDM.CleanLists(nil),
    spells = CDM.CleanSpells(nil),
}

-- Wakes: the trailing refresh of a throttle window, one fixed callback
-- behind its caller's own armed flag. On Retail 12.1.5 and WoW Forever a
-- wake is a key of one C-side timed signal map (C_Timer.NewTimedSignalMap),
-- so arming a window makes no timer object; 12.1.0 has none and a wake is a
-- C_Timer.After. Either way a disable leaves a wake to fire: its callback
-- drops the armed flag and finds the module inactive, so no window stays
-- armed without a wake behind it. The first wake picks the way (the map is
-- made then); each wake on the map runs isolated, so one that raises never
-- keeps another of its pass from running.
local C = P.CDM
local wakeFns, wakes = {}, nil
local function Woke(key) P.Suite.Dispatch(wakeFns[key]) end
-- A number for fn, registered once at load.
function C.NewWake(fn)
    wakeFns[#wakeFns + 1] = fn
    return #wakeFns
end
local function SignalWake(key, delay) wakes:SignalAfter(key, delay) end
local function AfterWake(key, delay) C_Timer.After(delay, wakeFns[key]) end
function C.Wake(key, delay)
    local NewTimedSignalMap = C_Timer.NewTimedSignalMap
    if NewTimedSignalMap then wakes = NewTimedSignalMap(Woke) end
    C.Wake = wakes and SignalWake or AfterWake
    return C.Wake(key, delay)
end
