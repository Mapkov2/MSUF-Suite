-- Real MSUF host: dynamic anchor choices, scrollable popup and full history.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local host, flavor = arg[3] or root .. "/../MidnightSimpleUnitFrames-7.0", arg[2] or "Mainline"
local World = assert(loadfile(host .. "/tools/tests/client_world.lua"))()
local w = World.New(host, flavor)
local env, ns = w.env, w.core
local checks = 0
local function Check(ok, message) checks = checks + 1 assert(ok, message) end
for _, name in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetNumeric", "SetTextInsets",
    "SetMaxLetters", "SetCursorPosition", "HighlightText", "SetAutoFocus" }) do w.widgets.Methods[name] = function() end end
w.widgets.Methods.HasFocus = function(self) return self.focused == true end
w.widgets.Methods.ClearFocus = function(self) self.focused = false end
w.widgets.Methods.SetVerticalScroll = function(self, value) self.verticalScroll = value end
w.widgets.Methods.GetVerticalScroll = function(self) return self.verticalScroll or 0 end
w.widgets.Methods.SetScrollChild = function(self, child) self.scrollChild = child end
env.GetCursorPosition = function() return 300, 400 end
env.IsShiftKeyDown, env.IsControlKeyDown = function() return false end, function() return false end
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
target.left, target.bottom, target.width, target.height = 22, 84, 300, 30
local value, values, reject, choiceReads = "", {{value="",text="Screen"}}, false, 0
for i = 1, 40 do values[#values+1] = {value="anchor"..i,text="Anchor "..i} end
local function Register(id, provider)
    return api.RegisterElement("AnchorChoice", { id = id, label = "Buff reminders", getFrame = function() return target end,
        captureState = function() return { anchor = value } end,
        restoreState = function(state) value = state.anchor return true end,
        movePosition = function() return true end,
        extraControls = {{id="anchor",label="Attach to",kind="choice",values=provider,
            get=function() return value end, set=function(v) value = v return not reject end}} })
end
Check(api.GetCapabilities().choiceControls == true, "choice support is not advertised")
Check(Register("buffs", function() choiceReads = choiceReads + 1 return values end) == true, "choice control registration failed")
local ok, reason = Register("invalid", {})
Check(ok == false and reason == "invalid_control_values", "invalid choice provider was accepted")
Check(em.State.Enter("player") == true, "edit mode entry failed")
local key = "external:anchorchoice:buffs"
Check(em.ExternalPopup.Open(key) == true, "choice popup failed")
local popup
for _, f in ipairs(w.widgets.frames) do if f._key == key and f._activeControlSet then popup = f end end
Check(popup and #popup._activeControlSet.choices == 1, "popup omitted the choice dropdown")
local button = popup._activeControlSet.choices[1].btn
Check(button._label:GetText():find("Screen", 1, true) ~= nil, "popup omitted the selected value")
local before = choiceReads
em.ExternalPopup.Sync()
em.ExternalPopup.Sync()
Check(choiceReads == before, "unchanged popup sync rebuilt the anchor list")
button.scripts.OnClick(button)
local menu = button._menu
menu.scripts.OnShow(menu) -- native Show dispatch is outside the generic widget fixture.
Check(menu:IsShown() and #menu._items == 41, "dropdown omitted registered anchors")
Check(menu:GetHeight() == 296 and menu._choiceScroll, "long anchor menu was not clipped for scrolling")
menu._choiceScroll.height = 288 -- the widget fixture does not resolve two-point geometry.
menu.scripts.OnMouseWheel(menu, -1)
Check(menu._choiceScroll:GetVerticalScroll() == 48, "anchor menu did not scroll")
menu._items[3].scripts.OnClick(menu._items[3])
Check(value == "anchor2" and not menu:IsShown(), "popup selection did not apply")
Check(em.Undo.DoUndo() == true and value == "", "choice undo failed")
Check(em.Undo.DoRedo() == true and value == "anchor2", "choice redo failed")
Check(not em.ExternalElements.ApplyControl(key, "anchor", "missing") and value == "anchor2", "unknown choice was stored")
reject = true
Check(not em.ExternalElements.ApplyControl(key, "anchor", "anchor4") and value == "anchor2", "rejected choice was not rolled back")
reject = false
Check(em.ExternalElements.ApplyControl(key, "anchor", "anchor4"), "valid choice was rejected")
button.scripts.OnClick(button)
values = {{value="",text="Screen"}}
menu._items[6].scripts.OnClick(menu._items[6])
Check(value == "anchor4", "a removed target from a stale menu was applied")
Check(em.State.CancelAll() ~= false and value == "", "discard did not restore the original anchor")
print("Anchor popup choices: " .. checks .. " checks passed (" .. flavor .. ")")
