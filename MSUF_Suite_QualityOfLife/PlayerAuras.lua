local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local cleanup, trayHooked
-- Side tables; nothing is written onto Blizzard frames.
--   saved    region -> the readable originals of what this module writes on it
--   borders  button -> the module's outline frame
--   hooked   frame  -> true once its native layout calls are hooked
--   debuffs  frame  -> true for the frame that takes the debuff row offset
--   laid     frame  -> { n, anchored, framed, restyle, [slot] = button }: the
--                       first n slots were placed since the frame's last native
--                       layout; anchored: the container's anchor and size
--                       hold; framed: the frame sits beside the minimap
--   styled   button -> the style generation its artwork and fonts carry
--   looks    parent -> MSUF's icon skin look of the buttons it holds (an aura
--                       frame's AuraContainer and the frame itself; nil: none)
--   skinned  button -> { look, w, h } while that skin draws on it
--   lifted   region -> the Duration's draw layer before a skin lifted it
local saved, borders, hooked, debuffs, laid, styled = {}, {}, {}, {}, {}, {}
local looks, skinned, lifted = {}, {}, {}
local generation, fontPath = 0, nil
local unpack, select, floor, ceil, max = unpack, select, math.floor, math.ceil, math.max
-- The client's secret test (Platform.lua), called directly on the aura path.
local IsSecret = NS.IsSecret

-- Blizzard_BuffFrame (live 12.1.5 and Forever 1.60.1): retain native buttons,
-- aura updates, cancel clicks, private anchors and duration timers.
-- Only public, configured geometry and artwork are changed here.
--
-- Cadence (BuffFrame.lua): every player UNIT_AURA that adds, removes or
-- updates an aura runs both frames' Update -> UpdateAuraButtons (283-295), and
-- DebuffFrame's UpdateAuraButtons ends in UpdateGridLayout (751-754).
-- UpdateGridLayout re-scales, re-sizes and re-anchors each button it lays
-- out, its Icon and its Duration (147-163) and the AuraContainer.
-- UpdateAuraButtons only shows, hides and refills buttons: SetTexture keeps
-- the TexCoord (Blizzard_CustomAuraButton.lua:501 resets it explicitly), and
-- SetAtlas ignores the atlas size on the native borders. So a button is placed
-- when its slot is new since the frame's last native layout, and its artwork
-- and fonts are painted once per style generation. A refresh that keeps the
-- shown buttons costs one IsShown per button and writes nothing.

-- A secret value is not recorded: SetPoint, SetSize, SetScale, SetFont and
-- SetShadow* refuse one from addon code, and SetAlpha, SetTexCoord and
-- SetTextColor would mark the region's aspect secret. Such a value keeps its
-- current state when the module stops.
local function Readable(...)
    local values = { n = select("#", ...), ... }
    for index = 1, values.n do
        if IsSecret(values[index]) then return nil end
    end
    return values
end

-- What the module writes on each kind of region, and so all that Remember
-- reads and Restore puts back. A FontString's size, a button's alpha (the
-- warning flash) and the frame's alpha (Edit Mode opacity) stay Blizzard's.
local BUTTON = { points = true, size = true, scale = true }
-- Aura button icons are Textures (BuffFrameTemplates.xml:8); a private aura
-- anchor's Icon frame is never written.
local ICON = { points = true, coords = true }
local TEXT = { points = true, alpha = true, text = true }
local BORDER = { size = true }
local FRAME = { points = true }
local CONTAINER = { points = true, size = true }

