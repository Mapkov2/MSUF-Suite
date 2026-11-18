-- Native container geometry uses its real parent scale and preserves bag input.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_window_controls_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))', 1, true))
local fixture = source:sub(1, stop - 1) .. [[
return { NS = NS, Frame = Frame, frames = createdFrames, jobs = combatJobs, panelSlots = panelSlots,
    NextFrame = NextFrame, reported = reported }
]]
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
local names = { "BankFrame", "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2",
    "ContainerFrame3", "ContainerFrame4", "ContainerFrame5", "ContainerFrame6" }

for _, flavor in ipairs({ "Mainline", "Forever" }) do
    _G.combat, _G.combatEdge = false, false
    local H = assert(loadstring(fixture, "@native_inventory_fixture"))()
    local NS, Frame = H.NS, H.Frame
    NS.Client.isForever = flavor == "Forever"
    C_Texture = { GetAtlasInfo = function(atlas) return atlas == "common-sidetab" and { width = 72 } or nil end }
    NS.DB.theme = { look = "midnight" }
    MSUFSuite = { Suite = { OwnsBlizzardSurface = function() return false end } }
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/SuiteOwnership.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/Catalog.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/CatalogGlass.lua"))("MSUF_Suite_Skin", NS)
    NS.CombatGate.Cancel = function(key) H.jobs[key] = nil end
    UIParent.scale = 0.8
    FullscreenFrame = Frame("FullscreenFrame", UIParent)
    FullscreenFrame.scale = 1.25
    function FullscreenFrame:GetEffectiveScale() return self.scale * UIParent:GetEffectiveScale() end

    -- Anchor rectangles in physical pixels. All anchors are retained, so an
    -- obsolete opposite-edge anchor cannot be hidden by the last SetPoint call.
    local Bounds
    local function Anchor(rect, point)
        local x = point:find("LEFT") and rect[1] or point:find("RIGHT") and rect[3] or (rect[1] + rect[3]) / 2
        local y = point:find("BOTTOM") and rect[2] or point:find("TOP") and rect[4] or (rect[2] + rect[4]) / 2
        return x, y
    end
    Bounds = function(frame)
        if frame == UIParent or frame == FullscreenFrame then
            local scale = UIParent:GetEffectiveScale()
            return { 0, 0, UIParent.width * scale, UIParent.height * scale }
        end
        local scale = frame:GetEffectiveScale()
        local width, height = frame.width * scale, frame.height * scale
        local left, bottom, right, top
        for _, point in ipairs(frame.anchors or {}) do
            local x, y = Anchor(Bounds(point[2]), point[3])
            x, y = x + point[4] * scale, y + point[5] * scale
            if point[1]:find("LEFT") then left = x elseif point[1]:find("RIGHT") then right = x else left = x - width / 2 end
            if point[1]:find("BOTTOM") then bottom = y elseif point[1]:find("TOP") then top = y else bottom = y - height / 2 end
        end
        left = left or (right and right - width) or frame.left * scale
        bottom = bottom or (top and top - height) or (frame.top - frame.height) * scale
        return { left, bottom, right or left + width, top or bottom + height }
    end
    local function Instrument(frame)
        local setPoint, clear = frame.SetPoint, frame.ClearAllPoints
        frame.anchors = {}
        function frame:GetEffectiveScale()
            return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1)
        end
        function frame:SetPoint(point, relative, relativePoint, x, y)
            setPoint(self, point, relative, relativePoint, x, y)
            for _, anchor in ipairs(self.anchors) do
                if anchor[1] == point then
                    anchor[2], anchor[3], anchor[4], anchor[5] = relative, relativePoint, x or 0, y or 0
                    return
                end
            end
            self.anchors[#self.anchors + 1] = { point, relative, relativePoint, x or 0, y or 0 }
        end
        function frame:ClearAllPoints() clear(self); self.anchors = {} end
        function frame:GetNumPoints() return #self.anchors end
        function frame:GetPoint(index) return unpack(self.anchors[index or 1]) end
        function frame:GetLeft() return Bounds(self)[1] / self:GetEffectiveScale() end
        function frame:GetBottom() return Bounds(self)[2] / self:GetEffectiveScale() end
        function frame:GetRight() return Bounds(self)[3] / self:GetEffectiveScale() end
        function frame:GetTop() return Bounds(self)[4] / self:GetEffectiveScale() end
        return frame
    end
    local nativeCreate = CreateFrame
    CreateFrame = function(...) return Instrument(nativeCreate(...)) end
    local panels = {}
    local function NativeAnchor(frame)
        local point = frame.name == "BankFrame"
            and { "TOPLEFT", UIParent, "TOPLEFT", 30, -90 }
            or { "BOTTOMRIGHT", FullscreenFrame, "BOTTOMRIGHT", -15, 15 }
        -- Blizzard can update its own protected roots during combat.
        frame.scale, frame.anchors, frame.point = 1, { point }, point
    end
    UpdateContainerFrameAnchors = function()
        for _, frame in ipairs(panels) do
            if frame.name ~= "BankFrame" and frame.shown then NativeAnchor(frame) end
        end
    end
    local nativeHook = hooksecurefunc
    hooksecurefunc = function(name, callback, method)
        if name ~= "UpdateContainerFrameAnchors" then return nativeHook(name, callback, method) end
        local original = _G[name]
        _G[name] = function(...) original(...); callback(...) end
    end
    assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))("MSUF_Suite_Skin", NS)
    local W = NS.WindowControls
    local function Intersects(a, b)
        return a[1] < b[3] and a[3] > b[1] and a[2] < b[4] and a[4] > b[2]
    end
    local function VisibleChrome(frame, state)
        local bounds, viewport = Bounds(frame), Bounds(UIParent)
        for _, control in ipairs({ state.grip, state.titleDrag }) do
            local rect = Bounds(control)
            Check(rect[1] >= viewport[1] and rect[2] >= viewport[2]
                and rect[3] <= viewport[3] and rect[4] <= viewport[4], frame.name .. " control outside viewport")
            if frame.name ~= "BankFrame" then
                Check(not Intersects(rect, bounds), frame.name .. " skin control covers native title/portrait/search/item input")
            end
        end
        Check(#state.grip.anchors == 1 and #state.titleDrag.anchors == 2, frame.name .. " retains stale chrome anchors")
    end
    for _, name in ipairs(names) do
        local parent = name == "BankFrame" and UIParent or FullscreenFrame
        local frame = Instrument(Frame(name, parent))
        panels[#panels + 1], _G[name] = frame, frame
        frame.width, frame.height = 400, 500
        frame.NineSlice = Frame(nil, frame)
        frame.NineSlice.frameLevel = 500
        frame.CloseButton = Frame(nil, frame, "Button")
        if name == "BankFrame" then
            Instrument(frame.CloseButton):SetSize(28, 28)
            frame.CloseButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 3)
        end
        frame.TitleContainer = Frame(nil, frame)
        frame.TitleContainer.OnMouseDown = function() frame.nativeMenuOpened = true end
        UIPanelWindows[name] = name == "BankFrame" and { area = "left" } or nil
        NativeAnchor(frame)
        frame.protected = true
        NS.DB.windowControls.scales[name] = 0.9
        Check(W.Attach(frame, "inventory"), flavor .. " implicit native " .. name .. " rejected outside combat")
        local state = assert(W.states[frame])
        Check(frame.parent == parent and state.grip.parent == frame and state.titleDrag.parent == frame,
            name .. " changed native parenting")
        Check(frame.scale == 0.9 and NS.DB.windowControls.positions[name] == nil,
            name .. " scale-only attachment created a custom position")
        VisibleChrome(frame, state)
        frame.TitleContainer.OnMouseDown()
        Check(frame.nativeMenuOpened, name .. " native title dropdown input was replaced")
    end
    if flavor == "Forever" then
        local bank, state = BankFrame, W.states[BankFrame]
        local nativeCloses = 0
        bank:HookScript("OnHide", function()
            if H.panelSlots.left == bank then H.panelSlots.left = nil end
            nativeCloses = nativeCloses + 1
        end)
        function bank:IsClampedToScreen() return self.clamped == true end
        bank:SetClampedToScreen(true)
        Check(state.closeCell and state.closeCell:IsShown() and bank.CloseButton:GetAlpha() == 0
            and state.minimize:IsShown() and state.maximize:IsShown(), "Forever bank did not get the Suite caption")
        Check(NS.WindowControlChrome.Footprint(state) == 72, "bank fit omitted the native side tabs")
        local native, scale = bank.anchors[1], bank.scale
        state.maximize.scripts.OnClick(state.maximize)
        Check(state.fit and bank.anchors[1][1] == "CENTER", "bank maximize did not fit the window")
        state.maximize.scripts.OnClick(state.maximize)
        Check(not state.fit and bank.scale == scale and bank.anchors[1][4] == native[4], "bank restore lost its geometry")
        local function Minimize()
            state.minimize.scripts.OnClick(state.minimize)
            Check(state.restore:IsShown() and bank:IsShown() and not bank:IsClampedToScreen()
                and Bounds(bank)[4] < 0, "bank minimize closed the session or left the window in the viewport")
        end
        Minimize()
        UpdateUIPanelPositions(bank)
        W.Refresh()
        Check(Bounds(bank)[4] < 0 and state.restore:IsShown(), "native layout or refresh lost the bank's minimized state")
        state.restore.scripts.OnClick(state.restore, "LeftButton")
        Check(not state.restore:IsShown() and bank:IsShown() and bank:IsClampedToScreen()
            and Bounds(bank)[4] > 0 and nativeCloses == 0, "bank restore restarted the session or lost clamping")
        Minimize()
        state.restore.scripts.OnClick(state.restore, "RightButton")
        Check(not state.restore:IsShown() and Bounds(bank)[4] > 0, "the restore tab discarded a live minimized bank")

        Minimize()
        _G.combatEdge = true
        bank:Hide() -- The native interaction can end while minimized, including in combat.
        H.NextFrame()
        Check(not state.restore:IsShown() and nativeCloses == 1, "ending the native bank interaction left a restore tab")
        _G.combatEdge = false
        for key, job in pairs(H.jobs) do H.jobs[key] = nil; job() end
        Check(bank:IsClampedToScreen() and Bounds(bank)[4] > 0, "closing in combat did not restore bank geometry later")
        bank:Show()
        H.NextFrame()
        Minimize()
        W.SetEnabled(false)
        Check(not state.restore:IsShown() and Bounds(bank)[4] > 0 and bank.CloseButton:GetAlpha() == 1,
            "disabling controls stranded a minimized bank")
        NS.DB.windowControls.enabled = true
        W.Refresh()
        bank.CloseButton:SetScript("OnClick", function() bank:Hide() end)
        Check(state.closeCell:GetScript("OnClick") == nil, "the drawn X took the native close click")
        bank.CloseButton.scripts.OnClick(bank.CloseButton)
        Check(not bank:IsShown() and nativeCloses == 2, "the Suite X failed to keep Blizzard's close path")
        bank:Show()
    end
    for index = 2, #panels do
        local frame = panels[index]
        local state = W.states[frame]
        Check(state.minimize and state.minimize:IsShown(), frame.name .. " lost the native inventory minimize")
        state.minimize.scripts.OnClick(state.minimize)
        UpdateContainerFrameAnchors()
        Check(frame:IsShown() and state.restore:IsShown() and Bounds(frame)[4] < 0,
            frame.name .. " minimize disturbed the native bag or did not survive relayout")
        state.restore.scripts.OnClick(state.restore, "LeftButton")
        Check(frame:IsShown() and not state.restore:IsShown() and Bounds(frame)[4] > 0,
            frame.name .. " restore did not return the same native bag")
    end
    UpdateContainerFrameAnchors()
    for index = 2, #panels do
        local frame = panels[index]
        Check(frame.scale == 0.9 and frame.anchors[1][1] == "BOTTOMRIGHT"
            and frame.anchors[1][2] == FullscreenFrame and frame.anchors[1][4] == -15,
            frame.name .. " scale-only native layout failed or replaced the native anchor")
    end
    -- A native combat layout can occur without any new adapter Attach call.
    -- Its temporary protection refusal must not drop a still-visible bag.
    _G.combatEdge = true
    UpdateContainerFrameAnchors()
    _G.combatEdge = false
    UpdateContainerFrameAnchors()
    for index = 2, #panels do
        Check(panels[index].scale == 0.9, panels[index].name .. " disappeared from native layout recovery after combat")
    end
    local bag, state = panels[2], W.states[panels[2]]
    cursorX, cursorY = 500, 500
    state.grip.scripts.OnMouseDown(state.grip, "LeftButton")
    cursorX, cursorY = 620, 500
    state.grip.scripts.OnUpdate(state.grip)
    local expected = math.floor((0.9 + 60 / (500 * FullscreenFrame:GetEffectiveScale())) * 100 + 0.5) / 100
    Check(bag.scale == expected, "scale drag ignored the actual native parent's physical pixel scale")
    state.grip.scripts.OnMouseUp(state.grip)
    Check(not state.grip.scripts.OnUpdate, "released bag scaling left an updater")
    -- Both combat entry and native layout must respect inherited protection.
    local writes = {}
    for _, frame in ipairs(panels) do writes[frame] = frame.geometryWrites end
    _G.combatEdge = true
    for _, frame in ipairs(panels) do
        Check(not W.Attach(frame, "inventory"), frame.name .. " protected combat attachment succeeded")
        local controls = W.states[frame]
        controls.grip.scripts.OnMouseDown(controls.grip, "LeftButton")
        Check(not controls.grip.scripts.OnUpdate and frame.geometryWrites == writes[frame],
            frame.name .. " started protected combat scaling")
    end
    UpdateContainerFrameAnchors()
    for _, frame in ipairs(panels) do
        Check(frame.geometryWrites == writes[frame], frame.name .. " native layout hook wrote protected geometry")
    end
    _G.combatEdge = false
    for key, callback in pairs(H.jobs) do H.jobs[key] = nil; callback() end
    W.Refresh()
    -- Exact global identity is required; arbitrary similarly named frames are not windows.
    Check(not W.Attach(Instrument(Frame("ContainerFrame1", FullscreenFrame)), "foreign"),
        "a foreign frame using a native bag name gained geometry controls")
    local explicit = panels[3]
    explicit.explicitProtected = true
    Check(not W.Attach(explicit, "inventory"), "explicitly protected inventory root gained controls")
    explicit.explicitProtected = false
    -- Native bags stack with an 8px vertical gutter and use 11px between
    -- columns. Both handles must fit that gap without covering a neighbour.
    for index = 2, #panels do
        local frame = panels[index]
        local rect, scale = Bounds(frame), frame:GetEffectiveScale()
        local width, height = rect[3] - rect[1], rect[4] - rect[2]
        local neighbours = {
            { rect[1], rect[4] + 8 * scale, rect[3], rect[4] + 8 * scale + height },
            { rect[1], rect[2] - 8 * scale - height, rect[3], rect[2] - 8 * scale },
            { rect[1] - 11 * scale - width, rect[2], rect[1] - 11 * scale, rect[4] },
            { rect[3] + 11 * scale, rect[2], rect[3] + 11 * scale + width, rect[4] },
        }
        local controls = W.states[frame]
        for _, control in ipairs({ controls.titleDrag, controls.grip }) do
            local hit = Bounds(control)
            for _, neighbour in ipairs(neighbours) do
                Check(not Intersects(hit, neighbour), frame.name .. " handle overlaps a native adjacent bag")
            end
            Check(hit[1] >= rect[1] and hit[3] <= rect[3] and hit[4] - hit[2] <= 6.01 * scale,
                frame.name .. " handle exceeds the native bag gutter")
        end
    end
    -- The native right/bottom edge and the top edge select exterior chrome
    -- positions that never clamp back over the native dropdown/header.
    for _, anchor in ipairs({ { "BOTTOMRIGHT", FullscreenFrame, "BOTTOMRIGHT", 0, 0 },
        { "TOPLEFT", FullscreenFrame, "TOPLEFT", 0, 0 } }) do
        bag.anchors, bag.point = { anchor }, anchor
        W.Refresh()
        VisibleChrome(bag, state)
    end
    local count = #H.frames
    for _, frame in ipairs(panels) do frame:Hide() end
    local hiddenReads = 0
    for _, frame in ipairs(panels) do
        frame.IsShown = function() hiddenReads = hiddenReads + 1; return false end
        frame.GetScale = function() hiddenReads = hiddenReads + 1; return frame.scale end
        frame.GetEffectiveScale = function() hiddenReads = hiddenReads + 1; return 1 end
    end
    for _ = 1, 100 do UpdateContainerFrameAnchors(); UpdateUIPanelPositions(); H.NextFrame() end
    Check(hiddenReads == 0 and #H.frames == count and next(H.jobs) == nil,
        "native container callbacks revisited closed inventory or scheduled idle work: reads=" .. hiddenReads
            .. " created=" .. (#H.frames - count) .. " job=" .. tostring(next(H.jobs)))
    Check(#H.reported == 0, "inventory callbacks reported errors: " .. table.concat(H.reported, "; "))
    for _, name in ipairs(names) do _G[name] = nil end
end
print("suite_window_controls_inventory_contract: " .. checks .. " checks passed")
