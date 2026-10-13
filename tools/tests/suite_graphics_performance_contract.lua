local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local secret = newproxy(true)
getmetatable(secret).__eq = function() error("compared secret") end
getmetatable(secret).__tostring = function() error("formatted secret") end
local values, writes, refused, adjusted, unsupported, combat, reads = {}, {}, {}, {}, {}, false, 0
C_CVar = {
    GetCVar = function(key) reads = reads + 1; return values[key] end,
    SetCVar = function(key, value)
        Check(not combat, "write in combat")
        writes[#writes + 1] = { key, value }
        if not refused[key] then values[key] = adjusted[key] or value end
    end,
}
local capability = true
C_VideoOptions = { IsSpellVisualDensitySystemSupported = function() return capability end }
IsGraphicsSettingValueSupported = function(key, value, raid)
    Check(raid == (key:sub(1, 4) == "raid"), "wrong native raid support argument")
    return unsupported[key] or 0
end
local Suite = { RootDB = {}, Client = { flavor = "Mainline" }, IsSecret = function(value) return rawequal(value, secret) end }
local P = { Suite = Suite, Tr = function(text) return text end, Combat = function() return combat end }
local function Load()
    assert(loadfile(root .. "/MSUF_Suite_Options/Menu/GraphicsPerformance.lua"))("MSUF_Suite_Options", P)
    return P.GraphicsPerformance
end
local function Reset(flavor)
    values, writes, refused, adjusted, unsupported, combat, capability = {}, {}, {}, {}, {}, false, true
    Suite.RootDB, Suite.Client.flavor = { profiles = { One = {}, Two = {} } }, flavor or "Mainline"
    for _, prefix in ipairs({ "graphics", "raidGraphics" }) do
        for _, suffix in ipairs({ "ShadowQuality", "LiquidDetail", "SSAO", "DepthEffects", "ComputeEffects",
            "ViewDistance", "EnvironmentDetail", "GroundClutter", "SpellDensity", "ProjectedTextures" }) do
            values[prefix .. suffix] = "3"
        end
    end
    values.RAIDsettingsEnabled, values.Contrast = "0", "50"
    values.ResampleAlwaysSharpen, values.Sound_EnableReverb = "0", "1"
end
Reset()
local G = Load()
Check(reads == 0 and #writes == 0, "loading options reads or applies a graphics preset")
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    Reset(flavor)
    local original = {}
    for key, value in pairs(values) do original[key] = value end
    local plan = G.Plan("balanced")
    Check(#plan == 10, "balanced native settings missing")
    for _, row in ipairs(plan) do
        Check(not row.key:match("^raid") and row.key ~= "RAIDsettingsEnabled", "balanced touches instance settings")
    end
    Check(#writes == 0 and not Suite.RootDB.graphicsRecovery, "preview creates recovery or writes settings")
    local result = assert(G.Apply(plan))
    Check(result.changed > 0 and result.failed == 0, "balanced apply failed")
    Check(values.graphicsProjectedTextures == "1", "ground projections not retained")
    Check(values.raidGraphicsShadowQuality == original.raidGraphicsShadowQuality, "general apply changed raid settings")
    Check(values.Contrast == "50" and values.Sound_EnableReverb == "1", "optional changes applied without consent")
    Suite.RootDB.activeProfile = "Two"
    G = Load()
    Check(G.PendingCount() > 0, "reload or profile change lost recovery")
    values.graphicsShadowQuality = "4"
    result = assert(G.Restore())
    Check(result.preserved == 1 and values.graphicsShadowQuality == "4", "restore overwrote manual edit")
    Check(values.graphicsViewDistance == original.graphicsViewDistance and G.PendingCount() == 0, "restore lost original")
    Reset(flavor)
    result = assert(G.Apply(G.Plan("raid", { sharpen = true, contrast = true, reverb = true })))
    Check(result.failed == 0 and values.RAIDsettingsEnabled == "1", "raid preset did not enable native instance settings")
    Check(values.graphicsShadowQuality == "3" and values.raidGraphicsShadowQuality == "1", "raid changes open-world graphics")
    Check(values.Contrast == "55" and values.ResampleAlwaysSharpen == "1" and values.Sound_EnableReverb == "0",
        "explicit optional choices missing")
    result = assert(G.Restore())
    Check(result.failed == 0 and values.RAIDsettingsEnabled == "0" and values.Contrast == "50", "raid recovery incomplete")
end
Reset()
unsupported.graphicsShadowQuality = 2
for _, row in ipairs(G.Plan("balanced")) do Check(row.key ~= "graphicsShadowQuality", "hardware-unsupported value offered") end
unsupported.graphicsShadowQuality = nil
local capabilityPlan = G.Plan("balanced")
unsupported.graphicsShadowQuality = secret
local capabilityResult, capabilityReason = G.Apply(capabilityPlan)
Check(not capabilityResult and capabilityReason == "stale" and #writes == 0, "stale or secret hardware support accepted")
Reset()
adjusted.graphicsSSAO = "1"
local adjustedResult = assert(G.Apply(G.Plan("balanced")))
Check(adjustedResult.failed == 1 and Suite.RootDB.graphicsRecovery.Mainline.graphicsSSAO.applied == "1",
    "adjusted write was not recorded for recovery")
adjusted.graphicsSSAO = nil
G.Restore()
Check(values.graphicsSSAO == "3" and G.PendingCount() == 0, "adjusted native write lost its original")
Reset()
G.Apply(G.Plan("balanced"))
adjusted.graphicsSSAO = "2"
local adjustedRestore = assert(G.Restore())
Check(adjustedRestore.failed == 1 and G.PendingCount() == 1, "adjusted restore discarded retryable recovery")
adjusted.graphicsSSAO = nil
Check(assert(G.Restore()).changed == 1 and values.graphicsSSAO == "3" and G.PendingCount() == 0,
    "adjusted native restore was mistaken for a manual edit on retry")
Reset()
local stale = G.Plan("balanced")
values.graphicsViewDistance = "6"
local result, reason = G.Apply(stale)
Check(not result and reason == "stale" and #writes == 0 and not Suite.RootDB.graphicsRecovery,
    "stale preview changed settings or made a fake backup")
combat = true
result, reason = G.Apply(G.Plan("balanced"))
Check(not result and reason == "combat" and #writes == 0, "combat edge accepted apply")
result, reason = G.Restore()
Check(not result and reason == "combat", "combat edge accepted restore")
Reset()
capability = false
values.graphicsComputeEffects, values.graphicsDepthEffects = nil, secret
for _, row in ipairs(G.Plan("balanced")) do
    Check(row.key ~= "graphicsSpellDensity" and row.key ~= "graphicsComputeEffects" and row.key ~= "graphicsDepthEffects",
        "unsupported or secret setting reached preview")
end
Check(assert(G.Apply(G.Plan("balanced"))).failed == 0, "supported settings did not apply around unavailable settings")
Reset()
refused.graphicsSSAO = true
result = assert(G.Apply(G.Plan("balanced")))
Check(result.failed == 1 and not Suite.RootDB.graphicsRecovery.Mainline.graphicsSSAO, "refused write claims recovery ownership")
refused.graphicsViewDistance = true
result = assert(G.Restore())
Check(result.failed == 1 and G.PendingCount() == 1, "restore failure discarded its backup")
refused.graphicsViewDistance = nil
Check(assert(G.Restore()).failed == 0 and G.PendingCount() == 0, "retry did not restore original")
Reset()
G.Apply(G.Plan("balanced"))
local saved = Suite.RootDB.graphicsRecovery.Mainline
values.graphicsViewDistance = secret
result = assert(G.Restore())
Check(result.failed == 1 and saved.graphicsViewDistance, "secret read lost retryable recovery")
values.graphicsViewDistance = "4"
saved.unrelated = { before = "0", applied = "1" }
saved.Contrast = { before = {}, applied = "55" }
G.Restore()
Check(not saved.unrelated and not saved.Contrast, "malformed or unknown recovery records survived")
Check(values.unrelated == nil, "unknown saved CVar was written")
Reset()
G.Apply(G.Plan("balanced"))
local before = Suite.RootDB.graphicsRecovery.Mainline.graphicsShadowQuality.before
values.graphicsShadowQuality = "5"
G.Apply(G.Plan("balanced"))
Check(Suite.RootDB.graphicsRecovery.Mainline.graphicsShadowQuality.before == before, "reapply overwrote first original")
-- Rejecting a second preset must keep the first successful ownership record.
refused.raidGraphicsViewDistance = true
G.Apply(G.Plan("raid"))
Check(not Suite.RootDB.graphicsRecovery.Mainline.raidGraphicsViewDistance, "refused new raid setting kept fake ownership")
Suite.Client.flavor = "Unknown"
Check(#G.Plan("balanced") == 0 and G.PendingCount() == 0, "unsupported client offered settings")

-- Exercise the actual page's cold build, narrow wrapped layout and controls.
Reset()
local buttons, bindings, texts, refreshers, sections = {}, {}, {}, {}, {}
local function Widget(text, width)
    local widget = { text = text or "", width = width or 208, height = 14 }
    function widget:GetText() return self.text end
    function widget:SetText(value) self.text = value end
    function widget:SetWidth(value) self.width = value end
    function widget:SetHeight(value) self.height = value end
    function widget:SetWordWrap() end
    function widget:ClearAllPoints() end
    function widget:SetPoint(_, x, y) self.x, self.y = x, y end
    function widget:GetStringHeight()
        local lines = 0
        for line in (self.text .. "\n"):gmatch("(.-)\n") do
            lines = lines + math.max(1, math.ceil(#line * 7 / self.width))
        end
        return lines * 14
    end
    return widget
end
P.HM = { GetSectionWidth = function() return 272 end, GetControlLabel = function(widget) return widget.label end }
P.T = { colors = { text = {} } }
P.Meta = function(page, id, key, kind, section)
    return { controlId = id .. "." .. key, classification = kind, sectionId = section, pageKey = page }
end
P.Text = function(_, text, _, y, width)
    local widget = Widget(text, width); widget.y = y; texts[#texts + 1] = widget; return widget
end
P.Description = P.Text
P.SetTranslatedText = function(widget, text) widget:SetText(text) end
P.FinishBody = function(_, body, y) body.bottom = y end
P.Refresh = function() for _, callback in ipairs(refreshers) do callback() end end
P.M = {
    BindDropdownAt = function(_, _, _, _, _, _, _, get, set, meta) bindings[meta.controlId] = { get = get, set = set } end,
    BindSwitchAt = function(_, _, _, _, _, _, get, set, meta) bindings[meta.controlId] = { get = get, set = set } end,
    TrackRefresh = function(_, callback) refreshers[#refreshers + 1] = callback end,
}
P.Button = function(_, _, label, _, _, width, callback, enabled, meta)
    local widget = Widget(); widget.label = Widget(label, width - 24)
    widget.click, widget.enabled = callback, enabled
    buttons[meta.controlId] = widget
    return widget
end
P.LazySection = function(builder, section, _, _, spec)
    local body = {}; sections[section] = body
    spec.finish(body, spec.content(body))
    return body
end
P.Confirm = function(_, _, callback) P.accept = callback end
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/GraphicsPerformance.lua"))("MSUF_Suite_Options", P)
local ctx = {}
P.BuildGraphicsPerformance(ctx, { width = 272 })
Check(#writes == 0 and not Suite.RootDB.graphicsRecovery, "opening page applied settings")
local apply, restore = buttons["graphicsPerformance.apply"], buttons["graphicsPerformance.restore"]
Check(apply and restore and apply.enabled() and not restore.enabled(), "cold actions wrong")
for _, key in ipairs({ "sharpen", "contrast", "reverb" }) do bindings["graphicsPerformance." .. key].set(true) end
bindings["graphicsPerformance.preset"].set("raid")
local preview, feedback = texts[2], texts[3]
Check(apply.y < preview.y - preview.height and restore.y < apply.y - apply.height, "wrapped preview overlaps actions")
Check(restore.height >= restore.label:GetStringHeight() + 12, "narrow restore button clips its label")
apply.click()
Check(values.RAIDsettingsEnabled == "1" and values.Contrast == "55" and restore.enabled(), "UI choices did not reach runtime")
local count = #writes
restore.click()
Check(#writes == count and P.accept, "restore ran before confirmation")
P.accept()
Check(values.RAIDsettingsEnabled == "0" and values.Contrast == "50" and not restore.enabled(), "confirmed UI restore incomplete")
Check(sections.suite_qualityOfLife_graphics_performance.bottom < feedback.y - feedback:GetStringHeight(),
    "feedback extends below accordion")
local search = {}
local afterRestore = #writes
P.AppendGraphicsSearchRows(search)
Check(#search == 2 and search[1].controlId == "graphicsPerformance.apply" and search[2].suiteAlways,
    "cold search does not target exact always-available actions")
Check(#writes == afterRestore, "search collection wrote settings")
print("suite_graphics_performance_contract: " .. checks .. " checks passed")
