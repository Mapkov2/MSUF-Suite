local _, Suite = ...

-- The Suite owns the embedded skin engine's load boundary and uses its public
-- surface API for Suite modules. Legacy standalone MapkoSkin can finish a
-- running session, but the embedded engine is the normal next-login owner.
local Skin = { enabled = false }
Suite.Skin = Skin
local clients = {}
local appearanceHooked = false
-- The HUD modules read skin colors and fonts when they paint.
local SKINNED_HUD = { "objectives", "announcements" }

local function HookOwnedHUD(api)
    -- hooksecurefunc raises when the hooked field is not a function.
    if appearanceHooked or type(api.OnAppearanceChanged) ~= "function" then return end
    hooksecurefunc(api, "OnAppearanceChanged", function()
        local controller = Suite.Suite
        if not controller.started then return end
        for _, id in ipairs(SKINNED_HUD) do
            if controller.states[id].active then controller.Apply(id) end
        end
    end)
    appearanceHooked = true
end

function Skin.IsAvailable()
    local provider = _G.MapkoSkin
    return type(provider) == "table" and type(provider.GetAPI) == "function"
end

function Skin.LoadLegacyDatabase()
    if type(_G.MapkoSkinDB) == "table" then return true end
    if type(_G.MapkoSkin) == "table" and not _G.MapkoSkin.migrationOnly then return false end
    if not Suite.Client.HasAddOn("MapkoSkin") then return false end
    -- LoadAddOn reports a failed load in its results; the addon's own load
    -- errors go to the client error handler. The database decides success.
    _G.MSUFSuiteSkinMigrating = true
    C_AddOns.LoadAddOn("MapkoSkin")
    _G.MSUFSuiteSkinMigrating = nil
    return type(_G.MapkoSkinDB) == "table"
end

function Skin.EnsureEngine()
    local provider = _G.MapkoSkin
    if type(provider) == "table" and provider.addonName == "MSUF_Suite_Skin" then
        if type(provider.EnsureDatabaseReady) == "function" then provider.EnsureDatabaseReady() end
        return true
    end
    if Skin.IsAvailable() and not provider.migrationOnly then return true, "legacy-session" end
    local importedLegacy = type(_G.MapkoSkinDB) == "table"
    -- The old addon is now load-on-demand. Load it only once as a data bridge:
    -- its skin hooks are suppressed by migrationOnly before PLAYER_LOGIN.
    if Suite.RootDB and not Suite.RootDB.skinMigrationDone then
        importedLegacy = Skin.LoadLegacyDatabase() or importedLegacy
    end
    local loaded, reason = C_AddOns.LoadAddOn("MSUF_Suite_Skin")
    if type(_G.MapkoSkin) == "table" and _G.MapkoSkin.addonName == "MSUF_Suite_Skin"
        and Skin.IsAvailable() then
        if type(_G.MapkoSkin.EnsureDatabaseReady) == "function" then
            _G.MapkoSkin.EnsureDatabaseReady()
        end
        if importedLegacy and Suite.RootDB then Suite.RootDB.skinMigrationDone = true end
        return true -- Forever may return a diagnostic.
    end
    return false, tostring(reason or loaded or "skin-engine-unavailable")
end

function Skin.Acquire(moduleID)
    if not Skin.enabled or type(moduleID) ~= "string" or not moduleID:match("^[%a][%w_]*$") then
        return nil
    end
    if clients[moduleID] then return clients[moduleID] end
    if not Skin.EnsureEngine() then return nil end
    local api = _G.MapkoSkin.GetAPI(2, 0)
    if not api or type(api.RegisterAddon) ~= "function" then return nil end
    HookOwnedHUD(api)
    local client = api:RegisterAddon("MSUF_Suite_" .. moduleID)
    if client then clients[moduleID] = client end
    return client
end

function Skin.Release(moduleID)
    local client = clients[moduleID]
    if not client then return end
    client:ReleaseAll()
    clients[moduleID] = nil
end

-- Re-applies the started modules so they pick up or drop the skin. A caller
-- that applies them itself right after (undo) passes deferApply.
function Skin.SetEnabled(enabled, deferApply)
    if Suite.IsCombatLocked() then return false, "combat" end
    enabled = enabled == true
    if enabled then Skin.EnsureEngine() end
    if not enabled then
        for moduleID in pairs(clients) do Skin.Release(moduleID) end
    end
    Skin.enabled = enabled
    if Suite.RootDB then Suite.RootDB.skinEnabled = enabled end
    if not deferApply and Suite.Suite.started then Suite.Suite.ApplyAll() end
    return true
end

-- A module that replaces a Blizzard surface starts ("before") or stopped
-- ("after"); see S.OwnsBlizzardSurface. The engine rebuilds only surfaces that
-- changed hands.
function Skin.SurfacesChanged(phase)
    local provider = _G.MapkoSkin
    if type(provider) ~= "table" or provider.addonName ~= "MSUF_Suite_Skin" then return end
    local ownership = provider.SuiteOwnership
    if type(ownership) == "table" and type(ownership.Refresh) == "function" then ownership.Refresh(phase) end
end

