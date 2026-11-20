local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
local D = P.Messenger
-- The whisper messenger's own window and launcher button. Every frame here
-- belongs to the Suite: no Blizzard chat frame, edit box, tab or table is
-- touched, so showing or hiding the window (also in combat) never runs
-- inside Blizzard's chat code. The reply line is a Suite edit box; its text
-- goes out through Messenger.lua's send path, never through Blizzard's chat
-- edit box, so its chatType and tell target stay untouched.
-- The messages show in one word-wrapped string of a scroll frame, built
-- again only when a line arrives in the shown tab or another tab is chosen;
-- the window holds no chat text while it is hidden. Each open tab can
-- keep its own unsent draft in session memory.
local W = {}
D.Window = W
local MODULE = "chatMessenger"
-- Twelve tabs (D.TABS_MAX) fit the list at the smallest window height (340).
local TAB_HEIGHT, TAB_GAP, LIST_WIDTH, HEADER, INPUT_HEIGHT, PAD = 20, 2, 140, 46, 24, 12
local RESTORE_TABS = 4
local Finite, PublicText = S.Finite, S.PublicText
local panel, launcher, config
local handlers = {}
local hiddenForCombat, openAfterCombat = false, false

-- Messenger.lua's actions: select, close, send, ask, closeAll.
function W.SetHandlers(actions)
    handlers = actions
end

------------------------------------------------------------------ positions
-- Window and launcher positions are per-profile module state, not settings.
local function SavedPoint(state, key)
    local point = state and state[key]
    if type(point) == "table" and Finite(point.x) and Finite(point.y) then return point end
end

local function SavePoint(frame, state, key)
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not (state and Finite(left) and Finite(bottom)) then return end
    state[key] = { x = math.floor(left + 0.5), y = math.floor(bottom + 0.5) }
end

local function BeginDrag(frame)
    frame.dragState = S.ModuleState(MODULE) or false
    frame:StartMoving()
end

local function EndDrag(frame, key)
    local state = frame.dragState
    if state == nil then return end
    frame.dragState = nil
    frame:StopMovingOrSizing()
    if key and state and state == S.ModuleState(MODULE) then SavePoint(frame, state, key) end
end

local function Place(frame, state, key, point, x, y)
    if frame.placed and frame.placementState == state then return end
    EndDrag(frame)
    frame.placed, frame.placementState = true, state
    frame:ClearAllPoints()
    local saved = SavedPoint(state, key)
    if saved then
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
    else
        frame:SetPoint(point, UIParent, point, x, y)
    end
end

------------------------------------------------------------------ widgets
local function FlatButton(parent, width, height)
    local button = S.CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button.fill = C.Fill(button, "BACKGROUND")
    button.fill:SetAllPoints(button)
    C.Tint(button.fill, "1a222b", 92)
    local hover = S.CreateTexture(button, nil, "HIGHLIGHT")
    hover:SetAllPoints(button)
    hover:SetColorTexture(0.30, 0.58, 0.82, 0.18)
    button.label = S.CreateFontString(button, nil, "ARTWORK")
    S.SetFont(button.label, nil, 12, "")
    button.label:SetPoint("LEFT", button, "LEFT", 7, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -7, 0)
    button.label:SetJustifyH("CENTER")
    button.label:SetWordWrap(false)
    return button
end

local function TabClicked(button, mouseButton)
    local tab = button.tab
    if not tab then return end
    if mouseButton == "RightButton" then
        S.ContextMenu(button, function(_, menu)
            local action = menu:CreateButton(S.Text(tab.pinned and "Unpin conversation" or "Pin conversation"),
                function() D.TogglePin(tab) end)
            action:SetEnabled(D.CanPin(tab))
        end)
        return
    end
    handlers.select(tab)
end

local function TabClosed(close)
    local tab = close:GetParent().tab
    if tab then handlers.close(tab) end
end

