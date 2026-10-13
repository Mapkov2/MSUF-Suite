local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
for _, flavor in ipairs(arg[2] and { arg[2] } or { "Mainline", "Forever" }) do
    local pad, kiosk, keybind, nativeClicks, fallback = false, false, false, 0, 0
    local W = H.New(root, flavor, { clientSecurity = true, clientCombatOrder = true, beforeModules = function(world)
        local G = world.G
        G.InputUtil = { IsGamepadUIEnabled = function() return pad end }
        G.Kiosk = { IsEnabled = function() return kiosk end }
        G.KeybindFrames_InQuickKeybindMode = function() return keybind end
        G.PVEFrame_ToggleFrame = function() fallback = fallback + 1 end
        G.ToggleGroupFinderFrame = function() fallback = fallback + 1 end
        G.LFDMicroButton = world.New("Button", nil, world.root)
        G.LFDMicroButton:SetScript("OnClick", function()
            assert(world.secure, "Gamepad group finder opened in addon context")
            nativeClicks = nativeClicks + 1
        end)
    end })
    H.Enable(W, { dungeonButton = true })
    local button = assert(W.MM.dungeonButton)
    W.Click(button)
    assert(fallback == 1, "mouse shortcut did not open group finder exactly once")
    if flavor == "Forever" then
        pad = true
        assert(not button:IsProtected(), "ordinary minimap host became protected")
        W.Click(button)
        assert(nativeClicks == 1 and fallback == 1, "Gamepad shortcut did not delegate exactly once")
        W.G.LFDMicroButton:Disable()
        W.Click(button)
        assert(nativeClicks == 1 and fallback == 1, "disabled native delegate was clicked")
        W.G.LFDMicroButton:Enable()
        W.G.LFDMicroButton:Hide()
        W.Click(button)
        assert(nativeClicks == 1, "hidden native delegate was clicked")
        W.G.LFDMicroButton:Show()
        local native = W.G.LFDMicroButton
        W.G.LFDMicroButton = nil
        W.Click(button)
        W.G.LFDMicroButton = native
        local forbidden = native.IsForbidden
        native.IsForbidden = function() return true end
        W.Click(button)
        native.IsForbidden = forbidden
        assert(nativeClicks == 1 and fallback == 1, "missing/forbidden delegate opened a window")
        pad = false
        W.Click(button)
        assert(nativeClicks == 1 and fallback == 2, "pad-to-pointer retained the secure target")
        pad = true
        W.Click(button)
        assert(nativeClicks == 2 and fallback == 2, "pointer-to-pad lost the current delegate")
    end
    local beforeHidden = nativeClicks + fallback
    assert(W.S.Set("minimap", "dungeonButton", false))
    W.Click(button)
    assert(nativeClicks + fallback == beforeHidden, "disabled shortcut opened a window")
    assert(W.S.Set("minimap", "dungeonButton", true))
    for _, block in ipairs({ "kiosk", "keybind", "edit", "combat", "disabled" }) do
        local before = nativeClicks + fallback
        kiosk, keybind, W.S.editMode = block == "kiosk", block == "keybind", block == "edit"
        if block == "combat" then W.SetCombat(true) end
        if block == "disabled" then assert(W.S.Set("minimap", "enabled", false)) end
        W.Click(button)
        assert(nativeClicks + fallback == before, block .. " still opened a window")
        if block == "combat" then W.SetCombat(false) end
    end
end
print("Dungeon shortcut: mouse/Gamepad native delegate, blocking states and unprotected host passed")
