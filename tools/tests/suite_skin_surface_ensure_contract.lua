-- Hooks that run per row initialization or per native update (Auction House
-- rows while scrolling, damage meter rows, paper doll slot and stats
-- updates) attach through Surface.Ensure: a surface that already shows its
-- spec, visible and painted for the current generation, costs no paint.
-- Surface.Attach keeps repainting fully. Real Defaults, Theme, Safety,
-- Registry, Geometry, Surface, AdapterKit, Commerce, DamageMeter and
-- PaperDollChrome.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

securecallfunction = function(callback, ...) return callback(...) end
InCombatLockdown = function() return false end
Enum = { UITextureSliceMode = { Stretched = 1 } }
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
C_Timer = { After = function(_, callback) callback() end }
dofile(root .. "/tools/tests/skin_registry_timer_fixture.lua")(C_Timer)

local paints = 0
local function Texture()
    local texture = { shown = true }
    for _, method in ipairs({ "SetTexture", "SetVertexColor", "SetGradient", "ClearTextureSlice",
        "SetTextureSliceMargins", "SetTextureSliceMode" }) do
        texture[method] = function() paints = paints + 1 end
    end
    function texture:SetVertexColor(_, _, _, alpha)
        paints = paints + 1
        self.vertexAlpha = alpha
    end
    function texture:SetGradient(_, first, last)
        paints = paints + 1
        self.gradientStartAlpha, self.gradientEndAlpha = first.a, last.a
    end
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    function texture:ClearAllPoints() end
    function texture:SetPoint() end
    function texture:SetDrawLayer() end
    return texture
end
local function Target(objectType)
    local target = {}
    function target:IsForbidden() return false end
    function target:IsProtected() return false, false end
    function target:GetObjectType() return objectType or "Frame" end
    function target:GetParent() return nil end
    function target:CreateTexture() return Texture() end
    function target:HookScript() end
    return target
end

