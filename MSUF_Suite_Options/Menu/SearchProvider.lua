local _, P = ...
local M, Suite = P.M, P.Suite
if type(M.RegisterSearchProvider) ~= "function" then return end
local EMPTY_ROWS = {}

-- Each host caps a provider's rows. Keep ordinary modules separate from
-- dynamic bars, partitioned by configured ordinal rather than numeric ID.
-- The host collects sorted provider names once per invalidated rebuild, so
-- the base callback generates every row once and the fixed siblings reuse it.
local ROWS_PER_PROVIDER, EXTRA_PROVIDERS = 4000, 2
local BARS_PER_GROUP = 16
local TRIM_CHECKPOINT_ROWS = 64
local GROUP_COUNT = math.ceil(Suite.DataTextBarLimit / BARS_PER_GROUP)
local barGroups, baseOverflow = {}, {}
local function Partition(checkpoint)
    local ordinal = {}
    for index, bar in ipairs(Suite.DataTextBarIDs(P.S.Config("dataTexts"))) do
        ordinal[tostring(bar)] = math.ceil(index / BARS_PER_GROUP)
    end
    local rows, baseCount = P.SearchRows(checkpoint), 0
    -- Keep ordinary builds in one array. A large dynamic-bar profile needs a
    -- separate base bucket so it can release the large input array promptly.
    local base = #rows <= 2 * ROWS_PER_PROVIDER and rows or {}
    local groups, overflow = {}, {}
    for read, row in ipairs(rows) do
        if checkpoint then checkpoint() end
        local bar = row.pageKey == "suite_dataTexts" and
            ((row.suiteRuleKey or ""):match("^bar(%d+)") or (row.sectionId or ""):match("^suite_dataTexts_bar(%d+)"))
        local group = bar and ordinal[bar]
        if group then
            local rows = groups[group]
            if not rows then
                rows = {}
                groups[group] = rows
            end
            rows[#rows + 1] = row
        elseif not bar then
            local page = math.floor(baseCount / ROWS_PER_PROVIDER)
            if page == 0 then
                if base ~= rows or baseCount + 1 ~= read then base[baseCount + 1] = row end
            else
                local bucket = overflow[page]
                if not bucket then
                    bucket = {}
                    overflow[page] = bucket
                end
                bucket[#bucket + 1] = row
            end
            baseCount = baseCount + 1
        end
    end
    if base == rows then
        for index = #rows, math.min(baseCount, ROWS_PER_PROVIDER) + 1, -1 do
            rows[index] = nil
            if checkpoint and index % TRIM_CHECKPOINT_ROWS == 0 then checkpoint() end
        end
    end
    -- Sibling providers see either the old complete partition or the new one.
    barGroups, baseOverflow = groups, overflow
    return base
end

function P.RegisterSuiteSearch(contextChanged)
    local function CollectBase(checkpoint)
        -- The first later context check must compare against what we actually collected.
        contextChanged()
        return Partition(checkpoint)
    end
    -- The host owns the job and its deadline. Abandoning the step also drops
    -- its coroutine, including its private rows and all loop positions.
    local function BeginBase()
        return coroutine.wrap(function(due)
            local work = 0
            local function Checkpoint()
                work = work + 1
                if work == 4 then
                    work = 0
                    if due() then due = coroutine.yield(nil, false) end
                end
            end
            return CollectBase(Checkpoint), true
        end)
    end
    P.searchRegistered = M.RegisterSearchProvider("MSUF_Suite", CollectBase, contextChanged, BeginBase) == true
    for index = 1, EXTRA_PROVIDERS do
        local page = index
        M.RegisterSearchProvider("MSUF_Suite.Controls." .. page, function()
            return baseOverflow[page] or EMPTY_ROWS
        end)
    end
    for index = 1, GROUP_COUNT do
        local group = index
        M.RegisterSearchProvider("MSUF_Suite.DataTexts." .. string.format("%02d", group), function()
            return barGroups[group] or EMPTY_ROWS
        end)
    end
    if M.InvalidateSearchProvider then
        function P.InvalidateSearch() M.InvalidateSearchProvider("MSUF_Suite") end
    else
        -- Registering again clears the host's cached rows of every provider; the
        -- DataText siblings read the partition the base collector refills first.
        function P.InvalidateSearch() M.RegisterSearchProvider("MSUF_Suite", CollectBase, contextChanged, BeginBase) end
    end
end
