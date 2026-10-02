-- Settings notifications arrive once per slider tick or colour-picker move.
-- The listeners whose work is a full pass (the Micro Bar skin, the character
-- stats fonts) and the public appearance signal (MSUF menus and Suite HUD
-- modules repaint on it) run once per frame, after that frame's writes.
-- Real Registry, Safety, MicroMenuStates.lua, MicroMenu.lua and
-- CharacterStats.lua; the public signal is covered in
-- suite_skin_absorption_contract.lua.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

securecallfunction = function(callback, ...) return callback(...) end
local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function NextFrame()
    local pending = timers
    timers = {}
    for _, callback in ipairs(pending) do callback() end
end

local function Frame(name, parent)
    local frame = { name = name, parent = parent }
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:GetObjectType() return "Frame" end
    function frame:IsForbidden() return false end
    function frame:IsProtected() return false, false end
    return setmetatable(frame, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return Noop end
    end })
end
CreateFrame = function() return Frame() end

local locked = false
local deferred = {}
local passes = 0
local NS = {
    Client = { isForever = false },
    IsCombatLocked = function() return locked end,
    MicroMenuLoadConditions = {},
    DB = { icons = { microMenu = { iconStyle = "blizzard", tint = "native", layoutMode = "blizzard",
        buttonBackground = false, buttonBorder = 0, barBackground = false, barBorder = 0 } } },
    CombatGate = { RunOrDefer = function(key, callback)
        if locked then
            deferred[key] = callback
            return false, "combat"
        end
        callback()
        return true
    end },
    MicroMenuVisual = { Prepare = function() return true end, Apply = function() return true end,
        Restore = function() return true end },
    OwnedMicroBar = {
        Apply = function(root) return root, "blizzard" end,
        GetFrames = function() return nil end,
        TrackHoverButtons = function() passes = passes + 1 end,
        Disable = function() return true end,
        HoverEnter = Noop, HoverLeave = Noop,
    },
    Surface = { Attach = function() return {} end, SetVisible = function() return true end },
}
for _, file in ipairs({ "Core/Safety.lua", "Core/Registry.lua", "Adapters/AdapterKit.lua",
    "Adapters/MicroMenuStates.lua", "Adapters/MicroMenu.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
local Registry = NS.Registry

-- The Micro Bar skin: one full pass per frame of colour writes.
local menu = Frame("MicroMenu")
local button = Frame("CharacterMicroButton", menu)
function button:GetObjectType() return "Button" end
for _, method in ipairs({ "SetPushed", "SetNormal", "OnEnable", "OnDisable", "HookScript" }) do
    button[method] = Noop
end
function hooksecurefunc() end
MicroMenu, MicroMenuContainer, CharacterMicroButton = menu, Frame("MicroMenuContainer"), button
assert(NS.MicroMenuSkin.Apply(menu, "micro"))
passes = 0
for step = 1, 12 do Registry.NotifyListeners("color", "microIcon" .. (step % 3)) end
Registry.NotifyListeners("appearance", "shellOpacity")
Check(passes == 0, "a colour write re-skinned the Micro Bar at once")
NextFrame()
Check(passes == 1, "a frame of colour writes re-skinned the Micro Bar " .. passes .. " times")
Registry.NotifyListeners("category", "group")
NextFrame()
Check(passes == 1, "an unrelated notification re-skinned the Micro Bar")
-- A pass queued just before combat waits for its end, then runs once.
Registry.NotifyListeners("theme", "look")
locked = true
NextFrame()
Check(passes == 1, "the Micro Bar was re-skinned in combat")
locked = false
for key, callback in pairs(deferred) do
    deferred[key] = nil
    callback()
end
Check(passes == 2, "the pass queued before combat did not run once after it")

-- The character stats fonts: one repaint per frame.
NS.CharacterDetails = { IsModern = function() return true end }
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/CharacterStats.lua"))("MSUF_Suite_Skin", NS)
local paints = 0
NS.CharacterStats.RefreshFonts = function() paints = paints + 1 end
for _ = 1, 10 do Registry.NotifyListeners("color", "muted") end
Check(paints == 0, "a colour write repainted the character stats at once")
NextFrame()
Check(paints == 1, "a frame of colour writes repainted the character stats " .. paints .. " times")

-- Blizzard's gold text: one pass over every catalogued font object per
-- frame of colour writes. Budget: 8 writes in one frame, one pass, i.e.
-- one SetTextColor per font object (was one pass per write: 8 per object).
local nativeWrites = 0
local function FontObject()
    local object = { color = { 1, 0.82, 0, 1 } }
    function object:GetObjectType() return "Font" end
    function object:GetTextColor() return unpack(self.color) end
    function object:SetTextColor(r, g, b, a)
        nativeWrites = nativeWrites + 1
        self.color = { r, g, b, a or 1 }
    end
    return object
end
local FONTS = 20
NS.BlizzardFontNames = {}
for index = 1, FONTS do
    local name = "ContractGameFont" .. index
    _G[name] = FontObject()
    NS.BlizzardFontNames[index] = name
end
local yellow = { 0.9, 0.7, 0.2, 1 }
NS.DB.enabled = true
NS.Theme = { GetColor = function() return yellow[1], yellow[2], yellow[3], yellow[4] end }
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/BlizzardYellow.lua"))("MSUF_Suite_Skin", NS)
NS.BlizzardYellow.Apply()
nativeWrites = 0
for step = 1, 8 do
    yellow[2] = 0.6 + step * 0.01
    Registry.NotifyListeners("color", "blizzardYellow")
end
Check(nativeWrites == 0, "a colour write recoloured Blizzard's gold text at once")
NextFrame()
Check(nativeWrites == FONTS, ("a frame of colour writes made %d native colour writes for %d fonts")
    :format(nativeWrites, FONTS))

print("Suite skin notification coalescing: " .. checks .. " checks passed")
