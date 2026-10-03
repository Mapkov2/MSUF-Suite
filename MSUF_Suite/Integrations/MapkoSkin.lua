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

-- The client stays cached: ReleaseAll drops its targets but the skin keeps
-- the name registered, so the module's next Acquire reuses this client.
function Skin.Release(moduleID)
    local client = clients[moduleID]
    if client then client:ReleaseAll() end
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

-- The Suite's own skin engine while it is loaded, else nil.
local function LoadedEngine()
    local provider = _G.MapkoSkin
    if type(provider) == "table" and provider.addonName == "MSUF_Suite_Skin" then return provider end
end

-- A module that replaces a Blizzard surface starts ("before") or stopped
-- ("after"); see S.OwnsBlizzardSurface. The engine rebuilds only surfaces that
-- changed hands.
function Skin.SurfacesChanged(phase)
    local provider = LoadedEngine()
    if not provider then return end
    local ownership = provider.SuiteOwnership
    if type(ownership) == "table" and type(ownership.Refresh) == "function" then ownership.Refresh(phase) end
end

------------------------------------------------------------------ chat colours
-- The skin themes a few chat message colours with ChangeChatColor, a
-- persistent client setting of the character (its chat cache). A colour
-- equal to a theme colour proves nothing: the player may have picked it. So
-- ownership comes only from provenance (a write the skin made), never from
-- colour equality. Per category:
--
--   Session (the skin's chat adapter, MSUF_Suite_Skin/Adapters/ChatFrames.lua)
--     A change is measured against the colour the category showed before
--     the edit began, and an edit that ends where it started is no change.
--     Colours compare as the chat cache stores them, one byte per channel:
--     different stored bytes are a change, however close.
--     - a ChangeChatColor the skin did not make that leaves the stored
--       bytes as they were is a no-op: the state stays;
--     - while ColorPickerFrame is shown (one picker session: Blizzard's
--       live preview, Cancel, OK) such writes are tentative and judged only
--       when it hides, against the colour each category showed when it
--       opened: equal (Cancel, or the same colour picked again) and the
--       state stays, different and it is a change. Theme repaints wait for
--       the session's end, so the colour Cancel returns to stays the
--       skin's;
--     - a session still open at logout or disable is unfinished: each
--       category keeps the state it had when the picker opened, so an owned
--       one is restored. What a disable put back stays owed until the
--       picker closes: if Cancel brings the skin's colour back, the
--       original goes back again, with no owner left.
--     Blizzard's default is the clean profile whenever the skin starts (a
--     login, or enabling it in a session that had not loaded it): it cannot
--     tell a player who picked exactly that colour from one who never
--     changed it, as it does not watch sessions it is not loaded in.
--     unowned   -> owned     first apply, the category shows Blizzard's
--                            default and nobody changed it this session;
--                            the skin's own ChangeChatColor writes the theme
--     unowned   -> released  first apply with any other colour, or a
--                            change earlier this session
--     owned     -> released  any change the skin did not make (another
--                            colour by ChangeChatColor or a picker session,
--                            or a colour that is not the skin's at a
--                            refresh); permanent this session, no colour
--                            equality brings it back
--     owned     -> (gone)    logout or disable writes the original back
--     owned     -> recorded  that write failed: a leftover for the ledger
--     released  -            never written by the skin, never recorded
--   Ledger (here, per character, in the Suite's saved variables)
--     recorded  -> ambiguous the next session starts (SettleChatColors)
--     ambiguous -            kept; never applied on its own; a later
--                            logout neither removes nor replaces it
--     recorded/ambiguous -> (gone)  "Restore chat colors" wrote it back
--   "Restore chat colors" (Skinning page, Maintenance): a category the
--   ledger records gets its recorded original back; one that shows the
--   skin's theme colour now gets Blizzard's default (the theme colour is
--   known while the skin engine is loaded); every other category keeps the
--   player's colour. This explicit action is the one place where a colour
--   equal to the skin's counts as the skin's, and the question before it
--   names every category it changes. Its writes are external to the
--   adapter, so a category it changed is released for the session and its
--   pending leftover dropped; an entry whose write failed stays.
--
--   suiteCharacters[guid].skinChatColors = { colors = { [chatType] =
--       { original = rgb, left = rgb, ambiguous = true|nil } } }
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

-- The skin's PLAYER_LOGOUT, after its restore. leftovers: { [chatType] =
-- { original = rgb, left = rgb } } it could not put back; each is recorded
-- unless the category already has an entry (the earlier original stays).
-- Nothing is removed here: only "Restore chat colors" consumes entries.
function Skin.CloseChatColors(leftovers)
    local colors = ChatLedger()
    for chatType, entry in pairs(leftovers or {}) do
        if type(chatType) == "string" and ReadableColor(entry.original) and ReadableColor(entry.left)
            and not (colors and colors[chatType]) then
            if not colors then
                local ledger = Suite.CharacterData(CHAT_LEDGER)
                if not ledger then return end
                ledger.colors = {}
                colors = ChatLedger()
            end
            colors[chatType] = { original = Copy3(entry.original), left = Copy3(entry.left) }
        end
    end
