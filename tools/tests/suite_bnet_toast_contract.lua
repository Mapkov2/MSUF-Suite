-- The Battle.net toast module (MSUF_Suite_QualityOfLife/BattleNetToast.lua):
-- MSUF Edit Mode moves Blizzard's toast, the module styles it, and nothing of
-- it runs unless Blizzard itself places the toast. The client model follows
-- Gethe wow-ui-source live 297d7aaa / forever 4cd0ab75 (identical there):
-- BNet.xml and SocialToast.xml (frame, lines, backdrop pieces, strata LOW),
-- AlertFrameAutoAnchoredMixin:AdjustAnchors (ClearAllPoints, then SetPoint to
-- the chat alert below the toast, only while it shows) and
-- AlertContainerMixin:GetPointsForJustification. Blizzard's objects refuse
-- every field write: the module may only call their widget methods.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

------------------------------------------------------------------ widgets
-- Widget state lives beside the objects, so a Blizzard object can refuse
-- field writes while its methods still work.
local state = setmetatable({}, { __mode = "k" })
local Widget = {}
local function New(kind, fields, blizzard)
    local object = fields or {}
    state[object] = { kind = kind, shown = true, alpha = 1, points = {}, scale = 1, strata = "MEDIUM",
        regions = {}, calls = {} }
    local meta = { __index = Widget }
    if blizzard then
        meta.__newindex = function(_, key) error("field written onto a Blizzard object: " .. tostring(key), 2) end
    end
    return setmetatable(object, meta)
end
local function Count(self, name)
    local calls = state[self].calls
    calls[name] = (calls[name] or 0) + 1
