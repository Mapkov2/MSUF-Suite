-- Optional arg 2 is the MSUF 7.0 host checkout; arg 3 is the client label.
local root = assert(arg[1], "repository root required")
local hostRoot, flavor = arg[2], arg[3] or "Mainline"
if hostRoot == "-" or hostRoot == "" then hostRoot = nil end
assert(flavor == "Mainline" or flavor == "Forever", "unsupported client")
local private
local original = loadfile
loadfile = function(path)
    local chunk, message = original(path)
    if not chunk or not path:find("MSUF_Suite_BuffReminders/Visuals.lua", 1, true) then return chunk, message end
    return function(name, namespace) private = namespace; return chunk(name, namespace) end
end
dofile(root .. "/tools/tests/suite_buff_reminders_contract.lua")
loadfile = original
local R, NS, S = private.BuffReminders, private.NS, private.Suite
assert(type(R.StyleIcon) == "function", "reminders must share the host skin painter in runtime and preview")
local paints, shapes, compiles, watched = 0, 0, 0, {}
local look = { signature = "shadow-gloss" }
NS.IconShapeIds = { "RECTANGLE", "CIRCLE", "ROUNDED", "DIAMOND", "HEXAGON", "BLIZZARD" }
NS.HostBridge = {
    IconSkinLook = function(choice, shape)
        compiles = compiles + 1
        if choice == "CUSTOM" or choice == false then return nil end
        return look
    end,
    ApplyIconShape = function(_, shape) shapes = shapes + 1; return shape end,
    PaintIconSkin = function(_, skin, width, height, anchor)
        paints = paints + 1
        assert(width == height and anchor, "skin must surround the actual reminder icon")
        return skin ~= nil
    end,
    IconShapeArt = function(shape) if shape ~= "RECTANGLE" then return "ring:" .. shape end end,
    WatchIconSkins = function(id, on) watched[id] = on end,
}
local function Button()
    local b = CreateFrame("Button")
    R.CreateIcon(b)
    b.border.SetVertexColor = function() end
    b.border.SetDrawLayer = function() end
    return b
end
local c = { size = 38, iconSkin = "SHADOW1", iconShape = 2, borderColor = "e8b855" }
local shape, skin = R.IconLook(c)
local b = Button()
R.StyleIcon(b, c, skin, shape)
assert(paints == 1 and shapes == 1 and b.reminderSkinned, "full host look and mask must apply once")
R.StyleIcon(b, c, skin, shape)
assert(paints == 1 and shapes == 1, "unchanged style must perform no native skin or mask writes")
c.size = 54
R.StyleIcon(b, c, skin, shape)
assert(paints == 2 and shapes == 2, "resizing must rescale shadow and gloss")
c.iconSkin, c.iconShape = "CUSTOM", 1
shape, skin = R.IconLook(c)
R.StyleIcon(b, c, skin, shape)
assert(not b.reminderSkinned and paints == 3 and shapes == 3, "turning off must hide the old skin and remove its mask")
R.StyleIcon(b, c, skin, shape)
assert(paints == 3 and shapes == 3, "off must remain idle")
-- Normal keeps only the chosen skin; highlight and pulse remain above it.
local owner = { config = c, view = {} }
c.iconSkin, c.iconShape = "SHADOW1", 1
shape, skin = R.IconLook(c)
R.StyleIcon(b, c, skin, shape)
R.AlertTransition(owner, b, { kind = "spell", id = 1459 }, true)
assert(b.reminderAlertBorder and not b.reminderAlertBorder.shown and not b.border.shown,
    "a square full skin must not retain the old golden border")
c.reminderGlow = 2
R.AlertTransition(owner, b, { kind = "spell", id = 1459 }, true)
assert(b.reminderAlertBorder.shown, "highlight must remain visible above a square host skin")
c.reminderGlow = 3
R.AlertTransition(owner, b, { kind = "spell", id = 1459 }, true)
assert(b.alertPulse and b.alertPulse.playing, "pulse must animate the visible ring")
c.iconShape = 2
shape, skin = R.IconLook(c)
R.StyleIcon(b, c, skin, shape)
R.AlertTransition(owner, b, { kind = "spell", id = 1459 }, true)
assert(not b.reminderAlertBorder and b.border.shown and b.alertPulse.playing,
    "a shaped skin must use a shaped alert ring and move the native pulse to it")
