local _, NS = ...

-- Clean-room Blizzard chat adapter verified against wow-ui-source upstream/ptr
-- a1f5e990. Hyperlinks, player/channel/class colors, conversation icons,
-- docking, Edit Mode placement and secure chat attributes remain Blizzard-owned.
-- Exact decorative FloatingChatFrame/EditBox regions plus Blizzard's SYSTEM and
-- ordinary NPC speech colors are recolored through their native OOC color path.
local ChatFramesSkin = { owners = {}, hooks = {} }
NS.ChatFramesSkin = ChatFramesSkin

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
-- the frame-local chrome below.  These are Retail's clean-profile defaults;
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

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function Getter(object, method)
    local getter = SafeField(object, method)
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter, object)
    return ok and value or nil
end

local function NamedRegion(object, suffix)
    local direct = SafeField(object, suffix)
    if direct then return direct end
    local name = Getter(object, "GetName")
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

local function ReadMessageColor(chatType)
    local info = SafeField(_G.ChatTypeInfo, chatType)
    local r = SafeField(info, "r")
    local g = SafeField(info, "g")
    local b = SafeField(info, "b")
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    return { r, g, b }
end

local function SameRGB(left, right)
    if not left or not right then return false end
    for index = 1, 3 do
        if type(left[index]) ~= "number" or type(right[index]) ~= "number"
            or math.abs(left[index] - right[index]) > 0.015 then
            return false
        end
    end
    return true
end

local function ChangeMessageColor(chatType, color)
    local change = SafeField(_G, "ChangeChatColor")
    if type(change) ~= "function" or not color then return false end
    changingChatColor = true
    local ok = pcall(change, chatType, color[1], color[2], color[3])
    changingChatColor = false
    return ok == true
end

local function ApplyMessageColor(state, chatType, recapture)
    local role = messageColorRoles[chatType]
    if not role then return false end
    local current = ReadMessageColor(chatType)
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
    if SameRGB(current, applied) then
        colorState.applied = applied
        return true
    end
    if ChangeMessageColor(chatType, applied) then
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
        local current = ReadMessageColor(chatType)
        local nativeDefault = blizzardMessageDefaults[chatType]
        -- Fail closed if another addon changed the category after MapkoSkin.
        -- When our value still owns it, always restore Blizzard's clean default
        -- rather than a possibly contaminated value captured on this login.
        if nativeDefault and SameRGB(current, colorState.applied)
            and ChangeMessageColor(chatType, nativeDefault) then
            restored = restored + 1
        end
    end
    state.messageColors = {}
    return restored
end

local function ReadTextColor(fontString)
    local getter = SafeField(fontString, "GetTextColor")
    if type(getter) ~= "function" then return nil end
    local ok, r, g, b, a = pcall(getter, fontString)
    if not ok or type(r) ~= "number" then return nil end
    return { r, g, b, tonumber(a) or 1 }
end

local function SameColor(left, right)
    if not left or not right then return false end
    for index = 1, 4 do
        if type(left[index]) ~= "number" or type(right[index]) ~= "number"
            or math.abs(left[index] - right[index]) > 0.015 then
            return false
        end
    end
    return true
end

local function SetTextRole(state, fontString, role, recapture)
    if not fontString or type(SafeField(fontString, "SetTextColor")) ~= "function" then
        return false
    end
    local current = ReadTextColor(fontString)
    if not current then return false end
    local textState = state.textStates[fontString]
    if not textState then
        textState = { original = current }
        state.textStates[fontString] = textState
    elseif recapture and not SameColor(current, textState.applied) then
        -- Preserve Blizzard's latest native tab color for cooperative restore.
        textState.original = current
    end
    local applied = { NS.Theme.GetColor(role) }
    local ok = pcall(fontString.SetTextColor, fontString, unpack(applied))
    if ok then
        textState.role = role
        textState.applied = applied
    end
    return ok == true
end

local function RefreshTextColors(state)
    for fontString, textState in pairs(state.textStates) do
        if type(SafeField(fontString, "SetTextColor")) == "function" then
            local applied = { NS.Theme.GetColor(textState.role) }
            if pcall(fontString.SetTextColor, fontString, unpack(applied)) then
                textState.applied = applied
            end
        end
    end
end

local function RestoreTextColors(state)
    for fontString, textState in pairs(state.textStates) do
        local current = ReadTextColor(fontString)
        if textState.original and SameColor(current, textState.applied)
            and type(SafeField(fontString, "SetTextColor")) == "function" then
            pcall(fontString.SetTextColor, fontString, unpack(textState.original))
        end
    end
    state.textStates = setmetatable({}, { __mode = "k" })
