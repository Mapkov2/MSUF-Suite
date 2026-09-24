-- Offline WoW stand-in for the minimap contracts. Each New() call builds an
-- isolated global environment (setfenv), a Blizzard minimap world for one
-- client family and a loaded suite, so Retail, Forever and Classic scenarios
-- run side by side in one process. Protected frames (the Minimap and every
-- ancestor of it) reject layout and visibility writes during combat unless a
-- secure state driver performs them.
local H = {}

-- Runtime files in load order across the shared and minimap AddOns.
H.MODULES = { "Bootstrap", "Host", "Input", "Elements", "Drawer",
    "Info", "Tooltips", "Controller" }

function H.New(root, client, options)
    options = options or {}
    local G = setmetatable({}, { __index = _G })
    G._G = G
    local W = { G = G, combat = false, secure = false, now = 0, timers = {}, frames = {}, drivers = {},
        hooks = 0, movers = {}, hostRecords = {}, cvars = { rotateMinimap = "0" }, calls = {} }
    local classic = client == "Vanilla" or client == "TBC" or client == "Mists"

    local function Count(key) W.calls[key] = (W.calls[key] or 0) + 1 end
    local function Visible(frame)
        while frame do
            if not frame.shown then return false end
            frame = frame.parent
        end
        return true
    end
    local function Fire(frame, script, ...)
        local handler = frame.scripts and frame.scripts[script]
        if handler then handler(frame, ...) end
        local hooks = frame.hookedScripts and frame.hookedScripts[script]
        if hooks then for i = 1, #hooks do hooks[i](frame, ...) end end
    end
    W.Fire = Fire
    local function Cascade(frame, script)
        Fire(frame, script)
        for _, child in ipairs(frame.children or {}) do
            if child.shown then Cascade(child, script) end
        end
    end
    local function Guard(frame, what)
        if W.combat and not W.secure and frame:IsProtected() then
            error("protected " .. what .. " in combat on " .. tostring(frame.name or frame.kind), 3)
        end
    end

    -- Regions (textures, font strings) share point and visibility handling.
    local R = {}
    R.__index = R
    function R:GetParent() return self.parent end
    function R:GetName() return self.name end
    function R:IsForbidden() return false end
    function R:IsShown() return self.shown end
    function R:IsVisible() return Visible(self) end
    function R:Show() self.shown = true end
    function R:Hide() self.shown = false end
    function R:SetShown(value) self.shown = value and true or false end
    function R:SetAlpha(value) self.alpha = value end
    function R:GetAlpha() return self.alpha end
    function R:ClearAllPoints() self.points = {} end
    function R:SetPoint(point, relative, relativePoint, x, y)
        if type(relative) == "number" then relative, relativePoint, x, y = self.parent, point, relative, relativePoint
        elseif relative == nil then relative, relativePoint = self.parent, point
        elseif type(relativePoint) == "number" then relativePoint, x, y = point, relativePoint, x end
        for i = 1, #self.points do
            if self.points[i][1] == point then table.remove(self.points, i); break end
        end
        self.points[#self.points + 1] = { point, relative, relativePoint or point, x or 0, y or 0 }
    end
    function R:SetAllPoints(relative) self.points = { { "TOPLEFT", relative or self.parent }, { "BOTTOMRIGHT", relative or self.parent } } end
    function R:GetPoint(i) local p = self.points[i or 1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
    function R:GetNumPoints() return #self.points end
    function R:SetSize(w, h) self.width, self.height = w, h end
    function R:SetWidth(w) self.width = w end
    function R:SetHeight(h) self.height = h end
    function R:GetSize() return self.width or 0, self.height or 0 end
    function R:GetWidth() return self.width or 0 end
    function R:GetHeight() return self.height or 0 end
    function R:SetTexture(value, ...) self.texture = value; self.wrap = { ... }; return true end
    function R:GetTexture() return self.texture end
    function R:SetColorTexture(...) self.color = { ... } end
    function R:SetVertexColor(...) self.vertex = { ... } end
    function R:SetBlendMode(value) self.blend = value end
    function R:SetRotation(value) self.rotation = value end
    function R:CreateAnimationGroup()
        local group = { playing = false }
        function group:SetLooping(value) self.looping = value end
        function group:CreateAnimation(kind)
            local animation = { kind = kind }
            function animation:SetOrigin(...) self.origin = { ... } end
            function animation:SetDegrees(value) self.degrees = value end
            function animation:SetDuration(value) self.duration = value end
            return animation
        end
        function group:IsPlaying() return self.playing end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        return group
    end
    function R:SetTexCoord(...) self.coords = { ... } end
    function R:SetAtlas(value) self.atlas = value end
    function R:SetDrawLayer(value) self.layer = value end
    function R:SetFont(path, size, flags) self.font = { path, size, flags }; return true end
    function R:GetFont() return "Native.ttf", 12, "" end
    function R:SetText(value) self.text = value; self.textWrites = (self.textWrites or 0) + 1 end
    function R:GetText() return self.text end
    function R:SetTextColor(...) self.textColor = { ... } end
    function R:SetJustifyH(value) self.justify = value end
    function R:SetJustifyV(value) self.justifyV = value end
    function R:SetWordWrap(value) self.wrapWords = value end
    function R:GetStringWidth() return self.text and #tostring(self.text) * 6 or 0 end
    local function Region(parent, name, layer)
        local region = setmetatable({ parent = parent, name = name, layer = layer, shown = true, alpha = 1, points = {} }, R)
        if name then G[name] = region end
        parent.regions[#parent.regions + 1] = region
        return region
    end

    local F = {}
    F.__index = F
    local function New(kind, name, parent)
        local frame = setmetatable({ kind = kind or "Frame", name = name, children = {}, regions = {}, points = {},
            scripts = {}, hookedScripts = {}, events = {}, shown = true, alpha = 1, scale = 1, width = 0, height = 0,
            strata = "MEDIUM", level = 1, mouse = false, wheel = false, enabled = true }, F)
        W.frames[#W.frames + 1] = frame
        if parent then
            frame.parent = parent
            parent.children[#parent.children + 1] = frame
            frame.strata, frame.level = parent.strata, parent.level + 1
        end
        if name then G[name] = frame end
        return frame
    end
    W.New = New
    function F:GetName() return self.name end
    function F:GetObjectType() return self.kind end
    function F:IsForbidden() return false end
    function F:IsProtected()
        if self.protected then return true, true end
        for _, child in ipairs(self.children) do if child:IsProtected() then return true, false end end
        return false, false
    end
    function F:GetParent() return self.parent end
    function F:SetParent(parent)
        Guard(self, "SetParent")
        Count("SetParent:" .. tostring(self.name or self.kind))
        local wasVisible = Visible(self)
        if self.parent then
            local siblings = self.parent.children
            for i = #siblings, 1, -1 do if siblings[i] == self then table.remove(siblings, i) end end
        end
        self.parent = parent
        if parent then
            parent.children[#parent.children + 1] = self
            if not self.fixedStrata then self.strata = parent.strata end
            if not self.fixedLevel then self.level = parent.level + 1 end
        end
        local nowVisible = Visible(self)
        if wasVisible ~= nowVisible then Cascade(self, nowVisible and "OnShow" or "OnHide") end
    end
    function F:GetChildren() return unpack(self.children) end
    function F:CreateTexture(name, layer, template, subLevel)
        assert(template == nil or type(template) == "string", "CreateTexture template must be a name")
        assert(subLevel == nil or type(subLevel) == "number", "CreateTexture subLevel must be a number")
        local region = Region(self, name, layer)
        region.template, region.subLevel = template, subLevel
        return region
    end
    function F:CreateFontString(name, layer) return Region(self, name, layer) end
    function F:IsShown() return self.shown end
    function F:IsVisible() return Visible(self) end
    function F:Show()
        Guard(self, "Show")
        if self.shown then return end
        local parentVisible = not self.parent or Visible(self.parent)
        self.shown = true
        if parentVisible then Cascade(self, "OnShow") end
    end
    function F:Hide()
        Guard(self, "Hide")
        if not self.shown then return end
        local wasVisible = Visible(self)
        self.shown = false
        if wasVisible then Cascade(self, "OnHide") end
    end
    function F:SetShown(value) if value then self:Show() else self:Hide() end end
    function F:SetAlpha(value) self.alpha = value end
    function F:GetAlpha() return self.alpha end
    function F:GetEffectiveAlpha() return self.alpha * (self.parent and self.parent:GetEffectiveAlpha() or 1) end
    function F:SetScale(value) Guard(self, "SetScale"); self.scale = value end
    function F:GetScale() return self.scale end
    function F:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
    function F:SetFrameStrata(value) Guard(self, "SetFrameStrata"); if not self.fixedStrata then self.strata = value end end
    function F:GetFrameStrata() return self.strata end
    function F:SetFrameLevel(value) Guard(self, "SetFrameLevel"); if not self.fixedLevel then self.level = value end end
    function F:GetFrameLevel() return self.level end
    function F:SetFixedFrameStrata(value) self.fixedStrata = value and true or false end
    function F:HasFixedFrameStrata() return self.fixedStrata == true end
    function F:SetFixedFrameLevel(value) self.fixedLevel = value and true or false end
    function F:HasFixedFrameLevel() return self.fixedLevel == true end
    function F:ClearAllPoints() Guard(self, "ClearAllPoints"); self.points = {} end
    function F:SetPoint(...) Guard(self, "SetPoint"); Count("SetPoint:" .. tostring(self.name or self.kind)); R.SetPoint(self, ...) end
    function F:SetAllPoints(relative) Guard(self, "SetAllPoints"); R.SetAllPoints(self, relative) end
    F.GetPoint, F.GetNumPoints = R.GetPoint, R.GetNumPoints
    function F:SetSize(w, h) Guard(self, "SetSize"); Count("SetSize:" .. tostring(self.name or self.kind)); self.width, self.height = w, h end
    function F:SetWidth(w) Guard(self, "SetWidth"); self.width = w end
    function F:SetHeight(h) Guard(self, "SetHeight"); self.height = h end
    F.GetSize, F.GetWidth, F.GetHeight = R.GetSize, R.GetWidth, R.GetHeight
    function F:GetCenter() if self.center then return self.center[1], self.center[2] end end
    function F:SetClampedToScreen(value) self.clamped = value end
    function F:IsClampedToScreen() return self.clamped == true end
    function F:SetClampRectInsets(...) Guard(self, "SetClampRectInsets"); self.clampInsets = { ... } end
    function F:SetHitRectInsets(...) Guard(self, "SetHitRectInsets"); self.hitInsets = { ... } end
    function F:GetHitRectInsets() local h = self.hitInsets or { 0, 0, 0, 0 }; return h[1], h[2], h[3], h[4] end
    function F:SetClipsChildren(value) self.clips = value end
    function F:DoesClipChildren() return self.clips == true end
    function F:EnableMouse(value) Guard(self, "EnableMouse"); self.mouse = value and true or false end
    function F:IsMouseEnabled() return self.mouse end
    function F:EnableMouseWheel(value) self.wheel = value and true or false end
    function F:IsMouseWheelEnabled() return self.wheel end
    function F:SetMouseClickEnabled(value) self.clicks = value end
    function F:SetMouseMotionEnabled(value) self.motion = value end
    function F:SetPassThroughButtons(...) Guard(self, "SetPassThroughButtons"); self.passThrough = { ... } end
    function F:SetPropagateMouseMotion(value) Guard(self, "SetPropagateMouseMotion"); self.propagate = value end
    function F:IsMouseOver() return self.mouseOver == true end
    function F:AddRoleset(value) self.roleset = value end
    function F:SetScript(key, value) self.scripts[key] = value end
    function F:GetScript(key) return self.scripts[key] end
    function F:HookScript(key, value)
        self.hookedScripts[key] = self.hookedScripts[key] or {}
        table.insert(self.hookedScripts[key], value)
    end
    function F:RegisterEvent(event) self.events[event] = true end
    function F:UnregisterEvent(event) self.events[event] = nil end
    function F:UnregisterAllEvents() self.events = {} end
    function F:RegisterForClicks(...) self.clicks = { ... } end
    function F:RegisterForDrag(...) self.drag = { ... } end
    function F:Click(button) Fire(self, "OnClick", button or "LeftButton") end
    function F:SetEnabled(value) self.enabled = value and true or false end
    function F:IsEnabled() return self.enabled end
    function F:Enable() self.enabled = true end
    function F:Disable() self.enabled = false end
    function F:SetNormalTexture(value) self.normal = value end
    function F:SetHighlightTexture(value) self.highlight = value end
    function F:SetAttribute(key, value) self.attributes = self.attributes or {}; self.attributes[key] = value end
    function F:GetAttribute(key) return self.attributes and self.attributes[key] end
    -- Minimap
    function F:SetMaskTexture(value) Count("mask"); self.mask = value end
    function F:GetZoom() return self.zoom or 0 end
    function F:SetZoom(value) Count("zoom"); self.zoom = value end
    function F:GetZoomLevels() return 6 end
    function F:SetArchBlobRingScalar(value) self.arch = value end
    function F:SetQuestBlobRingScalar(value) self.quest = value end
    function F:SetTaskBlobRingScalar(value) self.task = value end
    function F:SetIconScale(value) self.iconScale = value end
    function F:PingLocation(x, y) self.ping = { x, y } end

    local function Schedule(delay, callback)
        local timer = { due = W.now + delay, delay = delay, callback = callback }
        function timer:Cancel() self.cancelled = true end
        W.timers[#W.timers + 1] = timer
        return timer
    end
    function W.Advance(seconds)
        W.now = W.now + (seconds or 0)
        local fired = true
        while fired do
            fired = false
            for i = 1, #W.timers do
                local timer = W.timers[i]
                if not timer.cancelled and not timer.fired and timer.due <= W.now then
                    timer.fired, fired = true, true
                    timer.callback(timer)
                end
            end
        end
    end
    function W.Step() W.Advance(0) end
    -- Pending timers with the given delay; without one, every timer except the
    -- zero-delay (next frame) deferrals.
    function W.Pending(delay)
        local count = 0
        for _, timer in ipairs(W.timers) do
            if not timer.cancelled and not timer.fired and (delay and timer.delay == delay or not delay and timer.delay > 0) then
                count = count + 1
            end
        end
        return count
    end
    function W.Event(event, ...)
        local list = {}
        for _, frame in ipairs(W.frames) do if frame.events[event] then list[#list + 1] = frame end end
        for _, frame in ipairs(list) do Fire(frame, "OnEvent", event, ...) end
    end
    local function Drive(frame)
        local value, show = frame.stateDriver
        if value == "[combat] show; hide" then show = W.combat elseif value == "[combat] hide; show" then show = not W.combat end
        if show == nil then return end
        W.secure = true
        frame:SetShown(show)
        W.secure = false
    end
    function W.SetCombat(value)
        W.combat = value
        for frame in pairs(W.drivers) do Drive(frame) end
        W.Event(value and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    end
    -- Runs Blizzard code: secure, so it may move protected frames in combat.
    function W.Blizzard(callback, ...)
        local previous = W.secure
        W.secure = true
        callback(...)
        W.secure = previous
    end

    G.CreateFrame = function(kind, name, parent) return New(kind, name, parent) end
    G.InCombatLockdown = function() return W.combat end
    G.SlashCmdList = {}
    G.issecretvalue = function(value) return value == W.secret end
    W.secret = setmetatable({}, { __lt = function() error("secret comparison") end, __le = function() error("secret comparison") end })
    G.hooksecurefunc = function(target, name, hook)
        if type(target) == "string" then target, name, hook = G, target, name end
        local original = target[name]
        assert(type(original) == "function", "hook target missing: " .. tostring(name))
        W.hooks = W.hooks + 1
        target[name] = function(...)
            local a, b, c, d = original(...)
            hook(...)
            return a, b, c, d
        end
    end
    G.RegisterStateDriver = function(frame, state, value)
        assert(not W.combat, "state driver registered in combat")
        assert(state == "visibility")
        frame.stateDriver, W.drivers[frame] = value, true
        Drive(frame)
    end
    G.UnregisterStateDriver = function(frame, state)
        assert(not W.combat, "state driver removed in combat")
        assert(state == "visibility")
        frame.stateDriver, W.drivers[frame] = nil, nil
    end
    G.C_Timer = { After = function(delay, callback) Schedule(delay, callback) end, NewTimer = Schedule }
    G.GetTime = function() return W.now end
    G.GetCVar = function(key) return W.cvars[key] end
    G.SetCVar = function(key, value) W.cvars[key] = tostring(value) end
    G.C_CVar = { GetCVar = G.GetCVar, SetCVar = G.SetCVar }
    G.UnitClass = function() return "Mage", "MAGE" end
    G.UnitName = function() return "Tester" end
    G.GetRealmName = function() return "Realm" end
    G.RAID_CLASS_COLORS = { MAGE = { r = 0.2, g = 0.4, b = 0.8 } }
    G.PixelUtil = { GetPixelToUIUnitFactor = function() return 1 end }
    G.C_AddOns = { IsAddOnLoaded = function() return false end,
        DoesAddOnExist = function(name) return type(name) == "string" and name:match("^MSUF_Suite") ~= nil end }
    G.EditModeManagerFrame = { IsInitialized = function() return W.editModeReady == true end }
    G.MSUF_PixelLayoutRegion = function(region) return region end
    G.MSUF_EditModeAPI = {
        RegisterElement = function(owner, element) W.movers[owner .. "/" .. element.id] = element; return true end,
        RefreshOwner = function() end, UnregisterOwner = function(owner)
            for key in pairs(W.movers) do if key:find(owner, 1, true) == 1 then W.movers[key] = nil end end
        end,
        IsActive = function() return false end, RegisterSessionListener = function() end,
    }
    W.hostRecord = { isEnabled = function() return true end }
    G.MSUF_EM2 = { ExternalElements = { GetRecord = function(key) return key == "external:msuf.blizzard:minimap" and W.hostRecord or nil end } }
    G.GameTooltip = New("GameTooltip", "GameTooltip")
    G.GameTooltip:Hide()
    function G.GameTooltip:SetOwner(owner) self.owner = owner; self.lines = {} end
    function G.GameTooltip:GetOwner() return self.owner end
    function G.GameTooltip:ClearLines() self.lines = {} end
    function G.GameTooltip:SetText(text) self.lines = { text } end
    function G.GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function G.GameTooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " | " .. right end
    G.GameTooltip.lines = {}
    G.MSUF_NS = { Client = { Family = classic and "Classic" or "Mainline", Flavor = client == "Forever" and "Mainline" or client,
        IsForever = client == "Forever", IsRetail = not classic, SupportsEvent = function() return true end } }
    local ui = New("Frame", "UIParent")
    ui.width, ui.height, ui.strata, ui.level = 1366, 768, "MEDIUM", 0
    W.UIParent = ui

    -- Blizzard's minimap world (names from the mirror, per client family).
    local cluster = New("Frame", "MinimapCluster", ui)
    cluster.strata, cluster.mouse = "LOW", true
    cluster:SetSize(256, 256)
    local container = New("Frame", nil, cluster)
    container:SetSize(classic and 140 or 215, classic and 140 or 226)
    cluster.MinimapContainer = container
    local map = New("Minimap", "Minimap", container)
    map.protected = true
    map:SetSize(classic and 140 or 198, classic and 140 or 198)
    map:SetPoint("CENTER", container, "CENTER", 0, 0)
    map.center = { 1256, 638 }
    map.mouse = true
    map.wheel = not classic
    local backdrop = New("Frame", "MinimapBackdrop", map)
    backdrop:SetSize(classic and 192 or 215, classic and 192 or 226)
    backdrop:CreateTexture("MinimapCompassTexture", "OVERLAY")
    local function Button(name, parent, w, h, hidden)
        local button = New("Button", name, parent)
        button:SetSize(w, h)
        button:SetPoint("CENTER", parent, "CENTER", 0, 0)
        button.mouse = true
        if hidden then button.shown = false end
        return button
    end
    W.Button = Button
    if classic then
        cluster.ZoneTextButton = Button("MinimapZoneTextButton", cluster, 140, 12)
        Button("MinimapToggleButton", cluster, 32, 32)
        backdrop:CreateTexture("MinimapBorder", "ARTWORK")
        backdrop:CreateTexture("MinimapNorthTag", "OVERLAY")
        Button("MiniMapMailFrame", map, 33, 33, true).kind = "Frame"
        Button("MiniMapBattlefieldFrame", map, 33, 33, true)
        Button("MiniMapWorldMapButton", backdrop, 33, 33, client ~= "Mists")
        Button("MinimapZoomIn", backdrop, 32, 32)
        Button("MinimapZoomOut", backdrop, 32, 32)
        local tracking = Button("MiniMapTracking", backdrop, 33, 33)
        tracking.kind = "Frame"
        if client ~= "Vanilla" then
            local dropdown = Button("MiniMapTrackingButton", tracking, 32, 32)
            function dropdown:OpenMenu() self.menuOpen = true end
            function dropdown:CloseMenu() self.menuOpen = false end
            function dropdown:IsMenuOpen() return self.menuOpen == true end
        end
        if client == "Mists" then Button("GameTimeFrame", cluster, 40, 40)
        else Button("GameTimeFrame", backdrop, 50, 50).kind = "Frame" end
        Button("MiniMapInstanceDifficulty", container, 38, 46, true).kind = "Frame"
        Button("GuildInstanceDifficulty", container, 38, 46, true).kind = "Frame"
        Button("MiniMapChallengeMode", container, 27, 36, true).kind = "Frame"
        Button("LFGMinimapFrame", backdrop, 33, 33, true)
        Button("TimeManagerClockButton", backdrop, 60, 28)
        local mists = client == "Mists"
        G.MiniMap_ShouldShowDifficulty = function() return mists end
    else
        cluster.BorderTop = New("Frame", nil, cluster)
        cluster.ZoneTextButton = Button(nil, cluster, 135, 12)
        local tracking = New("Frame", nil, cluster)
        tracking:SetSize(17, 17)
        tracking:SetPoint("RIGHT", cluster.BorderTop, "LEFT", -2, 0)
        tracking.Button = Button(nil, tracking, 13, 14)
        function tracking.Button:OpenMenu() self.menuOpen = true end
        function tracking.Button:CloseMenu() self.menuOpen = false end
        function tracking.Button:IsMenuOpen() return self.menuOpen == true end
        cluster.Tracking = tracking
        local indicator = New("Frame", nil, cluster)
        cluster.IndicatorFrame = indicator
        indicator.MailFrame = Button(nil, indicator, 20, 15, true)
        indicator.CraftingOrderFrame = Button(nil, indicator, 20, 15, true)
        local zoomIn, zoomOut = Button(nil, map, 17, 17, true), Button(nil, map, 17, 9, true)
        map.ZoomIn, map.ZoomOut = zoomIn, zoomOut
        cluster.InstanceDifficulty = Button(nil, cluster, 35.5, 36.5)
        Button("GameTimeFrame", cluster, 19, 18)
        Button("AddonCompartmentFrame", cluster, 16, 16, true)
        Button("TimeManagerClockButton", cluster, 40, 16)
        Button("ExpansionLandingPageMinimapButton", backdrop, 53, 53)
        if client == "Forever" then
            backdrop:CreateTexture("MinimapCompassTextureUnderlay", "OVERLAY")
            container.PlayerCoords = New("Frame", nil, container)
        end
    end
    W.map, W.cluster, W.container, W.backdrop = map, cluster, container, backdrop

    local function Load(path, addon, namespace)
        local chunk = assert(loadfile(root .. "/" .. path))
        setfenv(chunk, G)
        return chunk(addon, namespace)
    end
    W.Suite = {}
    G.MSUFSuite = W.Suite
    -- Core files follow the TOC up to the controller (shared test support).
    local support = dofile(root .. "/tools/tests/suite_test_support.lua")
    for _, file in ipairs(support.TocFiles(root, "MSUF_Suite", classic and client or "Mainline")) do
        if file:match("%.lua$") then Load("MSUF_Suite/" .. file, "MSUF_Suite", W.Suite) end
        if file == "Core/Suite.lua" then break end
    end
    Load("MSUF_Suite/Integrations/MapkoSkin.lua", "MSUF_Suite", W.Suite)
    assert(W.Suite.Database.Initialize(nil))
    W.S = W.Suite.Suite
    W.S.Normalize(W.Suite.DB)
    W.private = {}
    if options.beforeModules then options.beforeModules(W) end
    for _, file in ipairs({ "Surfaces", "Runtime", "DataSources", "EditMode" }) do
        Load("MSUF_Suite_Modules/" .. file .. ".lua", "MSUF_Suite_Modules", W.private)
    end
    for _, file in ipairs(options.modules or H.MODULES) do
        Load("MSUF_Suite_Minimap/" .. file .. ".lua", "MSUF_Suite_Minimap", W.private)
    end
    W.MM = W.private.Minimap
    W.M = W.S.instances.minimap
    W.config = W.S.Config("minimap")
    return W
end

-- Starts the controller and turns the module on through the real Apply path.
function H.Enable(W, values)
    local S = W.S
    if not S.started then S.Start() end
    if values then for key, value in pairs(values) do W.config[key] = value end end
    assert(S.Set("minimap", "enabled", true))
    assert(W.M.active and S.states.minimap.active, "minimap did not activate")
end

function H.Near(a, b, tolerance)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (tolerance or 1e-6)
end

return H
