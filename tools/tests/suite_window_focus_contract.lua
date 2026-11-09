-- Native-window focus, geometry and lifecycle through the real control seam.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_window_controls_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))', 1, true))
local fixture = "issecretvalue = function(value) return type(value) == 'table' and value.secret == true end\n"
    .. source:sub(1, stop - 1) .. [[
return { NS = NS, Frame = Frame, frames = createdFrames, jobs = combatJobs }
]]
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    _G.combat, _G.combatEdge = false, false
    local H = assert(loadstring(fixture, "@window_focus_fixture"))()
    local NS, Frame = H.NS, H.Frame
    NS.Client.isForever = flavor == "Forever"
    NS.DB.theme = { look = "midnight", windowFocusDimming = true }
    NS.DB.windowControls.enabled = false
    NS.SuiteOwnership = { OwnsWindowGeometry = function() return true end }
    local listeners, nativeHooks, veils = {}, {}, {}
    local gamepadTarget, gamepadCallbacks
    EventRegistry = {
        RegisterCallback = function(_, event, callback, owner)
            gamepadCallbacks = { event = event, callback = callback, owner = owner }
        end,
        UnregisterCallback = function() gamepadCallbacks = nil end,
    }
    GamepadMode = flavor == "Forever" and { FrameControlsManager = {
        GetActiveFrame = function() return gamepadTarget end,
    } } or nil
    local manager = {}
    function manager:GetOpenMenu() return self.root end
    function manager:OpenMenu(_, description)
        self.root = description.root
        for _, callback in ipairs(description.acquired) do callback(self.root) end
    end
    manager.OpenContextMenu = manager.OpenMenu
    Menu = { GetManager = function() return manager end }
    NS.Registry.AddListener = function(owner, callback) listeners[owner] = callback end
    local parentHook = hooksecurefunc
    hooksecurefunc = function(target, method, callback)
        if type(target) == "string" then return parentHook(target, method) end
        local native = assert(target[method])
        nativeHooks[#nativeHooks + 1] = { target, method }
        target[method] = function(...) local result = native(...); callback(...); return result end
    end
    local function Load(path) assert(loadfile(root .. "/MSUF_Suite_Skin/" .. path))("MSUF_Suite_Skin", NS) end
    Load("Adapters/Catalog.lua")
    Load("Rendering/WindowControls.lua")
    NS.WindowFocusVisual = {
        Create = function()
            local overlay = Frame(nil, UIParent)
            overlay:EnableMouse(false)
            local record = { overlay = overlay, rect = {}, shows = 0 }
            veils[#veils + 1] = record
            return record
        end,
        Show = function(record, rect, _, layer, level)
            local first = not record.dim
            record.dim, record.shows = true, record.shows + 1
            record.rect.left, record.rect.bottom = rect.left, rect.bottom
            record.rect.width, record.rect.height = rect.width, rect.height
            local point = record.overlay.point
            if not point then point = {}; record.overlay.point = point end
            point[1], point[2], point[3], point[4], point[5] = "BOTTOMLEFT", UIParent, "BOTTOMLEFT", rect.left, rect.bottom
            record.overlay:SetSize(rect.width, rect.height)
            record.overlay:SetFrameStrata(layer)
            record.overlay:SetFrameLevel(level)
            if first then record.overlay:Show() end
        end,
        Hide = function(record) if record.dim then record.dim = false; record.overlay:Hide() end end,
        Refresh = function() end,
    }
    NS.FocusVeil = { SetWindowFocusProvider = function(opened, closed)
        NS.menuOpened, NS.menuClosed = opened, closed
    end }
    NS.Registry.GetSurface = function() return nil end
    Load("Rendering/WindowFocusContour.lua")
    Load("Rendering/WindowFocusGeometry.lua")
    Load("Rendering/WindowFocusLayers.lua")
    Load("Rendering/WindowFocusChrome.lua")
    Load("Rendering/WindowFocusPopups.lua")
    Load("Rendering/WindowFocus.lua")
    local F, W = NS.WindowFocus, NS.WindowControls
    local driver = H.frames[#H.frames]
    local foci, held = {}, false
    GetMouseFoci = function() return foci end
    IsMouseButtonDown = function() return held end
    local function Tick()
        if driver.scripts.OnUpdate then driver.scripts.OnUpdate(driver, 0.016) end
    end
    local function Click(frame, behind)
        foci[1], foci[2] = frame, behind
        if driver.events and driver.events.GLOBAL_MOUSE_DOWN then driver.scripts.OnEvent(driver, "GLOBAL_MOUSE_DOWN") end
    end
    local function Native(name, left, bottom, width, height)
        local frame = Frame(name, UIParent)
        _G[name] = frame
        frame.left, frame.bottom, frame.width, frame.height = left, bottom, width, height
        frame.top = bottom + height
        function frame:GetBottom() return self.bottom end
        function frame:IsVisible() return self.shown and self.parent.shown end
        function frame:Raise() self.frameLevel = self:GetFrameLevel() + 1 end
        function frame:StartSizing() self.sizing = true end
        frame.NineSlice = Frame(nil, frame)
        frame.NineSlice:SetFrameLevel(name == "PlayerSpellsFrame" and 5500 or 500)
        return frame
    end
    local function Dimmed(frame)
        local state = assert(F.records[frame])
        for _, record in ipairs(state.veils) do if record.dim then return true end end
        return false
    end
    local function Intersects(a, b)
        return a.left < b.left + b.width and b.left < a.left + a.width
            and a.bottom < b.bottom + b.height and b.bottom < a.bottom + a.height
    end
    local a = Native("CharacterFrame", 100, 100, 500, 500)
    local b = Native("ProfessionsFrame", 350, 250, 500, 450)
    local c = Native("PlayerSpellsFrame", 1100, 200, 500, 500)
    Check(not W.Attach(a, "windows") and F.records[a], "move-disabled window was not registered for focus")
    Check(not driver.events or not driver.events.GLOBAL_MOUSE_DOWN, "single window installed a global input listener")
    W.Attach(b, "windows")
    Check(F.active.frame == b and Dimmed(a) and not Dimmed(b), "newly opened window did not become active")
    Check(driver.events.GLOBAL_MOUSE_DOWN and not driver.scripts.OnUpdate, "focus needs an idle updater or misses input")
    for _, record in ipairs(F.records[a].veils) do
        Check(not record.dim or not Intersects(record.rect, F.records[b].rect), "inactive veil crosses active window")
    end
    local shell = Frame(nil, a)
    shell.left, shell.bottom, shell.width, shell.height = 100, 80, 940, 552
    function shell:GetBottom() return self.bottom end
    function shell:IsVisible() return self.shown and a:IsVisible() end
    F.Present(a, shell)
    Check(F.records[a].rect.width == 940 and F.records[a].rect.bottom == 80 and F.records[a].footprintCount == 1,
        "the presented Character Panel dimmed only its stock-sized native host")
    local child, nested = Frame(nil, shell, "Button"), Frame(nil, nil, "Button")
    nested.parent = child
    Click(nested)
    Check(F.active.frame == a and Dimmed(b) and not Dimmed(a), "hosted surface input did not focus its native root")
    F.Present(a, nil)
    Check(F.records[a].rect.width == 500, "closing the hosted shell retained the wide footprint on native tabs")
    Click(Frame(nil, UIParent), Frame(nil, b))
    Check(F.active.frame == a, "click through an untracked top popup stole focus")
    if flavor == "Forever" then
        Check(gamepadCallbacks and gamepadCallbacks.event == "Gamepad.RefreshFrameFocus",
            "Forever native focus callback was not registered")
        gamepadTarget = Frame(nil, b)
        gamepadCallbacks.callback(gamepadCallbacks.owner)
        Check(F.active.frame == b, "native gamepad focus did not follow its nested root")
        gamepadTarget = Frame(nil, UIParent)
        gamepadCallbacks.callback(gamepadCallbacks.owner)
        Check(F.active.frame == b, "untracked gamepad focus changed native-window MRU")
        gamepadTarget = nested
        gamepadCallbacks.callback(gamepadCallbacks.owner)
    else Check(not gamepadCallbacks, "gamepad provider was invented on Mainline") end
    b:Raise(); Tick()
    W.Attach(b, "windows")
    Check(F.active.frame == a, "native Raise or repeat skinning changed last-used focus")
    listeners[F](F, "profile")
    W.DisableOwner("windows")
    Check(not F.active and not Dimmed(a) and not Dimmed(b) and not driver.events.GLOBAL_MOUSE_DOWN,
        "owner disable left focused windows, veils or global input alive")
    W.Attach(a, "windows"); W.Attach(b, "windows")
    Check(F.active.frame == a, "profile owner refresh changed MRU order")
    a:Hide()
    Check(F.active.frame == b and not Dimmed(b), "hiding focused window did not restore its predecessor")
    Check(not gamepadCallbacks, "single remaining window retained a gamepad callback")
    a:Show()
    Check(F.active.frame == a and Dimmed(b), "reopened window did not become active")

    -- Implicitly protected roots and Suite-owned bags still participate;
    -- focus never creates geometry or changes alpha on the native targets.
    c.protected = true
    _G.combatEdge = true
    W.Attach(c, "windows")
    Check(F.active.frame == c and Dimmed(a) and not Dimmed(c), "protected combat window missed focus")
    Click(nested)
    Check(Dimmed(c), "protected native window could not be dimmed in combat")
    for _, record in ipairs(F.records[c].veils) do
        Check(record.overlay.parent == UIParent and record.overlay.point[2] == UIParent
            and not record.overlay.mouseEnabled and record.overlay.frameLevel > 5500,
            "protected root received an anchored, interactive or low veil")
    end
    local function Resize(frame)
        for _, callback in ipairs(frame.hooks.OnSizeChanged or {}) do callback(frame) end
        Tick()
    end
    local secret = setmetatable({ secret = true }, { __add = function() error("secret arithmetic") end,
        __mul = function() error("secret arithmetic") end, __lt = function() error("secret comparison") end })
    c.width = secret
    Resize(c)
    Check(not Dimmed(c), "secret inactive bounds retained their previous veil")
    c.width = 500
    a.left = secret
    Resize(a)
    Check(not Dimmed(b) and not Dimmed(c), "secret active bounds retained a stale clipping hole")
    a.left = 100
    a.IsForbidden = function() return true end
    local oldLeft = a.GetLeft
    a.GetLeft = function() error("forbidden geometry read") end
    Resize(a)
    Check(not Dimmed(b) and not Dimmed(c), "forbidden active window left other veils active")
    a.IsForbidden, a.GetLeft = function() return false end, oldLeft
    Resize(a)

    -- Native unskinned context menus and pooled submenus can live above the
    -- active root's bounds; they keep clear even with dropdown dimming off.
    local existingMenu = Native("ExistingUnskinnedMenu", 1120, 250, 130, 100)
    manager.root = existingMenu -- opened before this addon could observe its description
    NS.DB.theme.windowFocusDimming = false
    listeners[F](F, "motion")
    NS.DB.theme.windowFocusDimming = true
    listeners[F](F, "motion")
    Tick()
    Check(existingMenu.hooks.OnHide and #existingMenu.hooks.OnHide == 1,
        "an already-open menu had no per-lease hide observer")
    existingMenu:Hide()
    manager.root = nil
    existingMenu.GetLeft = function() error("closed preexisting menu geometry read") end
    Tick()
    Check(Dimmed(c), "closing a preexisting menu left a stale popup exclusion")
    local popup = Native("UnskinnedMenu", 1120, 250, 130, 100)
    local submenu = Native("UnskinnedSubmenu", 1280, 300, 130, 100)
    local description = { root = popup, acquired = {}, released = {} }
    function description:AddMenuAcquiredCallback(callback) self.acquired[#self.acquired + 1] = callback end
    function description:AddMenuReleasedCallback(callback) self.released[#self.released + 1] = callback end
    NS.DB.theme.dropdownDimming = false
    manager:OpenContextMenu(a, description)
    Tick()
    for _, record in ipairs(F.records[c].veils) do
        Check(not record.dim or not Intersects(record.rect, { left = 1120, bottom = 250, width = 130, height = 100 }),
            "inactive raised window shaded an unskinned context menu")
    end
    for _, acquired in ipairs(description.acquired) do acquired(submenu) end
    Tick()
    submenu.width = 200
    Resize(submenu)
    for _, record in ipairs(F.records[c].veils) do
        Check(not record.dim or not Intersects(record.rect, { left = 1280, bottom = 300, width = 200, height = 100 }),
            "in-place menu layout escaped the popup clipping rectangle")
    end
    for _, released in ipairs(description.released) do released(submenu) end
    submenu.hooks = {} -- compositor pool removes native scripts on release
    for _, acquired in ipairs(description.acquired) do acquired(submenu) end
    Check(submenu.hooks.OnSizeChanged and #submenu.hooks.OnSizeChanged == 1
        and submenu.hooks.OnHide and #submenu.hooks.OnHide == 1,
        "pooled submenu lost or duplicated its layout observer")
    NS.DB.theme.windowFocusDimming = false
    listeners[F](F, "motion")
    for _, released in ipairs(description.released) do released(popup); released(submenu) end
    manager:OpenMenu(a, description)
    for _, acquired in ipairs(description.acquired) do acquired(submenu) end
    NS.DB.theme.windowFocusDimming = true
    listeners[F](F, "motion")
    Tick()
    for _, record in ipairs(F.records[c].veils) do
        Check(not record.dim or not Intersects(record.rect, { left = 1280, bottom = 300, width = 200, height = 100 }),
            "reenabling focus missed an already-open unskinned submenu")
    end
    for _, released in ipairs(description.released) do released(popup); released(submenu) end
    manager.root = nil
    Tick()
    local bag = Native("ContainerFrameCombinedBags", 1500, 10, 350, 400)
    W.Attach(bag, "bags")
    Check(F.active.frame == bag, "Suite bag geometry ownership suppressed focus tracking")
    Check(not a.geometryWrites and not b.geometryWrites and not c.geometryWrites and not bag.geometryWrites,
        "focus changed native geometry")
    _G.combatEdge = false

    Click(nested)
    held = true
    a:StartMoving()
    Check(driver.scripts.OnUpdate and driver.events.GLOBAL_MOUSE_UP, "native engine movement had no bounded geometry driver")
    a.left = 650
    Tick()
    Check(F.records[a].rect.left == 650, "engine movement left stale active-window clipping")
    local function DragBudget()
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 300 do Tick() end
        local growth = collectgarbage("count") - before
        collectgarbage("restart")
        return growth
    end
    local growth = math.min(DragBudget(), DragBudget())
    Check(growth < 4, "steady native dragging allocated " .. growth .. " KiB")
    held = false
    driver.scripts.OnEvent(driver, "GLOBAL_MOUSE_UP")
    Tick() -- settle the one post-release native layout pass
    Check(not driver.scripts.OnUpdate and not driver.events.GLOBAL_MOUSE_UP, "mouse release left a movement updater")
    local before = F.active
    b:SetScale(0.8); Tick()
    Check(F.active == before and F.records[b].rect.width == 400 and not driver.scripts.OnUpdate,
        "native scaling changed focus or left stale bounds/idle work")
    local nativeLeft, nativeWidth = a.GetLeft, UIParent.width
    a.GetLeft = function(self) return UIParent:GetWidth() / 2 - self:GetWidth() / 2 end
    a:SetScale(a.scale); Tick()
    UIParent.width = UIParent.width + 200
    if driver.events.UI_SCALE_CHANGED then driver.scripts.OnEvent(driver, "UI_SCALE_CHANGED") end
    Tick()
    Check(F.records[a].rect.left == a:GetLeft(), "UIParent scale change left stale centered-window bounds")
    a.GetLeft, UIParent.width = nativeLeft, nativeWidth
    if driver.events.DISPLAY_SIZE_CHANGED then driver.scripts.OnEvent(driver, "DISPLAY_SIZE_CHANGED") end
    Tick()
    Check(F.records[a].rect.left == a:GetLeft(), "display resize did not refresh absolute window clipping")
    NS.DB.theme.windowFocusDimming = false
    listeners[F](F, "motion")
    Check(not Dimmed(a) and not Dimmed(b) and not Dimmed(c) and not driver.events.GLOBAL_MOUSE_DOWN,
        "focus feature disable left artwork or global input active")
    NS.DB.theme.windowFocusDimming = true
    listeners[F](F, "motion")
    Check(F.active == before and Dimmed(b), "reenabling focus lost the existing last-used window")

    -- Historical hidden roots cannot enlarge settings, owner release or combat work.
    a:Hide(); b:Hide(); c:Hide(); bag:Hide()
    local reads = 0
    for index = 1, 128 do
        local hidden = Native("ProfessionsFrame", 100, 100, 500, 500)
        hidden:Hide()
        W.TrackFocus(hidden, "history")
        hidden.GetLeft = function() reads = reads + 1; error("hidden native geometry read") end
        hidden.IsVisible = function() reads = reads + 1; return false end
    end
    local nativeHooksBefore, veilCount = #nativeHooks, #veils
    for _ = 1, 1000 do listeners[F](F, "profile"); W.DisableOwner("history") end
    Check(reads == 0 and #nativeHooks == nativeHooksBefore and #veils == veilCount
        and not driver.scripts.OnUpdate and not driver.events.GLOBAL_MOUSE_DOWN
        and not driver.events.UI_SCALE_CHANGED and not driver.events.DISPLAY_SIZE_CHANGED,
        "closed window history caused reads, allocations or idle callbacks")
    local forbidden = Native("ProfessionsFrame", 0, 0, 400, 400)
    forbidden.IsForbidden = function() return true end
    forbidden.GetName = function() error("forbidden native frame inspected") end
    Check(not F.Track(forbidden, "forbidden"), "forbidden native root was adopted")
end
print("Window focus controller: " .. checks .. " checks passed")
