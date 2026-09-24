local _, NS = ...

-- Clean-room adapter for Blizzard_PlayerSpells (Retail 12.1).
--
-- The adapter intentionally touches only explicitly named visual regions. It
-- never replaces Blizzard scripts, clicks, attributes, data providers, or
-- secure spell controls. Dynamic spell rows are refreshed from Blizzard's own
-- coarse-grained PagedSpells callbacks; there is no hook, timer, or OnUpdate.

local PlayerSpellsSkin = {
    states = setmetatable({}, { __mode = "k" }),
    callbacksRegistered = false,
}
NS.PlayerSpellsSkin = PlayerSpellsSkin

local CALLBACK_FRAME_TAB = "PlayerSpellsFrame.TabSet"
local CALLBACK_DISPLAYED_SPELLS = "PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged"

local tabArtKeys = {
    "Left", "Middle", "Right",
    "LeftActive", "MiddleActive", "RightActive",
    "LeftHighlight", "MiddleHighlight", "RightHighlight",
}

local function IsUnsafe(frame)
    return not NS.Safety or not NS.Safety.CanCreateRegions(frame, true)
end

local function IsUnsafeControl(frame)
    return not NS.Safety or not NS.Safety.CanControl(frame, true)
        or not NS.Safety.CanCreateRegions(frame, true)
end

local function NewState(frame, owner)
    return {
        frame = frame,
        owner = owner,
        active = false,
        surfaces = setmetatable({}, { __mode = "k" }),
        glyphs = setmetatable({}, { __mode = "k" }),
        buttonGlyphs = setmetatable({}, { __mode = "k" }),
        textColors = setmetatable({}, { __mode = "k" }),
        textRoles = setmetatable({}, { __mode = "k" }),
        vertexColors = setmetatable({}, { __mode = "k" }),
    }
end

local function GetState(frame, owner)
    local state = PlayerSpellsSkin.states[frame]
    if not state then
        state = NewState(frame, owner)
        PlayerSpellsSkin.states[frame] = state
    end
    return state
end

local function SetThemeTextColor(state, fontObject, colorKey, recapture)
    if not fontObject or type(fontObject.SetTextColor) ~= "function" then
        return false
    end

    if (recapture or not state.textColors[fontObject]) and type(fontObject.GetTextColor) == "function" then
        local ok, r, g, b, a = pcall(fontObject.GetTextColor, fontObject)
        if ok and type(r) == "number" then
            state.textColors[fontObject] = { r, g, b, tonumber(a) or 1 }
        end
    end

    state.textRoles[fontObject] = colorKey
    local r, g, b, a = NS.Theme.GetColor(colorKey)
    fontObject:SetTextColor(r, g, b, a)
    return true
end

local function SuppressVertexAlpha(state, texture)
    if not texture or type(texture.SetVertexColor) ~= "function" then
        return false
    end

    if not state.vertexColors[texture] and type(texture.GetVertexColor) == "function" then
        local ok, r, g, b, a = pcall(texture.GetVertexColor, texture)
        if ok and type(r) == "number" then
            state.vertexColors[texture] = { r, g, b, tonumber(a) or 1 }
        end
    end

    texture:SetVertexColor(1, 1, 1, 0)
    return true
end

local function AttachSurface(state, target, spec)
    if not target or IsUnsafe(target) then
        return nil
    end

    spec = spec or {}
    spec.allowImplicitProtected = true
    local surface = NS.Surface.Attach(target, spec)
    if surface then
        state.surfaces[target] = true
        NS.Surface.SetVisible(target, true)
    end
    return surface
end

local function Fade(state, region)
    if region then
        NS.Cosmetics.Fade(region, state.owner)
    end
end

local function FadeNineSlice(state, nineSlice)
    if nineSlice then
        NS.Cosmetics.FadeNineSlice(nineSlice, state.owner)
    end
end

local function FadeButtonTextures(state, button)
    if not button or IsUnsafeControl(button) then
        return false
    end

    local getters = {
        "GetNormalTexture",
        "GetPushedTexture",
        "GetDisabledTexture",
        "GetHighlightTexture",
    }
    for index = 1, #getters do
        local getter = button[getters[index]]
        if type(getter) == "function" then
            local ok, texture = pcall(getter, button)
            if ok then
                Fade(state, texture)
            end
        end
    end
    return true
end

