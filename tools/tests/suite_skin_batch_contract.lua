-- Reuse the independent public-API world; exercise real batch/queue/release
-- code rather than copying product helpers into the fixture.
local root = assert(arg[1])
local file = assert(io.open(root .. "/tools/tests/longterm_skin_cases.lua", "rb"))
local text = file:read("*a")
file:close()
local at = assert(text:find('if case == "public-fault"', 1, true))
local previous = arg[2]
arg[2] = "batch"
local makeWorld = assert(loadstring(text:sub(1, at - 1) .. "\nreturn PublicWorld"))()
arg[2] = previous
local world = makeWorld()
local jobs, checks = {}, 0
C_Timer.After = function(_, job) jobs[#jobs + 1] = job end
local function Check(value, why) checks = checks + 1 assert(value, why) end
local function Flush()
    for _ = 1, 10 do
        if #jobs == 0 then return end
        local pending = jobs
        jobs = {}
        for _, job in ipairs(pending) do job() end
    end
    error("unbounded batch work")
end
local skin = assert(world.api:RegisterAddon("BatchContract"))
Check(world.api:HasCapability("batches"), "batch capability is absent")
local entries = {}
for index = 1, 256 do
    entries[index] = { kind = "frame", target = { CreateTexture = function() end,
        IsProtected = function() return false, false end }, options = { role = "shell" } }
end
local ok, reason, count = skin:SkinBatch(entries)
Check(ok and count == 256 and world.attempts == 0, "cold batch did not retain its targets until ready")
world.NS.PublicAPI.Activate()
world.NS.PublicAPI.OnPlayerLogin()
skin:SkinBatch(entries) skin:SkinBatch(entries)
Flush()
Check(world.attempts == 512 and #world.reports == 0, "ready/cold batch requests did not coalesce per target: " .. world.attempts .. " / " .. #world.reports .. " / " .. tostring(world.reports[1]))
local before = world.attempts
Check(not skin:SkinBatch({ [2] = entries[1] }), "sparse batch was accepted")
Check(not skin:SkinBatch(setmetatable({}, {})), "batch metatable was accepted")
Check(not skin:SkinBatch({ entries[1], { kind = "callback", target = entries[2].target } }), "callback kind was accepted")
entries[257] = entries[1]
Check(not skin:SkinBatch(entries), "oversized batch was accepted")
entries[257] = nil
Flush()
Check(world.attempts == before, "malformed batch queued partial shape work")
assert(skin:ReleaseAll()) Flush()
Check(world.cleaned == 256, "batch release retained targets")
Check(skin:SkinBatch(entries), "released batch could not be acquired again") Flush()
Check(world.attempts == 768, "reacquired targets did not repaint")
print("Suite skin batch: " .. checks .. " checks passed")
