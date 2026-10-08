local _, Suite = ...

-- Only the installer's chrome lives here. Profile samples and palette
-- swatches remain owned by InstallerProfiles and describe the staged install.
local A = {}
Suite.InstallerAppearance = A
local Bridge = Suite.HostBridge
local panels, panelOrder, labels = {}, {}, {}
local window, progressPage, events, repaintPending
local unpack = unpack
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 } }
local NEUTRAL, TEXT = { 0.08, 0.08, 0.08, 0.98 }, { 1, 1, 1, 1 }
local TEMPLATE_ROLES = { GameFontNormalLarge = "hero", GameFontNormal = "card",
    GameFontNormalSmall = "caption", GameFontHighlightSmall = "supporting" }
local FALLBACK_FIELDS = { bg = "bgColor", popup = "bgColor", panel2 = "headerColor",
    pillBase = "headerColor", pillHover = "trackColor", pillActive = "headerColor",
    border = "borderColor", borderSoft = "borderColor", pillEdgeActive = "barColor",
    accent = "barColor", title = "titleColor", text = "leftColor", muted = "rightColor" }
local fallback = {}
-- Older hosts can lack both shared UI and Menu2. Reuse the core catalog's
-- authored palette rather than maintain another blue/dark/gold palette.
local presets = Suite.DamageMeterLookPresets
local preset = presets and presets[Suite.Client.isForever and 3 or 2]
if preset then
    for token, field in pairs(FALLBACK_FIELDS) do
        local r, g, b = Suite.RGB(preset[field])
        fallback[token] = { r, g, b, 1 }
    end
end

local function Color(token, alternate)
    local color = Bridge.MenuColor(token, alternate)
    return color or fallback[token] or fallback[alternate]
        or ((token == "text" or token == "title" or token == "muted") and TEXT or NEUTRAL)
end

local function PaintPanel(record)
    local selected = record.selected or record.primary
    if record.marker then
        record.marker:SetColorTexture(unpack(Color("accent")))
        record.marker:SetShown(selected == true)
    end
    if record.nativeButton then
        record.frame:SetActive(selected)
        return
    end
    local fill = record.shell and Color("popup", "bg")
        or Color(selected and "pillActive" or record.hovered and "pillHover"
            or record.button and "pillBase" or "panel2", "card")
    local edge = selected and (record.accent or Color("pillEdgeActive", "accent"))
        or Color(record.shell and "border" or "borderSoft", "border")
    if record.button or not Bridge.MenuMaterial(record.frame, record.shell and "popup" or "card") then
        record.frame:SetBackdrop(BACKDROP)
        record.frame:SetBackdropColor(unpack(fill))
        record.frame:SetBackdropBorderColor(unpack(edge))
    end
end

function A.Style(panel, selected, primary, accent)
    local record = panels[panel]
    record.selected, record.primary, record.accent = selected == true, primary == true, accent
    PaintPanel(record)
end

function A.Panel(parent, x, y, width, height, button)
    local panel = button and Bridge.MenuButton(parent, width, height) or nil
    local nativeButton = panel ~= nil
    panel = panel or CreateFrame(button and "Button" or "Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
    local record = { frame = panel, button = button, nativeButton = nativeButton }
    panels[panel], panelOrder[#panelOrder + 1] = record, record
    if button then
        -- Ordinary skin buttons share their idle and active material. Keep
        -- the installer's staged choice visible independently of that skin.
        local marker = panel:CreateTexture(nil, "ARTWORK")
        marker:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
        marker:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 4, 4)
        marker:SetWidth(2)
        record.marker, panel.suiteSelectionMarker = marker, marker
        local enter, leave = panel:GetScript("OnEnter"), panel:GetScript("OnLeave")
        -- Call the original UI painter from persistent hooks: later profile
        -- and module handlers replace scripts without losing hover cleanup.
        panel:SetScript("OnEnter", nil)
        panel:SetScript("OnLeave", nil)
        panel:HookScript("OnEnter", function(self)
            record.hovered = true
            if enter then enter(self) end
            PaintPanel(record)
        end)
        panel:HookScript("OnLeave", function(self)
            record.hovered = false
            if leave then leave(self) end
            PaintPanel(record)
        end)
        if nativeButton then Bridge.MenuButtonLabel(panel):Hide() end
    end
    PaintPanel(record)
    return panel
end

local function PaintLabel(record)
    local label = record.label
    -- Palette buttons retain their compact two-line captions.
    local role = type(record.parent.look) == "string" and "supporting" or record.role
    local title = role == "hero" or role == "heading" or role == "section" or role == "card"
    local color = Color(title and "title" or (role == "supporting" or role == "caption") and "muted" or "text", "text")
    if not Bridge.MenuFont(label, color, role) then
        label:SetTextColor(unpack(color))
        label:SetShadowColor(0, 0, 0, 0)
        label:SetShadowOffset(0, 0)
    end
end

function A.Label(parent, template, x, y, width, height, role)
    local label = parent:CreateFontString(nil, "OVERLAY", template)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetSize(width, height)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    local record = { label = label, parent = parent, role = role or TEMPLATE_ROLES[template] or "body" }
    labels[#labels + 1] = record
    PaintLabel(record)
    return label
end

function A.Button(parent, x, y, width, caption, callback, primary)
    local button = A.Panel(parent, x, y, width, 30, true)
    A.Style(button, false, primary)
    if panels[button].nativeButton then
        button.caption = Bridge.MenuButtonLabel(button)
        labels[#labels + 1] = { label = button.caption, parent = button, role = "control" }
        button.caption:SetSize(width, 30)
        button.caption:Show()
    else
        button.caption = A.Label(button, "GameFontNormal", 0, 0, width, 30, "control")
    end
    button.caption:ClearAllPoints()
    button.caption:SetPoint("CENTER")
    button.caption:SetJustifyH("CENTER")
    button.caption:SetJustifyV("MIDDLE")
    button.caption:SetText(caption)
    button:SetScript("OnClick", callback)
    return button
end

function A.Progress(frame, page)
    progressPage = page
    local accent, idle = Color("accent"), Color("borderSoft", "border")
    for index, segment in ipairs(frame.progress) do
        segment:SetColorTexture(unpack(index <= math.min(page, 5) and accent or idle))
    end
end

function A.Refresh()
    if not window then return end
    for _, record in ipairs(panelOrder) do PaintPanel(record) end
    for _, record in ipairs(labels) do PaintLabel(record) end
    if progressPage then A.Progress(window, progressPage) end
end

local function FinishRepaint()
    repaintPending = nil
    if window and window:IsShown() then Suite.Dispatch(A.Refresh) end
end
local function AppearanceChanged()
    if repaintPending or not window or not window:IsShown() then return end
    -- Core and optional skin event listeners may connect in either order.
    -- Repaint once after their palette writes; this is an event-owned job.
    repaintPending = true
    C_Timer.After(0, FinishRepaint)
end

function A.Window(frame)
    window = frame
    local record = { frame = frame, shell = true }
    panels[frame], panelOrder[#panelOrder + 1] = record, record
    PaintPanel(record)
    frame:HookScript("OnShow", A.Refresh)
    Bridge.WatchMenuAppearance(A, AppearanceChanged)
    events = CreateFrame("Frame")
    events:RegisterEvent("ADDON_LOADED")
    events:SetScript("OnEvent", function(_, _, addon)
        if addon == "MidnightSimpleUnitFrames_Options" or addon == "MSUF_Suite_Skin" or addon == "MapkoSkin" then
            Bridge.WatchMenuAppearance(A, AppearanceChanged)
            AppearanceChanged()
        end
    end)
end
