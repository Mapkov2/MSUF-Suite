local _, NS = ...

-- Clean-room Objective Tracker skin verified against wow-ui-source
-- upstream/forever bd2470ae and upstream/live 09b9db79. The tracker remains positioned and driven entirely
-- by Blizzard Edit Mode; this adapter only observes four exact visual
-- lifecycle methods and owns colors/textures on cosmetic regions.
local ObjectiveTrackerSkin = {
    owners = {},
    hookedModules = setmetatable({}, { __mode = "k" }),
    hookedBlocks = setmetatable({}, { __mode = "k" }),
    hookedPOIs = setmetatable({}, { __mode = "k" }),
    hookedHeaders = setmetatable({}, { __mode = "k" }),
}
NS.ObjectiveTrackerSkin = ObjectiveTrackerSkin

local DEFER_KEY = "objective-tracker:accent-refresh"
local SURFACE_DEFER_KEY = "objective-tracker:surface-refresh"
local RefreshAllAccents
local RefreshAllSurfaces
local SkinHeaderAccents
local SkinBlockAccents
local SkinPOIButton
local SkinBlockSurface
local SkinModuleSurface
local headerTrimCache = setmetatable({}, { __mode = "k" })
local headerRuleCache = setmetatable({}, { __mode = "k" })

local modules = {
    "ScenarioObjectiveTracker",
    "UIWidgetObjectiveTracker",
    "CampaignQuestObjectiveTracker",
    "QuestObjectiveTracker",
    "AdventureObjectiveTracker",
    "AchievementObjectiveTracker",
    "MonthlyActivitiesObjectiveTracker",
    "InitiativeTasksObjectiveTracker",
    "ProfessionsRecipeTracker",
    "BonusObjectiveTracker",
    "WorldQuestObjectiveTracker",
}

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function OwnerState(owner)
    local state = ObjectiveTrackerSkin.owners[owner]
    if not state then
        state = {
            active = false,
            surfaces = setmetatable({}, { __mode = "k" }),
            moduleSurfaces = setmetatable({}, { __mode = "k" }),
            blockSurfaces = setmetatable({}, { __mode = "k" }),
            headerSurfaces = setmetatable({}, { __mode = "k" }),
            headerTrims = setmetatable({}, { __mode = "k" }),
            headerRules = setmetatable({}, { __mode = "k" }),
        }
        ObjectiveTrackerSkin.owners[owner] = state
    end
    return state
end

local function Getter(object, method)
    local getter = SafeField(object, method)
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter, object)
    return ok and value or nil
end

local function TrackTexture(texture, owner, role)
    if not texture or not NS.Checkmarks
        or type(NS.Checkmarks.TrackTexture) ~= "function" then return false end
    return NS.Checkmarks.TrackTexture(texture, owner, role)
end

local function UntrackTexture(texture, owner)
    if texture and NS.Checkmarks and type(NS.Checkmarks.UntrackTexture) == "function" then
        NS.Checkmarks.UntrackTexture(texture, owner)
    end
end

local function TrackButtonTextures(button, owner, normalRole, pushedRole, hoverRole)
    if not button then return end
    TrackTexture(Getter(button, "GetNormalTexture"), owner, normalRole)
    TrackTexture(Getter(button, "GetPushedTexture"), owner, pushedRole or normalRole)
    TrackTexture(Getter(button, "GetDisabledTexture"), owner, "disabled")
    TrackTexture(Getter(button, "GetHighlightTexture"), owner, hoverRole or normalRole)
end

local function TrackerActionKind(button, collapsed)
    if type(collapsed) == "boolean" then
        return collapsed and "expand" or "collapse"
    end
    local atlas = Getter(Getter(button, "GetNormalTexture"), "GetAtlas")
    if type(atlas) == "string" then
        atlas = atlas:lower()
        if atlas == "ui-questtrackerbutton-expand-all"
            or atlas == "ui-questtrackerbutton-secondary-expand" then
            return "expand"
        end
        if atlas == "ui-questtrackerbutton-collapse-all"
            or atlas == "ui-questtrackerbutton-secondary-collapse" then
            return "collapse"
        end
    end
    if NS.WindowActionSkin and NS.WindowActionSkin.GetKind then
        return NS.WindowActionSkin.GetKind(button)
    end
    return nil
end

local function SkinTrackerAction(button, owner, collapsed)
    if not button then return end
    local kind = TrackerActionKind(button, collapsed)
    if kind and NS.WindowActionSkin then
        local action, reason = NS.WindowActionSkin.SyncNativeVisual(button, owner, kind)
        if action then return end
        if reason == "owned by another adapter"
            or reason == "state texture ownership changed" then return end
    end
    TrackButtonTextures(button, owner,
        "blizzardExpand", "blizzardExpandPressed", "blizzardExpandHover")