end
function Widget:SetPoint(...)
    Count(self, "SetPoint")
    local points = state[self].points
    points[#points + 1] = { ... }
end
function Widget:ClearAllPoints()
    Count(self, "ClearAllPoints")
    state[self].points = {}
end
function Widget:SetAllPoints(target) state[self].points = { { "ALL", target } } end
function Widget:GetPoint(index)
    local point = state[self].points[index or 1]
    if point then return unpack(point, 1, 5) end
end
function Widget:GetNumPoints() return #state[self].points end
function Widget:SetSize(width, height) state[self].width, state[self].height = width, height end
function Widget:SetWidth(width) state[self].width = width end
function Widget:SetHeight(height) state[self].height = height end
function Widget:GetWidth() return state[self].width end
function Widget:GetHeight() return state[self].height end
function Widget:GetRect() return unpack(state[self].rect) end
function Widget:SetScale(value) Count(self, "SetScale"); state[self].scale = value end
function Widget:GetScale() return state[self].scale end
function Widget:GetEffectiveScale() return state[self].effective or state[self].scale end
-- A strata change reaches every child (the client's rule for children
-- without a fixed strata).
function Widget:SetFrameStrata(value)
    Count(self, "SetFrameStrata")
    state[self].strata = value
    for _, child in ipairs(state[self].children or {}) do child:SetFrameStrata(value) end
end
function Widget:GetFrameStrata() return state[self].strata end
function Widget:EnableMouse(value) state[self].mouse = value end
function Widget:Show() state[self].shown = true end
function Widget:Hide() state[self].shown = false end
function Widget:SetShown(value) state[self].shown = value == true end
function Widget:IsShown() return state[self].shown end
function Widget:SetAlpha(value) Count(self, "SetAlpha"); state[self].alpha = value end
function Widget:GetAlpha() return state[self].alpha end
function Widget:SetColorTexture(...) state[self].color = { ... } end
function Widget:SetTexture(value) state[self].texture = value end
function Widget:SetTexCoord(...) state[self].coords = { ... } end
function Widget:SetBackdrop(info) state[self].backdrop = info end
function Widget:IsForbidden() return false end
function Widget:SetJustifyH() end
function Widget:SetWordWrap() end
function Widget:CreateTexture(_, layer, _, sublevel)
    local texture = New("Texture")
    state[texture].parent, state[texture].layer, state[texture].sublevel = self, layer, sublevel or 0
    table.insert(state[self].regions, texture)
    return texture
end
function Widget:CreateFontString(_, layer)
    local line = New("FontString")
    state[line].parent, state[line].layer = self, layer
    state[line].shadowColor, state[line].shadowOffset = { 0, 0, 0, 0 }, { 0, 0 }
    table.insert(state[self].regions, line)
    return line
end
function Widget:SetFont(path, size, flags)
    Count(self, "SetFont")
    assert(type(path) == "string" and path ~= "" and type(size) == "number", "invalid font")
    state[self].font = { path, size, flags }
    return true
end
function Widget:GetFont() return unpack(state[self].font) end
function Widget:SetFontObject(object) state[self].font = { object.path, object.size, object.flags } end
function Widget:SetText(value)
    assert(state[self].font, "FontString:SetText(): Font not set")
    state[self].text = value
end
function Widget:SetTextColor(...) state[self].textColor = { ... } end
function Widget:SetShadowColor(...) state[self].shadowColor = { ... } end
function Widget:GetShadowColor() return unpack(state[self].shadowColor) end
function Widget:SetShadowOffset(...) state[self].shadowOffset = { ... } end
function Widget:GetShadowOffset() return unpack(state[self].shadowOffset) end

local function PointOf(object, index) return state[object].points[index or 1] end
local function Calls(object, name) return state[object].calls[name] or 0 end
local function ResetCalls(object) state[object].calls = {} end
local function RegionsOn(frame) return state[frame].regions end

------------------------------------------------------------------ client
UIParent = New("Frame")
state[UIParent].width, state[UIParent].height = 1920, 1080
UnitName = function(unit) assert(unit == "player") return "Mapko" end
BN_TOAST_ONLINE = "has come online."
FriendsFont_Normal = { path = "Fonts\\FRIZQT__.TTF", size = 12, flags = "" }
GameFontHighlightSmall = { path = "Fonts\\FRIZQT__.TTF", size = 10, flags = "" }
BACKDROP_TOAST_12_12 = { bgFile = "Interface\\FriendsFrame\\UI-Toast-Background" }

local hookCalls = 0
hooksecurefunc = function(owner, key, callback)
    assert(type(owner) == "table" and key == "SetPoint", "unexpected hook " .. tostring(key))
    local original = owner[key]
    -- The client stores its secure wrapper under the method's name.
    rawset(owner, key, function(...)
        original(...)
        hookCalls = hookCalls + 1
        callback(...)
    end)
end

-- BNet.xml: the lines in BORDER 0 with FriendsFont_Normal, the backdrop
-- pieces of BackdropTemplate, strata LOW, anchored CENTER 0 50 at load.
local PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }
local LINES = { "TopLine", "MiddleLine", "BottomLine", "DoubleLine" }
local function BlizzardToast()
    local fields = {}
    for _, key in ipairs(PIECES) do fields[key] = New("Texture", nil, true) end
    for _, key in ipairs(LINES) do
        local line = New("FontString", nil, true)
        state[line].font = { "Fonts\\FRIZQT__.TTF", 12, "" }
        state[line].shadowColor, state[line].shadowOffset = { 0, 0, 0, 1 }, { 1, -1 }
        fields[key] = line
    end
    fields.TooltipFrame = New("Frame", nil, true)
    state[fields.TooltipFrame].strata = "TOOLTIP"
    local toast = New("Frame", fields, true)
    state[toast].children = { fields.TooltipFrame }
    state[fields.Center].alpha = .8
    state[toast].strata, state[toast].shown = "LOW", false
    state[toast].points = { { "CENTER", UIParent, "CENTER", 0, 50 } }
    return toast
end

