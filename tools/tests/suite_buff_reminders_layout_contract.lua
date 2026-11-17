-- Exercise native descendant visibility during real sticky-header activation.
local root, mode = assert(arg[1]), arg[4]
arg[4] = "fixture"
local F = assert(loadfile(root .. "/tools/tests/suite_menu_geometry_contract.lua"))()
arg[4] = mode
local env, M, world, mw, P, MenuWorld = F.env, F.M, F.world, F.mw, F.P, F.MenuWorld
local checks, contexts = 0, {}
local function Check(ok, message) checks = checks + 1 assert(ok, message) end
local createContext = M.CreateContext
M.CreateContext = function(...)
    local ctx = createContext(...)
    contexts[ctx.entry] = ctx
    return ctx
end
-- The client fires OnShow on visible descendants when their hidden header
-- is shown. The generic widget fixture only fires the parent's script.
world.widgets.Methods.SetMaxBytes = function(self, value) self.maxBytes = value end
local createFrame = env.CreateFrame
env.CreateFrame = function(kind, name, parent, template)
    local frame = createFrame(kind, name, parent, template)
    if template == "ScrollFrameTemplate" then
        frame.ScrollBar = createFrame("Frame", nil, frame)
        frame.ScrollBar.SetHideIfUnscrollable = function() end
    end
    return frame
end
local reminders = P.MenuSamples.Reminders
P.MenuSamples.Reminders = function(ui)
    reminders(ui)
    local show, hide = ui.header.Show, ui.header.Hide
    function ui.header:Show()
        local wasVisible = self:IsVisible()
        show(self)
        if not wasVisible and self:IsVisible() then
            MenuWorld.FireScript(ui.reminderPreview.viewport, "OnShow")
        end
    end
    function ui.header:Hide()
        local wasVisible = self:IsVisible()
        hide(self)
        if wasVisible then MenuWorld.FireScript(ui.reminderPreview.viewport, "OnHide") end
    end
end
local reminderHeight, reminderPaints = 94, 0
P.S.BuffRemindersDrawPreview = function(stage)
    reminderPaints = reminderPaints + 1
    stage:SetSize(72, reminderHeight)
    return 72, reminderHeight, 1
end
P.S.BuffRemindersReleasePreview = function() end
for _,height in ipairs({94, 180, 38, 120}) do
    M.SelectPage("suite_bags")
    reminderHeight = height
    assert(M.SelectPage("suite_buffReminders"))
    mw:RunTimers(1000)
    local ui = contexts[M.cache.suite_buffReminders].suiteWorkspace
    local record = M.cache.suite_buffReminders.pageHeaders[1]
    F.CheckTabDivider(ui.toolbar, ui.tabs)
    local expected = math.min(180, math.max(38, height * ui.reminderPreview.stage:GetScale()))
    Check(ui.reminderPreview.viewport:GetHeight() == expected, "reminder sample did not resize")
    Check(record.hostHeight >= record.headerTopInset + ui.header:GetHeight() + record.stickyGap,
        "Buff Reminders preview overlaps Basics: sticky slot retained its pre-show height")
    Check(M.pageHeaderHost:GetHeight() >= record.hostHeight, "settings start inside the reminder preview")
    local paints = reminderPaints
    ui.refreshPreview()
    Check(reminderPaints == paints, "unchanged reminder preview repainted")
end
local unitClass = env.UnitClass
local ui = contexts[M.cache.suite_buffReminders].suiteWorkspace
local settingsRows, anchorRow, pointRow = P.W.SettingsRows
P.W.SettingsRows = function(ctx, body, options)
    for _, row in ipairs(options.rows or {}) do
        if row.id == "anchorTarget" then anchorRow = row end
        if row.id == "point" then pointRow = row end
    end
    return settingsRows(ctx, body, options)
end
Check(ui:Focus("suite_buffReminders_position"), "anchor controls are not reachable under Appearance")
P.W.SettingsRows = settingsRows
local hasAnchor
for _, section in pairs(ui.sections) do
    if section._suiteWorkspaceSection == "suite_buffReminders_position" then hasAnchor = section end
end
Check(hasAnchor ~= nil, "anchor settings section is missing")
local anchorChoices = P.Suite.HostBridge.EditAnchorChoices("external:msufsuite.buffreminders:buffs")
Check(#anchorChoices > 1 and anchorChoices[1].value == "", "disabled runtime modules lost their anchor picker")
Check(anchorRow and anchorRow.kind == "dropdown" and #anchorRow.values() > 1,
    "the anchor setting is not a usable target dropdown")
Check(pointRow and pointRow.label == P.Tr("Reminder point"), "own reminder point was not labeled")
local savedAnchor = anchorRow.get()
anchorRow.set("player")
Check(anchorRow.get() == "player" and P.Get("buffReminders", "anchorTarget") == "player", "selected anchor was not saved by key")
anchorRow.set(savedAnchor)
for _, class in ipairs({ "MAGE", "PRIEST", "DRUID", "WARRIOR" }) do
    env.UnitClass = function() return class, class end
    Check(P.Gates.buffReminders({ key = "classMageArmor" }) == (arg[2] == "Forever" and class == "MAGE"),
        "Mage armor menu gate leaked to another class or client")
    Check(P.Gates.buffReminders({ key = "classInnerFire" }) == (arg[2] == "Forever" and class == "PRIEST"),
        "Inner Fire menu gate leaked to another class or client")
    Check(P.Gates.buffReminders({ key = "classThorns" }) == (arg[2] == "Forever" and class == "DRUID"),
        "Thorns menu gate leaked to another class or client")
end
env.UnitClass = unitClass
P.MenuSamples.Reminders = reminders
env.CreateFrame = createFrame
M.CreateContext = createContext
print("PASS Buff Reminders header layout " .. (arg[2] or "Mainline") .. " " .. checks .. " checks")
