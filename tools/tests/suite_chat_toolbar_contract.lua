local root = assert(arg[1])
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local function eq(actual, expected, label) assert(actual == expected, label or tostring(actual) .. " ~= " .. tostring(expected)) end
local patches = {
    nativeDock = { "Toolbar", 'M.context:Anchor(dock, point, relative, edge, x, y)', '' },
    hover = { "Toolbar", 'visual.toolbarHovered = true', 'visual.toolbarHovered = false' },
    combat = { "ToolbarGeometry", 'or NS.InCombat()', '' },
    profile = { "ToolbarGeometry", 'and M.config == gesture.config', '' },
    inputToggle = { "InputAnimation", 'if not config.animateInput then', 'if false then' },
    inputIM = { "InputAnimation", 'input:HookScript("OnEditFocusGained", Activated)', 'input:HookScript("OnShow", Activated)' },
    inputSquash = { "InputAnimation", 'local slide = group:CreateAnimation("Translation")',
        'local slide = group:CreateAnimation("Scale")' },
    inputSnap = { "InputAnimation", 'record.slide:SetOffset(0, distance)', 'record.slide:SetOffset(0, distance + 8)' },
}

local function Run(flavor)
    local combat, lockdown, protected = false, false, false
    local created, layouts, commits, copies, opened, inputs = 0, 0, 0, 0, 0, 0
    local hooks, waits = {}, {}
    local function Frame(parent)
        created = created + 1
        local frame = { parent = parent, points = {}, scripts = {}, events = {}, shown = true,
            width = 480, height = 180, alpha = 1, scale = 1 }
        function frame:SetScript(key, fn)
            assert(key ~= "OnUpdate" or fn == nil, "toolbar installed a Lua update loop")
            self.scripts[key] = fn
        end
        function frame:HookScript(key, fn)
            local before = self.scripts[key]
            self.scripts[key] = before and function(...) before(...); fn(...) end or fn
        end
        function frame:RegisterForDrag() end
        function frame:RegisterEvent(key) self.events[key] = true end
        function frame:UnregisterEvent(key) self.events[key] = nil end
        function frame:EnableMouse(value) self.mouse = value end
        function frame:SetMovable(value) self.movable = value end
        function frame:SetResizable(value) self.resizable = value end
        function frame:SetResizeBounds(...) self.bounds = {...} end
        function frame:SetClampedToScreen() end
        function frame:SetScale(value) self.scale = value end
        function frame:GetEffectiveScale() return self.scale end
        function frame:SetFrameLevel(value) self.level = value end
        function frame:GetFrameLevel() return self.level or 1 end
        function frame:SetSize(width, height)
            self.width, self.height = width, height
            if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, width, height) end
        end
        function frame:SetWidth(value) self.width = value end
        function frame:SetHeight(value) self.height = value end
        function frame:GetWidth()
            -- Blizzard's dock is horizontally stretched: SetWidth alone cannot shrink it.
            if #self.points > 1 and self.points[1][2] == self.points[2][2] then return self.points[1][2]:GetWidth() + (self.points[2][4] or 0) - (self.points[1][4] or 0) end
            return self.width
        end
        function frame:GetHeight() return self.height end
        function frame:SetPoint(...) self.points[#self.points + 1] = {...} end
        function frame:ClearAllPoints() self.points = {} end
        function frame:SetAllPoints(owner) self.all = owner end
        function frame:GetPoint(index) return unpack(self.points[index or 1] or {}) end
        function frame:GetNumPoints() return #self.points end
        function frame:GetLeft()
            local p = self.points[1]
            return p and (p[2] and p[2]:GetLeft() or 0) + (p[4] or 0) or 0
        end
        function frame:GetBottom()
            local p = self.points[2] or self.points[1]
            return p and (p[2] and p[2]:GetBottom() or 0) + (p[5] or 0) or 0
        end
        function frame:StartMoving() assert(self.movable); self.moving = true end
        function frame:StartSizing() assert(self.resizable); self.sizing = true end
        function frame:StopMovingOrSizing() self.moving, self.sizing = nil, nil end
        function frame:IsProtected() return self.explicitProtected or self == ChatFrame1 and protected end
        function frame:Show()
            local before = self.shown; self.shown = true
            if not before and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function frame:Hide()
            local before = self.shown; self.shown = false
            if before and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function frame:IsShown() return self.shown end
        function frame:IsVisible() return self.shown end
        function frame:SetShown(value) self.shown = value end
        function frame:SetAlpha(value) self.alpha = value end
        function frame:GetAlpha() return self.alpha end
        function frame:SetTexture(value) self.texture = value end
        function frame:SetColorTexture(...) self.color = {...} end
        function frame:GetName() return self.name end
        function frame:HasFocus() return self.focused == true end
        function frame:SetText(value) self.text = value end
        function frame:CreateAnimationGroup()
            local group = { animations = {}, plays = 0 }
            function group:CreateAnimation(kind)
                local animation = { kind = kind }
                function animation:SetFromAlpha(value) self.fromAlpha = value end
                function animation:SetToAlpha(value) self.toAlpha = value end
                function animation:SetScaleFrom(...) self.scaleFrom = {...} end
                function animation:SetScaleTo(...) self.scaleTo = {...} end
                function animation:SetOrigin(...) self.origin = {...} end
                function animation:SetDuration(value) self.duration = value end
                function animation:SetSmoothing(value) self.smoothing = value end
                function animation:SetOrder(value) self.order = value end
                function animation:SetOffset(x, y) self.offsetX, self.offsetY = x, y end
                self.animations[#self.animations + 1] = animation
                return animation
            end
            function group:Stop() self.playing = false end
            function group:Play() self.playing = true; self.plays = self.plays + 1 end
            self.animationGroups = self.animationGroups or {}
            self.animationGroups[#self.animationGroups + 1] = group
            return group
        end
        return frame
    end
    UIParent = Frame()
    ChatFrame1 = Frame(UIParent)
    ChatFrame1.name, ChatFrame1.editBox = "ChatFrame1", Frame()
    ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 12, 12)
    ChatFrame1Tab = Frame()
    GENERAL_CHAT_DOCK = Frame()
    local nativeRelative = flavor == "Forever" and Frame(ChatFrame1) or ChatFrame1
    GENERAL_CHAT_DOCK:SetPoint("BOTTOMLEFT", nativeRelative, "TOPLEFT", 0, 3)
    GENERAL_CHAT_DOCK:SetPoint("BOTTOMRIGHT", nativeRelative, "TOPRIGHT", 0, 3)
    GENERAL_CHAT_DOCK.selected = ChatFrame1
    EditModeManagerFrame = Frame()
    EditModeManagerFrame:Hide()
    CHAT_FRAME_FADE_OUT_TIME = 2
    hooksecurefunc = function(name, fn) hooks[name] = fn end
    ChatFrameUtil = {
        OpenChat = function(_, frame) eq(frame, GENERAL_CHAT_DOCK.selected); inputs = inputs + 1; frame.editBox.focused = true end,
        DeactivateChat = function(box) box.focused = false end,
    }
    local canCreate, canOpenPanel = true, true
    FCF_CanOpenNewWindow = function() return canCreate end
    local prompt, createdTab, filters, copiesFromDefault = nil, 0, nil, 0
    NAME_CHAT_WINDOW, DEFAULT_CHAT_FRAME = "Name chat window", ChatFrame1
    ChatConfigFrame = Frame()
    ChatConfigFrame:Hide()
    ChatConfigFrame.ChatTabManager = { UpdateSelection = function(_, index) filters = index end }
    ShowUIPanel = function(panel) eq(panel, ChatConfigFrame); panel:Show() end
    local nativeTab = Frame()
    FCF_OpenNewWindow = function(name) eq(name, "Guild"); createdTab = createdTab + 1; return nativeTab, 4 end
    FCF_CopyChatSettings = function(frame, source)
        eq(frame, nativeTab); eq(source, ChatFrame1); copiesFromDefault = copiesFromDefault + 1
    end
    FCF_DockUpdate = function() end
    FCFDock_UpdateTabs = function()
        layouts = layouts + 1
        -- The native layout's post-hook re-enters the toolbar layout.
        if layouts > 8 then error("recursive native tab layout") end
        if hooks.layout then hooks.layout() end
    end
    local config = Support.CatalogDefaults(root, "chat")
    config.headerToolbar, config.toolbarLocked = true, true
    local NS = { InCombat = function() return combat end, IsCombatLocked = function() return lockdown end,
        Safety = { IsForbidden = function(frame) return frame.forbidden == true end }, RestrictedNotice = function() return "combat" end }
    local S = {
        Finite = function(value) return type(value) == "number" and value == value end,
        Public = function() return true end, Text = function(value) return value end,
        RGB = function() return 1, 1, 1 end,
        CreateFrame = function(_, _, parent) return Frame(parent) end,
        CreateTexture = function(parent) return Frame(parent) end,
        CreateFontString = function(parent) return Frame(parent) end,
        Print = function() end, Queue = function() end, Open = function(id) eq(id, "chat") end,
        CanOpenNativeWindow = function() return canOpenPanel end,
        AskText = function(key, data)
            eq(key, "chat-new-tab"); eq(data.maxLetters, 31)
            opened, prompt = opened + 1, data.callback
        end,
        Set = function(_, key, value) config[key] = value end,
    }
    S.CommitEditPosition = function(id, values)
        eq(id, "chat"); assert(not lockdown)
        commits = commits + 1
        for key, value in pairs(values) do config[key] = value end
        return true
    end
    local context = { properties = {}, points = {} }
    function context:Property(frame, getter, setter, value)
        assert(not lockdown, "geometry write in lockdown")
        local all = self.properties[frame] or {}; self.properties[frame] = all
        local record = all[setter] or { before = frame[getter](frame), getter = getter }; all[setter] = record
        frame[setter](frame, value); record.applied = value
    end
    function context:RestoreProperty(frame, setter)
        local all = self.properties[frame]
        local record = all and all[setter]
        if not record then return end
        if frame[record.getter](frame) == record.applied then frame[setter](frame, record.before) end
        all[setter] = nil
    end
    function context:Anchor(frame, ...)
        assert(not lockdown, "anchor write in lockdown")
        if not self.points[frame] then self.points[frame] = { before = frame.points } end
        frame:ClearAllPoints(); frame:SetPoint(...)
        self.points[frame].applied = frame.points
    end
    function context:RestorePoints(frame)
        local record = self.points[frame]
        if not record then return end
        if frame.points == record.applied then frame.points = record.before end
        self.points[frame] = nil
    end
    function context:After(_, fn) waits[fn] = true end
    function context:Cancel(fn) waits[fn] = nil end
    local P = { NS = NS, Suite = S }
    local function Load(name)
        local path = root .. "/MSUF_Suite_Chat/" .. name .. ".lua"
        local patch = arg[2] and assert(patches[arg[2]], "unknown mutation")
        if patch and patch[1] == name then
            local file = assert(io.open(path, "rb"))
            local source = file:read("*a"); file:close()
            local first, last = source:find(patch[2], 1, true)
            assert(first, "mutation site missing")
            source = source:sub(1, first - 1) .. patch[3] .. source:sub(last + 1)
            assert(loadstring(source, "@" .. path))("chat", P)
        else
            assert(loadfile(path))("chat", P)
        end
    end
    Load("Shared"); Load("Positions"); Load("ToolbarGeometry"); Load("Toolbar"); Load("MinimalChrome"); Load("Fade"); Load("InputAnimation")
    local C, M = P.Chat, P.Chat.M
    M.active, M.config, M.context = true, config, context
    M.visuals[ChatFrame1] = { frame = ChatFrame1 }
    C.MessageFadeFocus, C.StopFadeAnimation, C.PrepareFadeAnimations = function() end, function() end, function() end
    C.FadePart = function(visual, index, alpha) visual.fadeParts[index]:SetAlpha(alpha); visual.fadeApplied[index] = alpha end
    C.OpenCopyDialog = function(module, frame) eq(module, M); eq(frame, GENERAL_CHAT_DOCK.selected); copies = copies + 1 end
    hooks.layout = C.LayoutToolbarDock
    -- The mover bounds use the drawn padding/sidebar, not Blizzard's selection.
    UIParent.width, UIParent.height = 1920, 1080
    M.positionFrame, S.editMode = ChatFrame1, true
    config.sidebarPanel, config.padding = false, 4
    ChatFrame1:ClearAllPoints(); ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 4, 4)
    C.UpdateWindowMoverBounds(M)
    eq(C.GetWindowMoverFrame():GetLeft(), 0, "painted panel left edge cannot reach corner")
    eq(C.GetWindowMoverFrame():GetBottom(), 0, "painted panel bottom edge cannot reach corner")
    config.sidebarPanel, config.sidebarSide, config.sidebarWidth = true, 1, 28
    ChatFrame1:ClearAllPoints(); ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 4)
    C.UpdateWindowMoverBounds(M)
    eq(C.GetWindowMoverFrame():GetLeft(), 0, "left sidebar is outside mover bounds")
    config.sidebarSide = 2
    ChatFrame1:ClearAllPoints(); ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 4, 4)
    C.UpdateWindowMoverBounds(M)
    eq(C.GetWindowMoverFrame():GetWidth(), 516, "right sidebar is outside mover bounds")
    config.tabPanel, config.headerToolbar = false, false
    C.UpdateWindowMoverBounds(M)
    eq(C.GetWindowMoverFrame().points[1][5], 24, "tabless sidebar escapes the mover top")
    config.tabPanel, config.headerToolbar = true, true
    config.sidebarPanel, S.editMode = false, false
    ChatFrame1:ClearAllPoints(); ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 12, 12)
    C.ApplyToolbar(); C.LayoutToolbarDock()
    eq(#M.toolbar.buttons, 5); eq(GENERAL_CHAT_DOCK:GetWidth(), 372)
    eq(select(2, GENERAL_CHAT_DOCK:GetPoint(1)), nativeRelative, "client-native anchor lost")
    eq(layouts, 1)
    local frames = created
    collectgarbage("collect"); collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 1000 do C.LayoutToolbarDock() end
    local allocated = collectgarbage("count") - before
    collectgarbage("restart")
    assert(allocated < 1, "stable dock layout allocates: " .. allocated)
    eq(created, frames); eq(layouts, 1, "stable header forced native layouts")
    config.tabX, config.tabY = 10, 6
    C.LayoutToolbarDock()
    eq(select(4, GENERAL_CHAT_DOCK:GetPoint(1)), 10, "changed tab offset was ignored")
    eq(select(5, GENERAL_CHAT_DOCK:GetPoint(1)), 9)
    config.tabX, config.tabY = 0, 0
    C.LayoutToolbarDock()
    local sample = Frame()
    C.PaintToolbar(sample, config, false)
    eq(#sample.buttons, 5); eq(sample.buttons[1].scripts.OnClick, nil, "preview has live actions")
    eq(sample.buttons[1].strokes[1].width, M.toolbar.buttons[1].strokes[1].width)
    local buttons = M.toolbar.buttons
    buttons[1].scripts.OnClick(buttons[1]); eq(opened, 1)
    canCreate = false
    prompt("Guild"); eq(createdTab, 0, "tab capacity was not rechecked when naming finished")
    buttons[1].scripts.OnClick(buttons[1]); eq(opened, 1, "tab dialog opened without a native slot")
    canCreate = true
    prompt("Guild")
    eq(createdTab, 1, "the name did not reach native tab creation")
    eq(copiesFromDefault, 1, "new tab lost native copy-settings behavior")
    eq(filters, 4, "native filters opened the wrong tab")
    canOpenPanel = false
    ChatConfigFrame:Hide()
    filters = nil
    prompt("Guild")
    eq(createdTab, 2, "Gamepad mode could not create a native tab")
    eq(filters, nil, "Gamepad mode tried to open the native filter panel")
    eq(ChatConfigFrame:IsShown(), false, "Gamepad mode showed the native filter panel")
    buttons[2].scripts.OnClick(buttons[2]); eq(inputs, 1)
    buttons[2].scripts.OnClick(buttons[2]); eq(ChatFrame1.editBox.focused, false)
    combat = true
    buttons[1].scripts.OnClick(buttons[1]); eq(opened, 1, "tab created during combat")
    buttons[3].scripts.OnClick(buttons[3]); eq(copies, 1, "public copy unavailable in combat")
    buttons[4].scripts.OnClick(buttons[4]); eq(config.toolbarLocked, true)
    combat = false
    buttons[4].scripts.OnClick(buttons[4]); eq(config.toolbarLocked, false)
    C.ApplyToolbarGeometry()
    combat = true
    M.toolbarDrag.scripts.OnDragStart(M.toolbarDrag); eq(M.toolbarGesture, nil, "gesture began at combat edge")
    combat = false
    protected = true
    M.toolbarDrag.scripts.OnDragStart(M.toolbarDrag); eq(M.toolbarGesture, nil)
    protected = false
    M.toolbarDrag.scripts.OnDragStart(M.toolbarDrag)
    assert(M.toolbarGesture); eq(ChatFrame1.movable, nil, "native movable state written")
    local proxy = M.toolbarProxy
    proxy:ClearAllPoints(); proxy:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 170, 80)
    M.toolbarDrag.scripts.OnDragStop(M.toolbarDrag)
    eq(commits, 1); eq(config.windowX, 170); eq(config.windowY, 80)
    eq(M.toolbarGesture, nil); eq(select(2, ChatFrame1:GetPoint()), UIParent)
    M.toolbarResize.scripts.OnDragStart(M.toolbarResize)
    proxy:SetSize(560, 240)
    eq(ChatFrame1:GetWidth(), 560); eq(ChatFrame1:GetHeight(), 240)
    combat = true -- event-derived combat precedes lockdown
    proxy.scripts.OnEvent(proxy, "PLAYER_REGEN_DISABLED")
    eq(commits, 2); eq(config.windowWidth, 560); eq(M.toolbarGesture, nil)
    eq(ChatFrame1:GetWidth(), 560, "combat edge reverted visible size")
    lockdown = true
    M.toolbarDrag.scripts.OnDragStart(M.toolbarDrag); eq(M.toolbarGesture, nil)
    combat, lockdown = false, false
    M.toolbarDrag.scripts.OnDragStart(M.toolbarDrag)
    M.config = {}; C.StopToolbarGesture(true); eq(commits, 2, "drag crossed profiles")
    M.config = config
    -- Narrow windows retain native static tabs: tools move to the row above.
    ChatFrame1:SetWidth(200)
    C.LayoutToolbarDock()
    eq(GENERAL_CHAT_DOCK:GetNumPoints(), 2)
    eq(GENERAL_CHAT_DOCK.width, 480, "latent native width was not restored before stretching")
    eq(C.HeaderTop(config, ChatFrame1), config.tabHeight + config.tabPanelGap + 24)
    -- Idle/minimal chrome owns the same toolbar used for the selected dock.
    config.idleSeconds, config.idleAlpha = 10, 0
    C.ApplyToolbar()
    local visual = M.visuals[ChatFrame1]
    visual.fadeCallback(); eq(M.toolbar:GetAlpha(), 0, "header survived idle fade")
    C.ChatActivity(ChatFrame1); eq(M.toolbar:GetAlpha(), 1, "header did not wake")
    config.minimalChrome = true
    C.UpdateMinimalChrome(visual, false); eq(M.toolbar:GetAlpha(), 0)
    C.ToolbarHover(buttons[1], true)
    hooks.FCF_FadeOutChatFrame(ChatFrame1)
    eq(M.toolbar:GetAlpha(), 1, "wrapped controls faded under pointer")
    visual.fadeCallback(); eq(M.toolbar:GetAlpha(), 1, "idle fade ignored toolbar hover")
    C.ToolbarHover(buttons[1], false)
    hooks.FCF_FadeInChatFrame(ChatFrame1); eq(M.toolbar:GetAlpha(), 1)
    hooks.FCF_FadeOutChatFrame(ChatFrame1); eq(M.toolbar:GetAlpha(), 0)
    C.ReleaseToolbar(); eq(M.toolbar:IsShown(), false); eq(M.toolbarResize:IsShown(), false)
    eq(GENERAL_CHAT_DOCK:GetNumPoints(), 2)
    local input = ChatFrame1.editBox
    C.ApplyInputAnimation(M, input)
    eq(input.animationGroups, nil, "disabled animation allocated a group")
    input:SetHeight(32)
    config.animateInput, config.inputAnimationDuration = true, 0.23
    C.ApplyInputAnimation(M, input)
    local animation = input.animationGroups[1]
    eq(#animation.animations, 3); eq(animation.plays, 0, "refresh unexpectedly animated the live chat")
    input:Hide()
    combat, lockdown = true, true
    input:Show(); input.scripts.OnEditFocusGained(input)
    eq(animation.plays, 1, "input animation failed in combat")
    eq(animation.animations[1].duration, 0.23 * 0.65)
    eq(animation.animations[1].kind, "Alpha"); eq(animation.animations[1].order, 2)
    eq(animation.animations[2].kind, "Translation"); eq(animation.animations[2].order, 1)
    eq(animation.animations[2].duration, 0); eq(animation.animations[2].offsetY, -24)
    eq(animation.animations[3].kind, "Translation"); eq(animation.animations[3].order, 2)
    eq(animation.animations[3].duration, 0.23); eq(animation.animations[3].offsetY, 24)
    eq(animation.animations[2].offsetY + animation.animations[3].offsetY, 0, "input animation snaps at its end")
    input:Hide(); eq(animation.playing, false, "hidden input kept animating")
    config.animateInput = false
    C.ApplyInputAnimation(M, input)
    input:Show(); input.scripts.OnEditFocusGained(input)
    eq(animation.plays, 1, "disabled input still animated")
    combat, lockdown = false, false
    config.animateInput = true
    sample:SetHeight(input:GetHeight())
    S.ChatPreviewInputAnimation(sample, config)
    local preview = sample.animationGroups[1]
    eq(preview.plays, 1); eq(preview.animations[1].duration, animation.animations[1].duration)
    eq(preview.animations[2].offsetY, animation.animations[2].offsetY)
    eq(preview.animations[3].offsetY, animation.animations[3].offsetY)
    config.inputTop = true
    S.ChatPreviewInputAnimation(sample, config)
    eq(preview.animations[2].offsetY, 24, "top input did not enter from above")
    eq(preview.animations[3].offsetY, -24)
    config.inputTop = false
    config.animateInput = false
    S.ChatPreviewInputAnimation(sample, config); eq(preview.playing, false)
    config.animateInput = true
    C.ApplyInputAnimation(M, input)
    input.scripts.OnEditFocusGained(input)
    local activations = animation.plays
    input.scripts.OnEditFocusLost(input)
    input.scripts.OnEditFocusGained(input)
    eq(animation.plays, activations + 1, "persistent IM input did not animate on reactivation")
    C.StopInputAnimations(); eq(animation.playing, false)
    print(flavor .. " chat header: native anchors/overflow, actions, preview, drag/resize, combat, restoration and idle budget passed")
end

Run("Mainline")
Run("Forever")
