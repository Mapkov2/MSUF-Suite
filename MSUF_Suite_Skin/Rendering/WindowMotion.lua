local _, NS = ...

-- Native windows keep their own layout, visibility and input. This controller
-- draws a short trace with detached Suite artwork in UIParent coordinates.
local WindowMotion = {}
NS.WindowMotion = WindowMotion
local Motion, Safety, Registry = NS.Motion, NS.Safety, NS.Registry
local Bounds, Shape = NS.WindowFocusGeometry, NS.Geometry
local spec = { windowAnimation = true, role = "shell", border = 2 }
local RESIZE_DURATION, CLOSE_DURATION = 0.28, 0.26
local CLOSE_SCALE = 0.84
local watched = setmetatable({}, { __mode = "k" })
local active = {}
local events = CreateFrame("Frame")
local roots = {
    CharacterFrame = true,
    MerchantFrame = true,
    InspectFrame = true,
    CollectionsJournal = true,
    AuctionHouseFrame = true,
    MacroFrame = true,
}

local function SafeContext()
    return not Motion.combat and not NS.IsCombatLocked() and not NS.Client.IsGamepadUI()
end

local function Available()
    return Motion.Enabled(spec) and SafeContext()
end

local function Live(record)
    if next(record.owners) == nil or not Available() then return false end
    if record.shop then return not Safety.IsForbidden(record.frame) end
    return Safety.CanCreateRegions(record.frame) and (record.preview or Safety.Read(record.frame, "GetParent") == UIParent)
end

local function CanOpenShop(record)
    return next(record.owners) ~= nil and Motion.WindowEnabled() and SafeContext()
        and not Safety.IsForbidden(record.frame)
end

local function StopVisual(record)
    if not active[record] then return end
    active[record] = nil
    record.art:Hide()
    if not next(active) then events:SetScript("OnUpdate", nil) end
end

local function Clear(record)
    record.pending, record.hasBounds = nil, false
    StopVisual(record)
end

local function CanDisplay(record)
    return not record.preview or Safety.Read(Safety.Read(record.frame, "GetParent"), "IsVisible") == true
end

local function CreateArt(record)
    local art = Safety.CreateChildFrame("Frame", UIParent)
    art:EnableMouse(false)
    art:Hide()
    local fill = art:CreateTexture(nil, "BACKGROUND")
    local edge = art:CreateTexture(nil, "BORDER")
    fill:SetAllPoints(art)
    edge:SetAllPoints(art)
    record.art, record.fill, record.edge = art, fill, edge
end

local function Paint(record, progress)
    local art, current = record.art, record.drawn
    local blend = progress * progress * (3 - 2 * progress)
    current.left = record.startLeft + record.travelX * blend
    current.bottom = record.startBottom + record.travelY * blend
    current.width = record.startWidth + record.travelWidth * blend
    current.height = record.startHeight + record.travelHeight * blend
    art:ClearAllPoints()
    art:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", current.left, current.bottom)
    art:SetSize(current.width, current.height)
    art:SetAlpha(1 - progress * progress)
end

-- Share the event frame between active traces. Sampling actual elapsed time
-- keeps prominent window motion independent of the quick control springs.
local function Step(_, elapsed)
    local safe = SafeContext()
    local extended = safe and Motion.Enabled(spec)
    local openings = safe and Motion.WindowEnabled()
    for record in pairs(active) do
        record.elapsed = record.elapsed + elapsed
        local available = record.opening and openings or extended
        if not available or record.elapsed >= record.duration or not CanDisplay(record) then
            StopVisual(record)
        else
            Paint(record, record.elapsed / record.duration)
        end
    end
end