ChatAlertFrame = New("Frame", { justification = "LEFT" }, true)
QuickJoinToastButton = New("Frame", nil, true)
local SIDES = { LEFT = "BOTTOMLEFT", CENTER = "BOTTOM", RIGHT = "BOTTOMRIGHT" }
local ABOVE = { BOTTOMLEFT = "TOPLEFT", BOTTOM = "TOP", BOTTOMRIGHT = "TOPRIGHT" }
-- One layout pass of ChatAlertFrame for the toast's subsystem.
local function LayoutPass()
    local toast = BNToastFrame
    if not toast:IsShown() then return end
    local point = SIDES[ChatAlertFrame.justification] or "BOTTOM"
    local relative, relativePoint = ChatAlertFrame, point
    if QuickJoinToastButton:IsShown() then relative, relativePoint = QuickJoinToastButton, ABOVE[point] end
    toast:ClearAllPoints()
    toast:SetPoint(point, relative, relativePoint, 0, 0)
end
-- BNToastMixin:ShowToast through AlertFrame_ShowNewAlert: Show, then the
-- postcall OnShow lays the container out.
local function ShowToast()
    BNToastFrame:Show()
    LayoutPass()
end
local function HideToast()
    BNToastFrame:Hide()
    LayoutPass()
end

------------------------------------------------------------------ suite
local function Hex(hex) return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
    tonumber(hex:sub(5, 6), 16) / 255 end
local PALETTES = {
    { background = "0a1220", border = "41627a", accent = "57c7df", text = "f4f7fb", muted = "aab5c2" },
    { background = "151719", border = "575b58", accent = "b9ab86", text = "e9e9e4", muted = "b9bdb9" },
    { background = "14181b", border = "9f8960", accent = "d8b66a", text = "f4f3eb", muted = "d4dce2" },
    { background = "101010", border = "333333", accent = "e6ecf2", text = "f5f5f5", muted = "bfc4c9" },
    { background = "101010", border = "c41e3a", accent = "c41e3a", text = "f5f5f5", muted = "bfc4c9" },
}
local installed, movers, created = {}, {}, {}
local S = { editMode = false, RGB = Hex }
S.Text = function(text) return text end
S.Finite = function(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
S.CreateFrame = function(kind, _, parent, template)
    local frame = New(kind)
    state[frame].parent, state[frame].template = parent, template
    created[#created + 1] = frame
    return frame
end
S.CreateTexture = function(parent, ...) return parent:CreateTexture(...) end
S.CreateFontString = function(parent, ...) return parent:CreateFontString(...) end
S.PlaceEdges = function(set, owner, width, r, g, b, a)
    for i = 1, 4 do
        set[i]:SetColorTexture(r, g, b, a)
        set[i]:SetShown(true)
        state[set[i]].edgeOwner, state[set[i]].edgeWidth = owner, width
    end
end
S.ResolveFont = function(name) return name ~= "" and "Fonts\\" .. name or nil end
S.GlobalFontPath = function() return "Fonts\\MSUF.ttf" end
S.SetFont = function(line, path, size, flags) return line:SetFont(path, size, flags) end
S.FontFlags = function(outline, rendering)
    if rendering == 3 then return outline == "" and "SLUG" or "OUTLINE,SLUG" end
    if rendering == 2 then return outline == "" and "MONOCHROME" or outline .. ",MONOCHROME" end
    return outline
end
S.Install = function(id, module) installed[id] = module end
S.RegisterOwnedMover = function(id, element, spec) movers[id .. "." .. element] = spec return true end
Support.QoLStyleFixture(root, S, PALETTES)
local NS = { AnchorPoints = Support.AnchorPoints(root), FontRendering = { SMOOTH = 1, SHARP = 2, SLUG = 3 },
    Safety = { IsForbidden = function(frame) return frame:IsForbidden() end } }

------------------------------------------------------------------ catalog
local catalog = { Client = { isForever = false }, Text = function(text) return text end }
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", catalog)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLife.lua"))("MSUF_Suite", catalog)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLifeDetails.lua"))("MSUF_Suite", catalog)
local spec = assert(catalog.SuiteCatalog.bnetToast, "the Battle.net toast module is not in the catalog")
local rules = spec.rules
Check(spec.addon == "MSUF_Suite_QualityOfLife" and spec.optIn and spec.rules.enabled.default == false
    and spec.editElement == "toast", "the module is not an opt-in QoL module with its Edit Mode element")
