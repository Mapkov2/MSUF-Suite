local _, P = ...
-- Shared glue for the suite pages. Everything here uses Menu2's public table
-- (_G.MSUF2), which the Main and the Classic MSUF build expose identically.
local Suite = assert(_G.MSUFSuite, "MSUF_Suite is required")
local M = assert(_G.MSUF2, "MSUF options are required")
P.Suite, P.S, P.M, P.host = Suite, Suite.Suite, M, _G.MSUF_NS
P.W, P.T = M.Widgets, M.Theme
P.catalog, P.order = Suite.SuiteCatalog, Suite.SuiteOrder
P.pages = {}
local S, T = P.S, P.T

function P.Tr(text)
    if type(text) ~= "string" then return text end
    return M.Tr and M.Tr(text) or text
end
local Tr = P.Tr

-- Previews must work before the optional runtime addon loads Surfaces.lua.
function P.StylePreviewFont(label, path, size, outline, rendering, shadow, opacity, distance)
    if S.SetStyledFont then
        return S.SetStyledFont(label, path, size, outline, rendering, shadow, opacity, distance)
    end
    local flags = outline or ""
    if rendering == 3 then
        flags = flags == "" and "SLUG" or "OUTLINE,SLUG"
    elseif rendering == 2 and not flags:find("MONOCHROME", 1, true) then
        flags = flags == "" and "MONOCHROME" or flags .. ",MONOCHROME"
    end
    local fallback = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    if label:SetFont(path or fallback, size, flags) == false then label:SetFont(fallback, size, "") end
    local shown = shadow == true and rendering ~= 3
    label:SetShadowColor(0, 0, 0, shown and (opacity or 100) / 100 or 0)
    local offset = shown and (distance or 1) or 0
    label:SetShadowOffset(offset, -offset)
end

-- One MSUF history entry owns a complete Suite gesture, including edits made
-- from the preview and Edit Mode. MSUF calls every provider on every tracked
-- gesture, so a snapshot holds only what a gesture can change: the active
-- Suite and skin profiles plus the small root flags. Other profiles (MSUF
-- clears its history on profile operations) and runtime logs stay out.
local SUITE_ROOT_SKIP = {
    profiles = true, suiteChat = true, suiteRuns = true, suiteRecovery = true, suiteXP = true, suiteGold = true,
}
local SKIN_ROOT_SKIP = { profiles = true, optionsUI = true }

-- Returns a root-shaped copy: { profiles = { [active] = copy }, flags... }.
local function CaptureRoot(root, skip)
    if type(root) ~= "table" or type(root.profiles) ~= "table" then return nil end
    local snapshot = { profiles = {} }
    for key, value in pairs(root) do
        if not skip[key] then snapshot[key] = Suite.CopyValue(value) end
    end
    local name = root.activeProfile
    if name ~= nil then snapshot.profiles[name] = Suite.CopyValue(root.profiles[name]) end
    return snapshot
end

local function RestoreRoot(root, snapshot, skip)
    for key in pairs(root) do
        if not skip[key] and snapshot[key] == nil then root[key] = nil end
    end
    for key, value in pairs(snapshot) do
        if not skip[key] then root[key] = Suite.CopyValue(value) end
    end
    local name = snapshot.activeProfile
    local profile = name ~= nil and type(snapshot.profiles) == "table" and snapshot.profiles[name]
    if type(profile) == "table" then root.profiles[name] = Suite.CopyValue(profile) end
end

local function SkinRoot()
    local skin = _G.MapkoSkin
    if type(skin) == "table" and skin.addonName == "MSUF_Suite_Skin"
        and skin.Database and type(skin.Database.GetRoot) == "function" then
        return skin, skin.Database.GetRoot()
    end
end

function P.CaptureHistoryState()
    local root = CaptureRoot(Suite.RootDB, SUITE_ROOT_SKIP)
    if not root then return nil end
    local _, skinRoot = SkinRoot()
    return { root = root, skinRoot = CaptureRoot(skinRoot, SKIN_ROOT_SKIP) }
end

