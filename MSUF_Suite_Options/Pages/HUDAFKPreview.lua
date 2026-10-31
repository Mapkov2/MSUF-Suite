local _, P = ...
local Suite, V, Tr = P.Suite, P.HUDPreview, P.Tr
local GOLD, WHITE, MUTED = { .88, .69, .42 }, { .96, .95, .91 }, { .67, .72, .76 }
local ICON_SIZE = 17
-- The rows the canvas fits at the usual spacing; the tenth row of WoW
-- Forever's character sheet (ranged weapon, ammunition) tightens it.
local ROWS_AT_FULL_SPACING, FULL_SPACING, TIGHT_SPACING = 9, 19, 17

local function Create(ui)
    local host = CreateFrame("Frame", nil, ui.canvas)
    host:SetAllPoints()
    local model = CreateFrame("PlayerModel", nil, host)
    model:SetPoint("TOPLEFT", 222, -8)
    model:SetSize(276, 232)
    model:EnableMouse(false)
    return { host = host, model = model, icons = {} }
end

-- Column (1 left, 2 right) and row of a slot as on the AFK screen: nine rows
-- on the left, then the right column; the ammunition slot is the tenth row of
-- the left one.
local function Cell(index)
    if index == Suite.AFK_AMMO_ROW then return 1, ROWS_AT_FULL_SPACING + 1 end
    if index <= ROWS_AT_FULL_SPACING then return 1, index end
    return 2, index - ROWS_AT_FULL_SPACING
end

local function SlotIcon(afk, index)
    local icon = afk.icons[index]
    if not icon then
        icon = afk.host:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetTexCoord(.07, .93, .07, .93)
        afk.icons[index] = icon
    end
    return icon
end

-- One slot of the client's list: its icon and item name. WoW Forever lists
-- the ammunition slot only while the ranged weapon uses ammunition
-- (UnitUsesAmmo, which only Forever has).
local function PaintSlot(ui, afk, index, spacing)
    if index == Suite.AFK_AMMO_ROW and UnitUsesAmmo("player") ~= true then return end
    local slot = Suite.AFKSlots[index]
    local column, row = Cell(index)
    local icon = SlotIcon(afk, index)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", column == 1 and 22 or 530, -58 - (row - 1) * spacing)
    icon:SetTexture(GetInventoryItemTexture("player", slot))
    icon:Show()
    local label = V.Label(ui, "", column == 1 and 44 or 552, -62 - (row - 1) * spacing, 155, 10, WHITE)
    local link = GetInventoryItemLink("player", slot)
    if not Suite.IsSecret(link) and type(link) == "string" then
        label:SetText(link:match("%[(.-)%]") or "")
    end
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
    -- The slots the client's character sheet lists, as the screen does.
    local count = Suite.AFKSlotCount()
    local spacing = count >= Suite.AFK_RANGED_ROW and TIGHT_SPACING or FULL_SPACING
    for _, icon in ipairs(afk.icons) do icon:Hide() end
    for index = 1, count do PaintSlot(ui, afk, index, spacing) end
    return 720, 240
end
