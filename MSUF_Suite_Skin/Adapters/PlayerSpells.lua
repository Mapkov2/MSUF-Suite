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

local Safety = NS.Safety
local Field = Safety.Field
local Kit = NS.AdapterKit
local Fade = Kit.Fade

local CALLBACK_FRAME_TAB = "PlayerSpellsFrame.TabSet"
local CALLBACK_DISPLAYED_SPELLS = "PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged"

local SHELL_SPEC = { role = "shell", radius = 8, inset = 0 }
local SPELL_BOOK_SPEC = { role = "panel", radius = 8, inset = 3 }
local PREVIEW_SPEC = { role = "popup", radius = 6, inset = 0 }
local LIST_CARD_SPEC = { role = "card", radius = 6, inset = 1, listItem = true }
local SPELL_BUTTON_SPEC = { role = "panel", radius = 6, inset = 1 }
local DROPDOWN_SPEC = { role = "button", shape = "round", radius = 6, inset = 2 }
local WINDOW_BUTTON_SPEC = { role = "button", shape = "round", radius = 6, inset = 2 }
local PREVIOUS_PAGE_SPEC = { role = "button", shape = "round", radius = 6, inset = 3 }
local NEXT_PAGE_SPEC = { role = "buttonPrimary", shape = "round", radius = 6, inset = 3 }
local SEARCH_SPEC = {
    role = "input",
    useControlShape = true,
    pillHeight = 28,
    inset = 1,
}
local TAB_SPEC = {
    role = "navigation",
    activeRole = "navigationActive",
    useControlShape = true,
    pillHeight = 32,
    inset = 1,
}

local PAGE_MODE = {
    role = "panel",
    radius = 8,
    maxDepth = 7,
    maxNodes = 480,
    allowImplicitProtected = true,
}
local TALENTS_MODE = {
    role = "panel",
    radius = 8,
    maxDepth = 7,
    maxNodes = 600,
    allowImplicitProtected = true,
}
local DIALOG_MODE = {
    role = "popup",
    radius = 8,
    maxDepth = 7,
    maxNodes = 480,
    allowImplicitProtected = true,
}

local buttonTextureGetters = {
    "GetNormalTexture",
    "GetPushedTexture",
    "GetDisabledTexture",
    "GetHighlightTexture",
}
local searchPreviewArt = {
    "Background", "BorderAnchor", "BotRightCorner",
    "BottomBorder", "LeftBorder", "RightBorder",
}
local spellBookArt = {
    "TopBar", "BookBGHalved", "BookBGLeft", "BookBGRight",
    "BookCornerFlipbook", "Bookmark",
}
local talentsArt = { "BlackBG", "BottomBar", "Background" }
-- Blizzard animates the region alpha of these textures. A zero vertex alpha
-- remains suppressed without touching animation state.
local talentsAnimatedArt = {
    "BackgroundFlash", "OverlayBackgroundRight", "OverlayBackgroundMid",
    "Clouds1", "Clouds2", "AirParticlesClose", "AirParticlesFar",
}
local talentDialogs = {
    "ClassTalentLoadoutCreateDialog",
    "ClassTalentLoadoutEditDialog",
    "ClassTalentLoadoutImportDialog",
    "HeroTalentsSelectionDialog",
}

local function CanCreateRegions(frame)
    return Safety.CanCreateRegions(frame, true)
end

local function GetState(frame, owner)
    local state = PlayerSpellsSkin.states[frame]
    if not state then
        state = {
            frame = frame,
            owner = owner,
            active = false,
            surfaces = Kit.WeakSet(),
            glyphs = Kit.WeakSet(),
            buttonGlyphs = Kit.WeakSet(),
            textColors = Kit.WeakSet(),
            textRoles = Kit.WeakSet(),
            vertexColors = Kit.WeakSet(),
        }
        PlayerSpellsSkin.states[frame] = state
    end
    return state
end

local function SetThemeTextColor(state, fontObject, colorKey, recapture)
    if type((Field(fontObject, "SetTextColor"))) ~= "function" then
        return false
    end
    if recapture or not state.textColors[fontObject] then
        local r, g, b, a = Safety.ReadColor(fontObject, "GetTextColor")
        if r then
            state.textColors[fontObject] = { r, g, b, a }
        end
    end
    state.textRoles[fontObject] = colorKey
    fontObject:SetTextColor(NS.Theme.GetColor(colorKey))
    return true