local function Play(record, from, to, fillAlpha, duration, opening)
    if not CanDisplay(record) or (not record.shop and not Bounds.Layer(record)) then return end
    if not record.art then CreateArt(record) end
    local art = record.art
    art:SetFrameStrata(record.strata)
    art:SetFrameLevel(record.level)
    record.shape = Shape.Resolve(spec, record.shape)
    Shape.ConfigureShape(record.fill, record.shape.fill, record.shape)
    Shape.ConfigureShape(record.edge, record.shape.edge, record.shape)
    local red, green, blue = NS.Theme.GetColor("accent")
    record.fill:SetVertexColor(red, green, blue, fillAlpha)
    record.edge:SetVertexColor(red, green, blue, 0.96)
    record.startLeft, record.startBottom = from.left, from.bottom
    record.startWidth, record.startHeight = from.width, from.height
    record.travelX, record.travelY = to.left - from.left, to.bottom - from.bottom
    record.travelWidth, record.travelHeight = to.width - from.width, to.height - from.height
    record.elapsed, record.duration, record.opening = 0, duration, opening
    Paint(record, 0)
    art:Show()
    if not next(active) then events:SetScript("OnUpdate", Step) end
    active[record] = true
end

local function Read(frame, rect)
    return Bounds.Read(frame, rect) and math.abs(rect.left) < math.huge and math.abs(rect.bottom) < math.huge
        and rect.width > 0 and rect.width < math.huge and rect.height > 0 and rect.height < math.huge
end

local function DifferentSize(first, second)
    return math.abs(first.width - second.width) >= 1 or math.abs(first.height - second.height) >= 1
end

local function ScaleAboutCenter(source, target, scale)
    target.width, target.height = source.width * scale, source.height * scale
    target.left = source.left + (source.width - target.width) / 2
    target.bottom = source.bottom + (source.height - target.height) / 2
end

local function Settle(record)
    local pending = record.pending
    record.pending = nil
    if not pending or record.interacting or Safety.Read(record.frame, "IsVisible") ~= true then return end
    if pending == "shop-open" then
        if not CanOpenShop(record) then return end
    elseif not Live(record) then return end
    local previous, current = record.bounds, record.sample
    if not Read(record.frame, current) or (record.shop and not Bounds.Layer(record)) then
        Clear(record)
        return
    end
    if pending == "resize" and record.hasBounds and DifferentSize(previous, current) then
        local start = active[record] and record.drawn or previous
        Play(record, start, current, 0.15, RESIZE_DURATION)
    elseif pending == "shop-open" then
        local extended = Motion.Enabled(spec)
        ScaleAboutCenter(current, previous, extended and 0.90 or 1)
        Play(record, previous, current, extended and 0.12 or 0, extended and 0.24 or 0.12, true)
    end
    record.bounds, record.sample, record.hasBounds = current, previous, true
end

local function Queue(record, purpose)
    if record.pending ~= "baseline" and record.pending ~= "shop-open" then record.pending = purpose end
    Registry.QueueJob(record.settle)
end

function WindowMotion.GeometryChanged(frame)
    local record = watched[frame]
    if not record or record.interacting then return end
    if Live(record) then Queue(record, "resize") else Clear(record) end
end

local function Shown(frame)
    local record = watched[frame]
    Clear(record)
    if Live(record) then Queue(record, "baseline") end
end

local function Hidden(frame)
    local record = watched[frame]
    local canClose = record.hasBounds and not record.interacting and Live(record)
        and (record.shop or Safety.Read(frame, "IsShown") == false)
    local from, to = record.bounds, record.sample
    Clear(record)
    record.interacting = nil
    if not canClose then return end
    -- Prefer the last settled size if this panel's OnHide reset the layout.
    -- Read a final position for panels moved by Blizzard without a size event.
    -- The secure shop announces its hide after teardown. Use its last visible
    -- bounds and layer instead of reading geometry after that notification.
    if not record.shop and Read(frame, to) and not DifferentSize(from, to) then from, to = to, from end
    ScaleAboutCenter(from, to, CLOSE_SCALE)
    Play(record, from, to, 0.24, CLOSE_DURATION)
end

