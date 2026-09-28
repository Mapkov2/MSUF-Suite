local _, P = ...
local ID = "nameplates"
local T, Tr = P.T, P.Tr
local Size = {}
P.NameplatesSize = Size

local function Clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function Round(value) return math.floor(value + 0.5) end

-- Size controls describe real runtime settings. Native cast geometry, badges,
-- raid icons and power bars have no independent safe width/height override.
function Size.Keys(handle)
    local id = handle and handle._key
    if not id or P.Get(ID, "look") == 2 then return end
    if id == "enemy.Health" or id == "friendly.Health" then
        local prefix = id:match("^(%a+)%.")
        return prefix .. "HealthWidthDelta", prefix .. "HealthHeightDelta", "W", "H"
    end
    if id == "enemy.target" or id == "friendly.target" then return "enemyTargetMarkerSize", nil, "Size" end
    if id:match("^[a-z]+%.elite$") or id:match("^[a-z]+%.quest$") then
        local prefix, kind = id:match("^(%a+)%.(%a+)$")
        return prefix .. (kind == "elite" and "Elite" or "Quest") .. "MarkerSize", nil, "Size"
    end
    if id:match("%.Auras$") or id:match("%.Buffs$") or id:match("%.ControlAura$") then
        return "auraScalePercent", nil, "Size %"
    end
    local prefix, element = id:match("^(%a+)%.(%a+)$")
    if not prefix then return end
    if element == "Name" and P.Get(ID, prefix .. "TextEnabled") then
        return prefix .. "NameSize", nil, "Font"
    end
    if element == "Level" and P.Get(ID, prefix .. "LevelEnabled")
        and not (P.Suite.Client.isForever and P.Get(ID, "levelAppearance") == 2)
        and not P.Suite.NameplateStyle.ClassicNativePlate(P.Get(ID, "nativeStyle")) then
        return prefix .. "LevelSize", nil, "Font"
    end
    if element == "HealthText" and prefix == "enemy" and P.Get(ID, "enemyTextEnabled") then
        return "enemyHealthTextSize", nil, "Font"
    end
    if (element == "CastText" or element == "CastTime" or element == "CastTarget")
        and P.Get(ID, prefix .. "CastTextEnabled") then
        return prefix .. "CastSize", nil, "Font"
    end
end

function Size.Value(handle, key)
    local value = P.Get(ID, key)
    if key:match("HealthWidthDelta$") then return (handle._npNativeWidth or 0) + value end
    if key:match("HealthHeightDelta$") then return (handle._npNativeHeight or 0) + value end
    if key == "auraScalePercent" and P.Get(ID, "auraScaleMode") ~= 2 then
        local api = _G.C_CVar
        local native = api and type(api.GetCVar) == "function" and api.GetCVar("nameplateAuraScale")
        if P.Suite.Public(native) then
            local scale = tonumber(native)
            if scale and scale > 0 then return Round(scale * 100) end
        end
    end
    return value
end

function Size.Write(ui, handle, key, value)
    if P.Combat() or not handle or not handle:IsShown() then return false end
    local rule = P.catalog[ID].rules[key]
    if not rule or type(value) ~= "number" or value ~= value then return false end
    if key:match("HealthWidthDelta$") then value = value - (handle._npNativeWidth or 0)
    elseif key:match("HealthHeightDelta$") then value = value - (handle._npNativeHeight or 0) end
    local step = rule.step or 1
    local rounded = Clamp(math.floor(value / step + 0.5) * step, rule.min, rule.max)
    local values = { [key] = rounded }
    if key == "auraScalePercent" then values.auraScaleMode = 2 end
    local ok = P.SetMany(ID, values)
    ui:Paint()
    return ok ~= false
end

function Size.ResetValues(handle, values, rules)
    local first, second = Size.Keys(handle)
    if first then values[first] = rules[first].default end
    if second then values[second] = rules[second].default end
    if first == "auraScalePercent" then values.auraScaleMode = rules.auraScaleMode.default end
end

