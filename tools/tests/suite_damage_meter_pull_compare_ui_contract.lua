local root = assert(arg[1], "repository root required")
MSUF_DM_FEATURE_TESTS = true
dofile(root .. "/tools/tests/suite_damage_meter_contract.lua")
local fixture = assert(MSUF_DM_FIXTURE)
local D, M, S, NS = fixture.D, fixture.M, fixture.S, fixture.NS

-- The meter fixture does not load the host's menu theme. Use the ordinary
-- Suite-owned window and native-button fallback with actual menu callbacks.
local function Noop() end
NS.HostBridge.MenuButton, NS.HostBridge.MenuCloseButton, NS.HostBridge.MenuMaterial = Noop, Noop, Noop
local Region = fixture.Region
Region.SetMaxLines, Region.SetBackdrop, Region.SetBackdropColor, Region.SetBackdropBorderColor = Noop, Noop, Noop, Noop
function Region:SetEnabled(value) self.enabled = value end

local compare
local makeWindow = S.QoLWindow
function S.QoLWindow(...)
    compare = makeWindow(...)
    return compare
end

fixture.SetCombat(false)
fixture.SetZone("none")
assert(S.SetMany("damageMeter", {
    enabled = true, windowCount = 1, visibility = 1, w1Type = 1, dropdownStyle = NS.DamageMeterDropdownStyle.ORIGINAL,
}))
local win = assert(D.windows[1])
local reads, spellReads = 0, 0
function C_DamageMeter.GetAvailableCombatSessions()
    return {
        { sessionID = 11, name = "First pull", durationSeconds = 20 },
        { sessionID = 22, name = "Second pull", durationSeconds = 30 },
    }
end
function C_DamageMeter.GetCombatSessionFromID(id, kind)
    reads = reads + 1
    local rate = id == 22 and 120 or 100
    if kind == D.TYPE.Hps then rate = rate * 2 end
    return { combatSources = {
        { name = "Player", sourceGUID = "Player-1", isLocalPlayer = true, amountPerSecond = rate },
        { name = "Other", sourceGUID = "Player-2", amountPerSecond = rate + 40 },
    } }
end
function C_DamageMeter.GetCombatSessionSourceFromID(id, kind, guid)
    spellReads = spellReads + 1
    local rate = id == 22 and 120 or 100
    if kind == D.TYPE.Hps then rate = rate * 2 end
    return { combatSpells = { { spellID = guid == "Player-1" and 111 or 222, amountPerSecond = rate } } }
end

local function Open()
    D.HeaderButtonClick(win.buttons.session)
    fixture.Pick(fixture.GetMenu(), "Compare pulls")
    assert(compare and compare:IsShown() and M.compareOpen, "fight menu did not open the comparison")
end

local function Click(button)
    button:GetScript("OnClick")(button)
end

Open()
assert(compare.pullA.id == 11 and compare.pullB.id == 22, "default comparison is not oldest to newest")
assert(reads == 2 and spellReads == 2, "opening should read each pull and selected player once")
assert(compare.players.selected.guid == "Player-1", "own player was not preselected")
assert(compare.players.selected.rateA == 100 and compare.players.selected.rateB == 120)
assert(compare.spells.items[1].rateA == 100 and compare.spells.items[1].rateB == 120)
Click(compare.players.rows[1])
assert(compare.players.selected.guid == "Player-2", "clicking another player did not drill down")
assert(reads == 2 and spellReads == 4 and compare.spells.items[1].spellID == 222)
Click(compare.players.rows[1])
assert(spellReads == 4, "selecting the already visible player reread spells")
Click(compare.hps)
assert(compare.meterType == D.TYPE.Hps and compare.players.selected.rateB == 240)
assert(reads == 4 and spellReads == 6, "changing metric did not refresh both pulls and details once")
Click(compare.aButton)
local swap = fixture.Pick(fixture.GetMenu(), compare.pullB.label)
assert(compare.pullA.id == 22 and compare.pullB.id == 11, "picking the opposite pull did not swap")
assert(reads == 6 and spellReads == 8, "swapping did not refresh both pull values")
fixture.Event("DAMAGE_METER_RESET")
assert(not compare:IsShown() and not M.compareOpen and compare.players.items == nil, "reset retained old IDs")
Open()
swap.callback(swap.data)
assert(compare.pullA.id == 11 and compare.pullB.id == 22, "old picker mutated a reopened comparison")
fixture.Event("PLAYER_REGEN_DISABLED")
assert(not compare:IsShown(), "combat edge did not close the comparison")
local previousReads, previousSpells = reads, spellReads
D.HeaderButtonClick(win.buttons.session)
local disabled = fixture.Pick(fixture.GetMenu(), "Compare pulls")
assert(disabled.enabled == false and not compare:IsShown(), "comparison reopened on the combat edge")
assert(reads == previousReads and spellReads == previousSpells, "combat compared protected data")
fixture.Event("PLAYER_REGEN_ENABLED")
Open()
assert(S.SetMany("damageMeter", { enabled = false }))
assert(not compare:IsShown() and not M.compareOpen, "disabling the module left the comparison open")

print("Pull comparison UI: fight menu, both pulls, DPS/HPS, drilldown, swap, stale picks, reset, combat and disable passed")
