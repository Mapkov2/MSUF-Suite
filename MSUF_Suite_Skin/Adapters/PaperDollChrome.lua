local _, NS = ...

-- Shared by CharacterPanel and InspectPanel (both load after this file):
-- per-owner state and combat deferral (an AdapterKit owner registry),
-- waiting for the load-on-demand window addon, and the decorative primitives
-- both PaperDoll windows use.
local Safety = NS.Safety
local Field, Read, Public = Safety.Field, Safety.Read, Safety.Public
local Dispatch = Safety.Dispatch
local Kit = NS.AdapterKit

local Chrome = {}
Chrome.__index = Chrome
NS.PaperDollChrome = Chrome

-- Surface specs are shared per call site; Surface.Attach stores, never edits them.
function Chrome.Spec(role, radius, inset, listItem, activeRole)
    return Kit.SurfaceSpec(role, radius, inset, listItem, nil, nil, activeRole)
end

local SLOT_SPEC = Chrome.Spec("button", 4, 0, true)
local INSET_SPEC = Chrome.Spec("panel", 5, 0)
local WINDOW_SPEC = Chrome.Spec("shell", 8, 0)
local ACTION_SPEC = NS.ControlSkin.MarkFixedButtonSpec({
    role = "button", radius = 5, inset = 1, useControlShape = true, pillHeight = 24, allowImplicitProtected = true,
}, true)
local TAB_SPECS = {}
for _, active in ipairs({ "selected", "idle", "native" }) do
    local spec = {
        role = "navigation", activeRole = "navigationActive", selectionEdge = true,
        radius = 5, inset = 1, useControlShape = true, pillHeight = 24, allowImplicitProtected = true,
    }
    if active ~= "native" then spec.active = active == "selected" end
    TAB_SPECS[active] = NS.ControlSkin.MarkFixedButtonSpec(spec, active ~= "native")
end
local headers = setmetatable({}, { __mode = "k" })
local watchingTheme

local function PaintHeader(header)
    local r, g, b, alpha = NS.Theme.GetColor("accent")
    header.rule:SetColorTexture(r, g, b, alpha * .36)
    local pr, pg, pb, pa = NS.Theme.GetColor("microBarFill")
    header.fill:SetColorTexture(pr, pg, pb, pa * .85)
end

local function ShowHeader(root, header)
    local geometry = NS.DB and NS.DB.geometry
    local round = geometry and geometry.roundWindows == true
    local shown = not header.prepared
    local suite = (round or header.roundedMask) and NS.SuiteCore and NS.SuiteCore()
    local skin = suite and suite.Skin
    if skin and skin.MaskOwnedWindow then
        local rounded = shown and round and skin.GetRoundedWindowGeometry() or nil
        header.roundedMask = skin.MaskOwnedWindow(root, header.roundedMask, rounded, header.fill)
    end
    local showFill = shown and (not round or header.roundedMask and header.roundedMask.active == true) or false
    if header.fillShown ~= showFill then
        header.fillShown = showFill
        if showFill then header.fill:Show() else header.fill:Hide() end
    end
    if header.ruleShown ~= shown then
        header.ruleShown = shown
        if shown then header.rule:Show() else header.rule:Hide() end
    end
end

local function RefreshHeaders()
    for root, header in pairs(headers) do
        if header.owner and Safety.CanDecorate(root, not NS.IsCombatLocked()) then
            PaintHeader(header)
            ShowHeader(root, header)
        end
    end
end

local function OnTheme(_, domain, key)
    local headerColor = domain == "color" and (key == "accent" or key == "microBarFill")
    if headerColor or domain == "theme" or domain == "profile" or domain == "appearance" or domain == "geometry" then
        NS.CombatGate.RunOrDefer("paper-doll-header-colors", RefreshHeaders)
    end
end

local function Band(root, layer, height, y)
    local region = root:CreateTexture(nil, layer, nil, -3)
    region:SetPoint("TOPLEFT", root, "TOPLEFT", 2, y)
    region:SetPoint("TOPRIGHT", root, "TOPRIGHT", -2, y)
    region:SetHeight(height)
    return region
end

