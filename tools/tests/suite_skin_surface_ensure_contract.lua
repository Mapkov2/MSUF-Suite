-- Hooks that run per row initialization or per native update (Auction House
-- rows while scrolling, damage meter rows, paper doll slot and stats
-- updates) attach through Surface.Ensure: a surface that already shows its
-- spec, visible and painted for the current generation, costs no paint.
-- Surface.Attach keeps repainting fully. Real Defaults, Theme, Safety,
-- Registry, Geometry, Surface, AdapterKit, Commerce, DamageMeter and
-- PaperDollChrome.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

securecallfunction = function(callback, ...) return callback(...) end
InCombatLockdown = function() return false end
Enum = { UITextureSliceMode = { Stretched = 1 } }
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
C_Timer = { After = function(_, callback) callback() end }

local paints = 0
local function Texture()
    local texture = { shown = true }
    for _, method in ipairs({ "SetTexture", "SetVertexColor", "SetGradient", "ClearTextureSlice",
        "SetTextureSliceMargins", "SetTextureSliceMode" }) do
        texture[method] = function() paints = paints + 1 end
    end
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    function texture:ClearAllPoints() end
    function texture:SetPoint() end
    function texture:SetDrawLayer() end
    return texture
end
local function Target(objectType)
    local target = {}
    function target:IsForbidden() return false end
    function target:IsProtected() return false, false end
    function target:GetObjectType() return objectType or "Frame" end
    function target:GetParent() return nil end
    function target:CreateTexture() return Texture() end
    function target:HookScript() end
    return target
end

local NS = {
    path = "",
    Client = { isForever = false },
    IsCombatLocked = function() return false end,
    BlizzardYellow = { TrackFrame = Noop },
}
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", NS)
NS.DB = NS.CopyValue(NS.Defaults)
for _, file in ipairs({ "Core/Safety.lua", "Core/Registry.lua", "Core/Theme.lua",
    "Rendering/Geometry.lua", "Rendering/Surface.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
local Surface = NS.Surface
local spec = { role = "card", radius = 4, inset = 1, listItem = true }

local row = Target()
Check(Surface.Ensure(row, spec) ~= nil and paints > 0, "the first Ensure did not paint the row")
paints = 0
for _ = 1, 100 do Surface.Ensure(row, spec) end
Check(paints == 0, ("a current row surface was painted again %d times by row initialization"):format(paints))
-- A settings change makes the next Ensure paint once.
NS.Registry.NotifyListeners("color", "accent")
Surface.Ensure(row, spec)
Check(paints > 0, "a row kept its old paint after a settings change")
paints = 0
Surface.Ensure(row, spec)
Check(paints == 0, "a repainted row was painted again")
-- A hidden surface is shown and painted again.
Surface.SetVisible(row, false)
paints = 0
Surface.Ensure(row, spec)
Check(paints > 0 and NS.Registry.GetSurface(row).visible == true, "Ensure left a hidden surface hidden")
-- Another spec paints; Attach always paints (callers that rewrite a spec
-- table in place rely on it).
paints = 0
Surface.Ensure(row, { role = "panel", radius = 4, inset = 1, listItem = true })
Check(paints > 0, "a new spec was not painted")
local current = NS.Registry.GetSurface(row).spec
paints = 0
current.inset = 2
Surface.Attach(row, current)
Check(paints > 0, "Attach skipped the repaint of a spec rewritten in place")
-- A tab that mirrors Blizzard's selection is painted every time.
local tab = Target("Button")
Surface.Ensure(tab, spec)
Surface.SetNativeStateSync(tab, true)
paints = 0
Surface.Ensure(tab, spec)
Check(paints > 0, "a surface that mirrors native selection skipped its repaint")

------------------------------------------------------------------ hot callers
-- Each hot path attaches through Ensure.
local ensures, attaches = 0, 0
NS.Surface = {
    Ensure = function() ensures = ensures + 1; return {} end,
    Attach = function() attaches = attaches + 1; return {} end,
    SetVisible = Noop,
}
NS.Cosmetics = { Fade = function() return true end, SuppressVertexAlpha = function() return true end }
NS.ControlSkin = { DisableOwner = Noop }
NS.IconSkin = { Apply = function() return {} end }
NS.GenericWindows = { IsCategoryEnabled = function() return true end }
NS.DB.skinCategories = { economy = true, social = false }
NS.DB.hud = { damageMeterRows = true }
ScrollBoxListMixin = { Event = { OnInitializedFrame = "OnInitializedFrame" } }
for _, file in ipairs({ "Adapters/AdapterKit.lua", "Adapters/Commerce.lua", "Adapters/DamageMeter.lua",
    "Adapters/PaperDollChrome.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
-- Auction House rows Blizzard initializes while scrolling.
local callbacks = {}
local scrollBox = Target()
function scrollBox:RegisterCallback(_, callback, owner) callbacks[#callbacks + 1] = { callback, owner } end
function scrollBox:ForEachFrame() end
AuctionHouseFrame = Target()
AuctionHouseFrame.BrowseResultsFrame = { ItemList = { ScrollBox = scrollBox } }
EventUtil = { ContinueOnAddOnLoaded = Noop }
NS.Commerce.Apply("hot")
local auctionRow = Target()
ensures, attaches = 0, 0
for _ = 1, 3 do
    for _, registration in ipairs(callbacks) do registration[1](registration[2], auctionRow) end
end
Check(#callbacks == 1 and ensures == 3 and attaches == 0,
    "Auction House row initialization did not attach through Ensure")
local rowEnsures = ensures
-- Damage meter rows.
local meterRow = Target()
meterRow.StatusBar = Target()
local meterCallbacks = {}
local meterBox = Target()
function meterBox:RegisterCallback(_, callback, owner) meterCallbacks[#meterCallbacks + 1] = { callback, owner } end
function meterBox:ForEachFrame() end
local window = Target()
window.MinimizeContainer = { ScrollBox = meterBox }
function window:SetMinimized() end
local meter = Target()
function meter:ForEachSessionWindow(callback) callback(window) end
NS.WindowActionSkin = { SyncNativeVisual = function() return {} end }
NS.Checkmarks = { TrackButton = Noop }
hooksecurefunc = Noop
NS.DamageMeterSkin.Apply(meter, "meter")
rowEnsures, attaches = ensures, 0
for _ = 1, 3 do meterCallbacks[1][1](meterCallbacks[1][2], meterRow) end
Check(ensures == rowEnsures + 3 and attaches == 0, "damage meter row initialization did not attach through Ensure")
-- Paper doll slot updates.
local chrome = NS.PaperDollChrome.New({ prefix = "hot", slotNames = { "HotSlot" } })
local state = chrome:OwnerState("hot")
state.active = true
local slot = Target()
chrome.exactSlots[slot] = true
local slotEnsures = ensures
for _ = 1, 3 do chrome:SkinSlot(state, slot) end
Check(ensures == slotEnsures + 3, "a paper doll slot update did not attach through Ensure")

print("Suite skin surface ensure: " .. checks .. " checks passed")
