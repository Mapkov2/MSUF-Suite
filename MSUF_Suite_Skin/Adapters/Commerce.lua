local _, NS = ...

-- Deep clean-room skins for Blizzard Mail and Auction House. Exact fields and
-- ScrollBox paths are verified against Gethe/wow-ui-source upstream/live at
-- 710f59e457317676c0f699e6addaf2c405c2a1a4. Blizzard scripts, anchors,
-- attributes, semantic icons/highlights and data providers stay untouched.
local Commerce = {
    owners = {},
    groups = {},
    scrollBoxes = setmetatable({}, { __mode = "k" }),
}
NS.Commerce = Commerce

local DEFAULT_OWNER = "blizzardWindows"
local AUCTION_ADDON = "Blizzard_AuctionHouseUI"

local auctionPanelPaths = {
    { "CategoriesList" },
    { "BrowseResultsFrame", "ItemList" },
    { "WoWTokenResults" },
    { "CommoditiesBuyFrame", "BuyDisplay" },
    { "CommoditiesBuyFrame", "ItemList" },
    { "ItemBuyFrame", "ItemDisplay" },
    { "ItemBuyFrame", "ItemList" },
    { "ItemSellFrame" },
    { "ItemSellList" },
    { "CommoditiesSellFrame" },
    { "CommoditiesSellList" },
    { "WoWTokenSellFrame" },
    { "AuctionsFrame", "SummaryList" },
    { "AuctionsFrame", "ItemDisplay" },
    { "AuctionsFrame", "AllAuctionsList" },
    { "AuctionsFrame", "BidsList" },
    { "AuctionsFrame", "ItemList" },
    { "AuctionsFrame", "CommoditiesList" },
    { "BuyDialog" },
}

local auctionScrollPaths = {
    { "CategoriesList", "ScrollBox", kind = "category" },
    { "BrowseResultsFrame", "ItemList", "ScrollBox", kind = "item" },
    { "CommoditiesBuyFrame", "ItemList", "ScrollBox", kind = "item" },
    { "ItemBuyFrame", "ItemList", "ScrollBox", kind = "item" },
    { "ItemSellList", "ScrollBox", kind = "item" },
    { "CommoditiesSellList", "ScrollBox", kind = "item" },
    { "AuctionsFrame", "SummaryList", "ScrollBox", kind = "summary" },
    { "AuctionsFrame", "AllAuctionsList", "ScrollBox", kind = "item" },
    { "AuctionsFrame", "BidsList", "ScrollBox", kind = "item" },
    { "AuctionsFrame", "ItemList", "ScrollBox", kind = "item" },
    { "AuctionsFrame", "CommoditiesList", "ScrollBox", kind = "item" },
}

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function Resolve(root, path)
    local object = root
    for index = 1, #(path or {}) do
        object = SafeField(object, path[index])
        if not object then return nil end
    end
    return object
end

local function Group(owner)
    local state = Commerce.groups[owner]
    if not state then
        state = {
            active = true,
            surfaces = setmetatable({}, { __mode = "k" }),
        }
        Commerce.groups[owner] = state
    else
        state.active = true
    end
    return state
end

local function Track(owner, target)
    local state = Group(owner)
    state.surfaces[target] = true
end

local function Fade(region, owner)
    if not region or NS.IsCombatLocked() or not NS.Cosmetics
        or type(NS.Cosmetics.Fade) ~= "function" or not NS.Safety
        or not NS.Safety.CanDecorate(region, true) then
        return false
    end
    local ok, result = pcall(NS.Cosmetics.Fade, region, owner)
    return ok and result == true
end

local function FadeNineSlice(target, owner)
    local nineSlice = SafeField(target, "NineSlice")
    if nineSlice and not NS.IsCombatLocked() and NS.Safety
        and NS.Safety.CanDecorate(nineSlice, true) and NS.Cosmetics
        and type(NS.Cosmetics.FadeNineSlice) == "function" then
        pcall(NS.Cosmetics.FadeNineSlice, nineSlice, owner)
    end
end

local function Attach(target, owner, role, inset, listItem)
    if not target or NS.IsCombatLocked() or not NS.Safety
        or not NS.Safety.CanDecorate(target, true) then
        return false
    end
    local ok, surface = pcall(NS.Surface.Attach, target, {
        role = role or "card",
        radius = role == "popup" and 8 or 4,
        inset = inset or 0,
        listItem = listItem == true,
        allowImplicitProtected = true,
    })
    if ok and surface then
        Track(owner, target)
        return true
    end
    return false
end

local function SkinPanel(target, owner, role)
    if not target then return false end
    Fade(SafeField(target, "Background"), owner)
    Fade(SafeField(target, "Bg"), owner)
    FadeNineSlice(target, owner)
    return Attach(target, owner, role or "card")
end

local function SkinControl(target, owner, kind, spec)
    if not target or NS.IsCombatLocked() or not NS.ControlSkin then
        return false
    end
    spec = spec or {}
    spec.allowImplicitProtected = true
    local method = kind == "tab" and NS.ControlSkin.ApplyTab
        or kind == "search" and NS.ControlSkin.ApplySearchBox
        or NS.ControlSkin.ApplyButton
    if type(method) ~= "function" then return false end
    local ok, state = pcall(method, target, owner, spec)
    if ok and state then
        Track(owner, target)
        return true
    end
    return false
