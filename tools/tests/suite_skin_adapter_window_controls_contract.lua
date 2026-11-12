-- Exact adapters must reach the real window controls, not just paint a shell.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_window_controls_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))', 1, true))
local fixture = source:sub(1, stop - 1) .. [[
return { NS = NS, Frame = Frame, frames = createdFrames, jobs = combatJobs,
    NextFrame = NextFrame, reported = reported }
]]
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
local function Noop() end
local only = arg[2]
local itemNames = { "ItemSocketingFrame", "ItemInteractionFrame", "ItemUpgradeFrame" }
local addons = { "Blizzard_ItemSocketingUI", "Blizzard_ItemInteractionUI", "Blizzard_ItemUpgradeUI" }

for _, flavor in ipairs({ "Mainline", "Forever" }) do
    _G.combat, _G.combatEdge = false, false
    local H = assert(loadstring(fixture, "@adapter_window_controls_fixture"))()
    local NS, Frame = H.NS, H.Frame
    NS.Client.isForever = flavor == "Forever"
    NS.DB.theme = { look = "midnight" }
    local skin = root .. "/MSUF_Suite_Skin/"
    local function Load(path) assert(loadfile(skin .. path))("MSUF_Suite_Skin", NS) end
    local loaded, continuations, nativeHooks = {}, {}, 0
    local owned, inventory = false, {}
    local nativeInset, nativeScale, nativeLayouts = 15, 1, 0
    MSUFSuite = { Suite = { OwnsBlizzardSurface = function(surface) return surface == "bagWindows" and owned end } }
    FullscreenFrame = Frame("FullscreenFrame", UIParent)
    UpdateContainerFrameAnchors = function()
        nativeLayouts = nativeLayouts + 1
        for _, frame in ipairs(inventory) do
            if frame ~= BankFrame and frame.shown then
                frame.scale = nativeScale
                frame.point = { "BOTTOMRIGHT", FullscreenFrame, "BOTTOMRIGHT", -nativeInset, nativeInset }
            end
        end
    end
    local nativeHook = hooksecurefunc
    hooksecurefunc = function(target, method, callback)
        if type(target) == "string" then
            if target ~= "UpdateContainerFrameAnchors" then return nativeHook(target, method) end
            local original = _G[target]
            _G[target] = function(...) original(...); method(...) end
            return
        end
        local original = assert(target[method])
        nativeHooks = nativeHooks + 1
        target[method] = function(...) original(...); callback(...) end
    end
    NS.Client.IsAddOnLoaded = function(addon) return loaded[addon] == true end
    NS.Client.HasAddOn = function() return true end
    EventUtil = { ContinueOnAddOnLoaded = function(addon, callback) continuations[addon] = callback end }
    EventRegistry = { RegisterCallback = Noop, UnregisterCallback = Noop }
    NS.CombatGate.Cancel = function(key) H.jobs[key] = nil end
    NS.CombatGate.IsPending = function(key) return H.jobs[key] ~= nil end
    NS.Registry.RemoveListener, NS.Registry.GetSurface = Noop, Noop
    NS.ReportError = function(...) error(table.concat({ ... }, ": ")) end
    NS.Surface.Attach = function(frame, spec) frame.surfaceSpec = spec; return { spec = spec } end
    NS.Surface.Ensure = NS.Surface.Attach
    NS.Surface.SetVisible = function(frame, visible) frame.surfaceVisible = visible end
    NS.Surface.SetActive = function(frame, active) frame.surfaceActive = active end
    NS.Cosmetics = { Fade = Noop, FadeNineSlice = Noop, FadeDialogHeader = Noop,
        Restore = Noop, RestoreOwner = Noop, SuppressVertexAlpha = Noop, GetOwner = Noop }
    NS.ControlSkin = { DisableOwner = Noop, RefreshOwner = Noop, Refresh = Noop,
        IsApplied = function() return false end, ApplyButton = function() return true end }
    NS.IconSkin = { DisableOwner = Noop, GetOwner = Noop }
    NS.ScrollBarSkin = { DisableOwner = Noop }
    NS.BlizzardYellow = { TrackFrame = Noop, TrackFrames = Noop, TrackMenuSelection = Noop }
    NS.Checkmarks = { TrackFrame = Noop, TrackDropdown = Noop, IsDropdown = function() return false end,
        GetWindowAction = Noop, UntrackOwner = Noop, TrackTexture = Noop, UntrackTexture = Noop,
        TrackButton = Noop }
    NS.WindowActionSkin = { Apply = Noop, SyncNativeVisual = Noop, DisableOwner = Noop }
    NS.CharacterDetails, NS.CharacterStats, NS.EQoLCharacter =
        { IsHost = function() return false end }, { IsHost = function() return false end },
        { IsHost = function() return false end }
    NS.MacroWindow = { Apply = Noop, Disable = Noop }
    NS.QuestText = { Activate = Noop, Deactivate = Noop }
    for _, path in ipairs({ "Core/SuiteOwnership.lua", "Adapters/Catalog.lua", "Adapters/CatalogGlass.lua", "Adapters/AdapterKit.lua",
        "Adapters/SharedChrome.lua", "Adapters/GenericWindows.lua", "Adapters/GenericWindowsNodes.lua",
        "Adapters/GenericWindowsFrames.lua", "Adapters/GenericWindowsCatalog.lua",
        "Rendering/WindowControls.lua", "Adapters/SocialUI.lua", "Adapters/MajorWindows.lua",
        "Adapters/MajorWindowsItems.lua", "Adapters/Blizzard.lua" }) do Load(path) end
    local W = NS.WindowControls
    local function Native(name, width, height)
        local frame = Frame(name, UIParent)
        frame.width, frame.height = width or 600, height or 500
        frame.NineSlice = Frame(nil, frame)
        frame.NineSlice.frameLevel = 500
        frame.CloseButton = Frame(nil, frame, "Button")
        local createFontString = frame.CloseButton.CreateFontString
        frame.CloseButton.CreateFontString = function(self)
            local label = createFontString(self)
            label.Show, label.Hide = Noop, Noop
            return label
        end
        frame.GetChildren = function() return frame.NineSlice, frame.CloseButton end
        frame.GetNumChildren = function() return 2 end
        _G[name] = frame
        return frame
    end
    local function Controls(frame, owner)
        local state = W.states[frame]
        Check(state and state.owners[owner], flavor .. " " .. frame.name .. " has no owned window controls")
        Check(state.grip.shown and state.titleDrag.shown, frame.name .. " has no visible move/scale input")
        Check(state.grip.frameLevel > frame.NineSlice.frameLevel
            and state.titleDrag.frameLevel > frame.NineSlice.frameLevel,
            frame.name .. " controls are below native chrome")
        return state
    end
    local function Exercise(frame, state)
        local frameCount, showHooks = #H.frames, #(frame.hooks.OnShow or {})
        state.titleDrag.scripts.OnDragStart(state.titleDrag)
        Check(frame.moving, frame.name .. " title cannot move")
        frame.left, frame.top = 390, 850
        state.titleDrag.scripts.OnDragStop(state.titleDrag)
        cursorX, cursorY = 500, 500
        state.grip.scripts.OnMouseDown(state.grip, "LeftButton")
        cursorX, cursorY = 620, 440
        state.grip.scripts.OnUpdate(state.grip)
        state.grip.scripts.OnMouseUp(state.grip)
        local scale, position = frame.scale, NS.DB.windowControls.positions[frame.name]
        Check(scale > 1 and NS.DB.windowControls.scales[frame.name] == scale and position,
            frame.name .. " did not persist move/scale")
        frame:Hide()
        frame.scale = 1
        frame:Show()
        Check(frame.scale == scale and frame.point[4] == position.x / scale,
            frame.name .. " reopen lost saved geometry")
        Check(#H.frames == frameCount and #(frame.hooks.OnShow or {}) == showHooks,
            frame.name .. " reopen created controls or duplicate hooks")
        Check(state.grip.scripts.OnUpdate == nil and next(H.jobs) == nil,
            frame.name .. " idle controls left work scheduled")
    end
    if not only or only == "social" then
        local social = Native("SocialUIFrame")
        social.RefreshTabs, social.RefreshTabStates = Noop, Noop
        social.EnumerateTabs = function() return function() end end
        Check(NS.SocialUISkin.Apply("social"), "social adapter did not paint")
        local state = Controls(social, "social:social-ui")
        Exercise(social, state)
        local frameCount, hookCount = #H.frames, nativeHooks
        social:RefreshTabs(); social:RefreshTabStates()
        NS.SocialUISkin.Apply("social")
        Check(#H.frames == frameCount and nativeHooks == hookCount,
            "social tab refresh or repeated apply recreated controls/hooks")
        -- A distinct parent-owned window must survive releasing the social sub-owner.
        local sibling = Native("CharacterFrame")
        W.Attach(sibling, "social")
        NS.SocialUISkin.Disable("social")
        Check(not state.grip.shown and not state.titleDrag.shown and next(state.owners) == nil,
            "social owner release left its controls active")
        Check(W.states[sibling].grip.shown, "social release removed a sibling owner's controls")
        W.DisableOwner("social")
        social:Hide(); sibling:Hide()
        -- A request made during combat recovers once through the existing owner gate.
        local cold = Native("SocialUIFrame")
        _G.combatEdge = true
        Check(not NS.SocialUISkin.Apply("cold-social") and W.states[cold] and not cold.surfaceSpec,
            "safe cold social opening lacks controls or traversed its deferred skin")
        local coldControls = Controls(cold, "cold-social:social-ui")
        coldControls.titleDrag.scripts.OnDragStart(coldControls.titleDrag)
        Check(cold.moving, "safe cold social title cannot move in combat")
        coldControls.titleDrag.scripts.OnDragStop(coldControls.titleDrag)
        cursorX, cursorY = 500, 500
        coldControls.grip.scripts.OnMouseDown(coldControls.grip, "LeftButton")
        cursorX, cursorY = 560, 470
        coldControls.grip.scripts.OnUpdate(coldControls.grip)
        coldControls.grip.scripts.OnMouseUp(coldControls.grip)
        Check(cold.scale > 1 and not cold.surfaceSpec, "safe cold social combat scale required a full skin pass")
        _G.combatEdge = false
        for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
        Controls(cold, "cold-social:social-ui")
        NS.SocialUISkin.Disable("cold-social")
        cold:Hide()
        local protected = Native("SocialUIFrame")
        protected.protected, _G.combatEdge = true, true
        NS.SocialUISkin.Apply("protected-social")
        Check(not W.states[protected] and not protected.surfaceSpec,
            "protected cold social opening acquired controls in combat")
        NS.SocialUISkin.Disable("protected-social")
        _G.combatEdge = false
        for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
        protected:Hide()
        local cancelled = Native("SocialUIFrame")
        cancelled:Hide()
        _G.combatEdge = true
        NS.SocialUISkin.Apply("cancelled-social")
        NS.SocialUISkin.Disable("cancelled-social")
        _G.combatEdge = false
        for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
        Check(not W.states[cancelled], "cancelled social combat continuation attached stale controls")
        cancelled:Hide()
        _G.SocialUIFrame, _G.CharacterFrame = nil, nil
    end
    if not only or only == "items" then
        local enabled = NS.GenericWindows.IsCategoryEnabled
        NS.GenericWindows.IsCategoryEnabled = function(category) return category == "item-service" end
        Check(NS.MajorWindows.Apply("items"), "item services did not wait for native LoD")
        local panels = {}
        for index, name in ipairs(itemNames) do
            local frame = Native(name)
            panels[index] = frame
            UIPanelWindows[name] = { area = "left" }
            frame:Hide()
            loaded[addons[index]] = true
            assert(continuations[addons[index]], "missing native LoD continuation")()
            Check(not W.states[frame], name .. " hidden native load created window controls")
            _G.combatEdge = true
            frame:Show()
            local state = Controls(frame, "items")
            _G.combatEdge = false
            for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
            Exercise(frame, state)
        end
        -- MajorWindows shares this owner with GenericWindows; only their final
        -- shared teardown releases controls, including the three exact roots.
        NS.MajorWindows.Disable("items")
        Check(W.states[panels[1]].grip.shown, "isolated MajorWindows release removed shared owner controls")
        NS.GenericWindows.Disable("items")
        for _, frame in ipairs(panels) do
            local state = W.states[frame]
            Check(not state.grip.shown and next(state.owners) == nil, frame.name .. " shared owner release failed")
            frame:Hide(); _G[frame.name] = nil
        end
        -- Protected descendants can postpone a cold opening; combat end must
        -- leave a now-closed root dormant until its next native OnShow.
        loaded[addons[1]] = false
        NS.MajorWindows.Apply("deferred-items")
        local delayed = Native(itemNames[1])
        delayed:Hide()
        loaded[addons[1]] = true
        continuations[addons[1]]()
        delayed.protected, _G.combatEdge = true, true
        delayed:Show()
        Check(not W.states[delayed] and next(H.jobs) ~= nil,
            "protected cold item service created controls or lost its continuation")
        delayed:Hide()
        delayed.protected, _G.combatEdge = false, false
        for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
        Check(not W.states[delayed], "combat completion created controls for a closed item service")
        delayed:Show()
        Controls(delayed, "deferred-items")
        NS.MajorWindows.Disable("deferred-items")
        NS.GenericWindows.Disable("deferred-items")
        delayed:Hide(); _G[delayed.name] = nil
        NS.GenericWindows.IsCategoryEnabled = enabled
    end
    if not only or only == "standalone" then
        local picker, opacity = Native("ColorPickerFrame", 360, 460), Native("OpacityFrame", 200, 100)
        opacity:Hide()
        Check(NS.Adapters.Apply("colorPicker"), "color picker adapter failed: " .. table.concat(H.reported, "; "))
        Exercise(picker, Controls(picker, "colorPicker"))
        opacity:Show()
        Exercise(opacity, Controls(opacity, "colorPicker"))
        NS.DB.skins.colorPicker = false
        NS.Adapters.Apply("colorPicker")
        Check(not W.states[picker].grip.shown and not W.states[opacity].grip.shown,
            "color picker adapter did not release both native roots")
        picker:Hide(); opacity:Hide()
        _G.ColorPickerFrame, _G.OpacityFrame = nil, nil
    end
    if not only or only == "inventory" then
        local names = { "BankFrame", "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame6" }
        for index, name in ipairs(names) do
            local frame = Native(name)
            inventory[index] = frame
            if name == "BankFrame" then
                UIPanelWindows[name] = { area = "left" }
                frame.point = { "TOPLEFT", UIParent, "TOPLEFT", 30, -90 }
            else
                UIPanelWindows[name] = nil
                frame.parent = FullscreenFrame
                frame.point = { "BOTTOMRIGHT", FullscreenFrame, "BOTTOMRIGHT", -15, 15 }
            end
            frame.GetPoint = function(self)
                return unpack(self.point or { "CENTER", UIParent, "CENTER", 0, 0 })
            end
        end
        -- Narrow the registered inventory to these native roots; the complete
        -- adapter refresh, GenericWindows skin pass, release and controls are real.
        NS.Adapters.Replace({ id = "blizzardWindows", menuMotion = false,
            resolve = function() return NS.BlizzardCatalog end,
            apply = function(_, owner)
                for _, frame in ipairs(inventory) do NS.GenericWindows.ApplyFrame(frame, owner, "window") end
                return true
            end,
            disable = function(_, owner) return NS.GenericWindows.Disable(owner) end,
        })
        Check(NS.Adapters.Apply("blizzardWindows"), "native inventory adapter failed")
        for _, frame in ipairs(inventory) do Exercise(frame, Controls(frame, "blizzardWindows")) end
        -- Blizzard's panel pass lays out the open Bank window in its slot; the
        -- skin keeps that place for the hand-off and never runs the pass itself.
        UpdateUIPanelPositions(BankFrame)
        UpdateContainerFrameAnchors()
        for index = 2, #inventory do
            local frame = inventory[index]
            Check(frame.scale == NS.DB.windowControls.scales[frame.name]
                and frame.point[4] == NS.DB.windowControls.positions[frame.name].x / frame.scale,
                frame.name .. " native container layout replaced custom geometry")
        end
        -- A later native fit/layout is the baseline to restore on handoff,
        -- not the inset and scale captured on the first opening.
        nativeInset, nativeScale = 40, 0.85
        UpdateContainerFrameAnchors()
        Check(W.states[BankFrame].originalScale == 1,
            "container layout captured the Bank panel's custom scale as native")
        local beforeRelease = nativeLayouts
        owned = true
        NS.SuiteOwnership.Refresh("before")
        Check(nativeLayouts == beforeRelease, "geometry handoff drove another native container anchor pass")
        for _, frame in ipairs(inventory) do
            local relinquished = NS.SuiteOwnership.OwnsWindowGeometry(frame)
            local state = W.states[frame]
            Check(relinquished == (not state.grip.shown), frame.name .. " geometry ownership transfer left competing controls")
            if relinquished then
                Check(frame.scale == (frame == BankFrame and 1 or nativeScale),
                    frame.name .. " ownership transfer did not restore the latest native scale")
                -- Blizzard anchors at offset / scale: the Bank window's place comes back
                -- through the scale it was laid out at, to the last float digit.
                local x, y = frame == BankFrame and 30 or -nativeInset, frame == BankFrame and -90 or nativeInset
                Check(frame.point and math.abs(frame.point[4] - x) < 1e-9 and math.abs(frame.point[5] - y) < 1e-9,
                    frame.name .. " ownership transfer did not restore native position")
                -- The module is free to place its native windows after the skin yields.
                frame.scale, frame.point = 0.75, { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 60 }
            end
        end
        NS.SuiteOwnership.Refresh("after")
        for _, frame in ipairs(inventory) do
            if NS.SuiteOwnership.OwnsWindowGeometry(frame) then
                Check(frame.scale == 0.75 and frame.point[4] == -80,
                    frame.name .. " skin fought the Bags module after ownership transfer")
                frame.scale, frame.point = 1, { "CENTER", UIParent, "CENTER", 0, 0 }
            end
        end
        owned = false
        NS.SuiteOwnership.Refresh("after")
        for _, frame in ipairs(inventory) do
            Controls(frame, "blizzardWindows")
            Check(frame.scale == NS.DB.windowControls.scales[frame.name], frame.name .. " did not reclaim saved skin scale")
        end
        NS.GenericWindows.Disable("blizzardWindows")
        for _, frame in ipairs(inventory) do frame:Hide(); _G[frame.name] = nil end
        -- Closed through the panel manager, the Bank window holds no slot any more.
        GetUIPanel = function() return nil end
    end
    local reads = 0
    for frame in pairs(W.states) do
        frame.IsShown = function() reads = reads + 1; return false end
        frame.GetScale = function() reads = reads + 1; return frame.scale end
    end
    for _ = 1, 20 do UpdateUIPanelPositions(); H.NextFrame() end
    Check(reads == 0 and next(H.jobs) == nil, "closed adapter windows are revisited by native reflow")
    Check(#H.reported == 0, "adapter/control integration reported an error: " .. table.concat(H.reported, "; "))
end
print("suite_skin_adapter_window_controls_contract: " .. checks .. " checks passed")
