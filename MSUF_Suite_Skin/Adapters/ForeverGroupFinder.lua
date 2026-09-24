local _, NS = ...

-- Camelot loads Blizzard_GroupFinder_VanillaStyle on demand. Its LFGParentFrame
-- is a different window from Retail's PVEFrame. Keep Blizzard's role icons,
-- category IDs, result rows, scripts, and secure listing controls intact.
local ForeverGroupFinder = {
    active = false, hooked = false,
    scrollBoxes = setmetatable({}, { __mode = "k" }),
}
NS.ForeverGroupFinder = ForeverGroupFinder

local ADDON = "Blizzard_GroupFinder_VanillaStyle"
local OWNER = "blizzardWindows:forever-group-finder"
local ROOT_MODE = {
    role = "shell", maxDepth = 0, maxNodes = 1,
    childSurfaces = false, registerDynamicRows = false,
    allowImplicitProtected = true,
}
local PANEL_MODE = {
    role = "panel", maxDepth = 0, maxNodes = 1,
    fillVisible = false, childSurfaces = false, registerDynamicRows = false,
    allowImplicitProtected = true,
}
local CARD_SPEC = {
    role = "card", activeRole = "navigationActive", radius = 5,
    inset = 0, listItem = true, allowImplicitProtected = true,
    regions = { "Icon", "Cover", "SelectedTexture", "HighlightTexture" },
}
local TAB_SPEC = {
    role = "navigation", activeRole = "navigationActive", radius = 4,
    inset = 0, allowImplicitProtected = true,
}
local RESULT_SPEC = {
    role = "card", activeRole = "navigationActive", radius = 4,
    inset = 0, listItem = true, allowImplicitProtected = true,
    regions = { "ResultBG", "Selected", "Highlight" },
}
local WHO_SPEC = {
    role = "card", activeRole = "navigationActive", radius = 4,
    inset = 0, listItem = true, allowImplicitProtected = true,
    regions = { "Background", "Selected" },
}

local function Ready()
    return ForeverGroupFinder.active and NS.Client and NS.Client.isForever
        and NS.GenericWindows and NS.ControlSkin and NS.Cosmetics
        and not NS.IsCombatLocked()
end

local function Fade(region)
    if region and NS.Safety.CanDecorate(region, true) then
        NS.Cosmetics.Fade(region, OWNER)
    end
end

local function FadeInset(inset)
    if not inset then return end
    Fade(inset.CustomBG)
    Fade(inset.Bg)
    NS.Cosmetics.FadeNineSlice(inset.NineSlice, OWNER)
end

local function SkinCategoryCards()
    if not Ready() then return end
    local listing = _G.LFGListingFrame
    local view = listing and listing.CategoryView
    local buttons = view and view.CategoryButtons
    if not buttons then return end
    for index = 1, #buttons do
        local button = buttons[index]
        if button and button.Icon and button.Cover and button.Label
            and NS.Safety.CanCreateRegions(button, true) then
            NS.ControlSkin.ApplyButton(button, OWNER, CARD_SPEC)
        end
    end
end

local function SkinResultRow(row, kind)
    if not Ready() or not row or not NS.Safety.CanCreateRegions(row, true) then return end
    if kind == "browse" and row.ResultBG and row.Name then
        NS.ControlSkin.ApplyButton(row, OWNER, RESULT_SPEC)
    elseif kind == "who" and row.Background and row.Name then
        NS.ControlSkin.ApplyButton(row, OWNER, WHO_SPEC)
    end
end

local function RegisterRows(scrollBox, kind)
    local event = ScrollBoxListMixin and ScrollBoxListMixin.Event
        and ScrollBoxListMixin.Event.OnInitializedFrame
    if not scrollBox or not event or ForeverGroupFinder.scrollBoxes[scrollBox]
        or type(scrollBox.RegisterCallback) ~= "function"
        or type(scrollBox.ForEachFrame) ~= "function" then
        return
    end
    local token = { kind = kind }
    scrollBox:RegisterCallback(event, function(_, row)
        SkinResultRow(row, kind)
    end, token)
    ForeverGroupFinder.scrollBoxes[scrollBox] = token
    scrollBox:ForEachFrame(function(row) SkinResultRow(row, kind) end)