Check(rules.look.default == 1 and #rules.look.choices == 6 and rules.look.choices[1] == "Blizzard",
    "the toast does not start with Blizzard's look")
Check(rules.moved.default == false and rules.moved.hidden and rules.point.hidden and rules.x.hidden
    and rules.y.hidden and rules.point.default == 7, "the position keys are not Edit Mode's hidden keys")
Check(rules.scale.default == 100 and rules.scale.min == 50 and rules.scale.max == 200,
    "the toast scale range changed")
Check(rules.opacity.requiresChoice.key == "look" and not rules.opacity.requiresChoice.values[1]
    and rules.opacity.requiresChoice.values[6] and rules.accent.requiresChoice == rules.opacity.requiresChoice,
    "the panel settings stay editable for Blizzard's look")
for _, key in ipairs({ "font", "fontSize", "fontOutline", "fontRendering", "fontShadow" }) do
    Check(rules[key].enableKey == "suiteFont", key .. " is editable without the Suite font")
end
local global = spec.look.global
Check(global[1] == 2 and global[2] == 3 and global[3] == 4 and global[5] == 5 and global[6] == 6
    and global[4] == nil, "the Suite-wide look does not pick the matching toast palette")
local function Defaults()
    local config = {}
    for key, rule in pairs(rules) do config[key] = rule.default end
    return config
end

------------------------------------------------------------------ module
local events = {}
local context = {
    Event = function(_, event, callback) events[event] = callback end,
    RemoveEvent = function(_, event) events[event] = nil end,
}
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/BattleNetToast.lua"))("MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
local M = assert(installed.bnetToast, "the module did not install")
local function Start(config)
    M.config, M.context, M.active = config, context, true
    M:Enable()
    M:RegisterMovers()
end
local function Set(key, value)
    M.config[key] = value
    M:Refresh()
end
local function SetMany(values)
    for key, value in pairs(values) do M.config[key] = value end
    M:Refresh()
end
local function Stop()
    M.active = false
    M:Disable()
end

-- Blizzard_BNet loads after the Suite: the module waits for it, and only for it.
BNToastFrame = nil
Start(Defaults())
Check(events.ADDON_LOADED ~= nil, "the module did not wait for Blizzard_BNet")
BNToastFrame = BlizzardToast()
local toast = BNToastFrame
events.ADDON_LOADED(M, "ADDON_LOADED", "Blizzard_Collections")
Check(events.ADDON_LOADED ~= nil and Calls(toast, "SetScale") == 0, "another addon's load ended the wait")
events.ADDON_LOADED(M, "ADDON_LOADED", "Blizzard_BNet")
Check(events.ADDON_LOADED == nil and next(events) == nil and Calls(toast, "SetScale") == 1,
    "the late toast was not set up, or an event stayed registered")

------------------------------------------------------------------ unmoved
-- Until Edit Mode moves it, Blizzard places the toast: no hook, no regions,
-- no look or font change, and no call into the module while it shows.
Check(rawget(toast, "SetPoint") == nil and hookCalls == 0, "a hook was installed on a toast that never moved")
Check(#RegionsOn(toast) == 0 and state[toast.Center].alpha == .8 and Calls(toast.TopLine, "SetFont") == 0,
    "Blizzard's look was changed with the Blizzard style")
Check(state[toast].scale == 1 and state[toast].strata == "LOW" and Calls(toast, "SetFrameStrata") == 0
    and state[toast.TooltipFrame].strata == "TOOLTIP", "the toast's own scale or layer changed")
ShowToast()
local point = PointOf(toast)
Check(point[1] == "BOTTOMLEFT" and point[2] == QuickJoinToastButton and point[3] == "TOPLEFT" and hookCalls == 0,
    "Blizzard did not keep its own spot for an unmoved toast")
HideToast()

