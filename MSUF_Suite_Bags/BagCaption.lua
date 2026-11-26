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
-- drawer's keyring (EquippedBags.lua), the secure button stays detached from
-- the native window. It tracks the visible minimize cell or restore tab
-- before mouse input arrives. Blizzard's list of open bags
-- (ContainerFrameSettingsManager) never comes from the Suite's code.
-- Maximize toggles full height for the side panel or fit for the Blizzard grid. Built once,
-- laid out when a window shows or moves; in combat the caption stays and
-- minimize and maximize wait for its end. Under the Gamepad UI Blizzard hides
-- its X (ContainerFrameCombinedBagsMixin:InitializeGamepad): no caption there.
local Caption = { states = setmetatable({}, { __mode = "k" }) }
P.BagCaption = Caption
local BLIZZARD_GRID = NS.BagsView.BLIZZARD_GRID

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
local visible = {}
local watchStart, watchEnd, watchScale = false, false, false
local SyncDelegate, ShowTab, SyncEvents

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
    if not owner or delegate.clicking or NS.IsCombatLocked() then return end
    delegate.owner, delegate.minimizeClick = nil, nil
    delegate:Hide()
    delegate:ClearAllPoints()
    delegate:SetAttribute("type1", nil)
    delegate:SetAttribute("clickbutton1", nil)
    Hover(owner, false)
    SyncEvents()
end

local function DelegateEnter(button)
    if button.owner then Hover(button.owner, true) end
end

local function DelegateLeave(button)
    if button.owner then Hover(button.owner, false) end
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
    local ratio = scale / parent
    return left * ratio, top * ratio, ratio
end

local function CursorOver(owner)
    local left, bottom, width, height = owner:GetScaledRect()
    local x, y = GetCursorPosition()
    if not (S.Finite(left) and S.Finite(bottom) and S.Finite(width) and S.Finite(height) and S.Finite(x) and S.Finite(y)) then
        return false
    end
    return x >= left and x <= left + width and y >= bottom and y <= bottom + height
end

-- The restore tab takes the place of the window's top left corner. While
-- Blizzard's click runs, the delegate stays where it is: PostClick ends it.
local function PreClick(button, mouseButton)
    button.clicking = true
    local owner = button.owner
    if not owner or mouseButton ~= "LeftButton" or InCombatLockdown() then return end
    local state = owner.bagCaption
    local rejects = NS.InCombat() or not owner:IsVisible() or not CursorOver(owner)
    if owner == tab and not rejects then
        -- A bag toggle can close open bags or handle a held item or modifier.
        local held, modified = CursorHasItem and CursorHasItem(), IsModifiedClick and IsModifiedClick()
        rejects = not tab.state or tab.state.frame:IsShown() or not NS.Public(held) or held
            or not NS.Public(modified) or modified or button:GetAttribute("clickbutton1") ~= Backpack()
    elseif not rejects then
        rejects = not state or not state.owned or not state.frame:IsShown() or not state.native:IsShown()
    end
    button.minimizeClick = nil
    if rejects then
        button:SetAttribute("type1", nil)
        return
    end
    if state and owner == state.minimize and state.owned and state.frame:IsShown() then
        button.minimizeClick = true
        state.tabX, state.tabY = TopLeft(state.frame)
    end
end

local function PostClick(button, mouseButton)
    button.clicking = nil
    local owner = button.owner
    local state = owner and (owner.bagCaption or owner.state)
    local minimized = mouseButton == "LeftButton" and button.minimizeClick
        and state and state.owned and P.BagsModule.active and not state.frame:IsShown()
    Detach()
    if minimized then return ShowTab(state) end
    if owner and owner == tab and (mouseButton == "RightButton" or tab.state and tab.state.frame:IsShown()) then
        tab:Hide()
    end
    if state then SyncDelegate(state) end
end

local function MouseDown(button, mouseButton)
    Press(button, true)
    if mouseButton == "LeftButton" then PreClick(button, mouseButton) end
end

local function MouseUp(button)
    Press(button, false)
    -- A release outside the button may not produce a click.
    if button.clicking then
        C_Timer.After(0, function()
            if button.clicking then
                button.minimizeClick = nil
                PostClick(button)
            end
        end)
    end
