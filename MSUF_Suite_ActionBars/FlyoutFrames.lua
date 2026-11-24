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
-- An open flyout waits this long for the mouse in combat; out of combat a
-- click anywhere else closes it, like Blizzard's spell flyouts.
local COMBAT_WAIT = 4
local SECURE_ATTRIBUTES = { "spell", "item", "toy", "macro" }
local TOOLTIP = AB.ENUM.TOOLTIP

local opener, watcher, openBox
local boxes = {}

-- The opener's click handler (SecureHandlerClickTemplate): the mouse button
-- name is the flyout id. Slot and macro owners are attributes the data side
-- writes out of combat ("s<slot>", "m<macro index>").
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
if count<1 then return end
local anchor,first
for i=1,self:GetAttribute("candidates") or 0 do
    local b=self:GetFrameRef("b"..i)
    if b and b:IsVisible() then
        local slot,hit=b:GetAttribute("action")
        if slot then
            hit=self:GetAttribute("s"..slot)==id
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
local dir=anchor:GetAttribute("flyoutDirection") or "UP"
local size=anchor~=self and anchor:GetWidth() or 36
if size<16 then size=16 elseif size>80 then size=80 end
local per=box:GetAttribute("perline") or 12
local step=size+4
local lines=floor((count-1)/per)+1
local across=count<per and count or per
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
self:SetAttribute("openid",id)
box:Show()
if SecureCmdOptionParse("[combat] 1; 0")=="1" then
    box:RegisterAutoHide(]] .. COMBAT_WAIT .. [[)
    if anchor~=self then box:AddToAutoHide(anchor) end
else
    box:UnregisterAutoHide()
end
]]
-- An entry closes its flyout once its own click ran (the post body needs a
-- message from the pre body).
local USED_PRE, USED_POST = [[return nil,true]], [[control:Hide()]]

------------------------------------------------------------------ look
local function FontSize(button)
    local width = button:GetWidth()
    if not Finite(width) then return 12 end
    return math.max(8, math.min(18, math.floor(width * .32 + .5)))
end

-- The look of the Suite buttons (Style.lua) at this entry's size; once per
-- style generation and size.
local function Style(button)
    local style = AB.style or AB.BuildStyle()
    local size = FontSize(button)
    if button.styleGen == AB.styleGen and button.fontSize == size then return end
    button.styleGen, button.fontSize = AB.styleGen, size
    local edge = math.max(style.border or 1, 1)
    button.slot:SetColorTexture(style.sr, style.sg, style.sb, math.max(style.slotAlpha, .6))
    S.PlaceEdges(button.edges, button, edge, style.br, style.bg, style.bb, 1)
    local icon = button.icon
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", edge, -edge)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -edge, edge)
    local zoom = style.zoom or .06
    icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    button.hover:SetColorTexture(style.ir, style.ig, style.ib, .25)
    button.press:SetColorTexture(style.ir, style.ig, style.ib, .45)
    local text = style.texts and style.texts.count
    S.SetStyledFont(button.count, text and text.font or style.font or STANDARD_TEXT_FONT, size,
        text and text.flags or style.flags, style.rendering, style.shadow, style.shadowOpacity, style.shadowDistance)
    button.count:SetTextColor(style.cr, style.cg, style.cb)
    button.cooldown:SetSwipeColor(style.wr, style.wg, style.wb, style.swipeAlpha)
    button.cooldown:SetHideCountdownNumbers(not AB.M.config.cooldownNumbers)
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

-- Count and cooldown, read when the flyout opens. A count goes straight to
-- the font string; only a readable zero greys the icon.
local function Paint(button)
    local entry = button.entry
    if not entry then return end
    Style(button)
    local empty = false
    if entry.item and entry.kind ~= "toy" then
        local count = C_Item.GetItemCount(entry.item, false, true)
        button.count:SetText(count)
        empty = Public(count) and count == 0
    else
        button.count:SetText("")
    end
    button.icon:SetDesaturated(empty)
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

------------------------------------------------------------------ outside clicks
-- Out of combat a mouse press outside the open flyout and its button closes
-- it. The listener exists only while a flyout is open.
local function Anchor(box)
    local _, relative = box:GetPoint(1)
    return relative
end

local function Outside()
    local box = openBox
    if not box or NS.IsCombatLocked() or box:IsMouseOver() then return end
    local anchor = Anchor(box)
    if anchor and anchor ~= opener and anchor:IsMouseOver() then return end
    box:Hide()
end

local function Watch(box)
    if not NS.Client.SupportsEvent("GLOBAL_MOUSE_DOWN") then return end
    if not watcher then
        watcher = S.CreateFrame("Frame")
        watcher:SetScript("OnEvent", Outside)
    end
    openBox = box
    watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
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
    if not NS.IsCombatLocked() then Watch(box) end
end

local function Hidden(box)
    if openBox == box then
        openBox = nil
        if watcher then watcher:UnregisterEvent("GLOBAL_MOUSE_DOWN") end
    end
    for _, button in ipairs(box.entries) do Leave(button) end
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
    return opener
end

local function NewBox(id)
    local box = S.CreateFrame("Frame", "MSUFSuiteFlyout" .. id, UIParent, "SecureHandlerBaseTemplate")
    box:SetFrameStrata("DIALOG")
    box:SetClampedToScreen(true)
    box:EnableMouse(false)
    box:SetAttribute("perline", Data.PER_LINE)
    box:Hide()
    box.entries, box.count = {}, 0
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
    button:SetAttribute("useOnKeyDown", false)
    button:SetSize(36, 36)
    button.slot = Region(button, "BACKGROUND")
    button.slot:SetAllPoints(button)
    button.icon = Region(button, "ARTWORK")
    button.edges = { Region(button, "OVERLAY", 1), Region(button, "OVERLAY", 1), Region(button, "OVERLAY", 1),
        Region(button, "OVERLAY", 1) }
    button.hover, button.press = Region(button, "HIGHLIGHT"), Region(button, "ARTWORK", 2)
    button.hover:SetAllPoints(button)
    button.press:SetAllPoints(button)
    button:SetHighlightTexture(button.hover)
    button:SetPushedTexture(button.press)
    button.cooldown = S.CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.count = S.CreateFontString(button.cooldown, nil, "OVERLAY")
    button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button:SetScript("OnEnter", Enter)
    button:SetScript("OnLeave", Leave)
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
        button.icon:SetTexture(entry.icon or 134400)
        button:Show()
    else
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

-- The flyout id whose macro an action slot or a macro index holds.
function Frames.SetSlot(slot, id)
    Opener():SetAttribute("s" .. slot, id)
end

function Frames.SetMacro(index, id)
    Opener():SetAttribute("m" .. index, id)
end

-- A flyout's shown entries (resolved by Flyouts.lua: type, attribute, value,
-- icon and the item or spell its count and cooldown follow).
function Frames.Apply(id, entries)
    local box = boxes[id] or NewBox(id)
    if box:IsShown() then box:Hide() end
    for index, entry in ipairs(entries) do Assign(box.entries[index] or NewEntry(box, index), entry) end
    for index = #entries + 1, #box.entries do Assign(box.entries[index], nil) end
    box.count = #entries
    box:SetAttribute("count", #entries)
end

function Frames.Remove(id)
    if boxes[id] then Frames.Apply(id, {}) end
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
