local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
securecallfunction = function(fn, ...) return fn(...) end
MSUF_NS = { Client = { Family = "Mainline", Flavor = "Mainline", IsForever = flavor == "Forever", IsRetail = flavor == "Mainline" } }
SlashCmdList = {}
local combat, gamepad, mounted = false, false, false
InCombatLockdown = function() return combat end
local frames = {}
CreateFrame = function()
    local frame = { scripts = {}, events = {} }
    function frame:SetScript(event, fn) self.scripts[event] = fn end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = frame
    return frame
end
local NS = {}
Support.Load(root, "MSUF_Suite", NS, "Core/Suite.lua", nil, "Mainline")
assert(NS.Database.Initialize(nil))
local S = NS.Suite
S.CreateFrame = CreateFrame
S.GamepadUI = function() return gamepad end
function SecureCmdOptionParse(expression)
    for part in expression:gmatch("[^;]+") do
        local condition, command = part:match("^%s*%[(.-)%]%s*(%w+)")
        if not condition then return part:match("%w+") end
        if condition == "combat" and combat or condition == "nocombat" and not combat
            or condition == "mounted" and mounted then return command end
    end
end
local available = { bags = true, dataTexts = true }
S.Availability = function(id) return available[id] ~= false end
S.NewContext = function()
    local context = {}
    local originalMotion
    function context:Property(frame, getter, setter, value)
        if originalMotion == nil then originalMotion = frame[getter](frame) end
        frame[setter](frame, value)
    end
    function context:RestoreProperty(frame, setter)
        if originalMotion == nil then return end
        frame[setter](frame, originalMotion)
        originalMotion = nil
    end
    function context:Release() end
    return context
end
S.RefreshEditMover, S.UnregisterEditElements = function() end, function() end
NS.Skin = { SurfacesChanged = function() end }
local backpack = { scripts = {} }
function backpack:HookScript(event, fn) self.scripts[event] = fn end
function backpack:GetChildren() end
BagsBar = { shown = true, alpha = .8, scripts = {}, motion = false, over = false }
function BagsBar:IsShown() return self.shown end
function BagsBar:Hide() self.shown = false end
function BagsBar:Show()
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function BagsBar:HookScript(event, fn) self.scripts[event] = fn end
function BagsBar:GetChildren() return backpack end
function BagsBar:IsMouseOver() return self.over end
function BagsBar:IsMouseMotionEnabled() return self.motion end
function BagsBar:SetMouseMotionEnabled(enabled) self.motion = enabled end
function BagsBar:GetAlpha() return self.alpha end
function BagsBar:SetAlpha(alpha) self.alpha = alpha end
local deviceHooks = {}
if flavor == "Forever" then
    assert(NS.Client.isForever, "expected Forever client metadata")
    MainActionBar_InitializeGamepad = function() gamepad = true; BagsBar:Hide() end
    MainActionBar_InitializeMKB = function() gamepad = false; BagsBar:Show() end
    hooksecurefunc = function(name, callback)
        local native = assert(_G[name])
        _G[name] = function() native(); callback() end
        deviceHooks[name] = (deviceHooks[name] or 0) + 1
    end
end
local timer
C_Timer = { NewTimer = function(_, callback)
    timer = { call = callback, Cancel = function(self) self.call = nil end }
    return timer
end }
RegisterStateDriver = function(frame, _, value)
    frame.driver = value
    if SecureCmdOptionParse(value) == "hide" then frame:Hide() else frame:Show() end
end
UnregisterStateDriver = function(frame) frame.driver = nil end
local mode = NS.BagsBarVisibility
local function VerifyMigration(data, wanted, newChoice)
    local profile = { suite = { revision = S.MigrationRevision, modules = {
        dataTexts = data, bags = { bagBarVisibility = newChoice },
    } } }
    S.Normalize(profile)
    assert(profile.suite.modules.bags.bagBarVisibility == wanted, "old bag-bar choice was not migrated to Bags")
end
VerifyMigration({ enabled = true, hideBlizzardBagBar = true }, mode.NEVER)
VerifyMigration({ enabled = true, hideBlizzardBagBar = false, bagBarMouseover = true }, mode.MOUSEOVER)
VerifyMigration({ enabled = false, hideBlizzardBagBar = true }, mode.ALWAYS)
VerifyMigration({ enabled = true, bar1Slot1 = 2 }, mode.ALWAYS)
VerifyMigration({ enabled = true, hideBlizzardBagBar = true }, mode.IN_COMBAT, mode.IN_COMBAT)
local bag = {}
local P = { NS = NS, Suite = S, BagsModule = bag }
assert(loadfile(root .. "/MSUF_Suite_Bags/NativeBagBar.lua"))("Bags", P)
bag.Enable, bag.Refresh, bag.Disable = P.NativeBagBar.Refresh, P.NativeBagBar.Refresh, P.NativeBagBar.Disable
S.instances.bags = bag
S.Config("dataTexts").enabled = false
S.Config("bags").bagBarVisibility = mode.NEVER
S.Config("bags").inventoryView, S.Config("bags").enabled = 1, false
S.started = true
S.Apply("bags")
assert(BagsBar.shown and not BagsBar.driver, "disabled Bags preserves native equipped slots")
local native = BagsBar
BagsBar = nil
S.Config("bags").enabled = true
S.Apply("bags")
BagsBar = native
for _, frame in ipairs(frames) do
    if frame.events.ADDON_LOADED then frame.scripts.OnEvent(frame, "ADDON_LOADED", "Blizzard_MainMenuBarBagButtons") end
