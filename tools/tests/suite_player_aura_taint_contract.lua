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

local function Run(scenario)
    local previousMode, previousSource = arg[2], arg[3]
    arg[2], arg[3] = "harness", sourceOverride
    local H = assert(loadfile(root .. "/tools/tests/suite_player_auras_contract.lua"))()
    arg[2], arg[3] = previousMode, previousSource
    local frame, module, NS = H.frame, H.module, H.private.NS
    local origin, executionTainted, meterStateTainted = "native", false, false
    local writes, addonWrites, solverCalls = 0, 0, 0
    local cacheOwners, skins, nativeContainers, solverCallsByFrame = {}, {}, {}, {}
    local yieldHistory = {}
    local boundaryErrors = {}
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

    NS.HostBridge.IconSkinLook = function(choice) return choice end
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
        for _, button in ipairs(auras) do
            button:SetScale(1)
            button:SetSize(30, 40)
            button.Icon:ClearAllPoints()
            button.Icon:SetPoint("TOP", button, "TOP", 0, 0)
            button.Duration:ClearAllPoints()
            button.Duration:SetPoint("TOP", button.Icon, "BOTTOM", 0, 0)
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
        nativeContainer:ClearAllPoints()
        nativeContainer:SetPoint(unpack(self.nativeContainerAnchor))
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
    Native(frame.ApplySystemAnchor, frame)
    Native(debuff.ApplySystemAnchor, debuff)
    Native(frame.UpdateGridLayout, frame)
    Native(debuff.UpdateGridLayout, debuff)
    local nativeCache = frame.AuraContainer.currentGridLayoutInfo
    origin = "addon"
    module:Enable()
    Check(frame.auraFrames[1].width == 52 and skins[frame.auraFrames[1]] == "taint-test-look",
        scenario .. ": custom aura layout or skin was not adopted")
    if scenario == "native-layout-change" then
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

    if scenario == "disable-forbidden-saved-icon" then
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
        Check(solverCalls == beforeSolver, "secret consolidation: restoration invoked the grid solver")
        Check(frame.auraFrames[1].width == 30 and collect.width == 30,
            "secret consolidation: restoration did not restore readable snapshots")
        collect.IsShown, collect.ShouldShow = readableShown, readableShouldShow
    elseif scenario == "fallback" or scenario == "pending-native-flags" or scenario == "pending-native-nil-flag" then
        if scenario == "pending-native-flags" then
            container.addIconsToRight = true
        elseif scenario == "pending-native-nil-flag" then
            container.addIconsToTop = true
        end
        failed.Icon.GetTexCoord = function() return { secret = true }, 0, 0, 1, 1, 0, 1, 1 end
        frame.auraInfo = { {}, {}, {} }
        Native(frame.UpdateAuraButtons, frame)
        Check(frame.auraFrames[1].width == 30 and frame.auraFrames[2].width == 30,
            "fallback: readable buttons retained Suite dimensions")
        if scenario ~= "fallback" then
            Check(failed.points[1] and failed.points[1][4] == -70,
                scenario .. ": pending native flags prevented restoring the last native grid")
        end
    else
        module:Disable()
        Check(frame.auraFrames[1].width == 30 and frame.auraFrames[1].Duration.font[2] == 10,
            "disable: native geometry or duration font was not restored")
    end

    if scenario == "cleanup-solver-error" then
        Check(#boundaryErrors == 1 and boundaryErrors[1]:find("fixture cleanup solver failure", 1, true),
            "cleanup did not report precisely the injected solver failure")
    else
        Check(#boundaryErrors == 0, scenario .. ": restoration reported an unexpected native error")
    end
    Check(addonWrites == 0, scenario .. ": Suite invoked the stateful native aura layout")
    Check(frame.AuraContainer.currentGridLayoutInfo == nativeCache,
        scenario .. ": Suite replaced Blizzard's aura layout cache")
    if scenario == "native-layout-change" then
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
Run("disable")
Run("native-layout-change")
Run("consolidation")
Run("native-container-change")
Run("native-frame-change")
Run("status-tray-default")
Run("status-tray-custom")
Run("secret-consolidation")
Run("transient-native-anchor")
Run("pending-native-flags")
Run("pending-native-nil-flag")
Run("disable-missing-icon")
Run("disable-forbidden-icon")
Run("cleanup-solver-error")
Run("disable-forbidden-saved-icon")
assert(#failures == 0, table.concat(failures, "\n"))
print("player aura native cache ownership and downstream damage meter paths: " .. checks .. " checks passed")
