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

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

-- Pass the operands through pcall; do not allocate a capturing closure per read.
local function IndexMember(object, key)
    return object[key]
end

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(IndexMember, object, key)
    return ok and value or nil
end

local function Path(object, ...)
    for index = 1, select("#", ...) do
        object = SafeField(object, select(index, ...))
        if not object then return nil end
    end
    return object
end

local function IsUnsafe(target, control)
    if not NS.Safety then return true end
    if control then return not NS.Safety.CanControl(target, true) end
    return not NS.Safety.CanDecorate(target, true)
end

local function NewState(frame, owner)
    return {
        frame = frame,
        owner = owner,
        active = false,
        surfaces = WeakSet(),
        rows = WeakSet(),
        scrollBoxes = WeakSet(),
        frameCallbacks = {},
    }
end

local function GetState(frame, owner)
    local state = CommunitiesSkin.states[frame]
    if not state then
        state = NewState(frame, owner)
        CommunitiesSkin.states[frame] = state
    end
    state.owner = owner or state.owner
    return state
end

local function Fade(state, region)
    if region then pcall(NS.Cosmetics.Fade, region, state.owner) end
end

local function FadeNineSlice(state, nineSlice)
    if nineSlice then pcall(NS.Cosmetics.FadeNineSlice, nineSlice, state.owner) end
end

