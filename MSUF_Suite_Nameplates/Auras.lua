local _, private = ...
local NS, S = private.NS, private.Suite
local IsSecret = NS.IsSecret
-- Click-through for Blizzard's nameplate aura buttons. A protected button
-- refuses SetMouseClickEnabled in combat with ADDON_ACTION_BLOCKED, which is
-- not a Lua error, so such a change waits for the end of combat.
local Auras = {}
private.Auras = Auras
local M
-- Click-through is a property of a pooled button frame. Blizzard's pool
-- reset (Blizzard_NamePlateAuras.lua auraItemFrameResetCallback),
-- NamePlateAuraItemMixin and RefreshAuras never touch its mouse state (live,
-- ptr2 and forever), and a pool makes a new button only when every button it
-- has is active. Once a walk left every active button click-through,
-- peaks[pool] keeps that active count: RefreshAuras releases them all onto
-- the pool's stack (SecureStack, last in first out) before it acquires, so a
-- later refresh with no more active buttons can only show buttons that
-- already are, and one GetNumActive replaces the walk. The 2026-10-07 raid
-- trace ran 1,716 pool walks in 60 s (ApplyPool 11.5 ms self through the
-- secure pool proxy, SetClickthrough 7.3 ms) for 1,368 buttons; the
-- 2026-10-11 raid trace (without peaks) 2,754 walks in 88 s, 0.24 ms/s.
-- A peak is the count of the last complete walk, never a high-water mark
-- kept across an incomplete one: a button that could not change (protected
-- in combat) or read as secret leaves its pool without a peak, so the next
-- refresh walks again until a walk completes. A refresh the module does not
-- follow (switched off or inactive) can add buttons unseen and drops the
-- pool's peak; Restore hands clicks back and forgets every peak.
local peaks = setmetatable({}, { __mode = "k" })
local duplicateStates = setmetatable({}, { __mode = "k" })
-- The lane each observed aura frame refreshes last: its CrowdControlListFrame,
-- a parentKey child from Blizzard_NamePlates.xml that no client code assigns
-- again (Retail and Forever), checked once by Observe. The 2026-11-15 raid
-- trace ran AfterList 6,339 times in 158 s, two of three for a lane that is
-- not the last: those cost one check of the lane and one table read instead
-- of a frame field read and two checks.
local lastLanes = setmetatable({}, { __mode = "k" })
local hidden = setmetatable({}, { __mode = "k" })
local pending = {}
local refreshQueue, refreshPending = {}, false
local restoreFrame, secrecyFrame, watchingSecrecy
local clickOwners = setmetatable({}, { __mode = "k" })
local clickFrames = setmetatable({}, { __mode = "k" })
local nativePolicies

local function SkinAllowed(auras)
    return not private.IsSkinSuppressed or not private.IsSkinSuppressed(M.auraHooks[auras])
end

-- A boolean covers the common case. Only mixed choices need a lane lookup
-- when Blizzard moves a recycled button to another row.
local function CompilePolicy(config, side, fallback)
    local choose = NS.NameplateAuraDisplay.Clickthrough
    local buff = choose(config["aura" .. side .. "BuffClickthrough"], fallback)
    local debuff = choose(config["aura" .. side .. "DebuffClickthrough"], fallback)
    local control = choose(config["aura" .. side .. "ControlClickthrough"], fallback)
    if buff == debuff and buff == control then return buff end
    return { buff = buff, debuff = debuff, control = control }
end

function Auras.Configure(config)
    local fallback = config.auraClickthrough == true
    local enemy = CompilePolicy(config, "Enemy", fallback)
    local friendly = CompilePolicy(config, "Friendly", fallback)
    nativePolicies = (enemy ~= fallback or friendly ~= fallback)
        and { enemy = enemy, friendly = friendly, fallback = fallback } or nil
end

local function Policy(auras, uf)
    if not nativePolicies then return M.config.auraClickthrough == true end
    uf = uf or M.auraHooks[auras]
    local side = uf and private.PlatePrefix(uf)
    return nativePolicies[side or "fallback"]
end

function Auras.Bind(module) M = module end

local function Safe(frame)
    return S.Public(frame) and frame and not NS.Safety.IsForbidden(frame)
end

-- IsProtected also reports implicit protection (a secure descendant).
local function CanChange(button, unprotectedOnly)
    if not unprotectedOnly and not NS.IsCombatLocked() then return true end
    local protected = button:IsProtected()
    return S.Public(protected) and protected == false
end

