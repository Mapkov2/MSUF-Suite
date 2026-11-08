return function(mw, P, uiFor, settle)
    local S, NS, M, env = P.S, P.Suite, P.M, mw.env
    local cursorX, cursorY = 400, 300
    local createFrame, frames = env.CreateFrame, 0
    env.CreateFrame = function(...) frames = frames + 1; return createFrame(...) end
    env.GetCursorPosition = function() return cursorX, cursorY end
    local keyboardFocus
    env.GetCurrentKeyBoardFocus = function() return keyboardFocus end
    env.IsShiftKeyDown, env.IsControlKeyDown = function() return false end, function() return false end
    env.BreakUpLargeNumbers = tostring
    env.Enum.SecondsFormatterInterval = { Seconds = 1 }
    env.Enum.SecondsFormatterAbbreviation = { OneLetter = 1 }
    env.C_StringUtil = { CreateSecondsFormatter = function()
        return { SetDesiredUnitCount = function() end, SetMinInterval = function() end,
            SetDefaultAbbreviation = function() end, Format = function(_, seconds) return seconds .. "s" end }
    end }
    local function Load(path, addon, private)
        local ok, why = mw.world:LoadFile(path, addon, private)
        assert(ok, tostring(why))
    end
    local suiteRoot = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
    local runtime = {}
    for _, name in ipairs({ "Surfaces", "Runtime" }) do
        Load(suiteRoot .. "/MSUF_Suite_Modules/" .. name .. ".lua", "MSUF_Suite_Modules", runtime)
    end
    S.instances.xpBar = nil
    local private = {}
    for _, name in ipairs({ "Bootstrap", "NativeExperienceBar", "ExperienceTrack", "ExperienceBarText", "ExperienceBar" }) do
        Load(suiteRoot .. "/MSUF_Suite_QualityOfLife/" .. name .. ".lua", "MSUF_Suite_QualityOfLife", private)
    end
    private.NativeExperienceBar.Sync = function() error("menu editor changed native XP visibility") end
    S.Config("xpBar").enabled = false
    M.InvalidatePage("suite_hud")
    assert(NS.Menu.Open("suite_hud"))
    assert(NS.Menu.FocusQualityOfLifeModule("xpBar"))
    settle()
    local ui = uiFor()
    S.Config("xpBar").showLevelTime = true
    ui.stage:Show()
    ui.Paint()
    local function Config() return S.Config("xpBar") end
    local function Script(handle, name, ...)
        if name == "OnEditFocusGained" then
            keyboardFocus = handle
            if not handle.xpTestClearFocus then
                local clear = handle.ClearFocus
                function handle:ClearFocus()
                    if keyboardFocus == self then keyboardFocus = nil end
                    return clear(self)
                end
                handle.xpTestClearFocus = true
            end
        end
        assert(handle:GetScript(name), name .. " missing")(handle, ...)
        if name == "OnEditFocusLost" and keyboardFocus == handle then keyboardFocus = nil end
    end
    local function Press(handle)
        cursorX, cursorY = 400, 300
        Script(handle, "OnMouseDown", "LeftButton")
        assert(ui.xpEditor.kit.drag, "drag did not start")
    end
    local function Travel(handle, dx, dy)
        local scale = ui.stage.suiteXPPreview.host:GetEffectiveScale()
        cursorX, cursorY = 400 + dx * scale, 300 + dy * scale
        Script(handle, "OnUpdate", .016)
    end
    local openTarget, navigations = M.SearchBridge.OpenSearchTarget, {}
    M.SearchBridge.OpenSearchTarget = function(page, label, anchor, section, route, exact)
        local called, opened, focused, matched = openTarget(page, label, anchor, section, route, exact)
        navigations[#navigations + 1] = { key = exact.settingKey, called = called, opened = opened, focused = focused }
        return called, opened, focused, matched
    end
    for _, spec in ipairs(NS.ExperienceBarLayout.Texts) do
        local handle, prefix = assert(ui.targets[spec.id]), spec.prefix
        M.ClearHistory()
        local x, y = Config()[prefix .. "X"], Config()[prefix .. "Y"]
        Press(handle); Script(handle, "OnMouseUp", "LeftButton"); Script(handle, "OnClick", "LeftButton"); settle()
        local target = navigations[#navigations]
        assert(target and target.key == "msufsuite.xpBar." .. prefix .. "Size" and target.called and target.opened and target.focused,
            spec.id .. " left click did not open its exact slider")
        assert(Config()[prefix .. "X"] == x and Config()[prefix .. "Y"] == y and #M.historyUndo == 0,
            spec.id .. " navigation changed offsets/history")
    end
    for _, spec in ipairs(NS.ExperienceBarLayout.Texts) do
        local handle, prefix = assert(ui.targets[spec.id]), spec.prefix
        local before = Config()[prefix .. "X"]
        M.ClearHistory()
        Press(handle); Travel(handle, 17, -9)
        assert(Config()[prefix .. "X"] == before, "follow wrote the profile before release")
        local count = #navigations
        Script(handle, "OnMouseUp", "LeftButton"); Script(handle, "OnClick", "LeftButton"); settle()
        assert(#navigations == count, spec.id .. " drag release navigated away")
        assert(Config()[prefix .. "X"] == before + 17 and Config()[prefix .. "Y"] == -9, spec.id .. " drag offsets")
        assert(#M.historyUndo == 1, spec.id .. " drag was not one undo step")
        assert(M.Undo()); settle()
        assert(Config()[prefix .. "X"] == before and Config()[prefix .. "Y"] == 0, spec.id .. " undo")
        assert(M.Redo()); settle()
        assert(Config()[prefix .. "X"] == before + 17, spec.id .. " redo")
        ui.xpEditor.kit:Select(handle)
        assert(ui.stage._msuf2SelectionDeps.ResetOffsets(ui.stage, handle)); settle()
        assert(Config()[prefix .. "X"] == 0 and Config()[prefix .. "Y"] == 0, spec.id .. " reset")
    end
    local level = ui.targets.level
    ui.xpEditor.kit:Select(level)
    local axis = ui.xpEditor.selection.axisX.edit
    M.ClearHistory()
    Script(axis, "OnEditFocusGained"); axis:SetText("31")
    Press(level)
    Travel(level, 17, 0)
    Script(level, "OnMouseUp", "LeftButton")
    settle()
    Script(axis, "OnEditFocusLost")
    assert(Config().levelTextX == 48, "delayed same-role focus loss overwrote completed drag")
    assert(#M.historyUndo == 2, "pending exact input and drag were not separate undo steps")
    assert(M.Undo()); settle()
    assert(Config().levelTextX == 31, "drag undo lost settled numeric input")
    assert(M.Undo()); settle()
    assert(Config().levelTextX == 0, "settled numeric input undo failed")
    -- A persistent property edit settles through the native slider callbacks before dragging.
    local _, propertySlider = M.RuntimeControlCatalog.ResolveExactTarget("suite_hud",
        P.Meta("suite_hud", "xpBar", "levelTextX", "setting", "suite_qualityOfLife_xpBar_xp_bar"))
    assert(propertySlider and propertySlider.editBox, "persistent X editor absent")
    local nativeScripts = assert(loadfile(assert(arg[3]) .. "/tools/tests/menu_core_world.lua"))().FireScript
    local nativeSetValue = propertySlider.SetValue
    function propertySlider:SetValue(value)
        local before = self:GetValue()
        nativeSetValue(self, value)
        if self:GetValue() ~= before then nativeScripts(self, "OnValueChanged", self:GetValue()) end
    end
    local propertyInput = propertySlider.editBox
    local nativeClear = propertyInput.ClearFocus
    function propertyInput:ClearFocus()
        local handler = self:GetScript("OnEditFocusLost")
        if handler then handler(self) end
        return nativeClear(self)
    end
    M.ClearHistory()
    Script(propertyInput, "OnEditFocusGained"); propertyInput:SetText("32")
    Press(level); Travel(level, 17, 0); Script(level, "OnMouseUp", "LeftButton"); settle()
    Script(propertyInput, "OnEditFocusLost"); settle()
    assert(Config().levelTextX == 49, "persistent property focus loss overwrote drag")
    assert(#M.historyUndo == 2, "persistent property and drag were not separate undo steps")
    assert(M.Undo()); settle()
    assert(Config().levelTextX == 32, "persistent property drag undo")
    assert(M.Undo()); settle()
    assert(Config().levelTextX == 0, "persistent property edit undo")
    local percent = ui.targets.percent
    assert(P.SetMany("xpBar", { width = 800, scale = 200, percentTextX = 500, percentTextY = 90 })); settle()
    assert(ui.stage.suiteXPPreview.host:GetScale() < 2, "text layout did not fit viewport")
    local _, _, _, centerX = ui.stage.suiteXPPreview.host:GetPoint(1)
    -- Independent native-coordinate oracle: the bar spans0..800 and the
    -- right-anchored percentage ends at800-6+500=1294. Its group center647
    -- must align to the stage; the host's own center is400, at every fit scale.
    assert(math.abs(centerX + 247) < .001, "fitted group was not centered in receiver coordinates")
    assert(1294 * ui.stage.suiteXPPreview.host:GetScale() <= ui.width - 16 + .001, "fit omitted outline padding")
    local before = Config().percentTextX
    M.ClearHistory()
    Press(percent); Travel(percent, -23, 11); Script(percent, "OnMouseUp", "LeftButton"); settle()
    assert(Config().percentTextX == before - 23 and Config().percentTextY == 101, "fitted/scaled drag used stage coordinates")
    assert(#M.historyUndo == 1, "scaled drag was not atomic")
    before = Config().percentTextX
    Press(percent); Travel(percent, 25, 0)
    assert(P.Set("xpBar", "height", Config().height + 1)); settle()
    assert(not ui.xpEditor.kit.drag and Config().percentTextX == before, "geometry change did not cancel drag")
    ui.xpEditor.kit:Select(ui.targets.level)
    local edit = ui.xpEditor.selection.axisX.edit
    Script(edit, "OnEditFocusGained"); edit:SetText("999")
    ui.xpEditor.kit:Select(percent); Script(edit, "OnEditFocusLost")
    assert(Config().levelTextX == 999 and Config().percentTextX == before, "text switch did not settle its own numeric input")
    assert(P.Set("xpBar", "levelTextX", 0)); settle()
    Press(percent); Travel(percent, 25, 0)
    local oldProfile = NS.DB
    NS.DB = NS.CopyValue(oldProfile)
    Travel(percent, 30, 0)
    assert(not ui.xpEditor.kit.drag and NS.DB.suite.modules.xpBar.percentTextX == before, "profile change committed drag")
    NS.DB = oldProfile; P.Refresh(); settle()
    Press(percent); Travel(percent, 25, 0)
    mw.world:EnterCombat(); settle()
    assert(not ui.xpEditor.kit.drag and Config().percentTextX == before, "combat committed held drag")
    mw.world:LeaveCombat()
    assert(M.Open("suite_hud") ~= false); settle()
    assert(NS.Menu.FocusQualityOfLifeModule("xpBar")); settle()
    ui.stage:Show(); ui.Paint()
    assert(P.SetMany("xpBar", { displayStyle = 2, percentTextFormat = 4, percentTextSize = 16, levelTextVisibility = 2 })); settle()
    local view = ui.stage.suiteXPPreview
    assert(view.levelText:IsShown() and view.percentText:GetText() == "62.00%", "visibility/decimal format did not reach preview")
    local _, size = view.percentText:GetFont()
    assert(size == 16, "per-text size did not override Minimal inheritance")
    ui.xpEditor.kit:Select(percent)
    local moved = Config().percentTextX
    assert(ui.xpEditor.kit:Nudge(1, -1)); settle()
    assert(Config().percentTextX == moved + 1, "selected text nudge failed")
    local count = frames
    for _ = 1, 10 do ui.Paint() end
    assert(frames == count, "warm repaint created frames")
    assert(not Config().enabled, "editor enabled inactive module")
    print("XP editor acceptance: drags/history/reset, fit, stale input/profile/geometry/combat, format, nudge, warm lifetime passed")
end
