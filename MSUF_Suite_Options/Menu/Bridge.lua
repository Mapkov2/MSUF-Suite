local _, P = ...
-- Shared glue for the suite pages. Everything here uses Menu2's public table
-- (_G.MSUF2), which the Main and the Classic MSUF build expose identically.
-- Pages check a Menu2 helper before use: an older MSUF install may lack it.
-- S.* functions of a load-on-demand module addon exist only once it loaded.
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
-- rendering is a "Font rendering" choice (MSUFSuite.FontRendering).
local RENDERING = Suite.FontRendering
function P.StylePreviewFont(label, path, size, outline, rendering, shadow, opacity, distance)
    if S.SetStyledFont then
        return S.SetStyledFont(label, path, size, outline, rendering, shadow, opacity, distance)
    end
    local flags = outline or ""
    if rendering == RENDERING.SLUG then
        flags = flags == "" and "SLUG" or "OUTLINE,SLUG"
    elseif rendering == RENDERING.SHARP and not flags:find("MONOCHROME", 1, true) then
        flags = flags == "" and "MONOCHROME" or flags .. ",MONOCHROME"
    end
    local fallback = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local checked = _G.MSUF_SetFontChecked
    if type(checked) == "function" then
        checked(label, path or fallback, size, flags)
    elseif label:SetFont(path or fallback, size, flags) == false then
        label:SetFont(fallback, size, "")
    end
    local shown = shadow == true and rendering ~= RENDERING.SLUG
    label:SetShadowColor(0, 0, 0, shown and (opacity or 100) / 100 or 0)
    local offset = shown and (distance or 1) or 0
    label:SetShadowOffset(offset, -offset)
end

-- One MSUF history entry owns a complete Suite gesture, including edits made
-- from the preview and Edit Mode. MSUF calls every provider on every tracked
-- gesture, so a snapshot holds only the settings a gesture can change
-- (Database.ROOT_SETTINGS and PROFILE_SETTINGS of the active Suite profile,
-- plus the Edit Mode layout state of PROFILE_LAYOUT_STATE) and the active
-- skin profile. Other profiles (MSUF clears its history on profile
-- operations), other module state and runtime data such as chat history,
-- gold ledgers and run history are never copied or rolled back.
local DB = Suite.Database
local SKIN_ROOT_SETTINGS = { "activeProfile" }

local function CopyKeys(source, keys, target)
    for _, key in ipairs(keys) do
        if source[key] ~= nil then target[key] = Suite.CopyValue(source[key]) end
    end
    return target
end

-- Returns a root-shaped copy: { profiles = { [active] = copy }, flags... }.
-- The Suite part holds the active profile's base settings: the stored ones,
-- never a variant overlay the core laid over them (ProfileVariants.lua).
-- The layout state of one stored Suite profile: { [owner] = { [key] = copy } }.
local function CaptureLayoutState(suite)
    local states = type(suite) == "table" and type(suite.moduleState) == "table" and suite.moduleState or {}
    local layout = {}
    for owner, keys in pairs(DB.PROFILE_LAYOUT_STATE) do
        local state = type(states[owner]) == "table" and states[owner] or {}
        layout[owner] = CopyKeys(state, keys, {})
    end
    return layout
end

local function CaptureSuite(root)
    if type(root) ~= "table" or type(root.profiles) ~= "table" then return nil end
    local snapshot = CopyKeys(root, DB.ROOT_SETTINGS, { profiles = {} })
    local name = root.activeProfile
    if name ~= nil and type(root.profiles[name]) == "table" then
        local settings = Suite.ProfileVariants.BaseSettings(name)
        if not settings then return nil end
        snapshot.profiles[name] = { suite = settings, layoutState = CaptureLayoutState(root.profiles[name].suite) }
    end
    return snapshot
end

-- Writes the captured layout state back, also where it was empty then.
local function RestoreLayoutState(root, snapshot)
    local name = snapshot.activeProfile
    local profile = name ~= nil and type(snapshot.profiles) == "table" and snapshot.profiles[name]
    local target = type(root.profiles[name]) == "table" and root.profiles[name].suite
    if type(profile) ~= "table" or type(profile.layoutState) ~= "table" or type(target) ~= "table" then return end
    for owner, keys in pairs(DB.PROFILE_LAYOUT_STATE) do
        local saved = type(profile.layoutState[owner]) == "table" and profile.layoutState[owner] or {}
        if type(target.moduleState) ~= "table" then target.moduleState = {} end
        local state = type(target.moduleState[owner]) == "table" and target.moduleState[owner] or {}
        target.moduleState[owner] = state
        for _, key in ipairs(keys) do state[key] = Suite.CopyValue(saved[key]) end
    end
