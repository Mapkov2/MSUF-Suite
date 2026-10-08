local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local combat, earlyCombat, queued, hooks, alphaWrites, mouseWrites, poolWalks = false, false, 0, 0, 0, 0, 0
local data, methods = {}, {}
local cleanupFrame
local staleCombat
local function Widget(alpha, click, motion)
    local frame = setmetatable({}, {
        __index = function(self, key) return methods[key] or data[self][key] end,
        __newindex = function(_, key) error("addon wrote native field " .. key) end,
    })
    data[frame] = { alpha = alpha, click = click, motion = motion, hooks = {} }
    return frame
end
function methods:GetAlpha() return data[self].alpha end
function methods:SetAlpha(value) data[self].alpha = value; alphaWrites = alphaWrites + 1 end
function methods:IsMouseClickEnabled() return data[self].click end
function methods:IsMouseMotionEnabled() return data[self].motion end
function methods:EnableMouse(value)
    assert(not combat and not earlyCombat, "protected mouse write during combat")
    data[self].click, data[self].motion = value, value
    mouseWrites = mouseWrites + 1
end
function methods:SetMouseClickEnabled(value)
    assert(not combat and not earlyCombat, "protected mouse write during combat")
    data[self].click = value
    mouseWrites = mouseWrites + 1
end
function methods:SetMouseMotionEnabled(value)
    assert(not combat and not earlyCombat, "protected mouse write during combat")
    data[self].motion = value
    mouseWrites = mouseWrites + 1
end
function methods:GetShownBar() return data[self].shown end
function methods:ApplyPendingBarToShow()
    local d = data[self]
    -- XP OnShow occurs before GetShownBar observes the new assignment.
    d.shown = d.pending
    d.pending = nil
    local callback = d.hooks.ApplyPendingBarToShow
    if callback then callback(self) end
end
function methods:UpdateDividers(count)
    local d = data[self]
    for divider in pairs(d.active) do d.active[divider] = nil end
    for i = 1, count do
        d.dividers[i] = d.dividers[i] or Widget(.6, false, false)
        d.active[d.dividers[i]] = true
    end
    local callback = d.hooks.UpdateDividers
    if callback then callback(self) end
end
hooksecurefunc = function(frame, method, callback)
    assert(not data[frame].hooks[method], "duplicate hook")
    data[frame].hooks[method] = callback
    hooks = hooks + 1
end
local secret = setmetatable({}, { __eq = function() error("secret alpha compared") end,
    __tostring = function() error("secret alpha converted") end })
local function Container(forever)
    local container, xp, rep, tick = Widget(.75), Widget(.8, false, true), Widget(.9, true, true), Widget(.7, true, false)
    data[xp].ExhaustionTick = tick
    data[container].bars = { [4] = xp, [1] = rep }
    data[container].shown = xp
    data[container].BarFrameTexture = Widget(secret)
    if forever then
        local active = {}
        data[container].active, data[container].dividers = active, {}
        data[container].HorizontalDividersPool = { EnumerateActive = function()
            poolWalks = poolWalks + 1
            return next, active, nil
        end }
        container:UpdateDividers(9)
    end
    return container, xp, rep, tick
end
local nativeUpdate = methods.UpdateDividers
local function Load(forever)
    methods.UpdateDividers = forever and nativeUpdate or nil
    local ns = { Client = { isForever = forever }, Text = function(text) return text end,
        AddQoLVisualStyle = function() end }
    assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", ns)
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLifeIndicators.lua"))("MSUF_Suite", ns)
    local defaults = {}
    for key, rule in pairs(ns.SuiteCatalog.xpBar.rules) do defaults[key] = rule.default end
    assert(defaults.hideBlizzard == true, "the Blizzard XP toggle is not default on")
    local rule = ns.SuiteCatalog.xpBar.rules.hideBlizzard
    assert(rule.label == "Hide Blizzard experience bar" and type(rule.default) == "boolean", "missing XP toggle")
    local module = { config = defaults }
    cleanupFrame = nil
    local private = { NS = { IsCombatLocked = function() return combat end,
        InCombat = function(event)
            return combat or earlyCombat or staleCombat and event ~= "PLAYER_REGEN_ENABLED"
        end },
        Suite = { Queue = function(id) assert(id == "xpBar"); queued = queued + 1 end,
            CreateFrame = function()
                local frame = { events = {} }
                function frame:SetScript(_, callback) self.callback = callback end
                function frame:RegisterEvent(event) self.events[event] = true end
                function frame:UnregisterEvent(event) self.events[event] = nil end
                cleanupFrame = frame
                return frame
            end } }
    local main, xp, rep, tick = Container(forever)
    local secondary, xp2, rep2 = Container(forever)
    data[secondary].shown = rep2
    StatusTrackingBarManager = { barContainers = { main, secondary } }
    StatusTrackingBarInfo = { BarsEnum = { Experience = 4 } }
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/NativeExperienceBar.lua"))("MSUF_Suite_QualityOfLife", private)
    return private.NativeExperienceBar, module, main, xp, rep, tick, secondary, xp2, rep2
