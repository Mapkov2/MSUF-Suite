local root = assert(arg[1])
local function Upvalue(fn, key)
    for index = 1, 60 do
        local name, value = debug.getupvalue(fn, index)
        if name == key then return value end
        if not name then break end
    end
    error("missing " .. key)
end

local repairs, secret = 0, {}
local actions = { M = { active = true }, Regrid = function() repairs = repairs + 1 end }
local suite = { Public = function(value) return not rawequal(value, secret) end,
    Dispatch = function(fn, ...) return fn(...) end }
assert(loadfile(root .. "/MSUF_Suite_ActionBars/Blizzard.lua"))("MSUF_Suite_ActionBars",
    { ActionBars = actions, Suite = suite, NS = {} })
local plan
hooksecurefunc = function(_, name, cb) assert(name == "UpdateShownButtons"); plan = cb end
local native, visible = {}, false
local bar = { native = true, header = { IsVisible = function() return visible end }, buttons = {} }
Upvalue(Upvalue(actions.Dispose, "DisposeBars"), "ObservePlan")(native, bar)
local function Button(shown, hidden)
    return { shown = shown, hidden = hidden, IsShown = function(self) return self.shown end,
        GetAttribute = function(self, key) assert(key == "statehidden"); return self.hidden end }
end
local filled, empty = Button(true, nil), Button(false, true)
bar.buttons = { { button = filled }, { button = empty } }
for i = 1, 90 do plan(native) end
assert(repairs == 0, "90 unchanged native plans triggered restricted grid work")
filled.shown = false
plan(native)
assert(repairs == 1, "silent native hide under an invisible header lost the real repair")
filled.hidden = secret
plan(native)
assert(repairs == 2, "unreadable intended visibility must use the secure repair")
filled.shown, filled.hidden = secret, true
plan(native)
assert(repairs == 3, "unreadable actual visibility must use the secure repair")
visible = true
plan(native)
assert(repairs == 3, "visible header already owns its restricted OnHide correction")
print("Hidden action bar plans: 90 unchanged, 3 repairs, visible header untouched")
