-- Open unprotected windows keep their geometry in combat; closed windows stay cold.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_window_controls_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))', 1, true))
local fixture = source:sub(1, stop - 1) .. [[
return { NS = NS, Frame = Frame, frames = createdFrames, jobs = combatJobs, NextFrame = NextFrame }
]]
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    _G.combat, _G.combatEdge = false, false
    local H = assert(loadstring(fixture, "@window_controls_combat_fixture"))()
    local NS, Frame = H.NS, H.Frame
    NS.Client.isForever = flavor == "Forever"
    NS.DB.theme = { look = "midnight" }
    local nativeWindows = {}
    UpdateScaleForFitForOpenPanels = function()
        for _, frame in ipairs(nativeWindows) do
            if frame.shown then frame.scale = 1 end -- native secure fit
        end
    end
    hooksecurefunc = function(name, callback, post)
        if type(name) == "table" then
            local native = name[callback]
            name[callback] = function(...) native(...) post(...) end
            return
        end
        local native = assert(_G[name])
        _G[name] = function(...) native(...); callback(...) end
    end
    assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))("MSUF_Suite_Skin", NS)
    local W = NS.WindowControls
    local panel = Frame("CharacterFrame", UIParent)
    nativeWindows[#nativeWindows + 1] = panel
    NS.DB.windowControls.scales.CharacterFrame = 0.8
    NS.DB.windowControls.positions.CharacterFrame = { x = 300, y = -90 }
    _G.combatEdge = true -- PLAYER_REGEN_DISABLED before native lockdown changes
    Check(W.Attach(panel, "combat"), flavor .. " cold combat window has no controls")
    local state = W.states[panel]
    Check(panel.scale == 0.8 and state.grip.shown, "combat attach lost stored scale or grip")
    local created = #H.frames
    local grip = state.grip
    cursorX, cursorY = 500, 500
    grip.scripts.OnMouseDown(grip, "LeftButton")
    cursorX, cursorY = 620, 440
    Check(grip.scripts.OnUpdate ~= nil, "safe combat grip cannot start a drag")
    grip.scripts.OnUpdate(grip)
    grip.scripts.OnMouseUp(grip)
    Check(panel.scale > 0.8 and NS.DB.windowControls.scales.CharacterFrame == panel.scale,
        "safe combat drag did not scale and persist")
    Check(grip.scripts.OnUpdate == nil and state.drag == nil, "released combat drag kept an updater")
    local saved = panel.scale
    _G.combatEdge, _G.combat = false, true
    panel:Hide()
    panel.scale = 1
    panel:Show()
    Check(panel.scale == saved and panel.point[4] == 300 / saved,
        "combat native reopen changed a static saved scale/position")
    UpdateScaleForFitForOpenPanels()
    Check(panel.scale == saved, "combat native fit replaced the selected scale")
    UpdateUIPanelPositions(panel)
    Check(panel.point[4] == 300 / saved, "combat native reflow replaced the selected position")
    -- Blizzard also repairs a slot directly and positions an incoming panel
    -- before Show. A locked title must never delay its plain root until regen.
    local title = state.titleDrag
    local protection = title.IsProtected
    title.IsProtected = function() return true, false end
    panel:Hide()
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 25, -35)
    panel:Show()
    Check(panel.point[4] == 300 / saved and panel.point[5] == -90 / saved,
        "combat reopen with a protected title lost the saved placement")
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 55, -110)
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 990, -135)
    H.NextFrame()
    Check(panel.point[4] == 300 / saved and panel.point[5] == -90 / saved,
        "private native slot changes displaced an already visible panel")
    _G.combat = false
    title.IsProtected = protection
    for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -90)
    H.NextFrame()
    Check(panel.point[4] == 300 / saved and panel.point[5] == -90 / saved, "combat-end native layout displaced the panel")
    _G.combat = true
    Check(next(H.jobs) == nil, "safe native refresh created post-combat work")
    -- Returning to native panel-manager positioning uses the protected delegate;
    -- unlike a direct safe-root anchor, it must wait and honor newer settings.
    local nativePositions = UpdateUIPanelPositions
    UpdateUIPanelPositions = function(...)
        Check(not NS.IsCombatLocked(), "skin drove the protected panel manager in combat")
        return nativePositions(...)
    end
    NS.DB.windowControls.positions.CharacterFrame = nil
    W.Refresh()
    Check(next(H.jobs) ~= nil, "native position reset lost its protected continuation")
    NS.DB.windowControls.positions.CharacterFrame = { x = 300, y = -90 }
    W.Refresh()
    _G.combat = false
    for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
    Check(panel.point[4] == 300 / saved, "stale native reset overrode newer position settings")
    UpdateUIPanelPositions = nativePositions
    _G.combat = true
    state.titleDrag.scripts.OnDragStart(state.titleDrag)
    Check(not panel.moving, "a combat title drag moved a placed window")
    state.titleDrag.scripts.OnDragStop(state.titleDrag)
    Check(NS.DB.windowControls.positions.CharacterFrame.x == 300 and next(H.jobs) == nil, "locked drag changed the saved position")
    grip.scripts.OnMouseDown(grip, "LeftButton")
    panel:Hide()
    Check(state.drag == nil and grip.scripts.OnUpdate == nil, "root hide retained a drag updater")
    panel:Show()
    Check(#H.frames == created and grip.scripts.OnUpdate == nil, "warm combat reopen created controls or an updater")
    _G.combat = false
    cursorX, cursorY = 500, 500
    grip.scripts.OnMouseDown(grip, "LeftButton")
    _G.combatEdge = true
    cursorX, cursorY = 560, 470
    grip.scripts.OnUpdate(grip)
    Check(state.drag ~= nil and panel.scale ~= saved, "combat edge stopped an unprotected drag")
    grip.scripts.OnMouseUp(grip)
    _G.combatEdge = false

    -- The first visible header after a combat reload can have no controls
    -- yet. Safe fit is independent of the native panel visibility lock.
    -- A managed window minimizes only through Blizzard's X while its native
    -- opener can bring it back (CollectionsMicroButton, ToggleCollectionsJournal).
    local settingsPanel = UIPanelWindows.SettingsPanel
    local collectionsPanel = UIPanelWindows.CollectionsJournal
    UIPanelWindows.CollectionsJournal = { area = "left" }
    local findByFrame = NS.BlizzardCatalog.FindByFrame
    NS.BlizzardCatalog.FindByFrame = function(name)
        if name == "CollectionsJournal" then return { category = "collections" } end
        return findByFrame(name)
    end
    CollectionsMicroButton = Frame("CollectionsMicroButton", UIParent, "Button")
    function CollectionsMicroButton:IsEnabled() return true end
    local caption = Frame("CollectionsJournal", UIParent)
    local close = Frame(nil, caption, "Button")
    close.anchorName, close.left, close.top, close.height = "TOPRIGHT", 668, 803, 26
    function close:GetEffectiveScale() return caption:GetEffectiveScale() end
    caption.CloseButton = close
    local nativeClose = function() caption:Hide() end
    close.scripts.OnClick = nativeClose
    _G.combat = true
    Check(W.Attach(caption, "reload-caption"), "safe cold header refused to attach")
    local header = W.states[caption]
    Check(header.maximize and header.maximize.shown and header.minimize.shown,
        "cold combat header lost its minimize/maximize caption")
    header.maximize.scripts.OnClick(header.maximize)
    Check(header.fit and caption.point[1] == "CENTER", "safe maximize was refused during combat")
    header.maximize.scripts.OnClick(header.maximize)
    Check(not header.fit, "safe fit could not restore during combat")
    header.minimize.scripts.OnClick(header.minimize)
    Check(caption.shown and not header.restore.shown and header.minimize.mouseEnabled == false,
        "combat minimize bypassed the native panel manager or retained mouse input")
    Check(close.scripts.OnClick == nativeClose and next(H.jobs) == "windowControls:captions",
        "cold header changed native close or lost its combat-end caption refresh")
    _G.combat = false
    for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
    Check(header.minimize.mouseEnabled == true, "combat-end refresh did not re-enable minimize input")
    header.minimize.scripts.OnClick(header.minimize)
    Check(caption.shown and not header.restore.shown and not header.minimized,
        "the skin's own minimize hid a managed window after combat")
    close.scripts.OnClick(close)
    Check(not caption.shown and not header.restore.shown, "the header lost its native close")
    W.DisableOwner("reload-caption")
    NS.BlizzardCatalog.FindByFrame, UIPanelWindows.CollectionsJournal = findByFrame, collectionsPanel

    local standalone = Frame("SettingsPanel", UIParent)
    UIPanelWindows.SettingsPanel = nil
    standalone.ClosePanelButton = Frame(nil, standalone, "Button")
    _G.combat = true
    Check(W.Attach(standalone, "standalone-caption"), "safe standalone cold window did not attach")
    local standaloneHeader = W.states[standalone]
    standaloneHeader.minimize.scripts.OnClick(standaloneHeader.minimize)
    Check(not standalone.shown and standaloneHeader.restore.shown, "safe standalone minimize was refused")
    standaloneHeader.restore.scripts.OnClick(standaloneHeader.restore, "LeftButton")
    Check(standalone.shown and not standaloneHeader.restore.shown, "safe standalone restore was refused")
    function standalone:GetAttribute(key)
        if key == "UIPanelLayout-area" then return "center" end
    end
    standaloneHeader.minimize.scripts.OnClick(standaloneHeader.minimize)
    Check(standalone.shown and not standaloneHeader.restore.shown, "late native panel attributes bypassed lockdown")
    standalone:Hide()
    _G.combat = false
    UIPanelWindows.SettingsPanel = settingsPanel
    W.DisableOwner("standalone-caption")

    -- Forbidden targets expose no getters: stopping our own transient updater
    -- must not read the native root or touch its button state.
    grip.scripts.OnMouseDown(grip, "LeftButton")
    local getScale = panel.GetScale
    panel.IsForbidden = function() return true end
    panel.GetScale = function() error("forbidden window scale read") end
    grip.scripts.OnUpdate(grip)
    Check(state.drag == nil and grip.scripts.OnUpdate == nil, "forbidden root retained an updater")
    panel.IsForbidden = function() return false end
    panel.GetScale = getScale

    -- A safe map root can retain children parented to an implicitly protected
    -- native border from its earlier OOC attach. Their visibility is guarded.
    UIPanelWindows.WorldMapFrame = { area = "left", pushable = 0 }
    local map = Frame("WorldMapFrame", UIParent)
    map.BorderFrame = Frame(nil, map)
    map.BorderFrame.protected = true
    W.Attach(map, "combat-map")
    local mapControls = assert(W.states[map])
    Check(mapControls.grip.parent == map.BorderFrame, "OOC map lost its native border strata")
    local mapGrip = mapControls.grip
    mapGrip.IsProtected = function() return map.BorderFrame:IsProtected() end
    local mapShow, mapHide = mapGrip.Show, mapGrip.Hide
    mapGrip.Show = function(self)
        Check(not NS.IsCombatLocked(), "protected map grip shown in combat"); mapShow(self)
    end
    mapGrip.Hide = function(self)
        Check(not NS.IsCombatLocked(), "protected map grip hidden in combat"); mapHide(self)
    end
    local recolor = NS.WindowControlChrome.RecolorGrip
    NS.WindowControlChrome.RecolorGrip = function(target)
        Check(not NS.IsCombatLocked() or not target:IsProtected(), "protected map grip recolored in combat")
        return recolor(target)
    end
    _G.combatEdge = true
    NS.DB.windowControls.positions.WorldMapFrame = { x = 410, y = -140 }
    map:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -24)
    NS.WindowControls:OnThemeChanged("color"); H.NextFrame()
    map:Hide(); map:Show(); W.Refresh()
    H.NextFrame()
    Check(map.point[4] == 410 and map.point[5] == -140, "protected title/grip blocked safe root placement in combat")
    W.Attach(map, "combat-map")
    mapGrip.scripts.OnMouseDown(mapGrip, "LeftButton")
    Check(mapGrip.scripts.OnUpdate == nil, "protected map grip started combat drag")
    W.DisableOwner("combat-map")
    local coldMap = Frame("WorldMapFrame", UIParent)
    coldMap.BorderFrame = Frame(nil, coldMap)
    coldMap.BorderFrame.protected = true
    W.Attach(coldMap, "cold-map")
    Check(W.states[coldMap].grip.parent == coldMap, "cold combat grip inherited a protected map border")
    coldMap:Hide()
    _G.combatEdge = false
    for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
    map:Hide()
    NS.DB.windowControls.positions.WorldMapFrame = nil
    NS.WindowControlChrome.RecolorGrip = recolor

    -- The Forever map can be unprotected while its native dungeon overlay is
    -- rebuilding during a boss encounter. Leave its automatic geometry to Blizzard.
    local dungeonMap = Frame("WorldMapFrame", UIParent)
    nativeWindows[#nativeWindows + 1] = dungeonMap
    NS.DB.windowControls.scales.WorldMapFrame = 1.22
    NS.DB.windowControls.positions.WorldMapFrame = { x = 300, y = -90 }
    _G.combatEdge = true
    Check(W.Attach(dungeonMap, "dungeon-map"), "combat map attach lost its controls")
    if NS.Client.isForever then
        Check(dungeonMap.geometryWrites == nil, "Forever combat attach wrote map geometry")
        dungeonMap:Hide()
        dungeonMap:Show()
        UpdateScaleForFitForOpenPanels()
        Check(dungeonMap.geometryWrites == nil, "Forever combat reopen or fit wrote map geometry")
        UpdateUIPanelPositions(dungeonMap)
        Check(dungeonMap.geometryWrites == 1 and dungeonMap.point[4] == 30,
            "Forever changed the map inside Blizzard's combat layout stack")
        H.NextFrame()
        Check(dungeonMap.point[4] * dungeonMap.scale == 300 and dungeonMap.point[5] * dungeonMap.scale == -90
            and dungeonMap.scale == 1, "Forever left the map at the native slot until combat ended")
        Check(next(H.jobs) == "windowControls:show:WorldMapFrame", "combat map replay was not queued")
        _G.combatEdge = false
        for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
        Check(dungeonMap.scale == 1.22 and dungeonMap.point[4] == 300 / 1.22,
            "combat end lost the saved map scale or position")
    else
        Check(dungeonMap.scale == 1.22 and dungeonMap.point[4] == 300 / 1.22,
            "Retail lost its immediate map placement in combat")
    end
    _G.combatEdge = false
    dungeonMap:Hide()

    if NS.Client.isForever then
        local previousMail, previousPanel = MailFrame, UIPanelWindows.MailFrame
        local previousFind, previousQueue = NS.BlizzardCatalog.FindByFrame, NS.Registry.QueueJob
        MailFrame = Frame("MailFrame", UIParent)
        UIPanelWindows.MailFrame = { area = "left" }
        NS.BlizzardCatalog.FindByFrame = function(name)
            if name == "MailFrame" then return { category = "social" } end
            return previousFind(name)
        end
        NS.Registry.QueueJob = function(job)
            if NS.IsCombatLocked() then NS.CombatGate.RunOrDefer(tostring(job), job) else previousQueue(job) end
        end
        NS.DB.windowControls.positions.MailFrame = { x = 390, y = -145 }
        MailFrame:Hide()
        Check(W.Attach(MailFrame, "placed-mail"), "cannot prepare mailbox")
        _G.combat = true
        UpdateUIPanelPositions(MailFrame)
        MailFrame:Show()
        Check(MailFrame.point[4] == 30, "mailbox was repositioned during its native opening stack")
        H.NextFrame()
        Check(MailFrame.point[4] == 390 and MailFrame.point[5] == -145, "mailbox waited for combat end to take its saved position")
        MailFrame:Hide()
        _G.combat = false
        for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
        W.DisableOwner("placed-mail")
        NS.BlizzardCatalog.FindByFrame, NS.Registry.QueueJob = previousFind, previousQueue
        MailFrame, UIPanelWindows.MailFrame = previousMail, previousPanel
    end

    -- The reviewed implicit spellbook exception remains out-of-combat only.
    local protected = Frame("PlayerSpellsFrame", UIParent)
    PlayerSpellsFrame = protected
    protected.protected = true
    do
        local nativeInsets = { -4, 7, 3, -2 }
        protected.insets = nativeInsets
        function protected:GetClampRectInsets() return unpack(self.insets) end
        function protected:IsClampedToScreen() return self.clamped == true end
        function protected:SetClampRectInsets(...)
            Check(not NS.IsCombatLocked(), "protected clamp changed in combat")
            self.insets = { ... }
        end
        local function DisplayedPosition(frame, nativeX, nativeY)
            if not frame:IsClampedToScreen() then return nativeX, nativeY end
            local l, r, t, b = frame:GetClampRectInsets()
            local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
            return math.max(-l * scale, math.min(nativeX, UIParent.width - (frame.width + r) * scale)),
                math.min(-t * scale, math.max(nativeY, (frame.height - b) * scale - UIParent.height))
        end
        NS.DB.windowControls.positions.PlayerSpellsFrame = { x = 520, y = -176 }
        NS.DB.windowControls.scales.PlayerSpellsFrame = 0.9
        Check(W.Attach(protected, "combat"), flavor .. " spellbook lost its reviewed OOC exception")
        local controls = W.states[protected]
        -- A native protected parent also protects its geometry children. Clearing
        -- our own updater is allowed; button/visibility writes must stay out.
        controls.grip.IsProtected = function() return protected:IsProtected() end
        controls.grip.IsMouseOver = function() return true end
        controls.grip.SetButtonState = function()
            Check(not NS.IsCombatLocked(), "protected grip button state changed in combat")
        end
        for _, control in ipairs({ controls.grip, controls.titleDrag }) do
            local hide = control.Hide
            control.Hide = function(self)
                Check(not NS.IsCombatLocked(), "protected child hidden in combat")
                hide(self)
            end
        end
        controls.grip.scripts.OnMouseDown(controls.grip, "LeftButton")
        local writes = protected.geometryWrites
        _G.combatEdge = true
        controls.grip.scripts.OnUpdate(controls.grip)
        Check(protected.geometryWrites == writes and not controls.grip.scripts.OnUpdate,
            "implicit spellbook geometry changed at combat edge")
        Check(not W.Attach(protected, "combat"), "protected combat reattach unexpectedly succeeded")
        for _, pos in ipairs({ { 30, -90 }, { 950, -360 } }) do
            local x, y = DisplayedPosition(protected, pos[1], pos[2])
            Check(math.abs(x - 520) < 0.001 and math.abs(y + 176) < 0.001,
                "native combat reflow displaced the already placed protected book")
        end
        protected.scale = 1 -- native fit can still reset its own protected panel
        protected:Hide()
        protected:Show()
        W.Refresh()
        Check(protected.geometryWrites == writes and next(H.jobs) ~= nil,
            "protected reopen wrote geometry or lost its bounded continuation")
        protected:Hide()
        _G.combatEdge = false
        for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
        Check(protected.geometryWrites == writes, "combat completion painted a closed protected window")
        protected:Show()
        Check(protected.scale == 0.9, "protected window lost safe recovery after combat")
        protected:Hide()
        Check(W.SetEnabled(false), "cannot release hidden position clamps")
        local left, right, top, bottom = protected:GetClampRectInsets()
        Check(not protected:IsClampedToScreen() and left == -4 and right == 7 and top == 3 and bottom == -2,
            "disabling controls did not return the hidden book's original clamp")
        W.SetEnabled(true)
        Check(protected:IsClampedToScreen(), "re-enabling the skin left a hidden protected book unprepared")
        NS.DB.windowControls.positions.PlayerSpellsFrame = nil
        W:OnThemeChanged("profile"); H.NextFrame()
        Check(not protected:IsClampedToScreen(), "a new profile retained the hidden book's old placement")
        NS.DB.windowControls.positions.PlayerSpellsFrame = { x = 250, y = -130 }
        W:OnThemeChanged("profile"); H.NextFrame()
        local x, y = DisplayedPosition(protected, 30, -90)
        Check(math.abs(x - 250) < 0.001 and math.abs(y + 130) < 0.001,
            "a profile assigning the hidden book a new position left its native slot active")
        local bag = Frame("ContainerFrame1", UIParent)
        _G.ContainerFrame1 = bag
        bag.protected, bag.clamped, bag.insets = true, true, { -1, 2, 3, -4 }
        bag.IsClampedToScreen, bag.GetClampRectInsets = protected.IsClampedToScreen, protected.GetClampRectInsets
        bag.SetClampRectInsets = protected.SetClampRectInsets
        function bag:GetEffectiveScale() return 0.85 * self.scale end
        NS.DB.windowControls.positions.ContainerFrame1 = { x = 470, y = -190 }
        Check(W.Attach(bag, "bag-position"), "could not prepare protected inventory placement")
        bag:Hide()
        local writes = bag.geometryWrites
        _G.combat = true
        bag.point = { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -15, 15 }
        bag:Show()
        local bagX, bagY = DisplayedPosition(bag, 1370, -655)
        Check(math.abs(bagX - 470) < 0.001 and math.abs(bagY + 190) < 0.001 and bag.geometryWrites == writes,
            "native bag anchor displaced a previously placed bag at its parent scale")
        _G.combat = false
        for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
        W.DisableOwner("bag-position")
        left, right, top, bottom = bag:GetClampRectInsets()
        Check(bag:IsClampedToScreen() and left == -1 and right == 2 and top == 3 and bottom == -4,
            "inventory release lost its original enabled native bounds")
        bag:Hide()
        _G.ContainerFrame1 = nil
    end
    local explicit = Frame("CharacterFrame", UIParent)
    explicit.protected, explicit.explicitProtected = true, true
    Check(not W.Attach(explicit, "combat"), "explicitly protected window gained controls")

    -- The native callbacks may run for other UI. They must not visit closed
    -- windows, repaint them, allocate per-window jobs or leave updates running.
    panel:Hide()
    local hiddenReads = 0
    for index = 1, 64 do
        local hidden = Frame("CharacterFrame", UIParent)
        W.Attach(hidden, "hidden")
        hidden:Hide()
        function hidden:IsShown() hiddenReads = hiddenReads + 1; return false end
        function hidden:GetScale() hiddenReads = hiddenReads + 1; return self.scale end
        function hidden:SetScale() error("closed window rescaled") end
        function hidden:SetPoint() error("closed window repositioned") end
    end
    local paints = 0
    NS.Theme.GetColor = function() paints = paints + 1; return 1, 1, 1, 1 end
    NS.WindowControls:OnThemeChanged("color")
    H.NextFrame()
    Check(paints == 0, "closed window controls repainted on a palette notification")
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 1000 do UpdateUIPanelPositions(); W.Refresh() end
    local growth = collectgarbage("count") - before
    collectgarbage("restart")
    Check(hiddenReads == 0 and growth < 1,
        "closed windows did work: " .. hiddenReads .. " reads, " .. growth .. " KiB")
    for _, frame in ipairs(H.frames) do
        Check(frame.scripts.OnUpdate == nil, "closed controls retained an updater")
    end
    Check(next(H.jobs) == nil, "closed callbacks accumulated combat jobs")
end
print("Window controls combat parity: " .. checks .. " checks passed")
