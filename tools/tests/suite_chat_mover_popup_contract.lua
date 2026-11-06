-- Real host registration and popup: owner coordinates replace the generic row.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local host = arg[3] or root .. "/../MidnightSimpleUnitFrames-7.0"
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(host .. "/tools/tests/client_world.lua"))()
local w = World.New(host, flavor)
local env, ns = w.env, w.core
local checks = 0
local function Check(ok, message) assert(ok, message) checks = checks + 1 end
for _, name in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetNumeric", "SetTextInsets",
    "SetMaxLetters", "SetCursorPosition", "HighlightText", "SetAutoFocus" }) do
    w.widgets.Methods[name] = function() end
end
w.widgets.Methods.HasFocus = function(self) return self.focused == true end
w.widgets.Methods.ClearFocus = function(self)
    local focused = self.focused
    self.focused = false
    if focused and self:GetScript("OnEditFocusLost") then self:GetScript("OnEditFocusLost")(self) end
end
local oldHide = w.widgets.Methods.Hide
w.widgets.Methods.Hide = function(self)
    -- Native child edit boxes lose focus when their row is hidden.
    for _, child in ipairs({ self:GetChildren() }) do
        if child:HasFocus() then child:ClearFocus() end
    end
    return oldHide(self)
end
env.GetCursorPosition = function() return 300, 400 end
env.IsShiftKeyDown = function() return false end
env.IsControlKeyDown = function() return false end
w:LoadGraph("MidnightSimpleUnitFrames", World.Graph(host, World.CoreTOC(w.client.tocSuffix or flavor),
    "enUS", w.client.isForever and "camelot" or nil), ns)
Check(w:FirstFailure() == nil, "core graph failed")
env = assert(loadfile(host .. "/tools/tests/namespace_view.lua"))()(w)
env.MSUF_InitProfiles()
local em, api = env.MSUF_EM2, env.MSUF_EditModeAPI
ns.ApplyService.QueueFlush = function() return true end
ns.ApplyService.Flush, ns.ApplyService.Quiesce = function() end, function() end
env.MSUF_UFCore_NotifyConfigChanged = function() return true end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
ns.UF.Apply = function() return true end
local target = env.CreateFrame("Frame", nil, env.UIParent)
target.left, target.bottom, target.width, target.height = 22, 84, 496, 148
local values, writes = { x = 22, y = 84 }, 0
local function Register(id, axes)
    local controls = {}
    for i, key in ipairs({ "x", "y" }) do
        controls[i] = { id = key, label = key:upper(), kind = "number", min = -4000, max = 4000,
            positionAxis = axes and axes[i], get = function() return values[key] end,
            set = function(value) writes = writes + 1 values[key] = value return true end }
    end
    Check(api.RegisterElement("ChatTest", { id = id, label = "Chat window", getFrame = function() return target end,
        captureState = function() return { x = values.x, y = values.y } end,
        restoreState = function(state) values.x, values.y = state.x, state.y return true end,
        movePosition = function() writes = writes + 1 return true end, extraControls = controls,
        resetPosition = function() values.x, values.y = 12, 12 return true end }) == true, "register " .. id)
    return "external:chattest:" .. id
end
local owned = Register("owned", { "x", "y" })
local generic = Register("generic")
local partial = Register("partial", { "x", "invalid" })
Check(em.State.Enter("player") == true, "edit entry failed")
local function Popup(key)
    Check(em.ExternalPopup.Open(key) == true, "popup did not open")
    for _, frame in ipairs(w.widgets.frames) do
        if frame.frameName == "MSUF_EM2_ExternalPopup" then return frame end
    end
    error("missing popup shell")
end
local f = Popup(owned)
Check(not f._positionRow:IsShown(), "duplicate coordinate row remains")
Check(f:GetHeight() == 264, "owner popup retains empty row space")
Check(select(5, f._activeControlSet.rows[1]:GetPoint()) == -104, "owner controls not moved into first row")
local ownerSet = f._activeControlSet
Check(ownerSet.numbers[1].box:GetText() == "22" and ownerSet.numbers[2].box:GetText() == "84", "wrong owner coordinates")
local xBox = ownerSet.numbers[1].box
xBox:SetText("60")
xBox:GetScript("OnEnterPressed")(xBox)
Check(values.x == 60 and values.y == 84 and writes == 1, "typed owner coordinate was not one write")
Check(em.Undo.DoUndo() == true and values.x == 22, "owner coordinate undo failed")
Check(em.Undo.DoRedo() == true and values.x == 60, "owner coordinate redo failed")
f = Popup(generic)
Check(f._positionRow:IsShown() and f:GetHeight() == 304, "generic popup lost position row")
Check(f._activeControlSet ~= ownerSet, "different coordinate metadata reused cached rows")
Check(select(5, f._activeControlSet.rows[1]:GetPoint()) == -144, "generic controls overlap position row")
f.xBox.focused = true
f.xBox:SetText("999")
local before = writes
local positionCalls, setPosition = 0, em.Ticker.SetExternalPosition
em.Ticker.SetExternalPosition = function(...)
    positionCalls = positionCalls + 1
    return setPosition(...)
end
f = Popup(owned)
Check(writes == before, "switching owner committed hidden generic coordinate")
Check(positionCalls == 0, "switching owner submitted hidden generic coordinate")
Check(not f.xBox:HasFocus() and not f._positionRow:IsShown(), "hidden generic coordinate retains focus")
Check(f._activeControlSet == ownerSet, "owner cache not reused")
ownerSet.numbers[1].box.focused = true
ownerSet.numbers[1].box:SetText("888")
f = Popup(partial)
Check(writes == before, "switching owner committed hidden owner coordinate")
Check(f._positionRow:IsShown(), "incomplete owner pair suppresses generic position")
Check(em.ExternalElements.GetControls(partial)[2].positionAxis == nil, "invalid coordinate metadata survived registration")
f = Popup(owned)
Check(em.State.CancelAll() ~= false, "discard failed")
Check(values.x == 22 and values.y == 84, "discard lost initial owner position")
print("Chat mover popup: " .. checks .. " checks passed (" .. flavor .. ")")