end

-- A skin profile holds settings only and is copied whole.
local function CaptureSkin(root)
    if type(root) ~= "table" or type(root.profiles) ~= "table" then return nil end
    local snapshot = CopyKeys(root, SKIN_ROOT_SETTINGS, { profiles = {} })
    local name, profile = root.activeProfile, root.profiles[root.activeProfile]
    if name ~= nil and type(profile) == "table" then snapshot.profiles[name] = Suite.CopyValue(profile) end
    return snapshot
end

local function RestoreRoot(root, snapshot, rootKeys, profileKeys)
    for _, key in ipairs(rootKeys) do
        if snapshot[key] ~= nil then root[key] = Suite.CopyValue(snapshot[key]) end
    end
    local name = snapshot.activeProfile
    local profile = name ~= nil and type(snapshot.profiles) == "table" and snapshot.profiles[name]
    if type(profile) ~= "table" then return end
    if not profileKeys then
        root.profiles[name] = Suite.CopyValue(profile)
        return
    end
    local target = type(root.profiles[name]) == "table" and root.profiles[name] or {}
    root.profiles[name] = target
    if type(target.suite) ~= "table" then target.suite = {} end
    local saved = type(profile.suite) == "table" and profile.suite or {}
    for _, key in ipairs(profileKeys) do target.suite[key] = Suite.CopyValue(saved[key]) end
end

local function SkinRoot()
    local skin = _G.MapkoSkin
    if type(skin) == "table" and skin.addonName == "MSUF_Suite_Skin"
        and skin.Database and type(skin.Database.GetRoot) == "function" then
        return skin, skin.Database.GetRoot()
    end
end

function P.CaptureHistoryState()
    local root = CaptureSuite(Suite.RootDB)
    if not root then return nil end
    local _, skinRoot = SkinRoot()
    return { root = root, skinRoot = CaptureSkin(skinRoot) }
end

