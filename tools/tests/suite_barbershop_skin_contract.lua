local root = assert(arg[1])
local flavor = arg[2] or "Mainline"
local function Noop() end
issecretvalue = function() return false end
InCombatLockdown = function() return false end
securecallfunction = function(fn, ...) return fn(...) end
local owner, attached = {}, 0
local NS = { Client = { isForever = flavor == "Forever", isMainline = flavor ~= "Forever" }, Checkmarks = {}, GenericWindowsShared = {}, AdapterKit = {
    WeakSet = function() return setmetatable({}, {__mode = "k"}) end,
    ObjectType = function(frame) return frame.kind end,
}}
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", NS)
local Shared = NS.GenericWindowsShared
Shared.CanSkin = function(frame, implicit) return NS.Safety.CanCreateRegions(frame, implicit) end
Shared.Attach = function() attached = attached + 1 return true end
Shared.Fade = function(_, region) if region then region.alpha = 0 end end
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/GenericWindowsNodes.lua"))("MSUF_Suite_Skin", NS)
local function Region(atlas)
    return {atlas = atlas, alpha = 1, SetAtlas = function(self, nextAtlas) self.atlas = nextAtlas end}
end
local button = {kind = "CheckButton", NormalTexture = Region(), PushedTexture = Region(),
    CheckedTexture = Region("charactercreate-ring-select"), Ring = Region("charactercreate-ring-metaldark"),
    CircleMask = Region("mask"), Flash = {Portrait = Region()} }
function button:IsForbidden() return false end
function button:IsProtected() return false, false end
function button:GetNormalTexture() return self.NormalTexture end
function button:GetPushedTexture() return self.PushedTexture end
function button:GetCheckedTexture() return self.CheckedTexture end
function button:SetNormalAtlas(atlas) self.NormalTexture:SetAtlas(atlas) end
function button:SetPushedAtlas(atlas) self.PushedTexture:SetAtlas(atlas) end
-- Native RingedMaskedButtonMixin:SetIconAtlas, verified at both pinned
-- Forever/Retail revisions in the accompanying source receipt.
function button:SetIconAtlas(atlas)
    self:SetNormalAtlas(atlas)
    self:SetPushedAtlas(atlas)
    self.Flash.Portrait:SetAtlas(atlas)
end
button:SetIconAtlas("charactercreate-icon-bodytype-selected")
local nativeIcon = button.NormalTexture.atlas
assert(Shared.SkinIconButtonBase(button, owner, {allowImplicitProtected = false}))
assert(attached == 1)
assert(button.NormalTexture.alpha == 1 and button.NormalTexture.atlas == nativeIcon,
    "Ringed body/category semantic icon disappeared while its checked ring remained")
assert(button.PushedTexture.alpha == 1 and button.CheckedTexture.alpha == 1 and button.Ring.alpha == 1,
    "masked customization selection/input artwork changed")
-- A pool reuse changes icon identity, never just the checked ring.
button:SetIconAtlas("charactercreate-icon-alteredform")
assert(Shared.SkinIconButtonBase(button, owner, {allowImplicitProtected = false}))
assert(button.NormalTexture.alpha == 1 and button.NormalTexture.atlas == "charactercreate-icon-alteredform")
local plain = { kind = "CheckButton", NormalTexture = Region("ordinary-checkbox-body") }
function plain:IsForbidden() return false end
function plain:IsProtected() return false, false end
function plain:GetNormalTexture() return self.NormalTexture end
assert(Shared.SkinIconButtonBase(plain, owner, {allowImplicitProtected = false}))
assert(plain.NormalTexture.alpha == 0, "ordinary checkbox chrome was left native")
button.IsProtected = function() return true, true end
assert(not Shared.SkinIconButtonBase(button, owner, {allowImplicitProtected = false}), "secure customization button was styled")
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/Catalog.lua"))("MSUF_Suite_Skin", NS)
local entry
for _, value in ipairs(NS.BlizzardCatalogData.entries) do if value.id == "barbershop" then entry = value end end
assert(entry and entry.mode and entry.mode.rootSurface == false and entry.mode.preserveRootArt == true,
    "the fullscreen barber interaction layer received a model-obscuring shell")
print("Suite barber icons and fullscreen layer: passed (" .. flavor .. ")")
