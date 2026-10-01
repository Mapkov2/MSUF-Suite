local _, P = ...
local NS, S = P.NS, P.Suite
-- Blizzard disposal: neutralise, never destroy, once per session and out of
-- combat. Every protected mutation runs inside the restricted environment
-- (SecureHandlerExecute), so the OnShow/OnHide scripts it triggers on
-- Blizzard frames run untainted.
--  * MainActionBar stays in Blizzard's parent chain (Edit Mode anchoring and
--    the pet battle micro menu depend on it): alpha 0, mouse off, pager mouse
--    off, plus an OnShow post-hook that re-applies the alpha.
--  * MultiBar1-7 move under a permanently hidden, full-screen parent with
--    their events unregistered. They are never Hide()n: Hide on an Edit Mode
--    bar routes through protected SetShownBase.
--  * Reused Retail buttons move into suite headers; other Blizzard action
--    buttons stay under their bars and are hidden securely (statehidden).
--  * The shared broadcasters (ActionBarButtonEventsFrame, ActionBarActions
--    EventsFrame, range/usable watchers) are left untouched: reused Retail
--    buttons were registered by Blizzard, while new suite buttons never join
--    them. OverrideActionBar and ExtraActionButton1 also depend on them.
--  * StanceBar and PetActionBar move under the hidden parent but keep their
--    events: Blizzard keeps painting their buttons (secret-safe) after the
--    suite adopts those buttons into its own headers.
local AB = P.ActionBars
local M = AB.M
local Dispatch = S.Dispatch

local DISPOSE = [[
local hidden=self:GetFrameRef("hidden")
local i=1
local bar=self:GetFrameRef("bar1")
while bar do
    bar:SetParent(hidden)
    i=i+1
    bar=self:GetFrameRef("bar"..i)
end
i=1
local button=self:GetFrameRef("twin1")
while button do
    button:Hide()
    i=i+1
    button=self:GetFrameRef("twin"..i)
end
i=1
button=self:GetFrameRef("reuse"..i)
while button do
    local header=self:GetFrameRef("reuseHeader"..i)
    button:SetParent(header)
    -- Reserve a showgrid bit that Blizzard never clears (its reasons are
    -- 1/2/4). The suite's secure statehidden still decides empty/capped slots.
    local mask=button:GetAttribute("showgrid") or 0
    if floor(mask/8)%2==0 then button:SetAttribute("showgrid",mask+8) end
    button:SetAttribute("index",self:GetAttribute("reuseIndex"..i))
    button:SetAttribute("action",self:GetAttribute("reuseSlot"..i))
    button:SetAttribute("statehidden",nil)
    i=i+1
    button=self:GetFrameRef("reuse"..i)
end
local main=self:GetFrameRef("main")
if main then
    main:SetAlpha(0)
    main:EnableMouse(false)
end
]]

-- Moves Blizzard's stance/pet buttons into the suite header and applies the
-- per-button state computed out of combat ("want"..i): "show"; "idle" (inside
-- the count but empty: hidden without statehidden, so Blizzard's own
-- UpdateShownButtons can show it once it gets an action); "cap" (beyond the
-- count: statehidden keeps Blizzard from showing it). "grid"..i sets or
-- clears the showgrid reason bit 1 (Blizzard's CVAR reason) for pet slots.
local ADOPT = [[
local header=self:GetFrameRef("header")
local i=1
local button=self:GetFrameRef("button1")
while button do
    if button:GetParent()~=header then button:SetParent(header) end
    local grid=self:GetAttribute("grid"..i)
    if grid~=nil then
        local mask=button:GetAttribute("showgrid") or 0
        if (mask%2==1)~=grid then button:SetAttribute("showgrid",grid and mask+1 or mask-1) end
    end
    local want=self:GetAttribute("want"..i)
    if want=="show" then
        button:Show()
    elseif want=="idle" then
        button:SetAttribute("statehidden",nil)
        button:Hide(true)
    else
        button:Hide()
    end
    i=i+1
    button=self:GetFrameRef("button"..i)
end
]]

local function Unmouse(frame)
    if frame and not NS.Safety.IsForbidden(frame) and not frame:IsProtected() then
        frame:EnableMouse(false)
    end
end

-- MainActionBar can be re-shown by Blizzard (vehicle exit, pet battles).
-- Alpha writes are allowed in combat; its protected mouse flag is only
-- re-asserted out of combat.
local function Reassert()
    local main = AB.Frame("MainActionBar")
    if not AB.disposed or not main then return end
    main:SetAlpha(0)
    local pager = main.ActionBarPageNumber
    if pager then
        Unmouse(pager.UpButton)
        Unmouse(pager.DownButton)
    end
    Unmouse(main.Selection)
end

-- Reads what Blizzard currently shows, for the first-enable import. Must run
-- before disposal moves the bars.
function AB.ReadBlizzard()
    local toggles = { GetActionBarToggles() }
    local state = {}
    for index = 1, 12 do
        local frame
        if index <= 8 then
            frame = AB.Frame(AB.NATIVE_BARS[index])
        elseif index == 11 then
            frame = AB.Frame("StanceBar")
        elseif index == 12 then
            frame = AB.Frame("PetActionBar")
        end
        local entry = { frame = frame }
        if index >= 2 and index <= 8 then entry.toggle = toggles[index - 1] end
        state[index] = entry
    end
    return state
end

-- Blizzard's hidden bars still apply their own shown-button plan to the
-- buttons the suite reuses: action changes (UpdateAction calls
-- self.bar:UpdateShownButtons, also in combat), spellbook and Quick Keybind
-- grids and Edit Mode icon counts call UpdateShownButtons, which caps them at
-- Blizzard's icon count. The suite's plan runs again with the next flush out
-- of combat (AB.Regrid, once per bar for a burst), and the reused buttons'
-- OnHide wrap (KEEP) answers at once, also in combat. The
-- suite writes nothing on Blizzard's bar or buttons (numButtonsShowable,
-- `bar` and the like): Blizzard's secure code reads those fields, and a
-- tainted value would spread into it.
local suiteBarOf = {}
local function AfterBlizzardPlan(blizzardBar)
    local bar = suiteBarOf[blizzardBar]
    if bar and M.active then AB.Regrid(bar) end
