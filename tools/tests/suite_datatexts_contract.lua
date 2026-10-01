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
    G.GetPhysicalScreenSize = function() return 1024, 768 end
    G.C_Container = {
        GetContainerNumSlots = function() return 20 end,
        GetContainerNumFreeSlots = function() return 8, 0 end,
    }
    G.UnitLevel = function() return 20 end
    G.UnitXP = function() return 200 end
    G.UnitXPMax = function() return 1000 end
    G.UnitGUID = function() return "Player-1" end
    G.UnitName = function() return "Alice" end
    G.GetRealmName = function() return "Realm" end
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
-- MSUF's font comes from the shared media table and money text from the
-- shared helper; DataTexts keeps its own sign characters.
local MEDIA_FONT = "Interface\\AddOns\\Test\\Media\\MSUF.ttf"
W.Suite.MSUFMedia.font = MEDIA_FONT
local sharedMoneyText, moneyTexts = S.MoneyText, 0
S.MoneyText = function(amount)
    moneyTexts = moneyTexts + 1
    return sharedMoneyText(amount)
end
-- The client loads every file of the addon's TOC, Sources.lua included.
W.LoadAddon("MSUF_Suite_DataTexts")
local M = assert(S.instances.dataTexts)
assert(not M.bars[1] and W.Pending() == 0, "dormant DataTexts allocated a visible bar or timer")
-- The shared data timer reuses one task table per owner for every tick.
local probeTicks = 0
local function Probe() probeTicks = probeTicks + 1 end
local firstTask = S.ScheduleDataTick("probe", 1, Probe)
assert(S.ScheduleDataTick("probe", 1, Probe) == firstTask, "a data tick allocated a new task table")
W.Advance(1)
assert(probeTicks == 1 and S.ScheduleDataTick("probe", 1, Probe) == firstTask, "a rescheduled tick allocated")
firstTask:Cancel()
W.Advance(1)
assert(probeTicks == 1 and W.Pending() == 0, "a cancelled data tick still fired or kept its timer")
local defaultLook = 5
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
assert(legacyLooks.suite.revision == S.MigrationRevision
    and legacyLooks.suite.lookPresetRevision == nil
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
    assert(footer.enabled and footer.bar1Point == 9 and footer.bar1X == -20 and footer.bar1Width == 340
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
    assert(old.suite.revision == S.MigrationRevision
        and old.suite.modules.dataTexts.bar1Width == 340
        and old.suite.modules.dataTexts.bar1Layout == 2
        and old.suite.modules.dataTexts.bar1Point == 9 and old.suite.modules.dataTexts.bar1X == -20
        and old.suite.modules.damageMeter.w1Y == 60
        and old.suite.modules.damageMeter.w2Y == 250
        and old.suite.modules.actionbars.bar1Visibility == 4
        and old.suite.modules.actionbars.bar12Visibility == 4
        and old.suite.modules.actionbars.enabled == true
        and old.suite.modules.chat.inputColor == "111517"
        and old.suite.modules.buffReminders.borderColor == "d8b66a"
        and old.suite.modules.cooldownManager.bar_barColor == "d8b66a",
        "old Forever factory layout was not repaired")
    old.suite.modules.actionbars.enabled = false
    S.Normalize(old)
    assert(old.suite.modules.actionbars.enabled == false,
        "a later ActionBars disable must survive normalization")
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
        and custom.suite.modules.dataTexts.bar1Point == 9
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
    assert(footer.hideBlizzardBagBar == true and footer.bar1Point == 8 and footer.bar1Slot1 == 3,
        "Retail starter bar must provide a bag DataText before hiding Blizzard bags")
    local installed = { suite = { modules = { dataTexts = {
        bar1Point = 9, bar1X = 0, bar1Y = 170,
    } } } }
    S.Normalize(installed)
    assert(installed.suite.modules.dataTexts.bar1Point == 8
        and installed.suite.modules.dataTexts.bar1Y == 170,
        "old Suite DataTexts preset was not centered")
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
assert(M.bars[1].slots[1].label.font[1] == MEDIA_FONT,
    "DataTexts did not take MSUF's font from the shared media table")
assert(reads.fps == before and W.Pending() == 1,
    "minimap and DataTexts did not reuse the FPS sample and timer")
local fpsRecord = M.values.fps
fps = 40
W.Advance(2)
assert(reads.fps == before + 1 and M.bars[1].slots[3].text == "FPS: 40" and W.Pending() == 1,
    "shared timer did not read FPS once for both displays")
assert(M.values.fps == fpsRecord, "a changed sample allocated a new value record")
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
    backgroundTexture = "TestTexture", font = "TestFont", textOutline = 2, fontRendering = 1,
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
assert(S.SetMany("dataTexts", { fontRendering = 2, fontShadow = true,
    fontShadowOpacity = 65, fontShadowDistance = 2 }))
assert(bar.slots[1].label.font[3] == "THICKOUTLINE,MONOCHROME"
    and bar.slots[1].label.shadowColor[4] == 0.65
    and bar.slots[1].label.shadowOffset[1] == 2,
    "DataText Sharp font or shadow was not applied")
assert(S.Set("dataTexts", "fontRendering", 3))
assert(bar.slots[1].label.font[3] == "OUTLINE,SLUG"
    and bar.slots[1].label.shadowColor[4] == 0,
    "DataText Slug retained a shadow")
local pixelBefore = { bar1X = S.Config("dataTexts").bar1X,
    bar1Y = S.Config("dataTexts").bar1Y,
    bar1Width = S.Config("dataTexts").bar1Width,
    bar1Height = S.Config("dataTexts").bar1Height,
    bar1Layout = S.Config("dataTexts").bar1Layout,
    borderEnabled = S.Config("dataTexts").borderEnabled,
    accentEnabled = S.Config("dataTexts").accentEnabled }
G.GetPhysicalScreenSize = function() return 800, 512 end
assert(S.SetMany("dataTexts", { bar1X = 11, bar1Y = 83, bar1Width = 395,
    bar1Height = 26, bar1Layout = 1, borderEnabled = true, accentEnabled = true }))
local pixelBar = M.bars[1]
local _, _, _, px, py = pixelBar.frame:GetPoint()
assert(px == 10.5 and py == 82.5
    and pixelBar.frame.width == 394.5 and pixelBar.frame.height == 25.5
    and pixelBar.border[1].height == 1.5 and pixelBar.accent.height == 1.5,
    ("DataTexts physical grid: x=%s y=%s w=%s h=%s border=%s accent=%s")
        :format(tostring(px), tostring(py), tostring(pixelBar.frame.width),
            tostring(pixelBar.frame.height), tostring(pixelBar.border[1].height),
            tostring(pixelBar.accent.height)))
G.GetPhysicalScreenSize = function() return 1024, 768 end
W.Event("DISPLAY_SIZE_CHANGED")
assert(pixelBar.border[1].height == 1 and pixelBar.accent.height == 1,
    "DataTexts did not refresh pixel strokes after screen resolution changed")
G.UIParent:SetScale(0.5)
W.Event("UI_SCALE_CHANGED")
assert(pixelBar.border[1].height == 2 and pixelBar.accent.height == 2,
    "DataTexts did not refresh pixel strokes after UI scale changed")
G.UIParent:SetScale(1)
W.Event("UI_SCALE_CHANGED")
assert(S.SetMany("dataTexts", pixelBefore))
local styledTextureWrites, styledFontWrites = textureWrites, fontWrites
W.Advance(2)
assert(textureWrites == styledTextureWrites and fontWrites == styledFontWrites,
    "sampled data update repeated cold-path texture or font styling")
local dataMover = assert(W.movers["MSUFSuite.dataTexts/bar1"], "DataTexts bar is missing in Edit Mode")
assert(dataMover.centerPopup == true, "DataTexts Edit Mode popup did not request the screen center")
assert(#dataMover.extraControls == 4
    and dataMover.extraControls[1].id == "bar1X"
    and dataMover.extraControls[2].id == "bar1Y"
    and dataMover.extraControls[3].id == "width"
    and dataMover.extraControls[4].id == "height",
    "DataTexts popup must expose exact position, width and height")
local dataBefore = dataMover.captureState()
assert(dataMover.extraControls[4].set(34) and S.Config("dataTexts").bar1Height == 34
    and dataMover.restoreState(dataBefore)
    and S.Config("dataTexts").bar1Height == dataBefore.values.bar1Height,
    "DataTexts popup height must apply and support undo")
money = 112345
W.Event("PLAYER_MONEY")
assert(M.bars[1].slots[1].text == "Gold: 11g", "gold event did not update the bar")
assert(S.Set("dataTexts", "trackAltGold", true))
assert(W.Suite.RootDB.goldLedger and W.Suite.RootDB.goldLedger["Player-1"]
    and W.Suite.RootDB.goldLedger["Player-1"].money == 112345,
    "gold ledger did not capture the current character when enabled")
-- A slot opens Blizzard's matching window out of combat (bags for gold, the
-- character sheet for durability; FPS has none) and explains its value.
do
    local opened, slots = {}, M.bars[1].slots
    W.G.OpenAllBags = function() opened[#opened + 1] = "bags" end
    W.G.ToggleCharacter = function(tab) opened[#opened + 1] = tab end
    for i = 1, 3 do W.Fire(slots[i], "OnClick", "LeftButton") end
    assert(#opened == 2 and opened[1] == "bags" and opened[2] == "PaperDollFrame",
        "DataText clicks did not open the gold and durability windows")
    W.combat = true
    W.Fire(slots[1], "OnClick", "LeftButton")
    W.combat = false
    assert(#opened == 2, "a DataText click opened a window in combat")
    local tip = W.G.GameTooltip
    W.Fire(slots[1], "OnEnter")
    assert(tip.shown and tip.owner == slots[1] and tip.lines[1] == W.Suite.DataTextSources[slots[1].sourceIndex]
        and tip.lines[2] == "Current | 11g 23s 45c", "the gold DataText tooltip did not show the full amount")
    W.Fire(slots[1], "OnLeave")
    assert(not tip.shown, "leaving a DataText kept its tooltip")
end
money = W.secret
W.Event("PLAYER_MONEY")
assert(M.bars[1].slots[1].text == "Gold: —", "secret gold was formatted")
assert(W.Suite.RootDB.goldLedger["Player-1"].money == 112345,
    "secret gold was stored in the account ledger")
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
assert(moneyTexts > 0, "session gold did not use the shared S.MoneyText")
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
local rebinds, rebind = 0, M.Rebind
M.Rebind = function(...) rebinds = rebinds + 1; return rebind(...) end
M.bars[1].frame.mouseOver = true
W.Fire(M.bars[1].slots[1], "OnEnter")
W.Fire(M.bars[1].slots[1], "OnLeave")
W.Fire(M.bars[1].slots[2], "OnEnter")
W.Fire(M.bars[1].slots[2], "OnLeave")
M.bars[1].frame.mouseOver = nil
M.Rebind = rebind
assert(rebinds == 0 and M.bars[1].frame.alpha == 1 and W.Pending() == 1,
    "moving between slots of a hovered bar rebound its data sources")
W.Fire(M.bars[1].frame, "OnLeave")
assert(M.bars[1].frame.alpha == 0 and W.Pending() == 0,
    "mouse exit did not cancel sampled data")
-- Auto-layout bars relayout on every changed value, so the relayout itself
-- must not allocate. The widgets are allocation-free stand-ins here.
do
    local Layout
    for index = 1, 60 do
        local name, value = debug.getupvalue(M.UpdateSource, index)
        if not name or name == "Layout" then
            Layout = value
            break
        end
    end
    assert(type(Layout) == "function", "DataTexts relayout function not found")
    local function Quiet() end
    local function Label() return 30 end
    local function Widget()
        return { ClearAllPoints = Quiet, SetPoint = Quiet, SetSize = Quiet, Show = Quiet, Hide = Quiet,
            GetStringWidth = Label, GetUnboundedStringWidth = Label }
    end
    local config = S.Config("dataTexts")
    local layout = config.bar1Layout
    local bar = { prefix = "bar1", widthKey = "bar1Width", heightKey = "bar1Height", layoutKey = "bar1Layout",
        style = { gap = 6, padding = 8, separatorEnabled = true, separatorSize = 2 },
        frame = { GetWidth = function() return config.bar1Width end, SetWidth = Quiet },
        slots = {}, dividers = {} }
    for slot = 1, 6 do
        local button = Widget()
        button.source, button.label = "fps", Widget()
        bar.slots[slot], bar.dividers[slot] = button, Widget()
    end
    for _, mode in ipairs({ 1, 2 }) do
        config.bar1Layout = mode
        Layout(bar)
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 200 do Layout(bar) end
        local grown = collectgarbage("count") - before
        collectgarbage("restart")
        assert(grown < 1, "a DataTexts relayout allocated tables (" .. grown .. " KB for 200 relayouts)")
    end
    config.bar1Layout = layout
end
assert(S.Set("dataTexts", "enabled", false))
if nativeBag then
    assert(nativeBag.shown and not nativeBag.driver,
        "disabling DataTexts did not restore Blizzard's bag bar")
end
assert(not M.bars[1].frame:IsShown() and not M.bars[2].frame:IsShown()
    and not M.context.callbacks.PLAYER_MONEY,
    "disabling DataTexts left a frame or money event active")
assert(W.Pending() == 0, "disabled information displays kept a timer")
-- New choices append to the existing index table so saved slot selections
-- retain their meaning. Both sampled values share the active bar's timer.
G.date = function(format)
    assert(format == "%d-%m-%Y")
    return "26-09-2026"
end
assert(S.SetMany("dataTexts", { bar1Slot1 = 12, bar1Slot2 = 13,
    bar1Slot3 = 1, bar1Visibility = 1, valueClassColor = true }))
assert(S.Set("dataTexts", "enabled", true))
assert(M.bars[1].slots[1].text == "Date: 26-09-2026"
    and M.bars[1].slots[2].text == "FPS / World: 40 / 50 ms"
    and M.bars[1].style.valueColor == "3366cc"
    and W.Pending() == 1, "date, combined FPS/latency or class-color DataText failed")
assert(S.Set("dataTexts", "enabled", false) and W.Pending() == 0,
    "new sampled sources remained active after disable")
-- The optional antique strip owns its style and values without changing the
-- other bars. Its toggles repaint in the current session on both clients.
do
    local c = S.Config("dataTexts")
    local bar1Width = c.bar1Width
    assert(S.SetMany("dataTexts", W.Suite.DataTextAntiqueFooterValues(2, c)))
    local ornate = M.bars[2]
    assert(c.bar1Width == bar1Width and c.bar2StyleOverride and c.bar2Width == 380
        and c.bar2Height == 36 and c.bar2FontSize == 11 and c.bar2BagBadgeSize == 38
        and c.bar2Slot1 == 3 and c.bar2Slot2 == 4 and c.bar2Slot3 == 5
        and ornate.frame:IsShown() and ornate.badge:IsShown() and ornate.gradient:IsShown()
        and not ornate.background:IsShown(), "antique footer did not apply to bar 2 alone")
    assert(ornate.slots[1].text == "Bags 60%" and ornate.slots[2].text == "Durability 80%"
        and ornate.slots[3].text == "14:03",
        "antique footer labels, used-bag percent or clock did not render")
    assert(ornate.slots[1].points[1][4] == 46 and ornate.accent.points[1][1] == "TOPLEFT"
        and ornate.dividers[1]:IsShown() and ornate.dividers[2]:IsShown(),
        "antique footer badge spacing, top line or separators did not render")
    local opens = 0
    G.OpenAllBags = function() opens = opens + 1 end
    W.Fire(ornate.badge, "OnClick", "LeftButton")
    assert(opens == 1 and ornate.badge.text == "Bags 60%",
        "antique footer badge did not open bags or show the current usage")
    assert(S.Set("dataTexts", "bar2Slot1", 1))
    assert(M.activeSources.bags and ornate.badge.text == "Bags 60%",
        "bag badge stopped updating after its text slot was removed")
    assert(S.Set("dataTexts", "bar2Slot1", 3))
    assert(S.Set("dataTexts", "bar2BagsPercent", false))
    assert(ornate.slots[1].text == "Bags 40/100", "bag percent toggle did not repaint")
    assert(S.Set("dataTexts", "bar2BagsPercent", true))
    assert(ornate.slots[1].text == "Bags 60%", "bag percent toggle did not restore")
    assert(S.Set("dataTexts", "bar2LabelColon", true))
    assert(ornate.slots[1].text == "Bags: 60%" and ornate.slots[2].text == "Durability: 80%",
        "label punctuation toggle did not repaint")
    assert(S.Set("dataTexts", "bar2LabelColon", false))
    assert(ornate.slots[1].text == "Bags 60%", "label punctuation toggle did not restore")
    assert(S.Set("dataTexts", "bar2ClockLabel", true))
    assert(ornate.slots[3].text == "Time 14:03", "clock label toggle did not repaint")
    assert(S.Set("dataTexts", "bar2ClockLabel", false))
    assert(ornate.slots[3].text == "14:03", "clock label toggle did not restore")
    assert(S.Set("dataTexts", "bar2BagBadge", false))
    assert(not ornate.badge:IsShown() and ornate.slots[1].points[1][4] == 0,
        "bag medallion toggle did not release its layout space")
    assert(S.Set("dataTexts", "bar2BagBadge", true))
    assert(ornate.badge:IsShown() and ornate.slots[1].points[1][4] == 46,
        "bag medallion toggle did not restore its layout space")
    assert(S.Set("dataTexts", "bar2BagBadgeSize", 80))
    assert(ornate.badge.width == 80 and ornate.slots[1].points[1][4] == 88,
        "bag medallion size did not resize the icon and its content inset")
    assert(S.Set("dataTexts", "bar2BagBadgeSize", 38))
    assert(S.Set("dataTexts", "bar2BackgroundGradient", false))
    assert(not ornate.gradient:IsShown() and ornate.background:IsShown(),
        "background fade toggle did not reveal the plain background")
    assert(S.Set("dataTexts", "bar2BackgroundGradient", true))
    assert(ornate.gradient:IsShown() and not ornate.background:IsShown(),
        "background fade toggle did not restore the gradient")
    assert(S.Set("dataTexts", "bar2BackgroundFadeColor", "224466"))
    assert(ornate.gradient.gradient[2][1] == 0x22 / 255,
        "background fade color did not repaint")
    assert(S.Set("dataTexts", "bar2SeparatorEnabled", false))
    assert(not ornate.dividers[1]:IsShown() and not ornate.dividers[2]:IsShown(),
        "separator toggle did not hide the dividers")
    assert(S.Set("dataTexts", "bar2SeparatorEnabled", true))
    assert(ornate.dividers[1]:IsShown() and ornate.dividers[2]:IsShown(),
        "separator toggle did not restore the dividers")
    assert(S.Set("dataTexts", "bar2AccentPosition", 1))
    assert(ornate.accent.points[1][1] == "BOTTOMLEFT", "accent position toggle did not repaint")
    assert(S.Set("dataTexts", "bar2AccentPosition", 2))
    assert(ornate.accent.points[1][1] == "TOPLEFT", "accent position toggle did not restore")
    assert(S.Set("dataTexts", "bar2Enabled", false))
end
-- Retail and WoW Forever always have the APIs DataTexts calls. The one
-- client-specific hook target (Forever's MainActionBar_InitializeMKB) is a
-- plain existence check, not a type guard.
do
    local file = assert(io.open(root .. "/MSUF_Suite_DataTexts/DataTexts.lua", "rb"))
    local source = file:read("*a")
    file:close()
    local guarded = source:match("type%(([^)]*)%)%s*[~=]=%s*\"function\"")
    assert(not guarded, "DataTexts guards " .. tostring(guarded) .. " as if a client lacked it")
    assert(not source:find("C_Housing and", 1, true), "DataTexts guards C_Housing as if a client lacked it")
    -- GameTooltip and FontString:GetUnboundedStringWidth exist on both clients.
    local code = source:gsub("%-%-[^\n]*", "")
    local probe = code:match("(GameTooltip) and") or code:match("not (GameTooltip) or")
        or code:match("%.(GetUnboundedStringWidth) or")
    assert(not probe, "DataTexts probes " .. tostring(probe) .. " as if a client lacked it")
    -- Per-bar setting names are built once (BAR_KEYS); the event paths that
    -- sync events and visibility read them instead of concatenating keys.
    local _, enabledKeys = code:gsub('%.%. "Enabled"', "")
    local _, hideKeys = code:gsub('%.%. "LoadCondHideIn', "")
    assert(enabledKeys == 1 and hideKeys == 2, "DataTexts concatenates per-bar setting keys outside BAR_KEYS")
end
print("Suite DataTexts: starter bars, shared samples/timer, events, secrets, Edit Mode and disable passed: " .. flavor)
