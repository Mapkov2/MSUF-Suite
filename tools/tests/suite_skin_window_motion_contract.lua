-- Check that the old window-outline entry points cannot leave artwork behind.
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
    for _, file in ipairs({ "Core/Client", "../MSUF_Suite/Appearance/Safety", "Core/Registry", "Rendering/Geometry",
        "Rendering/Motion", "Rendering/WindowFocusGeometry" }) do
        assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file .. ".lua"))("MSUF_Suite_Skin", ns)
    end
    local renderer = arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowMotion.lua"
    assert(loadfile(renderer))("MSUF_Suite_Skin", ns)
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
    local hook = frame.hooks[shown and "OnShow" or "OnHide"]
    if hook then hook(frame) end
end

local function AssertNoOutline(frames, message)
    for _, frame in ipairs(frames) do
        assert(not frame:IsShown() or not frame.textures, message)
    end
end

local function Run(forever, scenario)
    local skin, frames, Flush = Setup(forever)
    local owner, frame, window = "character", CharacterFrame, skin.WindowMotion
    skin.DB.theme.windowAnimations = "extended"
    if scenario == "close" then
        window.Watch(frame, owner)
        Flush()
        NativeVisible(frame, false)
        Flush()
        AssertNoOutline(frames, "closing a Blizzard window left a detached outline")
        NativeVisible(frame, true)
        Flush()
        NativeVisible(frame, false)
        window.Unwatch(frame, owner)
        AssertNoOutline(frames, "reopening and closing left a detached outline")
    elseif scenario == "resize" then
        window.Watch(frame, owner)
        Flush()
        frame.width = 500
        if frame.hooks.OnSizeChanged then frame.hooks.OnSizeChanged(frame, 500, frame.height) end
        Flush()
        AssertNoOutline(frames, "resizing a Blizzard window drew a detached outline")
    elseif scenario == "shop" then
        CatalogShopFrame = Frame("CatalogShopFrame", UIParent)
        CatalogShopFrame.protected = true
        for _, mode in ipairs({ "subtle", "extended", "off" }) do
            skin.DB.theme.windowAnimations = mode
            window.WatchShop(CatalogShopFrame, "shop")
            window.ShopVisibility(CatalogShopFrame, true)
            Flush()
            AssertNoOutline(frames, "opening the Shop drew a detached outline in " .. mode)
            NativeVisible(CatalogShopFrame, false)
            window.ShopVisibility(CatalogShopFrame, false)
            Flush()
            AssertNoOutline(frames, "closing the Shop drew a detached outline in " .. mode)
            window.Unwatch(CatalogShopFrame, "shop")
            NativeVisible(CatalogShopFrame, true)
        end
    elseif scenario == "preview" then
        local sample = Frame("StylePreview", Frame("StylePage", UIParent))
        window.WatchPreview(sample, owner)
        Flush()
        NativeVisible(sample, false)
        AssertNoOutline(frames, "closing the style sample drew a detached outline")
    end
    assert(not next(frame.hooks), "inactive outline renderer still hooks native windows")
    assert(frames[2] == nil, "inactive outline renderer still allocates a driver")
end

for _, scenario in ipairs({ "close", "resize", "shop", "preview" }) do
    if not arg[3] or arg[3] == scenario then
        Run(false, scenario)
        Run(true, scenario)
    end
end
print("no detached window outlines on Retail and Forever fixtures")
