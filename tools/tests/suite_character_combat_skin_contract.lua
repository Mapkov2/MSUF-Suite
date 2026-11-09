-- Native background resets must repaint cosmetics without rebuilding Character layout.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_forever_character_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(ns.CharacterPanel.Apply("blizzardWindows"))', 1, true))
SetPaperDollBackground = function() end
local H = assert(loadstring(source:sub(1, stop - 1) .. [[
return { NS = ns, hooks = hooks, backgrounds = modelBackgrounds, Texture = Texture,
    SetCombat = function(value) combatLocked = value end, reported = reported }
]], "@character_combat_fixture"))()
local NS = H.NS
-- Native securecallfunction has no Lua results-table allocation (the shared
-- fixture collects errors in a table; exclude that instrumentation here).
NS.Safety.Dispatch = function(callback, ...) return callback(...) end
NS.Client.isForever = arg[2] == "Forever"
NS.DB.theme.look = NS.Client.isForever and "foreverGlass" or "default"
if not NS.Client.isForever then
    local tabs = CharacterFrame.ModeTabs.Tabs
    CharacterFrameTab1, CharacterFrameTab2, CharacterFrameTab3 = tabs[1], tabs[2], tabs[3]
    NS.ControlSkin.ApplyPanelTab = NS.ControlSkin.ApplyButton
    PanelTemplates_GetSelectedTab = function() return 2 end
end
InCombatLockdown = function() return false end -- event edge before native lockdown flips
local writes, layout, queued, checks = 0, 0, 0, 0
local continuation
local function Check(value, message) assert(value, message); checks = checks + 1 end
for _, texture in ipairs(H.backgrounds) do
    texture.alpha = 1
    function texture:GetAlpha() return self.alpha end
    function texture:SetVertexColor(r, g, b, a)
        writes = writes + 1
        self.vertex[1], self.vertex[2], self.vertex[3], self.vertex[4] = r, g, b, a
    end
end
CharacterModelFrameBackgroundOverlay = H.Texture()
local overlay = CharacterModelFrameBackgroundOverlay
overlay.alpha = 1
function overlay:GetAlpha() return self.alpha end
function overlay:SetAlpha(alpha) writes = writes + 1; self.alpha = alpha end
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Cosmetics.lua"))("MSUF_Suite_Skin", NS)
-- Drive the public Character adapter, not only its individual painters.
local pending, detailCalls = {}, 0
local detailsApply, eqolApply = NS.CharacterDetails.Apply, NS.EQoLCharacter.Apply
NS.CharacterDetails.Apply = function(...) detailCalls = detailCalls + 1; return detailsApply(...) end
NS.EQoLCharacter.Apply = function(...) assert(not NS.IsCombatLocked(), "cold combat entered EQoL structure"); return eqolApply(...) end
NS.CombatGate.RunOrDefer = function(key, callback) pending[key] = callback end
H.SetCombat(true)
Check(NS.CharacterPanel.Apply("combat-cold") == true and detailCalls == 1 and overlay.alpha == 0,
    "public Character first combat apply lost dossier or cosmetic styling")
local jobs = 0
for _ in pairs(pending) do jobs = jobs + 1 end
Check(jobs == 1, "cold Character apply did not coalesce its post-combat completion")
H.SetCombat(false)
NS.CharacterPanel.Disable("combat-cold")
NS.Cosmetics.RestoreOwner("combat-cold") -- the parent GenericWindows owner normally releases this
NS.CharacterDetails.Apply, NS.EQoLCharacter.Apply = detailsApply, eqolApply
NS.CombatGate.RunOrDefer = function(_, callback) queued = queued + 1; continuation = callback end
assert(NS.CharacterPanel.Apply("blizzardWindows"))
if not NS.Client.isForever then
    Check(CharacterFrameTab1.surface.active == false and CharacterFrameTab2.surface.active == true,
        "the Retail tabs did not show the native selection")
