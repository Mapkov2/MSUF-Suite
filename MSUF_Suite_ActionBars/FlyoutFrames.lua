local _, P = ...
local NS, S = P.NS, P.Suite
-- The secure side of the action bar flyouts (Flyouts.lua owns the data).
-- Every flyout macro runs "/click MSUFSuiteFlyouts <id>". The invisible opener
-- takes that click in its restricted handler, finds the visible Suite action
-- button that holds the macro (the one under the mouse first, else the first
-- one in bar order) and opens that flyout's own container next to it, in the
-- bar's flyout direction and at the button's size. Entries are secure action
-- buttons whose attributes change out of combat only. A closed flyout costs
-- nothing: no events, no OnUpdate, no hooks on shared code. An open flyout
-- paints its counts and cooldowns once, when it opens.
local AB = P.ActionBars
local Frames = {}
AB.FlyoutFrames = Frames

local Public, Finite = S.Public, S.Finite
local Data = NS.ActionBarFlyouts
Frames.OPENER = "MSUFSuiteFlyouts"
-- In combat the client closes the flyout after the mouse leaves.
local COMBAT_WAIT = 4
local SECURE_ATTRIBUTES = { "spell", "item", "toy", "macro" }
local TOOLTIP = AB.ENUM.TOOLTIP
local opener, openCountBox
local boxes = {}

local LAYOUT = [[
local dir=anchor:GetAttribute("flyoutDirection") or "UP"
local size=anchor:GetWidth()
if size<2 then size=36 elseif size<16 then size=16 elseif size>80 then size=80 end
size=floor(size*(box:GetAttribute("entryScale") or 1)+0.5)
if size<16 then size=16 end
local per=box:GetAttribute("perline") or 12
local step=size+4
local lines=floor((count-1)/per)+1
if lines<1 then lines=1 end
local across=count<per and count or per
if across<1 then across=1 end
local width,height=across*step+2,lines*step+2
if dir=="UP" or dir=="DOWN" then width,height=height,width end
box:SetWidth(width)
box:SetHeight(height)
box:ClearAllPoints()
if dir=="DOWN" then box:SetPoint("TOPLEFT",anchor,"BOTTOMLEFT",-3,-1)
elseif dir=="LEFT" then box:SetPoint("TOPRIGHT",anchor,"TOPLEFT",-1,3)
elseif dir=="RIGHT" then box:SetPoint("TOPLEFT",anchor,"TOPRIGHT",1,3)
else box:SetPoint("BOTTOMLEFT",anchor,"TOPLEFT",-3,1) end
for j=1,count do
    local e=box:GetFrameRef("e"..j)
    local along,side=3+((j-1)%per)*step,3+floor((j-1)/per)*step
    e:SetWidth(size)
    e:SetHeight(size)
    e:ClearAllPoints()
    if dir=="DOWN" then e:SetPoint("TOPLEFT",box,"TOPLEFT",side,-along)
    elseif dir=="LEFT" then e:SetPoint("TOPRIGHT",box,"TOPRIGHT",-along,-side)
    elseif dir=="RIGHT" then e:SetPoint("TOPLEFT",box,"TOPLEFT",along,-side)
    else e:SetPoint("BOTTOMLEFT",box,"BOTTOMLEFT",side,along) end
end
]]

local REFLOW = [[
local box=self
local anchor=self:GetFrameRef("layoutAnchor")
local count=self:GetAttribute("count") or 0
]] .. LAYOUT

