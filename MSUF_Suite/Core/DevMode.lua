local _, Suite = ...
local Animation = Suite.DevBarAnimation
local Dev = {}
Suite.DevMode = Dev

local COMBAT = "addonCombatRestrictionsForced"
local TAINT = "taintLog"
local VERBOSE = "2"
local indicator
-- Force combat last when enabling the batch. Its simulated lockdown can
-- close the options menu. Recovery clears it before changing other CVars.
Dev.restrictions = {
    { key = "addonChatRestrictionsForced", label = "Chat restrictions" },
    { key = "addonMapRestrictionsForced", label = "Map restrictions" },
    { key = "addonEncounterRestrictionsForced", label = "Encounter restrictions" },
    { key = "addonChallengeModeRestrictionsForced", label = "Mythic+ restrictions" },
    { key = "addonPvPMatchRestrictionsForced", label = "PvP match restrictions" },
    { key = COMBAT, label = "Combat restrictions" },
}

function Dev.Read(key)
    local value = C_CVar.GetCVar(key)
    if Suite.IsSecret(value) then return nil, "rejected" end
    if type(value) == "string" and value ~= "" then return value end
end

local function Valid(key, value)
    if key == TAINT then return value == "0" or value == "1" or value == "2" end
    if value ~= "0" and value ~= "1" then return false end
    for _, entry in ipairs(Dev.restrictions) do
        if entry.key == key then return true end
    end
    return false
end

-- Restore logging at addon load, including reloads in combat. SetCVar's
-- public, non-secure CVar checks still apply to taintLog on this path.
local function Apply(key, value, restoringLogging, transition, prepare)
    local current, reason = Dev.Read(key)
    if reason then return false, reason end
    if current == nil then return false, "unsupported" end
    if current == value then
        if prepare then return prepare() end
        return true
    end
    -- Simulated lockdown can make InCombatLockdown true in the open world.
    -- Clear only its own force flag, and only while the player is out of combat.
    if not restoringLogging and Suite.InCombat(transition) then
        if key ~= COMBAT or value ~= "0" or current ~= "1" then return false, "combat" end
        local fighting = UnitAffectingCombat("player")
        if Suite.IsSecret(fighting) or fighting ~= false then return false, "combat" end
    end
    local _, _, _, _, locked, secure, readOnly = C_CVar.GetCVarInfo(key)
    if not Suite.Public(locked) or not Suite.Public(secure) or not Suite.Public(readOnly)
        or locked == true or secure == true or readOnly == true then return false, "rejected" end
    if prepare then
        local ok, failure = prepare()
        if not ok then return false, failure end
    end
    Suite.Dispatch(C_CVar.SetCVar, key, value)
    if Dev.Read(key) == value then return true end
    return false, "rejected"
end

local function SavedCVars()
    local root = Suite.RootDB
    local saved = root and root.devModeCVars
    if type(saved) == "table" then return saved end
end

local function Save(key, value)
    local root = Suite.RootDB
    if not root then return end
    local saved = SavedCVars()
    if value ~= "0" then
        if not saved then
            saved = {}
            root.devModeCVars = saved
        end
        saved[key] = value
    elseif saved then
        saved[key] = nil
        if not next(saved) then root.devModeCVars = nil end
    end
end

local function HasActiveDiagnostics()
    local saved = SavedCVars()
    if not saved then return false end
    for key, value in pairs(saved) do
        if not Suite.IsSecret(key) and not Suite.IsSecret(value) and value ~= "0" and Valid(key, value) then
            local current = Dev.Read(key)
            if current ~= "0" and Valid(key, current) then return true end
        end
    end
    return false
end

local function IndicatorCVarChanged(frame, _, key)
    if Suite.IsSecret(key) or type(key) ~= "string" then return end
    local saved = SavedCVars()
    if not saved then return end
    local lower = key:lower()
    for name in pairs(saved) do
        if not Suite.IsSecret(name) and type(name) == "string" and name:lower() == lower then
            -- Console changes to a tracked CVar also override its reload value.
            local current = Dev.Read(name)
            if Valid(name, current) then Save(name, current) end
            frame:SetShown(HasActiveDiagnostics())
            if not SavedCVars() then frame:UnregisterEvent("CVAR_UPDATE") end
            return
        end
    end
end

local function MakeIndicator()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 8, -8)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(false)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.06, 0.06, 0.08, 0.92)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 4, 0)
    icon:SetTexture("Interface\\AddOns\\MSUF_Suite\\Media\\SuiteIcon.tga")

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    label:SetText(Suite.Text("Dev Mode on"))
    frame:SetSize(label:GetStringWidth() + 28, 22)
    frame:SetScript("OnEvent", IndicatorCVarChanged)
    return frame