end
local hook = assert(H.hooks.SetPaperDollBackground, "native background hook missing")
local attach = NS.Surface.Ensure
NS.Surface.Ensure = function(...) layout = layout + 1; return attach(...) end
NS.Surface.Attach = NS.Surface.Ensure
H.SetCombat(true)
local function ResetAndOpen()
    overlay.alpha = 1
    for _, texture in ipairs(H.backgrounds) do
        texture.alpha = 1
        texture.vertex[1], texture.vertex[2], texture.vertex[3] = 1, 1, 1
    end
    hook(CharacterModelScene)
end
ResetAndOpen()
Check(overlay.alpha == 0, "native Character overlay returned during combat")
Check(NS.Client.isForever and H.backgrounds[1].vertex[1] == 0.36
    or not NS.Client.isForever and H.backgrounds[1].alpha == 0,
    "Character race background lost its configured skin during combat")
Check(layout == 0 and queued == 0, "cosmetic reset rebuilt layout or queued combat work")
collectgarbage("collect"); collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 1000 do ResetAndOpen() end
local growth = collectgarbage("count") - before
collectgarbage("restart")
Check(growth < 2, "warm Character reset allocated: " .. growth .. " KiB")
Check(layout == 0 and queued == 0, "warm Character reset scheduled structural work")
function overlay:IsProtected() return true, false end
overlay.alpha = 1
hook(CharacterModelScene)
Check(overlay.alpha == 1, "combat edge wrote implicitly protected artwork")
overlay.IsProtected = nil
function overlay:IsForbidden() return true end
overlay.alpha = 1
hook(CharacterModelScene)
Check(overlay.alpha == 1, "combat refresh wrote forbidden artwork")
overlay.IsForbidden = nil
if NS.Client.isForever then
    local tabs, points = CharacterFrame.ModeTabs, 0
    local place = tabs.SetPoint
    function tabs:SetPoint(...) points = points + 1; return place(self, ...) end
    function tabs:IsProtected() return true, false end
    H.hooks.UpdateTabLayout()
    Check(points == 0, "cached Forever tabs bypassed combat descendant protection")
    tabs.IsProtected, tabs.SetPoint = nil, place
end
local state = NS.CharacterPanel.owners.blizzardWindows
local nested = { TopEdge = overlay }
function overlay:IsProtected() return true, false end
overlay.alpha = 1
NS.AdapterKit.FadeNineSlice(state, nested)
Check(overlay.alpha == 1, "nested NineSlice piece bypassed combat protection")
overlay.IsProtected = nil
NS.AdapterKit.FadeNineSlice(state, nested)
Check(overlay.alpha == 0, "safe NineSlice piece was skipped")
local textWrites = 0
local protectedText = { IsProtected = function() return true, false end,
    SetTextColor = function() textWrites = textWrites + 1 end }
NS.AdapterKit.SetTextColor(NS.AdapterKit.NewTextColors(), protectedText, "text")
Check(textWrites == 0, "named text target bypassed combat protection")
state.active = false
local prior = writes
hook(CharacterModelScene)
Check(writes == prior, "inactive Character owner repainted")
state.active = true
hook({})
Check(writes == prior, "unrelated model reset repainted Character")
if NS.Client.isForever then
    local backdrop = H.backgrounds[1]
    local beforeColor = backdrop.vertex[1]
    function backdrop:IsProtected() return true, false end
    NS.DB.theme.look = "default"
    hook(CharacterModelScene)
    Check(backdrop.vertex[1] == beforeColor and continuation ~= nil,
        "look transition restored protected model color during combat")
    H.SetCombat(false)
    continuation()
    Check(backdrop.vertex[1] == 1, "look transition lost original model color after combat")
    backdrop.IsProtected = nil
    NS.DB.theme.look = "foreverGlass"
    hook(CharacterModelScene)
    H.SetCombat(true)
    NS.DB.theme.look = "default"
    hook(CharacterModelScene)
    NS.DB.theme.look = "foreverGlass"
    hook(CharacterModelScene)
    H.SetCombat(false)
    continuation()
    Check(backdrop.vertex[1] == 0.36, "stale combat completion removed the current model tint")
end
Check(#H.reported == 0, "Character callback reported a Lua error")
print(("Character combat skin: %d checks, %.3f KiB/1000 native resets (%s)"):format(checks, growth, arg[2]))
