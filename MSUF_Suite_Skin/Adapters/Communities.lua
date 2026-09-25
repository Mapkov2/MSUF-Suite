local _, NS = ...

-- Exact clean-room skin for Blizzard_Communities. The generic engine cannot
-- identify this addon's anonymous GuildFrame/TrainerTextures parchment or its
-- pooled guild perk, reward and news rows. This adapter uses only verified
-- parentKey paths and public CallbackRegistry/ScrollBox callbacks.
local CommunitiesSkin = {
    states = setmetatable({}, { __mode = "k" }),
    columnDisplayHooks = setmetatable({}, { __mode = "k" }),
}
NS.CommunitiesSkin = CommunitiesSkin

local Safety = NS.Safety
local Field = Safety.Field
local Kit = NS.AdapterKit
local Path = Kit.Path
local Fade = Kit.Fade
local FadeNineSlice = Kit.FadeNineSlice

local COLUMN_HEADER_LIMIT = 16

local SHELL_SPEC = { role = "shell", radius = 8, inset = 0 }
local POPUP_SPEC = { role = "popup", radius = 8, inset = 0 }
local PANEL_SPEC = { role = "panel", radius = 6, inset = 0 }
local NAVIGATION_SPEC = { role = "navigation", radius = 6, inset = 0, keepGlassFill = false }
local CARD_SPEC = { role = "card", radius = 6, inset = 0, keepGlassFill = false }
local STATUS_SPEC = { role = "status", radius = 4, inset = 1 }
local NOTE_SPEC = { role = "input", radius = 5, inset = 0 }

local PANEL_BUTTON_SPEC = {
    role = "button",
    activeRole = "buttonPrimary",
    pillHeight = 20,
    inset = 1,
    regions = { "Left", "Middle", "Right" },
}
local COMMUNITY_ROW_SPEC = {
    role = "navigation",
    activeRole = "navigationActive",
    radius = 6,
    inset = 2,
    pillHeight = 64,
    regions = { "Background", "Selection", "NewCommunityFlash" },
}
local PERK_ROW_SPEC = {
    role = "card", radius = 4, inset = 1, pillHeight = 40,
    keepGlassFill = false,
    regions = { "Left", "Right" },
}
local REWARD_ROW_SPEC = {
    role = "card", radius = 4, inset = 1, pillHeight = 44,
    keepGlassFill = false,
    regions = { "DisabledBG" },
}
local NEWS_ROW_SPEC = {
    role = "card", radius = 4, inset = 1, pillHeight = 18,
    listItem = true,
    regions = { "header" },
}
local TAB_SPEC = {
    role = "navigation", activeRole = "navigationActive",
    shape = "round", radius = 6, inset = 1,
}

local CONTROL_TREE_OPTIONS = { maxDepth = 8, maxNodes = 720 }
local COLUMN_HEADER_ART = { "Left", "Middle", "Right" }
local COLUMN_DISPLAY_ART = {
    "Background", "TopTileStreaks", "InsetBorderTopLeft",
    "InsetBorderTopRight", "InsetBorderBottomLeft", "InsetBorderTop",
    "InsetBorderLeft",
}
local GUILD_PANEL_BORDERS = {
    "InsetBorderTopLeft", "InsetBorderTopRight", "InsetBorderBottomLeft",
    "InsetBorderBottomRight", "InsetBorderLeft", "InsetBorderRight",
    "InsetBorderTopLeft2", "InsetBorderBottomLeft2", "InsetBorderLeft2",
}
local FACTION_BAR_ART = { "Left", "Right", "Middle", "BG", "Shadow" }
local COMMUNITY_LIST_ART = { "Bg", "TopFiligree", "BottomFiligree" }
local COMMUNITY_TABS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }
local WIDE_BACKGROUND_ATLAS = "communities-widebackground"

