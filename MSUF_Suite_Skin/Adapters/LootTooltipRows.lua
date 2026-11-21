local _, NS = ...

local Rows = {}
NS.LootTooltipRows = Rows
local Safety, Kit, Card = NS.Safety, NS.AdapterKit, NS.ItemTooltipCard
local rows, owners = Kit.WeakSet(), {}
local root, box, callbacks, enabled

local function Release(record)
    if not record or not record.active then return end
    record.active = false
    record.header.frame:Hide()
    record.outline.frame:Hide()
    NS.Cosmetics.RestoreOwner(record)
end

local function Released(_, row)
    if Safety.Public(row) then Release(rows[row]) end
end

local function New(row, item)
    local header = Card.Create(row, true)
    -- Keep Blizzard's actual item icon and its stack and quest overlays.
    header.frame:SetPoint("TOPLEFT", item, "TOPRIGHT", 2, 2)
    header.frame:SetPoint("TOPRIGHT", row, "TOPRIGHT", -1, -2)
    local outline = Card.CreateOutline(row, true)
    outline.frame:SetFrameLevel(row:GetFrameLevel() + 3)
    local record = { header = header, outline = outline }
    rows[row] = record
    return record
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
    local slot = Safety.Read(row, "GetSlotIndex")
    if type(slot) ~= "number" or slot < 1 then Release(record) return end
    local link = GetLootSlotLink(slot)
    local kind, level
    if Safety.Public(link) and type(link) == "string" and link ~= "" then
        local _
        _, kind, level = Card.ReadItem(link)
    end
    record = record or New(row, item)
    record.active = true
    if not (NS.Cosmetics.Fade(text, record) and NS.Cosmetics.Fade(qualityText, record)) then Release(record) return end
    NS.Cosmetics.Fade(row.QualityStripe, record)
    local quality = Safety.Read(row, "GetQuality")
    Card.Draw(record.header, name, nil, kind, level, quality, height - 4)
    record.header.frame:Show()
    local r, g, b = record.header.r, record.header.g, record.header.b
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
    local wanted = next(owners) ~= nil and NS.DB.enabled ~= false and Card.TypeStyle("loot") == "custom"
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
