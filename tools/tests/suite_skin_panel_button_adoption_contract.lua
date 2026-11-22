-- Panel buttons that existed before the skin loaded are adopted by one
-- EnumerateFrames pass per session (Adapters/UIPanelButtons.lua). When the
-- feature is first enabled during combat the pass runs once combat ends, not
-- never; a disable during combat cancels it. The runtime contract on the
-- Advanced page names the pass instead of claiming there is none. Real
-- UIPanelButtons.lua, CombatGate.lua, SuiteOwnership.lua, Safety.lua and the
-- Suite's HostBridge.lua, which owns the MSUF Auras3 marker read.
local root = assert(arg[1], "Suite root required")
local Secrets = dofile(root .. "/../MidnightSimpleUnitFrames-7.0/tools/tests/classpower_secrets.lua")
Secrets.Install()
Secrets.GUARD_NAMES.falsy.Public = true
local stopWatch = Secrets.Watch(root .. "/MSUF_Suite_Skin/Adapters/UIPanelButtons.lua", { strict = true })
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

securecallfunction = function(callback, ...) return callback(...) end
function hooksecurefunc(target, method, callback)
    if type(target) == "string" then target, method, callback = _G, target, method end
    assert(not target.rejectHooks, "restricted frame received a method hook")
    local original = target[method]
    assert(type(original) == "function", "hook target missing: " .. tostring(method))
    target[method] = function(...)
        original(...)
        callback(...)
    end
end
-- The handler Blizzard's XML bound to buttons created before the skin loaded.
local function NativeOnShow() end
local function NativeArtKit() end
local function NativeControllerShow() end
UIButtonMixin = { SetButtonArtKit = NativeArtKit }
ButtonControllerMixin = { OnShow = NativeControllerShow }
local secret = Secrets.New("boolean")
UIPanelButton_OnShow = NativeOnShow
UIPanelCloseButton_SetBorderAtlas = Noop
EventUtil = { ContinueOnAddOnLoaded = Noop }

local gateFrame
-- CombatGate times its drain (about 4 ms per frame); these jobs cost nothing.
debugprofilestop = function() return 0 end
CreateFrame = function()
    gateFrame = { events = {} }
    function gateFrame:RegisterEvent(event) self.events[event] = true end
    function gateFrame:UnregisterEvent(event) self.events[event] = nil end
    function gateFrame:SetScript(_, script) self.script = script end
    return gateFrame
end

-- Widget methods come from the widget type's shared method table, so a method
-- of another type reads as nil. GetButtonState is Button's own and is inherited
-- by every Button-derived type (CheckButton, ItemButton, the intrinsic
-- buttons); Frame, Cooldown, StatusBar and the rest lack it.
local function ButtonState() return "NORMAL" end
-- A button that already exists and shows the native handler.
local existing = { hooked = 0, GetButtonState = ButtonState }
function existing:IsForbidden() return false end
function existing:GetScript(name) return name == "OnShow" and NativeOnShow or nil end
function existing:HookScript(name) if name == "OnShow" then self.hooked = self.hooked + 1 end end
-- Forever SecureHelper.lua adds only ScriptBindings, not SetForbidden.
-- IsForbidden is false but GetScript and HookScript both reject addon calls.
local function Restricted(aspects, forbidden, notButton)
    local frame = { rejectHooks = true, aspectReads = 0, scriptReads = 0 }
    if not notButton then frame.GetButtonState = ButtonState end
    function frame:IsForbidden() return forbidden == true end
    function frame:HasAnyForbiddenAspects()
        assert(not forbidden, "fully forbidden frame queried beyond IsForbidden")
        self.aspectReads = self.aspectReads + 1
        return aspects
    end
    function frame:GetScript()
        self.scriptReads = self.scriptReads + 1
        error("SmartNavigationSecureHelper:GetScript(): forbidden aspect 'ScriptBindings'")
    end
    function frame:HookScript() error("restricted frame received a script hook") end
    return frame
end
local helper = Restricted(true)
local forbidden = Restricted(true, true)
local unreadable = Restricted(secret)
local lookalike = Restricted(true)
lookalike.SetButtonArtKit = NativeArtKit
lookalike.OnShow = NativeControllerShow
-- The same holds without Button methods: a raw mixin match on any frame type
-- is still checked for restrictions before it is hooked.
local frameLookalike = Restricted(true, false, true)
frameLookalike.SetButtonArtKit = NativeArtKit
frameLookalike.OnShow = NativeControllerShow
-- A restricted frame that is no Button and carries no native mixin handler is
-- no candidate: nothing beyond IsForbidden is asked of it.
local plainHelper = Restricted(true, false, true)
-- The same with unreadable raw fields under the mixin keys: a secret is never
-- compared with the native handler, and the frame stays a non-candidate.
local secretFields = Restricted(true, false, true)
secretFields.SetButtonArtKit, secretFields.OnShow = secret, secret
-- Modern readable frames and older clients without the aspect API both work.
local modern = { hooked = 0, aspectReads = 0, GetButtonState = ButtonState }
modern.IsForbidden, modern.GetScript, modern.HookScript = existing.IsForbidden, existing.GetScript, existing.HookScript
function modern:HasAnyForbiddenAspects()
    self.aspectReads = self.aspectReads + 1
    return false