end

local function IsGoldPOITexture(texture)
    if not texture then return false end
    local atlas = Getter(texture, "GetAtlas")
    if type(atlas) == "string" then
        atlas = atlas:lower()
        return atlas:find("ui%-questpoi%-", 1, false) == 1
            or atlas == "ui-questicon-turnin-normal"
            or atlas:find("quest%-in%-progress%-icon%-", 1, false) == 1
    end
    for _, method in ipairs({ "GetTextureFilePath", "GetTexture" }) do
        local path = Getter(texture, method)
        if type(path) == "string" then
            path = path:gsub("/", "\\"):lower():gsub("%.blp$", ""):gsub("%.tga$", "")
            if path == "interface\\worldmap\\ui-questpoi-numbericons" then return true end
        end
    end
    return false
end

local function TintPOITexture(texture, owner)
    if IsGoldPOITexture(texture) then
        TrackTexture(texture, owner, "blizzardYellow")
    else
        -- A pooled POI may change from a normal quest to campaign, legendary
        -- or another semantic classification. Never carry our tint across.
        UntrackTexture(texture, owner)
    end
end

local function ForEachPOITexture(poiButton, callback)
    if not poiButton then return end
    callback(SafeField(poiButton, "NormalTexture") or Getter(poiButton, "GetNormalTexture"))
    callback(SafeField(poiButton, "PushedTexture") or Getter(poiButton, "GetPushedTexture"))
    callback(SafeField(poiButton, "HighlightTexture") or Getter(poiButton, "GetHighlightTexture"))
    callback(SafeField(poiButton, "Glow"))
    callback(SafeField(SafeField(poiButton, "Display"), "Icon"))
end

local function DeferAccentRefresh()
    if NS.CombatGate then
        NS.CombatGate.RunOrDefer(DEFER_KEY, RefreshAllAccents)
    end
end

local function ForEachActiveState(callback, object)
    if NS.IsCombatLocked() then
        DeferAccentRefresh()
        return
    end
    for _, state in pairs(ObjectiveTrackerSkin.owners) do
        if state.active and state.accents then callback(state, object) end
    end
end

local function OnModuleLayoutBlock(_, block)
    ForEachActiveState(SkinBlockAccents, block)
    if NS.IsCombatLocked() then
        if NS.CombatGate then
            NS.CombatGate.RunOrDefer(SURFACE_DEFER_KEY, RefreshAllSurfaces)
        end
        return
    end
    for _, state in pairs(ObjectiveTrackerSkin.owners) do
        if state.active and not state.accents then SkinBlockSurface(state, block) end
    end
end

local function OnBlockHighlight(block)
    ForEachActiveState(SkinBlockAccents, block)
end

local function OnPOIStyleChanged(poiButton)
    ForEachActiveState(SkinPOIButton, poiButton)
end

local function OnHeaderCollapsed(header, collapsed)
    if NS.IsCombatLocked() then
        DeferAccentRefresh()
        return
    end
    for _, state in pairs(ObjectiveTrackerSkin.owners) do
        if state.active and state.accents then
            SkinHeaderAccents(state, header, collapsed)
        end
    end
end

local function HookModule(module)
    if not module or ObjectiveTrackerSkin.hookedModules[module]
        or type(hooksecurefunc) ~= "function"
        or type(SafeField(module, "LayoutBlock")) ~= "function" then return false end
    local ok = pcall(function()
        hooksecurefunc(module, "LayoutBlock", OnModuleLayoutBlock)
    end)
    if ok then ObjectiveTrackerSkin.hookedModules[module] = true end
    return ok == true
end

local function HookBlock(block)
    if not block or ObjectiveTrackerSkin.hookedBlocks[block]
        or type(hooksecurefunc) ~= "function"
        or type(SafeField(block, "UpdateHighlight")) ~= "function" then return false end
    local ok = pcall(function()
        hooksecurefunc(block, "UpdateHighlight", OnBlockHighlight)
    end)
    if ok then ObjectiveTrackerSkin.hookedBlocks[block] = true end
    return ok == true
end

local function HookPOI(poiButton)
    if not poiButton or ObjectiveTrackerSkin.hookedPOIs[poiButton]
        or type(hooksecurefunc) ~= "function"
        or type(SafeField(poiButton, "UpdateButtonStyle")) ~= "function" then return false end
    local ok = pcall(function()
        hooksecurefunc(poiButton, "UpdateButtonStyle", OnPOIStyleChanged)
    end)
    if ok then ObjectiveTrackerSkin.hookedPOIs[poiButton] = true end
    return ok == true
