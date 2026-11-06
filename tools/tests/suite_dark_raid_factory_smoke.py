"""Dark Raid: real import, compiled geometry and optional installer transaction."""
import re
import subprocess
import sys
from pathlib import Path

from suite_factory_profile_smoke import LUA, lua_literal
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_modern_dark_factory import literal
from build_forever_factory_preview import decode

CHECK = r'''
local root, host = arg[1], arg[2]
local fixtures, frames = FIXTURES, FRAMES
local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, value in pairs(v) do out[k] = Copy(value) end
    return out
end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local H = assert(loadfile(root .. "/tools/tests/suite_installer_harness.lua"))()
for _, forever in ipairs({false, true}) do
    local Suite = H.Setup({root = root, forever = forever, uiWidth = 2560, uiHeight = 1440,
        addons = { MSUF_Suite_Skin = false }, frameFactory = function() return frames.payload end})
    MSUF_TryDecodeCompactString = function(text)
        return Copy(assert(fixtures[text], "unexpected compact factory"))
    end
    Suite.DB.suite.modules.cooldownManager.listsData = "old-personal-layout"
    Suite.DB.suite.modules.cooldownManager.spellsData = "old-personal-spells"
    local priorFrames, priorModules = Copy(MSUF_DB), Copy(Suite.DB)
    assert(Suite.Installer.Open())
    local w = MSUFSuiteInstallFrame
    w.next.scripts.OnClick()
    w.darkRaid.scripts.OnClick()
    assert(w.darkRaid.mark.text == Suite.Text("SELECTED"))
    assert(w.layoutPreview.screenshotSpec.art == "Interface\\AddOns\\MSUF_Suite\\Media\\DarkRaidPreview.tga")
    assert(w.layoutPreview.screenshotSpec.bottom == 577 / 1024)
    assert(Equal(Suite.HostBridge.FactoryFramePreview("darkRaid"), frames.payload))
    local staged = assert(Suite.ProfileIO.PrepareProfile(Suite.DarkRaidModuleCompact, false))
    local modules = staged.suite.modules
    assert(modules.damageMeter.w1Type == 1 and modules.damageMeter.w2Type == 3)
    assert(modules.damageMeter.numberFormat == 3 and modules.damageMeter.englishNumbers
        and modules.damageMeter.englishDecimals == 2 and modules.damageMeter.englishKDecimals == 1
        and not modules.damageMeter.headerTimer, "meter lost total (rate) reference format")
    assert(modules.minimap.queueStatusEnabled and modules.minimap.queueStatusSize == 32)
    assert(modules.minimap.queueStatusX == 187 and modules.minimap.queueStatusY == -167)
    assert(modules.minimap.middleClick == 5, "hidden micro menu has no minimap access")
    assert(modules.nameplates.enemyTextMode == 4 and not modules.nameplates.enemyMirrorHeader)
    assert(modules.nameplates.enemyCastHeight == 16 and modules.nameplates.enemyCastIconSize == 16)
    for _, height in ipairs({768, 1080, 1440}) do
        local scene = Suite.InstallerPreviewModel.Build(staged, frames.payload, "darkRaid", nil,
            {width = height * 16 / 9, height = height})
        assert(scene.player.width == 248 and scene.player.height == 38)
        assert(scene.target.x - scene.player.x == 608)
        assert(scene.w2.x - scene.w1.x == 208 and scene.w1.width == 208)
        assert(scene.bar1.height == 59 and scene.bar2.x - scene.bar1.x == 180
            and scene.bar3.x + scene.bar3.width - scene.bar1.x == 539)
    end
    assert(Equal(MSUF_DB, priorFrames) and Equal(Suite.DB, priorModules), "preview changed live profiles")
    H.combat = true
    assert(not Suite.Installer.Apply(), "combat install succeeded")
    H.combat = false
    local ok, why = Suite.Installer.Apply()
    assert(ok, tostring(why))
    assert(Suite.RootDB.installation.profile == "darkRaid")
    assert(MSUF_ActiveProfile == "Dark Raid")
    assert(Equal(MSUF_GlobalDB.profiles.Default, priorFrames), "existing frame profile overwritten")
    assert(Equal(Suite.RootDB.profiles.Default, priorModules), "existing Suite profile overwritten")
    assert(MSUF_DB.boss.width == 192 and MSUF_DB.gf_mythicraid.growth == "RIGHT")
    assert(Suite.DB.suite.modules.damageMeter.windowCount == 2)
    local cd = Suite.DB.suite.modules.cooldownManager
    assert(cd.listsData ~= "old-personal-layout" and cd.spellsData == "", "another profile replaced authored CDM contents")
    local lists = Suite.CDM.Codec.DecodeLists(cd.listsData)
    assert(lists.shared.c1[1] == "s196718" and lists.shared.c1[2] == "s198589", "Darkness/Blur order lost")
    assert(cd.c1_on and cd.c1_shareContents and cd.c1_charges and cd.c1_stackText)
    assert(cd.c1_anchor == 14 and cd.c1_side == 2 and cd.c1_align == 3 and cd.c1_gap == 1)
    assert(cd.c1_size == 34 and cd.c1_perRow == 2)
    assert(cd.ess_perRow == 8 and cd.uti_perRow == 5)
    assert(cd.ess_maxIcons == 0 and cd.uti_maxIcons == 0, "preset silently truncates cooldowns")
    local dataTexts = Suite.DB.suite.modules.dataTexts
    assert(dataTexts.enabled and dataTexts.hideBlizzardBagBar and not dataTexts.trackAltGold)
    assert(dataTexts.barIds == "1" and not dataTexts.bar1Enabled, "hidden bag owner shows information strips")
    assert(Suite.DB.suite.modules.damageMeter.headerMouseover
        and Suite.DB.suite.modules.damageMeter.titleOffsetX == -6, "meter header differs from reference")
    assert(Suite.DB.suite.modules.damageMeter.nameMaxChars == 16)
    assert(Suite.DB.suite.modules.actionbars.bar1ShowEmpty)
end
for _, flavor in ipairs({"Mainline", "Forever"}) do
    local World = assert(loadfile(host .. "/tools/tests/client_world.lua"))()
    local world = World.New(host, flavor)
    local load = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        local ok, message = load(self, path, addon, namespace)
        if path:match("/State/MSUF_ProfileRuntime.lua$") then self.core.ProfileRuntime.Apply = function() end end
        return ok, message
    end
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and failure.message)
    local env, UF = world.env, world.core.UF
    local function Public(name)
        return world.core[name] or (world.core.PublicGlobals and world.core.PublicGlobals[name]) or env[name]
    end
    local original = env.MSUF_TryDecodeCompactString
    world.core.ExportPublic("MSUF_TryDecodeCompactString", function(text)
        if text == "MSUF3:dark-raid-test" then return Copy(frames) end
        if fixtures[text] then return Copy(fixtures[text]) end
        return original(text)
    end)
    Public("MSUF_InitProfiles")()
    local ok, why = Public("MSUF_Profiles_ImportIntoNewProfile")("Dark Raid imported", "MSUF3:dark-raid-test")
    assert(ok, tostring(why))
    Public("MSUF_EnsureDB")()
    UF.Config.Refresh()
    for _, unit in ipairs({"player", "target", "boss1", "boss2", "boss5"}) do
        local spec = assert(UF.Config.GetSpec(unit))
        local boss = unit:match("boss")
        assert(spec.width == (boss and 192 or 248) and spec.height == (boss and 36 or 38))
        assert(spec.health.mode == "dark", "normalizer lost dark health")
        local bg, pred = spec.health.background, spec.prediction
        assert(spec.health.backgroundColorMode == "custom" and spec.health.backgroundFillMode == "missing")
        assert(math.abs(bg.r - .32) < .001 and math.abs(bg.g - .32) < .001
            and math.abs(bg.b - .32) < .001 and math.abs(bg.a - .9) < .001,
            "missing health must be neutral gray, separate from blue absorbs")
        assert(math.abs(spec.alpha.hpAlpha - .85) < .001 and spec.alpha.excludeTextPortrait,
            "health material must be translucent without fading its text")
        assert(pred.absorbTexture == "Solid" and pred.absorbHeight == 0 and pred.absorbAnchorMode == 5)
        assert(math.abs(pred.absorbR - .24) < .001 and math.abs(pred.absorbG - .44) < .001
            and math.abs(pred.absorbB - .54) < .001 and pred.absorbA == 1, "shield lost flat blue tint")
        if unit == "boss1" then
            assert(spec.point == "RIGHT" and spec.relativePoint == "RIGHT" and spec.x == -470 and spec.y == 102,
                "boss no longer occupies the measured right-center column")
        end
        assert(spec.text.healthPercentDecimals == 1, "percentage lost its decimal place")
        assert(not env.MSUF_DB.general.fontSlug, "preset inherits stretched font rendering")
        local frame = env.CreateFrame("Frame", nil, env.UIParent)
        frame:SetSize(spec.width, spec.height)
        frame.MSUFUnitKey, frame.unit, frame.MSUFSpec = unit, unit, spec
        UF.elements.Text.Apply(frame, spec)
        UF.frames[unit] = frame
        world.core.ExportPublic("MSUF_" .. unit, frame)
        if unit ~= "player" then
            local point, _, relative, x, y = frame.nameText:GetPoint()
            assert(point == "LEFT" and relative == "LEFT" and x == 5 and y == 0)
            assert(frame.nameText:GetWidth() == (boss and 92 or 112))
        else
            assert(env.MSUF_DB.gameplay.enableCombatTimer and not env.MSUF_DB.player.showName)
        end
        local point, _, relative, x, y = frame.hpTextRight:GetPoint()
        assert(point == "RIGHT" and relative == "RIGHT" and x == -5 and y == 0)
    end
    local pools = world.core.Castbars.Pools
    local applyBoss = pools.ApplyBossCastbarsEnabled or Public("MSUF_ApplyBossCastbarsEnabled")
    applyBoss()
    local cast = assert((pools.BossCastbars or Public("MSUF_BossCastbars"))[1])
    cast:UpdateAnchor(true)
    local point, _, relative, _, y = cast:GetPoint()
    assert(point == "TOPLEFT" and relative == "BOTTOMLEFT")
    assert(36 - y + cast:GetHeight() < 58, "boss castbar overlaps the next boss")
    local driver = world.core.Castbars.Driver
    local applyTarget = driver and driver.CastbarDriver_ApplyBackendState or Public("MSUF_CastbarDriver_ApplyBackendState")
    local targetCast = applyTarget("target")
    Public("MSUF_ReanchorTargetCastBar")()
    assert(targetCast and targetCast:GetWidth() == 248 and targetCast:GetHeight() == 18)
    local point, _, relative, x, y = targetCast:GetPoint()
    assert(point == "BOTTOMLEFT" and relative == "TOPLEFT" and x == 0 and y == -57,
        "target castbar must sit below health; the reference bar above is a boss-mod timer")
    assert(y + targetCast:GetHeight() == -39, "target castbar must clear the 38px health frame by one pixel")
    local focusSpec = assert(UF.Config.GetSpec("focus"))
    assert(focusSpec.width == 156 and focusSpec.height == 30
        and focusSpec.point == "CENTER" and focusSpec.relativePoint == "CENTER"
        and focusSpec.x == -486 and focusSpec.y == -115,
        "reference focus must be the small left-side frame")
    assert(not focusSpec.showHealthText and focusSpec.text.healthRight == "NONE",
        "reference focus must not display HP numbers")
    local focus = env.CreateFrame("Frame", nil, env.UIParent)
    focus:SetSize(focusSpec.width, focusSpec.height)
    focus.MSUFUnitKey, focus.unit, focus.MSUFSpec = "focus", "focus", focusSpec
    UF.elements.Text.Apply(focus, focusSpec)
    assert(focus.nameText:GetWidth() == 146, "focus name inherited the narrow HP split")
    UF.frames.focus = focus
    world.core.ExportPublic("MSUF_focus", focus)
    UF.elements.StatusIndicators.Apply(focus, focusSpec)
    local point, _, relative, x, y = focus.raidTargetIcon:GetPoint()
    assert(point == "TOPRIGHT" and relative == "TOPRIGHT" and x == -5 and y == 7,
        "focus raid marker must sit at the top-right edge")
    local focusCast = applyTarget("focus")
    Public("MSUF_ReanchorFocusCastBar")()
    assert(focusCast:GetWidth() == 156 and focusCast:GetHeight() == 18)
    local point, _, relative, x, y = focusCast:GetPoint()
    assert(point == "BOTTOMLEFT" and relative == "TOPLEFT" and x == 0 and y == -49,
        "focus cast must sit one pixel below its own 30px health frame")
    Public("MSUF_ReanchorPlayerCastBar")()
    local castbars = world.core.Castbars
    local playerCast = assert(castbars and castbars.Frames and castbars.Frames.player or Public("MSUF_PlayerCastbar"))
    local point, _, relative, x, y = playerCast:GetPoint()
    assert(point == "BOTTOM" and relative == "TOP" and x == 304 and y == 11,
        "Eye Beam must sit above the resource bar, not below the utility row")
    assert(playerCast:GetWidth() == 314 and playerCast:GetHeight() == 24,
        "Eye Beam lost the reference CDM width / 24px height")
    -- At 1440px height the player top is 961, the cast spans y926..950,
    -- and the lower aura row ends at926. Power starts at950; the cast has no overlap.
    assert(env.MSUF_DB.general.castbarPlayerTimeFormat == "ELAPSED_MAX",
        "player cast must show elapsed / total time")
    assert(Public("MSUF_FormatCastbarTimeText")("ELAPSED_MAX", 1.1, 1.4) == "0.3 / 1.4",
        "reference Eye Beam elapsed-time text changed")
    local castColor
    local playerRuntime = world.core.Castbars.Player
    local painter = playerRuntime and playerRuntime.PlayerCastbar_UpdateColorForInterruptible
        or Public("MSUF_PlayerCastbar_UpdateColorForInterruptible")
    painter({unit = "player", statusBar = {SetStatusBarColor = function(_, r, g, b, a)
        castColor = {r, g, b, a}
    end}})
    assert(castColor and math.abs(castColor[1] - .58) < .001
        and math.abs(castColor[2] - .52) < .001 and castColor[3] == 1 and castColor[4] == 1,
        "player castbar lost its separate lavender palette")
    local kick = assert(world.core.KickReady)
    local look = kick.Look()
    assert(look.show and look.style == "fill" and not look.marker and not look.segment,
        "native nameplate cast fill does not use the preset palette")
    local normal, locked, unavailable = kick.FillColors()
    local r, g, b = normal:GetRGB()
    assert(math.abs(r - .25) < .001 and math.abs(g - .48) < .001 and b == 1)
    local r, g, b = locked:GetRGB()
    assert(r == 1 and math.abs(g - .3) < .001 and math.abs(b - .3) < .001)
    local r, g, b = unavailable:GetRGB()
    assert(math.abs(r - .25) < .001 and math.abs(g - .48) < .001 and b == 1,
        "plate casts fall back to orange when the interrupt is unavailable")
    local GF = world.core.GF
    assert(GF, "missing group runtime")
    local party = GF.CompileSpec("party")
    assert(party.text.nameClassColor, "group names ignore class colors")
    assert(party.health.backgroundColorMode == "custom" and party.prediction.absorbTexture == "Solid")
    assert(math.abs(party.prediction.absorbB - .54) < .001 and party.prediction.absorbHeight == 0)
    assert(math.abs(party.health.background.r - .32) < .001 and party.health.background.override
        and math.abs(party.health.background.b - .32) < .001 and party.alpha.excludeTextPortrait,
        "group missing health is neutral gray without dimming class-colored names")
    assert(party.text.healthRightY >= 17, "party health is not aligned with top-edge name")
    assert(not GF.GetConf("party").showPlayer, "party duplicates the standalone player frame")
    for _, entry in ipairs({{"party", 5, 208, 288}, {"raid", 40, 478, 526}, {"mythicraid", 20, 478, 262}}) do
        local kind, count = entry[1], entry[2]
        local _, _, width, height = GF.GetGridMetrics(kind, count)
        assert(width == entry[3] and height == entry[4],
            kind .. " grid differs: " .. tostring(width) .. " x " .. tostring(height))
        local conf = GF.GetConf(kind)
        assert(conf.positionMode == "GRID_BOUNDS_V2" and conf.point == "TOPLEFT")
        assert(conf.nameColorMode == "CLASS" and conf.gfBarMode == "dark")
    end
    local aura = world.core.MSUF_Auras3
    local playerAuras = assert(aura.ResolveUnitFrameConfig("player"))
    assert(playerAuras.lanes.buff.max == 4 and playerAuras.lanes.buff.width == 139)
    assert(playerAuras.lanes.buff.y == -40 and playerAuras.lanes.buff.buttonHeight == 34)
    assert(not playerAuras.lanes.buff.enabled,
        "player buff lane must not impersonate or overlap the consumable cooldown row")
    assert(playerAuras.lanes.buff.cooldownAnchor == "CENTER" and playerAuras.lanes.buff.stackAnchor == "BOTTOMRIGHT")
    local targetAuras = assert(aura.ResolveUnitFrameConfig("target"))
    local buffs, debuffs = targetAuras.lanes.buff, targetAuras.lanes.debuff
    assert(buffs.anchor == "TOPLEFT" and buffs.y == 36 and debuffs.anchor == "TOPRIGHT" and debuffs.y == 36)
    assert(buffs.width == 69 and debuffs.width == 139 and buffs.width + debuffs.width <= 248,
        "target's two full aura rows overlap")
    assert(not playerAuras.lanes.custom4 or not playerAuras.lanes.custom4.enabled,
        "active aura container duplicates the dedicated cooldown row")
    world.widgets:SetTime(0)
    local core = world.core
    core.MSUF_ApplyGameplayVisuals()
    local timer = assert(core.MSUF_GetCombatTimerFrame())
    local function timerText()
        for _, region in ipairs({timer:GetRegions()}) do
            if region.GetText and region:GetText() then return region:GetText() end
        end
    end
    world:EnterCombat()
    world.widgets:SetTime(5)
    core.MSUF_Gameplay_TickCombatTimer("PLAYER_REGEN_DISABLED")
    assert(timerText() == "00:05", "timer does not render padded minutes: " .. tostring(timerText()))
    world:LeaveCombat()
    assert(timer:IsShown() and timerText() == "00:05", "last combat time disappears")
    world.widgets:SetTime(8)
    world:EnterCombat()
    assert(timerText() == "00:00", "new combat did not reset the timer")
    env.MSUF_DB.gameplay.combatTimerKeepLast = false
    env.MSUF_DB.gameplay.combatTimerPadMinutes = false
    world.widgets:SetTime(13)
    core.MSUF_Gameplay_TickCombatTimer("PLAYER_REGEN_DISABLED")
    assert(timerText() == "0:05", "legacy timer format changed")
    world:LeaveCombat()
    assert(not timer:IsShown(), "legacy locked timer remains visible")
    for _, unit in ipairs({"boss1", "boss5"}) do
        local config = assert(aura.ResolveUnitFrameConfig(unit))
        assert(config.lanes.buff.buttonWidth == 34 and config.lanes.buff.buttonHeight == 34)
        assert(config.lanes.debuff.growthX == "LEFT" and config.lanes.buff.growthX == "RIGHT")
        local buff, debuff = config.lanes.buff, config.lanes.debuff
        local buffLeft = buff.anchor == "TOPRIGHT" and 192 + buff.x - buff.width or buff.x
        local debuffRight = debuff.anchor == "TOPRIGHT" and 192 + debuff.x or debuff.x + debuff.width
        assert(buffLeft >= 194 and debuffRight <= -2, "boss auras overlap the health/name bar")
    end
    do
    local function BackgroundPublic(name)
        return core[name] or core.PublicGlobals and core.PublicGlobals[name] or env[name]
    end
    BackgroundPublic('MSUF_EnsureDB')()
    local db=env.MSUF_DB
    db.general.barBgColorMode='custom'
    db.general.barBgFillMode='missing'
    db.general.classBarBgR,db.general.classBarBgG,db.general.classBarBgB=.32,.32,.32
    db.general.classBarBgA=1
    db.general.darkBgCustomColor=true
    db.player.hpBgAlpha=.9
    db.player.barBgColorOverride=true
    db.player.bgR,db.player.bgG,db.player.bgB=.24,.44,.54
    core.UF.Config.Refresh()
    local spec=core.UF.Config.GetSpec('player')
    local function near(a,b) return type(a)=='number' and math.abs(a-b)<.00001 end
    assert(spec.health.background.override and near(spec.health.background.r,.24)
        and near(spec.health.background.g,.44) and near(spec.health.background.b,.54),
        flavor..' opted-in per-unit color was not compiled')
    local frame=env.CreateFrame('Frame',nil,env.UIParent)
    frame.unit,frame.MSUFUnitKey,frame.MSUFSpec='player','player',spec
    frame.hpBar=env.CreateFrame('StatusBar',nil,frame)
    frame.hpBarBG=frame:CreateTexture(nil,'BACKGROUND')
    local paint={}
    local native=frame.hpBarBG.SetVertexColor
    function frame.hpBarBG:SetVertexColor(r,g,b,a)
        paint[1],paint[2],paint[3],paint[4]=r,g,b,a
        return native(self,r,g,b,a)
    end
    BackgroundPublic('MSUF_ApplyBarBackgroundVisual')(frame)
    assert(near(paint[1],.24) and near(paint[2],.44) and near(paint[3],.54) and near(paint[4],.9),
        flavor..' color/texture refresh overwrote compiled custom RGB: '..table.concat(paint,','))
    db=env.MSUF_DB
    db.player.barBgColorOverride=nil
    core.UF.Config.Refresh()
    frame.MSUFSpec=core.UF.Config.GetSpec('player')
    assert(not frame.MSUFSpec.health.background.override,'removed override flag remains cached')
    BackgroundPublic('MSUF_ApplyBarBackgroundVisual')(frame)
    assert(near(paint[1],.32) and near(paint[2],.32) and near(paint[3],.32),
        flavor..' old profile without flag no longer uses global custom color')
    db=env.MSUF_DB
    db.player.barBgColorOverride=true
    for _,mode in ipairs({'class','match_health','health_gradient'}) do
        db.general.barBgColorMode=mode
        core.UF.Config.Refresh()
        local health=core.UF.Config.GetSpec('player').health
        assert(not health.background.override and health.backgroundColorMode==mode,
            flavor..' per-unit override replaced '..mode..' mode')
    end
    print('PASS '..flavor..': compile/refresh keeps scoped RGB; missing flag restores global; dynamic modes keep precedence')
    end
end
print("Dark Raid: installer selection, combat refusal, profile preservation, real UF/GF import and boss auras passed")
'''



