local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local reads = { fps = 0, gold = 0, durability = 0 }
local money, fps = 100000, 80
local W = H.New(root, flavor, { beforeModules = function(world)
    local G = world.G
    G.GetFramerate = function() reads.fps = reads.fps + 1; return fps end
    G.GetMoney = function() reads.gold = reads.gold + 1; return money end
    G.GetInventoryItemDurability = function()
        reads.durability = reads.durability + 1
        return 80, 100
    end
    G.GetGameTime = function() return 14, 3 end
    G.GetServerTime = function() return 1700000000 + world.now end
    G.GetNetStats = function() return 0, 0, 30, 50 end
    G.C_Container = {
        GetContainerNumSlots = function() return 20 end,
        GetContainerNumFreeSlots = function() return 8, 0 end,
    }
    G.UnitLevel = function() return 20 end
    G.UnitXP = function() return 200 end
    G.UnitXPMax = function() return 1000 end
    G.UnitGUID = function() return "Player-1" end
    G.MSUF_ResolveStatusbarTextureKey = function(key)
        return key == "TestTexture" and "Interface\\AddOns\\Test\\Media\\bar.tga" or nil
    end
    G.MSUF_ResolveFontKeyPath = function(key)
        return key == "TestFont" and "Interface\\AddOns\\Test\\Media\\font.ttf" or nil
    end
end })
local G, S = W.G, W.S
local nativeBag
if flavor == "Forever" or flavor == "Mainline" then
    nativeBag = { shown = true }
    function nativeBag:IsShown() return self.shown end
    function nativeBag:Hide() self.shown = false end
    function nativeBag:Show()
        self.shown = true
        if self.onShow then self.onShow(self) end
    end
    function nativeBag:HookScript(script, callback)
        assert(script == "OnShow")
        self.onShow = callback
    end
    G.BagsBar = nativeBag
    G.RegisterStateDriver = function(frame, kind, driver)
        assert(frame == nativeBag and kind == "visibility" and driver == "hide")
        frame.driver = driver
    end
    G.UnregisterStateDriver = function(frame, kind)
        assert(frame == nativeBag and kind == "visibility")
        frame.driver = nil
    end
end
local function Load(file)
    local chunk = assert(loadfile(root .. "/MSUF_Suite_DataTexts/" .. file .. ".lua"))
    setfenv(chunk, G)
    chunk("MSUF_Suite_DataTexts", W.private)
end
Load("Bootstrap")
Load("DataTexts")
local M = assert(S.instances.dataTexts)
assert(not M.bars[1] and W.Pending() == 0, "dormant DataTexts allocated a visible bar or timer")
local defaultLook = flavor == "Forever" and 3 or 2
assert(S.Config("chat").look == defaultLook
    and S.Config("damageMeter").look == defaultLook
    and S.Config("dataTexts").look == defaultLook
    and S.Config("xpBar").look == defaultLook,
    "new Suite modules did not share the client default look")
local legacyLooks = { suite = { modules = {
    chat = { look = 2, panelColor = "14181b" },
    damageMeter = { look = 3, bgColor = "123456" },
    dataTexts = { look = 2, bar1Look = 2, bar1StyleOverride = true },
    xpBar = { look = 2 },
} } }
S.Normalize(legacyLooks)
assert(legacyLooks.suite.lookPresetRevision == 1
    and legacyLooks.suite.modules.chat.look == 3
    and legacyLooks.suite.modules.chat.panelColor == "14181b"
    and legacyLooks.suite.modules.damageMeter.look == 4
    and legacyLooks.suite.modules.damageMeter.bgColor == "123456"
    and legacyLooks.suite.modules.dataTexts.look == 3
    and legacyLooks.suite.modules.dataTexts.bar1Look == 3
    and legacyLooks.suite.modules.xpBar.look == 3,
    "old Forever and Custom look numbers were not migrated")
S.Normalize(legacyLooks)
assert(legacyLooks.suite.modules.chat.look == 3
    and legacyLooks.suite.modules.damageMeter.look == 4,
    "look migration changed the same profile twice")
