local _, P = ...
local NS, S = P.NS, P.Suite
-- Decorations belong to the Suite; native item buttons keep their alpha,
-- scripts and drag/click behavior. Repaint only on hover or an inventory pass.
local Hover = { frames = {} }
P.BagHover = Hover
local owner

local function Edge(parent, first, second, horizontal)
    local edge = S.CreateTexture(parent, nil, "OVERLAY", nil, 7)
    edge:SetColorTexture(.25, .72, 1, .95)
    edge:SetPoint(first)
    edge:SetPoint(second)
    if horizontal then edge:SetHeight(2) else edge:SetWidth(2) end
    return edge
end

local function Decoration(button)
    local frame = Hover.frames[button]
    if frame then return frame end
    -- Textures have no mouse or protected frame visibility. They remain safe
    -- to hide in lockdown even when the native item button is protected.
    frame = { fill = S.CreateTexture(button, nil, "OVERLAY", nil, 6) }
    frame.fill:SetAllPoints(button)
    frame.edges = {
        Edge(button, "TOPLEFT", "TOPRIGHT", true), Edge(button, "BOTTOMLEFT", "BOTTOMRIGHT", true),
        Edge(button, "TOPLEFT", "BOTTOMLEFT", false), Edge(button, "TOPRIGHT", "BOTTOMRIGHT", false),
    }
    Hover.frames[button] = frame
    return frame
end

local function Paint(button, match)
    local frame = Decoration(button)
    if frame.match ~= match then
        frame.match = match
        if match then
            frame.fill:SetColorTexture(.15, .55, 1, .12)
        else
            frame.fill:SetColorTexture(0, 0, 0, .5)
        end
    end
    frame.fill:Show()
    for i = 1, #frame.edges do frame.edges[i]:SetShown(match) end
end

local function Hide(frame)
    frame.fill:Hide()
    for i = 1, #frame.edges do frame.edges[i]:Hide() end
end

function Hover.Clear()
    owner = nil
    for _, frame in pairs(Hover.frames) do Hide(frame) end
end

-- A displayed stack may contain items from several bags. All contributing
-- physical stacks count, including a bag other than the representative's.
local function Matches(button, row, bag)
    if row then
        if row.stacks > 1 and row.bags then return row.bags[bag] ~= nil end
        return row.item.bag == bag
    end
    local id = button:GetBagID()
    return S.Finite(id) and id == bag
end

function Hover.Refresh()
    if not owner then return end
    local view = P.InventoryView
    if NS.InCombat() or not owner:IsShown() or not view or not view.SuiteLayout() then
        Hover.Clear()
        return
    end
    for _, frame in pairs(Hover.frames) do Hide(frame) end
    for button in pairs(view.visibleButtons) do
        local slot = view.slotState[button]
        Paint(button, Matches(button, slot and slot.row, owner.bagID))
    end
    -- Retail's separate reagent bag is beside the combined inventory.
    local reagent = ContainerFrame6
    if reagent and reagent:IsShown() then
        for _, button in reagent:EnumerateValidItems() do Paint(button, Matches(button, nil, owner.bagID)) end
    end
end

function Hover.Enter(button)
    if not S.Finite(button.bagID) then return end
    owner = button
    Hover.Refresh()
end

function Hover.Leave(button)
    if owner == button then Hover.Clear() end
end

function Hover.IsOwner(button) return owner == button end

function Hover.Tooltip(button)
    local free, total = C_Container.GetContainerNumFreeSlots(button.bagID), C_Container.GetContainerNumSlots(button.bagID)
    if S.Finite(free) and S.Finite(total) and free >= 0 and free <= total and total > 0 then
        GameTooltip:AddLine(string.format(S.Text("%d of %d slots occupied; %d free."), total - free, total, free), .8, .88, 1)
        GameTooltip:AddLine(
            S.Text("Highlighted items belong to this bag, including combined stacks. Some slots may be hidden by the current view."),
            .72, .78, .85, true)
    end
end
