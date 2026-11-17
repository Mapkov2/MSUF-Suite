local root = assert(arg[1])
local skin = root .. "/MSUF_Suite_Skin/"
local function Load(name, ns)
    assert(loadfile(skin .. name))("MSUF_Suite_Skin", ns)
end

local jobs = {}
local combat = false
local function Flush()
    while next(jobs) do
        local pending = jobs
        jobs = {}
        for job in pairs(pending) do job() end
    end
end

local ns = {
    DB = { enabled = true, typography = { enabled = true } },
    IsCombatLocked = function() return combat end,
    Registry = {
        QueueJob = function(job) jobs[job] = true end,
        AddListener = function() end,
    },
    Typography = {
        GetSelection = function() return "font" end,
        GetSelectionPath = function() return "Fonts\\Suite.ttf" end,
    },
}
local function Method(target, name)
    return type(target) == "table" and not target.forbidden and type(target[name]) == "function"
end
local function Call(target, name, ...)
    if Method(target, name) then return target[name](target, ...) end
end
ns.Safety = {
    Public = function(value) return value ~= "secret" end,
    CanDecorate = function(target) return type(target) == "table" and not target.forbidden end,
    IsCompositorManaged = function(target) return target and target.compositor end,
    HasMethod = Method,
    Call = Call,
    Read = Call,
    Invoke = Call,
    Field = function(target, key) return type(target) == "table" and target[key] end,
    ReadColor = Call,
    Isolated = function(callback) return callback end,
}

local writes, fonts, checks = 0, 0, 0
local function Check(ok, message)
    assert(ok, message)
    checks = checks + 1
end

local function Font(path)
    local font = { path = path, size = 12, flags = "" }
    function font:GetFont() return self.path, self.size, self.flags end
    function font:SetFont(nextPath, size, flags)
        self.path, self.size, self.flags = nextPath, size, flags
        -- SimpleFont:SetFont has no return value.
    end
    return font
end

CreateFont = function()
    fonts = fonts + 1
    return Font()
end

local default = Font("Fonts\\Native.ttf")
local function Label(text)
    local label = { text = text, font = default }
    function label:GetObjectType() return "FontString" end
    function label:GetFont() return self.font:GetFont() end
    function label:GetFontObject() return self.font end
    function label:SetFontObject(font) writes = writes + 1 self.font = font end
    function label:GetText() return self.text end
    function label:GetTextColor() return 1, 1, 1, 1 end
    function label:SetTextColor() end
    function label:SetFont(path, size, flags)
        self.font = Font(path)
        self.font:SetFont(path, size, flags)
        return true
    end
    return label
end

local function Frame()
    local frame = { visible = true }
    function frame:IsShown() return self.visible end
    function frame:IsVisible() return self.visible end
    function frame:GetChildren() return unpack(self.children or {}) end
    function frame:GetRegions() return unpack(self.regions or {}) end
    return frame
end

local function Description()
    local description = {}
    function description:AddMenuResponseCallback(callback) self.response = callback end
    function description:AddMenuAcquiredCallback(callback) self.acquired = callback end
    function description:AddMenuReleasedCallback(callback) self.released = callback end
    return description
end

local painted = {}
ns.BlizzardYellow = { TrackMenuSelection = function(row) painted[row] = (painted[row] or 0) + 1 end }
ns.Checkmarks = { TrackFrame = function() end }
ScrollBoxListMixin = { Event = { OnInitializedFrame = "initialized" } }

Load("Core/LabelStyle.lua", ns)
Load("Core/NativeMenuRows.lua", ns)
local dropdown = { description = Description() }
function dropdown:GetMenuDescription() return self.description end
local menu, wrapper, row = Frame(), Frame(), Frame()
local label = Label("\237\149\156\234\181\173\236\150\180")
row.regions = { label }
local scroll = Frame()
menu.ScrollBox = scroll
function scroll:RegisterCallback(_, fn, owner) self.initialized, self.owner = fn, owner end
function scroll:UnregisterCallback(_, owner)
    if owner == self.owner then self.initialized, self.owner = nil, nil end
end
function scroll:ForEachFrame(fn) fn(wrapper, row) end
local menus = ns.NativeMenuRows
Check(menus.Track(dropdown, menu, "menus"), "expected native menu response")
Check(writes == 0, "open callback did visual work synchronously")
Flush()
Check(label.font.path == "Fonts\\2002.TTF" and fonts == 1, "menu language fallback did not apply")
Check(painted[row] and not painted[wrapper], "scroll wrapper was mistaken for its native menu row")

