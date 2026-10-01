local _, P = ...
local S = P.Suite
local Finite = S.Finite
local Tr = S.Text

-- The party table of a Mythic+ result card. partyDetails picks how much it
-- shows: 2 characters and scores, 3 adds the combat figures of Blizzard's
-- damage meter, 4 adds the loot seen in chat. One cell may join two values
-- (build = specialization and item level, score = rating and its change).
local Party = {}
P.RunSummaryParty = Party
local SEPARATOR = "  \194\183  "
local COLUMNS = {
    { field = "name", title = "Character", width = 132, level = 2, sort = "name" },
    { field = "build", title = "Build", width = 128, level = 2, sort = "ilvl" },
    { field = "score", title = "Score", width = 98, level = 2, sort = "rating" },
    { field = "damage", title = "Damage", width = 148, level = 3, sort = "damage" },
    { field = "damageTaken", title = "Taken", width = 76, level = 3, sort = "damageTaken" },
    { field = "interrupts", title = "Kicks", width = 54, level = 3, sort = "interrupts" },
    { field = "deaths", title = "Deaths", width = 56, level = 3, sort = "deaths" },
    { field = "loot", title = "Loot", width = 210, level = 4, sort = "lootCount" },
}

local function Amount(value)
    return AbbreviateLargeNumbers(math.floor(value + .5))
end

-- The text of one cell, or nil when the player has no value for it.
local CELLS = {
    name = function(player) return player.name end,
    build = function(player)
        local ilvl = Finite(player.ilvl) and tostring(math.floor(player.ilvl)) or nil
        if player.spec and ilvl then return player.spec .. SEPARATOR .. ilvl end
        return player.spec or ilvl
    end,
    score = function(player)
        local rating, change = Finite(player.rating) and player.rating, Finite(player.scoreDelta) and player.scoreDelta
        if rating and change then return string.format("%.0f (%+.0f)", rating, change) end
        if rating then return string.format("%.0f", rating) end
        if change then return string.format("%+.0f", change) end
    end,
    damage = function(player)
        if not Finite(player.damage) then return nil end
        if not Finite(player.damagePerRunSecond) then return Amount(player.damage) end
        return Tr("%s  (%s/s)"):format(Amount(player.damage), Amount(player.damagePerRunSecond))
    end,
    damageTaken = function(player) return Finite(player.damageTaken) and Amount(player.damageTaken) or nil end,
    interrupts = function(player) return Finite(player.interrupts) and tostring(math.floor(player.interrupts)) or nil end,
    deaths = function(player) return Finite(player.deaths) and tostring(math.floor(player.deaths)) or nil end,
    loot = function(player)
        return type(player.loot) == "table" and #player.loot > 0 and table.concat(player.loot, "\n") or nil
    end,
}

local function SortValue(player, key)
    if key == "lootCount" then return type(player.loot) == "table" and #player.loot or nil end
    return player[key]
end

local function Sorted(self, players)
    local sorted = {}
    for _, player in ipairs(players) do sorted[#sorted + 1] = player end
    local key, ascending = self.sortField or "name", self.sortAscending
    table.sort(sorted, function(a, b)
        local av, bv = SortValue(a, key), SortValue(b, key)
        if av == bv then return (a.name or "") < (b.name or "") end
        if av == nil then return false end
        if bv == nil then return true end
        if type(av) == "number" then
            if ascending then return av < bv end
            return av > bv
        end
        if ascending == false then return av > bv end
        return av < bv
    end)
    return sorted
end

-- Columns the detail level allows and at least one player can fill.
local function Columns(level, players)
    local columns, width = {}, 0
    for _, column in ipairs(COLUMNS) do
        local available = column.level <= level and column.field == "name"
        if column.level <= level and not available then
            for _, player in ipairs(players) do
                if CELLS[column.field](player) then
                    available = true
                    break
                end
            end
        end
        if available then
            columns[#columns + 1] = column
            width = width + column.width
        end
    end
    return columns, width
end

local function HideAll(self)
    for _, header in pairs(self.playerHeaders or {}) do header:Hide() end
    for _, row in ipairs(self.playerRows or {}) do
        for _, cell in pairs(row) do cell:Hide() end
    end
end

local function Header(self, column)
    local header = self.playerHeaders[column.field]
    if header then return header end
    header = S.CreateFrame("Button", nil, self.host)
    header.label = S.CreateFontString(header, nil, "OVERLAY")
    header.label:SetAllPoints(header)
    header.label:SetJustifyH("LEFT")
    header:SetScript("OnClick", function()
        if self.sortField == column.sort then
            self.sortAscending = not self.sortAscending
        else
            self.sortAscending = column.sort == "name"
        end
        self.sortField = column.sort
        self:Refresh()
    end)
    self.playerHeaders[column.field] = header
    return header
end

local function Cell(self, index, field)
    local row = self.playerRows[index]
    if not row then
        row = {}
        self.playerRows[index] = row
    end
    local cell = row[field]
    if not cell then
        cell = S.CreateFontString(self.host, nil, "OVERLAY")
        row[field] = cell
    end
    return cell
end

local function PaintColumn(self, column, sorted, x, top, rowHeight, style)
    local header = Header(self, column)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", x, top)
    header:SetSize(column.width - 5, rowHeight)
    S.SetStyledFont(header.label, style.font, 10, "OUTLINE", 1, true, 70, 1)
    header.label:SetText(Tr(column.title))
    header:Show()
    for i, player in ipairs(sorted) do
        local cell = Cell(self, i, column.field)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", x, top - i * rowHeight)
        cell:SetWidth(column.width - 5)
        cell:SetJustifyH("LEFT")
        cell:SetWordWrap(column.field == "loot")
        S.SetStyledFont(cell, style.font, style.size, "OUTLINE", 1, true, 70, 1)
        cell:SetText(CELLS[column.field](player) or "--")
        cell:SetTextColor(style.r, style.g, style.b)
        cell:Show()
    end
end

-- Paints the table below top; returns the new top and the table width.
function Party.Paint(self, result, top, style)
    local level = self.config.partyDetails or 3
    if level <= 1 or result.kind ~= "mythic" or not result.players or #result.players == 0 then
        HideAll(self)
        return top, 0
    end
    self.playerHeaders, self.playerRows = self.playerHeaders or {}, self.playerRows or {}
    local columns, totalWidth = Columns(level, result.players)
    local sorted = Sorted(self, result.players)
    HideAll(self)
    local rowHeight, x = self.config.playerRowHeight or 25, 18
    if level >= 4 then
        for _, player in ipairs(sorted) do
            if type(player.loot) == "table" then rowHeight = math.max(rowHeight, math.min(#player.loot, 8) * 28) end
        end
    end
    for _, column in ipairs(columns) do
        PaintColumn(self, column, sorted, x, top, rowHeight, style)
        x = x + column.width
    end
    return top - (#sorted + 1) * rowHeight - 8, totalWidth + 36
end