local function Remember(region, aspects)
    if not region or saved[region] then return end
    local state = {}
    if aspects.points then
        state.points = {}
        for index = 1, region:GetNumPoints() do
            state.points[index] = Readable(region:GetPoint(index))
            if not state.points[index] then
                state.points = nil
                break
            end
        end
    end
    if aspects.size then state.size = Readable(region:GetWidth(), region:GetHeight()) end
    if aspects.scale then state.scale = Readable(region:GetScale()) end
    if aspects.alpha then state.alpha = Readable(region:GetAlpha()) end
    if aspects.coords then state.coords = Readable(region:GetTexCoord()) end
    if aspects.text then
        state.font = Readable(region:GetFont())
        state.color = Readable(region:GetTextColor())
        state.shadow = Readable(region:GetShadowColor())
        state.shadowOffset = Readable(region:GetShadowOffset())
    end
    saved[region] = state
end

local function Put(region, setter, values)
    if values then region[setter](region, unpack(values, 1, values.n)) end
end

local function Restore()
    for region, state in pairs(saved) do
        if state.points then
            region:ClearAllPoints()
            for _, point in ipairs(state.points) do Put(region, "SetPoint", point) end
        end
        Put(region, "SetSize", state.size)
        Put(region, "SetScale", state.scale)
        Put(region, "SetAlpha", state.alpha)
        Put(region, "SetTexCoord", state.coords)
        Put(region, "SetFont", state.font)
        Put(region, "SetTextColor", state.color)
        Put(region, "SetShadowColor", state.shadow)
        Put(region, "SetShadowOffset", state.shadowOffset)
        saved[region] = nil
    end
    for _, border in pairs(borders) do border:Hide() end
    for button in pairs(skinned) do
        NS.HostBridge.PaintIconSkin(button, nil)
        skinned[button] = nil
    end
    for region, layer in pairs(lifted) do
        if layer then Put(region, "SetDrawLayer", layer) end
        lifted[region] = nil
    end
end

-- Forget every placement and style: the next sync of each frame paints all.
local function Invalidate()
    generation = generation + 1
    for _, list in pairs(laid) do
        list.n, list.anchored, list.framed = 0, false, false
    end
end

-- In combat a protected frame or button waits: S.Queue re-applies the module
-- after it. The slots from `slot` on stay unplaced until then.
local function Refused(region, list, slot)
    local protected = region:IsProtected()
    if not (IsSecret(protected) or protected) then return false end
    S.Queue("playerAuras")
    list.n = slot - 1
    return true
end

local function Border(button, icon, c)
    local border = borders[button]
    if not border then
        border = S.CreateFrame("Frame", nil, button)
        border:EnableMouse(false)
        border.edges = {}
        for index = 1, 4 do border.edges[index] = S.CreateTexture(border, nil, "OVERLAY") end
        borders[button] = border
    end
    border:SetAllPoints(icon)
    local level = button:GetFrameLevel()
    if not IsSecret(level) then border:SetFrameLevel(level + 1) end
    local r, g, b = S.RGB(c.borderColor)
    S.PlaceEdges(border.edges, border, c.borderSize, r, g, b, 1)
    border:SetShown(c.borderSize > 0)
end