local function Bind(record)
    if record.shop or record.hooked or not Live(record) then return end
    local frame = record.frame
    if not Safety.HasMethod(frame, "HookScript") or not Safety.HasMethod(frame, "HasScript")
        or Safety.Read(frame, "HasScript", "OnShow") ~= true or Safety.Read(frame, "HasScript", "OnHide") ~= true
        or Safety.Read(frame, "HasScript", "OnSizeChanged") ~= true then return end
    frame:HookScript("OnShow", Safety.Isolated(Shown))
    frame:HookScript("OnHide", Safety.Isolated(Hidden))
    frame:HookScript("OnSizeChanged", Safety.Isolated(WindowMotion.GeometryChanged))
    record.hooked = true
end

local function Track(frame, owner, preview, shop)
    if not Safety.Public(owner) or owner == nil then return false end
    local record = watched[frame]
    if not record then
        record = { frame = frame, owners = {}, bounds = {}, sample = {}, drawn = {}, preview = preview, shop = shop }
        record.settle = function() Settle(record) end
        watched[frame] = record
    end
    if record.owners[owner] then return true end
    record.owners[owner] = true
    Bind(record)
    if record.hooked and not record.hasBounds and Live(record) and Safety.Read(frame, "IsVisible") == true then
        Queue(record, "baseline")
    end
    return true
end

function WindowMotion.Watch(frame, owner)
    if not Safety.CanCreateRegions(frame) then return false end
    local name = Safety.Read(frame, "GetName")
    if type(name) ~= "string" or Safety.Read(frame, "GetParent") ~= UIParent then return false end
    local root = Safety.Field(_G, name)
    if not Safety.Public(root) or root ~= frame then return false end
    if not roots[name] and not NS.WindowControlPolicy.IsAnimationWindow(frame) then return false end
    return Track(frame, owner, false)
end

function WindowMotion.ShopVisibility(frame, shown)
    local record = watched[frame]
    if not record or not record.shop or not Safety.Public(shown) then return end
    if shown ~= true then
        if shown == false then Hidden(frame) end
        return
    end
    Clear(record)
    if CanOpenShop(record) then Queue(record, "shop-open") end
end

function WindowMotion.WatchShop(frame, owner)
    if Safety.IsForbidden(frame) or Safety.Read(frame, "GetParent") ~= UIParent
        or Safety.Field(_G, "CatalogShopFrame") ~= frame then return false end
    local first = not watched[frame] or next(watched[frame].owners) == nil
    if not Track(frame, owner, false, true) then return false end
    -- The secure shop can open before the catalog receives its LoD callback.
    if first and Safety.Read(frame, "IsVisible") == true then WindowMotion.ShopVisibility(frame, true) end
    return true
end

function WindowMotion.WatchPreview(frame, owner)
    if not Safety.CanCreateRegions(frame) then return false end
    return Track(frame, owner, true)
end

function WindowMotion.Unwatch(frame, owner)
    if not Safety.Public(owner) then return end
    local record = watched[frame]
    if not record or not record.owners[owner] then return end
    record.owners[owner] = nil
    if not next(record.owners) then Clear(record) end
end

function WindowMotion.SetGeometryInteraction(frame, active)
    local record = watched[frame]
    if not record then return end
    record.interacting = active or nil
    Clear(record)
    if not active and Live(record) then Queue(record, "baseline") end
end

function WindowMotion.Refresh()
    for _, record in pairs(watched) do
        Clear(record)
        Bind(record)
        if (record.shop or record.hooked) and not record.interacting and Live(record)
            and Safety.Read(record.frame, "IsVisible") == true then Queue(record, "baseline") end
    end
end

NS.WindowControls.SetGeometryMotionProvider(WindowMotion.GeometryChanged, WindowMotion.SetGeometryInteraction)

Registry.AddListener(WindowMotion, function(_, domain, key)
    if domain == "profile" or domain == "theme"
        or domain == "motion" and (key == "windowAnimations" or key == "reduceMotion" or key == "menuAnimations") then
        WindowMotion.Refresh()
    elseif domain ~= "readability" then
        for record in pairs(active) do StopVisual(record) end
    end
end)

events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if next(watched) then Registry.QueueJob(WindowMotion.Refresh) end
    else
        for _, record in pairs(watched) do Clear(record) end
    end
end)