end

local function Delegate()
    if delegate then return delegate end
    local button = S.CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:EnableMouse(true)
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type1", "click")
    button:SetScript("OnEnter", DelegateEnter)
    button:SetScript("OnLeave", DelegateLeave)
    button:SetScript("OnMouseDown", MouseDown)
    button:SetScript("OnMouseUp", MouseUp)
    button:SetScript("PreClick", PreClick)
    button:SetScript("PostClick", PostClick)
    button:Hide()
    RegisterStateDriver(button, "visibility", "[combat] hide")
    delegate = button
    return button
end

-- target is the Blizzard button the delegate clicks from secure code.
local function Attach(owner, target)
    if not target or NS.Safety.IsForbidden(target) then return end
    local left, top, ratio = TopLeft(owner)
    local width, height = owner:GetWidth(), owner:GetHeight()
    if not left or not S.Finite(width) or not S.Finite(height) or width <= 0 or height <= 0 then return end
    local button = Delegate()
    local strata, level = owner:GetFrameStrata(), owner:GetFrameLevel() + 5
    width, height = width * ratio, height * ratio
    if button.owner == owner and button:IsShown() and button:GetAttribute("type1") == "click"
        and button:GetAttribute("clickbutton1") == target and button.left == left and button.top == top
        and button:GetWidth() == width and button:GetHeight() == height
        and button:GetFrameStrata() == strata and button:GetFrameLevel() == level then return true end
    button.owner = owner
    button.left, button.top = left, top
    button:SetAttribute("type1", "click")
    button:SetAttribute("clickbutton1", target)
    button:SetFrameStrata(strata)
    button:SetFrameLevel(level)
    -- A secure anchor to the bag cell would also protect the native bag.
    button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    button:SetSize(width, height)
    button:Show()
    return true
end

SyncDelegate = function(state, event)
    if not state.minimize or delegate and delegate.clicking or NS.IsCombatLocked() then return end
    if state.owned and P.BagsModule.active and not (NS.InCombat(event) or S.GamepadUI() or S.editMode) then
        if tab and tab.state == state and tab:IsVisible() and not state.frame:IsShown() then
            if Attach(tab, Backpack()) then return end
        elseif not state.minimize.bagDisabled and state.minimize:IsVisible() then
            if Attach(state.minimize, state.native) then return end
        end
    end
    Detach()
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

local function TabEnter()
    Caption.PaintTab(true)
end

local function TabLeave()
    Caption.PaintTab(false)
end

-- A click the delegate did not take: the right button dismisses the tab.
local function TabClick(button, mouseButton)
    if mouseButton == "RightButton" then button:Hide() end
end

local function TabHidden(button)
    button.state = nil
    if delegate and delegate.owner == button then Detach() end
    SyncEvents()
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
    tab:SetScript("OnShow", SyncEvents)
    tab:SetScript("OnHide", TabHidden)
    tab:Hide()
    hooksecurefunc(tab, "SetPoint", function(button)
        if button.state and button:IsVisible() then SyncDelegate(button.state) end
    end)
    if NS.MinimizedWindows then NS.MinimizedWindows.Track(tab) end
    return tab
end

ShowTab = function(state)
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
    SyncDelegate(state)
end

------------------------------------------------------------------ cells
local function SetDisabled(cell, disabled)
    if cell.bagDisabled == disabled then return end
    cell.bagDisabled = disabled
    cell:EnableMouse(not disabled and cell == cell.bagCaption.maximize)
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
    visible[state] = shown and state.close:IsVisible() or nil
    SyncEvents()
    if not shown then return SyncDelegate(state, event) end
    if state.minimize then
        local c, held = module.config, NS.InCombat(event) or S.editMode
        local panel = P.BagPresentation.IsPanel(c) and P.InventoryView.layout ~= "combat"
        local native = c.inventoryView == BLIZZARD_GRID
        local maximized = panel and c.panelFullHeight or native and module.nativeMaximized
        local kind = maximized and "restore" or "maximize"
        if state.maximize.caption.kind ~= kind then Painter().SetKind(state.maximize, kind) end
        SetDisabled(state.maximize, held or not (panel or native))
        SetDisabled(state.minimize, held or not Backpack())
    end
    if state.frame:IsVisible() then Snap(state) end
    SyncDelegate(state, event)
