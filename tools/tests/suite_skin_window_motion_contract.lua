-- Drive the real registry and detached window renderer. Native
-- panel methods fail if the renderer tries to change visibility or geometry.
local root = assert(arg[1], "Suite root required")
local secret = {}
issecretvalue = function(value) return value == secret end
securecallfunction = function(callback, ...) return callback(...) end
Enum = { UITextureSliceMode = { Stretched = 1 } }

local function Noop() end

local function Frame(name, parent)
    local frame = { name = name, parent = parent, shown = true, width = 300, height = 250,
        x = 30, y = 60, scripts = {}, hooks = {}, events = {} }
    function frame:IsForbidden() return self.forbidden end
    function frame:IsProtected() return self.protected, false end
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetLeft() return self.x end
    function frame:GetBottom() return self.y end
    function frame:GetEffectiveScale() return self.scale or 1 end
    function frame:GetFrameStrata() return "MEDIUM" end
    function frame:GetFrameLevel() return 5 end
    function frame:HasScript() return true end
    function frame:HookScript(event, callback)
        assert(not self.hooks[event], "window hook attached twice: " .. event)
        self.hooks[event] = callback
    end
    local function Owned(self) assert(not self.name, "unexpected write to " .. tostring(self.name)) end
    function frame:SetParent(value) Owned(self) self.parent = value end
    function frame:Show() Owned(self) self.shown = true end
    function frame:Hide() Owned(self) self.shown = false end
    function frame:SetAlpha(value) Owned(self) self.alpha = value end
    function frame:SetSize(width, height) Owned(self) self.width, self.height = width, height end
    function frame:SetPoint(_, relative, _, x, y) Owned(self) self.anchor, self.x, self.y = relative, x, y end
    function frame:EnableMouse(value) Owned(self) self.mouse = value end
    function frame:ClearAllPoints() Owned(self) end
    function frame:SetFrameStrata() Owned(self) end
    function frame:SetFrameLevel() Owned(self) end
    function frame:SetScript(event, callback) Owned(self) self.scripts[event] = callback end
    function frame:RegisterEvent(event) Owned(self) self.events[event] = true end
    function frame:CreateTexture(_, layer)
        Owned(self)
        local texture = { SetAllPoints = Noop,
            ClearTextureSlice = Noop, SetTextureSliceMargins = Noop, SetTextureSliceMode = Noop }
        function texture:SetVertexColor(_, _, _, alpha) self.alpha = alpha end
        function texture:SetTexture(asset) self.asset = asset end
        self.textures = self.textures or {}
        self.textures[layer] = texture
        return texture
    end
    return frame
end

local function Setup(forever)
    local frames, timers = {}, {}
    local lockdown, gamepad = false, false
    UIParent = Frame("UIParent")
    CharacterFrame = Frame("CharacterFrame", UIParent)
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    GameEvent = forever and { RegisterCamelotEvents = Noop } or nil
    InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
    InCombatLockdown = function() return lockdown end
    C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    CreateFrame = function() local frame = Frame() frames[#frames + 1] = frame return frame end
    local ns = { path = "", DB = { theme = {} }, IsCombatLocked = InCombatLockdown,
        CombatGate = { RunOrDefer = Noop }, GeometryBorders = { 0, 1, 2 }, GeometryRadii = { 4, 8, 12 },
        Defaults = { geometry = { family = "continuous", radius = 4 } } }
    ns.Theme = { GetColor = function() return 1, 1, 1, 1 end,
        GetWindowAnimationMode = function() return ns.DB.theme.windowAnimations or "subtle" end }
    ns.WindowControls = { SetGeometryMotionProvider = function(geometry, interaction)
        ns.WindowControls.geometry, ns.WindowControls.interaction = geometry, interaction
    end }
    ns.WindowControlPolicy = { IsAnimationWindow = function(frame) return frame == FriendsFrame end }
    for _, file in ipairs({ "Core/Client", "Core/Safety", "Core/Registry", "Rendering/Geometry",
        "Rendering/Motion", "Rendering/WindowFocusGeometry", "Rendering/WindowMotion" }) do
        assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file .. ".lua"))("MSUF_Suite_Skin", ns)
    end
    local function Flush()
        local pending = timers
        timers = {}
        for index = 1, #pending do pending[index]() end
    end
    local function Combat(active)
        lockdown = active
        local event = active and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED"
        for _, frame in ipairs(frames) do if frame.events[event] then frame.scripts.OnEvent(frame, event) end end
    end
    return ns, frames, Flush, Combat, function(value) gamepad = value end