local function OnCombatEnd(frame)
    if NS.IsCombatLocked() then return end
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    Auras.RestoreClicks()
end

local function Writable(button, unprotectedOnly)
    if not Safe(button) then return false end
    local allowed = button:CanBeAccessedInContext()
    return S.Public(allowed) and allowed == true and CanChange(button, unprotectedOnly)
end

local function ButtonPolicy(button, auras, policy)
    local lane = button:GetParent()
    if not S.Public(lane) or not lane then return end
    local buff, debuff, control = auras.BuffListFrame, auras.DebuffListFrame, auras.CrowdControlListFrame
    if S.Public(buff) and lane == buff then return policy.buff end
    if S.Public(debuff) and lane == debuff then return policy.debuff end
    if S.Public(control) and lane == control then return policy.control end
end

local function RestoreIcon(button, saved)
    if not Writable(button) then return false end
    local alpha = button:GetAlpha()
    if not S.Finite(alpha) then return false end
    if alpha == 0 then button:SetAlpha(saved[2]) end
    button:SetMouseMotionEnabled(saved[3])
    local auras = saved[1]
    local policy = M.active and SkinAllowed(auras) and Policy(auras)
    if policy and policy ~= true then policy = ButtonPolicy(button, auras, policy) end
    if policy then
        if saved[4] then M.auraButtons[button], clickOwners[button], clickFrames[auras] = true, auras, true end
    else
        button:SetMouseClickEnabled(M.auraButtons[button] or saved[4])
        M.auraButtons[button], clickOwners[button] = nil, nil
    end
    hidden[button], pending[button] = nil, nil
    return true
end

local function RetryIcons(frame)
    for button in pairs(pending) do
        local saved = hidden[button]
        if saved then RestoreIcon(button, saved) else pending[button] = nil end
    end
    if not next(pending) then frame:UnregisterAllEvents() end
end

local function RestoreOrDefer(button, saved)
    if RestoreIcon(button, saved) then return end
    pending[button] = true
    if not restoreFrame then
        restoreFrame = CreateFrame("Frame")
        restoreFrame:SetScript("OnEvent", RetryIcons)
    end
    restoreFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    restoreFrame:RegisterEvent("AURA_DATA_PROVIDER_SWITCH")
end

local function HideIcon(button, auras)
    if hidden[button] then
        pending[button] = nil
        return
    end
    local alpha, motion, click = button:GetAlpha(), button:IsMouseMotionEnabled(), button:IsMouseClickEnabled()
    if not S.Finite(alpha) or alpha == 0 or not S.Public(motion) or not S.Public(click) then return end
    hidden[button] = { auras, alpha, motion, click }
    button:SetAlpha(0)
    button:SetMouseMotionEnabled(false)
    button:SetMouseClickEnabled(false)
end

local function RestoreIcons(auras)
    for button, saved in pairs(hidden) do
        if not auras or saved[1] == auras then RestoreOrDefer(button, saved) end
    end
end

local function StopWatchingSecrecy()
    if not watchingSecrecy then return end
    watchingSecrecy = nil
    secrecyFrame:UnregisterAllEvents()
end

local function AuraDataReadable()
    local restricted = C_Secrets.ShouldAurasBeSecret()
    return S.Public(restricted) and restricted == false
end

local function Duplicate(auras, button, state)
    -- The pooled button must remain restorable when combat lockdown starts.
    if not state or not Writable(button, true) then return false end
    local id, lane = button.spellID, button:GetParent()
    if not S.Finite(id) or not S.Public(lane) or not Safe(lane) then return false end
    local buffs, debuffs = auras.BuffListFrame, auras.DebuffListFrame
    if not S.Public(buffs) or not S.Public(debuffs) or (lane ~= buffs and lane ~= debuffs) then return false end
    local ids = lane == buffs and state.duplicateBuffs or lane == debuffs and state.duplicateDebuffs
    return ids and ids[id] and private.AuraFilter.Match(state, lane == buffs, id, lane)
end

local function UpdateDuplicates(auras, state)
    if not AuraDataReadable() then
        if next(hidden) then RestoreIcons(auras) end
        return
    end
    local pool = auras.auraItemFramePool
    if IsSecret(pool) or not pool then return end
    if not private.AuraFilter.Visible(state) then
        if next(hidden) then RestoreIcons(auras) end
        return
    end
    local button = pool:GetNextActive()
    while S.Public(button) and button do
        local saved = hidden[button]
        if Duplicate(auras, button, state) then
            HideIcon(button, auras)
        elseif saved then
            RestoreOrDefer(button, saved)
        end
        button = pool:GetNextActive(button)
    end
    private.AuraFilter.End(state)
    if not S.Public(button) then RestoreIcons(auras) end
