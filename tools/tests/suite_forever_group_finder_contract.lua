local root = assert(arg[1], "Suite root required")
securecallfunction = function(callback, ...) return callback(...) end
local events, hooks, frames, buttons, faded = {}, {}, {}, {}, {}
local surfaces, checked, deferred = {}, {}, {}
local inCombat = false
InCombatLockdown = function() return inCombat end
local categoryEnabled = true
local mockEventFrame
ScrollBoxListMixin = { Event = { OnInitializedFrame = "initialized" } }
local function ScrollBox()
    local box = { callbacks = {}, rows = {} }
    function box:RegisterCallback(event, callback, token)
        self.callbacks[token] = callback
    end
    function box:UnregisterCallback(event, token)
        self.callbacks[token] = nil
    end
    function box:ForEachFrame(callback)
        for _, row in ipairs(self.rows) do callback(row) end
    end
    -- CallbackRegistry passes the registration owner first.
    function box:Initialize(row, elementData)
        row.elementData = elementData or row.elementData or {}
        row.GetElementData = function(self) return self.elementData end
        for token, callback in pairs(self.callbacks) do callback(token, row) end
    end
    return box
end

function CreateFrame()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(name, script) self.scripts[name] = script end
    mockEventFrame = frame
    return frame
end
function hooksecurefunc(name, method, callback)
    if type(name) == "table" then
        hooks[name] = hooks[name] or {}
        assert(hooks[name][method] == nil, "duplicate group finder method hook")
        hooks[name][method] = callback
        local original = name[method]
        name[method] = function(self, ...)
            original(self, ...)
            callback(self, ...)
        end
    else
        assert(hooks[name] == nil, "duplicate group finder hook")
        hooks[name] = method
    end
end

local namespace = {
    Client = { isForever = true, HasAddOn = function(name)
        assert(name == "Blizzard_GroupFinder_VanillaStyle")
        return true
    end },
    IsCombatLocked = function() return inCombat end,
    GenericWindows = {
        IsCategoryEnabled = function(category)
            assert(category == "group")
            return categoryEnabled
        end,
        ApplyFrame = function(frame, owner, mode)
            frames[frame] = { owner = owner, role = mode.role, depth = mode.maxDepth }
            return true
        end,
        Disable = function(owner)
            for frame, state in pairs(frames) do
                if state.owner == owner then frames[frame] = nil end
            end
            return true
        end,
    },
    ControlSkin = {
        ApplyButton = function(button, owner, spec)
            assert(not inCombat, "button paint during combat")
            if button.objectType == "Frame" then return nil, "invalid button" end
            buttons[button] = { owner = owner, role = spec.role, regions = spec.regions }
            surfaces[button] = { spec = spec, visible = true }
            return true
        end,
        ApplyTab = function(tab, owner, spec)
            buttons[tab] = { owner = owner, role = spec.role }
        end,
    },
    Cosmetics = {
        Fade = function(region, owner) faded[region] = owner end,
        FadeNineSlice = function() end,
        SuppressVertexAlpha = function(region, owner) faded[region] = owner end,
    },
    Surface = {
        Attach = function(frame, spec)
            assert(not inCombat, "surface paint during combat")
            surfaces[frame] = { spec = spec, visible = true }
            return surfaces[frame]
        end,
        SetActive = function(frame, active)
            assert(not inCombat, "selection paint during combat")
            assert(surfaces[frame], "selection has no surface")
            surfaces[frame].active = active
        end,
        SetVisible = function(frame, visible)
            if surfaces[frame] then surfaces[frame].visible = visible end
        end,
    },
    Checkmarks = { TrackFrame = function(frame) checked[frame] = true end },
    CombatGate = {
        Cancel = function(key) deferred[key] = nil end,
        RunOrDefer = function(key, callback)
            if inCombat then deferred[key] = callback return false, "combat" end
            return callback()
        end,
    },
}
namespace.Surface.Ensure = namespace.Surface.Attach

-- The real guards and ScrollBox row helpers.
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", namespace)
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/AdapterKit.lua"))("MSUF_Suite_Skin", namespace)
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/SharedChrome.lua"))("MSUF_Suite_Skin", namespace)
assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Adapters/ForeverGroupFinder.lua"))(
    "MSUF_Suite_Skin", namespace)
local adapter = assert(namespace.ForeverGroupFinder)
inCombat = true
local applied, state = adapter.Apply()
assert(applied and state == "waiting" and mockEventFrame.events.ADDON_LOADED,
    "combat startup lost later native ADDON_LOADED")
inCombat = false