-- The opener's click handler (SecureHandlerClickTemplate): the mouse button
-- name is the flyout id. Sample the actual slot's action on the click.
-- Macro owners ("m<macro index>") were prepared out of combat.
local OPEN = [[
local id=tonumber(button)
if not id or not self:GetAttribute("enabled") then return end
local open=self:GetAttribute("openid")
self:SetAttribute("openid",nil)
if open then
    local current=self:GetFrameRef("c"..open)
    if current and current:IsShown() then
        current:Hide()
        if open==id then return end
    end
end
local box=self:GetFrameRef("c"..id)
local count=box and box:GetAttribute("count") or 0
local combat=SecureCmdOptionParse("[combat] 1; 0")=="1"
if not box or (combat and count<1) then return end
local anchor,first
for i=1,self:GetAttribute("candidates") or 0 do
    local b=self:GetFrameRef("b"..i)
    if b and b:IsVisible() then
        local slot,hit=b:GetAttribute("action")
        if slot then
            local kind,macro,subtype=GetActionInfo(slot)
            hit=kind=="macro" and macro and subtype~="spell" and subtype~="item" and self:GetAttribute("m"..macro)==id
        elseif b:GetAttribute("type")=="macro" and b:GetAttribute("macro") then
            hit=self:GetAttribute("m"..b:GetAttribute("macro"))==id
        end
        if hit then
            if b:IsUnderMouse() then
                anchor=b
                break
            end
            first=first or b
        end
    end
end
anchor=anchor or first or self
]] .. LAYOUT .. [[
self:SetAttribute("openid",id)
box:Show()
if combat then
    box:RegisterAutoHide(]] .. COMBAT_WAIT .. [[)
    if anchor~=self then box:AddToAutoHide(anchor) end
else
    box:UnregisterAutoHide()
end
]]
-- An entry closes its flyout once its own click ran (the post body needs a
-- message from the pre body).
local USED_PRE = [[
if self:GetAttribute("msufFlyoutDrop") then return false end
return nil,true
]]
local USED_POST = [[control:Hide()]]

------------------------------------------------------------------ look
local function StyleFrame(button, style, size, edge)
    local config = AB.M.config
    local art = style.round or config.borderArt == AB.ENUM.BORDER_ART.BLIZZARD
    S.PlaceEdges(button.edges, button, art and 0 or edge, style.br, style.bg, style.bb, 1)
    if art and not style.skin and config.borderSize > 0 then
        if not button.frameArt then button.frameArt = S.CreateTexture(button, nil, "OVERLAY", nil, 5) end
        local extent = (size + config.borderExpansion * 2) * config.borderScale / 100
        AB.StyleButtonFrameArt(button.frameArt, button, extent, style, 1)
        button.frameArt:Show()
    elseif button.frameArt then
        button.frameArt:Hide()
    end
end

local function StyleIcon(button, style, size)
    local skin, icon = style.skin, button.icon
    -- SharedMedia backdrops belong to bars. Keep the flyout's fallback edge.
    local edge = style.border
    if not skin and style.mediaBorder then edge = 1 end
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", edge, -edge)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -edge, edge)
    local zoom = style.zoom
    icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    button.slot:SetColorTexture(style.sr, style.sg, style.sb, style.slotAlpha)
    StyleFrame(button, style, size, edge)
    if style.round or button.shapeRecord then
        if not button.shapeRecord then button.shapeRecord = { button = button, slotTexture = button.slot } end
        AB.StyleButtonShape(button.shapeRecord, style)
    end
    if skin or button.skinned then
        button.skinned = NS.HostBridge.PaintIconSkin(button, skin, size, size) or nil
    end
end

-- The secure layout sets an entry's actual width on open. Reuse its art
-- until the width or the compiled action-bar look changes.
local function Style(button)
    local style = AB.style or AB.BuildStyle()
    local width = button:GetWidth()
    local size = Finite(width) and width or button.styledWidth or 36
    if button.styleGen == AB.styleGen and button.styledWidth == size then return end
    StyleIcon(button, style, size)
    button.hover:SetColorTexture(style.ir, style.ig, style.ib, .25)
    button.press:SetColorTexture(style.ir, style.ig, style.ib, .45)
    local text = style.texts and style.texts.count
    local fontSize = math.max(8, math.min(18, math.floor(size * .32 + .5)))
    S.SetStyledFont(button.count, text and text.font or style.font or STANDARD_TEXT_FONT, fontSize,
        text and text.flags or style.flags, style.rendering, style.shadow, style.shadowOpacity, style.shadowDistance)
    button.count:SetTextColor(style.cr, style.cg, style.cb)
    button.cooldown:SetSwipeColor(style.wr, style.wg, style.wb, style.swipeAlpha)
    button.cooldown:SetHideCountdownNumbers(not AB.M.config.cooldownNumbers)
    button.styleGen, button.styledWidth = AB.styleGen, size
end

-- Cooldown of a spell (secret-safe duration object) or an item.
local function ShowCooldown(button, entry)
    local swipe = button.cooldown
    if entry.spell then
        local duration = C_Spell.GetSpellCooldownDuration(entry.spell)
        if duration then swipe:SetCooldownFromDurationObject(duration) else swipe:Clear() end
        return
    end
    if not entry.item then
        swipe:Clear()
        return
    end
    local began, length, running = C_Item.GetItemCooldown(entry.item)
    local ticking = Finite(began) and Finite(length) and Public(running) and running and running ~= 0
    if ticking and began > 0 and length > 0 then swipe:SetCooldown(began, length) else swipe:Clear() end
