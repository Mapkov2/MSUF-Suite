local root = assert(arg[1]):gsub("\\", "/")
local checks, combat, writes = 0, false, 0
local function Check(ok, message) checks = checks + 1 assert(ok, message) end
local frames, elements, listeners = {}, {}, {}
local function Frame()
    local f = { scale = 1, events = {}, points = {}, left = 0, bottom = 0, width = 100, height = 40 }
    function f:GetScale() return self.scale end
    function f:GetEffectiveScale() return self.scale end
    function f:GetRect() return self.left, self.bottom, self.width, self.height end
    function f:GetParent() return self.parent end
    function f:GetNumPoints() return #self.points end
    function f:GetPoint(i) return unpack(self.points[i]) end
    function f:ClearAllPoints() Check(not combat, "anchor write in combat") self.points = {} writes = writes + 1 end
    function f:SetPoint(...) Check(not combat, "anchor write in combat") self.points[#self.points+1] = {...} writes = writes + 1 end
    function f:SetScript(event, fn) self[event] = fn end
    function f:RegisterEvent(event) self.events[event] = true end
    function f:UnregisterAllEvents() self.events = {} end
    frames[#frames+1] = f
    return f
end
UIParent = Frame()
local host, player, cdm = Frame(), Frame(), Frame()
player.left, player.bottom, player.width, player.height, player.scale = 200, 300, 180, 40, .8
cdm.left, cdm.bottom, cdm.width, cdm.height = 500, 700, 300, 50
elements.player = { label = "Player", getFrame = function() return player end }
elements["external:msufsuite.cooldownmanager:custom1"] = { label = "My cooldowns", group = "MSUF Suite",
    externalPublicElement = true, getFrame = function() return cdm end }
elements["external:msufsuite.buffreminders:buffs"] = { label = "Buff reminders", getFrame = function() return host end }
MSUF_EM2 = { Registry = { All = function() return elements end,
    RegisterChangeListener = function(owner, fn) listeners[owner] = fn end,
    UnregisterChangeListener = function(owner) listeners[owner] = nil end } }
MSUF_NS = { PublicGlobals = { MSUF_EM2 = MSUF_EM2 } }
local NS = { DB = {}, IsCombatLocked = function() return combat end,
    Safety = { IsForbidden = function(f) return f.forbidden == true end },
    AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" } }
local config = { anchorTarget = "", relativePoint = 8, point = 2, x = 10, y = -12, size = 38, spacing = 6, columns = 6 }
local S = { Public = function(v) return not (type(v)=="table" and v.secret) end,
    Text = function(v) return v end, CreateFrame = Frame,
    Finite = function(v) return type(v)=="number" and v==v and v > -math.huge and v < math.huge end,
    Config = function() return config end }
NS.Text = S.Text
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("test", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeAnchors.lua"))("test", NS)
assert(loadfile(root .. "/MSUF_Suite_Modules/EditMode.lua"))("test", { NS = NS, Suite = S })
local R = { ScreenPoint = function(c) return ({"CENTER", "TOP"})[c.point] end }
assert(loadfile(root .. "/MSUF_Suite_BuffReminders/Anchors.lua"))("test", { NS = NS, Suite = S, BuffReminders = R })
local owner = { active = true, config = config, view = { host = host }, cursor = {} }
R.WatchAnchor(owner, true)
Check(owner.anchor == nil, "screen anchoring created a watcher")
R.PlaceAnchor(owner)
Check(host.points[1][2] == UIParent and host.points[1][3] == "TOP" and host.points[1][4] == 10, "old screen anchor changed")
local choices = NS.HostBridge.EditAnchorChoices("external:msufsuite.buffreminders:buffs")
Check(#choices == 3 and choices[1].value == "", "anchor list omitted MSUF, Suite or screen")
config.anchorTarget = "player"
R.WatchAnchor(owner, true)
R.PlaceAnchor(owner)
local function Position(x, y)
    local p = host.points[1]
    Check(p[2] == UIParent and p[3] == "BOTTOMLEFT", "secure host attached directly to the target")
    Check(math.abs(p[4]-x) < .001 and math.abs(p[5]-y) < .001, "wrong scaled anchor coordinates")
end
Position(242, 228)
Check(#owner.anchor.probes == 2 and owner.anchor.driver.events.PLAYER_REGEN_ENABLED, "event-driven following was not installed")
player.left = 300
owner.anchor.probes[1].OnSizeChanged()
Position(322, 228)
host.scale = .5
R.PlaceAnchor(owner, 25, 30)
Position(649, 510)
host.scale = 1
config.anchorTarget = "external:msufsuite.cooldownmanager:custom1"
listeners["MSUFSuite.BuffAnchor"]()
Position(660, 688)
config.anchorTarget = "later"
R.PlaceAnchor(owner)
Check(host.points[1][3] == "TOP" and config.anchorTarget == "later", "missing anchor destroyed the stored choice")
elements.later = { getFrame = function() return cdm end }
listeners["MSUFSuite.BuffAnchor"]()
Position(660, 688)
combat = true
local before = writes
cdm.left = 600
owner.anchor.probes[2].OnSizeChanged()
owner.anchor.driver.OnEvent(owner.anchor.driver, "ADDON_LOADED")
Check(writes == before, "target change moved secure reminders in combat")
combat = false
owner.anchor.driver.OnEvent(owner.anchor.driver, "PLAYER_REGEN_ENABLED")
Position(760, 688)
owner.cursor.displaced, config.followCursor = true, true
before = writes
owner.anchor.probes[1].OnSizeChanged()
Check(writes == before, "anchor pulled reminders away from the cursor")
S.editMode = true
R.PlaceAnchor(owner)
Position(760, 688)
S.editMode, owner.cursor.displaced, config.followCursor = false, false, false
cdm.parent = host
R.PlaceAnchor(owner)
Check(host.points[1][3] == "TOP", "a descendant anchor created a loop")
cdm.parent = nil
cdm.points = {{ "TOP", host }}
R.PlaceAnchor(owner)
Check(host.points[1][3] == "TOP", "an anchor dependency created a loop")
cdm.points = {}
cdm.left = { secret = true }
R.PlaceAnchor(owner)
Check(host.points[1][3] == "TOP", "unreadable geometry reached arithmetic")
cdm.left = 600
R.PlaceAnchor(owner)
R.WatchAnchor(owner, false)
Check(next(listeners) == nil and next(owner.anchor.driver.events) == nil, "disabled reminders retained listeners")
for _, probe in ipairs(owner.anchor.probes) do Check(#probe.points == 0, "disabled reminders retained target probes") end
Check(config.x == 10 and config.y == -12 and config.anchorTarget == "later", "following rewrote the profile position")
Check(#R.AnchorControls() == 3, "older hosts lost numeric popup controls")
MSUF_NS.PublicGlobals.MSUF_EditModeAPI = { GetCapabilities = function() return { choiceControls = true } end }
S.catalog = { buffReminders = { rules = { point = { choices = {"Center", "Top"} },
    relativePoint = { choices = {"Top left", "Top", "Top right", "Left", "Center", "Right", "Bottom left", "Bottom", "Bottom right"} } } } }
S.Set = function(_, key, value) config[key] = value return true end
local controls = R.AnchorControls()
Check(#controls == 6 and controls[1].kind == "choice" and #controls[1].values() == 4, "modern hosts omitted anchor choices")
Check(controls[2].values()[2].text == "Top" and #controls[3].values() == 9, "popup point choices differ from the catalog")
Check(controls[1].set("player") and config.anchorTarget == "player", "popup target did not use the shared setting")
print("Buff reminder anchors: " .. checks .. " checks passed")
