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
-- colour equal to a theme colour proves nothing: the player may have picked
-- it. So nothing is inferred from colours across sessions:
-- - Without a ledger entry, the colour a category shows is the player's.
--   The skin themes only a category that shows Blizzard's default.
-- - What a clean logout could not put back is recorded here, in the Suite's
--   saved variables (per character), with the colour to put back:
--   suiteCharacters[guid].skinChatColors = { colors = { [chatType] =
--   { original = rgb, left = rgb, ambiguous = true|nil } } }.
--   From the next session on such an entry is ambiguous: kept, never
--   applied on its own.
-- - "Restore chat colors" (Skinning page, Maintenance) is the only recovery:
--   it puts back the recorded originals, else Blizzard's defaults.
-- Limit: a session that ends without PLAYER_LOGOUT (a crash) saves nothing,
-- so a theme colour it left in the chat cache stays until the player picks
-- another colour or uses "Restore chat colors".
local CHAT_LEDGER = "skinChatColors"
-- Blizzard's clean-profile colours of the categories the skin themes
-- (Retail's ChatTypeInfo defaults).
Skin.CHAT_COLOR_DEFAULTS = {
    SYSTEM = { 1, 1, 0 },
    MONSTER_SAY = { 1, 1, 159 / 255 },
    MONSTER_PARTY = { 170 / 255, 170 / 255, 1 },
}

-- The character's ledger entries and the owner table; nil while the
-- database or the GUID is unreadable, or while there is none.
local function ChatLedger()
    local characters = type(Suite.RootDB) == "table" and Suite.RootDB.suiteCharacters
    local guid = Suite.PublicText(UnitGUID("player"))
    local own = type(characters) == "table" and guid and characters[guid]
    local ledger = type(own) == "table" and own[CHAT_LEDGER]
    if type(ledger) ~= "table" or type(ledger.colors) ~= "table" then return nil end
    return ledger.colors, own
end

local function ReadableColor(color)
    return type(color) == "table" and Suite.Finite(color[1]) and Suite.Finite(color[2])
        and Suite.Finite(color[3])
end

local function Copy3(color)
    return { color[1], color[2], color[3] }
end

local function DropEmpty(colors, own)
    if own and next(colors) == nil then own[CHAT_LEDGER] = nil end
end

-- PLAYER_ENTERING_WORLD of the login (Startup.lua): every entry an earlier
-- session left becomes ambiguous. Never writes a colour. Returns the number
-- of entries waiting for "Restore chat colors".
function Skin.SettleChatColors()
    local colors, own = ChatLedger()
    if not colors then return 0 end
    local count = 0
    for chatType, entry in pairs(colors) do
        if type(entry) == "table" and ReadableColor(entry.original) then
            entry.ambiguous = true
            count = count + 1
        else
            colors[chatType] = nil
        end
    end
    DropEmpty(colors, own)
    return count
end

-- The skin's PLAYER_LOGOUT, after its restore. restored: the chat types it
-- put back (their entries go); leftovers: { [chatType] = { original = rgb,
-- left = rgb } } it could not put back (recorded). Other entries stay.
function Skin.CloseChatColors(restored, leftovers)
    local colors, own = ChatLedger()
    if colors then
        for chatType in pairs(restored or {}) do colors[chatType] = nil end
    end
    for chatType, entry in pairs(leftovers or {}) do
        if type(chatType) == "string" and ReadableColor(entry.original) and ReadableColor(entry.left) then
            if not colors then
                local ledger = Suite.CharacterData(CHAT_LEDGER)
                if not ledger then return end
                ledger.colors = {}
                colors, own = ChatLedger()
            end
            colors[chatType] = { original = Copy3(entry.original), left = Copy3(entry.left) }
        end
    end
    if colors then DropEmpty(colors, own) end
end

-- The number of recorded colours "Restore chat colors" would put back.
function Skin.PendingChatColors()
    local colors = ChatLedger()
    local count = 0
    for _ in pairs(colors or {}) do count = count + 1 end
    return count
end

-- "Restore chat colors": each themed category gets its recorded original
-- back, else Blizzard's default, and the ledger goes. Refused in combat.
-- Returns ok and the number of colours written (or false, reason).
function Skin.RestoreChatColors()
    if Suite.IsCombatLocked() then return false, "combat" end
    local colors, own = ChatLedger()
    local written = 0
    for chatType, default in pairs(Skin.CHAT_COLOR_DEFAULTS) do
        local entry = colors and colors[chatType]
        local color = type(entry) == "table" and ReadableColor(entry.original) and entry.original or default
        if Suite.Dispatch(Suite.Finish, ChangeChatColor, chatType, color[1], color[2], color[3]) then
            written = written + 1
            if colors then colors[chatType] = nil end
        end
    end
    if colors then DropEmpty(colors, own) end
    return true, written
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