function P.RestoreHistoryState(state)
    if Suite.IsCombatLocked() or type(state) ~= "table" or type(state.root) ~= "table"
        or type(Suite.RootDB) ~= "table" or type(Suite.RootDB.profiles) ~= "table" then
        return false
    end
    local previousProfile = Suite.RootDB.activeProfile
    -- Base settings go under the overlay: lift it, write and normalize them,
    -- then lay it again.
    local lifted = Suite.ProfileVariants.LiftOverlay(previousProfile)
    RestoreRoot(Suite.RootDB, state.root, DB.ROOT_SETTINGS, DB.PROFILE_SETTINGS)
    RestoreLayoutState(Suite.RootDB, state.root)
    local active = Suite.RootDB.profiles[Suite.RootDB.activeProfile]
    if type(active) == "table" then
        Suite.DB = active
        S.Normalize(active)
    end
    if lifted then Suite.ProfileVariants.LayOverlay() end
    if type(active) ~= "table" then return false end
    local skin, skinRoot = SkinRoot()
    if type(state.skinRoot) == "table" and type(skinRoot) == "table" and type(skinRoot.profiles) == "table" then
        RestoreRoot(skinRoot, state.skinRoot, SKIN_ROOT_SETTINGS)
        skin.Database.SetActiveProfile(skinRoot.activeProfile)
    end
    -- The restored state reaches the modules in one pass: the skin switch
    -- defers its own pass, then either the controller's profile listener or
    -- ApplyAll applies everything.
    local skinEnabled = Suite.RootDB.skinEnabled == true
    if Suite.Skin.enabled ~= skinEnabled then Suite.Skin.SetEnabled(skinEnabled, true) end
    if previousProfile ~= Suite.RootDB.activeProfile then
        Suite.OnProfileChanged(Suite.RootDB.activeProfile)
    else
        S.ApplyAll()
    end
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
    Suite.Skin.EnsureEngine()
    return P.WithHistory("MSUF Forever suite look", "suite:forever-look", function()
        if not S.ApplyGlobalLook("foreverGlass") then return false end
        if Suite.Skin.EnsureEngine() then
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
        -- Choosing Jundies is an explicit request to use the nameplate skin.
        -- Older Forever profiles started with this optional module disabled.
        if id == "nameplates" and tonumber(value) == 1 then values.enabled = true end
        return values
    end
    if look.custom and look.visualKeys and look.visualKeys[key] and P.Get(id, look.key) ~= look.custom then
        return { [key] = value, [look.key] = look.custom }
    end
end

function P.Set(id, key, value)
    -- Both Colors and the section's three-dot picker use this path. Editing
    -- an active minimap text box chooses its own color in one undoable write.
    if id == "minimap" then
        local box = key:match("^(info%a+Box)Color$")
        if box and P.Get(id, box) == 2 then return P.SetMany(id, { [key] = value, [box] = 3 }) end
    end
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
    P.WithHistory(Tr("%s settings"):format(Tr(P.catalog[id].title)), "suite:" .. id .. ".multiple", function()
        ok, reason = S.SetMany(id, values)
        return ok
    end)
    if ok == nil then ok, reason = false, "Finish combat before editing the suite" end
    P.feedback[id] = not ok and reason or nil
    P.Refresh()
    return ok, reason
end

-- Module availability, kept for one menu refresh. Every control asks through
-- P.RuleEnabled, and each answer costs AddOn API calls (and a status string
-- while the AddOn is off). The first refresher of every Suite page and of the
-- Colors category (Register.lua, Controls.lua) starts a new pass.
local availableOk, availableWhy = {}, {}
function P.ForgetAvailability()
    for id in pairs(availableOk) do availableOk[id], availableWhy[id] = nil, nil end
end

function P.Available(id)
    local ok = availableOk[id]
    if ok == nil then
        local why
        ok, why = S.Availability(id)
        ok = ok == true
        availableOk[id], availableWhy[id] = ok, why
    end
    return ok, availableWhy[id]
end

-- Drops the cached Suite search rows; Search.lua replaces it with the host's
-- way once it registered the provider.
function P.InvalidateSearch() end

-- Repaints the visible suite page; controller changes queued in combat reach
-- the menu through Suite.Options.RefreshAll (set in Register.lua).
function P.Refresh()
    P.ForgetAvailability()
    P.InvalidateSearch()
    P.RefreshSkinPageShape()
    if M.RequestRefresh then M.RequestRefresh(nil, "suite") end
end

function P.Combat() return Suite.IsCombatLocked() end

-- A yes/no question in Blizzard's generic confirmation dialog: the pages add
-- no entry to Blizzard's StaticPopupDialogs. text is translated text, shown
-- as is; onAccept runs on Yes. S.Confirm (MSUF_Suite_Modules/Dialogs.lua)
-- also closes an earlier question under the same key; the pages work while
-- that load-on-demand runtime is not loaded, so they open Blizzard's dialog
-- themselves then.
function P.Confirm(key, text, onAccept)
    local data = { text = "%s", text_arg1 = text, callback = onAccept }
    if S.Confirm then return S.Confirm(key, data) end
    StaticPopup_ShowCustomGenericConfirmation(data)
end

-- Named capability checks used by catalog rules (rule.requires). Pages add
-- entries; unknown names are treated as available.
P.Requires = {}
-- Per-module extra gates: function(rule, key) -> boolean.
P.Gates = {}
-- Shared editors may select a compatible instance before search focuses its
-- widget. These callbacks change only the page's current selection.
P.SearchPreparers = {}
-- Per-module, per-key choice gates: function(choiceIndex) -> boolean.
P.ChoiceGates = {}

-- Enable is a stored preference; other rules require an available, enabled
-- module and satisfied presentation dependencies. `resolve` maps a
-- template rule key to the live key when a page edits one of several bars or
-- windows through shared controls.
local function RuleKey(resolve, key) return resolve and resolve(key) or key end
local function RuleLabel(id, key)
    local rule = P.catalog[id].rules[key]
    return Tr(rule and rule.label or key)
end
local function Blocked(explain, template, label)
    if not explain then return false end
    return false, label and Tr(template):format(label) or Tr(template)
end
function P.RuleEnabled(id, rule, resolve, explain)
    if P.Combat() then return Blocked(explain, "Finish combat before editing the suite") end
    if rule.key == "enabled" then return true end
    local available, why = P.Available(id)
    if not available then return Blocked(explain, why or "Unavailable on this client.") end
    if not P.Get(id, "enabled") then
        return Blocked(explain, "Turn on \"%s\" to change this.", explain and Tr(P.catalog[id].title))
    end
    local seen, current = 0, rule
    while current and current.enableKey and seen < 4 do
        if not P.Get(id, RuleKey(resolve, current.enableKey)) then
            return Blocked(explain, "Turn on \"%s\" to change this.", explain and RuleLabel(id, current.enableKey))
        end
        current = P.catalog[id].rules[current.enableKey]
        seen = seen + 1
    end
    if rule.disabledBy and P.Get(id, RuleKey(resolve, rule.disabledBy)) then
        return Blocked(explain, "Turn off \"%s\" to change this.", explain and RuleLabel(id, rule.disabledBy))
    end
    local choice = rule.requiresChoice
    if choice and not choice.values[P.Get(id, RuleKey(resolve, choice.key))] then
        if not explain then return false end
        local choices, labels = P.catalog[id].rules[choice.key], {}
        for value, label in ipairs(choices and choices.choices or {}) do
            if choice.values[value] then labels[#labels + 1] = Tr(label) end
        end
        if #labels > 0 then
            return false, Tr("Choose %s for \"%s\"."):format(table.concat(labels, " / "), RuleLabel(id, choice.key))
        end
        return Blocked(explain, "Unavailable with the current settings.")
    end
    if rule.requires and P.Requires[rule.requires] and not P.Requires[rule.requires]() then
        return Blocked(explain, "Unavailable on this client.")
    end
    local gate = P.Gates[id]
    if gate then
        local ok, reason = gate(rule, RuleKey(resolve, rule.key))
        if ok == false then return Blocked(explain, reason or "Unavailable with the current settings.") end
    end
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

-- Menu2's font strings and buttons translate what they are given (T.Font,
-- T.Button). Text that is in the reader's language already (translated,
-- composed or data) goes through their raw setter, so it is not looked up
-- a second time: T.SetTranslatedText where the host has it.
function P.SetTranslatedText(fontString, text)
    if T.SetTranslatedText then return T.SetTranslatedText(fontString, text or "") end
    local raw = fontString._msuf2RawSetText or fontString.SetText
    return raw(fontString, text or "")
