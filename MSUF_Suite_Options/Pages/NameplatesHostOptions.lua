local _, P = ...
local Suite, Tr = P.Suite, P.Tr
local UI = {}
P.NameplatesHostOptions = UI
local PAGE, ID = "suite_nameplates", "nameplates"
-- The host section this page edits. Interrupt readiness has no rows here: its
-- look is MSUF's castbar menu's, for castbars and nameplates alike.
local SECTION = "nameplates"
local contexts = setmetatable({}, { __mode = "k" })

local function Capture(state)
    if state.profile ~= Suite.DB or not state.shared then
        state.shared, state.exact = Suite.ProfileIO.CaptureNameplateShared()
        state.shared, state.profile = state.shared or {}, Suite.DB
    end
    return state.shared, state.exact
end

local function Get(state, section, key)
    local value, exact = Capture(state)
    if key == "fontOverride" then
        if Suite.HostBridge.HasNameplateFontSettings() then
            return exact and exact.nameplates and exact.nameplates.fontOverride == true or false
        end
        local stored = Suite.DB and Suite.DB.nameplateShared
        return stored and stored.nameplates and next(stored.nameplates) ~= nil and stored.nameplates.fontOverride ~= false or false
    end
    return value and value[section] and value[section][key]
end

local function ApplyShared(payload)
    local db = Suite.DB
    local _, exact = Suite.ProfileIO.CaptureNameplateShared()
    local stored, pending = Suite.CopyValue(db.nameplateShared), Suite.CopyValue(db.nameplateSharedPending)
    local ran, ok, reason = Suite.Dispatch(Suite.Finish, Suite.ProfileIO.ApplyNameplateShared, payload)
    if ran and ok then return true end
    local restored, accepted = Suite.Dispatch(Suite.Finish, Suite.HostBridge.ApplyNameplateSettings, exact)
    db.nameplateShared, db.nameplateSharedPending = stored, pending
    local painted = Suite.Dispatch(Suite.Finish, Suite.Suite.Apply, ID)
    if not restored or not accepted or not painted then
        return false, "Profile import failed; restore the previous profiles manually"
    end
    return false, reason or "Nameplate settings could not be applied"
end

local function Apply(state, payload)
    if P.Combat() then return end
    local ran, ok, reason
    P.WithHistory("Before editing nameplate text or interrupts", "suite:nameplates.host", function()
        ran, ok, reason = Suite.Dispatch(Suite.Finish, ApplyShared, payload)
        ok = ran and ok
        return ok
    end)
    if not ok then
        P.M.ShowStatusFeedback(Tr(reason or "Nameplate settings could not be applied"), "danger", 4)
    end
    state.shared = nil
    P.Refresh()
end

local function Set(state, section, key, value)
    if key == "fontOverride" and value == true then
        local shared = Capture(state)
        local typography = Suite.CopyValue(shared.nameplates or {})
        typography.fontOverride = true
        Apply(state, { version = 1, nameplates = typography })
    elseif value == "" then Apply(state, { version = 1, clear = { section .. "." .. key } })
    else Apply(state, { version = 1, [section] = { [key] = value } }) end
end

local function Row(state, section, key, label, kind)
    local row = P.Meta(PAGE, ID, "host." .. key, "setting", PAGE .. "_host_" .. section)
    row.id, row.kind, row.label = key, kind, Tr(label)
    row.get = function() return Get(state, section, key) end
    row.set = function(value) Set(state, section, key, value) end
    return row
end

local function Toggle(state, section, key, label, default)
    local row = Row(state, section, key, label, "toggle")
    row.get = function()
        local value = Get(state, section, key)
        if value == nil then return default == true end
        return value == true
    end
    return row
end

local function Slider(state, section, key, label, default, minimum, maximum, step)
    local row = Row(state, section, key, label, "slider")
    row.default, row.min, row.max, row.step = default, minimum, maximum, step or 1
    row.roundStep = row.step >= 1
    row.get = function()
        local value = Get(state, section, key)
        if value == nil then return default end
        return value
    end
    return row
end