end

local function HookHeader(header)
    if not header or ObjectiveTrackerSkin.hookedHeaders[header]
        or type(hooksecurefunc) ~= "function"
        or type(SafeField(header, "SetCollapsed")) ~= "function" then return false end
    local ok = pcall(function()
        hooksecurefunc(header, "SetCollapsed", OnHeaderCollapsed)
    end)
    if ok then ObjectiveTrackerSkin.hookedHeaders[header] = true end
    return ok == true
end

SkinPOIButton = function(state, poiButton)
    if not state or not state.active or not poiButton then return end
    ForEachPOITexture(poiButton, function(texture)
        TintPOITexture(texture, state.owner)
    end)
    HookPOI(poiButton)
end

SkinBlockAccents = function(state, block)
    if not state or not state.active or not block then return end
    -- Blizzard owns semantic campaign/quest colors and hover changes.
    TrackTexture(SafeField(block, "HeaderGlow"), state.owner, "blizzardYellow")
    HookBlock(block)
    SkinPOIButton(state, SafeField(block, "poiButton"))
end

local function EnumerateActiveBlocks(module, callback)
    local usedBlocks = SafeField(module, "usedBlocks")
    if type(usedBlocks) ~= "table" then return end
    pcall(function()
        for _, blocks in pairs(usedBlocks) do
            if type(blocks) == "table" then
                for _, block in pairs(blocks) do callback(block) end
            end
        end
    end)
end

local function SkinModuleAccents(state, module)
    if not module then return end
    SkinHeaderAccents(state, SafeField(module, "Header"))
    HookModule(module)
    EnumerateActiveBlocks(module, function(block)
        SkinBlockAccents(state, block)
    end)
end

local function HeaderSurfaceActive(header)
    for _, state in pairs(ObjectiveTrackerSkin.owners) do
        if state.active and not state.accents and state.headerSurfaces[header] then
            return true
        end
    end
    return false
end

SkinHeaderAccents = function(state, header, collapsed)
    if not state or not state.active or not header then return end
    local background = SafeField(header, "Background")
    if HeaderSurfaceActive(header) then
        -- The optional header surface replaces this native atlas. Keep its
        -- native color available to Cosmetics so either adapter can restore
        -- independently without leaving a stale tint behind.
        UntrackTexture(background, state.owner)
    else
        TrackTexture(background, state.owner, "blizzardYellow")
    end
    -- Keep Blizzard's category color (for example, green Campaign headers).
    TrackTexture(SafeField(header, "Shine"), state.owner, "blizzardYellow")
    TrackTexture(SafeField(header, "Glow"), state.owner, "blizzardYellow")
    SkinTrackerAction(SafeField(header, "MinimizeButton"), state.owner, collapsed)
    TrackButtonTextures(SafeField(header, "FilterButton"), state.owner,
        "blizzardYellow", "blizzardYellow", "blizzardYellow")
    HookHeader(header)
end

local function Track(owner, target)
    local state = ObjectiveTrackerSkin.owners[owner]
    if state and target then state.surfaces[target] = true end
end

local function Attach(target, owner, spec)
    if not target or not NS.Safety.CanDecorate(target, true) then return false end
    spec = spec or {}
    spec.allowImplicitProtected = true
    local surface = NS.Surface.Attach(target, spec)
    if surface then
        Track(owner, target)
        return true
    end
    return false
end

SkinBlockSurface = function(state, block)
    if not state or not state.active or not block then return end
    if SafeField(block, "used") ~= true
        or NS.DB.hud.objectiveTrackerStyle ~= "modern" then
        if state.blockSurfaces[block] then
            NS.Surface.SetVisible(block, false)
            state.blockSurfaces[block] = nil
        end
        return
    end
    -- Modern has a faint wash per item; Forever uses one group card.
    if state.blockSurfaces[block] then return end
    if Attach(block, state.owner, {
        role = "card", radius = 8, border = 0,
        fillAlphaScale = 0.22,
        inset = 0,
    }) then state.blockSurfaces[block] = true end
end

-- Blizzard sizes each module after laying out its blocks. A background on the
-- module itself follows that size automatically and gives each quest group one
-- compact dark card without touching anchors, block text or Edit Mode.
SkinModuleSurface = function(state, module)
    if not state or not state.active or not module then return end
    if not NS.DB.hud.objectiveTrackerBackground
        or NS.DB.hud.objectiveTrackerStyle ~= "forever" then
        if state.moduleSurfaces[module] then
            NS.Surface.SetVisible(module, false)
            state.moduleSurfaces[module] = nil
        end
        return
    end
    if Attach(module, state.owner, {
        role = "card", shape = "continuous", radius = 4,
        border = 0, inset = 0,
    }) then state.moduleSurfaces[module] = true end