end
function P.SetButtonText(button, text)
    local label = button._msuf2Label
    if label then return P.SetTranslatedText(label, text) end
    return button:SetText(text or "")
end

-- English text; Menu2's font string translates it.
function P.Text(parent, text, x, y, width, color)
    local label = T.Font(parent, "GameFontHighlightSmall", text or "", color or T.colors.muted, "supporting")
    label:SetPoint("TOPLEFT", x or 16, y or 0)
    label:SetWidth(width or 300)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    return label
end

-- Concise copy is authored alongside the full explanation, never cut mid-sentence.
function P.Help(summary, details) return { summary = summary, details = details } end
function P.Description(parent, text, x, y, width, title)
    local details
    if type(text) == "table" then
        details, text = text.details, text.summary
        -- Older hosts keep all instructions visible until they support detail help.
        if not P.W.DescriptionDetails then text, details = details, nil end
    end
    if P.W.Description then return P.W.Description(parent, text, x, y, width, title, details) end
    return P.Text(parent, text, x, y, width)
end

-- Buttons follow the page's enable rules: pass `enabled` (function) to gate.
function P.Button(ctx, parent, label, x, y, width, onClick, enabled, meta)
    local button = T.Button(parent, label, width or 180, 26)
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

-- A page button whose click runs one line of Blizzard's macro commands, such
-- as /editmode, from secure code. The pages stay insecure: while the pointer
-- rests on an enabled button out of combat, one SecureActionButtonTemplate
-- overlay in UIParent covers it, and the hardware click runs the macro there
-- (SecureActionButton_OnClick, Blizzard_FrameXML/SecureTemplates.lua). The
-- overlay never lives inside the menu. PLAYER_REGEN_DISABLED arrives before
-- the lockdown and releases it; a "[combat] hide" state driver backs that up.
local secure
local function SecureDetach()
    if not secure or P.Combat() then return end
    secure.owner = nil
    secure:Hide()
    secure:ClearAllPoints()
