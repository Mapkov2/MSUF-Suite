local _, Suite = ...
local DB = Suite.Database

-- Compare the saved base, then recheck after lifting a profile variant. Each
-- unchanged factory group updates independently of personal minimap edits.
local GROUPS = {
    { old = { size = 256, point = 3, x = -8, y = -8 },
      new = { size = 240, x = -16, y = -16 } },
    { plate = true, old = { borderSize = 2, borderColor = "000000", outerBorderSize = 2, outerBorderGap = 4,
        outerBorderColor = "000000", borderAlpha = 100, borderClassColor = false, shadowSize = 0,
        styleBackdrop = false, styleTexture = 1, styleBackdropPadding = 4 },
      new = { borderAlpha = 100, styleBackdrop = true, styleBackdropColor = "16191b",
        styleBackdropAlpha = 100, styleBackdropPadding = 6 } },
    { old = { infoLocationSource = 1, infoLocationZone = true, infoLocationSubzone = false },
      new = { infoLocationSource = 4 } },
    { old = { dungeonButton = true, dungeonStyle = 1, dungeonWidth = 52, dungeonHeight = 26,
        dungeonAnchor = 1, dungeonX = 0, dungeonY = -12 },
      new = { dungeonStyle = 2, dungeonWidth = 48, dungeonX = 8, dungeonY = -16 } },
}

-- Earlier installers retained the dormant plate from the native dark preset.
-- Only those two known factory pairs qualify; mixed or personal values do not.
local function OriginalPlate(c)
    return c.styleBackdropColor == "090c14" and c.styleBackdropAlpha == 85
        or c.styleBackdropColor == "101010" and c.styleBackdropAlpha == 82
end

local function Changes(profile)
    local c = profile and profile.suite and profile.suite.modules.minimap
    if not c then return end
    local result, found = {}, false
    for _, group in ipairs(GROUPS) do
        local same = not group.plate or OriginalPlate(c)
        for key, value in pairs(group.old) do
            local stored = c[key]
            if stored == nil and (key == "infoLocationSource" or key == "dungeonStyle") then stored = 1 end
            -- Earlier Modern Dark installs also inherited the old 95% ring.
            if key == "borderAlpha" and stored == 95 then stored = 100 end
            if stored ~= value then
                same = false
                break
            end
        end
        if same then
            for key, value in pairs(group.new) do result[key], found = value, true end
        end
    end
    return found and result or nil
end

function Suite.SuiteProfiles.EnsureModernDarkMinimap()
    local receipt = Suite.RootDB and Suite.RootDB.installation
    local name = DB.GetActiveProfileName()
    if Suite.InCombat() or not receipt or receipt.status ~= "complete"
        or receipt.profile ~= "modernDark" or receipt.frameProfileName ~= name
        or receipt.modernDarkMinimapRevision == 1 then return false end
    local base = Suite.ProfileVariants.BaseProfile(name)
    if not base then return false end
    if not Changes(base) then
        receipt.modernDarkMinimapRevision = 1
        return false
    end
    if not Suite.ProfileVariants.BeforeMutation(name) then return false end
    local changes = Changes(DB.GetProfile(name))
    local ok = changes and Suite.Suite.SetMany("minimap", changes) == true or false
    Suite.ProfileVariants.AfterMutation(name)
    if ok or not changes then receipt.modernDarkMinimapRevision = 1 end
    return ok
end