end

local function TrackTexture(state, texture, role, recapture)
    if not texture or not NS.Checkmarks then return false end
    if not state.textureCaptured[texture] then
        state.textureCaptured[texture] = true
        local getter = SafeField(texture, "IsDesaturated")
        if type(getter) == "function" then
            local ok, value = pcall(getter, texture)
            if ok then state.nativeDesaturation[texture] = value == true end
        end
    end
    if recapture and type(NS.Checkmarks.UntrackTexture) == "function" then
        NS.Checkmarks.UntrackTexture(texture, state.owner)
        -- Blizzard's refresh functions rewrite vertex RGB but do not own the
        -- desaturation flag. Rebase from the latest RGB while retaining the
        -- native desaturation state captured before MapkoSkin touched it.
        local originalDesaturated = state.nativeDesaturation[texture]
        if originalDesaturated ~= nil
            and type(SafeField(texture, "SetDesaturated")) == "function" then
            pcall(texture.SetDesaturated, texture, originalDesaturated)
        end
    end
    if type(NS.Checkmarks.TrackTexture) ~= "function" then return false end
    return NS.Checkmarks.TrackTexture(texture, state.owner, role)
end

local function TrackButtonTextures(state, button, normalRole, pushedRole, hoverRole, recapture)
    if not button then return end
    TrackTexture(state, Getter(button, "GetNormalTexture"), normalRole, recapture)
    TrackTexture(state, Getter(button, "GetPushedTexture"), pushedRole or normalRole, recapture)
    TrackTexture(state, Getter(button, "GetDisabledTexture"), "disabled", recapture)
    TrackTexture(state, Getter(button, "GetHighlightTexture"), hoverRole or normalRole, recapture)
end

local function SkinWindowAction(state, button, kind, recapture)
    if not button then return end
    if NS.WindowActionSkin then
        local action, reason = NS.WindowActionSkin.Apply(button, state.owner, kind)
        if action then return end
        if reason == "owned by another adapter"
            or reason == "state texture ownership changed" then return end
    end
    -- Protected or otherwise unsupported chat controls retain the previous
    -- reversible native-art tint instead of losing state feedback.
    TrackButtonTextures(state, button,
        "blizzardExpand", "blizzardExpandPressed", "blizzardExpandHover", recapture)
end

local function SkinFrameChrome(state, frame, recapture)
    if not frame then return end
    TrackTexture(state, NamedRegion(frame, "Background"), "background", recapture)
    for index = 1, #frameBorderSuffixes do
        TrackTexture(state, NamedRegion(frame, frameBorderSuffixes[index]), "border", recapture)
    end
end

local function SkinFlash(state, flash)
    if not flash or type(SafeField(flash, "GetRegions")) ~= "function" then return end
    pcall(function()
        local regions = { flash:GetRegions() }
        for index = 1, #regions do
            if Getter(regions[index], "GetObjectType") == "Texture" then
                TrackTexture(state, regions[index], "warning")
            end
        end
    end)
end

local function IsTabSelected(tab)
    local active = NamedRegion(tab, "ActiveMiddle")
        or NamedRegion(tab, "ActiveLeft") or NamedRegion(tab, "ActiveRight")
    local shown = active and SafeField(active, "IsShown")
    if type(shown) ~= "function" then return false end
    local ok, selected = pcall(shown, active)
    return ok and selected == true
end

local function SkinMinimizedFrame(state, minimized, recapture)
    if not minimized then return end
    for _, suffix in ipairs({ "Left", "Middle", "Right" }) do
        TrackTexture(state, NamedRegion(minimized, suffix), "buttonFillAlt")
    end
    for _, suffix in ipairs({ "HighlightLeft", "HighlightMiddle", "HighlightRight" }) do
        TrackTexture(state, NamedRegion(minimized, suffix), "hover", recapture)
    end
    TrackTexture(state, NamedRegion(minimized, "glow"), "warning", recapture)
    SetTextRole(state, NamedRegion(minimized, "Text"), "title", recapture)
    SkinWindowAction(state, SafeField(minimized, "MaximizeButton")
        or NamedRegion(minimized, "MaximizeButton"), "maximize", recapture)
end

