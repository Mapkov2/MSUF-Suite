local _,P=...
P.NS=P.NS or assert(_G.MSUFSuite,"MSUF_Suite is required")
P.Suite=P.Suite or P.NS.Suite
local NS=P.NS
-- Private state shared by every runtime file (see the build spec, section
-- 11). The module object exists from the first file on so each file can
-- attach to it; Controller.lua installs it last. EMPTY is the shared
-- read-only sentinel: writes to it are dropped, so it can never fill up.
-- wipe is the client's table.wipe (a plain loop where there is none).
local CDM=assert(NS.CDM,"MSUF_Suite is missing its cooldown manager catalog")
P.CDM={
    M={},
    EMPTY=setmetatable({},{__newindex=function() end}),
    wipe=table.wipe or wipe or function(t) for k in pairs(t) do t[k]=nil end return t end,
    state={inCombat=false,preview=false,soundQuietUntil=0},
    views={},plans={},bars={},entries={},
    lists=CDM.CleanLists(nil),
    spells=CDM.CleanSpells(nil),
}
