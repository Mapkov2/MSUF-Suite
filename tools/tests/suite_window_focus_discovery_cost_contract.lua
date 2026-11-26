-- One contour discovery reads each root-invariant source once, not once per node.
-- Capture 13 (build 68f773e6df5a537b): Shown -> Promote -> Reconcile -> Chrome.Update
-- -> Discover -> Inspect -> Safety.Read/Call, 3226 Inspect calls / 3073 ms inclusive.
local root = assert(arg[1])
local file = assert(io.open(root .. "/tools/tests/suite_window_focus_contract.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local stop = assert(source:find('    local a = Native("CharacterFrame"', 1, true))
local body = [======[
    Load("Adapters/CatalogGlass.lua")
    local character = Native("CharacterFrame", 180, 100, 400, 500)
    W.TrackFocus(character, "cost")
    local professions = Native("ProfessionsFrame", 600, 200, 700, 658)
    W.TrackFocus(professions, "cost")
    local scans, made = 0, 0
    local reads, aggregate = 0, 0
    local function Scalar(n) return function() reads = reads + 1; return n end end
    local single = { GetLeft = Scalar(10), GetBottom = Scalar(20), GetWidth = Scalar(30), GetHeight = Scalar(40),
        GetEffectiveScale = function() return 1 end,
        GetRect = function() aggregate = aggregate + 1; return 10, 20, 30, 40 end }
    local measured = {}
    for i = 1, 100 do Check(NS.WindowFocusGeometry.Read(single, measured), "lost a readable native rect") end
    print(("100 focus measurements: %d scalar reads, %d GetRect"):format(reads, aggregate))
    Check(aggregate == 100 and reads == 0 and measured.width == 30 and measured.bottom == 20,
        "each public geometry observation must use exactly one rectangle reading")
    single.GetRect = function() return 10, 20, { secret = true }, 40 end
    Check(not NS.WindowFocusGeometry.Read(single, measured), "secret native rect was painted")
    single.GetRect = function() end
    Check(not NS.WindowFocusGeometry.Read(single, measured), "an unanchored frame retained its rect")
    local function Children(parent, children)
        parent.GetChildren = function() scans = scans + 1; return unpack(children) end
    end
    local function Child(parent, kind, left, bottom, width, height)
        made = made + 1
        local child = Native("CostChild" .. made, left, bottom, width, height)
        child.parent, child.kind = parent, kind
        return child
    end
    -- Five nodes: two at depth 1, two at depth 2, one raised at depth 3.
    local page = Child(professions, "Frame", 600, 200, 700, 658)
    local card = Child(page, "Frame", 650, 400, 300, 100)
    local bar = Child(card, "Frame", 650, 400, 300, 20)
    bar.strata, bar.frameLevel = "HIGH", 100
    local tabs = Child(professions, "Frame", 620, 174, 400, 28)
    local tab = Child(tabs, "Button", 620, 174, 140, 28)
    Children(professions, { page, tabs })
    Children(page, { card }); Children(card, { bar }); Children(tabs, { tab })

    local hostReads, typeReads, scriptReads = 0, 0, 0
    local field = NS.Safety.Field
    NS.Safety.Field = function(target, key)
        if target == professions and key == "PortraitContainer" then hostReads = hostReads + 1 end
        return field(target, key)
    end
    local nativeType, nativeScript = bar.GetObjectType, bar.GetScript
    bar.GetObjectType = function(self) typeReads = typeReads + 1; return nativeType(self) end
    bar.GetScript = function(self, name) scriptReads = scriptReads + 1; return nativeScript(self, name) end

    professions:Hide()
    scans, hostReads, typeReads, scriptReads = 0, 0, 0, 0
    professions:Show()
    Check(scans == 3, "active window must read only the three parents of potential exterior pieces")
    Check(hostReads == 1, "one discovery resolved the root's artwork host " .. hostReads .. " times (once per node)")
    Check(typeReads == 0, "active window traversed a deep native layer with no veil to paint")
    Check(scriptReads == 0, "a node too deep to extend the shell had its mouse script read " .. scriptReads .. " times")

    -- The same walk still finds what it found before.
    Click(character)
    local state = F.records[professions]
    Check(typeReads == 1, "focus reversal must inspect the deep layer exactly once before dimming")
    Check(state.strata == "HIGH" and state.level > bar.frameLevel, "deep raised native content escaped its dim veil")
    local function Covered(rect)
        for _, veil in ipairs(state.veils) do
            if veil.dim and Intersects(veil.rect, rect) then return true end
        end
        return false
    end
    Check(Covered({ left = 620, bottom = 174, width = 140, height = 24 }), "native tab below the root lost its dimming")

    -- Demotion discovers a hidden deep branch for the first time. Its later
    -- show must lift the veil above newly visible content without any click.
    local branch = Child(card, "Frame", 655, 405, 200, 60)
    local raised = Child(branch, "Frame", 660, 410, 100, 30)
    raised.strata, raised.frameLevel = "TOOLTIP", 950
    branch:Hide()
    Children(card, { bar, branch })
    Children(branch, { raised })
    Click(professions); Tick()
    Click(character); Tick()
    branch:Show(); Tick()
    Check(state.level > raised.frameLevel and state.strata == "TOOLTIP",
        "showing a previously hidden deep branch left its child above the veil")
    branch:Hide(); Tick()
    Children(card, { bar })

    -- Nothing is kept across walks: a host and a region created while the
    -- window was closed are both seen by its next show.
    local portrait = Child(professions, "Frame", 600, 857, 1, 1)
    local art = Child(portrait, "Texture", 560, 830, 62, 62)
    function art:GetTexture() return "native-book" end
    function art:GetTexCoord() return 0, 0, 0, 1, 1, 0, 1, 1 end
    portrait.portrait = art
    local sideTab = Child(professions, "Frame", 1300, 600, 50, 46)
    sideTab.scripts.OnMouseDown = function() end
    professions:Hide()
    professions.PortraitContainer = portrait
    Children(professions, { page, tabs, portrait, sideTab })
    hostReads = 0
    professions:Show()
    Check(hostReads == 1, "the reopened window resolved its artwork host " .. hostReads .. " times")
    Click(character)
    Check(Covered({ left = 562, bottom = 832, width = 30, height = 20 }), "late native portrait host was not rediscovered on show")
    Check(Covered({ left = 1300, bottom = 600, width = 50, height = 46 }), "late-created side tab was not rediscovered on show")
    local dormant = Child(professions, "Button", 600, 174, 50, 28)
    dormant:Hide()
    local layerReads = 0
    local getLayer, getLevel = dormant.GetFrameStrata, dormant.GetFrameLevel
    function dormant:GetFrameStrata() layerReads = layerReads + 1; return getLayer(self) end
    function dormant:GetFrameLevel() layerReads = layerReads + 1; return getLevel(self) end
    Children(professions, { page, tabs, dormant })
    F.RefreshChrome(professions)
    Tick()
    Check(layerReads == 0, "hidden shallow child read native layering before it could affect the veil")
    dormant.strata, dormant.frameLevel = "TOOLTIP", 777
    dormant:Show(); Tick()
    Check(layerReads > 0 and F.records[professions].level >= 778,
        "showing a previously hidden child failed to discover its new layer")
    Tick()
    local armWrites, nativeSetScript = 0, driver.SetScript
    function driver:SetScript(name, callback)
        if name == "OnUpdate" and callback then armWrites = armWrites + 1 end
        return nativeSetScript(self, name, callback)
    end
    for i = 1, 100 do F.RefreshChrome(professions) end
    local nativeChildren, invalidate = professions.GetChildren, true
    function professions:GetChildren()
        if invalidate then
            invalidate = false
            F.RefreshChrome(self)
        end
        return nativeChildren(self)
    end
    Tick()
    Check(driver.scripts.OnUpdate ~= nil, "geometry invalidated during the pass lost its next settlement")
    Tick()
    print(("100 layout notifications plus one reentrant notification: %d driver arms"):format(armWrites))
    Check(armWrites == 1 and not driver.scripts.OnUpdate, "focus repeatedly rearmed or failed to settle its worker")
    local nodes = {}
    for i = 1, 100 do nodes[i] = Child(professions, "Button", 650, 400, 30, 20) end
    -- An exterior button at its own scale covers this precise strip.
    local outside = nodes[100]
    outside.left, outside.bottom, outside.width, outside.height, outside.scale = 310, 87, 70, 14, 2
    Children(professions, nodes)
    local scaleReads, childScaleReads = 0, 0
    local originalScale = UIParent.GetEffectiveScale
    function UIParent:GetEffectiveScale()
        scaleReads = scaleReads + 1
        return originalScale(self)
    end
    for i = 1, #nodes do
        local read = nodes[i].GetEffectiveScale
        nodes[i].GetEffectiveScale = function(self) childScaleReads = childScaleReads + 1; return read(self) end
    end
    F.RefreshChrome(professions)
    Tick()
    print(("100 visible buttons: %d UIParent scale reads, %d child scale reads"):format(scaleReads, childScaleReads))
    Check(scaleReads == 2 and childScaleReads == 100, "focus repeatedly fetched UIParent scale or skipped a button's own scale")
    Check(Covered({ left = 620, bottom = 174, width = 140, height = 24 }), "independently scaled tab escaped its veil")

    local originalRect, changed = nodes[1].GetRect, true
    nodes[1].GetRect = function(self)
        if changed then UIParent.scale, changed = 2, false end
        return originalRect(self)
    end
    F.RefreshChrome(professions)
    Tick()
    Check(not Dimmed(professions) and driver.scripts.OnUpdate, "reentrant scaling painted a mixed footprint or lost the layout retry")
    Tick()
    Check(Covered({ left = 310, bottom = 87, width = 70, height = 12 }) and not driver.scripts.OnUpdate,
        "tab geometry at the new UI scale failed to settle")

    local restricted = { secret = true }
    nodes[1].GetRect = function(self)
        UIParent.scale = restricted
        return originalRect(self)
    end
    F.RefreshChrome(professions)
    Tick()
    Check(not Dimmed(professions), "a previously public scale was used after it became restricted")
    Tick()
    Check(not driver.scripts.OnUpdate, "restricted root scale kept the worker armed")
    nodes[1].GetRect, UIParent.scale = originalRect, 1
    driver.scripts.OnEvent(driver, "UI_SCALE_CHANGED")
    Tick()
    Check(Covered({ left = 620, bottom = 174, width = 140, height = 24 }), "window failed to recover after a restricted scale")
    UIParent.GetEffectiveScale = originalScale
    F.RefreshChrome(professions)
    professions:Hide(); character:Hide()
    Check(not driver.events.GLOBAL_MOUSE_DOWN and not driver.scripts.OnUpdate, "discovery left idle work behind")

    local bag = Native("ContainerFrameCombinedBags", 1000, 100, 400, 400)
    bag:Hide()
    local rows, bagScans, rowReads = {}, 0, 0
    for i = 1, 100 do
        rows[i] = Child(bag, "Button", 1050, 200, 30, 25)
        local read = rows[i].GetRect
        rows[i].GetRect = function(self) rowReads = rowReads + 1; return read(self) end
    end
    function bag:GetChildren() bagScans = bagScans + 1; return unpack(rows) end
    character.left, character.bottom, character.width, character.height = 100, 160, 400, 220
    character:Show()
    W.TrackFocus(bag, "cost")
    bag:Show()
    for i = 1, 3 do F.RefreshChrome(bag); Tick() end
    print(("Distant bag, 100 rows, four layouts: %d bag scans, %d row geometry reads"):format(bagScans, rowReads))
    Check(bagScans == 0 and rowReads == 0 and Dimmed(character), "an unreachable clear bag traversed its row tree")

    -- A new external child needs no invalidation while the windows are apart.
    local late = Child(bag, "Button", 950, 200, 50, 30)
    rows[101] = late
    character.left, character.width = 600, 390
    F.RefreshChrome(character); Tick()
    local function CharacterVeil(x)
        for _, veil in ipairs(F.records[character].veils) do
            if veil.dim and Intersects(veil.rect, { left = x, bottom = 209, width = 1, height = 1 }) then return true end
        end
        return false
    end
    Check(bagScans == 1 and rowReads == 100 and not CharacterVeil(965) and CharacterVeil(930),
        "first nearby layout failed to cut out an external tab extending beyond the clear bag")
    late:Hide(); Tick()
    -- The native bound includes all current descendants. New exterior widgets
    -- and roots which exclude children from their bounds use the normal walk.
    local boundRight = 1400
    function bag:IsIgnoringChildrenForBounds() return false end
    function bag:GetBoundsRect() return 1000, 100, boundRight - 1000, 400 end
    local reserve = rowReads
    bag:Hide(); bag:Show()
    Check(rowReads == reserve, "warm interior bag measured its 100 slot rectangles")
    rows[102] = Child(bag, "Button", 955, 205, 20, 20)
    function bag:GetBoundsRect() return 950, 100, 450, 400 end
    bag:Hide(); bag:Show()
    Check(not CharacterVeil(963) and rowReads > reserve, "late exterior child escaped the warm bag broad phase")
    rows[102]:Hide(); Tick()
    function bag:IsIgnoringChildrenForBounds() return true end
    function bag:GetBoundsRect() return 1000, 100, 400, 400 end
    reserve = rowReads
    bag:Hide(); bag:Show()
    Check(rowReads > reserve, "ignored native children were classified using the parent bound")
    Check(CharacterVeil(965), "a discovered tab's native hide failed to restore the underlying veil")

    character.left, character.width, character.height = 1050, 140, 120
    bagScans, rowReads = 0, 0
    F.RefreshChrome(character); F.RefreshChrome(bag); Tick()
    Check(bagScans == 0 and rowReads == 0 and not Dimmed(character),
        "a clear bag covering the entire dimmed window still inspected rows or kept a veil")
    bag:Hide(); character:Hide()

    local spells = Native("PlayerSpellsFrame", 300, 200, 400, 300)
    local front = Native("FriendsFrame", 300, 200, 400, 300)
    spells:Hide(); front:Hide()
    W.TrackFocus(spells, "cover"); W.TrackFocus(front, "cover")
    local page = Child(spells, "Frame", 310, 210, 350, 260)
    local holder = Child(page, "Frame", 315, 220, 330, 240)
    local leaves, topLevel = {}, { page }
    local deepReads, lowReads, lowLevels, visibilityReads, childReads = 0, 0, 0, 0, 0
    for i = 1, 100 do
        local leaf = Child(holder, "Button", 325, 230, 32, 28)
        leaf.strata = "BACKGROUND"
        function leaf:GetObjectType() deepReads = deepReads + 1; return "Button" end
        local visible = leaf.IsVisible
        function leaf:IsVisible() visibilityReads = visibilityReads + 1; return visible(self) end
        function leaf:GetChildren() childReads = childReads + 1 end
        function leaf:GetFrameStrata() lowReads = lowReads + 1; return self.strata end
        function leaf:GetFrameLevel() lowLevels = lowLevels + 1; return self.frameLevel or 1 end
        leaves[i] = leaf
    end
    Children(spells, topLevel); Children(page, { holder })
    local holderScans = 0
    function holder:GetChildren() holderScans = holderScans + 1; return unpack(leaves) end
    spells:Show(); front:Show()
    for i = 1, 3 do F.RefreshChrome(spells); Tick() end
    print(("Equal bounds, 100 deep rows, four layouts: %d visits, %d native row reads"):format(deepReads,
        deepReads + lowReads + lowLevels + visibilityReads + childReads))
    Check(deepReads == 0 and holderScans == 0 and not Dimmed(spells),
        "fully covered native pages enumerated or inspected their deep rows for a veil")
    -- Newly acquired deep content must be discovered on the first exposed layout.
    local raised = Child(holder, "Frame", 340, 240, 60, 30)
    raised.strata, raised.frameLevel = "FULLSCREEN", 900
    leaves[101] = raised
    front.left = 440; F.RefreshChrome(front); Tick()
    Check(Dimmed(spells) and deepReads == 100 and F.records[spells].level > 900,
        "exposing a formerly covered window missed its new native raised descendant")
    Check(lowReads == 100 and lowLevels == 0, "a lower stratum queried levels that cannot contribute to painting")
    -- A small native tab above the equal root still needs real dimming.
    front.left = 300
    topLevel[2] = Child(spells, "Button", 460, 495, 40, 25)
    F.RefreshChrome(spells); F.RefreshChrome(front); Tick()
    local tabCovered = false
    for _, veil in ipairs(F.records[spells].veils) do
        if veil.dim and Intersects(veil.rect, { left = 466, bottom = 508, width = 5, height = 5 }) then tabCovered = true end
    end
    Check(tabCovered and F.records[spells].level > 900, "a visible exterior tab was swallowed by the root-only cover")
    front.left, front.bottom, front.width, front.height = 200, 100, 600, 500
    local beforeCover = deepReads
    F.RefreshChrome(spells); F.RefreshChrome(front); Tick()
    Check(not Dimmed(spells) and deepReads == beforeCover, "a fully padded cover traversed or painted a background page")
    spells:Hide(); front:Hide()

    local fullScans = 0
    local leftWindow = Native("CharacterFrame", 100, 100, 400, 360)
    local rightWindow = Native("ProfessionsFrame", 280, 180, 400, 360)
    local lchildren, rchildren = {}, {}
    local function NativeChildren(parent, children)
        function parent:GetChildren() fullScans = fullScans + 1; return unpack(children) end
        function parent:GetNumChildren() return #children end
    end
    local rowRects = 0
    local function Populate(window, children)
        local body = Child(window, "Frame", window.left + 8, window.bottom + 8, 200, 200)
        local rows = {}
        for i = 1, 40 do
            local button = Child(body, "Button", body.left + i, body.bottom + i, 18, 18)
            local read = button.GetRect
            function button:GetRect() rowRects = rowRects + 1; return read(self) end
            NativeChildren(button, {})
            rows[i] = button
        end
        NativeChildren(body, rows)
        children[1] = body
    end
    Populate(leftWindow, lchildren); Populate(rightWindow, rchildren)
    NativeChildren(leftWindow, lchildren); NativeChildren(rightWindow, rchildren)
    W.TrackFocus(leftWindow, "stable"); W.TrackFocus(rightWindow, "stable")
    local function FocusClick(target)
        Click(target)
        driver.scripts.OnEvent(driver, "GLOBAL_MOUSE_UP")
        Tick()
    end
    FocusClick(leftWindow); FocusClick(rightWindow)
    fullScans, rowRects = 0, 0
    FocusClick(leftWindow); FocusClick(rightWindow)
    Check(fullScans == 0 and rowRects == 0 and Dimmed(leftWindow) and F.active.frame == rightWindow,
        "a pure focus switch between visible stable windows rediscovered their descendants")
    local boundReads = 0
    function leftWindow:GetBoundsRect() boundReads = boundReads + 1; return self:GetRect() end
    function leftWindow:IsIgnoringChildrenForBounds() return false end
    lchildren[1].IsIgnoringChildrenForBounds = function() return false end
    rowRects = 0
    leftWindow:Hide(); leftWindow:Show()
    Check(boundReads > 0 and rowRects == 0, "an interior native window remeasured its 40 buttons on reopen")
    leftWindow.GetBoundsRect, leftWindow.IsIgnoringChildrenForBounds, lchildren[1].IsIgnoringChildrenForBounds = nil, nil, nil
    FocusClick(rightWindow)
    local fresh = Child(leftWindow, "Button", 82, 200, 25, 30)
    NativeChildren(fresh, {})
    lchildren[#lchildren + 1] = fresh
    FocusClick(leftWindow); FocusClick(rightWindow)
    Check(fullScans > 0 and F.records[leftWindow].extentCount > 0, "late native child was lost across pure focus switches")
    local first = Child(leftWindow, "Frame", 130, 130, 100, 100)
    local middle = Child(first, "Frame", 140, 140, 80, 80)
    local inner = Child(middle, "Frame", 145, 145, 60, 60)
    inner.strata, inner.frameLevel = "BACKGROUND", 1
    NativeChildren(first, {middle}); NativeChildren(middle,{inner}); NativeChildren(inner,{})
    lchildren[#lchildren + 1] = first
    F.RefreshChrome(leftWindow); Tick()
    FocusClick(leftWindow); FocusClick(rightWindow)
    inner:SetFrameStrata("TOOLTIP"); inner:SetFrameLevel(1500)
    FocusClick(leftWindow); FocusClick(rightWindow)
    Check(F.records[leftWindow].strata == "TOOLTIP" and F.records[leftWindow].level > 1500,
        "warm membership cache missed a newly raised previously low deep native child")
    -- An existing unbound side tab can become interactive while showing.
    local scripted = Child(leftWindow, "Frame", 70, 276, 45, 28)
    NativeChildren(scripted,{})
    lchildren[#lchildren + 1] = scripted
    F.RefreshChrome(leftWindow); Tick()
    FocusClick(leftWindow); FocusClick(rightWindow)
    local previousExtents = F.records[leftWindow].extentCount
    scripted:SetScript("OnMouseDown", function() end)
    FocusClick(leftWindow); FocusClick(rightWindow)
    Check(F.records[leftWindow].extentCount == previousExtents + 1, "new input script on an existing native tab was lost")
    local coldDiscoveries, anchors = 0, NS.WindowFocusContour.Anchors
    NS.WindowFocusContour.Anchors = function(window, result)
        if window == leftWindow and result == F.records[leftWindow].anchors then coldDiscoveries = coldDiscoveries + 1 end
        return anchors(window, result)
    end
    leftWindow:Hide(); leftWindow:Show()
    Check(coldDiscoveries == 0, "a stable reopened window repeated full contour discovery")
    leftWindow:Hide()
    fresh.left = 141
    leftWindow:Show()
    Check(coldDiscoveries > 0 and F.records[leftWindow].extentCount == 1,
        "a tab moved inside the hidden root but kept its old exterior cutout")
    local discoveredBefore = coldDiscoveries
    leftWindow:Hide()
    lchildren[#lchildren] = Child(leftWindow, "Button", 60, 280, 45, 28)
    NativeChildren(lchildren[#lchildren],{})
    scripted.parent = rightWindow
    leftWindow:Show()
    Check(coldDiscoveries > discoveredBefore, "a same-count reparent while closed reused stale membership")
    -- Parent visibility propagates OnHide/OnShow for individually shown
    -- descendants, but a locally hidden tab receives neither native signal.
    local dormantTab = Child(leftWindow, "Button", 58, 240, 48, 24)
    NativeChildren(dormantTab,{})
    dormantTab:Hide()
    lchildren[#lchildren + 1] = dormantTab
    F.RefreshChrome(leftWindow); Tick()
    coldDiscoveries = 0
    leftWindow:Hide()
    for _, hook in ipairs(fresh.hooks.OnHide or {}) do hook(fresh) end
    leftWindow:Show()
    for _, hook in ipairs(fresh.hooks.OnShow or {}) do hook(fresh) end
    Tick()
    Check(coldDiscoveries == 0, "inherited child visibility triggered another full warm discovery")
    local exteriors = F.records[leftWindow].extentCount
    leftWindow:Hide()
    dormantTab.shown = true -- no OnShow while the root is hidden
    leftWindow:Show()
    for _, hook in ipairs(dormantTab.hooks.OnShow or {}) do hook(dormantTab) end
    Tick()
    Check(coldDiscoveries > 0 and F.records[leftWindow].extentCount == exteriors + 1,
        "a child explicitly shown while the root was hidden missed its first visible contour")
    leftWindow:Hide()
    dormantTab.shown = false -- no OnHide while the root is hidden
    leftWindow:Show()
    Tick()
    Check(F.records[leftWindow].extentCount == exteriors, "hidden child still contributed after parent reopened")
    dormantTab:Show(); Tick()
    Check(F.records[leftWindow].extentCount == exteriors + 1, "a real subsequent child Show was mistaken for parent visibility")
    FocusClick(rightWindow)
    leftWindow:Hide()
    inner.frameLevel = 2100 -- Blizzard can change the effective level without a public Lua setter hook.
    leftWindow:Show()
    rightWindow:Hide(); rightWindow:Show(); Tick()
    Check(F.active.frame == rightWindow and F.records[leftWindow].level > 2100,
        "focus taken by native Show reused a stale layer after a hidden level change")
    NS.WindowFocusContour.Anchors = anchors
    leftWindow:Hide(); rightWindow:Hide()

end
print("suite_window_focus_discovery_cost_contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@window_focus_discovery_cost_fixture"))()
