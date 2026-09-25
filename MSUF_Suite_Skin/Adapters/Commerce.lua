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

local Field = NS.Safety.Field
local Kit = NS.AdapterKit
local Fade = Kit.Fade
local SurfaceSpec = Kit.SurfaceSpec

local DEFAULT_OWNER = "blizzardWindows"
local AUCTION_ADDON = "Blizzard_AuctionHouseUI"
local MAIL_ROW_COUNT = 7
local MAIL_ATTACHMENT_COUNT = 16

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

local mailStationery = {
    "SendStationeryBackgroundLeft", "SendStationeryBackgroundRight",
    "OpenStationeryBackgroundLeft", "OpenStationeryBackgroundRight",
    "SendMailHorizontalBarLeft", "SendMailHorizontalBarLeft2",
    "OpenMailHorizontalBarLeft",
}

local CARD_SPEC = SurfaceSpec("card", 4, 0)
local PANEL_SPEC = SurfaceSpec("panel", 4, 0)
local POPUP_SPEC = SurfaceSpec("popup", 8, 0)
local ROW_SPEC = SurfaceSpec("card", 4, 1, true)
local CATEGORY_ROW_SPEC = SurfaceSpec("navigation", 4, 1, true)
local ATTACHMENT_SPEC = SurfaceSpec("input", 4, 1)

local MAIL_INPUT_SPEC = { role = "input", regions = { "Left", "Middle", "Right" } }
local SEARCH_SPEC = {}
local BUTTON_SPEC = {}
local TAB_SPEC = {}

local function Group(owner)
    local state = Commerce.groups[owner]
    if not state then
        state = {
            owner = owner,
            surfaces = Kit.WeakSet(),
        }
        Commerce.groups[owner] = state
    end
    state.active = true
    return state
end

local function SkinPanel(group, target, spec)
    if not target then return false end
    Fade(group, Field(target, "Background"))
    Fade(group, Field(target, "Bg"))
    Kit.FadeNineSlice(group, Field(target, "NineSlice"))
    return Kit.Attach(group, target, spec or CARD_SPEC)
end

local function FadeMatchingRegion(region, group, texture)
    if NS.Safety.Read(region, "GetTexture") == texture then
        Fade(group, region)
    end
end

-- Fades every direct region of frame drawn with the same texture as sample.
local function FadeMatchingTexture(group, frame, sample)
    local texture = NS.Safety.Read(sample, "GetTexture")
    if texture ~= nil then
        Kit.ForEachRegion(frame, FadeMatchingRegion, group, texture)
    end
end

local function SkinMailRow(group, row)
    if not row then return false end
    -- MailItemTemplate's direct textures are its two parchment borders and
    -- divider. The item/COD icon is a child CheckButton and is preserved.
    Kit.FadeTextures(group, row)
    return Kit.Attach(group, row, ROW_SPEC)
end

local function SkinMailAttachment(group, globalName)
    local button = _G[globalName]
    if not button then return end
    Fade(group, _G[globalName .. "Slot"])
    Kit.Attach(group, button, ATTACHMENT_SPEC)
end

local function SkinMail(owner)
    if NS.IsCombatLocked() or not _G.MailFrame then return false, "missing" end
    local group = Group(owner)
    Fade(group, _G.InboxFrameBg)
    for index = 1, MAIL_ROW_COUNT do
        SkinMailRow(group, _G["MailItem" .. index])
    end

    for index = 1, #mailStationery do
        Fade(group, _G[mailStationery[index]])
    end
    FadeMatchingTexture(group, _G.SendMailFrame, _G.SendMailHorizontalBarLeft)
    FadeMatchingTexture(group, _G.OpenMailFrame, _G.OpenMailHorizontalBarLeft)

    -- InboxFrame is a 384x512 implementation container which extends far
    -- beyond the visible inbox. Generic window skinning may have attached a
    -- surface to it; keep that surface hidden and skin the seven visible rows
    -- instead, otherwise the mailbox grows a large empty dark rectangle.
    if _G.InboxFrame then
        NS.Surface.SetVisible(_G.InboxFrame, false)
    end
    SkinPanel(group, _G.SendMailScrollFrame, PANEL_SPEC)
    SkinPanel(group, _G.OpenMailScrollFrame, PANEL_SPEC)
    Kit.SkinControl(group, _G.SendMailNameEditBox, MAIL_INPUT_SPEC, "ApplySearchBox")
    Kit.SkinControl(group, _G.SendMailSubjectEditBox, MAIL_INPUT_SPEC, "ApplySearchBox")
    Kit.SkinControl(group, _G.MailFrameTab1, TAB_SPEC, "ApplyTab")
    Kit.SkinControl(group, _G.MailFrameTab2, TAB_SPEC, "ApplyTab")

    for index = 1, MAIL_ATTACHMENT_COUNT do
        SkinMailAttachment(group, "SendMailAttachment" .. index)
        SkinMailAttachment(group, "OpenMailAttachmentButton" .. index)
    end
    return true