local function TextureRegions(frame)
    local result = {}
    if not frame or type(SafeField(frame, "GetRegions")) ~= "function" then return result end
    pcall(function()
        local function Capture(...)
            for index = 1, select("#", ...) do
                local region = select(index, ...)
                local objectType = type(SafeField(region, "GetObjectType")) == "function"
                    and region:GetObjectType() or nil
                if objectType == "Texture" then result[#result + 1] = region end
            end
        end
        Capture(frame:GetRegions())
    end)
    return result
end

local function FadeTextureRegions(state, frame, exception)
    for _, region in ipairs(TextureRegions(frame)) do
        if region ~= exception then Fade(state, region) end
    end
end

local function FadeTextureAtlas(state, frame, atlas)
    if not atlas then return end
    for _, region in ipairs(TextureRegions(frame)) do
        local getter = SafeField(region, "GetAtlas")
        if type(getter) == "function" then
            local ok, value = pcall(getter, region)
            if ok and value == atlas then Fade(state, region) end
        end
    end
end

local function FadeButtonTexture(state, button, getter)
    local method = button and SafeField(button, getter)
    if type(method) ~= "function" then return end
    local ok, texture = pcall(method, button)
    if ok then Fade(state, texture) end
end

local function Attach(state, target, role, radius, inset, keepGlassFill)
    if not target or IsUnsafe(target, false) then return false end
    local ok, surface = pcall(NS.Surface.Attach, target, {
        role = role or "panel",
        radius = radius or 6,
        inset = inset or 0,
        keepGlassFill = keepGlassFill,
        allowImplicitProtected = true,
    })
    if ok and surface then
        state.surfaces[target] = true
        return true
    end
    return false
end

local function SkinDialogSurface(state, dialog, borderKey)
    if not dialog then return false end
    local attached = Attach(state, dialog, "popup", 8, 0)
    local border = SafeField(dialog, borderKey or "Border")
    if border then
        -- DialogBorder* owns the eight DiamondMetal pieces directly and its
        -- optional tiled fill as Bg. Keep the dialog itself as Blizzard's
        -- behavior/visibility owner and replace only those native visuals.
        FadeNineSlice(state, border)
        Fade(state, SafeField(border, "Bg"))
    end
    return attached
end

local function IsShown(region)
    if not region or type(SafeField(region, "IsShown")) ~= "function" then return false end
    local ok, shown = pcall(region.IsShown, region)
    return ok and shown == true
end

local function ApplyControl(state, row, spec)
    if not row or IsUnsafe(row, true) then return false end
    spec = spec or {}
    spec.allowImplicitProtected = true
    spec.useControlShape = true
    local ok, applied = pcall(NS.ControlSkin.ApplyButton, row, state.owner, spec)
    if ok and applied then
        state.rows[row] = true
        state.surfaces[row] = true
        return true
    end
    return false
end

local function SkinPanelButton(state, button)
    return ApplyControl(state, button, {
        role = "button",
        activeRole = "buttonPrimary",
        pillHeight = 20,
        inset = 1,
        regions = { "Left", "Middle", "Right" },
    })
end

-- These are the fixed UIPanelButtonTemplate descendants declared directly by
-- the Communities templates.  They may inherit implicit protection from the
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

local function SkinFixedPanelButtons(state)
    -- CommunitiesChatFrame.xml gives this one control an exact global name
    -- rather than a parentKey; all remaining controls use the paths above.
    SkinPanelButton(state, _G.JumpToUnreadButton)
    for index = 1, #communityPanelButtonPaths do
        SkinPanelButton(state, Path(state.frame, unpack(communityPanelButtonPaths[index])))
    end
end

local function SkinCommunitiesRow(state, row)
    if not row then return end
    ApplyControl(state, row, {
        role = "navigation",
        activeRole = "navigationActive",
        radius = 6,
        inset = 2,
        pillHeight = 64,
        regions = { "Background", "Selection", "NewCommunityFlash" },
        active = IsShown(SafeField(row, "Selection")),
    })
end

local function SkinPerkRow(state, row)
    if not row then return end
    -- The unnamed center and border textures are decorative; the verified
    -- Icon region is the perk's semantic content and remains visible.
    FadeTextureRegions(state, row, SafeField(row, "Icon"))
    FadeTextureRegions(state, SafeField(row, "NormalBorder"))
    FadeTextureRegions(state, SafeField(row, "DisabledBorder"))
    ApplyControl(state, row, {
        role = "card", radius = 4, inset = 1, pillHeight = 40,
        keepGlassFill = false,
        regions = { "Left", "Right" },
    })
end

local function SkinRewardRow(state, row)
    if not row then return end
    -- Guild reward buttons use an unnamed brown NormalTexture. ControlSkin
    -- replaces interaction-state textures, but deliberately does not assume a
    -- button's normal texture is cosmetic; this verified template is.
    FadeButtonTexture(state, row, "GetNormalTexture")
    ApplyControl(state, row, {
        role = "card", radius = 4, inset = 1, pillHeight = 44,
        keepGlassFill = false,
        regions = { "DisabledBG" },
    })
end

local function SkinNewsRow(state, row)
    if not row then return end
    FadeButtonTexture(state, row, "GetNormalTexture")
    ApplyControl(state, row, {
        role = "card", radius = 4, inset = 1, pillHeight = 18,
        listItem = true,
        regions = { "header" },
    })
end

local function SkinMemberRow(state, row)
    if not row then return end
    -- CommunitiesMemberListEntryTemplate uses a full-size GuildFrame normal
    -- texture for every pooled roster row. Its highlight and all member data
    -- remain Blizzard-owned and visible.
    FadeButtonTexture(state, row, "GetNormalTexture")
end

local function SkinApplicantRow(state, row)
    if not row then return end
    -- ClubFinderApplicantEntryTemplate uses the same full-width GuildFrame
    -- strip as roster rows. Class and role textures are separate regions.
    FadeButtonTexture(state, row, "GetNormalTexture")
end

local function SkinRow(state, row, kind)
    if not state.active or NS.IsCombatLocked() then return end
    if kind == "communities" then SkinCommunitiesRow(state, row)
    elseif kind == "perk" then SkinPerkRow(state, row)
    elseif kind == "reward" then SkinRewardRow(state, row)
    elseif kind == "news" then SkinNewsRow(state, row)
    elseif kind == "member" then SkinMemberRow(state, row)
    elseif kind == "applicant" then SkinApplicantRow(state, row)
    end
end

local function ScrollEvent()
    return ScrollBoxListMixin and ScrollBoxListMixin.Event
        and ScrollBoxListMixin.Event.OnInitializedFrame
end

local function RegisterScrollBox(state, scrollBox, kind)
    local event = ScrollEvent()
    if not event or not scrollBox or state.scrollBoxes[scrollBox]
        or type(SafeField(scrollBox, "RegisterCallback")) ~= "function" then return end
    local token = {}
    local function OnInitializedFrame(_, row)
        local active = CommunitiesSkin.activeState
        if active and active.active then SkinRow(active, row, kind) end
    end
    local ok = pcall(scrollBox.RegisterCallback, scrollBox, event, OnInitializedFrame, token)
    if not ok then return end
    state.scrollBoxes[scrollBox] = { kind = kind, token = token }
    if type(SafeField(scrollBox, "ForEachFrame")) == "function" then
        pcall(scrollBox.ForEachFrame, scrollBox, function(row) SkinRow(state, row, kind) end)
    end
end

local function RefreshCommunitySelection(state)
    for row in pairs(state.rows) do
        if SafeField(row, "Selection") then
            pcall(NS.Surface.SetActive, row, IsShown(row.Selection))
        end
    end
end

local function SkinLeftNavigation(state)
    local list = Path(state.frame, "CommunitiesList")
    if not list then return end
    Attach(state, list, "navigation", 6, 0, false)
    for _, key in ipairs({ "Bg", "TopFiligree", "BottomFiligree" }) do Fade(state, SafeField(list, key)) end
    local overlay = SafeField(list, "FilligreeOverlay")
    FadeTextureRegions(state, overlay)
    FadeNineSlice(state, Path(list, "InsetFrame", "NineSlice"))
    RegisterScrollBox(state, SafeField(list, "ScrollBox"), "communities")
end

local function SkinColumnHeaders(state, columnDisplay)
    local pool = SafeField(columnDisplay, "columnHeaders")
    if not pool or type(SafeField(pool, "EnumerateActive")) ~= "function" then return end
    pcall(function()
        local visited = 0
        for header in pool:EnumerateActive() do
            if not header or visited >= 16 then break end
            visited = visited + 1
            for _, key in ipairs({ "Left", "Middle", "Right" }) do
                Fade(state, SafeField(header, key))
            end
        end
    end)
end

local function HookColumnDisplay(state, columnDisplay)
    if not columnDisplay or CommunitiesSkin.columnDisplayHooks[columnDisplay]
        or type(SafeField(columnDisplay, "LayoutColumns")) ~= "function"
        or type(hooksecurefunc) ~= "function" then
        return
    end
    local ok = pcall(hooksecurefunc, columnDisplay, "LayoutColumns", function()
        if state.active and not NS.IsCombatLocked() then
            SkinColumnHeaders(state, columnDisplay)
        end
    end)
    if ok then CommunitiesSkin.columnDisplayHooks[columnDisplay] = true end
end

local function SkinMemberList(state)
    local memberList = SafeField(state.frame, "MemberList")
    if not memberList then return end
    Attach(state, memberList, "panel", 6, 0)

    local columns = SafeField(memberList, "ColumnDisplay")
    if columns then
        for _, key in ipairs({
            "Background", "TopTileStreaks", "InsetBorderTopLeft",
            "InsetBorderTopRight", "InsetBorderBottomLeft", "InsetBorderTop",
            "InsetBorderLeft",
        }) do
            Fade(state, SafeField(columns, key))
        end
        SkinColumnHeaders(state, columns)
        HookColumnDisplay(state, columns)
    end

    Fade(state, Path(memberList, "ScrollBar", "Background"))
    FadeNineSlice(state, Path(memberList, "InsetFrame", "NineSlice"))
    RegisterScrollBox(state, SafeField(memberList, "ScrollBox"), "member")
end

local function SkinFinderPane(state, frame)
    if not frame then return end

    -- Both finder variants construct their visible Search action together
    -- with CommunitiesFrame.  The button inherits UIPanelButtonTemplate, but
    -- can be implicitly protected through the Communities tree and therefore
    -- fail the global legacy-button owner.  Claim this exact source-reviewed
    -- parentKey path through the dedicated OOC owner instead.
    SkinPanelButton(state, Path(frame, "OptionsList", "Search"))
    SkinPanelButton(state, Path(frame, "RequestToJoinFrame", "Apply"))
    SkinPanelButton(state, Path(frame, "RequestToJoinFrame", "Cancel"))
    SkinDialogSurface(state, SafeField(frame, "RequestToJoinFrame"), "BG")

    -- Each GuildCards container owns exactly three XML-created cards through
    -- parentArray="Cards". CommunityCards uses a different whole-row button
    -- template and has no red RequestJoin child.
    for _, containerKey in ipairs({ "GuildCards", "PendingGuildCards" }) do
        local cards = Path(frame, containerKey, "Cards")
        if type(cards) == "table" then
            for cardIndex = 1, 3 do
                SkinPanelButton(state, Path(cards[cardIndex], "RequestJoin"))
            end
        end
    end

    -- GuildFinderFrame and CommunityFinderFrame both inherit the same
    -- ClubFinderGuildAndCommunityFrameTemplate. Unlike Chat, finder display
    -- modes hide CommunitiesFrame.Inset and show this pane-local marble inset.
    local inset = SafeField(frame, "InsetFrame")
    Fade(state, SafeField(inset, "Bg"))
    FadeNineSlice(state, SafeField(inset, "NineSlice"))

    -- When Club Finder is unavailable Blizzard swaps to another full-size
    -- InsetFrame with one anonymous wide-background texture. Preserve its
    -- semantic title and explanatory FontStrings, but remove both backdrops.
    local disabled = SafeField(frame, "DisabledFrame")
    Fade(state, SafeField(disabled, "Bg"))
    FadeNineSlice(state, SafeField(disabled, "NineSlice"))
    FadeTextureAtlas(state, disabled, "communities-widebackground")
end

local function SkinFinderPanes(state)
    SkinFinderPane(state, SafeField(state.frame, "GuildFinderFrame"))
    SkinFinderPane(state, SafeField(state.frame, "CommunityFinderFrame"))
end

local function SkinApplicantList(state)
    local applicantList = SafeField(state.frame, "ApplicantList")
    if not applicantList then return end

    local columns = SafeField(applicantList, "ColumnDisplay")
    if columns then
        for _, key in ipairs({
            "Background", "TopTileStreaks", "InsetBorderTopLeft",
            "InsetBorderTopRight", "InsetBorderBottomLeft", "InsetBorderTop",
            "InsetBorderLeft",
        }) do
            Fade(state, SafeField(columns, key))
        end
        SkinColumnHeaders(state, columns)
        HookColumnDisplay(state, columns)
    end

    Fade(state, Path(applicantList, "ScrollBar", "Background"))
    local inset = SafeField(applicantList, "InsetFrame")
    Fade(state, SafeField(inset, "Bg"))
    FadeNineSlice(state, SafeField(inset, "NineSlice"))
    RegisterScrollBox(state, SafeField(applicantList, "ScrollBox"), "applicant")
end

local function SkinInvitationPane(state, frame)
    if not frame then return end
    local inset = SafeField(frame, "InsetFrame")
    Fade(state, SafeField(inset, "Bg"))
    FadeNineSlice(state, SafeField(inset, "NineSlice"))
    -- Invitation/Ticket frames also own avatar, ring and guild-banner
    -- textures. Match only the verified full-area background atlas.
    FadeTextureAtlas(state, frame, "communities-widebackground")

    -- ClubFinderInvitationFrame owns both exact DialogBorderDark popups.
    -- Ordinary InvitationFrame/TicketFrame simply have no matching children.
    SkinDialogSurface(state, SafeField(frame, "WarningDialog"), "BG")
    SkinDialogSurface(state, SafeField(frame, "RequestToJoinFrame"), "BG")
end

local function SkinInvitationPanes(state)
    for _, key in ipairs({ "InvitationFrame", "ClubFinderInvitationFrame", "TicketFrame" }) do
        SkinInvitationPane(state, SafeField(state.frame, key))
    end
end

local function SkinGuildBenefits(state)
    local benefits = Path(state.frame, "GuildBenefitsFrame")
    if not benefits then return end
    Attach(state, benefits, "panel", 6, 0)
    for _, key in ipairs({
        "InsetBorderTopLeft", "InsetBorderTopRight", "InsetBorderBottomLeft",
        "InsetBorderBottomRight", "InsetBorderLeft", "InsetBorderRight",
        "InsetBorderTopLeft2", "InsetBorderBottomLeft2", "InsetBorderLeft2",
    }) do Fade(state, SafeField(benefits, key)) end

    local perks = SafeField(benefits, "Perks")
    local rewards = SafeField(benefits, "Rewards")
    Attach(state, perks, "card", 6, 0, false)
    Attach(state, rewards, "card", 6, 0, false)
    FadeTextureRegions(state, perks)
    Fade(state, SafeField(rewards, "Bg"))
    Fade(state, Path(perks, "ScrollBar", "Background"))
    RegisterScrollBox(state, SafeField(perks, "ScrollBox"), "perk")
    RegisterScrollBox(state, SafeField(rewards, "ScrollBox"), "reward")

    local factionBar = Path(benefits, "FactionFrame", "Bar")
    if factionBar then
        Attach(state, factionBar, "status", 4, 1)
        for _, key in ipairs({ "Left", "Right", "Middle", "BG", "Shadow" }) do
            Fade(state, SafeField(factionBar, key))
        end
    end
end

local function SkinGuildDetails(state)
    local details = Path(state.frame, "GuildDetailsFrame")
    if not details then return end
    Attach(state, details, "panel", 6, 0)
    for _, key in ipairs({
        "InsetBorderTopLeft", "InsetBorderTopRight", "InsetBorderBottomLeft",
        "InsetBorderBottomRight", "InsetBorderLeft", "InsetBorderRight",
        "InsetBorderTopLeft2", "InsetBorderBottomLeft2", "InsetBorderLeft2",
    }) do Fade(state, SafeField(details, key)) end

    local info = SafeField(details, "Info")
    local news = SafeField(details, "News")
    Attach(state, info, "card", 6, 0, false)
    Attach(state, news, "card", 6, 0, false)
    FadeTextureRegions(state, info)
    FadeTextureRegions(state, news)
    Fade(state, Path(news, "ScrollBar", "Background"))
    RegisterScrollBox(state, SafeField(news, "ScrollBox"), "news")
end

local function SkinBottomButtons(state)
    -- These controls are direct children of CommunitiesFrame (or of its
    -- direct CommunitiesControlFrame child), not GuildDetailsFrame. Blizzard
    -- creates them before ordinary addons, so use their verified parentKeys
    -- instead of depending on a late template OnShow notification.
    SkinPanelButton(state, SafeField(state.frame, "GuildLogButton"))
    SkinPanelButton(state, SafeField(state.frame, "InviteButton"))

    local controls = SafeField(state.frame, "CommunitiesControlFrame")
    SkinPanelButton(state, SafeField(controls, "CommunitiesSettingsButton"))
    SkinPanelButton(state, SafeField(controls, "GuildControlButton"))
    SkinPanelButton(state, SafeField(controls, "GuildRecruitmentButton"))
end

local function SkinGuildMemberDetail(state)
    -- GuildRoster.xml constructs this hidden dialog together with
    -- CommunitiesFrame. Its two actions inherit UIPanelButtonTemplate, so
    -- their red Left/Middle/Right art exists even before the detail dialog is
    -- first shown. Skin the exact parentKey controls up front: DisplayMember
    -- only changes their enabled state and never replaces the controls.
    local detail = SafeField(state.frame, "GuildMemberDetailFrame")
    if not detail then return end

    SkinDialogSurface(state, detail, "Border")
    for _, key in ipairs({ "NoteBackground", "OfficerNoteBackground" }) do
        local note = SafeField(detail, key)
        if note then
            Attach(state, note, "input", 5, 0)
            FadeNineSlice(state, SafeField(note, "NineSlice"))
        end
    end
    SkinPanelButton(state, SafeField(detail, "RemoveButton"))
    SkinPanelButton(state, SafeField(detail, "GroupInviteButton"))
end

local function SkinOwnedDialogs(state)
    SkinDialogSurface(state, SafeField(state.frame, "EditStreamDialog"), "BG")
    SkinDialogSurface(state, SafeField(state.frame, "RecruitmentDialog"), "BG")
end

local function SkinTabs(state)
    for _, key in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }) do
        local tab = SafeField(state.frame, key)
        if tab and not IsUnsafe(tab, true) then
            pcall(NS.ControlSkin.ApplyButton, tab, state.owner, {
                role = "navigation", activeRole = "navigationActive",
                shape = "round", radius = 6, inset = 1,
                active = type(SafeField(tab, "GetChecked")) == "function" and tab:GetChecked() == true,
                allowImplicitProtected = true,
            })
            state.surfaces[tab] = true
        end
    end
