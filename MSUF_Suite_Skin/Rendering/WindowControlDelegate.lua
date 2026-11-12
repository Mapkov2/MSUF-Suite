local _, NS = ...

-- Minimize and the restore tab click Blizzard's own buttons from secure code.
--
-- ShowUIPanel, HideUIPanel and UpdateUIPanelPositions hand a window to the
-- panel manager through SetAttribute on its FramePositionDelegate
-- (Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua, live and
-- forever), and that attribute handler runs inside the call. From the skin's
-- click the manager's pass and the window's OnShow and OnHide ran under the
-- skin's taint, and the next native open read what they wrote (its panel
-- slots; QuestMapFrame_OnHide's DetailsFrame.questID, which the map's quest
-- pins read). WoW Forever's world map then called the protected
-- SetPassThroughButtons for each quest pin from tainted code
-- (MapCanvasMixin:AcquirePin -> CheckMouseButtonPassthrough): an
-- ADDON_ACTION_BLOCKED naming MSUF_Suite_Skin on the next M.
--
-- As the Suite's bag caption does (MSUF_Suite_Bags/BagCaption.lua), one
-- SecureActionButtonTemplate parented to UIParent covers the minimize cell or
-- the restore tab while the pointer rests on it out of combat. Its hardware
-- click makes SecureActionButton_OnClick click the window's X (minimize) or
-- the Blizzard button that opens the window (restore, Policy.Opener). No
-- window turns protected. The cell and the tab keep their own handlers for
-- the clicks the delegate does not take (combat, a window without an opener).
local Delegate = {}
NS.WindowControlDelegate = Delegate

local Safety, Policy = NS.Safety, NS.WindowControlPolicy
-- Our minimize cell or restore tab -> { state, role, prepare, finish }.
local bound = setmetatable({}, { __mode = "k" })
local secure

local function Forward(owner, script, ...)
    local handler = owner and owner:GetScript(script)
    if handler then handler(owner, ...) end
end

-- In combat only the bookkeeping waits: the state driver has hidden it. A
-- drag of the tab ends with it, whichever of the drag and click ends first.
local function Release()
    local owner = secure and secure.owner
    if not owner or NS.IsCombatLocked() then return end
    if secure.dragging then
        secure.dragging = nil
        Forward(owner, "OnDragStop")
    end
    secure.owner = nil
    secure:Hide()
    secure:ClearAllPoints()
    Forward(owner, "OnLeave")
end

local function Target(record)
    if record.role == "minimize" then
        -- The map goes only while Blizzard's map button can bring it back.
        if Policy.SecureOnly(record.state) and not Policy.Opener(record.state) then return nil end
        return record.state.close
    end
    return Policy.Opener(record.state)
end

-- Minimize first does what the skin's own minimize did before its hide (the
-- tab's place, the profession). A window that may not go now gets no click.
-- While Blizzard's click runs the delegate stays: PostClick lets it go.
local function PreClick(button, mouseButton)
    button.clicking = true
    local record = bound[button.owner]
    if not record or record.role ~= "minimize" or mouseButton ~= "LeftButton" then return end
    if not record.prepare(record.state) and not InCombatLockdown() then button:SetAttribute("type1", nil) end
end

-- Blizzard's X kept the window open: no tab. A right click on the tab is the
-- tab's own (it lets the window go).
local function PostClick(button, mouseButton)
    button.clicking = nil
    local owner = button.owner
    local record = bound[owner]
    if record and record.role == "minimize" and record.state.minimized then
        record.finish(record.state)
    elseif record and mouseButton == "RightButton" then
        Forward(owner, "OnClick", mouseButton)
    end
    Release()
end

-- A cell or tab that hid under the pointer (controls off, the window closed).
local function OwnerHidden(owner)
    if secure and secure.owner == owner and not secure.clicking then Release() end
end

-- The tab still moves: the drag is the tab's own and never clicks its opener.
local function DragStart(button)
    local record = bound[button.owner]
    if not record or record.role ~= "restore" or InCombatLockdown() then return end
    button:SetAttribute("type1", nil)
    button.dragging = true
    Forward(button.owner, "OnDragStart")
end

local function DragStop()
    Release()
end

local function Secure()
    if secure then return secure end
    secure = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    secure:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    secure:RegisterForDrag("LeftButton")
    secure:SetAttribute("useOnKeyDown", false)
    secure:SetScript("OnEnter", function(button) Forward(button.owner, "OnEnter") end)
    secure:SetScript("OnLeave", Release)
    secure:SetScript("OnMouseDown", function(button) Forward(button.owner, "OnMouseDown") end)
    secure:SetScript("OnMouseUp", function(button) Forward(button.owner, "OnMouseUp") end)
    secure:SetScript("PreClick", PreClick)
    secure:SetScript("PostClick", PostClick)
    secure:SetScript("OnDragStart", DragStart)
    secure:SetScript("OnDragStop", DragStop)
    secure:Hide()
    RegisterStateDriver(secure, "visibility", "[combat] hide")
    return secure
end

local function Attach(owner)
    local record = bound[owner]
    if not record or NS.IsCombatLocked() or NS.Client.IsGamepadUI() then return end
    local target = Target(record)
    if not target or Safety.IsForbidden(target) then return end
    -- Over the cell or tab, then the Blizzard button its click runs.
    local button = Secure()
    button:ClearAllPoints()
    button:SetAllPoints(owner)
    button:SetFrameStrata(owner:GetFrameStrata())
    button:SetFrameLevel(owner:GetFrameLevel() + 5)
    button:SetAttribute("type1", "click")
    button:SetAttribute("clickbutton1", target)
    button.owner = owner
    button:Show()
end

local function Bind(owner, state, role, prepare, finish)
    if not owner or bound[owner] then return end
    bound[owner] = { state = state, role = role, prepare = prepare, finish = finish }
    owner:HookScript("OnEnter", Attach)
    owner:HookScript("OnHide", OwnerHidden)
end

-- prepare(state): minimize's bookkeeping, false when the window may not go now.
-- finish(state): after Blizzard's X ran, the tab or nothing.
function Delegate.Bind(state, prepare, finish)
    Bind(state.minimize, state, "minimize", prepare, finish)
    Bind(state.restore, state, "restore")
end

return Delegate
