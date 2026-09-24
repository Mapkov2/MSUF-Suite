local _, NS = ...

-- Clean-room Character/PaperDoll coverage verified against
-- Gethe/wow-ui-source upstream/live at
-- 027d26c3406d3de2cbd2b1f67d468fe033a1bcd4:
--
--   Blizzard_UIPanels_Game/Mainline/CharacterFrame.xml
--   Blizzard_UIPanels_Game/Mainline/PaperDollFrame.xml
--   Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua
-- Forever uses upstream/forever c6e89983 Camelot/CharacterFrame.xml: its native
-- LeftPaneHost, RightPaneHost and ModeTabs remain responsible for content,
-- sizing, selection and click behavior.
--
-- Blizzard keeps ownership of the model scene, equipment slots, scripts,
-- item/state data and pooled stat lifecycle. Wide equipment geometry is owned
-- reversibly by GearAnnotations, after the exact native UpdateSize completion.
local CharacterPanel = {
    owners = {},
    activeOwnerCount = 0,
    waiting = false,
    hookedStats = false,
    hookedSlots = false,
    hookedSidebar = false,
    hookedModelBackground = false,
    hookedModeTabs = false,
    hookedTabLayout = false,
    exactSlots = setmetatable({}, { __mode = "k" }),
}
NS.CharacterPanel = CharacterPanel

local DEFAULT_OWNER = "blizzardWindows"
local CHARACTER_ADDON = "Blizzard_UIPanels_Game"

local modelArtNames = {
    "CharacterModelFrameBackgroundTopLeft",
    "CharacterModelFrameBackgroundTopRight",
    "CharacterModelFrameBackgroundBotLeft",
    "CharacterModelFrameBackgroundBotRight",
    "CharacterModelFrameBackgroundOverlay",
    "PaperDollInnerBorderTopLeft",
    "PaperDollInnerBorderTopRight",
    "PaperDollInnerBorderBottomLeft",
    "PaperDollInnerBorderBottomRight",
    "PaperDollInnerBorderLeft",
    "PaperDollInnerBorderRight",
    "PaperDollInnerBorderTop",
    "PaperDollInnerBorderBottom",
    "PaperDollInnerBorderBottom2",
}
local modelBackgroundNames = {
    "CharacterModelFrameBackgroundTopLeft",
    "CharacterModelFrameBackgroundTopRight",
    "CharacterModelFrameBackgroundBotLeft",
    "CharacterModelFrameBackgroundBotRight",
}

local slotNames = {
    "CharacterHeadSlot",
    "CharacterNeckSlot",
    "CharacterShoulderSlot",
    "CharacterBackSlot",
    "CharacterChestSlot",
    "CharacterShirtSlot",
    "CharacterTabardSlot",
    "CharacterWristSlot",
    "CharacterHandsSlot",
    "CharacterWaistSlot",
    "CharacterLegsSlot",
    "CharacterFeetSlot",
    "CharacterFinger0Slot",
    "CharacterFinger1Slot",
    "CharacterTrinket0Slot",
    "CharacterTrinket1Slot",
    "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot",
}

local statCategoryFields = {
    "ItemLevelCategory",
    "AttributesCategory",
    "EnhancementsCategory",
}

local FOREVER_VIEWS = {
    { "ReputationFrame", "ReputationDetailFrame" },
    { "TokenFrame", "DetailFrame" },
    { "SkillsFrame", "SkillDetailFrame" },
    { "PVPRankFrame", "DetailFrame" },
    { "StatisticsFrame" },
}

