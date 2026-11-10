local _, P = ...
local S, Interaction = P.S, P.PreviewInteraction
local Header, Model = S.CharacterHeader, P.Suite.CharacterTabs
local Handles = {}
Handles.__index = Handles
P.CharacterPreviewHandles = Handles

local ID, OWN = "characterPanel", "own"
local FIELD, TAB = "field", "tab"
local DRAG_RAISE = 8

local function TabKind(handles)
    return handles.ui.mode == OWN and TAB or "inspectTab"
end

local function TabOrderKey(handles)
    return handles.ui.mode == OWN and "tabOrder" or "inspectTabOrder"
end

local function HiddenTabKey(handles)
    return handles.ui.mode == OWN and "hiddenTabs" or "hiddenInspectTabs"
end

local function PositionsTab(handles, button)
    return button.group == TAB and button.spec.custom and handles.ui.mode == OWN and handles.positionMode
end

local function SavedOffsets(handles, button, config)
    if button.group == FIELD then return config[button.xKey] or 0, config[button.yKey] or 0 end
    if PositionsTab(handles, button) then return Model.Position(Model.Find(config, button.spec.id)) end
    return 0, 0
end

local function DrawnOffsets(handles, button)
    if button.group == FIELD then return button.x - button.baseX, button.baseY - button.y end
    if PositionsTab(handles, button) then return Model.Position(button.spec) end
    return 0, 0
end

local function Geometry(button)
    if button.group == FIELD then return button.x, button.y, button.width, button.height end
    return button.panelX, button.panelY, button.panelWidth, button.panelHeight
end

local function CanUse(handles, button)
    if not button:IsVisible() then return false end
    if button.group == FIELD then return button.baseX ~= nil end
    return button.id == button.spec.id and handles.tabs[button.id] == button
end

local function IsCurrent(handles, button, config)
    local claim = handles.claim
    if not claim or not CanUse(handles, button) or not claim.profile() or claim.config ~= config
        or claim.mode ~= handles.ui.mode or claim.positionMode ~= handles.positionMode
        or claim.spec ~= button.spec or claim.scale ~= button:GetEffectiveScale() then return false end
    local x, y, width, height = Geometry(button)
    if x ~= claim.left or y ~= claim.top or width ~= claim.width or height ~= claim.height then return false end
    if button.group == TAB then
        local view = handles.view
        return view.tabs == claim.order and view.visibleTabs == claim.visibleTabs and view.promotedTab == claim.promotedTab
            and view.fontRevision == claim.fontRevision and config[TabOrderKey(handles)] == claim.savedOrder
            and config[HiddenTabKey(handles)] == claim.hiddenTabs
            and (claim.mode ~= OWN or (config.customTabs == claim.customTabs
                and config.showAttributesTab == claim.showAttributes))
    end
    local savedX, savedY = SavedOffsets(handles, button, config)
    local header = handles.view.header
    return savedX == claim.savedX and savedY == claim.savedY and button.baseX == claim.baseX
        and button.baseY == claim.baseY and header.width == claim.headerWidth and header.rightReserve == claim.rightReserve
end

local function Outline(handles, button)
    if not button then return end
    Interaction.Outline(button, CanUse(handles, button)
        and (button.previewHover == true or handles.kit:Selected() == button or handles.drop == button))
end

local function SetDrop(handles, target)
    if handles.drop == target then return end
    local previous = handles.drop
    handles.drop = target
    Outline(handles, previous)
    Outline(handles, target)
end

local function DropTarget(handles, button, dx, dy)
    local x = button.panelX + button.panelWidth / 2 + dx
    local y = button.panelY + button.panelHeight / 2 - dy
    for _, spec in ipairs(handles.order) do
        local target = handles.tabs[spec.id]
        if target and target ~= button and x >= target.panelX and x <= target.panelX + target.panelWidth
            and y >= target.panelY and y <= target.panelY + target.panelHeight then return target end
    end
end