end

local function SkinHeader(header, owner, primary)
    if not header then return end
    local hud = NS.DB.hud
    local enabled = primary and hud.objectiveTrackerBackground
        or not primary and hud.objectiveTrackerHeaders
    if enabled then
        NS.Cosmetics.SuppressVertexAlpha(SafeField(header, "Background"), owner)
        local state = OwnerState(owner)
        local modern = hud.objectiveTrackerStyle == "modern"
        local dark = NS.DB.theme.look == "midnightDark"
        if Attach(header, owner, {
            role = primary and "navigation" or "card",
            radius = modern and 8 or 4, border = dark and 1 or 0,
            fillVisible = primary or modern or dark,
            fillAlphaScale = primary and (dark and 0.70 or modern and 0.48 or 0.38)
                or (dark and 0.60 or 0.20),
            inset = 0,
        }) then
            state.headerSurfaces[header] = true
            local trim = headerTrimCache[header]
            if not trim and NS.Safety.CanDecorate(header, true) then
                local ok, texture = pcall(header.CreateTexture, header, nil, "OVERLAY")
                if ok and texture then
                    texture:SetPoint("TOPLEFT", header, "TOPLEFT", 1, -2)
                    texture:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 1, 2)
                    texture:SetWidth(primary and 2 or 1)
                    headerTrimCache[header] = texture
                    trim = texture
                end
            end
            if trim then
                state.headerTrims[header] = trim
                trim:SetWidth(primary and 2 or 1)
                local r, g, b = NS.Theme.GetColor(primary and "accent" or "accentAlt")
                trim:SetColorTexture(r, g, b, primary and 0.78 or 0.55)
                trim:Show()
            end
            if primary then
                local rule = headerRuleCache[header]
                if not rule and NS.Safety.CanDecorate(header, true) then
                    local ok, texture = pcall(header.CreateTexture, header, nil, "OVERLAY")
                    if ok and texture then
                        texture:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 7, 2)
                        texture:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, 2)
                        texture:SetHeight(1)
                        headerRuleCache[header] = texture
                        rule = texture
                    end
                end
                if rule then
                    state.headerRules[header] = rule
                    local r, g, b = NS.Theme.GetColor("accentAlt")
                    rule:SetColorTexture(r, g, b, modern and 0.18 or 0.28)
                    rule:Show()
                end
            end
        end
    end
end


local function SuspendHeaderBackgroundAccents()
    for _, state in pairs(ObjectiveTrackerSkin.owners) do
        if state.active and state.accents then
            UntrackTexture(SafeField(SafeField(state.frame, "Header"), "Background"), state.owner)
            for index = 1, #modules do
                local module = _G[modules[index]]
                UntrackTexture(SafeField(SafeField(module, "Header"), "Background"), state.owner)
            end
        end
    end
end

local function SkinBar(wrapper, owner)
    if not wrapper or not NS.DB.hud.objectiveTrackerBars then return end
    local bar = SafeField(wrapper, "Bar")
    if not bar then return end
    NS.Cosmetics.Fade(SafeField(bar, "BorderLeft"), owner)
    NS.Cosmetics.Fade(SafeField(bar, "BorderRight"), owner)
    NS.Cosmetics.Fade(SafeField(bar, "BorderMid"), owner)
    -- The Blizzard StatusBar fill remains visible and semantic.  MapkoSkin
    -- supplies only the inactive/background plate and its exact border.
    Attach(bar, owner, { role = "input", shape = "continuous", radius = 4, inset = 0 })
end

local function SkinCurrentModuleBars(module, owner)
    for _, field in ipairs({ "usedProgressBars", "usedTimerBars" }) do
        local bars = SafeField(module, field)
        if type(bars) == "table" then
            for _, bar in pairs(bars) do SkinBar(bar, owner) end
        end
    end
end

