-- The Journeys tutorial uses a pooled HelpTip, not the shared GameTooltip.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_skin_encounter_render_contract.lua", "rb"))
local source = file:read("*a"); file:close()
local stop = assert(source:find("local boss=Button()", 1, true))
local body = [======[
local override = os.getenv("SUITE_EJ_PANELS_SOURCE")
if override then assert(loadfile(override))("MSUF_Suite_Skin", NS) end
local locked, visible, jobs = false, true, {}
InCombatLockdown = function() return locked end
NS.IsCombatLocked = InCombatLockdown
NS.CombatGate = { Cancel = function(key) jobs[key] = nil end,
    RunOrDefer = function(key, callback) jobs[key] = callback end }
local function Protected(self) return self.protected == true, self.protected == true end
local function NativeTexture()
    local texture = Texture()
    texture.r, texture.g, texture.b, texture.a = 1, 1, 1, 1
    texture.IsProtected = Protected
    function texture:IsDesaturated() return self.desaturated == true end
    function texture:SetDesaturated(value)
        assert(not (locked and self.protected), "protected desaturation write")
        self.desaturated = value
    end
    function texture:GetVertexColor() return self.r, self.g, self.b, self.a end
    function texture:SetVertexColor(r,g,b,a)
        assert(not (locked and self.protected), "protected vertex write")
        self.r, self.g, self.b, self.a = r,g,b,a
    end
    return texture
end
local journal, encounter, info = Target(), Target(), Target()
journal.encounter, encounter.info = encounter, info
function journal:IsVisible() return visible end
local state = { frame=journal, owner="journal-tip", active=true, surfaces=NS.AdapterKit.WeakSet(),
    textColors=NS.AdapterKit.NewTextColors(), deferred={} }
NS.EncounterJournalSkin = { activeState = state }
EncounterJournalJourneysTab = Target()
function EncounterJournalJourneysTab:GetParent() return journal end
local parent = EncounterJournalJourneysTab
local tip = Target()
tip.Text, tip.hooks = Text(), {}
tip.Text.r, tip.IsProtected = .8, Protected
tip.BG, tip.GlowTop, tip.ShadowTop = Texture(), Texture(), Texture()
tip.regions = {tip.BG, tip.GlowTop, tip.ShadowTop}
for _, region in ipairs(tip.regions) do
    function region:GetObjectType() return "Texture" end
end
tip.Arrow = { Arrow = NativeTexture(), Glow = Texture() }
tip.CloseButton = { Texture = NativeTexture(), OnClick = Noop }
tip.Arrow.Arrow.rotation = 180
function tip:GetParent() return parent end
function tip:GetRegions() return unpack(self.regions) end
function tip:HookScript(event, callback) self.hooks[event] = callback end
local pool = {}
function pool:GetNextActive(previous) if previous == nil then return tip end end
HelpTip = { Show=Noop, framePool=pool }
local showHook
function hooksecurefunc(target, method, callback)
    Check(target == HelpTip and method == "Show", "unexpected global hook")
    showHook = callback
end
NS.EncounterJournalPanels.Apply(state)
local function Styled()
    Check(tip.BG:GetAlpha() == 0 and tip.GlowTop:GetAlpha() == 0, "tutorial retained native yellow box/glow")
    Check(NS.Registry.GetSurface(tip).fill.shown, "tutorial theme background is absent")
    Check(tip.Text.r == NS.Theme.GetColor("text"), "tutorial text ignores theme")
    Check(tip.Arrow.Arrow:IsDesaturated() and tip.CloseButton.Texture:IsDesaturated(), "tutorial arrow/close remain yellow")
    Check(tip.Arrow.Glow:GetAlpha() == 0 and tip.Arrow.Arrow.rotation == 180, "pointer glow or direction changed")
    Check(tip.CloseButton.OnClick == Noop, "native tutorial close action was replaced")
end
local function Restored()
    Check(tip.BG:GetAlpha() == 1 and tip.GlowTop:GetAlpha() == 1 and tip.Arrow.Glow:GetAlpha() == 1,
        "pooled tutorial did not restore its native art")
    Check(not tip.Arrow.Arrow:IsDesaturated() and not tip.CloseButton.Texture:IsDesaturated(), "pooled tutorial kept tint")
    Check(tip.Text.r == .8 and not NS.Registry.GetSurface(tip).fill.shown, "pooled tutorial kept theme text/surface")
end
Styled()
NS.DB.theme.colors.text = { .7,.8,.9,1 }
NS.EncounterJournalPanels.RefreshTips(state)
Styled()
tip.hooks.OnHide(tip)
Restored()
parent = Target()
tip.hooks.OnShow(tip)
showHook(HelpTip, parent)
Restored()
parent = EncounterJournalJourneysTab
locked = true
showHook(HelpTip, parent)
Styled()
tip.Arrow.Arrow.protected = true
tip.hooks.OnHide(tip)
Check(next(jobs) ~= nil and tip.Arrow.Arrow:IsDesaturated(), "combat cleanup was not safely deferred")
parent = Target()
tip.hooks.OnShow(tip)
local installed = tip.Text.r
NS.DB.theme.colors.text = { .6,.7,.8,1 }
NS.EncounterJournalPanels.RefreshTips(state)
Check(next(jobs) ~= nil and tip.Text.r == installed, "foreign pooled tooltip cancelled pending release or repainted")
tip.Arrow.Arrow.protected, locked = false, false
for key, callback in pairs(jobs) do jobs[key] = nil; callback() end
Restored()
parent = EncounterJournalJourneysTab
visible = false
showHook(HelpTip, parent)
Restored()
visible = true
showHook(HelpTip, parent)
Styled()
state.active = false
NS.EncounterJournalPanels.Reset(state)
Restored()
showHook(HelpTip, parent)
Restored()
print("suite_skin_encounter_helptip_contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@encounter_helptip"))()