end

-- Counts can also change on a bag event while the flyout is visible.
-- Only a readable zero greys the icon.
local function PaintCount(button, entry)
    local empty = false
    if entry.item and entry.kind ~= "toy" then
        local count = C_Item.GetItemCount(entry.item, false, true)
        if AB.M.config.flyoutStackCounts ~= false then button.count:SetText(count) else button.count:SetText("") end
        empty = Public(count) and count == 0
    else
        button.count:SetText("")
    end
    button.icon:SetDesaturated(empty)
end

local function Paint(button)
    local entry = button.entry
    if not entry then return end
    Style(button)
    PaintCount(button, entry)
    ShowCooldown(button, entry)
end

------------------------------------------------------------------ tooltips
local function Enter(button)
    local entry, box = button.entry, button:GetParent()
    if not entry or box.tooltip == TOOLTIP.NEVER or box.tooltip == TOOLTIP.OUT_OF_COMBAT and NS.InCombat() then return end
    local tip = GameTooltip
    tip:SetOwner(button, "ANCHOR_RIGHT")
    if entry.kind == "toy" then
        tip:SetToyByItemID(entry.id)
    elseif entry.keystone and AB.FlyoutSources.KeystoneStillInSlot(entry.keystone) then
        tip:SetBagItem(entry.keystone.bag, entry.keystone.slot)
    elseif entry.item then
        tip:SetItemByID(entry.item)
    elseif entry.spell then
        tip:SetSpellByID(entry.spell)
    else
        tip:SetText(entry.name or "")
    end
    tip:Show()
end

local function Leave(button)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function Anchor(box)
    local _, relative = box:GetPoint(1)
    return relative
end

local function Reflow(box)
    local anchor = Anchor(box)
    if not anchor then return end
    SecureHandlerSetFrameRef(box, "layoutAnchor", anchor)
    SecureHandlerExecute(box, REFLOW)
end

local function EntryScale()
    return (AB.M.config.flyoutButtonScale or 100) / 100
end

-- The bar the flyout opened on decides its tooltips.
local function TooltipMode(box)
    local rec = AB.records[Anchor(box)]
    local bar = rec and rec.bar
    return bar and bar.key and AB.M.config[bar.key.Tooltip] or TOOLTIP.ALWAYS
end

local function Shown(box)
    box.tooltip = TooltipMode(box)
    for index = 1, box.count or 0 do S.Dispatch(Paint, box.entries[index]) end
    if not NS.InCombat() then
        openCountBox = box.hasItemCounts and box or nil
        AB.Flyouts.WatchOpen(box.flyoutID, box.hasItemCounts)
        AB.FlyoutEdit.FlyoutOpened(box)
    end
end

local function Hidden(box)
    if openCountBox == box then openCountBox = nil end
    AB.Flyouts.WatchOpen(nil)
    AB.FlyoutEdit.FlyoutClosed(box)
    for _, button in ipairs(box.entries) do Leave(button) end
end

function Frames.RefreshBagCounts()
    local box = openCountBox
    if not box then return end
    for position = 1, box.count do
        local button = box.entries[position]
        local entry = button.entry
        if entry.item and entry.kind ~= "toy" then PaintCount(button, entry) end
    end
end

local function Receive(button)
    AB.FlyoutEdit.DropIn(button:GetParent(), button.entry)
end

local function Drag(button)
    if NS.InCombat() or not button.entry then return end
    if not (AB.grid:GetAttribute("unlocked") or IsModifiedClick("PICKUPACTION")) then return end
    Leave(button)
    S.ActionBarFlyouts.PickupEntry(button:GetParent().flyoutID, button.entry)
end

local function BeforeClick(button, _, down)
    if down or NS.InCombat() then return end
    local kind = GetCursorInfo()
    if not Public(kind) or kind ~= nil then button:SetAttribute("msufFlyoutDrop", true) end
end

