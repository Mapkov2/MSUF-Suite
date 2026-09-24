local _, NS = ...

-- A deliberately small, OOC-only icon primitive. Blizzard remains the owner
-- of item identity and quality: we read its existing IconBorder color and
-- never query item data, replace scripts, or hook quality update functions.
local IconSkin = {
    states = setmetatable({}, { __mode = "k" }),
    owners = {},
}
NS.IconSkin = IconSkin

local listenerOwner = {}
local listenerRegistered = false

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

local function Accessible(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        if type(canaccessvalue) ~= "function" or not canaccessvalue(value) then
            return nil
        end
    end
    return value
end

local function IsShown(region)
    if not region or type(region.IsShown) ~= "function" then return nil end
    local ok, shown = pcall(region.IsShown, region)
    if not ok then return nil end
    shown = Accessible(shown)
    if shown == nil then return nil end
    return shown == true
end

local function ReadVertexColor(region)
    if not region or type(region.GetVertexColor) ~= "function" then return nil end
    local ok, r, g, b, a = pcall(region.GetVertexColor, region)
    if not ok then return nil end
    r, g, b, a = Accessible(r), Accessible(g), Accessible(b), Accessible(a)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    return r, g, b, type(a) == "number" and a or 1
end

local function SetLineColor(line, r, g, b, a)
    if type(line.SetColorTexture) == "function" then
        line:SetColorTexture(r, g, b, a)
    else
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        line:SetVertexColor(r, g, b, a)
    end
end

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

local function RefreshState(state)
    if not state or NS.IsCombatLocked() then return false end
    local style = (NS.DB and NS.DB.theme and NS.DB.theme.iconBorderStyle)
        or NS.Defaults.theme.iconBorderStyle
    local iconVisible = IsShown(state.icon)
    local visible = state.enabled ~= false and style ~= "off" and iconVisible ~= false
    local r, g, b, a
    if visible and style == "quality" and IsShown(state.nativeBorder) == true then
        r, g, b, a = ReadVertexColor(state.nativeBorder)
    end
    if not r then
        r, g, b, a = NS.Theme.GetColor("iconBorder")
    end
    local theme = NS.DB and NS.DB.theme or NS.Defaults.theme
    AnchorLines(state.lines, state.icon, theme.iconBorderThickness, theme.iconBorderPadding)
    a = a * (tonumber(theme.iconBorderOpacity) or 1)
    for index = 1, #state.lines do
        local line = state.lines[index]
        SetLineColor(line, r, g, b, a)
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

local function EnsureListener()
    if listenerRegistered then return end
    NS.Registry.AddListener(listenerOwner, RefreshAll)
    listenerRegistered = true
end

local function CreateLines(button, icon)
    local top = button:CreateTexture(nil, "OVERLAY", nil, 1)
    local bottom = button:CreateTexture(nil, "OVERLAY", nil, 1)
    local left = button:CreateTexture(nil, "OVERLAY", nil, 1)
    local right = button:CreateTexture(nil, "OVERLAY", nil, 1)

    local lines = { top, bottom, left, right }
    AnchorLines(lines, icon, 1, 0)
    return lines
end

function IconSkin.Apply(button, owner, spec)
    spec = spec or {}
    if not button or NS.IsCombatLocked() then return nil, "combat" end
    if not NS.Safety or not NS.Safety.CanCreateRegions(button, spec.allowImplicitProtected) then
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
    if not state then
        local faded = NS.Cosmetics.Fade(nativeBorder, owner)
        if not faded then return nil, "native" end
        state = {
            button = button,
            icon = icon,
            nativeBorder = nativeBorder,
            lines = CreateLines(button, icon),
            owner = owner,
            enabled = true,
        }
        IconSkin.states[button] = state
    else
        local faded = NS.Cosmetics.Fade(nativeBorder, owner)
        if not faded then return nil, "native" end
        state.icon = icon
        state.nativeBorder = nativeBorder
        state.owner = owner
        state.enabled = true
    end
    local owned = IconSkin.owners[owner]
    if not owned then
        owned = WeakSet()
        IconSkin.owners[owner] = owned
    end
    owned[button] = true
    EnsureListener()
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