end

local function RegionList(frame)
    if not frame or type(frame.GetRegions) ~= "function" then return {} end
    local ok, regions = pcall(function() return { frame:GetRegions() } end)
    return ok and regions or {}
end

local function FadeMatchingTexture(frame, sample, owner)
    if not sample or type(sample.GetTexture) ~= "function" then return end
    local ok, texture = pcall(sample.GetTexture, sample)
    if not ok or texture == nil then return end
    local regions = RegionList(frame)
    for index = 1, #regions do
        local region = regions[index]
        if region and type(region.GetTexture) == "function" then
            local read, candidate = pcall(region.GetTexture, region)
            if read and candidate == texture then Fade(region, owner) end
        end
    end
end

local function SkinMailRow(row, owner)
    if not row then return false end
    local regions = RegionList(row)
    for index = 1, #regions do
        local region = regions[index]
        local kind
        if region and type(region.GetObjectType) == "function" then
            local ok, value = pcall(region.GetObjectType, region)
            kind = ok and value or nil
        end
        -- MailItemTemplate's direct textures are its two parchment borders and
        -- divider. The item/COD icon is a child CheckButton and is preserved.
        if kind == "Texture" then Fade(region, owner) end
    end
    return Attach(row, owner, "card", 1, true)
end

local function SkinMailAttachment(button, owner, globalName)
    if not button then return end
    Fade(_G[globalName .. "Slot"], owner)
    Attach(button, owner, "input", 1)
end

local function SkinMail(owner)
    if NS.IsCombatLocked() or not _G.MailFrame then return false, "missing" end
    Group(owner)
    Fade(_G.InboxFrameBg, owner)
    for index = 1, 7 do
        SkinMailRow(_G["MailItem" .. index], owner)
    end

    for _, name in ipairs({
        "SendStationeryBackgroundLeft", "SendStationeryBackgroundRight",
        "OpenStationeryBackgroundLeft", "OpenStationeryBackgroundRight",
        "SendMailHorizontalBarLeft", "SendMailHorizontalBarLeft2",
        "OpenMailHorizontalBarLeft",
    }) do
        Fade(_G[name], owner)
    end
    FadeMatchingTexture(_G.SendMailFrame, _G.SendMailHorizontalBarLeft, owner)
    FadeMatchingTexture(_G.OpenMailFrame, _G.OpenMailHorizontalBarLeft, owner)

    -- InboxFrame is a 384x512 implementation container which extends far
    -- beyond the visible inbox. Generic window skinning may have attached a
    -- surface to it; keep that surface hidden and skin the seven visible rows
    -- instead, otherwise the mailbox grows a large empty dark rectangle.
    if _G.InboxFrame and NS.Surface then
        NS.Surface.SetVisible(_G.InboxFrame, false)
    end
    SkinPanel(_G.SendMailScrollFrame, owner, "panel")
    SkinPanel(_G.OpenMailScrollFrame, owner, "panel")
    SkinControl(_G.SendMailNameEditBox, owner, "search", {
        role = "input", regions = { "Left", "Middle", "Right" },
    })
    SkinControl(_G.SendMailSubjectEditBox, owner, "search", {
        role = "input", regions = { "Left", "Middle", "Right" },
    })
    SkinControl(_G.MailFrameTab1, owner, "tab")
    SkinControl(_G.MailFrameTab2, owner, "tab")

    for index = 1, 16 do
        local sendName = "SendMailAttachment" .. index
        local openName = "OpenMailAttachmentButton" .. index
        SkinMailAttachment(_G[sendName], owner, sendName)
        SkinMailAttachment(_G[openName], owner, openName)
    end
    return true
end

local function SkinAuctionRow(row, kind, owner)
    local state = Commerce.groups[owner]
    if not state or not state.active or NS.IsCombatLocked() or not row then
        return false
    end
    if kind == "category" then
        Fade(SafeField(row, "NormalTexture"), owner)
        Fade(SafeField(row, "Lines"), owner)
        -- SelectedTexture and HighlightTexture convey Blizzard selection.
        return Attach(row, owner, "navigation", 1, true)
    end
    if kind == "item" then
        Fade(SafeField(row, "NormalTexture"), owner)
    end
    -- Summary rows have no neutral background art; the surface supplies one
    -- while item icons and selection/highlight overlays remain intact.
    return Attach(row, owner, "card", 1, true)
end

local function ScrollEvent()
    return ScrollBoxListMixin and ScrollBoxListMixin.Event
        and ScrollBoxListMixin.Event.OnInitializedFrame
end