local function AddButtonGlyph(state, button, text, colorKey)
    if not button or IsUnsafeControl(button) then
        return nil
    end

    local glyph = state.buttonGlyphs[button]
    if not glyph then
        glyph = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        glyph:SetPoint("CENTER", button, "CENTER", 0, 0)
        state.buttonGlyphs[button] = glyph
        state.glyphs[glyph] = colorKey or "text"
    end

    glyph:SetText(text)
    state.glyphs[glyph] = colorKey or state.glyphs[glyph] or "text"
    local r, g, b, a = NS.Theme.GetColor(state.glyphs[glyph])
    glyph:SetTextColor(r, g, b, a)
    glyph:Show()
    return glyph
end

local function SkinGlyphButton(state, button, glyphText, spec)
    if not button or IsUnsafeControl(button) then
        return false
    end
    local actionKind = NS.Checkmarks and NS.Checkmarks.GetWindowAction(button) or nil
    if actionKind and NS.ControlSkin then
        spec = spec or {
            role = "button",
            shape = "round",
            radius = 6,
            inset = 2,
        }
        spec.allowImplicitProtected = true
        local applied = NS.ControlSkin.ApplyButton(button, state.owner, spec)
        if applied then
            state.surfaces[button] = true
            return true
        end
        return false
    end
    if not AttachSurface(state, button, spec or {
        role = "button",
        shape = "round",
        radius = 6,
        inset = 2,
    }) then
        return false
    end
    FadeButtonTextures(state, button)
    AddButtonGlyph(state, button, glyphText,
        glyphText == "X" and "blizzardClose" or "accentBright")
    return true
end

local function SkinSearchBox(state, searchBox)
    if not searchBox or IsUnsafeControl(searchBox) then
        return
    end

    local surface = NS.ControlSkin.ApplySearchBox(searchBox, state.owner, {
        role = "input",
        useControlShape = true,
        pillHeight = 28,
        inset = 1,
        allowImplicitProtected = true,
    })
    if surface then
        state.surfaces[searchBox] = true
    end
    SetThemeTextColor(state, searchBox, "text")
    SetThemeTextColor(state, searchBox.Instructions, "muted")
end

local function SkinSearchPreview(state, preview)
    if not preview or IsUnsafe(preview) then
        return
    end

    AttachSurface(state, preview, {
        role = "popup",
        radius = 6,
        inset = 0,
    })
    Fade(state, preview.Background)
    Fade(state, preview.BorderAnchor)
    Fade(state, preview.BotRightCorner)
    Fade(state, preview.BottomBorder)
    Fade(state, preview.LeftBorder)
    Fade(state, preview.RightBorder)
end

local function SkinTab(state, tab)
    if not tab or IsUnsafeControl(tab) then
        return
    end

    local surface = NS.ControlSkin.ApplyTab(tab, state.owner, {
        role = "navigation",
        activeRole = "navigationActive",
        useControlShape = true,
        pillHeight = 32,
        inset = 1,
        allowImplicitProtected = true,
    })
    if surface then
        state.surfaces[tab] = true
    end

    local selected = tab.isSelected == true
    NS.ControlSkin.Refresh(tab, selected)
    -- Blizzard changes the tab's FontObject whenever selection changes. Save
    -- that current native color before applying ours so Disable restores the
    -- latest selected/unselected state rather than the first state we saw.
    SetThemeTextColor(state, tab.Text, selected and "accentBright" or "muted", true)
end

local function SkinTabSystem(state, tabSystem)
    if not tabSystem or type(tabSystem.tabs) ~= "table" then
        return
    end
    for index = 1, #tabSystem.tabs do
        SkinTab(state, tabSystem.tabs[index])
    end
end

local function SkinHeader(state, header)
    AttachSurface(state, header, {
        role = "card",
        radius = 6,
        inset = 1,
        listItem = true,
    })
    SuppressVertexAlpha(state, header.Backplate)
    SuppressVertexAlpha(state, header.Border)
    SetThemeTextColor(state, header.Text, "title")
end

local function SkinSpellItem(state, item)
    AttachSurface(state, item, {
        role = "card",
        radius = 6,
        inset = 1,
        listItem = true,
    })

    -- Backplate alpha is changed by Blizzard on hover, so vertex alpha is used
    -- here instead of SetAlpha(0). The suppression survives those hover updates.
    SuppressVertexAlpha(state, item.Backplate)

    local button = item.Button
    if button and not IsUnsafeControl(button) then
        AttachSurface(state, button, {
            role = "panel",
            radius = 6,
            inset = 1,
        })
        SuppressVertexAlpha(state, button.Border)
    end

    local textContainer = item.TextContainer
    SetThemeTextColor(state, item.Name or (textContainer and textContainer.Name), "text")
    SetThemeTextColor(state, item.SubName or (textContainer and textContainer.SubName), "muted")
    SetThemeTextColor(state, item.RequiredLevel or (textContainer and textContainer.RequiredLevel), "warning")