-- These are the fixed UIPanelButtonTemplate descendants declared directly by
-- the Communities templates. They may inherit implicit protection from the
-- surrounding Communities tree, so the global legacy-button hook correctly
-- refuses them; the dedicated OOC owner can claim these exact paths safely.
local communityPanelButtonPaths = {
    { "InvitationFrame", "AcceptButton" },
    { "InvitationFrame", "DeclineButton" },
    { "TicketFrame", "AcceptButton" },
    { "TicketFrame", "DeclineButton" },
    { "ClubFinderInvitationFrame", "AcceptButton" },
    { "ClubFinderInvitationFrame", "ApplyButton" },
    { "ClubFinderInvitationFrame", "DeclineButton" },
    { "ClubFinderInvitationFrame", "WarningDialog", "Accept" },
    { "ClubFinderInvitationFrame", "WarningDialog", "Cancel" },
    { "ClubFinderInvitationFrame", "RequestToJoinFrame", "Apply" },
    { "ClubFinderInvitationFrame", "RequestToJoinFrame", "Cancel" },
    { "RecruitmentDialog", "Accept" },
    { "RecruitmentDialog", "Cancel" },
    { "EditStreamDialog", "Accept" },
    { "EditStreamDialog", "Delete" },
    { "EditStreamDialog", "Cancel" },
    { "GuildNameChangeFrame", "Button" },
    { "CommunityNameChangeFrame", "Button" },
    { "GuildPostingChangeFrame", "Button" },
    { "CommunityPostingChangeFrame", "Button" },
}

local function GetState(frame, owner)
    local state = CommunitiesSkin.states[frame]
    if not state then
        state = {
            frame = frame,
            owner = owner,
            active = false,
            surfaces = Kit.WeakSet(),
            rows = Kit.WeakSet(),
            scrollBoxes = Kit.WeakSet(),
            frameCallbacks = {},
        }
        CommunitiesSkin.states[frame] = state
    end
    state.owner = owner or state.owner
    return state
end

local function FadeButtonNormalTexture(state, button)
    Fade(state, (Safety.Call(button, "GetNormalTexture")))
end

local function SkinDialogSurface(state, dialog, borderKey)
    if not dialog then return false end
    local attached = Kit.Attach(state, dialog, POPUP_SPEC)
    local border = Field(dialog, borderKey or "Border")
    if border then
        -- DialogBorder* owns the eight DiamondMetal pieces directly and its
        -- optional tiled fill as Bg. Keep the dialog itself as Blizzard's
        -- behavior/visibility owner and replace only those native visuals.
        FadeNineSlice(state, border)
        Fade(state, Field(border, "Bg"))
    end
    return attached
end

-- Row and button controls are remembered for the selection refresh.
local function ApplyControl(state, row, spec)
    if not Kit.SkinControl(state, row, spec) then return false end
    state.rows[row] = true
    return true
end

local function SkinPanelButton(state, button)
    return ApplyControl(state, button, PANEL_BUTTON_SPEC)
end

local function SkinFixedPanelButtons(state)
    -- CommunitiesChatFrame.xml gives this one control an exact global name
    -- rather than a parentKey; all remaining controls use the paths above.
    SkinPanelButton(state, _G.JumpToUnreadButton)
    for index = 1, #communityPanelButtonPaths do
        SkinPanelButton(state, Kit.PathOf(state.frame, communityPanelButtonPaths[index]))
    end
end

local function SkinCommunitiesRow(state, row)
    -- ControlSkin copies the spec synchronously, so the shared table can
    -- carry this row's selection for exactly one call.
    COMMUNITY_ROW_SPEC.active = Kit.IsShown(Field(row, "Selection"))
    ApplyControl(state, row, COMMUNITY_ROW_SPEC)
    COMMUNITY_ROW_SPEC.active = nil
end

local function SkinPerkRow(state, row)
    -- The unnamed center and border textures are decorative; the verified
    -- Icon region is the perk's semantic content and remains visible.
    Kit.FadeTextures(state, row, Field(row, "Icon"))
    Kit.FadeTextures(state, Field(row, "NormalBorder"))
    Kit.FadeTextures(state, Field(row, "DisabledBorder"))
    ApplyControl(state, row, PERK_ROW_SPEC)
end

