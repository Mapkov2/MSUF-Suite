local _, P = ...
-- Cooldown manager page, sound picker: a pooled popup that the per-spell
-- popover (CooldownManagerPopover.lua) opens through Page.OpenSoundPicker.
local Page = P.CDMPage
local Tr = P.Tr
local EMPTY = {}
local max = math.max
local SetRaw, Media = Page.SetRaw, Page.Media
local Accent, TextColor, MutedColor = Page.Accent, Page.TextColor, Page.MutedColor
local Button, Label = Page.Button, Page.Label

------------------------------------------------------------------ sound picker
-- "None", the current value when no list below has it, Blizzard's Cooldown
-- Manager sounds by category, then the LibSharedMedia sounds. Items and rows
-- are pooled; a header shows while one of its rows matches the filter, and a
-- category name finds all of its sounds.
local SOUND_W, SOUND_H = 280, 400
local sounds

local function SoundRowClick(self)
    local item = self.item
    if not item or item.header or P.Combat() then return end
    local pick = sounds.onPick
    sounds:Hide()
    if pick then pick(item.value) end
end
local function SoundPlayClick(self)
    local item = self.row and self.row.item
    if item and not item.header then Page.PlaySound(item.value) end
end
local function SoundRowEnter(self) if self.item and not self.item.header then self.hover:Show() end end
local function SoundRowLeave(self) self.hover:Hide() end
local function SoundRow(index)
    local row = sounds.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, sounds.content)
    row:SetSize(SOUND_W - 40, 22)
    row:RegisterForClicks("LeftButtonUp")
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints(row)
    row.hover:SetColorTexture(1, 1, 1, 0.06)
    row.hover:Hide()
    row.text = Label(row, "GameFontHighlightSmall", "")
    row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text:SetWidth(SOUND_W - 100)
    row.play = Button(row, "Play", 44, 18, SoundPlayClick)
    row.play.row = row
    row.play:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row:SetScript("OnClick", SoundRowClick)
    row:SetScript("OnEnter", SoundRowEnter)
    row:SetScript("OnLeave", SoundRowLeave)
    sounds.rows[index] = row
    return row
end
local function PaintSoundRow(row, item)
    row.item = item
    SetRaw(row.text, item.text)
    local r, g, b
    if item.header == 2 then
        r, g, b = MutedColor()
    elseif item.header or item.value == sounds.current then
        r, g, b = Accent()
    else
        r, g, b = TextColor()
    end
    row.text:SetTextColor(r, g, b)
    row.play:SetShown(not item.header and item.value ~= "")
    row.hover:Hide()
end
function Page.FilterSounds()
    local query = Page.Query(sounds.search)
    local items = sounds.items
    -- Headers come before their rows: they are cleared before a row marks them.
    for i = 1, sounds.count do
        local item = items[i]
        if item.header then
            item.match = false
        else
            item.match = query == "" or item.search:find(query, 1, true) ~= nil
            if item.match then
                if item.section then item.section.match = true end
                if item.group then item.group.match = true end
            end
        end
    end
    local shown = 0
    for i = 1, sounds.count do
        local item = items[i]
        if item.match then
            shown = shown + 1
            local row = SoundRow(shown)
            PaintSoundRow(row, item)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", sounds.content, "TOPLEFT", 0, -(shown - 1) * 22)
            row:Show()
        end
    end
    for i = shown + 1, #sounds.rows do
        sounds.rows[i].item = nil
        sounds.rows[i]:Hide()
    end
    sounds.content:SetHeight(max(1, shown * 22))
end
-- header: 1 section, 2 category. Rows are found by their category name too.
local function SoundItem(n, value, text, header, section, group)
    local item = sounds.items[n]
    if not item then
        item = {}
        sounds.items[n] = item
    end
    item.value, item.text, item.header, item.section, item.group = value, text, header, section, group
    local search = type(text) == "string" and text:lower() or ""
    item.search = group and (search .. " " .. group.search) or search
    return item
end
local function KitListed(value, kits)
    local kit = kits and value:match("^kit:(%d+)$")
    return kit ~= nil and kits.names[tonumber(kit)] ~= nil
end
-- Blizzard's Cooldown Manager sounds, one header per category.
local function AddKitSounds(n, kits)
    local groups = kits and kits.groups or EMPTY
    if #groups == 0 then return n end
    n = n + 1
    local section = SoundItem(n, nil, Tr("Blizzard Cooldown Manager"), 1)
    for i = 1, #groups do
        local group = groups[i]
        n = n + 1
        local header = SoundItem(n, nil, group.title, 2, section)
        for j = 1, #group do
            n = n + 1
            SoundItem(n, group[j].value, group[j].text, nil, section, header)
        end
    end
    return n
end
local function AddMediaSounds(n)
    local lsm = Media()
    local names = lsm and lsm.List and lsm:List("sound") or EMPTY
    local section
    for i = 1, #names do
        local name = names[i]
        if type(name) == "string" and name ~= "" and #name <= 116 then
            if not section then
                n = n + 1
                section = SoundItem(n, nil, Tr("Shared media"), 1)
            end
            n = n + 1
            SoundItem(n, "lsm:" .. name, name, nil, section)
        end
    end
    return n
end
local function EnsureSounds()
    if sounds then return sounds end
    sounds = Page.NewPopup(SOUND_W, SOUND_H)
    Page.soundPicker = sounds
    sounds.items, sounds.rows, sounds.count = {}, {}, 0
    sounds.title = Label(sounds, "GameFontNormal", Tr("Choose a sound"))
    sounds.title:SetPoint("TOPLEFT", sounds, "TOPLEFT", 12, -12)
    sounds.close = Button(sounds, "x", 22, 20, function() sounds:Hide() end)
    sounds.close:SetPoint("TOPRIGHT", sounds, "TOPRIGHT", -8, -8)
    sounds.search = Page.SearchBox(sounds, SOUND_W - 28, Tr("Filter sounds"), Page.FilterSounds)
    sounds.search:SetPoint("TOPLEFT", sounds, "TOPLEFT", 14, -36)
    sounds.scroll, sounds.content = Page.ScrollArea(sounds, SOUND_W - 40)
    sounds.scroll:SetPoint("TOPLEFT", sounds, "TOPLEFT", 12, -66)
    sounds.scroll:SetPoint("BOTTOMRIGHT", sounds, "BOTTOMRIGHT", -26, 12)
    sounds.OnClosed = function(self)
        self.search:ClearFocus()
        self.onPick = nil
    end
    return sounds
end
function Page.OpenSoundPicker(anchor, current, onPick)
    if P.Combat() then return false end
    if sounds and sounds:IsShown() and sounds.anchor == anchor then
        sounds:Hide()
        return false
    end
    EnsureSounds()
    current = type(current) == "string" and current or ""
    local kits = Page.BlizzardSounds()
    local n = 1
    SoundItem(n, "", Tr("None"))
    if current ~= "" and not current:find("^lsm:") and not KitListed(current, kits) then
        n = n + 1
        SoundItem(n, current, Page.SoundLabel(current))
    end
    n = AddMediaSounds(AddKitSounds(n, kits))
    sounds.count, sounds.current, sounds.onPick = n, current, onPick
    Page.ClosePopups(Page.popover)
    Page.PlacePopup(sounds, anchor)
    if Page.popover then sounds:SetFrameLevel(Page.popover:GetFrameLevel() + 20) end
    sounds.search:SetText("")
    sounds.scroll:SetVerticalScroll(0)
    Page.FilterSounds()
    sounds:Show()
    return true
end
