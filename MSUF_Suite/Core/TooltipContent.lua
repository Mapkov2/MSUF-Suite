local _, Suite = ...
local Content = {}
Suite.TooltipContent = Content

local rules = {
    unit = {
        { "guild", "Guild details", { "guildRank" } },
        { "target", "Target", { "target" } },
        { "location", "Location", { "unitLocation" } },
        { "threat", "Threat", { "unitThreatStatus", "unitThreatPercent" } },
        { "watchers", "Targeted by", { "unitTargeters" } },
    },
    creature = {
        { "target", "Target", { "target" } },
        { "threat", "Threat", { "unitThreatStatus", "unitThreatPercent" } },
        { "watchers", "Targeted by", { "unitTargeters" } },
    },
    item = {
        { "stack", "Maximum stack", { "maxStack" } },
        { "icon", "Item icon ID", { "iconID" } },
    },
}
Content.Fields = { unit = "unitContentOrder", creature = "creatureContentOrder", item = "itemContentOrder" }

function Content.Groups(kind) return rules[kind] end

-- Preserve known keys once, then add any groups introduced after the profile
-- was saved in their original order.
function Content.Order(kind, saved)
    local allowed, seen, result = {}, {}, {}
    local groups = rules[kind]
    for index = 1, #groups do allowed[groups[index][1]] = true end
    if type(saved) == "string" then
        for key in saved:gmatch("[a-z]+") do
            if allowed[key] and not seen[key] then
                seen[key] = true
                result[#result + 1] = key
            end
        end
    end
    for index = 1, #groups do
        local key = groups[index][1]
        if not seen[key] then result[#result + 1] = key end
    end
    return result
end

function Content.Priorities(kind, saved)
    local priorities, byKey = {}, {}
    local groups, ordered = rules[kind], Content.Order(kind, saved)
    for index = 1, #ordered do byKey[ordered[index]] = index end
    for index = 1, #groups do
        local group = groups[index]
        for _, field in ipairs(group[3]) do priorities[field] = byKey[group[1]] end
    end
    return priorities
end