local calls = compiles
local m = testModule
m.config.iconSkin, m.config.iconShape = "SHADOW1", 2
m:Enable()
assert(watched.buffReminders == true, "enabled reminders must follow host profile changes")
local before = paints
m:Compile()
assert(paints == before, "unchanged compile must not repaint skins")
for i = 1, 100 do m:Update("aura") end
assert(paints == before and compiles == calls + 2, "aura refreshes must not resolve or paint skins")
local combatCheck = NS.IsCombatLocked
NS.IsCombatLocked = function() return true end
m.config.iconShape = 3
m:Compile()
assert(paints == before, "secure pool styling must be deferred in combat")
NS.IsCombatLocked = combatCheck
m.config.iconShape = 2
look = { signature = "new-host-profile" }
m:Refresh()
assert(paints > before, "a host/default/profile look change must restyle the secure pool")
m:Disable()
assert(watched.buffReminders == false, "disabled reminders must stop watching host skins")
-- The actual bridge callback must skip CUSTOM and retain default/fixed
-- consumers when a global tint or gloss edit changes their compiled look.
do
    local recording, callback, applies = NS.HostBridge, nil, 0
    local api = MSUF_HostAPI
    MSUF_HostAPI = { version = 1, GetIconSkins = function()
        return { version = 1, DEFAULT = "DEFAULT", CUSTOM = "CUSTOM",
            Compile = recording.IconSkinLook, Paint = recording.PaintIconSkin,
            ApplyShape = recording.ApplyIconShape, ShapeArt = recording.IconShapeArt,
            Subscribe = function(_, fn) callback = fn end }
    end }
    NS.Suite = { Apply = function(id)
        assert(id == "buffReminders")
        applies = applies + 1
        m:Refresh()
    end }
    assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", NS)
    NS.HostBridge.IconSkins()
    m.config.iconSkin, m.config.iconShape = "CUSTOM", 1
    m:Enable()
    callback("apply")
    assert(applies == 0, "enabled CUSTOM reminders must not refresh on a global skin edit")
    for _, choice in ipairs({ "DEFAULT", "SHADOW1" }) do
        m.config.iconSkin = choice
        m:Refresh()
        local prior, writes = applies, paints
        look = { signature = "global-color-" .. choice }
        callback("apply")
        assert(applies == prior + 1 and paints > writes, choice .. ": global tint/gloss edit must refresh reminders")
        m.config.iconSkin = "CUSTOM"
        m:Refresh()
        prior = applies
        callback("profile")
        assert(applies == prior, "reset CUSTOM reminders must stop following global skins")
    end
    m:Disable()
    MSUF_HostAPI = api
end
if hostRoot then
    -- Reuse the established host/region fixture, including the actual engine,
    -- rather than maintaining another fake MSUF skin implementation here.
    local hostNS
    loadfile = function(path)
        local chunk, message = original(path)
        if path:find("/Runtime/MSUF_HostAPI.lua", 1, true) then
            return function(name, namespace)
                namespace.Client = { Family = "Mainline", Flavor = "Mainline", IsRetail = true, IsForever = flavor == "Forever" }
                return chunk(name, namespace)
            end
        end
        if not chunk or not path:find("/MSUF_Suite/Core/HostBridge.lua", 1, true) then return chunk, message end
        return function(name, namespace) hostNS = namespace; return chunk(name, namespace) end
    end
    dofile(root .. "/tools/tests/suite_icon_skins_contract.lua")
    loadfile = original
    NS.HostBridge = assert(hostNS).HostBridge
    local realButton = CreateFrame("Button", nil, UIParent)
    R.CreateIcon(realButton)
    local currentMask
    local addMask, removeMask = realButton.icon.AddMaskTexture, realButton.icon.RemoveMaskTexture
    realButton.icon.AddMaskTexture = function(self, mask) currentMask = mask; return addMask(self, mask) end
    realButton.icon.RemoveMaskTexture = function(self, mask) currentMask = nil; return removeMask(self, mask) end
    local realConfig = { size = 38, spacing = 5, columns = 6, iconSkin = "SHADOW1", iconShape = 1,
        borderColor = "e8b855" }
    local realShape, realLook = R.IconLook(realConfig)
    assert(realLook, "the real host must compile Shadow 1")
    R.StyleIcon(realButton, realConfig, realLook, realShape)
    local gloss, layers = false, 0
    for _, child in ipairs(realButton.children) do
        gloss = gloss or child.layer == "OVERLAY" and child.sublevel == -1
        if child.layer == "ARTWORK" and (child.sublevel or 0) >= 5 then layers = layers + 1 end
    end
    assert(realButton.reminderSkinned and gloss and layers > 0, "the actual host must draw shadow, frame and gloss")
    local function Writes()
        local n = 0
        for _, child in ipairs(realButton.children) do
            for _, count in pairs(child.calls or {}) do n = n + count end
        end
        return n
    end
    local beforeWrites = Writes()
    R.StyleIcon(realButton, realConfig, realLook, realShape)
    assert(Writes() == beforeWrites, "an unchanged real skin must do no region writes")
    for index, shapeID in ipairs(NS.IconShapeIds) do
        realConfig.iconShape, realConfig.iconSkin = index, "CUSTOM"
        realShape, realLook = R.IconLook(realConfig)
        R.StyleIcon(realButton, realConfig, realLook, realShape)
        assert(realButton.reminderStyleShape == shapeID and not realButton.reminderSkinned,
            shapeID .. ": a custom shape must remove the previous skin")
        assert((currentMask ~= nil) == (shapeID ~= "RECTANGLE"), shapeID .. ": actual icon mask mismatch")
        assert(realButton.count.AddMaskTexture == nil, "count text must never receive the icon mask")
    end
    realConfig.iconShape, realConfig.iconSkin = 1, false
    realShape, realLook = R.IconLook(realConfig)
    R.StyleIcon(realButton, realConfig, realLook, realShape)
    assert(not currentMask and not realButton.reminderSkinned, "explicit false must restore native rectangle")
    realConfig.iconShape, realConfig.iconSkin = 1, "SHADOW1"
    local stage = CreateFrame("Frame", nil, UIParent)
    S.BuffRemindersDrawPreview(stage, realConfig, true, function() end,
        { "MAGE", "Mage", 1459, 777, 888, 135932 })
    for _, icon in ipairs(stage.buffReminderPreview.view.buttons) do
        assert(icon.reminderSkinned and icon.reminderStyleLook == select(2, R.IconLook(realConfig)),
            "the actual preview must share runtime's compiled look and painter")
    end
    S.BuffRemindersReleasePreview(stage)
end
print("Suite reminder skins: host painting, shape/reset, cold cache, profile refresh and aura silence passed")
