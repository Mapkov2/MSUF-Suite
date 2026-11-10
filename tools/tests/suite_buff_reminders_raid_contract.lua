-- The actual runtime, native-event routing and menu renderer, on both clients.
local root = assert(arg[1])
local private, originalLoad = nil, loadfile
local mutations = {
    selection = { "RaidOverview.lua", "if self.config.raidBuffOverview then", "if false then" },
    delta = { "RaidOverview.lua", "R.AuraChangeAffects(member, info)", "false" },
    hidden = { "RaidOverview.lua", "if unit and self.list.needsFullRefresh then return end", "" },
    combat = { "Group.lua", "self.config.otherClassBuffs == true or self.config.raidBuffOverview == true",
        "self.config.otherClassBuffs == true" },
    reshow = { "RaidOverview.lua", "button.overviewShown = false", "" },
    preview = { "Preview.lua", "R.BuildRaidOverview(state, true)", "R.BuildRaidOverview(state, false)" },
}
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    local mutation = mutations[arg[2]]
    if mutation and path:find("MSUF_Suite_BuffReminders/" .. mutation[1], 1, true) then
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local first, last = assert(source:find(mutation[2], 1, true))
        chunk = assert(loadstring(source:sub(1, first - 1) .. mutation[3] .. source:sub(last + 1), "@" .. path))
    end
    return function(addon, namespace)
        if path:find("MSUF_Suite_BuffReminders/Controller.lua", 1, true) then private = namespace end
        return chunk(addon, namespace)
    end
end
assert(originalLoad(root .. "/tools/tests/suite_buff_reminders_contract.lua"))()
loadfile = originalLoad
local NS, S, R = private.NS, private.Suite, private.BuffReminders
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local module = testModule
local baseUpdate = module.Update

