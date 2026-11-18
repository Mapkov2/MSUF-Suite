local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Transmog = {}
P.BagTransmog = Transmog

local Collection = C_TransmogCollection
local MISSING, ALTERNATE, COLLECTED = 1, 2, 3
local LIMIT = 512
local links, sources, linkCount, sourceCount = {}, {}, 0, 0
local stale, enabled, listening = true, false, false
local badges = setmetatable({}, { __mode = "k" })
local nativeMessages = {
    [MISSING] = _G.TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN,
    [ALTERNATE] = _G.TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE_KNOWN,
    [COLLECTED] = _G.TRANSMOGRIFY_TOOLTIP_APPEARANCE_KNOWN,
}
local events, badgeTimer

local function Readable(value)
    return S.Public(value) and type(value) == "table" and canaccesstable(value)
end

local function ResolveSource(link)
    local source = links[link]
    if source ~= nil then return source or nil end
    if not (link:find("|Hitem:", 1, true) or link:sub(1, 5) == "item:") then return end
    local _, id = Collection.GetItemInfo(link)
    if not S.Public(id) then return end
    if not S.Finite(id) or id < 1 then
        -- An uncached item can return no appearance before its data arrives.
        local cached = C_Item.IsItemDataCachedByID(link)
        if not S.Public(cached) or cached ~= true then return end
        id = false
    end
    if linkCount == LIMIT then
        wipe(links)
        linkCount = 0
    end
    links[link], linkCount = id, linkCount + 1
    return id or nil
end

local function Status(link)
    link = S.PublicText(link)
    if not link then return end
    if stale then
        wipe(links)
        wipe(sources)
        linkCount, sourceCount, stale = 0, 0, false
    end
    local source = ResolveSource(link)
    if not source then return end
    local status = sources[source]
    if status then return status end
    local info = Collection.GetAppearanceInfoBySource(source)
    if not Readable(info) then return end
    local appearance, exact = info.appearanceIsCollected, info.sourceIsCollected
    if not S.Public(appearance) or not S.Public(exact)
        or type(appearance) ~= "boolean" or type(exact) ~= "boolean" then return end
    status = exact and COLLECTED or appearance and ALTERNATE or MISSING
    if sourceCount == LIMIT then
        wipe(sources)
        sourceCount = 0
    end
    sources[source], sourceCount = status, sourceCount + 1
    return status
end

local function StatusText(status)
    if status == COLLECTED then return S.Text("Transmog source collected") end
    if status == ALTERNATE then return S.Text("Transmog appearance collected from another source") end
    return S.Text("Transmog appearance not collected")
end

local function AlreadyShown(data, text, status)
    local rows = data.lines
    if not Readable(rows) then return true end
    local native = nativeMessages[status]
    for i = 1, #rows do
        local row = rows[i]
        if Readable(row) then
            local left = S.PublicText(row.leftText)
            if left and (left == text or left == native) then return true end
        end
    end
    return false
end

function Transmog.Tooltip(tooltip, data)
    if NS.InCombat() or NS.Safety.IsForbidden(tooltip) or not Readable(data) then return end
    local primary = tooltip:GetPrimaryTooltipData()
    if not S.Public(primary) or primary ~= data then return end
    local link = S.PublicText(data.hyperlink)
    if not link then
        local guid = S.PublicText(data.guid)
        if guid then link = C_Item.GetItemLinkByGUID(guid) end
    end
    local status = Status(link)
    if not status then return end
    local text = StatusText(status)
    if not AlreadyShown(data, text, status) then tooltip:AddLine(text, .67, .82, 1) end
end

local function PaintBadge(button, item)
    local status = S.PublicText(item.equipLoc) and Status(item.link)
    local badge = badges[button]
    if status == MISSING or status == ALTERNATE then
        if not badge then
            badge = M.OverlayText(button, "RIGHT", -2, 0, "RIGHT")
            S.SetFont(badge, nil, 12, "OUTLINE")
            badge.transmogBank = item.bankType ~= nil
            badges[button] = badge
        end
        if badge.transmogStatus ~= status then
            badge.transmogStatus = status
            badge:SetText(status == MISSING and "!" or "+")
            if status == MISSING then badge:SetTextColor(1, .78, .28)
            else badge:SetTextColor(.59, .82, 1) end
        end
        if not badge:IsShown() then badge:Show() end
    elseif badge and badge:IsShown() then
        badge:Hide()
    end
end

function Transmog.Paint(button, item)
    if not NS.InCombat() then PaintBadge(button, item) end
end

function Transmog.HideBadges(onlyBags)
    for _, badge in pairs(badges) do
        if (not onlyBags or not badge.transmogBank) and badge:IsShown() then badge:Hide() end
    end
end

local function VisibleBags()
    local view = P.InventoryView
    if view.active and view.layout == "suite" and view.frame:IsVisible() then return view end
end

local function VisibleBank()
    local view = P.BankInventory
    if view.active and view.frame:IsVisible() then return view end
end

-- Resolve the view's current row at repaint time. A slot can have moved,
-- been hidden or been reused between a collection event and this callback.
local function RepaintBags(view)
    for button in pairs(view.visibleButtons) do
        local slot = view.slotState[button]
        local item = slot and slot.row and slot.row.item
        if item and button:IsVisible() then PaintBadge(button, item) end
    end
end

local function RepaintBank(view)
    for _, button in ipairs(view.buttons) do
        if button.record and button:IsVisible() then PaintBadge(button, button.record) end
    end
end

local function RepaintVisible()
    badgeTimer = nil
    if not listening or not M.config.showTransmogBadges or NS.InCombat() then return end
    local bag, bank = VisibleBags(), VisibleBank()
    if bag then RepaintBags(bag) end
    if bank then RepaintBank(bank) end
end

local function Changed()
    if stale or NS.InCombat() then return end
    stale = true
    if not badgeTimer and M.config.showTransmogBadges and (VisibleBags() or VisibleBank()) then
        badgeTimer = C_Timer.NewTimer(0, RepaintVisible)
    end
end

local function CancelRepaint()
    if not badgeTimer then return end
    badgeTimer:Cancel()
    badgeTimer = nil
end

function Transmog.Pause()
    if not listening then return end
    listening = false
    CancelRepaint()
    events:UnregisterEvent("TRANSMOG_COLLECTION_UPDATED")
    events:UnregisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")
    P.InventoryDetails.SetTransmog(false)
    Transmog.HideBadges()
end

local function Resume(event)
    if NS.InCombat(event) then return end
    if not listening then
        -- A collection change in combat has no listener. Resolve fresh data
        -- when a tooltip or a visible slot next needs it outside combat.
        stale, listening = true, true
        events:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
        events:RegisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")
    end
    local showBadges = M.config.showTransmogBadges
    P.InventoryDetails.SetTransmog(true, showBadges)
    if not showBadges then
        CancelRepaint()
        Transmog.HideBadges()
    end
end

function Transmog.Disable()
    if not enabled then return end
    enabled = false
    Transmog.Pause()
    events:UnregisterAllEvents()
    wipe(links)
    wipe(sources)
    linkCount, sourceCount, stale = 0, 0, true
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        Transmog.Pause()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Resume(event)
    else
        Changed()
    end
end

function Transmog.Refresh()
    if not M.config.showTransmogStatus then
        Transmog.Disable()
        return
    end
    if not enabled then
        enabled = true
        if not events then
            -- Bags already owns the regen callback in its shared context.
            events = S.CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    if NS.InCombat() then Transmog.Pause() else Resume() end
end
