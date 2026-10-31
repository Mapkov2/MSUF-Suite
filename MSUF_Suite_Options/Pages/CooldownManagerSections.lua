local _, P = ...
-- Section actions use the same popup and undo transaction as the existing
-- whole-bar copy. Identity, attachment and position stay with each bar.
local Page = P.CDMPage

function Page.SectionTargets(from)
    local targets = { { value = "all", text = "All compatible bars" } }
    local CDM = P.Suite.CDM
    local kind = Page.Kind(from)
    local timers = kind == CDM.KIND.COOLDOWN and P.Get(Page.ID, CDM.KEYS[from].cooldownDuration) == true
    for _, slot in ipairs(CDM.SLOTS) do
        local other = slot.key
        local same = Page.Kind(other) == kind
        if same and kind == CDM.KIND.COOLDOWN then
            same = (P.Get(Page.ID, CDM.KEYS[other].cooldownDuration) == true) == timers
        end
        if other ~= from and Page.Listed(other) and same then
            targets[#targets + 1] = { value = other, text = Page.BarName(other), translate = false }
        end
    end
    return targets
end

function Page.CopySection(spec, from, target)
    if P.Combat() then return false end
    local CDM = P.Suite.CDM
    if not CDM.KEYS[from] then return false end
    local skip = { on = true, name = true, kind = true, anchor = true, anchorFrame = true,
        x = true, y = true, shareContents = true }
    local values, keys, count = {}, {}, 0
    for _, item in ipairs(Page.SectionTargets(from)) do
        local to = item.value
        if to ~= "all" and (target == "all" or target == to) then
            count = count + 1
            for _, suffix in ipairs(spec.suffixes) do
                if not skip[suffix] and Page.Relevant(from, suffix) and Page.Relevant(to, suffix) then
                    local key = CDM.KEYS[to][suffix]
                    local value = P.Get(Page.ID, CDM.KEYS[from][suffix])
                    if P.Get(Page.ID, key) ~= value then values[key], keys[#keys + 1] = value, key end
                end
            end
        end
    end
    if count == 0 then return false end
    if #keys == 0 then return true end
    local ok, reason = Page.WithUndo(P.Tr("Copied this section to %d bars."):format(count), keys,
        function() return P.SetMany(Page.ID, values) end)
    if not ok then Page.Fail(reason) end
    return ok
end

function Page.SectionCopy(spec)
    return {
        source = function() return Page.selected end,
        sourceLabel = Page.BarName,
        targets = Page.SectionTargets,
        run = function(from, target) return Page.CopySection(spec, from, target) end,
    }
end