local function ApplyNow(frame, owner)
    local state = OwnerState(owner)
    state.active = true
    state.accents = false
    state.owner = owner
    state.frame = frame

    if NS.DB.hud.objectiveTrackerHeaders or NS.DB.hud.objectiveTrackerBackground then
        -- Restore the exact Blizzard atlas colors before Cosmetics captures
        -- and hides them for the optional replacement header surfaces.
        SuspendHeaderBackgroundAccents()
    end

    if NS.DB.hud.objectiveTrackerBackground then
        NS.Cosmetics.FadeNineSlice(SafeField(frame, "NineSlice"), owner)
    end
    SkinHeader(SafeField(frame, "Header"), owner, true)

    for index = 1, #modules do
        local module = _G[modules[index]]
        if module then
            SkinModuleSurface(state, module)
            SkinHeader(SafeField(module, "Header"), owner, false)
            HookModule(module)
            EnumerateActiveBlocks(module, function(block)
                SkinBlockSurface(state, block)
            end)
            SkinCurrentModuleBars(module, owner)
        end
    end
    return true
end

RefreshAllSurfaces = function()
    if NS.IsCombatLocked() then return false end
    for _, state in pairs(ObjectiveTrackerSkin.owners) do
        if state.active and not state.accents then
            SkinHeader(SafeField(state.frame, "Header"), state.owner, true)
            for index = 1, #modules do
                local module = _G[modules[index]]
                if module then
                    SkinModuleSurface(state, module)
                    SkinHeader(SafeField(module, "Header"), state.owner, false)
                    EnumerateActiveBlocks(module, function(block)
                        SkinBlockSurface(state, block)
                    end)
                end
            end
        end
    end
    return true
end

RefreshAllAccents = function()
    if NS.IsCombatLocked() then return false end
    for _, state in pairs(ObjectiveTrackerSkin.owners) do
        if state.active and state.accents then
            SkinHeaderAccents(state, SafeField(state.frame, "Header"))
            for index = 1, #modules do
                SkinModuleAccents(state, _G[modules[index]])
            end
        end
    end
    return true
end

function ObjectiveTrackerSkin:OnThemeChanged(domain, key)
    if domain == "color" and key ~= "blizzardYellow" and key ~= "title"
        and key ~= "accent" and key ~= "accentAlt"
        and key ~= "blizzardExpand" and key ~= "blizzardExpandPressed"
        and key ~= "blizzardExpandHover" and key ~= "disabled" then return end
    if domain == "adapter" and key ~= "objectiveTracker"
        and key ~= "objectiveTrackerAccents" then return end
    if domain == "hud" and key ~= "objectiveTrackerHeaders"
        and key ~= "objectiveTrackerBackground"
        and key ~= "objectiveTrackerStyle" then return end
    if domain ~= "color" and domain ~= "theme" and domain ~= "profile"
        and domain ~= "adapter" and domain ~= "hud" then return end
    RefreshAllAccents()
    RefreshAllSurfaces()
end

function ObjectiveTrackerSkin.Apply(frame, owner)
    if not frame then return false, "missing" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not NS.Safety.CanDecorate(frame, true) then return false, "protected" end
    return ApplyNow(frame, owner)
end

function ObjectiveTrackerSkin.ApplyAccents(frame, owner)
    if not frame then return false, "missing" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not NS.Safety.CanDecorate(frame, true) then return false, "protected" end
    local state = OwnerState(owner)
    state.active = true
    state.accents = true
    state.owner = owner
    state.frame = frame
    SkinHeaderAccents(state, SafeField(frame, "Header"))
    for index = 1, #modules do
        SkinModuleAccents(state, _G[modules[index]])
    end
    return true
end

function ObjectiveTrackerSkin.Disable(_, owner)
    if NS.IsCombatLocked() then return false, "combat" end
    local state = ObjectiveTrackerSkin.owners[owner]
    if state then
        state.active = false
        for target in pairs(state.surfaces) do
            pcall(NS.Surface.SetVisible, target, false)
        end
        for _, trim in pairs(state.headerTrims) do pcall(trim.Hide, trim) end
        for _, rule in pairs(state.headerRules) do pcall(rule.Hide, rule) end
    end
    if NS.Checkmarks then NS.Checkmarks.UntrackOwner(owner) end
    NS.Cosmetics.RestoreOwner(owner)
    ObjectiveTrackerSkin.owners[owner] = nil
    local anyAccents = false
    for _, other in pairs(ObjectiveTrackerSkin.owners) do
        if other.active and other.accents then anyAccents = true break end
    end
    if not anyAccents and NS.CombatGate then NS.CombatGate.Cancel(DEFER_KEY) end
    local anySurfaces = false
    for _, other in pairs(ObjectiveTrackerSkin.owners) do
        if other.active and not other.accents then anySurfaces = true break end
    end
    if not anySurfaces and NS.CombatGate then NS.CombatGate.Cancel(SURFACE_DEFER_KEY) end
    return true
end


NS.Registry.AddListener(ObjectiveTrackerSkin, ObjectiveTrackerSkin.OnThemeChanged)

return ObjectiveTrackerSkin
