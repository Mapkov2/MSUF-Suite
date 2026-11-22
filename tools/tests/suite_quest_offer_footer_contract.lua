-- The two native quest-offer buttons are 77/78 x 22 UIPanelButtonTemplate
-- instances. Their scripts swap the three BACKGROUND slices on mouse down,
-- mouse up, enable and disable. Test the real Suite renderer and NPC owner.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local source = (arg[3] or root) .. "/MSUF_Suite_Skin/"
local checks, failures = 0, {}
local function Check(value, why)
    checks = checks + 1
    if not value then failures[#failures + 1] = why end
end
local function Noop() end
Enum = {UITextureSliceMode = {Stretched = 1}}
CreateColor = function(r, g, b, a) return {r = r, g = g, b = b, a = a} end
InCombatLockdown = function() return false end
securecallfunction = function(callback, ...) return callback(...) end
C_Timer = {After = function(_, cb) cb() end}
function hooksecurefunc(target, key, action)
    if type(target) == "string" then target, key, action = _G, target, key end
    local native = assert(target[key])
    target[key] = function(...)
        local results = {native(...)}
        action(...)
        return unpack(results)
    end
end

local Object = {}
Object.__index = Object
local function New(kind, parent, name)
    local obj = setmetatable({
        kind = kind, parent = parent, shown = true, alpha = 1, regions = {}, hooks = {}, scripts = {}, points = {},
        name = name, vertex = {1, 1, 1, 1}, enabled = true
    }, Object)
    if name then _G[name] = obj end
    return obj
end
function Object:GetParent() return self.parent end
function Object:GetName() return self.name end
function Object:GetObjectType() return self.kind end
function Object:IsObjectType(kind) return self.kind == kind end
function Object:IsProtected() return false, false end
function Object:IsForbidden() return false end
function Object:IsShown() return self.shown end
function Object:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Object:Show()
    if not self.shown then
        self.shown = true
        self:Fire("OnShow")
    end
end
function Object:Hide()
    if self.shown then
        self.shown = false
        self:Fire("OnHide")
    end
end
function Object:SetShown(value)
    if value then
        self:Show()
    else
        self:Hide()
    end
end
function Object:Fire(key, ...)
    if self.scripts[key] then self.scripts[key](self, ...) end
    for _, cb in ipairs(self.hooks[key] or {}) do cb(self, ...) end
end
function Object:HookScript(key, cb)
    assert(key ~= "OnUpdate", "unexpected polling")
    self.hooks[key] = self.hooks[key] or {}
    table.insert(self.hooks[key], cb)
end
function Object:GetScript(key) return self.scripts[key] end
function Object:SetScript(key, value) self.scripts[key] = value end
function Object:HasScript() return self.kind == "Frame" or self.kind == "Button" end
function Object:GetAlpha() return self.alpha end
function Object:SetAlpha(a) self.alpha, self.vertex[4] = a, a end
function Object:GetVertexColor() return unpack(self.vertex) end
function Object:SetVertexColor(r, g, b, a)
    self.vertex = {r, g, b, a or 1}
    self.alpha = a or 1
end
function Object:SetColorTexture(r, g, b, a) self.colorTexture = {r, g, b, a or 1} end
function Object:SetGradient(_, a, b) self.gradient = {a, b} end
function Object:GetDrawLayer() return self.layer, self.level end
function Object:SetDrawLayer(l, n) self.layer, self.level = l, n end
function Object:GetBlendMode() return self.blend or "BLEND" end
function Object:SetBlendMode(mode) self.blend = mode end
function Object:SetTexture(asset) self.asset = asset end
function Object:GetTexture() return self.asset end
function Object:SetAtlas(atlas) self.atlas = atlas end
function Object:GetAtlas() return self.atlas end
function Object:SetTexCoord(...) self.texCoords = {...} end
function Object:SetPoint(...) table.insert(self.points, {...}) end
function Object:GetPoint(i) return unpack(self.points[i or 1] or {}) end
function Object:ClearAllPoints() self.points = {} end
function Object:SetAllPoints(target) self.all = target or self.parent end
function Object:SetHeight(h) self.height = h end
function Object:SetWidth(w) self.width = w end
function Object:SetSize(w, h) self.width, self.height = w, h end
function Object:GetHeight() return self.height or 496 end
function Object:GetWidth() return self.width or 338 end
function Object:GetText() return self.text end
function Object:SetText(text) self.text = text end
function Object:GetFontString() return self.Text end
function Object:GetTextColor() return unpack(self.vertex) end
function Object:SetTextColor(...) self:SetVertexColor(...) end
function Object:GetRegions() return unpack(self.regions) end
function Object:CreateTexture(_, layer, _, level)
    local texture = New("Texture", self)
    texture:SetDrawLayer(layer, level or 0)
    table.insert(self.regions, texture)
    return texture
end
function Object:IsEnabled() return self.enabled end
function Object:SetEnabled(on)
    if self.enabled ~= on then
        self.enabled = on
        self:Fire(on and "OnEnable" or "OnDisable")
    end
end
function Object:Click() if self.enabled then self:Fire("OnClick", "LeftButton") end end
for _, name in ipairs({"Highlight", "Pushed", "Disabled", "Normal"}) do
    Object["Get" .. name .. "Texture"] = function(self) return self[name] end
    Object["Set" .. name .. "Texture"] = function(self, v, blend)
        self[name] = v
        if blend then v:SetBlendMode(blend) end
    end
end
Object.SetTextureSliceMargins, Object.SetTextureSliceMode, Object.ClearTextureSlice = Noop, Noop, Noop

local NS = {
    Client = {isForever = flavor == "Forever"}, path = "Interface\\AddOns\\MSUF_Suite_Skin\\",
    IsCombatLocked = InCombatLockdown, CombatGate = {RunOrDefer = function(_, cb) return cb() end, Cancel = Noop},
    Checkmarks = {
        GetWindowAction = Noop, TrackButton = Noop, TrackDropdown = Noop, UntrackButton = Noop,
        UntrackDropdown = Noop, UntrackOwner = Noop
    }, BlizzardYellow = {TrackFrame = Noop}, WindowActionSkin = {DisableOwner = Noop},
    GenericWindows = {IsCategoryEnabled = function(cat) return cat == "quest" end}, QuestText = {Refresh = Noop},
    IconSkin = {Apply = Noop, DisableOwner = Noop}, ScrollBarSkin = {GetState = Noop, DisableOwner = Noop}
}
local function Load(path) assert(loadfile(source .. path))("MSUF_Suite_Skin", NS) end
Load("Core/Defaults.lua")
Load("Core/DefaultsLooks.lua")
NS.DB = NS.CopyValue(NS.Defaults)
for _, file in ipairs({
    "../MSUF_Suite/Appearance/Safety.lua", "Core/Registry.lua", "Core/Theme.lua", "../MSUF_Suite/Appearance/Cosmetics.lua", "Rendering/Geometry.lua",
    "Rendering/Surface.lua", "Rendering/ControlSkin.lua", "Adapters/AdapterKit.lua",
    "Adapters/QuestRewardCards.lua", "Adapters/QuestWindow.lua"
}) do Load(file) end
NS.Registry.QueueJob = function(cb) cb() end
QuestFrame_SetMaterial, QuestInfo_ShowRewards, QuestInfoItem_OnClick = Noop, Noop, Noop
local q = New("Frame", nil, "QuestFrame")
local detail = New("Frame", q, "QuestFrameDetailPanel")
QuestInfoFrame = {itemChoice = 0}
QuestDetailScrollChildFrame = New("Frame", detail)
QuestInfoRewardsFrame = New("Frame", QuestDetailScrollChildFrame)
local preview = New("Button", QuestInfoRewardsFrame)
preview.largeItemButton, preview.type = true, "choice"
preview.Icon = preview:CreateTexture(nil, "BACKGROUND")
preview.Icon:SetTexture(132272)
preview.Name = New("FontString", preview)
preview.Name:SetText("Gryphon Rider's Leggings")
preview.NameFrame = preview:CreateTexture(nil, "BACKGROUND")
preview.IconBorder = preview:CreateTexture(nil, "OVERLAY")
QuestInfoRewardsFrame.RewardButtons = {preview}
local hover, accepts, auto, popups, declines, grants = 0, 0, 0, 0, 0, 0
local pvp, automatic = false, false
preview.scripts.OnEnter = function() hover = hover + 1 end
GetQuestReward = function() grants = grants + 1 end
local function Accept()
    if pvp then
        popups = popups + 1
    elseif automatic then
        auto = auto + 1
    else
        accepts = accepts + 1
    end
end
local function Decline()
    declines = declines + 1
    q:Hide()
end
local function Button(name, label, width, click, parent)
    local b = New("Button", parent or detail, name)
    b:SetSize(width, 22)
    b.Text = New("FontString", b)
    b.Text:SetText(label)
    b.scripts.OnClick = click
    for _, s in ipairs({"Left", "Middle", "Right"}) do b[s] = b:CreateTexture(nil, "BACKGROUND") end
    b.Highlight = b:CreateTexture(nil, "HIGHLIGHT")
    b.Highlight:SetTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    local function Material(state)
        for _, s in ipairs({"Left", "Middle", "Right"}) do
            b[s]:SetTexture("Interface\\Buttons\\UI-Panel-Button-" .. state)
        end
    end
    b.scripts.OnShow = function() Material(b.enabled and "Up" or "Disabled") end
    b.scripts.OnMouseDown = function() if b.enabled then Material("Down") end end
    b.scripts.OnMouseUp = function() if b.enabled then Material("Up") end end
    b.scripts.OnDisable = function() Material("Disabled") end
    b.scripts.OnEnable = function() Material("Up") end
    b:Fire("OnShow")
    return b
end
local accept = Button("QuestFrameAcceptButton", "Accept", 77, Accept)
local decline = Button("QuestFrameDeclineButton", "Decline", 78, Decline)
local rewardPage = New("Frame", q, "QuestFrameRewardPanel")
local progressPage = New("Frame", q, "QuestFrameProgressPanel")
local greetingPage = New("Frame", q, "QuestFrameGreetingPanel")
for _, page in ipairs({rewardPage, progressPage, greetingPage}) do page:Hide() end
local originalAcceptHighlight, originalDeclineHighlight = accept.Highlight, decline.Highlight
local owner = "blizzardWindows:deep-windows"
NS.QuestWindow.Activate(q, owner)
Check(NS.QuestWindow.GetStatus() == "painted", "visible detail page was not painted")
Check(accepts + declines + grants + auto + popups == 0, "painting triggered a quest action")
local function VisibleTexture(region)
    return region and region:IsVisible() and region:GetAlpha() > 0 and (region:GetTexture() or region:GetAtlas())
end
local function NativeCovered(b)
    for _, key in ipairs({"Left", "Middle", "Right"}) do if VisibleTexture(b[key]) then return false end end
    return true
end
local function Painted(texture, b)
    return VisibleTexture(texture) and texture:GetParent() == b and #texture.points == 2 and texture.points[1][2] ==
               b and texture.points[2][2] == b
end
for _, b in ipairs({accept, decline}) do
    local surface = NS.Registry.GetSurface(b)
    Check(surface and Painted(surface.fill, b) and Painted(surface.edge, b) and NativeCovered(b),
        b.name .. " has no visible native-sized idle texture")
    b:Fire("OnEnter")
    Check(Painted(b:GetHighlightTexture(), b) and b:GetHighlightTexture():GetDrawLayer() == "HIGHLIGHT" and
              b:GetHighlightTexture() == surface.highlight, b.name .. " lost its textured hover state")
    b:Fire("OnMouseDown")
    Check(Painted(b:GetPushedTexture(), b) and b:GetPushedTexture() == surface.pushed and NativeCovered(b),
        b.name .. " exposed native red on press or lost its pressed texture")
    b:Fire("OnMouseUp")
    b:SetEnabled(false)
    b:Click()
    Check(Painted(b:GetDisabledTexture(), b) and b:GetDisabledTexture() == surface.disabled and NativeCovered(b),
        b.name .. " has no styled disabled texture")
    b:SetEnabled(true)
    -- A late external style write shares the texture's alpha channel with
    -- its vertex tint. It need not cause a new quest event.
    b.Left:SetAlpha(.70)
    b.Left:Show()
    b.Middle:SetVertexColor(.92, .78, .64, .82)
    b.Middle:SetShown(true)
    b.Right:SetTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    b.Right:SetAlpha(.61)
    b.Right:Show()
    Check(NativeCovered(b) and Painted(surface.fill, b),
        b.name .. " exposed the native red material after late SetAlpha/SetTexture/Show")
    Check(b.Text:GetText() == (b == accept and "Accept" or "Decline") and b.Text:GetAlpha() == 1,
        b.name .. " changed the original visible label")
end
Check(accepts + declines + grants + auto + popups == 0, "disabled controls accepted, declined or granted a reward")
Check(accept:GetScript("OnClick") == Accept and decline:GetScript("OnClick") == Decline and accept.width == 77 and
          decline.width == 78 and accept.height == 22 and decline.height == 22,
    "original click handlers or native hit areas changed")
accept:Click()
pvp = true
accept:Click()
pvp = false
automatic = true
accept:Click()
Check(accepts == 1 and popups == 1 and auto == 1 and declines == 0,
    "accept lost normal, PvP confirmation or auto-quest routing")
preview:Fire("OnEnter")
Check(hover == 1 and VisibleTexture(preview.Icon) and preview.Name:GetText() == "Gryphon Rider's Leggings" and
          QuestInfoFrame.itemChoice == 0 and grants == 0,
    "button styling disturbed the visible reward preview or selected a reward")
decline:Click()
Check(declines == 1 and not q:IsShown() and accepts == 1, "decline lost the native close action")
q:Show()
accept.Middle:Hide()
decline.Right:SetShown(false)
NS.QuestWindow.Deactivate(q, owner)
Check(accept:GetHighlightTexture() == originalAcceptHighlight and decline:GetHighlightTexture() ==
          originalDeclineHighlight and accept.Left:IsShown() and not accept.Middle:IsShown() and
          decline.Middle:IsShown() and not decline.Right:IsShown(),
    "disable did not restore both native highlights and the last per-slice show/hide request")
Check(not VisibleTexture(NS.Registry.GetSurface(accept).fill) and
          not VisibleTexture(NS.Registry.GetSurface(decline).fill),
    "disabled owner left the native buttons' Suite faces visible")
NS.QuestWindow.Activate(q, owner)
accept.Left:SetAlpha(.5)
accept.Left:Show()
Check(NativeCovered(accept) and NativeCovered(decline) and VisibleTexture(NS.Registry.GetSurface(accept).fill) and
          VisibleTexture(preview.Icon) and grants == 0,
    "re-enabling the owner lost either its button face or reward protection")
NS.QuestWindow.Deactivate(q, owner)
-- The generic UIPanelButtons adapter can win the initial ownership claim.
-- A quest refresh borrows its existing styled surface, while foreign
-- controls keep their own visibility and input.
local borrowed = Button("QuestFrameDeclineButton", "Decline", 78, Decline)
local foreign = Button("QuestFrameAcceptButton", "Accept", 77, Accept)
local shared = {role = "button", allowImplicitProtected = true}
assert(NS.ControlSkin.ApplyThreeSliceButton(borrowed, "uipanel-buttons", shared))
assert(NS.ControlSkin.ApplyThreeSliceButton(foreign, "other-skin", shared))
local borrowedFace = NS.Registry.GetSurface(borrowed).fill
NS.QuestWindow.Activate(q, owner)
borrowed.Left:SetAlpha(.64)
borrowed.Left:Show()
foreign.Left:SetAlpha(.68)
foreign.Left:Show()
Check(NativeCovered(borrowed) and Painted(borrowedFace, borrowed) and NS.ControlSkin.GetOwner(borrowed) ==
          "uipanel-buttons", "pre-existing generic button owner lost the styled face or exposed its raw left slice")
Check(VisibleTexture(foreign.Left) and NS.ControlSkin.GetOwner(foreign) == "other-skin" and
          foreign:GetScript("OnClick") == Accept, "quest footer concealed another owner's button")
NS.QuestWindow.Deactivate(q, owner)
Check(VisibleTexture(borrowedFace) and NS.ControlSkin.GetOwner(borrowed) == "uipanel-buttons",
    "releasing quest chrome disabled the generic button owner's surface")

detail:Hide()
local turnIn = Button("QuestFrameCompleteQuestButton", "Complete Quest", 120, GetQuestReward, rewardPage)
local continue = Button("QuestFrameCompleteButton", "Continue", 77, Noop, progressPage)
local cancel = Button("QuestFrameGoodbyeButton", "Cancel", 78, Noop, progressPage)
local goodbye = Button("QuestFrameGreetingGoodbyeButton", "Goodbye", 78, Noop, greetingPage)
NS.QuestWindow.Activate(q, owner)
for _, b in ipairs({continue, cancel, goodbye, turnIn}) do
    local page = b:GetParent()
    page:Show()
    local surface = NS.Registry.GetSurface(b)
    b:Fire("OnMouseDown")
    b:Fire("OnMouseUp")
    for _, key in ipairs({"Left", "Middle", "Right"}) do
        b[key]:SetAlpha(1)
        b[key]:Show()
    end
    Check(surface and Painted(surface.fill, b) and NativeCovered(b), b.name .. " exposes red after a late repaint")
    page:Hide()
end
rewardPage:Show()
local grantsBeforeClick = grants
turnIn:SetEnabled(false)
turnIn:Click()
Check(grants == grantsBeforeClick and NativeCovered(turnIn), "disabled completion accepted a reward or exposed red")
turnIn:SetEnabled(true)
turnIn:Click()
Check(grants == grantsBeforeClick + 1 and turnIn:GetScript("OnClick") == GetQuestReward,
    "restyled completion bypassed the native button click")
NS.QuestWindow.Deactivate(q, owner)
Check(VisibleTexture(turnIn.Left) and VisibleTexture(turnIn.Middle) and VisibleTexture(turnIn.Right),
    "disabling the quest skin did not restore the completion button")
assert(#failures == 0, table.concat(failures, "\n"))
-- Arm while hidden, then open the native greeting for the first time in a
-- fight. Queued layout/settings work cannot run until after combat.
q:Hide()
rewardPage:Hide()
greetingPage:Show()
local locked, timers, afterCombat = false, {}, {}
NS.IsCombatLocked = function() return locked end
InCombatLockdown = NS.IsCombatLocked
NS.Registry.QueueJob = function(job) afterCombat[job] = job end
NS.CombatGate.RunOrDefer = function(key, job)
    if locked then afterCombat[key] = job else job() end
end
C_Timer.After = function(delay, fn)
    assert(delay == 0)
    timers[#timers + 1] = fn
end
local function NextFrame()
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do fn() end
end
locked = flavor == "Forever"
NS.QuestWindow.Activate(q, owner)
locked = true
q:Show()
QuestFrame_SetMaterial()
NextFrame()
NextFrame()
Check(NativeCovered(goodbye) and NS.Registry.GetSurface(goodbye).visible ~= false,
    "first combat greeting exposed its native Goodbye button")
for _, piece in ipairs({goodbye.Left, goodbye.Middle, goodbye.Right}) do
    piece:SetAlpha(1)
    piece:Show()
end
NextFrame()
Check(NativeCovered(goodbye), "Blizzard redrew the greeting art over the skin during combat")
Check(#timers == 0, "concealing our own greeting art scheduled an idle paint loop")
goodbye.IsProtected = function() return true, false end
goodbye.Left:Show()
NextFrame()
Check(goodbye.Left:IsShown(), "a texture on a protected button was hidden in combat")
goodbye.IsProtected = Object.IsProtected
q:Hide()
locked = false
for _, fn in pairs(afterCombat) do fn() end
NextFrame()
Check(not q:IsShown(), "deferred repaint reopened a closed quest")
NS.QuestWindow.Deactivate(q, owner)
assert(#failures == 0, table.concat(failures, "\n"))
print(("suite_quest_offer_footer_contract (%s): %d checks passed"):format(flavor, checks))
