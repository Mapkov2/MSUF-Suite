local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Lifecycle (spec 8.1), the preview mode and the exports that use controller
-- state. The work itself is split along its seams, each file loading before
-- this one:
--  Flush.lua     one dirty mask with a prebuilt next-frame flush
--  Settings.lua  the settings reader and the first-run capture
--  Events.lua    the event map, spec detection, the assisted-combat source
--                and the combat edges
-- The movers and the exports for the options page and MSUF are in Exports.lua.
--
-- Refresh runs on every setting change (slider ticks included). It reads the
-- flat settings into per-bar views in place, bumps the generation of each
-- group that changed and marks only the work that setting needs; the flush
-- then runs it in dependency order.
local M = C.M
local ID = "cooldownManager"
local type = type
local wipe = C.wipe
local Dispatch = S.Dispatch
local Flush, Settings, Events = C.Flush, C.Settings, C.Events
local dirty = Flush.dirty
local Schedule, Pending, ResetDirty, ForgetPlans = Flush.Schedule, Flush.Pending, Flush.Reset, Flush.Forget
local ReadGlobals, ReadViews, DecodeData = Settings.ReadGlobals, Settings.ReadViews, Settings.DecodeData
local UpdateSpec = Events.UpdateSpec
local first, optionsPreview = true, false

------------------------------------------------------------------ preview mode
local function PreviewChanged()
    dirty.resolve, dirty.cooldowns, dirty.effects, dirty.layout, dirty.visibility = true, true, true, true, true
    -- All glows only in combat leaves aura glows on in the preview: the aura
    -- buttons take that through a structural sync of every bar.
    if C.state.allGlowsCombat then
        local slots = NS.CDM.SLOTS
        for i = 1, #slots do Flush.sync[slots[i].key] = true end
    end
    Schedule()
end
-- MSUF Edit Mode wins over the options page; both suspend the bar rules.
local function ApplyPreview()
    local mode = (S.editMode == true and "edit") or (optionsPreview and "options") or nil
    if C.Preview.SetMode(mode) then PreviewChanged() end
end

------------------------------------------------------------------ lifecycle (spec 8.1)
function M:Enable()
    Events.EnterWorld()
    C.Layout.InvalidateScale()
    C.Resolve.SpellsChanged()
    first = true
    Settings.BeginCapture(self.config)
    self.context:Callback("CooldownViewerSettings.OnPendingChanges", Events.OnLayoutChanged)
    self.context:Callback("CooldownViewerSettings.OnHide", Events.OnLayoutChanged)
    -- The suite action bars started, stopped or changed their form pages:
    -- the key texts they answered are stale.
    self.context:Callback("MSUFSuite.ActionBars.BindingsChanged", Events.OnActionBars)
    -- The suite action bars paged bar 1 themselves (target or modifier
    -- paging): glows on its buttons may describe the previous page.
    self.context:Callback("MSUFSuite.ActionBars.ActionsChanged", Events.OnActionPage)
    self.context:Callback("AssistedCombatManager.OnSetUseAssistedHighlight", Events.OnAssistPolicyChanged)
    self:Refresh()
end

function M:Refresh()
    local config = self.config
    local all = first
    first = false
    local text = ReadGlobals(config, all)
    ReadViews(config, all, text)
    DecodeData(config)
    if all then dirty.catalog, dirty.resolve, dirty.layout, dirty.visibility, dirty.events, dirty.keybinds = true, true, true, true, true, true end
    C.PressBridge()
    ApplyPreview()
    C.Effects.Recommendation()
    if not Settings.CaptureWaiting() then
        C.Native.Apply()
        Settings.SyncViewerOffset()
    end
    if S.editMode then
        C.Layout.ForgetAnchors()
        dirty.layout = true
    end
    Events.CoreEvents()
    if Pending() then Schedule() end
end

-- The next activation starts from a clean slate.
local function ForgetState()
    wipe(C.plans)
    wipe(C.entries)
    wipe(C.Layout.dirty)
    ForgetPlans()
    C.Index.Rebuild()
    ResetDirty()
end

-- The options page's preview request outlives a disable: the page turns it
-- off when it closes, and a re-enable while it is open applies it again.
-- Each release step runs isolated (Dispatch), as Context:Release does: one
-- that raises is reported and every later step still runs.
function M:Disable()
    Dispatch(C.PressBridge)
    Dispatch(C.Preview.SetMode, nil)
    Dispatch(C.Preview.ReleaseAll)
    Dispatch(Settings.ForgetCapture)
    Dispatch(C.Alerts.ReleaseAll)
    Dispatch(C.Auras.ReleaseAll)
    Dispatch(C.ActionGlows.Release)
    Dispatch(C.Effects.ReleaseAll)
    Dispatch(C.Icons.ReleaseAll)
    Dispatch(C.Layout.HideAll)
    Dispatch(C.Visibility.ReleaseAll)
    Dispatch(C.Native.Release)
    Dispatch(C.Keybinds.Clear)
    Dispatch(Events.Release, self.context)
    Dispatch(ForgetState)
    first = true
end

------------------------------------------------------------------ exports that use controller state
-- The spec export is in Events.lua, the other exports (options page, MSUF)
-- are in Exports.lua.

-- A loaded but inactive module answers from a cold snapshot of the saved
-- settings; nothing is flushed while it is off. No catalog events run then,
-- so the Blizzard snapshot is rebuilt whenever the specialization moved.
function C.Cold()
    if M.active then return end
    local config = S.Config(ID)
    if type(config) ~= "table" then return end
    ReadGlobals(config, false)
    ReadViews(config, false, false)
    DecodeData(config)
    UpdateSpec()
    local catalog = C.Catalog
    if catalog.generation == 0 or catalog.specTag ~= C.state.specTag then catalog.Rebuild() end
    ResetDirty()
end

-- The options page keeps every bar visible while it is open. A request made
-- while the module is off is kept and applies once it is enabled; the
-- result says whether the preview runs now.
function S.CooldownManagerSetPreview(on)
    on = on == true
    if on and NS.IsCombatLocked() then return false end
    if optionsPreview ~= on then
        optionsPreview = on
        if M.active then ApplyPreview() end
    end
    return M.active == true or not on
end

S.Install(ID, M)
