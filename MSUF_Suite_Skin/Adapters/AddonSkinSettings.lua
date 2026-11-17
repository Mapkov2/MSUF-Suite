local _, NS = ...

-- Addons such as OneForAll use Blizzard's generated Settings rows instead of
-- their own canvas. Those rows have Blizzard source locations, so ownership
-- must follow the selected addon category and the row-pool lifecycle.
local SettingsSkin = {}
NS.AddonSettings = SettingsSkin
local Skins, Safety = NS.AddonSkins, NS.Safety
local state = { owner = "addon-skin:native-settings" }
local mode = { rootSurface = false, allowImplicitProtected = false, maxDepth = 4, maxNodes = 96 }

local function Release()
    if state.scrollBox then NS.AdapterKit.UnregisterRowCallback(state.scrollBox, state.event, state) end
    NS.GenericWindows.Disable(state.owner)
    NS.AddonSkinVisuals.Release(state.owner)
    state.scrollBox, state.event, state.id, state.applied = nil, nil, nil, false
end

local function Row(_, row)
    if not state.id or not Skins.IsEnabled(state.id) or NS.IsCombatLocked() then return end
    if NS.GenericWindows.ApplyDescendant(row, state.owner, mode) then
        NS.AddonSkinVisuals.Tree(row, state.owner)
        state.applied = true
    end
end

local function Refresh()
    Release()
    local panel = rawget(_G, "SettingsPanel")
    local category = Safety.Read(panel, "GetCurrentCategory")
    local id = Skins.ResolveApp(Safety.Read(category, "GetName"))
    if not id or not Skins.IsEnabled(id) or Skins.cooperative[id] then return end
    state.id = id
    -- The native Settings adapter already owns these controls when enabled.
    -- Let its skin win; disabling an addon skin never steals that owner.
    if NS.DB.skins.settings ~= false then state.applied = true return end
    local list = Safety.Read(panel, "GetSettingsList")
    local scrollBox = Safety.Field(list, "ScrollBox")
    if not NS.AddonSkinVisuals.Safe(scrollBox) or not Safety.HasMethod(scrollBox, "ForEachFrame") then return end
    state.scrollBox = scrollBox
    state.event = NS.AdapterKit.RegisterRowCallback(scrollBox, Row, state)
    scrollBox:ForEachFrame(function(row) Row(state, row) end)
end

function SettingsSkin.IsApplied(id) return state.id == id and state.applied == true end
function SettingsSkin.ReleaseAddon(id)
    if state.id == id then Release() end
    if not Skins.cooperative[id] then NS.Registry.QueueJob(Refresh) end
end

local function Changed() NS.Registry.QueueJob(Refresh) end
EventRegistry:RegisterCallback("Settings.CategoryChanged", Changed, SettingsSkin)
NS.Registry.AddListener(SettingsSkin, Changed)
Changed()