local function TabButton(index)
    local button = FlatButton(panel.list, LIST_WIDTH, TAB_HEIGHT)
    button:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 0, -(index - 1) * (TAB_HEIGHT + TAB_GAP))
    button.label:SetJustifyH("LEFT")
    button.label:SetPoint("RIGHT", button, "RIGHT", -24, 0)
    button.marker = C.Fill(button, "ARTWORK")
    button.marker:SetPoint("TOPLEFT")
    button.marker:SetPoint("BOTTOMLEFT")
    button.marker:SetWidth(2)
    local close = FlatButton(button, 18, 18)
    close:SetPoint("RIGHT", button, "RIGHT", -2, 0)
    close.label:SetText("x")
    close:SetScript("OnClick", TabClosed)
    button.close = close
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", TabClicked)
    panel.tabs[index] = button
    return button
end

------------------------------------------------------------------ painting
local function ArchiveRecording()
    local chat = S.Config("chat")
    return type(chat) == "table" and chat.enabled == true and chat.saveHistory == true
        and chat.historyWhispers ~= false and chat.historyConversations == true
end

local function StatusText()
    if D.nativeOnly > 0 then
        return S.Text("Restricted whispers shown only in Blizzard chat: %d"):format(D.nativeOnly)
    end
    if NS.ChatLocked() then return S.Text("Chat is restricted here: replies wait until it is allowed again.") end
    local tab = D.selected
    if tab and tab.kind == "bnet" then return S.Text("Battle.net conversations last for this session.") end
    if config and config.showArchive ~= false and not ArchiveRecording() then
        return S.Text("Turn on Archive whispers by character name in Chat tools to keep conversations.")
    end
    return ""
end

local function PaintTab(button, tab)
    button.tab = tab
    local label = tab.label or ""
    if tab.pinned then label = "|TInterface\\Minimap\\Tracking\\Target:12:12|t " .. label end
    if tab.unread > 0 then label = label .. " |cffffd100(" .. tab.unread .. ")|r" end
    button.label:SetText(label)
    local selected = tab == D.selected
    C.Tint(button.fill, selected and "2a3a4a" or "1a222b", 92)
    if tab.unread > 0 then
        C.Tint(button.marker, "ffd100", 100)
    else
        C.Tint(button.marker, "57c7df", selected and 100 or 0)
    end
    button:Show()
end

local function RenderTabs()
    for index, tab in ipairs(D.tabs) do PaintTab(panel.tabs[index] or TabButton(index), tab) end
    for index = #D.tabs + 1, #panel.tabs do
        local button = panel.tabs[index]
        button.tab = nil
        button:Hide()
    end
end

local function EmptyText(tab)
    if tab then return "" end
    return S.Text("No conversation yet. Whispers you send or receive appear here; use New to write to a character.")
end

