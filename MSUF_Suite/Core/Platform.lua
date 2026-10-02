local _, Suite = ...
local MSUF = assert(_G.MSUF_NS, "MSUF_Suite requires MSUF")

-- Only Suite-owned surfaces use the shared 0..30 MSUF layer slots. Auto (-1)
-- preserves their existing levels, including older profiles and clients.
function Suite.ApplyOwnedLayer(frame, layer, detail)
    local layers = MSUF.UF and MSUF.UF.Layers
    if layers and type(layers.ApplyOwnedSurface) == "function" then
        return layers.ApplyOwnedSurface(frame, layer, detail)
    end
    return false
end

-- Child artwork stays inside its parent's 32-level slot. On Auto, restore
-- its relative level only after the parent actually returned to legacy mode.
function Suite.ApplyOwnedChildLayer(frame, parent, layer, detail, parentRestored)
    if not (frame and frame.GetFrameLevel and frame.SetFrameLevel and parent and parent.GetFrameLevel) then return false end
    local layers = MSUF.UF and MSUF.UF.Layers
    if not (layers and type(layers.ApplyOwnedSurface) == "function") then return false end
    local wanted
    if type(layer) == "number" and layer >= 0 then
        if not (layers and type(layers.ElementLevel) == "function") then return false end
        wanted = layers.ElementLevel(layer, 0, detail)
    elseif parentRestored then
        wanted = parent:GetFrameLevel() + detail
    else
        return false
    end
    if frame:GetFrameLevel() ~= wanted then
        frame:SetFrameLevel(wanted)
        return true
    end
    return false
end

-- The Suite runs on Retail and on WoW Forever, which runs Blizzard's Mainline
-- code from the _Mainline.toc. Classic MSUF (the multi-client build that hosts
-- the Suite on Forever) publishes MSUF.Client; Main (Retail-only) MSUF does
-- not, so the suite derives the same facts itself under that host.
local host = type(MSUF.Client) == "table" and MSUF.Client or nil

-- Blizzard_Game defines this camelot marker before any addon loads, and only
-- on Forever (same probe as Classic MSUF).
local function HasForeverMarker()
    local gameEvent = _G.GameEvent
    return type(gameEvent) == "table" and type(gameEvent.RegisterCamelotEvents) == "function"
end

local isMainline, isForever
if host and type(host.Flavor) == "string" then
    isMainline = host.Flavor == "Mainline"
    isForever = host.IsForever == true
else
    -- The marker places Forever whatever project ID the client reports.
    isForever = HasForeverMarker()
    isMainline = isForever or _G.WOW_PROJECT_ID ~= nil and _G.WOW_PROJECT_ID == _G.WOW_PROJECT_MAINLINE
end

local eventValidity = {}
local function SupportsEvent(event)
    if type(event) ~= "string" or event == "" then return false end
    local valid = eventValidity[event]
    if valid ~= nil then return valid end
    valid = C_EventUtils.IsEventValid(event) == true
    eventValidity[event] = valid
    return valid
end

Suite.Client = {
    -- "Mainline" (Retail), "Forever", or "Unknown" for an unidentified client.
    flavor = isForever and "Forever" or isMainline and "Mainline" or "Unknown",
    isMainline = isMainline,
    isForever = isForever,
    -- Retail's own items and equipment rules; Forever has its own.
    modernEquipment = isMainline and not isForever,
    hasSecrets = type(_G.issecretvalue) == "function",
    SupportsEvent = host and type(host.SupportsEvent) == "function" and host.SupportsEvent or SupportsEvent,
}

-- Forever's Gamepad interface uses Blizzard's D-pad SmartNavigation. Native
-- pointer mode uses the same open-edge cursor API as Blizzard's own panels.
-- Both paths are queried live, so no input polling or device-name mapping is
-- needed. A registered window is briefly removed while it builds new pages:
-- SmartNavigation otherwise walks the entire window on each CreateFrame.
local function ForeverGamepadUI()
    local input = _G.InputUtil
    return isForever and input and type(input.IsGamepadUIEnabled) == "function"
        and input.IsGamepadUIEnabled() == true
