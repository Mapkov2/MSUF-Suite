-- Exercise retained Suite selectors through the host's real menu zoom path.
local root = assert(arg[1])
local flavor = arg[2] or "Mainline"
arg[4] = "fixture"
local F = assert(loadfile(root .. "/tools/tests/suite_menu_geometry_contract.lua"))()
local M, P, env, methods = F.M, F.P, F.env, F.world.widgets.Methods
local pack = dofile(root .. "/tools/tests/suite_test_support.lua").SuitePack(root, "esES")
local english = M.Tr
M.Tr = function(text, ...) return pack[text] or english(text, ...) end
assert(P.Tr("Run Summaries") ~= "Run Summaries", "fixture did not apply the Suite locale")
local function Noop() end
methods.SetMaxBytes = methods.SetMaxBytes or Noop
methods.SetMotionScriptsWhileDisabled = methods.SetMotionScriptsWhileDisabled or Noop
methods.SetDrawBling = methods.SetDrawBling or Noop
methods.SetSwipeColor = methods.SetSwipeColor or Noop
methods.GetCountdownFontString = methods.GetCountdownFontString or function(self)
    self.fixtureCountdown = self.fixtureCountdown or self:CreateFontString(nil, "OVERLAY")
    return self.fixtureCountdown
end
methods.SetMultiLine = methods.SetMultiLine or Noop
methods.SetMaxLetters = methods.SetMaxLetters or Noop
methods.SetFocus = function(self) self.fixtureFocus = true end
methods.ClearFocus = function(self) self.fixtureFocus = false end
env.C_SpecializationInfo.GetNumSpecializationsForClassID = function() return 0 end
env.C_SpecializationInfo.GetActiveSpecGroup = function() return 1 end
local createFrame = env.CreateFrame
env.CreateFrame = function(kind, name, parent, template)
    local frame = createFrame(kind, name, parent, template)
    if template == "ScrollFrameTemplate" and not frame.ScrollBar then
        frame.ScrollBar = createFrame("Frame", nil, frame)
        frame.ScrollBar.SetHideIfUnscrollable = Noop
    end
    return frame
end

-- Font hinting can change the local width of an anchored string even when
-- the same text in the UIParent measuring probe stays at its previous width.
local scale = 1
local function Factor(label)
    local _, button = label:GetPoint(1)
    return button and button._msuf2SegmentChoice == true and scale or 1
end
methods.GetUnboundedStringWidth = function(self) return self:GetStringWidth() * Factor(self) end
methods.GetUnboundedStringWidthForText = function(self, text) return #text * 6 * Factor(self) end
local contentWidth = 680
M.GetContentMetrics = function() return contentWidth, 900 end

local zoom = M.GetGeneralDB()
local function SetZoom(value, widthFactor)
    scale = widthFactor
    zoom.slashMenuScale = value
    M.ApplyMenuFrameScale(F.mw.win)
end
local checks = 0
local function CheckButton(button, page)
    local label = assert(P.HM.GetControlLabel(button))
    local _, _, _, left = label:GetPoint(1)
    local _, rightOwner, _, right = label:GetPoint(2)
    if button.chevron and rightOwner == button.chevron then
        local _, _, _, chevronInset = button.chevron:GetPoint(1)
        right = right + chevronInset - button.chevron:GetWidth()
    end
    local available = button:GetWidth() - left + right
    assert(available >= label:GetUnboundedStringWidth(), page .. " clipped " .. label:GetText())
    checks = checks + 1
end

for _, page in ipairs({ "suite_chat", "suite_minimap", "suite_nameplates", "suite_qualityOfLife",
    "suite_cooldownManager", "suite_macros", "suite_actionbars", "suite_hud" }) do
    SetZoom(.80, 1)
    contentWidth = page == "suite_actionbars" and 720 or page == "suite_hud" and 950 or 680
    if page == "suite_cooldownManager" then
        local config = P.S.Config("cooldownManager")
        config.c1_on, config.c1_name = true, "Editor test"
    end
    assert(M.SelectPage(page), "could not open " .. page)
    F.mw:RunTimers(1000)
    local count = 0
    local focus
    if page == "suite_macros" then
        focus = assert(P.MacroPage.ui.pools.edit.name)
        focus:SetFocus()
    end
    for _, input in ipairs({ { .68, 1.18 }, { .92, 1.24 }, { .80, 1 } }) do
        SetZoom(input[1], input[2])
        for _, frame in ipairs(F.world.widgets.frames) do
            if frame._msuf2SegmentChoice == true and frame:IsVisible() then
                CheckButton(frame, page)
                count = count + 1
            end
        end
        if focus then assert(focus.fixtureFocus, "zoom cleared the macro editor's input focus") end
    end
    assert(count >= 9, "fixture did not visit the selectors on " .. page)
    if page == "suite_cooldownManager" then
        assert(P.CDMPage.ui.chips.c1:IsVisible() and P.CDMPage.ui.chips.c1.chevron, "custom chip was not audited")
    end
    M.SelectPage("home")
end

assert(M.SelectPage("suite_buffReminders"))
local ui = assert(M.cache.suite_buffReminders.context.suiteWorkspace)
local before = ui.header:GetHeight()
M.SelectPage("home")
M.InvalidatePage("suite_buffReminders")
contentWidth = 270
assert(M.SelectPage("suite_buffReminders"))
ui = assert(M.cache.suite_buffReminders.context.suiteWorkspace)
local preview = ui.reminderPreview.viewport:GetParent()
local extra = ui.tabs:GetHeight() - 26
local _, relative, _, _, offset = preview:GetPoint(1)
assert(extra > 0, "fixture did not wrap the Buff Reminders tabs at width " .. ui.tabs:GetWidth())
assert(relative == ui.header and offset == -extra, "wrapped Buff Reminders tabs overlap the preview")
assert(ui.header:GetHeight() >= before + extra, "the sticky header did not reserve the extra tab rows")

print("PASS Suite menu zoom tabs " .. flavor .. " " .. checks .. " captions")