local function RegisterScrollBox(scrollBox, kind, owner)
    local event = ScrollEvent()
    if not scrollBox or not event or Commerce.scrollBoxes[scrollBox]
        or type(SafeField(scrollBox, "RegisterCallback")) ~= "function" then
        return false
    end
    local token = {}
    local function Initialized(_, row)
        SkinAuctionRow(row, kind, owner)
    end
    local ok = pcall(scrollBox.RegisterCallback, scrollBox, event, Initialized, token)
    if not ok then return false end
    Commerce.scrollBoxes[scrollBox] = { token = token, owner = owner, kind = kind }
    if type(SafeField(scrollBox, "ForEachFrame")) == "function" and not NS.IsCombatLocked() then
        pcall(scrollBox.ForEachFrame, scrollBox, function(row)
            SkinAuctionRow(row, kind, owner)
        end)
    end
    return true
end

local function SkinAuction(owner)
    local frame = _G.AuctionHouseFrame
    if NS.IsCombatLocked() then return false, "combat" end
    if not frame then return false, "missing" end
    if not NS.Safety or not NS.Safety.CanDecorate(frame, true) then
        return false, "protected"
    end
    Group(owner)
    for index = 1, #auctionPanelPaths do
        local role = index == #auctionPanelPaths and "popup" or "card"
        SkinPanel(Resolve(frame, auctionPanelPaths[index]), owner, role)
    end

    local search = SafeField(frame, "SearchBar")
    SkinControl(search and search.SearchBox, owner, "search")
    SkinControl(search and search.SearchButton, owner, "button")
    SkinControl(search and search.FilterButton, owner, "button")
    SkinControl(frame.BuyTab, owner, "tab")
    SkinControl(frame.SellTab, owner, "tab")
    SkinControl(frame.AuctionsTab, owner, "tab")
    local auctions = frame.AuctionsFrame
    SkinControl(auctions and auctions.AuctionsTab, owner, "tab")
    SkinControl(auctions and auctions.BidsTab, owner, "tab")

    for index = 1, #auctionScrollPaths do
        local path = auctionScrollPaths[index]
        RegisterScrollBox(Resolve(frame, path), path.kind, owner)
    end
    return true
end

local function UnregisterOwner(owner)
    local event = ScrollEvent()
    for scrollBox, registration in pairs(Commerce.scrollBoxes) do
        if registration.owner == owner then
            local unregister = SafeField(scrollBox, "UnregisterCallback")
            if event and type(unregister) == "function" then
                pcall(unregister, scrollBox, event, registration.token)
            end
            Commerce.scrollBoxes[scrollBox] = nil
        end
    end
end

local function DisableGroup(owner)
    local state = Commerce.groups[owner]
    if not state then return true end
    state.active = false
    UnregisterOwner(owner)
    if NS.ControlSkin then NS.ControlSkin.DisableOwner(owner) end
    if NS.Cosmetics then NS.Cosmetics.RestoreOwner(owner) end
    for target in pairs(state.surfaces) do
        pcall(NS.Surface.SetVisible, target, false)
    end
    Commerce.groups[owner] = nil
    return true
end

local function ScheduleAuction(parentOwner, auctionOwner)
    local state = Commerce.owners[parentOwner]
    if not state or state.auctionWaiting or not EventUtil
        or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then
        return false
    end
    state.auctionWaiting = true
    local ok = pcall(EventUtil.ContinueOnAddOnLoaded, AUCTION_ADDON, function()
        local current = Commerce.owners[parentOwner]
        if not current then return end
        current.auctionWaiting = nil
        if current.active and not NS.IsCombatLocked()
            and NS.DB.skinCategories.economy ~= false then
            SkinAuction(auctionOwner)
        end
    end)
    if not ok then state.auctionWaiting = nil end
    return ok
end

function Commerce.Apply(parentOwner)
    parentOwner = parentOwner or DEFAULT_OWNER
    local state = Commerce.owners[parentOwner]
    if not state then
        state = {
            active = true,
            mailOwner = parentOwner .. ":commerce:mail",
            auctionOwner = parentOwner .. ":commerce:auction",
        }
        Commerce.owners[parentOwner] = state
    end
    state.active = true
    local applied = false
    if NS.DB.skinCategories.social ~= false then
        applied = SkinMail(state.mailOwner) == true or applied
    else
        DisableGroup(state.mailOwner)
    end
    if NS.DB.skinCategories.economy ~= false then
        if _G.AuctionHouseFrame then
            applied = SkinAuction(state.auctionOwner) == true or applied
        else
            ScheduleAuction(parentOwner, state.auctionOwner)
        end
    else
        DisableGroup(state.auctionOwner)
    end
    return applied or state.auctionWaiting == true, applied and "applied" or "waiting"
end

function Commerce.Disable(parentOwner)
    parentOwner = parentOwner or DEFAULT_OWNER
    local state = Commerce.owners[parentOwner]
    if not state then return true end
    state.active = false
    DisableGroup(state.mailOwner)
    DisableGroup(state.auctionOwner)
    Commerce.owners[parentOwner] = nil
    return true
end

function Commerce.GetStatus(parentOwner)
    local state = Commerce.owners[parentOwner or DEFAULT_OWNER]
    return {
        active = state and state.active == true or false,
        mail = state and Commerce.groups[state.mailOwner] ~= nil or false,
        auction = state and Commerce.groups[state.auctionOwner] ~= nil or false,
        auctionWaiting = state and state.auctionWaiting == true or false,
    }
end

return Commerce
