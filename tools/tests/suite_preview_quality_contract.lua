local root = assert(arg[1])
local originalLoad, P = loadfile
local mutations = {
    meterText = { "Pages/DamageMeterPreview.lua", 'row.valueText, row, "suite_damageMeter_text"', 'row.valueText, row, "suite_damageMeter_bars"' },
    bank = { "Pages/BagsPreview.lua", 'ui.selected == "bank" and "suite_bags_bank" or "suite_bags_organisation"', '"suite_bags_organisation"' },
    icons = { "Pages/BagsPreview.lua", 'slot.icon:SetTexture(item[1])', 'slot.icon:SetTexture(134400)' },
    warm = { "Pages/BagsPreview.lua", 'if not changed and preview.tab == ui.selected then return end', 'if false then return end' },
    cdmHidden = { "Pages/CooldownManagerPreview.lua", 'if not ui.previewBody:IsVisible() or P.Combat() then return end', 'if P.Combat() then return end' },
    skinHidden = { "Pages/AppearancePreview.lua", 'if frame:IsVisible() then refresh(value) end', 'refresh(value)' },
    chatReady = { "Pages/Chat.lua", ' and parts.fontReady == ready', '' },
    chatRegen = { "Pages/Chat.lua", 'P.PreviewCanvas.Watch({ header = sample, ctx = ctx }, Refresh)', 'M.TrackRefresh(ctx, Refresh)\n    Refresh()' },
}
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    local mutation = mutations[arg[3]]
    if mutation and path:find("MSUF_Suite_Options/" .. mutation[1], 1, true) then
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local a, z = assert(source:find(mutation[2], 1, true))
        chunk = assert(loadstring(source:sub(1, a - 1) .. mutation[3] .. source:sub(z + 1), "@" .. path))
    end
    return function(addon, namespace)
        if path:find("MSUF_Suite_Options/Menu/Bridge.lua", 1, true) then P = namespace end
        return chunk(addon, namespace)
    end
end
assert(originalLoad(root .. "/tools/tests/suite_menu_ux_contract.lua"))()
loadfile = originalLoad
local function Context(page)
    return { key = page, width = 340, sections = {}, widgets = {}, refreshers = {}, pageItems = {}, wrapper = CreateFrame("Frame") }
end
local function Refresh(ctx) for _, fn in ipairs(ctx.refreshers) do fn() end end
local function Build(page)
    local ctx = Context(page)
    P.M.pages[page].build(ctx)
    Refresh(ctx)
    return ctx, ctx.suiteWorkspace
end
-- The options renderer receives a runtime window-shaped provider. The real
-- provider is exercised separately by suite_meter_menu_preview_contract.
P.S.DamageMeterDrawMenuPreview = function(parent)
    if rawget(parent, "provider") then return parent.provider end
    local win = { frame = CreateFrame("Frame", nil, parent), buttons = {}, rows = {} }
    win.frame:SetSize(420, 240)
    win.header, win.body = CreateFrame("Button", nil, win.frame), CreateFrame("Frame", nil, win.frame)
    win.title, win.timer = win.header:CreateFontString(), win.header:CreateFontString()
    for _, key in ipairs({ "settings", "reset", "session", "type" }) do win.buttons[key] = CreateFrame("Button", nil, win.header) end
    for i = 1, 3 do
        local row = CreateFrame("Button", nil, win.body)
        row.icon, row.nameText, row.valueText = row:CreateTexture(), row:CreateFontString(), row:CreateFontString()
        win.rows[i] = row
    end
    parent.provider = win
    return win