local function SkinRewardRow(state, row)
    -- Guild reward buttons use an unnamed brown NormalTexture. ControlSkin
    -- replaces interaction-state textures, but deliberately does not assume a
    -- button's normal texture is cosmetic; this verified template is.
    FadeButtonNormalTexture(state, row)
    ApplyControl(state, row, REWARD_ROW_SPEC)
end

local function SkinNewsRow(state, row)
    FadeButtonNormalTexture(state, row)
    ApplyControl(state, row, NEWS_ROW_SPEC)
end

-- CommunitiesMemberListEntryTemplate uses a full-size GuildFrame normal
-- texture for every pooled roster row, and ClubFinderApplicantEntryTemplate
-- the same full-width strip. Highlight, class/role textures and all member
-- data remain Blizzard-owned and visible.
local rowSkinners = {
    communities = SkinCommunitiesRow,
    perk = SkinPerkRow,
    reward = SkinRewardRow,
    news = SkinNewsRow,
    member = FadeButtonNormalTexture,
    applicant = FadeButtonNormalTexture,
}

local function SkinRow(state, row, kind)
    if not state.active or not row or NS.IsCombatLocked() then return end
    rowSkinners[kind](state, row)
end

-- Registered once per ScrollBox as callback(registration, row).
local function OnRowInitialized(registration, row)
    local active = CommunitiesSkin.activeState
    if active and active.active then SkinRow(active, row, registration.kind) end
end

local function RegisterScrollBox(state, scrollBox, kind)
    if not scrollBox or state.scrollBoxes[scrollBox] then return end
    local registration = { kind = kind }
    registration.event = Kit.RegisterRowCallback(scrollBox, OnRowInitialized, registration)
    if not registration.event then return end
    state.scrollBoxes[scrollBox] = registration
    Kit.ForEachRow(scrollBox, function(row) SkinRow(state, row, kind) end)
end

local function RefreshCommunitySelection(state)
    for row in pairs(state.rows) do
        local selection = Field(row, "Selection")
        if selection then
            NS.Surface.SetActive(row, Kit.IsShown(selection))
        end
    end
end

local function SkinLeftNavigation(state)
    local list = Field(state.frame, "CommunitiesList")
    if not list then return end
    Kit.Attach(state, list, NAVIGATION_SPEC)
    Kit.FadeFields(state, list, COMMUNITY_LIST_ART)
    Kit.FadeTextures(state, Field(list, "FilligreeOverlay"))
    FadeNineSlice(state, Path(list, "InsetFrame", "NineSlice"))
    RegisterScrollBox(state, Field(list, "ScrollBox"), "communities")
end

local function SkinColumnHeaders(state, columnDisplay)
    local pool = Field(columnDisplay, "columnHeaders")
    if type((Field(pool, "EnumerateActive"))) ~= "function" then return end
    local visited = 0
    for header in pool:EnumerateActive() do
        if not header or visited >= COLUMN_HEADER_LIMIT then break end
        visited = visited + 1
        Kit.FadeFields(state, header, COLUMN_HEADER_ART)
    end
end

local function HookColumnDisplay(state, columnDisplay)
    if CommunitiesSkin.columnDisplayHooks[columnDisplay] then return end
    CommunitiesSkin.columnDisplayHooks[columnDisplay] = Kit.HookFunction(columnDisplay, "LayoutColumns",
        function()
            if state.active and not NS.IsCombatLocked() then
                SkinColumnHeaders(state, columnDisplay)
            end
        end) or nil
end

local function SkinColumnDisplay(state, columns)
    if not columns then return end
    Kit.FadeFields(state, columns, COLUMN_DISPLAY_ART)
    SkinColumnHeaders(state, columns)
    HookColumnDisplay(state, columns)
end

local function SkinMemberList(state)
    local memberList = Field(state.frame, "MemberList")
    if not memberList then return end
    Kit.Attach(state, memberList, PANEL_SPEC)
    SkinColumnDisplay(state, Field(memberList, "ColumnDisplay"))
    Fade(state, Path(memberList, "ScrollBar", "Background"))
    FadeNineSlice(state, Path(memberList, "InsetFrame", "NineSlice"))
    RegisterScrollBox(state, Field(memberList, "ScrollBox"), "member")
