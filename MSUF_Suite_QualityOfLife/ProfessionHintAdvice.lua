local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client.isForever then return end

local Data = P.ProfessionHintData
local A = {}
P.ProfessionHintAdvice = A

function A.SkillLine(id)
    if not S.Finite(id) then return end
    return Data.baseSkillLines[id] or id
end

function A.GatheringRow(rows, skill, bonus, cap)
    if not rows then return end
    local row, target
    for _, candidate in ipairs(rows) do
        if skill + bonus < candidate[1] then
            target = candidate[1] - bonus
            break
        end
        row = candidate
    end
    return row, math.min(target or cap, cap)
end

local function RecipeScore(recipe, skill)
    if skill < recipe[3] then return 3, recipe[3] end
    if skill < recipe[4] then return 2, recipe[4] end
    return 1, recipe[5]
end

-- Prefer the better skill-up color, then an already known recipe. The curated
-- order breaks ties in favor of inexpensive reagents and easy recipe sources.
function A.Recipes(rows, skill, cap, readRecipe)
    if not rows then return end
    local best, alternative, bestScore, altScore
    for _, recipe in ipairs(rows) do
        if skill >= recipe[2] and skill < recipe[5] then
            local learned, canSkillUp = readRecipe(recipe[1])
            if canSkillUp ~= false or learned ~= true then
                local score, target = RecipeScore(recipe, skill)
                score = score * 2 + (learned == true and 1 or 0)
                local choice = { recipe = recipe, target = math.min(target, cap), learned = learned }
                if not bestScore or score > bestScore then
                    alternative, altScore = best, bestScore
                    best, bestScore = choice, score
                elseif not altScore or score > altScore then
                    alternative, altScore = choice, score
                end
            end
        end
    end
    return best, alternative
end

function A.MapName(id)
    local info = C_Map.GetMapInfo(id)
    return S.Public(info) and type(info) == "table" and S.PublicText(info.name) or Data.mapNames[id]
end

local function WorldPosition(map, position)
    if not S.Public(position) or not position or not S.Finite(position.x) or not S.Finite(position.y) then return end
    local instance, point = C_Map.GetWorldPosFromMapPos(map, position)
    if S.Finite(instance) and S.Public(point) and point then
        local x, y = point.x, point.y
        if S.Finite(x) and S.Finite(y) then return instance, x, y end
    end
end

local function PlayerPosition()
    local map = C_Map.GetBestMapForUnit("player")
    if not S.Finite(map) or map <= 0 then return end
    return map, WorldPosition(map, C_Map.GetPlayerMapPosition(map, "player"))
end

local function Distance(map, here, instance, x, y, point)
    if map == here then return -1 end
    if not instance then return math.huge end
    local remote, rx, ry = WorldPosition(map, point)
    if remote ~= instance then return math.huge, remote ~= nil end
    local dx, dy = x - rx, y - ry
    return dx * dx + dy * dy
end

local function Nearer(a, b)
    if a.distance == b.distance then return a.index < b.index end
    return a.distance < b.distance
end

function A.Zones(maps)
    local here, instance, x, y = PlayerPosition()
    local center = instance and CreateVector2D(.5, .5)
    local ordered = {}
    for index, map in ipairs(maps) do
        local distance, other = Distance(map, here, instance, x, y, center)
        ordered[index] = { map = map, index = index, distance = distance, other = other }
    end
    table.sort(ordered, Nearer)
    local names = {}
    for index = 1, math.min(3, #ordered) do
        local row = ordered[index]
        local name = A.MapName(row.map)
        if name then
            if row.other then name = S.Text("%s (other continent)"):format(name) end
            names[#names + 1] = name
        end
    end
    return table.concat(names, ", ")
end

function A.Trainer(rows, faction)
    if not rows then return end
    local here, instance, x, y = PlayerPosition()
    local center = instance and CreateVector2D(.5, .5)
    local nearest, best
    for _, row in ipairs(rows) do
        if not row[3] or row[3] == faction then
            local distance = Distance(row[1], here, instance, x, y, center)
            if not nearest or distance < best then
                nearest, best = row, distance
            end
        end
    end
    return nearest
end