-- The template keeps Duration on BACKGROUND, under a skin's layers: while a
-- skin draws it moves to OVERLAY (the Count's layer). Its own layer, read once,
-- comes back when the skin goes or the module stops.
local function Lift(region, on)
    if not (region and region.SetDrawLayer) then return end
    if on then
        if lifted[region] == nil then lifted[region] = Readable(region:GetDrawLayer()) or false end
        region:SetDrawLayer("OVERLAY", 0)
    elseif lifted[region] ~= nil then
        if lifted[region] then Put(region, "SetDrawLayer", lifted[region]) end
        lifted[region] = nil
    end
end

local function Font(region, c)
    if not (region and region.SetFont) then return end
    Remember(region, TEXT)
    region:SetFont(fontPath, c.fontSize, "OUTLINE")
    region:SetTextColor(1, 1, 1, 1)
    region:SetShadowColor(0, 0, 0, 1)
    region:SetShadowOffset(1, -1)
end

local function Pin(region, button, point)
    if not (region and region.SetFont) then return end
    Remember(region, TEXT)
    region:ClearAllPoints()
    region:SetPoint(point, button, point, point == "BOTTOMRIGHT" and -2 or 2, 1)
end

local function NativeBorder(region, c)
    if not region then return end
    Remember(region, BORDER)
    region:SetSize(c.iconWidth + 2, c.iconHeight + 2)
end

-- Native code keeps all of this until the configuration or Edit Mode changes.
-- (zhTW alone: AuraButtonMixin:OnUpdate sets the Duration font object every
-- frame for long auras, BuffFrame.lua:963-973.)
local function Style(button, icon, c)
    styled[button] = generation
    if icon.SetTexCoord then
        local x, y = .43, .43
        if c.iconWidth > c.iconHeight then
            y = y * c.iconHeight / c.iconWidth
        else
            x = x * c.iconWidth / c.iconHeight
        end
        icon:SetTexCoord(.5 - x, .5 + x, .5 - y, .5 + y)
        Border(button, icon, c)
    end
    NativeBorder(button.DebuffBorder, c)
    NativeBorder(button.TempEnchantBorder, c)
    Font(button.Count, c)
    Font(button.Duration, c)
    Pin(button.Count, button, "BOTTOMRIGHT")
    if button.Duration and button.Duration.SetFont then button.Duration:SetAlpha(c.showDuration and 1 or 0) end
end

-- MSUF's icon skin on a button Style just styled, run in Style's stead
-- (Place's `style`, chosen by ResolveLooks on the settings path) only while
-- a row has a look: the aura updates of a player without skins run Style
-- alone. Once per style generation and when Blizzard shows a button the pool
-- hands out, also in combat, so every button shows the same look: its row's,
-- found by the button's parent (that frame's AuraContainer). Its layers are
-- textures of the button around its Icon (ARTWORK 5-7, gloss OVERLAY -1: the
-- debuff type border and Count, OVERLAY, stay above); it replaces the
-- module's outline while it draws. Style made that outline with the icon's
-- texture coordinates: without it the icon is not styled and takes no skin.
local style = Style
local function StyleSkinned(button, icon, c)
    Style(button, icon, c)
    local border = borders[button]
    if not border then return end
    local look, shown = looks[button:GetParent()], skinned[button]
    if not (look or shown) then return end
    -- The look it shows at this size (a restyle of the same buttons, also an
    -- adoption in combat) is kept: Style only showed the outline again.
    if shown and shown.look == look and shown.w == c.iconWidth and shown.h == c.iconHeight then
        border:Hide()
        return
    end
    local skin = NS.HostBridge.PaintIconSkin(button, look, c.iconWidth, c.iconHeight, icon)
    skinned[button] = skin and { look = look, w = c.iconWidth, h = c.iconHeight } or nil
    Lift(button.Duration, skin)
    if skin then border:Hide() end
end

-- Native layout owns these: UpdateGridLayout resets them on each laid-out button.
local function Place(button, icon, slot, container, c)
    if not saved[button] then Remember(button, BUTTON) end
    local col, row = (slot - 1) % c.perRow, floor((slot - 1) / c.perRow)
    button:SetScale(1)
    button:SetSize(c.iconWidth, c.iconHeight)
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", container, "TOPRIGHT", -col * (c.iconWidth + c.spacing),
        -row * (c.iconHeight + c.rowSpacing))
    -- Private aura artwork is registered with fixed native dimensions.
    -- Keep its native IconInfo; only place its public anchor in the row.
    if button.isAuraAnchor then return end
    if not saved[icon] then Remember(icon, ICON) end
    icon:ClearAllPoints()
    icon:SetAllPoints(button)
    Pin(button.Duration, button, "BOTTOMLEFT")
    if styled[button] ~= generation then style(button, icon, c) end
end

