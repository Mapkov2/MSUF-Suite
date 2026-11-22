local _, NS = ...

local Rows = {}
NS.LootTooltipRows = Rows
local Safety, Kit, Card = NS.Safety, NS.AdapterKit, NS.ItemTooltipCard
local rows, owners = Kit.WeakSet(), {}
local root, box, callbacks, enabled, rich, matching

local function ReleaseHeader(header)
    if not header then return end
    header.frame:Hide()
    NS.Cosmetics.RestoreOwner(header)
end

local function Release(record)
    if not record or not record.active then return end
    record.active = false
    ReleaseHeader(record.header)
    if record.outline then record.outline.frame:Hide() end
    if record.backing then record.backing:Hide() end
    NS.Cosmetics.RestoreOwner(record)
    record.nativeFill = nil
end

local function Released(_, row)
    if Safety.Public(row) then Release(rows[row]) end
end

local function PaintBacking(record, row, level)
    local native = matching and Safety.Field(row, "NameFrame")
    if not native or level < 1 or not Kit.ParentIs(native, row) then
        if record.backing then record.backing:Hide() end
        NS.Cosmetics.Restore(record.nativeFill, record)
        record.nativeFill = nil
        return false
    end
    if record.nativeFill ~= native then
        NS.Cosmetics.Restore(record.nativeFill, record)
        record.nativeFill = nil
    end
    if not record.backing then
        record.backing = Card.CreateBacking(row, level - 1)
        if not record.backing then return false end
        record.backing:SetAllPoints(row)
    elseif record.backing:GetFrameLevel() ~= level - 1 then
        record.backing:SetFrameLevel(level - 1)
    end
    if not record.nativeFill or Safety.Read(native, "GetAlpha") ~= 0 then
        if not NS.Cosmetics.Fade(native, record) then
            record.backing:Hide()
            return false
        end
        record.nativeFill = native
    end
    if not record.backing:IsShown() then record.backing:Show() end
    return true
end

local function PaintHeader(record, row, item, slot, name, height, unified)
    local text, qualityText = row.Text, row.QualityText
    local header = record.header
    if not header then
        header = Card.Create(row, true)
        -- Keep Blizzard's item widget, its stack, and its quest overlays.
        header.frame:SetPoint("TOPLEFT", item, "TOPRIGHT", 2, 2)
        header.frame:SetPoint("TOPRIGHT", row, "TOPRIGHT", -1, -2)
        record.header = header
    end
    if not (NS.Cosmetics.Fade(text, header) and NS.Cosmetics.Fade(qualityText, header)) then
        ReleaseHeader(header)
        return
    end
    NS.Cosmetics.Fade(row.QualityStripe, header)
    local link = GetLootSlotLink(slot)
    local kind, level
    if Safety.Public(link) and type(link) == "string" and link ~= "" then
        local _
        _, kind, level = Card.ReadItem(link)
    end
    Card.SetUnifiedHeader(header, unified)
    Card.Draw(header, name, nil, kind, level, Safety.Read(row, "GetQuality"), height - 4)
    header.frame:Show()
    return header
end

local function Paint(row)
    if not enabled or not Safety.Public(row) or not Safety.CanCreateRegions(row) then return end
    local record = rows[row]
    if Safety.Read(row, "GetItemSlotType") ~= Enum.LootSlotType.Item then Release(record) return end
    local item, text, qualityText = row.Item, row.Text, row.QualityText
    local height, name = Safety.Read(row, "GetHeight"), Safety.Read(text, "GetText")
    if not Kit.ParentIs(item, row) or not Kit.ParentIs(text, row) or not Kit.ParentIs(qualityText, row)
        or type(height) ~= "number" or height < 36 or type(name) ~= "string" or name == "" then
        Release(record)
        return
    end
    local slot, frameLevel = Safety.Read(row, "GetSlotIndex"), Safety.Read(row, "GetFrameLevel")
    if type(slot) ~= "number" or slot < 1 or type(frameLevel) ~= "number" then Release(record) return end
    if not record then
        record = {}
        rows[row] = record
    end
    record.active = true
    local unified = PaintBacking(record, row, frameLevel)
    local header
    if rich then
        header = PaintHeader(record, row, item, slot, name, height, unified)
    else
        ReleaseHeader(record.header)
    end
    if not unified and not header then Release(record) return end
    local r, g, b
    if header then r, g, b = header.r, header.g, header.b
    else r, g, b = Safety.ReadColor(text, "GetTextColor") end
    if not record.outline then record.outline = Card.CreateOutline(row, true) end
    if record.outline.frame:GetFrameLevel() ~= frameLevel + 3 then record.outline.frame:SetFrameLevel(frameLevel + 3) end
    Card.PaintOutline(record.outline, row, row, r, g, b)
    if record.outline.frame:IsShown() then NS.Cosmetics.Fade(row.BorderFrame, record)
    else NS.Cosmetics.Restore(row.BorderFrame, record) end
end

local function PaintRow(row)
    Safety.Dispatch(Paint, row)
end

local function Initialized(_, row)
    PaintRow(row)
end

local function OnHide()
    for _, record in pairs(rows) do Release(record) end
end

local function OnEvent(_, event, slot)
    -- Blizzard reinitializes a row in place for this event, without notifying
    -- the ScrollBox's initialization subscribers.
    if not enabled or event ~= "LOOT_SLOT_CHANGED" or not Safety.Public(slot) then return end
    local row = box:FindFrameByPredicate(function(frame) return Safety.Read(frame, "GetSlotIndex") == slot end)
    if row then PaintRow(row) end
end

local function Refresh()
    if not root then return end
    rich, matching = Card.TypeStyle("loot") == "custom", Card.MatchesLootSurface()
    local wanted = next(owners) ~= nil and NS.DB.enabled ~= false and (rich or matching)
    if wanted ~= enabled then
        enabled = wanted
        if wanted then
            box:RegisterCallback(callbacks.OnInitializedFrame, Initialized, Rows)
            box:RegisterCallback(callbacks.OnReleasedFrame, Released, Rows)
        else
            box:UnregisterCallback(callbacks.OnInitializedFrame, Rows)
            box:UnregisterCallback(callbacks.OnReleasedFrame, Rows)
            OnHide()
        end
    end
    if wanted and Safety.Read(root, "IsShown") == true then Kit.ForEachRow(box, PaintRow) end
end

local function ThemeChanged(_, domain)
    if domain == "tooltipStyle" or domain == "theme" or domain == "color" or domain == "profile"
        or domain == "appearance" or domain == "typography" or domain == "geometry" then Refresh() end
end

function Rows.Apply(frame, owner)
    if not root then
        local scrollBox = Safety.Field(frame, "ScrollBox")
        local events = ScrollBoxListMixin and ScrollBoxListMixin.Event
        if not events or not events.OnInitializedFrame or not events.OnReleasedFrame
            or not Safety.HasMethod(scrollBox, "RegisterCallback") then return end
        root, box, callbacks, enabled = frame, scrollBox, events, false
        root:HookScript("OnHide", OnHide)
        root:HookScript("OnEvent", OnEvent)
        NS.Registry.AddListener(Rows, ThemeChanged)
    end
    owners[owner] = true
    Refresh()
end

function Rows.Disable(owner)
    owners[owner] = nil
    Refresh()
end