end
-- Both hooks run inside Blizzard's call chains (UpdateShownButtons, the
-- main bar's OnShow): isolated, so an error never stops Blizzard's caller.
local function AfterBlizzardPlanHook(blizzardBar) Dispatch(AfterBlizzardPlan, blizzardBar) end
local function ReassertHook() Dispatch(Reassert) end

-- Blizzard's plan shows only buttons without statehidden, which every suite
-- hide sets (a restricted Hide), so only its hides can disagree with the
-- suite: one beyond Blizzard's icon count. When a reused button itself (not
-- its header) was hidden without statehidden, the suite's plan decides in
-- the restricted environment, also in combat (SecureHandlers.lua
-- Wrapped_ShowHide: the post-body runs after Blizzard's own OnHide).
local KEEP_PRE = [[if not self:IsShown() then return nil, true end]]
local KEEP_POST = [[
if self:GetAttribute("statehidden") then return end
local bar=self:GetParent()
local action=self:GetAttribute("action")
local show=action and (self:GetAttribute("index") or 1)<=(bar:GetAttribute("count") or 12)
if show and not bar:GetAttribute("showempty") and (bar:GetAttribute("gridmask") or 0)<2 and not HasAction(action) then show=false end
if show then self:Show() end
]]

-- Bars 2-8 and the stance and pet bars go under the hidden parent. Bars
-- 2-8 lose their events; a reused bar keeps a post-hook on its own
-- shown-button plan (AfterBlizzardPlan).
local function DisposeBars(control)
    local bars = 0
    for index = 2, 8 do
        local bar = AB.Frame(AB.NATIVE_BARS[index])
        if bar then
            bars = bars + 1
            SecureHandlerSetFrameRef(control, "bar" .. bars, bar)
            bar:UnregisterAllEvents()
            local target = AB.bars[index]
            if target and target.native then
                suiteBarOf[bar] = target
                hooksecurefunc(bar, "UpdateShownButtons", AfterBlizzardPlanHook)
            end
        end
    end
    for _, name in ipairs({ "StanceBar", "PetActionBar" }) do
        local bar = AB.Frame(name)
        if bar then
            bars = bars + 1
            SecureHandlerSetFrameRef(control, "bar" .. bars, bar)
        end
    end
end

-- Reused buttons move into the suite headers; the other Blizzard action
-- buttons (twins) are hidden securely and lose their events.
local function DisposeButtons(control)
    local twins, reused = 0, 0
    for index = 1, 8 do
        for i = 1, AB.BUTTONS do
            local button = AB.Frame(AB.NATIVE_BUTTONS[index] .. i)
            if button then
                local target = AB.bars[index]
                if target and target.native then
                    reused = reused + 1
                    -- Blizzard's `bar` field stays (its readers: UpdateAction,
                    -- proc alert art, tooltip anchor); the OnHide wrap keeps
                    -- the suite's plan. Every reused button carries a
                    -- flyoutDirection attribute (Bars.lua), so Blizzard's
                    -- flyout never asks the hidden bar for a direction.
                    SecureHandlerWrapScript(button, "OnHide", target.header, KEEP_PRE, KEEP_POST)
                    button:SetAttribute("_childupdate-grid", AB.SNIPPET.BUTTON)
                    SecureHandlerSetFrameRef(control, "reuse" .. reused, button)
                    SecureHandlerSetFrameRef(control, "reuseHeader" .. reused, target.header)
                    control:SetAttribute("reuseIndex" .. reused, i)
                    control:SetAttribute("reuseSlot" .. reused, target.buttons[i].slot)
                else
                    twins = twins + 1
                    SecureHandlerSetFrameRef(control, "twin" .. twins, button)
                    button:UnregisterAllEvents()
                end
            end
        end
    end
