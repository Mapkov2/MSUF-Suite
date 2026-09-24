local _, NS = ...
-- Every Core/Catalog file has loaded before this one (see the TOC order).
NS.FinalizeCatalog()
local S = { states={}, instances={}, catalog=NS.SuiteCatalog, order=NS.SuiteOrder, started=false }
NS.Suite = S
local pending, pendingFrame, pendingListening = {}, nil, false
local runtimeAddon = "MSUF_Suite_Modules"
for i=1,#S.order do S.states[S.order[i]] = { active=false } end

local function ValidText(rule,value)
    return #value<=rule.maxLength and not ((rule.spells or rule.items or rule.ids) and value:find("[^%d%s,]"))
        and not (rule.color and (#value~=6 or value:find("[^%x]")))
end

function S.Normalize(profile)
    local db = profile.suite
    if type(db) ~= "table" then db = {}; profile.suite = db end
    -- Preserve future-version data intact. Apply fails closed on its schema.
    if type(db.schema)=="number" and db.schema>1 then return end
    db.schema=1
    if type(db.modules)~="table" then db.modules={} end
    local oldDataTexts = db.modules.dataTexts
    local dataHadBagChoice = type(oldDataTexts)=="table" and oldDataTexts.hideBlizzardBagBar ~= nil
    local dataHadAnySlot, dataHadBagSlot = false, false
    if type(oldDataTexts)=="table" then
        for bar=1,3 do
            for slot=1,6 do
                local source=oldDataTexts["bar"..bar.."Slot"..slot]
                if source ~= nil then dataHadAnySlot=true end
                if source == 3 then dataHadBagSlot=true end
            end
        end
    end
    -- Action-bar looks are new. Existing profiles keep their exact button
    -- colors and spacing, so show them as Custom instead of repainting them.
    if (tonumber(db.actionBarLookRevision) or 0) < 1 then
        local bars = db.modules.actionbars
        if type(bars)=="table" and next(bars) and bars.look == nil then bars.look = 4 end
        db.actionBarLookRevision = 1
    end
    if (tonumber(db.bagsLookRevision) or 0) < 1 then
        local bags = db.modules.bags
        if type(bags)=="table" and next(bags) and bags.look == nil then
            -- The previous bag appearance was the Forever palette on every
            -- client. Preserve missing visual fields in partial saved profiles.
            local previous = NS.BagsLookPresets[3]
            for key, value in pairs(previous) do
                if bags[key] == nil then bags[key] = value end
            end
            bags.look = 4
        end
        db.bagsLookRevision = 1
    end
    -- Preset 2 used to mean Forever and preset 3 meant Custom. Translate
    -- stored choices once, before catalog normalization can fill new defaults.
    if (tonumber(db.lookPresetRevision) or 0) < 1 then
        local legacyDefault = NS.Client.isForever and 3 or 1
        for _, id in ipairs({ "chat", "damageMeter" }) do
            local config = db.modules[id]
            if type(config)=="table" and next(config) then
                if config.look == nil then
                    local preset = id == "chat" and NS.ChatLookPresets[legacyDefault]
                        or NS.DamageMeterLookPresets[legacyDefault]
                    local custom = false
                    for key, value in pairs(preset) do
                        if config[key] == nil then config[key] = value
                        elseif config[key] ~= value then custom = true end
                    end
                    config.look = custom and 4 or legacyDefault
                elseif config.look == 2 then config.look = 3
                elseif config.look == 3 then config.look = 4 end
            end
        end
        local data = db.modules.dataTexts
        if type(data)=="table" and next(data) then
            if data.look == nil then data.look = legacyDefault
            elseif data.look == 2 then data.look = 3 end
            for bar=1,3 do
                local key = "bar" .. bar .. "Look"
                if data[key] == 2 then data[key] = 3
                elseif data[key] == nil and data["bar" .. bar .. "StyleOverride"] then
                    data[key] = legacyDefault
                end
            end
        end
        local xp = db.modules.xpBar
        if type(xp)=="table" and next(xp) then
            if xp.look == nil then xp.look = legacyDefault
            elseif xp.look == 2 then xp.look = 3 end
        end
        db.lookPresetRevision = 1
    end
    for i=1,#S.order do
        local id = S.order[i]
        local config = db.modules[id]
        if type(config)~="table" then config={}; db.modules[id]=config end
        for key,rule in pairs(S.catalog[id].rules) do
            local value=config[key]
            if type(value)~=type(rule.default) then value=rule.default end
            if type(value)=="number" then
                if value~=value or value==math.huge or value==-math.huge then value=rule.default end
                value=math.max(rule.min,math.min(rule.max,value))
                if rule.choices or rule.step==1 then value=math.floor(value) end
            end
            if type(value)=="string" then
                value=value:sub(1,rule.maxLength)
                if not ValidText(rule,value) then value=rule.default end
            end
            config[key]=value
        end
    end
    -- An older Retail profile may have DataTexts without a Bag space slot.
    -- Keep Blizzard's bag buttons until that player explicitly chooses this.
    if NS.Client.isMainline and dataHadAnySlot and not dataHadBagChoice and not dataHadBagSlot then
        db.modules.dataTexts.hideBlizzardBagBar=false
    end
    -- Existing Forever profiles predate the safer default. Disable ActionBars
    -- once; a deliberate re-enable afterward remains the player's choice.
    if NS.Client.isForever and (tonumber(db.actionBarsDefaultRevision) or 0) < 1 then
        db.modules.actionbars.enabled = false
        db.actionBarsDefaultRevision = 1
    end
    -- Repair the original Forever factory stack once, without moving bars
    -- whose position or size was customized in an existing profile.
    if NS.Client.isForever and (tonumber(db.layoutRevision) or 0) < 2 then
        local data = db.modules.dataTexts
        if data and data.bar1Width == 270 and data.bar1Layout == 1
            and data.bar1Point == 9 and data.bar1X == -20 and data.bar1Y == 20
            and data.bar1Slot1 == 3 and data.bar1Slot2 == 4 and data.bar1Slot3 == 5 then
            data.bar1Width, data.bar1Layout = 340, 2
        end
        local meter = db.modules.damageMeter
        if meter and meter.windowCount == 2
            and meter.w1Width == 260 and meter.w1Height == 170 and meter.w1X == -20 and meter.w1Y == 20
            and meter.w2Width == 260 and meter.w2Height == 170 and meter.w2X == -20 and meter.w2Y == 210 then
            meter.w1Width, meter.w1Y = 340, 60
            meter.w2Width, meter.w2Y = 340, 250
        end
        local bars = db.modules.actionbars
        local previous = { 1, 1, 4, 1, 4, 6, 6, 6, 6, 6, 1, 1 }
        local factory = bars and bars.imported == false
        if factory then
            for i = 1, #previous do
                if bars["bar" .. i .. "Visibility"] ~= previous[i]
                    or bars["bar" .. i .. "ResumeVisibility"] ~= (previous[i] == 6 and 1 or previous[i]) then
                    factory = false
                    break
                end
            end
        end
        if factory then
            for i = 1, #previous do
                bars["bar" .. i .. "Visibility"] = 4
                bars["bar" .. i .. "ResumeVisibility"] = 4
            end
        end
        db.layoutRevision = 2
    end
    if NS.Client.isForever and (tonumber(db.paletteRevision) or 0) < 1 then
        local chat = db.modules.chat
        if chat and chat.look == 3 and chat.inputColor == "1a1a1b" then
            chat.inputColor = "111517"
        end
        local reminders = db.modules.buffReminders
        if reminders and reminders.borderColor == "e8b855" then
            reminders.borderColor = "d8b66a"
        end
        local cooldowns = db.modules.cooldownManager
        if cooldowns then
            for key, color in pairs(cooldowns) do
                if type(key) == "string" and key:sub(-8) == "barColor"
                    and color == "e8b855" then
                    cooldowns[key] = "d8b66a"
                end
            end
        end
        db.paletteRevision = 1
    end
end

-- The Skinning look is a deliberate suite-wide gesture. Keep the choice in
-- this profile so an optional module adopts it when it is enabled later.
local globalLookIndices = { midnight = 1, midnightDark = 2, foreverGlass = 3 }
local minimapLookIndices = { [1] = 8, [2] = 9, [3] = 7 }
local function LookValues(id, index, config)
    local preset
    if id == "actionbars" then preset = NS.ActionBarLookPresets[index]
    elseif id == "bags" then preset = NS.BagsLookPresets[index]
    elseif id == "chat" then preset = NS.ChatLookPresets[index]
    elseif id == "damageMeter" then preset = NS.DamageMeterLookPresets[index]
    elseif id == "minimap" then return NS.MinimapStylePresets[minimapLookIndices[index]]
    elseif id == "xpBar" then return { look = index }
    elseif id == "buffReminders" then
        return { borderColor = NS.DataTextLooks[index].border }
    elseif id == "cooldownManager" then
        local palette = NS.DataTextLooks[index]
        local values = {
            cdColor = palette.value,
            stackColor = palette.value,
            keybindColor = palette.value,
        }
        for _, slot in ipairs(NS.CDM.SLOTS) do
            local keys = NS.CDM.KEYS[slot.key]
            if keys.borderColor then values[keys.borderColor] = palette.border end
            if keys.glowColor then values[keys.glowColor] = palette.accent end
            if keys.barColor then values[keys.barColor] = palette.accent end
        end
        return values
    elseif id == "dataTexts" then
        local values = { look = index, customColors = false }
        for bar = 1, 3 do
            if config["bar" .. bar .. "StyleOverride"] then
                values["bar" .. bar .. "Look"] = index
                values["bar" .. bar .. "CustomColors"] = false
            end
        end
        return values
    end
    if not preset then return nil end
    local values = { look = index }
    for key, value in pairs(preset) do values[key] = value end
    if id == "actionbars" then
        local background = NS.DataTextLooks[index].background
        for bar = 1, NS.ActionBarCount do
            values["bar" .. bar .. "BackgroundColor"] = background
        end
    end
    return values
end

local function ApplyLookToConfig(id, config, lookName)
    local index = globalLookIndices[lookName]
    local values = index and LookValues(id, index, config)
    if not values then return false end
    local rules = S.catalog[id].rules
    local changed = false
    for key, value in pairs(values) do
        if rules[key] and type(value) == type(rules[key].default)
            and config[key] ~= value then
            config[key] = value
            changed = true
        end
    end
    return changed
end
function S.SanitizeImport(profile)
    -- Sharing a visual setup never authorizes merchant spending.
    local modules=type(profile)=="table" and type(profile.suite)=="table" and profile.suite.modules
    if type(modules)=="table" and type(modules.qol)=="table" then
        modules.qol.enabled=false; modules.qol.repair=false; modules.qol.autoJunk=false
    end
    if type(modules)=="table" and type(modules.quests)=="table" then modules.quests.enabled=false end
    if type(modules)=="table" and type(modules.loot)=="table" then modules.loot.quickLoot=false end
    if type(modules)=="table" and type(modules.combatLog)=="table" then modules.combatLog.enabled=false end
end
function S.Config(id)
    local db=NS.DB and NS.DB.suite
    return db and db.schema==1 and db.modules and db.modules[id] or NS.Defaults.suite.modules[id]
end
function S.Availability(id)
    local spec=S.catalog[id]
    if not spec then return false,"Unknown module" end
    if NS.Client.flavor=="Unknown" then return false,"This client has not been identified" end
    local enabled, addonReason=NS.Client.AddOnEnabled(spec.addon)
    if not enabled then return false,addonReason end
    -- Each catalog entry may declare its own client requirement.
    if spec.available then
        local ok,why=spec.available()
        if not ok then return false,why or "Unavailable on this client" end
    end
    for i=1,#spec.conflicts do
        if NS.Client.IsAddOnLoaded(spec.conflicts[i]) then return false,"Managed by "..spec.conflicts[i] end
    end
    return true
end
local function Changed()
    if NS.Options and NS.Options.RefreshAll then NS.Options.RefreshAll() end
end
local function Stop(id)
    local state,instance=S.states[id],S.instances[id]
    if S.CloseMovers then S.CloseMovers(id) end
    if S.UnregisterEditElements then S.UnregisterEditElements(id) end
    state.active=false
    if instance then
        instance.active=false
        instance:Disable()
        if instance.context then instance.context:Release() end
    end
end
local function Flush(self)
    if NS.IsCombatLocked() then return end
    self:UnregisterAllEvents()
    pendingListening=false
    for id in pairs(pending) do pending[id]=nil; S.Apply(id) end
    Changed()
end
function S.Queue(id)
    pending[id]=true
    if not pendingFrame then pendingFrame=CreateFrame("Frame"); pendingFrame:SetScript("OnEvent",Flush) end
    if not pendingListening then
        pendingFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        pendingListening=true
    end
end
function S.Apply(id)
    if not S.started or not S.catalog[id] then return end
    if NS.IsCombatLocked() then S.Queue(id); return end
    pending[id]=nil
    if pendingListening and not next(pending) then
        pendingFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        pendingListening=false
    end
    local state,config=S.states[id],S.Config(id)
    local supported,reason=S.Availability(id)
    state.unavailable=not supported and reason or nil
    local db=NS.DB and NS.DB.suite
    if not db or db.schema~=1 or not config.enabled or not supported or state.error then
        if state.active or (S.instances[id] and S.instances[id].active) then Stop(id) end
        if S.RestoreSaved then S.RestoreSaved(id) end
        return
    end
    if state.error then return end
    if not S.instances[id] then
        local loader=C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
        local loaded, why
        if type(loader)=="function" then
            if not NS.Client.IsAddOnLoaded(runtimeAddon) then loaded,why=loader(runtimeAddon) end
            if type(S.NewContext)=="function" then loaded,why=loader(S.catalog[id].addon) end
        end
        -- Some Forever builds return an empty/diagnostic result even after the
        -- addon ran. Successful registration is the authoritative outcome.
        if not S.instances[id] then
            if NS.Client.IsAddOnLoaded(S.catalog[id].addon) then
                state.error=S.catalog[id].title.." is missing from "..S.catalog[id].addon
            else
                state.error="Cannot load "..S.catalog[id].addon..": "..tostring(why or loaded or "not installed")
            end
            return
        end
    end
    local instance=S.instances[id]
    -- A previous callback may have raised a client-visible error after taking
    -- ownership. Release that partial activation before a deliberate retry.
    if instance.active and not state.active then Stop(id) end
    instance.config=config
    instance.active=true
    instance.context=instance.context or S.NewContext(id)
    local fn=state.active and instance.Refresh or instance.Enable
    -- Follow MSUF error reporting: Lua errors reach the client error handler.
    -- A successful callback is required before publishing an active state.
    fn(instance)
    if instance.context.RefreshOwnedSkins then instance.context:RefreshOwnedSkins() end
    state.active=true
    if S.RefreshEditMover then S.RefreshEditMover(id) end
end
function S.ApplyAll()
    for i=1,#S.order do S.Apply(S.order[i]) end
end
function S.ApplyGlobalLook(lookName)
    if NS.IsCombatLocked() or not globalLookIndices[lookName] or not NS.DB
        or not NS.DB.suite or NS.DB.suite.schema ~= 1 then return false end
    local db = NS.DB.suite
    db.globalLook = lookName
    for i = 1, #S.order do
        local id = S.order[i]
        local config = S.Config(id)
        if config.enabled and ApplyLookToConfig(id, config, lookName) then
            S.states[id].error = nil
            S.Apply(id)
        end
    end
    Changed()
    return true
end
function S.Set(id,key,value)
    if NS.IsCombatLocked() then return false,"Finish combat before editing the suite" end
    if not NS.DB or not NS.DB.suite or NS.DB.suite.schema~=1 then return false,"Unsupported suite profile" end
    local rule=S.catalog[id] and S.catalog[id].rules[key]
    if not rule or type(value)~=type(rule.default) then return false,"Invalid setting" end
    if type(value)=="number" then
        if value~=value or value==math.huge or value==-math.huge then return false,"Invalid number" end
        value=math.max(rule.min,math.min(rule.max,value))
        if rule.choices or rule.step==1 then value=math.floor(value) end
    end
    if type(value)=="string" and not ValidText(rule,value) then return false,"Invalid setting text" end
    if S.Config(id)[key]==value and not S.states[id].error and not S.states[id].unavailable then return true end
    S.Config(id)[key]=value
    if key == "enabled" and value == true then
        ApplyLookToConfig(id, S.Config(id), NS.DB.suite.globalLook)
    end
    S.states[id].error=nil
    S.Apply(id)
    Changed()
    return true
end
function S.SetMany(id,values)
    if NS.IsCombatLocked() then return false,"Finish combat before editing the suite" end
    if not NS.DB or not NS.DB.suite or NS.DB.suite.schema~=1 or type(values)~="table" then return false,"Invalid settings" end
    local spec=S.catalog[id]
    if not spec then return false,"Unknown module" end
    local clean={}
    for key,value in pairs(values) do
        local rule=spec.rules[key]
        if not rule or type(value)~=type(rule.default) then return false,"Invalid setting" end
        if type(value)=="number" then
            if value~=value or value==math.huge or value==-math.huge then return false,"Invalid number" end
            value=math.max(rule.min,math.min(rule.max,value))
            if rule.choices or rule.step==1 then value=math.floor(value) end
        end
        if type(value)=="string" and not ValidText(rule,value) then return false,"Invalid setting text" end
        clean[key]=value
    end
    for key,value in pairs(clean) do S.Config(id)[key]=value end
    if clean.enabled == true then
        ApplyLookToConfig(id, S.Config(id), NS.DB.suite.globalLook)
    end
    S.states[id].error=nil
    S.Apply(id); Changed()
    return true
end
function S.AddSpellFromCursor(id,key)
    local rule=S.catalog[id] and S.catalog[id].rules[key]
    if not rule or not (rule.spells or rule.items) or NS.IsCombatLocked() or type(GetCursorInfo)~="function" then return false end
    local kind,cursorID,_,spellID=GetCursorInfo()
    if type(issecretvalue)=="function" and (issecretvalue(kind) or issecretvalue(cursorID) or issecretvalue(spellID)) then return false end
    if rule.items then
        if kind~="item" then return false end
        spellID=cursorID
    elseif kind~="spell" then return false end
    if type(spellID)~="number" then return false end
    local text=S.Config(id)[key]
    for token in text:gmatch("%d+") do if tonumber(token)==spellID then return false end end
    local ok=S.Set(id,key,text=="" and tostring(spellID) or text.." "..tostring(spellID))
    if ok and type(ClearCursor)=="function" then ClearCursor() end
    return ok
end
function S.Reset(id)
    if NS.IsCombatLocked() or not S.catalog[id] or NS.DB.suite.schema~=1 then return false end
    NS.DB.suite.modules[id]=NS.CopyValue(NS.Defaults.suite.modules[id])
    if S.Config(id).enabled then
        ApplyLookToConfig(id, S.Config(id), NS.DB.suite.globalLook)
    end
    S.states[id].error=nil
    S.Apply(id); Changed()
    return true
end
-- "core" enables available core modules; "off" disables every module. Setup
-- never enables spending or automation: opt-in modules keep their own choice.
function S.Preset(kind)
    if NS.IsCombatLocked() or not NS.DB or NS.DB.suite.schema~=1 then return false end
    if kind~="core" and kind~="off" then return false end
    for i=1,#S.order do
        local id=S.order[i]
        if S.catalog[id].core or kind=="off" then
            S.Config(id).enabled=kind=="core" and S.Availability(id)==true
            if S.Config(id).enabled then
                ApplyLookToConfig(id, S.Config(id), NS.DB.suite.globalLook)
            end
            S.states[id].error=nil
        end
    end
    S.ApplyAll(); Changed()
    return true
end
function S.Start()
    if S.started then return end
    S.started=true
    if NS.DB then S.Normalize(NS.DB) end
    if NS.RootDB and NS.RootDB.suiteRecovery and next(NS.RootDB.suiteRecovery) then
        local loader=C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
        if type(loader)=="function" then loader(runtimeAddon) end
    end
    NS.Registry.AddListener(S,function(_,domain)
        if domain=="profile" then
            if S.CloseMovers then S.CloseMovers() end
            if NS.DB then S.Normalize(NS.DB) end
            S.ApplyAll()
        end
    end)
    S.ApplyAll()
end
function S.Status(id)
    local state=S.states[id]
    if state.error then return state.error end
    if pending[id] then return "Waiting for combat to end" end
    -- Modules set a specific message when Blizzard frames return only on reload.
    if state.reloadRequired then
        return type(state.reloadRequired)=="string" and state.reloadRequired or "Reload the UI to finish this change"
    end
    if state.unavailable then return state.unavailable end
    return state.active and "Active" or "Off"
end
function S.Open(id)
    local page=type(id)=="string" and S.catalog[id] and (S.catalog[id].page or ("suite_"..id)) or "suite_actionbars"
    if NS.Menu and NS.Menu.Open and NS.Menu.Open(page) then return end
    NS.Print("Open MSUF > UI Suite. MSUF must be installed and enabled.")
end
SLASH_MSUFSUITE1="/msuite"
SlashCmdList.MSUFSUITE=function() S.Open() end