end

local function FadeInsetFrame(state, inset)
    Fade(state, Field(inset, "Bg"))
    FadeNineSlice(state, Field(inset, "NineSlice"))
end

local function SkinFinderPane(state, frame)
    if not frame then return end

    -- Both finder variants construct their visible Search action together
    -- with CommunitiesFrame. The button inherits UIPanelButtonTemplate, but
    -- can be implicitly protected through the Communities tree and therefore
    -- fail the global legacy-button owner. Claim this exact source-reviewed
    -- parentKey path through the dedicated OOC owner instead.
    SkinPanelButton(state, Path(frame, "OptionsList", "Search"))
    SkinPanelButton(state, Path(frame, "RequestToJoinFrame", "Apply"))
    SkinPanelButton(state, Path(frame, "RequestToJoinFrame", "Cancel"))
    SkinDialogSurface(state, Field(frame, "RequestToJoinFrame"), "BG")

    -- Each GuildCards container owns exactly three XML-created cards through
    -- parentArray="Cards". CommunityCards uses a different whole-row button
    -- template and has no red RequestJoin child.
    for _, containerKey in ipairs({ "GuildCards", "PendingGuildCards" }) do
        local cards = Path(frame, containerKey, "Cards")
        if type(cards) == "table" then
            for cardIndex = 1, 3 do
                SkinPanelButton(state, Field(cards[cardIndex], "RequestJoin"))
            end
        end
    end

    -- GuildFinderFrame and CommunityFinderFrame both inherit the same
    -- ClubFinderGuildAndCommunityFrameTemplate. Unlike Chat, finder display
    -- modes hide CommunitiesFrame.Inset and show this pane-local marble inset.
    FadeInsetFrame(state, Field(frame, "InsetFrame"))

    -- When Club Finder is unavailable Blizzard swaps to another full-size
    -- InsetFrame with one anonymous wide-background texture. Preserve its
    -- semantic title and explanatory FontStrings, but remove both backdrops.
    local disabled = Field(frame, "DisabledFrame")
    FadeInsetFrame(state, disabled)
    Kit.FadeAtlas(state, disabled, WIDE_BACKGROUND_ATLAS)
end

local function SkinApplicantList(state)
    local applicantList = Field(state.frame, "ApplicantList")
    if not applicantList then return end
    SkinColumnDisplay(state, Field(applicantList, "ColumnDisplay"))
    Fade(state, Path(applicantList, "ScrollBar", "Background"))
    FadeInsetFrame(state, Field(applicantList, "InsetFrame"))
    RegisterScrollBox(state, Field(applicantList, "ScrollBox"), "applicant")
end

local function SkinInvitationPane(state, frame)
    if not frame then return end
    FadeInsetFrame(state, Field(frame, "InsetFrame"))
    -- Invitation/Ticket frames also own avatar, ring and guild-banner
    -- textures. Match only the verified full-area background atlas.
    Kit.FadeAtlas(state, frame, WIDE_BACKGROUND_ATLAS)

    -- ClubFinderInvitationFrame owns both exact DialogBorderDark popups.
    -- Ordinary InvitationFrame/TicketFrame simply have no matching children.
    SkinDialogSurface(state, Field(frame, "WarningDialog"), "BG")
    SkinDialogSurface(state, Field(frame, "RequestToJoinFrame"), "BG")
end

local function SkinGuildBenefits(state)
    local benefits = Field(state.frame, "GuildBenefitsFrame")
    if not benefits then return end
    Kit.Attach(state, benefits, PANEL_SPEC)
    Kit.FadeFields(state, benefits, GUILD_PANEL_BORDERS)

    local perks = Field(benefits, "Perks")
    local rewards = Field(benefits, "Rewards")
    Kit.Attach(state, perks, CARD_SPEC)
    Kit.Attach(state, rewards, CARD_SPEC)
    Kit.FadeTextures(state, perks)
    Fade(state, Field(rewards, "Bg"))
    Fade(state, Path(perks, "ScrollBar", "Background"))
    RegisterScrollBox(state, Field(perks, "ScrollBox"), "perk")
    RegisterScrollBox(state, Field(rewards, "ScrollBox"), "reward")

    local factionBar = Path(benefits, "FactionFrame", "Bar")
    if factionBar then
        Kit.Attach(state, factionBar, STATUS_SPEC)
        Kit.FadeFields(state, factionBar, FACTION_BAR_ART)
    end