------------------------------------------------------------------ chat colours
-- The skin themes a few chat message colours with ChangeChatColor, a
-- persistent client setting of the character (its chat cache), and puts
-- them back at PLAYER_LOGOUT (MSUF_Suite_Skin/Adapters/ChatFrames.lua). A
-- session that ends without PLAYER_LOGOUT can leave the skin's colour
-- behind, and a skin that is off never runs again to put it back. So the
-- skin keeps a ledger here, in the Suite's saved variables, which load with
-- or without it: per character and chat type the colour to put back and the
-- colour the skin wrote, { original = { r, g, b }, applied = { r, g, b } }.
-- Saved variables are written only by a clean logout or reload, after the
-- skin's restore, so an entry stays through logout: it is what the next
-- session finds when that one ends without logout.
local CHAT_LEDGER = "skinChatColors"
-- The chat client stores colours in 8 bits per channel (the skin's own
-- tolerance, Safety.COLOR_OWN).
local CHAT_COLOR_TOLERANCE = 1 / 255
local chatColorsClaimed = false

-- The character's ledger; nil while the database or the GUID is unreadable,
-- and while there is none unless create asks for one.
local function ChatLedger(create)
    if create then return Suite.CharacterData(CHAT_LEDGER) end
    local characters = type(Suite.RootDB) == "table" and Suite.RootDB.suiteCharacters
    local guid = Suite.PublicText(UnitGUID("player"))
    local own = type(characters) == "table" and guid and characters[guid]
    local ledger = type(own) == "table" and own[CHAT_LEDGER]
    if type(ledger) ~= "table" then return nil end
    return ledger, own
end

-- An empty ledger leaves the saved variables.
local function DropEmptyLedger(ledger, own)
    if own and next(ledger) == nil then own[CHAT_LEDGER] = nil end
end

local function CopyColor(source, target)
    target = type(target) == "table" and target or {}
    target[1], target[2], target[3] = source[1], source[2], source[3]
    return target
end

local function ReadableColor(color)
    return type(color) == "table" and Suite.Finite(color[1]) and Suite.Finite(color[2])
        and Suite.Finite(color[3])
end

-- The skin's chat adapter runs this session: it owns the ledger now.
function Skin.ClaimChatColors()
    chatColorsClaimed = true
end

-- The skin wrote applied over a category that showed original.
function Skin.RememberChatColor(chatType, original, applied)
    if type(chatType) ~= "string" or not ReadableColor(original) or not ReadableColor(applied) then return false end
    local ledger = ChatLedger(true)
    if not ledger then return false end
    local entry = type(ledger[chatType]) == "table" and ledger[chatType] or {}
    entry.original = CopyColor(original, entry.original)
    entry.applied = CopyColor(applied, entry.applied)
    ledger[chatType] = entry
    return true
end

-- The category is the player's again, or the skin put its colour back.
function Skin.ForgetChatColor(chatType)
    local ledger, own = ChatLedger(false)
    if not ledger then return end
    ledger[chatType] = nil
    DropEmptyLedger(ledger, own)
end

-- The colour to put back and the colour the skin wrote, or nil. Read only.
function Skin.RememberedChatColor(chatType)
    local ledger = ChatLedger(false)
    local entry = ledger and ledger[chatType]
    if type(entry) ~= "table" or not ReadableColor(entry.original) or not ReadableColor(entry.applied) then
        return nil
    end
    return entry.original, entry.applied
end

local function ShowsColor(chatType, color)
    local info = ChatTypeInfo[chatType]
    if type(info) ~= "table" then return nil end
    local r, g, b = info.r, info.g, info.b
    if not (Suite.Finite(r) and Suite.Finite(g) and Suite.Finite(b)) then return nil end
    return math.abs(r - color[1]) <= CHAT_COLOR_TOLERANCE and math.abs(g - color[2]) <= CHAT_COLOR_TOLERANCE
        and math.abs(b - color[3]) <= CHAT_COLOR_TOLERANCE
end

-- PLAYER_ENTERING_WORLD of the login (Startup.lua), after the skin's login
-- pass: when no skin claimed the ledger, the skin is off, so each category
-- that still shows the colour it wrote gets its original back, and every
-- entry it can read goes. Returns the number of colours put back.
function Skin.SettleChatColors()
    if chatColorsClaimed then return 0 end
    local ledger, own = ChatLedger(false)
    if not ledger then return 0 end
    local restored = 0
    for chatType, entry in pairs(ledger) do
        local original, applied = Skin.RememberedChatColor(chatType)
        local shows = original and ShowsColor(chatType, applied)
        if shows and Suite.Dispatch(Suite.Finish, ChangeChatColor, chatType, original[1], original[2], original[3]) then
            restored = restored + 1
            ledger[chatType] = nil
        elseif shows == false or type(entry) ~= "table" or not original then
            ledger[chatType] = nil
        end
    end
    DropEmptyLedger(ledger, own)
    return restored
end

function Skin.OpenEditor(parent, width, height)
    if Suite.IsCombatLocked() then return false, "combat" end
    Skin.EnsureEngine()
    local provider = _G.MapkoSkin
    if type(provider) ~= "table" or type(provider.MountOptions) ~= "function" then
        return false, "skin-editor-unavailable"
    end
    return provider.MountOptions(parent, width, height)
end
