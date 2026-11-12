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

local function PublicField(target, key)
    local value = Field(target, key)
    if Safety.Public(value) then return value end
end

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
    if Kit.Ensure(state, preview, PREVIEW_SPEC) then
        Kit.FadeFields(state, preview, searchPreviewArt)
    end
end

local function SkinTab(state, tab)
    if not tab or not CanCreateRegions(tab) then
        return
    end
    Kit.SkinControl(state, tab, TAB_SPEC, "ApplyTab")
    local selected = PublicField(tab, "isSelected") == true
    NS.ControlSkin.Refresh(tab, selected)
    -- Blizzard changes the tab's FontObject whenever selection changes. Save
    -- that current native color before applying ours so Disable restores the
    -- latest selected/unselected state rather than the first state we saw.
    SetThemeTextColor(state, PublicField(tab, "Text"), selected and "accentBright" or "muted", true)
end

local function SkinTabSystem(state, tabSystem, unpreparedOnly)
    if not tabSystem or Safety.IsForbidden(tabSystem) then return end
    local tabs = PublicField(tabSystem, "tabs")
    if type(tabs) ~= "table" then
        return
    end
    for index = 1, #tabs do
        local tab = tabs[index]
        if Safety.Public(tab) and (not unpreparedOnly or not state.surfaces[tab]) then SkinTab(state, tab) end
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
    SuppressVertexAlpha(state, PublicField(header, "Backplate"))
    SuppressVertexAlpha(state, PublicField(header, "Border"))
    SkinRowText(state, PublicField(header, "Text"), "title")
end

local function SkinSpellItem(state, item, button, textContainer)
    Kit.Ensure(state, item, LIST_CARD_SPEC)

    -- Backplate alpha is changed by Blizzard on hover, so vertex alpha is used
    -- here instead of SetAlpha(0). The suppression survives those hover updates.
    SuppressVertexAlpha(state, PublicField(item, "Backplate"))

    if not Safety.IsForbidden(button) then
        Kit.Ensure(state, button, SPELL_BUTTON_SPEC)
        -- The per-region guard also applies to decorations of a protected button.
        SuppressVertexAlpha(state, PublicField(button, "Border"))
    end
    if Safety.IsForbidden(textContainer) then textContainer = nil end
    SkinRowText(state, PublicField(item, "Name") or PublicField(textContainer, "Name"), "text")
    SkinRowText(state, PublicField(item, "SubName") or PublicField(textContainer, "SubName"), "muted")
    SkinRowText(state, PublicField(item, "RequiredLevel") or PublicField(textContainer, "RequiredLevel"), "warning")
end

local function SkinDisplayedSpellFrames(state, book)
    if not book or Safety.IsForbidden(book) then return end
    local paged = PublicField(book, "PagedSpellsFrame")
    local frames = Safety.Read(paged, "GetFrames")
    if type(frames) ~= "table" then
        return
    end
    for index = 1, #frames do
        local element = frames[index]
        if Safety.Public(element) and element and not Safety.IsForbidden(element) then
            local button = PublicField(element, "Button")
            local text = PublicField(element, "TextContainer")
            if button and text then
                SkinSpellItem(state, element, button, text)
            elseif PublicField(element, "Backplate") and PublicField(element, "Text") then
                SkinHeader(state, element)
            end
        end
    end
end

local function SkinPagingControls(state, pagingControls)
    if not pagingControls or Safety.IsForbidden(pagingControls) then return end
    SkinRowText(state, PublicField(pagingControls, "PageText"), "muted")
    SkinGlyphButton(state, PublicField(pagingControls, "PrevPageButton"), "<", PREVIOUS_PAGE_SPEC)
    SkinGlyphButton(state, PublicField(pagingControls, "NextPageButton"), ">", NEXT_PAGE_SPEC)
end

-- Forever: Classic's "Show All Spell Ranks" option back on the page, as a
-- toggle chip in the theme's controls: a lit dot and the active fill while
-- on. It only flips Blizzard's own ShowAllSpellRanks setting. Refreshing the
-- list from here would taint the spell buttons, so Blizzard applies the
-- setting when the player switches spellbook tabs; the tooltip says so.
local RANKS_CVAR = "ShowAllSpellRanks"
local classesWithoutRanks = { ROGUE = true, WARRIOR = true }
local RANKS_SPEC = { role = "button", activeRole = "navigationActive", useControlShape = true, ownedArt = true }

