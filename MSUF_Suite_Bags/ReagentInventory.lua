local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Reagent = { buttons = {}, controls = {}, pooled = setmetatable({}, { __mode = "k" }) }
P.ReagentInventory = Reagent
local BAG = Enum.BagIndex.ReagentBag

function Reagent.Enabled(c)
    return c.combineReagentBag == true and c.inventoryView ~= NS.BagsView.BLIZZARD_GRID and not S.GamepadUI()
end

local function Changed()
    if not M.active then return end
    P.InventoryIndex.Invalidate(P.InventoryView.index)
    P.InventoryView.positionsDirty = true
    for _, slot in pairs(P.InventoryView.slotState) do slot.x, slot.y = nil, nil end
    P.InventoryView.Request()
end

local function LayoutChanged()
    for _, button in ContainerFrame6:EnumerateValidItems() do
        local record = M.overlays[button]
        if record then record.slotStyle, record.strokeStyle = nil, nil end
    end
    Changed()
end

local function Property(frame, getter, setter, value)
    local ctx = Reagent.context
    local set = NS.IsCombatLocked() and ctx.UnprotectedProperty or ctx.Property
    return set(ctx, frame, getter, setter, value)
end

function Reagent.Release()
    if not Reagent.active then return end
    if NS.IsCombatLocked() then
        S.Queue("bags")
        return
    end
    for button in pairs(Reagent.buttons) do
        Reagent.context:RestoreProperty(button, "SetParent")
        Reagent.buttons[button] = nil
    end
    for control in pairs(Reagent.controls) do
        Reagent.context:HideControl(control, false)
        Reagent.controls[control] = nil
    end
    Reagent.context:HideControl(ContainerFrame6, false)
    Reagent.active = false
    ContainerFrame6:UpdateItemLayout()
    Changed()
end

local function MuteChildren(...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        if not Reagent.pooled[child] then
            P.BagLayout.HideControl(Reagent.context, child, true)
            Reagent.controls[child] = true
        end
    end
end

-- Keep the native reagent container shown and listening to its events. Only
-- its shell is muted; its own buttons retain Blizzard's bag/slot identity,
-- item actions, cooldowns, search, tooltips and new-item handling.
function Reagent.Prepare()
    local view, frame = P.InventoryView, ContainerFrame6
    if not Reagent.Enabled(M.config) or not view.frame:IsShown() then
        Reagent.Release()
        return
    end
    if NS.InCombat() and not Reagent.active then return end
    local size = P.SlotCache.Sync(BAG)
    if not S.Finite(size) or size == 0 then
        Reagent.Release()
        return
    end
    if not frame:IsShown() then
        if NS.InCombat() then return end
        OpenBag(BAG)
    end
    if not frame:IsShown() then return end
    if NS.IsCombatLocked() and not P.BagLayout.Frame(frame) then return end
    if not Reagent.active then P.InventoryIndex.Invalidate(view.index) end
    Reagent.active = true
    Property(frame, "GetAlpha", "SetAlpha", 0)
    Property(frame, "IsMouseEnabled", "EnableMouse", false)
    Reagent.generation = (Reagent.generation or 0) + 1
    for _, button in frame:EnumerateValidItems() do
        if not NS.IsCombatLocked() or P.BagLayout.Frame(button) then
            Reagent.pooled[button] = true
            if Reagent.controls[button] then
                Reagent.context:HideControl(button, false)
                Reagent.controls[button] = nil
            end
            Property(button, "GetParent", "SetParent", view.frame)
            Reagent.buttons[button] = Reagent.generation
            M:StyleSlot(button)
        end
    end
    for button, generation in pairs(Reagent.buttons) do
        if generation ~= Reagent.generation and (not NS.IsCombatLocked() or P.BagLayout.Frame(button)) then
            P.BagLayout.RestoreProperty(Reagent.context, button, "SetParent")
            Reagent.buttons[button] = nil
        end
    end
    MuteChildren(frame:GetChildren())
end

function Reagent.Refresh()
    -- Only property records are used and restored explicitly: releasing a
    -- second module context would also release the main Bags skin ownership.
    Reagent.context = Reagent.context or S.NewContext("bags")
    if not Reagent.hooked then
        hooksecurefunc(ContainerFrame6, "UpdateItems", Changed)
        hooksecurefunc(ContainerFrame6, "UpdateItemLayout", LayoutChanged)
        ContainerFrame6:HookScript("OnHide", Changed)
        Reagent.hooked = true
    end
    if not Reagent.Enabled(M.config) then Reagent.Release() end
end

function Reagent.AppendButtons(buttons, order)
    if not Reagent.active then return end
    for _, button in ContainerFrame6:EnumerateValidItems() do
        local slot = button:GetID()
        if S.Finite(slot) and slot > 0 and slot < P.SlotCache.KEY then
            local key = BAG * P.SlotCache.KEY + slot
            if not buttons[key] then order[#order + 1] = key end
            buttons[key] = button
        end
    end
end
