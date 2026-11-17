local _, NS = ...

local Labels = {}
NS.LabelStyle = Labels
local Safety = NS.Safety
local styled = setmetatable({}, { __mode = "k" })
local menuFonts = {}
local menuFontCount = 0
local MAX_MENU_FONTS = 32

-- Blizzard's GameFonts.xml supplies these families for the corresponding
-- scripts. Greek uses the broad UI sans face. Mixed labels that use the
-- configured face only need a fallback when they contain one of these scripts.
local function Fallback(text)
    if type(text) ~= "string" then return end
    if text:find("[\234-\237][\128-\191][\128-\191]") then
        for char in text:gmatch("[\234-\237][\128-\191][\128-\191]") do
            local a, b = char:byte(1, 2)
            if a >= 235 and (a < 237 or b <= 158) or a == 234 and b >= 176 then
                return "Fonts\\2002.TTF"
            end
        end
    end
    if text:find("[\208-\211][\128-\191]") then return "Fonts\\FRIZQT___CYR.TTF" end
    if text:find("[\206\207][\128-\191]") then return "Fonts\\ARIALN.TTF" end
    if text:find("[\227-\233][\128-\191][\128-\191]") then return "Fonts\\ARKai_T.ttf" end
end

local function Font(path, height, flags)
    if type(CreateFont) ~= "function" then return end
    local key = path .. ":" .. height .. ":" .. flags
    local font = menuFonts[key]
    if font ~= nil then return font or nil end
    if menuFontCount >= MAX_MENU_FONTS then return end
    menuFontCount = menuFontCount + 1
    font = CreateFont("MSUFSkinMenuLabelFont" .. menuFontCount)
    if not font then return end
    menuFonts[key] = false
    font:SetFont(path, height, flags)
    local actual = Safety.Read(font, "GetFont")
    if type(actual) ~= "string" or actual:lower() ~= path:lower() then return end
    menuFonts[key] = font
    return font
end

local function ReadFont(label)
    local path, height, flags = Safety.Call(label, "GetFont")
    if not Safety.Public(path) or not Safety.Public(height) or not Safety.Public(flags)
        or type(path) ~= "string" or type(height) ~= "number" or height <= 0 then return end
    return path, height, type(flags) == "string" and flags or ""
end

function Labels.GetConfiguredPath()
    local settings = NS.DB and NS.DB.typography
    if not settings or not settings.enabled then return end
    return NS.Typography.GetSelectionPath(NS.Typography.GetSelection())
end

function Labels.CanStyle(label, menu)
    if not Safety.Public(label) or not Safety.CanDecorate(label)
        or Safety.Read(label, "GetObjectType") ~= "FontString" then return false end
    if menu then return true end
    local parent = Safety.Call(label, "GetParent")
    return Safety.Public(parent) and not Safety.IsCompositorManaged(label)
        and (parent == nil or not Safety.IsCompositorManaged(parent))
end

function Labels.Apply(label, owner, menu, configured)
    if NS.IsCombatLocked() or not Labels.CanStyle(label, menu) then return end
    local current, height, flags = ReadFont(label)
    if not current then return end
    local previous = styled[label]
    if previous and previous.owner ~= owner then return end
    local text = Safety.Read(label, "GetText")
    if configured == nil then configured = Labels.GetConfiguredPath() end
    local desired = configured and (Fallback(text) or configured)
    if not desired then
        if previous then Labels.Release(label, owner) end
        return
    end
    if current:lower() == desired:lower() then return end
    local original = previous and previous.path or current
    if previous and previous.applied ~= current then original = current end
    if menu then
        local font = Font(desired, height, flags)
        if not font or not Safety.HasMethod(label, "SetFontObject") then return end
        local nativeFont = Safety.Read(label, "GetFontObject")
        if not nativeFont then return end
        if previous and previous.applied == current then nativeFont = previous.font end
        local r, g, b, a = Safety.ReadColor(label, "GetTextColor")
        label:SetFontObject(font)
        if r then label:SetTextColor(r, g, b, a) end
        styled[label] = { owner = owner, path = original, applied = desired, font = nativeFont }
        return
    end
    if Safety.HasMethod(label, "SetFont") and label:SetFont(desired, height, flags) then
        styled[label] = { owner = owner, path = original, applied = desired }
    end
end

function Labels.Release(label, owner, resetByPool)
    local previous = styled[label]
    if not previous or previous.owner ~= owner then return end
    if not resetByPool and NS.IsCombatLocked() then
        local key = "skin-label-release:" .. tostring(label)
        NS.CombatGate.RunOrDefer(key, function() Labels.Release(label, owner) end)
        return
    end
    styled[label] = nil
    if resetByPool or not Labels.CanStyle(label, previous.font ~= nil) then return end
    local current, height, flags = ReadFont(label)
    if not current or current:lower() ~= previous.applied:lower() then return end
    if previous.font then
        local r, g, b, a = Safety.ReadColor(label, "GetTextColor")
        label:SetFontObject(previous.font)
        if r then label:SetTextColor(r, g, b, a) end
    elseif Safety.HasMethod(label, "SetFont") then
        label:SetFont(previous.path, height, flags)
    end
end
