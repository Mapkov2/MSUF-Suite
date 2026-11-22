local _, NS = ...
local Safety = NS.Safety
local Reference, owner = {}, {}
NS.ItemReference = Reference

local itemReferenceCells = setmetatable({}, { __mode = "k" })

local function ItemReferenceCaptionColor()
    return NS.TooltipPalette.Title()
end

local function DismissItemReference(cell)
    local frame = cell:GetParent()
    -- This is a special window outside the UI panel layout. Blizzard also
    -- hides it directly when the same link is clicked or Escape closes it.
    if cell.itemReferenceOwner and frame == Safety.Field(_G, "ItemRefTooltip")
        and Safety.CanControl(frame) then
        frame:Hide()
    end
end

function Reference.Apply(frame)
    -- The native X calls HideUIPanel, which refuses insecure combat calls
    -- even for this unmanaged tooltip. Use the same hit rectangle.
    local close = Safety.Field(frame, "CloseButton")
    if not Safety.Public(close) or not Safety.CanCreateRegions(frame) or not Safety.CanControl(close)
        or Safety.Read(close, "GetParent") ~= frame then return end
    local level = Safety.Read(close, "GetFrameLevel")
    if not level then return end
    local caption = NS.SuiteCore().WindowCaption
    local cell = itemReferenceCells[close]
    if not cell then
        cell = Safety.CreateChildFrame("Button", frame)
        if not cell then return end
        cell:Hide()
        cell:EnableMouse(true)
        cell:SetAllPoints(close)
        caption.Dress(cell, "close", ItemReferenceCaptionColor)
        cell:RegisterForClicks("LeftButtonUp")
        cell:SetScript("OnClick", DismissItemReference)
        close:HookScript("OnShow", function()
            if itemReferenceCells[close] == cell and cell.itemReferenceOwner then
                cell:Show()
            end
        end)
        close:HookScript("OnHide", function() cell:Hide() end)
        cell:HookScript("OnShow", function() caption.SetKind(cell, "close") end)
        itemReferenceCells[close] = cell
    end
    if not NS.Cosmetics.Fade(close, owner) then return end
    cell.itemReferenceOwner = owner
    cell:SetFrameLevel(level + 1)
    cell:SetShown(Safety.Read(close, "IsShown") == true)
end

function Reference.Disable()
    for close, cell in pairs(itemReferenceCells) do
        if cell.itemReferenceOwner then
            cell.itemReferenceOwner = nil
            cell:Hide()
            NS.Cosmetics.Restore(close, owner)
        end
    end
end