end
local ctx, ui = Build("suite_damageMeter")
local focused
ui.Focus = function(_, section) focused = section end
local targets = ui.meterPreview.targets
targets.rows[1].value.scripts.OnClick()
assert(focused == "suite_damageMeter_text", "meter value text opened bar settings")
targets.rows[1].name.scripts.OnClick()
assert(focused == "suite_damageMeter_text", "meter name opened bar settings")
ui.meterPreview.stage.provider.rows[1].scripts.OnClick()
assert(focused == "suite_damageMeter_bars", "meter bar did not open bar settings")
targets.timer.scripts.OnClick()
assert(focused == "suite_damageMeter_timer", "meter clock did not open timer settings")
local paints = 0
P.S.BagsPaintPreviewWindow = function() paints = paints + 1 end
P.S.BagsStylePreviewLabel = function() end
C_Item.GetItemQualityColor = function(q) return q / 5, .5, 1 end
ctx, ui = Build("suite_bags")
ui.Focus = function(_, section) focused = section end
local preview = ui.bagsPreview
for _, slot in ipairs(preview.slots) do assert(slot.icon.texture and slot.icon.texture ~= 134400, "bag preview still contains question marks") end
local prior = paints
Refresh(ctx)
assert(paints == prior, "unchanged bag preview redrew its chrome")
ui.selected = "bank"
ui.refreshPreview()
preview.search.scripts.OnClick()
assert(focused == "suite_bags_bank", "bank search opened inventory settings")
preview.categories.scripts.OnClick()
assert(focused == "suite_bags_bank", "bank categories opened inventory settings")
assert(ui.header:GetHeight() >= 344 + (preview.footer:GetStringHeight() or 14), "bag footer exceeds the reserved header")
prior = paints
ui.header:Hide()
Refresh(ctx)
assert(paints == prior, "hidden bags preview repainted")
-- The skin preview owns these engine states. Its wrapper must stop native
-- paint calls when the sample is hidden, without changing runtime states.
local states, skinPaints = {}, 0
local function Attach(frame)
    local state = { target = frame, refresh = function() skinPaints = skinPaints + 1 end }
    states[#states + 1] = state
    return state
end
local skin = { Surface = { Attach = Attach, SkinOwnedButton = Attach },
    Theme = { GetColor = function() return 1, 1, 1 end }, LookPresets = {}, DB = { theme = { look = "custom" } } }
local skinCtx = Context("suite_skin")
P.BuildSkinMenuPreview(skinCtx, P.W.PageBuilder(skinCtx), skin)
local section = skinCtx.skinPreview.section
for _, state in ipairs(states) do state.refresh(state) end
prior = skinPaints
section:Hide()
for _, state in ipairs(states) do state.refresh(state) end
assert(skinPaints == prior, "hidden skin preview repainted runtime surfaces")
section:Show()
for _, state in ipairs(states) do state.refresh(state) end
assert(skinPaints > prior, "reopened skin preview did not resume its runtime painter")
-- Editor selection passes isolated saved-spec data and keeps profile lists.
P.CDMPage.ui = nil
local sample, renders = nil, 0
P.S.CooldownManagerEditorContext = function(spec, classID) return {spec=spec,classID=classID,bars={}} end
P.S.CooldownManagerRenderPreview = function(_, _, _, _, value)
    sample, renders = value, renders + 1
    return nil
end
local cdmCtx = Build("suite_cooldownManager")
local cdm = P.CDMPage.ui
local saved = P.S.Config("cooldownManager")
local lists = saved.listsData
cdm.classPicker.set(9)
assert(sample and sample.spec == 265 and sample.classID == 9,
    "selected specialization did not reach the isolated CDM canvas")
assert(saved.listsData == lists, "class selector changed saved CDM lists")
cdm.classPicker.set(0)
assert(sample == nil and P.CDMPage.targetSpec == nil, "character selection did not restore the CDM canvas")
prior = renders
cdm.previewBody:Hide()
cdm.PaintPreview()
assert(renders == prior, "hidden CDM canvas rendered")
-- The generic fixture previously tried a missing Chat addon. Reset only
-- this isolated preview helper to model a genuinely cold menu open.
assert(originalLoad(root .. "/MSUF_Suite_Options/Menu/PreviewCanvas.lua"))("MSUF_Suite_Options", P)
local combat, chatLoads, chatPaints, eventFrames = true, 0, 0, {}
local originalCreate, originalCombat, originalAddonLoad = CreateFrame, P.Combat, C_AddOns.LoadAddOn
P.Combat = function() return combat end
P.S.ChatStylePreviewFonts = nil
CreateFrame = function(...)
    local frame = originalCreate(...)
    eventFrames[#eventFrames + 1] = frame
    return frame
end
C_AddOns.LoadAddOn = function(addon)
    if addon ~= "MSUF_Suite_Chat" then return originalAddonLoad(addon) end
    chatLoads = chatLoads + 1
    P.S.ChatStylePreviewFonts = function() chatPaints = chatPaints + 1 end
    return true
end
local chatCtx = Build("suite_chat")
local parts, regen = chatCtx.chatPreview, nil
assert(parts and chatLoads == 0 and chatPaints == 0, "cold combat loaded or painted the Chat runtime")
for _, frame in ipairs(eventFrames) do
    local events = rawget(frame, "_events")
    if rawget(frame, "parent") == parts.sample and events and events.PLAYER_REGEN_ENABLED then regen = frame end
end
assert(regen and regen.scripts.OnEvent, "Chat preview has no visible post-combat retry event")
combat = false
regen.scripts.OnEvent(regen, "PLAYER_REGEN_ENABLED")
assert(chatLoads == 1 and chatPaints == 1, "cold-combat Chat preview never retried its runtime font painter")
for _ = 1, 100 do Refresh(chatCtx) end
assert(chatPaints == 1, "unchanged Chat preview repainted its fonts")
parts.sample:Hide()
regen.scripts.OnHide(regen)
assert(not next(regen._events), "hidden Chat preview retained its regen listener")
local chatConfig = P.S.Config("chat")
chatConfig.fontSize = chatConfig.fontSize + 1
Refresh(chatCtx)
assert(chatPaints == 1, "hidden Chat preview repainted its fonts")
parts.sample:Show()
regen.scripts.OnShow(regen)
assert(chatPaints == 2 and regen._events.PLAYER_REGEN_ENABLED, "visible Chat preview did not resume")
CreateFrame, P.Combat, C_AddOns.LoadAddOn = originalCreate, originalCombat, originalAddonLoad
print("Preview quality: distinct meter targets, bank routing, useful items, reserved height, warm/hidden budgets and cold-combat Chat retry passed")
