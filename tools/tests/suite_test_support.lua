-- Shared by the suite contract tests (not a test itself). Files load in TOC
-- order, so the tests follow load-order changes without their own file lists.
local Support = {}
-- These native APIs exist on both supported clients. Most contracts do not
-- care about character color; tests that do supply their own fixture.
if not UnitClass then UnitClass = function() return nil end end
if not C_ClassColor then C_ClassColor = { GetClassColor = function() return nil end } end
-- The client's strsplit(delimiter, text): every piece, empty ones included.
if not strsplit then
    strsplit = function(delimiter, text)
        local pieces, start = {}, 1
        while true do
            local at = text:find(delimiter, start, true)
            if not at then break end
            pieces[#pieces + 1] = text:sub(start, at - 1)
            start = at + #delimiter
        end
        pieces[#pieces + 1] = text:sub(start)
        return unpack(pieces)
    end
end

-- The Suite's anchor point list (NS.AnchorPoints, MSUF_Suite/Core/
-- SuiteCatalog.lua), read from the shipped file.
function Support.AnchorPoints(root)
    local file = assert(io.open(root .. "/MSUF_Suite/Core/SuiteCatalog.lua", "rb"))
    local source = file:read("*a")
    file:close()
    local list = assert(source:match("\nNS%.AnchorPoints = (%b{})"), "NS.AnchorPoints is missing from SuiteCatalog.lua")
    return assert(loadstring("return " .. list))()
end

-- Isolated QoL module tests load one file without the addon's Bootstrap.lua.
-- Install the real palette bridge (with the cards and S.PlaceHost) with a
-- minimal core namespace that has the Suite's anchor points, and the shared
-- windows and copy dialog (MSUF_Suite_Modules/Dialogs.lua). palettes
-- (optional) replaces the single default palette.
function Support.QoLStyleFixture(root, suite, palettes)
    assert(loadfile(root .. "/MSUF_Suite_Modules/Dialogs.lua"))("MSUF_Suite_Modules", { Suite = suite })
    suite.RGB = suite.RGB or function() return 1, 1, 1 end
    local previous = _G.MSUFSuite
    _G.MSUFSuite = { Suite = suite, QoLVisualStyles = palettes or {
        [1] = { background = "0a1220", border = "41627a", accent = "57c7df",
            text = "f4f7fb", muted = "aab5c2" },
    }, Finish = function(callback, ...) return true, callback(...) end, AnchorPoints = Support.AnchorPoints(root) }
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/Bootstrap.lua"))(
        "MSUF_Suite_QualityOfLife", {})
    _G.MSUFSuite = previous
end

