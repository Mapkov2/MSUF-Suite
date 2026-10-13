local root = assert(arg[1])
local function Widget(parent)
    local w = { parent = parent, shown = true, scale = 1, scripts = {}, events = {} }
    function w:SetPoint(...) self.point = { ... } end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetOrientation() end
    function w:EnableMouse() end
    function w:SetMinMaxValues() end
    function w:SetValueStep() end
    function w:SetObeyStepOnDrag() end
    function w:SetThumbTexture() self.thumb = Widget(self) end
    function w:GetThumbTexture() return self.thumb end
    function w:CreateTexture() return Widget(self) end
    function w:SetColorTexture() end
    function w:SetJustifyH() end
    function w:SetText(text) self.text = text end
    function w:SetValue(number)
        self.value = number
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, number) end
    end
    function w:SetWidth(width) self.width = width end
    function w:SetHeight(height) self.height = height end
    function w:GetStringHeight() return self.width < 300 and 42 or 28 end
    function w:SetScale(scale) self.scale = scale end
    function w:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
    function w:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function w:SetScript(key, callback) self.scripts[key] = callback end
    function w:RegisterEvent(event) self.events[event] = true end
    function w:UnregisterAllEvents() self.events = {} end
    function w:SetClipsChildren(value) self.clips = value end
    function w:ClearAllPoints() end
    function w:Show() self.shown = true end
    return w
end
UIParent = Widget()
UIParent.scale = .8
CreateFrame = function(_, _, parent) return Widget(parent) end
local configs = { xpBar = { enabled = false, width = 800, height = 40, scale = 200 },
    skyriding = { enabled = false, width = 600, height = 300, scale = 200 } }
local combat, loads, draws, skips = true, 0, 0, 0
local S = { Config = function(id) return configs[id] end }
local P = { S = S, Suite = { Client = { isForever = false } },
    T = { colors = { accent = { 1, 1, 1 }, border = { .1, .1, .1 } } },
    Combat = function() return combat end, Tr = function(text) return text end,
    Text = function(parent, text, x, y, width)
        local label = Widget(parent)
        label.text, label.width = text, width
        return label
    end,
    SetTranslatedText = function(label, text) label.text = text end,
    HM = { SkipHistoryCheckpoint = function() skips = skips + 1 end },
    M = { TrackRefresh = function(ctx, callback) ctx.refresh[#ctx.refresh + 1] = callback end }, W = {} }
function P.W.SettingsRows() error("sample sliders must not enter profile bindings/history") end
local function Draw(parent, config, sample, viewport)
    draws = draws + 1
    assert(config.enabled == false, "preview enabled a disabled module")
    parent.host = parent.host or Widget(parent)
    parent.host:SetSize(config.width, config.height + 23)
    parent.host:SetScale(viewport.scale * math.min(1, viewport.width / (config.width * viewport.scale),
        viewport.height / ((config.height + 23) * viewport.scale)))
    parent.sample = sample
    return parent.host, config.width, config.height + 23
end
C_AddOns = { LoadAddOn = function(name)
    assert(name == "MSUF_Suite_QualityOfLife")
    loads = loads + 1
    S.DrawExperienceBarPreview, S.DrawSkyridingPreview = Draw, Draw
end }
assert(loadfile(root .. "/MSUF_Suite_Options/Menu/PreviewCanvas.lua"))("MSUF_Suite_Options", P)
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/QualityOfLifePreview.lua"))("MSUF_Suite_Options", P)
for _, width in ipairs({ 260, 720 }) do
    for _, id in ipairs({ "xpBar", "skyriding" }) do
        local parent, ctx = Widget(UIParent), { refresh = {} }
        parent.scale = .7
        local bottom = P.BuildQoLIndicatorPreview(ctx, parent, id, width, -42)
        assert(bottom < -42 and skips > 0)
        local ui = ctx.qolIndicatorPreviews[id]
        if combat then
            assert(loads == 0 and draws == 0 and ui.status.text ~= "")
            combat = false
            ui.stage.scripts.OnEvent()
        end
        assert(ui.stage.host and ui.stage.clips and ui.status.text == "")
        assert(configs[id].width * ui.stage.host.scale <= ui.width + .001)
        assert((configs[id].height + 23) * ui.stage.host.scale <= ui.height + .001)
        local key, before = id == "xpBar" and "xp" or "vigor", draws
        ui.sliders[key]:SetValue(0)
        assert(ui.sample[key] == 0 and draws == before + 1, "sample slider did not repaint")
        assert(configs[id].scale == 200 and not configs[id].enabled and not configs[id].xp)
        parent.shown = false
        before = draws
        ctx.refresh[1]()
        assert(draws == before, "hidden preview redrew")
        ui.stage.scripts.OnHide()
        assert(next(ui.stage.events) == nil, "hidden preview retained event listeners")
    end
end
assert(loads == 1, "preview repeatedly loaded its renderer")
P.Suite.Client.isForever = true
assert(P.BuildQoLIndicatorPreview({ refresh = {} }, Widget(), "skyriding", 720, -42) == -42)
print("QoL indicator preview: lazy load, combat recovery, disabled modules, local sliders, scale fitting and hide lifecycle OK")
