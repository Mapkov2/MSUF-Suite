local _, P = ...
local K, Tr = P.PreviewCanvas, P.Tr
local function Jump(ctx, section)
    local ui = ctx.suiteWorkspace
    if ui then ui:Focus("suite_skin_" .. section) end
end
local function VisibleRefresh(frame, state)
    if not state or state.target ~= frame then return end
    local refresh = state.refresh
    state.refresh = function(value)
        if frame:IsVisible() then refresh(value) end
    end
    frame:HookScript("OnShow", function() state.refresh(state) end)
end
local function Box(skin, parent, x, y, w, h, role, section, ctx)
    local frame = K.Button(parent, x, y, w, h, function() Jump(ctx, section) end)
    local spec = { role = role, ownedArt = true }
    local state
    if role == "buttonPrimary" or role == "button" then
        state = skin.Surface.SkinOwnedButton(frame, spec, false)
    else state = skin.Surface.Attach(frame, spec) end
    VisibleRefresh(frame, state)
    return frame
end
local function Label(preview, frame, text, x, y, width, token)
    local label = frame:CreateFontString(nil, "OVERLAY", token == "title" and "GameFontNormal" or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    label:SetText(Tr(text))
    preview.labels[#preview.labels + 1] = { region = label, token = token or "text" }
    return label
end
local function Contents(preview, skin, ctx)
    local shell, width = preview.shell, preview.width
    local panel = Box(skin, shell, 12, -38, width - 24, 142, "panel", "material", ctx)
    local left = math.min(126, width * .3)
    local nav = Box(skin, panel, 8, -8, left, 126, "card", "shape", ctx)
    Label(preview, nav, "Character and equipment", 8, -10, left - 16, "accent")
    Label(preview, nav, "Bags and bank", 8, -58, left - 16)
    Label(preview, nav, "Group Finder and PvE", 8, -90, left - 16)
    local x, room = left + 18, width - left - 50
    local search = Box(skin, panel, x, -8, room, 24, "card", "material", ctx)
    Label(preview, search, "Search items", 8, -5, room - 16, "muted")
    local card = Box(skin, panel, x, -40, room, 45, "card", "material", ctx)
    Label(preview, card, "Equipment", 8, -6, room - 16, "title")
    Label(preview, card, "Panel and card layer", 8, -25, room - 16)
    local normal = Box(skin, panel, x, -97, math.max(50, room * .46), 26, "button", "shape", ctx)
    Label(preview, normal, "Fonts", 6, -6, math.max(38, room * .46 - 12))
    local primary = Box(skin, panel, x + room * .52, -97, math.max(50, room * .48), 26, "buttonPrimary", "basic", ctx)
    Label(preview, primary, "Choose a look", 6, -6, math.max(38, room * .48 - 12), "accent")
    preview.panel, preview.primary, preview.normal = panel, primary, normal
end
local function Refresh(preview, skin)
    if not preview.section:IsVisible() or P.Combat() then return end
    for _, row in ipairs(preview.labels) do
        local r, g, b = skin.Theme.GetColor(row.token)
        if row.r ~= r or row.g ~= g or row.b ~= b then
            row.r, row.g, row.b = r, g, b
            row.region:SetTextColor(r, g, b)
        end
    end
    if preview.look ~= skin.DB.theme.look then
        preview.look = skin.DB.theme.look
        local look = skin.LookPresets[preview.look]
        local text = Tr(look and look.label or "Custom") .. " · " .. Tr(look and look.description or "Your own colors, materials and shape.")
            .. "\n" .. Tr("Sample values. Click an element to open its settings.")
        P.SetTranslatedText(preview.note, text)
    end
    local ui = preview.ctx.suiteWorkspace
    local height = math.max(380, 336 + math.ceil(preview.note:GetStringHeight() or 28))
    if ui then P.MenuWorkspace.FitHeader(ui, height) else preview.section:SetHeight(height) end
end

function P.BuildSkinMenuPreview(ctx, b, skin)
    local section, toolbar = P.W.FixedPreviewSection(ctx, b, { title = Tr("Skin preview"), height = 380 })
    if not section then return end
    local width = math.max(240, math.min(560, (P.HM.GetSectionWidth(section) or b.width or 720) - 48))
    local hint = K.Text(toolbar, "Choose a look below; this sample follows your changes.", 125, 0, math.max(80, width - 125))
    hint:SetJustifyH("LEFT")
    hint:SetShown(width >= 420)
    local preview = { ctx = ctx, section = section, width = width, labels = {} }
    local shell = Box(skin, section, 20, -98, width, 218, "shell", "window_controls", ctx)
    preview.shell = shell
    local title = Label(preview, shell, "Window shell", 14, -10, width - 90, "title")
    K.Jump({ Focus = function(_, id) Jump(ctx, id) end }, title, shell, "fonts")
    local minimize = Box(skin, shell, width - 64, -6, 24, 24, "button", "window_controls", ctx)
    Label(preview, minimize, "−", 7, -4, 18)
    local close = Box(skin, shell, width - 34, -6, 24, 24, "button", "window_controls", ctx)
    Label(preview, close, "×", 7, -4, 18)
    Contents(preview, skin, ctx)
    Label(preview, shell, "Window position, size and minimize", 14, -193, width - 28, "muted")
    preview.note = K.Text(section, "", 20, -324, width)
    ctx.skinPreview = preview
    local function Paint() Refresh(preview, skin) end
    preview.Paint = Paint
    P.M.TrackRefresh(ctx, Paint)
    section:HookScript("OnShow", Paint)
    Paint()
    return section
end