end

local function SkinFrame(frame, mode)
    if frame and NS.Safety.CanCreateRegions(frame, true) then
        NS.GenericWindows.ApplyFrame(frame, OWNER, mode)
    end
end

local function SkinLoadedWindow()
    if not Ready() then return false, "combat" end
    local parent = _G.LFGParentFrame
    local listing = _G.LFGListingFrame
    local browse = _G.LFGBrowseFrame
    if not parent or not listing or not browse then return false, "missing" end

    SkinFrame(parent, ROOT_MODE)
    SkinFrame(listing, PANEL_MODE)
    SkinFrame(browse, PANEL_MODE)
    SkinFrame(_G.LFGWhoListFrame, PANEL_MODE)

    Fade(listing.RolesSection and listing.RolesSection.RoleBackground)
    FadeInset(listing.Inset)
    Fade(browse.BackgroundArt)
    FadeInset(browse.Inset)
    local who = _G.LFGWhoListFrame
    if who then
        Fade(who.headerBackground)
        Fade(who.insideFrame)
    end

    for _, key in ipairs({ "Tab1", "Tab2", "Tab3" }) do
        local tab = parent[key]
        if tab and NS.Safety.CanCreateRegions(tab, true) then
            NS.ControlSkin.ApplyTab(tab, OWNER, TAB_SPEC)
        end
    end
    for _, key in ipairs({ "ListingTab", "BrowsingTab", "WhoListingTab" }) do
        local tab = parent[key]
        if tab and NS.Safety.CanCreateRegions(tab, true) then
            NS.ControlSkin.ApplyButton(tab, OWNER, TAB_SPEC)
        end
    end
    SkinCategoryCards()
    RegisterRows(browse.ScrollBox, "browse")
    RegisterRows(who and who.ScrollBox, "who")

    if not ForeverGroupFinder.hooked
        and type(_G.LFGListingCategorySelection_UpdateCategoryButtons) == "function"
        and type(hooksecurefunc) == "function" then
        hooksecurefunc("LFGListingCategorySelection_UpdateCategoryButtons", SkinCategoryCards)
        ForeverGroupFinder.hooked = true
    end
    return true, "applied"
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, addon)
    if event ~= "ADDON_LOADED" or addon ~= ADDON then return end
    eventFrame:UnregisterEvent("ADDON_LOADED")
    if not ForeverGroupFinder.active then return end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(OWNER .. ":load", SkinLoadedWindow)
    else
        SkinLoadedWindow()
    end
end)

function ForeverGroupFinder.Apply()
    if not NS.Client or not NS.Client.isForever then return true, "disabled" end
    if not NS.GenericWindows.IsCategoryEnabled("group") then
        ForeverGroupFinder.Disable()
        return true, "disabled"
    end
    ForeverGroupFinder.active = true
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(OWNER .. ":apply", SkinLoadedWindow)
        return true, "waiting"
    end
    if _G.LFGParentFrame then return SkinLoadedWindow() end
    if NS.Client.HasAddOn(ADDON) == false then return true, "unavailable" end
    eventFrame:RegisterEvent("ADDON_LOADED")
    return true, "waiting"
end

function ForeverGroupFinder.Disable()
    ForeverGroupFinder.active = false
    eventFrame:UnregisterEvent("ADDON_LOADED")
    NS.CombatGate.Cancel(OWNER .. ":load")
    NS.CombatGate.Cancel(OWNER .. ":apply")
    local event = ScrollBoxListMixin and ScrollBoxListMixin.Event
        and ScrollBoxListMixin.Event.OnInitializedFrame
    if event then
        for scrollBox, token in pairs(ForeverGroupFinder.scrollBoxes) do
            if type(scrollBox.UnregisterCallback) == "function" then
                scrollBox:UnregisterCallback(event, token)
            end
            ForeverGroupFinder.scrollBoxes[scrollBox] = nil
        end
    end
    return NS.GenericWindows.Disable(OWNER)
end

return ForeverGroupFinder
