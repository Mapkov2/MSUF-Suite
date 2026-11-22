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
        "SetColorWheelTexture", "SetColorValueTexture", "SetColorRGB", "ClearTextureSlice", "SetVertexOffset" }) do
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
    local input, feedback
    local captures, applies = 0, 0
    local capture, apply = Suite.ProfileIO.CaptureNameplateShared, Suite.ProfileIO.ApplyNameplateShared
    Suite.ProfileIO.CaptureNameplateShared = function(...)
        captures = captures + 1
        return capture(...)
    end
    Suite.ProfileIO.ApplyNameplateShared = function(...)
        applies = applies + 1
        return apply(...)
    end
    local grid, button, bindDropdown, textInput, create = P.W.SettingsRows, P.Button, M.BindDropdown, M.BindTextInputAt, P.NameplatesEditor.Create
    M.BindDropdown = function(ctx, widget, ...)
        local setter = widget.SetOnValueChanged
        widget.SetOnValueChanged = function(self, callback) dropdowns[self] = callback return setter(self, callback) end
        return bindDropdown(ctx, widget, ...)
    end
    P.W.SettingsRows = function(ctx, parent, spec)
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
    assert(M.SelectPage("suite_nameplates"))
    local function Expand(section)
        local body = assert(M.cache[M.activeKey].sections[section], "missing section " .. section)
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
    local basics = "suite_nameplates_enemyBasics"
    Expand(basics)
    assert(not (rows[basics] and rows[basics].look), "a category still renders the global Look control")
    local general = "suite_nameplates_general"
    Expand(general)
    assert(P.NameplatesWorkspace.Kind() == "general", "opening the global settings did not select General")
    assert(rows[general].look and not rows[general].nameplatePreset, "General must keep Look without the template selector")
    for _, label in ipairs({ "Quick Setup", "Preview template", "Show original" }) do
        assert(not (buttons[basics] and buttons[basics][label]), "Basics kept " .. label)
    end
    local fonts = "opt_fonts_host_nameplates"
    assert(not P.NameplatesWorkspace.Open("profiles"), "Templates is still a top-level Nameplates tab")
    assert(not P.NameplatesWorkspace.Open("shared"), "Shared is still a top-level Nameplates tab")
    assert(not M.cache.suite_nameplates.sections.suite_nameplates_profiles and not input, "the dedicated profile UI survived")
    -- MSUF's castbar menu owns the interrupt-ready look and switch for castbars
    -- and nameplates alike: this page has no section, row or color for them.
    assert(M.cache.suite_nameplates.sections.suite_nameplates_host_general == nil,
        "nameplates kept an interrupt readiness section of their own")
    local config = Suite.Suite.Config("nameplates")
    if P.NameplateFonts.HasLinks() then
        assert(Suite.HostBridge.OpenNameplateFonts(M, "fonts_global_font"), "native Fonts scope is unreachable")
        assert(M.activeKey == "opt_fonts")
        return
    end
    assert(M.SelectPage("opt_fonts"))
    Expand(fonts)
    local fontRows, fontControls = rows[fonts], controls[fonts]
    assert(fontRows.fontShadowOpacity.step == .01 and fontRows.fontShadowOpacity.roundStep == false
        and fontRows.fontTextAlpha.step == .01 and fontRows.fontTextAlpha.roundStep == false,
        "opacity sliders lost one-percent-point editing")
    assert(not fontRows.fontSize and not fontRows.nameFontSize, "Fonts still offers nameplate size controls")
    assert(fontRows.fontBaselineOffset.step == 1, "baseline offset lost single-unit editing")
    Click(fonts, "Use inherited settings")
    assert(fontRows.fontOverride.get() == false, "font reset retained its scope override")
    assert(not Suite.NameplatePortableText.Stored(), "font reset retained portable typography")
    fontControls.fontOverride:GetScript("OnClick")(fontControls.fontOverride)
    mw:RunTimers(1000)
    assert(fontRows.fontOverride.get() == true and fontControls.fontBaselineOffset:IsEnabled(), "font override did not enable typography")
    MenuWorld.FireScript(fontControls.fontBaselineOffset, "OnValueChanged", 0)
    dropdowns[fontControls.nameFormat]("ABBREV_CUT")
    local captured = assert(Suite.ProfileIO.CaptureNameplateShared())
    assert(captured.nameplates.fontBaselineOffset == 0
        and captured.nameplates.nameFormat == "ABBREV_CUT", "shared typography edits did not reach the owning model")
    local applied, checkpointed = applies, checkpoints
    local fontSlider = fontControls.fontBaselineOffset
    MenuWorld.FireScript(fontSlider, "OnMouseDown", "LeftButton")
    for value = 1, 3 do MenuWorld.FireScript(fontSlider, "OnValueChanged", value) end
    assert(applies == applied and checkpoints == checkpointed, "slider ticks applied settings or created checkpoints")
    assert(capture().nameplates.fontBaselineOffset == 0, "slider drag changed live typography before release")
    MenuWorld.FireScript(fontSlider, "OnMouseUp", "LeftButton")
    MenuWorld.FireScript(fontSlider, "OnValueChanged", 4)
    mw:RunTimers(1000)
    assert(applies == applied + 1 and capture().nameplates.fontBaselineOffset == 4, "slider release failed to commit the final native tick once")
    assert(checkpoints == checkpointed, "slider release duplicated the host's history checkpoint")
    applied = applies
    MenuWorld.FireScript(fontSlider, "OnMouseDown", "LeftButton")
    MenuWorld.FireScript(fontSlider, "OnValueChanged", 2)
    MenuWorld.FireScript(fontSlider, "OnValueChanged", 4)
    MenuWorld.FireScript(fontSlider, "OnMouseUp", "LeftButton")
    mw:RunTimers(1000)
    assert(applies == applied, "unchanged slider drag committed a redundant write")
    MenuWorld.FireScript(fontSlider.editBox, "OnEditFocusGained")
    fontSlider.editBox:SetText("1")
    MenuWorld.FireScript(fontSlider.editBox, "OnEnterPressed")
    -- The fixture's SetValue stores the native value without dispatching its
    -- engine event, so deliver that event after the real keyboard handler.
    assert(fontSlider:GetValue() == 1, "keyboard slider entry did not update the native value")
    MenuWorld.FireScript(fontSlider, "OnValueChanged", fontSlider:GetValue())
    mw:RunTimers(1000)
    assert(capture().nameplates.fontBaselineOffset == 1, "keyboard slider entry failed to commit")
    applied = applies
    env.IsShiftKeyDown = function() return true end
    MenuWorld.FireScript(fontSlider, "OnMouseWheel", 1)
    MenuWorld.FireScript(fontSlider, "OnValueChanged", fontSlider:GetValue())
    env.IsShiftKeyDown = function() return false end
    mw:RunTimers(1000)
    assert(applies == applied + 1 and capture().nameplates.fontBaselineOffset > 1, "mouse-wheel slider edit failed to commit once")
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
    print("PASS Nameplates menu and typography " .. flavor .. " " .. host:match("([^/]+)$"))
end

for _, host in ipairs({ root .. "/../MidnightSimpleUnitFrames-7.0" }) do
    for _, flavor in ipairs({ "Mainline", "Forever" }) do
        if not arg[2] or flavor == arg[2] then
            if not arg[3] or host:match("([^/]+)$") == arg[3] then Verify(host, flavor) end
        end
    end
end
