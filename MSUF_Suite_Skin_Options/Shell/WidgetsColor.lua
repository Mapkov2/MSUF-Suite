local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

-- Color rows: swatch, hex field and the color pickers (see Widgets.lua).
local Widgets = Private.Widgets
local CanChange = Widgets.CanChange
local ColorChanged = Widgets.ColorChanged
local CreateInputBox = Widgets.CreateInputBox
local popups = Widgets.popups
local WatchCombat = Widgets.WatchCombat

-- Cancels our color picker if it is still the one Blizzard shows.
local function CancelColorPicker()
    local cancel = popups.pickerCancel
    popups.pickerCancel = nil
    local picker = ColorPickerFrame
    if cancel and NS.Safety.Read(picker, "IsShown") == true and picker.cancelFunc == cancel then
        cancel()
        picker:Hide()
    end
end
Widgets.CloseOnCombat(CancelColorPicker)

local function IsEmbeddedCard(card)
    local host = O.embeddedHost
    for _ = 1, 16 do
        if not card then break end
        if card == host then return true end
        card = card:GetParent()
    end
    return false
end

local function ColorHistoryLabel(colorKey)
    return L["Color: %s"]:format(tostring(colorKey))
end

-- One MSUF context-color target bound to a skin color token.
local function ColorTarget(colorKey, label)
    local profile, epoch = NS.DB, NS.Database.GetHistoryEpoch()
    return {
        label = label,
        hasOpacity = true,
        getRGB = function()
            local color = NS.Theme.GetColorTable(colorKey)
            return color[1], color[2], color[3]
        end,
        getOpacity = function() return NS.Theme.GetColorTable(colorKey)[4] end,
        -- SetColor notifies the options, which repaint once per frame.
        setRGB = function(r, g, b, a)
            if NS.DB ~= profile or NS.Database.GetHistoryEpoch() ~= epoch then return end
            NS.Theme.SetColor(colorKey, r, g, b, a)
        end,
    }
end

-- MSUF's menu widgets belong to another addon; each helper is checked
-- before it is used.
local function MenuWidgets()
    local menu = _G.MSUF2
    return menu and menu.Widgets
end

-- One channel as the 8-bit value the hex field and swatch show.
local function Byte(value)
    return math.floor((value or 0) * 255 + 0.5)
end

-- True when r, g, b, a round to the same 8-bit color as `color`: a picker
-- or hex entry that ends on the shown color changes nothing.
local function SameByteColor(color, r, g, b, a)
    return Byte(color[1]) == Byte(r) and Byte(color[2]) == Byte(g)
        and Byte(color[3]) == Byte(b) and Byte(color[4] or 1) == Byte(a or 1)
end

local function OpenBlizzardColorPicker(colorKey)
    if not CanChange() then return end
    local current = NS.Theme.GetColorTable(colorKey)
    local original = { current[1], current[2], current[3], current[4] }
    local originalPreset = NS.DB.theme.preset
    local originalLook = NS.DB.theme.look
    local profile, epoch = NS.DB, NS.Database.GetHistoryEpoch()
    local micro = profile.icons and profile.icons.microMenu
    local originalMicro = micro and micro.preset
    local historyLabel = ColorHistoryLabel(colorKey)
    local historyCaptured = false
    local changed = false

    -- Blizzard calls this on every color move, again on Okay, and may call
    -- it while the picker opens; the shown color itself changes nothing.
    local function ApplySelection()
        if NS.DB ~= profile or NS.Database.GetHistoryEpoch() ~= epoch or not CanChange() then return end
        local r, g, b = ColorPickerFrame:GetColorRGB()
        local a = ColorPickerFrame:GetColorAlpha()
        if SameByteColor(NS.Theme.GetColorTable(colorKey), r, g, b, a) then return end
        local began = not historyCaptured and O.BeginUserChange(historyLabel)
        if NS.Theme.SetColor(colorKey, r, g, b, a) then changed = true end
        if began then
            O.CommitUserChange(historyLabel)
            historyCaptured = true
        end
    end

    -- Cancel restores the color and the look and palette names SetColor
    -- replaced with "custom"; like every change it waits out combat.
    local function Cancel()
        if popups.pickerCancel == Cancel then
            popups.pickerCancel = nil
            WatchCombat()
        end
        if NS.DB ~= profile or NS.Database.GetHistoryEpoch() ~= epoch or not CanChange() or not changed then return end
        NS.Theme.RestoreColor(colorKey, original[1], original[2], original[3], original[4],
            originalPreset, originalLook, originalMicro)
        if historyCaptured then O.DiscardLastChange(historyLabel) end
        O.RefreshAll()
    end

    popups.pickerCancel = Cancel
    WatchCombat()
    ColorPickerFrame:SetupColorPickerAndShow({
        r = current[1],
        g = current[2],
        b = current[3],
        opacity = current[4],
        hasOpacity = true,
        swatchFunc = ApplySelection,
        opacityFunc = ApplySelection,
        cancelFunc = Cancel,
    })
end

-- Embedded in MSUF, colors open MSUF's own picker so the change joins its
-- history; the standalone window uses Blizzard's color picker.
local function OpenColorPicker(colorKey, card)
    local widgets = MenuWidgets()
    if IsEmbeddedCard(card) and O.embeddedHost:IsShown()
        and widgets and type(widgets.OpenContextColors) == "function" then
        local opened = widgets.OpenContextColors(card, {
            title = tostring(colorKey),
            targets = { ColorTarget(colorKey, tostring(colorKey)) },
            historyLabel = ColorHistoryLabel(colorKey),
            historySource = "suite:skin-color",
        })
        if opened then return end
    end
    OpenBlizzardColorPicker(colorKey)