-- The container that holds the rows, and the frame beside the minimap. The
-- frame is an Edit Mode system whose SetPoint and ClearAllPoints are Lua
-- overrides that mark Edit Mode's anchors dirty (EditModeSystemTemplates.lua
-- 9-17, 147-156), so it moves only after Blizzard moved it.
local function Anchor(frame, list, count)
    local c, container = M.config, frame.AuraContainer
    if not list.framed then
        Remember(frame, FRAME)
        frame:ClearAllPoints()
        frame:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", c.x, c.y - (debuffs[frame] and c.debuffOffset or 0))
        list.framed = true
    end
    Remember(container, CONTAINER)
    container:ClearAllPoints()
    container:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    container:SetSize(c.perRow * (c.iconWidth + c.spacing) - c.spacing,
        max(1, ceil(count / c.perRow)) * (c.iconHeight + c.rowSpacing) - c.rowSpacing)
    list.anchored = true
end

-- The shown buttons in slot order, the native consolidation button first.
-- Only a slot whose button differs from the last placement is written; the
-- combat state is read once, at the first write.
local function Sync(frame)
    if not (M.active and frame and frame.AuraContainer and frame.auraFrames) then return end
    local list = laid[frame]
    if not list then
        list = { n = 0, anchored = false, framed = false, restyle = false }
        laid[frame] = list
    end
    local valid, slot, seated, locked = list.n, 0, false, nil
    if list.restyle then
        generation, valid, list.restyle = generation + 1, 0, false
        list.anchored, list.framed = false, false
    end
    local buttons, collect = frame.auraFrames, frame.ConsolidatedBuffs
    for index = collect and 0 or 1, #buttons do
        local button = index == 0 and collect or buttons[index]
        local shown = button:IsShown()
        if not IsSecret(shown) and shown then
            slot = slot + 1
            if slot > valid or list[slot] ~= button then
                if locked == nil then
                    locked = NS.IsCombatLocked()
                    if locked and Refused(frame, list, slot) then return end
                end
                local icon = button.Icon
                if icon then
                    if locked and Refused(button, list, slot) then return end
                    Place(button, icon, slot, frame.AuraContainer, M.config)
                end
                list[slot], seated = button, true
            end
        end
    end
    list.n = slot
    if not (seated or slot ~= valid or not list.anchored) then return end
    if locked == nil then
        locked = NS.IsCombatLocked()
        if locked and Refused(frame, list, slot + 1) then return end
    end
    Anchor(frame, list, slot)
end

-- UpdateGridLayout re-scaled, re-sized and re-anchored what it laid out and
-- the container; the frame itself stays where it was.
local function Relayout(frame)
    local list = laid[frame]
    if list then
        list.n, list.anchored = 0, false
    end
    Sync(frame)
end

-- Edit Mode's first refill resets every Duration font object (BuffFrame.lua:374,
-- after SetIsEditing in EditModeManager.lua:2290-2300); the sync that follows
-- it paints the styles again.
local function Restyle(frame)
    local list = laid[frame]
    if list then list.restyle = true end
end

-- Blizzard placed the frame itself: Edit Mode applies a layout or a reset
-- (ApplySystemAnchor, EditModeSystemTemplates.lua:350; UpdateSystem lays the
-- auras out afterwards, 1945-1948).
local function Moved(frame)
    local list = laid[frame]
    if list then
        list.anchored, list.framed = false, false
    end
    Sync(frame)
end

-- StatusTrayManager (LoadFirst on Retail and Forever) moves a default-placed
-- BuffFrame below the help and survey trays without either (StatusTrayManager
-- .lua:36-43): after Edit Mode lays out its systems (EditModeManager.lua
-- 187-191) and when a tray shows.
local function Reanchor()
    for frame in pairs(laid) do Moved(frame) end
end