end
modern.SetButtonArtKit, modern.OnShow = NativeArtKit, NativeControllerShow
-- Blizzard_AuraContainerFrameProviders' native buttons, managed by MSUF Auras3.
-- IsForbidden is public false, yet HasAnyForbiddenAspects can raise on them
-- from addon code. This fixture raises from it on the client that has it
-- (Forever) and from the script accessors on both, so any call past the raw
-- host marker is counted. The fixture carries the native mixin handlers too,
-- so any hook would be visible.
local function AuraButton(marker, hasAspectApi)
    local frame = { rejectHooks = true, probes = 0, forbiddenReads = 0,
        _msufA3ManagedAuraButton = marker, _msufA3NativeButton = true, _msufPixelLayoutOwned = true,
        SetButtonArtKit = NativeArtKit, OnShow = NativeControllerShow }
    local function Raise(self)
        self.probes = self.probes + 1
        error("Attempt to access forbidden object from code tainted by an AddOn")
    end
    function frame:IsForbidden()
        self.forbiddenReads = self.forbiddenReads + 1
        return false
    end
    if hasAspectApi then frame.HasAnyForbiddenAspects = Raise end
    frame.GetScript, frame.HookScript = Raise, Raise
    return frame
end
local auraButtons = {
    AuraButton(true, true),   -- Forever: aspect API present
    AuraButton(true, false),  -- Retail: no aspect API, script accessors raise
    AuraButton(secret, true), -- unreadable ownership is refused, not probed
    AuraButton(1, true),      -- unexpected truthy marker is still ownership
}
-- No Auras3 ownership: a false or missing marker, even on a pixel-layout
-- owned button, leaves a readable native button adoptable.
local function Unowned(marker)
    local frame = { hooked = 0, aspectReads = 0, _msufA3ManagedAuraButton = marker, _msufPixelLayoutOwned = true,
        GetButtonState = ButtonState }
    frame.IsForbidden, frame.GetScript, frame.HookScript = existing.IsForbidden, existing.GetScript, existing.HookScript
    function frame:HasAnyForbiddenAspects()
        self.aspectReads = self.aspectReads + 1
        return false
    end
    return frame
end
local released, pixelOnly = Unowned(false), Unowned(nil)
-- The Cooldown child MSUF Auras3 creates on a managed aura button
-- (ButtonVisuals.lua). It carries the pixel-layout markers but not the Auras3
-- button marker, IsForbidden is public false, and HasAnyForbiddenAspects
-- raises on it from addon code (the 2026-11 Forever login error). Shaped as
-- the client shapes a widget: the markers are raw instance fields, the methods
-- sit behind the metatable, and a Cooldown has no Button method. Only the
-- enumeration's own IsForbidden and the identity getters answer; every other
-- call raises and is counted. Indexing a method without calling it is safe:
-- the reported error came from the call, after the same index.
local function Cooldown()
    local frame = { forbiddenReads = 0, probes = 0, identityReads = 0,
        _msufPixelLayoutOwned = true, _msufPixelLayoutEnabled = true, _msufPixelLayoutTemplateVisited = true }
    local methods = {}
    local function Raise(self)
        self.probes = self.probes + 1
        error("Attempt to access forbidden object from code tainted by an AddOn")
    end
    function methods:IsForbidden()
        self.forbiddenReads = self.forbiddenReads + 1
        return false
    end
    function methods:GetObjectType()
        self.identityReads = self.identityReads + 1
        return "Cooldown"
    end
    function methods:IsObjectType(objectType)
        self.identityReads = self.identityReads + 1
        return objectType == "Cooldown" or objectType == "Frame"
    end
    for _, name in ipairs({ "HasAnyForbiddenAspects", "GetScript", "HookScript", "HasScript", "GetParent",
        "GetName", "IsProtected", "SetCooldown" }) do
        methods[name] = Raise
    end
    return setmetatable(frame, { __index = methods })