end
assert(not BagsBar.shown and BagsBar.driver == "hide", "Bags did not hide the late-loading HUD bar")
assert(S.OwnsBlizzardSurface("bagBar"), "skin yields to Bags when it hides the native slots")
S.Config("bags").inventoryView = 4
S.Apply("bags")
assert(not BagsBar.shown and BagsBar.driver == "hide" and S.OwnsBlizzardSurface("bagBar"),
    "Blizzard grid ignores the existing hide setting")
assert(S.Set("bags", "bagBarVisibility", mode.MOUSEOVER))
assert(BagsBar.shown and not BagsBar.driver and BagsBar.alpha == 0 and BagsBar.motion
    and not S.OwnsBlizzardSurface("bagBar"), "mouseover displaced Blizzard buttons or their skin")
BagsBar.over = true
backpack.scripts.OnEnter(backpack)
assert(BagsBar.alpha == .8, "mouseover did not reveal the native bag bar")
backpack.scripts.OnLeave(backpack)
timer.call()
assert(BagsBar.alpha == .8, "moving through a gap between bag buttons hid the bar")
BagsBar.scripts.OnEnter(BagsBar)
BagsBar.over = false
combat = true
BagsBar.scripts.OnLeave(BagsBar)
timer.call()
assert(BagsBar.alpha == 0, "leaving the bar in combat did not hide it")
combat = false
assert(S.Set("bags", "inventoryView", 2))
assert(BagsBar.shown and BagsBar.alpha == 0 and BagsBar.motion, "switching layouts forgot the mouseover preference")
assert(S.Set("bags", "bagBarVisibility", mode.ALWAYS))
assert(BagsBar.shown and BagsBar.alpha == .8 and not BagsBar.motion, "always-visible failed to restore the native bar")
assert(S.Set("bags", "bagBarVisibility", mode.IN_COMBAT))
assert(not BagsBar.shown and BagsBar.driver == "[petbattle] hide; [nocombat] hide; show",
    "in-combat mode did not install its secure driver")
assert(S.SetMany("bags", { bagBarVisibility = mode.OUT_OF_COMBAT, bagBarHideMounted = true, bagBarHideNoTarget = true }))
assert(BagsBar.driver == "[petbattle] hide; [combat] hide; [mounted] hide; [@target,noexists] hide; show",
    "unit-frame conditions were not combined with the chosen mode")
assert(S.catalog.bags.rules.bagBarVisibility.section == "bagBar" and S.catalog.dataTexts.rules.hideBlizzardBagBar.hidden,
    "the new Bags section did not take over from the legacy DataTexts control")
mounted = true
BagsBar:Show()
assert(not BagsBar.shown, "native reopen ignored a hide condition")
mounted = false
S.editMode = true
S.Apply("bags")
assert(BagsBar.shown and not BagsBar.driver, "editing did not restore the bag bar for placement")
S.editMode = nil
S.Apply("bags")
if flavor == "Forever" then
    assert(deviceHooks.MainActionBar_InitializeGamepad == 1 and deviceHooks.MainActionBar_InitializeMKB == 1)
    MainActionBar_InitializeGamepad()
else
    gamepad = true
    BagsBar:Hide()
    S.Apply("bags")
end
assert(not BagsBar.shown and not BagsBar.driver, "keyboard visibility overrode the Gamepad layout")
if flavor == "Forever" then
    MainActionBar_InitializeMKB()
else
    gamepad = false
    BagsBar:Show()
end
assert(BagsBar.driver, "switching back to keyboard did not reapply the driver")
assert(S.Set("bags", "bagBarVisibility", mode.NEVER))
combat = true
S.Config("bags").enabled = false
S.Apply("bags")
assert(not BagsBar.shown, "combat bypassed pending bag-bar restoration")
combat = false
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_REGEN_ENABLED then frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED") end
end
assert(BagsBar.shown and not BagsBar.driver and not S.OwnsBlizzardSurface("bagBar"), "disabling Bags did not release the HUD")
S.Config("bags").enabled = true
S.Apply("bags")
available.bags = false
S.Apply("bags")
assert(BagsBar.shown and not BagsBar.driver, "unavailable replacement returns native bags")
print("Bags native bar lifecycle contract passed: " .. flavor)