METER_CHECK = r"""
Suite.DB.suite.modules.damageMeter = PAYLOAD
S.Normalize(Suite.DB)
S.started = true
S.Apply("damageMeter")
assert(M.active)
for _, win in ipairs({D.windows[1], D.windows[2]}) do
    assert(win.frame.width == 208 and win.frame.height == 196)
    assert(win.title.points[1][4] == 0, "title not aligned with row icons")
    assert(win.header.shown and win.timer.text == "", "header title/timer mismatch")
    D.ApplyHover(win)
    assert(win.buttons.settings.alpha == 0 and win.buttons.reset.alpha == 0, "header controls visible without hover")
    win.hover = true
    D.ApplyHover(win)
    assert(win.buttons.settings.alpha == 1 and win.buttons.reset.alpha == 1, "header controls inaccessible on hover")
    win.hover = false
    D.ApplyHover(win)
    assert(win.buttons.settings.alpha == 0 and win.buttons.reset.alpha == 0)
end
print("PASS: actual Kuro meter header geometry; buttons hide and restore on hover")
"""

BAG_CHECK = r"""
for id in pairs(S.catalog) do S.Config(id).enabled = false end
W.Suite.DB.suite.modules.dataTexts = PAYLOAD
S.Normalize(W.Suite.DB)
S.Start()
assert(M.active and nativeBag.shown and not nativeBag.driver, "disabled Bags must preserve native equipped bag slots")
assert(next(M.bars) == nil and next(M.activeSources) == nil and W.Pending() == 0,
    "bag-only owner allocated visible bars, active sources or a repeating timer")
nativeBag:Show()
assert(nativeBag.shown, "DataTexts cannot hide the only equipped bag slots")
W.SetCombat(true)
assert(not S.Set("dataTexts", "hideBlizzardBagBar", false), "combat menu edit was accepted")
S.Config("dataTexts").hideBlizzardBagBar = false
M:Refresh()
assert(nativeBag.shown and not nativeBag.driver, "disabled Bags changed native access during combat")
W.SetCombat(false)
assert(nativeBag.shown and not nativeBag.driver, "bag restore was not replayed after combat")
assert(S.Set("dataTexts", "hideBlizzardBagBar", true))
assert(nativeBag.shown and not nativeBag.driver, "hide preference removed equipped slots without a replacement")
assert(S.Set("dataTexts", "enabled", false))
assert(nativeBag.shown and not nativeBag.driver, "profile disable did not restore native bag bar")
print("PASS: DataTexts preserves native bags without a replacement; combat deferral and restore work")
"""