end

local function ForeverFrameManager()
    if not ForeverGamepadUI() then return nil end
    local mode = _G.GamepadMode
    return mode and mode.FrameControlsManager or nil
end

function Suite.Client.PauseControllerWindow(frame)
    if not (isForever and frame and frame._msufsuitePadRegistered) then return end
    frame._msufsuitePadRegistered = nil
    local mode = _G.GamepadMode
    local manager = mode and mode.FrameControlsManager
    if manager then manager:FrameHidden(frame) end
end

function Suite.Client.ResumeControllerWindow(frame)
    if not (isForever and frame and frame:IsShown()) or frame._msufsuitePadRegistered then return end
    local manager = ForeverFrameManager()
    if manager then frame._msufsuitePadRegistered = manager:FrameShown(frame) == true end
end

function Suite.Client.AttachControllerWindow(frame)
    if not (isForever and frame) or frame._msufsuitePadAttached then return end
    frame._msufsuitePadAttached = true
    frame:HookScript("OnHide", Suite.Client.PauseControllerWindow)
end

function Suite.Client.RaiseControllerCursor()
    if not isForever or ForeverGamepadUI() then return end
    if type(_G.CanAutoSetGamePadCursorControl) == "function"
        and type(_G.SetGamePadCursorControl) == "function"
        and CanAutoSetGamePadCursorControl(true)
    then
        SetGamePadCursorControl(true)
    end
end

-- Which MSUF build hosts the suite, for diagnostics; every integration below
-- probes the capability it needs instead.
Suite.Host = { build = host and "Classic" or "Main" }

Suite.Defaults = {}
Suite.L = type(MSUF.L) == "table" and MSUF.L or {}
Suite.Safety = {}

-- English source text through MSUF's locale table; a missing or empty
-- translation stays English.
function Suite.Text(english)
    local value = Suite.L[english]
    return type(value) == "string" and value ~= "" and value or english
end

-- Statuses and refusal reasons are stored and returned as English text and
-- translated once, where they are shown. A status that names an addon or a
-- module is built here, so its display can translate the English format and
-- fill in the names again.
local statusSources = {}
function Suite.FormatStatus(format, ...)
    local text = format:format(...)
    if not statusSources[text] then statusSources[text] = { format, ... } end
    return text
end

-- A status in the reader's language. translate(english) defaults to
-- Suite.Text; the options pages pass their menu translation.
function Suite.StatusText(text, translate)
    translate = translate or Suite.Text
    local source = statusSources[text]
    if not source then return translate(text) end
    return translate(source[1]):format(unpack(source, 2))
end

------------------------------------------------------------------ secret values
-- Retail and Forever return secret values from many getters in combat. A
-- secret must never be compared, used in arithmetic, used as a table key or
-- passed to tonumber; it may only flow into C sinks such as SetText. These
-- readers live here (always loaded) so the options pages share them with the
-- module runtime (MSUF_Suite_Modules/Runtime.lua aliases them as S.*).
-- The readers below sit on event hot paths (health, damage meter, cooldowns),
-- so each tests the secret flag inline instead of calling Public. The hottest
-- module paths call Suite.IsSecret themselves: on a client with secrets it is
-- the client's issecretvalue, so a test costs one C call and no Lua call.
local IsSecret = type(issecretvalue) == "function" and issecretvalue or function() return false end
local HUGE = math.huge

local function Public(value)
    return not IsSecret(value)
end

-- A readable number: not secret, not NaN.
local function Number(value)
    return not IsSecret(value) and type(value) == "number" and value == value
end

-- A readable number that is also not infinite.
local function Finite(value)
    return not IsSecret(value) and type(value) == "number" and value == value
        and value > -HUGE and value < HUGE
end

-- Readable text: a non-empty, non-secret string, else nil.
local function PublicText(value)
    return not IsSecret(value) and type(value) == "string" and value ~= "" and value or nil
end

