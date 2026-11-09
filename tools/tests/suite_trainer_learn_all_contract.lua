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

local function Frame(shown)
    local frame = { shown = shown == true, scripts = {}, hooks = {} }
    function frame:SetSize() end
    function frame:SetJustifyH() end
    function frame:SetMaxLines() end
    function frame:CreateFontString(_, _, template)
        assert(template == "GameFontHighlightSmall")
        return Frame(false)
    end
    function frame:SetPoint() end
    function frame:SetFrameLevel() end
    function frame:GetFrameLevel() return 1 end
    function frame:SetText(value) self.text = value self.textWrites = (self.textWrites or 0) + 1 end
    function frame:SetEnabled(value) self.enabled = value end
    function frame:SetScript(kind, fn) self.scripts[kind] = fn end
    function frame:SetParent(value) self.parent = value end
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
local dialogs = Support.StaticPopups()
local function Question() return dialogs.Last("GENERIC_CONFIRMATION") end
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
    -- Parented after creation (SmartNavigation's CreateFrame post-hook).
    CreateFrame = function(_, _, parent)
        assert(parent == nil, "the trainer button was created with a parent inside Blizzard's trainer window")
        return Frame(false)
    end,
    Dispatch = Support.Dispatcher(reported),
}
local ns = {
    Client = { isForever = false },
    IsCombatLocked = function() return combat end,
    Safety = { IsForbidden = function() return false end },
    Print = function(value) messages[#messages + 1] = value end,
    Finish = function(callback, ...) return true, callback(...) end,
    Dispatch = suite.Dispatch,
}
Support.ModuleTimers(root, suite, ns)("trainerLearnAll", nil, context)
-- The Suite's questions (S.Confirm) live in MSUF_Suite_Modules/Dialogs.lua.
assert(loadfile(root .. "/MSUF_Suite_Modules/Dialogs.lua"))("MSUF_Suite_Modules", { Suite = suite })
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
assert(Question() and Question().text
    == "Learn 2 available abilities for 500c? Profession choices and rank steps are excluded."
    and Question().acceptText == "Accept" and Question().alert and #buys == 0,
    "confirm exactly the two non-profession abilities and total cost")
dialogs.Accept(Question())
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
assert(Question() and Question().data.text_arg1 == 2, "new batch can be previewed")
services[4][5] = 250
dialogs.Accept(Question())
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
dialogs.Accept(Question())
assert(#buys == 3 and module.queue, "third batch started")
-- The client sends PLAYER_REGEN_DISABLED while InCombatLockdown() is still
-- false; the lockdown turns on after it.
Emit("PLAYER_REGEN_DISABLED")
combat = true
assert(module.queue == nil and not module.button:IsShown(), "combat stops purchases and hides the button")
combat = false
Emit("PLAYER_REGEN_ENABLED")
assert(module.button:IsShown() and not events.PLAYER_REGEN_ENABLED, "the button did not come back after combat")
module:UpdateButton()
Click()
assert(Question(), "the batch was not offered again after combat")
module:Disable()
assert(not module.button:IsShown() and not Question(), "disable hides the helper and its question")

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
dialogs.Accept(Question())
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
dialogs.Accept(Question())
assert(module.queue == nil and module.purchasing == nil and module.deferred == nil
    and #buys == beforeFailure,
    "rejected purchase clears even a synchronous deferred update without retrying")
assert(#reported == 1 and reported[1]:find("client rejected purchase", 1, true)
    and messages[#messages] == "Training stopped because the purchase call failed.",
    "a raising purchase call was swallowed instead of reported")
Emit("TRAINER_UPDATE")
assert(#buys == beforeFailure, "later updates cannot restart a failed purchase")
assert(module.button.parent == ClassTrainerFrame, "the trainer button did not join the trainer window")
-- The same opt-in uses a read-only budget on Forever.
module:Disable()
local trainerFrame = ClassTrainerFrame
ClassTrainerFrame = nil
ns.Client.isForever = true
local trainerType, serviceReads = 0, 0
Enum = { TrainerType = { Pet = 2 } }
C_Trainer = { GetTrainerType = function() return trainerType end }
local originalInfo = GetTrainerServiceInfo
GetTrainerServiceInfo = function(index)
    serviceReads = serviceReads + 1
    return originalInfo(index)
end
services[3][2], services[4][2], services[5][2] = "available", "available", "unavailable"
services[6] = { "Free ability", "available", 6, 1, 0, false }
gold = 400
local pending = {}
C_Timer.After = function(_, callback) pending[#pending + 1] = callback end
local function Flush()
    local timers = pending
    pending = {}
    for i = 1, #timers do timers[i]() end
end
local secrets, stopWatch, secretCost
if arg[2] then
    secrets = assert(loadfile(arg[2]))()
    secrets.Install()
    secrets.GUARD_NAMES.falsy.Public = true
    secrets.GUARD_NAMES.falsy.Finite = true
    secrets.GUARD_NAMES.falsy.PublicText = true
    secretCost = secrets.New("number")
    stopWatch = secrets.Watch(root .. "/MSUF_Suite_QualityOfLife/TrainerLearnAll.lua", { strict = true })
    local public, finite, publicText = suite.Public, suite.Finite, suite.PublicText
    suite.Public = function(value) return not secrets.IsSecret(value) and public(value) end
    suite.Finite = function(value) return not secrets.IsSecret(value) and finite(value) end
    suite.PublicText = function(value) return not secrets.IsSecret(value) and publicText(value) end
else
    secretCost = "SECRET"
end
BuyTrainerService = function() error("Forever tried to buy training") end
events = {}
chunk("MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
module = assert(installed)
suite.instances.trainerLearnAll = module
module:Enable()
assert(not module.budget and not events.PLAYER_MONEY, "closed trainer did budget work")
ClassTrainerFrame = trainerFrame
ClassTrainerFrame:Show()
Emit("ADDON_LOADED", "Blizzard_TrainerUI")
Emit("TRAINER_UPDATE")
Flush()
local budget = assert(module.budget)
assert(budget:IsShown() and budget.text == "2 paid · 500c\n100c short" and not module.button and not Question(),
    "budget totals only the visible available paid abilities")
assert(serviceReads == #services - 1, "opening and trainer update did not coalesce")
local reads, writes = serviceReads, budget.textWrites
Emit("PLAYER_MONEY")
assert(serviceReads == reads and budget.textWrites == writes, "unchanged funds reread services or rewrote text")
gold = 501
Emit("PLAYER_MONEY")
assert(budget.text == "2 paid · 500c" and serviceReads == reads, "balance update rescanned or kept outdated shortfall")
services[4][2] = "used"
Emit("TRAINER_UPDATE")
Flush()
assert(budget.text == "1 paid · 300c", "changed trainer list kept stale costs")
services[3][5] = secretCost
Emit("TRAINER_UPDATE")
Flush()
assert(not budget:IsShown(), "unreadable costs must hide the total")
services[3][5] = 300
trainerType = Enum.TrainerType.Pet
Emit("TRAINER_UPDATE")
Flush()
assert(not budget:IsShown(), "pet points treated as copper")
trainerType = 0
Emit("TRAINER_UPDATE")
Flush()
assert(budget:IsShown(), "changed trainer type did not restore budget")
Emit("PLAYER_REGEN_DISABLED")
assert(not budget:IsShown() and not events.PLAYER_MONEY, "combat edge did not suspend trainer updates")
Emit("PLAYER_REGEN_ENABLED")
Flush()
assert(budget:IsShown() and events.PLAYER_MONEY, "open trainer did not resume")
Emit("TRAINER_CLOSED")
assert(not budget:IsShown() and not events.PLAYER_MONEY and not events.TRAINER_UPDATE, "trainer close left live work")
ClassTrainerFrame.hooks.OnShow(ClassTrainerFrame)
Flush()
assert(budget:IsShown(), "reopened trainer did not update")
module:Disable()
assert(not budget:IsShown() and not events.PLAYER_MONEY, "disabling left the budget active")
assert(#reported == 1, table.concat(reported, "\n"))
if stopWatch then
    local violations = stopWatch()
    assert(#violations == 0, table.concat(violations, "\n"))
end
print("Suite trainer Retail confirmation and Forever read-only budget lifecycle passed")