local function AfterClick(button, mouse, down)
    if down or NS.InCombat() then return end
    if button:GetAttribute("msufFlyoutDrop") then
        button:SetAttribute("msufFlyoutDrop", nil)
        Receive(button)
    elseif mouse == "LeftButton" then
        local key = button.entry and button.entry.keystone
        if not key or not AB.FlyoutSources.KeystoneStillInSlot(key) then return end
        local held = GetCursorInfo()
        if Public(held) and held == nil then C_Container.PickupContainerItem(key.bag, key.slot) end
    end
end

local function BeforeOpen(_, mouse)
    local id = tonumber(mouse)
    local box = id and boxes[id]
    if box and not box:IsShown() then AB.Flyouts.Prepare(id) end
end

------------------------------------------------------------------ frames
-- Created once, out of combat. The opener stays shown (a click needs no
-- mouse) without art or mouse input; an unanchored flyout opens above it.
local function Opener()
    if opener then return opener end
    opener = S.CreateFrame("Button", Frames.OPENER, UIParent, "SecureHandlerClickTemplate")
    opener:SetSize(1, 1)
    opener:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    opener:EnableMouse(false)
    opener:RegisterForClicks("AnyUp", "AnyDown")
    opener:SetAttribute("_onclick", OPEN)
    opener:SetScript("PreClick", BeforeOpen)
    return opener
end

local function NewBox(id)
    local box = S.CreateFrame("Frame", "MSUFSuiteFlyout" .. id, UIParent, "SecureHandlerBaseTemplate")
    box:SetFrameStrata("DIALOG")
    box:SetClampedToScreen(true)
    box:EnableMouse(false)
    box:SetAttribute("perline", Data.PER_LINE)
    box:SetAttribute("entryScale", EntryScale())
    box:SetAttribute("count", 0)
    box:Hide()
    box.entries, box.count, box.flyoutID = {}, 0, id
    box:HookScript("OnShow", Shown)
    box:HookScript("OnHide", Hidden)
    SecureHandlerSetFrameRef(Opener(), "c" .. id, box)
    boxes[id] = box
    return box
end

local function Region(button, layer, sublevel)
    return S.CreateTexture(button, nil, layer, nil, sublevel)
end