-- The first result of a client text API as readable text.
local function ReadText(fn, ...)
    return PublicText((fn(...)))
end

Suite.IsSecret, Suite.Public, Suite.Number, Suite.Finite = IsSecret, Public, Number, Finite
Suite.PublicText, Suite.ReadText = PublicText, ReadText

------------------------------------------------------------------ shared media
-- Settings store colors as six hex digits (validated by the controller).
-- Shared by the module runtime (S.RGB), the minimap style and the menu.
function Suite.RGB(hex)
    if type(hex) ~= "string" or #hex ~= 6 then return 1, 1, 1 end
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
        (tonumber(hex:sub(3, 4), 16) or 255) / 255,
        (tonumber(hex:sub(5, 6), 16) or 255) / 255
end

-- LibSharedMedia when another addon loaded it, else nil.
function Suite.SharedMedia()
    local stub = _G.LibStub
    return type(stub) == "table" and type(stub.GetLibrary) == "function" and stub:GetLibrary("LibSharedMedia-3.0", true) or nil
end

-- Font keys are MSUF/SharedMedia font keys; "" delegates to the caller's default.
-- Shared by the module runtime (S.ResolveFont) and the menu previews.
function Suite.ResolveFont(key)
    if type(key) ~= "string" or key == "" then return nil end
    -- MSUF's font list may hand out file paths as selection values.
    if key:find("\\", 1, true) or key:find("/", 1, true) then return key end
    local resolve = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey
    local path = type(resolve) == "function" and resolve(key) or nil
    if type(path) ~= "string" or path == "" then
        local media = Suite.SharedMedia()
        path = media and media:Fetch("font", key, true) or nil
    end
    return type(path) == "string" and path ~= "" and path or nil
end

-- Texture keys are MSUF/SharedMedia statusbar keys; "" means the caller's default.
function Suite.ResolveTexture(key, fallback)
    if type(key) ~= "string" or key == "" then return fallback end
    local resolve = _G.MSUF_ResolveStatusbarTextureKey
    if type(resolve) == "function" then
        local path = resolve(key)
        if type(path) == "string" and path ~= "" then return path end
    end
    local media = Suite.SharedMedia()
    local path = media and media:Fetch("statusbar", key, true) or nil
    return type(path) == "string" and path ~= "" and path or fallback
end

function Suite.IsCombatLocked()
    return InCombatLockdown() == true
end

-- The client sends PLAYER_REGEN_DISABLED before InCombatLockdown() turns
-- true and PLAYER_REGEN_ENABLED after it turns false. A handler that decides
-- "in combat" while running for one of those events passes the event here.
-- Code that runs inside another PLAYER_REGEN_DISABLED handler without
-- knowing it asks without an event: MSUF Edit Mode closes for combat in its
-- handler, and the modules re-apply right there (S.SetEditMode). The
-- player's combat flag already marks that window as combat starting:
-- Blizzard's own REGEN handlers read UnitAffectingCombat("player")
-- (EditModeActionBarMixin:UpdateVisibility, upstream/live ActionBar.lua),
-- and it is never secret (UnitDocumentation.lua, live and forever).
function Suite.InCombat(event)
    if event == "PLAYER_REGEN_DISABLED" then return true end
    if event == "PLAYER_REGEN_ENABLED" then return false end
    return InCombatLockdown() == true or UnitAffectingCombat("player") == true
end

-- Restricted actions raise ADDON_ACTION_BLOCKED when an addon calls them at
-- the wrong time, and no Lua code can catch that: callers ask first and
-- show Suite.RestrictedNotice() instead. Chat messages are blocked during chat
-- messaging lockdown, which also covers communication-restricted maps such
-- as dungeons and raids.
function Suite.ChatLocked()
    return C_ChatInfo.InChatMessagingLockdown() == true
end