def check_meter_and_bags(root, module):
    modules = module[b'profile'][b'suite'][b'modules']
    cases = [
        ('suite_damage_meter_contract.lua', '-- The controller drives the lifecycle;', METER_CHECK, b'damageMeter', ['Mainline']),
        ('suite_datatexts_contract.lua', '-- The shared data timer', BAG_CHECK, b'dataTexts', ['Mainline', 'Forever']),
    ]
    for test, marker, checks, key, flavors in cases:
        source = (root / 'tools/tests' / test).read_text(encoding='utf-8-sig')
        assert marker in source
        source = source.split(marker, 1)[0] + checks.replace('PAYLOAD', lua_literal(modules[key]))
        for flavor in flavors:
            result = subprocess.run([LUA, '-', str(root), flavor], input=source,
                                    text=True, capture_output=True, cwd=root)
            print(result.stdout, end='')
            if result.returncode:
                print(result.stderr, file=sys.stderr, end='')
                return result.returncode
    return 0


def main():
    root = Path(sys.argv[1]).resolve()
    core = root / 'MSUF_Suite/Core'
    fixtures = {}
    for path in core.glob('*.lua'):
        source = path.read_text(encoding='utf-8-sig')
        for name in re.findall(r'Suite\.(\w+Compact)\s*=', source):
            value = literal(path, 'Suite.' + name)
            if value.startswith('MSUFM1:MSUF3:'):
                fixtures[value[7:]] = decode(value, 'MSUFM1:MSUF3:')
            elif value.startswith('MSUF3:'):
                fixtures[value] = decode(value, 'MSUF3:')
    default = literal(root.parent / 'MidnightSimpleUnitFrames/MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Shell.lua', 'MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT')
    fixtures[default] = decode(default, 'MSUF3:')
    skin = decode(literal(core / 'DarkRaidFactory.lua', 'Suite.DarkRaidSkinCompact'), 'MSKIN1:')[b'payload']
    micro = skin[b'icons'][b'microMenu']
    assert skin[b'enabled'] and skin[b'skins'][b'microMenu'] and micro[b'layoutMode'] == b'owned'
    assert micro[b'visibility'] == b'never' and micro[b'layoutY'] == 64
    module = decode(literal(core / 'DarkRaidFactory.lua', 'Suite.DarkRaidModuleCompact'), 'MSUFM1:MSUF3:')
    lists = module[b'profile'][b'suite'][b'modules'][b'cooldownManager'][b'listsData'].decode()
    fixtures[lists] = decode(lists, 'MSUF3:')
    frame = decode(literal(core / 'DarkRaidFactory.lua', 'Suite.DarkRaidFramesCompact'), 'MSUF3:')
    script = CHECK.replace('FIXTURES', lua_literal(fixtures), 1).replace('FRAMES', lua_literal(frame), 1)
    host = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else root.parent / 'MidnightSimpleUnitFrames'
    result = subprocess.run([LUA, '-', str(root), str(host)], input=script,
                            text=True, capture_output=True, cwd=root)
    print(result.stdout, end='')
    if result.returncode:
        print(result.stderr, file=sys.stderr, end='')
    return result.returncode or check_meter_and_bags(root, module)


if __name__ == '__main__':
    sys.exit(main())
