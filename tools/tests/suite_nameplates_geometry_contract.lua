local root = assert(arg[1])
local combat, style, calls = false, 0, 0
local NS = {
    Client = { isMainline = true, isForever = false },
    Public = function(v) return v ~= "secret" end,
    Finite = function(v) return type(v) == "number" and v == v end,
    IsCombatLocked = function() return combat end,
    Safety = { IsForbidden = function(r)
        if r.forbiddenChecks then r.forbiddenChecks = r.forbiddenChecks + 1 end
        return r.forbidden == true
    end },
    HostBridge = { NameFormatter = function() end },
}
C_CVar = { GetCVar = function() return tostring(style) end, GetCVarBool = function() return false end }
-- Blizzard_SharedXMLBase PixelUtil; the pixel snap itself is the engine's.
PixelUtil = { SetPoint = function(region, ...) region:SetPoint(...) end }
-- The plate is a hostile NPC: Forever's level badge rule shows the badge.
UnitIsGameObject = function(unit) assert(unit == "nameplate1"); return false end
UnitIsFriend = function(_, unit) assert(unit == "nameplate1"); return false end
UnitIsPlayer = function(unit) assert(unit == "nameplate1"); return false end
local textureAnchors, extensionAnchors = 0, 0
-- The cold-layout handoff: the plate and the cast height it had when the
-- layout owner reported its final geometry.
local layouts, layoutPlate, layoutHeight = 0, nil, nil
local private = { NS = NS,
    Textures = { inUse = true, OnAnchors = function() textureAnchors = textureAnchors + 1 end,
        OnLayout = function(uf)
            layouts, layoutPlate = layouts + 1, uf
            layoutHeight = uf.CastBarsContainer.castBar.height
        end },
    Extensions = { OnAnchors = function() extensionAnchors = extensionAnchors + 1 end } }
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateAuraDisplay.lua"))("MSUF_Suite", NS)
NS.NameplatePortableText = { Stored = function() end, Resolve = function() end }
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateText.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Modes.lua"))("MSUF_Suite_Nameplates", private)
assert(loadfile(arg[2] or root .. "/MSUF_Suite_Nameplates/Geometry.lua"))("MSUF_Suite_Nameplates", private)
assert(loadfile(arg[3] or root .. "/MSUF_Suite_Nameplates/Layout.lua"))("MSUF_Suite_Nameplates", private)
local function Frame()
    local f = { points = {} }
    function f:SetPoint(point, owner, relative, x, y)
        calls = calls + 1
        self.points[point] = { owner, relative, x, y }
    end
    function f:SetHeight(h) calls = calls + 1; self.height = h end
    function f:SetSize(w, h) calls = calls + 1; self.width, self.height = w, h end
    function f:SetPointsOffset(x, y) calls = calls + 1; self.x, self.y = x, y end
    function f:IsShown() return self.shown end
    function f:IsProtected() return self.protected == true end
    function f:GetEffectiveScale() return self.restrictedScale and "secret" or 1 end
    function f:CanBeAccessedInContext() return not self.restricted end
    function f:GetScale() return self.scale or 1 end
    function f:SetScale(v) calls = calls + 1; self.scale = v end
    function f:GetAlpha() return self.alpha or 1 end
    function f:SetAlpha(v) calls = calls + 1; self.alpha = v end
    function f:GetFrameLevel() return self.layer or 4 end
    function f:SetFrameLevel(v) calls = calls + 1; self.layer = v end
    function f:GetPoint() error("restricted anchor read") end
    function f:GetWidth() error("restricted dimension read") end
    function f:GetTexCoord() return unpack(self.coords or { 0, 0, 0, 1, 1, 0, 1, 1 }) end
    function f:SetTexCoord(...) self.coords = { ... } end
    return f
end
hooksecurefunc = function(uf, method, callback) uf.hook = callback end
local module = { active = true, activeUnits = {}, levelLabels = {}, castTimes = {}, pendingPlates = {} }
private.Layout.Bind(module)
local setup
local function Native(uf)
    local cast, health = uf.CastBarsContainer, uf.HealthBarsContainer
    cast:SetPoint("BOTTOMLEFT", uf, "BOTTOMLEFT", setup.insetWidth, 0)
    cast:SetPoint("BOTTOMRIGHT", uf, "BOTTOMRIGHT", -setup.insetWidth, 0)
    health:SetPoint("BOTTOMLEFT", cast, "TOPLEFT", 0, setup.castBarToHealthBarSpacing)
    health:SetPoint("BOTTOMRIGHT", cast, "TOPRIGHT", NS.Client.isForever and -33 or 0, setup.castBarToHealthBarSpacing)
    cast:SetHeight(setup.castBarHeight + (setup.spellNameInsideCastBar and 0 or setup.castIconHeight))
    cast.castBar:SetHeight(setup.castBarHeight)
    cast.castBar.Icon:SetSize(setup.castIconWidth, setup.castIconHeight)
    if cast.castBar.Text then cast.castBar.Text:SetPointsOffset(0, 0) end
    if setup.useClassicCastBar then
        local h, y = setup.horizontalScale, .5 * setup.verticalScale
        cast.castBar:SetPoint("TOPLEFT", cast, "TOPLEFT", 20.75 * h, y)
        cast.castBar:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", -3.5 * h, y)
        cast.castBar.Border:SetSize(setup.castBarBorderWidth, setup.castBarBorderHeight)
    elseif setup.spellNameInsideCastBar then
        cast.castBar:SetPoint("TOPLEFT", cast, "TOPLEFT", 0, 0)
        cast.castBar:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", 0, 0)
    else
        cast.castBar:SetPoint("LEFT", cast, "BOTTOMLEFT", 0, 0)
        cast.castBar:SetPoint("RIGHT", cast, "BOTTOMRIGHT", 0, 0)
        cast.castBar.Icon:SetPoint("BOTTOMLEFT", cast, "BOTTOMLEFT", 0, 0)
        cast.castBar:SetPoint("BOTTOM", cast.castBar.Icon, "TOP", 0, 0)
    end
    health:SetHeight(setup.healthBarHeight)
    for _, key in ipairs({ "CrowdControlListFrame", "LossOfControlFrame" }) do
        uf.AurasFrame[key]:SetPoint("LEFT", health, "RIGHT", NS.Client.isForever and 38 or 5, 0)
    end