end

local function SkinStatic(state)
    Attach(state, state.frame, "shell", 8, 0)
    FadeNineSlice(state, SafeField(state.frame, "NineSlice"))
    Fade(state, SafeField(state.frame, "Bg"))
    -- ButtonFrameTemplate owns a second, full-content marble backdrop below
    -- Chat and MemberList. CommunitiesFrame explicitly shows this inherited
    -- Inset in ordinary display modes, so removing only the root Bg leaves an
    -- opaque black rectangle inside an otherwise translucent Glass shell.
    local inset = SafeField(state.frame, "Inset")
    Fade(state, SafeField(inset, "Bg"))
    FadeNineSlice(state, SafeField(inset, "NineSlice"))
    SkinLeftNavigation(state)
    SkinMemberList(state)
    SkinFinderPanes(state)
    SkinApplicantList(state)
    SkinInvitationPanes(state)
    SkinGuildBenefits(state)
    SkinGuildDetails(state)
    SkinTabs(state)
    SkinBottomButtons(state)
    SkinGuildMemberDetail(state)
    SkinOwnedDialogs(state)
    SkinFixedPanelButtons(state)
    if NS.Checkmarks and type(NS.Checkmarks.TrackControlTree) == "function" then
        NS.Checkmarks.TrackControlTree(state.frame, state.owner, {
            maxDepth = 8,
            maxNodes = 720,
        })
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
    if not event or state.frameCallbacks[event]
        or type(SafeField(state.frame, "RegisterCallback")) ~= "function" then return end
    local ok = pcall(state.frame.RegisterCallback, state.frame, event, method, CommunitiesSkin)
    if ok then state.frameCallbacks[event] = true end