end
for _, forever in ipairs({ false, true }) do
    hooks, alphaWrites, mouseWrites, poolWalks = 0, 0, 0, 0
    local native, module, main, xp, rep, tick, secondary, xp2, rep2 = Load(forever)
    native.Sync(module, true)
    assert(xp:GetAlpha() == 0 and xp2:GetAlpha() == 0, "both XP children must be hidden")
    assert(main.BarFrameTexture:GetAlpha() == 0, "the XP frame border remained visible")
    assert(secondary.BarFrameTexture:GetAlpha() == secret and rep2:GetAlpha() == .9,
        "the secondary reputation bar was suppressed")
    assert(not xp:IsMouseMotionEnabled() and not tick:IsMouseClickEnabled(), "invisible XP still accepts the mouse")
    assert(main:GetAlpha() == .75 and main:GetShownBar() == xp, "native container selection/fading was changed")
    if forever then
        for divider in pairs(data[main].active) do assert(divider:GetAlpha() == 0, "floating XP divider") end
        main:UpdateDividers(19)
        for divider in pairs(data[main].active) do assert(divider:GetAlpha() == 0, "new keyboard XP divider remained visible") end
        main:UpdateDividers(9)
        for divider in pairs(data[main].active) do assert(divider:GetAlpha() == 0, "layout restored XP dividers") end
    end
    local a, m, p, h = alphaWrites, mouseWrites, poolWalks, hooks
    for _ = 1, 100 do native.Sync(module, true) end
    assert(alphaWrites == a and mouseWrites == m and poolWalks == p and hooks == h,
        "unchanged settings repeat native writes, hooks or divider walks")
    -- Native fades can finish in combat: only alpha sinks follow the swap.
    combat = true
    data[main].pending = rep
    main:ApplyPendingBarToShow()
    assert(main.BarFrameTexture:GetAlpha() == secret and rep:GetAlpha() == .9, "combat swap hid reputation")
    if forever then
        for _, divider in ipairs(data[main].dividers) do assert(divider:GetAlpha() == .6, "divider alpha not restored") end
    end
    data[secondary].pending = xp2
    secondary:ApplyPendingBarToShow()
    assert(secondary.BarFrameTexture:GetAlpha() == 0, "deferred secondary XP swap retained its border")
    module.config.hideBlizzard = false
    native.Sync(module, true)
    assert(queued > 0 and xp:GetAlpha() == 0, "combat lifecycle did not defer")
    combat, earlyCombat = false, true
    local q = queued
    native.Sync(module, true)
    assert(queued == q + 1, "the early combat edge did not defer")
    earlyCombat = false
    native.Sync(module, true)
    assert(xp:GetAlpha() == .8 and xp2:GetAlpha() == .8, "toggle off did not restore XP alpha")
    assert(not xp:IsMouseClickEnabled() and xp:IsMouseMotionEnabled(), "split XP mouse flags not restored")
    assert(tick:IsMouseClickEnabled() and not tick:IsMouseMotionEnabled(), "split rested mouse flags not restored")
    assert(secondary.BarFrameTexture:GetAlpha() == secret, "toggle off did not restore the border snapshot")
    module.config.hideBlizzard = true
    native.Sync(module, true)
    native.Sync(module, false)
    assert(xp:GetAlpha() == .8 and secondary.BarFrameTexture:GetAlpha() == secret, "module disable did not restore")
    a, p = alphaWrites, poolWalks
    data[main].pending = xp
    main:ApplyPendingBarToShow()
    assert(alphaWrites == a and poolWalks == p, "disabled native hooks did work")
    StatusTrackingBarManager = nil
    StatusTrackingBarInfo = nil
    native.Sync(module, true)
    StatusTrackingBarManager = { barContainers = { main, secondary } }
    StatusTrackingBarInfo = { BarsEnum = { Experience = 4 } }
    native.AddonLoaded(module, "ADDON_LOADED", "OtherAddon")
    assert(xp:GetAlpha() == .8, "unrelated addon load suppressed XP")
    native.AddonLoaded(module, "ADDON_LOADED", forever and "Blizzard_StatusTrackingBar" or "Blizzard_ActionBar")
    assert(xp:GetAlpha() == 0, "late native addon was not adopted")
    -- Stop/Fail releases the module context in combat; restoration cannot
    -- depend on the controller calling an inactive module's Disable again.
    combat = true
    native.Sync(module, false)
    assert(cleanupFrame and cleanupFrame.events.PLAYER_REGEN_ENABLED, "combat disable has no cleanup event")
    -- The native lockdown is over before PLAYER_REGEN_ENABLED is delivered.
    combat, earlyCombat, staleCombat = false, false, true
    cleanupFrame.callback(cleanupFrame, "PLAYER_REGEN_ENABLED")
    staleCombat = false
    assert(xp:GetAlpha() == .8 and not cleanupFrame.events.PLAYER_REGEN_ENABLED,
        "combat disable stranded native state or retained an idle listener")
    native.Sync(module, true)
    combat = true
    native.Sync(module, false)
    combat = false
    native.Sync(module, true)
    cleanupFrame.callback()
    assert(xp:GetAlpha() == 0 and not cleanupFrame.events.PLAYER_REGEN_ENABLED,
        "an old cleanup undid a later valid enable")
    native.Sync(module, false)
end
print("suite_xp_native_contract: OK (Retail/Forever, combat swaps, restore, bounded native work)")
