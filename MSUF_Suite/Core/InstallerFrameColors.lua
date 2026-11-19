local _, Suite = ...
-- Frame colors are staged separately from the Suite and Skin palettes.
local F = {}
Suite.InstallerFrameColors = F
local choices = {}
local SCOPES = { { "unit", "Unit Frames" }, { "group", "Group Frames" } }
local MODES = {
    { "profile", "Profile colors" }, { "class", "Class Colors" }, { "dark", "Dark Mode" }, { "unified", "Unified" },
}
local UNITS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena",
    "boss1", "boss2", "boss3", "boss4", "boss5", "arena1", "arena2", "arena3", "arena4", "arena5" }
local GROUPS = { "gf_party", "gf_raid", "gf_mythicraid", "gf_priority" }
local cachedSource, cachedPreview
local pickerSession, hookedPicker
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Valid(mode) return mode == "class" or mode == "dark" or mode == "unified" end

local function GlobalMode(general)
    local mode = general and general.barMode
    mode = type(mode) == "string" and string.lower(mode)
    if mode == "gradient" and general.enableHealthGradient == false then return "class" end
    return (Valid(mode) or mode == "gradient") and mode or general and general.useClassColors and "class" or "dark"
end

local function UnifiedRGB(frames, scope)
    local general = frames and frames.general or {}
    local group = scope == "group" and frames and frames.gf_party or {}
    return group.gfUnifiedR or general.unifiedBarR or .1, group.gfUnifiedG or general.unifiedBarG or .6,
        group.gfUnifiedB or general.unifiedBarB or .9
end

local function GroupConfig(frames, key)
    local config = frames[key]
    if type(config) == "table" then return config end
    -- Older hosts have no priority group. The other groups share the
    -- global fallback until their own settings have been materialized.
    if key == "gf_priority" then return end
    config = {}
    frames[key] = config
    return config
end

local function RetainGroupModes(copy, retainUnifiedColor)
    local previous = GlobalMode(copy.general)
    local r, g, b = UnifiedRGB(copy, "unit")
    for _, key in ipairs(GROUPS) do
        local config = GroupConfig(copy, key)
        if config then
            local mode = type(config.gfBarMode) == "string" and string.lower(config.gfBarMode)
            if not Valid(mode) and mode ~= "gradient" and mode ~= "custom" then
                mode = previous
                config.gfBarMode = mode == "class" and "CLASS" or mode
            end
            if retainUnifiedColor and mode == "unified" then
                config.gfUnifiedR, config.gfUnifiedG, config.gfUnifiedB = config.gfUnifiedR or r, config.gfUnifiedG or g,
                    config.gfUnifiedB or b
            end
        end
    end
end

function F.Reset()
    F.ClosePicker()
    choices, cachedSource, cachedPreview = {}, nil, nil
end

function F.Choices()
    if not next(choices) then return nil end
    return Suite.CopyValue(choices)
end

local function ValidColor(color)
    return color == nil or type(color) == "string" and #color == 6 and color:match("^%x+$") ~= nil
end

function F.Apply(frames, modes)
    if type(frames) ~= "table" or type(modes) ~= "table" then return nil end
    if modes.unit ~= nil and not Valid(modes.unit) or modes.group ~= nil and not Valid(modes.group) then return nil end
    if not ValidColor(modes.unitColor) or not ValidColor(modes.groupColor) then return nil end
    local copy = Suite.CopyValue(frames)
    if modes.unit then
        -- GLOBAL groups must keep their effective mode when the unit-only
        -- choice changes the general fallback used by MSUF's compiler.
        if not modes.group then RetainGroupModes(copy, modes.unit == "unified" and modes.unitColor ~= nil) end
        copy.general = copy.general or {}
        copy.general.barMode = modes.unit
        copy.general.darkMode, copy.general.useClassColors = modes.unit == "dark", modes.unit == "class"
        if modes.unit == "unified" and modes.unitColor then
            copy.general.unifiedBarR, copy.general.unifiedBarG, copy.general.unifiedBarB = Suite.RGB(modes.unitColor)
        end
        for _, key in ipairs(UNITS) do
            if type(copy[key]) == "table" then copy[key].healthColorMode = string.upper(modes.unit) end
        end
    end
    if modes.group then
        local r, g, b
        if modes.group == "unified" and modes.groupColor then r, g, b = Suite.RGB(modes.groupColor) end
        for _, key in ipairs(GROUPS) do
            local config = GroupConfig(copy, key)
            if config then
                config.gfBarMode = modes.group == "class" and "CLASS" or modes.group
                if r then config.gfUnifiedR, config.gfUnifiedG, config.gfUnifiedB = r, g, b end
            end
        end
    end
    return copy