end

local function SuppressVertexAlpha(state, texture)
    if type((Field(texture, "SetVertexColor"))) ~= "function" then
        return false
    end
    if not state.vertexColors[texture] then
        local r, g, b, a = Safety.ReadColor(texture, "GetVertexColor")
        if r then
            state.vertexColors[texture] = { r, g, b, a }
        end
    end
    texture:SetVertexColor(1, 1, 1, 0)
    return true
end

local function FadeButtonTextures(state, button)
    if not button or not CanCreateRegions(button) then
        return false
    end
    for index = 1, #buttonTextureGetters do
        Fade(state, (Safety.Call(button, buttonTextureGetters[index])))
    end
    return true
end

local function AddButtonGlyph(state, button, text, colorKey)
    local glyph = state.buttonGlyphs[button]
    if not glyph then
        glyph = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        glyph:SetPoint("CENTER", button, "CENTER", 0, 0)
        state.buttonGlyphs[button] = glyph
    end
    state.glyphs[glyph] = colorKey
    glyph:SetText(text)
    glyph:SetTextColor(NS.Theme.GetColor(colorKey))
    glyph:Show()
    return glyph
end

local function SkinGlyphButton(state, button, glyphText, spec)
    if not button or not CanCreateRegions(button) then
        return false
    end
    if NS.Checkmarks and NS.Checkmarks.GetWindowAction(button) then
        return Kit.SkinControl(state, button, spec)
    end
    if not Kit.Attach(state, button, spec) then
        return false
    end
    FadeButtonTextures(state, button)
    AddButtonGlyph(state, button, glyphText,
        glyphText == "X" and "blizzardClose" or "accentBright")
    return true
end

local function SkinSearchBox(state, searchBox)
    if not searchBox or not CanCreateRegions(searchBox) then
        return
    end
    Kit.SkinControl(state, searchBox, SEARCH_SPEC, "ApplySearchBox")
    SetThemeTextColor(state, searchBox, "text")
    SetThemeTextColor(state, Field(searchBox, "Instructions"), "muted")
end

local function SkinSearchPreview(state, preview)
    if not preview or not CanCreateRegions(preview) then
        return
    end
    Kit.Attach(state, preview, PREVIEW_SPEC)
    Kit.FadeFields(state, preview, searchPreviewArt)
end

local function SkinTab(state, tab)
    if not tab or not CanCreateRegions(tab) then
        return
    end
    Kit.SkinControl(state, tab, TAB_SPEC, "ApplyTab")
    local selected = Field(tab, "isSelected") == true
    NS.ControlSkin.Refresh(tab, selected)
    -- Blizzard changes the tab's FontObject whenever selection changes. Save
    -- that current native color before applying ours so Disable restores the
    -- latest selected/unselected state rather than the first state we saw.
    SetThemeTextColor(state, Field(tab, "Text"), selected and "accentBright" or "muted", true)
end

local function SkinTabSystem(state, tabSystem)
    local tabs = Field(tabSystem, "tabs")
    if type(tabs) ~= "table" then
        return
    end
    for index = 1, #tabs do
        SkinTab(state, tabs[index])
    end
end

local function SkinHeader(state, header)
    Kit.Attach(state, header, LIST_CARD_SPEC)
    SuppressVertexAlpha(state, header.Backplate)
    SuppressVertexAlpha(state, header.Border)
    SetThemeTextColor(state, header.Text, "title")
end

local function SkinSpellItem(state, item)
    Kit.Attach(state, item, LIST_CARD_SPEC)

    -- Backplate alpha is changed by Blizzard on hover, so vertex alpha is used
    -- here instead of SetAlpha(0). The suppression survives those hover updates.
    SuppressVertexAlpha(state, item.Backplate)

    local button = item.Button
    if button and CanCreateRegions(button) then
        Kit.Attach(state, button, SPELL_BUTTON_SPEC)
        SuppressVertexAlpha(state, button.Border)
    end

    local textContainer = item.TextContainer
    SetThemeTextColor(state, item.Name or Field(textContainer, "Name"), "text")
    SetThemeTextColor(state, item.SubName or Field(textContainer, "SubName"), "muted")
    SetThemeTextColor(state, item.RequiredLevel or Field(textContainer, "RequiredLevel"), "warning")