end

local function NativeVisible(frame, shown)
    frame.shown = shown
    frame.hooks[shown and "OnShow" or "OnHide"](frame)
end

local function Run(forever)
    local skin, frames, Flush, Combat, Gamepad = Setup(forever)
    local owner, frame, window = "character", CharacterFrame, skin.WindowMotion
    FriendsFrame = Frame("FriendsFrame", UIParent)
    assert(window.Watch(FriendsFrame, owner), "catalogued top-level frames should get extended window effects")
    window.Unwatch(FriendsFrame, owner)
    ArbitraryFrame = Frame("ArbitraryFrame", UIParent)
    assert(not window.Watch(ArbitraryFrame, owner), "a global name alone must not opt in")
    assert(not window.Watch(Frame("CharacterFrame", UIParent), owner), "duplicate name passed the allowlist")
    frame.name = secret
    assert(not window.Watch(frame, owner), "secret name passed the allowlist")
    frame.name = "CharacterFrame"
    frame.protected = true
    assert(not window.Watch(frame, owner), "implicit protection must be honored")
    frame.protected, frame.parent = nil, secret
    assert(not window.Watch(frame, owner), "secret parent allowed")
    frame.parent = UIParent
    assert(window.Watch(frame, owner) and not next(frame.hooks), "default mode installed extended hooks")
    local function Mode(mode, reduced)
        skin.DB.theme.windowAnimations, skin.DB.theme.reduceMotion = mode, reduced
        skin.Registry.NotifyListeners("motion", "windowAnimations")
        Flush()
    end
    local function Size(width)
        frame.width = width
        frame.hooks.OnSizeChanged(frame, width, frame.height)
    end
    Mode("extended")
    Size(500)
    Size(480)
    assert(#frames == 2, "resize did visual work before native layout settled")
    Flush()
    local proxy = assert(frames[3], "resize failed to create an outline")
    local driver = frames[2]
    local function Tick(elapsed) driver.scripts.OnUpdate(driver, elapsed) end
    assert(proxy:IsShown() and proxy.mouse == false and proxy.anchor == UIParent and proxy.width == 300)
    assert(proxy.textures.BORDER.asset:match("_edge2%.png$") and proxy.textures.BORDER.alpha >= 0.9)
    assert(proxy.textures.BACKGROUND.alpha >= 0.12 and proxy.textures.BACKGROUND.alpha <= 0.25)
    Tick(0.06)
    assert(proxy.width > 315 and proxy.width < 390 and frame.width == 480 and proxy.alpha > 0.9,
        "resize effect became too fast or faded too early")
    Tick(0.15)
    assert(proxy:IsShown() and proxy.width > 440 and proxy.width < 480 and proxy.alpha > 0.35,
        "extended resize must still be visible at 210 ms")
    Tick(0.08)
    assert(not proxy:IsShown() and not driver.scripts.OnUpdate, "resize must finish and release its driver")
    frame.scale = 1.2
    skin.WindowControls.geometry(frame)
    Flush()
    assert(proxy:IsShown() and proxy.width == 480, "native scale change has no OnSizeChanged event")
    NativeVisible(frame, false)
    assert(proxy:IsShown() and not frame:IsShown(), "native close should be immediate")
    local closeWidth = proxy.width
    assert(proxy.textures.BACKGROUND.alpha > 0.2, "close trace must have a visible fill")
    Tick(0.12)
    assert(proxy.width < closeWidth * 0.94 and proxy.width > closeWidth * 0.84 and proxy.alpha > 0.7,
        "extended close must visibly shrink and remain legible halfway through")
    NativeVisible(frame, true)
    Flush()
    assert(not proxy:IsShown() and not driver.scripts.OnUpdate, "reopen did not clear the old close trace")
    NativeVisible(frame, false)
    Tick(0.23)
    assert(proxy:IsShown() and proxy.width < closeWidth * 0.87, "close effect was too short or too small")
    Tick(0.04)
    assert(not proxy:IsShown() and not driver.scripts.OnUpdate, "close must finish and release its driver")
    NativeVisible(frame, true)
    Flush()
    skin.WindowControls.interaction(frame, true)
    Size(510)
    Flush()
    assert(not proxy:IsShown(), "manual resizing must stay immediate")
    skin.WindowControls.interaction(frame, false)
    Flush()
    Size(secret)
    Flush()
    NativeVisible(frame, false)
    assert(not proxy:IsShown(), "unreadable bounds must not animate stale geometry")
    frame.width = 510
    NativeVisible(frame, true)
    Flush()
    Size(600)
    Combat(true)
    Combat(false)
    Flush()
    assert(not proxy:IsShown(), "queued resize replayed after combat")
    Size(650)
    Flush()
    assert(proxy:IsShown(), "resize did not recover after combat")
    Mode("extended", true)
    assert(not proxy:IsShown(), "reduced motion did not stop the active trace")
    Mode("off")
    Size(670)
    Flush()
    Mode("extended")
    Gamepad(true)
    if forever then
        Size(700)
        Flush()
        assert(not proxy:IsShown(), "Forever Gamepad UI should own its own windows")
        Gamepad(false)
        Mode("extended")
    end
    window.Unwatch(frame, owner)
    NativeVisible(frame, false)
    assert(not proxy:IsShown() and #frames == 3, "unwatched window still animates or leaks overlays")
end

local function Shop()
    local skin, frames, Flush = Setup(true)
    local window = skin.WindowMotion
    local shop = Frame("CatalogShopFrame", UIParent)
    CatalogShopFrame, shop.protected = shop, true
    for _, method in ipairs({ "GetLeft", "GetBottom", "GetWidth", "GetHeight", "GetFrameLevel", "GetFrameStrata" }) do
        local read = shop[method]
        shop[method] = function(self)
            assert(self.shown, "read Shop geometry after secure teardown")
            return read(self)
        end
    end
    skin.DB.theme.windowAnimations = "extended"
    assert(window.WatchShop(shop, "shop") and not next(shop.hooks), "secure shop must not have script hooks")
    Flush()
    local driver, proxy = frames[2], assert(frames[3], "first already-visible shop did not open with a trace")
    assert(proxy:IsShown() and proxy.mouse == false and proxy.width == 270)
    driver.scripts.OnUpdate(driver, 0.15)
    assert(proxy:IsShown() and proxy.width > 270 and proxy.width < 300, "extended shop reveal lost its motion")
    shop.shown = false
    window.ShopVisibility(shop, false)
    assert(proxy:IsShown() and proxy.width == 300, "native shop close did not start from settled geometry")
    shop.shown = true
    window.ShopVisibility(shop, true)
    assert(not proxy:IsShown(), "rapid shop reopen left the old close trace")
    Flush()
    skin.DB.theme.windowAnimations = "subtle"
    skin.Registry.NotifyListeners("motion", "windowAnimations")
    window.ShopVisibility(shop, true)
    Flush()
    assert(proxy:IsShown() and proxy.width == 300, "subtle shop opening should fade a stationary contour")
    driver.scripts.OnUpdate(driver, 0.13)
    assert(not proxy:IsShown() and not driver.scripts.OnUpdate)
    skin.DB.theme.windowAnimations = "off"
    window.ShopVisibility(shop, true)
    Flush()
    assert(not proxy:IsShown() and not driver.scripts.OnUpdate)
    window.Unwatch(shop, "shop")
end

local function Preview()
    local skin, frames, Flush = Setup(false)
    local parent = Frame("StylePage", UIParent)
    local sample = Frame("StylePreview", parent)
    skin.DB.theme.windowAnimations = "extended"
    assert(skin.WindowMotion.WatchPreview(sample, parent))
    Flush()
    parent.shown = false
    sample.hooks.OnHide(sample)
    assert(#frames == 2, "hiding the Style page must not leave a preview trace")
    parent.shown = true
    sample.hooks.OnShow(sample)
    Flush()
    NativeVisible(sample, false)
    assert(frames[3]:IsShown(), "closing the preview should demonstrate the native-window effect")
end

Run(false)
Run(true)
Preview()
Shop()
print("window motion contract passed on Retail and Forever fixtures")
