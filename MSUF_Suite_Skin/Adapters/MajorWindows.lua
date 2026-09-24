local _, NS = ...

-- Purpose-built clean-room skins for visually unique Blizzard windows
-- which cannot be completed by the conservative catalog traversal alone.
-- Exact fields were verified against Gethe/wow-ui-source upstream/ptr at
-- a1f5e990cb945b0586a26789fa56bdc6c5331e89:
--
--   Blizzard_ProfessionsBook/Blizzard_ProfessionsBook.xml
--   Blizzard_HousingDashboard/*.xml and *.lua
--   Blizzard_PVPUI/Mainline/Blizzard_PVPUI.xml and *.lua
--   Blizzard_GroupFinder/Mainline/{PVEFrame,LFDFrame,LFGList}.xml
--   Blizzard_WeeklyRewards/{Blizzard_WeeklyRewards.xml,.lua}
--   Blizzard_ItemSocketingUI/Blizzard_ItemSocketingUI.xml
--   Blizzard_ItemInteractionUI/Blizzard_ItemInteractionUI.xml
--   Blizzard_ItemUpgradeUI/Mainline/Blizzard_ItemUpgradeUI.xml
--
-- The item-service fields are unchanged between upstream/live
-- 027d26c3406d3de2cbd2b1f67d468fe033a1bcd4 and upstream/ptr
-- e9e8bf68cb7b4177566532f8da9373590759587d.
--
-- Only explicitly named cosmetic regions and addon-owned surfaces are
-- changed. Blizzard scripts, anchors, data providers, secure profession
-- buttons, semantic icons, rewards and progress fills stay untouched.
local MajorWindows = {
    owners = {},
    waiting = {},
    indicators = setmetatable({}, { __mode = "k" }),
    activeOwnerCount = 0,
    housingCallbacksRegistered = false,
    housingRewardEventFrame = nil,
}
NS.MajorWindows = MajorWindows

local DEFAULT_OWNER = "blizzardWindows"

local groups = {
    {
        id = "profession-book",
        category = "profession",
        addon = "Blizzard_ProfessionsBook",
        root = "ProfessionsBookFrame",
    },
    {
        id = "housing-dashboard",
        category = "housing",
        addon = "Blizzard_HousingDashboard",
        root = "HousingDashboardFrame",
    },
    {
        id = "pvp",
        category = "group",
        addon = "Blizzard_PVPUI",
        root = "PVPUIFrame",
    },
    {
        id = "group-finder",
        category = "group",
        addon = "Blizzard_GroupFinder",
        root = "PVEFrame",
    },
    {
        id = "great-vault",
        category = "expansion",
        addon = "Blizzard_WeeklyRewards",
        root = "WeeklyRewardsFrame",
    },
    {
        id = "item-socketing",
        category = "item-service",
        addon = "Blizzard_ItemSocketingUI",
        root = "ItemSocketingFrame",
    },
    {
        id = "item-interaction",
        category = "item-service",
        addon = "Blizzard_ItemInteractionUI",
        root = "ItemInteractionFrame",
    },
    {
        id = "item-upgrade",
        category = "item-service",
        addon = "Blizzard_ItemUpgradeUI",
        root = "ItemUpgradeFrame",
    },
}

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function Path(object, ...)
    for index = 1, select("#", ...) do
        object = SafeField(object, select(index, ...))
        if not object then return nil end
    end
    return object
end

local function IsLoaded(addon)
    if type(addon) ~= "string" or addon == "" then return true end
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loadedOrLoading, loaded = pcall(C_AddOns.IsAddOnLoaded, addon)
        if not ok then return false end
        return loaded == true or (loaded == nil and loadedOrLoading == true)
    end
    if type(IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(IsAddOnLoaded, addon)
        return ok and loaded == true
    end
    return false
end

local function CategoryEnabled(category)
    return not NS.GenericWindows
        or type(NS.GenericWindows.IsCategoryEnabled) ~= "function"
        or NS.GenericWindows.IsCategoryEnabled(category)
end

local function OwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = MajorWindows.owners[owner]
    if not state then
        state = {
            owner = owner,
            active = false,
            surfaces = WeakSet(),
            textColors = setmetatable({}, { __mode = "k" }),
            textRoles = setmetatable({}, { __mode = "k" }),
            installedTextColors = setmetatable({}, { __mode = "k" }),
            housingPoolsPrepared = setmetatable({}, { __mode = "k" }),
        }
        MajorWindows.owners[owner] = state
    end
    return state, owner
end

local function Report(label, message)
    if type(NS.ReportError) == "function" then
        NS.ReportError("major windows " .. tostring(label), message)
    end
end

local function TrackSurface(state, target)
    if state and target then state.surfaces[target] = true end
end

local function Fade(state, region)
    if not region or NS.IsCombatLocked() or not NS.Cosmetics
        or type(NS.Cosmetics.Fade) ~= "function" or not NS.Safety
        or not NS.Safety.CanDecorate(region, true) then
        return false
    end
    local ok, result = pcall(NS.Cosmetics.Fade, region, state.owner)
    if not ok then Report("fade", result) end
    return ok and result == true
end

local function FadeFields(state, target, fields)
    for index = 1, #(fields or {}) do
        Fade(state, SafeField(target, fields[index]))
    end
end

local function FadeNineSlice(state, target)
    local nineSlice = SafeField(target, "NineSlice")
    if not nineSlice or NS.IsCombatLocked() or not NS.Safety
        or not NS.Safety.CanDecorate(nineSlice, true) or not NS.Cosmetics
        or type(NS.Cosmetics.FadeNineSlice) ~= "function" then
        return
    end
    local ok, message = pcall(NS.Cosmetics.FadeNineSlice, nineSlice, state.owner)
    if not ok then Report("nine slice", message) end
end

local function DirectRegions(frame)
    if not frame or type(SafeField(frame, "GetRegions")) ~= "function" then return {} end
    local ok, regions = pcall(function() return { frame:GetRegions() } end)
    return ok and regions or {}
end

local function FadeDirectTextures(state, frame, exceptions)
    exceptions = exceptions or {}
    local regions = DirectRegions(frame)
    local surface = NS.Registry and NS.Registry.GetSurface(frame) or nil
    for index = 1, #regions do
        local region = regions[index]
        local owned = surface and (region == surface.fill or region == surface.edge
            or region == surface.depth or region == surface.highlight
            or region == surface.pushed or region == surface.disabled)
        local objectType
        if region and type(SafeField(region, "GetObjectType")) == "function" then
            local ok, value = pcall(region.GetObjectType, region)
            objectType = ok and value or nil
        end
        if objectType == "Texture" and not owned and not exceptions[region] then
            Fade(state, region)
        end
    end
end

local function Attach(state, target, role, radius, inset, listItem, forceEdge, fillVisible)
    if not target or NS.IsCombatLocked() or not NS.Surface or not NS.Safety
        or not NS.Safety.CanDecorate(target, true) then
        return false
    end
    local ok, surface = pcall(NS.Surface.Attach, target, {
        role = role or "panel",
        radius = radius or (role == "popup" and 8 or 6),
        inset = inset or 0,
        listItem = listItem == true,
        forceEdge = forceEdge == true,
        fillVisible = fillVisible ~= false,
        allowImplicitProtected = true,
    })
    if ok and surface then
        TrackSurface(state, target)
        return true
    end
    if not ok then Report("surface", surface) end
    return false
end

local function SkinControl(state, target, spec)
    if not target or NS.IsCombatLocked() or not NS.ControlSkin or not NS.Safety
        or not NS.Safety.CanControl(target, true) then
        return false
    end
    spec = spec or {}
    spec.allowImplicitProtected = true
    spec.useControlShape = spec.useControlShape ~= false
    local ok, applied = pcall(NS.ControlSkin.ApplyButton, target, state.owner, spec)
    if ok and applied then
        TrackSurface(state, target)
        return true
    end
    if not ok then Report("control", applied) end
    return false
end

local function ReadTextColor(fontObject)
    local getter = SafeField(fontObject, "GetTextColor")
    if type(getter) ~= "function" then return nil end
    local ok, r, g, b, a = pcall(getter, fontObject)
    if not ok or type(r) ~= "number" then return nil end
    return { r, g, b, tonumber(a) or 1 }
end

local function SameColor(left, right)
    return left and right
        and left[1] == right[1] and left[2] == right[2]
        and left[3] == right[3] and left[4] == right[4]
end

local function SetThemeText(state, fontObject, role)
    if not fontObject or type(SafeField(fontObject, "SetTextColor")) ~= "function" then return end
    if not state.textColors[fontObject] then
        state.textColors[fontObject] = ReadTextColor(fontObject)
    end
    state.textRoles[fontObject] = role
    local installed = { NS.Theme.GetColor(role) }
    state.installedTextColors[fontObject] = installed
    fontObject:SetTextColor(installed[1], installed[2], installed[3], installed[4])
end

local function RefreshTextColors(state)
    for fontObject, role in pairs(state.textRoles) do
        if type(SafeField(fontObject, "SetTextColor")) == "function" then
            local installed = { NS.Theme.GetColor(role) }
            state.installedTextColors[fontObject] = installed
            fontObject:SetTextColor(installed[1], installed[2], installed[3], installed[4])
        end
    end
end

local function RestoreTextColors(state)
    for fontObject, original in pairs(state.textColors) do
        local current = ReadTextColor(fontObject)
        local installed = state.installedTextColors[fontObject]
        if original and installed and SameColor(current, installed)
            and type(SafeField(fontObject, "SetTextColor")) == "function" then
            fontObject:SetTextColor(original[1], original[2], original[3], original[4])
        end
    end
    state.textColors = setmetatable({}, { __mode = "k" })
    state.textRoles = setmetatable({}, { __mode = "k" })
    state.installedTextColors = setmetatable({}, { __mode = "k" })
end

local function ApplyGeneric(root, owner, mode)
    if not NS.GenericWindows or type(NS.GenericWindows.ApplyFrame) ~= "function" then
        return false, "generic-missing"
    end
    local ok, applied, reason = pcall(NS.GenericWindows.ApplyFrame, root, owner, mode)
    if not ok then
        Report("generic", applied)
        return false, "failed"
    end
    return applied, reason
end

local function SkinProfessionCard(state, card)
    if not card then return end
    Attach(state, card, "card", 6, 1)
    for _, key in ipairs({ "SpellButton1", "SpellButton2" }) do
        local button = SafeField(card, key)
        local getName = SafeField(button, "GetName")
        if type(getName) == "function" then
            local ok, name = pcall(getName, button)
            if ok and type(name) == "string" and name ~= "" then
                local nameFrame = _G[name .. "NameFrame"]
                local getParent = SafeField(nameFrame, "GetParent")
                if type(getParent) == "function" then
                    local parentOK, parent = pcall(getParent, nameFrame)
                    if parentOK and parent == button then Fade(state, nameFrame) end
                end
            end
        end
    end
    SetThemeText(state, SafeField(card, "professionName"), "title")
    SetThemeText(state, SafeField(card, "specialization"), "accentAlt")
    SetThemeText(state, SafeField(card, "missingHeader"), "title")
    SetThemeText(state, SafeField(card, "missingText"), "text")
    SetThemeText(state, SafeField(card, "rank"), "muted")
end

local function SkinProfessionBook(root, state)
    local applied, reason = ApplyGeneric(root, state.owner, {
        role = "shell", maxDepth = 6, maxNodes = 260,
        childSurfaces = false,
        allowImplicitProtected = true,
    })
    if not applied then return false, reason end

    Fade(state, _G.ProfessionsBookPage1)
    Fade(state, _G.ProfessionsBookPage2)
    -- ProfessionsContentFrame exactly covers the book shell. Keeping a second
    -- material fill here makes Glass nearly opaque; retain only its edge.
    Attach(state, _G.ProfessionsContentFrame, "panel", 6, 0, false, false, false)
    for _, name in ipairs({
        "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1",
        "SecondaryProfession2", "SecondaryProfession3",
    }) do
        SkinProfessionCard(state, _G[name])
    end
    return true, "applied"
end

local function SkinHousingReward(state, reward)
    if not reward then return end
    Attach(state, reward, "card", 6, 1, true)
    Fade(state, SafeField(reward, "Background"))
    Fade(state, SafeField(reward, "Divider"))
end

local function GetHousingUpgrade(root)
    return Path(root, "HouseInfoContent", "ContentFrame", "HouseUpgradeFrame")
end

local function HousingRewardsLoaded(upgrade)
    local checker = SafeField(upgrade, "AllRewardsLoaded")
    if type(checker) == "function" then
        local ok, loaded = pcall(checker, upgrade)
        if ok then return loaded == true end
    end
    local infos = SafeField(upgrade, "houseLevelRewardInfos")
    if type(infos) ~= "table" or #infos == 0 then return false end
    for index = 1, #infos do
        local info = infos[index]
        if type(info) == "table" and not info.isMax and type(info.rewards) ~= "table" then
            return false
        end
    end
    return true
end

local function SkinAndReserveHousingPool(state, pool, required)
    if not pool or required <= 0 then return end
    local activeCount = 0
    local enumerate = SafeField(pool, "EnumerateActive")
    if type(enumerate) == "function" then
        pcall(function()
            for reward in enumerate(pool) do
                activeCount = activeCount + 1
                SkinHousingReward(state, reward)
            end
        end)
    end

    local acquire = SafeField(pool, "Acquire")
    local release = SafeField(pool, "Release")
    if type(acquire) ~= "function" or type(release) ~= "function" then return end
    local acquired = {}
    for _ = activeCount + 1, required do
        local ok, reward = pcall(acquire, pool)
        if not ok or not reward then break end
        acquired[#acquired + 1] = reward
        SkinHousingReward(state, reward)
    end
    for index = #acquired, 1, -1 do
        pcall(release, pool, acquired[index])
    end
end

local function PrepareHousingRewardPools(root, state)
    local upgrade = GetHousingUpgrade(root)
    if not upgrade or state.housingPoolsPrepared[upgrade] then return false end
    if not HousingRewardsLoaded(upgrade) then return false end

    local maximumLarge, maximumSmall = 0, 0
    local infos = SafeField(upgrade, "houseLevelRewardInfos")
    for index = 1, #(infos or {}) do
        local rewards = type(infos[index]) == "table" and infos[index].rewards or nil
        local count = type(rewards) == "table" and #rewards or 0
        if count > 0 and count <= 4 then
            maximumLarge = math.max(maximumLarge, count)
        elseif count > 4 then
            maximumSmall = math.max(maximumSmall, count)
        end
    end

    -- Prewarm exactly the largest data-driven layout in each Blizzard pool.
    -- Every later level selection therefore reuses an already skinned frame;
    -- no hook, polling loop or per-click addon callback is necessary.
    SkinAndReserveHousingPool(state, SafeField(upgrade, "rewardPoolLarge"), maximumLarge)
    SkinAndReserveHousingPool(state, SafeField(upgrade, "rewardPoolSmall"), maximumSmall)
    state.housingPoolsPrepared[upgrade] = true
    return true
end

local function SkinHousingRewards(root, state)
    local rewards = Path(root, "HouseInfoContent", "ContentFrame", "HouseUpgradeFrame", "RewardsFrame")
    if not rewards then return end
    Attach(state, rewards, "panel", 6, 0)

    local getter = SafeField(rewards, "GetLayoutChildren")
    if type(getter) ~= "function" then getter = SafeField(rewards, "GetChildren") end
    if type(getter) ~= "function" then return end
    pcall(function()
        local values = { getter(rewards) }
        if #values == 1 and type(values[1]) == "table"
            and type(SafeField(values[1], "GetObjectType")) ~= "function" then
            for index = 1, #values[1] do
                SkinHousingReward(state, values[1][index])
            end
        else
            for index = 1, #values do
                SkinHousingReward(state, values[index])
            end
        end
    end)
    PrepareHousingRewardPools(root, state)
end

local function SkinHousingInitiatives(root, state)
    local initiatives = Path(root, "HouseInfoContent", "ContentFrame", "InitiativesFrame")
    if not initiatives then return end
    Attach(state, initiatives, "panel", 6, 0)

    local art = SafeField(initiatives, "InitiativesArt")
    Fade(state, SafeField(art, "InitiativesBG"))
    FadeDirectTextures(state, SafeField(art, "BorderArt"))

    local setFrame = SafeField(initiatives, "InitiativeSetFrame")
    local tasks = SafeField(setFrame, "InitiativeTasks")
    local activity = SafeField(setFrame, "InitiativeActivity")
    Attach(state, tasks, "card", 6, 0)
    Attach(state, activity, "card", 6, 0)
    FadeFields(state, tasks, { "BG", "BorderTop", "BorderRight", "TitleCornerTR" })
    FadeFields(state, activity, { "BG", "BGTexture", "BorderTop", "TitleCornerTR" })
end

local function SkinHousingContent(root, state)
    local houseInfo = SafeField(root, "HouseInfoContent")
    local noHouse = SafeField(houseInfo, "DashboardNoHousesFrame")
    local content = SafeField(houseInfo, "ContentFrame")
    local upgrade = SafeField(content, "HouseUpgradeFrame")

    Attach(state, houseInfo, "panel", 6, 0)
    Attach(state, noHouse, "panel", 6, 0)
    Fade(state, SafeField(noHouse, "Background"))
    Attach(state, content, "panel", 6, 0)
    Attach(state, upgrade, "panel", 6, 0)
    -- Every direct texture on HousingUpgradeFrame is verified decorative:
    -- the full Elwynn background, four filigree corners and header divider.
    -- The level medallion, progress fill and reward icons are child frames.
    FadeDirectTextures(state, upgrade)
    Attach(state, SafeField(upgrade, "TrackFrame"), "card", 6, 0)
    Fade(state, Path(upgrade, "TrackFrame", "Background"))

    local catalog = SafeField(root, "CatalogContent")
    Attach(state, catalog, "panel", 6, 0)
    Fade(state, SafeField(catalog, "Background"))
    for _, key in ipairs({ "Filters", "Categories", "OptionsContainer", "PreviewFrame" }) do
        Attach(state, SafeField(catalog, key), "card", 6, 0)
    end
    Fade(state, SafeField(catalog, "Divider"))

    local collection = SafeField(root, "CollectionContent")
    Attach(state, collection, "panel", 6, 0)
    Fade(state, SafeField(collection, "Background"))
    for _, key in ipairs({ "Categories", "BlueprintCollection", "BlueprintDetails" }) do
        Attach(state, SafeField(collection, key), "card", 6, 0)
    end
    Fade(state, SafeField(collection, "Divider"))
    Fade(state, Path(collection, "BlueprintDetails", "PreviewBackground"))

    SkinHousingInitiatives(root, state)
    SkinHousingRewards(root, state)
end

local function SkinHousingDashboard(root, state)
    local applied, reason = ApplyGeneric(root, state.owner, {
        role = "shell", maxDepth = 9, maxNodes = 1000,
        allowImplicitProtected = true,
    })
    if not applied then return false, reason end
    SkinHousingContent(root, state)
    return true, "applied"
end

local function ConfigureIndicator(indicator, button, panel)
    if type(SafeField(indicator, "SetParent")) == "function" then indicator:SetParent(panel) end
    if type(SafeField(indicator, "ClearAllPoints")) == "function" then indicator:ClearAllPoints() end
    if type(SafeField(indicator, "SetAllPoints")) == "function" then indicator:SetAllPoints(button) end
    if type(SafeField(indicator, "EnableMouse")) == "function" then indicator:EnableMouse(false) end
    if type(SafeField(indicator, "Show")) == "function" then indicator:Show() end
end

local function SkinPVPIndicator(state, button, panel)
    if not button or not panel or type(CreateFrame) ~= "function" or not NS.Safety
        or not NS.Safety.CanDecorate(panel, true) then
        return
    end
    local indicator = MajorWindows.indicators[button]
    if not indicator then
        local ok, created = pcall(CreateFrame, "Frame", nil, panel)
        if not ok or not created then return end
        indicator = created
        MajorWindows.indicators[button] = indicator
    end
    ConfigureIndicator(indicator, button, panel)
    -- Selection lives above Blizzard's button so its visibility can follow
    -- the selected content panel. Keep its center transparent: the themed
    -- edge remains readable without covering the button's icon or label.
    Attach(state, indicator, "navigationActive", 8, 2, true, true)
end

local function SkinPVPStatus(state, statusBar)
    if not statusBar then return end
    Attach(state, statusBar, "status", 4, 1)
    FadeFields(state, statusBar, { "Background", "Border" })
end

local function SkinPVPActivity(state, button)
    SkinControl(state, button, {
        role = "card", activeRole = "navigationActive", radius = 6,
        inset = 1, pillHeight = 54, listItem = true,
        regions = { "NormalTexture", "Bg" },
    })
end

local function SkinPVPPopup(state, popup)
    if not popup then return end
    Attach(state, popup, "popup", 8, 0)
    FadeFields(state, popup, {
        "Background", "BottomLeftCorner", "BottomRightCorner",
        "TopLeftCorner", "TopRightCorner", "BottomBorder", "TopBorder",
        "LeftBorder", "RightBorder", "LeftHide", "LeftHide2",
        "RightHide", "RightHide2", "BottomHide", "BottomHide2",
        "TopLeftFiligree", "TopRightFiligree",
    })
end

local function SkinPVPContent(root, state)
    local queue = _G.PVPQueueFrame or SafeField(root, "PVPQueueFrame")
    if not queue then return end

    local panels = {
        _G.HonorFrame or SafeField(queue, "HonorFrame"),
        _G.ConquestFrame or SafeField(queue, "ConquestFrame"),
        _G.LFGListPVPStub or SafeField(queue, "LFGListPVPStub"),
        _G.TrainingGroundsFrame or SafeField(queue, "TrainingGroundsFrame"),
        _G.PlunderstormFrame or SafeField(queue, "PlunderstormFrame"),
    }
    for index = 1, 5 do
        local button = SafeField(queue, "CategoryButton" .. index)
        local panel = panels[index]
        SkinControl(state, button, {
            role = "navigation", radius = 8, inset = 2, pillHeight = 60,
            regions = { "Background", "Ring" },
        })
        SkinPVPIndicator(state, button, panel)
    end

    -- These are visibility/controller frames, not visual panels. In Blizzard's
    -- PvP layout their content uses the same frame level as the controller, so
    -- a late full-frame surface can composite above and hide the Rated queue
    -- rows. Skin the concrete Insets/cards below instead.

    local honor = panels[1]
    local conquest = panels[2]
    local training = panels[4]
    local plunder = panels[5]

    for _, panel in ipairs({ honor, conquest, training }) do
        local inset = SafeField(panel, "Inset")
        Attach(state, inset, "card", 6, 0)
        FadeNineSlice(state, inset)
        Fade(state, SafeField(inset, "Bg"))
        SkinPVPStatus(state, SafeField(panel, "ConquestBar"))
    end

    local bonus = SafeField(honor, "BonusFrame")
    Attach(state, bonus, "panel", 6, 0)
    Fade(state, SafeField(bonus, "WorldBattlesTexture"))
    for _, key in ipairs({
        "RandomBGButton", "RandomEpicBGButton", "Arena1Button",
        "BrawlButton", "BrawlButton2",
    }) do
        SkinPVPActivity(state, SafeField(bonus, key))
    end

    Fade(state, SafeField(conquest, "RatedBGTexture"))
    for _, key in ipairs({
        "RatedSoloShuffle", "RatedBGBlitz", "Arena2v2", "Arena3v3", "RatedBG",
    }) do
        SkinPVPActivity(state, SafeField(conquest, key))
    end

    local trainingBonus = SafeField(training, "BonusTrainingGroundList")
    Attach(state, trainingBonus, "panel", 6, 0)
    Fade(state, SafeField(trainingBonus, "WorldBattlesTexture"))
    SkinPVPActivity(state, SafeField(trainingBonus, "RandomTrainingGroundButton"))
    SkinPVPActivity(state, SafeField(trainingBonus, "RandomTrainingGroundArenaButton"))

    Fade(state, SafeField(plunder, "Background"))
    local plunderInset = SafeField(plunder, "Inset")
    Attach(state, plunderInset, "card", 6, 0)
    FadeNineSlice(state, plunderInset)
    Fade(state, SafeField(plunderInset, "Bg"))

    local honorInset = SafeField(queue, "HonorInset")
    Attach(state, honorInset, "card", 6, 0)
    FadeNineSlice(state, honorInset)
    Fade(state, SafeField(honorInset, "Bg"))
    Fade(state, SafeField(honorInset, "Background"))

    SkinPVPPopup(state, SafeField(queue, "NewSeasonPopup"))
    local prestige = SafeField(queue, "PrestigeLevelDialog")
    if prestige then
        Attach(state, prestige, "popup", 8, 0)
        FadeNineSlice(state, prestige)
    end
end

local function SkinPVP(root, state)
    local applied, reason = ApplyGeneric(root, state.owner, {
        role = "panel", maxDepth = 9, maxNodes = 1000,
        allowImplicitProtected = true,
    })
    if not applied then return false, reason end
    SkinPVPContent(root, state)
    return true, "applied"
end

local function SkinGroupFinderPanel(state, panel)
    if not panel then return end
    Attach(state, panel, "panel", 6, 0)
    FadeFields(state, panel, {
        "Background", "Bg", "TopTileStreaks", "RoleBackground",
        "InfoBackground", "CustomBG",
    })
    local inset = SafeField(panel, "Inset")
    if inset then
        Attach(state, inset, "card", 6, 0)
        FadeNineSlice(state, inset)
        FadeFields(state, inset, { "Background", "Bg" })
    end
end

local function SkinGroupFinder(root, state)
    local applied, reason = ApplyGeneric(root, state.owner, {
        role = "shell", maxDepth = 10, maxNodes = 1200,
        registerDynamicRows = true, allowImplicitProtected = true,
    })
    if not applied then return false, reason end

    -- PVEFrame.xml keeps the blue rail and most gold dividers as named global
    -- textures rather than parentKey fields. They are exact window chrome;
    -- the category icons and labels remain untouched.
    for _, name in ipairs({
        "PVEFrameBlueBg", "PVEFrameTLCorner", "PVEFrameTRCorner",
        "PVEFrameBRCorner", "PVEFrameBLCorner", "PVEFrameLLVert",
        "PVEFrameRLVert", "PVEFrameBottomLine", "PVEFrameTopLine",
        "PVEFrameTopFiligree", "PVEFrameBottomFiligree",
    }) do
        Fade(state, _G[name])
    end

    -- Blizzard raises this exact chrome-only frame above the navigation rail.
    -- Fading its parent removes the anonymous gold divider regardless of rect
    -- state or region order; PVEFrame_ShowLeftInset only toggles Show/Hide.
    Fade(state, SafeField(root, "shadows"))

    local navigation = _G.GroupFinderFrame
    if navigation then
        for index = 1, 4 do
            local button = SafeField(navigation, "groupButton" .. index)
                or _G["GroupFinderFrameGroupButton" .. index]
            if button then
                SkinControl(state, button, {
                    role = "navigation", activeRole = "navigationActive",
                    radius = 6, inset = 2, pillHeight = 64,
                    regions = { "bg", "ring" },
                })
            end
        end
    end

    for _, name in ipairs({
        "LFDParentFrame", "RaidFinderFrame", "LFGListFrame", "ChallengesFrame",
    }) do
        SkinGroupFinderPanel(state, _G[name])
    end

    local list = _G.LFGListFrame
    if list then
        for _, key in ipairs({
            "CategorySelection", "SearchPanel", "ApplicationViewer", "EntryCreation",
        }) do
            SkinGroupFinderPanel(state, SafeField(list, key))
        end
    end
    return true, "applied"
end

local function SkinGreatVault(root, state)
    local applied, reason = ApplyGeneric(root, state.owner, {
        role = "shell", maxDepth = 10, maxNodes = 1200,
        allowImplicitProtected = true,
    })
    if not applied then return false, reason end

    FadeFields(state, root, {
        "Background", "BorderShadow", "Divider1", "Divider2",
    })
    local border = SafeField(root, "BorderContainer")
    FadeFields(state, border, { "Border", "TopDecor" })
    FadeFields(state, SafeField(root, "HeaderFrame"), { "HeaderDivider" })

    for _, key in ipairs({ "RaidFrame", "MythicFrame", "PVPFrame", "WorldFrame" }) do
        local typeFrame = SafeField(root, key)
        if typeFrame then
            Attach(state, typeFrame, "panel", 6, 0)
            FadeFields(state, typeFrame, { "Background", "Border" })
        end
    end

    -- WeeklyRewardsMixin creates every selectable activity during OnLoad and
    -- exposes the stable list as Activities. Preserve completion icons,
    -- reward effects and item icons; replace only each card's base chrome.
    local activities = SafeField(root, "Activities")
    if type(activities) == "table" then
        for index = 1, #activities do
            local activity = activities[index]
            if activity then
                Attach(state, activity, "card", 6, 1, true)
                FadeFields(state, activity, { "Background", "Border" })
            end
        end
    end

    SkinControl(state, SafeField(root, "SelectRewardButton"), {
        role = "button", activeRole = "buttonPrimary",
        radius = 5, inset = 1, pillHeight = 24,
        regions = { "Left", "Middle", "Right", "Background" },
    })

    local warning = _G.WeeklyRewardExpirationWarningDialog
    if warning then
        Attach(state, warning, "popup", 8, 0)
        FadeNineSlice(state, warning)
        FadeFields(state, warning, { "ExtraBG" })
    end
    return true, "applied"
end

local function SkinExactItemServiceShell(root, state)
    Attach(state, root, "shell", 8, 0)
    FadeNineSlice(state, root)
    FadeFields(state, root, { "Bg", "TopTileStreaks", "Portrait", "portrait" })
    Fade(state, Path(root, "PortraitContainer", "portrait"))
    Fade(state, Path(root, "PortraitContainer", "Portrait"))
end

local function SkinItemSocketing(root, state)
    SkinExactItemServiceShell(root, state)

    -- These exact fields are the parchment, gold frame, shadow and rivet
    -- layers around Blizzard's socket data. The socket Background, Icon,
    -- brackets, Shine and interaction textures remain native and visible.
    FadeFields(state, root, {
        "ParchmentFrame-Top", "ParchmentFrame-Bottom",
        "ParchmentFrame-Left", "ParchmentFrame-Right",
        "SocketFrame-Left", "SocketFrame-Right",
        "ButtonFrame-Left", "ButtonFrame-Right", "ButtonBorder-Mid",
        "GoldBorder-BottomRight", "GoldBorder-BottomLeft",
        "GoldBorder-TopRight", "GoldBorder-TopLeft",
        "GoldBorder-Left", "GoldBorder-Right",
        "GoldBorder-Top", "GoldBorder-Bottom",
        "BackgroundColor", "BackgroundHighlight",
        "BorderShadow-TopLeftCorner", "BorderShadow-TopRightCorner",
        "BorderShadow-BottomLeftCorner", "BorderShadow-BottomRightCorner",
        "BorderShadow-Top", "BorderShadow-Left",
        "BorderShadow-Bottom", "BorderShadow-Right",
        "BottomLeftNub", "BottomRightNub",
        "MiddleLeftNub", "MiddleRightNub",
        "TopLeftNub", "TopRightNub",
    })

    local description = _G.ItemSocketingDescription
    Attach(state, description, "panel", 6, 0)
    FadeNineSlice(state, description)

    local container = SafeField(root, "SocketingContainer")
    local sockets = SafeField(container, "SocketFrames")
    if type(sockets) == "table" then
        for index = 1, #sockets do
            local socket = sockets[index]
            if socket then
                Attach(state, socket, "card", 5, 0, true)
                FadeFields(state, socket, { "LeftFiligree", "RightFiligree" })
            end
        end
    end
    SkinControl(state, SafeField(container, "ApplySocketsButton"), {
        role = "button", activeRole = "buttonPrimary",
        radius = 5, inset = 1, pillHeight = 24,
    })
    return true, "applied"
end

local function SkinItemInteraction(root, state)
    SkinExactItemServiceShell(root, state)

    -- Background is the Blizzard-selected interaction texture kit. Keep it,
    -- along with conversion borders and celebration layers, as native state.
    local footer = SafeField(root, "ButtonFrame")
    Attach(state, footer, "navigation", 5, 0)
    FadeFields(state, footer, {
        "BlackBorder", "ButtonBorder", "ButtonBottomBorder",
    })
    FadeDirectTextures(state, SafeField(footer, "MoneyFrameEdge"))
    SkinControl(state, SafeField(footer, "ActionButton"), {
        role = "button", activeRole = "buttonPrimary",
        radius = 5, inset = 1, pillHeight = 24,
    })

    -- The slot surface is cosmetic only. Icon/GlowOverlay and all conversion
    -- input/output borders, arrows, flashes and texture-kit states stay native.
    Attach(state, SafeField(root, "ItemSlot"), "card", 5, 1, true)
    return true, "applied"
end

local function SkinItemUpgrade(root, state)
    SkinExactItemServiceShell(root, state)

    -- Suppress only the static panel ornament. BottomPanel_Flash, Ring,
    -- tooltip glow pieces, arrows and button glow remain Blizzard-owned so the
    -- complete upgrade-success and interaction feedback is preserved.
    FadeFields(state, root, {
        "BottomBG", "BottomBGShadow", "TopBG", "IdleGlow", "MicaFleckSheen",
    })

    local itemButton = SafeField(root, "UpgradeItemButton")
    Attach(state, itemButton, "card", 5, 1, true)
    -- ButtonFrame is static slot ornament. IconBorder remains native because
    -- SetItemButtonQuality updates it whenever the selected item/target quality
    -- changes; no addon lifecycle hook is needed to preserve that state.
    Fade(state, SafeField(itemButton, "ButtonFrame"))

    for _, key in ipairs({
        "LeftItemPreviewFrame", "RightItemPreviewFrame", "ItemHoverPreviewFrame",
    }) do
        local preview = SafeField(root, key)
        Attach(state, preview, key == "ItemHoverPreviewFrame" and "popup" or "card", 6, 0)
        -- ItemUpgradePreviewTemplate also owns GlowNineSlice; fading only the
        -- inherited NineSlice keeps that success effect intact.
        FadeNineSlice(state, preview)
    end

    local cost = SafeField(root, "UpgradeCostFrame")
    Attach(state, cost, "card", 5, 0)
    Fade(state, SafeField(cost, "BGTex"))
    FadeDirectTextures(state, SafeField(root, "PlayerCurrenciesBorder"))
    SkinControl(state, SafeField(root, "UpgradeButton"), {
        role = "button", activeRole = "buttonPrimary",
        radius = 5, inset = 1, pillHeight = 24,
    })
    SkinControl(state, Path(root, "ItemInfo", "Dropdown"), {
        role = "button", radius = 5, inset = 1, pillHeight = 24,
        regions = { "Background" },
    })
    return true, "applied"
end

local groupSkinners = {
    ["profession-book"] = SkinProfessionBook,
    ["housing-dashboard"] = SkinHousingDashboard,
    pvp = SkinPVP,
    ["group-finder"] = SkinGroupFinder,
    ["great-vault"] = SkinGreatVault,
    ["item-socketing"] = SkinItemSocketing,
    ["item-interaction"] = SkinItemInteraction,
    ["item-upgrade"] = SkinItemUpgrade,
}

local function ApplyGroup(spec, state)
    if not state or not state.active then return false, "disabled" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not CategoryEnabled(spec.category) then return true, "disabled" end
    local root = _G[spec.root]
    if not root then return false, IsLoaded(spec.addon) and "missing" or "waiting" end
    local skinner = groupSkinners[spec.id]
    if type(skinner) ~= "function" then return false, "missing" end
    return skinner(root, state)
end

local function ApplyGroupForOwners(spec)
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("major-windows:load:" .. spec.id, function()
            ApplyGroupForOwners(spec)
        end)
        return
    end
    for _, state in pairs(MajorWindows.owners) do
        if state.active then
            local ok, message = pcall(ApplyGroup, spec, state)
            if not ok then Report(spec.id, message) end
        end
    end
end

local function RefreshHousingRewards()
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("major-windows:housing-rewards", RefreshHousingRewards)
        return
    end
    local root = _G.HousingDashboardFrame
    if not root then return end
    for _, state in pairs(MajorWindows.owners) do
        if state.active and CategoryEnabled("housing") then
            SkinHousingRewards(root, state)
        end
    end
end

local function StopHousingRewardEvent()
    local frame = MajorWindows.housingRewardEventFrame
    if frame and type(SafeField(frame, "UnregisterEvent")) == "function" then
        pcall(frame.UnregisterEvent, frame, "RECEIVED_HOUSE_LEVEL_REWARDS")
    end
end

local function EnsureHousingRewardEvent()
    local root = _G.HousingDashboardFrame
    local upgrade = root and GetHousingUpgrade(root)
    if not upgrade or HousingRewardsLoaded(upgrade) or type(CreateFrame) ~= "function" then
        return
    end
    local frame = MajorWindows.housingRewardEventFrame
    if not frame then
        local ok, created = pcall(CreateFrame, "Frame")
        if not ok or not created then return end
        frame = created
        MajorWindows.housingRewardEventFrame = frame
        frame:SetScript("OnEvent", function()
            local currentRoot = _G.HousingDashboardFrame
            local currentUpgrade = currentRoot and GetHousingUpgrade(currentRoot)
            if currentUpgrade and HousingRewardsLoaded(currentUpgrade) then
                StopHousingRewardEvent()
                RefreshHousingRewards()
            end
        end)
    end
    frame:RegisterEvent("RECEIVED_HOUSE_LEVEL_REWARDS")
end

local function Schedule(spec)
    if MajorWindows.waiting[spec.id] then return true end
    if IsLoaded(spec.addon) or not EventUtil
        or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then
        return false
    end
    MajorWindows.waiting[spec.id] = true
    local ok, message = pcall(EventUtil.ContinueOnAddOnLoaded, spec.addon, function()
        MajorWindows.waiting[spec.id] = nil
        ApplyGroupForOwners(spec)
        if spec.id == "housing-dashboard" then MajorWindows.RegisterHousingCallbacks() end
    end)
    if not ok then
        MajorWindows.waiting[spec.id] = nil
        Report("load " .. spec.id, message)
        return false
    end
    return true
end

local function OnHousingUpgradeShown()
    RefreshHousingRewards()
    EnsureHousingRewardEvent()
end

function MajorWindows.RegisterHousingCallbacks()
    if MajorWindows.housingCallbacksRegistered or not _G.HousingDashboardFrame
        or not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then
        return false
    end
    local ok, message = pcall(EventRegistry.RegisterCallback, EventRegistry,
        "HousingUpgradeFrame.Shown", OnHousingUpgradeShown, MajorWindows)
    if not ok then
        Report("housing callback", message)
        return false
    end
    MajorWindows.housingCallbacksRegistered = true
    EnsureHousingRewardEvent()
    return true
end

local function UnregisterHousingCallbacks()
    if not MajorWindows.housingCallbacksRegistered then return end
    if EventRegistry and type(EventRegistry.UnregisterCallback) == "function" then
        pcall(EventRegistry.UnregisterCallback, EventRegistry,
            "HousingUpgradeFrame.Shown", MajorWindows)
    end
    MajorWindows.housingCallbacksRegistered = false
    StopHousingRewardEvent()
end

function MajorWindows.OnThemeChanged(_, domain)
    if domain ~= "theme" and domain ~= "profile" and domain ~= "color" then return end
    if NS.IsCombatLocked() then return end
    for _, state in pairs(MajorWindows.owners) do
        if state.active then RefreshTextColors(state) end
    end
end

function MajorWindows.Apply(owner)
    local state
    state, owner = OwnerState(owner)
    if not state.active then
        state.active = true
        MajorWindows.activeOwnerCount = MajorWindows.activeOwnerCount + 1
    end
    if NS.IsCombatLocked() then return false, "combat" end

    local applied, waiting, failed = 0, 0, 0
    for index = 1, #groups do
        local spec = groups[index]
        if CategoryEnabled(spec.category) then
            local ok, reason = ApplyGroup(spec, state)
            if ok then
                applied = applied + 1
            elseif reason == "waiting" and Schedule(spec) then
                waiting = waiting + 1
            else
                failed = failed + 1
            end
        end
    end
    MajorWindows.RegisterHousingCallbacks()
    NS.Registry.AddListener(MajorWindows, MajorWindows.OnThemeChanged)

    if failed > 0 and applied == 0 and waiting == 0 then return false, "missing" end
    if failed > 0 then return true, "partial" end
    if waiting > 0 and applied == 0 then return true, "waiting" end
    return true, waiting > 0 and "partial" or "applied"
end

function MajorWindows.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = MajorWindows.owners[owner]
    if not state then return true end
    if NS.IsCombatLocked() then return false, "combat" end
    state.active = false
    for target in pairs(state.surfaces) do
        pcall(NS.Surface.SetVisible, target, false)
    end
    for _, indicator in pairs(MajorWindows.indicators) do
        if type(SafeField(indicator, "Hide")) == "function" then indicator:Hide() end
    end
    RestoreTextColors(state)
    MajorWindows.owners[owner] = nil
    MajorWindows.activeOwnerCount = math.max(0, MajorWindows.activeOwnerCount - 1)
    if MajorWindows.activeOwnerCount == 0 then
        UnregisterHousingCallbacks()
        NS.Registry.RemoveListener(MajorWindows)
        NS.CombatGate.Cancel("major-windows:housing-rewards")
        for index = 1, #groups do
            NS.CombatGate.Cancel("major-windows:load:" .. groups[index].id)
        end
    end
    -- GenericWindows owns shared ControlSkin/Cosmetics restoration and runs
    -- after this module in the blizzardWindows adapter teardown.
    return true
end

function MajorWindows.GetIndicator(button)
    return MajorWindows.indicators[button]
end

function MajorWindows.GetWaitingCount()
    local count = 0
    for _ in pairs(MajorWindows.waiting) do count = count + 1 end
    return count
end

return MajorWindows
