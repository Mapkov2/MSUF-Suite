-- Stored profiles are repaired, not refused (MSUF_Suite/Core/Suite.lua):
-- an over-long text from older or hand-edited saved data is cut to its
-- rule's byte limit at a character boundary, never inside a UTF-8 character.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")
local Suite = H.Setup({ root = root, forever = true })
local S = Suite.Suite

local limit = S.catalog.dataTexts.rules.bar1Name.maxLength
local profile = Suite.Database.CreateFactoryProfile()
-- One ASCII letter, then two-byte characters: the byte limit falls on the
-- first byte of a character.
local stored = "a" .. ("\195\169"):rep(limit)
profile.suite.modules.dataTexts.bar1Name = stored
S.Normalize(profile)
local repaired = profile.suite.modules.dataTexts.bar1Name
assert(#repaired <= limit, "the repaired name is still longer than its rule allows")
assert(repaired == stored:sub(1, #repaired), "the repair changed the kept text")
local last = repaired:byte(#repaired)
assert(not (last >= 192), "the repaired name ends with the first byte of a split character")
assert(repaired == "a" .. ("\195\169"):rep(math.floor((limit - 1) / 2)),
    "the repaired name lost whole characters: " .. #repaired .. " bytes")
assert(#H.reported == 0, "a call raised: " .. tostring(H.reported[1]))
print("repair text contract: ok (" .. #repaired .. " of " .. limit .. " bytes)")
