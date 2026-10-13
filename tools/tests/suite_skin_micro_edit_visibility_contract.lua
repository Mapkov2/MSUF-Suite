local root = assert(arg[1])
local callbacks, nativeOpen, combat, pending = {}, false, false, nil
EventRegistry = {
    RegisterCallback = function(_, key, callback, owner) callbacks[key] = { callback, owner } end,
    UnregisterCallback = function(_, key) callbacks[key] = nil end,
}
EditModeManagerFrame = { IsEditModeActive = function() return nativeOpen end }
local function Trigger(key)
    local record = assert(callbacks[key], "native edit mode was not observed: " .. key)
    record[1](record[2])
end
local function Frame()
    return {
        shown = true, alpha = 1,
        SetAlpha = function(self, value) self.alpha = value end,
        EnableMouse = function(self, value) self.mouse = value end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        IsMouseOver = function() return false end,
    }
end
local settings = { visibility = "mouseover", loadShowWhenInjured = true }
local bar, gate, menu = Frame(), Frame(), { IsShown = function() return true end }
local owner = { active = true, GetRoot = function() return menu end }
local NS = {
    IsCombatLocked = function() return combat end,
    Safety = { Public = function() return true end, Call = function(object, method, ...)
        if object and object[method] then return object[method](object, ...) end
    end },
    OwnedMicroBarLayout = { Settings = function() return settings end }, MicroMenuLoadConditions = {},
    CombatGate = { RunOrDefer = function(_, callback)
        if combat then pending = callback else callback() end
    end },
}
C_Timer = { NewTimer = function(_, callback)
    return { Cancel = function() end, callback = callback }
end }
C_CurveUtil = { CreateCurve = function() return { SetType = function() end, AddPoint = function() end } end }
Enum = { LuaCurveType = { Step = 1 } }
UnitHealthPercent = function() return .5 end
RegisterStateDriver = function() end
UnregisterStateDriver = function() end
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/OwnedMicroBarVisibility.lua"))("MSUF_Suite_Skin", NS)
local V = NS.OwnedMicroBarVisibility
V.Attach(owner, bar, gate)
V.Apply(settings)
assert(bar.alpha == 0 and gate.alpha == .5)
nativeOpen = true
Trigger("EditMode.Enter")
assert(bar.alpha == 1 and bar.shown and gate.alpha == 1, "native editor left the menu faded")
V.HoverLeave()
assert(bar.alpha == 1, "mouseover hid the menu during editing")
V.SetEditSession(true)
nativeOpen = false
Trigger("EditMode.Exit")
assert(bar.alpha == 1, "native exit hid an ongoing MSUF edit session")
V.SetEditSession(false)
V.Apply(settings)
assert(bar.alpha == 0 and gate.alpha == .5, "normal mouseover/health settings did not return")
V.Reset()
assert(not callbacks["EditMode.Enter"] and not callbacks["EditMode.Exit"], "disable leaked callbacks")
nativeOpen = true
V.Apply(settings)
assert(bar.alpha == 1, "enabling the skin inside an already open editor left it hidden")
combat = true
Trigger("EditMode.Exit")
assert(bar.alpha == 1, "edit exit mutated protected visibility in combat")
combat = false
assert(pending, "combat edit exit has no replay job")
pending()
assert(bar.alpha == 0, "post-combat apply forgot native edit exit")
settings.visibility = "never"
V.Apply(settings)
assert(not bar.shown)
Trigger("EditMode.Enter")
assert(bar.shown and bar.alpha == 1, "never mode hid the edit preview")
Trigger("EditMode.Exit")
assert(not bar.shown, "never mode did not return")
assert(settings.visibility == "never" and settings.loadShowWhenInjured, "editing changed saved choices")
combat = true
Trigger("EditMode.Enter")
owner.active = false
V.Reset()
combat = false
pending()
assert(not bar.shown, "queued edit callback revived a disabled menu")
print("Micro menu native/MSUF edit visibility, overlap, cold enable, reset and combat replay passed")
