local _, NS = ...

-- Clean-room Blizzard chat adapter verified against wow-ui-source upstream/ptr
-- a1f5e990. Hyperlinks, player/channel/class colors, conversation icons,
-- docking, Edit Mode placement and secure chat attributes remain Blizzard-owned.
-- Exact decorative FloatingChatFrame/EditBox regions plus Blizzard's SYSTEM and
-- ordinary NPC speech colors are recolored through their native OOC color path.
local ChatFramesSkin = { owners = {}, hooks = {} }
NS.ChatFramesSkin = ChatFramesSkin

local Safety = NS.Safety
local Field = Safety.Field
local Call = Safety.Call
local HasMethod = Safety.HasMethod
local Dispatch = Safety.Dispatch
local ColorMatches = Safety.ColorMatches
local SameColor = Safety.SameColor
local COLOR_OWN = Safety.COLOR_OWN
local COLOR_NATIVE = Safety.COLOR_NATIVE
local Kit = NS.AdapterKit

local REFRESH_KEY = "chat-frames:refresh"
local BUILTIN_CHAT_WINDOWS = 10
local MAX_CHAT_FRAMES = 64
local RefreshAll
local changingChatColor = false

-- These are the yellow message families visible in the default General chat:
-- system notices (group joins, loot-specialization changes, etc.) and ordinary
-- NPC speech. Player channels, raid/party text, links and class colors remain
-- independent Blizzard/user choices.
local messageColorRoles = {
    SYSTEM = "blizzardYellow",
    MONSTER_SAY = "blizzardYellow",
    MONSTER_PARTY = "blizzardYellow",
}

-- ChangeChatColor is a persistent Blizzard setting (chat-cache.txt), unlike
-- the frame-local chrome below, and the colours are the player's. Ownership
-- comes only from the skin's own writes, never from colour equality; the
-- per-category state machine (unowned, owned, released, recorded,
-- ambiguous) is in MSUF_Suite/Integrations/MapkoSkin.lua. The skin themes a
-- category only while it shows Blizzard's clean-profile default and nobody
-- else changed it this session; any change the skin did not make releases it
-- for the rest of the session. Logout and disable put back the colour a
-- category had before the skin, while it still shows the skin's own; what
-- they could not put back goes to the Suite's ledger, which only the
-- explicit "Restore chat colors" applies. Keep this list limited to the
-- categories we change.

local frameBorderSuffixes = {
    "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
}
local threeSliceSuffixes = { "Left", "Middle", "Right" }
local highlightSuffixes = { "HighlightLeft", "HighlightMiddle", "HighlightRight" }
local activeSuffixes = { "ActiveLeft", "ActiveMiddle", "ActiveRight" }
local editBoxSuffixes = { "Left", "Mid", "Right" }
local editBoxFocusSuffixes = { "FocusLeft", "FocusMid", "FocusRight" }
local utilityButtonNames = {
    "ChatFrameChannelButton",
    "ChatFrameToggleVoiceDeafenButton",
    "ChatFrameToggleVoiceMuteButton",
}

local function NamedRegion(object, suffix)
    local direct = Field(object, suffix)
    if direct then return direct end
    local name = Call(object, "GetName")
    if type(name) ~= "string" or name == "" then return nil end
    return _G[name .. suffix]
end

local function OwnerState(owner)
    local state = ChatFramesSkin.owners[owner]
    if not state then
        state = {
            active = false,
            owner = owner,
            frames = setmetatable({}, { __mode = "k" }),
            textStates = setmetatable({}, { __mode = "k" }),
            textureCaptured = setmetatable({}, { __mode = "k" }),
            nativeDesaturation = setmetatable({}, { __mode = "k" }),
            messageColors = {},
        }
        ChatFramesSkin.owners[owner] = state
    end
    return state
end

-- Message colors ------------------------------------------------------------