local FOREVER_TAB_FALLBACKS = {
    "Character", "Reputation", "Skills", "PvP", "Currency", "Statistics",
}

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function AccessibleBoolean(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        if type(canaccessvalue) ~= "function" or not canaccessvalue(value) then
            return nil
        end
    end
    return value == true
end

local function IsShown(region)
    local method = SafeField(region, "IsShown")
    if type(method) ~= "function" then return nil end
    local ok, shown = pcall(method, region)
    if not ok then return nil end
    return AccessibleBoolean(shown)
end

local function OwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = CharacterPanel.owners[owner]
    if not state then
        state = {
            owner = owner,
            active = false,
            surfaces = WeakSet(),
            deferred = {},
        }
        CharacterPanel.owners[owner] = state
    end
    return state, owner
end

local function Report(label, message)
    if type(NS.ReportError) == "function" then
        NS.ReportError("character panel " .. tostring(label), message)
    end
end

local function CategoryEnabled()
    return not NS.GenericWindows
        or type(NS.GenericWindows.IsCategoryEnabled) ~= "function"
        or NS.GenericWindows.IsCategoryEnabled("character")
end

local function IsAddonLoaded()
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loadedOrLoading, loaded = pcall(C_AddOns.IsAddOnLoaded, CHARACTER_ADDON)
        return ok and (loaded == true or (loaded == nil and loadedOrLoading == true))
    end
    if type(IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(IsAddOnLoaded, CHARACTER_ADDON)
        return ok and loaded == true
    end
    return _G.CharacterFrame ~= nil
end

local function TrackSurface(state, target)
    if state and target then state.surfaces[target] = true end
end

local function Fade(state, region)
    if not state or not region or NS.IsCombatLocked() or not NS.Cosmetics
        or type(NS.Cosmetics.Fade) ~= "function" or not NS.Safety
        or not NS.Safety.CanDecorate(region, true) then
        return false
    end
    local ok, result = pcall(NS.Cosmetics.Fade, region, state.owner)
    if not ok then Report("fade", result) end
    return ok and result == true
end

local function FadeNineSlice(state, target)
    local nineSlice = SafeField(target, "NineSlice")
    if not nineSlice or NS.IsCombatLocked() or not NS.Cosmetics
        or type(NS.Cosmetics.FadeNineSlice) ~= "function" or not NS.Safety
        or not NS.Safety.CanDecorate(nineSlice, true) then
        return false
    end
    local ok, message = pcall(NS.Cosmetics.FadeNineSlice, nineSlice, state.owner)
    if not ok then
        Report("nine slice", message)
        return false
    end
    return true
end

local function Attach(state, target, role, radius, inset, listItem, activeRole)
    if not state or not target or NS.IsCombatLocked() or not NS.Surface
        or type(NS.Surface.Attach) ~= "function" or not NS.Safety
        or not NS.Safety.CanCreateRegions(target, true) then
        return false
    end
    local ok, surface = pcall(NS.Surface.Attach, target, {
        role = role or "card",
        radius = radius or 4,
        inset = inset or 0,
        listItem = listItem == true,
        activeRole = activeRole,
        allowImplicitProtected = true,
    })
    if ok and surface then
        TrackSurface(state, target)
        return true
    end
    if not ok then Report("surface", surface) end
    return false
end

local function FadeAtlas(state, host, atlas)
    if not host or type(host.GetRegions) ~= "function" then return end
    local ok, regions = pcall(function() return { host:GetRegions() } end)
    if not ok then return end
    for index = 1, #regions do
        local region = regions[index]
        local getAtlas = SafeField(region, "GetAtlas")
        if type(getAtlas) == "function" then
            local read, name = pcall(getAtlas, region)
            if read and name == atlas then Fade(state, region) end
        end
    end
end

local function ForeverLook()
    return NS.Client.isForever and NS.DB and NS.DB.theme
        and NS.DB.theme.look == "foreverGlass"
end

local function CaptureGeometry(frame)
    if not frame or type(frame.GetNumPoints) ~= "function"
        or type(frame.GetWidth) ~= "function" or type(frame.GetHeight) ~= "function"
        or type(frame.ClearAllPoints) ~= "function" or type(frame.SetPoint) ~= "function"
        or type(frame.SetSize) ~= "function" then return nil end
    local count = frame:GetNumPoints()
    if type(count) ~= "number" or count > 4 then return nil end
    local snapshot = { width = frame:GetWidth(), height = frame:GetHeight(), points = {} }
    if type(frame.GetFrameStrata) == "function" then
        snapshot.strata = frame:GetFrameStrata()
    end
    if type(frame.GetFrameLevel) == "function" then
        snapshot.level = frame:GetFrameLevel()
    end
    for index = 1, count do
        snapshot.points[index] = { frame:GetPoint(index) }
    end
    return snapshot
end

local function CanMoveForever(frame)
    if not frame or not NS.Safety.CanCreateRegions(frame, true) then return false end
    if type(NS.Safety.GetProtection) == "function" then
        local protected = NS.Safety.GetProtection(frame)
        if protected then return false end
    end
    return true
end

local function RestoreGeometry(frame, snapshot)
    if not frame or not snapshot then return end
    frame:ClearAllPoints()
    for index = 1, #snapshot.points do
        frame:SetPoint(unpack(snapshot.points[index]))
    end
    frame:SetSize(snapshot.width, snapshot.height)
    if snapshot.strata and type(frame.SetFrameStrata) == "function" then
        frame:SetFrameStrata(snapshot.strata)
    end
    if snapshot.level and type(frame.SetFrameLevel) == "function" then
        frame:SetFrameLevel(snapshot.level)
    end
end

local function RestoreForeverTabs(state, root)
    local nav = root and root._msufForeverTabs
    if not nav or not nav.active then return end
    nav.active, nav.restoring = false, true
    for index, tab in ipairs(nav.tabs) do
        RestoreGeometry(tab, nav.tabGeometry[index])
        if tab._msufForeverLabel then tab._msufForeverLabel:Hide() end
        if tab._msufForeverRule then tab._msufForeverRule:Hide() end
        local icon = SafeField(tab, "Icon")
        if icon then NS.Cosmetics.Restore(icon, state.owner) end
    end
    RestoreGeometry(nav.container, nav.containerGeometry)
    if type(root.UpdateTabLayout) == "function" then root:UpdateTabLayout() end
    if nav.header then nav.header:Hide() end
    if nav.headerRule then nav.headerRule:Hide() end
    local title = SafeField(root, "TitleText")
    if title then NS.Cosmetics.Restore(title, state.owner) end
    nav.restoring = false
end

local function PositionForeverTabs(state, root)
    if not ForeverLook() or not NS.Theme or not NS.Safety
        or not CanMoveForever(root) then
        RestoreForeverTabs(state, root)
        return false
    end
    local container = SafeField(root, "ModeTabs")
    local tabs = SafeField(container, "Tabs")
    local width = type(root.GetWidth) == "function" and root:GetWidth()
    if type(tabs) ~= "table" or #tabs < 3 or #tabs > 8
        or type(width) ~= "number" or width < 550
        or type(container.SetFrameStrata) ~= "function"
        or type(container.SetFrameLevel) ~= "function"
        or type(root.GetFrameLevel) ~= "function" then
        RestoreForeverTabs(state, root)
        return false
    end
    local nav = root._msufForeverTabs
    if not nav then
        local original = CaptureGeometry(container)
        if not original or not CanMoveForever(container) then return false end
        nav = { container = container, containerGeometry = original,
            tabs = {}, tabGeometry = {} }
        for index = 1, #tabs do
            local tab = tabs[index]
            local geometry = CaptureGeometry(tab)
            if not geometry or not CanMoveForever(tab) then return false end
            nav.tabs[index], nav.tabGeometry[index] = tab, geometry
        end
        root._msufForeverTabs = nav
    end
    if nav.restoring then return false end
    if not nav.header then
        nav.header = container:CreateTexture(nil, "ARTWORK", nil, -7)
        nav.headerRule = container:CreateTexture(nil, "ARTWORK", nil, -6)
        nav.headerRule:SetHeight(1)
    end
    nav.header:SetColorTexture(NS.Theme.GetColor("microBarFill"))
    nav.headerRule:SetColorTexture(NS.Theme.GetColor("microBarBorder"))
    local usable = math.min(384, width - 24)
    local visibleTabs = {}
    for index, tab in ipairs(nav.tabs) do
        if IsShown(tab) ~= false then
            visibleTabs[#visibleTabs + 1] = { tab = tab, index = index }
        end
    end
    if #visibleTabs == 0 then
        nav.header:Hide()
        nav.headerRule:Hide()
        return false
    end
    nav.header:Show()
    nav.headerRule:Show()
    nav.active = true
    local tabWidth = math.min(64, math.floor(usable / #visibleTabs))
    -- The native reputation/currency lists use HIGH strata. Keep their native
    -- tabs above those panes when presenting the tabs inside the window.
    container:SetFrameStrata("HIGH")
    container:SetFrameLevel(math.max(520, root:GetFrameLevel() + 50))
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", root, "TOPLEFT", 8, -26)
    container:SetSize(tabWidth * #visibleTabs, 30)
    nav.header:ClearAllPoints()
    nav.header:SetPoint("TOPLEFT", container, "TOPLEFT", -4, 2)
    nav.header:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 4, -2)
    nav.headerRule:ClearAllPoints()
    nav.headerRule:SetPoint("BOTTOMLEFT", nav.header, "BOTTOMLEFT", 0, 0)
    nav.headerRule:SetPoint("BOTTOMRIGHT", nav.header, "BOTTOMRIGHT", 0, 0)
    for visualIndex, item in ipairs(visibleTabs) do
        local tab, index = item.tab, item.index
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", container, "TOPLEFT", (visualIndex - 1) * tabWidth, 0)
        tab:SetSize(tabWidth, 30)
        local icon = SafeField(tab, "Icon")
        if icon then Fade(state, icon) end
        if not tab._msufForeverLabel then
            local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("CENTER", tab, "CENTER", 0, 1)
            tab._msufForeverLabel = label
            local rule = tab:CreateTexture(nil, "OVERLAY")
            rule:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 10, 1)
            rule:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -10, 1)
            rule:SetHeight(2)
            tab._msufForeverRule = rule
        end
        local labelText = tab.tooltipText
        tab._msufForeverLabel:SetText(type(labelText) == "string"
            and labelText ~= "" and labelText
            or FOREVER_TAB_FALLBACKS[index] or tostring(index))
        tab._msufForeverLabel:SetWidth(tabWidth - 4)
        tab._msufForeverLabel:Show()
        local selected = root.selectedTab == index
        tab._msufForeverLabel:SetTextColor(NS.Theme.GetColor(
            selected and "accent" or "text"))
        tab._msufForeverRule:SetColorTexture(NS.Theme.GetColor("accent"))
        tab._msufForeverRule:SetShown(selected)
    end
    local title = SafeField(root, "TitleText")
    if title then NS.Cosmetics.Restore(title, state.owner) end
    return true
end

local function SkinForeverPanes(state, root)
    if not NS.Client.isForever then return end
    local left = SafeField(root, "LeftPaneHost")
    local right = SafeField(root, "RightPaneHost")
    if Attach(state, left, "panel", 4, 0) then
        FadeAtlas(state, left, "UI-Character-Info-General-BG")
    end
    if Attach(state, right, "panel", 4, 0) then
        FadeAtlas(state, right, "UI-Character-Info-Stat-BG")
        Fade(state, SafeField(right, "StoneBg"))
    end
end

local function SkinForeverSubframes(state, root)
    if not ForeverLook() or not state or not state.active or NS.IsCombatLocked() then
        return
    end
    -- Camelot already supplies the faction, currency, skills, PvP and
    -- statistics views. Decorate their exact native list and detail hosts as
    -- each Blizzard subframe becomes available; keep its data and scripts.
    for index = 1, #FOREVER_VIEWS do
        local spec = FOREVER_VIEWS[index]
        local view = _G[spec[1]]
        if view and type(view.GetParent) == "function"
            and view:GetParent() == root then
            local list = SafeField(view, "ScrollBox")
            local detail = spec[2] and SafeField(view, spec[2])
            if list then Attach(state, list, "panel", 4, 0) end
            if detail then Attach(state, detail, "card", 4, 0) end
        end
    end
end

local function SkinForeverModeTabs(state, root)
    if not NS.Client.isForever or not state or not state.active or NS.IsCombatLocked() then return end
    local container = SafeField(root, "ModeTabs")
    local tabs = SafeField(container, "Tabs")
    if type(tabs) ~= "table" then return end
    Attach(state, container, "panel", 4, 0)
    for index = 1, #tabs do
        local tab = tabs[index]
        if tab then
            local attached
            if ForeverLook() and NS.Surface and NS.Surface.Attach then
                local ok, surface = pcall(NS.Surface.Attach, tab, {
                    role = "navigation", activeRole = "navigationActive",
                    fillVisible = false, border = 0, radius = 2, inset = 0,
                    allowImplicitProtected = true,
                })
                attached = ok and surface ~= nil
                if attached then TrackSurface(state, tab) end
            else
                attached = Attach(state, tab, "navigation", 4, 1, true, "navigationActive")
            end
            if attached then
                Fade(state, SafeField(tab, "Background"))
                Fade(state, SafeField(tab, "SelectedTexture"))
                Fade(state, SafeField(tab, "HighlightTexture"))
                NS.Surface.SetActive(tab, root.selectedTab == index)
            end
        end
    end
    PositionForeverTabs(state, root)
end

local function SkinInset(state, inset)
    if not inset then return false end
    FadeNineSlice(state, inset)
    Fade(state, SafeField(inset, "Bg"))
    Fade(state, SafeField(inset, "Background"))
    return Attach(state, inset, "panel", 5, 0)
end

local function SkinStatRow(state, row)
    if not row then return false end
    Fade(state, SafeField(row, "Background"))
    if row.Label and row.Value and NS.CharacterStats.StylesRows(_G.CharacterStatsPane) then
        -- The stat-card pass supplies the final spec once for these exact rows.
        TrackSurface(state, row)
        return true
    end
    return Attach(state, row, "card", 2, 1, true)
end

local function SkinStats(state)
    local pane = _G.CharacterStatsPane
    if not pane or not state or not state.active or NS.IsCombatLocked() then
        return false
    end

    Fade(state, SafeField(pane, "ClassBackground"))
    Attach(state, pane, NS.GearAnnotations.IsWide() and "card" or "panel", 5, 0)
    local pool = SafeField(pane, "statsFramePool")
    local enumerate = SafeField(pool, "EnumerateActive")
    local modern = NS.CharacterStats.StylesRows(pane) and type(enumerate)=="function"

    for index = 1, #statCategoryFields do
        local category = SafeField(pane, statCategoryFields[index])
        if category then
            Fade(state, SafeField(category, "Background"))
            -- The dedicated pass owns the final section spec; do not paint a
            -- boxed header only to replace it again in the same update.
            if modern then TrackSurface(state,category)
            else Attach(state, category, "card", 3, 1, false) end
        end
    end

    local itemLevel = SafeField(pane, "ItemLevelFrame")
    if itemLevel then
        Fade(state, SafeField(itemLevel, "Background"))
        if modern then TrackSurface(state,itemLevel)
        else Attach(state, itemLevel, "card", 3, 1, false) end
    end

    if type(enumerate) == "function" then
        local ok, iterator, invariant, initial = pcall(enumerate, pool)
        if ok and type(iterator) == "function" then
            local control = initial
            -- Retail currently has far fewer than 64 active character-stat
            -- rows. The hard ceiling keeps this foreign-pool walk bounded if
            -- a future/custom iterator ever violates the normal contract.
            for _ = 1, 64 do
                local iterOk, row = pcall(iterator, invariant, control)
                if not iterOk then
                    Report("stat pool", row)
                    break
                end
                if row == nil then break end
                control = row
                -- ObjectPoolMixin:EnumerateActive() returns object -> true.
                -- Only the object key is touched; Blizzard owns every value.
                SkinStatRow(state, row)
            end
        end
    end
    NS.CharacterStats.Apply(pane, state.owner)
    return true
end

local function SkinModel(state)
    if not state or not state.active or NS.IsCombatLocked() then return false end
    local model = _G.CharacterModelScene
    local saved = model and model._msufForeverBackgroundColors
    if model and ForeverLook() then
        if model and not saved then
            saved = {}
            model._msufForeverBackgroundColors = saved
        end
        for index = 1, #modelBackgroundNames do
            local region = _G[modelBackgroundNames[index]]
            if region and NS.Safety.CanDecorate(region, true)
                and type(region.GetVertexColor) == "function"
                and type(region.SetVertexColor) == "function" then
                NS.Cosmetics.Restore(region, state.owner)
                if not saved[region] then
                    saved[region] = { region:GetVertexColor() }
                end
                region:SetVertexColor(0.36, 0.44, 0.54, saved[region][4] or 1)
            end
        end
    elseif saved then
        for region, color in pairs(saved) do
            region:SetVertexColor(unpack(color))
        end
        model._msufForeverBackgroundColors = nil
    end
    for index = ForeverLook() and #modelBackgroundNames + 1 or 1, #modelArtNames do
        Fade(state, _G[modelArtNames[index]])
    end
    return Attach(state, model, "card", 6, 0)
end

local function SkinSlot(state, slot)
    if not state or not state.active or not slot or not CharacterPanel.exactSlots[slot]
        or NS.IsCombatLocked() then
        return false
    end

    Attach(state, slot, "button", 4, 0, true)
    if NS.IconSkin and type(NS.IconSkin.Apply) == "function" then
        local icon = SafeField(slot, "Icon") or SafeField(slot, "icon")
        local border = SafeField(slot, "IconBorder") or SafeField(slot, "iconBorder")
        if icon and border then
            local ok, iconState = pcall(NS.IconSkin.Apply, slot, state.owner, {
                icon = icon,
                nativeBorder = border,
                allowImplicitProtected = true,
            })
            if not ok then Report("slot icon", iconState) end
        end
    end
    return true
end

local function SkinAllSlots(state)
    if not state or not state.active or NS.IsCombatLocked() then return false end
    local applied = false
    for index = 1, #slotNames do
        local name = slotNames[index]
        local slot = _G[name]
        if slot then
            CharacterPanel.exactSlots[slot] = true
            Fade(state, _G[name .. "Frame"])
            applied = SkinSlot(state, slot) or applied
        end
    end
    return applied
end

local function SkinSidebar(state)
    if not state or not state.active or NS.IsCombatLocked() then return false end
    local container = _G.PaperDollSidebarTabs
    Fade(state, SafeField(container, "DecorLeft"))
    Fade(state, SafeField(container, "DecorRight"))

    local applied = false
    for index = 1, 3 do
        local tab = _G["PaperDollSidebarTab" .. index]
        if tab then
            local tabApplied = false
            local hider = SafeField(tab, "Hider")
            local active = IsShown(hider) == false
            if NS.ControlSkin and type(NS.ControlSkin.ApplyButton) == "function"
                and NS.Safety and NS.Safety.CanControl(tab, true) then
                local ok, controlState = pcall(NS.ControlSkin.ApplyButton, tab, state.owner, {
                    role = "navigation",
                    activeRole = "navigationActive",
                    active = active,
                    useControlShape = true,
                    pillHeight = 32,
                    radius = 5,
                    inset = 1,
                    regions = { "TabBg", "Hider", "Highlight" },
                    allowImplicitProtected = true,
                })
                if ok and controlState then
                    TrackSurface(state, tab)
                    tabApplied = true
                    applied = true
                elseif not ok then
                    Report("sidebar tab", controlState)
                end
            end
            if not tabApplied then
                Fade(state, SafeField(tab, "TabBg"))
                Fade(state, hider)
                Fade(state, SafeField(tab, "Highlight"))
                tabApplied = Attach(state, tab, "navigation", 5, 1, true)
                applied = tabApplied or applied
            end
        end
    end
    return applied
end

local function DeferredKey(state, suffix)
    return "character-panel:" .. tostring(suffix) .. ":" .. tostring(state.owner)
end

local function RunOrDefer(state, suffix, callback)
    if not state or not state.active or type(callback) ~= "function" then return false end
    local key = DeferredKey(state, suffix)
    state.deferred[key] = true
    local ran, reason = NS.CombatGate.RunOrDefer(key, function()
        local current = CharacterPanel.owners[state.owner]
        if current then current.deferred[key] = nil end
        if current and current.active then callback(current) end
    end)
    if ran then state.deferred[key] = nil end
    return ran == true, reason
end

local function RefreshStatsForOwners()
    for _, state in pairs(CharacterPanel.owners) do
        if state.active then
            RunOrDefer(state, "stats", SkinStats)
        end
    end
end

local function RefreshSlotForOwners(slot)
    if not CharacterPanel.exactSlots[slot] then return end
    for _, state in pairs(CharacterPanel.owners) do
        if state.active then
            if NS.IsCombatLocked() then
                -- All native slot updates in one combat window collapse into
                -- one bounded pass after PLAYER_REGEN_ENABLED.
                RunOrDefer(state, "slots", SkinAllSlots)
            else
                SkinSlot(state, slot)
            end
        end
    end
end

local function RefreshSidebarForOwners()
    for _, state in pairs(CharacterPanel.owners) do
        if state.active then
            RunOrDefer(state, "sidebar", SkinSidebar)
        end
    end
end

local function RefreshModelForOwners(model)
    if model ~= _G.CharacterModelScene then return end
    for _, state in pairs(CharacterPanel.owners) do
        if state.active then
            RunOrDefer(state, "model", SkinModel)
        end
    end
end

local function InstallHooks()
    if type(hooksecurefunc) ~= "function" then return false end

    local root=_G.CharacterFrame
    if root and CharacterPanel.layoutRoot~=root and type(root.UpdateSize)=="function" then
        hooksecurefunc(root,"UpdateSize",function()
            for _,state in pairs(CharacterPanel.owners) do
                if state.active then
                    RunOrDefer(state,"layout",function(current)
                        local view=NS.CharacterDetails.views[root]
                        NS.GearAnnotations.ApplyLayout(view)
                        -- ShowSubFrame assigns activeSubframe AFTER showing the
                        -- PaperDoll child. Reflow its existing snapshots here;
                        -- do not perform another inventory/tooltip scan.
                        if view and view.wide then
                            for _,row in ipairs(view.rows) do NS.GearAnnotations.Update(view,row,row.slotName) end
                            NS.GearAnnotations.UpdateSummary(view)
                        end
                        NS.EQoLCharacter.Refresh()
                        SkinStats(current)
                    end)
                end
            end
        end)
        CharacterPanel.layoutRoot=root
    end

    if not CharacterPanel.hookedStats
        and type(_G.PaperDollFrame_UpdateStats) == "function" then
        local ok = pcall(function()
            hooksecurefunc("PaperDollFrame_UpdateStats", RefreshStatsForOwners)
        end)
        CharacterPanel.hookedStats = ok == true
    end

    if not CharacterPanel.hookedSlots
        and type(_G.PaperDollItemSlotButton_Update) == "function" then
        local ok = pcall(function()
            hooksecurefunc("PaperDollItemSlotButton_Update", RefreshSlotForOwners)
        end)
        CharacterPanel.hookedSlots = ok == true
    end

    if not CharacterPanel.hookedSidebar
        and type(_G.PaperDollFrame_UpdateSidebarTabs) == "function" then
        local ok = pcall(function()
            hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", RefreshSidebarForOwners)
        end)
        CharacterPanel.hookedSidebar = ok == true
    end


    -- SetPaperDollBackground rewrites the native race background and its
    -- overlay alpha every time the paper doll opens. Re-assert only our
    -- cosmetic suppression after that native update; the model and textures
    -- remain Blizzard-owned.
    if not CharacterPanel.hookedModelBackground
        and type(_G.SetPaperDollBackground) == "function" then
        local ok = pcall(function()
            hooksecurefunc("SetPaperDollBackground", RefreshModelForOwners)
        end)
        CharacterPanel.hookedModelBackground = ok == true
    end

    if NS.Client.isForever and not CharacterPanel.hookedModeTabs and root
        and type(root.SetSelectedModeTabByFrame) == "function" then
        local ok = pcall(function()
            hooksecurefunc(root, "SetSelectedModeTabByFrame", function()
                for _, state in pairs(CharacterPanel.owners) do
                    if state.active then
                        RunOrDefer(state, "mode-tabs", function(current)
                            SkinForeverModeTabs(current, root)
                            SkinForeverSubframes(current, root)
                        end)
                    end
                end
            end)
        end)
        CharacterPanel.hookedModeTabs = ok == true
    end
    if NS.Client.isForever and not CharacterPanel.hookedTabLayout and root
        and type(root.UpdateTabLayout) == "function" then
        local ok = pcall(function()
            hooksecurefunc(root, "UpdateTabLayout", function()
                for _, state in pairs(CharacterPanel.owners) do
                    if state.active then
                        RunOrDefer(state, "mode-tabs-layout", function(current)
                            PositionForeverTabs(current, root)
                        end)
                    end
                end
            end)
        end)
        CharacterPanel.hookedTabLayout = ok == true
    end

    return CharacterPanel.hookedStats and CharacterPanel.hookedSlots
        and CharacterPanel.hookedSidebar and CharacterPanel.hookedModelBackground
end

local function ApplyNow(state)
    local root = _G.CharacterFrame
    if not root or not state or not state.active then return false, "missing" end
    if NS.IsCombatLocked() then return false, "combat" end

    Fade(state, SafeField(root, "Background"))
    Fade(state, _G.CharacterFramePortrait)
    Fade(state, SafeField(root, "Portrait"))
    Fade(state, SafeField(root, "portrait"))
    local portraitContainer = SafeField(root, "PortraitContainer")
    Fade(state, SafeField(portraitContainer, "Portrait"))
    Fade(state, SafeField(portraitContainer, "portrait"))
    SkinInset(state, SafeField(root, "Inset"))
    SkinInset(state, SafeField(root, "InsetRight") or _G.CharacterFrameInsetRight)
    SkinForeverPanes(state, root)

    NS.CharacterDetails.Apply(root,"character",state.owner)

    SkinModel(state)

    SkinStats(state)
    SkinAllSlots(state)
    SkinSidebar(state)
    SkinForeverModeTabs(state, root)
    SkinForeverSubframes(state, root)
    NS.EQoLCharacter.Apply(state.owner)
    InstallHooks()
    return true, "applied"
end

local function ApplyForActiveOwners()
    if NS.IsCombatLocked() then
        for _, state in pairs(CharacterPanel.owners) do
            if state.active then
                RunOrDefer(state, "apply", ApplyNow)
            end
        end
        return
    end
    for _, state in pairs(CharacterPanel.owners) do
        if state.active then
            local ok, message = pcall(ApplyNow, state)
            if not ok then Report("load", message) end
        end
    end
end

local function ScheduleLoad()
    if CharacterPanel.waiting or IsAddonLoaded() or not EventUtil
        or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then
        return false
    end
    CharacterPanel.waiting = true
    local ok, message = pcall(EventUtil.ContinueOnAddOnLoaded, CHARACTER_ADDON, function()
        CharacterPanel.waiting = false
        ApplyForActiveOwners()
    end)
    if not ok then
        CharacterPanel.waiting = false
        Report("addon load", message)
        return false
    end
    return true
end

function CharacterPanel.Apply(owner)
    if not CategoryEnabled() then return true, "disabled" end
    local state
    state, owner = OwnerState(owner)
    if not state.active then
        state.active = true
        CharacterPanel.activeOwnerCount = CharacterPanel.activeOwnerCount + 1
    end
    if NS.IsCombatLocked() then
        RunOrDefer(state, "apply", function(current)
            if _G.CharacterFrame then
                ApplyNow(current)
            else
                ScheduleLoad()
            end
        end)
        return false, "combat"
    end
    if not _G.CharacterFrame then
        if ScheduleLoad() then return true, "waiting" end
        return false, "missing"
    end
    return ApplyNow(state)
end

function CharacterPanel.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = CharacterPanel.owners[owner]
    if not state then return true end
    if NS.IsCombatLocked() then return false, "combat" end

    state.active = false
    local model = _G.CharacterModelScene
    local colors = model and model._msufForeverBackgroundColors
    if colors then
        for region, color in pairs(colors) do region:SetVertexColor(unpack(color)) end
        model._msufForeverBackgroundColors = nil
    end
    RestoreForeverTabs(state, _G.CharacterFrame)
    NS.EQoLCharacter.Disable(owner)
    NS.CharacterStats.Disable(_G.CharacterStatsPane, owner)
    NS.CharacterDetails.Disable(_G.CharacterFrame,owner)
    for key in pairs(state.deferred) do
        NS.CombatGate.Cancel(key)
        state.deferred[key] = nil
    end
    for target in pairs(state.surfaces) do
        pcall(NS.Surface.SetVisible, target, false)
    end
    CharacterPanel.owners[owner] = nil
    CharacterPanel.activeOwnerCount = math.max(0, CharacterPanel.activeOwnerCount - 1)

    -- The parent blizzardWindows adapter restores the shared IconSkin,
    -- ControlSkin and Cosmetics owner exactly once through GenericWindows.
    return true
end

if NS.Registry and type(NS.Registry.AddListener) == "function" then
    NS.Registry.AddListener(CharacterPanel, function(_, domain, key)
        if not NS.Client.isForever or (domain ~= "profile"
            and not (domain == "theme" and key == "look")) then return end
        local root = _G.CharacterFrame
        if not root then return end
        for _, state in pairs(CharacterPanel.owners) do
            if state.active then
                RunOrDefer(state, "mode-tabs-theme", function(current)
                    SkinForeverModeTabs(current, root)
                    SkinForeverSubframes(current, root)
                    SkinModel(current)
                end)
            end
        end
    end)
end

return CharacterPanel