-- DebuffFrame's UpdateAuraButtons ends in UpdateGridLayout, so its layout hook
-- already sees every refill; a second hook would sync it twice per aura event.
local function Hook(frame, debuff)
    if not frame or hooked[frame] or not frame.UpdateGridLayout then return end
    hooked[frame] = true
    debuffs[frame] = debuff
    hooksecurefunc(frame, "UpdateGridLayout", Relayout)
    local mixin = _G.DebuffFrameMixin
    if frame.UpdateAuraButtons and not (mixin and frame.UpdateAuraButtons == mixin.UpdateAuraButtons) then
        hooksecurefunc(frame, "UpdateAuraButtons", Sync)
    end
    if frame.SetIsEditing then hooksecurefunc(frame, "SetIsEditing", Restyle) end
    if frame.ApplySystemAnchor then hooksecurefunc(frame, "ApplySystemAnchor", Moved) end
end

-- The square look of a frame's Icon Skins page row, for the buttons its
-- AuraContainer holds and those on the frame itself (BuffFrame's consolidated
-- buffs button, Sync's slot 0). HostBridge keeps one table per look until
-- MSUF reports a change: WatchIconSkins refreshes then.
local function SetLook(name, choice)
    local frame = _G[name]
    if not frame then return end
    local look = NS.HostBridge.IconSkinLook(choice)
    looks[frame] = look
    local container = frame.AuraContainer
    if container then looks[container] = look end
end

-- The rows' looks and the style they need, on the settings path (Enable,
-- Refresh: also MSUF's reports, WatchIconSkins): an adoption (a zone, the
-- combat end, an addon loading, also in combat) stays Suite main's code.
local function ResolveLooks()
    local c = M.config
    SetLook("BuffFrame", c.buffSkin)
    SetLook("DebuffFrame", c.debuffSkin)
    -- A button whose row has no look any more drops its skin now, a hidden one
    -- too (an adoption restyles only shown buttons), so No skin on both rows
    -- selects Style at once.
    for button in pairs(skinned) do
        if not looks[button:GetParent()] then
            NS.HostBridge.PaintIconSkin(button, nil)
            skinned[button] = nil
            Lift(button.Duration, false)
        end
    end
    style = next(looks) and StyleSkinned or Style
end

local function Adopt()
    local buffs, debuffFrame = _G.BuffFrame, _G.DebuffFrame
    fontPath = S.ResolveFont(M.config.font) or NS.MSUFMedia.font
    Invalidate()
    Hook(buffs, false)
    Hook(debuffFrame, true)
    Sync(buffs)
    Sync(debuffFrame)
    if not trayHooked then
        hooksecurefunc(StatusTrayManager, "UpdateTrayAndBuffFrameLayout", Reanchor)
        trayHooked = true
    end
end

local function FinishCleanup()
    if NS.IsCombatLocked() then return end
    if cleanup then cleanup:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    Restore()
    for frame in pairs(hooked) do frame:UpdateGridLayout() end
    -- The skin-only piece paints the buttons again (if it runs).
    P.PlayerAuraSkins.Yield(false)
end

function M:Enable()
    if cleanup then cleanup:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    self.active = true
    -- The skin-only piece (PlayerAuraSkins.lua) lets go of the buttons first.
    P.PlayerAuraSkins.Yield(true)
    -- MSUF's default icon skin changed: Refresh resolves the looks again.
    NS.HostBridge.WatchIconSkins("playerAuras", true)
    self.context:Event("PLAYER_ENTERING_WORLD", Adopt)
    self.context:Event("PLAYER_REGEN_ENABLED", Adopt)
    self.context:Event("ADDON_LOADED", Adopt)
    ResolveLooks()
    Adopt()
end

function M:Refresh()
    ResolveLooks()
    Adopt()
end

function M:Disable()
    self.active = false
    NS.HostBridge.WatchIconSkins("playerAuras", false)
    if NS.IsCombatLocked() then
        if not cleanup then
            cleanup = S.CreateFrame("Frame")
            cleanup:SetScript("OnEvent", FinishCleanup)
        end
        cleanup:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        FinishCleanup()
    end
end

S.Install("playerAuras", M)
