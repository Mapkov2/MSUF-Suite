-- Exact window-action lifecycle paints safe controls in combat without a driver.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_skin_motion_contract.lua", "rb"))
local source = file:read("*a"); file:close()
local stop = assert(source:find('local parent = Target("Frame", UIParent)', 1, true))
source = source:sub(1, stop - 1):gsub('Load%("Rendering/WindowActionSkin.lua"%)',
    'assert(loadfile(arg[3] or root .. "/MSUF_Suite_Skin/Rendering/WindowActionSkin.lua"))("MSUF_Suite_Skin", NS)')
local H = assert(loadstring(source .. [[
return { NS = NS, Target = Target, Texture = Texture, created = created, Tick = Tick,
    SetCombat = function(value) lockdown = value end }
]], "@window_action_combat_fixture"))()
local NS, checks, jobs, writes = H.NS, 0, {}, 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
NS.CombatGate.RunOrDefer = function(key, callback)
    if NS.IsCombatLocked() then jobs[key] = callback; return false, "combat" end
    return callback()
end
NS.CombatGate.Cancel = function(key) jobs[key] = nil end
NS.Checkmarks.DetectWindowAction = function(button) return button.detected or "close" end
NS.DB.icons.windowActions.style = "bare"
local W = NS.WindowActionSkin
local suffixes = { Normal = "", Pushed = "-Pressed", Disabled = "-Disabled", Highlight = "-Highlight" }
local function Texture(parent, atlas)
    local texture = H.Texture()
    texture.atlas = atlas
    function texture:IsProtected() return self.protected or parent.protected or false, self.explicit or false end
    function texture:IsForbidden() return self.forbidden == true end
    function texture:GetAtlas() return self.atlas end
    function texture:SetAtlas(value) self.atlas = value end
    for _, key in ipairs({ "SetAlpha", "SetAtlas", "SetSize", "SetPoint", "ClearAllPoints", "SetVertexColor", "Show", "Hide" }) do
        local native = texture[key]
        texture[key] = function(self, ...)
            local protected, explicit = self:IsProtected()
            assert(not self.forbidden and not explicit and not (protected and NS.IsCombatLocked()), "protected action texture write")
            writes = writes + 1
            return native(self, ...)
        end
    end
    return texture
end
local function Button()
    local button = H.Target("Button", UIParent)
    function button:CreateTexture() return Texture(self) end
    for key, suffix in pairs(suffixes) do button.slots[key] = Texture(button, "redbutton-exit" .. suffix) end
    return button
end
local function Drain()
    H.SetCombat(false)
    for key, callback in pairs(jobs) do jobs[key] = nil; callback() end
    H.SetCombat(true)
end
H.SetCombat(true)
local button = Button()
local state = W.Apply(button, "combat", "close")
Check(state and W.HasOwnedStates(button) and next(jobs) == nil, "cold safe combat action stayed native or queued work")
local nativeNormal = state.native.normal
state.glyphs.normal.atlas, state.glyphs.pushed.atlas = "redbutton-expand", "redbutton-expand-Pressed"
Check(W.SyncNativeVisual(button, "combat", "maximize") == state and nativeNormal.atlas == "redbutton-expand",
    "safe native visual reset did not synchronize in combat")
button.slots.Normal, button.slots.Pushed = Texture(button, "redbutton-exit"), Texture(button, "redbutton-exit-Pressed")
Check(W.AdoptNativeVisual(button, "combat", "close") == state and W.HasOwnedStates(button),
    "safe replaced native slots were not adopted in combat")
for key, suffix in pairs(suffixes) do button.slots[key].atlas = "redbutton-condense" .. suffix end
Check(W.SyncButtonArtKit(button, "combat", "redbutton-condense", "minimize") == state
    and state.native.disabled.atlas == "redbutton-condense-Disabled", "safe native art kit did not synchronize in combat")
button.detected = "close"
Check(W.OnNativeChanged(button) and state.kind == "close", "safe native changed callback lost current action")
Check(next(jobs) == nil, "safe lifecycle accumulated combat jobs")
-- Every actual write target matters, even below an otherwise safe button.
button.Border = Texture(button)
for _, target in ipairs({ button, button.slots.Normal, state.native.normal, button.Border }) do
    target.protected = true
    local before = writes
    Check(W.Apply(button, "combat", "close") == nil, "protected target accepted an immediate skin")
    W.SyncNativeVisual(button, "combat", "close")
    W.AdoptNativeVisual(button, "combat", "close")
    W.SyncButtonArtKit(button, "combat", "redbutton-exit", "close")
    W.OnNativeChanged(button)
    Check(writes == before and next(jobs) ~= nil, "protected lifecycle wrote artwork or lost bounded recovery")
    target.protected = nil
    Drain()