-- Blizzard_GroupFinder_VanillaStyle as of Forever 1.60.1.70009: the role strip's
-- background has no parentKey (only its atlas names it), the insets carry
-- CustomBG plus a Border, and browse, activity and Who lists gained a stone
-- header (Bg) and two scroll lines.
local function Texture(atlas)
    return { GetAtlas = function() return atlas end, shown = false,
        IsShown = function(self) return self.shown end,
        SetShown = function(self, shown) self.shown = shown end }
end
local function Button()
    local normal = Texture()
    return { Background = Texture(), Icon = Texture(),
        GetNormalTexture = function() return normal end }
end
local function SideTab(selected)
    return { objectType = "Frame", Background = Texture(), Icon = Texture(), Mask = Texture(),
        SelectedTexture = Texture(), HighlightTexture = Texture(), TabGlow = Texture(),
        SetChecked = function(self, value) self.SelectedTexture:SetShown(value) end,
        initiallySelected = selected }
end
local function SelectionBehavior()
    return { selections = {}, IsSelected = function(self, row)
        return self.selections[row:GetElementData()] == true
    end }
end
local roleArt, roleIcon = Texture("groupfinder-roles-background"), Texture("groupfinder-icon-role-large-tank")
local cardArt, cardLabel = {}, {}
local card = { Icon = cardArt, Cover = {}, Label = cardLabel, HighlightTexture = {} }
local rolesSection = { GetRegions = function() return roleArt, roleIcon end }
local listingInset = { CustomBG = {}, Border = {} }
local divider = {}
local activityView = { BarTop = {}, BarMiddle = {}, PlayStyleDropdown = Button(), VoiceChatDropdown = Button(),
    ScrollBar = {}, ScrollBox = ScrollBox(), Comment = { EditBox = {}, NineSlice = {} },
    LevelRangesCheckbox = { Checkbox = {} } }
local browseInset = { CustomBG = {}, Border = {} }
local whoFilter = { Background = {} }
_G.LFGParentFrame = { Tab1 = {}, Tab2 = {}, Tab3 = {},
    ListingTab = SideTab(false), BrowsingTab = SideTab(true), WhoListingTab = SideTab(false) }
for _, key in ipairs({ "ListingTab", "BrowsingTab", "WhoListingTab" }) do
    local tab = _G.LFGParentFrame[key]
    tab:SetChecked(tab.initiallySelected)
end
_G.LFGListingFrame = {
    RolesSection = rolesSection,
    Inset = listingInset,
    DividerFrame = { Divider = divider },
    ActivityView = activityView,
    CategoryView = { CategoryButtons = { card } },
    BackButton = Button(), PostButton = Button(),
    GroupRoleButtons = { RolePollButton = Button(), RoleDropdown = Button() },
}
_G.LFGBrowseFrame = { BackgroundArt = {}, Bg = {}, BarTop = {}, BarMiddle = {},
    Inset = browseInset, ScrollBox = ScrollBox(), ScrollBar = {}, CategoryDropdown = Button(),
    ActivityDropdown = Button(), RefreshButton = Button(), SendMessageButton = Button(),
    GroupInviteButton = Button(), selectionBehavior = SelectionBehavior() }
_G.LFGWhoListFrame = { BackgroundArt = {}, headerBackground = {}, insideFrame = {},
    BarTop = {}, BarMiddle = {}, FilterDropdown = whoFilter, ScrollBox = ScrollBox(),
    ScrollBar = {}, WhoSearch = Button() }
_G.LFGListingCategorySelection_UpdateCategoryButtons = function() end
_G.LFGBrowseSearchEntry_SetSelection = function(row, selected)
    -- The native selection callback fires after the model has changed.
    _G.LFGBrowseFrame.selectionBehavior.selections[row:GetElementData()] = selected
    row.Selected:SetShown(selected)
end
mockEventFrame.scripts.OnEvent(mockEventFrame, "ADDON_LOADED", "Other")
assert(mockEventFrame.events.ADDON_LOADED and next(frames) == nil)
mockEventFrame.scripts.OnEvent(mockEventFrame, "ADDON_LOADED",
    "Blizzard_GroupFinder_VanillaStyle")
assert(not mockEventFrame.events.ADDON_LOADED)
assert(frames[_G.LFGParentFrame].role == "shell"
    and frames[_G.LFGListingFrame].role == "panel"
    and frames[_G.LFGBrowseFrame].role == "panel"
    and frames[_G.LFGWhoListFrame].role == "panel")
assert(faded[roleArt] and not faded[roleIcon]
    and buttons[card].role == "card" and not faded[cardLabel],
    "decorative LFG art or semantic controls were misidentified")
