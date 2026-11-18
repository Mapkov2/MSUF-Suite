local _, NS = ...
local Caption = {}
NS.PublicCaption = Caption
local S, W = NS.Safety, NS.PublicWidgets
local active = setmetatable({}, { __mode = "k" })
local Watch, Unwatch
local cache = setmetatable({}, { __mode = "k" })
local slots = { "GetNormalTexture", "GetHighlightTexture", "GetPushedTexture", "GetDisabledTexture" }
local extras = { "Icon", "icon", "Border", "Bg", "NormalTexture", "PushedTexture", "DisabledTexture", "HighlightTexture", "HoverTexture" }

function Caption.Parts(button)
    local parts = {}
    local function Add(part)
        if not S.Public(part) then return false end
        if part == nil then return true end
        if not W.Safe(part) or not W.Belongs(button, part) then return false end
        if S.HasMethod(part, "SetAlpha") then parts[part] = true end
        return true
    end
    for _, slot in ipairs(slots) do if not Add(S.Call(button, slot)) then return end end
    for _, key in ipairs(extras) do
        local part = S.Field(button, key)
        if not S.Public(part) or type(part) == "table" and not Add(part) then return end
    end
    local label = S.Read(button, "GetFontString")
    local text = S.Read(label, "GetText")
    if (text == "X" or text == "x" or text == "×" or text == "✕") and not Add(label) then return end
    return parts
end

local function Paint(state, layout)
    if not state.enabled or NS.IsCombatLocked() or not W.Safe(state.button) then return end
    local art = state.art
    art.disabled = S.Read(state.button, "IsEnabled") == false
    if layout then NS.SuiteCore().WindowCaption.UpdateGlyph(state.cell, art, true) end
    NS.WindowControlChrome.PaintActionCell(state.cell)
end

local function Event(button, hover, down, layout)
    local state = cache[button]
    if not state or not state.enabled then return end
    if hover ~= nil then state.art.hover = hover end
    if down ~= nil then state.art.down = down end
    if layout then NS.Registry.QueueJob(state.refresh)
    elseif NS.IsCombatLocked() then NS.CombatGate.RunOrDefer(state, state.refresh) else Paint(state) end
end

local function Create(button, kind)
    local cell = S.CreateChildFrame("Frame", button)
    local art = NS.WindowControlChrome.Control(cell, kind, 1, true)
    cell:ClearAllPoints()
    cell:SetAllPoints(button)
    local state = { button = button, cell = cell, art = art }
    cache[button] = state
    state.refresh = function() Paint(state, true) end
    button:HookScript("OnEnter", function(b) Event(b, true) end)
    button:HookScript("OnLeave", function(b) Event(b, false, false) end)
    button:HookScript("OnMouseDown", function(b) Event(b, nil, true) end)
    button:HookScript("OnMouseUp", function(b) Event(b, nil, false) end)
    button:HookScript("OnHide", function(b) Event(b, false, false) end)
    button:HookScript("OnSizeChanged", function(b) Event(b, nil, nil, true) end)
    button:HookScript("OnEnable", function(b) Event(b) end)
    button:HookScript("OnDisable", function(b) Event(b, false, false) end)
    return state
end

local function ReleasePart(button, part, owner)
    if W.Safe(part) and W.Belongs(button, part) then NS.Cosmetics.Restore(part, owner)
    else NS.Cosmetics.Forget(part, owner) end
end

function Caption.Apply(entry, parts)
    local button = entry.target
    local state = cache[button] or Create(button, entry.control.action)
    if state.enabled and entry.caption ~= state then return false, "already-owned" end
    entry.caption, state.owner = state, entry.owner
    state.art.kind = entry.control.action
    state.art.hover = S.Read(button, "IsMouseOver") == true
    state.art.down = S.Read(button, "GetButtonState") == "PUSHED"
    state.enabled = true
    if state.parts then
        for part in pairs(state.parts) do if not parts[part] then ReleasePart(button, part, state.owner) end end
    end
    state.parts = parts
    for part in pairs(parts) do
        if S.Read(part, "GetAlpha") ~= 0 or NS.Cosmetics.GetOwner(part) ~= state.owner then
            if NS.Cosmetics.GetOwner(part) == state.owner then NS.Cosmetics.CaptureNativeAlpha(part, state.owner) end
            if not NS.Cosmetics.Fade(part, state.owner) then return false, "unsupported-caption-art" end
        end
    end
    Watch(state)
    state.cell:Show()
    Paint(state, true)
    return true
end

function Caption.Release(entry)
    local state = entry.caption
    if not state then return end
    state.enabled, entry.caption = false, nil
    NS.CombatGate.Cancel(state)
    for part in pairs(state.parts or {}) do ReleasePart(state.button, part, state.owner) end
    state.parts, state.owner = nil, nil
    Unwatch(state)
    state.cell:Hide()
end

local function Repaint()
    for state in pairs(active) do
        if state.enabled and W.Safe(state.button) then NS.WindowControlChrome.PaintActionCell(state.cell, true) end
    end
end
local function Setting(_, domain, key)
    if domain == "theme" or domain == "profile" or domain == "windowAction"
        or domain == "color" and (key == "text" or key == "danger" or key == "disabled") then NS.Registry.QueueJob(Repaint) end
end
Watch = function(state)
    if not next(active) then NS.Registry.AddListener(Caption, Setting) end
    active[state] = true
end
Unwatch = function(state)
    active[state] = nil
    if not next(active) then NS.Registry.RemoveListener(Caption) end
end