local function ReadMessageColor(chatType)
    local info = Field(_G.ChatTypeInfo, chatType)
    local r, g, b = Field(info, "r"), Field(info, "g"), Field(info, "b")
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    return { r, g, b }
end

-- changingChatColor keeps our own ChangeChatColor post-hook quiet during the
-- call. The call is its own error boundary, so the flag is cleared even when
-- it raises and later user color changes are still observed.
local function ChangeMessageColor(chatType, r, g, b)
    changingChatColor = true
    local finished = Kit.Isolate(ChangeChatColor, chatType, r, g, b)
    changingChatColor = false
    return finished == true
end

local function Shows(color, current, tolerance)
    return ColorMatches(color, current[1], current[2], current[3], nil, tolerance)
end

-- The Suite core's skin boundary (MSUF_Suite/Integrations/MapkoSkin.lua):
-- the chat colour ledger and Blizzard's default chat colours. Resolved once,
-- at the first use, through the skin's handle on the core (NS.SuiteCore).
local suiteSkin
local function Ledger()
    if not suiteSkin then suiteSkin = NS.SuiteCore().Skin end
    return suiteSkin
end

local function DefaultColor(chatType)
    return Ledger().CHAT_COLOR_DEFAULTS[chatType]
end

-- What the restores of this session could not put back, handed to the
-- ledger at logout; and the categories something other than the skin
-- changed this session (released for its rest).
local leftovers, changedExternally = {}, {}

-- The state of a category the skin meets for the first time: owned with the
-- colour to restore while it shows Blizzard's default and nobody changed it
-- this session, else released.
local function CaptureMessageColor(chatType, current)
    if not changedExternally[chatType] and Shows(DefaultColor(chatType), current, COLOR_NATIVE) then
        return { original = current, applied = {} }
    end
    return { released = true }
end

local function ApplyMessageColor(state, chatType)
    local role = messageColorRoles[chatType]
    local current = role and ReadMessageColor(chatType)
    if not current then return false end
    local r, g, b = NS.Theme.GetColor(role)
    local colorState = state.messageColors[chatType]
    if not colorState then
        colorState = CaptureMessageColor(chatType, current)
        state.messageColors[chatType] = colorState
    elseif not colorState.released and colorState.applied[1] and not Shows(colorState.applied, current, COLOR_OWN) then
        -- Changed by a path the ChangeChatColor hook does not see: theirs.
        colorState.released = true
    end
    if colorState.released then return false end
    if SameColor(current[1], current[2], current[3], nil, r, g, b, nil, COLOR_OWN)
        or ChangeMessageColor(chatType, r, g, b) then
        local applied = colorState.applied
        applied[1], applied[2], applied[3] = r, g, b
        return true
    end
    return false
end

local function ApplyMessageColors(state)
    for chatType in pairs(messageColorRoles) do
        ApplyMessageColor(state, chatType)
    end
end

-- Puts back the colour each owned category had before the skin, while it
-- still shows the skin's own; a released category keeps the player's. An
-- owned category the restore could not put back is a leftover for the
-- ledger, with the colour it shows.
local function RestoreMessageColors(state)
    local restored = 0
    for chatType, colorState in pairs(state.messageColors) do
        local current = ReadMessageColor(chatType)
        local original = colorState.original
        local owned = not colorState.released and current and original
            and Shows(colorState.applied, current, COLOR_OWN)
        if owned and ChangeMessageColor(chatType, original[1], original[2], original[3]) then
            restored = restored + 1
            leftovers[chatType] = nil
        elseif owned then
            leftovers[chatType] = { original = original, left = current }
        end
    end
    state.messageColors = {}
    return restored
end

-- Text colors ----------------------------------------------------------------

local function ReadTextColor(fontString)
    return Safety.ReadColor(fontString, "GetTextColor")
end

local function ApplyTextRole(fontString, textState)
    local r, g, b, a = NS.Theme.GetColor(textState.role)
    fontString:SetTextColor(r, g, b, a)
    local applied = textState.applied
    applied[1], applied[2], applied[3], applied[4] = r, g, b, a