end

local function SkinDisplayedSpellFrames(state)
    local paged = Kit.Path(state.frame, "SpellBookFrame", "PagedSpellsFrame")
    local frames = type((Field(paged, "GetFrames"))) == "function" and paged:GetFrames() or nil
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
    SkinGlyphButton(state, pagingControls.PrevPageButton, "<", PREVIOUS_PAGE_SPEC)
    SkinGlyphButton(state, pagingControls.NextPageButton, ">", NEXT_PAGE_SPEC)
end

local function SkinSpellBookStatic(state, spellBook)
    if not spellBook or not CanCreateRegions(spellBook) then
        return
    end

    Kit.Attach(state, spellBook, SPELL_BOOK_SPEC)
    Kit.FadeFields(state, spellBook, spellBookArt)
    SkinTabSystem(state, spellBook.CategoryTabSystem)
    SkinSearchBox(state, spellBook.SearchBox)
    SkinSearchPreview(state, spellBook.SearchPreviewContainer)

    local settingsDropdown = spellBook.SettingsDropdown
    if settingsDropdown and CanCreateRegions(settingsDropdown) then
        Kit.Attach(state, settingsDropdown, DROPDOWN_SPEC)
    end

    -- The assisted-combat chip owns an explicitly secure spell button, so the
    -- entire chip stays untouched and no MapkoSkin region joins its tree.

    SkinPagingControls(state, Field(spellBook.PagedSpellsFrame, "PagingControls"))
end

-- Each page gets one generic traversal per apply; it is only walked while
-- shown so hidden pages keep their untouched native state until opened.
local function ApplyPageOnce(state, page, mode, requireShown)
    if requireShown and Safety.Read(page, "IsShown") == false then return end
    state.pagesSkinned = state.pagesSkinned or Kit.WeakSet()
    if state.pagesSkinned[page] then return end
    NS.GenericWindows.ApplyFrame(page, state.owner, mode)
    state.pagesSkinned[page] = true
end

local function SkinSpecializationAndTalentPages(state)
    local frame = state.frame
    if not frame then
        return
    end

    local specFrame = frame.SpecFrame
    if specFrame and CanCreateRegions(specFrame) then
        -- Suppress the opaque native layer before attaching; the surface is
        -- then created after it and remains the visible full-frame base.
        Fade(state, specFrame.BlackBG)
        Fade(state, specFrame.Background)
        ApplyPageOnce(state, specFrame, PAGE_MODE, true)
    end

    local talentsFrame = frame.TalentsFrame
    if talentsFrame and CanCreateRegions(talentsFrame) then
        Kit.FadeFields(state, talentsFrame, talentsArt)
        for index = 1, #talentsAnimatedArt do
            SuppressVertexAlpha(state, talentsFrame[talentsAnimatedArt[index]])
        end
        ApplyPageOnce(state, talentsFrame, TALENTS_MODE, true)
        SkinSearchBox(state, talentsFrame.SearchBox)
        SkinSearchPreview(state, talentsFrame.SearchPreviewContainer)
    end

    for index = 1, #talentDialogs do
        local dialog = _G[talentDialogs[index]]
        if dialog and CanCreateRegions(dialog) then
            ApplyPageOnce(state, dialog, DIALOG_MODE, false)
        end
    end
end

local function SkinRootStatic(state)
    local frame = state.frame
    if not frame or not CanCreateRegions(frame) then
        return false
    end

    Kit.Attach(state, frame, SHELL_SPEC)
    Fade(state, frame.Bg)
    Fade(state, frame.TopTileStreaks)
    Kit.FadeNineSlice(state, frame.NineSlice)

    SetThemeTextColor(state, Kit.Path(frame, "TitleContainer", "TitleText"), "title")
    SkinTabSystem(state, frame.TabSystem)
    SkinGlyphButton(state, frame.CloseButton, "X", WINDOW_BUTTON_SPEC)

    local maxMin = frame.MaximizeMinimizeButton
    if maxMin then
        SkinGlyphButton(state, maxMin.MaximizeButton, "+", WINDOW_BUTTON_SPEC)
        SkinGlyphButton(state, maxMin.MinimizeButton, "-", WINDOW_BUTTON_SPEC)
    end

    SkinSpellBookStatic(state, frame.SpellBookFrame)
    return true