end

local function RefreshIndicator()
    local active = HasActiveDiagnostics()
    if not indicator and not active then return end
    indicator = indicator or MakeIndicator()
    indicator:SetShown(active)
    if SavedCVars() then
        indicator:RegisterEvent("CVAR_UPDATE")
    else
        indicator:UnregisterEvent("CVAR_UPDATE")
    end
end

local function SetAndSave(key, value, prepare)
    local ok, reason = Apply(key, value, false, nil, prepare)
    if ok or (value == "0" and reason == "unsupported") then Save(key, value) end
    return ok, reason
end

local function StartLogging()
    local ok, reason = SetAndSave(TAINT, VERBOSE)
    return ok or reason == "unsupported", reason
end

function Dev.Set(key, value)
    if Suite.IsSecret(key) or Suite.IsSecret(value) or not Valid(key, value) then return false, "invalid" end
    local prepare = key ~= TAINT and value == "1" and StartLogging or nil
    local ok, reason = SetAndSave(key, value, prepare)
    RefreshIndicator()
    return ok, reason
end

function Dev.GetTaintReport()
    local host = Suite.HostBridge
    if host and host.TaintReport then return host.TaintReport() end
end

function Dev.SetAll(enabled)
    if not enabled then
        Animation.Stop()
        local report = Dev.GetTaintReport()
        if report then report.Stop() end
    end
    local value = enabled and "1" or "0"
    local any, failure, failedKey = false
    if enabled then
        local ok, reason = StartLogging()
        if not ok then return false, reason, TAINT end
    end
    local function Change(key)
        local ok, reason = SetAndSave(key, value)
        any = any or ok
        if not ok and not failure and reason ~= "unsupported" then failure, failedKey = reason, key end
    end
    if not enabled then Change(COMBAT) end
    for _, entry in ipairs(Dev.restrictions) do
        if enabled or entry.key ~= COMBAT then Change(entry.key) end
    end
    if not enabled then Change(TAINT) end
    RefreshIndicator()
    if failure then return false, failure, failedKey end
    if not any then return false, "unsupported" end
    return true
end

local function Restore(saved, key, restoringLogging, transition)
    local value = saved[key]
    if Suite.IsSecret(value) or value == "0" or not Valid(key, value) then return end
    local ok, reason = Apply(key, value, restoringLogging, transition)
    if reason ~= "unsupported" then Dev.Report(ok, reason, key) end
end

local function HasSavedRestrictions(saved)
    for _, entry in ipairs(Dev.restrictions) do
        local value = saved[entry.key]
        if not Suite.IsSecret(value) and value == "1" then return true end
    end
    return false
end

function Dev.RestoreLogging()
    local saved = SavedCVars()
    if not saved then return end
    if HasSavedRestrictions(saved) then
        -- Upgrade older Dev Mode records that only saved test restrictions.
        local ok, reason = Apply(TAINT, VERBOSE, true)
        if ok then Save(TAINT, VERBOSE) end
        if reason ~= "unsupported" then Dev.Report(ok, reason, TAINT) end
    else
        Restore(saved, TAINT, true)
    end
    -- A client that retained the simulated lockdown would skip Suite startup.
    -- Release that simulation briefly if the player is actually out of combat.
    local forceCombat = saved[COMBAT]
    if not Suite.IsSecret(forceCombat) and forceCombat == "1" and Suite.IsCombatLocked() then
        local fighting = UnitAffectingCombat("player")
        if not Suite.IsSecret(fighting) and fighting == false then
            local ok, reason = Apply(COMBAT, "0")
            if reason ~= "unsupported" then Dev.Report(ok, reason, COMBAT) end
        end
    end
    RefreshIndicator()
end

function Dev.RestoreRestrictions(transition)
    local saved = SavedCVars()
    if not saved then return end
    for _, entry in ipairs(Dev.restrictions) do Restore(saved, entry.key, false, transition) end
    RefreshIndicator()
end

function Dev.Report(ok, reason, key)
    if ok then return end
    if reason == "combat" then
        Suite.Print(Suite.Text("Change diagnostics outside combat."))
    elseif reason == "unsupported" then
        Suite.Print(Suite.Text("This diagnostic setting is unavailable on this client."))
    else
        Suite.Print(Suite.Text("The client refused a diagnostic setting. Check the current values."))
        if key then Suite.Print(key) end
    end
end

