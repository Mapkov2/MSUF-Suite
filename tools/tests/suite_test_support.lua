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

-- Isolated QoL module tests load one file without the addon's Bootstrap.lua.
-- Install the real palette bridge with a minimal core namespace. palettes
-- (optional) replaces the single default palette.
function Support.QoLStyleFixture(root, suite, palettes)
    suite.RGB = suite.RGB or function() return 1, 1, 1 end
    local previous = _G.MSUFSuite
    _G.MSUFSuite = { Suite = suite, QoLVisualStyles = palettes or {
        [1] = { background = "0a1220", border = "41627a", accent = "57c7df",
            text = "f4f7fb", muted = "aab5c2" },
    }, Finish = function(callback, ...) return true, callback(...) end }
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/Bootstrap.lua"))(
        "MSUF_Suite_QualityOfLife", {})
    _G.MSUFSuite = previous
end

-- Opt-in: the shipped combat and restriction rules of MSUF_Suite/Core/
-- Platform.lua (Suite.InCombat, ChatLocked, GroupActionsRestricted,
-- RestrictedNotice) for module tests with a stub core namespace. env holds
-- the client functions they read (InCombatLockdown, C_ChatInfo,
-- C_RestrictedActions, Enum); Text translates like the test's Suite.Text.
function Support.Platform(root, env)
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
function Support.InCombat(root, isLocked)
    return Support.Platform(root, { InCombatLockdown = isLocked }).InCombat
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

-- The client's securecallfunction: an error is reported, nothing returned.
function Support.Dispatcher(reported)
    return function(callback, ...)
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
