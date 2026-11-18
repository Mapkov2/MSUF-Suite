local root = assert(arg[1], "repository or staged root required")
local mode = arg[2] or "all"
local secret = {}
local function Public(value) return value ~= secret end
local function Finite(value)
    return Public(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function CheckErrors()
    local names = {
        "LE_GAME_ERR_GENERIC_THROTTLE", "LE_GAME_ERR_BADATTACKFACING",
        "LE_GAME_ERR_BADATTACKPOS", "LE_GAME_ERR_PET_SPELL_NOT_BEHIND",
        "LE_GAME_ERR_SPELL_COOLDOWN", "LE_GAME_ERR_ABILITY_COOLDOWN",
    }
    local function Load(forever, missingPet)
        local frame, module = { enabled = {}, writes = {} }
        for index, name in ipairs(names) do
            _G[name] = index + 200
            frame.enabled[index + 200] = true
        end
        frame.enabled[203] = false
        if missingPet then LE_GAME_ERR_PET_SPELL_NOT_BEHIND = nil end
        function frame:ShouldDisplayMessageType(id) return self.enabled[id] end
        function frame:SetMessageTypeEnabled(id, value)
            self.enabled[id] = value
            self.writes[#self.writes + 1] = { id, value }
        end
        UIErrorsFrame = frame
        local context = { events = {} }
        function context:Event(name, callback) self.events[name] = callback end
        function context:RemoveEvent(name) self.events[name] = nil end
        local ns = { Client = { isForever = forever }, Safety = { IsForbidden = function() return false end } }
        local suite = { Install = function(_, value) module = value end, Public = Public, Finite = Finite }
        assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/UIErrorFilter.lua"))("test", { NS = ns, Suite = suite })
        module.context = context
        module.config = { throttle = true, facing = true, spellCooldown = true }
        return module, frame, context
    end
    for _, forever in ipairs({ false, true }) do
        local module, frame, context = Load(forever)
        module:Enable()
        assert(frame.enabled[201] == false, "doing-that-too-fast filter did not apply")
        assert(frame.enabled[202] == false and frame.enabled[203] == false and frame.enabled[204] == false,
            "facing/position/pet-behind filter did not apply or changed an existing suppression")
        assert(frame.enabled[205] == not forever and frame.enabled[206] == not forever,
            "spell/ability cooldown filter did not respect the Forever-only scope")
        local writes = #frame.writes
        module:Refresh()
        assert(#frame.writes == writes, "unchanged settings rewrote native error filters")
        assert(not context.events.UI_ERROR_MESSAGE and not context.events.ADDON_LOADED,
            "small native categories added a message listener or kept a loading retry")
        module:Disable()
        assert(frame.enabled[201] and frame.enabled[202] and not frame.enabled[203] and frame.enabled[204]
            and frame.enabled[205] and frame.enabled[206], "disable did not restore prior native settings")
    end
    local module, frame = Load(true, true)
    LE_GAME_ERR_GENERIC_THROTTLE = secret
    module:Enable()
    assert(frame.enabled[201] and not frame.enabled[202] and not frame.enabled[205],
        "unavailable or restricted error IDs were used, or valid categories were skipped")
    module:Disable()
    print("UI error detail categories: lifecycle, client scope and unavailable IDs passed")
end

local function CheckOptimizer()
    local function Load(options)
        options = options or {}
        local now, warnings, scheduled, events = 0, {}, {}, {}
        local stacks = options.stacks
        local restricted = options.restricted or false
        local combat, dead = options.combat or false, options.dead or false
        local kind = options.kind or "world"
        local aura
        if not options.missing then
            aura = { spellId = 429959, applications = stacks, expirationTime = options.expires or 1000 }
        end
        local ns = { InCombat = function() return combat end }
        local suite = {
            Text = function(value) return value end, Public = Public, Finite = Finite,
            InstanceKind = function() return kind end,
            Print = function(value) warnings[#warnings + 1] = value end,
        }
        local p = {
            NS = ns, Suite = suite,
            ExperienceBarText = { Exact = tostring, Duration = tostring, HourlyRate = function() return 0 end },
        }
        GetTime = function() return now end
        UnitIsAFK = function() return options.afk or false end
        UnitIsDeadOrGhost = function() return dead end
        GetInventoryItemID = function() return nil end
        canaccesstable = Public
        wipe = function(t) for key in pairs(t) do t[key] = nil end end
        C_Secrets = { ShouldAurasBeSecret = function() return restricted end }
        C_UnitAuras = { GetAuraDataByIndex = function(unit, index, filter)
            assert(unit == "player" and filter == "HELPFUL", "optimizer read another unit's auras")
            if index == 1 then return aura end
            if index == 2 and options.incomplete then return { spellId = secret } end
        end }
        C_Item = { GetItemCount = function(id) return id == 211527 and 1 or 0 end }
        C_Spell = { GetItemCooldown = function() return { startTime = 0, duration = 0, isEnabled = true } end }
        C_QuestLog = { GetNumQuestLogEntries = function() return 0 end }
        local owner = { optimizerPaint = function() end, optimizerTooltip = function() end }
        local context = {}
        owner.context = context
        function context:Coalesce(_, callback)
            local job = {}
            function job:Request() callback(owner) end
            function job:Cancel() end
            return job
        end
        function context:Event(event, callback) events[event] = callback end
        function context:RemoveEvent(event) events[event] = nil end
        function context:After(delay, callback) scheduled[callback] = now + delay end
        function context:Cancel(callback) scheduled[callback] = nil end
        assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/ExperienceOptimizer.lua"))("test", p)
        p.ExperienceOptimizer.Start(owner, options.level or 21)
        local function Advance(target)
            local iterations = 0
            while true do
                local callback, deadline
                for fn, at in pairs(scheduled) do
                    if at <= target and (not deadline or at < deadline) then callback, deadline = fn, at end
                end
                if not callback then break end
                iterations = iterations + 1
                assert(iterations < 20, "warning scheduling became a polling loop")
                now, scheduled[callback] = deadline, nil
                callback(owner)
            end
            now = target
        end
        local function AuraChange(value)
            if aura then aura.applications = value end
            events.UNIT_AURA(owner, "UNIT_AURA", "player")
        end
        return {
            owner = owner, warnings = warnings, events = events, advance = Advance, aura = AuraChange,
            release = function()
                combat, dead, kind = false, false, "world"
                events.PLAYER_REGEN_ENABLED(owner, "PLAYER_REGEN_ENABLED")
            end,
            stop = function()
                p.ExperienceOptimizer.Stop(owner)
                assert(next(scheduled) == nil and not events.UNIT_AURA, "disable retained warning work")
            end,
        }
    end
    local first = Load({ stacks = 1 })
    first.advance(14)
    assert(#first.warnings == 0, "partial stacks bypassed login grace")
    first.advance(16)
    assert(#first.warnings == 1
        and first.warnings[1] == "XP bonus not fully stacked: Cozy Sleeping Bag (1 / 3).",
        "one known personal sleeping-bag stack did not warn")
    first.aura(2)
    assert(#first.warnings == 1, "stack growth repeated the same warning")
    first.aura(3)
    first.aura(2)
    first.advance(314)
    assert(#first.warnings == 1, "warning transition bypassed the existing 300-second spacing")
    first.advance(316)
    assert(#first.warnings == 2
        and first.warnings[2] == "XP bonus not fully stacked: Cozy Sleeping Bag (2 / 3).",
        "existing reminder deadline did not deliver a newly eligible partial-stack warning")
    first.stop()
    for _, options in ipairs({
        { stacks = 3 }, { stacks = 0 }, {}, { stacks = secret },
        { stacks = 1, restricted = true }, { stacks = 1, incomplete = true },
        { stacks = 1, level = 13 }, { stacks = 1, afk = true },
    }) do
        local quiet = Load(options)
        quiet.advance(16)
        assert(#quiet.warnings == 0, "full, unknown, unavailable or gated stacks produced a warning")
        quiet.stop()
    end
    for _, options in ipairs({
        { stacks = 1, combat = true }, { stacks = 1, dead = true }, { stacks = 1, kind = "party" },
    }) do
        local gated = Load(options)
        gated.advance(16)
        assert(#gated.warnings == 0, "partial-stack warning bypassed a combat/death/instance gate")
        gated.release()
        assert(#gated.warnings == 1, "existing status event did not recover an eligible warning")
        gated.stop()
    end
    local expiring = Load({ stacks = 1, expires = 70 })
    expiring.advance(16)
    assert(#expiring.warnings == 1
        and expiring.warnings[1] == "XP bonus expiring soon: Cozy Sleeping Bag.",
        "partial-stack warning displaced the existing expiration warning")
    expiring.stop()
    local missing = Load({ missing = true })
    missing.advance(16)
    assert(#missing.warnings == 1 and missing.warnings[1] == "XP bonus missing: Cozy Sleeping Bag.",
        "partial-stack addition displaced the existing missing-buff warning")
    missing.stop()
    print("Sleeping-bag detail: positive personal stacks, unknown state, warning gates and spacing passed")
end

if mode == "all" or mode == "filter" then CheckErrors() end
if mode == "all" or mode == "xp" then CheckOptimizer() end