end

function F.Preview(frames)
    if not frames or not next(choices) then return frames end
    if cachedSource ~= frames then
        cachedSource, cachedPreview = frames, F.Apply(frames, choices)
    end
    return cachedPreview
end

local function Mode(frames, scope)
    local general = frames and frames.general or {}
    local config = frames and (scope == "group" and frames.gf_party or frames.player)
    local mode = config and (scope == "group" and config.gfBarMode or config.healthColorMode)
    if not mode or mode == "GLOBAL" then mode = GlobalMode(general) end
    return type(mode) == "string" and string.lower(mode) or "dark"
end

local function Hex(r, g, b)
    return string.format("%02x%02x%02x", math.floor(math.max(0, math.min(1, r)) * 255 + .5),
        math.floor(math.max(0, math.min(1, g)) * 255 + .5), math.floor(math.max(0, math.min(1, b)) * 255 + .5))
end

function F.HealthFill(frames, scope, config, sampleReaction)
    local general = frames and frames.general or {}
    local mode
    if scope == "group" then
        mode = Mode(frames, scope)
    else
        config = config or frames and frames.player
        mode = config and config.healthColorMode
        mode = type(mode) == "string" and string.lower(mode)
        if not Valid(mode) and mode ~= "gradient" then
            mode = GlobalMode(general)
        end
    end
    if mode == "class" then
        local npc = sampleReaction and frames.npcColors and frames.npcColors[sampleReaction]
        if type(npc) == "table" then
            local r, g, b = npc.r or npc[1], npc.g or npc[2], npc.b or npc[3]
            if Suite.Finite(r) and Suite.Finite(g) and Suite.Finite(b) then return Hex(r, g, b) end
        end
        local _, class = UnitClass("player")
        local color = class and C_ClassColor.GetClassColor(class)
        return color and Hex(color.r, color.g, color.b) or "e6ecf2"
    end
    local group = scope == "group" and frames and frames.gf_party or {}
    if mode == "unified" then
        return Hex(UnifiedRGB(frames, scope))
    end
    if mode == "dark" then
        local gray = general.darkBarGray or general.darkBgBrightness or .07
        if gray > 1 then gray = gray / 100 end
        return Hex(group.gfDarkR or general.darkBarR or gray, group.gfDarkG or general.darkBarG or gray,
            group.gfDarkB or general.darkBarB or gray)
    end
end

local function SelectColor(scope, mode, color)
    choices[scope], choices[scope .. "Color"] = mode, color
    cachedSource, cachedPreview = nil, nil
end

local function RestorePickerWindow(picker)
    local session = pickerSession
    if not session or session.picker ~= picker then return end
    pickerSession = nil
    -- Some native button handlers hide the picker before calling their callback.
    C_Timer.After(0, function() session.closed = true end)
    session.window:SetFrameStrata(session.strata)
    if session.window:IsShown() then Suite.Client.ResumeControllerWindow(session.window) end
end

