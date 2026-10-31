-- The cooldown manager data plane on stubbed client APIs, for the CDM
-- contracts that need the catalog at the 2026-10-28 trace's size: the core
-- catalog, Const, AuraTimers, Presets, GuideProfiles, Catalog, EntryFill,
-- Resolve and Index, loaded in TOC order. Blizzard's category sets and
-- cooldown infos are plain tables the contract edits (W.sets, W.infos);
-- every client read is counted per API (W.natives). Secrets are sentinels
-- that raise on any Lua use. Not a contract itself (no "suite_" prefix).
return function(root)
    local W = { natives = {}, combat = false }
    local function Count(name) W.natives[name] = (W.natives[name] or 0) + 1 end

    local SecretMT = {}
    local function Raise(what) return function() error("secret value used: " .. what, 2) end end
    for _, key in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat", "__lt", "__le", "__eq",
        "__call" }) do SecretMT[key] = Raise(key) end
    SecretMT.__index, SecretMT.__newindex, SecretMT.__tostring = Raise("index"), Raise("assignment"), Raise("tostring")
    function W.Secret() return setmetatable({}, SecretMT) end
    local function IsSecret(value) return getmetatable(value) == SecretMT end
    issecretvalue = IsSecret
    InCombatLockdown = function() return W.combat end
    securecallfunction = function(callback, ...) return callback(...) end

    MSUF_NS = { Client = { Family = "Mainline", Flavor = "Mainline", IsRetail = true, SupportsEvent = function() return true end } }
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    local store = {}
    MSUF_EncodeCompactTable = function(t, prefix) local n = #store + 1; store[n] = t; return prefix .. ":" .. n end
    MSUF_TryDecodeCompactString = function(s) local n = tonumber(s:match("^MSUF3:(%d+)$")); return n and store[n] or nil end
    local NS = {}
    for _, f in ipairs({ "Core/Platform.lua", "Core/Database.lua", "Core/SuiteCatalog.lua" }) do
        assert(loadfile(root .. "/MSUF_Suite/" .. f))("MSUF_Suite", NS)
    end
    local B = NS.CatalogBuild
    local original = B.Module
    B.Module = function(mid, spec)
        if mid == "cooldownManager" then
            local catalog, order = NS.SuiteCatalog, NS.SuiteOrder
            spec.id, spec.addon, spec.controls, spec.rules, spec.conflicts = mid, "MSUF_Suite_CooldownManager", {}, {}, spec.conflicts or {}
            catalog[mid], order[#order + 1] = spec, mid
            B.Add(mid, B.Bool("enabled", "Enable module", false))
            return spec
        end
        return original(mid, spec)
    end
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/CooldownManager.lua"))("MSUF_Suite", NS)
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/CooldownManagerData.lua"))("MSUF_Suite", NS)
    W.NS, W.CDM = NS, NS.CDM

    Constants = { SpellCooldownConsts = { GLOBAL_RECOVERY_CATEGORY = 133 } }
    INVSLOT_TRINKET1, INVSLOT_TRINKET2 = 13, 14
    Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 }, CompressionMethod = { Deflate = 0 },
        CooldownViewerCategory = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3, GroupBuff = 4, SpecAgnosticEssential = 5,
            SpecAgnosticTracked = 6, EquipSlotEssential = 7, EquipSlotTracked = 8 },
        StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 }, StatusBarInterpolation = { Immediate = 0 } }
    W.sets, W.infos, W.layouts, W.layoutBlob = {}, {}, {}, ""
    C_CooldownViewer = {
        GetCooldownViewerCategorySet = function(category, allow)
            assert(allow == true)
            Count("GetCooldownViewerCategorySet")
            return W.sets[category] or {}
        end,
        GetCooldownViewerCooldownInfo = function(id)
            assert(not IsSecret(id), "a secret cooldownID reached the info read")
            Count("GetCooldownViewerCooldownInfo")
            return W.infos[id]
        end,
        GetLayoutData = function() Count("GetLayoutData"); return W.layoutBlob end,
    }
    C_EncodingUtil = { DecodeBase64 = function(s) return s end, DecompressString = function(s) return s end,
        DeserializeCBOR = function(s) return W.layouts[s] end }
    W.specIndex, W.classID = 3, 8
    UnitClass = function() return "Mage", "MAGE", W.classID end
    C_SpecializationInfo = { GetSpecialization = function() return W.specIndex end }
    W.known = {}
    C_Spell = {
        GetSpellName = function(id) Count("GetSpellName"); return "Spell " .. id end,
        GetSpellTexture = function(id) Count("GetSpellTexture"); return 100000 + id end,
        GetBaseSpell = function(id) return id end,
        GetSpellCharges = function() Count("GetSpellCharges") end,
        SpellHasRange = function() Count("SpellHasRange"); return false end,
        GetSpellCooldownDuration = function() end,
        IsSpellHarmful = function() return false end,
    }
    C_SpellBook = {
        FindSpellOverrideByID = function() end,
        IsSpellKnownOrInSpellBook = function(id, bank)
            Count("IsSpellKnownOrInSpellBook")
            return bank == nil and W.known[id] == true
        end,
    }
    W.equipped = { [13] = 5555, [14] = 5566 }
    GetInventoryItemID = function(_, slot) return W.equipped[slot] end
    GetInventoryItemTexture = function(_, slot) return W.equipped[slot] and 9000 + slot end
    C_PaperDollInfo = { GetInventorySlotInfoForInvSlot = function(slot) return slot, 136528 end }
    C_Item = {
        GetItemIconByID = function(id) return 700000 + id end,
        GetItemNameByID = function(id) return "Item " .. id end,
        GetItemSpell = function(id) return "Use", 800000 + id end,
    }
    C_EventUtils = { IsEventValid = function() return true end }
    IsLoggedIn = function() return true end
    CreateFrame = function()
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(key, fn) self.scripts[key] = fn end
        return frame
    end

    local S = { Public = function(v) return not IsSecret(v) end, Text = function(v) return v end,
        CreateFrame = function(...) return CreateFrame(...) end }
    local P = { NS = NS, Suite = S }
    P.CDM = { M = { active = true }, EMPTY = {}, Diagnostics = {}, state = {}, views = {}, plans = {}, bars = {}, entries = {},
        lists = NS.CDM.CleanLists(nil), spells = NS.CDM.CleanSpells(nil),
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end }
    local C = P.CDM
    W.P, W.S, W.C = P, S, C
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/Const.lua"))("MSUF_Suite_CooldownManager", P)
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/AuraTimers.lua"))("MSUF_Suite_CooldownManager", P)
    for _, file in ipairs({ "Presets.lua", "GuideProfiles.lua", "Catalog.lua", "CatalogSlices.lua", "EntryFill.lua", "Resolve.lua", "ResolveStages.lua", "Index.lua" }) do
        local override = os.getenv("SUITE_CDM_" .. file:sub(1, -5):upper() .. "_SOURCE")
        assert(loadfile(override or root .. "/MSUF_Suite_CooldownManager/" .. file))("MSUF_Suite_CooldownManager", P)
    end

    -- One view per slot: built-in bars on, custom bars off.
    function W.Views()
        for _, def in ipairs(NS.CDM.SLOTS) do
            C.views[def.key] = { key = def.key, index = NS.CDM.SLOT_INDEX[def.key], kind = def.kind or 1, builtin = def.builtin == true,
                on = def.builtin == true, range = true, usable = true, procGlow = true, showAura = true, charges = true, assist = false }
        end
    end
    -- Lua VM instructions of the CDM runtime files while fn runs (GC stopped).
    function W.Cost(fn, ...)
        local n = 0
        collectgarbage("stop")
        debug.sethook(function()
            local info = debug.getinfo(2, "S")
            if info and info.source:find("MSUF_Suite_CooldownManager", 1, true) then n = n + 1 end
        end, "", 1)
        local a, b = fn(...)
        debug.sethook()
        collectgarbage("restart")
        return n, a, b
    end
    function W.Reset() for key in pairs(W.natives) do W.natives[key] = nil end end
    return W
end