end

local function SetTextRole(state, fontString, role, recapture)
    if not HasMethod(fontString, "SetTextColor") then return false end
    local r, g, b, a = ReadTextColor(fontString)
    if not r then return false end
    local textState = state.textStates[fontString]
    if not textState then
        textState = { original = { r, g, b, a }, applied = {} }
        state.textStates[fontString] = textState
    elseif recapture and not ColorMatches(textState.applied, r, g, b, a, COLOR_OWN) then
        -- Preserve Blizzard's latest native tab color for cooperative restore.
        local original = textState.original
        original[1], original[2], original[3], original[4] = r, g, b, a
    end
    textState.role = role
    ApplyTextRole(fontString, textState)
    return true
end

local function RefreshTextColors(state)
    for fontString, textState in pairs(state.textStates) do
        if HasMethod(fontString, "SetTextColor") then
            ApplyTextRole(fontString, textState)
        end
    end
end

local function RestoreTextColors(state)
    for fontString, textState in pairs(state.textStates) do
        local r, g, b, a = ReadTextColor(fontString)
        if ColorMatches(textState.applied, r, g, b, a, COLOR_OWN) then
            local original = textState.original
            fontString:SetTextColor(original[1], original[2], original[3], original[4])
        end
    end
    state.textStates = setmetatable({}, { __mode = "k" })
end

-- Textures -------------------------------------------------------------------

local function TrackTexture(state, texture, role, recapture)
    if not texture then return false end
    if not state.textureCaptured[texture] then
        state.textureCaptured[texture] = true
        if HasMethod(texture, "IsDesaturated") then
            state.nativeDesaturation[texture] = Call(texture, "IsDesaturated") == true
        end
    end
    if recapture then
        NS.Checkmarks.UntrackTexture(texture, state.owner)
        -- Blizzard's refresh functions rewrite vertex RGB but do not own the
        -- desaturation flag. Rebase from the latest RGB while retaining the
        -- native desaturation state captured before MapkoSkin touched it.
        local originalDesaturated = state.nativeDesaturation[texture]
        if originalDesaturated ~= nil then
            Call(texture, "SetDesaturated", originalDesaturated)
        end
    end
    return NS.Checkmarks.TrackTexture(texture, state.owner, role)
end

local function TrackSuffixes(state, object, suffixes, role, recapture)
    for index = 1, #suffixes do
        TrackTexture(state, NamedRegion(object, suffixes[index]), role, recapture)
    end
end

local function TrackButtonTextures(state, button, normalRole, pushedRole, hoverRole, recapture)
    if not button then return end
    TrackTexture(state, Call(button, "GetNormalTexture"), normalRole, recapture)
    TrackTexture(state, Call(button, "GetPushedTexture"), pushedRole or normalRole, recapture)
    TrackTexture(state, Call(button, "GetDisabledTexture"), "disabled", recapture)
    TrackTexture(state, Call(button, "GetHighlightTexture"), hoverRole or normalRole, recapture)
end

local function SkinWindowAction(state, button, kind, recapture)
    if not button then return end
    local action, reason = NS.WindowActionSkin.Apply(button, state.owner, kind)
    if action or reason == "owned by another adapter"
        or reason == "state texture ownership changed" then
        return
    end
    -- Protected or otherwise unsupported chat controls retain the previous
    -- reversible native-art tint instead of losing state feedback.
    TrackButtonTextures(state, button,
        "blizzardExpand", "blizzardExpandPressed", "blizzardExpandHover", recapture)
end

local function SkinFrameChrome(state, frame, recapture)
    if not frame then return end
    TrackTexture(state, NamedRegion(frame, "Background"), "background", recapture)
    TrackSuffixes(state, frame, frameBorderSuffixes, "border", recapture)
end