local function Command(message)
    if Suite.IsSecret(message) or type(message) ~= "string" then return end
    local command, value = message:lower():match("^%s*(%S*)%s*(%S*)%s*$")
    if command == "" and Suite.Menu.Open("suite_devMode") then return end
    if command == "quest" then
        if Suite.Client.isForever then Suite.DevQuestTurnIn.Command(value)
        else Dev.Report(false, "unsupported") end
        return
    end
    if value == "" and (command == "on" or command == "off") then
        local ok, reason, key = Dev.SetAll(command == "on")
        Dev.Report(ok, reason, key)
        if command == "off" and reason == "rejected" and key == COMBAT then
            Suite.Print("/console addonCombatRestrictionsForced 0")
        end
        if ok then
            if command == "on" then
                Suite.Print(Suite.Text("Supported addon restrictions are forced. Use /msufdev off to stop."))
            else
                Suite.Print(Suite.Text("Forced restrictions and taint logging are off."))
            end
        end
        return
    end
    if command == "log" and value == "" then command, value = "taint", VERBOSE end
    if command == "taint" and Valid(TAINT, value) then
        local ok, reason = Dev.Set(TAINT, value)
        Dev.Report(ok, reason)
        if ok then Suite.Print(Suite.Text("Taint logging level: %s. Log file: Logs/taint.log."):format(value)) end
        return
    end
    Suite.Print(Suite.Text("Use /msufdev to open Dev Mode, /msufdev on or off, or /msufdev taint 0, 1 or 2."))
    Suite.Print("/msufdev log (" .. Suite.Text("Taint logging") .. ")")
    if Suite.Client.isForever then Suite.Print("/msufdev quest on | off | capture | report | latest") end
end

SLASH_MSUFSUITEDEVMODE1 = "/msufdev"
SlashCmdList.MSUFSUITEDEVMODE = Command

