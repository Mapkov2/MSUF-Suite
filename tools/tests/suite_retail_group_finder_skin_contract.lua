local root = assert(arg[1], "Suite root required")
local skin = root .. "/MSUF_Suite_Skin/"
local owner = "blizzardWindows"
local combat, deferred = false, {}
local nativeOpening, nativeLoaded, loader = false, false, nil
local timers = {}

securecallfunction = function(callback, ...) return callback(...) end
InCombatLockdown = function() return combat end
ScrollBoxListMixin = { Event = { OnInitializedFrame = "OnInitializedFrame" } }
C_Timer = { After = function(delay, callback)
    assert(delay == 0)
    timers[#timers + 1] = callback
end }
EventUtil = { ContinueOnAddOnLoaded = function(addon, callback)
    assert(addon == "Blizzard_GroupFinder" and not nativeLoaded and not loader)
    loader = callback
end }

hooksecurefunc = function(name, callback)
    local native = assert(_G[name])
    _G[name] = function(...)
        native(...)
        callback(...)
    end
end

local function RunTimers()
    local pending = timers
    timers = {}
    for _, callback in ipairs(pending) do callback() end
end

local function Widget(kind)
    local widget = { alpha = 1, shown = true, kind = kind or "Frame", hooks = {}, paints = 0 }
    function widget:GetObjectType() return self.kind end
    function widget:GetAlpha() return self.alpha end
    function widget:SetAlpha(alpha)
        assert(not combat)
        self.alpha = alpha
    end
    function widget:IsVisible() return self.shown end
    function widget:HookScript(event, fn) self.hooks[event] = fn end
    function widget:Show()
        self.shown = true
        if self.hooks.OnShow then self.hooks.OnShow(self) end
    end
    function widget:GetRegions() return unpack(self.regions or {}) end
    function widget:GetNormalTexture() return self.Normal end
    function widget:GetHighlightTexture() return self.Highlight end
    function widget:GetPushedTexture() return self.Pushed end
    function widget:GetDisabledTexture() return self.Disabled end
    function widget:SetHighlightTexture(texture) self.Highlight = texture end
    function widget:SetPushedTexture(texture) self.Pushed = texture end
    function widget:SetDisabledTexture(texture) self.Disabled = texture end
    function widget:CreateTexture() return Widget("Texture") end
    return widget
end

local function Button(kind)
    local button = Widget(kind or "Button")
    button.Middle, button.Highlight = Widget("Texture"), Widget("Texture")
    return button
end

local function Paint(target, spec)
    assert(not combat, "finder skinned a control in combat")
    assert(not nativeOpening, "finder styled the window inside Blizzard's opening stack")
    target.paints = target.paints + 1
    local surface = target.surface or {}
    surface.spec, surface.visible = spec, true
    target.surface = surface
    return surface
end

local NS = {
    Client = { isForever = false, IsAddOnLoaded = function() return nativeLoaded end },
    DB = { enabled = true, skins = {} },
    BlizzardCatalog = {},
    GenericWindows = {
        IsCategoryEnabled = function(category) return category == "group" end,
        ApplyAll = function() return false, "unavailable" end,
    },
    WindowControls = { TrackFocus = function() end },
    IsCombatLocked = InCombatLockdown,
    Registry = { GetSurface = function(target) return target.surface end },
    Surface = {
        Attach = Paint,
        SkinOwnedButton = function(target, spec, active)
            local surface = Paint(target, spec)
            surface.kind, surface.active = "button", active
            surface.highlight = surface.highlight or Widget("Texture")
            surface.pushed = surface.pushed or Widget("Texture")
            surface.disabled = surface.disabled or Widget("Texture")
            return surface
        end,
        EnsureOwnedButtonHighlightLayer = function() end,
        SetNativeStateSync = function() end,
        SetVisible = function(target, visible) target.surface.visible = visible end,
    },
    CombatGate = {
        RunOrDefer = function(key, callback)
            if combat then deferred[key] = callback else callback() end
        end,
        Cancel = function(key) deferred[key] = nil end,
    },
    Checkmarks = {
        GetWindowAction = function() end,
        TrackButton = function(button) if button then button.tracked = true end end,
        TrackDropdown = function() end,
        UntrackDropdown = function() end,
        UntrackOwner = function() end,
    },
    WindowActionSkin = {},
}

for _, path in ipairs({
    "../MSUF_Suite/Appearance/Safety.lua", "../MSUF_Suite/Appearance/Cosmetics.lua",
    "Rendering/ControlSkin.lua", "Adapters/AdapterKit.lua",
}) do
    assert(loadfile(skin .. path))("MSUF_Suite_Skin", NS)
end
assert(loadfile(arg[2] or skin .. "Adapters/CommonArt.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(arg[3] or skin .. "Adapters/Blizzard.lua"))("MSUF_Suite_Skin", NS)

-- Reload before the native frames exist. Even a catalog apply that returns
-- early must leave the exact Retail finder armed for Blizzard's load.
assert(not NS.Adapters.Apply(owner) and loader and #timers == 0,
    "the normal adapter path lost the Retail finder when the catalog or native addon was unavailable")

local function ScrollBox(row)
    local box = Widget()
    box.row = row
    function box:RegisterCallback(event, callback, context)
        assert(event == "OnInitializedFrame" and not self.initialized)
        self.initialized, self.context = callback, context
    end
    function box:UnregisterCallback(event, context)
        assert(event == "OnInitializedFrame" and self.context == context)
        self.initialized, self.context = nil, nil
    end
    function box:HasView() return true end
    function box:ForEachFrame(callback) callback(self.row) end
    function box:Initialize() self.initialized(self.context, self.row) end
    return box
end

local function Choice()
    local checkbox, disclosure = Button("CheckButton"), Button()
    checkbox.Normal, checkbox.Checked = Widget("Texture"), Widget("Texture")
    return { enableButton = checkbox, expandOrCollapseButton = disclosure, lockedIndicator = Widget("Texture") }
end

PVEFrame, PVEFrameBlueBg = Widget(), Widget("Texture")
PVEFrame.shown, PVEFrame.shadows = false, Widget()
PVEFrame.Inset = Widget()
GroupFinderFrame = { groupButton1 = Button(), groupButton3 = Button() }
local navigation = GroupFinderFrame.groupButton1
navigation.bg, navigation.ring, navigation.icon = Widget("Texture"), Widget("Texture"), Widget("Texture")
LFDQueueFrameFindGroupButton, RaidFinderFrameFindRaidButton = Button(), Button()
local findGroup = LFDQueueFrameFindGroupButton
local nativeHighlight = findGroup.Highlight
local specific, follower = Choice(), Choice()
local specificBox, followerBox = ScrollBox(specific), ScrollBox(follower)
LFDQueueFrame = { Specific = { ScrollBox = specificBox }, Follower = { ScrollBox = followerBox }, TypeDropdown = Button() }
local dropdown = LFDQueueFrame.TypeDropdown
dropdown.Background, dropdown.Arrow = Widget("Texture"), Widget("Texture")
LFDQueueFrameRoleButtonDPS = Button()
local role = LFDQueueFrameRoleButtonDPS
role.background, role.Normal = Widget("Texture"), Widget("Texture")
RaidFinderFrameBottomInset = Widget()
RaidFinderFrameBottomInset.NineSlice = { BottomEdge = Widget("Texture") }

local category, search, entry = Widget(), Widget(), Widget()
category.StartGroupButton, category.FindGroupButton = Button(), Button()
search.SearchBox, search.SignUpButton, search.AutoCompleteFrame = Widget("EditBox"), Button(), Widget()
search.AutoCompleteFrame.BottomBorder = Widget("Texture")
local result = Button()
result.ResultBG, result.BackgroundTexture = Widget("Texture"), Widget("Texture")
search.ScrollBox = ScrollBox(result)
local description, activity = Widget("ScrollFrame"), Widget()
description.TopTex, description.EditBox = Widget("Texture"), Widget("EditBox")
activity.BorderFrame = { NineSlice = { TopEdge = Widget("Texture") } }
activity.EntryBox, activity.SelectButton = Widget("EditBox"), Button()
entry.Description, entry.ActivityFinder, entry.ListGroupButton = description, { Dialog = activity }, Button()
LFGListFrame = { CategorySelection = category, SearchPanel = search, EntryCreation = entry }
LFGDungeonReadyPopup = Widget()
LFGDungeonReadyPopup.shown = false
LFGDungeonReadyDialog = { background = Widget("Texture"), enterButton = Button(), roleIcon = Widget("Texture") }

function GroupFinderFrame_ShowGroupFrame()
    assert(nativeOpening)
end
function LFGListCategorySelection_UpdateCategoryButtons() end

local function OpenNativeFinder(shellAlreadyShown)
    nativeOpening = true
    if shellAlreadyShown then PVEFrame.shown = true else PVEFrame:Show() end
    GroupFinderFrame_ShowGroupFrame()
    nativeOpening = false
end

nativeLoaded = true
loader()
assert(not findGroup.surface and #timers == 0, "native addon loading painted a closed finder")
combat = true
LFGDungeonReadyPopup:Show()
-- The native page selection can follow an early shell show that already ran.
OpenNativeFinder(true)
assert(#timers == 1, "native group selection did not schedule the missing paint")
RunTimers()
assert(next(deferred) and not findGroup.surface and not LFGDungeonReadyDialog.enterButton.surface,
    "first opening in combat did not defer both surfaces")
local function EndCombat()
    combat = false
    local pending = deferred
    deferred = {}
    for _, callback in pairs(pending) do callback() end
end
EndCombat()

assert(findGroup.surface and findGroup.Middle.alpha == 0 and RaidFinderFrameFindRaidButton.Middle.alpha == 0,
    "Dungeon and Raid Finder queue buttons kept the native skin")
assert(PVEFrame.Inset.surface and PVEFrameBlueBg.alpha == 0 and PVEFrame.shadows.alpha == 0
    and navigation.bg.alpha == 0 and navigation.ring.alpha == 0 and navigation.icon.alpha == 1,
    "the navigation kept native chrome or lost a category icon")
assert(dropdown.Background.alpha == 0 and dropdown.Arrow.alpha == 1 and role.background.alpha == 0 and role.Normal.alpha == 1,
    "queue controls kept native chrome or lost an arrow or role icon")
assert(RaidFinderFrameBottomInset.surface and RaidFinderFrameBottomInset.NineSlice.BottomEdge.alpha == 0,
    "Raid Finder's lower inset kept its native frame")
assert(category.StartGroupButton.Middle.alpha == 0 and category.FindGroupButton.Middle.alpha == 0
    and search.SignUpButton.Middle.alpha == 0 and entry.ListGroupButton.Middle.alpha == 0,
    "one of the Premade Groups actions remained red")
assert(search.SearchBox.surface and search.AutoCompleteFrame.BottomBorder.alpha == 0 and result.ResultBG.alpha == 0
    and result.BackgroundTexture.alpha == 1, "the search skin missed chrome or concealed a result status")
assert(description.surface and description.TopTex.alpha == 0 and not description.EditBox.surface
    and activity.EntryBox.surface and activity.BorderFrame.NineSlice.TopEdge.alpha == 0,
    "the listing form kept native borders or styled the protected inner edit box")
assert(LFGDungeonReadyDialog.background.alpha == 0 and LFGDungeonReadyDialog.enterButton.Middle.alpha == 0
    and LFGDungeonReadyDialog.roleIcon.alpha == 1, "the ready prompt missed its skin or lost a role icon")

for _, row in ipairs({ specific, follower }) do
    assert(row.enableButton.Normal.alpha == 0 and row.enableButton.Checked.alpha == 1
        and row.expandOrCollapseButton.tracked and row.lockedIndicator.alpha == 1,
        "a dungeon row lost its native state or kept its stock checkbox")
end
local reused = follower.enableButton
followerBox:Initialize()
assert(reused.paints == 1, "the pooled row repainted its fixed checkbox on reuse")
followerBox.row = Choice()
followerBox:Initialize()
assert(followerBox.row.enableButton.surface, "a late dungeon row missed the skin")
combat = true
followerBox.row = Choice()
followerBox:Initialize()
assert(next(deferred) and not followerBox.row.enableButton.surface, "combat row arrival lost its deferred pass")
EndCombat()
assert(followerBox.row.enableButton.surface, "combat row arrival missed the skin after combat")

NS.CommonArt.Disable(owner)
NS.ControlSkin.DisableOwner(owner)
NS.Cosmetics.RestoreOwner(owner)
assert(not specificBox.initialized and not followerBox.initialized and not search.ScrollBox.initialized
    and not next(deferred), "finder callbacks survived teardown")
assert(not findGroup.surface.visible and findGroup.Middle.alpha == 1 and findGroup.Highlight == nativeHighlight
    and PVEFrameBlueBg.alpha == 1 and reused.Normal.alpha == 1 and description.TopTex.alpha == 1,
    "turning off the skin failed to restore native art and button feedback")

PVEFrame.shown = false
NS.Adapters.Apply(owner)
OpenNativeFinder(false)
assert(#timers == 1 and findGroup.Middle.alpha == 1, "shell show and native page selection did not coalesce")
RunTimers()
assert(findGroup.Middle.alpha == 0, "normal first open did not paint the queue button")
OpenNativeFinder(true)
assert(#timers == 0, "a warm group selection scheduled a full paint")
PVEFrame.shown = false
local newCategory = Button()
category.CategoryButtons = { newCategory }
LFGListCategorySelection_UpdateCategoryButtons(category)
assert(not newCategory.surface and #timers == 0, "a hidden category update painted the finder")
OpenNativeFinder(false)
RunTimers()
assert(newCategory.surface, "a category added while hidden missed its first visible paint")

NS.Adapters.Apply(owner)
assert(#timers == 1, "a visible refresh did not schedule a paint")
NS.CommonArt.Disable(owner)
NS.ControlSkin.DisableOwner(owner)
NS.Cosmetics.RestoreOwner(owner)
RunTimers()
assert(findGroup.Middle.alpha == 1, "a queued paint survived disabling the finder")

NS.Client.isForever = true
assert(NS.CommonArt.Apply(owner) and not next(NS.CommonArt.owners) and not findGroup.surface.visible,
    "the Retail finder initialized in Forever")

print("Retail Group Finder chrome, pooled rows, combat and restoration passed")