local function TrackFlashTextures(state, ...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if Call(region, "GetObjectType") == "Texture" then
            TrackTexture(state, region, "warning")
        end
    end
end

local function IsTabSelected(tab)
    local active = NamedRegion(tab, "ActiveMiddle")
        or NamedRegion(tab, "ActiveLeft") or NamedRegion(tab, "ActiveRight")
    return Call(active, "IsShown") == true
end

local function SkinMinimizedFrame(state, minimized, recapture)
    if not minimized then return end
    TrackSuffixes(state, minimized, threeSliceSuffixes, "buttonFillAlt")
    TrackSuffixes(state, minimized, highlightSuffixes, "hover", recapture)
    TrackTexture(state, NamedRegion(minimized, "glow"), "warning", recapture)
    SetTextRole(state, NamedRegion(minimized, "Text"), "title", recapture)
    SkinWindowAction(state, NamedRegion(minimized, "MaximizeButton"), "maximize", recapture)
end

local function SkinTab(state, tab, selected, recapture)
    if not tab then return end
    if type(selected) ~= "boolean" then selected = IsTabSelected(tab) end
    TrackSuffixes(state, tab, threeSliceSuffixes, "buttonFillAlt")
    TrackSuffixes(state, tab, activeSuffixes, "active", recapture)
    TrackSuffixes(state, tab, highlightSuffixes, "hover", recapture)
    TrackTexture(state, NamedRegion(tab, "glow"), "warning", recapture)
    TrackFlashTextures(state, Call(NamedRegion(tab, "Flash"), "GetRegions"))
    SetTextRole(state, NamedRegion(tab, "Text") or Call(tab, "GetFontString"),
        selected and "title" or "text", recapture)

    local name = Call(tab, "GetName")
    local frameName = type(name) == "string" and name:match("^(ChatFrame%d+)Tab$")
    if frameName then
        SkinMinimizedFrame(state, _G[frameName .. "Minimized"], recapture)
    end
end

local SkinEditBox

local function AnyActive()
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then return true end
    end
    return false
end

-- Native chat hooks can fire in combat; they defer one full recapture instead.
local function DeferIfCombat()
    if not NS.IsCombatLocked() then return false end
    if AnyActive() then NS.CombatGate.RunOrDefer(REFRESH_KEY, RefreshAll) end
    return true
end

-- ChatFrameEditBoxMixin is copied onto each edit box when it is created, so
-- a hook on the mixin table never reaches the edit boxes that existed before
-- this load-on-demand addon. Hook each skinned instance instead.
local function OnEditBoxHeader(editBox)
    if DeferIfCombat() then return end
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then SkinEditBox(state, editBox, true) end
    end
end

-- Every chat hook runs inside Blizzard's own call (FCFTab_UpdateColors runs
-- once per tab in FCFDock_UpdateTabs's loop), so each is its own error boundary.
local function OnEditBoxHeaderHook(editBox)
    Dispatch(OnEditBoxHeader, editBox)
end

local hookedEditBoxes = setmetatable({}, { __mode = "k" })

SkinEditBox = function(state, editBox, recapture)
    if not editBox then return end
    TrackSuffixes(state, editBox, editBoxSuffixes, "input")
    TrackSuffixes(state, editBox, editBoxFocusSuffixes, "active", recapture)
    TrackButtonTextures(state, NamedRegion(editBox, "Language"),
        "checkmark", "pressed", "hover")
    if not hookedEditBoxes[editBox] and HasMethod(editBox, "UpdateHeader") then
        hooksecurefunc(editBox, "UpdateHeader", OnEditBoxHeaderHook)
        hookedEditBoxes[editBox] = true
    end
end

local function SkinChatFrame(state, frame, recapture)
    state.frames[frame] = true
    SkinFrameChrome(state, frame, recapture)

    local buttonFrame = Field(frame, "buttonFrame") or NamedRegion(frame, "ButtonFrame")
    SkinFrameChrome(state, buttonFrame, recapture)
    SkinWindowAction(state, Field(buttonFrame, "minimizeButton")
        or NamedRegion(buttonFrame, "MinimizeButton"), "minimize", recapture)
    TrackButtonTextures(state, Field(frame, "ResizeButton"),
        "border", "pressed", "hover")
    TrackButtonTextures(state, Field(frame, "ScrollToBottomButton"),
        "blizzardArrow", "pressed", "hover")
    SkinEditBox(state, Field(frame, "editBox") or NamedRegion(frame, "EditBox"), recapture)

    local name = Call(frame, "GetName")
    if type(name) == "string" then
        SkinTab(state, _G[name .. "Tab"], nil, recapture)
        SkinMinimizedFrame(state, _G[name .. "Minimized"], recapture)
    end
end

local function SkinDock(state, recapture)
    local dock = GeneralDockManager
    TrackTexture(state, Field(dock, "insertHighlight")
        or NamedRegion(dock, "InsertHighlight"), "active", recapture)
    TrackButtonTextures(state, Field(dock, "overflowButton")
        or NamedRegion(dock, "OverflowButton"),
        "blizzardArrow", "pressed", "blizzardExpandHover")
end

-- These controls live beside the primary chat frame but are not children of
-- the ScrollingMessageFrame itself. Their combined button/icon atlases are
-- source-verified in FloatingChatFrameVoiceChat.xml and PropertyButton.xml;
-- recoloring keeps the voice/channel glyphs intact while removing the native
-- gold chrome. No script, click action, visibility state or voice state changes.
local function SkinChatUtilityButtons(state, recapture)
    SkinFrameChrome(state, _G.ChatFrame1ButtonFrame, recapture)
    for index = 1, #utilityButtonNames do
        local button = _G[utilityButtonNames[index]]
        if button then
            TrackButtonTextures(state, button,
                "blizzardExpand", "blizzardExpandPressed", "blizzardExpandHover", recapture)
            TrackTexture(state, Field(button, "Icon"), "blizzardExpand", recapture)
            TrackTexture(state, Field(button, "Flash"), "warning", recapture)
        end
    end
end

-- The ten built-in windows, any extra CHAT_FRAMES entry (temporary whisper
-- windows) and the GM window, each once and at most MAX_CHAT_FRAMES in total.
local function SkinChatFrames(state, recapture)
    local seen, count = {}, 0
    local function Visit(frame)
        if not frame or seen[frame] or count >= MAX_CHAT_FRAMES then return end
        seen[frame] = true
        count = count + 1
        SkinChatFrame(state, frame, recapture)
    end
    for index = 1, BUILTIN_CHAT_WINDOWS do Visit(_G["ChatFrame" .. index]) end
    for _, name in pairs(CHAT_FRAMES) do
        if type(name) == "string" then Visit(_G[name]) end
    end
    Visit(_G.GMChatFrame)
end

local function ApplyAllNow(state, recapture)
    if not state or not state.active or NS.IsCombatLocked() then return false end
    SkinChatFrames(state, recapture)
    SkinDock(state, recapture)
    SkinChatUtilityButtons(state, recapture)
    TrackButtonTextures(state, _G.ChatFrameMenuButton,
        "blizzardExpand", "blizzardExpandPressed", "blizzardExpandHover", recapture)
    ApplyMessageColors(state)
    return true
end

local function OnTabColors(tab, selected)
    if DeferIfCombat() then return end
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then SkinTab(state, tab, selected == true, true) end
    end
end

local function OnWindowColor(frame)
    if DeferIfCombat() then return end
    local buttonFrame = Field(frame, "buttonFrame") or NamedRegion(frame, "ButtonFrame")
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then
            SkinFrameChrome(state, frame, true)
            SkinFrameChrome(state, buttonFrame, true)
        end
    end
end

local function OnTemporaryWindow()
    if DeferIfCombat() then return end
    RefreshAll()
end

-- Someone else set this category's colour (the player, another addon, the
-- colour picker's live preview or its Cancel, "Restore chat colors"): from
-- now on, for the rest of the session, it is theirs, whatever colour it
-- shows, and nothing is left to put back. Only bookkeeping, so it also runs
-- in combat.
local function OnMessageColorChanged(chatType)
    if changingChatColor or not messageColorRoles[chatType] then return end
    changedExternally[chatType] = true
    leftovers[chatType] = nil
    for _, state in pairs(ChatFramesSkin.owners) do
        local colorState = state.messageColors[chatType]
        if colorState then colorState.released = true end
    end
end

-- These Blizzard functions are called through their globals, so a global
-- post-hook reaches every chat window, including ones created earlier.
local globalHooks = {
    { "FCFTab_UpdateColors", function(tab, selected) Dispatch(OnTabColors, tab, selected) end },
    { "FCF_SetWindowColor", function(frame) Dispatch(OnWindowColor, frame) end },
    { "FCF_OpenTemporaryWindow", function() Dispatch(OnTemporaryWindow) end },
    { "ChangeChatColor", function(chatType) Dispatch(OnMessageColorChanged, chatType) end },
}

local function RegisterHooks()
    for index = 1, #globalHooks do
        local name, callback = globalHooks[index][1], globalHooks[index][2]
        if not ChatFramesSkin.hooks[name] and type(_G[name]) == "function" then
            hooksecurefunc(name, callback)
            ChatFramesSkin.hooks[name] = true
        end
    end
end

-- Recaptures native colors first: every caller follows a Blizzard update.
RefreshAll = function()
    if NS.IsCombatLocked() then return false end
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then ApplyAllNow(state, true) end
    end
    return true
end

-- Theme writes arrive once per slider tick or colour-picker move: they
-- repaint once on the next frame (after combat when it started meanwhile),
-- so a colour drag writes each chat category's persistent colour once.
local messageColorsQueued = false

local function RefreshThemeColors()
    local messages = messageColorsQueued
    messageColorsQueued = false
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then
            RefreshTextColors(state)
            if messages then ApplyMessageColors(state) end
        end
    end
end

function ChatFramesSkin:OnThemeChanged(domain, key)
    if domain == "color" and key ~= "title" and key ~= "text"
        and key ~= "blizzardYellow" then return end
    if domain ~= "color" and domain ~= "theme" and domain ~= "profile" then return end
    if domain ~= "color" or key == "blizzardYellow" then messageColorsQueued = true end
    NS.Registry.QueueJob(RefreshThemeColors)
end

function ChatFramesSkin.Apply(frame, owner)
    if not frame then return false, "missing" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not NS.Safety.CanDecorate(frame, true) then return false, "protected" end
    local state = OwnerState(owner)
    state.active = true
    state.owner = owner
    RegisterHooks()
    ApplyAllNow(state, false)
    return true
end

function ChatFramesSkin.Disable(_, owner)
    if NS.IsCombatLocked() then return false, "combat" end
    local state = ChatFramesSkin.owners[owner]
    if state then
        state.active = false
        RestoreTextColors(state)
        RestoreMessageColors(state)
    end
    NS.Checkmarks.UntrackOwner(owner)
    ChatFramesSkin.owners[owner] = nil
    if not AnyActive() then NS.CombatGate.Cancel(REFRESH_KEY) end
    return true
end

-- Visual regions are rebuilt by Blizzard after logout/reload, but native chat
-- colors persist. Clean only categories currently owned by an active adapter so
-- disabling MapkoSkin before the next login cannot leave its preset behind.
-- PLAYER_LOGOUT: the ledger learns what went back and what could not.
function ChatFramesSkin.RestoreBlizzardMessageColors()
    local restored = 0
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then restored = restored + RestoreMessageColors(state) end
    end
    Ledger().CloseChatColors(leftovers)
    return true, restored
end

NS.Registry.AddListener(ChatFramesSkin, ChatFramesSkin.OnThemeChanged)

return ChatFramesSkin
