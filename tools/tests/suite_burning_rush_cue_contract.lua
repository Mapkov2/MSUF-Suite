-- Native active-aura cue contract. Live visual, combat and taint behavior
-- still require a Retail client check.
local root = assert(arg[1], "repository root required")
local events, nativeCount, slotCount, moverCount = {}, 0, 0, 0
local installed, combat, playerClass = nil, false, "WARLOCK"
local driverCount, undriverCount, queued = 0, 0, 0
local driver

local function Region()
    local region = { shown = true }
    function region:SetSize(w, h) self.width, self.height = w, h end
    function region:SetFrameStrata(value) self.strata = value end
    function region:EnableMouse() end
    function region:SetMouseClickEnabled() end
    function region:SetAllPoints() end
    function region:SetPoint(...) self.point = { ... } end
    function region:ClearAllPoints() self.point = nil end
    function region:SetScale(value) self.scale = value end
    function region:SetColorTexture() end
    function region:SetWidth() end
    function region:SetJustifyH() end
    function region:SetTextColor() end
    function region:SetText(value) self.text = value end
    function region:SetTexture(value)
        assert(not self.bound, "bound native icon was mutated after handoff")
        self.texture = value
    end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:SetShown(value) self.shown = value end
    function region:IsShown() return self.shown end
    function region:CreateTexture() return Region() end
    function region:CreateFontString() return Region() end
    return region
end

UIParent = Region()
UnitClassBase = function(unit) assert(unit == "player"); return playerClass end
C_UnitAuras = setmetatable({}, { __index = function() error("Suite must not inspect combat aura data") end })
C_Timer = setmetatable({}, { __index = function() error("cue must not poll") end })
RegisterStateDriver = function(frame, state, condition)
    assert(frame == installed.container and state == "visibility"
        and condition == "[combat] show; hide", "native slot needs a secure combat visibility driver")
    assert(not driver, "visibility driver was registered twice")
    driver, driverCount = frame, driverCount + 1
    frame:SetShown(combat)
end
UnregisterStateDriver = function(frame, state)
    assert(frame == driver and state == "visibility")
    driver, undriverCount = nil, undriverCount + 1
end
local function SecureDriverUpdate()
    assert(driver, "native visibility driver was not active")
    driver:SetShown(combat)
end

CreateFrame = function(kind, name, parent, template)
    assert(kind == "AuraContainer" and name == nil and parent and template == "CustomAuraContainerTemplate",
        "native aura template or parent changed")
    nativeCount = nativeCount + 1
    local container = Region()
    function container:SetUnit(unit) self.unit = unit end
    function container:SetEnabled(value) self.enabled = value end
    function container:AddAuraSlot(key, filter, options)
        slotCount = slotCount + 1
        assert(key == "burningRush" and filter == "HELPFUL", "cue must use one helpful native slot")
        local ids = options.candidateFilters and options.candidateFilters.includeSpellIDs
        assert(ids and ids[111400] == true and next(ids, 111400) == nil,
            "native slot must select only Burning Rush")
        assert(type(options.initializeFrame) == "function", "native initializer is required")
        self.button = Region()
        self.button.shown = false -- Blizzard owns this state from aura presence.
        function self.button:SetIcon(icon)
            assert(icon.texture == nil, "native icon must be handed off unbound")
            self.icon = icon
            icon.bound = true
        end
        options.initializeFrame(self.button)
        assert(self.button.icon and self.button.width == 216 and self.button.height == 46,
            "native button was not fully built before handoff")
        return self.button
    end
    return container
end

local context = {}
function context:Event(name, callback, allowCombat)
    assert(name ~= "UNIT_AURA" and dofile(root .. "/tools/tests/suite_test_support.lua").InCombatOption(allowCombat), "Lua aura listener or blocked combat event")
    events[name] = callback
end
function context:RemoveEvent(name) events[name] = nil end

local config = { point = 5, x = 0, y = 150, scale = 100 }
local suite = {
    Install = function(id, module)
        assert(id == "burningRushCue")
        installed = module
        module.active, module.context, module.config = true, context, config
    end,
    CreateFrame = function(kind, name, parent)
        assert(kind == "Frame" and name == nil and parent)
        return Region()
    end,
    SetFont = function() end,
    Text = function(value) return value end,
    PublicText = function(value) return type(value) == "string" and value or nil end,
    RegisterOwnedMover = function(id, element, options)
        assert(id == "burningRushCue" and element == "combat"
            and options.getFrame() == installed.host)
        moverCount = moverCount + 1
    end,
    Config = function() return config end,
    Set = function(_, key, value) config[key] = value end,
    Queue = function(id) assert(id == "burningRushCue"); queued = queued + 1 end,
}
local ns = {
    Client = { isForever = false },
    IsCombatLocked = function() return combat end,
    AnchorPoints = { [5] = "CENTER" },
}

assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().QoLStyleFixture(root, suite)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/BurningRushCue.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local cue = assert(installed)

ns.Client.isForever = true
cue:Enable()
assert(nativeCount == 0 and not cue.host, "Forever must not create the Retail cue")
ns.Client.isForever, playerClass = false, "MAGE"
cue:Enable()
assert(nativeCount == 0 and not cue.host, "non-Warlock must not create the cue")
playerClass = "WARLOCK"
cue:Enable()
assert(nativeCount == 1 and slotCount == 1 and moverCount == 1
    and cue.container.unit == "player" and cue.container.enabled == true
    and driver == cue.container and driverCount == 1,
    "Warlock must bind exactly one native player aura slot")
assert(events.PLAYER_ENTERING_WORLD and events.PLAYER_REGEN_DISABLED
    and events.PLAYER_REGEN_ENABLED and not events.UNIT_AURA,
    "only public combat/world events should be routed through Suite")
assert(cue.host:IsShown() and not cue.container:IsShown()
    and not cue.preview:IsShown() and not cue.container.button:IsShown(),
    "idle and absent aura stay visually silent through native visibility")

combat = true
SecureDriverUpdate()
events.PLAYER_REGEN_DISABLED(cue)
assert(cue.host:IsShown() and cue.container:IsShown() and not cue.preview:IsShown(),
    "secure driver exposes the native aura slot without a Suite aura read")
combat = false
SecureDriverUpdate()
events.PLAYER_REGEN_ENABLED(cue)
assert(cue.host:IsShown() and not cue.container:IsShown(),
    "secure driver must hide the native cue outside combat")

suite.editMode = true
cue:Refresh()
assert(cue.host:IsShown() and cue.preview:IsShown() and not cue.container:IsShown()
    and cue.container.enabled == false,
    "Edit Mode must show an inert sample and pause native aura tracking")
combat = true
SecureDriverUpdate()
events.PLAYER_REGEN_DISABLED(cue)
assert(not cue.preview:IsShown() and cue.container.enabled == false,
    "combat hides an Edit Mode sample without native reconfiguration")
combat = false
SecureDriverUpdate()
events.PLAYER_REGEN_ENABLED(cue)
assert(cue.preview:IsShown() and cue.container.enabled == false,
    "Edit Mode sample returns after combat if the session remains active")
suite.editMode = false
cue:Refresh()
assert(cue.host:IsShown() and not cue.preview:IsShown() and not cue.container:IsShown()
    and cue.container.enabled == true,
    "leaving Edit Mode must restore the native slot")

config.x, config.y, config.scale = 17, 31, 125
cue:Refresh()
assert(cue.host.scale == 1.25 and cue.host.point[4] == 17 and cue.host.point[5] == 31,
    "saved position and scale must reach the owner frame")
cue:Disable()
assert(not cue.host:IsShown() and not events.PLAYER_ENTERING_WORLD
    and not events.PLAYER_REGEN_DISABLED and not events.PLAYER_REGEN_ENABLED
    and cue.container.enabled == false and not driver and undriverCount == 1,
    "disable must stop native tracking, visibility driver and Suite listeners")
cue:Enable()
assert(nativeCount == 1 and slotCount == 1 and cue.container.enabled == true
    and driver == cue.container and driverCount == 2,
    "reenable must reuse and reactivate the native slot")

-- Settings/Edit Mode changes that arrive during combat may not reconfigure
-- the native container. The Suite controller flushes the queued apply later.
combat = true
SecureDriverUpdate()
suite.editMode = true
local before = queued
cue:Refresh()
assert(queued == before + 1 and cue.container.enabled == true
    and not cue.preview:IsShown(), "combat Edit Mode change must be deferred")
-- The controller never stops a module in lockdown (S.Apply queues it).
events.PLAYER_REGEN_DISABLED(cue)
assert(not cue.preview:IsShown() and queued == before + 2 and driver == cue.container,
    "combat event must never reconfigure native aura state")
combat = false
SecureDriverUpdate()
cue:Refresh()
assert(cue.container.enabled == false and cue.preview:IsShown(),
    "deferred Edit Mode state must apply out of combat")
cue:Disable()
assert(cue.container.enabled == false and not driver,
    "final disable must stop the native container")

print("Suite Burning Rush native combat cue lifecycle passed")
