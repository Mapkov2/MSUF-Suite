local _, NS = ...

-- A deliberately small, OOC-only icon primitive. Blizzard remains the owner
-- of item identity and quality: we read its existing IconBorder color and
-- never query item data or replace scripts. Adapters repaint a border after
-- Blizzard's own quality update (a SetItemButtonQuality post-hook, see
-- DeepWindows.InstallItemQualityHook); this module installs no hooks itself.
local IconSkin = {
    states = setmetatable({}, { __mode = "k" }),
    owners = {},
}
NS.IconSkin = IconSkin

local WatchSettings = NS.Registry.WatchSettings
local emptySpec = {}

-- true, false, or nil when unknown (missing method, forbidden or secret).
local function IsShown(region)
    local shown = NS.Safety.Read(region, "IsShown")
    if shown == nil then return nil end
    return shown == true
end

-- Places the four border lines (top, bottom, left, right) around icon.
-- Thickness is clamped to 1..3 and padding to 0..3 whole pixels.
local function AnchorLines(lines, icon, thickness, padding)
    if not lines or not icon then return end
    thickness = math.max(1, math.min(3, math.floor((tonumber(thickness) or 1) + 0.5)))
    padding = math.max(0, math.min(3, math.floor((tonumber(padding) or 0) + 0.5)))
    local extent = padding + thickness
    local top, bottom, left, right = lines[1], lines[2], lines[3], lines[4]
    for index = 1, 4 do lines[index]:ClearAllPoints() end

    top:SetPoint("BOTTOMLEFT", icon, "TOPLEFT", -extent, padding)
    top:SetPoint("BOTTOMRIGHT", icon, "TOPRIGHT", extent, padding)
    top:SetHeight(thickness)
    bottom:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -extent, -padding)
    bottom:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", extent, -padding)
    bottom:SetHeight(thickness)
    left:SetPoint("TOPRIGHT", icon, "TOPLEFT", -padding, extent)
    left:SetPoint("BOTTOMRIGHT", icon, "BOTTOMLEFT", -padding, -extent)
    left:SetWidth(thickness)
    right:SetPoint("TOPLEFT", icon, "TOPRIGHT", padding, extent)
    right:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", padding, -extent)
    right:SetWidth(thickness)
end
-- Shared with the options preview so it draws the same border.
IconSkin.AnchorLines = AnchorLines

local function RefreshState(state)
    if not state or NS.IsCombatLocked() then return false end
    local theme = NS.DB and NS.DB.theme or NS.Defaults.theme
    local style = theme.iconBorderStyle or NS.Defaults.theme.iconBorderStyle
    local visible = state.enabled ~= false and style ~= "off" and IsShown(state.icon) ~= false
    local r, g, b, a
    -- The faded native border still carries Blizzard's live quality color.
    if visible and style == "quality" and IsShown(state.nativeBorder) == true then
        r, g, b, a = NS.Safety.ReadColor(state.nativeBorder, "GetVertexColor")
    end
    if not r then
        r, g, b, a = NS.Theme.GetColor("iconBorder")
    end
    AnchorLines(state.lines, state.icon, theme.iconBorderThickness, theme.iconBorderPadding)
    a = a * (tonumber(theme.iconBorderOpacity) or 1)
    for index = 1, #state.lines do
        local line = state.lines[index]
        line:SetColorTexture(r, g, b, a)
        if visible then line:Show() else line:Hide() end
    end
    return true
end

local function RefreshAll()
    if NS.IsCombatLocked() then return end
    for _, state in pairs(IconSkin.states) do
        RefreshState(state)
    end
end

-- The border settings RefreshState reads. Borders repaint only for these
-- (see Registry.WatchSettings), once per frame however many settings a
-- slider drag writes.
local BORDER_SETTINGS = {
    appearance = {
        iconBorderStyle = true,
        iconBorderThickness = true,
        iconBorderPadding = true,
        iconBorderOpacity = true,
    },
    color = { iconBorder = true },
}

local function CreateLines(button, icon)
    local lines = {
        button:CreateTexture(nil, "OVERLAY", nil, 1),
        button:CreateTexture(nil, "OVERLAY", nil, 1),
        button:CreateTexture(nil, "OVERLAY", nil, 1),
        button:CreateTexture(nil, "OVERLAY", nil, 1),
    }
    AnchorLines(lines, icon, 1, 0)
    return lines
end

function IconSkin.Apply(button, owner, spec)
    spec = spec or emptySpec
    if not button or NS.IsCombatLocked() then return nil, "combat" end
    if not NS.Safety.CanCreateRegions(button, spec.allowImplicitProtected) then
        return nil, "protected"
    end
    local icon = spec.icon or button.Icon or button.icon or button.IconTexture
    local nativeBorder = spec.nativeBorder or button.IconBorder or button.iconBorder
    if not icon or not nativeBorder or type(button.CreateTexture) ~= "function" then
        return nil, "unsupported"
    end

    local state = IconSkin.states[button]
    if state and state.enabled ~= false and state.owner ~= owner then
        return nil, "already owned"
    end
    if not NS.Cosmetics.Fade(nativeBorder, owner) then return nil, "native" end
    if not state then
        state = {
            button = button,
            lines = CreateLines(button, icon),
        }
        IconSkin.states[button] = state
    end
    state.icon = icon
    state.nativeBorder = nativeBorder
    state.owner = owner
    state.enabled = true
    local owned = IconSkin.owners[owner]
    if not owned then
        owned = setmetatable({}, { __mode = "k" })
        IconSkin.owners[owner] = owned
    end
    owned[button] = true
    WatchSettings(RefreshAll, BORDER_SETTINGS)
    RefreshState(state)
    return state
end

function IconSkin.DisableOwner(owner)
    local owned = IconSkin.owners[owner]
    if not owned then return false end
    for button in pairs(owned) do
        local state = IconSkin.states[button]
        if state and state.owner == owner then
            state.enabled = false
            for index = 1, #state.lines do state.lines[index]:Hide() end
        end
    end
    IconSkin.owners[owner] = nil
    return true
end

function IconSkin.GetState(button)
    return IconSkin.states[button]
end

function IconSkin.GetOwner(button)
    local state = IconSkin.states[button]
    return state and state.enabled ~= false and state.owner or nil
end