function P.RestoreHistoryState(state)
    if Suite.IsCombatLocked() or type(state) ~= "table" or type(state.root) ~= "table"
        or type(Suite.RootDB) ~= "table" or type(Suite.RootDB.profiles) ~= "table" then
        return false
    end
    local previousProfile = Suite.RootDB.activeProfile
    RestoreRoot(Suite.RootDB, state.root, SUITE_ROOT_SKIP)
    local active = Suite.RootDB.profiles[Suite.RootDB.activeProfile]
    if type(active) ~= "table" then return false end
    Suite.DB = active
    S.Normalize(active)
    if previousProfile ~= Suite.RootDB.activeProfile and Suite.OnProfileChanged then
        Suite.OnProfileChanged(Suite.RootDB.activeProfile)
    end
    local skin, skinRoot = SkinRoot()
    if type(state.skinRoot) == "table" and type(skinRoot) == "table" and type(skinRoot.profiles) == "table" then
        RestoreRoot(skinRoot, state.skinRoot, SKIN_ROOT_SKIP)
        skin.Database.SetActiveProfile(skinRoot.activeProfile)
    end
    if Suite.Skin and Suite.Skin.enabled ~= (Suite.RootDB.skinEnabled == true) then
        Suite.Skin.SetEnabled(Suite.RootDB.skinEnabled == true)
    end
    S.ApplyAll()
    P.Refresh()
    return true
end
function P.WithHistory(label, source, fn)
    if type(fn) ~= "function" then return false end
    if P.historyRegistered and type(M.RunWithHistory) == "function" then
        return M.RunWithHistory(label or "Suite change", source or "suite:options", fn)
    end
    return fn()
end

-- One visual preset across the Suite's visible modules and the embedded skin.
-- Layout, visibility and gameplay behavior stay with their current settings.
function P.ApplyForeverStyle()
    if P.Combat() then return false end
    -- Load the dormant skin database before the history snapshot so undo also
    -- includes its palette even when Skinning was previously switched off.
    if Suite.Skin and Suite.Skin.EnsureEngine then Suite.Skin.EnsureEngine() end
    return P.WithHistory("MSUF Forever suite look", "suite:forever-look", function()
        if not S.ApplyGlobalLook("foreverGlass") then return false end
        if Suite.Skin and Suite.Skin.EnsureEngine and Suite.Skin.EnsureEngine() then
            local skin = _G.MapkoSkin
            if skin and skin.addonName == "MSUF_Suite_Skin" and skin.Theme and skin.Theme.ApplyLook then
                if skin.Theme.ApplyLook("foreverGlass") == false then return false end
            end
        end
        P.Refresh()
        return true
    end)
end

function P.Get(id, key)
    local value = S.Config(id)[key]
    if value == nil then value = P.catalog[id].rules[key].default end
    return value
end

-- Every write goes through the controller; the page repaints afterwards. The
-- last refusal per module is shown in that module's status line.
P.feedback = {}

-- Look rules come from the catalog entry (spec.look, see SuiteCatalog.lua):
-- choosing a preset writes its values, and editing one of its visual
-- settings switches the preset to Custom.
local function LookEdit(id, key, value)
    local look = P.catalog[id].look
    if not look or not look.key then return nil end
    if key == look.key then
        local preset = look.presets and look.presets[tonumber(value)]
        if not preset then return nil end
        local values = { [key] = value }
        for setting, choice in pairs(preset) do values[setting] = choice end
        return values
    end
    if look.custom and look.visualKeys and look.visualKeys[key] and P.Get(id, look.key) ~= look.custom then
        return { [key] = value, [look.key] = look.custom }
    end
end

function P.Set(id, key, value)
    local values = LookEdit(id, key, value)
    if values then return P.SetMany(id, values) end
    local ok, reason
    P.WithHistory(P.catalog[id].rules[key].label, "suite:" .. id .. "." .. key, function()
        ok, reason = S.Set(id, key, value)
        return ok
    end)
    if ok == nil then ok, reason = false, "Finish combat before editing the suite" end
    P.feedback[id] = not ok and reason or nil
    P.Refresh()
    return ok, reason
end
function P.SetMany(id, values)
    local look = P.catalog[id].look
    if look and look.custom and look.visualKeys and type(values) == "table"
        and values[look.key] == nil and P.Get(id, look.key) ~= look.custom then
        for key in pairs(values) do
            if look.visualKeys[key] then
                local custom = { [look.key] = look.custom }
                for setting, value in pairs(values) do custom[setting] = value end
                values = custom
                break
            end
        end
    end
    local ok, reason
    P.WithHistory(P.catalog[id].title .. " settings", "suite:" .. id .. ".multiple", function()
        ok, reason = S.SetMany(id, values)
        return ok
    end)
    if ok == nil then ok, reason = false, "Finish combat before editing the suite" end
    P.feedback[id] = not ok and reason or nil
    P.Refresh()
    return ok, reason
