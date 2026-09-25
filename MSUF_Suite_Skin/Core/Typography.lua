local _, NS = ...

-- Blizzard-wide typeface replacement without frame enumeration.  The engine
-- touches only FontObjects present in the generated Blizzard whitelist and a
-- short, explicit list of Blizzard scrolling-message frames which cache their
-- own font path.  Heights, flags, shadows, colors and justification remain
-- Blizzard-owned.
local Typography = {
    fontStates = setmetatable({}, { __mode = "k" }),
    directStates = setmetatable({}, { __mode = "k" }),
    waiting = {},
    appliedCount = 0,
    directCount = 0,
    lastError = nil,
    startupSettleScheduled = false,
}
NS.Typography = Typography

-- Deferred jobs resolve the current entry points when they run.
local function ApplyConfigured()
    Typography.ApplyConfigured()
end

local function Restore()
    Typography.Restore()
end

NS.FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" }

local faceLabels = {
    friz = "Friz Quadrata",
    arial = "Arial Narrow",
    morpheus = "Morpheus",
    skurri = "Skurri",
    sharedMedia = "SharedMedia catalog",
    custom = "Custom path",
}

local specialPrefixes = {
    "Combat", "Damage", "Fancy", "Invoice", "Mail", "Movie", "Number",
    "Price", "Quest", "Splash", "WorldMap", "Zone",
}

local loadOnDemandOwners = {
    "Blizzard_PlayerChoice",
    "Blizzard_BoostTutorial",
    "Blizzard_Kiosk",
    "Blizzard_Communities",
}

local function IsLoaded(addon)
    if not C_AddOns or type(C_AddOns.IsAddOnLoaded) ~= "function" then
        return false
    end
    local first, second = C_AddOns.IsAddOnLoaded(addon)
    return second == true or (second == nil and first == true)
end

local function LocaleFallback(kind)
    local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
    if locale == "ruRU" then
        if kind == "morpheus" then return "Fonts\\MORPHEUS_CYR.TTF" end
        if kind == "skurri" then return "Fonts\\SKURRI_CYR.TTF" end
        return "Fonts\\FRIZQT___CYR.TTF"
    end
    if locale == "koKR" then
        return kind == "skurri" and "Fonts\\K_Damage.TTF" or "Fonts\\2002.TTF"
    end
    if locale == "zhCN" then
        return kind == "skurri" and "Fonts\\ARKai_C.ttf" or "Fonts\\ARKai_T.ttf"
    end
    if locale == "zhTW" then
        return kind == "skurri" and "Fonts\\bKAI00M.TTF" or "Fonts\\blei00d.TTF"
    end
    if kind == "arial" then return "Fonts\\ARIALN.TTF" end
    if kind == "morpheus" then return "Fonts\\MORPHEUS.TTF" end
    if kind == "skurri" then return "Fonts\\skurri.ttf" end
    return "Fonts\\FRIZQT__.TTF"
end

local function ConfiguredPath()
    local config = NS.DB and NS.DB.typography
    if not config then
        return nil
    end
    if config.face == "custom" then
        local path = tostring(config.customPath or ""):match("^%s*(.-)%s*$")
        return path ~= "" and path or nil
    end
    if config.face == "sharedMedia" then
        return NS.SharedMedia and NS.SharedMedia.FetchFont(config.sharedMediaFont) or nil
    end
    return LocaleFallback(config.face)
end

local selectionPrefix = "lsm:"

function Typography.GetSelection()
    local config = NS.DB and NS.DB.typography
    if not config then return "friz" end
    if config.face == "sharedMedia" then
        return selectionPrefix .. tostring(config.sharedMediaFont or "")
    end
    return config.face or "friz"
end

