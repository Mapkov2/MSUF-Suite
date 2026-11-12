-- Real host registration and popup (MSUF 7.0 Shell/EditMode): an element with
-- sizeSummary = false (the player aura movers) shows no W/H readout and its
-- rows move up into that line; every other element keeps the readout.
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
w.widgets.Methods.ClearFocus = function(self) self.focused = false end
env.GetCursorPosition = function() return 300, 400 end
env.IsShiftKeyDown = function() return false end
env.IsControlKeyDown = function() return false end
w:LoadGraph("MidnightSimpleUnitFrames", World.Graph(host, World.CoreTOC(w.client.tocSuffix or flavor),
    "enUS", w.client.isForever and "camelot" or nil), ns)
Check(w:FirstFailure() == nil, "core graph failed")
env = assert(loadfile(host .. "/tools/tests/namespace_view.lua"))()(w)
env.MSUF_InitProfiles()
local em, api = env.MSUF_EM2, env.MSUF_EditModeAPI
-- Edit Mode entry without the unit frame engine (as in the chat mover popup contract).
ns.ApplyService.QueueFlush = function() return true end
ns.ApplyService.Flush, ns.ApplyService.Quiesce = function() end, function() end
env.MSUF_UFCore_NotifyConfigChanged = function() return true end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
ns.UF.Apply = function() return true end
local target = env.CreateFrame("Frame", nil, env.UIParent)
target.left, target.bottom, target.width, target.height = 22, 84, 440, 29
local values = { x = 22, y = 84, size = 33 }
local function Register(id, owned, summary)
    local controls = {}
    for i, key in ipairs({ "x", "y", "size" }) do
        controls[i] = { id = key, label = key == "size" and "Icon width" or key:upper(), kind = "number",
            min = -4000, max = 4000, positionAxis = owned and key ~= "size" and key or nil,
            get = function() return values[key] end,
            set = function(value) values[key] = value return true end }
    end
    return api.RegisterElement("SummaryTest", { id = id, label = "Player buffs", sizeSummary = summary,
        getFrame = function() return target end,
        captureState = function() return { x = values.x, y = values.y } end,
        restoreState = function(state) values.x, values.y = state.x, state.y return true end,
        movePosition = function() return true end, extraControls = controls,
        resetPosition = function() return true end })
end
Check(Register("readout", true) == true, "register the default element")
Check(Register("quiet", true, false) == true, "register the opted-out element")
Check(Register("quietgeneric", false, false) == true, "register the opted-out element without owner coordinates")
local ok, reason = Register("broken", true, "no")
Check(ok == false and reason == "invalid_size_summary", "a non-boolean sizeSummary was accepted")
Check(em.State.Enter("player") == true, "edit entry failed")
local function Popup(id)
    Check(em.ExternalPopup.Open("external:summarytest:" .. id) == true, "popup did not open: " .. id)
    for _, frame in ipairs(w.widgets.frames) do
        if frame.frameName == "MSUF_EM2_ExternalPopup" then return frame end
    end
    error("missing popup shell")
end
local function Top(region) return select(5, region:GetPoint()) end

-- Default: the readout line, owner coordinates in the first row (-104).
local f = Popup("readout")
Check(f._summaryFS:IsShown() and f._summaryFS:GetText():find("W ", 1, true) ~= nil, "default readout missing")
Check(Top(f._activeControlSet.rows[1]) == -104, "default owner rows moved")
Check(f:GetHeight() == 304 and Top(f._settingsBtn) == -190, "default popup geometry changed")
local readoutSet = f._activeControlSet

-- Opted out: no readout; rows, buttons and height move up by its line.
f = Popup("quiet")
Check(not f._summaryFS:IsShown() and f._summaryFS:GetText() == "", "the W/H readout is still shown")
Check(f._activeControlSet ~= readoutSet, "the lifted rows reused the default layout")
Check(Top(f._activeControlSet.rows[1]) == -76 and Top(f._activeControlSet.rows[2]) == -116,
    "the rows did not move into the readout line")
Check(f:GetHeight() == 276 and Top(f._settingsBtn) == -162 and Top(f._resetBtn) == -162,
    "the popup kept the readout's height")

-- Opted out without owner coordinates: the generic row moves up as well.
f = Popup("quietgeneric")
Check(f._positionRow:IsShown() and Top(f._positionRow) == -76, "the generic position row stayed below the readout")
Check(Top(f._activeControlSet.rows[1]) == -116, "the controls overlap the lifted position row")

-- Back to the default: everything returns to its place.
f = Popup("readout")
Check(f._summaryFS:IsShown() and Top(f._positionRow) == -104, "the default popup kept the lift")
Check(f._activeControlSet == readoutSet and Top(readoutSet.rows[1]) == -104, "the default rows were moved")
Check(f:GetHeight() == 304, "the default popup kept the lifted height")
Check(em.State.CancelAll() ~= false, "discard failed")
print("Mover popup summary: " .. checks .. " checks passed (" .. flavor .. ")")