local function Field(ui, row, body, index)
    local group = CreateFrame("Frame", nil, row)
    group:SetSize(92, 22)
    if index == 1 then group:SetPoint("LEFT", row, "LEFT", 0, 0)
    else group:SetPoint("LEFT", ui.sizeFields[1].frame, "RIGHT", 4, 0) end
    local caption = T.Font(group, "GameFontDisableSmall", "", T.colors.muted)
    caption:SetPoint("LEFT", group, "LEFT", 0, 0)
    caption:SetWidth(14)
    local minus = T.Button(group, "-", 16, 18)
    minus:SetPoint("LEFT", caption, "RIGHT", 2, 0)
    local edit = CreateFrame("EditBox", nil, group, "InputBoxTemplate")
    edit:SetSize(38, 18)
    edit:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("RIGHT")
    edit:SetMaxLetters(6)
    if T.SkinEditBox then T.SkinEditBox(edit) end
    local plus = T.Button(group, "+", 16, 18)
    plus:SetPoint("LEFT", edit, "RIGHT", 2, 0)
    local field = { frame = group, caption = caption, edit = edit, minus = minus, plus = plus }
    local function Key()
        local first, second = Size.Keys(body._selectedHandle)
        return index == 1 and first or second
    end
    local function Update(value)
        local key = Key()
        return key and Size.Write(ui, body._selectedHandle, key, value) or false
    end
    local function Step(delta)
        local key = Key()
        local rule = key and P.catalog[ID].rules[key]
        if rule then Update(Size.Value(body._selectedHandle, key) + delta * rule.step) end
    end
    minus:SetScript("OnClick", function() Step(-1) end)
    plus:SetScript("OnClick", function() Step(1) end)
    edit:SetScript("OnEditFocusGained", function(self) self._npSizeEditing = true end)
    edit:SetScript("OnEscapePressed", function(self)
        self._npSizeEditing = nil
        self:ClearFocus()
        ui:RefreshSizeSelection()
    end)
    edit:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        self._npSizeEditing = nil
        if value then Update(value) end
        self:ClearFocus()
        ui:RefreshSizeSelection()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if not self._npSizeEditing then return end
        self._npSizeEditing = nil
        local value = tonumber(self:GetText())
        if value then Update(value) else ui:RefreshSizeSelection() end
    end)
    return field
end

function Size.Build(ui, bar, body)
    local row = CreateFrame("Frame", nil, bar)
    -- Use the rendered end of Y, not the axis container's nominal width.
    row:SetPoint("LEFT", bar.axisY.plusButton, "RIGHT", 6, 0)
    row:SetPoint("RIGHT", bar.resetButton, "LEFT", -6, 0)
    row:SetHeight(22)
    ui.sizeFields = {}
    ui.sizeFields[1] = Field(ui, row, body, 1)
    ui.sizeFields[2] = Field(ui, row, body, 2)
    local fields = ui.sizeFields
    ui.sizeFields, ui.sizeRow = fields, row
    local unsupported = T.Font(row, "GameFontDisableSmall",
        Tr("Size: Blizzard"), T.colors.muted)
    unsupported:SetPoint("LEFT", row, "LEFT", 0, 0)
    unsupported:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    unsupported:SetJustifyH("LEFT")
    if unsupported.SetMaxLines then unsupported:SetMaxLines(1) end
    local function Layout()
        local width = bar:GetWidth()
        if not width or width <= 0 then width = ui.layoutWidth end
        local wide = width >= 780
        bar.label:SetWidth(wide and 132 or 108)
        local showOpen = width >= (wide and 780 or 756)
        bar.openButton:SetShown(showOpen)
        bar.resetButton:ClearAllPoints()
        if showOpen then bar.resetButton:SetPoint("RIGHT", bar.openButton, "LEFT", -6, 0)
        else bar.resetButton:SetPoint("RIGHT", bar, "RIGHT", -8, 0) end
    end
    bar:SetScript("OnSizeChanged", Layout)
    Layout()
    function ui:RefreshSizeSelection()
        local handle = body._selectedHandle
        local first, second, labelX, labelY = Size.Keys(handle)
        row:SetShown(handle ~= nil)
        unsupported:SetShown(handle ~= nil and first == nil)
        for index, key in ipairs({ first or false, second or false }) do
            local field = fields[index]
            local shown = key ~= false
            field.frame:SetShown(shown)
            if shown then
                field.caption:SetWidth(second and 14 or 38)
                field.frame:SetWidth(second and 92 or 116)
                field.caption:SetText(index == 1 and labelX or labelY)
                if not field.edit._npSizeEditing then
                    field.edit:SetText(tostring(Round(Size.Value(handle, key))))
                end
                local enabled = not P.Combat()
                field.edit:SetEnabled(enabled)
                field.minus:SetEnabled(enabled)
                field.plus:SetEnabled(enabled)
            end
        end
    end
    ui:RefreshSizeSelection()
end
