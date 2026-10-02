-- Panel buttons that existed before the skin loaded are adopted by one
-- EnumerateFrames pass per session (Adapters/UIPanelButtons.lua). When the
-- feature is first enabled during combat the pass runs once combat ends, not
-- never; a disable during combat cancels it. The runtime contract on the
-- Advanced page names the pass instead of claiming there is none. Real
-- UIPanelButtons.lua, CombatGate.lua, SuiteOwnership.lua and Safety.lua.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

securecallfunction = function(callback, ...) return callback(...) end
function hooksecurefunc(target, method, callback)
    if type(target) == "string" then target, method, callback = _G, target, method end
    local original = target[method]
    assert(type(original) == "function", "hook target missing: " .. tostring(method))
    target[method] = function(...)
        original(...)
        callback(...)
    end
end
-- The handler Blizzard's XML bound to buttons created before the skin loaded.
local function NativeOnShow() end
UIPanelButton_OnShow = NativeOnShow
UIPanelCloseButton_SetBorderAtlas = Noop
EventUtil = { ContinueOnAddOnLoaded = Noop }

local gateFrame
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
local walks = 0
EnumerateFrames = function(previous)
    if previous == nil then
        walks = walks + 1
        return existing
    end
    return nil
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
-- Once per session.
Buttons.Apply()
Check(walks == 1 and existing.hooked == 1, "the frame pass ran again")

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

print("Suite skin panel button adoption: " .. checks .. " checks passed")