if flavor == "Forever" then
    local footer = S.Config("dataTexts")
    assert(footer.enabled and footer.bar1Point == 9 and footer.bar1Width == 340
        and footer.bar1Layout == 2
        and footer.bar1Slot1 == 3 and footer.bar1Slot2 == 4 and footer.bar1Slot3 == 5,
        "Forever footer defaults are not bags, durability and clock at bottom right")
    local old = { suite = { modules = {
        dataTexts = { bar1Width = 270, bar1Layout = 1, bar1Point = 9,
            bar1X = -20, bar1Y = 20, bar1Slot1 = 3, bar1Slot2 = 4, bar1Slot3 = 5 },
        damageMeter = { windowCount = 2, w1Width = 260, w1Height = 170,
            w1X = -20, w1Y = 20, w2Width = 260, w2Height = 170,
            w2X = -20, w2Y = 210 },
        actionbars = { imported = false, enabled = true },
        chat = { look = 2, inputColor = "1a1a1b" },
        buffReminders = { borderColor = "e8b855" },
        cooldownManager = { bar_barColor = "e8b855" },
    } } }
    local previous = { 1, 1, 4, 1, 4, 6, 6, 6, 6, 6, 1, 1 }
    for i = 1, #previous do
        old.suite.modules.actionbars["bar" .. i .. "Visibility"] = previous[i]
        old.suite.modules.actionbars["bar" .. i .. "ResumeVisibility"] = previous[i] == 6 and 1 or previous[i]
    end
    S.Normalize(old)
    assert(old.suite.layoutRevision == 2
        and old.suite.modules.dataTexts.bar1Width == 340
        and old.suite.modules.dataTexts.bar1Layout == 2
        and old.suite.modules.damageMeter.w1Y == 60
        and old.suite.modules.damageMeter.w2Y == 250
        and old.suite.modules.actionbars.bar1Visibility == 4
        and old.suite.modules.actionbars.bar12Visibility == 4
        and old.suite.modules.actionbars.enabled == false
        and old.suite.actionBarsDefaultRevision == 1
        and old.suite.paletteRevision == 1
        and old.suite.modules.chat.inputColor == "111517"
        and old.suite.modules.buffReminders.borderColor == "d8b66a"
        and old.suite.modules.cooldownManager.bar_barColor == "d8b66a",
        "old Forever factory layout was not repaired")
    old.suite.modules.actionbars.enabled = true
    S.Normalize(old)
    assert(old.suite.modules.actionbars.enabled == true,
        "a deliberate ActionBars re-enable must survive normalization")
    local custom = { suite = { modules = {
        dataTexts = { bar1Width = 300, bar1Layout = 1, bar1Point = 9, bar1X = -20, bar1Y = 20 },
        damageMeter = { windowCount = 2, w1Width = 290, w1Y = 20, w2Y = 210 },
        actionbars = { imported = true, bar1Visibility = 1 },
        chat = { look = 2, inputColor = "222222" },
        buffReminders = { borderColor = "123456" },
        cooldownManager = { bar_barColor = "654321" },
    } } }
    S.Normalize(custom)
    assert(custom.suite.modules.dataTexts.bar1Width == 300
        and custom.suite.modules.damageMeter.w1Width == 290
        and custom.suite.modules.actionbars.bar1Visibility == 1
        and custom.suite.modules.chat.inputColor == "222222"
        and custom.suite.modules.buffReminders.borderColor == "123456"
        and custom.suite.modules.cooldownManager.bar_barColor == "654321",
        "custom Forever layout was overwritten")
    -- The remaining contract exercises the shared sampled FPS path and gold
    -- events with the same data sources on both client families.
    footer.bar1Slot1, footer.bar1Slot3 = 2, 6
    footer.backgroundOpacity = 82
elseif flavor == "Mainline" then
    local footer = S.Config("dataTexts")
    assert(footer.hideBlizzardBagBar == true and footer.bar1Slot1 == 3,
        "Retail starter bar must provide a bag DataText before hiding Blizzard bags")
    local older = { suite = { modules = {
        dataTexts = { bar1Slot1 = 2, bar1Slot2 = 5, bar1Slot3 = 6 },
        damageMeter = { bgColor = "000000" },
    } } }
    S.Normalize(older)
    assert(older.suite.modules.dataTexts.hideBlizzardBagBar == false
        and older.suite.modules.damageMeter.look == 4,
        "existing Retail profiles lost bag access or mislabelled a custom meter")
    footer.bar1Slot1, footer.bar1Slot3 = 2, 6
end
H.Enable(W, { infoFPS = true, infoClock = false, infoLocation = false })
local before = reads.fps
assert(S.Set("dataTexts", "enabled", true))
if nativeBag then
    assert(not nativeBag.shown and nativeBag.driver == "hide",
        "native bag buttons remained visible beside the bag DataText")
    nativeBag:Show()
    assert(not nativeBag.shown, "Blizzard re-showed the bag bar")
    assert(S.Set("dataTexts", "hideBlizzardBagBar", false))
    assert(nativeBag.shown and nativeBag.driver == nil,
        "bag toggle did not restore Blizzard buttons")
    assert(S.Set("dataTexts", "hideBlizzardBagBar", true))
    assert(not nativeBag.shown and nativeBag.driver == "hide",
        "bag toggle did not hide Blizzard buttons again")
end
assert(S.states.dataTexts.active and M.bars[1].frame:IsShown()
    and M.bars[1].slots[1].text == "Gold: 10g"
    and M.bars[1].slots[2].text == "Durability: 80%"
    and M.bars[1].slots[3].text == "FPS: 80",
    "starter bar did not render its selected sources")
assert(reads.fps == before and W.Pending() == 1,
    "minimap and DataTexts did not reuse the FPS sample and timer")
fps = 40
W.Advance(2)
assert(reads.fps == before + 1 and M.bars[1].slots[3].text == "FPS: 40" and W.Pending() == 1,
    "shared timer did not read FPS once for both displays")
local bar = M.bars[1]
local textureWrites, fontWrites = 0, 0
local setTexture, setFont = bar.background.SetTexture, bar.slots[1].label.SetFont
function bar.background:SetTexture(...)
    textureWrites = textureWrites + 1
    return setTexture(self, ...)
