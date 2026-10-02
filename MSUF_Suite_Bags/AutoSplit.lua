local _, P = ...
local NS, S, M, Inventory = P.NS, P.Suite, P.BagsModule, P.SplitInventory
local AutoSplit = {}
P.AutoSplit = AutoSplit
local Step, Timeout
local EVENTS = { "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "CURSOR_CHANGED", "GUILDBANKBAGSLOTS_CHANGED",
    "GUILDBANK_ITEM_LOCK_CHANGED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_CLOSED", "PLAYER_REGEN_DISABLED" }

-- AutoSplit.onStop (StackSplitter.lua) runs after every stop, also the first one in Start.
-- The split's next step waits one frame (a ctx:Coalesce job); each step
-- restarts the 3-second timeout (ctx:After). Both run only while Bags runs.
function AutoSplit.Stop()
    AutoSplit.job = nil
    if M.context then M.context:Cancel(Timeout) end
    if AutoSplit.events then AutoSplit.events:UnregisterAllEvents() end
    if AutoSplit.onStop then AutoSplit.onStop() end
end

Timeout = function() AutoSplit.Stop() end

local function ArmTimeout()
    M.context:After(3, Timeout)
end

local function Destination(job)
    while job.next <= #job.destinations do
        local destination = job.destinations[job.next]
        local link, count, locked = Inventory.Read(destination)
        if not link and count == 0 and not locked then return destination end
        job.next = job.next + 1
    end
end

Step = function()
    local job = AutoSplit.job
    if not job then return end
    if not M.active or NS.IsCombatLocked() or not Inventory.Available(job.source) then
        AutoSplit.Stop()
        return
    end
    local kind, _, cursorLink = GetCursorInfo()
    if job.phase == "cursor" then
        if kind == nil then return end
        if kind ~= "item" or not S.Public(cursorLink) or cursorLink ~= job.link then
            AutoSplit.Stop()
            return
        end
        local link, count, locked = Inventory.Read(job.destination)
        if link or count ~= 0 or locked then
            AutoSplit.Stop()
            return
        end
        job.phase = "placed"
        Inventory.Place(job.destination)
        ArmTimeout()
        return
    end
    if job.phase == "placed" then
        if kind ~= nil then return end
        local link, count, locked = Inventory.Read(job.destination)
        if locked or count == 0 then return end
        if link ~= job.link or count ~= job.amount then
            AutoSplit.Stop()
            return
        end
        job.next, job.phase, job.completed = job.next + 1, "source", job.completed + 1
    elseif kind ~= nil then
        AutoSplit.Stop()
        return
    end
    if job.completed >= 128 then
        AutoSplit.Stop()
        return
    end
    local link, count, locked = Inventory.Read(job.source)
    if locked then return end
    if link ~= job.link or not S.Finite(count) or count <= job.amount then
        AutoSplit.Stop()
        return
    end
    job.destination = Destination(job)
    if not job.destination then
        AutoSplit.Stop()
        return
    end
    job.phase = "cursor"
    Inventory.Split(job.source, job.amount)
    ArmTimeout()
    AutoSplit.Request()
end

function AutoSplit.Request()
    if not AutoSplit.job then return end
    AutoSplit.stepJob = AutoSplit.stepJob or M.context:Coalesce(0, Step)
    AutoSplit.stepJob:Request()
end

local function Event(_, event)
    if event == "PLAYER_REGEN_DISABLED" or event == "BANKFRAME_CLOSED" or event == "GUILDBANKFRAME_CLOSED" then
        AutoSplit.Stop()
    else
        AutoSplit.Request()
    end
end

function AutoSplit.Start(owner, amount)
    AutoSplit.Stop()
    if not M.active or NS.IsCombatLocked() or not S.Finite(amount) or amount < 1 or GetCursorInfo() ~= nil then return false end
    local source = Inventory.Source(owner)
    if not source or not Inventory.Available(source) then return false end
    local link, count, locked = Inventory.Read(source)
    if not S.Public(link) or type(link) ~= "string" or locked or not S.Finite(count) or count <= amount then return false end
    local destinations = Inventory.Destinations(source, link)
    if #destinations == 0 then return false, "full" end
    AutoSplit.job = { source = source, link = link, amount = math.floor(amount), destinations = destinations,
        next = 1, completed = 0, phase = "source" }
    if not AutoSplit.events then
        AutoSplit.events = S.CreateFrame("Frame")
        AutoSplit.events:SetScript("OnEvent", Event)
    end
    for i = 1, #EVENTS do if NS.Client.SupportsEvent(EVENTS[i]) then AutoSplit.events:RegisterEvent(EVENTS[i]) end end
    ArmTimeout()
    Step()
    return true
end