local function Choice(state, section, key, label, options)
    local row = Row(state, section, key, label, "dropdown")
    row.values = {}
    for _, option in ipairs(options) do
        row.values[#row.values + 1] = { value = option[1], text = Tr(option[2]) }
    end
    row.get = function() return Get(state, section, key) or options[1][1] end
    return row
end

local function DeferredRow(row)
    local get, set = row.get, row.set
    local edit = {}
    function edit.Begin()
        if edit.active and edit.current() then return end
        edit.active, edit.current, edit.values, edit.queued = true, P.ProfileGuard(), nil, nil
    end
    function edit.Finish()
        if not edit.active or edit.queued then return end
        edit.queued = true
        local current = edit.current
        -- Native sliders can send a final value after MouseUp/Hide.
        -- One event turn includes that last value before committing.
        C_Timer.After(0, function()
            if edit.current ~= current then return end
            local values = edit.values
            edit.active, edit.queued, edit.values, edit.current = nil, nil, nil, nil
            if not values or not current() then return end
            local current, changed = { get() }, false
            for index, value in ipairs(values) do
                if current[index] ~= value then changed = true end
            end
            if changed then set(unpack(values)) end
        end)
    end
    row.get = function()
        if edit.values and edit.current() then return unpack(edit.values) end
        return get()
    end
    row.set = function(...)
        if edit.active and edit.current() or edit.isActive and edit.isActive() then
            edit.Begin()
            edit.values = { ... }
        else set(...) end
    end
    return edit
end

local function DeferredRows(rows)
    local edits = {}
    for _, row in ipairs(rows) do
        if row.kind == "slider" then edits[row.id] = DeferredRow(row) end
    end
    return edits
end

local function FontRows(state)
    local rows = {
        Toggle(state, "nameplates", "fontOverride", "Customize nameplate typography"),
        Slider(state, "nameplates", "fontSize", "Nameplate text size", 12, 6, 40),
        Slider(state, "nameplates", "nameFontSize", "Name size", 12, 6, 40),
        Toggle(state, "nameplates", "noOutline", "Hide text outline"),
        Toggle(state, "nameplates", "boldText", "Thick text outline"),
        Toggle(state, "nameplates", "fontMonochrome", "Monochrome text"),
        Toggle(state, "nameplates", "fontSlug", "Use Slug text rendering"),
        Toggle(state, "nameplates", "textBackdrop", "Text shadow", true),
        Slider(state, "nameplates", "fontShadowOpacity", "Text shadow opacity", 1, .2, 1, .01),
        Slider(state, "nameplates", "fontShadowDistance", "Text shadow distance", 1, 1, 2),
        Slider(state, "nameplates", "fontTextAlpha", "Text opacity", 1, .7, 1, .01),
        Slider(state, "nameplates", "fontBaselineOffset", "Text baseline offset", 0, -4, 4),
        Choice(state, "nameplates", "nameFormat", "Name format", {
            { "FULL", "Full name" }, { "CUT", "Truncate" }, { "ABBREV", "Abbreviate" }, { "ABBREV_CUT", "Abbreviate and truncate" } }),
        Slider(state, "nameplates", "shortenNameMaxChars", "Maximum name characters", 12, 4, 40),
        Choice(state, "nameplates", "shortenNameClipSide", "Clip name on", { { "LEFT", "Left" }, { "RIGHT", "Right" } }),
        Toggle(state, "nameplates", "shortenNameShowDots", "Show ellipsis", true),
        Toggle(state, "nameplates", "nameClassColor", "Class-colored player names"),
        Toggle(state, "nameplates", "npcNameRed", "Red NPC names"),
    }
    local font = Row(state, "nameplates", "fontKey", "Nameplate font", "dropdown")
    font.values = function() return P.FontValues(Get(state, "nameplates", "fontKey")) end
    font.get = function() return Get(state, "nameplates", "fontKey") or "" end
    table.insert(rows, 2, font)
    return rows
end

local function Content(ctx, builder, body, state)
    local width = math.max(240, (P.HM.GetSectionWidth(body) or builder.width or 720) - 32)
    local rows = FontRows(state)
    local label = P.Description(body, "Nameplate typography is included when sharing a complete nameplate setup.", 16, -12, width)
    local y = -24 - math.max(14, label:GetStringHeight() or 14)
    local edits = DeferredRows(rows)
    local grid = P.W.SettingsRows(ctx, body, { x = 16, y = y, width = width, columns = 2, rows = rows })
    for _, row in ipairs(rows) do
        local edit = edits[row.id]
        if edit then
            edit.isActive = P.HM.TrackControlInteraction(grid.controls[row.id], row.kind, edit.Begin, edit.Finish)
        end
    end
    y = grid.bottomY - 12
    P.Button(ctx, body, "Use inherited settings", 16, y, 220, function()
        local clear = {}
        for _, key in ipairs(Suite.NameplateHostSettings.Keys(SECTION)) do
            if key ~= "fontOverride" then clear[#clear + 1] = SECTION .. "." .. key end
        end
        Apply(state, { version = 1, clear = clear, nameplates = { fontOverride = false } })
    end, nil, P.Meta(PAGE, ID, "host.reset." .. SECTION, "action", PAGE .. "_host_" .. SECTION))
    P.M.TrackRefresh(ctx, function()
        local enabled, typography = not P.Combat(), Get(state, SECTION, "fontOverride")
        for _, row in ipairs(rows) do grid.controls[row.id]:SetEnabled(enabled and (typography or row.id == "fontOverride")) end
    end)
    P.FinishBody(builder, body, y - 44)
end

function UI.Build(ctx, builder)
    local state = contexts[ctx]
    if not state then
        state = {}
        contexts[ctx] = state
        P.M.TrackRefresh(ctx, function() state.shared = nil end)
    end
    return P.LazySection(builder, PAGE .. "_host_" .. SECTION, Tr("Shared nameplate typography"), false, {
        content = function(body) Content(ctx, builder, body, state) end,
    })
end