-- Follows the newest line unless the player scrolled up in the same tab.
local function RenderMessages()
    local scroll, tab = panel.scroll, D.selected
    local range, current = scroll:GetVerticalScrollRange(), scroll:GetVerticalScroll()
    local follow = panel.renderedTab ~= tab or not (Finite(range) and Finite(current)) or current >= range - 4
    local parts = {}
    if tab then
        for index, entry in ipairs(tab.lines) do parts[index] = entry.text end
    end
    panel.text:SetText(#parts > 0 and table.concat(parts, "\n") or EmptyText(tab))
    local width = scroll:GetWidth()
    if Finite(width) and width > 40 then
        panel.child:SetWidth(width)
        panel.text:SetWidth(width - 6)
    end
    local height = panel.text:GetStringHeight()
    panel.child:SetHeight(Finite(height) and math.max(1, height + 6) or 1)
    scroll:UpdateScrollChildRect()
    if follow then
        local newest = scroll:GetVerticalScrollRange()
        if Finite(newest) then scroll:SetVerticalScroll(newest) end
    end
    panel.renderedTab = tab
end

local function SetDraftTab(tab)
    local old, input = panel.inputTab, panel.input
    if old == tab then return end
    if old and D.byKey[old.key] == old then old.draft = PublicText(input:GetText()) end
    panel.inputTab = tab
    local draft = tab and tab.draft
    if tab then tab.draft = nil end
    input:SetText(draft or "")
end

local function RenderInput()
    local tab = D.selected
    SetDraftTab(tab)
    local hint = tab and S.Text("Reply to %s"):format(tab.label or "") or S.Text("Open a conversation first")
    panel.input.Instructions:SetText(hint)
end

local function LauncherText()
    local count = D.TotalUnread() + D.nativeOnly
    local text = S.Text("Whispers")
    if count > 0 then text = text .. " |cffffd100" .. count .. "|r" end
    return text, count
end

function W.UpdateLauncher()
    if not launcher or not launcher:IsShown() then return end
    local text, count = LauncherText()
    launcher.label:SetText(text)
    local width = launcher.label:GetStringWidth()
    if Finite(width) then launcher:SetWidth(math.max(60, math.ceil(width) + 18)) end
    C.Tint(launcher.fill, count > 0 and "3a2f12" or "1a222b", 92)
end

function W.IsShown()
    return panel ~= nil and panel:IsShown()
end

function W.Refresh()
    W.UpdateLauncher()
    if not W.IsShown() then return end
    local unread = D.TotalUnread()
    local title = S.Text("Whispers")
    panel.heading:SetText(unread > 0 and title .. " |cffffd100(" .. unread .. ")|r" or title)
    panel.status:SetText(StatusText())
    RenderTabs()
    RenderMessages()
    RenderInput()
end
D.Changed = W.Refresh

------------------------------------------------------------------ window
local function Sent(box)
    local tab = panel.inputTab
    if not tab or not W.IsShown() then return end
    local text = PublicText(box:GetText())
    if not text or not handlers.send(text, tab) then return end
    if panel.inputTab == tab and PublicText(box:GetText()) == text then
        box:SetText("")
    elseif tab.draft == text then
        tab.draft = nil
    end
end

local function CreateInput()
    local input = S.CreateFrame("EditBox", nil, panel, "InputBoxInstructionsTemplate")
    input:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD + LIST_WIDTH + 16, PAD)
    input:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD - 4, PAD)
    input:SetHeight(INPUT_HEIGHT)
    input:SetAutoFocus(false)
    -- A whisper carries at most 255 bytes, as Blizzard's own chat line.
    input:SetMaxBytes(256)
    input:SetScript("OnEnterPressed", Sent)
    input:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    local bridge = NS.HostBridge
    bridge.MenuEditBox(input)
    panel.input = input
end

local function CreateMessages()
    local scroll = S.CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel.list, "TOPRIGHT", 12, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, PAD + INPUT_HEIGHT + 10)
    local child = S.CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    local text = S.CreateFontString(child, nil, "ARTWORK")
    S.SetFont(text, nil, 12, "")
    text:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -2)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    text:SetSpacing(2)
    scroll:SetScrollChild(child)
    panel.scroll, panel.child, panel.text = scroll, child, text
end

local function HeaderButton(label, x, width, action)
    local button = FlatButton(panel, width, 22)
    button:SetPoint("TOPRIGHT", panel, "TOPRIGHT", x, -11)
    button.label:SetText(S.Text(label))
    button:SetScript("OnClick", action)
    return button
end

-- The player's unsent draft stays; the shown conversation does not.
local function WindowHidden()
    EndDrag(panel, "window")
    panel.input:ClearFocus()
    SetDraftTab(nil)
    panel.text:SetText("")
    panel.renderedTab = nil
end

local function CreateWindow()
    panel = S.QoLWindow(480, 360, "", 14, true)
    panel:SetFrameStrata("HIGH")
    panel.tabs = {}
    panel.heading = S.QoLLabel(panel, "Whispers", 14)
    panel.heading:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
    panel.status = S.QoLLabel(panel, "", 11)
    panel.status:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -32)
    panel.status:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -32)
    panel.status:SetJustifyH("LEFT")
    panel.status:SetWordWrap(false)
    panel.status:SetTextColor(0.74, 0.81, 0.90)
    panel.list = S.CreateFrame("Frame", nil, panel)
    panel.list:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -HEADER - 6)
    panel.list:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, PAD)
    panel.list:SetWidth(LIST_WIDTH)
    CreateMessages()
    CreateInput()
    HeaderButton("New", -46, 58, function() handlers.ask() end)
    HeaderButton("Close all", -110, 76, function() handlers.closeAll() end)
    panel.close:SetScript("OnClick", function() W.Hide() end)
    panel.dragHandle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -194, 0)
    panel.dragHandle:SetScript("OnDragStart", function() BeginDrag(panel) end)
    panel.dragHandle:SetScript("OnDragStop", function() EndDrag(panel, "window") end)
    panel:SetScript("OnShow", W.Refresh)
    panel:SetScript("OnHide", WindowHidden)
    panel:Hide()