end

local function RefreshAfterAuraEvent()
    refreshPending = false
    for auras in pairs(refreshQueue) do
        refreshQueue[auras] = nil
        local state = duplicateStates[auras]
        if state and Safe(auras) then UpdateDuplicates(auras, state) end
    end
end

local function QueueDuplicateRefresh(auras)
    refreshQueue[auras] = true
    if not refreshPending then
        refreshPending = true
        C_Timer.After(0, RefreshAfterAuraEvent)
    end
end

local function OnAuraAccessChanged(_, event)
    if event == "PLAYER_REGEN_DISABLED" or not AuraDataReadable() then RestoreIcons() end
    for auras in pairs(duplicateStates) do QueueDuplicateRefresh(auras) end
end

local function ObserveRestrictions()
    if watchingSecrecy then return end
    if not secrecyFrame then
        secrecyFrame = CreateFrame("Frame")
        secrecyFrame:SetScript("OnEvent", OnAuraAccessChanged)
    end
    secrecyFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    secrecyFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    secrecyFrame:RegisterEvent("AURA_DATA_PROVIDER_SWITCH")
    watchingSecrecy = true
end

local function RestoreButton(button, enabled)
    if hidden[button] then return true end
    if Safe(button) then
        if not CanChange(button) then return false end
        button:SetMouseClickEnabled(enabled)
    end
    M.auraButtons[button], clickOwners[button] = nil, nil
    return true
end

local function RestorePlateClicks(uf, auras)
    local pool = auras.auraItemFramePool
    if S.Public(pool) and pool then peaks[pool] = nil end
    if not clickFrames[auras] then return end
    local waiting
    for button, owner in pairs(clickOwners) do
        if owner == auras and not RestoreButton(button, M.auraButtons[button]) then waiting = true end
    end
    clickFrames[auras] = waiting
    if waiting then M.pendingPlates[uf] = true end
end

function Auras.RestorePlate(uf)
    local auras = uf.AurasFrame
    if not Safe(auras) then return end
    Auras.SetDuplicateState(uf, nil)
    RestorePlateClicks(uf, auras)
end

function Auras.RestoreClicks()
    for pool in pairs(peaks) do peaks[pool] = nil end
    local waiting = false
    for button, enabled in pairs(M.auraButtons) do
        if not RestoreButton(button, enabled) then waiting = true end
    end
    if not waiting then
        for auras in pairs(clickFrames) do clickFrames[auras] = nil end
        return
    end
    if not M.auraRestoreFrame then
        M.auraRestoreFrame = CreateFrame("Frame")
        M.auraRestoreFrame:SetScript("OnEvent", OnCombatEnd)
    end
    M.auraRestoreFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Auras.Restore()
    RestoreIcons()
    StopWatchingSecrecy()
    Auras.RestoreClicks()
end

-- True when the button needs nothing more: click-through by our own write
-- (M.auraButtons keeps it until Restore hands the clicks back; no Blizzard
-- code changes it meanwhile), click-through already, or forbidden (never
-- touched). A protected button in combat waits for the end of combat, which
-- applies its plate again (Skin.lua OnCombatEnded): M.auraHooks maps the
-- plate's aura frame (auras) to its unit frame, a pair Blizzard keeps for
-- the session.
local function SetClickthrough(button, auras)
    if M.auraButtons[button] ~= nil or not Safe(button) then return true end
    local current = button:IsMouseClickEnabled()
    if not S.Public(current) then return false end
    if current ~= true then return true end
    if not CanChange(button) then
        M.pendingPlates[M.auraHooks[auras]] = true
        return false
    end
    M.auraButtons[button], clickOwners[button], clickFrames[auras] = current, auras, true
    button:SetMouseClickEnabled(false)
    return true
end

local function ApplyButtonPolicy(button, auras, enabled)
    if enabled then return SetClickthrough(button, auras) end
    local original = M.auraButtons[button]
    if original and not RestoreButton(button, original) then
        M.pendingPlates[M.auraHooks[auras]] = true
    end
end

local function ApplyMixedPool(pool, auras, policy)
    local button = pool:GetNextActive()
    while S.Public(button) and button do
        if Safe(button) then
            local enabled = ButtonPolicy(button, auras, policy)
            if enabled ~= nil then ApplyButtonPolicy(button, auras, enabled) end
        end
        button = pool:GetNextActive(button)
    end