end

local function SkinDisplayedSpellFrames(state)
    local spellBook = state.frame and state.frame.SpellBookFrame
    local paged = spellBook and spellBook.PagedSpellsFrame
    if not paged or type(paged.GetFrames) ~= "function" then
        return
    end

    local frames = paged:GetFrames()
    if type(frames) ~= "table" then
        return
    end

    for index = 1, #frames do
        local element = frames[index]
        if element then
            if element.Button and element.TextContainer then
                SkinSpellItem(state, element)
            elseif element.Backplate and element.Text then
                SkinHeader(state, element)
            end
        end
    end
end

local function SkinPagingControls(state, pagingControls)
    if not pagingControls then
        return
    end

    SetThemeTextColor(state, pagingControls.PageText, "muted")
    SkinGlyphButton(state, pagingControls.PrevPageButton, "<", {
        role = "button",
        shape = "round",
        radius = 6,
        inset = 3,
    })
    SkinGlyphButton(state, pagingControls.NextPageButton, ">", {
        role = "buttonPrimary",
        shape = "round",
        radius = 6,
        inset = 3,
    })
end

local function SkinSpellBookStatic(state, spellBook)
    if not spellBook or IsUnsafe(spellBook) then
        return
    end

    AttachSurface(state, spellBook, {
        role = "panel",
        radius = 8,
        inset = 3,
    })

    Fade(state, spellBook.TopBar)
    Fade(state, spellBook.BookBGHalved)
    Fade(state, spellBook.BookBGLeft)
    Fade(state, spellBook.BookBGRight)
    Fade(state, spellBook.BookCornerFlipbook)
    Fade(state, spellBook.Bookmark)

    SkinTabSystem(state, spellBook.CategoryTabSystem)
    SkinSearchBox(state, spellBook.SearchBox)
    SkinSearchPreview(state, spellBook.SearchPreviewContainer)

    local settingsDropdown = spellBook.SettingsDropdown
    if settingsDropdown and not IsUnsafeControl(settingsDropdown) then
        AttachSurface(state, settingsDropdown, {
            role = "button",
            shape = "round",
            radius = 6,
            inset = 2,
        })
    end

    -- The assisted-combat spell button itself inherits SecureFrameTemplate and
    -- is deliberately untouched. Only its non-secure containing chip is drawn.
    -- This container owns an explicitly secure spell button.  Leave the entire
    -- chip untouched so no MapkoSkin region participates in its secure tree.

    local paged = spellBook.PagedSpellsFrame
    SkinPagingControls(state, paged and paged.PagingControls)
end

local function SkinSpecializationAndTalentPages(state)
    local frame = state.frame
    if not frame or not NS.GenericWindows then
        return
    end

    local specFrame = frame.SpecFrame
    if specFrame and not IsUnsafe(specFrame) then
        -- Suppress the opaque native layer before attaching; the surface is
        -- then created after it and remains the visible full-frame base.
        Fade(state, specFrame.BlackBG)
        Fade(state, specFrame.Background)
        local shown = type(specFrame.IsShown) ~= "function" or specFrame:IsShown()
        if shown and (not state.pagesSkinned or not state.pagesSkinned[specFrame]) then
            NS.GenericWindows.ApplyFrame(specFrame, state.owner, {
                role = "panel",
                radius = 8,
                maxDepth = 7,
                maxNodes = 480,
                allowImplicitProtected = true,
            })
            state.pagesSkinned = state.pagesSkinned or setmetatable({}, { __mode = "k" })
            state.pagesSkinned[specFrame] = true
        end
    end

    local talentsFrame = frame.TalentsFrame
    if talentsFrame and not IsUnsafe(talentsFrame) then
        for _, key in ipairs({
            "BlackBG", "BottomBar", "Background",
        }) do
            Fade(state, talentsFrame[key])
        end
        for _, key in ipairs({
            "BackgroundFlash", "OverlayBackgroundRight", "OverlayBackgroundMid",
            "Clouds1", "Clouds2", "AirParticlesClose", "AirParticlesFar",
        }) do
            -- Blizzard animates the region alpha of these textures. A zero
            -- vertex alpha remains suppressed without touching animation state.
            SuppressVertexAlpha(state, talentsFrame[key])
        end
        local shown = type(talentsFrame.IsShown) ~= "function" or talentsFrame:IsShown()
        if shown and (not state.pagesSkinned or not state.pagesSkinned[talentsFrame]) then
            NS.GenericWindows.ApplyFrame(talentsFrame, state.owner, {
                role = "panel",
                radius = 8,
                maxDepth = 7,
                maxNodes = 600,
                allowImplicitProtected = true,
            })
            state.pagesSkinned = state.pagesSkinned or setmetatable({}, { __mode = "k" })
            state.pagesSkinned[talentsFrame] = true
        end
        SkinSearchBox(state, talentsFrame.SearchBox)
        SkinSearchPreview(state, talentsFrame.SearchPreviewContainer)
    end

    for _, dialog in ipairs({
        _G.ClassTalentLoadoutCreateDialog,
        _G.ClassTalentLoadoutEditDialog,
        _G.ClassTalentLoadoutImportDialog,
        _G.HeroTalentsSelectionDialog,
    }) do
        if dialog and not IsUnsafe(dialog)
            and (not state.pagesSkinned or not state.pagesSkinned[dialog]) then
            NS.GenericWindows.ApplyFrame(dialog, state.owner, {
                role = "popup",
                radius = 8,
                maxDepth = 7,
                maxNodes = 480,
                allowImplicitProtected = true,
            })
            state.pagesSkinned = state.pagesSkinned or setmetatable({}, { __mode = "k" })
            state.pagesSkinned[dialog] = true
        end
    end