local function NewEntry(box, index)
    local button = S.CreateFrame("Button", nil, box, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton", "RightButton")
    button:SetAttribute("useOnKeyDown", false)
    button:SetSize(36, 36)
    button.slot = Region(button, "BACKGROUND")
    button.icon = Region(button, "ARTWORK")
    button.slot:SetAllPoints(button.icon)
    button.edges = { Region(button, "OVERLAY", 1), Region(button, "OVERLAY", 1), Region(button, "OVERLAY", 1),
        Region(button, "OVERLAY", 1) }
    button.hover, button.press = Region(button, "HIGHLIGHT"), Region(button, "ARTWORK", 2)
    button.hover:SetAllPoints(button)
    button.press:SetAllPoints(button)
    button:SetHighlightTexture(button.hover)
    button:SetPushedTexture(button.press)
    button.cooldown = S.CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    -- A cleared cooldown can hide its frame. Keep stack text above the swipe
    -- on an always-visible sibling, like the count on a regular action.
    local labels = S.CreateFrame("Frame", nil, button)
    labels:SetAllPoints(button)
    labels:SetFrameLevel(button.cooldown:GetFrameLevel() + 1)
    labels:EnableMouse(false)
    button.count = S.CreateFontString(labels, nil, "OVERLAY")
    button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button:SetScript("OnEnter", Enter)
    button:SetScript("OnLeave", Leave)
    button:SetScript("OnDragStart", Drag)
    button:SetScript("OnReceiveDrag", Receive)
    button:SetScript("PreClick", BeforeClick)
    button:SetScript("PostClick", AfterClick)
    SecureHandlerWrapScript(button, "OnClick", box, USED_PRE, USED_POST)
    SecureHandlerSetFrameRef(box, "e" .. index, button)
    box.entries[index] = button
    return button
end

-- Writes one entry's secure action; nil clears it.
local function Assign(button, entry)
    for _, name in ipairs(SECURE_ATTRIBUTES) do
        local value = entry and entry.attribute == name and entry.value or nil
        if button:GetAttribute(name) ~= value then button:SetAttribute(name, value) end
    end
    local kind = entry and entry.type or nil
    if button:GetAttribute("type") ~= kind then button:SetAttribute("type", kind) end
    button.entry = entry
    if entry then
        local icon = entry.icon or 134400
        if button.currentIcon ~= icon then
            button.currentIcon = icon
            button.icon:SetTexture(icon)
        end
        if not button:IsShown() then button:Show() end
    elseif button:IsShown() then
        button:Hide()
    end
end

------------------------------------------------------------------ data side API
-- Every call below runs out of combat (Flyouts.lua checks first).

-- The Suite action buttons a flyout can open from, in bar order.
function Frames.Candidates(records)
    local frame = Opener()
    for i, rec in ipairs(records) do SecureHandlerSetFrameRef(frame, "b" .. i, rec.button) end
    frame:SetAttribute("candidates", #records)
end

function Frames.SetEnabled(on)
    if opener or on then Opener():SetAttribute("enabled", on == true) end
    if not on then Frames.CloseAll() end
end

-- The flyout id whose macro a macro index holds.
function Frames.SetMacro(index, id)
    Opener():SetAttribute("m" .. index, id)
end

function Frames.LayoutMarker(rec, direction)
    local arrow = rec.flyoutMarker
    if not arrow or rec.flyoutMarkerDirection == direction then return end
    rec.flyoutMarkerDirection = direction
    Data.PositionArrow(arrow, rec.button, direction)
end

function Frames.Marker(rec, shown)
    local arrow = rec.flyoutMarker
    if not arrow and shown then
        arrow = S.CreateTexture(AB.DecorationHost(rec), nil, "OVERLAY", nil, 5)
        rec.flyoutMarker = arrow
        rec.flyoutMarkerShown = true
    elseif arrow and rec.flyoutMarkerShown ~= shown then
        rec.flyoutMarkerShown = shown
        arrow:SetShown(shown)
    end
    if shown then
        local config = AB.M.config
        local size, style = config.flyoutArrowSize or 14, config.flyoutArrowStyle or 1
        if rec.flyoutMarkerSize ~= size or rec.flyoutMarkerStyle ~= style then
            rec.flyoutMarkerSize, rec.flyoutMarkerStyle = size, style
            Data.StyleArrow(arrow, style, size)
            local direction = rec.flyoutMarkerDirection or rec.button:GetAttribute("flyoutDirection") or "UP"
            rec.flyoutMarkerDirection = direction
            Data.PositionArrow(arrow, rec.button, direction)
        end
    end
end

-- The opener owns the currently open id. A skin edit only paints the
-- visible entries, without refreshing their actions, counts or watches.
function Frames.RefreshStyle()
    local box = opener and boxes[opener:GetAttribute("openid")]
    if not box or not box:IsShown() then return end
    for index = 1, box.count do S.Dispatch(Style, box.entries[index]) end
end

function Frames.RefreshAppearance()
    local scale = EntryScale()
    for _, box in pairs(boxes) do
        local changed = box:GetAttribute("entryScale") ~= scale
        if changed then box:SetAttribute("entryScale", scale) end
        if box:IsShown() then
            if changed then Reflow(box) end
            Shown(box)
        end
    end
end

-- A flyout's shown entries (resolved by Flyouts.lua: type, attribute, value,
-- icon and the item or spell its count and cooldown follow).
function Frames.Apply(id, entries)
    local box = boxes[id] or NewBox(id)
    local oldCount = box.count
    local hasItemCounts = false
    for index, entry in ipairs(entries) do
        if entry.item and entry.kind ~= "toy" then hasItemCounts = true end
        Assign(box.entries[index] or NewEntry(box, index), entry)
    end
    for index = #entries + 1, #box.entries do Assign(box.entries[index], nil) end
    box.count, box.hasItemCounts = #entries, hasItemCounts
    if oldCount ~= box.count then box:SetAttribute("count", box.count) end
    if not box:IsShown() then return end
    if oldCount ~= box.count then Reflow(box) end
    Shown(box)
end

function Frames.Remove(id)
    local box = boxes[id]
    if box then
        box:Hide()
        Frames.Apply(id, {})
    end
end

-- Runs before the lockdown (PLAYER_REGEN_DISABLED) and on disable.
function Frames.CloseAll()
    if NS.IsCombatLocked() then return end
    for _, box in pairs(boxes) do
        if box:IsShown() then box:Hide() end
    end
end

-- Read-only views for the contract tests; nothing in the addon calls them.
AB.Diagnostics.Flyouts = {
    Opener = function() return opener end,
    Box = function(id) return boxes[id] end,
    OPEN = OPEN, USED_PRE = USED_PRE, USED_POST = USED_POST,
}