end

-- GetNextActive (Blizzard_SharedXMLBase Pools.lua, both clients) visits the
-- active buttons without the iterator closure EnumerateActive allocates;
-- GetNumActive is on the same pool proxy (ObjectPoolProxyMixin, both clients).
local function ApplyPool(pool, auras, policy)
    if not S.Public(pool) or not pool then return end
    if not M.active or not policy then
        peaks[pool] = nil
        if M.active and nativePolicies and clickFrames[auras] then
            RestorePlateClicks(M.auraHooks[auras], auras)
        end
        return
    end
    if policy ~= true then
        -- The same active count can now contain buttons in different rows.
        peaks[pool] = nil
        return ApplyMixedPool(pool, auras, policy)
    end
    local count = pool:GetNumActive()
    if IsSecret(count) or type(count) ~= "number" then count = nil end
    local peak = peaks[pool]
    if count and peak and count <= peak then return end
    local done = count ~= nil
    local button = pool:GetNextActive()
    while S.Public(button) and button do
        if not SetClickthrough(button, auras) then done = false end
        button = pool:GetNextActive(button)
    end
    peaks[pool] = done and S.Public(button) and count or nil
end

local function LossOfControlItem(auras)
    local frame = auras.LossOfControlFrame
    return S.Public(frame) and frame and frame.AuraItemFrame
end

local function AfterList(auras, lane)
    -- Both clients refresh Debuffs, Buffs and then Crowd Control, even when
    -- that last lane is hidden. Observe the completed pool without hooking
    -- RefreshAuras itself or looking at the aura list or UNIT_AURA payload.
    if IsSecret(lane) or lane ~= lastLanes[auras] then return end
    local state = duplicateStates[auras]
    if state then
        if AuraDataReadable() then
            -- The native and tracked containers receive UNIT_AURA independently.
            -- Reconcile after both processed it, regardless of their event order.
            QueueDuplicateRefresh(auras)
        elseif next(hidden) then
            RestoreIcons(auras)
        end
    end
    if SkinAllowed(auras) then
        ApplyPool(auras.auraItemFramePool, auras, Policy(auras))
    end
end

local function ApplyLossOfControl(auras, policy)
    if policy and policy ~= true then policy = policy.control end
    if not policy and not clickFrames[auras] then return end
    local item = LossOfControlItem(auras)
    if S.Public(item) and item then ApplyButtonPolicy(item, auras, policy) end
end

local function OnRefreshLossOfControl(auras)
    if M.active and SkinAllowed(auras) then ApplyLossOfControl(auras, Policy(auras)) end
end

local function Observe(uf, auras)
    if M.auraHooks[auras] then return true end
    local refresh, lane = auras.RefreshList, auras.CrowdControlListFrame
    if not S.Public(refresh) or type(refresh) ~= "function" or not Safe(lane) then return false end
    lastLanes[auras] = lane
    hooksecurefunc(auras, "RefreshList", AfterList)
    local control = auras.RefreshLossOfControl
    if S.Public(control) and type(control) == "function" then
        hooksecurefunc(auras, "RefreshLossOfControl", OnRefreshLossOfControl)
    end
    M.auraHooks[auras] = uf
    return true
end

function Auras.SetDuplicateState(uf, state, exclusions)
    local auras = uf.AurasFrame
    if not Safe(auras) then return end
    if state then
        if not Observe(uf, auras) then return end
        state.duplicateBuffs, state.duplicateDebuffs = exclusions.buff, exclusions.debuff
        duplicateStates[auras] = state
        ObserveRestrictions()
        UpdateDuplicates(auras, state)
    elseif duplicateStates[auras] then
        duplicateStates[auras] = nil
        refreshQueue[auras] = nil
        RestoreIcons(auras)
        if not next(duplicateStates) then StopWatchingSecrecy() end
    end
end

function Auras.Apply(uf)
    if not nativePolicies and not M.config.auraClickthrough then
        if next(M.auraButtons) then Auras.RestoreClicks() end
        return
    end
    local auras = uf.AurasFrame
    if not Safe(auras) then return end
    local policy = Policy(auras, uf)
    if not policy then
        if clickFrames[auras] then RestorePlateClicks(uf, auras) end
        return
    end
    if not Observe(uf, auras) then return end
    ApplyPool(auras.auraItemFramePool, auras, policy)
    ApplyLossOfControl(auras, policy)
end