local function Check(forever)
    module.Update, module.raid = baseUpdate, {}
    NS.Client.isForever, NS.Client.modernEquipment = forever, not forever
    local roster = { player = "PRIEST", raid2 = "MAGE", raid3 = "WARRIOR", raid4 = "DRUID",
        raid5 = "SHAMAN", raid6 = "EVOKER" }
    local combat, restricted, invisible, disconnected, dead = false, false, {}, {}, {}
    local buffs, reads, lastUnit = {}, 0, nil
    local classes = { "PRIEST", "MAGE", "WARRIOR", "DRUID", "SHAMAN", "EVOKER" }
    for unit in pairs(roster) do
        buffs[unit] = {}
        for index, class in ipairs(classes) do
            local buff = R.ClassBuff(class)
            if buff then buffs[unit][buff.auras[1]] = { auraInstanceID = 100 + index, spellId = buff.auras[1] } end
        end
    end
    buffs.raid3[1459] = nil
    UnitClass = function(unit) return roster[unit], roster[unit] end
    IsInRaid = function() return true end
    GetNumGroupMembers = function() return 6 end
    GetNumSubgroupMembers = function() return 0 end
    UnitIsUnit = function(unit, other) return unit == other or unit == "raid1" and other == "player" end
    UnitExists = function(unit) return roster[unit] ~= nil end
    UnitIsConnected = function(unit) return not disconnected[unit] end
    UnitIsVisible = function(unit) return not invisible[unit] end
    UnitIsDeadOrGhost = function(unit) return dead[unit] == true end
    UnitInVehicle, IsMounted = function() return false end, function() return false end
    GetInstanceInfo = function() return "World", "none" end
    NS.IsCombatLocked = function() return combat end
    C_Secrets.ShouldAurasBeSecret = function() return restricted end
    local function Read(unit, id)
        reads, lastUnit = reads + 1, unit
        return buffs[unit] and buffs[unit][id]
    end
    C_UnitAuras.GetUnitAuraBySpellID = Read
    C_UnitAuras.GetPlayerAuraBySpellID = function(id) return Read("player", id) end
    C_UnitAuras.GetAuraDataBySpellName = function(unit, name, filter)
        assert(filter == "HELPFUL")
        return Read(unit, tonumber(name:match("(%d+)$")))
    end
    C_UnitAuras.GetAuraDataByAuraInstanceID = function() error("no instance-ID reads") end
    C_UnitAuras.GetAuraDataByIndex = function() error("no aura enumeration") end
    C_Timer.NewTicker = function() error("no recurring ticker") end
    local queue, callbacks = {}, {}
    C_Timer.After = function(delay, callback)
        assert(delay == .1, "only the existing bounded group coalescer may run")
        queue[#queue + 1] = callback
    end
    local function Flush()
        local current = queue
        queue = {}
        for _, callback in ipairs(current) do callback() end
    end
    local TimerContext = Support.ModuleTimers(root, S, NS)
    module.context = TimerContext("buffReminders", module, {
        Event = function(_, event, callback) callbacks[event] = callback end,
        RemoveEvent = function(_, event) callbacks[event] = nil end,
    })
    local function Event(event, unit, info)
        if callbacks[event] then callbacks[event](module, event, unit, info) end
    end
    local c = {}
    for key, value in pairs(NS.Defaults.suite.modules.buffReminders) do c[key] = value end
    c.raidBuffOverview, c.classBuff, c.groupBuff, c.otherClassBuffs = true, false, false, false
    c.autoFood, c.autoFlask, c.autoRune, c.autoWeapon, c.autoRoguePoisons = false, false, false, false, false
    c.classInnerFire, c.classMageArmor, c.remindBeforeMinutes, c.hideMounted = false, false, 0, false
    module.config, module.active, S.editMode = c, true, false
    module:Enable()
    local expected = forever and 4 or 6
    assert(#module.list.entries == 0 and #module.raid.rows == expected, "overview took personal slots or wrong client buffs")
    assert(module.raid.rows[1].id == (forever and 1243 or 21562)
        and module.raid.rows[1].ranked == forever, "client-specific aura IDs or rank readers were mixed")
    local row, button = module.raid.rows[2], module.raid.buttons[2]
    assert(row.id == 1459 and row.covered == 5 and row.total == 6 and row.unknown == 0)
    assert(button.shown and button.count.text == "5/6", "live coverage was not rendered")
    assert(not next(button.attributes), "overview acquired a spell-casting action")
    button:OnEnter()
    assert(GameTooltip.spell == 1459 and GameTooltip.lines[1] == "Buffed: 5/6", "coverage tooltip missing")
    button:OnLeave()

    local before = reads
    local unrelated = { addedAuras = { { spellId = 999999, name = "Spell 999999", auraInstanceID = 999 } } }
    Event("UNIT_AURA", "raid3", unrelated)
    Flush()
    assert(reads == before, "unrelated member aura caused native reads")
    buffs.raid3[1459] = { spellId = 1459, auraInstanceID = 102 }
    local added = { addedAuras = { { spellId = 1459, name = "Spell 1459", auraInstanceID = 102 } } }
    Event("UNIT_AURA", "raid3", added)
    Event("UNIT_AURA", "raid3", added)
    assert(#queue == 1, "aura burst queued multiple passes")
    Flush()
    assert(reads == before + 1 and lastUnit == "raid3" and button.count.text == "6/6",
        "one changed buff should read one member once")
    buffs.raid3[1459] = nil
    Event("UNIT_AURA", "raid3", { removedAuraInstanceIDs = { 102 } })
    Flush()
    assert(button.count.text == "5/6", "removal left stale coverage")
    invisible.raid3 = true
    before = reads
    Event("UNIT_FLAGS", "raid3")
    Flush()
    assert(reads == before and button.count.text == "5/6 ?" and row.unknown == 1,
        "unreadable player became confirmed missing")
    invisible.raid3 = nil
    restricted = true
    before = reads
    Event("UNIT_AURA", "raid4", { isFullUpdate = true })
    Flush()
    assert(reads == before and row.unknown == 2, "restricted auras were read or counted absent")
    restricted = false
    Event("UNIT_AURA", "raid4", { isFullUpdate = true })
    Flush()
    assert(row.unknown == 1, "public aura data did not recover")

    -- The old reminders retain their independent category filter.
    c.class_showWorld = false
    module:Update("visual")
    assert(not button.shown, "class visibility did not hide the overview")
    c.class_showWorld = true
    module:Update("visual")
    assert(button.shown, "overview did not return")
    before = reads
    Event("PLAYER_REGEN_DISABLED")
    combat = true
    Event("UNIT_AURA", "raid2", { isFullUpdate = true })
    module:Update("all")
    Flush()
    assert(reads == before and callbacks.UNIT_AURA == nil, "combat still performed aura work")
    combat = false
    Event("PLAYER_REGEN_ENABLED")
    assert(callbacks.UNIT_AURA and #module.raid.rows == expected, "combat end did not restore the overview")
    Event("PLAYER_REGEN_DISABLED")
    combat = true
    roster.raid4, roster.raid6 = "EVOKER", nil
    GetNumGroupMembers = function() return 5 end
    Event("GROUP_ROSTER_UPDATE")
    combat = false
    Event("PLAYER_REGEN_ENABLED")
    assert(#module.raid.rows == expected - 1, "last provider leaving in combat stayed in the overview")
    roster.raid4, roster.raid6 = "DRUID", "EVOKER"
    GetNumGroupMembers = function() return 6 end
    Event("GROUP_ROSTER_UPDATE")
    Flush()

    -- Additions/removals rebuild the provider row without duplicate players.
    roster.raid6, roster.raid5 = nil, nil
    GetNumGroupMembers = function() return 4 end
    Event("GROUP_ROSTER_UPDATE")
    Flush()
    assert(#module.raid.rows == 4 and module.raid.rows[2].total == 4, "roster/provider removal stayed stale")
    roster.raid5, roster.raid6 = "SHAMAN", "EVOKER"
    GetNumGroupMembers = function() return 6 end
    Event("GROUP_ROSTER_UPDATE")
    Flush()
    assert(#module.raid.rows == expected and module.raid.buttons[expected].shown,
        "returning provider icon stayed hidden")
    local lastRow = table.remove(module.raid.rows)
    R.LayoutRaidOverview(module)
    assert(not module.raid.buttons[expected].shown, "unused layout icon stayed visible")
    module.raid.rows[expected] = lastRow
    R.LayoutRaidOverview(module)
    R.DrawRaidOverview(module, true, false)
    assert(module.raid.buttons[expected].shown, "returning provider icon stayed hidden")

    -- Forty players retain one pass for a burst, with no unrelated aura reads.
    for i = 7, 40 do
        local unit = "raid" .. i
        roster[unit], buffs[unit] = classes[(i - 1) % #classes + 1], {}
        for _, class in ipairs(classes) do
            local buff = R.ClassBuff(class)
            if buff then buffs[unit][buff.auras[1]] = { spellId = buff.auras[1], auraInstanceID = i * 10 } end
        end
    end
    GetNumGroupMembers = function() return 40 end
    Event("GROUP_ROSTER_UPDATE")
    Flush()
    assert(module.raid.rows[2].total == 40, "forty-player roster counted the player twice")
    before = reads
    for _ = 1, 100 do Event("UNIT_AURA", "raid40", unrelated) end
    assert(#queue == 1, "forty-player burst scheduled repeated work")
    Flush()
    assert(reads == before, "forty-player unrelated burst performed native aura reads")
    for i = 7, 40 do roster["raid" .. i] = nil end
    GetNumGroupMembers = function() return 6 end

    -- Menu samples are independent of live aura counts, even for a solo player.
    IsInRaid, GetNumSubgroupMembers = function() return false end, function() return 0 end
    local stage, opened = CreateFrame("Frame"), 0
    before = reads
    local _, _, count = S.BuffRemindersDrawPreview(stage, c, true, function() opened = opened + 1 end)
    assert(count == expected and reads == before, "solo preview did not show supported sample buffs without aura reads")
    local sample = stage.buffReminderPreview.raid
    assert(sample.rows ~= module.raid.rows and sample.buttons[1].count.text == "18/20", "preview contaminated live coverage")
    sample.buttons[1]:OnClick()
    assert(opened == 1 and not next(sample.buttons[1].attributes), "sample click was not settings-only")
    c.raidBuffOverview = false
    S.BuffRemindersDrawPreview(stage, c, false, function() end)
    for _, icon in ipairs(sample.buttons) do assert(not icon.shown, "disabled sample stayed visible") end
    c.raidBuffOverview = true
    S.BuffRemindersDrawPreview(stage, c, false, function() end)
    for _, icon in ipairs(sample.buttons) do assert(icon.shown, "re-enabled sample stayed hidden") end

    S.editMode = true
    module:Update("visual")
    assert(#module.raid.rows == expected and not module.view.preview.shown, "Edit Mode did not show coverage samples")
    S.editMode = false
    module:Refresh()
    assert(#module.raid.rows == 0, "solo player retained a live raid overview")
    assert(callbacks.UNIT_AURA == nil, "solo coverage kept an unused aura listener")
    c.raidBuffOverview = false
    module:Refresh()
    assert(callbacks.GROUP_ROSTER_UPDATE == nil and callbacks.UNIT_AURA == nil,
        "disabled overview retained group listeners")
    module:Disable()
    c.raidBuffOverview, c.hideMounted = true, true
    IsMounted = function() return true end
    IsInRaid = function() return true end
    module:Enable()
    before = reads
    Event("UNIT_AURA", "raid2", added)
    Flush()
    assert(reads == before, "hidden first-show state applied a delta or read native auras")
    IsMounted = function() return false end
    Event("PLAYER_MOUNT_DISPLAY_CHANGED")
    assert(module.raid.rows[2].total == 6 and module.raid.buttons[2].shown,
        "first visible state did not take a complete snapshot")
    module:Disable()
    module.active = false
end

Check(false)
Check(true)
print("Raid coverage: both clients, native deltas, coalescing, restricted data, combat, providers and isolated previews passed")
