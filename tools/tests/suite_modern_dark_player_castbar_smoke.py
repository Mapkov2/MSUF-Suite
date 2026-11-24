"""Modern Dark casts clear the player aura row on new and existing profiles."""
from pathlib import Path
import subprocess
import sys

from suite_factory_profile_smoke import LUA, lua_literal

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_forever_factory_preview import decode
from build_modern_dark_factory import literal


CHECK = r"""
local host, root = arg[1], arg[2]
local old = OLD_PRESETS
local H = assert(loadfile(root .. "/tools/tests/suite_installer_harness.lua"))()
for _, forever in ipairs({ false, true }) do
    local Suite = H.Setup({ root = root, forever = forever })
    local profile = { suite = { modules = { actionbars = { enabled = true, bar4Y = 130, bar12Point = 8,
        bar12X = 240, bar12Y = 170, bar12Size = 30, bar12Rows = 1, bar12Visibility = 6 } } } }
    local bar = profile.suite.modules.actionbars
    Suite.RootDB.installation = { status = "complete", profile = "modernDark", frameProfileName = "Default" }
    Suite.Database.GetProfile = function() return profile end
    Suite.ProfileVariants.BaseProfile = function() return profile end
    Suite.ProfileVariants.BeforeMutation = function() return true end
    Suite.ProfileVariants.AfterMutation = function() end
    Suite.Suite.SetMany = function(id, values)
        assert(id == "actionbars")
        for key, value in pairs(values) do bar[key] = value end
        return true
    end
    bar.bar12Y = 125
    assert(not Suite.SuiteProfiles.EnsureModernDarkPetBar() and bar.bar12Y == 125, "custom pet bar moved")
    Suite.RootDB.installation.modernDarkPetBarRevision = nil
    bar.bar12Y = 170
    assert(Suite.SuiteProfiles.EnsureModernDarkPetBar())
    assert(bar.bar12X == 0 and bar.bar12Y == 92 and bar.bar12Visibility == 1, "stock pet bar still overlaps")
end
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local world = assert(loadfile(host .. "/tools/tests/client_world.lua"))().New(host, flavor)
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and failure.message)
    local core = world.core
    local migrations = core.ProfileMigrations
    local frame = core.Castbars.Frames.CreateCastbarPreviewFrame("player", nil,
        { parent = world.env.UIParent, width = 184, height = 14 })
    local g = { castbarPlayerBarWidth = 184, castbarPlayerBarHeight = 14,
        castbarPlayerSpellNamePosition = "CENTER", castbarPlayerSpellNameTruncate = "CLIP",
        castbarPlayerSpellNameMaxWidth = 207, castbarPlayerTimePosition = "RIGHT", showPlayerCastTime = true }
    frame.timeText:SetText("2.5")
    core.Castbars.Visuals.ApplyCastbarDetailLayout(frame, "player", g)
    local statusW = frame.statusBar:GetWidth()
    local width = frame.castText:GetWidth()
    local x = select(4, frame.castText:GetPoint(1))
    assert(width < statusW and x < 0 and statusW / 2 + x + width / 2 <= statusW - 44,
        "the centered Clip name crossed into the player timer")
    g.castbarPlayerTimePosition = "LEFT"
    core.Castbars.Visuals.ApplyCastbarDetailLayout(frame, "player", g)
    assert(select(4, frame.castText:GetPoint(1)) > 0, "the name did not clear a left timer")
    g.showPlayerCastTime = false
    core.Castbars.Visuals.ApplyCastbarDetailLayout(frame, "player", g)
    assert(frame.castText:GetWidth() == statusW, "hiding the timer did not return the full text width")
    g.showPlayerCastTime = true
    g.castbarPlayerTimePosition, g.castbarPlayerTimeOffsetX = "CENTER", -70
    core.Castbars.Visuals.ApplyCastbarDetailLayout(frame, "player", g)
    assert(frame.castText:GetWidth() > 100 and select(4, frame.castText:GetPoint(1)) > 0,
        "a far-left timer starved the name despite open space on the right")
    g.castbarPlayerTimePosition, g.castbarPlayerTimeOffsetX = "RIGHT", 0
    g.castbarPlayerTimeFontSize, g.castbarPlayerTimeFormat = 18, "CURRENT_MAX"
    frame.timeText:SetText("")
    core.Castbars.Visuals.ApplyCastbarDetailLayout(frame, "player", g)
    x = select(4, frame.castText:GetPoint(1))
    assert(statusW / 2 + x + frame.castText:GetWidth() / 2 <= statusW - math.floor(statusW * .45),
        "an empty CURRENT_MAX timer did not reserve room for its formatted width")
    local cpDB = { general = { powerColorMode = "Class" }, colorOverrides = {} }
    local colors = core.PublicGlobals.MSUF_CP_CORE_BUILDERS.CONTROLLER_COLORS({ scene = true,
        _cpDB = cpDB,
        POWER_TYPE_TOKENS = { [0] = "MANA" } })
    local r, green, b = colors.ResolveClassPowerColor(0)
    local cr, cg, cb = core._colorsAPI.GetClassColor(select(2, world.env.UnitClass("player")))
    assert(r == cr and green == cg and b == cb, "Mana ignored the class colour mode")
    cpDB.colorOverrides.MANA = { .11, .44, .42 }
    colors.ResetTokens()
    r, green, b = colors.ResolveClassPowerColor(0)
    assert(r == .11 and green == .44 and b == .42, "explicit class resource colour was overwritten")
    for _, source in ipairs(old) do
        local function Copy(value)
            if type(value) ~= "table" then return value end
            local out = {}
            for key, child in pairs(value) do out[key] = Copy(child) end
            return out
        end
        for _, sparse in ipairs({ true, false }) do
            local saved = Copy(source)
            if sparse then saved.general.castbarPlayerOffsetY = nil end
            migrations.Apply(saved)
            assert(saved.general.castbarPlayerOffsetY == -104, flavor .. ": old Modern Dark cast still clips")
            assert(saved.general.powerColorMode == "class", "stock green power tint was retained")
            local units = saved.auras3.perUnit
            assert(units.player.layout.debuffGroupOffsetY == -59, "player debuffs did not move below health")
            assert(units.target.layoutShared.debuffGrowthX == "LEFT", "target auras did not align to its right edge")
            for i = 1, 5 do
                local aura = units["boss" .. i]
                assert(aura.layout.debuffGroupOffsetX == -2 and aura.layoutShared.debuffPerRow == 4
                    and aura.layoutShared.maxDebuffs == 12, "boss debuffs still project beyond their frame")
            end
            saved.general.castbarPlayerOffsetY = -59
            migrations.Apply(saved)
            assert(saved.general.castbarPlayerOffsetY == -59, "repair replay moved a user edit")
        end
        local customAuras = Copy(source)
        customAuras.auras3.perUnit.player.layout.debuffGroupOffsetY = 100
        migrations.Apply(customAuras)
        assert(customAuras.general.castbarPlayerOffsetY == -59, "custom aura arrangement moved the castbar")
        assert(customAuras.auras3.perUnit.player.layout.debuffGroupOffsetY == 100, "custom aura placement was overwritten")
        local customBoss = Copy(source)
        customBoss.auras3.perUnit.boss1.layout.buffStackTextSize = 16
        migrations.Apply(customBoss)
        assert(customBoss.auras3.perUnit.boss1.layout.buffStackTextSize == 16, "custom boss aura font was overwritten")
        local custom = Copy(source)
        custom.general.castbarPlayerOffsetY = -95
        migrations.Apply(custom)
        assert(custom.general.castbarPlayerOffsetY == -95, "custom cast position changed")
        assert(custom.auras3.perUnit.player.layout.debuffGroupOffsetY == 80, "new debuff lane overlaps the custom castbar")
        local detached = Copy(source)
        detached.general.castbarPlayerDetached = true
        migrations.Apply(detached)
        assert(detached.general.castbarPlayerOffsetY == -59, "detached cast moved")
    end
end
"""


