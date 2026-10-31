local _, P = ...
local D, S, NS = P.DamageMeter, P.Suite, P.NS
local M = D.M
local Public, Finite = S.Public, S.Finite

-- Target selection is runtime state of one fight, never a saved creature name.
-- One native enemy source supplies both the ranking and its spell drilldown.
function D.ClearTarget(win)
    win.damageTarget, win.filteredCache = nil, nil
end

local function Restricted()
    return M.inCombat or NS.IsCombatLocked()
end

local function SourceRow(native)
    local guid, creature = D.Identity(native)
    return { name = native.name, classFilename = native.classFilename, specIconID = native.specIconID,
        sourceGUID = guid, sourceCreatureID = creature, isLocalPlayer = native.isLocalPlayer,
        totalAmount = 0, amountPerSecond = 0, deathRecapID = 0, deathTimeSeconds = 0,
        detail = { combatSpells = {}, totalAmount = 0, maxAmount = 0 } }
end

local function AddSpell(rows, full, short, spell)
    if not Public(spell) or type(spell) ~= "table" then return false end
    local unit = spell.combatSpellDetails
    if not Public(unit) or type(unit) ~= "table" then return false end
    local name, class, amount = unit.unitName, unit.unitClassFilename, spell.totalAmount
    if not Public(name) or type(name) ~= "string" or not Public(class) or type(class) ~= "string"
        or not Finite(amount) or amount < 0 then return false end
    if amount == 0 then return true end
    local resolved, ambiguous = D.TargetPlayer(full, short, name, class)
    -- A pet, guardian, totem or NPC is no player's row: it is left out, as the
    -- hover list leaves it out (Data.lua). A name that fits several players
    -- fails the filter, so a ranking never shows a guessed attribution.
    if not resolved then return not ambiguous end
    local row = rows[resolved]
    if not row then
        row = SourceRow(full[resolved].source)
        rows[resolved] = row
    end
    row.totalAmount = row.totalAmount + amount
    local rate = spell.amountPerSecond
    if Finite(rate) and rate >= 0 and row.nativeRate ~= false then
        row.nativeRate = (row.nativeRate or 0) + rate
    else row.nativeRate = false end
    local detail = row.detail
    detail.combatSpells[#detail.combatSpells + 1] = spell
    detail.totalAmount = row.totalAmount
    detail.maxAmount = math.max(detail.maxAmount, amount)
    return true
end

local function ByAmount(a, b) return a.totalAmount > b.totalAmount end

local function Build(win, native)
    local full, short = D.TargetIndex(native)
    if not full then return nil end
    local target = win.damageTarget
    local detail = D.EnemySource(win, target.guid, target.creature)
    if not Public(detail) or type(detail) ~= "table" then return nil end
    local spells = detail.combatSpells
    if not Public(spells) or type(spells) ~= "table" then return nil end
    local rows, count = {}, D.Count(spells)
    for i = 1, count do if not AddSpell(rows, full, short, spells[i]) then return nil end end
    local list, total, duration = {}, 0, native.durationSeconds
    duration = Finite(duration) and duration > 0 and duration or 0
    for _, row in pairs(rows) do
        if row.nativeRate == false and duration == 0 then return nil end
        row.amountPerSecond = row.nativeRate or (duration > 0 and row.totalAmount / duration or 0)
        row.targets = { { name = target.name, amount = row.totalAmount, class = "", spec = 0 } }
        table.sort(row.detail.combatSpells, ByAmount)
        total = total + row.totalAmount
        list[#list + 1] = row
    end
    table.sort(list, ByAmount)
    return { combatSources = list, maxAmount = list[1] and list[1].totalAmount or 0,
        totalAmount = total, durationSeconds = duration }
end

function D.FilterSession(win, native)
    if Restricted() or not native then return nil end
    local cache = win.filteredCache
    if not cache or cache.revision ~= M.targetRevision
        or (not cache.session and GetTime() >= cache.retryAt) then
        cache = { revision = M.targetRevision, session = Build(win, native), retryAt = GetTime() + 1 }
        win.filteredCache = cache
    end
    return cache.session
end

function D.FilterSource(win, guid, creature)
    if Restricted() then return nil end
    local cache = win.filteredCache
    if not cache or cache.revision ~= M.targetRevision then D.FetchSession(win) end
    local session = win.filteredCache and win.filteredCache.session
    local sources = session and session.combatSources
    for i = 1, D.Count(sources) do
        local source = sources[i]
        if (guid and source.sourceGUID == guid) or (creature and source.sourceCreatureID == creature) then
            return source.detail
        end
    end
end

function D.SelectTarget(win, target)
    if Restricted() or not D.damageTypes[win.meterType] then return false end
    D.ClearTarget(win)
    win.damageTarget = target
    D.CloseBreakdown(win, true)
    win.offset, win.dirty = 0, true
    D.SyncWatch()
    D.UpdateTitle(win)
    if win.shown then D.Paint(win) end
    return true
end

local function Selected(data)
    local current, target = data.win.damageTarget, data.target
    if not current or not target then return current == target end
    return current.guid == target.guid and current.creature == target.creature
end
local function Chosen(data) D.SelectTarget(data.win, data.target) end

local function TargetMenu(_, root, win)
    root:CreateTitle(S.Text("Filter damage by target"))
    if Restricted() then
        local item = root:CreateButton(S.Text("Targets after combat"))
        item:SetEnabled(false)
        return
    end
    root:CreateRadio(S.Text("All targets"), Selected, Chosen, { win = win })
    local session = D.EnemySession(win)
    local sources = session and session.combatSources
    for i = 1, D.Count(sources) do
        local enemy = sources[i]
        local name = enemy.name
        local guid, creature = D.Identity(enemy)
        if Public(name) and type(name) == "string" and name ~= "" and (guid or creature) then
            root:CreateRadio(name, Selected, Chosen,
                { win = win, target = { name = name, guid = guid, creature = creature } })
        end
    end
end

function D.OpenTargetMenu(win, owner)
    if D.damageTypes[win.meterType] then S.ContextMenu(owner, TargetMenu, win) end
end
