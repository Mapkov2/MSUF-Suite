local root = assert(arg[1], "repository root required")
local modules = {}
local S = {
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value) return type(value) == "string" and value ~= "secret" and value or nil end,
    Finite = function(value) return type(value) == "number" and value == value end,
    Text = function(value) return value end,
    Install = function(id, module) modules[id] = module end,
    SetFont = function(font) font.styled = true end,
    SetMany = function(id, values)
        for key, value in pairs(values) do modules[id].config[key] = value end
        return true
    end,
}
local combat = false
local NS = { Safety = { IsForbidden = function() return false end }, IsCombatLocked = function() return combat end,
    Dispatch = function(callback, ...) return callback(...) end }
local function Context()
    local context = { events = {} }
    function context:Event(name, callback) self.events[name] = callback end
    function context:RemoveEvent(name) self.events[name] = nil end
    return context
end
local function Frame()
    local f = { shown = false, alpha = 1, mouse = true }
    function f:SetSize(width, height) self.width, self.height = width, height end
    function f:SetFrameStrata() end
    function f:EnableMouse(value) self.mouse = value end
    function f:IsMouseEnabled() return self.mouse end
    function f:IsProtected() return self.protected == true end
    function f:GetAlpha() return self.alpha end
    function f:SetAlpha(value) self.alpha = value end
    function f:SetPoint() end
    function f:SetAllPoints() end
    function f:SetWidth() end
    function f:SetColorTexture() end
    function f:SetJustifyH() end
    function f:SetText(value) assert(self.styled, "text written before font"); self.text = value end
    function f:SetTextColor() end
    function f:Show() self.shown = true; if self.onShow then self.onShow(self) end end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:HookScript(script, callback) assert(script == "OnShow"); self.onShow = callback end
    return f
