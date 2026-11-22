-- Suite tooltip line helpers share the TooltipLines.lua runtime. Rich cards
-- also need native comparison and restricted-data callbacks of their own.
-- No helper registers an insecure line pre-call (Blizzard then packs every
-- line of every tooltip through a forbidden attribute delegate and the
-- registration cannot be removed, TooltipDataHandler.lua) or asks GameTooltip
-- to rebuild from addon code (RefreshDataNextUpdate writes its update fields,
-- GameTooltip.lua).
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checked = 0

local function Code(source)
    -- Comments may name the APIs; only code counts.
    source = source:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
    return source
end

for _, addon in ipairs({ "MSUF_Suite_QualityOfLife", "MSUF_Suite_Tooltips" }) do
    for _, file in ipairs(Support.TocFiles(root, addon)) do
        if file:match("%.lua$") then
            local handle = assert(io.open(root .. "/" .. addon .. "/" .. file, "rb"))
            local code = Code(handle:read("*a"))
            handle:close()
            assert(not code:find("AddLinePreCall", 1, true), file .. " registers a tooltip line pre-call")
            assert(not code:find("RefreshDataNextUpdate", 1, true), file .. " asks GameTooltip to rebuild")
            if file ~= "ItemTooltipCard.lua" then
                assert(not code:find("AddTooltipPostCall", 1, true),
                    file .. " registers its own tooltip post-call instead of TooltipLines.lua")
            end
            checked = checked + 1
        end
    end
end
assert(checked > 50, "the tooltip and Quality of Life TOCs listed only " .. checked .. " files")
print("Suite tooltip pipeline: " .. checked .. " files checked")
