local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Masque skins for cooldown icons ("Skin icons with Masque", per bar): one
-- Masque group per bar, holding that bar's icons. Only our own cooldown icons
-- qualify. Buff icons are Blizzard's sealed aura buttons (never reskinned or
-- scripted after they are built) and timer bars are not icons, so both keep
-- their look. Masque draws the border, backdrop and gloss and places the icon
-- art (Icons.lua leaves those to it while icon.masqued); the swipes, texts
-- and glows stay ours. Without Masque nothing here runs: the bar is a plain
-- one and no group exists.
local Masque = {}
C.Masque = Masque
local KIND = C.Const.KIND
local regions = setmetatable({}, { __mode = "k" }) -- icon -> the regions handed to Masque

-- The Masque library, or nil while Masque is not loaded.
local function Library()
    local stub = rawget(_G, "LibStub")
    if type(stub) ~= "table" then return nil end
    local lib = stub:GetLibrary("Masque", true)
    return type(lib) == "table" and lib or nil
end

-- Whether Masque skins this bar's icons: switched on for a bar of cooldown
-- icons, with Masque loaded.
function Masque.Active(view)
    return view.masque == true and view.kind == KIND.COOLDOWN and not view.cooldownDuration and Library() ~= nil
end

local function Add(pool, icon)
    local set = regions[icon]
    if not set then
        set = { Icon = icon.tex, Cooldown = icon.cd }
        regions[icon] = set
    end
    pool.group:AddButton(icon, set, "Item", true)
    icon.masqued = true
end
function Masque.Remove(pool, icon)
    icon.masqued = nil
    -- The next style pass places the art and the border again.
    icon.styleGen = nil
    if pool.group then pool.group:RemoveButton(icon) end
end

-- A sync of a bar's icons: opens or closes its group and holds every icon of
-- the pool in it. The icons that join later are added as they are made
-- (Masque.Join); the ones that leave are removed as they are recycled.
function Masque.Update(slot, pool, view)
    local active = Masque.Active(view)
    local group = pool.group
    if active and not group then
        group = Library():Group("MSUF Suite", view.title, slot)
        pool.group = group
    end
    if not group then return end
    local changed = false
    for _, icon in pairs(pool.byKey) do
        if active and not icon.masqued then
            Add(pool, icon)
            changed = true
        elseif not active and icon.masqued then
            Masque.Remove(pool, icon)
        end
    end
    for i = 1, #pool.free do
        if pool.free[i].masqued then Masque.Remove(pool, pool.free[i]) end
    end
    if not active then
        group:Delete()
        pool.group = nil
    elseif changed then
        group:ReSkin()
    end
end
-- A new or reused icon of a bar whose icons are skinned.
function Masque.Join(pool, icon)
    if not icon.masqued then Add(pool, icon) end
end
