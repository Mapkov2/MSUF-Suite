local _, NS = ...

-- Disclosure and window-action glyphs are owned textures even when their
-- native button uses a bare look and therefore has no Surface background.
local GlyphMotion = { records = setmetatable({}, { __mode = "k" }) }
NS.GlyphMotion = GlyphMotion
local Motion, Safety = NS.Motion, NS.Safety

local function Safe(record)
    local target = record.state.target
    return record.owner.visible == true and record.owner.style ~= "native"
        and not Safety.IsForbidden(target) and not Safety.GetProtection(target)
        and Safety.Read(target, "IsVisible") == true
end

local function Paint(record)
    local c = record.channels
    local size = record.size * (1 + 0.04 * NS.Clamp(c[5].value, 0, 1)) * (1 - 0.08 * c[6].value) * c[7].value
    for _, glyph in pairs(record.owner.glyphs) do
        glyph:SetSize(size, size)
        glyph:SetRotation(c[1].value)
    end
end

local function Get(target)
    local record = GlyphMotion.records[target]
    if record and Safe(record) and Motion.Enabled(record.state.spec)
        and Safety.Read(target, "IsEnabled") == true then return record end
end

local function Enter(target)
    local record = Get(target)
    if record then
        Motion.Set(record, 5, 1)
        Motion.Play(record, 0.12)
    end
end
local function Leave(target)
    local record = Get(target)
    if record then
        Motion.Set(record, 5, 0)
        Motion.Play(record, 0.12)
    end
end
local function Down(target)
    local record = Get(target)
    if record then
        Motion.Set(record, 6, 1)
        Motion.Play(record, 0.14)
    end
end
local function Up(target)
    local record = Get(target)
    if record then
        Motion.Set(record, 6, 0)
        Motion.Play(record, 0.14)
    end
end
local function Click(target)
    local record = Get(target)
    if record then
        Motion.Set(record, 6, 0, 1)
        Motion.Play(record, 0.14)
    end
end

function GlyphMotion.Stop(target)
    local record = GlyphMotion.records[target]
    if record then Motion.Clear(record) end
end

local hooks = { OnEnter = Enter, OnLeave = Leave, OnMouseDown = Down, OnMouseUp = Up,
    OnHide = GlyphMotion.Stop, OnDisable = GlyphMotion.Stop, OnClick = Click }

function GlyphMotion.Refresh(target, owner, size, glyphMode)
    local record = GlyphMotion.records[target]
    if not record and owner.motionPolicy ~= false and Motion.Enabled() and not Safety.GetProtection(target)
        and Safety.HasMethod(target, "HasScript") then
        record = Motion.New({ target = target, spec = {} }, Paint, Safe, Motion.Restore)
        record.owner = owner
        GlyphMotion.records[target] = record
        for event, callback in pairs(hooks) do
            if target:HasScript(event) then target:HookScript(event, callback) end
        end
    end
    if not record then return end
    record.size = size
    record.state.spec.motion = owner.motionPolicy
    if not Motion.Enabled(record.state.spec) then
        Motion.Clear(record)
        record.kind = owner.kind
        return
    end
    if record.kind and record.kind ~= owner.kind then
        Motion.Set(record, 7, 1, 0.75)
        if glyphMode == "chevrons" then Motion.Set(record, 1, 0, math.pi) end
        Motion.Play(record, 0.14)
    end
    record.kind = owner.kind
end
NS.WindowActionSkin.SetMotionProvider(GlyphMotion.Refresh, GlyphMotion.Stop)
