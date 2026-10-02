local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
-- Split amounts and automatic splitting, beside Blizzard's stack split window
-- (attached) or on their own for the Suite bank view. The amount lives in
-- this panel: the Suite never writes StackSplitFrame fields, calls its
-- methods or hides it. Its OnHide releases held key bindings and owner state
-- (StackSplitFrame.lua), which must stay Blizzard's own secure code.
local Splitter = { amount = 1, stack = 1 }
P.StackSplitter = Splitter
local PRESETS = { 1, 5, 10, 20 }

local function Close()
    if Splitter.frame then Splitter.frame:Hide() end
    Splitter.owner, Splitter.attached = nil, false
end
Splitter.Close = Close

-- typed: the amount box is being edited; it keeps the player's text unless
-- the amount had to be clamped.
local function SetAmount(amount, typed)
    if not S.Finite(amount) then amount = 1 end
    Splitter.amount = math.max(1, math.min(Splitter.stack, math.floor(amount)))
    Splitter.take:SetText(string.format(S.Text("Pick up %d"), Splitter.amount))
    Splitter.auto:SetText(string.format(S.Text("Auto split by %d"), Splitter.amount))
    local box = Splitter.box
    if box and (not typed or tonumber(box:GetText()) ~= Splitter.amount) then box:SetText(tostring(Splitter.amount)) end
end

-- The panel standing alone (Suite bank view) takes any amount like
-- Blizzard's split window: arrows step it and the box takes a typed number.
local function Step(button) SetAmount(Splitter.amount + button.step) end
local function Typed(box, userInput)
    if userInput and tonumber(box:GetText()) then SetAmount(tonumber(box:GetText()), true) end
end

local function Preset(button)
    SetAmount(button.half and math.floor(Splitter.stack / 2) or button.amount)
end

local function Source()
    return Splitter.owner and P.SplitInventory.Source(Splitter.owner)
end

-- Like Blizzard's Okay: the chosen amount goes onto the cursor. Placing it on
-- a bag slot closes Blizzard's split window through its own click handler.
local function Take()
    local source = Source()
    if NS.IsCombatLocked() or not source or GetCursorInfo() ~= nil or not P.SplitInventory.Available(source) then
        return
    end
    P.SplitInventory.Split(source, Splitter.amount)
    if not Splitter.attached then Close() end
end

local function Explain(reason)
    GameTooltip:SetOwner(Splitter.auto, "ANCHOR_RIGHT")
    GameTooltip:SetText(S.Text("Auto split"))
    local message = reason == "full" and S.Text("No compatible empty slots.")
        or S.Text("Choose a smaller stack size and make sure the item is unlocked, your cursor is empty and you are out of combat.")
    GameTooltip:AddLine(message, 1, 0.6, 0.2, true)
    GameTooltip:Show()
end

local function Auto()
    local started, reason = P.AutoSplit.Start(Splitter.owner, Splitter.amount)
    if not started then Explain(reason) end
end

