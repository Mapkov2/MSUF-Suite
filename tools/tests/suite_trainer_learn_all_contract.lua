-- Focused offline contract for the user-confirmed trainer batch. It does not
-- claim that a live client permits follow-up purchase calls from TRAINER_UPDATE.
local root = (...)
assert(root, "pass the Suite root")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local reported = {}

local services = {
    { "Alchemy", "available", 1, 1, 100, true },
    { "Profession rank", "available", 2, 1, 50, false },
    { "Ability A", "available", 3, 1, 300, false },
    { "Ability B", "available", 4, 1, 200, false },
    { "Future ability", "unavailable", 5, 1, 0, false },
}
local gold, combat = 1000, false
local buys, messages, events = {}, {}, {}
local popup

local function Frame(shown)
    local frame = { shown = shown == true, scripts = {}, hooks = {} }
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:SetFrameLevel() end
    function frame:GetFrameLevel() return 1 end
    function frame:SetText(value) self.text = value end
    function frame:SetEnabled(value) self.enabled = value end
    function frame:SetScript(kind, fn) self.scripts[kind] = fn end
    function frame:HookScript(kind, fn) self.hooks[kind] = fn end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    return frame
end

ClassTrainerFrame = Frame(true)
ClassTrainerTrainButton = Frame(true)
GameTooltip = { SetOwner = function() end, SetText = function() end,
    AddLine = function() end, Show = function() end }
GameTooltip_Hide = function() end
StaticPopupDialogs = {}
StaticPopup_Show = function(name, count, cost, data)
    popup = { name = name, count = count, cost = cost, data = data }
end
StaticPopup_Hide = function() popup = nil end
-- The deprecated GetCoinTextureString global exists only with the
-- loadDeprecationFallbacks CVar; this client runs without it.
C_CurrencyInfo = { GetCoinTextureString = function(value) return tostring(value) .. "c" end }
GetMoney = function() return gold end
GetNumTrainerServices = function() return #services end
GetTrainerServiceStepIndex = function() return 2 end
GetTrainerServiceInfo = function(index)
    local item = services[index]
    return item[1], item[2], item[3], item[4]
end
GetTrainerServiceCost = function(index)
    local item = services[index]
    return item[5], item[6]
end
BuyTrainerService = function(index) buys[#buys + 1] = index end
C_Timer = { After = function(_, fn) fn() end }

local context = {}
function context:Event(event, fn) events[event] = fn end
function context:RemoveEvent(event) events[event] = nil end
local installed
local suite = {
    Install = function(_, module)
        installed = module
        module.context, module.active = context, true
    end,
    Public = function(value) return value ~= "SECRET" end,
    PublicText = function(value)
        return type(value) == "string" and value ~= "" and value ~= "SECRET" and value or nil
    end,
    Finite = function(value)
        return type(value) == "number" and value == value
            and value > -math.huge and value < math.huge
    end,
    Text = function(value) return value end,
    BlizzardText = function(_, fallback) return fallback end,
    CreateFrame = function() return Frame(false) end,
    Dispatch = Support.Dispatcher(reported),
}
local ns = {
    IsCombatLocked = function() return combat end,
    Safety = { IsForbidden = function() return false end },
    Print = function(value) messages[#messages + 1] = value end,
    Finish = function(callback, ...) return true, callback(...) end,
    Dispatch = suite.Dispatch,
}
Support.ModuleTimers(root, suite, ns)("trainerLearnAll", nil, context)
local chunk = assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TrainerLearnAll.lua"))
chunk("MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local module = assert(installed)
suite.instances.trainerLearnAll = module
local function Emit(event, ...)
    assert(events[event], "missing event " .. event)(module, event, ...)
end
local function Click()
    assert(module.button and module.button.scripts.OnClick)
    module.button.scripts.OnClick(module.button)
end

module:Enable()
assert(module.button:IsShown() and module.button.enabled, "visible opt-in button")
Click()
assert(popup and popup.count == 2 and popup.cost == "500c" and #buys == 0,
    "confirm exactly the two non-profession abilities and total cost")
StaticPopupDialogs[popup.name].OnAccept(nil, popup.data)
assert(#buys == 1 and buys[1] == 3, "first service requested after confirmation")
services[3][2] = "used"
gold = gold - 300
Emit("TRAINER_UPDATE")
assert(#buys == 2 and buys[2] == 4, "next purchase waits for trainer update")
services[4][2] = "used"
gold = gold - 200
services[5][2] = "available"
Emit("TRAINER_UPDATE")
assert(#buys == 2 and module.queue == nil,
    "newly unlocked service was never included in the reviewed batch")

services[3][2], services[4][2], services[5][2], gold = "available", "available", "unavailable", 1000
module:UpdateButton()
Click()
assert(popup and popup.count == 2, "new batch can be previewed")
services[4][5] = 250
StaticPopupDialogs[popup.name].OnAccept(nil, popup.data)
assert(#buys == 2 and module.queue == nil, "cost change invalidates confirmation")
services[4][5] = 200

services[4][1], services[4][3], services[4][5] = "Ability A", 3, 300
module:UpdateButton()
assert(not module.button.enabled, "ambiguous trainer services cannot be batch purchased")
services[4][1], services[4][3], services[4][5] = "Ability B", 4, 200
gold = 400
module:UpdateButton()
assert(not module.button.enabled, "batch is disabled when total cost exceeds gold")
gold = 1000
module:UpdateButton()
Click()
StaticPopupDialogs[popup.name].OnAccept(nil, popup.data)
assert(#buys == 3 and module.queue, "third batch started")
combat = true
Emit("PLAYER_REGEN_DISABLED")
assert(module.queue == nil and not module.button:IsShown(), "combat stops purchases")
combat = false
module:UpdateButton()
module:Disable()
assert(not module.button:IsShown(), "disable hides the helper")

-- Some trainer implementations send TRAINER_UPDATE during BuyTrainerService.
-- Follow-up work must wait until that call has returned.
services[3][2], services[4][2], services[5][2], gold = "available", "available", "unavailable", 1000
BuyTrainerService = function(index)
    buys[#buys + 1] = index
    gold = gold - services[index][5]
    services[index][2] = "used"
    Emit("TRAINER_UPDATE")
end
module:Enable()
module:UpdateButton()
Click()
local before = #buys
StaticPopupDialogs[popup.name].OnAccept(nil, popup.data)
assert(#buys == before + 2 and module.queue == nil,
    "synchronous trainer updates are deferred until each purchase returns")

services[3][2], services[4][2], gold = "available", "available", 1000
BuyTrainerService = function()
    Emit("TRAINER_UPDATE")
    error("client rejected purchase")
end
module:UpdateButton()
Click()
local beforeFailure = #buys
StaticPopupDialogs[popup.name].OnAccept(nil, popup.data)
assert(module.queue == nil and module.purchasing == nil and module.deferred == nil
    and #buys == beforeFailure,
    "rejected purchase clears even a synchronous deferred update without retrying")
assert(#reported == 1 and reported[1]:find("client rejected purchase", 1, true)
    and messages[#messages] == "Training stopped because the purchase call failed.",
    "a raising purchase call was swallowed instead of reported")
Emit("TRAINER_UPDATE")
assert(#buys == beforeFailure, "later updates cannot restart a failed purchase")
print("Suite trainer learn-all confirmation and update lifecycle passed")
