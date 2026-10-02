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
