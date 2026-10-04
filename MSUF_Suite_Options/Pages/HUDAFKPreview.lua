local _, P = ...
local V, Tr = P.HUDPreview, P.Tr
local GOLD, WHITE, MUTED = { .88, .69, .42 }, { .96, .95, .91 }, { .67, .72, .76 }
local SLOTS = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 }

local function Create(ui)
    local host = CreateFrame("Frame", nil, ui.canvas)
    host:SetAllPoints()
    local model = CreateFrame("PlayerModel", nil, host)
    model:SetPoint("TOPLEFT", 222, -8)
    model:SetSize(276, 232)
    model:EnableMouse(false)
    local icons = {}
    for i = 1, #SLOTS do
        local icon = host:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", i <= 9 and 22 or 530, -58 - ((i - 1) % 9) * 19)
        icon:SetSize(17, 17)
        icon:SetTexCoord(.07, .93, .07, .93)
        icons[i] = icon
    end
    return { host = host, model = model, icons = icons }
end

-- An isolated menu model: no camera, UIParent fade, /afk, or feature activation.
V.Render.afkScreen = function(ui)
    local afk = ui.afk or Create(ui)
    ui.afk = afk
    afk.host:Show()
    afk.model:SetUnit("player")
    afk.model:SetPortraitZoom(0)
    afk.model:SetRotation(0)
    V.Fill(ui, 0, 0, 720, 240, { .004, .008, .014 }, .95)
    V.Fill(ui, 14, -47, 184, 1, GOLD, .72)
    V.Fill(ui, 526, -47, 180, 1, GOLD, .72)
    V.Label(ui, UnitName("player"), 18, -12, 195, 22, WHITE)
    V.Label(ui, Tr("AFK"), 532, -8, 170, 30, WHITE)
    V.Label(ui, Tr("AWAY FROM KEYBOARD"), 532, -35, 176, 9, GOLD)
    V.Label(ui, GetZoneText(), 235, -216, 258, 12, MUTED):SetJustifyH("CENTER")
    for i, slot in ipairs(SLOTS) do
        afk.icons[i]:SetTexture(GetInventoryItemTexture("player", slot))
        local label = V.Label(ui, "", i <= 9 and 44 or 552, -62 - ((i - 1) % 9) * 19, 155, 10, WHITE)
        local link = GetInventoryItemLink("player", slot)
        if not P.Suite.IsSecret(link) and type(link) == "string" then
            label:SetText(link:match("%[(.-)%]") or "")
        end
    end
    return 720, 240
end
