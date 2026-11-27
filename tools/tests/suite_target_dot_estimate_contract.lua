local root = assert(arg[1])
local file = assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TargetDotEstimate.lua"))
local secret = {}

local function Run(locale, description)
    local combat, enteringCombat, restricted = false, false, false
    local fill, reverse, auras = {}, false, {}
    local health, shade, moves = 800, nil, 0
    local handlers, module = {}, nil
    local bar = {}
    local function Public(value) return value ~= secret end
    function bar:CreateTexture()
        assert(not combat and not enteringCombat, "texture created at combat entry")
        shade = {}
        function shade:Hide() self.visible = false end
        function shade:Show() self.visible = true end
        function shade:ClearAllPoints()
            assert(not combat and not enteringCombat, "anchor cleared in combat")
        end
        function shade:SetPoint(point, parent, relativePoint)
            assert(not combat and not enteringCombat, "anchor changed in combat")
            assert(point == relativePoint and parent == fill, "wrong fill anchor")
            self.edge, moves = point, moves + 1
        end
        function shade:SetSize(width, height) self.width, self.height = width, height end
        function shade:SetColorTexture() end
        return shade
    end
    function bar:GetStatusBarTexture() return fill end
    function bar:GetReverseFill() return reverse end
    function bar:GetWidth() return 100 end
    function bar:GetHeight() return 20 end

    C_Secrets = { ShouldAurasBeSecret = function() return restricted end }
    C_UnitAuras = { GetUnitAuras = function(unit, filter, maximum)
        assert(not restricted and unit == "target" and filter == "HARMFUL|PLAYER" and maximum == 32)
        return auras
    end }
    C_Spell = { GetSpellDescription = function() return description end }
    canaccesstable = Public
    GetLocale = function() return locale end
    GetTime = function() return 10 end
    UnitCanAttack = function() return true end
    UnitHealth = function() return health end
    UnitHealthMax = function() return 1000 end
    wipe = function(value) for key in pairs(value) do value[key] = nil end end

    local ns = {
        InCombat = function(event) return event == "PLAYER_REGEN_DISABLED" or combat end,
        HostBridge = { TargetHealthAnchor = function() return bar end },
        Safety = { CanAnchor = Public },
    }
    local suite = {
        Public = Public,
        PublicText = function(value) return Public(value) and type(value) == "string" and value or nil end,
        Finite = function(value) return Public(value) and type(value) == "number" and math.abs(value) < math.huge end,
        Install = function(id, value)
            assert(id == "targetDotEstimate")
            module = value
        end,
    }
    file("MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
    module.config = { opacity = 55 }
    module.context = { Event = function(_, event, callback, options, unit)
        assert(options.inCombat == true)
        if event == "UNIT_AURA" or event == "UNIT_HEALTH" then assert(unit == "target") end
        handlers[event] = callback
    end }

    local function Fire(event)
        local handler = assert(handlers[event], "missing " .. event)
        handler(module, event, "target")
    end
    local function ApplyDoT() auras[1] = { spellId = 123, duration = 12, expirationTime = 16 } end
    module:Enable()
    assert(shade and not shade.visible, "idle preparation must leave the overlay hidden")
    enteringCombat = true
    Fire("PLAYER_REGEN_DISABLED")
    enteringCombat, combat = false, true
    ApplyDoT()
    Fire("UNIT_AURA")
    assert(shade.visible and shade.edge == "RIGHT" and shade.width == 60 and shade.height == 20,
        "the first DoT after combat starts must show its overlay")

    health = secret
    Fire("UNIT_HEALTH")
    assert(not shade.visible, "secret health must hide the overlay")
    health = 800
    Fire("UNIT_HEALTH")
    assert(shade.visible, "the overlay must resume when health is public")
    restricted = true
    Fire("UNIT_AURA")
    assert(not shade.visible, "aura restrictions must hide the overlay")
    restricted = false
    Fire("UNIT_AURA")
    assert(shade.visible, "the overlay must resume when aura data are public")

    fill, reverse = {}, true
    Fire("UNIT_HEALTH")
    assert(not shade.visible and moves == 1, "changed fill must defer reanchoring in combat")
    auras[1], combat = nil, false
    Fire("PLAYER_REGEN_ENABLED")
    assert(not shade.visible and moves == 2 and shade.edge == "LEFT", "rebind changed fill before the next DoT")
    ApplyDoT()
    enteringCombat = true
    Fire("UNIT_AURA")
    Fire("PLAYER_REGEN_DISABLED")
    enteringCombat, combat = false, true
    assert(shade.visible and shade.edge == "LEFT" and shade.width == 60,
        "combat entry must preserve the first DoT even when UNIT_AURA arrives first")

    combat, enteringCombat, fill = false, true, {}
    Fire("PLAYER_REGEN_DISABLED")
    assert(not shade.visible and moves == 2, "combat entry must defer anchoring even before the combat flag")
    module:Disable()
    assert(not shade.visible)
end

Run("enUS", "Inflicts 1,200 Shadow damage over 12 sec.")
Run("deDE", "Verursacht 1.200 Schattenschaden im Verlauf von 12 Sek.")
print("Target DoT estimate combat entry and anchor lifecycle validated")
