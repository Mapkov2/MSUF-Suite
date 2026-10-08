local root = assert(arg[1], "repository root required")
local selected = arg[2]
local function Load(path, private) return assert(loadfile(root .. "/" .. path))("Suite", private) end
local function Upvalue(fn, wanted, seen)
    seen = seen or {}
    if seen[fn] then return end
    seen[fn] = true
    for i = 1, 200 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
    for i = 1, 200 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if type(value) == "function" then
            local found = Upvalue(value, wanted, seen)
            if found then return found end
        end
    end
end
local function Case(name, callback)
    if not selected or selected == name then callback(); print(name .. " passed") end
end

Case("host-suppression-boundary", function()
    local ns, suite = {}, {}
    Load("MSUF_Suite/Core/HostBridge.lua", ns)
    local record = { isEnabled = function() return true end }
    MSUF_EM2 = { ExternalElements = { GetRecord = function(key) assert(key == "Blizzard.Minimap"); return record end } }
    local bridge, calls = ns.HostBridge, 0
    local suppress = bridge.SuppressEditElement
    bridge.SuppressEditElement = function(...) calls = calls + 1; return suppress(...) end
    Load("MSUF_Suite_Modules/EditMode.lua", { NS = ns, Suite = suite })
    suite.SuppressHostElement("minimap", "Blizzard.Minimap", true)
    assert(calls == 1 and not record.isEnabled(), "runtime bypassed the host bridge")
    suite.SuppressHostElement("minimap", "Blizzard.Minimap", false)
    assert(record.isEnabled(), "release did not restore original availability")
    suite.SuppressHostElement("minimap", "Blizzard.Minimap", true)
    record = { isEnabled = function() return true end }
    bridge.RefreshSuppressedEditElements()
    assert(not record.isEnabled(), "recreated host record escaped its active claim")
    MSUF_EM2 = nil
end)

Case("category-profile", function()
    local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
    for _, client in ipairs({ "Mainline", "Forever" }) do
        for _, action in ipairs({ "save", "add", "remove", "down" }) do
            local W = H.New(root, { client = client, config = { customCategories = "1|A|101\n1|Second|102" } })
            W.Apply()
            local editor = W.P.InventoryEditor
            W.NS.DB = {}
            editor.Show()
            W.NS.DB = {}
            W.config.customCategories = "1|B|202"
            editor.name:SetText("Stale")
            editor[action]:GetScript("OnClick")(editor[action])
            assert(W.config.customCategories == "1|B|202", action .. " crossed the profile boundary")
            assert(not editor.frame:IsShown(), "stale editor remained open")
        end
        local W = H.New(root, { client = client })
        W.Apply()
        W.NS.DB = {}
        local editor, state = W.P.InventoryEditor, W.S.ModuleState("bags")
        state.pinned = { [101] = true }
        editor.ShowPinned()
        assert(editor.categories[1].items ~= state.pinned, "pins edit buffer aliases live data")
        editor.categories[1].items[202] = true
        assert(not state.pinned[202], "a draft mutated pins before Save")
        -- Use the real database activation and registry path, including returning
        -- to the same profile table and a same-table import notification.
        Load("MSUF_Suite/Core/Database.lua", W.NS)
        W.NS.ProfileVariants = { CanMutate = function() return true end, OnActivated = function() end }
        local profileA, profileB = {}, {}
        W.NS.RootDB.profiles = { A = profileA, B = profileB }
        assert(W.NS.Database.Activate("A"))
        for _, operation in ipairs({ "roundtrip", "in-place", "close" }) do
            W.config.customCategories = "1|Current|101"
            editor.Show()
            editor.name:SetText("Stale draft")
            if operation == "roundtrip" then
                assert(W.NS.Database.Activate("B"))
                assert(W.NS.Database.Activate("A"))
            elseif operation == "in-place" then
                W.NS.OnProfileChanged("A")
            else
                editor.frame:Hide()
            end
            W.config.customCategories = "1|Updated|202"
            editor.save:GetScript("OnClick")(editor.save)
            assert(W.config.customCategories == "1|Updated|202", operation .. " revived stale category draft")
            assert(not editor.open and editor.profile == nil and not editor.frame:IsShown(), operation .. " retained editor session")
        end
        editor.Show()
        editor.name:SetText("Fresh")
        editor.save:GetScript("OnClick")(editor.save)
        assert(W.config.customCategories:find("Fresh", 1, true), "fresh editor stopped saving")
    end
end)

