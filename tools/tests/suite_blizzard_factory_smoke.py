"""Blizzard preset: actual data, staged previews, install, rollback and host compiler."""
import subprocess
import struct
import sys
from pathlib import Path

from suite_factory_profile_smoke import LUA, lua_literal
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_modern_dark_factory import literal
from build_forever_factory_preview import decode

CHECK = r'''
local root, host = arg[1], arg[2]
local fixtures, frameData, skinData = FIXTURES, FRAMES, SKIN
local H = assert(loadfile(root .. "/tools/tests/suite_installer_harness.lua"))()
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, entry in pairs(value) do out[key] = Copy(entry) end
    return out
end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function SkinFactory(forever)
    local NS = { Client = { isForever = forever, isMainline = true },
        FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" } }
    for _, name in ipairs({ "Defaults", "DefaultsLooks", "Database" }) do
        assert(loadfile(root .. "/MSUF_Suite_Skin/Core/" .. name .. ".lua"))("MSUF_Suite_Skin", NS)
    end
    local profile = assert(NS.Database.SanitizeProfile(Copy(skinData.payload)))
    assert(profile.enabled, "Blizzard setup disabled the skin engine")
    for key in pairs(NS.Defaults.skins) do
        assert(profile.skins[key] == (key ~= "chatFrames"), "incorrect window skin: " .. key)
    end
    assert(profile.theme.preset == "midnightDark" and profile.theme.materialDepth == 0)
    assert(profile.theme.colors.accent[1] == .84 and profile.theme.shellOpacity == .96)
    assert(profile.geometry.family == "continuous" and profile.geometry.radius == 8)
    assert(profile.characterDetails.enabled and profile.characterDetails.view == "modern")
    assert(profile.typography.enabled and not profile.typography.applyChat)
    assert(profile.typography.sharedMediaFont == "MapkoSkin - Expressway")
    return profile
end
local function CheckRaidHeader(world, GF, kind)
    local env = world.env
    local count, columns = kind == "raid" and 40 or 20, kind == "raid" and 8 or 4
    local conf = GF.GetConf(kind)
    env._testInRaid, env._testRaidCount = true, count
    GF.InvalidateLayoutRoster()
    local oldWidth, oldHeight = env.UIParent:GetSize()
    env.UIParent:SetSize(1366, 768)
    local header = assert(GF.SetupHeader("raid", kind), kind .. " secure header missing")
    assert(header:GetAttribute("unitsPerColumn") == 5 and header:GetAttribute("maxColumns") == columns,
        kind .. " secure header truncates the full roster")
    assert(header:GetAttribute("initial-width") == 104 and header:GetAttribute("initial-height") == 58)
    assert(header:GetAttribute("showRaid") and header:GetAttribute("showPlayer"), kind .. " hides raid members")
    assert(header:GetAttribute("groupFilter") == nil and header:GetAttribute("nameList") == nil,
        kind .. " inherited a member filter")
    assert(header:GetAttribute("point") == "TOP" and header:GetAttribute("xOffset") == 0
        and header:GetAttribute("yOffset") == -4 and header:GetAttribute("columnAnchorPoint") == "LEFT"
        and header:GetAttribute("columnSpacing") == 4, kind .. " secure growth differs from its preview")
    local _, _, width, height, unitWidth, unitHeight, spacing, growth, perColumn = GF.GetGridMetrics(kind, count)
    assert(unitWidth == 104 and unitHeight == 58 and spacing == 4 and growth == "DOWN" and perColumn == 5)
    assert(width == columns * 104 + (columns - 1) * 4 and height == 306, kind .. " full-grid bounds changed")
    local point, parent, relative, x, y = header:GetParent():GetPoint()
    assert(point == "TOPLEFT" and parent == env.UIParent and relative == "TOPLEFT" and x == 32 and y == -280,
        kind .. " legacy grid migration moved the authored anchor: " .. tostring(x) .. "," .. tostring(y))
    assert(conf.positionMode == "GRID_BOUNDS_V2" and conf.positionMigrationCount == nil
        and conf.positionMigrationDX == nil and conf.positionMigrationDY == nil, kind .. " retained legacy grid metadata")
    assert(x + width <= 1366 and -y + height <= 768, kind .. " clips the supported small viewport")
    for index = 1, count do
        local unit = "raid" .. index
        local frame = env.CreateFrame("Button", nil, env.UIParent)
        frame.MSUFUnitKey, frame.unit = unit, unit
        frame._msufIsGroupFrame, frame._msufGFKind = true, kind
        local spec = assert(GF.CompileSpec(kind, frame, unit), kind .. " could not compile " .. unit)
        assert(spec.width == 104 and spec.height == 58 and spec.unit == unit,
            kind .. " member identity/geometry changed at " .. index)
    end
    env.UIParent:SetSize(oldWidth, oldHeight)
    env._testInRaid, env._testRaidCount = false, 0
    GF.InvalidateLayoutRoster()
end

local function CheckFramePaint(world, UF, env, flavor, Host)
    env.UnitExists = function() return true end
    env.UnitIsVisible = function() return true end
    env.UnitIsConnected = function() return true end
    env.UnitClass = function() return "Mage", "MAGE" end
    env.SetPortraitTexture = function(tex, unit) tex:SetTexture("portrait:" .. unit) end
    for _, unit in ipairs({ "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }) do
        local boss = unit:match("^boss") ~= nil
        local spec = assert(UF.Config.GetSpec(unit))
        local frame = env.CreateFrame("Button", nil, env.UIParent)
        frame:SetSize(spec.width, spec.height)
        frame:SetFrameLevel(20)
        frame.MSUFUnitKey, frame.unit = unit, unit
        UF.ApplySpec(frame, spec)
        UF.frames[unit] = frame
        world.core.ExportPublic("MSUF_" .. unit, frame)
        world.core.TextureLayer.ApplyToUnitFrame(frame)
        local layer = assert(frame._msufTexLayers and frame._msufTexLayers[1], unit .. " has no chassis")
        assert(layer:IsShown() and layer:GetWidth() == 128 and layer:GetHeight() == 64)
        local artwork = boss and "BossFrame.tga" or "UnitFrame.tga"
        assert(layer.tex:GetTexture() == "Interface\\AddOns\\MSUF_Suite\\Media\\BlizzardFrames\\" .. artwork)
        local point, owner, relative, x, y = layer:GetPoint()
        assert(point == "CENTER" and owner == frame and relative == "CENTER" and x == 0 and y == (boss and 6 or 7))
        assert(layer:GetFrameLevel() < frame.nameText:GetParent():GetFrameLevel(), "chassis covers name")
        point, owner, relative, x, y = frame.nameText:GetPoint()
        if boss then
            assert(point == "LEFT" and relative == "TOPLEFT" and x == 4 and y == 6)
            assert(frame.nameText:GetWidth() == 84 and frame.nameText:GetJustifyH() == "LEFT")
        else
            assert(point == "CENTER" and relative == "TOP" and x == 0 and y == 7, "name misses header")
        end
        local value = boss and frame.hpTextRight or frame.hpTextCenter
        point, owner, relative, x, y = value:GetPoint()
        local _, fontSize = value:GetFont()
        if boss then
            assert(spec.height == 28 and spec.text.healthRight == "PERCENT" and spec.text.healthCenter == "NONE")
            assert(point == "RIGHT" and relative == "RIGHT" and x == -20 and y == 4)
            assert(y + spec.height / 2 - fontSize / 2 >= (frame.hpBar._msufHealthPowerInset or 0))
            assert(spec.status.level.enabled and frame.levelText:GetPoint() == "RIGHT")
            local _, _, _, levelX, levelY = frame.levelText:GetPoint()
            assert(levelX == -20 and levelY == 20, "level misses native boss header")
        else
            assert(point == "CENTER" and relative == "BOTTOM", "health value returned to top edge")
            assert(y - fontSize / 2 >= (frame.hpBar._msufHealthPowerInset or 0), "HP overlaps power bar")
        end
        assert(frame.hpBar._msufTexture == "Interface\\AddOns\\MSUF_Suite\\Media\\BlizzardFrames\\HealthFill.tga",
            "striped or symmetric fill returned")
        for _, text in ipairs({frame.nameText, value}) do
            local _, _, flags = text:GetFont()
            assert(flags == "", "compact frame retained outlined/slug text")
            local shadowX, shadowY = text:GetShadowOffset()
            local _, _, _, alpha = text:GetShadowColor()
            assert(shadowX == 1 and shadowY == -1 and alpha == 1, "native text shadow missing")
        end
        local portrait = assert(frame.MSUFPortraitHolder)
        point, owner, relative, x, y = portrait:GetPoint()
        assert(owner == frame and y == (boss and 6 or 7), "portrait misses full chassis center")
        assert(not boss or x == -12, "boss portrait must overlap the body by 12 pixels")
        assert(portrait:GetWidth() == 60 and portrait:GetHeight() == 60)
        if unit:match("^boss") then
            local index = tonumber(unit:match("%d+"))
            assert(spec.x == -712 and spec.y == 220 - (index - 1) * 112)
            assert(spec.relativePoint == "RIGHT" and spec.portrait.blizzardElite)
        end
    end
    local createCast = world.core.Castbars.Driver.CreateCastBar or Host("MSUF_CreateCastBar")
    local targetCast = assert(createCast("MSUF_TargetCastBar", "target"))
    Host("MSUF_ReanchorTargetCastBar")()
    assert(targetCast:GetWidth() == 184 and targetCast:GetHeight() == 14)
    assert(not targetCast.icon:IsShown(), "target cast icon widens the reference silhouette")
    local point, owner, relative, x, y = targetCast:GetPoint()
    assert(point == "BOTTOMLEFT" and relative == "TOPLEFT" and x == 0 and y == -67,
        "target cast does not clear the complete portrait/chassis")
    local function CheckCast(frame)
        assert(frame.statusBar:GetStatusBarTexture():GetTexture():match("CastFill.tga$"), "old cast fill returned")
        assert(frame.castText:GetJustifyH() == "CENTER", "cast name alignment is not centered")
        local point, owner, relative, _, y = frame.castText:GetPoint()
        assert(point == "TOP" and owner == frame.statusBar and relative == "BOTTOM" and y == -2,
            "cast name is not centered below")
    end
    CheckCast(targetCast)
    local initialize = Host("MSUF_InitSafePlayerCastbar") or world.core.Castbars.Manager.InitSafePlayerCastbar
    initialize()
    Host("MSUF_ReanchorPlayerCastBar")()
    local playerCast = Host("MSUF_PlayerCastbar") or world.core.Castbars.Frames.player
    assert(playerCast:GetWidth() == 184 and playerCast:GetHeight() == 14 and not playerCast.icon:IsShown())
    point, owner, relative, x, y = playerCast:GetPoint()
    assert(point == "BOTTOM" and relative == "TOP" and x == -30 and y == -67, "wide player cast returned")
    CheckCast(playerCast)
    assert(playerCast.castText:GetWidth() == 184 and targetCast.castText:GetWidth() == 184,
        "below-bar names still reserve in-bar timer space")
    local _, _, _, nonR, nonG, nonB = Host("MSUF_ResolveCastbarColors")()
    assert(nonR == .6 and nonG == .6 and nonB == .6, "uninterruptible casts are not neutral grey")
    Host("MSUF_ApplyBossCastbarPositionSetting")(true, true)
    local castbars = assert(Host("MSUF_BossCastbars"))
    for index = 1, 5 do
        local bar = assert(castbars[index])
        assert(bar:GetWidth() == 208 and bar:GetHeight() == 16)
        point, owner, relative, x, y = bar:GetPoint()
        assert(point == "TOPLEFT" and relative == "BOTTOMLEFT" and x == -44)
        assert(math.abs(y + 16) < .01, "boss cast does not match native boss layout")
    end
    local Bridge = {}
    local chunk = assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))
    setfenv(chunk, env)("MSUF_Suite", Bridge)
    Bridge.Safety = { IsForbidden = function(frame) return frame.forbidden == true end }
    Bridge.HostBridge.CastbarArtwork(function(frame)
        frame.IsProtected = function(self) return self.protected == true end
    end)
    local preview = assert(world.core.Castbars.Pools.previews.boss:Create(1))
    preview.IsProtected = function(self) return self.protected == true end
    world.core.Castbars.Pools.previews.boss:ApplyLayout(preview, 1)
    preview:Show()
    local artwork, textures = nil, {}
    local moduleSuite = {
        Install = function(_, value) artwork = value end,
        CreateTexture = function(parent, ...)
            local texture = parent:CreateTexture(...)
            textures[#textures + 1] = texture
            return texture
        end,
    }
    chunk = assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/CastbarArt.lua"))
    setfenv(chunk, env)("MSUF_Suite_QualityOfLife", { NS = Bridge, Suite = moduleSuite })
    artwork.config = { namePanel = true }
    artwork:Enable()
    assert(#textures >= 14, "cast artwork missed live player, target or boss pool")
    local panels = 0
    for _, texture in ipairs(textures) do
        if texture:GetTexture():match("CastName.tga$") and texture:IsShown() then panels = panels + 1 end
    end
    assert(panels >= 2, "cast name panels were not painted")
    local previewPanel, targetPanel
    for _, texture in ipairs(textures) do
        if texture:GetTexture():match("CastName.tga$") then
            if texture:GetParent() == preview.statusBar then previewPanel = texture end
            if texture:GetParent() == targetCast.statusBar then targetPanel = texture end
        end
    end
    assert(previewPanel and previewPanel:IsShown(), "already visible boss preview missed its artwork")
    assert(targetPanel:GetWidth() == targetCast:GetWidth(), "name panel does not span the full castbar")
    local config = Host("MSUF_DB").general
    local globalName, targetName = config.castbarShowSpellName, config.castbarTargetShowSpellName
    config.castbarShowSpellName, config.castbarTargetShowSpellName = false, nil
    local refresh = world.core.Castbars.Visuals.RefreshCastbarFrame or Host("MSUF_RefreshCastbarFrame")
    refresh(targetCast, "target", config)
    assert(not targetPanel:IsShown(), "globally hidden cast name kept its dark panel")
    config.castbarShowSpellName, config.castbarTargetShowSpellName = globalName, targetName
    refresh(targetCast, "target", config)
    assert(targetPanel:IsShown(), "live castbar refresh did not restore name artwork")
    artwork.config.namePanel = false
    artwork:Refresh()
    for _, texture in ipairs(textures) do
        if texture:GetTexture():match("CastName.tga$") then assert(not texture:IsShown()) end
    end
    artwork:Disable()
    refresh(targetCast, "target", config)
    for _, texture in ipairs(textures) do assert(not texture:IsShown(), "cast art survived disabling") end
    local GF = assert(world.core.GF)
    env.UnitIsPlayer = function(unit) return unit == "player" end
    env.UnitReaction = function(unit) return (unit:match("^party") or unit:match("^raid")) and 5 or 3 end
    env.UnitCanAttack = function(_, unit) return unit == "target" end
    for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
        if kind ~= "mythicraid" or flavor ~= "Forever" then
            local unit = kind == "party" and "party1" or "raid1"
            local frame = env.CreateFrame("Button", nil, env.UIParent)
            frame.MSUFUnitKey, frame.unit = unit, unit
            frame._msufIsGroupFrame, frame._msufGFKind = true, kind
            local spec = assert(GF.CompileSpec(kind, frame, unit))
            frame:SetSize(spec.width, spec.height)
            UF.ApplySpec(frame, spec, nil, GF.GROUP_APPLY_MASK)
            assert(frame.MSUFGFNameBar:IsShown() and frame.MSUFGFNameBar:GetHeight() == 12)
            assert(frame.hpBar._msufHealthTopInset == 12, "group health covers name plate")
            assert(frame.hpBar._msufTexture == "Interface\\RaidFrame\\Raid-Bar-Hp-Fill", "group fill is not native Blizzard artwork")
            assert(frame.nameText:GetJustifyH() == "CENTER")
            assert(spec.width == 104 and spec.height == 58 and not spec.power.enabled)
            local point, _, relative, x, y = frame.roleIcon:GetPoint()
            assert(point == "TOPLEFT" and relative == "TOPLEFT" and x == 3 and y == -1)
            assert(frame.roleIcon:GetWidth() == 10 and spec.status.role.style == "BLIZZARD")
            local r, g, b = world.core.UFBarTextCommon.HealthColor(frame, unit, 100, 100, nil, "UNIT_HEALTH")
            local er, eg, eb = world.core.UFBarTextCommon.ClassColorForToken("MAGE")
            assert(r == er and g == eg and b == eb,
                string.format("%s RGB %.3f/%.3f/%.3f vs %.3f/%.3f/%.3f", kind, r, g, b, er, eg, eb))
            for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
                env._testRole = role
                world.core.UFStatusRuntime.UpdateRole(frame, spec.status)
                assert(frame.roleIcon:IsShown(), kind .. " role filter hides " .. role)
                assert(GF.GetRoleTexture(kind, role, spec.status.role.style) == "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
            end
            local aura = assert(world.core.MSUF_Auras3.ResolveAuraPreviewConfig(frame, unit)).lanes
            assert(aura.buff.anchor == "TOPLEFT" and aura.buff.x == 43 and aura.buff.y == -16)
            assert(aura.buff.enabled and aura.buff.size == 18 and aura.buff.max == 3
                and aura.buff.perRow == 3 and aura.buff.xSign == 1 and aura.buff.ySign == -1)
            assert(aura.buff.nativeFilter == "HELPFUL|PLAYER|!EXTERNAL_DEFENSIVE",
                kind .. " helpful filter changed: " .. tostring(aura.buff.nativeFilter))
            assert(aura.debuff.anchor == "BOTTOMLEFT" and aura.debuff.x == 2 and aura.debuff.y == 2)
            assert(aura.external.anchor == "BOTTOMRIGHT" and aura.external.x == -2 and aura.external.y == 2)
            assert(aura.debuff.enabled and aura.external.enabled and aura.debuff.size == 18 and aura.external.size == 18)
            assert(aura.debuff.max == 2 and aura.external.max == 2 and aura.debuff.perRow == 2 and aura.external.perRow == 2)
            assert(aura.debuff.xSign == 1 and aura.debuff.ySign == 1
                and aura.external.xSign == -1 and aura.external.ySign == 1, kind .. " lower aura lanes overlap")
            if kind ~= "party" then CheckRaidHeader(world, GF, kind) end
            assert(spec.text.healthLeft == "NONE" and spec.text.healthCenter == "NONE" and spec.text.healthRight == "NONE")
        end
    end
end
for _, forever in ipairs({ false, true }) do
    for _, skinState in ipairs({ "missing", "disabled", "enabled" }) do
        local skin = skinState == "enabled"
        MapkoSkin = nil
        local Suite = H.Setup({ root = root, forever = forever, uiWidth = 2560, uiHeight = 1072,
            addons = skinState ~= "missing" and { MSUF_Suite_Skin = skin } or {},
            frameFactory = function() return frameData.payload end })
        MSUF_TryDecodeCompactString = function(text)
            local value = assert(fixtures[text], text)
            return Suite.CopyValue(value)
        end
        H.skin = H.FakeSkin({ Default = { enabled = false } })
        local authoredSkin = SkinFactory(forever)
        H.skin.ProfileIO.PrepareProfile = function(text)
            return text == Suite.BlizzardSkinCompact and Suite.CopyValue(authoredSkin)
                or { enabled = true, icons = {} }
        end
        assert(Suite.Skin.SetEnabled(false, true))
        Suite.DB.suite.modules.cooldownManager.listsData = "personal-list"
        Suite.DB.suite.modules.cooldownManager.spellsData = "personal-spell-look"
        local previous = Suite.CopyValue(Suite.DB)
        local oldFrames = Suite.CopyValue(MSUF_DB)
        assert(Suite.Installer.Open())
        local w = MSUFSuiteInstallFrame
        w.next.scripts.OnClick()
        assert(w.blizzard:IsShown(), "preset missing from the first installer")
        w.colors[6].scripts.OnClick()
        w.blizzard.scripts.OnClick()
        assert(not w.colors[6]:IsShown(), "global palette can overwrite the reference geometry")
        assert(w.blizzard.mark.text == Suite.Text("SELECTED"))
        local p = w.layoutPreview
        assert(p.screenshot:IsShown() and p.screenshot.art.texture:match("BlizzardPreviewSolo.tga$"))
        assert(p.screenshotNext:IsShown() and p.note.text:find("another UI", 1, true), "reference is misrepresented")
        assert(math.abs(p.screenshot:GetWidth() / p.screenshot:GetHeight() - 2560 / 1072) < .001)
        p.screenshotNext.scripts.OnClick()
        assert(p.screenshot.art.texture:match("BlizzardPreviewGroup.tga$"))
        p.screenshot.scripts.OnClick()
        assert(p.screenshotZoom:IsShown() and p.screenshotZoom.art.texture == p.screenshot.art.texture)
        p.screenshotToggle.scripts.OnClick()
        assert(p.canvas:IsShown() and not p.screenshot:IsShown() and not p.screenshotZoom:IsShown())
        local staged = assert(Suite.ProfileIO.PrepareProfile(Suite.BlizzardModuleCompact, false))
        local frames = assert(Suite.HostBridge.FactoryFramePreview("blizzard"))
        assert(Equal(frames, frameData.payload), "preview differs from installed frame payload")
        local modules = staged.suite.modules
        assert(modules.actionbars.bar1LeftEndcap == 4 and modules.actionbars.bar1Visibility == 1)
        assert(modules.chat.panelColor == "151310" and modules.chat.panelAlpha == 35)
        assert(modules.chat.headerClock and not modules.chat.headerClock24Hour and not modules.chat.allTimestamps)
        assert(modules.chat.hideNativeTimestamps and modules.chat.fontSize == 16 and modules.chat.tabFontSize == 16)
        assert(modules.chat.font:match("Expressway SemiBold.ttf$") and modules.chat.tabFont:match("Expressway Bold.ttf$"))
        assert(modules.chat.windowHeight == 148 and not modules.chat.copyMessages)
        assert(modules.chat.hideNativeButtons and modules.chat.completeMessages, "chat keeps unused buttons or clipped lines")
        assert(modules.playerAuras.enabled and modules.playerAuras.x == -10 and modules.playerAuras.y == 0)
        assert(modules.playerAuras.iconWidth == 28 and modules.playerAuras.debuffOffset == 88)
        assert(not modules.targetDistance.enabled and modules.castbarArt.enabled)
        assert(modules.minimap.queueStatusEnabled and modules.minimap.queueStatusSize == 32)
        local data = modules.dataTexts
        assert(data.bar1SourceIcons and data.bar1FpsAccent)
        assert(data.bar1Slot1 == Suite.DataTextSourceIndex.homeLatency and data.bar1Slot2 == Suite.DataTextSourceIndex.latency)
        assert(modules.damageMeter.barTexture:match("HealthFill.tga$"), "old damage meter fill returned")
        assert(not modules.xpBar.enabled and not modules.cooldownManager.uti_on)
        assert(modules.cooldownManager.defaultsVersion == Suite.CDM.DEFAULTS_VERSION)
        assert(modules.cooldownManager.positionsData == "" and not modules.cooldownManager.specPositions)
        assert(modules.cooldownManager.ess_align == Suite.CDM.ALIGN.CENTER and modules.cooldownManager.buf_height == 100)
        local plates = modules.nameplates
        assert(plates.enabled and plates.nativeStyle == 5 and plates.enemyTextMode == 2)
        assert(plates.enemyTargetMarker and plates.enemyTargetColor == "fff14a" and not plates.enemyRoleColors)
        assert(not plates.enemyNpcControl and not plates.enemyNpcDebuffs and plates.personalResource == 3)
        assert(modules.damageMeter.w1Session == 2 and modules.damageMeter.w2Type == 1)
        assert(modules.objectives.colorStyle == 2 and modules.objectives.groupUnderlines)
        assert(not modules.objectives.enabled, "reference must keep Blizzard's native gold tracker")
        local separation
        for _, height in ipairs({ 768, 1072, 1440 }) do
            local scene = Suite.InstallerPreviewModel.Build(staged, frames, "blizzard", nil,
                { width = height * 16 / 9, height = height })
            assert(scene.player and scene.target and scene.cooldowns and scene.playerPower)
            assert(scene.playerPower.y == scene.cooldowns.y + scene.cooldowns.height + 2)
            assert(scene.resource.width == scene.cooldowns.width)
            assert(scene.resource.y + scene.resource.height == scene.cooldowns.y - 4)
            assert(math.abs(scene.cooldowns.x + scene.cooldowns.width / 2 - scene.width / 2) < .001)
            local distance = scene.target.x - scene.player.x
            assert(not separation or distance == separation, "16:9 changes the spacing of the center cluster")
            separation = distance
            assert(scene.player.width == 124 and frames.player.portraitWidth == 60)
        end
        assert(Equal(Suite.DB, previous) and Equal(MSUF_DB, oldFrames), "preview wrote saved settings")
        assert(not Suite.Skin.enabled and Suite.RootDB.skinEnabled == false, "preview activated skinning")
        H.combat = true
        assert(not Suite.Installer.Apply(), "combat installation was allowed")
        H.combat = false
        w.next.scripts.OnClick(); w.next.scripts.OnClick(); w.next.scripts.OnClick()
        assert(w.review[1].detail.text:find("MSUF Blizzard", 1, true))
        if skin then
            local load = C_AddOns.LoadAddOn
            C_AddOns.LoadAddOn = function(name)
                if name == "MSUF_Suite_Skin" then return false, "skin-load-refused" end
                return load(name)
            end
            assert(not Suite.Installer.Apply(), "enabled but unloadable Skin silently skipped")
            C_AddOns.LoadAddOn = load
            assert(not Suite.Database.GetProfile("MSUF Blizzard") and not Suite.Skin.enabled)
            assert(Equal(Suite.DB, previous) and Equal(MSUF_DB, oldFrames))
        end
        local scaleApply = Suite.HostBridge.ApplyScale
        Suite.HostBridge.ApplyScale = function() return false, "test refusal" end
        assert(not Suite.Installer.Apply(), "failed scale did not roll back")
        assert(Equal(Suite.DB, previous) and Equal(MSUF_DB, oldFrames), "rollback changed the previous profile")
        assert(not Suite.Database.GetProfile("MSUF Blizzard"), "rollback leaked a profile")
        assert(not Suite.Skin.enabled and Suite.RootDB.skinEnabled == false, "rollback activated skinning")
        Suite.HostBridge.ApplyScale = scaleApply
        assert(Suite.Installer.Apply())
        assert(Suite.Database.GetActiveProfileName() == "MSUF Blizzard")
        assert(Suite.RootDB.installation.profile == "blizzard" and Suite.RootDB.installation.status == "complete")
        assert(Suite.RootDB.installation.look == "authored", "installer recorded a palette that was not applied")
        assert(Suite.DB.suite.modules.minimap.shape == 2 and Suite.DB.suite.modules.damageMeter.w2Y == 244)
        assert(Suite.DB.suite.modules.minimap.styleTexture == 8)
        assert(Suite.DB.suite.modules.cooldownManager.listsData == "", "old CDM layout escaped into reference preset")
        assert(Suite.DB.suite.modules.cooldownManager.spellsData == "", "old spell styles escaped into reference preset")
        assert(Equal(Suite.Database.GetProfile("Default"), previous), "install changed the original Suite profile")
        assert(Suite.Skin.enabled == skin and Suite.RootDB.skinEnabled == skin, "skinning stayed disabled")
        assert(H.skin.Database.GetProfile("Default").enabled == false, "old Skin profile changed")
        if skin then
            assert(H.loaded.MSUF_Suite_Skin and H.skin.Database.GetActiveProfileName() == "MSUF Blizzard")
            assert(Equal(H.skin.Database.GetProfile("MSUF Blizzard"), authoredSkin))
        end
        assert(#H.reported == 0, table.concat(H.reported, "\n"))
    end
end
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local world = assert(loadfile(host .. "/tools/tests/client_world.lua"))().New(host, flavor)
    local loadFile = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        local ok, why = loadFile(self, path, addon, namespace)
        if path:match("/State/MSUF_ProfileRuntime.lua$") then self.core.ProfileRuntime.Apply = function() end end
        return ok, why
    end
    world.env.RAID_CLASS_COLORS = { MAGE = { r = .25, g = .78, b = .92 }, WARRIOR = { r = .78, g = .61, b = .43 } }
    world.env.UnitIsDeadOrGhost = function() return false end
    world.env.UnitExists = function() return true end
    world.env.UnitIsVisible = function() return true end
    world.env.UnitIsConnected = function() return true end
    world.env.UnitIsPlayer = function(unit) return unit == "player" end
    world.env.UnitReaction = function(unit) return (unit:match("^party") or unit:match("^raid")) and 5 or 3 end
    world.env.UnitCanAttack = function(_, unit) return unit == "target" end
    world.env.UnitClass = function() return "Mage", "MAGE", 8 end
    world.env.UnitGroupRolesAssigned = function() return world.env._testRole end
    world.env.IsInRaid = function() return world.env._testInRaid == true end
    world.env.IsInGroup = function() return world.env._testInRaid == true end
    world.env.GetNumGroupMembers = function() return world.env._testRaidCount or 0 end
    world.env.GetRaidRosterInfo = function(index)
        return "Member" .. index, 0, math.floor((index - 1) / 5) + 1, 90, "Mage", "MAGE", "Zone",
            true, false, "DAMAGER", false, "DAMAGER"
    end
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and failure.message)
    local env, UF = world.env, world.core.UF
    local public = world.core.PublicGlobals or env
    local function Host(name) return env[name] or public[name] end
    local decode = Host("MSUF_TryDecodeCompactString")
    world.core.ExportPublic("MSUF_TryDecodeCompactString", function(text)
        if text == "MSUF3:blizzard-factory-import-test" then return Copy(frameData) end
        if fixtures[text] then return Copy(fixtures[text]) end
        return decode(text)
    end)
    Host("MSUF_InitProfiles")()
    local oldName = Host("MSUF_ActiveProfile")
    local oldProfile = Copy(Host("MSUF_GlobalDB").profiles[oldName])
    local ok, why = Host("MSUF_Profiles_ImportIntoNewProfile")("Blizzard imported", "MSUF3:blizzard-factory-import-test")
    assert(ok, tostring(why))
    assert(Host("MSUF_ActiveProfile") == "Blizzard imported", "host did not activate the imported profile")
    assert(Equal(Host("MSUF_GlobalDB").profiles[oldName], oldProfile), "host import changed the previous profile")
    UF.Config.Refresh()
    CheckFramePaint(world, UF, env, flavor, Host)
    local aura = world.core.MSUF_Auras3 or env.MSUF_Auras3
    local playerAuras = assert(aura.ResolveUnitFrameConfig("player"))
    assert(not playerAuras.enabled and not playerAuras.lanes.buff and not playerAuras.lanes.debuff,
        "duplicate player auras cover the name header")
    local nativeAuras = Host("MSUF_DB").auras3.shared
    assert(not nativeAuras.hideBlizzardBuffFrame and not nativeAuras.hideBlizzardDebuffFrame,
        "native top-right auras were hidden")
    local focus = assert(UF.Config.GetSpec("focus"))
    assert(focus.x == 358 and focus.y == -327 and focus.anchorFrameName == "UIParent",
        "focus position differs from the imported global anchor")
    for _, kind in ipairs({ "boss", "arena" }) do
        if kind == "boss" or flavor ~= "Forever" then
            for index = 1, kind == "boss" and 5 or 3 do
                local lanes = assert(aura.ResolveUnitFrameConfig(kind .. index)).lanes
                local buff, debuff = assert(lanes.buff), assert(lanes.debuff)
                local boss = kind == "boss"
                assert(buff.anchor == "BOTTOMRIGHT" and debuff.anchor == "TOPLEFT")
                assert(buff.x == (boss and 78 or 25) and buff.y == (boss and -1 or 15),
                    kind .. index .. " buff position differs from the imported layout")
                assert(debuff.x == (boss and 0 or 2) and debuff.y == (boss and 43 or 10),
                    kind .. index .. " debuff position differs from the imported layout")
            end
        end
    end
    local lanes = assert(aura.ResolveUnitFrameConfig("target")).lanes
    local buff, debuff = assert(lanes.buff), assert(lanes.debuff)
    assert(buff.enabled and debuff.enabled and buff.anchor == "TOPLEFT" and debuff.anchor == "TOPLEFT")
    assert(buff.y - buff.height > 21, "target auras cover the name header or portrait")
    assert(debuff.y - debuff.height >= buff.y + 2, "enabled buff and debuff lanes overlap")
    for _, unit in ipairs({ "player", "target" }) do
        local spec = assert(UF.Config.GetSpec(unit))
        assert(spec.width == 124 and spec.height == 32)
        assert(spec.portrait.shape == "BLIZZARD" and spec.portrait.width == 60)
        assert(spec.portrait.alpha == 1, "portrait became transparent")
        assert(spec.health.mode == "class" and spec.backgroundAlpha == .8, "host changed authored health colors")
    end
    local power = UF.Config.GetSpec("player").power
    assert(power.enabled and power.detached and not power.detachedAnchorClass and power.mode == "power")
    assert(power.detachedY == 34 and power.detachedX == 350 and power.detachedHeight == 6)
    local party = Host("MSUF_DB").gf_party
    assert(party.offsetX == 0 and party.growth == "RIGHT", "party import: " .. tostring(party.offsetX) .. "/" .. tostring(party.growth))
    assert(Host("MSUF_DB").general.playerCastbarOverrideEnabled == false)
    local viewer = env.CreateFrame("Frame", nil, env.UIParent)
    viewer:SetSize(334, 40)
    env.EssentialCooldownViewer, env.MSUF_ClassPowerContainer = viewer, nil
    world.core.ExportPublic("MSUF_GetEffectiveCooldownFrame", function(name)
        return name == "EssentialCooldownViewer" and viewer or nil
    end)
    for _, height in ipairs({ 768, 1072, 1080, 1440, 2160, 768 }) do
        env.UIParent:SetSize(height * 16 / 9, height)
        UF.Config.Refresh()
        for _, unit in ipairs({ "player", "target" }) do
            local spec = UF.Config.GetSpec(unit)
            assert(spec.x == (unit == "player" and -350 or 350) and spec.y == -190,
                "imported frame spacing changes with screen height")
        end
        local spec = UF.Config.GetSpec("player")
        local frame = env.CreateFrame("Button", nil, env.UIParent)
        frame:SetSize(spec.width, spec.height)
        frame.MSUFUnitKey, frame.unit = "player", "player"
        UF.AttachFrame(frame, { scope = "unit" })
        UF.Elements.Power.Apply(frame, spec)
        local bar = assert(frame.targetPowerBar)
        local point, owner, relative, x, y = bar:GetPoint()
        assert(point == "TOP" and owner == frame and relative == "BOTTOM" and x == 350 and y == 34)
        assert(bar:GetWidth() == 334 and bar:GetHeight() == 6, "power row needs a class-resource container")
    end
end
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local Mini = assert(loadfile(root .. "/tools/tests/suite_minimap_harness.lua"))()
    MSUF_TryDecodeCompactString, MSUF_EncodeCompactTable = nil, nil
    local W = Mini.New(root, flavor)
    local modules = fixtures[SuiteModuleKey].profile.suite.modules
    Mini.Enable(W, modules.minimap)
    W.Step()
    local art = W.MM.style.artOver
    assert(W.MM.host:GetWidth() == 210 and W.config.shape == 2)
    assert(art:IsShown() and art.atlas == "ui-hud-minimap-frame", "runtime misses native compass artwork")
    assert(Mini.Near(art:GetWidth(), 210 * 215 / 198) and Mini.Near(art:GetHeight(), 210 * 226 / 198))
    assert(W.S.Set("minimap", "styleTexture", 2))
    assert(art.texture:match("ArcaneRing.tga$"), "native atlas survived a style switch")
    assert(art.coords[1] == 0 and art.coords[4] == 1, "atlas coordinates cropped the replacement artwork")
end
print("Blizzard preset: both clients, 40/20 raid headers, group roles/auras, optional Skin, preview, combat, rollback and host compiler passed")
'''


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
    subprocess.run([sys.executable, str(root / 'tools/build_blizzard_frame_art.py'), '--check'], check=True)
    subprocess.run([sys.executable, str(root / 'tools/build_datatext_icons.py'), '--check'], check=True)
    artwork = (root / 'MSUF_Suite/Media/BlizzardFrames/UnitFrame.tga').read_bytes()
    assert artwork[2] == 2 and struct.unpack_from('<HH', artwork, 12) == (128, 64)
    assert artwork[16:18] == bytes((32, 0x28)) and len(artwork) == 18 + 128 * 64 * 4
    alpha = artwork[21::4]
    assert all(alpha[y * 128 + x] == 0 for y in range(26, 52) for x in range(5, 123)), 'opaque health opening'
    assert alpha[23 * 128 + 2] > 0 and alpha[23 * 128 + 5] == 0, 'square health corner returned'
    assert all(alpha[y * 128 + x] > 100 for y in range(9, 23) for x in range(2, 126)), 'missing name strip'
    boss_art = (root / 'MSUF_Suite/Media/BlizzardFrames/BossFrame.tga').read_bytes()
    assert len(boss_art) == len(artwork) and boss_art[:18] == artwork[:18]
    alpha = boss_art[21::4]
    assert all(alpha[y * 128 + x] == 0 for y in range(24, 52) for x in range(2, 126))
    assert all(alpha[y * 128 + x] > 100 for y in range(12, 24) for x in range(2, 126))
    fill = (root / 'MSUF_Suite/Media/BlizzardFrames/HealthFill.tga').read_bytes()
    assert fill[2] == 2 and struct.unpack_from('<HH', fill, 12) == (256, 64)
    assert fill[16:18] == bytes((32, 0x28)) and len(fill) == 18 + 256 * 64 * 4
    pixels = list(struct.iter_unpack('BBBB', fill[18:]))
    assert all(b == g == r and a == 255 for b, g, r, a in pixels)
    ramp = [pixels[y * 256 + 128][0] for y in range(64)]
    peak = ramp.index(max(ramp))
    assert 46 <= peak <= 54 and ramp[0] < 110 and ramp[-1] < 110, 'lower health glow lost'
    assert all(a <= b for a, b in zip(ramp[:peak], ramp[1:peak + 1])), 'striped health ramp'
    assert pixels[peak * 256][0] < ramp[peak] * .6, 'missing soft inset edge'
    core = root / 'MSUF_Suite/Core'
    fixtures = {}
    for filename, names in (
        ('ClassicFramesFactory.lua', ['ClassicFactoryFramesCompact']),
        ('ForeverFrames.lua', ['ForeverFactoryFramesCompact']),
        ('ForeverFactory.lua', ['ForeverFactoryModuleCompact']),
        ('RetailFactory.lua', ['RetailFactoryModuleCompact']),
        ('RetailProfile.lua', ['RetailProfileModuleCompact']),
        ('ModernDarkFactory.lua', ['ModernDarkFramesCompact', 'ModernDarkModuleCompact']),
        ('BlizzardFactory.lua', ['BlizzardFramesCompact', 'BlizzardModuleCompact']),
        ('DarkRaidFactory.lua', ['DarkRaidModuleCompact'])):
        for name in names:
            text = literal(core / filename, 'Suite.' + name)
            module = 'Module' in name
            fixtures[text[7:] if module else text] = decode(text, 'MSUFM1:MSUF3:' if module else 'MSUF3:')
    frame = decode(literal(core / 'BlizzardFactory.lua', 'Suite.BlizzardFramesCompact'), 'MSUF3:')
    skin = decode(literal(core / 'BlizzardFactory.lua', 'Suite.BlizzardSkinCompact'), 'MSKIN1:')
    for name in ('MidnightSimpleUnitFrames', 'MidnightSimpleUnitFrames-7.0'):
        path = root.parent / name / 'MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Shell.lua'
        if path.exists() and 'MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT =' in path.read_text(encoding='utf-8-sig'):
            text = literal(path, 'MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT')
            fixtures[text] = decode(text, 'MSUF3:')
    script = CHECK.replace('FIXTURES', lua_literal(fixtures), 1).replace('FRAMES', lua_literal(frame), 1)
    script = script.replace('SKIN', lua_literal(skin), 1)
    script = script.replace('SuiteModuleKey', lua_literal(literal(core / 'BlizzardFactory.lua', 'Suite.BlizzardModuleCompact')[7:]))
    for name in ('MidnightSimpleUnitFrames', 'MidnightSimpleUnitFrames-7.0'):
        host = root.parent / name
        if not host.exists():
            continue
        run = subprocess.run([LUA, '-', str(root), str(host)], input=script, text=True, capture_output=True, cwd=root)
        print(name + ': ' + run.stdout, end='')
        if run.returncode:
            print(run.stderr, file=sys.stderr, end='')
            return run.returncode
    return 0


if __name__ == '__main__':
    sys.exit(main())
