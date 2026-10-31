-- Native lifecycle fixture shared only by the comfort feature regressions.
local F = {}
function F.New(root, forever)
    local modules, frames, combat, jobs = {}, {}, false, {}
    local secret = setmetatable({}, { __tostring = function() error("secret formatted") end })
    local S = { instances = modules, Text = function(v) return v end, Public = function(v) return v ~= secret end,
        PublicText = function(v) return v ~= secret and type(v) == "string" and v or nil end,
        Finite = function(v) return v ~= secret and type(v) == "number" and v == v end,
        SetFont = function() end, RGB = function() return 1, 1, 1 end }
    local NS = { Client = { isForever = forever, HasAddOn = function() return true end }, RootDB = {}, DB = {},
        Safety = { IsForbidden = function() return false end }, Suite = S }
    NS.Public, NS.PublicText, NS.Finite, NS.Text = S.Public, S.PublicText, S.Finite, S.Text
    NS.BlizzardText = function(_, fallback) return fallback end
    NS.InCombat = function() return combat end
    NS.IsCombatLocked = NS.InCombat
    local char = {}
    NS.CharacterData = function(owner) char[owner] = char[owner] or {}; return char[owner] end
    function S.Install(id, m) modules[id] = m; m.id = id end
    function S.Set(id, key, value) modules[id].config[key] = value; modules[id]:Refresh(); return true end
    local function Frame(kind, name, parent, template)
        local f = { scripts = {}, events = {}, attrs = {}, shown = true, parent = parent, name = name, template = template }
        local function Noop() end
        for _, method in ipairs({ "SetSize", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetWidth", "SetHeight", "SetTexture",
            "SetColorTexture", "SetJustifyH", "SetTextColor", "SetWordWrap", "SetAutoFocus", "SetMaxLetters", "RegisterForClicks",
            "EnableMouseWheel", "ClearFocus" }) do f[method] = Noop end
        function f:SetScript(event, fn) self.scripts[event] = fn end
        function f:HookScript(event, fn) self.scripts[event] = fn end
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterEvent(event) self.events[event] = nil end
        function f:UnregisterAllEvents() self.events = {} end
        function f:SetAttribute(key, value) assert(not combat, "protected write in combat"); self.attrs[key] = value end
        function f:GetAttribute(key) return self.attrs[key] end
        function f:SetText(value) self.text = value; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
        function f:GetText() return self.text or "" end
        function f:SetAlpha(value) self.alpha = value end
        function f:SetEnabled(value) self.enabled = value end
        function f:SetChecked(value) self.checked = value end
        function f:GetChecked() return self.checked end
        function f:SetSize(width, height) self.width, self.height = width, height end
        function f:SetHeight(height) self.height = height end
        function f:SetPoint(...) self.point = { ... } end
        function f:ClearAllPoints() self.point = nil end
        function f:SetShown(value) self.shown = value end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        function f:IsShown() return self.shown end
        function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
        function f:GetID() return self.id end
        if template == "InputBoxInstructionsTemplate" then f.Instructions = { SetText = function() end } end
        frames[#frames + 1] = f
        if name then _G[name] = f end
        return f
    end
    S.CreateFrame, S.CreateTexture, S.CreateFontString = Frame, Frame, Frame
    S.QoLStyle = function() return { background = "111111" } end
    S.QoLColor = function() end
    local P = { NS = NS, Suite = S }
    function F.Load(name) return assert(loadfile(root .. "/" .. name))("test", P) end
    local E = { S = S, NS = NS, P = P, modules = modules, frames = frames, secret = secret, Frame = Frame }
    function E:Combat(value) combat = value end
    function E:Context()
        local ctx = { events = {} }
        function ctx:Event(event, fn) self.events[event] = fn end
        function ctx:RemoveEvent(event) self.events[event] = nil end
        function ctx:Coalesce(_, fn)
            if jobs[fn] then return jobs[fn] end
            local job = { fn = fn }
            function job:Request() self.pending = true end
            function job:Cancel() self.pending = false end
            jobs[fn] = job
            return job
        end
        return ctx
    end
    function E:Flush()
        for _, job in pairs(jobs) do if job.pending then job.pending = false; job.fn() end end
    end
    function E:Emit(m, event, ...)
        local fn = m.context.events[event]
        if fn then fn(m, event, ...) end
    end
    function E:NativeEvent(event, ...)
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    function E:Start(id, config)
        local m = assert(modules[id]); m.config, m.active, m.context = config, true, self:Context()
        m:Enable(); self:Flush(); return m
    end
    function E:Load(name) return assert(loadfile(root .. "/" .. name))("test", P) end
    return E
end
return F