end

local function FormatHex(color)
    return ("#%02X%02X%02X%02X"):format(Byte(color[1]), Byte(color[2]), Byte(color[3]), Byte(color[4] or 1))
end

local function ParseHex(value, fallbackAlpha)
    value = tostring(value or ""):gsub("%s+", ""):gsub("^#", "")
    if (#value ~= 6 and #value ~= 8) or value:find("[^%x]") then return nil end
    local r = tonumber(value:sub(1, 2), 16)
    local g = tonumber(value:sub(3, 4), 16)
    local b = tonumber(value:sub(5, 6), 16)
    local a = #value == 8 and tonumber(value:sub(7, 8), 16) or Byte(fallbackAlpha or 1)
    if not r or not g or not b or not a then return nil end
    return r / 255, g / 255, b / 255, a / 255
end

local function CreateSwatch(row, colorKey)
    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(52, 24)
    swatch:SetPoint("RIGHT", -10, 0)
    NS.Surface.SkinOwnedButton(swatch, {
        role = "input",
        shape = "continuous",
        radius = 4,
        border = 1,
        useControlShape = false,
    })
    local color = swatch:CreateTexture(nil, "BACKGROUND", nil, -6)
    color:SetPoint("TOPLEFT", 4, -4)
    color:SetPoint("BOTTOMRIGHT", -4, 4)
    swatch:SetScript("OnClick", function() OpenColorPicker(colorKey, row) end)
    return color
end

-- A rejected hex entry reads like a refused profile operation.
local HEX_FORMAT_ERROR = L["Error: %s"]:format(L["Hex colors need 6 or 8 digits (#RRGGBB or #RRGGBBAA)"])

-- The hex field of a color row. Only text the user typed is committed, once:
-- focus loss after Enter or Escape, or a click away from an untouched field,
-- changes nothing, so the look and palette keep their names and no undo step
-- is recorded. Escape discards the typed text. Typed text that is no hex
-- color says so in the row's help line until the next accepted entry or
-- Escape; an emptied field just shows the stored color again. Returns the
-- function that shows (true) or clears (false) the error.
local function BindHexInput(input, help, helpText, colorKey, labelText)
    local edited = false
    local showsError = false
    local function ShowError(show)
        if show == showsError then return end
        showsError = show
        help:SetText(show and HEX_FORMAT_ERROR or helpText)
        O.SetTextColor(help, show and "danger" or "dim")
    end
    local function CommitHex()
        local current = NS.Theme.GetColorTable(colorKey)
        local r, g, b, a
        if edited and CanChange() then
            local text = input:GetText() or ""
            r, g, b, a = ParseHex(text, current[4])
            ShowError(r == nil and text:find("[^%s#]") ~= nil)
        end
        edited = false
        if not r or SameByteColor(current, r, g, b, a) then
            input:SetText(FormatHex(current))
            return
        end
        local began = O.BeginUserChange(labelText)
        NS.Theme.SetColor(colorKey, r, g, b, a)
        if began then O.CommitUserChange(labelText) end
        input:SetText(FormatHex(NS.Theme.GetColorTable(colorKey)))
    end
    input:SetScript("OnTextChanged", function(_, userInput)
        if userInput then edited = true end
    end)
    input:SetScript("OnEnterPressed", function(self)
        CommitHex()
        self:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", function(self)
        edited = false
        ShowError(false)
        self:SetText(FormatHex(NS.Theme.GetColorTable(colorKey)))
        self:ClearFocus()
    end)
    input:SetScript("OnEditFocusLost", CommitHex)
    return ShowError
end

function O.CreateColorRow(parent, colorKey, labelText, width, description)
    local row = O.CreatePanel(parent, "card")
    row:SetSize(width or 600, 50)
    local label = O.CreateText(row, labelText, 12, "text")
    label:SetPoint("TOPLEFT", 12, -8)

    local help = O.CreateText(row, description or colorKey, 9, "dim")
    help:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    help:SetPoint("RIGHT", -250, 0)

    local input = CreateInputBox(row, 7)
    input:SetSize(126, 24)
    input:SetPoint("RIGHT", -72, 0)

    local color = CreateSwatch(row, colorKey)
    local widgets = MenuWidgets()
    if IsEmbeddedCard(row) and widgets and type(widgets.AttachContextColorShortcut) == "function" then
        widgets.AttachContextColorShortcut(row, {
            title = tostring(labelText),
            offsetX = -207,
            getTargets = function() return { ColorTarget(colorKey, tostring(labelText)) } end,
            historyLabel = ColorHistoryLabel(colorKey),
            historySource = "suite:skin-color",
        })
    end

    local ShowHexError = BindHexInput(input, help, description or colorKey, colorKey, labelText)

    -- The hex text is rewritten after a color change, once the field has no
    -- focus; typing is never overwritten. A color change by any path (the
    -- picker, a palette, undo) also clears an earlier hex format error.
    local swatchColor = {}
    local hexStale = true
    O.TrackAndRefresh(function()
        local tableColor = NS.Theme.GetColorTable(colorKey)
        local r, g, b, a = tableColor[1], tableColor[2], tableColor[3], tableColor[4]
        if ColorChanged(swatchColor, r, g, b, a) then
            color:SetColorTexture(r, g, b, a)
            hexStale = true
            ShowHexError(false)
        end
        if hexStale and not input:HasFocus() then
            input:SetText(FormatHex(tableColor))
            hexStale = false
        end
    end)
    return row
end