-- Raid markers, countdowns and ready checks (HasRestrictions) are blocked
-- while combat, an encounter, a keystone, a PvP match or a restricted map
-- applies addon restrictions.
local GROUP_ACTION_LIMITS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }
function Suite.GroupActionsRestricted()
    if InCombatLockdown() then return true end
    local kinds = Enum.AddOnRestrictionType
    for i = 1, #GROUP_ACTION_LIMITS do
        if C_RestrictedActions.IsAddOnRestrictionActive(kinds[GROUP_ACTION_LIMITS[i]]) then return true end
    end
    return false
end

function Suite.RestrictedNotice()
    return Suite.Text("Blizzard blocks this right now. Try again after combat, the encounter or the keystone.")
end

-- Runs code whose failure must not stop its caller (module callbacks, data
-- ticks, deferred jobs) the way Blizzard's CallbackRegistry runs callbacks:
-- the error is reported to the error handler (BugSack) and the caller goes
-- on. Nothing is swallowed. Returns the results, or nothing after an error.
Suite.Dispatch = securecallfunction

-- Dispatch returns nothing when the call raised. Routing a call through
-- Finish tells the two apart: Dispatch(Suite.Finish, fn, ...) returns true
-- and fn's results, or nothing.
function Suite.Finish(callback, ...)
    return true, callback(...)
end

-- MSUF's own media: the default font and bar texture of Suite surfaces.
Suite.MSUFMedia = {
    font = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf",
    barTexture = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Bars\\MSUF_Lucent_v2.tga",
}

-- The global MSUF Fonts selection is the baseline for Suite-owned text.
-- Resolve it when styling, not at addon load: profile and menu changes may
-- replace the selected face while the Suite is already visible.
function Suite.GlobalFontPath()
    local path = type(_G.MSUF_GetFontPath) == "function" and _G.MSUF_GetFontPath() or nil
    return Public(path) and type(path) == "string" and path ~= ""
        and path or Suite.MSUFMedia.font
end

function Suite.Safety.IsForbidden(frame)
    return frame and type(frame.IsForbidden) == "function" and frame:IsForbidden() == true
end

function Suite.Client.IsAddOnLoaded(name)
    local loaded, finished = C_AddOns.IsAddOnLoaded(name)
    if finished ~= nil then return finished == true end
    return loaded == true
end

function Suite.Client.HasAddOn(name)
    return C_AddOns.DoesAddOnExist(name) == true
end

-- Match Blizzard's current-character AddOns checkbox. The GUID argument is
-- used by upstream/live's Blizzard_SharedXMLBase/AddOnUtil.lua; nil means the
-- all-characters list, so avoid it when a player GUID is available.
-- Enum.AddOnEnableState.None is 0 on both clients.
-- Returns true, or false and the reason; a third result, true, tells an AddOn
-- that is not installed at all from one switched off in the AddOns list.
function Suite.Client.AddOnEnabled(name)
    if not Suite.Client.HasAddOn(name) then
        return false, Suite.FormatStatus("Install %s to use this module", name), true
    end
    local guid = UnitGUID("player")
    if not Public(guid) then return false, "AddOn state unavailable in combat" end
    local state = C_AddOns.GetAddOnEnableState(name, guid)
    if type(state) == "number" and state > 0 then return true end
    return false, Suite.FormatStatus("Disabled in Blizzard's AddOns list: %s", name)
end

function Suite.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("MSUF Suite: " .. tostring(message))
end

-- Listeners are configuration-only. Registering one allocates no frame and
-- profile notifications never pass through MapkoSkin's registry.
local listeners = {}
Suite.Registry = {}
function Suite.Registry.AddListener(owner, callback)
    assert(type(callback) == "function", "profile listener must be callable")
    listeners[owner] = callback
end
function Suite.Registry.RemoveListener(owner)
    listeners[owner] = nil
end
-- One failing listener is reported and does not stop the others.
function Suite.Registry.NotifyListeners(domain, reason)
    local dispatch = Suite.Dispatch
    for owner, callback in pairs(listeners) do dispatch(callback, owner, domain, reason) end
end
function Suite.OnProfileChanged(name)
    Suite.Registry.NotifyListeners("profile", name)
end
