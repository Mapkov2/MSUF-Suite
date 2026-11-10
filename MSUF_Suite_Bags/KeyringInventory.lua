local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client or not NS.Client.isForever or not S.Finite(KEYRING_CONTAINER) then return end

local Index, Slots = P.InventoryIndex, P.SlotCache
local BAG = KEYRING_CONTAINER
local Keyring = {}
P.KeyringInventory = Keyring
local buttons, versions, shownSlots = {}, {}, 0

local function Enabled()
    local shouldShow = C_ActionBar.ShouldShowKeyring
    if not shouldShow then return false end
    local enabled = shouldShow()
    return S.Public(enabled) and enabled == true and GetCVarBool("showKeyring") and not S.GamepadUI()
end

-- Blizzard's template keeps the physical bag/slot identity, clicks, drag and
-- tooltip. These buttons belong to the Suite, outside Blizzard's item list.
local function Button(frame, slot)
    local button = buttons[slot]
    if not button then
        button = P.ChildFrame("ItemButton", frame, "ContainerFrameItemButtonTemplate")
        button:Initialize(frame, BAG, slot)
        button:Hide()
        buttons[slot] = button
    end
    return button
end

local function Paint(button, item, info)
    local icon = info and info.iconFileID
    icon = S.Public(icon) and icon or nil
    button:SetHasItem(icon)
    if icon then button:SetItemButtonTexture(icon) end
    button:SyncAppearanceWithHasItem()
    SetItemButtonQuality(button, item.quality, item.link, false, item.bound)
    button:SetReadable(info and S.Public(info.isReadable) and info.isReadable == true)
    button:UpdateCooldown(icon)
end

local function Trim(size)
    for slot = size + 1, shownSlots do buttons[slot]:Hide() end
    shownSlots = size
end

function Keyring.Hide()
    if shownSlots > 0 and not NS.IsCombatLocked() then Trim(0) end
end

function Keyring.OwnsBag(bag)
    return shownSlots > 0 and S.Finite(bag) and bag == BAG
end

function Keyring.Append(index, frame, allowed)
    -- Gamepad and any future native combined layout already supply their own
    -- buttons. A mouse keyring never changes the carried-bag free-slot total.
    if not allowed or index.hasKeyring or not Enabled() then
        Keyring.Hide()
        return
    end
    local size = Slots.Sync(BAG)
    for slot = 1, size do
        local button = Button(frame, slot)
        local info, quest, version = Slots.Get(BAG, slot)
        local item = Index.ReadButton(index, button, info, quest, version, BAG, slot)
        item.keyring, item.bagName, item.mergeKey = true, KEYRING, item.key
        if versions[slot] ~= version then
            versions[slot] = version
            Paint(button, item, info)
        end
    end
    Trim(size)
    index.hasKeyring = size > 0
end