end

local function SkinAuctionRow(row, kind, owner)
    local group = Commerce.groups[owner]
    if not group or not group.active or NS.IsCombatLocked() or not row then
        return false
    end
    if kind == "category" then
        Fade(group, Field(row, "NormalTexture"))
        Fade(group, Field(row, "Lines"))
        -- SelectedTexture and HighlightTexture convey Blizzard selection.
        return Kit.Attach(group, row, CATEGORY_ROW_SPEC)
    end
    if kind == "item" then
        Fade(group, Field(row, "NormalTexture"))
    end
    -- Summary rows have no neutral background art; the surface supplies one
    -- while item icons and selection/highlight overlays remain intact.
    return Kit.Attach(group, row, ROW_SPEC)
end

-- Registered once per ScrollBox as callback(registration, row).
local function OnRowInitialized(registration, row)
    SkinAuctionRow(row, registration.kind, registration.owner)
end

local function RegisterScrollBox(scrollBox, kind, owner)
    if not scrollBox or Commerce.scrollBoxes[scrollBox] then
        return false
    end
    local registration = { owner = owner, kind = kind }
    registration.event = Kit.RegisterRowCallback(scrollBox, OnRowInitialized, registration)
    if not registration.event then return false end
    Commerce.scrollBoxes[scrollBox] = registration
    if not NS.IsCombatLocked() then
        Kit.ForEachRow(scrollBox, function(row) SkinAuctionRow(row, kind, owner) end)
    end
    return true
end

local function SkinAuction(owner)
    local frame = _G.AuctionHouseFrame
    if NS.IsCombatLocked() then return false, "combat" end
    if not frame then return false, "missing" end
    if not NS.Safety.CanDecorate(frame, true) then
        return false, "protected"
    end
    local group = Group(owner)
    for index = 1, #auctionPanelPaths do
        local spec = index == #auctionPanelPaths and POPUP_SPEC or CARD_SPEC
        SkinPanel(group, Kit.PathOf(frame, auctionPanelPaths[index]), spec)
    end

    local search = Field(frame, "SearchBar")
    Kit.SkinControl(group, Field(search, "SearchBox"), SEARCH_SPEC, "ApplySearchBox")
    Kit.SkinControl(group, Field(search, "SearchButton"), BUTTON_SPEC)
    Kit.SkinControl(group, Field(search, "FilterButton"), BUTTON_SPEC)
    Kit.SkinControl(group, Field(frame, "BuyTab"), TAB_SPEC, "ApplyTab")
    Kit.SkinControl(group, Field(frame, "SellTab"), TAB_SPEC, "ApplyTab")
    Kit.SkinControl(group, Field(frame, "AuctionsTab"), TAB_SPEC, "ApplyTab")
    local auctions = Field(frame, "AuctionsFrame")
    Kit.SkinControl(group, Field(auctions, "AuctionsTab"), TAB_SPEC, "ApplyTab")
    Kit.SkinControl(group, Field(auctions, "BidsTab"), TAB_SPEC, "ApplyTab")

    for index = 1, #auctionScrollPaths do
        local path = auctionScrollPaths[index]
        RegisterScrollBox(Kit.PathOf(frame, path), path.kind, owner)
    end
    return true
end

local function UnregisterOwner(owner)
    for scrollBox, registration in pairs(Commerce.scrollBoxes) do
        if registration.owner == owner then
            Kit.UnregisterRowCallback(scrollBox, registration.event, registration)
            Commerce.scrollBoxes[scrollBox] = nil
        end
    end
end

local function DisableGroup(owner)
    local group = Commerce.groups[owner]
    if not group then return true end
    group.active = false
    UnregisterOwner(owner)
    NS.ControlSkin.DisableOwner(owner)
    NS.Cosmetics.RestoreOwner(owner)
    Kit.HideSurfaces(group)
    Commerce.groups[owner] = nil
    return true
end

local function ScheduleAuction(parentOwner, auctionOwner)
    local state = Commerce.owners[parentOwner]
    if not state or state.auctionWaiting then
        return false
    end
    state.auctionWaiting = true
    local scheduled = Kit.ContinueOnAddOnLoaded(AUCTION_ADDON, function()
        local current = Commerce.owners[parentOwner]
        if not current then return end
        current.auctionWaiting = nil
        if current.active and not NS.IsCombatLocked()
            and NS.DB.skinCategories.economy ~= false then
            SkinAuction(auctionOwner)
        end
    end)
    if not scheduled then state.auctionWaiting = nil end
    return scheduled
end

function Commerce.Apply(parentOwner)
    parentOwner = parentOwner or DEFAULT_OWNER
    local state = Commerce.owners[parentOwner]
    if not state then
        state = {
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