-- The Edit Mode element: the host stands at Blizzard's spot, and a drag starts there.
local mover = assert(movers["bnetToast.toast"], "the toast has no MSUF Edit Mode element")
local host = mover.getFrame()
Check(host and state[host].parent == UIParent and state[host].template == "BackdropTemplate"
    and state[host].width == 250 and state[host].height == 63 and not host:IsShown(),
    "the toast's Edit Mode frame is not a hidden toast-sized Suite frame")
Check(mover.xKey == "x" and mover.yKey == "y" and mover.pointKey == "point" and mover.point() == "BOTTOMLEFT"
    and mover.moveValues.moved == true and mover.resetKeys[1] == "moved" and mover.sizeKeys[1] == "scale",
    "the Edit Mode element does not move, reset and size the toast")
point = PointOf(host)
Check(point[1] == "BOTTOMLEFT" and point[2] == QuickJoinToastButton and point[3] == "TOPLEFT",
    "the Edit Mode frame does not stand at Blizzard's spot")
-- The scale reaches the toast at Blizzard's spot too, and the Edit Mode
-- frame keeps the toast's size.
Set("scale", 150)
Check(state[toast].scale == 1.5 and state[host].scale == 1.5 and PointOf(toast)[2] == QuickJoinToastButton,
    "the scale of an unmoved toast missed the toast or its Edit Mode frame")
Set("scale", 100)
state[host].rect = { 35.04, 280.36, 250, 63 }
local origin = { x = 0, y = 0 }
mover.capture(origin)
Check(origin.x == 35 and origin.y == 280.4, "a first drag does not start at Blizzard's spot")
M.config.point = 3
state[host].scale, state[host].rect = 2, { 20, 140, 250, 63 }
origin = { x = 0, y = 0 }
mover.capture(origin)
Check(origin.x == -690 and origin.y == -337, "a scaled drag start is not in the toast's own scale")
M.config.point = 7
state[host].scale = 1

------------------------------------------------------------------ moved
-- The commit of a drag: the toast follows the host, also through Blizzard's
-- later layout passes, at one bounded hook call per pass.
SetMany({ moved = true, x = 400, y = -200, point = 5 })
point = PointOf(host)
Check(point[1] == "CENTER" and point[2] == UIParent and point[4] == 400 and point[5] == -200,
    "the host is not at the saved position")
Check(rawget(toast, "SetPoint") ~= nil, "the toast was moved without the placement hook")
point = PointOf(toast)
Check(point[1] == "CENTER" and point[2] == host and point[3] == "CENTER", "the moved toast is not on its host")
origin = { x = 7, y = 9 }
mover.capture(origin)
Check(origin.x == 7 and origin.y == 9, "a drag of a moved toast did not start at its saved position")
local function Pass(show)
    hookCalls = 0
    ResetCalls(toast)
    if show then ShowToast() else LayoutPass() end
    return hookCalls, Calls(toast, "ClearAllPoints"), Calls(toast, "SetPoint")
end
local hooks, clears, sets = Pass(true)
point = PointOf(toast)
Check(#state[toast].points == 1 and point[2] == host and point[1] == "CENTER",
    "Blizzard's layout pass took the moved toast back")
Check(hooks == 2 and clears == 2 and sets == 2,
    ("a layout pass cost more than Blizzard's and one module placement: %d hooks, %d clears, %d points")
        :format(hooks, clears, sets))
InCombatLockdown = function() return true end
hooks, clears, sets = Pass(false)
Check(PointOf(toast)[2] == host and hooks == 2 and clears == 2 and sets == 2,
    "the toast was not held in place during combat at the same cost")
HideToast()
hooks = Pass(false)
Check(hooks == 0, "a layout pass with the toast hidden called the module")
InCombatLockdown = function() return false end
-- A changed screen anchor moves both.
Set("point", 9)
Check(PointOf(toast)[1] == "BOTTOMRIGHT" and PointOf(toast)[3] == "BOTTOMRIGHT" and PointOf(host)[1] == "BOTTOMRIGHT",
    "the toast did not take the new screen anchor")