end

------------------------------------------------------------------ launcher
local function LauncherTip()
    local lines = { S.Text("Whisper messenger"), S.Text("Click to open or close. Shift-drag to move.") }
    if D.nativeOnly > 0 then
        lines[3] = S.Text("Restricted whispers shown only in Blizzard chat: %d"):format(D.nativeOnly)
    end
    return table.concat(lines, "\n")
end

local function LauncherDrag(button)
    local shift = IsShiftKeyDown()
    if S.Public(shift) and shift == true then BeginDrag(button) end
end

local function CreateLauncher()
    launcher = FlatButton(UIParent, 80, 22)
    launcher:SetFrameStrata("MEDIUM")
    launcher:SetMovable(true)
    launcher:SetClampedToScreen(true)
    launcher:RegisterForDrag("LeftButton")
    launcher:SetScript("OnDragStart", LauncherDrag)
    launcher:SetScript("OnDragStop", function(button) EndDrag(button, "launcher") end)
    launcher:SetScript("OnClick", function() W.Toggle() end)
    launcher:SetScript("OnEnter", function(button) C.ShowTooltip(button, LauncherTip()) end)
    launcher:SetScript("OnLeave", function(button) C.HideTooltip(button) end)
end

------------------------------------------------------------------ visibility
function W.Apply(settings)
    config = settings
    local state = S.ModuleState(MODULE)
    if settings.launcher and not launcher then CreateLauncher() end
    if launcher then
        Place(launcher, state, "launcher", "BOTTOMLEFT", 14, 236)
        if settings.launcher then
            launcher:Show()
        else
            EndDrag(launcher, "launcher")
            launcher:Hide()
        end
    end
    if panel then
        Place(panel, state, "window", "CENTER", 0, 0)
        panel:SetSize(settings.width, settings.height)
        S.SetFont(panel.text, nil, settings.fontSize, "")
    end
    W.Refresh()
end

function W.Show()
    if not config then return end
    if not panel then
        CreateWindow()
        W.Apply(config)
    end
    hiddenForCombat, openAfterCombat = false, false
    D.RestoreRecent(RESTORE_TABS)
    if not D.selected then D.selected = D.tabs[1] end
    D.Seed(D.selected)
    D.MarkRead(D.selected)
    D.nativeOnly = 0
    if W.IsShown() then W.Refresh() else panel:Show() end
end

-- The player's own close: nothing comes back after combat.
function W.Hide()
    hiddenForCombat, openAfterCombat = false, false
    if panel then panel:Hide() end
    W.UpdateLauncher()
end

function W.Toggle()
    if W.IsShown() then W.Hide() else W.Show() end
end

function W.FocusInput()
    if W.IsShown() and D.selected then panel.input:SetFocus() end
end

-- Combat start hides an open window; it returns when combat ends, as does
-- one a new whisper asked to open meanwhile. Unread lines keep counting on
-- the launcher.
function W.CombatStarted(hide)
    if hide and W.IsShown() then
        panel:Hide()
        hiddenForCombat = true
    end
end

function W.OpenAfterCombat()
    openAfterCombat = true
end

function W.CombatEnded()
    local show = hiddenForCombat or openAfterCombat
    hiddenForCombat, openAfterCombat = false, false
    if show and not W.IsShown() then W.Show() end
end

function W.Release()
    hiddenForCombat, openAfterCombat = false, false
    if panel then
        panel:Hide()
        panel.input:SetText("")
        panel.placed, panel.placementState = nil, nil
    end
    if launcher then
        EndDrag(launcher)
        C.HideTooltip(launcher)
        launcher:Hide()
        launcher.placed, launcher.placementState = nil, nil
    end
    config = nil
end