end

local function SkinGuildDetails(state)
    local details = Field(state.frame, "GuildDetailsFrame")
    if not details then return end
    Kit.Attach(state, details, PANEL_SPEC)
    Kit.FadeFields(state, details, GUILD_PANEL_BORDERS)

    local info = Field(details, "Info")
    local news = Field(details, "News")
    Kit.Attach(state, info, CARD_SPEC)
    Kit.Attach(state, news, CARD_SPEC)
    Kit.FadeTextures(state, info)
    Kit.FadeTextures(state, news)
    Fade(state, Path(news, "ScrollBar", "Background"))
    RegisterScrollBox(state, Field(news, "ScrollBox"), "news")
end

local function SkinBottomButtons(state)
    -- These controls are direct children of CommunitiesFrame (or of its
    -- direct CommunitiesControlFrame child), not GuildDetailsFrame. Blizzard
    -- creates them before ordinary addons, so use their verified parentKeys
    -- instead of depending on a late template OnShow notification.
    SkinPanelButton(state, Field(state.frame, "GuildLogButton"))
    SkinPanelButton(state, Field(state.frame, "InviteButton"))

    local controls = Field(state.frame, "CommunitiesControlFrame")
    SkinPanelButton(state, Field(controls, "CommunitiesSettingsButton"))
    SkinPanelButton(state, Field(controls, "GuildControlButton"))
    SkinPanelButton(state, Field(controls, "GuildRecruitmentButton"))
end

local function SkinGuildMemberDetail(state)
    -- GuildRoster.xml constructs this hidden dialog together with
    -- CommunitiesFrame. Its two actions inherit UIPanelButtonTemplate, so
    -- their red Left/Middle/Right art exists even before the detail dialog is
    -- first shown. Skin the exact parentKey controls up front: DisplayMember
    -- only changes their enabled state and never replaces the controls.
    local detail = Field(state.frame, "GuildMemberDetailFrame")
    if not detail then return end

    SkinDialogSurface(state, detail, "Border")
    for _, key in ipairs({ "NoteBackground", "OfficerNoteBackground" }) do
        local note = Field(detail, key)
        if note then
            Kit.Attach(state, note, NOTE_SPEC)
            FadeNineSlice(state, Field(note, "NineSlice"))
        end
    end
    SkinPanelButton(state, Field(detail, "RemoveButton"))
    SkinPanelButton(state, Field(detail, "GroupInviteButton"))
end

local function SkinTabs(state)
    for index = 1, #COMMUNITY_TABS do
        local tab = Field(state.frame, COMMUNITY_TABS[index])
        -- ControlSkin copies the spec synchronously; see SkinCommunitiesRow.
        TAB_SPEC.active = Safety.Read(tab, "GetChecked") == true
        Kit.SkinControl(state, tab, TAB_SPEC)
        TAB_SPEC.active = nil
    end
end

