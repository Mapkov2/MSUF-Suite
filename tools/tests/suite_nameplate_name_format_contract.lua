local root = assert(arg[1]):gsub("\\", "/")
local host = root .. "/../MidnightSimpleUnitFrames-7.0"
local MenuWorld = assert(loadfile(host .. "/tools/tests/menu_core_world.lua"))()
local ClientWorld = assert(loadfile(host .. "/tools/tests/client_world.lua"))()
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local secret = {}
    local isPlayer, tapped, classSecret = false, false, false
    local world = ClientWorld.New(host, flavor)
    world.env.issecretvalue = function(v) return rawequal(v, secret) end
    world.env.UnitExists = function(unit) return unit == "nameplate1" end
    world.env.UnitIsPlayer = function(unit) return unit == "player" or isPlayer end
    world.env.UnitIsTapDenied = function() return tapped end
    world.env.UnitReaction = function() return 3 end
    world.env.UnitCanAttack = function() return true end
    world.env.UnitClassification = function() return "normal" end
    local classColor = { r = .78, g = .61, b = .43 }
    world.env.RAID_CLASS_COLORS, world.env.CUSTOM_CLASS_COLORS = { WARRIOR = classColor }, false
    world.env.C_ClassColor = { GetClassColor = function() return classColor end }
    world.env.UnitClass = function(unit)
        if unit == "nameplate1" and classSecret then return secret, secret, secret end
        return "Warrior", "WARRIOR", 1
    end
    world.env.MAX_BOSS_FRAMES = 5
    world:Boot()
    local mw = MenuWorld.Open(host, flavor, { open = false, world = world })
    local engine = assert(mw.core.HostAPI.GetNameFormatter(), "host name formatter is missing")
    local db = mw.M.EnsureDB()
    db.general.nameFormat, db.general.shortenNameMaxChars = "ABBREV_CUT", 14
    db.general.shortenNameClipSide, db.general.shortenNameShowDots = "RIGHT", false
    db.general.fontSize, db.general.fontShadowOpacity, db.general.fontShadowDistance = 19, .35, 2
    db.general.textBackdrop, db.general.nameColorMode = true, "CUSTOM"
    db.general.nameColorR, db.general.nameColorG, db.general.nameColorB = .2, .4, .6
    db.general.fontTextAlpha = .8
    -- This contract retains the optional version-1 legacy provider matrix.
    -- The standard native scope is covered by the real Fonts-page contract.
    local legacy = {}
    for key, value in pairs(engine) do if key ~= "Nameplates" then legacy[key] = value end end
    local provider = legacy
    local combat, checks, reads, writes, hooks = false, 0, 0, 0, 0
    local S = {
        Public = function(v) return not rawequal(v, secret) end,
        Finite = function(v) return not rawequal(v, secret) and type(v) == "number" and v == v end,
        RGB = function(hex) return tonumber(hex:sub(1, 2), 16)/255, tonumber(hex:sub(3, 4), 16)/255,
            tonumber(hex:sub(5, 6), 16)/255 end,
        SetFont = function(label, ...) label:SetFont(...) end,
    }
    local NS = { Suite = S, RGB = S.RGB, Finite = S.Finite, Client = { isForever = flavor == "Forever" }, NameplateStyle = { Font = function(key) return key end,
            FontFlags = function(value) return value == 2 and "THICKOUTLINE" or "OUTLINE" end },
        HostBridge = { NameFormatter = function() return provider end },
        Safety = { IsForbidden = function(f) checks = checks + 1 return f.forbidden == true end },
        IsCombatLocked = function() return combat end }
    assert(loadfile(os.getenv("SUITE_NAME_TEXT_HELPER_OVERRIDE") or root .. "/MSUF_Suite/Core/NameplateText.lua"))("Suite", NS)
    local private = { NS = NS, Suite = S }
    local callback
    hooksecurefunc = function(name, fn)
        assert(name == "CompactUnitFrame_UpdateName")
        callback, hooks = fn, hooks + 1
    end
    assert(loadfile(os.getenv("SUITE_NAME_FORMAT_OVERRIDE") or root .. "/MSUF_Suite_Nameplates/NameText.lua"))("Nameplates", private)
    local Names = private.NameText
    local config = { enemy = true, friendly = true, nameFormattingEnabled = true }
    local module = { active = true, config = config, pendingPlates = {}, activeUnits = {} }
    Names.Bind(module)
    local label = { value = "Ravenous Twilight Shadowcaster", r = .9, g = .7, b = .5, a = 1, shown = true }
    function label:GetText() reads = reads + 1 return self.value end
    function label:SetText(v) writes = writes + 1 self.value = v end
    function label:GetTextColor() reads = reads + 1 return self.r, self.g, self.b, self.a end
    function label:SetVertexColor(r,g,b,a) writes = writes + 1 self.r,self.g,self.b,self.a = r,g,b,a or 1 end
    label.SetTextColor = label.SetVertexColor
    function label:IsShown() reads = reads + 1 return self.shown end
    function label:IsProtected() return self.protected == true end
    local uf = { name = label }
    function uf:IsProtected() return self.protected == true end
    module.activeUnits.nameplate1 = uf
    Names.Configure(config)
    Names.Apply(uf, "enemy", "nameplate1")
    assert(label.value == "R. T. Shadowca", "Shared name format was not inherited")
    assert(label.r == .2 and label.g == .4 and label.b == .6 and label.a == .8, "Shared custom name color was not inherited: " .. tostring(label.r) .. "," .. tostring(label.g) .. "," .. tostring(label.b) .. "," .. tostring(label.a))
    local shared = NS.NameplateText.Shared(config)
    assert(shared.fontSize == 19 and shared.fontShadowAlpha == .35 and shared.fontShadowX == 2,
        "Shared typography getter differs from unit configuration")
    config.enemyNameColorEnabled, config.enemyNameColor = true, "00ff00"
    Names.Configure(config)
    Names.Apply(uf, "enemy", "nameplate1")
    assert(label.g == 1 and label.a == .8, "local RGB override dropped Shared opacity")
    config.enemyNameColorEnabled = false
    Names.Configure(config)
    Names.Apply(uf, "enemy", "nameplate1")
    local out = label.value
    reads, writes, checks = 0, 0, 0
    for i = 1, 10000 do Names.Apply(uf, "enemy", "nameplate1") end
    assert(reads == 0 and writes == 0 and checks == 0, "warm skin passes perform native name work")
    local function Native(text)
        label.value, label.r, label.g, label.b, label.a = text, .9, .7, .5, 1
        callback(uf)
    end
    Native("Ancient Twilight Archmage")
    assert(label.value == "A. T. Archmage", "native name reset was not reformatted")
    combat, uf.protected = true, true
    Native("Ancient Twilight Sorcerer")
    assert(module.pendingPlates[uf], "protected native update was not queued")
    combat, uf.protected = false, false
    Names.Apply(uf, "enemy", "nameplate1")
    assert(label.value == "A. T. Sorcerer", "protected native replay hit a stale warm cache")
    Native("Ancient Twilight Archmage")
    module.activeUnits.nameplate1 = {}
    Native("Unmapped Native")
    assert(label.value == "Unmapped Native", "native hook repainted an unmapped plate")
    module.activeUnits.nameplate1 = uf
    Native("Ancient Twilight Archmage")
    label.shown = false
    callback(uf)
    label.shown = true
    config.nameTextUseCustomSettings = true
    config.enemyNameFormat, config.enemyNameMaxChars = 2, 7
    config.enemyNameNoEllipsis = true
    config.enemyNameColorEnabled, config.enemyNameColor = true, "00ff00"
    Names.Configure(config)
    Names.Apply(uf, "enemy", "nameplate1")
    assert(label.value == "Ancient" and label.g == 1, "local format/color override failed")
    config.enemyNameFormat, config.enemyNameMaxChars = 4, 5
    config.enemyNameClipSide = 2
    Names.Configure(config)
    Names.Apply(uf, "enemy", "nameplate1")
    assert(label.value == "hmage", "length/direction override failed")
    label.shown = false
    callback(uf)
    config.nameFormattingEnabled, config.enemyNameColorEnabled = false, false
    Names.Configure(config)
    Names.Apply(uf, "enemy", "nameplate1")
    assert(label.value == "Ancient Twilight Archmage" and label.r == .9, "disabled options failed to restore the native baseline")
    reads, writes, checks = 0, 0, 0
    for i = 1, 10000 do Names.Apply(uf, "enemy", "nameplate1") end
    assert(reads == 0 and writes == 0 and checks == 0, "disabled retained states perform native work")
    label.shown = true
    config.nameFormattingEnabled, config.enemyNameColorEnabled = true, true
    Names.Configure(config)
    Names.Apply(uf, "enemy", "nameplate1")
    label.shown, label.value = false, secret
    callback(uf)
    config.nameFormattingEnabled, config.enemyNameColorEnabled = false, false
    Names.Configure(config)
    Names.Apply(uf, "enemy", "nameplate1")
    assert(rawequal(label.value, secret) and Names.states[uf].raw == nil, "restoration overwrote/cached a hidden secret name")
    label.shown = true
    config.nameFormattingEnabled = true
    Names.Configure(config)
    Native(secret)
    assert(Names.states[uf].unit == "nameplate1" and Names.states[uf].raw == nil, "secret lost the public unit mapping")
    Native("Old Native Name")
    assert(label.value ~= "Old Native Name", "public name did not recover after secret input")
    combat, uf.protected = true, true
    module.activeUnits.nameplate1 = nil
    Names.Release(uf)
    assert(Names.states[uf].unit == nil and Names.states[uf].raw == nil, "protected release retained old identity")
    label.value, label.r, label.g, label.b = "New Native Wizard", .9, .7, .5
    combat, uf.protected = false, false
    module.activeUnits.nameplate1 = uf
    Names.Apply(uf, "enemy", "nameplate1")
    assert(label.value == "izard", "pooled same-token reuse repainted the old name")
    module.config.enemy = false
    Names.Apply(uf, "enemy", "nameplate1")
    Native("Unskinned Enemy")
    assert(label.value == "Unskinned Enemy", "disabled side was formatted by the native hook")
    module.config.enemy = true
    provider = nil
    Names.Configure(config)
    Names.Apply(uf, "enemy", "nameplate1")
    assert(label.value == "Unskinned Enemy", "old host changed an unformatted native name")
    config.enemyNameColorEnabled = true
    Names.Configure(config)
    Native("Old Host Color")
    Names.Apply(uf, "enemy", "nameplate1")
    assert(label.value == "Old Host Color" and label.g == 1, "old host color support depends on the formatter")
    provider = legacy
    Names.Configure(config)
    label.value, label.r, label.g, label.b, label.a = "Restricted Color", secret, .7, .5, 1
    callback(uf)
    assert(rawequal(label.r, secret), "a restricted native color was overwritten")
    Native("Warm Native Input")
    Native("Warm Native Input")
    local function Allocation()
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for i = 1, 1000 do Native("Warm Native Input") end
        local delta = collectgarbage("count") - before
        collectgarbage("restart")
        return delta
    end
    local allocated = math.min(Allocation(), Allocation())
    assert(allocated < .05, "repeated native names allocated " .. allocated .. " KB")
    assert(hooks == 1, "name posthook installed more than once")
    provider, config.nameTextUseCustomSettings, config.enemyNameColorEnabled = engine, false, false
    local stored = config.enemyNameMaxChars
    db.general.nameFormat = "ABBREV_SHORT"
    assert(NS.NameplateText.InheritedValue(config, "enemyNameFormat") == 4)
    assert(NS.NameplateText.InheritedValue(config, "enemyNameMaxChars") == 10)
    assert(NS.NameplateText.InheritedValue(config, "enemyNameClipSide") == 1)
    assert(NS.NameplateText.InheritedValue(config, "enemyNameNoEllipsis") == true)
    assert(config.enemyNameMaxChars == stored, "showing Shared values rewrote local overrides")
    db.general.nameFormat = "ABBREV_CUT"
    db.general.nameColorMode, db.general.nameClassColor = "CLASS", true
    db.general.npcNameRed, db.general.nameNpcClassColor, db.general.npcColorMode = false, false, "reaction"
    local colors = engine.Shared({})
    local r,g,b = engine.SampleColor({ MSUFSpec = colors, _msufPortraitSampleClass = "WARRIOR" }, "enemy")
    assert(r == colors.textColor.r and g == colors.textColor.g and b == colors.textColor.b,
        "NPC sample inherited the player-only class color")
    db.general.npcColorMode, db.general.npcTypeColorText, db.general.npcTypeTarget = "type", true, false
    colors = engine.Shared({})
    assert(colors.key == "nameplates" and colors.text.npcColorMode == "type" and colors.text.npcTypeColorText,
        "Shared NPC type policy was not compiled for its independent nameplate scope")
    local er,eg,eb = mw.core.UFText.NPCColor("npcCaster")
    r,g,b = engine.SampleColor({ MSUFSpec = colors }, "enemy")
    assert(r == er and g == eg and b == eb, "NPC type sample differs from the core palette")
    assert(colors.text.tapDeniedGray == (mw.core.Client.SupportsTapDenied == true), "client tagged-mob policy was lost")
    db.general.tapDeniedGray = false
    assert(engine.Shared({}).text.tapDeniedGray == false, "tagged-mob opt-out was lost")
    config.nameTextUseCustomSettings, config.nameFormattingEnabled = false, true
    isPlayer = true
    Names.Begin(uf)
    Names.Configure(config)
    Native("Player Example")
    Names.Apply(uf, "enemy", "nameplate1")
    assert(label.r == .78 and label.g == .61 and label.b == .43, "Shared player class color was not applied: " .. tostring(label.r) .. "," .. tostring(label.g) .. "," .. tostring(label.b))
    isPlayer = false
    Names.Begin(uf)
    Names.Configure(config)
    Native("NPC Example")
    Names.Apply(uf, "enemy", "nameplate1")
    local state = Names.states[uf]
    local kind = mw.core.UFText.UnitNPCKind(state, "nameplate1", state.MSUFSpec, true)
    er,eg,eb = mw.core.UFText.NPCColor(kind)
    assert(label.r == er and label.g == eg and label.b == eb and kind ~= nil,
        "Shared NPC type color was not applied to the live nameplate")
    if mw.core.Client.SupportsTapDenied then
        tapped = true
        Names.Begin(uf)
        db.general.tapDeniedGray = true
        Names.Configure(config)
        Native("Tagged Example")
        Names.Apply(uf, "enemy", "nameplate1")
        assert(label.r == .5 and label.g == .5 and label.b == .5, "Shared tagged-mob gray was lost")
        tapped = false
    end
    db.general.npcColorMode = "reaction"
    isPlayer, classSecret = true, true
    Names.Begin(uf)
    Names.Configure(config)
    Native("Restricted Player")
    Names.Apply(uf, "enemy", "nameplate1")
    assert(S.Finite(label.r) and S.Finite(label.g) and S.Finite(label.b), "restricted class color escaped the engine safety policy")
    isPlayer, classSecret = false, false
    db.general.nameColorMode, db.general.npcColorMode = "CUSTOM", "reaction"
    assert(engine.Shared({}).text.npcTypeColorText == false, "custom name color lost precedence over NPC type")
    config.nameTextUseCustomSettings = true
    config.enemyNameFont, config.enemyNameSize, config.enemyTextOutline, config.enemyTextShadow = "Custom Face", 23, 2, true
    local ownStyle = NS.NameplateText.FontStyle(config, "enemy")
    assert(ownStyle.font == "Custom Face" and ownStyle.size == 23 and ownStyle.flags == "THICKOUTLINE" and ownStyle.shadow,
        "custom preview/runtime typography compiler differs")
    config.nameTextUseCustomSettings = false
    local sampleLook = NS.NameplateText.Compile(config, "friendly")
    local sample = NS.NameplateText.Sample("friendly")
    assert(sample == (flavor == "Forever" and "Alexandriana Brightwhisper" or "Alexandriana"))
    Names.Begin(uf)
    Names.Configure(config)
    Native("Warm Native Input")
    Names.Apply(uf, "enemy", "nameplate1")
    Native("Warm Native Input")
    assert(math.min(Allocation(), Allocation()) < .05, "Shared color/name warm path allocates")
    -- The full-name no-write check exercises the legacy Suite settings.
    -- The native provider takes both formatting and color from the host scope.
    provider, config.nameTextUseCustomSettings, config.enemyNameFormat = legacy, true, 1
    Names.Configure(config)
    Native("Unchanged Full Name")
    writes = 0
    Native("Unchanged Full Name")
    assert(writes == 0, "unchanged full names issue redundant native writes")
    NS.NameplateText.Paint(label, {}, sample, sampleLook)
    assert(label.value == engine.Format({}, sample, "ABBREV_CUT", 14, false, "RIGHT"), "preview differs from runtime formatter")
    print("PASS nameplate names " .. flavor .. ": Shared/local/color, native reset, secret recovery, disabled/warm 10000 zero native calls, pool and old-host parity")
end
