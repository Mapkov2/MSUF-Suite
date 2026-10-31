local root = assert(arg[1], "repository root required")
local sourcePath = root .. "/MSUF_Suite_Options/Menu/PreviewCanvas.lua"

-- The header is detached from the scrolling page wrapper. Their effective
-- visibility can settle in separate native notifications; neither notification
-- implies that the other owner has already become visible. Keep those states
-- explicit here rather than deriving both from one ancestor's shown flag.
-- This is a watcher ordering contract, not a simulated full native renderer.
local function Fixture()
    local frames, timers = {}, {}
    local state = { paints = 0, scheduled = 0, callbacks = 0, refreshers = {} }
    local Methods = {}
    Methods.__index = Methods
    function Methods:IsVisible()
        if self.parent then return self.shown and self.parent:IsVisible() end
        return self.shown and self.visible
    end
    function Methods:IsShown() return self.shown end
    function Methods:SetScript(name, callback) self.scripts[name] = callback end
    function Methods:GetScript(name) return self.scripts[name] end
    function Methods:HookScript(name, callback)
        local hooks = self.hooks[name] or {}
        hooks[#hooks + 1] = callback
        self.hooks[name] = hooks
    end
    function Methods:RegisterEvent(event) self.events[event] = true end
    function Methods:UnregisterAllEvents() self.events = {} end
    function Methods:Fire(name, ...)
        local script = self.scripts[name]
        if script then script(self, ...) end
        for _, hook in ipairs(self.hooks[name] or {}) do hook(self, ...) end
    end
    local function Frame(parent)
        local frame = setmetatable({ parent = parent, shown = true, visible = false,
            scripts = {}, hooks = {}, events = {} }, Methods)
        frames[#frames + 1] = frame
        return frame
    end
    state.header, state.wrapper = Frame(), Frame()
    local function Change(owner, key, value, notify)
        local before = {}
        for _, frame in ipairs(frames) do before[frame] = frame:IsVisible() end
        owner[key] = value
        if notify == false then return end
        for _, frame in ipairs(frames) do
            local after = frame:IsVisible()
            if before[frame] ~= after then frame:Fire(after and "OnShow" or "OnHide") end
        end
    end
    function state:Visible(owner, visible, notify) Change(owner, "visible", visible, notify) end
    function state:Shown(owner, shown) Change(owner, "shown", shown) end
    function state:Flush()
        local batch = timers
        timers = {}
        for _, callback in ipairs(batch) do
            self.callbacks = self.callbacks + 1
            callback()
        end
        assert(#timers == 0, "visibility replay scheduled another replay instead of stopping")
    end
    function state:Pending() return #timers end
    local P = { M = { TrackRefresh = function(_, callback)
        state.refreshers[#state.refreshers + 1] = callback
    end } }
    local env = setmetatable({
        CreateFrame = function(_, _, parent) return Frame(parent) end,
        C_Timer = { After = function(delay, callback)
            assert(delay == 0, "visibility replay must run once on the next frame")
            state.scheduled = state.scheduled + 1
            timers[#timers + 1] = callback
        end },
    }, { __index = _G })
    local chunk = assert(loadfile(sourcePath))
    setfenv(chunk, env)
    chunk("MSUF_Suite_Options", P)
    state.ui = { header = state.header, ctx = { wrapper = state.wrapper } }
    P.PreviewCanvas.Watch(state.ui, function()
        assert(state.header:IsVisible() and state.wrapper:IsVisible(), "paint escaped the owner visibility gate")
        state.paints = state.paints + 1
    end)
    assert(state.paints == 0 and state.scheduled == 0, "hidden construction painted or scheduled work")
    assert(#state.refreshers == 1, "preview did not register its settings refresher")
    return state
end

local cases = {}
function cases.header_first_wrapper_later()
    local f = Fixture()
    f:Visible(f.header, true)
    assert(f.paints == 0, "header appearance painted before the wrapper")
    f:Flush()
    assert(f.paints == 0, "unsettled wrapper painted during one-shot replay")
    f:Visible(f.wrapper, true)
    f:Flush()
    assert(f.paints == 1, "later wrapper visibility never woke the detached-header preview")
end
function cases.one_frame_visibility_settle()
    local f = Fixture()
    f:Visible(f.header, true)
    assert(f:Pending() == 1, "early header visibility did not queue exactly one settle replay")
    f:Visible(f.wrapper, true, false)
    f:Flush()
    assert(f.paints == 1, "preview stayed blank after effective visibility settled")
end
function cases.wrapper_first_header_later()
    local f = Fixture()
    f:Visible(f.wrapper, true)
    f:Flush()
    assert(f.paints == 0, "wrapper appearance painted before the header")
    f:Visible(f.header, true)
    f:Flush()
    assert(f.paints == 1, "later header visibility never woke the preview")
end
function cases.public_refresh_after_geometry_transition()
    local f = Fixture()
    f:Visible(f.header, true, false)
    for _ = 1, 20 do f.ui.refreshPreview() end
    assert(f.paints == 0 and f:Pending() == 1, "public refresh missed or duplicated the geometry-settle replay")
    f:Visible(f.wrapper, true, false)
    f:Flush()
    assert(f.paints == 1, "public refresh never recovered after its missed visibility gate")
end
function cases.hide_cancels_pending_paint()
    local f = Fixture()
    f:Visible(f.header, true)
    f:Visible(f.header, false)
    f:Flush()
    assert(f.paints == 0, "hidden preview painted an abandoned request")
    local scheduled = f.scheduled
    for _ = 1, 100 do f.ui.refreshPreview() end
    assert(f.scheduled == scheduled and f:Pending() == 0, "hidden refresh started background retries")
    f:Visible(f.wrapper, true)
    f:Visible(f.header, true)
    f:Flush()
    assert(f.paints == 1, "cancelling a hidden request prevented the next visible paint")
end
function cases.logically_hidden_header_does_not_queue()
    local f = Fixture()
    f:Shown(f.header, false)
    f:Visible(f.header, true, false)
    f:Visible(f.wrapper, true)
    for _ = 1, 100 do f.ui.refreshPreview() end
    assert(f.paints == 0 and f.scheduled == 0, "intentionally hidden header scheduled layout retries")
    f:Shown(f.header, true)
    f:Flush()
    assert(f.paints == 1, "showing the collapsed header did not repaint")
end
function cases.logically_hidden_wrapper_does_not_queue()
    local f = Fixture()
    f:Shown(f.wrapper, false)
    f:Visible(f.wrapper, true, false)
    f:Visible(f.header, true)
    for _ = 1, 100 do f.ui.refreshPreview() end
    assert(f.paints == 0 and f.scheduled == 0, "intentionally hidden wrapper scheduled layout retries")
    f:Shown(f.wrapper, true)
    f:Flush()
    assert(f.paints == 1, "showing the owning wrapper did not repaint")
end
function cases.bursts_are_bounded_and_warm_refreshes_do_not_queue()
    local f = Fixture()
    f:Visible(f.header, true)
    for _ = 1, 20 do f.ui.refreshPreview() end
    assert(f:Pending() == 1 and f.scheduled == 1, "missed-gate burst queued more than one replay")
    f:Flush()
    assert(f.paints == 0 and f:Pending() == 0, "unsettled replay polled for visibility")
    f:Visible(f.wrapper, true)
    f:Flush()
    local painted, scheduled = f.paints, f.scheduled
    for _ = 1, 100 do f.ui.refreshPreview() end
    assert(f.paints == painted + 100, "warm explicit refresh stopped painting")
    assert(f.scheduled == scheduled and f:Pending() == 0, "warm refresh allocated visibility timers")
end

local order = { "header_first_wrapper_later", "one_frame_visibility_settle", "wrapper_first_header_later",
    "public_refresh_after_geometry_transition", "hide_cancels_pending_paint", "logically_hidden_header_does_not_queue",
    "logically_hidden_wrapper_does_not_queue", "bursts_are_bounded_and_warm_refreshes_do_not_queue" }
local failed = 0
for _, name in ipairs(order) do
    local ok, message = pcall(cases[name])
    if not ok then
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(message))
    end
end
assert(failed == 0, tostring(failed) .. " preview visibility lifecycle cases failed")
print("Preview canvas lifecycle: staged owner visibility, public refresh, bounded replay, cancellation and warm timer budgets passed")