function Chrome.Window(state, root, prepare)
    if not Kit.Ensure(state, root, WINDOW_SPEC, prepare) then return end
    state.preparedWindow = prepare and root or nil
    if not Safety.HasMethod(root, "GetFrameLevel") then return end
    local header = headers[root]
    if header and header.owner == state then
        if header.prepared and not prepare then
            header.prepared = nil
            ShowHeader(root, header)
        end
        return
    end
    if not header then
        header = { fill = Band(root, "BACKGROUND", 25, -2), rule = Band(root, "ARTWORK", 1, -27) }
        headers[root] = header
    end
    header.owner, state.headerRoot = state, root
    PaintHeader(header)
    header.prepared = prepare
    ShowHeader(root, header)
    if not watchingTheme then
        watchingTheme = true
        NS.Registry.AddListener(headers, OnTheme)
    end
end

function Chrome.PaintBadge(badge, info)
    local path = Kit.FontPath()
    if path ~= badge.path then
        if badge.text:SetFont(path, 11, "") == false then
            local fallback = Kit.DEFAULT_FONT
            local existing = Safety.Read(badge.text, "GetFont")
            if not existing and fallback and path ~= fallback then
                badge.text:SetFont(fallback, 11, "")
            end
        end
        badge.path = path
    end
    local color = info and info.quality and ITEM_QUALITY_COLORS[info.quality]
    if color then
        badge.text:SetTextColor(color.r, color.g, color.b, 1)
    else
        badge.text:SetTextColor(NS.Theme.GetColor("text"))
    end
    local r, g, b = NS.Theme.GetColor("ink")
    badge.fill:SetColorTexture(r, g, b, .88)
end

function Chrome.UpdateBadge(row, slot, info)
    local badge = row.levelBadge
    if not info or not info.itemLevel then
        if badge and Safety.CanDecorate(badge.frame, not NS.IsCombatLocked()) then badge.frame:Hide() end
        return
    end
    if not badge then
        local frame = NS.Safety.CreateChildFrame("Frame", slot)
        frame:SetSize(27, 13)
        frame:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -1, -1)
        frame:SetFrameLevel(slot:GetFrameLevel() + 2)
        frame:EnableMouse(false)
        local fill = frame:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        badge = { frame = frame, fill = fill, text = text }
        row.levelBadge = badge
    end
    if not Safety.CanDecorate(badge.frame, not NS.IsCombatLocked()) then return end
    Chrome.PaintBadge(badge, info)
    if badge.level ~= info.itemLevel then
        badge.text:SetText(string.format("%d", info.itemLevel))
        badge.level = info.itemLevel
    end
    badge.frame:Show()
end

function Chrome.Action(state, button)
    return Kit.SkinControl(state, button, ACTION_SPEC)
end

function Chrome.PanelTabs(state, root, ...)
    local selected = Kit.ReadValues(PanelTemplates_GetSelectedTab, root)
    for index = 1, select("#", ...) do
        local tab = select(index, ...)
        local active = selected == nil and "native" or selected == index and "selected" or "idle"
        Kit.SkinControl(state, tab, TAB_SPECS[active], "ApplyPanelTab")
    end
end

-- The owner state is the kit's skin context ({ owner, surfaces }), so the
-- kit's gated primitives serve it directly.
Chrome.Track = Kit.Track
Chrome.Fade = Kit.Fade

function Chrome.FadeNineSlice(state, target)
    return Kit.FadeNineSlice(state, Field(target, "NineSlice"))
end

-- ensure: the caller is a native update hook (slot or stats update), so a
-- surface that already shows spec and is current is left alone.
function Chrome.Attach(state, target, spec, ensure)
    if ensure then return Kit.Ensure(state, target, spec) end
    return Kit.Attach(state, target, spec)
end

function Chrome.SkinInset(state, inset)
    if not inset then return false end
    Chrome.FadeNineSlice(state, inset)
    Chrome.Fade(state, Field(inset, "Bg"))
    Chrome.Fade(state, Field(inset, "Background"))
    return Chrome.Attach(state, inset, INSET_SPEC)
end

