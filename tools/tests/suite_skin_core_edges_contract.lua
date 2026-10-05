-- Edges of the skin core, each with the real files:
--   * NS.Clamp turns NaN into the minimum, so an imported profile that carries
--     NaN for a range or a colour channel comes out of SanitizeProfile clamped.
--   * Registry.NotifyListeners calls every listener of its start exactly once,
--     also when a listener adds others meanwhile (WatchSettings does), and
--     skips one removed meanwhile.
--   * A texture an adapter bound to a colour role (Checkmarks.TrackTexture,
--     e.g. the QuickJoin social button) follows a look, colour or profile change.
-- Real Defaults, DefaultsLooks, Database, Safety, Registry, CombatGate, Theme,
-- Checkmarks and CheckmarksMenus.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, label)
    assert(value, label)
    checks = checks + 1
end

local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
InCombatLockdown = function() return false end
local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function NextFrame()
    local queued = timers
    timers = {}
    for _, callback in ipairs(queued) do callback() end
end
CreateFrame = function()
    return { SetScript = function() end, RegisterEvent = function() end, UnregisterEvent = function() end }
end
EventRegistry = { RegisterCallback = function() end, UnregisterCallback = function() end }
UnitClass = function() return "Mage", "MAGE" end
C_ClassColor = { GetClassColor = function() return nil end }
RAID_CLASS_COLORS = {}
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local NS = {
    IsCombatLocked = function() return InCombatLockdown() end,
    Client = { isForever = false, isMainline = true },
    FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" },
    GenericWindows = { Disable = function() end, ApplyFrame = function() end },
    WindowActionSkin = { Restore = function() end, HasOwnedStates = function() return false end,
        DisableOwner = function() end },
}
for _, file in ipairs({ "Core/Defaults.lua", "Core/DefaultsLooks.lua", "Core/Database.lua", "Core/Safety.lua",
    "Core/Registry.lua", "Core/CombatGate.lua", "Core/Theme.lua", "Core/Checkmarks.lua",
    "Core/CheckmarksMenus.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end

------------------------------------------------------------------ Clamp and NaN
local nan = 0 / 0
Check(NS.Clamp(nan, 0, 1) == 0 and NS.Clamp(nan, 0.35, 1) == 0.35, "NS.Clamp passed NaN through")
Check(NS.Clamp(-1, 0, 1) == 0 and NS.Clamp(2, 0, 1) == 1 and NS.Clamp(0.5, 0, 1) == 0.5
    and NS.Clamp("x", 0, 1) == 0 and NS.Clamp(nil, 0.2, 1) == 0.2, "NS.Clamp changed for ordinary values")
-- An import payload (C_EncodingUtil.DeserializeCBOR keeps a NaN float).
local imported = NS.CopyValue(NS.Defaults)
imported.theme.gradientStrength = nan
imported.theme.shellOpacity = nan
imported.theme.colors.text = { nan, 0.5, 0.5, nan }
local profile = NS.Database.SanitizeProfile(imported)
local theme = profile and profile.theme
Check(theme and theme.gradientStrength == 0 and theme.shellOpacity == 0.35,
    "an imported NaN range survived SanitizeProfile")
Check(theme.colors.text[1] == 0 and theme.colors.text[2] == 0.5 and theme.colors.text[4] == 0,
    "an imported NaN colour channel survived SanitizeProfile")

------------------------------------------------------------------ listeners
-- Inserting keys into the weak listener table while pairs() walks it can
-- rehash the table: next() then skips or repeats owners (Lua 5.1 leaves the
-- traversal undefined). Every size from 1 to 48 listeners, a first listener
-- that adds eight more.
local Registry = NS.Registry
local saved = Registry.listeners
for size = 1, 48 do
    Registry.listeners = setmetatable({}, { __mode = "k" })
    local calls, owners, added = {}, {}, {}
    local function Count(owner) calls[owner] = (calls[owner] or 0) + 1 end
    local function AddMore(owner)
        Count(owner)
        if #added == 0 then
            for index = 1, 8 do
                added[index] = {}
                Registry.AddListener(added[index], Count)
            end
        end
    end
    for index = 1, size do
        owners[index] = {}
        Registry.AddListener(owners[index], AddMore)
    end
    Registry.NotifyListeners("profile", "activate")
    for index = 1, size do
        Check(calls[owners[index]] == 1, size .. " listeners: one was called "
            .. tostring(calls[owners[index]] or 0) .. " times while another added listeners")
    end
end
-- A listener removed by an earlier one in the same pass is not called.
Registry.listeners = setmetatable({}, { __mode = "k" })
local first, second, passCalls = {}, {}, 0
-- Whichever runs first removes the other one.
local function RemoveOther(owner)
    passCalls = passCalls + 1
    Registry.RemoveListener(owner == first and second or first)
end
Registry.AddListener(first, RemoveOther)
Registry.AddListener(second, RemoveOther)
Registry.NotifyListeners("profile", "activate")
Check(passCalls == 1, "a listener removed during the pass was still called")
Registry.listeners = saved

------------------------------------------------------------------ bound roles
NS.DB = NS.Database.Normalize(NS.CopyValue(NS.Defaults))
-- QuickJoinToastButton.FriendsButton (live Blizzard_QuickJoin/QuickJoinToast.xml):
-- an atlas the global allowlist does not know, native white vertex colour.
local friends = { vertex = { 1, 1, 1, 1 }, desaturated = false }
function friends:GetVertexColor() return unpack(self.vertex) end
function friends:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a or 1 } end
function friends:SetDesaturated(value) self.desaturated = value end
function friends:IsDesaturated() return self.desaturated end
function friends:GetAtlas() return "quickjoin-button-friendslist-up" end
function friends:GetTexture() return 4615818 end
function friends:IsForbidden() return false end
local function Paints(role)
    local r, g, b = NS.Theme.GetColor(role)
    local vertex = friends.vertex
    return math.abs(vertex[1] - r) < 1e-6 and math.abs(vertex[2] - g) < 1e-6 and math.abs(vertex[3] - b) < 1e-6
end
-- UIPanelButtons.lua SkinQuickJoin binds it like this.
Check(NS.Checkmarks.TrackTexture(friends, "uipanel-buttons", "blizzardExpand") and Paints("blizzardExpand"),
    "the bound texture was not painted")
local before = { unpack(friends.vertex) }
Check(NS.Theme.ApplyLook("midnight"), "the look did not change")
NextFrame()
local _, beforeGreen = unpack(before)
Check(Paints("blizzardExpand") and friends.vertex[2] ~= beforeGreen,
    "a look change left the bound texture in the previous look's colour")
Check(NS.Theme.SetColor("blizzardExpand", 0.9, 0.1, 0.1, 1), "the colour did not change")
NextFrame()
Check(Paints("blizzardExpand"), "a colour change left the bound texture in its previous colour")
-- Releasing it restores Blizzard's colour; the theme pass no longer paints it.
Check(NS.Checkmarks.UntrackTexture(friends, "uipanel-buttons") and friends.vertex[1] == 1
    and friends.vertex[2] == 1 and friends.vertex[3] == 1, "untracking did not restore the native colour")
Check(NS.Theme.ApplyLook("cleanModern"), "the look did not change back")
NextFrame()
Check(friends.vertex[1] == 1 and friends.vertex[2] == 1 and friends.vertex[3] == 1,
    "the theme pass painted a released texture")
Check(#reported == 0, "the skin core reported errors: " .. table.concat(reported, "; "))

print("Suite skin core edges: " .. checks .. " checks passed")