end

local function SkinRootStatic(state)
    local frame = state.frame
    if not frame or IsUnsafe(frame) then
        return false
    end

    AttachSurface(state, frame, {
        role = "shell",
        radius = 8,
        inset = 0,
    })
    Fade(state, frame.Bg)
    Fade(state, frame.TopTileStreaks)
    FadeNineSlice(state, frame.NineSlice)

    local title = frame.TitleContainer and frame.TitleContainer.TitleText
    SetThemeTextColor(state, title, "title")
    SkinTabSystem(state, frame.TabSystem)

    SkinGlyphButton(state, frame.CloseButton, "X", {
        role = "button",
        shape = "round",
        radius = 6,
        inset = 2,
    })

    local maxMin = frame.MaximizeMinimizeButton
    if maxMin then
        SkinGlyphButton(state, maxMin.MaximizeButton, "+", {
            role = "button",
            shape = "round",
            radius = 6,
            inset = 2,
        })
        SkinGlyphButton(state, maxMin.MinimizeButton, "-", {
            role = "button",
            shape = "round",
            radius = 6,
            inset = 2,
        })
    end

    SkinSpellBookStatic(state, frame.SpellBookFrame)
    return true
end

local function RefreshThemeColors(state)
    for fontObject, colorKey in pairs(state.textRoles) do
        if fontObject and type(fontObject.SetTextColor) == "function" then
            local r, g, b, a = NS.Theme.GetColor(colorKey)
            fontObject:SetTextColor(r, g, b, a)
        end
    end
    for glyph, colorKey in pairs(state.glyphs) do
        if glyph and type(glyph.SetTextColor) == "function" then
            local r, g, b, a = NS.Theme.GetColor(colorKey)
            glyph:SetTextColor(r, g, b, a)
        end
    end
end

local function RefreshVisualState(state, refreshPages)
    if not state or not state.active then
        return
    end
    SkinTabSystem(state, state.frame.TabSystem)
    local spellBook = state.frame.SpellBookFrame
    SkinTabSystem(state, spellBook and spellBook.CategoryTabSystem)
    SkinDisplayedSpellFrames(state)
    if refreshPages then
        SkinSpecializationAndTalentPages(state)
    end
    RefreshThemeColors(state)
end

function PlayerSpellsSkin:QueueRefresh(frame, refreshPages)
    local state = self.activeState
    if not state or not state.active then
        return
    end
    if frame and frame ~= state.frame then
        return
    end

    if NS.IsCombatLocked() then
        state.pendingPageRefresh = state.pendingPageRefresh or refreshPages == true
        NS.CombatGate.RunOrDefer("playerSpells:refresh", function()
            local current = PlayerSpellsSkin.activeState
            if current and current.active then
                local includePages = current.pendingPageRefresh == true
                current.pendingPageRefresh = nil
                RefreshVisualState(current, includePages)
            end
        end)
        return
    end
    RefreshVisualState(state, refreshPages)
end

function PlayerSpellsSkin:OnFrameTabSet(frame)
    self:QueueRefresh(frame, true)
end

function PlayerSpellsSkin:OnDisplayedSpellsChanged()
    self:QueueRefresh()
