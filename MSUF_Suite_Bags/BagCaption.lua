local _, P = ...
local NS, S = P.NS, P.Suite
local Layout = P.BagLayout

-- The Windows caption of the bag windows, as on the Blizzard windows the Skin
-- dresses: minimize, maximize and close cells with thin glyphs on whole
-- pixels, no box, a red close cell under the pointer, painted by the Suite's
-- caption painter (S.WindowCaption, MSUF_Suite/Core/WindowCaption.lua).
-- Blizzard's X keeps the close: it moves under the close cell and fades, its
-- hover and press light the cell, and its click closes the bag in Blizzard's
-- own code (ContainerFrame_OnCloseButtonClicked). Minimize closes the bag
-- through that same X from a secure click and leaves a restore tab, which
-- reopens it through Blizzard's backpack button the same way. As for the
-- drawer's keyring (EquippedBags.lua), one secure button covers the minimize
-- cell or the tab only while the pointer rests on it out of combat: no bag
-- window turns protected, and Blizzard's list of open bags
-- (ContainerFrameSettingsManager) never comes from the Suite's code.
-- Maximize turns the side panel's full screen height on and off. Built once,
-- laid out when a window shows or moves; in combat the caption stays and
-- minimize and maximize wait for its end. Under the Gamepad UI Blizzard hides
-- its X (ContainerFrameCombinedBagsMixin:InitializeGamepad): no caption there.
local Caption = { states = setmetatable({}, { __mode = "k" }) }
P.BagCaption = Caption

local CELL_W, CELL_H = 30, 24
-- How far a caption reaches in from the window's right edge: three cells or
-- the close cell alone, one pixel inside the edge.
Caption.WIDE, Caption.NARROW = 1 + 3 * CELL_W, 1 + CELL_W
-- The side panel's tools end 8 left of the caption (four 24 wide, 32 apart);
-- its heading and drag strip end 12 left of the tools.
Caption.PANEL_TOOLS = Caption.WIDE + 8
Caption.PANEL_TITLE = Caption.PANEL_TOOLS + 3 * 32 + 24 + 12
local TEXT, MUTED = { .94, .95, .98, 1 }, { .45, .48, .53, 1 }
local states, natives = Caption.states, setmetatable({}, { __mode = "k" })
local delegate, tab, events

local function Painter() return S.WindowCaption end

-- Blizzard's backpack button opens the combined bag again
-- (BaseBagSlotButtonMixin:BagSlotOnClick runs ToggleBag(0)).
local function Backpack()
    local button = _G.MainMenuBarBackpackButton
    if not button or NS.Safety.IsForbidden(button) then return nil end
    return button
end

-- The space a window's caption takes from its right edge (TitleContainer).
function Caption.Inset(combined)
    if S.GamepadUI() then return 24 end
    return combined and Caption.WIDE or Caption.NARROW
end

-- Quality of Life's buttons on a bag window's title (Delete cheapest item)
-- stay left of the caption the Suite drew there; nil: no Suite caption.
function S.BagsTitleInset(frame)
    local state = states[frame]
    if not state or not state.owned or not P.BagsModule.active then return nil end
    return Caption.Inset(state.maximize ~= nil)
end

------------------------------------------------------------------ secure delegate
local function Hover(owner, hover)
    if owner.caption then
        Painter().SetHover(owner, hover)
    elseif owner == tab then
        Caption.PaintTab(hover)
    end
end

-- In combat only the bookkeeping waits: the delegate is hidden by its state
-- driver already, and the combat end lets its points go.
local function Detach()
    local owner = delegate and delegate.owner
    if not owner or NS.IsCombatLocked() then return end
    delegate.owner = nil
    delegate:Hide()
    delegate:ClearAllPoints()
    Hover(owner, false)
end

local function DelegateEnter(button)
    if button.owner then Hover(button.owner, true) end
end

local function Press(button, down)
    local owner = button.owner
    if not owner or not owner.caption then return end
    owner.caption.down = down or nil
    Painter().Paint(owner)
end