end

function AB.Dispose()
    if AB.disposed then return true end
    if NS.IsCombatLocked() then return false end
    local control = S.CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    local hidden = S.CreateFrame("Frame", nil, UIParent, "SecureFrameTemplate")
    hidden:SetAllPoints(UIParent)
    hidden:Hide()
    AB.hidden, AB.control = hidden, control
    SecureHandlerSetFrameRef(control, "hidden", hidden)
    DisposeBars(control)
    DisposeButtons(control)
    local main = AB.Frame("MainActionBar")
    if main then SecureHandlerSetFrameRef(control, "main", main) end
    SecureHandlerExecute(control, DISPOSE)
    AB.disposed = true
    if main then
        Reassert()
        main:HookScript("OnShow", ReassertHook)
        -- The vehicle leave button (taxis, unskinned vehicles) is parented
        -- to the invisible main bar. It is not protected; move it only when
        -- that causes no show/hide transition, else on a later refresh.
        AB.ReparentLeaveButton()
    end
    return true
end

function AB.ReparentLeaveButton()
    local leave, main = AB.Frame("MainMenuBarVehicleLeaveButton"), AB.Frame("MainActionBar")
    if AB.leaveMoved or not leave or not main or NS.IsCombatLocked() or leave:IsProtected() then return end
    if leave:GetParent() ~= main then
        AB.leaveMoved = true
        return
    end
    if leave:IsShown() and not main:IsVisible() then return end
    leave:SetParent(UIParent)
    AB.leaveMoved = true
end

local function PetHasAction(i)
    return GetPetActionInfo(i) ~= nil
end

-- Adopts Blizzard's stance (11) or pet (12) buttons into the suite header
-- and sets which of them are shown. Blizzard's own UpdateShownButtons honours
-- statehidden (set by the secure Hide) and the showgrid bit afterwards.
function AB.Adopt(index)
    local bar = AB.bars[index]
    if not bar or NS.IsCombatLocked() or not AB.control then return false end
    local control, config = AB.control, M.config
    local prefix = index == 11 and "StanceButton" or "PetActionButton"
    if not bar.adopted then
        for i = 1, 10 do
            local button = AB.Frame(prefix .. i)
            if not button then break end
            local rec = {
                button = button, bar = bar, index = i, owned = false,
                command = AB.COMMANDS[index] .. i, name = prefix .. i,
            }
            AB.records[button] = rec
            bar.buttons[i] = rec
            AB.adopted[#AB.adopted + 1] = rec
        end
        bar.adopted = true
    end
    local count = AB.Count(bar, config)
    local showEmpty = config[bar.key.ShowEmpty] and true or false
    SecureHandlerSetFrameRef(control, "header", bar.header)
    for i = 1, 10 do
        local rec = bar.buttons[i]
        if rec then
            SecureHandlerSetFrameRef(control, "button" .. i, rec.button)
            local want = "cap"
            if i <= count then
                want = "show"
                if index == 12 and not showEmpty and not PetHasAction(i) then want = "idle" end
            end
            control:SetAttribute("want" .. i, want)
            if index == 12 then
                control:SetAttribute("grid" .. i, i <= count and showEmpty)
            else
                control:SetAttribute("grid" .. i, nil)
            end
        else
            -- The snippet walks references until the first gap.
            control:SetAttribute("frameref-button" .. i, nil)
        end
    end
    SecureHandlerExecute(control, ADOPT)
    return true
end

-- Opens Blizzard's Quick Keybind mode through the restricted environment.
-- Its OnShow reveals every Blizzard grid; run insecurely it would taint
-- MainActionBar's grid state and block a later combat Show.
local OPEN_QUICK_KEYBIND = [[
local frame=self:GetFrameRef("quickkeybind")
if frame then frame:Show() end
]]
function S.OpenQuickKeybind()
    local frame = AB.Frame("QuickKeybindFrame")
    if not frame or NS.IsCombatLocked() then return false end
    local control = AB.control
    if not control then
        control = S.CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
        AB.control = control
    end
    SecureHandlerSetFrameRef(control, "quickkeybind", frame)
    SecureHandlerExecute(control, OPEN_QUICK_KEYBIND)
    return true
end
