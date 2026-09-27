local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

-- Slider, text and search rows (see Widgets.lua).
local Widgets = Private.Widgets
local CanChange = Widgets.CanChange
local ColorChanged = Widgets.ColorChanged
local BeginWidgetChange = Widgets.BeginWidgetChange
local CommitWidgetChange = Widgets.CommitWidgetChange
local CreateInputBox = Widgets.CreateInputBox

------------------------------------------------------------------ slider
-- The slider with its track and thumb; Refresh paints their colors.
local function CreateSliderBar(row, minimum, maximum, step)
    local slider = CreateFrame("Slider", nil, row)
    slider:SetPoint("BOTTOMLEFT", 14, 10)
    slider:SetPoint("BOTTOMRIGHT", -14, 10)
    slider:SetHeight(14)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(3)

    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(16, 16)
    thumb:SetTexture(NS.path .. "Media\\Shapes\\continuous_r8_fill.png")
    slider:SetThumbTexture(thumb)
    return slider, track, thumb
end

-- The dragged value on the step grid: Shift moves in 5 steps, Ctrl in 10,
-- like the Suite controls in the MSUF menu.
local function SnapToStep(value, minimum, maximum, step)
    local multiplier = IsControlKeyDown() and 10 or IsShiftKeyDown() and 5 or 1
    local increment = step * multiplier
    value = minimum + math.floor((value - minimum) / increment + 0.5) * increment
    return math.max(minimum, math.min(maximum, value))
end

function O.CreateSlider(parent, labelText, minimum, maximum, step, getter, setter, width, formatter, options)
    -- One whole unit for integral ranges, one percent point for fractional
    -- ranges such as opacity and scale.
    step = step < 1 and 0.01 or 1
    local row = O.CreatePanel(parent, "card")
    row:SetSize(width or 520, 58)
    local label = O.CreateText(row, labelText, 12, "text")
    label:SetPoint("TOPLEFT", 12, -9)
    local valueText = O.CreateText(row, "", 11, "accent", "RIGHT")
    valueText:SetPoint("TOPRIGHT", -12, -9)
    local slider, track, thumb = CreateSliderBar(row, minimum, maximum, step)

    local internalChange = false
    local dragging = false
    -- The value this row last showed; nil after the user moved the thumb.
    local paintedValue
    local Refresh
    slider:SetScript("OnMouseDown", function()
        dragging = BeginWidgetChange(labelText, options) or false
    end)
    slider:SetScript("OnMouseUp", function()
        if dragging then CommitWidgetChange(labelText, options, true) end
        dragging = false
    end)
    slider:SetScript("OnValueChanged", function(_, value)
        if internalChange then return end
        paintedValue = nil
        -- A refused move puts the thumb and text back on the stored value.
        if not CanChange() then
            Refresh()
            return
        end
        value = SnapToStep(value, minimum, maximum, step)
        if value ~= slider:GetValue() then
            internalChange = true
            slider:SetValue(value)
            internalChange = false
        end
        local current = tonumber(getter())
        if current and math.abs(current - value) < 0.000001 then return end
        local began = not dragging and BeginWidgetChange(labelText, options)
        setter(value)
        if began then CommitWidgetChange(labelText, options, true) end
    end)

    local trackColor, thumbColor = {}, {}
    function Refresh()
        local value = getter()
        if value ~= paintedValue then
            paintedValue = value
            internalChange = true
            slider:SetValue(value)
            internalChange = false
            valueText:SetText(formatter and formatter(value) or tostring(value))
        end
        local r, g, b, a = NS.Theme.GetColor("borderSoft")
        if ColorChanged(trackColor, r, g, b, a) then track:SetColorTexture(r, g, b, a) end
        r, g, b, a = NS.Theme.GetColor("accent")
        if ColorChanged(thumbColor, r, g, b, a) then thumb:SetVertexColor(r, g, b, a) end
    end
    O.TrackAndRefresh(Refresh)
    row._mskinControl = slider
    return row
end

------------------------------------------------------------------ text and search
function O.CreateInput(parent, labelText, getter, setter, width, options)
    local row = O.CreatePanel(parent, "card")
    row:SetSize(width or 520, 58)
    local label = O.CreateText(row, labelText, 12, "text")
    label:SetPoint("TOPLEFT", 12, -9)

    local input = CreateInputBox(row, 8)
    input:SetPoint("BOTTOMLEFT", 12, 8)
    input:SetPoint("BOTTOMRIGHT", -12, 8)
    input:SetHeight(24)

    local function Current()
        return tostring(getter() or "")
    end
    local function Commit()
        local value = input:GetText() or ""
        if value ~= Current() then
            local began = BeginWidgetChange(labelText, options)
            if began == nil then
                -- Refused in combat: the field shows the stored value again.
                input:SetText(Current())
                return
            end
            setter(value)
            CommitWidgetChange(labelText, options, began)
        end
    end
    input:SetScript("OnEnterPressed", function(self)
        Commit()
        self:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", function(self)
        self:SetText(Current())
        self:ClearFocus()
    end)
    input:SetScript("OnEditFocusLost", Commit)

    O.TrackRefresh(function()
        if not input:HasFocus() then input:SetText(Current()) end
    end)
    input:SetText(Current())
    return row, input
end

function O.CreateSearchBox(parent, placeholderText, callback, width)
    local input = CreateInputBox(parent, 10)
    input:SetSize(width or 300, 28)

    local placeholder = O.CreateText(input, placeholderText or L["Search..."], 11, "dim")
    placeholder:SetPoint("LEFT", 10, 0)
    placeholder:SetPoint("RIGHT", -10, 0)

    local function RefreshSearch()
        local text = input:GetText() or ""
        placeholder:SetShown(text == "")
        if callback then callback(text, input) end
    end
    input:SetScript("OnTextChanged", RefreshSearch)
    input:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") else self:ClearFocus() end
        RefreshSearch()
    end)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    input.RefreshSearch = RefreshSearch
    return input
end
