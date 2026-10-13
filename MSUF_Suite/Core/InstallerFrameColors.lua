local _, Suite = ...
-- Frame colors are staged separately from Suite/Skin palettes. Only copied
-- factory payloads are edited; retaining current frames retains their colors.
local F = {}
Suite.InstallerFrameColors = F
local choices = {}
local SCOPES = { { "unit", "Unit Frames" }, { "group", "Group Frames" } }
local MODES = { { "class", "Class Colors" }, { "dark", "Dark Mode" }, { "unified", "Unified" } }
local UNITS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena",
    "boss1", "boss2", "boss3", "boss4", "boss5", "arena1", "arena2", "arena3", "arena4", "arena5" }
local GROUPS = { "gf_party", "gf_raid", "gf_mythicraid" }
local cachedSource, cachedPreview
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Valid(mode) return mode == "class" or mode == "dark" or mode == "unified" end

local function GlobalMode(general)
    local mode = general and general.barMode
    mode = type(mode) == "string" and string.lower(mode)
    if mode == "gradient" and general.enableHealthGradient == false then return "class" end
    return (Valid(mode) or mode == "gradient") and mode or general and general.useClassColors and "class" or "dark"
end

local function RetainGroupModes(copy)
    local previous = GlobalMode(copy.general)
    for _, key in ipairs(GROUPS) do
        local config = copy[key] or {}
        local mode = config.gfBarMode
        mode = type(mode) == "string" and string.lower(mode)
        if not Valid(mode) and mode ~= "gradient" and mode ~= "custom" then
            config.gfBarMode = previous == "class" and "CLASS" or previous
            copy[key] = config
        end
    end
end

function F.Reset()
    choices, cachedSource, cachedPreview = {}, nil, nil
end

function F.Choices()
    if not next(choices) then return nil end
    return { unit = choices.unit, group = choices.group }
end

function F.Apply(frames, modes)
    if type(frames) ~= "table" or type(modes) ~= "table" then return nil end
    if modes.unit ~= nil and not Valid(modes.unit) or modes.group ~= nil and not Valid(modes.group) then return nil end
    local copy = Suite.CopyValue(frames)
    if modes.unit then
        -- GLOBAL groups must keep their effective mode when the unit-only
        -- choice changes the general fallback used by MSUF's compiler.
        if not modes.group then RetainGroupModes(copy) end
        copy.general = copy.general or {}
        copy.general.barMode = modes.unit
        copy.general.darkMode, copy.general.useClassColors = modes.unit == "dark", modes.unit == "class"
        for _, key in ipairs(UNITS) do
            if type(copy[key]) == "table" then copy[key].healthColorMode = string.upper(modes.unit) end
        end
    end
    if modes.group then
        for _, key in ipairs(GROUPS) do
            copy[key] = copy[key] or {}
            copy[key].gfBarMode = modes.group == "class" and "CLASS" or modes.group
        end
    end
    return copy
end

function F.Preview(frames, keepFrames)
    if keepFrames or not frames or not next(choices) then return frames end
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

function F.HealthFill(frames, scope, config)
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
        local _, class = UnitClass("player")
        local color = class and C_ClassColor.GetClassColor(class)
        return color and Hex(color.r, color.g, color.b) or "e6ecf2"
    end
    local group = scope == "group" and frames and frames.gf_party or {}
    if mode == "unified" then
        return Hex(group.gfUnifiedR or general.unifiedBarR or .1, group.gfUnifiedG or general.unifiedBarG or .6,
            group.gfUnifiedB or general.unifiedBarB or .9)
    end
    if mode == "dark" then
        local gray = general.darkBarGray or general.darkBgBrightness or .07
        if gray > 1 then gray = gray / 100 end
        return Hex(group.gfDarkR or general.darkBarR or gray, group.gfDarkG or general.darkBarG or gray,
            group.gfDarkB or general.darkBarB or gray)
    end
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
            local button = A.Button(panel, 14 + (slot - 1) * 106, 112 - (index - 1) * 54, 100,
                Suite.Text(mode[2]), function()
                    if panel.retainFrameColors then return end
                    choices[key], cachedSource, cachedPreview = value, nil, nil
                    Suite.Installer.Refresh()
                end)
            button.mode = value
            button.caption:SetSize(94, 28)
            row.buttons[slot] = button
        end
        panel.frameColors[index] = row
    end
    panel.frameColorHint = A.Label(panel, "GameFontHighlightSmall", 14, -338, 312, 44)
    panel.frameColorHint:SetText(Suite.Text("Keeping current MSUF frames also keeps their colors."))
end

function F.Show(panel, shown, keepFrames, frames)
    panel.retainFrameColors = keepFrames
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
            button:SetEnabled(not keepFrames)
            button:SetAlpha(keepFrames and .45 or 1)
            Suite.InstallerAppearance.Style(button, button.mode == Mode(frames, row.scope))
        end
    end
    panel.frameColorHint:SetShown(shown and keepFrames == true)
end