local function SyncRanksToggle(button)
    local on = GetCVarBool(RANKS_CVAR) == true
    button.on = on
    NS.ControlSkin.Refresh(button, on)
    button.Text:SetTextColor(NS.Theme.GetColor(on and "accentBright" or "muted"))
    button.Dot:SetColorTexture(NS.Theme.GetColor(on and "accentBright" or "border"))
end

local function OnRanksToggleClick(button)
    SetCVar(RANKS_CVAR, button.on and "0" or "1")
    SyncRanksToggle(button)
end

local function OnRanksToggleEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip_SetTitle(GameTooltip, SHOW_ALL_SPELL_RANKS)
    GameTooltip_AddNormalLine(GameTooltip, NS.L["Takes effect when you switch spellbook tabs."], true)
    GameTooltip:Show()
end

local function CreateRanksToggle(spellBook, paged)
    local button = CreateFrame("Button")
    button:SetParent(spellBook)
    button:SetPoint("BOTTOMLEFT", paged, "BOTTOMLEFT", 80, 34)
    -- Above the pages and the book's skin surface, like Blizzard's paging controls.
    button:SetFrameLevel((Safety.Read(paged, "GetFrameLevel") or 1) + 10)
    button.Dot = button:CreateTexture(nil, "OVERLAY")
    button.Dot:SetSize(6, 6)
    button.Dot:SetPoint("LEFT", button, "LEFT", 11, 0)
    button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.Text:SetPoint("LEFT", button.Dot, "RIGHT", 8, 0)
    button.Text:SetText(SHOW_ALL_SPELL_RANKS)
    button:SetSize(math.ceil((Safety.Read(button.Text, "GetStringWidth") or 120) + 37), 24)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", OnRanksToggleClick)
    button:SetScript("OnShow", SyncRanksToggle)
    button:SetScript("OnEnter", OnRanksToggleEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

local function SkinRanksToggle(state, spellBook, paged)
    if not NS.Client.isForever or NS.Client.IsGamepadUI() then return end
    local _, classFile = UnitClass("player")
    -- A combat page repair only shows a toggle created before the fight.
    if classesWithoutRanks[classFile] or not state.ranksToggle and NS.IsCombatLocked() then return end
    state.ranksToggle = state.ranksToggle or CreateRanksToggle(spellBook, paged)
    Kit.SkinControl(state, state.ranksToggle, RANKS_SPEC)
    SyncRanksToggle(state.ranksToggle)
    state.ranksToggle:Show()
end

local function SkinSpellBookControls(state, spellBook)
    SkinTabSystem(state, PublicField(spellBook, "CategoryTabSystem"))
    Kit.SkinSearchBox(state, PublicField(spellBook, "SearchBox"))
    SkinSearchPreview(state, PublicField(spellBook, "SearchPreviewContainer"))

    local settingsDropdown = PublicField(spellBook, "SettingsDropdown")
    if settingsDropdown and CanCreateRegions(settingsDropdown) then
        Kit.Attach(state, settingsDropdown, DROPDOWN_SPEC)
    end

    -- The assisted-combat chip owns an explicitly secure spell button, so the
    -- entire chip stays untouched and no MapkoSkin region joins its tree.

    local paged = PublicField(spellBook, "PagedSpellsFrame")
    if paged and not Safety.IsForbidden(paged) then
        SkinPagingControls(state, PublicField(paged, "PagingControls"))
        SkinRanksToggle(state, spellBook, paged)
    end
end

local function SkinSpellBookStatic(state, spellBook)
    if not spellBook or Safety.IsForbidden(spellBook) then return end
    if Kit.Ensure(state, spellBook, SPELL_BOOK_SPEC) then Kit.FadeFields(state, spellBook, spellBookArt) end
    SkinSpellBookControls(state, spellBook)
end

-- Each page gets one generic traversal per apply; it is only walked while
-- shown so hidden pages keep their untouched native state until opened.
local function ApplyPageOnce(state, page, mode, requireShown)
    state.pagesSkinned = state.pagesSkinned or Kit.WeakSet()
    if state.pagesSkinned[page] then return true end
    if requireShown and Safety.Read(page, "IsShown") == false then
        -- Prepare the visible chrome without walking the hidden talent tree.
        return Kit.Ensure(state, page, PAGE_SHELL_SPEC)
    end
    if not NS.GenericWindows.ApplyFrame(page, state.owner, mode) then return false end
    state.pagesSkinned[page] = true
    return true
end

local function SkinTalentControls(state, page)
    SkinTabSystem(state, PublicField(page, "TabSystem"), true)
    local apply = PublicField(page, "ApplyButton")
    if apply and not state.surfaces[apply] then Kit.SkinControl(state, apply, WINDOW_BUTTON_SPEC) end
    local search = PublicField(page, "SearchBox")
    if search and not state.surfaces[search] then Kit.SkinSearchBox(state, search) end
    SkinSearchPreview(state, PublicField(page, "SearchPreviewContainer"))
end

local function SkinSpecializationAndTalentPages(state)
    local frame = state.frame
    if not frame then
        return
    end

    local specFrame = PublicField(frame, "SpecFrame")
    if CanCreateRegions(specFrame) and ApplyPageOnce(state, specFrame, PAGE_MODE, true) then
        Fade(state, specFrame.BlackBG)
        Fade(state, specFrame.Background)
    end

    local talentsFrame = PublicField(frame, "TalentsFrame")
    if CanCreateRegions(talentsFrame) and ApplyPageOnce(state, talentsFrame, TALENTS_MODE, true) then
        Kit.FadeFields(state, talentsFrame, talentsArt)
        if NS.Client.isForever then Kit.FadeFields(state, talentsFrame, foreverTalentsArt) end
        for index = 1, #talentsAnimatedArt do
            SuppressVertexAlpha(state, talentsFrame[talentsAnimatedArt[index]])
        end
    end
    if talentsFrame and not Safety.IsForbidden(talentsFrame) then
        SkinTalentControls(state, talentsFrame)
    end

    for index = 1, #talentDialogs do
        local dialog = _G[talentDialogs[index]]
        if dialog and CanCreateRegions(dialog) then
            ApplyPageOnce(state, dialog, DIALOG_MODE, false)
        end
    end
end

local function SkinRootControls(state)
    local frame = state.frame
    local title = PublicField(frame, "TitleContainer")
    if title and not Safety.IsForbidden(title) then
        SetThemeTextColor(state, PublicField(title, "TitleText"), "title")
    end
    SkinTabSystem(state, PublicField(frame, "TabSystem"))
    SkinGlyphButton(state, PublicField(frame, "CloseButton"), "X", WINDOW_BUTTON_SPEC)

    local maxMin = PublicField(frame, "MaximizeMinimizeButton")
    if maxMin and not Safety.IsForbidden(maxMin) then
        SkinGlyphButton(state, PublicField(maxMin, "MaximizeButton"), "+", WINDOW_BUTTON_SPEC)
        SkinGlyphButton(state, PublicField(maxMin, "MinimizeButton"), "-", WINDOW_BUTTON_SPEC)
    end
end

-- Blizzard's portrait overhangs the frame corner. Like the Legacy window's
-- emblem, a round copy sits inside the spell book's free top-left corner,
-- level with the category tabs, and follows every portrait change. It lives
-- on the spell book page, so the talents tab shows none. The native
-- portrait only fades; Blizzard keeps setting it.
local BADGE_SIZE, BADGE_MASK = 40, "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function SyncPortraitBadge(badge)
    local texture = Safety.Read(badge.portrait, "GetTexture")
    if texture == nil then return end
    badge.icon:SetTexture(texture)
    local left, top, x2, y2, x3, y3, right, bottom = Safety.Call(badge.portrait, "GetTexCoord")
    if Safety.Public(bottom) then badge.icon:SetTexCoord(left, top, x2, y2, x3, y3, right, bottom) end
end

local function CreatePortraitBadge(spellBook, portrait)
    local badge = Safety.CreateChildFrame("Frame", spellBook)
    local tabs = PublicField(spellBook, "CategoryTabSystem")
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    if tabs then
        badge:SetPoint("RIGHT", tabs, "LEFT", -14, 0)
    else
        badge:SetPoint("TOPLEFT", spellBook, "TOPLEFT", 16, -22)
    end
    badge:SetFrameLevel((Safety.Read(tabs, "GetFrameLevel") or Safety.Read(spellBook, "GetFrameLevel") or 1) + 1)
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetAllPoints(badge)
    if Safety.HasMethod(badge, "CreateMaskTexture") then
        local mask = badge:CreateMaskTexture()
        mask:SetTexture(BADGE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(badge)
        badge.icon:AddMaskTexture(mask)
    end
    badge.portrait = portrait
    local function Sync() if badge:IsShown() then SyncPortraitBadge(badge) end end
    Kit.HookFunction(portrait, "SetTexture", Sync)
    Kit.HookFunction(portrait, "SetTexCoord", Sync)
    return badge
end

local function SkinPortrait(state, frame)
    local portrait = PublicField(PublicField(frame, "PortraitContainer"), "portrait")
    local spellBook = PublicField(frame, "SpellBookFrame")
    if not portrait or Safety.IsForbidden(portrait) or not spellBook or Safety.IsForbidden(spellBook) then return end
    state.portraitBadge = state.portraitBadge or CreatePortraitBadge(spellBook, portrait)
    Fade(state, portrait)
    SyncPortraitBadge(state.portraitBadge)
    state.portraitBadge:Show()
    Kit.PortraitBezel(state.portraitBadge, state.portraitBadge, state.owner, 2)
end

local function SkinRootStatic(state, skipWindowControls)
    local frame = state.frame
    if not CanCreateRegions(frame) or not Kit.Attach(state, frame, SHELL_SPEC) then return false end
    Fade(state, frame.Bg)
    Fade(state, frame.TopTileStreaks)
    Kit.FadeNineSlice(state, frame.NineSlice)
    SkinRootControls(state)
    SkinPortrait(state, frame)
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
    SkinTabSystem(state, PublicField(state.frame, "TabSystem"))
    local book = PublicField(state.frame, "SpellBookFrame")
    if book and not Safety.IsForbidden(book) then
        SkinTabSystem(state, PublicField(book, "CategoryTabSystem"))
        SkinDisplayedSpellFrames(state, book)
    end
    if refreshPages then
        SkinSpecializationAndTalentPages(state)
        NS.WindowControls.Attach(state.frame, state.owner)
    end
    RefreshThemeColors(state)
end

local function RefreshPendingState()
    local current = PlayerSpellsSkin.activeState
    if current and current.active and current.pendingRefresh and not current.combatPrepared
        and Safety.Read(current.frame, "IsShown") ~= false then
        local includePages = current.pendingPageRefresh == true
        current.pendingRefresh, current.pendingPageRefresh = nil, nil
        RefreshVisualState(current, includePages)
    end
end

local function FadeVisibleArt(state, frame, fields)
    for index = 1, #fields do
        local region = PublicField(frame, fields[index])
        local alpha = Safety.Read(region, "GetAlpha")
        if type(alpha) == "number" and alpha > 0 then Fade(state, region) end
    end
end

-- Reuse a page's own replacement even when its outer window was protected
-- on first open. Native backgrounds stay visible when no replacement exists.
local function HasPageSurface(state, page)
    if not (state.surfaces[page] or state.pagesSkinned and state.pagesSkinned[page]) then return false end
    local surface = NS.Registry.GetSurface(page)
    return surface and Safety.Read(surface.fill, "IsShown") == true
end

local function ShownPage(frame, key)
    local page = PublicField(frame, key)
    if page and not Safety.IsForbidden(page) and not Kit.IsHidden(page) then return page end
end

local function RefreshCombatPage(state, book)
    if book then
        if HasPageSurface(state, book) then
            FadeVisibleArt(state, book, spellBookArt)
        else
            SkinSpellBookStatic(state, book)
        end
        return
    end

    local talents = ShownPage(state.frame, "TalentsFrame")
    if talents then
        if HasPageSurface(state, talents) or Kit.Ensure(state, talents, PAGE_SHELL_SPEC) then
            FadeVisibleArt(state, talents, talentsArt)
            if NS.Client.isForever then FadeVisibleArt(state, talents, foreverTalentsArt) end
            for index = 1, #talentsAnimatedArt do
                SuppressVertexAlpha(state, PublicField(talents, talentsAnimatedArt[index]))
            end
        end
        SkinTalentControls(state, talents)
        return
    end

    local spec = ShownPage(state.frame, "SpecFrame")
    if spec and (HasPageSurface(state, spec) or Kit.Ensure(state, spec, PAGE_SHELL_SPEC)) then
        Fade(state, PublicField(spec, "BlackBG"))
        Fade(state, PublicField(spec, "Background"))
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

    state.pendingRefresh = true
    state.pendingPageRefresh = state.pendingPageRefresh or refreshPages == true
    if Safety.Read(state.frame, "IsShown") == false then return end
    if NS.IsCombatLocked() or state.combatPrepared then
        local book = ShownPage(state.frame, "SpellBookFrame")
        if refreshPages then RefreshCombatPage(state, book) end
        if book then SkinDisplayedSpellFrames(state, book) end
        if not state.combatPrepared then NS.CombatGate.RunOrDefer("playerSpells:refresh", RefreshPendingState) end
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

local function Activate(state)
    state.active = true
    PlayerSpellsSkin.activeState = state
    if PlayerSpellsSkin.callbacksRegistered then return end
    EventRegistry:RegisterCallback(CALLBACK_FRAME_TAB, PlayerSpellsSkin.OnFrameTabSet, PlayerSpellsSkin)
    EventRegistry:RegisterCallback(CALLBACK_DISPLAYED_SPELLS,
        PlayerSpellsSkin.OnDisplayedSpellsChanged, PlayerSpellsSkin)
    NS.Registry.AddListener(PlayerSpellsSkin, PlayerSpellsSkin.OnThemeChanged)
    PlayerSpellsSkin.callbacksRegistered = true
end

local function PrepareCombatPages(state)
    if state.active then return end
    local frame = state.frame
    if type(PublicField(frame, "SpellBookFrame")) ~= "table" and type(PublicField(frame, "TalentsFrame")) ~= "table"
        and type(PublicField(frame, "SpecFrame")) ~= "table" then return end
    -- The deferred Apply owns the full pass. Start native page updates now,
    -- even if every enclosing frame is protected and only row art is safe.
    state.combatPrepared = true
    if not SkinRootStatic(state, true) then SkinRootControls(state) end
    Activate(state)
end

local function OnShown(frame)
    local state = PlayerSpellsSkin.states[frame]
    if state and state.windowControlsRequested and frame == Field(_G, "PlayerSpellsFrame")
        and NS.DB.enabled ~= false and NS.DB.skins.playerSpells ~= false then
        if NS.IsCombatLocked() then PrepareCombatPages(state) end
        if NS.WindowControls.Attach(frame, state.owner) then state.windowControlsRequested = nil end
    end
    if state and state.active and NS.IsCombatLocked() then
        if state.combatPrepared or state.pendingRefresh then
            PlayerSpellsSkin:QueueRefresh(frame, true)
        else
            RefreshCombatPage(state, ShownPage(frame, "SpellBookFrame"))
        end
    elseif state and state.pendingRefresh then
        PlayerSpellsSkin:QueueRefresh(frame)
    end
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
    if state.portraitBadge then state.portraitBadge:Hide() end
    Kit.HidePortraitBezels(state.owner)
    if state.ranksToggle then state.ranksToggle:Hide() end
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
    if not SkinRootStatic(state) then return false, "failed" end

    SkinSpellBookStatic(state, PublicField(frame, "SpellBookFrame"))
    SkinSpecializationAndTalentPages(state)
    state.combatPrepared = nil
    Activate(state)
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
