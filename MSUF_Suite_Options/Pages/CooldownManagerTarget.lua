local _, P = ...
-- Ephemeral editor target; writes keep the active Suite profile and the
-- existing per-spec codec. Choosing another spec never activates that spec.
local Page, Suite, S = P.CDMPage, P.Suite, P.S
local Tr, Public = P.Tr, Page.Public
local ID, PAGE = Page.ID, Page.PAGE
local PlayerSpec = Page.Spec
Page.PlayerSpec = PlayerSpec
local specs, classes, classChoices
local characterProfile, characterRows
local EMPTY = {}

local function Catalog()
    if specs then return end
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
                end
            end
        end
    end
end
function Page.Spec()
    Catalog()
    local row = specs[Page.targetSpec]
    if row then return row.id, row.name, row.icon end
    return PlayerSpec()
end
function Page.ForeignSpec() return Page.targetSpec ~= nil and Page.targetSpec ~= PlayerSpec() end
function Page.TargetContext()
    if not Page.ForeignSpec() then return nil end
    local get, row = S.CooldownManagerEditorContext, specs[Page.targetSpec]
    return get and row and get(row.id, row.classID, row.classFile) or nil
end
function Page.ClassSpecs(out)
    Catalog()
    local row = specs[Page.Spec()]
    local list = row and classes[row.classID]
    for i = 1, list and #list or 0 do out[#out + 1] = list[i].value end
    return out
end
function Page.SelectSpec(spec)
    if P.Combat() then return false end
    Catalog()
    if spec ~= nil and not specs[spec] then return false end
    -- Finish text/drag/popover gestures in their old scope before changing it.
    Page.CommitFocus()
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
    ui.specPicker = P.M.BindDropdownAt(ui.ctx, body, Tr("Edit specialization"), cell + gap, 0, SpecChoices, cell,
        function() return Page.Spec() or 0 end, Page.SelectSpec, meta("editor.spec"))
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