-- The window portrait lives under several names across clients.
function Chrome.FadePortraits(state, root, globalPortrait)
    Chrome.Fade(state, globalPortrait)
    Chrome.Fade(state, Field(root, "Portrait"))
    Chrome.Fade(state, Field(root, "portrait"))
    local container = Field(root, "PortraitContainer")
    Chrome.Fade(state, Field(container, "Portrait"))
    Chrome.Fade(state, Field(container, "portrait"))
end

-- Pass keys (Chrome:RepeatedPass) hold only readable values; nil means an
-- input could not be read, and such a pass always runs.
-- Mode tabs: the selection, the tab-row mode (Gamepad UI, Glass look),
-- combat and the root width (Expand and Collapse resize it between passes).
function Chrome.ModeTabKey(root)
    local selected = Field(root, "selectedTab")
    if not Public(selected) then return nil end
    if selected == nil then selected = 0 end
    local width = Read(root, "GetWidth")
    if type(selected) ~= "number" or selected < 0 or selected >= 16
        or type(width) ~= "number" then return nil end
    local look = NS.DB and NS.DB.theme and NS.DB.theme.look == "foreverGlass"
    return selected + (NS.Client.IsGamepadUI() and 16 or 0) + (look and 32 or 0)
        + (NS.IsCombatLocked() and 64 or 0) + 128 * math.floor(width)
end

-- A sidebar tab is active when checked or, with an unreadable checked
-- state, while its Hider is hidden. CharacterPanel paints by this rule.
function Chrome.SidebarActive(tab)
    local checked = Read(tab, "GetChecked")
    if checked ~= nil then return checked == true end
    local shown = Read(Field(tab, "Hider"), "IsShown")
    return shown ~= nil and shown ~= true
end

-- Sidebar: per tab its active, shown and enabled state, the tab count, the
-- equipment manager pane (its UIPanelButtons reset their art on show) and combat.
function Chrome.SidebarKey(count, tabAt)
    if count > 8 then return nil end
    local key = count
    for index = 1, count do
        local tab = tabAt(index)
        key = key * 8 + (tab and Chrome.SidebarActive(tab) and 1 or 0)
            + (Read(tab, "IsShown") == true and 2 or 0) + (Read(tab, "IsEnabled") == true and 4 or 0)
    end
    local pane = Field(PaperDollFrame, "EquipmentManagerPane")
    return key * 4 + (Read(pane, "IsShown") == true and 1 or 0) + (NS.IsCombatLocked() and 2 or 0)
end

-- config: prefix (deferral keys), addon, rootName, slotNames, applyNow(state),
-- applyOrWait(state) (applies once the root exists, else waits for the addon),
-- optional initState(state) and slotIcon(slot) fallback.
function Chrome.New(config)
    config.registry = Kit.NewOwners({
        prefix = config.prefix, surfaces = true, isolate = true, init = config.initState,
    })
    config.owners = config.registry.owners
    config.exactSlots = Kit.WeakSet()
    config.waiting = false
    config.passes = {}
    return setmetatable(config, Chrome)
end

-- Blizzard repeats one refresh up to three times in a frame (an opening runs
-- Expand twice), and GetTime() is constant within a frame. True when this
-- suffix already ran this frame with the same key: the first pass stays
-- synchronous, a changed input or the next frame runs in full.
function Chrome:RepeatedPass(suffix, key)
    if key == nil then return false end
    local now, pass = GetTime(), self.passes[suffix]
    if pass and pass.time == now and pass.key == key then return true end
    if not pass then
        pass = {}
        self.passes[suffix] = pass
    end
    pass.time, pass.key = now, key
    return false
end

function Chrome:ForgetPasses()
    for _, pass in pairs(self.passes) do pass.time = nil end
end

function Chrome:OwnerState(owner)
    return (self.registry.State(owner))
end

-- Runs callback(state) now, or once after combat (the kit's registry: one
-- cached job per owner and suffix). The callers are Blizzard's PaperDoll
-- post-hooks: each pass is its own error boundary (isolate), so a raising
-- pass never reaches Blizzard's caller.
function Chrome:RunOrDefer(state, suffix, callback)
    return self.registry.RunOrDefer(state, suffix, callback)
end

function Chrome:ForActiveOwners(suffix, callback)
    for _, state in pairs(self.owners) do
        if state.active then self:RunOrDefer(state, suffix, callback) end
    end
