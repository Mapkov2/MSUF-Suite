local root = assert(arg[1]):gsub("\\", "/")
local function Equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do if not Equal(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end
local function InstallMethods(world)
    local methods = world.widgets.Methods
    for _, name in ipairs({ "SetStartPoint", "SetEndPoint", "SetThickness", "SetTextHeight", "SetPointsOffset",
        "SetColorWheelTexture", "SetColorValueTexture", "SetColorRGB" }) do
        if not methods[name] then methods[name] = function(self, ...) self[name .. "Args"] = { ... } end end
    end
    for _, part in ipairs({ "ColorWheelThumbTexture", "ColorValueThumbTexture" }) do
        methods["Set" .. part] = function(self, path)
            self[part] = self:CreateTexture(nil, "OVERLAY")
            self[part]:SetTexture(path)
        end
        methods["Get" .. part] = function(self) return self[part] end
    end
    methods.IsVisible = function(self)
        local parent = self:GetParent()
        return self:IsShown() and (not parent or parent:IsVisible())
    end
end

local function Load(rootPath, world, addon, namespace)
    local file = assert(io.open(rootPath .. "/" .. addon .. "/" .. addon .. "_Mainline.toc", "rb"))
    local source = file:read("*a")
    file:close()
    for line in source:gmatch("[^\r\n]+") do
        if line:sub(1, 1) ~= "#" then
            local path = rootPath .. "/" .. addon .. "/" .. line:gsub("\\", "/")
            if path == arg[4] then path = arg[5] end
            local ok, message = world:LoadFile(path, addon, namespace)
            assert(ok, tostring(message))
        end
    end
end

local function Open(host, flavor)
    local MenuWorld = assert(loadfile(host .. "/tools/tests/menu_core_world.lua"))()
    local mw = MenuWorld.Open(host, flavor, { locale = "enUS", clientScriptBindings = true, beforeCore = InstallMethods })
    local env = mw.env
    env.InCombatLockdown, env.UnitAffectingCombat = function() return false end, function() return false end
    env.GetCurrentKeyBoardFocus = function() return nil end
    env.IsControlKeyDown, env.IsShiftKeyDown = function() return false end, function() return false end
    env.C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
    env.C_SpecializationInfo = { GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return flavor == "Forever" and 1482 or 71, "Fixture specialization" end }
    env.C_AddOns = {
        GetAddOnMetadata = function() end,
        IsAddOnLoaded = function(name) local loaded = name:find("^MSUF") or name:find("^MidnightSimpleUnitFrames") return loaded, loaded end,
        DoesAddOnExist = function(name) return name:find("^MSUF_Suite") ~= nil end,
        GetAddOnEnableState = function() return 2 end, LoadAddOn = function() return false, "MISSING" end,
        GetNumAddOns = function() return 0 end,
    }
    local cvars = {}
    env.C_CVar.GetCVar = function(key) return cvars[key] or "1" end
    env.C_CVar.GetCVarDefault = function() return "1" end
    env.C_CVar.SetCVar = function(key, value) cvars[key] = tostring(value) end
    env.C_GameRules = { IsGameRuleActive = function() return false end }
    Load(root, mw.world, "MSUF_Suite", {})
    local Suite, P = env.MSUFSuite, {}
    assert(Suite.Database.Initialize(nil))
    -- Full host HUD redraw needs the live totem/class-power scene. Its
    -- profile notification is outside these menu and nameplate owner checks.
    Suite.ProfileVariants.AfterMutation = function() end
    -- CBOR/compression is a native client service. Stable in-process tokens
    -- keep the real Suite profile normalization/import paths in this UI test.
    local encoded = {}
    env.MSUF_EncodeCompactTable = function(value)
        local text = "MSUF3:UITOKEN" .. (#encoded + 1)
        encoded[#encoded + 1] = Suite.CopyValue(value)
        return text
    end
    env.MSUF_TryDecodeCompactString = function(text)
        return Suite.CopyValue(encoded[tonumber(text:match("^MSUF3:UITOKEN(%d+)$"))])
    end
    Suite.Suite.Config("nameplates").enabled = true
    Load(root, mw.world, "MSUF_Suite_Options", P)
    return mw, P, Suite, MenuWorld
end

local function Verify(host, flavor)
    local mw, P, Suite, MenuWorld = Open(host, flavor)
    local env, M = mw.env, mw.M
    local rows, controls, buttons, dropdowns, preview = {}, {}, {}, {}
    local input, feedback, promptedName, status
    local captures, applies, checkpoints, refreshes, prompts, inspections = 0, 0, 0, 0, 0, 0
    local capture, apply, checkpoint = Suite.ProfileIO.CaptureNameplateShared, Suite.ProfileIO.ApplyNameplateShared,
        Suite.ProfileWorkbenchBridge.Checkpoint
    Suite.ProfileIO.CaptureNameplateShared = function(...)
        captures = captures + 1
        return capture(...)
    end
    Suite.ProfileIO.ApplyNameplateShared = function(...)
        applies = applies + 1
        return apply(...)
    end
    Suite.ProfileWorkbenchBridge.Checkpoint = function(...)
        checkpoints = checkpoints + 1
        return checkpoint(...)
    end
    local refresh, description, inspect = P.Refresh, P.Description, Suite.NameplateProfiles.Inspect
    P.Refresh = function(...) refreshes = refreshes + 1 return refresh(...) end
    P.Description = function(parent, text, ...)
        local label = description(parent, text, ...)
        local section = P.HM.GetSectionEntry(parent)
        if section and section.sectionId == "suite_nameplates_profiles" and text == "" then status = label end
        return label
    end
    Suite.NameplateProfiles.Inspect = function(...)
        inspections = inspections + 1
        return inspect(...)
    end
    local grid, button, bindDropdown, textInput, create = P.W.SettingsRows, P.Button, M.BindDropdown, M.BindTextInputAt, P.NameplatesEditor.Create
    M.BindDropdown = function(ctx, widget, ...)
        local setter = widget.SetOnValueChanged
        widget.SetOnValueChanged = function(self, callback) dropdowns[self] = callback return setter(self, callback) end
        return bindDropdown(ctx, widget, ...)
    end
    P.W.SettingsRows = function(ctx, parent, spec)
        for _, row in ipairs(spec.rows) do
            -- A host may initialize a selector by invoking its setter. All
            -- status/input dependencies must already exist at this point.
            if row.id == "template" then row.set(row.get()) end
        end
        local result = grid(ctx, parent, spec)
        for _, row in ipairs(spec.rows) do
            local section = row.sectionId
            rows[section], controls[section] = rows[section] or {}, controls[section] or {}
            rows[section][row.id], controls[section][row.id] = row, result.controls[row.id]
        end
        return result
    end
    P.Button = function(ctx, parent, label, x, y, width, click, enabled, meta, options)
        local result = button(ctx, parent, label, x, y, width, click, enabled, meta, options)
        if meta and meta.sectionId then
            buttons[meta.sectionId] = buttons[meta.sectionId] or {}
            buttons[meta.sectionId][label] = result
        end
        return result
    end
    M.BindTextInputAt = function(ctx, parent, label, ...)
        local widget = textInput(ctx, parent, label, ...)
        if label == "Nameplate import / export" then input = widget end
        return widget
    end
    P.NameplatesEditor.Create = function(...) preview = create(...) return preview end
    M.ShowStatusFeedback = function(text, kind) feedback = { text, kind } end
    P.AskText = function(_, _, callback) prompts = prompts + 1 callback(assert(promptedName)) end
    P.Confirm = function(_, _, callback) callback() end
    assert(M.SelectPage("suite_nameplates"))
    local function Expand(section)
        local body = assert(M.cache.suite_nameplates.sections[section], "missing section " .. section)
        P.W.FocusCollapsibleSection(body, { scroll = false, flash = false })
        mw:RunTimers(1000)
        assert(body:IsVisible(), "hidden section " .. section)
    end
    local function Click(section, label, expectedFailure)
        local widget = assert(buttons[section][label], "missing button " .. label)
        assert(widget:IsVisible() and widget:IsEnabled(), "inactive button " .. label)
        feedback = nil
        widget:GetScript("OnClick")(widget, "LeftButton")
        mw:RunTimers(1000)
        if expectedFailure then assert(feedback and feedback[2] == "danger", "expected failure for " .. label)
        else assert(not feedback or feedback[2] ~= "danger", feedback and feedback[1]) end
    end
    local profiles, fonts = "suite_nameplates_profiles", "suite_nameplates_host_nameplates"
    -- MSUF's castbar menu owns the interrupt-ready look and switch for castbars
    -- and nameplates alike: this page has no section, row or color for them.
    assert(M.cache.suite_nameplates.sections.suite_nameplates_host_general == nil,
        "nameplates kept an interrupt readiness section of their own")
    Expand(fonts)
    local initialOverride = rows[fonts].fontOverride.get()
    Expand(profiles)
    assert(input and input:IsVisible(), "profile transfer input was not constructed")
    assert(status and status:GetText():find("nameplate settings will change", 1, true), "initial template preview lost its status")
    for _, group in ipairs(Suite.NameplateProfiles.Groups) do
        local widget = assert(controls[profiles][group.key])
        assert(rows[profiles][group.key].get() == true)
        local inspected = inspections
        widget:GetScript("OnClick")(widget)
        assert(rows[profiles][group.key].get() == false, "selection group toggle did not update")
        assert(inspections == inspected + 1, "selection group left its old import preview visible")
        widget:GetScript("OnClick")(widget)
        assert(rows[profiles][group.key].get() == true)
    end
    local config = Suite.Suite.Config("nameplates")
    local initialWidth = config.enemyHealthWidthDelta
    local selector = controls[profiles].template
    dropdowns[selector]("tank")
    assert(#input:GetText() > 0 and config.enemyHealthWidthDelta == initialWidth, "template selection applied before confirmation")
    Click(profiles, "Load template")
    Click(profiles, "Preview import")
    assert(config.enemyHealthWidthDelta == initialWidth, "import preview changed settings")
    local refreshed = refreshes
    Click(profiles, "Apply selection")
    assert(config.enemyHealthWidthDelta == 150 and config.enemyTankMode, "built-in template did not apply")
    assert(refreshes > refreshed, "applying a template did not refresh dependent controls")
    refreshed = refreshes
    Click(profiles, "Restore previous setup")
    assert(config.enemyHealthWidthDelta == initialWidth, "previous setup was not restored")
    assert(refreshes > refreshed, "restoring a template did not refresh dependent controls")
    promptedName = "UI template"
    Click(profiles, "Save current setup")
    local saved = assert(Suite.NameplateProfiles.Read("saved:UI template"))
    Click(profiles, "Save current setup", true)
    assert(Suite.NameplateProfiles.Read("saved:UI template") == saved, "saving silently overwrote an existing template")
    local asked = prompts
    dropdowns[selector]("saved:missing")
    Click(profiles, "Duplicate template", true)
    assert(prompts == asked, "duplicating an invalid source asked for a name and could save the current setup")
    dropdowns[selector]("saved:UI template")
    promptedName = "UI duplicate"
    Click(profiles, "Duplicate template")
    assert(Suite.NameplateProfiles.Read("saved:UI duplicate") == saved, "template duplication changed the snapshot")
    config.enemyHealthWidthDelta = 71
    Click(profiles, "Update saved template")
    local updatedID, updated = Suite.ProfileIO.PrepareModuleProfile(Suite.NameplateProfiles.Read("saved:UI duplicate"))
    assert(updatedID == "nameplates" and updated.enemyHealthWidthDelta == 71, "updating a saved template left old settings")
    Click(profiles, "Export selection")
    assert(Suite.NameplateProfiles.Inspect(input:GetText()), "export input contains an invalid profile")
    Click(profiles, "Delete saved template")
    assert(not Suite.NameplateProfiles.Read("saved:UI duplicate"), "deleting a saved template failed")

    Expand(fonts)
    local fontRows, fontControls = rows[fonts], controls[fonts]
    assert(fontRows.fontShadowOpacity.step == .01 and fontRows.fontShadowOpacity.roundStep == false
        and fontRows.fontTextAlpha.step == .01 and fontRows.fontTextAlpha.roundStep == false,
        "opacity sliders lost one-percent-point editing")
    assert(fontRows.fontBaselineOffset.step == 1, "baseline offset lost single-unit editing")
    assert(fontRows.fontOverride.get() == initialOverride, "restoring the previous setup changed its font override")
    Click(fonts, "Use inherited settings")
    assert(fontRows.fontOverride.get() == false, "font reset retained its scope override")
    assert(not Suite.NameplatePortableText.Stored(), "font reset retained portable typography")
    fontControls.fontOverride:GetScript("OnClick")(fontControls.fontOverride)
    mw:RunTimers(1000)
    assert(fontRows.fontOverride.get() == true and fontControls.fontSize:IsEnabled(), "font override did not enable typography")
    MenuWorld.FireScript(fontControls.fontSize, "OnValueChanged", 19)
    MenuWorld.FireScript(fontControls.nameFontSize, "OnValueChanged", 21)
    dropdowns[fontControls.nameFormat]("ABBREV_CUT")
    local captured = assert(Suite.ProfileIO.CaptureNameplateShared())
    assert(captured.nameplates.fontSize == 19 and captured.nameplates.nameFontSize == 21
        and captured.nameplates.nameFormat == "ABBREV_CUT", "shared typography edits did not reach the owning model")
    local applied, checkpointed = applies, checkpoints
    local fontSlider = fontControls.fontSize
    MenuWorld.FireScript(fontSlider, "OnMouseDown", "LeftButton")
    for value = 20, 30 do MenuWorld.FireScript(fontSlider, "OnValueChanged", value) end
    assert(applies == applied and checkpoints == checkpointed, "slider ticks applied settings or created checkpoints")
    assert(capture().nameplates.fontSize == 19, "slider drag changed live typography before release")
    MenuWorld.FireScript(fontSlider, "OnMouseUp", "LeftButton")
    MenuWorld.FireScript(fontSlider, "OnValueChanged", 31)
    mw:RunTimers(1000)
    assert(applies == applied + 1 and capture().nameplates.fontSize == 31, "slider release failed to commit the final native tick once")
    assert(checkpoints == checkpointed, "slider release duplicated the host's history checkpoint")
    applied = applies
    MenuWorld.FireScript(fontSlider, "OnMouseDown", "LeftButton")
    MenuWorld.FireScript(fontSlider, "OnValueChanged", 25)
    MenuWorld.FireScript(fontSlider, "OnValueChanged", 31)
    MenuWorld.FireScript(fontSlider, "OnMouseUp", "LeftButton")
    mw:RunTimers(1000)
    assert(applies == applied, "unchanged slider drag committed a redundant write")
    MenuWorld.FireScript(fontSlider.editBox, "OnEditFocusGained")
    fontSlider.editBox:SetText("23")
    MenuWorld.FireScript(fontSlider.editBox, "OnEnterPressed")
    -- The fixture's SetValue stores the native value without dispatching its
    -- engine event, so deliver that event after the real keyboard handler.
    assert(fontSlider:GetValue() == 23, "keyboard slider entry did not update the native value")
    MenuWorld.FireScript(fontSlider, "OnValueChanged", fontSlider:GetValue())
    mw:RunTimers(1000)
    assert(capture().nameplates.fontSize == 23, "keyboard slider entry failed to commit")
    applied = applies
    env.IsShiftKeyDown = function() return true end
    MenuWorld.FireScript(fontSlider, "OnMouseWheel", 1)
    MenuWorld.FireScript(fontSlider, "OnValueChanged", fontSlider:GetValue())
    env.IsShiftKeyDown = function() return false end
    mw:RunTimers(1000)
    assert(applies == applied + 1 and capture().nameplates.fontSize > 23, "mouse-wheel slider edit failed to commit once")
    local general = M.EnsureDB().general
    general.fontColorR, general.fontColorG, general.fontColorB = .2, .4, .6
    local ok = Suite.ProfileIO.ApplyNameplateShared({ version = 1, nameplates = {
        fontOverride = true, fontColorR = .3, fontColorG = .5, fontColorB = .7, fontTextAlpha = .8 } })
    assert(ok)
    preview:Paint()
    local shared = assert(Suite.NameplateText.Shared(config))
    for _, id in ipairs({ "enemy.CastText", "enemy.CastTime", "enemy.HealthText" }) do
        local handle = assert(preview.kit.entries[id]).region
        local label = assert(({ handle:GetRegions() })[1])
        local r, g, b, a = label:GetTextColor()
        assert(r == shared.textColor.r and g == shared.textColor.g and b == shared.textColor.b and a == shared.textColor.a,
            "preview glyph color differs from shared runtime typography for " .. id)
    end
    Click(fonts, "Use inherited settings")
    assert(fontRows.fontOverride.get() == false, "font reset retained its scope override")

    P.Refresh()
    mw:RunTimers(1000)
    local capturedBeforeReads = captures
    for _ = 1, 50 do
        for _, row in pairs(fontRows) do row.get() end
    end
    assert(captures == capturedBeforeReads, "host rows repeated full captures within one refresh")
    captured = capture()
    local inheritedShadow, inheritedDots = captured.nameplates.textBackdrop, captured.nameplates.shortenNameShowDots
    if inheritedShadow == nil then inheritedShadow = true end
    if inheritedDots == nil then inheritedDots = true end
    assert(fontRows.textBackdrop.get() == inheritedShadow and fontRows.shortenNameShowDots.get() == inheritedDots,
        "inherited typography controls differ from the effective host settings")
    for id in pairs(fontRows) do
        assert(not id:find("^kickReady") and id ~= "castbarOutlineThickness", "typography section kept an interrupt row: " .. id)
    end
    local _, exactBefore = capture()
    local storedBefore, pendingBefore = Suite.CopyValue(Suite.DB.nameplateShared), Suite.CopyValue(Suite.DB.nameplateSharedPending)
    local settingsBefore = Suite.CopyValue(config)
    local nativeBefore = Suite.ProfileIO.CaptureNameplateCVars()
    local dispatch, fail = Suite.Dispatch, true
    Suite.Dispatch = function(reporter, callback, ...)
        if callback == Suite.ProfileIO.ApplyNameplateShared and fail then
            fail = false
            callback(...)
            -- Model securecallfunction's failed return after the real host,
            -- stored state and Suite repaint writes have already occurred.
            return false, nil, "injected failure after host write"
        end
        return dispatch(reporter, callback, ...)
    end
    feedback = nil
    fontControls.fontOverride:GetScript("OnClick")(fontControls.fontOverride)
    Suite.Dispatch = dispatch
    mw:RunTimers(1000)
    local _, exactAfter = capture()
    assert(not fail and feedback and feedback[2] == "danger", "failed host edit was reported as successful")
    assert(Equal(exactBefore, exactAfter) and Equal(storedBefore, Suite.DB.nameplateShared)
        and Equal(pendingBefore, Suite.DB.nameplateSharedPending), "failed host edit left partial shared settings")
    assert(Equal(settingsBefore, config) and Equal(nativeBefore, Suite.ProfileIO.CaptureNameplateCVars()),
        "shared-only edit changed module settings or Blizzard CVars")
    assert(fontRows.fontOverride.get() == false, "failed typography edit kept its override")
    print("PASS nameplate profile and host UI " .. flavor .. " " .. host:match("([^/]+)$"))
end

for _, host in ipairs({ root .. "/../MidnightSimpleUnitFrames", root .. "/../MidnightSimpleUnitFrames-7.0" }) do
    for _, flavor in ipairs({ "Mainline", "Forever" }) do
        if not arg[2] or flavor == arg[2] then
            if not arg[3] or host:match("([^/]+)$") == arg[3] then Verify(host, flavor) end
        end
    end
end