function Typography.GetSelectionValues()
    local values = { "friz", "arial", "morpheus", "skurri" }
    local fonts = Typography.GetSharedMediaFontNames()
    for index = 1, #fonts do
        values[#values + 1] = selectionPrefix .. fonts[index]
    end
    values[#values + 1] = "custom"
    return values
end

function Typography.GetSelectionLabel(selection)
    if type(selection) == "string" and selection:sub(1, #selectionPrefix) == selectionPrefix then
        return selection:sub(#selectionPrefix + 1)
    end
    return faceLabels[selection] or tostring(selection)
end

function Typography.GetSelectionPath(selection)
    if type(selection) ~= "string" then return nil end
    if selection:sub(1, #selectionPrefix) == selectionPrefix then
        return NS.SharedMedia and NS.SharedMedia.FetchFont(selection:sub(#selectionPrefix + 1)) or nil
    end
    if selection == "custom" then
        local path = NS.DB and NS.DB.typography and tostring(NS.DB.typography.customPath or "") or ""
        path = path:match("^%s*(.-)%s*$") or ""
        return path ~= "" and path or nil
    end
    return LocaleFallback(selection)
end

function Typography.SetSelection(selection)
    if NS.IsCombatLocked() or type(selection) ~= "string" or not NS.DB then return false end
    if selection:sub(1, #selectionPrefix) == selectionPrefix then
        local name = selection:sub(#selectionPrefix + 1)
        if not (NS.SharedMedia and NS.SharedMedia.FetchFont(name)) then return false end
        NS.DB.typography.sharedMediaFont = name
        NS.DB.typography.face = "sharedMedia"
    elseif selection == "custom" or selection == "friz" or selection == "arial"
        or selection == "morpheus" or selection == "skurri" then
        NS.DB.typography.face = selection
    else
        return false
    end
    Typography.ApplyConfigured()
    return true
end

local function IsSpecial(name)
    for index = 1, #specialPrefixes do
        if name:find("^" .. specialPrefixes[index]) then
            return true
        end
    end
    return false
end

local function ReadFont(object)
    local path, height, flags = NS.Safety.Call(object, "GetFont")
    if not NS.Safety.Public(path) or not NS.Safety.Public(height)
        or type(path) ~= "string" or type(height) ~= "number" or height <= 0 then
        return nil
    end
    return path, height, flags or ""
end

local function NormalizePath(path)
    return type(path) == "string" and path:gsub("/", "\\"):lower() or ""
end

local function ApplyObject(object, path, states)
    if not object or type(object.SetFont) ~= "function" then
        return false
    end
    local currentPath, height, flags = ReadFont(object)
    if not currentPath then
        return false
    end
    local state = states[object]
    if not state then
        state = { originalPath = currentPath }
        states[object] = state
    end
    -- SetFont returns false for a file it cannot load; the path read back
    -- confirms that the object really switched.
    local appliedPath = object:SetFont(path, height, flags) ~= false and ReadFont(object) or nil
    if NormalizePath(appliedPath) ~= NormalizePath(path) then
        object:SetFont(currentPath, height, flags)
        return false
    end
    state.lastPath = appliedPath
    return true
end

local function RestoreObject(object, state)
    local currentPath, height, flags = ReadFont(object)
    if not currentPath or NormalizePath(currentPath) ~= NormalizePath(state.lastPath) then
        return false
    end
    return object:SetFont(state.originalPath, height, flags) ~= false
end

local function RestoreTracked(states)
    local restored = 0
    for object, state in pairs(states) do
        if RestoreObject(object, state) then restored = restored + 1 end
        states[object] = nil
    end
    return restored
end

local function BlizzardFontSet()
    local set = {}
    for index = 1, #(NS.BlizzardFontNames or {}) do
        set[NS.BlizzardFontNames[index]] = true
    end
    return set
end

local function ApplyFontObjects(path)
    local names = type(GetFonts) == "function" and GetFonts() or nil
    if type(names) ~= "table" then
        return 0
    end
    local allowed = BlizzardFontSet()
    local includeSpecial = NS.DB.typography.includeSpecial ~= false
    local count = 0
    for index = 1, #names do
        local name = names[index]
        if allowed[name] and (includeSpecial or not IsSpecial(name)) then
            local object = _G[name]
            if ApplyObject(object, path, Typography.fontStates) then
                count = count + 1
            end
        end
    end
    return count
end

local function AddDirectTarget(target, list, seen)
    if target and not seen[target] and type(target.GetFont) == "function"
        and type(target.SetFont) == "function" then
        seen[target] = true
        list[#list + 1] = target
    end
end

local function DirectTargets()
    local targets, seen = {}, setmetatable({}, { __mode = "k" })
    local total = tonumber(_G.NUM_CHAT_WINDOWS) or 10
    for index = 1, total do
        AddDirectTarget(_G["ChatFrame" .. index], targets, seen)
    end
    AddDirectTarget(_G.DEFAULT_CHAT_FRAME, targets, seen)
    AddDirectTarget(_G.GMChatFrame, targets, seen)

    local communities = _G.CommunitiesFrame
    local chat = communities and communities.Chat
    AddDirectTarget(chat and chat.MessageFrame, targets, seen)

    local console = _G.DeveloperConsole
    AddDirectTarget(console and console.EditBox, targets, seen)
    AddDirectTarget(console and console.MessageFrame, targets, seen)
    return targets
end

local function ApplyDirect(path)
    if NS.DB.typography.applyChat == false then
        return 0
    end
    local count = 0
    local targets = DirectTargets()
    for index = 1, #targets do
        if ApplyObject(targets[index], path, Typography.directStates) then
            count = count + 1
        end
    end
    return count
end

local function ScheduleLateFonts()
    if not EventUtil or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then
        return
    end
    for index = 1, #loadOnDemandOwners do
        local addon = loadOnDemandOwners[index]
        if not IsLoaded(addon) and not Typography.waiting[addon] then
            Typography.waiting[addon] = true
            EventUtil.ContinueOnAddOnLoaded(addon, function()
                Typography.waiting[addon] = nil
                if NS.DB and NS.DB.enabled and NS.DB.typography.enabled then
                    NS.CombatGate.RunOrDefer("typography:late", ApplyConfigured)
                end
            end)
        end
    end
end

local function ScheduleStartupSettle()
    if Typography.startupSettleScheduled or not EventUtil
        or type(EventUtil.ContinueAfterAllEvents) ~= "function" then
        return
    end
    Typography.startupSettleScheduled = true
    EventUtil.ContinueAfterAllEvents(function()
        if NS.DB and NS.DB.enabled and NS.DB.typography.enabled then
            NS.CombatGate.RunOrDefer("typography:startup-settle", ApplyConfigured)
        end
    end, "PLAYER_ENTERING_WORLD")
end

function Typography.ApplyConfigured()
    if not NS.DB or not NS.DB.typography then
        return false, "uninitialized"
    end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("typography:apply", ApplyConfigured)
        return false, "combat"
    end
    if not NS.DB.enabled or not NS.DB.typography.enabled then
        return Typography.Restore()
    end
    local path = ConfiguredPath()
    if not path then
        RestoreTracked(Typography.fontStates)
        RestoreTracked(Typography.directStates)
        Typography.appliedCount = 0
        Typography.directCount = 0
        Typography.lastError = "invalid-path"
        return false, "invalid-path"
    end
    -- Reconcile exclusions and direct-chat toggles first. This is an explicit
    -- OOC settings/load action, never a recurring update path.
    RestoreTracked(Typography.fontStates)
    RestoreTracked(Typography.directStates)
    local fonts = ApplyFontObjects(path)
    local direct = ApplyDirect(path)
    Typography.appliedCount = fonts
    Typography.directCount = direct
    if fonts > 0 then
        Typography.lastError = nil
    else
        Typography.lastError = "font-unavailable"
    end
    ScheduleLateFonts()
    ScheduleStartupSettle()
    if NS.CharacterDetails then NS.CharacterDetails.RefreshFonts() end
    if NS.CharacterStats then NS.CharacterStats.RefreshFonts() end
    return fonts > 0, Typography.lastError
end

function Typography.Restore()
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("typography:restore", Restore)
        return false, "combat"
    end
    local restored = RestoreTracked(Typography.fontStates)
        + RestoreTracked(Typography.directStates)
    Typography.appliedCount = 0
    Typography.directCount = 0
    Typography.lastError = nil
    NS.CombatGate.Cancel("typography:apply")
    NS.CombatGate.Cancel("typography:late")
    NS.CombatGate.Cancel("typography:shared-media")
    if NS.CharacterDetails then NS.CharacterDetails.RefreshFonts() end
    if NS.CharacterStats then NS.CharacterStats.RefreshFonts() end
    return true, restored
end

local function SetValue(key, value)
    if NS.IsCombatLocked() or not NS.DB or not NS.DB.typography then
        return false
    end
    NS.DB.typography[key] = value
    Typography.ApplyConfigured()
    return true
end

function Typography.SetEnabled(enabled)
    return SetValue("enabled", enabled == true)
end

function Typography.SetFace(face)
    for index = 1, #NS.FontFaces do
        if NS.FontFaces[index] == face then
            return SetValue("face", face)
        end
    end
    return false
end

function Typography.SetCustomPath(path)
    return SetValue("customPath", tostring(path or ""))
end

function Typography.SetSharedMediaFont(name)
    local path = NS.SharedMedia and NS.SharedMedia.FetchFont(name)
    if not path then return false end
    NS.DB.typography.sharedMediaFont = name
    if NS.DB.typography.face == "sharedMedia" then Typography.ApplyConfigured() end
    return true
end

function Typography.GetSharedMediaFontNames()
    return NS.SharedMedia and NS.SharedMedia.GetFontNames() or { "Friz Quadrata TT" }
end

function Typography.SetApplyChat(enabled)
    return SetValue("applyChat", enabled == true)
end

function Typography.SetIncludeSpecial(enabled)
    return SetValue("includeSpecial", enabled == true)
end

function Typography.GetFaceLabel(face)
    return faceLabels[face] or tostring(face)
end

function Typography.GetStatus()
    return {
        enabled = NS.DB and NS.DB.typography and NS.DB.typography.enabled == true,
        face = NS.DB and NS.DB.typography and NS.DB.typography.face or "friz",
        path = ConfiguredPath(),
        fontObjects = Typography.appliedCount,
        directFrames = Typography.directCount,
        error = Typography.lastError,
    }
end

return Typography
