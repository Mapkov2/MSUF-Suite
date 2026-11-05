-- Panel buttons that existed before the skin loaded are adopted by one
-- EnumerateFrames pass per session (Adapters/UIPanelButtons.lua). When the
-- feature is first enabled during combat the pass runs once combat ends, not
-- never; a disable during combat cancels it. The runtime contract on the
-- Advanced page names the pass instead of claiming there is none. Real
-- UIPanelButtons.lua, CombatGate.lua, SuiteOwnership.lua and Safety.lua.
local root = assert(arg[1], "Suite root required")
local Secrets = dofile(root .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua")
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

-- A button that already exists and shows the native handler.
local existing = { hooked = 0 }
function existing:IsForbidden() return false end
function existing:GetScript(name) return name == "OnShow" and NativeOnShow or nil end
function existing:HookScript(name) if name == "OnShow" then self.hooked = self.hooked + 1 end end
-- Forever SecureHelper.lua adds only ScriptBindings, not SetForbidden.
-- IsForbidden is false but GetScript and HookScript both reject addon calls.
local function Restricted(aspects, forbidden)
    local frame = { rejectHooks = true, aspectReads = 0, scriptReads = 0 }
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
-- Modern readable frames and older clients without the aspect API both work.
local modern = { hooked = 0, aspectReads = 0 }
modern.IsForbidden, modern.GetScript, modern.HookScript = existing.IsForbidden, existing.GetScript, existing.HookScript
function modern:HasAnyForbiddenAspects()
    self.aspectReads = self.aspectReads + 1
    return false
end
modern.SetButtonArtKit, modern.OnShow = NativeArtKit, NativeControllerShow
local frames = { helper, forbidden, unreadable, lookalike, modern, existing }
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
local NS = {
    DB = { enabled = true, skins = {} },
    IsCombatLocked = function() return locked end,
    GenericWindows = { IsCategoryEnabled = function() return true end },
    ControlSkin = { DisableOwner = function() return true end, GetOwner = Noop },
    WindowActionSkin = { GetOwner = Noop, IsApplied = function() return false end },
    Checkmarks = { TrackTexture = Noop, UntrackOwner = Noop, IsRedButtonArtKit = function() return false end },
}
MSUFSuite = { Suite = { OwnsBlizzardSurface = function() return false end } }
for _, file in ipairs({ "Core/Safety.lua", "Core/CombatGate.lua", "Core/Cosmetics.lua",
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

-- Enabled during combat: the pass runs once combat ends.
locked = true
Buttons.Apply()
Check(walks == 0 and Gate.GetPendingCount() > 0, "the adoption was neither run nor deferred")
EndCombat()
Check(walks == 1 and existing.hooked == 1, "a feature first enabled in combat never adopted existing buttons")
Check(helper.aspectReads == 1 and helper.scriptReads == 0, "SmartNavigation scripts were queried")
Check(forbidden.aspectReads == 0 and forbidden.scriptReads == 0, "fully forbidden frame was inspected")
Check(unreadable.aspectReads == 1 and unreadable.scriptReads == 0, "secret restriction failed open")
Check(lookalike.SetButtonArtKit == NativeArtKit and lookalike.OnShow == NativeControllerShow,
    "restricted mixin lookalike was hooked")
Check(modern.aspectReads == 1 and modern.hooked == 1, "readable modern button after helper was missed")
Check(modern.SetButtonArtKit ~= NativeArtKit and modern.OnShow ~= NativeControllerShow,
    "readable mixin adoption stopped working")
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
