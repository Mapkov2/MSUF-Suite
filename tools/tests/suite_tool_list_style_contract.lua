-- Actual shared mail UI and HostBridge; native Menu2 control contracts.
local root = assert(arg[1])
local F = dofile(root .. "/tools/tests/suite_inventory_tools_fixture.lua")
local E = F.New(root)
local S, NS = E.S, E.NS
local sample = S.CreateFrame("Frame")
local methods = getmetatable(sample).__index
local function Noop() end
for _, name in ipairs({"ClearAllPoints", "SetMovable", "SetClampedToScreen", "EnableMouse", "RegisterForDrag",
    "StartMoving", "StopMovingOrSizing"}) do methods[name] = Noop end
local checks, loads, paints, selected, watched = 0, 0, 0, {}, nil
local function Check(ok, message) assert(ok, message); checks = checks + 1 end
local colors = { text={.9,.9,.9,1}, danger={1,.4,.4,1} }
local theme = { colors=colors }
function theme.ApplyMaterial(frame, role) paints=paints+1; frame.material=role end
function theme.ApplyMenuAtmosphere(frame) frame.atmosphere=true end
function theme.Button(parent, text, width, height)
    local button = S.CreateFrame("Button", nil, parent)
    button:SetSize(width,height)
    button._msuf2Label=S.QoLLabel(button,text,12)
    function button:SetText(value) self._msuf2Label:SetText(value) end
    function button:GetText() return self._msuf2Label:GetText() end
    function button:GetFontString() return nil end -- Menu2 owns a custom label.
    function button:SetActive(value) selected[self]=value end
    function button:RefreshVisual() end
    button.modern=true
    return button
end
function theme.CloseButton(parent) return theme.Button(parent,"X",24,24) end
function theme.SkinEditBox(edit) edit.modern=true end
function theme.StyleFontString(label) paints=paints+1; label.modern=true; label.themeColor=colors.text end
InCombatLockdown=function() return E.combat end
NS.HostBridge={}
NS.Client.IsAddOnLoaded=function() return false end
MSUF2=nil
C_AddOns={LoadAddOn=function() loads=loads+1; MSUF2={Theme=theme} end}
local api={OnAppearanceChanged=Noop}
MapkoSkin={GetAPI=function() return api end}
hooksecurefunc=function(target,name,callback) Check(target==api,"unexpected hook"); watched=callback end
E:Load("MSUF_Suite/Core/HostBridgeMenu.lua",true)
local override=os.getenv("SUITE_TOOL_WINDOW_SOURCE")
if override then assert(loadfile(override))("Test",{NS=NS,Suite=S}) end
local originalSetFont=S.SetFont
S.SetFont=function(label,...) Check(label~=nil,"font painter received nil custom button label"); originalSetFont(label,...) end
local owner, rows, calls, saves = {active=true}, {}, 0, 0
for i=1,14 do rows[i]={key=i,label="Template "..i,detail="Recipient and materials",disabled=i==2} end
local spec={title="Mail templates",help="Choose a template",rows=function() calls=calls+1; return rows end,
    actions={{label="Preview",enabled=function(_,row) return row~=nil end,run=Noop}}}
local window=S.ToolListWindow.Open(owner,spec)
Check(loads==1,"cold open did not resolve Menu2 theme exactly once")
Check(window.toolModern and window.material=="shell" and window.atmosphere,"legacy gold window is still used")
Check(window.search.modern and window.actions[1].modern and window.close.modern,"search/actions/close are not themed")
Check(window.actions[1].enabled==false,"no-selection action was not disabled")
window.buttons[1]:Click()
Check(selected[window.buttons[1]]==true and window:Selected().key==1,"selection is not painted by the native control")
Check(window.buttons[2].enabled==false,"disabled template remained actionable")
Check(window.buttons[1].text:GetText()=="Template 1","row label was lost")
window.search:SetText("Template 14")
Check(window:Selected()==nil and window.actions[1].enabled==false,"filtered-out selection retained its action")
window:Hide()
local oldPaints,oldCalls=paints,calls
watched()
S.ToolListWindow.Refresh(owner)
Check(paints==oldPaints and calls==oldCalls,"closed window does style/provider work")
local frameCount=#E.frames
Check(S.ToolListWindow.Open(owner,spec)==window and #E.frames==frameCount,"warm open rebuilt the window")
Check(loads==1,"warm open loads options again")
S.ToolListWindow.Edit(owner,{title="Mail subject",text="Raid",onSave=function(_,text) saves=saves+1; return false,"Invalid" end})
local editor
for _,frame in ipairs(E.frames) do if frame.input and frame.save then editor=frame end end
Check(editor and editor.material=="shell" and editor.inputScroll.material=="card","editor retained legacy surfaces")
Check(editor.input.modern and editor.input.themeColor==colors.text,"typed editor text ignores theme")
Check(editor.save.modern and editor.cancel.modern,"editor controls are not native Menu2 buttons")
editor.save:Click()
Check(saves==1 and editor:IsShown(),"validation refusal closed editor or did not run")
local count=#E.frames
colors.text={.3,.3,.3,1}
watched()
Check(editor.input.themeColor==colors.text,"typed editor text ignores palette changes")
Check(#E.frames==count,"appearance refresh rebuilt widgets")
editor.cancel:Click()
Check(not editor:IsShown() and saves==1,"Cancel saved or left editor visible")
NS.DB={}
S.ToolListWindow.Refresh(owner)
Check(not window:IsShown(),"profile switch left stale window open")
E.combat=true
Check(S.ToolListWindow.Open(owner,spec)==nil,"tool opened in combat")
E.combat=false
MSUF2=nil
C_AddOns.LoadAddOn=function() end
-- Re-load only the shared view, simulating a host without the optional Menu2 renderer.
assert(loadfile(override or root.."/MSUF_Suite_Modules/ToolListWindow.lua"))("Test",{NS=NS,Suite=S})
local fallback=S.ToolListWindow.Open(owner,spec)
Check(fallback and not fallback.toolModern and #fallback.buttons==12,"older host fallback is unusable")
print("suite_tool_list_style_contract: "..checks.." checks passed")