local function AutoEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(S.Text("Auto split"))
    GameTooltip:AddLine(S.Text(
        "Split this stack into the selected amount using compatible empty slots. Stops on combat, cursor changes, a full inventory or after 128 stacks."
    ), 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

local function Button(text, width, callback)
    local button = S.CreateFrame("Button", nil, Splitter.frame, "UIPanelButtonTemplate")
    button:SetSize(width, 23)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local function Create()
    local frame = S.CreateFrame("Frame", nil, UIParent)
    Splitter.frame = frame
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetSize(260, 69)
    frame:EnableMouse(true)
    local background = S.CreateTexture(frame, nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0.06, 0.07, 0.08, 1)
    for i, amount in ipairs(PRESETS) do
        local button = Button(tostring(amount), 37, Preset)
        button:SetPoint("TOPLEFT", 7 + (i - 1) * 40, -8)
        button.amount = amount
    end
    local half = Button(S.Text("Half"), 60, Preset)
    half:SetPoint("TOPLEFT", 167, -8)
    half.half = true
    Splitter.close = Button("X", 23, Close)
    Splitter.close:SetPoint("TOPRIGHT", -7, -8)
    Splitter.take = Button("", 80, Take)
    Splitter.take:SetPoint("BOTTOMLEFT", 7, 7)
    Splitter.auto = Button("", 104, Auto)
    Splitter.auto:SetPoint("LEFT", Splitter.take, "RIGHT", 4, 0)
    Splitter.auto:SetScript("OnEnter", AutoEnter)
    Splitter.auto:SetScript("OnLeave", GameTooltip_Hide)
    -- A closure: Stop is looked up when clicked (finding 11).
    local stop = Button(S.Text("Stop"), 52, function() P.AutoSplit.Stop() end)
    stop:SetPoint("BOTTOMRIGHT", -7, 7)
    local less = Button("<", 23, Step)
    less:SetPoint("TOPLEFT", 7, -36)
    less.step = -1
    local box = S.CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    box:SetSize(52, 20)
    box:SetPoint("LEFT", less, "RIGHT", 9, 0)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(4)
    box:SetJustifyH("CENTER")
    box:SetScript("OnTextChanged", Typed)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    local more = Button(">", 23, Step)
    more:SetPoint("LEFT", box, "RIGHT", 4, 0)
    more.step = 1
    Splitter.box, Splitter.stepper = box, { less, box, more }
end

local function Show(owner, stack, attached)
    if not Splitter.frame then Create() end
    Splitter.owner, Splitter.stack, Splitter.attached = owner, math.max(1, stack), attached
    local frame = Splitter.frame
    frame:ClearAllPoints()
    if attached then
        frame:SetPoint("TOP", StackSplitFrame, "BOTTOM", 0, 20)
    else
        frame:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 4)
    end
    Splitter.close:SetShown(not attached)
    -- Attached, Blizzard's own arrows and typing set the amount.
    frame:SetHeight(attached and 69 or 97)
    for _, control in ipairs(Splitter.stepper) do control:SetShown(not attached) end
    if attached then Splitter.box:ClearFocus() end
    frame:Show()
end

-- Blizzard opened its split window (secure); the panel joins it for bag and
-- guild bank owners. Multi-stack merchant splits keep Blizzard's window alone.
local function OpenAttached()
    local owner = StackSplitFrame.owner
    if not M.active or not M.config.stackSplitter or NS.IsCombatLocked() or StackSplitFrame.minSplit ~= 1
        or not owner or not P.SplitInventory.Source(owner) then
        if Splitter.attached then Close() end
        return
    end
    Show(owner, StackSplitFrame.maxStack, true)
    SetAmount(StackSplitFrame.split)
end

-- The player's arrows and typing in Blizzard's window set the amount too.
local function NativeAmountChanged()
    if Splitter.attached and Splitter.frame:IsShown() then SetAmount(StackSplitFrame.split) end
end

local function NativeClosed()
    if Splitter.attached and not P.AutoSplit.job then Close() end
end

-- An automatic split ended: an attached panel follows Blizzard's window.
local function AutoStopped()
    if Splitter.attached and not StackSplitFrame:IsShown() then Close() end
end

-- The Suite bank view's own buttons (BankActions.lua): Blizzard's split
-- window would be opened from Suite code there, so the panel stands alone.
function Splitter.OpenFor(owner, stack)
    if not M.active or NS.IsCombatLocked() or not S.Finite(stack) or stack < 2 then return false end
    Show(owner, stack, false)
    SetAmount(1)
    return true
end

function Splitter.OwnerHidden(owner)
    if Splitter.owner == owner and not Splitter.attached then Close() end
end

function Splitter.Refresh()
    if not Splitter.hooked then
        hooksecurefunc(StackSplitFrame, "OpenStackSplitFrame", OpenAttached)
        hooksecurefunc(StackSplitFrame, "UpdateStackText", NativeAmountChanged)
        StackSplitFrame:HookScript("OnHide", NativeClosed)
        P.AutoSplit.onStop = AutoStopped
        Splitter.hooked = true
    end
    if StackSplitFrame:IsShown() then OpenAttached() end
end
