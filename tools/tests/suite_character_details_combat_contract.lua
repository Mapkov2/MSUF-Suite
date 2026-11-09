-- A visible safe dossier reads and paints in combat, without hidden work.
local root = assert(arg[1], "Suite root required")
local file=assert(io.open(root .. "/tools/tests/suite_character_stats_dr_contract.lua","rb"))
local source=file:read("*a"); file:close()
local stop=assert(source:find('details.Apply(characterFrame, "character", "details")',1,true))
local H=assert(loadstring(source:sub(1,stop-1) .. [[
return { NS=NS, Details=details, root=characterFrame, Object=Object,
    Reads=function() return reads end, SetCombat=function(value) combatLocked=value end }
]],"@character_details_combat_fixture"))()
local checks=0
local function Check(value,message) assert(value,message); checks=checks+1 end
InCombatLockdown=function() return false end
local wake
C_Timer={After=function(delay, callback)
    assert(delay==0 and not wake, "unexpected dossier wake-up")
    wake=callback
end}
H.SetCombat(true)
H.Details.Apply(H.root,"character","details")
local view=H.Details.views[H.root]
Check(view and view.panel:IsShown() and H.Reads()==16,"cold combat open lost dossier or item data")
view.host:Hide()
local reads=H.Reads()
H.Details.Refresh(view)
view.host.scripts.OnEvent(view.host,"PLAYER_EQUIPMENT_CHANGED",1)
Check(H.Reads()==reads and not view.registered,"hidden dossier performed item reads or retained events")
view.host:Show()
Check(view.panel:IsShown() and H.Reads()>reads,"combat reopen hid the configured dossier")
reads=H.Reads()
view.host.protected=true
H.Details.Refresh(view)
Check(H.Reads()==reads,"protected dossier entered the painting pass at combat edge")
view.host.protected=nil
function view.host:IsForbidden() return self.forbidden == true end
view.host.forbidden=true
H.Details.Refresh(view)
Check(H.Reads()==reads,"forbidden dossier entered the painting pass")
view.host.forbidden=nil
for _, kind in ipairs({"explicit","forbidden"}) do
    local guarded=H.Object()
    function guarded:IsProtected() return kind=="explicit",kind=="explicit" end
    function guarded:IsForbidden() return kind=="forbidden" end
    H.Details.Apply(guarded,"character","guarded")
    Check(not H.Details.views[guarded],"cold dossier attached to unsafe " .. kind .. " root")
end
H.SetCombat(false)
if wake then wake() end

-- The Suite dock takes only the skin's supplemental dossier. The native
-- character frame, close skin, model, slot scripts and Basic preference survive.
CharacterFrame = H.root
local ownsDossier, restored, closeReleases = false, 0, 0
MSUFSuite = { Suite = { OwnsBlizzardSurface = function(surface) return surface == "characterDossier" and ownsDossier end } }
H.NS.CharacterDetails = H.Details
H.NS.CharacterPanel = {
    owners = { blizzardWindows = { active = true, owner = "details" } },
    Apply = function(owner) H.Details.Apply(H.root, "character", owner) end,
}
H.NS.Adapters = { Refresh = function() error("character dossier handoff rebuilt unrelated windows") end }
H.NS.GearAnnotations.RestoreLayout = function(v)
    if v == view then restored = restored + 1 end
end
H.root.CloseButton = H.Object()
H.NS.WindowActionSkin.Disable = function(frame)
    if frame == H.root.CloseButton then closeReleases = closeReleases + 1 end
end
local function NativeWrite() error("dossier ownership modified a native frame") end
H.root.Show, H.root.Hide, H.root.SetPoint = NativeWrite, NativeWrite, NativeWrite
CharacterModelScene, CharacterMainHandSlot = H.Object(), H.Object()
CharacterModelScene.Show, CharacterModelScene.Hide, CharacterModelScene.SetParent = NativeWrite, NativeWrite, NativeWrite
CharacterMainHandSlot.SetScript, CharacterMainHandSlot.SetParent, CharacterMainHandSlot.Hide = NativeWrite, NativeWrite, NativeWrite
H.NS.DB.characterDetails.view = "list"
H.Details.Apply(H.root, "character", "details")
Check(view.active and view.panel:IsShown() and view.registered, "Basic list did not start with its dossier")

ownsDossier = true
local ownership = H.NS.SuiteOwnership
ownership.Refresh("after")
Check(view.active, "the dossier yielded after the Suite dock started")
ownership.Refresh("before")
Check(not view.active and not view.host:IsShown() and not view.registered and restored > 0,
    "the dossier or its native layout survived the Suite handoff")
Check(H.Details.GetView() == "list" and H.Details.IsModern() and closeReleases == 0,
    "the handoff altered the Basic preference, native stat styling or close skin")

H.SetCombat(true)
ownsDossier = false
local coldRoot, beforeReads = H.Object(), H.Reads()
H.Details.Apply(coldRoot, "character", "details")
Check(not H.Details.views[coldRoot] and H.Reads() == beforeReads, "queued Basic mode created a dossier in combat")
H.SetCombat(false)
ownership.Refresh("before")
Check(not view.active, "Basic took its dossier back before the Suite dock stopped")
ownership.Refresh("after")
Check(view.active and view.panel:IsShown() and view.registered and H.Details.GetView() == "list",
    "returning to Basic did not restore the saved list view")

view.host:Hide()
local beforeClaim = restored
ownsDossier = true
ownership.Refresh("before")
Check(not view.active and restored > beforeClaim, "a hidden Basic dossier retained its layout on takeover")
ownsDossier = false
ownership.Refresh("after")

H.Details.Disable(H.root,"details")
Check(not view.registered and not view.host:IsShown(),"disabled dossier retained work")
Check(closeReleases == 1, "full adapter disable did not release the close skin")
-- Forever keeps the native equipment pane and reads its extra ranged slot.
H.NS.Client.modernEquipment, H.NS.Client.isForever = false, true
H.NS.DB.characterDetails.expanded = true
H.NS.EquipmentInfo.Check = function() error("Retail enchant checks reached Forever") end
C_PaperDollInfo.GetInspectItemLevel = function() error("Retail inspect average reached Forever") end
InspectPaperDollFrame, InspectRangedSlot = H.Object(), H.Object()
local inspect = H.Object({ unit = "target", ModeTabs = H.Object() })
function inspect:GetRight() return 398 end
function inspect.ModeTabs:GetRight() return 462 end
reads = H.Reads()
H.Details.Apply(inspect, "inspect", "details")
local dossier = H.Details.views[inspect]
Check(dossier and dossier.panel:IsShown() and H.Reads() == reads + 17,
    "Forever Inspect did not show the equipment list with its native ranged slot")
Check(dossier.bySlot[18] and not dossier.averageLabel:IsShown() and dossier.sidecarGap == 64,
    "Forever Inspect overlapped its tabs or painted a Retail header")
H.Details.Disable(inspect, "details")
Check(not dossier.host:IsShown() and not dossier.registered, "Forever Inspect retained hidden work")
print("Character dossier combat and Forever: " .. checks .. " checks")