local function SkinTab(state, tab, selected, recapture)
    if not tab then return end
    if type(selected) ~= "boolean" then selected = IsTabSelected(tab) end
    for _, suffix in ipairs({ "Left", "Middle", "Right" }) do
        TrackTexture(state, NamedRegion(tab, suffix), "buttonFillAlt")
    end
    for _, suffix in ipairs({ "ActiveLeft", "ActiveMiddle", "ActiveRight" }) do
        TrackTexture(state, NamedRegion(tab, suffix), "active", recapture)
    end
    for _, suffix in ipairs({ "HighlightLeft", "HighlightMiddle", "HighlightRight" }) do
        TrackTexture(state, NamedRegion(tab, suffix), "hover", recapture)
    end
    TrackTexture(state, NamedRegion(tab, "glow"), "warning", recapture)
    SkinFlash(state, NamedRegion(tab, "Flash"))
    SetTextRole(state, NamedRegion(tab, "Text") or Getter(tab, "GetFontString"),
        selected and "title" or "text", recapture)

    local name = Getter(tab, "GetName")
    if type(name) == "string" then
        local frameName = name:match("^(ChatFrame%d+)Tab$")
        if frameName then SkinMinimizedFrame(state, _G[frameName .. "Minimized"], recapture) end
    end
end

local function SkinEditBox(state, editBox, recapture)
    if not editBox then return end
    for _, suffix in ipairs({ "Left", "Mid", "Right" }) do
        TrackTexture(state, NamedRegion(editBox, suffix), "input")
    end
    for _, suffix in ipairs({ "FocusLeft", "FocusMid", "FocusRight" }) do
        TrackTexture(state, NamedRegion(editBox, suffix), "active", recapture)
    end
    TrackButtonTextures(state, NamedRegion(editBox, "Language"),
        "checkmark", "pressed", "hover")
end

local function SkinChatFrame(state, frame, recapture)
    if not frame then return end
    state.frames[frame] = true
    SkinFrameChrome(state, frame, recapture)

    local buttonFrame = SafeField(frame, "buttonFrame") or NamedRegion(frame, "ButtonFrame")
    SkinFrameChrome(state, buttonFrame, recapture)
    SkinWindowAction(state, SafeField(buttonFrame, "minimizeButton")
        or NamedRegion(buttonFrame, "MinimizeButton"), "minimize", recapture)
    TrackButtonTextures(state, SafeField(frame, "ResizeButton"),
        "border", "pressed", "hover")
    TrackButtonTextures(state, SafeField(frame, "ScrollToBottomButton"),
        "blizzardArrow", "pressed", "hover")
    SkinEditBox(state, SafeField(frame, "editBox") or NamedRegion(frame, "EditBox"), recapture)

    local name = Getter(frame, "GetName")
    if type(name) == "string" then
        SkinTab(state, _G[name .. "Tab"], nil, recapture)
        SkinMinimizedFrame(state, _G[name .. "Minimized"], recapture)
    end
end

local function SkinDock(state, recapture)
    local dock = _G.GeneralDockManager
    if not dock then return end
    TrackTexture(state, SafeField(dock, "insertHighlight")
        or NamedRegion(dock, "InsertHighlight"), "active", recapture)
    local overflow = SafeField(dock, "overflowButton") or NamedRegion(dock, "OverflowButton")
    TrackButtonTextures(state, overflow,
        "blizzardArrow", "pressed", "blizzardExpandHover")
end

-- These controls live beside the primary chat frame but are not children of
-- the ScrollingMessageFrame itself. Their combined button/icon atlases are
-- source-verified in FloatingChatFrameVoiceChat.xml and PropertyButton.xml;
-- recoloring keeps the voice/channel glyphs intact while removing the native
-- gold chrome. No script, click action, visibility state or voice state changes.
local function SkinChatUtilityButtons(state, recapture)
    SkinFrameChrome(state, _G.ChatFrame1ButtonFrame, recapture)
    for _, globalName in ipairs({
        "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton",
        "ChatFrameToggleVoiceMuteButton",
    }) do
        local button = _G[globalName]
        if button then
            TrackButtonTextures(state, button,
                "blizzardExpand", "blizzardExpandPressed",
                "blizzardExpandHover", recapture)
            TrackTexture(state, SafeField(button, "Icon"), "blizzardExpand", recapture)
            TrackTexture(state, SafeField(button, "Flash"), "warning", recapture)
        end
    end
end