def main():
    root = Path(sys.argv[1]).resolve()
    host = root.parent / "MidnightSimpleUnitFrames-7.0"
    factory = root / "MSUF_Suite/Core/ModernDarkFactory.lua"
    fallback = literal(factory, "Suite.ModernDarkFramesCompact")
    host_factory = host / "MidnightSimpleUnitFrames_Options/State/MSUF_Defaults_ModernDark.lua"
    assert literal(host_factory, "MSUF.MSUF_MODERN_DARK_PROFILE_COMPACT") == fallback
    modules = decode(literal(factory, "Suite.ModernDarkModuleCompact"), "MSUFM1:MSUF3:")
    actionbars = modules[b"profile"][b"suite"][b"modules"][b"actionbars"]
    assert actionbars[b"bar12Visibility"] == 1 and actionbars[b"bar12X"] == actionbars[b"bar4X"]
    assert actionbars[b"bar12Y"] + actionbars[b"bar12Size"] + 4 <= actionbars[b"bar4Y"]
    old = []
    for compact in (fallback, literal(factory, "Suite.ModernDarkUnitFramesCompact")):
        profile = decode(compact, "MSUF3:")[b"payload"]
        cast = profile[b"general"]
        aura = profile[b"auras3"][b"perUnit"][b"player"][b"layout"]
        aura_bottom = aura[b"debuffGroupOffsetY"] - round(aura[b"debuffGroupIconSize"] * aura[b"debuffIconHeightPercent"] / 100)
        assert cast[b"castbarPlayerOffsetY"] + cast[b"castbarPlayerBarHeight"] <= aura_bottom - 4
        assert cast[b"castbarPlayerOffsetY"] > -(profile[b"player"][b"height"] - profile[b"pet"][b"offsetY"])
        units = profile[b"auras3"][b"perUnit"]
        for index in range(1, 6):
            boss = units[f"boss{index}".encode()]
            layout, shared = boss[b"layout"], boss[b"layoutShared"]
            assert layout[b"debuffAnchor"] == b"TOPRIGHT"
            assert shared[b"debuffPerRow"] == 4 and shared[b"maxDebuffs"] == 12
            layout.update({b"buffAnchor": b"BOTTOMRIGHT", b"buffGroupOffsetX": -1, b"buffGroupOffsetY": -3,
                           b"debuffAnchor": b"TOPLEFT", b"debuffGroupOffsetX": 234, b"debuffGroupOffsetY": -45,
                           b"buffGroupIconSize": 52, b"debuffGroupIconSize": 52, b"buffSpacing": 4, b"debuffSpacing": 4,
                           b"buffIconHeightPercent": 50, b"debuffIconHeightPercent": 50,
                           b"buffCooldownTextSize": 12, b"debuffCooldownTextSize": 12,
                           b"buffStackTextSize": 11, b"debuffStackTextSize": 11})
            shared.update({b"buffPerRow": 12, b"debuffPerRow": 12, b"debuffGrowthX": b"RIGHT"})
        assert cast[b"powerColorMode"] == b"class"
        cast[b"powerColorMode"] = b"static"
        cast[b"castbarPlayerOffsetY"] = -59
        aura.update({b"buffGroupOffsetY": 46, b"debuffGroupOffsetY": 80, b"debuffIconHeightPercent": 50})
        target = units[b"target"]
        target[b"layout"].update({b"buffAnchor": b"TOPLEFT", b"debuffAnchor": b"TOPLEFT",
                                  b"buffGroupOffsetY": 80, b"debuffGroupOffsetY": 46})
        target[b"layoutShared"].update({b"buffGrowthX": b"RIGHT", b"debuffGrowthX": b"RIGHT"})
        old.append(profile)
    script = CHECK.replace("OLD_PRESETS", lua_literal(old), 1)
    return subprocess.run([LUA, "-", str(host), str(root)], input=script, text=True, cwd=root).returncode


if __name__ == "__main__":
    sys.exit(main())