end

local function Maximize(cell)
    local module = P.BagsModule
    if cell.bagDisabled or not module.active or NS.InCombat() then return end
    if module.config.inventoryView == BLIZZARD_GRID then
        module:ToggleNativeMaximize()
        Caption.Sync(cell.bagCaption)
    elseif P.BagPresentation.IsPanel(module.config) then
        S.Set("bags", "panelFullHeight", not module.config.panelFullHeight)
    end
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

-- The delegate confirms its own native close in PostClick.
local function WindowHidden(frame)
    local state = states[frame]
    if not state then return end
    visible[state] = nil
    if delegate and delegate.owner and delegate.owner.bagCaption == state then Detach() end
    SyncEvents()
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
        -- The native bag header has HIGH-strata controls.
        state.minimize:SetFrameStrata("HIGH")
        state.minimize:EnableMouse(false)
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

local function MaximizedGridShown(module)
    return module.active and module.nativeMaximized and module.frame and module.frame:IsVisible()
end

local function CaptionEvent(_, event)
    local module = P.BagsModule
    local state = states[module.frame]
    local restore = tab and tab.state and tab:IsVisible() and tab.state
    if event == "UI_SCALE_CHANGED" then
        if MaximizedGridShown(module) then
            module:RefreshWindowLayout()
        else
            Caption.Moved()
        end
        if restore then SyncDelegate(restore) end
        return
    end
    -- Combat starts before lockdown. A prior locked detach may still need
    -- the exit edge even after the last window closed or the module stopped.
    if delegate then delegate.clicking = nil end
    Detach()
    if state and visible[state] then Caption.Sync(state, event) end
    if restore then SyncDelegate(restore, event) end
    SyncEvents()
end

local function Watch(event, wanted)
    if wanted then events:RegisterEvent(event) else events:UnregisterEvent(event) end
end

SyncEvents = function()
    local module = P.BagsModule
    local restore = tab and tab.state and tab:IsVisible()
    local combined = visible[states[module.frame]]
    local start = module.active and (combined or restore) or delegate and delegate.clicking or false
    local finish = start or delegate ~= nil and delegate.owner ~= nil
    -- Even when Gamepad hides the X, a visible maximized native grid must
    -- still refit on a viewport change. A closed maximized grid owns no event.
    local scale = module.active and (next(visible) ~= nil or restore or MaximizedGridShown(module)) or false
    if start == watchStart and finish == watchEnd and scale == watchScale then return end
    if not events then
        events = S.CreateFrame("Frame")
        events:SetScript("OnEvent", CaptionEvent)
    end
    if start ~= watchStart then Watch("PLAYER_REGEN_DISABLED", start) end
    if finish ~= watchEnd then Watch("PLAYER_REGEN_ENABLED", finish) end
    if scale ~= watchScale then Watch("UI_SCALE_CHANGED", scale) end
    watchStart, watchEnd, watchScale = start, finish, scale
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
    for state in pairs(visible) do
        Snap(state)
        SyncDelegate(state)
    end
end

function Caption.Refresh()
    if P.BagsModule.config.inventoryView ~= BLIZZARD_GRID then P.BagsModule.nativeMaximized = nil end
    for _, state in pairs(states) do
        Own(state, P.BagsModule.context)
        Caption.Sync(state)
    end
    Caption.PaintTab(tab and tab:IsMouseOver())
    SyncEvents()
end

-- The module stops: its context hands Blizzard's X back afterwards.
function Caption.Release()
    P.BagsModule.nativeMaximized = nil
    for _, state in pairs(states) do
        state.owned = false
        visible[state] = nil
        for _, cell in ipairs(state.cells) do cell:Hide() end
    end
    if tab then tab:Hide() end
    if delegate then delegate.clicking = nil end
    Detach()
    SyncEvents()
end