end

local function RefreshThemeColors(state)
    for fontObject, colorKey in pairs(state.textRoles) do
        fontObject:SetTextColor(NS.Theme.GetColor(colorKey))
    end
    for glyph, colorKey in pairs(state.glyphs) do
        glyph:SetTextColor(NS.Theme.GetColor(colorKey))
    end
end

local function RefreshVisualState(state, refreshPages)
    if not state or not state.active then
        return
    end
    SkinTabSystem(state, state.frame.TabSystem)
    SkinTabSystem(state, Field(state.frame.SpellBookFrame, "CategoryTabSystem"))
    SkinDisplayedSpellFrames(state)
    if refreshPages then
        SkinSpecializationAndTalentPages(state)
    end
    RefreshThemeColors(state)
end

local function RefreshPendingState()
    local current = PlayerSpellsSkin.activeState
    if current and current.active then
        local includePages = current.pendingPageRefresh == true
        current.pendingPageRefresh = nil
        RefreshVisualState(current, includePages)
    end
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
        NS.CombatGate.RunOrDefer("playerSpells:refresh", RefreshPendingState)
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
    if PlayerSpellsSkin.callbacksRegistered then
        return
    end
    if Kit.RegisterEventCallback(CALLBACK_FRAME_TAB, PlayerSpellsSkin.OnFrameTabSet, PlayerSpellsSkin) then
        Kit.RegisterEventCallback(CALLBACK_DISPLAYED_SPELLS,
            PlayerSpellsSkin.OnDisplayedSpellsChanged, PlayerSpellsSkin)
        NS.Registry.AddListener(PlayerSpellsSkin, PlayerSpellsSkin.OnThemeChanged)
        PlayerSpellsSkin.callbacksRegistered = true
    end
end

local function UnregisterCallbacks()
    if not PlayerSpellsSkin.callbacksRegistered then
        return
    end
    Kit.UnregisterEventCallback(CALLBACK_FRAME_TAB, PlayerSpellsSkin)
    Kit.UnregisterEventCallback(CALLBACK_DISPLAYED_SPELLS, PlayerSpellsSkin)
    NS.Registry.RemoveListener(PlayerSpellsSkin)
    PlayerSpellsSkin.callbacksRegistered = false
end

-- Restores a native color only while our themed color is still installed.
local function RestoreTextColors(state)
    for fontObject, color in pairs(state.textColors) do
        local role = state.textRoles[fontObject]
        if role then
            local r, g, b, a = Safety.ReadColor(fontObject, "GetTextColor")
            local themeR, themeG, themeB, themeA = NS.Theme.GetColor(role)
            if r and r == themeR and g == themeG and b == themeB and a == themeA then
                fontObject:SetTextColor(color[1], color[2], color[3], color[4])
            end
        end
    end
end

local function RestoreVertexColors(state)
    for texture, color in pairs(state.vertexColors) do
        local r, g, b, a = Safety.ReadColor(texture, "GetVertexColor")
        if r == 1 and g == 1 and b == 1 and a == 0 then
            texture:SetVertexColor(color[1], color[2], color[3], color[4])
        end
    end
end

local function RestoreState(state)
    state.active = false
    NS.GenericWindows.Disable(state.owner)
    state.pagesSkinned = nil
    NS.ControlSkin.DisableOwner(state.owner)
    Kit.HideSurfaces(state)
    for glyph in pairs(state.glyphs) do
        glyph:Hide()
    end
    RestoreTextColors(state)
    RestoreVertexColors(state)
    NS.Cosmetics.RestoreOwner(state.owner)
end

function PlayerSpellsSkin.Apply(frame, owner)
    frame = frame or _G.PlayerSpellsFrame
    owner = owner or "playerSpells"
    if not frame then
        return false, "missing"
    end
    if not CanCreateRegions(frame) then
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
    frame = frame or (PlayerSpellsSkin.activeState and PlayerSpellsSkin.activeState.frame)
        or _G.PlayerSpellsFrame
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