end
bar.slots[1].label.SetFont = function(self, ...)
    fontWrites = fontWrites + 1
    return setFont(self, ...)
end
assert(S.SetMany("dataTexts", {
    backgroundTexture = "TestTexture", font = "TestFont", textOutline = 2,
    customColors = true, backgroundColor = "123456", labelColor = "abcdef", valueColor = "fedcba",
    borderEnabled = false, accentEnabled = false, separatorEnabled = true,
    separatorSize = 2, gap = 6, padding = 8, textAlign = 1,
}))
assert(bar.background.texture == "Interface\\AddOns\\Test\\Media\\bar.tga"
    and bar.background.vertex[1] == 0x12 / 255 and bar.background.vertex[4] == .82
    and not bar.border[1]:IsShown() and not bar.accent:IsShown()
    and bar.dividers[1] and bar.dividers[1]:IsShown() and bar.dividers[1].width == 2
    and bar.slots[1].label.font[1] == "Interface\\AddOns\\Test\\Media\\font.ttf"
    and bar.slots[1].label.font[3] == "THICKOUTLINE"
    and bar.slots[1].label.justify == "LEFT"
    and bar.slots[1].label.text:find("|cffabcdefGold: |r|cfffedcba10g|r", 1, true),
    "custom texture, colors, outline, alignment or dividers were not applied")
local styledTextureWrites, styledFontWrites = textureWrites, fontWrites
W.Advance(2)
assert(textureWrites == styledTextureWrites and fontWrites == styledFontWrites,
    "sampled data update repeated cold-path texture or font styling")
assert(W.movers["MSUFSuite.dataTexts/bar1"], "DataTexts bar is missing in Edit Mode")
money = 112345
W.Event("PLAYER_MONEY")
assert(M.bars[1].slots[1].text == "Gold: 11g", "gold event did not update the bar")
money = W.secret
W.Event("PLAYER_MONEY")
assert(M.bars[1].slots[1].text == "Gold: —", "secret gold was formatted")
money = 100000
W.Suite.RootDB.suiteGold = { ["Player-1"] = 100000 }
W.Suite.loginKind, W.Suite.goldSessionCaptured = "login", false
assert(S.Set("dataTexts", "bar1Slot4", 11))
assert(M.bars[1].slots[4].text == "Session: —", "saved gold was shown before the login baseline was captured")
W.Suite.goldSessionCaptured = true
money = 112345
W.Event("PLAYER_MONEY")
assert(M.bars[1].slots[4].text == "Session: +1g 23s 45c",
    "session gold lost silver or copper")
money = 99901
W.Event("PLAYER_MONEY")
assert(M.bars[1].slots[4].text == "Session: −99c", "session gold loss was formatted incorrectly")
money = 100000
G.UnitGUID = function() return W.secret end
W.Event("PLAYER_MONEY")
assert(M.bars[1].slots[4].text == "Session: —", "secret character ID was inspected")
G.UnitGUID = function() return "Player-1" end
W.Event("PLAYER_MONEY")
assert(S.SetMany("dataTexts", { bar2Enabled = true, bar2Slot1 = 7, bar2Slot2 = 8 }))
assert(M.bars[2].frame:IsShown() and W.movers["MSUFSuite.dataTexts/bar2"],
    "second bar did not become movable")
assert(M.bars[2].style.valueColor == "fedcba", "second bar did not inherit the shared style")
assert(S.SetMany("dataTexts", { bar2StyleOverride = true, bar2CustomColors = true,
    bar2ValueColor = "00ff00", bar2BorderEnabled = true }))
assert(M.bars[2].style.valueColor == "00ff00" and M.bars[2].border[1]:IsShown()
    and M.bars[1].style.valueColor == "fedcba", "own bar style changed another bar")
assert(S.Set("dataTexts", "bar1Visibility", 4))
assert(M.bars[1].frame.alpha == 0, "mouseover bar was still visible")
assert(S.Set("dataTexts", "bar2Enabled", false))
assert(S.Set("minimap", "infoFPS", false))
assert(W.Pending() == 0, "hidden bars kept a sampled data timer")
W.Fire(M.bars[1].frame, "OnEnter")
assert(M.bars[1].frame.alpha == 1 and W.Pending() == 1,
    "mouse entry did not resume sampled data")
W.Fire(M.bars[1].frame, "OnLeave")
assert(M.bars[1].frame.alpha == 0 and W.Pending() == 0,
    "mouse exit did not cancel sampled data")
assert(S.Set("dataTexts", "enabled", false))
if nativeBag then
    assert(nativeBag.shown and not nativeBag.driver,
        "disabling DataTexts did not restore Blizzard's bag bar")
end
assert(not M.bars[1].frame:IsShown() and not M.bars[2].frame:IsShown()
    and not M.context.callbacks.PLAYER_MONEY,
    "disabling DataTexts left a frame or money event active")
assert(W.Pending() == 0, "disabled information displays kept a timer")
print("Suite DataTexts: starter bars, shared samples/timer, events, secrets, Edit Mode and disable passed: " .. flavor)
