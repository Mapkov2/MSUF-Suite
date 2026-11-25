local root = assert(arg[1], "Suite root required")
local sourceOverride = arg[2]

-- This models the native cache ownership and the exact writer/reader order.
-- It does not emulate WoW secret values or certify live secure execution.
-- Forever bebcb6bf, BuffFrame.lua:77-186 and Mainline EditModeManagerOverrides.lua:39-55.
local failures, checks = {}, 0
local function Check(value, message)
    checks = checks + 1
    if not value then failures[#failures + 1] = message end
end

local function ShippedCanAnchor(isForbidden)
    local handle = assert(io.open(root .. "/MSUF_Suite/Core/Platform.lua", "rb"))
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    local body = assert(text:match("\n(function Suite%.Safety%.CanAnchor%(.-\nend)\n"),
        "Suite.Safety.CanAnchor must live in MSUF_Suite/Core/Platform.lua (the Safety of _G.MSUFSuite)")
    local chunk = assert(loadstring("local Suite, IsSecret = ...\n" .. body .. "\nreturn Suite.Safety.CanAnchor"))
    return chunk({ Safety = { IsForbidden = isForbidden } },
        function(value) return type(value) == "table" and value.secret == true end)
end

local function Run(scenario)
    local previousMode, previousSource = arg[2], arg[3]
    arg[2], arg[3] = "harness", sourceOverride
    local H = assert(loadfile(root .. "/tools/tests/suite_player_auras_contract.lua"))()
    arg[2], arg[3] = previousMode, previousSource
    local frame, module, NS = H.frame, H.module, H.private.NS
    -- The shipped anchoring guard on the harness's Safety stand-in. Player aura layout's NS is
    -- _G.MSUFSuite, the Suite core table: its Safety is Platform.lua's Suite.Safety.
    NS.Safety.CanAnchor = ShippedCanAnchor(NS.Safety.IsForbidden)
    local origin, executionTainted, meterStateTainted = "native", false, false
    local writes, addonWrites, solverCalls = 0, 0, 0
    local cacheOwners, skins, nativeContainers, solverCallsByFrame = {}, {}, {}, {}
    local yieldHistory = {}
    local boundaryErrors, expectedError, expectedErrors = {}, nil, 0
    NS.Dispatch = function(callback, ...)
        local ok, result = pcall(callback, ...)
        if not ok then boundaryErrors[#boundaryErrors + 1] = result end
        return ok and result or nil
    end
    H.private.PlayerAuraSkins.Yield = function(value) yieldHistory[#yieldHistory + 1] = value end

    local function Native(callback, ...)
        local previous = origin
        origin = "native"
        callback(...)
        origin = previous
    end
    hooksecurefunc = function(owner, key, callback)
        local original = owner[key]
        owner[key] = function(self, ...)
            original(self, ...)
            local previous = origin
            origin = "addon"
            callback(self, ...)
            origin = previous
        end
    end

    NS.HostBridge.PlayerAuraSkin = function(choice) return choice end
    NS.HostBridge.PaintIconSkin = function(button, look)
        skins[button] = look
        return look ~= nil
    end
    module.config.buffSkin = "taint-test-look"
    for _, button in ipairs(frame.auraFrames) do
        function button:GetParent() return frame.AuraContainer end
    end
    local failed = H.Button(false)
    function failed:GetParent() return frame.AuraContainer end
    frame.auraFrames[3] = failed
    local container = frame.AuraContainer
    nativeContainers[container] = true
    container.currentGridLayoutInfo = nil
    container.isHorizontal, container.iconStride, container.iconPadding = true, 12, 5
    container.addIconsToRight, container.addIconsToTop, container.iconScale = false, false, 1
    if scenario == "pending-native-nil-flag" then container.addIconsToTop = nil end
    function container:GetParent() return frame end
    function frame:UpdateSize() self:SetSize(304, 40) end
    frame.defaultPosition = true
    frame.nativeAnchor = { "TOPRIGHT", UIParent, "TOPRIGHT", -30, -40 }
    frame.nativeContainerAnchor = { "TOPRIGHT", frame, "TOPRIGHT", 0, 0 }
    function frame:IsInDefaultPosition() return self.defaultPosition end
    function frame:ApplySystemAnchor()
        if self.skipAnchor then return end
        self:ClearAllPoints()
        self:SetPoint(unpack(self.nativeAnchor))
    end
    StatusTrayManager.UpdateTrayAndBuffFrameLayout = function()
        if frame:IsInDefaultPosition() then
            frame:ClearAllPoints()
            frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -99)
        end
    end

    -- GridLayoutUtil creates its own layout manager and writes C geometry.
    -- Its input layout and anchor remain owned by the preceding native pass.
    GridLayoutUtil = { ApplyGridLayout = function(buttons, anchor, layout)
        Check(nativeContainers[anchor.relativeTo], scenario .. ": a grid anchor referenced the owned proxy")
        for slot, button in ipairs(buttons) do
            button:ClearAllPoints()
            button:SetPoint(anchor.point, anchor.relativeTo, anchor.relativePoint,
                anchor.x - (slot - 1) * layout.spacing, anchor.y)
        end
    end }

    -- AuraContainerMixin:UpdateGridLayout reads the prior cache before writing
    -- a replacement. Native BuffFrame also caches collapse-button direction.
    AuraContainerMixin = {}
    function AuraContainerMixin:UpdateGridLayout(auras)
        solverCalls = solverCalls + 1
        local parent = self:GetParent()
        solverCallsByFrame[parent] = (solverCallsByFrame[parent] or 0) + 1
        if cacheOwners[self.currentGridLayoutInfo] == "addon" then executionTainted = true end
        local previous = self.currentGridLayoutInfo
        local anchor
        if previous and previous.addIconsToTop == self.addIconsToTop
            and previous.addIconsToRight == self.addIconsToRight then
            anchor = previous.anchor
        else
            anchor = { point = self.addIconsToTop and "BOTTOMRIGHT" or "TOPRIGHT", relativeTo = self,
                relativePoint = self.addIconsToTop and "BOTTOMRIGHT" or "TOPRIGHT", x = 0, y = 0 }
        end
        local sameLayout = previous ~= nil
        for _, key in ipairs({ "isHorizontal", "iconStride", "iconPadding", "addIconsToRight", "addIconsToTop" }) do
            if not previous or previous[key] ~= self[key] then sameLayout = false break end
        end
        local cache = {
            isHorizontal = self.isHorizontal, iconStride = self.iconStride, iconPadding = self.iconPadding,
            addIconsToRight = self.addIconsToRight, addIconsToTop = self.addIconsToTop,
            anchor = anchor,
            layout = sameLayout and previous.layout or { spacing = 30 + self.iconPadding },
        }
        local cacheOwner = "native"
        if origin == "addon" or executionTainted then cacheOwner = "addon" end
        cacheOwners[cache] = cacheOwner
        self.currentGridLayoutInfo = cache
        if self == container then
            writes = writes + 1
            if origin == "addon" then addonWrites = addonWrites + 1 end
        end
        local point = "TOP"
        if not self.isHorizontal then point = self.addIconsToRight and "LEFT" or "RIGHT"
        elseif self.addIconsToTop then point = "BOTTOM" end
        local opposite = ({ TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT" })[point]
        for _, button in ipairs(auras) do
            button:SetScale(1)
            button:SetSize(30, 40)
            button.Icon:ClearAllPoints()
            button.Icon:SetPoint(point, button, point, 0, 0)
            button.Duration:ClearAllPoints()
            button.Duration:SetPoint(point, button.Icon, opposite, 0, 0)
        end
        self:GetParent():UpdateSize()
        GridLayoutUtil.ApplyGridLayout(auras, cache.anchor, cache.layout)
    end
    function frame:UpdateGridLayout()
        local nativeContainer = self.AuraContainer
        local icons = self.auraFrames
        if self.ConsolidatedBuffs and self.ConsolidatedBuffs:ShouldShow() then
            icons = { self.ConsolidatedBuffs, unpack(self.auraFrames) }
        end
        AuraContainerMixin.UpdateGridLayout(self.AuraContainer, icons)
        if self.skipContainerAnchor then return end
        nativeContainer:ClearAllPoints()
        nativeContainer:SetPoint(unpack(self.nativeContainerAnchor))
        if self.CollapseAndExpandButton then
            self.CollapseAndExpandButton:ClearAllPoints()
            self.CollapseAndExpandButton:SetPoint("TOPRIGHT", self, "TOPRIGHT", 8, 2)
        end
        nativeContainer:SetSize(304, 40)
    end

    local debuff = H.Region()
    debuff.AuraContainer, debuff.auraFrames = H.Region(), { H.Button(true) }
    local debuffContainer = debuff.AuraContainer
    nativeContainers[debuffContainer] = true
    debuffContainer.isHorizontal, debuffContainer.iconStride, debuffContainer.iconPadding = true, 12, 5
    debuffContainer.addIconsToRight, debuffContainer.addIconsToTop, debuffContainer.iconScale = false, false, 1
    function debuffContainer:GetParent() return debuff end
    debuff.auraFrames[1].GetParent = function() return debuffContainer end
    debuff.defaultPosition = false
    debuff.nativeAnchor = { "TOPLEFT", UIParent, "TOPLEFT", 80, -120 }
    debuff.nativeContainerAnchor = { "TOPRIGHT", debuff, "TOPRIGHT", 0, 0 }
    for _, key in ipairs({ "UpdateSize", "ApplySystemAnchor", "IsInDefaultPosition", "UpdateGridLayout",
        "UpdateAuraButtons", "ShouldShowAura", "IsEditing", "SetIsEditing", "RefreshConsolidationFrameVisibility" }) do
        debuff[key] = frame[key]
    end
    DebuffFrame = debuff
    if scenario == "noop-native-anchors" or scenario == "coincident-native-anchors" or scenario == "independent-arrow" then
        frame.CollapseAndExpandButton = H.Region()
        frame.nativeContainerAnchor = { "BOTTOMLEFT", frame, "BOTTOMLEFT", 19, 27 }
    end
    Native(frame.ApplySystemAnchor, frame)
    Native(debuff.ApplySystemAnchor, debuff)
    Native(frame.UpdateGridLayout, frame)
    Native(debuff.UpdateGridLayout, debuff)
    local nativeCache = frame.AuraContainer.currentGridLayoutInfo
    origin = "addon"
    local icon = frame.auraFrames[1].Icon
    local getPoint, getWidth, getHeight = icon.GetPoint, icon.GetWidth, icon.GetHeight
    local unavailableGrid = scenario == "disable-with-unreadable-native-anchors"
    if scenario == "restricted-icon" or scenario == "secret-icon" or unavailableGrid then
        icon.GetPoint = function() return "TOP", frame.auraFrames[1], "TOP", { secret = true }, 0 end
        icon.GetWidth, icon.GetHeight = function() return { secret = true } end, function() return { secret = true } end
    end
    -- 12.x: text anchored to artwork with secret anchors reads secret anchors too.
    if scenario == "restricted-icon" or scenario == "secret-icon" or unavailableGrid then
        for _, text in ipairs({ frame.auraFrames[1].Duration, frame.auraFrames[1].Count }) do
            text:ClearAllPoints()
            text:SetPoint("TOP", icon, "BOTTOM", 0, 0)
            text.GetNumPoints = function() return 1 end
            text.GetPoint = function() return "TOP", icon, "BOTTOM", { secret = true }, 0 end
        end
    end
    if scenario == "restricted-icon" then
        icon.IsAnchoringRestricted = function() return true end
        frame.auraFrames[1].Duration.IsAnchoringRestricted = icon.IsAnchoringRestricted
    end
    module:Enable()
    Check(frame.auraFrames[1].width == 52 and skins[frame.auraFrames[1]] == "taint-test-look",
        scenario .. ": custom aura layout or skin was not adopted")
    if scenario == "noop-native-anchors" then
        frame.skipAnchor, frame.skipContainerAnchor = true, true
        Native(frame.ApplySystemAnchor, frame)
        container.iconPadding = 9
    elseif scenario == "coincident-native-anchors" then
        frame.nativeAnchor = { "TOPRIGHT", Minimap, "TOPLEFT", -12, 0 }
        frame.nativeContainerAnchor = { "TOPRIGHT", frame, "TOPRIGHT", 0, 0 }
        Native(frame.ApplySystemAnchor, frame)
        container.iconPadding = 9
    elseif scenario == "native-layout-change" then
        container.iconPadding = 9
    elseif scenario == "native-container-change" or scenario == "transient-native-anchor" then
        container.addIconsToTop = true
        frame.nativeContainerAnchor = { "BOTTOMLEFT", frame, "BOTTOMLEFT", 13, 17 }
        if scenario == "transient-native-anchor" then
            local nativeGetPoint = container.GetPoint
            container.GetPoint = function() return "BOTTOMLEFT", frame, "BOTTOMLEFT", { secret = true }, 17 end
            Native(frame.UpdateGridLayout, frame)
            local cacheAfterUnreadable = container.currentGridLayoutInfo
            container.GetPoint = nativeGetPoint
            Native(frame.UpdateGridLayout, frame)
            Check(container.currentGridLayoutInfo.anchor == cacheAfterUnreadable.anchor
                and container.currentGridLayoutInfo.layout == cacheAfterUnreadable.layout,
                "transient native anchor: fixture did not retry the same native identities")
        end
    elseif scenario == "native-frame-change" then
        frame.nativeAnchor = { "TOPLEFT", UIParent, "TOPLEFT", 71, -83 }
        Native(frame.ApplySystemAnchor, frame)
    elseif scenario == "status-tray-custom" then
        frame.defaultPosition = false
    elseif scenario == "consolidation" or scenario == "secret-consolidation" then
        frame.ConsolidatedBuffs = H.Button(true)
        function frame.ConsolidatedBuffs:GetParent() return frame end
    end
    Native(frame.UpdateGridLayout, frame)
    Check(frame.auraFrames[1].width == 52 and skins[frame.auraFrames[1]] == "taint-test-look",
        scenario .. ": a native event lost the custom aura layout or skin")
    nativeCache = frame.AuraContainer.currentGridLayoutInfo
    if scenario == "status-tray-default" or scenario == "status-tray-custom" then
        Native(StatusTrayManager.UpdateTrayAndBuffFrameLayout)
    end

    if scenario == "direct-frame-release" or scenario == "direct-frame-adopt" or scenario == "direct-frame-refill" then
        -- A native snap or drag can write the Edit Mode override without
        -- invoking ApplySystemAnchor. Capture it before a release or re-adopt.
        Native(frame.ClearAllPoints, frame)
        Native(frame.SetPoint, frame, "TOPLEFT", UIParent, "TOPLEFT", 87, -99)
        if scenario == "direct-frame-adopt" then module:Refresh() end
        if scenario == "direct-frame-refill" then
            Native(frame.UpdateAuraButtons, frame)
            Check(frame.points[1][2] == Minimap, "the next buff update kept an external frame position")
        end
        module:Disable()
        local point = frame.points[1]
        Check(point[2] == UIParent and point[4] == 87 and point[5] == -99,
            scenario .. ": lost a direct native frame anchor")
    elseif scenario == "independent-arrow" then
        local arrow = frame.CollapseAndExpandButton
        Native(arrow.ClearAllPoints, arrow)
        Native(arrow.SetPoint, arrow, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 14, -7)
        frame.skipContainerAnchor = true
        Native(frame.UpdateGridLayout, frame)
        nativeCache = container.currentGridLayoutInfo
        module:Disable()
        local p = arrow.points[1]
        Check(p[1] == "BOTTOMRIGHT" and p[2] == frame and p[4] == 14 and p[5] == -7,
            "a grid notification erased a genuine independent native arrow position")
    elseif scenario == "cleanup-region-error" then
        expectedError, expectedErrors = "fixture saved region failure", 1
        local count = frame.auraFrames[1].Count
        local setColor = count.SetTextColor
        count.SetTextColor = function() error(expectedError) end
        local finished = pcall(module.Disable, module)
        count.SetTextColor = setColor
        Check(finished and yieldHistory[#yieldHistory] == false, "a throwing region blocked the skin-only handoff")
        Check(frame.auraFrames[2].Duration.font[2] == 10 and debuff.auraFrames[1].Duration.font[2] == 10,
            "one throwing region prevented restoration on other buttons or the other row")
        Check(skins[frame.auraFrames[1]] == nil and skins[frame.auraFrames[2]] == nil,
            "native selected skins were left owned by the disabled layout module")
    elseif scenario == "persistent-solver-error" then
        local original = AuraContainerMixin.UpdateGridLayout
        local tries = 0
        expectedError = "fixture persistent proxy solver failure"
        AuraContainerMixin.UpdateGridLayout = function(self, ...)
            if self:GetParent() == frame and self ~= container then
                tries = tries + 1
                error(expectedError)
            end
            return original(self, ...)
        end
        local bad = H.Button(true)
        function bad:GetParent() return container end
        local scale = bad.GetScale
        bad.GetScale = function() return nil end
        frame.auraFrames[4], frame.auraInfo = bad, { {}, {}, {}, {} }
        Native(frame.UpdateAuraButtons, frame)
        Check(tries == 1 and skins[frame.auraFrames[1]] == "taint-test-look" and skins[bad] == "taint-test-look",
            "a throwing native solver stranded the visible pool without its selected skin")
        for _ = 1, 8 do Native(frame.UpdateAuraButtons, frame) end
        Check(tries == 2 and frame.auraFrames[1].width == 30,
            "a persistent proxy solver error must allow one transient retry then leave the row native")
        module:Refresh()
        Check(tries == 3 and skins[bad] == "taint-test-look", "explicit refresh did not retry the solver with native skins")
        -- DebuffFrame ends every refill with a real native grid. The successful
        -- native pass supplies the geometry without ever re-entering the proxy.
        for _ = 1, 5 do Native(frame.UpdateGridLayout, frame) end
        nativeCache = container.currentGridLayoutInfo
        Check(tries == 3 and skins[bad] == "taint-test-look", "native relayouts repeatedly rearmed the failed solver")
        bad.GetScale = scale
        Native(frame.UpdateAuraButtons, frame)
        Check(frame.auraFrames[1].width == 52 and bad.width == 52 and skins[bad] == "taint-test-look",
            "the custom layout failed to recover after Blizzard solved the row and the bad entry became readable")
        expectedErrors = 3
        AuraContainerMixin.UpdateGridLayout = original
    elseif scenario == "independent-adoption" then
        expectedError, expectedErrors = "fixture failed cold buff adoption", 1
        local first = frame.auraFrames[1]
        local setter = first.SetScale
        first.SetScale = function() error(expectedError) end
        module.config.iconWidth = 67
        local adopted = pcall(module.Refresh, module)
        first.SetScale = setter
        Check(adopted and debuff.auraFrames[1].width == 67, "one row aborted adoption of the other row")
    elseif unavailableGrid then
        local button = frame.auraFrames[1]
        local duration = button.Duration
        Check(duration.points[1][1] == "BOTTOMLEFT" and duration.points[1][2] == button,
            "unreadable native anchors prevented the suite timer placement")
        -- The live grid can change orientation while the Suite layout owns the row.
        container.isHorizontal, container.addIconsToRight = false, true
        Native(frame.UpdateGridLayout, frame)
        nativeCache = container.currentGridLayoutInfo
        Check(duration.points[1][1] == "BOTTOMLEFT", "native reflow reclaimed a Suite timer")
        local otherIcon = failed.Icon
        otherIcon.forbidden = true
        local beforeSolver = solverCallsByFrame[frame]
        module:Disable()
        Check(solverCallsByFrame[frame] == beforeSolver, "a restricted slot reached the native grid solver")
        Check(yieldHistory[#yieldHistory] == false and skins[button] == nil,
            "disabling both pieces did not release the icon skin")
        otherIcon.forbidden = nil
        -- A buff refresh does not rewrite its grid anchors (e.g. Edit Mode exit).
        Native(frame.UpdateAuraButtons, frame)
        local point = duration.points[1]
        Check(#duration.points == 1 and point and point[1] == "LEFT" and point[2] == icon and point[3] == "RIGHT",
            "disabled layout left the timer inside its icon after a buff refresh")
        point = icon.points[1]
        Check(#icon.points == 1 and point and point[1] == "LEFT" and point[2] == button and point[3] == "LEFT",
            "disabled layout left the icon stretched after a buff refresh")
        Check(duration.font[2] == 10, "disabled layout retained the Suite timer font")
    elseif scenario == "disable-forbidden-saved-icon" then
        local icon = frame.auraFrames[1].Icon
        local clear, coordinates = icon.ClearAllPoints, icon.SetTexCoord
        local beforeSolver = solverCallsByFrame[frame]
        icon.forbidden = true
        icon.ClearAllPoints = function() error("fixture forbidden icon anchor write") end
        icon.SetTexCoord = function() error("fixture forbidden icon crop write") end
        local finished = pcall(module.Disable, module)
        Check(finished, "disable touched an already-styled Icon after it became forbidden")
        Check(solverCallsByFrame[frame] == beforeSolver, "forbidden saved Icon reached the native solver")
        Check(yieldHistory[#yieldHistory] == false, "forbidden saved Icon prevented releasing the skin-only piece")
        icon.forbidden, icon.ClearAllPoints, icon.SetTexCoord = nil, clear, coordinates
    elseif scenario == "disable-missing-icon" or scenario == "disable-forbidden-icon" then
        local originalIcon = failed.Icon
        local beforeSolver = solverCallsByFrame[frame]
        if scenario == "disable-missing-icon" then failed.Icon = nil
        else failed.Icon.forbidden = true end
        module:Disable()
        Check(solverCallsByFrame[frame] == beforeSolver, scenario .. ": cleanup invoked an unsafe native solver")
        Check(yieldHistory[#yieldHistory] == false, scenario .. ": cleanup did not release the skin-only piece")
        failed.Icon = originalIcon
        failed.Icon.forbidden = nil
    elseif scenario == "cleanup-solver-error" then
        expectedError, expectedErrors = "fixture cleanup solver failure", 1
        local updateGrid = AuraContainerMixin.UpdateGridLayout
        local visited = {}
        AuraContainerMixin.UpdateGridLayout = function(self, auras)
            local parent = self:GetParent()
            visited[parent] = true
            if parent == frame then error("fixture cleanup solver failure") end
            return updateGrid(self, auras)
        end
        module:Disable()
        AuraContainerMixin.UpdateGridLayout = updateGrid
        Check(visited[frame] and visited[debuff], "cleanup solver error prevented the other frame's restoration")
        Check(yieldHistory[#yieldHistory] == false, "cleanup solver error prevented releasing the skin-only piece")
    elseif scenario == "secret-consolidation" then
        local collect = frame.ConsolidatedBuffs
        local readableShown, readableShouldShow = collect.IsShown, collect.ShouldShow
        collect.IsShown = function() return { secret = true } end
        collect.ShouldShow = function() return { secret = true } end
        local beforeSolver = solverCalls
        Native(frame.UpdateAuraButtons, frame)
        Check(frame.auraFrames[1].width == 52 and collect.width == 52,
            "secret consolidation tore down a prepared custom row")
        local bad = H.Button(true)
        function bad:GetParent() return container end
        bad.GetScale = function() return nil end
        frame.auraFrames[4] = bad
        frame.auraInfo = { {}, {}, {}, {} }
        Native(frame.UpdateAuraButtons, frame)
        Check(solverCalls == beforeSolver, "secret consolidation: restoration invoked the grid solver")
        Check(frame.auraFrames[1].width == 30 and collect.width == 30,
            "secret consolidation: restoration did not restore readable snapshots")
        collect.IsShown, collect.ShouldShow = readableShown, readableShouldShow
    elseif scenario == "restricted-icon" then
        local button, neighbor = frame.auraFrames[1], frame.auraFrames[2]
        local p = frame.points[1]
        Check(p and p[2] == Minimap and p[4] == -12 and p[5] == 0, "restricted icon displaced the entire buff row")
        Check(button.Icon.points[1][1] == "TOP" and #button.Icon.points == 1, "Suite overwrote an unreadable native texture anchor")
        Check(neighbor.width == 52 and neighbor.Duration.points[1][1] == "BOTTOMLEFT" and skins[button] == "taint-test-look",
            "restricted icon prevented Suite skin, duration or neighbor layout")
        Check(#button.Duration.points == 1 and button.Duration.points[1][1] == "TOP" and button.Duration.font[2] == 10,
            "Suite wrote a restricted, unreadable duration anchor")
        icon.GetPoint, icon.GetWidth, icon.GetHeight = getPoint, getWidth, getHeight
        module:Refresh()
        Check(#icon.points == 2 and icon.points[1][1] == "TOPLEFT" and icon.points[2][1] == "BOTTOMRIGHT",
            "the previously restricted texture did not fill its slot after becoming readable")
        module:Disable()
        Check(frame.points[1][2] == UIParent and button.Icon.points[1][1] == "TOP", "restricted icon broke native restoration")
    elseif scenario == "secret-icon" then
        local button = frame.auraFrames[1]
        local duration, count = button.Duration, button.Count
        Check(#icon.points == 2 and icon.points[1][1] == "TOPLEFT" and icon.points[2][1] == "BOTTOMRIGHT",
            "a texture with unreadable but writable anchors did not fill its slot")
        Check(#duration.points == 1 and duration.points[1][1] == "BOTTOMLEFT" and duration.font[2] == 16,
            "an unreadable duration anchor kept the native duration")
        -- Blizzard's grid never re-anchors Count: it keeps its own anchor on the filled icon.
        Check(#count.points == 1 and count.points[1][2] == icon and count.font[2] == 10,
            "Suite moved a count whose native anchor it cannot restore")
        module:Disable()
        Check(#icon.points == 1 and icon.points[1][1] == "TOP" and #duration.points == 1 and duration.points[1][2] == icon
            and duration.font[2] == 10, "the native grid did not restore unreadable icon and duration anchors")
        icon.GetPoint, icon.GetWidth, icon.GetHeight = getPoint, getWidth, getHeight
    elseif scenario == "fallback" or scenario == "pending-native-flags" or scenario == "pending-native-nil-flag" then
        if scenario == "pending-native-flags" then
            container.addIconsToRight = true
        elseif scenario == "pending-native-nil-flag" then
            container.addIconsToTop = true
        end
        failed = H.Button(true)
        function failed:GetParent() return container end
        frame.auraFrames[3] = failed
        failed.GetScale = function() return { secret = true } end
        failed.Icon.GetWidth = function(_, intrinsic) return intrinsic and 30 or { secret = true } end
        frame.auraInfo = { {}, {}, {} }
        Native(frame.UpdateAuraButtons, frame)
        Check(frame.auraFrames[1].width == 30 and frame.auraFrames[2].width == 30,
            "fallback: readable buttons retained Suite dimensions")
        Check(frame.points[1][2] == Minimap and skins[failed] == "taint-test-look",
            "an unreadable visible buff lost its skin or moved the entire row to Blizzard's anchor")
        frame.nativeAnchor = { "TOPRIGHT", UIParent, "TOPRIGHT", -274.4, -209.7 }
        Native(frame.ApplySystemAnchor, frame)
        Check(frame.points[1][2] == Minimap, "a native layout update moved the row during fallback")
        if scenario ~= "fallback" then
            Check(failed.points[1] and failed.points[1][4] == -70,
                scenario .. ": pending native flags prevented restoring the last native grid")
        end
        module:Disable()
        Check(frame.points[1][2] == UIParent and frame.points[1][5] == -209.7,
            "disabling the layout during fallback lost Blizzard's latest position")
    else
        module:Disable()
        Check(frame.auraFrames[1].width == 30 and frame.auraFrames[1].Duration.font[2] == 10,
            "disable: native geometry or duration font was not restored")
    end

    Check(#boundaryErrors == expectedErrors, scenario .. ": unexpected error count at the isolation boundary")
    for _, message in ipairs(boundaryErrors) do
        Check(expectedError and message:find(expectedError, 1, true), scenario .. ": unexpected error at the boundary")
    end
    Check(addonWrites == 0, scenario .. ": Suite invoked the stateful native aura layout")
    Check(frame.AuraContainer.currentGridLayoutInfo == nativeCache,
        scenario .. ": Suite replaced Blizzard's aura layout cache")
    if scenario == "noop-native-anchors" then
        local point, containerPoint, arrow = frame.points[1], container.points[1], frame.CollapseAndExpandButton.points[1]
        Check(point[2] == UIParent and point[4] == -30 and point[5] == -40,
            "no-op ApplySystemAnchor recorded Suite's minimap position as Blizzard's")
        Check(containerPoint[1] == "BOTTOMLEFT" and containerPoint[4] == 19 and containerPoint[5] == 27,
            "a new grid identity recorded Suite's untouched container position as Blizzard's")
        Check(arrow[1] == "TOPRIGHT" and arrow[4] == 8 and arrow[5] == 2,
            "a new grid identity recorded Suite's untouched arrow position as Blizzard's")
    elseif scenario == "coincident-native-anchors" then
        local point, containerPoint = frame.points[1], container.points[1]
        Check(point[2] == Minimap and point[4] == -12 and point[5] == 0,
            "Blizzard genuinely moved its frame to the current Suite position but cleanup restored an older position")
        Check(containerPoint[1] == "TOPRIGHT" and containerPoint[4] == 0 and containerPoint[5] == 0,
            "Blizzard genuinely moved its container to the current Suite position but cleanup restored an older position")
    elseif scenario == "native-layout-change" then
        Check(frame.auraFrames[2].points[1][4] == -39,
            "native layout change: restoration used obsolete native grid spacing")
    elseif scenario == "consolidation" then
        Check(frame.ConsolidatedBuffs.width == 30 and frame.ConsolidatedBuffs.points[1][4] == 0
            and frame.auraFrames[1].points[1][4] == -35,
            "consolidation: restoration omitted the native consolidation slot")
    elseif scenario == "native-container-change" or scenario == "transient-native-anchor" then
        local point = container.points[1]
        Check(point and point[1] == "BOTTOMLEFT" and point[2] == frame and point[4] == 13 and point[5] == 17,
            scenario .. ": restoration lost the latest native container points")
        Check(container.width == 304 and container.height == 40,
            scenario .. ": restoration kept the Suite container size")
    elseif scenario == "native-frame-change" then
        local point = frame.points[1]
        Check(point and point[1] == "TOPLEFT" and point[2] == UIParent and point[4] == 71 and point[5] == -83,
            "native frame change: restoration lost the latest ApplySystemAnchor position")
    elseif scenario == "status-tray-default" or scenario == "status-tray-custom" then
        local buffPoint, debuffPoint = frame.points[1], debuff.points[1]
        local expectedY = scenario == "status-tray-default" and -99 or -40
        Check(buffPoint and buffPoint[2] == UIParent and buffPoint[4] == -30 and buffPoint[5] == expectedY,
            scenario .. ": tray layout saved the Suite position over the native buff anchor")
        Check(debuffPoint and debuffPoint[2] == UIParent and debuffPoint[4] == 80 and debuffPoint[5] == -120,
            scenario .. ": tray layout saved the Suite position over the untouched native debuff anchor")
    end

    -- EditModeFrameSetup calls aura layout before RefreshDamageMeter, in one
    -- ordinary Lua call chain. A tainted cache read contaminates that chain.
    executionTainted = false
    Native(frame.UpdateGridLayout, frame)
    meterStateTainted = executionTainted
    Check(not executionTainted, scenario .. ": native Edit Mode reached the secret specIconID comparison tainted")

    -- SetIsEditing stores its state during that setup. A later OnEvent reads
    -- the retained flag in ShouldBeShown before updating the session timer.
    executionTainted = false
    if meterStateTainted then executionTainted = true end
    Check(not executionTainted, scenario .. ": native event reached the secret durationSeconds comparison tainted")
    Check(writes >= 2, scenario .. ": normal native aura layouts did not run")
    Check(frame.AuraContainer.currentGridLayoutInfo ~= nativeCache,
        scenario .. ": a real native layout failed to replace its cache")
end

Run("fallback")
Run("restricted-icon")
Run("secret-icon")
Run("disable")
Run("native-layout-change")
Run("consolidation")
Run("native-container-change")
Run("native-frame-change")
Run("noop-native-anchors")
Run("direct-frame-release")
Run("direct-frame-adopt")
Run("direct-frame-refill")
Run("independent-arrow")
Run("coincident-native-anchors")
Run("status-tray-default")
Run("status-tray-custom")
Run("secret-consolidation")
Run("transient-native-anchor")
Run("pending-native-flags")
Run("pending-native-nil-flag")
Run("disable-missing-icon")
Run("disable-forbidden-icon")
Run("cleanup-solver-error")
Run("persistent-solver-error")
Run("cleanup-region-error")
Run("independent-adoption")
Run("disable-with-unreadable-native-anchors")
Run("disable-forbidden-saved-icon")
assert(#failures == 0, table.concat(failures, "\n"))
print("player aura native cache ownership and downstream damage meter paths: " .. checks .. " checks passed")
