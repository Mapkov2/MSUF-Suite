local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client.isForever then return end

-- The leader's current area sits inside each native browse row, right-aligned
-- on the playstyle line. As a region of the row it scrolls, clips and pools
-- with it; nothing floats beside the Group Finder. Forever 1.60.1 returns no
-- name or area for non-leader members (GetSearchResultPlayerInfo index > 1),
-- so group rows mark the area with the native leader crown.
local Locations = { labels = {} }
local ADDON = "Blizzard_GroupFinder_VanillaStyle"
local VIEW_EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}
-- Forever 9dc84f0 Mainline rows: DataDisplay (200x32) is centred on the right
-- edge and PlaystyleLabel sits bottom-left, so the bottom-right corner is free.
local RIGHT_INSET, BOTTOM_INSET, MAX_WIDTH = 10, 8, 180
local LEADER_PREFIX = "|A:groupfinder-icon-leader:14:14|a "

local function HideRow(row)
    local record = Locations.labels[row]
    if not record or not record.shown then return end
    record.label:Hide()
    record.shown = false
end

local function LabelFor(row)
    local record = Locations.labels[row]
    if record then return record end
    local label = S.CreateFontString(row, nil, "OVERLAY")
    S.SetFont(label, nil, 12, "")
    label:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -RIGHT_INSET, BOTTOM_INSET)
    label:SetWidth(MAX_WIDTH)
    label:SetJustifyH("RIGHT")
    label:SetWordWrap(false)
    label:SetMaxLines(1)
    record = { label = label, shown = true }
    Locations.labels[row] = record
    return record
end

-- Forever 9dc84f0: the native browse row calls these same LFG readers and
-- refreshes on LFG_LIST_SEARCH_RESULT_UPDATED. No additional search or poll.
local function PaintRow(row)
    if not Locations.visible or not Locations.eligible or not row:IsShown() then return HideRow(row) end
    local id, delisted, own = row.resultID, row.isDelisted, row.hasSelf
    if not S.Finite(id) or id <= 0 or not S.Public(delisted) or delisted then return HideRow(row) end
    -- Your own listing uses the short row, where the corner meets DataDisplay.
    if not S.Public(own) or own then return HideRow(row) end
    local info = C_LFGList.GetSearchResultLeaderInfo(id)
    local area = S.PublicText(S.PublicField(info, "areaName"))
    if not area then return HideRow(row) end
    -- The native row shows PartyIcon (the same crown atlas) only for groups.
    local party = row.PartyIcon
    local group = party and party:IsShown() or false
    local record = LabelFor(row)
    if record.text ~= area or record.group ~= group then
        record.label:SetText(group and LEADER_PREFIX .. area or area)
        record.text, record.group = area, group
    end
    if not record.shown then
        record.label:Show()
        record.shown = true
    end
end

local function NativeRowUpdated(row)
    if not Locations.active or not Locations.visible or not Locations.eligible then return end
    S.Dispatch(NS.Finish, PaintRow, row)
end

local function HideAll()
    for row in pairs(Locations.labels) do HideRow(row) end
end

local function StopWatching()
    if not Locations.watching then return end
    Locations.watching = false
    for _, event in ipairs(VIEW_EVENTS) do Locations.context:RemoveEvent(event) end
end

local function Sync(_, event)
    Locations.visible = Locations.active and Locations.browse and Locations.browse:IsVisible() or false
    if Locations.visible and not Locations.watching then
        Locations.watching = true
        for _, name in ipairs(VIEW_EVENTS) do Locations.context:Event(name, Sync) end
    elseif not Locations.visible then
        StopWatching()
    end
    Locations.eligible = Locations.visible and event ~= "PLAYER_LEAVING_WORLD"
        and not NS.InCombat(event) and S.InstanceKind() == "world"
    if not Locations.eligible then return HideAll() end
    local scroll = Locations.browse.ScrollBox
    if scroll:GetView() then scroll:ForEachFrame(PaintRow) end
end

local function BrowseChanged()
    if Locations.active then S.Dispatch(NS.Finish, Sync) end
end

local function Attach()
    if Locations.browse then return true end
    local browse = _G.LFGBrowseFrame
    if not browse or not browse.ScrollBox or type(_G.LFGBrowseSearchEntry_Update) ~= "function" then return false end
    Locations.browse = browse
    browse:HookScript("OnShow", BrowseChanged)
    browse:HookScript("OnHide", BrowseChanged)
    hooksecurefunc("LFGBrowseSearchEntry_Update", NativeRowUpdated)
    Locations.context:RemoveEvent("ADDON_LOADED")
    return true
end

local function AddonLoaded(_, _, name)
    if name == ADDON and Attach() then Sync() end
end

function Locations:Enable()
    if Attach() then
        Sync()
    else
        self.context:Event("ADDON_LOADED", AddonLoaded)
    end
end

function Locations:Refresh()
    if Attach() then Sync() end
end

function Locations:Disable()
    self.visible, self.eligible = false, false
    StopWatching()
    self.context:RemoveEvent("ADDON_LOADED")
    HideAll()
end

S.Install("groupFinderLocations", Locations)
