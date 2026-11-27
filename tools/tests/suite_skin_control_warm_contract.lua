-- Warm re-apply of reusePaint ControlSkin specs (perf pass 2026-11-26, owner
-- goal: skinning is cold path). The real Surface, Registry and ControlSkin of
-- the motion fixture: a marked spec, also an active one, keeps its material on
-- a warm apply; a settings change, a selection changed by another path, a
-- hidden surface and unmarked specs still repaint. ControlSkin.IsWarm answers
-- from owned state only.
local root = assert(arg[1])
local file = assert(io.open(root .. "/tools/tests/suite_skin_motion_contract.lua", "rb"))
local fixture = file:read("*a")
file:close()
local finish = assert(fixture:find("local parent = Target(", 1, true))
local body = [=[
local ControlSkin = NS.ControlSkin
local function NativeButton()
    local button = Target("Button", UIParent)
    button.Left, button.Middle, button.Right = Texture(), Texture(), Texture()
    return button
end
local function CountPaints(button)
    local surface = assert(NS.Registry.GetSurface(button))
    local paint, counter = surface.refresh, { paints = 0 }
    surface.refresh = function(...) counter.paints = counter.paints + 1; return paint(...) end
    return surface, counter
end

-- A marked active spec: the second apply reuses the painted material.
local selected = ControlSkin.MarkFixedButtonSpec({ active = true }, true)
local button = NativeButton()
assert(ControlSkin.ApplyButton(button, "warm-owner", selected), "marked active spec did not skin")
local surface, count = CountPaints(button)
assert(surface.active == true and ControlSkin.IsWarm(button, "warm-owner", selected),
    "a freshly painted marked spec did not read as warm")
local instructions = 0
debug.sethook(function() instructions = instructions + 100 end, "", 100)
for _ = 1, 10 do assert(ControlSkin.ApplyButton(button, "warm-owner", selected)) end
debug.sethook()
print(("Ten warm applies of a marked active spec: %d material paints, %d sampled instructions"):format(count.paints, instructions))
assert(count.paints == 0, "a warm marked active spec repainted its unchanged material")
-- Measured 2026-11-26: 7,700 with reuse, 33,000 with a full paint per apply.
assert(instructions < 9500, "ten warm marked applies exceeded the measured VM budget")
assert(surface.active == true and button:GetHighlightTexture() == surface.highlight
    and button.Left:GetAlpha() == 0, "a warm apply lost its selection, slot binding or faded slice")
-- Native art is still repaired on the warm path.
local foreign = Texture()
button:SetHighlightTexture(foreign)
button.Left:SetAlpha(1)
ControlSkin.ApplyButton(button, "warm-owner", selected)
assert(count.paints == 0 and button:GetHighlightTexture() == surface.highlight and button.Left:GetAlpha() == 0,
    "a warm apply skipped the native slot or slice repair")

-- IsWarm: owner, spec identity and the reusePaint mark.
assert(not ControlSkin.IsWarm(button, "other-owner", selected), "IsWarm ignored the owner")
assert(not ControlSkin.IsWarm(button, "warm-owner", { active = true }), "IsWarm accepted another spec table")
assert(not ControlSkin.IsWarm(NativeButton(), "warm-owner", selected), "IsWarm accepted an unskinned button")

-- A settings change repaints once, then the warm path holds again.
NS.Registry.NotifyListeners("profile", "changed")
assert(not ControlSkin.IsWarm(button, "warm-owner", selected), "IsWarm missed a settings generation")
ControlSkin.ApplyButton(button, "warm-owner", selected)
assert(count.paints == 1 and ControlSkin.IsWarm(button, "warm-owner", selected),
    "a changed profile did not repaint the warm active spec exactly once")
ControlSkin.ApplyButton(button, "warm-owner", selected)
assert(count.paints == 1, "the repainted marked spec left its warm path")

-- Another path changed the painted selection: the next apply repaints it.
NS.Surface.SetActive(button, false)
assert(count.paints == 2 and not ControlSkin.IsWarm(button, "warm-owner", selected),
    "IsWarm accepted a selection other than the requested one")
ControlSkin.ApplyButton(button, "warm-owner", selected)
assert(count.paints == 3 and surface.active == true, "a warm apply kept a selection another path changed")

-- A hidden surface and a combat-deferred change are never warm.
NS.Surface.SetVisible(button, false)
assert(count.paints == 4 and not ControlSkin.IsWarm(button, "warm-owner", selected), "IsWarm accepted a hidden surface")
ControlSkin.ApplyButton(button, "warm-owner", selected)
assert(count.paints == 5 and surface.visible == true, "a hidden marked button was not shown again")
surface.pendingVisible = "surface-visible:test"
assert(not ControlSkin.IsWarm(button, "warm-owner", selected), "IsWarm accepted a combat-deferred visibility")
surface.pendingVisible = nil
assert(ControlSkin.IsWarm(button, "warm-owner", selected))
assert(ControlSkin.Disable(button) and not ControlSkin.IsWarm(button, "warm-owner", selected),
    "IsWarm accepted a released button")

-- Unmarked specs and immutable-only marks keep their full paint per apply.
for _, spec in ipairs({ { active = true }, ControlSkin.MarkFixedButtonSpec({ active = true }) }) do
    local plain = NativeButton()
    ControlSkin.ApplyButton(plain, "warm-owner", spec)
    local _, plainCount = CountPaints(plain)
    ControlSkin.ApplyButton(plain, "warm-owner", spec)
    ControlSkin.ApplyButton(plain, "warm-owner", spec)
    assert(plainCount.paints == 2 and not ControlSkin.IsWarm(plain, "warm-owner", spec),
        "unmarked or immutable-only specs must retain full paints")
end
print("ControlSkin warm reuse: marked active spec, IsWarm, profile, selection, visibility, release passed")
]=]
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    arg[2] = flavor
    assert(loadstring(fixture:sub(1, finish - 1) .. body, "@control_warm_fixture"))()
end
