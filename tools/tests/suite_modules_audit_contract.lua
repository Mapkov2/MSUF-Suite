local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")

-- The HUD modules (objective tracker, run summary, announcements, Mythic+,
-- raid view, AFK screen) after the modules audit: one check per finding.
-- Catalog checks load the real catalog file for both clients; the runtime
-- checks load the shipped module files over small client stand-ins.

-- The module a loaded file installs.
local Installed

local function Fail(message) error(message, 2) end
local function Check(condition, message) if not condition then Fail(message) end end

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function Upvalue(fn, wanted)
    for i = 1, 200 do
        local name, value = debug.getupvalue(fn, i)
        if not name then return nil end
        if name == wanted then return value end
    end
end

-- A frame or region stand-in that accepts every call and answers itself.
local function Widget()
    local widget = {}
    return setmetatable(widget, { __index = function(_, key)
        if key == "GetStringHeight" then return function() return 12 end end
        return function(self) return self end
    end })
end

local function Catalog(client, id)
    local _, ns = Support.CatalogDefaults(root, id or "objectives", "HUD", client)
    return ns
end
local RETAIL, FOREVER = { isForever = false }, { isForever = true }

local function Rgb(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

------------------------------------------------------------------ 1. conflicts
do
    local rules = Catalog(RETAIL).SuiteCatalog.objectives
    local found
    for _, name in ipairs(rules.conflicts) do found = found or name == "!KalielsTracker" end
    Check(found, "the objective tracker does not yield to Kaliel's Tracker (!KalielsTracker)")
end

------------------------------------------------------------------ 2. text style
do
    for _, client in ipairs({ RETAIL, FOREVER }) do
        local ns = Catalog(client)
        for _, id in ipairs({ "objectives", "runSummary", "announcements" }) do
            local rules = ns.SuiteCatalog[id].rules
            Check(rules.fontOutline and rules.fontOutline.default == 2 and rules.fontOutline.choices[2] == "Outline",
                id .. ": the outline does not default to Outline")
            Check(rules.fontRendering.default == ns.FontRendering.SMOOTH, id .. ": rendering does not default to Smooth")
            Check(rules.fontShadow.default == true and rules.fontShadowOpacity.default == 70
                and rules.fontShadowDistance.default == 1, id .. ": the shadow does not default to the drawn one")
            Check(rules.fontShadowOpacity.enableKey == "fontShadow", id .. ": the shadow opacity is not linked to its switch")
            -- With no settings, and with the defaults, text is drawn as before.
            local config = {}
            for key, rule in pairs(rules) do config[key] = rule.default end
            for _, role in ipairs({ "body", "title", "subtitle", "banner" }) do
                local named = role ~= "body" and role or nil
                local plain, byDefault = { ns.HUDTextArgs(nil, named) }, { ns.HUDTextArgs(config, named) }
                for i = 1, 5 do
                    Check(plain[i] == byDefault[i], id .. ": default settings draw " .. role .. " text differently")
                end
            end
        end
        -- The fixed shadows of the three kinds of text: body 70/1, title 80/1,
        -- subtitle 75/1, banner headline 80/2.
        local function Args(role) return { ns.HUDTextArgs(nil, role) } end
        local body, title, subtitle, banner = Args(), Args("title"), Args("subtitle"), Args("banner")
        Check(body[1] == "OUTLINE" and body[2] == 1 and body[3] == true and body[4] == 70 and body[5] == 1,
            "the body text style is not the outlined, smooth, 70% 1 px shadow text")
        Check(title[4] == 80 and title[5] == 1 and subtitle[4] == 75 and subtitle[5] == 1
            and banner[4] == 80 and banner[5] == 2, "headline shadows differ from the ones always drawn")
        local choice = { ns.HUDTextArgs({ fontOutline = 1, fontRendering = 3, fontShadow = false, fontShadowOpacity = 40,
            fontShadowDistance = 2 }) }
        Check(choice[1] == "" and choice[2] == 3 and choice[3] == false and choice[4] == 40 and choice[5] == 2,
            "the text style choices are not passed on")
    end
    -- No module draws a hard-coded outline and shadow any more.
    for _, file in ipairs({ "ObjectivesTracker", "ObjectivesDetails", "MythicPlus", "Raid", "RunSummary", "RunSummaryParty",
        "Announcements" }) do
        Check(not Read("MSUF_Suite_Modules/" .. file .. ".lua"):find('"OUTLINE", 1, true', 1, true),
            file .. ".lua still draws a fixed outline and shadow")
    end
end

------------------------------------------------------------------ 3. greying links
do
    local retail = Catalog(RETAIL).SuiteCatalog
    local rules, summary = retail.objectives.rules, retail.runSummary.rules
    -- A setting that needs a choice is greyed for the choices not listed.
    local function Needs(rule, ruleset, key, values, name)
        Check(rule.requiresChoice and rule.requiresChoice.key == key, name .. " is not tied to " .. key)
        for index = 1, #ruleset[key].choices do
            Check((rule.requiresChoice.values[index] == true) == (values[index] == true),
                name .. " has the wrong state for " .. key .. " choice " .. index)
        end
    end
    Needs(rules.bossTargets, rules, "bossPace", { false, true, true, true, true }, "bossTargets")
    Needs(summary.playerRowHeight, summary, "partyDetails", { false, true, true, true }, "playerRowHeight")
    Check(rules.forcesBarHeight.enableKey == "showForcesBar" and rules.forcesBarWidth.enableKey == "showForcesBar",
        "the forces bar size is not tied to the forces bar")
    Check(rules.forcesTextSize.enableKey == "showForcesText", "the forces text size is not tied to the forces text")
    Check(rules.hideDuringBoss.disabledBy == "hideInRaid" and rules.pauseInRaidCombat.disabledBy == "hideInRaid",
        "the raid pause settings stay editable while the tracker is hidden throughout the raid")
    Check(rules.recipesColor.enableKey == "showRecipes", "the recipes color is not tied to the recipes switch")
    for _, rule in pairs(rules) do
        for _, field in ipairs({ "enableKey", "disabledBy" }) do
            local target = rule[field]
            Check(target == nil or rules[target] and type(rules[target].default) == "boolean",
                rule.key .. "." .. field .. " names no switch: " .. tostring(target))
        end
    end
end

------------------------------------------------------------------ 4. recipes
do
    local retail, forever = Catalog(RETAIL).SuiteCatalog.objectives.rules, Catalog(FOREVER).SuiteCatalog.objectives.rules
    Check(retail.showRecipes and retail.showRecipes.default == true, "tracked recipes have no switch, or it defaults off")
    Check(retail.recipesColor and retail.recipesColor.default == retail.questsColor.default,
        "the recipes color does not start as the quest color")
    Check(not forever.showRecipes and not forever.recipesColor, "Forever offers recipe settings without recipes")
    local prepare = Catalog(RETAIL).SuiteCatalog.objectives.prepareConfig
    local saved = { questsColor = "336699" }
    prepare(saved)
    Check(saved.recipesColor == "336699", "a customized quest color is not carried over to recipes")
    saved.questsColor = "112233"
    prepare(saved)
    Check(saved.recipesColor == "336699", "the recipes color carry-over is not one-shot")
    Check(Catalog(FOREVER).SuiteCatalog.objectives.prepareConfig == nil, "Forever prepares a recipes color it has no rule for")
    -- Switched off, the collector reads nothing; on, it reads both lists.
    local reads = 0
    C_TradeSkillUI = { GetRecipesTracked = function() reads = reads + 1; return {} end }
    local function Public(value) return value ~= nil end
    local S = { Public = Public, Finite = function(v) return type(v) == "number" end, PublicText = function(v) return v end }
    local private = { Suite = S, NS = { Client = RETAIL } }
    assert(loadfile(root .. "/MSUF_Suite_Modules/ObjectivesData.lua"))("MSUF_Suite_Modules", private)
    local collect = private.Objectives.COLLECTORS.recipes
    collect({ count = 0 }, { showRecipes = false })
    Check(reads == 0, "tracked recipes were read with the switch off")
    collect({ count = 0 }, { showRecipes = true })
    Check(reads == 2, "tracked recipes were not read with the switch on")
    -- The tracker colors the recipes group by its own setting, and the late color too.
    local widgetS = { Text = function(v) return v end, Public = Public, Finite = S.Finite, PublicText = S.PublicText,
        ResolveFont = function() return "font" end, GlobalFontPath = function() return "font" end,
        RGB = function(hex) return Rgb(hex) end, SetStyledFont = function() end, MythicPlus = nil }
    local O = { M = {}, SOURCES = {}, Read = function() end, FlatSlot = function() end, EntryBase = function() end,
        AddFlat = function() end, SameItem = function() end, ApplyHeading = function() end }
    local trackerPrivate = { NS = { Client = RETAIL, HUDTextArgs = function() end }, Suite = widgetS, Objectives = O }
    local chunk = assert(loadstring(Read("MSUF_Suite_Modules/ObjectivesTracker.lua") .. "\nO.TestTheme = Theme"))
    chunk("MSUF_Suite_Modules", trackerPrivate)
    local config = {}
    for key, rule in pairs(retail) do config[key] = rule.default end
    config.colorStyle, config.recipesColor, config.lateColor = 2, "336699", "112233"
    local owner = { config = config, background = Widget(), title = Widget(), count = Widget(), divider = Widget() }
    O.TestTheme(owner)
    local group, own = owner.groupRGB.recipes, { Rgb("336699") }
    Check(math.abs(group[1] - own[1]) < 1e-6 and math.abs(group[3] - own[3]) < 1e-6,
        "the recipes group does not use its own color")
    local late = { Rgb("112233") }
    Check(math.abs(owner.lateRGB[1] - late[1]) < 1e-6, "the over-time color ignores its setting")
    config.colorStyle = 1
    O.TestTheme(owner)
    Check(math.abs(owner.groupRGB.recipes[1] - .91) < 1e-6 and owner.lateRGB[1] == .92,
        "the default look of recipes or the over-time color changed")
end

------------------------------------------------------------------ 5. raid view gate
do
    for _, client in ipairs({ RETAIL, FOREVER }) do
        local rules = Catalog(client).SuiteCatalog.objectives.rules
        Check(rules.showRaid and rules.showRaid.default == false, "the raid view switch is missing or on by default")
    end
    -- Raid.lua defines the view on both clients (Forever used to return early).
    for _, client in ipairs({ RETAIL, FOREVER }) do
        local S = { Finite = function(v) return type(v) == "number" end, Public = function() return true end,
            PublicText = function(v) return v end, Text = function(v) return v end, ClockText = tostring,
            Dispatch = function(fn, ...) return fn(...) end, CharacterData = function() return nil end }
        local private = { NS = { Client = client, IsSecret = function() return false end, Finish = function() end,
            HUDTextArgs = function() end }, Suite = S }
        assert(loadfile(root .. "/MSUF_Suite_Modules/RaidRecords.lua"))("MSUF_Suite_Modules", private)
        assert(loadfile(root .. "/MSUF_Suite_Modules/Raid.lua"))("MSUF_Suite_Modules", private)
        Check(type(S.Raid) == "table" and type(S.Raid.Detect) == "function",
            "the raid encounter view is missing on " .. (client.isForever and "Forever" or "Retail"))
    end
end

------------------------------------------------------------------ 6. preview samples
do
    local function Preview(client, config)
        local calls = { labels = {}, fills = {} }
        local V = { Choices = {}, Render = {}, Views = nil }
        function V.Label(_, text, x, y, width, size, color, role)
            calls.labels[#calls.labels + 1] = { text = text, size = size, color = color, role = role }
            return Widget()
        end
        function V.Fill(_, x, y, width, height, color)
            calls.fills[#calls.fills + 1] = { x = x, y = y, width = width, height = height, color = color }
            return Widget()
        end
        function V.Color(c, key, fallback)
            if c.colorStyle == 2 then return Rgb(c[key]) end
            return unpack(fallback)
        end
        local P = { HUDPreview = V, Tr = function(text) return text end, Suite = { Client = client },
            RGB = function(hex) return Rgb(hex) end }
        for _, file in ipairs({ "HUDPreviewSamples", "HUDPreviewViews" }) do
            assert(loadfile(root .. "/MSUF_Suite_Options/Pages/" .. file .. ".lua"))("MSUF_Suite_Options", P)
        end
        return V, calls, { config = config }
    end
    local function Defaults(client)
        local config = {}
        for key, rule in pairs(Catalog(client).SuiteCatalog.objectives.rules) do config[key] = rule.default end
        return config
    end
    local function Choices(V)
        local seen = {}
        for _, choice in ipairs(V.Choices.objectives) do seen[choice[1]] = true end
        return seen
    end
    local function Draw(client, mode, change)
        local config = Defaults(client)
        config.colorStyle = 2
        for key, value in pairs(change or {}) do config[key] = value end
        local V, calls, ui = Preview(client, config)
        V.Render.objectives(ui, mode)
        return calls, config
    end
    local retail = Choices((Preview(RETAIL, Defaults(RETAIL))))
    for _, mode in ipairs({ "bonus", "focused", "campaign", "important", "complete", "recipes", "mythic", "mythicLate", "raid" }) do
        Check(retail[mode], "the tracker preview cannot show " .. mode)
    end
    local forever = Choices((Preview(FOREVER, Defaults(FOREVER))))
    Check(forever.raid and not forever.mythic and not forever.recipes, "the Forever preview offers the wrong views")
    -- A group's heading takes the group's own color.
    for mode, key in pairs({ bonus = "bonusColor", focused = "focusedColor", campaign = "campaignColor",
        important = "importantColor", complete = "completeGroupColor", recipes = "recipesColor" }) do
        local calls, config = Draw(RETAIL, mode, { [key] = "123456" })
        local r = Rgb(config[key])
        local heading = calls.labels[3] -- after the tracker title and its count
        Check(heading and math.abs(heading.color[1] - r) < 1e-6, mode .. " does not use " .. key)
    end
    -- Group underlines replace the stripe with a line under the heading.
    local plain = Draw(RETAIL, "quests", { groupUnderlines = false })
    local underlined = Draw(RETAIL, "quests", { groupUnderlines = true })
    Check(#underlined.fills ~= #plain.fills, "group underlines do not change the preview")
    -- The first fill is the header divider; the second the line under the heading.
    Check(underlined.fills[2].height == 4 and underlined.fills[2].width == 310 - 17,
        "the underline is not drawn under the heading")
    -- Bonus rows follow their switch.
    local hidden = Draw(RETAIL, "bonus", { showBonus = false })
    Check(#hidden.labels < #Draw(RETAIL, "bonus").labels, "the bonus switch does not change the preview")
    -- The Mythic+ view follows the bar, forces and pace settings; the over-time key uses the late color.
    local function Texts(calls)
        local all = {}
        for _, label in ipairs(calls.labels) do all[#all + 1] = tostring(label.text) end
        return table.concat(all, "\n")
    end
    local mythic = Draw(RETAIL, "mythic", { showForcesText = true, showForcesBar = false, bossPace = 1 })
    Check(Texts(mythic):find("ENEMY FORCES", 1, true), "the Mythic+ preview lacks the enemy forces line")
    Check(not Texts(mythic):find("Observed enemies", 1, true), "the observed pull shows while switched off")
    Check(Texts(Draw(RETAIL, "mythic", { showObservedPull = true })):find("Observed enemies", 1, true),
        "the observed pull is not previewed")
    Check(not Texts(Draw(RETAIL, "mythic", { showForcesText = false })):find("ENEMY FORCES", 1, true),
        "the forces text switch does not change the Mythic+ preview")
    local late = Draw(RETAIL, "mythicLate", { lateColor = "ff0000" })
    local sawLate
    for _, fill in ipairs(late.fills) do
        sawLate = sawLate or (fill.color[1] == 1 and fill.color[2] == 0 and fill.color[3] == 0)
    end
    Check(sawLate, "the over-time Mythic+ bar does not use the late color")
    Check(Texts(late):find("OVER", 1, true), "the over-time Mythic+ preview does not say so")
    -- The raid view exists on Forever as well.
    Check(Texts(Draw(FOREVER, "raid")):find("FASTEST KILL", 1, true), "the raid preview lacks the fastest kill")
end

------------------------------------------------------------------ 7. over-time color
do
    local retail = Catalog(RETAIL).SuiteCatalog.objectives.rules
    local default = { Rgb(retail.lateColor.default) }
    Check(math.abs(default[1] - .92) < .003 and math.abs(default[2] - .36) < .003 and math.abs(default[3] - .36) < .003,
        "the over-time color no longer starts as the red it always was")
    Check(not Catalog(FOREVER).SuiteCatalog.objectives.rules.lateColor, "Forever offers a Mythic+ color")
    local S = { Finite = function(v) return type(v) == "number" end, Public = function() return true end,
        PublicText = function(v) return v end, Text = function(v) return v end, ClockText = tostring,
        PublicField = function() end, CreateFontString = Widget, CreateFrame = Widget, CreateTexture = Widget,
        SetStyledFont = function() end }
    local private = { NS = { Client = RETAIL, HUDTextArgs = function() end }, Suite = S }
    assert(loadfile(root .. "/MSUF_Suite_Modules/MythicPlus.lua"))("MSUF_Suite_Modules", private)
    local Bracket = Upvalue(S.MythicPlus.Theme, "BracketColor") or Upvalue(Upvalue(S.MythicPlus.Theme, "ThemeBars"), "BracketColor")
    Check(Bracket, "the Mythic+ bracket color function was not found")
    Check(Bracket({}, 0)[1] == .92, "the default over-time color changed")
    local chosen = { .1, .2, .3 }
    Check(Bracket({ lateRGB = chosen }, 0) == chosen, "the over-time bar ignores the chosen color")
end

------------------------------------------------------------------ 8. /msufruns without runs
do
    local printed, history = {}, {}
    local S = { Finite = function(v) return type(v) == "number" end, Public = function() return true end,
        PublicText = function(v) return v end, Text = function(v) return v end, ClockText = tostring,
        PublicField = function() end, Print = function(text) printed[#printed + 1] = text end,
        CharacterData = function() return { history = history } end, Install = function(_, module) Installed = module end,
        RaidRecords = {} }
    local private = { NS = { Client = RETAIL, AnchorPoints = {}, HUDTextArgs = function() end,
        IsCombatLocked = function() return true end }, Suite = S, RunSummaryParty = {} }
    SlashCmdList = {}
    assert(loadfile(root .. "/MSUF_Suite_Modules/RunSummary.lua"))("MSUF_Suite_Modules", private)
    local module = Installed
    -- An inactive module shows nothing (Show returns first), so only the answer is observed.
    local self = setmetatable({ active = false, config = {} }, { __index = module })
    Check(module.ShowHistory(self) == false, "an empty history reported a run to show")
    history[1] = { kind = "mythic", historyID = 1 }
    Check(module.ShowHistory(self) == true, "a saved run was not reported")
    history[1] = nil
    local register = Upvalue(module.Enable, "RegisterCommand")
    self.active = true
    register(self)
    SlashCmdList.MSUFSUITERUNS()
    Check(#printed == 1 and printed[1] == "No Mythic+ runs recorded yet.", "/msufruns said nothing without saved runs")
    history[1] = { kind = "mythic", historyID = 1 }
    SlashCmdList.MSUFSUITERUNS()
    Check(#printed == 1, "/msufruns complained although a run exists")
    self.active = false
    history[1] = nil
    SlashCmdList.MSUFSUITERUNS()
    Check(#printed == 1, "/msufruns answered while the module is off")
    -- The card no longer keeps raid records of its own.
    Check(not Read("MSUF_Suite_Modules/RunSummary.lua"):find("data.raidRecords", 1, true),
        "the run summary still owns a raid record store")
end

------------------------------------------------------------------ 9. one raid record store
do
    local now = 100
    GetTime = function() return now end
    local data = { objectives = {}, runSummary = {} }
    local S = { Finite = function(v) return type(v) == "number" and v == v end,
        CharacterData = function(owner) return data[owner] end }
    assert(loadfile(root .. "/MSUF_Suite_Modules/RaidRecords.lua"))("MSUF_Suite_Modules", { NS = {}, Suite = S })
    local R = S.RaidRecords
    -- Saved data of both former stores moves into the one store, nothing lost.
    data.runSummary.raidRecords = { ["9001:16"] = { best = 120, kills = 2 }, ["9002:15"] = { best = 300, kills = 1 } }
    data.objectives.raidRecords = { ["9001:16"] = { fastest = 150, best = { defeated = 1, remaining = 20 },
        bestPhases = { DBM = { stage = 2 } } }, ["9003:16"] = { fastest = 90 } }
    local records = R.Store()
    local shared = records["9001:16"]
    Check(shared.fastest == 120 and shared.kills == 2 and shared.best.remaining == 20 and shared.bestPhases.DBM.stage == 2,
        "the merge lost a fastest kill, a kill count or the tracker's wipe progress")
    Check(records["9002:15"].fastest == 300 and records["9002:15"].kills == 1 and records["9003:16"].fastest == 90,
        "the merge lost an encounter of one store")
    Check(data.runSummary.raidRecords == nil, "the run summary's former records stayed behind")
    Check(R.Store() == records and records["9001:16"].kills == 2, "adopting the former records twice changed them")
    -- A stronger saved record of the shared store wins over a weaker former one.
    data.runSummary.raidRecords = { ["9003:16"] = { best = 200, kills = 5 } }
    Check(R.Store()["9003:16"].fastest == 90 and records["9003:16"].kills == 5, "a weaker former record replaced a stronger one")
    -- One kill reported by both modules counts once and keeps its answer.
    local best, new, kills = R.Kill(records, "9100:16", 200)
    Check(best == 200 and new == true and kills == 1, "a first kill is not a new best")
    local best2, new2, kills2 = R.Kill(records, "9100:16", 200)
    Check(best2 == 200 and new2 == true and kills2 == 1 and records["9100:16"].kills == 1,
        "the second module's report of the same kill counted it again or lost the new best")
    now = 110
    local best3, new3, kills3 = R.Kill(records, "9100:16", 250)
    Check(best3 == 200 and new3 == false and kills3 == 2, "a slower later kill changed the fastest time")
    now = 120
    Check(select(2, R.Kill(records, "9100:16", 150)) == true and records["9100:16"].fastest == 150, "a faster kill is not recorded")
    -- An unknown character gets the figures of this kill alone.
    data.objectives = nil
    Check(R.Store() == nil, "an unknown character got a store")
    now = 200
    local solo, soloNew, soloKills = R.Kill(nil, "9200:16", 80)
    Check(solo == 80 and soloNew == true and soloKills == 1, "an unknown character's kill was not reported")
end

------------------------------------------------------------------ 10. owned-skins stub
do
    for _, addon in ipairs({ "MSUF_Suite", "MSUF_Suite_Modules" }) do
        for _, file in ipairs(Support.TocFiles(root, addon)) do
            if file:match("%.lua$") then
                Check(not Read(addon .. "/" .. file):find("RefreshOwnedSkins", 1, true),
                    addon .. "/" .. file .. " still mentions RefreshOwnedSkins")
            end
        end
    end
end

------------------------------------------------------------------ 11. AFK preview slots
do
    local rangedShown, usesAmmo = false, false
    C_PaperDollInfo = { IsRangedSlotShown = function() return rangedShown end }
    UnitUsesAmmo = function() return usesAmmo end
    UnitName = function() return "Tester" end
    GetZoneText = function() return "Zone" end
    GetInventoryItemTexture = function(_, slot) return 1000 + slot end
    GetInventoryItemLink = function() return nil end
    CreateFrame = function()
        local frame = Widget()
        frame.CreateTexture = function()
            local icon = Widget()
            icon.shown = true
            icon.Hide = function(self) self.shown = false end
            icon.Show = function(self) self.shown = true end
            icon.SetTexture = function(self, texture) self.texture = texture end
            return icon
        end
        return frame
    end
    local function Shown(client)
        local ns = Catalog(client)
        local V = { Render = {}, Label = function() return Widget() end, Fill = function() end }
        local P = { HUDPreview = V, Tr = function(text) return text end,
            Suite = { AFKSlots = ns.AFKSlots, AFKSlotCount = ns.AFKSlotCount, AFK_RANGED_ROW = ns.AFK_RANGED_ROW,
                AFK_AMMO_ROW = ns.AFK_AMMO_ROW, IsSecret = function() return false end } }
        assert(loadfile(root .. "/MSUF_Suite_Options/Pages/HUDAFKPreview.lua"))("MSUF_Suite_Options", P)
        local ui = { canvas = Widget() }
        V.Render.afkScreen(ui)
        local count, textures = 0, {}
        for index, icon in pairs(ui.afk.icons) do
            if icon.shown then
                count = count + 1
                textures[index] = icon.texture
            end
        end
        return count, textures
    end
    Check(Shown(RETAIL) == 18, "the Retail AFK preview does not list the 18 slots of the sheet")
    Check(Shown(FOREVER) == 18, "a Forever sheet without a ranged slot got extra preview slots")
    rangedShown = true
    local count, textures = Shown(FOREVER)
    Check(count == 19 and textures[19] == 1018, "the Forever AFK preview lacks the ranged slot")
    usesAmmo = true
    count, textures = Shown(FOREVER)
    Check(count == 20 and textures[20] == 1000, "the Forever AFK preview lacks the ammunition slot of an ammunition user")
    Check(Shown(RETAIL) == 18, "the ranged slot leaked into the Retail AFK preview")
end

------------------------------------------------------------------ 12. windows opened by rows
do
    local printed, opened, combat, gamepad = {}, {}, false, false
    local S = { Finite = function(v) return type(v) == "number" end, Public = function() return true end,
        Text = function(v) return v end, Print = function(text) printed[#printed + 1] = text end,
        GamepadUI = function() return gamepad end,
        CanOpenNativeWindow = function() return not combat and not gamepad end,
        PanelButton = function(panel) return { panel = panel } end }
    local NS = { IsCombatLocked = function() return combat end, RestrictedNotice = function() return "blocked" end }
    local O = { Read = function(fn, ...) return fn(...) end }
    local private = { NS = NS, Suite = S, Objectives = O }
    IsModifiedClick, IsShiftKeyDown = function() return false end, function() return false end
    ProfessionsFrame_LoadUI = function() opened.professions = true end
    C_TradeSkillUI = { IsRecipeProfessionLearned = function() return true end,
        OpenRecipe = function(id) opened.recipe = id end }
    EncounterJournal_LoadUI, MonthlyActivitiesFrame_OpenFrameToActivity = function() end, function(id) opened.activity = id end
    Enum = { ContentTrackingTargetType = { Achievement = 2, Profession = 3, Vendor = 1 } }
    local target
    C_ContentTracking = { GetCurrentTrackingTarget = function() return target, 5 end }
    for _, file in ipairs({ "ObjectivesActions", "ObjectivesContentActions" }) do
        assert(loadfile(root .. "/MSUF_Suite_Modules/" .. file .. ".lua"))("MSUF_Suite_Modules", private)
    end
    -- Every row that opens a window says so once in combat, and opens nothing.
    local rows = { { recipeID = 42, kind = "entry" }, { group = "travelersLog", contentID = 7, kind = "entry" } }
    combat = true
    for _, row in ipairs(rows) do
        printed, opened = {}, {}
        if row.recipeID then O.OnRecipeClick(row) else O.OnContentClick(row) end
        Check(#printed == 1 and printed[1] == "blocked" and next(opened) == nil,
            "a " .. (row.recipeID and "recipe" or "Traveler's Log") .. " click in combat did not refuse with the notice")
    end
    combat, printed, opened = false, {}, {}
    O.OnRecipeClick(rows[1])
    O.OnContentClick(rows[2])
    Check(opened.recipe == 42 and opened.activity == 7 and #printed == 0, "an allowed click did not open its window")
    -- Under the Gamepad UI nothing opens from the Suite; Blizzard's button takes the click.
    gamepad, printed, opened = true, {}, {}
    O.OnRecipeClick(rows[1])
    Check(next(opened) == nil and #printed == 0, "a recipe opened from the Suite under the Gamepad UI")
    local function Delegate(row)
        local attributes = {}
        row.SetAttribute = function(_, key, value) attributes[key] = value end
        O.RowPreClick(row, "LeftButton")
        return attributes.clickbutton and attributes.clickbutton.panel, row.secureWindow
    end
    local panel, secure = Delegate({ kind = "entry", recipeID = 42 })
    Check(panel == "professions" and secure == true, "a recipe row has no delegate to the professions window")
    Check(Delegate({ kind = "entry", recipeID = 42, isRecraft = true }) == nil, "a recraft row got a delegate")
    Check(Delegate({ kind = "entry", group = "travelersLog", contentID = 7 }) == "journal",
        "a Traveler's Log row has no delegate to the Adventure Guide")
    Check(Delegate({ kind = "entry", group = "endeavors", contentID = 7 }) == nil, "an Endeavors row got a delegate")
    for kind, expected in pairs({ [3] = "professions", [1] = "worldMap" }) do
        target = kind
        Check(Delegate({ kind = "entry", group = "collectibles", contentID = 9, contentType = 0 }) == expected,
            "a collectible with target type " .. kind .. " goes to the wrong window")
    end
    target = 2
    Check(Delegate({ kind = "entry", group = "collectibles", contentID = 9, contentType = 0 }) == nil,
        "an achievement target got a delegate")
end

------------------------------------------------------------------ 13. hooks into Blizzard's tracker
do
    local reported, hooks = {}, {}
    local S = { Finite = function(v) return type(v) == "number" end, Public = function() return true end,
        Text = function(v) return v end, GamepadUI = function() return false end,
        Dispatch = function(fn, ...)
            local ok, err = pcall(fn, ...)
            if not ok then reported[#reported + 1] = err end
        end, Install = function(_, module) Installed = module end }
    local NS = { Client = RETAIL, IsCombatLocked = function() return false end,
        Safety = { IsForbidden = function() return false end } }
    local O = { M = { dirty = {}, sources = {}, rows = {} }, SOURCES = {}, CONTENT_EVENTS = {}, COLLECTED_EVENTS = {} }
    hooksecurefunc = function(object, method, callback)
        local original = object[method]
        object[method] = function(self, ...)
            original(self, ...)
            callback(self, ...)
        end
        hooks[#hooks + 1] = method
    end
    ObjectiveTrackerFrame = { AddModule = function() end, GetChildren = function() end }
    UIWidgetObjectiveTracker = { MarkDirty = function() end }
    assert(loadfile(root .. "/MSUF_Suite_Modules/Objectives.lua"))("MSUF_Suite_Modules",
        { NS = NS, Suite = S, Objectives = O })
    local module = Installed
    local context = { HideControl = function() end, Scale = function() end }
    module.active, module.context, module.config = true, context, {}
    module:SuppressNative()
    Check(#hooks == 2, "the tracker did not hook Blizzard's AddModule and MarkDirty")
    -- A raising handler is reported and never reaches Blizzard's caller.
    context.HideControl = function() error("boom") end
    ObjectiveTrackerFrame:AddModule()
    module.flushJob = { Request = function() error("boom") end }
    UIWidgetObjectiveTracker:MarkDirty()
    Check(#reported == 2, "a raising hook handler reached Blizzard's code, or went unreported")
end

------------------------------------------------------------------ 14. collected items
do
    for _, client in ipairs({ RETAIL, FOREVER }) do
        local stopped, tracked = {}, true
        local S = { Finite = function(v) return type(v) == "number" end, Public = function() return true end,
            PublicText = function(v) return v end, Text = function(v) return v end }
        local O = { SOURCES = {}, COLLECTORS = {}, NextEntry = function() end, AddLine = function() end,
            Read = function(fn, ...) return fn(...) end }
        Enum = { ContentTrackingType = { Appearance = 0, Decor = 3 }, ContentTrackingStopType = { Collected = 1 } }
        ContentTrackingUtil = { IsContentTrackingEnabled = function() return false end,
            MakeCombinedID = function(kind, id) return id * 1000 + kind end }
        C_ContentTracking = { IsTracking = function() return tracked end,
            StopTracking = function(kind, id, how) stopped[#stopped + 1] = { kind, id, how } end }
        assert(loadfile(root .. "/MSUF_Suite_Modules/ObjectivesContent.lua"))("MSUF_Suite_Modules",
            { NS = { Client = client }, Suite = S, Objectives = O })
        Check(O.COLLECTED_EVENTS.TRANSMOG_COLLECTION_SOURCE_ADDED, "collected appearances are not heard")
        Check((O.COLLECTED_EVENTS.HOUSE_DECOR_ADDED_TO_CHEST ~= nil) == not client.isForever,
            "collected decor is heard on the wrong client")
        O.NoteCollected("TRANSMOG_COLLECTION_SOURCE_ADDED", 321)
        Check(#stopped == 0, "tracking stopped before the next pass over the collectibles")
        O.COLLECTORS.collectibles({ count = 0 }, { showCollectibles = true })
        Check(#stopped == 1 and stopped[1][1] == 0 and stopped[1][2] == 321 and stopped[1][3] == 1,
            "a collected appearance was not stopped as collected")
        O.COLLECTORS.collectibles({ count = 0 }, { showCollectibles = true })
        Check(#stopped == 1, "a collected item was stopped twice")
        tracked = false
        O.NoteCollected("TRANSMOG_COLLECTION_SOURCE_ADDED", 322)
        O.COLLECTORS.collectibles({ count = 0 }, { showCollectibles = true })
        Check(#stopped == 1, "an item that was not tracked was stopped")
    end
    -- The events are heard only while collectibles are shown and the tracker works.
    local S = { Finite = function(v) return type(v) == "number" end, Public = function() return true end,
        Text = function(v) return v end, GamepadUI = function() return false end, Dispatch = function() end,
        Install = function(_, module) Installed = module end }
    local O = { M = { dirty = {} }, SOURCES = {}, CONTENT_EVENTS = {},
        COLLECTED_EVENTS = { TRANSMOG_COLLECTION_SOURCE_ADDED = function() end }, NoteCollected = function() end }
    assert(loadfile(root .. "/MSUF_Suite_Modules/Objectives.lua"))("MSUF_Suite_Modules",
        { NS = { Client = RETAIL }, Suite = S, Objectives = O })
    local sync = Upvalue(Installed.Refresh, "SyncCollectedEvents")
    local events = {}
    local context = { Event = function(_, event) events[event] = true end, RemoveEvent = function(_, event) events[event] = nil end }
    local owner = { context = context, config = { showCollectibles = true } }
    sync(owner, true)
    Check(events.TRANSMOG_COLLECTION_SOURCE_ADDED, "collected items are not heard while shown")
    owner.config.showCollectibles = false
    sync(owner, true)
    Check(not events.TRANSMOG_COLLECTION_SOURCE_ADDED, "collected items are heard while collectibles are hidden")
    owner.config.showCollectibles = true
    sync(owner, false)
    Check(not events.TRANSMOG_COLLECTION_SOURCE_ADDED, "collected items are heard while the tracker is paused")
end

------------------------------------------------------------------ 15. saved Mythic+ splits
do
    local S = { Finite = function(v) return type(v) == "number" and v == v end, Public = function() return true end,
        PublicText = function(v) return v end, Text = function(v) return v end, ClockText = tostring,
        PublicField = function() end, RaidRecords = {}, CharacterData = function() return nil end,
        Install = function(_, module) Installed = module end }
    local private = { NS = { Client = RETAIL, HUDTextArgs = function() end }, Suite = S, RunSummaryParty = {} }
    assert(loadfile(root .. "/MSUF_Suite_Modules/RunSummary.lua"))("MSUF_Suite_Modules", private)
    -- SaveRunSplits sits under the run events; find it by walking the closures.
    local function Find(fn, wanted, seen)
        seen = seen or {}
        if seen[fn] then return nil end
        seen[fn] = true
        for i = 1, 200 do
            local name, value = debug.getupvalue(fn, i)
            if not name then break end
            if name == wanted then return value end
            if type(value) == "function" then
                local found = Find(value, wanted, seen)
                if found then return found end
            end
        end
    end
    local save = Find(Installed.Enable, "SaveRunSplits")
    Check(save, "the run split writer was not found")
    -- MythicPlus.lua keys a split by the criterion ID as text, or by the name without an ID.
    S.instances = { objectives = { active = true, mplusActive = true,
        mplus = { mapID = 42, level = 10, splits = { ["101"] = 300, ["102"] = 612.5, ["Boss without ID"] = 90 } } } }
    local result = { mapID = 42, level = 10 }
    save(result)
    Check(result.splits and result.splits[101] == 300 and result.splits[102] == 612.5,
        "the run kept none of the boss splits, or kept them under a text key")
    Check(result.splits["101"] == nil and result.splits["Boss without ID"] == nil,
        "a split was kept under a key the planner cannot compare")
end

------------------------------------------------------------------ 16. tracker help text
do
    local help = Read("MSUF_Suite_Options/Pages/HUD.lua")
    for _, group in ipairs({ "zone event progress", "collectibles", "Traveler's Log", "Housing endeavors", "tracked recipes" }) do
        Check(help:find(group, 1, true), "the tracker help does not name " .. group)
    end
end

print("MSUF Suite modules audit contract passed")
