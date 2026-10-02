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
-- them back at PLAYER_LOGOUT (MSUF_Suite_Skin/Adapters/ChatFrames.lua).
-- Saved variables are written only by a clean logout or reload, after that
-- restore, so this ledger (per character, in the Suite's saved variables,
-- which load with or without the skin) holds only what a clean logout could
-- not put back: per chat type the colour to put back and the colour the
-- category showed at that logout, stamped with that logout's generation.
--   suiteCharacters[guid].skinChatColors =
--       { generation = n, colors = { [chatType] = { original = rgb, left = rgb, generation = n } } }
-- A category the logout restored, or that became the player's, is not in
-- it. A session that ends without PLAYER_LOGOUT (a crash) saves nothing:
-- its colours are recognised only by the skin when it runs again (its own
-- theme colour), never by the ledger. A colour goes back only when the
-- category shows exactly what the last saved logout left; everything else
-- is ambiguous (the player may have picked that colour in a session without
-- the Suite) and is left alone.
local CHAT_LEDGER = "skinChatColors"
local chatColorsClaimed = false

-- The character's ledger and its owner table; nil while the database or the
-- GUID is unreadable, or while there is none.
local function ChatLedger()
    local characters = type(Suite.RootDB) == "table" and Suite.RootDB.suiteCharacters
    local guid = Suite.PublicText(UnitGUID("player"))
    local own = type(characters) == "table" and guid and characters[guid]
    local ledger = type(own) == "table" and own[CHAT_LEDGER]
    if type(ledger) ~= "table" then return nil end
    return ledger, own
end

local function ReadableColor(color)
    return type(color) == "table" and Suite.Finite(color[1]) and Suite.Finite(color[2])
        and Suite.Finite(color[3])
end

local function Copy3(color)
    return { color[1], color[2], color[3] }
end

-- The entries the last saved logout stamped, else nil.
local function Eligible(ledger, entry)
    return type(entry) == "table" and Suite.Finite(ledger.generation) and entry.generation == ledger.generation
        and ReadableColor(entry.original) and ReadableColor(entry.left)
end

-- The category's colour, when ChatTypeInfo holds a readable one.
local function CurrentColor(chatType)
    local info = ChatTypeInfo[chatType]
    if type(info) ~= "table" then return nil end
    local r, g, b = info.r, info.g, info.b
    if not (Suite.Finite(r) and Suite.Finite(g) and Suite.Finite(b)) then return nil end
    return r, g, b
end

-- The skin's chat adapter runs this session and takes over what the last
-- logout left: { [chatType] = { original = rgb, left = rgb } } (copies).
-- The ledger keeps nothing then; the skin's logout writes it anew.
function Skin.ClaimChatColors()
    chatColorsClaimed = true
    local ledger = ChatLedger()
    local leftovers = {}
    if not ledger then return leftovers end
    for chatType, entry in pairs(type(ledger.colors) == "table" and ledger.colors or {}) do
        if Eligible(ledger, entry) then
            leftovers[chatType] = { original = Copy3(entry.original), left = Copy3(entry.left) }
        end
    end
    ledger.colors = nil
    return leftovers
end

-- The skin's PLAYER_LOGOUT, after its restore: leftovers maps each chat type
-- the restore could not put back to { original = rgb, left = rgb }.
-- Without leftovers the ledger leaves the saved variables.
function Skin.CloseChatColors(leftovers)
    if not chatColorsClaimed then return end
    local ledger, own = ChatLedger()
    local colors
    for chatType, entry in pairs(leftovers or {}) do
        if type(chatType) == "string" and ReadableColor(entry.original) and ReadableColor(entry.left) then
            colors = colors or {}
            colors[chatType] = { original = Copy3(entry.original), left = Copy3(entry.left) }
        end
    end
    if not colors then
        if own then own[CHAT_LEDGER] = nil end
        return
    end
    if not ledger then
        ledger = Suite.CharacterData(CHAT_LEDGER)
        if not ledger then return end
    end
    local generation = (Suite.Finite(ledger.generation) and ledger.generation or 0) + 1
    for _, entry in pairs(colors) do entry.generation = generation end
    ledger.generation, ledger.colors = generation, colors
end

-- PLAYER_ENTERING_WORLD of the login (Startup.lua), after the skin's login
-- pass: when no skin claimed the ledger, each category that shows exactly
-- the colour the last logout left gets its original back. Every entry it can
-- read goes; one whose colour is unreadable waits. Returns the number of
-- colours put back.
function Skin.SettleChatColors()
    if chatColorsClaimed then return 0 end
    local ledger, own = ChatLedger()
    if not ledger then return 0 end
    local colors = type(ledger.colors) == "table" and ledger.colors or {}
    local restored = 0
    for chatType, entry in pairs(colors) do
        local r, g, b = CurrentColor(chatType)
        local eligible = Eligible(ledger, entry)
        if not eligible then
            colors[chatType] = nil
        elseif r then
            local left = entry.left
            if r == left[1] and g == left[2] and b == left[3] then
                local original = entry.original
                if Suite.Dispatch(Suite.Finish, ChangeChatColor, chatType, original[1], original[2], original[3]) then
                    restored = restored + 1
                    colors[chatType] = nil
                end
            else
                colors[chatType] = nil
            end
        end
    end
    if next(colors) == nil and own then own[CHAT_LEDGER] = nil end
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
