local root = assert(arg[1], "Suite root required")
local events, hooks, frames, buttons, faded = {}, {}, {}, {}, {}
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
    function box:Initialize(row)
        for _, callback in pairs(self.callbacks) do callback(nil, row) end
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
function hooksecurefunc(name, callback)
    assert(hooks[name] == nil, "duplicate group finder hook")
    hooks[name] = callback
end

local namespace = {
    Client = { isForever = true, HasAddOn = function(name)
        assert(name == "Blizzard_GroupFinder_VanillaStyle")
        return true
    end },
    IsCombatLocked = function() return false end,
    Safety = {
        CanCreateRegions = function() return true end,
        CanDecorate = function() return true end,
    },
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
            buttons[button] = { owner = owner, role = spec.role, regions = spec.regions }
        end,
        ApplyTab = function(tab, owner, spec)
            buttons[tab] = { owner = owner, role = spec.role }
        end,
    },
    Cosmetics = {
        Fade = function(region, owner) faded[region] = owner end,
        FadeNineSlice = function() end,
    },
    CombatGate = { Cancel = function() end },
}

assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/ForeverGroupFinder.lua"))(
    "MSUF_Suite_Skin", namespace)
local adapter = assert(namespace.ForeverGroupFinder)
local applied, state = adapter.Apply()
assert(applied and state == "waiting" and mockEventFrame.events.ADDON_LOADED)

local roleArt, roleIcon, cardArt, cardLabel = {}, {}, {}, {}
local card = { Icon = cardArt, Cover = {}, Label = cardLabel,
    SelectedTexture = {}, HighlightTexture = {} }
_G.LFGParentFrame = { Tab1 = {}, Tab2 = {}, Tab3 = {},
    ListingTab = {}, BrowsingTab = {}, WhoListingTab = {} }
_G.LFGListingFrame = {
    RolesSection = { RoleBackground = roleArt, RoleIcon = roleIcon },
    Inset = { CustomBG = {} },
    CategoryView = { CategoryButtons = { card } },
}
_G.LFGBrowseFrame = { BackgroundArt = {}, Inset = { CustomBG = {} }, ScrollBox = ScrollBox() }
_G.LFGWhoListFrame = { headerBackground = {}, insideFrame = {}, ScrollBox = ScrollBox() }
_G.LFGListingCategorySelection_UpdateCategoryButtons = function() end
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

local later = { Icon = {}, Cover = {}, Label = {},
    SelectedTexture = {}, HighlightTexture = {} }
_G.LFGListingFrame.CategoryView.CategoryButtons[2] = later
hooks.LFGListingCategorySelection_UpdateCategoryButtons()
assert(buttons[later] and buttons[later].role == "card",
    "newly created category cards did not receive the skin")
local browseRow = { ResultBG = {}, Selected = {}, Highlight = {}, Name = {}, PartyIcon = {} }
local whoRow = { Background = {}, Selected = {}, Name = {} }
_G.LFGBrowseFrame.ScrollBox:Initialize(browseRow)
_G.LFGWhoListFrame.ScrollBox:Initialize(whoRow)
assert(buttons[browseRow] and buttons[whoRow]
    and not faded[browseRow.PartyIcon], "pooled group finder rows lost semantic content")
assert(adapter.Disable() and next(frames) == nil)
assert(next(_G.LFGBrowseFrame.ScrollBox.callbacks) == nil
    and next(_G.LFGWhoListFrame.ScrollBox.callbacks) == nil,
    "group finder row callbacks survived disable")
buttons[later] = nil
hooks.LFGListingCategorySelection_UpdateCategoryButtons()
assert(buttons[later] == nil, "disabled skin repainted a card")

categoryEnabled = false
assert(adapter.Apply() and not mockEventFrame.events.ADDON_LOADED)
print("Forever group finder load, cards, semantic art, and disable passed")
