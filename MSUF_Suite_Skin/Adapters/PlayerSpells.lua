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
local PAGE_SHELL_SPEC = { role = "panel", radius = 8, inset = 0 }
local SPELL_BOOK_SPEC = { role = "panel", radius = 8, inset = 3 }
local PREVIEW_SPEC = { role = "popup", radius = 6, inset = 0 }
local LIST_CARD_SPEC = { role = "card", radius = 6, inset = 1, listItem = true }
local SPELL_BUTTON_SPEC = { role = "panel", radius = 6, inset = 1 }
local DROPDOWN_SPEC = { role = "button", shape = "round", radius = 6, inset = 2 }
local WINDOW_BUTTON_SPEC = { role = "button", shape = "round", radius = 6, inset = 2 }
local PREVIOUS_PAGE_SPEC = { role = "button", shape = "round", radius = 6, inset = 3 }
local NEXT_PAGE_SPEC = { role = "buttonPrimary", shape = "round", radius = 6, inset = 3 }
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
local foreverTalentsArt = { "ClassBackground", "BackgroundBorder" }
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
    return Safety.CanCreateRegions(frame, not NS.IsCombatLocked())
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
            textColors = Kit.NewTextColors(),
            vertexColors = Kit.WeakSet(),
        }
        PlayerSpellsSkin.states[frame] = state
    end
    return state
end

-- The kit's reversible text colors: with recapture, a native color Blizzard
-- painted since our last paint becomes the one restored on disable, while
-- our own color is never mistaken for it.
local function SetThemeTextColor(state, fontObject, colorKey, recapture)
    return Kit.SetTextColor(state.textColors, fontObject, colorKey, recapture)
end

local function SuppressVertexAlpha(state, texture)
    if not Safety.CanDecorate(texture, not NS.IsCombatLocked()) or not Safety.HasMethod(texture, "SetVertexColor") then
        return false
    end
    local r, g, b, a = Safety.ReadColor(texture, "GetVertexColor")
    if not r then return false end
    if a == 0 then return true end
    if not state.vertexColors[texture] then state.vertexColors[texture] = { r, g, b, a } end
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
    if NS.Checkmarks.GetWindowAction(button) then
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

local function SkinTabSystem(state, tabSystem, unpreparedOnly)
    local tabs = Field(tabSystem, "tabs")
    if type(tabs) ~= "table" then
        return
    end
    for index = 1, #tabs do
        local tab = tabs[index]
        if not unpreparedOnly or not state.surfaces[tab] then SkinTab(state, tab) end
    end
end

local function SkinRowText(state, text, role)
    if not Safety.Public(text) or not text then return end
    local colors = state.textColors
    if colors.roles[text] == role and Kit.ShowsTextColor(colors, text, Safety.ReadColor(text, "GetTextColor")) then
        return
    end
    SetThemeTextColor(state, text, role, true)
end

local function SkinHeader(state, header)
    Kit.Ensure(state, header, LIST_CARD_SPEC)
    SuppressVertexAlpha(state, header.Backplate)
    SuppressVertexAlpha(state, header.Border)
    SkinRowText(state, header.Text, "title")
end

local function SkinSpellItem(state, item)
    Kit.Ensure(state, item, LIST_CARD_SPEC)

    -- Backplate alpha is changed by Blizzard on hover, so vertex alpha is used
    -- here instead of SetAlpha(0). The suppression survives those hover updates.
    SuppressVertexAlpha(state, item.Backplate)

    local button = item.Button
    Kit.Ensure(state, button, SPELL_BUTTON_SPEC)
    -- The icon border is a decoration even if the native spell button is
    -- protected. The per-region guard decides whether it can be painted.
    SuppressVertexAlpha(state, Field(button, "Border"))

    local textContainer = item.TextContainer
    SkinRowText(state, item.Name or Field(textContainer, "Name"), "text")
    SkinRowText(state, item.SubName or Field(textContainer, "SubName"), "muted")
    SkinRowText(state, item.RequiredLevel or Field(textContainer, "RequiredLevel"), "warning")
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

    if not Kit.Attach(state, spellBook, SPELL_BOOK_SPEC) then return end
    Kit.FadeFields(state, spellBook, spellBookArt)
    SkinTabSystem(state, spellBook.CategoryTabSystem)
    Kit.SkinSearchBox(state, spellBook.SearchBox)
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
local function ApplyPageOnce(state, page, mode, requireShown, shellOnly)
    state.pagesSkinned = state.pagesSkinned or Kit.WeakSet()
    if state.pagesSkinned[page] then return true end
    if shellOnly or requireShown and Safety.Read(page, "IsShown") == false then
        -- Prepare the visible chrome without walking the hidden talent tree.
        return Kit.Ensure(state, page, PAGE_SHELL_SPEC)
    end
    if not NS.GenericWindows.ApplyFrame(page, state.owner, mode) then return false end
    state.pagesSkinned[page] = true
    return true
