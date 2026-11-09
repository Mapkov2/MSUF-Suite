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
H.Details.Disable(H.root,"details")
Check(not view.registered and not view.host:IsShown(),"disabled dossier retained work")
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
