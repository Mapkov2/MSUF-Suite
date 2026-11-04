-- Character equipment and item upgrades are used together, even with another
-- window open. Exercise the real focus controller on both supported clients.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_window_focus_contract.lua", "rb"))
local source = file:read("*a"); file:close()
local stop = assert(source:find('    local a = Native("CharacterFrame"', 1, true))
local body = [======[
    Load("Adapters/CatalogGlass.lua")
    UIPanelWindows.ItemUpgradeFrame = { area = "left" }
    local character = Native("CharacterFrame", 100, 100, 338, 496)
    local upgrade = Native("ItemUpgradeFrame", 500, 100, 400, 500)
    local other = Native("ProfessionsFrame", 1000, 50, 400, 600)
    W.TrackFocus(character, "upgrade")
    W.TrackFocus(other, "other")
    Check(Dimmed(character), "a lone character window became exempt from dimming")
    Check(W.TrackFocus(upgrade, "upgrade"), "native item-upgrade window was not enrolled")
    Check(not Dimmed(character) and not Dimmed(upgrade), "opening upgrades dims the equipped items")
    Click(character); Tick()
    Check(not Dimmed(character) and not Dimmed(upgrade) and Dimmed(other), "clicking equipment dims upgrades")
    Click(upgrade); Tick()
    Check(not Dimmed(character) and not Dimmed(upgrade), "clicking upgrades dims equipment")
    Click(other); Tick()
    Check(not Dimmed(character) and not Dimmed(upgrade), "a third window dims the open equipment/upgrade pair")
    local width = character.GetWidth
    character.GetWidth = function() return { secret = true } end
    listeners[F](F, "geometry")
    Check(not Dimmed(character) and not Dimmed(upgrade), "unreadable character bounds break the visible pair")
    character.GetWidth = width
    listeners[F](F, "geometry")
    Check(not Dimmed(character) and not Dimmed(upgrade), "readable bounds did not restore the pair")
    other.left, other.width = 50, 1000
    Click(character); Tick()
    for _, veil in ipairs(F.records[other].veils) do
        if veil.dim then
            Check(not Intersects(veil.rect, F.records[character].rect)
                and not Intersects(veil.rect, F.records[upgrade].rect), "another window's veil covers the undimmed pair")
        end
    end
    other.left, other.width = 1000, 400
    upgrade:Hide(); Click(other); Tick()
    Check(Dimmed(character), "closing upgrades leaves character permanently exempt")
    character:Hide(); upgrade:Show(); Click(other); Tick()
    Check(Dimmed(upgrade), "a lone upgrade window became exempt from dimming")
    character:Show(); Tick()
    Check(not Dimmed(character) and not Dimmed(upgrade), "reverse opening order breaks the pair")
    combat, combatEdge = true, true
    Click(upgrade); Tick(); Click(character); Tick()
    Check(not Dimmed(character) and not Dimmed(upgrade), "combat breaks the undimmed pair")
    Check((character.geometryWrites or 0) == 0 and (upgrade.geometryWrites or 0) == 0,
        "pair handling changes native geometry in combat")
    combat, combatEdge = false, false
    F.ReleaseOwner("upgrade")
    Check(not Dimmed(character) and not Dimmed(upgrade), "releasing the pair retains a veil")
    W.TrackFocus(character, "upgrade"); W.TrackFocus(upgrade, "upgrade")
    NS.DB.theme.windowFocusDimming = false; listeners[F](F, "theme")
    Check(not Dimmed(other), "disabling dimming leaves another window dark")
    NS.DB.theme.windowFocusDimming = true; listeners[F](F, "theme")
    Check(not Dimmed(character) and not Dimmed(upgrade), "reenabling loses the pair")
    character:Hide(); upgrade:Hide(); other:Hide()
    local reads = 0
    character.GetWidth = function() reads = reads + 1; return 338 end
    upgrade.GetWidth = function() reads = reads + 1; return 400 end
    for _ = 1, 1000 do Tick() end
    Check(reads == 0 and not driver.scripts.OnUpdate, "closed pair polls native geometry")
end
]======]
assert(loadstring(source:sub(1, stop - 1) .. body .. '\nprint("suite_window_focus_upgrade_contract: " .. checks .. " checks passed")',
    "@window_focus_upgrade_contract"))()