local function Neighbor(handles, button, dx, dy)
    local delta = dx ~= 0 and dx or -dy
    if delta == 0 then return end
    for index, entry in ipairs(handles.order) do
        if entry.id == button.spec.id then return handles.order[index + (delta < 0 and -1 or 1)] end
    end
end

local function WriteTabPosition(button, config, x, y)
    x, y = Model.ClampPosition(TAB, x, y)
    local tabs = Model.Copy(config)
    for _, tab in ipairs(tabs) do
        if tab.id == button.spec.id then
            if tab.x == x and tab.y == y then return false end
            tab.x, tab.y = x, y
            local encoded = Model.Encode(tabs)
            return encoded ~= nil and P.Set(ID, "customTabs", encoded) ~= false
        end
    end
    return false
end

local function WriteOffsets(handles, button, x, y, dragged)
    local config = S.Config(ID)
    if P.Combat() or not CanUse(handles, button) or (dragged and not IsCurrent(handles, button, config)) then return false end
    if button.group == TAB then
        if PositionsTab(handles, button) then return WriteTabPosition(button, config, x, y) end
        local target
        if dragged then
            local drop = DropTarget(handles, button, x, y)
            target = drop and drop.spec
        else
            target = Neighbor(handles, button, x, y)
        end
        local order = target and Header.Move(config, TabKind(handles), button.spec.id, target.id)
        local key = TabOrderKey(handles)
        return order ~= nil and order ~= config[key] and P.Set(ID, key, order) ~= false
    end
    x, y = Header.DragOffsets(handles.view.header, button.spec.id, math.floor(x + .5), math.floor(y + .5))
    local oldX, oldY = SavedOffsets(handles, button, config)
    if x == oldX and y == oldY then return false end
    return P.SetMany(ID, { [button.xKey] = x, [button.yKey] = y }) ~= false
end

local function Place(button, left, top)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", left, -top)
end

local function Restore(handles, button)
    local claim = handles.claim
    if not claim then return end
    if claim.drawX ~= 0 or claim.drawY ~= 0 then
        local left, top = Geometry(button)
        Place(button, left, top)
        claim.drawX, claim.drawY = 0, 0
    end
    if claim.raised then
        button:SetFrameLevel(claim.level)
        claim.raised = nil
    end
    SetDrop(handles)
end

local function Follow(handles, button, dx, dy)
    local claim = handles.claim
    if not claim or not handles.kit.drag then return end
    if not IsCurrent(handles, button, S.Config(ID)) then
        handles.kit:Cancel()
        return
    end
    if button.group == FIELD then
        local x, y = Header.DragOffsets(handles.view.header, button.spec.id, claim.x + dx, claim.y + dy)
        dx, dy = x - claim.x, y - claim.y
    elseif PositionsTab(handles, button) then
        local x, y = Model.ClampPosition(TAB, claim.x + dx, claim.y + dy)
        dx, dy = x - claim.x, y - claim.y
    else
        SetDrop(handles, DropTarget(handles, button, dx, dy))
    end
    if claim.drawX == dx and claim.drawY == dy then return end
    claim.drawX, claim.drawY = dx, dy
    Place(button, claim.left + dx, claim.top - dy)
end

local function Claim(handles, button)
    local view, config = handles.view, S.Config(ID)
    local savedX, savedY = SavedOffsets(handles, button, config)
    local x, y = DrawnOffsets(handles, button)
    local left, top, width, height = Geometry(button)
    handles.claim = {
        profile = P.ProfileGuard(), config = config, mode = handles.ui.mode, positionMode = handles.positionMode,
        spec = button.spec, order = view.tabs, savedOrder = config[TabOrderKey(handles)], customTabs = config.customTabs,
        hiddenTabs = config[HiddenTabKey(handles)], showAttributes = config.showAttributesTab,
        visibleTabs = view.visibleTabs, promotedTab = view.promotedTab,
        fontRevision = view.fontRevision, scale = button:GetEffectiveScale(),
        left = left, top = top, width = width, height = height, baseX = button.baseX, baseY = button.baseY,
        headerWidth = view.header.width, rightReserve = view.header.rightReserve,
        x = x, y = y, savedX = savedX, savedY = savedY, drawX = 0, drawY = 0, level = button:GetFrameLevel(),
    }
    button.previewCancelled = nil
