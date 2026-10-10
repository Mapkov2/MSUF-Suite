local root = assert(arg[1])
local combat, spec, creations, writes = false, 101, 0, 0
local secret = setmetatable({}, { __lt = function() error("secret comparison") end })
local info = { [11] = { spellID = 589, hasAura = true, selfAura = false, isKnown = true, linkedSpellIDs = {} },
    [12] = { spellID = 34914, hasAura = true, selfAura = false, isKnown = true, linkedSpellIDs = {} } }
C_CooldownViewer = {
    GetCooldownViewerCooldownInfo = function(id) return info[id] end,
    GetCooldownViewerCategorySet = function(category) return category == 0 and { 11, 12 } or {} end,
}
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return spec, "Spec" end,
}
UnitClass = function() return "Priest", "PRIEST" end
local NS = {
    Public = function(value) return value ~= secret end,
    InCombat = function() return combat end,
    Safety = { IsForbidden = function() return false end },
    RGB = function(hex)
        return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    end,
    HostBridge = {},
}
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateAuraColors.lua"))("MSUF_Suite", NS)
local A = NS.NameplateAuraColors
MSUF_NS = { MSUF_Auras3 = { TargetDotData = { PRIEST = { { 589 }, { 34914 }, { 335467 }, { secret }, { "bad" } } } } }
local suggestions = A.Suggestions()
assert(#suggestions == 3 and suggestions[1].id == 589 and suggestions[1].cooldown == 11)
assert(suggestions[1].curated and suggestions[3].id == 335467 and suggestions[3].curated
    and suggestions[3].cooldown == nil, "curated host IDs absent from Blizzard's catalog were lost")
suggestions[1].id = 1
assert(MSUF_NS.MSUF_Auras3.TargetDotData.PRIEST[1][1] == 589, "host DoT catalog was shared mutably")
MSUF_NS = nil
assert(#A.Suggestions() == 2, "older hosts lost native suggestions")
assert(A.ID(secret) == nil and A.ID(0 / 0) == nil and A.ID(1.5) == nil and A.ID(2147483648) == nil)
local saved = { [101] = { { id = 589, ids = { 589 }, enabled = true, color = "112233", cooldown = 11 },
    { id = 34914, ids = { 34914 }, enabled = true, color = "445566", cooldown = 12 },
    { id = 999, ids = { 999 }, enabled = false, color = "aabbcc" } },
    [102] = { { id = 777, ids = { 777 }, enabled = true, color = "ccddee" } } }
local encoded = A.Encode(saved)
local decoded = A.Decode(encoded)
assert(A.Encode(decoded) == encoded and decoded[101][3].enabled == false and decoded[102][1].id == 777)
assert(next(A.Decode("broken")) == nil and next(A.Decode(string.rep("x", 60001))) == nil)
info[12].isKnown = false
assert(A.Paused(decoded[101][2]) and #A.Selected(decoded[101]) == 1)
info[12].spellID = 123
assert(not A.Paused(decoded[101][2]), "reused cooldown handle paused a different aura")
info[12].spellID, info[12].isKnown = 34914, true
assert(not A.Paused({ id = 999 }), "manual aura IDs were treated as unlearned cast spells")
local cfg = { auraColorsEnabled = true, auraColorsAll = "48af97", auraColorsNone = "d9ab4b",
    auraColorsNoneEnabled = false, auraColorsIndividual = false, auraColorsData = encoded, look = 4, enemy = true }
assert(A.Preview({}, {}, cfg) == nil, "empty selection activated the all color")
assert(A.Preview(decoded[101], {}, cfg) == nil)
cfg.auraColorsIndividual = true
assert(A.Preview(decoded[102], { [777] = true }, cfg) == "ccddee",
    "the all color overrides the only selected DoT's individual color")
cfg.auraColorsIndividual = false
assert(A.Preview(decoded[102], { [777] = true }, cfg) == cfg.auraColorsAll,
    "a singleton without individual colors lost its all color")

local containers, textures = {}, {}
local function Region(parent)
    local r = { parent = parent, points = {}, shown = true }
    function r:SetPoint(point, target, relative, x, y)
        assert(not self.native, "aura colors reanchored a native nameplate frame")
        assert(not self.sealed, "addon changed the layout of a sealed native slot")
        self.points[point] = { target = target, relative = relative, y = y or 0 }
        writes = writes + 1
    end
    function r:ClearAllPoints() assert(not self.sealed); self.points = {}; writes = writes + 1 end
    function r:SetSize(w, h) assert(not self.sealed and not self.native); self.width, self.height = w, h end
    function r:SetHeight(h) assert(not self.sealed and not self.native); self.height = h end
    function r:SetAllPoints(target) assert(not self.native); self.allPoints = target; writes = writes + 1 end
    function r:SetIgnoringChildrenForBounds(value) self.ignoreChildrenForBounds = value end
    function r:SetCollapsesLayout(value) assert(not self.sealed); self.collapse = value end
    function r:SetMouseClickEnabled(value) assert(not self.sealed and value == false); self.clicks = value end
    function r:SetMouseMotionEnabled(value) assert(not self.sealed and value == false); self.motion = value end
    function r:SetTexture(path) self.path = path end
    function r:SetColorTexture(...) self.color = { ... }; writes = writes + 1 end
    function r:AddMaskTexture(mask) self.mask = mask end
    function r:Show() assert(not self.native); self.shown = true; writes = writes + 1 end
    function r:Hide() assert(not self.native); self.shown = false; writes = writes + 1 end
    function r:SetShown(value) assert(not self.native); self.shown = value == true; writes = writes + 1 end
    function r:IsShown() error("addon queried native secret visibility") end
    function r:GetHeight() error("addon queried native secret height") end
    function r:CreateMaskTexture() return Region(self) end
    function r:CreateTexture(_, layer, _, sublevel)
        local t = Region(self)
        t.layer, t.sublevel, t.order = layer, sublevel, #textures + 1
        textures[#textures + 1] = t
        return t
    end
    return r
end
UIParent = Region()
CreateFrame = function(kind, _, parent, template)
    creations = creations + 1
    local r = Region(parent)
    if kind == "AuraContainer" then
        assert(template == "CustomAuraContainerTemplate")
        r.slots = {}
        function r:AddAuraSlot(key, filter, options)
            assert(filter == "HARMFUL|PLAYER", "other players' or friendly auras included")
            local slot = Region(self)
            options.initializeFrame(slot)
            slot.sealed, slot.filter = true, options.candidateFilters
            self.slots[key] = slot
            return slot
        end
        function r:SetAuraSlotCandidateFilters(key, filter) self.slots[key].filter = filter end
        function r:SetEnabled(value) self.enabled = value end
        function r:SetUnit(unit) self.unit = unit end
        containers[#containers + 1] = r
    else
        assert(template == "DisableUntrustedLayoutScriptsTemplate")
        assert(parent == UIParent, "aura helpers joined the native nameplate hierarchy")
    end
    return r
end
local plate = Region(UIParent)
local health = Region(plate)
plate.native, health.native = true, true
health.height = 32
local fill = Region(health)
function health:GetStatusBarTexture() return fill end
local uf = { HealthBarsContainer = { healthBar = health } }
local private = { NS = NS, Mode = { LOOK_BLIZZARD = 2 } }
assert(loadfile(root .. "/MSUF_Suite_Nameplates/AuraColors.lua"))("MSUF_Suite_Nameplates", private)
local C = private.AuraColors
local module = {}
C.Bind(module)
C.Configure({ auraColorsEnabled = false })
C.Apply(uf, "nameplate1", true)
assert(creations == 0 and #textures == 0, "disabled feature allocated frames")
C.Configure(cfg)
C.Apply(uf, "nameplate1", true)
assert(creations == 2 and #textures == A.LIMIT + 2 and #containers == 1)
local container = containers[1]
local wrapper = container.parent
assert(wrapper.parent == UIParent and wrapper.ignoreChildrenForBounds,
    "oversized aura slots entered native nameplate bounds")
assert(wrapper.allPoints == health and health.parent == plate and health.height == 32,
    "helper setup changed the native plate hierarchy or dimensions")
local function NativePass(present)
    for _, slot in pairs(container.slots) do
        slot.nativeShown = false
        if container.enabled then
            for id in pairs(present) do if slot.filter.includeSpellIDs[id] then slot.nativeShown = true end end
        end
    end
end
local Top
local function Bottom(region)
    if region == health then return 0 end
    local p = region.points.BOTTOM
    if p then return (p.relative == "TOP" and Top(p.target) or Bottom(p.target)) + p.y end
    local top = region.points.TOP
    if top then return (top.relative == "TOP" and Top(top.target) or Bottom(top.target)) + top.y - (region.height or 0) end
    error("missing native anchor")
end
Top = function(region)
    return Bottom(region) + (region.collapse and not region.nativeShown and 0 or region.height or 0)
end
local function VisibleColor()
    local chosen
    for _, texture in ipairs(textures) do
        local visible, parent = texture.shown, texture.parent
        while parent do visible, parent = visible and parent.shown, parent.parent end
        if visible then
            local maskBottom = Bottom(texture.mask)
            if maskBottom < health.height and maskBottom + texture.mask.height > 0 then chosen = texture end
        end
    end
    if not chosen then return nil end
    return string.format("%02x%02x%02x", math.floor(chosen.color[1] * 255 + .5),
        math.floor(chosen.color[2] * 255 + .5), math.floor(chosen.color[3] * 255 + .5))
end
for _, individual in ipairs({ false, true }) do
    for _, none in ipairs({ false, true }) do
        cfg.auraColorsIndividual, cfg.auraColorsNoneEnabled = individual, none
        C.Configure(cfg)
        C.Apply(uf, "nameplate1", true)
        for mask = 0, 3 do
            local present = { [9999] = true }
            if mask % 2 == 1 then present[589] = true end
            if mask >= 2 then present[34914] = true end
            NativePass(present)
            local expected = mask == 3 and cfg.auraColorsAll or mask == 0 and none and cfg.auraColorsNone
                or individual and mask == 1 and "112233" or individual and mask == 2 and "445566" or nil
            assert(VisibleColor() == expected, "native collapsed mask predicate / layer priority differed from preview")
        end
    end
end
local beforeFrames, beforeTextures, beforeWrites = creations, #textures, writes
for _, slot in pairs(container.slots) do assert(slot.clicks == false and slot.motion == false) end
for i = 1, 100 do C.Apply(uf, "nameplate1", true) end
assert(creations == beforeFrames and #textures == beforeTextures and writes == beforeWrites,
    "warm role/health repaint allocated or rewrote aura visuals")
C.Configure(cfg)
C.Apply(uf, "nameplate1", true)
assert(writes == beforeWrites, "unrelated settings refresh rebuilt the native aura layout")
combat = true
C.Configure(cfg)
assert(module.needsRefresh, "combat configuration was not deferred")
C.Restore(uf)
assert(not container.enabled and not wrapper.shown and VisibleColor() == nil,
    "removed plate retained its detached aura helpers")
plate = Region(UIParent)
plate.native = true
health.parent = plate
C.Apply(uf, "nameplate2", true)
assert(container.unit == "nameplate2" and wrapper.shown and wrapper.parent == UIParent
    and creations == beforeFrames, "recycled plate retained its previous unit or reparented/recreated helpers")
NativePass({ [589] = true })
assert(VisibleColor() == "112233")
health.shown = false
C.Apply(uf, "nameplate2", true)
assert(not health.shown and VisibleColor() == nil, "colors changed native plate visibility")
health.shown = true
assert(VisibleColor() == "112233", "detached helpers lost inherited native texture visibility")
combat = false
spec = 102
C.Configure(cfg)
C.Apply(uf, "nameplate2", true)
NativePass({ [589] = true })
assert(VisibleColor() == cfg.auraColorsNone, "new spec read the old spec's list")
NativePass({ [777] = true })
assert(VisibleColor() == "ccddee", "runtime overrides the only selected DoT's individual color")
C.Apply(uf, "nameplate2", false)
assert(VisibleColor() == nil and not container.enabled and not wrapper.shown,
    "friendly plate retained detached harmful aura helpers")
cfg.look = 2
C.Configure(cfg)
C.Apply(uf, "nameplate2", true)
assert(VisibleColor() == nil and not wrapper.shown)
cfg.look, cfg.auraColorsData = 4, ""
C.Configure(cfg)
C.Apply(uf, "nameplate2", true)
assert(VisibleColor() == nil and not wrapper.shown, "zero selected DoTs retained aura helpers")

-- Maximal selections remain isolated for every public synthetic aura subset.
local many = {}
for i = 1, A.LIMIT do
    many[i] = { id = 1000 + i, ids = { 1000 + i }, enabled = true, color = string.format("%06x", i * 1000) }
end
spec = 101
cfg.auraColorsIndividual, cfg.auraColorsNoneEnabled = true, true
cfg.auraColorsData = A.Encode({ [101] = many })
C.Configure(cfg)
C.Apply(uf, "nameplate3", true)
for subset = 0, 2 ^ A.LIMIT - 1 do
    local present, first, count = {}, nil, 0
    for i, row in ipairs(many) do
        if math.floor(subset / 2 ^ (i - 1)) % 2 == 1 then
            present[row.id], first, count = true, first or row.color, count + 1
        end
    end
    NativePass(present)
    local expected = count == A.LIMIT and cfg.auraColorsAll or first or cfg.auraColorsNone
    assert(VisibleColor() == expected, "maximal selection mask priority changed")
    for _, slot in pairs(container.slots) do
        local owner = slot
        while owner do assert(owner ~= health and owner ~= plate); owner = owner.parent end
    end
end
assert(plate.shown and health.shown, "aura colors hid a native plate")
cfg.auraColorsEnabled = false
C.Configure(cfg)
C.Apply(uf, "nameplate3", true)
assert(not wrapper.shown and not container.enabled and VisibleColor() == nil)
local disabledWrites = writes
for i = 1, 100 do C.Apply(uf, "nameplate3", true) end
assert(writes == disabledWrites, "disabled detached helpers kept repainting")

local listener, watcher, changes = nil, nil, 0
NS.DB = {}
NS.Registry = { AddListener = function(_, callback) listener = callback end }
local config = { auraColorsEnabled = false, auraColorsAll = "ffffff", auraColorsNone = "dddddd",
    auraColorsIndividual = false, auraColorsNoneEnabled = false, auraColorsData = encoded }
local P = { Suite = NS, Combat = function() return combat end, Refresh = function() end,
    S = { Config = function() return config end }, Get = function(_, key) return config[key] end }
function P.Set(_, key, value) changes = changes + 1; config[key] = value; return true end
function P.SetMany(_, values)
    changes = changes + 1
    for key, value in pairs(values) do config[key] = value end
    return true
end
CreateFrame = function()
    local r = {}
    function r:SetScript(_, fn) self.callback = fn end
    function r:RegisterEvent(event) self.event = event end
    function r:UnregisterEvent() self.event = nil end
    watcher = r
    return r
end
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesAuraDraft.lua"))("MSUF_Suite_Options", P)
local D = P.NameplatesAuraDraft
spec = 101
combat = true
D.Set("auraColorsEnabled", true)
D.Set("auraColorsEnabled", false)
D.Set("auraColorsAll", "abcdef")
assert(D.Get("auraColorsEnabled") == false and config.auraColorsAll == "ffffff" and changes == 0 and D.Pending())
watcher.callback()
assert(changes == 0, "early combat-exit event wrote before lockdown ended")
combat = false
watcher.callback()
assert(changes == 1 and config.auraColorsAll == "abcdef" and not D.Pending(), "latest draft was not applied atomically")
combat = true
D.Set("auraColorsAll", "123456")
listener(D, "profile", "other")
listener(D, "profile", "original")
combat = false
watcher.callback()
assert(config.auraColorsAll == "abcdef", "draft survived A/B/A profile switch")
combat = true
D.Set("auraColorsAll", "123456")
config.auraColorsAll = "654321"
combat = false
watcher.callback()
assert(config.auraColorsAll == "654321", "draft overwrote a later profile/import setting")
local selection = A.Decode(config.auraColorsData)
local beforeChanges = changes
D.ResetColors()
local after = A.Decode(config.auraColorsData)
assert(changes == beforeChanges + 1 and #after[101] == #selection[101] and after[101][3].enabled == false)
assert(after[102][1].color == selection[102][1].color, "color reset changed another spec")
local originalRows = D.Rows()
local getColor, setColor = D.BindColor("auraColorsData", originalRows[1])
D.Edit(function(rows) rows[1], rows[2] = rows[2], rows[1] end)
D.selected = 102
setColor("111111")
local changed = A.Decode(config.auraColorsData)
assert(changed[101][2].id == 589 and changed[101][2].color == "111111"
    and changed[101][1].color == A.DEFAULT_COLOR and changed[102][1].color == "ccddee",
    "open picker redirected its write after reorder or spec selection")
assert(getColor() == "111111")
setColor(A.DEFAULT_COLOR)
local staleGet, staleSet = D.BindColor("auraColorsAll")
listener(D, "profile", "B")
listener(D, "profile", "A")
assert(staleSet("121212") == false and staleGet() == "48af97")
combat = true
D.Set("auraColorsAll", "123456")
D.Discard()
combat = false
watcher.callback()
assert(config.auraColorsAll == "48af97", "discarded draft applied")
print("Native DoT masks, curated host IDs, spec/profile/combat lifecycle and warm/disabled budgets passed")

-- Use each real host's bindings, whose normal callbacks refuse combat.
-- Feature-owned callbacks must reach the draft without touching the DB.
for _, host in ipairs({ "MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames-Classic" }) do
    GetNumSpecializations = function() return 2 end
    C_Spell = { GetSpellName = function(id) return "Spell " .. id end, GetSpellTexture = function() return 1 end }
    local controls, metas, fonts = {}, {}, {}
    local function Widget()
        local w = { scripts = {} }
        function w:SetScript(event, callback) self.scripts[event] = callback end
        function w:SetOnValueChanged(callback) self.change = callback end
        function w:SetOnValueCommitted(callback) self.commit = callback end
        function w:SetValue(value) self.value = value end
        function w:SetChecked(value) self.checked = value end
        function w:SetText(value) self.text = value end
        function w:GetStringHeight() return 14 end
        function w:GetFrameLevel() return 1 end
        function w:GetParent() return nil end
        function w:CreateTexture() return Widget() end
        function w:CreateFontString()
            local font = Widget()
            fonts[#fonts + 1] = font
            return font
        end
        function w:SetTextColor(r, g, b, a)
            assert(type(r) == "number" and type(g) == "number" and type(b) == "number"
                and (a == nil or type(a) == "number"), host .. ": invalid native SetTextColor arguments")
            self.textColor = { r, g, b, a }
        end
        return setmetatable(w, { __index = function(_, key)
            if key:sub(1, 6) == "_msuf2" or key == "title" then return nil end
            return function() end
        end })
    end
    local M = { ApplyService = {}, IsConfigCombatLocked = function() return combat end,
        MarkMenuDataDirty = function() end, KeySet = function(...) return { ... } end,
        DeclareExactSearchPreparation = function() end, RegisterRuntimeControl = function() end,
        FindPageEntry = function() end,
        Theme = { colors = { text = { 1, 1, 1, 1 }, muted = { 0.5, 0.6, 0.7, 1 } } } }
    function M.AssignNamedValues(target, names, ...)
        local i = 0
        for name in names:gmatch("%S+") do i = i + 1; target[name] = select(i, ...) end
    end
    function M.Assign(target, values)
        for key, value in pairs(values) do target[key] = value end
    end
    function M.WordList(names)
        local values = {}
        for name in names:gmatch("%S+") do values[#values + 1] = name end
        return values
    end
    function M.KeySetFromWords(names)
        local values = {}
        for name in names:gmatch("%S+") do values[name] = true end
        return values
    end
    CreateFrame = Widget
    assert(loadfile(root .. "/../" .. host .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua"))(
        "MSUF_Options", { MSUF2 = M, Translate = function(text) return text end })
    local bindings = assert(loadfile(root .. "/../" .. host .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Bindings.lua"))
    bindings("MSUF_Options", { MSUF2 = M })
    function M.RegisterControlMetadata(_, meta) metas[meta.key] = meta end
    function M.AddTooltip() end
    function M.TrackRefresh(ctx, callback) M.AddRefresher(ctx, callback) end
    local W = { _Shared = {} }
    M.Widgets = W
    M.Theme.Button = Widget
    local widgetsFile = host == "MidnightSimpleUnitFrames" and "MSUF_Menu2_Widgets.lua" or "MSUF_Menu2_Widgets_ContextColors.lua"
    assert(loadfile(root .. "/../" .. host .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/" .. widgetsFile))(
        "MSUF_Options", { MSUF2 = M })
    function W.SettingsRows(ctx, _, spec)
        local grid = { controls = {}, bottomY = spec.y - #spec.rows * 40 }
        for _, row in ipairs(spec.rows) do
            local w = Widget()
            w.values = type(row.values) == "function" and row.values() or row.values
            controls[row.key], metas[row.key] = w, row
            grid.controls[row.id] = w
            if row.kind == "toggle" then M.BindToggle(ctx, w, row.get, row.set, row)
            else M.BindDropdown(ctx, w, row.get, row.set, row) end
        end
        return grid
    end
    function M.BindTextInputAt(ctx, _, _, _, _, _, get, set, blur, meta)
        local w = Widget()
        M.BindTextInput(ctx, w, get, set, blur, meta)
        controls[meta.key] = w
        return w
    end
    P.M, P.W = M, W
    P.T = { Button = Widget }
    P.HM = { GetSectionWidth = function() return 720 end }
    P.Tr = function(text) return text end
    P.Help = function(text) return text end
    P.Description = Widget
    -- Use the real Suite text bridge and host theme, including numeric C sinks.
    MSUF2 = M
    MSUFSuite = { Suite = P.S, FontRendering = {}, Database = {},
        HostBridge = { Menu2 = function() return P.HM end } }
    local textBridge = {}
    assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Bridge.lua"))("MSUF_Suite_Options", textBridge)
    P.Text = textBridge.Text
    P.SetTranslatedText = function(widget, text) widget:SetText(text) end
    P.FinishBody = function() end
    P.RGB = NS.RGB
    CreateFrame = Widget
    P.Meta = function(_, _, key, classification, section)
        return { key = key, classification = classification, sectionId = section,
            historyMode = classification == "action" and "none" or nil,
            settingKey = classification == "setting" and "msufsuite.nameplates." .. key or nil }
    end
    combat, spec, D.selected = false, 101, 101
    config.auraColorsEnabled = false
    config.auraColorsData = A.Encode({ [101] = { saved[101][1] }, [102] = saved[102] })
    local baseline, before = config.auraColorsData, changes
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesAuraColors.lua"))("MSUF_Suite_Options", P)
    P.NameplatesAuraUI.Build({ key = "suite_nameplates", refreshers = {} }, { width = 720 }, Widget())
    assert(#fonts > 1, host .. ": nameplate labels bypassed the real theme")
    for _, font in ipairs(fonts) do
        local color, muted = font.textColor, M.Theme.colors.muted
        assert(color and color[1] == muted[1] and color[2] == muted[2] and color[3] == muted[3],
            host .. ": supporting text lost the muted theme color")
    end
    local specMeta = metas["action.auraSpec"]
    assert(specMeta and specMeta.classification == "action" and specMeta.historyMode == "none"
        and specMeta.settingKey == nil, "spec selector advertises a false data setting")
    combat = true
    local toggle = controls.auraColorsEnabled
    toggle.scripts.OnClick(toggle)
    assert(D.Pending() and D.Get("auraColorsEnabled") == true and config.auraColorsEnabled == false,
        host .. ": real host binder blocked the feature draft toggle")
    controls["action.auraSpec"].change(101)
    controls["action.auraSample"].change("none")
    assert(D.sample == "none", host .. ": real host binder blocked preview selection")
    controls["action.auraSuggestion"].change(2)
    controls["action.auraCustom"].commit("335467")
    local rows = D.Rows()
    assert(#rows == 3 and rows[2].id == 34914 and rows[3].id == 335467,
        host .. ": real host binder blocked suggestion/custom-ID additions")
    local entry = controls["action.auraEntry1"]
    entry.scripts.OnClick(entry)
    assert(D.Rows()[1].enabled == false and config.auraColorsData == baseline and changes == before,
        host .. ": list edits bypassed the combat draft or the checkbox was blocked")
    combat = false
    watcher.callback()
    assert(changes == before + 1 and config.auraColorsEnabled == true and #A.Decode(config.auraColorsData)[101] == 3,
        host .. ": real UI draft did not flush in one transaction")
    -- Resolve this feature's real targets through the host's actual contextual
    -- picker bridge. Exercise repeated drags and the cancel/restore callback.
    local shortcut, owners
    P.HM.ReleaseColorShortcut = function(button) shortcut = button end
    P.AttachSectionReset = function() end
    P.LazySection = function(_, _, _, _, options)
        local body = Widget()
        options.shell(body)
        return body
    end
    W.OpenColorContextPicker = function(_, targets) owners = targets end
    config.auraColorsIndividual, config.auraColorsNoneEnabled = true, true
    config.auraColorsData = A.Encode({ [101] = { saved[101][1] }, [102] = saved[102] })
    P.BuildNameplatesAuraColors({ refreshers = {} }, { width = 720 }, {})
    shortcut.scripts.OnClick(shortcut)
    assert(owners and #owners == 3, host .. ": feature picker lost global/individual color targets")
    local palette = { "04e18a", "f3027c", "126bd9" }
    for i, hex in ipairs(palette) do
        local r, g, b = NS.RGB(hex)
        owners[i]:SetRGB(r, g, b)
        owners[i]._msuf2OnColorChanged(r, g, b)
    end
    assert(config.auraColorsAll == palette[1] and config.auraColorsNone == palette[2]
        and A.Decode(config.auraColorsData)[101][1].color == palette[3],
        host .. ": contextual picker RGB did not reach the correct stored hex colors")
    local r, g, b = owners[3]:GetRGB()
    assert(r == 18 / 255 and g == 107 / 255 and b == 217 / 255, host .. ": picker readback changed RGB channels")
    owners[3]._msuf2OnColorChanged(1, 0, 0)
    owners[3]._msuf2OnColorChanged(r, g, b)
    assert(A.Decode(config.auraColorsData)[101][1].color == palette[3],
        host .. ": repeated picker writes/cancel failed to restore the individual color")
    for key, value in pairs(config) do cfg[key] = value end
    C.Configure(cfg)
    C.Apply(uf, "nameplate4", true)
    NativePass({ [589] = true })
    assert(VisibleColor() == palette[3] and A.Preview(A.Selected(D.Rows()), { [589] = true }, cfg) == palette[3],
        host .. ": picker color differs from singleton runtime/preview")
    NativePass({})
    assert(VisibleColor() == palette[2], host .. ": picker warning color differs from runtime")
    cfg.auraColorsIndividual = false
    C.Configure(cfg)
    C.Apply(uf, "nameplate4", true)
    NativePass({ [589] = true })
    assert(VisibleColor() == palette[1], host .. ": picker all color differs from runtime")
end
print("Actual Retail/Classic themes and callbacks: numeric fonts, drafts, picker RGB persistence and runtime/preview colors passed")
