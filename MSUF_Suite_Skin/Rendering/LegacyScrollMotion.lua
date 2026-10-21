local _, NS = ...

-- Short render transforms follow the native offset; no scroll write, wheel
-- replacement, recurring timer or persistent update script is installed.
local Legacy = { states = setmetatable({}, { __mode = "k" }) }
NS.LegacyScrollMotion = Legacy
local Safety = NS.Safety

local function Stop(state)
    if state.current then state.current.group:Stop() end
end

local function Enabled()
    local db = NS.DB
    return db and db.enabled and db.theme.smoothScrolling ~= false and db.theme.reduceMotion ~= true
        and not NS.Motion.combat and not NS.IsCombatLocked()
end

local function Hidden(frame)
    local state = Legacy.states[frame]
    if state then state.dragging = false Stop(state) end
end

local function RangeChanged(frame)
    local state = Legacy.states[frame]
    if state then Stop(state) state.offset = Safety.Read(frame, "GetVerticalScroll") end
end

local function Changed(frame, offset)
    local state = Legacy.states[frame]
    if not state or not next(state.owners) or not Safety.Public(offset) or type(offset) ~= "number" then return end
    local previous = state.offset
    state.offset = offset
    if previous == nil or previous == offset then return end
    local child = Safety.Read(frame, "GetScrollChild")
    if not Enabled() or state.dragging or not Safety.CanCreateRegions(child) or Safety.GetProtection(child)
        or Safety.Read(frame, "IsVisible") ~= true then Stop(state) return end
    local record = state.records[child]
    if not record then
        local group = child:CreateAnimationGroup()
        local move = group:CreateAnimation("Translation")
        move:SetDuration(0.11)
        move:SetSmoothing("OUT")
        record = { group = group, move = move }
        state.records[child] = record
    end
    local carry = 0
    if record.group:IsPlaying() then
        local progress = Safety.Read(record.move, "GetSmoothProgress")
        if type(progress) == "number" then carry = record.offset * progress end
    end
    Stop(state)
    record.offset = previous - offset + carry
    record.move:SetOffset(0, record.offset)
    state.current = record
    record.group:Play(true)
end

local function DragDown(bar, button)
    if not Safety.Public(button) or button ~= "LeftButton" then return end
    for _, state in pairs(Legacy.states) do
        if state.bar == bar and next(state.owners) then state.dragging = true Stop(state) end
    end
end
local function DragUp(bar)
    for _, state in pairs(Legacy.states) do
        if state.bar == bar then state.dragging = false end
    end
end
local bars = setmetatable({}, { __mode = "k" })

function Legacy.Track(frame, owner, bar)
    if not Safety.CanCreateRegions(frame) or Safety.GetProtection(frame)
        or not Safety.HasMethod(frame, "GetScrollChild") then return false end
    bar = bar or Safety.Field(frame, "ScrollBar") or Safety.Field(frame, "scrollBar")
    local state = Legacy.states[frame]
    if Safety.HasMethod(bar, "CanInterpolateScroll") then
        if state then wipe(state.owners) Stop(state) end
        return NS.ScrollMotion.Track(bar, owner)
    end
    if not state then
        state = { owners = {}, records = {}, target = frame, offset = Safety.Read(frame, "GetVerticalScroll") }
        Legacy.states[frame] = state
        frame:HookScript("OnVerticalScroll", Changed)
        frame:HookScript("OnScrollRangeChanged", RangeChanged)
        frame:HookScript("OnHide", Hidden)
    end
    state.owners[owner] = true
    if Safety.CanCreateRegions(bar) and Safety.HasMethod(bar, "HookScript") then
        state.bar = bar
        if not bars[bar] then
            bars[bar] = true
            bar:HookScript("OnMouseDown", DragDown)
            bar:HookScript("OnMouseUp", DragUp)
            bar:HookScript("OnHide", DragUp)
        end
    end
    return true
end

function Legacy.ReleaseOwner(owner)
    NS.ScrollMotion.ReleaseOwner(owner)
    for _, state in pairs(Legacy.states) do
        state.owners[owner] = nil
        if not next(state.owners) then Stop(state) end
    end
end
local function StopAll()
    for _, state in pairs(Legacy.states) do Stop(state) end
end
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", StopAll)
NS.Registry.AddListener(Legacy, StopAll)
