-- Real Chrome -> AdapterKit -> IconSkin: cold safe combat and exact native targets.
local root = assert(arg[1])
local combat, checks, writes, probes = true, 0, 0, 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
local function Noop() end
securecallfunction = function(callback, ...) return callback(...) end
InCombatLockdown = function() return false end -- PLAYER_REGEN_DISABLED edge
local function Region()
    local region = { shown = true, alpha = 1, color = { 0.1, 0.7, 0.2, 1 }, hooks = {} }
    function region:IsForbidden() probes = probes + 1 return self.forbidden == true end
    function region:IsProtected() probes = probes + 1 return self.protected == true, false end
    function region:IsShown() return self.shown end
    function region:IsVisible() return self.shown end
    function region:GetVertexColor() return unpack(self.color) end
    function region:HookScript(event, callback) self.hooks[event] = callback end
    function region:Fire(event) if self.hooks[event] then self.hooks[event](self) end end
    for _, key in ipairs({ "ClearAllPoints", "SetPoint", "SetWidth", "SetHeight", "SetColorTexture" }) do
        region[key] = function() writes = writes + 1 end
    end
    function region:Show() writes = writes + 1 self.shown = true end
    function region:Hide() writes = writes + 1 self.shown = false end
    function region:CreateTexture() writes = writes + 1 return Region() end
    return region
end
local pending, watcher = {}, nil
local NS = { IsCombatLocked = function() return combat end,
    DB = { enabled = true, theme = { iconBorderStyle = "quality", iconBorderThickness = 2, iconBorderPadding = 1 } },
    Defaults = { theme = { iconBorderStyle = "quality" } },
    Theme = { GetColor = function() return 1, 1, 1, 1 end },
    Client = { IsAddOnLoaded = function() return true end },
    Registry = { WatchSettings = function(callback) watcher = callback end },
    GenericWindows = { IsCategoryEnabled = function() return true end },
    CombatGate = {
        RunOrDefer = function(key, callback) if combat then pending[key] = callback else callback() end end,
        Cancel = function(key) pending[key] = nil end,
    },
}
local function Load(path)
    local override = os.getenv("SUITE_PAPERDOLL_OVERRIDE_ROOT")
    local candidate = override and override .. "/" .. path
    local handle = candidate and io.open(candidate, "rb")
    if handle then handle:close() else candidate = nil end
    assert(loadfile(candidate or root .. "/MSUF_Suite_Skin/" .. path))("MSUF_Suite_Skin", NS)
end
Load("Core/Safety.lua")
NS.Cosmetics = { Fade = function(target)
    Check(NS.Safety.CanDecorate(target, not combat), "native protected icon border was faded")
    writes = writes + 1
    return true
end }
NS.Surface = { Attach = function(target)
    Check(NS.Safety.CanCreateRegions(target, not combat), "protected slot surface was created")
    writes = writes + 1
    return {}
end, SetVisible = Noop }
NS.Surface.Ensure = NS.Surface.Attach
Load("Rendering/IconSkin.lua")
Load("Adapters/AdapterKit.lua")
Load("Adapters/PaperDollChrome.lua")
CharacterFrame, CharacterHeadSlot = Region(), Region()
CharacterHeadSlot.Icon, CharacterHeadSlot.IconBorder = Region(), Region()
local panel, applies = nil, 0
local function Apply(state)
    if NS.AdapterKit.DeferHidden(CharacterFrame, state, Apply, state) then return true, "hidden" end
    applies = applies + 1
    panel:SkinAllSlots(state)
    return true, "applied"
end
panel = NS.PaperDollChrome.New({ prefix = "combat-character", rootName = "CharacterFrame",
    addon = "native", slotNames = { "CharacterHeadSlot" }, safeCombatApply = true,
    applyNow = Apply, applyOrWait = Apply })
panel.skinAllSlots = function(state) panel:SkinAllSlots(state) end
Check(panel:Activate("window") and applies == 1, "safe cold combat Character activation was deferred")
local state = NS.IconSkin.GetState(CharacterHeadSlot)
Check(state and state.linesShown and state.anchoredThickness == 2 and state.anchoredPadding == 1,
    "cold combat slot lost actual icon skin or configured border geometry")
local callback = pending["combat-character:window:apply"]
Check(type(callback) == "function", "safe combat activation lost complete regen reconciliation")
panel:Activate("window")
Check(pending["combat-character:window:apply"] == callback, "combat activation allocated repeated completion jobs")
CharacterHeadSlot.IconBorder.color = { 0.8, 0.1, 0.9, 1 }
panel:RefreshSlot(CharacterHeadSlot)
Check(state.painted[1] == 0.8, "safe combat slot update did not repaint real IconSkin")
for _, target in ipairs({ CharacterHeadSlot, CharacterHeadSlot.Icon, CharacterHeadSlot.IconBorder }) do
    target.protected = true
    writes = 0
    panel:RefreshSlot(CharacterHeadSlot)
    Check(writes == 0, "slot refresh wrote a protected native child")
    Check(pending["combat-character:window:slots"], "protected slot refresh lost deferred reconciliation")
    Check(not NS.IconSkin.Apply(CharacterHeadSlot, "window", { allowImplicitProtected = true }),
        "real IconSkin adopted a protected target at the combat edge")
    target.protected = false
end
CharacterHeadSlot.IconBorder.forbidden = true
writes = 0
panel:RefreshSlot(CharacterHeadSlot)
Check(writes == 0, "slot refresh wrote forbidden artwork")
CharacterHeadSlot.IconBorder.forbidden = false
CharacterFrame.shown = false
writes, probes = 0, 0
for _ = 1, 64 do panel:RefreshSlot(CharacterHeadSlot) end
Check(writes == 0 and probes == 128, "hidden native slot updates performed per-row work")
-- No opt-in: Inspect and structural callers retain their established gate.
local inspectApplies = 0
InspectFrame = Region()
local inspect = NS.PaperDollChrome.New({ prefix = "inspect", rootName = "InspectFrame", addon = "native", slotNames = {},
    applyNow = function() inspectApplies = inspectApplies + 1 end,
    applyOrWait = function() inspectApplies = inspectApplies + 1 end })
Check(not inspect:Activate("window") and inspectApplies == 0, "unaudited Inspect activation bypassed combat deferral")
local structural = 0
panel:ForActiveOwners("layout", function() structural = structural + 1 end)
Check(structural == 0, "structural PaperDoll callback bypassed combat deferral")
combat = false
for key, job in pairs(pending) do pending[key] = nil job() end
Check(applies == 2, "hidden regen completion traversed Character contents")
CharacterFrame.shown = true
CharacterFrame:Fire("OnShow")
Check(applies == 3 and state.painted[1] == 0.8, "safe show lost deferred completion")
Check(inspectApplies == 1 and structural == 1, "deferred structural work was lost")
Check(watcher, "icon setting watcher was not retained")
print("PaperDoll safe combat integration: " .. checks .. " checks passed")