------------------------------------------------------------------ look
local function TexturesOn(frame)
    local list = {}
    for _, region in ipairs(RegionsOn(frame)) do
        if state[region].kind == "Texture" then list[#list + 1] = region end
    end
    return list
end
Set("look", 3)
local textures = TexturesOn(toast)
Check(#textures == 6, "the Suite panel is not one fill, four edges and a stripe")
-- BNet.xml draws the toast's lines and icon in BORDER 0.
local fill, stripe, edges = nil, nil, {}
for _, texture in ipairs(textures) do
    local layer, sublevel = state[texture].layer, state[texture].sublevel
    Check(layer == "BACKGROUND" or (layer == "BORDER" and sublevel < 0), "a panel texture covers the toast's text")
    if layer == "BACKGROUND" then fill = texture
    elseif sublevel == -7 then stripe = texture
    else edges[#edges + 1] = texture end
end
Check(fill and stripe and #edges == 4, "the Suite panel is not one fill, four edges and a stripe")
for i = 1, 4 do
    Check(state[edges[i]].edgeOwner == toast and state[edges[i]].shown, "a panel edge is missing")
end
local r, g, b = Hex(PALETTES[2].background)
local color = state[fill].color
Check(math.abs(color[1] - r) < 1e-6 and math.abs(color[2] - g) < 1e-6 and math.abs(color[3] - b) < 1e-6
    and math.abs(color[4] - .92) < 1e-6 and state[fill].shown, "Midnight Dark did not paint its own palette")
Check(state[stripe].shown, "the accent stripe is off by default")
for _, key in ipairs(PIECES) do
    Check(state[toast[key]].alpha == 0, "Blizzard's backdrop piece " .. key .. " still shows under the Suite look")
end
SetMany({ opacity = 50, accent = false })
Check(math.abs(state[fill].color[4] - .5) < 1e-6 and not state[stripe].shown, "opacity or stripe was ignored")
Set("look", 6)
Check(#TexturesOn(toast) == 6, "a second look built a second panel")
r = Hex(PALETTES[5].border)
Check(math.abs(state[edges[1]].color[1] - r) < 1e-6, "Class Style did not paint the class palette")
Set("look", 1)
Check(not state[fill].shown and not state[edges[1]].shown and state[toast.Center].alpha == .8
    and state[toast.TopEdge].alpha == 1, "Blizzard's look did not come back as it was")

------------------------------------------------------------------ text
SetMany({ suiteFont = true, font = "Expressway.ttf", fontSize = 14, fontOutline = 3 })
for _, key in ipairs(LINES) do
    local line = toast[key]
    local font = state[line].font
    Check(font[1] == "Fonts\\Expressway.ttf" and font[2] == 14 and font[3] == "THICKOUTLINE"
        and state[line].shadowColor[4] == 0 and state[line].shadowOffset[1] == 0,
        key .. " did not take the Suite font")
end
SetMany({ fontShadow = true, fontShadowOpacity = 60, fontShadowDistance = 2, fontOutline = 1, fontRendering = 2 })
local line = toast.BottomLine
Check(state[line].font[3] == "MONOCHROME" and math.abs(state[line].shadowColor[4] - .6) < 1e-6
    and state[line].shadowOffset[1] == 2 and state[line].shadowOffset[2] == -2, "the text shadow was ignored")
Set("fontRendering", 3)
Check(state[line].shadowColor[4] == 0, "Slug text got a shadow")
Set("suiteFont", false)
for _, key in ipairs(LINES) do
    local saved = state[toast[key]]
    Check(saved.font[1] == "Fonts\\FRIZQT__.TTF" and saved.font[2] == 12 and saved.font[3] == ""
        and saved.shadowColor[4] == 1 and saved.shadowOffset[1] == 1 and saved.shadowOffset[2] == -1,
        key .. " did not get Blizzard's font and shadow back")
end

------------------------------------------------------------------ frame
SetMany({ scale = 150, raise = true })
Check(state[toast].scale == 1.5 and state[host].scale == 1.5 and state[toast].strata == "HIGH",
    "scale or layer did not reach the toast")
Check(state[toast.TooltipFrame].strata == "TOOLTIP", "the raised toast pulled its broadcast tooltip down")
-- Toast and host share the anchor point and scale, so the toast sits where
-- the Edit Mode frame shows it at any scale.
Check(PointOf(toast)[2] == host and PointOf(toast)[1] == PointOf(host)[1], "the scaled toast left its host")

------------------------------------------------------------------ edit mode
S.editMode = true
SetMany({ look = 2, suiteFont = false })
Check(host:IsShown() and state[host].backdrop == nil, "Edit Mode does not show the Suite look on the sample")
local lines = {}
for _, region in ipairs(RegionsOn(host)) do
    if state[region].kind == "FontString" then lines[#lines + 1] = region end
end
Check(#lines == 3 and state[lines[1]].text == "Battle.net friend" and state[lines[2]].text == "Mapko"
    and state[lines[3]].text == "has come online." and state[lines[1]].font[1] == "Fonts\\FRIZQT__.TTF",
    "the Edit Mode sample is not an online toast in Blizzard's font")
Check(state[host].strata == "HIGH", "the sample is not in the toast's layer")
Set("look", 1)
Check(state[host].backdrop == BACKDROP_TOAST_12_12 and not state[TexturesOn(host)[2]].shown,
    "the sample does not show Blizzard's look")
SetMany({ suiteFont = true, fontSize = 13 })
Check(state[lines[3]].font[2] == 13 and state[lines[3]].textColor[1] == .486,
    "the sample's Suite font lost its size or colors")
M:HideEditPreview()
Check(not host:IsShown(), "the sample stayed after Edit Mode closed")
S.editMode = false
M:Refresh()
Check(not host:IsShown(), "the sample showed outside Edit Mode")

------------------------------------------------------------------ hand back
-- Reset in Edit Mode: Blizzard's spot again, and its later passes stay there.
ShowToast()
SetMany({ moved = false, point = 7, x = 0, y = 0 })
point = PointOf(toast)
Check(point[2] == QuickJoinToastButton and point[1] == "BOTTOMLEFT" and point[3] == "TOPLEFT",
    "a reset toast was not handed back to Blizzard's spot")
hooks = Pass(false)
Check(hooks == 1 and PointOf(toast)[2] == QuickJoinToastButton and #state[toast].points == 1,
    "the passive hook placed a toast that keeps Blizzard's spot")
-- Right-side chat buttons and a hidden Friends button.
rawset(ChatAlertFrame, "justification", "RIGHT")
QuickJoinToastButton:Hide()
M:Refresh()
point = PointOf(host)
Check(point[1] == "BOTTOMRIGHT" and point[2] == ChatAlertFrame and point[3] == "BOTTOMRIGHT",
    "Blizzard's spot ignores the chat side or the hidden Friends button")
rawset(ChatAlertFrame, "justification", "LEFT")
QuickJoinToastButton:Show()

-- Off: everything comes back, and the hook stays inert.
SetMany({ moved = true, x = 100, y = 100, look = 4, scale = 80, raise = true })
Check(PointOf(toast)[2] == host and state[toast].scale == .8, "the toast did not follow again")
Stop()
point = PointOf(toast)
Check(point[2] == QuickJoinToastButton and state[toast].scale == 1 and state[toast].strata == "LOW"
    and state[toast.Center].alpha == .8 and not state[fill].shown and state[toast.TopLine].font[2] == 12
    and state[toast.TooltipFrame].strata == "TOOLTIP",
    "turning the module off did not give Blizzard its toast back")
hooks = Pass(false)
Check(hooks == 1 and PointOf(toast)[2] == QuickJoinToastButton, "the hook of a module that is off moved the toast")
Check(next(events) == nil, "the module listens to an event")
-- On again with Blizzard_BNet loaded: no event, no script, no ticker.
Start(Defaults())
Check(next(events) == nil, "the module listens to an event while the toast exists")
for _, frame in ipairs(created) do
    Check(state[frame].scripts == nil, "the module set a frame script")
end
Stop()

print("Suite Battle.net toast: " .. checks .. " checks passed")