end
local cooldown, legacyCooldown = Cooldown(), Cooldown()
-- ButtonControllerMixin sits on a plain Frame child of the button, and an art
-- kit handler is matched by its raw field, whatever the frame type: neither
-- has a Button method, and neither is asked for a script.
local function MixinFrame(key, handler)
    local frame = { aspectReads = 0, scriptReads = 0, [key] = handler }
    function frame:IsForbidden() return false end
    function frame:HasAnyForbiddenAspects()
        self.aspectReads = self.aspectReads + 1
        return false
    end
    function frame:GetScript() self.scriptReads = self.scriptReads + 1 end
    function frame:HookScript() error("a frame that is no Button received a script hook") end
    return frame
end
local controllerFrame = MixinFrame("OnShow", NativeControllerShow)
local artKitFrame = MixinFrame("SetButtonArtKit", NativeArtKit)
-- The Cooldown and the aura buttons come first: the valid modern and legacy
-- targets follow them.
local frames = { cooldown, auraButtons[1], auraButtons[2], auraButtons[3], auraButtons[4],
    helper, plainHelper, secretFields, forbidden, unreadable, lookalike, frameLookalike, released, pixelOnly,
    controllerFrame, artKitFrame, modern, existing }
local walks = 0
EnumerateFrames = function(previous)
    if previous == nil then
        walks = walks + 1
        return frames[1]
    end
    for index = 1, #frames do
        if frames[index] == previous then return frames[index + 1] end
    end
    error("unknown enumeration cursor")
end

local locked = false
InCombatLockdown = function() return locked end
local NS = {
    DB = { enabled = true, skins = {} },
    IsCombatLocked = function() return locked end,
    GenericWindows = { IsCategoryEnabled = function() return true end },
    ControlSkin = { DisableOwner = function() return true end, GetOwner = Noop },
    WindowActionSkin = { GetOwner = Noop, IsApplied = function() return false end },
    Checkmarks = { TrackTexture = Noop, UntrackOwner = Noop, IsRedButtonArtKit = function() return false end },
}
-- The real host bridge on a tiny Suite root, shaped as the addon publishes
-- it: HostBridge and Public on the root namespace, the lifecycle controller
-- as its Suite member. Public is the strict Secrets mock's rule
-- (Core/Platform.lua), counted so the bridge guard is observable.
local publicReads, secretReads = 0, 0
local Suite = { OwnsBlizzardSurface = function() return false end }
local SuiteRoot = { Suite = Suite }
function SuiteRoot.Public(value)
    publicReads = publicReads + 1
    local readable = issecretvalue == nil or not issecretvalue(value)
    if not readable then secretReads = secretReads + 1 end
    return readable