end

local function SkinTalentControls(state, page)
    SkinTabSystem(state, Field(page, "TabSystem"), true)
    local apply = Field(page, "ApplyButton")
    if apply and not state.surfaces[apply] then Kit.SkinControl(state, apply, WINDOW_BUTTON_SPEC) end
end

local function SkinSpecializationAndTalentPages(state, shellOnly)
    local frame = state.frame
    if not frame then
        return
    end

    local specFrame = frame.SpecFrame
    if CanCreateRegions(specFrame) and ApplyPageOnce(state, specFrame, PAGE_MODE, true, shellOnly) then
        Fade(state, specFrame.BlackBG)
        Fade(state, specFrame.Background)
    end

    local talentsFrame = frame.TalentsFrame
    if CanCreateRegions(talentsFrame) and ApplyPageOnce(state, talentsFrame, TALENTS_MODE, true, shellOnly) then
        Kit.FadeFields(state, talentsFrame, talentsArt)
        if NS.Client.isForever then Kit.FadeFields(state, talentsFrame, foreverTalentsArt) end
        for index = 1, #talentsAnimatedArt do
            SuppressVertexAlpha(state, talentsFrame[talentsAnimatedArt[index]])
        end
        Kit.SkinSearchBox(state, talentsFrame.SearchBox)
        SkinSearchPreview(state, talentsFrame.SearchPreviewContainer)
        if shellOnly and NS.Client.isForever and Safety.Read(talentsFrame, "IsShown") then
            SkinTalentControls(state, talentsFrame)
        end
    end

    for index = 1, #talentDialogs do
        local dialog = _G[talentDialogs[index]]
        if dialog and CanCreateRegions(dialog) then
            if not shellOnly then ApplyPageOnce(state, dialog, DIALOG_MODE, false) end
        end
    end
end

local function SkinRootControls(state)
    local frame = state.frame
    SetThemeTextColor(state, Kit.Path(frame, "TitleContainer", "TitleText"), "title")
    SkinTabSystem(state, frame.TabSystem)
    SkinGlyphButton(state, frame.CloseButton, "X", WINDOW_BUTTON_SPEC)

    local maxMin = frame.MaximizeMinimizeButton
    if maxMin then
        SkinGlyphButton(state, maxMin.MaximizeButton, "+", WINDOW_BUTTON_SPEC)
        SkinGlyphButton(state, maxMin.MinimizeButton, "-", WINDOW_BUTTON_SPEC)
    end
end

local function SkinRootStatic(state, skipWindowControls)
    local frame = state.frame
    if not CanCreateRegions(frame) or not Kit.Attach(state, frame, SHELL_SPEC) then return false end
    Fade(state, frame.Bg)
    Fade(state, frame.TopTileStreaks)
    Kit.FadeNineSlice(state, frame.NineSlice)
    SkinRootControls(state)
    SkinSpellBookStatic(state, frame.SpellBookFrame)
    if not skipWindowControls then NS.WindowControls.Attach(frame, state.owner) end
    return true
end

local function RefreshThemeColors(state)
    Kit.RefreshTextColors(state.textColors)
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
        NS.WindowControls.Attach(state.frame, state.owner)
    end
    RefreshThemeColors(state)
end