local browse, who = _G.LFGBrowseFrame, _G.LFGWhoListFrame
for label, region in pairs({
    ["listing inset CustomBG"] = listingInset.CustomBG, ["listing inset Border"] = listingInset.Border,
    ["listing divider"] = divider, ["activity BarTop"] = activityView.BarTop,
    ["activity BarMiddle"] = activityView.BarMiddle, ["browse BackgroundArt"] = browse.BackgroundArt,
    ["browse Bg"] = browse.Bg, ["browse BarTop"] = browse.BarTop, ["browse BarMiddle"] = browse.BarMiddle,
    ["browse inset Border"] = browseInset.Border, ["who BackgroundArt"] = who.BackgroundArt,
    ["who headerBackground"] = who.headerBackground, ["who insideFrame"] = who.insideFrame,
    ["who BarTop"] = who.BarTop, ["who BarMiddle"] = who.BarMiddle,
}) do
    assert(faded[region] == "blizzardWindows:forever-group-finder", "70009 group finder art stayed visible: " .. label)
end
assert(buttons[whoFilter] and buttons[whoFilter].role == "button"
    and buttons[whoFilter].regions[1] == "Background" and not faded[whoFilter],
    "the Who filter dropdown must be skinned as a button, not faded")

-- These exact controls have parentKeys, but the depth-zero panel pass does
-- not visit them. Refresh is recognized by the generic pass; the rest need
-- the Forever adapter. Their semantic Icon regions must remain visible.
for _, control in ipairs({ browse.CategoryDropdown, browse.ActivityDropdown, browse.RefreshButton,
    browse.SendMessageButton, browse.GroupInviteButton, who.WhoSearch,
    _G.LFGListingFrame.BackButton, _G.LFGListingFrame.PostButton,
    _G.LFGListingFrame.GroupRoleButtons.RolePollButton,
    _G.LFGListingFrame.GroupRoleButtons.RoleDropdown, activityView.PlayStyleDropdown, activityView.VoiceChatDropdown }) do
    assert(buttons[control], "Forever browser control stayed unskinned")
    assert(not faded[control.Icon], "a browser action lost its semantic icon")
    assert(faded[control:GetNormalTexture()], "native button chrome covered the browser skin")
end
assert(frames[activityView] and frames[activityView.Comment], "activity controls/comment missed the skin")

-- Mainline LargeSideTabButtonTemplate is a Frame, so ApplyButton cannot
-- decorate it. Keep its icon/mask and take selection from SetChecked.
local browseTab = _G.LFGParentFrame.BrowsingTab
assert(surfaces[browseTab] and surfaces[browseTab].active == true,
    "Forever's Frame-based side tab did not receive its selected surface")
assert(faded[browseTab.Background] and faded[browseTab.SelectedTexture]
    and not faded[browseTab.Icon] and not faded[browseTab.Mask], "side-tab semantic art was changed")
assert(not faded[browseTab.HighlightTexture], "Frame side tab lost native mouseover feedback")
browseTab:SetChecked(false)
assert(surfaces[browseTab].active == false, "side tab selection did not follow Blizzard")

local later = { Icon = {}, Cover = {}, Label = {}, HighlightTexture = {} }
_G.LFGListingFrame.CategoryView.CategoryButtons[2] = later
hooks.LFGListingCategorySelection_UpdateCategoryButtons()
assert(buttons[later] and buttons[later].role == "card",
    "newly created category cards did not receive the skin")
local browseRow = { ResultBG = {}, Selected = Texture(), Highlight = {}, Name = {}, PartyIcon = {},
    DataDisplay = { DelistButton = Button(), Enumerate = { Icon1 = {} } } }
local whoRow = { Background = {}, Selected = Texture(), Name = {}, InviteButton = Button(),
    SetSelected = function(self, selected) self.Selected:SetShown(selected) end }
local grouping = { ResultBG = {}, CategoryLabel = {}, ExpandIcon = {}, CollapseIcon = {}, Highlight = {} }
local activityRow = { NameButton = Button(), CheckButton = {}, ExpandOrCollapseButton = {} }
_G.LFGBrowseFrame.ScrollBox:Initialize(browseRow)
_G.LFGWhoListFrame.ScrollBox:Initialize(whoRow)
_G.LFGBrowseFrame.ScrollBox:Initialize(grouping)
activityView.ScrollBox:Initialize(activityRow)
assert(buttons[browseRow] and buttons[whoRow]
    and not faded[browseRow.PartyIcon], "pooled group finder rows lost semantic content")