end

local function Root(self) return _G[self.rootName] end

local function VisibleRoot(self)
    local root = Root(self)
    return root and not Safety.IsForbidden(root) and Safety.Read(root, "IsVisible") ~= false
        and Safety.Read(root, "IsShown") ~= false
end

-- The Suite geometry owns the Character slots' art: their updates paint nothing.
local function SuiteOwnsSlots(self)
    return self.rootName == "CharacterFrame" and NS.GearGeometry.Owns(Root(self))
end

function Chrome:SkinSlot(state, slot)
    if not state.active or not slot or not self.exactSlots[slot] or SuiteOwnsSlots(self) or not VisibleRoot(self) then return false end
    local combat = NS.IsCombatLocked()
    if combat and not self.safeCombatApply or not Safety.CanCreateRegions(slot, not combat) then
        if combat then self:RunOrDefer(state, "slots", self.skinAllSlots) end
        return false
    end
    local icon = Field(slot, "Icon") or Field(slot, "icon")
        or (self.slotIcon and self.slotIcon(slot))
    local border = Field(slot, "IconBorder") or Field(slot, "iconBorder")
    if icon and not Safety.CanDecorate(icon, not combat) or border and not Safety.CanDecorate(border, not combat) then
        if combat then self:RunOrDefer(state, "slots", self.skinAllSlots) end
        return false
    end
    Chrome.Attach(state, slot, SLOT_SPEC, true)
    if icon and border then
        -- The kit's scratch spec: slot updates allocate no table.
        Kit.SkinItemIcon(slot, state.owner, icon, border, not combat)
    end
    return true
end

function Chrome:SkinAllSlots(state)
    if not state.active or not VisibleRoot(self) or NS.IsCombatLocked() and not self.safeCombatApply then return false end
    local applied = false
    for index = 1, #self.slotNames do
        local name = self.slotNames[index]
        local slot = _G[name]
        if slot then
            self.exactSlots[slot] = true
            Chrome.Fade(state, _G[name .. "Frame"])
            applied = self:SkinSlot(state, slot) or applied
        end
    end
    return applied
end

-- Safe visible slots repaint immediately. Protected targets share one cached
-- completion after combat; closed windows never enter a per-slot pass.
function Chrome:RefreshSlot(slot)
    if not self.exactSlots[slot] or SuiteOwnsSlots(self) or not VisibleRoot(self) then return end
    for _, state in pairs(self.owners) do
        if state.active then Dispatch(Chrome.SkinSlot, self, state, slot) end
    end
end

function Chrome:ApplyForActiveOwners()
    self:ForActiveOwners("apply", self.applyOrWait)
end

-- True while waiting for the window addon to load.
function Chrome:ScheduleLoad()
    if self.waiting then return true end
    if NS.Client.IsAddOnLoaded(self.addon) then return false end
    self.waiting = true
    EventUtil.ContinueOnAddOnLoaded(self.addon, function()
        self.waiting = false
        self:ApplyForActiveOwners()
    end)
    return true
end

local function CategoryEnabled()
    return NS.GenericWindows.IsCategoryEnabled("character")
end

function Chrome:Activate(owner)
    if not CategoryEnabled() then return true, "disabled" end
    local state = self:OwnerState(owner)
    state.active = true
    if NS.IsCombatLocked() then
        -- Full completion still owns optional integrations and protected descendants.
        self:RunOrDefer(state, "apply", self.applyOrWait)
        if not self.safeCombatApply or not Safety.CanCreateRegions(Root(self)) then return false, "combat" end
    end
    if not Root(self) then
        if self:ScheduleLoad() then return true, "waiting" end
        return false, "missing"
    end
    return self.applyNow(state)
end

-- Cancels deferred work, hides this owner's surfaces and forgets the owner.
function Chrome:Release(state)
    self:ForgetPasses()
    state.preparedWindow = nil
    local header = state.headerRoot and headers[state.headerRoot]
    if header and header.owner == state then
        header.fill:Hide()
        header.rule:Hide()
        header.fillShown, header.ruleShown = false, false
        header.owner = nil
    end
    self.registry.Release(state)
end

return Chrome
