local root = assert(arg[1])
C_Navigation = {}
SUITE_OPTIONS_FIXTURE = true
local fixture = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
SUITE_OPTIONS_FIXTURE = nil
local P, M = fixture.optionsNS, fixture.M
local lastView
fixture.S.Navigation = { Sample = function(model, _, scene, distance)
    model.scene, model.distance = scene, distance
end }
fixture.S.DrawNavigationPreview = function(parent, _, model)
    local view = rawget(parent, "testNavigationView")
    if not view then
        view = { root = fixture.Widget("Frame"), card = fixture.Widget("Frame"),
            beam = fixture.Widget("Frame"), distance = fixture.Widget("Frame") }
        view.root.SetScale = function(self, scale) self.testScale = scale end
        view.root.GetScale = function(self) return self.testScale end
        parent.testNavigationView = view
    end
    view.scale = model.scene ~= 4 and .5 or nil
    view.root:SetShown(model.scene ~= 4)
    lastView = view
    return view
end
local ctx = { key = "suite_qualityOfLife", width = 850, refreshers = {}, widgets = {}, sections = {},
    pageItems = {}, entry = { sections = {} } }
fixture.SetCurrent(ctx)
M.pages.suite_qualityOfLife.build(ctx)
local group = assert(P.QoLView.FindFeature("navigation"))
local section = P.QoLView.FeatureSectionId(group)
local resolver = assert(P.HM.GetMissingSectionResolver(ctx.entry))
assert(resolver(section), "navigation settings are not discoverable")
local config = fixture.S.Config("navigation")
assert(config.enabled == false, "opening the preview enabled live navigation")
local count, size = 0, nil
for _, widget in ipairs(ctx.widgets) do
    local key = widget.meta and widget.meta.settingKey
    if key and key:find("msufsuite.navigation.", 1, true) then count = count + 1 end
    if key == "msufsuite.navigation.markerSize" then size = widget end
end
assert(count > 20, "navigation controls were not registered for search: " .. count)
assert(size and size.set, "waypoint size setting is missing")
size.set(42)
assert(config.markerSize == 42 and config.enabled == false, "editing the disabled preview changed activation")
assert(fixture.registeredControls["menu2.suite_qualityOfLife.navigation.action.colors.enabled"], "navigation colors are unreachable")
assert(lastView and math.abs(lastView.root:GetScale() - .425) < .0001, "preview discarded the painter's distance scale")
fixture.registeredControls["menu2.suite_qualityOfLife.navigation.preview.4"].scripts.OnClick()
assert(not lastView.root:IsShown(), "No destination preview retained a marker")
fixture.registeredControls["menu2.suite_qualityOfLife.navigation.preview.1"].scripts.OnClick()
assert(lastView.root:IsShown() and config.enabled == false, "preview recovery enabled live navigation")
print("PASS navigation settings: real menu builds the preview and searchable controls without enabling navigation")
