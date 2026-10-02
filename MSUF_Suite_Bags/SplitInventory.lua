local _, P = ...
local NS, S = P.NS, P.Suite
local SplitInventory = {}
P.SplitInventory = SplitInventory

function SplitInventory.Source(owner)
    if S.Finite(owner.bankTabID) and S.Finite(owner.containerSlotID) then
        return { kind = "bank", bag = owner.bankTabID, slot = owner.containerSlotID, bankType = owner.bankType }
    end
    if type(owner.GetBagID) == "function" then
        local bag, slot = owner:GetBagID(), owner:GetID()
        if S.Finite(bag) and S.Finite(slot) then return { kind = "bag", bag = bag, slot = slot } end
    end
    local frame = owner
    for _ = 1, 6 do
        if not frame then break end
        if frame == _G.GuildBankFrame then
            return { kind = "guild", bag = GetCurrentGuildBankTab(), slot = owner:GetID() }
        end
        frame = frame:GetParent()
    end
end

function SplitInventory.Read(source, slot)
    slot = slot or source.slot
    if source.kind == "guild" then
        local link = GetGuildBankItemLink(source.bag, slot)
        local texture, count, locked = GetGuildBankItemInfo(source.bag, slot)
        if not S.Public(link) or not S.Public(texture) or not S.Public(count) or not S.Public(locked) then return nil, nil, true end
        if link == nil and texture == nil and (count == nil or count == 0) and not locked then return nil, 0, false end
        if not S.Finite(count) then return nil, nil, true end
        return link, count, locked
    end
    local info = C_Container.GetContainerItemInfo(source.bag, slot)
    if not S.Public(info) then return nil, nil, true end
    if not info then return nil, 0, false end
    if not S.Public(info.hyperlink) or not S.Finite(info.stackCount) or not S.Public(info.isLocked) then
        return nil, nil, true
    end
    return info.hyperlink, info.stackCount, info.isLocked
end

local function AddSlots(destinations, source, bag, family)
    local free, accepts = C_Container.GetContainerNumFreeSlots(bag)
    if not S.Finite(free) or free <= 0 or not S.Finite(accepts) then return end
    if accepts ~= 0 and (not S.Finite(family) or bit.band(family, accepts) == 0) then return end
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if S.Public(info) and info == nil then
            destinations[#destinations + 1] = { kind = source.kind, bag = bag, slot = slot }
        end
    end
end

function SplitInventory.Destinations(source, link)
    local destinations = {}
    if source.kind == "guild" then
        -- Blizzard_GuildBankUI's native tab has seven columns of fourteen slots.
        for slot = 1, 98 do
            local value, count, locked = SplitInventory.Read(source, slot)
            if value == nil and count == 0 and not locked then
                destinations[#destinations + 1] = { kind = "guild", bag = source.bag, slot = slot }
            end
        end
    else
        local family = C_Item.GetItemFamily(link)
        if source.kind == "bag" and source.bag >= 0 and source.bag <= NUM_TOTAL_EQUIPPED_BAG_SLOTS then
            -- The reagent bag takes crafting reagents only, whatever family it
            -- reports; GetItemInfo's 17th result is isCraftingReagent.
            local reagent = select(17, C_Item.GetItemInfo(link)) == true
            for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
                if bag ~= Enum.BagIndex.ReagentBag or reagent then AddSlots(destinations, source, bag, family) end
            end
        elseif source.kind == "bank" and not NS.Client.isForever then
            local tabs = C_Bank.FetchPurchasedBankTabData(source.bankType)
            for i = 1, #tabs do AddSlots(destinations, source, tabs[i].ID, family) end
        else
            AddSlots(destinations, source, source.bag, family)
        end
    end
    return destinations
end

function SplitInventory.Available(source)
    if source.kind == "guild" then
        return _G.GuildBankFrame and GuildBankFrame:IsShown() and GetCurrentGuildBankTab() == source.bag
    end
    if source.kind == "bank" then
        return BankFrame:IsShown() and C_Bank.CanUseBank(source.bankType)
    end
    return true
end

function SplitInventory.Split(source, amount)
    if source.kind == "guild" then
        SplitGuildBankItem(source.bag, source.slot, amount)
    else
        C_Container.SplitContainerItem(source.bag, source.slot, amount)
    end
end

function SplitInventory.Place(destination)
    if destination.kind == "guild" then
        PickupGuildBankItem(destination.bag, destination.slot)
    else
        C_Container.PickupContainerItem(destination.bag, destination.slot)
    end
end