local function TopLeft(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    local scale, parent = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (S.Finite(left) and S.Finite(top) and S.Finite(scale) and S.Finite(parent)) or parent <= 0 then return nil end
    return left * scale / parent, top * scale / parent
end

-- The restore tab takes the place of the window's top left corner. While
-- Blizzard's click runs, the delegate stays where it is: PostClick ends it.
local function PreClick(button, mouseButton)
    button.clicking = true
    local state = button.owner and button.owner.bagCaption
    if state and button.owner == state.minimize and mouseButton == "LeftButton" then
        state.minimizing = true
        state.tabX, state.tabY = TopLeft(state.frame)
    end
end

local function PostClick(button, mouseButton)
    button.clicking = nil
    local owner = button.owner
    local state = owner and owner.bagCaption
    if state then state.minimizing = nil end
    if owner and owner == tab and (mouseButton == "RightButton" or tab.state and tab.state.frame:IsShown()) then
        tab:Hide()
    end
    Detach()
end

local function Delegate()
    if delegate then return delegate end
    local button = S.CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type1", "click")
    button:SetScript("OnEnter", DelegateEnter)
    button:SetScript("OnLeave", Detach)
    button:SetScript("OnMouseDown", function(self) Press(self, true) end)
    button:SetScript("OnMouseUp", function(self) Press(self, false) end)
    button:SetScript("PreClick", PreClick)
    button:SetScript("PostClick", PostClick)
    button:Hide()
    RegisterStateDriver(button, "visibility", "[combat] hide")
    delegate = button
    return button
end

-- target is the Blizzard button the delegate clicks from secure code.
local function Attach(owner, target)
    if not target or NS.InCombat() or S.GamepadUI() or S.editMode then return end
    local button = Delegate()
    button.owner = owner
    button:SetAttribute("clickbutton1", target)
    button:SetFrameStrata(owner:GetFrameStrata())
    button:SetFrameLevel(owner:GetFrameLevel() + 5)
    button:ClearAllPoints()
    button:SetAllPoints(owner)
    button:Show()
end

------------------------------------------------------------------ restore tab
function Caption.PaintTab(hover)
    if not tab then return end
    local c = P.BagsModule.config or S.Config("bags")
    local r, g, b = S.RGB(c.backgroundColor)
    local ar, ag, ab = S.RGB(c.accentColor)
    local lift = hover and .06 or 0
    tab.fill:SetColorTexture(r + lift, g + lift, b + lift, .96)
    tab.rule:SetColorTexture(ar, ag, ab, hover and 1 or .7)
end

local function TabEnter(button)
    Caption.PaintTab(true)
    Attach(button, Backpack())
end

local function TabLeave(button)
    if not (delegate and delegate.owner == button) then Caption.PaintTab(false) end
end

-- A click the delegate did not take: the right button dismisses the tab.
local function TabClick(button, mouseButton)
    if mouseButton == "RightButton" then button:Hide() end
end

local function TabHidden(button)
    button.state = nil
    if delegate and delegate.owner == button then Detach() end
end

local function Tab()
    if tab then return tab end
    tab = S.CreateFrame("Button", nil, UIParent)
    tab:SetSize(154, 26)
    tab:SetFrameStrata("DIALOG")
    tab:SetClampedToScreen(true)
    tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tab.fill = S.CreateTexture(tab, nil, "BACKGROUND")
    tab.fill:SetAllPoints(tab)
    tab.rule = S.CreateTexture(tab, nil, "BORDER")
    tab.rule:SetPoint("BOTTOMLEFT")
    tab.rule:SetPoint("BOTTOMRIGHT")
    tab.rule:SetHeight(1)
    tab.label = P.GridView.Font(tab, 12)
    tab.label:SetPoint("LEFT", 10, 0)
    tab.label:SetPoint("RIGHT", -10, 0)
    tab.label:SetWordWrap(false)
    tab.label:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
    tab:SetScript("OnEnter", TabEnter)
    tab:SetScript("OnLeave", TabLeave)
    tab:SetScript("OnClick", TabClick)
    tab:SetScript("OnHide", TabHidden)
    tab:Hide()
    return tab
end

local function ShowTab(state)
    local button = Tab()
    button.state = state
    Caption.PaintTab(false)
    button.label:SetText(S.Text("Backpack") .. "  +")
    button:ClearAllPoints()
    if state.tabX then
        button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", state.tabX, state.tabY)
    else
        button:SetPoint("TOP", UIParent, "TOP", 0, -80)
    end
    button:Show()
end

------------------------------------------------------------------ cells
local function SetDisabled(cell, disabled)
    if cell.bagDisabled == disabled then return end
    cell.bagDisabled = disabled
    cell:EnableMouse(not disabled)
    Painter().SetHover(cell, false)
end

-- Glyph bars sit on whole screen pixels of the window's place: laid out
-- again only once the window moved or changed its scale.
local function Snap(state)
    local frame = state.frame
    local left, top, scale = frame:GetLeft(), frame:GetTop(), frame:GetEffectiveScale()
    if not (S.Finite(left) and S.Finite(top) and S.Finite(scale)) then return end
    if left == state.left and top == state.top and scale == state.scale then return end
    state.left, state.top, state.scale = left, top, scale
    for _, cell in ipairs(state.cells) do Painter().SetKind(cell, cell.caption.kind) end
end

-- event: the combat event being handled (NS.InCombat), else nil.
function Caption.Sync(state, event)
    local module = P.BagsModule
    local shown = module.active and state.owned and not S.GamepadUI() and state.native:IsShown() == true
    for _, cell in ipairs(state.cells) do cell:SetShown(shown) end
    if not shown then return end
    if state.minimize then
        local c, held = module.config, NS.InCombat(event) or S.editMode
        local panel = P.BagPresentation.IsPanel(c) and P.InventoryView.layout ~= "combat"
        local kind = panel and c.panelFullHeight and "restore" or "maximize"
        if state.maximize.caption.kind ~= kind then Painter().SetKind(state.maximize, kind) end
        SetDisabled(state.maximize, held or not panel)
        SetDisabled(state.minimize, held or not Backpack())
    end
    if state.frame:IsVisible() then Snap(state) end
end

local function Maximize(cell)
    local module = P.BagsModule
    if cell.bagDisabled or not module.active or NS.InCombat() then return end
    if P.BagPresentation.IsPanel(module.config) then S.Set("bags", "panelFullHeight", not module.config.panelFullHeight) end
end

local function MinimizeEnter(cell)
    local state = cell.bagCaption
    if cell.bagDisabled or not state.owned or not P.BagsModule.active or not Backpack() then return end
    Attach(cell, state.native)
end

local function NewCell(state, kind, frameType)
    local cell = P.ChildFrame(frameType, state.shell)
    cell.bagCaption = state
    cell:SetSize(CELL_W, CELL_H)
    Painter().Dress(cell, kind, function()
        local color = cell.bagDisabled and MUTED or TEXT
        return color[1], color[2], color[3], color[4]
    end)
    return cell
end

------------------------------------------------------------------ Blizzard's X
local function NativeHover(native, hover)
    local state = natives[native]
    if state and state.owned then Painter().SetHover(state.close, hover) end
end

local function NativePress(native, down)
    local state = natives[native]
    if not state or not state.owned then return end
    state.close.caption.down = down or nil
    Painter().Paint(state.close)
end

-- Alpha is no protected action: the faded X stays faded in combat too.
local function KeepFaded(native, alpha)
    local state = natives[native]
    if state and state.owned and alpha ~= 0 then native:SetAlpha(0) end
end

local function NativeVisibility(native)
    local state = natives[native]
    if state then Caption.Sync(state) end
end

local function HookNative(native)
    native:HookScript("OnEnter", function(self) NativeHover(self, true) end)
    native:HookScript("OnLeave", function(self) NativeHover(self, false) end)
    native:HookScript("OnMouseDown", function(self) NativePress(self, true) end)
    native:HookScript("OnMouseUp", function(self) NativePress(self, false) end)
    native:HookScript("OnShow", NativeVisibility)
    native:HookScript("OnHide", NativeVisibility)
    hooksecurefunc(native, "SetAlpha", KeepFaded)
end

-- The X keeps its click under the close cell: the whole cell closes.
local function Own(state, context)
    if state.owned then return true end
    local native, frame = state.native, state.frame
    if NS.IsCombatLocked() and not (Layout.Frame(frame) and Layout.Frame(native)) then return false end
    Layout.Anchor(context, native, "TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    Layout.Size(context, native, CELL_W, CELL_H)
    Layout.Alpha(context, native, 0)
    state.owned = true
    return true
end

------------------------------------------------------------------ windows
local function WindowShown(frame)
    local state = states[frame]
    if not state then return end
    if tab and tab.state == state and not (delegate and delegate.clicking) then tab:Hide() end
    Caption.Sync(state)
end

-- A minimize click hid the window: its tab takes the window's place.
local function WindowHidden(frame)
    local state = states[frame]
    if not state then return end
    local minimizing = state.minimizing
    state.minimizing = nil
    if minimizing and P.BagsModule.active then
        ShowTab(state)
    elseif delegate and not delegate.clicking and delegate.owner and delegate.owner.bagCaption == state then
        Detach()
    end
end

local function New(frame, t)
    local native = frame.CloseButton
    if not native or NS.Safety.IsForbidden(native) or not Painter() then return nil end
    local state = { frame = frame, shell = t.shell, native = native, cells = {} }
    state.close = NewCell(state, "close", "Frame")
    state.close:EnableMouse(false)
    state.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    state.cells[1] = state.close
    if t.combined then
        state.maximize = NewCell(state, "maximize", "Button")
        state.maximize:RegisterForClicks("LeftButtonUp")
        state.maximize:SetScript("OnClick", Maximize)
        state.maximize:SetPoint("TOPRIGHT", state.close, "TOPLEFT", 0, 0)
        state.minimize = NewCell(state, "minimize", "Button")
        state.minimize:HookScript("OnEnter", MinimizeEnter)
        state.minimize:SetPoint("TOPRIGHT", state.maximize, "TOPLEFT", 0, 0)
        state.cells[2], state.cells[3] = state.maximize, state.minimize
    end
    -- Above Blizzard's X and the title's drag strip.
    local level = math.max(native:GetFrameLevel(), frame:GetFrameLevel()) + 2
    for _, cell in ipairs(state.cells) do cell:SetFrameLevel(level) end
    natives[native] = state
    HookNative(native)
    frame:HookScript("OnShow", WindowShown)
    frame:HookScript("OnHide", WindowHidden)
    return state
end

local function CombatChanged(_, event)
    -- PLAYER_REGEN_DISABLED runs before the lockdown: the delegate lets go.
    Detach()
    for _, state in pairs(states) do Caption.Sync(state, event) end
end

local function WatchCombat()
    events = events or S.CreateFrame("Frame")
    events:SetScript("OnEvent", CombatChanged)
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- StyleWindows: t is the window's Suite style (BagWindow.lua NewWindowStyle).
function Caption.Attach(module, frame, t)
    local state = states[frame] or New(frame, t)
    if not state then return end
    states[frame] = state
    Own(state, module.context)
    Caption.Sync(state)
end

-- A window layout pass moved or scaled a window.
function Caption.Moved()
    for _, state in pairs(states) do
        if state.owned and state.close:IsVisible() then Snap(state) end
    end
end

function Caption.Refresh()
    WatchCombat()
    for _, state in pairs(states) do
        Own(state, P.BagsModule.context)
        Caption.Sync(state)
    end
    Caption.PaintTab(tab and tab:IsMouseOver())
end

-- The module stops: its context hands Blizzard's X back afterwards.
function Caption.Release()
    for _, state in pairs(states) do
        state.owned, state.minimizing = false, nil
        for _, cell in ipairs(state.cells) do cell:Hide() end
    end
    if tab then tab:Hide() end
    Detach()
    if events then events:UnregisterAllEvents() end
end
