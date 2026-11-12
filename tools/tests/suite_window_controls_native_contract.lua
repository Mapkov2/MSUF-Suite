-- Native window topology: separate panels retain independent layout, while
-- PlayerSpells tabs share one root and native actions keep their input zones.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_window_controls_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))', 1, true))
local fixture = source:sub(1, stop - 1) .. [[
return { NS = NS, Frame = Frame, frames = createdFrames, jobs = combatJobs }
]]
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    _G.combat, _G.combatEdge = false, false
    local H = assert(loadstring(fixture, "@window_controls_native_fixture"))()
    local NS, Frame = H.NS, H.Frame
    NS.Client.isForever = flavor == "Forever"
    NS.DB.theme = { look = "midnight" }
    assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/Catalog.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/CatalogGlass.lua"))("MSUF_Suite_Skin", NS)
    local panels, nativePasses = {}, 0
    UpdateUIPanelPositions = function(currentFrame)
        if currentFrame and UIPanelWindows[currentFrame.name].checkFit == 1 then currentFrame.scale = 1 end
        nativePasses = nativePasses + 1
        for index, panel in ipairs(panels) do
            if panel.shown then panel.point = { "TOPLEFT", UIParent, "TOPLEFT", index * 30, -90 } end
        end
    end
    UpdateScaleForFitForOpenPanels = function()
        for _, panel in ipairs(panels) do
            if panel.shown then panel.scale = 1 end
        end
        UpdateUIPanelPositions()
    end
    hooksecurefunc = function(name, callback, method)
        if type(name) == "table" then
            local object, key, post = name, callback, method
            local native = object[key]
            object[key] = function(...) native(...) post(...) end
            return
        end
        local native = assert(_G[name])
        _G[name] = function(...) native(...); callback(...) end
    end
    assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))("MSUF_Suite_Skin", NS)
    local W = NS.WindowControls
    local saved = {}
    for index, name in ipairs({ "ProfessionsFrame", "FriendsFrame", "PlayerSpellsFrame" }) do
        local panel = Frame(name, UIParent)
        _G[name], panels[index] = panel, panel
        UIPanelWindows[name] = { area = "left", checkFit = 1, pushable = 1 }
        panel.NineSlice = Frame(nil, panel)
        panel.NineSlice:SetFrameLevel(name == "PlayerSpellsFrame" and 5500 or 500)
        panel.CloseButton = Frame(nil, panel, "Button")
        panel.CloseButton:SetSize(24, 24)
        panel.CloseButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 1, 0)
        panel.CloseButton.left = 676
        -- Children share the panel's effective scale, as in the client.
        function panel.CloseButton:GetEffectiveScale() return panel:GetEffectiveScale() end
        panel.MaximizeMinimizeButton = Frame(nil, panel, "Button")
        panel.MaximizeMinimizeButton:SetSize(24, 24)
        panel.MaximizeMinimizeButton:SetPoint("RIGHT", panel.CloseButton, "LEFT", 0, 0)
        if name == "PlayerSpellsFrame" then
            -- Blizzard's MaximizeMinimizeButtonFrameTemplate: two buttons, one shown.
            local toggle = panel.MaximizeMinimizeButton
            toggle.MaximizeButton, toggle.MinimizeButton = Frame(nil, toggle, "Button"), Frame(nil, toggle, "Button")
            toggle.MaximizeButton.shown = false
        end
        local nativeClick = function() end
        panel.CloseButton:SetScript("OnClick", nativeClick)
        panel.MaximizeMinimizeButton:SetScript("OnClick", nativeClick)
        saved[index] = { scale = 0.65 + index * 0.1, x = 200 + index * 200, y = -index * 80 }
        NS.DB.windowControls.scales[name] = saved[index].scale
        NS.DB.windowControls.positions[name] = { x = saved[index].x, y = saved[index].y }
        Check(W.Attach(panel, "native"), flavor .. " " .. name .. " did not attach")
        local state = W.states[panel]
        Check(state.titleDrag:GetFrameLevel() > panel.NineSlice:GetFrameLevel(), name .. " title remained under native chrome")
        Check(state.titleDrag.point[1] == "TOPRIGHT" and state.titleDrag.point[4] <= -50,
            name .. " title strip intercepts native close/maximize buttons")
        Check(panel.CloseButton:GetScript("OnClick") == nativeClick
            and panel.MaximizeMinimizeButton:GetScript("OnClick") == nativeClick,
            name .. " native actions were replaced")
        if name == "PlayerSpellsFrame" then
            -- Windows order in one cell size: our minimize, a drawn cell over
            -- Blizzard's own size toggle, a drawn cell over Blizzard's X. The
            -- native buttons keep their clicks; their art fades.
            local minimize, toggle = state.minimize, panel.MaximizeMinimizeButton
            local closeCell, toggleCell, maximize = state.closeCell, state.toggleCell, state.maximize
            Check(minimize and minimize.shown and toggleCell and toggleCell.shown and closeCell and closeCell.shown
                and maximize and not maximize.shown, name .. " lacks the Windows caption beside its native size toggle")
            Check(closeCell.point[1] == "TOPRIGHT" and toggleCell.point[2] == closeCell and minimize.point[2] == toggleCell
                and minimize.width == toggleCell.width and toggleCell.width == closeCell.width,
                name .. " caption cells are not one row of equal cells")
            Check(toggle.alpha == 0 and panel.CloseButton.alpha == 0,
                name .. " shows Blizzard's caption art under the drawn cells")
            -- Talents hide Blizzard's toggle: our maximize takes its place. The
            -- hidden toggle stays faded, so it cannot flash when it comes back.
            toggle:Hide()
            Check(not toggleCell.shown and maximize.shown and maximize.point[2] == closeCell
                and minimize.point[2] == maximize and toggle.alpha == 0,
                name .. " caption lost its maximize with the size toggle hidden")
            toggle:Show()
            Check(toggleCell.shown and not maximize.shown and minimize.point[2] == toggleCell and toggle.alpha == 0,
                name .. " caption lost the returning size toggle")
        else
            Check(not state.minimize and not state.maximize,
                name .. " custom caption covers the native maximize/minimize control")
        end
        Check(not state.grip.scripts.OnUpdate, name .. " idle grip retained an updater")
    end
    local function CheckLayout(label)
        for index, panel in ipairs(panels) do
            local layout = saved[index]
            Check(panel.shown, label .. ": another visible window was closed")
            Check(math.abs(panel.scale - layout.scale) < 0.001, label .. ": independent scale lost")
            Check(panel.point[1] == "TOPLEFT" and math.abs(panel.point[4] - layout.x / layout.scale) < 0.001
                and math.abs(panel.point[5] - layout.y / layout.scale) < 0.001,
                label .. ": independent position lost")
        end
    end
    CheckLayout("initial three windows")
    UpdateUIPanelPositions(panels[1])
    CheckLayout("native panel reflow")
    UpdateScaleForFitForOpenPanels()
    CheckLayout("native scale fit")
    -- Native OpenMailFrame is a separate UIParent child without a panel
    -- manager entry. The catalogued window still gets a safe caption.
    local mail = Frame("OpenMailFrame", UIParent)
    OpenMailFrame = mail
    mail.CloseButton = Frame(nil, mail, "Button")
    mail.CloseButton.left, mail.CloseButton.top, mail.CloseButton.height = 668, 803, 26
    Check(W.Attach(mail, "mail-caption") and W.states[mail].maximize.shown,
        "catalogued standalone mail window lost its caption")
    local nestedMail = Frame("OpenMailFrame", mail)
    nestedMail.CloseButton = mail.CloseButton
    Check(not W.Attach(nestedMail, "mail-caption"), "nested lookalike gained standalone geometry")
    mail:Hide()
    W.DisableOwner("mail-caption")
    OpenMailFrame = nil
    local spellbook = panels[3]
    local children = {}
    for _, key in ipairs({ "SpecFrame", "TalentsFrame", "SpellBookFrame" }) do
        local child = Frame(key, spellbook)
        spellbook[key], children[#children + 1] = child, child
        child.dragHandler = function() end
        child:SetScript("OnDragStart", child.dragHandler)
        Check(not W.Attach(child, "native"), "a spellbook tab became an independent window")
        spellbook.NineSlice:SetFrameLevel(spellbook.NineSlice:GetFrameLevel() + 10)
        Check(W.Attach(spellbook, "native"), "tab refresh lost the existing root")
        Check(W.states[spellbook].titleDrag:GetFrameLevel() > spellbook.NineSlice:GetFrameLevel(),
            "tab refresh lost native chrome level")
    end
    CheckLayout("spellbook tab changes")
    for index, panel in ipairs(panels) do
        local state = W.states[panel]
        state.titleDrag.scripts.OnDragStart(state.titleDrag)
        Check(panel.moving, "native window title did not start moving")
        panel.left, panel.top = 175 + index * 100, 950 - index * 80
        state.titleDrag.scripts.OnDragStop(state.titleDrag)
        local position = NS.DB.windowControls.positions[panel.name]
        saved[index].x, saved[index].y = position.x, position.y
        Check(not panel.moving and not state.titleDrag.events.GLOBAL_MOUSE_UP, "move left a global mouse listener")
        cursorX, cursorY = 400, 400
        state.grip.scripts.OnMouseDown(state.grip, "LeftButton")
        cursorX, cursorY = 460, 340
        state.grip.scripts.OnUpdate(state.grip)
        state.grip.scripts.OnMouseUp(state.grip)
        saved[index].scale = NS.DB.windowControls.scales[panel.name]
        Check(not state.grip.scripts.OnUpdate, "completed scale drag retained an updater")
    end
    UpdateScaleForFitForOpenPanels()
    CheckLayout("independent move and scale")
    for _, panel in ipairs(panels) do panel:Hide(); panel.scale = 1; panel:Show() end
    CheckLayout("native reopen")
    _G.combatEdge = true
    UpdateScaleForFitForOpenPanels()
    CheckLayout("unprotected combat fit")
    -- The spellbook's minimize hides a managed panel: it greys out in combat
    -- and its caption refresh waits for the combat end. Nothing else waits.
    Check(H.jobs["windowControls:captions"] and W.states[panels[3]].minimize.mouseEnabled == false,
        "spellbook minimize stayed active in combat")
    H.jobs["windowControls:captions"] = nil
    Check(next(H.jobs) == nil, "safe visible windows queued combat work")
    _G.combatEdge = false
    for _, child in ipairs(children) do
        Check(child.scale == 1 and not child.geometryWrites and child:GetScript("OnDragStart") == child.dragHandler,
            "root controls changed native spellbook contents")
    end
    Check(W.ResetLayout() and next(NS.DB.windowControls.scales) == nil
        and next(NS.DB.windowControls.positions) == nil, "reset retained per-window settings")
    for _, panel in ipairs(panels) do
        Check(panel.scale == 1, "reset retained a custom scale")
        panel:Hide()
    end
    local scaleOnly = Frame("ProfessionsFrame", UIParent)
    panels[#panels + 1] = scaleOnly
    NS.DB.windowControls.scales.ProfessionsFrame = 0.8
    Check(W.Attach(scaleOnly, "scaleOnly"), "scale-only checkFit window did not attach")
    UpdateUIPanelPositions(scaleOnly)
    Check(scaleOnly.scale == 0.8 and not NS.DB.windowControls.positions.ProfessionsFrame,
        "native current-panel fit lost a custom scale without a saved position")
    scaleOnly:Hide()
    local before = nativePasses
    W.Refresh()
    Check(nativePasses == before, "refreshing closed windows ran native layout")

    -- Exact reviewed standalone utility windows are not UIPanelWindows on
    -- every client. HUD, tooltip, nested panes and secure roots stay excluded.
    for _, name in ipairs({ "SocialUIFrame", "ChatConfigFrame", "HelpFrame", "CooldownViewerSettings",
        "ColorPickerFrame", "OpacityFrame", "ScriptErrorsFrame", "ModelPreviewFrame", "EventTrace", "TimeManagerFrame",
        "DeathRecapFrame", "ClickBindingFrame", "GuideFrame", "SubscriptionInterstitialFrame",
        "CurrencyTransferMenu", "FriendsFriendsFrame" }) do
        UIPanelWindows[name] = nil
        local panel = Frame(name, UIParent)
        _G[name] = panel
        if name == "TimeManagerFrame" then panel.width, panel.height = 220, 240 end
        if name == "OpacityFrame" then panel.width, panel.height = 80, 180 end
        Check(W.Attach(panel, "standalone"), name .. " standalone root did not attach")
        local controls = W.states[panel]
        if name == "OpacityFrame" then
            Check(controls.titleDrag.point[4] == -4 and controls.titleDrag.height == 20
                and -controls.titleDrag.point[5] + controls.titleDrag.height < 35,
                "compact opacity title strip overlaps the native slider")
            Check(not controls.minimize, "opacity popup gained a minimize button")
        end
        if name == "ChatConfigFrame" or name == "HelpFrame" or name == "CooldownViewerSettings"
            or name == "ColorPickerFrame" or name == "OpacityFrame" or name == "ScriptErrorsFrame"
            or name == "ModelPreviewFrame" or name == "EventTrace" then
            local point = controls.grip.point
            Check(point[1] == "TOPLEFT" and point[3] == "BOTTOMRIGHT" and point[4] > 0 and point[5] < 0,
                name .. " scale grip overlaps native footer actions or resize handle")
        end
        panel:Hide()
        local nested = Frame(name, panel)
        Check(not W.Attach(nested, "standalone"), name .. " nested pane became a movable window")
        local protected = Frame(name, UIParent)
        protected.protected, protected.explicitProtected = true, true
        Check(not W.Attach(protected, "standalone"), name .. " explicitly secure root gained geometry controls")
    end
    local alternate = Frame("NativeAlternateTopLevelParent", UIParent)
    GetAppropriateTopLevelParent = function() return alternate end
    for _, name in ipairs({ "FriendsFrame", "SocialUIFrame", "ModelPreviewFrame" }) do
        local panel = Frame(name, alternate)
        Check(W.Attach(panel, "alternate"), name .. " rejected its native alternate top-level parent")
        Check(panel.parent == alternate, name .. " changed its native parent")
        panel:Hide()
        Check(not W.Attach(Frame(name, Frame(nil, alternate)), "alternate"),
            name .. " accepted an arbitrary nested parent")
    end
    GetAppropriateTopLevelParent = nil
    for _, name in ipairs({ "FriendsTooltip", "OpacityFrameCloseButton",
        "ContainerFrameCombinedBags", "ObjectiveTrackerFrame", "GameTooltip", "StaticPopup1" }) do
        Check(not W.Attach(Frame(name, UIParent), "excluded"), name .. " non-window gained controls")
    end
    -- Retail initializes this exact native root at 1x658. Its first SetTab
    -- finishes layout after OnShow, so no second skin/Attach call is guaranteed.
    local initial = Frame("ProfessionsFrame", UIParent)
    _G.ProfessionsFrame = initial
    initial.width, initial.height = 1, 658
    initial.protected = flavor == "Forever"
    initial:Hide()
    NS.DB.windowControls.scales.ProfessionsFrame = 0.8
    NS.DB.windowControls.positions.ProfessionsFrame = nil
    Check(W.Attach(initial, "initialProfession"), "native width-one profession root never enrolled controls")
    local initialState = W.states[initial]
    Check(initial.scale == 0.8 and initialState.originalScale == 1,
        "initial profession layout lost its saved or original scale")
    initial:Show()
    initial:SetWidth(960)
    Check(initialState.titleDrag.shown and initialState.grip.shown,
        "first native profession layout required another Attach")
    cursorX, cursorY = 400, 400
    initialState.grip.scripts.OnMouseDown(initialState.grip, "LeftButton")
    Check(initialState.drag.pixels == 960, "profession scaling retained its initial width-one measurement")
    cursorX, cursorY = 496, 304
    initialState.grip.scripts.OnUpdate(initialState.grip)
    initialState.grip.scripts.OnMouseUp(initialState.grip)
    Check(math.abs(initial.scale - 0.9) < 0.001, "profession scale used stale pre-layout bounds")
    initialState.titleDrag.scripts.OnDragStart(initialState.titleDrag)
    Check(initial.moving, "first-layout profession title did not move")
    initial.left, initial.top = 380, 760
    initialState.titleDrag.scripts.OnDragStop(initialState.titleDrag)
    initial:Hide()
    local tinyImpostor = Frame("ProfessionsFrame", UIParent)
    tinyImpostor.width = 1
    Check(not W.Attach(tinyImpostor, "initialProfession"), "width-one allowance admitted a named impostor")
    initial.width = 0
    Check(not W.Attach(initial, "initialProfession"), "invalid zero-width profession root gained controls")

    -- Profession spell buttons are explicitly secure; their plain book root is
    -- only implicitly protected. Retail hosts it in ProfessionsBookFrame;
    -- Forever embeds the same book under ProfessionsFrame.BookPage.
    local bookName = flavor == "Forever" and "ProfessionsFrame" or "ProfessionsBookFrame"
    local book = Frame(bookName, UIParent)
    _G[bookName], book.protected = book, true
    UIPanelWindows[bookName] = { area = "left", pushable = 1 }
    NS.DB.windowControls.scales[bookName], NS.DB.windowControls.positions[bookName] = nil, nil
    book.NineSlice = Frame(nil, book)
    book.NineSlice:SetFrameLevel(500)
    local page = Frame(nil, book)
    book.BookPage = page
    local secureSpell = Frame(nil, page, "CheckButton")
    secureSpell.protected, secureSpell.explicitProtected = true, true
    local nativeClick = function() end
    secureSpell:SetScript("OnClick", nativeClick)
    Check(W.Attach(book, "secureProfessionBook"), flavor .. " native profession book rejected secure descendants out of combat")
    local controls = W.states[book]
    controls.titleDrag.scripts.OnDragStart(controls.titleDrag)
    Check(book.moving, flavor .. " profession title could not move out of combat")
    book.left, book.top = 380, 760
    controls.titleDrag.scripts.OnDragStop(controls.titleDrag)
    Check(NS.DB.windowControls.positions[bookName], "profession book did not retain its independent position")
    cursorX, cursorY = 400, 400
    controls.grip.scripts.OnMouseDown(controls.grip, "LeftButton")
    cursorX, cursorY = 480, 320
    controls.grip.scripts.OnUpdate(controls.grip)
    controls.grip.scripts.OnMouseUp(controls.grip)
    Check(book.scale ~= 1 and NS.DB.windowControls.scales[bookName] == book.scale,
        "profession book could not scale out of combat")
    local writes = book.geometryWrites
    _G.combatEdge = true
    Check(not W.Attach(book, "secureProfessionBook"), "protected profession book gained combat geometry controls")
    controls.titleDrag.scripts.OnDragStart(controls.titleDrag)
    controls.grip.scripts.OnMouseDown(controls.grip, "LeftButton")
    Check(book.geometryWrites == writes and not controls.grip.scripts.OnUpdate and not book.moving,
        "protected profession book changed geometry at the combat edge")
    Check(not W.Attach(secureSpell, "secureProfessionBook") and not secureSpell.geometryWrites
        and secureSpell:GetScript("OnClick") == nativeClick, "native secure profession action was changed")
    _G.combatEdge = false
    local replayKey = "windowControls:show:" .. bookName
    local replay = H.jobs[replayKey]
    H.jobs[replayKey] = nil
    if replay then replay() end
    Check(W.Attach(book, "secureProfessionBook") and controls.grip.shown and controls.titleDrag.shown,
        "profession controls did not recover after combat")
    book:Hide()
    local impostor = Frame(bookName, UIParent)
    impostor.protected = true
    Check(not W.Attach(impostor, "secureProfessionBook"), "a profession-name impostor bypassed protection")
    book.explicitProtected = true
    Check(not W.Attach(book, "secureProfessionBook"), "an explicitly secure profession root bypassed protection")
    if flavor == "Mainline" then
        local unreviewed = Frame("ProfessionsFrame", UIParent)
        _G.ProfessionsFrame, unreviewed.protected = unreviewed, true
        Check(not W.Attach(unreviewed, "secureProfessionBook"), "unreviewed retail profession protection was bypassed")
    end
end
print("Native window controls: " .. checks .. " checks passed")
