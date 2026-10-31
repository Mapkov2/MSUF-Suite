-- Measure Options execution through the existing Suite/Menu2 fixture.
-- Bytecode compilation and the client's LoadAddOn native cost are separate.
local root = assert(arg[1]):gsub("\\", "/")
arg[1] = root
local baseline, originalLoad = os.getenv("SUITE_A7_BASELINE"), loadfile
if baseline then
    loadfile = function(path)
        local relative = path:sub(1, #root + 1) == root .. "/" and path:sub(#root + 2)
        local candidate = relative and baseline .. "/" .. relative
        local file = candidate and io.open(candidate, "rb")
        if file then file:close(); return originalLoad(candidate) end
        return originalLoad(path)
    end
end
local file = assert(io.open(root .. "/tools/tests/suite_options_menu_contract.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
-- Compile the actual chunks before the measured ADDON_LOADED/Attach action.
-- This isolates the removable execution work from parsing all Options files.
local chunks = {}
local toc = assert(io.open(root .. "/MSUF_Suite_Options/MSUF_Suite_Options_Mainline.toc", "rb"))
for line in toc:lines() do
    line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
    if line ~= "" and line:sub(1, 1) ~= "#" then
        local path = root .. "/MSUF_Suite_Options/" .. line:gsub("\\", "/")
        chunks[#chunks + 1] = assert(loadfile(path))
    end
end
toc:close()
source = source:gsub('local function LoadTOC%(addon, ns%)', [[local function LoadTOC(addon, ns)
    if addon == "MSUF_Suite_Options" then
        for _, chunk in ipairs(A7_CHUNKS) do chunk(addon, ns) end
        return
    end]], 1)
source = source:gsub('assert%(Suite.Menu.Attach%(%), "suite menu did not attach"%)', [[
    A7_BEGIN()
    assert(Suite.Menu.Attach(), "suite menu did not attach")
    A7_END()
]], 1)
local run = assert(loadstring(source, "@options-load-world"))
SUITE_OPTIONS_FIXTURE, A7_CHUNKS = true, chunks
local vm, kb, calls, before, native = 0, 0, 0, 0, {}
for pass = 1, 2 do
    A7_BEGIN = function()
        if pass == 1 then
            collectgarbage("collect")
            collectgarbage("stop")
            before = collectgarbage("count")
            debug.sethook(function() vm = vm + 1 end, "", 1)
        else
            native[C_AddOns.LoadAddOn], native[C_AddOns.IsAddOnLoaded] = true, true
            native[CreateFrame], native[issecretvalue], native[InCombatLockdown] = true, true, true
            native[table.sort] = true
            debug.sethook(function(event)
                if event == "call" and native[debug.getinfo(2, "f").func] then calls = calls + 1 end
            end, "c")
        end
    end
    A7_END = function()
        debug.sethook()
        if pass == 1 then kb = collectgarbage("count") - before; collectgarbage("restart") end
    end
    local world = run()
    local P = world.optionsNS
    -- Deferred rank compilation has exactly the same values and override rules.
    for id, spec in pairs(P.catalog) do
        local rank = 0
        for key in (spec.summary or ""):gmatch("%S+") do
            rank = rank + 1
            assert(P.SummaryPriority(id, key) == rank, "summary rank changed: " .. id .. "." .. key)
        end
    end
    P.RegisterSummary("A7Probe", "first second")
    assert(P.SummaryPriority("A7Probe", "second") == 2)
    P.RegisterSummary("A7Probe", "second first")
    assert(P.SummaryPriority("A7Probe", "second") == 1)
    assert(P.SummaryPriority("A7Probe", "absent") == nil)
    assert(#P.QualityOfLifeCategories > 0 and #P.QualityOfLifeSearchFeatures > 0,
        "cold navigation/search identities disappeared")
    if P.SortQualityOfLifeCategories then
        assert(not P.qualityOfLifeSorted, "hidden QoL categories were sorted during load")
        P.SortQualityOfLifeCategories()
    end
    local function Ordered(list)
        for index = 2, #list do
            assert(P.Tr(list[index - 1].title) <= P.Tr(list[index].title), "visible QoL order changed")
        end
    end
    Ordered(P.QualityOfLifeCategories)
    for _, category in ipairs(P.QualityOfLifeCategories) do
        Ordered(category.features)
        if category.tabs then
            Ordered(category.tabs)
            for _, tab in ipairs(category.tabs) do Ordered(tab.features) end
        end
    end
end
print(string.format("BUDGET options-attach-execution vm=%d kb=%.3f native=%d", vm, kb, calls))
if not os.getenv("SUITE_A7_MEASURE_ONLY") then
    -- Thirteen opt-in planning/inventory/everyday entries and their cold menu routes:
    -- same-run baseline 37260 VM / 379.287 KiB / 8 native; new 38273 / 389.034 / 8.
    -- This allows 12 KiB for the new reachable controls; execution/native limits stay fixed.
    -- The eager-summary mutation remains above this ceiling (395.358 KiB).
    assert(vm < 54000 and kb < 392 and calls < 10, "Options load execution budget exceeded")
end
print("RECEIPT all catalog summary ranks and overrides; cold QoL category/feature identities present")
SUITE_OPTIONS_FIXTURE, A7_CHUNKS, A7_BEGIN, A7_END = nil, nil, nil, nil