end
for _, forever in ipairs({ false, true }) do
    NS.Client.isForever = forever
    -- The width constants are named NAMEPLATE_WIDTH on Retail and
    -- NAME_PLATE_WIDTH in Forever's Camelot constants.
    NamePlateConstants = forever and { NAME_PLATE_WIDTH = 190, CLASSIC_NAME_PLATE_WIDTH = 152 }
        or { NAMEPLATE_WIDTH = 230, CLASSIC_NAMEPLATE_WIDTH = 152 }
    local nativeWidth = forever and 190 or 230
    for _, scale in ipairs({ .8, 1, 1.25, 1.6 }) do
        for _, selected in ipairs({ 0, 1, 2, 3, 4, 5, 6 }) do
            style = selected
            local classic = style == 6
            local baseWidth = classic and 152 or nativeWidth
            local largeHealth = style == 0 or style == 2 or style == 3
            local largeCast = style == 2 or style == 4
            setup = { horizontalScale = scale, verticalScale = scale,
                insetWidth = 12 * scale, castBarToHealthBarSpacing = 2 * scale,
                healthBarHeight = (largeHealth and 20 or forever and 13 or 10) * scale,
                castBarHeight = (largeCast and 16 or forever and 6 or 10) * scale,
                castIconHeight = (forever and 10 or 12) * scale,
                castIconWidth = (forever and 11 or 13) * scale,
                castBarBorderWidth = 128 * scale, castBarBorderHeight = 31 * scale,
                playerLevelDiffWidth = 28, useClassicCastBar = classic, useClassicHealthBar = classic,
                spellNameInsideCastBar = classic or largeCast, unitNameAnchorStyle = 1 }
            NamePlateSetupOptions = setup
            local uf = Frame()
            uf.unit, uf.showOnlyName, uf.isFriend, uf.UpdateAnchors = "nameplate1", false, false, function() end
            module.activeUnits[uf.unit] = uf
            uf.HealthBarsContainer, uf.CastBarsContainer = Frame(), Frame()
            uf.HealthBarsContainer.healthBar = Frame()
            uf.CastBarsContainer.castBar = Frame()
            uf.CastBarsContainer.castBar.Icon, uf.CastBarsContainer.castBar.Border = Frame(), Frame()
            uf.PlayerLevelDiffFrame = Frame(); uf.PlayerLevelDiffFrame.shown = true
            uf.AurasFrame = Frame()
            local auras = uf.AurasFrame
            auras.BuffListFrame, auras.DebuffListFrame = Frame(), Frame()
            auras.CrowdControlListFrame, auras.LossOfControlFrame = Frame(), Frame()
            Native(uf)
            if style == 0 and scale == 1 then
                local layout, row = private.Layout, auras.BuffListFrame
                local auraConfig = { look = 1, enemy = true, barGeometry = 1,
                    auraEnemyBuffScale = 150, auraEnemyBuffAlpha = 40, auraEnemyBuffLayer = 2 }
                layout.Configure(auraConfig)
                row.restricted = true
                layout.Apply(uf, "enemy", auraConfig)
                assert(module.pendingPlates[uf] and not row.scale)
                row.restricted, module.pendingPlates[uf] = nil, nil
                layout.Apply(uf, "enemy", auraConfig)
                assert(row.scale == 1.5 and row.alpha == .4 and row.layer == 6,
                    "a newly accessible native row missed the ordinary pending-plate replay")
                layout.Restore(uf, true)
                local getScale = row.GetScale
                row.GetScale = function() return "secret" end
                module.pendingPlates[uf] = nil
                layout.Apply(uf, "enemy", auraConfig)
                assert(module.pendingPlates[uf] and row.scale == 1 and row.alpha == .4 and row.layer == 6,
                    "a restricted scale lost its retry or prevented public alpha and layer writes")
                row.GetScale, module.pendingPlates[uf] = getScale, nil
                local before = calls
                layout.Apply(uf, "enemy", auraConfig)
                assert(row.scale == 1.5 and calls == before + 1, "retry repeated other row or geometry writes")
                layout.Restore(uf, true)
                auras.restricted = true
                layout.Apply(uf, "enemy", auraConfig)
                auraConfig.auraEnemyBuffScale, auraConfig.auraEnemyBuffAlpha, auraConfig.auraEnemyBuffLayer = 100, 100, 0
                auraConfig.auraEnemyDebuffScale = 175
                layout.Configure(auraConfig)
                layout.Apply(uf, "enemy", auraConfig)
                auras.restricted = nil
                layout.Apply(uf, "enemy", auraConfig)
                assert(auras.DebuffListFrame.scale == 1.75 and row.scale == 1 and row.alpha == 1 and row.layer == 4,
                    "the container replay applied a stale row plan after a profile change")
                layout.Restore(uf, true)
                auras.DebuffListFrame.scale, auraConfig.auraEnemyDebuffScale = nil, nil
                auraConfig.auraEnemyBuffScale = 150
                layout.Configure(auraConfig)
                row.GetScale = function() return "secret" end
                layout.Apply(uf, "enemy", auraConfig)
                row.restricted, module.pendingPlates[uf] = true, nil
                layout.Restore(uf, true)
                assert(not module.pendingPlates[uf], "a never-owned restricted property demanded a restore")
                row.restricted, row.GetScale = nil, getScale
                auraConfig.auraEnemyBuffScale, auraConfig.auraEnemyBuffAlpha, auraConfig.auraEnemyBuffLayer = 150, 40, 2
                layout.Configure(auraConfig)
                local function AuraCycle()
                    layout.Apply(uf, "enemy", auraConfig)
                    assert(row.scale == 1.5 and row.alpha == .4 and row.layer == 6,
                        "an empty native row was not ready for Blizzard's first icon")
                    layout.Restore(uf, true)
                    assert(row.scale == 1 and row.alpha == 1 and row.layer == 4)
                end
                AuraCycle()
                collectgarbage("collect")
                collectgarbage("stop")
                local before = collectgarbage("count")
                for _ = 1, 100 do AuraCycle() end
                local growth = collectgarbage("count") - before
                collectgarbage("restart")
                print(("100 empty native aura-row leases: %.2f KB"):format(growth))
                assert(growth < 1, "empty native aura rows reallocated their property snapshots")
                row.scale, row.alpha, row.layer = 2, .5, 7
                layout.Apply(uf, "enemy", auraConfig)
                assert(row.scale == 3 and row.alpha == .2 and row.layer == 9)
                row.restricted = true
                layout.Restore(uf, true)
                assert(row.scale == 3 and module.pendingPlates[uf], "a denied native row restore lost ownership")
                row.restricted = nil
                layout.Restore(uf, true)
                assert(row.scale == 2 and row.alpha == .5 and row.layer == 7,
                    "row reuse restored the previous occupant's native properties")
                row.scale, row.alpha, row.layer = nil, nil, nil
                module.pendingPlates[uf] = nil
            end
            local config = { look = 4, barGeometry = 2, nativeStyle = style + 2, enemy = true,
                enemyHealthWidthDelta = 41, enemyHealthHeightDelta = 7 }
            module.config = config
            private.Layout.Configure(config)
            local firstLayout = layouts
            private.Layout.Apply(uf, "enemy", config)
            assert(layouts == firstLayout + 1 and layoutPlate == uf
                and layoutHeight == uf.CastBarsContainer.castBar.height,
                "the first layout pass did not hand its final cast geometry over exactly once")
            if selected == 0 and scale == 1 then
                local container = uf.CastBarsContainer
                local cast = container.castBar
                cast.Text = Frame()
                config.enemyCastHeight, config.enemyCastTextOffsetY = 16, 13
                private.Layout.Configure(config)
                private.Layout.Apply(uf, "enemy", config)
                private.Layout.InvalidateName(uf)
                combat = true
                local stableCalls = calls
                private.Layout.Apply(uf, "enemy", config)
                assert(calls == stableCalls, "name invalidation repeated the cast layout without a native rebuild")
                combat = false
                private.Layout.Restore(uf, true)
                combat = true
                Native(uf)
                private.Layout.Apply(uf, "enemy", config) -- A cold add in lockdown.
                assert(cast.height == 16 and cast.Text.y == 13
                    and container.points.BOTTOMLEFT[3] == setup.insetWidth + (baseWidth - 230) / 2,
                    "combat acquisition left the native cast size or text position")
                assert(uf.HealthBarsContainer.height == 27 and uf.HealthBarsContainer.points.BOTTOMLEFT[3] == -41,
                    "combat cast rebuild dropped the configured health size")
                if forever then
                    assert(auras.CrowdControlListFrame.points.LEFT[3] == 5 and auras.LossOfControlFrame.points.LEFT[3] == 5,
                        "combat cast rebuild displaced the control auras")
                end
                combat = false
                private.Layout.Apply(uf, "enemy", config)
                assert(cast.height == 16 and cast.Text.y == 13 and uf.HealthBarsContainer.height == 27,
                    "leaving combat changed a successfully applied cast layout")
                if forever then
                    assert(auras.CrowdControlListFrame.points.LEFT[3] == 5
                        and auras.LossOfControlFrame.points.LEFT[3] == 5,
                        "leaving combat displaced the control auras")
                end
                local afterCombatCalls = calls
                private.Layout.Apply(uf, "enemy", config)
                assert(calls == afterCombatCalls, "settled cast layout repeated writes after combat")

                combat = true
                Native(uf)
                uf.hook(uf)
                assert(cast.height == 16 and cast.Text.y == 13,
                    "combat rebuild lost the configured cast size or text position")
                local settledCalls = calls
                private.Layout.Apply(uf, "enemy", config)
                assert(calls == settledCalls, "unchanged combat cast geometry repeated writes")

                local timeLabel = Frame()
                cast.CastTargetNameText = Frame()
                module.castTimes[cast] = { label = timeLabel }
                local denied = {
                    { cast.Text, "protected" }, { timeLabel, "protected" },
                    { container, "restrictedScale" }, { cast.CastTargetNameText, "restrictedScale" },
                }
                if forever then
                    denied[#denied + 1] = { auras.CrowdControlListFrame, "protected" }
                end
                for _, deniedRegion in ipairs(denied) do
                    local region, flag = deniedRegion[1], deniedRegion[2]
                    module.pendingPlates[uf] = nil
                    region[flag] = true
                    Native(uf)
                    settledCalls = calls
                    uf.hook(uf)
                    assert(calls == settledCalls and module.pendingPlates[uf],
                        "unwritable cast layout changed geometry or lost its retry: " .. flag)
                    region[flag] = nil
                end
                module.castTimes[cast] = nil
                combat = false
                private.Layout.Apply(uf, "enemy", config)
                assert(cast.height == 16 and cast.Text.y == 13, "combat exit did not finish the cast layout")
                module.pendingPlates[uf] = nil
                config.enemyCastHeight, config.enemyCastTextOffsetY = nil, nil
                private.Layout.Configure(config)
                private.Layout.Apply(uf, "enemy", config)

                local buff, debuff = auras.BuffListFrame, auras.DebuffListFrame
                local cc, loc = auras.CrowdControlListFrame, auras.LossOfControlFrame
                cc.restricted = true
                config.auraEnemyBuffScale, config.auraEnemyControlAlpha, config.auraEnemyControlLayer = 150, 65, 3
                private.Layout.Configure(config)
                private.Layout.Apply(uf, "enemy", config)
                assert(buff.scale == 1.5 and not buff.alpha and not buff.layer and not debuff.scale)
                assert(loc.alpha == .65 and loc.layer == 7 and not cc.alpha and module.pendingPlates[uf])
                cc.restricted = false
                private.Layout.Reapply(uf, "enemy", config)
                assert(cc.alpha == .65 and cc.layer == 7 and loc.layer == 7)
                config.auraEnemyBuffScale, config.auraEnemyControlAlpha, config.auraEnemyControlLayer = 100, 100, 0
                private.Layout.Configure(config)
                private.Layout.Apply(uf, "enemy", config)
                assert(buff.scale == 1 and cc.alpha == 1 and cc.layer == 4 and loc.alpha == 1 and loc.layer == 4)
            end
            local cast, health = uf.CastBarsContainer, uf.HealthBarsContainer
            local function Near(a, b) assert(math.abs(a - b) < .00001, tostring(a) .. " ~= " .. tostring(b)) end
            local function Check()
                local width = baseWidth * scale
                    - cast.points.BOTTOMLEFT[3] + cast.points.BOTTOMRIGHT[3]
                local uniformWidth = (classic and 128 or 206) * scale
                Near(width, uniformWidth)
                Near(width - health.points.BOTTOMLEFT[3] + health.points.BOTTOMRIGHT[3], uniformWidth + 41)
                Near(health.height, (largeHealth and 20 or 10) * scale + 7)
                Near(cast.castBar.height, (largeCast and 16 or 10) * scale)
                Near(cast.castBar.Icon.height, (classic and 14 or 12) * scale)
                assert(uf.AurasFrame.CrowdControlListFrame.points.LEFT[3] == 5,
                    "invisible native badge still displaces portable control aura")
            end
            Check()
            local writes, settled = calls, layouts
            for _ = 1, 100 do private.Layout.Apply(uf, "enemy", config) end
            assert(calls == writes, "unchanged plate repeated geometry writes")
            assert(layouts == settled, "an unchanged plate repeated the cold-layout handoff")
            if selected == 0 and scale == 1 then
                -- Native SetUnit runs ApplyFrameOptions and OnUnitSet before
                -- the Suite receives NAME_PLATE_UNIT_ADDED for the reused frame.
                module.activeUnits[uf.unit] = nil
                local beforeRelease = calls
                private.Layout.Restore(uf, true)
                Near(cast.castBar.height, (largeCast and 16 or 10) * scale)
                local expected = 0
                assert(calls - beforeRelease == expected, "recycling rewrote geometry that Blizzard resets")
                local textures, extensions, skippedWrites, instructions = textureAnchors, extensionAnchors, 0, 0
                local pooledLayouts = layouts
                local prefix, prefixReads = private.PlatePrefix, 0
                private.PlatePrefix = function(frame)
                    prefixReads = prefixReads + 1
                    return prefix(frame)
                end
                for _ = 1, 3 do
                    Native(uf)
                    local nativeWrites = calls
                    debug.sethook(function() instructions = instructions + 1 end, "", 1)
                    uf.hook(uf)
                    debug.sethook()
                    skippedWrites = skippedWrites + calls - nativeWrites
                end
                print(("Pooled native setup (%s), three hooks: %d geometry writes, %d Lua instructions")
                    :format(forever and "Forever" or "Retail", skippedWrites, instructions))
                assert(skippedWrites == 0, "pooled setup repeated Suite geometry writes before add")
                private.PlatePrefix = prefix
                assert(prefixReads == 0, "an unbound returned frame still classified its side on native anchor rebuilds")
                assert(instructions < 240, "pooled setup exceeded the anchor hook instruction budget")
                assert(textureAnchors == textures + 3 and extensionAnchors == extensions + 3,
                    "pooled setup stopped notifying texture and extension owners")
                -- Blizzard's rebuild alone is the texture owner's edge (OnAnchors).
                assert(layouts == pooledLayouts, "a pass that wrote no Suite geometry handed a layout over")
                local isSuppressed = private.IsSkinSuppressed
                private.IsSkinSuppressed = function() return true end
                extensions = extensionAnchors
                uf.hook(uf)
                assert(extensionAnchors == extensions, "a suppressed unbound plate notified extension layout")
                private.IsSkinSuppressed = isSuppressed
                combat, module.pendingPlates[uf] = true, nil
                uf.hook(uf)
                assert(module.pendingPlates[uf], "cold layout swallowed the combat retry")
                combat, module.pendingPlates[uf] = false, nil
                module.activeUnits[uf.unit] = uf
                -- A native rebuild after the next binding must restore the
                -- configured geometry even before an explicit skin pass.
                uf.hook(uf)
                Check()
                private.Layout.Apply(uf, "enemy", config)
                Check()
                -- A recycled frame can still own fixed XML links after a
                -- combat-time removal could not restore its layout.
                local debuffs = auras.DebuffListFrame
                debuffs:SetPoint("LEFT", uf.HealthBarsContainer, "LEFT", 0, 0)
                config.enemyAurasOffsetX = 7
                GetCVarNumberOrDefault = function() return 0 end
                NamePlateConstants.DEBUFF_PADDING_CVAR = "padding"
                private.Layout.Configure(config)
                private.Layout.Apply(uf, "enemy", config)
                assert(debuffs.points.LEFT[3] == 7)
                local unit = uf.unit
                local combatLayouts = layouts
                combat = true
                module.activeUnits[unit] = nil
                private.Layout.Restore(uf)
                Native(uf)
                uf.hook(uf)
                assert(module.pendingPlates[uf] and debuffs.points.LEFT[3] == 7,
                    "combat reset lost its deferred fixed link")
                assert(layouts == combatLayouts, "a combat-locked pass handed a layout over")
                combat = false
                Native(uf)
                uf.hook(uf)
                assert(debuffs.points.LEFT[3] == 0, "recycled native reset did not restore the fixed XML link")
                config.enemyAurasOffsetX = 0
                private.Layout.Configure(config)
                module.activeUnits[unit] = uf
                private.Layout.Apply(uf, "enemy", config)
                Check()
                local soft = Frame()
                soft.forbiddenChecks, soft.forbidden, uf.SoftTargetFrame = 0, true, soft
                private.Layout.Reapply(uf, "enemy", config)
                assert(soft.forbiddenChecks == 0, "untouched zero offset probed native access")
                config.enemySoftTargetOffsetX = 8
                private.Layout.Configure(config)
                private.Layout.Apply(uf, "enemy", config)
                assert(soft.forbiddenChecks == 1 and soft.x == nil, "forbidden target marker was moved")
                soft.forbidden = false
                private.Layout.Reapply(uf, "enemy", config)
                assert(soft.forbiddenChecks == 2 and soft.x == 8, "allowed marker was not moved")
                private.Layout.Configure(config)
                private.Layout.Apply(uf, "enemy", config)
                assert(soft.forbiddenChecks == 2, "already applied offset probed native access")
                config.enemySoftTargetOffsetX = 0
                private.Layout.Configure(config)
                private.Layout.Apply(uf, "enemy", config)
                assert(soft.forbiddenChecks == 3 and soft.x == 0, "reset skipped native access or left the offset")
            end
            Native(uf); uf.hook(uf); Check()
            -- Dragging changes the preset label, never the saved size basis.
            config.look = 3
            private.Layout.Configure(config); private.Layout.Apply(uf, "enemy", config); Check()
            config.enemyCastHeight, config.enemyCastIconSize, config.enemyCastWidthDelta = 28, 40, 36
            config.enemyCastOffsetX, config.enemyCastOffsetY = 9, -4
            config.enemyCastIconOffsetX, config.enemyCastIconOffsetY = 11, 8
            -- Switching from offsets-only to explicit width must release the
            -- old SetPointsOffset before composing both values into the edges.
            config.enemyCastWidthDelta = 0
            private.Layout.Configure(config); private.Layout.Apply(uf, "enemy", config)
            assert(cast.castBar.x == 9 and cast.castBar.y == -4)
            config.enemyCastWidthDelta = 36
            private.Layout.Configure(config); private.Layout.Apply(uf, "enemy", config)
            local function CheckCastWidth(delta)
                local inside = setup.spellNameInsideCastBar
                local left, right = inside and "TOPLEFT" or "LEFT", inside and "BOTTOMRIGHT" or "RIGHT"
                local x, y = delta ~= 0 and 9 or 0, delta ~= 0 and -4 or 0
                local iconX, iconY = delta ~= 0 and 20 or 0, delta ~= 0 and 4 or 0
                Near(cast.castBar.points[left][3], (classic and 20.75 * scale or 0) - delta / 2 + x)
                Near(cast.castBar.points[right][3], (classic and -3.5 * scale or 0) + delta / 2 + x)
                Near(cast.castBar.points[left][4], (classic and .5 * scale or 0) + y)
                if delta ~= 0 then assert(cast.castBar.x == 0 and cast.castBar.y == 0) end
                if not inside then
                    Near(cast.castBar.Icon.points.BOTTOMLEFT[3], -delta / 2 + iconX)
                    Near(cast.castBar.Icon.points.BOTTOMLEFT[4], iconY)
                    if delta ~= 0 then
                        Near(cast.castBar.points.BOTTOM[4], y - iconY)
                        assert(cast.castBar.Icon.x == 0 and cast.castBar.Icon.y == 0)
                    end
                end
                if classic then Near(cast.castBar.Border.width, setup.castBarBorderWidth + delta) end
            end
            Near(cast.castBar.height, 28); Near(cast.castBar.Icon.width, 40); Near(cast.castBar.Icon.height, 40)
            assert(layoutPlate == uf, "a Suite cast size was not handed over")
            Near(layoutHeight, 28) -- Handed over after the Suite sized the cast, not before.
            CheckCastWidth(36)
            if selected == 2 and scale == 1 then
                local icon = cast.castBar.Icon
                config.enemyCastWidthMode, config.enemyCastManualWidth, config.enemyCastIconZoom = 3, 185, 200
                private.Layout.Configure(config); private.Layout.Apply(uf, "enemy", config)
                CheckCastWidth(185 - (230 - 24))
                assert(icon.coords[1] == .25 and icon.coords[6] == .25 and icon.coords[7] == .75)
                config.enemyCastWidthMode, config.enemyCastIconZoom = 2, 100
                private.Layout.Configure(config); private.Layout.Apply(uf, "enemy", config)
                CheckCastWidth(41)
                assert(icon.coords[1] == 0 and icon.coords[7] == 1)
                config.enemyCastWidthMode = 1
                private.Layout.Configure(config); private.Layout.Apply(uf, "enemy", config)
                CheckCastWidth(36)
            end
            Near(cast.height, 28 + (setup.spellNameInsideCastBar and 0 or 40))
            Near(health.height, (largeHealth and 20 or 10) * scale + 7)
            local customWrites, customLayouts = calls, layouts
            private.Layout.Apply(uf, "enemy", config)
            assert(calls == customWrites, "unchanged custom cast dimensions repeated writes")
            assert(layouts == customLayouts, "unchanged custom cast dimensions repeated the layout handoff")
            -- Blizzard's rebuild returns the native cast height first: the
            -- handoff follows the Suite's reapplied height, once.
            layoutHeight = nil
            Native(uf); uf.hook(uf)
            Near(cast.castBar.height, 28); Near(cast.castBar.Icon.height, 40)
            assert(layouts == customLayouts + 1 and layoutPlate == uf, "a native rebuild was not handed over once")
            Near(layoutHeight, 28)
            CheckCastWidth(36)
            combat = true; private.Layout.Restore(uf)
            -- Held back for this plate only (Skin.lua OnCombatEnded applies it again).
            assert(module.pendingPlates[uf] and not module.needsRefresh and health.height ~= setup.healthBarHeight)
            assert(layouts == customLayouts + 1, "a restore held back by combat handed a layout over")
            module.pendingPlates[uf] = nil
            combat = false; private.Layout.Restore(uf)
            assert(layouts == customLayouts + 2, "a restored cast size was not handed over once")
            Near(layoutHeight, setup.castBarHeight)
            Near(health.height, setup.healthBarHeight)
            Near(cast.castBar.height, setup.castBarHeight)
            CheckCastWidth(0)
            Near(cast.points.BOTTOMLEFT[3], setup.insetWidth)
            assert(health.points.BOTTOMRIGHT[3] == (forever and -33 or 0))
            -- Native sizing keeps explicit cast and health overrides. Zero
            -- restores each cast dimension independently from Blizzard.
            private.Layout.Apply(uf, "enemy", config)
            config.barGeometry = 1
            private.Layout.Configure(config); private.Layout.Apply(uf, "enemy", config)
            Near(health.height, setup.healthBarHeight + 7)
            Near(cast.castBar.height, 28)
            CheckCastWidth(36)
            config.enemyCastHeight, config.enemyCastIconSize, config.enemyCastWidthDelta = 0, 0, 0
            private.Layout.Configure(config); private.Layout.Apply(uf, "enemy", config)
            Near(health.height, setup.healthBarHeight + 7)
            Near(cast.castBar.height, setup.castBarHeight)
            Near(cast.castBar.Icon.width, setup.castIconWidth)
            Near(cast.castBar.Icon.height, setup.castIconHeight)
            CheckCastWidth(0)
            assert(cast.castBar.x == 9 and cast.castBar.y == -4, "resetting width cleared the saved cast offset")
            private.Layout.Restore(uf)
        end
    end
end
-- With native geometry, a cast-height slider must leave the icon alone.
-- Inside bars also keep the container height when only the icon changes.
do
    local setup = { insetWidth = 12, castBarToHealthBarSpacing = 1, healthBarHeight = 10,
        castBarHeight = 14, castIconWidth = 12, castIconHeight = 12, horizontalScale = 1,
        verticalScale = 1, spellNameInsideCastBar = true, useClassicCastBar = false }
    local cast, container, icon = Frame(), Frame(), Frame()
    local uf = { HealthBarsContainer = Frame(), CastBarsContainer = container }
    container.castBar, cast.Icon = cast, icon
    container:SetHeight(14)
    cast:SetHeight(14)
    icon:SetSize(12, 12)
    local config = { barGeometry = 1, enemyCastHeight = 18 }
    local state, before = {}, calls
    private.Geometry.Apply(state, uf, setup, config, false, "enemy")
    assert(calls - before == 2 and container.height == 18 and cast.height == 18 and icon.height == 12,
        "changing height also sized the unchanged cast icon")
    before = calls
    private.Geometry.Restore(state, uf, setup)
    assert(calls - before == 2 and container.height == 14 and cast.height == 14, "height restore sized the unchanged icon")
    config.enemyCastHeight, config.enemyCastIconSize = 0, 17
    before = calls
    private.Geometry.Apply(state, uf, setup, config, false, "enemy")
    assert(calls - before == 1 and container.height == 14 and cast.height == 14 and icon.height == 17,
        "sizing the inside icon also sized the castbar")
    before = calls
    private.Geometry.Restore(state, uf, setup)
    assert(calls - before == 1 and icon.height == 12, "icon restore sized an unchanged castbar")
end

local function DungeonPlate()
    local uf, name, health, hpText = Frame(), Frame(), Frame(), Frame()
    uf.unit, uf.showOnlyName, uf.isFriend, uf.UpdateAnchors = "nameplate1", false, false, function() end
    uf.name, uf.HealthBarsContainer, uf.CastBarsContainer = name, health, Frame()
    health.healthBar = Frame()
    health.healthBar.Text = hpText
    uf.CastBarsContainer.castBar = Frame()
    uf.AurasFrame = {}
    name.shown, name.text, name.reads = true, "secret", 0
    function name:ClearAllPoints()
        calls = calls + 1
        self.points = {}
    end
    function name:SetPointsOffset(x, y)
        calls = calls + 1
        self.x, self.y = x, y
        for _, point in pairs(self.points) do point[3], point[4] = x, y end
    end
    function name:GetText() self.reads = self.reads + 1; return self.text end
    function name:GetJustifyH() return self.justify end
    function name:SetJustifyH(justify) self.justify = justify end
    local function Reset()
        name:ClearAllPoints()
        name:SetPoint("LEFT", health, "LEFT", 4, 0)
        name:SetPoint("RIGHT", hpText, "LEFT", -2, 0)
        name:SetJustifyH("LEFT")
    end
    Reset()
    module.activeUnits[uf.unit] = uf
    return uf, name, hpText, Reset
end

local function CheckDungeonNameWidth(forever)
    NS.Client.isForever = forever
    NamePlateConstants = forever and { NAME_PLATE_WIDTH = 190 } or { NAMEPLATE_WIDTH = 230 }
    NS.IsSecret = function(value) return value == "secret" end
    NamePlateSetupOptions = { horizontalScale = 1, insetWidth = 10, unitNameAnchorStyle = 1,
        useClassicHealthBar = false, useClassicCastBar = false, spellNameInsideCastBar = true,
        healthBarHeight = 10, castBarHeight = 10, castIconHeight = 12, castBarToHealthBarSpacing = 2 }
    local config = { look = 4, barGeometry = 1, enemy = true, enemyTextMode = 2 }
    module.config = config
    local layout, observer, timer, observed = private.Layout
    C_Timer = { After = function(delay, fn)
        assert(delay == 0 and not timer, "secret name changes must coalesce into one layout pass")
        timer = fn
    end }
    local function Flush()
        local callback = assert(timer)
        timer = nil
        callback()
    end
    private.NameText = { secretNameWidth = 66, ObserveNameClip = function(fn, marks) observer, observed = fn, marks end }
    local uf, name, hpText, Reset = DungeonPlate()
    local function Apply() layout.Apply(uf, "enemy", config) end
    local function Unclipped() assert(name.points.LEFT[1] == uf.HealthBarsContainer, "native anchor was not restored") end
    local function Clipped()
        local left, right = name.points.LEFT, name.points.RIGHT
        assert(left[1] == uf.HealthBarsContainer and right[1] == left[1]
            and left[3] == 4 and right[3] == 70,
            "secret name did not receive a stable 66-unit span")
    end
    layout.Configure(config)
    Apply()
    Unclipped()
    assert(name.reads == 0, "outside dungeons layout queried the name")
    assert(layout.InstanceNameClip, "dungeon name width support missing")
    local options = NamePlateSetupOptions
    options.unitNameAnchorStyle, options.healthBarToNameAboveSpacing = 2, "secret"
    assert(not private.Geometry.LimitNativeName(uf, options, false, { Name = { 0, 0 } }, 66),
        "the width cap used secret baseline anchor offsets")
    options.unitNameAnchorStyle, options.healthBarToNameAboveSpacing = 1, nil
    layout.InstanceNameClip(true)
    local layoutHandoffs = layouts
    Apply()
    Clipped()
    assert(layouts == layoutHandoffs, "an otherwise inactive plan ran the full layout for a name")
    local warmReads, warmWrites = name.reads, calls
    for _ = 1, 100 do Apply() end
    assert(name.reads == warmReads and calls == warmWrites, "unchanged labels ran native layout work")
    Reset()
    uf.hook(uf)
    Clipped()
    name.text = "An ordinary name"
    observer(uf, false)
    Clipped() -- The native name hook must never write geometry synchronously.
    Flush()
    Unclipped()
    name.text = "secret"
    observer(uf, true)
    uf.UpdateNameOverride = true
    Flush()
    Unclipped()
    assert(name.points.RIGHT[1] == hpText, "the native HP text anchor was lost")
    uf.UpdateNameOverride = nil
    layout.Reapply(uf, "enemy", config)
    Clipped()
    layout.InstanceNameClip(false)
    Apply()
    Unclipped()

    layout.InstanceNameClip(true)
    combat, uf.protected = true, true
    local before = calls
    Apply()
    assert(module.pendingPlates[uf] and calls == before, "protected name anchors were written or lost their retry")
    combat, uf.protected = false, nil
    Apply()
    Clipped()
    layout.Restore(uf, true)
    Reset()
    combat = true
    Apply()
    Clipped()
    warmReads, warmWrites = name.reads, calls
    for _ = 1, 100 do Apply() end
    assert(name.reads == warmReads and calls == warmWrites, "combat paint repeated native name layout")
    combat = false
    layout.Restore(uf, true)
    Reset()
    name.text = "Next pooled occupant"
    Apply()
    Unclipped()

    name.text = "secret"
    config.enemyTextMode = 4
    private.NameText.secretNameWidth = 1000
    layout.InstanceNameClip(true)
    Apply()
    local available = (forever and 190 or 230) - 20 - 8 - 15 * 10 * .75 - 2
    assert(name.points.RIGHT[3] - name.points.LEFT[3] == available, "long caps did not reserve the HP column")

    config.enemyTextMode = 2
    config.enemyNameOffsetX, config.enemyNameOffsetY = 9, -4
    private.NameText.secretNameWidth = 66
    name.text = "Public name with custom offsets"
    layout.Configure(config)
    layout.InstanceNameClip(true)
    Apply()
    assert(name.x == 9 and name.y == -4, "the public name did not acquire its ordinary offset")
    name.text = "secret"
    observer(uf, true)
    Flush()
    assert(name.points.LEFT[3] == 13 and name.points.RIGHT[3] == 79 and name.points.LEFT[4] == -4
        and (name.x or 0) == 0, "the capped name lost or doubled its manual offset")

    config.enemyNameRelativeAnchor = 10
    name.IsAnchoringRestricted = function() return false end
    name.GetNumPoints = function() return 2 end
    function name:GetPoint(index)
        local key = index == 1 and "LEFT" or "RIGHT"
        return key, unpack(self.points[key])
    end
    layout.Configure(config)
    Apply()
    local manual, capPoints = NS.NameplateText.NameAnchor(config, "enemy"), name.points
    combat = true
    name.text = "First public name after the pull began"
    observer(uf, false)
    Flush()
    assert(name.points == capPoints and module.pendingPlates[uf], "lockdown replaced a manual anchor or lost its replay")
    combat = false
    Apply()
    assert(name.points[manual][1] == uf.HealthBarsContainer.healthBar and name.points ~= capPoints,
        "combat-end replay did not restore the uncapped manual anchor")

    layout.Restore(uf)
    module.pendingPlates[uf] = nil

    NS.NameplateExtensions = { OpacityScope = function() return "friendly" end }
    local friendly, friendlyName = DungeonPlate()
    friendly.isFriend = true
    friendlyName.text = "Party Member"
    private.UnitKinds[friendly] = "friendlyPlayer"
    config.friendly, config.friendlyCenterName = true, true
    NamePlateSetupOptions.healthBarToNameAboveSpacing = 2
    layout.Configure(config)
    layout.Apply(friendly, "friendly", config)
    assert(friendlyName.points.BOTTOMLEFT and not observed[friendly] and friendlyName.reads == 0,
        "a friendly name received the hostile dungeon width state")
    observer(friendly, true)
    assert(not observed[friendly] and not timer, "a friendly secrecy notification queued dungeon geometry")
    local beforeCombat = calls
    combat = true
    layout.Apply(friendly, "friendly", config)
    assert(calls == beforeCombat, "a friendly name unnecessarily reapplied its centre anchor in combat")
    combat = false
    layout.InstanceNameClip(false)
    layout.Restore(friendly)
    module.pendingPlates[friendly] = nil
end

CheckDungeonNameWidth(false)
CheckDungeonNameWidth(true)

print("Mapko dimensions: Retail/Forever, seven styles, four scales, native rebuild, Custom, combat and restoration passed")