local before = writes
dropdown.description.response()
dropdown.description.response()
Flush()
Check(writes == before, "unchanged rows wrote their font again")

local extra, extraLabel = Frame(), Label("Newly scrolled row")
extra.regions = { extraLabel }
scroll.initialized(scroll.owner, wrapper, extra)
Check(extraLabel.font == default, "ScrollBox callback painted synchronously")
Flush()
Check(extraLabel.font.path == "Fonts\\Suite.ttf" and painted[extra], "new pooled row lost its style")

local old = dropdown.description
dropdown.description = Description()
old.response()
Flush()
Check(dropdown.description.response ~= nil, "description regeneration lost its callback")
label.font = default
dropdown.description.response()
Flush()
Check(label.font.path == "Fonts\\2002.TTF", "response did not restore the native menu's selected font")

local child, childRow, childLabel = Frame(), Frame(), Label("Child row")
childRow.regions, child.children = { childLabel }, { childRow }
dropdown.description.acquired(child)
Flush()
Check(childLabel.font.path == "Fonts\\Suite.ttf", "submenu was not styled")
child.visible = false
dropdown.description.released(child)
Flush()

combat = true
label.font = default
dropdown.description.response()
Flush()
Check(label.font == default, "response wrote a font during combat")
combat = false
dropdown.description.response()
Flush()
Check(label.font.path == "Fonts\\2002.TTF", "out-of-combat response did not recover")
menus.Close(dropdown, true)
Flush()
Check(label.font == default and not scroll.initialized, "disable failed to restore the open menu")

local owned = Label("Addon label")
ns.LabelStyle.Apply(owned, "thirdParty")
Check(owned.font.path == "Fonts\\Suite.ttf", "registered label did not follow the skin")
ns.LabelStyle.Release(owned, "thirdParty")
Check(owned.font.path == "Fonts\\Native.ttf", "registered label did not restore")

Load("Rendering/CaptionTitles.lua", ns)
local frame, container = Frame(), Frame()
frame.TitleContainer = container
local offset = -24
function container:GetNumPoints() return 1 end
function container:GetPoint() return "TOPRIGHT", frame, "TOPRIGHT", offset, -1 end
function container:GetEffectiveScale() return 1 end
function container:GetLeft() return 60 end
function container:SetPoint(_, _, _, x) offset = x end
local caption = { frame = frame }
ns.CaptionTitles.Fit(caption, 223, 300, 1)
Check(offset == -24, "caption resized before native layout settled")
Flush()
Check(offset == -83, "title covered a visible header button")
ns.CaptionTitles.Restore(caption)
Check(offset == -24, "title's original anchor did not restore")
ns.CaptionTitles.Fit(caption, 223, 300, 1)
ns.CaptionTitles.Restore(caption)
Flush()
Check(offset == -24, "queued fit changed an already released caption")
function owned:GetParent() return { compositor = true } end
Check(not ns.LabelStyle.CanStyle(owned), "public API accepted a compositor-managed font string")

local pointer = Frame()
pointer.Content = Frame()
local shown = { NextID = 1, InUseFrames = {} }
function shown:Show()
    self.InUseFrames[self.NextID] = pointer
    self.NextID = self.NextID + 1
end
TutorialPointerFrame = shown
local applied = 0
ns.GenericWindows = {
    IsCategoryEnabled = function() return true end,
    Disable = function() end,
    ApplyFrame = function(content, _, mode)
        assert(content == pointer.Content and mode.motion == false)
        applied = applied + 1
    end,
}
ns.BlizzardYellow.TrackFrame = function() end
ns.AdapterKit = {
    HookFunction = function(target, name, callback)
        local original = target[name]
        target[name] = function(self, ...) original(self, ...) callback(self, ...) end
        return true
    end,
    ForEachRegion = function() end,
}
Load("Adapters/TutorialPointers.lua", ns)
ns.TutorialPointers.Enable()
shown:Show()
shown:Show()
Check(applied == 0, "tutorial art was applied during Blizzard's show")
Flush()
Check(applied == 1, "tutorial pointer reuse did not coalesce")
ns.TutorialPointers.Disable()
shown:Show()
Flush()
Check(applied == 1, "disabled tutorial continued painting")

print("Suite skin polish: " .. checks .. " checks")