end
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", SuiteRoot)
local HostBridge = SuiteRoot.HostBridge
Check(HostBridge ~= nil and Suite.HostBridge == nil, "the host bridge was not published on the Suite root")
MSUFSuite = SuiteRoot
for _, file in ipairs({ "../MSUF_Suite/Appearance/Safety.lua", "../MSUF_Suite/Appearance/CombatGate.lua", "../MSUF_Suite/Appearance/Cosmetics.lua",
    "Core/SuiteOwnership.lua", "Adapters/UIPanelButtons.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
local Buttons, Gate = NS.UIPanelButtons, NS.CombatGate
local function EndCombat()
    locked = false
    gateFrame.script(gateFrame, "PLAYER_REGEN_ENABLED")
end

-- Enabled during combat, then disabled before it ends: no pass.
locked = true
Buttons.Apply()
Check(walks == 0, "the frame pass ran during combat")
Buttons.Disable()
EndCombat()
Check(walks == 0 and Gate.GetPendingCount() == 0, "a disabled feature adopted buttons after combat")

-- A legacy Suite without the bridge capability still adopts: the pass runs
-- without the marker read. It walks its own frame list here, so the session
-- frames below stay untouched, and the once-per-session latch is then
-- cleared for the real pass.
local legacy = { hooked = 0, GetButtonState = ButtonState }
legacy.IsForbidden, legacy.GetScript, legacy.HookScript = existing.IsForbidden, existing.GetScript, existing.HookScript
local sessionFrames = frames
frames = { legacyCooldown, legacy }
SuiteRoot.HostBridge = nil
Buttons.Apply()
Check(walks == 1 and legacy.hooked == 1 and auraButtons[1].forbiddenReads == 0 and existing.hooked == 0,
    "a Suite without the aura-button bridge did not adopt existing buttons")
Check(legacyCooldown.forbiddenReads == 1 and legacyCooldown.probes == 0,
    "a Suite without the aura-button bridge probed an Auras3 Cooldown beyond IsForbidden")
Buttons.Disable()
SuiteRoot.HostBridge = HostBridge
frames, walks, Buttons.adopted = sessionFrames, 0, false
Check(publicReads == 0, "the host bridge was consulted outside the adoption pass")

-- Enabled during combat: the pass runs once combat ends.
locked = true
Buttons.Apply()
Check(walks == 0 and Gate.GetPendingCount() > 0, "the adoption was neither run nor deferred")
EndCombat()
Check(walks == 1 and existing.hooked == 1, "a feature first enabled in combat never adopted existing buttons")
Check(cooldown.forbiddenReads == 1 and cooldown.probes == 0,
    "an Auras3 Cooldown was probed beyond IsForbidden")
Check(helper.aspectReads == 1 and helper.scriptReads == 0, "SmartNavigation scripts were queried")
Check(plainHelper.aspectReads == 0 and plainHelper.scriptReads == 0,
    "a restricted frame that is no candidate was probed")
Check(secretFields.aspectReads == 0 and secretFields.scriptReads == 0,
    "a non-candidate with secret raw mixin fields was probed")
Check(forbidden.aspectReads == 0 and forbidden.scriptReads == 0, "fully forbidden frame was inspected")
Check(unreadable.aspectReads == 1 and unreadable.scriptReads == 0, "secret restriction failed open")
Check(lookalike.SetButtonArtKit == NativeArtKit and lookalike.OnShow == NativeControllerShow,
    "restricted mixin lookalike was hooked")
Check(frameLookalike.aspectReads == 1 and frameLookalike.scriptReads == 0
    and frameLookalike.SetButtonArtKit == NativeArtKit and frameLookalike.OnShow == NativeControllerShow,
    "restricted mixin lookalike that is no Button was hooked or not checked")
Check(controllerFrame.aspectReads == 1 and controllerFrame.OnShow ~= NativeControllerShow
    and controllerFrame.scriptReads == 0, "a button controller on a plain frame was not adopted by its raw handler")
Check(artKitFrame.aspectReads == 1 and artKitFrame.SetButtonArtKit ~= NativeArtKit
    and artKitFrame.scriptReads == 0, "an art kit handler on another frame type was not adopted by its raw field")
Check(modern.aspectReads == 1 and modern.hooked == 1, "readable modern button after helper was missed")
Check(modern.SetButtonArtKit ~= NativeArtKit and modern.OnShow ~= NativeControllerShow,
    "readable mixin adoption stopped working")
for index = 1, #auraButtons do
    local aura = auraButtons[index]
    Check(aura.forbiddenReads == 1 and aura.probes == 0,
        "Auras3-managed native button " .. index .. " was probed beyond IsForbidden")
    Check(aura.SetButtonArtKit == NativeArtKit and aura.OnShow == NativeControllerShow,
        "Auras3-managed native button " .. index .. " was hooked")
end
Check(released.aspectReads == 1 and released.hooked == 1, "a false Auras3 marker excluded a native button")
Check(pixelOnly.aspectReads == 1 and pixelOnly.hooked == 1, "pixel-layout ownership alone excluded a native button")
-- The marker crossed the real bridge: every non-forbidden frame once, the
-- secret marker through the root's Public, with the fail-closed answers.
Check(publicReads == #frames - 1 and secretReads == 1, "the host bridge guard did not read each marker once")
Check(HostBridge.ManagesAuraButton(auraButtons[3]) == true and HostBridge.ManagesAuraButton(auraButtons[4]) == true
    and HostBridge.ManagesAuraButton(released) == false and HostBridge.ManagesAuraButton(pixelOnly) == false,
    "the host bridge misreported Auras3 ownership")
-- Once per session.
Buttons.Apply()
Check(walks == 1 and existing.hooked == 1 and modern.hooked == 1, "the frame pass ran again")
Buttons.Disable()
Buttons.Apply()
Check(walks == 1 and existing.hooked == 1 and modern.hooked == 1, "re-enable repeated the frame pass")

-- The runtime contract names the pass, in both locales.
local function Read(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"))
    local text = handle:read("*a")
    handle:close()
    return text
end
local claim = "No global frame enumeration"
local named = "• One frame walk per session, when the window skin is first enabled, adopts existing panel buttons"
for _, path in ipairs({ "MSUF_Suite_Skin_Options/Pages/Advanced.lua", "MSUF_Suite_Skin/Locales/enUS.lua",
    "MSUF_Suite/Locales/deDE.lua" }) do
    local text = Read(path)
    Check(not text:find(claim, 1, true) and text:find(named, 1, true),
        path .. " still claims there is no global frame enumeration")
end
Check(Read("MSUF_Suite/Locales/deDE.lua"):find("• Ein Frame-Durchlauf pro Sitzung", 1, true),
    "the German runtime contract does not name the frame pass")

local violations = stopWatch()
Check(#violations == 0, "secret restriction tested before Public guard: " .. table.concat(violations, "; "))

print("Suite skin panel button adoption: " .. checks .. " checks passed")
