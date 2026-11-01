-- Real cosmetic layers: pooled Game Menu buttons must paint on combat opens.
-- The deterministic fixture cannot establish native rendering or taint safety.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_skin_motion_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find("\nlocal parent = Target(\"Frame\", UIParent)", 1, true), "motion fixture boundary moved")
local fixture = assert(loadstring(source:sub(1, stop - 1) .. "\n" .. [[
return { NS = NS, Target = Target, Texture = Texture, Load = Load, Tick = Tick,
    created = created, clock = clock, SetLockdown = function(value) lockdown = value end,
    ForeignWrites = function() return foreignWrites end,
    NativeCounts = function() return textures, frames end }
]], "@suite_skin_game_menu_combat_fixture"))()
local NS, Target, Texture = fixture.NS, fixture.Target, fixture.Texture
local checks, writes, enumerations, childReads = 0, 0, 0, 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

-- Actual hook dispatch, with the native implementation running first.
hooksecurefunc = function(target, name, callback)
    local previous = assert(target[name])
    target[name] = function(...)
        local result = previous(...)
        callback(...)
        return result
    end
end
local pending = {}
C_Timer = {
    After = function(delay, callback)
        Check(delay == 0, "skin introduced a repeating or delayed background timer")
        pending[#pending + 1] = callback
    end,
    NewTicker = function() error("skin introduced a repeating ticker") end,
}
local function Flush()
    local rounds = 0
    while #pending > 0 do
        rounds = rounds + 1
        Check(rounds <= 4, "skin queued itself repeatedly without new input")
        local current = pending
        pending = {}
        for _, callback in ipairs(current) do callback() end
    end
end
fixture.Load("Core/CombatGate.lua")
fixture.Load("Core/Cosmetics.lua")
fixture.Load("Adapters/AdapterKit.lua")
fixture.Load("Adapters/GameMenu.lua")
NS.IsCombatLocked = function() return InCombatLockdown() or NS.Motion.combat end
debugprofilestop = function() return 0 end
UnitClass = function() return "Rogue", "ROGUE" end
C_ClassColor = { GetClassColor = function() return { r = 1, g = 0.96, b = 0.41, a = 1 } end }

local function Combat(value)
    if not value then fixture.SetLockdown(false) end
    for _, frame in ipairs(fixture.created) do
        local event = value and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED"
        if frame.events[event] then frame:Fire("OnEvent", event) end
    end
    fixture.SetLockdown(value)
end

local function NewTexture()
    local texture = Texture()
    for _, name in ipairs({ "SetAlpha", "SetTexture", "SetGradient", "SetVertexColor", "SetPoint",
        "SetSize", "SetRotation", "Show", "Hide" }) do
        local callback = texture[name]
        texture[name] = function(...)
            writes = writes + 1
            return callback(...)
        end
    end
    return texture
end
local function NewTarget(kind, parent)
    local target = Target(kind, parent)
    target.children = {}
    function target:GetChildren()
        childReads = childReads + 1
        return unpack(self.children)
    end
    function target:CreateTexture()
        Check(not self.forbidden and (not NS.IsCombatLocked() or not self.protected),
            "created artwork on a forbidden or protected combat target")
        return NewTexture()
    end
    if parent then parent.children[#parent.children + 1] = target end
    return target
end
local function Button(parent, slices)
    local button = NewTarget("Button", parent)
    if slices ~= false then
        button.Left, button.Center, button.Right = NewTexture(), NewTexture(), NewTexture()
    end
    button.nativeClick = function() end
    button:SetScript("OnClick", button.nativeClick)
    return button
end
local function NativeReset(button)
    button.nativeHighlight, button.nativePushed, button.nativeDisabled = NewTexture(), NewTexture(), NewTexture()
    button:SetHighlightTexture(button.nativeHighlight)
    button:SetPushedTexture(button.nativePushed)
    button:SetDisabledTexture(button.nativeDisabled)
    if button.Left then
        button.Left:SetAlpha(1)
        button.Center:SetAlpha(1)
        button.Right:SetAlpha(1)
    end
end
local function Skinned(button, inset)
    local state = NS.Registry.GetSurface(button)
    return state and state.kind == "button" and state.spec.inset == inset
        and button:GetHighlightTexture() == state.highlight
        and button:GetPushedTexture() == state.pushed
        and button:GetDisabledTexture() == state.disabled
        and (not button.Left or button.Left:GetAlpha() == 0 and button.Center:GetAlpha() == 0 and button.Right:GetAlpha() == 0)
        and button:GetScript("OnClick") == button.nativeClick
end

local menu = NewTarget("Frame")
menu.Header = NewTarget("Frame", menu)
menu.Border = { Bg = NewTexture() }
menu.shown = false
local pool = { active = {} }
function pool:EnumerateActive()
    enumerations = enumerations + 1
    return next, self.active, nil
end
function pool:IsActive(button) return self.active[button] == true end
function pool:Acquire() error("skin acquired a native pooled button") end
function pool:Release() error("skin released a native pooled button") end
menu.buttonPool = pool
function menu:InitButtons()
    for button in pairs(self.buttonPool.active) do NativeReset(button) end
end
Check(NS.GameMenuSkin.Apply(menu, "combat-menu"), "initial hidden Game Menu skin setup failed")
Flush()
local ownerGroups = {}
for _, action in ipairs({ "apply", "enable" }) do
    local group = { owner = "combat-owner-" .. action, action = action, first = Button(nil), second = Button(nil) }
    NativeReset(group.first)
    NativeReset(group.second)
    Check(NS.ControlSkin.ApplyButton(group.first, group.owner) ~= nil
        and NS.ControlSkin.ApplyButton(group.second, group.owner) ~= nil, "owner-release setup failed")
    ownerGroups[#ownerGroups + 1] = group
end

-- No button existed at setup. Blizzard acquires it only on the combat open.
Combat(true)
menu.shown = true
local first = Button(menu)
pool.active[first] = true
menu:InitButtons()
Check(Skinned(first, 2), "first combat-created pooled button kept native art")
Check(NS.CombatGate.GetPendingCount() == 0, "safe first-open art was deferred until combat ended")
Check(not NS.Registry.GetSurface(first).motion, "first combat paint installed animation work")

-- Rebuilding pooled buttons must repair their native state textures immediately.
local originalSurface = NS.Registry.GetSurface(first)
menu:InitButtons()
Check(Skinned(first, 2) and NS.Registry.GetSurface(first) == originalSurface,
    "combat pool rebuild failed to restore existing cosmetic state")
for _ = 1, 12 do menu:InitButtons() end
Check(#pending == 1, "combat pool rebuilds did not coalesce the late direct-button pass")
local late = Button(menu)
local msuf = Button(menu, false)
menu.MSUF = msuf
NativeReset(late)
NativeReset(msuf)
local reads = enumerations
Flush()
Check(Skinned(late, 2) and Skinned(msuf, 0), "late addon/MSUF buttons missed the combat skin")
Check(reads == enumerations, "late direct-button pass revisited the native pool")
Check(NS.Motion.count == 0 and NS.CombatGate.GetPendingCount() == 0, "combat skin left animation/deferred work")

-- The other MSUF template keeps its no-inset bounds too.
local msufThree = Button(menu)
menu.MSUF = msufThree
menu:InitButtons()
Check(Skinned(msufThree, 0), "MSUF three-slice combat button lost its full-width border")
Flush()

-- The same real shared layers apply a previously unseen safe surface in combat.
local freshMenu = NewTarget("Frame")
freshMenu.Header = NewTarget("Frame", freshMenu)
freshMenu.buttonPool = { active = {}, EnumerateActive = pool.EnumerateActive, IsActive = pool.IsActive }
freshMenu.InitButtons = function() end
Check(NS.GameMenuSkin.Apply(freshMenu, "fresh-combat-menu"), "first-ever Game Menu apply failed in combat")
Check(NS.Registry.GetSurface(freshMenu) ~= nil, "first-ever combat menu has no shell")

-- Shared public cosmetic paths also work for unprotected targets in combat.
local direct = NewTarget("Button")
Check(NS.Surface.Attach(direct, { role = "panel" }) ~= nil, "safe shared surface attach was deferred")
Check(NS.Surface.SetActive(direct, true), "safe shared selection change was deferred")
Check(NS.Surface.SetVisible(direct, false), "safe shared visibility change was deferred")
Check(NS.Surface.SetVisible(direct, true) and NS.Surface.Refresh(direct), "safe shared refresh was blocked")
Check(NS.Surface.Ensure(direct, NS.Registry.GetSurface(direct).spec) == NS.Registry.GetSurface(direct),
    "safe shared ensure rejected an existing combat surface")
local control = Button(nil)
NativeReset(control)
Check(NS.ControlSkin.ApplyButton(control, "combat-control") ~= nil, "safe shared control apply was deferred")
Check(NS.ControlSkin.Refresh(control), "safe shared control refresh was deferred")
Check(NS.ControlSkin.Disable(control) and control:GetHighlightTexture() == control.nativeHighlight,
    "safe shared control disable failed to restore native state")
Check(NS.ControlSkin.Enable(control) and Skinned(control), "safe shared control enable was deferred")
local search = NewTarget("EditBox")
search.Left, search.Middle, search.Right = NewTexture(), NewTexture(), NewTexture()
Check(NS.ControlSkin.ApplySearchBox(search, "combat-search") ~= nil and search.Left:GetAlpha() == 0,
    "safe shared search-box apply was deferred")

for _, mode in ipairs({ "protected", "explicit", "forbidden" }) do
    local unsafe = Button(menu)
    unsafe.protected = mode ~= "forbidden"
    unsafe.explicit = mode == "explicit"
    unsafe.forbidden = mode == "forbidden"
    Check(NS.Surface.Attach(unsafe, { allowImplicitProtected = true }) == nil,
        mode .. " target accepted shared surface art")
    Check(NS.Surface.SkinOwnedButton(unsafe, { allowImplicitProtected = true }) == nil,
        mode .. " target accepted shared button art")
    Check(NS.ControlSkin.ApplyButton(unsafe, "unsafe", { allowImplicitProtected = true }) == nil,
        mode .. " target accepted control skin")
    Check(NS.ControlSkin.states[unsafe] == nil, mode .. " target created control ownership before rejection")
    pool.active[unsafe] = true
    menu:InitButtons()
    Check(NS.Registry.GetSurface(unsafe) == nil, mode .. " Game Menu child accepted cosmetic art")
    pool.active[unsafe] = nil
end
Flush()

-- Configure outside combat, then create a fresh native button during combat.
-- Every shipped palette and appearance look follows the same cold path.
local variants = {}
for name in pairs(NS.PresetOverrides) do variants[#variants + 1] = { kind = "palette", name = name } end
for name in pairs(NS.LookPresets) do
    if NS.Theme.ValidateLook(name) then variants[#variants + 1] = { kind = "look", name = name } end
end
table.sort(variants, function(a, b) return a.kind .. a.name < b.kind .. b.name end)
for _, variant in ipairs(variants) do
    Combat(false)
    local setter = variant.kind == "look" and NS.Theme.ApplyLook or NS.Theme.ApplyPreset
    Check(setter(variant.name), "could not configure " .. variant.kind .. " " .. variant.name)
    Flush()
    fixture.Tick(30)
    Combat(true)
    local themed = Button(menu)
    pool.active[themed] = true
    menu:InitButtons()
    Check(Skinned(themed, 2), "combat pooled button missed " .. variant.kind .. " " .. variant.name)
    Check(not NS.Registry.GetSurface(themed).motion and NS.Motion.count == 0,
        "combat skin started motion for " .. variant.kind .. " " .. variant.name)
    Flush()
    pool.active[themed] = nil
end

-- Protection can change after a prior safe paint. The fast paths re-check it.
NS.Surface.Ensure(direct, NS.Registry.GetSurface(direct).spec)
direct.protected = true
local savedWrites = writes
Check(NS.Surface.Ensure(direct, NS.Registry.GetSurface(direct).spec) == nil,
    "already painted target bypassed its new combat protection")
Check(not NS.Surface.Refresh(direct), "newly protected target accepted an explicit refresh")
Check(not NS.Surface.SetActive(direct, false) and not NS.Surface.SetVisible(direct, false),
    "newly protected target accepted a combat state write")
Check(writes == savedWrites, "newly protected surface was repainted")
Check(NS.CombatGate.GetPendingCount() == 2, "protected state changes did not retain one deferred job each")
direct.protected = false
local superseded = NewTarget("Button")
Check(NS.Surface.Attach(superseded, { role = "panel" }) ~= nil, "supersession surface did not attach")
superseded.protected = true
Check(not NS.Surface.SetActive(superseded, false) and not NS.Surface.SetVisible(superseded, false),
    "supersession setup did not defer protected writes")
superseded.protected = false
Check(NS.Surface.SetActive(superseded, true) and NS.Surface.SetVisible(superseded, true),
    "new safe state request did not run during combat")
Check(NS.CombatGate.GetPendingCount() == 2, "new safe state request retained a stale protected request")
local reattached = NewTarget("Frame")
Check(NS.Surface.Attach(reattached, { role = "panel" }) ~= nil, "reattach setup failed")
reattached.protected = true
Check(not NS.Surface.SetVisible(reattached, false), "reattach setup did not defer visibility")
reattached.protected = false
Check(NS.Surface.Attach(reattached, { role = "panel" }) ~= nil, "safe reattach failed")
Check(NS.CombatGate.GetPendingCount() == 2, "safe reattach retained a stale protected visibility request")
local reskinned = NewTarget("Button")
Check(NS.Surface.SkinOwnedButton(reskinned, { role = "button" }, true) ~= nil, "button reskin setup failed")
reskinned.protected = true
Check(not NS.Surface.SetActive(reskinned, false) and not NS.Surface.SetVisible(reskinned, false),
    "button reskin setup did not defer state")
reskinned.protected = false
Check(NS.Surface.SkinOwnedButton(reskinned, { role = "button" }, true) ~= nil, "safe button reskin failed")
Check(NS.CombatGate.GetPendingCount() == 2, "safe button reskin retained a stale protected state request")
local unspecified = NewTarget("Button")
Check(NS.Surface.SkinOwnedButton(unspecified, { role = "button" }, false) ~= nil, "unspecified-active setup failed")
unspecified.protected = true
Check(not NS.Surface.SetActive(unspecified, true), "unspecified-active setup failed to queue")
unspecified.protected = false
Check(NS.Surface.SkinOwnedButton(unspecified, { role = "button" }) ~= nil,
    "button reskin without an active argument failed")
Check(NS.CombatGate.GetPendingCount() == 3, "unspecified active argument discarded a pending selection")
for _, group in ipairs(ownerGroups) do
    Check(not NS.ControlSkin.DisableOwner(group.owner), "owner release did not defer in combat")
    local applied
    if group.action == "apply" then applied = NS.ControlSkin.ApplyButton(group.first, group.owner)
    else applied = NS.ControlSkin.Enable(group.first) end
    Check(applied, "new individual " .. group.action .. " request did not run during combat")
end

menu:InitButtons()
menu.shown = false
savedWrites, reads = writes, childReads
Flush()
Check(writes == savedWrites and reads == childReads, "hidden menu's queued callback performed skin work")
reads = enumerations
menu:InitButtons()
Check(reads == enumerations and #pending == 0, "hidden native rebuild started a skin pass")
savedWrites = writes
fixture.Tick(600)
Check(writes == savedWrites and NS.Motion.count == 0 and fixture.clock:GetScript("OnUpdate") == nil,
    "closed combat menu retained frame-by-frame cosmetic work")
menu.shown = true
menu:InitButtons()
menu.forbidden = true
savedWrites, reads = writes, childReads
Flush()
Check(writes == savedWrites and reads == childReads, "forbidden menu's queued callback read its children")
menu.forbidden = false

Combat(false)
Check(NS.CombatGate.GetPendingCount() == 0 and NS.Registry.GetSurface(direct).active == false
    and NS.Registry.GetSurface(direct).visible == false, "protected state requests failed to replay after combat")
Check(NS.Registry.GetSurface(superseded).active == true and NS.Registry.GetSurface(superseded).visible == true,
    "old protected request overwrote the newer safe state at combat end")
Check(NS.Registry.GetSurface(reattached).visible == true and NS.Registry.GetSurface(reskinned).visible == true
    and NS.Registry.GetSurface(reskinned).active == true, "old protected state overwrote a later safe attach or reskin")
Check(NS.Registry.GetSurface(unspecified).active == true, "reskin without active argument lost pending selection")
for _, group in ipairs(ownerGroups) do
    Check(NS.ControlSkin.IsApplied(group.first), "old owner release overrode a newer individual " .. group.action)
    Check(not NS.ControlSkin.IsApplied(group.second), "new individual request canceled another control's owner release")
    Check(NS.ControlSkin.DisableOwner(group.owner) and not NS.ControlSkin.IsApplied(group.first),
        "retained individual control lost its owner cleanup registration")
end
menu.shown = true
menu:InitButtons()
Flush()
Check(Skinned(first, 2) and NS.Registry.GetSurface(first).motion ~= nil,
    "out-of-combat reopen failed to restore normal motion binding")
first:Fire("OnEnter")
Check(NS.Motion.count > 0, "post-combat button hover did not animate")
first:Fire("OnLeave")
fixture.Tick(30)
Check(NS.Motion.count == 0 and fixture.clock:GetScript("OnUpdate") == nil,
    "post-combat hover retained an idle animation driver")
menu:InitButtons()
Check(NS.GameMenuSkin.Disable(menu, "combat-menu"), "Game Menu disable failed")
pool.active = {}
savedWrites, reads = writes, enumerations
Flush()
Check(writes == savedWrites, "disabled menu's queued callback performed cosmetic writes")
menu:InitButtons()
Check(writes == savedWrites and reads == enumerations and #pending == 0, "disabled menu performed a skin pass")
Check(fixture.ForeignWrites() == 0, "skin changed native frame geometry")
print("suite_skin_game_menu_combat_contract: " .. checks .. " checks passed, " .. #variants
    .. " palettes/looks (" .. tostring(arg[2] or "Mainline") .. ")")
