-- Native EditMode/addon close templates use the Suite X even when the other
-- actions stay Native. Input, geometry and original native artwork stay owned.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local checks = 0
local function Check(value, why) assert(value, why) checks = checks + 1 end
local function Read(path)
    local f = assert(io.open(path, "rb")) local text = f:read("*a") f:close()
    return (text:gsub("\r\n", "\n"))
end
local source = Read(root .. "/tools/tests/suite_skin_motion_contract.lua")
source = source:sub(1, assert(source:find('local parent = Target("Frame", UIParent)', 1, true)) - 1)
local first = assert(source:find("NS.Checkmarks = {", 1, true))
local last = assert(source:find('Load("Rendering/WindowActionSkin.lua")', first, true))
source = source:sub(1, first - 1) .. [[Load("Core/Checkmarks.lua")
NS.Checkmarks.TrackDropdown, NS.Checkmarks.UntrackDropdown = Noop, Noop
NS.Checkmarks.ReleaseMenus = Noop
]] .. source:sub(last)
local H = assert(loadstring(source .. [[
return { NS = NS, Target = Target, Texture = Texture, Tick = Tick, created = created,
    SetCombat = function(value) lockdown = value end }
]], "@close-style-host"))()
local NS, W = H.NS, H.NS.WindowActionSkin
local function Noop() end
NS.CombatGate.RunOrDefer = function(_, callback) return callback() end
NS.DB.enabled = true
NS.BlizzardYellow.TrackFrames = Noop
NS.SuiteOwnership = { IsBagShell = function() return false end }
NS.CharacterDetails = { IsHost = function() return false end }
NS.CharacterStats, NS.EQoLCharacter = NS.CharacterDetails, NS.CharacterDetails
NS.WindowControls = { Attach = Noop, TrackFocus = Noop, DisableOwner = Noop }
NS.LabelStyle = { CanStyle = function() return false end, Apply = Noop }
for _, file in ipairs({ "../MSUF_Suite/Appearance/Cosmetics", "Rendering/ScrollBarSkin", "Adapters/AdapterKit", "Adapters/GenericWindows",
    "Adapters/GenericWindowsNodes", "Adapters/GenericWindowsFrames", "Adapters/AddonSkinVisuals", "Adapters/AceWidgets" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file .. ".lua"))("MSUF_Suite_Skin", NS)
end
UIParent.width, UIParent.height = 1920, 1080
local options = NS.DB.icons.windowActions
local nativeAtlases = { Normal = "RedButton-Exit", Pushed = "RedButton-exit-pressed",
    Disabled = "RedButton-Exit-Disabled", Highlight = "RedButton-Highlight" }
local function Button(parent)
    local button, native = H.Target("Button", parent, 0, 0, 24, 24), {}
    function button:GetObjectType() return "Button" end
    function button:GetText() return "" end
    function button:GetRegions() return end
    function button:GetChildren() return end
    for key, atlas in pairs(nativeAtlases) do
        local region = H.Texture()
        function region:GetAtlas() return atlas end
        function region:GetObjectType() return "Texture" end
        button.slots[key], native[key] = region, region
    end
    return button, native
end
local function Root(name)
    local frame = H.Target("Frame", UIParent, 0, 0, 500, 400)
    function frame:GetName() return name end
    function frame:GetRegions() return end
    function frame:GetChildren() return self.CloseButton end
    return frame
end

