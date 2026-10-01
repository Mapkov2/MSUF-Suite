local _, NS = ...

-- Shared by CharacterPanel and InspectPanel (both load after this file):
-- per-owner state, combat deferral, waiting for the load-on-demand window
-- addon, and the decorative primitives both PaperDoll windows use.
local Safety = NS.Safety
local Field = Safety.Field
local Dispatch = Safety.Dispatch
local Kit = NS.AdapterKit

local Chrome = {}
Chrome.__index = Chrome
NS.PaperDollChrome = Chrome

-- Surface specs are shared per call site; Surface.Attach stores, never edits them.
function Chrome.Spec(role, radius, inset, listItem, activeRole)
    return {
        role = role,
        radius = radius,
        inset = inset,
        listItem = listItem == true,
        activeRole = activeRole,
        allowImplicitProtected = true,
    }
end

local SLOT_SPEC = Chrome.Spec("button", 4, 0, true)
local INSET_SPEC = Chrome.Spec("panel", 5, 0)

function Chrome.Track(state, target)
    if target then state.surfaces[target] = true end
end

function Chrome.Fade(state, region)
    if not region or NS.IsCombatLocked() or not Safety.CanDecorate(region, true) then
        return false
    end
    return NS.Cosmetics.Fade(region, state.owner) == true
end

function Chrome.FadeNineSlice(state, target)
    local nineSlice = Field(target, "NineSlice")
    if not nineSlice or NS.IsCombatLocked() or not Safety.CanDecorate(nineSlice, true) then
        return false
    end
    NS.Cosmetics.FadeNineSlice(nineSlice, state.owner)
    return true
end

-- ensure: the caller is a native update hook (slot or stats update), so a
-- surface that already shows spec and is current is left alone.
function Chrome.Attach(state, target, spec, ensure)
    local attach = ensure and NS.Surface.Ensure or NS.Surface.Attach
    if not target or NS.IsCombatLocked() or not Safety.CanCreateRegions(target, true)
        or not attach(target, spec) then
        return false
    end
    state.surfaces[target] = true
    return true
end

function Chrome.SkinInset(state, inset)
    if not inset then return false end
    Chrome.FadeNineSlice(state, inset)
    Chrome.Fade(state, Field(inset, "Bg"))
    Chrome.Fade(state, Field(inset, "Background"))
    return Chrome.Attach(state, inset, INSET_SPEC)
end

-- The window portrait lives under several names across clients.
function Chrome.FadePortraits(state, root, globalPortrait)
    Chrome.Fade(state, globalPortrait)
    Chrome.Fade(state, Field(root, "Portrait"))
    Chrome.Fade(state, Field(root, "portrait"))
    local container = Field(root, "PortraitContainer")
    Chrome.Fade(state, Field(container, "Portrait"))
    Chrome.Fade(state, Field(container, "portrait"))
end

-- config: prefix (deferral keys), addon, rootName, slotNames, applyNow(state),
-- applyOrWait(state) (applies once the root exists, else waits for the addon),
-- optional initState(state) and slotIcon(slot) fallback.
function Chrome.New(config)
    config.owners = {}
    config.exactSlots = Kit.WeakSet()
    config.waiting = false
    return setmetatable(config, Chrome)
end

function Chrome:OwnerState(owner)
    local state = self.owners[owner]
    if not state then
        state = {
            owner = owner,
            active = false,
            surfaces = Kit.WeakSet(),
            deferred = {},
            jobs = {},
        }
        if self.initState then self.initState(state) end
        self.owners[owner] = state
    end
    return state
end

-- Runs callback(state) now, or once after combat. A suffix always maps to the
-- same callback, so its combat job and key are built once per owner. The
-- callers are Blizzard's PaperDoll post-hooks: each pass is its own error
-- boundary, so a raising pass never reaches Blizzard's caller.
function Chrome:RunOrDefer(state, suffix, callback)
    if not state.active then return false end
    if not NS.IsCombatLocked() then
        Dispatch(callback, state)
        return true
    end
    local job = state.jobs[suffix]
    if not job then
        local key = self.prefix .. ":" .. suffix .. ":" .. tostring(state.owner)
        local owners = self.owners
        job = { key = key }
        job.run = function()
            local current = owners[state.owner]
            if current then current.deferred[key] = nil end
            if current and current.active then callback(current) end
        end
        state.jobs[suffix] = job
    end
    state.deferred[job.key] = true
    NS.CombatGate.RunOrDefer(job.key, job.run)
    return false, "combat"
end

function Chrome:ForActiveOwners(suffix, callback)
    for _, state in pairs(self.owners) do
        if state.active then self:RunOrDefer(state, suffix, callback) end
    end
end

function Chrome:SkinSlot(state, slot)
    if not state.active or not slot or not self.exactSlots[slot] or NS.IsCombatLocked() then
        return false
    end
    Chrome.Attach(state, slot, SLOT_SPEC, true)
    local icon = Field(slot, "Icon") or Field(slot, "icon")
        or (self.slotIcon and self.slotIcon(slot))
    local border = Field(slot, "IconBorder") or Field(slot, "iconBorder")
    if icon and border then
        -- The kit's scratch spec: slot updates allocate no table.
        Kit.SkinItemIcon(slot, state.owner, icon, border, true)
    end
    return true
end

function Chrome:SkinAllSlots(state)
    if not state.active or NS.IsCombatLocked() then return false end
    local applied = false
    for index = 1, #self.slotNames do
        local name = self.slotNames[index]
        local slot = _G[name]
        if slot then
            self.exactSlots[slot] = true
            Chrome.Fade(state, _G[name .. "Frame"])
            applied = self:SkinSlot(state, slot) or applied
        end
    end
    return applied
end

-- Native slot updates: one slot now, or, in combat, one bounded pass over
-- all slots after PLAYER_REGEN_ENABLED for the whole combat window.
function Chrome:RefreshSlot(slot)
    if not self.exactSlots[slot] then return end
    local skinAll = self.skinAllSlots
    for _, state in pairs(self.owners) do
        if state.active then
            if NS.IsCombatLocked() then
                self:RunOrDefer(state, "slots", skinAll)
            else
                Dispatch(Chrome.SkinSlot, self, state, slot)
            end
        end
    end
end

function Chrome:ApplyForActiveOwners()
    self:ForActiveOwners("apply", self.applyOrWait)
end

-- True while waiting for the window addon to load.
function Chrome:ScheduleLoad()
    if self.waiting then return true end
    if NS.Client.IsAddOnLoaded(self.addon) then return false end
    self.waiting = true
    EventUtil.ContinueOnAddOnLoaded(self.addon, function()
        self.waiting = false
        self:ApplyForActiveOwners()
    end)
    return true
end

local function CategoryEnabled()
    return NS.GenericWindows.IsCategoryEnabled("character")
end

function Chrome:Activate(owner)
    if not CategoryEnabled() then return true, "disabled" end
    local state = self:OwnerState(owner)
    state.active = true
    if NS.IsCombatLocked() then
        self:RunOrDefer(state, "apply", self.applyOrWait)
        return false, "combat"
    end
    if not _G[self.rootName] then
        if self:ScheduleLoad() then return true, "waiting" end
        return false, "missing"
    end
    return self.applyNow(state)
end

-- Cancels deferred work, hides this owner's surfaces and forgets the owner.
function Chrome:Release(state)
    state.active = false
    for key in pairs(state.deferred) do
        NS.CombatGate.Cancel(key)
        state.deferred[key] = nil
    end
    for target in pairs(state.surfaces) do
        NS.Surface.SetVisible(target, false)
    end
    self.owners[state.owner] = nil
end

return Chrome