end

-- The number of recorded colours "Restore chat colors" would put back.
function Skin.PendingChatColors()
    local colors = ChatLedger()
    local count = 0
    for _ in pairs(colors or {}) do count = count + 1 end
    return count
end

-- The colour the skin themes a category with now, one byte per channel, as
-- the chat cache stores it. Only the loaded skin engine knows it (its theme
-- decides it); nil without it. The engine ships with this Suite.
local function SkinThemeColor(chatType)
    local provider = LoadedEngine()
    local chat = provider and provider.ChatFramesSkin
    return chat and chat.ThemeMessageColor(chatType) or nil
end

local function StoredByte(value) return math.floor(value * 255 + 0.5) end

-- True when the category's colour now is the skin's theme colour.
local function ShowsSkinColor(chatType)
    local theme = SkinThemeColor(chatType)
    local info = ChatTypeInfo[chatType]
    if not ReadableColor(theme) or type(info) ~= "table" then return false end
    -- Suite.Finite (ReadableColor) tests the secret flag before it compares.
    local current = { info.r, info.g, info.b }
    if not ReadableColor(current) then return false end
    for channel = 1, 3 do
        if StoredByte(current[channel]) ~= StoredByte(theme[channel]) then return false end
    end
    return true
end

-- What "Restore chat colors" writes, in a fixed order: a category the
-- ledger records gets its recorded original; one that shows the skin's
-- theme colour now gets Blizzard's default. Every other category keeps the
-- player's colour. This explicit action is the one place where a colour
-- equal to the skin's counts as the skin's. Returns a list of
-- { chatType = , color = rgb, recorded = true|nil }.
local CHAT_TYPES = { "SYSTEM", "MONSTER_SAY", "MONSTER_PARTY" }
function Skin.ChatColorRestorePlan()
    local colors = ChatLedger()
    local plan = {}
    for _, chatType in ipairs(CHAT_TYPES) do
        local entry = colors and colors[chatType]
        if type(entry) == "table" and ReadableColor(entry.original) then
            plan[#plan + 1] = { chatType = chatType, color = entry.original, recorded = true }
        elseif ShowsSkinColor(chatType) then
            plan[#plan + 1] = { chatType = chatType, color = Skin.CHAT_COLOR_DEFAULTS[chatType] }
        end
    end
    return plan
end

-- "Restore chat colors": the categories of the plan above get their colour.
-- asked (optional { [chatType] = true }): the categories the player was
-- shown; a category outside it is left alone, so Yes never changes more than
-- the question said. A written entry goes; an entry whose write failed
-- stays. Refused in combat. Returns ok (every write went through), the
-- number written and the number that failed; or false, "combat".
function Skin.RestoreChatColors(asked)
    if Suite.IsCombatLocked() then return false, "combat" end
    local colors, own = ChatLedger()
    local written, failed = 0, 0
    for _, step in ipairs(Skin.ChatColorRestorePlan()) do
        local chatType, color = step.chatType, step.color
        if not asked or asked[chatType] then
            if Suite.Dispatch(Suite.Finish, ChangeChatColor, chatType, color[1], color[2], color[3]) then
                written = written + 1
                if colors then colors[chatType] = nil end
            else
                failed = failed + 1
            end
        end
    end
    if colors then DropEmpty(colors, own) end
    return failed == 0, written, failed
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