for _, globalStyle in ipairs({ "native", "bare", "soft", "outline" }) do
    for _, closeStyle in ipairs({ "missing", "bare", "soft", "outline", "native", "global" }) do
        options.style = globalStyle
        options.closeStyle = closeStyle ~= "missing" and closeStyle or nil
        local expected = closeStyle == "missing" and "bare" or closeStyle == "global" and globalStyle or closeStyle
        local frame = Root("EditModeManagerFrame")
        local button, native = Button(frame)
        frame.CloseButton = button
        local clicks = 0
        local click = function() clicks = clicks + 1 end
        button:SetScript("OnClick", click)
        local owner = "native-close:" .. globalStyle .. ":" .. closeStyle
        Check(NS.Checkmarks.DetectWindowAction(button) == "close", "pinned native atlas family was not detected")
        Check(NS.GenericWindows.ApplyFrame(frame, owner, { allowImplicitProtected = true, registerDynamicRows = false }),
            "native EditMode generic route refused the root")
        local state = W.GetState(button)
        Check(state and state.style == expected, "EditMode X did not resolve its own style: " .. globalStyle .. "/" .. closeStyle)
        Check(W.HasOwnedStates(button) == (expected ~= "native"), "Suite X slots disagree with the effective close style")
        Check(button.width == 24 and button.height == 24 and button.scripts.OnClick == click,
            "close styling changed native geometry or input")
        button:Fire("OnClick")
        Check(clicks == 1, "native close click did not fire once")
        local surface = NS.Registry.GetSurface(button)
        if expected == "bare" or expected == "native" then
            Check(not surface or surface.visible == false, "bare/native X retained a generic button surface")
        else
            Check(surface and surface.visible and surface.spec.fillVisible == (expected == "soft"), "custom X surface style was lost")
        end
        Check(W.Disable(button, owner), "native close release failed")
        for key, region in pairs(native) do Check(button.slots[key] == region, "native close slot did not restore: " .. key) end

        -- The same exact template is also constructed by AceGUI/addons.
        local addon = Root("AddonWindow")
        addon.CloseButton = Button(addon)
        local widget = { type = "Window", frame = addon, closebutton = addon.CloseButton }
        Check(NS.AceWidgets.Apply(widget, owner), "Ace addon window refused the skin")
        NS.AddonSkinVisuals.Tree(addon, owner)
        Check(W.GetState(addon.CloseButton).style == expected, "addon and EditMode X styles differ")
        NS.AddonSkinVisuals.Release(owner)
    end
end

-- Existing profiles gain only the independent X default. Native expand/minimize
-- and every unrelated saved preference stay intact; invalid imports normalize.
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Database.lua"))("MSUF_Suite_Skin", NS)
NS.FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" }
local legacy = NS.CopyValue(NS.Defaults)
legacy.icons.windowActions.style, legacy.icons.windowActions.closeStyle = "native", nil
local opacity = legacy.icons.windowActions.opacity
NS.Database.Normalize(legacy)
Check(legacy.icons.windowActions.style == "native" and legacy.icons.windowActions.closeStyle == "bare"
    and legacy.icons.windowActions.opacity == opacity, "old Native profile did not retain its choices with the Suite X default")
legacy.icons.windowActions.closeStyle = "invalid"
NS.Database.Normalize(legacy)
Check(legacy.icons.windowActions.closeStyle == "bare", "invalid imported close style survived normalization")
legacy.icons.windowActions.closeStyle = "global"
NS.Database.Normalize(legacy)
Check(legacy.icons.windowActions.closeStyle == "global", "explicit global close style was discarded")

options.style, options.closeStyle = "native", nil
local minimize = Button(UIParent)
Check(W.ApplyExplicit(minimize, "other-action", "minimize").style == "native"
    and not W.HasOwnedStates(minimize), "independent X restyled another window action")
W.Disable(minimize, "other-action")
local api = NS.PublicAPI.API
local scope = assert(api:RegisterAddon("CloseStyleContract"))
local external = Button(UIParent)
Check(scope:SkinWindowAction(external, "close"), "cooperative addon close failed")
Check(W.HasOwnedStates(external) and W.GetState(external).style == "bare", "cooperative API kept the native X")
local glyphs = W.GetState(external).glyphs
Check(W.SetOption("closeStyle", "native") and not W.HasOwnedStates(external), "explicit Native X was not available")
Check(W.SetOption("closeStyle", "bare") and W.HasOwnedStates(external) and W.GetState(external).glyphs == glyphs,
    "returning to the Suite X allocated another glyph set")
Check(not W.SetOption("closeStyle", "invalid"), "invalid close-style option was accepted")
H.SetCombat(true)
Check(not W.SetOption("closeStyle", "native") and options.closeStyle == "bare", "combat settings write changed the X")
H.SetCombat(false)
Check(scope:ReleaseAll() and not W.IsApplied(external), "API release left the X style applied")

if flavor == "Forever" then
    local caption = H.Target("Button", UIParent, 0, 0, 24, 24)
    Check(W.PaintCaption(caption, "close", "normal"), "skin preview kept the native X under Native actions")
    Check(not W.PaintCaption(caption, "minimize", "normal"), "skin preview restyled a Native minimize action")
    W.SetOption("closeStyle", "native")
    Check(not W.PaintCaption(caption, "close", "normal"), "preview did not honor explicit Native X")
end
H.Tick(200)
for _, frame in ipairs(H.created) do
    Check(frame:GetScript("OnUpdate") == nil, "close-style selection retained an idle driver")
end
print("Suite close style (" .. flavor .. "): " .. checks .. " checks passed")