local function EnumerateChatFrames(callback)
    local seen, count = setmetatable({}, { __mode = "k" }), 0
    local function Visit(frame)
        if not frame or seen[frame] or count >= MAX_CHAT_FRAMES then return end
        seen[frame] = true
        count = count + 1
        callback(frame)
    end
    for index = 1, BUILTIN_CHAT_WINDOWS do Visit(_G["ChatFrame" .. index]) end
    local names = _G.CHAT_FRAMES
    if type(names) == "table" then
        pcall(function()
            for _, name in pairs(names) do
                if count >= MAX_CHAT_FRAMES then break end
                if type(name) == "string" then Visit(_G[name]) end
            end
        end)
    end
    Visit(_G.GMChatFrame)
end

local function ApplyAllNow(state, recapture)
    if not state or not state.active or NS.IsCombatLocked() then return false end
    EnumerateChatFrames(function(frame) SkinChatFrame(state, frame, recapture) end)
    SkinDock(state, recapture)
    SkinChatUtilityButtons(state, recapture)
    TrackButtonTextures(state, _G.ChatFrameMenuButton,
        "blizzardExpand", "blizzardExpandPressed", "blizzardExpandHover", recapture)
    ApplyMessageColors(state, recapture)
    return true
end

local function AnyActive()
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then return true end
    end
    return false
end

local function DeferRefresh()
    if NS.CombatGate then
        NS.CombatGate.RunOrDefer(REFRESH_KEY, function() RefreshAll(true) end)
    end
end

local function ForEachActive(callback, object, value)
    if NS.IsCombatLocked() then
        if AnyActive() then DeferRefresh() end
        return
    end
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then callback(state, object, value, true) end
    end
end

local function OnTabColors(tab, selected)
    ForEachActive(SkinTab, tab, selected == true)
end

local function OnWindowColor(frame)
    ForEachActive(function(state, target)
        SkinFrameChrome(state, target, true)
        SkinFrameChrome(state, SafeField(target, "buttonFrame")
            or NamedRegion(target, "ButtonFrame"), true)
    end, frame)
end

local function OnEditBoxHeader(editBox)
    ForEachActive(function(state, target)
        SkinEditBox(state, target, true)
    end, editBox)
end

local function OnTemporaryWindow()
    if NS.IsCombatLocked() then
        if AnyActive() then DeferRefresh() end
        return
    end
    RefreshAll(true)
end

local function OnMessageColorChanged(chatType)
    if changingChatColor or not messageColorRoles[chatType] then return end
    if NS.IsCombatLocked() then
        if AnyActive() then DeferRefresh() end
        return
    end
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then ApplyMessageColor(state, chatType, true) end
    end
end

local function RegisterGlobalHook(key, functionName, callback)
    if ChatFramesSkin.hooks[key] or type(hooksecurefunc) ~= "function"
        or type(_G[functionName]) ~= "function" then return false end
    local ok = pcall(function() hooksecurefunc(functionName, callback) end)
    if ok then ChatFramesSkin.hooks[key] = true end
    return ok == true
end

local function RegisterHooks()
    RegisterGlobalHook("tabs", "FCFTab_UpdateColors", OnTabColors)
    RegisterGlobalHook("windowColor", "FCF_SetWindowColor", OnWindowColor)
    RegisterGlobalHook("temporary", "FCF_OpenTemporaryWindow", OnTemporaryWindow)
    RegisterGlobalHook("messageColor", "ChangeChatColor", OnMessageColorChanged)

    local mixin = _G.ChatFrameEditBoxMixin
    if not ChatFramesSkin.hooks.editBox and type(hooksecurefunc) == "function"
        and type(SafeField(mixin, "UpdateHeader")) == "function" then
        local ok = pcall(function()
            hooksecurefunc(mixin, "UpdateHeader", OnEditBoxHeader)
        end)
        if ok then ChatFramesSkin.hooks.editBox = true end
    end
end

RefreshAll = function(recapture)
    if NS.IsCombatLocked() then return false end
    for _, state in pairs(ChatFramesSkin.owners) do
        if state.active then ApplyAllNow(state, recapture == true) end
    end
    return true
end

function ChatFramesSkin:OnThemeChanged(domain, key)
    if domain == "color" and key ~= "title" and key ~= "text"
        and key ~= "blizzardYellow" then return end
    if domain ~= "color" and domain ~= "theme" and domain ~= "profile" then return end
    if NS.IsCombatLocked() then
        if AnyActive() then DeferRefresh() end
        return
    end
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
    if NS.Checkmarks then NS.Checkmarks.UntrackOwner(owner) end
    ChatFramesSkin.owners[owner] = nil
    if not AnyActive() and NS.CombatGate then NS.CombatGate.Cancel(REFRESH_KEY) end
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