end

local function RegisterCallbacks(state)
    local events = CommunitiesFrameMixin and CommunitiesFrameMixin.Event
    if events then
        RegisterFrameCallback(state, events.DisplayModeChanged, CommunitiesSkin.OnDisplayChanged)
        RegisterFrameCallback(state, events.ClubSelected, CommunitiesSkin.OnClubSelected)
    end
end

local function UnregisterCallbacks(state)
    if type(SafeField(state.frame, "UnregisterCallback")) == "function" then
        for event in pairs(state.frameCallbacks) do
            pcall(state.frame.UnregisterCallback, state.frame, event, CommunitiesSkin)
        end
    end
    state.frameCallbacks = {}
    local event = ScrollEvent()
    if event then
        for scrollBox, registration in pairs(state.scrollBoxes) do
            if type(SafeField(scrollBox, "UnregisterCallback")) == "function" then
                pcall(scrollBox.UnregisterCallback, scrollBox, event, registration.token)
            end
        end
    end
    state.scrollBoxes = WeakSet()
end

local function RestoreState(state)
    state.active = false
    UnregisterCallbacks(state)
    pcall(NS.ControlSkin.DisableOwner, state.owner)
    for target in pairs(state.surfaces) do pcall(NS.Surface.SetVisible, target, false) end
    pcall(NS.Cosmetics.RestoreOwner, state.owner)
    state.rows = WeakSet()
end

function CommunitiesSkin.Apply(frame, owner)
    frame = frame or _G.CommunitiesFrame
    owner = owner or "communities"
    if not frame then return false, "missing" end
    if IsUnsafe(frame, false) then return false, "protected" end
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
    local ok, result = pcall(SkinStatic, state)
    if not ok then
        NS.ReportError("communities apply", result)
        RestoreState(state)
        return false, "failed"
    end
    RegisterCallbacks(state)
    RefreshCommunitySelection(state)
    return true
end

function CommunitiesSkin.Disable(frame, owner)
    frame = frame or (CommunitiesSkin.activeState and CommunitiesSkin.activeState.frame) or _G.CommunitiesFrame
    NS.CombatGate.Cancel("communities:apply")
    if not frame then return true end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("communities:disable", function()
            CommunitiesSkin.Disable(frame, owner)
        end)
        return false, "combat"
    end
    local state = CommunitiesSkin.states[frame]
    if state then RestoreState(state)
    elseif owner then
        pcall(NS.ControlSkin.DisableOwner, owner)
        pcall(NS.Cosmetics.RestoreOwner, owner)
    end
    if CommunitiesSkin.activeState == state then CommunitiesSkin.activeState = nil end
    return true
end

return CommunitiesSkin
