local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client.isForever then return end
local Labels = {}
P.ForeverMapLabels = Labels
local levels = P.ForeverMapData.levels
local names = {}

local function BuildNames(mapID)
    local children = C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Zone, true)
    if not S.Public(children) or type(children) ~= "table" then return end
    for i = 1, #children do
        local info = children[i]
        if S.Public(info) and type(info) == "table" and S.Finite(info.mapID) then
            local name = S.PublicText(info.name)
            if name then names[name] = info.mapID end
        end
    end
end

local function Range(mapID)
    local low, high = C_Map.GetMapLevels(mapID)
    if S.Finite(low) and S.Finite(high) and low > 0 and high >= low then return low, high end
    local fallback = levels[mapID]
    if fallback then return fallback[1], fallback[2] end
end

local function Paint(owner, raw)
    if not owner.active or not owner.config.zoneLevels then return end
    if not S.Public(raw) or owner.labelRaw == raw then return end
    if not owner.map or not owner.map:IsShown() then return end
    owner.labelRaw = raw
    -- Native AreaLabel can SetText every hovered frame. All work below this
    -- equality gate happens only when its public text changes.
    local name = S.PublicText(raw)
    if not name or name:find("%(%d+%-?%d*%)") then return owner.label:Hide() end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local mapID = names[name]
    local low, high
    if mapID then low, high = Range(mapID) end
    if not low then return owner.label:Hide() end
    local level = UnitLevel("player")
    if not S.Finite(level) then return owner.label:Hide() end
    local color = GetQuestDifficultyColor(level < low and low or level > high and high - 2 or level)
    owner.label:SetText(S.Text("Levels %d-%d"):format(low, high))
    owner.label:SetTextColor(color.r, color.g, color.b)
    owner.label:Show()
end

function Labels.Attach(owner)
    if not owner.config.zoneLevels then
        if owner.label then owner.label:Hide() end
        return
    end
    if not owner.zoneNamesBuilt then
        owner.zoneNamesBuilt = true
        BuildNames(947)
        for mapID in pairs(levels) do
            local info = C_Map.GetMapInfo(mapID)
            local name = S.Public(info) and info and S.PublicText(info.name)
            if name then names[name] = mapID end
        end
    end
    for provider in pairs(owner.map.dataProviders) do
        local native = provider.Label
        if native and native.Name then
            if owner.nativeLabel ~= native.Name then
                owner.nativeLabel = native.Name
                owner.label = owner.label or S.CreateFontString(native, nil, "OVERLAY")
                owner.label:SetPoint("TOP", native.Name, "BOTTOM", 0, -2)
                hooksecurefunc(native.Name, "SetText", function(_, text) Paint(owner, text) end)
            end
            S.SetFont(owner.label, S.GlobalFontPath(), 12, "OUTLINE")
            owner.labelRaw = nil
            Paint(owner, native.Name:GetText())
            return
        end
    end
end

function Labels.Refresh(owner)
    owner.labelRaw = nil
    if owner.nativeLabel and owner.label then Paint(owner, owner.nativeLabel:GetText()) end
end
