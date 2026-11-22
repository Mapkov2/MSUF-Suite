local root = assert(arg[1], "Suite root required")

local function Run(flavor)
    issecretvalue = nil
    local fixture = assert(loadfile(root .. "/tools/tests/suite_skin_generic_windows_contract.lua"))("flight-map-fixture", flavor)
    local NS = fixture.NS
    local function Window(name, parent, kind)
        local w = fixture.frame(name)
        if name then _G[name] = w end
        w.shown, w.hooks = parent ~= nil, {}
        if parent then table.insert(parent.children, w) end
        function w:GetParent() return parent end
        function w:GetObjectType() return kind or "Frame" end
        function w:IsShown() return self.shown end
        function w:IsVisible() return self.shown and (not parent or parent:IsVisible()) end
        function w:IsProtected() return self.protected == true, false end
        function w:HookScript(event, fn)
            self.hooks[event] = self.hooks[event] or {}
            table.insert(self.hooks[event], fn)
        end
        function w:Show()
            self.shown = true
            for _, fn in ipairs(self.hooks.OnShow or {}) do fn(self) end
        end
        return w
    end
    local mail, opened, gossip = Window("MailFrame"), Window("OpenMailFrame"), Window("GossipFrame")
    local quest, activations = Window("QuestFrame"), 0
    NS.QuestWindow = {
        Activate = function(target, owner)
            assert(target == quest and owner == "blizzardWindows")
            activations = activations + 1
            return true
        end,
        Deactivate = function(target, owner) assert(target == quest and owner == "blizzardWindows") end,
    }
    local page = Window(nil, gossip)
    local goodbye = Window(nil, page, "Button")
    gossip.GreetingPanel, page.GoodbyeButton = page, goodbye
    for _, key in ipairs({"Left", "Middle", "Right"}) do
        goodbye[key] = {GetParent = function() return goodbye end}
    end
    local covered = {}
    NS.ControlSkin.ApplyButton = function(button) return button == goodbye end
    NS.Cosmetics.HideDecoration = function(region) covered[region] = true end
    local timers, deferred = {}, {}
    C_Timer = {After = function(delay, fn) assert(delay == 0); timers[#timers + 1] = fn end}
    local function NextFrame()
        local batch = timers
        timers = {}
        for _, fn in ipairs(batch) do fn() end
    end
    NS.CombatGate.RunOrDefer = function(key, fn)
        if fixture.inCombat() then deferred[key] = fn else fn() end
    end
    NS.Registry.QueueJob = function(fn) NS.CombatGate.RunOrDefer(fn, fn) end
    InCombatLockdown = fixture.inCombat
    NS.DB = {enabled = true, skins = {blizzardWindows = true}, skinCategories = {quest = false, social = true}}
    fixture.setCombat(true)
    local windows = NS.GenericWindows
    windows.PrepareInteractionWindows("blizzardWindows")
    assert(not gossip.hooks.OnShow, "disabled quest category armed the NPC window")
    NS.DB.skinCategories.quest = true
    windows.PrepareInteractionWindows("blizzardWindows")
    windows.PrepareInteractionWindows("blizzardWindows")
    assert(#mail.hooks.OnShow == 1 and #gossip.hooks.OnShow == 1, "cold login installed duplicate show handlers")
    assert(activations == 1, "cold login failed to arm the dedicated native quest pages once")
    mail:Show()
    assert(not mail.surfaceSpec, "skin ran on the native mailbox opening stack")
    NextFrame()
    assert(mail.surfaceSpec and fixture.inCombat(), "first mail opening waited until combat ended")
    opened:Show()
    opened.shown = false
    NextFrame()
    assert(not opened.surfaceSpec, "queued mail paint ran after the letter closed")
    opened:Show()
    NextFrame()
    assert(opened.surfaceSpec and fixture.inCombat(), "opening an individual letter in combat missed the skin")
    gossip:Show()
    NextFrame()
    fixture.noErrors()
    assert(gossip.surfaceSpec and covered[goodbye.Left] and covered[goodbye.Middle] and covered[goodbye.Right],
        "combat gossip greeting missed its shell or native Goodbye slices")
    mail.shown, opened.shown, gossip.shown = false, false, false
    fixture.setCombat(false)
    for _, fn in pairs(deferred) do fn() end
    assert(not mail.shown and not opened.shown and not gossip.shown, "combat end reopened an interaction")
    fixture.noErrors()
end

Run("Mainline")
Run("Forever")
print("Combat NPC greeting and mailbox openings passed on Mainline and Forever")