assert(buttons[grouping] and not faded[grouping.ExpandIcon] and not faded[grouping.CollapseIcon],
    "the Groups header was not skinned or lost its collapse controls")
assert(buttons[browseRow.DataDisplay.DelistButton] and buttons[whoRow.InviteButton],
    "pooled row action buttons missed the skin")
assert(checked[activityRow], "activity checkboxes were not tracked")
_G.LFGBrowseSearchEntry_SetSelection(browseRow, true)
assert(hooks.LFGBrowseSearchEntry_SetSelection, "browse selection has no native post-hook")
hooks.LFGBrowseSearchEntry_SetSelection(browseRow, true)
whoRow:SetSelected(true)
assert(surfaces[browseRow].active == true and surfaces[whoRow].active == true,
    "skin hid the native selection without retaining selected state")
whoRow:SetSelected(false)
assert(surfaces[whoRow].active == false, "reused Who row retained stale selection")

-- Browse does not reset Selected when a Button is recycled. The selected
-- element A remains in the model while its old Button displays unselected B.
local selectedElement = browseRow:GetElementData()
browse.ScrollBox:Initialize(browseRow, {})
assert(surfaces[browseRow].active == false and browseRow.Selected:IsShown()
    and browse.selectionBehavior.selections[selectedElement] == true,
    "reused browse row took stale Selected art or changed native selection")
browse.ScrollBox:Initialize(browseRow, selectedElement)
assert(surfaces[browseRow].active == true, "selected browse result lost its selection after scrolling back")

-- Rows initialized while locked down must receive their skin after combat.
-- Reapplying visits existing registrations too; registering alone cannot
-- recover a visible row which was skipped by OnInitializedFrame.
local combatRow = { ResultBG = {}, Selected = Texture(), Highlight = {}, Name = {} }
browse.ScrollBox.rows = { browseRow, grouping, combatRow }
who.ScrollBox.rows = { whoRow }
inCombat = true
browse.ScrollBox:Initialize(combatRow)
assert(not buttons[combatRow] and next(deferred), "combat row was painted or never deferred")
inCombat = false
for key, callback in pairs(deferred) do deferred[key] = nil callback() end
assert(buttons[combatRow], "post-combat replay missed an already visible row")
inCombat = true
browseTab:SetChecked(true)
assert(next(deferred) and surfaces[browseTab].active == false, "tab selection painted in combat or was lost")
inCombat = false
for key, callback in pairs(deferred) do deferred[key] = nil callback() end
assert(surfaces[browseTab].active == true, "post-combat replay missed side-tab selection")
assert(adapter.Disable() and next(frames) == nil)
assert(next(_G.LFGBrowseFrame.ScrollBox.callbacks) == nil
    and next(_G.LFGWhoListFrame.ScrollBox.callbacks) == nil
    and next(activityView.ScrollBox.callbacks) == nil,
    "group finder row callbacks survived disable")
buttons[later] = nil
hooks.LFGListingCategorySelection_UpdateCategoryButtons()
assert(buttons[later] == nil, "disabled skin repainted a card")
local disabledActive = surfaces[browseTab].active
browseTab:SetChecked(false)
assert(surfaces[browseTab].active == disabledActive and surfaces[browseTab].visible == false,
    "disabled side tab repainted or left its surface visible")
assert(adapter.Apply(), "re-enable failed")
assert(buttons[combatRow] and surfaces[browseTab].visible == true,
    "re-enable did not replay already visible rows/tabs")
adapter.Disable()
-- Older Forever builds omit the voice selector; the remaining controls still skin.
activityView.VoiceChatDropdown = nil
assert(adapter.Apply() and buttons[activityView.PlayStyleDropdown],
    "an older listing without a voice selector did not skin")
adapter.Disable()

-- A queued apply/repaint must not revive the adapter after disable.
inCombat = true
assert(adapter.Apply() and next(deferred), "combat Apply was not queued")
adapter.Disable()
assert(next(deferred) == nil and not adapter.active, "disable retained queued group finder paint")
inCombat = false

categoryEnabled = false
assert(adapter.Apply() and not mockEventFrame.events.ADDON_LOADED)

-- Retail has no Blizzard_GroupFinder_VanillaStyle: the client guard is the
-- only one, and it keeps the adapter off.
categoryEnabled = true
namespace.Client.isForever = false
local retailApplied, retailState = adapter.Apply()
assert(retailApplied and retailState == "disabled" and not adapter.active
    and not mockEventFrame.events.ADDON_LOADED, "the Forever group finder skin ran on Retail")
print("Forever group finder load, cards, semantic art, and disable passed")
