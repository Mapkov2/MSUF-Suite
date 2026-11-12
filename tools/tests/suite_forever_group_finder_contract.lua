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

local bezelFrames = {}
function CreateFrame(_, _, parent)
    local frame = { events = {}, scripts = {}, shown = true }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(name, script) self.scripts[name] = script end
    -- Owned child frames (portrait bezels) are parented after creation.
    assert(parent == nil, "an owned frame was created with a parent (Forever SmartNavigation hook)")
    function frame:SetParent(newParent) self.parent = newParent; bezelFrames[#bezelFrames + 1] = self end
    function frame:SetFrameLevel(level) self.level = level end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:CreateTexture()
        local texture = { anchors = {} }
        function texture:SetTexture(path) self.path = path end
        function texture:SetDesaturated(value) self.desaturated = value end
        function texture:SetVertexColor(r, g, b) self.color = { r, g, b } end
        function texture:ClearAllPoints() self.anchors = {} end
        function texture:SetPoint(_, relative) self.anchors[#self.anchors + 1] = relative end
        self.ring = texture
        return texture
    end
    -- The adapter's own event frame is the first frame created at load.
    mockEventFrame = mockEventFrame or frame
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
            assert(not inCombat or not (button.IsProtected and button:IsProtected()), "protected button paint during combat")
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
            assert(not inCombat or not (frame.IsProtected and frame:IsProtected()), "protected surface paint during combat")
            local function Region()
                local region = { anchors = {} }
                function region:ClearAllPoints() self.anchors = {} end
                function region:SetPoint(_, relative) self.anchors[#self.anchors + 1] = relative end
                function region:SetDrawLayer(layer) self.layer = layer end
                return region
            end
            surfaces[frame] = { spec = spec, visible = true, fill = Region(), edge = Region() }
            return surfaces[frame]
        end,
        SetActive = function(frame, active)
            assert(not inCombat or not (frame.IsProtected and frame:IsProtected()), "protected selection paint during combat")
            assert(surfaces[frame], "selection has no surface")
            surfaces[frame].active = active
        end,
        SetVisible = function(frame, visible)
            if surfaces[frame] then surfaces[frame].visible = visible end
        end,
    },
    Checkmarks = { TrackFrame = function(frame) checked[frame] = true end },
    Registry = { AddListener = function() end },
    Theme = { GetColor = function() return 0.25, 0.5, 0.75, 1 end },
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
    GroupRoleButtons = { RolePollButton = Button(), RoleDropdown = Button(), RoleIcon = Button() },
    SoloRoleButtons = { RoleButtons = { Button(), Button(), Button() } },
    NewPlayerFriendlyButton = Button(),
}
-- Owned icon textures the adapter creates on the role buttons.
local function CreateOwnedTexture(self)
    local texture = { owner = self }
    function texture:SetPoint() end
    function texture:SetAtlas(atlas) self.atlas = atlas end
    function texture:SetSize(width) self.size = width end
    function texture:Show() self.visible = true end
    function texture:Hide() self.visible = false end
    self.ownedTextures = (self.ownedTextures or 0) + 1
    return texture
end
for index, role in ipairs(_G.LFGListingFrame.SoloRoleButtons.RoleButtons) do
    role.CheckButton, role.cover = {}, {}
    role.roleID = ({ "TANK", "HEALER", "DAMAGER" })[index]
    role.CreateTexture = CreateOwnedTexture
end
local newPlayerButton = _G.LFGListingFrame.NewPlayerFriendlyButton
local newcomerBadge = Texture("newplayerchat-chaticon-newcomer")
newPlayerButton.CheckButton, newPlayerButton.CreateTexture = {}, CreateOwnedTexture
newPlayerButton.GetRegions = function(self) return newcomerBadge, adapter.flatIcons[self] end
_G.LFGBrowseFrame = { BackgroundArt = {}, Bg = {}, BarTop = {}, BarMiddle = {},
    Inset = browseInset, ScrollBox = ScrollBox(), ScrollBar = {}, CategoryDropdown = Button(),
    ActivityDropdown = Button(), RefreshButton = Button(), SendMessageButton = Button(),
    GroupInviteButton = Button(), selectionBehavior = SelectionBehavior() }
_G.LFGWhoListFrame = { BackgroundArt = {}, headerBackground = {}, insideFrame = {},
    BarTop = {}, BarMiddle = {}, FilterDropdown = whoFilter, ScrollBox = ScrollBox(),
    ScrollBar = {}, WhoSearch = Button() }
-- The big eye portrait (LFGEyeBigTemplate) bakes a stone ring into its art.
_G.LFGParentFramePortrait = { GetFrameLevel = function() return 5 end }
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
-- Role buttons: the coloured halo is decoration; the role icon (normal
-- texture) and the not-recommended cover carry meaning. Role checkboxes and
-- the new-player checkbox take the window's checkmark colours.
local listingFrame = _G.LFGListingFrame
local flatIcons = adapter.flatIcons
local expectedAtlas = { TANK = "groupfinder-icon-role-large-tank", HEALER = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps" }
for _, role in ipairs(listingFrame.SoloRoleButtons.RoleButtons) do
    assert(faded[role.Background] == "blizzardWindows:forever-group-finder", "role halo stayed visible")
    -- The ringed, glowing native icon is replaced by the flat role icon;
    -- the not-recommended cover stays native.
    local icon = flatIcons[role]
    assert(icon and icon.atlas == expectedAtlas[role.roleID] and icon.visible, "role kept its ringed native icon")
    assert(faded[role:GetNormalTexture()] and not faded[role.cover], "role icon or cover handled wrongly")
    assert(checked[role], "role checkbox kept Blizzard's yellow check")
end
assert(faded[listingFrame.GroupRoleButtons.RoleIcon.Background], "group role halo stayed visible")
local newcomerIcon = flatIcons[newPlayerButton]
assert(newcomerIcon and newcomerIcon.atlas == "newplayerchat-chaticon-newcomer" and newcomerIcon.visible
    and faded[newPlayerButton:GetNormalTexture()] and faded[newcomerBadge] and not faded[newcomerIcon],
    "New Player Friendly kept its ringed flag or faded its own icon")
assert(checked[newPlayerButton.CheckButton], "new-player checkbox kept Blizzard's check")
-- The eye gets an owned bezel above it: theme-tinted ring, nothing written to the eye.
local eye = _G.LFGParentFramePortrait
local bezel = bezelFrames[1]
assert(bezel and bezel.parent == eye and bezel.level == 13 and bezel.ring.desaturated
    and bezel.ring.anchors[1] == eye and bezel.ring.color[1] == 0.25 and bezel.shown,
    "the Group Finder eye kept its stone ring instead of the owned bezel")
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
-- The Legacy tab tile: fitted to the icon (the frame keeps the art's right
-- padding), edge above the icon, selection drawn on the edge.
local tabSurface = surfaces[browseTab]
assert(tabSurface.spec.selectionEdge and tabSurface.spec.radius == 6
    and tabSurface.fill.anchors[1] == browseTab.Icon and tabSurface.edge.anchors[2] == browseTab.Icon
    and tabSurface.edge.layer == "OVERLAY", "Forever side tab tile is not fitted to its icon like the Legacy tabs")
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
local protectedRow = { ResultBG = {}, Selected = Texture(), Highlight = {}, Name = {} }
function protectedRow:IsProtected() return true, false end
browse.ScrollBox.rows = { browseRow, grouping, combatRow, protectedRow }
who.ScrollBox.rows = { whoRow }
inCombat = true
browse.ScrollBox:Initialize(combatRow)
assert(buttons[combatRow] and next(deferred) == nil, "safe combat row waited or scheduled a replay")
browse.ScrollBox:Initialize(protectedRow)
assert(not buttons[protectedRow] and next(deferred), "protected row was painted or never deferred")
inCombat = false
for key, callback in pairs(deferred) do deferred[key] = nil callback() end
assert(buttons[protectedRow], "post-combat replay missed an already visible protected row")
protectedRow.IsProtected = nil
inCombat = true
browseTab:SetChecked(true)
assert(not next(deferred) and surfaces[browseTab].active == true, "safe tab selection waited until combat ended")
inCombat = false
for key, callback in pairs(deferred) do deferred[key] = nil callback() end
assert(surfaces[browseTab].active == true, "post-combat replay missed side-tab selection")
assert(adapter.Disable() and next(frames) == nil)
for _, icon in pairs(adapter.flatIcons) do assert(icon.visible == false, "disable left a flat role icon visible") end
assert(bezelFrames[1].shown == false, "disable left the eye bezel visible")
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
assert(adapter.Apply() and frames[LFGParentFrame] and next(deferred) == nil,
    "cold unprotected LFG chrome waited until combat ended")
adapter.Disable()
function LFGParentFrame:IsProtected() return true, false end
assert(adapter.Apply() and next(deferred), "combat Apply was not queued")
adapter.Disable()
assert(next(deferred) == nil and not adapter.active, "disable retained queued group finder paint")
LFGParentFrame.IsProtected = nil
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
