local root, before, onlyBefore = assert(arg[1], "repository root required"), arg[2], arg[3]
local checks = 0
local function Check(ok, label) checks = checks + 1 assert(ok, label) end
local function World(test, file, id)
    local env, captured = {}, { materialCalls = 0, iconCalls = 0, barCalls = 0, frames = 0, textures = {}, events = {} }
    env._G = env
    setmetatable(env, { __index = _G })
    local function Chunk(path)
        local chunk, reason = loadfile(path)
        assert(chunk, reason)
        return setfenv(chunk, env)
    end
    local function Enhance(widget, suite)
        if widget.glossFixture then return widget end
        widget.glossFixture = true
        local originalAlpha = widget.SetAlpha
        function widget:SetAlpha(value)
            if originalAlpha then originalAlpha(self, value) end
            self.alpha = value
            if self.vertexColor then self.vertexColor[4] = value end
        end
        function widget:GetAlpha() return self.alpha or 1 end
        function widget:SetParent(parent) self.parent = parent end
        function widget:GetWidth() return self.width or 1 end
        function widget:GetFrameStrata() return "MEDIUM" end
        function widget:SetVertexColor(r, g, b, alpha)
            self.vertexColor, self.alpha = { r, g, b, alpha }, alpha
        end
        function widget:SetBlendMode(value) self.blendMode = value end
        function widget:SetTexCoord(...) self.texCoord = { ... } end
        function widget:SetAllPoints(target) self.allPoints = target end
        function widget:SetShown(value) self.shown = value end
        function widget:CreateTexture()
            return suite.CreateTexture(self)
        end
        function widget:GetStatusBarTexture()
            if not self.glossFill then self.glossFill = suite.CreateTexture(self) end
            return self.glossFill
        end
        return widget
    end
    local function LoadRuntime(path)
        return function(addon, part)
            local suite, ns = part.Suite, part.NS
            captured.suite, captured.ns = suite, ns
            suite.Text = suite.Text or function(value) return value end
            local createFrame, createTexture = suite.CreateFrame, suite.CreateTexture
            suite.CreateFrame = function(...)
                captured.frames = captured.frames + 1
                return Enhance(createFrame(...), suite)
            end
            suite.CreateTexture = function(parent, ...)
                -- Avoid the simple fixture's parent:CreateTexture recursion.
                local widget
                if parent and parent.glossFixture then
                    local fixtureParent = setmetatable({}, { __index = parent })
                    fixtureParent.CreateTexture = parent.originalCreateTexture
                    widget = createTexture(fixtureParent, ...)
                else widget = createTexture(parent, ...) end
                captured.textures[#captured.textures + 1] = widget
                widget.glossOwner = parent
                return Enhance(widget, suite)
            end
            -- Preserve the fixture constructor used by its Suite helper.
            suite.CreateFrame = function(...)
                local widget = createFrame(...)
                widget.originalCreateTexture = widget.CreateTexture
                captured.frames = captured.frames + 1
                return Enhance(widget, suite)
            end
            local looks = {}
            ns.HostBridge = {
                GlossTexture = function() return "existing-gloss-art.tga" end,
                IconSkinLook = function(choice, shape, strength)
                    Check(choice == "FRAME_BEVEL" and shape == "RECTANGLE", "QoL uses another icon look")
                    if not looks[strength] then looks[strength] = { strength = strength } end
                    return looks[strength]
                end,
                PaintIconSkin = function(owner, look, width, height, anchor)
                    owner.glossLook, owner.glossAnchor = look, anchor
                    if look then owner.glossWidth, owner.glossHeight = width, height end
                    return look ~= nil
                end,
                WatchIconSkins = function(module, on) captured.watched = on and module or nil end,
            }
            Chunk(root .. "/MSUF_Suite/Core/GlossMaterial.lua")("MSUF_Suite", ns)
            local icon, bar = ns.GlossMaterial.Icon, ns.GlossMaterial.Bar
            ns.GlossMaterial.Icon = function(...)
                captured.materialCalls, captured.iconCalls = captured.materialCalls + 1, captured.iconCalls + 1
                return icon(...)
            end
            ns.GlossMaterial.Bar = function(...)
                captured.materialCalls, captured.barCalls = captured.materialCalls + 1, captured.barCalls + 1
                return bar(...)
            end
            local install = suite.Install
            suite.Install = function(module, value)
                if module == id then captured.module = value end
                return install(module, value)
            end
            if before and (not onlyBefore or onlyBefore == file) then
                path = before .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"
            end
            return Chunk(path)(addon, part)
        end
    end
    env.loadfile = function(path)
        if path:match("/MSUF_Suite_QualityOfLife/" .. file .. "%.lua$") then return LoadRuntime(path) end
        return Chunk(path)
    end
    env.dofile = function(path) return env.loadfile(path)() end
    Chunk(root .. "/tools/tests/" .. test)()
    Check(captured.materialCalls == 0, id .. " default-off entered material painter")
    local context = captured.module.context
    local event = context.Event
    context.Event = function(self, name, callback, ...)
        captured.events[name] = callback
        return event(self, name, callback, ...)
    end
    return captured, env
end

local function Configure(world)
    local module = world.module
    world.suite.editMode, module.active = false, true
    module.config.glossEnabled, module.config.glossStrength = true, 60
    return module
end

local action, actionEnv = World("suite_action_tracker_contract.lua", "ActionTracker", "actionTracker")
local tracker = Configure(action)
tracker:Enable()
Check(action.iconCalls == 8 and action.watched == "actionTracker", "Action Tracker cold style did not skin every row")
Check(tracker.rows[1].frame.glossLook.strength == .6, "Action Tracker lost its configured strength")
local actionCalls = action.materialCalls
for index = 1, 20 do action.events.UNIT_SPELLCAST_SUCCEEDED(tracker, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", index) end
Check(action.materialCalls == actionCalls, "Action Tracker spell events repainted material")
tracker.config.glossStrength = 20
tracker:Refresh()
Check(tracker.rows[1].frame.glossLook.strength == .2, "Action Tracker warm strength remained stale")
tracker.config.glossEnabled = false
tracker:Refresh()
Check(tracker.rows[1].frame.glossLook == nil and action.watched == nil, "Action Tracker disable retained icon skin")
actionCalls = action.materialCalls
tracker:Refresh()
Check(action.materialCalls == actionCalls, "Action Tracker warm-off entered material painter")

local battle = World("suite_battle_res_contract.lua", "BattleRes", "battleRes")
local resurrection = Configure(battle)
resurrection:Enable()
Check(battle.iconCalls == 1 and resurrection.host.glossLook.strength == .6, "Battle Rez cold style did not draw its icon")
local battleCalls = battle.materialCalls
local update = battle.events.PLAYER_ENTERING_WORLD
for index = 1, 20 do update(resurrection, "PLAYER_ENTERING_WORLD") end
Check(battle.materialCalls == battleCalls, "Battle Rez charge/context events repainted material")
resurrection.config.glossStrength = 0
resurrection:Refresh()
Check(resurrection.host.glossLook == nil, "Battle Rez zero strength stayed visible")
resurrection.config.glossEnabled = false
resurrection:Refresh()
battleCalls = battle.materialCalls
resurrection:Refresh()
Check(battle.materialCalls == battleCalls, "Battle Rez warm-off entered material painter")

local cast, castEnv = World("suite_enemy_cast_stack_contract.lua", "EnemyCastStack", "enemyCastStack")
local stack = Configure(cast)
castEnv.IsInInstance = function() return true, "party" end
castEnv.UnitExists = function() return false end
stack.config.fadeMinor, stack.config.onlyImportant, stack.config.dimOutOfRange = false, false, false
stack.config.readyStripe, stack.config.showMarkers = false, false
stack:Enable()
Check(cast.iconCalls > 0 and cast.barCalls > 0, "Cast Stack cold style omitted bar or icon gloss")
local duration = {}
castEnv.UnitCastingInfo = function() return "Cast", nil, 134400, nil, nil, false, nil, false, 116 end
castEnv.UnitCastingDuration = function() return duration end
castEnv.UnitSpellTargetName = function() return "Target" end
cast.events.UNIT_SPELLCAST_START(stack, "UNIT_SPELLCAST_START", "nameplate1")
local castCalls = cast.materialCalls
for index = 1, 20 do cast.events.UNIT_SPELLCAST_DELAYED(stack, "UNIT_SPELLCAST_DELAYED", "nameplate1") end
Check(cast.materialCalls == castCalls, "Cast Stack duration events repainted material")
Check(stack.entries.nameplate1.row.glossLook.strength == .6, "Cast Stack icon strength differs")
local reflections = {}
for _, texture in ipairs(cast.textures) do
    if texture.glossOwner == stack.entries.nameplate1.row and texture.texture == "existing-gloss-art.tga" then
        reflections[#reflections + 1] = texture
    end
end
Check(#reflections == 2, "Cast Stack did not reuse the two real reflection regions")
Check(reflections[1].vertexColor[1] == .6 * .65 and reflections[2].vertexColor[1] == .6 * .08,
    "Cast Stack bar gloss lost its strength")
Check(reflections[1].alpha == 1 and reflections[1].allPoints == stack.entries.nameplate1.row.glossFill,
    "Cast Stack gloss bypassed the native fill or row alpha")
stack.config.glossEnabled = false
stack:Refresh()
Check(stack.rows[1].glossLook == nil and cast.watched == nil, "Cast Stack disable retained look or subscription")
castCalls = cast.materialCalls
stack:Refresh()
Check(cast.materialCalls == castCalls, "Cast Stack warm-off entered material painter")

local function Preview(world, name, field)
    local suite, module = world.suite, world.module
    local draw = assert(suite[name], name .. " export missing")
    module.config.glossEnabled, module.config.glossStrength = true, 70
    local parent = suite.CreateFrame("Frame", nil, UIParent)
    local viewport = { width = 700, height = 260, scale = 1 }
    local host = draw(parent, module.config, {}, viewport)
    Check(host ~= module.host and parent[field].host == host, name .. " borrowed the live instance")
    local frames, textures = world.frames, #world.textures
    for index = 1, 20 do Check(draw(parent, module.config, {}, viewport) == host, name .. " replaced its host") end
    Check(world.frames == frames and #world.textures == textures, name .. " leaked pooled preview regions")
    return parent[field]
end
local actionView = Preview(action, "DrawActionTrackerPreview", "suiteActionTrackerPreview")
Check(actionView.rows[1].frame.glossLook.strength == .7, "Action Tracker preview bypassed real style")
local battleView = Preview(battle, "DrawBattleResPreview", "suiteBattleResPreview")
Check(battleView.host.glossLook.strength == .7 and battleView.count.text == "2", "Battle Rez preview bypassed real style/sample")
local castView = Preview(cast, "DrawEnemyCastStackPreview", "suiteCastStackPreview")
Check(castView.previews[1].glossLook.strength == .7, "Cast Stack preview bypassed real style")
Check(castView.previews ~= stack.previews, "Cast Stack menu samples alias live Edit Mode rows")
print("QoL gloss contract: " .. checks .. " checks; real material, three runtime styles and isolated cached previews")
