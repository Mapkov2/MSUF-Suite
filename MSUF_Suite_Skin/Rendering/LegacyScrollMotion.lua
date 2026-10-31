local _, NS = ...

-- Short render transforms follow the native offset; no scroll write, wheel
-- replacement, recurring timer or persistent update script is installed.
local Legacy = { states = setmetatable({}, { __mode = "k" }) }
NS.LegacyScrollMotion = Legacy
local Safety = NS.Safety

local function Stop(state)
    if state.current then state.current.group:Stop() end
end

local function SmoothScrolling()
    local db = NS.DB
    return db and db.enabled and db.theme.smoothScrolling ~= false and db.theme.reduceMotion ~= true
end

local function Enabled()
    return SmoothScrolling() and not NS.Motion.combat and not NS.IsCombatLocked()
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

-- A legacy Slider bar gets no OnMouseDown/OnMouseUp: Forever's SmartNavigation reads
-- both with GetScript on every non-Button of a panel it scans (Blizzard_Gamepad-
-- SmartNavigation/Utility.lua:196-206), and a skin hook there is a tainted value in
-- that secure scan. A drag starts on a global press over a shown bar and ends on the
-- global release. Presses are watched only while a tracked bar shows, out of combat
-- and with smooth scrolling on; the release only while a drag is held.
local events = CreateFrame("Frame")
local bars = setmetatable({}, { __mode = "k" })
local shownBars = setmetatable({}, { __mode = "k" })

local function Watch(combat)
    if not combat and next(shownBars) and SmoothScrolling() and not NS.IsCombatLocked() then
        events:RegisterEvent("GLOBAL_MOUSE_DOWN")
    else
        events:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    end
end

local function Owned(bar)
    for _, state in pairs(Legacy.states) do
        if state.bar == bar and next(state.owners) then return true end
    end
    return false
end

local function BarShown(bar)
    if Owned(bar) then shownBars[bar] = true Watch() end
end

local function BarHidden(bar)
    for _, state in pairs(Legacy.states) do
        if state.bar == bar then state.dragging = false end
    end
    shownBars[bar] = nil
    Watch()
end

local function DragDown(button)
    if not Safety.Public(button) or button ~= "LeftButton" or not Enabled() then return end
    for bar in pairs(shownBars) do
        if Safety.Read(bar, "IsMouseOver") == true then
            for _, state in pairs(Legacy.states) do
                if state.bar == bar and next(state.owners) then state.dragging = true Stop(state) end
            end
            events:RegisterEvent("GLOBAL_MOUSE_UP")
        end
    end
end

local function DragReleased(button)
    if not Safety.Public(button) or button ~= "LeftButton" then return end
    events:UnregisterEvent("GLOBAL_MOUSE_UP")
    for _, state in pairs(Legacy.states) do state.dragging = false end
end

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
            bar:HookScript("OnShow", BarShown)
            bar:HookScript("OnHide", BarHidden)
        end
        if Safety.Read(bar, "IsVisible") == true then shownBars[bar] = true end
        Watch()
    end
    return true
end

function Legacy.ReleaseOwner(owner)
    NS.ScrollMotion.ReleaseOwner(owner)
    for _, state in pairs(Legacy.states) do
        state.owners[owner] = nil
        if not next(state.owners) then Stop(state) end
    end
    for bar in pairs(shownBars) do
        if not Owned(bar) then shownBars[bar] = nil end
    end
    Watch()
end
local function StopAll()
    for _, state in pairs(Legacy.states) do Stop(state) end
end
-- PLAYER_REGEN_DISABLED arrives before lockdown is on, so combat is passed in.
local function OnEvent(_, event, button)
    if event == "GLOBAL_MOUSE_DOWN" then DragDown(button)
    elseif event == "GLOBAL_MOUSE_UP" then DragReleased(button)
    elseif event == "PLAYER_REGEN_DISABLED" then StopAll() Watch(true)
    else Watch() end
end
local function SettingsChanged()
    StopAll()
    Watch()
end
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", OnEvent)
NS.Registry.AddListener(Legacy, SettingsChanged)