local function RefreshPendingState()
    local current = PlayerSpellsSkin.activeState
    if current and current.active and current.pendingRefresh and Safety.Read(current.frame, "IsShown") ~= false then
        local includePages = current.pendingPageRefresh == true
        current.pendingRefresh, current.pendingPageRefresh = nil, nil
        RefreshVisualState(current, includePages)
    end
end

local function FadeVisibleArt(state, frame, fields)
    for index = 1, #fields do
        local region = Field(frame, fields[index])
        local alpha = Safety.Read(region, "GetAlpha")
        if type(alpha) == "number" and alpha > 0 then Fade(state, region) end
    end
end

-- An already painted shell stays valid when the native root becomes
-- protected. Restore only its visible decorative art, not its layout or
-- surface, after Blizzard selects or opens a page.
local function ReconcilePreparedPage(state)
    local frame = state.frame
    local shell = NS.Registry.GetSurface(frame)
    if not shell or not state.surfaces[frame] or not Safety.Read(shell.fill, "IsShown") then return false end
    local book = Field(frame, "SpellBookFrame")
    if state.surfaces[book] and Safety.Read(book, "IsShown") then
        FadeVisibleArt(state, book, spellBookArt)
        return true
    end
    local talents = Field(frame, "TalentsFrame")
    local hasTalentSurface = state.surfaces[talents] or state.pagesSkinned and state.pagesSkinned[talents]
    if hasTalentSurface and Safety.Read(talents, "IsShown") then
        FadeVisibleArt(state, talents, talentsArt)
        FadeVisibleArt(state, talents, foreverTalentsArt)
        SkinTalentControls(state, talents)
        return true
    end
    return false
end

function PlayerSpellsSkin:QueueRefresh(frame, refreshPages)
    local state = self.activeState
    if not state or not state.active then
        return
    end
    if frame and frame ~= state.frame then
        return
    end

    state.pendingRefresh = true
    state.pendingPageRefresh = state.pendingPageRefresh or refreshPages == true
    if Safety.Read(state.frame, "IsShown") == false then return end
    if NS.IsCombatLocked() then
        if NS.Client.isForever then
            local book = Field(state.frame, "SpellBookFrame")
            if book and not Kit.IsHidden(book) then SkinDisplayedSpellFrames(state) end
        end
        if refreshPages and not (NS.Client.isForever and ReconcilePreparedPage(state)) then
            SkinSpecializationAndTalentPages(state, true)
        end
        NS.CombatGate.RunOrDefer("playerSpells:refresh", RefreshPendingState)
        return
    end
    RefreshPendingState()
end

function PlayerSpellsSkin:OnFrameTabSet(frame)
    self:QueueRefresh(frame, true)
end

function PlayerSpellsSkin:OnDisplayedSpellsChanged()
    self:QueueRefresh()
end

local function PrepareCombatPages(state)
    if state.active or state.combatPrepared then return end
    local frame = state.frame
    local book = Field(frame, "SpellBookFrame")
    if not (CanCreateRegions(book) or CanCreateRegions(Field(frame, "TalentsFrame"))
        or CanCreateRegions(Field(frame, "SpecFrame"))) then return end
    state.combatPrepared = true
    local rootPainted = SkinRootStatic(state, true)
    if not rootPainted then SkinSpellBookStatic(state, book) end
    SkinSpecializationAndTalentPages(state, true)
    local talents = Field(frame, "TalentsFrame")
    local page = Safety.Read(talents, "IsShown") and talents or Safety.Read(book, "IsShown") and book
    if not rootPainted and NS.Client.isForever and page and state.surfaces[page] then
        SkinRootControls(state)
    end
end

local function OnShown(frame)
    local state = PlayerSpellsSkin.states[frame]
    if state and state.windowControlsRequested and frame == Field(_G, "PlayerSpellsFrame")
        and NS.DB.enabled ~= false and NS.DB.skins.playerSpells ~= false then
        if NS.IsCombatLocked() then PrepareCombatPages(state) end
        if NS.WindowControls.Attach(frame, state.owner) then state.windowControlsRequested = nil end
    end
    if state and state.active and NS.Client.isForever and NS.IsCombatLocked() then ReconcilePreparedPage(state) end
    if state and state.pendingRefresh then PlayerSpellsSkin:QueueRefresh(frame) end
