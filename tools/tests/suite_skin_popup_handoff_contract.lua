-- Static popups: while the Suite's popup module paints them it owns their
-- panels and text (Core/SuiteOwnership.lua; GenericWindowsCatalog leaves the
-- panels to it). It paints no button, so the skin keeps styling the popup
-- buttons and adopting the close button before, during and after the
-- module's look, as it did before the ownership surface existed. Real
-- UIPanelButtons.lua, SuiteOwnership.lua and Safety.lua.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

securecallfunction = function(callback, ...) return callback(...) end
function hooksecurefunc(target, method, callback)
    if type(target) == "string" then target, method, callback = _G, target, method end
    local original = target[method]
    assert(type(original) == "function", "hook target missing: " .. tostring(method))
    target[method] = function(...)
        original(...)
        callback(...)
    end
end
UIPanelButton_OnShow = Noop
UIPanelCloseButton_SetBorderAtlas = Noop
EventUtil = { ContinueOnAddOnLoaded = Noop }

local function Region()
    local region = { alpha = 1 }
    function region:IsForbidden() return false end
    function region:GetAlpha() return self.alpha end
    function region:SetAlpha(alpha) self.alpha = alpha end
    return region
end
local function PopupButton(name)
    local button = Region()
    button.name = name
    button.normal = Region()
    function button:IsProtected() return false, false end
    function button:GetNormalTexture() return self.normal end
    return button
end
local popupButtons = { PopupButton("StaticPopup1Button1"), PopupButton("StaticPopup1Button2") }
local popup = Region()
popup.CloseButton = PopupButton("StaticPopup1CloseButton")
popup.ButtonContainer = { Buttons = popupButtons }
function popup:IsProtected() return false, false end
function popup:GetName() return "StaticPopup1" end
function popup:SetupButtons() end
function popup:SetupCloseButton() end
StaticPopup1 = popup

local skinned, released, adopted, actionReleased = {}, {}, {}, {}
local owned = false
MSUFSuite = { Suite = { OwnsBlizzardSurface = function(surface)
    return surface == "staticPopups" and owned
end } }
local NS = {
    DB = { enabled = true, skins = {} },
    IsCombatLocked = function() return false end,
    GenericWindows = { IsCategoryEnabled = function() return true end },
    CombatGate = { RunOrDefer = Noop, Cancel = Noop },
    ControlSkin = {
        ApplyButton = function(button) skinned[button] = (skinned[button] or 0) + 1; return {} end,
        ApplyUIPanelButton = function(button) skinned[button] = (skinned[button] or 0) + 1; return {} end,
        ApplyThreeSliceButton = function() return {} end,
        Disable = function(button) released[button] = true; return true end,
        DisableOwner = Noop,
        GetOwner = function() return nil end,
    },
    WindowActionSkin = {
        AdoptNativeVisual = function(button) adopted[button] = (adopted[button] or 0) + 1 end,
        SyncNativeVisual = function(button) adopted[button] = (adopted[button] or 0) + 1; return {} end,
        Disable = function(button) actionReleased[button] = true end,
        GetOwner = function() return nil end,
        IsApplied = function() return false end,
    },
    Checkmarks = { TrackTexture = Noop, UntrackOwner = Noop, IsRedButtonArtKit = function() return false end },
}
for _, file in ipairs({ "Core/Safety.lua", "Core/Cosmetics.lua", "Core/SuiteOwnership.lua",
    "Adapters/UIPanelButtons.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
local Buttons = NS.UIPanelButtons

-- Free popups: the skin styles their buttons and adopts the close button.
assert(Buttons.Apply())
Check((skinned[popupButtons[1]] or 0) > 0 and (skinned[popupButtons[2]] or 0) > 0,
    "the skin did not style free static popup buttons")
Check(popupButtons[1].normal.alpha == 0, "the native popup button art was not faded")
popup:SetupCloseButton({ closeButton = true })
Check(adopted[popup.CloseButton] == 1, "the skin did not adopt a free popup close button")
local legacy = PopupButton("ContractLegacyButton")
UIPanelButton_OnShow(legacy)
Check(skinned[legacy] == 1, "a legacy UIPanelButton was not styled")

-- The popup module paints the popups: their buttons and close button keep
-- the skin, also when Blizzard sets a popup up again.
owned = true
Buttons.Refresh()
Check(NS.SuiteOwnership.Owns("staticPopups") and NS.SuiteOwnership.Owned("staticPopups"),
    "the contract lost the popup module's ownership")
Check(not released[popupButtons[1]] and not released[popupButtons[2]] and popupButtons[1].normal.alpha == 0,
    "the skin gave the popup buttons back while the popup module paints the panel")
Check(not actionReleased[popup.CloseButton], "the skin gave the popup close button back to Blizzard")
skinned[popupButtons[1]] = 0
local closeAdoptions = adopted[popup.CloseButton]
popup:SetupButtons()
popup:SetupCloseButton({ closeButton = true })
Check(skinned[popupButtons[1]] > 0 and adopted[popup.CloseButton] == closeAdoptions + 1,
    "a popup the Suite module paints lost its button skin on setup")
local legacySkins = skinned[legacy]
UIPanelButton_OnShow(legacy)
Check(skinned[legacy] == legacySkins + 1, "the popup module's look stopped the legacy button skin")

-- The module stops: the popups stay styled.
owned = false
skinned[popupButtons[1]] = 0
Buttons.Refresh()
Check(skinned[popupButtons[1]] > 0, "the skin lost the popup buttons after the module stopped")
local adoptions = adopted[popup.CloseButton]
popup:SetupCloseButton({ closeButton = true })
Check(adopted[popup.CloseButton] == adoptions + 1, "a popup close button was not adopted again")

print("Suite skin popup handoff: " .. checks .. " checks passed")