end

local function Drag(handles, button, phase)
    if phase == "press" then
        handles.kit:Select(button)
        Claim(handles, button)
    elseif phase == "start" and handles.claim then
        handles.claim.raised = true
        button:SetFrameLevel(handles.claim.level + DRAG_RAISE)
    elseif phase == "stop" or phase == "cancel" then
        Restore(handles, button)
        if phase == "cancel" then
            handles.claim = nil
            button.previewCancelled = true
        end
    elseif phase == "done" then
        handles.claim = nil
    end
end

local function Bind(handles, button, group, spec)
    button.group, button.spec = group, spec
    if group == FIELD then button.xKey, button.yKey = spec.prefix .. "X", spec.prefix .. "Y" end
    handles.kit:Add(button, button, function() return DrawnOffsets(handles, button) end,
        function(x, y, dragged) return WriteOffsets(handles, button, x, y, dragged) end, {
            select = false,
            can = function() return CanUse(handles, button) end,
            follow = function(_, dx, dy) Follow(handles, button, dx, dy) end,
            clicks = { "LeftButtonUp" },
        })
    P.HM.SkipHistoryCheckpoint(button)
end

function Handles.Create(ui, preview, selectTab, openField, refresh, onSelection)
    local view = preview.view
    local handles = setmetatable({ ui = ui, view = view, tabs = {} }, Handles)
    local host = P.Suite.PreviewKit.NewHost(nil, {
        frame = view.frame,
        paint = function(_, reason) if reason == "commit" then refresh() end end,
    })
    handles.kit = Interaction.Handles(host, {
        pixels = true, threshold = 4, manualDrag = true,
        pointerHeld = function() return IsMouseButtonDown("LeftButton") end,
        click = function(button, mouse, moved)
            if moved or button.previewCancelled or mouse ~= "LeftButton" or P.Combat() or not CanUse(handles, button) then return end
            handles.kit:Select(button)
            if button.group == FIELD then openField(button.spec) else selectTab(button.spec.id) end
        end,
        tip = function(button, entering)
            button.previewHover = entering
            Outline(handles, button)
        end,
        drag = function(button, phase) Drag(handles, button, phase) end,
        mark = function(button) Outline(handles, button) end,
        select = onSelection,
    })
    for _, field in ipairs(Header.Fields) do Bind(handles, view.header.buttons[field.id], FIELD, field) end
    return handles
end

function Handles:Refresh(order, positionMode)
    self.order, self.positionMode = order, positionMode == true
    local kit, view = self.kit, self.view
    if kit.drag and (P.Combat() or not IsCurrent(self, kit.drag.entry.region, S.Config(ID))) then kit:Cancel() end
    local previous = kit:Selected()
    local tabID = previous and previous.group == TAB and previous.spec.id
    wipe(self.tabs)
    for index, spec in ipairs(order) do
        local button = view.tabButtons[index]
        if button:IsVisible() then
            if button.spec ~= spec then
                if not button.spec then Bind(self, button, TAB, spec) else button.spec = spec end
            end
            self.tabs[spec.id] = button
        end
    end
    local selected = tabID and self.tabs[tabID] or (not tabID and previous)
    if selected ~= previous or selected and not CanUse(self, selected) then
        kit:Select(selected and CanUse(self, selected) and selected or nil)
    end
end

function Handles:Cancel()
    self.kit:Cancel()
end

function Handles:Release()
    self.kit:Release()
end

function Handles:SelectField(id)
    local button = self.view.header.buttons[id]
    if button and CanUse(self, button) then self.kit:Select(button) end
end

function Handles:SelectTab(id)
    local button = self.tabs[id]
    if button and CanUse(self, button) then self.kit:Select(button) end
end

function Handles:Selected()
    return self.kit:Selected()
end

function Handles:Nudge(dx, dy)
    return self.kit:Nudge(dx, dy)
end