end

-- Repaints the visible suite page; controller changes queued in combat reach
-- the menu through Suite.Options.RefreshAll (set in Register.lua).
function P.Refresh()
    if M.RequestRefresh then M.RequestRefresh(nil, "suite") end
end

function P.Combat() return Suite.IsCombatLocked() end

-- Named capability checks used by catalog rules (rule.requires). Pages add
-- entries; unknown names are treated as available.
P.Requires = {}
-- Per-module extra gates: function(rule, key) -> boolean.
P.Gates = {}
-- Per-module, per-key choice gates: function(choiceIndex) -> boolean.
P.ChoiceGates = {}

-- Enable is a stored preference; other rules require an available, enabled
-- module and satisfied presentation dependencies. `resolve` maps a
-- template rule key to the live key when a page edits one of several bars or
-- windows through shared controls.
function P.RuleEnabled(id, rule, resolve)
    if P.Combat() then return false end
    if rule.key == "enabled" then return true end
    local available = S.Availability(id)
    if not available or not P.Get(id, "enabled") then return false end
    local function Key(key) return resolve and resolve(key) or key end
    local seen = 0
    local current = rule
    while current and current.enableKey and seen < 4 do
        if not P.Get(id, Key(current.enableKey)) then return false end
        current = P.catalog[id].rules[current.enableKey]
        seen = seen + 1
    end
    if rule.disabledBy and P.Get(id, Key(rule.disabledBy)) then return false end
    local choice = rule.requiresChoice
    if choice and not choice.values[P.Get(id, Key(choice.key))] then return false end
    if rule.requires and P.Requires[rule.requires] and not P.Requires[rule.requires]() then return false end
    local gate = P.Gates[id]
    if gate and gate(rule, Key(rule.key)) == false then return false end
    return true
end

-- Control identities for Menu2's search and runtime catalog. Suite settings
-- live in MSUFSuiteDB, so the setting keys carry their own namespace.
function P.Meta(pageKey, id, key, classification, sectionId)
    classification = classification or "setting"
    local exact = { sectionId = sectionId }
    if classification == "setting" then exact.settingKey = "msufsuite." .. id .. "." .. key
    else exact.historyMode = "none" end
    if M.ControlMeta then return M.ControlMeta(pageKey, "suite", id .. "." .. key, classification, exact) end
    exact.classification = classification
    return exact
end

function P.Text(parent, text, x, y, width, color)
    local label = T.Font(parent, "GameFontHighlightSmall", Tr(text or ""), color or T.colors.muted, "supporting")
    label:SetPoint("TOPLEFT", x or 16, y or 0)
    label:SetWidth(width or 300)
    label:SetJustifyH("LEFT")
    if label.SetWordWrap then label:SetWordWrap(true) end
    return label
end

-- Buttons follow the page's enable rules: pass `enabled` (function) to gate.
function P.Button(ctx, parent, label, x, y, width, onClick, enabled, meta)
    local button = T.Button(parent, Tr(label), width or 180, 26)
    button:SetPoint("TOPLEFT", x, y)
    button:SetScript("OnClick", function()
        if P.Combat() then return end
        onClick()
        P.Refresh()
    end)
    if meta and M.RegisterControlMetadata then M.RegisterControlMetadata(button, meta, label, "button") end
    if enabled then
        M.TrackRefresh(ctx, function() button:SetEnabled(enabled() and not P.Combat() and true or false) end)
    end
    return button
end

-- Collapsible bodies built with explicit positions report their height here,
-- through the builder's own auto-height path.
function P.FinishBody(b, body, bottomY, pad)
    body._msuf2CursorY = math.min(bottomY, -39)
    if b.FinishSection then b:FinishSection(body, pad or 12) end
end

-- Module status line: availability, controller status and page feedback.
function P.StatusText(id)
    local reason = P.feedback[id]
    if reason then return Tr(reason) end
    local ok, why = S.Availability(id)
    if not ok then return Tr(why or "Unavailable on this client") end
    return Tr(S.Status(id))
end

function P.RegisterPage(spec)
    assert(type(spec.key) == "string" and type(spec.build) == "function", "invalid suite page")
    P.pages[#P.pages + 1] = spec
end

-- Opens MSUF Edit Mode with a module's element selected; closes the menu.
function P.MoveOnScreen(id, element)
    if P.Combat() or not S.OpenEditMode then return end
    if S.OpenEditMode(id, element) and M.frame and M.frame.Hide then M.frame:Hide() end
end