-- Temporary root-cause probe: metadata only, no chat text is retained.
do
    local BOX_FIELDS = {
        "GetText", "SetText", "Insert", "AddHistoryLine", "GetAttribute", "SetAttribute",
        "ParseText", "HandleChatType", "ProcessChatType", "SendText", "SendMessage",
        "OnEnterPressed", "OnTextChanged", "OnTextSet", "OnUpdate", "OnChar", "OnSpacePressed",
        "ClearChat", "Deactivate", "UpdateHeader", "ResetChatType", "ResetChatTypeToSticky",
        "OnEditFocusGained", "OnEditFocusLost", "Show", "Hide", "SetFocus", "ClearFocus",
        "setText", "text", "header", "chatFrame", "autoCompleteSource", "autoCompleteParams",
    }
    local GLOBAL_FIELDS = {
        "ChatFrameEditBoxBaseMixin", "ChatFrameEditBoxMixin", "ChatFrameUtil",
        "hash_ChatTypeInfoList", "hash_SlashCmdList", "SlashCmdList", "ChatTypeInfo",
        "ACTIVE_CHAT_EDIT_BOX", "LAST_ACTIVE_CHAT_EDIT_BOX", "CHAT_FOCUS_OVERRIDE", "DEFAULT_CHAT_FRAME",
        "strmatch", "strupper", "strsub", "strfind", "strlen", "AutoCompleteEditBox_OnEnterPressed",
    }
    local UTIL_FIELDS = {
        "ImportAllListsToHash", "OpenChat", "ActivateChat", "DeactivateChat", "ChooseBoxForSend", "SetLastActiveWindow",
    }
    local SOURCE_FIELDS = { "GetText", "SetText", "SetScript", "HookScript", "OnEnterPressed", "ParseText", "ProcessChatType" }

    local function Primitive(value)
        if Suite.IsSecret(value) then return "<secret>" end
        local kind = type(value)
        if kind == "boolean" or kind == "number" or kind == "string" then return value end
    end

    local function Origins(target, fields, shadows)
        if Suite.IsSecret(target) or type(target) ~= "table" then return {} end
        local found = {}
        for _, key in ipairs(fields) do
            local clean, addon = issecurevariable(target, key)
            local origin = { secure = Primitive(clean), addon = Primitive(addon) }
            if shadows then
                local raw = rawget(target, key)
                origin.shadow = not Suite.IsSecret(raw) and raw ~= nil
            end
            found[key] = origin
        end
        return found
    end

    local function Source(callback)
        if Suite.IsSecret(callback) or type(callback) ~= "function" then return end
        -- Function-source metadata is optional; WoW does not expose Lua's debug library.
        local debugger = debug
        if Suite.IsSecret(debugger) or type(debugger) ~= "table" then return end
        local getinfo = debugger.getinfo
        if Suite.IsSecret(getinfo) or type(getinfo) ~= "function" then return end
        local info = getinfo(callback, "S")
        if Suite.IsSecret(info) or type(info) ~= "table" then return end
        local source = Primitive(info.source)
        if type(source) ~= "string" then return end
        -- Only addon file identifiers; dynamic Lua source can contain user text.
        local file = source:match("^@?(Interface/AddOns/[^%s]+%.lua)$")
            or source:match("^@?(Interface/AddOns/[^%s]+%.xml)$")
        return { file = file or "<dynamic-or-native>", line = Primitive(info.linedefined) }
    end

    local function Capture(phase, box)
        if Dev.Read("addonChatRestrictionsForced") ~= "1" or not Suite.RootDB then return end
        local log = Suite.RootDB.devChatTaintProbe
        if type(log) ~= "table" then
            log = { version = 1, entries = {} }
            Suite.RootDB.devChatTaintProbe = log
        end
        local entries = log.entries
        if #entries >= 24 then table.remove(entries, 1) end
        local record = { phase = phase, at = date("%Y-%m-%d %H:%M:%S"), flags = {} }
        entries[#entries + 1] = record
        for _, entry in ipairs(Dev.restrictions) do record.flags[entry.key] = Dev.Read(entry.key) end
        record.globals = Origins(_G, GLOBAL_FIELDS)
        record.util = Origins(ChatFrameUtil, UTIL_FIELDS)
        record.baseMixin = Origins(ChatFrameEditBoxBaseMixin, BOX_FIELDS)
        record.mixin = Origins(ChatFrameEditBoxMixin, BOX_FIELDS)
        record.hashSecret = Primitive(issecrettable(hash_ChatTypeInfoList))
        record.hashAccessible = Primitive(canaccesstable(hash_ChatTypeInfoList))
        record.commandSlots = Origins(hash_ChatTypeInfoList, { "/RELOAD", "/RL", "/SAY", "/MSUFDEV", "/MSUF", "/PVP" })
        record.slashSlots = Origins(hash_SlashCmdList, { "/RELOAD", "/RL", "/SAY", "/MSUFDEV", "/MSUF", "/PVP" })
        record.loaded = {}
        for _, addon in ipairs({ "MSUF_Suite_Chat", "MSUF_Suite_Skin", "EllesmereUIChat", "DaylightUI_Chat", "Aurora" }) do
            record.loaded[addon] = Primitive(C_AddOns.IsAddOnLoaded(addon))
        end
        if Suite.IsSecret(box) or type(box) ~= "table" then return end
        local forbidden = box:IsForbidden()
        if Suite.IsSecret(forbidden) or forbidden then record.boxUnavailable = true return end
        record.box = Origins(box, BOX_FIELDS, true)
        record.processSource = Source(box.ProcessChatType)
        record.scripts = {}
        for _, key in ipairs({ "OnEnterPressed", "OnTextChanged", "OnTextSet", "OnUpdate", "OnChar", "OnKeyDown" }) do
            record.scripts[key] = Source(box:GetScript(key))
        end
        local name = box:GetName()
        record.boxName = not Suite.IsSecret(name) and type(name) == "string" and name:match("^ChatFrame%d+EditBox$") or "<unavailable>"
        record.textSecret = Suite.IsSecret(box:GetText())
        record.objectSecrets = Primitive(box:HasSecretValues())
        record.aspects = Primitive(box:HasAnySecretAspect())
        record.chatTypeSecret = Suite.IsSecret(box:GetAttribute("chatType"))
        record.stickyTypeSecret = Suite.IsSecret(box:GetAttribute("stickyType"))
        record.tellTargetSecret = Suite.IsSecret(box:GetAttribute("tellTarget"))
        record.header = Origins(box.header, SOURCE_FIELDS)
        record.chatFrame = Origins(box.chatFrame, { "AddMessage", "OnEditFocusGained", "OnEditFocusLost", "SetGamepadFocus", "ClearGamepadFocus" })
        record.complete = true
    end

    local function Focused(_, box)
        if Dev.Read("addonChatRestrictionsForced") ~= "1" or not Suite.RootDB then return end
        Suite.Dispatch(Capture, "before-activation", box)
        C_Timer.After(0, function() Suite.Dispatch(Capture, "after-activation", box) end)
        C_Timer.After(1, function() Suite.Dispatch(Capture, "after-input", box) end)
        C_Timer.After(4, function() Suite.Dispatch(Capture, "after-input-4s", box) end)
    end

    if Suite.Client.isForever then
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusGained", Focused, "MSUF_Suite.DevMode.RootProbe")
    end
end