-- The client's dialogs for Suite questions (Blizzard_StaticPopup/
-- StaticPopup.lua, Blizzard_StaticPopup_Game/GameDialogDefs.lua and
-- GameDialog.lua; the same on upstream/live and upstream/forever).
-- StaticPopupDialogs is Blizzard's table: an entry written by an addon
-- raises. The generic confirmation and input box take text, labels and
-- callbacks as data and allow several dialogs at a time. Four dialog frames
-- are shared by every dialog, so an edit box keeps what a caller set on it
-- (SetNumeric, SetMaxLetters) into the next dialog; hiding clears its text.
-- The input box's Accept and Enter work only while its text is not empty.
-- Returns dialogs: Last(which) (the newest shown) and Count(which); Accept,
-- Cancel, Enter and Escape (the edit box's: a hide without cancel) answer
-- one.
function Support.StaticPopups()
    local dialogs, shown = { frames = {} }, {}
    local GENERIC = {
        GENERIC_CONFIRMATION = { accept = "Yes", cancel = "No" },
        GENERIC_INPUT_BOX = { accept = "Done", cancel = "Cancel", hasEditBox = true },
    }
    StaticPopupDialogs = setmetatable({}, {
        __index = GENERIC,
        __newindex = function(_, key) error("an addon wrote " .. tostring(key) .. " into Blizzard's StaticPopupDialogs") end,
    })
    local function Frame()
        local dialog = { shown = false }
        local edit = { text = "", numeric = false, maxLetters = 0 }
        function edit:SetText(value)
            self.text = value
            dialog.acceptEnabled = value ~= ""
        end
        function edit:GetText() return self.text end
        function edit:SetNumeric(value) self.numeric = value == true end
        function edit:IsNumeric() return self.numeric end
        function edit:SetMaxLetters(value) self.maxLetters = value end
        function edit:SetCountInvisibleLetters() end
        function edit:HighlightText() self.highlighted = true end
        function edit:GetParent() return dialog end
        function dialog:GetEditBox() return edit end
        function dialog:IsShown() return self.shown end
        function dialog:Hide()
            if not self.shown then return end
            self.shown = false
            for i = #shown, 1, -1 do
                if shown[i] == self then table.remove(shown, i) end
            end
            local onHide = self.onHide
            self.onHide = nil
            if onHide then onHide(self) end
            edit:SetText("")
        end
        return dialog
    end
    for i = 1, 4 do dialogs.frames[i] = Frame() end
    local function Cancel(dialog)
        local data = dialog.data
        dialog:Hide()
        if data and data.cancelCallback then data.cancelCallback() end
    end
    StaticPopup_Show = function(which, _, _, data, _, onHide)
        local info = GENERIC[which]
        if not info then error("Dialog " .. tostring(which) .. " does not exist.") end
        for _, open in ipairs(shown) do
            if open.which == which and open.data == data then Cancel(open) break end
        end
        local dialog
        for _, frame in ipairs(dialogs.frames) do
            if not frame.shown then dialog = frame break end
        end
        if not dialog then
            if data.cancelCallback then data.cancelCallback() end
            return nil
        end
        dialog.which, dialog.data, dialog.onHide = which, data, onHide
        dialog.text = string.format(data.text, data.text_arg1, data.text_arg2)
        dialog.acceptText = data.acceptText or info.accept
        dialog.cancelText = data.cancelText or info.cancel
        dialog.alert = which == "GENERIC_CONFIRMATION" and data.showAlert == true
        if info.hasEditBox then
            dialog:GetEditBox():SetMaxLetters(data.maxLetters or 24)
            dialog.acceptEnabled = dialog:GetEditBox():GetText() ~= ""
        end
        dialog.shown = true
        shown[#shown + 1] = dialog
        return dialog
    end
    StaticPopup_ShowCustomGenericConfirmation = function(data, inserted)
        StaticPopup_Show("GENERIC_CONFIRMATION", nil, nil, data, inserted)
    end
    StaticPopup_ShowCustomGenericInputBox = function(data, inserted)
        StaticPopup_Show("GENERIC_INPUT_BOX", nil, nil, data, inserted)
    end
    StaticPopup_Hide = function(which, data)
        for i = #shown, 1, -1 do
            local dialog = shown[i]
            if dialog and dialog.which == which and (not data or data == dialog.data) then dialog:Hide() end
        end
    end
    function dialogs.Last(which)
        for i = #shown, 1, -1 do
            if shown[i].which == which then return shown[i] end
        end
    end
    function dialogs.Count(which)
        local count = 0
        for _, dialog in ipairs(shown) do
            if dialog.which == which then count = count + 1 end
        end
        return count
    end
    function dialogs.Accept(dialog)
        assert(dialog and dialog.shown, "no shown dialog to accept")
        local data = dialog.data
        if dialog.which == "GENERIC_INPUT_BOX" then
            assert(dialog.acceptEnabled, "Accept is disabled while the input box is empty")
            data.callback(dialog:GetEditBox():GetText())
        else
            data.callback()
        end
        dialog:Hide()
    end
    function dialogs.Enter(dialog)
        if not dialog.acceptEnabled then return end
        dialog.data.callback(dialog:GetEditBox():GetText())
        dialog:Hide()
    end
    dialogs.Cancel = Cancel
    function dialogs.Escape(dialog) dialog:Hide() end
    return dialogs
end

-- Opt-in: the shipped combat and restriction rules of MSUF_Suite/Core/
-- Platform.lua (Suite.InCombat, ChatLocked, GroupActionsRestricted,
-- RestrictedNotice) for module tests with a stub core namespace. env holds
-- the client functions they read (InCombatLockdown, UnitAffectingCombat,
-- C_ChatInfo, C_RestrictedActions, Enum); Text translates like the test's
-- Suite.Text. The player's combat flag (UnitAffectingCombat("player")) is
-- true from PLAYER_REGEN_DISABLED, before the lockdown, to
-- PLAYER_REGEN_ENABLED; without a flag of its own, a test gets one that
-- follows its lockdown.
function Support.Platform(root, env)
    if not env.UnitAffectingCombat and env.InCombatLockdown then
        local locked = env.InCombatLockdown
        env.UnitAffectingCombat = function(unit)
            assert(unit == "player", "the combat rules read the player's combat flag only")
            return locked()
        end
    end
    local file = assert(io.open(root .. "/MSUF_Suite/Core/Platform.lua", "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local block = assert(source:match("\n(function Suite%.InCombat%(event%)\n.-\nfunction Suite%.RestrictedNotice%(%)\n.-\nend)\n"),
        "the combat and restriction rules are missing from Platform.lua")
    local chunk = assert(loadstring("local Suite = ...\n" .. block .. "\nreturn Suite"))
    setfenv(chunk, env)
    return chunk({ Text = env.Text or function(text) return text end })
end

-- The client sends PLAYER_REGEN_DISABLED while InCombatLockdown() is still
-- false; tests fire that event first and only then turn their lockdown on.
-- isFighting (optional) is the player's combat flag, which is already true
-- then.
function Support.InCombat(root, isLocked, isFighting)
    return Support.Platform(root, { InCombatLockdown = isLocked, UnitAffectingCombat = isFighting }).InCombat
end

-- The client's slash command registry (Blizzard_ChatFrameBase/Shared:
-- ChatFrameSetup.lua, ChatFrameUtil.lua ImportListToHash, ChatFrameEditBox.lua
-- ParseText). SlashCmdList carries a proxy metatable; every typed command
-- first imports the list (aliases into hash_SlashCmdList, handlers into the
-- proxy, list wiped) and then runs what hash_SlashCmdList holds.
function Support.SlashRegistry()
    local proxy = {}
    SlashCmdList = setmetatable({}, { __index = proxy })
    hash_SlashCmdList = {}
    local registry = { proxy = proxy }
    function registry.Import()
        local imported = {}
        for key, handler in pairs(SlashCmdList) do
            local index = 1
            local tag = _G["SLASH_" .. key .. index]
            while tag do
                hash_SlashCmdList[tag:upper()] = handler
                index = index + 1
                tag = _G["SLASH_" .. key .. index]
            end
            proxy[key] = handler
            imported[#imported + 1] = key
        end
        for _, key in ipairs(imported) do rawset(SlashCmdList, key, nil) end
    end
    -- Returns true when a handler ran for the typed text.
    function registry.Type(text)
        registry.Import()
        local command, message = text:match("^(/%S+)%s*(.-)$")
        local handler = hash_SlashCmdList[command:upper()]
        if not handler then return false end
        handler(message)
        return true
    end
    return registry
end

-- Blizzard_UIParentPanelManager as addon code meets it: ShowUIPanel and
-- HideUIPanel refuse a call from addon code in combat (the "interface action
-- blocked" message, no Lua error); otherwise the secure delegate shows or
-- hides the panel. ToggleCharacter runs CharacterFrame's tab code in the
-- caller's context, which addon code must not do. inCombat() is the
-- fixture's InCombatLockdown().
function Support.UIPanels(inCombat)
    local panels = { shown = 0, hidden = 0, blocked = 0 }
    InCombatLockdown = inCombat
    ShowUIPanel = function(frame)
        if inCombat() then panels.blocked = panels.blocked + 1 return end
        if not frame:IsShown() then
            panels.shown = panels.shown + 1
            frame:Show()
        end
    end
    HideUIPanel = function(frame)
        if inCombat() then panels.blocked = panels.blocked + 1 return end
        if frame:IsShown() then
            panels.hidden = panels.hidden + 1
            frame:Hide()
        end
    end
    ToggleCharacter = function() error("ToggleCharacter ran CharacterFrame's tab code from addon code") end
    return panels
end

-- Frames that receive client events: frames:Create() is a CreateFrame stand-in;
-- frames.Fire(event, ...) runs OnEvent on every frame registered for it, as
-- the client does for a synchronous event raised inside an API call.
function Support.EventFrames()
    local frames = { list = {} }
    function frames.Create()
        local frame = { events = {}, scripts = {} }
        function frame:SetScript(name, callback) self.scripts[name] = callback end
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        frames.list[#frames.list + 1] = frame
        return frame
    end
    function frames.Fire(event, ...)
        for _, frame in ipairs(frames.list) do
            if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    return frames
end

-- Blizzard's tooltip data processor (Blizzard_SharedXMLGame/Tooltip/
-- TooltipDataHandler.lua) for isolated tooltip helper tests: post-calls per
-- tooltip type and line pre-calls are recorded; fixture.Run(kind, tooltip,
-- data) runs the post-calls of one build. Loads the shared TooltipLines.lua.
function Support.TooltipFixture(root, suite, ns)
    local fixture = { post = {}, pre = {} }
    TooltipDataProcessor = {
        AllTypes = "ALL",
        AddTooltipPostCall = function(kind, callback)
            local list = fixture.post[kind] or {}
            fixture.post[kind] = list
            list[#list + 1] = callback
        end,
        AddLinePreCall = function(kind, callback) fixture.pre[kind] = callback end,
    }
    if not canaccesstable then canaccesstable = function() return true end end
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TooltipLines.lua"))(
        "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
    function fixture.Run(kind, tooltip, data)
        for _, callback in ipairs(fixture.post[kind] or {}) do callback(tooltip, data) end
    end
    return fixture
end

-- The client's frame clock and C_Timer (UITimerDocumentation.lua): GetTime()
-- is the time of the current frame, and a callback fires on the first frame
-- at or after its due time, never inside the call that scheduled it (a delay
-- of 0 means the next frame). C_Timer.After cannot be cancelled; NewTimer and
-- NewTicker return a handle with Cancel and IsCancelled and pass it to the
-- callback. clock.Frame(dt) runs one frame, clock.Advance(seconds) frames
-- until that much time passed; clock.native counts the C_Timer calls.
function Support.Clock(start)
    local clock = { now = start or 1000, frame = 1 / 60, native = 0, tickers = 0 }
    local entries, sequence = {}, 0
    local function Add(seconds, callback)
        assert(type(seconds) == "number" and seconds == seconds, "C_Timer needs a number of seconds")
        assert(type(callback) == "function", "C_Timer needs a callback function")
        sequence = sequence + 1
        entries[#entries + 1] = { at = clock.now + math.max(0, seconds), sequence = sequence, callback = callback }
        clock.native = clock.native + 1
    end
    local function Handle()
        local handle = { cancelled = false }
        function handle:Cancel() self.cancelled = true end
        function handle:IsCancelled() return self.cancelled end
        return handle
    end
    GetTime = function() return clock.now end
    C_Timer = {
        After = Add,
        NewTimer = function(seconds, callback)
            local handle = Handle()
            Add(seconds, function()
                if handle.cancelled then return end
                handle.cancelled = true
                callback(handle)
            end)
            return handle
        end,
        NewTicker = function(seconds, callback, iterations)
            local handle, left = Handle(), iterations
            clock.tickers = clock.tickers + 1
            local function Tick()
                if handle.cancelled then return end
                if left then
                    left = left - 1
                    if left <= 0 then handle.cancelled = true end
                end
                if not handle.cancelled then Add(seconds, Tick) end
                callback(handle)
            end
            Add(seconds, Tick)
            return handle
        end,
    }
    function clock.Frame(dt)
        clock.now = clock.now + (dt or clock.frame)
        local limit = sequence
        while true do
            local best
            for i, entry in ipairs(entries) do
                if entry.sequence <= limit and entry.at <= clock.now + 1e-9 then
                    local current = entries[best]
                    if not current or entry.at < current.at
                        or (entry.at == current.at and entry.sequence < current.sequence) then best = i end
                end
            end
            if not best then return end
            table.remove(entries, best).callback()
        end
    end
    function clock.Advance(seconds)
        local target = clock.now + seconds
        repeat clock.Frame(math.min(clock.frame, target - clock.now)) until clock.now >= target - 1e-9
    end
    function clock.Queued()
        return #entries
    end
    return clock
end

-- MSUF_Suite_Modules/Timers.lua for module tests with a stub context: loads
-- the shipped timer methods once per suite table (suite.instances is the
-- module registry they read, ns.Dispatch runs the callbacks) and returns
-- Context(id, module, fields), which registers module under id and gives the
-- stub context `fields` the real ctx:After, Coalesce, Ticker and Cancel.
function Support.ModuleTimers(root, suite, ns)
    suite.instances = suite.instances or {}
    local methods = {}
    assert(loadfile(root .. "/MSUF_Suite_Modules/Timers.lua"))("MSUF_Suite_Modules",
        { NS = ns, Suite = suite, Context = methods })
    local meta = { __index = methods }
    return function(id, module, fields)
        suite.instances[id] = module
        local context = setmetatable(fields or {}, meta)
        context.id = id
        return context
    end
end

-- The named Context:Event option (Runtime.lua) of an event the module also
-- handles in combat: an options table with inCombat = true.
function Support.InCombatOption(options)
    return type(options) == "table" and options.inCombat == true
end

-- What Context:Event (Runtime.lua) registers for a callback: a job's event
-- function, since Dispatch takes functions only. Stub contexts use it too.
function Support.EventCallback(callback)
    if type(callback) == "table" then return callback:EventFunction() end
    return callback
end

-- The client's securecallfunction: an error is reported, nothing returned.
-- It takes a function only; a callable table is refused, as the client may.
function Support.Dispatcher(reported)
    return function(callback, ...)
        assert(type(callback) == "function", "securecallfunction needs a function, got " .. type(callback))
        local results = { pcall(callback, ...) }
        if not results[1] then reported[#reported + 1] = tostring(results[2]) return end
        return unpack(results, 2)
    end
end

function Support.TocFiles(root, addon, flavor)
    local path = root .. "/" .. addon .. "/" .. addon .. "_" .. (flavor or "Mainline") .. ".toc"
    local toc = assert(io.open(path, "rb"), "missing " .. path)
    local text = toc:read("*a"):gsub("\r", "")
    toc:close()
    local files = {}
    for line in text:gmatch("[^\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then files[#files + 1] = (line:gsub("\\", "/")) end
    end
    return files
end

-- Loads the addon's Lua files up to and including `through` (for example
-- "Core/Suite.lua"). Files listed in `skip` are left out.
function Support.Load(root, addon, namespace, through, skip, flavor)
    local reached = through == nil
    for _, file in ipairs(Support.TocFiles(root, addon, flavor)) do
        if file:match("%.lua$") and not (skip and skip[file]) then
            assert(loadfile(root .. "/" .. addon .. "/" .. file))(addon, namespace)
        end
        if file == through then reached = true; break end
    end
    assert(reached, tostring(through) .. " is not listed in the " .. addon .. " TOC")
    return namespace
end

-- The Suite's profile name rule (MSUF_Suite/Core/Database.lua). The skin's
-- profile store asks MSUFSuite.Database for it, as in the client, where the
-- skin loads after MSUF_Suite. Gives suite (default _G.MSUFSuite, created
-- when missing) the real Database unless it has one, publishes it as
-- _G.MSUFSuite and returns it.
function Support.SuiteProfileNames(root, suite)
    suite = suite or _G.MSUFSuite or {}
    if not suite.Database then
        local core = {}
        assert(loadfile(root .. "/MSUF_Suite/Core/Database.lua"))("MSUF_Suite", core)
        suite.Database = core.Database
    end
    _G.MSUFSuite = suite
    return suite
end

-- The step of a MIGRATIONS entry (MSUF_Suite/Core/Suite.lua) found by the
-- function it runs, and the number of steps, so that a test does not depend on
-- the order in which branches appended their steps.
function Support.MigrationStep(root, name)
    local file = assert(io.open(root .. "/MSUF_Suite/Core/Suite.lua", "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local block = assert(source:match("\nlocal MIGRATIONS = {\n(.-)\n}\n"), "MIGRATIONS table not found")
    local steps, step = 0, nil
    for line in (block .. "\n"):gmatch("(.-)\n") do
        local run = line:match("^%s*{ run = ([%w_%.]+)")
        if run then
            steps = steps + 1
            if run == name then step = steps end
        end
    end
    return assert(step, "no migration step runs " .. name), steps
end

-- One module's catalog defaults (MSUF_Suite/Core/Catalog/<file>.lua): the
-- complete config the controller hands a module whose profile changed
-- nothing. Tests then override only what they exercise.
function Support.CatalogDefaults(root, id, file, client)
    local ns = { Client = client or { isForever = false }, Text = function(text) return text end }
    assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", ns)
    file = file or (id:sub(1, 1):upper() .. id:sub(2))
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/" .. file .. ".lua"))("MSUF_Suite", ns)
    local config = {}
    for key, rule in pairs(ns.SuiteCatalog[id].rules) do config[key] = rule.default end
    return config, ns
end

return Support