end

function PlayerSpellsSkin:OnThemeChanged()
    local state = self.activeState
    if state and state.active and not NS.IsCombatLocked() then
        RefreshThemeColors(state)
    end
end

local function RegisterCallbacks()
    if PlayerSpellsSkin.callbacksRegistered or not EventRegistry then
        return
    end
    EventRegistry:RegisterCallback(CALLBACK_FRAME_TAB, PlayerSpellsSkin.OnFrameTabSet, PlayerSpellsSkin)
    EventRegistry:RegisterCallback(CALLBACK_DISPLAYED_SPELLS, PlayerSpellsSkin.OnDisplayedSpellsChanged, PlayerSpellsSkin)
    NS.Registry.AddListener(PlayerSpellsSkin, PlayerSpellsSkin.OnThemeChanged)
    PlayerSpellsSkin.callbacksRegistered = true
end

local function UnregisterCallbacks()
    if not PlayerSpellsSkin.callbacksRegistered then
        return
    end
    if EventRegistry then
        EventRegistry:UnregisterCallback(CALLBACK_FRAME_TAB, PlayerSpellsSkin)
        EventRegistry:UnregisterCallback(CALLBACK_DISPLAYED_SPELLS, PlayerSpellsSkin)
    end
    NS.Registry.RemoveListener(PlayerSpellsSkin)
    PlayerSpellsSkin.callbacksRegistered = false
end

local function RestoreState(state)
    state.active = false

    if NS.GenericWindows then
        NS.GenericWindows.Disable(state.owner)
    end
    state.pagesSkinned = nil
    NS.ControlSkin.DisableOwner(state.owner)

    for target in pairs(state.surfaces) do
        NS.Surface.SetVisible(target, false)
    end
    for glyph in pairs(state.glyphs) do
        if glyph and type(glyph.Hide) == "function" then
            glyph:Hide()
        end
    end
    for fontObject, color in pairs(state.textColors) do
        if fontObject and type(fontObject.SetTextColor) == "function" then
            local role = state.textRoles[fontObject]
            local current = role and { NS.Theme.GetColor(role) } or nil
            local ok, r, g, b, a = type(fontObject.GetTextColor) == "function"
                and pcall(fontObject.GetTextColor, fontObject)
            if ok and current
                and r == current[1] and g == current[2]
                and b == current[3] and (tonumber(a) or 1) == current[4] then
                fontObject:SetTextColor(color[1], color[2], color[3], color[4])
            end
        end
    end
    for texture, color in pairs(state.vertexColors) do
        if texture and type(texture.SetVertexColor) == "function" then
            local ok, r, g, b, a = type(texture.GetVertexColor) == "function"
                and pcall(texture.GetVertexColor, texture)
            if ok and r == 1 and g == 1 and b == 1 and (tonumber(a) or 1) == 0 then
                texture:SetVertexColor(color[1], color[2], color[3], color[4])
            end
        end
    end

    NS.Cosmetics.RestoreOwner(state.owner)
end

function PlayerSpellsSkin.Apply(frame, owner)
    frame = frame or _G.PlayerSpellsFrame
    owner = owner or "playerSpells"
    if not frame then
        return false, "missing"
    end
    if IsUnsafe(frame) then
        return false, "protected"
    end

    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("playerSpells:apply", function()
            PlayerSpellsSkin.Apply(_G.PlayerSpellsFrame or frame, owner)
        end)
        return false, "combat"
    end

    local state = GetState(frame, owner)
    state.active = true
    PlayerSpellsSkin.activeState = state

    if not SkinRootStatic(state) then
        state.active = false
        return false, "failed"
    end

    SkinSpecializationAndTalentPages(state)
    RegisterCallbacks()
    RefreshVisualState(state)
    return true
end

function PlayerSpellsSkin.Disable(frame, owner)
    frame = frame or (PlayerSpellsSkin.activeState and PlayerSpellsSkin.activeState.frame) or _G.PlayerSpellsFrame
    if not frame then
        return true
    end

    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("playerSpells:disable", function()
            PlayerSpellsSkin.Disable(frame, owner)
        end)
        return false, "combat"
    end

    local state = PlayerSpellsSkin.states[frame]
    if state then
        RestoreState(state)
    elseif owner then
        NS.Cosmetics.RestoreOwner(owner)
    end

    if PlayerSpellsSkin.activeState == state then
        PlayerSpellsSkin.activeState = nil
    end
    UnregisterCallbacks()
    return true
end

return PlayerSpellsSkin
