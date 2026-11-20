-- Real optional runtime and Ace widget adapters. Foreign widget constructors
-- model the target APIs, including private/lazy roots and detached pullouts.
local root = assert(arg[1])
local checks, combat, sourceReads, childReads = 0, false, 0, 0
local function Check(value, why) checks = checks + 1 assert(value, why) end
local function Noop() end
local frames, queue, listeners, surfaces, paints, labels = {}, {}, {}, {}, {}, {}
local paintCounts = {}
local paintModes = {}
local releasedOwners = {}
C_Timer = { After = function(_, job) queue[job] = true end }
local function Frame(kind, parent, source)
    local frame = { kind = kind or "Frame", parent = parent, source = source, children = {}, regions = {},
        scripts = {}, events = {}, shown = true, width = 400, height = 250, alpha = 1, vertex = { 1, 1, 1, 1 } }
    frames[#frames + 1] = frame
    if parent then parent.children[#parent.children + 1] = frame end
    function frame:GetObjectType() return self.kind end
    function frame:GetName() return self.name end
    function frame:IsForbidden() return self.forbidden == true end
    function frame:IsProtected() return self.protected == true, self.protected == true and not self.implicit end
    function frame:GetParent() return self.parent end
    function frame:GetSourceLocation() sourceReads = sourceReads + 1 return self.source end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:IsMouseEnabled() return self.mouse ~= false end
    function frame:IsVisible() return self.shown end
    function frame:IsShown() return self.shown end
    function frame:GetBackdrop() return self.backdrop end
    function frame:GetChildren() childReads = childReads + 1 return unpack(self.children) end
    function frame:GetRegions() return unpack(self.regions) end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:GetFont()
        if self.font then return self.font, 14, "" end
        if self.fontObject then return self.fontObject:GetFont() end
    end
    function frame:SetFont(font) self.font = font return true end
    function frame:GetFontObject() return self.fontObject end
    function frame:SetFontObject(font) self.fontObject, self.font = font, nil end
    function frame:GetText() return self.text end
    function frame:GetTextColor() return unpack(self.textColor or { 1, 1, 1, 1 }) end
    function frame:SetTextColor(...) self.textColor = { ... } end
    function frame:GetVertexColor() return unpack(self.vertex) end
    function frame:SetVertexColor(...) self.vertex = { ... } end
    function frame:GetTexture() return self.texture end
    function frame:CreateTexture() return Frame("Texture", nil) end
    function frame:SetHighlightTexture() end
    function frame:SetPushedTexture() end
    function frame:SetScript(key, callback) self.scripts[key] = callback end
    function frame:HookScript(key, callback)
        local previous = self.scripts[key]
        self.scripts[key] = function(...) if previous then previous(...) end callback(...) end
    end
    function frame:RegisterEvent(key) self.events[key] = true end
    function frame:UnregisterEvent(key) self.events[key] = nil end
    function frame:Show() self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end
    function frame:Hide() self.shown = false end
    return frame
end
CreateFrame = function(kind, _, parent) return Frame(kind, parent) end
UIParent = Frame()
UIParent.width, UIParent.height = 1920, 1080
issecretvalue = function(value) return type(value) == "table" and rawget(value, "secret") == true end
securecallfunction = function(callback, ...) return callback(...) end
hooksecurefunc = function(target, key, callback)
    local original = assert(target[key])
    target[key] = function(...)
        local values = { original(...) }
        callback(...)
        return unpack(values)
    end
end
local foci = {}
GetMouseFoci = function() return foci end
InCombatLockdown = function() return combat end
SlashCmdList, C_AddOns = {}, { GetAddOnMetadata = Noop }
local NS = {
    addonName = "MSUF_Suite_Skin", IsCombatLocked = function() return combat end,
    Client = { isForever = arg[2] == "Forever", HasAddOn = function() return true end, IsAddOnLoaded = function() return true end },
    Registry = { QueueJob = function(job) queue[job] = true end,
        AddListener = function(owner, callback) listeners[owner] = callback end },
    Theme = { GetColor = function() return 0.2, 0.3, 0.4, 1 end },
    LabelStyle = { CanStyle = function(label) return type(label) == "table" and label.kind == "FontString" end,
        Apply = function(label, owner) labels[label] = owner end,
        Release = function(label, owner) if labels[label] == owner then labels[label] = nil end end },
    Surface = { Attach = function(frame, spec) surfaces[frame] = { role = spec.role, visible = true } return frame end,
        SetVisible = function(frame, value) if surfaces[frame] then surfaces[frame].visible = value end end },
    ControlSkin = { ApplyButton = function(frame) paints[frame] = "button" end,
        ApplySearchBox = function(frame) paints[frame] = "input" end,
        DisableOwner = function(owner) releasedOwners[owner] = true end },
    ScrollBarSkin = { Apply = function(frame) paints[frame] = "scrollbar" end, DisableOwner = Noop },
    MenuMotion = { Release = Noop, OwnerFor = Noop },
    WindowActionSkin = { ApplyExplicit = function(button) paints[button] = "close" return {} end,
        IsApplied = function() return false end, DisableOwner = Noop },
    Checkmarks = { GetWindowAction = function(frame) return frame.action end },
    ContentMotion = { Watch = Noop, Unwatch = Noop, Play = Noop }, Motion = {},
    PublicAPI = {}, AddonSettings = { IsApplied = function() return false end, ReleaseAddon = Noop },
}
NS.Registry.NotifyListeners = function(domain, key)
    for owner, callback in pairs(listeners) do callback(owner, domain, key) end
end
local function Load(path)
    local file = root .. "/MSUF_Suite_Skin/" .. path
    local override = os.getenv("SUITE_ADDON_OVERRIDE_ROOT")
    if override then
        local candidate = override .. "/" .. path
        local handle = io.open(candidate, "rb")
        if handle then handle:close() file = candidate end
    end
    assert(loadfile(file))(NS.addonName, NS)
end
Load("Core/Safety.lua")
Load("Core/Cosmetics.lua")
Load("Core/Defaults.lua")
NS.DB = { enabled = true, skins = { blizzardWindows = false }, addonSkins = NS.CopyValue(NS.Defaults.addonSkins) }
NS.GenericWindows = {
    ApplyFrame = function(frame, _, mode)
        paints[frame] = "shell"
        paintModes[frame] = mode
        paintCounts[frame] = (paintCounts[frame] or 0) + 1
        return true
    end,
    Disable = Noop,
}
local gui = { RegisterAsWidget = Noop, RegisterAsContainer = Noop, Release = Noop }
local dialog = { OpenFrames = {}, Open = function(self, name, widget) self.OpenFrames[name] = widget end }
local brokerObjects = {}
local broker = { GetDataObjectByName = function(_, name) return brokerObjects[name] end,
    DataObjectIterator = function() return pairs(brokerObjects) end,
    NewDataObject = function(_, name, object) brokerObjects[name] = object return object end }
LibStub = { GetLibrary = function(_, name)
    if name == "AceGUI-3.0" then return gui end
    if name == "AceConfigDialog-3.0" then return dialog end
    if name == "LibDataBroker-1.1" then return broker end
end }
Load("Adapters/AddonSkinVisuals.lua")
Load("Adapters/AddonSkinCompendium.lua")
Load("Adapters/AddonSkinRestedXP.lua")
Load("Adapters/AddonSkinProfiler.lua")
Load("Adapters/AddonSkinEnhanceQoL.lua")
Load("Adapters/AceWidgets.lua")
local preopened = { type = "Frame", frame = Frame(), children = {} }
dialog.OpenFrames.BugSack = preopened
Load("Adapters/AddonMenus.lua")
local addonCatalog = {}
assert(loadfile(root .. "/MSUF_Suite/Core/AddonSkinCatalog.lua"))("MSUF_Suite", addonCatalog)
NS.SuiteCore = function() return addonCatalog end
Load("Adapters/AddonSkinsCatalog.lua")
Load("Adapters/AddonSkins.lua")
Load("Adapters/AddonSkinTriggers.lua")
Load("Adapters/AddonSkinDiscovery.lua")
Load("Adapters/AddonSkinSpoken.lua")
local function Flush()
    if combat then return end
    for _ = 1, 20 do
        if not next(queue) then return end
        local pending = queue
        queue = {}
        for job in pairs(pending) do job() end
    end
    error("unbounded addon skin queue")
end
local function Event(name, ...)
    for _, frame in ipairs(frames) do
        if frame.events[name] then frame.scripts.OnEvent(frame, name, ...) end
    end
end
Check(NS.DB.addonSkins.enabled == false, "addon skins must start opt-in")
Check(#NS.AddonSkinDefinitions == 23, "the requested addon catalog is incomplete")
local windows = {}
for _, entry in ipairs(NS.AddonSkinDefinitions) do
    local window = Frame("Frame", UIParent, "@Interface/AddOns/" .. entry.addons[1] .. "/Settings.lua:10")
    window.backdrop, window.Center = {}, Frame("Texture")
    windows[entry.id] = window
end
Event("PLAYER_LOGIN") Flush()
Check(not next(paints), "disabled addon skins painted a foreign window")
assert(NS.AddonSkins.SetOption("enabled", true)) Flush()
Check(NS.AddonMenus.widgets[preopened].addonID == "bugSack" and paints[preopened.frame] == "shell",
    "AceConfig window already open during engine loading lost its addon identity or skin")
gui:Release(preopened)
dialog.OpenFrames.BugSack = nil
for id, frame in pairs(windows) do
    Check(paints[frame] == "shell" and frame.Center.alpha == 0, id .. " window/chrome was not skinned")
end
local before = sourceReads
for _ = 1, 30 do NS.Registry.NotifyListeners("theme", "color") end
Flush()
Check(sourceReads == before, "palette changes rediscovered foreign windows")
local warmPaints, warmChildren = 0, childReads
for _, count in pairs(paintCounts) do warmPaints = warmPaints + count end
for _ = 1, 100 do
    for _, window in pairs(windows) do window:Show() end
end
Flush()
local afterPaints = 0
for _, count in pairs(paintCounts) do afterPaints = afterPaints + count end
Check(afterPaints == warmPaints and childReads == warmChildren, "unchanged addon shows repeated the skin tree")
foci, before = { windows.bugSack }, sourceReads
for _ = 1, 100 do Event("GLOBAL_MOUSE_UP") Flush() end
Check(sourceReads == before, "ordinary addon clicks rediscovered the entire UI")
local ordinary = Frame("Frame", UIParent, "@Interface/AddOns/Unrelated/Settings.lua:1")
local fullscreen = Frame("Frame", UIParent, "@Interface/AddOns/LootTriage/SettingsWindow.lua:27")
fullscreen.width, fullscreen.height = 1920, 1080
NS.AddonSkins.Discover() Flush()
Check(not paints[ordinary] and not paints[fullscreen], "discovery skinned unrelated/fullscreen frames")
local late
SlashCmdList.LOOTTRIAGE = function()
    late = Frame("Frame", UIParent, "@Interface/AddOns/LootTriage/SettingsWindow.lua:27")
end
NS.AddonSkins.InstallTriggers()
SlashCmdList.LOOTTRIAGE() Flush()
Check(paints[late] == "shell", "lazy anonymous slash window was missed")
local launched
local object = broker:NewDataObject("TrueshotLodge", { OnClick = function()
    launched = Frame("Frame", UIParent, "@Interface/AddOns/TrueshotLodge/src/ui/window.lua:212")
end })
object.OnClick() Flush()
Check(paints[launched] == "shell", "late LibDataBroker launcher missed its window")
-- DoesItDie builds its Advanced action rows once and lazily constructs the
-- named tick viewer from a private View callback, outside all addon launchers.
local viewButton
SlashCmdList.DOESITDIE = function()
    DoesItDieOptions = Frame("Frame", UIParent)
    DoesItDieOptions.settingsArea = Frame("Frame", DoesItDieOptions)
    local row = Frame("Frame", DoesItDieOptions.settingsArea)
    viewButton = Frame("Button", row)
    row.button = viewButton
    viewButton:SetScript("OnClick", function()
        if not DoesItDieLearnedTicks then DoesItDieLearnedTicks = Frame("Frame", UIParent) end
        DoesItDieLearnedTicks:Show()
    end)
end
NS.AddonSkins.InstallTriggers()
SlashCmdList.DOESITDIE() Flush()
viewButton.scripts.OnClick(viewButton) Flush()
Check(paints[DoesItDieLearnedTicks] == "shell", "DoesItDie secondary View window missed its construction skin")
local viewerPaints, secondaryReads, secondaryChildren = paintCounts[DoesItDieLearnedTicks], sourceReads, childReads
for _ = 1, 100 do viewButton.scripts.OnClick(viewButton) Flush() end
Check(paintCounts[DoesItDieLearnedTicks] == viewerPaints and sourceReads == secondaryReads and childReads == secondaryChildren,
    "DoesItDie's known secondary window triggered discovery or repeated painting")
local function Widget(kind, selectTab)
    local widget = { type = kind, frame = Frame(), children = {}, content = Frame(), OnAcquire = Noop, SelectTab = selectTab }
    widget.frame.obj = widget
    function widget:AddChild(child) self.children[#self.children + 1] = child child.parent = self end
    gui:RegisterAsContainer(widget)
    widget:OnAcquire()
    return widget
end
do
    NS.AddonSkins.SetOption("enabled", false) Flush()
    local releaseWidget, releases = NS.AceWidgets.Release, {}
    NS.AceWidgets.Release = function(widget, owner)
        releases[widget] = (releases[widget] or 0) + 1
        releaseWidget(widget, owner)
    end
    local enqueue, requests = NS.Registry.QueueJob, 0
    NS.Registry.QueueJob = function(job) requests = requests + 1 enqueue(job) end
    local live, hidden, unused = Widget("Frame"), Widget("Window"), Widget("Frame")
    local child, nested = Widget("SimpleGroup"), Widget("Button")
    child.label = Frame("FontString")
    live:AddChild(child)
    hidden.frame:Hide()
    gui:Release(live)
    live:OnAcquire()
    gui:Release(unused)
    local tab, selected, unwatched = Widget("TabGroup", Noop), false, false
    local motionOwner = {}
    NS.MenuMotion.OwnerFor = function(content) if content == tab.content then return motionOwner end end
    NS.ContentMotion.Play = function(content, owner, token)
        selected = content == tab.content and owner == motionOwner and token == "example"
        return selected
    end
    NS.ContentMotion.Unwatch = function(owner, content) unwatched = owner == motionOwner and content == tab.content end
    tab:SelectTab("example")
    gui:Release(tab)
    NS.MenuMotion.OwnerFor, NS.ContentMotion.Play, NS.ContentMotion.Unwatch = Noop, Noop, Noop
    Check(selected and unwatched, "disabled widget art interrupted independent content motion ownership")
    Check(not next(releases), "pool released visual owners for unpainted widgets while disabled")
    local reads, children = sourceReads, childReads
    local field, parentReads = NS.Safety.Field, 0
    NS.Safety.Field = function(target, key)
        if key == "parent" then parentReads = parentReads + 1 end
        return field(target, key)
    end
    for _ = 1, 100 do
        live.frame:Show()
        live:OnAcquire()
        child:AddChild(nested)
        child.children[1] = nil
        Flush()
    end
    NS.Safety.Field = field
    NS.Registry.QueueJob = enqueue
    Check(sourceReads == reads and childReads == children and parentReads == 0 and requests == 0,
        "disabled Ace root lifecycle queued discovery or walked a child parent chain")
    child:AddChild(nested)
    NS.AddonSkins.SetOption("enabled", true) Flush()
    Check(paints[live.frame] == "shell" and labels[child.label] and not paints[hidden.frame] and not paints[unused.frame],
        "re-enable missed a standalone pooled Ace window or painted a hidden/released one")
    hidden.frame:Show() Flush()
    Check(paints[hidden.frame] == "shell", "hidden Ace window failed first visible paint after enable")
    -- Native ownership moves the same live child to the second root.
    live.children = {}
    hidden:AddChild(child) Flush()
    gui:Release(live)
    Check(not releases[child] and labels[child.label], "old root released a widget adopted by another window")
    child:OnAcquire()
    gui:Release(hidden)
    gui:Release(child)
    gui:Release(nested)
    gui:Release(hidden)
    Check(releases[live] == 1 and releases[hidden] == 1 and releases[child] == 1 and releases[nested] == 1
        and not labels[child.label], "applied Ace art did not release exactly once across root and individual teardown")

    local partial = Widget("Window")
    local owner = NS.AddonMenus.widgets[partial].owner
    local apply, disable = NS.GenericWindows.ApplyFrame, NS.GenericWindows.Disable
    local released = false
    NS.GenericWindows.ApplyFrame = function(frame, ...)
        apply(frame, ...)
        if frame == partial.frame then error("partial Ace paint") end
    end
    NS.GenericWindows.Disable = function(lease)
        if lease == owner then released = true end
        disable(lease)
    end
    local ok, err = pcall(Flush)
    NS.GenericWindows.ApplyFrame = apply
    Check(not ok and tostring(err):find("partial Ace paint", 1, true), "partial paint fixture did not acquire its lease")
    NS.AddonSkins.SetOption("enabled", false) Flush()
    Check(released, "disabling Ace lost the lease left by an interrupted first paint")
    gui:Release(partial)
    NS.GenericWindows.Disable = disable
    NS.AddonSkins.SetOption("enabled", true) Flush()

    local interrupted, interruptedChild = Widget("Frame"), Widget("Button")
    interrupted:AddChild(interruptedChild)
    local applyWidget = NS.AceWidgets.Apply
    NS.AceWidgets.Apply = function(widget, ...)
        applyWidget(widget, ...)
        if widget == interruptedChild then error("partial Ace widget art") end
    end
    ok, err = pcall(Flush)
    NS.AceWidgets.Apply = applyWidget
    Check(not ok and tostring(err):find("partial Ace widget art", 1, true), "widget art interruption was not reached")
    gui:Release(interrupted)
    gui:Release(interruptedChild)
    Check(releases[interrupted] == 1 and releases[interruptedChild] == 1, "partial Ace widget art lost its single release")
    NS.AceWidgets.Release = releaseWidget
end
local config = Widget("Frame")
config.frame.backdrop, config.frame.Center = {}, Frame("Texture")
local title = Frame("FontString")
config.titletext = title
local check = Widget("CheckBox")
check.checkbg, check.check, check.highlight, check.value = Frame("Texture"), Frame("Texture"), Frame("Texture"), true
local slider = Widget("Slider")
slider.slider, slider.editbox = Frame("Slider"), Frame("EditBox")
local tree = Widget("TreeGroup")
tree.scrollbar = Frame("Slider")
local thumb = Frame("Texture")
tree.scrollbar.GetThumbTexture = function() return thumb end
local dropdown, pullout = Widget("Dropdown"), Widget("Dropdown-Pullout")
dropdown.dropdown, dropdown.pullout = Frame(), pullout
pullout.frame.backdrop, pullout.frame.Center = {}, Frame("Texture")
config:AddChild(check) config:AddChild(slider) config:AddChild(tree) config:AddChild(dropdown)
dialog:Open("BugSack", config) Flush()
Check(config.frame.Center.alpha == 0 and labels[title], "Ace native backdrop/font were missed")
Check(check.checkbg.vertex[1] == 0.2 and check.check.alpha == 1 and check.value,
    "Ace checkbox decoration changed native checked state/visibility")
Check(paints[slider.editbox] == "input" and thumb.vertex[1] == 0.2, "Ace inputs/legacy scrollbar were missed")
Check(pullout.frame.Center.alpha == 0, "detached Ace dropdown retained its native backdrop")
local menuPaints, menuChildren = paintCounts[config.frame], childReads
for _ = 1, 100 do config.frame:Show() end
NS.Registry.NotifyListeners("quests", "layout") Flush()
Check(paintCounts[config.frame] == menuPaints and childReads == menuChildren,
    "unchanged Ace window or unrelated setting repeated its widget tree")
NS.AddonSkins.SetOption("bugSack", false) Flush()
Check(config.frame.Center.alpha == 1 and not labels[title], "per-addon disable retained Ace decoration")
NS.AddonSkins.SetOption("bugSack", true) Flush()
gui:Release(check)
Check(check.checkbg.vertex[1] == 1, "pooled Ace checkbox retained old colors")
gui:Release(config)
Check(config.frame.Center.alpha == 1 and pullout.frame.Center.alpha == 1, "Ace root release retained child/popup chrome")
local fontless, fontlessOwner = Widget("CustomElement"), {}
fontless.button = Frame("Button")
NS.AceWidgets.Apply(fontless, fontlessOwner)
NS.AceWidgets.Release(fontless, fontlessOwner)
Check(releasedOwners[fontlessOwner], "fontless custom Ace widget retained its control lease")
NS.AddonSkins.SetOption("oneForAll", true)
local nativeRow = Frame()
local nativeBox = Frame()
function nativeBox:ForEachFrame(callback) callback(nativeRow) end
local category = { GetName = function() return "One For All" end }
SettingsPanel = { GetCurrentCategory = function() return category end,
    GetSettingsList = function() return { ScrollBox = nativeBox } end }
EventRegistry = { RegisterCallback = Noop, UnregisterCallback = Noop }
NS.AdapterKit = { RegisterRowCallback = function() return "initialized" end, UnregisterRowCallback = Noop }
NS.GenericWindows.ApplyDescendant = function(row) paints[row] = "native-addon-row" return true end
NS.DB.skins.settings = false
Load("Adapters/AddonSkinSettings.lua") Flush()
Check(paints[nativeRow] == "native-addon-row" and NS.AddonSettings.IsApplied("oneForAll"),
    "native generated addon options did not follow their category")
NS.AddonSkins.SetOption("oneForAll", false) Flush()
Check(not NS.AddonSettings.IsApplied("oneForAll"), "native addon settings ignored their per-addon switch")
-- Automatic narration constructs Spoken's player without a click or slash.
local spokenPlayer, spokenPortrait
local nativeTick = function() end
SpokenEnv = { PlayerFrame = {} }
function SpokenEnv.PlayerFrame:InitDisplay()
    spokenPlayer = Frame("Frame", UIParent, "@Interface/AddOns/Spoken/UI/PlayerFrame.lua:104")
    spokenPlayer.name, spokenPlayer.background = "SpokenPlayerFrame", Frame("Texture")
    spokenPlayer.scripts.OnUpdate = nativeTick
    spokenPortrait = Frame("Frame", spokenPlayer)
    spokenPortrait.background = Frame("Texture")
    spokenPlayer.portrait = spokenPortrait
    self.frame, SpokenPlayerFrame = spokenPlayer, spokenPlayer
end
NS.AddonSkins.SetOption("spoken", true) Flush()
SpokenEnv.PlayerFrame:InitDisplay() Flush()
Check(paints[spokenPlayer] == "shell" and spokenPlayer.background.alpha == 0,
    "automatic Spoken player creation missed the skin")
Check(spokenPortrait.background.alpha == 1 and not paints[spokenPortrait]
    and spokenPlayer.scripts.OnUpdate == nativeTick, "Spoken skin changed its portrait or narration tick")
NS.AddonSkins.SetOption("spoken", false) Flush()
Check(spokenPlayer.background.alpha == 1, "Spoken disable did not restore its original player artwork")
local dialogue = Frame("Frame", UIParent, "@Interface/AddOns/Spoken/UI/DialogueUIPlayer.lua:298")
dialogue.name, SpokenDialogueUIPlayerFrame = "SpokenDialogueUIPlayerFrame", dialogue
local parchment, tintWrites = Frame("Texture"), 0
local tint = parchment.SetVertexColor
function parchment:SetVertexColor(...)
    Check(not dialogue.spokenFrozen, "Spoken framebuffer received a renderer write")
    tintWrites = tintWrites + 1
    tint(self, ...)
end
SpokenEnv.DialogueUIPlayer = { frame = dialogue, parchments = { parchment } }
function SpokenEnv.DialogueUIPlayer:Unbuffer() self.buffered, self.frame.spokenFrozen = nil, nil end
NS.AddonSkins.SetOption("spoken", true) Flush()
Check(tintWrites > 0 and not surfaces[dialogue] and not paints[dialogue],
    "Spoken framebuffer variant registered a shared surface/control")
SpokenEnv.DialogueUIPlayer.buffered, dialogue.spokenFrozen = true, true
local written = tintWrites
NS.Registry.NotifyListeners("theme", "colors") Flush()
NS.AddonSkins.SetOption("spoken", false) Flush()
Check(tintWrites == written, "Spoken frozen theme/disable mutated its regions")
SpokenEnv.DialogueUIPlayer:Unbuffer() Flush()
Check(parchment.vertex[1] == 1, "Spoken framebuffer disable did not resume after native Unbuffer")
NS.AddonSkins.SetOption("spoken", true) Flush()
SpokenEnv.DialogueUIPlayer.buffered, dialogue.spokenFrozen = true, true
NS.PublicAPI.OnRegistrationChanged("Spoken", true) Flush()
SpokenEnv.DialogueUIPlayer:Unbuffer() Flush()
Check(parchment.vertex[1] == 1, "Spoken cooperative transfer retained a deferred skin")
NS.PublicAPI.OnRegistrationChanged("Spoken", false) Flush()
Check(parchment.vertex[1] == 0.2, "Spoken cooperative unregister did not restore the automatic skin")

do
    NS.AddonSkins.SetOption("enabled", false) Flush()
    local oldStyle = NS.LabelStyle
    Load("Core/LabelStyle.lua")
    NS.DB.typography = { enabled = true }
    NS.Typography = { GetSelection = Noop, GetSelectionPath = function() return "Suite.ttf" end }
    STANDARD_TEXT_FONT = "NativeText.ttf"
    local template = Frame("Font")
    template.font = "Suite.ttf"
    local function Label(parent, text)
        local label = Frame("FontString", parent)
        label:SetFontObject(template)
        label.text = text
        return label
    end
    SpokenEnv.Subtitle = {}
    function SpokenEnv.Subtitle:Build()
        local frame = Frame("Frame", UIParent)
        frame.name, frame.scripts.OnUpdate = "SpokenSubtitleFrame", nativeTick
        self.frame, SpokenSubtitleFrame = frame, frame
        self.title, self.dot = Label(frame, "Bibbly"), Label(frame, "·")
        self.heldDot, self.moreDot = Label(frame, "·"), Label(frame, "·")
        self.shadow, self.fill = Frame("Texture"), Frame("Texture")
        self.portrait = Frame("Texture")
    end
    NS.Registry.NotifyListeners("typography", "enabled") Flush()
    SpokenEnv.Subtitle:Build() Flush()
    local subtitle = SpokenEnv.Subtitle
    Check(subtitle.dot.font == STANDARD_TEXT_FONT and subtitle.shadow.vertex[1] == 1,
        "global typography lost the separator when addon skins were off")
    NS.AddonSkins.SetOption("enabled", true) Flush()
    Check(not paintModes[subtitle.frame] and not surfaces[subtitle.frame]
        and subtitle.shadow.vertex[1] == .2 and subtitle.fill.vertex[1] == .2
        and subtitle.title.textColor[1] == .2, "lazy subtitle did not receive the transparent themed skin")
    for _, label in ipairs({ subtitle.dot, subtitle.heldDot, subtitle.moreDot }) do
        Check(label.font == STANDARD_TEXT_FONT and label.text == "·", "subtitle separator lost its native glyph")
    end
    Check(subtitle.frame.scripts.OnUpdate == nativeTick and subtitle.portrait.vertex[1] == 1,
        "subtitle skin changed the playback update or portrait")

    local map = Frame("Frame", UIParent)
    SpokenPlaces = {}
    function SpokenPlaces:SetupMapPanel()
        local panel = Frame("Frame", map, "@Interface/AddOns/Spoken_Places/UI/MapPanel.lua:142")
        panel.name = "SpokenPlacesPanel"
        panel.backdrop, panel.Center = {}, Frame("Texture")
        panel.TitleContainer = { TitleText = Label(panel, "Place Story") }
        panel.rim, panel.close = Frame("Frame", panel), Frame("Button", panel)
        panel.close.scripts.OnClick = nativeTick
        local page = { sub = { text = Label(panel, "In Kalimdor · 15 of 19 discovered") },
            bg = Frame("Texture"), picture = Frame("Texture") }
        panel.page = setmetatable({ page = page }, { __index = function(self, key) return self.page[key] end })
        SpokenPlacesPanel = panel
    end
    function SpokenPlaces:ApplyPanelOptions()
        SpokenPlacesPanel.page.sub.text:SetFontObject(template)
    end
    Check(NS.AddonSkins.ResolveApp("Spoken_Places") == "spoken", "Spoken Places load event has no adapter")
    NS.AddonSkins.SetOption("enabled", false) Flush()
    Event("ADDON_LOADED", "Spoken_Places") Flush()
    combat = true
    SpokenPlaces:SetupMapPanel() Flush()
    local panel = SpokenPlacesPanel
    local line = panel.page.sub.text
    Check(not paints[panel] and panel.rim.alpha == 1 and line:GetFont() == "Suite.ttf", "Place Story was changed in combat")
    combat = false Flush()
    Check(not paints[panel] and line.font == STANDARD_TEXT_FONT, "late Places load missed glyph repair with addon skins off")
    NS.AddonSkins.SetOption("enabled", true) Flush()
    Check(paintModes[panel] and paintModes[panel].role == "shell" and paints[panel.close] == "close",
        "Place Story created beside the map missed the Suite shell or close glyph")
    Check(panel.rim.alpha == 0 and panel.Center.alpha == 0 and panel.page.bg.alpha == 1 and panel.page.picture.alpha == 1
        and panel.close.scripts.OnClick == nativeTick, "Place Story skin changed its content or close action")
    Check(line.font == STANDARD_TEXT_FONT and line.text == "In Kalimdor · 15 of 19 discovered",
        "Place Story discovery text lost its separator or content")
    SpokenPlaces:ApplyPanelOptions() Flush()
    Check(line.font == STANDARD_TEXT_FONT, "Spoken options reapplied the broken separator font")
    template.font = "RestoredGameFont.ttf"
    NS.DB.typography.enabled = false
    NS.Registry.NotifyListeners("typography", "enabled") Flush()
    Check(line:GetFont() == template.font and subtitle.dot:GetFont() == template.font,
        "disabled typography retained a stale font instead of restoring the template")
    template.font = "Suite.ttf"
    NS.DB.typography.enabled = true
    NS.Registry.NotifyListeners("typography", "enabled") Flush()
    Check(line.font == STANDARD_TEXT_FONT and subtitle.dot.font == STANDARD_TEXT_FONT,
        "re-enabled typography missed the separator font")
    NS.AddonSkins.SetOption("spoken", false) Flush()
    Check(panel.rim.alpha == 1 and panel.Center.alpha == 1 and subtitle.shadow.vertex[1] == 1 and subtitle.fill.vertex[1] == 1
        and line:GetFont() == STANDARD_TEXT_FONT and subtitle.dot:GetFont() == STANDARD_TEXT_FONT,
        "disabling Spoken skin did not restore native chrome independently of typography")
    NS.DB.blizzardWindowsEnabled = false
    NS.Registry.NotifyListeners("adapter", "blizzardWindowsEnabled") Flush()
    Check(line:GetFont() == "Suite.ttf" and subtitle.dot:GetFont() == "Suite.ttf",
        "disabling Blizzard typography did not release Spoken's inherited fonts")
    NS.DB.blizzardWindowsEnabled = nil
    NS.DB.typography, NS.LabelStyle = nil, oldStyle
    SpokenEnv.Subtitle, SpokenSubtitleFrame, SpokenPlaces, SpokenPlacesPanel = nil, nil, nil, nil
end

-- RestedXP's legacy shell can be implicitly protected by its secure item
-- buttons; the reviewed builtin exception remains strictly out of combat.
RXPFrame = Frame("Frame", UIParent, "@Interface/AddOns/RXPGuides/GuideWindow.lua:24")
RXPFrame.protected, RXPFrame.implicit, RXPFrame.name = true, true, "RXPFrame"
RXPFrame.backdrop, RXPFrame.Center = {}, Frame("Texture")
function RXPFrame:UpdateVisuals() self.Center.alpha = 1 end
local scrollChild = Frame("Frame", RXPFrame)
RXPFrame.ScrollChild, scrollChild.framePool = scrollChild, {}
RXP = {}
function RXP:LoadGuide()
    local row = Frame("Frame", scrollChild)
    row.backdrop, row.Center = {}, Frame("Texture")
    scrollChild.framePool[#scrollChild.framePool + 1] = row
    return row
end
local questAction = Frame("Button", RXPFrame)
questAction.protected, questAction.backdrop, questAction.Center = true, {}, Frame("Texture")
local nativeQuestClick = function() end
questAction.scripts.OnClick = nativeQuestClick
RXPV2GuideWindow = Widget("RXPV2GuideWindow")
RXPV2GuideWindow.frame.backdrop, RXPV2GuideWindow.frame.Center = {}, Frame("Texture")
function RXPV2GuideWindow:UpdateTheme() self.frame.Center.alpha = 1 end
RXPV2GuideWindow.UpdateSubTheme = RXPV2GuideWindow.UpdateTheme
RXPV2GuideWindow.guideSteps = Widget("RXPV2GuideSteps")
RXPV2GuideWindow.guideSteps.frame.parent = RXPV2GuideWindow.frame
RXPV2GuideWindow.frame.children[#RXPV2GuideWindow.frame.children + 1] = RXPV2GuideWindow.guideSteps.frame
function RXPV2GuideWindow.guideSteps:SetRows(rows)
    for _ = 1, rows do
        local item = Widget("RXPV2GuideStepsItem")
        item.frame.kind = "Button" -- Native RXP guide step roots are buttons.
        item.frame.rxpBackground = Frame("Frame", item.frame)
        item.frame.rxpBackground.textures = { Frame("Texture") }
        self.items = self.items or {}
        self.items[#self.items + 1] = item
        item.frame.parent = self.frame -- Native RXP uses frame parenting, without widget.parent or AddChild.
        self.frame.children[#self.frame.children + 1] = item.frame
    end
end
NS.AddonSkins.SetOption("restedXP", true) Flush()
Check(paints[RXPFrame] == "shell" and RXPFrame.Center.alpha == 0, "RestedXP legacy shell was skipped")
Check(paints[RXPV2GuideWindow.frame] == "shell", "RestedXP V2 widget frame was missed")
Check(questAction.Center.alpha == 1 and questAction.scripts.OnClick == nativeQuestClick,
    "RestedXP skin changed a secure quest action")
Check(NS.AddonSkins.ResolveApp("RestedXP Guides/Guide Options") == "restedXP", "RestedXP AceConfig alias was missed")
-- Loading the saved guide after the shell is already visible can create rows
-- without a theme update or an AceGUI widget acquisition.
local loadedRow = RXP:LoadGuide()
Flush()
Check(loadedRow.Center.alpha == 0, "late RestedXP legacy guide row retained native chrome")
RXPFrame:UpdateVisuals() Flush()
Check(RXPFrame.Center.alpha == 0, "RestedXP theme rebuild retained native chrome")
RXPV2GuideWindow:UpdateTheme() Flush()
Check(RXPV2GuideWindow.frame.Center.alpha == 0, "RestedXP V2 UpdateTheme retained native chrome")
local painted = paintCounts[RXPV2GuideWindow.frame]
for _ = 1, 10 do RXPV2GuideWindow.guideSteps:SetRows(1) end
Flush()
Check(paintCounts[RXPV2GuideWindow.frame] == painted, "new RestedXP items repainted the entire guide window")
for _, item in ipairs(RXPV2GuideWindow.guideSteps.items) do
    Check(item.frame.rxpBackground.textures[1].alpha == 0, "new RXP button card retained native background art")
end
local unchangedReads = childReads
for _ = 1, 100 do
    RXPV2GuideWindow.guideSteps:SetRows(0)
    RXPV2GuideWindow.guideSteps.items[1]:OnAcquire()
end
Flush()
Check(childReads == unchangedReads and paintCounts[RXPV2GuideWindow.frame] == painted,
    "unchanged RestedXP rows or reused widgets repeated skin discovery")
combat = true
local combatItem = { type = "RXPV2GuideStepsItem", frame = Frame("Button"), OnAcquire = Noop }
combatItem.frame.parent = RXPV2GuideWindow.frame
RXPV2GuideWindow.frame.children[#RXPV2GuideWindow.frame.children + 1] = combatItem.frame
combatItem.frame.protected, combatItem.frame.implicit = true, true
combatItem.frame.rxpBackground = Frame("Frame", combatItem.frame)
local combatFill = Frame("Texture")
combatItem.frame.rxpBackground.textures = { combatFill }
gui:RegisterAsWidget(combatItem)
combatItem:OnAcquire()
Check(combatFill.alpha == 1 and not combatItem.frame.scripts.OnShow, "RXP combat acquire wrote or hooked protected frame scripts")
combat = false Flush()
Check(combatFill.alpha == 0, "RXP combat-created card missed its deferred construction skin")
-- RXP keeps every guide card in its pool, beyond the bounded initial root pass.
-- A root and its rows may all first be constructed while combat defers painting.
combat = true
local wide = { type = "RXPV2GuideWindow", frame = Frame("Frame", UIParent), OnAcquire = Noop }
wide.frame.protected, wide.frame.implicit = true, true
gui:RegisterAsWidget(wide) wide:OnAcquire()
local wideFills = {}
for index = 1, 240 do
    local item = { type = "RXPV2GuideStepsItem", frame = Frame("Button", wide.frame), OnAcquire = Noop }
    item.frame.protected, item.frame.implicit = true, true
    item.frame.rxpBackground = Frame("Frame", item.frame)
    wideFills[index] = Frame("Texture")
    item.frame.rxpBackground.textures = { wideFills[index] }
    local number = Frame("Frame", item.frame)
    number.rxpBackground, number.rxpBorder = Frame("Frame", number), Frame("Frame", number)
    gui:RegisterAsWidget(item) item:OnAcquire()
end
combat = false Flush()
for index, fill in ipairs(wideFills) do
    Check(fill.alpha == 0, "deferred RXP construction lost a card beyond the root budget: " .. index)
end
Check(next(queue) == nil, "wide RXP construction retained a retry loop")
local pooled = RXPV2GuideWindow.guideSteps.items[1]
local children = RXPV2GuideWindow.guideSteps.frame.children
for at = #children, 1, -1 do if children[at] == pooled.frame then table.remove(children, at) end end
pooled.frame.parent = UIParent -- AceGUI.Release removes it from the native window.
NS.AddonSkins.SetOption("restedXP", false) Flush()
Check(RXPFrame.Center.alpha == 1, "RestedXP disable did not restore native chrome")
Check(pooled.frame.rxpBackground.textures[1].alpha == 1, "RXP disable lost a detached pooled card")
NS.AddonSkins.SetOption("restedXP", true) Flush()
Check(pooled.frame.rxpBackground.textures[1].alpha == 1, "RXP enable scanned detached unused pool objects")
pooled.frame.parent = RXPV2GuideWindow.guideSteps.frame
children[#children + 1] = pooled.frame
painted = paintCounts[RXPV2GuideWindow.frame]
pooled:OnAcquire() Flush()
Check(pooled.frame.rxpBackground.textures[1].alpha == 0 and paintCounts[RXPV2GuideWindow.frame] == painted,
    "RXP disable/re-enable invalidated neither the pooled card generation nor its minimal repaint")
NS.AddonSkins.SetOption("restedXP", false) Flush()
-- The Compendium's own parchment and ink need an explicit page pass.
SpokenCompendiumWindow = Frame("Frame", UIParent)
local panel = Frame("Frame", SpokenCompendiumWindow)
panel.inset, panel.pageInset = Frame("Frame", panel), Frame("Frame", panel)
panel.inset.Bg = Frame("Texture")
local pageFrame = Frame("Frame", panel.pageInset)
local paper, picture, words = Frame("Texture"), Frame("Texture"), Frame("FontString")
local fadeStrip = Frame("Texture")
paper.texture, picture.texture, fadeStrip.texture = "shared-atlas-file", "shared-atlas-file", "shared-atlas-file"
paper.atlas, picture.atlas = "native-parchment", "story-picture"
words.textColor = { .25, .16, .08, 1 }
pageFrame.regions = { paper, picture, words, fadeStrip }
local body = { strips = { fadeStrip }, SetText = function() words:SetTextColor(.3, .2, .1, 1) end }
panel.page = { frame = pageFrame, bg = paper, body = body }
panel.Refresh = Noop
SpokenCompendium = { window = SpokenCompendiumWindow, tabs = { quests = { panel = panel } }, Open = Noop, Select = Noop }
NS.AddonSkins.SetOption("spoken", true) Flush()
Check(paper.alpha == 0 and panel.inset.Bg.alpha == 0, "Compendium retained parchment or marble over the Suite panels")
Check(fadeStrip.alpha == 0, "Compendium retained its parchment scroll-edge strips")
Check(surfaces[pageFrame] and surfaces[panel.inset], "Compendium page/inset did not receive Suite panels")
local textRed, textGreen = NS.Theme.GetColor("text")
Check(words.textColor[1] == textRed and words.textColor[2] == textGreen, "Compendium retained unreadable dark page ink")
body:SetText()
Check(words.textColor[1] == textRed, "native Compendium content refresh flashed dark text")
Check(picture.alpha == 1, "Compendium skin erased a semantic story picture")
NS.AddonSkins.SetOption("spoken", false) Flush()
Check(paper.alpha == 1 and panel.inset.Bg.alpha == 1 and words.textColor[1] == .3,
    "Compendium release did not restore the latest native paper/ink")
Check(fadeStrip.alpha == 1 and picture.alpha == 1, "Compendium release changed a picture or lost a parchment strip")
words:SetTextColor(.4, .3, .2, 1)
Check(words.textColor[1] == .4, "released Compendium text-color observer retained ownership")

-- Actual RXP V2 texture groups have no GetBackdrop. Include anonymous floating steps.
local upper = Frame("Frame", RXPV2GuideWindow.frame)
local fill, edge = Frame("Texture"), Frame("Texture")
upper.rxpBackground = Frame("Frame", upper)
upper.rxpBackground.textures = { fill }
upper.rxpBorder = Frame("Frame", upper)
upper.rxpBorder.textures = { edge }
RXPV2GuideWindow.frame.obj = RXPV2GuideWindow
RXPV2GuideWindow.banner, RXPV2GuideWindow.footerBackground = Frame("Texture"), Frame("Texture")
local actionIcon = Frame("Texture")
upper.regions = { actionIcon }
NS.AddonSkins.SetOption("restedXP", true) Flush()
Check(fill.alpha == 0 and edge.alpha == 0 and surfaces[upper], "RXP custom background/border groups remained native")
Check(RXPV2GuideWindow.banner.alpha == 0 and RXPV2GuideWindow.footerBackground.alpha == 0,
    "RXP V2 retained its banner/footer over the Suite material")
Check(actionIcon.alpha == 1, "RXP skin erased a semantic action icon")
local floating = { type = "RXPV2ActiveStepsFrame", frame = Frame("Frame", UIParent), OnAcquire = Noop }
floating.frame.rxpBackground = Frame("Frame", floating.frame)
local floatingFill = Frame("Texture")
floating.frame.rxpBackground.textures = { floatingFill }
gui:RegisterAsWidget(floating)
floating:OnAcquire()
Flush()
Check(NS.AddonSkins.roots[floating.frame] and floatingFill.alpha == 0, "anonymous RXP active steps were not skinned on pool acquisition")
NS.AddonSkins.SetOption("restedXP", false) Flush()
Check(fill.alpha == 1 and edge.alpha == 1 and floatingFill.alpha == 1, "RXP texture groups were not restored on disable")

-- The real LibSettingsDesigner publishes a named frame only inside UI:Open.
-- Compartment, binding and Blizzard Settings launches need this shared edge.
local library = { _Internal = {} }
function library._Internal.applyFrameBackground(frame, app) frame.bg:SetAlpha(app.alpha) end
function library._Internal.applySidebarShellBackground(frame, app) frame.SidebarBackgroundTexture:SetAlpha(app.sidebarAlpha) end
function library._Internal.applyContentShellBackground(frame, app) frame.ContentBackgroundTexture:SetAlpha(.75) end
function library:Open(app)
    local name = app.id .. "ConfigCenterFrame"
    local frame = _G[name]
    if not frame then
        frame = Frame("Frame", UIParent)
        _G[name] = frame
        frame.bg, frame.MaterialOverlay = Frame("Texture"), Frame("Texture")
        frame.MaterialOverlay.alpha = .08
        frame.SidebarShell, frame.ContentShell = Frame("Frame", frame), Frame("Frame", frame)
        frame.SidebarShell.SidebarBackgroundTexture = Frame("Texture")
        frame.ContentShell.ContentBackgroundTexture = Frame("Texture")
        local row = Frame("Frame", frame.ContentShell)
        frame.styleFill, frame.styleBorder = Frame("Texture"), Frame("Texture")
        frame.styleFill.alpha = .65
        row._LibSettingsDesignerTextureStyleParts = { Fill = { L = frame.styleFill }, Border = { L = frame.styleBorder } }
        local swatch = Frame("Button", frame.ContentShell)
        frame.swatch = Frame("Texture")
        swatch._LibSettingsDesignerColorTextureParts = { Fill = { M = frame.swatch } }
        frame._LibSettingsDesignerState = { app = app, RenderContent = function() frame.styleFill.alpha = .65 end }
    end
    self._Internal.applyFrameBackground(frame, app)
    self._Internal.applySidebarShellBackground(frame.SidebarShell, app)
    self._Internal.applyContentShellBackground(frame.ContentShell, app)
    frame:Show()
    return frame
end
EnhanceQoL = { LibSettingsDesigner = { UI = library } }
NS.AddonSkins.SetOption("enhanceQoL", true) Flush()
local app = { id = "EnhanceQoL", alpha = .9, sidebarAlpha = .6 }
local discoveryReads = sourceReads
local eqol = library:Open(app) Flush()
Check(NS.AddonSkins.roots[eqol] and sourceReads == discoveryReads, "framework Open missed the root or globally rediscovered windows")
Check(eqol.bg.alpha == 0 and eqol.MaterialOverlay.alpha == 0 and eqol.styleFill.alpha == 0 and eqol.styleBorder.alpha == 0,
    "Enhance QoL native window/style art covered the Suite skin")
Check(eqol.SidebarShell.SidebarBackgroundTexture.alpha == 0 and eqol.ContentShell.ContentBackgroundTexture.alpha == 0,
    "shared framework retained native sidebar/content images")
Check(eqol.swatch.alpha == 1, "shared framework erased a semantic color swatch")
eqol._LibSettingsDesignerState:RenderContent() Flush()
Check(eqol.styleFill.alpha == 0, "Enhance QoL pooled content lost its skin after rendering")
local cleanPaints, cleanChildren = paintCounts[eqol], childReads
for _ = 1, 100 do eqol:Show() end
Flush()
Check(paintCounts[eqol] == cleanPaints and childReads == cleanChildren, "framework warm shows repeated the skin pass")
app.alpha, app.sidebarAlpha = .37, 0
library:Open(app) Flush()
NS.AddonSkins.SetOption("enhanceQoL", false) Flush()
Check(eqol.bg.alpha == .37 and eqol.SidebarShell.SidebarBackgroundTexture.alpha == 0
    and eqol.ContentShell.ContentBackgroundTexture.alpha == .75 and eqol.MaterialOverlay.alpha == .08 and eqol.styleFill.alpha == .65,
    "Enhance QoL disable did not restore authored transparency")
CampingKit = { LibSettingsDesigner = { UI = library } }
NS.AddonSkins.InstallTriggers()
local camping = library:Open({ id = "CampingKit", alpha = .8, sidebarAlpha = .5 }) Flush()
Check(NS.AddonSkins.roots[camping].id == "campingKit" and camping.ContentShell.ContentBackgroundTexture.alpha == 0,
    "shared framework was restricted to the EQoL adapter")

-- Existing guides can be larger than either initial tree budget at enable.
NS.AddonSkins.SetOption("restedXP", false) Flush()
local existing = Widget("RXPV2GuideWindow")
existing.guideSteps = Widget("RXPV2GuideSteps")
existing.guideSteps.frame.parent = existing.frame
existing.frame.children[#existing.frame.children + 1] = existing.guideSteps.frame
existing.guideSteps.items = {}
for index = 1, 240 do
    local item = Widget("RXPV2GuideStepsItem")
    item.frame.kind, item.frame.parent = "Button", existing.guideSteps.frame
    existing.guideSteps.frame.children[#existing.guideSteps.frame.children + 1] = item.frame
    item.frame.rxpBackground = Frame("Frame", item.frame)
    item.frame.rxpBackground.textures = { Frame("Texture") }
    item.text, item.number = Frame("FontString"), Frame("FontString")
    item.frame.regions = { item.text, item.number }
    Frame("Frame", item.frame) -- native numberFrame
    existing.guideSteps.items[index] = item
end
RXPV2GuideWindow = existing
NS.AddonSkins.SetOption("restedXP", true) Flush()
for index, item in ipairs(existing.guideSteps.items) do
    Check(item.frame.rxpBackground.textures[1].alpha == 0 and labels[item.text] and labels[item.number],
        "existing RXP guide missed a complete card at enable: " .. index)
end
local existingPaints, existingReads = paintCounts[existing.frame], childReads
for _ = 1, 100 do existing.guideSteps.items[240]:OnAcquire() end
Flush()
Check(paintCounts[existing.frame] == existingPaints and childReads == existingReads, "completed RXP catch-up did not stay warm")
for _, item in ipairs(existing.guideSteps.items) do labels[item.text], labels[item.number] = nil, nil end
NS.AddonSkins.RefreshAddon("restedXP") Flush() -- Native theme force-resets all row fonts.
for index, item in ipairs(existing.guideSteps.items) do
    Check(labels[item.text] and labels[item.number], "RXP theme refresh missed a cached card font: " .. index)
end
local popup = Widget("RXPV2Popup") Flush()
local popupPaints = paintCounts[popup.frame]
popup:OnAcquire() Flush()
Check(paintCounts[popup.frame] == popupPaints + 1, "native root pool acquisition did not refresh its rebuilt controls")

-- Numy's UI is lazy. Neither profiling ticks nor repeated value/pool updates
-- may perform Suite work; only a new FontString has a construction callback.
NS.AddonSkins.SetOption("addonProfiler", false) Flush()
local profilerTicks = 0
local profilerTick = function() profilerTicks = profilerTicks + 1 end
local function ProfilerRow(parent)
    local row = Frame("Button", parent)
    function row:CreateFontString()
        local label = Frame("FontString")
        self.regions[#self.regions + 1] = label
        return label
    end
    row.UpdateColumns = profilerTick
    return row
end
NumyAddonProfiler = { InitUI = function(self)
    self.ProfilerFrame = Frame("Frame", UIParent)
    self.ProfilerFrame:SetScript("OnUpdate", profilerTick)
    self.ProfilerFrame.TotalRow = ProfilerRow(self.ProfilerFrame)
    self.ProfilerFrame.ResizeButton = Frame("Button", self.ProfilerFrame)
    self.ProfilerFrame.ScrollBox = Frame("Frame", self.ProfilerFrame)
    self.visibleRow = ProfilerRow(self.ProfilerFrame.ScrollBox)
    function self.ProfilerFrame.ScrollBox:ForEachFrame(callback) callback(NumyAddonProfiler.visibleRow) end
    self.PinContainer = Frame("Frame", UIParent)
    self.PinContainer:SetScript("OnUpdate", profilerTick)
    self.PinContainer.regions = { Frame("Texture") }
    self.PinContainer.regions[1].alpha = .75
    self.PinContainer.Header = ProfilerRow(self.PinContainer)
    self.PinContainer.Header.BG = Frame("Texture")
    self.PinContainer.pinnedAddons = {}
    function self.PinContainer:PinAddon(name)
        self.pinnedAddons[name] = self.pinnedAddons[name] or ProfilerRow(self)
    end
end, ToggleFrame = function(self)
    if self.ProfilerFrame:IsShown() then self.ProfilerFrame:Hide() else self.ProfilerFrame:Show() end
end, CollectData = profilerTick }
-- Mirror Numy's installed launcher routes. Right clicks and non-UI slash
-- commands affect profiling or preferences without opening a window.
local function ProfilerClick(_, button)
    if button == "LeftButton" then NumyAddonProfiler:ToggleFrame() else profilerTick() end
end
local function ProfilerSlash(command)
    if command == "" or command == "ui" then NumyAddonProfiler:ToggleFrame() else profilerTick() end
end
SlashCmdList.NUMY_ADDON_PROFILER = ProfilerSlash
NumyAddonProfiler_OnAddonCompartmentClick = ProfilerClick
local profilerBroker = broker:NewDataObject("NumyAddonProfiler", { OnClick = ProfilerClick })
local profilerToggle = NumyAddonProfiler.ToggleFrame
C_AddOns.GetAddOnMetadata = function(addon, key)
    if addon ~= "!!AddonProfiler" then return end
    if key == "AddonCompartmentFunc" then return "NumyAddonProfiler_OnAddonCompartmentClick" end
    if key == "Title" then return "Localized profiler title" end
end
NS.AddonSkins.SetOption("addonProfiler", true) Flush()
local profilerReads = sourceReads
combat = true
NumyAddonProfiler:InitUI() Flush()
local profiler = NumyAddonProfiler
local nativePin = profiler.PinContainer.PinAddon
profiler.ProfilerFrame:Hide()
Check(not NS.AddonSkins.roots[profiler.ProfilerFrame] and not NS.AddonSkins.roots[profiler.PinContainer],
    "profiler construction attached a root in combat")
combat = false
Flush()
Check(profiler.PinContainer.PinAddon ~= nativePin and not paints[profiler.ProfilerFrame],
    "profiler pin hook was not deferred or the hidden profiler was painted")
SlashCmdList.NUMY_ADDON_PROFILER("ui") Flush()
Check(NS.AddonSkins.ResolveApp("!!AddonProfiler") == "addonProfiler"
    and NS.AddonSkins.ResolveApp("Numy's Addon Profiler") == "addonProfiler", "Numy's profiler identity was missed")
Check(NS.AddonSkins.ResolveApp("Localized profiler title") == "addonProfiler", "profiler title alias was lost")
Check(NumyAddonProfiler_OnAddonCompartmentClick == ProfilerClick and SlashCmdList.NUMY_ADDON_PROFILER == ProfilerSlash
    and profilerBroker.OnClick == ProfilerClick, "skin hooked a generic profiler launcher")
Check(profiler.ToggleFrame == profilerToggle, "skin hooked the warm profiler toggle")
Check(NS.AddonSkins.roots[profiler.ProfilerFrame] and NS.AddonSkins.roots[profiler.PinContainer],
    "lazy profiler construction missed its main or pin window")
Check(sourceReads == profilerReads, "known profiler construction scanned the global UI")
Check(paintModes[profiler.ProfilerFrame].registerDynamicRows == false,
    "profiling list acquired recurring row-initialization callbacks")
Check(profiler.PinContainer.regions[1].alpha == 0 and profiler.PinContainer.Header.BG.alpha == 0,
    "the separate profiler pin background retained native art")
local totalLabel = profiler.ProfilerFrame.TotalRow:CreateFontString()
local mainRowLabel = profiler.visibleRow:CreateFontString()
Check(labels[totalLabel] and labels[mainRowLabel], "new profiler columns missed cold construction styling")
profiler.visibleRow = ProfilerRow(profiler.ProfilerFrame.ScrollBox)
profiler.ProfilerFrame.ResizeButton.scripts.OnMouseUp(profiler.ProfilerFrame.ResizeButton) Flush()
local resizedLabel = profiler.visibleRow:CreateFontString()
Check(labels[resizedLabel], "new rows created by native window resizing missed construction styling")
profiler.PinContainer:PinAddon("Example") Flush()
local pinLabel = profiler.PinContainer.pinnedAddons.Example:CreateFontString()
Check(labels[pinLabel], "a late pinned row missed construction styling")
local profilerPaints, pinPaints, profilerChildren = paintCounts[profiler.ProfilerFrame], paintCounts[profiler.PinContainer], childReads
for _ = 1, 1000 do
    profiler:CollectData()
    profiler.visibleRow:UpdateColumns()
    profiler.PinContainer.scripts.OnUpdate()
end
for _ = 1, 100 do
    SlashCmdList.NUMY_ADDON_PROFILER("ui")
    SlashCmdList.NUMY_ADDON_PROFILER("reset")
    profilerBroker.OnClick(nil, "LeftButton")
    profilerBroker.OnClick(nil, "RightButton")
    NumyAddonProfiler_OnAddonCompartmentClick(nil, "LeftButton")
    NumyAddonProfiler_OnAddonCompartmentClick(nil, "RightButton")
end
Check(not next(queue), "profiler launchers queued work after its windows were skinned")
Flush()
Check(paintCounts[profiler.ProfilerFrame] == profilerPaints and paintCounts[profiler.PinContainer] == pinPaints
    and childReads == profilerChildren and sourceReads == profilerReads, "warm profiler work repainted or scanned windows")
Check(profiler.CollectData == profilerTick and profiler.visibleRow.UpdateColumns == profilerTick
    and profiler.ProfilerFrame.scripts.OnUpdate == profilerTick and profiler.PinContainer.scripts.OnUpdate == profilerTick,
    "Suite wrapped native profiling or data updates")
NS.AddonSkins.SetOption("addonProfiler", false) Flush()
Check(profiler.PinContainer.regions[1].alpha == .75 and not labels[pinLabel], "profiler disable failed to restore its owned art")
local offLabel = profiler.PinContainer.pinnedAddons.Example:CreateFontString()
Check(not labels[offLabel], "disabled profiler construction still received a skin")
NS.AddonSkins.SetOption("addonProfiler", true) Flush()
Check(labels[offLabel] and profiler.PinContainer.regions[1].alpha == 0, "profiler re-enable missed its existing pool")

local protected = Frame()
protected.protected = true
Check(not NS.AddonSkins.Watch(protected, "bugSack"), "protected window was accepted")
Check(not NS.AddonSkins.Watch(protected, "restedXP"), "RestedXP accepted an explicitly protected action")
combat = true
Check(not NS.AddonSkins.Watch(RXPFrame, "restedXP"), "RestedXP protected shell was accepted in combat")
Check(not NS.AddonSkins.SetOption("enabled", false), "combat setting mutation was accepted")
combat = false
NS.AddonSkins.SetOption("enabled", false) Flush()
for _, frame in ipairs(frames) do
    Check(not frame.scripts.OnUpdate
        or (frame == spokenPlayer or frame.name == "SpokenSubtitleFrame") and frame.scripts.OnUpdate == nativeTick
        or frame == profiler.ProfilerFrame and frame.scripts.OnUpdate == profilerTick
        or frame == profiler.PinContainer and frame.scripts.OnUpdate == profilerTick,
        "addon skin introduced idle polling")
end
print("Suite addon skins (" .. (arg[2] or "Mainline") .. "): " .. checks .. " checks passed")
