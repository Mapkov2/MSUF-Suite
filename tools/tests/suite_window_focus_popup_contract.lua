-- Popup leases follow native acquire-before-layout and release-before-reset.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, label) assert(value, label); checks = checks + 1 end
local secret = setmetatable({ secret = true }, {
    __lt = function() error("secret compared") end,
    __mul = function() error("secret arithmetic") end,
})
issecretvalue = function(value) return type(value) == "table" and value.secret == true end
CreateFrame = function() error("popup observation created a polling driver") end
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local NS, changes, reads = {}, 0, 0
    local manager = {}
    local function Frame()
        local frame = { shown = false, width = 1, height = 1, hooks = {}, strata = "FULLSCREEN_DIALOG", level = 9501 }
        function frame:IsForbidden() reads = reads + 1; return self.forbidden == true end
        function frame:IsVisible() reads = reads + 1; return self.visibilitySecret and secret or self.shown end
        function frame:GetLeft() reads = reads + 1; return self.left end
        function frame:GetBottom() reads = reads + 1; return self.bottom end
        function frame:GetWidth() reads = reads + 1; return self.width end
        function frame:GetHeight() reads = reads + 1; return self.height end
        function frame:GetEffectiveScale() reads = reads + 1; return 1 end
        function frame:GetFrameStrata() reads = reads + 1; return self.strata end
        function frame:GetFrameLevel() reads = reads + 1; return self.level end
        function frame:HookScript(event, callback)
            local hooks = self.hooks[event] or {}
            self.hooks[event] = hooks
            hooks[#hooks + 1] = callback
        end
        function frame:Fire(event) for _, callback in ipairs(self.hooks[event] or {}) do callback(self) end end
        function frame:Show() self.shown = true; self:Fire("OnShow") end
        function frame:Hide() self.shown = false; self:Fire("OnHide") end
        function frame:SetPoint() end
        function frame:SetScale() end
        function frame:Reset()
            self.shown, self.hooks, self.left, self.bottom = false, {}, nil, nil
            self.width, self.height = 1, 1
        end
        function frame:Layout(left, bottom, width, height)
            self.left, self.bottom, self.width, self.height = left, bottom, width, height
            self:Fire("OnSizeChanged")
        end
        return frame
    end
    UIParent = Frame()
    function manager:GetOpenMenu() return self.root end
    function manager:OpenMenu(_, description)
        self.root = description.root
        self.root:Reset()
        for _, acquired in ipairs(description.acquired) do acquired(self.root) end
        if description.beforeLayout then description.beforeLayout(self.root) end
        self.root:Layout(250, 250, 100, 100)
        self.root:Show()
    end
    manager.OpenContextMenu = manager.OpenMenu
    Menu = { GetManager = function() return manager end }
    hooksecurefunc = function(target, method, callback)
        local original = assert(target[method])
        target[method] = function(...) original(...); callback(...) end
    end
    NS.FocusVeil = { SetWindowFocusProvider = function(opened, closed)
        NS.menuOpened, NS.menuClosed = opened, closed
    end }
    local function Load(path) assert(loadfile(root .. "/MSUF_Suite_Skin/" .. path))("MSUF_Suite_Skin", NS) end
    Load("Core/Safety.lua")
    Load("Rendering/WindowFocusGeometry.lua")
    Load("Rendering/WindowFocusLayers.lua")
    assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowFocusPopups.lua"))("MSUF_Suite_Skin", NS)
    local P, G = NS.WindowFocusPopups, NS.WindowFocusGeometry
    P.Initialize(function() changes = changes + 1 end)
    P.SetActive(true)
    local function State(rank, level)
        local state = { rect = { left = 0, bottom = 0, width = 500, height = 500 }, rank = rank or 3, level = level or 100 }
        local strata = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
        state.strata = strata[state.rank]
        NS.WindowFocusLayers.Prepare(state)
        G.Begin(state)
        return state
    end
    local function Area(state)
        local area = 0
        for index = 1, state.sliceCount do area = area + state.slices[index].width * state.slices[index].height end
        return area
    end
    local function Clear(label, rank, level)
        local state = State(rank, level)
        Check(P.Subtract(state) and Area(state) == 250000, label)
    end
    local function Cut(label)
        local state = State()
        Check(P.Subtract(state) and Area(state) == 240000, label)
    end
    local menu, submenu = Frame(), Frame()
    local description = { root = menu, acquired = {}, released = {} }
    function description:AddMenuAcquiredCallback(callback) self.acquired[#self.acquired + 1] = callback end
    function description:AddMenuReleasedCallback(callback) self.released[#self.released + 1] = callback end
    local function Release(frame)
        if manager.root == frame then manager.root = nil end
        for _, released in ipairs(description.released) do released(frame) end
        frame:Hide()
        frame:Reset()
    end
    manager:OpenContextMenu({}, description)
    Cut("first context-menu layout was not excluded")
    Release(menu)
    Clear("released menu left an exclusion")
    description.beforeLayout = function(frame)
        local before = reads
        Clear("hidden acquired menu cancelled inactive dimming")
        Check(reads == before, "pending acquired menu was measured before native layout/show")
        Check(frame.hooks.OnShow and #frame.hooks.OnShow == 1, "new lease has no single OnShow promotion")
    end
    for _ = 1, 100 do
        manager:OpenMenu({}, description)
        Cut("pooled menu did not promote after layout/show")
        Release(menu)
        Clear("native release/reset poisoned a later paint")
    end
    description.beforeLayout = nil
    manager:OpenMenu({}, description)
    Cut("valid visible menu did not cut its rectangle")
    menu:Layout(250, 250, 0, 100)
    Clear("zero-width popup suppressed unrelated windows", 8, 10000)
    menu:Layout(250, 250, 100, 100)
    Cut("zero-size popup did not recover after native size event")
    menu.left = secret
    menu:Fire("OnSizeChanged")
    Clear("unreadable high popup suppressed a lower native window")
    Check(not P.Subtract(State(8, 10000)), "unknown shown popup let a TOOLTIP veil cover its active contents")
    Check(not P.Subtract(State(7, 9501)), "equal-layer unknown popup lost conservative protection")
    Clear("lower frame-level veil unnecessarily suppressed", 7, 9500)
    menu.strata = "HIGH"
    Check(not P.Subtract(State()), "DIALOG paint floor covered an unreadable native HIGH popup")
    menu.strata = secret
    Check(not P.Subtract(State()), "unknown popup layer lost conservative protection")
    menu.strata, menu.left = "FULLSCREEN_DIALOG", 250
    menu:Fire("OnSizeChanged")
    Cut("readable popup recovery lost real occlusion")
    menu.visibilitySecret = true
    Clear("unknown visibility on a higher popup unnecessarily suppressed a lower window")
    Check(not P.Subtract(State(8, 10000)), "unknown popup visibility let a higher veil cover its contents")
    menu.visibilitySecret, menu.forbidden = nil, true
    Check(not P.Subtract(State()), "previously shown forbidden popup lost conservative protection")
    menu.forbidden = false
    Cut("readable visibility recovery lost popup occlusion")
    -- A live submenu arrives through shared description callbacks, still hidden.
    submenu:Reset()
    for _, acquired in ipairs(description.acquired) do acquired(submenu) end
    Cut("pending submenu poisoned the valid root menu")
    submenu:Layout(350, 250, 100, 100)
    submenu:Show()
    local two = State()
    Check(P.Subtract(two) and Area(two) == 230000, "shown submenu was not excluded")
    P.SetActive(false)
    local beforeReads, beforeChanges = reads, changes
    for _ = 1, 1000 do menu:Fire("OnSizeChanged"); submenu:Fire("OnSizeChanged") end
    Check(reads == beforeReads and changes == beforeChanges, "disabled hooks did popup work")
    P.SetActive(true); P.Discover()
    two = State()
    Check(P.Subtract(two) and Area(two) == 230000, "reenabling lost the open root or submenu")
    Release(submenu); Release(menu)
    -- A preexisting root needs public-manager discovery, not a description callback.
    local existing = Frame()
    existing:Layout(250, 250, 100, 100); existing:Show(); manager.root = existing
    P.Discover(); Cut("already-open unskinned menu was missed")
    manager.root = nil; existing:Hide(); existing:Reset()
    Clear("preexisting menu close left stale membership")
    -- Static popups follow the same actual-show and pending-layout rules.
    local static = Frame()
    StaticPopup1 = static
    P.Discover()
    static:Show()
    Clear("unpositioned static popup suppressed lower native windows")
    static:Layout(250, 250, 100, 100)
    Cut("late static layout was not promoted")
    static:Hide()
    Clear("hidden static popup left a cut")
    beforeReads, beforeChanges = reads, changes
    for _ = 1, 10000 do
        static:Fire("OnSizeChanged")
        static:SetPoint(); static:SetScale()
        Clear("closed popup history poisoned dimming")
    end
    Check(reads == beforeReads and changes == beforeChanges, "closed popup history performed native reads or callbacks")
    StaticPopup1 = nil
    P.SetActive(false)
    print("Window focus popup lifecycle " .. flavor .. ": pass")
end
print("Window focus popup checks: " .. checks)
