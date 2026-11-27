local _, P = ...
-- Ephemeral editor target; writes keep the active Suite profile and the
-- existing per-spec codec. Choosing another spec never activates that spec.
local Page, Suite, S = P.CDMPage, P.Suite, P.S
local Tr, Public = P.Tr, Page.Public
local ID, PAGE = Page.ID, Page.PAGE
local CDM = Suite.CDM
local PlayerSpec = Page.Spec
Page.PlayerSpec = PlayerSpec
local specs, classes, classChoices, builtForever
local characterProfile, characterRows
local EMPTY = {}

-- WoW Forever: a class's one specialization in its two talent groups, each
-- with its own lists, spell choices and bar layout (CDM.GroupSpec).
local GROUPS = { "Primary", "Secondary" }
local function AddGroups(list, primary)
    local key = CDM.GroupSpec(primary.id, 2)
    local secondary = {}
    for field, value in pairs(primary) do secondary[field] = value end
    primary.group, primary.name = 1, string.format(Tr("%s - %s"), primary.name, Tr(GROUPS[1]))
    secondary.id, secondary.group = key, 2
    secondary.name = string.format(Tr("%s - %s"), secondary.name, Tr(GROUPS[2]))
    specs[key] = secondary
    list[#list].text = primary.name
    list[#list + 1] = { value = key, text = secondary.name }
end
-- Built once per client flavor (WoW Forever adds the talent groups).
local function Catalog()
    local forever = Suite.Client.isForever == true
    if specs and builtForever == forever then return end
    builtForever, characterProfile, characterRows = forever, nil, nil
    specs, classes, classChoices = {}, {}, { { value = 0, text = Tr("Your character") } }
    for classID = 1, 13 do
        local info = C_CreatureInfo.GetClassInfo(classID)
        local name = info and info.className
        local count = C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
        if Public(name) and type(name) == "string" and Public(count) and type(count) == "number" then
            local list = {}
            classes[classID] = list
            classChoices[#classChoices + 1] = { value = classID, text = name }
            for index = 1, math.min(count, 6) do
                local id, title, _, icon = GetSpecializationInfoForClassID(classID, index)
                if Public(id) and type(id) == "number" and id > 0 and Public(title) and type(title) == "string" then
                    specs[id] = { id = id, name = title, icon = Public(icon) and icon or nil, classID = classID, className = name,
                        classFile = Public(info.classFile) and info.classFile or nil }
                    list[#list + 1] = { value = id, text = title }
                    if forever then AddGroups(list, specs[id]) end
                end
            end
        end
    end
end
function Page.Spec()
    Catalog()
    local row = specs[Page.targetSpec]
    if row then return row.id, row.name, row.icon end
    local id, name, icon = PlayerSpec()
    -- WoW Forever names the talent group.
    row = specs[id]
    if row and row.group then return id, row.name, row.icon or icon end
    return id, name, icon
end
function Page.ForeignSpec() return Page.targetSpec ~= nil and Page.targetSpec ~= PlayerSpec() end
-- Only a talent group the character can use is offered: the primary one,
-- and the secondary one of the player's own class once dual specialization
-- is learned (Blizzard's Camelot talent frame enables its tab on
-- GetNumSpecGroups() > 1).
local function OwnClass(row)
    local _, _, classID = UnitClass("player")
    return row ~= nil and Public(classID) and row.classID == classID
end
local function Usable(row)
    if row.group ~= 2 then return true end
    if not OwnClass(row) then return false end
    local count = GetNumSpecGroups()
    return Public(count) and type(count) == "number" and count > 1
end
function Page.TargetContext()
    if not Page.ForeignSpec() then return nil end
    local get, row = S.CooldownManagerEditorContext, specs[Page.targetSpec]
    return get and row and get(row.id, row.classID, row.classFile) or nil
end
function Page.ClassSpecs(out)
    Catalog()
    local row = specs[Page.Spec()]
    local list = row and classes[row.classID]
    for i = 1, list and #list or 0 do
        if Usable(specs[list[i].value]) then out[#out + 1] = list[i].value end
    end
    return out
end
-- A secondary talent group opened for the first time starts as a copy of
-- the primary one (the runtime does the same when the group turns active).
local function SeedGroup(spec)
    local lists = CDM.Codec.DecodeLists(P.Get(ID, "listsData"))
    local spells = CDM.Codec.DecodeSpells(P.Get(ID, "spellsData"))
    if not CDM.SeedGroup(lists, spells, spec) then return end
    local listsText, spellsText = CDM.Codec.EncodeLists(lists), CDM.Codec.EncodeSpells(spells)
    if listsText and spellsText then P.SetMany(ID, { listsData = listsText, spellsData = spellsText }) end
end
function Page.SelectSpec(spec)
    if P.Combat() then return false end
    Catalog()
    if spec ~= nil and (not specs[spec] or not Usable(specs[spec])) then return false end
    -- Finish text/drag/popover gestures in their old scope before changing it.
    Page.CommitFocus()
    if spec ~= nil and CDM.SpecGroup(spec) == 2 then SeedGroup(spec) end
    Page.ClosePopups()
    local ui = Page.ui
    if ui and ui.drag then Page.CancelPreviewDrag(ui.drag) end
    Page.ClearNote()
    Page.targetSpec = spec
    Page.spellSpecScope = true
    if Page.ForeignSpec() then Page.SetSimulate(false) end
    if ui and ui.grid then ui.grid.valid = false end
    if ui then ui.PaintPreview() end
    P.Refresh()
    return true
end
local function ClassValue()
    Catalog()
    local row = specs[Page.targetSpec]
    return row and row.classID or 0
end
local function SpecChoices()
    Catalog()
    local row = specs[Page.Spec()]
    return row and classes[row.classID] or EMPTY
end
local function CharacterChoices()
    Catalog()
    local profile = Suite.Database.GetActiveProfileName()
    if characterProfile == profile and characterRows then return characterRows end
    local rows = { { value = 0, text = Tr("Choose a character") } }
    local assignments = Suite.HostBridge.ProfileCharacters(profile)
    for _, entry in ipairs(assignments) do
        local row = specs[entry.spec]
        if row then
            rows[#rows + 1] = { value = entry.spec, text = string.format(Tr("%s - %s"), entry.name, row.name) }
        else
            rows[#rows + 1] = { value = entry.name, text = string.format(Tr("%s - choose a specialization"), entry.name) }
        end
    end
    characterProfile, characterRows = profile, rows
    return rows
end
-- WoW Forever: the talent groups as two large choices where Retail lists a
-- class's specializations. Choosing the group that is active in the game
-- follows it live; the other one is edited offline. A green dot marks the
-- active group; a group the character cannot use is not offered.
local function GroupClick(self)
    if P.Combat() then return end
    local row = specs[Page.Spec()]
    if not row then return end
    local key = CDM.GroupSpec(row.id, self.group)
    Page.SelectSpec(key ~= PlayerSpec() and key or nil)
end
local function GroupEnter(self)
    Page.ShowTip(self, Tr(GROUPS[self.group]), self.liveShown and Tr("Current specialization")
        or Tr("Offline view: talent choices and equipped items are not available."))
end
local function GroupLeave(self) Page.HideTip(self) end
local function BuildGroups(ui, body, x, width)
    ui.groupLabel = P.T.Font(body, "GameFontHighlightSmall", "Edit specialization", P.T.colors.text)
    ui.groupLabel:SetPoint("TOPLEFT", body, "TOPLEFT", x, 0)
    local half = math.floor((width - 6) / 2)
    ui.groups = {}
    for group = 1, 2 do
        local button = Page.Button(body, GROUPS[group], half, 26, GroupClick)
        P.HM.MarkSegmentChoice(button)
        button.group = group
        button:SetPoint("TOPLEFT", body, "TOPLEFT", x + (group - 1) * (half + 6), -20)
        button.live = button:CreateTexture(nil, "OVERLAY")
        button.live:SetSize(6, 6)
        button.live:SetPoint("TOPRIGHT", button, "TOPRIGHT", -4, -4)
        button.live:SetColorTexture(0.3, 0.85, 0.4, 1)
        button.live:Hide()
        button:HookScript("OnEnter", GroupEnter)
        button:HookScript("OnLeave", GroupLeave)
        ui.groups[group] = button
    end
end
-- Writes only what changed: the shown groups, the chosen one, the live dot.
local function PaintGroups(ui)
    local buttons = ui.groups
    if not buttons then return end
    local key = Page.Spec()
    local row = specs[key]
    local live = PlayerSpec()
    for group = 1, 2 do
        local button = buttons[group]
        local own = row and CDM.GroupSpec(row.id, group)
        local shown = own ~= nil and Usable(specs[own] or row)
        local active, dot = shown and own == key, shown and own == live and OwnClass(row)
        if button.groupShown ~= shown then
            button.groupShown = shown
            button:SetShown(shown)
        end
        if button.groupActive ~= active then
            button.groupActive = active
            button:SetActive(active)
        end
        if button.liveShown ~= dot then
            button.liveShown = dot
            button.live:SetShown(dot)
        end
    end
end
function Page.BuildTargetPicker(ui, body)
    Catalog()
    characterProfile, characterRows = nil, nil
    local width, gap = ui.width, 8
    local columns = width >= 600 and 3 or 2
    local cell = math.floor((width - (columns - 1) * gap) / columns)
    local meta = function(key) return P.Meta(PAGE, ID, key, "ephemeral", Page.PREVIEW_SECTION) end
    ui.classPicker = P.M.BindDropdownAt(ui.ctx, body, Tr("Edit class"), 0, 0, classChoices, cell,
        ClassValue, function(value)
            local first = classes[value] and classes[value][1]
            Page.SelectSpec(first and first.value or nil)
        end, meta("editor.class"))
    if Suite.Client.isForever then
        BuildGroups(ui, body, cell + gap, cell)
    else
        ui.specPicker = P.M.BindDropdownAt(ui.ctx, body, Tr("Edit specialization"), cell + gap, 0, SpecChoices, cell,
            function() return Page.Spec() or 0 end, Page.SelectSpec, meta("editor.spec"))
    end
    local x, y = columns == 3 and 2 * (cell + gap) or 0, columns == 3 and 0 or -48
    ui.characterPicker = P.M.BindDropdownAt(ui.ctx, body, Tr("Characters in this profile"), x, y, CharacterChoices, cell,
        function() return 0 end, function(value)
            if type(value) == "number" and value ~= 0 then Page.SelectSpec(value)
            elseif type(value) == "string" then Page.Note(Tr("Choose this character's class and specialization above.")) end
        end, meta("editor.character"))
    ui.pickerHeight = columns == 3 and 48 or 96
    ui.profileCaption = P.T.Font(body, "GameFontDisableSmall", "", P.T.colors.muted)
    ui.profileCaption:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -ui.pickerHeight)
    ui.profileCaption:SetWidth(width)
    ui.profileCaption:SetJustifyH("LEFT")
    ui.profileCaption:SetWordWrap(true)
end
function Page.PaintTargetPicker(ui)
    PaintGroups(ui)
    local profile = Suite.Database.GetActiveProfileName()
    local text
    if P.Get(ID, "specPositions") then
        local _, name = PlayerSpec()
        text = string.format(
            Tr("Profile: %s. Layout edits change the active specialization (%s). Colors are shared; lists and overrides use the selected spec."),
            profile, name or Tr("No specialization"))
    else
        text = string.format(Tr("Profile: %s. Layout and colors are shared; spell lists and specialization overrides use the selected spec."), profile)
    end
    if ui.profileText ~= text then
        ui.profileText = text
        Page.SetRaw(ui.profileCaption, text)
    end
    local height = math.max(28, ui.profileCaption:GetStringHeight() or 28)
    local top = ui.pickerHeight + height + 8
    if ui.stripTop ~= top then
        ui.stripTop = top
        ui.strip:ClearAllPoints()
        ui.strip:SetPoint("TOPLEFT", ui.previewBody, "TOPLEFT", 0, -top)
    end
    return top
end

local Entries, CatalogEntries = Page.Entries, Page.Catalog
function Page.Entries(slot)
    local context = Page.TargetContext()
    if Page.ForeignSpec() then return context and context.bars[slot] or {} end
    local rows = Entries(slot)
    local remember = S.CooldownManagerRememberCatalog
    if remember then remember() end
    return rows
end
function Page.Catalog(family)
    if not Page.ForeignSpec() then return CatalogEntries(family) end
    local context, rows = Page.TargetContext(), {}
    if not context then return rows end
    for _, key in ipairs(context.order) do
        local row = context.records[key]
        if row.family == family then rows[#rows + 1] = row end
    end
    return rows
end