end
local function SecureForward(owner, script)
    local handler = owner and owner:GetScript(script)
    if handler then handler(owner) end
end
-- From the combat start until its end no hover attaches the overlay again;
-- the lockdown itself begins only after the PLAYER_REGEN_DISABLED handlers.
local function SecureCombat(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self.combat = false
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local owner = self.owner
    self.combat = true
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    SecureDetach()
    SecureForward(owner, "OnLeave")
end
local function SecureOverlay()
    if secure then return secure end
    secure = CreateFrame("Button", nil, _G.UIParent, "SecureActionButtonTemplate")
    secure.combat = false
    secure:RegisterForClicks("LeftButtonUp")
    -- SecureActionButton_OnClick acts on the press while ActionButtonUseKeyDown
    -- is on; the overlay registers the release, which must be the click.
    secure:SetAttribute("useOnKeyDown", false)
    secure:SetAttribute("type1", "macro")
    -- The covered button keeps its hover look and tooltip.
    secure:SetScript("OnEnter", function(self) SecureForward(self.owner, "OnEnter") end)
    secure:SetScript("OnLeave", function(self)
        local owner = self.owner
        SecureDetach()
        SecureForward(owner, "OnLeave")
    end)
    secure:SetScript("OnEvent", SecureCombat)
    secure:RegisterEvent("PLAYER_REGEN_DISABLED")
    secure:Hide()
    RegisterStateDriver(secure, "visibility", "[combat] hide")
    return secure
end
local function SecureAttach(button)
    if P.Combat() or secure and secure.combat or not button.secureMacro or not button.secureReady() then return end
    local overlay = SecureOverlay()
    if overlay.owner == button and overlay:IsShown() then return end
    overlay.owner = button
    overlay:SetAttribute("macrotext1", button.secureMacro)
    overlay:SetFrameStrata(button:GetFrameStrata())
    overlay:SetFrameLevel(button:GetFrameLevel() + 5)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(button)
    overlay:Show()
end
function P.SecureMacroButton(ctx, parent, label, x, y, width, macro, enabled, meta)
    local button = T.Button(parent, label, width or 180, 26)
    button:SetPoint("TOPLEFT", x, y)
    button.secureMacro = macro
    button.secureReady = function() return not enabled or enabled() and true or false end
    button:HookScript("OnEnter", SecureAttach)
    button:HookScript("OnHide", function(self)
        if secure and secure.owner == self then SecureDetach() end
    end)
    if meta and M.RegisterControlMetadata then M.RegisterControlMetadata(button, meta, label, "button") end
    M.TrackRefresh(ctx, function() button:SetEnabled(button.secureReady() and not P.Combat()) end)
    return button
end

-- Collapsible bodies built with explicit positions report their height here,
-- through the builder's own auto-height path.
function P.FinishBody(b, body, bottomY, pad)
    body._msuf2CursorY = math.min(bottomY, -39)
    if b.FinishSection then b:FinishSection(body, pad or 12) end
end

-- Module status line: availability, controller status and page feedback.
-- Statuses arrive as English text and are translated here, once.
function P.StatusText(id)
    local reason = P.feedback[id]
    if reason then return Suite.StatusText(reason, Tr) end
    local ok, why = P.Available(id)
    if not ok then return Suite.StatusText(why or "Unavailable on this client", Tr) end
    return Suite.StatusText(S.Status(id), Tr)
end

function P.RegisterPage(spec)
    assert(type(spec.key) == "string" and type(spec.build) == "function", "invalid suite page")
    P.pages[#P.pages + 1] = spec
end

-- S.OpenEditMode is an export of the load-on-demand runtime (EditMode.lua),
-- which loads with the first active module. Edit Mode buttons stay disabled
-- until it exists.
function P.EditModeReady()
    return S.OpenEditMode ~= nil
end

-- Opens MSUF Edit Mode with a module's element selected.
function P.OpenEditMode(id, element)
    if P.Combat() or not S.OpenEditMode then return false end
    return S.OpenEditMode(id, element)
end

-- Opens MSUF Edit Mode with a module's element selected; closes the menu.
function P.MoveOnScreen(id, element)
    if P.OpenEditMode(id, element) and M.frame and M.frame.Hide then M.frame:Hide() end
end
