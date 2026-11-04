local _, P = ...
local Bridge = P.Suite.HostBridge
local Gameplay = { registered = false }
P.GameplayPage = Gameplay

-- These features stay in the Suite catalogue and profile. Only their menu
-- destination changes when the host supports appending to its Gameplay page.
local MODULES = {
    "actionTracker", "selfCombatText", "combatStatsHUD", "targetDistance", "threatMeter",
    "burningRushCue", "combatMovementCue", "combatPetStatus", "cursorEffects",
    "battleRes", "groupBloodlust", "groupDeathAlert", "innervateCue", "enemyCastStack",
}
local owned = {}
for _, id in ipairs(MODULES) do owned[id] = true end

function Gameplay.Relocated(id)
    return Gameplay.registered and owned[id] == true
end

local function Build(ctx, builder)
    P.M.TrackRefresh(ctx, P.ForgetAvailability)
    P.QoLView.BuildGameplay(ctx, builder)
end

local function CanReset()
    for _, id in ipairs(MODULES) do
        if P.Available(id) then return true end
    end
    return false
end

local function Reset()
    for _, id in ipairs(MODULES) do
        if not P.S.Reset(id) then return false end
    end
    return true
end

-- Old search history and favourites retain their stable Suite section IDs.
-- Copy the target so opening a saved link never changes the saved record.
function Gameplay.Resolve(page, target)
    if not Gameplay.registered or not target then return end
    local id = (target.settingKey or ""):match("^msufsuite%.([^.]+)%.")
        or (target.sectionId or ""):match("^suite_qualityOfLife_([^_]+)_")
    local category = (target.sectionId or ""):match("^suite_qualityOfLife_category_(.+)$")
    if not owned[id] and category ~= "combatAlerts" and category ~= "gameplay" then return end
    local copy = {}
    for key, value in pairs(target) do copy[key] = value end
    copy.pageKey = "gameplay"
    if category then copy.sectionId = "suite_qualityOfLife_category_gameplay" end
    if type(copy.controlId) == "string" then
        copy.controlId = copy.controlId:gsub("^menu2%.suite%.quality%.of%.life%.", "menu2.gameplay.")
    end
    return "gameplay", copy, {}
end

local provider = {
    build = Build,
    canReset = CanReset,
    warning = function()
        return P.Tr("This also resets the Suite combat helpers shown on Gameplay for the active profile.")
    end,
    prepare = function() return not P.Combat() end,
    reset = Reset,
    finish = function() P.Refresh() end,
}
function Gameplay.Register()
    -- Registration may immediately rebuild a visible Gameplay page. All
    -- painters must have loaded and know their destination before that call.
    Gameplay.registered = true
    Gameplay.registered = Bridge.RegisterPageExtension(P.M, "gameplay", "MSUF_Suite.Gameplay", provider)
    if Gameplay.registered then
        Bridge.RegisterSearchTargetResolver(P.M, "MSUF_Suite.Gameplay", Gameplay.Resolve)
    end
end
