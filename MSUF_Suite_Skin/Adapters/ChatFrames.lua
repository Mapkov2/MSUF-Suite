local _, NS = ...

-- Clean-room Blizzard chat adapter verified against wow-ui-source upstream/ptr
-- a1f5e990. Hyperlinks, player/channel/class colors, conversation icons,
-- docking, Edit Mode placement and secure chat attributes remain Blizzard-owned.
-- Exact decorative FloatingChatFrame/EditBox regions plus Blizzard's SYSTEM and
-- ordinary NPC speech colors are recolored through their native OOC color path.
local ChatFramesSkin = { owners = {}, hooks = {} }
NS.ChatFramesSkin = ChatFramesSkin

local Field = NS.Safety.Field
local Call = NS.Safety.Call
local Public = NS.Safety.Public

local REFRESH_KEY = "chat-frames:refresh"
local BUILTIN_CHAT_WINDOWS = 10
local MAX_CHAT_FRAMES = 64
local COLOR_TOLERANCE = 0.015
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
-- the frame-local chrome below. These are Retail's clean-profile defaults;
-- restoring them prevents a MapkoSkin preset from surviving a later addon
-- disable. Keep this list deliberately limited to the categories we change.
local blizzardMessageDefaults = {
    SYSTEM = { 1, 1, 0 },
    MONSTER_SAY = { 1, 1, 159 / 255 },
    MONSTER_PARTY = { 170 / 255, 170 / 255, 1 },
}

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

local function Near(left, right)
    return math.abs(left - right) <= COLOR_TOLERANCE
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

local function SameRGB(left, right)
    return left ~= nil and right ~= nil
        and Near(left[1], right[1]) and Near(left[2], right[2]) and Near(left[3], right[3])
end

local function ChangeMessageColor(chatType, color)
    local change = _G.ChangeChatColor
    if type(change) ~= "function" or not color then return false end
    changingChatColor = true
    change(chatType, color[1], color[2], color[3])
    changingChatColor = false
    return true
end

local function ApplyMessageColor(state, chatType, recapture)
    local role = messageColorRoles[chatType]
    local current = role and ReadMessageColor(chatType)
    if not current then return false end

    local colorState = state.messageColors[chatType]
    if not colorState then
        colorState = { original = current, role = role }
        state.messageColors[chatType] = colorState
    elseif recapture and not SameRGB(current, colorState.applied) then
        -- A user or Blizzard changed this chat category after MapkoSkin.
        -- Preserve that latest native choice for cooperative disable/restore.
        colorState.original = current
    end

    local r, g, b = NS.Theme.GetColor(role)
    local applied = { r, g, b }
    colorState.role = role
    if SameRGB(current, applied) or ChangeMessageColor(chatType, applied) then
        colorState.applied = applied
        return true
    end
    return false
end

local function ApplyMessageColors(state, recapture)
    for chatType in pairs(messageColorRoles) do
        ApplyMessageColor(state, chatType, recapture)
    end
end

local function RestoreMessageColors(state)
    local restored = 0
    for chatType, colorState in pairs(state.messageColors) do
        local nativeDefault = blizzardMessageDefaults[chatType]
        -- Fail closed if another addon changed the category after MapkoSkin.
        -- When our value still owns it, always restore Blizzard's clean default
        -- rather than a possibly contaminated value captured on this login.
        if nativeDefault and SameRGB(ReadMessageColor(chatType), colorState.applied)
            and ChangeMessageColor(chatType, nativeDefault) then
            restored = restored + 1
        end
    end
    state.messageColors = {}
    return restored
end

-- Text colors ----------------------------------------------------------------

local function ReadTextColor(fontString)
    local r, g, b, a = Call(fontString, "GetTextColor")
    if type(r) ~= "number" or not Public(r) or not Public(g)
        or not Public(b) or not Public(a) then
        return nil
    end
    return r, g, b, tonumber(a) or 1
end

local function SameColor(color, r, g, b, a)
    return color[1] ~= nil and r ~= nil
        and Near(color[1], r) and Near(color[2], g) and Near(color[3], b) and Near(color[4], a)
end

local function ApplyTextRole(fontString, textState)
    local r, g, b, a = NS.Theme.GetColor(textState.role)
    fontString:SetTextColor(r, g, b, a)
    local applied = textState.applied
    applied[1], applied[2], applied[3], applied[4] = r, g, b, a
end

local function SetTextRole(state, fontString, role, recapture)
    if type(Field(fontString, "SetTextColor")) ~= "function" then return false end
    local r, g, b, a = ReadTextColor(fontString)
    if not r then return false end
    local textState = state.textStates[fontString]
    if not textState then
        textState = { original = { r, g, b, a }, applied = {} }
        state.textStates[fontString] = textState
    elseif recapture and not SameColor(textState.applied, r, g, b, a) then
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
        if type(Field(fontString, "SetTextColor")) == "function" then
            ApplyTextRole(fontString, textState)
        end
    end
end

local function RestoreTextColors(state)
    for fontString, textState in pairs(state.textStates) do
        if SameColor(textState.applied, ReadTextColor(fontString)) then
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
        if type(Field(texture, "IsDesaturated")) == "function" then
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

local hookedEditBoxes = setmetatable({}, { __mode = "k" })

SkinEditBox = function(state, editBox, recapture)
    if not editBox then return end
    TrackSuffixes(state, editBox, editBoxSuffixes, "input")
    TrackSuffixes(state, editBox, editBoxFocusSuffixes, "active", recapture)
    TrackButtonTextures(state, NamedRegion(editBox, "Language"),
        "checkmark", "pressed", "hover")
    if not hookedEditBoxes[editBox] and type(Field(editBox, "UpdateHeader")) == "function" then
        hooksecurefunc(editBox, "UpdateHeader", OnEditBoxHeader)
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
    local dock = _G.GeneralDockManager
    if not dock then return end
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
    local names = _G.CHAT_FRAMES
    if type(names) == "table" then
        for _, name in pairs(names) do
            if type(name) == "string" then Visit(_G[name]) end
        end
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
    ApplyMessageColors(state, recapture)
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

local function OnMessageColorChanged(chatType)
    if changingChatColor or not messageColorRoles[chatType] or DeferIfCombat() then return end
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then ApplyMessageColor(state, chatType, true) end
    end
end

-- These Blizzard functions are called through their globals, so a global
-- post-hook reaches every chat window, including ones created earlier.
local globalHooks = {
    { "FCFTab_UpdateColors", OnTabColors },
    { "FCF_SetWindowColor", OnWindowColor },
    { "FCF_OpenTemporaryWindow", OnTemporaryWindow },
    { "ChangeChatColor", OnMessageColorChanged },
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

function ChatFramesSkin:OnThemeChanged(domain, key)
    if domain == "color" and key ~= "title" and key ~= "text"
        and key ~= "blizzardYellow" then return end
    if domain ~= "color" and domain ~= "theme" and domain ~= "profile" then return end
    if DeferIfCombat() then return end
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then
            RefreshTextColors(state)
            if domain ~= "color" or key == "blizzardYellow" then
                ApplyMessageColors(state, false)
            end
        end
    end
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
function ChatFramesSkin.RestoreBlizzardMessageColors()
    local restored = 0
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then restored = restored + RestoreMessageColors(state) end
    end
    return true, restored
end

NS.Registry.AddListener(ChatFramesSkin, ChatFramesSkin.OnThemeChanged)

return ChatFramesSkin
