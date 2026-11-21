local _, NS = ...
local S, W = NS.Safety, NS.PublicWidgets
local MenuStyle = {}
NS.PublicMenuStyle = MenuStyle

local elements = setmetatable({}, { __mode = "k" })
local classicMarks = {
    ["common-dropdown-icon-checkmark-yellow-classic-2"] = true,
    ["common-dropdown-icon-radialtick-yellow-classic"] = true,
}

local function Region(row, key, kind)
    local region = S.Field(row, key)
    if not W.Safe(region) then return end
    -- Blizzard swaps in an __index function for each compositor attachment.
    -- A template's persistent XML regions keep their original metatable.
    local mt = getmetatable(region)
    if type(mt) == "table" and type(mt.__index) == "function"
        and S.Read(region, "GetParent") == row and S.Read(region, "GetObjectType") == kind then
        return region
    end
end

local function Tint(texture, role)
    if texture then S.Invoke(texture, "SetVertexColor", NS.Theme.GetColor(role)) end
end

local function PaintLabel(label, role)
    local path = NS.Typography.GetSelectionPath(NS.Typography.GetSelection())
    local font = NS.LabelStyle.GetMenuFont(label, path)
    if font and S.Invoke(label, "SetFontObject", font) then
        local labelText = S.Read(label, "GetText")
        if type(labelText) == "string" then S.Invoke(label, "SetTextToFit", labelText) end
    end
    S.Invoke(label, "SetTextColor", NS.Theme.GetColor(role))
end

local function Live(binding)
    if not binding then return false end
    local scope = binding.scope
    return scope.releaseEpoch == binding.epoch and not scope.released
        and not scope.client.released and not scope.client.unregisterPending
end

-- Runs inside Blizzard's description initializer. The native compositor resets
-- the attached regions when the row is released or initialized again.
local function Paint(row, description)
    if not S.Public(description) or not description or NS.IsCombatLocked() then return end
    local binding = elements[description]
    if not Live(binding) or binding.scope.suspended or not binding.enabled(binding.scope) then return end
    if not S.Public(row) or not S.CanDecorate(row) or not S.IsCompositorManaged(row) then return end
    local label = Region(row, "fontString", "FontString")
    if not label then return end
    local base = Region(row, "leftTexture1", "Texture")
    local mark = Region(row, "leftTexture2", "Texture")
    local atlas = base and S.Read(base, "GetAtlas")
    local singleMark = type(atlas) == "string" and classicMarks[atlas]
    local selected = mark or singleMark
    PaintLabel(label, selected and "accentBright" or S.Read(row, "GetObjectType") == "Frame" and "title" or "text")
    Tint(base, singleMark and "checkmark" or "borderSoft")
    Tint(mark, "checkmark")
    Tint(Region(row, "highlight", "Texture"), "hover")
    Tint(Region(row, "arrow", "Texture"), "blizzardArrow")
end

local Initialize = S.Isolated(Paint)

local function Collect(description, found, seen)
    if not S.Public(description) or not S.HasMethod(description, "EnumerateElementDescriptions") then return end
    for _, child in description:EnumerateElementDescriptions() do
        if S.Public(child) and S.HasMethod(child, "AddInitializer") and not seen[child] then
            seen[child] = true
            found[#found + 1] = child
            Collect(child, found, seen)
        end
    end
end

function MenuStyle.Bind(root, scope, enabled)
    if not S.Public(root) or not S.HasMethod(root, "AddMenuReleasedCallback")
        or not S.HasMethod(root, "EnumerateElementDescriptions") then return false, "invalid-menu-description" end
    local found = {}
    Collect(root, found, { [root] = true })
    for _, child in ipairs(found) do
        local binding = elements[child]
        if Live(binding) and binding.scope ~= scope then return false, "target-owned" end
    end
    local binding = { scope = scope, epoch = scope.releaseEpoch, enabled = enabled }
    for _, child in ipairs(found) do
        if not elements[child] then child:AddInitializer(Initialize) end
        elements[child] = binding
    end
    return true, "registered"
end