end

-- Load-on-demand can finish before Blizzard shows the root. Keep that one
-- native show callback ready; geometry guards still reject protected combat roots.
function PlayerSpellsSkin.AttachWindowControls(frame, owner)
    if not frame or frame ~= Field(_G, "PlayerSpellsFrame") or Safety.IsForbidden(frame) then return false end
    local state = GetState(frame, owner or "playerSpells")
    state.windowControlsRequested = true
    if not state.showHooked then
        frame:HookScript("OnShow", Safety.Isolated(OnShown))
        state.showHooked = true
    end
    if Safety.Read(frame, "IsShown") then OnShown(frame) end
    if not state.windowControlsRequested then return true end
    return false
end

local function RefreshActiveColors()
    local state = PlayerSpellsSkin.activeState
    if state and state.active and not NS.IsCombatLocked() then
        if Safety.Read(state.frame, "IsShown") == false then
            state.pendingRefresh = true
        else
            RefreshThemeColors(state)
        end
    end
end

-- Once per frame of settings writes.
function PlayerSpellsSkin:OnThemeChanged()
    NS.Registry.QueueJob(RefreshActiveColors)
end

local function RegisterCallbacks()
    if PlayerSpellsSkin.callbacksRegistered then
        return
    end
    EventRegistry:RegisterCallback(CALLBACK_FRAME_TAB, PlayerSpellsSkin.OnFrameTabSet, PlayerSpellsSkin)
    EventRegistry:RegisterCallback(CALLBACK_DISPLAYED_SPELLS,
        PlayerSpellsSkin.OnDisplayedSpellsChanged, PlayerSpellsSkin)
    NS.Registry.AddListener(PlayerSpellsSkin, PlayerSpellsSkin.OnThemeChanged)
    PlayerSpellsSkin.callbacksRegistered = true
end

local function UnregisterCallbacks()
    if not PlayerSpellsSkin.callbacksRegistered then
        return
    end
    EventRegistry:UnregisterCallback(CALLBACK_FRAME_TAB, PlayerSpellsSkin)
    EventRegistry:UnregisterCallback(CALLBACK_DISPLAYED_SPELLS, PlayerSpellsSkin)
    NS.Registry.RemoveListener(PlayerSpellsSkin)
    PlayerSpellsSkin.callbacksRegistered = false
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
    state.combatPrepared = nil
    state.pendingRefresh, state.pendingPageRefresh = nil, nil
    NS.GenericWindows.Disable(state.owner)
    state.pagesSkinned = nil
    NS.ControlSkin.DisableOwner(state.owner)
    Kit.HideSurfaces(state)
    state.surfaces = Kit.WeakSet()
    for glyph in pairs(state.glyphs) do
        glyph:Hide()
    end
    -- A native color comes back only while our themed color is still shown.
    Kit.RestoreTextColors(state.textColors)
    RestoreVertexColors(state)
    NS.Cosmetics.RestoreOwner(state.owner)
end

function PlayerSpellsSkin.Apply(frame, owner)
    frame = frame or _G.PlayerSpellsFrame
    owner = owner or "playerSpells"
    if not frame then
        return false, "missing"
    end
    NS.WindowControls.TrackFocus(frame, owner)
    if NS.IsCombatLocked() then
        PlayerSpellsSkin.AttachWindowControls(frame, owner)
        NS.CombatGate.RunOrDefer("playerSpells:apply", function()
            PlayerSpellsSkin.Apply(_G.PlayerSpellsFrame or frame, owner)
        end)
        return false, "combat"
    end
    if not CanCreateRegions(frame) then return false, "protected" end

    local state = GetState(frame, owner)
    state.active = true
    PlayerSpellsSkin.activeState = state

    if not SkinRootStatic(state) then
        state.active = false
        return false, "failed"
    end

    SkinSpecializationAndTalentPages(state)
    RegisterCallbacks()
    if not state.showHooked then
        frame:HookScript("OnShow", Safety.Isolated(OnShown))
        state.showHooked = true
    end
    PlayerSpellsSkin:QueueRefresh(frame)
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
        state.windowControlsRequested = nil
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