function F.ClosePicker()
    local session = pickerSession
    if not session then return end
    session.closed = true
    RestorePickerWindow(session.picker)
    if session.picker.cancelFunc == session.cancel and session.picker:IsShown() then
        SelectColor(session.scope, session.mode, session.color)
        session.picker:Hide()
    end
end

local function OpenUnifiedPicker(panel, scope)
    local picker = _G.ColorPickerFrame
    if not picker or not picker.SetupColorPickerAndShow or picker:IsShown() then return end
    if hookedPicker ~= picker then
        picker:HookScript("OnHide", RestorePickerWindow)
        hookedPicker = picker
    end
    local window, staged = panel:GetParent(), choices
    local session = { picker = picker, window = window, strata = window:GetFrameStrata(),
        scope = scope, mode = staged[scope], color = staged[scope .. "Color"] }
    function session.cancel()
        if session.closed or choices ~= staged then return end
        SelectColor(scope, session.mode, session.color)
        Suite.Installer.Refresh()
    end
    local function Pick()
        if session.closed or choices ~= staged then return end
        local r, g, b = picker:GetColorRGB()
        if not (Suite.Finite(r) and Suite.Finite(g) and Suite.Finite(b)) then return end
        SelectColor(scope, "unified", Hex(r, g, b))
        Suite.Installer.Refresh()
    end
    local r, g, b = UnifiedRGB(panel.frameColorFrames, scope)
    SelectColor(scope, "unified", Hex(r, g, b))
    pickerSession = session
    window:SetFrameStrata("HIGH")
    picker:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, swatchFunc = Pick, cancelFunc = session.cancel })
    Suite.Installer.Refresh()
end

function F.Build(panel)
    local A = Suite.InstallerAppearance
    panel.frameColors = {}
    for index, scope in ipairs(SCOPES) do
        local key = scope[1]
        local row = { scope = key, buttons = {} }
        row.label = A.Label(panel, "GameFontNormalSmall", 14, -228 - (index - 1) * 54, 260, 18)
        row.label:SetText(Suite.Text(scope[2]))
        row.sample = panel:CreateTexture(nil, "ARTWORK")
        row.sample:SetTexture(WHITE)
        row.sample:SetSize(40, 10)
        row.sample:SetPoint("TOPRIGHT", row.label, "TOPRIGHT", 52, -3)
        for slot, mode in ipairs(MODES) do
            local value = mode[1]
            local button = A.Button(panel, 14 + (slot - 1) * 79, 112 - (index - 1) * 54, 75,
                Suite.Text(mode[2]), function()
                    if value == "unified" then
                        OpenUnifiedPicker(panel, key)
                    else
                        F.ClosePicker()
                        SelectColor(key, value ~= "profile" and value or nil)
                        Suite.Installer.Refresh()
                    end
                end)
            button.mode = value
            button.caption:SetSize(71, 28)
            row.buttons[slot] = button
        end
        panel.frameColors[index] = row
    end
    panel.frameColorHint = A.Label(panel, "GameFontHighlightSmall", 14, -338, 312, 44)
    panel.frameColorHint:SetText(Suite.Text("Changing colors saves a new profile."))
end

function F.Show(panel, shown, keepFrames, frames)
    if not shown then F.ClosePicker() end
    panel.frameColorFrames = shown and frames or nil
    for _, label in ipairs({ panel.viewport, panel.frameSource, panel.info, panel.note, panel.modules }) do
        label:SetShown(not shown)
    end
    for _, row in ipairs(panel.frameColors) do
        row.label:SetShown(shown)
        row.sample:SetShown(shown)
        local color = F.HealthFill(frames, row.scope)
        row.sample:SetVertexColor(Suite.RGB(color or "e6ecf2"))
        for _, button in ipairs(row.buttons) do
            button:SetShown(shown)
            Suite.InstallerAppearance.Style(button, button.mode == (choices[row.scope] or "profile"))
        end
    end
    panel.frameColorHint:SetShown(shown and keepFrames == true)
end
