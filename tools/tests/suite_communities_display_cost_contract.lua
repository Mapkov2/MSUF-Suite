-- SetDisplayMode changes visibility of named panes already created by the XML.
-- A display transition skins those panes and retains one bounded discovery budget.
local root = assert(arg[1])
local function Ignore() end
local function False() return false end
local function Frame(name)
    return { name = name, IsForbidden = False, IsProtected = False }
end
securecallfunction = function(fn, ...) return fn(...) end
CommunitiesFrameMixin = { Event = { DisplayModeChanged = "DisplayModeChanged", ClubSelected = "ClubSelected" } }
do
    local combat, pending, queues, selections = false, {}, 0, 0
    local ns = {
        IsCombatLocked = function() return combat end,
        CombatGate = {
            RunOrDefer = function(key, callback) pending[key] = callback; queues = queues + 1 end,
            Cancel = function(key) pending[key] = nil end,
        },
        Cosmetics = { RestoreOwner = Ignore, Fade = Ignore }, ControlSkin = { DisableOwner = Ignore },
        Surface = { SetActive = function() selections = selections + 1 end }, Checkmarks = {},
    }
    assert(loadfile(root .. "/MSUF_Suite/Appearance/Safety.lua"))("Suite", ns)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/AdapterKit.lua"))("Skin", ns)
    local frame = Frame("CommunitiesFrame")
    local skin = assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/Communities.lua"))("Skin", ns)
    local shown, jobs, mode = true, {}, { "MemberList", "Chat", "GuildFinderFrame" }
    local registrations, current, visibilityReads, hooks = {}, nil, 0, 0
    function frame:IsVisible() visibilityReads = visibilityReads + 1; return shown end
    function frame:GetDisplayMode() return current end
    function frame:HookScript(script, callback)
        assert(not combat, "hooked Communities during combat")
        hooks = hooks + 1
        jobs[script] = callback
    end
    function frame:RegisterCallback(event, fn, owner) registrations[event] = { fn, owner } end
    function frame:UnregisterCallback(event) registrations[event] = nil end
    local function Display(value)
        current = value
        local reg = assert(registrations.DisplayModeChanged)
        reg[1](reg[2], value)
    end
    local function Hide()
        shown = false
        jobs.OnHide(frame)
    end
    local function Show()
        shown = true
        jobs.OnShow(frame)
    end
    local function EndCombat()
        combat = false
        local key, callback = next(pending)
        assert(key and callback and next(pending, key) == nil, "expected a single combat wake")
        pending[key] = nil
        callback()
    end
    local walks, painted = {}, {}
    ns.AdapterKit.Attach = function(state, target, spec)
        if target then painted[target] = true end
        return target ~= nil
    end
    ns.AdapterKit.HideSurfaces = Ignore
    ns.AdapterKit.SkinControl = function(state, target) return target ~= nil end
    local function Pane(name, visible)
        local pane = Frame(name)
        pane.shown = visible
        function pane:IsShown() return self.shown end
        frame[name] = pane
        return pane
    end
    local member, chat, finder = Pane("MemberList", true), Pane("Chat", true), Pane("GuildFinderFrame", false)
    frame.InviteButton = Frame("InviteButton")
    frame.InviteButton.Selection = Frame("Selection")
    ns.Checkmarks.TrackControlTree = function(target, owner, options)
        walks[#walks + 1] = { target, options.maxNodes, owner }
        return true, math.min(target == member and 600 or 150, options.maxNodes)
    end
    -- A pooled roster row can return with the same art, with Blizzard's
    -- alpha restored, or with a new normal texture after template reuse.
    assert(loadfile(root .. "/MSUF_Suite/Appearance/Cosmetics.lua"))("Suite", ns)
    ScrollBoxListMixin = { Event = { OnInitializedFrame = "OnInitializedFrame" } }
    local row, box, callback, receiver = Frame("RosterRow"), Frame("RosterBox")
    local function Texture()
        local tex = Frame("RosterBG")
        tex.alpha, tex.writes = .75, 0
        function tex:GetAlpha() return self.alpha end
        function tex:SetAlpha(alpha) self.alpha, self.writes = alpha, self.writes + 1 end
        return tex
    end
    local original = Texture()
    row.normal, member.ScrollBox = original, box
    function row:GetNormalTexture() return self.normal end
    function box:RegisterCallback(_, fn, owner) callback, receiver = fn, owner end
    function box:ForEachFrame(fn) fn(row) end
    function box:UnregisterCallback() end
    assert(skin.Apply(frame, "guild"))
    assert(original.writes == 1 and callback, "initial roster skin did not fade the native background")
    for i = 1, 20 do callback(receiver, row) end
    assert(original.writes == 1, "stable pooled roster data repainted the same normal texture")
    original.alpha = .5
    callback(receiver, row)
    assert(original.alpha == 0 and original.writes == 2, "native roster alpha reset was not repaired")
    row.normal = Texture()
    callback(receiver, row)
    assert(row.normal.alpha == 0 and row.normal.writes == 1, "replacement roster texture missed first paint")
    assert(walks[1][1] == frame and painted[member], "initial static controls were skipped")
    assert(hooks == 2 and jobs.OnHide and jobs.OnShow, "visibility was not bound during the out-of-combat apply")
    walks, painted = {}, {}
    Display(mode)
    assert(#walks == 2 and walks[1][1] == member and walks[2][1] == chat,
        "display transition rescanned the root or an unrelated/hidden pane")
    assert(walks[1][2] == 719 and walks[2][2] == 119, "visible panes each reset the node budget")
    assert(painted[member] and not painted[frame], "display change repainted the whole shell")
    walks = {}
    Display(nil)
    assert(#walks == 1 and walks[1][1] == frame, "client without a mode payload lost its fallback")
    member.shown, finder.shown = false, true
    local replacement = Pane("GuildFinderFrame", true)
    walks = {}
    Display({ "GuildFinderFrame" })
    assert(#walks == 1 and walks[1][1] == replacement, "a replaced native pane retained the old skin target")
    Hide()
    walks = {}
    combat = true
    local readsBefore, selectionsBefore = visibilityReads, selections
    Display(mode)
    skin:OnClubSelected()
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 250 do
        Display(mode)
        skin:OnClubSelected()
    end
    local after = collectgarbage("count")
    collectgarbage("restart")
    assert(after == before, "repeated closed-window notifications allocated Lua heap")
    Display({ "GuildFinderFrame" })
    skin:OnClubSelected()
    assert(#walks == 0 and queues == 0 and visibilityReads == readsBefore and selections == selectionsBefore
        and hooks == 2, "hidden combat events requested work, read visibility or painted selection")
    combat = false
    Show()
    assert(#walks == 1 and walks[1][1] == replacement, "reopen lost or duplicated the latest display update")
    assert(selections == selectionsBefore + 1, "combined display/selection refreshed the selection twice")
    walks = {}
    Hide()
    Display(mode)
    combat = true
    Show()
    Display({ "GuildFinderFrame" })
    skin:OnClubSelected()
    assert(#walks == 0 and queues == 1, "combat reopen touched a protected pane or requested repeated work")
    EndCombat()
    assert(#walks == 1 and walks[1][1] == replacement, "combat recovery missed the current native pane")
    combat = true
    skin:OnClubSelected()
    Hide()
    assert(next(pending) == nil, "closing Communities left a combat wake queued")
    combat = false
    Show()
    local blocked = false
    function frame:IsForbidden() return blocked end
    walks, blocked = {}, true
    Display(mode)
    assert(#walks == 0, "forbidden window received a display pass")
    blocked = false
    Hide()
    Display(mode)
    assert(skin.Disable(frame, "guild"))
    walks = {}
    Show()
    assert(#walks == 0, "released Communities owner repainted a delayed display")
    assert(next(registrations) == nil, "released Communities callback stayed registered")
    print("Communities display: cold apply, scoped panes, replacement, hidden, combat, forbidden and release passed")
end
