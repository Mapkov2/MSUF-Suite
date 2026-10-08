local root = assert(arg[1], "repository root required")
local H = assert(loadfile(root .. "/tools/tests/suite_installer_harness.lua"))()
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function Region(panel, module, label)
    for _, region in ipairs(panel.regions) do
        if region:IsShown() and region.module == module and (not label or region.label == label) then return region end
    end
end
local function Row(window, id)
    for _, row in ipairs(window.moduleRows) do if row.id == id then return row end end
    error("module row missing: " .. id)
end

for _, forever in ipairs({ false, true }) do
    local Suite = H.Setup({ root = root, forever = forever, uiWidth = 1920, uiHeight = 1080,
        uiScale = .8, physicalWidth = 3840, physicalHeight = 2160 })
    local modules = {}
    for _, id in ipairs(Suite.SuiteOrder) do
        modules[id] = Copy(Suite.Defaults.suite.modules[id] or {})
        modules[id].enabled = true
    end
    modules.actionbars.bar1Size, modules.actionbars.bar1Buttons = 40, 12
    modules.actionbars.bar1Point, modules.actionbars.bar1Y = 8, 40
    local profile = { suite = { modules = modules } }
    Suite.ProfileIO.PrepareProfile = function() return profile end
    local factory = { player = { width = 275, height = 40, offsetX = -326, offsetY = -180 } }
    local frameReads = 0
    Suite.HostBridge.FactoryFramePreview = function()
        frameReads = frameReads + 1
        return factory
    end
    MSUF_DB.player = { enabled = true, point = "TOPLEFT", relativePoint = "TOPLEFT",
        offsetX = 67, offsetY = -81, width = 300, height = 60 }
    local saved, savedSuite, cached = Copy(MSUF_DB), Copy(Suite.RootDB), Copy(profile)
    assert(Suite.Installer.Open())
    local window = assert(MSUFSuiteInstallFrame)
    local panel = assert(window.layoutPreview)
    assert(not panel:IsShown(), "welcome must remain compact")
    window.next.scripts.OnClick() -- layout
    local map = assert(Region(panel, "minimap"), "preview module has no navigation owner")
    assert(map.kind == "Button" and map.scripts.OnClick, "layout elements are still hover-only")
    map.scripts.OnClick()
    assert(window.moduleScroll:IsShown() and panel:IsShown() and window.moduleFocus == "minimap",
        "clicking the minimap did not navigate to its staged module choice")
    local mapRow = Row(window, "minimap")
    assert(mapRow:IsShown() and mapRow.focus:IsShown(), "the clicked module is not identified in the list")
    mapRow.scripts.OnClick()
    assert(not Region(panel, "minimap") and panel.info:GetText():find("OFF", 1, true),
        "disabled module remains visible or its selected state is lost")
    assert(profile.suite.modules.minimap.enabled, "module selection edited the cached factory")
    mapRow.scripts.OnClick()
    assert(Region(panel, "minimap"), "reenabled module does not return to the preview")
    -- Focus a row beyond the first viewport; no second module toggle exists.
    local last = window.moduleGroups.modules[#window.moduleGroups.modules]
    assert(Suite.InstallerModules.Focus(window, last.id))
    Suite.Installer.Refresh()
    local scroll = window.moduleScroll
    assert(scroll:GetVerticalScroll() >= 0 and scroll:GetVerticalScroll() <= scroll:GetVerticalScrollRange(),
        "module focus escaped the owned scroll range")
    assert(last.focus:IsShown(), "the focused module was not marked")
    window.next.scripts.OnClick() -- scale
    assert(panel:IsShown() and window.scaleToggle:IsShown(), "scaling lost the decision preview")
    window.keepFrames.scripts.OnClick()
    local player = assert(Region(panel, "frames", "Player"), "current frames were replaced by no data")
    local expected = 312 / 1920
    assert(math.abs(player.point[4] - 67 * expected) < .000001
        and math.abs(player.point[5] + 81 * expected) < .000001
        and math.abs(player:GetWidth() - 300 * expected) < .000001,
        "Keep current frames still shows factory geometry")
    assert(panel.frameSource:GetText() == "Current MSUF frames")
    local before = frameReads
    Suite.Installer.Refresh()
    assert(frameReads == before, "retained frames unnecessarily read a factory")
    local current = MSUF_DB
    MSUF_DB = nil
    Suite.Installer.Refresh()
    assert(not Region(panel, "frames", "Player") and panel.frameSource:GetText() == "MSUF frame preview unavailable"
        and frameReads == before, "missing current settings silently substituted a factory")
    MSUF_DB = current
    window.scaleToggle.scripts.OnClick()
    window.scaleSlider:SetValue(.6)
    local small = assert(Region(panel, "actionbars")):GetWidth()
    window.scaleSlider:SetValue(.9)
    assert(assert(Region(panel, "actionbars")):GetWidth() > small * 1.49,
        "changing scale does not change the staged layout")
    local viewport = Suite.InstallerPreviewModel.Viewport({ useScale = true, scale = .6 })
    assert(viewport.width == 2560 and viewport.height == 1440,
        "physical pixels were treated as UI units instead of using the actual parent scale")
    UIParent:SetSize(2560, 1080)
    Suite.Installer.Refresh()
    assert(panel.canvas:GetWidth() == 312 and panel.canvas:GetHeight() < 132,
        "wide-screen preview still uses a fixed 16:9 picture")
    UIParent:SetSize(1920, 1080)
    -- Unknown external anchors must be disclosed, never guessed at CENTER.
    MSUF_DB.player.anchorFrameName = "ExternalAddonFrame"
    Suite.Installer.Refresh()
    assert(not Region(panel, "frames", "Player") and panel.note:GetText():find("Externally anchored", 1, true),
        "external frame anchoring is silently presented as a screen-center position")
    MSUF_DB.player.anchorFrameName = nil
    MSUF_DB.general.anchorName = "ExternalAddonFrame"
    Suite.Installer.Refresh()
    assert(not Region(panel, "frames", "Player") and panel.note:GetText():find("Externally anchored", 1, true),
        "an inherited external anchor was presented as a screen-relative position")
    MSUF_DB.player.anchorFrameName = "UIParent"
    MSUF_DB.general.anchorToCooldown = true
    Suite.Installer.Refresh()
    assert(Region(panel, "frames", "Player"), "an explicit screen anchor lost to the inherited global anchor")
    MSUF_DB.player.anchorFrameName, MSUF_DB.general.anchorName, MSUF_DB.general.anchorToCooldown = nil, nil, nil
    MSUF_DB.bars = { showClassPower = true, classPowerAnchorToCooldown = true }
    Suite.Installer.Refresh()
    assert(Region(panel, "frames", "Player") and not Region(panel, "frames", "Resources")
        and panel.note:GetText():find("Externally anchored", 1, true),
        "retained CDM-anchored resources were shown at a guessed player-relative position")
    MSUF_DB.bars = nil
    Suite.Installer.Refresh()
    MSUF_DB.player.screenPositionMode, MSUF_DB.player.screenPositionHeight = "relativeHeight", 1080
    window.scaleSlider:SetValue(.6)
    for _, anchor in ipairs({ "GLOBAL", "global", "FREE", "" }) do
        MSUF_DB.player.anchorToUnitframe = anchor
        Suite.Installer.Refresh()
        assert(math.abs(assert(Region(panel, "frames", "Player")).point[4] - 67 * 312 / 2560) < .000001,
            "relative-height adaptation ignored the host's explicit unit-anchor guard")
    end
    MSUF_DB.player.anchorToUnitframe = nil
    Suite.Installer.Refresh()
    assert(math.abs(assert(Region(panel, "frames", "Player")).point[4] - 67 * 1440 / 1080 * 312 / 2560) < .000001,
        "an unanchored relative-height frame lost its supported adaptation")
    MSUF_DB.player.screenPositionMode, MSUF_DB.player.screenPositionHeight = nil, nil
    -- Off restores Blizzard's unchanged scale; the schematic explicitly shows
    -- current scale until it is applied, even when an MSUF overlay differs.
    local cvar = C_CVar.GetCVar
    C_CVar.GetCVar = function(key) return key == "uiScale" and "0.6" or "1" end
    window.scaleToggle.scripts.OnClick()
    assert(panel.viewport:GetText():find("Current UI scale 80%", 1, true)
        and window.scaleHint:GetText():find("This preview uses the current UI scale.", 1, true),
        "scaling Off promises the current overlay as the later Blizzard setting")
    assert(UIParent:GetEffectiveScale() == .8 and C_CVar.GetCVar("uiScale") == "0.6",
        "preview wrote the parent scale or Blizzard CVars")
    C_CVar.GetCVar = cvar
    window.next.scripts.OnClick() -- review
    assert(panel:IsShown() and window.review[1]:IsShown(), "review lost the final staged preview")
    panel.modules.scripts.OnClick()
    assert(window.moduleScroll:IsShown() and panel:IsShown(), "review cannot return to module choices")
    assert(Equal(MSUF_DB, saved) and Equal(Suite.RootDB, savedSuite) and Equal(profile, cached),
        "preview navigation changed saved settings or a factory")
    assert(#H.appliedScales == 0 and next(H.loaded) == nil and #H.reported == 0,
        "preview applied a scale, loaded an optional addon or raised an error")
    Suite.Installer.Open()
    assert(rawget(window, "moduleFocus") == nil and rawget(panel, "selectedModule") == nil and scroll:GetVerticalScroll() == 0,
        "reopened setup retained another session's selection or scroll")
end
print("useful installer preview: navigation, module choices, retained frames, staged scale, review and read-only state passed")
