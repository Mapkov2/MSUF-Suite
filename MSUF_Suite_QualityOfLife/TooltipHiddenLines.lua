local _, P = ...
local S = P.Suite

-- Blanks the faction, PvP and guild lines of a unit tooltip and the realm of
-- a name. It changes the text of the tooltip's own lines after Blizzard built
-- them and before the tooltip is sized (TooltipLines.lua); Blizzard's line
-- data stays as it was, and a line whose text is not public is never touched.
local H = {}
S.TooltipHiddenLines = H
-- Lines examined after the name line.
local MAX_LINES = 20

local function PublicTable(value)
    return S.Public(value) and type(value) == "table" and canaccesstable(value)
end

-- The unit's guild name, its localized faction and Blizzard's PvP label, each
-- only when the player hides it and the client lets addons read it.
local function Targets(unit, config)
    local guild = config.hideGuild and S.PublicText((GetGuildInfo(unit))) or nil
    local faction = config.hideFaction and S.PublicText(select(2, UnitFactionGroup(unit))) or nil
    return guild, faction, config.hidePvP and S.PublicText(PVP) or nil
end

local function Blank(row)
    local index = row.lineIndex
    local line = S.Finite(index) and index > 1 and _G["GameTooltipTextLeft" .. index]
    if line then line:SetText("") end
end

-- The guild line reads "<Guild name>", possibly followed by more text.
local function IsGuildLine(text, guildLine)
    return guildLine ~= nil and text:sub(1, #guildLine) == guildLine
end

function H.Lines(data, unit, config)
    if not (config.hideGuild or config.hideFaction or config.hidePvP) then return end
    local guild, faction, pvp = Targets(unit, config)
    local rows = data.lines
    if not (guild or faction or pvp) or not PublicTable(rows) then return end
    local guildLine = guild and "<" .. guild .. ">"
    for i = 2, math.min(#rows, MAX_LINES) do
        local row = rows[i]
        local text = PublicTable(row) and S.PublicText(row.leftText)
        if text and (text == faction or text == pvp or IsGuildLine(text, guildLine)) then Blank(row) end
    end
end

-- The name line of a player from another realm ends with the realm, after a
-- hyphen with or without spaces. Titles and the name stay.
function H.Realm(unit, nameText, row)
    local text = nameText and S.PublicText(row.leftText)
    local realm = select(2, UnitName(unit))
    realm = S.PublicText(realm)
    if not (text and realm) then return end
    local cut = #text - #realm
    if cut < 2 or text:sub(cut + 1) ~= realm then return end
    local name = text:sub(1, cut):gsub("[%s%-]+$", "")
    if name ~= "" then nameText:SetText(name) end
end