local function SkinStatic(state)
    local frame = state.frame
    Kit.Attach(state, frame, SHELL_SPEC)
    FadeNineSlice(state, Field(frame, "NineSlice"))
    Fade(state, Field(frame, "Bg"))
    -- ButtonFrameTemplate owns a second, full-content marble backdrop below
    -- Chat and MemberList. CommunitiesFrame explicitly shows this inherited
    -- Inset in ordinary display modes, so removing only the root Bg leaves an
    -- opaque black rectangle inside an otherwise translucent Glass shell.
    FadeInsetFrame(state, Field(frame, "Inset"))
    SkinLeftNavigation(state)
    SkinMemberList(state)
    SkinFinderPane(state, Field(frame, "GuildFinderFrame"))
    SkinFinderPane(state, Field(frame, "CommunityFinderFrame"))
    SkinApplicantList(state)
    for _, key in ipairs({ "InvitationFrame", "ClubFinderInvitationFrame", "TicketFrame" }) do
        SkinInvitationPane(state, Field(frame, key))
    end
    SkinGuildBenefits(state)
    SkinGuildDetails(state)
    SkinTabs(state)
    SkinBottomButtons(state)
    SkinGuildMemberDetail(state)
    SkinDialogSurface(state, Field(frame, "EditStreamDialog"), "BG")
    SkinDialogSurface(state, Field(frame, "RecruitmentDialog"), "BG")
    SkinFixedPanelButtons(state)
    if NS.Checkmarks then
        NS.Checkmarks.TrackControlTree(frame, state.owner, CONTROL_TREE_OPTIONS)
    end
end

function CommunitiesSkin:OnDisplayChanged()
    local state = self.activeState
    if not state or not state.active or NS.IsCombatLocked() then return end
    SkinStatic(state)
    RefreshCommunitySelection(state)
end

function CommunitiesSkin:OnClubSelected()
    local state = self.activeState
    if not state or not state.active or NS.IsCombatLocked() then return end
    RefreshCommunitySelection(state)
end

local function RegisterFrameCallback(state, event, method)
    if type(event) ~= "string" or state.frameCallbacks[event] then return end
    if Safety.Invoke(state.frame, "RegisterCallback", event, method, CommunitiesSkin) then
        state.frameCallbacks[event] = true
    end
end

local function RegisterCallbacks(state)
    local events = _G.CommunitiesFrameMixin and _G.CommunitiesFrameMixin.Event
    if type(events) == "table" then
        RegisterFrameCallback(state, events.DisplayModeChanged, CommunitiesSkin.OnDisplayChanged)
        RegisterFrameCallback(state, events.ClubSelected, CommunitiesSkin.OnClubSelected)
    end
end

local function UnregisterCallbacks(state)
    for event in pairs(state.frameCallbacks) do
        Safety.Invoke(state.frame, "UnregisterCallback", event, CommunitiesSkin)
    end
    state.frameCallbacks = {}
    for scrollBox, registration in pairs(state.scrollBoxes) do
        Kit.UnregisterRowCallback(scrollBox, registration.event, registration)
    end
    state.scrollBoxes = Kit.WeakSet()
end

local function RestoreState(state)
    state.active = false
    UnregisterCallbacks(state)
    NS.ControlSkin.DisableOwner(state.owner)
    Kit.HideSurfaces(state)
    NS.Cosmetics.RestoreOwner(state.owner)
    state.rows = Kit.WeakSet()
end

function CommunitiesSkin.Apply(frame, owner)
    frame = frame or _G.CommunitiesFrame
    owner = owner or "communities"
    if not frame then return false, "missing" end
    if not Safety.CanDecorate(frame, true) then return false, "protected" end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("communities:apply", function()
            CommunitiesSkin.Apply(_G.CommunitiesFrame or frame, owner)
        end)
        return false, "combat"
    end
    local state = GetState(frame, owner)
    if state.active and state.owner ~= owner then RestoreState(state) end
    state.active = true
    CommunitiesSkin.activeState = state
    SkinStatic(state)
    RegisterCallbacks(state)
    RefreshCommunitySelection(state)
    return true
end

function CommunitiesSkin.Disable(frame, owner)
    frame = frame or (CommunitiesSkin.activeState and CommunitiesSkin.activeState.frame)
        or _G.CommunitiesFrame
    NS.CombatGate.Cancel("communities:apply")
    if not frame then return true end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("communities:disable", function()
            CommunitiesSkin.Disable(frame, owner)
        end)
        return false, "combat"
    end
    local state = CommunitiesSkin.states[frame]
    if state then
        RestoreState(state)
    elseif owner then
        NS.ControlSkin.DisableOwner(owner)
        NS.Cosmetics.RestoreOwner(owner)
    end
    if CommunitiesSkin.activeState == state then CommunitiesSkin.activeState = nil end
    return true
end

return CommunitiesSkin
