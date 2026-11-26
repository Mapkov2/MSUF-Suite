-- Drive the real adapter callback, ControlSkin and Surface against native-shaped tabs.
local root = assert(arg[1])
local input = assert(io.open(root .. "/tools/tests/suite_skin_motion_contract.lua", "rb"))
local fixture = input:read("*a")
input:close()
local stop = assert(fixture:find('local parent = Target(', 1, true))
local scenario = [=[
local selections = 0
NS.MenuMotion = { SelectionChanged = function() selections = selections + 1 end }
hooksecurefunc = function(target, method, callback)
    if type(target) == "string" then return end
    local original = target[method]
    target[method] = function(...) original(...); callback(...) end
end
Load("Rendering/TabMotion.lua")
Load("Adapters/AdapterKit.lua")
Load("Adapters/PlayerSpells.lua")
local spells = Target("Frame", UIParent)
local first, second = Target("Button", spells), Target("Button", spells)
spells.TabSystem = { tabs = { first, second } }
for _, tab in ipairs(spells.TabSystem.tabs) do
    function tab:IsSelected() return self.nativeSelection end
    function tab:SetTabSelected(selected)
        self.isSelected, self.nativeSelection = selected, selected
    end
end
local skin = NS.PlayerSpellsSkin
skin.activeState = { active = true, frame = spells, owner = "spellbook", surfaces = {},
    glyphs = {}, textColors = NS.AdapterKit.NewTextColors() }
local repairs, paints = 0, 0
local originalRefresh, originalPaint = NS.ControlSkin.Refresh, NS.Surface.SkinOwnedButton
function NS.ControlSkin.Refresh(...)
    repairs = repairs + 1
    return originalRefresh(...)
end
function NS.Surface.SkinOwnedButton(...)
    paints = paints + 1
    return originalPaint(...)
end
first.isSelected, first.nativeSelection = true, true
second.isSelected, second.nativeSelection = false, false
local originalHighlight = Texture()
first:SetHighlightTexture(originalHighlight)
for i = 1, 5 do skin:QueueRefresh(spells) end
print(("Five native refreshes of two spellbook tabs: %d surface calls, %d second passes"):format(paints, repairs))
assert(paints == 10 and repairs == 0, "unchanged tabs painted twice")
local ownerPaints = 0
for _, tab in ipairs(spells.TabSystem.tabs) do
    local surface = NS.Registry.GetSurface(tab)
    local paint = surface.refresh
    surface.refresh = function(...) ownerPaints = ownerPaints + 1; return paint(...) end
end
local ownerInstructions = 0
debug.sethook(function() ownerInstructions = ownerInstructions + 100 end, "", 100)
for i = 1, 7 do skin:QueueRefresh(spells) end
debug.sethook()
print(("Seven warm owner refreshes of two spellbook tabs: %d material paints, %d sampled instructions"):format(ownerPaints, ownerInstructions))
assert(ownerPaints == 0, "deferred adapter refresh rematerialized already current tabs")
assert(ownerInstructions < 33000, "seven warm adapter refreshes exceeded the measured two-tab budget")
NS.Surface.Attach(Target("Frame", UIParent), { role = "shell" })
skin:QueueRefresh(spells)
assert(ownerPaints == 0, "opening an unrelated Blizzard surface repainted unchanged spellbook tabs")
NS.Registry.NotifyListeners("profile", "changed")
skin:QueueRefresh(spells)
assert(ownerPaints == 2, "deferred adapter refresh ignored a changed material generation")
local previousOwner = skin.activeState.owner
skin.activeState.owner = "different-spellbook-owner"
skin:QueueRefresh(spells)
assert(ownerPaints == 4, "changing the adapter owner skipped adoption")
skin.activeState.owner = previousOwner
skin:QueueRefresh(spells)
assert(ownerPaints == 6, "returning ownership skipped adoption")
local firstSurface = NS.Registry.GetSurface(first)
local bindings, layers = 0, 0
for _, key in ipairs({ "Highlight", "Pushed", "Disabled" }) do
    local setter, old = "Set" .. key .. "Texture", first["Set" .. key .. "Texture"]
    first[setter] = function(self, texture, blend)
        bindings = bindings + 1
        if key == "Highlight" then texture.blend = blend end
        return old(self, texture, blend)
    end
    local texture = firstSurface[key:lower()]
    texture.layer = key == "Highlight" and "HIGHLIGHT" or "BACKGROUND"
    texture.sublevel = key == "Highlight" and 0 or key == "Pushed" and -5 or -4
    function texture:GetDrawLayer() return self.layer, self.sublevel end
    function texture:SetDrawLayer(layer, sublevel) layers, self.layer, self.sublevel = layers + 1, layer, sublevel end
end
firstSurface.highlight.blend = "BLEND"
function firstSurface.highlight:GetBlendMode() return self.blend end
skin:QueueRefresh(spells)
assert(bindings == 0 and layers == 0, "stable native spellbook tab rebound textures or rewrote draw layers")
firstSurface.pushed.layer = "ARTWORK"
skin:QueueRefresh(spells)
assert(bindings == 0 and layers == 1 and firstSurface.pushed.layer == "BACKGROUND" and firstSurface.pushed.sublevel == -5, "native draw layer reset not repaired")
firstSurface.highlight.blend = "ADD"
skin:QueueRefresh(spells)
assert(bindings == 1 and layers == 1 and firstSurface.highlight.blend == "BLEND", "native tab blend reset not repaired")
local foreign = Texture()
first:SetHighlightTexture(foreign)
skin:QueueRefresh(spells)
assert(first:GetHighlightTexture() ~= foreign, "replaced native texture was not repaired")
first.isSelected, second.isSelected = false, true
skin:QueueRefresh(spells)
assert(NS.Registry.GetSurface(first).active == false and NS.Registry.GetSurface(second).active == true,
    "public selection lost when the native getter disagrees")
assert(NS.ControlSkin.Disable(first) and first:GetHighlightTexture() == originalHighlight, "restore lost original highlight")
first:SetHighlightTexture(foreign)
skin:QueueRefresh(spells)
assert(NS.ControlSkin.states[first].enabled and NS.Registry.GetSurface(first).visible,
    "re-enable failed after ownership release")
assert(NS.ControlSkin.Disable(first) and first:GetHighlightTexture() == foreign, "new ownership lost foreign highlight")
-- A Blizzard action may replace a previously skinned tab while its old button
-- surface is still present. Keep the full refresh on that ownership path.
second.isSelected, second.nativeSelection = true, true
local oldAction, oldApply = NS.Checkmarks.GetWindowAction, NS.WindowActionSkin.Apply
NS.Checkmarks.GetWindowAction = function(button) if button == second then return "close" end end
NS.WindowActionSkin.Apply = function() return true end
local beforeAction = repairs
skin:QueueRefresh(spells)
assert(NS.ControlSkin.states[second].windowAction and repairs > beforeAction,
    "a stale button surface masked the native action refresh")
NS.Checkmarks.GetWindowAction, NS.WindowActionSkin.Apply = oldAction, oldApply
local book, category = Target("Frame", spells), Target("Button", spells)
local rowReads = 0
book.CategoryTabSystem = { tabs = { category } }
book.PagedSpellsFrame = { GetFrames = function() rowReads = rowReads + 1 return {} end }
spells.SpellBookFrame = book
book:Hide()
skin:QueueRefresh(spells)
assert(rowReads == 0 and not NS.ControlSkin.states[category], "hidden spellbook page processed rows or tabs")
book:Show()
skin:QueueRefresh(spells)
assert(rowReads == 1 and NS.ControlSkin.states[category].enabled, "shown spellbook page missed its first rows or tabs")
-- TabSystemMixin broadcasts to all siblings, including already inactive tabs.
first:SetTabSelected(true)
second:SetTabSelected(false)
local materialPaints = 0
for _, tab in ipairs({ first, second }) do
    local surface = NS.Registry.GetSurface(tab)
    local paint = surface.refresh
    surface.refresh = function(...) materialPaints = materialPaints + 1; return paint(...) end
end
local initialSelections = selections
first:SetHighlightTexture(foreign)
local instructions = 0
debug.sethook(function() instructions = instructions + 100 end, "", 100)
for i = 1, 10 do first:SetTabSelected(true); second:SetTabSelected(false) end
debug.sethook()
print(("Twenty repeated native tab states: %d material paints, %d sampled instructions"):format(materialPaints, instructions))
assert(materialPaints == 0, "native repeat repainted the same PlayerSpells tab material")
assert(instructions < 33000, "twenty unchanged PlayerSpells tab notifications exceeded the VM budget")
assert(selections == initialSelections + 10 and first:GetHighlightTexture() ~= foreign,
    "tab changes lost content-motion dispatch or failed to repair native artwork")
first:SetTabSelected(false)
second:SetTabSelected(true)
assert(materialPaints == 2 and not NS.Registry.GetSurface(first).active and NS.Registry.GetSurface(second).active,
    "a real tab switch must paint both changed materials")
NS.Registry.NotifyListeners("profile", "changed")
first:SetTabSelected(false)
assert(materialPaints == 3, "repeated selection retained an old profile")
NS.ControlSkin.Refresh(first, false)
assert(materialPaints == 4, "an explicit repair must repaint")
local peer = Target("Button", spells)
peer.isSelected = false
peer.SetTabSelected = function(self, selected) self.isSelected = selected end
NS.ControlSkin.ApplyTab(peer, "another-window", { role = "navigation" })
local peerSurface = NS.Registry.GetSurface(peer)
local paintPeer, peerPaints = peerSurface.refresh, 0
peerSurface.refresh = function(...) peerPaints = peerPaints + 1; return paintPeer(...) end
peer:SetTabSelected(false)
peer:SetTabSelected(false)
assert(peerPaints == 2, "unmarked tabs in other windows must keep their complete selection refresh")
spells:Hide()
local before = paints
skin:QueueRefresh(spells)
assert(before == paints, "closed spellbook painted")
]=]
for _, client in ipairs({ "Forever", "Mainline" }) do
    arg[2] = client
    assert(loadstring(fixture:sub(1, stop - 1) .. scenario, "@spellbook_tab_repaint_fixture"))()
end