Case("announcements", function()
    local module
    GetTime = function() return 100 end
    local suite = { Public = function() return true end, PublicText = function(v) return type(v) == "string" and v ~= "" and v end,
        Number = function(v) return type(v) == "number" end, ReadText = function(fn, ...) return fn(...) end,
        Dispatch = function(fn, ...) return fn(...) end, Text = function(v) return v end,
        Install = function(_, value) module = value end }
    Load("MSUF_Suite_Modules/Announcements.lua", { Suite = suite, NS = { Safety = { IsForbidden = function() return false end } } })
    local event, alert = Upvalue(module.Enable, "Event"), Upvalue(module.ApplyNative, "OnShowAlert")
    local label = { SetText = function() end, SetTextColor = function() end }
    module.active, module.config = true, { quests = true, duration = 4 }
    module.context = { After = function() end }
    module.host = { SetAlpha = function() end, Show = function() end }
    module.enter = { Stop = function() end, Play = function() end }; module.leave = module.enter
    module.title, module.subtitle = label, label
    module.accent, module.divider = { SetColorTexture = function() end }, { SetColorTexture = function() end }
    module.kindColors = { quest = { 0, 1, 0 }, zone = { 1, 0, 0 } }
    C_QuestLog = { GetTitleForQuestID = function() return "Same title" end }
    local system = {}
    module.alertHooks = { [system] = "quests" }
    for _, reversed in ipairs({ false, true }) do
        module.queue, module.current, module.showing, module.lastKey = {}, nil, false, nil
        local data = { taskName = "Same title", questID = 123 }
        if reversed then alert(system, data); event(module, "QUEST_TURNED_IN", 123)
        else event(module, "QUEST_TURNED_IN", 123); alert(system, data) end
        assert(module.current.kind == "quest" and #module.queue == 0, "completion duplicated or used zone color")
        alert(system, { taskName = "Same title", questID = 124 })
        assert(#module.queue == 1, "distinct quest identity was deduplicated")
    end
end)

Case("objective-deadline", function()
    local now = 100
    GetTime = function() return now end
    local suite = { Text = function(v) return v end, Public = function() return true end,
        PublicText = function(v) return v end, Finite = function(v) return type(v) == "number" end,
        SetStyledFont = function() end, ClockText = function(v) return tostring(math.ceil(v)) end }
    local private = { Suite = suite }
    Load("MSUF_Suite_Modules/ObjectivesData.lua", private)
    local objectives = private.Objectives
    local collectors = assert(Upvalue(objectives.CollectDirty, "COLLECTORS"))
    collectors.quests = function(list) list.count = 1; list[1] = { timeLeft = 60 } end
    local owner = { sources = {}, dirty = { quests = true }, config = {} }
    objectives.CollectDirty(owner)
    local cached = owner.sources.quests[1]
    assert(cached.timerEnd == 160, "source did not capture one absolute deadline")
    Load("MSUF_Suite_Modules/ObjectivesTracker.lua", private)
    local paint = assert(Upvalue(objectives.Render, "PaintRowWidgets"))
    local timer = { Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
        ClearAllPoints = function() end, SetPoint = function() end, SetWidth = function() end,
        SetTextColor = function() end, SetText = function(self, text) self.text = text end }
    local row = { timer = timer, collapse = { Hide = function() end } }
    owner.active, owner.font, owner.mutedRGB, owner.timedRows = true, "native", {1,1,1}, {}
    owner.countdownJob = { Request = function() end }
    cached.kind = "entry"
    paint(owner, row, cached, {1,1,1}, 15)
    now = 130
    paint(owner, row, cached, {1,1,1}, 15)
    objectives.UpdateTimers(owner)
    assert(row.timerEnd == 160 and timer.text == "30", "repaint restarted the objective timer")
    now = 161
    paint(owner, row, cached, {1,1,1}, 15)
    objectives.UpdateTimers(owner)
    assert(not timer.shown and not row.timerEnd, "expired cached timer reappeared")
end)

Case("minimap-reset-layout", function()
    local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
    for _, client in ipairs({ "Mainline", "Forever" }) do
        local W = H.New(root, client)
        W.editModeReady = true
        H.Enable(W); W.Step()
        assert(type(W.MM.park.Layout) == "function", "parked Blizzard alert lost parent Layout")
        W.MM.park:Layout()
        assert(W.S.Reset("minimap")); W.Step()
        assert(W.S.SetMany("minimap", { size = 287, x = -75, y = -82 }))
        assert(W.S.Set("minimap", "enabled", false))
        assert(W.S.Set("minimap", "enabled", true)); W.Step()
        local c = W.S.Config("minimap")
        assert(c.size == 287 and c.x == -75 and c.y == -82, "post-reset edits were recaptured")
    end
end)

Case("bank-label-style", function()
    local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
    local W = H.New(root, { client = "Mainline" })
    W.Apply()
    local paint = assert(Upvalue(W.P.BankInventory.Refresh, "StyleItem"))
    local calls = 0
    local button = { level = { SetText = function() end, Show = function() end, Hide = function() end }, Count = {} }
    button.levelStyle = { label = button.level }
    W.M.StyleItemLevel = function(_, record)
        assert(record.label == button.level); calls = calls + 1
    end
    W.M.PaintItemLevelQuality = function(_, record, quality)
        assert(record == button.levelStyle and quality == 4); calls = calls + 1
    end
    W.S.SetFont = function() end
    SetItemButtonDesaturated = function() end
    paint(button, { quality = 4, level = 640 }, "font")
    assert(calls == 2, "organized bank bypassed the shared bag level-label style")
end)

Case("group-note-profile", function()
    local module, writes, profile = nil, 0, {}
    local function Widget()
        local w = { scripts = {}, shown = false, text = "" }
        setmetatable(w, { __index = function(_, key)
            if key == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
            if key == "SetText" then return function(self, text) self.text = text end end
            if key == "GetText" then return function(self) return self.text end end
            if key == "Show" then return function(self) self.shown = true end end
            if key == "Hide" then return function(self) self.shown = false end end
            return function() end
        end })
        return w
    end
    local ns = { DB = profile, IsCombatLocked = function() return false end }
    local suite = { Install = function(_, value) module = value end, CreateFrame = Widget, CreateTexture = Widget,
        CreateFontString = Widget, SetStyledFont = function() end, GlobalFontPath = function() return "font" end,
        Text = function(v) return v end, Set = function(_, _, text) writes = writes + 1; module.config.note = text end }
    local opened
    LFGListApplicationDialog = { IsShown = function() return true end,
        HookScript = function(_, _, callback) opened = callback end }
    hooksecurefunc = function() end
    Load("MSUF_Suite_QualityOfLife/GroupFinderDoubleClick.lua", { NS = ns, Suite = suite })
    module.active, module.config = true, { showNote = true, note = "First" }
    module.context = { RemoveEvent = function() end }
    module:Enable(); module:Refresh()
    opened()
    local box = module.noteEdit
    assert(box.text == "First")
    module.config.note = "Changed in options"; module:Refresh()
    assert(box.text == "Changed in options", "open note did not refresh")
    box.scripts.OnEditFocusLost(box)
    assert(writes == 0, "copy/blur overwrote configured note")
    box.text = "Draft"; box.scripts.OnTextChanged(box, true); module:Refresh()
    assert(box.text == "Draft", "refresh discarded an active draft")
    ns.DB = {}; module.config.note = "Second profile"
    box.scripts.OnEditFocusLost(box)
    assert(writes == 0 and module.config.note == "Second profile", "old note draft crossed profile boundary")
end)