local NS = {
    path = "",
    Client = { isForever = arg[2] == "Forever" },
    IsCombatLocked = function() return false end,
    BlizzardYellow = { TrackFrame = Noop },
}
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", NS)
NS.DB = NS.CopyValue(NS.Defaults)
for _, file in ipairs({ "../MSUF_Suite/Appearance/Safety.lua", "Core/Registry.lua", "Core/Theme.lua",
    "Rendering/Geometry.lua", "Rendering/Surface.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
-- A recycled row can reapply its tint and visibility without resetting its
-- owned nine-slice. Native button slots can be rewritten by Blizzard.
local function CheckShapeReuse()
    local texture, another = Texture(), Texture()
    local geometry = { slice = true, margins = { 2, 3, 4, 5 } }
    local configure = NS.Geometry.ConfigureShape
    local before = paints
    configure(texture, "first", geometry)
    Check(paints - before == 4, "first shape did not configure its slice")
    configure(texture, "first", geometry)
    Check(paints - before == 4, "stable owned shape rewrote its slice")
    configure(another, "first", geometry)
    Check(paints - before == 8, "a different texture reused the first texture's shape")
    geometry.margins[4] = 6
    configure(texture, "first", geometry)
    Check(paints - before == 12, "changed slice margin was ignored")
    geometry.slice = false
    configure(texture, "first", geometry)
    Check(paints - before == 14, "disabling the slice did not clear it")
    configure(texture, "second", geometry)
    Check(paints - before == 16, "changed asset was ignored")
    configure(another, "first", geometry, true)
    configure(another, "first", geometry, true)
    Check(paints - before == 20, "native button slot stopped restoring its shape")
end
CheckShapeReuse()

local Surface = NS.Surface

-- New rows in the same menu use the exact same material colors. Count only
-- colors: the per-row paint still writes the gradient on every texture.
do
    local create, created, writes = CreateColor, 0, 0
    CreateColor = function(...)
        created = created + 1
        return create(...)
    end
    local surface = { spec = {} }
    local texture = { SetVertexColor = Noop }
    function texture:SetGradient(direction, first, last)
        writes = writes + 1
        self.direction, self.first, self.last = direction, first, last
    end
    local theme, material = NS.DB.theme, NS.Theme.GetMaterial("panel")
    local oldGradient, oldStrength, oldOpacity = theme.gradient, theme.gradientStrength, theme.panelOpacity
    theme.gradient, theme.gradientStrength, theme.panelOpacity = true, .713, .617
    local rows = {}
    for i = 1, 456 do rows[i] = { spec = {} } end
    for i = 1, #rows do Surface.PaintFill(texture, material, rows[i]) end
    local first, last = texture.first, texture.last
    local firstAlpha, lastAlpha = first.a, last.a
    print(("456 panel paints: %d colors, %d gradients"):format(created, writes))
    Check(created <= 2 and writes == #rows, "cold rows allocated gradient colors per surface")
    theme.panelOpacity = .283
    Surface.PaintFill(texture, material, surface)
    Check(texture.first.a ~= firstAlpha and texture.last.a ~= lastAlpha and first.a == firstAlpha and last.a == lastAlpha,
        "a changed opacity mutated colors still used by other rows")
    local afterChange = created
    for i = 1, #rows do Surface.PaintFill(texture, material, rows[i]) end
    Check(created == afterChange, "an opacity edit allocated identical colors for each updated surface")
    local custom = { spec = { resolveFill = function() return .3, .4, .5, .6, .7, .8, .9, .1, true, "HORIZONTAL" end } }
    Surface.PaintFill(texture, material, custom)
    Check(texture.direction == "HORIZONTAL" and texture.first.a == .6 and texture.last.b == .9,
        "custom surface shading reused a theme color")
    local alternate = { spec = { fillAlphaScale = .4 } }
    Surface.PaintFill(texture, material, alternate)
    local bothVariants = created
    for i = 1, 10 do
        Surface.PaintFill(texture, material, rows[1])
        Surface.PaintFill(texture, material, alternate)
    end
    Check(created == bothVariants, "alternating panel opacities discarded their existing colors")
    local prepared = Surface.PrepareFill(material, rows[1].spec)
    Surface.PaintFill(texture, material, { spec = {} }, nil, prepared)
    Check(texture.first ~= rows[1].gradientFrom and texture.last ~= rows[1].gradientTo,
        "a caller's prepared fill shared mutable state with a material")
    theme.gradient = false
    Surface.PaintFill(texture, material, rows[1])
    Check(texture.first == texture.last and texture.first.a ~= firstAlpha, "unshading left a stale gradient")
    theme.gradient, theme.gradientStrength, theme.panelOpacity = oldGradient, oldStrength, oldOpacity
    CreateColor = create
end
-- Prepare geometry and real materials without exposing any layer, even if the
-- parent changes protection before its deferred first show is allowed to run.
do
    local root, control, spec = Target(), Target(), { role = "shell", inset = 1 }
    local prepared = assert(Surface.Ensure(root, spec, true))
    Check(not Surface.Ensure(root, { role = "panel" }, true) and prepared.spec == spec,
        "a second owner claimed another pending material")
    local normal = assert(Surface.Ensure(control, spec))
    Check(prepared.preparedShell and not prepared.fill.shown and not prepared.edge.shown
        and (not prepared.depth or not prepared.depth.shown), "prepared shell exposed native layers")
    Surface.Refresh(root)
    Check(not prepared.fill.shown and not prepared.edge.shown and (not prepared.depth or not prepared.depth.shown),
        "refresh exposed a deferred native surface")
    function root:IsProtected() return true, true end
    local before = paints
    Check(not Surface.Ensure(root, spec) and paints == before and not prepared.fill.shown,
        "a protected first reveal repainted or exposed the prepared root")
    function root:IsProtected() return false, false end
    Check(Surface.Ensure(root, spec) == prepared and not prepared.preparedShell and paints == before
        and prepared.fill.shown == normal.fill.shown and prepared.edge.shown == normal.edge.shown
        and (not normal.depth or normal.depth.shown == prepared.depth.shown),
        "first allowed reveal repeated painting or discarded prepared layer policy")
    Check(not Surface.Ensure(root, spec, true) and prepared.fill.shown == normal.fill.shown,
        "preparation stole or concealed a previously adopted surface")
end
local spec = { role = "card", radius = 4, inset = 1, listItem = true }

local row = Target()
Check(Surface.Ensure(row, spec) ~= nil and paints > 0, "the first Ensure did not paint the row")
paints = 0
for _ = 1, 100 do Surface.Ensure(row, spec) end
Check(paints == 0, ("a current row surface was painted again %d times by row initialization"):format(paints))
-- A settings change makes the next Ensure paint once.
NS.Registry.NotifyListeners("color", "accent")
Surface.Ensure(row, spec)
Check(paints > 0, "a row kept its old paint after a settings change")
paints = 0
Surface.Ensure(row, spec)
Check(paints == 0, "a repainted row was painted again")
-- A hidden surface is shown and painted again.
Surface.SetVisible(row, false)
paints = 0
Surface.Ensure(row, spec)
Check(paints > 0 and NS.Registry.GetSurface(row).visible == true, "Ensure left a hidden surface hidden")
-- Another spec paints; Attach always paints (callers that rewrite a spec
-- table in place rely on it).
paints = 0
Surface.Ensure(row, { role = "panel", radius = 4, inset = 1, listItem = true })
Check(paints > 0, "a new spec was not painted")
local current = NS.Registry.GetSurface(row).spec
paints = 0
current.inset = 2
Surface.Attach(row, current)
Check(paints > 0, "Attach skipped the repaint of a spec rewritten in place")
-- A tab that mirrors Blizzard's selection is painted every time.
local tab = Target("Button")
Surface.Ensure(tab, spec)
Surface.SetNativeStateSync(tab, true)
paints = 0
Surface.Ensure(tab, spec)
Check(paints > 0, "a surface that mirrors native selection skipped its repaint")

-- Selection hooks call SetActive per row initialization and per native
-- refresh: the same state on a current surface costs no native paint call;
-- a new state, or the first call after a settings change, paints once.
-- Budget: 50 unchanged calls, 0 native paint calls (was one full paint each).
local selectable = Target("Button")
Surface.Attach(selectable, spec)
Surface.SetActive(selectable, true)
paints = 0
for _ = 1, 50 do Surface.SetActive(selectable, true) end
Check(paints == 0, ("an unchanged selection was painted again %d times"):format(paints))
Surface.SetActive(selectable, false)
Check(paints > 0 and NS.Registry.GetSurface(selectable).active == false, "a new selection state was not painted")
NS.Registry.NotifyListeners("color", "accent")
paints = 0
Surface.SetActive(selectable, false)
Check(paints > 0, "SetActive kept a stale paint after a settings change")
paints = 0
Surface.SetActive(selectable, false)
Check(paints == 0, "SetActive painted a current surface twice")
Surface.SetNativeStateSync(selectable, true)
Surface.SetActive(selectable, false)
Check(paints > 0, "SetActive skipped a surface that mirrors native selection")
Surface.SetNativeStateSync(selectable, false)

-- Reading surfaces keep both ends opaque across gradient settings, while
-- an ordinary panel continues to use the configured panel opacity.
local opacity, gradient = NS.DB.theme.panelOpacity, NS.DB.theme.gradient
NS.DB.theme.panelOpacity = 0.3
NS.DB.theme.gradient = false
local readingPanel = Target()
local ordinaryPanel = Target()
Surface.Attach(readingPanel, { role = "panel", opaqueFill = true, keepGlassFill = true })
Surface.Attach(ordinaryPanel, { role = "panel" })
local readingFill = NS.Registry.GetSurface(readingPanel).fill
local ordinaryFill = NS.Registry.GetSurface(ordinaryPanel).fill
Check(readingFill.vertexAlpha == 1, "solid reading surface let the world show through")
Check(ordinaryFill.vertexAlpha < 1, "normal surfaces lost their configured transparency")
NS.DB.theme.gradient = true
Surface.Refresh(readingPanel)
Check(readingFill.gradientStartAlpha == 1 and readingFill.gradientEndAlpha == 1,
    "a reading gradient let the world show through")
NS.DB.theme.panelOpacity, NS.DB.theme.gradient = opacity, gradient

if NS.Client.isForever then
    local rootFrame, child = Target(), Target()
    function child:GetParent() return rootFrame end
    local window = Surface.Attach(rootFrame, { role = "shell", radius = 4 })
    local content = Surface.Attach(child, { role = "panel", radius = 4 })
    local theme = NS.DB.theme
    local shell, background, ink = theme.shellOpacity, theme.colors.background, theme.colors.ink
    theme.colors.background, theme.colors.ink = { .031, .043, .051, .92 }, { .031, .043, .051, .92 }
    NS.Theme.SetAppearance("shellOpacity", .9)
    Check(theme.look == "custom" and Surface.UsesGlassCompositing(), "editing a translucent shell disabled Glass compositing")
    theme.colors.background, theme.colors.ink = { .08, .09, .1, 1 }, { .08, .09, .1, 1 }
    NS.Theme.SetAppearance("shellOpacity", 1)
    Check(not Surface.UsesGlassCompositing(), "the actual opaque shell was classified as Glass")
    theme.shellOpacity, theme.colors.background, theme.colors.ink = shell, background, ink
    NS.Theme.SetAppearance("shellOpacity", 0.5)
    NS.Theme.SetAppearance("gradient", false)
    NS.Theme.SetGeometry("radius", 12)
    Check(window.geometry.radius == 12 and content.geometry.radius == 4, "Forever window ignored global radius")
    NS.Theme.SetAppearance("panelOpacity", 0.85)
    local before = content.fill.vertexAlpha
    NS.Theme.SetAppearance("panelOpacity", 0.4)
    Check(content.fill.shown and content.fill.vertexAlpha < before, "Forever glass masked content opacity")
end

-- An independent window opening cannot change this window's paint. A glass
-- panel, however, follows the public parent chain even when Blizzard reparents
-- an existing container without a Suite attach/visibility or settings event.
do
    local theme = NS.DB.theme
    local opacity = theme.shellOpacity
    NS.Theme.SetAppearance("shellOpacity", .35)
    Check(Surface.UsesGlassCompositing(), "fixture needs a translucent shell")
    local rootA, middle, leaf, row, other = Target(), Target(), Target(), Target(), Target()
    local parent, parentReads = rootA, 0
    function leaf:GetParent() return middle end
    function middle:GetParent() return parent end
    function row:GetParent() parentReads = parentReads + 1; return rootA end
    local childSpec = { role = "panel", keepGlassFill = false }
    local shellSpec = { role = "shell" }
    local child = Surface.Attach(leaf, childSpec)
    local rowSpec = { role = "card", listItem = true }
    local rows = { row }
    for i = 2, 32 do rows[i] = Target() end
    for _, visibleRow in ipairs(rows) do Surface.Attach(visibleRow, rowSpec) end
    Surface.Attach(other, shellSpec)
    local before, instructions = paints, 0
    debug.sethook(function() instructions = instructions + 100 end, "", 100)
    Surface.Ensure(leaf, childSpec)
    for _, visibleRow in ipairs(rows) do Surface.Ensure(visibleRow, rowSpec) end
    debug.sethook()
    print(("After an independent window attach, 32 rows and one panel: %d material writes, %d sampled instructions")
        :format(paints - before, instructions))
    Check(paints == before and parentReads == 0, "an unrelated window rematerialized another window or queried a row's ancestry")
    Check(child.fill.shown, "glass panel without a filled ancestor lost its fill")
    Surface.Attach(rootA, shellSpec)
    Surface.Ensure(leaf, childSpec)
    Check(not child.fill.shown, "a late structural ancestor did not flatten its glass descendant")
    Surface.SetVisible(rootA, false)
    Surface.Ensure(leaf, childSpec)
    Check(child.fill.shown, "hiding the structural ancestor left its glass descendant flattened")
    Surface.SetVisible(rootA, true)
    Surface.Ensure(leaf, childSpec)
    Check(not child.fill.shown, "showing the structural ancestor lost the nested glass correction")
    parent = nil
    Surface.Ensure(leaf, childSpec)
    Check(child.fill.shown, "reparenting an intermediate native container retained a stale base")
    parent = rootA
    shellSpec.fillVisible = false
    Surface.Attach(rootA, shellSpec)
    Surface.Ensure(leaf, childSpec)
    Check(child.fill.shown, "an edge-only ancestor suppressed its child's fill")
    shellSpec.fillVisible = true
    Surface.Attach(rootA, shellSpec)
    Surface.Ensure(leaf, childSpec)
    Check(not child.fill.shown, "a filling ancestor with the same spec identity was missed")
    local switchSpec = { role = "button", activeRole = "panel" }
    Surface.Attach(rootA, switchSpec)
    Surface.Ensure(leaf, childSpec)
    Check(child.fill.shown, "a nonstructural ancestor suppressed its child")
    Surface.SetActive(rootA, true)
    Surface.Ensure(leaf, childSpec)
    Check(not child.fill.shown, "the active structural role did not flatten its child")
    local chain = {}
    for i = 1, 13 do
        local nextParent = chain[i - 1] or rootA
        chain[i] = Target()
        chain[i].GetParent = function() return nextParent end
    end
    parent = chain[9] -- leaf -> middle -> nine plain containers -> root
    Surface.Ensure(leaf, childSpec)
    Check(not child.fill.shown, "a structural ancestor inside the supported depth was ignored")
    parent = chain[12]
    Surface.Ensure(leaf, childSpec)
    Check(child.fill.shown, "a structural ancestor past the supported depth changed the glass")
    local current = paints
    NS.Registry.NotifyListeners("profile", "changed")
    Surface.Ensure(row, rowSpec)
    Check(paints > current, "real profile change reused an obsolete row")
    NS.Theme.SetAppearance("shellOpacity", opacity)
end

------------------------------------------------------------------ hot callers
-- Each hot path attaches through Ensure.
local ensures, attaches = 0, 0
NS.Surface = {
    Ensure = function() ensures = ensures + 1; return {} end,
    Attach = function() attaches = attaches + 1; return {} end,
    SetVisible = Noop,
}
NS.Cosmetics = { Fade = function() return true end, SuppressVertexAlpha = function() return true end }
NS.ControlSkin = { DisableOwner = Noop }
NS.IconSkin = { Apply = function() return {} end }
NS.GenericWindows = { IsCategoryEnabled = function() return true end }
NS.DB.skinCategories = { economy = true, social = false }
NS.DB.hud = { damageMeterRows = true }
ScrollBoxListMixin = { Event = { OnInitializedFrame = "OnInitializedFrame" } }
for _, file in ipairs({ "Adapters/AdapterKit.lua", "Adapters/Commerce.lua", "Adapters/DamageMeter.lua",
    "Adapters/PaperDollChrome.lua" }) do
    local override = file == "Adapters/PaperDollChrome.lua" and os.getenv("SUITE_ENSURE_CHROME_OVERRIDE")
    assert(loadfile(override or root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
-- Auction House rows Blizzard initializes while scrolling.
local callbacks = {}
local scrollBox = Target()
function scrollBox:RegisterCallback(_, callback, owner) callbacks[#callbacks + 1] = { callback, owner } end
function scrollBox:ForEachFrame() end
AuctionHouseFrame = Target()
AuctionHouseFrame.BrowseResultsFrame = { ItemList = { ScrollBox = scrollBox } }
EventUtil = { ContinueOnAddOnLoaded = Noop }
NS.Commerce.Apply("hot")
local auctionRow = Target()
ensures, attaches = 0, 0
for _ = 1, 3 do
    for _, registration in ipairs(callbacks) do registration[1](registration[2], auctionRow) end
end
Check(#callbacks == 1 and ensures == 3 and attaches == 0,
    "Auction House row initialization did not attach through Ensure")
local rowEnsures = ensures
-- Damage meter rows.
local meterRow = Target()
meterRow.StatusBar = Target()
local meterCallbacks = {}
local meterBox = Target()
function meterBox:RegisterCallback(_, callback, owner) meterCallbacks[#meterCallbacks + 1] = { callback, owner } end
function meterBox:ForEachFrame() end
local window = Target()
window.MinimizeContainer = { ScrollBox = meterBox }
function window:SetMinimized() end
local meter = Target()
function meter:ForEachSessionWindow(callback) callback(window) end
NS.WindowActionSkin = { SyncNativeVisual = function() return {} end }
NS.Checkmarks = { TrackButton = Noop }
hooksecurefunc = Noop
NS.DamageMeterSkin.Apply(meter, "meter")
rowEnsures, attaches = ensures, 0
for _ = 1, 3 do meterCallbacks[1][1](meterCallbacks[1][2], meterRow) end
Check(ensures == rowEnsures + 3 and attaches == 0, "damage meter row initialization did not attach through Ensure")
-- Paper doll slot updates.
HotPaperDoll = Target()
function HotPaperDoll:IsVisible() return self.shown ~= false end
local chrome = NS.PaperDollChrome.New({ prefix = "hot", rootName = "HotPaperDoll", slotNames = { "HotSlot" } })
local state = chrome:OwnerState("hot")
state.active = true
local slot = Target()
chrome.exactSlots[slot] = true
local slotEnsures = ensures
for _ = 1, 3 do chrome:SkinSlot(state, slot) end
Check(ensures == slotEnsures + 3, "a paper doll slot update did not attach through Ensure")
HotSlot = slot
HotPaperDoll.shown = false
slotEnsures = ensures
for _ = 1, 64 do
    chrome:SkinSlot(state, slot)
    chrome:RefreshSlot(slot)
    chrome:SkinAllSlots(state)
end
Check(ensures == slotEnsures and attaches == 0, "hidden PaperDoll updates traversed slot paint paths")
HotPaperDoll.shown = true
chrome:RefreshSlot(slot)
Check(ensures == slotEnsures + 1, "visible PaperDoll slot failed to resume Ensure")

print("Suite skin surface ensure: " .. checks .. " checks passed")