end
local protected = Button()
protected.explicit = true
Check(W.Apply(protected, "protected", "close") == nil, "explicit protected action accepted skin")
Drain()
Check(W.states[protected] == nil, "explicit protected action acquired artwork after combat")
button.Border.forbidden = true
local before = writes
W.SyncNativeVisual(button, "combat", "close")
Check(writes == before, "forbidden extra art received a write")
button.Border.forbidden = nil
Drain()
-- An owner-wide disable remains a barrier against later combat callbacks.
W.DisableOwner("combat")
local disabledWrites = writes
W.Apply(button, "combat", "close")
Check(writes == disabledWrites, "disabled owner repainted before combat cleanup")
Drain()
Check(not state.visible, "combat callback revived a disabled action owner")
H.SetCombat(false)
Check(W.Apply(button, "combat", "close") == state, "safe owner reactivation lost reusable artwork")
local compact = Button()
compact.width, compact.height = 16, 12
function compact:GetWidth() return self.width end
function compact:GetHeight() return self.height end
local settings = NS.DB.icons.windowActions
settings.closeGlyphSize, settings.glyphOffsetX, settings.glyphOffsetY = 24, 5, -5
local compactState = W.Apply(compact, "compact", "close")
local glyph = compactState.glyphs.normal
local center = glyph.points.CENTER
Check(math.abs(center.x) + glyph.width * 1.04 / 2 <= 8.001 and math.abs(center.y) + glyph.height * 1.04 / 2 <= 6.001,
    "native close glyph or its hover growth crossed the compact button")
H.SetCombat(true)
Check(W.Disable(button, "combat") and not state.visible, "safe per-button disable waited for combat")
button:Hide(); H.Tick()
for _, frame in ipairs(H.created) do Check(frame:GetScript("OnUpdate") == nil, "closed action retained an updater") end
Check(next(jobs) == nil, "closed action retained combat jobs")
-- Windows mode: Blizzard's maximize/minimize pair draws Windows' maximize
-- square and restore squares; close and the other modes keep their glyphs.
H.SetCombat(false)
local caption = Button()
local captionState = W.Apply(caption, "caption", "maximize")
for _, glyph in pairs(captionState.glyphs) do
    function glyph:SetTexture(path) self.file = path end
    function glyph:SetTexCoord(left, right) self.left, self.right = left, right end
end
local function Glyph(kind, mode)
    settings.glyphMode = mode
    Check(W.Apply(caption, "caption", kind) == captionState, kind .. " " .. mode .. " did not apply")
    local glyph = captionState.glyphs.normal
    return glyph.file, glyph.left, glyph.right
end
local path, left, right = Glyph("maximize", "windows")
Check(path:find("MapkoSkinWindowCaptionFine", 1, true) and left == 0 and right == 0.5,
    "Windows mode lacks the maximize square")
path, left, right = Glyph("minimize", "windows")
Check(path:find("MapkoSkinWindowCaptionFine", 1, true) and left == 0.5 and right == 1,
    "Windows mode lacks the restore squares")
path, left = Glyph("close", "windows")
Check(path:find("MapkoSkinWindowActionsFine", 1, true) and left == 0, "Windows mode changed the close glyph")
path, left = Glyph("maximize", "plusMinus")
Check(path:find("MapkoSkinWindowActionsFine", 1, true) and left == 1 / 8, "plus/minus mode lost its plus")
settings.weight = "bold"
path = Glyph("minimize", "windows")
Check(path:find("MapkoSkinWindowCaptionBold", 1, true), "bold weight lost the bold restore squares")
settings.weight = "fine"
-- A button our Windows caption cell stands for drops the action skin at once
-- and takes none while the cell is there; released, it can be skinned again.
W.Yield(caption, true)
Check(not captionState.visible and caption.slots.Normal.atlas == "redbutton-exit"
    and W.Apply(caption, "caption", "close") == nil, "a captioned native kept or retook the old action skin")
W.Yield(caption, false)
Check(W.Apply(caption, "caption", "close") == captionState and captionState.visible,
    "a released native could not take the action skin again")
print("Window action combat parity: " .. checks .. " checks passed (" .. tostring(arg[2]) .. ")")
