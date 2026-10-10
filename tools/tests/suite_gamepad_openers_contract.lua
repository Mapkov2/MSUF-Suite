-- WoW Forever's Gamepad UI: Blizzard's frame controls manager
-- (Blizzard_GamepadSharedUtility/FrameControlsManager.lua) follows every
-- Blizzard panel (ShowUIPanel's BroadcastShowUIPanelEvent), context menu
-- (MenuProxy.OnShow) and static popup (StaticPopupGamepad.lua PopupOpened)
-- inside the call that opens it. Opened from addon code, its focus and
-- binding state is written tainted and the gamepad's protected calls are
-- blocked (SetPreferredGamepadInteractTarget, CastSpellBookItem). This
-- contract runs the Suite's openers through the minimap world (clientSecurity)
-- with Retail, Forever and Forever's Gamepad UI side by side:
--   * under the Gamepad UI no Suite code calls ShowUIPanel, HideUIPanel,
--     MenuUtil.CreateContextMenu, StaticPopup_Show* or the Toggle* openers;
--     windows open through secure clicks on Blizzard's own buttons, which
--     the Gamepad UI keeps hidden (MicroMenu:Hide(), BagsBar:Hide());
--   * menus and questions show in the Suite's own list with the same
--     entries and callbacks;
--   * Retail and Forever without the Gamepad UI keep their paths.
-- Usage: lua suite_gamepad_openers_contract.lua <root> [case]
local root = assert(arg[1], "repository root required")
local selected = arg[2]
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")

local function Case(name, callback)
    if not selected or selected == name then
        callback()
        print(name .. " passed")
    end
end

-- The client's EditBox and FontString calls the Suite's list uses, added to
-- the harness world's frame and region classes.
local function Extend(W)
    local frame = W.New("Frame", nil, W.UIParent)
    local F = getmetatable(frame).__index
    local R = getmetatable(frame:CreateTexture()).__index
    function R:SetFormattedText(format, ...) self.text = format:format(...) end
    function R:GetStringHeight() return 14 end
    function F:SetText(value) self.text = value end
    function F:GetText() return self.text end
    function F:SetAutoFocus(value) self.autoFocus = value end
    function F:SetMaxLetters(value) self.maxLetters = value end
    function F:SetFocus() self.focused = true end
    function F:ClearFocus() self.focused = false end
    function F:SetNumeric(value) self.numeric = value end
    -- ScrollFrame: the range is the scroll child's height beyond the frame's.
    function F:SetScrollChild(child) self.scrollChild = child end
    function F:GetScrollChild() return self.scrollChild end
    function F:SetVerticalScroll(value) self.verticalScroll = value end
    function F:GetVerticalScroll() return self.verticalScroll or 0 end
    function F:GetVerticalScrollRange()
        return math.max(0, (self.scrollChild and self.scrollChild.height or 0) - self.height)
    end
end

-- Classic MSUF's pad navigation on Forever (Game/Forever/PadNavigation.lua
-- there, MSUF_PadNavigation): Attach and Activate stack a window; the pad
-- is captured only for the window on top, out of combat, while the Gamepad
-- UI is on and no Blizzard panel shows SmartNavigation (UpdateCapture, which
-- its poll repeats; nav.Poll here). Back runs a window's Close.
local function PadNavigation(world)
    local nav = { scopes = {}, attached = {}, capturing = false }
    local function Remove(frame)
        for index = #nav.scopes, 1, -1 do
            if nav.scopes[index] == frame then table.remove(nav.scopes, index) end
        end
    end
    function nav.Poll()
        local top, smart = nav.scopes[#nav.scopes], world.G.SmartNavigation
        nav.capturing = top ~= nil and not world.combat and world.gamepad == true
            and not (smart and smart:IsShown())
    end
    function nav.Attach(frame)
        if nav.attached[frame] then return end
        nav.attached[frame] = true
        frame:HookScript("OnHide", function() nav.Release(frame) end)
    end
    function nav.Activate(frame)
        if not frame:IsShown() or world.gamepad ~= true then return end
        Remove(frame)
        nav.scopes[#nav.scopes + 1] = frame
        nav.Poll()
    end
    function nav.Release(frame)
        Remove(frame)
        nav.Poll()
    end
    function nav.IsCapturing() return nav.capturing end
    function nav.Top() return nav.capturing and nav.scopes[#nav.scopes] or nil end
    function nav.Back()
        local top = nav.Top()
        if top and top.Close then top:Close() elseif top then top:Hide() end
    end
    return nav
end

-- Blizzard's CloseSpecialWindows (UIParentPanelManager.lua), which Escape
-- runs through securecall: hides each shown frame named in UISpecialFrames.
local function CloseSpecialWindows(W)
    local found
    for _, name in ipairs(W.G.UISpecialFrames) do
        local frame = W.G[name]
        if frame and frame:IsShown() then
            frame:Hide()
            found = true
        end
    end
    return found
end

-- Blizzard's openers record each call and whether it came from secure code
-- (W.secure: a secure click's own handler) or from the Suite's.
local function World(client, gamepad, fixture)
    local W = H.New(root, client, { clientSecurity = true, beforeModules = function(world)
        local G = world.G
        world.opened = {}
        local function Record(name)
            return function(...)
                world.opened[#world.opened + 1] = { name = name, secure = world.secure, args = { ... } }
            end
        end
        for _, name in ipairs({ "OpenAllBags", "ToggleCalendar", "ToggleTimeManager", "ToggleWorldMap",
            "ToggleCharacter", "ToggleProfessionsBook", "ToggleQuestLog", "ToggleEncounterJournal",
            "OpenQuestLog", "QuestMapFrame_OpenToQuestDetails", "OpenDeathRecapUI",
            "StaticPopup_ShowCustomGenericConfirmation", "StaticPopup_Hide" }) do
            G[name] = Record(name)
        end
        G.StaticPopup_Show = function(...)
            Record("StaticPopup_Show")(...)
            return { GetEditBox = function() return {} end }
        end
        G.MenuUtil = { CreateContextMenu = Record("MenuUtil.CreateContextMenu") }
        G.MenuResponse = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 }
        G.YES, G.NO, G.DONE, G.CANCEL = "Yes", "No", "Okay", "Cancel"
        G.SOUNDKIT = { IG_MAINMENU_OPEN = 850, IG_MAINMENU_QUIT = 851 }
        G.PlaySound = function() end
        G.GameMenuFrame = world.New("Frame", "GameMenuFrame", world.UIParent)
        G.GameMenuFrame:Hide()
        -- MainActionBar_InitializeGamepad hides MicroMenu and BagsBar; their
        -- buttons stay shown inside them.
        local micro = world.New("Frame", "MicroMenu", world.UIParent)
        local bags = world.New("Frame", "BagsBar", world.UIParent)
        for index, name in ipairs({ "CharacterMicroButton", "ProfessionMicroButton", "QuestLogMicroButton",
            "EJMicroButton", "GuildMicroButton", "MainMenuMicroButton" }) do
            local button = world.New("Button", name, micro)
            button.layoutIndex = index
            button.scripts.OnClick = Record(name .. ":Click")
        end
        world.New("Button", "MainMenuBarBackpackButton", bags).scripts.OnClick = Record("Backpack:Click")
        if client == "Forever" then
            G.InputUtil = { IsGamepadUIEnabled = function() return world.gamepad == true end }
            world.padNavigation = PadNavigation(world)
            G.MSUF_PadNavigation = world.padNavigation
        end
        G.UISpecialFrames = {}
        world.gamepad = gamepad
        world.micro, world.bags = micro, bags
        if fixture then fixture(world) end
    end })
    Extend(W)
    for _, name in ipairs({ "GameTimeFrame", "TimeManagerClockButton" }) do
        W.G[name].scripts.OnClick = function()
            W.opened[#W.opened + 1] = { name = name .. ":Click", secure = W.secure }
        end
    end
    W.cluster.ZoneTextButton.scripts.OnClick = function()
        W.opened[#W.opened + 1] = { name = "ZoneTextButton:Click", secure = W.secure }
    end
    if gamepad then
        W.micro:Hide()
        W.bags:Hide()
    end
    return W
end

-- Names of the calls a world recorded since index from (default all).
local function Calls(W, from)
    local names = {}
    for i = from or 1, #W.opened do names[#names + 1] = W.opened[i].name end
    return table.concat(names, ",")
end

-- The calls the Suite made from its own (insecure) code.
local function InsecureCalls(W, from)
    local names = {}
    for i = from or 1, #W.opened do
        if not W.opened[i].secure then names[#names + 1] = W.opened[i].name end
    end
    for _, call in ipairs(W.panelCalls) do
        if not call.secure then names[#names + 1] = (call.shown and "ShowUIPanel:" or "HideUIPanel:") .. tostring(call.frame.name) end
    end
    return table.concat(names, ",")
end

Case("core", function()
    -- Retail: no Gamepad UI exists; every path stays as it was.
    local W = World("Mainline", false)
    local S = W.S
    assert(S.PanelButton("character") == W.G.CharacterMicroButton, "Retail lost the character button")
    W.micro:Hide()
    assert(S.PanelButton("character") == nil, "Retail accepted a micro button that is not visible")
    for _, panel in ipairs({ "bags", "calendar", "clock", "professions", "questLog", "journal" }) do
        assert(S.PanelButton(panel) == nil, "Retail gained a Gamepad UI button for " .. panel)
    end
    S.TogglePanel("character")
    assert(#W.panelCalls == 1 and W.panelCalls[1].frame == W.G.CharacterFrame, "Retail TogglePanel stopped opening")
    S.ToggleGameMenu()
    assert(#W.panelCalls == 2 and W.panelCalls[2].frame == W.G.GameMenuFrame, "Retail game menu stopped opening")
    local list = {}
    local count = S.MicroMenuEntries(list, true)
    assert(list[count].action and list[count].enabled, "Retail game menu row was switched off")
    local retail = W

    -- Forever without the Gamepad UI: as Retail.
    W = World("Forever", false)
    S = W.S
    assert(S.PanelButton("bags") == nil, "Forever's mouse UI took a Gamepad UI path")
    S.TogglePanel("worldMap")
    assert(#W.panelCalls == 1 and W.panelCalls[1].frame == W.G.WorldMapFrame, "Forever TogglePanel stopped opening")
    local mouse = W

    -- Forever's Gamepad UI: the hidden micro menu's buttons count, Blizzard's
    -- buttons stand in for the Suite's own openers, and nothing opens from
    -- Suite code.
    W = World("Forever", true)
    S = W.S
    assert(not W.G.CharacterMicroButton:IsVisible(), "fixture: the Gamepad UI hides the micro menu")
    local expected = { character = "CharacterMicroButton", bags = "MainMenuBarBackpackButton",
        calendar = "GameTimeFrame", clock = "TimeManagerClockButton", professions = "ProfessionMicroButton",
        questLog = "QuestLogMicroButton", journal = "EJMicroButton", currency = "CharacterMicroButton" }
    W.G.CharacterFrameTab3 = nil
    for panel, name in pairs(expected) do
        assert(S.PanelButton(panel) == W.G[name], "Gamepad UI button for " .. panel .. " is wrong")
    end
    assert(S.PanelButton("worldMap") == W.cluster.ZoneTextButton, "the zone text button no longer opens the map")
    W.cluster.ZoneTextButton = nil
    assert(S.PanelButton("worldMap") == W.G.QuestLogMicroButton, "a missing zone text button left no map button")
    W.G.ProfessionMicroButton:Disable()
    assert(S.PanelButton("professions") == nil, "a disabled Blizzard button was offered")
    S.TogglePanel("character")
    S.TogglePanel("worldMap")
    S.ToggleGameMenu()
    assert(#W.panelCalls == 0, "the Gamepad UI ran Blizzard's panel manager from Suite code")
    list = {}
    count = S.MicroMenuEntries(list, true)
    assert(list[count].action == S.ToggleGameMenu and list[count].enabled == false,
        "the plain game menu row stayed usable under the Gamepad UI")
    assert(list[1].button == W.G.CharacterMicroButton and list[1].enabled, "hidden micro buttons left the micro menu")

    -- The shared predicates the other places ask.
    assert(retail.S.GamepadUI() == false and mouse.S.GamepadUI() == false, "a client without it reported a Gamepad UI")
    assert(S.GamepadUI() == true, "Forever's Gamepad UI was not recognised")
    assert(S.CanOpenNativeWindow() == false, "the Gamepad UI allowed Suite code to open windows")
    W.gamepad = false
    assert(S.CanOpenNativeWindow() == true, "leaving the Gamepad UI kept the openers off")
    W.SetCombat(true)
    assert(S.CanOpenNativeWindow() == false, "combat lockdown allowed Suite code to open windows")
end)

-- A generator as the Suite's menus write it (Specialization.lua, Menus.lua).
local function Generator(log)
    return function(owner, root, extra)
        log.owner, log.extra = owner, extra
        root:CreateTitle("Title")
        root:CreateButton("Plain", function(data) log.plain = data end, "plain-data")
        local off = root:CreateButton("Off", function() log.off = true end)
        off:SetEnabled(false)
        root:CreateDivider()
        local sub = root:CreateButton("Submenu")
        sub:CreateRadio("Radio", function(data) return log.radio == data end, function(data) log.radio = data end, 7)
        root:CreateCheckbox("Check", function() return log.check == true end, function() log.check = not log.check end)
        root:SetScrollMode(200)
        root:CreateButton("Stay", function() log.stay = (log.stay or 0) + 1; return log.refresh end)
    end
end

local function Row(panel, text)
    for _, row in ipairs(panel.rows) do
        if row.shown and row.label.text and row.label.text:find(text, 1, true) then return row end
    end
end

Case("questions", function()
    -- Retail and Forever's mouse UI keep Blizzard's dialogs.
    for _, client in ipairs({ "Mainline", "Forever" }) do
        local W = World(client, false)
        W.S.Confirm("key", { text = "%s?", text_arg1 = "Reset", callback = function() end })
        assert(W.opened[#W.opened].name == "StaticPopup_ShowCustomGenericConfirmation", client .. " confirmation moved")
        W.S.AskText("ask", { text = "Name", callback = function() end })
        assert(W.opened[#W.opened].name == "StaticPopup_Show", client .. " input box moved")
    end

    -- The Gamepad UI: the Suite's own list, Blizzard's answers.
    local W = World("Forever", true)
    local S = W.S
    local answers = {}
    S.Confirm("key", { text = "%s?", text_arg1 = "Reset", acceptText = "Do it",
        callback = function(...) answers[#answers + 1] = { "yes", select("#", ...) } end,
        cancelCallback = function() answers[#answers + 1] = { "no" } end })
    assert(InsecureCalls(W) == "", "the Gamepad UI question ran Blizzard code: " .. InsecureCalls(W))
    local question
    for _, frame in ipairs(W.frames) do
        if frame.Answer and frame.shown then question = frame end
    end
    assert(question and question.text.text == "Reset?", "the question text is wrong")
    assert(Row(question, "Do it") and Row(question, "No"), "the answer labels are wrong")
    W.Click(Row(question, "Do it"))
    assert(#answers == 1 and answers[1][1] == "yes" and not question.shown, "accepting did not answer once")
    S.Confirm("key", { text = "Again", callback = function() answers[#answers + 1] = { "yes" } end,
        cancelCallback = function() answers[#answers + 1] = { "no" } end })
    question:Close()
    assert(#answers == 2 and answers[2][1] == "no" and not question.shown, "B did not decline")
    S.Confirm("key", { text = "Hidden", callback = function() answers[#answers + 1] = { "yes" } end })
    S.HideQuestion("key")
    assert(#answers == 2 and not question.shown, "S.HideQuestion answered the question")
    local typed, hidden
    local dialog = S.AskText("ask", { text = "Name %s", text_arg1 = "it", maxLetters = 12,
        callback = function(text) typed = text end }, function(frame) hidden = frame end)
    assert(dialog == question and dialog:GetEditBox() == question.edit and question.edit.shown
        and question.edit.maxLetters == 12, "the input question lost its edit box")
    W.Click(Row(question, "Okay"))
    assert(typed == nil and question.shown, "an empty answer was accepted")
    dialog:GetEditBox():SetText("Profile")
    W.Click(Row(question, "Okay"))
    assert(typed == "Profile" and hidden == question and not question.shown, "the typed answer or onHide was lost")
    assert(InsecureCalls(W) == "", "answering ran Blizzard code: " .. InsecureCalls(W))

    -- The pad reaches the question through the host's navigation; B declines.
    local nav = W.padNavigation
    S.Confirm("key", { text = "Pad", callback = function() answers[#answers + 1] = { "yes" } end,
        cancelCallback = function() answers[#answers + 1] = { "no" } end })
    assert(nav.attached[question] and nav.Top() == question, "the pad's navigation does not hold the question")
    nav.Back()
    assert(#answers == 3 and answers[3][1] == "no" and not question.shown and nav.Top() == nil,
        "the pad's B did not decline the question or the navigation kept it")
    -- Escape closes it in every case, as Blizzard's dialog (hideOnEscape):
    -- Blizzard's CloseSpecialWindows hides it, and that declines it.
    S.Confirm("key", { text = "Escape", callback = function() answers[#answers + 1] = { "yes" } end,
        cancelCallback = function() answers[#answers + 1] = { "no" } end })
    local listed
    for _, name in ipairs(W.G.UISpecialFrames) do listed = listed or W.G[name] == question end
    assert(listed, "Escape cannot close the pad question (not in UISpecialFrames)")
    assert(CloseSpecialWindows(W) and #answers == 4 and answers[4][1] == "no" and not question.shown,
        "Escape did not decline the pad question")
    -- A new question declines the one it replaces: its caller is not left waiting.
    S.Confirm("first", { text = "First", callback = function() answers[#answers + 1] = { "first yes" } end,
        cancelCallback = function() answers[#answers + 1] = { "first no" } end })
    S.Confirm("second", { text = "Second", callback = function() answers[#answers + 1] = { "second yes" } end,
        cancelCallback = function() answers[#answers + 1] = { "second no" } end })
    assert(#answers == 5 and answers[5][1] == "first no" and question.shown and question.text.text == "Second",
        "the replaced question was never answered")
    S.HideQuestion("first")
    assert(question.shown and #answers == 5, "closing the replaced question's key closed the newer one")
    -- Hiding the whole UI (Alt+Z) keeps the question unanswered, as Blizzard's dialog.
    W.UIParent:Hide()
    W.UIParent:Show()
    assert(question.shown and #answers == 5, "hiding the UI answered the question")
    -- A question that replaces another while the UI is hidden declines it
    -- too: Hide fires no OnHide on a frame that is not visible.
    W.UIParent:Hide()
    S.Confirm("third", { text = "Third", callback = function() answers[#answers + 1] = { "third yes" } end,
        cancelCallback = function() answers[#answers + 1] = { "third no" } end })
    W.UIParent:Show()
    assert(#answers == 6 and answers[6][1] == "second no" and question.shown and question.text.text == "Third",
        "a question replaced while the UI was hidden was never answered")
    -- S.HideQuestion closes it unanswered, also while the UI is hidden, and
    -- still undoes the caller's presets (onHide).
    W.UIParent:Hide()
    S.HideQuestion("third")
    W.UIParent:Show()
    assert(not question.shown and #answers == 6, "S.HideQuestion answered the question")
    local undone
    S.AskText("preset", { text = "Preset", callback = function() end }, function() undone = true end)
    W.UIParent:Hide()
    S.HideQuestion("preset")
    W.UIParent:Show()
    assert(undone and not question.shown and question.edit.text == "",
        "closing a question while the UI was hidden kept the caller's presets")

    -- A Blizzard panel holding SmartNavigation keeps the pad (PadNavigation.lua
    -- refuses to capture then): the question waits on top and Escape still
    -- declines it; once the panel closes the pad reaches it.
    local smart = W.New("Frame", "SmartNavigation", W.UIParent)
    S.Confirm("key", { text = "Waiting", callback = function() answers[#answers + 1] = { "yes" } end,
        cancelCallback = function() answers[#answers + 1] = { "no" } end })
    assert(question.shown and nav.scopes[#nav.scopes] == question and not nav.IsCapturing(),
        "fixture: the host captured the pad while SmartNavigation showed")
    smart:Hide()
    nav.Poll()
    assert(nav.Top() == question, "the waiting question did not take the pad once SmartNavigation closed")
    smart:Show()
    nav.Poll()
    assert(CloseSpecialWindows(W) and answers[#answers][1] == "no" and not question.shown and #nav.scopes == 0,
        "Escape did not decline the question while SmartNavigation held the pad")
    assert(InsecureCalls(W) == "", "the pad question ran Blizzard code: " .. InsecureCalls(W))

    -- A host without the pad's navigation (Classic MSUF before it): nothing
    -- could reach the Suite's list, so Blizzard's dialogs stay, as before.
    W = World("Forever", true, function(world) world.G.MSUF_PadNavigation = nil end)
    W.S.Confirm("key", { text = "Old host", callback = function() end })
    assert(W.opened[#W.opened].name == "StaticPopup_ShowCustomGenericConfirmation",
        "a host without pad navigation lost Blizzard's confirmation")
    W.S.AskText("ask", { text = "Name", callback = function() end })
    assert(W.opened[#W.opened].name == "StaticPopup_Show", "a host without pad navigation lost Blizzard's input box")
end)

Case("menus", function()
    -- Retail and Forever's mouse UI keep Blizzard's context menu.
    for _, client in ipairs({ "Mainline", "Forever" }) do
        local W = World(client, false)
        local owner = W.New("Button", nil, W.UIParent)
        local generator = Generator({})
        W.S.ContextMenu(owner, generator, "extra")
        local call = W.opened[#W.opened]
        assert(call.name == "MenuUtil.CreateContextMenu" and call.args[1] == owner and call.args[2] == generator
            and call.args[3] == "extra", client .. " no longer opens Blizzard's context menu")
    end

    local W = World("Forever", true)
    local S = W.S
    local log = { refresh = W.G.MenuResponse.Refresh }
    local owner = W.New("Button", nil, W.UIParent)
    local panel = assert(S.ContextMenu(owner, Generator(log), "extra"), "the Gamepad UI opened no Suite menu")
    assert(InsecureCalls(W) == "", "the Gamepad UI menu ran Blizzard code: " .. InsecureCalls(W))
    assert(log.owner == owner and log.extra == "extra", "the generator lost its owner or arguments")
    assert(panel.shown and panel.events.GLOBAL_MOUSE_DOWN, "the menu list did not show or watch clicks away")
    assert(Row(panel, "Title") and not Row(panel, "Title").enabled, "a title became clickable")
    assert(Row(panel, "Off") and not Row(panel, "Off").enabled, "a disabled entry became clickable")
    assert(Row(panel, "(  ) Radio") and Row(panel, "[  ] Check"), "the submenu entries or marks are missing")
    W.Click(Row(panel, "Off"))
    assert(not log.off and panel.shown, "a disabled entry ran")
    W.Click(Row(panel, "Check"))
    assert(log.check == true and panel.shown and Row(panel, "[x] Check"), "a checkbox did not refresh in place")
    W.Click(Row(panel, "Stay"))
    assert(log.stay == 1 and panel.shown, "a Refresh response closed the menu")
    W.Click(Row(panel, "Radio"))
    assert(log.radio == 7 and not panel.shown, "a radio did not pick and close")
    S.ContextMenu(owner, Generator(log))
    W.Click(Row(panel, "Plain"))
    assert(log.plain == "plain-data" and not panel.shown, "a button did not run its callback and close")
    S.ContextMenu(owner, Generator(log))
    assert(W.padNavigation.Top() == panel, "the pad's navigation does not hold the menu")
    panel.mouseOver = false
    W.Fire(panel, "OnEvent", "GLOBAL_MOUSE_DOWN", "LeftButton")
    assert(not panel.shown and not panel.events.GLOBAL_MOUSE_DOWN, "a click elsewhere kept the menu")
    assert(W.padNavigation.Top() == nil, "a closed menu kept the pad")
    -- Below its owner; a menu of UIParent (or of no frame) in the screen's
    -- centre, not at UIParent's bottom-left corner.
    S.ContextMenu(owner, Generator(log))
    local point, relative, relativePoint = panel:GetPoint(1)
    assert(point == "TOPLEFT" and relative == owner and relativePoint == "BOTTOMLEFT", "the menu left its owner")
    for _, frame in ipairs({ W.UIParent, false }) do
        S.ContextMenu(frame or nil, Generator(log))
        point, relative, relativePoint = panel:GetPoint(1)
        assert(panel:GetNumPoints() == 1 and point == "CENTER" and relative == W.UIParent and relativePoint == "CENTER",
            "a menu without an owner frame opened at the screen's corner")
    end
    panel:Hide()

    -- A menu taller than the screen scrolls: its rows sit in a scroll frame's
    -- child (Classic MSUF's ScrollIntoView walks a row's parents to the
    -- ScrollFrame), the panel fits the screen, the wheel scrolls the rest
    -- and a refresh keeps the place.
    local long = {}
    local function LongMenu(_, root)
        for index = 1, 60 do
            root:CreateCheckbox("Entry " .. index, function() return long[index] == true end,
                function() long[index] = not long[index] end)
        end
    end
    S.ContextMenu(owner, LongMenu)
    local last = Row(panel, "Entry 60")
    local scroll = last:GetParent():GetParent()
    assert(last:GetParent() == panel.child and scroll:GetObjectType() == "ScrollFrame"
        and scroll:GetScrollChild() == last:GetParent(), "the long menu's rows are not in a scroll frame")
    assert(panel:GetHeight() <= W.UIParent:GetHeight() - 80 and scroll:GetVerticalScrollRange() > 0,
        "the long menu is taller than the screen or cannot scroll")
    W.Fire(scroll, "OnMouseWheel", -1)
    local offset = scroll:GetVerticalScroll()
    assert(offset > 0, "the mouse wheel did not scroll the long menu")
    W.Click(Row(panel, "Entry 40"))
    assert(long[40] and panel.shown and scroll:GetVerticalScroll() == offset and Row(panel, "[x] Entry 40"),
        "a checkbox refresh lost the long menu's scroll place")
    for _ = 1, 40 do W.Fire(scroll, "OnMouseWheel", -1) end
    assert(scroll:GetVerticalScroll() == scroll:GetVerticalScrollRange(), "the wheel scrolled past the menu's end")
    S.ContextMenu(owner, Generator(log))
    assert(scroll:GetVerticalScroll() == 0 and scroll:GetVerticalScrollRange() == 0
        and panel:GetHeight() == 2 * 8 + 8 * 22, "a short menu kept the long menu's scroll or size")
    panel:Hide()

    -- A host without the pad's navigation keeps Blizzard's context menu.
    W = World("Forever", true, function(world) world.G.MSUF_PadNavigation = nil end)
    owner = W.New("Button", nil, W.UIParent)
    assert(W.S.ContextMenu(owner, Generator({})) == nil
        and W.opened[#W.opened].name == "MenuUtil.CreateContextMenu",
        "a host without pad navigation lost Blizzard's context menu")
end)

-- The client APIs the DataTexts places read (as suite_datatexts_security_contract).
local function DataTextFixture(world)
    local G = world.G
    G.GetGameTime = function() return 14, 3 end
    G.GetMoney = function() return 120000 end
    G.C_Container = { GetContainerNumSlots = function() return 20 end,
        GetContainerNumFreeSlots = function() return 8, 0 end }
    G.PlayerHasToy = function() return false end
    G.C_Item = { GetItemCount = function() return 0 end, GetItemInfo = function() end }
    G.GetSpecialization, G.GetSpecializationInfo = nil, nil
    G.C_SpecializationInfo = { GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 62, "Arcane", "", 135932 end }
    G.C_Spell = { GetSpellCooldownDuration = function() return nil end }
    G.C_CurrencyInfo = { GetCurrencyInfo = function() end }
    G.GetProfessions = function() end
end

local function Choice(W, key)
    for index, value in ipairs(W.Suite.DataTextSourceKeys) do
        if value == key then return index end
    end
    error("unknown DataText source " .. key)
end

Case("datatexts", function()
    for _, mode in ipairs({ "Mainline", "Forever", "Gamepad" }) do
        local gamepad = mode == "Gamepad"
        local W = World(gamepad and "Forever" or mode, gamepad, DataTextFixture)
        local S, G = W.S, W.G
        W.LoadAddon("MSUF_Suite_DataTexts")
        local M, A = assert(S.instances.dataTexts), W.private.DataTextActions
        S.Start()
        assert(S.SetMany("dataTexts", { enabled = true, bar1Enabled = true, bar1Layout = 2,
            bar1Slot1 = Choice(W, "gold"), bar1Slot2 = Choice(W, "date"), bar1Slot3 = Choice(W, "clock"),
            bar1Slot4 = Choice(W, "durability"), bar1Slot5 = Choice(W, "professions"),
            bar1Slot6 = Choice(W, "currency") }))
        local gold, date, clock, durability, professions, currency = unpack(M.bars[1].slots, 1, 6)
        if gamepad then
            -- Forever's character window has no CharacterFrameTab3 (Camelot/CharacterFrame.xml).
            G.CharacterFrameTab3 = nil
            for _, case in ipairs({ { gold, "Backpack:Click" }, { date, "GameTimeFrame:Click" },
                { clock, "GameTimeFrame:Click" }, { durability, "CharacterMicroButton:Click" },
                { professions, "ProfessionMicroButton:Click" }, { currency, "CharacterMicroButton:Click" } }) do
                local place, name = case[1], case[2]
                W.Fire(place, "OnEnter")
                local overlay = A.overlay
                assert(overlay and overlay.shown and overlay.points[1][2] == place
                    and overlay:GetAttribute("type1") == "click",
                    "the " .. tostring(place.source) .. " place has no secure overlay under the Gamepad UI")
                local before = #W.opened
                W.Click(overlay)
                local call = W.opened[#W.opened]
                assert(#W.opened == before + 1 and call.name == name and call.secure,
                    "the " .. tostring(place.source) .. " place did not click " .. name .. " securely")
                W.Fire(overlay, "OnLeave")
                -- A click that reaches the place itself opens nothing from Suite code.
                W.Click(place)
                W.Fire(place, "OnLeave")
            end
            assert(InsecureCalls(W) == "", "a Gamepad UI place opened a window from Suite code: " .. InsecureCalls(W))
        else
            -- Retail and Forever's mouse UI keep their openers on these places.
            W.Fire(gold, "OnEnter")
            assert(not (A.overlay and A.overlay.shown and A.overlay.points[1][2] == gold),
                mode .. ": the gold place took the Gamepad UI overlay")
            W.Fire(gold, "OnLeave")
            for _, case in ipairs({ { gold, "OpenAllBags" }, { date, "ToggleCalendar" }, { clock, "ToggleCalendar" },
                { professions, "ToggleProfessionsBook" } }) do
                W.Click(case[1])
                assert(W.opened[#W.opened].name == case[2], mode .. ": the " .. tostring(case[1].source)
                    .. " place no longer runs " .. case[2])
            end
        end
    end
end)

Case("minimap", function()
    for _, mode in ipairs({ "Mainline", "Gamepad" }) do
        local gamepad = mode == "Gamepad"
        local nativeMouseUp, nativeWheel = function() end, function() end
        local W = World(gamepad and "Forever" or "Mainline", gamepad, function(world)
            world.G.GetInventoryItemDurability = function(slot) if slot == 1 then return 50, 100 end end
            -- Blizzard's own map handlers (MinimapMixin:OnClick, :OnMouseWheel).
            world.map:SetScript("OnMouseUp", nativeMouseUp)
            world.map:SetScript("OnMouseWheel", nativeWheel)
        end)
        W.editModeReady = true
        local S, G = W.S, W.G
        H.Enable(W, { captured = true, infoClock = true, infoDurability = true, collectButtons = true })
        W.Step()
        local M, MM = W.M, W.MM
        local clock, durability = M.infoEntries.Clock.button, M.infoEntries.Durability.button
        -- The Clock text: left opens the clock (the default), right the calendar.
        clock.mouseOver = true
        W.Fire(clock, "OnEnter")
        local overlay = MM.infoOverlay
        if gamepad then
            assert(overlay and overlay.shown and overlay.points[1][2] == clock
                and overlay:GetAttribute("*clickbutton1") == G.TimeManagerClockButton
                and overlay:GetAttribute("*clickbutton2") == G.GameTimeFrame,
                "the Clock text has no secure clock and calendar clicks under the Gamepad UI")
            W.Click(overlay, "LeftButton")
            assert(W.opened[#W.opened].name == "TimeManagerClockButton:Click" and W.opened[#W.opened].secure,
                "the Clock text's left click did not open the clock securely")
            W.Click(overlay, "RightButton")
            assert(W.opened[#W.opened].name == "GameTimeFrame:Click" and W.opened[#W.opened].secure,
                "the Clock text's right click did not open the calendar securely")
            -- A modified click (shift-, ctrl-, alt-) opens the same windows:
            -- the secure lookup tries the modifier's own attribute first.
            for _, modifier in ipairs({ "shift", "ctrl", "alt" }) do
                W.modifiers[modifier] = true
                local before = #W.opened
                W.Click(overlay, "RightButton")
                assert(#W.opened == before + 1 and W.opened[#W.opened].name == "GameTimeFrame:Click",
                    "a " .. modifier .. "-right click on the Clock text did not open the calendar")
                W.Click(overlay, "LeftButton")
                assert(#W.opened == before + 2 and W.opened[#W.opened].name == "TimeManagerClockButton:Click",
                    "a " .. modifier .. "-left click on the Clock text did not open the clock")
                W.modifiers[modifier] = nil
            end
            overlay.mouseOver = false
            W.Fire(overlay, "OnLeave")
        else
            assert(not (overlay and overlay.shown and overlay.points[1][2] == clock),
                "Retail's Clock text took the Gamepad UI overlay")
        end
        W.Click(clock, "LeftButton")
        W.Click(clock, "RightButton")
        clock.mouseOver = false
        W.Fire(clock, "OnLeave")
        if not gamepad then
            assert(Calls(W) == "ToggleTimeManager,ToggleCalendar", "Retail's Clock text no longer opens its windows")
        end
        -- Durability: the character micro button, hidden with the micro menu.
        durability.mouseOver = true
        W.Fire(durability, "OnEnter")
        assert(MM.infoOverlay.shown and MM.infoOverlay:GetAttribute("clickbutton") == G.CharacterMicroButton,
            mode .. ": the Durability text lost its secure character window click")
        W.Fire(MM.infoOverlay, "OnLeave")
        durability.mouseOver = false
        -- Middle-click: tracking menu, calendar and world map.
        -- WoW Forever's SmartNavigation reads GetScript("OnMouseUp") and
        -- ("OnMouseDown") of every non-Button it scans (Blizzard_GamepadSmart-
        -- Navigation/Utility.lua SmartNavigation_CanFocusFrame): there the map
        -- keeps Blizzard's own handlers.
        if gamepad then
            assert(W.map:GetScript("OnMouseUp") == nativeMouseUp and W.map:GetScript("OnMouseWheel") == nativeWheel,
                "Forever's map runs a Suite mouse handler SmartNavigation reads")
        end
        local function mouseUp(_, button) W.MapMouseUp(button) end
        local tracking = W.cluster.Tracking.Button
        assert(S.Set("minimap", "middleClick", 2))
        mouseUp(W.map, "MiddleButton")
        assert(tracking:IsMenuOpen() == not gamepad, mode .. ": the middle-click tracking menu is wrong")
        if tracking:IsMenuOpen() then tracking:CloseMenu() end
        for _, case in ipairs({ { 3, "GameTimeFrame:Click", "ToggleCalendar" },
            { 4, "ZoneTextButton:Click", "ShowUIPanel:WorldMapFrame" } }) do
            assert(S.Set("minimap", "middleClick", case[1]))
            local before = #W.opened
            mouseUp(W.map, "MiddleButton")
            if gamepad then
                local flyout = assert(MM.microMenu, "the Gamepad UI middle-click opened no secure flyout")
                local rows = {}
                for _, child in ipairs(flyout.children) do
                    if child.shown and child:GetAttribute("type") == "click" then rows[#rows + 1] = child end
                end
                local row = rows[1]
                assert(flyout.shown and #rows == 1, "the middle-click flyout does not hold one secure row")
                W.Click(row)
                assert(W.opened[#W.opened].name == case[2] and W.opened[#W.opened].secure and not flyout.shown,
                    "the middle-click flyout did not click " .. case[2] .. " securely")
            else
                assert(#W.opened == before + 1 and W.opened[#W.opened].name == case[3]
                    or W.panelCalls[#W.panelCalls] and W.panelCalls[#W.panelCalls].frame == G.WorldMapFrame,
                    "Retail's middle-click no longer opens its window")
            end
        end
        -- The addon button layout menu.
        local menus = #W.opened
        assert(S.MinimapButtonLayoutMenu(), mode .. ": the addon button layout menu did not open")
        if gamepad then
            assert(#W.opened == menus, "the Gamepad UI opened Blizzard's context menu from the minimap")
        else
            assert(W.opened[#W.opened].name == "MenuUtil.CreateContextMenu", "Retail's layout menu moved")
        end
        if gamepad then
            assert(InsecureCalls(W) == "", "the Gamepad UI minimap ran Blizzard openers: " .. InsecureCalls(W))
        end
    end
end)

-- Every context menu and question of the Suite's runtime addons and option
-- pages goes through S.ContextMenu, S.Confirm and S.AskText
-- (MSUF_Suite_Modules/Dialogs.lua; the pages through P.ContextMenu,
-- P.Confirm and P.AskText, MSUF_Suite_Options/Menu/Bridge.lua), which choose
-- the Suite's own list under the Gamepad UI. The skin's addons are not part
-- of this check.
Case("routing", function()
    local support = dofile(root .. "/tools/tests/suite_test_support.lua")
    local files = {}
    for _, addon in ipairs({ "MSUF_Suite", "MSUF_Suite_ActionBars", "MSUF_Suite_Bags", "MSUF_Suite_BuffReminders",
        "MSUF_Suite_Chat", "MSUF_Suite_CooldownManager", "MSUF_Suite_DamageMeter", "MSUF_Suite_DataTexts",
        "MSUF_Suite_Minimap", "MSUF_Suite_Modules", "MSUF_Suite_Nameplates", "MSUF_Suite_QualityOfLife",
        "MSUF_Suite_Options" }) do
        for _, file in ipairs(support.TocFiles(root, addon, "Mainline")) do
            if file:match("%.lua$") and not file:match("^Libs/") then files[#files + 1] = addon .. "/" .. file end
        end
    end
    assert(#files > 100, "no Suite files found under " .. root)
    local offenders = {}
    for _, rel in ipairs(files) do
        if rel ~= "MSUF_Suite_Modules/Dialogs.lua" and rel ~= "MSUF_Suite_Options/Menu/Bridge.lua" then
            local file = assert(io.open(root .. "/" .. rel, "rb"))
            local source = file:read("*a"):gsub("\r\n", "\n")
            file:close()
            local number = 0
            for line in (source .. "\n"):gmatch("(.-)\n") do
                number = number + 1
                local code = line:gsub("%-%-.*$", "")
                if code:find("MenuUtil%.CreateContextMenu%s*%(") or code:find("StaticPopup_Show[%w_]*%s*%(") then
                    offenders[#offenders + 1] = rel .. ":" .. number
                end
            end
        end
    end
    assert(#offenders == 0, "Blizzard's menu or popup opened directly: " .. table.concat(offenders, ", "))
end)

-- The map's own mouse handlers. Retail and Forever's mouse UI keep the
-- Suite's wrappers (no Blizzard ping on the middle-click, a quiet wheel
-- zoom). SmartNavigation scans only under Forever's Gamepad UI
-- (FrameControlsManager.lua FrameShown returns at once outside it), and
-- there the map keeps Blizzard's handlers, which SmartNavigation_CanFocusFrame
-- reads with GetScript. The switch follows INPUT_DEVICE_INTERFACE_TRANSITION,
-- waits for the end of combat and ends with the module.
Case("minimap-input-mode", function()
    local nativeMouseUp, nativeWheel = function() end, function() end
    local W = World("Forever", false, function(world)
        world.map:SetScript("OnMouseUp", nativeMouseUp)
        world.map:SetScript("OnMouseWheel", nativeWheel)
    end)
    W.editModeReady = true
    local S, map = W.S, W.map
    H.Enable(W, { captured = true, middleClick = 3 })
    W.Step()
    local function Native()
        return map:GetScript("OnMouseUp") == nativeMouseUp and map:GetScript("OnMouseWheel") == nativeWheel
    end
    local function Wrapped()
        return map:GetScript("OnMouseUp") ~= nativeMouseUp and map:GetScript("OnMouseWheel") ~= nativeWheel
    end
    assert(Wrapped(), "Forever's mouse UI lost the Suite's own map handlers (Blizzard's ping and zoom sound)")
    W.MapMouseUp("MiddleButton")
    assert(Calls(W) == "ToggleCalendar", "Forever's mouse UI middle-click no longer opens the calendar")
    W.gamepad = true
    W.Event("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
    assert(Native(), "the Gamepad UI kept a Suite mouse handler SmartNavigation reads")
    W.MapMouseUp("MiddleButton")
    assert(Calls(W) == "ToggleCalendar" and W.MM.microMenu and W.MM.microMenu.shown,
        "the Gamepad UI middle-click did not open the secure flyout")
    W.MM.CloseMicroMenu()
    W.gamepad = false
    W.Event("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 1)
    assert(Wrapped(), "leaving the Gamepad UI did not bring the Suite's map handlers back")
    W.MapMouseUp("MiddleButton")
    assert(Calls(W) == "ToggleCalendar,ToggleCalendar", "the mouse UI middle-click ran twice or not at all")
    -- In combat the protected map takes no script change: the switch waits.
    W.SetCombat(true)
    W.gamepad = true
    W.Event("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
    assert(Wrapped(), "the input switch changed the protected map's scripts in combat")
    W.SetCombat(false)
    W.Step()
    assert(Native(), "the input switch made in combat was not applied after it")
    assert(S.Set("minimap", "enabled", false))
    W.Step()
    W.gamepad = false
    W.Event("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 1)
    assert(Native(), "a disabled minimap took the map's mouse handlers again")
    W.MapMouseUp("MiddleButton")
    assert(Calls(W) == "ToggleCalendar,ToggleCalendar", "a disabled minimap still answered the middle-click")
    assert(S.Set("minimap", "enabled", true))
    W.Step()
    assert(Wrapped(), "re-enabling on the mouse UI did not wrap the map again")
    assert(S.Set("minimap", "enabled", false))
    W.Step()
    assert(Native(), "disabling on the mouse UI did not give the map its own handlers back")
end)