end
S.CreateFrame = function() return Frame() end
S.CreateTexture = function() return Frame() end
S.CreateFontString = function() return Frame() end
UIParent = Frame()
Enum = { TooltipDataType = { Item = 1 } }
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local clock = Support.Clock()
local reported = {}
S.Dispatch = Support.Dispatcher(reported)
local tooltips = Support.TooltipFixture(root, S, NS)
local function callback(tip, data) tooltips.Run(1, tip, data) end
local tooltip = Frame()
tooltip.shown = true
function tooltip:AddDoubleLine(left, right) self.line = { left, right } end
function tooltip:RefreshDataNextUpdate() error("addon code wrote GameTooltip's update fields") end
GameTooltip = tooltip
C_Item = { GetItemCount = function(id, bank, uses, reagent, account)
    assert(id == 123 and bank and not uses and reagent and account)
    return 7
end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/ItemCounts.lua"))("MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
local counts = modules.itemCounts
counts.context, counts.config, counts.active = Context(), {}, true
counts:Enable()
counts:Refresh()
assert(#tooltips.post[1] == 1 and counts.context.events.ADDON_LOADED == nil, "item tooltip hook did not install")
callback(tooltip, { id = 123 })
assert(tooltip.line[1] == "Owned" and tooltip.line[2] == "7", "owned count was not rendered")
tooltip.line = nil
callback(tooltip, { id = "secret" })
assert(not tooltip.line, "secret item ID reached count lookup")
counts.active = false
counts:Disable()
callback(tooltip, { id = 123 })
assert(not tooltip.line and #reported == 0, "disabled tooltip module still painted")

local inInstance, instanceID, lootSpec = false, 42, 0
IsInInstance = function() return inInstance, inInstance and "party" or "none" end
GetInstanceInfo = function() return nil, "party", nil, nil, nil, nil, nil, instanceID end
GetLootSpecialization = function() return lootSpec end
GetSpecializationInfoByID = function() return nil, "Holy" end
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 256, "Discipline" end,
}
-- Client contract: GetActiveConfigID() is the spec's base config and stays
-- the same across loadout switches; the chosen loadout is
-- GetLastSelectedSavedConfigID(specID) (Blizzard_ClassTalentsFrame.lua:236).
local selectedLoadout, starterBuild = 100, false
C_ClassTalents = {
    GetActiveConfigID = function() return 7 end,
    GetLastSelectedSavedConfigID = function(specID)
        assert(specID == 256, "loadout was read for another specialization")
        return selectedLoadout
    end,
    GetStarterBuildActive = function() return starterBuild end,
}
local configNames = { [7] = "Base", [100] = "Raid", [101] = "Dungeon" }
C_Traits = { GetConfigInfo = function(configID) return { name = configNames[configID] } end }
UnitGUID = function() return "Player-123" end
assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().QoLStyleFixture(root, S)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/LoadoutReminder.lua"))("MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
local reminder = modules.loadoutReminder
reminder.context = Support.ModuleTimers(root, S, NS)("loadoutReminder", reminder, Context())
reminder.config = { onReadyCheck = true, onInstanceEntry = true, onlyMismatch = false,
    duration = 8, expectedConfigID = 0, expectedLootSpecID = 0 }
reminder.active = true
reminder:Enable()
assert(reminder.context.events.READY_CHECK and not reminder.host,
    "reminder did work before its first event")
reminder.context.events.READY_CHECK(reminder)
assert(reminder.host.shown and reminder.title.text == "Current loadout"
    and reminder.detail.text == "Raid  |  Loot: Discipline (current)",
    "ready check did not show public build and loot spec")
reminder.config.expectedConfigID = 200
clock.Advance(5)
reminder.context.events.READY_CHECK(reminder)
assert(reminder.title.text == "Check your loadout", "different build was not highlighted")
clock.Advance(5)
assert(reminder.host.shown, "earlier reminder timer hid a later alert")
assert(reminder:SaveCurrent() and reminder.config.expectedConfigID == 100
    and reminder.config.expectedLootSpecID == 256
    and reminder.config.expectedCharacterGUID == "Player-123", "save-current action lost selection")
reminder.config.onlyMismatch = true
reminder.host:Hide()
reminder.context.events.READY_CHECK(reminder)
assert(not reminder.host.shown, "matching selection ignored warn-only option")
reminder.host:Show()
clock.Advance(10)
assert(reminder.host.shown, "warn-only suppression retained a hide timer")
reminder.host:Hide()
lootSpec = 257
reminder.config.expectedLootSpecID = 256
inInstance = true
reminder.context.events.ZONE_CHANGED_NEW_AREA(reminder)
assert(reminder.host.shown and reminder.title.text == "Check your loadout",
    "instance entry missed changed loot specialization")
reminder.host:Hide()
reminder.context.events.ZONE_CHANGED_NEW_AREA(reminder)
assert(not reminder.host.shown, "zone event repeated one instance reminder")
selectedLoadout = 101
reminder.context.events.SELECTED_LOADOUT_CHANGED(reminder, "SELECTED_LOADOUT_CHANGED")
assert(reminder.host.shown and reminder.title.text == "Check your loadout"
    and reminder.detail.text:find("Dungeon", 1, true),
    "switching loadouts inside an instance did not refresh the reminder")
reminder.host:Hide()
reminder.context.events.PLAYER_TALENT_UPDATE(reminder, "PLAYER_TALENT_UPDATE")
assert(not reminder.host.shown, "unchanged talents repeated the reminder")
selectedLoadout = nil
reminder.context.events.PLAYER_TALENT_UPDATE(reminder, "PLAYER_TALENT_UPDATE")
assert(reminder.host.shown and reminder.detail.text:find("Base", 1, true),
    "a spec without a saved loadout did not fall back to its base config")
reminder.host:Hide()
starterBuild = true
reminder.context.events.PLAYER_TALENT_UPDATE(reminder, "PLAYER_TALENT_UPDATE")
assert(reminder.host.shown and reminder.detail.text:find("Starter build", 1, true),
    "the active starter build was not named")
starterBuild, selectedLoadout = false, 101
reminder.config.onLfgProposal = true
reminder:Refresh()
assert(reminder.context.events.LFG_PROPOSAL_SHOW,
    "dungeon queue reminder did not subscribe")
reminder.host:Hide()
reminder.context.events.LFG_PROPOSAL_SHOW(reminder)
assert(reminder.host.shown and reminder.title.text == "Check your loadout",
    "dungeon queue did not show a mismatched loadout")
reminder.config.onLfgProposal = false
reminder.config.onReadyCheck, reminder.config.onInstanceEntry = false, false
reminder:Refresh()
assert(not reminder.context.events.READY_CHECK and not reminder.context.events.ZONE_CHANGED_NEW_AREA
    and not reminder.context.events.PLAYER_TALENT_UPDATE
    and not reminder.context.events.LFG_PROPOSAL_SHOW,
    "disabled reminder triggers kept listening")
reminder.host:Show()
clock.Advance(10)
assert(reminder.host.shown, "disabled reminder triggers retained an alert timer")
reminder.host:Hide()
reminder.config.onInstanceEntry = true
reminder:Refresh()
assert(reminder.context.events.ZONE_CHANGED_NEW_AREA and reminder.host.shown,
    "re-enabling instance reminders did not check the current instance")
reminder.active = false
reminder:Disable()
assert(not reminder.host.shown, "disabled reminder remained visible")
assert(reminder:ClearSaved() and reminder.config.expectedConfigID == 0
    and reminder.config.expectedLootSpecID == 0 and reminder.config.expectedCharacterGUID == "",
    "clear action retained a character-specific expectation")

TalkingHeadFrame, BossBanner, QuickJoinToastButton = Frame(), Frame(), nil
-- Blizzard's PlayCurrent shows the frame and then starts the voice-over.
local stopped, nextHandle = {}, 40
function TalkingHeadFrame:PlayCurrent()
    self:Show()
    nextHandle = nextHandle + 1
    self.voHandle = nextHandle
end
hooksecurefunc = function(frame, method, callback)
    assert(frame == TalkingHeadFrame and method == "PlayCurrent", "unexpected secure hook " .. tostring(method))
    local original = frame[method]
    frame[method] = function(...)
        original(...)
        callback(...)
    end
end
StopSound = function(handle) stopped[#stopped + 1] = handle end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/QuietPopups.lua"))("MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
local quiet = modules.quietPopups
quiet.context = Context()
quiet.config = { talkingHead = false, bossBanner = true, quickJoin = false }
quiet.active = true
quiet:Enable()
assert(not quiet.context.events.ADDON_LOADED and not quiet.hooked.talkingHead,
    "unused popups retained hooks or an addon-load listener")
assert(not quiet.original.bossBanner and BossBanner.alpha == 1,
    "hidden boss banner was modified before it appeared")
BossBanner:Show()
TalkingHeadFrame:Show()
assert(BossBanner.shown and BossBanner.alpha == 0 and not BossBanner.mouse
    and TalkingHeadFrame.alpha == 1,
    "selective popup muting altered native playback or an unselected frame")
quiet.config.bossBanner = false
quiet:Refresh()
assert(BossBanner.alpha == 1 and BossBanner.mouse,
    "turning off a popup option did not restore native visibility")
quiet.config.bossBanner = true
combat = true
BossBanner.protected = true
BossBanner:Show()
assert(BossBanner.alpha == 1, "protected popup was modified during combat")
BossBanner.protected = false
BossBanner:Show()
assert(BossBanner.alpha == 0, "unprotected boss banner remained visible during combat")
combat = false
quiet.config.bossBanner = false
quiet:Refresh()
assert(BossBanner.alpha == 1, "combat suppression did not restore boss banner")
-- A hidden Talking Head does not keep talking.
TalkingHeadFrame:PlayCurrent()
assert(#stopped == 0, "a shown Talking Head lost its voice-over")
quiet.config.talkingHead = true
quiet:Refresh()
TalkingHeadFrame:PlayCurrent()
assert(TalkingHeadFrame.alpha == 0 and stopped[1] == TalkingHeadFrame.voHandle,
    "a hidden Talking Head kept playing its voice-over")
quiet.config.talkingHead = false
quiet:Refresh()
TalkingHeadFrame:PlayCurrent()
assert(TalkingHeadFrame.alpha == 1 and #stopped == 1, "turning the option off kept the voice-over muted")
quiet.config.quickJoin = true
quiet:Refresh()
assert(quiet.context.events.ADDON_LOADED, "late Quick Join addon was not observed when selected")
QuickJoinToastButton = Frame()
QuickJoinToastButton.Toast, QuickJoinToastButton.Toast2 = Frame(), Frame()
quiet.context.events.ADDON_LOADED(quiet, "ADDON_LOADED", "UnrelatedAddon")
assert(not quiet.hooked.quickJoin, "unrelated addon load triggered Quick Join work")
quiet.context.events.ADDON_LOADED(quiet, "ADDON_LOADED", "Blizzard_QuickJoin")
assert(quiet.hooked.quickJoin and not quiet.context.events.ADDON_LOADED,
    "Quick Join load did not install and release its listener")
QuickJoinToastButton:Show()
assert(QuickJoinToastButton.alpha == 1 and QuickJoinToastButton.mouse
    and QuickJoinToastButton.Toast.alpha == 0 and QuickJoinToastButton.Toast2.alpha == 0,
    "Quick Join toast hid its native friends button or stayed visible")
quiet.active = false
quiet:Disable()
assert(QuickJoinToastButton.Toast.alpha == 1 and QuickJoinToastButton.Toast2.alpha == 1,
    "disabling popup module left native toast muted")
print("QoL additions: tooltip count, loadout reminder, and native popup lifecycle passed")
